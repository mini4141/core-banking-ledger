package com.corebanking.transfer;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;
import java.time.Instant;

record TransferRequest(@NotBlank String idempotencyKey,
                              @NotBlank String fromAccountId,
                              @NotBlank String toAccountId,
                              @NotNull @DecimalMin("0.01") BigDecimal amount) {
}

/** Body sent to accounts-service for one leg of a transfer. */
record LegRequest(String transferId, String leg, BigDecimal amount) {
}

record LegResult(String accountId, BigDecimal balance, boolean applied) {
}

record TransferView(String id, String idempotencyKey, String fromAccountId, String toAccountId,
                    BigDecimal amount, String status, Instant createdAt) {
    static TransferView of(Transfer t) {
        return new TransferView(t.getId(), t.getIdempotencyKey(), t.getFromId(), t.getToId(),
                t.getAmount(), t.getStatus(), t.getCreatedAt());
    }
}

record TransferOutcome(TransferView transfer, boolean replayed) {
}

/** Kafka payload on topic banking.transfers. */
record TransferCompletedEvent(String eventId, String type, String transferId, String fromAccountId,
                              String toAccountId, BigDecimal amount, Instant occurredAt) {
}
