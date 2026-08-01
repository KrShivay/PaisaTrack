package com.paisatrack.capture

import android.content.ContentResolver
import android.content.Context
import android.os.Bundle
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

    /** Returns one raw-inbox page, filtered to financial messages. */
    fun readPage(
        beforeEpochMillis: Long?,
        beforeId: Long?,
        limit: Int,
    ): Map<String, Any> {
        require(limit in 1..MaxPageSize)
        require((beforeEpochMillis == null) == (beforeId == null))
        val projection = arrayOf(
            Telephony.Sms._ID,
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE,
        )
        val selection = beforeEpochMillis?.let {
            "(${Telephony.Sms.DATE} < ?) OR " +
                "(${Telephony.Sms.DATE} = ? AND ${Telephony.Sms._ID} < ?)"
        }
        val selectionArgs = beforeEpochMillis?.let {
            arrayOf(it.toString(), it.toString(), beforeId.toString())
        }
        val queryArgs = Bundle().apply {
            if (selection != null) {
                putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection)
                putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, selectionArgs)
            }
            putString(
                ContentResolver.QUERY_ARG_SQL_SORT_ORDER,
                "${Telephony.Sms.DATE} DESC, ${Telephony.Sms._ID} DESC",
            )
            // One look-ahead row tells the caller whether another page exists.
            putInt(ContentResolver.QUERY_ARG_LIMIT, limit + 1)
        }
        val cursor = appContext.contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            projection,
            queryArgs,
            null,
        ) ?: return mapOf(
            "messages" to emptyList<Map<String, Any>>(),
            "hasMore" to false,
            "scanned" to 0,
            "filterRejected" to 0,
            "unknownSender" to 0,
            "accepted" to 0,
        )

        val results = mutableListOf<Map<String, Any>>()
        var scanned = 0
        var filterRejected = 0
        var unknownSender = 0
        var accepted = 0
        var lastDate: Long? = null
        var lastId: Long? = null
        var hasMore = false
        cursor.use { rows ->
            val idIndex = rows.getColumnIndexOrThrow(Telephony.Sms._ID)
            val addressIndex = rows.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val bodyIndex = rows.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val dateIndex = rows.getColumnIndexOrThrow(Telephony.Sms.DATE)

            while (scanned < limit && rows.moveToNext()) {
                scanned++
                val inboxId = rows.getLong(idIndex)
                val receivedAtEpochMillis = rows.getLong(dateIndex)
                lastId = inboxId
                lastDate = receivedAtEpochMillis
                when (classifyInboxAdmission(
                    rows.getString(addressIndex),
                    rows.getString(bodyIndex),
                )) {
                    SmsInboxAdmission.FILTER_REJECTED -> filterRejected++
                    SmsInboxAdmission.UNKNOWN_SENDER -> unknownSender++
                    SmsInboxAdmission.ACCEPTED -> {
                        accepted++
                        val sender = rows.getString(addressIndex)!!
                        val body = rows.getString(bodyIndex)!!
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
            }
            hasMore = rows.moveToNext()
        }
        return mutableMapOf<String, Any>(
            "messages" to results,
            "hasMore" to hasMore,
            "scanned" to scanned,
            "filterRejected" to filterRejected,
            "unknownSender" to unknownSender,
            "accepted" to accepted,
        ).apply {
            if (hasMore && lastDate != null && lastId != null) {
                put("nextBeforeEpochMillis", checkNotNull(lastDate))
                put("nextBeforeId", checkNotNull(lastId))
            }
        }
    }

    private companion object {
        const val MaxPageSize = 500
    }
}

internal enum class SmsInboxAdmission {
    FILTER_REJECTED,
    UNKNOWN_SENDER,
    ACCEPTED,
}

internal fun classifyInboxAdmission(sender: String?, body: String?): SmsInboxAdmission {
    if (sender == null) return SmsInboxAdmission.UNKNOWN_SENDER
    if (body == null) return SmsInboxAdmission.FILTER_REJECTED

    val unknownBefore = SmsFilter.batchUnknownSenderDropCount.get()
    val allowed = SmsFilter.isAllowed(sender, body, isBatch = true)
    val unknownAfter = SmsFilter.batchUnknownSenderDropCount.get()
    if (allowed) return SmsInboxAdmission.ACCEPTED
    return if (unknownAfter > unknownBefore) {
        SmsInboxAdmission.UNKNOWN_SENDER
    } else {
        SmsInboxAdmission.FILTER_REJECTED
    }
}
