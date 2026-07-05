package com.paisatrack.capture

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * Receives incoming SMS, reassembles multipart bodies, and keeps only messages
 * the [SmsFilter] accepts.
 *
 * Delivery of accepted messages into the Dart capture pipeline is added in
 * T-022; for now accepted messages are handed to [CapturedSmsSink.current],
 * which defaults to a no-op. This class never logs message bodies.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            return
        }

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            ?: return

        val partsBySender = messages.groupBy { message ->
            message.displayOriginatingAddress ?: message.originatingAddress ?: ""
        }

        for ((sender, parts) in partsBySender) {
            if (sender.isEmpty()) continue
            val body = parts.joinToString(separator = "") { part ->
                part.displayMessageBody ?: part.messageBody ?: ""
            }
            if (SmsFilter.isAllowed(sender, body)) {
                CapturedSmsSink.current.accept(
                    CapturedSms(
                        sender = sender,
                        body = body,
                        receivedAtEpochMillis = System.currentTimeMillis(),
                    ),
                )
            }
        }
    }
}

/** A sanitized, filter-approved SMS ready for the Dart pipeline. */
data class CapturedSms(
    val sender: String,
    val body: String,
    val receivedAtEpochMillis: Long,
)

/** Destination for filter-approved messages. Replaced by the channel in T-022. */
fun interface CapturedSmsSink {
    fun accept(sms: CapturedSms)

    companion object {
        /** No-op default until T-022 wires the platform channel sink. */
        @Volatile
        var current: CapturedSmsSink = CapturedSmsSink { }
    }
}
