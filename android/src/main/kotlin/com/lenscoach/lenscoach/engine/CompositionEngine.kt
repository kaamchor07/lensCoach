package com.lenscoach.lenscoach.engine

import android.graphics.Bitmap
import com.lenscoach.lenscoach.ml.SegmentationResult

/**
 * CompositionEngine — Rule-based photography composition guidance.
 *
 * Two explicit input modes:
 * 1. Mask input — from successful segmentation (primary path)
 * 2. Bounding box input — from bbox fallback when segmentation fails twice
 * Both modes produce a GuidancePayload with the same structure.
 *
 * 5 rule evaluations per Section 2.2:
 * 1. Subject centroid vs acceptable zone (per scene type)
 * 2. Size ratio (bbox area / frame area) — thresholds 0.05, 0.55
 * 3. Background entropy (pixel variance in inverse mask/bbox region)
 * 4. Edge sharpness (Laplacian variance on mask boundary; skipped for bbox input)
 * 5. Lighting (mean luminance masked/bbox vs background, 30% threshold)
 */
class CompositionEngine {

    companion object {
        private const val SIZE_TOO_SMALL = 0.05f
        private const val SIZE_TOO_LARGE = 0.55f
        private const val ENTROPY_THRESHOLD = 0.7f
        private const val BACKLIGHT_DELTA = 0.30f
        private const val SHARPNESS_THRESHOLD = 50.0f // Laplacian variance threshold
    }

    /**
     * Evaluate composition using a segmentation mask (primary path).
     */
    fun evaluateWithMask(
        segResult: SegmentationResult,
        sceneType: String,
        frame: Bitmap? = null
    ): GuidancePayload {
        val warnings = mutableListOf<GuidanceWarning>()

        // Rule 1: Centroid placement
        val centroidWarning = evaluateCentroidPlacement(
            segResult.centroidX, segResult.centroidY, sceneType
        )
        if (centroidWarning != null) warnings.add(centroidWarning)

        // Rule 2: Size ratio
        val sizeWarning = evaluateSizeRatio(segResult.sizeRatio)
        if (sizeWarning != null) warnings.add(sizeWarning)

        // Rule 3: Background entropy (uses inverse mask)
        if (frame != null) {
            val entropyWarning = evaluateBackgroundEntropy(frame, segResult.mask, segResult.width, segResult.height)
            if (entropyWarning != null) warnings.add(entropyWarning)
        }

        // Rule 4: Edge sharpness (mask-specific, NOT available for bbox)
        if (frame != null) {
            val sharpnessWarning = evaluateEdgeSharpness(frame, segResult.mask, segResult.width, segResult.height)
            if (sharpnessWarning != null) warnings.add(sharpnessWarning)
        }

        // Rule 5: Lighting comparison
        if (frame != null) {
            val lightingWarning = evaluateLighting(frame, segResult.mask, segResult.width, segResult.height)
            if (lightingWarning != null) warnings.add(lightingWarning)
        }

        return buildPayload(segResult.centroidX, segResult.centroidY, sceneType, warnings)
    }

    /**
     * Evaluate composition using a bounding box (fallback path).
     * Edge sharpness is skipped since we don't have a precise mask boundary.
     */
    fun evaluateWithBoundingBox(
        bboxLeft: Float,
        bboxTop: Float,
        bboxRight: Float,
        bboxBottom: Float,
        sceneType: String,
        frame: Bitmap? = null
    ): GuidancePayload {
        val warnings = mutableListOf<GuidanceWarning>()

        val centroidX = (bboxLeft + bboxRight) / 2f
        val centroidY = (bboxTop + bboxBottom) / 2f
        val sizeRatio = (bboxRight - bboxLeft) * (bboxBottom - bboxTop)

        // Rule 1: Centroid placement
        val centroidWarning = evaluateCentroidPlacement(centroidX, centroidY, sceneType)
        if (centroidWarning != null) warnings.add(centroidWarning)

        // Rule 2: Size ratio
        val sizeWarning = evaluateSizeRatio(sizeRatio)
        if (sizeWarning != null) warnings.add(sizeWarning)

        // Rule 3: Background entropy (uses inverse bbox)
        if (frame != null) {
            val bboxMask = createBboxMask(bboxLeft, bboxTop, bboxRight, bboxBottom, frame.width, frame.height)
            val entropyWarning = evaluateBackgroundEntropy(frame, bboxMask, frame.width, frame.height)
            if (entropyWarning != null) warnings.add(entropyWarning)
        }

        // Rule 4: Edge sharpness — SKIPPED for bbox input
        // (No precise mask boundary available)

        // Rule 5: Lighting comparison
        if (frame != null) {
            val bboxMask = createBboxMask(bboxLeft, bboxTop, bboxRight, bboxBottom, frame.width, frame.height)
            val lightingWarning = evaluateLighting(frame, bboxMask, frame.width, frame.height)
            if (lightingWarning != null) warnings.add(lightingWarning)
        }

        return buildPayload(centroidX, centroidY, sceneType, warnings)
    }

