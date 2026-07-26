package com.paisatrack.intelligence

import android.content.Context
import java.io.File

/** Local-only LiteRT-LM bridge. Only [downloadModel] opens a network connection. */
class LlmBridge(private val context: Context) {
    private val spec = LlmModels.active
    private val modelsDirectory = File(context.filesDir, "models")
    private val engine: LiteRtEngineHandle =
        LiteRtLlmEngine(context, spec) { downloader.modelFile().absolutePath }
    private var progress =
        ModelDownloadProgress(ModelDownloadState.IDLE, 0, spec.sizeBytes)
    private val downloader = PinnedModelDownloader(
        modelsDirectory = modelsDirectory,
        spec = spec,
        beforePromote = ::close,
        onProgress = { progress = it },
    )
    private val eligibility = DeviceEligibility(context, modelsDirectory)

    fun isDeviceSupported(): Boolean =
        eligibility.evaluate(spec, downloader.isInstalled()).supported

    fun isModelAvailable(): Boolean = downloader.isInstalled()

    fun modelStatus(): Map<String, Any> {
        val installed = downloader.isInstalled()
        val support = eligibility.evaluate(spec, installed)
        return mutableMapOf<String, Any>(
            "modelId" to spec.id,
            "displayName" to spec.displayName,
            "sizeBytes" to spec.sizeBytes,
            "runtime" to spec.runtime,
            "quantization" to spec.quantization,
            "contextTokens" to spec.contextTokens,
            "installed" to installed,
            "downloadState" to progress.state.wireValue,
            "downloadedBytes" to progress.downloadedBytes,
        ).apply {
            putAll(support.toMap())
        }
    }

    fun downloadModel(): Boolean {
        val support = eligibility.evaluate(spec, downloader.isInstalled())
        if (!support.downloadSupported) {
            throw LlmOperationException(support.reason)
        }
        return when (downloader.download()) {
            ModelDownloadState.INSTALLED -> true
            ModelDownloadState.CANCELLED -> throw LlmOperationException("download_cancelled")
            else -> false
        }
    }

    fun cancelModelDownload(): Boolean {
        downloader.cancel()
        return true
    }

    fun deleteModel(): Boolean = downloader.delete()

    fun complete(
        systemInstruction: String,
        userMessage: String,
        task: LlmTask,
    ): String? {
        if (!downloader.isInstalled()) return null
        val support = eligibility.evaluate(spec, installed = true)
        if (!support.supported) throw LlmOperationException(support.reason)
        return engine.complete(systemInstruction, userMessage, task)
    }

    fun close() {
        engine.close()
    }
}
