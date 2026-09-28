import 'package:flutter/material.dart';
import 'package:lenscoach/models/hud_state.dart';

/// HudBar — 3-slot persistent HUD anchored above the shutter button.
///
/// Each slot shows: parameter name (small), current value (large), status dot (colored).
/// Tapping a slot expands an inline tooltip that auto-collapses after 3 seconds.
class HudBar extends StatelessWidget {
  final HudState hudState;

  const HudBar({super.key, required this.hudState});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(child: _HudSlotWidget(slot: hudState.slot1)),
          _divider(),
          Expanded(child: _HudSlotWidget(slot: hudState.slot2)),
          _divider(),
          Expanded(child: _HudSlotWidget(slot: hudState.slot3)),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 36,
      color: Colors.white12,
    );
  }
}

class _HudSlotWidget extends StatefulWidget {
  final HudSlot slot;

  const _HudSlotWidget({required this.slot});

  @override
  State<_HudSlotWidget> createState() => _HudSlotWidgetState();
}

class _HudSlotWidgetState extends State<_HudSlotWidget> {
  bool _expanded = false;

  Color get _statusColor {
    switch (widget.slot.status) {
      case HudStatus.green:
        return const Color(0xFF00E676);
      case HudStatus.amber:
        return const Color(0xFFFFAB00);
      case HudStatus.red:
        return const Color(0xFFFF1744);
    }
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _expanded = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleExpanded,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Label + status dot
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.slot.label,
                  style: TextStyle(
                    color: _statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _statusColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _statusColor.withValues(alpha: 0.5),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            // Value
            Text(
              widget.slot.value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            // Expandable tooltip
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  widget.slot.tooltip,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10,
                    height: 1.3,
                  ),
                ),
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }
}
