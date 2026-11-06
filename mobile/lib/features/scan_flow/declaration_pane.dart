import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/block_declaration.dart';
import '../../services/settings_store.dart';

/// The operator's blind declaration of the block, asked after the three
/// photos and before the upload, so no count has been seen yet. Everything
/// starts unknown: a field left alone states nothing. SKIP DECLARATION is
/// always allowed; the result then can never be `confirmed`.
class DeclarationPane extends StatefulWidget {
  const DeclarationPane({
    super.key,
    required this.onDeclare,
    required this.onSkip,
    this.settings,
    this.now = DateTime.now,
  });

  final ValueChanged<BlockDeclaration> onDeclare;
  final VoidCallback onSkip;

  /// Remembers the last operator name; none in tests.
  final SettingsStore? settings;

  /// The declaration's timestamp, set when it is saved.
  final DateTime Function() now;

  @override
  State<DeclarationPane> createState() => _DeclarationPaneState();
}

class _DeclarationPaneState extends State<DeclarationPane> {
  int _x = 1;
  int _y = 1;
  String _interior = BlockDeclaration.kUnknown;
  final Set<(int, int)> _missing = {};
  final List<PartialStack> _partials = [];
  String _cover = BlockDeclaration.kUnknown;
  String _occupancy = BlockDeclaration.kUnknown;
  bool _measured = false;
  int _partialX = 0;
  int _partialY = 0;
  final _height = TextEditingController();
  final _partialLayers = TextEditingController();
  final _operator = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOperator();
  }

  Future<void> _loadOperator() async {
    final settings = widget.settings;
    if (settings == null) return;
    try {
      final name = await settings.getOperatorName();
      if (!mounted || name == null || _operator.text.isNotEmpty) return;
      setState(() => _operator.text = name);
    } on Object {
      // A remembered name is a convenience; the field stays editable.
    }
  }

  @override
  void dispose() {
    _height.dispose();
    _partialLayers.dispose();
    _operator.dispose();
    super.dispose();
  }

  /// A smaller grid drops the cells and stacks that no longer fit.
  void _resize({int? x, int? y}) {
    setState(() {
      _x = (x ?? _x).clamp(BlockDeclaration.minSide, BlockDeclaration.maxSide);
      _y = (y ?? _y).clamp(BlockDeclaration.minSide, BlockDeclaration.maxSide);
      _missing.removeWhere((c) => c.$1 >= _x || c.$2 >= _y);
      _partials.removeWhere((p) => p.x >= _x || p.y >= _y);
      _partialX = _partialX.clamp(0, _x - 1);
      _partialY = _partialY.clamp(0, _y - 1);
    });
  }

  void _addPartial() {
    final layers = int.tryParse(_partialLayers.text.trim());
    if (layers == null || layers < 1 || layers > 400) {
      setState(() => _error = 'Enter the partial stack height in layers (1-400).');
      return;
    }
    setState(() {
      _error = null;
      _partials
        ..removeWhere((p) => p.x == _partialX && p.y == _partialY)
        ..add(PartialStack(x: _partialX, y: _partialY, layers: layers));
      // A partial stack is a stack, not a gap.
      _missing.remove((_partialX, _partialY));
      _partialLayers.clear();
    });
  }

  void _save() {
    FocusManager.instance.primaryFocus?.unfocus();
    final heightText = _height.text.trim();
    final height = heightText.isEmpty ? null : int.tryParse(heightText);
    if (heightText.isNotEmpty && (height == null || height < 1 || height > 400)) {
      setState(() => _error = 'The reference height is a number of layers (1-400).');
      return;
    }
    if (_measured && height == null) {
      setState(
        () => _error =
            'Enter the height you measured, or untick "I measured this height".',
      );
      return;
    }
    final missing = _missing.toList()
      ..sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1));
    final declaration = BlockDeclaration(
      x: _x,
      y: _y,
      interior: _interior,
      missingCells: [
        for (final c in missing) [c.$1, c.$2],
      ],
      partialStacks: List.unmodifiable(_partials),
      coverTrays: _cover,
      occupancy: _occupancy,
      referenceHeight: height,
      referenceHeightMeasured: _measured && height != null,
      operator: _operator.text.trim(),
      declaredAt: widget.now(),
    );
    if (declaration.encode() == null) {
      setState(
        () => _error =
            'Too many marked cells to send with the photos. Mark only the '
            'cells you are sure of.',
      );
      return;
    }
    final name = declaration.operator;
    if (name.isNotEmpty) {
      widget.settings?.setOperatorName(name).catchError((Object _) {});
    }
    widget.onDeclare(declaration);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Text(
          'DECLARE THE BLOCK',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter what you know about this block now, before any count is '
          'shown. Leave anything you have not checked as unknown. A '
          'declaration is never a measurement: the result labels every value '
          'that rests on it as declared.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        CountStepper(
          label: 'X columns (front face, left to right)',
          value: _x,
          keyPrefix: 'decl-x',
          onChanged: (v) => _resize(x: v),
        ),
        CountStepper(
          label: 'Y rows (front to back)',
          value: _y,
          keyPrefix: 'decl-y',
          onChanged: (v) => _resize(y: v),
        ),
        const SizedBox(height: 12),
        _Heading('Interior'),
        _Choice(
          keyPrefix: 'decl-interior',
          values: BlockDeclaration.interiorValues,
          labels: const ['FULL', 'PARTIAL', 'UNKNOWN'],
          selected: _interior,
          onChanged: (v) => setState(() => _interior = v),
        ),
        // Worker 0.7.0: hidden stacks are full by the farm's stacking rule, so a
        // vague "partly empty" leaves no total; named stacks are honoured.
        Text(
          'The stacking rule counts every hidden stack as full. PARTIAL gives '
          'no total: instead mark below which stacks are missing or short.',
          key: const ValueKey('decl-rule-help'),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        _Heading('Known missing cells (tap to mark)'),
        Text(
          'Front row at the bottom, x from the left. Mark only cells you know '
          'have no stack. Inside the block, each one is an exception to the '
          'stacking rule.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        CellGrid(
          width: _x,
          depth: _y,
          keyPrefix: 'missing',
          cellBuilder: (x, y) {
            final marked = _missing.contains((x, y));
            return (
              text: marked ? 'X' : '',
              color: marked ? const Color(0xFFE0564B) : null,
            );
          },
          onTap: (x, y) => setState(() {
            if (!_missing.remove((x, y))) {
              _missing.add((x, y));
              _partials.removeWhere((p) => p.x == x && p.y == y);
            }
          }),
        ),
        const SizedBox(height: 12),
        _Heading('Known partial-height stacks (rule exceptions inside)'),
        for (final p in _partials)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('x${p.x} y${p.y}: ${p.layers} layers'),
            trailing: IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() => _partials.remove(p)),
            ),
          ),
        Row(
          children: [
            const Text('x '),
            DropdownButton<int>(
              key: const ValueKey('partial-x'),
              value: _partialX,
              items: [
                for (var i = 0; i < _x; i++)
                  DropdownMenuItem(value: i, child: Text('$i')),
              ],
              onChanged: (v) => setState(() => _partialX = v ?? 0),
            ),
            const SizedBox(width: 12),
            const Text('y '),
            DropdownButton<int>(
              key: const ValueKey('partial-y'),
              value: _partialY,
              items: [
                for (var i = 0; i < _y; i++)
                  DropdownMenuItem(value: i, child: Text('$i')),
              ],
              onChanged: (v) => setState(() => _partialY = v ?? 0),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const ValueKey('partial-layers'),
                controller: _partialLayers,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Layers',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('partial-add'),
              tooltip: 'Add partial stack',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: _addPartial,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Heading('Empty cover trays on the block'),
        _Choice(
          keyPrefix: 'decl-cover',
          values: BlockDeclaration.coverValues,
          labels: const ['YES', 'NO', 'UNKNOWN'],
          selected: _cover,
          onChanged: (v) => setState(() => _cover = v),
        ),
        const SizedBox(height: 12),
        _Heading('Occupancy'),
        RadioGroup<String>(
          groupValue: _occupancy,
          onChanged: (v) => setState(() => _occupancy = v ?? _occupancy),
          child: const Column(
            children: [
              RadioListTile<String>(
                key: ValueKey('decl-occupancy-egg_filled'),
                value: BlockDeclaration.kEggFilled,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('All counted trays hold eggs'),
              ),
              RadioListTile<String>(
                key: ValueKey('decl-occupancy-unknown'),
                value: BlockDeclaration.kUnknown,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('Unknown'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('decl-height'),
          controller: _height,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Reference stack height in layers (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        CheckboxListTile(
          key: const ValueKey('decl-height-measured'),
          value: _measured,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('I measured this height'),
          subtitle: const Text('An unmeasured height is ignored.'),
          onChanged: (v) => setState(() => _measured = v ?? false),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('decl-operator'),
          controller: _operator,
          decoration: const InputDecoration(
            labelText: 'Operator name or code',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null) ...[
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 10),
        ],
        FilledButton.icon(
          key: const ValueKey('declare-continue'),
          onPressed: _save,
          icon: const Icon(Icons.assignment_turned_in_outlined),
          label: const Text('SAVE DECLARATION AND CONTINUE'),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('declare-skip'),
          onPressed: widget.onSkip,
          child: const Text('SKIP DECLARATION'),
        ),
        Text(
          'A declaration lets the app check the block size against the photos.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// A whole-number stepper from [min] to [max]; a long press moves by five.
class CountStepper extends StatelessWidget {
  const CountStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.keyPrefix,
    this.min = BlockDeclaration.minSide,
    this.max = BlockDeclaration.maxSide,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final String keyPrefix;
  final int min;
  final int max;

  void _move(int by) => onChanged((value + by).clamp(min, max));

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label)),
      GestureDetector(
        onLongPress: value > min ? () => _move(-5) : null,
        child: IconButton(
          key: ValueKey('$keyPrefix-minus'),
          tooltip: 'Fewer',
          onPressed: value > min ? () => _move(-1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
      ),
      SizedBox(
        width: 34,
        child: Text(
          '$value',
          key: ValueKey('$keyPrefix-value'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
      ),
      GestureDetector(
        onLongPress: value < max ? () => _move(5) : null,
        child: IconButton(
          key: ValueKey('$keyPrefix-plus'),
          tooltip: 'More',
          onPressed: value < max ? () => _move(1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ),
    ],
  );
}

/// What one cell of a [CellGrid] shows.
typedef CellLook = ({String text, Color? color});

/// An X by Y grid of tappable cells, front row (y = 0) at the bottom and x
/// from the left, as the block is seen from the STRAIGHT position. Scrolls
/// sideways when the block is wider than the screen.
class CellGrid extends StatelessWidget {
  const CellGrid({
    super.key,
    required this.width,
    required this.depth,
    required this.keyPrefix,
    required this.cellBuilder,
    required this.onTap,
    this.cellSize = 34,
  });

  final int width;
  final int depth;
  final String keyPrefix;
  final CellLook Function(int x, int y) cellBuilder;
  final void Function(int x, int y) onTap;
  final double cellSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var y = depth - 1; y >= 0; y--)
            Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text('$y', style: const TextStyle(fontSize: 10)),
                ),
                for (var x = 0; x < width; x++)
                  Builder(
                    builder: (context) {
                      final look = cellBuilder(x, y);
                      return InkWell(
                        key: ValueKey('$keyPrefix-$x-$y'),
                        onTap: () => onTap(x, y),
                        child: Container(
                          width: cellSize,
                          height: cellSize,
                          margin: const EdgeInsets.all(1),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: look.color ?? scheme.surfaceContainerHighest,
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Text(
                            look.text,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          Row(
            children: [
              const SizedBox(width: 22),
              for (var x = 0; x < width; x++)
                SizedBox(
                  width: cellSize + 2,
                  child: Text(
                    '$x',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(left: 22, top: 2),
            child: Text(
              'FRONT (STRAIGHT PHOTO SIDE)',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
  );
}

/// One of a few fixed answers; the key of each button is
/// `<keyPrefix>-<value>`.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.keyPrefix,
    required this.values,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final String keyPrefix;
  final List<String> values;
  final List<String> labels;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    children: [
      for (var i = 0; i < values.length; i++)
        ChoiceChip(
          key: ValueKey('$keyPrefix-${values[i]}'),
          label: Text(labels[i]),
          selected: selected == values[i],
          onSelected: (_) => onChanged(values[i]),
        ),
    ],
  );
}
