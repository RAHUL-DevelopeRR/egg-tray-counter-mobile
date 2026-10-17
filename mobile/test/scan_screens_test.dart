import 'package:egg_tray_counter/app/app_version.dart';
import 'package:egg_tray_counter/features/home/home_screen.dart';
import 'package:egg_tray_counter/features/scan_flow/scan_flow_screen.dart';
import 'package:egg_tray_counter/models/capture_view.dart';
import 'package:egg_tray_counter/models/scan_result.dart';
import 'package:egg_tray_counter/models/scan_session.dart';
import 'package:egg_tray_counter/services/api_client.dart';
import 'package:egg_tray_counter/services/device_auth.dart';
import 'package:egg_tray_counter/services/frame_preflight.dart';
import 'package:egg_tray_counter/services/history_database.dart';
import 'package:egg_tray_counter/services/pending_scans.dart';
import 'package:egg_tray_counter/services/scan_failure.dart';
import 'package:egg_tray_counter/services/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';

const _base = 'https://staging.example.test';

class _Settings implements SettingsStore {
  @override
  Future<String> getBaseUrl() async => _base;
  @override
  Future<void> setBaseUrl(String value) async {}
  @override
  Future<PoseCalibration> getPoseCalibration() async => PoseCalibration.none;
  @override
  Future<void> setPoseCalibration(PoseCalibration calibration) async {}
  @override
  Future<void> clearPoseCalibration() async {}
  @override
  Future<String?> getHeightPilot() async => null;
  @override
  Future<void> setHeightPilot(String json) async {}
}

class _History extends HistoryDatabase {
  final List<ScanResult> saved = [];

  @override
  Future<void> save(
    ScanResult result, {
    String appVersion = kAppVersion,
  }) async => saved.add(result);

  @override
  Future<List<ScanHistoryEntry>> recent({int limit = 20}) async => const [];
}

/// Unfinished scans in memory: rows, sessions and kept answers.
class _Pending implements PendingScanStore {
  final Map<String, PendingScanRow> rows = {};
  final Map<String, ScanSession> sessions = {};
  final Map<String, Map<String, dynamic>> results = {};

  void add(String scanId, {bool bodySent = false, Map<String, dynamic>? kept}) {
    rows[scanId] = PendingScanRow(
      scanId: scanId,
      createdAt: DateTime.utc(2026, 10, 15, 9),
      state: kept != null ? 'result_received' : 'failed',
      bodySent: bodySent,
    );
    sessions[scanId] = _session(scanId);
    if (kept != null) results[scanId] = kept;
  }

  void _update(String scanId, {String? state, String? error, bool? sent}) {
    final row = rows[scanId];
    if (row == null) return;
    rows[scanId] = PendingScanRow(
      scanId: scanId,
      createdAt: row.createdAt,
      state: state ?? row.state,
      attempts: row.attempts,
      lastErrorClass: error ?? row.lastErrorClass,
      bodySent: sent ?? row.bodySent,
    );
  }

  @override
  Future<PendingScanRow?> find(String scanId) async => rows[scanId];
  @override
  Future<PendingScanRow?> latest() async => rows.values.lastOrNull;
  @override
  Future<PendingScanRow> create(ScanSession session) async {
    add(session.scanId);
    return rows[session.scanId]!;
  }

  @override
  Future<void> recordAttempt(String scanId) async =>
      _update(scanId, state: 'uploading');
  @override
  Future<void> markBodySent(String scanId) async => _update(scanId, sent: true);
  @override
  Future<void> markFailed(String scanId, String errorClass) async =>
      _update(scanId, state: 'failed', error: errorClass);
  @override
  Future<void> storeResult(String scanId, Map<String, dynamic> body) async =>
      results[scanId] = body;
  @override
  Future<Map<String, dynamic>?> storedResult(String scanId) async =>
      results[scanId];
  @override
  Future<void> clearResult(String scanId) async => results.remove(scanId);
  @override
  Future<ScanSession> restore(String scanId) async => sessions[scanId]!;
  @override
  Future<void> remove(String scanId) async {
    rows.remove(scanId);
    results.remove(scanId);
  }

  @override
  Future<void> sweep() async {}
}

/// A complete session whose photo files are never read (nothing here
/// uploads): LEFT carries cell ID A1, as in [scanBody].
ScanSession _session(String scanId) {
  final session = ScanSession(scanId: scanId);
  for (final view in CaptureView.values) {
    session.setPath(
      view,
      '/no-such-dir/${view.name}-$scanId.jpg',
      cellId: view == CaptureView.left ? 'A1' : '',
      evidence: '{"view":"${view.name}"}',
    );
  }
  return session;
}

