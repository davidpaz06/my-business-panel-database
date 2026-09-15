-- Migration: 026-repoint-product-variant-to-product-id
-- What: Add product_variant.product_id (UUID, FK to product.product_id),
--       backfill it from the existing product_variant.cabys_code -> product
--       link, then drop product_variant.cabys_code entirely. Also drops the
--       transient legacy_cabys_code bridge columns left on product and
--       product_category by migrations/general/023 and 024 — CABYS is now
--       fully removed from the schema.
-- Why:  Costa Rica -> Venezuela business migration. Requirement 3: remove CABYS
--       entirely. product_variant.cabys_code was the only link from a tenant's
--       sellable variant to the (now CABYS-free) product catalog; product_id is
--       its replacement.
-- Context: Slice C (CABYS removal), final step of the product/category/variant
--       PK redesign started in migrations/general/023 and 024. product_variant
--       is partitioned x8 by tenant_id (schemas/general/general_schema.sql) —
--       product itself is not tenant-scoped, so product_id needs no composite
--       partition-key FK, matching the cabys_code FK it replaces. Runs after
--       migrations/pos/025 (drop invoice_item.cabys_code), which must clear its
--       FK on product before this migration drops product.legacy_cabys_code.

-- ─────────────────────────────────────────────────────────────────────────────
-- FORWARD MIGRATION
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Add the new link column.
ALTER TABLE general_schema.product_variant
    ADD COLUMN IF NOT EXISTS product_id UUID;

-- 2. Backfill from the existing cabys_code link (product.cabys_code was renamed
--    to legacy_cabys_code by migrations/general/024, FK follows the rename).
UPDATE general_schema.product_variant pv
   SET product_id = p.product_id
  FROM general_schema.product p
 WHERE pv.cabys_code = p.legacy_cabys_code
   AND pv.cabys_code IS NOT NULL;

-- 3. Drop the old cabys_code column (and its FK/index, dropped implicitly with
--    the column) and add the new FK + index for product_id.
DROP INDEX IF EXISTS general_schema.idx_product_variant_cabys;

ALTER TABLE general_schema.product_variant
    DROP COLUMN IF EXISTS cabys_code;

ALTER TABLE general_schema.product_variant
    ADD CONSTRAINT product_variant_product_id_fkey
    FOREIGN KEY (product_id)
    REFERENCES general_schema.product(product_id)
    ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_product_variant_product
    ON general_schema.product_variant(product_id)
    WHERE product_id IS NOT NULL;

-- 4. CABYS fully removed now — drop the transient bridge columns.
ALTER TABLE general_schema.product
    DROP COLUMN IF EXISTS legacy_cabys_code;

ALTER TABLE general_schema.product_category
    DROP COLUMN IF EXISTS legacy_cabys_code;


-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- Not reversible: the CABYS code values are gone (dropped, not archived) by
-- this point. Restoring product_variant.cabys_code would require re-importing
-- the CABYS catalog and re-deriving the mapping from scratch.
