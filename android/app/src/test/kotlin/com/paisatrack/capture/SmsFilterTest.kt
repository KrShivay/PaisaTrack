package com.paisatrack.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class SmsFilterTest {
    @Before
    fun setUp() {
        SmsFilter.resetCounters()
    }

    @Test
    fun allowsTransactionalBankAlert() {
        assertTrue(
            SmsFilter.isAllowed(
                "AD-HDFCBK",
                "Rs 250.00 debited from a/c XX1234 on 05-07-26 to UPI/merchant.",
            ),
        )
    }

    @Test
    fun allowsUpiWalletAlert() {
        assertTrue(
            SmsFilter.isAllowed(
                "VM-PHONPE-S",
                "You paid Rs 120 to Chai Point via UPI. Ref 123456.",
            ),
        )
    }

    @Test
    fun allowsPnbSenderVariants() {
        val body = "Your a/c XX5788 is credited for INR 20.00 on 05-06-25"

        assertTrue(SmsFilter.isAllowed("ONE-PNB", body))
        assertTrue(SmsFilter.isAllowed("AD-PNB-S", body))
        assertTrue(SmsFilter.isAllowed("VM-PNBSMS", body))
    }

    @Test
    fun rejectsPnbNearMatch() {
        assertFalse(
            SmsFilter.isAllowed(
                "AD-PNBX-S",
                "Your a/c XX5788 is credited for INR 20.00 on 05-06-25",
            ),
        )
    }

    @Test
    fun allowsTransactionWithSecurityFooterNoComma() {
        assertTrue(
            SmsFilter.isAllowed(
                "AD-HDFCBK",
                "Rs 1200 debited from a/c XX1234. Do not share your PIN",
            ),
        )
    }

    @Test
    fun allowsTransactionWithSecurityFooterWithComma() {
        assertTrue(
            SmsFilter.isAllowed(
                "AD-HDFCBK",
                "Rs 1,200 debited from a/c XX1234. Do not share your PIN",
            ),
        )
    }

    @Test
    fun allowsCashbackCreditWithCongratulations() {
        assertTrue(
            SmsFilter.isAllowed(
                "AD-HDFCBK",
                "Congratulations! Rs 500 cashback credited to your a/c XX1234",
            ),
        )
    }

    @Test
    fun allowsLegitimateCashbackNoticeNoAccountToken() {
        assertTrue(
            SmsFilter.isAllowed(
                "AD-HDFCBK",
                "You have earned Rs 50 cashback",
            ),
        )
    }

    @Test
    fun rejectsNegativePromo() {
        assertFalse(
            SmsFilter.isAllowed(
                "AD-HDFCBK",
                "Congratulations! You've won a chance to get Rs 10,000",
            ),
        )
    }

    @Test
    fun rejectsOtpWithSecureCode() {
        assertFalse(
            SmsFilter.isAllowed(
                "VK-HDFCBK",
                "Your OTP for bank login is 123456. Secure code.",
            ),
        )
    }

    @Test
    fun rejectsOtpMessageFromBankHeader() {
        assertFalse(
            SmsFilter.isAllowed(
                "VK-HDFCBK",
                "123456 is your OTP for the transaction. Do not share it.",
            ),
        )
    }

    @Test
    fun rejectsPromotionalMessage() {
        assertFalse(
            SmsFilter.isAllowed(
                "AX-ICICIB",
                "Special offer! Get a pre-approved loan at lowest price. Apply now.",
            ),
        )
    }

    @Test
    fun rejectsPersonalNumberSender() {
        assertFalse(
            SmsFilter.isAllowed(
                "+919876543210",
                "Hey did you get the Rs 500 I sent you?",
            ),
        )
    }

    @Test
    fun rejectsUnknownSenderToken() {
        assertFalse(
            SmsFilter.isAllowed(
                "AD-SHOPXY",
                "Rs 999 debited for your order.",
            ),
        )
    }

    @Test
    fun rejectsEmptySender() {
        assertFalse(SmsFilter.isAllowed("", "Rs 10 debited"))
    }

    @Test
    fun tracksLiveAndBatchDropCountersSeparately() {
        assertEquals(0L, SmsFilter.liveFilterDropCount.get())
        assertEquals(0L, SmsFilter.batchFilterDropCount.get())
        assertEquals(0L, SmsFilter.liveUnknownSenderDropCount.get())
        assertEquals(0L, SmsFilter.batchUnknownSenderDropCount.get())

        SmsFilter.isAllowed("VK-HDFCBK", "Your OTP for login is 123456", isBatch = false)
        SmsFilter.isAllowed("VK-HDFCBK", "Your OTP for login is 654321", isBatch = true)

        assertEquals(1L, SmsFilter.liveFilterDropCount.get())
        assertEquals(1L, SmsFilter.batchFilterDropCount.get())

        SmsFilter.isAllowed("AD-SHOPXY", "Rs 999 debited for your order.", isBatch = false)
        SmsFilter.isAllowed("+919876543210", "Hey did you get the Rs 500?", isBatch = true)

        assertEquals(1L, SmsFilter.liveUnknownSenderDropCount.get())
        assertEquals(1L, SmsFilter.batchUnknownSenderDropCount.get())
    }

    @Test
    fun exposesContentFreeCounterSnapshot() {
        SmsFilter.isAllowed("AD-SHOPXY", "Rs 999 debited for your order.")
        SmsFilter.isAllowed("AD-SHOPXY", "Rs 999 debited for your order.", isBatch = true)

        assertEquals(
            SmsFilterCounters(
                liveFilterRejected = 0,
                batchFilterRejected = 0,
                liveUnknownSender = 1,
                batchUnknownSender = 1,
            ),
            SmsFilter.counters(),
        )
    }
}
