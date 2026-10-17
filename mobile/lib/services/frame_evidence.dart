import 'dart:math' as math;
import 'dart:typed_data';

/// Every analysed frame (live preview or captured still) is reduced to this
/// width before metrics are computed, so the thresholds below mean the same
/// thing for a 640x480 preview frame and a 4000x3000 still.
const int kAnalysisWidth = 320;

/// Normalised rectangle in 0..1 image coordinates. Kept dependency-free so the
/// analyser can be unit tested without a Flutter binding.
class NormalizedRect {
  const NormalizedRect(this.left, this.top, this.right, this.bottom);

  static const NormalizedRect full = NormalizedRect(0, 0, 1, 1);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
}

/// Maps a guide drawn on the preview onto the captured still.
///
/// Preview and still are different resolutions with different aspect ratios,
/// and the platform presents one as a crop of the other. The crop axis follows
/// from which aspect ratio is narrower: the narrower frame keeps the long
/// dimension and trims the other, so the guide is remapped along that axis
/// only. Positions outside the visible crop keep a small margin via [clamp].
NormalizedRect mapGuideToStill(
  NormalizedRect guide, {
  required double previewAspect,
  required double stillAspect,
}) {
  if (previewAspect <= 0 || stillAspect <= 0) return guide;
  final ratio = previewAspect / stillAspect;
  if ((ratio - 1).abs() < 0.02) return guide;
  if (ratio < 1) {
    // The preview is narrower than the still: same vertical extent, narrower
    // horizontal field of view.
    return NormalizedRect(
      _remapAcrossCrop(guide.left, ratio),
      guide.top,
      _remapAcrossCrop(guide.right, ratio),
      guide.bottom,
    );
  }
  final visible = 1 / ratio;
  return NormalizedRect(
    guide.left,
    _remapAcrossCrop(guide.top, visible),
    guide.right,
    _remapAcrossCrop(guide.bottom, visible),
  );
}

/// Places [value], a 0..1 position inside the visible crop, in full-frame
/// coordinates.
///
/// Visibility fraction above 1 means the still is the cropped one, so the
/// guide is expanded rather than contracted; both cases use the same form.
double _remapAcrossCrop(double value, double visibleFraction) =>
    (0.5 + (value - 0.5) * visibleFraction).clamp(0.0, 1.0);

/// A single-channel luminance plane, row-major, values 0..255.
class LumaPlane {
  const LumaPlane({
    required this.width,
    required this.height,
    required this.luma,
  });

  final int width;
  final int height;
  final Uint8List luma;

  int valueAt(int x, int y) => luma[y * width + x];

  /// Samples a larger plane down to roughly [targetWidth] without allocating
  /// the full-resolution copy. Used for the live YUV stream, where plane 0 is
  /// already luminance and only a subsample is needed.
  factory LumaPlane.sample(
    Uint8List bytes, {
    required int width,
    required int height,
    required int rowStride,
    int pixelStride = 1,
    int rotationDegrees = 0,
    int targetWidth = kAnalysisWidth,
  }) {
    if (width <= 0 ||
        height <= 0 ||
        targetWidth <= 0 ||
        pixelStride <= 0 ||
        rowStride < (width - 1) * pixelStride + 1 ||
        bytes.length <
            (height - 1) * rowStride + (width - 1) * pixelStride + 1 ||
        ![0, 90, 180, 270].contains(rotationDegrees)) {
      throw ArgumentError(
        'Invalid luminance plane dimensions, stride or rotation',
      );
    }
    final sideways = rotationDegrees == 90 || rotationDegrees == 270;
    final orientedWidth = sideways ? height : width;
    final orientedHeight = sideways ? width : height;
    final outWidth = math.min(orientedWidth, targetWidth);
    final scale = orientedWidth / outWidth;
    final outHeight = math.max(1, (orientedHeight / scale).round());
    final out = Uint8List(outWidth * outHeight);
    for (var y = 0; y < outHeight; y += 1) {
      final targetRow = y * outWidth;
      for (var x = 0; x < outWidth; x += 1) {
        final ox = (x * scale).floor().clamp(0, orientedWidth - 1);
        final oy = (y * scale).floor().clamp(0, orientedHeight - 1);
        final (sx, sy) = switch (rotationDegrees) {
          90 => (oy, height - 1 - ox),
          180 => (width - 1 - ox, height - 1 - oy),
          270 => (width - 1 - oy, ox),
          _ => (ox, oy),
        };
        // ponytail: sparse live sampling; tune sharpness against each camera's
        // still path before treating these pilot thresholds as calibrated.
        out[targetRow + x] = bytes[sy * rowStride + sx * pixelStride];
      }
    }
    return LumaPlane(width: outWidth, height: outHeight, luma: out);
  }

