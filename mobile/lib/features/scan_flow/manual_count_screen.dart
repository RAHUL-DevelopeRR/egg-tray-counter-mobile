import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/manual_count.dart';
import '../../models/scan_result.dart';
import '../../services/api_client.dart';
import '../../services/manual_count_store.dart';
import 'block_view.dart';

/// On-site count entry for the block the app just scanned: one row per stack,
/// pre-filled with the app's layer count, saved on the phone and sent to the
/// server next to the scan's photos. This is the ground truth for scoring; the
/// app never uses it to change its own count.
class ManualCountScreen extends StatefulWidget {
  const ManualCountScreen({
    super.key,
    required this.result,
    required this.repository,
    required this.baseUrl,
    this.appVersion = '0.4.3+14',
  });

  final ScanResult result;
  final ManualCountRepository repository;
  final String baseUrl;
  final String appVersion;

  @override
  State<ManualCountScreen> createState() => _ManualCountScreenState();
}

class _ManualCountScreenState extends State<ManualCountScreen> {
  late ManualCount _count;
  final _blockId = TextEditingController();
  final _notes = TextEditingController();
  final Map<String, TextEditingController> _filled = {};
  final Map<String, TextEditingController> _empty = {};
  String? _status;
  bool _busy = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    final block = widget.result.block;
    final cells = [
      for (final c in (block?.cells ?? const []))
        ManualCountCell.fromBlockCell(c),
    ]..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
    _count = ManualCount(
      scanId: widget.result.scanId,
      blockId: '',
      cells: cells,
      notes: '',
      createdAt: DateTime.now(),
      appTotal: block?.totalTrays,
    );
    for (final c in cells) {
      _filled[_key(c)] = TextEditingController(text: '${c.filled}');
      _empty[_key(c)] = TextEditingController(text: '${c.empty}');
    }
  }

  String _key(ManualCountCell c) => '${c.x},${c.y}';

  @override
  void dispose() {
    _blockId.dispose();
    _notes.dispose();
    for (final c in _filled.values) {
      c.dispose();
    }
    for (final c in _empty.values) {
      c.dispose();
    }
    super.dispose();
  }

  ManualCount _collect() => _count.copyWith(
    blockId: _blockId.text.trim(),
    notes: _notes.text.trim(),
    cells: [
      for (final c in _count.cells)
        c.copyWith(
          filled: int.tryParse(_filled[_key(c)]!.text.trim()) ?? 0,
          empty: int.tryParse(_empty[_key(c)]!.text.trim()) ?? 0,
        ),
    ],
  );

  void _toggleUnreachable(ManualCountCell cell, bool value) {
    setState(() {
      _count = _count.copyWith(
        cells: [
          for (final c in _count.cells)
            _key(c) == _key(cell) ? c.copyWith(unreachable: value) : c,
        ],
      );
    });
  }

  Future<void> _save({bool send = false}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final count = _collect();
    if (count.blockId.isEmpty) {
      setState(() => _status = 'Enter the block ID first.');
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await widget.repository.save(count);
      var saved = count;
      if (send) {
        final response = await ApiClient(
          widget.baseUrl,
        ).submitManualCount(count, appVersion: widget.appVersion);
        saved = count.copyWith(submitted: true);
        await widget.repository.save(saved);
        final totals = response['totals'];
        setState(() {
          _sent = true;
          _status =
              'Sent to server: filled ${totals?['filled']}, empty ${totals?['empty']}.';
        });
      } else {
        setState(() => _status = 'Saved on this phone.');
      }
      _count = saved;
    } on Object catch (error) {
      setState(() => _status = 'Saved on phone; sending failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyCsv() async {
    final csv = await widget.repository.csv();
    await Clipboard.setData(ClipboardData(text: csv));
    if (!mounted) return;
    setState(() => _status = 'All manual counts copied as CSV.');
  }

  @override
  Widget build(BuildContext context) {
    final live = _collect();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Manual count')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Text(
            'Count each stack on site. x runs left to right as seen from the '
            'STRAIGHT position, y runs front to back, both from 0. Tick '
            '"unreachable" for interior stacks you cannot count.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _blockId,
            decoration: const InputDecoration(
              labelText: 'Block ID',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 12),
          if (_count.cells.isEmpty)
            const Text(
              'No block grid in this result; nothing to count against.',
            )
          else
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2.2),
                1: FlexColumnWidth(1.1),
                2: FlexColumnWidth(1.1),
                3: FlexColumnWidth(1.3),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  children: [
                    _head('Stack (app)'),
                    _head('Filled'),
                    _head('Empty'),
                    _head('Unreachable'),
                  ],
                ),
                for (final c in _count.cells)
                  TableRow(
                    children: [
                      Padding(
                        key: ValueKey('row-${_key(c)}'),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              color: statusColor(c.appStatus),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'x${c.x} y${c.y}  app ${c.appLayers ?? '—'}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _number(_filled[_key(c)]!, 'filled-${_key(c)}'),
                      _number(_empty[_key(c)]!, 'empty-${_key(c)}'),
                      Checkbox(
                        key: ValueKey('unreachable-${_key(c)}'),
                        value: c.unreachable,
                        onChanged: (v) => _toggleUnreachable(c, v ?? false),
                      ),
                    ],
                  ),
              ],
            ),
          const Divider(height: 28),
          _totalsRow('App total', '${_count.appTotal ?? '—'}'),
          _totalsRow('Manual filled', '${live.filledTotal}'),
          _totalsRow('Manual empty', '${live.emptyTotal}'),
          _totalsRow('Unreachable stacks', '${live.unreachableCount}'),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(
              labelText: 'Notes (lighting, gaps, rescans, anything odd)',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          if (_status != null) ...[
            Text(_status!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
          ],
          if (_sent) ...[
            FilledButton.icon(
              key: const ValueKey('manual-count-done'),
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('DONE — NEXT BLOCK'),
            ),
            const SizedBox(height: 8),
          ],
          FilledButton.icon(
            onPressed: _busy ? null : () => _save(send: true),
            icon: const Icon(Icons.cloud_upload_outlined),
            label: Text(_sent ? 'SEND AGAIN (CORRECTION)' : 'SAVE AND SEND TO SERVER'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : () => _save(),
            child: const Text('SAVE ON PHONE ONLY'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _busy ? null : _copyCsv,
            icon: const Icon(Icons.copy_all_outlined),
            label: const Text('COPY ALL COUNTS AS CSV'),
          ),
        ],
      ),
    );
  }

  Widget _head(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
  );

  Widget _number(TextEditingController controller, String key) => Padding(
    padding: const EdgeInsets.all(3),
    child: TextField(
      key: ValueKey(key),
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
      ),
    ),
  );

  Widget _totalsRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    ),
  );
}
