package com.paisatrack

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AskNowPendingResponseCodecTest {
    @Test
    fun appendsAndDecodesCategoryAndFreeTextResponses() {
        val withCategory = AskNowPendingResponseCodec.append(
            "[]",
            txnId = "txn_1",
            categoryId = "food_dining",
            freeText = null,
        )
        val withFreeText = AskNowPendingResponseCodec.append(
            withCategory,
            txnId = "txn_2",
            categoryId = null,
            freeText = "Petrol",
        )

        val decoded = AskNowPendingResponseCodec.decode(withFreeText)

        assertEquals(2, decoded.size)
        assertEquals("txn_1", decoded[0]["txnId"])
        assertEquals("food_dining", decoded[0]["categoryId"])
        assertNull(decoded[0]["freeText"])
        assertEquals("txn_2", decoded[1]["txnId"])
        assertNull(decoded[1]["categoryId"])
        assertEquals("Petrol", decoded[1]["freeText"])

        val afterAck = AskNowPendingResponseCodec.decode(
            AskNowPendingResponseCodec.remove(withFreeText, setOf("txn_1")),
        )
        assertEquals(1, afterAck.size)
        assertEquals("txn_2", afterAck.single()["txnId"])
    }
}
