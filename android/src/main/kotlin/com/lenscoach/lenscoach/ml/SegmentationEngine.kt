package com.lenscoach.lenscoach.ml

import android.content.Context
import android.graphics.Bitmap
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * SegmentationEngine — MobileSAM on-device tap-to-segment inference.
 *
 * Architecture: Encoder + Decoder split ONNX models
 * - Encoder runs ONLY on tap trigger or 1.5s refresh cycle (NOT every frame)
 * - Decoder runs immediately after encoder with tap point prompt
 *
 * Input: full-res frame + normalized tap point (0.0–1.0 x,y)
 * Output: binary segmentation mask at original resolution
 *
 * Post-processing: morphological closing (3px radius) to smooth mask edges
 *
 * Subject tracking:
 * - Refresh every 1.5s while subject is active
 * - If centroid drift > 15% of frame width, recompute immediately
 * - If subject exits frame, show "Subject lost" tooltip
 */
class SegmentationEngine(private val context: Context) {

    companion object {
        private const val ENCODER_MODEL = "mobilesam_encoder.onnx"
        private const val DECODER_MODEL = "mobilesam_decoder.onnx"
        private const val CONFIDENCE_THRESHOLD = 0.6f
        private const val CENTROID_DRIFT_THRESHOLD = 0.15f // fraction of frame width
    }

    private var encoderSession: OnnxSessionManager.SessionWrapper? = null
    private var decoderSession: OnnxSessionManager.SessionWrapper? = null
    private var isInitialized = false

    // Cached encoder embeddings — reused across decoder runs until next encode
    private var cachedEmbeddings: FloatArray? = null
    private var cachedFrameTimestamp: Long = 0

    // Current segmentation state
    private val _currentMask = MutableStateFlow<SegmentationResult?>(null)
    val currentMask: StateFlow<SegmentationResult?> = _currentMask

    private val _isSubjectActive = MutableStateFlow(false)
    val isSubjectActive: StateFlow<Boolean> = _isSubjectActive

    /**
     * Initialize encoder and decoder ONNX sessions.
     */
    fun initialize(): Boolean {
        return try {
            encoderSession = OnnxSessionManager.createSession(context, ENCODER_MODEL)
            decoderSession = OnnxSessionManager.createSession(context, DECODER_MODEL)
            isInitialized = true
            true
        } catch (e: Exception) {
            e.printStackTrace()
            isInitialized = false
            false
        }
    }

