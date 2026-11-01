import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/extra_capture.dart';
import 'declaration_pane.dart';

/// The operator's reading of the ELEVATED photo: one tap per cell cycles it
/// through present, missing, step down and unsure. Untapped cells are not
/// reported. The grid is the declared X by Y; without a declaration the
/// operator gives X and Y first.
class ElevatedTapGrid extends StatefulWidget {
  const ElevatedTapGrid({
    super.key,
    required this.onDone,
    required this.onSkip,
    this.x,
    this.y,
    this.initial,
    this.photoPath,
  });

  /// The declared grid size; null asks for it.
  final int? x;
  final int? y;

  /// Taps already made on this photo (edited again).
  final ElevatedTaps? initial;

  /// The elevated photo, shown above the grid to read from.
  final String? photoPath;
  final ValueChanged<ElevatedTaps> onDone;
  final VoidCallback onSkip;

  @override
  State<ElevatedTapGrid> createState() => _ElevatedTapGridState();
}

class _ElevatedTapGridState extends State<ElevatedTapGrid> {
  late int _x;
  late int _y;

  /// False while X and Y are still being asked for.
  late bool _sized;
  late ElevatedTaps _taps;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final declared = widget.x != null && widget.y != null;
    _x = widget.x ?? initial?.x ?? 1;
    _y = widget.y ?? initial?.y ?? 1;
    _sized = declared || initial != null;
    _taps = initial != null && initial.x == _x && initial.y == _y
        ? initial
        : ElevatedTaps(x: _x, y: _y);
  }

  static Color? _colour(String? state) => switch (state) {
    kTapPresent => const Color(0xFF3FBF6F),
    kTapMissing => const Color(0xFFE0564B),
    kTapStepDown => const Color(0xFF64B5F6),
    kTapUnsure => const Color(0xFFB0BEC5),
    _ => null,
  };

  static String _mark(String? state) => switch (state) {
    kTapPresent => 'P',
    kTapMissing => 'X',
    kTapStepDown => 'v',
    kTapUnsure => '?',
    _ => '',
  };

  void _done() {
    if (!_taps.fitsUpload) {
      setState(
        () => _error =
            'Too many tapped cells to send with the photos. Leave cells you '
            'are unsure of untapped.',
      );
      return;
    }
    widget.onDone(_taps);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = widget.photoPath;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Text(
          'READ THE BLOCK TOP',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        if (path != null)
          SizedBox(
            height: 200,
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
              cacheWidth: 800,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        const SizedBox(height: 8),
        if (!_sized) ...[
          Text(
            'There is no declaration for this block. Give its size first.',
            style: theme.textTheme.bodySmall,
          ),
          CountStepper(
            label: 'X columns (front face, left to right)',
            value: _x,
            keyPrefix: 'taps-x',
            onChanged: (v) => setState(() => _x = v),
          ),
          CountStepper(
            label: 'Y rows (front to back)',
            value: _y,
            keyPrefix: 'taps-y',
            onChanged: (v) => setState(() => _y = v),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('taps-size-done'),
            onPressed: () => setState(() {
              _sized = true;
              _taps = ElevatedTaps(x: _x, y: _y);
            }),
            child: const Text('START READING THE TOP'),
          ),
        ] else ...[
          Text(
            'Tap each cell you can read in the photo: present (P), missing '
            '(X), step down (v) or unsure (?). Each tap moves to the next. '
            'Cells you leave untapped are not reported.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          CellGrid(
            width: _x,
            depth: _y,
            keyPrefix: 'tap',
            cellBuilder: (x, y) {
              final state = _taps.cells[(x, y)];
              return (text: _mark(state), color: _colour(state));
            },
            onTap: (x, y) => setState(() {
              _error = null;
              _taps = _taps.tap(x, y);
            }),
          ),
          const SizedBox(height: 8),
          Text(
            '${_taps.cells.length} of ${_x * _y} cells read.',
            key: const ValueKey('taps-summary'),
            style: theme.textTheme.bodySmall,
          ),
          TextButton(
            onPressed: _taps.cells.isEmpty
                ? null
                : () => setState(() => _taps = ElevatedTaps(x: _x, y: _y)),
            child: const Text('CLEAR ALL TAPS'),
          ),
          if (_error != null) ...[
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 8),
          ],
          FilledButton(
            key: const ValueKey('taps-done'),
            onPressed: _done,
            child: const Text('SAVE TOP READING'),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('taps-skip'),
          onPressed: widget.onSkip,
          child: const Text('SKIP - KEEP THE PHOTO WITHOUT A READING'),
        ),
      ],
    );
  }
}
