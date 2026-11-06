// Worker 0.7.0 answers (the stacking rule, docs/PLAN_5_MULTI_PHOTO.md) in this app. The fixtures are real Worker
// output, written offline by scripts/write_worker_070_fixtures.mjs.
//
// Plan 5 Phase 1 gate 8 (the installed 0.6.1 app reads these answers: "(range not given)", no neighbour range row, no
// "depth not proven" panel) passed against the 0.6.1 panel at commit e6afb48. App 0.7.0 (Phase 2) shows the rule: "=H"
// ghosts, the rule split line, the residual line, the sensitivity row and the rule's own provisional panel.
import 'dart:convert';
import 'dart:io';

import 'package:egg_tray_counter/features/scan_flow/block_view.dart';
import 'package:egg_tray_counter/models/block_result.dart';
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

String _textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

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
  test('every 0.7.0 answer parses, with the rule and its fields', () {
    for (final name in [
      'fr01_released.json',
      'fr02_taller.json',
      'fr15_no_rule_height.json',
    ]) {
      final result = _load(name);
      expect(result.block, isNotNull, reason: name);
      expect(result.block!.gridContract, '0.7.0', reason: name);
      expect(result.block!.rule, isNotNull, reason: name);
      expect(result.views.keys.toSet(), {'left', 'right', 'straight'});
    }
    final block = _load('fr01_released.json').block!;
    final rule = block.rule!;
    expect([rule.applied, rule.height, rule.partner, rule.fullHeights], [
      true,
      20,
      19,
      [19, 20],
    ]);
    final inv = block.inventory!;
    expect([inv.ruleStacks, inv.ruleHeight, inv.ruleTrays, inv.ruleTraysRange], [
      6,
      20,
      120,
      [114, 120],
    ]);
    expect([inv.sensitivityPerLayer, inv.twoPhotoStacks, inv.ruleFullHeights], [
      6,
      2,
      [19, 20],
    ]);
    final split = block.split!;
    expect(split.byRule, isTrue);
    // What app 0.6.x prints for the same answer (gate 8), still true of the parser.
    expect(
      traySplitLine(split),
      'Counted 171 + Assumed 120 (range not given) = Estimated 291 tray layers',
    );
    expect(
      ruleSplitLine(split),
      'Counted 171 + 6 × 20 by the stacking rule = Estimated 291 tray layers',
    );
    final p = _load('fr02_taller.json').block!.rule!.provisional!;
    expect([p.kind, p.countedOnFaces, p.atRuleHeight, p.tallerHeight, p.atTaller],
        ['stack_taller_than_rule_height', 172, 292, 21, 298]);
  });

  testWidgets('a released rule block: "=20" ghosts, the rule split line and '
      'headline, the residual line, the sensitivity row, no neighbour range', (
    tester,
  ) async {
    final result = _load('fr01_released.json');
    final block = result.block!;
    final hidden = block.evidence.where((e) => e.hidden).toList();
    expect(hidden, hasLength(6));
    for (final e in hidden) {
      expect(e.byRule, isTrue);
      expect(cellLook(e).label, '=20');
      expect(evidenceLegendLabel(e), '= full by the stacking rule, not seen');
    }
    await _pump(tester, result);
    expect(tester.takeException(), isNull);
    expect(
      _textOf(tester, 'block-headline'),
      'ESTIMATE: 171 COUNTED + 6 × 20 BY THE STACKING RULE',
    );
    expect(
      _textOf(tester, 'tray-split'),
      'Counted 171 + 6 × 20 by the stacking rule = Estimated 291 tray layers',
    );
    expect(
      _textOf(tester, 'rule-line'),
      'Counted on faces: 171 (2 stacks read the same in two photos). Hidden: '
      '6 stacks × 20 = 120, full by the stacking rule, not seen. Cover trays '
      'are sometimes used: the hidden stacks hold 114–120 tray layers.',
    );
    expect(_textOf(tester, 'rule-residual'), kRuleResidualLine);
    expect(find.byKey(const ValueKey('sensitivity-row')), findsOneWidget);
    expect(find.byKey(const ValueKey('range-row')), findsNothing);
    expect(find.byKey(const ValueKey('assumption-line')), findsNothing);
    expect(find.byKey(const ValueKey('rule-provisional-panel')), findsNothing);
    final text = _allText(tester).toLowerCase();
    // A rule value is never called exact, verified or confirmed.
    for (final banned in ['exact', 'verified', 'confirmed', 'neighbours']) {
      expect(text, isNot(contains(banned)), reason: banned);
    }
    expect(text, contains('= full by the stacking rule, not seen'));
  });

  testWidgets('a withheld rule block: the reason in plain words and the rule '
      'panel with its provisional figures, never a total', (tester) async {
    final taller = _load('fr02_taller.json');
    expect(taller.block!.provisional, isNull);
    await _pump(tester, taller);
    expect(tester.takeException(), isNull);
    expect(
      _textOf(tester, 'total-withheld'),
      "TOTAL WITHHELD: a stack on a face reads taller than the block's full "
      'height; retake the named face',
    );
    expect(find.byKey(const ValueKey('rule-provisional-panel')), findsOneWidget);
    expect(
      _textOf(tester, 'rule-provisional-at-h'),
      'Only if the stacking rule holds at 20: ≈ 292 (286–292 with or without '
      'cover trays)',
    );
    expect(
      _textOf(tester, 'rule-provisional-taller'),
      'If the taller reading (21) is the full height: ≈ 298',
    );
    expect(find.byKey(const ValueKey('tray-split')), findsNothing);
    expect(find.byKey(const ValueKey('provisional-panel')), findsNothing);
    expect(_allText(tester), isNot(contains('DEPTH NOT PROVEN')));

    final none = _load('fr15_no_rule_height.json');
    await _pump(tester, none);
    expect(tester.takeException(), isNull);
    expect(
      _textOf(tester, 'total-withheld'),
      startsWith("TOTAL WITHHELD: the block's full height is not clear"),
    );
    expect(
      _textOf(tester, 'rule-provisional-typical'),
      'At the most common face height (20): ≈ 291',
    );
    expect(find.byKey(const ValueKey('rule-provisional-at-h')), findsNothing);
    // The retake names a face the app can take (STRAIGHT, LEFT or RIGHT).
    expect(taller.recommendedView, 'straight');
    expect(['left', 'right'], contains(none.recommendedView));
  });

  test('every 0.7.0 withheld reason has its own words', () {
    for (final reason in [
      'no_rule_height',
      'one_side_only',
      'stack_taller_than_rule_height',
      'back_corner_below_rule_height',
      'inside_hint_below_rule',
      'rule_height_ambiguous',
      'rule_height_out_of_range',
      'inside_step_up',
      'inside_declared_partial',
      'reference_height_differs',
    ]) {
      expect(
        withheldWords(reason),
        isNot('the photos do not settle the block'),
        reason: reason,
      );
    }
  });

  test('a rule block with declared exceptions adds them apart', () {
    const split = TraySplit(
      counted: 100,
      assumed: 112,
      estimated: 212,
      ruleHeight: 20,
      ruleStacks: 5,
      ruleTrays: 100,
      ruleTraysRange: [95, 105],
    );
    expect(
      ruleSplitLine(split),
      'Counted 100 + 5 × 20 by the stacking rule + 12 declared = Estimated '
      '212 tray layers',
    );
    expect(ruleLine(split), contains('12 tray layers in hidden stacks at the '
        'height you declared.'));
    expect(ruleLine(split), contains('hold 95–105 tray layers'));
  });
}
