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

/// How a stack is drawn. A counted stack is a solid box with layer ticks; a
/// stack whose height is assumed is a see-through ghost with no ticks; a
/// stack known to be absent is only its footprint (dashed when a face photo
/// saw the gap).
enum CellShape { solid, ghost, footprint, dashedFootprint }

/// One stack's drawing: its shape, colour, drawn height, the label on its top
/// and a badge above it. [edge] outlines a ghost's top (seen from the top) or
/// a footprint (how the gap is known).
typedef CellLook = ({
  CellShape shape,
  Color color,
  int layers,
  bool ticks,
  String? label,
  String? badge,
  Color? edge,
});

CellLook _look(
  CellShape shape,
  Color color, {
  int layers = 0,
  String? label,
  String? badge,
  Color? edge,
}) => (
  shape: shape,
  color: color,
  layers: layers,
  ticks: shape == CellShape.solid,
  label: label,
  badge: badge,
  edge: edge,
);

/// The drawing of one stack by its evidence class. Only a measured stack is
/// solid with ticks; a hidden one's height is written "~N" (assumed), a
/// step up "▲ ≥N" (at least its lowest neighbour + 1, open above) and a step
/// down "▼ ?" (height unknown).
CellLook cellLook(CellEvidence e) {
  final range = e.range;
  // A ghost with no height is drawn at the top of its range, if any.
  final shown = e.layers ?? (range == null ? null : range[1]) ?? 0;
  return switch (e.evidenceClass) {
    EvidenceClass.measured when shown > 0 => _look(
      CellShape.solid,
      e.singleReading ? kSingleReading : kVerified,
      layers: shown,
      label: '$shown',
    ),
    EvidenceClass.measured => _look(CellShape.footprint, kVerified),
    EvidenceClass.assumed => _look(
      CellShape.ghost,
      kComputed,
      layers: shown,
      label: e.layers == null ? '?' : '~${e.layers}',
    ),
    EvidenceClass.topPresent => _look(
      CellShape.ghost,
      kComputed,
      layers: shown,
      label: e.layers == null ? '?' : '~${e.layers}',
      edge: kTopView,
    ),
    EvidenceClass.topStep when e.stepDown => _look(
      CellShape.ghost,
      kComputed,
      layers: shown,
      label: '▼ ?',
      badge: 'shorter',
      edge: kTopView,
    ),
    EvidenceClass.topStep => _look(
      CellShape.ghost,
      kComputed,
      layers: shown,
      label: '▲ ≥${range?.first ?? e.layers ?? '?'}',
      badge: 'taller',
      edge: kTopView,
    ),
    EvidenceClass.seenEmpty => _look(CellShape.dashedFootprint, kMissing),
    // A hole inside the block: its footprint, and "0" on the block's top.
    EvidenceClass.topMissing => _look(
      CellShape.footprint,
      kMissing,
      label: '0',
      edge: kTopView,
    ),
    EvidenceClass.declaredMissing => _look(
      CellShape.footprint,
      kMissing,
      label: '0',
      edge: kDeclared,
    ),
    EvidenceClass.conflict when shown > 0 => _look(
      CellShape.ghost,
      kRescan,
      layers: shown,
      label: '?',
    ),
    EvidenceClass.conflict => _look(CellShape.footprint, kRescan, label: '?'),
  };
}

/// The legend words for one stack, in the operator's words.
String evidenceLegendLabel(CellEvidence e) => switch (e.evidenceClass) {
  EvidenceClass.measured =>
    e.singleReading ? 'counted, read once' : 'counted, two photos agree',
  EvidenceClass.assumed when e.flags.contains('line_of_sight_past_gap') =>
    'seen through a gap: assumed',
  EvidenceClass.assumed => '~ assumed, not counted',
  EvidenceClass.topPresent => '~ assumed, there from the top',
  EvidenceClass.topStep when e.stepDown => '▼ shorter from the top',
  EvidenceClass.topStep => '▲ taller from the top',
  EvidenceClass.seenEmpty => 'no stack (seen on a face)',
  EvidenceClass.topMissing => 'no stack (top view)',
  EvidenceClass.declaredMissing => 'no stack (declared)',
  EvidenceClass.conflict => 'conflict / rescan',
};

/// Isometric drawing of the block: one box per stack, height = layers, drawn
/// by evidence class ([cellLook]). The grid model when the server sends one,
/// else the older cells, both read through [BlockResult.evidence].
class BlockPainter extends CustomPainter {
  BlockPainter(this.block, {this.layerHeight = 0.22});

