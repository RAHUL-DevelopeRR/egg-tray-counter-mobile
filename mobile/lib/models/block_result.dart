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

/// A measured cell the server used to assume a hidden stack's height (Worker
/// 0.6.0 `grid[][].neighbours`).
class GridNeighbour {
  const GridNeighbour({required this.x, required this.y, this.layers});

  final int x;
  final int y;
  final int? layers;

  static GridNeighbour? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final x = _int(json['x']);
    final y = _int(json['y']);
    if (x == null || y == null) return null;
    return GridNeighbour(x: x, y: y, layers: _int(json['layers']));
  }
}

/// One physical stack of the grid model (Worker 0.5.0 `block.grid`). A shared
/// corner is one stack: a second face is another observation, never more
/// inventory. `stack_present` is null when unknown.
///
/// Worker 0.6.0 adds the evidence class and, on a hidden stack, how its
/// height was assumed; older servers leave those fields empty and the app
/// works the class out ([evidenceClassOf]).
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
    this.evidenceClass,
    this.hidden,
    this.assumedLayers,
    this.assumedRange,
    this.assumedFrom,
    this.neighbours = const [],
    this.topTap,
    this.flags = const [],
    this.pastGapLayers,
    this.pastGapScale,
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

  /// The server's evidence class as sent (Worker 0.6.0), null from older
  /// servers; [evidenceClassOf] reads it.
  final String? evidenceClass;

  /// True when no face reading counts the stack (0.6.0).
  final bool? hidden;

  /// A present hidden stack's assumed height; null when unknown.
  final int? assumedLayers;

  /// The spread of the neighbours' heights, `[low, high]`, not a bound on the
  /// truth; `high` is null after a step up (open above).
  final List<int?>? assumedRange;

  /// `neighbours`, `face_typical` or `declared_partial`.
  final String? assumedFrom;
  final List<GridNeighbour> neighbours;

  /// The operator's top-view tap: present, missing, step_up, step_down or
  /// unsure.
  final String? topTap;

  /// single_neighbour, no_neighbour, step_up_count_unknown, single_reading,
  /// line_of_sight_past_gap and others.
  final List<String> flags;

  /// Trays seen through a gap in front of this stack: a hint, never counted.
  final int? pastGapLayers;
  final double? pastGapScale;

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
        evidenceClass: json['evidence_class'] as String?,
        hidden: json['hidden'] as bool?,
        assumedLayers: _int(json['assumed_layers']),
        assumedRange: _range(json['assumed_range']),
        assumedFrom: json['assumed_from'] as String?,
        neighbours: [
          for (final n in (json['neighbours'] as List<dynamic>? ?? const []))
            ?GridNeighbour.fromJson(n),
        ],
        topTap: json['top_tap'] as String?,
        flags: _strings(json['flags']),
        pastGapLayers: _int(json['past_gap_layers']),
        pastGapScale: (json['past_gap_scale'] as num?)?.toDouble(),
      );

  /// The same stack as an older [BlockCell], for screens that list stacks.
  BlockCell toBlockCell() =>
      BlockCell(x: x, y: y, status: status, layers: zLayers);
}

/// What a stack's height rests on (Worker 0.6.0 `evidence_class`). Only
/// [measured] is a count: read top to floor on a photographed face. A hidden
/// stack is [assumed] at its neighbours' face height; a top-view tap says only
/// that it is there ([topPresent]), taller or shorter ([topStep]) or absent
/// ([topMissing]), and never counts it.
enum EvidenceClass {
  measured('measured'),
  seenEmpty('seen_empty'),
  topPresent('top_present'),
  topStep('top_step'),
  topMissing('top_missing'),
  declaredMissing('declared_missing'),
  assumed('assumed'),
  conflict('conflict');

  const EvidenceClass(this.wire);

  /// The name in the server's JSON.
  final String wire;

