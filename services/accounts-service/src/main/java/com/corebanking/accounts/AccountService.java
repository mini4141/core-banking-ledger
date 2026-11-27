package com.corebanking.accounts;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;
import java.util.function.Supplier;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

@Service
class AccountService {

    private static final Logger log = LoggerFactory.getLogger(AccountService.class);
    private static final int MAX_LOCK_RETRIES = 8;

    private final AccountRepository accounts;
    private final AccountLegRepository legs;
    private final BalanceCache cache;
    private final TransactionTemplate tx;

    AccountService(AccountRepository accounts, AccountLegRepository legs, BalanceCache cache, TransactionTemplate tx) {
        this.accounts = accounts;
        this.legs = legs;
        this.cache = cache;
        this.tx = tx;
    }

    AccountView create(CreateAccountRequest req) {
        Account saved = accounts.save(new Account(UUID.randomUUID().toString(), req.customerName(), req.currency()));
        log.info("account created accountId={}", saved.getId());
        return AccountView.of(saved);
    }

    List<AccountView> list() {
        return accounts.findAll().stream().map(AccountView::of).toList();
    }

    AccountView get(String id) {
        return cache.get(id).orElseGet(() -> {
            AccountView view = AccountView.of(accounts.findById(id).orElseThrow(() -> new AccountNotFoundException(id)));
            cache.put(view);
            return view;
        });
    }

    AccountView deposit(String id, BigDecimal amount) {
        Account a = withLockRetry(() -> tx.execute(s -> {
            Account acc = accounts.findById(id).orElseThrow(() -> new AccountNotFoundException(id));
            acc.credit(amount);
            return accounts.saveAndFlush(acc);
        }));
        cache.evict(id);
        log.info("deposit applied accountId={} amount={}", id, amount);
        return AccountView.of(a);
    }

    /** Applies one leg exactly once: UNIQUE(transfer_id, leg) turns replays into no-ops. */
    LegResult applyLeg(String accountId, LegRequest req) {
        LegResult result;
        try {
            result = withLockRetry(() -> tx.execute(s -> doApplyLeg(accountId, req)));
        } catch (DataIntegrityViolationException duplicate) {
            result = new LegResult(accountId, accounts.findById(accountId).orElseThrow().getBalance(), false);
        }
        cache.evict(accountId);
        log.info("leg {} accountId={} transferId={} applied={}", req.leg(), accountId, req.transferId(), result.applied());
        return result;
    }

    private LegResult doApplyLeg(String accountId, LegRequest req) {
        Account acc = accounts.findById(accountId).orElseThrow(() -> new AccountNotFoundException(accountId));
        if (legs.existsByTransferIdAndLeg(req.transferId(), req.leg())) {
            return new LegResult(accountId, acc.getBalance(), false);
        }
        if ("DEBIT".equals(req.leg())) {
            acc.debit(req.amount());
        } else {
            acc.credit(req.amount());
        }
        legs.saveAndFlush(new AccountLeg(accountId, req.transferId(), req.leg(), req.amount()));
        accounts.saveAndFlush(acc);
        return new LegResult(accountId, acc.getBalance(), true);
    }

    private <T> T withLockRetry(Supplier<T> action) {
        for (int attempt = 1; ; attempt++) {
            try {
                return action.get();
            } catch (ObjectOptimisticLockingFailureException e) {
                if (attempt >= MAX_LOCK_RETRIES) {
                    throw e;
                }
            }
        }
    }
}
