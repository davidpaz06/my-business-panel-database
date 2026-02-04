-- ============================================
-- TEST: MANUAL DISCREPANCY REPORT (IDEMPOTENTE)
-- ============================================
-- Objetivo: Crear warehouse + inventory, realizar un conteo físico
--           distinto del stock del sistema y generar un registro
--           en `discrepancy_count` para simular reporte manual.
-- ============================================

-- ========================================
-- SECCIÓN 0: Limpieza inicial (idempotente)
-- ========================================
DO $$
DECLARE
    v_wh_name VARCHAR := 'test_warehouse_discrepancy';
    v_wh_id uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧹 SECCIÓN 0: Limpieza inicial';
    RAISE NOTICE '========================================';

    SELECT warehouse_id INTO v_wh_id
    FROM inventory_schema.warehouse
    WHERE warehouse_name = v_wh_name
    LIMIT 1;

    IF v_wh_id IS NOT NULL THEN
        DELETE FROM inventory_schema.discrepancy_count WHERE warehouse_id = v_wh_id;
        DELETE FROM inventory_schema.inventory WHERE warehouse_id = v_wh_id;
        DELETE FROM inventory_schema.warehouse WHERE warehouse_id = v_wh_id;
        RAISE NOTICE '   ✓ Removed previous test warehouse and related rows: %', v_wh_id;
    ELSE
        RAISE NOTICE '   No prior test warehouse found';
    END IF;

    RAISE NOTICE '✅ Limpieza completada';
    RAISE NOTICE '========================================';
END $$ LANGUAGE plpgsql;

-- ========================================
-- SECCIÓN 1: Preparar datos (warehouse + inventory)
-- ========================================
DO $$
DECLARE
    v_tenant_id uuid := (SELECT tenant_id FROM general_schema.tenant LIMIT 1);
    v_branch_id uuid := (SELECT branch_id FROM general_schema.branch WHERE tenant_id = v_tenant_id LIMIT 1);
    v_product_id uuid;
    v_wh_id uuid;
    v_inv_id uuid;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📦 SECCIÓN 1: Preparar datos (warehouse + inventory)';
    RAISE NOTICE '========================================';

    IF v_branch_id IS NULL THEN
        RAISE EXCEPTION 'No hay registros en general_schema.branch. Inserte al menos una branch en general_schema.branch';
    END IF;

    -- Crear warehouse de prueba
    INSERT INTO inventory_schema.warehouse(branch_id, warehouse_name, warehouse_address)
    VALUES (v_branch_id, 'test_warehouse_discrepancy', 'Discrepancy address')
    RETURNING warehouse_id INTO v_wh_id;

    RAISE NOTICE '   ✓ Warehouse creado: %', v_wh_id;

    -- Obtener un product_variant existente
    SELECT product_variant_id INTO v_product_id FROM general_schema.product_variant WHERE tenant_id = v_tenant_id LIMIT 1;
    IF v_product_id IS NULL THEN
        DELETE FROM inventory_schema.warehouse WHERE warehouse_id = v_wh_id;
        RAISE EXCEPTION 'No hay product_variant en general_schema.product_variant. Inserte al menos un registro';
    END IF;

    -- Insertar inventory con stock conocido (sistema)
    INSERT INTO inventory_schema.inventory(tenant_id, product_variant_id, warehouse_id, stock, expiration_date)
    VALUES (v_tenant_id, v_product_id, v_wh_id, 42, current_timestamp + interval '90 days')
    RETURNING inventory_id INTO v_inv_id;

    RAISE NOTICE '   ✓ Inventory insertado: % (stock sistema = 42)', v_inv_id;
    RAISE NOTICE '✅ SECCIÓN 1 COMPLETADA';
    RAISE NOTICE '========================================';
END $$ LANGUAGE plpgsql;

