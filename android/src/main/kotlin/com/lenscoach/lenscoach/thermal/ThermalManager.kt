package com.lenscoach.lenscoach.thermal

import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.widget.Toast
import com.lenscoach.lenscoach.sensors.MotionDetector
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

/**
 * ThermalManager — 4-tier thermal throttling with MotionDetector integration.
 *
 * Thermal tiers (Section 4.2):
 * - NONE/LIGHT: Full operation, all ML paths active at normal cadence
 * - MODERATE: Scene classifier every 2.5s (instead of 1.5s), no other changes
 * - SEVERE: Classifier every 4s, disable background entropy check + geometry snapping
 * - CRITICAL/EMERGENCY: Disable all ML inference, static grid overlays only, toast warning
 *
 * MotionDetector integration (explicit wiring per spec feedback):
 * - Subscribes to MotionDetector.isStationary StateFlow
 * - When isStationary=true, pauses all ML pipelines REGARDLESS of thermal tier
 * - Resumes immediately on motion detected
 */
class ThermalManager(
    private val context: Context,
    private val motionDetector: MotionDetector
) {
    enum class ThermalTier {
        NONE_LIGHT,
        MODERATE,
        SEVERE,
        CRITICAL
    }

    private val _currentTier = MutableStateFlow(ThermalTier.NONE_LIGHT)
    val currentTier: StateFlow<ThermalTier> = _currentTier

    /**
     * Whether ML pipelines should be active.
     * False when: device is stationary OR thermal tier is CRITICAL.
     */
    private val _mlActive = MutableStateFlow(true)
    val mlActive: StateFlow<Boolean> = _mlActive

    /**
     * Current scene classifier interval in milliseconds.
     * Adjusted based on thermal tier.
     */
    private val _classifierIntervalMs = MutableStateFlow(1500L)
    val classifierIntervalMs: StateFlow<Long> = _classifierIntervalMs

    /**
     * Whether background entropy check is enabled.
     * Disabled at SEVERE tier and above.
     */
    private val _entropyCheckEnabled = MutableStateFlow(true)
    val entropyCheckEnabled: StateFlow<Boolean> = _entropyCheckEnabled

    /**
     * Whether geometry snapping is enabled.
     * Disabled at SEVERE tier and above.
     */
    private val _geometrySnapEnabled = MutableStateFlow(true)
    val geometrySnapEnabled: StateFlow<Boolean> = _geometrySnapEnabled

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var thermalListener: Any? = null // API 30+ listener

    fun start() {
        registerThermalListener()
        wireMotionDetector()
    }

    fun stop() {
        scope.cancel()
        unregisterThermalListener()
    }

    /**
     * Register PowerManager thermal status listener.
     * API 30+ (Android 11): Uses OnThermalStatusChangedListener
     * API <30: Polls currentThermalStatus every 5 seconds
     */
    private fun registerThermalListener() {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // API 30+: Real-time listener
            val listener = PowerManager.OnThermalStatusChangedListener { status ->
                updateThermalTier(status)
            }
            powerManager.addThermalStatusListener(listener)
            thermalListener = listener

            // Also get current status immediately
            updateThermalTier(powerManager.currentThermalStatus)
        } else {
            // API <30: Poll every 5 seconds
            scope.launch {
                while (isActive) {
                    try {
                        val status = powerManager.currentThermalStatus
                        updateThermalTier(status)
                    } catch (_: Exception) {
                        // Some devices may not support this
                    }
                    delay(5000)
                }
            }
        }
    }

    private fun unregisterThermalListener() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val listener = thermalListener as? PowerManager.OnThermalStatusChangedListener
            if (listener != null) {
                val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                pm.removeThermalStatusListener(listener)
            }
        }
    }

    /**
     * Map Android thermal status to our 4-tier model.
     */
    private fun updateThermalTier(thermalStatus: Int) {
        val tier = when (thermalStatus) {
            PowerManager.THERMAL_STATUS_NONE,
            PowerManager.THERMAL_STATUS_LIGHT -> ThermalTier.NONE_LIGHT

            PowerManager.THERMAL_STATUS_MODERATE -> ThermalTier.MODERATE

            PowerManager.THERMAL_STATUS_SEVERE -> ThermalTier.SEVERE

            PowerManager.THERMAL_STATUS_CRITICAL,
            PowerManager.THERMAL_STATUS_EMERGENCY,
            PowerManager.THERMAL_STATUS_SHUTDOWN -> ThermalTier.CRITICAL

            else -> ThermalTier.NONE_LIGHT
        }

        _currentTier.value = tier
        applyTierSettings(tier)
    }

    /**
     * Apply throttling settings for the given tier.
     */
    private fun applyTierSettings(tier: ThermalTier) {
        when (tier) {
            ThermalTier.NONE_LIGHT -> {
                _classifierIntervalMs.value = 1500L
                _entropyCheckEnabled.value = true
                _geometrySnapEnabled.value = true
                _mlActive.value = !motionDetector.isStationary.value
            }
            ThermalTier.MODERATE -> {
                _classifierIntervalMs.value = 2500L
                _entropyCheckEnabled.value = true
                _geometrySnapEnabled.value = true
                _mlActive.value = !motionDetector.isStationary.value
            }
            ThermalTier.SEVERE -> {
                _classifierIntervalMs.value = 4000L
                _entropyCheckEnabled.value = false
                _geometrySnapEnabled.value = false
                _mlActive.value = !motionDetector.isStationary.value
            }
            ThermalTier.CRITICAL -> {
                _mlActive.value = false
                // Show toast on main thread
                scope.launch(Dispatchers.Main) {
                    Toast.makeText(
                        context,
                        "Device cooling — AI guidance paused",
                        Toast.LENGTH_LONG
                    ).show()
                }
            }
        }
    }

    /**
     * Wire MotionDetector.isStationary directly to ML pipeline pause.
     * This is an explicit subscription — when device is stationary (< 0.05g for > 4s),
     * ALL ML pipelines pause regardless of thermal tier.
     * Resumes immediately on motion detected.
     */
    private fun wireMotionDetector() {
        scope.launch {
            motionDetector.isStationary.collect { stationary ->
                if (_currentTier.value != ThermalTier.CRITICAL) {
                    _mlActive.value = !stationary
                }
                // If CRITICAL, mlActive stays false regardless
            }
        }
    }

    /**
     * Get a summary map for sending to Flutter via platform channel.
     */
    fun toMap(): Map<String, Any> = mapOf(
        "tier" to _currentTier.value.name,
        "mlActive" to _mlActive.value,
        "classifierIntervalMs" to _classifierIntervalMs.value,
        "entropyCheckEnabled" to _entropyCheckEnabled.value,
        "geometrySnapEnabled" to _geometrySnapEnabled.value
    )
}
