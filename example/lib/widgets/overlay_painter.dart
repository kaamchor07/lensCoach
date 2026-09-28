import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lenscoach/models/scene_type.dart';

/// OverlayPainter — Renders composition grids and guides on top of the camera preview.
///
/// Implements the full Scene-to-Overlay Matrix from Section 2.3:
/// - Rule of Thirds (horizontal, vertical, full)
/// - Golden Ratio grid
/// - Golden Spiral (Fibonacci)
/// - Horizon line
/// - Centre cross
/// - Diagonal guides
/// - Perspective grid / vanishing point
/// - Symmetry axis
///
/// Each scene type maps to specific primary + secondary overlays.
class OverlayPainter extends CustomPainter {
  final SceneType sceneType;
  final int styleIndex; // 0 = primary, 1 = secondary, 2 = all
  final double opacity;
  final double horizonAngle; // degrees from level

  OverlayPainter({
    required this.sceneType,
    required this.styleIndex,
    required this.opacity,
    this.horizonAngle = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.01) return;

    final w = size.width;
    final h = size.height;

    // Base paint style
    final primaryPaint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final secondaryPaint = Paint()
      ..color = Colors.white.withValues(alpha: opacity * 0.6)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    final accentPaint = Paint()
      ..color = const Color(0xFF00E676).withValues(alpha: opacity * 0.8)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw overlays based on scene type and style index
    switch (sceneType) {
      case SceneType.landscape:
        _drawRuleOfThirdsHorizontal(canvas, w, h, primaryPaint);
        _drawHorizonLine(canvas, w, h, accentPaint);
        if (styleIndex >= 1) {
          _drawGoldenRatioHorizontal(canvas, w, h, secondaryPaint);
        }
        break;

      case SceneType.architecture:
        _drawPerspectiveGrid(canvas, w, h, primaryPaint);
        _drawVerticalThirds(canvas, w, h, primaryPaint);
        if (styleIndex >= 1) {
          _drawGoldenRatio(canvas, w, h, secondaryPaint);
          _drawSymmetryAxis(canvas, w, h, secondaryPaint);
        }
        break;

      case SceneType.portrait:
        _drawVerticalThirds(canvas, w, h, primaryPaint);
        _drawFaceZone(canvas, w, h, accentPaint);
        if (styleIndex >= 1) {
          _drawGoldenSpiral(canvas, w, h, secondaryPaint);
        }
        break;

      case SceneType.street:
        _drawRuleOfThirds(canvas, w, h, primaryPaint);
        _drawDiagonalGuides(canvas, w, h, secondaryPaint);
        if (styleIndex >= 1) {
          _drawLeadingLines(canvas, w, h, secondaryPaint);
        }
        break;

      case SceneType.macro:
        _drawCentreCross(canvas, w, h, primaryPaint);
        _drawGoldenSpiral(canvas, w, h, primaryPaint);
        if (styleIndex >= 1) {
          _drawRuleOfThirds(canvas, w, h, secondaryPaint);
        }
        break;

      case SceneType.lowLight:
        _drawRuleOfThirds(canvas, w, h, primaryPaint);
        // Minimal overlays for low-light per spec
        break;
    }

    // Always draw horizon level indicator
    _drawHorizonIndicator(canvas, w, h, accentPaint);
  }

  // ─── Grid Implementations ──────────────────────────────────────────────────

  /// Rule of Thirds — full grid (2 horizontal + 2 vertical lines)
  void _drawRuleOfThirds(Canvas canvas, double w, double h, Paint paint) {
    final thirdW = w / 3;
    final thirdH = h / 3;

    // Vertical lines
    canvas.drawLine(Offset(thirdW, 0), Offset(thirdW, h), paint);
    canvas.drawLine(Offset(thirdW * 2, 0), Offset(thirdW * 2, h), paint);

    // Horizontal lines
    canvas.drawLine(Offset(0, thirdH), Offset(w, thirdH), paint);
    canvas.drawLine(Offset(0, thirdH * 2), Offset(w, thirdH * 2), paint);

    // Intersection dots
    final dotPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;
    for (int i = 1; i <= 2; i++) {
      for (int j = 1; j <= 2; j++) {
        canvas.drawCircle(Offset(thirdW * i, thirdH * j), 3, dotPaint);
      }
    }
  }

