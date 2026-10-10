import 'dart:io';

import 'package:egg_tray_counter/services/captured_still.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// The scene as the operator sees it: grey, a red block near the top-left
/// and a green floor band near the bottom.
img.Image _scene(int width, int height) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(128, 128, 128));
  img.fillRect(
    image,
    x1: (width * 0.08).round(),
    y1: (height * 0.20).round(),
    x2: (width * 0.30).round(),
    y2: (height * 0.40).round(),
    color: img.ColorRgb8(230, 20, 20),
  );
  img.fillRect(
    image,
    x1: 0,
    y1: (height * 0.72).round(),
    x2: width - 1,
    y2: (height * 0.85).round(),
    color: img.ColorRgb8(20, 200, 20),
  );
  return image;
}

/// What the phone writes with the screen locked portrait: CameraX tags every
/// still with the portrait display rotation (EXIF 6 on a back camera with
/// sensorOrientation 90), and the sensor pixels relate to the scene by how
/// the phone is held. Upright the sensor sees the scene turned
/// counter-clockwise; turned counter-clockwise the sensor sees it upright;
/// turned clockwise it sees it upside down.
File _phoneStill(Directory dir, img.Image scene, int captureRotation) {
  final pixels = switch (captureRotation) {
    90 => img.Image.from(scene),
    270 => img.copyRotate(scene, angle: 180),
    _ => img.copyRotate(scene, angle: -90),
  };
  pixels.exif.imageIfd.orientation = 6;
  final file = File('${dir.path}/raw-$captureRotation.jpg')
    ..writeAsBytesSync(img.encodeJpg(pixels, quality: 95));
  return file;
}

bool _red(img.Image image, double fx, double fy) {
  final p = image.getPixel(
    (image.width * fx).round(),
    (image.height * fy).round(),
  );
  return p.r > 170 && p.g < 90 && p.b < 90;
}

bool _green(img.Image image, double fx, double fy) {
  final p = image.getPixel(
    (image.width * fx).round(),
    (image.height * fy).round(),
  );
  return p.g > 150 && p.r < 90 && p.b < 90;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('still-test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('portrait/sideways bands have hysteresis and ignore upside down', () {
    expect(nextCaptureRotation(0, 10), 0);
    expect(nextCaptureRotation(0, 45), 0);
    // Top of the phone to the operator's left: turned counter-clockwise.
    expect(nextCaptureRotation(0, 70), 90);
    expect(nextCaptureRotation(0, -70), 270);
    expect(nextCaptureRotation(90, 45), 90);
    expect(nextCaptureRotation(90, 25), 0);
    expect(nextCaptureRotation(270, -45), 270);
    expect(nextCaptureRotation(90, -80), 270);
    expect(nextCaptureRotation(90, 170), 90);
    expect(nextCaptureRotation(0, -175), 0);
    expect(nextCaptureRotation(270, null), 270);
    expect(nextCaptureRotation(0, double.nan), 0);
    expect(stillRotationCw(0), 0);
    expect(stillRotationCw(90), 270);
    expect(stillRotationCw(270), 90);
  });

  for (final rotation in [0, 90, 270]) {
    test('held at $rotation: the upload is the scene upright, no tag', () {
      final scene = rotation == 0 ? _scene(180, 320) : _scene(320, 180);
      final raw = _phoneStill(dir, scene, rotation);
      final prepared = prepareCapturedStillSync(
        StillRequest(
          sourcePath: raw.path,
          targetPath: '${dir.path}/upright-$rotation.jpg',
          captureRotation: rotation,
          sensorOrientation: 90,
        ),
      );
      expect(prepared, isNotNull);
      final bytes = File(prepared!.path).readAsBytesSync();
      final exif = img.decodeJpgExif(bytes);
      expect(exif?.imageIfd.hasOrientation ?? false, isFalse);
      final out = img.decodeJpg(bytes)!;
      expect(out.width, scene.width);
      expect(out.height, scene.height);
      expect(prepared.landscape, rotation != 0);
      expect(_red(out, 0.19, 0.30), isTrue, reason: 'red block top-left');
      expect(_green(out, 0.5, 0.78), isTrue, reason: 'floor at the bottom');
      expect(_red(out, 0.81, 0.30), isFalse);
      expect(_green(out, 0.5, 0.22), isFalse);
      // The analysis plane is the whole upright frame, same orientation.
      expect(prepared.analysis.width > prepared.analysis.height, rotation != 0);
    });
  }

  test('the whole camera frame is uploaded, never trimmed', () {
    // A 20:9 trim to the screen shape was measured to cost the detector a
    // layer on some stacks; the viewfinder shows the whole frame instead.
    for (final rotation in [0, 90, 270]) {
      final scene = rotation == 0
          ? _scene(1080 ~/ 4, 1920 ~/ 4)
          : _scene(1920 ~/ 4, 1080 ~/ 4);
      final prepared = prepareCapturedStillSync(
        StillRequest(
          sourcePath: _phoneStill(dir, scene, rotation).path,
          targetPath: '${dir.path}/full-$rotation.jpg',
          captureRotation: rotation,
          sensorOrientation: 90,
        ),
      )!;
      expect((prepared.width, prepared.height), (scene.width, scene.height));
      expect(
        prepared.analysis.width / prepared.analysis.height,
        closeTo(scene.width / scene.height, 0.02),
      );
    }
  });

  test('an untagged sensor-oriented still is turned upright first', () {
    final scene = _scene(180, 320);
    final pixels = img.copyRotate(scene, angle: -90); // no EXIF tag
    final raw = File('${dir.path}/untagged.jpg')
      ..writeAsBytesSync(img.encodeJpg(pixels, quality: 95));
    final prepared = prepareCapturedStillSync(
      StillRequest(
        sourcePath: raw.path,
        targetPath: '${dir.path}/untagged-upright.jpg',
        captureRotation: 0,
        sensorOrientation: 90,
      ),
    )!;
    final out = img.decodeJpg(File(prepared.path).readAsBytesSync())!;
    expect(out.height > out.width, isTrue);
    expect(_red(out, 0.19, 0.30), isTrue);
    expect(_green(out, 0.5, 0.78), isTrue);
  });

  test('an unreadable file gives null, never a crash', () {
    final raw = File('${dir.path}/broken.jpg')..writeAsBytesSync([1, 2, 3]);
    expect(
      prepareCapturedStillSync(
        StillRequest(
          sourcePath: raw.path,
          targetPath: '${dir.path}/x.jpg',
          captureRotation: 90,
          sensorOrientation: 90,
        ),
      ),
      isNull,
    );
  });
}
