-- ======================================================
-- MIGRATION: general_schema/002-product-category-functions.sql
-- ======================================================
-- Author: David
-- Description: Part 2 - Adds functions and triggers for category hierarchy
--              Includes cycle detection, hierarchy level calculation, and tree queries
-- 
-- Dependencies: 001-product-category-update.sql MUST be executed first
-- Breaking Changes: NO - Only adds functions and triggers
-- Rollback: See bottom of file
-- ======================================================

BEGIN;

SET SEARCH_PATH TO general_schema;

CREATE OR REPLACE FUNCTION general_schema.prevent_category_cycles()
RETURNS TRIGGER AS $$
DECLARE
    v_current_id INTEGER;
    v_visited INTEGER[];
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

COMMENT ON FUNCTION general_schema.prevent_category_cycles() IS 
    'Validates category hierarchy to prevent circular references (both direct and indirect cycles)';

DROP TRIGGER IF EXISTS trigger_prevent_category_cycles 
    ON general_schema.product_category;
CREATE TRIGGER trigger_prevent_category_cycles
    BEFORE INSERT OR UPDATE OF parent_category_id
    ON general_schema.product_category
    FOR EACH ROW
    EXECUTE FUNCTION general_schema.prevent_category_cycles();


CREATE OR REPLACE FUNCTION general_schema.update_category_hierarchy_level()
RETURNS TRIGGER AS $$
DECLARE
    v_parent_level INTEGER;
BEGIN
    IF NEW.parent_category_id IS NULL THEN
        NEW.hierarchy_level := 0;
    ELSE
        SELECT hierarchy_level INTO v_parent_level
        FROM general_schema.product_category
        WHERE product_category_id = NEW.parent_category_id;
        
        IF v_parent_level IS NULL THEN
            RAISE EXCEPTION 'Parent category % not found', NEW.parent_category_id;
        END IF;
        
        NEW.hierarchy_level := v_parent_level + 1;
        
        IF NEW.hierarchy_level > 5 THEN
            RAISE EXCEPTION 'Maximum category depth exceeded (max 5 levels)';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION general_schema.update_category_hierarchy_level() IS 
    'Automatically calculates and updates hierarchy_level based on parent category. Enforces max depth of 5 levels.';

DROP TRIGGER IF EXISTS trigger_update_category_hierarchy 
    ON general_schema.product_category;
CREATE TRIGGER trigger_update_category_hierarchy
    BEFORE INSERT OR UPDATE OF parent_category_id
    ON general_schema.product_category
    FOR EACH ROW
    EXECUTE FUNCTION general_schema.update_category_hierarchy_level();


CREATE OR REPLACE FUNCTION general_schema.get_subcategories(
    p_parent_category_id INTEGER DEFAULT NULL
)
RETURNS TABLE(
    category_id INTEGER,
    category_name VARCHAR(100),
    parent_id INTEGER,
    level INTEGER,
    full_path TEXT,
    product_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE category_tree AS (
        SELECT 
            pc.product_category_id,
            pc.category_name,
            pc.parent_category_id,
            pc.hierarchy_level,
            0 AS depth,
            pc.category_name::TEXT AS path
        FROM general_schema.product_category pc
        WHERE (p_parent_category_id IS NULL AND pc.parent_category_id IS NULL)
           OR (pc.parent_category_id = p_parent_category_id)
        
        UNION ALL
        
        SELECT 
            pc.product_category_id,
            pc.category_name,
            pc.parent_category_id,
            pc.hierarchy_level,
            ct.depth + 1,
            ct.path || ' > ' || pc.category_name
        FROM general_schema.product_category pc
        INNER JOIN category_tree ct 
            ON pc.parent_category_id = ct.product_category_id
    )
    SELECT 
        ct.product_category_id,
        ct.category_name,
        ct.parent_category_id,
        ct.hierarchy_level,
        ct.path,
        COUNT(p.product_id) AS product_count
    FROM category_tree ct
    LEFT JOIN general_schema.product p 
        ON p.product_category_id = ct.product_category_id
    GROUP BY ct.product_category_id, ct.category_name, ct.parent_category_id, 
             ct.hierarchy_level, ct.path, ct.depth
    ORDER BY ct.depth, ct.category_name;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION general_schema.get_subcategories(INTEGER) IS 
    'Returns all subcategories (recursive) for a given parent with full paths and product counts. 
     Pass NULL to get all root categories and their complete trees.';

COMMIT;

-- -----------------
-- ROLLBACK (Run manually if needed)
-- -----------------
/*
BEGIN;

-- Drop triggers first (depend on functions)
DROP TRIGGER IF EXISTS trigger_update_category_hierarchy 
    ON general_schema.product_category;

DROP TRIGGER IF EXISTS trigger_prevent_category_cycles 
    ON general_schema.product_category;

-- Drop functions
DROP FUNCTION IF EXISTS general_schema.update_category_hierarchy_level() CASCADE;
DROP FUNCTION IF EXISTS general_schema.get_subcategories(INTEGER) CASCADE;
DROP FUNCTION IF EXISTS general_schema.prevent_category_cycles() CASCADE;

RAISE NOTICE 'Migration 002-product-category-functions rolled back successfully';

COMMIT;
*/
