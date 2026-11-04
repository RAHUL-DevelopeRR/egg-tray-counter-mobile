import 'dart:io';
import 'dart:typed_data';

import 'package:egg_tray_counter/features/capture/photo_upload_pane.dart';
import 'package:egg_tray_counter/models/capture_view.dart';
import 'package:egg_tray_counter/models/scan_session.dart';
import 'package:egg_tray_counter/services/captured_still.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// The checkerboard the quality check accepts (sharp, mid contrast).
img.Image _checker(int width, int height) {
  final image = img.Image(width: width, height: height);
  for (final pixel in image) {
    final value = ((pixel.x ~/ 8 + pixel.y ~/ 8) % 2 == 0) ? 65 : 190;
    pixel.setRgb(value, value, value);
  }
  return image;
}

/// [jpeg] with its frame header rewritten to claim [width] x [height], so a
/// size check can be tested without building a 50 MP image.
Uint8List _claimSize(Uint8List jpeg, int width, int height) {
  final out = Uint8List.fromList(jpeg);
  for (var i = 2; i + 9 < out.length; i++) {
    if (out[i] == 0xFF && out[i + 1] == 0xC0) {
      out[i + 5] = height >> 8;
      out[i + 6] = height & 0xFF;
      out[i + 7] = width >> 8;
      out[i + 8] = width & 0xFF;
      return out;
    }
  }
  throw StateError('no SOF0 marker');
}

void main() {
  test('pixel size comes from the JPEG frame header or PNG IHDR', () {
    final withExif = _checker(64, 48)..exif.imageIfd.orientation = 6;
    final jpeg = img.encodeJpg(withExif);
    expect(encodedPixelSize(jpeg), (width: 64, height: 48));
    expect(encodedPixelSize(_claimSize(jpeg, 8192, 6144)), (
      width: 8192,
      height: 6144,
    ));
    expect(encodedPixelSize(img.encodePng(_checker(30, 20))), (
      width: 30,
      height: 20,
    ));
    expect(encodedPixelSize(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
  });

  test(
    'a photo over 40 megapixels is shrunk to the upload size, not refused',
    () async {
      final dir = await Directory.systemTemp.createTemp('upload-big-');
      final big = File('${dir.path}/big.jpg')
        ..writeAsBytesSync(
          _claimSize(img.encodeJpg(_checker(64, 48)), 8192, 6144),
        );
      final original = big.readAsBytesSync();
      try {
        await expectLater(
          prepareUploadedPhoto(big.path),
          throwsA(isA<OversizedPhotoException>()),
        );
        late String shrunk;
        final copy = await prepareGalleryPhoto(
          big.path,
          shrink: (source, longSide) async {
            expect(source, big.path);
            expect(longSide, kUploadLongSide);
            shrunk = '${dir.path}/shrunk.png';
            File(shrunk).writeAsBytesSync(img.encodePng(_checker(1600, 1200)));
            return shrunk;
          },
        );
        final out = img.decodeJpg(File(copy).readAsBytesSync())!;
        expect((out.width, out.height), (1600, 1200));
        expect(File(shrunk).existsSync(), isFalse);
        expect(big.readAsBytesSync(), original);
        File(copy).deleteSync();
      } finally {
        dir.deleteSync(recursive: true);
      }
    },
  );

  testWidgets(
    'the platform decoder shrinks to the long side and turns upright',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('upload-shrink-');
      // Stored 3200 x 1600 with EXIF orientation 6: upright it is portrait.
      final source = File('${dir.path}/rotated.jpg')
        ..writeAsBytesSync(
          img.encodeJpg(_checker(3200, 1600)..exif.imageIfd.orientation = 6),
        );
      try {
        final path = await tester.runAsync(
          () => shrinkWithPlatformDecoder(source.path, kUploadLongSide),
        );
        final out = img.decodePng(File(path!).readAsBytesSync())!;
        expect((out.width, out.height), (800, 1600));
      } finally {
        dir.deleteSync(recursive: true);
      }
    },
  );

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
