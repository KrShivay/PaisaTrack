package com.paisatrack.intelligence

import java.io.ByteArrayInputStream
import java.io.File
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.file.Files
import java.security.MessageDigest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LlmBridgeTest {
    @Test
    fun validFreshDownloadIsVerifiedAndPromoted() = withDirectory { directory ->
        val bytes = "verified model".encodeToByteArray()
        var engineClosed = false
        val downloader = downloader(
            directory = directory,
            expected = bytes,
            connection = FakeConnection(200, bytes),
            beforePromote = { engineClosed = true },
        )

        assertEquals(ModelDownloadState.INSTALLED, downloader.download())
        assertTrue(engineClosed)
        assertTrue(downloader.isInstalled())
        assertEquals(bytes.toList(), downloader.modelFile().readBytes().toList())
        assertFalse(downloader.partialFile().exists())
    }

    @Test
    fun sameSizeCorruptInstalledModelIsRejected() = withDirectory { directory ->
        val expected = "expected".encodeToByteArray()
        val downloader = downloader(directory, expected, FakeConnection(500, byteArrayOf()))
        directory.mkdirs()
        downloader.modelFile().writeBytes("corrupt!".encodeToByteArray())

        assertFalse(downloader.isInstalled())
    }

    @Test
    fun matchingRangeResumeAppendsAndPromotes() = withDirectory { directory ->
        val expected = "good".encodeToByteArray()
        val connection = FakeConnection(
            responseCodeValue = 206,
            body = "od".encodeToByteArray(),
            headers = mapOf("Content-Range" to "bytes 2-3/4"),
        )
        val downloader = downloader(directory, expected, connection)
        directory.mkdirs()
        downloader.partialFile().writeText("go")

        assertEquals(ModelDownloadState.INSTALLED, downloader.download())
        assertEquals("good", downloader.modelFile().readText())
        assertEquals("bytes=2-", connection.getRequestProperty("Range"))
    }

    @Test
    fun oversizedChunkedBodyIsBoundedAndDiscarded() = withDirectory { directory ->
        val expected = "good".encodeToByteArray()
        val connection = FakeConnection(
            responseCodeValue = 200,
            body = "good-extra".encodeToByteArray(),
            contentLengthValue = -1,
        )
        val downloader = downloader(directory, expected, connection)

        val error = runCatching { downloader.download() }.exceptionOrNull()
        assertTrue(error is LlmOperationException)
        assertFalse(downloader.modelFile().exists())
        assertFalse(downloader.partialFile().exists())
    }

    @Test
    fun errorResponseIsRejectedWithoutReadingBody() = withDirectory { directory ->
        val connection = FakeConnection(500, "server error".encodeToByteArray())
        val downloader = downloader(directory, "good".encodeToByteArray(), connection)

        val error = runCatching { downloader.download() }.exceptionOrNull()
        assertTrue(error is LlmOperationException)
        assertFalse(connection.inputStreamOpened)
    }

    @Test
    fun insufficientStorageDoesNotOpenNetwork() = withDirectory { directory ->
        var connectionOpened = false
        val expected = "good".encodeToByteArray()
        val downloader = PinnedModelDownloader(
            modelsDirectory = directory,
            spec = spec(expected),
            connectionFactory = {
                connectionOpened = true
                FakeConnection(200, expected)
            },
            usableSpace = { 0 },
            beforePromote = {},
        )

        val error = runCatching { downloader.download() }.exceptionOrNull()
        assertTrue(error is LlmOperationException)
        assertEquals("insufficient_storage", (error as LlmOperationException).code)
        assertFalse(connectionOpened)
    }

    private fun downloader(
        directory: File,
        expected: ByteArray,
        connection: FakeConnection,
        beforePromote: () -> Unit = {},
    ) = PinnedModelDownloader(
        modelsDirectory = directory,
        spec = spec(expected),
        connectionFactory = { connection },
        usableSpace = { Long.MAX_VALUE },
        beforePromote = beforePromote,
    )

    private fun spec(bytes: ByteArray) = LlmModelSpec(
        id = "test",
        displayName = "Test",
        runtime = "test",
        repository = "test/test",
        revision = "a".repeat(40),
        fileName = "model.litertlm",
        downloadUrl = "https://example.test/model.litertlm",
        sizeBytes = bytes.size.toLong(),
        sha256 = sha256Hex(bytes),
        quantization = "test",
        contextTokens = 32,
        backend = "CPU",
    )

    private fun withDirectory(block: (File) -> Unit) {
        val directory = Files.createTempDirectory("llm_model_test_").toFile()
        try {
            block(directory)
        } finally {
            directory.deleteRecursively()
        }
    }

    private fun sha256Hex(bytes: ByteArray): String = MessageDigest
        .getInstance("SHA-256")
        .digest(bytes)
        .joinToString("") { "%02x".format(it) }
}

private class FakeConnection(
    private val responseCodeValue: Int,
    private val body: ByteArray,
    private val headers: Map<String, String> = emptyMap(),
    private val contentLengthValue: Long = body.size.toLong(),
) : HttpURLConnection(URL("https://example.test/model.litertlm")) {
    var inputStreamOpened = false
        private set

    override fun connect() {
        connected = true
    }

    override fun disconnect() {
        connected = false
    }

    override fun usingProxy(): Boolean = false

    override fun getResponseCode(): Int = responseCodeValue

    override fun getContentLengthLong(): Long = contentLengthValue

    override fun getHeaderField(name: String?): String? = headers[name]

    override fun getInputStream(): InputStream {
        inputStreamOpened = true
        return ByteArrayInputStream(body)
    }
}
