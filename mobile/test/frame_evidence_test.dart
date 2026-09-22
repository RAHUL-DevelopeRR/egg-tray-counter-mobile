import 'dart:math' as math;
import 'dart:typed_data';

import 'package:egg_tray_counter/services/frame_evidence.dart';
import 'package:flutter_test/flutter_test.dart';

/// A synthetic tray wall: flat background, one block of tray texture in the
/// middle, and a flat outer ring so frame-border clipping stays out of the way.
LumaPlane syntheticScene({
  int width = kAnalysisWidth,
  int height = 240,
  int brightness = 120,
  int contrast = 70,
}) {
  final luma = Uint8List(width * height);
  final borderX = math.max(1, (width * 0.03).round());
  final borderY = math.max(1, (height * 0.03).round());
  for (var y = 0; y < height; y += 1) {
    for (var x = 0; x < width; x += 1) {
      final inBorder =
          x < borderX ||
          y < borderY ||
          x >= width - borderX ||
          y >= height - borderY;
      final inStack =
          x >= width * 0.15 &&
          x < width * 0.85 &&
          y >= height * 0.28 &&
          y < height * 0.72;
      var value = brightness;
      if (!inBorder && inStack) {
        final rim = y % 10 < 2;
        final wall = x % 24 < 2;
        if (rim && wall) {
          value = brightness - 2 * contrast;
        } else if (rim || wall) {
          value = brightness - contrast;
        }
      }
      luma[y * width + x] = value.clamp(0, 255);
    }
  }
  return LumaPlane(width: width, height: height, luma: luma);
}

LumaPlane flatScene(int value, {int width = kAnalysisWidth, int height = 240}) {
  final luma = Uint8List(width * height)..fillRange(0, width * height, value);
  return LumaPlane(width: width, height: height, luma: luma);
}

