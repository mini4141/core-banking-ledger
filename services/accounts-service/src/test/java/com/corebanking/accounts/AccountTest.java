package com.corebanking.accounts;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.math.BigDecimal;
import org.junit.jupiter.api.Test;

class AccountTest {

    @Test
    void creditAndDebitAdjustBalance() {
        Account a = new Account("a1", "Alice", "JPY");
        a.credit(new BigDecimal("10000.00"));
        a.debit(new BigDecimal("2500.50"));
        assertEquals(new BigDecimal("7499.50"), a.getBalance());
    }

    @Test
    void debitBeyondBalanceIsRejected() {
        Account a = new Account("a1", "Alice", "JPY");
        a.credit(new BigDecimal("100"));
        assertThrows(InsufficientFundsException.class, () -> a.debit(new BigDecimal("100.01")));
    }
}
