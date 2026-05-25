-- Migration: 001-add-sale-receivable-subsystem
-- What: Add sale_account_receivable, sale_collection, sale_collection_alert_type,
--       sale_collection_alert, and sale_collection_alert_config tables to pos_schema.
-- Why:  Complete the CxC (Cuentas por Cobrar) subsystem for credit sales. These tables
--       mirror purchase_account_payable, purchase_order_payment, and the payment_alert
--       tables in purchase_schema, but applied to outgoing receivables from customers.
-- Context: Part of CxC subsystem implementation. Requires 001-add-account-receivable
--          migration on general_schema to be applied first.

-- ─────────────────────────────────────────────────────────────────────────────
-- FORWARD MIGRATION
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS pos_schema.sale_account_receivable (
    sale_account_receivable_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_receivable_id      UUID NOT NULL UNIQUE REFERENCES general_schema.account_receivable(account_receivable_id) ON DELETE CASCADE,
    sale_id                    UUID NOT NULL UNIQUE REFERENCES pos_schema.sale(sale_id) ON DELETE CASCADE,
    tax_amount                 NUMERIC(12,3) DEFAULT 0,
    account_receivable_status  INTEGER REFERENCES general_schema.account_receivable_status(status_id),
    created_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS pos_schema.sale_collection (
    sale_collection_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_account_receivable_id UUID NOT NULL REFERENCES pos_schema.sale_account_receivable(sale_account_receivable_id) ON DELETE CASCADE,
    payment_method_id          INTEGER REFERENCES general_schema.payment_method(payment_method_id),
    currency_id                INTEGER NOT NULL DEFAULT 1 REFERENCES general_schema.currency(currency_id),
    amount_paid                NUMERIC(12,3) NOT NULL CHECK (amount_paid > 0),
    payment_date               TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    payment_reference          VARCHAR(100),
    notes                      TEXT,
    created_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_sale_collection_receivable
    ON pos_schema.sale_collection(sale_account_receivable_id);

CREATE INDEX IF NOT EXISTS idx_sale_collection_date
    ON pos_schema.sale_collection(payment_date);

CREATE TABLE IF NOT EXISTS pos_schema.sale_collection_alert_type (
    collection_alert_type_id   SERIAL PRIMARY KEY,
    collection_alert_type_name VARCHAR(50) NOT NULL,
    description                TEXT,
    created_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS pos_schema.sale_collection_alert (
    collection_alert_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_account_receivable_id UUID NOT NULL REFERENCES pos_schema.sale_account_receivable(sale_account_receivable_id) ON DELETE CASCADE,
    collection_alert_type_id   INTEGER NOT NULL REFERENCES pos_schema.sale_collection_alert_type(collection_alert_type_id),
    alert_date                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_resolved                BOOLEAN DEFAULT FALSE,
    created_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS pos_schema.sale_collection_alert_config (
    collection_alert_config_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                    UUID UNIQUE NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    warning_days_before_due      INTEGER DEFAULT 7,
    urgent_days_before_due       INTEGER DEFAULT 3,
    email_notifications_enabled  BOOLEAN DEFAULT TRUE,
    sms_notifications_enabled    BOOLEAN DEFAULT FALSE,
    created_at                   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at                   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- DROP TABLE IF EXISTS pos_schema.sale_collection_alert_config;
-- DROP TABLE IF EXISTS pos_schema.sale_collection_alert;
-- DROP TABLE IF EXISTS pos_schema.sale_collection_alert_type;
-- DROP INDEX IF EXISTS pos_schema.idx_sale_collection_date;
-- DROP INDEX IF EXISTS pos_schema.idx_sale_collection_receivable;
-- DROP TABLE IF EXISTS pos_schema.sale_collection;
-- DROP TABLE IF EXISTS pos_schema.sale_account_receivable;
