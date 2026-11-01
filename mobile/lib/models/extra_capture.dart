import 'dart:convert';

/// The optional photos taken after the three required faces (Worker 0.5.0).
/// They are not [CaptureView] values on purpose: the three faces decide when
/// a scan is complete and are looped over everywhere; these never are.
enum ExtraView { corner, elevated }

extension ExtraViewLabel on ExtraView {
  /// The upload field name (`corner`, `elevated`).
  String get wireName => name;

  String get title => switch (this) {
    ExtraView.corner => 'CORNER PHOTO',
    ExtraView.elevated => 'ELEVATED PHOTO',
  };

  String get instruction => switch (this) {
    ExtraView.corner =>
      'Stand at the chosen front corner so two adjoining faces show, top row '
          'and floor visible. Hold the phone level at mid-height.',
    ExtraView.elevated =>
      'From a ladder, or with your arms raised, look down on the block top so '
          'every stack top shows. Pointing down is allowed for this photo.',
  };
}

/// Which front corner the operator stood at for the CORNER photo.
const kCornerFrontLeft = 'front_left';
const kCornerFrontRight = 'front_right';
const kCornerSides = [kCornerFrontLeft, kCornerFrontRight];

/// The operator's reading of one cell in the ELEVATED photo.
const kTapPresent = 'present';
const kTapMissing = 'missing';
const kTapStepDown = 'step_down';
const kTapUnsure = 'unsure';
const kTapStates = [kTapPresent, kTapMissing, kTapStepDown, kTapUnsure];

/// The operator's reading of the ELEVATED photo (contract `elevated_taps`):
/// an X x Y grid where only cells the operator tapped are reported. An
/// untapped cell is not "present"; it is simply not read.
class ElevatedTaps {
  const ElevatedTaps({required this.x, required this.y, this.cells = const {}});

  static const maxEncodedLength = 8000;

  final int x;
  final int y;

  /// `(x, y)` to one of [kTapStates].
  final Map<(int, int), String> cells;

  /// One tap: untapped, then present, missing, step down, unsure, and round
  /// to present again.
  static String nextState(String? state) {
    final index = state == null ? -1 : kTapStates.indexOf(state);
    return kTapStates[(index + 1) % kTapStates.length];
  }

  ElevatedTaps tap(int cx, int cy) => ElevatedTaps(
    x: x,
    y: y,
    cells: {...cells, (cx, cy): nextState(cells[(cx, cy)])},
  );

  Map<String, dynamic> toJson() {
    final keys = cells.keys.toList()
      ..sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1));
    return {
      'x': x,
      'y': y,
      'cells': [
        for (final key in keys)
          {'x': key.$1, 'y': key.$2, 'state': cells[key]},
      ],
    };
  }

  String encode() => jsonEncode(toJson());

  bool get fitsUpload => encode().length <= maxEncodedLength;

  static ElevatedTaps? fromJson(Object? json) {
    if (json is! Map) return null;
    final x = json['x'], y = json['y'];
    if (x is! int || y is! int) return null;
    return ElevatedTaps(
      x: x,
      y: y,
      cells: {
        for (final c in (json['cells'] as List<dynamic>? ?? const []))
          if (c is Map &&
              c['x'] is int &&
              c['y'] is int &&
              kTapStates.contains(c['state']))
            (c['x'] as int, c['y'] as int): c['state'] as String,
      },
    );
  }
}

/// One optional photo kept by the scan session: the file, its constraint
/// evidence and, for the corner, the side; for the elevated photo, the taps.
class ExtraCapture {
  const ExtraCapture({
    required this.path,
    this.evidence,
    this.side,
    this.taps,
  });

  final String path;
  final String? evidence;
  final String? side;
  final ElevatedTaps? taps;

  ExtraCapture withTaps(ElevatedTaps? taps) =>
      ExtraCapture(path: path, evidence: evidence, side: side, taps: taps);
}
