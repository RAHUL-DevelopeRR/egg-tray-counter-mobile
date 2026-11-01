import 'dart:math' as math;
import 'dart:typed_data';

import 'frame_evidence.dart';

// Layer periodicity of a tray face, measured from luminance alone.
//
// Tray layers repeat at a fixed spacing (the pitch), so the rows of a face
// carry horizontal edges every pitch. The face band is cut into vertical
// strips; each strip becomes a vertical-gradient row profile, and the
// profile's autocorrelation peaks at the pitch. The repeating run of rims in
// each strip gives where the layers start and end in the frame.
//
// Classical signal processing only: no model, so it is not tied to the
// server detector's mistakes. It was meant to drive the frame-margin, distance
// and pitch-consistency gates (plan C4, C5, C7) and is not wired into the live
// checks.
//
// Measured 2026-11-01 (reports/layer-signal-20261101): against the detector
// pitch it is within 10% on under half of the accepted columns, and half or
// double the pitch on over a quarter of the faces, because stacked trays
// alternate orientation (rims alternate long and short gaps) and each rim
// gives two edges. That trips the plan's kill rule; do not gate on it.
//
// Port of `estimate_pitch` in `backend/app/vision/layer_signal.py`, with a
// parabolic sub-pixel peak.

/// Strips across the face band. A stack at working distance spans one or more
/// strips, so each stack gets its own pitch and run.
const int kLayerStrips = 16;

/// Pitch search range as a fraction of the band height. Below 1% of the frame
/// a layer is too small to count; above 15% fewer than seven layers fit, which
/// no full stack in frame produces.
const double kMinPitchFraction = 0.01;
const double kMaxPitchFraction = 0.15;

/// Lowest pitch searched in pixels, as in the backend settings.
const int kMinPitchPx = 8;

/// Normalised autocorrelation below this is not a repeating pattern.
const double kMinPeriodicStrength = 0.08;

/// Autocorrelation peaks at least this share of the strongest one are
/// "strong"; the shortest strong lag wins, so a pitch beats its multiples.
const double kStrongPeakShare = 0.72;

/// A strip's own pitch is searched within this factor of the face pitch, so a
/// strip cannot lock onto half or twice the face pitch (harmonics), while a
/// real difference of 1.2x (an angled view or a second block) still shows.
const double kStripPitchWindow = 1.5;

/// Rim peaks must stand this far (robust z units) above the surrounding
/// half pitch, as the backend's minimum peak prominence.
const double kMinRimProminence = 0.75;

/// ... and at least this share of the strip's typical strong rim (the median
/// of its six most prominent), as `rim_count.py`'s prominence fraction, so
/// faint texture spaced about a pitch apart does not extend a run.
const double kRimShare = 0.6;

/// Rims spaced by one or two pitches within this share of a pitch belong to
/// one run; two pitches is one faint rim between them.
const double kRunResidual = 0.28;

/// A run needs this many layers; fewer is not a stack (as the Worker's
/// three-box column minimum).
const int kMinRunLayers = 3;

/// A run touches a frame edge when its outer rim is closer to it than this
/// many pitches: the frame has no room for the next rim, so the stack may go
/// on past the edge. A cut stack always meets this (its next rim is outside the
/// frame), and it is the plan's half-pitch margin on the run's end, taken half
/// a pitch beyond the outer rim. A definition for reporting; the gate
/// threshold would come from phase G.
const double kEdgeTouchPitches = 1.0;

/// One strip of the face band.
class LayerStrip {
  const LayerStrip({
    required this.index,
    required this.x0,
    required this.x1,
    required this.pitchPx,
    required this.strength,
    required this.topY,
    required this.baseY,
    required this.runLayers,
    required this.frameHeight,
  });

  final int index;

  /// Pixel columns [x0, x1) of the plane.
  final int x0;
  final int x1;

