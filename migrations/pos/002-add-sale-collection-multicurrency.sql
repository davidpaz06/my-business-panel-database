-- Migration: 002-add-sale-collection-multicurrency
-- What:  Add original_amount and exchange_rate columns to pos_schema.sale_collection
--        so that a collection can be registered in a non-base currency while the
--        recalc-friendly amount_paid stays denominated in the base currency (CRC).
-- Why:   Tenants in Costa Rica can receive payments in USD/EUR/GBP/JPY. Recording
--        the original amount + the rate applied at the time of payment preserves
--        the audit trail (real cash received) while keeping receivable arithmetic
--        consistent in CRC for SUM-based recalculations.
-- Context: pos_schema.sale_collection.currency_id is repurposed to represent the
--        currency the customer paid in. amount_paid stays as the CRC-equivalent.

-- ─────────────────────────────────────────────────────────────────────────────
-- FORWARD MIGRATION
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE pos_schema.sale_collection
    ADD COLUMN IF NOT EXISTS original_amount NUMERIC(12,3);

ALTER TABLE pos_schema.sale_collection
    ADD COLUMN IF NOT EXISTS exchange_rate NUMERIC(18,8);

-- Backfill existing rows: treat legacy collections as base-currency payments.
UPDATE pos_schema.sale_collection
   SET original_amount = amount_paid,
       exchange_rate   = 1
 WHERE original_amount IS NULL;

ALTER TABLE pos_schema.sale_collection
    ALTER COLUMN original_amount SET DEFAULT 0,
    ALTER COLUMN exchange_rate   SET DEFAULT 1;

ALTER TABLE pos_schema.sale_collection
    ADD CONSTRAINT chk_sale_collection_original_amount_positive
    CHECK (original_amount IS NULL OR original_amount > 0);

ALTER TABLE pos_schema.sale_collection
    ADD CONSTRAINT chk_sale_collection_exchange_rate_positive
    CHECK (exchange_rate IS NULL OR exchange_rate > 0);


-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- ALTER TABLE pos_schema.sale_collection DROP CONSTRAINT IF EXISTS chk_sale_collection_exchange_rate_positive;
-- ALTER TABLE pos_schema.sale_collection DROP CONSTRAINT IF EXISTS chk_sale_collection_original_amount_positive;
-- ALTER TABLE pos_schema.sale_collection DROP COLUMN IF EXISTS exchange_rate;
-- ALTER TABLE pos_schema.sale_collection DROP COLUMN IF EXISTS original_amount;
