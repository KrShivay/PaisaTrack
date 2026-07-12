package com.paisatrack.intelligence

import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LlmBridgeTest {
    @Test
    fun completePartialIsVerifiedAndPromotedWithoutAnotherDownload() {
        val directory = Files.createTempDirectory("llm_model_test_").toFile()
        try {
            val partial = File(directory, "model.task.part")
            val target = File(directory, "model.task")
            val bytes = "verified model".encodeToByteArray()
            partial.writeBytes(bytes)
            var inferenceReleased = false

            val promoted = LlmModelInstaller.promoteVerifiedPartial(
                partial = partial,
                target = target,
                expectedSize = bytes.size.toLong(),
                expectedSha256 = sha256Hex(bytes),
                beforePromote = { inferenceReleased = true },
            )

            assertTrue(promoted)
            assertTrue(inferenceReleased)
            assertFalse(partial.exists())
            assertEquals(bytes.toList(), target.readBytes().toList())
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun corruptCompletePartialIsDiscardedInsteadOfPromoted() {
        val directory = Files.createTempDirectory("llm_model_test_").toFile()
        try {
            val partial = File(directory, "model.task.part")
            val target = File(directory, "model.task")
            partial.writeText("corrupt")

            val promoted = LlmModelInstaller.promoteVerifiedPartial(
                partial = partial,
                target = target,
                expectedSize = partial.length(),
                expectedSha256 = "0".repeat(64),
                beforePromote = {},
            )

            assertFalse(promoted)
            assertFalse(partial.exists())
            assertFalse(target.exists())
        } finally {
            directory.deleteRecursively()
        }
    }

    @Test
    fun closingCacheReleasesTheNativeInferenceHandleOnce() {
        val cache = LlmInferenceCache()
        val handle = FakeInferenceHandle()

        cache.getOrCreate { handle }
        cache.close()
        cache.close()

        assertEquals(1, handle.closeCalls)
    }

    private fun sha256Hex(bytes: ByteArray): String = MessageDigest
        .getInstance("SHA-256")
        .digest(bytes)
        .joinToString("") { "%02x".format(it) }
}

private class FakeInferenceHandle : LlmInferenceHandle {
    var closeCalls = 0
        private set

    override fun generateResponse(prompt: String): String = "response"

    override fun close() {
        closeCalls += 1
    }
}
