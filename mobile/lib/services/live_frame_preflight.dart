import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:sensors_plus/sensors_plus.dart';

import '../models/capture_view.dart';
import 'frame_evidence.dart';
import 'frame_preflight.dart';

/// Turns the live preview stream and the accelerometer into a continuously
/// updated [PreflightReport], so the operator is told what is wrong *before*
/// pressing capture rather than after a rejected upload.
///
/// This class holds no widgets and no thresholds of its own: measurement lives
/// in [FrameAnalyzer], judgement in [FramePreflight]. It only schedules work,
/// converts the platform encodings (camera Y plane, JPEG still, accelerometer
/// axes) into the two inputs those two classes accept, and publishes the result.
class LiveFramePreflight extends ValueNotifier<PreflightReport> {
  LiveFramePreflight({
    this.analyzer = const FrameAnalyzer(),
    this.preflight = const FramePreflight(),
    this.minimumInterval = const Duration(milliseconds: 300),
  }) : super(PreflightReport.waiting);

  final FrameAnalyzer analyzer;
  final FramePreflight preflight;

  /// Analysis is deliberately slow. Trays do not move, and spending every
  /// preview frame on the main isolate would stutter the viewfinder an
  /// operator has to aim with.
  final Duration minimumInterval;

  CameraController? _controller;
  StreamSubscription<AccelerometerEvent>? _accelerometer;
  DevicePose? _rawPose;
  PoseCalibration _calibration = PoseCalibration.none;
  FrameMetrics? _metrics;
  CaptureView _view = CaptureView.left;
  DateTime? _lastAnalysis;
  DateTime? _lastPose;
  Timer? _freshnessTimer;
  bool _disposed = false;
  bool _analysing = false;
  bool _streaming = false;
  String? _streamError;

  /// Null while the image stream is healthy. Set when the device refuses to
  /// stream, which is common on phones that already have the camera open.
  String? get streamError => _streamError;

  bool get streaming => _streaming;

  PoseCalibration get calibration => _calibration;

  DevicePose? get rawPose =>
      _lastPose != null &&
          DateTime.now().difference(_lastPose!) <= const Duration(seconds: 2)
      ? _rawPose
      : null;

  DevicePose? get pose => rawPose == null ? null : _calibration.apply(rawPose!);

  bool get frameFresh =>
      _metrics != null &&
      _lastAnalysis != null &&
      DateTime.now().difference(_lastAnalysis!) <= const Duration(seconds: 2);

  FrameMetrics? get metrics => _metrics;

  void setView(CaptureView view) {
    if (_view == view) return;
    _view = view;
    _publish();
  }

  void setCalibration(PoseCalibration calibration) {
    _calibration = calibration;
    _publish();
  }

  void startSensors() {
    _freshnessTimer ??= Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _publish(),
    );
    if (_accelerometer != null) return;
    try {
      _accelerometer =
          accelerometerEventStream(
            samplingPeriod: SensorInterval.uiInterval,
          ).listen(
            _onAccelerometer,
            onError: (Object _) {
              _rawPose = null;
              _lastPose = null;
              _publish();
            },
          );
    } on Object {
      // A device without an accelerometer still gets every image check.
      _rawPose = null;
    }
  }

  Future<void> stopSensors() async {
    final subscription = _accelerometer;
    _accelerometer = null;
    _rawPose = null;
    _lastPose = null;
    await subscription?.cancel();
  }

  /// Starts the analysis stream. Safe to call when the controller is already
  /// streaming; a second call is ignored.
  Future<void> startCamera(CameraController controller) async {
    _controller = controller;
    if (!controller.value.isInitialized || _streaming) return;
    _metrics = null;
    _lastAnalysis = null;
    try {
      await controller.startImageStream(_onCameraImage);
      _streaming = true;
      _streamError = null;
    } on CameraException catch (error) {
      _streaming = false;
      _streamError =
          'Live constraint analysis could not start (${error.code}). '
          'The checks below and the post-capture verification still apply.';
    } on Object {
      _streaming = false;
      _streamError =
          'Live constraint analysis could not start on this device. '
          'The checks below and the post-capture verification still apply.';
    }
    _publish();
  }

  /// Must be awaited before `takePicture`: Android rejects a still capture
  /// while an image stream is active.
  Future<void> stopCamera() async {
    final controller = _controller;
    _streaming = false;
    _analysing = false;
    _metrics = null;
    _lastAnalysis = null;
    _publish();
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } on CameraException {
      // The controller is usually being torn down; nothing to recover here.
    } on Object {
      // Same: a disposed camera cannot be stopped again.
    }
  }

  Future<void> restartCamera() async {
    final controller = _controller;
    if (controller == null) return;
    await startCamera(controller);
  }

  void _onAccelerometer(AccelerometerEvent event) {
    _rawPose = devicePoseFromAccelerometer(event.x, event.y, event.z);
    _lastPose = DateTime.now();
  }

  void _onCameraImage(CameraImage image) {
    if (_analysing) return;
    final now = DateTime.now();
    final last = _lastAnalysis;
    if (last != null && now.difference(last) < minimumInterval) return;
    _lastAnalysis = now;
    _analysing = true;
    try {
      if (image.format.group != ImageFormatGroup.yuv420 ||
          image.planes.isEmpty) {
        throw const FormatException('Unsupported live frame format');
      }
      final plane = image.planes.first;
      final metrics = analyzer.analyze(
        LumaPlane.sample(
          plane.bytes,
          width: image.width,
          height: image.height,
          rowStride: plane.bytesPerRow,
          pixelStride: plane.bytesPerPixel ?? 1,
          rotationDegrees: _controller?.description.sensorOrientation ?? 0,
        ),
      );
      _metrics = metrics;
      _streamError = null;
      _publish();
    } on Object {
      // A malformed frame must never take the preview down with it.
      _metrics = null;
      _streamError = 'Live frame could not be measured. Restart the camera.';
      _publish();
    } finally {
      _analysing = false;
    }
  }

  void _publish() {
    if (_disposed) return;
    value = preflight.evaluate(
      view: _view,
      metrics: frameFresh ? _metrics : null,
      pose: pose,
      calibrationSet: _calibration.isSet,
      measuredAt: _lastAnalysis,
    );
  }

  /// Re-runs every check against the frame that was actually captured, using
  /// the angle the operator held at capture time. This is the check that
  /// decides whether a still is worth uploading.
  PreflightReport evaluateStill(
    FrameMetrics metrics, {
    DevicePose? capturePose,
  }) => preflight.evaluate(
    view: _view,
    metrics: metrics,
    pose: capturePose ?? pose,
    calibrationSet: _calibration.isSet,
    measuredAt: DateTime.now(),
  );

  @override
  void dispose() {
    _disposed = true;
    _freshnessTimer?.cancel();
    _accelerometer?.cancel();
    _accelerometer = null;
    super.dispose();
  }
}