  /// The strip's own pitch near the face pitch, or null when the strip does
  /// not repeat (background, a gap between stacks).
  final double? pitchPx;

  /// Normalised autocorrelation at [pitchPx] (0..1).
  final double strength;

  /// Plane rows of the first and last rim of the strip's longest periodic
  /// run, or null when it has no run of [kMinRunLayers].
  final double? topY;
  final double? baseY;

  /// Rims in the run plus faint rims bridged inside it. Diagnostic only: it is
  /// not a reading of the stack.
  final int runLayers;

  final int frameHeight;

  bool get hasRun => topY != null && baseY != null;

  /// Distance from the run's outer rims to the frame top / bottom, in the
  /// strip's pitches (a run is only traced with a strip pitch).
  double? get topMarginPitches => hasRun ? topY! / pitchPx! : null;
  double? get bottomMarginPitches =>
      hasRun ? (frameHeight - 1 - baseY!) / pitchPx! : null;

  bool get touchesTop =>
      topMarginPitches != null && topMarginPitches! < kEdgeTouchPitches;
  bool get touchesBottom =>
      bottomMarginPitches != null && bottomMarginPitches! < kEdgeTouchPitches;

  Map<String, Object?> toJson() => {
    'index': index,
    'x0': x0,
    'x1': x1,
    'pitch_px': _round2OrNull(pitchPx),
    'strength': _round2OrNull(strength),
    'top_y': _round2OrNull(topY),
    'base_y': _round2OrNull(baseY),
    'run_layers': runLayers,
    'top_margin_pitches': _round2OrNull(topMarginPitches),
    'bottom_margin_pitches': _round2OrNull(bottomMarginPitches),
    'touches_top': touchesTop,
    'touches_bottom': touchesBottom,
  };
}

/// Periodicity of one face band.
class LayerSignal {
  const LayerSignal({
    required this.frameWidth,
    required this.frameHeight,
    required this.pitchPx,
    required this.strength,
    required this.strips,
    required this.touchesLeft,
    required this.touchesRight,
  });

  final int frameWidth;
  final int frameHeight;

  /// Face pitch from the mean strip autocorrelation, or null when the band
  /// does not repeat.
  final double? pitchPx;

  /// Normalised autocorrelation at [pitchPx] (0..1).
  final double strength;

  final List<LayerStrip> strips;

  /// The first / last strip lies on the frame's side edge and carries a run:
  /// a stack continues past the side of the photo.
  final bool touchesLeft;
  final bool touchesRight;

  /// Pitch as a share of the frame height, the distance measure (plan C5).
  double? get pitchFrac => pitchPx == null ? null : pitchPx! / frameHeight;

  Iterable<LayerStrip> get runStrips => strips.where((s) => s.hasRun);

  /// Highest first rim and lowest last rim over every strip with a run.
  double? get topY => runStrips.isEmpty
      ? null
      : runStrips.map((s) => s.topY!).reduce(math.min);
  double? get baseY => runStrips.isEmpty
      ? null
      : runStrips.map((s) => s.baseY!).reduce(math.max);

  bool get touchesTop => runStrips.any((s) => s.touchesTop);
  bool get touchesBottom => runStrips.any((s) => s.touchesBottom);

  List<int> get stripsTouchingTop =>
      [for (final s in runStrips) if (s.touchesTop) s.index];
  List<int> get stripsTouchingBottom =>
      [for (final s in runStrips) if (s.touchesBottom) s.index];

  /// Largest disagreement between a strip with a run and the face pitch, as a
  /// ratio of at least 1 (1.2 means one strip is 20% off). Null without a face
  /// pitch or a strip pitch.
  double? get pitchConsistency {
    final face = pitchPx;
    if (face == null) return null;
    double? worst;
    for (final strip in runStrips) {
      final pitch = strip.pitchPx;
      if (pitch == null) continue;
      final ratio = math.max(pitch / face, face / pitch);
      worst = worst == null ? ratio : math.max(worst, ratio);
    }
    return worst;
  }

