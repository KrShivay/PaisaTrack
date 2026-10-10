package com.paisatrack

import android.content.Context
import android.content.ContentResolver
import android.content.Intent
import android.database.MatrixCursor
import android.provider.Telephony
import com.paisatrack.capture.CapturedSms
import com.paisatrack.capture.CapturedSmsSink
import com.paisatrack.capture.InboxCursorQuery
import com.paisatrack.capture.SmsInboxReader
import com.paisatrack.capture.SmsReceiver

/** Fixed synthetic-only proof for the live/inbox SMS identity boundary. */
internal object SmsIdentityQaProbe {
    private const val SyntheticReceivedOffsetMillis = 60_000L
    private const val SyntheticInboxId = 1L
    private const val SyntheticSentAtEpochMillis = 1_791_115_200_000L
    private const val SyntheticSender = "HDFCBK"
    private const val SyntheticBody = "Rs 250 debited from a/c XX1234"

    // GSM SMS-DELIVER from HDFCBK with body "Rs 250 debited from a/c XX1234"
    // and an SMSC timestamp of 2026-10-04 12:00:00 UTC.
    private val syntheticPdu = hexToBytes(
        "00000bd048a271285c020000620140210000001ed23948568381c865719a5e2683ccf2771b147e8d41586c4c36a301",
    )

    fun run(context: Context): Map<String, Any> {
        val liveMessages = mutableListOf<CapturedSms>()
        val originalSink = CapturedSmsSink.current
        try {
            CapturedSmsSink.current = CapturedSmsSink(liveMessages::add)
            SmsReceiver().onReceive(
                context,
                Intent(Telephony.Sms.Intents.SMS_RECEIVED_ACTION).apply {
                    putExtra("pdus", arrayOf(syntheticPdu))
                    putExtra("format", "3gpp")
                },
            )
        } finally {
            CapturedSmsSink.current = originalSink
        }

        check(liveMessages.size == 1) { "Synthetic PDU was not accepted." }
        val live = liveMessages.single()
        check(live.sender == SyntheticSender) { "Synthetic PDU sender differed." }
        check(live.body == SyntheticBody) { "Synthetic PDU body differed." }
        check(live.receivedAtEpochMillis == SyntheticSentAtEpochMillis) {
            "Synthetic PDU timestamp differed."
        }
        val providerReceivedAt = live.receivedAtEpochMillis +
            SyntheticReceivedOffsetMillis
        var requestedDateSent = false
        var sortOrderUsesReceiptDate = false
        val reader = SmsInboxReader.withQuery(
            context,
            InboxCursorQuery { _, projection, queryArgs ->
                requestedDateSent = projection.contains(Telephony.Sms.DATE_SENT)
                sortOrderUsesReceiptDate = queryArgs.getString(
                    ContentResolver.QUERY_ARG_SQL_SORT_ORDER,
                ) == "${Telephony.Sms.DATE} DESC, ${Telephony.Sms._ID} DESC"
                MatrixCursor(projection).apply {
                    addRow(
                        projection.map { column ->
                            when (column) {
                                Telephony.Sms._ID -> SyntheticInboxId
                                Telephony.Sms.ADDRESS -> live.sender
                                Telephony.Sms.BODY -> live.body
                                Telephony.Sms.DATE -> providerReceivedAt
                                Telephony.Sms.DATE_SENT -> live.receivedAtEpochMillis
                                else -> null
                            }
                        },
                    )
                    addRow(
                        projection.map { column ->
                            when (column) {
                                Telephony.Sms._ID -> SyntheticInboxId - 1L
                                Telephony.Sms.ADDRESS -> live.sender
                                Telephony.Sms.BODY -> live.body
                                Telephony.Sms.DATE -> providerReceivedAt - 1_000L
                                Telephony.Sms.DATE_SENT -> live.receivedAtEpochMillis - 1_000L
                                else -> null
                            }
                        },
                    )
                }
            },
        )
        val page = reader.readPage(
            beforeEpochMillis = null,
            beforeId = null,
            limit = 1,
        )
        @Suppress("UNCHECKED_CAST")
        val inboxMessages = page["messages"] as List<Map<String, Any>>
        check(inboxMessages.size == 1) { "Synthetic inbox row was not returned." }
        val inbox = inboxMessages.single()
        val inboxId = inbox["id"] as String
        val expectedLegacyId = com.paisatrack.capture.CapturedSmsId.forMessage(
            sender = live.sender,
            body = live.body,
            receivedAtEpochMillis = providerReceivedAt,
        )
        val legacyId = inbox["legacyId"] as? String

        return mapOf(
            "acceptedByLiveReceiver" to true,
            "acceptedByInboxReader" to true,
            "senderMatchesFixture" to (live.sender == SyntheticSender),
            "bodyMatchesFixture" to (live.body == SyntheticBody),
            "liveTimestampMatchesPdu" to
                (live.receivedAtEpochMillis == SyntheticSentAtEpochMillis),
            "idsMatch" to (live.id == inboxId),
            "legacyReceiptIdMatches" to (legacyId == expectedLegacyId),
            "legacyIdPresent" to (legacyId != null),
            "liveTimestampEpochMillis" to live.receivedAtEpochMillis,
            "inboxTimestampEpochMillis" to
                (inbox["receivedAtEpochMillis"] as Long),
            "syntheticReceivedOffsetMillis" to SyntheticReceivedOffsetMillis,
            "dateSentRequested" to requestedDateSent,
            "pageHasMore" to (page["hasMore"] == true),
            "nextCursorUsesReceivedDate" to
                (page["nextBeforeEpochMillis"] == providerReceivedAt),
            "nextCursorIdMatches" to
                (page["nextBeforeId"] == SyntheticInboxId),
            "sortOrderUsesReceiptDate" to sortOrderUsesReceiptDate,
        )
    }

    private fun hexToBytes(hex: String): ByteArray {
        require(hex.length % 2 == 0)
        return ByteArray(hex.length / 2) { index ->
            hex.substring(index * 2, index * 2 + 2).toInt(16).toByte()
        }
    }
}
