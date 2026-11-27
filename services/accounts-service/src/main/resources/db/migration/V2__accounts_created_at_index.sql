-- The ops console lists the newest accounts first.
CREATE INDEX idx_accounts_created_at ON accounts (created_at);
