import 'dart:io';

import 'package:egg_tray_counter/features/capture/photo_upload_pane.dart';
import 'package:egg_tray_counter/models/capture_view.dart';
import 'package:egg_tray_counter/models/scan_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test(
    'upload owns a JPEG copy; cleanup preserves original; invalid input fails',
    () async {
      final dir = await Directory.systemTemp.createTemp('upload-test-');
      final original = File('${dir.path}/original.png');
      final image = img.Image(width: 480, height: 480);
      for (final pixel in image) {
        final value = ((pixel.x ~/ 8 + pixel.y ~/ 8) % 2 == 0) ? 65 : 190;
        pixel.setRgb(value, value, value);
      }
      final bytes = img.encodePng(image);
      await original.writeAsBytes(bytes);
      try {
        final copy = File(await prepareUploadedPhoto(original.path));
        expect(copy.path, isNot(original.path));
        expect(img.decodeJpg(await copy.readAsBytes()), isNotNull);
        await copy.delete();
        expect(await original.readAsBytes(), bytes);
        await original.writeAsString('not an image');
        await expectLater(
          prepareUploadedPhoto(original.path),
          throwsFormatException,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  testWidgets('requires three views and unchanged-scene confirmation', (
    tester,
  ) async {
    final session = ScanSession(scanId: 'upload');
    var submitted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhotoUploadPane(
            session: session,
            onComplete: (_) => submitted = true,
          ),
        ),
      ),
    );
    for (final view in CaptureView.values) {
      expect(find.text(view.title), findsOneWidget);
    }
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(submitted, isFalse);
    final dir = Directory.systemTemp.createTempSync('upload-ui-test-');
    final photo = File('${dir.path}/preview.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 8, height: 8)));
    try {
      for (final view in CaptureView.values) {
        session.setPath(view, photo.path);
      }
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      expect(submitted, isTrue);
      await tester.pumpWidget(const SizedBox());
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
