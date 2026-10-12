import 'dart:io';
import 'dart:convert';
import '../models/reconstruction_result.dart';
import 'reconstruction_photos.dart';

import 'package:dio/dio.dart';

import '../models/capture_view.dart';
import '../models/manual_count.dart';
import '../models/scan_result.dart';
import '../models/scan_session.dart';

class ApiClient {
  ApiClient(String baseUrl)
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          // Three photos (about 1.5 MB) over a mobile link that drops 40% of
          // its packets (measured on Jio LTE to workers.dev, 2026-10-12) can
          // take well over a minute; the old 45 s cut such uploads off.
          sendTimeout: const Duration(seconds: 150),
          receiveTimeout: const Duration(seconds: 90),
        ),
      );

  final Dio _dio;
  CancelToken? _cancelToken;

  /// Pauses between retries: short, then longer, so a dropped TLS handshake
  /// (the common failure on this link) gets a fresh connection each time.
  static const List<Duration> _backoff = [
    Duration(milliseconds: 800),
    Duration(seconds: 2),
    Duration(seconds: 5),
  ];

  /// Three quick tries: one dropped handshake must not read as "offline".
  Future<bool> health() async {
    for (var attempt = 0; attempt < 3; attempt += 1) {
      try {
        final response = await _dio.get<Map<String, dynamic>>(
          '/health',
          options: Options(receiveTimeout: const Duration(seconds: 12)),
        );
        return response.statusCode == 200 && response.data?['status'] == 'ok';
      } on DioException catch (error) {
        if (!_retryable(error) || attempt == 2) return false;
        await Future<void>.delayed(_backoff[attempt]);
      }
    }
    return false;
  }

  /// What went wrong, in the operator's words. Server-provided messages win.
  static String describe(DioException error) {
    final detail = error.response?.data;
    if (detail is Map && detail['detail'] is Map) {
      final message = (detail['detail'] as Map)['message']?.toString();
      if (message != null && message.isNotEmpty) return message;
    }
    final status = error.response?.statusCode;
    if (status != null) {
      return 'The server answered with error $status. Try again; if it repeats, '
          'the server needs attention.';
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout || DioExceptionType.connectionError =>
        'The phone could not reach the server (connection dropped). The mobile '
            'signal to the server is unstable here: move to better signal or '
            'Wi-Fi and tap RETRY SAME SCAN.',
      DioExceptionType.sendTimeout =>
        'The photos could not be uploaded in time (weak or unstable signal). '
            'Move to better signal or Wi-Fi and tap RETRY SAME SCAN.',
      DioExceptionType.receiveTimeout =>
        'The server did not answer in time. Tap RETRY SAME SCAN; the photos '
            'are kept.',
      DioExceptionType.cancel => 'The scan was cancelled.',
      _ => switch (error.error) {
        SocketException() || HandshakeException() || HttpException() =>
          'The connection to the server dropped. Move to better signal or '
              'Wi-Fi and tap RETRY SAME SCAN.',
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

  Future<void> requireModelScan() async {
    Response<Map<String, dynamic>>? response;
    for (var attempt = 0; attempt < 3; attempt += 1) {
      try {
        response = await _dio.get<Map<String, dynamic>>(
          '/health',
          options: Options(receiveTimeout: const Duration(seconds: 12)),
        );
        break;
      } on DioException catch (error) {
        if (!_retryable(error) || attempt == 2) rethrow;
        await Future<void>.delayed(_backoff[attempt]);
      }
    }
    if (!supportsModelScan(response!.data)) {
      throw const FormatException(
        'The server needs the optional-marker scan update. No images were uploaded. Update the backend and retry.',
      );
    }
  }

  Future<ReconstructionResult> reconstruct(PreparedPair pair) async {
    final health = await _dio.get<Map<String, dynamic>>('/health');
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
        '/v1/reconstruct',
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

  Future<ScanResult> countScan(
    ScanSession session, {
    required void Function(int sent, int total) onProgress,
  }) async {
    if (!session.isComplete) {
      throw StateError('LEFT, RIGHT, and STRAIGHT are required');
    }
    await requireModelScan();
    _cancelToken = CancelToken();
    DioException? lastError;
    // Four tries with growing pauses: a dropped handshake or a stalled upload
    // on a lossy link is retried with a fresh connection before giving up.
    for (var attempt = 0; attempt < 4; attempt += 1) {
      try {
        final form = FormData.fromMap({
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
        final response = await _dio.post<Map<String, dynamic>>(
          '/v1/scans/count',
          data: form,
          cancelToken: _cancelToken,
          onSendProgress: onProgress,
        );
        final data = response.data;
        if (data == null) throw const FormatException('Empty API response');
        // Reject servers that silently ignore the requested analysis contract.
        if (data['processing'] is! Map ||
            data['processing']['mode'] != 'model_spatial_v1' ||
            data['cell_ids'] is! Map ||
            session.cellIds.entries.any(
              (entry) => data['cell_ids'][entry.key] != entry.value,
            )) {
          throw const FormatException(
            'The server returned an incompatible scan result. Update the backend and retry.',
          );
        }
        return ScanResult.fromJson(data);
      } on DioException catch (error) {
        lastError = error;
        if (CancelToken.isCancel(error) || !_retryable(error) || attempt == 3) {
          rethrow;
        }
        await Future<void>.delayed(_backoff[attempt]);
      }
    }
    throw lastError ?? const HttpException('Scan request failed');
  }

  /// Stores the operator's on-site count next to the scan's archived photos.
  Future<Map<String, dynamic>> submitManualCount(
    ManualCount count, {
    String? appVersion,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/v1/scans/${count.scanId}/manual-count',
      data: count.toJson(appVersion: appVersion),
      options: Options(contentType: 'application/json'),
    );
    final data = response.data;
    if (data == null || data['stored'] != true) {
      throw const FormatException('The server did not store the manual count.');
    }
    return data;
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
    _cancelToken?.cancel('Operator cancelled scan');
  }
}
