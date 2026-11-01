import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/block_result.dart';

/// Older cells: `observed` was seen on a face. Grid model: `verified` was
/// read the same by two independent captures (the same green).
const Color kObserved = Color(0xFF3FBF6F);
const Color kVerified = kObserved;

/// Grid model `observed`: seen, but read by one capture only.
const Color kSingleReading = Color(0xFFC5E1A5);
const Color kComputed = Color(0xFF8A94A6);
const Color kDeclared = Color(0xFFB39DDB);
const Color kTopView = Color(0xFF64B5F6);
const Color kMissing = Color(0xFFE0564B);
const Color kRescan = Color(0xFFFFB86B);
const Color kUnknownCell = Color(0xFF546E7A);

Color statusColor(String status) => switch (status) {
  'observed' || 'verified' => kObserved,
  'computed' => kComputed,
  'declared' => kDeclared,
  'top_view' => kTopView,
  'missing' => kMissing,
  'unknown' => kUnknownCell,
  _ => kRescan,
};

/// A grid-model stack's colour: by status, with a stack seen by one capture
/// only told apart from a verified one, and a stack known to be absent drawn
/// as missing whatever its status says.
Color gridCellColor(GridCell cell) {
  if (cell.stackPresent == false) return kMissing;
  return switch (cell.status) {
    'observed' => kSingleReading,
    'verified' ||
    'computed' ||
    'declared' ||
    'top_view' ||
    'missing' ||
    'conflict' ||
    'rescan' ||
    'unknown' => statusColor(cell.status),
    // A status this app does not know (a newer server): its first source.
    _ when cell.measurementSources.isNotEmpty => switch (cell
        .measurementSources
        .first) {
      'observed' => kSingleReading,
      final source => statusColor(source),
    },
    _ => kUnknownCell,
  };
}

/// Far-to-near order for the isometric axes used by [BlockPainter]
/// (x to the lower right, y to the upper right): the nearest corner is
/// x = width, y = 0, so nearness grows with x - y.
List<BlockCell> paintOrder(List<BlockCell> cells) =>
    [...cells]..sort((a, b) => (a.x - a.y).compareTo(b.x - b.y));

/// One stack as drawn: a box [layers] high, or only its floor.
typedef _Box = ({int x, int y, int layers, Color color, bool floorOnly});

/// Isometric drawing of the block: one box per stack, height = layers. The
/// grid model (z layers per cell, coloured by status and source) when the
/// server sends one, else the older cells.
class BlockPainter extends CustomPainter {
  BlockPainter(this.block, {this.layerHeight = 0.22});

  final BlockResult block;
  final double layerHeight;

