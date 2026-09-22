import 'dart:math' as math;

import '../models/capture_view.dart';
import 'frame_evidence.dart';

/// Device attitude from the accelerometer, already corrected by the stored
/// level reference.
///
/// Sign conventions assume a portrait phone and the Android accelerometer axes
/// (+x to the right, +y up the screen, +z out of the screen towards the
/// operator), which is what `sensors_plus` reports:
///   roll      = atan2(ax, ay)  -> 0 when the phone is level
///   pitchDown = atan2(az, ay)  -> 0 when the camera looks at the horizon,
///                                 +90 when the camera points straight down
/// The roll direction is independently cross-checked against the image-space
/// horizon tilt, so a wrong sign convention shows up as an inconsistent-check
/// warning rather than as silently wrong advice.
class DevicePose {
  const DevicePose({required this.rollDeg, required this.pitchDownDeg});

  final double rollDeg;
  final double pitchDownDeg;
}

/// Operator-chosen level reference. Tray racks are not always level, and an
/// operator's natural shooting stance has a small constant roll, so the
/// absolute sensor angle is not the right baseline. "Set level reference"
/// stores the current attitude; every later frame is measured against it.
class PoseCalibration {
  const PoseCalibration({
    this.rollOffsetDeg = 0,
    this.pitchOffsetDeg = 0,
    this.referenceSet = false,
  });

  static const PoseCalibration none = PoseCalibration();

  final double rollOffsetDeg;
  final double pitchOffsetDeg;

  /// True once the operator has taken a level reference, even if the offsets
  /// came out at zero on a perfectly level surface. Without this flag a
  /// genuinely level setup would keep reporting "reference not set".
  final bool referenceSet;

  bool get isSet => referenceSet || rollOffsetDeg != 0 || pitchOffsetDeg != 0;

  DevicePose apply(DevicePose raw) => DevicePose(
    rollDeg: raw.rollDeg - rollOffsetDeg,
    pitchDownDeg: raw.pitchDownDeg - pitchOffsetDeg,
  );
}

enum PreflightSeverity { pass, advisory, blocking }

enum PreflightCheckId {
  calibration,
  lighting,
  sharpness,
  tilt,
  framing,
  coverage,
  direction,
}

/// One evaluated check with the exact reason and the repair action.
class PreflightCheck {
  const PreflightCheck({
    required this.id,
    required this.severity,
    required this.headline,
    required this.detail,
    this.action,
  });

  final PreflightCheckId id;
  final PreflightSeverity severity;

  /// Short status shown in the banner, e.g. `LIGHTING TOO LOW`.
  final String headline;

  /// Measured value against the accepted range; never a guess.
  final String detail;

  /// What the operator must change. Null when the check passes.
  final String? action;

  bool get blocking => severity == PreflightSeverity.blocking;
  bool get advisory => severity == PreflightSeverity.advisory;
  bool get passes => severity == PreflightSeverity.pass;
}

/// The result of evaluating one frame.
class PreflightReport {
  const PreflightReport({
    required this.checks,
    this.metrics,
    this.pose,
    this.measuredAt,
  });

  final List<PreflightCheck> checks;
  final FrameMetrics? metrics;
  final DevicePose? pose;
  final DateTime? measuredAt;

  bool get blocked => checks.any((check) => check.blocking);
  bool get hasAdvisory => checks.any((check) => check.advisory);
  bool get measurable => metrics != null && !blocked;

  PreflightCheck? get firstBlocker {
    for (final check in checks) {
      if (check.blocking) return check;
    }
    return null;
  }

  /// Everything the operator must read, worst first.
  List<PreflightCheck> get active => [
    for (final check in checks)
      if (!check.passes) check,
  ];

  static const PreflightReport waiting = PreflightReport(checks: []);

  /// Copy where the listed checks can no longer block.
  ///
  /// The still-capture path measures the guide region through a different crop
  /// than the preview showed, so those region-derived checks are approximations
  /// there. An approximation must never hard-block a capture, but it still has
  /// to be reported.
  PreflightReport withAdvisoryOnly(Set<PreflightCheckId> ids) =>
      PreflightReport(
        checks: [
          for (final check in checks)
            if (ids.contains(check.id) && check.blocking)
              PreflightCheck(
                id: check.id,
                severity: PreflightSeverity.advisory,
                headline: check.headline,
                detail: '${check.detail} (region estimated for this still)',
                action: check.action,
              )
            else
              check,
        ],
        metrics: metrics,
        pose: pose,
        measuredAt: measuredAt,
      );

