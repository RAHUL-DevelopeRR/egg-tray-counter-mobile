import 'dart:convert';

import 'package:egg_tray_counter/models/height_calibration.dart';
import 'package:flutter_test/flutter_test.dart';

// Synthetic arithmetic cases only. These are NOT warehouse accuracy evidence.
void main() {
  HeightCalibration calibration({double error = 0.1}) => HeightCalibration(
    profile: 'SYNTHETIC TEST ONLY',
    heights: {1: 6, 5: 26, 10: 51, 20: 101},
    errorCm: error,
  );

  test('all in-range synthetic counts obey first-tray offset and pitch', () {
    final c = calibration();
    for (var n = 1; n <= 20; n++) {
      expect(c.estimate(6 + (n - 1) * 5).count, n);
    }
    expect(c.estimate(76.05).count, 15);
  });

  test('does not round gaps, extrapolate or accept ambiguous heights', () {
    expect(calibration().estimate(78.5).count, isNull);
    expect(calibration().estimate(106).count, isNull);
    expect(calibration().estimate(1).count, isNull);
    expect(
      calibration(error: 3).estimate(51).candidates.length,
      greaterThan(1),
    );
    expect(calibration(error: 3).estimate(51).count, isNull);
    expect(calibration(error: 3).estimate(101).count, isNull);
  });

  test('rejects inconsistent references and nonfinite or missing inputs', () {
    expect(
      () => HeightCalibration(
        profile: 'test',
        heights: {1: 6, 5: 12, 10: 51, 20: 101},
        errorCm: 0.1,
      ),
      throwsFormatException,
    );
    expect(
      () => HeightCalibration(profile: 'test', heights: {}, errorCm: 1),
      throwsFormatException,
    );
    expect(() => calibration(error: 0), throwsFormatException);
    expect(() => calibration(error: double.nan), throwsFormatException);
    for (final h in [0.0, -1.0, double.nan, double.infinity]) {
      expect(() => calibration().estimate(h), throwsFormatException);
    }
  });

  test('calibration snapshot is immutable and survives JSON storage', () {
    final c = calibration();
    expect(() => c.heights[20] = 999, throwsUnsupportedError);
    final copy = HeightCalibration.fromJson(
      jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>,
    );
    expect(copy.estimate(76).count, 15);
    expect(copy.toJson(), c.toJson());
  });
}
