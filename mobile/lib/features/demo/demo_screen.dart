import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../models/block_result.dart';
import '../../models/scan_result.dart';
import '../scan_flow/block_view.dart';
import '../scan_flow/result_look.dart';

/// One saved server answer, shown offline with where it came from and what
/// it does not prove.
typedef DemoCase = ({
  String asset,
  String tab,
  String title,
  String source,
  String story,
  List<String> caveats,
});

/// Real answers the test server gave earlier, bundled with the app. Nothing
/// is sent and nothing is saved to the scan history.
const List<DemoCase> kDemoCases = [
  (
    asset: 'assets/demo/demo_99_block.json',
    tab: '5 × 1 row',
    title: 'A row of 5 stacks: every stack seen',
    source: 'Test server 47cb2378 · 15 Oct 2026 · gallery photos',
    story:
        'All five stacks face the camera, so nothing is assumed. They read 20, 20, 20, 20 and 19; '
        'the shorter stack is drawn shorter.',
    caveats: [
      'The handwritten label says 99. The front photo was used while tuning the counter and the '
          'side photos came from other pictures, so this is a worked example, not a fresh test.',
    ],
  ),
  (
    asset: 'assets/demo/demo_field_4x3.json',
    tab: '4 × 3 block',
    title: 'A farm block, 4 wide × 3 deep: counted + assumed',
    source: 'Field scan 13 Oct 2026 · answer from test server f5776f0d (an older version)',
    story:
        'Stacks on the faces were counted from the photos. The front-right spot was seen empty. '
        'The stacks in the middle were never photographed: their trays are assumed, not counted.',
    caveats: [
      'A visual count of the same photos gives 104 egg trays on the seen stacks against the '
          "app's 105 layers; the difference is one empty cover tray. The 60 hidden trays are an "
          'assumption in both.',
      "Today's server holds this block back until a CORNER photo confirms its depth.",
      'No stack of this block was counted by hand on the farm yet.',
    ],
  ),
  (
    asset: 'assets/demo/demo_l100_refused.json',
    tab: 'Refused',
    title: 'Refused: the side photos show the front again',
    source: 'Test server 0.5.0 (52a1d5e8) · 1 Nov 2026 · photo set L-100',
    story:
        'Both side photos show the same 5 stacks as the front, so the depth of the block is '
        'unknown. The app gives no total and asks for real side photos.',
    caveats: [
      'Without this check, multiplying the front by a false depth gave 500 for this block of '
          'about 100 in an earlier test. A wrong total is worse than none.',
    ],
  ),
];

typedef AssetLoader = Future<String> Function(String asset);

class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key, this.load = _loadAsset});

  /// Reads a bundled answer; tests pass a file reader.
  final AssetLoader load;

  static Future<String> _loadAsset(String asset) => rootBundle.loadString(asset);

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  int _selected = 0;
  late List<Future<ScanResult>> _results;

  @override
  void initState() {
    super.initState();
    _results = [
      for (final demo in kDemoCases)
        widget.load(demo.asset).then(
          (text) => ScanResult.fromJson(jsonDecode(text) as Map<String, dynamic>),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final demo = kDemoCases[_selected];
    return Scaffold(
      appBar: AppBar(title: const Text('Demo: saved results')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Saved answers from the test server, shown offline. Not a live scan: '
                'nothing is sent and nothing is saved.',
                key: ValueKey('demo-banner'),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: [
              for (var i = 0; i < kDemoCases.length; i++)
                ButtonSegment(value: i, label: Text(kDemoCases[i].tab)),
            ],
            selected: {_selected},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _selected = s.first),
          ),
          const SizedBox(height: 12),
          FutureBuilder<ScanResult>(
            key: ValueKey(demo.asset),
            future: _results[_selected],
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('Could not read this saved answer: ${snapshot.error}');
              }
              final block = snapshot.data?.block;
              if (snapshot.data == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return _DemoCaseView(demo: demo, block: block);
            },
          ),
        ],
      ),
    );
  }
}

class _DemoCaseView extends StatelessWidget {
  const _DemoCaseView({required this.demo, required this.block});

  final DemoCase demo;
  final BlockResult? block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final block = this.block;
    final look = resultLook(block?.status ?? 'needs_view');
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          demo.title,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(demo.source, style: small),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(look.icon, color: look.color),
            const SizedBox(width: 8),
            Text(
              look.headline,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: look.color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(demo.story),
        const SizedBox(height: 10),
        if (block != null && block.totalTrays != null) _SplitCard(block: block),
        if (block != null && block.totalTrays == null) _HeldBackCard(block: block),
        const SizedBox(height: 10),
        if (block != null) BlockPanel(block: block),
        const SizedBox(height: 10),
        Text('What this does not show', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final caveat in demo.caveats)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('• $caveat', style: small),
          ),
      ],
    );
  }
}

/// Stacks no photo saw, whose height the server filled in from the faces.
List<({int x, int y, int layers})> hiddenStacks(BlockResult block) => [
  for (final cell in block.stackCells)
    if (cell.status == 'computed' && (cell.layers ?? 0) > 0)
      (x: cell.x, y: cell.y, layers: cell.layers!),
];

/// The total split into what the photos counted and what was assumed, and
/// how the assumed part was worked out.
class _SplitCard extends StatelessWidget {
  const _SplitCard({required this.block});

  final BlockResult block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hidden = hiddenStacks(block);
    final heights = {for (final h in hidden) h.layers}.toList()..sort();
    final w = block.width;
    final d = block.depth;
    final bold = theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              block.computedTrays == 0
                  ? 'Counted ${block.observedTrays} = ${block.totalTrays} tray layers'
                  : 'Counted ${block.observedTrays} + Assumed ${block.computedTrays} '
                        '= Estimated ${block.totalTrays} tray layers',
              key: const ValueKey('demo-split'),
              textAlign: TextAlign.center,
              style: bold,
            ),
            const SizedBox(height: 8),
            if (hidden.isEmpty)
              const Text('Every stack was seen in a photo; nothing is assumed.')
            else ...[
              Text('How the hidden trays are worked out', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              if (w != null && d != null)
                Text('1. Width $w from the front photo, depth $d from the side photos.'),
              Text(
                '2. Stacks no photo can see: ${hidden.length} '
                '(the ones in the middle and back).',
              ),
              Text(
                '3. Each is assumed as tall as the faces around it '
                '(${heights.join('/')}): ${block.computedTrays} tray layers.',
              ),
              const Text(
                '4. A top photo can show whether one of them is missing or taller. '
                'It cannot count their trays.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeldBackCard extends StatelessWidget {
  const _HeldBackCard({required this.block});

  final BlockResult block;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'No total: the app held the answer back',
            key: const ValueKey('demo-held-back'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            block.conflicts.isEmpty
                ? 'A photo is missing or was refused.'
                : 'Why, in the server\'s words, is listed below.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
