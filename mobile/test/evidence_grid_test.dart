import 'dart:ui' as ui;

import 'package:egg_tray_counter/features/scan_flow/block_view.dart';
import 'package:egg_tray_counter/models/block_result.dart';
import 'package:egg_tray_counter/models/scan_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/grid_06_fixtures.dart';

/// A canvas that only records what is drawn on it.
class _RecordingCanvas implements Canvas {
  final List<Invocation> calls = [];

  int count(Symbol member) => calls.where((c) => c.memberName == member).length;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    return null;
  }
}

/// An older (0.5) grid cell: status, presence and sources only.
Map<String, dynamic> _cell05(
  int x,
  int y,
  String status, {
  int? z = 20,
  bool? present = true,
  List<String> sources = const ['observed'],
}) => {
  'x': x,
  'y': y,
  'status': status,
  'stack_present': present,
  'z_layers': z,
  'measurement_sources': sources,
};

/// An older (0.4.x) cell.
Map<String, dynamic> _cell04(
  int x,
  int y,
  String status,
  int? layers, {
  String? source,
  bool? verified,
}) => {
  'x': x,
  'y': y,
  'status': status,
  'layers': layers,
  'source': ?source,
  'verified': ?verified,
};

Map<String, dynamic> _block04({
  required List<Map<String, dynamic>> cells,
  required int observed,
  required int computed,
  required int? total,
  int width = 3,
  int depth = 2,
  String? status,
}) => {
  'contract': 'block_model_v1',
  'status': ?status,
  'width': width,
  'depth': depth,
  'faces_used': ['straight', 'left', 'right'],
  'typical_layers': 20,
  'cells': cells,
  'observed_trays': observed,
  'computed_trays': computed,
  'total_trays': total,
  'total_eggs': total == null ? null : total * 30,
  'fully_observed': computed == 0,
  'faces_consistent': true,
  'conflicts': <Object>[],
  'rescan_cells': <Object>[],
  'note': 'n',
};

/// A 4 x 4 0.6.0 grid holding every evidence class at least once (a painter
/// fixture, not a physical case).
BlockResult _everyClass() => BlockResult.fromJson({
  ...h2Block06(),
  'status': 'conflict',
  'total_trays': null,
  // A 0.6.0 server sends no counted figures for a block it withholds.
  'inventory': null,
  'width': 4,
  'depth': 4,
  'grid': [
    [
      measured06(0, 0, 20),
      measured06(1, 0, 19, single: true),
      cell06(2, 0, 'seen_empty', legacy: 'missing', z: 0, present: false),
      measured06(3, 0, 20),
    ],
    [
      measured06(0, 1, 20),
      assumed06(
        1,
        1,
        20,
        [19, 20],
        [
          [1, 0, 19],
          [0, 1, 20],
        ],
      ),
      cell06(
        2,
        1,
        'top_step',
        legacy: 'unknown',
        z: null,
        sources: const ['top_view'],
        hidden: true,
        range: [1, 20],
        tap: 'step_down',
        flags: const ['step_down_count_unknown'],
      ),
      measured06(3, 1, 20),
    ],
    [
      measured06(0, 2, 20),
      cell06(
        1,
        2,
        'top_present',
        legacy: 'top_view',
        z: 20,
        hidden: true,
        assumed: 20,
        range: [20, 20],
        tap: 'present',
      ),
      cell06(
        2,
        2,
        'top_step',
        legacy: 'top_view',
        z: 21,
        hidden: true,
        assumed: 21,
        range: [21, null],
        tap: 'step_up',
        flags: const ['step_up_count_unknown'],
      ),
      measured06(3, 2, 20),
    ],
    [
      cell06(0, 3, 'conflict', legacy: 'conflict', z: null, present: null),
      cell06(
        1,
        3,
        'top_missing',
        legacy: 'top_view',
        z: 0,
        present: false,
        hidden: true,
        tap: 'missing',
      ),
      cell06(
        2,
        3,
        'declared_missing',
        legacy: 'declared',
        z: 0,
        present: false,
        sources: const ['declared'],
        hidden: true,
      ),
      measured06(3, 3, 20),
    ],
  ],
});

String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join(' | ');

Future<void> _pumpPanel(WidgetTester tester, BlockResult block) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: BlockPanel(block: block)),
      ),
    ),
  );
}

