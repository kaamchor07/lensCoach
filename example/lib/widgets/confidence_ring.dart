import 'package:flutter/material.dart';

/// ConfidenceRing — Not used as a standalone widget.
/// Confidence display is integrated into ShutterButton via its tier-based ring.
/// This file is a placeholder for potential standalone confidence indicator usage.
///
/// See shutter_button.dart for the actual confidence ring implementation.
class ConfidenceRing extends StatelessWidget {
  final double score;

  const ConfidenceRing({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
