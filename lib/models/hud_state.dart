/// HUD state model — mirrors the Kotlin HudState structure.
/// Represents the 3-slot settings HUD displayed above the shutter button.

enum HudStatus {
  green,
  amber,
  red;

  static HudStatus fromString(String value) {
    return HudStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => HudStatus.green,
    );
  }
}

class HudSlot {
  final String parameter;
  final String value;
  final HudStatus status;
  final String label;
  final String tooltip;

  const HudSlot({
    required this.parameter,
    required this.value,
    required this.status,
    required this.label,
    required this.tooltip,
  });

  factory HudSlot.fromMap(Map<String, dynamic> map) {
    return HudSlot(
      parameter: map['parameter'] as String? ?? '',
      value: map['value'] as String? ?? '—',
      status: HudStatus.fromString(map['status'] as String? ?? 'green'),
      label: map['label'] as String? ?? '',
      tooltip: map['tooltip'] as String? ?? '',
    );
  }

  static HudSlot defaultSlot(String parameter) => HudSlot(
        parameter: parameter,
        value: '—',
        status: HudStatus.green,
        label: 'READY',
        tooltip: 'Waiting for camera...',
      );
}

class HudState {
  final HudSlot slot1;
  final HudSlot slot2;
  final HudSlot slot3;
  final List<HudSlot> additionalWarnings;

  const HudState({
    required this.slot1,
    required this.slot2,
    required this.slot3,
    this.additionalWarnings = const [],
  });

  factory HudState.fromMap(Map<String, dynamic>? map) {
    if (map == null) return HudState.defaultState();
    return HudState(
      slot1: HudSlot.fromMap((map['slot1'] as Map?)?.cast<String, dynamic>() ?? {}),
      slot2: HudSlot.fromMap((map['slot2'] as Map?)?.cast<String, dynamic>() ?? {}),
      slot3: HudSlot.fromMap((map['slot3'] as Map?)?.cast<String, dynamic>() ?? {}),
      additionalWarnings: (map['additionalWarnings'] as List?)
              ?.map((e) => HudSlot.fromMap((e as Map).cast<String, dynamic>()))
              .toList() ??
          [],
    );
  }

  factory HudState.defaultState() => HudState(
        slot1: HudSlot.defaultSlot('LIGHT'),
        slot2: HudSlot.defaultSlot('MOTION'),
        slot3: HudSlot.defaultSlot('FOCUS'),
      );

  /// Count of non-green slots for scoring.
  int get amberCount => [slot1, slot2, slot3]
      .where((s) => s.status == HudStatus.amber)
      .length;

  int get redCount => [slot1, slot2, slot3]
      .where((s) => s.status == HudStatus.red)
      .length;

  /// Settings score for confidence indicator (Section 2.5).
  /// 1.0 if all green, subtract 0.15 per amber, 0.35 per red.
  double get settingsScore {
    double score = 1.0;
    score -= amberCount * 0.15;
    score -= redCount * 0.35;
    return score.clamp(0.0, 1.0);
  }
}
