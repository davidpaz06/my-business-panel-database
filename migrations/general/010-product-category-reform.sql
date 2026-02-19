-- ============================================================================
-- MIGRATION: 010-product-category-reform.sql
-- ============================================================================
-- Author: David
-- Date: 2026-02-18
-- Description: Removes the unique constraint from category_name and ensures
--              category_name length is VARCHAR(255) in product_category table.
--
-- Changes:
--   1. Removes the unique constraint on general_schema.product_category.category_name
--   2. Sets general_schema.product_category.category_name to VARCHAR(255)
--
-- Dependencies: None
-- Breaking Changes: NO
-- Rollback: See bottom of file
-- ============================================================================

BEGIN;

SET SEARCH_PATH TO general_schema;

-- ============================================================================
-- STEP 1: Remove unique constraint from category_name in product_category
-- ============================================================================

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.table_constraints
        WHERE table_schema = 'general_schema'
          AND table_name = 'product_category'
          AND constraint_type = 'UNIQUE'
          AND constraint_name = 'product_category_category_name_key'
    ) THEN
        ALTER TABLE general_schema.product_category
            DROP CONSTRAINT product_category_category_name_key;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- STEP 2: Ensure category_name length is 255
-- ============================================================================

ALTER TABLE general_schema.product_category
    ALTER COLUMN category_name TYPE VARCHAR(255);

COMMIT;

-- ============================================================================
-- ROLLBACK (Run manually if needed)
-- ============================================================================
/*
BEGIN;

SET SEARCH_PATH TO general_schema;

ALTER TABLE general_schema.product_category
    ADD CONSTRAINT IF NOT EXISTS product_category_category_name_key UNIQUE (category_name);

COMMIT;
*/
