import 'package:egg_tray_counter/features/scan_flow/manual_count_screen.dart';
import 'package:egg_tray_counter/models/block_result.dart';
import 'package:egg_tray_counter/models/manual_count.dart';
import 'package:egg_tray_counter/models/scan_result.dart';
import 'package:egg_tray_counter/services/manual_count_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ScanResult _result() => ScanResult.fromJson({
  'scan_id': '8a1b2c3d-1111-4222-8333-444455556666',
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
  'block': {
    'contract': 'block_model_v1',
    'width': 2,
    'depth': 2,
    'faces_used': ['straight', 'left'],
    'typical_layers': 20,
    'cells': [
      {'x': 0, 'y': 0, 'status': 'observed', 'layers': 20},
      {'x': 1, 'y': 0, 'status': 'missing', 'layers': 0},
      {'x': 0, 'y': 1, 'status': 'observed', 'layers': 19},
      {'x': 1, 'y': 1, 'status': 'computed', 'layers': 20},
    ],
    'observed_trays': 39,
    'computed_trays': 20,
    'total_trays': 59,
    'total_eggs': 1770,
    'fully_observed': false,
    'faces_consistent': true,
    'conflicts': <Object>[],
    'rescan_cells': <Object>[],
    'note': 'n',
  },
});

void main() {
  test('cells are pre-filled from the block and missing stacks start at 0', () {
    final block = BlockResult.fromJson(_result().block!.toJsonForTest());
    final cells = block.cells.map(ManualCountCell.fromBlockCell).toList();
    expect(cells.map((c) => c.filled), [20, 0, 19, 20]);
    expect(cells.every((c) => c.empty == 0), isTrue);
  });

  test('csv rows and server payload carry every field', () {
    final count = ManualCount(
      scanId: 's1',
      blockId: 'B,01',
      cells: const [
        ManualCountCell(
          x: 0,
          y: 0,
          appLayers: 20,
          appStatus: 'observed',
          filled: 19,
          empty: 1,
        ),
        ManualCountCell(
          x: 0,
          y: 1,
          appLayers: 20,
          appStatus: 'computed',
          filled: 0,
          empty: 0,
          unreachable: true,
        ),
      ],
      notes: 'n',
      createdAt: DateTime.utc(2026, 10, 9, 8),
      appTotal: 40,
    );
    expect(count.filledTotal, 19);
    expect(count.unreachableCount, 1);
    final rows = count.csvRows();
    expect(rows.first, startsWith('s1,"B,01",0,0,20,observed,19,1,no,2026-10-09T08:00:00.000Z,no'));
    final json = count.toJson(appVersion: '0.4.0+11');
    expect(json['block_id'], 'B,01');
    expect((json['cells'] as List).length, 2);
    expect(json['app_version'], '0.4.0+11');
  });

  test('repository csv joins header and all counts', () async {
    final repo = InMemoryManualCountRepository();
    await repo.save(
      ManualCount(
        scanId: 's1',
        blockId: 'B01',
        cells: const [
          ManualCountCell(
            x: 0,
            y: 0,
            appLayers: 20,
            appStatus: 'observed',
            filled: 20,
            empty: 0,
          ),
        ],
        notes: '',
        createdAt: DateTime.utc(2026, 10, 9),
      ),
    );
    final csv = await repo.csv();
    expect(csv.split('\n').first, ManualCount.csvHeader);
    expect(csv.split('\n'), hasLength(2));
  });

  testWidgets('screen lists one row per stack, requires a block ID, saves locally', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = InMemoryManualCountRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ManualCountScreen(
          result: _result(),
          repository: repo,
          baseUrl: 'http://127.0.0.1:9',
        ),
      ),
    );
    expect(find.byKey(const ValueKey('row-0,0')), findsOneWidget);
    expect(find.byKey(const ValueKey('row-1,1')), findsOneWidget);
    expect(find.text('59'), findsNWidgets(2)); // app total and manual filled (pre-filled)
    await tester.tap(find.text('SAVE ON PHONE ONLY'));
    await tester.pump();
    expect(find.text('Enter the block ID first.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'B07');
    await tester.enterText(find.byKey(const ValueKey('filled-0,1')), '18');
    await tester.tap(find.byKey(const ValueKey('unreachable-1,1')));
    await tester.pump();
    await tester.tap(find.text('SAVE ON PHONE ONLY'));
    await tester.pumpAndSettle();
    final saved = await repo.all();
    expect(saved.single.blockId, 'B07');
    expect(saved.single.cells.firstWhere((c) => c.x == 0 && c.y == 1).filled, 18);
    expect(saved.single.cells.firstWhere((c) => c.x == 1 && c.y == 1).unreachable, isTrue);
    expect(find.text('Saved on this phone.'), findsOneWidget);
    // Not sent yet: no DONE button; the send button keeps its first label.
    expect(find.byKey(const ValueKey('manual-count-done')), findsNothing);
    expect(find.text('SAVE AND SEND TO SERVER'), findsOneWidget);
  });

  testWidgets('a failed send keeps the phone copy and offers no DONE', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = InMemoryManualCountRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: ManualCountScreen(
          result: _result(),
          repository: repo,
          baseUrl: 'http://127.0.0.1:9', // nothing listens here
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'B08');
    await tester.tap(find.text('SAVE AND SEND TO SERVER'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect((await repo.all()).single.submitted, isFalse);
    expect(find.textContaining('sending failed'), findsOneWidget);
    expect(find.byKey(const ValueKey('manual-count-done')), findsNothing);
  });
}

extension on BlockResult {
  Map<String, dynamic> toJsonForTest() => {
    'width': width,
    'depth': depth,
    'cells': [
      for (final c in cells)
        {'x': c.x, 'y': c.y, 'status': c.status, 'layers': c.layers},
    ],
    'observed_trays': observedTrays,
    'computed_trays': computedTrays,
    'total_trays': totalTrays,
    'total_eggs': totalEggs,
    'fully_observed': fullyObserved,
    'faces_consistent': facesConsistent,
    'faces_used': facesUsed,
    'conflicts': <Object>[],
    'rescan_cells': <Object>[],
    'note': note,
  };
}
