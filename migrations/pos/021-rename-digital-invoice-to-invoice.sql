-- Migration: 021-rename-digital-invoice-to-invoice
-- What: Rename digital_sale_invoice(_item/_payment) -> invoice(_item/_payment) and
--       repoint every dependent column (return_transaction, score_transaction) to
--       invoice_id. Fast RENAME TO / RENAME COLUMN — no data movement, PK values
--       and sequences are preserved.
-- Why:  Costa Rica -> Venezuela business migration. Requirement 2: with Hacienda
--       electronic invoicing gone (migration 020), the digital invoice becomes
--       the system's only invoice concept, so it is renamed to its plain name.
-- Context: Slice B (invoice consolidation). functions/pos/pos_functions.sql is
--       rewritten in the same deployment (source-of-truth file, not migration-
--       tracked) to match these new names — it cannot lag behind this migration.

-- ─────────────────────────────────────────────────────────────────────────────
-- FORWARD MIGRATION
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE pos_schema.digital_sale_invoice RENAME TO invoice;
ALTER TABLE pos_schema.invoice RENAME COLUMN digital_sale_invoice_id TO invoice_id;

ALTER TABLE pos_schema.digital_sale_invoice_item RENAME TO invoice_item;
ALTER TABLE pos_schema.invoice_item RENAME COLUMN digital_sale_invoice_id TO invoice_id;
ALTER TABLE pos_schema.invoice_item
    RENAME CONSTRAINT digital_sale_invoice_item_product_variant_fkey TO invoice_item_product_variant_fkey;

ALTER TABLE pos_schema.digital_sale_invoice_payment RENAME TO invoice_payment;
ALTER TABLE pos_schema.invoice_payment RENAME COLUMN digital_sale_invoice_id TO invoice_id;

ALTER TABLE pos_schema.return_transaction RENAME COLUMN digital_sale_invoice_id TO invoice_id;
ALTER TABLE pos_schema.return_transaction ALTER COLUMN invoice_id SET NOT NULL;

ALTER TABLE pos_schema.score_transaction RENAME COLUMN digital_sale_invoice_id TO invoice_id;

ALTER INDEX IF EXISTS pos_schema.idx_digital_sale_invoice_sale_id RENAME TO idx_invoice_sale_id;
ALTER INDEX IF EXISTS pos_schema.idx_digital_sale_invoice_cash_register_session RENAME TO idx_invoice_cash_register_session;
ALTER INDEX IF EXISTS pos_schema.idx_digital_invoice_item_invoice RENAME TO idx_invoice_item_invoice;
ALTER INDEX IF EXISTS pos_schema.idx_digital_invoice_item_sale_item RENAME TO idx_invoice_item_sale_item;
ALTER INDEX IF EXISTS pos_schema.idx_digital_invoice_item_variant RENAME TO idx_invoice_item_variant;
ALTER INDEX IF EXISTS pos_schema.idx_digital_invoice_item_tax_rate RENAME TO idx_invoice_item_tax_rate;
ALTER INDEX IF EXISTS pos_schema.idx_return_transaction_digital_sale_invoice_id RENAME TO idx_return_transaction_invoice_id;


-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- ALTER INDEX IF EXISTS pos_schema.idx_return_transaction_invoice_id RENAME TO idx_return_transaction_digital_sale_invoice_id;
-- ALTER INDEX IF EXISTS pos_schema.idx_invoice_item_tax_rate RENAME TO idx_digital_invoice_item_tax_rate;
-- ALTER INDEX IF EXISTS pos_schema.idx_invoice_item_variant RENAME TO idx_digital_invoice_item_variant;
-- ALTER INDEX IF EXISTS pos_schema.idx_invoice_item_sale_item RENAME TO idx_digital_invoice_item_sale_item;
-- ALTER INDEX IF EXISTS pos_schema.idx_invoice_item_invoice RENAME TO idx_digital_invoice_item_invoice;
-- ALTER INDEX IF EXISTS pos_schema.idx_invoice_cash_register_session RENAME TO idx_digital_sale_invoice_cash_register_session;
-- ALTER INDEX IF EXISTS pos_schema.idx_invoice_sale_id RENAME TO idx_digital_sale_invoice_sale_id;
--
-- ALTER TABLE pos_schema.score_transaction RENAME COLUMN invoice_id TO digital_sale_invoice_id;
-- ALTER TABLE pos_schema.return_transaction ALTER COLUMN invoice_id DROP NOT NULL;
-- ALTER TABLE pos_schema.return_transaction RENAME COLUMN invoice_id TO digital_sale_invoice_id;
-- ALTER TABLE pos_schema.invoice_payment RENAME COLUMN invoice_id TO digital_sale_invoice_id;
-- ALTER TABLE pos_schema.invoice_payment RENAME TO digital_sale_invoice_payment;
-- ALTER TABLE pos_schema.invoice_item RENAME CONSTRAINT invoice_item_product_variant_fkey TO digital_sale_invoice_item_product_variant_fkey;
-- ALTER TABLE pos_schema.invoice_item RENAME COLUMN invoice_id TO digital_sale_invoice_id;
-- ALTER TABLE pos_schema.invoice_item RENAME TO digital_sale_invoice_item;
-- ALTER TABLE pos_schema.invoice RENAME COLUMN invoice_id TO digital_sale_invoice_id;
-- ALTER TABLE pos_schema.invoice RENAME TO digital_sale_invoice;
