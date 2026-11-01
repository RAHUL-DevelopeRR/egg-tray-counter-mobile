import 'block_declaration.dart';

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
    this.verified,
  });

  final int x;
  final int y;
  final String status;
  final int? layers;
  final String? source;

  /// Layers counted between detected boxes (no box of their own).
  final int filledLayers;

  /// Read the same by two photos (Worker 0.4.14); null from older servers.
  final bool? verified;

  factory BlockCell.fromJson(Map<String, dynamic> json) => BlockCell(
    x: json['x'] as int,
    y: json['y'] as int,
    status: json['status'] as String,
    layers: json['layers'] as int?,
    source: json['source'] as String?,
    filledLayers: json['filled_layers'] as int? ?? 0,
    verified: json['verified'] as bool?,
  );
}

/// One count of one stack by one reader (Worker 0.5.0 `grid[][].readings`).
class GridReading {
  const GridReading({
    this.captureId,
    this.reader,
    this.physicalStackId,
    this.view,
    this.count,
    this.evidence = const {},
    this.quality,
    this.trusted,
    this.pipelineVersion,
  });

  final String? captureId;
  final String? reader;
  final String? physicalStackId;
  final String? view;
  final int? count;
  final Map<String, dynamic> evidence;

  /// `accepted` or `refused`.
  final String? quality;
  final bool? trusted;
  final String? pipelineVersion;

  factory GridReading.fromJson(Map<String, dynamic> json) => GridReading(
    captureId: json['capture_id'] as String?,
    reader: json['reader'] as String?,
    physicalStackId: json['physical_stack_id'] as String?,
    view: json['view'] as String?,
    count: _int(json['count']),
    evidence: json['evidence'] is Map<String, dynamic>
        ? json['evidence'] as Map<String, dynamic>
        : const {},
    quality: json['quality'] as String?,
    trusted: json['trusted'] as bool?,
    pipelineVersion: json['pipeline_version'] as String?,
  );
}

/// One physical stack of the grid model (Worker 0.5.0 `block.grid`). A shared
/// corner is one stack: a second face is another observation, never more
/// inventory. `stack_present` is null when unknown.
class GridCell {
  const GridCell({
    required this.x,
    required this.y,
    required this.status,
    this.physicalStackId,
    this.stackPresent,
    this.zLayers,
    this.filledLayers,
    this.partialLayers,
    this.emptyCoverLayers,
    this.unknownLayers,
    this.observedViews = const [],
    this.measurementSources = const [],
    this.uncertainties = const [],
    this.readings = const [],
    this.pairType,
  });

  final int x;
  final int y;

  /// verified, observed, computed, declared, top_view, missing, conflict,
  /// rescan or unknown.
  final String status;
  final String? physicalStackId;
  final bool? stackPresent;

  /// Physical layers in the stack; null when unknown.
  final int? zLayers;
  final int? filledLayers;
  final int? partialLayers;
  final int? emptyCoverLayers;
  final int? unknownLayers;
  final List<String> observedViews;

  /// observed, declared, computed, top_view.
  final List<String> measurementSources;
  final List<String> uncertainties;
  final List<GridReading> readings;

  /// `cross_photo`, `same_photo_reader` or null.
  final String? pairType;

  factory GridCell.fromJson(Map<String, dynamic> json, {int? x, int? y}) =>
      GridCell(
        x: _int(json['x']) ?? x ?? 0,
        y: _int(json['y']) ?? y ?? 0,
        status: json['status'] as String? ?? 'unknown',
        physicalStackId: json['physical_stack_id'] as String?,
        stackPresent: json['stack_present'] as bool?,
        zLayers: _int(json['z_layers']),
        filledLayers: _int(json['filled_layers']),
        partialLayers: _int(json['partial_layers']),
        emptyCoverLayers: _int(json['empty_cover_layers']),
        unknownLayers: _int(json['unknown_layers']),
        observedViews: _strings(json['observed_views']),
        measurementSources: _strings(json['measurement_sources']),
        uncertainties: _strings(json['uncertainties']),
        readings: [
          for (final r in (json['readings'] as List<dynamic>? ?? const []))
            if (r is Map<String, dynamic>) GridReading.fromJson(r),
        ],
        pairType: json['pair_type'] as String?,
      );

  /// The same stack as an older [BlockCell], for screens that list stacks.
  BlockCell toBlockCell() =>
      BlockCell(x: x, y: y, status: status, layers: zLayers);
}

/// One inventory figure and what it rests on: `measured`, `declared` or
/// `unknown`, never mixed.
class InventoryValue {
  const InventoryValue({required this.value, required this.basis, this.note});

  final int? value;
  final String basis;
  final String? note;

  static InventoryValue? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return InventoryValue(
      value: _int(json['value']),
      basis: json['basis'] as String? ?? 'unknown',
      note: json['note'] as String?,
    );
  }
}

/// The block's inventory with photo, computed, declared and unknown kept
/// apart (Worker 0.5.0 `block.inventory`).
class BlockInventory {
  const BlockInventory({
    this.physicalLayersObserved,
    this.physicalLayersComputed,
    this.physicalLayersDeclared,
    this.eligibleEggTrays,
    this.emptyCoverLayers,
    this.unknownOccupancyLayers,
    this.unknownCells,
  });

  final int? physicalLayersObserved;
  final int? physicalLayersComputed;
  final int? physicalLayersDeclared;

  /// Trays holding eggs (a partly filled tray is one; an empty cover tray is
  /// never one). Its basis says whether occupancy was measured or declared.
  final InventoryValue? eligibleEggTrays;
  final InventoryValue? emptyCoverLayers;
  final int? unknownOccupancyLayers;
  final int? unknownCells;

