/// Worker 0.6.0 block answers (grid contract 0.6.0), built by hand from the
/// final design's cases: hidden stacks assumed at their neighbours' face
/// height, counted and assumed trays kept apart.
library;

/// One 0.6.0 grid cell. [legacy] is the 0.5 status the server keeps for
/// older apps.
Map<String, dynamic> cell06(
  int x,
  int y,
  String evidenceClass, {
  String legacy = 'verified',
  int? z,
  bool? present = true,
  List<String> sources = const ['observed'],
  bool hidden = false,
  int? assumed,
  List<int?>? range,
  String? from,
  List<List<int>> neighbours = const [],
  String? tap,
  List<String> flags = const [],
  int? pastGapLayers,
  double? pastGapScale,
}) => {
  'physical_stack_id': 'S$x-$y',
  'x': x,
  'y': y,
  'status': legacy,
  'stack_present': present,
  'z_layers': z,
  'filled_layers': null,
  'partial_layers': null,
  'empty_cover_layers': null,
  'unknown_layers': z,
  'observed_views': hidden ? <String>[] : ['straight'],
  'measurement_sources': sources,
  'uncertainties': hidden
      ? [
          "hidden: height assumed from its neighbours' face heights; it can "
              'be missing, shorter or taller',
        ]
      : ['occupancy not measured'],
  'readings': <Object>[],
  'pair_type': null,
  'evidence_class': evidenceClass,
  'hidden': hidden,
  'assumed_layers': assumed,
  'assumed_range': range,
  'assumed_from': from,
  'neighbours': [
    for (final n in neighbours) {'x': n[0], 'y': n[1], 'layers': n[2]},
  ],
  'top_tap': tap,
  'flags': flags,
  'past_gap_layers': pastGapLayers,
  'past_gap_scale': pastGapScale,
};

/// A measured stack (read by two captures unless [single]).
Map<String, dynamic> measured06(int x, int y, int z, {bool single = false}) =>
    cell06(
      x,
      y,
      'measured',
      legacy: single ? 'observed' : 'verified',
      z: z,
      flags: single ? const ['single_reading'] : const [],
    );

/// A present hidden stack assumed at [z] from [neighbours] (x, y, layers).
Map<String, dynamic> assumed06(
  int x,
  int y,
  int z,
  List<int?> range,
  List<List<int>> neighbours,
) => cell06(
  x,
  y,
  'assumed',
  legacy: 'computed',
  z: z,
  sources: const ['computed'],
  hidden: true,
  assumed: z,
  range: range,
  from: 'neighbours',
  neighbours: neighbours,
  flags: neighbours.length == 1 ? const ['single_neighbour'] : const [],
);

Map<String, dynamic> _inventory06({
  required int? counted,
  required int countedStacks,
  required int? assumed,
  required List<int?>? assumedRange,
  required int? assumedStacks,
  required int? total,
  required List<int?>? totalRange,
  required int? hidden,
  required int? topChecked,
  required int? unchecked,
  Map<String, int> missing = const {
    'seen_empty': 0,
    'top_missing': 0,
    'declared_missing': 0,
  },
  bool released = true,
  String? withheld,
  Map<String, dynamic>? provisional,
  String note = '',
}) => {
  'physical_layers_observed': counted ?? 0,
  'physical_layers_computed': assumed ?? 0,
  'physical_layers_declared': 0,
  'eligible_egg_trays': {
    'value': null,
    'basis': 'unknown',
    'note': 'hidden stacks are assumed: their trays are not counted',
  },
  'empty_cover_layers': {'value': null, 'basis': 'unknown'},
  'unknown_occupancy_layers': total ?? 0,
  'unknown_cells': 0,
  'unit': 'tray_layers',
  'released': released,
  'withheld_reason': withheld,
  'provisional': provisional,
  'counted_trays': counted,
  'counted_stacks': countedStacks,
  'assumed_trays': assumed,
  'assumed_range': assumedRange,
  'assumed_stacks': assumedStacks,
  'estimated_total': total,
  'estimated_range': totalRange,
  'hidden_stacks': hidden,
  'hidden_stacks_top_checked': topChecked,
  'unchecked_hidden_stacks': unchecked,
  'missing_stacks': missing,
  'cover_trays': {'value': null, 'basis': 'unknown'},
  'note': note,
};

