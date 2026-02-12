-- ============================================================================
-- MIGRATION: 007-product-cabys-catalog
-- ============================================================================
-- Author: David
-- Date: 2026-02-11
-- Description: Transforms the `product` table from a tenant-specific product
--              catalog into a global CABYS (Catálogo de Bienes y Servicios)
--              reference table for Costa Rica.
--
--   Changes:
--   1. Creates `unit_measure` and `commercial_unit_measure` reference tables.
--   2. Drops the old tenant-partitioned `product` table (8 hash partitions).
--   3. Creates a new non-partitioned `product` table with:
--        - cabys_code (VARCHAR 13) as PRIMARY KEY
--        - tax_rate_id FK to tax_rate
--        - unit_measure_id FK to unit_measure
--        - commercial_unit_measure_id FK to commercial_unit_measure
--        - is_exonerated BOOLEAN
--        - product_name with full-text search (GENERATED tsvector)
--   4. Modifies `product_variant` to reference CABYS entries via cabys_code
--      instead of the old composite (tenant_id, product_id) FK.
--   5. Removes the obsolete update_product_tsv trigger (GENERATED column
--      handles tsvector automatically).
--
-- Dependencies: 004-product-variant-model.sql must have been applied
-- Breaking Changes: YES
--   - product PK changed from (tenant_id, product_id) to cabys_code
--   - product_variant.product_id replaced by cabys_code
--   - product table no longer partitioned
--   - Existing product data will be lost (must re-seed with CABYS catalog)
--   - Tenants now add their sellable items only via product_variant
-- Related: general_functions.sql (triggers and get_subcategories updated)
-- Rollback: See bottom of file
-- ============================================================================

BEGIN;

SET SEARCH_PATH TO general_schema;

-- ============================================================================
-- STEP 1: Create unit_measure and commercial_unit_measure tables
-- ============================================================================

