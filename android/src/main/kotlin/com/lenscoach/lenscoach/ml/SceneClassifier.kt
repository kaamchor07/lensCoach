package com.lenscoach.lenscoach.ml

import android.content.Context
import android.graphics.Bitmap
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * SceneClassifier — On-device scene classification via ONNX Runtime.
 *
 * Classifies camera frames into 6 scene types:
 * Landscape, Architecture, Portrait, Street, Macro, Low-Light
 *
 * Model: MobileNetV3-Small fine-tuned on Places365 → 6 classes
 * Input: 224×224 RGB (downsampled before inference)
 * Output: softmax over 6 classes + confidence score
 * Cadence: every 1.5s on background coroutine (adjusted by ThermalManager)
 *
 * ONNX model outputs a clean 6-class softmax — no remapping in Kotlin.
 * Fallback: if confidence < 0.55 on all classes, default to Street.
 */
class SceneClassifier(private val context: Context) {

    companion object {
        private const val MODEL_FILENAME = "scene_classifier.onnx"
        private const val INPUT_SIZE = 224
        private const val MIN_CONFIDENCE = 0.55f
        private const val DEFAULT_SCENE = "street"

        val SCENE_LABELS = arrayOf(
            "landscape",
            "architecture",
            "portrait",
            "street",
            "macro",
            "lowLight"
        )
    }

    // ONNX Runtime session — initialized lazily
    private var ortSession: OnnxSessionManager.SessionWrapper? = null
    private var isInitialized = false

    private val _currentScene = MutableStateFlow(DEFAULT_SCENE)
    val currentScene: StateFlow<String> = _currentScene

    private val _confidence = MutableStateFlow(0f)
    val confidence: StateFlow<Float> = _confidence

    private val _lastInferenceTimeMs = MutableStateFlow(0L)
    val lastInferenceTimeMs: StateFlow<Long> = _lastInferenceTimeMs

    /**
     * Initialize the ONNX session. Call once at startup.
     * Returns true if model loaded successfully.
     */
    fun initialize(): Boolean {
        return try {
            ortSession = OnnxSessionManager.createSession(context, MODEL_FILENAME)
            isInitialized = true
            true
        } catch (e: Exception) {
            e.printStackTrace()
            isInitialized = false
            false
        }
    }

    /**
     * Classify a camera frame.
     *
     * @param bitmap The camera frame, will be resized to 224×224 internally.
     * @return Pair of (scene label, confidence) or null if not initialized.
     */
    fun classify(bitmap: Bitmap): Pair<String, Float>? {
        if (!isInitialized || ortSession == null) return null

        val startTime = System.currentTimeMillis()

        try {
            // Resize to model input size
            val resized = Bitmap.createScaledBitmap(bitmap, INPUT_SIZE, INPUT_SIZE, true)

            // Convert to float array (RGB, normalized 0-1)
            val inputArray = bitmapToFloatArray(resized)
            if (resized != bitmap) resized.recycle()

            // Run inference
            val output = ortSession!!.run(inputArray, INPUT_SIZE, INPUT_SIZE)

            // Find argmax and confidence
            var maxIdx = 0
            var maxVal = output[0]
            for (i in 1 until output.size) {
                if (output[i] > maxVal) {
                    maxVal = output[i]
                    maxIdx = i
                }
            }

            val inferenceTime = System.currentTimeMillis() - startTime
            _lastInferenceTimeMs.value = inferenceTime

            // Apply confidence threshold
            val sceneLabel = if (maxVal >= MIN_CONFIDENCE && maxIdx < SCENE_LABELS.size) {
                SCENE_LABELS[maxIdx]
            } else {
                DEFAULT_SCENE // fallback per spec
            }

            _currentScene.value = sceneLabel
            _confidence.value = maxVal

            return Pair(sceneLabel, maxVal)

        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
    }

    /**
     * Convert Bitmap to normalized float array in CHW format (channels-first).
     * ImageNet normalization: mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]
     */
    private fun bitmapToFloatArray(bitmap: Bitmap): FloatArray {
        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)

        // CHW format: [C, H, W] = [3, 224, 224]
        val floatArray = FloatArray(3 * height * width)
        val mean = floatArrayOf(0.485f, 0.456f, 0.406f)
        val std = floatArrayOf(0.229f, 0.224f, 0.225f)

        for (i in pixels.indices) {
            val pixel = pixels[i]
            val r = ((pixel shr 16) and 0xFF) / 255.0f
            val g = ((pixel shr 8) and 0xFF) / 255.0f
            val b = (pixel and 0xFF) / 255.0f

            // Normalized, CHW layout
            floatArray[i] = (r - mean[0]) / std[0]                     // R channel
            floatArray[width * height + i] = (g - mean[1]) / std[1]    // G channel
            floatArray[2 * width * height + i] = (b - mean[2]) / std[2] // B channel
        }

        return floatArray
    }

    fun release() {
        ortSession?.close()
        ortSession = null
        isInitialized = false
    }
}
