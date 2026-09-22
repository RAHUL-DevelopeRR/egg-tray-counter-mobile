import 'capture_view.dart';

enum CaptureState { left, right, straight, processing, complete }

class ScanSession {
  ScanSession({required this.scanId});

  final String scanId;
  final Map<CaptureView, String> _paths = {};
  final Map<CaptureView, String> _cellIds = {};
  final Map<CaptureView, String> _evidence = {};

  Map<CaptureView, String> get paths => Map.unmodifiable(_paths);

  /// Per-view constraint evidence (angle, lighting, sharpness, framing) as it
  /// stood at the moment of capture, keyed by view name. Uploaded with the
  /// scan so a count can be audited against the evidence it was taken from.
  Map<String, String> get constraintEvidence => {
    for (final entry in _evidence.entries) entry.key.name: entry.value,
  };

  bool get isComplete => nextMissing == null;
  String? cellIdFor(CaptureView view) => _cellIds[view];
  Map<String, String> get cellIds => {
    for (final entry in _cellIds.entries) entry.key.name: entry.value,
  };

  static String normalizeCellId(String raw) {
    final id = raw.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9][A-Z0-9_-]{0,31}$').hasMatch(id)) {
      throw const FormatException(
        'Use 1-32 letters, digits, - or _ for the painted cell ID.',
      );
    }
    return id;
  }

  String? pathFor(CaptureView view) => _paths[view];

  void setPath(
    CaptureView view,
    String path, {
    String cellId = '',
    String? evidence,
  }) {
    final id = cellId.trim().isEmpty ? null : normalizeCellId(cellId);
    _paths[view] = path;
    if (evidence == null) {
      _evidence.remove(view);
    } else {
      _evidence[view] = evidence;
    }
    if (id == null) {
      _cellIds.remove(view);
    } else {
      _cellIds[view] = id;
    }
  }

  void clear(CaptureView view) {
    _paths.remove(view);
    _cellIds.remove(view);
    _evidence.remove(view);
  }

  CaptureView? get nextMissing {
    for (final view in CaptureView.values) {
      if (!_paths.containsKey(view)) return view;
    }
    return null;
  }

  CaptureState get captureState => switch (nextMissing) {
    CaptureView.left => CaptureState.left,
    CaptureView.right => CaptureState.right,
    CaptureView.straight => CaptureState.straight,
    null => CaptureState.processing,
  };
}
