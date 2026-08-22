import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../models/capture_view.dart';
import '../../models/scan_session.dart';
import '../../services/image_quality_service.dart';
import 'camera_guide_overlay.dart';
import 'capture_frame_gate.dart';

class GuidedCapturePane extends StatefulWidget {
  const GuidedCapturePane({
    required this.cameras,
    required this.session,
    required this.onComplete,
    this.initialView,
    super.key,
  });

  final List<CameraDescription> cameras;
  final ScanSession session;
  final CaptureView? initialView;
  final ValueChanged<ScanSession> onComplete;

  @override
  State<GuidedCapturePane> createState() => _GuidedCapturePaneState();
}

class _GuidedCapturePaneState extends State<GuidedCapturePane>
    with WidgetsBindingObserver {
  final _quality = const ImageQualityService();
  CameraController? _controller;
  late CaptureView _view;
  bool _capturing = false;
  String? _cameraError;
  CaptureFrameGate _frameGate = const CaptureFrameGate();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _view =
        widget.initialView ?? widget.session.nextMissing ?? CaptureView.left;
    _initializeCamera();
  }

  CameraDescription? get _preferredCamera {
    if (widget.cameras.isEmpty) return null;
    return widget.cameras.cast<CameraDescription?>().firstWhere(
      (camera) => camera?.lensDirection == CameraLensDirection.back,
      orElse: () => widget.cameras.first,
    );
  }

  Future<void> _initializeCamera() async {
    final camera = _preferredCamera;
    if (camera == null) {
      setState(() => _cameraError = 'No camera is available on this device.');
      return;
    }
    final previous = _controller;
    _controller = null;
    await previous?.dispose();
    final next = CameraController(
      camera,
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await next.initialize();
      if (!mounted) {
        await next.dispose();
        return;
      }
      setState(() {
        _controller = next;
        _cameraError = null;
      });
    } on CameraException catch (error) {
      await next.dispose();
      if (!mounted) return;
      setState(() {
        _cameraError = error.code == 'CameraAccessDenied'
            ? 'Camera permission was denied. Enable it in device settings.'
            : 'Camera could not start: ${error.description ?? error.code}';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final photo = await controller.takePicture();
      final quality = await _quality.inspect(photo.path);
      if (!quality.accepted) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.photo_camera_back_outlined),
            title: Text('Retake ${_view.name.toUpperCase()}'),
            content: Text(quality.reason ?? 'Image quality is not sufficient.'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('RETAKE'),
              ),
            ],
          ),
        );
        return;
      }
      widget.session.setPath(_view, photo.path);
      if (widget.session.isComplete) {
        widget.onComplete(widget.session);
        return;
      }
      if (!mounted) return;
      setState(() {
        _view = widget.session.nextMissing!;
        _frameGate = const CaptureFrameGate();
      });
    } on CameraException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.description ?? 'Camera capture failed.')),
      );
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (controller != null && controller.value.isInitialized)
                      Center(child: CameraPreview(controller))
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
                    CameraGuideOverlay(view: _view, ready: _frameGate.ready),
                    Positioned(
                      left: 20,
                      right: 20,
                      top: 18,
                      child: _ReadinessBanner(ready: _frameGate.ready),
                    ),
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 18,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Text(
                            'Frame one physical stack. Align its base with the lower guide.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
            onPressed:
                controller?.value.isInitialized == true &&
                    !_capturing &&
                    _frameGate.ready
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

class _ReadinessBanner extends StatelessWidget {
  const _ReadinessBanner({required this.ready});

  final bool ready;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: (ready ? Colors.green.shade800 : Colors.red.shade800).withValues(
          alpha: 0.86,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          ready
              ? 'READY — framing confirmed'
              : 'NOT READY — complete framing checks',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w900),
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
            title: const Text('One stack is completely inside the guide'),
          ),
          CheckboxListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            value: gate.topAndBaseVisible,
            onChanged: (value) =>
                onChanged(gate.copyWith(topAndBaseVisible: value ?? false)),
            title: const Text('Stack top and base are visible'),
          ),
          CheckboxListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            value: gate.viewAngleConfirmed,
            onChanged: (value) =>
                onChanged(gate.copyWith(viewAngleConfirmed: value ?? false)),
            title: Text('${view.name.toUpperCase()} angle matches the guide'),
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
