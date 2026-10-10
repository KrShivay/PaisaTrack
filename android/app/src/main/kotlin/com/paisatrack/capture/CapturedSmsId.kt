package com.paisatrack.capture

import java.security.MessageDigest

/**
 * Deterministic identity for a captured SMS.
 *
 * Live capture hashes the PDU timestamp. Inbox identity matches it only when
 * the provider exposes the same positive value in DATE_SENT; missing, zero,
 * or unusable DATE_SENT falls back to receipt DATE and can retain the prior
 * timestamp mismatch. The receipt-time hash stays available as one exact-body
 * compatibility alias. Keep this pure (no Android types) and never log bodies.
 */
internal object CapturedSmsId {
    data class InboxIdentity(
        val id: String,
        val legacyReceivedId: String?,
        val identityTimestampEpochMillis: Long,
    )

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

    fun forInboxMessage(
        sender: String,
        body: String,
        receivedAtEpochMillis: Long,
        sentAtEpochMillis: Long?,
    ): InboxIdentity {
        val canonicalTimestamp = sentAtEpochMillis
            ?.takeIf { it > 0L }
            ?: receivedAtEpochMillis
        val canonicalId = forMessage(sender, body, canonicalTimestamp)
        val legacyId = if (canonicalTimestamp != receivedAtEpochMillis) {
            forMessage(sender, body, receivedAtEpochMillis)
        } else {
            null
        }
        return InboxIdentity(canonicalId, legacyId, canonicalTimestamp)
    }
}
