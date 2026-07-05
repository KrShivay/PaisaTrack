package com.paisatrack.capture

import java.security.MessageDigest

/**
 * Deterministic identity for a captured SMS.
 *
 * The same message must hash to the same id whether it arrives live via
 * [SmsReceiver] or is re-read from the inbox by [SmsInboxReader], so that
 * historical backfill (T-023) upserts onto existing rows instead of creating
 * duplicates. Keep this pure (no Android types) and never log message bodies.
 */
internal object CapturedSmsId {
    fun forMessage(
        sender: String,
        body: String,
        receivedAtEpochMillis: Long,
    ): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val raw = "$sender\n$receivedAtEpochMillis\n$body".toByteArray(Charsets.UTF_8)
        val hash = digest.digest(raw)
        return hash.joinToString(separator = "") { byte -> "%02x".format(byte) }
    }
}
