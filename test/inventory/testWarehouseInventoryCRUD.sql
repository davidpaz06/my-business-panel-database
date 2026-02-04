-- ============================================
-- TEST: CRUD WAREHOUSE & INVENTORY (IDEMPOTENTE)
-- ============================================
-- Objetivo: Probar creación, lectura, actualización y eliminación
--            para `warehouse` e `inventory`, y validar constraints.
-- ============================================

-- ========================================
-- SECCIÓN 0: Limpieza inicial (idempotente)
-- ========================================
DO $$
DECLARE
    v_warehouse_name VARCHAR := 'test_warehouse_mvp';
    v_warehouse_id uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧹 SECCIÓN 0: Limpieza inicial';
    RAISE NOTICE '========================================';

    SELECT warehouse_id INTO v_warehouse_id
    FROM inventory_schema.warehouse
    WHERE warehouse_name = v_warehouse_name
    LIMIT 1;

    IF v_warehouse_id IS NOT NULL THEN
        DELETE FROM inventory_schema.inventory WHERE warehouse_id = v_warehouse_id;
        DELETE FROM inventory_schema.warehouse WHERE warehouse_id = v_warehouse_id;
        RAISE NOTICE '   ✓ Warehouse and related inventory removed: %', v_warehouse_id;
    ELSE
        RAISE NOTICE '   No existing test warehouse found';
    END IF;

    RAISE NOTICE '✅ Limpieza completada';
    RAISE NOTICE '========================================';
END $$;

-- ========================================
-- SECCIÓN 1: Creación de warehouse e inventory
-- ========================================
DO $$
DECLARE
    v_warehouse_id uuid;
    v_branch_id uuid := (SELECT branch_id FROM general_schema.branch LIMIT 1);
    v_tenant_id uuid;
    v_product_id uuid;
    v_inventory_id uuid;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📦 SECCIÓN 1: Creación de warehouse e inventory';
    RAISE NOTICE '========================================';

    IF v_branch_id IS NULL THEN
        RAISE EXCEPTION 'No hay registros en general_schema.branch. Inserte al menos una branch en general_schema.branch';
    END IF;

    -- Crear warehouse
    INSERT INTO inventory_schema.warehouse(branch_id, warehouse_name, warehouse_address)
    VALUES (v_branch_id, 'test_warehouse_mvp', 'Address 123')
    RETURNING warehouse_id INTO v_warehouse_id;

    IF v_warehouse_id IS NULL THEN
        RAISE EXCEPTION 'Error: no se creó warehouse';
    END IF;
    RAISE NOTICE '   ✓ Warehouse creado: %', v_warehouse_id;

    -- Obtener un product_variant existente para inventory (tenant_id, product_variant_id)
    SELECT tenant_id, product_variant_id INTO v_tenant_id, v_product_id FROM general_schema.product_variant LIMIT 1;
    IF v_product_id IS NULL THEN
        -- Si no hay product_variant, limpiamos y abortamos test
        DELETE FROM inventory_schema.inventory WHERE warehouse_id = v_warehouse_id;
        DELETE FROM inventory_schema.warehouse WHERE warehouse_id = v_warehouse_id;
        RAISE EXCEPTION 'No hay registros en general_schema.product_variant. Inserte al menos un product_variant';
    END IF;

    -- Insertar inventory válido
    INSERT INTO inventory_schema.inventory(tenant_id, product_variant_id, warehouse_id, stock, expiration_date)
    VALUES (v_tenant_id, v_product_id, v_warehouse_id, 100, current_timestamp + interval '30 days')
    RETURNING inventory_id INTO v_inventory_id;

    IF v_inventory_id IS NULL THEN
        RAISE EXCEPTION 'Error: no se creó inventory';
    END IF;
    RAISE NOTICE '   ✓ Inventory creado: %', v_inventory_id;

    RAISE NOTICE '✅ SECCIÓN 1 COMPLETADA';
    RAISE NOTICE '========================================';
END $$ LANGUAGE plpgsql;

-- ========================================
-- SECCIÓN 2: Lectura y validaciones
-- ========================================
DO $$
DECLARE
    v_warehouse_id uuid;
    v_inventory_count int;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🔍 SECCIÓN 2: Lectura y validaciones';
    RAISE NOTICE '========================================';

    SELECT warehouse_id INTO v_warehouse_id FROM inventory_schema.warehouse WHERE warehouse_name = 'test_warehouse_mvp' LIMIT 1;
    IF v_warehouse_id IS NULL THEN
        RAISE EXCEPTION 'No se encontró el warehouse de prueba';
    END IF;

    SELECT count(*) INTO v_inventory_count FROM inventory_schema.inventory WHERE warehouse_id = v_warehouse_id;
    RAISE NOTICE '   Inventories found for warehouse %: %', v_warehouse_id, v_inventory_count;

    IF v_inventory_count = 0 THEN
        RAISE EXCEPTION 'No se halló inventory asociado al warehouse';
    END IF;

    RAISE NOTICE '✅ SECCIÓN 2 COMPLETADA';
    RAISE NOTICE '========================================';
END $$ LANGUAGE plpgsql;

