-- ======================================================
-- MIGRATION: pos/010-branch-einvoice-sequence.sql
-- ======================================================
-- Author: David
-- Date: 2026-03-12
-- Description: Introduces an atomic per-branch sequence counter for
--   electronic invoice consecutive numbers, eliminating the race
--   condition that could produce duplicate consecutive_number values
--   when two sales are processed concurrently for the same branch.
--
--   The previous approach read MAX(consecutive_number) in a plain
--   SELECT, which allowed two concurrent reads to obtain the same
--   value before either had inserted its new row.
--
--   The new table uses INSERT ... ON CONFLICT DO UPDATE (upsert),
--   which PostgreSQL executes under a row-level lock, guaranteeing
--   each caller receives a distinct, monotonically increasing number.
--
-- Dependencies: 009-invoice-product-tax-linkage.sql
-- Breaking Changes: NO (additive only)
-- Rollback: See bottom of file
-- ======================================================

BEGIN;

CREATE TABLE IF NOT EXISTS pos_schema.branch_einvoice_seq (
    branch_id UUID PRIMARY KEY
        REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
    next_seq  BIGINT NOT NULL DEFAULT 1
);

COMMENT ON TABLE pos_schema.branch_einvoice_seq IS
    'Atomic per-branch counter for electronic invoice consecutive numbers.
     Use INSERT ... ON CONFLICT DO UPDATE to get the next value safely.';

-- Backfill from existing electronic_sale_invoice rows so the counter
-- starts from the highest already-used sequence number + 1.
INSERT INTO pos_schema.branch_einvoice_seq (branch_id, next_seq)
SELECT
    b.branch_id,
    COALESCE(
        MAX(SUBSTRING(esi.consecutive_number FROM 11 FOR 10)::bigint),
        0
    ) + 1
FROM general_schema.branch b
LEFT JOIN pos_schema.sale s          ON s.branch_id = b.branch_id
LEFT JOIN pos_schema.electronic_sale_invoice esi ON esi.sale_id = s.sale_id
GROUP BY b.branch_id
ON CONFLICT (branch_id) DO NOTHING;

COMMIT;

-- ======================================================
-- ROLLBACK (run manually if needed):
-- ======================================================
-- BEGIN;
-- DROP TABLE IF EXISTS pos_schema.branch_einvoice_seq;
-- COMMIT;
