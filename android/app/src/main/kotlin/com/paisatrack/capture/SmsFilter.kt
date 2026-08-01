package com.paisatrack.capture

import java.util.concurrent.atomic.AtomicLong

/**
 * Decides whether an incoming SMS should enter the capture pipeline.
 *
 * This is deliberately pure Kotlin (no Android framework types) so it can be
 * unit tested on the JVM. It is a first-pass allowlist.
 *
 * Privacy: this class never logs message bodies.
 */
object SmsFilter {
    /**
     * Alphabetic tokens found in Indian DLT header sender IDs for banks, cards,
     * and UPI/wallet services (the part after the 2-char operator prefix).
     */
    private val bankTokens = setOf(
        "HDFCBK", "ICICIB", "ICICIT", "SBIINB", "SBICRD", "SBIUPI", "AXISBK",
        "KOTAKB", "PNBSMS", "PNB", "CANBNK", "BOIIND", "YESBNK", "IDFCFB", "INDUSB",
        "CENTBK", "UNIONB", "BOBSMS", "RBLBNK", "AUBANK", "FEDBNK", "IDBIBK",
        "PAYTMB", "PHONPE", "GPAYUP", "AMZNUP", "MOBKWK", "SLICEIT",
    )

    private val otpMarkers = setOf(
        "otp", "one time password", "one-time password", "do not share",
        "don't share", "never share", "verification code", "secure code",
    )

    private val promoMarkers = setOf(
        "offer", "sale", "discount", "lowest price", "cashback offer",
        "win ", "congratulations", "limited period", "apply now", "pre-approved",
    )

    private val settledVerbs = setOf(
        "debited", "credited", "spent", "paid", "received", "transferred", "withdrawn",
    )

    private val accountTokenRegex = Regex("""\b(a/c|acct|card|xx\d{4}|x\d{4})\b""")
    private val otpShapeRegex = Regex("""\b\d{4,8}\b""")

    val liveFilterDropCount = AtomicLong(0)
    val batchFilterDropCount = AtomicLong(0)
    val liveUnknownSenderDropCount = AtomicLong(0)
    val batchUnknownSenderDropCount = AtomicLong(0)

    fun resetCounters() {
        liveFilterDropCount.set(0)
        batchFilterDropCount.set(0)
        liveUnknownSenderDropCount.set(0)
        batchUnknownSenderDropCount.set(0)
    }

    /** Returns content-free counters for developer diagnostics. */
    fun counters(): SmsFilterCounters = SmsFilterCounters(
        liveFilterRejected = liveFilterDropCount.get(),
        batchFilterRejected = batchFilterDropCount.get(),
        liveUnknownSender = liveUnknownSenderDropCount.get(),
        batchUnknownSender = batchUnknownSenderDropCount.get(),
    )

    /**
     * Returns true only for messages that look like transactional bank/UPI
     * alerts from a known sender and are not OTP or promotional.
     */
    fun isAllowed(sender: String, body: String, isBatch: Boolean = false): Boolean {
        val normalizedSender = sender.trim().uppercase()
        if (normalizedSender.isEmpty()) {
            recordUnknownSenderDrop(isBatch)
            return false
        }

        // Personal numbers (all digits, optionally +country code) are not banks.
        if (normalizedSender.removePrefix("+").all { it.isDigit() }) {
            recordUnknownSenderDrop(isBatch)
            return false
        }

        val token = headerToken(normalizedSender)
        if (token == null || token !in bankTokens) {
            recordUnknownSenderDrop(isBatch)
            return false
        }

        val lowerBody = body.lowercase()
        val hasSettledVerb = settledVerbs.any { lowerBody.contains(it) }

        // OTP check: reject if any OTP marker co-occurs with an OTP shape and no settled verb.
        if (otpMarkers.any { lowerBody.contains(it) }) {
            val hasOtpShape = otpShapeRegex.containsMatchIn(lowerBody)
            if (hasOtpShape && !hasSettledVerb) {
                recordDrop(isBatch)
                return false
            }
        }

        // Promo check: reject if promo marker occurs without a settled verb AND without an account token.
        if (promoMarkers.any { lowerBody.contains(it) }) {
            val hasAccountToken = accountTokenRegex.containsMatchIn(lowerBody)
            if (!hasSettledVerb && !hasAccountToken) {
                recordDrop(isBatch)
                return false
            }
        }

        return true
    }

    private fun recordDrop(isBatch: Boolean) {
        if (isBatch) {
            batchFilterDropCount.incrementAndGet()
        } else {
            liveFilterDropCount.incrementAndGet()
        }
    }

    private fun recordUnknownSenderDrop(isBatch: Boolean) {
        if (isBatch) {
            batchUnknownSenderDropCount.incrementAndGet()
        } else {
            liveUnknownSenderDropCount.incrementAndGet()
        }
    }

    /**
     * Extracts the alphabetic token from a header like `AD-HDFCBK` or
     * `VM-HDFCBK-S`; falls back to the whole ID for tokens without a prefix.
     */
    private fun headerToken(sender: String): String? {
        val parts = sender.split("-").filter { it.isNotEmpty() }
        return when {
            parts.isEmpty() -> null
            parts.size == 1 -> parts[0].takeIf { it.length >= 4 }
            // Prefer the segment that matches a known token (handles XX-TOKEN-S).
            else -> parts.firstOrNull { it in bankTokens } ?: parts[1]
        }
    }
}

data class SmsFilterCounters(
    val liveFilterRejected: Long,
    val batchFilterRejected: Long,
    val liveUnknownSender: Long,
    val batchUnknownSender: Long,
)
