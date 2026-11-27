package com.corebanking.transfer;

import feign.FeignException;
import io.github.resilience4j.bulkhead.annotation.Bulkhead;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.ratelimiter.annotation.RateLimiter;
import io.github.resilience4j.retry.annotation.Retry;
import java.util.function.Supplier;
import org.springframework.stereotype.Component;

/**
 * Every call to accounts-service goes through here: retry (2 attempts) around circuit breaker
 * around rate limiter around bulkhead. The accounts legs are idempotent (UNIQUE transfer_id+leg),
 * so retrying them is safe. The 1 s timeout lives on the Feign client.
 */
@Component
class AccountsGateway {

    private final AccountsClient client;

    AccountsGateway(AccountsClient client) {
        this.client = client;
    }

    @Retry(name = "accounts")
    @CircuitBreaker(name = "accounts")
    @RateLimiter(name = "accounts")
    @Bulkhead(name = "accounts")
    LegResult debit(String accountId, LegRequest request) {
        return call(() -> client.debit(accountId, request));
    }

    @Retry(name = "accounts")
    @CircuitBreaker(name = "accounts")
    @RateLimiter(name = "accounts")
    @Bulkhead(name = "accounts")
    LegResult credit(String accountId, LegRequest request) {
        return call(() -> client.credit(accountId, request));
    }

    private LegResult call(Supplier<LegResult> action) {
        try {
            return action.get();
        } catch (FeignException.UnprocessableEntity e) {
            throw new BusinessException("INSUFFICIENT_FUNDS", "insufficient funds", 422);
        } catch (FeignException.NotFound e) {
            throw new BusinessException("ACCOUNT_NOT_FOUND", "account not found", 404);
        }
    }
}