-- ========================================
-- SECCIÓN 3: Actualización
-- ========================================
DO $$
DECLARE
    v_warehouse_id uuid;
    v_inventory_id uuid;
    v_old_stock INTEGER;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✏️ SECCIÓN 3: Actualización';
    RAISE NOTICE '========================================';

    SELECT warehouse_id INTO v_warehouse_id FROM inventory_schema.warehouse WHERE warehouse_name = 'test_warehouse_mvp' LIMIT 1;
    SELECT inventory_id, stock INTO v_inventory_id, v_old_stock FROM inventory_schema.inventory WHERE warehouse_id = v_warehouse_id LIMIT 1;

    IF v_inventory_id IS NULL THEN
        RAISE EXCEPTION 'No hay inventory para actualizar';
    END IF;

    -- Actualizar stock
    UPDATE inventory_schema.inventory SET stock = stock + 50 WHERE inventory_id = v_inventory_id;
    RAISE NOTICE '   ✓ Stock actualizado de % a %', v_old_stock, v_old_stock + 50;

    -- Actualizar warehouse_name
    UPDATE inventory_schema.warehouse SET warehouse_name = 'test_warehouse_mvp_updated', updated_at = current_timestamp WHERE warehouse_id = v_warehouse_id;
    RAISE NOTICE '   ✓ Warehouse name actualizado: %', v_warehouse_id;

    RAISE NOTICE '✅ SECCIÓN 3 COMPLETADA';
    RAISE NOTICE '========================================';
END $$ LANGUAGE plpgsql;

-- ========================================
-- SECCIÓN 4: Borrado y validación de cascada
-- ========================================
DO $$
DECLARE
    v_warehouse_id uuid;
    v_inventory_count int;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🗑️ SECCIÓN 4: Borrado y validación de cascada';
    RAISE NOTICE '========================================';

    SELECT warehouse_id INTO v_warehouse_id FROM inventory_schema.warehouse WHERE warehouse_name = 'test_warehouse_mvp_updated' LIMIT 1;
    IF v_warehouse_id IS NULL THEN
        RAISE EXCEPTION 'No se encontró el warehouse actualizado para borrar';
    END IF;

    DELETE FROM inventory_schema.warehouse WHERE warehouse_id = v_warehouse_id;
    RAISE NOTICE '   ✓ Warehouse eliminado: %', v_warehouse_id;

    SELECT count(*) INTO v_inventory_count FROM inventory_schema.inventory WHERE warehouse_id = v_warehouse_id;
    IF v_inventory_count = 0 THEN
        RAISE NOTICE '   ✅ Cascade delete confirmado: no hay inventory para %', v_warehouse_id;
    ELSE
        RAISE EXCEPTION 'Inventory no fue eliminado por cascade: % registros restantes', v_inventory_count;
    END IF;

    RAISE NOTICE '✅ SECCIÓN 4 COMPLETADA';
    RAISE NOTICE '========================================';
END $$ LANGUAGE plpgsql;

-- ========================================
-- SECCIÓN 5: Validación de constraint (expiration_date)
-- ========================================
DO $$
DECLARE
    v_branch_id uuid := (SELECT branch_id FROM general_schema.branch LIMIT 1);
    v_warehouse_id uuid;
    v_tenant_id uuid;
    v_product_id uuid;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🛡️ SECCIÓN 5: Validación de constraint (expiration_date)';
    RAISE NOTICE '========================================';

    -- Recrear warehouse temporal para probar constraint
    INSERT INTO inventory_schema.warehouse(branch_id, warehouse_name, warehouse_address)
    VALUES (v_branch_id, 'test_warehouse_mvp_tmp', 'Address tmp')
    RETURNING warehouse_id INTO v_warehouse_id;

    SELECT tenant_id, product_id INTO v_tenant_id, v_product_id FROM general_schema.product LIMIT 1;
    IF v_product_id IS NULL THEN
        DELETE FROM inventory_schema.warehouse WHERE warehouse_id = v_warehouse_id;
        RAISE EXCEPTION 'No hay registros en general_schema.product. Inserte al menos un product en general_schema.product';
    END IF;

    RAISE NOTICE '   Forzando inserción inválida (expiration_date en el pasado)';
    BEGIN
        INSERT INTO inventory_schema.inventory(tenant_id, product_id, warehouse_id, stock, expiration_date)
        VALUES (v_tenant_id, v_product_id, v_warehouse_id, 1, current_timestamp - interval '1 day');

        RAISE EXCEPTION '❌ Fallo de prueba: Se permitió la inserción inválida de inventory';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLSTATE = '23514' THEN
                RAISE NOTICE '   ✅ EXITO. Inserción bloqueada por constraint de expiration_date';
            ELSE
                RAISE EXCEPTION 'Se lanzó una excepción inesperada: %', SQLERRM;
            END IF;
    END;

    -- Limpieza del warehouse temporal
    DELETE FROM inventory_schema.inventory WHERE warehouse_id = v_warehouse_id;
    DELETE FROM inventory_schema.warehouse WHERE warehouse_id = v_warehouse_id;

    RAISE NOTICE '✅ SECCIÓN 5 COMPLETADA';
    RAISE NOTICE '========================================';
END $$ LANGUAGE plpgsql;

-- ========================================
-- SECCIÓN 6: Resumen final
-- ========================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📊 SECCIÓN 6: RESUMEN FINAL';
    RAISE NOTICE '========================================';
    RAISE NOTICE '   ✅ TEST WAREHOUSE & INVENTORY FINALIZADO EXITOSAMENTE';
    RAISE NOTICE '========================================';
END $$ LANGUAGE plpgsql;