  Map<String, Object?> toJson() => {
    'frame_width': frameWidth,
    'frame_height': frameHeight,
    'pitch_px': _round2OrNull(pitchPx),
    'pitch_frac': pitchFrac == null
        ? null
        : (pitchFrac! * 10000).roundToDouble() / 10000,
    'strength': _round2OrNull(strength),
    'top_y': _round2OrNull(topY),
    'base_y': _round2OrNull(baseY),
    'touches_top': touchesTop,
    'touches_bottom': touchesBottom,
    'touches_left': touchesLeft,
    'touches_right': touchesRight,
    'pitch_consistency': _round2OrNull(pitchConsistency),
    'strips': [for (final s in strips) s.toJson()],
  };
}

/// Measures [plane] inside [band] (default: the whole frame).
///
/// [columnStep] samples every n-th pixel column of a strip; the row profile is
/// a mean over the strip, so 2 halves the work and keeps the rims.
LayerSignal estimateLayerSignal(
  LumaPlane plane, {
  NormalizedRect band = NormalizedRect.full,
  int strips = kLayerStrips,
  int columnStep = 2,
}) {
  if (plane.width < strips ||
      plane.height < 16 ||
      plane.luma.length < plane.width * plane.height ||
      strips <= 0 ||
      columnStep <= 0) {
    throw ArgumentError('Luminance plane too small for $strips strips');
  }
  final bx0 = (band.left * plane.width).round().clamp(0, plane.width - 1);
  final bx1 = (band.right * plane.width).round().clamp(bx0 + 1, plane.width);
  final by0 = (band.top * plane.height).round().clamp(0, plane.height - 1);
  final by1 = (band.bottom * plane.height).round().clamp(
    by0 + 1,
    plane.height,
  );
  final rows = by1 - by0;
  final minPitch = math.max(kMinPitchPx, (kMinPitchFraction * rows).round());
  final maxPitch = math.max(minPitch + 2, (kMaxPitchFraction * rows).round());

  final bounds = <(int, int)>[];
  final profiles = <Float64List>[];
  final correlations = <Float64List?>[];
  for (var i = 0; i < strips; i += 1) {
    final x0 = bx0 + ((bx1 - bx0) * i / strips).round();
    final x1 = math.max(x0 + 1, bx0 + ((bx1 - bx0) * (i + 1) / strips).round());
    bounds.add((x0, x1));
    final profile = rowProfile(plane, x0, x1, by0, by1, columnStep);
    profiles.add(profile);
    correlations.add(autocorrelation(profile, maxPitch + 1));
  }

  // The mean of the strips' autocorrelations is phase-free: stacks standing
  // at different heights in the frame still add up at the shared pitch.
  final usable = correlations.whereType<Float64List>().toList();
  PitchEstimate? face;
  if (usable.isNotEmpty) {
    final mean = Float64List(usable.first.length);
    for (final c in usable) {
      for (var lag = 0; lag < mean.length; lag += 1) {
        mean[lag] += c[lag] / usable.length;
      }
    }
    face = pitchFromAutocorrelation(mean, minPitch, maxPitch);
  }

  final facePitch = face?.pitch;
  final result = <LayerStrip>[];
  for (var i = 0; i < strips; i += 1) {
    final (x0, x1) = bounds[i];
    final correlation = correlations[i];
    PitchEstimate? own;
    if (facePitch != null && correlation != null) {
      own = pitchFromAutocorrelation(
        correlation,
        math.max(minPitch, (facePitch / kStripPitchWindow).floor()),
        math.min(maxPitch, (facePitch * kStripPitchWindow).ceil()),
        strongestOnly: true,
      );
    }
    final run = own == null ? null : periodicRun(profiles[i], own.pitch);
    result.add(
      LayerStrip(
        index: i,
        x0: x0,
        x1: x1,
        pitchPx: own?.pitch,
        strength: own?.strength ?? 0,
        topY: run == null ? null : by0 + run.first,
        baseY: run == null ? null : by0 + run.last,
        runLayers: run?.layers ?? 0,
        frameHeight: plane.height,
      ),
    );
  }
  return LayerSignal(
    frameWidth: plane.width,
    frameHeight: plane.height,
    pitchPx: facePitch,
    strength: face?.strength ?? 0,
    strips: result,
    touchesLeft: bx0 == 0 && result.first.hasRun,
    touchesRight: bx1 == plane.width && result.last.hasRun,
  );
}