  List<_Box> get _boxes {
    if (block.hasGridModel) {
      return [
        for (final cell in block.grid)
          (
            x: cell.x,
            y: cell.y,
            layers: cell.stackPresent == false ? 0 : cell.zLayers ?? 0,
            color: gridCellColor(cell),
            floorOnly:
                cell.stackPresent == false ||
                cell.status == 'missing' ||
                (cell.zLayers ?? 0) == 0,
          ),
      ];
    }
    if (!block.hasGrid) return const [];
    return [
      for (final cell in block.cells)
        (
          x: cell.x,
          y: cell.y,
          layers: cell.layers ?? 0,
          color: statusColor(cell.status),
          floorOnly: (cell.layers ?? 0) == 0,
        ),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final boxes = _boxes;
    if (boxes.isEmpty) return;
    final w = block.hasGridModel ? block.gridWidth : block.width!;
    final d = block.hasGridModel ? block.gridDepth : block.depth!;
    final maxLayers = boxes
        .map((b) => b.layers)
        .fold<int>(0, math.max)
        .clamp(1, 1000);
    // Isometric axes: x to the right-down, y to the right-up, z up.
    const ax = Offset(0.87, 0.5);
    const ay = Offset(0.87, -0.5);
    final extentX = (w + d) * 0.87;
    final extentY = (w + d) * 0.5 + maxLayers * layerHeight;
    final scale = math.min(size.width / extentX, size.height / extentY) * 0.92;
    final origin = Offset(
      (size.width - extentX * scale) / 2,
      size.height - (size.height - extentY * scale) / 2 - w * 0.5 * scale,
    );
    Offset project(double x, double y, double z) =>
        origin +
        Offset(
          (ax.dx * x + ay.dx * y) * scale,
          (ax.dy * x + ay.dy * y) * scale - z * scale,
        );
    // Server y=0 is the STRAIGHT (front) row; it is drawn at y=0, whose
    // outward face is the visible front face in this projection.
    final ordered = [...boxes]
      ..sort((a, b) => (a.x - a.y).compareTo(b.x - b.y));
    for (final box in ordered) {
      final color = box.color;
      final layers = box.layers;
      final x = box.x.toDouble();
      final y = box.y.toDouble();
      final h = layers * layerHeight;
      final floor = Path()
        ..moveTo(project(x, y, 0).dx, project(x, y, 0).dy)
        ..lineTo(project(x + 1, y, 0).dx, project(x + 1, y, 0).dy)
        ..lineTo(project(x + 1, y + 1, 0).dx, project(x + 1, y + 1, 0).dy)
        ..lineTo(project(x, y + 1, 0).dx, project(x, y + 1, 0).dy)
        ..close();
      if (box.floorOnly) {
        canvas.drawPath(
          floor,
          Paint()
            ..color = color.withValues(alpha: 0.35)
            ..style = PaintingStyle.fill,
        );
        canvas.drawPath(
          floor,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        continue;
      }
      final top = Path()
        ..moveTo(project(x, y, h).dx, project(x, y, h).dy)
        ..lineTo(project(x + 1, y, h).dx, project(x + 1, y, h).dy)
        ..lineTo(project(x + 1, y + 1, h).dx, project(x + 1, y + 1, h).dy)
        ..lineTo(project(x, y + 1, h).dx, project(x, y + 1, h).dy)
        ..close();
      final front = Path()
        ..moveTo(project(x, y, 0).dx, project(x, y, 0).dy)
        ..lineTo(project(x + 1, y, 0).dx, project(x + 1, y, 0).dy)
        ..lineTo(project(x + 1, y, h).dx, project(x + 1, y, h).dy)
        ..lineTo(project(x, y, h).dx, project(x, y, h).dy)
        ..close();
      final side = Path()
        ..moveTo(project(x + 1, y, 0).dx, project(x + 1, y, 0).dy)
        ..lineTo(project(x + 1, y + 1, 0).dx, project(x + 1, y + 1, 0).dy)
        ..lineTo(project(x + 1, y + 1, h).dx, project(x + 1, y + 1, h).dy)
        ..lineTo(project(x + 1, y, h).dx, project(x + 1, y, h).dy)
        ..close();
      final fill = Paint()..style = PaintingStyle.fill;
      canvas.drawPath(front, fill..color = color.withValues(alpha: 0.95));
      canvas.drawPath(side, fill..color = color.withValues(alpha: 0.7));
      canvas.drawPath(top, fill..color = color.withValues(alpha: 1.0));
      final edge = Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;
      canvas.drawPath(front, edge);
      canvas.drawPath(side, edge);
      canvas.drawPath(top, edge);
      // Layer ticks on the front face so the height is readable.
      for (var k = 1; k < layers; k++) {
        final z = k * layerHeight;
        canvas.drawLine(
          project(x, y, z),
          project(x + 1, y, z),
          Paint()
            ..color = Colors.black.withValues(alpha: 0.18)
            ..strokeWidth = 0.5,
        );
      }
      final label = TextPainter(
        text: TextSpan(
          text: '$layers',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Colors.black,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final centre = project(x + 0.5, y + 0.5, h);
      label.paint(canvas, centre - Offset(label.width / 2, label.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant BlockPainter old) => old.block != block;
}

/// What a `confirmed` interior rests on, in the operator's words.
String confirmedBasisWords(List<String> basis) {
  final words = [
    if (basis.contains('declaration')) 'OPERATOR DECLARATION',
    if (basis.contains('top_view')) 'TOP VIEW',
  ];
  return words.isEmpty ? 'NOT REPORTED' : words.join(' + ');
}

String _agreement(bool? agrees, String what) => switch (agrees) {
  true => 'agrees with $what',
  false => 'disagrees with $what',
  null => 'not compared',
};

String _side(String? side) => switch (side) {
  'front_left' => 'front left',
  'front_right' => 'front right',
  final other => other ?? 'side not given',
};

class BlockPanel extends StatelessWidget {
  const BlockPanel({super.key, required this.block});

  final BlockResult block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final single = block.visibleSingleReadingTrays ?? 0;
    final (headline, color) = switch (block.status) {
      kBlockExact => ('EVERY STACK SEEN BY TWO PHOTOS', kObserved),
      // Never "exact" or "physically verified": the interior is declared or
      // read from the top view, and the panel says which.
      kBlockConfirmed => (
        'INTERIOR BASIS: ${confirmedBasisWords(block.confirmedBasis)}',
        kDeclared,
      ),
      kBlockEstimated when block.computedTrays > 0 => (
        'ESTIMATE: ${block.computedTrays} TRAYS IN HIDDEN STACKS',
        kComputed,
      ),
      kBlockEstimated when single > 0 => (
        'ESTIMATE: $single TRAYS SEEN BY ONE PHOTO ONLY',
        kComputed,
      ),
      kBlockEstimated => ('ESTIMATE: A READING IS UNCERTAIN', kComputed),
      'needs_view' => ('RETAKE A PHOTO', kRescan),
      _ => ('RESCAN REQUIRED', kRescan),
    };
    final gridModel = block.hasGridModel;
    final inventory = block.inventory;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              headline,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            if (gridModel || block.hasGrid) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 220,
                child: CustomPaint(painter: BlockPainter(block)),
              ),
              if (gridModel)
                Text(
                  'Grid model from photos, not a point cloud or measured mesh.',
                  key: const ValueKey('grid-model-caption'),
                  textAlign: TextAlign.center,
                  style: small,
                ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 14,
                runSpacing: 4,
                children: gridModel
                    ? const [
                        _Legend(color: kVerified, label: 'verified (two captures)'),
                        _Legend(color: kSingleReading, label: 'seen by one capture'),
                        _Legend(color: kComputed, label: 'computed'),
                        _Legend(color: kDeclared, label: 'declared'),
                        _Legend(color: kTopView, label: 'top view'),
                        _Legend(color: kMissing, label: 'no stack'),
                        _Legend(color: kRescan, label: 'conflict / rescan'),
                        _Legend(color: kUnknownCell, label: 'unknown'),
                      ]
                    : const [
                        _Legend(color: kObserved, label: 'seen'),
                        _Legend(color: kComputed, label: 'hidden, computed'),
                        _Legend(color: kMissing, label: 'no stack'),
                        _Legend(color: kRescan, label: 'rescan'),
                      ],
              ),
              const Divider(height: 24),
              _Row(
                gridModel ? 'Block (grid model)' : 'Block',
                gridModel
                    ? '${block.gridWidth} wide × ${block.gridDepth} deep'
                    : '${block.width} wide × ${block.depth} deep',
              ),
              if (block.visibleVerifiedTrays == null)
                _Row('Seen trays', '${block.observedTrays}')
              else ...[
                _Row('Seen by two photos', '${block.visibleVerifiedTrays}'),
                _Row('Seen by one photo only', '$single'),
              ],
              if (gridModel && inventory != null)
                ..._inventoryRows(inventory, small)
              else ...[
                _Row('Hidden trays (computed)', '${block.computedTrays}'),
                if (block.filledTrays > 0)
                  _Row('Layers between detected boxes', '${block.filledTrays}'),
                _Row('Total trays', '${block.totalTrays ?? '—'}'),
                // Egg occupancy is not measured: 30 per tray is capacity.
                _Row('Eggs if every tray is full', '${block.totalEggs ?? '—'}'),
              ],
            ],
            ..._evidenceRows(small),
            if (block.ambiguities.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...block.ambiguities.map(
                (a) => Text('• $a', style: theme.textTheme.bodySmall),
              ),
            ],
            if (block.conflicts.isNotEmpty || block.rescanCells.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...block.conflicts.map(
                (c) => Text('• $c', style: theme.textTheme.bodySmall),
              ),
              if (block.rescanCells.isNotEmpty)
                Text(
                  '• Stacks needing a rescan (x,y): '
                  '${block.rescanCells.map((c) => '(${c[0]},${c[1]})').join(' ')}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
            const SizedBox(height: 8),
            Text(block.note, style: small),
          ],
        ),
      ),
    );
  }

  /// Physical layers kept apart by where they come from, and egg trays with
  /// what their occupancy rests on (measured, declared or unknown).
  List<Widget> _inventoryRows(BlockInventory inventory, TextStyle? small) {
    String n(int? value) => value == null ? '—' : '$value';
    final eligible = inventory.eligibleEggTrays;
    final cover = inventory.emptyCoverLayers;
    return [
      _Row('Physical layers observed', n(inventory.physicalLayersObserved)),
      _Row('Physical layers computed', n(inventory.physicalLayersComputed)),
      _Row('Physical layers declared', n(inventory.physicalLayersDeclared)),
      if (block.totalTrays != null)
        _Row('Physical layers in total', '${block.totalTrays}'),
      _Row(
        'Eligible egg trays',
        eligible?.value == null
            ? 'unknown'
            : '${eligible!.value} (${eligible.basis})',
        key: const ValueKey('eligible-egg-trays'),
      ),
      if (eligible?.note case final note? when note.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(note, style: small),
        ),
      _Row(
        'Empty cover layers',
        cover?.value == null
            ? 'unknown'
            : '${cover!.value} (${cover.basis})',
      ),
      _Row('Unknown-occupancy layers', n(inventory.unknownOccupancyLayers)),
      if ((inventory.unknownCells ?? 0) > 0)
        _Row('Unknown cells', '${inventory.unknownCells}'),
    ];
  }

  /// The declaration, corner and top view, and the views that would help.
  List<Widget> _evidenceRows(TextStyle? small) {
    final declaration = block.declaration;
    final corner = block.corner;
    final top = block.topView;
    return [
      if (declaration != null || corner != null || top != null)
        const Divider(height: 20),
      if (declaration != null)
        _Row(
          'Declaration (${declaration.x} × ${declaration.y})',
          _agreement(declaration.agreesWithFaces, 'faces'),
        ),
      if (corner != null)
        _Row(
          'Corner photo (${_side(corner.side)})',
          _agreement(corner.agrees, 'faces'),
        ),
      if (top != null) ...[
        _Row('Top view', _agreement(top.agrees, 'faces')),
        Text(
          'Top view: ${top.cellsPresent ?? '—'} present, '
          '${top.cellsMissing ?? '—'} missing, ${top.steps ?? '—'} steps.',
          style: small,
        ),
      ],
      if (block.suggestedViews.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
          'Would help: ${block.suggestedViews.map((v) => '${v.toUpperCase()} photo').join(', ')}.',
          key: const ValueKey('suggested-views'),
          style: small,
        ),
      ],
    ];
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: 12, color: color),
      const SizedBox(width: 4),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