  int get blockingCount => checks.where((check) => check.blocking).length;

  int get advisoryCount => checks.where((check) => check.advisory).length;

  /// The one line the operator must act on right now.
  PreflightCheck? get primary {
    if (firstBlocker != null) return firstBlocker;
    for (final check in checks) {
      if (check.advisory) return check;
    }
    for (final check in checks) {
      if (check.passes) return check;
    }
    return null;
  }

  /// Audit record attached to every capture. The backend can use it to reject
  /// counts whose evidence was already known to be unusable, and a reviewer can
  /// see exactly which measurements the operator was shown.
  Map<String, Object?> toJson() {
    final pose = this.pose;
    return {
      'measured_at': measuredAt?.toUtc().toIso8601String(),
      'blocked': blocked,
      'blocking_count': blockingCount,
      'advisory_count': advisoryCount,
      'pose': pose == null
          ? null
          : {
              'roll_deg': (pose.rollDeg * 10).roundToDouble() / 10,
              'pitch_down_deg': (pose.pitchDownDeg * 10).roundToDouble() / 10,
            },
      'metrics': metrics?.toJson(),
      'checks': [
        for (final check in checks)
          {
            'id': check.id.name,
            'severity': check.severity.name,
            'headline': check.headline,
            'detail': check.detail,
          },
      ],
    };
  }
}

/// Pilot thresholds. These are heuristics chosen for the current warehouse
/// lighting and phone, not validated accuracy gates; every one of them must be
/// re-calibrated against labelled warehouse examples before release.
class PreflightPolicy {
  const PreflightPolicy();

  static const double minMeanLuma = 45;
  static const double maxMeanLuma = 215;
  static const double maxClipLowFraction = 0.40;
  static const double maxClipHighFraction = 0.20;
  static const double maxBandLumaRatio = 2.6;

  static const double minSharpness = 18;
  static const double advisorySharpness = 30;

  static const double maxRollDeg = 4;
  static const double minPitchDownDeg = -5;
  static const double maxPitchDownDeg = 28;
  static const double comfortableMinPitchDownDeg = 0;
  static const double comfortableMaxPitchDownDeg = 22;

  static const double minCoverage = 0.18;
  static const double comfortableCoverage = 0.32;
  static const double maxCoverage = 0.97;

  static const double maxEdgeEnergyRatio = 0.45;
  static const double advisoryEdgeEnergyRatio = 0.30;
  static const double maxBorderEnergyShare = 0.34;

  static const double maxKeystoneRatio = 1.45;
  static const double maxRollDisagreementDeg = 6;
}

class FramePreflight {
  const FramePreflight({this.policy = const PreflightPolicy()});

  final PreflightPolicy policy;

  PreflightReport evaluate({
    required CaptureView view,
    FrameMetrics? metrics,
    DevicePose? pose,
    required bool calibrationSet,
    DateTime? measuredAt,
  }) {
    final checks = <PreflightCheck>[];
    if (metrics == null) {
      return PreflightReport(
        checks: const [
          PreflightCheck(
            id: PreflightCheckId.calibration,
            severity: PreflightSeverity.blocking,
            headline: 'ANALYSIS STARTING',
            detail:
                'The live frame analysis has not produced a measurement yet.',
            action: 'Hold the phone steady on the stacks for a moment.',
          ),
        ],
        pose: pose,
        measuredAt: measuredAt,
      );
    }

    checks
      ..addAll(_lightingChecks(metrics))
      ..addAll(_sharpnessChecks(metrics))
      ..addAll(_framingChecks(metrics))
      ..addAll(_directionChecks(metrics, view))
      ..addAll(_tiltChecks(metrics, pose, calibrationSet));

    return PreflightReport(
      checks: checks,
      metrics: metrics,
      pose: pose,
      measuredAt: measuredAt,
    );
  }

