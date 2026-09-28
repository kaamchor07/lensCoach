package com.lenscoach.lenscoach

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry
import com.lenscoach.lenscoach.camera.CameraSessionManager
import com.lenscoach.lenscoach.engine.CompositionEngine
import com.lenscoach.lenscoach.engine.SettingsHeuristics
import com.lenscoach.lenscoach.ml.SceneClassifier
import com.lenscoach.lenscoach.ml.SegmentationEngine
import com.lenscoach.lenscoach.sensors.HorizonDetector
import com.lenscoach.lenscoach.sensors.MotionDetector
import com.lenscoach.lenscoach.thermal.ThermalManager
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

/**
 * LenscoachPlugin — Flutter plugin entry point.
 *
 * Bridges the Kotlin native camera/ML/sensor layer with the Flutter UI layer
 * via MethodChannel (commands) and EventChannel (continuous data streams).
 *
 * Component wiring:
 *   CameraSessionManager → FrameMetadata → SettingsHeuristics → HudState
 *   ThermalManager ← MotionDetector.isStationary (StateFlow subscription)
 *   SceneClassifier → currentScene (every 1.5s, cadence from ThermalManager)
 *   SegmentationEngine → SegmentationResult → CompositionEngine → GuidancePayload
 */
class LenscoachPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware {

    private lateinit var methodChannel: MethodChannel
    private lateinit var sensorEventChannel: EventChannel

    private var activity: Activity? = null
    private var context: Context? = null
    private var textureRegistry: TextureRegistry? = null
    private var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding? = null

    // Native components
    private var cameraManager: CameraSessionManager? = null
    private var settingsHeuristics: SettingsHeuristics? = null
    private var horizonDetector: HorizonDetector? = null
    private var motionDetector: MotionDetector? = null
    private var thermalManager: ThermalManager? = null
    private var sceneClassifier: SceneClassifier? = null
    private var segmentationEngine: SegmentationEngine? = null
    private var compositionEngine: CompositionEngine? = null

    // Coroutines
    private val pluginScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var classifierJob: Job? = null

    // Current state
    private var currentSceneType: String = "street"

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        this.flutterPluginBinding = flutterPluginBinding
        this.context = flutterPluginBinding.applicationContext
        this.textureRegistry = flutterPluginBinding.textureRegistry

        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.lenscoach/method")
        methodChannel.setMethodCallHandler(this)

        sensorEventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "com.lenscoach/sensors")
        sensorEventChannel.setStreamHandler(SensorStreamHandler())
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${android.os.Build.VERSION.RELEASE}")
            }
            "startCamera" -> {
                startCamera(result)
            }
            "stopCamera" -> {
                stopCamera(result)
            }
            "capturePhoto" -> {
                capturePhoto(result)
            }
            "setSceneType" -> {
                val sceneType = call.argument<String>("sceneType") ?: "street"
                currentSceneType = sceneType
                cameraManager?.setSceneType(sceneType)
                result.success(true)
            }
            "getTextureId" -> {
                result.success(cameraManager?.getTextureId())
            }
            "getSensorData" -> {
                result.success(buildSensorDataMap())
            }
            "tapToSegment" -> {
                val x = call.argument<Double>("x")?.toFloat() ?: 0.5f
                val y = call.argument<Double>("y")?.toFloat() ?: 0.5f
                handleTapToSegment(x, y, result)
            }
            "deselectSubject" -> {
                segmentationEngine?.deselect()
                result.success(true)
            }
            "getThermalStatus" -> {
                result.success(thermalManager?.toMap())
            }
            else -> result.notImplemented()
        }
    }

    private fun startCamera(result: Result) {
        val act = activity
        val binding = flutterPluginBinding
        if (act == null || binding == null) {
            result.error("NO_ACTIVITY", "Activity not available", null)
            return
        }

        try {
            // Initialize sensors
            horizonDetector = HorizonDetector(act)
            motionDetector = MotionDetector(act)
            settingsHeuristics = SettingsHeuristics()
            compositionEngine = CompositionEngine()

            horizonDetector?.start()
            motionDetector?.start()

            // Initialize thermal manager (wired to MotionDetector)
            thermalManager = ThermalManager(act, motionDetector!!)
            thermalManager?.start()

            // Initialize ML components (lazy — won't crash if models not present)
            sceneClassifier = SceneClassifier(act).also {
                pluginScope.launch(Dispatchers.IO) {
                    it.initialize() // Safe to fail
                }
            }
            segmentationEngine = SegmentationEngine(act).also {
                pluginScope.launch(Dispatchers.IO) {
                    it.initialize() // Safe to fail
                }
            }

            // Initialize camera
            cameraManager = CameraSessionManager(
                activity = act,
                textureRegistry = binding.textureRegistry,
                onFrameMetadata = { metadata ->
                    settingsHeuristics?.evaluate(metadata)
                }
            )
            cameraManager?.startCamera(
                onSuccess = { textureId ->
                    // Start scene classifier refresh cycle
                    startClassifierLoop()
                    result.success(textureId)
                },
                onError = { error ->
                    result.error("CAMERA_ERROR", error, null)
                }
            )
        } catch (e: Exception) {
            result.error("CAMERA_ERROR", "Failed to start camera: ${e.message}", null)
        }
    }

    /**
     * Scene classifier runs every 1.5s (cadence from ThermalManager).
     * Only runs when ThermalManager.mlActive is true.
     */
    private fun startClassifierLoop() {
        classifierJob?.cancel()
        classifierJob = pluginScope.launch(Dispatchers.IO) {
            while (isActive) {
                val interval = thermalManager?.classifierIntervalMs?.value ?: 1500L
                delay(interval)

                // Check if ML is active (thermal + stationary gating)
                if (thermalManager?.mlActive?.value != true) continue

                // Classify current frame
                val frame = cameraManager?.latestFrame
                if (frame != null && !frame.isRecycled) {
                    sceneClassifier?.classify(frame)?.let { (scene, _) ->
                        currentSceneType = scene
                        cameraManager?.setSceneType(scene)
                    }
                }
            }
        }
    }

    /**
     * Handle tap-to-segment request from Flutter.
     * Runs encoder + decoder on background thread, and triggers hardware auto-focus.
     */
    private fun handleTapToSegment(x: Float, y: Float, result: Result) {
        // Trigger hardware focus on the tapped area
        cameraManager?.focusAt(x, y)

        pluginScope.launch(Dispatchers.IO) {
            try {
                val frame = cameraManager?.latestFrame
                if (frame != null && !frame.isRecycled) {
                    segmentationEngine?.segment(frame, x, y)
                }

                val segResult = segmentationEngine?.currentMask?.value

                if (segResult != null) {
                    // Run composition engine on segmentation result
                    val guidance = compositionEngine?.evaluateWithMask(
                        segResult, currentSceneType
                    )

                    withContext(Dispatchers.Main) {
                        result.success(mapOf(
                            "segmentation" to segResult.toMap(),
                            "guidance" to guidance?.toMap()
                        ))
                    }
                } else {
                    withContext(Dispatchers.Main) {
                        result.success(null)
                    }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("SEGMENT_ERROR", e.message, null)
                }
            }
        }
    }

    private fun stopCamera(result: Result) {
        classifierJob?.cancel()
        cameraManager?.stopCamera()
        horizonDetector?.stop()
        motionDetector?.stop()
        thermalManager?.stop()
        result.success(true)
    }

    private fun capturePhoto(result: Result) {
        cameraManager?.capturePhoto { path, error ->
            if (error != null) {
                result.error("CAPTURE_ERROR", error, null)
            } else {
                result.success(path)
            }
        }
    }

    private fun buildSensorDataMap(): Map<String, Any?> {
        return mapOf(
            "horizonAngle" to (horizonDetector?.currentAngle ?: 0f),
            "horizonPitch" to (horizonDetector?.currentPitch ?: 0f),
            "gyroDelta" to (horizonDetector?.gyroDelta ?: 0f),
            "isStationary" to (motionDetector?.isStationary?.value ?: false),
            "hud" to (settingsHeuristics?.currentHudState?.value?.toMap()),
            "cameraMetadata" to (cameraManager?.latestMetadata?.toMap()),
            "thermalTier" to (thermalManager?.currentTier?.value?.name),
            "mlActive" to (thermalManager?.mlActive?.value ?: true),
            "sceneType" to currentSceneType,
            "segmentation" to (segmentationEngine?.currentMask?.value?.toMap())
        )
    }

    // --- ActivityAware ---

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        classifierJob?.cancel()
        pluginScope.cancel()
        cameraManager?.stopCamera()
        horizonDetector?.stop()
        motionDetector?.stop()
        thermalManager?.stop()
        sceneClassifier?.release()
        segmentationEngine?.release()
        flutterPluginBinding = null
    }

    /**
     * EventChannel stream handler for continuous sensor data.
     * Pushes sensor updates to Flutter at ~30fps.
     */
    inner class SensorStreamHandler : EventChannel.StreamHandler {
        private var job: Job? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            job = pluginScope.launch {
                while (isActive) {
                    events?.success(buildSensorDataMap())
                    delay(33) // ~30fps
                }
            }
        }

        override fun onCancel(arguments: Any?) {
            job?.cancel()
            job = null
        }
    }
}
