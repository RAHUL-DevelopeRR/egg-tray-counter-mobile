import 'dart:convert';

/// One stack the operator knows is shorter than the rest.
class PartialStack {
  const PartialStack({required this.x, required this.y, required this.layers});

  final int x;
  final int y;
  final int layers;

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'layers': layers};

  static PartialStack? fromJson(Object? json) {
    if (json is! Map) return null;
    final x = json['x'], y = json['y'], layers = json['layers'];
    if (x is! int || y is! int || layers is! int) return null;
    return PartialStack(x: x, y: y, layers: layers);
  }
}

/// What the operator states about a block before any count is shown
/// (contract `block_declaration`, Worker 0.5.0). It is entered blind: the
/// pane that collects it runs after the three photos and before the upload,
/// and is never offered again once a result has been seen.
///
/// A declaration is never a measurement. The server labels every value that
/// rests on it `declared`, and it can confirm a block (never make it exact).
class BlockDeclaration {
  const BlockDeclaration({
    required this.x,
    required this.y,
    required this.declaredAt,
    this.interior = kUnknown,
    this.missingCells = const [],
    this.partialStacks = const [],
    this.coverTrays = kUnknown,
    this.occupancy = kUnknown,
    this.referenceHeight,
    this.referenceHeightMeasured = false,
    this.operator = '',
    this.agreesWithFaces,
  });

  static const kUnknown = 'unknown';
  static const kEggFilled = 'egg_filled';
  static const interiorValues = ['full', 'partial', kUnknown];
  static const coverValues = ['yes', 'no', kUnknown];
  static const occupancyValues = [kEggFilled, kUnknown];

  /// Grid limits and the size limit of the upload field.
  static const minSide = 1;
  static const maxSide = 40;
  static const maxEncodedLength = 4000;

  /// Columns on the front face (x, left to right) and rows front to back (y).
  final int x;
  final int y;
  final String interior;

  /// `[x, y]` cells the operator knows are empty floor.
  final List<List<int>> missingCells;
  final List<PartialStack> partialStacks;
  final String coverTrays;

  /// `egg_filled`: every counted tray holds eggs (the server then reports the
  /// eligible egg trays with the basis `declared`); otherwise unknown.
  final String occupancy;

  /// Layers in a full stack. The server ignores it unless
  /// [referenceHeightMeasured]; it can only demote a result.
  final int? referenceHeight;
  final bool referenceHeightMeasured;
  final String operator;
  final DateTime declaredAt;

  /// Server answer only: whether the measured faces agree with this
  /// declaration (null when the server could not tell).
  final bool? agreesWithFaces;

  bool isMissing(int cx, int cy) =>
      missingCells.any((c) => c.length == 2 && c[0] == cx && c[1] == cy);

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'interior': interior,
    'missing_cells': [
      for (final c in missingCells) [c[0], c[1]],
    ],
    'partial_stacks': [for (final p in partialStacks) p.toJson()],
    'cover_trays': coverTrays,
    'occupancy': occupancy,
    'reference_height': referenceHeight,
    'reference_height_measured': referenceHeightMeasured,
    'operator': operator,
    'declared_at': isoSeconds(declaredAt),
  };

  /// The upload field; null when it would exceed the contract's limit (the
  /// pane refuses such a declaration, so this only guards older sessions).
  String? encode() {
    final text = jsonEncode(toJson());
    return text.length <= maxEncodedLength ? text : null;
  }

  /// UTC, second precision, as in the contract example.
  static String isoSeconds(DateTime time) =>
      '${time.toUtc().toIso8601String().substring(0, 19)}Z';

  static String _oneOf(Object? value, List<String> allowed) =>
      value is String && allowed.contains(value) ? value : kUnknown;

  /// Reads a declaration back (the pending-scan copy, or `block.declaration`
  /// from the server); null when it has no usable grid size.
  static BlockDeclaration? fromJson(Object? json) {
    if (json is! Map) return null;
    final x = json['x'], y = json['y'];
    if (x is! int || y is! int) return null;
    final height = json['reference_height'];
    return BlockDeclaration(
      x: x,
      y: y,
      interior: _oneOf(json['interior'], interiorValues),
      missingCells: [
        for (final c in (json['missing_cells'] as List<dynamic>? ?? const []))
          if (c is List && c.length == 2 && c[0] is int && c[1] is int)
            [c[0] as int, c[1] as int],
      ],
      partialStacks: [
        for (final p in (json['partial_stacks'] as List<dynamic>? ?? const []))
          ?PartialStack.fromJson(p),
      ],
      coverTrays: _oneOf(json['cover_trays'], coverValues),
      occupancy: _oneOf(json['occupancy'], occupancyValues),
      referenceHeight: height is num ? height.round() : null,
      referenceHeightMeasured: json['reference_height_measured'] == true,
      operator: json['operator'] as String? ?? '',
      declaredAt:
          DateTime.tryParse(json['declared_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      agreesWithFaces: json['agrees_with_faces'] as bool?,
    );
  }
}
