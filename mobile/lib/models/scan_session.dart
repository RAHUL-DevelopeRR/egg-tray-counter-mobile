import 'capture_view.dart';

enum CaptureState { left, right, straight, processing, complete }

class ScanSession {
  ScanSession({required this.scanId});

  final String scanId;
  final Map<CaptureView, String> _paths = {};

  Map<CaptureView, String> get paths => Map.unmodifiable(_paths);

  bool get isComplete => CaptureView.values.every(_paths.containsKey);

  String? pathFor(CaptureView view) => _paths[view];

  void setPath(CaptureView view, String path) {
    _paths[view] = path;
  }

  void clear(CaptureView view) {
    _paths.remove(view);
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
