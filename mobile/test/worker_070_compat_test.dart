// Worker 0.7.0 answers (the stacking rule, docs/PLAN_5_MULTI_PHOTO.md) read by this app's 0.6.x parser and block panel:
// Plan 5 Phase 1 gate 8. The fixtures are real Worker output, written offline by scripts/write_worker_070_fixtures.mjs.
import 'dart:convert';
import 'dart:io';

import 'package:egg_tray_counter/features/scan_flow/block_view.dart';
import 'package:egg_tray_counter/models/scan_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ScanResult _load(String name) => ScanResult.fromJson(
  jsonDecode(File('test/fixtures/worker_0_7_0/$name').readAsStringSync())
      as Map<String, dynamic>,
);

String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join(' | ');

Future<void> _pump(WidgetTester tester, ScanResult result) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: BlockPanel(block: result.block!)),
      ),
    ),
  );
}

void main() {
  test('every 0.7.0 answer parses with no error', () {
    for (final name in [
      'fr01_released.json',
      'fr02_taller.json',
      'fr15_no_rule_height.json',
    ]) {
      final result = _load(name);
      expect(result.block, isNotNull, reason: name);
      expect(result.block!.gridContract, '0.7.0', reason: name);
      expect(result.views.keys.toSet(), {'left', 'right', 'straight'});
    }
  });

  testWidgets('a released rule block: hidden stacks drawn as assumed, the '
      'split says "(range not given)", no neighbour range row', (
    tester,
  ) async {
    final result = _load('fr01_released.json');
    final block = result.block!;
    final hidden = block.grid.where((c) => c.hidden == true).toList();
    expect(hidden, hasLength(6));
    for (final cell in hidden) {
      expect(cell.evidenceClass, 'assumed');
      expect(cell.assumedLayers, 20);
      expect(cell.assumedFrom, 'stacking_rule');
    }
    final split = block.split!;
    expect(
      traySplitLine(split, status: block.displayStatus),
      'Counted 171 + Assumed 120 (range not given) = Estimated 291 tray '
      'layers',
    );
    await _pump(tester, result);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('tray-split')), findsOneWidget);
    expect(find.byKey(const ValueKey('range-row')), findsNothing);
    expect(
      find.text("If every hidden stack is there at its neighbours' heights"),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('provisional-panel')), findsNothing);
    final text = _allText(tester);
    // The 0.6.x app does not know the rule: it calls the height assumed, never
    // counted, exact or verified.
    expect(text, contains('an assumed height'));
    expect(text.toLowerCase(), isNot(contains('exact')));
    expect(text.toLowerCase(), isNot(contains('verified')));
  });

  testWidgets('a withheld rule block shows the generic withheld line and no '
      '"depth not proven" panel', (tester) async {
    for (final name in ['fr02_taller.json', 'fr15_no_rule_height.json']) {
      final result = _load(name);
      final block = result.block!;
      expect(block.released, isFalse, reason: name);
      expect(block.provisional, isNull, reason: name);
      expect(block.split, isNull, reason: name);
      await _pump(tester, result);
      expect(tester.takeException(), isNull, reason: name);
      expect(
        find.byKey(const ValueKey('total-withheld')),
        findsOneWidget,
        reason: name,
      );
      expect(
        find.byKey(const ValueKey('provisional-panel')),
        findsNothing,
        reason: name,
      );
      expect(find.byKey(const ValueKey('tray-split')), findsNothing);
      expect(_allText(tester), isNot(contains('DEPTH NOT PROVEN')));
    }
    // The retake names a face the app can show (STRAIGHT, LEFT or RIGHT).
    expect(_load('fr02_taller.json').recommendedView, 'straight');
    expect(
      ['left', 'right'],
      contains(_load('fr15_no_rule_height.json').recommendedView),
    );
  });
}