/// [estimateLayerSignal] with its run time, to measure the phone's budget
/// before the gates are wired (the 720G cost is unmeasured).
({LayerSignal signal, Duration elapsed}) timedLayerSignal(
  LumaPlane plane, {
  NormalizedRect band = NormalizedRect.full,
  int strips = kLayerStrips,
  int columnStep = 2,
}) {
  final watch = Stopwatch()..start();
  final signal = estimateLayerSignal(
    plane,
    band: band,
    strips: strips,
    columnStep: columnStep,
  );
  watch.stop();
  return (signal: signal, elapsed: watch.elapsed);
}

/// Vertical-gradient row profile of columns [x0, x1) and rows [y0, y1):
/// Gaussian-smoothed Sobel-y magnitude averaged across the strip, then
/// robustly standardised (median 0, MAD-scaled), as the backend's
/// `horizontal_structure_signal`.
Float64List rowProfile(
  LumaPlane plane,
  int x0,
  int x1,
  int y0,
  int y1,
  int columnStep,
) {
  final width = plane.width;
  final luma = plane.luma;
  final rows = y1 - y0;
  final raw = Float64List(rows);
  // [1, 2, 0, -2, -1] is the 3-tap blur convolved with the 3-tap derivative;
  // rows within two of the plane edge reuse the nearest valid row.
  final first = math.max(y0, 2);
  final last = math.min(y1, plane.height - 2);
  var samples = 0;
  for (var x = x0; x < x1; x += columnStep) {
    samples += 1;
  }
  for (var y = first; y < last; y += 1) {
    final a = (y - 2) * width;
    final b = (y - 1) * width;
    final c = (y + 1) * width;
    final d = (y + 2) * width;
    var total = 0;
    for (var x = x0; x < x1; x += columnStep) {
      final g = luma[a + x] + 2 * luma[b + x] - 2 * luma[c + x] - luma[d + x];
      total += g < 0 ? -g : g;
    }
    raw[y - y0] = total / samples;
  }
  if (last > first) {
    for (var y = y0; y < first; y += 1) {
      raw[y - y0] = raw[first - y0];
    }
    for (var y = last; y < y1; y += 1) {
      raw[y - y0] = raw[last - 1 - y0];
    }
  }
  final smooth = gaussianSmooth(raw, 1.2);
  final sorted = Float64List.fromList(smooth)..sort();
  final median = _median(sorted);
  final deviations = Float64List(smooth.length);
  for (var i = 0; i < smooth.length; i += 1) {
    deviations[i] = (smooth[i] - median).abs();
  }
  deviations.sort();
  final scale = math.max(1.4826 * _median(deviations), 1e-6);
  for (var i = 0; i < smooth.length; i += 1) {
    smooth[i] = (smooth[i] - median) / scale;
  }
  return smooth;
}

