import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:egg_tray_counter/models/reconstruction_result.dart';
import 'package:egg_tray_counter/services/reconstruction_photos.dart';
import 'package:egg_tray_counter/services/settings_store.dart';
import 'package:egg_tray_counter/features/reconstruction/reconstruction_screen.dart';

class _TestSettings implements SettingsStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('projection and orbit have known geometry', () {
    expect(projectPoint([0, 0, 0], 1), [0, 0, 4]);
    expect(projectPoint([4, 2, 0], 1), [1, .5, 4]);
    expect(projectPoint([0, 0, -5], 1), isNull);
    expect(orbitPoint([1, 2, 3], 0, 0), [1, 2, 3]);
  });
  test('parser rejects count claims and accepts diagnostic failure', () {
    final json = <String, dynamic>{
      'status': 'insufficient_matches',
      'reason': 'Need overlap',
      'physical_trays': null,
      'verified': false,
      'scale': 'arbitrary_unit_baseline',
      'focal_hypotheses': [],
    };
    expect(ReconstructionResult.fromJson(json).status, 'insufficient_matches');
    expect(
      () => ReconstructionResult.fromJson({...json, 'physical_trays': 99}),
      throwsFormatException,
    );
    expect(
      () => ReconstructionResult.fromJson({...json, 'status': 'reconstructed'}),
      throwsFormatException,
    );
  });
  test(
    'pair constraints preserve originals and reject duplicates or unequal dimensions',
    () async {
      final dir = await Directory.systemTemp.createTemp('reconstruction-test');
      try {
        final a = File('${dir.path}/a.jpg'),
            b = File('${dir.path}/b.jpg'),
            c = File('${dir.path}/c.jpg');
        await a.writeAsBytes(img.encodeJpg(img.Image(width: 64, height: 64)));
        await b.writeAsBytes(
          img.encodeJpg(
            img.fill(
              img.Image(width: 64, height: 64),
              color: img.ColorRgb8(255, 0, 0),
            ),
          ),
        );
        await c.writeAsBytes(img.encodeJpg(img.Image(width: 80, height: 64)));
        expect(
          () => prepareReconstructionPair([a.path, a.path]),
          throwsFormatException,
        );
        expect(
          () => prepareReconstructionPair([a.path, c.path]),
          throwsFormatException,
        );
        final pair = await prepareReconstructionPair([a.path, b.path]);
        expect(pair.paths, [a.path, b.path]);
        expect(pair.metadata['resized'], false);
        expect(pair.metadata['exif_missing'], [true, true]);
        final oversized = File('${dir.path}/oversized.jpg');
        await oversized.writeAsBytes([
          ...await a.readAsBytes(),
          ...List<int>.filled(2000000, 0),
        ]);
        final resized = await prepareReconstructionPair([
          oversized.path,
          b.path,
        ]);
        expect(resized.metadata['resized'], true);
        final first = img.decodeImage(
          await File(resized.paths[0]).readAsBytes(),
        )!;
        final second = img.decodeImage(
          await File(resized.paths[1]).readAsBytes(),
        )!;
        expect([first.width, first.height], [second.width, second.height]);
        expect(
          await File(resized.paths[0]).length(),
          lessThanOrEqualTo(2000000),
        );
        await resized.dispose();
        await pair.dispose();
        expect(await a.exists(), true);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'diagnostic banner persists and no inventory result is displayed',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ReconstructionScreen(settings: _TestSettings())),
      );
      expect(find.text(reconstructionBanner), findsOneWidget);
      expect(find.text('RECONSTRUCT 3D'), findsOneWidget);
      expect(find.textContaining('Total trays'), findsNothing);
      expect(find.textContaining('VERIFIED'), findsNothing);
    },
  );
}
