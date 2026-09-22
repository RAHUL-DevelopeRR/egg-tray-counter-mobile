import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/capture_view.dart';
import '../../models/scan_session.dart';
import '../../services/frame_evidence.dart';
import '../../services/frame_preflight.dart';
import '../../services/image_quality_service.dart';
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
    super.key,
  });

  final List<CameraDescription> cameras;
  final ScanSession session;
  final CaptureView? initialView;
  final ValueChanged<ScanSession> onComplete;
  final SettingsStore? settings;

  @override
  State<GuidedCapturePane> createState() => _GuidedCapturePaneState();
}

class _GuidedCapturePaneState extends State<GuidedCapturePane>
    with WidgetsBindingObserver {
  final _quality = const ImageQualityService();
  final _live = LiveFramePreflight();
  CameraController? _controller;
  late CaptureView _view;
  bool _capturing = false;
  String? _cameraError;
  CaptureFrameGate _frameGate = const CaptureFrameGate();
  PreflightReport _report = PreflightReport.waiting;
  Future<void> _cameraTask = Future<void>.value();
  int _cameraGeneration = 0;
  bool _cameraActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _view =
        widget.initialView ?? widget.session.nextMissing ?? CaptureView.left;
    _live
      ..addListener(_onLiveReport)
      ..setView(_view)
      ..startSensors();
    _loadLevelReference();
    _initializeCamera();
  }

  void _onLiveReport() {
    if (!mounted) return;
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
    return widget.cameras.cast<CameraDescription?>().firstWhere(
      (camera) => camera?.lensDirection == CameraLensDirection.back,
      orElse: () => widget.cameras.first,
    );
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
      setState(() => _cameraError = 'No camera is available on this device.');
      return;
    }
    final next = CameraController(
      camera,
      ResolutionPreset.max,
      enableAudio: false,
      // The analysis stream reads plane 0 of the preview, which is luminance
      // only in yuv420. Still captures stay JPEG regardless.
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    try {
      await next.initialize();
      if (!mounted || !_cameraActive || generation != _cameraGeneration) {
        await _disposeCamera(next);
        return;
      }
      await next.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted || !_cameraActive || generation != _cameraGeneration) {
        await _disposeCamera(next);
        return;
      }
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

  /// Stores an operator reference for tilt guidance, not camera calibration.
  Future<void> _setLevelReference() async {
    final raw = _live.rawPose;
    if (raw == null) {
      _message(
        'The tilt sensor has not reported a reading yet. Hold the phone still for a moment.',
      );
      return;
    }
    final calibration = PoseCalibration(
      rollOffsetDeg: raw.rollDeg,
      pitchOffsetDeg: raw.pitchDownDeg,
      referenceSet: true,
    );
    _live.setCalibration(calibration);
    await widget.settings?.setPoseCalibration(calibration);
    if (!mounted) return;
    _message(
      'Tilt reference stored. This does not measure your left/right viewpoint.',
    );
  }

  Future<void> _clearLevelReference() async {
    _live.setCalibration(PoseCalibration.none);
    await widget.settings?.clearPoseCalibration();
    if (!mounted) return;
    _message('Level reference cleared. Checks use absolute gravity again.');
  }

  bool get _liveReady =>
      _cameraActive &&
      _live.streamError == null &&
      _live.frameFresh &&
      _report.metrics != null &&
      _report.measurable;

  bool get _captureAllowed => !_capturing && _liveReady;

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }
    if (!_captureAllowed || !_frameGate.ready) return;
    final generation = _cameraGeneration;
    String? pendingPhoto;
    setState(() => _capturing = true);
    try {
      final cellId = await _confirmCell();
      if (cellId == null || !mounted) return;
      // The operator can move while the optional-ID dialog is open.
      if (!_liveReady ||
          generation != _cameraGeneration ||
          !identical(controller, _controller)) {
        _message(
          'Check the live guidance and hold the phone steady before capturing.',
        );
        return;
      }
      final capturePose = _live.pose;
      // Android refuses a still capture while an image stream is active.
      await _live.stopCamera();
      XFile photo;
      try {
        photo = await controller.takePicture();
        pendingPhoto = photo.path;
      } finally {
        if (mounted &&
            _cameraActive &&
            generation == _cameraGeneration &&
            identical(controller, _controller)) {
          await _live.restartCamera();
        }
      }
      final still = await _verify(photo.path, controller, capturePose);
      if (!mounted || generation != _cameraGeneration) return;
      if (still == null) {
        await _showRejection(
          'Photo could not be checked',
          'The saved photo could not be decoded. Retake this view.',
        );
        return;
      }
      if (still.blocked) {
        await _showRejection(
          still.firstBlocker!.headline,
          '${still.firstBlocker!.detail}\n\n${still.firstBlocker!.action ?? ''}',
        );
        return;
      }
      final quality = await _quality.inspect(photo.path);
      if (!mounted || generation != _cameraGeneration) return;
      if (!quality.accepted) {
        await _showRejection(
          'Retake ${_view.name.toUpperCase()}',
          quality.reason ?? 'Image quality is not sufficient.',
        );
        return;
      }
      final previousPath = widget.session.pathFor(_view);
      widget.session.setPath(
        _view,
        photo.path,
        cellId: cellId,
        evidence: jsonEncode({...still.toJson(), 'source': 'captured_still'}),
      );
      pendingPhoto = null; // The session now owns this file.
      if (previousPath != null && previousPath != photo.path) {
        await _deleteCapture(previousPath);
      }
      if (widget.session.isComplete) {
        widget.onComplete(widget.session);
        return;
      }
      if (!mounted) return;
      setState(() {
        _view = widget.session.nextMissing!;
        _frameGate = const CaptureFrameGate();
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
      if (pendingPhoto != null) await _deleteCapture(pendingPhoto);
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Re-runs every check on the still that was actually written to disk, using
  /// the angle held at capture time. The preview and the still are different
  /// crops, so guide-derived checks are limited to advisories here while
  /// lighting, focus and clipping keep full blocking power.
  Future<PreflightReport?> _verify(
    String path,
    CameraController controller,
    DevicePose? capturePose,
  ) async {
    final bytes = await File(path).readAsBytes();
    final plane = lumaFromJpeg(bytes);
    if (plane == null) return null;
    // The camera sensor is landscape-native; this pane locks capture upright.
    final previewAspect = 1 / controller.value.aspectRatio;
    final stillAspect = plane.width / plane.height;
    final guide = mapGuideToStill(
      const FrameAnalyzer().guide,
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
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
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
    );
  }

  Future<String?> _confirmCell() async {
    var input = '';
    final form = GlobalKey<FormState>();
    final id = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${_view.name.toUpperCase()}: capture the same stacks'),
        content: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Keep the same group of stacks in all three photos. If a painted cell ID is present, enter it. Otherwise leave this blank for model analysis.',
                ),
                TextFormField(
                  onChanged: (value) => input = value,
                  autofocus: true,
                  maxLength: 32,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Painted cell ID (optional)',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    try {
                      ScanSession.normalizeCellId(value);
                      return null;
                    } on FormatException catch (error) {
                      return error.message;
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(
                  context,
                  input.trim().isEmpty
                      ? ''
                      : ScanSession.normalizeCellId(input),
                );
              }
            },
            child: const Text('CAPTURE'),
          ),
        ],
      ),
    );
    return id;
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
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
    return Column(
      children: [
        _CaptureHeader(view: _view, session: widget.session),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: AspectRatio(
                    // The preview box matches the image aspect so the on-screen
                    // guide is the same normalised rectangle the analyser uses.
                    aspectRatio: prepared
                        ? 1 / controller.value.aspectRatio
                        : 0.75,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (prepared)
                          CameraPreview(controller)
                        else
                          Center(
                            child: _cameraError == null
                                ? const CircularProgressIndicator()
                                : Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      _cameraError!,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                          ),
                        CameraGuideOverlay(
                          view: _view,
                          severity: _report.blocked
                              ? PreflightSeverity.blocking
                              : _report.hasAdvisory
                              ? PreflightSeverity.advisory
                              : PreflightSeverity.pass,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 160,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                _ConstraintBanner(
                  report: _report,
                  streamError:
                      _live.streamError ??
                      (!_live.frameFresh
                          ? 'Waiting for a fresh camera frame. Hold still.'
                          : null),
                  locked: !_captureAllowed,
                ),
                _LevelReferenceBar(
                  calibration: _live.calibration,
                  rawPose: _live.rawPose,
                  onSet: _setLevelReference,
                  onClear: _clearLevelReference,
                ),
              ],
            ),
          ),
        ),
        _FrameChecklist(
          gate: _frameGate,
          view: _view,
          onChanged: (gate) => setState(() => _frameGate = gate),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: FilledButton.icon(
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
          ),
        ),
      ],
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

  Color get _color {
    if (report.blocked) return const Color(0xFFB3261E);
    if (report.hasAdvisory) return const Color(0xFF8A5A00);
    if (report.metrics == null) return const Color(0xFF37474F);
    return const Color(0xFF1B5E20);
  }

  @override
  Widget build(BuildContext context) {
    final primary = report.primary;
    final measured = report.measuredAt;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (streamError != null)
              Text(
                streamError!,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              )
            else if (primary == null)
              const Text(
                'ANALYSING FRAME',
                style: TextStyle(fontWeight: FontWeight.w900),
              )
            else ...[
              Row(
                children: [
                  Icon(
                    primary.blocking
                        ? Icons.block
                        : primary.advisory
                        ? Icons.warning_amber
                        : Icons.verified,
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
              const SizedBox(height: 4),
              Text(primary.detail, style: const TextStyle(fontSize: 12)),
              if (primary.action != null) ...[
                const SizedBox(height: 4),
                Text(
                  primary.action!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              if (locked && report.blockingCount > 0)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'CAPTURE LOCKED UNTIL THIS IS FIXED',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
            ],
            if (report.checks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final id in PreflightCheckId.values)
                    _CheckChip(id: id, severity: _severityFor(report, id)),
                ],
              ),
            ],
            if (measured != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Roll ${report.pose?.rollDeg.abs().toStringAsFixed(1) ?? '-'}° · '
                  'Pitch ${report.pose?.pitchDownDeg.toStringAsFixed(1) ?? '-'}° · '
                  'Sharpness ${report.metrics?.sharpness.toStringAsFixed(0) ?? '-'} · '
                  'Light ${report.metrics?.meanLuma.toStringAsFixed(0) ?? '-'}/255',
                  style: const TextStyle(fontSize: 11),
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
    PreflightCheckId.calibration: 'LEVEL REF',
    PreflightCheckId.lighting: 'LIGHT',
    PreflightCheckId.sharpness: 'FOCUS',
    PreflightCheckId.tilt: 'TILT',
    PreflightCheckId.framing: 'FRAMING',
    PreflightCheckId.coverage: 'COVERAGE',
    PreflightCheckId.direction: 'ANGLE',
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

/// Takes and clears the operator's level reference without leaving the camera.
class _LevelReferenceBar extends StatelessWidget {
  const _LevelReferenceBar({
    required this.calibration,
    required this.rawPose,
    required this.onSet,
    required this.onClear,
  });

  final PoseCalibration calibration;
  final DevicePose? rawPose;
  final VoidCallback onSet;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                calibration.isSet
                    ? 'Level reference set (${calibration.rollOffsetDeg.abs().toStringAsFixed(1)}° roll, '
                          '${calibration.pitchOffsetDeg.toStringAsFixed(1)}° pitch stored)'
                    : 'Align with the upright tray stacks, then set a tilt reference. '
                          'Left/right position still needs your check.',
                style: const TextStyle(fontSize: 11),
              ),
            ),
            const SizedBox(width: 8),
            if (calibration.isSet)
              TextButton(onPressed: onClear, child: const Text('CLEAR'))
            else
              FilledButton.tonal(
                onPressed: rawPose == null ? null : onSet,
                child: const Text('SET LEVEL'),
              ),
          ],
        ),
      ),
    );
  }
}

