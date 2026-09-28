package com.lenscoach.lenscoach.sensors

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlin.math.sqrt

/**
 * MotionDetector — Detects device motion state via TYPE_LINEAR_ACCELERATION.
 *
 * Exposes `isStationary` as a StateFlow<Boolean>.
 * - Stationary = acceleration magnitude < 0.05g for > 4 seconds
 * - ThermalManager subscribes to this to pause ML pipelines regardless of thermal tier
 * - Resumes immediately on motion detected
 *
 * Also provides gyroscope delta for overlay opacity fade during active composition.
 */
class MotionDetector(private val context: Context) : SensorEventListener {

    private var sensorManager: SensorManager? = null
    private var linearAccelSensor: Sensor? = null

    companion object {
        /** Acceleration threshold in m/s² (approximately 0.05g) */
        private const val STATIONARY_THRESHOLD = 0.49f
        /** Duration in ms device must be still before considered stationary */
        private const val STATIONARY_DURATION_MS = 4000L
    }

    private val _isStationary = MutableStateFlow(false)
    /**
     * True when device has been stationary (< 0.05g) for > 4 seconds.
     * ThermalManager subscribes to this directly to pause ML pipelines.
     */
    val isStationary: StateFlow<Boolean> = _isStationary

    private val _currentAccelMagnitude = MutableStateFlow(0f)
    val currentAccelMagnitude: StateFlow<Float> = _currentAccelMagnitude

    private var lastMotionTimestamp: Long = System.currentTimeMillis()

    fun start() {
        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        linearAccelSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION)

        linearAccelSensor?.let {
            sensorManager?.registerListener(
                this,
                it,
                SensorManager.SENSOR_DELAY_UI // ~15fps, sufficient for motion detection
            )
        }

        lastMotionTimestamp = System.currentTimeMillis()
    }

    fun stop() {
        sensorManager?.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent?) {
        event ?: return
        if (event.sensor.type != Sensor.TYPE_LINEAR_ACCELERATION) return

        val x = event.values[0]
        val y = event.values[1]
        val z = event.values[2]
        val magnitude = sqrt((x * x + y * y + z * z).toDouble()).toFloat()

        _currentAccelMagnitude.value = magnitude

        val now = System.currentTimeMillis()

        if (magnitude > STATIONARY_THRESHOLD) {
            // Motion detected — reset timer, mark as non-stationary immediately
            lastMotionTimestamp = now
            _isStationary.value = false
        } else {
            // Below threshold — check if we've been still long enough
            val elapsed = now - lastMotionTimestamp
            if (elapsed >= STATIONARY_DURATION_MS) {
                _isStationary.value = true
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // Not needed
    }
}
