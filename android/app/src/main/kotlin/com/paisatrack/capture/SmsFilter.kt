package com.paisatrack.capture

/**
 * Decides whether an incoming SMS should enter the capture pipeline.
 *
 * This is deliberately pure Kotlin (no Android framework types) so it can be
 * unit tested on the JVM. It is a first-pass allowlist: Phase 1 fixture work
 * (T-024) refines the sender tokens and rejection markers against real SMS.
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
        "KOTAKB", "PNBSMS", "CANBNK", "BOIIND", "YESBNK", "IDFCFB", "INDUSB",
        "CENTBK", "UNIONB", "BOBSMS", "RBLBNK", "AUBANK", "FEDBNK", "IDBIBK",
        "PAYTMB", "PHONPE", "GPAYUP", "AMZNUP", "MOBKWK", "SLICEIT",
    )

    private val otpMarkers = listOf(
        "otp", "one time password", "one-time password", "do not share",
        "verification code", "secure code",
    )

    private val promoMarkers = listOf(
        "offer", "sale", "discount", "lowest price", "cashback offer",
        "win ", "congratulations", "limited period", "apply now", "pre-approved",
    )

    /**
     * Returns true only for messages that look like transactional bank/UPI
     * alerts from a known sender and are not OTP or promotional.
     */
    fun isAllowed(sender: String, body: String): Boolean {
        val normalizedSender = sender.trim().uppercase()
        if (normalizedSender.isEmpty()) return false

        // Personal numbers (all digits, optionally +country code) are not banks.
        if (normalizedSender.removePrefix("+").all { it.isDigit() }) return false

        val token = headerToken(normalizedSender) ?: return false
        if (token !in bankTokens) return false

        val lowerBody = body.lowercase()
        if (otpMarkers.any { lowerBody.contains(it) }) return false
        if (promoMarkers.any { lowerBody.contains(it) }) return false
        return true
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
