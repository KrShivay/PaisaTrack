package com.paisatrack.sms

class SmsFilter {
    private val transactionalSender = Regex("^[A-Z]{2}-[A-Z0-9]{5,8}$|^[A-Z0-9]{5,8}$")
    private val junkTerms = listOf("otp", "one time password", "verification code", "offer", "sale")

    fun shouldProcess(sender: String, body: String): Boolean {
        val lowerBody = body.lowercase()
        if (junkTerms.any { lowerBody.contains(it) }) {
            return false
        }

        return transactionalSender.matches(sender)
    }
}
