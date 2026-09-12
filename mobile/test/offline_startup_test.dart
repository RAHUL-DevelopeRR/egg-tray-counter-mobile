import 'dart:async';

import 'package:egg_tray_counter/app/egg_counter_app.dart';
import 'package:egg_tray_counter/services/history_database.dart';
import 'package:egg_tray_counter/services/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _UnavailableHistory extends HistoryDatabase {
  @override
  Future<List<ScanHistoryEntry>> recent({int limit = 20}) =>
      Completer<List<ScanHistoryEntry>>().future;
}

class _BlankSettings implements SettingsStore {
  @override
  Future<String?> getHeightPilot() async => null;
  @override
  Future<void> setHeightPilot(String json) async {}
  @override
  Future<String> getBaseUrl() async => SettingsStore.defaultBaseUrl;
  @override
  Future<void> setBaseUrl(String value) async {}
}

void main() {
  testWidgets('offline pilot opens without camera setup or backend readiness', (
    tester,
  ) async {
    await tester.pumpWidget(
      EggCounterApp(settings: _BlankSettings(), history: _UnavailableHistory()),
    );
    await tester.pump();
    await tester.tap(find.text('GRID + HEIGHT PILOT'));
    await tester.pumpAndSettle();
    expect(find.text('Grid + height pilot'), findsOneWidget);
    expect(find.text('OFFLINE · MEASUREMENT-ASSISTED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
