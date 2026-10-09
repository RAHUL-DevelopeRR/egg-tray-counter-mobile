import 'package:egg_tray_counter/features/scan_flow/block_view.dart';
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

  testWidgets('block panel renders the computed headline and grid', (
    tester,
  ) async {
    final block = BlockResult.fromJson(
      _block()
        ..['fully_observed'] = false
        ..['computed_trays'] = 20
        ..['observed_trays'] = 60,
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: BlockPanel(block: block))),
    );
    expect(find.text('COMPUTED FROM 3 FACES'), findsOneWidget);
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
}
