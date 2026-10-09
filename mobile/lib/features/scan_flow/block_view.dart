import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/block_result.dart';

const Color kObserved = Color(0xFF3FBF6F);
const Color kComputed = Color(0xFF8A94A6);
const Color kMissing = Color(0xFFE0564B);
const Color kRescan = Color(0xFFFFB86B);

Color statusColor(String status) => switch (status) {
  'observed' => kObserved,
  'computed' => kComputed,
  'missing' => kMissing,
  _ => kRescan,
};

/// Far-to-near order for the isometric axes used by [BlockPainter]
/// (x to the lower right, y to the upper right): the nearest corner is
/// x = width, y = 0, so nearness grows with x - y.
List<BlockCell> paintOrder(List<BlockCell> cells) =>
    [...cells]..sort((a, b) => (a.x - a.y).compareTo(b.x - b.y));

/// Isometric drawing of the block: one box per stack, height = layers.
class BlockPainter extends CustomPainter {
  BlockPainter(this.block, {this.layerHeight = 0.22});

  final BlockResult block;
  final double layerHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (!block.hasGrid) return;
    final w = block.width!;
    final d = block.depth!;
    final maxLayers = block.cells
        .map((c) => c.layers ?? 0)
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
    for (final cell in paintOrder(block.cells)) {
      final color = statusColor(cell.status);
      final layers = cell.layers ?? 0;
      final x = cell.x.toDouble();
      final y = cell.y.toDouble();
      final h = layers * layerHeight;
      final floor = Path()
        ..moveTo(project(x, y, 0).dx, project(x, y, 0).dy)
        ..lineTo(project(x + 1, y, 0).dx, project(x + 1, y, 0).dy)
        ..lineTo(project(x + 1, y + 1, 0).dx, project(x + 1, y + 1, 0).dy)
        ..lineTo(project(x, y + 1, 0).dx, project(x, y + 1, 0).dy)
        ..close();
      if (layers == 0) {
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

class BlockPanel extends StatelessWidget {
  const BlockPanel({super.key, required this.block});

  final BlockResult block;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headline = block.totalTrays != null
        ? (block.fullyObserved
              ? 'ALL STACKS OBSERVED'
              : 'COMPUTED FROM ${block.facesUsed.length} FACES')
        : 'RESCAN REQUIRED';
    final color = block.totalTrays != null
        ? (block.fullyObserved ? kObserved : kComputed)
        : kRescan;
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
            if (block.hasGrid) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 220,
                child: CustomPaint(painter: BlockPainter(block)),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 14,
                children: const [
                  _Legend(color: kObserved, label: 'observed'),
                  _Legend(color: kComputed, label: 'computed'),
                  _Legend(color: kMissing, label: 'missing'),
                  _Legend(color: kRescan, label: 'rescan'),
                ],
              ),
              const Divider(height: 24),
              _Row('Block', '${block.width} wide × ${block.depth} deep'),
              _Row('Observed trays', '${block.observedTrays}'),
              _Row('Computed trays', '${block.computedTrays}'),
              _Row('Total trays', '${block.totalTrays ?? '—'}'),
              _Row('Total eggs', '${block.totalEggs ?? '—'}'),
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
            Text(
              block.note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
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
