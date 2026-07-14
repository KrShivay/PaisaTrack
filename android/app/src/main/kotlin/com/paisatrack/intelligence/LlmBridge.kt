package com.paisatrack.intelligence

import android.app.ActivityManager
import android.content.Context
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/** T-075 on-device LLM. Only [downloadModel] can access the network. */
class LlmBridge(private val context: Context) {
    companion object {
        const val PINNED_MODEL_URL =
            "https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/resolve/" +
                "6c237a59eedeb06a821b21f0a59b03d346ac8bc3/" +
                "Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task"
        const val PINNED_MODEL_SIZE = 546_660_344L
        const val PINNED_MODEL_SHA256 =
            "e608953f169aeb1bd7b9155fec2559825e08453fc209b84eda3a781ed0452fd2"
        const val MODEL_FILE_NAME = "qwen2_5_0_5b_q8_ekv1280.task"
        private const val MIN_TOTAL_MEMORY_BYTES = 3_000_000_000L
        // Covers the compact assistant/SMS prompts plus structured output while
        // halving the fixed KV-cache allocation from the previous 1024.
        internal const val MAX_TOTAL_TOKENS = 512
    }

    private val inferenceCache = LlmInferenceCache()

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
        if (promoteCompletePartial(partial)) return true
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
            promoteCompletePartial(partial)
        } catch (_: Exception) {
            false // Keep a valid-size partial download for the next Range request.
        } finally {
            connection?.disconnect()
        }
    }

    fun deleteModel(): Boolean {
        close()
        val modelDeleted = !modelFile().exists() || modelFile().delete()
        val partialDeleted = !partialFile().exists() || partialFile().delete()
        return modelDeleted && partialDeleted
    }

    fun complete(prompt: String): String? {
        if (!isModelAvailable()) return null
        if (!isDeviceSupported()) throw UnsupportedOperationException("unsupported_device")
        val engine = inferenceCache.getOrCreate { createInference() }
        return try {
            engine.generateResponse(prompt)
        } catch (error: Exception) {
            // A failed native session can poison the cached task runner. Drop
            // it so the next request starts from a clean engine instead of
            // failing repeatedly until the activity is restarted.
            inferenceCache.close()
            throw error
        }
    }

    /** Releases the cached native engine before the Flutter engine is disposed. */
    fun close() {
        inferenceCache.close()
    }

    private fun promoteCompletePartial(partial: File): Boolean =
        LlmModelInstaller.promoteVerifiedPartial(
            partial = partial,
            target = modelFile(),
            expectedSize = PINNED_MODEL_SIZE,
            expectedSha256 = PINNED_MODEL_SHA256,
            beforePromote = ::close,
        )

    private fun createInference(): LlmInferenceHandle {
        val delegate = LlmInference.createFromOptions(
            context,
            LlmInference.LlmInferenceOptions.builder()
                .setModelPath(modelFile().absolutePath)
                .setMaxTokens(MAX_TOTAL_TOKENS)
                .setMaxTopK(1)
                .setPreferredBackend(LlmInference.Backend.CPU)
                .build(),
        )
        return object : LlmInferenceHandle {
            // Greedy decoding (topK=1, temperature=0) so intent classification is
            // deterministic and follows the prompt's examples. Default sampling
            // (topK~40, temp~0.8) made the same question return different intents
            // on each ask. Params live on the session, not LlmInferenceOptions,
            // in tasks-genai 0.10.24, so each one-shot call runs in its own
            // session and closes it to avoid conversation-state carryover.
            override fun generateResponse(prompt: String): String {
                val sessionOptions =
                    LlmInferenceSession.LlmInferenceSessionOptions.builder()
                        .setTopK(1)
                        .setTemperature(0.0f)
                        .setRandomSeed(1)
                        .build()
                return LlmInferenceSession.createFromOptions(delegate, sessionOptions)
                    .use { session ->
                        session.addQueryChunk(prompt)
                        session.generateResponse()
                    }
            }

            override fun close() {
                delegate.close()
            }
        }
    }
}

/** Keeps the heavyweight MediaPipe engine alive for reuse and releases it exactly once. */
internal class LlmInferenceCache {
    private var handle: LlmInferenceHandle? = null

    fun getOrCreate(factory: () -> LlmInferenceHandle): LlmInferenceHandle {
        return handle ?: factory().also { handle = it }
    }

    fun close() {
        try {
            handle?.close()
        } catch (_: Exception) {
            // Best effort; stale native state must not block teardown or model deletion.
        }
        handle = null
    }
}

internal interface LlmInferenceHandle {
    fun generateResponse(prompt: String): String
    fun close()
}

/** Verifies a complete partial file before promoting it without reopening the network. */
internal object LlmModelInstaller {
    fun promoteVerifiedPartial(
        partial: File,
        target: File,
        expectedSize: Long,
        expectedSha256: String,
        beforePromote: () -> Unit,
    ): Boolean {
        if (!partial.isFile || partial.length() != expectedSize) return false
        if (sha256Hex(partial) != expectedSha256) {
            partial.delete()
            return false
        }
        beforePromote()
        if (target.exists() && !target.delete()) return false
        if (partial.renameTo(target)) return target.isFile && target.length() == expectedSize
        return try {
            partial.copyTo(target, overwrite = true)
            if (target.length() != expectedSize || sha256Hex(target) != expectedSha256) {
                target.delete()
                false
            } else {
                partial.delete()
                true
            }
        } catch (_: Exception) {
            target.delete()
            false
        }
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
