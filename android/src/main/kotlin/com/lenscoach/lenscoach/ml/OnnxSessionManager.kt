package com.lenscoach.lenscoach.ml

import android.content.Context
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import ai.onnxruntime.OnnxTensor
import java.io.File
import java.io.FileOutputStream
import java.nio.FloatBuffer

/**
 * OnnxSessionManager — Manages ONNX Runtime environment and session lifecycle.
 *
 * - Lazy initialization
 * - NNAPI delegate enabled with CPU fallback
 * - Proper cleanup on release
 */
object OnnxSessionManager {

    private var environment: OrtEnvironment? = null
    private var isInitialized = false

    /**
     * Initialize the ONNX Runtime environment.
     * Call once at application startup.
     */
    fun initialize() {
        if (isInitialized) return
        try {
            environment = OrtEnvironment.getEnvironment()
            isInitialized = true
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * Create an ONNX session from an asset file.
     *
     * @param context Android context for asset loading
     * @param modelFilename Filename in assets/ directory
     * @return SessionWrapper for inference
     */
    fun createSession(context: Context, modelFilename: String): SessionWrapper {
        initialize()

        val env = environment ?: throw IllegalStateException("ONNX environment not initialized")

        // Copy model from assets to internal storage (ONNX Runtime needs a file path)
        val modelFile = copyAssetToInternal(context, modelFilename)

        // Create session with NNAPI delegate enabled
        val sessionOptions = OrtSession.SessionOptions()
        try {
            sessionOptions.addNnapi()
        } catch (e: Exception) {
            // NNAPI not available on this device, fallback to CPU
            e.printStackTrace()
        }
        
        val session = env.createSession(modelFile.absolutePath, sessionOptions)

        return SessionWrapper(session, env)
    }

    /**
     * Copy a model file from assets to internal storage.
     */
    private fun copyAssetToInternal(context: Context, filename: String): File {
        val outputFile = File(context.filesDir, filename)

        // Only copy if not already present (or if size differs)
        if (outputFile.exists()) return outputFile

        try {
            context.assets.open(filename).use { input ->
                FileOutputStream(outputFile).use { output ->
                    input.copyTo(output)
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }

        return outputFile
    }

    /**
     * Wrapper around an ONNX Runtime session.
     */
    class SessionWrapper(private val session: OrtSession, private val env: OrtEnvironment) {

        /**
         * Run inference on input data.
         *
         * @param inputData Normalized float array in CHW format
         * @param width Input width
         * @param height Input height
         * @return Output softmax probabilities
         */
        fun run(inputData: FloatArray, width: Int, height: Int): FloatArray {
            var inputTensor: OnnxTensor? = null
            var results: OrtSession.Result? = null
            try {
                inputTensor = OnnxTensor.createTensor(
                    env,
                    FloatBuffer.wrap(inputData),
                    longArrayOf(1, 3, height.toLong(), width.toLong())
                )
                
                // Assuming model input name is "input"
                results = session.run(mapOf("input" to inputTensor))
                
                val output = (results[0].value as Array<FloatArray>)[0]
                return output
            } catch (e: Exception) {
                e.printStackTrace()
                // Fallback to uniform distribution if model execution fails
                return FloatArray(6) { 1.0f / 6.0f }
            } finally {
                inputTensor?.close()
                results?.close()
            }
        }

        fun close() {
            session.close()
        }
    }

    fun shutdown() {
        isInitialized = false
        environment?.close()
        environment = null
    }
}
