import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:egg_tray_counter/services/captured_still.dart';
import 'package:egg_tray_counter/services/frame_evidence.dart';
import 'package:egg_tray_counter/services/layer_signal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Parity harness: LayerSignal on the photos behind every face of
/// `benchmarks/registry-20261101/manifest.json`, against the detector's stack
/// columns (`test/fixtures/layer_signal_columns.json`, written by
/// `reports/layer-signal-20261101/make_columns.mjs` from the Worker's own
/// column code).
///
/// Each photo is prepared the way it was sent: MUTAA sets (a `_sent` record)
/// through [prepareCapturedStillSync] to the sent size, the 7 Oct batches as
/// raw pixels. Photos outside the repository (`C:\Users\rahul\MUTAA`) are
/// skipped when missing.
///
/// Set LAYER_SIGNAL_OUT to a file path to write every measurement as JSON, and
/// LAYER_SIGNAL_PROFILES to write each strip's raw row profiles (mean
/// |Sobel-y| and mean signed Sobel-y) for
/// `reports/layer-signal-20261101/explore_variants.py`.
///
/// Pass bar (plan K2, offline part): the strip pitch within 10% of the
/// detector pitch on at least 90% of accepted columns; face pitch at half or
/// twice the detector pitch on at most 10% of faces (the kill rule); the
/// img-30 photo's run touches the frame bottom in both preparations.
///
/// Harness, not an assertion suite, for the bar: it failed when first
/// measured (2026-11-01, reports/layer-signal-20261101/README.md), and the
/// estimator is not wired anywhere. The test asserts that every present photo
/// was measured at the size the detector saw and prints the bar's verdict.
const _fixture = 'test/fixtures/layer_signal_columns.json';

/// Faces whose bottom tray is cut by the frame edge (plan C4).
const _cutAtBottom = {'img-30', 'mutaa:L-80:straight'};

class _Prepared {
  const _Prepared(this.plane, this.width, this.height);

  final LumaPlane plane;
  final int width;
  final int height;
}

LumaPlane _fullLuma(img.Image image) {
  final luma = Uint8List(image.width * image.height);
  var index = 0;
  for (final pixel in image) {
    luma[index] = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b)
        .round()
        .clamp(0, 255);
    index += 1;
  }
  return LumaPlane(width: image.width, height: image.height, luma: luma);
}

String? _resolve(String photo) {
  final file = File(photo.contains(':') ? photo : '../$photo');
  return file.existsSync() ? file.path : null;
}

_Prepared? _prepare(Map<String, dynamic> face, Directory scratch) {
  final path = _resolve(face['photo'] as String);
  if (path == null) return null;
  final prepare = face['prepare'] as Map<String, dynamic>;
  if (prepare['mode'] == 'sent') {
    final still = prepareCapturedStillSync(
      StillRequest(
        sourcePath: path,
        targetPath:
            '${scratch.path}/${(face['id'] as String).replaceAll(':', '_')}.jpg',
        captureRotation: 0,
        sensorOrientation: 0,
      ),
    );
    if (still == null) return null;
    final sent = img.decodeJpg(File(still.path).readAsBytesSync())!;
    return _Prepared(_fullLuma(sent), still.width, still.height);
  }
  final raw = img.decodeJpg(File(path).readAsBytesSync())!;
  return _Prepared(_fullLuma(raw), raw.width, raw.height);
}

