import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import '../app/app_version.dart';
import '../models/capture_view.dart';
import '../models/manual_count.dart';
import '../models/reconstruction_result.dart';
import '../models/scan_session.dart';
import 'device_auth.dart';
import 'ipv4_first.dart';
import 'reconstruction_photos.dart';
import 'scan_failure.dart';

/// Waits between retries; tests pass one that returns at once.
typedef Delay = Future<void> Function(Duration duration);

class ApiClient {
  /// [dio] or [adapter] replace the shared connection (tests drive the client
  /// through a fake adapter); [deviceAuth] replaces the phone's credential;
  /// [delay] and [now] replace the real pauses and clock.
  ApiClient(
    String baseUrl, {
    Dio? dio,
    HttpClientAdapter? adapter,
    DeviceAuth? deviceAuth,
    Delay? delay,
    DateTime Function()? now,
  }) : _base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), ''),
       _auth = deviceAuth ?? DeviceAuth.shared,
       _delay = delay ?? _sleep,
       _now = now ?? DateTime.now,
       _dio =
           dio ??
           (adapter != null || deviceAuth != null
               ? buildDio(adapter: adapter, deviceAuth: deviceAuth)
               : shared);

  final String _base;
  final DeviceAuth _auth;
  final Delay _delay;
  final DateTime Function() _now;
  final Dio _dio;
  CancelToken? _cancelToken;
  bool _closed = false;

  static Future<void> _sleep(Duration duration) =>
      Future<void>.delayed(duration);

  static Dio? _shared;

  /// One Dio for the whole app: one connection pool behind the IPv4-first
  /// connector, and the device credential on every request to a server that
  /// asks for it. Screens used to build a Dio each, so nothing was shared.
  static Dio get shared => _shared ??= buildDio();

  static Dio buildDio({HttpClientAdapter? adapter, DeviceAuth? deviceAuth}) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        // Three photos (about 1.5 MB) over a mobile link that drops 40% of
        // its packets (measured on Jio LTE to workers.dev, 2026-10-12) can
        // take well over a minute; the old 45 s cut such uploads off.
        sendTimeout: const Duration(seconds: 150),
        receiveTimeout: const Duration(seconds: 90),
      ),
    );
    dio.httpClientAdapter =
        adapter ??
        IOHttpClientAdapter(
          createHttpClient: () => ipv4FirstHttpClient(onAttempt: _logAttempt),
        );
    dio.interceptors.add(DeviceAuthInterceptor(deviceAuth ?? DeviceAuth.shared));
    return dio;
  }

  /// One line per new connection (family, address, TCP and TLS times) for
  /// `adb logcat`. Addresses and timings only; never headers or bodies.
  static void _logAttempt(DialAttempt attempt) =>
      debugPrint('EGGCONN ${jsonEncode(attempt.toJson())}');

  Uri get _uri => Uri.parse(_base);

  String _url(String path) => '$_base$path';

  /// Pauses between retries: short, then longer, so a dropped TLS handshake
  /// (the common failure on this link) gets a fresh connection each time.
  static const List<Duration> _backoff = [
    Duration(milliseconds: 800),
    Duration(seconds: 2),
    Duration(seconds: 5),
  ];

  /// Four tries with growing pauses before an upload counts as failed.
  static const _maxPosts = 4;

  /// How long a sent scan's result is asked for before it counts as lost:
  /// the Worker's own worst case is about 3 minutes (182 s of inference
  /// retries plus rim verification). Measured on the clock, requests
  /// included: on a link that drops every request, 14 of them used to add
  /// 2.5 to 5 minutes to the pauses alone.
  static const _resultBudget = Duration(minutes: 3);

  /// One request for the result never waits longer than this for its answer.
  static const _resultReceive = Duration(seconds: 20);
  static const List<Duration> _pollSteps = [
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 8),
    Duration(seconds: 13),
    Duration(seconds: 20),
  ];

  /// Three quick tries: one dropped handshake must not read as "offline".
  Future<bool> health() async {
    try {
      return (await serverInfo(refresh: true)).ok;
    } on DioException {
      return false;
    }
  }

  /// What the server advertises (/health), remembered for two minutes so a
  /// retry does not spend three more round trips on a lossy link.
  Future<ServerInfo> serverInfo({bool refresh = false}) async {
    final cached = refresh
        ? null
        : _auth.serverInfo(_uri, maxAge: const Duration(minutes: 2));
    if (cached != null) return cached;
    final response = await _retrying(
      () => _dio.get<Map<String, dynamic>>(
        _url('/health'),
        options: Options(receiveTimeout: const Duration(seconds: 12)),
      ),
    );
    _auth.noteHealth(_uri, response.data);
    return _auth.serverInfo(_uri)!;
  }

  /// What went wrong, in the operator's words. Server-provided messages win.
  static String describe(DioException error) {
    final message = _serverMessage(error);
    if (message != null) return message;
    final status = error.response?.statusCode;
    if (status != null) {
      return 'The server answered with error $status. Try again; if it repeats, '
          'the server needs attention.';
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout || DioExceptionType.connectionError =>
        'The phone could not reach the server (connection dropped). The mobile '
            'signal to the server is unstable here: move to better signal or '
            'Wi-Fi and try again.',
      DioExceptionType.sendTimeout =>
        'The data could not be sent in time (weak or unstable signal). Move '
            'to better signal or Wi-Fi and try again.',
      DioExceptionType.receiveTimeout =>
        'The server did not answer in time. Try again.',
      DioExceptionType.cancel => 'Cancelled.',
      _ => switch (error.error) {
        SocketException() || HandshakeException() || HttpException() =>
          'The connection to the server dropped. Move to better signal or '
              'Wi-Fi and try again.',
        _ => error.message ?? 'Network request failed.',
      },
    };
  }

  static bool supportsCellIdentity(Map<String, dynamic>? data) =>
      data?['status'] == 'ok' && data?['scan_contract'] == 'cell_identity_v1';

  static bool supportsModelScan(Map<String, dynamic>? data) =>
      data?['status'] == 'ok' &&
      data?['scan_contracts'] is List &&
      (data!['scan_contracts'] as List).contains('model_spatial_v1');

  Future<ServerInfo> requireModelScan() async {
    var info = await serverInfo();
    if (!info.ok || !info.modelScan) info = await serverInfo(refresh: true);
    if (!info.ok || !info.modelScan) {
      throw const FormatException(
        'The server needs the optional-marker scan update. No images were uploaded. Update the backend and retry.',
      );
    }
    return info;
  }

  /// Registers this phone if the server asks for device credentials, then
  /// reads its status. Never throws: problems come back in [DeviceState].
  Future<DeviceState> checkDevice() async {
    final ServerInfo info;
    try {
      info = await serverInfo();
    } on DioException {
      return _auth.stateFor(_uri) ??
          const DeviceState(
            authRequired: false,
            problem: 'The phone could not reach the server.',
          );
    }
    if (!info.deviceAuth) return _note(DeviceState.open);
    final DeviceIdentity identity;
    try {
      identity = await _auth.identity();
    } on Object {
      return _note(
        const DeviceState(
          authRequired: true,
          problem:
              'This phone could not read its device key from secure storage.',
        ),
      );
    }
    try {
      if (!_auth.isRegistered(_uri)) await _register(identity);
      try {
        return _note(await _me(identity));
      } on DioException catch (error) {
        if (_code(error) != 'device_auth_failed') rethrow;
        // The server no longer knows this id (its records were reset):
        // registering again is idempotent and puts it back as pending.
        await _register(identity);
        return _note(await _me(identity));
      }
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == null) {
        // No answer is not a refusal: the server's last answer stands (it is
        // not overwritten), and without one the scan may still start. An
        // upload the server refuses gets its own 401/403 and keeps its photos.
        final known = _auth.stateFor(_uri);
        if (known != null &&
            known.authRequired &&
            known.status != DeviceStatus.unknown) {
          return known;
        }
        return _note(
          DeviceState(
            authRequired: true,
            displayCode: identity.displayCode,
            unreachable: true,
            problem:
                'The phone could not reach the server to check its approval. '
                'Scans can still start; the server checks the phone when the '
                'photos are sent.',
          ),
        );
      }
      final code = _code(error);
      return _note(
        DeviceState(
          authRequired: true,
          status: switch (code) {
            'device_pending' => DeviceStatus.pending,
            'device_revoked' => DeviceStatus.revoked,
            _ => DeviceStatus.unknown,
          },
          displayCode: identity.displayCode,
          problem: switch (code) {
            'device_exists' =>
              'The server already has this device id with a different key. '
                  'Clear the app data to make a new device id, then ask the '
                  'admin to approve it.',
            _ =>
              'The server refused the device check '
                  '(${_serverMessage(error) ?? 'error $status'}).',
          },
        ),
      );
    }
  }

  DeviceState _note(DeviceState state) {
    _auth.noteState(_uri, state);
    return state;
  }

  /// Create-only on the server; the same id and secret again is a no-op.
  Future<void> _register(DeviceIdentity identity) async {
    await _retrying(
      () => _dio.post<Map<String, dynamic>>(
        _url('/v1/devices'),
        data: {
          'device_id': identity.deviceId,
          'secret': identity.secret,
          'app_version': kAppVersion,
        },
        options: Options(
          contentType: 'application/json',
          receiveTimeout: const Duration(seconds: 20),
        ),
      ),
    );
    _auth.markRegistered(_uri);
  }

  Future<DeviceState> _me(DeviceIdentity identity) async {
    final response = await _retrying(
      () => _dio.get<Map<String, dynamic>>(
        _url('/v1/devices/me'),
        options: Options(receiveTimeout: const Duration(seconds: 20)),
      ),
    );
    final data = response.data;
    final code = data?['display_code'];
    return DeviceState(
      authRequired: true,
      status: DeviceState.parseStatus(data?['status']),
      displayCode: code is String && code.isNotEmpty
          ? code
          : identity.displayCode,
    );
  }

  Future<ReconstructionResult> reconstruct(PreparedPair pair) async {
    final health = await _dio.get<Map<String, dynamic>>(_url('/health'));
    _auth.noteHealth(_uri, health.data);
    if (health.data?['scan_contracts'] is! List ||
        !(health.data!['scan_contracts'] as List).contains('reconstruct_v1')) {
      throw const FormatException(
        'This server does not support 3D reconstruction. Select the staging server in Settings.',
      );
    }
    final form = FormData.fromMap({
      'client_processing': jsonEncode(pair.metadata),
    });
    for (var i = 0; i < 2; i++) {
      final signature = await File(pair.paths[i]).openRead(0, 8).first;
      final png = signature.first == 137;
      form.files.add(
        MapEntry(
          i == 0 ? 'first' : 'second',
          await MultipartFile.fromFile(
            pair.paths[i],
            filename: '${i == 0 ? 'first' : 'second'}.${png ? 'png' : 'jpg'}',
            contentType: DioMediaType.parse(png ? 'image/png' : 'image/jpeg'),
          ),
        ),
      );
    }
    _cancelToken = CancelToken();
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _url('/v1/reconstruct'),
        data: form,
        cancelToken: _cancelToken,
        options: Options(
          sendTimeout: const Duration(seconds: 120),
          receiveTimeout: const Duration(seconds: 150),
        ),
      );
      if (response.data == null) {
        throw const FormatException('Empty 3D response');
      }
      return ReconstructionResult.fromJson(response.data!);
    } on DioException catch (error) {
      final data = error.response?.data;
      if (data is Map && data['detail'] is Map) {
        throw FormatException(data['detail']['message'].toString());
      }
      rethrow;
    }
  }

  /// Sends one scan (one scan id = one triplet) and returns the server's 200
  /// body, unparsed, so the caller can keep it before reading it. Throws
  /// [ScanFailure].
  ///
  /// On a server with stored results (`scan_jobs_v1`) a scan whose photos
  /// were fully sent is never uploaded again blindly: the app asks for the
  /// result and uploads again only when the server has none (404) or its job
  /// failed (409). [askResultFirst] does that before the first upload (resume,
  /// or a retry after the photos were sent); with [bodySentBefore] false (no
  /// earlier upload of this scan finished sending) it asks once and uploads
  /// if that question gets no answer. [onBodySent] fires once the whole
  /// request body has been handed to the connection.
  Future<Map<String, dynamic>> submitScan(
    ScanSession session, {
    required void Function(int sent, int total) onProgress,
    void Function(ScanStage stage)? onStage,
    void Function()? onBodySent,
    bool askResultFirst = false,
    bool bodySentBefore = true,
  }) async {
    if (!session.isComplete) {
      throw StateError('LEFT, RIGHT, and STRAIGHT are required');
    }
    _cancelToken ??= CancelToken();
    final ServerInfo info;
    try {
      info = await requireModelScan();
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      throw ScanFailure(
        ScanFailureKind.uploadFailed,
        status == null
            ? 'The phone could not reach the server, so no photos were sent. '
                  'They are kept on this phone. Move to better signal or Wi-Fi '
                  'and tap RETRY UPLOAD.'
            : 'The server is not ready (error $status), so no photos were '
                  'sent. They are kept on this phone; tap RETRY UPLOAD.',
        status: status,
      );
    } on FormatException catch (error) {
      // Nothing was sent, and a server update makes the same photos work:
      // the scan is kept for a retry rather than rejected.
      throw ScanFailure(ScanFailureKind.uploadFailed, error.message);
    }
    _checkCancelled();
    final jobs = info.scanJobs;
    var needResult = askResultFirst && jobs;
    var askOnce = needResult && !bodySentBefore;
    var firstWait = Duration.zero;
    Duration? pause;
    var posts = 0;
    ScanFailure? last;
    while (true) {
      if (needResult) {
        final stored = await _awaitResult(
          session.scanId,
          onStage,
          firstWait: firstWait,
          once: askOnce,
        );
        if (stored != null) return stored;
        // 404 or 409 (or no answer to a single question): upload again.
        needResult = false;
        askOnce = false;
        firstWait = Duration.zero;
      }
      if (posts == _maxPosts) {
        throw last ??
            const ScanFailure(
              ScanFailureKind.uploadFailed,
              'The photos could not be uploaded. They are kept on this phone; '
              'tap RETRY UPLOAD.',
            );
      }
      if (pause != null) await _delay(pause);
      _checkCancelled();
      pause = null;
      posts += 1;
      var bodySent = false;
      onStage?.call(ScanStage.uploading);
      try {
        final response = await _dio.post<Map<String, dynamic>>(
          _url('/v1/scans/count'),
          data: await _scanForm(session),
          cancelToken: _cancelToken,
          onSendProgress: (sent, total) {
            if (!bodySent && total > 0 && sent >= total) {
              bodySent = true;
              onBodySent?.call();
            }
            onProgress(sent, total);
          },
        );
        if (response.statusCode == 202) {
          if (!jobs) {
            throw const ScanFailure(
              ScanFailureKind.processingFailed,
              'The server is still working on this scan. Tap RETRY in a '
              'minute; the photos are kept.',
              status: 202,
            );
          }
          // Another upload of this scan holds the job: wait for its result.
          needResult = true;
          firstWait = _retryAfter(response.data) ?? _pollSteps.first;
          continue;
        }
        final data = response.data;
        if (data == null) {
          throw const ScanFailure(
            ScanFailureKind.processingFailed,
            'The server answered without a result. The photos are kept; tap '
            'RETRY.',
          );
        }
        return data;
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) throw _cancelledFailure;
        final status = error.response?.statusCode;
        if (status != null && _tryLater.contains(status)) {
          // Busy or timed out on the server's side: nothing was counted.
          last = _httpFailure(error);
          pause = _retryAfterHeader(error.response) ?? _backoffAfter(posts);
          continue;
        }
        if (status != null) throw _httpFailure(error);
        final failure = _transportFailure(
          error,
          bodySent: bodySent,
          jobs: jobs,
        );
        if (!_retryable(error)) throw failure;
        last = failure;
        if (bodySent && jobs) {
          // The server may be counting it already: ask, do not upload again.
          needResult = true;
        } else {
          pause = _backoffAfter(posts);
        }
      }
    }
  }

  /// Answers that say "not now" rather than "no": request timeout, too early,
  /// too many requests (a Cloudflare rate limit). Asked again, never counted
  /// as a refusal of the scan.
  static const _tryLater = {408, 425, 429};

  static Duration _backoffAfter(int posts) =>
      _backoff[min(posts - 1, _backoff.length - 1)];

  Future<FormData> _scanForm(ScanSession session) async => FormData.fromMap({
    'scan_id': session.scanId,
    'scan_contract': 'model_spatial_v1',
    for (final entry in session.cellIds.entries)
      '${entry.key}_cell_id': entry.value,
    // Constraint evidence is additive: deployments that predate it ignore
    // the extra fields, so uploads stay compatible either way.
    for (final entry in session.constraintEvidence.entries)
      '${entry.key}_constraint_evidence': entry.value,
    'left': await MultipartFile.fromFile(
      session.pathFor(CaptureView.left)!,
      filename: 'left.jpg',
      contentType: DioMediaType.parse('image/jpeg'),
    ),
    'right': await MultipartFile.fromFile(
      session.pathFor(CaptureView.right)!,
      filename: 'right.jpg',
      contentType: DioMediaType.parse('image/jpeg'),
    ),
    'straight': await MultipartFile.fromFile(
      session.pathFor(CaptureView.straight)!,
      filename: 'straight.jpg',
      contentType: DioMediaType.parse('image/jpeg'),
    ),
  });

  /// Asks for a stored result until it arrives (200), the server says it has
  /// none (404, or 409 for a failed job: returns null, upload again) or about
  /// three minutes have passed on the clock (result lost). With [once], a
  /// question that gets no answer returns null too (upload): the photos of
  /// such a scan never finished sending, so it is not waited for.
  Future<Map<String, dynamic>?> _awaitResult(
    String scanId,
    void Function(ScanStage stage)? onStage, {
    Duration firstWait = Duration.zero,
    bool once = false,
  }) async {
    final deadline = _now().add(_resultBudget);
    var wait = firstWait;
    var step = 0;
    var running = firstWait > Duration.zero;
    while (true) {
      if (wait > Duration.zero) {
        onStage?.call(running ? ScanStage.waiting : ScanStage.checking);
        await _delay(wait);
      }
      _checkCancelled();
      onStage?.call(running ? ScanStage.waiting : ScanStage.checking);
      Duration? hint;
      try {
        final left = deadline.difference(_now());
        final response = await _dio.get<Map<String, dynamic>>(
          _url('/v1/scans/$scanId/result'),
          cancelToken: _cancelToken,
          options: Options(
            // Never far past the budget, never too short to get an answer.
            receiveTimeout: left < const Duration(seconds: 5)
                ? const Duration(seconds: 5)
                : (left < _resultReceive ? left : _resultReceive),
          ),
        );
        final data = response.data;
        if (response.statusCode == 200 && data != null) return data;
        // 202: still running under a valid lease.
        running = true;
        hint = _retryAfter(data);
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) throw _cancelledFailure;
        final status = error.response?.statusCode;
        if (status == 404 || status == 409) return null;
        if (status != null && status < 500 && !_tryLater.contains(status)) {
          throw _httpFailure(error);
        }
        // A 5xx, "try later" or no answer: ask again while the budget lasts.
        if (status != null) hint = _retryAfterHeader(error.response);
        if (once && !running) return null;
      }
      final remaining = deadline.difference(_now());
      if (remaining <= Duration.zero) {
        throw const ScanFailure(
          ScanFailureKind.resultLost,
          'The photos were sent, but no result has come back after about 3 '
          'minutes of asking. If they arrived, the server keeps this scan\'s '
          'result: tap KEEP WAITING to ask again. The photos are kept on this '
          'phone and are not counted twice.',
        );
      }
      final next = hint ?? _pollSteps[min(step, _pollSteps.length - 1)];
      wait = next < remaining ? next : remaining;
      step += 1;
    }
  }

  static Duration? _retryAfter(Map<String, dynamic>? data) {
    final job = data?['job'];
    final seconds = job is Map ? job['retry_after_s'] : null;
    if (seconds is! num) return null;
    return Duration(seconds: seconds.round().clamp(1, 30));
  }

  /// A `Retry-After: <seconds>` header, kept between 1 and 30 s.
  static Duration? _retryAfterHeader(Response<dynamic>? response) {
    final seconds = int.tryParse(
      response?.headers.value('retry-after')?.trim() ?? '',
    );
    if (seconds == null) return null;
    return Duration(seconds: seconds.clamp(1, 30));
  }

  /// No HTTP answer. "Sent" only means the whole body was handed to the
  /// connection, not that the server read it, so the words never say the
  /// photos arrived.
  ScanFailure _transportFailure(
    DioException error, {
    required bool bodySent,
    required bool jobs,
  }) {
    final what = switch (error.type) {
      DioExceptionType.sendTimeout => 'the upload timed out',
      DioExceptionType.receiveTimeout => 'no answer in time',
      DioExceptionType.connectionTimeout => 'the connection timed out',
      _ => 'the connection dropped',
    };
    if (!bodySent) {
      return ScanFailure(
        ScanFailureKind.uploadFailed,
        'The photos did not reach the server ($what before the upload '
        'finished). They are kept on this phone. Move to better signal or '
        'Wi-Fi and tap RETRY UPLOAD.',
      );
    }
    if (!jobs) {
      // No stored results (production while it stays open): there is
      // nothing to ask for, and sending again counts again.
      return ScanFailure(
        ScanFailureKind.resultLost,
        'The photos were sent, but no answer came back ($what). This server '
        'does not keep results, so the answer cannot be asked for: the server '
        'may already have counted them, and sending again makes it count them '
        'again. The photos are kept on this phone; tap SEND PHOTOS AGAIN.',
        serverKeepsResult: false,
      );
    }
    return ScanFailure(
      ScanFailureKind.resultLost,
      'The photos were sent, but no answer came back ($what). If they '
      'arrived, the server keeps this scan\'s result: tap KEEP WAITING to ask '
      'for it. The photos are kept on this phone and are not counted twice.',
    );
  }

  /// An HTTP answer, in the contract's failure classes. Only answers that
  /// no retry can change reject (and so forget) a scan; anything unexpected
  /// keeps the photos for a retry.
  ScanFailure _httpFailure(DioException error) {
    final status = error.response?.statusCode ?? 0;
    final code = _code(error);
    final server = _serverMessage(error);
    if (status == 401 || (status == 403 && code != 'scan_forbidden')) {
      final refused = switch (code) {
        'device_pending' => DeviceStatus.pending,
        'device_revoked' => DeviceStatus.revoked,
        _ => null,
      };
      if (refused != null) {
        _auth.noteState(
          _uri,
          DeviceState(
            authRequired: true,
            status: refused,
            displayCode: _auth.cachedIdentity?.displayCode,
          ),
        );
      }
      return ScanFailure(
        ScanFailureKind.notAuthorised,
        switch (code) {
          'device_pending' =>
            'This phone is waiting for approval. Ask the admin to approve '
                'it; the photos are kept and the scan can be resumed from the '
                'home screen.',
          'device_revoked' =>
            'This phone has been revoked and cannot send scans.',
          'device_auth_failed' =>
            "The server does not recognise this phone's device key.",
          'device_credentials_required' =>
            "The server asked for this phone's device key, which could not "
                'be sent.',
          _ => 'The server refused this phone (${server ?? 'error $status'}).',
        },
        code: code,
        status: status,
      );
    }
    if (status >= 500 ||
        (status == 409 &&
            (code == 'scan_failed' || code == 'processing_interrupted'))) {
      return ScanFailure(
        ScanFailureKind.processingFailed,
        'The server received the photos but could not count them '
        '(${server ?? 'error $status'}). The photos are kept; tap RETRY.',
        code: code,
        status: status,
      );
    }
    if (_tryLater.contains(status)) {
      return ScanFailure(
        ScanFailureKind.uploadFailed,
        'The server is busy and did not take the photos '
        '(${server ?? 'error $status'}). They are kept on this phone; wait a '
        'minute and tap RETRY UPLOAD.',
        code: code,
        status: status,
      );
    }
    // 403 scan_forbidden (the scan id belongs to another phone) is rejected
    // too: this phone can never send under that id; a retake makes a new one.
    final refusedScan =
        const {400, 413, 415, 422}.contains(status) ||
        (status == 409 && code == 'scan_id_conflict') ||
        (status == 403 && code == 'scan_forbidden');
    if (!refusedScan) {
      return ScanFailure(
        ScanFailureKind.processingFailed,
        'The server gave an unexpected answer '
        '(${server ?? 'error $status'}). The photos are kept on this phone; '
        'check the server address in Settings, then tap RETRY.',
        code: code,
        status: status,
      );
    }
    return ScanFailure(
      ScanFailureKind.rejected,
      '${server ?? 'The server refused this scan (error $status).'} '
      'Sending it again will not help: retake the photos or start a new scan.',
      code: code,
      status: status,
    );
  }

  static const _cancelledFailure = ScanFailure(
    ScanFailureKind.cancelled,
    'The scan was cancelled.',
  );

  void _checkCancelled() {
    if (_closed || (_cancelToken?.isCancelled ?? false)) {
      throw _cancelledFailure;
    }
  }

  /// Stores the operator's on-site count next to the scan's archived photos.
  /// The body, and so its `count_id`, is the same on every transport retry,
  /// so the server keeps one record however many tries reach it.
  Future<Map<String, dynamic>> submitManualCount(
    ManualCount count, {
    String? appVersion,
  }) async {
    if (_auth.serverInfo(_uri) == null) {
      try {
        await serverInfo();
      } on DioException {
        // Unknown server: send anyway; the answer says what is wrong.
      }
    }
    final body = count.toJson(appVersion: appVersion);
    final response = await _retrying(
      () => _dio.post<Map<String, dynamic>>(
        _url('/v1/scans/${count.scanId}/manual-count'),
        data: body,
        options: Options(contentType: 'application/json'),
      ),
    );
    final data = response.data;
    if (data == null || (data['stored'] != true && data['replayed'] != true)) {
      throw const FormatException('The server did not store the manual count.');
    }
    return data;
  }

  /// Runs an idempotent request, retrying transport failures with backoff.
  Future<T> _retrying<T>(Future<T> Function() request, {int tries = 3}) async {
    for (var attempt = 0; ; attempt += 1) {
      try {
        return await request();
      } on DioException catch (error) {
        if (CancelToken.isCancel(error) ||
            !_retryable(error) ||
            attempt == tries - 1) {
          rethrow;
        }
        await _delay(_backoff[min(attempt, _backoff.length - 1)]);
      }
    }
  }

  static String? _code(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is Map) {
      final code = (data['detail'] as Map)['code'];
      if (code is String) return code;
    }
    return null;
  }

  static String? _serverMessage(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is Map) {
      final message = (data['detail'] as Map)['message']?.toString();
      if (message != null && message.isNotEmpty) return message;
    }
    return null;
  }

  /// Transport failures are retried; an HTTP answer from the server is not.
  bool _retryable(DioException error) =>
      error.response == null &&
      ({
            DioExceptionType.connectionError,
            DioExceptionType.connectionTimeout,
            DioExceptionType.receiveTimeout,
            DioExceptionType.sendTimeout,
          }.contains(error.type) ||
          error.error is SocketException ||
          error.error is HandshakeException ||
          error.error is HttpException);

  void cancel() {
    _closed = true;
    _cancelToken?.cancel('Operator cancelled scan');
  }
}
