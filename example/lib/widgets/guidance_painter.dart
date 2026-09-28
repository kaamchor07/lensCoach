import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lenscoach/models/guidance_payload.dart';

/// GuidancePainter — Renders composition guidance overlays on the viewfinder.
///
/// Draws:
/// - Directional arrows from subject centroid to target zone
/// - Text nudges ("Move closer", "Step back", "Background too busy")
/// - Subject highlight outline (dotted when confidence < threshold)
/// - Target zone highlight
class GuidancePainter extends CustomPainter {
  final GuidancePayload? guidance;
  final double opacity;
  final bool showSubjectOutline;
  final double? bboxLeft;
  final double? bboxTop;
  final double? bboxRight;
  final double? bboxBottom;
  final double maskConfidence;

  GuidancePainter({
    this.guidance,
    this.opacity = 0.8,
    this.showSubjectOutline = false,
    this.bboxLeft,
    this.bboxTop,
    this.bboxRight,
    this.bboxBottom,
    this.maskConfidence = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (guidance == null || opacity <= 0.01) return;

    final w = size.width;
    final h = size.height;

    // Draw subject bounding box outline
    if (showSubjectOutline && bboxLeft != null) {
      _drawSubjectOutline(canvas, w, h);
    }

    // Draw guidance arrows and warnings
    for (final warning in guidance!.warnings) {
      switch (warning.type) {
        case WarningType.placement:
          _drawPlacementArrow(canvas, w, h, warning);
          break;
        case WarningType.size:
          _drawSizeNudge(canvas, w, h, warning);
          break;
        case WarningType.background:
          _drawBackgroundWarning(canvas, w, h, warning);
          break;
        case WarningType.focus:
          _drawFocusWarning(canvas, w, h, warning);
          break;
        case WarningType.lighting:
          _drawLightingWarning(canvas, w, h, warning);
          break;
      }
    }
  }

  void _drawSubjectOutline(Canvas canvas, double w, double h) {
    final rect = Rect.fromLTRB(
      bboxLeft! * w,
      bboxTop! * h,
      bboxRight! * w,
      bboxBottom! * h,
    );

    if (maskConfidence >= 0.6) {
      // Solid outline — confident segmentation
      final paint = Paint()
        ..color = const Color(0xFF00E676).withValues(alpha: opacity * 0.6)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        paint,
      );
    } else {
      // Dotted outline — low confidence per spec
      final paint = Paint()
        ..color = const Color(0xFFFFAB00).withValues(alpha: opacity * 0.6)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      _drawDashedRect(canvas, rect, paint, 6, 4);
    }
  }

  void _drawPlacementArrow(
      Canvas canvas, double w, double h, GuidanceWarning warning) {
    final from = Offset(warning.arrowFromX * w, warning.arrowFromY * h);
    final to = Offset(warning.arrowToX * w, warning.arrowToY * h);

    final arrowPaint = Paint()
      ..color = const Color(0xFF00E676).withValues(alpha: opacity)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Draw arrow shaft
    canvas.drawLine(from, to, arrowPaint);

    // Draw arrowhead
    final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
    const headLength = 16.0;
    const headAngle = 0.5;

    final head1 = Offset(
      to.dx - headLength * math.cos(angle - headAngle),
      to.dy - headLength * math.sin(angle - headAngle),
    );
    final head2 = Offset(
      to.dx - headLength * math.cos(angle + headAngle),
      to.dy - headLength * math.sin(angle + headAngle),
    );

    final headPaint = Paint()
      ..color = const Color(0xFF00E676).withValues(alpha: opacity)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(head1.dx, head1.dy)
      ..lineTo(head2.dx, head2.dy)
      ..close();
    canvas.drawPath(path, headPaint);
  }

  void _drawSizeNudge(
      Canvas canvas, double w, double h, GuidanceWarning warning) {
    _drawTextLabel(
      canvas,
      warning.message,
      Offset(w / 2, h * 0.85),
      const Color(0xFFFFAB00),
    );
  }

  void _drawBackgroundWarning(
      Canvas canvas, double w, double h, GuidanceWarning warning) {
    _drawTextLabel(
      canvas,
      warning.message,
      Offset(w / 2, h * 0.12),
      const Color(0xFFFF1744),
    );
  }

  void _drawFocusWarning(
      Canvas canvas, double w, double h, GuidanceWarning warning) {
    _drawTextLabel(
      canvas,
      warning.message,
      Offset(w / 2, h * 0.88),
      const Color(0xFFFFAB00),
    );
  }

  void _drawLightingWarning(
      Canvas canvas, double w, double h, GuidanceWarning warning) {
    _drawTextLabel(
      canvas,
      warning.message,
      Offset(w / 2, h * 0.15),
      const Color(0xFFFFAB00),
    );
  }

  void _drawTextLabel(
      Canvas canvas, String text, Offset position, Color color) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color.withValues(alpha: opacity),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final bgRect = Rect.fromCenter(
      center: position,
      width: textPainter.width + 20,
      height: textPainter.height + 10,
    );

    final bgPaint = Paint()
      ..color = Colors.black.withValues(alpha: opacity * 0.6)
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(6)),
      bgPaint,
    );

    textPainter.paint(
      canvas,
      Offset(
        position.dx - textPainter.width / 2,
        position.dy - textPainter.height / 2,
      ),
    );
  }

  void _drawDashedRect(
      Canvas canvas, Rect rect, Paint paint, double dash, double gap) {
    final perimeter = [
      [rect.topLeft, rect.topRight],
      [rect.topRight, rect.bottomRight],
      [rect.bottomRight, rect.bottomLeft],
      [rect.bottomLeft, rect.topLeft],
    ];

    for (final side in perimeter) {
      _drawDashedLine(canvas, side[0], side[1], paint, dash, gap);
    }
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
    double dashLength,
    double gapLength,
  ) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final totalLength = math.sqrt(dx * dx + dy * dy);
    final unitDx = dx / totalLength;
    final unitDy = dy / totalLength;

    double distance = 0;
    bool drawing = true;

    while (distance < totalLength) {
      final segLength = drawing
          ? math.min(dashLength, totalLength - distance)
          : math.min(gapLength, totalLength - distance);

      if (drawing) {
        canvas.drawLine(
          Offset(start.dx + unitDx * distance, start.dy + unitDy * distance),
          Offset(start.dx + unitDx * (distance + segLength),
              start.dy + unitDy * (distance + segLength)),
          paint,
        );
      }

      distance += segLength;
      drawing = !drawing;
    }
  }

  @override
  bool shouldRepaint(covariant GuidancePainter oldDelegate) {
    return oldDelegate.guidance != guidance ||
        oldDelegate.opacity != opacity ||
        oldDelegate.showSubjectOutline != showSubjectOutline;
  }
}