  final BlockResult block;
  final double layerHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (!block.hasGridModel && !block.hasGrid) return;
    final cells = block.evidence;
    if (cells.isEmpty) return;
    final boxes = [for (final c in cells) (cell: c, look: cellLook(c))];
    final w = cells.fold<int>(
      block.hasGridModel ? block.gridWidth : block.width ?? 0,
      (m, c) => math.max(m, c.x + 1),
    );
    final d = cells.fold<int>(
      block.hasGridModel ? block.gridDepth : block.depth ?? 0,
      (m, c) => math.max(m, c.y + 1),
    );
    final maxLayers = boxes
        .map((b) => b.look.layers)
        .fold<int>(0, math.max)
        .clamp(1, 1000);
    // The block's top (median counted height): a hole inside the block is
    // outlined there too, or the stacks in front would hide its footprint.
    final counted = [
      for (final b in boxes)
        if (b.cell.evidenceClass.counted && b.look.layers > 0) b.look.layers,
    ]..sort();
    final lid = counted.isEmpty ? 0 : counted[counted.length ~/ 2];
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
    Path quad(List<Offset> points) => Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();
    // Server y=0 is the STRAIGHT (front) row; it is drawn at y=0, whose
    // outward face is the visible front face in this projection.
    final ordered = [...boxes]
      ..sort((a, b) => (a.cell.x - a.cell.y).compareTo(b.cell.x - b.cell.y));
    for (final box in ordered) {
      final look = box.look;
      final color = look.color;
      final x = box.cell.x.toDouble();
      final y = box.cell.y.toDouble();
      final h = look.layers * layerHeight;
      final floorCorners = [
        project(x, y, 0),
        project(x + 1, y, 0),
        project(x + 1, y + 1, 0),
        project(x, y + 1, 0),
      ];
      final floor = quad(floorCorners);
      final flat =
          look.shape == CellShape.footprint ||
          look.shape == CellShape.dashedFootprint ||
          look.layers == 0;
      if (flat) {
        canvas.drawPath(
          floor,
          Paint()
            ..color = color.withValues(
              alpha: look.shape == CellShape.ghost ? 0.12 : 0.2,
            )
            ..style = PaintingStyle.fill,
        );
        final stroke = Paint()
          ..color = look.edge ?? color
          ..style = PaintingStyle.stroke
          ..strokeWidth = look.edge == null ? 1.2 : 2.0;
        canvas.drawPath(
          look.shape == CellShape.dashedFootprint
              ? _dashed(floorCorners)
              : floor,
          stroke,
        );
        final hole =
            box.cell.hidden && box.cell.evidenceClass.empty && lid > 0;
        final labelZ = hole ? lid * layerHeight : 0.0;
        if (hole) {
          canvas.drawPath(
            _dashed([
              project(x, y, labelZ),
              project(x + 1, y, labelZ),
              project(x + 1, y + 1, labelZ),
              project(x, y + 1, labelZ),
            ]),
            stroke..strokeWidth = 1.4,
          );
        }
        if (look.label case final label?) {
          _text(
            canvas,
            label,
            project(x + 0.5, y + 0.5, labelZ),
            const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          );
        }
        continue;
      }
      final top = quad([
        project(x, y, h),
        project(x + 1, y, h),
        project(x + 1, y + 1, h),
        project(x, y + 1, h),
      ]);
      final front = quad([
        project(x, y, 0),
        project(x + 1, y, 0),
        project(x + 1, y, h),
        project(x, y, h),
      ]);
      final side = quad([
        project(x + 1, y, 0),
        project(x + 1, y + 1, 0),
        project(x + 1, y + 1, h),
        project(x + 1, y, h),
      ]);
      final fill = Paint()..style = PaintingStyle.fill;
      if (look.shape == CellShape.solid) {
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
      } else {
        // A ghost: see-through faces, hatched front, no layer ticks, because
        // its height is assumed and was never counted.
        canvas.drawPath(front, fill..color = color.withValues(alpha: 0.16));
        canvas.drawPath(side, fill..color = color.withValues(alpha: 0.1));
        canvas.drawPath(top, fill..color = color.withValues(alpha: 0.22));
        canvas.save();
        canvas.clipPath(front);
        canvas.drawPath(
          _hatch(front.getBounds()),
          Paint()
            ..color = color.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.6,
        );
        canvas.restore();
        final edge = Paint()
          ..color = color.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9;
        canvas.drawPath(front, edge);
        canvas.drawPath(side, edge);
        canvas.drawPath(top, edge);
      }
      if (look.edge case final edgeColor?) {
        canvas.drawPath(
          top,
          Paint()
            ..color = edgeColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
      }
      // Layer ticks on the front face so a counted height is readable.
      if (look.ticks) {
        for (var k = 1; k < look.layers; k++) {
          final z = k * layerHeight;
          canvas.drawLine(
            project(x, y, z),
            project(x + 1, y, z),
            Paint()
              ..color = Colors.black.withValues(alpha: 0.18)
              ..strokeWidth = 0.5,
          );
        }
      }
      final centre = project(x + 0.5, y + 0.5, h);
      if (look.label case final label?) {
        _text(
          canvas,
          label,
          centre,
          TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            fontStyle: look.shape == CellShape.solid
                ? FontStyle.normal
                : FontStyle.italic,
            color: look.shape == CellShape.solid
                ? Colors.black
                : const Color(0xFF37474F),
          ),
        );
      }
      if (look.badge case final badge?) {
        _badge(canvas, badge, centre - Offset(0, 0.55 * scale), look.edge);
      }
    }
  }

  /// Diagonal hatching over [bounds] as one path.
  static Path _hatch(Rect bounds) {
    final path = Path();
    const step = 5.0;
    for (var s = bounds.left - bounds.height; s < bounds.right; s += step) {
      path
        ..moveTo(s, bounds.bottom)
        ..lineTo(s + bounds.height, bounds.top);
    }
    return path;
  }

  /// The closed outline through [corners] as dashes.
  static Path _dashed(List<Offset> corners) {
    final path = Path();
    const dash = 4.0;
    const gap = 3.0;
    for (var i = 0; i < corners.length; i++) {
      final a = corners[i];
      final b = corners[(i + 1) % corners.length];
      final length = (b - a).distance;
      if (length == 0) continue;
      final unit = (b - a) / length;
      for (var t = 0.0; t < length; t += dash + gap) {
        final start = a + unit * t;
        final end = a + unit * math.min(t + dash, length);
        path
          ..moveTo(start.dx, start.dy)
          ..lineTo(end.dx, end.dy);
      }
    }
    return path;
  }

  static void _text(Canvas canvas, String text, Offset centre, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      centre - Offset(painter.width / 2, painter.height / 2),
    );
  }

  static void _badge(Canvas canvas, String text, Offset centre, Color? edge) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: Color(0xFF0D47A1),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final box = Rect.fromCenter(
      center: centre,
      width: painter.width + 8,
      height: painter.height + 4,
    );
    final shape = RRect.fromRectAndRadius(box, const Radius.circular(4));
    canvas.drawRRect(
      shape,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..color = edge ?? kTopView
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    painter.paint(canvas, box.topLeft + const Offset(4, 2));
  }

  @override
  bool shouldRepaint(covariant BlockPainter old) =>
      old.block != block || old.layerHeight != layerHeight;
}

