package com.paisatrack.capture

import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

class SmsInboxReaderTest {
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
