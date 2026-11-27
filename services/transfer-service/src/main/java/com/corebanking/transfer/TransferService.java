package com.corebanking.transfer;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;

@Service
class TransferService {

    private static final Logger log = LoggerFactory.getLogger(TransferService.class);

    private final AccountsGateway accounts;
    private final TransferRepository transfers;
    private final IdempotencyStore idempotency;
    private final TransferEventPublisher events;
    private final ObjectMapper mapper;

    TransferService(AccountsGateway accounts, TransferRepository transfers, IdempotencyStore idempotency,
                    TransferEventPublisher events, ObjectMapper mapper) {
        this.accounts = accounts;
        this.transfers = transfers;
        this.idempotency = idempotency;
        this.events = events;
        this.mapper = mapper;
    }

    /** validate, claim idempotency key, debit, credit (compensate on failure), persist, publish. */
    TransferOutcome transfer(TransferRequest req) {
        if (req.fromAccountId().equals(req.toAccountId())) {
            throw new BusinessException("VALIDATION_FAILED", "source and destination must differ", 400);
        }
        if (!idempotency.tryAcquire(req.idempotencyKey())) {
            return replay(req.idempotencyKey());
        }
        String transferId = UUID.randomUUID().toString();
        MDC.put("transferId", transferId);
        try {
            TransferView view = execute(transferId, req);
            idempotency.complete(req.idempotencyKey(), toJson(view));
            return new TransferOutcome(view, false);
        } catch (RuntimeException e) {
            idempotency.release(req.idempotencyKey());
            throw e;
        } finally {
            MDC.remove("transferId");
        }
    }

    private TransferView execute(String transferId, TransferRequest req) {
        accounts.debit(req.fromAccountId(), new LegRequest(transferId, "DEBIT", req.amount()));
        try {
            accounts.credit(req.toAccountId(), new LegRequest(transferId, "CREDIT", req.amount()));
        } catch (RuntimeException creditFailure) {
            log.warn("credit failed, compensating transferId={}", transferId, creditFailure);
            String status = compensate(transferId, req);
            transfers.save(new Transfer(transferId, req.idempotencyKey(), req.fromAccountId(),
                    req.toAccountId(), req.amount(), status));
            throw creditFailure;
        }
        Transfer saved = transfers.save(new Transfer(transferId, req.idempotencyKey(), req.fromAccountId(),
                req.toAccountId(), req.amount(), "COMPLETED"));
        events.publish(new TransferCompletedEvent(UUID.randomUUID().toString(), "TransferCompleted", transferId,
                req.fromAccountId(), req.toAccountId(), req.amount(), Instant.now()));
        log.info("transfer completed transferId={} from={} to={} amount={}", transferId,
                req.fromAccountId(), req.toAccountId(), req.amount());
        return TransferView.of(saved);
    }

    private String compensate(String transferId, TransferRequest req) {
        try {
            accounts.credit(req.fromAccountId(), new LegRequest(transferId, "CREDIT_BACK", req.amount()));
            return "REVERSED";
        } catch (RuntimeException e) {
            log.error("compensation failed, manual reversal needed transferId={}", transferId, e);
            return "REVERSAL_PENDING";
        }
    }

    private TransferOutcome replay(String key) {
        Optional<String> stored = idempotency.find(key);
        if (stored.isEmpty() || IdempotencyStore.IN_PROGRESS.equals(stored.get())) {
            throw new BusinessException("IDEMPOTENCY_IN_PROGRESS", "request with this key is still in progress", 409);
        }
        try {
            log.info("idempotent replay key={}", key);
            return new TransferOutcome(mapper.readValue(stored.get(), TransferView.class), true);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException(e);
        }
    }

    private String toJson(TransferView view) {
        try {
            return mapper.writeValueAsString(view);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException(e);
        }
    }

    TransferView get(String id) {
        return transfers.findById(id).map(TransferView::of)
                .orElseThrow(() -> new BusinessException("TRANSFER_NOT_FOUND", "transfer not found", 404));
    }

    List<TransferView> list(String accountId) {
        PageRequest page = PageRequest.of(0, 50);
        List<Transfer> rows = accountId == null || accountId.isBlank()
                ? transfers.findAllByOrderByCreatedAtDesc(page)
                : transfers.findByAccount(accountId, page);
        return rows.stream().map(TransferView::of).toList();
    }
}
