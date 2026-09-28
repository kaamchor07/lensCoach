/// ReviewResult — Structured response from VLM post-shot review.
///
/// Contains exactly 6 fields per the VLM prompt schema in Section 7.3.
class ReviewResult {
  final int compositionRating;    // 1-10
  final int lightingRating;       // 1-10
  final String sceneTypeDetected;
  final String topIssue;
  final String improvementSuggestion;
  final String strength;
  final bool isOfflineFallback;

  const ReviewResult({
    required this.compositionRating,
    required this.lightingRating,
    required this.sceneTypeDetected,
    required this.topIssue,
    required this.improvementSuggestion,
    required this.strength,
    this.isOfflineFallback = false,
  });

  factory ReviewResult.fromMap(Map<String, dynamic> map) {
    return ReviewResult(
      compositionRating: (map['composition_rating'] as num?)?.toInt() ?? 5,
      lightingRating: (map['lighting_rating'] as num?)?.toInt() ?? 5,
      sceneTypeDetected: map['scene_type_detected'] as String? ?? 'unknown',
      topIssue: map['top_issue'] as String? ?? '',
      improvementSuggestion: map['improvement_suggestion'] as String? ?? '',
      strength: map['strength'] as String? ?? '',
      isOfflineFallback: map['isOfflineFallback'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'composition_rating': compositionRating,
    'lighting_rating': lightingRating,
    'scene_type_detected': sceneTypeDetected,
    'top_issue': topIssue,
    'improvement_suggestion': improvementSuggestion,
    'strength': strength,
    'isOfflineFallback': isOfflineFallback,
  };
}