/// Labels of every button on screen.
List<String> _buttons(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data ?? '')
    .toList();

String _title(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('failure-title'))).data!;

void main() {
  late NoWait wait;
  late DeviceAuth auth;
  late _Pending pending;
  late _History history;

  setUp(() {
    wait = NoWait();
    auth = DeviceAuth(store: InMemorySecretStore());
    pending = _Pending();
    history = _History();
  });

  ApiClient Function(String) clientFor(FakeServer server) =>
      (base) => ApiClient(
        base,
        adapter: server,
        deviceAuth: auth,
        delay: wait.call,
        now: wait.clock,
      );

  void tallView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('failure screen per class (a resumed scan through a fake server)', () {
    Future<void> resume(
      WidgetTester tester,
      FakeServer server,
      String scanId, {
      bool bodySent = false,
    }) async {
      tallView(tester);
      pending.add(scanId, bodySent: bodySent);
      await tester.pumpWidget(
        MaterialApp(
          home: ScanFlowScreen(
            cameras: const [],
            settings: _Settings(),
            history: history,
            pendingScans: pending,
            uploadPhotos: true,
            resume: pending.sessions[scanId],
            clientFor: clientFor(server),
          ),
        ),
      );
      // A resume claims nothing about the photos before the server answers.
      expect(find.text('Contacting the server...'), findsOneWidget);
      await tester.pumpAndSettle();
    }

    testWidgets('rejected (403 scan_forbidden): no retry, only a new scan or '
        'a retake, and the scan is forgotten', (tester) async {
      final server = FakeServer({
        'GET /health': [reply(jobsHealth)],
        'GET /v1/scans/f1/result': [
          reply(
            detail('scan_forbidden', 'This scan belongs to another device'),
            403,
          ),
        ],
      });
      await resume(tester, server, 'f1');
      expect(_title(tester), 'SCAN REJECTED');
      expect(
        _buttons(tester),
        unorderedEquals([
          'NEW SCAN',
          'RETAKE LEFT',
          'RETAKE RIGHT',
          'RETAKE STRAIGHT',
          'CLOSE',
        ]),
      );
      expect(pending.rows, isEmpty);
    });

    testWidgets('not authorised: CHECK APPROVAL only', (tester) async {
      final server = FakeServer({
        'GET /health': [reply(jobsHealth)],
        'GET /v1/scans/f2/result': [reply(detail('device_pending'), 403)],
      });
      await resume(tester, server, 'f2');
      expect(_title(tester), 'PHONE NOT AUTHORISED');
      expect(_buttons(tester), [
        'CHECK APPROVAL',
        'CLOSE - RESUME LATER FROM HOME',
      ]);
      expect(pending.rows['f2']?.lastErrorClass, 'not_authorised');
    });

    testWidgets('an unexpected answer is a processing failure with RETRY, and '
        'the scan is kept', (tester) async {
      final server = FakeServer({
        'GET /health': [reply(jobsHealth)],
        'GET /v1/scans/f3/result': [reply(detail('teapot'), 418)],
      });
      await resume(tester, server, 'f3');
      expect(_title(tester), 'PROCESSING FAILED');
      expect(_buttons(tester), ['RETRY', 'CLOSE - RESUME LATER FROM HOME']);
      expect(pending.rows['f3']?.lastErrorClass, 'processing_failed');
    });

    testWidgets('an answer for another scan is an app error with TRY AGAIN, '
        'and is not kept', (tester) async {
      final server = FakeServer({
        'GET /health': [reply(jobsHealth)],
        'GET /v1/scans/f4/result': [reply(scanBody('someone-else'))],
      });
      await resume(tester, server, 'f4');
      expect(_title(tester), 'APP ERROR');
      expect(_buttons(tester), ['TRY AGAIN', 'CLOSE - RESUME LATER FROM HOME']);
      expect(pending.results, isEmpty);
    });

    testWidgets('no server: upload failed with RETRY UPLOAD', (tester) async {
      final server = FakeServer({
        'GET /health': [dropBeforeBody()],
      });
      await resume(tester, server, 'f5');
      expect(_title(tester), 'UPLOAD FAILED');
      expect(_buttons(tester), [
        'RETRY UPLOAD',
        'CLOSE - RESUME LATER FROM HOME',
      ]);
    });

    testWidgets('photos sent, no answer for 3 minutes: KEEP WAITING and SEND '
        'PHOTOS AGAIN', (tester) async {
      final server = FakeServer({
        'GET /health': [reply(jobsHealth)],
        'GET /v1/scans/f6/result': [dropBeforeBody()],
      });
      await resume(tester, server, 'f6', bodySent: true);
      expect(_title(tester), 'RESULT NOT RECEIVED YET');
      expect(_buttons(tester), [
        'KEEP WAITING',
        'SEND PHOTOS AGAIN',
        'CLOSE - RESUME LATER FROM HOME',
      ]);
      expect(wait.elapsed, greaterThanOrEqualTo(const Duration(minutes: 3)));
      expect(server.log.where((r) => r.startsWith('POST')), isEmpty);
    });

    testWidgets('a stored result finishes the scan', (tester) async {
      final server = FakeServer({
        'GET /health': [reply(jobsHealth)],
        'GET /v1/scans/f7/result': [reply(scanBody('f7'))],
      });
      await resume(tester, server, 'f7', bodySent: true);
      expect(find.text('Scan result'), findsOneWidget);
      expect(history.saved.single.scanId, 'f7');
      expect(pending.rows, isEmpty);
    });

    testWidgets(
      'a server that keeps no results offers only SEND PHOTOS AGAIN',
      (tester) async {
        tallView(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ScanFailurePane(
                failure: const ScanFailure(
                  ScanFailureKind.resultLost,
                  'm',
                  serverKeepsResult: false,
                ),
                device: null,
                displayCode: null,
                onRetry: () {},
                onKeepWaiting: () {},
                onSendAgain: () {},
                onCheckApproval: () {},
                onRetake: (_) {},
                onNewScan: () {},
                onClose: () {},
              ),
            ),
          ),
        );
        expect(_title(tester), 'RESULT NOT RECEIVED');
        expect(_buttons(tester), [
          'SEND PHOTOS AGAIN',
          'CLOSE - RESUME LATER FROM HOME',
        ]);
      },
    );
  });

  group('home screen', () {
    Future<void> openHome(WidgetTester tester, FakeServer server) async {
      tallView(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            settings: _Settings(),
            history: history,
            pendingScans: pending,
            clientFor: clientFor(server),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('RESUME finishes a scan whose result is kept on the phone '
        'without the server', (tester) async {
      final server = FakeServer({
        'GET /health': [dropBeforeBody()],
      });
      pending.add('h1', bodySent: true, kept: scanBody('h1'));
      // No camera on the test host: RESUME falls back to the gallery screen.
      const camera = MethodChannel('plugins.flutter.io/camera');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        camera,
        (_) async => <Object>[],
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          camera,
          null,
        ),
      );
      await openHome(tester, server);
      expect(find.textContaining('SERVER NOT REACHED'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('resume-scan')));
      await tester.pumpAndSettle();
      expect(find.text('Scan result'), findsOneWidget);
      expect(history.saved.single.scanId, 'h1');
      expect(pending.rows, isEmpty);
      expect(server.log.where((r) => r != 'GET /health'), isEmpty);
    });

    testWidgets('DISCARD forgets the unfinished scan after a confirmation', (
      tester,
    ) async {
      final server = FakeServer({
        'GET /health': [reply(openHealth)],
      });
      pending.add('h2');
      await openHome(tester, server);
      expect(find.byKey(const ValueKey('resume-scan')), findsOneWidget);
      await tester.tap(find.text('DISCARD UNFINISHED SCAN'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('DISCARD'));
      await tester.pumpAndSettle();
      expect(pending.rows, isEmpty);
      expect(find.byKey(const ValueKey('resume-scan')), findsNothing);
    });

    testWidgets('a device check that gets no answer does not block a scan', (
      tester,
    ) async {
      final server = FakeServer({
        'GET /health': [reply(jobsHealth)],
        'POST /v1/devices': [dropBeforeBody()],
      });
      await openHome(tester, server);
      expect(find.byKey(const ValueKey('device-status')), findsOneWidget);
      expect(find.textContaining('DEVICE NOT CHECKED'), findsOneWidget);
      await tester.tap(find.textContaining('GALLERY'));
      await tester.pumpAndSettle();
      expect(find.text('Upload photos'), findsOneWidget);
    });

    testWidgets('a phone the server says is pending cannot start a scan', (
      tester,
    ) async {
      final server = FakeServer({
        'GET /health': [reply(jobsHealth)],
        'POST /v1/devices': [
          reply({'status': 'pending'}, 201),
        ],
        'GET /v1/devices/me': [reply(detail('device_pending'), 403)],
      });
      await openHome(tester, server);
      await tester.tap(find.textContaining('GALLERY'));
      await tester.pumpAndSettle();
      expect(find.text('Upload photos'), findsNothing);
      expect(find.textContaining('waiting for approval'), findsWidgets);
    });
  });
}