/// What a `confirmed` interior rests on, in the operator's words (0.5
/// servers only).
String confirmedBasisWords(List<String> basis) {
  final words = [
    if (basis.contains('declaration')) 'OPERATOR DECLARATION',
    if (basis.contains('top_view')) 'TOP VIEW',
  ];
  return words.isEmpty ? 'NOT REPORTED' : words.join(' + ');
}

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// `[low, high]` in words: "75–80", or "75 or more" when open above.
String rangeWords(List<int?> range) =>
    range[1] == null ? '${range[0]} or more' : '${range[0]}–${range[1]}';

/// The split line: "Counted 157 + Assumed 79 (range 75–80) = Estimated 236
/// tray layers". The range belongs to the assumed part and is never printed
/// bare; an older server sends none. Only for a block with a total.
String traySplitLine(TraySplit split, {String status = kBlockEstimated}) {
  final assumed = split.assumed ?? 0;
  final range = split.assumedRange;
  final rangeText = assumed == 0 && (split.assumedStacks ?? 0) == 0
      ? ''
      : range == null
      ? ' (range not given)'
      : ' (range ${rangeWords(range)})';
  final total = status == kBlockExact ? 'Total' : 'Estimated';
  return 'Counted ${split.counted} + Assumed $assumed$rangeText = '
      '$total ${split.estimated} tray layers';
}

