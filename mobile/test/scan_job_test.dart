import 'dart:io';

import 'package:dio/dio.dart';
import 'package:egg_tray_counter/app/app_version.dart';
import 'package:egg_tray_counter/models/manual_count.dart';
import 'package:egg_tray_counter/services/api_client.dart';
import 'package:egg_tray_counter/services/device_auth.dart';
import 'package:egg_tray_counter/services/scan_failure.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';

const _base = 'https://staging.example.test';
const _count = 'POST /v1/scans/count';

void main() {
  late Directory dir;
  late DeviceAuth auth;
  late NoWait wait;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('scan_job_test');
    auth = DeviceAuth(store: InMemorySecretStore());
    wait = NoWait();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  ApiClient client(FakeServer server) => ApiClient(
    _base,
    adapter: server,
    deviceAuth: auth,
    delay: wait.call,
    now: wait.clock,
  );

  Future<Map<String, dynamic>> submit(
    ApiClient api,
    String scanId, {
    bool askResultFirst = false,
    bool bodySentBefore = true,
    void Function()? onBodySent,
  }) => api.submitScan(
    photoSession(dir, scanId),
    onProgress: (_, _) {},
    onBodySent: onBodySent,
    askResultFirst: askResultFirst,
    bodySentBefore: bodySentBefore,
  );

  group('scan upload and job recovery', () {
    test('a transport error before the body was sent uploads again', () async {
      final server = FakeServer({
        'GET /health': [reply(jobsHealth)],
        _count: [dropBeforeBody(), reply(scanBody('s1'))],
      });
      var sent = 0;
      final body = await submit(client(server), 's1', onBodySent: () => sent++);
      expect(body['scan_id'], 's1');
      expect(server.calls(_count), hasLength(2));
      expect(server.calls('GET /v1/scans/s1/result'), isEmpty);
      expect(sent, 1, reason: 'only the second upload completed its body');
      expect(wait.waits, [const Duration(milliseconds: 800)]);
    });

    test('a receive timeout after the body was sent asks for the result and '
        'does not upload again', () async {
      final server = FakeServer({
        'GET /health': [reply(jobsHealth)],
        _count: [timeoutAfterBody(), reply(scanBody('s2'))],
        'GET /v1/scans/s2/result': [reply(scanBody('s2'))],
      });
      final body = await submit(client(server), 's2');
      expect(body['scan_id'], 's2');
      expect(server.calls(_count), hasLength(1));
      expect(server.calls('GET /v1/scans/s2/result'), hasLength(1));
      expect(server.log.last, 'GET /v1/scans/s2/result');
    });

    test('202 processing waits, then the stored result is used', () async {
      final server = FakeServer({
        'GET /health': [reply(jobsHealth)],
        _count: [
          reply({
            ...detail('processing'),
            'job': {'status': 'running', 'retry_after_s': 4},
          }, 202),
        ],
        'GET /v1/scans/s3/result': [
          reply({
            ...detail('processing'),
            'job': {'status': 'running', 'retry_after_s': 7},
          }, 202),
          reply(scanBody('s3')),
        ],
      });
      final body = await submit(client(server), 's3');
      expect(body['scan_id'], 's3');
      expect(server.calls(_count), hasLength(1));
      expect(server.calls('GET /v1/scans/s3/result'), hasLength(2));
      expect(wait.waits, [
        const Duration(seconds: 4),
        const Duration(seconds: 7),
      ]);
    });

    test('404 from the result route uploads the same scan again', () async {
      final server = FakeServer({
        'GET /health': [reply(jobsHealth)],
        _count: [timeoutAfterBody(), reply(scanBody('s4'))],
        'GET /v1/scans/s4/result': [reply(detail('scan_not_found'), 404)],
      });
      final body = await submit(client(server), 's4');
      expect(body['scan_id'], 's4');
      expect(server.log, [
        'GET /health',
        _count,
        'GET /v1/scans/s4/result',
        _count,
      ]);
      // Both uploads carried the same scan id.
      for (final upload in server.calls(_count)) {
        expect(String.fromCharCodes(upload.body!), contains('s4'));
      }
    });

    test('409 scan_failed from the result route uploads again', () async {
      final server = FakeServer({
        'GET /health': [reply(jobsHealth)],
        _count: [reply(scanBody('s9'))],
        'GET /v1/scans/s9/result': [reply(detail('scan_failed'), 409)],
      });
      final body = await submit(client(server), 's9', askResultFirst: true);
      expect(body['scan_id'], 's9');
      expect(server.log, ['GET /health', 'GET /v1/scans/s9/result', _count]);
    });

    test('409 scan_id_conflict is rejected without a retry', () async {
      final server = FakeServer({
        'GET /health': [reply(jobsHealth)],
        _count: [
          reply(
            detail(
              'scan_id_conflict',
              'This scan id was already used with other photos',
            ),
            409,
          ),
        ],
      });
      await expectLater(
        submit(client(server), 's5'),
        throwsA(
          isA<ScanFailure>()
              .having((f) => f.kind, 'kind', ScanFailureKind.rejected)
              .having((f) => f.retryable, 'retryable', isFalse)
              .having((f) => f.message, 'message', contains('other photos')),
        ),
      );
      expect(server.calls(_count), hasLength(1));
      expect(server.calls('GET /v1/scans/s5/result'), isEmpty);
    });

    test('413, 415 and 422 are rejected; 5xx is a processing failure', () async {
      for (final (status, code, kind) in [
        (413, 'image_too_large', ScanFailureKind.rejected),
        (415, 'invalid_mime_type', ScanFailureKind.rejected),
        (422, 'duplicate_view', ScanFailureKind.rejected),
        (502, 'inference_failed', ScanFailureKind.processingFailed),
        (503, 'inference_quota_exhausted', ScanFailureKind.processingFailed),
      ]) {
        final server = FakeServer({
          'GET /health': [reply(jobsHealth)],
          _count: [reply(detail(code), status)],
        });
        await expectLater(
          submit(client(server), 'r$status'),
          throwsA(isA<ScanFailure>().having((f) => f.kind, 'kind', kind)),
          reason: '$status $code',
        );
        expect(server.calls(_count), hasLength(1), reason: '$status');
      }
    });

    test('401 and 403 device errors are not authorised', () async {
      for (final (status, code) in [
        (401, 'device_auth_failed'),
        (401, 'device_credentials_required'),
        (403, 'device_pending'),
        (403, 'device_revoked'),
      ]) {
        final server = FakeServer({
          'GET /health': [reply(jobsHealth)],
          _count: [reply(detail(code), status)],
        });
        await expectLater(
          submit(client(server), 'a$status'),
          throwsA(
            isA<ScanFailure>()
                .having((f) => f.kind, 'kind', ScanFailureKind.notAuthorised)
                .having((f) => f.code, 'code', code)
                .having((f) => f.retryable, 'retryable', isFalse),
          ),
        );
        expect(server.calls(_count), hasLength(1));
      }
      expect(
        auth.stateFor(Uri.parse(_base))?.status,
        DeviceStatus.revoked,
        reason: 'the last refusal is what the home screen shows',
      );
    });

    test('a result that never comes is lost after about three minutes', () async {
      final server = FakeServer({
        'GET /health': [reply(jobsHealth)],
        _count: [timeoutAfterBody()],
        'GET /v1/scans/s6/result': [
          reply({...detail('processing'), 'job': <String, Object>{}}, 202),
        ],
      });
      await expectLater(
        submit(client(server), 's6'),
        throwsA(
          isA<ScanFailure>()
              .having((f) => f.kind, 'kind', ScanFailureKind.resultLost)
              .having((f) => f.retryable, 'retryable', isTrue),
        ),
      );
      expect(server.calls(_count), hasLength(1));
      final waited = wait.waits.fold(Duration.zero, (a, b) => a + b);
      expect(waited, greaterThanOrEqualTo(const Duration(minutes: 3)));
      expect(waited, lessThan(const Duration(minutes: 4)));
    });

    test('the result budget is measured on the clock, requests included', () async {
      // Every result request hangs for 10 s and then drops. The old budget
      // added up only the pauses: 14 requests and about 331 s.
      final server = FakeServer({
        'GET /health': [reply(jobsHealth)],
        _count: [timeoutAfterBody()],
        'GET /v1/scans/b1/result': [slowDrop(wait, const Duration(seconds: 10))],
      });
      await expectLater(
        submit(client(server), 'b1'),
        throwsA(
          isA<ScanFailure>()
              .having((f) => f.kind, 'kind', ScanFailureKind.resultLost)
              .having((f) => f.serverKeepsResult, 'keeps', isTrue)
              .having((f) => f.message, 'message', contains('were sent'))
              .having((f) => f.message, 'message', isNot(contains('reached'))),
        ),
      );
      expect(wait.elapsed, greaterThanOrEqualTo(const Duration(minutes: 3)));
      expect(wait.elapsed, lessThan(const Duration(seconds: 200)));
      final asks = server.calls('GET /v1/scans/b1/result');
      expect(asks.length, lessThan(14));
      expect(server.calls(_count), hasLength(1));
      // No single question waits past the budget by more than its floor.
      for (final ask in asks) {
        expect(
          ask.options.receiveTimeout,
          lessThanOrEqualTo(const Duration(seconds: 20)),
        );
      }
      expect(
        asks.last.options.receiveTimeout,
        lessThan(const Duration(seconds: 20)),
      );
    });

    test('a server without stored results never offers to ask for one and '
        'says that sending again counts again', () async {
      final server = FakeServer({
        'GET /health': [reply(openHealth)],
        _count: [timeoutAfterBody()],
      });
      await expectLater(
        submit(client(server), 'n1', askResultFirst: true),
        throwsA(
          isA<ScanFailure>()
              .having((f) => f.kind, 'kind', ScanFailureKind.resultLost)
              .having((f) => f.serverKeepsResult, 'keeps', isFalse)
              .having((f) => f.title, 'title', 'Result not received')
              .having((f) => f.message, 'message', contains('count them again'))
              .having(
                (f) => f.message,
                'message',
                isNot(contains('not counted twice')),
              ),
        ),
      );
      expect(server.calls(_count), hasLength(4));
      expect(server.log.where((r) => r.contains('/result')), isEmpty);
    });

    test('a resumed scan whose photos never finished sending is asked for '
        'once, then uploaded', () async {
      final server = FakeServer({
        'GET /health': [reply(jobsHealth)],
        'GET /v1/scans/q2/result': [dropBeforeBody()],
        _count: [reply(scanBody('q2'))],
      });
      final body = await submit(
        client(server),
        'q2',
        askResultFirst: true,
        bodySentBefore: false,
      );
      expect(body['scan_id'], 'q2');
      expect(server.log, [
        'GET /health',
        'GET /v1/scans/q2/result',
        _count,
      ]);
    });

    test('a resumed scan that was sent in full keeps asking; a 202 on the '
        'single question switches to waiting', () async {
      final server = FakeServer({
        'GET /health': [reply(jobsHealth)],
        'GET /v1/scans/q3/result': [
          reply({
            ...detail('processing'),
            'job': {'status': 'running', 'retry_after_s': 3},
          }, 202),
          dropBeforeBody(),
          reply(scanBody('q3')),
        ],
      });
      final body = await submit(
        client(server),
        'q3',
        askResultFirst: true,
        bodySentBefore: false,
      );
      expect(body['scan_id'], 'q3');
      expect(server.calls('GET /v1/scans/q3/result'), hasLength(3));
      expect(server.calls(_count), isEmpty);
    });

    test('429 and 408 are tried again after Retry-After, never a rejection',
        () async {
      final server = FakeServer({
        'GET /health': [reply(jobsHealth)],
        _count: [
          reply(detail('rate_limited'), 429, {
            'retry-after': ['7'],
          }),
          reply(detail('request_timeout'), 408),
          reply(scanBody('t1')),
        ],
      });
      final body = await submit(client(server), 't1');
      expect(body['scan_id'], 't1');
      expect(server.calls(_count), hasLength(3));
      expect(wait.waits, [
        const Duration(seconds: 7),
        const Duration(seconds: 2),
      ]);

      final busy = FakeServer({
        'GET /health': [reply(jobsHealth)],
        _count: [reply(detail('rate_limited'), 429)],
      });
      await expectLater(
        submit(client(busy), 't2'),
        throwsA(
          isA<ScanFailure>()
              .having((f) => f.kind, 'kind', ScanFailureKind.uploadFailed)
              .having((f) => f.status, 'status', 429)
              .having((f) => f.retryable, 'retryable', isTrue),
        ),
      );
      expect(busy.calls(_count), hasLength(4));
    });

    test('a 429 while asking for the result asks again', () async {
      final server = FakeServer({
        'GET /health': [reply(jobsHealth)],
        'GET /v1/scans/t3/result': [
          reply(detail('rate_limited'), 429, {
            'retry-after': ['4'],
          }),
          reply(scanBody('t3')),
        ],
      });
      final body = await submit(client(server), 't3', askResultFirst: true);
      expect(body['scan_id'], 't3');
      expect(wait.waits, [const Duration(seconds: 4)]);
      expect(server.calls(_count), isEmpty);
    });

    test('only refusals no retry can change are rejected; scan_forbidden is '
        'rejected, processing_interrupted and unexpected answers keep the '
        'scan', () async {
      for (final (status, code, kind) in [
        (400, 'bad_request', ScanFailureKind.rejected),
        (403, 'scan_forbidden', ScanFailureKind.rejected),
        (409, 'processing_interrupted', ScanFailureKind.processingFailed),
        (404, 'not_found', ScanFailureKind.processingFailed),
        (405, 'method_not_allowed', ScanFailureKind.processingFailed),
        (409, 'something_else', ScanFailureKind.processingFailed),
      ]) {
        final server = FakeServer({
          'GET /health': [reply(jobsHealth)],
          _count: [reply(detail(code), status)],
        });
        await expectLater(
          submit(client(server), 'k$status$code'.replaceAll('_', '')),
          throwsA(isA<ScanFailure>().having((f) => f.kind, 'kind', kind)),
          reason: '$status $code',
        );
        expect(server.calls(_count), hasLength(1), reason: '$status $code');
      }
      // Asking for the result: an unexpected 4xx is not a rejection either.
      final odd = FakeServer({
        'GET /health': [reply(jobsHealth)],
        'GET /v1/scans/k1/result': [reply(detail('teapot'), 418)],
      });
      await expectLater(
        submit(client(odd), 'k1', askResultFirst: true),
        throwsA(
          isA<ScanFailure>().having(
            (f) => f.kind,
            'kind',
            ScanFailureKind.processingFailed,
          ),
        ),
      );
    });

    test('a server without stored results keeps the 0.4.11 retry', () async {
      final server = FakeServer({
        'GET /health': [reply(openHealth)],
        _count: [timeoutAfterBody(), reply(scanBody('s7'))],
      });
      final body = await submit(client(server), 's7', askResultFirst: true);
      expect(body['scan_id'], 's7');
      expect(server.log, ['GET /health', _count, _count]);
    });

    test('no photos are sent when the server cannot be reached', () async {
      final server = FakeServer({
        'GET /health': [dropBeforeBody()],
      });
      await expectLater(
        submit(client(server), 's8'),
        throwsA(
          isA<ScanFailure>()
              .having((f) => f.kind, 'kind', ScanFailureKind.uploadFailed)
              .having((f) => f.message, 'message', contains('no photos')),
        ),
      );
      expect(server.calls(_count), isEmpty);
    });
  });

  group('device credentials', () {
    test('are sent only to a server that advertises device_v1', () async {
      final count = ManualCount(
        scanId: 'm1',
        blockId: 'B1',
        cells: const [],
        notes: '',
        createdAt: DateTime.utc(2026, 10, 15, 8),
        countId: '0f8fad5b-d9cb-469f-a165-70867728950e',
      );
      final open = FakeServer({
        'GET /health': [reply(openHealth)],
        'POST /v1/scans/m1/manual-count': [reply({'stored': true})],
      });
      await client(open).submitManualCount(count, appVersion: kAppVersion);
      for (final request in open.requests) {
        expect(request.headers.containsKey('X-Device-Id'), isFalse);
        expect(request.headers.containsKey('Authorization'), isFalse);
      }

      final enforced = FakeServer({
        'GET /health': [reply(jobsHealth)],
        'POST /v1/scans/m1/manual-count': [reply({'stored': true})],
      });
      await ApiClient(
        'https://enforced.example.test',
        adapter: enforced,
        deviceAuth: auth,
        delay: wait.call,
      ).submitManualCount(count, appVersion: kAppVersion);
      final identity = await auth.identity();
      final post = enforced.calls('POST /v1/scans/m1/manual-count').single;
      expect(post.headers['X-Device-Id'], identity.deviceId);
      expect(post.headers['Authorization'], 'Device ${identity.secret}');

      // The first server still gets nothing, and neither does another host.
      await client(open).submitManualCount(count, appVersion: kAppVersion);
      expect(
        open.calls('POST /v1/scans/m1/manual-count').last.headers,
        isNot(contains('Authorization')),
      );
    });

    test('identity is a UUID v4 and a 32-byte base64url secret, made once, '
        'and never printed', () async {
      final store = InMemorySecretStore();
      final first = await DeviceAuth(store: store).identity();
      final again = await DeviceAuth(store: store).identity();
      expect(again.deviceId, first.deviceId);
      expect(again.secret, first.secret);
      expect(
        first.deviceId,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(first.secret, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(first.displayCode, matches(RegExp(r'^[0-9A-F]{4}-[0-9A-F]{4}$')));
      expect(first.toString(), isNot(contains(first.secret)));
    });

    test('registration is idempotent and the status follows approval', () async {
      final records = <String, ({String secret, String status})>{};
      Answer register() => (request) async {
        await readBody(request);
        final body = request.json;
        final id = body['device_id'] as String;
        final known = records[id];
        if (known != null && known.secret != body['secret']) {
          return json(detail('device_exists'), 409);
        }
        records[id] = known ?? (secret: body['secret'] as String, status: 'pending');
        return json({
          'device_id': id,
          'status': records[id]!.status,
          'display_code': DeviceIdentity.displayCodeFor(id),
        }, known == null ? 201 : 200);
      };
      Answer me() => (request) async {
        final id = request.headers['X-Device-Id'] as String;
        final record = records[id];
        if (record == null ||
            request.headers['Authorization'] != 'Device ${record.secret}') {
          return json(detail('device_auth_failed'), 401);
        }
        return json({
          'device_id': id,
          'status': record.status,
          'display_code': DeviceIdentity.displayCodeFor(id),
        }, 200);
      };
      FakeServer server() => FakeServer({
        'GET /health': [reply(jobsHealth)],
        'POST /v1/devices': [register()],
        'GET /v1/devices/me': [me()],
      });

      final store = InMemorySecretStore();
      final launch1 = server();
      final firstAuth = DeviceAuth(store: store);
      final first = await ApiClient(
        _base,
        adapter: launch1,
        deviceAuth: firstAuth,
        delay: wait.call,
      ).checkDevice();
      expect(first.status, DeviceStatus.pending);
      expect(first.mayScan, isFalse);
      expect(first.label, startsWith('WAITING FOR APPROVAL - device '));
      expect(first.blockReason, contains(first.displayCode));

      // A relaunch registers again with the same id and secret: no new record.
      final launch2 = server();
      final secondAuth = DeviceAuth(store: store);
      final second = await ApiClient(
        _base,
        adapter: launch2,
        deviceAuth: secondAuth,
        delay: wait.call,
      ).checkDevice();
      expect(second.status, DeviceStatus.pending);
      expect(records, hasLength(1));
      final bodies = [
        ...launch1.calls('POST /v1/devices'),
        ...launch2.calls('POST /v1/devices'),
      ].map((r) => r.json).toList();
      expect(bodies, hasLength(2));
      expect(bodies[1]['device_id'], bodies[0]['device_id']);
      expect(bodies[1]['secret'], bodies[0]['secret']);
      expect(bodies[0]['app_version'], kAppVersion);

      // The admin approves: the next check says so and scans may start.
      final id = records.keys.single;
      records[id] = (secret: records[id]!.secret, status: 'active');
      final approved = await ApiClient(
        _base,
        adapter: launch2,
        deviceAuth: secondAuth,
        delay: wait.call,
      ).checkDevice();
      expect(approved.status, DeviceStatus.active);
      expect(approved.label, 'DEVICE APPROVED');
      expect(approved.mayScan, isTrue);
      expect(launch2.calls('POST /v1/devices'), hasLength(1));

      // Same id with another secret: the server refuses, the phone says why.
      store.values.update('egg_device_secret_v1', (_) => 'x' * 43);
      final clash = await ApiClient(
        _base,
        adapter: server(),
        deviceAuth: DeviceAuth(store: store),
        delay: wait.call,
      ).checkDevice();
      expect(clash.mayScan, isFalse);
      expect(clash.problem, contains('different key'));
    });

    test('a device check that gets no answer keeps the last answer and does '
        'not block a scan', () async {
      var meAnswers = 0;
      Answer me() => (request) async {
        meAnswers += 1;
        if (meAnswers == 1) {
          return json({'device_id': 'x', 'status': 'active'}, 200);
        }
        throw DioException.connectionError(
          requestOptions: request.options,
          reason: 'Connection reset by peer',
          error: const SocketException('Connection reset by peer'),
        );
      };
      final server = FakeServer({
        'GET /health': [reply(jobsHealth)],
        'POST /v1/devices': [reply({'status': 'pending'}, 201)],
        'GET /v1/devices/me': [me()],
      });
      final first = await client(server).checkDevice();
      expect(first.status, DeviceStatus.active);
      final dropped = await client(server).checkDevice();
      expect(dropped.status, DeviceStatus.active);
      expect(dropped.mayScan, isTrue);
      expect(auth.stateFor(Uri.parse(_base))?.status, DeviceStatus.active);

      // Never answered before: not a refusal either.
      final fresh = DeviceAuth(store: InMemorySecretStore());
      final silent = await ApiClient(
        'https://silent.example.test',
        adapter: FakeServer({
          'GET /health': [reply(jobsHealth)],
          'POST /v1/devices': [dropBeforeBody()],
        }),
        deviceAuth: fresh,
        delay: wait.call,
      ).checkDevice();
      expect(silent.unreachable, isTrue);
      expect(silent.mayScan, isFalse);
      expect(silent.blockReason, isNull, reason: 'a scan may start');
      expect(silent.problem, contains('could not reach the server'));
      expect(silent.label, startsWith('DEVICE NOT CHECKED'));

      // A definite refusal still blocks.
      final pending = await ApiClient(
        'https://pending.example.test',
        adapter: FakeServer({
          'GET /health': [reply(jobsHealth)],
          'POST /v1/devices': [reply({'status': 'pending'}, 201)],
          'GET /v1/devices/me': [reply(detail('device_pending'), 403)],
        }),
        deviceAuth: fresh,
        delay: wait.call,
      ).checkDevice();
      expect(pending.status, DeviceStatus.pending);
      expect(pending.blockReason, isNotNull);
    });

    test('an open server needs no registration', () async {
      final server = FakeServer({
        'GET /health': [reply(openHealth)],
      });
      final state = await client(server).checkDevice();
      expect(state.authRequired, isFalse);
      expect(state.mayScan, isTrue);
      expect(server.log, ['GET /health']);
    });
  });

  group('manual counts', () {
    test('the body carries count_id, created_at, app_total and the app '
        'version; a transport retry sends the same count_id', () async {
      final count = ManualCount(
        scanId: 'm2',
        blockId: 'B2',
        cells: const [
          ManualCountCell(
            x: 0,
            y: 0,
            appLayers: 20,
            appStatus: 'observed',
            filled: 19,
            empty: 1,
          ),
        ],
        notes: 'n',
        createdAt: DateTime.utc(2026, 10, 15, 7, 19),
        appTotal: 20,
        countId: '7c9e6679-7425-40de-944b-e07fc1f90ae7',
      );
      final server = FakeServer({
        'GET /health': [reply(jobsHealth)],
        'POST /v1/scans/m2/manual-count': [
          timeoutAfterBody(),
          reply({'stored': true, 'replayed': true, 'totals': {'filled': 19}}),
        ],
      });
      final response = await client(
        server,
      ).submitManualCount(count, appVersion: kAppVersion);
      expect(response['replayed'], isTrue);
      final posts = server.calls('POST /v1/scans/m2/manual-count');
      expect(posts, hasLength(2));
      final body = posts.first.json;
      expect(body['count_id'], '7c9e6679-7425-40de-944b-e07fc1f90ae7');
      expect(body['created_at'], '2026-10-15T07:19:00.000Z');
      expect(body['app_total'], 20);
      expect(body['app_version'], kAppVersion);
      expect(posts.last.json, body);
    });
  });
}