void main() {
  const analyzer = FrameAnalyzer();

  test('a well-framed tray wall measures inside every accepted band', () {
    final metrics = analyzer.analyze(syntheticScene());

    expect(metrics.meanLuma, inInclusiveRange(100, 130));
    expect(metrics.clipLowFraction, lessThan(0.4));
    expect(metrics.clipHighFraction, 0);
    expect(metrics.sharpness, greaterThan(30));
    expect(metrics.guideCoverage, greaterThan(0.35));
    // Flat margins above and below the stack: the load does not run past the
    // guide, so neither band may look busy.
    expect(metrics.guideTopEnergyRatio, lessThan(0.2));
    expect(metrics.guideBottomEnergyRatio, lessThan(0.2));
    expect(metrics.frameBorderEnergyShare, lessThan(0.05));
    expect(metrics.bandLumaRatio, lessThan(1.5));
    expect((metrics.verticalEdgeTiltDeg ?? 0).abs(), lessThanOrEqualTo(5));
    expect((metrics.horizontalEdgeTiltDeg ?? 0).abs(), lessThanOrEqualTo(5));
    expect(metrics.keystoneRatio, isNotNull);
    expect((metrics.keystoneRatio! - 1).abs(), lessThan(0.35));
  });

  test('a dark frame reports low light instead of inventing structure', () {
    final metrics = analyzer.analyze(flatScene(12));

    expect(metrics.meanLuma, lessThan(45));
    expect(metrics.clipLowFraction, greaterThan(0.9));
    expect(metrics.sharpness, lessThan(1));
    expect(metrics.guideCoverage, 0);
    // Without structure no direction can be claimed.
    expect(metrics.verticalEdgeTiltDeg, isNull);
    expect(metrics.horizontalEdgeTiltDeg, isNull);
    expect(metrics.keystoneRatio, isNull);
  });

  test('a softly lit but flat frame separates blur from darkness', () {
    final metrics = analyzer.analyze(flatScene(128));

    expect(metrics.meanLuma, closeTo(128, 0.5));
    expect(metrics.sharpness, lessThan(1));
    expect(metrics.guideCoverage, 0);
    expect(metrics.guideTopEnergyRatio, 0);
    expect(metrics.bandLumaRatio, 1);
  });

  test('tray texture running through the guide bottom is a cut base', () {
    // Flat background with the load continuing from the guide's lower third
    // through the bottom edge: the lowest layers cannot be counted.
    final width = kAnalysisWidth;
    final height = 240;
    final luma = Uint8List(width * height)..fillRange(0, width * height, 120);
    for (var y = (height * 0.75).round(); y < height; y += 1) {
      for (var x = (width * 0.15).round(); x < (width * 0.85).round(); x += 1) {
        final rim = y % 10 < 2;
        final wall = x % 24 < 2;
        luma[y * width + x] = rim || wall ? (rim && wall ? 0 : 50) : 120;
      }
    }
    final metrics = analyzer.analyze(
      LumaPlane(width: width, height: height, luma: luma),
    );

    expect(metrics.guideBottomEnergyRatio, greaterThan(0.45));
    // This layout still has plenty of structure away from the frame border, so
    // it is the guide test that has to fire, not the frame-clipping one.
    expect(metrics.frameBorderEnergyShare, lessThan(0.34));
  });

  test('detail only at the frame edge is reported as frame clipping', () {
    // An otherwise featureless frame where the load enters at the very bottom
    // edge: the stacks are cut by the photo border itself.
    final width = kAnalysisWidth;
    final height = 240;
    final luma = Uint8List(width * height)..fillRange(0, width * height, 120);
    for (var y = (height * 0.95).round(); y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        luma[y * width + x] = x % 8 < 2 ? 40 : 110;
      }
    }
    final metrics = analyzer.analyze(
      LumaPlane(width: width, height: height, luma: luma),
    );

    expect(metrics.frameBorderEnergyShare, greaterThan(0.34));
    expect(metrics.guideCoverage, lessThan(0.18));
  });

  test('luma sampling respects the plane stride', () {
    // Two rows of a 4-pixel-wide plane, padded to a 6-byte stride.
    final bytes = Uint8List.fromList([1, 2, 3, 4, 99, 99, 5, 6, 7, 8, 99, 99]);
    final plane = LumaPlane.sample(
      bytes,
      width: 4,
      height: 2,
      rowStride: 6,
      targetWidth: 4,
    );

    expect(plane.width, 4);
    expect(plane.height, 2);
    expect(plane.luma, [1, 2, 3, 4, 5, 6, 7, 8]);
  });

  test('metrics serialise the numbers the operator was shown', () {
    final json = analyzer.analyze(syntheticScene()).toJson();

    expect(json['analysis_width'], kAnalysisWidth);
    expect(json['mean_luma'], isA<double>());
    expect(json['sharpness'], isA<double>());
    expect(json.containsKey('keystone_ratio'), isTrue);
  });

  test(
    'rotation and pixel stride map the live plane into upright coordinates',
    () {
      final plane = LumaPlane.sample(
        Uint8List.fromList([1, 99, 2, 99, 3, 99, 4, 99, 5, 99, 6]),
        width: 3,
        height: 2,
        rowStride: 6,
        pixelStride: 2,
        rotationDegrees: 90,
        targetWidth: 2,
      );
      expect(plane.width, 2);
      expect(plane.height, 3);
      expect(plane.luma, [4, 1, 5, 2, 6, 3]);
      expect(
        () => LumaPlane.sample(Uint8List(3), width: 3, height: 2, rowStride: 3),
        throwsArgumentError,
      );
    },
  );

  test('a black half remains unevenly lit instead of returning ratio one', () {
    final plane = flatScene(120);
    plane.luma.fillRange(plane.luma.length ~/ 2, plane.luma.length, 0);
    final metrics = const FrameAnalyzer(
      guide: NormalizedRect.full,
    ).analyze(plane);
    expect(metrics.bandLumaRatio, greaterThan(2.6));
    expect(metrics.bottomMeanLuma, 0);
  });

  group('mapGuideToStill', () {
    const guide = NormalizedRect(0.10, 0.10, 0.90, 0.88);

    test('leaves the guide alone when both crops share an aspect ratio', () {
      final mapped = mapGuideToStill(
        guide,
        previewAspect: 0.75,
        stillAspect: 0.75,
      );
      expect(mapped.left, 0.10);
      expect(mapped.top, 0.10);
      expect(mapped.right, 0.90);
      expect(mapped.bottom, 0.88);
    });

    test('narrows the guide when the preview crop is narrower', () {
      final mapped = mapGuideToStill(
        guide,
        previewAspect: 0.5625,
        stillAspect: 0.75,
      );
      expect(mapped.left, closeTo(0.20, 0.001));
      expect(mapped.right, closeTo(0.80, 0.001));
      expect(mapped.top, 0.10);
      expect(mapped.bottom, 0.88);
    });

    test('shortens the guide when the preview crop is wider', () {
      final mapped = mapGuideToStill(
        guide,
        previewAspect: 0.75,
        stillAspect: 0.5625,
      );
      expect(mapped.left, 0.10);
      expect(mapped.right, 0.90);
      expect(mapped.top, closeTo(0.20, 0.001));
      expect(mapped.bottom, closeTo(0.785, 0.001));
    });
  });
}
