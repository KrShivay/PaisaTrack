package com.paisatrack.intelligence

import android.app.ActivityManager
import android.content.Context
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/** T-075 on-device LLM. Only [downloadModel] can access the network. */
class LlmBridge(private val context: Context) {
    companion object {
        const val PINNED_MODEL_URL =
            "https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/" +
                "19edb84c69a0212f29a6ef17ba0d6f278b6a1614/" +
                "Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.task"
        const val PINNED_MODEL_SIZE = 1_598_556_720L
        const val PINNED_MODEL_SHA256 =
            "82968d0a6c3872cf016fdbcfc591571605f4c7fd2b0f64d2533df502cc6596b3"
        const val MODEL_FILE_NAME = "qwen2_5_1_5b_q8_ekv4096.task"
        private const val MIN_TOTAL_MEMORY_BYTES = 3_000_000_000L
    }

    private var inference: LlmInference? = null

    private fun modelsDir() = File(context.filesDir, "models")
    private fun modelFile() = File(modelsDir(), MODEL_FILE_NAME)
    private fun partialFile() = File(modelsDir(), "$MODEL_FILE_NAME.part")

    fun isDeviceSupported(): Boolean {
        val info = ActivityManager.MemoryInfo()
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        manager.getMemoryInfo(info)
        return info.totalMem >= MIN_TOTAL_MEMORY_BYTES && !manager.isLowRamDevice
    }

    fun isModelAvailable(): Boolean {
        val file = modelFile()
        return file.isFile && file.length() == PINNED_MODEL_SIZE
    }

    fun downloadModel(): Boolean {
        if (isModelAvailable()) return true
        modelsDir().mkdirs()
        val partial = partialFile()
        if (partial.length() > PINNED_MODEL_SIZE) partial.delete()
        var connection: HttpURLConnection? = null
        return try {
            val offset = if (partial.isFile) partial.length() else 0L
            connection = URL(PINNED_MODEL_URL).openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = true
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            if (offset > 0) connection.setRequestProperty("Range", "bytes=$offset-")
            connection.connect()
            val resumed = offset > 0 && connection.responseCode == HttpURLConnection.HTTP_PARTIAL
            val append = resumed
            if (offset > 0 && !resumed) partial.delete()
            connection.inputStream.use { input ->
                FileOutputStream(partial, append).use { output -> input.copyTo(output) }
            }
            if (partial.length() != PINNED_MODEL_SIZE) return false
            if (sha256Hex(partial) != PINNED_MODEL_SHA256) {
                partial.delete()
                return false
            }
            closeInference()
            val target = modelFile()
            target.delete()
            if (!partial.renameTo(target)) partial.copyTo(target, overwrite = true)
            isModelAvailable()
        } catch (_: Exception) {
            false // Keep a valid-size partial download for the next Range request.
        } finally {
            connection?.disconnect()
        }
    }

    fun deleteModel(): Boolean {
        closeInference()
        val modelDeleted = !modelFile().exists() || modelFile().delete()
        val partialDeleted = !partialFile().exists() || partialFile().delete()
        return modelDeleted && partialDeleted
    }

    fun complete(prompt: String): String? {
        if (!isModelAvailable()) return null
        if (!isDeviceSupported()) throw UnsupportedOperationException("unsupported_device")
        val engine = inference ?: LlmInference.createFromOptions(
            context,
            LlmInference.LlmInferenceOptions.builder()
                .setModelPath(modelFile().absolutePath)
                .setMaxTokens(1024)
                .build(),
        ).also { inference = it }
        return engine.generateResponse(prompt)
    }

    private fun closeInference() {
        try {
            inference?.close()
        } catch (_: Exception) {
            // Best effort; stale native state must not block model deletion.
        }
        inference = null
    }

    private fun sha256Hex(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