  List<PreflightCheck> _lightingChecks(FrameMetrics metrics) {
    final checks = <PreflightCheck>[];
    final mean = metrics.meanLuma;

    if (mean < PreflightPolicy.minMeanLuma) {
      checks.add(
        PreflightCheck(
          id: PreflightCheckId.lighting,
          severity: PreflightSeverity.blocking,
          headline: 'LIGHTING TOO LOW',
          detail:
              'Average brightness ${mean.toStringAsFixed(0)}/255 '
              '(needs ${PreflightPolicy.minMeanLuma.toStringAsFixed(0)} or more). '
              'The frame is below the pilot brightness threshold.',
          action:
              'Move to a brighter position or add diffused light. Do not aim '
              'the phone at the light itself.',
        ),
      );
    } else if (mean > PreflightPolicy.maxMeanLuma) {
      checks.add(
        PreflightCheck(
          id: PreflightCheckId.lighting,
          severity: PreflightSeverity.blocking,
          headline: 'LIGHTING TOO BRIGHT',
          detail:
              'Average brightness ${mean.toStringAsFixed(0)}/255 '
              '(limit ${PreflightPolicy.maxMeanLuma.toStringAsFixed(0)}).',
          action:
              'Reduce exposure: step out of direct sunlight or shade the load.',
        ),
      );
    }

    if (metrics.clipHighFraction > PreflightPolicy.maxClipHighFraction) {
      checks.add(
        PreflightCheck(
          id: PreflightCheckId.lighting,
          severity: PreflightSeverity.blocking,
          headline: 'GLARE / BLOWN HIGHLIGHTS',
          detail:
              '${(metrics.clipHighFraction * 100).toStringAsFixed(1)}% of the '
              'frame is pure white '
              '(limit ${(PreflightPolicy.maxClipHighFraction * 100).toStringAsFixed(0)}%). '
              'Tray detail in those areas is lost.',
          action:
              'Change position so the light source is not reflected at the camera.',
        ),
      );
    }

    if (metrics.clipLowFraction > PreflightPolicy.maxClipLowFraction) {
      checks.add(
        PreflightCheck(
          id: PreflightCheckId.lighting,
          severity: PreflightSeverity.blocking,
          headline: 'SHADOWS CRUSHED',
          detail:
              '${(metrics.clipLowFraction * 100).toStringAsFixed(1)}% of the frame '
              'is near black '
              '(limit ${(PreflightPolicy.maxClipLowFraction * 100).toStringAsFixed(0)}%).',
          action: 'Add light to the shaded side of the stacks.',
        ),
      );
    }

    if (checks.isEmpty &&
        metrics.bandLumaRatio > PreflightPolicy.maxBandLumaRatio) {
      checks.add(
        PreflightCheck(
          id: PreflightCheckId.lighting,
          severity: PreflightSeverity.blocking,
          headline: 'UNEVEN LIGHTING',
          detail:
              'The brighter half of the guide is '
              '${metrics.bandLumaRatio.toStringAsFixed(1)}x more lit than the '
              'darker half '
              '(limit ${PreflightPolicy.maxBandLumaRatio.toStringAsFixed(1)}x). '
              '${metrics.topMeanLuma != null && metrics.bottomMeanLuma != null ? (metrics.bottomMeanLuma! < metrics.topMeanLuma! ? 'The bottom' : 'The top') : 'One'} half of the guide has limited lighting.',
          action:
              'Use light from both sides, or move so the load is not backlit.',
        ),
      );
    }

    if (checks.isEmpty) {
      checks.add(
        PreflightCheck(
          id: PreflightCheckId.lighting,
          severity: PreflightSeverity.pass,
          headline: 'LIGHTING OK',
          detail:
              'Brightness ${mean.toStringAsFixed(0)}/255, '
              'balance ${metrics.bandLumaRatio.toStringAsFixed(1)}x.',
        ),
      );
    }
    return checks;
  }

