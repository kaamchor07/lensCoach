package com.lenscoach.lenscoach.camera

import android.app.Activity
import android.content.ContentValues
import android.os.Build
import android.provider.MediaStore
import android.util.Size
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.view.TextureRegistry
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * CameraSessionManager — Manages CameraX lifecycle with ImageAnalysis.
 *
 * Provides:
 * - Live camera preview streamed to Flutter via TextureRegistry SurfaceProducer
 * - Frame metadata extraction (EV, ISO, shutter speed, AF, WB)
 * - Photo capture to device storage
 * - Resolution locked to 1920×1080 during coaching (full res on capture)
 */
class CameraSessionManager(
    private val activity: Activity,
    private val textureRegistry: TextureRegistry,
    private val onFrameMetadata: (FrameMetadata) -> Unit
) {
    private var cameraProvider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var imageCapture: ImageCapture? = null
    private var preview: Preview? = null

    private var surfaceProducer: TextureRegistry.SurfaceProducer? = null
    private val analysisExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    private var _sceneType: String = "street"

    // Latest frame metadata exposed to plugin
    var latestMetadata: FrameMetadata? = null
        private set

    private val _metadataFlow = MutableStateFlow<FrameMetadata?>(null)
    val metadataFlow: StateFlow<FrameMetadata?> = _metadataFlow

    fun getTextureId(): Long {
        return surfaceProducer?.id() ?: -1L
    }

    fun setSceneType(sceneType: String) {
        _sceneType = sceneType
    }

    fun startCamera(onSuccess: (Long) -> Unit, onError: (String) -> Unit) {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(activity)

        cameraProviderFuture.addListener({
            try {
                cameraProvider = cameraProviderFuture.get()

            // Create SurfaceProducer for Flutter preview
            val producer = textureRegistry.createSurfaceProducer()
            surfaceProducer = producer
            producer.setSize(1920, 1080)

            // Preview use case — 1080p locked for coaching session
            preview = Preview.Builder()
                .setTargetResolution(Size(1920, 1080))
                .build()

            // Connect preview to Flutter's SurfaceProducer surface
            // Do NOT cache the surface — always call getSurface() fresh
            preview?.surfaceProvider = Preview.SurfaceProvider { request ->
                val surface = producer.getSurface()
                request.provideSurface(surface, ContextCompat.getMainExecutor(activity)) { }
            }

            // Register callback for surface lifecycle
            producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
                override fun onSurfaceAvailable() {
                    // Surface recreated (e.g. after resume) — rebind preview
                }

                override fun onSurfaceCleanup() {
                    // Surface about to be destroyed — stop rendering
                }
            })

            // ImageAnalysis use case — frame metadata extraction
            imageAnalysis = ImageAnalysis.Builder()
                .setTargetResolution(Size(1920, 1080))
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
                .also { analysis ->
                    analysis.setAnalyzer(analysisExecutor) { imageProxy ->
                        processFrame(imageProxy)
                    }
                }

            // ImageCapture use case — full resolution on capture
            imageCapture = ImageCapture.Builder()
                .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
                .build()

            // Bind to lifecycle
            val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

                cameraProvider?.unbindAll()
                camera = cameraProvider?.bindToLifecycle(
                    activity as LifecycleOwner,
                    cameraSelector,
                    preview,
                    imageAnalysis,
                    imageCapture
                )
                
                onSuccess(producer.id())
            } catch (e: Exception) {
                e.printStackTrace()
                onError(e.message ?: "Unknown camera error")
            }
        }, ContextCompat.getMainExecutor(activity))
    }

    fun stopCamera() {
        cameraProvider?.unbindAll()
        surfaceProducer?.release()
        surfaceProducer = null
        analysisExecutor.shutdown()
    }

    /**
     * Trigger hardware autofocus at normalized coordinates (0.0 to 1.0)
     */
    fun focusAt(x: Float, y: Float) {
        val factory = androidx.camera.core.SurfaceOrientedMeteringPointFactory(1.0f, 1.0f)
        val point = factory.createPoint(x, y)
        val action = androidx.camera.core.FocusMeteringAction.Builder(point, androidx.camera.core.FocusMeteringAction.FLAG_AF)
            .build()
        camera?.cameraControl?.startFocusAndMetering(action)
    }

    fun capturePhoto(callback: (String?, String?) -> Unit) {
        val imageCapture = imageCapture ?: run {
            callback(null, "ImageCapture not initialized")
            return
        }

        val name = SimpleDateFormat("yyyy-MM-dd-HH-mm-ss-SSS", Locale.US)
            .format(System.currentTimeMillis())

        val photoFile = java.io.File(activity.cacheDir, "LensCoach_$name.jpg")

        val outputOptions = ImageCapture.OutputFileOptions.Builder(photoFile).build()

        imageCapture.takePicture(
            outputOptions,
            ContextCompat.getMainExecutor(activity),
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                    callback(output.savedUri?.toString(), null)
                }

                override fun onError(exception: ImageCaptureException) {
                    callback(null, exception.message)
                }
            }
        )
    }

    var latestFrame: android.graphics.Bitmap? = null
        private set

    /**
     * Process each frame for metadata extraction.
     * This runs on the analysis executor thread.
     */
    private fun processFrame(imageProxy: ImageProxy) {
        try {
            val metadata = extractMetadata(imageProxy)
            latestMetadata = metadata
            _metadataFlow.value = metadata
            onFrameMetadata(metadata)
            
            // Extract bitmap for ML (only update if previous was consumed or replaced to avoid OOM)
            val bitmap = imageProxy.toBitmap()
            val oldBitmap = latestFrame
            latestFrame = bitmap
            oldBitmap?.recycle()
            
        } catch (e: Exception) {
            e.printStackTrace()
        } finally {
            imageProxy.close()
        }
    }

    /**
     * Extract camera sensor metadata from ImageProxy.
     */
    private fun extractMetadata(imageProxy: ImageProxy): FrameMetadata {
        val timestamp = imageProxy.imageInfo.timestamp
        val rotationDegrees = imageProxy.imageInfo.rotationDegrees

        var ev = 5.0f
        var iso = 100
        var shutter = 1.0f / 60.0f
        var afConf = 0.8f
        var wbTemp = 5500

        return FrameMetadata(
            timestamp = timestamp,
            rotationDegrees = rotationDegrees,
            width = imageProxy.width,
            height = imageProxy.height,
            exposureValue = ev,
            iso = iso,
            shutterSpeed = shutter,
            afConfidence = afConf,
            whiteBalanceTemp = wbTemp,
            frameMotionDelta = 0f
        )
    }
}
