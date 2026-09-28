/// LensCoach — Confidence Scoring
///
/// Composite "Perfect Shot" scoring function per Section 2.5.
/// Aggregates composition, settings, and focus into a single confidence score.
library;

import 'package:lenscoach/utils/constants.dart';

/// Score tiers for shutter button state and haptic feedback.
enum ScoreTier {
  /// 0.0–0.49: Default white ring, no haptic.
  low,

  /// 0.50–0.74: Amber pulse (0.8s cycle), no haptic.
  medium,

  /// 0.75–0.89: Green glow, single soft tick.
  good,

  /// 0.90–1.00: Bright green glow + ring expand, double tick.
  excellent;

  static ScoreTier fromScore(double score) {
    if (score >= scoreTierHigh) return ScoreTier.excellent;
    if (score >= scoreTierMid) return ScoreTier.good;
    if (score >= scoreTierLow) return ScoreTier.medium;
    return ScoreTier.low;
  }
}

/// Computes the weighted confidence score.
///
/// - [compositionScore]: 0.0–1.0, from CompositionEngine rules.
///   Decremented by 0.2 per active warning.
/// - [settingsScore]: 0.0–1.0, from SettingsHeuristics.
///   Amber -0.15, Red -0.35 per slot.
/// - [focusScore]: 0.0–1.0, raw AF confidence from camera metadata.
class ConfidenceScore {
  final double compositionScore;
  final double settingsScore;
  final double focusScore;

  const ConfidenceScore({
    required this.compositionScore,
    required this.settingsScore,
    required this.focusScore,
  });

  /// Weighted final score per spec:
  /// Composition × 0.50 + Settings × 0.30 + Focus × 0.20
  double get finalScore {
    final raw = compositionScore * weightComposition +
        settingsScore * weightSettings +
        focusScore * weightFocus;
    return raw.clamp(0.0, 1.0);
  }

  ScoreTier get tier => ScoreTier.fromScore(finalScore);

  /// Mock score for Phase 1 testing.
  /// Uses fixed composition score and real settings + focus scores.
  factory ConfidenceScore.mock({
    double settingsScore = 1.0,
    double focusScore = 0.8,
  }) {
    return ConfidenceScore(
      compositionScore: 0.7, // fixed mock — replaced by CompositionEngine in Phase 3
      settingsScore: settingsScore,
      focusScore: focusScore,
    );
  }

  /// Live score for Phase 3+.
  factory ConfidenceScore.compute({
    double compositionScore = 1.0,
    double settingsScore = 1.0,
    double focusScore = 0.8,
  }) {
    return ConfidenceScore(
      compositionScore: compositionScore,
      settingsScore: settingsScore,
      focusScore: focusScore,
    );
  }
}