  /// Rule of Thirds — horizontal lines only (for landscape)
  void _drawRuleOfThirdsHorizontal(
      Canvas canvas, double w, double h, Paint paint) {
    final thirdH = h / 3;
    canvas.drawLine(Offset(0, thirdH), Offset(w, thirdH), paint);
    canvas.drawLine(Offset(0, thirdH * 2), Offset(w, thirdH * 2), paint);
  }

  /// Vertical thirds only (for portrait/architecture)
  void _drawVerticalThirds(Canvas canvas, double w, double h, Paint paint) {
    final thirdW = w / 3;
    canvas.drawLine(Offset(thirdW, 0), Offset(thirdW, h), paint);
    canvas.drawLine(Offset(thirdW * 2, 0), Offset(thirdW * 2, h), paint);
  }

  /// Golden Ratio grid — full
  void _drawGoldenRatio(Canvas canvas, double w, double h, Paint paint) {
    const phi = 1.618;
    final gw = w / (1 + phi);
    final gh = h / (1 + phi);

    canvas.drawLine(Offset(gw, 0), Offset(gw, h), paint);
    canvas.drawLine(Offset(w - gw, 0), Offset(w - gw, h), paint);
    canvas.drawLine(Offset(0, gh), Offset(w, gh), paint);
    canvas.drawLine(Offset(0, h - gh), Offset(w, h - gh), paint);
  }

  /// Golden Ratio — horizontal only (for landscape)
  void _drawGoldenRatioHorizontal(
      Canvas canvas, double w, double h, Paint paint) {
    const phi = 1.618;
    final gh = h / (1 + phi);
    canvas.drawLine(Offset(0, gh), Offset(w, gh), paint);
    canvas.drawLine(Offset(0, h - gh), Offset(w, h - gh), paint);
  }

  /// Golden Spiral (Fibonacci approximation)
  void _drawGoldenSpiral(Canvas canvas, double w, double h, Paint paint) {
    const phi = 1.618;

    // Draw a simplified Fibonacci spiral using arcs
    double rectW = w;
    double rectH = h;
    double x = 0;
    double y = 0;

    for (int i = 0; i < 6; i++) {
      final size = i % 2 == 0 ? rectH / phi : rectW / phi;

      switch (i % 4) {
        case 0:
          canvas.drawArc(
            Rect.fromLTWH(x, y, size * 2, size * 2),
            math.pi,
            math.pi / 2,
            false,
            paint,
          );
          rectH -= size;
          y += size;
          break;
        case 1:
          canvas.drawArc(
            Rect.fromLTWH(x - size, y, size * 2, size * 2),
            -math.pi / 2,
            math.pi / 2,
            false,
            paint,
          );
          rectW -= size;
          break;
        case 2:
          canvas.drawArc(
            Rect.fromLTWH(x - size, y - size, size * 2, size * 2),
            0,
            math.pi / 2,
            false,
            paint,
          );
          rectH -= size;
          break;
        case 3:
          canvas.drawArc(
            Rect.fromLTWH(x, y - size, size * 2, size * 2),
            math.pi / 2,
            math.pi / 2,
            false,
            paint,
          );
          rectW -= size;
          x += size;
          break;
      }
    }
  }

  /// Horizon line at the level position
  void _drawHorizonLine(Canvas canvas, double w, double h, Paint paint) {
    final centerY = h / 2;
    final angle = horizonAngle * math.pi / 180;
    final dx = w / 2 * math.cos(angle);
    final dy = w / 2 * math.sin(angle);

    canvas.drawLine(
      Offset(w / 2 - dx, centerY + dy),
      Offset(w / 2 + dx, centerY - dy),
      paint,
    );
  }

  /// Centre cross (for macro)
  void _drawCentreCross(Canvas canvas, double w, double h, Paint paint) {
    final cx = w / 2;
    final cy = h / 2;
    final size = math.min(w, h) * 0.08;

    // Horizontal
    canvas.drawLine(Offset(cx - size, cy), Offset(cx + size, cy), paint);
    // Vertical
    canvas.drawLine(Offset(cx, cy - size), Offset(cx, cy + size), paint);
  }

