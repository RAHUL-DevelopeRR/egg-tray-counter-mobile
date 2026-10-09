import 'dart:math' as math;

List<double> vector(dynamic value, int size) {
  if (value is! List ||
      value.length != size ||
      value.any((v) => v is! num || !v.isFinite)) {
    throw const FormatException('Invalid 3D coordinates');
  }
  return value.map((v) => (v as num).toDouble()).toList();
}

class ReconstructionHypothesis {
  ReconstructionHypothesis(Map<String, dynamic> json)
    : label = json['label'] as String,
      points = (json['render']['points'] as List)
          .map((p) => vector(p, 6))
          .toList(),
      centres = (json['render']['cameras'] as List)
          .map((c) => vector(c['centre'], 3))
          .toList(),
      orientations = (json['render']['cameras'] as List)
          .map(
            (c) => (c['orientation'] as List).map((r) => vector(r, 3)).toList(),
          )
          .toList(),
      minimum = vector(json['render']['bounds']['min'], 3),
      maximum = vector(json['render']['bounds']['max'], 3),
      error = (json['render']['median_error_px'] as num).toDouble(),
      inliers = json['render']['inlier_count'] as int {
    if (points.isEmpty ||
        points.length > 2000 ||
        centres.length != 2 ||
        orientations.any((m) => m.length != 3) ||
        !error.isFinite ||
        error < 0 ||
        inliers < 0) {
      throw const FormatException('Invalid 3D evidence');
    }
  }
  final String label;
  final List<List<double>> points, centres;
  final List<List<List<double>>> orientations;
  final List<double> minimum, maximum;
  final double error;
  final int inliers;
}

class ReconstructionResult {
  ReconstructionResult.fromJson(Map<String, dynamic> json)
    : status = json['status'] as String,
      reason = json['reason'] as String,
      hypotheses = (json['focal_hypotheses'] as List)
          .map(
            (h) =>
                ReconstructionHypothesis(Map<String, dynamic>.from(h as Map)),
          )
          .toList() {
    if (![
          'reconstructed',
          'insufficient_matches',
          'pose_failed',
        ].contains(status) ||
        json['physical_trays'] != null ||
        json['verified'] != false ||
        json['scale'] != 'arbitrary_unit_baseline' ||
        (status == 'reconstructed' && hypotheses.isEmpty)) {
      throw const FormatException('Incompatible diagnostic result');
    }
  }
  final String status, reason;
  final List<ReconstructionHypothesis> hypotheses;
}

// Camera looks along +Z after orbiting normalized scene coordinates.
List<double> orbitPoint(List<double> p, double yaw, double pitch) {
  final x = math.cos(yaw) * p[0] + math.sin(yaw) * p[2];
  final z = -math.sin(yaw) * p[0] + math.cos(yaw) * p[2];
  return [
    x,
    math.cos(pitch) * p[1] - math.sin(pitch) * z,
    math.sin(pitch) * p[1] + math.cos(pitch) * z,
  ];
}

List<double>? projectPoint(List<double> p, double zoom) {
  final depth = p[2] + 4;
  if (depth <= .05) return null;
  return [p[0] * zoom / depth, p[1] * zoom / depth, depth];
}
