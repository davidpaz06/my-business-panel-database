-- ============================================================================
-- MIGRATION: Drop product_id from Inventory Schema
-- Date: 2026-02-04
-- Description: Removes product_id columns from inventory-related tables.
--              Now only product_variant_id is used as it maps directly to
--              the new product variant model. This reduces redundancy and
--              simplifies the schema.
-- ============================================================================

BEGIN;

SET SEARCH_PATH TO inventory_schema;

-- ============================================================================
-- 1. Inventory Table
-- ============================================================================
ALTER TABLE inventory_schema.inventory
DROP COLUMN IF EXISTS product_id CASCADE;

-- ============================================================================
-- 2. Inventory Log Table
-- ============================================================================
ALTER TABLE inventory_schema.inventory_log
DROP COLUMN IF EXISTS product_id CASCADE;

-- ============================================================================
-- 3. Inventory Transfer Product Table
-- ============================================================================
ALTER TABLE inventory_schema.inventory_transfer_product
DROP COLUMN IF EXISTS product_id CASCADE;

-- ============================================================================
-- 4. Discrepancy Count Table
-- ============================================================================
ALTER TABLE inventory_schema.discrepancy_count
DROP COLUMN IF EXISTS product_id CASCADE;

-- ============================================================================
-- Summary
-- ============================================================================
-- All inventory-related tables now use only product_variant_id.
-- This aligns with the new product variant model where:
-- - product (base product) → product_variant (sellable SKU) → inventory
--
-- Removed columns:
--   - inventory.product_id
--   - inventory_log.product_id
--   - inventory_transfer_product.product_id
--   - discrepancy_count.product_id

COMMIT;
