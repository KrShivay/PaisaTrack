package com.paisatrack.capture

import android.content.Context
import android.provider.Telephony

/**
 * Reads historical transactional SMS from the device inbox for backfill (T-023).
 *
 * Only messages accepted by [SmsFilter] are returned, and each is stamped with
 * the same deterministic [CapturedSmsId] as live capture so the Dart ingestor
 * upserts onto existing rows instead of duplicating them. The inbox `DATE`
 * column is stable across reads, so re-running a backfill yields identical ids.
 *
 * Privacy: this class never logs message bodies. The returned payloads stay on
 * device and are consumed synchronously by the encrypted local pipeline.
 */
class SmsInboxReader(context: Context) {
    private val appContext = context.applicationContext

    /**
     * Returns filter-approved inbox messages received at or after
     * [sinceEpochMillis], newest first. Callers run this off the main thread.
     */
    fun readSince(sinceEpochMillis: Long): List<Map<String, Any>> {
        val projection = arrayOf(
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE,
        )
        val selection = "${Telephony.Sms.DATE} >= ?"
        val selectionArgs = arrayOf(sinceEpochMillis.toString())
        val cursor = appContext.contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            "${Telephony.Sms.DATE} DESC",
        ) ?: return emptyList()

        val results = mutableListOf<Map<String, Any>>()
        cursor.use { rows ->
            val addressIndex = rows.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val bodyIndex = rows.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val dateIndex = rows.getColumnIndexOrThrow(Telephony.Sms.DATE)

            while (rows.moveToNext()) {
                val sender = rows.getString(addressIndex) ?: continue
                val body = rows.getString(bodyIndex) ?: continue
                val receivedAtEpochMillis = rows.getLong(dateIndex)
                if (!SmsFilter.isAllowed(sender, body)) continue

                results.add(
                    mapOf(
                        "id" to CapturedSmsId.forMessage(
                            sender = sender,
                            body = body,
                            receivedAtEpochMillis = receivedAtEpochMillis,
                        ),
                        "sender" to sender,
                        "body" to body,
                        "receivedAtEpochMillis" to receivedAtEpochMillis,
                    ),
                )
            }
        }
        return results
    }
}
