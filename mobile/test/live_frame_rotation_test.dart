import 'package:egg_tray_counter/services/frame_preflight.dart';
import 'package:egg_tray_counter/services/live_frame_preflight.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const method = MethodChannel('dev.fluttercommunity.plus/sensors/method');
  const accelerometer = EventChannel(
    'dev.fluttercommunity.plus/sensors/accelerometer',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MockStreamHandlerEventSink gravity;
  late LiveFramePreflight live;

  setUp(() {
    messenger.setMockMethodCallHandler(method, (_) async => null);
    messenger.setMockStreamHandler(
      accelerometer,
      MockStreamHandler.inline(
        onListen: (_, sink) {
          gravity = sink;
        },
      ),
    );
    live = LiveFramePreflight()..startSensors();
  });
  tearDown(() async {
    await live.stopSensors();
    live.dispose();
    messenger.setMockMethodCallHandler(method, null);
    messenger.setMockStreamHandler(accelerometer, null);
  });

  Future<void> hold(double x, double y, [double z = 0]) async {
    gravity.success([x, y, z, 0.0]);
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'a phone held level sideways reads as level, either way round',
    () async {
      // Turned counter-clockwise (top of the phone to the left).
      await hold(9.81, 0);
      expect(live.rawRollDeg, closeTo(90, 0.5));
      live.setCaptureRotation(90);
      expect(live.pose!.rollDeg, closeTo(0, 0.5));
      // Turned clockwise.
      await hold(-9.81, 0);
      live.setCaptureRotation(270);
      expect(live.pose!.rollDeg, closeTo(0, 0.5));
      // A 6 degree lean while sideways is still reported as 6 degrees.
      await hold(-9.81 * 0.9945, 9.81 * 0.1045);
      expect(live.pose!.rollDeg.abs(), closeTo(6, 0.5));
      // Assumed the wrong way round, the same phone is far from level.
      await hold(9.81, 0);
      expect(live.pose!.rollDeg.abs(), closeTo(180, 0.5));
    },
  );

  test('pitch is the same sideways as upright', () async {
    // Camera aimed 8 degrees down, upright and sideways.
    await hold(0, 9.81 * 0.990, 9.81 * 0.139);
    live.setCaptureRotation(0);
    final upright = live.pose!.pitchDownDeg;
    await hold(9.81 * 0.990, 0, 9.81 * 0.139);
    live.setCaptureRotation(90);
    expect(live.pose!.pitchDownDeg, closeTo(upright, 0.2));
    expect(upright, closeTo(8, 0.3));
  });

  test('an upright level reference only lends its pitch offset sideways', () {
    live.setCalibration(
      const PoseCalibration(
        rollOffsetDeg: 4,
        pitchOffsetDeg: 2,
        referenceSet: true,
      ),
    );
    gravity.success([9.81, 0.0, 0.0, 0.0]);
    return Future<void>.delayed(Duration.zero).then((_) {
      live.setCaptureRotation(90);
      expect(live.pose!.rollDeg, closeTo(0, 0.5));
      expect(live.pose!.pitchDownDeg, closeTo(-2, 0.5));
    });
  });

  test('a flat phone gives no roll, so the orientation is kept', () async {
    await hold(0.3, 0.2, 9.8);
    expect(live.rawRollDeg, isNull);
    expect(live.rawPose, isNotNull);
  });

  test('changing the rotation discards the last frame measurement', () {
    live.setCaptureRotation(90);
    expect(live.captureRotation, 90);
    expect(live.frameFresh, isFalse);
    expect(() => live.setCaptureRotation(180), throwsArgumentError);
  });
}
