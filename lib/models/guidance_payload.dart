/// GuidancePayload — Composition guidance from the CompositionEngine.
///
/// Contains directional arrows, text nudges, and warnings
/// produced by the 5-rule evaluation in CompositionEngine.

class GuidancePayload {
  final double centroidX;
  final double centroidY;
  final double compositionScore;
  final List<GuidanceWarning> warnings;

  const GuidancePayload({
    required this.centroidX,
    required this.centroidY,
    required this.compositionScore,
    this.warnings = const [],
  });

  factory GuidancePayload.fromMap(Map<String, dynamic>? map) {
    if (map == null) return GuidancePayload.empty();
    return GuidancePayload(
      centroidX: (map['centroidX'] as num?)?.toDouble() ?? 0.5,
      centroidY: (map['centroidY'] as num?)?.toDouble() ?? 0.5,
      compositionScore: (map['compositionScore'] as num?)?.toDouble() ?? 1.0,
      warnings: (map['warnings'] as List?)
              ?.map((e) => GuidanceWarning.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  factory GuidancePayload.empty() => const GuidancePayload(
        centroidX: 0.5,
        centroidY: 0.5,
        compositionScore: 1.0,
      );

  bool get hasWarnings => warnings.isNotEmpty;
  bool get hasPlacementArrow =>
      warnings.any((w) => w.type == WarningType.placement);
}

enum WarningType {
  placement,
  size,
  background,
  focus,
  lighting;

  static WarningType fromString(String value) {
    return WarningType.values.firstWhere(
      (e) => e.name.toUpperCase() == value.toUpperCase(),
      orElse: () => WarningType.placement,
    );
  }
}

class GuidanceWarning {
  final WarningType type;
  final String message;
  final double arrowFromX;
  final double arrowFromY;
  final double arrowToX;
  final double arrowToY;

  const GuidanceWarning({
    required this.type,
    required this.message,
    this.arrowFromX = 0,
    this.arrowFromY = 0,
    this.arrowToX = 0,
    this.arrowToY = 0,
  });

  factory GuidanceWarning.fromMap(Map<String, dynamic> map) {
    return GuidanceWarning(
      type: WarningType.fromString(map['type'] as String? ?? 'PLACEMENT'),
      message: map['message'] as String? ?? '',
      arrowFromX: (map['arrowFromX'] as num?)?.toDouble() ?? 0,
      arrowFromY: (map['arrowFromY'] as num?)?.toDouble() ?? 0,
      arrowToX: (map['arrowToX'] as num?)?.toDouble() ?? 0,
      arrowToY: (map['arrowToY'] as num?)?.toDouble() ?? 0,
    );
  }
}