double? _median(Iterable<double> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return null;
  final n = sorted.length;
  return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

/// within (10%), half, double or other; none without an estimate.
String _classify(double? estimate, double reference) {
  if (estimate == null) return 'none';
  final ratio = estimate / reference;
  if ((ratio - 1).abs() <= 0.10) return 'within';
  if ((ratio - 0.5).abs() <= 0.10) return 'half';
  if ((ratio - 2).abs() <= 0.20) return 'double';
  return 'other';
}

/// Strips whose centre lies inside the column, else the most overlapping one.
List<LayerStrip> _stripsOf(LayerSignal signal, Map<String, dynamic> column) {
  final xMin = (column['x_min'] as num).toDouble();
  final xMax = (column['x_max'] as num).toDouble();
  final inside = [
    for (final s in signal.strips)
      if ((s.x0 + s.x1) / 2 >= xMin && (s.x0 + s.x1) / 2 <= xMax) s,
  ];
  if (inside.isNotEmpty) return inside;
  LayerStrip? best;
  var overlap = 0.0;
  for (final s in signal.strips) {
    final o = (s.x1 < xMax ? s.x1 : xMax) - (s.x0 > xMin ? s.x0 : xMin);
    if (o > overlap) {
      overlap = o.toDouble();
      best = s;
    }
  }
  return best == null ? const [] : [best];
}

/// Raw strip profiles before smoothing: mean |g| and mean g, where g is the
/// estimator's vertical gradient, for the offline variant comparison.
Map<String, Object?> _rawProfiles(LumaPlane plane, LayerSignal signal) {
  final width = plane.width;
  final luma = plane.luma;
  return {
    'height': plane.height,
    'width': width,
    'strips': [
      for (final strip in signal.strips)
        () {
          final magnitude = <double>[];
          final signed = <double>[];
          for (var y = 0; y < plane.height; y += 1) {
            if (y < 2 || y >= plane.height - 2) {
              magnitude.add(0);
              signed.add(0);
              continue;
            }
            var total = 0;
            var sum = 0;
            var n = 0;
            for (var x = strip.x0; x < strip.x1; x += 2) {
              final g =
                  luma[(y - 2) * width + x] +
                  2 * luma[(y - 1) * width + x] -
                  2 * luma[(y + 1) * width + x] -
                  luma[(y + 2) * width + x];
              total += g.abs();
              sum += g;
              n += 1;
            }
            magnitude.add((total / n * 10).roundToDouble() / 10);
            signed.add((sum / n * 10).roundToDouble() / 10);
          }
          return {'x0': strip.x0, 'x1': strip.x1, 'abs': magnitude, 'sgn': signed};
        }(),
    ],
  };
}

void main() {
  final fixture = File(_fixture);

  test(
    'LayerSignal against the detector columns of the registry faces',
    () {
      final data =
          jsonDecode(fixture.readAsStringSync()) as Map<String, dynamic>;
      final scratch = Directory.systemTemp.createTempSync('layer_signal_');
      addTearDown(() => scratch.deleteSync(recursive: true));

      final records = <Map<String, Object?>>[];
      final profiles = <Map<String, Object?>>[];
      final profilesOut = Platform.environment['LAYER_SIGNAL_PROFILES'];
      final skipped = <String>[];
      final timings = <double>[];
      final columnClass = <String, int>{};
      final acceptedClass = <String, int>{};
      final faceClass = <String, int>{};
      final acceptedFaceClass = <String, int>{};
      var acceptedColumns = 0;
      var endsCompared = 0;
      var topAgrees = 0;
      var baseAgrees = 0;
      final topOffsets = <double>[];
      final baseOffsets = <double>[];
      final touchingCorrect = <String>[];
      var correctFaces = 0;
      final cutTouches = <String, bool>{};

      debugPrint(
        'face                          det-ref  face-px  frac    cons  '
        'top bottom side  columns (detector->strips, class)  ms',
      );
      for (final face in (data['faces'] as List).cast<Map<String, dynamic>>()) {
        final id = face['id'] as String;
        final prepared = _prepare(face, scratch);
        if (prepared == null) {
          skipped.add(id);
          continue;
        }
        final image = face['image'] as Map<String, dynamic>;
        expect(
          [prepared.width, prepared.height],
          [image['width'], image['height']],
          reason: '$id must be measured at the size the detector saw',
        );
        final timed = timedLayerSignal(prepared.plane);
        final signal = timed.signal;
        timings.add(timed.elapsed.inMicroseconds / 1000);

        final columns = (face['columns'] as List).cast<Map<String, dynamic>>();
        final columnRecords = <Map<String, Object?>>[];
        for (final column in columns) {
          final detectorPitch = (column['pitch_px'] as num).toDouble();
          final strips = _stripsOf(signal, column);
          final pitch = _median([
            for (final s in strips)
              if (s.pitchPx != null) s.pitchPx!,
          ]);
          final runs = strips.where((s) => s.hasRun);
          final top = _median(runs.map((s) => s.topY!));
          final base = _median(runs.map((s) => s.baseY!));
          final kind = _classify(pitch, detectorPitch);
          columnClass[kind] = (columnClass[kind] ?? 0) + 1;
          final accepted = column['accepted'] == true;
          if (accepted) {
            acceptedColumns += 1;
            acceptedClass[kind] = (acceptedClass[kind] ?? 0) + 1;
            if (top != null && base != null) {
              endsCompared += 1;
              final topOffset =
                  (top - (column['y_first'] as num)) / detectorPitch;
              final baseOffset =
                  (base - (column['y_last'] as num)) / detectorPitch;
              topOffsets.add(topOffset);
              baseOffsets.add(baseOffset);
              if (topOffset.abs() <= 0.5) topAgrees += 1;
              if (baseOffset.abs() <= 0.5) baseAgrees += 1;
            }
          }
          columnRecords.add({
            'x_min': column['x_min'],
            'x_max': column['x_max'],
            'detector_pitch_px': detectorPitch,
            'y_first': column['y_first'],
            'y_last': column['y_last'],
            'accepted': accepted,
            'strips': [for (final s in strips) s.index],
            'pitch_px': pitch,
            'top_y': top,
            'base_y': base,
            'class': kind,
          });
        }

        String? faceKind;
        if (columns.isNotEmpty) {
          // The Worker's reference pitch: the median of the front group, the
          // columns at or above the face median.
          final pitches = [
            for (final c in columns) (c['pitch_px'] as num).toDouble(),
          ];
          final faceMedian = _median(pitches)!;
          final reference = _median(pitches.where((p) => p >= faceMedian))!;
          faceKind = _classify(signal.pitchPx, reference);
          faceClass[faceKind] = (faceClass[faceKind] ?? 0) + 1;
          if (face['capture_accepted'] == true) {
            acceptedFaceClass[faceKind] =
                (acceptedFaceClass[faceKind] ?? 0) + 1;
          }
          final correct =
              face['usable'] == true &&
              face['capture_accepted'] == true &&
              face['truth'] == face['total'];
          if (correct) correctFaces += 1;
          if (correct && (signal.touchesTop || signal.touchesBottom)) {
            touchingCorrect.add(
              '$id(${signal.touchesTop ? 'top ${signal.stripsTouchingTop}' : ''}'
              '${signal.touchesBottom ? 'bottom ${signal.stripsTouchingBottom}' : ''})',
            );
          }
          debugPrint(
            '${id.padRight(30)}${reference.toStringAsFixed(1).padLeft(7)}  '
            '${(signal.pitchPx?.toStringAsFixed(1) ?? '-').padLeft(7)}  '
            '${(signal.pitchFrac?.toStringAsFixed(3) ?? '-').padLeft(5)}  '
            '${(signal.pitchConsistency?.toStringAsFixed(2) ?? '-').padLeft(5)}  '
            '${signal.touchesTop ? 'T' : '.'}   '
            '${signal.touchesBottom ? 'B' : '.'}      '
            '${signal.touchesLeft ? 'L' : '.'}${signal.touchesRight ? 'R' : '.'}   '
            '${[for (final c in columnRecords) '${(c['detector_pitch_px'] as double).toStringAsFixed(0)}->${(c['pitch_px'] as double?)?.toStringAsFixed(0) ?? '-'}${c['class'] == 'within' ? '' : '!'}'].join(' ')}  '
            '${timings.last.toStringAsFixed(0)}',
          );
        }
        if (_cutAtBottom.contains(id)) cutTouches[id] = signal.touchesBottom;
        if (profilesOut != null && profilesOut.isNotEmpty) {
          profiles.add({
            'id': id,
            'capture_accepted': face['capture_accepted'],
            'columns': columns,
            ..._rawProfiles(prepared.plane, signal),
          });
        }

        records.add({
          'id': id,
          'prepare': face['prepare'],
          'capture_accepted': face['capture_accepted'],
          'correct':
              face['usable'] == true &&
              face['capture_accepted'] == true &&
              face['truth'] == face['total'],
          'face_class': faceKind,
          'elapsed_ms': timings.last,
          'signal': signal.toJson(),
          'columns': columnRecords,
        });
      }

      String share(int part, int whole) => whole == 0
          ? '-'
          : '$part/$whole (${(100 * part / whole).toStringAsFixed(1)}%)';
      final within = acceptedClass['within'] ?? 0;
      final facesMeasured = faceClass.values.fold(0, (a, b) => a + b);
      final harmonicFaces =
          (faceClass['half'] ?? 0) + (faceClass['double'] ?? 0);
      final timingSorted = [...timings]..sort();
      final cutMeasured = _cutAtBottom.where(cutTouches.containsKey);
      final passBar = <String, Object?>{
        'pitch_within_10pct_share': acceptedColumns == 0
            ? null
            : within / acceptedColumns,
        'pitch_bar_met': acceptedColumns > 0 && within / acceptedColumns >= 0.90,
        'harmonic_face_share': facesMeasured == 0
            ? null
            : harmonicFaces / facesMeasured,
        'kill_rule_triggered':
            facesMeasured > 0 && harmonicFaces / facesMeasured > 0.10,
        'cut_faces_touch_bottom': cutMeasured.isEmpty
            ? null
            : cutMeasured.every((id) => cutTouches[id] == true),
      };
      final summary = <String, Object?>{
        'pass_bar': passBar,
        'faces_measured': records.length,
        'faces_skipped': skipped,
        'accepted_columns': acceptedColumns,
        'accepted_columns_by_class': acceptedClass,
        'all_columns_by_class': columnClass,
        'faces_by_class': faceClass,
        'capture_accepted_faces_by_class': acceptedFaceClass,
        'ends_compared': endsCompared,
        'top_within_half_pitch': topAgrees,
        'base_within_half_pitch': baseAgrees,
        'median_top_offset_pitches': _median(topOffsets),
        'median_base_offset_pitches': _median(baseOffsets),
        'correct_faces': correctFaces,
        'correct_faces_touching_top_or_bottom': touchingCorrect,
        'cut_at_bottom_touches': cutTouches,
        'elapsed_ms_median': _median(timings),
        'elapsed_ms_max': timingSorted.isEmpty ? null : timingSorted.last,
      };
      debugPrint(
        'accepted columns within 10%: ${share(within, acceptedColumns)}; '
        'by class $acceptedClass; all columns $columnClass',
      );
      debugPrint(
        'face pitch half/double: ${share(harmonicFaces, facesMeasured)}; '
        'faces $faceClass; capture-accepted faces $acceptedFaceClass',
      );
      debugPrint(
        'run ends within half a pitch of the boxes on accepted columns: '
        'top ${share(topAgrees, endsCompared)}, base ${share(baseAgrees, endsCompared)}; '
        'median offset top ${_median(topOffsets)?.toStringAsFixed(2)} '
        'base ${_median(baseOffsets)?.toStringAsFixed(2)} pitches',
      );
      debugPrint(
        'cut at bottom: $cutTouches; correct faces touching an edge: '
        '${share(touchingCorrect.length, correctFaces)} $touchingCorrect; '
        'skipped ${skipped.length}: $skipped',
      );
      debugPrint('pass bar: $passBar');
      debugPrint(
        'estimator time (test VM, not the phone): median '
        '${_median(timings)?.toStringAsFixed(1)} ms, max '
        '${timingSorted.isEmpty ? '-' : timingSorted.last.toStringAsFixed(1)} ms',
      );

      final out = Platform.environment['LAYER_SIGNAL_OUT'];
      if (out != null && out.isNotEmpty) {
        File(out).writeAsStringSync(
          const JsonEncoder.withIndent(' ').convert({
            'fixture': _fixture,
            'worker': data['worker'],
            'summary': summary,
            'faces': records,
          }),
        );
      }

      if (profilesOut != null && profilesOut.isNotEmpty) {
        File(profilesOut).writeAsStringSync(jsonEncode(profiles));
      }

      // Only photos outside the repository may be missing.
      expect(records.length + skipped.length, (data['faces'] as List).length);
      for (final face in (data['faces'] as List).cast<Map<String, dynamic>>()) {
        if (!(face['photo'] as String).contains(':')) {
          expect(skipped, isNot(contains(face['id'])));
        }
      }
      expect(acceptedColumns, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 15)),
    skip: fixture.existsSync() ? false : 'column fixture is not present',
  );
}