  static EvidenceClass? fromWire(Object? value) {
    for (final c in values) {
      if (c.wire == value) return c;
    }
    return null;
  }

  /// Trays read on a face: the only count.
  bool get counted => this == measured;

  /// A stack taken to be there whose height is assumed, not counted.
  bool get assumedHeight =>
      this == assumed || this == topPresent || this == topStep;

  /// Known to hold no stack.
  bool get empty =>
      this == seenEmpty || this == topMissing || this == declaredMissing;
}

/// One stack's evidence as the app draws and adds it up: the server's class
/// (0.6.0), or the class worked out from an older response ([derived]).
class CellEvidence {
  const CellEvidence({
    required this.x,
    required this.y,
    required this.evidenceClass,
    this.layers,
    this.range,
    this.flags = const [],
    this.hidden = false,
    this.topTap,
    this.assumedFrom,
    this.neighbours = const [],
    this.derived = false,
  });

  final int x;
  final int y;
  final EvidenceClass evidenceClass;

  /// The counted height of a measured stack, the assumed height of a hidden
  /// one, 0 for no stack; null when unknown.
  final int? layers;

  /// The assumed range `[low, high]`; `high` null is open above.
  final List<int?>? range;
  final List<String> flags;
  final bool hidden;
  final String? topTap;
  final String? assumedFrom;
  final List<GridNeighbour> neighbours;

  /// Worked out by the app from an older server's status.
  final bool derived;

  bool get singleReading => flags.contains('single_reading');

  bool get stepDown =>
      evidenceClass == EvidenceClass.topStep &&
      (topTap == 'step_down' || flags.contains('step_down_count_unknown'));

  bool get stepUp => evidenceClass == EvidenceClass.topStep && !stepDown;
}

/// The evidence class of [cell]: the server's when it sends one, else worked
/// out from an older status (Worker 0.4.x and 0.5.x). [legacySource] is the
/// older `cells[]` source at the same (x, y): a stack whose every reading was
/// taken looking through a gap (`straight-recessed`) is not counted.
CellEvidence evidenceClassOf(GridCell cell, {String? legacySource}) {
  final server = EvidenceClass.fromWire(cell.evidenceClass);
  if (server != null) {
    return CellEvidence(
      x: cell.x,
      y: cell.y,
      evidenceClass: server,
      layers: server.empty
          ? 0
          : server.assumedHeight
          ? cell.assumedLayers ?? cell.zLayers
          : cell.zLayers,
      range: cell.assumedRange,
      flags: cell.flags,
      hidden:
          cell.hidden ??
          !(server == EvidenceClass.measured ||
              server == EvidenceClass.seenEmpty),
      topTap: cell.topTap,
      assumedFrom: cell.assumedFrom,
      neighbours: cell.neighbours,
    );
  }
  return _derive(
    x: cell.x,
    y: cell.y,
    status: cell.status,
    layers: cell.zLayers,
    stackPresent: cell.stackPresent,
    sources: cell.measurementSources,
    legacySource: legacySource,
    singleReading: cell.status == 'observed',
  );
}

/// The evidence class of an older (0.4.x) stack, by the same rules.
CellEvidence evidenceClassOfBlockCell(BlockCell cell) => _derive(
  x: cell.x,
  y: cell.y,
  status: cell.status,
  layers: cell.layers,
  stackPresent: cell.status == 'missing' ? false : null,
  sources: const [],
  legacySource: cell.source,
  singleReading: cell.verified != true,
);

