import 'package:egg_tray_counter/features/scan_flow/declaration_pane.dart';
import 'package:egg_tray_counter/features/scan_flow/elevated_tap_grid.dart';
import 'package:egg_tray_counter/features/scan_flow/extra_views_pane.dart';
import 'package:egg_tray_counter/models/block_declaration.dart';
import 'package:egg_tray_counter/models/extra_capture.dart';
import 'package:egg_tray_counter/models/scan_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _tap(WidgetTester tester, String key, {int times = 1}) async {
  for (var i = 0; i < times; i++) {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
  }
}

void main() {
  group('declaration pane', () {
    Future<(List<BlockDeclaration>, List<bool>)> show(
      WidgetTester tester,
    ) async {
      _tall(tester);
      final declared = <BlockDeclaration>[];
      final skipped = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeclarationPane(
              onDeclare: declared.add,
              onSkip: () => skipped.add(true),
              now: () => DateTime.utc(2026, 11, 1, 10, 0, 0, 123),
            ),
          ),
        ),
      );
      return (declared, skipped);
    }

    testWidgets('every field starts unknown and is sent as the contract '
        'declaration, timestamped when saved', (tester) async {
      final (declared, skipped) = await show(tester);
      // Nothing is pre-declared: a field left alone states nothing.
      final untouched = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('decl-interior-unknown')),
      );
      expect(untouched.selected, isTrue);

      await _tap(tester, 'decl-x-plus', times: 4);
      await _tap(tester, 'decl-y-plus', times: 2);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('decl-x-value'))).data,
        '5',
      );
      await _tap(tester, 'decl-interior-full');
      await _tap(tester, 'missing-2-1');
      // A partial stack at x4 y0, 12 layers.
      await tester.tap(find.byKey(const ValueKey('partial-x')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('partial-layers')), '12');
      await _tap(tester, 'partial-add');
      expect(find.text('x4 y0: 12 layers'), findsOneWidget);
      await _tap(tester, 'decl-cover-no');
      await _tap(tester, 'decl-occupancy-egg_filled');
      await tester.enterText(find.byKey(const ValueKey('decl-height')), '20');
      await _tap(tester, 'decl-height-measured');
      await tester.enterText(find.byKey(const ValueKey('decl-operator')), 'OP7');
      await _tap(tester, 'declare-continue');

      expect(skipped, isEmpty);
      expect(declared.single.toJson(), {
        'x': 5,
        'y': 3,
        'interior': 'full',
        'missing_cells': [
          [2, 1],
        ],
        'partial_stacks': [
          {'x': 4, 'y': 0, 'layers': 12},
        ],
        'cover_trays': 'no',
        'occupancy': 'egg_filled',
        'reference_height': 20,
        'reference_height_measured': true,
        'operator': 'OP7',
        'declared_at': '2026-11-01T10:00:00Z',
      });
      expect(declared.single.encode()!.length, lessThan(4000));
    });

    testWidgets('SKIP DECLARATION declares nothing', (tester) async {
      final (declared, skipped) = await show(tester);
      await _tap(tester, 'declare-skip');
      expect(skipped, [true]);
      expect(declared, isEmpty);
      expect(
        find.text('Without a declaration the result can never be CONFIRMED.'),
        findsOneWidget,
      );
    });

    testWidgets('a height ticked as measured must be given; an unticked '
        'height is sent as unmeasured', (tester) async {
      final (declared, _) = await show(tester);
      await _tap(tester, 'decl-height-measured');
      await _tap(tester, 'declare-continue');
      expect(declared, isEmpty);
      expect(find.textContaining('Enter the height you measured'), findsOneWidget);
      await _tap(tester, 'decl-height-measured');
      await tester.enterText(find.byKey(const ValueKey('decl-height')), '18');
      await _tap(tester, 'declare-continue');
      expect(declared.single.referenceHeight, 18);
      expect(declared.single.referenceHeightMeasured, isFalse);
      expect(declared.single.toJson()['interior'], 'unknown');
      expect(declared.single.toJson()['occupancy'], 'unknown');
      expect(declared.single.toJson()['cover_trays'], 'unknown');
    });

    testWidgets('a smaller grid drops the cells that no longer fit, and the '
        'size stays within 1-40', (tester) async {
      final (declared, _) = await show(tester);
      await _tap(tester, 'decl-x-plus', times: 2);
      await _tap(tester, 'missing-2-0');
      await _tap(tester, 'missing-0-0');
      await _tap(tester, 'decl-x-minus');
      expect(find.byKey(const ValueKey('missing-2-0')), findsNothing);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('decl-y-minus')))
            .onPressed,
        isNull,
      );
      await _tap(tester, 'declare-continue');
      expect(declared.single.x, 2);
      expect(declared.single.missingCells, [
        [0, 0],
      ]);
    });
  });

  group('elevated tap grid', () {
    test('a tap cycles untapped, present, missing, step down, unsure, and '
        'round to present', () {
      expect(ElevatedTaps.nextState(null), kTapPresent);
      expect(ElevatedTaps.nextState(kTapPresent), kTapMissing);
      expect(ElevatedTaps.nextState(kTapMissing), kTapStepDown);
      expect(ElevatedTaps.nextState(kTapStepDown), kTapUnsure);
      expect(ElevatedTaps.nextState(kTapUnsure), kTapPresent);
      var taps = const ElevatedTaps(x: 2, y: 1);
      for (var i = 0; i < 3; i++) {
        taps = taps.tap(1, 0);
      }
      taps = taps.tap(0, 0);
      expect(taps.toJson(), {
        'x': 2,
        'y': 1,
        'cells': [
          {'x': 0, 'y': 0, 'state': 'present'},
          {'x': 1, 'y': 0, 'state': 'step_down'},
        ],
      });
      expect(ElevatedTaps.fromJson(taps.toJson())!.cells, taps.cells);
    });

    testWidgets('the declared size is used; untapped cells are not sent', (
      tester,
    ) async {
      _tall(tester);
      final done = <ElevatedTaps>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ElevatedTapGrid(
              x: 3,
              y: 2,
              onDone: done.add,
              onSkip: () {},
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('tap-2-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('taps-x-plus')), findsNothing);
      String mark(String key) => tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byType(Text),
            ),
          )
          .data!;
      final seen = <String>[];
      for (var i = 0; i < 5; i++) {
        await _tap(tester, 'tap-0-0');
        seen.add(mark('tap-0-0'));
      }
      expect(seen, ['P', 'X', 'v', '?', 'P']);
      await _tap(tester, 'tap-2-1', times: 2);
      expect(find.text('2 of 6 cells read.'), findsOneWidget);
      await _tap(tester, 'taps-done');
      expect(done.single.toJson(), {
        'x': 3,
        'y': 2,
        'cells': [
          {'x': 0, 'y': 0, 'state': 'present'},
          {'x': 2, 'y': 1, 'state': 'missing'},
        ],
      });
    });

    testWidgets('without a declaration X and Y are asked first', (
      tester,
    ) async {
      _tall(tester);
      final done = <ElevatedTaps>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ElevatedTapGrid(onDone: done.add, onSkip: () {}),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('tap-0-0')), findsNothing);
      await _tap(tester, 'taps-x-plus', times: 3);
      await _tap(tester, 'taps-y-plus');
      await _tap(tester, 'taps-size-done');
      expect(find.byKey(const ValueKey('tap-3-1')), findsOneWidget);
      await _tap(tester, 'tap-3-1', times: 4);
      await _tap(tester, 'taps-done');
      expect(done.single.toJson(), {
        'x': 4,
        'y': 2,
        'cells': [
          {'x': 3, 'y': 1, 'state': 'unsure'},
        ],
      });
    });
  });

  group('optional extra photos', () {
    testWidgets('both extras are offered; the corner side is chosen; upload '
        'never waits for them', (tester) async {
      _tall(tester);
      final session = ScanSession(scanId: 'e1');
      final corners = <String>[];
      var elevated = 0;
      var uploads = 0;
      Widget pane() => MaterialApp(
        home: Scaffold(
          body: ExtraViewsPane(
            session: session,
            onCorner: corners.add,
            onElevated: () => elevated++,
            onEditTaps: () {},
            onRemove: session.clearExtra,
            onUpload: () => uploads++,
          ),
        ),
      );
      await tester.pumpWidget(pane());
      expect(find.text('Add a CORNER photo (optional)'), findsOneWidget);
      expect(find.text('Add an ELEVATED photo (optional)'), findsOneWidget);
      await _tap(tester, 'extras-upload');
      expect(uploads, 1);
      await tester.tap(find.text('FRONT RIGHT'));
      await tester.pump();
      await _tap(tester, 'add-corner');
      expect(corners, [kCornerFrontRight]);
      await _tap(tester, 'add-elevated');
      expect(elevated, 1);

      session
        ..setExtra(ExtraView.corner, 'c.jpg', side: kCornerFrontLeft)
        ..setExtra(ExtraView.elevated, 'e.jpg')
        ..setElevatedTaps(const ElevatedTaps(x: 5, y: 3).tap(0, 0).tap(1, 0));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(pane());
      expect(find.text('Taken from the front left corner.'), findsOneWidget);
      expect(find.text('Taken; 2 of 15 cells read.'), findsOneWidget);
      expect(find.text('RETAKE CORNER PHOTO'), findsOneWidget);
    });
  });
}
