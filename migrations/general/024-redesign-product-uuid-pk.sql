-- Migration: 024-redesign-product-uuid-pk
-- What: Replace product's CABYS-code (13-digit) primary key with a surrogate
--       UUID primary key. product_category_id is repointed from the old
--       VARCHAR(13) CABYS category code to product_category's new UUID key
--       (migrations/general/023) via the transient legacy_cabys_code bridge
--       column. product.cabys_code itself is renamed to legacy_cabys_code here
--       too (kept temporarily so migrations/general/025 can repoint
--       product_variant before dropping it for good).
-- Why:  Costa Rica -> Venezuela business migration. Requirement 3: remove CABYS
--       entirely. product.cabys_code was the product's identity; there is no
--       Venezuela tariff/classification catalog available yet, so product
--       identity becomes a plain surrogate key. product.tax_rate_id (already a
--       direct column) remains the IVA-assignment mechanism — no CABYS-derived
--       lookup replaces it.
-- Context: Slice C (CABYS removal). Must run after migrations/general/023
--       (product_category UUID PK) and before migrations/pos/025
--       (invoice_item.cabys_code drop) and migrations/general/026
--       (product_variant repoint + final legacy_cabys_code cleanup on both
--       tables).

-- ─────────────────────────────────────────────────────────────────────────────
-- FORWARD MIGRATION
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Add the new surrogate key column, backfilled with fresh UUIDs.
ALTER TABLE general_schema.product
    ADD COLUMN IF NOT EXISTS new_product_id UUID DEFAULT gen_random_uuid();

UPDATE general_schema.product
   SET new_product_id = gen_random_uuid()
 WHERE new_product_id IS NULL;

ALTER TABLE general_schema.product
    ALTER COLUMN new_product_id SET NOT NULL;

-- 2. Repoint product_category_id from the old VARCHAR(13) CABYS category code to
--    product_category's new UUID key, via the legacy_cabys_code bridge column
--    that migrations/general/023 preserved.
ALTER TABLE general_schema.product
    ADD COLUMN IF NOT EXISTS new_product_category_id UUID;

UPDATE general_schema.product p
   SET new_product_category_id = pc.product_category_id
  FROM general_schema.product_category pc
 WHERE p.product_category_id = pc.legacy_cabys_code
   AND p.product_category_id IS NOT NULL;

-- 3. Drop the old PK and FKs pointing at it, rename cabys_code out of the way
--    (kept temporarily for migrations/general/025 to repoint product_variant),
--    promote the new columns.
ALTER TABLE general_schema.product
    DROP CONSTRAINT IF EXISTS product_pkey;

DROP INDEX IF EXISTS general_schema.idx_product_category;

ALTER TABLE general_schema.product
    DROP CONSTRAINT IF EXISTS product_product_category_id_fkey;

ALTER TABLE general_schema.product
    DROP COLUMN product_category_id;

ALTER TABLE general_schema.product
    RENAME COLUMN cabys_code TO legacy_cabys_code;

ALTER TABLE general_schema.product
    RENAME COLUMN new_product_id TO product_id;

ALTER TABLE general_schema.product
    RENAME COLUMN new_product_category_id TO product_category_id;

ALTER TABLE general_schema.product
    ADD CONSTRAINT product_pkey PRIMARY KEY (product_id);

ALTER TABLE general_schema.product
    ADD CONSTRAINT product_product_category_id_fkey
    FOREIGN KEY (product_category_id)
    REFERENCES general_schema.product_category(product_category_id)
    ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_product_category
    ON general_schema.product(product_category_id)
    WHERE product_category_id IS NOT NULL;

COMMENT ON COLUMN general_schema.product.legacy_cabys_code IS
    'Transient bridge column from the CR->VE CABYS-removal migration (general/023-025). Dropped once product_variant is repointed (general/025). Not a live identifier.';


-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- Not reversible as live identifiers once migrations/general/025 drops
-- legacy_cabys_code on both product and product_category.
