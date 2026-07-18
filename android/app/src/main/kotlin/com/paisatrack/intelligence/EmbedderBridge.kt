package com.paisatrack.intelligence

import android.content.Context
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.text.textembedder.TextEmbedder
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/**
 * T-050: downloads, verifies, and runs the pinned on-device text-embedding
 * model (ADR 0007 — MediaPipe Universal Sentence Encoder float32 TFLite).
 *
 * Privacy contract (ADR 0002): the ONLY network use is [downloadModel],
 * which fetches the model binary itself and carries no user data. [embed]
 * is file-and-CPU only. The model is never bundled (no redistribution
 * grant, ADR 0007) and lives in app-private storage with a delete control.
 */
class EmbedderBridge(private val context: Context) {

    companion object {
        // ADR 0007 pin — do not edit without a superseding ADR.
        // GCS generation-pinned URL: byte-exact, immutable object.
        const val PINNED_MODEL_URL =
            "https://storage.googleapis.com/download/storage/v1/b/mediapipe-models/o/" +
                "text_embedder%2Funiversal_sentence_encoder%2Ffloat32%2F1%2F" +
                "universal_sentence_encoder.tflite?generation=1682480025058456&alt=media"
        const val PINNED_MODEL_SIZE = 6_120_274L
        const val PINNED_MODEL_SHA256 =
            "89ad3c74175dd8caa398cc22b657296d94302d20c525c12b58b29420f7249749"
        const val MODEL_FILE_NAME = "universal_sentence_encoder.tflite"
    }

    private var textEmbedder: TextEmbedder? = null

    private fun modelFile(): File =
        File(File(context.filesDir, "models"), MODEL_FILE_NAME)

    /** Fast availability check: file present with the pinned byte size. */
    fun isModelAvailable(): Boolean {
        val file = modelFile()
        return file.isFile && file.length() == PINNED_MODEL_SIZE
    }

    /**
     * Downloads the pinned artifact to a temp file, verifies size + SHA-256
     * against the ADR 0007 pin, then atomically moves it into place.
     * Returns true when the verified model is in place (including when it
     * already was). Never leaves a partial or unverified file behind.
     */
    fun downloadModel(): Boolean {
        if (isModelAvailable()) return true
        val target = modelFile()
        target.parentFile?.mkdirs()
        val temp = File.createTempFile("embedder_download", ".tmp", context.cacheDir)
        try {
            val connection = URL(PINNED_MODEL_URL).openConnection() as HttpURLConnection
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.inputStream.use { input ->
                FileOutputStream(temp).use { output -> input.copyTo(output) }
            }
            connection.disconnect()
            if (temp.length() != PINNED_MODEL_SIZE) return false
            if (sha256Hex(temp) != PINNED_MODEL_SHA256) return false
            closeEmbedder()
            target.delete()
            if (!temp.renameTo(target)) {
                temp.copyTo(target, overwrite = true)
            }
            return isModelAvailable()
        } catch (e: Exception) {
            return false
        } finally {
            temp.delete()
        }
    }

    /** Settings delete control (ADR 0007). */
    fun deleteModel(): Boolean {
        closeEmbedder()
        val file = modelFile()
        return !file.exists() || file.delete()
    }

    /**
     * Embeds [text]; returns null when the verified model is not available
     * so callers can fall back without blocking ingest (T-050 AC).
     */
    fun embed(text: String): DoubleArray? {
        if (!isModelAvailable()) return null
        return try {
            val embedder = textEmbedder ?: run {
                // The model lives in app-private files (not APK assets), so it
                // is passed as a read-only mapped buffer rather than an asset
                // path.
                val buffer = java.io.FileInputStream(modelFile()).channel.use { channel ->
                    channel.map(java.nio.channels.FileChannel.MapMode.READ_ONLY, 0, channel.size())
                }
                TextEmbedder.createFromOptions(
                    context,
                    TextEmbedder.TextEmbedderOptions.builder()
                        .setBaseOptions(
                            BaseOptions.builder()
                                .setModelAssetBuffer(buffer)
                                .build(),
                        )
                        .build(),
                ).also { textEmbedder = it }
            }
            val embedding = embedder.embed(text).embeddingResult().embeddings()[0]
            embedding.floatEmbedding().map { it.toDouble() }.toDoubleArray()
        } catch (e: Exception) {
            null
        }
    }

    private fun closeEmbedder() {
        try {
            textEmbedder?.close()
        } catch (_: Exception) {
            // Best effort; a stale native handle must not block delete/replace.
        }
        textEmbedder = null
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
