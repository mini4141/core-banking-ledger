package com.corebanking.accounts;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.time.Instant;

record CreateAccountRequest(@NotBlank @Size(max = 100) String customerName,
                            @NotBlank @Pattern(regexp = "[A-Z]{3}") String currency) {
}

record AmountRequest(@NotNull @DecimalMin("0.01") BigDecimal amount) {
}

record LegRequest(@NotBlank String transferId,
                  @Pattern(regexp = "DEBIT|CREDIT|CREDIT_BACK") String leg,
                  @NotNull @DecimalMin("0.01") BigDecimal amount) {
}

record AccountView(String id, String customerName, String currency, BigDecimal balance, Instant createdAt) {
    static AccountView of(Account a) {
        return new AccountView(a.getId(), a.getCustomerName(), a.getCurrency(), a.getBalance(), a.getCreatedAt());
    }
}

record LegResult(String accountId, BigDecimal balance, boolean applied) {
}
