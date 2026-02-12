-- =====================================
-- SCRIPT DE PRUEBA: CABYS CATALOG & PRODUCT VARIANTS (idempotent)
-- =====================================
-- Objetivo:
--  - Demostrar inserción y borrado de entradas CABYS y variantes de producto
--  - La tabla product es el catálogo global CABYS
--  - Los tenants crean sus productos vendibles en product_variant
--  - Idempotencia: al ejecutar varias veces el script, el estado final es el mismo
-- Estructura:
--  0) Limpieza (idempotente)
--  1) Preparación (tenant, categoría, entradas CABYS)
--  2) Insertar variantes individuales (single inserts)
--  3) Insertar variantes en lote (batch inserts)
--  4) Borrar variante individual
--  5) Borrar lote de variantes
--  6) Verificaciones (constraints / conteos / CABYS)
--  7) Resumen final
-- =====================================

SET LOCAL search_path = general_schema, pos_schema;

-- ========================================
-- SECCIÓN 0: Limpieza inicial (idempotente)
-- ========================================
DO $$
DECLARE
    v_tenant_id uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧹 SECCIÓN 0: Limpieza inicial (idempotente)';
    RAISE NOTICE '========================================';

    SELECT tenant_id INTO v_tenant_id FROM general_schema.tenant WHERE tenant_name = 'Product Test Shop' LIMIT 1;

    IF v_tenant_id IS NOT NULL THEN
        DELETE FROM general_schema.attribute_assignation WHERE tenant_id = v_tenant_id;
        DELETE FROM general_schema.product_variant WHERE tenant_id = v_tenant_id;
        RAISE NOTICE '   Removed previous product variants for tenant %', v_tenant_id;
    ELSE
        RAISE NOTICE '   No previous test tenant found, nothing to clean';
    END IF;

    -- Limpiar entradas CABYS de prueba
    DELETE FROM general_schema.product WHERE cabys_code LIKE 'TEST%';
    RAISE NOTICE '   Removed test CABYS entries';

    -- Resincronizar secuencia de product_category
    PERFORM setval('general_schema.product_category_product_category_id_seq', 
        coalesce((SELECT max(product_category_id) FROM general_schema.product_category), 0) + 1, 
        false);
    RAISE NOTICE '   ✅ product_category sequence synchronized';

    RAISE NOTICE '✅ SECCIÓN 0 COMPLETADA';
    RAISE NOTICE '========================================';
END $$;


-- ========================================
-- SECCIÓN 1: Preparación (tenant, categoría, entradas CABYS)
-- ========================================
DO $$
DECLARE
    v_tenant_id uuid;
    v_category_id int;
    v_cabys text;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🏪 SECCIÓN 1: Preparación (tenant, category & CABYS catalog)';
    RAISE NOTICE '========================================';

    -- Tenant
    SELECT tenant_id INTO v_tenant_id FROM general_schema.tenant WHERE tenant_name = 'Product Test Shop' LIMIT 1;
    IF v_tenant_id IS NULL THEN
        INSERT INTO general_schema.tenant (tenant_name, region_id, contact_email, is_subscribed)
        VALUES ('Product Test Shop', (SELECT region_id FROM general_schema.region LIMIT 1), 'products@testshop.local', false)
        RETURNING tenant_id INTO v_tenant_id;
        RAISE NOTICE '   Tenant created: %', v_tenant_id;
    ELSE
        RAISE NOTICE '   Tenant exists: %', v_tenant_id;
    END IF;

    -- Categoría
    SELECT product_category_id INTO v_category_id FROM general_schema.product_category WHERE category_name = 'Test Category' LIMIT 1;
    IF v_category_id IS NULL THEN
        INSERT INTO general_schema.product_category (category_name) VALUES ('Test Category') RETURNING product_category_id INTO v_category_id;
        RAISE NOTICE '   Product category created: %', v_category_id;
    ELSE
        RAISE NOTICE '   Product category exists: %', v_category_id;
    END IF;

    -- Entradas CABYS de prueba
    INSERT INTO general_schema.product (cabys_code, product_name, product_category_id)
    VALUES 
        ('TEST000000001', 'Producto de prueba CABYS uno', v_category_id),
        ('TEST000000002', 'Producto de prueba CABYS dos', v_category_id)
    ON CONFLICT (cabys_code) DO NOTHING;
    RAISE NOTICE '   ✅ CABYS catalog entries created';

    RAISE NOTICE '✅ SECCIÓN 1 COMPLETADA';
    RAISE NOTICE '========================================';