    /**
     * Run full segmentation: encode frame + decode with tap point.
     * Called on user tap and on 1.5s refresh cycle.
     *
     * @param frame Full-resolution camera frame
     * @param tapX Normalized X coordinate (0.0–1.0)
     * @param tapY Normalized Y coordinate (0.0–1.0)
     * @return SegmentationResult or null if failed
     */
    fun segment(frame: Bitmap, tapX: Float, tapY: Float): SegmentationResult? {
        if (!isInitialized) return null

        val startTime = System.currentTimeMillis()

        try {
            // Step 1: Run encoder (only on tap or refresh, never per-frame)
            val embeddings = runEncoder(frame)
            cachedEmbeddings = embeddings
            cachedFrameTimestamp = startTime

            // Step 2: Run decoder with tap point prompt
            val mask = runDecoder(embeddings, tapX, tapY, frame.width, frame.height)

            // Step 3: Post-process mask (morphological closing)
            val processedMask = morphologicalClosing(mask, frame.width, frame.height, 3)

            // Step 4: Compute mask metadata
            val result = computeSegmentationResult(
                processedMask, frame.width, frame.height, tapX, tapY,
                System.currentTimeMillis() - startTime
            )

            _currentMask.value = result
            _isSubjectActive.value = result.confidence >= CONFIDENCE_THRESHOLD

            return result

        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
    }

    /**
     * Refresh segmentation using cached embeddings + new tap point.
     * Used for the 1.5s refresh cycle to track subject drift.
     */
    fun refreshWithCachedEmbeddings(tapX: Float, tapY: Float, frameWidth: Int, frameHeight: Int): SegmentationResult? {
        val embeddings = cachedEmbeddings ?: return null
        if (!isInitialized) return null

        try {
            val mask = runDecoder(embeddings, tapX, tapY, frameWidth, frameHeight)
            val processedMask = morphologicalClosing(mask, frameWidth, frameHeight, 3)
            val result = computeSegmentationResult(
                processedMask, frameWidth, frameHeight, tapX, tapY, 0
            )

            // Check centroid drift
            val previousResult = _currentMask.value
            if (previousResult != null) {
                val drift = Math.abs(result.centroidX - previousResult.centroidX)
                if (drift > CENTROID_DRIFT_THRESHOLD) {
                    // Significant drift — overlays should recompute immediately
                    result.driftDetected = true
                }
            }

            _currentMask.value = result
            _isSubjectActive.value = result.confidence >= CONFIDENCE_THRESHOLD

            return result
        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
    }

    /**
     * Clear current subject selection.
     */
    fun deselect() {
        _currentMask.value = null
        _isSubjectActive.value = false
        cachedEmbeddings = null
    }

    private fun runEncoder(frame: Bitmap): FloatArray {
        // TODO: Actual encoder inference
        // val inputTensor = preprocessForEncoder(frame)
        // val result = encoderSession!!.run(inputTensor, ...)
        return FloatArray(256 * 64 * 64) // Stub embedding shape
    }

    private fun runDecoder(
        embeddings: FloatArray,
        tapX: Float,
        tapY: Float,
        width: Int,
        height: Int
    ): BooleanArray {
        // TODO: Actual decoder inference with point prompt
        // Returns binary mask at original resolution
        return BooleanArray(width * height) { false } // Stub
    }

    /**
     * Apply morphological closing to smooth mask edges.
     * Uses a circular structuring element with given radius.
     */
    private fun morphologicalClosing(
        mask: BooleanArray,
        width: Int,
        height: Int,
        radius: Int
    ): BooleanArray {
        // Dilation followed by erosion
        val dilated = dilate(mask, width, height, radius)
        return erode(dilated, width, height, radius)
    }

    private fun dilate(mask: BooleanArray, width: Int, height: Int, radius: Int): BooleanArray {
        val result = BooleanArray(mask.size)
        for (y in 0 until height) {
            for (x in 0 until width) {
                if (mask[y * width + x]) {
                    for (dy in -radius..radius) {
                        for (dx in -radius..radius) {
                            if (dx * dx + dy * dy <= radius * radius) {
                                val nx = x + dx
                                val ny = y + dy
                                if (nx in 0 until width && ny in 0 until height) {
                                    result[ny * width + nx] = true
                                }
                            }
                        }
                    }
                }
            }
        }
        return result
    }

    private fun erode(mask: BooleanArray, width: Int, height: Int, radius: Int): BooleanArray {
        val result = BooleanArray(mask.size)
        for (y in 0 until height) {
            for (x in 0 until width) {
                var allSet = true
                for (dy in -radius..radius) {
                    for (dx in -radius..radius) {
                        if (dx * dx + dy * dy <= radius * radius) {
                            val nx = x + dx
                            val ny = y + dy
                            if (nx < 0 || nx >= width || ny < 0 || ny >= height || !mask[ny * width + nx]) {
                                allSet = false
                                break
                            }
                        }
                    }
                    if (!allSet) break
                }
                result[y * width + x] = allSet
            }
        }
        return result
    }

    private fun computeSegmentationResult(
        mask: BooleanArray,
        width: Int,
        height: Int,
        tapX: Float,
        tapY: Float,
        inferenceTimeMs: Long
    ): SegmentationResult {
        // Compute centroid and bounding box
        var sumX = 0L
        var sumY = 0L
        var count = 0
        var minX = width
        var maxX = 0
        var minY = height
        var maxY = 0

        for (y in 0 until height) {
            for (x in 0 until width) {
                if (mask[y * width + x]) {
                    sumX += x
                    sumY += y
                    count++
                    if (x < minX) minX = x
                    if (x > maxX) maxX = x
                    if (y < minY) minY = y
                    if (y > maxY) maxY = y
                }
            }
        }

        val centroidX = if (count > 0) sumX.toFloat() / count / width else tapX
        val centroidY = if (count > 0) sumY.toFloat() / count / height else tapY
        
        // Fix for invalid bounding box when mask is empty:
        // Use a small fallback box centered at tap coordinates
        if (count == 0) {
            val fallbackSize = 0.1f // 10% of frame
            minX = ((tapX - fallbackSize/2) * width).toInt().coerceIn(0, width - 1)
            maxX = ((tapX + fallbackSize/2) * width).toInt().coerceIn(0, width - 1)
            minY = ((tapY - fallbackSize/2) * height).toInt().coerceIn(0, height - 1)
            maxY = ((tapY + fallbackSize/2) * height).toInt().coerceIn(0, height - 1)
        }

        val bboxArea = if (count > 0) {
            ((maxX - minX).toFloat() / width) * ((maxY - minY).toFloat() / height)
        } else 0f

        return SegmentationResult(
            mask = mask,
            width = width,
            height = height,
            centroidX = centroidX,
            centroidY = centroidY,
            bboxLeft = minX.toFloat() / width,
            bboxTop = minY.toFloat() / height,
            bboxRight = maxX.toFloat() / width,
            bboxBottom = maxY.toFloat() / height,
            sizeRatio = bboxArea,
            confidence = if (count > 0) 0.85f else 0f, // Stub confidence
            inferenceTimeMs = inferenceTimeMs
        )
    }

    fun release() {
        encoderSession?.close()
        decoderSession?.close()
        encoderSession = null
        decoderSession = null
        isInitialized = false
    }
}

/**
 * Result of a segmentation operation.
 */
data class SegmentationResult(
    val mask: BooleanArray,
    val width: Int,
    val height: Int,
    val centroidX: Float,       // Normalized 0–1
    val centroidY: Float,       // Normalized 0–1
    val bboxLeft: Float,        // Normalized 0–1
    val bboxTop: Float,
    val bboxRight: Float,
    val bboxBottom: Float,
    val sizeRatio: Float,       // bbox area / frame area
    val confidence: Float,      // 0–1
    val inferenceTimeMs: Long,
    var driftDetected: Boolean = false
) {
    fun toMap(): Map<String, Any> = mapOf(
        "centroidX" to centroidX,
        "centroidY" to centroidY,
        "bboxLeft" to bboxLeft,
        "bboxTop" to bboxTop,
        "bboxRight" to bboxRight,
        "bboxBottom" to bboxBottom,
        "sizeRatio" to sizeRatio,
        "confidence" to confidence,
        "inferenceTimeMs" to inferenceTimeMs,
        "driftDetected" to driftDetected
    )
}
