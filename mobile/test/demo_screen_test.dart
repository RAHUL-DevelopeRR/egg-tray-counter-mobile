import 'dart:convert';
import 'dart:io';

import 'package:egg_tray_counter/features/demo/demo_screen.dart';
import 'package:egg_tray_counter/models/scan_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ScanResult _result(String asset) => ScanResult.fromJson(
  jsonDecode(File(asset).readAsStringSync()) as Map<String, dynamic>,
);

void main() {
  test('every demo answer is bundled, parses and carries a block', () {
    for (final demo in kDemoCases) {
      final text = File(demo.asset).readAsStringSync();
      expect(text, isNot(contains(r'C:\')), reason: demo.asset);
      expect(text, isNot(contains('"_')), reason: demo.asset);
      expect(_result(demo.asset).block, isNotNull, reason: demo.asset);
    }
  });

  test('4 x 3 block: 105 counted + 60 assumed in 4 hidden stacks = 165', () {
    final block = _result('assets/demo/demo_field_4x3.json').block!;
    expect(block.status, 'estimated');
    expect(block.observedTrays, 105);
    expect(block.computedTrays, 60);
    expect(block.totalTrays, 165);
    final hidden = hiddenStacks(block);
    expect(hidden.map((h) => (h.x, h.y)), [(1, 1), (2, 1), (1, 2), (2, 2)]);
    expect(hidden.every((h) => h.layers == 15), isTrue);
  });

  test('99 row: every stack seen, nothing assumed', () {
    final block = _result('assets/demo/demo_99_block.json').block!;
    expect(block.totalTrays, 99);
    expect(block.computedTrays, 0);
    expect(hiddenStacks(block), isEmpty);
  });

  test('L-100: held back because the sides repeat the front', () {
    final block = _result('assets/demo/demo_l100_refused.json').block!;
    expect(block.status, 'needs_view');
    expect(block.totalTrays, isNull);
    expect(block.conflicts.join(' '), contains('front face again'));
  });

  testWidgets('demo screen walks through the three saved answers', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    // Real file reads never finish inside the test's fake async zone.
    final texts = {
      for (final demo in kDemoCases) demo.asset: File(demo.asset).readAsStringSync(),
    };
    await tester.pumpWidget(
      MaterialApp(home: DemoScreen(load: (asset) async => texts[asset]!)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('demo-banner')), findsOneWidget);
    expect(find.text('Counted 99 = 99 tray layers'), findsOneWidget);

    await tester.tap(find.text('4 × 3 block'));
    await tester.pumpAndSettle();
    expect(
      find.text('Counted 105 + Assumed 60 = Estimated 165 tray layers'),
      findsOneWidget,
    );
    expect(find.textContaining('Stacks no photo can see: 4'), findsOneWidget);

    await tester.tap(find.text('Refused'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('demo-held-back')), findsOneWidget);
    expect(find.byKey(const ValueKey('demo-split')), findsNothing);
  });
}
