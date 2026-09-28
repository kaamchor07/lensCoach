package com.lenscoach.lenscoach.camera

/**
 * FrameMetadata — Captured sensor data from each camera frame.
 *
 * Consumed by SettingsHeuristics (HUD), CompositionEngine (scoring),
 * and ConfidenceScorer (weighted final score).
 */
data class FrameMetadata(
    val timestamp: Long,
    val rotationDegrees: Int,
    val width: Int,
    val height: Int,
    val exposureValue: Float,     // EV — derived from sensor exposure time + ISO
    val iso: Int,                 // ISO sensitivity
    val shutterSpeed: Float,      // Exposure time in seconds (e.g. 1/60 = 0.0167)
    val afConfidence: Float,      // Auto-focus confidence 0.0–1.0
    val whiteBalanceTemp: Int,    // Color temperature in Kelvin
    val frameMotionDelta: Float   // Inter-frame motion magnitude
) {
    /**
     * Convert to Map for passing over MethodChannel to Flutter.
     */
    fun toMap(): Map<String, Any> = mapOf(
        "timestamp" to timestamp,
        "rotationDegrees" to rotationDegrees,
        "width" to width,
        "height" to height,
        "exposureValue" to exposureValue,
        "iso" to iso,
        "shutterSpeed" to shutterSpeed,
        "afConfidence" to afConfidence,
        "whiteBalanceTemp" to whiteBalanceTemp,
        "frameMotionDelta" to frameMotionDelta
    )
}