/// Device attitude from raw accelerometer axes.
///
/// Portrait phone, Android axes (+x right, +y up the screen, +z out of the
/// screen towards the operator), gravity measured as proper acceleration when
/// the phone is at rest:
///   upright, camera on the horizon -> (0, +g, 0)
///   lying flat, camera on the floor -> (0, 0, +g)
/// which the two atan2 forms below turn into the [DevicePose] convention
/// (roll 0 = level, pitchDown 0 = horizontal, +90 = straight down).
/// Roll is positive when the top of the phone leans to the operator's left.
/// That sense is cross-checked against the image horizon by
/// [FramePreflight], so a wrong convention surfaces as an inconsistency
/// warning instead of silently wrong advice.
DevicePose? devicePoseFromAccelerometer(double x, double y, double z) {
  final magnitude = math.sqrt(x * x + y * y + z * z);
  if (!magnitude.isFinite || magnitude < 0.5) {
    // Free fall or a saturated reading: no usable attitude.
    return null;
  }
  final ax = x / magnitude;
  final ay = y / magnitude;
  final az = z / magnitude;
  return DevicePose(
    rollDeg: math.atan2(ax, ay) * 180 / math.pi,
    pitchDownDeg: math.atan2(az, math.sqrt(ax * ax + ay * ay)) * 180 / math.pi,
  );
}

/// Decodes a captured JPEG into the analyser's luminance input.
///
/// Orientation is baked first: Android sensors are landscape-native, so the
/// stored pixels are usually rotated and the EXIF tag carries the correction.
/// Without this the guide rectangle would be applied to a sideways image.
LumaPlane? lumaFromJpeg(Uint8List bytes) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object {
    // Truncated and malformed files make the decoder throw rather than return
    // null, and a failed still check must never break the capture flow.
    return null;
  }
  if (decoded == null) return null;
  final oriented = img.bakeOrientation(decoded);
  final sample = oriented.width > kAnalysisWidth
      ? img.copyResize(
          oriented,
          width: kAnalysisWidth,
          interpolation: img.Interpolation.average,
        )
      : oriented;
  final luma = Uint8List(sample.width * sample.height);
  var index = 0;
  for (final pixel in sample) {
    luma[index] = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b)
        .round()
        .clamp(0, 255);
    index += 1;
  }
  return LumaPlane(width: sample.width, height: sample.height, luma: luma);
}

/// Reads [path] and measures it exactly as the live stream would.
Future<FrameMetrics?> measureStill(
  String path, {
  FrameAnalyzer analyzer = const FrameAnalyzer(),
}) async {
  final bytes = await File(path).readAsBytes();
  final plane = lumaFromJpeg(bytes);
  if (plane == null) return null;
  return analyzer.analyze(plane);
}
