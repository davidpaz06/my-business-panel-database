-- ======================================================
-- MIGRATION: purchase_schema/002-supplier-added-by-tenant.sql
-- ======================================================
-- Author: David
-- Description: Changes `added_by` column in supplier table to reference
--              general_schema.tenant instead of general_schema.branch
-- 
-- Dependencies: purchase_schema.sql, migration 001 must be applied
-- Breaking Changes: NO - Changes FK reference only, data structure unchanged
-- Rollback: See bottom of file
-- ======================================================

BEGIN;

SET SEARCH_PATH TO purchase_schema;

-- 1. Drop existing foreign key constraint
ALTER TABLE purchase_schema.supplier
DROP CONSTRAINT IF EXISTS supplier_added_by_fkey;

-- 2. Add new foreign key constraint referencing tenant
ALTER TABLE purchase_schema.supplier
ADD CONSTRAINT supplier_added_by_tenant_fkey
FOREIGN KEY (added_by) REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE;

-- 3. Recreate index if needed (optional, as query patterns may differ)
DROP INDEX IF EXISTS idx_supplier_added_by;

CREATE INDEX IF NOT EXISTS idx_supplier_added_by_tenant
    ON purchase_schema.supplier(added_by)
    WHERE added_by IS NOT NULL;

COMMIT;

-- ======================================================
-- ROLLBACK (run manually if needed):
-- ======================================================
-- BEGIN;
-- ALTER TABLE purchase_schema.supplier
-- DROP CONSTRAINT IF EXISTS supplier_added_by_tenant_fkey;
-- 
-- ALTER TABLE purchase_schema.supplier
-- ADD CONSTRAINT supplier_added_by_fkey
-- FOREIGN KEY (added_by) REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE;
-- 
-- DROP INDEX IF EXISTS idx_supplier_added_by_tenant;
-- CREATE INDEX IF NOT EXISTS idx_supplier_added_by
--     ON purchase_schema.supplier(added_by)
--     WHERE added_by IS NOT NULL;
-- COMMIT;