  static BlockInventory? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return BlockInventory(
      physicalLayersObserved: _int(json['physical_layers_observed']),
      physicalLayersComputed: _int(json['physical_layers_computed']),
      physicalLayersDeclared: _int(json['physical_layers_declared']),
      eligibleEggTrays: InventoryValue.fromJson(json['eligible_egg_trays']),
      emptyCoverLayers: InventoryValue.fromJson(json['empty_cover_layers']),
      unknownOccupancyLayers: _int(json['unknown_occupancy_layers']),
      unknownCells: _int(json['unknown_cells']),
    );
  }
}

/// What the CORNER photo read: the corner, the block size seen from it, and
/// whether that agrees with the faces.
class CornerReading {
  const CornerReading({this.side, this.x, this.y, this.agrees});

  final String? side;
  final int? x;
  final int? y;
  final bool? agrees;

  static CornerReading? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return CornerReading(
      side: json['side'] as String?,
      x: _int(json['x']),
      y: _int(json['y']),
      agrees: json['agrees'] as bool?,
    );
  }
}

/// What the ELEVATED photo (with the operator's taps) said about the top.
/// The cell figures are counts; a server that sends cell lists is read as
/// their lengths.
class TopViewReading {
  const TopViewReading({
    this.cellsPresent,
    this.cellsMissing,
    this.steps,
    this.agrees,
  });

  final int? cellsPresent;
  final int? cellsMissing;
  final int? steps;
  final bool? agrees;

  static TopViewReading? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return TopViewReading(
      cellsPresent: _count(json['cells_present']),
      cellsMissing: _count(json['cells_missing']),
      steps: _count(json['steps']),
      agrees: json['agrees'] as bool?,
    );
  }
}

int? _int(Object? value) => value is num ? value.round() : null;

int? _count(Object? value) => value is List ? value.length : _int(value);

List<String> _strings(Object? value) => value is List
    ? value.map((v) => v.toString()).toList(growable: false)
    : const [];

/// The block's one result state; the result icon, headline and history all
/// use it. `exact`: every stack seen and read the same by two photos.
/// `confirmed`: every visible stack verified, the declaration agrees with
/// every measured face, and the interior is declared full or supported by
/// the top view; it always names its basis and is never called exact.
/// `estimated`: a total exists, but hidden stacks are computed, a stack was
/// read by one photo only, or two faces differ by one layer. `conflict`: no total, retake the named face. `needs_view`: a photo
/// is missing or was refused.
const kBlockExact = 'exact';
const kBlockConfirmed = 'confirmed';
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
    this.visibleVerifiedTrays,
    this.visibleSingleReadingTrays,
    this.grid = const [],
    this.inventory,
    this.declaration,
    this.corner,
    this.topView,
    this.suggestedViews = const [],
    this.confirmedBasis = const [],
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

  /// Seen trays split by how they were read (Worker 0.4.14): by two photos
  /// that agree, or by one photo only. Null from older servers.
  final int? visibleVerifiedTrays;
  final int? visibleSingleReadingTrays;

  /// The grid model (Worker 0.5.0), flattened row by row; empty from older
  /// servers, which send only [cells].
  final List<GridCell> grid;
  final BlockInventory? inventory;

  /// The declaration as the server stored it, with `agrees_with_faces`.
  final BlockDeclaration? declaration;
  final CornerReading? corner;
  final TopViewReading? topView;

  /// Extra views that would resolve the block, for example `elevated`.
  final List<String> suggestedViews;

  /// What a `confirmed` status rests on: `declaration`, `top_view`.
  final List<String> confirmedBasis;

  bool get hasGrid =>
      width != null && depth != null && width! > 0 && depth! > 0 && cells.isNotEmpty;

  bool get hasGridModel => grid.isNotEmpty;

  /// Grid size: the server's width and depth, else what the grid spans.
  int get gridWidth =>
      grid.fold<int>(width ?? 0, (m, c) => c.x + 1 > m ? c.x + 1 : m);
  int get gridDepth =>
      grid.fold<int>(depth ?? 0, (m, c) => c.y + 1 > m ? c.y + 1 : m);

  /// One entry per stack for screens that list stacks (the manual count):
  /// the older cells, or the grid model's when a server sends only that.
  List<BlockCell> get stackCells =>
      cells.isNotEmpty ? cells : [for (final g in grid) g.toBlockCell()];

  /// `grid` is an array of rows (y from 0), each an array of cells (x from
  /// 0); a cell's own x and y win over its position.
  static List<GridCell> _grid(Object? rows) {
    if (rows is! List) return const [];
    return [
      for (var y = 0; y < rows.length; y++)
        if (rows[y] case final List row)
          for (var x = 0; x < row.length; x++)
            if (row[x] case final Map<String, dynamic> cell)
              GridCell.fromJson(cell, x: x, y: y),
    ];
  }

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
    visibleVerifiedTrays: json['visible_verified_trays'] as int?,
    visibleSingleReadingTrays: json['visible_single_reading_trays'] as int?,
    grid: _grid(json['grid']),
    inventory: BlockInventory.fromJson(json['inventory']),
    declaration: BlockDeclaration.fromJson(json['declaration']),
    corner: CornerReading.fromJson(json['corner']),
    topView: TopViewReading.fromJson(json['top_view']),
    suggestedViews: _strings(json['suggested_views']),
    confirmedBasis: _strings(json['confirmed_basis']),
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