CellEvidence _derive({
  required int x,
  required int y,
  required String status,
  required int? layers,
  required bool? stackPresent,
  required List<String> sources,
  required String? legacySource,
  required bool singleReading,
}) {
  final throughGap =
      legacySource != null &&
      legacySource.isNotEmpty &&
      legacySource.split('+').every((part) => part.endsWith('-recessed'));
  var (cls, tap, from) = switch (status) {
    'verified' => (EvidenceClass.measured, null, null),
    // Trays seen behind a gap are another reading's line of sight, never a
    // count of this stack.
    'observed' when throughGap => (EvidenceClass.assumed, null, null),
    'observed' => (EvidenceClass.measured, null, null),
    'missing' => (EvidenceClass.seenEmpty, null, null),
    'computed' => (EvidenceClass.assumed, null, 'face_typical'),
    'top_view' when stackPresent == false => (
      EvidenceClass.topMissing,
      'missing',
      null,
    ),
    'top_view' => (EvidenceClass.topPresent, 'present', 'face_typical'),
    'declared' when stackPresent == false => (
      EvidenceClass.declaredMissing,
      null,
      null,
    ),
    'declared' => (EvidenceClass.assumed, null, 'declared'),
    'unknown' when sources.length == 1 && sources.first == 'top_view' => (
      EvidenceClass.topStep,
      'step_down',
      null,
    ),
    'conflict' || 'rescan' => (EvidenceClass.conflict, null, null),
    // unknown, or a status this app does not know: never a count.
    _ => (EvidenceClass.assumed, null, 'face_typical'),
  };
  // A stack known to be absent is drawn and added as no stack, whatever its
  // status says.
  if (stackPresent == false && cls.assumedHeight) {
    cls = sources.contains('top_view')
        ? EvidenceClass.topMissing
        : sources.contains('declared')
        ? EvidenceClass.declaredMissing
        : EvidenceClass.seenEmpty;
    from = null;
  }
  final measured = cls == EvidenceClass.measured;
  return CellEvidence(
    x: x,
    y: y,
    evidenceClass: cls,
    layers: cls.empty ? 0 : layers,
    flags: [
      if (measured && singleReading) 'single_reading',
      if (throughGap && status == 'observed') 'line_of_sight_past_gap',
    ],
    hidden: !(measured || cls == EvidenceClass.seenEmpty) &&
        cls != EvidenceClass.conflict,
    topTap: tap,
    assumedFrom: from,
    derived: true,
  );
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

/// What a withheld block would hold if the operator's size were right
/// (Worker 0.6.0 `provisional.if_depth`). Never a total.
class ProvisionalDepth {
  const ProvisionalDepth({
    this.y,
    this.countedTrays,
    this.assumedTrays,
    this.assumedStacks,
    this.estimatedTotal,
  });

  final int? y;
  final int? countedTrays;
  final int? assumedTrays;
  final int? assumedStacks;
  final int? estimatedTotal;

  static ProvisionalDepth? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return ProvisionalDepth(
      y: _int(json['y']),
      countedTrays: _int(json['counted_trays']),
      assumedTrays: _int(json['assumed_trays']),
      assumedStacks: _int(json['assumed_stacks']),
      estimatedTotal: _int(json['estimated_total']),
    );
  }
}

/// Figures for a block whose depth is not proven (Worker 0.6.0
/// `provisional`): the front row counted, and what the block would hold at
/// the depth the sides read. Not released: never a headline, a history total,
/// an export or the manual count's app total.
class ProvisionalFigures {
  const ProvisionalFigures({
    this.kind,
    this.reason,
    this.frontRowCounted,
    this.ifDepth,
  });

  /// `depth_unproven` or `side_repeats_front`.
  final String? kind;
  final String? reason;
  final int? frontRowCounted;
  final ProvisionalDepth? ifDepth;

  static ProvisionalFigures? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return ProvisionalFigures(
      kind: json['kind'] as String?,
      reason: json['reason'] as String?,
      frontRowCounted: _int(json['front_row_counted']),
      ifDepth: ProvisionalDepth.fromJson(json['if_depth']),
    );
  }
}

