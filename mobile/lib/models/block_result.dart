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
  });

  final int x;
  final int y;
  final String status;
  final int? layers;
  final String? source;

  factory BlockCell.fromJson(Map<String, dynamic> json) => BlockCell(
    x: json['x'] as int,
    y: json['y'] as int,
    status: json['status'] as String,
    layers: json['layers'] as int?,
    source: json['source'] as String?,
  );
}

class BlockResult {
  const BlockResult({
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
  });

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

  bool get hasGrid =>
      width != null && depth != null && width! > 0 && depth! > 0 && cells.isNotEmpty;

  factory BlockResult.fromJson(Map<String, dynamic> json) => BlockResult(
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
    conflicts: (json['conflicts'] as List<dynamic>? ?? const [])
        .map((c) {
          final m = c as Map<String, dynamic>;
          final reason = m['reason']?.toString() ?? 'faces disagree';
          final extras = m.entries
              .where((e) => e.key != 'reason')
              .map((e) => '${e.key}=${e.value}')
              .join(', ');
          return extras.isEmpty ? reason : '$reason ($extras)';
        })
        .toList(growable: false),
    rescanCells: (json['rescan_cells'] as List<dynamic>? ?? const [])
        .map((c) => (c as List<dynamic>).map((v) => v as int).toList())
        .toList(growable: false),
    note: json['note'] as String? ?? '',
  );
}
