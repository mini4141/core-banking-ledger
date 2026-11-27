package com.corebanking.accounts;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;
import java.math.BigDecimal;
import java.time.Instant;

@Entity
@Table(name = "accounts")
public class Account {

    @Id
    private String id;
    @Column(name = "customer_name", nullable = false)
    private String customerName;
    @Column(nullable = false, length = 3)
    private String currency;
    @Column(nullable = false)
    private BigDecimal balance = BigDecimal.ZERO;
    @Version
    private long version;
    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    protected Account() {
    }

    public Account(String id, String customerName, String currency) {
        this.id = id;
        this.customerName = customerName;
        this.currency = currency;
    }

    public void credit(BigDecimal amount) {
        balance = balance.add(amount);
    }

    public void debit(BigDecimal amount) {
        if (balance.compareTo(amount) < 0) {
            throw new InsufficientFundsException(id);
        }
        balance = balance.subtract(amount);
    }

    public String getId() { return id; }
    public String getCustomerName() { return customerName; }
    public String getCurrency() { return currency; }
    public BigDecimal getBalance() { return balance; }
    public long getVersion() { return version; }
    public Instant getCreatedAt() { return createdAt; }
}
