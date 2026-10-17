import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/capture_view.dart';
import '../../models/scan_session.dart';
import '../../models/reconstruction_result.dart';
import '../../services/api_client.dart';
import '../../services/settings_store.dart';
import '../../services/reconstruction_photos.dart';
import '../capture/guided_capture_pane.dart';

const reconstructionBanner =
    'Diagnostic 3D evidence — arbitrary scale, feature points are not trays, no count';

class ReconstructionScreen extends StatefulWidget {
  const ReconstructionScreen({required this.settings, super.key});
  final SettingsStore settings;
  @override
  State<ReconstructionScreen> createState() => _ReconstructionScreenState();
}

class _ReconstructionScreenState extends State<ReconstructionScreen> {
  final _paths = <String?>[null, null];
  final _captured = <String>[];
  ApiClient? _api;
  PreparedPair? _prepared;
  ReconstructionResult? _result;
  Map<String, String> _captureEvidence = {};
  String? _error;
  bool _busy = false, _sameScene = false;

  Future<void> _prepare() async {
    await _prepared?.dispose();
    _prepared = null;
    _result = null;
    if (_paths.every((p) => p != null)) {
      final prepared = await compute(
        prepareReconstructionPair,
        _paths.cast<String>(),
      );
      if (!mounted) {
        await prepared.dispose();
        return;
      }
      _prepared = prepared;
      _prepared!.metadata['capture_evidence'] = _captureEvidence;
    }
  }

