package com.lenscoach.lenscoach.sensors

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import kotlin.math.atan2

/**
 * HorizonDetector — Uses TYPE_ROTATION_VECTOR to compute horizon angle.
 *
 * Provides real-time device orientation for:
 * - Horizon level indicator overlay
 * - Gyroscope delta for overlay fade during active composition
 *
 * Runs at sensor default rate (~60fps).
 */
class HorizonDetector(private val context: Context) : SensorEventListener {

    private var sensorManager: SensorManager? = null
    private var rotationSensor: Sensor? = null

    private val rotationMatrix = FloatArray(9)
    private val orientationAngles = FloatArray(3)

    /**
     * Current horizon angle in degrees.
     * 0 = perfectly level, positive = tilted clockwise, negative = counter-clockwise.
     */
    @Volatile
    var currentAngle: Float = 0f
        private set

    /**
     * Current pitch angle in degrees (device tilt forward/backward).
     */
    @Volatile
    var currentPitch: Float = 0f
        private set

    /**
     * Gyroscope delta — magnitude of angular change between readings.
     * Used to detect active composition (user moving the device).
     */
    @Volatile
    var gyroDelta: Float = 0f
        private set

    private var previousRoll: Float = 0f

    fun start() {
        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        rotationSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)

        rotationSensor?.let {
            sensorManager?.registerListener(
                this,
                it,
                SensorManager.SENSOR_DELAY_GAME // ~60fps
            )
        }
    }

    fun stop() {
        sensorManager?.unregisterListener(this)
    }

    override fun onSensorChanged(event: SensorEvent?) {
        event ?: return
        if (event.sensor.type != Sensor.TYPE_ROTATION_VECTOR) return

        // Convert rotation vector to rotation matrix
        SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)

        // Get orientation angles (azimuth, pitch, roll)
        SensorManager.getOrientation(rotationMatrix, orientationAngles)

        val roll = Math.toDegrees(orientationAngles[2].toDouble()).toFloat()
        val pitch = Math.toDegrees(orientationAngles[1].toDouble()).toFloat()

        // Compute delta from previous reading
        gyroDelta = Math.abs(roll - previousRoll)
        previousRoll = roll

        currentAngle = roll
        currentPitch = pitch
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // Not needed for rotation vector
    }
}