  /// Area-averaged reduction to [targetWidth]. Averaging (rather than sampling)
  /// keeps blur and noise behaviour comparable between the live and still paths.
  LumaPlane reduceToWidth(int targetWidth) {
    if (targetWidth >= width) return this;
    final factor = width / targetWidth;
    final outWidth = targetWidth;
    final outHeight = math.max(1, (height / factor).round());
    final out = Uint8List(outWidth * outHeight);
    for (var y = 0; y < outHeight; y += 1) {
      final y0 = ((y * factor).floor()).clamp(0, height - 1);
      final y1 = (((y + 1) * factor).ceil()).clamp(y0 + 1, height);
      for (var x = 0; x < outWidth; x += 1) {
        final x0 = ((x * factor).floor()).clamp(0, width - 1);
        final x1 = (((x + 1) * factor).ceil()).clamp(x0 + 1, width);
        var total = 0;
        var count = 0;
        for (var sy = y0; sy < y1; sy += 1) {
          final row = sy * width;
          for (var sx = x0; sx < x1; sx += 1) {
            total += luma[row + sx];
            count += 1;
          }
        }
        out[y * outWidth + x] = count == 0 ? 0 : (total / count).round();
      }
    }
    return LumaPlane(width: outWidth, height: outHeight, luma: out);
  }
}

/// Deterministic measurements taken from one frame.
///
/// These are *measurements*, not conclusions: `FramePreflight` turns them into
/// pass/fail checks. Nothing here proves that hidden trays or egg contents are
/// visible; the checks can only reject evidence that is demonstrably unusable.
class FrameMetrics {
  const FrameMetrics({
    required this.analysisWidth,
    required this.analysisHeight,
    required this.meanLuma,
    required this.clipLowFraction,
    required this.clipHighFraction,
    required this.sharpness,
    required this.guideCoverage,
    required this.guideTopEnergyRatio,
    required this.guideBottomEnergyRatio,
    required this.frameBorderEnergyShare,
    required this.bandLumaRatio,
    required this.verticalEdgeTiltDeg,
    required this.horizontalEdgeTiltDeg,
    required this.keystoneRatio,
    this.topMeanLuma,
    this.bottomMeanLuma,
  });

  final int analysisWidth;
  final int analysisHeight;

  /// Mean luminance in 0..255.
  final double meanLuma;

  /// Fraction of pixels crushed to near black (<= 16).
  final double clipLowFraction;

  /// Fraction of pixels blown out to near white (>= 245).
  final double clipHighFraction;

  /// Variance of the Laplacian at [kAnalysisWidth]. Higher is sharper.
  final double sharpness;

  /// Fraction of guide sub-cells that carry resolvable structure (0..1).
  /// Near zero means nothing usable is framed: empty floor, a wall, or the
  /// stacks are too far away to resolve tray rims.
  final double guideCoverage;

  /// Energy just inside the top / bottom edge of the guide divided by the
  /// energy of the guide interior. A high value means the stack continues past
  /// the guide edge, so the top of the stack (or the base) is cut off.
  final double guideTopEnergyRatio;
  final double guideBottomEnergyRatio;

  /// Share of the strongest image gradients that sit in the outer 3% ring of
  /// the whole frame. High values mean stack content is clipped by the frame
  /// itself, not merely by the guide.
  final double frameBorderEnergyShare;

  /// Brighter half divided by darker half of the guide, top-vs-bottom. Large
  /// values indicate backlighting, glare or shadow across the load.
  final double bandLumaRatio;
  final double? topMeanLuma;
  final double? bottomMeanLuma;

  /// Deviation of the dominant near-vertical edge family from vertical, and of
  /// the dominant near-horizontal family from horizontal, in degrees.
  /// Null when the frame has too little structure to measure a direction.
  final double? verticalEdgeTiltDeg;
  final double? horizontalEdgeTiltDeg;

  /// Height of the strong vertical-edge span on the guide's left half divided
  /// by the right half. About 1.0 is fronto-parallel; a strong deviation is an
  /// advisory hint about the oblique angle. Not an accepted yaw measurement.
  final double? keystoneRatio;

