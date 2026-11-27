package com.corebanking.accounts;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import java.time.Instant;

@Entity
@Table(name = "account_legs")
public class AccountLeg {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @Column(name = "account_id", nullable = false)
    private String accountId;
    @Column(name = "transfer_id", nullable = false)
    private String transferId;
    @Column(nullable = false)
    private String leg;
    @Column(nullable = false)
    private BigDecimal amount;
    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    protected AccountLeg() {
    }

    public AccountLeg(String accountId, String transferId, String leg, BigDecimal amount) {
        this.accountId = accountId;
        this.transferId = transferId;
        this.leg = leg;
        this.amount = amount;
    }
}
