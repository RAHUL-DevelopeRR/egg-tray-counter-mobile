import 'dart:math' as math;

/// Measurement-assisted pilot, NOT an image detector or an accuracy guarantee.
/// Inputs are cm from the stack support to the top tray rim, excluding egg tips.
class HeightCalibration {
  HeightCalibration({
    required this.profile,
    required Map<int, double> heights,
    required this.errorCm,
  }) : heights = Map.unmodifiable(heights) {
    if (profile.trim().isEmpty ||
        profile.length > 64 ||
        !errorCm.isFinite ||
        errorCm <= 0 ||
        heights.length != 4 ||
        ![1, 5, 10].every(heights.containsKey) ||
        heights.keys.any((n) => n < 1 || n > 200) ||
        maxCount <= 10 ||
        heights.values.any((h) => !h.isFinite || h <= errorCm || h > 10000)) {
      throw const FormatException(
        'Enter a tray profile, positive cm measurements for 1, 5, 10 and a larger known stack (11–200), and a positive uncertainty.',
      );
    }
    if (!_fits(heights.entries.toList())) {
      throw const FormatException(
        'Reference heights do not fit one positive stacking pitch within the stated uncertainty. Remeasure; do not widen uncertainty just to force a pass.',
      );
    }
  }

  final String profile;
  final Map<int, double> heights;
  final double errorCm;
  int get maxCount => heights.keys.reduce(math.max);

  /// Is there an H1 and positive pitch satisfying ALL height intervals?
  /// Pairwise bounds eliminate H1; never blindly round to the nearest count.
  bool _fits(List<MapEntry<int, double>> points) {
    points.sort((a, b) => a.key.compareTo(b.key));
    var low = 0.0;
    var high = double.infinity;
    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        final dn = points[j].key - points[i].key;
        final dh = points[j].value - points[i].value;
        if (dn == 0) {
          if (dh.abs() > 2 * errorCm + 1e-9) return false;
        } else {
          low = math.max(low, (dh - 2 * errorCm) / dn);
          high = math.min(high, (dh + 2 * errorCm) / dn);
        }
      }
    }
    return high > 0 && low <= high + 1e-9;
  }

  HeightEstimate estimate(double heightCm) {
    if (!heightCm.isFinite || heightCm <= 0 || heightCm > 10000) {
      throw const FormatException(
        'Enter a finite positive stack height in cm.',
      );
    }
    final candidates = <int>[];
    // Include out-of-range neighbours so clipping cannot manufacture uniqueness.
    for (var count = 0; count <= maxCount + 1; count++) {
      if (_fits([...heights.entries, MapEntry(count, heightCm)])) {
        candidates.add(count);
      }
    }
    if (candidates.any((n) => n == 0 || n > maxCount)) {
      return const HeightEstimate(
        [],
        'Outside or too close to the calibration boundary. Manually recount; add a taller reference before estimating taller stacks.',
      );
    }
    if (candidates.isEmpty) {
      return const HeightEstimate(
        [],
        'Height does not fit the calibration. Check the base, top rim, tray type and units; manually recount.',
      );
    }
    return HeightEstimate(
      candidates,
      candidates.length == 1
          ? 'One candidate under your calibration assumptions. Physical recount is still required in this pilot.'
          : 'Several counts fit the uncertainty. Do not round or auto-accept; manually recount.',
    );
  }

  Map<String, Object> toJson() => {
    'profile': profile,
    'heights_cm': {for (final e in heights.entries) '${e.key}': e.value},
    'error_cm': errorCm,
  };

  factory HeightCalibration.fromJson(Map<String, dynamic> json) =>
      HeightCalibration(
        profile: json['profile'] as String,
        heights: {
          for (final e in (json['heights_cm'] as Map<String, dynamic>).entries)
            int.parse(e.key): (e.value as num).toDouble(),
        },
        errorCm: (json['error_cm'] as num).toDouble(),
      );
}

class HeightEstimate {
  const HeightEstimate(this.candidates, this.reason);
  final List<int> candidates;
  final String reason;
  int? get count => candidates.length == 1 ? candidates.single : null;
}