END $$;


-- ========================================
-- SECCIÓN 2: Insertar variantes individuales (single inserts)
-- ========================================
DO $$
DECLARE
    v_tenant_id uuid := (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Product Test Shop' LIMIT 1);
    v_vid uuid;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '➕ SECCIÓN 2: Insertar variantes individuales';
    RAISE NOTICE '========================================';

    -- Single insert 1
    INSERT INTO general_schema.product_variant (tenant_id, sku, variant_name, unit_price, cabys_code, is_active)
    VALUES (v_tenant_id, 'SINGLE-001', 'Variante Individual Uno', 9.99, 'TEST000000001', true)
    ON CONFLICT (tenant_id, sku) DO NOTHING
    RETURNING product_variant_id INTO v_vid;
    IF v_vid IS NOT NULL THEN
        RAISE NOTICE '   Inserted SINGLE-001 -> %', v_vid;
    ELSE
        RAISE NOTICE '   SINGLE-001 already exists';
    END IF;

    -- Single insert 2
    INSERT INTO general_schema.product_variant (tenant_id, sku, variant_name, unit_price, cabys_code, is_active)
    VALUES (v_tenant_id, 'SINGLE-002', 'Variante Individual Dos', 19.50, 'TEST000000002', true)
    ON CONFLICT (tenant_id, sku) DO NOTHING
    RETURNING product_variant_id INTO v_vid;
    IF v_vid IS NOT NULL THEN
        RAISE NOTICE '   Inserted SINGLE-002 -> %', v_vid;
    ELSE
        RAISE NOTICE '   SINGLE-002 already exists';
    END IF;

    RAISE NOTICE '✅ SECCIÓN 2 COMPLETADA';
END $$;


-- ========================================
-- SECCIÓN 3: Insertar variantes en lote (batch inserts)
-- ========================================
DO $$
DECLARE
    v_tenant_id uuid := (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Product Test Shop' LIMIT 1);
    i int;
    v_sku text;
    v_vid uuid;
    v_count_inserted int := 0;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📦 SECCIÓN 3: Insertar variantes en LOTE (20 items)';
    RAISE NOTICE '========================================';

    FOR i IN 1..20 LOOP
        v_sku := lpad(i::text, 3, '0');
        INSERT INTO general_schema.product_variant (tenant_id, sku, variant_name, unit_price, cabys_code, is_active)
        VALUES (v_tenant_id, 'BATCH-' || v_sku, 'Batch Variant ' || v_sku, round((5 + random()*45)::numeric, 2), 'TEST000000001', true)
        ON CONFLICT (tenant_id, sku) DO NOTHING
        RETURNING product_variant_id INTO v_vid;
        
        IF v_vid IS NOT NULL THEN
            v_count_inserted := v_count_inserted + 1;
        END IF;
    END LOOP;

    RAISE NOTICE '   Inserted batch variants this run: %', v_count_inserted;
    RAISE NOTICE '✅ SECCIÓN 3 COMPLETADA';
END $$;


-- ========================================
-- SECCIÓN 4: Borrar variante individual
-- ========================================
DO $$
DECLARE
    v_tenant_id uuid := (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Product Test Shop' LIMIT 1);
    v_deleted int;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '➖ SECCIÓN 4: Borrar variante individual (SINGLE-002)';
    RAISE NOTICE '========================================';

    DELETE FROM general_schema.product_variant WHERE tenant_id = v_tenant_id AND sku = 'SINGLE-002';
    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    IF v_deleted = 1 THEN
        RAISE NOTICE '   SINGLE-002 deleted';
    ELSE
        RAISE NOTICE '   SINGLE-002 not found (already deleted)';
    END IF;

    RAISE NOTICE '✅ SECCIÓN 4 COMPLETADA';
END $$;


-- ========================================
-- SECCIÓN 5: Borrar lote de variantes (batch delete)
-- ========================================
DO $$
DECLARE
    v_tenant_id uuid := (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Product Test Shop' LIMIT 1);
    v_deleted int;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧺 SECCIÓN 5: Borrar lote de variantes (sku LIKE ''BATCH-%%'')';
    RAISE NOTICE '========================================';

    DELETE FROM general_schema.product_variant WHERE tenant_id = v_tenant_id AND sku LIKE 'BATCH-%';
    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    RAISE NOTICE '   Batch variants deleted this run: %', v_deleted;

    RAISE NOTICE '✅ SECCIÓN 5 COMPLETADA';
END $$;


-- ========================================
-- SECCIÓN 6: Verificaciones (constraints / conteos / CABYS)
-- ========================================
DO $$
DECLARE
    v_tenant_id uuid := (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Product Test Shop' LIMIT 1);
    v_count_total int;
    v_count_single int;
    v_cabys_count int;
    v_tableoid record;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🔍 SECCIÓN 6: Verificaciones finales';
    RAISE NOTICE '========================================';

    SELECT count(*) INTO v_count_total FROM general_schema.product_variant WHERE tenant_id = v_tenant_id;
    SELECT count(*) INTO v_count_single FROM general_schema.product_variant WHERE tenant_id = v_tenant_id AND sku = 'SINGLE-001';
    SELECT count(*) INTO v_cabys_count FROM general_schema.product WHERE cabys_code LIKE 'TEST%';

    RAISE NOTICE '   Variants remaining for tenant %: %', v_tenant_id, v_count_total;
    RAISE NOTICE '   SINGLE-001 exists: %', CASE WHEN v_count_single > 0 THEN 'yes' ELSE 'no' END;
    RAISE NOTICE '   Test CABYS entries: %', v_cabys_count;

    -- Verificar partición de variante
    IF v_count_total > 0 THEN
        FOR v_tableoid IN
            SELECT tableoid::regclass AS partition_name FROM general_schema.product_variant WHERE tenant_id = v_tenant_id LIMIT 1
        LOOP
            RAISE NOTICE '   Sample variant partition: %', v_tableoid.partition_name;
        END LOOP;
    END IF;

    -- Verificar full-text search en catálogo CABYS
    IF EXISTS (SELECT 1 FROM general_schema.product WHERE product_name_tsv @@ to_tsquery('spanish', 'prueba')) THEN
        RAISE NOTICE '   ✅ Full-text search on CABYS catalog works';
    END IF;

    -- Assertions
    IF v_count_single = 0 THEN
        RAISE EXCEPTION 'Expected SINGLE-001 to exist after tests but it is missing';
    END IF;
    IF v_cabys_count < 2 THEN
        RAISE EXCEPTION 'Expected at least 2 CABYS entries but found %', v_cabys_count;
    END IF;

    RAISE NOTICE '✅ SECCIÓN 6 COMPLETADA - Constraints & counts ok';
END $$;


-- ========================================
-- SECCIÓN 7: Resumen final
-- ========================================
DO $$
DECLARE
    v_tenant_id uuid := (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Product Test Shop' LIMIT 1);
    v_variant_count int;
    v_cabys_count int;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📊 SECCIÓN 7: RESUMEN FINAL';
    RAISE NOTICE '========================================';

    SELECT count(*) INTO v_variant_count FROM general_schema.product_variant WHERE tenant_id = v_tenant_id;
    SELECT count(*) INTO v_cabys_count FROM general_schema.product WHERE cabys_code LIKE 'TEST%';

    RAISE NOTICE '   Tenant: %', v_tenant_id;
    RAISE NOTICE '   Final variant count for tenant: %', v_variant_count;
    RAISE NOTICE '   CABYS catalog test entries: %', v_cabys_count;
    RAISE NOTICE '';
    RAISE NOTICE '✅ TEST COMPLETADO - CABYS catalog & variant Insert/Delete verified';
    RAISE NOTICE '========================================';
END $$;