  List<PreflightCheck> _sharpnessChecks(FrameMetrics metrics) {
    if (metrics.sharpness < PreflightPolicy.minSharpness) {
      return [
        PreflightCheck(
          id: PreflightCheckId.sharpness,
          severity: PreflightSeverity.blocking,
          headline: 'BLUR OR LOW DETAIL',
          detail:
              'Sharpness ${metrics.sharpness.toStringAsFixed(1)} '
              '(needs ${PreflightPolicy.minSharpness.toStringAsFixed(0)}). '
              'Motion blur, missed focus or a smeared lens all reduce this.',
          action: 'Hold the phone still, let focus settle, wipe the lens.',
        ),
      ];
    }
    if (metrics.sharpness < PreflightPolicy.advisorySharpness) {
      return [
        PreflightCheck(
          id: PreflightCheckId.sharpness,
          severity: PreflightSeverity.advisory,
          headline: 'SHARPNESS MARGINAL',
          detail:
              'Sharpness ${metrics.sharpness.toStringAsFixed(1)}; tray rim '
              'layers may be hard to separate.',
          action: 'Brace the phone or step closer.',
        ),
      ];
    }
    return [
      PreflightCheck(
        id: PreflightCheckId.sharpness,
        severity: PreflightSeverity.pass,
        headline: 'SHARPNESS OK',
        detail: 'Sharpness ${metrics.sharpness.toStringAsFixed(1)}.',
      ),
    ];
  }

  List<PreflightCheck> _framingChecks(FrameMetrics metrics) {
    final checks = <PreflightCheck>[];

    if (metrics.guideCoverage < PreflightPolicy.minCoverage) {
      checks.add(
        PreflightCheck(
          id: PreflightCheckId.coverage,
          severity: PreflightSeverity.advisory,
          headline: 'LIMITED IMAGE DETAIL',
          detail:
              'Only ${(metrics.guideCoverage * 100).toStringAsFixed(0)}% of the '
              'guide carries contrast/texture '
              '(needs ${(PreflightPolicy.minCoverage * 100).toStringAsFixed(0)}% or more). '
              'This check cannot identify trays or confirm their visibility.',
          action:
              'Move closer until tray rims and eggs fill most of the guide.',
        ),
      );
    } else if (metrics.guideCoverage < PreflightPolicy.comfortableCoverage) {
      checks.add(
        PreflightCheck(
          id: PreflightCheckId.coverage,
          severity: PreflightSeverity.advisory,
          headline: 'CHECK STACK SIZE IN FRAME',
          detail:
              'Guide coverage '
              '${(metrics.guideCoverage * 100).toStringAsFixed(0)}%. Layer '
              'separation improves when the stacks fill more of the guide.',
          action: 'Step closer without cropping the top or the base.',
        ),
      );
    }

    if (metrics.guideTopEnergyRatio > PreflightPolicy.maxEdgeEnergyRatio) {
      checks.add(
        PreflightCheck(
          id: PreflightCheckId.framing,
          severity: PreflightSeverity.advisory,
          headline: 'CHECK TOP MARGIN',
          detail:
              'Image texture is present at the top edge of the guide '
              '(edge strength ${metrics.guideTopEnergyRatio.toStringAsFixed(2)}, '
              'limit ${PreflightPolicy.maxEdgeEnergyRatio.toStringAsFixed(2)}). '
              'This may be background texture; check the highest tray is visible.',
          action:
              'Step back or aim slightly up until the top tray is inside the guide.',
        ),
      );
    } else if (metrics.guideTopEnergyRatio >
        PreflightPolicy.advisoryEdgeEnergyRatio) {
      checks.add(
        PreflightCheck(
          id: PreflightCheckId.framing,
          severity: PreflightSeverity.advisory,
          headline: 'CHECK TOP MARGIN',
          detail:
              'Edge strength at the guide top is '
              '${metrics.guideTopEnergyRatio.toStringAsFixed(2)}.',
          action: 'Leave a small margin above the highest tray.',
        ),
      );
    }

    if (metrics.guideBottomEnergyRatio > PreflightPolicy.maxEdgeEnergyRatio) {
      checks.add(
        PreflightCheck(
          id: PreflightCheckId.framing,
          severity: PreflightSeverity.advisory,
          headline: 'CHECK BASE MARGIN',
          detail:
              'Image texture is present at the bottom edge of the guide '
              '(edge strength '
              '${metrics.guideBottomEnergyRatio.toStringAsFixed(2)}, '
              'limit ${PreflightPolicy.maxEdgeEnergyRatio.toStringAsFixed(2)}). '
              'This may be background texture; check the lowest tray is visible.',
          action:
              'Step back or lower the phone until the base tray is inside the guide.',
        ),
      );
    } else if (metrics.guideBottomEnergyRatio >
        PreflightPolicy.advisoryEdgeEnergyRatio) {
      checks.add(
        PreflightCheck(
          id: PreflightCheckId.framing,
          severity: PreflightSeverity.advisory,
          headline: 'CHECK BASE MARGIN',
          detail:
              'Edge strength at the guide bottom is '
              '${metrics.guideBottomEnergyRatio.toStringAsFixed(2)}.',
          action: 'Leave a small margin below the base tray.',
        ),
      );
    }

    if (metrics.frameBorderEnergyShare > PreflightPolicy.maxBorderEnergyShare) {
      checks.add(
        PreflightCheck(
          id: PreflightCheckId.framing,
          severity: PreflightSeverity.advisory,
          headline: 'CHECK FRAME EDGES',
          detail:
              '${(metrics.frameBorderEnergyShare * 100).toStringAsFixed(0)}% of the '
              'image detail sits in the outer 3% of the frame '
              '(limit ${(PreflightPolicy.maxBorderEnergyShare * 100).toStringAsFixed(0)}%). '
              'Texture alone cannot establish whether stacks are cropped.',
          action:
              'Move back until there is clear floor or wall around every stack.',
        ),
      );
    }

    if (checks.isEmpty) {
      checks.add(
        PreflightCheck(
          id: PreflightCheckId.coverage,
          severity: PreflightSeverity.pass,
          headline: 'FRAME TEXTURE CHECK PASSED',
          detail:
              'Guide coverage '
              '${(metrics.guideCoverage * 100).toStringAsFixed(0)}%. Confirm all stacks, tops and bases are visible.',
        ),
      );
    }
    return checks;
  }

