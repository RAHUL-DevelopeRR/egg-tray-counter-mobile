import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:egg_tray_counter/models/capture_view.dart';
import 'package:egg_tray_counter/services/heading_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';

final _t0 = DateTime.utc(2026, 10, 31, 12);

/// Turns [yaw] at [rate] rad/s about the device axis [axis] for [seconds],
/// in 20 ms gyroscope samples, with gravity along that same axis.
YawIntegrator _turn(List<double> axis, double rate, double seconds) {
  final yaw = YawIntegrator()
    ..addAccelerometer(axis[0] * 9.81, axis[1] * 9.81, axis[2] * 9.81);
  final steps = (seconds / 0.02).round();
  for (var i = 0; i <= steps; i++) {
    yaw.addGyroscope(
      axis[0] * rate,
      axis[1] * rate,
      axis[2] * rate,
      _t0.add(Duration(milliseconds: 20 * i)),
    );
  }
  return yaw;
}

void main() {
  test('a quarter turn reads 90 degrees however the phone is held', () {
    // Upright portrait (gravity along +y), sideways (along +x), flat (+z).
    for (final axis in [
      [0.0, 1.0, 0.0],
      [1.0, 0.0, 0.0],
      [0.0, 0.0, 1.0],
    ]) {
      expect(_turn(axis, math.pi / 2, 1).yawDeg, closeTo(90, 0.5));
      expect(_turn(axis, -math.pi / 4, 2).yawDeg, closeTo(-90, 0.5));
    }
  });

  test('tilting the phone forward is not a turn about the vertical', () {
    final yaw = YawIntegrator()..addAccelerometer(0, 9.81, 0);
    for (var i = 0; i <= 50; i++) {
      yaw.addGyroscope(1.0, 0, 0, _t0.add(Duration(milliseconds: 20 * i)));
    }
    expect(yaw.yawDeg, closeTo(0, 1e-9));
  });

  test('nothing is integrated before up is known, and gaps count as lost', () {
    final yaw = YawIntegrator();
    yaw.addGyroscope(0, 1, 0, _t0);
    yaw.addGyroscope(0, 1, 0, _t0.add(const Duration(seconds: 1)));
    expect(yaw.yawDeg, 0);
    yaw.addAccelerometer(0, 9.81, 0);
    yaw.addAccelerometer(0, 40, 0); // a jolt does not move up
    yaw.addGyroscope(0, 1, 0, _t0.add(const Duration(seconds: 2)));
    expect(yaw.lost, const Duration(milliseconds: 800));
    expect(yaw.yawDeg, closeTo(0.2 * 180 / math.pi, 1e-6));
  });

  test('a side photo must be turned from the front, and LEFT from RIGHT', () {
    const s = CaptureHeading(10, 'a');
    expect(
      sideHeadingProblem(CaptureView.left, const CaptureHeading(30, 'a'), {
        CaptureView.straight: s,
      }),
      contains('turned only 20°'),
    );
    expect(
      sideHeadingProblem(CaptureView.left, const CaptureHeading(100, 'a'), {
        CaptureView.straight: s,
      }),
      isNull,
    );
    // Heading wraps: 350 -> 80 is a 90 degree turn.
    expect(
      sideHeadingProblem(CaptureView.right, const CaptureHeading(80, 'a'), {
        CaptureView.straight: const CaptureHeading(350, 'a'),
      }),
      isNull,
    );
    expect(
      sideHeadingProblem(CaptureView.right, const CaptureHeading(105, 'a'), {
        CaptureView.straight: s,
        CaptureView.left: const CaptureHeading(100, 'a'),
      }),
      contains('same way as the LEFT photo (5° apart)'),
    );
    expect(
      sideHeadingProblem(CaptureView.right, const CaptureHeading(-80, 'a'), {
        CaptureView.straight: s,
        CaptureView.left: const CaptureHeading(100, 'a'),
      }),
      isNull,
    );
  });

  test('headings from another session, missing ones and STRAIGHT are never refused', () {
    expect(
      sideHeadingProblem(CaptureView.left, const CaptureHeading(12, 'b'), {
        CaptureView.straight: const CaptureHeading(10, 'a'),
      }),
      isNull,
    );
    expect(
      sideHeadingProblem(CaptureView.left, null, {
        CaptureView.straight: const CaptureHeading(10, 'a'),
      }),
      isNull,
    );
    expect(
      sideHeadingProblem(CaptureView.straight, const CaptureHeading(0, 'a'), {
        CaptureView.left: const CaptureHeading(1, 'a'),
      }),
      isNull,
    );
  });

  test('a heading round-trips through the view evidence the Worker reads', () {
    final evidence = jsonEncode({
      'source': 'captured_still',
      ...const CaptureHeading(91.26, 'k3x9').toJson(),
    });
    final back = CaptureHeading.fromEvidence(evidence)!;
    expect(back.yawDeg, 91.3);
    expect(back.session, 'k3x9');
    expect(CaptureHeading.fromEvidence(null), isNull);
    expect(CaptureHeading.fromEvidence('{not json'), isNull);
    expect(CaptureHeading.fromEvidence(jsonEncode({'sharpness': 3})), isNull);
  });

  test('the tracker needs a live gyroscope and starts a new session on every start', () async {
    var now = _t0;
    final gyro = StreamController<GyroscopeEvent>.broadcast();
    final accel = StreamController<AccelerometerEvent>.broadcast();
    final tracker = HeadingTracker(
      gyroscope: () => gyro.stream,
      accelerometer: () => accel.stream,
      random: math.Random(1),
      clock: () => now,
    );
    Future<void> gyroFor(int samples, {double rate = math.pi / 2}) async {
      for (var i = 0; i < samples; i++) {
        now = now.add(const Duration(milliseconds: 20));
        gyro.add(GyroscopeEvent(0, rate, 0, now));
      }
      await Future<void>.delayed(Duration.zero);
    }

    tracker.start();
    accel.add(AccelerometerEvent(0, 9.81, 0, _t0));
    await gyroFor(kMinGyroSamples - 1);
    expect(tracker.current, isNull); // too few gyroscope samples yet
    await gyroFor(1);
    final first = tracker.current!;
    expect(first.yawDeg, closeTo(90.0 * 0.02 * (kMinGyroSamples - 1), 0.01));
    expect(first.session, matches(RegExp(r'^[a-z0-9]{10}$')));
    // A gyroscope that stops reporting does not freeze the heading.
    now = now.add(kMaxGyroSilence + const Duration(milliseconds: 1));
    expect(tracker.current, isNull);
    await gyroFor(1, rate: 0);
    expect(tracker.current, isNotNull);
    await tracker.stop();
    expect(tracker.current, isNull);
    tracker.start();
    accel.add(AccelerometerEvent(0, 9.81, 0, now));
    await gyroFor(kMinGyroSamples, rate: 0);
    expect(tracker.current!.session, isNot(first.session));
    expect(tracker.current!.yawDeg, 0);
    await tracker.stop();
  });

  test('a registered gyroscope that never reports, or an erroring one, gives no heading', () async {
    final accel = StreamController<AccelerometerEvent>.broadcast();
    final silent = HeadingTracker(
      gyroscope: () => const Stream<GyroscopeEvent>.empty(),
      accelerometer: () => accel.stream,
    );
    silent.start();
    accel.add(AccelerometerEvent(0, 9.81, 0, _t0));
    await Future<void>.delayed(Duration.zero);
    expect(silent.current, isNull);
    await silent.stop();

    final broken = HeadingTracker(
      gyroscope: () => Stream<GyroscopeEvent>.error(StateError('no gyro')),
      accelerometer: () => accel.stream,
    );
    broken.start();
    accel.add(AccelerometerEvent(0, 9.81, 0, _t0));
    await Future<void>.delayed(Duration.zero);
    expect(broken.current, isNull);
    await broken.stop();
    await accel.close();
  });
}