String _basisWords(Set<String> from) {
  final words = <String>{
    for (final f in from)
      switch (f) {
        'neighbours' => "its neighbours' face height",
        'face_typical' => "the block's typical face height",
        'declared_partial' || 'declared' => 'the declared height',
        _ => 'an assumed height',
      },
  };
  return words.isEmpty ? "the faces' height" : words.join(' or ');
}

/// What the assumed part rests on, and what it can hide.
String assumptionLine(TraySplit split) {
  final stacks = split.assumedStacks;
  final hidden = split.hiddenStacks;
  if (split.assumed == 0 && (stacks ?? 0) == 0) {
    if (hidden != null && hidden > 0) {
      final which = hidden == 1
          ? 'the hidden stack is'
          : 'the $hidden hidden stacks are';
      return 'Nothing assumed: $which marked empty from the top view or the '
          'declaration.';
    }
    return 'Nothing assumed: every stack in the total was counted on a '
        'photographed face.';
  }
  final trays = split.assumed == null
      ? 'an unknown number of tray layers'
      : '${split.assumed} tray layers';
  final where = stacks == null
      ? 'hidden stacks'
      : _plural(stacks, 'hidden stack', 'hidden stacks');
  final line = StringBuffer(
    'Assumed: $trays in $where that no face photo counts, each set to '
    '${_basisWords(split.assumedFrom)}.',
  );
  if (split.topChecked != null && hidden != null && hidden > 0) {
    line.write(' ${split.topChecked} of $hidden checked from the top.');
  }
  if (split.stepUps > 0) {
    line.write(
      ' ${_plural(split.stepUps, 'stack', 'stacks')} tapped taller from the '
      'top: open above.',
    );
  }
  line.write(' A hidden stack can be missing, shorter or taller.');
  return line.toString();
}

/// Egg occupancy is known only when declared; otherwise it was not checked.
String eggFilledLine(BlockInventory? inventory) {
  final eligible = inventory?.eligibleEggTrays;
  if (eligible?.value case final value?) {
    return 'Egg-filled trays: $value (${eligible!.basis})';
  }
  return 'Egg-filled trays: not checked';
}

