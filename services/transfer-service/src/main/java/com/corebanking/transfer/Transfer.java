package com.corebanking.transfer;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

@Entity
@Table(name = "transfers")
public class Transfer {

    @Id
    private String id;
    @Column(name = "idempotency_key", nullable = false, unique = true)
    private String idempotencyKey;
    @Column(name = "from_id", nullable = false)
    private String fromId;
    @Column(name = "to_id", nullable = false)
    private String toId;
    @Column(nullable = false)
    private BigDecimal amount;
    @Column(nullable = false)
    private String status;
    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    protected Transfer() {
    }

    public Transfer(String id, String idempotencyKey, String fromId, String toId, BigDecimal amount, String status) {
        this.id = id;
        this.idempotencyKey = idempotencyKey;
        this.fromId = fromId;
        this.toId = toId;
        this.amount = amount;
        this.status = status;
    }

    public String getId() { return id; }
    public String getIdempotencyKey() { return idempotencyKey; }
    public String getFromId() { return fromId; }
    public String getToId() { return toId; }
    public BigDecimal getAmount() { return amount; }
    public String getStatus() { return status; }
    public Instant getCreatedAt() { return createdAt; }
}

interface TransferRepository extends JpaRepository<Transfer, String> {

    @Query("select t from Transfer t where t.fromId = :accountId or t.toId = :accountId order by t.createdAt desc")
    List<Transfer> findByAccount(String accountId, Pageable page);

    List<Transfer> findAllByOrderByCreatedAtDesc(Pageable page);
}