    // ─── Rule Implementations ────────────────────────────────────────────────

    /**
     * Rule 1: Evaluate subject centroid against acceptable zones per scene type.
     */
    private fun evaluateCentroidPlacement(
        centroidX: Float,
        centroidY: Float,
        sceneType: String
    ): GuidanceWarning? {
        val zone = getAcceptableZone(sceneType)

        val xInZone = centroidX in zone.xMin..zone.xMax
        val yInZone = centroidY in zone.yMin..zone.yMax

        if (xInZone && yInZone) return null

        // Compute target zone center for arrow direction
        val targetX = (zone.xMin + zone.xMax) / 2f
        val targetY = (zone.yMin + zone.yMax) / 2f

        return GuidanceWarning(
            type = WarningType.PLACEMENT,
            message = "Move subject to improve composition",
            arrowFromX = centroidX,
            arrowFromY = centroidY,
            arrowToX = targetX,
            arrowToY = targetY
        )
    }

    /**
     * Rule 2: Subject-to-frame size ratio check.
     */
    private fun evaluateSizeRatio(sizeRatio: Float): GuidanceWarning? {
        return when {
            sizeRatio < SIZE_TOO_SMALL -> GuidanceWarning(
                type = WarningType.SIZE,
                message = "Move closer"
            )
            sizeRatio > SIZE_TOO_LARGE -> GuidanceWarning(
                type = WarningType.SIZE,
                message = "Step back"
            )
            else -> null
        }
    }

    /**
     * Rule 3: Background entropy — variance of pixel values in non-masked region.
     */
    private fun evaluateBackgroundEntropy(
        frame: Bitmap,
        mask: BooleanArray,
        width: Int,
        height: Int
    ): GuidanceWarning? {
        var sum = 0.0
        var sumSq = 0.0
        var count = 0

        val pixels = IntArray(width * height)
        frame.getPixels(pixels, 0, width, 0, 0, width, height)

        for (i in pixels.indices) {
            if (!mask[i]) { // Inverse mask = background
                val luminance = pixelLuminance(pixels[i])
                sum += luminance
                sumSq += luminance * luminance
                count++
            }
        }

        if (count == 0) return null

        val mean = sum / count
        val variance = (sumSq / count) - (mean * mean)
        val normalizedVariance = (variance / (255.0 * 255.0)).toFloat()

        return if (normalizedVariance > ENTROPY_THRESHOLD) {
            GuidanceWarning(
                type = WarningType.BACKGROUND,
                message = "Background too busy"
            )
        } else null
    }

    /**
     * Rule 4: Edge sharpness — Laplacian variance on mask boundary pixels.
     */
    private fun evaluateEdgeSharpness(
        frame: Bitmap,
        mask: BooleanArray,
        width: Int,
        height: Int
    ): GuidanceWarning? {
        val pixels = IntArray(width * height)
        frame.getPixels(pixels, 0, width, 0, 0, width, height)

        var laplacianSum = 0.0
        var laplacianSumSq = 0.0
        var count = 0

        // Find boundary pixels (mask edge)
        for (y in 1 until height - 1) {
            for (x in 1 until width - 1) {
                val idx = y * width + x
                if (!mask[idx]) continue

                // Check if on boundary (adjacent to non-mask pixel)
                val isEdge = !mask[idx - 1] || !mask[idx + 1] ||
                        !mask[idx - width] || !mask[idx + width]

                if (isEdge) {
                    // Compute Laplacian at this pixel
                    val center = pixelLuminance(pixels[idx])
                    val left = pixelLuminance(pixels[idx - 1])
                    val right = pixelLuminance(pixels[idx + 1])
                    val top = pixelLuminance(pixels[idx - width])
                    val bottom = pixelLuminance(pixels[idx + width])

                    val laplacian = (left + right + top + bottom) - 4.0 * center
                    laplacianSum += laplacian
                    laplacianSumSq += laplacian * laplacian
                    count++
                }
            }
        }

        if (count < 10) return null // Not enough edge pixels

        val mean = laplacianSum / count
        val variance = (laplacianSumSq / count) - (mean * mean)

        return if (variance < SHARPNESS_THRESHOLD) {
            GuidanceWarning(
                type = WarningType.FOCUS,
                message = "Subject not in focus"
            )
        } else null
    }

