CREATE TABLE accounts (
    id            VARCHAR(36)    NOT NULL PRIMARY KEY,
    customer_name VARCHAR(100)   NOT NULL,
    currency      CHAR(3)        NOT NULL,
    balance       DECIMAL(19, 2) NOT NULL DEFAULT 0,
    version       BIGINT         NOT NULL DEFAULT 0,
    created_at    TIMESTAMP(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
) ENGINE = InnoDB;

CREATE TABLE account_legs (
    id          BIGINT         NOT NULL AUTO_INCREMENT PRIMARY KEY,
    account_id  VARCHAR(36)    NOT NULL,
    transfer_id VARCHAR(36)    NOT NULL,
    leg         VARCHAR(16)    NOT NULL,
    amount      DECIMAL(19, 2) NOT NULL,
    created_at  TIMESTAMP(6)   NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    CONSTRAINT uq_transfer_leg UNIQUE (transfer_id, leg),
    CONSTRAINT fk_leg_account FOREIGN KEY (account_id) REFERENCES accounts (id),
    INDEX idx_leg_account (account_id, created_at)
) ENGINE = InnoDB;
