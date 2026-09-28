import 'package:flutter/material.dart';
import 'package:lenscoach/models/scene_type.dart';

/// SceneSelector — Horizontal scrollable scene type picker.
///
/// Allows manual toggle between 6 scene types.
/// In Phase 2, this becomes a secondary control (classifier is primary).
class SceneSelector extends StatelessWidget {
  final SceneType currentScene;
  final ValueChanged<SceneType> onSceneChanged;

  const SceneSelector({
    super.key,
    required this.currentScene,
    required this.onSceneChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: SceneType.values.length,
        separatorBuilder: (context, i) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final scene = SceneType.values[index];
          final isSelected = scene == currentScene;

          return GestureDetector(
            onTap: () => onSceneChanged(scene),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF00E676).withValues(alpha: 0.2)
                    : Colors.black38,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF00E676)
                      : Colors.white24,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    scene.icon,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    scene.displayName,
                    style: TextStyle(
                      color: isSelected ? const Color(0xFF00E676) : Colors.white60,
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
