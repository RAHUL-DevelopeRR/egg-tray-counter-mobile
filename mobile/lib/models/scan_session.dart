import 'capture_view.dart';

enum CaptureState { left, right, straight, processing, complete }

class ScanSession {
  ScanSession({required this.scanId});

  final String scanId;
  final Map<CaptureView, String> _paths = {};
  final Map<CaptureView, String> _cellIds = {};

  Map<CaptureView, String> get paths => Map.unmodifiable(_paths);

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

  void setPath(CaptureView view, String path, {required String cellId}) {
    final id = normalizeCellId(cellId);
    _paths[view] = path;
    _cellIds[view] = id;
  }

  void clear(CaptureView view) {
    _paths.remove(view);
    _cellIds.remove(view);
  }

  CaptureView? get nextMissing {
    for (final view in CaptureView.values) {
      if (!_paths.containsKey(view) || !_cellIds.containsKey(view)) return view;
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
