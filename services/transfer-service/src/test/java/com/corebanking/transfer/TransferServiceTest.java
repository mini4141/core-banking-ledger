package com.corebanking.transfer;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import java.math.BigDecimal;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;

class TransferServiceTest {

    private AccountsGateway accounts;
    private TransferRepository repository;
    private IdempotencyStore idempotency;
    private TransferEventPublisher events;
    private TransferService service;

    private final TransferRequest request =
            new TransferRequest("key-1", "acc-a", "acc-b", new BigDecimal("10000"));

    @BeforeEach
    void setUp() {
        accounts = mock(AccountsGateway.class);
        repository = mock(TransferRepository.class);
        idempotency = mock(IdempotencyStore.class);
        events = mock(TransferEventPublisher.class);
        ObjectMapper mapper = new ObjectMapper().registerModule(new JavaTimeModule());
        service = new TransferService(accounts, repository, idempotency, events, mapper);
        when(repository.save(any(Transfer.class))).thenAnswer(i -> i.getArgument(0));
        when(idempotency.tryAcquire("key-1")).thenReturn(true);
    }

    @Test
    void debitsThenCreditsPersistsAndPublishes() {
        TransferOutcome outcome = service.transfer(request);

        assertEquals("COMPLETED", outcome.transfer().status());
        InOrder order = inOrder(accounts, repository, events);
        order.verify(accounts).debit(eq("acc-a"), any(LegRequest.class));
        order.verify(accounts).credit(eq("acc-b"), any(LegRequest.class));
        order.verify(repository).save(any(Transfer.class));
        order.verify(events).publish(any(TransferCompletedEvent.class));
        verify(idempotency).complete(eq("key-1"), any(String.class));
    }

    @Test
    void failedCreditIsCompensatedAndNothingIsPublished() {
        when(accounts.credit(eq("acc-b"), any(LegRequest.class))).thenThrow(new IllegalStateException("down"));

        assertThrows(IllegalStateException.class, () -> service.transfer(request));

        verify(accounts).credit(eq("acc-a"), org.mockito.ArgumentMatchers.argThat(r -> "CREDIT_BACK".equals(r.leg())));
        verify(events, never()).publish(any());
        verify(idempotency).release("key-1");
    }
}
