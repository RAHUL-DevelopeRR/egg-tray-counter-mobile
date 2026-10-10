import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'frame_evidence.dart';
import 'image_quality_service.dart';
import 'live_frame_preflight.dart';

/// How the phone is held while the screen stays portrait, in the Android
/// display-rotation convention: 0 upright, 90 turned counter-clockwise (top
/// of the phone to the operator's left, raw roll near +90), 270 turned
/// clockwise (raw roll near -90).
///
/// The bands give hysteresis: from upright the phone has to roll past 60
/// degrees before the photo turns landscape, and back under 30 degrees before
/// it turns portrait again, so a hand wobbling around 45 degrees never flips
/// it. Upside down (beyond 135 degrees) and unreadable rolls keep the current
/// value.
int nextCaptureRotation(int current, double? rawRollDeg) {
  if (rawRollDeg == null || !rawRollDeg.isFinite) return current;
  if (rawRollDeg.abs() < 30) return 0;
  if (rawRollDeg > 60 && rawRollDeg < 135) return 90;
  if (rawRollDeg < -60 && rawRollDeg > -135) return 270;
  return current;
}

/// Clockwise degrees that turn the picture the portrait screen showed into
/// the picture the operator saw through the phone. Turned counter-clockwise
/// (90) the screen shows the world rotated clockwise, so it is turned back by
/// 270, and the other way round.
int stillRotationCw(int captureRotation) => (360 - captureRotation) % 360;

/// What [prepareCapturedStill] needs. Plain values only, so it can be sent to
/// a background isolate.
class StillRequest {
  const StillRequest({
    required this.sourcePath,
    required this.targetPath,
    required this.captureRotation,
    required this.sensorOrientation,
  });

  /// The JPEG the camera plugin wrote.
  final String sourcePath;

  /// Where the upright copy is written.
  final String targetPath;

  /// 0, 90 or 270 from [nextCaptureRotation] at the moment of capture.
  final int captureRotation;

  /// Camera sensor orientation, used only when the JPEG carries no
  /// orientation tag and its pixels are still in sensor orientation.
  final int sensorOrientation;
}

/// The photo that is uploaded, plus the measurements taken from it.
class PreparedStill {
  const PreparedStill({
    required this.path,
    required this.width,
    required this.height,
    required this.analysis,
    required this.quality,
    required this.captureRotation,
  });

  /// Upright JPEG of the whole camera frame (the viewfinder shows all of
  /// it), with no orientation tag.
  final String path;
  final int width;
  final int height;

  /// The same upright frame at analysis width, so the guide checks see the
  /// geometry the live frames had.
  final LumaPlane analysis;

  /// Blur and exposure of the uploaded picture itself.
  final LocalQualityResult quality;

  final int captureRotation;

  bool get landscape => width > height;
}

/// Turns a captured still into the upload: upright pixels whichever way the
/// phone was held, with no orientation tag left for a viewer or the server to
/// apply twice. The frame is never trimmed: a very wide trim (20:9, the shape
/// of this phone's screen) was measured to cost the detector a layer on some
/// stacks (staging, 2026-10-09), and the viewfinder shows the whole frame.
///
/// Runs on a background isolate; one 1080p decode, rotate, crop and encode.
Future<PreparedStill?> prepareCapturedStill(StillRequest request) =>
    compute(prepareCapturedStillSync, request);

/// Synchronous body of [prepareCapturedStill]; public for tests.
PreparedStill? prepareCapturedStillSync(StillRequest request) {
  final Uint8List bytes;
  try {
    bytes = File(request.sourcePath).readAsBytesSync();
  } on FileSystemException {
    return null;
  }
  img.Image? decoded;
  try {
    decoded = img.decodeJpg(bytes) ?? img.decodeImage(bytes);
  } on Object {
    // Truncated files make the decoder throw; the caller asks for a retake.
    return null;
  }
  if (decoded == null) return null;

  // The JPEG decoder applies the EXIF orientation, so this is the picture as
  // the portrait screen showed it; bakeOrientation covers other decoders.
  var screen = img.bakeOrientation(decoded);
  if (screen.width > screen.height && request.sensorOrientation % 180 == 90) {
    // A portrait screen always yields a portrait still unless the device
    // wrote sensor-oriented pixels without a tag.
    screen = img.copyRotate(screen, angle: request.sensorOrientation);
  }

  final turn = stillRotationCw(request.captureRotation);
  final upload = turn == 0 ? screen : img.copyRotate(screen, angle: turn);
  upload.exif.imageIfd.orientation = null;
  final analysis = lumaFromImage(upload);

  final quality = const ImageQualityService().inspectImage(upload);
  try {
    File(
      request.targetPath,
    ).writeAsBytesSync(img.encodeJpg(upload, quality: 95), flush: true);
  } on FileSystemException {
    return null;
  }
  return PreparedStill(
    path: request.targetPath,
    width: upload.width,
    height: upload.height,
    analysis: analysis,
    quality: quality,
    captureRotation: request.captureRotation,
  );
}
