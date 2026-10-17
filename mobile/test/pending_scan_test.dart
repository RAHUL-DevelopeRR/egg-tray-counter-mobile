import 'dart:io';

import 'package:egg_tray_counter/app/app_version.dart';
import 'package:egg_tray_counter/features/home/home_screen.dart';
import 'package:egg_tray_counter/models/capture_view.dart';
import 'package:egg_tray_counter/models/scan_result.dart';
import 'package:egg_tray_counter/services/api_client.dart';
import 'package:egg_tray_counter/services/device_auth.dart';
import 'package:egg_tray_counter/services/history_database.dart';
import 'package:egg_tray_counter/services/pending_scans.dart';
import 'package:egg_tray_counter/services/scan_failure.dart';
import 'package:egg_tray_counter/services/scan_job_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_server.dart';

const _base = 'https://staging.example.test';
const _count = 'POST /v1/scans/count';

/// History whose first saves fail, like a full disk.
class _FlakyHistory extends HistoryDatabase {
  _FlakyHistory({required super.factory, required super.path});

  int failures = 1;

  @override
  Future<void> save(ScanResult result, {String appVersion = kAppVersion}) {
    if (failures > 0) {
      failures -= 1;
      throw const FileSystemException('disk full');
    }
    return super.save(result, appVersion: appVersion);
  }
}

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late Directory photos;
  late Directory pendingRoot;
  late Directory scratch;
  late String dbPath;
  late NoWait wait;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pending_scan_test');
    photos = Directory('${dir.path}/photos')..createSync();
    pendingRoot = Directory('${dir.path}/pending');
    scratch = Directory('${dir.path}/scratch')..createSync();
    dbPath = '${dir.path}/egg_tray_counter.db';
    wait = NoWait();
  });

  tearDown(() async {
    for (var i = 0; i < 5; i++) {
      try {
        dir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        // Windows may still hold the database file for a moment.
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  HistoryDatabase openHistory() =>
      HistoryDatabase(factory: databaseFactoryFfi, path: dbPath);

  DiskPendingScanStore storeFor(HistoryDatabase history) =>
      DiskPendingScanStore(
        database: history,
        root: () async => pendingRoot,
        scratch: () async => scratch,
      );

  ScanJobRunner runner(FakeServer server, HistoryDatabase history) =>
      ScanJobRunner(
        api: ApiClient(
          _base,
          adapter: server,
          deviceAuth: DeviceAuth(store: InMemorySecretStore()),
          delay: wait.call,
          now: wait.clock,
        ),
        pending: storeFor(history),
        history: history,
      );

  test('an unfinished scan survives a relaunch and resumes by asking for its '
      'result first', () async {
    final session = photoSession(photos, 'p1');
    final history = openHistory();
    final failing = FakeServer({
      'GET /health': [reply(jobsHealth)],
      _count: [dropBeforeBody()],
    });
    await expectLater(
      runner(failing, history).run(session, onProgress: (_, _) {}),
      throwsA(
        isA<ScanFailure>().having(
          (f) => f.kind,
          'kind',
          ScanFailureKind.uploadFailed,
        ),
      ),
    );
    expect(failing.calls(_count), hasLength(4));
    final row = await history.pending('p1');
    expect(row, isNotNull);
    expect(row!.state, 'failed');
    expect(row.attempts, 1);
    expect(row.lastErrorClass, 'upload_failed');
    expect(row.bodySent, isFalse);
    for (final name in ['left.jpg', 'right.jpg', 'straight.jpg', 'session.json']) {
      expect(File('${pendingRoot.path}/p1/$name').existsSync(), isTrue, reason: name);
    }
    await history.close();
    // Android killed the app; the operator's own photo files are gone too.
    for (final path in session.paths.values) {
      File(path).deleteSync();
    }

    // Next launch: the home screen finds it and the operator resumes.
    final relaunched = openHistory();
    final store = storeFor(relaunched);
    final latest = await store.latest();
    expect(latest?.scanId, 'p1');
    final restored = await store.restore('p1');
    expect(restored.scanId, 'p1');
    expect(restored.isComplete, isTrue);
    expect(restored.cellIds, {'left': 'A1'});
    expect(restored.constraintEvidence['right'], '{"view":"right"}');
    expect(restored.pathFor(CaptureView.left), startsWith(scratch.path));

    final server = FakeServer({
      'GET /health': [reply(jobsHealth)],
      'GET /v1/scans/p1/result': [reply(detail('scan_not_found'), 404)],
      _count: [reply(scanBody('p1'))],
    });
    final result = await runner(
      server,
      relaunched,
    ).run(restored, onProgress: (_, _) {}, resume: true);
    expect(result.scanId, 'p1');
    // Asked first; uploaded only because the server had nothing.
    expect(server.log, ['GET /health', 'GET /v1/scans/p1/result', _count]);
    final saved = await relaunched.recent();
    expect(saved.single.scanId, 'p1');
    expect(saved.single.appVersion, kAppVersion);
    expect(saved.single.trayCount, 59);
    expect(await relaunched.pending('p1'), isNull);
    expect(Directory('${pendingRoot.path}/p1').existsSync(), isFalse);
    await relaunched.close();
  });

  test('resume uses the stored result and uploads nothing', () async {
    final history = openHistory();
    final session = photoSession(photos, 'p2');
    final lost = FakeServer({
      'GET /health': [reply(jobsHealth)],
      _count: [timeoutAfterBody()],
      'GET /v1/scans/p2/result': [dropBeforeBody()],
    });
    await expectLater(
      runner(lost, history).run(session, onProgress: (_, _) {}),
      throwsA(
        isA<ScanFailure>().having(
          (f) => f.kind,
          'kind',
          ScanFailureKind.resultLost,
        ),
      ),
    );
    final row = await history.pending('p2');
    expect(row!.bodySent, isTrue);
    expect(row.lastErrorClass, 'result_lost');

    final server = FakeServer({
      'GET /health': [reply(jobsHealth)],
      'GET /v1/scans/p2/result': [reply(scanBody('p2'))],
    });
    final restored = await storeFor(history).restore('p2');
    final result = await runner(
      server,
      history,
    ).run(restored, onProgress: (_, _) {}, resume: true);
    expect(result.scanId, 'p2');
    expect(server.calls(_count), isEmpty);
    expect(await history.pending('p2'), isNull);
    await history.close();
  });

  test('a failure on the phone after a 200 never uploads again', () async {
    final history = _FlakyHistory(factory: databaseFactoryFfi, path: dbPath);
    final session = photoSession(photos, 'p3');
    final server = FakeServer({
      'GET /health': [reply(jobsHealth)],
      _count: [reply(scanBody('p3'))],
    });
    final jobs = runner(server, history);
    await expectLater(
      jobs.run(session, onProgress: (_, _) {}),
      throwsA(
        isA<ScanFailure>()
            .having((f) => f.kind, 'kind', ScanFailureKind.appError)
            .having((f) => f.message, 'message', contains('not sent again')),
      ),
    );
    expect(server.requests, hasLength(2));
    final row = await history.pending('p3');
    expect(row!.lastErrorClass, 'app_error');
    expect(File('${pendingRoot.path}/p3/result.json').existsSync(), isTrue);

    // TRY AGAIN: the kept answer is saved; nothing goes to the server.
    final result = await jobs.run(session, onProgress: (_, _) {});
    expect(result.scanId, 'p3');
    expect(server.requests, hasLength(2));
    expect((await history.recent()).single.scanId, 'p3');
    expect(await history.pending('p3'), isNull);
    await history.close();
  });

  test('an answer for another scan id is never saved', () async {
    final history = openHistory();
    final server = FakeServer({
      'GET /health': [reply(jobsHealth)],
      _count: [reply(scanBody('someone-else'))],
    });
    await expectLater(
      runner(server, history).run(
        photoSession(photos, 'p4'),
        onProgress: (_, _) {},
      ),
      throwsA(
        isA<ScanFailure>()
            .having((f) => f.kind, 'kind', ScanFailureKind.appError)
            .having((f) => f.message, 'message', contains('different scan')),
      ),
    );
    expect(await history.recent(), isEmpty);
    expect(server.calls(_count), hasLength(1));
    await history.close();
  });

  test('an answer that does not fit the scan is not kept: TRY AGAIN and '
      'RESUME ask the server again', () async {
    final history = openHistory();
    final session = photoSession(photos, 'p6');
    final wrong = FakeServer({
      'GET /health': [reply(jobsHealth)],
      _count: [reply(scanBody('p6', cellIds: const {'left': 'ZZ'}))],
    });
    await expectLater(
      runner(wrong, history).run(session, onProgress: (_, _) {}),
      throwsA(
        isA<ScanFailure>()
            .having((f) => f.kind, 'kind', ScanFailureKind.appError)
            .having((f) => f.message, 'message', contains('TRY AGAIN')),
      ),
    );
    expect(File('${pendingRoot.path}/p6/result.json').existsSync(), isFalse);
    expect((await history.pending('p6'))!.lastErrorClass, 'app_error');

    // The backend is fixed: the next try asks it (the photos were sent).
    final fixed = FakeServer({
      'GET /health': [reply(jobsHealth)],
      'GET /v1/scans/p6/result': [reply(scanBody('p6'))],
    });
    final result = await runner(
      fixed,
      history,
    ).run(session, onProgress: (_, _) {}, resume: true);
    expect(result.scanId, 'p6');
    expect(fixed.log, ['GET /health', 'GET /v1/scans/p6/result']);
    expect(await history.pending('p6'), isNull);
    await history.close();
  });

  test('a wrong answer already kept on the phone is dropped, not replayed',
      () async {
    final history = openHistory();
    final session = photoSession(photos, 'p7');
    final store = storeFor(history);
    await store.create(session);
    // Kept by a build that stored before checking.
    await store.storeResult(
      'p7',
      scanBody('p7', cellIds: const {'left': 'ZZ'}),
    );
    final server = FakeServer({
      'GET /health': [reply(jobsHealth)],
      'GET /v1/scans/p7/result': [reply(scanBody('p7'))],
    });
    final result = await runner(
      server,
      history,
    ).run(session, onProgress: (_, _) {}, resume: true);
    expect(result.scanId, 'p7');
    expect(server.calls('GET /v1/scans/p7/result'), hasLength(1));
    expect((await history.recent()).single.scanId, 'p7');
    await history.close();
  });

  test('a resumed scan whose photos never left is asked for once and then '
      'uploaded, not waited for', () async {
    final history = openHistory();
    final session = photoSession(photos, 'q2');
    final failing = FakeServer({
      'GET /health': [reply(jobsHealth)],
      _count: [dropBeforeBody()],
    });
    await expectLater(
      runner(failing, history).run(session, onProgress: (_, _) {}),
      throwsA(
        isA<ScanFailure>().having(
          (f) => f.kind,
          'kind',
          ScanFailureKind.uploadFailed,
        ),
      ),
    );
    expect((await history.pending('q2'))!.bodySent, isFalse);

    // RESUME on a link that drops the question.
    final server = FakeServer({
      'GET /health': [reply(jobsHealth)],
      'GET /v1/scans/q2/result': [dropBeforeBody()],
      _count: [reply(scanBody('q2'))],
    });
    final result = await runner(
      server,
      history,
    ).run(session, onProgress: (_, _) {}, resume: true);
    expect(result.scanId, 'q2');
    expect(server.calls('GET /v1/scans/q2/result'), hasLength(1));
    expect(server.calls(_count), hasLength(1));
    await history.close();
  });

  test('a busy server (429) keeps the unfinished scan for a retry', () async {
    final history = openHistory();
    final server = FakeServer({
      'GET /health': [reply(jobsHealth)],
      _count: [reply(detail('rate_limited'), 429)],
    });
    await expectLater(
      runner(server, history).run(
        photoSession(photos, 'p8'),
        onProgress: (_, _) {},
      ),
      throwsA(
        isA<ScanFailure>().having(
          (f) => f.kind,
          'kind',
          ScanFailureKind.uploadFailed,
        ),
      ),
    );
    final row = await history.pending('p8');
    expect(row, isNotNull);
    expect(row!.lastErrorClass, 'upload_failed');
    expect(Directory('${pendingRoot.path}/p8').existsSync(), isTrue);
    await history.close();
  });

  test('a rejected scan is not kept for resume', () async {
    final history = openHistory();
    final server = FakeServer({
      'GET /health': [reply(jobsHealth)],
      _count: [reply(detail('duplicate_view'), 422)],
    });
    await expectLater(
      runner(server, history).run(
        photoSession(photos, 'p5'),
        onProgress: (_, _) {},
      ),
      throwsA(
        isA<ScanFailure>().having(
          (f) => f.kind,
          'kind',
          ScanFailureKind.rejected,
        ),
      ),
    );
    expect(await history.pending('p5'), isNull);
    expect(Directory('${pendingRoot.path}/p5').existsSync(), isFalse);
    await history.close();
  });

  test('history v1 to v2 keeps old rows, shows them as unknown and never '
      'rewrites them', () async {
    final v1 = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute('''
          CREATE TABLE scans (
            scan_id TEXT PRIMARY KEY,
            created_at TEXT NOT NULL,
            status TEXT NOT NULL,
            tray_count INTEGER,
            egg_count INTEGER,
            model_version TEXT NOT NULL,
            latency_ms INTEGER NOT NULL
          )
        '''),
      ),
    );
    await v1.insert('scans', {
      'scan_id': 'old-1',
      'created_at': '2026-10-12T10:00:00.000Z',
      'status': 'rescan_required',
      'tray_count': null,
      'egg_count': null,
      'model_version': 'projec-mutta/2',
      'latency_ms': 900,
    });
    await v1.insert('scans', {
      'scan_id': 'old-2',
      'created_at': '2026-10-14T10:00:00.000Z',
      'status': 'estimated',
      'tray_count': 99,
      'egg_count': 2970,
      'model_version': 'projec-mutta/2',
      'latency_ms': 800,
    });
    await v1.close();

    final history = openHistory();
    final rows = {for (final row in await history.recent()) row.scanId: row};
    expect(rows.keys, unorderedEquals(['old-1', 'old-2']));
    expect(rows['old-1']!.appVersion, isNull);
    expect(rows['old-1']!.recordedByOlderApp, isTrue);
    expect(rows['old-1']!.status, 'rescan_required');
    expect(rows['old-2']!.recordedByOlderApp, isFalse);
    expect(rows['old-2']!.trayCount, 99);

    // A save under an old id leaves the old row exactly as it was.
    await history.save(ScanResult.fromJson(scanBody('old-1')));
    final kept = (await history.recent()).firstWhere((r) => r.scanId == 'old-1');
    expect(kept.status, 'rescan_required');
    expect(kept.trayCount, isNull);
    expect(kept.appVersion, isNull);

    // New rows record the app version; the pending table exists.
    await history.save(ScanResult.fromJson(scanBody('new-1')));
    final fresh = (await history.recent()).firstWhere((r) => r.scanId == 'new-1');
    expect(fresh.appVersion, kAppVersion);
    expect(fresh.status, 'estimated');
    expect(fresh.recordedByOlderApp, isFalse);
    await history.insertPending(
      PendingScanRow(scanId: 'x', createdAt: DateTime.now(), state: 'captured'),
    );
    expect((await history.latestPending())?.scanId, 'x');
    await history.close();

    final raw = await databaseFactoryFfi.openDatabase(dbPath);
    expect(await raw.getVersion(), HistoryDatabase.schemaVersion);
    await raw.close();
  });

  testWidgets('an old rescan_required row reads "Unknown - recorded by an '
      'older app"', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              HistoryTile(
                ScanHistoryEntry(
                  scanId: 'old',
                  createdAt: DateTime.utc(2026, 10, 12),
                  status: 'rescan_required',
                  trayCount: null,
                  eggCount: null,
                  modelVersion: 'm',
                  latencyMs: 1,
                ),
              ),
              HistoryTile(
                ScanHistoryEntry(
                  scanId: 'new',
                  createdAt: DateTime.utc(2026, 10, 15),
                  status: 'rescan_required',
                  trayCount: null,
                  eggCount: null,
                  modelVersion: 'm',
                  latencyMs: 1,
                  appVersion: kAppVersion,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Unknown - recorded by an older app'), findsOneWidget);
    expect(find.text('UNKNOWN'), findsOneWidget);
    expect(find.text('Rescan required'), findsOneWidget);
  });
}
