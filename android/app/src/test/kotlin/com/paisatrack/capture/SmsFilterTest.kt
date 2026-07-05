package com.paisatrack.capture

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SmsFilterTest {
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
}
