import 'package:egg_tray_counter/models/capture_view.dart';
import 'package:egg_tray_counter/services/frame_evidence.dart';
import 'package:egg_tray_counter/services/frame_preflight.dart';
import 'package:flutter_test/flutter_test.dart';

/// Metrics of a frame that would be accepted, with individual values overridden
/// per test. Keeps each case about exactly one defect.
FrameMetrics goodMetrics({
  double meanLuma = 120,
  double clipLowFraction = 0.02,
  double clipHighFraction = 0.01,
  double sharpness = 60,
  double guideCoverage = 0.6,
  double guideTopEnergyRatio = 0.1,
  double guideBottomEnergyRatio = 0.1,
  double frameBorderEnergyShare = 0.05,
  double bandLumaRatio = 1.1,
  double? verticalEdgeTiltDeg = 0,
  double? horizontalEdgeTiltDeg = 0,
  double? keystoneRatio = 1.0,
}) => FrameMetrics(
  analysisWidth: kAnalysisWidth,
  analysisHeight: 240,
  meanLuma: meanLuma,
  clipLowFraction: clipLowFraction,
  clipHighFraction: clipHighFraction,
  sharpness: sharpness,
  guideCoverage: guideCoverage,
  guideTopEnergyRatio: guideTopEnergyRatio,
  guideBottomEnergyRatio: guideBottomEnergyRatio,
  frameBorderEnergyShare: frameBorderEnergyShare,
  bandLumaRatio: bandLumaRatio,
  verticalEdgeTiltDeg: verticalEdgeTiltDeg,
  horizontalEdgeTiltDeg: horizontalEdgeTiltDeg,
  keystoneRatio: keystoneRatio,
);

const preflight = FramePreflight();

PreflightReport evaluate(
  FrameMetrics? metrics, {
  DevicePose? pose = const DevicePose(rollDeg: 0, pitchDownDeg: 6),
  bool calibrationSet = true,
  CaptureView view = CaptureView.left,
}) => preflight.evaluate(
  view: view,
  metrics: metrics,
  pose: pose,
  calibrationSet: calibrationSet,
);

PreflightSeverity severityOf(PreflightReport report, PreflightCheckId id) =>
    report.checks.firstWhere((check) => check.id == id).severity;

void main() {
  test('an accepted frame passes and can be captured', () {
    final report = evaluate(goodMetrics());

    expect(report.blocked, isFalse);
    expect(report.measurable, isTrue);
    expect(report.active, isEmpty);
    expect(report.toJson()['blocked'], false);
  });

  test('no metrics yet means analysis has not started, not that it passed', () {
    final report = evaluate(null);

    expect(report.metrics, isNull);
    expect(report.blocked, isTrue);
    expect(report.measurable, isFalse);
    expect(report.primary?.headline, 'ANALYSIS STARTING');
  });

  test('low light blocks before anything else is judged', () {
    final report = evaluate(goodMetrics(meanLuma: 18));

    expect(report.blocked, isTrue);
    expect(report.firstBlocker?.id, PreflightCheckId.lighting);
    expect(report.firstBlocker?.headline, 'LIGHTING TOO LOW');
    expect(report.firstBlocker?.action, isNotNull);
  });

  test('washed out light blocks too', () {
    final report = evaluate(goodMetrics(meanLuma: 238));

    expect(report.firstBlocker?.id, PreflightCheckId.lighting);
  });

  test('a blurry frame blocks on sharpness', () {
    final report = evaluate(goodMetrics(sharpness: 9));

    expect(report.blocked, isTrue);
    expect(report.firstBlocker?.id, PreflightCheckId.sharpness);
  });

  test('a frame with nothing framed is reported as no structure', () {
    final report = evaluate(goodMetrics(guideCoverage: 0.02));

    expect(report.blocked, isFalse);
    expect(report.primary?.id, PreflightCheckId.coverage);
  });

  test('bottom texture is advice and cannot prove a cut-off base', () {
    final report = evaluate(goodMetrics(guideBottomEnergyRatio: 0.7));

    expect(report.blocked, isFalse);
    expect(report.primary?.headline, 'CHECK BASE MARGIN');
  });

  test('a tilted phone blocks and says which way to correct', () {
    final report = evaluate(
      goodMetrics(),
      pose: const DevicePose(rollDeg: -9, pitchDownDeg: 6),
    );

    expect(report.blocked, isTrue);
    expect(report.firstBlocker?.headline, 'CAMERA IS TILTED');
  });

  test('an extreme pitch blocks even with a level roll', () {
    final report = evaluate(
      goodMetrics(),
      pose: const DevicePose(rollDeg: 0, pitchDownDeg: 55),
    );

    expect(report.firstBlocker?.headline, 'CAMERA ANGLED TOO FAR DOWN');
  });

  test('a missing level reference is an advisory, not a block', () {
    final report = evaluate(goodMetrics(), calibrationSet: false);

    expect(report.blocked, isFalse);
    expect(
      severityOf(report, PreflightCheckId.calibration),
      PreflightSeverity.advisory,
    );
    expect(report.primary?.headline, 'LEVEL REFERENCE NOT SET');
  });

  test('a level reference removes the calibration advisory', () {
    final report = evaluate(goodMetrics(), calibrationSet: true);

    expect(
      report.checks.any((check) => check.id == PreflightCheckId.calibration),
      isFalse,
    );
  });

  test('sensor and image tilt that disagree are flagged as unreliable', () {
    final report = evaluate(
      goodMetrics(horizontalEdgeTiltDeg: 18),
      pose: const DevicePose(rollDeg: 0.4, pitchDownDeg: 6),
    );

    expect(report.blocked, isFalse);
    expect(
      severityOf(report, PreflightCheckId.calibration),
      PreflightSeverity.advisory,
    );
    expect(report.primary?.headline, 'TILT CHECK INCONSISTENT');
  });

  test('a missing sensor downgrades the level check to advice', () {
    final report = evaluate(goodMetrics(), pose: null);

    expect(report.blocked, isFalse);
    expect(report.primary?.headline, 'TILT SENSOR UNAVAILABLE');
  });

  test('an oblique view is hinted, never hard-blocked', () {
    final report = evaluate(
      goodMetrics(keystoneRatio: 2.0),
      view: CaptureView.left,
    );

    expect(report.blocked, isFalse);
    expect(
      severityOf(report, PreflightCheckId.direction),
      PreflightSeverity.advisory,
    );
  });

  test('withAdvisoryOnly can no longer block but still reports', () {
    final report = evaluate(
      goodMetrics(sharpness: 2),
    ).withAdvisoryOnly({PreflightCheckId.sharpness});

    expect(report.blocked, isFalse);
    expect(report.hasAdvisory, isTrue);
    expect(report.primary?.headline, 'BLUR OR LOW DETAIL');
    expect(report.primary?.detail, contains('region estimated'));
  });

  test('the audit record carries the checks the operator saw', () {
    final json = evaluate(goodMetrics(meanLuma: 18)).toJson();

    expect(json['blocked'], true);
    expect(json['blocking_count'], greaterThan(0));
    expect(json['pose'], isNotNull);
    final checks = json['checks']! as List<Object?>;
    expect(
      checks.any(
        (check) => (check! as Map<String, Object?>)['id'] == 'lighting',
      ),
      isTrue,
    );
  });
}
