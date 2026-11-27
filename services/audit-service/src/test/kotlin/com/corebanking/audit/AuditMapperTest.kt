package com.corebanking.audit

import java.math.BigDecimal
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals

class AuditMapperTest {

    @Test
    fun `transfer event maps to a debit and a credit item`() {
        val event = TransferCompleted(
            eventId = "e1", type = "TransferCompleted", transferId = "t1",
            fromAccountId = "A", toAccountId = "B", amount = BigDecimal("10000"),
            occurredAt = Instant.parse("2026-01-01T00:00:00Z"),
        )

        val items = AuditMapper.toItems(event)

        assertEquals(listOf("ACCOUNT#A", "ACCOUNT#B"), items.map { it.pk })
        assertEquals(listOf("DEBIT", "CREDIT"), items.map { it.type })
        assertEquals("TS#2026-01-01T00:00:00Z#t1", items[0].sk)
        assertEquals("B", items[0].counterparty)
    }
}