Map<String, dynamic> _block06({
  required String status,
  required int width,
  required int? depth,
  required List<List<Map<String, dynamic>>> grid,
  required Map<String, dynamic> inventory,
  required int? total,
  int? observed,
  int? computed,
  String? depthBasis = 'declaration',
  List<String> suggestedViews = const [],
  List<String> suggestedInputs = const [],
}) => {
  'contract': 'block_model_v1',
  'grid_contract': '0.6.0',
  'status': status,
  'width': width,
  'depth': depth,
  'faces_used': ['straight', 'left', 'right'],
  'typical_layers': 20,
  'cells': <Object>[],
  'observed_trays': observed,
  'computed_trays': computed,
  'total_trays': total,
  'total_eggs': total == null ? null : total * 30,
  'fully_observed': false,
  'faces_consistent': status != 'conflict',
  'conflicts': <Object>[],
  'ambiguities': <Object>[],
  'rescan_cells': <Object>[],
  'note':
      'Counted trays are read top to floor on photographed faces. Hidden '
      'stacks are assumed at their neighbours\' face height and are not '
      'counted. A top view checks holes and step-ups, never counts. A depth '
      'over one stack rests on the declared block size.',
  'grid': grid,
  'inventory': inventory,
  'declaration': null,
  'corner': null,
  'top_view': null,
  'depth_basis': depthBasis,
  'suggested_views': suggestedViews,
  'suggested_inputs': suggestedInputs,
  'confirmed_basis': <Object>[],
};

/// Design case H2: a 4 x 3 block, front 20/19/20/20, LEFT end 20 and 18,
/// RIGHT end 20 and 20. Four hidden stacks: (1,1) 20 [19,20], (2,1) 20
/// [20,20], (1,2) 19 [18,20], (2,2) 20 [18,20]. 157 counted + 79 assumed =
/// 236, range 232–237.
Map<String, dynamic> h2Block06() => _block06(
  status: 'estimated',
  width: 4,
  depth: 3,
  total: 236,
  observed: 157,
  computed: 79,
  suggestedViews: const ['elevated'],
  grid: [
    [
      measured06(0, 0, 20),
      measured06(1, 0, 19),
      measured06(2, 0, 20),
      measured06(3, 0, 20),
    ],
    [
      measured06(0, 1, 20),
      assumed06(
        1,
        1,
        20,
        [19, 20],
        [
          [1, 0, 19],
          [0, 1, 20],
          [3, 1, 20],
        ],
      ),
      assumed06(
        2,
        1,
        20,
        [20, 20],
        [
          [2, 0, 20],
          [0, 1, 20],
          [3, 1, 20],
        ],
      ),
      measured06(3, 1, 20),
    ],
    [
      measured06(0, 2, 18),
      assumed06(
        1,
        2,
        19,
        [18, 20],
        [
          [1, 0, 19],
          [0, 2, 18],
          [3, 2, 20],
        ],
      ),
      assumed06(
        2,
        2,
        20,
        [18, 20],
        [
          [2, 0, 20],
          [0, 2, 18],
          [3, 2, 20],
        ],
      ),
      measured06(3, 2, 20),
    ],
  ],
  inventory: _inventory06(
    counted: 157,
    countedStacks: 8,
    assumed: 79,
    assumedRange: [75, 80],
    assumedStacks: 4,
    total: 236,
    totalRange: [232, 237],
    hidden: 4,
    topChecked: 0,
    unchecked: 4,
    note:
        '157 counted on faces; 79 assumed in 4 hidden stacks, none checked '
        'from the top',
  ),
);