/// 1-D Gaussian filter with reflected ends (scipy `gaussian_filter1d`,
/// truncated at 4 sigma).
Float64List gaussianSmooth(Float64List signal, double sigma) {
  final radius = (4 * sigma + 0.5).floor();
  final kernel = Float64List(2 * radius + 1);
  var sum = 0.0;
  for (var k = -radius; k <= radius; k += 1) {
    final w = math.exp(-0.5 * k * k / (sigma * sigma));
    kernel[k + radius] = w;
    sum += w;
  }
  final n = signal.length;
  final out = Float64List(n);
  for (var i = 0; i < n; i += 1) {
    var total = 0.0;
    for (var k = -radius; k <= radius; k += 1) {
      var j = i + k;
      // scipy 'reflect': (d c b a | a b c d | d c b a).
      while (j < 0 || j >= n) {
        j = j < 0 ? -j - 1 : 2 * n - j - 1;
      }
      total += kernel[k + radius] * signal[j];
    }
    out[i] = total / sum;
  }
  return out;
}

/// Autocorrelation of the mean-removed [signal] for lags 0..[maxLag],
/// normalised so lag 0 is 1; null for a flat signal.
Float64List? autocorrelation(Float64List signal, int maxLag) {
  final n = signal.length;
  if (n < 2) return null;
  var mean = 0.0;
  for (final v in signal) {
    mean += v;
  }
  mean /= n;
  final centred = Float64List(n);
  for (var i = 0; i < n; i += 1) {
    centred[i] = signal[i] - mean;
  }
  final lags = math.min(maxLag, n - 1);
  final out = Float64List(lags + 1);
  for (var lag = 0; lag <= lags; lag += 1) {
    var total = 0.0;
    for (var i = 0; i + lag < n; i += 1) {
      total += centred[i] * centred[i + lag];
    }
    out[lag] = total;
  }
  if (out[0] <= 1e-9) return null;
  final zero = out[0];
  for (var lag = 0; lag <= lags; lag += 1) {
    out[lag] /= zero;
  }
  return out;
}

class PitchEstimate {
  const PitchEstimate(this.pitch, this.strength);

  final double pitch;
  final double strength;
}

/// `estimate_pitch` on a normalised autocorrelation: among the local maxima
/// with lags [minPitch, maxPitch], the shortest one at least
/// [kStrongPeakShare] of the strongest wins ([strongestOnly]: the strongest).
/// Null when the winner is weaker than [kMinPeriodicStrength].
PitchEstimate? pitchFromAutocorrelation(
  Float64List correlation,
  int minPitch,
  int maxPitch, {
  bool strongestOnly = false,
}) {
  final upper = math.min(maxPitch, correlation.length - 1);
  if (upper <= minPitch) return null;
  // Local maxima strictly inside the section, as scipy find_peaks: a plateau
  // counts once, at its middle.
  final peaks = <int>[];
  var lag = minPitch + 1;
  while (lag < upper) {
    if (correlation[lag] > correlation[lag - 1]) {
      var end = lag;
      while (end + 1 < upper && correlation[end + 1] == correlation[lag]) {
        end += 1;
      }
      if (end + 1 <= upper && correlation[end + 1] < correlation[lag]) {
        peaks.add((lag + end) ~/ 2);
      }
      lag = end + 1;
    } else {
      lag += 1;
    }
  }
  int best;
  if (peaks.isEmpty) {
    best = minPitch;
    for (var l = minPitch; l <= upper; l += 1) {
      if (correlation[l] > correlation[best]) best = l;
    }
  } else {
    var strongest = peaks.first;
    for (final p in peaks) {
      if (correlation[p] > correlation[strongest]) strongest = p;
    }
    best = strongest;
    if (!strongestOnly) {
      final threshold = math.max(
        kMinPeriodicStrength,
        correlation[strongest] * kStrongPeakShare,
      );
      for (final p in peaks) {
        if (correlation[p] >= threshold) {
          best = p;
          break;
        }
      }
    }
  }
  final strength = correlation[best];
  if (strength < kMinPeriodicStrength) return null;
  var pitch = best.toDouble();
  if (best > 0 && best + 1 < correlation.length) {
    final left = correlation[best - 1];
    final right = correlation[best + 1];
    final curvature = left - 2 * strength + right;
    if (curvature < 0) {
      pitch += (0.5 * (left - right) / curvature).clamp(-0.5, 0.5);
    }
  }
  return PitchEstimate(pitch, strength);
}