/// Why a block has no total, in the operator's words.
String withheldWords(String? reason, {String? status}) =>
    switch (reason ?? status) {
      'height_unknown' => "a hidden stack's height is unknown",
      'conflict' => 'the readings disagree; retake the named face',
      'needs_view' => 'a photo is missing or was refused',
      'depth_unproven' => 'the depth is not proven; declare the block size',
      'side_repeats_front' =>
        'a side photo repeats the front; add a CORNER photo',
      _ => 'the photos do not settle the block',
    };

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
    final split = block.split;
    final status = block.displayStatus;
    final assumed = split?.assumed;
    final stacks = split?.assumedStacks;
    final hasAssumed =
        split != null && (assumed == null || assumed > 0 || (stacks ?? 0) > 0);
    final inStacks = stacks == null
        ? 'IN HIDDEN STACKS'
        : 'IN ${_plural(stacks, 'HIDDEN STACK', 'HIDDEN STACKS')}';
    final (headline, color) = switch (status) {
      kBlockExact => ('EVERY STACK SEEN BY TWO PHOTOS', kObserved),
      kBlockEstimated ||
      kBlockConfirmed when split != null && !split.released => (
        'TOTAL WITHHELD: '
            '${withheldWords(block.withheldReason, status: 'height_unknown').toUpperCase()}',
        kRescan,
      ),
      // Counted and assumed always side by side; never "exact" or
      // "confirmed" for a total that includes assumed stacks.
      kBlockEstimated || kBlockConfirmed when hasAssumed => (
        'ESTIMATE: ${split.counted} COUNTED + ${assumed ?? '?'} ASSUMED '
            '$inStacks',
        kComputed,
      ),
      // A 0.5 server's stronger label, shown as the estimate it is.
      kBlockConfirmed => ('ESTIMATE (OLDER SERVER)', kComputed),
      kBlockEstimated when single > 0 => (
        'ESTIMATE: $single TRAYS SEEN BY ONE PHOTO ONLY',
        kComputed,
      ),
      kBlockEstimated => ('ESTIMATE: A READING IS UNCERTAIN', kComputed),
      'needs_view'
          when block.provisional != null ||
              block.suggestedInputs.contains('declaration') =>
        ('NO TOTAL YET', kRescan),
      'needs_view' => ('RETAKE A PHOTO', kRescan),
      _ => ('RESCAN REQUIRED', kRescan),
    };
    final gridModel = block.hasGridModel;
    final drawn = gridModel || block.hasGrid;
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
              key: const ValueKey('block-headline'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            if (block.status == kBlockConfirmed) ...[
              const SizedBox(height: 4),
              Text(
                'An older server gave this block a stronger label. Its hidden '
                'stacks were never counted, so it is shown as an estimate.',
                key: const ValueKey('older-label-note'),
                textAlign: TextAlign.center,
                style: small,
              ),
            ],
            if (block.suggestedInputs.contains('declaration')) ...[
              const SizedBox(height: 6),
              Text(
                'DECLARE THE BLOCK SIZE AND SCAN AGAIN',
                key: const ValueKey('declare-size'),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
            if (block.provisional case final provisional?) ...[
              const SizedBox(height: 10),
              _ProvisionalPanel(provisional),
            ],
            if (drawn) ...[
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
              _EvidenceLegend(block.evidence),
              const SizedBox(height: 10),
              ..._summary(theme, small, split),
              const Divider(height: 24),
              _Row(
                gridModel ? 'Block (grid model)' : 'Block',
                gridModel
                    ? '${block.gridWidth} wide × ${block.gridDepth} deep'
                    : '${block.width} wide × ${block.depth} deep',
              ),
              if (block.visibleVerifiedTrays != null) ...[
                _Row('Seen by two photos', '${block.visibleVerifiedTrays}'),
                _Row('Seen by one photo only', '$single'),
              ],
              ..._countRows(split),
              // No eggs row: occupancy is not measured, and a block is reported
              // in tray layers only (user decision, 3 Nov 2026).
              if (!gridModel && block.filledTrays > 0)
                _Row('Layers between detected boxes', '${block.filledTrays}'),
              if (gridModel && inventory != null) ..._inventoryRows(inventory),
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

  /// The split line (or why there is no total), what the assumed part rests
  /// on, and the egg occupancy.
  List<Widget> _summary(ThemeData theme, TextStyle? small, TraySplit? split) {
    final eligible = block.inventory?.eligibleEggTrays;
    final bold = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w900,
    );
    return [
      if (split != null && split.released)
        Text(
          traySplitLine(split, status: block.displayStatus),
          key: const ValueKey('tray-split'),
          textAlign: TextAlign.center,
          style: bold,
        )
      else if (block.provisional == null)
        Text(
          split == null
              ? 'TOTAL WITHHELD: '
                    '${withheldWords(block.withheldReason, status: block.status)}'
              : 'Counted ${split.counted} on faces (at least); TOTAL '
                    'WITHHELD: '
                    '${withheldWords(block.withheldReason, status: 'height_unknown')}',
          key: const ValueKey('total-withheld'),
          textAlign: TextAlign.center,
          style: bold,
        ),
      if (split != null) ...[
        const SizedBox(height: 4),
        Text(
          assumptionLine(split),
          key: const ValueKey('assumption-line'),
          textAlign: TextAlign.center,
          style: small,
        ),
      ],
      const SizedBox(height: 4),
      Text(
        eggFilledLine(block.inventory),
        key: const ValueKey('egg-filled-line'),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      if (eligible?.note case final note? when note.isNotEmpty)
        Text(note, textAlign: TextAlign.center, style: small),
    ];
  }

  /// Counted and assumed trays kept apart; the range is labelled with what
  /// it means and never printed bare.
  List<Widget> _countRows(TraySplit? split) {
    if (split == null) return const [];
    final assumed = split.assumed;
    final stacks = split.assumedStacks;
    final hasAssumed = assumed == null || assumed > 0 || (stacks ?? 0) > 0;
    final range = split.estimatedRange;
    final exact = block.displayStatus == kBlockExact;
    return [
      _Row(
        'Counted on faces',
        exact ? '${split.counted}' : '${split.counted} (at least)',
        key: const ValueKey('counted-row'),
      ),
      if (hasAssumed)
        _Row(
          stacks == null
              ? 'Assumed in hidden stacks'
              : 'Assumed in ${_plural(stacks, 'hidden stack', 'hidden stacks')}',
          // The top-checked count also covers stacks tapped missing, so it is
          // stated against all hidden stacks in the assumption line instead.
          '${assumed ?? 'unknown'}',
          key: const ValueKey('assumed-row'),
        ),
      if (split.released)
        _Row(
          exact ? 'Total' : 'Estimate',
          '${split.estimated}',
          key: const ValueKey('estimate-row'),
        ),
      // A withheld block shows no whole-block figure, the range included.
      if (range != null && hasAssumed && split.released)
        _Row(
          "If every hidden stack is there at its neighbours' heights",
          rangeWords(range),
          key: const ValueKey('range-row'),
        ),
    ];
  }

  /// Occupancy and covers, with what they rest on (measured, declared or
  /// unknown).
  List<Widget> _inventoryRows(BlockInventory inventory) {
    String n(int? value) => value == null ? '—' : '$value';
    final cover = inventory.emptyCoverLayers;
    return [
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
          '${top.cellsMissing ?? '—'} missing, ${top.steps ?? '—'} steps. '
          'It finds holes and taller stacks; it never counts trays.',
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

/// Figures for a block whose depth is not proven. They are not a total: never
/// in the headline, the history, an export or the manual count.
class _ProvisionalPanel extends StatelessWidget {
  const _ProvisionalPanel(this.provisional);

  final ProvisionalFigures provisional;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ifDepth = provisional.ifDepth;
    return Container(
      key: const ValueKey('provisional-panel'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            provisional.kind == 'side_repeats_front'
                ? 'NOT RELEASED: A SIDE REPEATS THE FRONT'
                : 'NOT RELEASED: DEPTH NOT PROVEN',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          if (provisional.reason case final reason? when reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(reason, style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 6),
          Text(
            'Front row counted: '
            '${provisional.frontRowCounted ?? 'not readable'}',
          ),
          if (ifDepth != null)
            Text(
              'Only if the block is ${ifDepth.y ?? '?'} deep: '
              '${ifDepth.countedTrays ?? '?'} counted + '
              '${ifDepth.assumedTrays ?? '?'} assumed ≈ '
              '${ifDepth.estimatedTotal ?? '?'}',
              key: const ValueKey('provisional-if-depth'),
            ),
          const SizedBox(height: 4),
          Text(
            'These figures are not a total.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
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

/// One entry per kind of stack in this block, each with its drawing.
class _EvidenceLegend extends StatelessWidget {
  const _EvidenceLegend(this.cells);

  final List<CellEvidence> cells;

  @override
  Widget build(BuildContext context) {
    final entries = <String, CellLook>{};
    final ordered = [...cells]
      ..sort((a, b) => a.evidenceClass.index.compareTo(b.evidenceClass.index));
    for (final c in ordered) {
      entries.putIfAbsent(evidenceLegendLabel(c), () => cellLook(c));
    }
    return Wrap(
      key: const ValueKey('evidence-legend'),
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final e in entries.entries) _Legend(look: e.value, label: e.key),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.look, required this.label});

  final CellLook look;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CustomPaint(size: const Size(12, 12), painter: _Swatch(look)),
      const SizedBox(width: 4),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

/// A legend square drawn the way the block draws that kind of stack.
class _Swatch extends CustomPainter {
  _Swatch(this.look);

  final CellLook look;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final color = look.color;
    switch (look.shape) {
      case CellShape.solid:
        canvas.drawRect(rect, Paint()..color = color);
      case CellShape.ghost:
        canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.25));
        canvas.drawRect(
          rect.deflate(0.5),
          Paint()
            ..color = look.edge ?? color
            ..style = PaintingStyle.stroke
            ..strokeWidth = look.edge == null ? 1 : 2,
        );
      case CellShape.footprint:
        canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.2));
        canvas.drawRect(
          rect.deflate(0.75),
          Paint()
            ..color = look.edge ?? color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      case CellShape.dashedFootprint:
        final dash = Paint()
          ..color = color
          ..strokeWidth = 1.5;
        for (var t = 0.0; t < size.width; t += 4) {
          final end = math.min(t + 2, size.width);
          canvas.drawLine(Offset(t, 0.75), Offset(end, 0.75), dash);
          canvas.drawLine(
            Offset(t, size.height - 0.75),
            Offset(end, size.height - 0.75),
            dash,
          );
          canvas.drawLine(Offset(0.75, t), Offset(0.75, end), dash);
          canvas.drawLine(
            Offset(size.width - 0.75, t),
            Offset(size.width - 0.75, end),
            dash,
          );
        }
    }
  }

  @override
  bool shouldRepaint(covariant _Swatch old) => old.look != look;
}
