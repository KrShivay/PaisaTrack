package com.paisatrack.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class SmsInboxReaderTest {
    @Test
    fun positiveSentTimeIsCanonicalAndReceiptTimeIsExactLegacyAlias() {
        val identity = CapturedSmsId.forInboxMessage(
            sender = "HDFCBK",
            body = "Rs 250 debited from a/c XX1234",
            receivedAtEpochMillis = 1_791_115_260_000L,
            sentAtEpochMillis = 1_791_115_200_000L,
        )

        assertEquals(
            CapturedSmsId.forMessage(
                "HDFCBK",
                "Rs 250 debited from a/c XX1234",
                1_791_115_200_000L,
            ),
            identity.id,
        )
        assertEquals(
            CapturedSmsId.forMessage(
                "HDFCBK",
                "Rs 250 debited from a/c XX1234",
                1_791_115_260_000L,
            ),
            identity.legacyReceivedId,
        )
        assertNotEquals(identity.id, identity.legacyReceivedId)
        assertEquals(1_791_115_200_000L, identity.identityTimestampEpochMillis)
    }

    @Test
    fun missingNullAndZeroSentTimeFallBackToReceiptTimeWithoutAlias() {
        val receivedAt = 1_791_115_260_000L
        val expectedId = CapturedSmsId.forMessage(
            "HDFCBK",
            "Rs 250 debited from a/c XX1234",
            receivedAt,
        )

        listOf(null, 0L, -1L).forEach { sentAt ->
            val identity = CapturedSmsId.forInboxMessage(
                sender = "HDFCBK",
                body = "Rs 250 debited from a/c XX1234",
                receivedAtEpochMillis = receivedAt,
                sentAtEpochMillis = sentAt,
            )
            assertEquals(expectedId, identity.id)
            assertNull(identity.legacyReceivedId)
            assertEquals(receivedAt, identity.identityTimestampEpochMillis)
        }

        val missingSentColumnIdentity = CapturedSmsId.forInboxMessage(
            sender = "HDFCBK",
            body = "Rs 250 debited from a/c XX1234",
            receivedAtEpochMillis = receivedAt,
            sentAtEpochMillis = null,
        )
        assertEquals(expectedId, missingSentColumnIdentity.id)
    }

    @Before
    fun setUp() {
        SmsFilter.resetCounters()
    }

    @Test
    fun missingSenderIsUnknownSender() {
        assertEquals(
            SmsInboxAdmission.UNKNOWN_SENDER,
            classifyInboxAdmission(null, "Rs 250 debited from a/c XX1234"),
        )
    }

    @Test
    fun missingBodyIsFilterRejected() {
        assertEquals(
            SmsInboxAdmission.FILTER_REJECTED,
            classifyInboxAdmission("AD-HDFCBK", null),
        )
    }

    @Test
    fun unknownSenderRejectedByFilterIsUnknownSender() {
        assertEquals(
            SmsInboxAdmission.UNKNOWN_SENDER,
            classifyInboxAdmission("+919999999999", "Rs 250 debited from a/c XX1234"),
        )
    }

    @Test
    fun knownSenderWithoutTransactionSignalIsFilterRejected() {
        assertEquals(
            SmsInboxAdmission.FILTER_REJECTED,
            classifyInboxAdmission("AD-HDFCBK", "Get Rs 500 cashback offer today."),
        )
    }

    @Test
    fun transactionalKnownSenderIsAccepted() {
        assertEquals(
            SmsInboxAdmission.ACCEPTED,
            classifyInboxAdmission("AD-HDFCBK", "Rs 250 debited from a/c XX1234"),
        )
    }
}
