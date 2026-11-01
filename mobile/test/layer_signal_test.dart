import 'dart:math' as math;
import 'dart:typed_data';

import 'package:egg_tray_counter/services/frame_evidence.dart';
import 'package:egg_tray_counter/services/layer_signal.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tray rims as dark lines every [pitch] rows over [top, bottom) of the
/// columns [left, right), on a mid-grey background with mild noise. Columns
/// from [secondFrom] of the width on use [secondPitch] (a second block).
LumaPlane rims({
  int width = 400,
  int height = 800,
  double pitch = 23.4,
  double top = 120,
  double bottom = 680,
  int left = 0,
  int? right,
  double? secondPitch,
  double secondFrom = 0.75,
  int seed = 7,
}) {
  final random = math.Random(seed);
  final luma = Uint8List(width * height);
  final edge = right ?? width;
  for (var y = 0; y < height; y += 1) {
    for (var x = 0; x < width; x += 1) {
      var value = 140 + random.nextInt(9) - 4;
      final p = secondPitch != null && x >= width * secondFrom
          ? secondPitch
          : pitch;
      if (x >= left && x < edge && y >= top && y < bottom) {
        final phase = (y - top) % p;
        if (phase < 3) value = 60 + random.nextInt(9) - 4;
      }
      luma[y * width + x] = value.clamp(0, 255);
    }
  }
  return LumaPlane(width: width, height: height, luma: luma);
}

void main() {
  test('pitch with a sub-pixel peak, and the run inside the frame', () {
    final signal = estimateLayerSignal(rims());
    expect(signal.pitchPx, closeTo(23.4, 0.3));
    expect(signal.pitchFrac, closeTo(23.4 / 800, 0.001));
    expect(signal.strength, greaterThan(0.5));
    // First rim near row 120, last near the final rim above row 680.
    expect(signal.topY, closeTo(121, 3));
    expect(signal.baseY, closeTo(120 + 23 * 23.4, 4));
    expect(signal.touchesTop, isFalse);
    expect(signal.touchesBottom, isFalse);
    expect(signal.pitchConsistency, closeTo(1, 0.05));
    expect(signal.runStrips, hasLength(kLayerStrips));
  });

  test('a stack that continues past the frame bottom touches it', () {
    final signal = estimateLayerSignal(rims(bottom: 800));
    expect(signal.touchesBottom, isTrue);
    expect(signal.stripsTouchingBottom, hasLength(kLayerStrips));
    expect(signal.touchesTop, isFalse);
  });

  test('a stack cut by the frame top touches it', () {
    final signal = estimateLayerSignal(rims(top: -11.7, bottom: 600));
    expect(signal.touchesTop, isTrue);
    expect(signal.touchesBottom, isFalse);
  });

  test('only strips on a frame side with a run touch that side', () {
    final atLeft = estimateLayerSignal(rims(right: 200));
    expect(atLeft.touchesLeft, isTrue);
    expect(atLeft.touchesRight, isFalse);
    // Strips beyond the stack carry no run.
    expect(atLeft.strips.last.hasRun, isFalse);

    final inside = estimateLayerSignal(rims(left: 60, right: 340));
    expect(inside.touchesLeft, isFalse);
    expect(inside.touchesRight, isFalse);
  });

  test('a second block at another distance shows as poor consistency', () {
    // A quarter of the band holds a block whose layers are 30% larger.
    final signal = estimateLayerSignal(rims(pitch: 20, secondPitch: 26));
    expect(signal.pitchPx, closeTo(20, 0.5));
    expect(signal.strips.first.pitchPx, closeTo(20, 0.5));
    expect(signal.strips.last.pitchPx, closeTo(26, 0.7));
    expect(signal.pitchConsistency, greaterThan(1.2));

    final single = estimateLayerSignal(rims(pitch: 20));
    expect(single.pitchConsistency, lessThan(1.05));
  });

  test('a flat frame has no pitch and no run', () {
    final plane = LumaPlane(
      width: 200,
      height: 300,
      luma: Uint8List(200 * 300)..fillRange(0, 200 * 300, 128),
    );
    final signal = estimateLayerSignal(plane);
    expect(signal.pitchPx, isNull);
    expect(signal.runStrips, isEmpty);
    expect(signal.touchesTop || signal.touchesBottom, isFalse);
    expect(signal.pitchConsistency, isNull);
  });

  test('the shortest strong lag wins over its multiples', () {
    // Rims every 20 rows with every other rim stronger: the 40-row lag is the
    // strongest peak, the 20-row lag is still strong and wins.
    final profile = Float64List(400);
    for (var y = 0; y < 400; y += 1) {
      if (y % 20 == 0) profile[y] = y % 40 == 0 ? 10 : 8;
    }
    final correlation = autocorrelation(profile, 100)!;
    final estimate = pitchFromAutocorrelation(correlation, 8, 100)!;
    expect(estimate.pitch, closeTo(20, 0.5));
  });

  test('a band limits the strips to the guide', () {
    final signal = estimateLayerSignal(
      rims(),
      band: const NormalizedRect(0.25, 0.1, 0.75, 0.9),
      strips: 8,
    );
    expect(signal.strips.first.x0, 100);
    expect(signal.strips.last.x1, 300);
    expect(signal.touchesLeft, isFalse);
    expect(signal.pitchPx, closeTo(23.4, 0.3));
  });

  test('timing helper reports the run time and rejects tiny planes', () {
    final timed = timedLayerSignal(rims(width: 160, height: 320));
    expect(timed.elapsed, greaterThanOrEqualTo(Duration.zero));
    expect(timed.signal.pitchPx, closeTo(23.4, 0.4));
    expect(
      () => estimateLayerSignal(
        LumaPlane(width: 8, height: 8, luma: Uint8List(64)),
      ),
      throwsArgumentError,
    );
  });

  test('evidence json is rounded and complete', () {
    final json = estimateLayerSignal(rims()).toJson();
    expect(json['pitch_px'], closeTo(23.4, 0.3));
    expect(json['touches_bottom'], isFalse);
    expect(json['strips'], hasLength(kLayerStrips));
  });
}
