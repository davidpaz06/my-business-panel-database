-- Migration: 023-redesign-product-category-uuid-pk
-- What: Replace product_category's CABYS-hierarchy VARCHAR(13) primary key with a
--       surrogate UUID primary key. The self-referencing parent_category_id column
--       is repointed to the new UUID id, preserving the existing hierarchy. The
--       old CABYS code is kept, renamed to legacy_cabys_code (nullable, no longer
--       the key), so migrations/general/024 (product) can still join on it to
--       repoint product.product_category_id before it is dropped for good in
--       migrations/general/026.
-- Why:  Costa Rica -> Venezuela business migration. Requirement 3: remove CABYS
--       (Costa Rica's national product tax-code catalog) entirely. product_category
--       was structurally defined as the CABYS hierarchy (13-digit codes as PKs) —
--       there is no Venezuela equivalent catalog, so it becomes a plain flat/
--       optionally-nested category table with a generic surrogate key.
-- Context: Slice C (CABYS removal) of the general-module CR->VE migration.
--       Sequenced before migrations/general/024 (product) and 026 (product_variant
--       repoint + final legacy_cabys_code cleanup), which depend on this table's
--       new key. Also drops product.product_category_id_fkey here (not in 024)
--       since it blocks this file's own PK drop below.

-- ─────────────────────────────────────────────────────────────────────────────
-- FORWARD MIGRATION
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Add the new surrogate key column, backfilled with fresh UUIDs.
ALTER TABLE general_schema.product_category
    ADD COLUMN IF NOT EXISTS new_product_category_id UUID DEFAULT gen_random_uuid();

UPDATE general_schema.product_category
   SET new_product_category_id = gen_random_uuid()
 WHERE new_product_category_id IS NULL;

ALTER TABLE general_schema.product_category
    ALTER COLUMN new_product_category_id SET NOT NULL;

-- 2. Add a new parent column pointing at the new UUID key, backfilled by joining
--    the old CABYS-code parent link to the new UUID of that same row.
ALTER TABLE general_schema.product_category
    ADD COLUMN IF NOT EXISTS new_parent_category_id UUID;

UPDATE general_schema.product_category child
   SET new_parent_category_id = parent.new_product_category_id
  FROM general_schema.product_category parent
 WHERE child.parent_category_id = parent.product_category_id
   AND child.parent_category_id IS NOT NULL;

-- 3. Drop the old PK/FK/CHECK, rename the old code column out of the way
--    (kept temporarily as a join key for migrations/general/024), and promote
--    the new columns.
ALTER TABLE general_schema.product_category
    DROP CONSTRAINT IF EXISTS chk_no_self_reference;

ALTER TABLE general_schema.product_category
    DROP CONSTRAINT IF EXISTS product_category_parent_category_id_fkey;

DROP INDEX IF EXISTS general_schema.idx_product_category_parent;
DROP INDEX IF EXISTS general_schema.idx_product_category_hierarchy;

-- product.product_category_id still FKs into product_category_pkey at this
-- point (migrations/general/024 doesn't repoint it until after this file
-- runs) — drop that dependent FK first or the PK drop below fails with
-- "cannot drop constraint ... because other objects depend on it".
ALTER TABLE general_schema.product
    DROP CONSTRAINT IF EXISTS product_product_category_id_fkey;

ALTER TABLE general_schema.product_category
    DROP CONSTRAINT IF EXISTS product_category_pkey;

-- trigger_prevent_category_cycles and trigger_update_category_hierarchy are
-- both "BEFORE ... UPDATE OF parent_category_id" triggers (functions/general/
-- general_functions.sql) — that column-specific USE OF clause makes them
-- depend on the column itself, so dropping it fails with "cannot drop column
-- ... because other objects depend on it" unless these are dropped first.
-- prevent_category_cycles() also declares VARCHAR(13) locals sized for the
-- old CABYS code; recreated below with UUID locals to match the new column.
DROP TRIGGER IF EXISTS trigger_prevent_category_cycles ON general_schema.product_category;
DROP TRIGGER IF EXISTS trigger_update_category_hierarchy ON general_schema.product_category;

ALTER TABLE general_schema.product_category
    DROP COLUMN parent_category_id;

ALTER TABLE general_schema.product_category
    RENAME COLUMN product_category_id TO legacy_cabys_code;

ALTER TABLE general_schema.product_category
    RENAME COLUMN new_product_category_id TO product_category_id;

ALTER TABLE general_schema.product_category
    RENAME COLUMN new_parent_category_id TO parent_category_id;

ALTER TABLE general_schema.product_category
    ADD CONSTRAINT product_category_pkey PRIMARY KEY (product_category_id);

ALTER TABLE general_schema.product_category
    ADD CONSTRAINT product_category_parent_category_id_fkey
    FOREIGN KEY (parent_category_id)
    REFERENCES general_schema.product_category(product_category_id)
    ON DELETE CASCADE;

ALTER TABLE general_schema.product_category
    ADD CONSTRAINT chk_no_self_reference
    CHECK (product_category_id != parent_category_id);

CREATE INDEX IF NOT EXISTS idx_product_category_parent
    ON general_schema.product_category(parent_category_id)
    WHERE parent_category_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_product_category_hierarchy
    ON general_schema.product_category(parent_category_id, hierarchy_level);

COMMENT ON COLUMN general_schema.product_category.legacy_cabys_code IS
    'Transient bridge column from the CR->VE CABYS-removal migration (general/023-025). Dropped once product.product_category_id is repointed (general/025). Not a live identifier.';

-- Recreate the two triggers dropped above, now with parent_category_id/
-- product_category_id as UUID (prevent_category_cycles locals updated from
-- VARCHAR(13) to UUID to match; see functions/general/general_functions.sql,
-- source of truth, updated the same way).
CREATE OR REPLACE FUNCTION general_schema.prevent_category_cycles()
RETURNS TRIGGER AS $$
DECLARE
    v_current_id UUID;
    v_visited UUID[];
    v_max_iterations INTEGER := 10;
    v_iteration INTEGER := 0;
BEGIN
    IF NEW.parent_category_id IS NULL THEN
        RETURN NEW;
    END IF;

    v_current_id := NEW.parent_category_id;
    v_visited := ARRAY[NEW.product_category_id];

    WHILE v_current_id IS NOT NULL AND v_iteration < v_max_iterations LOOP
        IF v_current_id = NEW.product_category_id THEN
            RAISE EXCEPTION 'Cycle detected: category % cannot be its own ancestor',
                NEW.product_category_id;
        END IF;

        IF v_current_id = ANY(v_visited) THEN
            RAISE EXCEPTION 'Cycle detected in category hierarchy';
        END IF;

        v_visited := array_append(v_visited, v_current_id);

        SELECT parent_category_id INTO v_current_id
        FROM general_schema.product_category
        WHERE product_category_id = v_current_id;

        v_iteration := v_iteration + 1;
    END LOOP;

    IF v_iteration >= v_max_iterations THEN
        RAISE EXCEPTION 'Category hierarchy too deep or contains cycle';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_prevent_category_cycles
    BEFORE INSERT OR UPDATE OF parent_category_id
    ON general_schema.product_category
    FOR EACH ROW
    EXECUTE FUNCTION general_schema.prevent_category_cycles();

CREATE TRIGGER trigger_update_category_hierarchy
    BEFORE INSERT OR UPDATE OF parent_category_id
    ON general_schema.product_category
    FOR EACH ROW
    EXECUTE FUNCTION general_schema.update_category_hierarchy_level();


-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- Not reversible without the original CABYS codes as live identifiers (the old
-- PK/FK structure is gone; legacy_cabys_code is transient and removed by
-- migrations/general/025).
