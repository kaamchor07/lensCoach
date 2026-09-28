import 'package:flutter/material.dart';
import 'package:lenscoach/utils/scoring.dart';

/// ShutterButton — Animated capture button with confidence tier states.
///
/// Visual states per Section 2.5:
/// - Low (0.0–0.49): White ring, no haptic
/// - Medium (0.50–0.74): Amber pulse (0.8s cycle), no haptic
/// - Good (0.75–0.89): Green glow, single soft tick
/// - Excellent (0.90–1.00): Bright green glow + ring expand, double tick
class ShutterButton extends StatefulWidget {
  final ScoreTier tier;
  final double score;
  final VoidCallback onCapture;

  const ShutterButton({
    super.key,
    required this.tier,
    required this.score,
    required this.onCapture,
  });

  @override
  State<ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<ShutterButton>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _pressController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _pressAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _pressController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _pressAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );

    _updatePulse();
  }

  @override
  void didUpdateWidget(covariant ShutterButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tier != widget.tier) {
      _updatePulse();
    }
  }

  void _updatePulse() {
    if (widget.tier == ScoreTier.medium) {
      _pulseController.repeat(reverse: true);
    } else if (widget.tier == ScoreTier.excellent) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  Color get _ringColor {
    switch (widget.tier) {
      case ScoreTier.low:
        return Colors.white;
      case ScoreTier.medium:
        return const Color(0xFFFFAB00);
      case ScoreTier.good:
        return const Color(0xFF00E676);
      case ScoreTier.excellent:
        return const Color(0xFF00E676);
    }
  }

  double get _ringWidth {
    switch (widget.tier) {
      case ScoreTier.low:
        return 3.0;
      case ScoreTier.medium:
        return 3.5;
      case ScoreTier.good:
        return 4.0;
      case ScoreTier.excellent:
        return 5.0;
    }
  }

  List<BoxShadow> get _glowShadows {
    if (widget.tier == ScoreTier.good || widget.tier == ScoreTier.excellent) {
      return [
        BoxShadow(
          color: _ringColor.withValues(alpha: 0.4),
          blurRadius: widget.tier == ScoreTier.excellent ? 20 : 12,
          spreadRadius: widget.tier == ScoreTier.excellent ? 4 : 2,
        ),
      ];
    }
    return [];
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressController.forward(),
      onTapUp: (_) {
        _pressController.reverse();
        widget.onCapture();
      },
      onTapCancel: () => _pressController.reverse(),
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseAnimation, _pressAnimation]),
        builder: (context, child) {
          final scale = (_pulseController.isAnimating
                  ? _pulseAnimation.value
                  : 1.0) *
              _pressAnimation.value;

          return Transform.scale(
            scale: scale,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _ringColor,
                  width: _ringWidth,
                ),
                boxShadow: _glowShadows,
              ),
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