void main() {
  group('0.6.0 parsing', () {
    test('every new cell field parses', () {
      final block = BlockResult.fromJson(h2Block06());
      expect(block.gridContract, '0.6.0');
      expect(block.depthBasis, 'declaration');
      expect(block.suggestedInputs, isEmpty);
      final hidden = block.grid.firstWhere((c) => c.x == 1 && c.y == 2);
      expect(hidden.evidenceClass, 'assumed');
      expect(hidden.hidden, isTrue);
      expect(hidden.assumedLayers, 19);
      expect(hidden.assumedRange, [18, 20]);
      expect(hidden.assumedFrom, 'neighbours');
      expect(hidden.neighbours.map((n) => (n.x, n.y, n.layers)), [
        (1, 0, 19),
        (0, 2, 18),
        (3, 2, 20),
      ]);
      expect(hidden.topTap, isNull);
      expect(hidden.flags, isEmpty);
      // Every 0.5.0 field is still there for older screens.
      expect(hidden.status, 'computed');
      expect(hidden.zLayers, 19);
      expect(hidden.measurementSources, ['computed']);
      final step = BlockResult.fromJson(
        verified3x2Block06(tap: 'step_up'),
      ).grid.firstWhere((c) => c.x == 1 && c.y == 1);
      expect(step.assumedRange, [21, null]);
      expect(step.topTap, 'step_up');
      expect(step.flags, ['step_up_count_unknown']);
      final gap = GridCell.fromJson(
        cell06(
          2,
          1,
          'assumed',
          legacy: 'computed',
          z: 18,
          hidden: true,
          assumed: 18,
          range: [0, 20],
          flags: const ['line_of_sight_past_gap'],
          pastGapLayers: 16,
          pastGapScale: 0.75,
        ),
      );
      expect(gap.pastGapLayers, 16);
      expect(gap.pastGapScale, 0.75);
    });

    test('the inventory parses with counted and assumed kept apart', () {
      final inv = BlockResult.fromJson(h2Block06()).inventory!;
      expect(inv.unit, 'tray_layers');
      expect(inv.released, isTrue);
      expect(inv.withheldReason, isNull);
      expect(inv.provisional, isNull);
      expect(inv.countedTrays, 157);
      expect(inv.countedStacks, 8);
      expect(inv.assumedTrays, 79);
      expect(inv.assumedRange, [75, 80]);
      expect(inv.assumedStacks, 4);
      expect(inv.estimatedTotal, 236);
      expect(inv.estimatedRange, [232, 237]);
      expect(inv.hiddenStacks, 4);
      expect(inv.hiddenStacksTopChecked, 0);
      expect(inv.uncheckedHiddenStacks, 4);
      expect(inv.missingStacks, {
        'seen_empty': 0,
        'top_missing': 0,
        'declared_missing': 0,
      });
      expect(inv.coverTrays!.basis, 'unknown');
      expect(inv.note, contains('79 assumed'));
      expect(inv.eligibleEggTrays!.value, isNull);
    });

    test('a withheld block carries provisional figures that are never a '
        'total', () {
      final result = ScanResult.fromJson({
        'scan_id': 's25',
        'status': 'rescan_required',
        'accepted': false,
        'physical_stack_count': null,
        'total_trays': null,
        'eggs_per_tray': 30,
        'total_eggs': null,
        'processing': {'latency_ms': 1, 'model_version': 'm'},
        'views': <String, Object>{},
        'stacks': <Object>[],
        'block': s25Block06(),
      });
      final block = result.block!;
      expect(block.released, isFalse);
      expect(block.withheldReason, 'depth_unproven');
      expect(block.suggestedInputs, ['declaration']);
      final p = block.provisional!;
      expect(p.kind, 'depth_unproven');
      expect(p.frontRowCounted, 100);
      expect(p.ifDepth!.y, 3);
      expect(p.ifDepth!.countedTrays, 180);
      expect(p.ifDepth!.assumedTrays, 120);
      expect(p.ifDepth!.assumedStacks, 6);
      expect(p.ifDepth!.estimatedTotal, 300);
      // Not a total anywhere: not the shown total, not the history status.
      expect(block.split, isNull);
      expect(block.totalTrays, isNull);
      expect(result.shownTrays, isNull);
      expect(result.resultStatus, 'needs_view');
      // A server that sends it on the block instead of the inventory.
      final top = BlockResult.fromJson({
        ...s25Block06(),
        'inventory': null,
        'provisional': {'kind': 'side_repeats_front', 'front_row_counted': 60},
      });
      expect(top.provisional!.kind, 'side_repeats_front');
      expect(top.provisional!.ifDepth, isNull);
    });

    test('the server class wins over the legacy status; an unknown class '
        'falls back to the status', () {
      final c = evidenceClassOf(
        GridCell.fromJson(
          cell06(1, 1, 'top_present', legacy: 'top_view', z: 20, hidden: true),
        ),
      );
      expect(c.evidenceClass, EvidenceClass.topPresent);
      expect(c.derived, isFalse);
      final future = evidenceClassOf(
        GridCell.fromJson(
          cell06(0, 0, 'measured_by_lidar', legacy: 'verified', z: 20),
        ),
      );
      expect(future.evidenceClass, EvidenceClass.measured);
      expect(future.derived, isTrue);
    });
  });

  group('older responses map to evidence classes', () {
    EvidenceClass of(
      String status, {
      bool? present = true,
      List<String> sources = const ['observed'],
      String? legacySource,
    }) => evidenceClassOf(
      GridCell.fromJson(
        _cell05(0, 0, status, present: present, sources: sources),
      ),
      legacySource: legacySource,
    ).evidenceClass;

    test('0.5 grid statuses', () {
      expect(of('verified'), EvidenceClass.measured);
      expect(of('observed'), EvidenceClass.measured);
      expect(of('missing', present: false), EvidenceClass.seenEmpty);
      expect(of('computed', sources: ['computed']), EvidenceClass.assumed);
      expect(
        of('top_view', present: false, sources: ['top_view']),
        EvidenceClass.topMissing,
      );
      expect(
        of('top_view', sources: ['top_view', 'computed']),
        EvidenceClass.topPresent,
      );
      expect(
        of('declared', present: false, sources: ['declared']),
        EvidenceClass.declaredMissing,
      );
      expect(of('declared', sources: ['declared']), EvidenceClass.assumed);
      expect(
        of('unknown', present: null, sources: ['top_view']),
        EvidenceClass.topStep,
      );
      expect(of('unknown', present: null, sources: []), EvidenceClass.assumed);
      expect(of('conflict'), EvidenceClass.conflict);
      expect(of('rescan'), EvidenceClass.conflict);
    });

    test('flags: one reading, a step down, a reading through a gap', () {
      final single = evidenceClassOf(
        GridCell.fromJson(_cell05(0, 0, 'observed')),
      );
      expect(single.singleReading, isTrue);
      expect(single.hidden, isFalse);
      final twice = evidenceClassOf(
        GridCell.fromJson(_cell05(0, 0, 'verified')),
      );
      expect(twice.singleReading, isFalse);
      final down = evidenceClassOf(
        GridCell.fromJson(
          _cell05(
            1,
            1,
            'unknown',
            z: null,
            present: null,
            sources: ['top_view'],
          ),
        ),
      );
      expect(down.stepDown, isTrue);
      expect(down.layers, isNull);
      expect(down.hidden, isTrue);
      // Every reading of the stack looked past a missing one: not a count.
      expect(
        of('observed', legacySource: 'straight-recessed'),
        EvidenceClass.assumed,
      );
      expect(
        of('observed', legacySource: 'straight-recessed+left-recessed'),
        EvidenceClass.assumed,
      );
      final gap = evidenceClassOf(
        GridCell.fromJson(_cell05(1, 1, 'observed', z: 18)),
        legacySource: 'straight-recessed',
      );
      expect(gap.flags, ['line_of_sight_past_gap']);
      expect(gap.layers, 18);
      // A face that read it head-on is a count.
      expect(
        of('observed', legacySource: 'right+straight-recessed'),
        EvidenceClass.measured,
      );
    });

    test('0.4.x cells by the same rules', () {
      EvidenceClass old(Map<String, dynamic> json) =>
          evidenceClassOfBlockCell(BlockCell.fromJson(json)).evidenceClass;
      expect(
        old(_cell04(0, 0, 'observed', 20, source: 'straight')),
        EvidenceClass.measured,
      );
      expect(old(_cell04(0, 0, 'missing', 0)), EvidenceClass.seenEmpty);
      expect(
        old(_cell04(1, 1, 'computed', 20, source: 'faces')),
        EvidenceClass.assumed,
      );
      expect(old(_cell04(1, 1, 'rescan', 20)), EvidenceClass.conflict);
      expect(
        old(_cell04(1, 1, 'observed', 18, source: 'straight-recessed')),
        EvidenceClass.assumed,
      );
      final verified = evidenceClassOfBlockCell(
        BlockCell.fromJson(_cell04(0, 0, 'observed', 20, verified: true)),
      );
      expect(verified.singleReading, isFalse);
      final unread = evidenceClassOfBlockCell(
        BlockCell.fromJson(_cell04(0, 0, 'observed', 20)),
      );
      expect(unread.singleReading, isTrue);
    });
  });

  group('the split adds up', () {
    test('0.6.0: 157 counted + 79 assumed = 236, range 75–80', () {
      final split = BlockResult.fromJson(h2Block06()).split!;
      expect(split.fromServer, isTrue);
      expect(split.counted + split.assumed!, split.estimated);
      expect(split.estimated, 236);
      expect(split.assumedStacks, 4);
      expect(split.hiddenStacks, 4);
      expect(split.topChecked, 0);
      expect(split.unchecked, 4);
      expect(split.assumedFrom, {'neighbours'});
      expect(split.estimatedRange, [232, 237]);
      expect(
        traySplitLine(split),
        'Counted 157 + Assumed 79 (range 75–80) = Estimated 236 tray layers',
      );
      final line = assumptionLine(split);
      expect(line, contains('79 tray layers in 4 hidden stacks'));
      expect(line, contains("its neighbours' face height"));
      expect(line, contains('0 of 4 checked from the top'));
      expect(line, contains('can be missing, shorter or taller'));
    });

    test('0.6.0 top-view taps: present, missing, step up, step down', () {
      final present = BlockResult.fromJson(
        verified3x2Block06(tap: 'present'),
      ).split!;
      expect(
        (present.counted, present.assumed, present.estimated),
        (100, 20, 120),
      );
      expect(present.topChecked, 1);
      expect(present.unchecked, 0);

      final missing = BlockResult.fromJson(
        verified3x2Block06(tap: 'missing'),
      ).split!;
      expect(
        (missing.counted, missing.assumed, missing.estimated),
        (100, 0, 100),
      );
      expect(
        traySplitLine(missing),
        'Counted 100 + Assumed 0 = Estimated 100 tray layers',
      );
      expect(
        assumptionLine(missing),
        contains('the hidden stack is marked empty'),
      );

      final up = BlockResult.fromJson(
        verified3x2Block06(tap: 'step_up'),
      ).split!;
      expect((up.counted, up.assumed, up.estimated), (100, 21, 121));
      expect(up.stepUps, 1);
      expect(
        traySplitLine(up),
        'Counted 100 + Assumed 21 (range 21 or more) = Estimated 121 tray layers',
      );
      expect(
        assumptionLine(up),
        contains('1 stack tapped taller from the top: open above'),
      );

      final downBlock = BlockResult.fromJson(
        verified3x2Block06(tap: 'step_down'),
      );
      final down = downBlock.split!;
      expect(down.counted, 100);
      expect(down.assumed, isNull);
      expect(down.estimated, isNull);
      expect(down.released, isFalse);
      expect(downBlock.released, isFalse);
      expect(downBlock.withheldReason, 'height_unknown');
      expect(downBlock.provisional, isNull);
    });

    test('0.5: from the grid, not computed_trays kept after a missing tap', () {
      final block = BlockResult.fromJson({
        ..._block04(cells: const [], observed: 100, computed: 20, total: 100),
        'status': 'estimated',
        'grid': [
          [
            _cell05(0, 0, 'verified'),
            _cell05(1, 0, 'verified'),
            _cell05(2, 0, 'verified'),
          ],
          [
            _cell05(0, 1, 'verified'),
            _cell05(
              1,
              1,
              'top_view',
              z: 0,
              present: false,
              sources: ['top_view'],
            ),
            _cell05(2, 1, 'verified'),
          ],
        ],
      });
      final split = block.split!;
      expect(split.fromServer, isFalse);
      expect((split.counted, split.assumed, split.estimated), (100, 0, 100));
      expect(split.hiddenStacks, 1);
      expect(split.topChecked, 1);
      expect(split.assumedRange, isNull);
    });

    test('0.4.x: a stack read only through a gap is assumed, so the block '
        'is not exact', () {
      final block = BlockResult.fromJson(
        _block04(
          cells: [
            _cell04(0, 0, 'observed', 20, source: 'straight+left'),
            _cell04(1, 0, 'missing', 0, source: 'straight'),
            _cell04(2, 0, 'observed', 20, source: 'straight+right'),
            _cell04(0, 1, 'observed', 20, source: 'left'),
            _cell04(1, 1, 'observed', 18, source: 'straight-recessed'),
            _cell04(2, 1, 'observed', 20, source: 'right'),
          ],
          observed: 98,
          computed: 0,
          total: 98,
        ),
      );
      // An older server without a status: no computed trays reads as exact.
      expect(block.status, kBlockExact);
      final split = block.split!;
      expect((split.counted, split.assumed, split.estimated), (80, 18, 98));
      expect(split.assumedStacks, 1);
      expect(block.displayStatus, kBlockEstimated);
      expect(
        traySplitLine(split, status: block.displayStatus),
        'Counted 80 + Assumed 18 (range not given) = Estimated 98 tray layers',
      );
    });

    test('0.4.x: the field 4 x 3 block, 105 counted + 60 assumed = 165', () {
      final block = BlockResult.fromJson(
        _block04(
          width: 4,
          depth: 3,
          cells: [
            _cell04(0, 0, 'observed', 15, source: 'straight'),
            _cell04(1, 0, 'observed', 15, source: 'straight'),
            _cell04(2, 0, 'observed', 15, source: 'straight'),
            _cell04(3, 0, 'missing', 0, source: 'straight'),
            _cell04(0, 1, 'observed', 15, source: 'left'),
            _cell04(1, 1, 'computed', 15, source: 'faces'),
            _cell04(2, 1, 'computed', 15, source: 'faces'),
            _cell04(3, 1, 'observed', 14, source: 'right+straight-recessed'),
            _cell04(0, 2, 'observed', 16, source: 'left'),
            _cell04(1, 2, 'computed', 15, source: 'faces'),
            _cell04(2, 2, 'computed', 15, source: 'faces'),
            _cell04(3, 2, 'observed', 15, source: 'right'),
          ],
          observed: 105,
          computed: 60,
          total: 165,
        ),
      );
      final split = block.split!;
      expect((split.counted, split.assumed, split.estimated), (105, 60, 165));
      expect(split.assumedStacks, 4);
      expect(split.assumedFrom, {'face_typical'});
      expect(
        assumptionLine(split),
        contains("the block's typical face height"),
      );
    });

    test('0.4.x: cells that do not cover every stack fall back to the '
        "server's totals", () {
      final block = BlockResult.fromJson(
        _block04(
          cells: [_cell04(0, 0, 'observed', 20)],
          observed: 60,
          computed: 20,
          total: 80,
        ),
      );
      final split = block.split!;
      expect((split.counted, split.assumed, split.estimated), (60, 20, 80));
      expect(split.assumedStacks, isNull);
      expect(
        assumptionLine(split),
        contains('20 tray layers in hidden stacks'),
      );
    });

    test('exact: nothing assumed, called a total', () {
      final block = BlockResult.fromJson(
        _block04(
          width: 2,
          depth: 1,
          cells: [
            _cell04(0, 0, 'observed', 20, verified: true),
            _cell04(1, 0, 'observed', 20, verified: true),
          ],
          observed: 40,
          computed: 0,
          total: 40,
          status: 'exact',
        ),
      );
      expect(block.displayStatus, kBlockExact);
      final split = block.split!;
      expect(
        traySplitLine(split, status: block.displayStatus),
        'Counted 40 + Assumed 0 = Total 40 tray layers',
      );
      expect(assumptionLine(split), startsWith('Nothing assumed'));
    });

    test('no split for a block without a counted figure', () {
      expect(
        BlockResult.fromJson(
          _block04(cells: const [], observed: 0, computed: 0, total: null),
        ).split,
        isNull,
      );
    });

    test('egg-filled trays are not checked unless declared', () {
      expect(eggFilledLine(null), 'Egg-filled trays: not checked');
      expect(
        eggFilledLine(BlockResult.fromJson(h2Block06()).inventory),
        'Egg-filled trays: not checked',
      );
      expect(
        eggFilledLine(
          BlockInventory.fromJson({
            'eligible_egg_trays': {'value': 20, 'basis': 'declared'},
          }),
        ),
        'Egg-filled trays: 20 (declared)',
      );
    });
  });

  group('drawing by evidence class', () {
    test('each class has its own look; only counted stacks get ticks', () {
      final looks = {
        for (final e in _everyClass().evidence)
          '${e.x},${e.y}': (e: e, look: cellLook(e)),
      };
      final counted = looks['0,0']!.look;
      expect(counted.shape, CellShape.solid);
      expect(counted.ticks, isTrue);
      expect(counted.color, kVerified);
      expect(counted.label, '20');
      expect(looks['1,0']!.look.color, kSingleReading);
      final assumed = looks['1,1']!.look;
      expect(assumed.shape, CellShape.ghost);
      expect(assumed.ticks, isFalse);
      expect(assumed.label, '~20');
      expect(assumed.edge, isNull);
      final present = looks['1,2']!.look;
      expect(present.shape, CellShape.ghost);
      expect(present.edge, kTopView);
      expect(present.label, '~20');
      final up = looks['2,2']!.look;
      expect(up.shape, CellShape.ghost);
      expect(up.ticks, isFalse);
      expect(up.label, '▲ ≥21');
      expect(up.badge, 'taller');
      expect(up.layers, 21);
      final down = looks['2,1']!.look;
      expect(down.label, '▼ ?');
      expect(down.badge, 'shorter');
      expect(down.layers, 20); // drawn at the top of its range
      expect(looks['2,0']!.look.shape, CellShape.dashedFootprint);
      expect(looks['2,0']!.look.color, kMissing);
      expect(looks['1,3']!.look.shape, CellShape.footprint);
      expect(looks['1,3']!.look.edge, kTopView);
      expect(looks['2,3']!.look.shape, CellShape.footprint);
      expect(looks['2,3']!.look.edge, kDeclared);
      expect(looks['0,3']!.look.color, kRescan);
      expect(looks['0,3']!.look.ticks, isFalse);
      for (final entry in looks.values) {
        expect(
          entry.look.ticks,
          entry.e.evidenceClass == EvidenceClass.measured,
          reason: '${entry.e.x},${entry.e.y}',
        );
      }
    });

    test('the painter draws ticks on counted stacks only and labels every '
        'stack that has one', () {
      final block = _everyClass();
      final canvas = _RecordingCanvas();
      BlockPainter(block).paint(canvas, const Size(400, 300));
      final looks = block.evidence.map(cellLook).toList();
      final ticks = looks
          .where((l) => l.ticks)
          .fold<int>(0, (s, l) => s + l.layers - 1);
      expect(ticks, 19 + 18 + 6 * 19);
      expect(canvas.count(#drawLine), ticks);
      final texts =
          looks.where((l) => l.label != null).length +
          looks.where((l) => l.badge != null).length;
      expect(canvas.count(#drawParagraph), texts);
      // Ghosts are hatched inside their front face.
      expect(
        canvas.count(#clipPath),
        looks.where((l) => l.shape == CellShape.ghost && l.layers > 0).length,
      );
    });

    test('the painter runs on a real canvas for every format', () {
      for (final block in [
        _everyClass(),
        BlockResult.fromJson(h2Block06()),
        BlockResult.fromJson(verified3x2Block06(tap: 'step_down')),
        BlockResult.fromJson(s25Block06()),
        BlockResult.fromJson(
          _block04(
            cells: [
              _cell04(0, 0, 'observed', 20),
              _cell04(1, 0, 'missing', 0),
              _cell04(2, 0, 'observed', 20),
              _cell04(0, 1, 'observed', 20),
              _cell04(1, 1, 'computed', 20),
              _cell04(2, 1, 'rescan', 19),
            ],
            observed: 80,
            computed: 20,
            total: null,
          ),
        ),
      ]) {
        final recorder = ui.PictureRecorder();
        BlockPainter(block).paint(Canvas(recorder), const Size(320, 220));
        recorder.endRecording().dispose();
      }
    });
  });

  group('the panel', () {
    testWidgets('0.6.0 estimate: counted and assumed apart, the range '
        'labelled, occupancy not checked', (tester) async {
      await _pumpPanel(tester, BlockResult.fromJson(h2Block06()));
      expect(tester.takeException(), isNull);
      expect(
        find.text('ESTIMATE: 157 COUNTED + 79 ASSUMED IN 4 HIDDEN STACKS'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Counted 157 + Assumed 79 (range 75–80) = Estimated 236 tray layers',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('assumption-line')), findsOneWidget);
      expect(find.text('Egg-filled trays: not checked'), findsOneWidget);
      expect(find.text('Counted on faces'), findsOneWidget);
      expect(find.text('157 (at least)'), findsOneWidget);
      expect(find.text('Assumed in 4 hidden stacks'), findsOneWidget);
      expect(find.text('79 (0 checked from the top)'), findsOneWidget);
      expect(find.text('Estimate'), findsOneWidget);
      expect(
        find.text("If every hidden stack is there at its neighbours' heights"),
        findsOneWidget,
      );
      expect(find.text('232–237'), findsOneWidget);
      expect(find.byKey(const ValueKey('provisional-panel')), findsNothing);
      final text = _allText(tester).toLowerCase();
      for (final word in ['exact', 'confirmed', 'verified']) {
        expect(text, isNot(contains(word)), reason: word);
      }
    });

    testWidgets('every evidence class is in the legend', (tester) async {
      await _pumpPanel(tester, _everyClass());
      expect(tester.takeException(), isNull);
      for (final label in [
        'counted, two photos agree',
        'counted, read once',
        '~ assumed, not counted',
        '~ assumed, there from the top',
        '▼ shorter from the top',
        '▲ taller from the top',
        'no stack (seen on a face)',
        'no stack (top view)',
        'no stack (declared)',
        'conflict / rescan',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('RESCAN REQUIRED'), findsOneWidget);
      expect(find.byKey(const ValueKey('total-withheld')), findsOneWidget);
    });

    testWidgets('a step down withholds the total and says why', (tester) async {
      await _pumpPanel(
        tester,
        BlockResult.fromJson(verified3x2Block06(tap: 'step_down')),
      );
      expect(
        find.text("TOTAL WITHHELD: A HIDDEN STACK'S HEIGHT IS UNKNOWN"),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('tray-split')), findsNothing);
      expect(
        find.text(
          "Counted 100 on faces (at least); TOTAL WITHHELD: a hidden stack's "
          'height is unknown',
        ),
        findsOneWidget,
      );
      expect(find.text('101–120'), findsOneWidget);
      expect(find.byKey(const ValueKey('estimate-row')), findsNothing);
    });

    testWidgets('a step up shows the open range', (tester) async {
      await _pumpPanel(
        tester,
        BlockResult.fromJson(verified3x2Block06(tap: 'step_up')),
      );
      expect(
        find.text(
          'Counted 100 + Assumed 21 (range 21 or more) = Estimated 121 tray '
          'layers',
        ),
        findsOneWidget,
      );
      expect(find.text('121 or more'), findsOneWidget);
    });

    testWidgets('depth not proven: a grey panel, never a total', (
      tester,
    ) async {
      await _pumpPanel(tester, BlockResult.fromJson(s25Block06()));
      expect(find.text('NO TOTAL YET'), findsOneWidget);
      expect(find.byKey(const ValueKey('provisional-panel')), findsOneWidget);
      expect(find.text('NOT RELEASED: DEPTH NOT PROVEN'), findsOneWidget);
      expect(find.text('Front row counted: 100'), findsOneWidget);
      expect(
        find.text(
          'Only if the block is 3 deep: 180 counted + 120 assumed ≈ 300',
        ),
        findsOneWidget,
      );
      expect(
        find.text('DECLARE THE BLOCK SIZE AND SCAN AGAIN'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('tray-split')), findsNothing);
      final headline = tester.widget<Text>(
        find.byKey(const ValueKey('block-headline')),
      );
      expect(headline.data, isNot(contains('300')));
    });

    testWidgets('a side that repeats the front: the front row only', (
      tester,
    ) async {
      await _pumpPanel(
        tester,
        BlockResult.fromJson(s25Block06(kind: 'side_repeats_front')),
      );
      expect(
        find.text('NOT RELEASED: A SIDE REPEATS THE FRONT'),
        findsOneWidget,
      );
      expect(find.text('Front row counted: 100'), findsOneWidget);
      expect(find.byKey(const ValueKey('provisional-if-depth')), findsNothing);
    });
  });
}
