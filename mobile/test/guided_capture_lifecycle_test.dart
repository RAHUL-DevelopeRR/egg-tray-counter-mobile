import 'dart:async';
import 'package:camera/camera.dart' show CameraPreview;

// Camera's own platform interface is used only to fake hardware in this test.
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:egg_tray_counter/features/capture/guided_capture_pane.dart';
import 'package:egg_tray_counter/models/scan_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Camera extends CameraPlatform {
  int creates = 0;
  final disposed = <int>[];
  Completer<void>? initialization;
  final errors = StreamController<CameraErrorEvent>.broadcast();
  final frames = StreamController<CameraImageData>.broadcast();

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings settings,
  ) async => ++creates;
  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    await initialization?.future;
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          1280,
          720,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      );
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => errors.stream;
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();
  @override
  bool supportsImageStreaming() => true;
  @override
  Future<void> lockCaptureOrientation(
    int cameraId,
    DeviceOrientation orientation,
  ) async {}
  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) => frames.stream;
  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Colors.black);
  @override
  Future<void> dispose(int cameraId) async => disposed.add(cameraId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sensorChannels = [
    MethodChannel('dev.fluttercommunity.plus/sensors/method'),
    MethodChannel('dev.fluttercommunity.plus/sensors/accelerometer'),
  ];
  const cameras = [
    CameraDescription(
      name: 'back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];
  late _Camera camera;
  late CameraPlatform previous;
  setUp(() {
    for (final channel in sensorChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
    }
    previous = CameraPlatform.instance;
    CameraPlatform.instance = camera = _Camera();
  });
  tearDown(() {
    CameraPlatform.instance = previous;
    for (final channel in sensorChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  Future<void> show(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.view.physicalSize = const Size(480, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GuidedCapturePane(
            cameras: cameras,
            session: ScanSession(scanId: 'test'),
            onComplete: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> drainCamera(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  testWidgets(
    'camera restarts after inactive cleared controller; no frame locks capture',
    (tester) async {
      await show(tester);
      await drainCamera(tester);
      expect(camera.creates, 1);
      expect(find.byType(CameraPreview), findsOneWidget);
      final capture = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'CAPTURE LEFT'),
      );
      expect(capture.onPressed, isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await drainCamera(tester);
      expect(camera.disposed, [1]);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await drainCamera(tester);
      expect(camera.creates, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await drainCamera(tester);
      expect(camera.disposed, [1, 2]);
    },
  );

  testWidgets('initialization completing after unmount releases its camera', (
    tester,
  ) async {
    camera.initialization = Completer<void>();
    await show(tester);
    expect(camera.creates, 1);
    await tester.pumpWidget(const SizedBox());
    camera.initialization!.complete();
    await drainCamera(tester);
    expect(camera.disposed, [1]);
    expect(tester.takeException(), isNull);
  });
}
