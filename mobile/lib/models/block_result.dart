/// Block model returned by the server as `block` (contract block_model_v1).
///
/// STRAIGHT is the X face, LEFT and RIGHT are the Y faces. Each cell is one
/// stack: `observed` was seen on a face, `computed` is the X x Y x height
/// calculation for the interior, `missing` is a gap, `rescan` or `conflict`
/// means the faces disagreed and no total is given.
class BlockCell {
  const BlockCell({
    required this.x,
    required this.y,
    required this.status,
    required this.layers,
    this.source,
    this.filledLayers = 0,
  });

  final int x;
  final int y;
  final String status;
  final int? layers;
  final String? source;

  /// Layers counted between detected boxes (no box of their own).
  final int filledLayers;

  factory BlockCell.fromJson(Map<String, dynamic> json) => BlockCell(
    x: json['x'] as int,
    y: json['y'] as int,
    status: json['status'] as String,
    layers: json['layers'] as int?,
    source: json['source'] as String?,
    filledLayers: json['filled_layers'] as int? ?? 0,
  );
}

/// The block's one result state; the result icon, headline and history all
/// use it. `exact`: every stack seen and the faces agree. `estimated`: a
/// total exists but hidden stacks are computed or two faces differ by one
/// layer. `conflict`: no total, retake the named face. `needs_view`: a photo
/// is missing or was refused.
const kBlockExact = 'exact';
const kBlockEstimated = 'estimated';

class BlockResult {
  const BlockResult({
    required this.status,
    required this.width,
    required this.depth,
    required this.cells,
    required this.observedTrays,
    required this.computedTrays,
    required this.totalTrays,
    required this.totalEggs,
    required this.facesConsistent,
    required this.fullyObserved,
    required this.facesUsed,
    required this.conflicts,
    required this.rescanCells,
    required this.note,
    this.filledTrays = 0,
    this.ambiguities = const [],
    this.eggsBasis,
  });

  final String status;
  final int? width;
  final int? depth;
  final List<BlockCell> cells;
  final int observedTrays;
  final int computedTrays;
  final int? totalTrays;
  final int? totalEggs;
  final bool facesConsistent;
  final bool fullyObserved;
  final List<String> facesUsed;
  final List<String> conflicts;
  final List<List<int>> rescanCells;
  final String note;
  final int filledTrays;
  final List<String> ambiguities;
  final String? eggsBasis;

  bool get hasGrid =>
      width != null && depth != null && width! > 0 && depth! > 0 && cells.isNotEmpty;

  /// Servers before the result status derive it from the old flags.
  static String _status(Map<String, dynamic> json) {
    final status = json['status'];
    if (status is String) return status;
    if (json['total_trays'] == null) return 'conflict';
    return (json['computed_trays'] as int? ?? 0) > 0 ? kBlockEstimated : kBlockExact;
  }

  factory BlockResult.fromJson(Map<String, dynamic> json) => BlockResult(
    status: _status(json),
    width: json['width'] as int?,
    depth: json['depth'] as int?,
    cells: (json['cells'] as List<dynamic>? ?? const [])
        .map((c) => BlockCell.fromJson(c as Map<String, dynamic>))
        .toList(growable: false),
    observedTrays: json['observed_trays'] as int? ?? 0,
    computedTrays: json['computed_trays'] as int? ?? 0,
    totalTrays: json['total_trays'] as int?,
    totalEggs: json['total_eggs'] as int?,
    facesConsistent: json['faces_consistent'] as bool? ?? false,
    fullyObserved: json['fully_observed'] as bool? ?? false,
    facesUsed: (json['faces_used'] as List<dynamic>? ?? const [])
        .map((f) => f.toString())
        .toList(growable: false),
    conflicts: _describe(json['conflicts'], 'faces disagree'),
    rescanCells: (json['rescan_cells'] as List<dynamic>? ?? const [])
        .map((c) => (c as List<dynamic>).map((v) => v as int).toList())
        .toList(growable: false),
    note: json['note'] as String? ?? '',
    filledTrays: json['filled_trays'] as int? ?? 0,
    ambiguities: _describe(json['ambiguities'], 'faces differ by one layer'),
    eggsBasis: json['eggs_basis'] as String?,
  );

  static List<String> _describe(Object? entries, String fallback) =>
      (entries as List<dynamic>? ?? const [])
          .map((c) {
            final m = c as Map<String, dynamic>;
            final reason = m['reason']?.toString() ?? fallback;
            final extras = m.entries
                .where((e) => e.key != 'reason')
                .map((e) => '${e.key}=${e.value}')
                .join(', ');
            return extras.isEmpty ? reason : '$reason ($extras)';
          })
          .toList(growable: false);
}
