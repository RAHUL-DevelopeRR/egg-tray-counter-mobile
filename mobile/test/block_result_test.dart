import 'package:egg_tray_counter/features/scan_flow/block_view.dart';
import 'package:egg_tray_counter/features/scan_flow/result_look.dart';
import 'package:egg_tray_counter/models/block_result.dart';
import 'package:egg_tray_counter/models/scan_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _scan({Map<String, dynamic>? block}) => {
  'scan_id': 'scan-9',
  'status': 'rescan_required',
  'accepted': false,
  'physical_stack_count': null,
  'total_trays': null,
  'eggs_per_tray': 30,
  'total_eggs': null,
  'processing': {
    'mode': 'model_spatial_v1',
    'latency_ms': 50,
    'model_version': 'projec-mutta/2',
  },
  'views': {
    'left': {'quality': 0, 'accepted': false, 'reason': 'x'},
    'right': {'quality': 0, 'accepted': false, 'reason': 'x'},
    'straight': {'quality': 0, 'accepted': false, 'reason': 'x'},
  },
  'stacks': <Object>[],
  'rescan': {'recommended_view': 'straight', 'reason': 'x'},
  'block': ?block,
};

Map<String, dynamic> _block() => {
  'contract': 'block_model_v1',
  'width': 2,
  'depth': 2,
  'faces_used': ['straight', 'left', 'right'],
  'typical_layers': 20,
  'cells': [
    {'x': 0, 'y': 0, 'status': 'observed', 'layers': 20, 'source': 'straight'},
    {'x': 1, 'y': 0, 'status': 'observed', 'layers': 20, 'source': 'straight'},
    {'x': 0, 'y': 1, 'status': 'observed', 'layers': 20, 'source': 'left'},
    {'x': 1, 'y': 1, 'status': 'observed', 'layers': 20, 'source': 'right'},
  ],
  'observed_trays': 80,
  'computed_trays': 0,
  'total_trays': 80,
  'total_eggs': 2400,
  'fully_observed': true,
  'faces_consistent': true,
  'conflicts': <Object>[],
  'rescan_cells': <Object>[],
  'note': 'n',
};

Map<String, dynamic> _gridCell(
  int x,
  int y,
  String status, {
  int? z = 20,
  bool? present = true,
  List<String> sources = const ['observed'],
  List<Object> readings = const [],
}) => {
  'physical_stack_id': 'S$x-$y',
  'x': x,
  'y': y,
  'stack_present': present,
  'z_layers': z,
  'filled_layers': null,
  'partial_layers': null,
  'empty_cover_layers': null,
  'unknown_layers': z,
  'observed_views': ['straight', 'left'],
  'measurement_sources': sources,
  'status': status,
  'uncertainties': ['occupancy not measured'],
  'readings': readings,
  'pair_type': readings.length > 1 ? 'cross_photo' : null,
};

Map<String, dynamic> _reading(String view, String captureId) => {
  'capture_id': captureId,
  'reader': 'rf-walk',
  'physical_stack_id': 'S0-0',
  'view': view,
  'count': 20,
  'evidence': {'gap_filled': 0, 'doubts': <Object>[]},
  'quality': 'accepted',
  'trusted': true,
  'pipeline_version': 'worker-0.5.0',
};

/// A Worker 0.5.0 block: a 2 x 2 grid model with one verified, one
/// single-reading, one declared and one missing stack.
Map<String, dynamic> _gridBlock({
  String status = 'estimated',
  List<String> basis = const [],
}) => {
  ..._block(),
  'status': status,
  'observed_trays': 40,
  'computed_trays': 20,
  'total_trays': 60,
  'cells': <Object>[],
  'grid': [
    [
      _gridCell(
        0,
        0,
        'verified',
        readings: [_reading('straight', 'a1'), _reading('left', 'b2')],
      ),
      _gridCell(1, 0, 'observed', readings: [_reading('straight', 'a1')]),
    ],
    [
      _gridCell(0, 1, 'declared', sources: ['declared']),
      _gridCell(1, 1, 'missing', z: 0, present: false, sources: []),
    ],
  ],
  'inventory': {
    'physical_layers_observed': 40,
    'physical_layers_computed': 0,
    'physical_layers_declared': 20,
    'eligible_egg_trays': {
      'value': 60,
      'basis': 'declared',
      'note': 'occupancy declared by the operator',
    },
    'empty_cover_layers': {'value': null, 'basis': 'unknown'},
    'unknown_occupancy_layers': 0,
    'unknown_cells': 0,
  },
  'declaration': {
    'x': 2,
    'y': 2,
    'interior': 'full',
    'missing_cells': [
      [1, 1],
    ],
    'partial_stacks': <Object>[],
    'cover_trays': 'no',
    'occupancy': 'egg_filled',
    'reference_height': null,
    'reference_height_measured': false,
    'operator': 'OP7',
    'declared_at': '2026-11-01T10:00:00Z',
    'agrees_with_faces': true,
  },
  'corner': {'side': 'front_left', 'x': 2, 'y': 2, 'agrees': true},
  'top_view': {
    'cells_present': 3,
    'cells_missing': 1,
    'steps': 0,
    'agrees': true,
  },
  'suggested_views': ['elevated'],
  'confirmed_basis': basis,
};

