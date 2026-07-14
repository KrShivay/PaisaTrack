package com.paisatrack.capture

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * Receives incoming SMS, reassembles multipart bodies, and keeps only messages
 * the [SmsFilter] accepts.
 *
 * Accepted messages are forwarded to [CapturedSmsSink.current], which the
 * Flutter host replaces with an event-channel bridge during app startup.
 * This class never logs message bodies.
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
                // The inbox provider stores the SMS/PDU timestamp. Hash the
                // same value here so a later full-history import resolves to
                // the identical SMS and transaction ids.
                val receivedAtEpochMillis = parts.minOf { it.timestampMillis }
                CapturedSmsSink.current.accept(
                    CapturedSms(
                        id = CapturedSmsId.forMessage(
                            sender = sender,
                            body = body,
                            receivedAtEpochMillis = receivedAtEpochMillis,
                        ),
                        sender = sender,
                        body = body,
                        receivedAtEpochMillis = receivedAtEpochMillis,
                    ),
                )
            }
        }
    }
}

/** A sanitized, filter-approved SMS ready for the Dart pipeline. */
data class CapturedSms(
    val id: String,
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
