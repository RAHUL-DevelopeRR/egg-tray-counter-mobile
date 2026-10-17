import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/capture_view.dart';
import '../../models/scan_session.dart';
import '../../services/captured_still.dart';
import '../../services/frame_evidence.dart';
import '../../services/frame_preflight.dart';
import '../../services/live_frame_preflight.dart';
import '../../services/settings_store.dart';
import 'camera_guide_overlay.dart';
import 'capture_frame_gate.dart';

class GuidedCapturePane extends StatefulWidget {
  const GuidedCapturePane({
    required this.cameras,
    required this.session,
    required this.onComplete,
    this.initialView,
    this.settings,
    this.views = CaptureView.values,
    this.mainCameraOnly = false,
    this.onClose,
    super.key,
  });

  final List<CameraDescription> cameras;
  final ScanSession session;
  final CaptureView? initialView;
  final ValueChanged<ScanSession> onComplete;
  final SettingsStore? settings;
  final List<CaptureView> views;
  final bool mainCameraOnly;

  /// Shown as a close control over the viewfinder (the screen has no app bar).
  final VoidCallback? onClose;

  @override
  State<GuidedCapturePane> createState() => _GuidedCapturePaneState();
}

class _GuidedCapturePaneState extends State<GuidedCapturePane>
    with WidgetsBindingObserver {
  final _live = LiveFramePreflight();
  CameraController? _controller;
  late CaptureView _view;
  bool _capturing = false;
  bool _torchChanging = false;
  String? _cameraError;
  CaptureFrameGate _frameGate = const CaptureFrameGate(
    stackContained: true,
    topAndBaseVisible: true,
    viewAngleConfirmed: true,
  );
  PreflightReport _report = PreflightReport.waiting;
  Future<void> _cameraTask = Future<void>.value();
  int _cameraGeneration = 0;
  bool _cameraActive = true;

  /// How the phone is held (0 upright, 90 turned counter-clockwise, 270
  /// clockwise). The screen itself never rotates: the viewfinder stays fixed
  /// to the phone like a normal camera app, the text and guide turn to face
  /// the operator, and the saved photo is turned upright to match.
  int _captureRotation = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    WidgetsBinding.instance.addObserver(this);
    _view = widget.initialView ?? _nextMissing ?? widget.views.first;
    _live
      ..addListener(_onLiveReport)
      ..setView(_view)
      ..startSensors();
    _loadLevelReference();
    _initializeCamera();
  }

  CaptureView? get _nextMissing {
    for (final view in widget.views) {
      if (widget.session.pathFor(view) == null) return view;
    }
    return null;
  }

  void _onLiveReport() {
    if (!mounted) return;
    _followHand(_live.rawRollDeg);
    setState(() => _report = _live.value);
  }

  Future<void> _loadLevelReference() async {
    final settings = widget.settings;
    if (settings == null) return;
    final calibration = await settings.getPoseCalibration();
    if (!mounted) return;
    _live.setCalibration(calibration);
  }

  CameraDescription? get _preferredCamera {
    if (widget.cameras.isEmpty) return null;
    // The main (1x) back camera when the device reports lens types; otherwise
    // the first back camera, which is the main one on every phone seen so far.
    for (final camera in widget.cameras) {
      if (camera.lensDirection == CameraLensDirection.back &&
          camera.lensType == CameraLensType.wide) {
        return camera;
      }
    }
    return widget.cameras.cast<CameraDescription?>().firstWhere(
      (camera) => camera?.lensDirection == CameraLensDirection.back,
      orElse: () => widget.mainCameraOnly ? null : widget.cameras.first,
    );
  }

  /// Reads how the phone is held from the accelerometer; works with the
  /// system rotation lock on, and never turns the screen.
  void _followHand(double? rawRoll) {
    final next = nextCaptureRotation(_captureRotation, rawRoll);
    if (next == _captureRotation) return;
    _captureRotation = next;
    _live.setCaptureRotation(next);
  }

  Future<void> _initializeCamera() {
    final generation = ++_cameraGeneration;
    _cameraActive = true;
    return _cameraTask = _cameraTask.then((_) => _replaceCamera(generation));
  }

  Future<void> _replaceCamera(int generation) async {
    await _live.stopCamera();
    final previous = _controller;
    _controller = null;
    if (mounted) setState(() {});
    await _disposeCamera(previous);
    if (!mounted || !_cameraActive || generation != _cameraGeneration) return;
    final camera = _preferredCamera;
    if (camera == null) {
      setState(
        () => _cameraError = widget.mainCameraOnly
            ? 'The main camera cannot be identified on this device. Upload original 1x photos instead.'
            : 'No camera is available on this device.',
      );
      return;
    }
    final next = CameraController(
      camera,
      // 1080p: enough pixels per layer for the counter, a tenth of the upload
      // bytes of a full-resolution still, no Worker resource limits.
      ResolutionPreset.veryHigh,
      enableAudio: false,
      // The analysis stream reads plane 0 of the preview, which is luminance
      // only in yuv420. Still captures stay JPEG regardless.
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    try {
      await next.initialize();
      try {
        await next.setZoomLevel(1.0);
      } on Object {
        // Zoom control is optional; the preset already selects the main lens.
      }
      if (!mounted || !_cameraActive || generation != _cameraGeneration) {
        await _disposeCamera(next);
        return;
      }
      // No capture-orientation lock: the plugin rotates the preview and tags
      // the still from the display rotation at capture time, so a sideways
      // phone gives an upright landscape photo like any camera app.
      setState(() {
        _controller = next;
        _cameraError = null;
      });
      await _live.startCamera(next);
    } on CameraException catch (error) {
      await _disposeCamera(next);
      if (!mounted || generation != _cameraGeneration) return;
      setState(() {
        _controller = null;
        _cameraError = error.code == 'CameraAccessDenied'
            ? 'Camera permission was denied. Enable it in device settings.'
            : 'Camera could not start: ${error.description ?? error.code}';
      });
    } on Object {
      await _disposeCamera(next);
      if (!mounted || generation != _cameraGeneration) return;
      setState(() {
        _controller = null;
        _cameraError = 'Camera could not start. Reopen the scan to retry.';
      });
    }
  }

  Future<void> _disposeCamera(CameraController? controller) async {
    try {
      await controller?.dispose();
    } on CameraException {
      // A camera already released by Android must not break the resume queue.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _cameraActive = false;
      ++_cameraGeneration;
      _live.stopSensors();
      _cameraTask = _cameraTask.then((_) async {
        await _live.stopCamera();
        final controller = _controller;
        _controller = null;
        if (mounted) setState(() {});
        await _disposeCamera(controller);
      });
    } else if (state == AppLifecycleState.resumed) {
      _live.startSensors();
      _initializeCamera();
    }
  }

  bool get _liveReady =>
      _cameraActive &&
      _live.streamError == null &&
      _live.frameFresh &&
      _report.metrics != null &&
      _report.measurable;

  bool get _captureAllowed => !_capturing && !_torchChanging && _liveReady;

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        !_cameraActive ||
        _capturing ||
        _torchChanging) {
      return;
    }
    setState(() => _torchChanging = true);
    try {
      await controller.setFlashMode(
        controller.value.flashMode == FlashMode.torch
            ? FlashMode.off
            : FlashMode.torch,
      );
      // Discard pre-lighting measurements before permitting another capture.
      if (mounted && _cameraActive && identical(controller, _controller)) {
        await _live.stopCamera();
        await _live.restartCamera();
      }
    } on CameraException {
      if (mounted) {
        _message('Torch is unavailable. Add even lighting around the stacks.');
      }
    } finally {
      if (mounted) setState(() => _torchChanging = false);
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }
    if (!_captureAllowed || !_frameGate.ready) return;
    final generation = _cameraGeneration;
    String? rawPhoto;
    String? pendingPhoto;
    setState(() => _capturing = true);
    try {
      const cellId = '';
      if (!mounted) return;
      // The operator can move between the tap and the still capture.
      if (!_liveReady ||
          generation != _cameraGeneration ||
          !identical(controller, _controller)) {
        _message(
          'Check the live guidance and hold the phone steady before capturing.',
        );
        return;
      }
      final capturePose = _live.pose;
      // How the phone is held at the tap: the photo is turned to match.
      final rotation = _captureRotation;
      // Android refuses a still capture while an image stream is active.
      await _live.stopCamera();
      XFile photo;
      try {
        photo = await controller.takePicture();
        rawPhoto = photo.path;
      } finally {
        if (mounted &&
            _cameraActive &&
            generation == _cameraGeneration &&
            identical(controller, _controller)) {
          await _live.restartCamera();
        }
      }
      final prepared = await prepareCapturedStill(
        StillRequest(
          sourcePath: photo.path,
          targetPath: _uprightPath(photo.path),
          captureRotation: rotation,
          sensorOrientation: controller.description.sensorOrientation,
        ),
      );
      if (prepared != null) pendingPhoto = prepared.path;
      if (!mounted || generation != _cameraGeneration) return;
      if (prepared == null) {
        await _showRejection(
          'Photo could not be checked',
          'The saved photo could not be decoded. Retake this view.',
        );
        return;
      }
      final still = _verify(prepared.analysis, controller, capturePose);
      if (still.blocked) {
        await _showRejection(
          still.firstBlocker!.headline,
          '${still.firstBlocker!.detail}\n\n${still.firstBlocker!.action ?? ''}',
        );
        return;
      }
      if (!prepared.quality.accepted) {
        await _showRejection(
          'Retake ${_view.name.toUpperCase()}',
          prepared.quality.reason ?? 'Image quality is not sufficient.',
        );
        return;
      }
      final previousPath = widget.session.pathFor(_view);
      widget.session.setPath(
        _view,
        prepared.path,
        cellId: cellId,
        evidence: jsonEncode({
          ...still.toJson(),
          'source': 'captured_still',
          'capture_orientation': switch (rotation) {
            90 => 'landscape_left',
            270 => 'landscape_right',
            _ => 'portrait',
          },
          'upright_pixels': true,
          'width': prepared.width,
          'height': prepared.height,
        }),
      );
      pendingPhoto = null; // The session now owns this file.
      if (previousPath != null && previousPath != prepared.path) {
        await _deleteCapture(previousPath);
      }
      if (_nextMissing == null) {
        widget.onComplete(widget.session);
        return;
      }
      if (!mounted) return;
      setState(() {
        _view = _nextMissing!;
        _frameGate = const CaptureFrameGate(
          stackContained: true,
          topAndBaseVisible: true,
          viewAngleConfirmed: true,
        );
      });
      _live.setView(_view);
    } on CameraException catch (error) {
      if (!mounted) return;
      _message(error.description ?? 'Camera capture failed.');
    } on FileSystemException {
      if (mounted) {
        _message('Could not read the saved photo. Please retake it.');
      }
    } finally {
      if (rawPhoto != null) await _deleteCapture(rawPhoto);
      if (pendingPhoto != null) await _deleteCapture(pendingPhoto);
      if (mounted) setState(() => _capturing = false);
    }
  }

  String _uprightPath(String raw) =>
      '${raw.replaceFirst(RegExp(r'\.jpe?g$', caseSensitive: false), '')}'
      '-upright.jpg';

  /// Re-runs every check on the photo that will be uploaded, measured on the
  /// whole upright frame (the geometry the live frames had) with the angle
  /// held at capture time. A device whose still has a different aspect from
  /// its preview keeps the guide-derived checks advisory, while lighting,
  /// focus and clipping keep full blocking power.
  PreflightReport _verify(
    LumaPlane plane,
    CameraController controller,
    DevicePose? capturePose,
  ) {
    // previewSize is in sensor coordinates (long side first); the upright
    // frame is portrait or landscape the way the phone was held.
    final sensorAspect = controller.value.aspectRatio;
    final landscapeAspect = sensorAspect >= 1 ? sensorAspect : 1 / sensorAspect;
    final stillAspect = plane.width / plane.height;
    final previewAspect = stillAspect >= 1
        ? landscapeAspect
        : 1 / landscapeAspect;
    final guide = mapGuideToStill(
      _live.analyzer.guide,
      previewAspect: previewAspect,
      stillAspect: stillAspect,
    );
    final metrics = FrameAnalyzer(guide: guide).analyze(plane);
    final report = _live.preflight.evaluate(
      view: _view,
      metrics: metrics,
      pose: capturePose,
      calibrationSet: _live.calibration.isSet,
      measuredAt: DateTime.now(),
    );
    final mismatch = (previewAspect / stillAspect - 1).abs() > 0.05;
    if (!mismatch) return report;
    return report.withAdvisoryOnly({
      PreflightCheckId.framing,
      PreflightCheckId.coverage,
    });
  }

  Future<void> _deleteCapture(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // Only app-created, individually named captures are removed; a failed
      // cleanup must not discard the session's replacement photo.
    }
  }

  Future<void> _showRejection(String title, String body) async {
    final turns = _captureRotation ~/ 90;
    await showDialog<void>(
      context: context,
      builder: (context) => _WorldOriented(
        quarterTurns: turns,
        child: AlertDialog(
          icon: const Icon(Icons.photo_camera_back_outlined),
          title: Text(title),
          content: Text(body),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('RETAKE'),
            ),
          ],
        ),
      ),
    );
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    WidgetsBinding.instance.removeObserver(this);
    _cameraActive = false;
    ++_cameraGeneration;
    _live.removeListener(_onLiveReport);
    _live.dispose();
    _cameraTask = _cameraTask.then((_) async {
      await _live.stopCamera();
      await _live.stopSensors();
      await _disposeCamera(_controller);
      _controller = null;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final prepared = controller != null && controller.value.isInitialized;
    final turns = _captureRotation ~/ 90;
    final sideways = turns != 0;
    final torch = TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      onPressed: prepared && _cameraActive && !_capturing && !_torchChanging
          ? _toggleTorch
          : null,
      icon: Icon(
        controller?.value.flashMode == FlashMode.torch
            ? Icons.flashlight_off
            : Icons.flashlight_on,
        size: 18,
      ),
      label: Text(
        controller?.value.flashMode == FlashMode.torch
            ? 'TURN TORCH OFF'
            : 'TURN TORCH ON',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
    final capture = FilledButton.icon(
      style: FilledButton.styleFrom(
        minimumSize: Size(sideways ? 200 : double.infinity, 52),
      ),
      onPressed: prepared && _captureAllowed && _frameGate.ready
          ? _capture
          : null,
      icon: _capturing
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.camera_alt),
      label: Text('CAPTURE ${_view.name.toUpperCase()}'),
    );
    final banner = _ConstraintBanner(
      report: _report,
      streamError:
          _live.streamError ??
          (!_live.frameFresh
              ? 'Waiting for a fresh camera frame. Hold still.'
              : null),
      locked: !_captureAllowed,
    );
    final top = SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (widget.onClose != null)
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                  color: Colors.white,
                  tooltip: 'Close',
                ),
              const Spacer(),
              torch,
              const SizedBox(width: 6),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: _StepRow(
              view: _view,
              session: widget.session,
              views: widget.views,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  _view.instruction,
                  maxLines: sideways ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    final bottom = sideways
        ? Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: banner),
                    const SizedBox(width: 12),
                    capture,
                  ],
                ),
              ),
            ),
          )
        : Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [banner, const SizedBox(height: 8), capture],
                ),
              ),
            ),
          );
    return Stack(
      fit: StackFit.expand,
      children: [
        _CameraStage(
          controller: prepared ? controller : null,
          guideTurns: turns,
          cameraError: _cameraError,
          view: _view,
          report: _report,
        ),
        _WorldOriented(
          quarterTurns: turns,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(top: 0, left: 0, right: 0, child: top),
              bottom,
            ],
          ),
        ),
      ],
    );
  }
}

