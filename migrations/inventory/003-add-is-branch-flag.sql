-- ======================================================
-- MIGRATION: inventory/003-add-is-branch-flag.sql
-- ======================================================
-- Description: Add is_branch flag to warehouse table to distinguish between
--              storage warehouses and branch sales floor
-- 
-- Business Logic:
--   - is_branch = FALSE: Traditional warehouse (bodega)
--   - is_branch = TRUE: Branch sales floor (piso de venta)
--   - Both use same inventory table
--   - Sales reduce inventory from is_branch = TRUE warehouses
-- ======================================================

BEGIN;

ALTER TABLE inventory_schema.warehouse
ADD COLUMN IF NOT EXISTS is_branch BOOLEAN DEFAULT FALSE NOT NULL;

CREATE INDEX IF NOT EXISTS idx_warehouse_is_branch 
    ON inventory_schema.warehouse(is_branch);

CREATE INDEX IF NOT EXISTS idx_warehouse_branch_sales 
    ON inventory_schema.warehouse(branch_id, is_branch)
    WHERE is_branch = TRUE;

CREATE UNIQUE INDEX IF NOT EXISTS uq_warehouse_branch_sales_floor 
    ON inventory_schema.warehouse(branch_id)
    WHERE is_branch = TRUE;

COMMENT ON COLUMN inventory_schema.warehouse.is_branch IS 
    'TRUE = Sales floor, FALSE = Storage warehouse. Only one sales floor allowed per branch.';

COMMIT;

-- -----------------
-- ROLLBACK
-- -----------------
/*
BEGIN;

DROP INDEX IF EXISTS inventory_schema.uq_warehouse_branch_sales_floor;
DROP INDEX IF EXISTS inventory_schema.idx_warehouse_branch_sales;
DROP INDEX IF EXISTS inventory_schema.idx_warehouse_is_branch;

ALTER TABLE inventory_schema.warehouse 
DROP COLUMN IF EXISTS is_branch;

COMMIT;
*/