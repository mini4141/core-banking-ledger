CREATE TABLE transfers (
    id              VARCHAR(36)    NOT NULL PRIMARY KEY,
    idempotency_key VARCHAR(100)   NOT NULL,
    from_id         VARCHAR(36)    NOT NULL,
    to_id           VARCHAR(36)    NOT NULL,
    amount          DECIMAL(19, 2) NOT NULL,
    status          VARCHAR(20)    NOT NULL,
    created_at      TIMESTAMP(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT uq_transfer_idem UNIQUE (idempotency_key),
    INDEX idx_transfers_from (from_id, created_at),
    INDEX idx_transfers_to (to_id, created_at)
) ENGINE = InnoDB;