  List<PreflightCheck> _directionChecks(
    FrameMetrics metrics,
    CaptureView view,
  ) {
    final keystone = metrics.keystoneRatio;
    if (keystone == null) return const [];
    final ratio = math.max(keystone, 1 / keystone);
    if (ratio <= PreflightPolicy.maxKeystoneRatio) return const [];
    final steeperSide = keystone > 1 ? 'left' : 'right';
    return [
      PreflightCheck(
        id: PreflightCheckId.direction,
        severity: PreflightSeverity.advisory,
        headline: 'VIEW DIRECTION LOOKS ${steeperSide.toUpperCase()}-HEAVY',
        detail:
            'The $steeperSide half of the guide shows '
            '${ratio.toStringAsFixed(2)}x the vertical tray edge span of the '
            'other half. Single-view yaw cannot be measured exactly indoors, so '
            'this is a hint, not a calibrated angle.',
        action: view == CaptureView.straight
            ? 'For STRAIGHT, face the row squarely so both sides look the same.'
            : 'For ${view.name.toUpperCase()}, step around the stacks until the '
                  'guide outline matches the on-screen shape.',
      ),
    ];
  }

  List<PreflightCheck> _tiltChecks(
    FrameMetrics metrics,
    DevicePose? pose,
    bool calibrationSet,
  ) {
    final checks = <PreflightCheck>[];
    final horizon = metrics.horizonTiltDeg;

    if (pose == null) {
      checks.add(
        const PreflightCheck(
          id: PreflightCheckId.tilt,
          severity: PreflightSeverity.advisory,
          headline: 'TILT SENSOR UNAVAILABLE',
          detail:
              'No accelerometer reading, so camera level is judged from the '
              'image only. Level checks are not enforced.',
          action: 'Keep the tray rims parallel to the on-screen guide lines.',
        ),
      );
    } else {
      final roll = pose.rollDeg.abs();
      if (roll > PreflightPolicy.maxRollDeg) {
        checks.add(
          PreflightCheck(
            id: PreflightCheckId.tilt,
            severity: PreflightSeverity.blocking,
            headline: 'CAMERA IS TILTED',
            detail:
                'Roll ${roll.toStringAsFixed(1)}deg from level '
                '(limit ${PreflightPolicy.maxRollDeg.toStringAsFixed(0)}deg). '
                'A tilted frame destroys the rim geometry used for counting.',
            action: 'Level the phone and keep the tray rims horizontal.',
          ),
        );
      } else if (roll > PreflightPolicy.maxRollDeg * 0.6) {
        checks.add(
          PreflightCheck(
            id: PreflightCheckId.tilt,
            severity: PreflightSeverity.advisory,
            headline: 'TILT NEAR THE LIMIT',
            detail:
                'Roll ${roll.toStringAsFixed(1)}deg of '
                '${PreflightPolicy.maxRollDeg.toStringAsFixed(0)}deg allowed.',
            action: 'Straighten the phone slightly.',
          ),
        );
      }

      final pitch = pose.pitchDownDeg;
      if (pitch < PreflightPolicy.minPitchDownDeg ||
          pitch > PreflightPolicy.maxPitchDownDeg) {
        checks.add(
          PreflightCheck(
            id: PreflightCheckId.tilt,
            severity: PreflightSeverity.blocking,
            headline: pitch > 0
                ? 'CAMERA ANGLED TOO FAR DOWN'
                : 'CAMERA ANGLED TOO FAR UP',
            detail:
                'Camera pitch ${pitch.toStringAsFixed(1)}deg below horizontal '
                '(accepted '
                '${PreflightPolicy.minPitchDownDeg.toStringAsFixed(0)} to '
                '${PreflightPolicy.maxPitchDownDeg.toStringAsFixed(0)}deg). '
                'Hidden layers are created by extreme viewing angles.',
            action: pitch > 0
                ? 'Raise the phone towards the middle of the stack height.'
                : 'Lower the phone towards the middle of the stack height.',
          ),
        );
      } else if (pitch < PreflightPolicy.comfortableMinPitchDownDeg ||
          pitch > PreflightPolicy.comfortableMaxPitchDownDeg) {
        checks.add(
          PreflightCheck(
            id: PreflightCheckId.tilt,
            severity: PreflightSeverity.advisory,
            headline: 'PITCH NEAR THE LIMIT',
            detail:
                'Camera pitch ${pitch.toStringAsFixed(1)}deg below horizontal; '
                'the comfortable band is '
                '${PreflightPolicy.comfortableMinPitchDownDeg.toStringAsFixed(0)} to '
                '${PreflightPolicy.comfortableMaxPitchDownDeg.toStringAsFixed(0)}deg.',
            action:
                'Adjust the phone height so rims and base are both visible.',
          ),
        );
      }

      if (!calibrationSet) {
        checks.add(
          const PreflightCheck(
            id: PreflightCheckId.calibration,
            severity: PreflightSeverity.advisory,
            headline: 'LEVEL REFERENCE NOT SET',
            detail:
                'Level checks currently use absolute gravity, which assumes the '
                'racks and the operator stance are level.',
            action:
                'Hold the phone in the normal shooting pose and tap SET LEVEL.',
          ),
        );
      } else if (horizon != null &&
          (horizon.abs() - roll).abs() >
              PreflightPolicy.maxRollDisagreementDeg) {
        checks.add(
          PreflightCheck(
            id: PreflightCheckId.calibration,
            severity: PreflightSeverity.advisory,
            headline: 'TILT CHECK INCONSISTENT',
            detail:
                'Sensor roll ${roll.toStringAsFixed(1)}deg but the image horizon '
                'is tilted ${horizon.toStringAsFixed(1)}deg. One of the two is '
                'unreliable for this frame.',
            action: 'Re-set the level reference on a level surface and retry.',
          ),
        );
      }
    }

    if (checks.isEmpty) {
      checks.add(
        PreflightCheck(
          id: PreflightCheckId.tilt,
          severity: PreflightSeverity.pass,
          headline: 'CAMERA LEVEL',
          detail: pose == null
              ? 'Image horizon is level.'
              : 'Roll ${pose.rollDeg.abs().toStringAsFixed(1)}deg, '
                    'pitch ${pose.pitchDownDeg.toStringAsFixed(1)}deg.',
        ),
      );
    }
    return checks;
  }
}
