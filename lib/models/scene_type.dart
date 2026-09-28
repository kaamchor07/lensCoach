/// Scene types supported by LensCoach.
/// Each scene type maps to a specific overlay configuration and acceptable centroid zones.
enum SceneType {
  landscape('Landscape', '🏔️'),
  architecture('Architecture', '🏛️'),
  portrait('Portrait', '👤'),
  street('Street', '🏙️'),
  macro('Macro', '🔍'),
  lowLight('Low-Light', '🌙');

  const SceneType(this.displayName, this.icon);

  final String displayName;
  final String icon;

  /// Convert to string for platform channel.
  String get channelValue => name;

  /// Parse from platform channel string.
  static SceneType fromString(String value) {
    return SceneType.values.firstWhere(
      (e) => e.name == value || e.displayName == value,
      orElse: () => SceneType.street, // fallback per spec
    );
  }
}