  /// Image-space roll estimate: how far the horizon is rotated. Used as an
  /// independent cross-check of the device tilt sensor.
  double? get horizonTiltDeg => horizontalEdgeTiltDeg;

  /// Audit record. Rounded to two decimals: the numbers are evidence for a
  /// retake decision, not a measurement claim.
  Map<String, Object?> toJson() => {
    'analysis_width': analysisWidth,
    'analysis_height': analysisHeight,
    'mean_luma': _round2(meanLuma),
    'clip_low_fraction': _round2(clipLowFraction),
    'clip_high_fraction': _round2(clipHighFraction),
    'sharpness': _round2(sharpness),
    'guide_coverage': _round2(guideCoverage),
    'top_edge_energy_ratio': _round2(guideTopEnergyRatio),
    'bottom_edge_energy_ratio': _round2(guideBottomEnergyRatio),
    'frame_border_energy_share': _round2(frameBorderEnergyShare),
    'band_luma_ratio': _round2(bandLumaRatio),
    'top_mean_luma': _round2OrNull(topMeanLuma),
    'bottom_mean_luma': _round2OrNull(bottomMeanLuma),
    'vertical_edge_tilt_deg': _round2OrNull(verticalEdgeTiltDeg),
    'horizontal_edge_tilt_deg': _round2OrNull(horizontalEdgeTiltDeg),
    'keystone_ratio': _round2OrNull(keystoneRatio),
  };
}

double _round2(double value) => (value * 100).roundToDouble() / 100;

double? _round2OrNull(double? value) => value == null ? null : _round2(value);

/// Measures [plane] inside [guide]. [guide] is expressed in normalised image
/// coordinates so callers can pass the on-screen framing rectangle directly.
class FrameAnalyzer {
  const FrameAnalyzer({
    this.guide = const NormalizedRect(0.10, 0.10, 0.90, 0.88),
    this.structureThreshold = 14,
    this.cellThreshold = 7,
  });

  final NormalizedRect guide;

  /// Gradient magnitude above which a pixel counts as real structure.
  final double structureThreshold;

  /// Mean-cell gradient above which a guide cell counts as carrying content.
  final double cellThreshold;

