package com.lenscoach.lenscoach.engine

import com.lenscoach.lenscoach.camera.FrameMetadata
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * SettingsHeuristics — Real-time camera settings evaluation engine.
 *
 * Evaluates 7 rules from the spec against live sensor metadata.
 * Produces HUD state (3 slots: label, status color, tooltip) for each frame.
 * Runs on CPU — compute cost is negligible.
 */
class SettingsHeuristics {

    private val _currentHudState = MutableStateFlow(HudState.default())
    val currentHudState: StateFlow<HudState> = _currentHudState

    /**
     * Evaluate all 7 heuristic rules against current frame metadata.
     * Called every frame by the FrameDispatcher.
     */
    fun evaluate(metadata: FrameMetadata) {
        val slot1 = evaluateExposure(metadata)
        val slot2 = evaluateMotionBlur(metadata)
        val slot3 = evaluateFocus(metadata)

        // Additional rules evaluated but shown via slot rotation or warnings
        val faceLighting = evaluateFaceLighting(metadata)
        val whiteBalance = evaluateWhiteBalance(metadata)

        _currentHudState.value = HudState(
            slot1 = slot1,
            slot2 = slot2,
            slot3 = slot3,
            additionalWarnings = listOfNotNull(faceLighting, whiteBalance)
        )
    }

    // --- Rule 1, 2, 3: Exposure Value ---

    private fun evaluateExposure(metadata: FrameMetadata): HudSlot {
        val ev = metadata.exposureValue
        return when {
            ev < 1.5f -> HudSlot(
                parameter = "LIGHT",
                value = "EV ${String.format("%.1f", ev)}",
                status = HudStatus.RED,
                label = "LOW LIGHT",
                tooltip = "Low light detected. Try Night Mode or reduce shutter speed."
            )
            ev > 10f -> HudSlot(
                parameter = "LIGHT",
                value = "EV ${String.format("%.1f", ev)}",
                status = HudStatus.AMBER,
                label = "OVEREXPOSED",
                tooltip = "Very bright scene. Reduce ISO or increase shutter speed."
            )
            else -> HudSlot(
                parameter = "LIGHT",
                value = "EV ${String.format("%.1f", ev)}",
                status = HudStatus.GREEN,
                label = "GOOD LIGHT",
                tooltip = "Lighting is well-suited for this shot."
            )
        }
    }

    // --- Rule 4: Motion Blur ---

    private fun evaluateMotionBlur(metadata: FrameMetadata): HudSlot {
        val highMotion = metadata.frameMotionDelta > 0.5f
        val slowShutter = metadata.shutterSpeed > (1.0f / 120.0f)

        return if (highMotion && slowShutter) {
            HudSlot(
                parameter = "MOTION",
                value = "1/${(1.0f / metadata.shutterSpeed).toInt()}s",
                status = HudStatus.RED,
                label = "MOTION BLUR",
                tooltip = "Subject or camera is moving. Increase shutter speed to freeze motion."
            )
        } else {
            HudSlot(
                parameter = "MOTION",
                value = "1/${(1.0f / metadata.shutterSpeed).toInt()}s",
                status = HudStatus.GREEN,
                label = "STEADY",
                tooltip = "Camera is stable. No motion blur risk."
            )
        }
    }

    // --- Rule 5: Focus Confidence ---

    private fun evaluateFocus(metadata: FrameMetadata): HudSlot {
        val af = metadata.afConfidence
        return when {
            af < 0.6f -> HudSlot(
                parameter = "FOCUS",
                value = "${(af * 100).toInt()}%",
                status = HudStatus.AMBER,
                label = "SOFT FOCUS",
                tooltip = "Auto-focus isn't locked. Tap the subject to focus manually."
            )
            else -> HudSlot(
                parameter = "FOCUS",
                value = "${(af * 100).toInt()}%",
                status = HudStatus.GREEN,
                label = "FOCUSED",
                tooltip = "Focus is locked and sharp."
            )
        }
    }

    // --- Rule 6: Face Detected + Flat Lighting ---

    private fun evaluateFaceLighting(metadata: FrameMetadata): HudSlot? {
        // Phase 1: face detection not yet integrated, return null
        // Phase 2: will use ML face detection + EV + lighting angle
        // Condition: face detected, EV < 3, flat lighting angle
        return null
    }

    // --- Rule 7: White Balance ---

    private fun evaluateWhiteBalance(metadata: FrameMetadata): HudSlot? {
        val wbTemp = metadata.whiteBalanceTemp
        // Scene-appropriate ranges (simplified):
        // Daylight: 5200-6500K, Cloudy: 6500-8000K, Tungsten: 2800-3500K
        // Flag if WB is far from expected range
        val inRange = wbTemp in 3500..7500
        return if (!inRange) {
            HudSlot(
                parameter = "WB",
                value = "${wbTemp}K",
                status = HudStatus.AMBER,
                label = "COLOUR CAST",
                tooltip = "White balance may be off for this lighting. Try switching to the matching preset."
            )
        } else {
            null // No warning needed
        }
    }
}

// --- Data Models ---

enum class HudStatus {
    GREEN, AMBER, RED;

    fun toMap(): String = name.lowercase()
}

data class HudSlot(
    val parameter: String,
    val value: String,
    val status: HudStatus,
    val label: String,
    val tooltip: String
) {
    fun toMap(): Map<String, Any> = mapOf(
        "parameter" to parameter,
        "value" to value,
        "status" to status.toMap(),
        "label" to label,
        "tooltip" to tooltip
    )
}

data class HudState(
    val slot1: HudSlot,
    val slot2: HudSlot,
    val slot3: HudSlot,
    val additionalWarnings: List<HudSlot> = emptyList()
) {
    companion object {
        fun default(): HudState = HudState(
            slot1 = HudSlot("LIGHT", "—", HudStatus.GREEN, "READY", "Waiting for camera..."),
            slot2 = HudSlot("MOTION", "—", HudStatus.GREEN, "READY", "Waiting for camera..."),
            slot3 = HudSlot("FOCUS", "—", HudStatus.GREEN, "READY", "Waiting for camera...")
        )
    }

    fun toMap(): Map<String, Any> = mapOf(
        "slot1" to slot1.toMap(),
        "slot2" to slot2.toMap(),
        "slot3" to slot3.toMap(),
        "additionalWarnings" to additionalWarnings.map { it.toMap() }
    )
}
