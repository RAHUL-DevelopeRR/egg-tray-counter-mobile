import 'package:egg_tray_counter/app/app_version.dart';
import 'package:egg_tray_counter/features/scan_flow/manual_count_screen.dart';
import 'package:egg_tray_counter/models/scan_result.dart';
import 'package:egg_tray_counter/services/api_client.dart';
import 'package:egg_tray_counter/services/device_auth.dart';
import 'package:egg_tray_counter/services/manual_count_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_server.dart';

const _route = 'POST /v1/scans/c1/manual-count';

void main() {
  testWidgets('a resend of the same counts keeps its count_id; a correction '
      'gets a new one', (tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final server = FakeServer({
      'GET /health': [reply(jobsHealth)],
      _route: [
        reply({'detail': {'code': 'archive_unavailable', 'message': 'busy'}}, 503),
        reply({'stored': true, 'replayed': false, 'totals': {'filled': 59, 'empty': 0}}),
      ],
    });
    final client = ApiClient(
      'https://staging.example.test',
      adapter: server,
      deviceAuth: DeviceAuth(store: InMemorySecretStore()),
      delay: NoWait().call,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ManualCountScreen(
          result: ScanResult.fromJson(scanBody('c1', cellIds: const {})),
          repository: InMemoryManualCountRepository(),
          baseUrl: 'https://staging.example.test',
          client: client,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'B09');
    await tester.tap(find.text('SAVE AND SEND TO SERVER'));
    await tester.pumpAndSettle();
    expect(find.textContaining('sending failed'), findsOneWidget);

    // Same counts again: a retry of the same save.
    await tester.tap(find.text('SAVE AND SEND TO SERVER'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sent to server'), findsOneWidget);
    final first = server.calls(_route)[0].json;
    final second = server.calls(_route)[1].json;
    expect(second['count_id'], first['count_id']);
    expect(second['created_at'], first['created_at']);
    expect(first['app_total'], 59);
    expect(first['app_version'], kAppVersion);
    expect(
      first['count_id'],
      matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
    );
    expect(DateTime.parse(first['created_at'] as String).isUtc, isTrue);

    // A correction after a successful send is a new count.
    await tester.enterText(find.byKey(const ValueKey('filled-0,0')), '58');
    await tester.tap(find.text('SEND AGAIN (CORRECTION)'));
    await tester.pumpAndSettle();
    final third = server.calls(_route)[2].json;
    expect(third['count_id'], isNot(first['count_id']));
    expect(
      DateTime.parse(third['created_at'] as String).isBefore(
        DateTime.parse(first['created_at'] as String),
      ),
      isFalse,
    );
  });

  Future<FakeServer> openScreen(
    WidgetTester tester,
    List<Answer> answers,
  ) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final server = FakeServer({
      'GET /health': [reply(jobsHealth)],
      _route: answers,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ManualCountScreen(
          result: ScanResult.fromJson(scanBody('c1', cellIds: const {})),
          repository: InMemoryManualCountRepository(),
          baseUrl: 'https://staging.example.test',
          client: ApiClient(
            'https://staging.example.test',
            adapter: server,
            deviceAuth: DeviceAuth(store: InMemorySecretStore()),
            delay: NoWait().call,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'B09');
    return server;
  }

  testWidgets('a refused send is not repeated as it was: the next send of the '
      'same counts is a new count with the current time', (tester) async {
    final server = await openScreen(tester, [
      reply(
        detail(
          'invalid_created_at',
          "created_at is in the future; check the phone's clock",
        ),
        422,
      ),
      reply({'stored': true, 'replayed': false, 'is_latest': true}),
    ]);
    await tester.tap(find.text('SAVE AND SEND TO SERVER'));
    await tester.pumpAndSettle();
    expect(find.textContaining("check the phone's clock"), findsOneWidget);

    // The operator fixes the clock and sends the same counts again.
    await tester.tap(find.text('SAVE AND SEND TO SERVER'));
    await tester.pumpAndSettle();
    final first = server.calls(_route)[0].json;
    final second = server.calls(_route)[1].json;
    expect(second['count_id'], isNot(first['count_id']));
    expect(second['cells'], first['cells']);
    expect(find.textContaining('Sent to server'), findsOneWidget);
  });

  testWidgets('a count the server stores but does not keep as the latest '
      'says so instead of "Sent to server"', (tester) async {
    await openScreen(tester, [
      reply({
        'stored': true,
        'replayed': false,
        'is_latest': false,
        'totals': {'filled': 59, 'empty': 0},
      }),
    ]);
    await tester.tap(find.text('SAVE AND SEND TO SERVER'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sent to server'), findsNothing);
    expect(find.textContaining('later count for this scan'), findsOneWidget);
    expect(find.text('SEND AGAIN (CORRECTION)'), findsOneWidget);
  });
}