/// Every text on screen, joined, for words that must never appear.
String _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .join(' | ');

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('older server without block leaves block null', () {
    expect(ScanResult.fromJson(_scan()).block, isNull);
  });

  test('block contract parses and keeps legacy total absent', () {
    final result = ScanResult.fromJson(_scan(block: _block()));
    expect(result.totalTrays, isNull);
    expect(result.block!.totalTrays, 80);
    expect(result.block!.totalEggs, 2400);
    expect(result.block!.fullyObserved, isTrue);
    expect(result.block!.cells, hasLength(4));
  });

  test('inconsistent block has no total and lists conflicts', () {
    final json = _block()
      ..['total_trays'] = null
      ..['total_eggs'] = null
      ..['faces_consistent'] = false
      ..['fully_observed'] = false
      ..['conflicts'] = [
        {'reason': 'depth differs between LEFT and RIGHT faces'},
      ]
      ..['rescan_cells'] = [
        [1, 0],
      ];
    final block = BlockResult.fromJson(json);
    expect(block.totalTrays, isNull);
    expect(block.conflicts.single, contains('depth differs'));
    expect(block.rescanCells.single, [1, 0]);
  });

  testWidgets('block panel renders the counted + assumed headline and grid', (
    tester,
  ) async {
    _tall(tester);
    final block = BlockResult.fromJson(
      _block()
        ..['fully_observed'] = false
        ..['computed_trays'] = 20
        ..['observed_trays'] = 60
        ..['cells'] = [
          ...(_block()['cells'] as List).take(3),
          {'x': 1, 'y': 1, 'status': 'computed', 'layers': 20, 'source': 'faces'},
        ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: BlockPanel(block: block)),
        ),
      ),
    );
    expect(
      find.text('ESTIMATE: 60 COUNTED + 20 ASSUMED IN 1 HIDDEN STACK'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Counted 60 + Assumed 20 (range not given) = Estimated 80 tray layers',
      ),
      findsOneWidget,
    );
    expect(find.text('2 wide × 2 deep'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  test('status colours distinguish observed, computed and missing', () {
    expect(statusColor('observed'), isNot(statusColor('computed')));
    expect(statusColor('missing'), isNot(statusColor('observed')));
  });
  test('paint order is far to near: nearest corner (x=width-1, y=0) is last', () {
    final cells = [
      for (var y = 0; y < 2; y++)
        for (var x = 0; x < 2; x++)
          BlockCell(x: x, y: y, status: 'observed', layers: 20),
    ];
    final order = paintOrder(cells).map((c) => '${c.x},${c.y}').toList();
    expect(order.first, '0,1');
    expect(order.last, '1,0');
    final column = [
      for (var y = 0; y < 8; y++)
        BlockCell(x: 0, y: y, status: 'observed', layers: 20),
    ];
    final deep = paintOrder(column).map((c) => c.y).toList();
    expect(deep.first, 7);
    expect(deep.last, 0);
  });

  testWidgets('degenerate block (no grid, one conflict) renders without a grid', (
    tester,
  ) async {
    final block = BlockResult.fromJson({
      'width': null,
      'depth': null,
      'cells': <Object>[],
      'observed_trays': 0,
      'computed_trays': 0,
      'total_trays': null,
      'total_eggs': null,
      'fully_observed': false,
      'faces_consistent': false,
      'faces_used': <Object>[],
      'conflicts': [
        {'reason': 'STRAIGHT and at least one side face must show stacks'},
        {'reason': 'depth differs between LEFT and RIGHT faces', 'left': 4, 'right': 3},
      ],
      'rescan_cells': <Object>[],
      'note': 'n',
    });
    expect(block.hasGrid, isFalse);
    expect(block.conflicts[1], contains('left=4, right=3'));
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: BlockPanel(block: block))),
    );
    expect(find.text('RESCAN REQUIRED'), findsOneWidget);
    expect(find.textContaining('depth differs'), findsOneWidget);
  });

  test('hasGrid requires positive dimensions', () {
    final json = _block()..['width'] = 0..['depth'] = 0;
    expect(BlockResult.fromJson(json).hasGrid, isFalse);
  });

  test('server status is used; older servers derive it from the totals', () {
    expect(BlockResult.fromJson(_block()..['status'] = 'estimated').status, 'estimated');
    expect(BlockResult.fromJson(_block()).status, 'exact');
    expect(BlockResult.fromJson(_block()..['computed_trays'] = 20).status, 'estimated');
    expect(BlockResult.fromJson(_block()..['total_trays'] = null).status, 'conflict');
  });

  test('result status, shown total and history agree for block scans', () {
    final estimate = ScanResult.fromJson(
      _scan(block: _block()..['status'] = 'estimated'..['computed_trays'] = 20),
    );
    expect(estimate.resultStatus, 'estimated');
    expect(estimate.shownTrays, 80);
    expect(estimate.shownEggs, 2400);
    expect(resultLook(estimate.resultStatus).label, 'ESTIMATE');
    final withheld = ScanResult.fromJson(
      _scan(block: _block()..['status'] = 'conflict'..['total_trays'] = null..['total_eggs'] = null),
    );
    expect(withheld.shownTrays, isNull);
    expect(resultLook(withheld.resultStatus).label, 'RETAKE');
    expect(resultLook('exact').headline, 'BLOCK COUNTED');
    expect(resultLook('rescan_required').headline, 'RETAKE NEEDED');
  });

  testWidgets('one-layer disagreement is shown as an estimate with its reason', (
    tester,
  ) async {
    final block = BlockResult.fromJson(
      _block()
        ..['status'] = 'estimated'
        ..['filled_trays'] = 1
        ..['ambiguities'] = [
          {'reason': 'faces differ by one layer', 'cell': [0, 0], 'straight_layers': 20, 'left_layers': 19},
        ],
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: BlockPanel(block: block)))),
    );
    expect(find.text('ESTIMATE: A READING IS UNCERTAIN'), findsOneWidget);
    expect(find.textContaining('straight_layers=20'), findsOneWidget);
    expect(find.text('Layers between detected boxes'), findsOneWidget);
    expect(find.text('Eggs if every tray is full'), findsOneWidget);
    // An older server: no two-photo split, the counted row instead.
    expect(find.text('Counted on faces'), findsOneWidget);
    expect(find.text('Seen by two photos'), findsNothing);
  });

  testWidgets('a 0.4.14 block splits seen trays into two-photo and one-photo readings', (tester) async {
    final block = BlockResult.fromJson(
      _block()
        ..['status'] = 'estimated'
        ..['visible_verified_trays'] = 40
        ..['visible_single_reading_trays'] = 40
        ..['cells'] = [
          {'x': 0, 'y': 0, 'status': 'observed', 'layers': 20, 'verified': true},
          {'x': 1, 'y': 0, 'status': 'observed', 'layers': 20, 'verified': false},
        ],
    );
    expect(block.cells.map((c) => c.verified), [true, false]);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: BlockPanel(block: block)))),
    );
    expect(find.text('ESTIMATE: 40 TRAYS SEEN BY ONE PHOTO ONLY'), findsOneWidget);
    expect(find.text('Seen by two photos'), findsOneWidget);
    expect(find.text('Seen by one photo only'), findsOneWidget);
    expect(find.text('Seen trays'), findsNothing);
  });

  group('grid model (Worker 0.5.0)', () {
    test('every grid cell field, the inventory, declaration, corner, top '
        'view, suggested views and confirmed basis parse', () {
      final block = BlockResult.fromJson(_gridBlock(basis: ['declaration']));
      expect(block.hasGridModel, isTrue);
      expect(block.grid, hasLength(4));
      expect((block.gridWidth, block.gridDepth), (2, 2));
      final verified = block.grid.firstWhere((c) => c.x == 0 && c.y == 0);
      expect(verified.physicalStackId, 'S0-0');
      expect(verified.status, 'verified');
      expect(verified.stackPresent, isTrue);
      expect(verified.zLayers, 20);
      expect(verified.unknownLayers, 20);
      expect(verified.filledLayers, isNull);
      expect(verified.partialLayers, isNull);
      expect(verified.emptyCoverLayers, isNull);
      expect(verified.observedViews, ['straight', 'left']);
      expect(verified.measurementSources, ['observed']);
      expect(verified.uncertainties, ['occupancy not measured']);
      expect(verified.pairType, 'cross_photo');
      expect(verified.readings, hasLength(2));
      final reading = verified.readings.last;
      expect(reading.captureId, 'b2');
      expect(reading.reader, 'rf-walk');
      expect(reading.physicalStackId, 'S0-0');
      expect(reading.view, 'left');
      expect(reading.count, 20);
      expect(reading.evidence['gap_filled'], 0);
      expect(reading.quality, 'accepted');
      expect(reading.trusted, isTrue);
      expect(reading.pipelineVersion, 'worker-0.5.0');
      final missing = block.grid.firstWhere((c) => c.x == 1 && c.y == 1);
      expect(missing.stackPresent, isFalse);
      expect(missing.status, 'missing');

      final inventory = block.inventory!;
      expect(inventory.physicalLayersObserved, 40);
      expect(inventory.physicalLayersComputed, 0);
      expect(inventory.physicalLayersDeclared, 20);
      expect(inventory.eligibleEggTrays!.value, 60);
      expect(inventory.eligibleEggTrays!.basis, 'declared');
      expect(inventory.eligibleEggTrays!.note, contains('declared'));
      expect(inventory.emptyCoverLayers!.value, isNull);
      expect(inventory.emptyCoverLayers!.basis, 'unknown');
      expect(inventory.unknownOccupancyLayers, 0);
      expect(inventory.unknownCells, 0);

      expect(block.declaration!.x, 2);
      expect(block.declaration!.interior, 'full');
      expect(block.declaration!.missingCells, [
        [1, 1],
      ]);
      expect(block.declaration!.occupancy, 'egg_filled');
      expect(block.declaration!.agreesWithFaces, isTrue);
      expect(block.corner!.side, 'front_left');
      expect(block.corner!.agrees, isTrue);
      expect(block.topView!.cellsPresent, 3);
      expect(block.topView!.cellsMissing, 1);
      expect(block.topView!.steps, 0);
      expect(block.suggestedViews, ['elevated']);
      expect(block.confirmedBasis, ['declaration']);
      // A grid-only server still gives the manual count one row per stack.
      expect(block.cells, isEmpty);
      expect(block.stackCells.map((c) => '${c.x},${c.y}:${c.layers}'), [
        '0,0:20',
        '1,0:20',
        '0,1:20',
        '1,1:0',
      ]);
    });

    test('cells take their position when the server leaves x and y out; '
        'top-view cell lists count as their lengths', () {
      final block = BlockResult.fromJson({
        ..._block(),
        'grid': [
          [
            {'status': 'unknown', 'z_layers': null},
            {'status': 'computed', 'z_layers': 20},
          ],
        ],
        'top_view': {
          'cells_present': [
            [0, 0],
            [1, 0],
          ],
          'cells_missing': <Object>[],
          'steps': null,
          'agrees': null,
        },
      });
      expect(block.grid.map((c) => (c.x, c.y, c.status)), [
        (0, 0, 'unknown'),
        (1, 0, 'computed'),
      ]);
      expect(block.grid.first.stackPresent, isNull);
      expect(block.grid.first.zLayers, isNull);
      expect(block.topView!.cellsPresent, 2);
      expect(block.topView!.cellsMissing, 0);
      expect(block.topView!.steps, isNull);
    });

    test('an older server: no grid, every new field empty, cells drive the '
        'drawing and the manual count', () {
      final block = BlockResult.fromJson(_block());
      expect(block.hasGridModel, isFalse);
      expect(block.grid, isEmpty);
      expect(block.inventory, isNull);
      expect(block.declaration, isNull);
      expect(block.corner, isNull);
      expect(block.topView, isNull);
      expect(block.suggestedViews, isEmpty);
      expect(block.confirmedBasis, isEmpty);
      expect(block.stackCells, same(block.cells));
    });

    testWidgets('an older server keeps the cells drawing and its rows', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BlockPanel(block: BlockResult.fromJson(_block())),
            ),
          ),
        ),
      );
      // Before 0.4.14 nothing was read twice: counted, read once.
      expect(find.text('counted, read once'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(
        find.text('Counted 80 + Assumed 0 = Total 80 tray layers'),
        findsOneWidget,
      );
      expect(find.text('Egg-filled trays: not checked'), findsOneWidget);
      expect(find.byKey(const ValueKey('grid-model-caption')), findsNothing);
      expect(find.text('Physical layers observed'), findsNothing);
    });

    testWidgets('the grid model is drawn with its legend, its label and the '
        'inventory kept apart by basis', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BlockPanel(block: BlockResult.fromJson(_gridBlock())),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.text('Grid model from photos, not a point cloud or measured mesh.'),
        findsOneWidget,
      );
      for (final label in [
        'counted, two photos agree',
        'counted, read once',
        '~ assumed, not counted',
        'no stack (seen on a face)',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('2 wide × 2 deep'), findsOneWidget);
      expect(find.text('Counted on faces'), findsOneWidget);
      expect(find.text('40 (at least)'), findsOneWidget);
      expect(find.text('Assumed in 1 hidden stack'), findsOneWidget);
      expect(
        find.text(
          'Counted 40 + Assumed 20 (range not given) = Estimated 60 tray '
          'layers',
        ),
        findsOneWidget,
      );
      expect(find.text('Egg-filled trays: 60 (declared)'), findsOneWidget);
      expect(find.text('occupancy declared by the operator'), findsOneWidget);
      expect(find.text('Unknown-occupancy layers'), findsOneWidget);
      expect(find.text('Declaration (2 × 2)'), findsOneWidget);
      expect(find.text('Corner photo (front left)'), findsOneWidget);
      expect(find.byKey(const ValueKey('suggested-views')), findsOneWidget);
      // Old cells-only rows are replaced, not shown next to the inventory.
      expect(find.text('Hidden trays (computed)'), findsNothing);
    });

    test('grid colours tell verified, one-capture, declared, top view, '
        'missing and unknown apart', () {
      final block = BlockResult.fromJson(_gridBlock());
      final colours = {for (final c in block.grid) c.status: gridCellColor(c)};
      expect(colours['verified'], kVerified);
      expect(colours['observed'], kSingleReading);
      expect(colours['declared'], kDeclared);
      expect(colours['missing'], kMissing);
      expect(colours.values.toSet(), hasLength(4));
      expect(
        gridCellColor(const GridCell(x: 0, y: 0, status: 'top_view')),
        kTopView,
      );
      expect(
        gridCellColor(const GridCell(x: 0, y: 0, status: 'unknown')),
        kUnknownCell,
      );
      expect(
        gridCellColor(const GridCell(x: 0, y: 0, status: 'conflict')),
        kRescan,
      );
      // Known absent wins over any status.
      expect(
        gridCellColor(
          const GridCell(x: 0, y: 0, status: 'computed', stackPresent: false),
        ),
        kMissing,
      );
    });
  });

  group("an older server's confirmed", () {
    test('the look is an estimate: never exact, confirmed or verified', () {
      for (final basis in [
        <String>[],
        ['declaration'],
        ['top_view'],
        ['declaration', 'top_view'],
      ]) {
        final look = resultLook('confirmed', basis: basis);
        expect(look.headline, 'BLOCK ESTIMATE');
        expect(look.label, 'ESTIMATE (OLDER SERVER)');
        for (final words in [look.headline, look.label]) {
          expect(words.toLowerCase(), isNot(contains('exact')));
          expect(words.toLowerCase(), isNot(contains('confirmed')));
          expect(words.toLowerCase(), isNot(contains('verified')));
        }
      }
      expect(resultLook('confirmed').color, isNot(resultLook('exact').color));
      final result = ScanResult.fromJson(
        _scan(block: _gridBlock(status: 'confirmed', basis: ['declaration'])),
      );
      // History keeps what the server said; the look shows an estimate.
      expect(result.resultStatus, kBlockConfirmed);
    });

    testWidgets('the panel shows counted and assumed apart and no "exact", '
        '"confirmed" or "verified" anywhere', (tester) async {
      _tall(tester);
      final block = BlockResult.fromJson(
        _gridBlock(status: 'confirmed', basis: ['declaration']),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: BlockPanel(block: block)),
          ),
        ),
      );
      expect(
        find.text('ESTIMATE: 40 COUNTED + 20 ASSUMED IN 1 HIDDEN STACK'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('older-label-note')), findsOneWidget);
      final text = _allText(tester).toLowerCase();
      expect(text, isNot(contains('exact')));
      expect(text, isNot(contains('confirmed')));
      expect(text, isNot(contains('verified')));
      expect(text, isNot(contains('every stack seen by two photos')));
    });
  });
}