class _FrameChecklist extends StatelessWidget {
  const _FrameChecklist({
    required this.gate,
    required this.view,
    required this.onChanged,
  });

  final CaptureFrameGate gate;
  final CaptureView view;
  final ValueChanged<CaptureFrameGate> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          CheckboxListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            value: gate.stackContained,
            onChanged: (value) =>
                onChanged(gate.copyWith(stackContained: value ?? false)),
            title: const Text(
              'The same complete group of stacks is inside the guide',
            ),
          ),
          CheckboxListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            value: gate.topAndBaseVisible,
            onChanged: (value) =>
                onChanged(gate.copyWith(topAndBaseVisible: value ?? false)),
            title: const Text('The stack tops and bases are visible'),
          ),
          CheckboxListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            value: gate.viewAngleConfirmed,
            onChanged: (value) =>
                onChanged(gate.copyWith(viewAngleConfirmed: value ?? false)),
            title: Text(
              'I moved to the ${view.name.toUpperCase()} viewpoint; the same stacks remain visible',
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptureHeader extends StatelessWidget {
  const _CaptureHeader({required this.view, required this.session});

  final CaptureView view;
  final ScanSession session;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: CaptureView.values
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
          ),
          const SizedBox(height: 18),
          Text(
            view.title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(view.instruction),
        ],
      ),
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
      padding: const EdgeInsets.symmetric(vertical: 9),
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
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