/// The block's inventory with photo, computed, declared and unknown kept
/// apart (Worker 0.5.0 `block.inventory`).
///
/// Worker 0.6.0 adds counted (read on faces) and assumed (hidden stacks at
/// their neighbours' height) trays, kept apart, all in tray layers. The new
/// numbers are null unless the block is `exact` or `estimated`.
class BlockInventory {
  const BlockInventory({
    this.physicalLayersObserved,
    this.physicalLayersComputed,
    this.physicalLayersDeclared,
    this.eligibleEggTrays,
    this.emptyCoverLayers,
    this.unknownOccupancyLayers,
    this.unknownCells,
    this.unit,
    this.released,
    this.withheldReason,
    this.provisional,
    this.countedTrays,
    this.countedStacks,
    this.assumedTrays,
    this.assumedRange,
    this.assumedStacks,
    this.estimatedTotal,
    this.estimatedRange,
    this.hiddenStacks,
    this.hiddenStacksTopChecked,
    this.uncheckedHiddenStacks,
    this.missingStacks = const {},
    this.coverTrays,
    this.note,
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

  /// `tray_layers`.
  final String? unit;

  /// Whether the block has a total; null from older servers.
  final bool? released;

  /// height_unknown, conflict, needs_view, depth_unproven or
  /// side_repeats_front.
  final String? withheldReason;
  final ProvisionalFigures? provisional;

  /// Read top to floor on photographed faces: the only floor of the truth.
  final int? countedTrays;
  final int? countedStacks;

  /// Hidden stacks at their neighbours' height: not counted.
  final int? assumedTrays;

  /// `[low, high]`, `high` null when a step up leaves the top open.
  final List<int?>? assumedRange;
  final int? assumedStacks;

  /// counted + assumed.
  final int? estimatedTotal;

  /// "If every hidden stack is there at its neighbours' heights": never a
  /// bound, because it ignores holes.
  final List<int?>? estimatedRange;
  final int? hiddenStacks;
  final int? hiddenStacksTopChecked;
  final int? uncheckedHiddenStacks;

  /// Stacks known to be absent, by how: seen_empty, top_missing,
  /// declared_missing.
  final Map<String, int> missingStacks;
  final InventoryValue? coverTrays;
  final String? note;

  static BlockInventory? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final missing = json['missing_stacks'];
    return BlockInventory(
      physicalLayersObserved: _int(json['physical_layers_observed']),
      physicalLayersComputed: _int(json['physical_layers_computed']),
      physicalLayersDeclared: _int(json['physical_layers_declared']),
      eligibleEggTrays: InventoryValue.fromJson(json['eligible_egg_trays']),
      emptyCoverLayers: InventoryValue.fromJson(json['empty_cover_layers']),
      unknownOccupancyLayers: _int(json['unknown_occupancy_layers']),
      unknownCells: _int(json['unknown_cells']),
      unit: json['unit'] as String?,
      released: json['released'] as bool?,
      withheldReason: json['withheld_reason'] as String?,
      provisional: ProvisionalFigures.fromJson(json['provisional']),
      countedTrays: _int(json['counted_trays']),
      countedStacks: _int(json['counted_stacks']),
      assumedTrays: _int(json['assumed_trays']),
      assumedRange: _range(json['assumed_range']),
      assumedStacks: _int(json['assumed_stacks']),
      estimatedTotal: _int(json['estimated_total']),
      estimatedRange: _range(json['estimated_range']),
      hiddenStacks: _int(json['hidden_stacks']),
      hiddenStacksTopChecked: _int(json['hidden_stacks_top_checked']),
      uncheckedHiddenStacks: _int(json['unchecked_hidden_stacks']),
      missingStacks: missing is Map<String, dynamic>
          ? {
              for (final e in missing.entries) e.key: ?_int(e.value),
            }
          : const {},
      coverTrays: InventoryValue.fromJson(json['cover_trays']),
      note: json['note'] as String?,
    );
  }
}

/// The block's tray layers split into counted (read on faces) and assumed
/// (hidden stacks), from the server's 0.6.0 inventory or worked out from an
/// older response's stacks. Counted is the only floor of the truth; there is
/// no ceiling, and the range is "if every hidden stack is there at its
/// neighbours' heights", never a bound.
class TraySplit {
  const TraySplit({
    required this.counted,
    required this.assumed,
    required this.estimated,
    this.assumedStacks,
    this.hiddenStacks,
    this.topChecked,
    this.unchecked,
    this.stepUps = 0,
    this.assumedRange,
    this.estimatedRange,
    this.assumedFrom = const {},
    this.fromServer = false,
  });