/// The 3 x 2 `verified3x2` block of design case H6: every face stack 20, one
/// hidden stack (1,1) with neighbours 20/20/20, given the top-view [tap]
/// (`step_up`, `step_down`, `present`, `missing` or null).
Map<String, dynamic> verified3x2Block06({String? tap}) {
  final hiddenCell = switch (tap) {
    'step_up' => cell06(
      1,
      1,
      'top_step',
      legacy: 'top_view',
      z: 21,
      sources: const ['top_view', 'computed'],
      hidden: true,
      assumed: 21,
      range: [21, null],
      from: 'neighbours',
      neighbours: const [
        [1, 0, 20],
        [0, 1, 20],
        [2, 1, 20],
      ],
      tap: 'step_up',
      flags: const ['step_up_count_unknown'],
    ),
    'step_down' => cell06(
      1,
      1,
      'top_step',
      legacy: 'unknown',
      z: null,
      sources: const ['top_view'],
      hidden: true,
      range: [1, 20],
      from: 'neighbours',
      neighbours: const [
        [1, 0, 20],
        [0, 1, 20],
        [2, 1, 20],
      ],
      tap: 'step_down',
      flags: const ['step_down_count_unknown'],
    ),
    'present' => cell06(
      1,
      1,
      'top_present',
      legacy: 'top_view',
      z: 20,
      sources: const ['top_view', 'computed'],
      hidden: true,
      assumed: 20,
      range: [20, 20],
      from: 'neighbours',
      neighbours: const [
        [1, 0, 20],
        [0, 1, 20],
        [2, 1, 20],
      ],
      tap: 'present',
    ),
    'missing' => cell06(
      1,
      1,
      'top_missing',
      legacy: 'top_view',
      z: 0,
      present: false,
      sources: const ['top_view'],
      hidden: true,
      tap: 'missing',
    ),
    _ => assumed06(
      1,
      1,
      20,
      [20, 20],
      [
        [1, 0, 20],
        [0, 1, 20],
        [2, 1, 20],
      ],
    ),
  };
  final (assumed, range, total, totalRange) = switch (tap) {
    'step_up' => (21, <int?>[21, null], 121, <int?>[121, null]),
    'step_down' => (null, <int?>[1, 20], null, <int?>[101, 120]),
    'missing' => (0, <int?>[0, 0], 100, <int?>[100, 100]),
    _ => (20, <int?>[20, 20], 120, <int?>[120, 120]),
  };
  final present = tap != 'missing';
  return _block06(
    status: 'estimated',
    width: 3,
    depth: 2,
    total: total,
    observed: 100,
    computed: switch (tap) {
      'step_down' || 'missing' => 0,
      'step_up' => 21,
      _ => 20,
    },
    suggestedViews: tap == null ? const ['elevated'] : const [],
    grid: [
      [measured06(0, 0, 20), measured06(1, 0, 20), measured06(2, 0, 20)],
      [measured06(0, 1, 20), hiddenCell, measured06(2, 1, 20)],
    ],
    inventory: _inventory06(
      counted: 100,
      countedStacks: 5,
      assumed: assumed,
      assumedRange: present ? range : null,
      assumedStacks: present ? 1 : 0,
      total: total,
      totalRange: totalRange,
      hidden: 1,
      topChecked: tap == null || tap == 'unsure' ? 0 : 1,
      unchecked: tap == null || tap == 'unsure' ? 1 : 0,
      missing: {
        'seen_empty': 0,
        'top_missing': tap == 'missing' ? 1 : 0,
        'declared_missing': 0,
      },
      released: total != null,
      withheld: total == null ? 'height_unknown' : null,
    ),
  );
}

/// Design case H10: S25, a front of 5 x 20 with sides that read 3 deep and a
/// real turn, no declaration. Withheld (`needs_view`) with provisional
/// figures that are never a total.
Map<String, dynamic> s25Block06({String kind = 'depth_unproven'}) {
  final repeats = kind == 'side_repeats_front';
  return {
    ..._block06(
      status: 'needs_view',
      width: 5,
      depth: null,
      total: null,
      depthBasis: null,
      suggestedInputs: const ['declaration'],
      grid: const [],
      inventory: _inventory06(
        counted: null,
        countedStacks: 0,
        assumed: null,
        assumedRange: null,
        assumedStacks: null,
        total: null,
        totalRange: null,
        hidden: null,
        topChecked: null,
        unchecked: null,
        released: false,
        withheld: kind,
        provisional: {
          'kind': kind,
          'reason': repeats
              ? 'LEFT: shows the same 5 stacks with the same heights as '
                    'STRAIGHT; add a CORNER photo'
              : 'LEFT: the block reads 3 deep here, but rows standing '
                    'against a block look the same in every photo; declare '
                    'the block size (X x Y) before the scan to say where the '
                    'block ends',
          'front_row_counted': 100,
          'if_depth': repeats
              ? null
              : {
                  'y': 3,
                  'counted_trays': 180,
                  'assumed_trays': 120,
                  'assumed_stacks': 6,
                  'estimated_total': 300,
                },
        },
      ),
    ),
    'conflicts': [
      {'reason': 'LEFT: the block reads 3 deep here; declare the block size'},
    ],
  };
}
