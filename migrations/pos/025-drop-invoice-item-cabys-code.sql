-- Migration: 025-drop-invoice-item-cabys-code
-- What: Drop pos_schema.invoice_item.cabys_code (and its FK to
--       general_schema.product). Tax data on the line item (tax_rate_id,
--       tax_rate_percentage, tax_amount) already lives directly on invoice_item
--       and is resolved via product_variant.product_id -> product.tax_rate_id
--       (functions/pos/pos_functions.sql), not via this code.
-- Why:  Costa Rica -> Venezuela business migration. Requirement 3: remove CABYS
--       entirely. This is the last CABYS-shaped column in pos_schema.
-- Context: Slice C (CABYS removal). Must run AFTER migrations/general/024
--       (product's cabys_code is renamed to legacy_cabys_code there — this FK
--       follows the rename automatically) and BEFORE migrations/general/026,
--       which drops product.legacy_cabys_code for good — that drop would fail
--       while this FK still references it.

-- ─────────────────────────────────────────────────────────────────────────────
-- FORWARD MIGRATION
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE pos_schema.invoice_item
    DROP COLUMN IF EXISTS cabys_code;


-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- ALTER TABLE pos_schema.invoice_item
--     ADD COLUMN cabys_code VARCHAR(13)
--         REFERENCES general_schema.product(legacy_cabys_code) ON DELETE SET NULL;
-- (Values are not recoverable — this restores the column shape only.)