  final int counted;

  /// Null when a present hidden stack's height is unknown.
  final int? assumed;

  /// counted + assumed; null when the total is withheld.
  final int? estimated;
  final int? assumedStacks;
  final int? hiddenStacks;

  /// Hidden stacks tapped from the top (present, missing or a step).
  final int? topChecked;

  /// Present hidden stacks with no top tap.
  final int? unchecked;

  /// Hidden stacks tapped taller than their neighbours: open above.
  final int stepUps;
  final List<int?>? assumedRange;
  final List<int?>? estimatedRange;

  /// Where the assumed heights came from: neighbours, face_typical,
  /// declared_partial or declared.
  final Set<String> assumedFrom;

  /// The server's 0.6.0 numbers, not the app's.
  final bool fromServer;

  bool get released => estimated != null;
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

/// `[low, high]` with `high` possibly null (open); anything else is null.
List<int?>? _range(Object? value) {
  if (value is! List || value.length != 2) return null;
  final low = _int(value[0]);
  if (low == null) return null;
  return [low, _int(value[1])];
}

List<String> _strings(Object? value) => value is List
    ? value.map((v) => v.toString()).toList(growable: false)
    : const [];

/// The block's one result state; the result icon, headline and history all
/// use it. `exact`: every stack seen and read the same by two photos.
/// `estimated`: a total exists, but hidden stacks are assumed, a stack was
/// read by one photo only, or two faces differ by one layer. `conflict`: no
/// total, retake the named face. `needs_view`: a photo is missing or was
/// refused, or the depth is not proven.
///
/// `confirmed` came only from 0.5 servers (an interior declared or seen from
/// above). Worker 0.6.0 never sends it: hidden stacks are assumed, so such a
/// block is shown as an estimate.
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
    this.depthBasis,
    this.gridContract,
    this.suggestedInputs = const [],
    this.provisionalFigures,
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

  /// What a `confirmed` status rests on: `declaration`, `top_view`. Always
  /// empty from Worker 0.6.0.
  final List<String> confirmedBasis;

  /// What the depth rests on (0.6.0): `one_deep`, `declaration`,
  /// `corner_and_declaration`, or null.
  final String? depthBasis;

  /// `0.6.0` from Worker 0.6.0; null from older servers.
  final String? gridContract;

  /// Inputs that would release the block, for example `declaration`.
  final List<String> suggestedInputs;

  /// The block-level `provisional` object, when a server sends it there and
  /// not in the inventory; read [provisional].
  final ProvisionalFigures? provisionalFigures;

  /// Figures for a block whose depth is not proven: never a total.
  ProvisionalFigures? get provisional =>
      inventory?.provisional ?? provisionalFigures;

  /// Whether the block has a total.
  bool get released => inventory?.released ?? totalTrays != null;

  /// The status to show: `exact` only when nothing in the total is assumed.
  /// An older server could call a block exact while a stack was read only
  /// through a gap, which the app does not count.
  String get displayStatus {
    if (status != kBlockExact) return status;
    final assumed = split?.assumed;
    return assumed == null || assumed > 0 ? kBlockEstimated : status;
  }

  /// Why the total is withheld (0.6.0), null from older servers.
  String? get withheldReason => inventory?.withheldReason;

