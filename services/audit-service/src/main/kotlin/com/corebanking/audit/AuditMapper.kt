package com.corebanking.audit

import java.math.BigDecimal
import java.time.Instant

/** Payload of topic banking.transfers, produced by transfer-service. */
data class TransferCompleted(
    val eventId: String,
    val type: String,
    val transferId: String,
    val fromAccountId: String,
    val toAccountId: String,
    val amount: BigDecimal,
    val occurredAt: Instant,
)

/** One DynamoDB item of table audit_events: PK = ACCOUNT#id, SK = TS#iso#transferId. */
data class AuditItem(
    val pk: String,
    val sk: String,
    val type: String,
    val amount: BigDecimal,
    val counterparty: String,
    val transferId: String,
)

object AuditMapper {
    /** A transfer yields a DEBIT item for the source account and a CREDIT item for the destination. */
    fun toItems(event: TransferCompleted): List<AuditItem> {
        fun item(account: String, type: String, counterparty: String) = AuditItem(
            pk = "ACCOUNT#$account",
            sk = "TS#${event.occurredAt}#${event.transferId}",
            type = type,
            amount = event.amount,
            counterparty = counterparty,
            transferId = event.transferId,
        )
        return listOf(
            item(event.fromAccountId, "DEBIT", event.toAccountId),
            item(event.toAccountId, "CREDIT", event.fromAccountId),
        )
    }
}
