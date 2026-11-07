import 'block_declaration.dart';
import 'capture_view.dart';
import 'extra_capture.dart';

enum CaptureState { left, right, straight, processing, complete }

class ScanSession {
  ScanSession({required this.scanId});

  final String scanId;
  final Map<CaptureView, String> _paths = {};
  final Map<CaptureView, String> _cellIds = {};
  final Map<CaptureView, String> _evidence = {};
  final Map<ExtraView, ExtraCapture> _extras = {};
  BlockDeclaration? _declaration;
  bool _declarationAsked = false;

  Map<CaptureView, String> get paths => Map.unmodifiable(_paths);

  /// Every photo file the session owns: the three faces and the extras.
  List<String> get allPaths => [
    ..._paths.values,
    for (final extra in _extras.values) extra.path,
  ];

  /// The operator's blind declaration; null when it was skipped (or not yet
  /// asked, see [declarationAsked]). A skipped declaration means the result
  /// can never be `confirmed`.
  BlockDeclaration? get declaration => _declaration;

  /// True once the operator declared or skipped. The declaration is asked
  /// once per block, before any count is shown, and never after a result.
  bool get declarationAsked => _declarationAsked;

  void declare(BlockDeclaration? declaration) {
    _declaration = declaration;
    _declarationAsked = true;
  }

  /// The optional CORNER and ELEVATED photos. They never decide whether the
  /// scan is complete.
  Map<ExtraView, ExtraCapture> get extras => Map.unmodifiable(_extras);

  ExtraCapture? extraFor(ExtraView view) => _extras[view];

  /// A new photo for [view]; elevated taps belonged to the old photo and are
  /// dropped with it.
  void setExtra(
    ExtraView view,
    String path, {
    String? evidence,
    String? side,
  }) {
    _extras[view] = ExtraCapture(path: path, evidence: evidence, side: side);
  }

  void setElevatedTaps(ElevatedTaps? taps) {
    final elevated = _extras[ExtraView.elevated];
    if (elevated == null) return;
    _extras[ExtraView.elevated] = elevated.withTaps(taps);
  }

  void clearExtra(ExtraView view) => _extras.remove(view);

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

  /// The session for a retake of [view]: the other photos, their cell IDs and
  /// evidence carried over under a new [scanId]. One scan id is one ordered
  /// triplet; the server refuses an id reused with other photos. The extras
  /// and the declaration are the same block's and carry over unchanged: the
  /// declaration was made blind and is not asked again after a result.
  ScanSession retake(CaptureView view, {required String scanId}) {
    final next = ScanSession(scanId: scanId);
    next._extras.addAll(_extras);
    next._declaration = _declaration;
    next._declarationAsked = _declarationAsked;
    for (final kept in CaptureView.values) {
      if (kept == view) continue;
      final path = _paths[kept];
      if (path == null) continue;
      next._paths[kept] = path;
      final cellId = _cellIds[kept];
      if (cellId != null) next._cellIds[kept] = cellId;
      final evidence = _evidence[kept];
      if (evidence != null) next._evidence[kept] = evidence;
    }
    return next;
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