/// First and last rim of the longest periodic run in a standardised profile.
class PeriodicRun {
  const PeriodicRun(this.first, this.last, this.layers);

  final double first;
  final double last;
  final int layers;
}

/// Rims are profile peaks standing at least [kMinRimProminence] and
/// [kRimShare] of the strip's strong rims above the lowest point within half a
/// pitch on both sides, thinned to one per 0.58 pitch (the backend's peak
/// distance). The run is the chain of rims spaced by one or two
/// pitches (within [kRunResidual]) that covers the most layers; null under
/// [kMinRunLayers].
PeriodicRun? periodicRun(Float64List profile, double pitch) {
  final n = profile.length;
  final half = math.max(1, (pitch / 2).round());
  final candidates = <int>[];
  final prominences = <double>[];
  for (var i = 1; i < n - 1; i += 1) {
    if (profile[i] <= profile[i - 1] || profile[i] < profile[i + 1]) continue;
    var leftLow = profile[i];
    for (var j = math.max(0, i - half); j < i; j += 1) {
      leftLow = math.min(leftLow, profile[j]);
    }
    var rightLow = profile[i];
    for (var j = i + 1; j <= math.min(n - 1, i + half); j += 1) {
      rightLow = math.min(rightLow, profile[j]);
    }
    final prominence = profile[i] - math.max(leftLow, rightLow);
    if (prominence >= kMinRimProminence) {
      candidates.add(i);
      prominences.add(prominence);
    }
  }
  if (candidates.isEmpty) return null;
  final strongest = Float64List.fromList(prominences)
    ..sort((a, b) => b.compareTo(a));
  final floor =
      kRimShare *
      _median(
        Float64List.fromList(
          strongest.sublist(0, math.min(6, strongest.length)).reversed.toList(),
        ),
      );
  final distance = math.max(2, (pitch * 0.58).round());
  final byHeight = [
    for (var k = 0; k < candidates.length; k += 1)
      if (prominences[k] >= floor) candidates[k],
  ]..sort((a, b) => profile[b].compareTo(profile[a]));
  final kept = <int>[];
  for (final c in byHeight) {
    if (kept.every((k) => (k - c).abs() >= distance)) kept.add(c);
  }
  kept.sort();
  if (kept.length < 2) return null;

  // Longest chain ending at each rim: layers covered, then rim height.
  final layers = List<int>.filled(kept.length, 1);
  final score = List<double>.generate(kept.length, (i) => profile[kept[i]]);
  final start = List<int>.generate(kept.length, (i) => i);
  for (var j = 1; j < kept.length; j += 1) {
    for (var i = j - 1; i >= 0; i -= 1) {
      final ratio = (kept[j] - kept[i]) / pitch;
      if (ratio > 2 + kRunResidual) break;
      final steps = ratio.round();
      if (steps < 1 || (ratio - steps).abs() > kRunResidual) continue;
      final total = layers[i] + steps;
      final total2 = score[i] + profile[kept[j]];
      if (total > layers[j] || (total == layers[j] && total2 > score[j])) {
        layers[j] = total;
        score[j] = total2;
        start[j] = start[i];
      }
    }
  }
  var end = 0;
  for (var j = 1; j < kept.length; j += 1) {
    if (layers[j] > layers[end] ||
        (layers[j] == layers[end] && score[j] > score[end])) {
      end = j;
    }
  }
  if (layers[end] < kMinRunLayers) return null;
  return PeriodicRun(
    kept[start[end]].toDouble(),
    kept[end].toDouble(),
    layers[end],
  );
}

double _median(Float64List sorted) {
  final n = sorted.length;
  if (n == 0) return 0;
  return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

double? _round2OrNull(double? value) =>
    value == null ? null : (value * 100).roundToDouble() / 100;