-- ========================================
-- SECCIÓN 2: Conteo físico y cálculo de discrepancia
-- ========================================
DO $$
DECLARE
    v_wh_id uuid := (SELECT warehouse_id FROM inventory_schema.warehouse WHERE warehouse_name = 'test_warehouse_discrepancy' LIMIT 1);
    v_tenant_id uuid;
    v_product_id uuid;
    v_system_stock INTEGER;
    v_physical_count INTEGER := 37; -- conteo físico asumido distinto (ejemplo)
    v_delta INTEGER;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🔢 SECCIÓN 2: Conteo físico y cálculo de discrepancia';
    RAISE NOTICE '========================================';

    IF v_wh_id IS NULL THEN
        RAISE EXCEPTION 'No se encontró warehouse de prueba';
    END IF;

    SELECT tenant_id, product_variant_id, stock INTO v_tenant_id, v_product_id, v_system_stock
    FROM inventory_schema.inventory
    WHERE warehouse_id = v_wh_id
    LIMIT 1;

    IF v_product_id IS NULL THEN
        RAISE EXCEPTION 'No inventory para contar';
    END IF;

    RAISE NOTICE '   Stock en sistema para product_variant %: %', v_product_id, v_system_stock;
    RAISE NOTICE '   Conteo físico (simulado): %', v_physical_count;

    v_delta := v_physical_count - v_system_stock;
    RAISE NOTICE '   Delta (physical - system) = %', v_delta;

    RAISE NOTICE '✅ SECCIÓN 2 COMPLETADA';
    RAISE NOTICE '========================================';
END $$ LANGUAGE plpgsql;

-- ========================================
-- SECCIÓN 3: Registrar discrepancy_count (reporte manual)
-- ========================================
DO $$
DECLARE
    v_wh_id uuid := (SELECT warehouse_id FROM inventory_schema.warehouse WHERE warehouse_name = 'test_warehouse_discrepancy' LIMIT 1);
    v_tenant_id uuid;
    v_product_id uuid;
    v_stored INTEGER;
    v_physical INTEGER := 37; -- mismo valor usado arriba
    v_report_id uuid;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📝 SECCIÓN 3: Registrar discrepancy_count (reporte manual)';
    RAISE NOTICE '========================================';

    SELECT tenant_id, product_variant_id, stock INTO v_tenant_id, v_product_id, v_stored
    FROM inventory_schema.inventory
    WHERE warehouse_id = v_wh_id
    LIMIT 1;

    IF v_product_id IS NULL THEN
        RAISE EXCEPTION 'No inventory para reportar discrepancia';
    END IF;

    INSERT INTO inventory_schema.discrepancy_count(tenant_id, product_variant_id, warehouse_id, stored_quantity, physical_quantity, discrepancy_reason)
    VALUES (v_tenant_id, v_product_id, v_wh_id, v_stored, v_physical, 'Manual count: found fewer items than system')
    RETURNING discrepancy_count_id INTO v_report_id;

    RAISE NOTICE '   ✓ Discrepancy registrado: % (stored=% physical=%)', v_report_id, v_stored, v_physical;

    -- Verificar registro
    PERFORM 1 FROM inventory_schema.discrepancy_count WHERE discrepancy_count_id = v_report_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'No se pudo verificar el registro de discrepancy';
    END IF;

    RAISE NOTICE '✅ SECCIÓN 3 COMPLETADA';
    RAISE NOTICE '========================================';
END $$ LANGUAGE plpgsql;

-- ========================================
-- SECCIÓN 4: Limpieza y resumen
-- ========================================
DO $$
DECLARE
    v_wh_id uuid := (SELECT warehouse_id FROM inventory_schema.warehouse WHERE warehouse_name = 'test_warehouse_discrepancy' LIMIT 1);
    v_report_count int;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧾 SECCIÓN 4: Limpieza y resumen';
    RAISE NOTICE '========================================';

    IF v_wh_id IS NULL THEN
        RAISE NOTICE 'No hay warehouse de prueba para limpiar';
    ELSE
        SELECT count(*) INTO v_report_count FROM inventory_schema.discrepancy_count WHERE warehouse_id = v_wh_id;
        RAISE NOTICE '   Discrepancy reports for warehouse %: %', v_wh_id, v_report_count;

        -- Limpiar registros de prueba
        DELETE FROM inventory_schema.discrepancy_count WHERE warehouse_id = v_wh_id;
        DELETE FROM inventory_schema.inventory WHERE warehouse_id = v_wh_id;
        DELETE FROM inventory_schema.warehouse WHERE warehouse_id = v_wh_id;
        RAISE NOTICE '   ✓ Test rows removed';
    END IF;

    RAISE NOTICE '';
    RAISE NOTICE '┌────────────────────────────────────────────┐';
    RAISE NOTICE '│  ✅ TEST MANUAL DISCREPANCY FINALIZADO     │';
    RAISE NOTICE '└────────────────────────────────────────────┘';
    RAISE NOTICE '';
END $$ LANGUAGE plpgsql;
