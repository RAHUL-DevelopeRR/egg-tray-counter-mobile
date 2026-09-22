import 'dart:math' as math;
import 'dart:typed_data';

import 'package:egg_tray_counter/models/capture_view.dart';
import 'package:egg_tray_counter/services/frame_evidence.dart';
import 'package:egg_tray_counter/services/frame_preflight.dart';
import 'package:egg_tray_counter/services/live_frame_preflight.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

FrameMetrics darkMetrics() => const FrameMetrics(
  analysisWidth: kAnalysisWidth,
  analysisHeight: 240,
  meanLuma: 15,
  clipLowFraction: 0.95,
  clipHighFraction: 0,
  sharpness: 2,
  guideCoverage: 0,
  guideTopEnergyRatio: 0,
  guideBottomEnergyRatio: 0,
  frameBorderEnergyShare: 0,
  bandLumaRatio: 1,
  verticalEdgeTiltDeg: null,
  horizontalEdgeTiltDeg: null,
  keystoneRatio: null,
);

void main() {
  group('devicePoseFromAccelerometer', () {
    test('holding the phone upright on the horizon reads as level', () {
      final pose = devicePoseFromAccelerometer(0, 9.81, 0)!;

      expect(pose.rollDeg, closeTo(0, 0.01));
      expect(pose.pitchDownDeg, closeTo(0, 0.01));
    });

    test('pointing the camera at the floor reads as 90 degrees down', () {
      final pose = devicePoseFromAccelerometer(0, 0, 9.81)!;

      expect(pose.rollDeg, closeTo(0, 0.01));
      expect(pose.pitchDownDeg, closeTo(90, 0.01));
    });

    test('leaning the top of the phone to the left reads as positive roll', () {
      final pose = devicePoseFromAccelerometer(
        9.81 * math.sin(math.pi / 6),
        9.81 * math.cos(math.pi / 6),
        0,
      )!;

      expect(pose.rollDeg, closeTo(30, 0.01));
      expect(pose.pitchDownDeg, closeTo(0, 0.01));
    });

    test('scale does not change the reading', () {
      final scaled = devicePoseFromAccelerometer(0, 0.98, 0.02)!;
      final raw = devicePoseFromAccelerometer(0, 9.8, 0.2)!;

      expect(scaled.rollDeg, closeTo(raw.rollDeg, 0.01));
      expect(scaled.pitchDownDeg, closeTo(raw.pitchDownDeg, 0.01));
    });

    test('a collapsed reading reports no attitude rather than a wrong one', () {
      final pose = devicePoseFromAccelerometer(0.01, 0.01, 0);

      expect(pose, isNull);
      expect(devicePoseFromAccelerometer(double.nan, 9.81, 0), isNull);
    });
  });

  group('lumaFromJpeg', () {
    Uint8List greyJpeg(int value, {int width = 64, int height = 48}) {
      final image = img.Image(width: width, height: height);
      img.fill(image, color: img.ColorRgb8(value, value, value));
      return Uint8List.fromList(img.encodeJpg(image));
    }

    test('decodes a still into luma at the analysis scale', () {
      final plane = lumaFromJpeg(greyJpeg(90));

      expect(plane, isNotNull);
      expect(plane!.width, 64);
      expect(plane.height, 48);
      expect(plane.luma.first, closeTo(90, 3));
    });

    test('reduces a large still to the analysis width', () {
      final plane = lumaFromJpeg(greyJpeg(200, width: 1280, height: 960));

      expect(plane!.width, kAnalysisWidth);
      expect(plane.height, 240);
    });

    test('reports undecodable bytes instead of inventing a frame', () {
      expect(lumaFromJpeg(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });
  });

  group('LiveFramePreflight', () {
    test('publishes a blocking verdict for a still taken in the dark', () {
      final live = LiveFramePreflight();
      addTearDown(live.dispose);

      final report = live.evaluateStill(darkMetrics());

      expect(report.blocked, isTrue);
      expect(report.firstBlocker?.headline, 'LIGHTING TOO LOW');
    });

    test('starts out waiting rather than ready', () {
      final live = LiveFramePreflight();
      addTearDown(live.dispose);

      expect(live.value.metrics, isNull);
      expect(live.value.blocked, isFalse);
      expect(live.value.measurable, isFalse);
      expect(live.frameFresh, isFalse);

      live.setView(CaptureView.straight);

      expect(live.value.primary?.headline, 'ANALYSIS STARTING');
    });

    test('carrying a level reference changes the published report', () {
      final live = LiveFramePreflight();
      addTearDown(live.dispose);
      live.setView(CaptureView.straight);

      live.setCalibration(
        const PoseCalibration(rollOffsetDeg: 3, referenceSet: true),
      );

      expect(live.calibration.isSet, isTrue);
      expect(
        live.value.checks.any(
          (check) => check.id == PreflightCheckId.calibration,
        ),
        isTrue,
      );
    });
  });
}