    /**
     * Rule 5: Lighting comparison — subject vs background luminance.
     */
    private fun evaluateLighting(
        frame: Bitmap,
        mask: BooleanArray,
        width: Int,
        height: Int
    ): GuidanceWarning? {
        val pixels = IntArray(width * height)
        frame.getPixels(pixels, 0, width, 0, 0, width, height)

        var subjectSum = 0.0
        var bgSum = 0.0
        var subjectCount = 0
        var bgCount = 0

        for (i in pixels.indices) {
            val lum = pixelLuminance(pixels[i])
            if (mask[i]) {
                subjectSum += lum
                subjectCount++
            } else {
                bgSum += lum
                bgCount++
            }
        }

        if (subjectCount == 0 || bgCount == 0) return null

        val subjectMean = subjectSum / subjectCount
        val bgMean = bgSum / bgCount

        // Backlit = subject significantly darker than background
        val delta = (bgMean - subjectMean) / bgMean

        return if (delta > BACKLIGHT_DELTA) {
            GuidanceWarning(
                type = WarningType.LIGHTING,
                message = "Subject backlit — reposition or use fill flash"
            )
        } else null
    }

    // ─── Utility ─────────────────────────────────────────────────────────────

    private fun pixelLuminance(pixel: Int): Double {
        val r = (pixel shr 16) and 0xFF
        val g = (pixel shr 8) and 0xFF
        val b = pixel and 0xFF
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    private fun createBboxMask(
        left: Float, top: Float, right: Float, bottom: Float,
        width: Int, height: Int
    ): BooleanArray {
        val mask = BooleanArray(width * height)
        val l = (left * width).toInt().coerceIn(0, width - 1)
        val t = (top * height).toInt().coerceIn(0, height - 1)
        val r = (right * width).toInt().coerceIn(0, width - 1)
        val b = (bottom * height).toInt().coerceIn(0, height - 1)

        for (y in t..b) {
            for (x in l..r) {
                mask[y * width + x] = true
            }
        }
        return mask
    }

    private fun buildPayload(
        centroidX: Float,
        centroidY: Float,
        sceneType: String,
        warnings: List<GuidanceWarning>
    ): GuidancePayload {
        // Composition score: 1.0 minus 0.2 per active warning
        val compositionScore = (1.0f - warnings.size * 0.2f).coerceIn(0f, 1f)

        return GuidancePayload(
            centroidX = centroidX,
            centroidY = centroidY,
            compositionScore = compositionScore,
            warnings = warnings
        )
    }

    /**
     * Get acceptable centroid zone for a given scene type.
     * Per Section 2.2 table.
     */
    private fun getAcceptableZone(sceneType: String): AcceptableZone {
        return when (sceneType) {
            "portrait" -> AcceptableZone(0.2f, 0.8f, 0.25f, 0.55f)  // Left/right third, upper-middle
            "street" -> AcceptableZone(0.2f, 0.8f, 0.3f, 0.6f)      // Left/right third, middle band
            "macro" -> AcceptableZone(0.35f, 0.65f, 0.35f, 0.65f)    // Center-ish
            "wildlife" -> AcceptableZone(0.2f, 0.8f, 0.25f, 0.55f)   // Left/right, upper-middle
            "lowLight" -> AcceptableZone(0.25f, 0.75f, 0.25f, 0.75f) // Relaxed
            else -> AcceptableZone(0.2f, 0.8f, 0.25f, 0.75f)         // Generic fallback
        }
    }
}

// ─── Data Models ─────────────────────────────────────────────────────────────

data class AcceptableZone(
    val xMin: Float, val xMax: Float,
    val yMin: Float, val yMax: Float
)

enum class WarningType {
    PLACEMENT,
    SIZE,
    BACKGROUND,
    FOCUS,
    LIGHTING
}

data class GuidanceWarning(
    val type: WarningType,
    val message: String,
    val arrowFromX: Float = 0f,
    val arrowFromY: Float = 0f,
    val arrowToX: Float = 0f,
    val arrowToY: Float = 0f
) {
    fun toMap(): Map<String, Any> = mapOf(
        "type" to type.name,
        "message" to message,
        "arrowFromX" to arrowFromX,
        "arrowFromY" to arrowFromY,
        "arrowToX" to arrowToX,
        "arrowToY" to arrowToY
    )
}

data class GuidancePayload(
    val centroidX: Float,
    val centroidY: Float,
    val compositionScore: Float,
    val warnings: List<GuidanceWarning>
) {
    fun toMap(): Map<String, Any> = mapOf(
        "centroidX" to centroidX,
        "centroidY" to centroidY,
        "compositionScore" to compositionScore,
        "warnings" to warnings.map { it.toMap() }
    )
}
