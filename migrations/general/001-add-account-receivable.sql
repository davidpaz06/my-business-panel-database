-- Migration: 001-add-account-receivable
-- What: Add account_receivable_status, account_receivable_type, and account_receivable tables
--       to general_schema as the master AR (Cuentas por Cobrar) ledger.
-- Why:  The sales module needs a full AR subsystem mirroring the existing AP subsystem
--       in the purchase module. These tables are the general-schema counterparts to
--       account_payable_status, account_payable_type, and account_payable.
-- Context: Part of CxC subsystem implementation (credit sales tracking).

-- ─────────────────────────────────────────────────────────────────────────────
-- FORWARD MIGRATION
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS general_schema.account_receivable_status (
    status_id   SERIAL PRIMARY KEY,
    status_name VARCHAR(50) NOT NULL,
    description TEXT,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS general_schema.account_receivable_type (
    account_receivable_type_id SERIAL PRIMARY KEY,
    type_name                  VARCHAR(50) UNIQUE NOT NULL,
    description                TEXT,
    created_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS general_schema.account_receivable (
    account_receivable_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_receivable_type_id INT REFERENCES general_schema.account_receivable_type(account_receivable_type_id) ON DELETE SET NULL,
    account_status             INTEGER NOT NULL DEFAULT 1 REFERENCES general_schema.account_receivable_status(status_id),
    tenant_id                  UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    tenant_customer_id         UUID REFERENCES general_schema.tenant_customer(tenant_customer_id) ON DELETE SET NULL,
    has_invoice                BOOLEAN DEFAULT TRUE,
    has_tax                    BOOLEAN DEFAULT FALSE,
    subtotal                   NUMERIC(12,3) NOT NULL CHECK (subtotal >= 0),
    amount_paid                NUMERIC(12,3) DEFAULT 0 CHECK (amount_paid >= 0),
    balance_remaining          NUMERIC(12,3) GENERATED ALWAYS AS (subtotal - amount_paid) STORED,
    is_paid                    BOOLEAN DEFAULT FALSE,
    due_date                   DATE NOT NULL,
    created_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_account_receivable_tenant
    ON general_schema.account_receivable(tenant_id);

CREATE INDEX IF NOT EXISTS idx_account_receivable_status
    ON general_schema.account_receivable(tenant_id, account_status);

CREATE INDEX IF NOT EXISTS idx_account_receivable_due_date
    ON general_schema.account_receivable(tenant_id, due_date);

CREATE INDEX IF NOT EXISTS idx_account_receivable_customer
    ON general_schema.account_receivable(tenant_customer_id)
    WHERE tenant_customer_id IS NOT NULL;


-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- DROP INDEX IF EXISTS general_schema.idx_account_receivable_customer;
-- DROP INDEX IF EXISTS general_schema.idx_account_receivable_due_date;
-- DROP INDEX IF EXISTS general_schema.idx_account_receivable_status;
-- DROP INDEX IF EXISTS general_schema.idx_account_receivable_tenant;
-- DROP TABLE IF EXISTS general_schema.account_receivable;
-- DROP TABLE IF EXISTS general_schema.account_receivable_type;
-- DROP TABLE IF EXISTS general_schema.account_receivable_status;