/// The viewfinder: the whole portrait camera frame, as large as the screen
/// allows, so what the operator sees is exactly what is photographed and
/// counted (a neighbouring stack at the edge is visible, not hidden off
/// screen). It never rotates; when the phone is held sideways the guide is
/// drawn turned to the operator, in the same upright-frame coordinates the
/// analyser measures.
class _CameraStage extends StatelessWidget {
  const _CameraStage({
    required this.controller,
    required this.guideTurns,
    required this.cameraError,
    required this.view,
    required this.report,
  });

  final CameraController? controller;
  final int guideTurns;
  final String? cameraError;
  final CaptureView view;
  final PreflightReport report;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    final size = controller?.value.previewSize;
    final severity = report.blocked
        ? PreflightSeverity.blocking
        : report.hasAdvisory
        ? PreflightSeverity.advisory
        : PreflightSeverity.pass;
    if (controller == null || size == null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: cameraError == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(cameraError!, textAlign: TextAlign.center),
                ),
        ),
      );
    }
    final long = size.width > size.height ? size.width : size.height;
    final short = size.width > size.height ? size.height : size.width;
    return ColoredBox(
      color: Colors.black,
      child: FittedBox(
        fit: BoxFit.contain,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: short,
          height: long,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreview(controller),
              RotatedBox(
                quarterTurns: guideTurns,
                child: CameraGuideOverlay(view: view, severity: severity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lays [child] out for the way the phone is held and turns it to match, so
/// text reads upright to the operator while the screen stays portrait.
/// Screen insets (status bar, gesture bar) are turned with it.
class _WorldOriented extends StatelessWidget {
  const _WorldOriented({required this.quarterTurns, required this.child});

  /// 0, 1 (phone turned counter-clockwise) or 3 (turned clockwise).
  final int quarterTurns;
  final Widget child;

  EdgeInsets _turn(EdgeInsets p) => quarterTurns == 1
      ? EdgeInsets.fromLTRB(p.top, p.right, p.bottom, p.left)
      : EdgeInsets.fromLTRB(p.bottom, p.left, p.top, p.right);

  @override
  Widget build(BuildContext context) {
    if (quarterTurns % 4 == 0) return child;
    final media = MediaQuery.of(context);
    return RotatedBox(
      quarterTurns: quarterTurns,
      child: MediaQuery(
        data: media.copyWith(
          size: media.size.flipped,
          padding: _turn(media.padding),
          viewPadding: _turn(media.viewPadding),
          viewInsets: EdgeInsets.zero,
        ),
        child: child,
      ),
    );
  }
}

/// The live verdict: what is wrong, by how much, and what to do about it.
class _ConstraintBanner extends StatelessWidget {
  const _ConstraintBanner({
    required this.report,
    required this.streamError,
    required this.locked,
  });

  final PreflightReport report;
  final String? streamError;
  final bool locked;

  List<PreflightCheck> get _visible => [
    for (final check in report.checks)
      if (check.id != PreflightCheckId.calibration) check,
  ];

  PreflightCheck? get _primary {
    final visible = _visible;
    for (final check in visible) {
      if (check.blocking) return check;
    }
    for (final check in visible) {
      if (check.advisory) return check;
    }
    return null;
  }

  Color get _color {
    final primary = _primary;
    if (primary?.blocking ?? false) return const Color(0xFFB3261E);
    if (primary?.advisory ?? false) return const Color(0xFF8A5A00);
    if (report.metrics == null) return const Color(0xFF37474F);
    return const Color(0xFF1B5E20);
  }

  @override
  Widget build(BuildContext context) {
    final primary = _primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (streamError != null)
              Text(
                streamError!,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              )
            else if (report.metrics == null)
              const Text(
                'ANALYSING FRAME',
                style: TextStyle(fontWeight: FontWeight.w900),
              )
            else if (primary == null)
              const Row(
                children: [
                  Icon(Icons.verified, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'READY TO CAPTURE',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              )
            else ...[
              Row(
                children: [
                  Icon(
                    primary.blocking ? Icons.block : Icons.warning_amber,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      primary.headline,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              if (primary.action != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    primary.action!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
            if (report.checks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final id in PreflightCheckId.values)
                      if (id != PreflightCheckId.calibration)
                        _CheckChip(id: id, severity: _severityFor(report, id)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static PreflightSeverity _severityFor(
    PreflightReport report,
    PreflightCheckId id,
  ) {
    for (final check in report.checks) {
      if (check.id != id) continue;
      if (check.blocking) return PreflightSeverity.blocking;
      if (check.advisory) return PreflightSeverity.advisory;
      return PreflightSeverity.pass;
    }
    return PreflightSeverity.pass;
  }
}

class _CheckChip extends StatelessWidget {
  const _CheckChip({required this.id, required this.severity});

  final PreflightCheckId id;
  final PreflightSeverity severity;

  static const Map<PreflightCheckId, String> _labels = {
    PreflightCheckId.lighting: 'LIGHT',
    PreflightCheckId.sharpness: 'FOCUS',
    PreflightCheckId.tilt: 'TILT',
    PreflightCheckId.framing: 'FRAMING',
    PreflightCheckId.coverage: 'COVERAGE',
    PreflightCheckId.direction: 'SQUARE-ON',
  };

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (severity) {
      PreflightSeverity.blocking => (Icons.close, const Color(0xFFFFCDD2)),
      PreflightSeverity.advisory => (
        Icons.priority_high,
        const Color(0xFFFFECB3),
      ),
      PreflightSeverity.pass => (Icons.check, const Color(0xFFC8E6C9)),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
            Text(
              _labels[id]!,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.view,
    required this.session,
    required this.views,
  });

  final CaptureView view;
  final ScanSession session;
  final List<CaptureView> views;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: views
          .map(
            (item) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _StepChip(
                  label: item.name.toUpperCase(),
                  complete: session.pathFor(item) != null,
                  current: item == view,
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.label,
    required this.complete,
    required this.current,
  });

  final String label;
  final bool complete;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
      decoration: BoxDecoration(
        color: complete || current
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: current ? Border.all(color: scheme.primary, width: 2) : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (complete) ...[
            const Icon(Icons.check, size: 16),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
