package com.corebanking.accounts;

class AccountNotFoundException extends RuntimeException {
    AccountNotFoundException(String id) {
        super("account not found: " + id);
    }
}

class InsufficientFundsException extends RuntimeException {
    InsufficientFundsException(String accountId) {
        super("insufficient funds on account " + accountId);
    }
}