  FrameMetrics analyze(LumaPlane raw) {
    if (raw.width < 3 ||
        raw.height < 3 ||
        raw.luma.length < raw.width * raw.height) {
      throw ArgumentError('Luminance plane must contain at least 3 x 3 pixels');
    }
    final plane = raw.reduceToWidth(kAnalysisWidth);
    final width = plane.width;
    final height = plane.height;
    final luma = plane.luma;
    final pixelCount = width * height;

    var total = 0.0;
    var clippedLow = 0;
    var clippedHigh = 0;
    for (var i = 0; i < pixelCount; i += 1) {
      final value = luma[i];
      total += value;
      if (value <= 16) clippedLow += 1;
      if (value >= 245) clippedHigh += 1;
    }
    final meanLuma = total / pixelCount;

    final x0 = (guide.left * width).round().clamp(0, width - 1);
    final x1 = (guide.right * width).round().clamp(x0 + 1, width);
    final y0 = (guide.top * height).round().clamp(0, height - 1);
    final y1 = (guide.bottom * height).round().clamp(y0 + 1, height);

    var laplacianTotal = 0.0;
    var laplacianSquared = 0.0;
    var laplacianCount = 0;
    var guideEnergy = 0.0;
    var guideEnergyCount = 0;
    var topBandEnergy = 0.0;
    var topBandCount = 0;
    var bottomBandEnergy = 0.0;
    var bottomBandCount = 0;
    var borderEnergy = 0.0;
    var internEnergy = 0.0;
    var topSum = 0.0;
    var topCount = 0;
    var bottomSum = 0.0;
    var bottomCount = 0;

    // Orientation histogram weighted by gradient magnitude, 36 bins of 5 deg.
    final orientation = List<double>.filled(36, 0);

    final borderThickness = math.max(1, (height * 0.03).round());
    final bandHeight = math.max(1, ((y1 - y0) * 0.08).round());
    final guideMiddleY = (y0 + y1) ~/ 2;

    for (var y = 1; y < height - 1; y += 1) {
      final row = y * width;
      for (var x = 1; x < width - 1; x += 1) {
        final index = row + x;
        final center = luma[index].toDouble();
        final left = luma[index - 1].toDouble();
        final right = luma[index + 1].toDouble();
        final up = luma[index - width].toDouble();
        final down = luma[index + width].toDouble();
        final laplacian = left + right + up + down - 4 * center;
        laplacianTotal += laplacian;
        laplacianSquared += laplacian * laplacian;
        laplacianCount += 1;

        final gx = right - left;
        final gy = down - up;
        final magnitude = math.sqrt(gx * gx + gy * gy);

        final inGuide = x >= x0 && x < x1 && y >= y0 && y < y1;
        if (inGuide) {
          guideEnergy += magnitude;
          guideEnergyCount += 1;
          if (y < y0 + bandHeight) {
            topBandEnergy += magnitude;
            topBandCount += 1;
          }
          if (y >= y1 - bandHeight) {
            bottomBandEnergy += magnitude;
            bottomBandCount += 1;
          }
          if (y < guideMiddleY) {
            topSum += center;
            topCount += 1;
          } else {
            bottomSum += center;
            bottomCount += 1;
          }
        }

        final nearFrameBorder =
            x < borderThickness ||
            y < borderThickness ||
            x >= width - borderThickness ||
            y >= height - borderThickness;
        if (nearFrameBorder) {
          borderEnergy += magnitude;
        } else {
          internEnergy += magnitude;
        }

        if (magnitude >= structureThreshold) {
          var degrees = math.atan2(gy, gx) * 180 / math.pi;
          if (degrees < 0) degrees += 180;
          final bin = (degrees / 5).floor().clamp(0, 35);
          orientation[bin] += magnitude;
        }
      }
    }

    final laplacianMean = laplacianTotal / laplacianCount;
    final sharpness =
        laplacianSquared / laplacianCount - laplacianMean * laplacianMean;

    final guideCellCount = _countContentCells(plane, x0, x1, y0, y1);
    final cellSize = _cellSize(x1 - x0, y1 - y0);
    final guideCells =
        ((x1 - x0) / cellSize).ceil() * ((y1 - y0) / cellSize).ceil();

    final guideMeanEnergy = guideEnergyCount == 0
        ? 0.0
        : guideEnergy / guideEnergyCount;
    final topMeanEnergy = topBandCount == 0
        ? 0.0
        : topBandEnergy / topBandCount;
    final bottomMeanEnergy = bottomBandCount == 0
        ? 0.0
        : bottomBandEnergy / bottomBandCount;

    final topMean = topCount == 0 ? 0.0 : topSum / topCount;
    final bottomMean = bottomCount == 0 ? 0.0 : bottomSum / bottomCount;
    final brighter = math.max(topMean, bottomMean);
    final darker = math.min(topMean, bottomMean);

    final totalEnergy = borderEnergy + internEnergy;
    // Gradient direction is perpendicular to the edge, not along it.
    final verticalTilt = _horizontalTilt(orientation);
    final horizontalTilt = _familyTilt(orientation, 55, 125);

    return FrameMetrics(
      analysisWidth: width,
      analysisHeight: height,
      meanLuma: meanLuma,
      clipLowFraction: clippedLow / pixelCount,
      clipHighFraction: clippedHigh / pixelCount,
      sharpness: sharpness,
      guideCoverage: guideCellCount / guideCells,
      guideTopEnergyRatio: guideMeanEnergy <= 0
          ? 0
          : topMeanEnergy / guideMeanEnergy,
      guideBottomEnergyRatio: guideMeanEnergy <= 0
          ? 0
          : bottomMeanEnergy / guideMeanEnergy,
      frameBorderEnergyShare: totalEnergy <= 0 ? 0 : borderEnergy / totalEnergy,
      bandLumaRatio: (brighter / math.max(1, darker)).clamp(1, 99),
      topMeanLuma: topMean,
      bottomMeanLuma: bottomMean,
      verticalEdgeTiltDeg: verticalTilt,
      horizontalEdgeTiltDeg: horizontalTilt,
      keystoneRatio: _keystoneRatio(plane, x0, x1, y0, y1),
    );
  }

  /// Guide sub-cell size in pixels: between 4 and 8 cells across the shorter
  /// guide dimension, never smaller than 4 px.
  int _cellSize(int width, int height) {
    final shorter = math.max(1, math.min(width, height));
    final cells = math.max(4, math.min(8, (shorter / 40).ceil()));
    return math.max(4, (shorter / cells).floor());
  }