CREATE TABLE IF NOT EXISTS general_schema.unit_measure(
    unit_measure_id SERIAL PRIMARY KEY,
    unit_name VARCHAR(50) UNIQUE NOT NULL,
    symbol VARCHAR(10),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE general_schema.unit_measure IS
    'CABYS unit of measure for products (e.g., kg, lt, m, unidad).';

CREATE TABLE IF NOT EXISTS general_schema.commercial_unit_measure(
    commercial_unit_measure_id SERIAL PRIMARY KEY,
    commercial_unit_name VARCHAR(50) UNIQUE NOT NULL,
    symbol VARCHAR(10),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE general_schema.commercial_unit_measure IS
    'CABYS commercial unit of measure for products (e.g., paquete, caja, docena).';

-- ============================================================================
-- STEP 2: Drop dependent FKs and indexes on product_variant
-- ============================================================================

ALTER TABLE general_schema.product_variant
    DROP CONSTRAINT IF EXISTS product_variant_tenant_id_product_id_fkey;

DROP INDEX IF EXISTS general_schema.idx_product_variant_product;

-- ============================================================================
-- STEP 3: Drop old product table triggers, indexes, partitions, and table
-- ============================================================================

-- Drop triggers
DROP TRIGGER IF EXISTS update_product_tsv ON general_schema.product;
DROP TRIGGER IF EXISTS update_product_timestamp ON general_schema.product;

-- Drop indexes
DROP INDEX IF EXISTS general_schema.idx_product_tenant_sku;
DROP INDEX IF EXISTS general_schema.idx_product_tenant_btree;
DROP INDEX IF EXISTS general_schema.idx_product_name_fts;

-- Drop product partitions and table
DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 0..7 LOOP
        EXECUTE format('DROP TABLE IF EXISTS general_schema.product_p%s;', i);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

DROP TABLE IF EXISTS general_schema.product CASCADE;

-- ============================================================================
-- STEP 4: Create new product table (CABYS catalog)
-- ============================================================================

CREATE TABLE IF NOT EXISTS general_schema.product(
    cabys_code VARCHAR(13) PRIMARY KEY,
    product_name VARCHAR(255) NOT NULL,
    product_name_tsv tsvector GENERATED ALWAYS AS (to_tsvector('spanish', product_name)) STORED,
    product_category_id INT REFERENCES general_schema.product_category(product_category_id) ON DELETE SET NULL,
    tax_rate_id INT REFERENCES general_schema.tax_rate(tax_rate_id) ON DELETE SET NULL,
    unit_measure_id INT REFERENCES general_schema.unit_measure(unit_measure_id) ON DELETE SET NULL,
    commercial_unit_measure_id INT REFERENCES general_schema.commercial_unit_measure(commercial_unit_measure_id) ON DELETE SET NULL,
    is_exonerated BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_product_name_fts
    ON general_schema.product USING gin(product_name_tsv);

CREATE INDEX IF NOT EXISTS idx_product_category
    ON general_schema.product(product_category_id)
    WHERE product_category_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_product_tax_rate
    ON general_schema.product(tax_rate_id)
    WHERE tax_rate_id IS NOT NULL;

COMMENT ON TABLE general_schema.product IS
    'Global CABYS (Catálogo de Bienes y Servicios) catalog for Costa Rica.
     This is a reference table, not tenant-specific. Tenants create their
     sellable items via product_variant linked to CABYS entries.';

COMMENT ON COLUMN general_schema.product.cabys_code IS
    'CABYS 13-digit code. Unique identifier for each product/service in the
     Costa Rica tax catalog.';

COMMENT ON COLUMN general_schema.product.product_name IS
    'Official CABYS product/service description.';

COMMENT ON COLUMN general_schema.product.is_exonerated IS
    'Indicates whether the product is tax-exonerated.';

-- ============================================================================
-- STEP 5: Update product_variant to use cabys_code
-- ============================================================================

-- Remove old product_id column
ALTER TABLE general_schema.product_variant
    DROP COLUMN IF EXISTS product_id;

-- Add cabys_code reference
ALTER TABLE general_schema.product_variant
    ADD COLUMN IF NOT EXISTS cabys_code VARCHAR(13)
    REFERENCES general_schema.product(cabys_code) ON DELETE SET NULL;

-- Index for CABYS lookups on variants
CREATE INDEX IF NOT EXISTS idx_product_variant_cabys
    ON general_schema.product_variant(cabys_code);

-- ============================================================================
-- STEP 6: Recreate triggers on product
-- ============================================================================

-- product_name_tsv is GENERATED ALWAYS — no tsv trigger needed.
-- Only the timestamp trigger is required.

DROP TRIGGER IF EXISTS update_product_timestamp ON general_schema.product;
CREATE TRIGGER update_product_timestamp
    BEFORE UPDATE ON general_schema.product
    FOR EACH ROW
    EXECUTE FUNCTION general_schema.update_timestamp();

-- Timestamp triggers for new measurement tables
DROP TRIGGER IF EXISTS update_unit_measure_timestamp ON general_schema.unit_measure;
CREATE TRIGGER update_unit_measure_timestamp
    BEFORE UPDATE ON general_schema.unit_measure
    FOR EACH ROW
    EXECUTE FUNCTION general_schema.update_timestamp();

DROP TRIGGER IF EXISTS update_commercial_unit_measure_timestamp ON general_schema.commercial_unit_measure;
CREATE TRIGGER update_commercial_unit_measure_timestamp
    BEFORE UPDATE ON general_schema.commercial_unit_measure
    FOR EACH ROW
    EXECUTE FUNCTION general_schema.update_timestamp();

COMMIT;

-- ============================================================================
-- ROLLBACK (Run manually if needed)
-- ============================================================================
/*
BEGIN;

SET SEARCH_PATH TO general_schema;

-- Drop triggers on new tables
DROP TRIGGER IF EXISTS update_product_timestamp ON general_schema.product;
DROP TRIGGER IF EXISTS update_unit_measure_timestamp ON general_schema.unit_measure;
DROP TRIGGER IF EXISTS update_commercial_unit_measure_timestamp ON general_schema.commercial_unit_measure;

-- Drop new index on product_variant
DROP INDEX IF EXISTS general_schema.idx_product_variant_cabys;

-- Remove cabys_code from product_variant
ALTER TABLE general_schema.product_variant
    DROP COLUMN IF EXISTS cabys_code;

-- Re-add product_id to product_variant
ALTER TABLE general_schema.product_variant
    ADD COLUMN IF NOT EXISTS product_id uuid NOT NULL DEFAULT gen_random_uuid();

-- Drop new product table
DROP INDEX IF EXISTS general_schema.idx_product_name_fts;
DROP INDEX IF EXISTS general_schema.idx_product_category;
DROP INDEX IF EXISTS general_schema.idx_product_tax_rate;
DROP TABLE IF EXISTS general_schema.product CASCADE;

-- Recreate old product table with partitions
CREATE TABLE IF NOT EXISTS general_schema.product(
    tenant_id uuid NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    product_id uuid NOT NULL DEFAULT gen_random_uuid(),
    sku VARCHAR(50) NOT NULL,
    product_name VARCHAR(100) NOT NULL,
    product_name_tsv tsvector GENERATED ALWAYS AS (to_tsvector('spanish', product_name)) STORED,
    product_description text,
    product_category_id INT REFERENCES general_schema.product_category(product_category_id) ON DELETE SET NULL,
    unit_price numeric(10,2) NOT NULL CHECK (unit_price >= 0),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (tenant_id, product_id)
) PARTITION BY HASH (tenant_id);

DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 0..7 LOOP
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS general_schema.product_p%s
             PARTITION OF general_schema.product
             FOR VALUES WITH (MODULUS 8, REMAINDER %s);',
            i, i
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Recreate old indexes
CREATE UNIQUE INDEX IF NOT EXISTS idx_product_tenant_sku
    ON general_schema.product(tenant_id, sku);
CREATE INDEX IF NOT EXISTS idx_product_tenant_btree
    ON general_schema.product(tenant_id);
CREATE INDEX IF NOT EXISTS idx_product_name_fts
    ON general_schema.product USING gin(product_name_tsv);

-- Recreate old FK on product_variant
ALTER TABLE general_schema.product_variant
    ADD CONSTRAINT product_variant_tenant_id_product_id_fkey
    FOREIGN KEY (tenant_id, product_id)
    REFERENCES general_schema.product(tenant_id, product_id)
    ON DELETE CASCADE;

-- Recreate old index on product_variant
CREATE INDEX IF NOT EXISTS idx_product_variant_product
    ON general_schema.product_variant(tenant_id, product_id);

-- Recreate triggers
CREATE TRIGGER update_product_tsv
    BEFORE INSERT OR UPDATE ON general_schema.product
    FOR EACH ROW
    EXECUTE FUNCTION general_schema.update_product_tsv();

CREATE TRIGGER update_product_timestamp
    BEFORE UPDATE ON general_schema.product
    FOR EACH ROW
    EXECUTE FUNCTION general_schema.update_timestamp();

-- Drop measurement tables
DROP TABLE IF EXISTS general_schema.commercial_unit_measure;
DROP TABLE IF EXISTS general_schema.unit_measure;

RAISE NOTICE 'Migration 007-product-cabys-catalog rolled back successfully';

COMMIT;
*/
