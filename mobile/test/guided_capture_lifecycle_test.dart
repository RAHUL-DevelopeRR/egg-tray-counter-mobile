import 'dart:async';
import 'package:camera/camera.dart' show CameraPreview;

// Camera's own platform interface is used only to fake hardware in this test.
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:egg_tray_counter/features/capture/camera_guide_overlay.dart';
import 'package:egg_tray_counter/features/capture/guided_capture_pane.dart';
import 'package:egg_tray_counter/models/scan_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Camera extends CameraPlatform {
  int creates = 0;
  final flashModes = <FlashMode>[];
  bool rejectTorch = false;
  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {
    if (rejectTorch) throw PlatformException(code: 'torch_unavailable');
    flashModes.add(mode);
  }

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
  final orientations =
      StreamController<DeviceOrientationChangedEvent>.broadcast();
  final locks = <DeviceOrientation>[];
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      orientations.stream;
  @override
  bool supportsImageStreaming() => true;
  @override
  Future<void> lockCaptureOrientation(
    int cameraId,
    DeviceOrientation orientation,
  ) async => locks.add(orientation);
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

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(480, 1000),
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.view.physicalSize = size;
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

  testWidgets('preview turns with the device orientation and is never locked', (
    tester,
  ) async {
    // A sideways phone must show an upright picture: the camera package
    // rotates CameraPreview by the device orientation unless a capture lock
    // overrides it (0.4.5 locked portraitUp, which drew landscape sideways).
    await show(tester, size: const Size(1000, 480));
    await drainCamera(tester);
    expect(camera.locks, isEmpty);
    int turns() => tester
        .widget<RotatedBox>(
          find.descendant(
            of: find.byType(CameraPreview),
            matching: find.byType(RotatedBox),
          ),
        )
        .quarterTurns;
    expect(turns(), 0);
    camera.orientations.add(
      const DeviceOrientationChangedEvent(DeviceOrientation.landscapeLeft),
    );
    await drainCamera(tester);
    expect(turns(), 3);
    camera.orientations.add(
      const DeviceOrientationChangedEvent(DeviceOrientation.landscapeRight),
    );
    await drainCamera(tester);
    expect(turns(), 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await drainCamera(tester);
  });

  testWidgets('viewfinder shows the whole camera frame, full width', (
    tester,
  ) async {
    // What is on screen is exactly what is photographed: the 720x1280 frame
    // is scaled to the 480 px width (853 px tall) of a 480x1000 screen, with
    // the controls over it.
    await show(tester);
    await drainCamera(tester);
    final guide = tester.getRect(find.byType(CameraGuideOverlay));
    expect(guide.width, closeTo(480, 0.5));
    expect(guide.height, closeTo(480 * 1280 / 720, 0.5));
    expect(guide.center.dy, closeTo(500, 0.5));
    expect(
      tester
          .getCenter(find.widgetWithText(FilledButton, 'CAPTURE STRAIGHT'))
          .dy,
      greaterThan(900),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await drainCamera(tester);
  });

  testWidgets(
    'held sideways the screen stays portrait; text and guide turn to the hand',
    (tester) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      final orientationRequests = <Object?>[];
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientationRequests.add(call.arguments);
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      const accelerometer = EventChannel(
        'dev.fluttercommunity.plus/sensors/accelerometer',
      );
      MockStreamHandlerEventSink? gravity;
      messenger.setMockStreamHandler(
        accelerometer,
        MockStreamHandler.inline(
          onListen: (_, sink) {
            gravity = sink;
          },
        ),
      );
      addTearDown(() => messenger.setMockStreamHandler(accelerometer, null));

      await show(tester);
      await drainCamera(tester);
      expect(gravity, isNotNull);
      final button = find.widgetWithText(FilledButton, 'CAPTURE STRAIGHT');
      int overlayTurns() {
        final boxes = find.ancestor(
          of: button,
          matching: find.byType(RotatedBox),
        );
        return boxes.evaluate().isEmpty
            ? 0
            : tester.widget<RotatedBox>(boxes.first).quarterTurns;
      }

      int guideTurns() => tester
          .widget<RotatedBox>(
            find
                .ancestor(
                  of: find.byType(CameraGuideOverlay),
                  matching: find.byType(RotatedBox),
                )
                .first,
          )
          .quarterTurns;

      Future<void> hold(double x, double y) async {
        gravity!.success([x, y, 0.0, 0.0]);
        await tester.pump(const Duration(milliseconds: 600));
      }

      expect((overlayTurns(), guideTurns()), (0, 0));

      // Top of the phone to the operator's left (turned counter-clockwise):
      // the operator's bottom-right is the screen's bottom-left.
      await hold(9.81, 0);
      expect((overlayTurns(), guideTurns()), (1, 1));
      var centre = tester.getCenter(button);
      expect(centre.dx, lessThan(240));
      expect(centre.dy, greaterThan(500));
      expect(find.text('TURN TORCH ON'), findsOneWidget);
      expect(find.text('CAMERA IS TILTED'), findsNothing);
      expect(tester.takeException(), isNull);

      // Turned clockwise: the operator's bottom-right is the screen's top-right.
      await hold(-9.81, 0);
      expect((overlayTurns(), guideTurns()), (3, 3));
      centre = tester.getCenter(button);
      expect(centre.dx, greaterThan(240));
      expect(centre.dy, lessThan(500));
      expect(tester.takeException(), isNull);

      // Back upright.
      await hold(0, 9.81);
      expect((overlayTurns(), guideTurns()), (0, 0));

      // The screen was never asked to rotate, and the camera never locked.
      expect(
        orientationRequests,
        everyElement(equals(['DeviceOrientation.portraitUp'])),
      );
      expect(camera.locks, isEmpty);
      expect(find.byType(CameraPreview), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await drainCamera(tester);
    },
  );

  testWidgets(
    'camera restarts after inactive cleared controller; no frame locks capture',
    (tester) async {
      await show(tester);
      await drainCamera(tester);
      expect(camera.creates, 1);
      expect(find.byType(CameraPreview), findsOneWidget);
      final capture = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'CAPTURE STRAIGHT'),
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

  testWidgets(
    'torch toggles and unavailable hardware reports recovery advice',
    (tester) async {
      await show(tester);
      await drainCamera(tester);
      for (final label in ['TURN TORCH ON', 'TURN TORCH OFF']) {
        await tester.tap(find.text(label));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await drainCamera(tester);
      }
      expect(camera.flashModes, [FlashMode.torch, FlashMode.off]);
      camera.rejectTorch = true;
      await tester.tap(find.text('TURN TORCH ON'));
      await drainCamera(tester);
      expect(
        find.text('Torch is unavailable. Add even lighting around the stacks.'),
        findsOneWidget,
      );
      expect(find.text('TURN TORCH ON'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await drainCamera(tester);
    },
  );
}