  /// Diagonal guides (for street)
  void _drawDiagonalGuides(Canvas canvas, double w, double h, Paint paint) {
    // Main diagonals
    canvas.drawLine(const Offset(0, 0), Offset(w, h), paint);
    canvas.drawLine(Offset(w, 0), Offset(0, h), paint);
  }

  /// Leading lines suggestion (simplified — drawn from bottom corners to thirds)
  void _drawLeadingLines(Canvas canvas, double w, double h, Paint paint) {
    final thirdW = w / 3;
    final thirdH = h / 3;

    // From bottom-left to right-third intersection
    canvas.drawLine(Offset(0, h), Offset(thirdW * 2, thirdH), paint);
    // From bottom-right to left-third intersection
    canvas.drawLine(Offset(w, h), Offset(thirdW, thirdH), paint);
  }

  /// Perspective grid (for architecture)
  void _drawPerspectiveGrid(Canvas canvas, double w, double h, Paint paint) {
    final cx = w / 2;
    final vpY = h * 0.35; // vanishing point in upper third

    // Vanishing point dot
    final dotPaint = Paint()
      ..color = const Color(0xFF00E676).withValues(alpha: opacity)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, vpY), 4, dotPaint);

    // Lines radiating from vanishing point
    canvas.drawLine(Offset(cx, vpY), Offset(0, h), paint);
    canvas.drawLine(Offset(cx, vpY), Offset(w, h), paint);
    canvas.drawLine(Offset(cx, vpY), Offset(w * 0.25, h), paint);
    canvas.drawLine(Offset(cx, vpY), Offset(w * 0.75, h), paint);

    // Horizontal reference lines
    final hStep = (h - vpY) / 4;
    for (int i = 1; i <= 3; i++) {
      final y = vpY + hStep * i;
      canvas.drawLine(Offset(0, y), Offset(w, y), paint..strokeWidth = 0.4);
    }
  }

  /// Symmetry axis (for architecture)
  void _drawSymmetryAxis(Canvas canvas, double w, double h, Paint paint) {
    final cx = w / 2;
    // Dashed vertical center line
    _drawDashedLine(
        canvas, Offset(cx, 0), Offset(cx, h), paint, 8, 4);
  }

  /// Face zone highlight (for portrait — upper-middle area)
  void _drawFaceZone(Canvas canvas, double w, double h, Paint paint) {
    final rect = Rect.fromLTRB(
      w * 0.25,
      h * 0.15,
      w * 0.75,
      h * 0.45,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    canvas.drawRRect(rrect, paint..strokeWidth = 0.6);
  }

  /// Horizon level indicator — small level bubble at top center
  void _drawHorizonIndicator(Canvas canvas, double w, double h, Paint paint) {
    final cx = w / 2;
    final y = 60.0;
    final indicatorWidth = 60.0;

    // Background track
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: opacity * 0.3)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(cx - indicatorWidth / 2, y),
      Offset(cx + indicatorWidth / 2, y),
      trackPaint,
    );

    // Center mark
    canvas.drawLine(
      Offset(cx, y - 4),
      Offset(cx, y + 4),
      trackPaint,
    );

    // Level bubble (offset by horizon angle)
    final bubbleOffset = (horizonAngle / 45.0).clamp(-1.0, 1.0) *
        (indicatorWidth / 2);
    final isLevel = horizonAngle.abs() < 1.5;
    final bubblePaint = Paint()
      ..color = isLevel
          ? const Color(0xFF00E676).withValues(alpha: opacity)
          : Colors.white.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(cx + bubbleOffset, y), 4, bubblePaint);
  }

  // ─── Utility ────────────────────────────────────────────────────────────────

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
          Offset(
              start.dx + unitDx * distance, start.dy + unitDy * distance),
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
  bool shouldRepaint(covariant OverlayPainter oldDelegate) {
    return oldDelegate.sceneType != sceneType ||
        oldDelegate.styleIndex != styleIndex ||
        oldDelegate.opacity != opacity ||
        oldDelegate.horizonAngle != horizonAngle;
  }
}
