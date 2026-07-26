package com.paisatrack.intelligence

import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean

enum class ModelDownloadState(val wireValue: String) {
    IDLE("idle"),
    DOWNLOADING("downloading"),
    VERIFYING("verifying"),
    INSTALLED("installed"),
    CANCELLED("cancelled"),
    FAILED("failed"),
}

data class ModelDownloadProgress(
    val state: ModelDownloadState,
    val downloadedBytes: Long,
    val totalBytes: Long,
)

class PinnedModelDownloader(
    private val modelsDirectory: File,
    private val spec: LlmModelSpec,
    private val connectionFactory: (URL) -> HttpURLConnection = {
        it.openConnection() as HttpURLConnection
    },
    private val usableSpace: (File) -> Long = { it.usableSpace },
    private val beforePromote: () -> Unit,
    private val onProgress: (ModelDownloadProgress) -> Unit = {},
    private val cancelled: AtomicBoolean = AtomicBoolean(false),
) {
    companion object {
        private const val COPY_BUFFER_SIZE = 64 * 1024
        private const val STORAGE_HEADROOM_BYTES = 128L * 1024 * 1024
        private val CONTENT_RANGE =
            Regex("""bytes\s+(\d+)-(\d+)/(\d+)""", RegexOption.IGNORE_CASE)
    }

    private var verifiedLength = -1L
    private var verifiedModified = -1L

    fun modelFile(): File = File(modelsDirectory, spec.fileName)

    fun partialFile(): File = File(modelsDirectory, "${spec.fileName}.part")

    @Synchronized
    fun isInstalled(): Boolean {
        val target = modelFile()
        if (!target.isFile || target.length() != spec.sizeBytes) return false
        if (target.length() == verifiedLength && target.lastModified() == verifiedModified) {
            return true
        }
        val valid = sha256Hex(target).equals(spec.sha256, ignoreCase = true)
        if (valid) {
            verifiedLength = target.length()
            verifiedModified = target.lastModified()
        }
        return valid
    }

    fun cancel() {
        cancelled.set(true)
    }

    @Synchronized
    fun download(): ModelDownloadState {
        cancelled.set(false)
        if (isInstalled()) {
            emit(ModelDownloadState.INSTALLED, spec.sizeBytes)
            return ModelDownloadState.INSTALLED
        }
        modelsDirectory.mkdirs()
        val partial = partialFile()
        if (partial.length() > spec.sizeBytes) partial.delete()
        if (promoteVerifiedPartial(partial)) return ModelDownloadState.INSTALLED

        val remaining = spec.sizeBytes - partial.length()
        val requiredSpace = remaining + spec.sizeBytes + STORAGE_HEADROOM_BYTES
        if (usableSpace(modelsDirectory) < requiredSpace) {
            emit(ModelDownloadState.FAILED, partial.length())
            throw LlmOperationException("insufficient_storage")
        }

        var connection: HttpURLConnection? = null
        try {
            var offset = if (partial.isFile) partial.length() else 0L
            connection = connectionFactory(URL(spec.downloadUrl)).apply {
                instanceFollowRedirects = true
                connectTimeout = 15_000
                readTimeout = 30_000
                if (offset > 0) setRequestProperty("Range", "bytes=$offset-")
                connect()
            }
            if (connection.url.protocol.lowercase() != "https") {
                throw LlmOperationException("download_failure")
            }

            val responseCode = connection.responseCode
            var append = false
            when (responseCode) {
                HttpURLConnection.HTTP_OK -> {
                    if (offset > 0) partial.delete()
                    offset = 0L
                }
                HttpURLConnection.HTTP_PARTIAL -> {
                    if (offset == 0L || !hasValidContentRange(connection, offset)) {
                        throw LlmOperationException("download_failure")
                    }
                    append = true
                }
                else -> throw LlmOperationException("download_failure")
            }

            val expectedBodyBytes = spec.sizeBytes - offset
            val contentLength = connection.contentLengthLong
            if (contentLength > expectedBodyBytes) {
                throw LlmOperationException("download_failure")
            }

            emit(ModelDownloadState.DOWNLOADING, offset)
            connection.inputStream.use { input ->
                FileOutputStream(partial, append).use { output ->
                    val buffer = ByteArray(COPY_BUFFER_SIZE)
                    var downloaded = offset
                    while (true) {
                        if (cancelled.get()) {
                            emit(ModelDownloadState.CANCELLED, downloaded)
                            return ModelDownloadState.CANCELLED
                        }
                        val maximumRead =
                            minOf(buffer.size.toLong(), spec.sizeBytes - downloaded + 1).toInt()
                        val read = input.read(buffer, 0, maximumRead)
                        if (read < 0) break
                        downloaded += read
                        if (downloaded > spec.sizeBytes) {
                            partial.delete()
                            throw LlmOperationException("download_failure")
                        }
                        output.write(buffer, 0, read)
                        emit(ModelDownloadState.DOWNLOADING, downloaded)
                    }
                }
            }

            if (partial.length() != spec.sizeBytes) {
                emit(ModelDownloadState.FAILED, partial.length())
                return ModelDownloadState.FAILED
            }
            return if (promoteVerifiedPartial(partial)) {
                ModelDownloadState.INSTALLED
            } else {
                ModelDownloadState.FAILED
            }
        } catch (error: LlmOperationException) {
            emit(ModelDownloadState.FAILED, partial.length())
            throw error
        } catch (_: Exception) {
            emit(ModelDownloadState.FAILED, partial.length())
            return ModelDownloadState.FAILED
        } finally {
            connection?.disconnect()
        }
    }

    @Synchronized
    fun delete(): Boolean {
        beforePromote()
        verifiedLength = -1L
        verifiedModified = -1L
        val targetDeleted = !modelFile().exists() || modelFile().delete()
        val partialDeleted = !partialFile().exists() || partialFile().delete()
        emit(ModelDownloadState.IDLE, 0)
        return targetDeleted && partialDeleted
    }

    private fun hasValidContentRange(connection: HttpURLConnection, offset: Long): Boolean {
        val match = CONTENT_RANGE.matchEntire(connection.getHeaderField("Content-Range") ?: "")
            ?: return false
        val start = match.groupValues[1].toLongOrNull() ?: return false
        val end = match.groupValues[2].toLongOrNull() ?: return false
        val total = match.groupValues[3].toLongOrNull() ?: return false
        return start == offset && end >= start && end < spec.sizeBytes && total == spec.sizeBytes
    }

    private fun promoteVerifiedPartial(partial: File): Boolean {
        if (!partial.isFile || partial.length() != spec.sizeBytes) return false
        emit(ModelDownloadState.VERIFYING, spec.sizeBytes)
        if (!sha256Hex(partial).equals(spec.sha256, ignoreCase = true)) {
            partial.delete()
            emit(ModelDownloadState.FAILED, 0)
            return false
        }
        beforePromote()
        val target = modelFile()
        if (target.exists() && !target.delete()) return false
        val promoted = if (partial.renameTo(target)) {
            true
        } else {
            try {
                partial.copyTo(target, overwrite = true)
                val valid = target.length() == spec.sizeBytes &&
                    sha256Hex(target).equals(spec.sha256, ignoreCase = true)
                if (valid) partial.delete() else target.delete()
                valid
            } catch (_: Exception) {
                target.delete()
                false
            }
        }
        if (promoted) {
            verifiedLength = target.length()
            verifiedModified = target.lastModified()
            emit(ModelDownloadState.INSTALLED, spec.sizeBytes)
        }
        return promoted
    }

    private fun emit(state: ModelDownloadState, downloadedBytes: Long) {
        onProgress(ModelDownloadProgress(state, downloadedBytes, spec.sizeBytes))
    }

    private fun sha256Hex(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(COPY_BUFFER_SIZE)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}

class LlmOperationException(val code: String) : RuntimeException(code)
