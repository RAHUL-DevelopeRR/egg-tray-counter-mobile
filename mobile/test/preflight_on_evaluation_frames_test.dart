import 'dart:io';

import 'package:egg_tray_counter/models/capture_view.dart';
import 'package:egg_tray_counter/services/frame_evidence.dart';
import 'package:egg_tray_counter/services/frame_preflight.dart';
import 'package:egg_tray_counter/services/live_frame_preflight.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Harness, not an assertion suite: it runs the live preflight engine over the
/// ten labelled frames in `accuracy-evaluation/test-images` and prints what the
/// app would tell the operator about each one.
///
/// Ground truth and the deployed model's per-view count are copied from
/// `accuracy-evaluation/results.csv` (evaluation date 2026-08-31). The point is
/// to see whether the frames the model gets badly wrong are frames this gate
/// would have refused to upload, or frames it would have accepted.
class _Frame {
  const _Frame(this.name, this.trays, this.modelCount);

  final String name;
  final int trays;
  final int modelCount;
}

const _frames = [
  _Frame('img01', 60, 9),
  _Frame('img02', 60, 12),
  _Frame('img03', 60, 93),
  _Frame('img04', 32, 29),
  _Frame('img05', 120, 124),
  _Frame('img06', 21, 9),
  _Frame('img07', 21, 21),
  _Frame('img08', 46, 73),
  _Frame('img09', 76, 25),
  _Frame('img10', 1, 1),
];

void main() {
  final directory = Directory('../accuracy-evaluation/test-images');

  test('preflight verdicts for the labelled evaluation frames', () async {
    const preflight = FramePreflight();
    var accepted = 0;
    var acceptedFullFrame = 0;
    var acceptedError = 0;
    var refusedError = 0;

    debugPrint(
      'image  trays  model  sharp  luma  cover  top   bot   border  '
      'app-guide verdict / full-frame verdict',
    );
    for (final frame in _frames) {
      final file = File('${directory.path}/${frame.name}.jpg');
      final source = file.existsSync()
          ? file
          : File('${directory.path}/${frame.name}.jpeg');
      final metrics = await measureStill(source.path);
      expect(metrics, isNotNull, reason: '${frame.name} must decode');

      /// No sensor in a plain test run and no stored level reference, so the
      /// level checks fall back to advice, exactly as on a device without an
      /// accelerometer.
      PreflightReport verdict(FrameMetrics metrics) => preflight.evaluate(
        view: CaptureView.straight,
        metrics: metrics,
        pose: null,
        calibrationSet: false,
      );

      final report = verdict(metrics!);
      // The same frame measured against the whole picture instead of the app's
      // guide: this separates "the load does not fit the guide" from "the photo
      // itself is unusable", and it is the number that tells us how far the
      // guide has to move to be satisfiable in this warehouse.
      final fullFrame = await measureStill(
        source.path,
        analyzer: const FrameAnalyzer(guide: NormalizedRect.full),
      );
      final fullReport = verdict(fullFrame!);

      final error = (frame.modelCount - frame.trays).abs();
      if (report.blocked) {
        refusedError += error;
      } else {
        accepted += 1;
        acceptedError += error;
      }
      if (!fullReport.blocked) acceptedFullFrame += 1;

      String fixed(double? value, {int digits = 1}) =>
          value == null ? '  -  ' : value.toStringAsFixed(digits);
      String describe(PreflightReport report) => report.blocked
          ? 'REFUSE: ${report.firstBlocker!.headline}'
          : 'accept';

      debugPrint(
        '${frame.name}   ${frame.trays.toString().padLeft(4)}  '
        '${frame.modelCount.toString().padLeft(5)}  '
        '${fixed(metrics.sharpness, digits: 0).padLeft(5)}  '
        '${fixed(metrics.meanLuma, digits: 0).padLeft(4)}  '
        '${fixed(metrics.guideCoverage, digits: 2).padLeft(5)}  '
        '${fixed(metrics.guideTopEnergyRatio, digits: 2).padLeft(5)}  '
        '${fixed(metrics.guideBottomEnergyRatio, digits: 2).padLeft(5)}  '
        '${fixed(metrics.frameBorderEnergyShare, digits: 2).padLeft(6)}  '
        '${describe(report).padRight(28)} ${describe(fullReport)}',
      );
    }

    final refused = _frames.length - accepted;
    debugPrint(
      'accepted $accepted/${_frames.length} frames under the app guide '
      '(mean |error| ${accepted == 0 ? '-' : (acceptedError / accepted).toStringAsFixed(1)} trays), '
      'refused $refused (mean |error| '
      '${(refusedError / refused).toStringAsFixed(1)} trays); '
      'full-frame guide accepts $acceptedFullFrame/${_frames.length}',
    );

    // Texture at a guide border is not evidence of a cropped tray. Report
    // outcomes without forcing refusal of every known counting failure.
    expect(accepted + refused, _frames.length);
  }, skip: directory.existsSync() ? false : 'evaluation frames are not present');
}