  /// Every stack with its evidence class: the grid model's, else the older
  /// cells'. Empty when the server sent neither.
  List<CellEvidence> get evidence {
    if (grid.isNotEmpty) {
      final sources = {for (final c in cells) (c.x, c.y): c.source};
      return [
        for (final g in grid)
          evidenceClassOf(g, legacySource: sources[(g.x, g.y)]),
      ];
    }
    return [for (final c in cells) evidenceClassOfBlockCell(c)];
  }

  /// Counted and assumed trays kept apart, with the estimate they add up to.
  /// From the 0.6.0 inventory when the server sends it; for older servers
  /// worked out from the stacks' evidence classes (not `computed_trays`,
  /// which 0.5 kept after a stack was tapped missing). Null when the block
  /// has no counted figure (conflict, needs_view, a withheld 0.6.0 block).
  TraySplit? get split {
    final inv = inventory;
    if (inv?.countedTrays case final counted?) {
      final assumedFrom = {
        for (final e in evidence)
          if (e.evidenceClass.assumedHeight) ?e.assumedFrom,
      };
      return TraySplit(
        counted: counted,
        assumed: inv!.assumedTrays,
        estimated: inv.estimatedTotal ?? (inv.released == false ? null : totalTrays),
        assumedStacks: inv.assumedStacks,
        hiddenStacks: inv.hiddenStacks,
        topChecked: inv.hiddenStacksTopChecked,
        unchecked: inv.uncheckedHiddenStacks,
        stepUps: evidence.where((e) => e.stepUp).length,
        assumedRange: inv.assumedRange,
        estimatedRange: inv.estimatedRange,
        assumedFrom: assumedFrom,
        fromServer: true,
      );
    }
    // A 0.6.0 server sends no counted figure for a block it withholds.
    if (gridContract != null) return null;
    if (status != kBlockExact &&
        status != kBlockEstimated &&
        status != kBlockConfirmed) {
      return null;
    }
    final stacks = evidence;
    if (stacks.isNotEmpty) {
      var counted = 0;
      int? assumed = 0;
      var assumedStacks = 0;
      var hidden = 0;
      var checked = 0;
      var unchecked = 0;
      final from = <String>{};
      for (final e in stacks) {
        final cls = e.evidenceClass;
        if (cls.counted) counted += e.layers ?? 0;
        if (e.hidden) hidden++;
        if (e.hidden && e.topTap != null && e.topTap != 'unsure') checked++;
        if (!cls.assumedHeight) continue;
        assumedStacks++;
        if (e.topTap == null || e.topTap == 'unsure') unchecked++;
        if (e.assumedFrom case final f?) from.add(f);
        final layers = e.layers;
        assumed = layers == null || assumed == null ? null : assumed + layers;
      }
      final total = totalTrays;
      bool addsUp(int? a, int? b) => a != null && b != null && a + b == total;
      // The stacks when they add up to the server's total; otherwise the
      // server's own split when that does (a cells list that does not cover
      // every stack); a grid whose stacks and totals both disagree keeps
      // the stacks.
      if (total == null ||
          addsUp(counted, assumed) ||
          (grid.isNotEmpty && !addsUp(observedTrays, computedTrays))) {
        return TraySplit(
          counted: counted,
          assumed: assumed,
          estimated: total,
          assumedStacks: assumedStacks,
          hiddenStacks: hidden,
          topChecked: checked,
          unchecked: unchecked,
          stepUps: stacks.where((e) => e.stepUp).length,
          assumedFrom: from,
        );
      }
    }
    return TraySplit(
      counted: observedTrays,
      assumed: computedTrays,
      estimated: totalTrays,
      assumedFrom: computedTrays > 0 ? const {'face_typical'} : const {},
    );
  }

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
    depthBasis: json['depth_basis'] as String?,
    gridContract: json['grid_contract'] as String?,
    suggestedInputs: _strings(json['suggested_inputs']),
    provisionalFigures: ProvisionalFigures.fromJson(json['provisional']),
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
