import 'dart:convert';

import 'package:egg_tray_counter/features/grid_height/grid_height_screen.dart';
import 'package:egg_tray_counter/models/height_calibration.dart';
import 'package:egg_tray_counter/services/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements SettingsStore {
  String? data;
  bool failWrites = false;
  @override
  Future<String> getBaseUrl() async => SettingsStore.defaultBaseUrl;
  @override
  Future<void> setBaseUrl(String value) async => throw UnimplementedError();
  @override
  Future<String?> getHeightPilot() async => data;
  @override
  Future<void> setHeightPilot(String json) async {
    if (failWrites) throw StateError('test disk unavailable');
    data = json;
  }
}

void main() {
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    if (finder.hitTestable().evaluate().isNotEmpty) return;
    final scrollable = find.byType(Scrollable).first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: scrollable,
      maxScrolls: 30,
    );
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String key, String text) async {
    final finder = find.byKey(ValueKey(key));
    await reveal(tester, finder);
    await tester.enterText(finder, text);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await reveal(tester, finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  _MemoryStore preparedStore() => _MemoryStore()
    ..data = jsonEncode({
      'schema': 1,
      'session_id': '2026-09-10T10:00:00.000Z',
      'records': [],
      'calibration': HeightCalibration(
        profile: 'SYNTHETIC TEST ONLY',
        heights: {1: 6, 5: 26, 10: 51, 20: 101},
        errorCm: 0.1,
      ).toJson(),
    });
  Future<void> measure(WidgetTester tester) async {
    await enter(tester, 'cell', 'a1');
    await enter(tester, 'height', '76');
    final checkbox = find.byType(CheckboxListTile);
    await reveal(tester, checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    await tap(tester, 'CHECK HEIGHT');
  }

  testWidgets('fresh pilot has no fictional calibration and cannot count', (
    tester,
  ) async {
    final store = _MemoryStore();
    await tester.pumpWidget(MaterialApp(home: GridHeightScreen(store: store)));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('h1')))
          .controller!
          .text,
      isEmpty,
    );
    await reveal(tester, find.byKey(const ValueKey('checkHeight')));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('checkHeight')))
          .onPressed,
      isNull,
    );
    await tap(tester, 'SAVE CALIBRATION');
    expect(
      find.textContaining('11–200 manually counted trays'),
      findsOneWidget,
    );
    for (final entry in {
      'profile': 'SYNTHETIC TEST ONLY',
      'h1': '6',
      'h5': '26',
      'h10': '51',
      'maxCount': '20',
      'hMax': '101',
      'error': '0.1',
    }.entries) {
      await enter(tester, entry.key, entry.value);
    }
    await tap(tester, 'SAVE CALIBRATION');
    expect(
      jsonDecode(store.data!)['calibration']['profile'],
      'SYNTHETIC TEST ONLY',
    );
  });

  testWidgets(
    'saves physical truth even when estimate is wrong; cell update never double counts',
    (tester) async {
      final store = preparedStore();
      await tester.pumpWidget(
        MaterialApp(home: GridHeightScreen(store: store)),
      );
      await tester.pumpAndSettle();
      await measure(tester);
      expect(find.text('Candidate: 15 trays'), findsOneWidget);
      await tap(tester, 'SAVE PHYSICAL RECOUNT');
      expect((jsonDecode(store.data!)['records'] as List), isEmpty);
      await enter(tester, 'physical', '16');
      await tap(tester, 'SAVE PHYSICAL RECOUNT');
      final row = (jsonDecode(store.data!)['records'] as List).single;
      expect(row['estimated_count'], 15);
      expect(row['physical_count'], 16);
      expect(row['auto_verified'], isFalse);
      expect(row['cell_id'], 'A1');
      await measure(tester);
      await enter(tester, 'physical', '15');
      await tap(tester, 'SAVE PHYSICAL RECOUNT');
      await tap(tester, 'CONFIRM');
      expect((jsonDecode(store.data!)['records'] as List).length, 2);
      expect(find.text('4. Recorded cells: 15 trays'), findsOneWidget);
      await tap(tester, 'START NEW TALLY');
      await tap(tester, 'CONFIRM');
      expect(find.text('4. Recorded cells: 0 trays'), findsOneWidget);
      expect((jsonDecode(store.data!)['records'] as List).length, 2);
    },
  );

  testWidgets('write failure retains unsaved recount and reports failure', (
    tester,
  ) async {
    final store = preparedStore()..failWrites = true;
    final before = store.data;
    await tester.pumpWidget(MaterialApp(home: GridHeightScreen(store: store)));
    await tester.pumpAndSettle();
    await measure(tester);
    await enter(tester, 'physical', '15');
    await tap(tester, 'SAVE PHYSICAL RECOUNT');
    expect(store.data, before);
    expect(find.textContaining('Not saved:'), findsOneWidget);
    expect(find.text('Candidate: 15 trays'), findsOneWidget);
  });
}
