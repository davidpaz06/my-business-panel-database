-- ======================================================
-- MIGRATION: general_schema/001-product-category-update.sql
-- ======================================================
-- Author: David
-- Description: Part 1 - Adds hierarchical structure to product_category table
--              Adds columns and indexes for parent/child relationships
-- 
-- Dependencies: general_schema.sql must exist
-- Breaking Changes: NO - Adds optional columns, existing data remains valid
-- Related: 002-product-category-functions.sql (must run after this)
-- Rollback: See bottom of file
-- ======================================================

BEGIN;

SET SEARCH_PATH TO general_schema;

ALTER TABLE general_schema.product_category 
ADD COLUMN IF NOT EXISTS parent_category_id INTEGER 
    REFERENCES general_schema.product_category(product_category_id) 
    ON DELETE CASCADE;

ALTER TABLE general_schema.product_category 
ADD COLUMN IF NOT EXISTS hierarchy_level INTEGER DEFAULT 0 
    CHECK (hierarchy_level >= 0);

CREATE INDEX IF NOT EXISTS idx_product_category_parent 
    ON general_schema.product_category(parent_category_id) 
    WHERE parent_category_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_product_category_hierarchy 
    ON general_schema.product_category(parent_category_id, hierarchy_level);

ALTER TABLE general_schema.product_category
ADD CONSTRAINT chk_no_self_reference 
    CHECK (product_category_id != parent_category_id);

COMMENT ON COLUMN general_schema.product_category.parent_category_id IS 
    'Reference to parent category. NULL for root categories.';

COMMENT ON COLUMN general_schema.product_category.hierarchy_level IS 
    'Depth level in the category tree (0-5). Automatically calculated by trigger.';

COMMIT;

-- -----------------
-- ROLLBACK (Run manually if needed)
-- -----------------
/*
BEGIN;

-- Drop indexes
DROP INDEX IF EXISTS general_schema.idx_product_category_hierarchy;
DROP INDEX IF EXISTS general_schema.idx_product_category_parent;

-- Remove constraints
ALTER TABLE general_schema.product_category 
    DROP CONSTRAINT IF EXISTS chk_no_self_reference;

-- Remove columns (in reverse order of creation)
ALTER TABLE general_schema.product_category 
    DROP COLUMN IF EXISTS hierarchy_level;

ALTER TABLE general_schema.product_category 
    DROP COLUMN IF EXISTS parent_category_id CASCADE;

RAISE NOTICE 'Migration 001-product-category-update rolled back successfully';

COMMIT;
*/