  int _countContentCells(LumaPlane plane, int x0, int x1, int y0, int y1) {
    final cell = _cellSize(x1 - x0, y1 - y0);
    var populated = 0;
    for (var cy = y0; cy < y1; cy += cell) {
      for (var cx = x0; cx < x1; cx += cell) {
        final endY = math.min(cy + cell, y1);
        final endX = math.min(cx + cell, x1);
        var energy = 0.0;
        var count = 0;
        for (var y = math.max(cy, 1); y < endY; y += 1) {
          // The neighbour taps below read one row past the current one, so the
          // last row of the plane cannot be measured. A guide that reaches the
          // image edge is legal, so this is a guard, not an assumption.
          if (y >= plane.height - 1) break;
          for (var x = math.max(cx, 1); x < endX; x += 1) {
            if (x >= plane.width - 1) continue;
            final index = y * plane.width + x;
            final gx =
                plane.luma[index + 1].toDouble() -
                plane.luma[index - 1].toDouble();
            final gy =
                plane.luma[index + plane.width].toDouble() -
                plane.luma[index - plane.width].toDouble();
            energy += math.sqrt(gx * gx + gy * gy);
            count += 1;
          }
        }
        if (count > 0 && energy / count >= cellThreshold) populated += 1;
      }
    }
    return populated;
  }

  /// Dominant magnitude-weighted orientation inside an angular family.
  double? _familyTilt(List<double> orientation, double minDeg, double maxDeg) {
    var best = -1.0;
    var bestBin = -1;
    for (var bin = 0; bin < orientation.length; bin += 1) {
      final degrees = bin * 5 + 2.5;
      if (degrees < minDeg || degrees > maxDeg) continue;
      if (orientation[bin] > best) {
        best = orientation[bin];
        bestBin = bin;
      }
    }
    final total = orientation.fold<double>(0, (sum, value) => sum + value);
    if (bestBin < 0 || total <= 0 || best / total < 0.08) return null;
    // Deviation from vertical: a vertical edge is oriented at 90 degrees.
    return bestBin * 5 + 2.5 - 90;
  }

  double? _horizontalTilt(List<double> orientation) {
    var best = -1.0;
    var bestDegrees = 0.0;
    for (var bin = 0; bin < orientation.length; bin += 1) {
      final degrees = bin * 5 + 2.5;
      final nearHorizontal = degrees <= 35 || degrees >= 145;
      if (!nearHorizontal) continue;
      if (orientation[bin] > best) {
        best = orientation[bin];
        bestDegrees = degrees >= 145 ? degrees - 180 : degrees;
      }
    }
    final total = orientation.fold<double>(0, (sum, value) => sum + value);
    if (best <= 0 || total <= 0 || best / total < 0.08) return null;
    return bestDegrees;
  }

  /// Vertical span of strong vertical edges on the left versus right half of
  /// the guide. Advisory only: repeated tray texture can create false edges.
  double? _keystoneRatio(LumaPlane plane, int x0, int x1, int y0, int y1) {
    final midX = (x0 + x1) ~/ 2;
    final left = _verticalSpan(plane, x0, midX, y0, y1);
    final right = _verticalSpan(plane, midX, x1, y0, y1);
    if (left == null || right == null || right <= 0) return null;
    return left / right;
  }

  double? _verticalSpan(LumaPlane plane, int x0, int x1, int y0, int y1) {
    var minRow = -1;
    var maxRow = -1;
    final step = math.max(1, (x1 - x0) ~/ 24);
    for (var y = math.max(y0 + 1, 1); y < y1 - 1; y += 2) {
      var strong = false;
      for (var x = math.max(x0 + 1, 1); x < x1 - 1; x += step) {
        final index = y * plane.width + x;
        final gx =
            (plane.luma[index + 1].toDouble() -
                    plane.luma[index - 1].toDouble())
                .abs();
        final gy =
            (plane.luma[index + plane.width].toDouble() -
                    plane.luma[index - plane.width].toDouble())
                .abs();
        // A near-vertical edge: strong horizontal change, weak vertical change.
        if (gx >= structureThreshold * 1.5 && gy <= gx * 0.6) {
          strong = true;
          break;
        }
      }
      if (strong) {
        if (minRow < 0) minRow = y;
        maxRow = y;
      }
    }
    if (minRow < 0 || maxRow <= minRow) return null;
    return (maxRow - minRow).toDouble();
  }
}
