import 'package:flutter/material.dart';

import '../../models/capture_view.dart';
import '../../services/frame_preflight.dart';

/// Framing guide whose colour is the live preflight verdict, so the operator
/// sees the same judgement as the text banner without reading it.
///
/// The guide rectangle below is the bounding box the analyser measures: left
/// and right views are trapezoids inset by 10% on one edge, and the analyser
/// treats them as their bounding rectangle. That is deliberate, and it is why
/// angled views rely on the ANGLE hint rather than on a hard geometry test.
class CameraGuideOverlay extends StatelessWidget {
  const CameraGuideOverlay({
    required this.view,
    required this.severity,
    super.key,
  });

  final CaptureView view;
  final PreflightSeverity severity;

  @override
  Widget build(BuildContext context) {
    final color = switch (severity) {
      PreflightSeverity.blocking => Colors.redAccent,
      PreflightSeverity.advisory => Colors.amberAccent,
      PreflightSeverity.pass => Colors.greenAccent,
    };
    return IgnorePointer(
      child: CustomPaint(
        painter: _GuidePainter(view, color),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter(this.view, this.color);

  final CaptureView view;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Rect.fromLTWH(
      size.width * 0.10,
      size.height * 0.10,
      size.width * 0.80,
      size.height * 0.78,
    );
    final inset = size.width * 0.10;
    final guidePath = Path();
    switch (view) {
      case CaptureView.left:
        guidePath
          ..moveTo(bounds.left + inset, bounds.top)
          ..lineTo(bounds.right, bounds.top)
          ..lineTo(bounds.right - inset, bounds.bottom)
          ..lineTo(bounds.left, bounds.bottom)
          ..close();
      case CaptureView.right:
        guidePath
          ..moveTo(bounds.left, bounds.top)
          ..lineTo(bounds.right - inset, bounds.top)
          ..lineTo(bounds.right, bounds.bottom)
          ..lineTo(bounds.left + inset, bounds.bottom)
          ..close();
      case CaptureView.straight:
        guidePath.addRRect(
          RRect.fromRectAndRadius(bounds, const Radius.circular(22)),
        );
    }
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.36)
      ..style = PaintingStyle.fill;
    final cutout = Path()
      ..addRect(Offset.zero & size)
      ..addPath(guidePath, Offset.zero)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(cutout, shadow);

    final line = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawPath(guidePath, line);
    final guide = Paint()
      ..color = color.withValues(alpha: 0.72)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(bounds.left, bounds.top + bounds.height * 0.10),
      Offset(bounds.right, bounds.top + bounds.height * 0.10),
      guide,
    );
    canvas.drawLine(
      Offset(bounds.left, bounds.bottom - bounds.height * 0.10),
      Offset(bounds.right, bounds.bottom - bounds.height * 0.10),
      guide,
    );
    final base = Paint()
      ..color = color
      ..strokeWidth = 4;
    canvas.drawLine(
      Offset(bounds.left, bounds.bottom),
      Offset(bounds.right, bounds.bottom),
      base,
    );
  }

  @override
  bool shouldRepaint(_GuidePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.view != view;
}