  Future<void> _pick(int index) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Photos',
            extensions: ['jpg', 'jpeg', 'png'],
            mimeTypes: ['image/jpeg', 'image/png'],
          ),
        ],
      );
      if (file == null || !mounted) return;
      _paths[index] = file.path;
      _sameScene = false;
      _captureEvidence = {};
      await _prepare();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _capture() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      final session = ScanSession(scanId: const Uuid().v4());
      final captured = await Navigator.of(context).push<ScanSession>(
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Two overlapping views · 1x')),
            body: GuidedCapturePane(
              cameras: cameras,
              session: session,
              settings: widget.settings,
              views: const [CaptureView.straight, CaptureView.right],
              mainCameraOnly: true,
              onComplete: (s) => Navigator.of(context).pop(s),
            ),
          ),
        ),
      );
      _captured.addAll(session.paths.values);
      if (captured == null) return;
      _paths[0] = captured.pathFor(CaptureView.straight);
      _paths[1] = captured.pathFor(CaptureView.right);
      _captureEvidence = captured.constraintEvidence;
      _sameScene = false;
      await _prepare();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reconstruct() async {
    if (_prepared == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final url = await widget.settings.getBaseUrl();
      if (!mounted) return;
      _api = ApiClient(url);
      final result = await _api!.reconstruct(_prepared!);
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _api?.cancel();
    _prepared?.dispose();
    for (final path in _captured) {
      File(path).delete().catchError((_) => File(path));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('3D evidence')),
    body: SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(14),
            child: const Text(reconstructionBanner),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Keep the stacks unchanged. Use two original photos with substantial overlap, taken at 1x on the main camera. Include the full stacks.',
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < 2; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _paths[i] == null
                        ? const Icon(Icons.add_photo_alternate_outlined)
                        : Image.file(
                            File(_paths[i]!),
                            width: 56,
                            height: 64,
                            cacheWidth: 112,
                            fit: BoxFit.cover,
                          ),
                    title: Text('Photo ${i + 1}'),
                    subtitle: Text(
                      _paths[i] == null
                          ? 'Choose original photo'
                          : 'Selected · tap to replace',
                    ),
                    onTap: _busy ? null : () => _pick(i),
                  ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _capture,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('CAPTURE TWO PHOTOS'),
                ),
                if (_prepared != null) ...[
                  if ((_prepared!.metadata['exif_missing'] as List).contains(
                    true,
                  ))
                    const Text(
                      'Camera metadata is missing. This can happen with shared or compressed photos; it does not prove WhatsApp compression. Original camera files are recommended.',
                    ),
                  if (_prepared!.metadata['resized'] == true)
                    Text(
                      'Both photos resized to ${_prepared!.metadata['width']} × ${_prepared!.metadata['height']} with the same scale. Originals are preserved.',
                    ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _sameScene,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _sameScene = v ?? false),
                    title: const Text(
                      'The same stacks remained unchanged between these photos.',
                    ),
                  ),
                ],
                FilledButton(
                  onPressed: !_busy && _prepared != null && _sameScene
                      ? _reconstruct
                      : null,
                  child: const Text('RECONSTRUCT 3D'),
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        LinearProgressIndicator(),
                        SizedBox(height: 8),
                        Text('Preparing 3D evidence…'),
                      ],
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(_error!),
                  ),
                if (_result != null) ...[
                  const SizedBox(height: 16),
                  if (_result!.status == 'reconstructed')
                    ReconstructionView(result: _result!)
                  else
                    Text(
                      '${_result!.reason}\nRetake with more overlapping detail and a small sideways camera movement.',
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class ReconstructionView extends StatefulWidget {
  const ReconstructionView({required this.result, super.key});
  final ReconstructionResult result;
  @override
  State<ReconstructionView> createState() => _ReconstructionViewState();
}

class _ReconstructionViewState extends State<ReconstructionView> {
  int _index = 0;
  double _yaw = .3, _pitch = -.15, _zoom = 1, _startZoom = 1;
  @override
  Widget build(BuildContext context) {
    final h = widget.result.hypotheses[_index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButton<int>(
          isExpanded: true,
          value: _index,
          items: widget.result.hypotheses
              .asMap()
              .entries
              .map(
                (e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(
                    e.value.label == 'exif_focal'
                        ? 'EXIF focal estimate'
                        : 'Assumed focal ${e.value.label} × width',
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _index = v!),
        ),
        Text(
          '${h.points.length} feature points · ${h.inliers} inliers · ${h.error.toStringAsFixed(3)} px reprojection error',
        ),
        const SizedBox(height: 10),
        Semantics(
          label:
              'Interactive sparse 3D evidence. Drag to orbit; pinch to zoom.',
          child: GestureDetector(
            onScaleStart: (_) => _startZoom = _zoom,
            onScaleUpdate: (d) => setState(() {
              _yaw += d.focalPointDelta.dx * .01;
              _pitch = (_pitch + d.focalPointDelta.dy * .01).clamp(-1.5, 1.5);
              _zoom = (_startZoom * d.scale).clamp(.4, 5.0);
            }),
            child: SizedBox(
              height: 360,
              child: CustomPaint(
                painter: ReconstructionPainter(h, _yaw, _pitch, _zoom),
              ),
            ),
          ),
        ),
        const Text(
          'Drag to rotate · pinch to zoom. Amber and blue outlines show the two cameras.',
        ),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            IconButton(
              tooltip: 'Rotate left',
              onPressed: () => setState(() => _yaw -= .4),
              icon: const Icon(Icons.rotate_left),
            ),
            IconButton(
              tooltip: 'Rotate right',
              onPressed: () => setState(() => _yaw += .4),
              icon: const Icon(Icons.rotate_right),
            ),
            IconButton(
              tooltip: 'Zoom in',
              onPressed: () =>
                  setState(() => _zoom = (_zoom * 1.2).clamp(.4, 5.0)),
              icon: const Icon(Icons.zoom_in),
            ),
            IconButton(
              tooltip: 'Reset view',
              onPressed: () => setState(() {
                _yaw = .3;
                _pitch = -.15;
                _zoom = 1;
              }),
              icon: const Icon(Icons.restart_alt),
            ),
          ],
        ),
      ],
    );
  }
}

class ReconstructionPainter extends CustomPainter {
  ReconstructionPainter(this.h, this.yaw, this.pitch, this.zoom);
  final ReconstructionHypothesis h;
  final double yaw, pitch, zoom;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xff081113),
    );
    final low = List<double>.generate(
      3,
      (i) =>
          math.min(h.minimum[i], h.centres.map((c) => c[i]).reduce(math.min)),
    );
    final high = List<double>.generate(
      3,
      (i) =>
          math.max(h.maximum[i], h.centres.map((c) => c[i]).reduce(math.max)),
    );
    final centre = List<double>.generate(3, (i) => (low[i] + high[i]) / 2);
    final radius = math.max(
      .001,
      List<double>.generate(3, (i) => high[i] - low[i]).reduce(math.max) / 2,
    );
    Offset? project(List<double> p) {
      final v = orbitPoint(
        List<double>.generate(3, (i) => (p[i] - centre[i]) / radius),
        yaw,
        pitch,
      );
      final projected = projectPoint(v, zoom);
      return projected == null
          ? null
          : Offset(
              size.width / 2 + projected[0] * size.shortestSide,
              size.height / 2 + projected[1] * size.shortestSide,
            );
    }

    void line(List<double> a, List<double> b, Color color) {
      final pa = project(a), pb = project(b);
      if (pa != null && pb != null) {
        canvas.drawLine(
          pa,
          pb,
          Paint()
            ..color = color
            ..strokeWidth = 1.5,
        );
      }
    }

    final corners = List.generate(
      8,
      (n) => List<double>.generate(
        3,
        (i) => (n & (1 << i)) == 0 ? h.minimum[i] : h.maximum[i],
      ),
    );
    for (var n = 0; n < 8; n++) {
      for (var i = 0; i < 3; i++) {
        if ((n & (1 << i)) == 0) {
          line(corners[n], corners[n | (1 << i)], Colors.white30);
        }
      }
    }
    final points = [...h.points]
      ..sort(
        (a, b) => orbitPoint(
          b,
          yaw,
          pitch,
        )[2].compareTo(orbitPoint(a, yaw, pitch)[2]),
      );
    for (final p in points) {
      final projected = project(p);
      if (projected != null) {
        canvas.drawCircle(
          projected,
          2.5,
          Paint()
            ..color = Color.fromARGB(
              255,
              p[3].round().clamp(0, 255),
              p[4].round().clamp(0, 255),
              p[5].round().clamp(0, 255),
            ),
        );
      }
    }
    for (var c = 0; c < 2; c++) {
      final scale = radius * .15;
      final frustum =
          [
                [-.6, -.4, 1.0],
                [.6, -.4, 1.0],
                [.6, .4, 1.0],
                [-.6, .4, 1.0],
              ]
              .map(
                (v) => List<double>.generate(
                  3,
                  (r) =>
                      h.centres[c][r] +
                      scale *
                          (h.orientations[c][r][0] * v[0] +
                              h.orientations[c][r][1] * v[1] +
                              h.orientations[c][r][2] * v[2]),
                ),
              )
              .toList();
      final color = c == 0 ? Colors.amber : Colors.lightBlueAccent;
      for (var i = 0; i < 4; i++) {
        line(h.centres[c], frustum[i], color);
        line(frustum[i], frustum[(i + 1) % 4], color);
      }
    }
  }

  @override
  bool shouldRepaint(covariant ReconstructionPainter old) =>
      old.h != h || old.yaw != yaw || old.pitch != pitch || old.zoom != zoom;
}
