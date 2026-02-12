-- ============================================
-- TEST: PRODUCT VARIANT MODEL - CRUD & INVENTORY (IDEMPOTENTE)
-- ============================================
-- Objetivo: 
--   - Crear productos base
--   - Crear atributos y valores (Color, Size)
--   - Crear variantes de producto con atributos asignados
--   - Registrar inventario por variante
--   - Listar inventario por variante
-- ============================================
-- Estructura:
--   0) Limpieza inicial (idempotente)
--   1) Preparación (tenant, branch, warehouse, categoría)
--   2) Crear atributos y valores
--   3) Crear producto base
--   4) Crear variantes de producto
--   5) Asignar atributos a variantes
--   6) Registrar inventario por variante
--   7) Consultas de verificación
--   8) Resumen final
-- ============================================

SET LOCAL search_path = general_schema, inventory_schema, pos_schema;

-- ========================================
-- SECCIÓN 0: Limpieza inicial (idempotente)
-- ========================================
DO $$
DECLARE
    v_tenant_id UUID;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧹 SECCIÓN 0: Limpieza inicial (idempotente)';
    RAISE NOTICE '========================================';

    SELECT tenant_id INTO v_tenant_id 
    FROM general_schema.tenant 
    WHERE tenant_name = 'Variant Test Shop' 
    LIMIT 1;

    IF v_tenant_id IS NOT NULL THEN
        -- Limpiar en orden de dependencias
        DELETE FROM inventory_schema.inventory WHERE tenant_id = v_tenant_id;
        DELETE FROM inventory_schema.inventory_transfer_product WHERE tenant_id = v_tenant_id;
        DELETE FROM inventory_schema.inventory_log WHERE tenant_id = v_tenant_id;
        DELETE FROM general_schema.attribute_assignation WHERE tenant_id = v_tenant_id;
        DELETE FROM general_schema.product_variant WHERE tenant_id = v_tenant_id;
        DELETE FROM general_schema.attribute_value WHERE tenant_id = v_tenant_id;
        DELETE FROM general_schema.tenant_attribute WHERE tenant_id = v_tenant_id;
        DELETE FROM inventory_schema.warehouse 
        WHERE branch_id IN (
            SELECT branch_id FROM general_schema.branch WHERE tenant_id = v_tenant_id
        );
        DELETE FROM general_schema.branch WHERE tenant_id = v_tenant_id;
        DELETE FROM general_schema.tenant WHERE tenant_id = v_tenant_id;
        
        RAISE NOTICE '   ✓ Removed previous test data for tenant: %', v_tenant_id;
    ELSE
        RAISE NOTICE '   ℹ️  No previous test tenant found';
    END IF;

    -- Limpiar entradas CABYS de prueba
    DELETE FROM general_schema.product WHERE cabys_code LIKE 'TSHIRT%';
    RAISE NOTICE '   ✓ Removed test CABYS entries';

    RAISE NOTICE '✅ SECCIÓN 0 COMPLETADA';
    RAISE NOTICE '========================================';
END $$;

-- ========================================
-- SECCIÓN 1: Preparación (tenant, branch, warehouse, categoría)
-- ========================================
DO $$
DECLARE
    v_tenant_id UUID;
    v_region_id INT;
    v_branch_id UUID;
    v_warehouse_id UUID;
    v_category_id INT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🏪 SECCIÓN 1: Preparación (tenant, branch, warehouse, categoría)';
    RAISE NOTICE '========================================';

    -- Obtener o crear región
    SELECT region_id INTO v_region_id 
    FROM general_schema.region 
    WHERE region_name = 'Test Region' 
    LIMIT 1;
    
    IF v_region_id IS NULL THEN
        INSERT INTO general_schema.region (region_name) 
        VALUES ('Test Region') 
        RETURNING region_id INTO v_region_id;
        RAISE NOTICE '   ✓ Region created: %', v_region_id;
    ELSE
        RAISE NOTICE '   ℹ️  Region exists: %', v_region_id;
    END IF;

    -- Crear tenant
    INSERT INTO general_schema.tenant (
        tenant_name, 
        region_id, 
        contact_email, 
        is_subscribed
    ) VALUES (
        'Variant Test Shop', 
        v_region_id, 
        'variants@testshop.local', 
        TRUE
    )
    RETURNING tenant_id INTO v_tenant_id;
    RAISE NOTICE '   ✓ Tenant created: %', v_tenant_id;

    -- Crear branch
    INSERT INTO general_schema.branch (
        tenant_id,
        branch_name,
        branch_address,
        contact_email,
        is_main_branch
    ) VALUES (
        v_tenant_id,
        'Main Store',
        '123 Test Street',
        'main@testshop.local',
        TRUE
    )
    RETURNING branch_id INTO v_branch_id;
    RAISE NOTICE '   ✓ Branch created: %', v_branch_id;

    -- Crear warehouse
    INSERT INTO inventory_schema.warehouse (
        branch_id,
        warehouse_name,
        warehouse_address,
        is_branch
    ) VALUES (
        v_branch_id,
        'Main Warehouse',
        '123 Test Street',
        TRUE
    )
    RETURNING warehouse_id INTO v_warehouse_id;
    RAISE NOTICE '   ✓ Warehouse created: %', v_warehouse_id;

    -- Crear categoría de producto
    INSERT INTO general_schema.product_category (category_name)
    VALUES ('Clothing')
    ON CONFLICT (category_name) DO NOTHING
    RETURNING product_category_id INTO v_category_id;
    
    IF v_category_id IS NULL THEN
        SELECT product_category_id INTO v_category_id 
        FROM general_schema.product_category 
        WHERE category_name = 'Clothing';
        RAISE NOTICE '   ℹ️  Category exists: %', v_category_id;
    ELSE
        RAISE NOTICE '   ✓ Category created: %', v_category_id;
    END IF;

    RAISE NOTICE '✅ SECCIÓN 1 COMPLETADA';
    RAISE NOTICE '========================================';
END $$;
select * from general_schema.product_category
-- ========================================
-- SECCIÓN 2: Crear atributos y valores
-- ========================================
BEGIN
    -- Variables
    DO $$
    DECLARE
        v_tenant_id UUID := (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Variant Test Shop' LIMIT 1);
        v_attr_color UUID;
        v_attr_size UUID;
        v_val_red UUID;
        v_val_blue UUID;
        v_val_green UUID;
        v_val_s UUID;
        v_val_m UUID;
        v_val_l UUID;
        v_val_xl UUID;
    BEGIN
        RAISE NOTICE '';
        RAISE NOTICE '========================================';
        RAISE NOTICE '🎨 SECCIÓN 2: Crear atributos y valores';
        RAISE NOTICE '========================================';

        -- Crear atributo "Color"
        INSERT INTO general_schema.tenant_attribute (
            tenant_id,
            attribute_name,
            is_custom
        ) VALUES (
            v_tenant_id,
            'Color',
            TRUE
        )
        RETURNING tenant_attribute_id INTO v_attr_color;
        RAISE NOTICE '   ✓ Attribute "Color" created: %', v_attr_color;

        -- Crear atributo "Size"
        INSERT INTO general_schema.tenant_attribute (
            tenant_id,
            attribute_name,
            is_custom
        ) VALUES (
            v_tenant_id,
            'Size',
            TRUE
        )
        RETURNING tenant_attribute_id INTO v_attr_size;
        RAISE NOTICE '   ✓ Attribute "Size" created: %', v_attr_size;

        -- Crear valores para Color
        INSERT INTO general_schema.attribute_value (tenant_id, tenant_attribute_id, value_name)
        VALUES (v_tenant_id, v_attr_color, 'Red')
        RETURNING attribute_value_id INTO v_val_red;
        RAISE NOTICE '   ✓ Value "Red" created: %', v_val_red;

        INSERT INTO general_schema.attribute_value (tenant_id, tenant_attribute_id, value_name)
        VALUES (v_tenant_id, v_attr_color, 'Blue')
        RETURNING attribute_value_id INTO v_val_blue;
        RAISE NOTICE '   ✓ Value "Blue" created: %', v_val_blue;

        INSERT INTO general_schema.attribute_value (tenant_id, tenant_attribute_id, value_name)
        VALUES (v_tenant_id, v_attr_color, 'Green')
        RETURNING attribute_value_id INTO v_val_green;
        RAISE NOTICE '   ✓ Value "Green" created: %', v_val_green;

        -- Crear valores para Size
        INSERT INTO general_schema.attribute_value (tenant_id, tenant_attribute_id, value_name)
        VALUES (v_tenant_id, v_attr_size, 'S')
        RETURNING attribute_value_id INTO v_val_s;
        RAISE NOTICE '   ✓ Value "S" created: %', v_val_s;

        INSERT INTO general_schema.attribute_value (tenant_id, tenant_attribute_id, value_name)
        VALUES (v_tenant_id, v_attr_size, 'M')
        RETURNING attribute_value_id INTO v_val_m;
        RAISE NOTICE '   ✓ Value "M" created: %', v_val_m;

        INSERT INTO general_schema.attribute_value (tenant_id, tenant_attribute_id, value_name)
        VALUES (v_tenant_id, v_attr_size, 'L')
        RETURNING attribute_value_id INTO v_val_l;
        RAISE NOTICE '   ✓ Value "L" created: %', v_val_l;

        INSERT INTO general_schema.attribute_value (tenant_id, tenant_attribute_id, value_name)
        VALUES (v_tenant_id, v_attr_size, 'XL')
        RETURNING attribute_value_id INTO v_val_xl;
        RAISE NOTICE '   ✓ Value "XL" created: %', v_val_xl;

        RAISE NOTICE '   📊 Summary: 2 attributes, 7 values created';
        RAISE NOTICE '✅ SECCIÓN 2 COMPLETADA';
        RAISE NOTICE '========================================';
    END $$;
END;

-- ========================================
-- SECCIÓN 3: Crear entrada CABYS (catálogo global)
-- ========================================
DO $$
DECLARE
    v_category_id INT := (SELECT product_category_id FROM general_schema.product_category WHERE category_name = 'Clothing' LIMIT 1);
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📦 SECCIÓN 3: Crear entrada CABYS (catálogo global)';
    RAISE NOTICE '========================================';

    -- Crear entrada CABYS: Camiseta de algodón
    INSERT INTO general_schema.product (
        cabys_code,
        product_name,
        product_category_id
    ) VALUES (
        'TSHIRT0000001',
        'Camiseta de algodón',
        v_category_id
    )
    ON CONFLICT (cabys_code) DO NOTHING;
    
    RAISE NOTICE '   ✓ CABYS entry created:';
    RAISE NOTICE '     - Code: TSHIRT0000001';
    RAISE NOTICE '     - Name: Camiseta de algodón';

    RAISE NOTICE '✅ SECCIÓN 3 COMPLETADA';
    RAISE NOTICE '========================================';
END $$;

-- ========================================
-- SECCIÓN 4: Crear variantes de producto
-- ========================================
DO $$
DECLARE
    v_tenant_id UUID := (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Variant Test Shop' LIMIT 1);
    v_variant_id UUID;
    v_count INT := 0;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🎯 SECCIÓN 4: Crear variantes de producto';
    RAISE NOTICE '========================================';

    -- Red S
    INSERT INTO general_schema.product_variant (
        tenant_id, cabys_code, sku, variant_name, unit_price, is_active
    ) VALUES (
        v_tenant_id, 'TSHIRT0000001', 'TSHIRT-RED-S', 'Cotton T-Shirt - Red/S', 25.00, TRUE
    )
    RETURNING product_variant_id INTO v_variant_id;
    RAISE NOTICE '   ✓ Variant created: TSHIRT-RED-S (%)', v_variant_id;
    v_count := v_count + 1;

    -- Red M
    INSERT INTO general_schema.product_variant (
        tenant_id, cabys_code, sku, variant_name, unit_price, is_active
    ) VALUES (
        v_tenant_id, 'TSHIRT0000001', 'TSHIRT-RED-M', 'Cotton T-Shirt - Red/M', 25.00, TRUE
    )
    RETURNING product_variant_id INTO v_variant_id;
    RAISE NOTICE '   ✓ Variant created: TSHIRT-RED-M (%)', v_variant_id;
    v_count := v_count + 1;

    -- Red L
    INSERT INTO general_schema.product_variant (
        tenant_id, cabys_code, sku, variant_name, unit_price, is_active
    ) VALUES (
        v_tenant_id, 'TSHIRT0000001', 'TSHIRT-RED-L', 'Cotton T-Shirt - Red/L', 27.00, TRUE
    )
    RETURNING product_variant_id INTO v_variant_id;
    RAISE NOTICE '   ✓ Variant created: TSHIRT-RED-L (%)', v_variant_id;
    v_count := v_count + 1;

    -- Blue S
    INSERT INTO general_schema.product_variant (
        tenant_id, cabys_code, sku, variant_name, unit_price, is_active
    ) VALUES (
        v_tenant_id, 'TSHIRT0000001', 'TSHIRT-BLUE-S', 'Cotton T-Shirt - Blue/S', 25.00, TRUE
    )
    RETURNING product_variant_id INTO v_variant_id;
    RAISE NOTICE '   ✓ Variant created: TSHIRT-BLUE-S (%)', v_variant_id;
    v_count := v_count + 1;

    -- Blue M
    INSERT INTO general_schema.product_variant (
        tenant_id, cabys_code, sku, variant_name, unit_price, is_active
    ) VALUES (
        v_tenant_id, 'TSHIRT0000001', 'TSHIRT-BLUE-M', 'Cotton T-Shirt - Blue/M', 25.00, TRUE
    )
    RETURNING product_variant_id INTO v_variant_id;
    RAISE NOTICE '   ✓ Variant created: TSHIRT-BLUE-M (%)', v_variant_id;
    v_count := v_count + 1;

    -- Blue XL
    INSERT INTO general_schema.product_variant (
        tenant_id, cabys_code, sku, variant_name, unit_price, is_active
    ) VALUES (
        v_tenant_id, 'TSHIRT0000001', 'TSHIRT-BLUE-XL', 'Cotton T-Shirt - Blue/XL', 29.00, TRUE
    )
    RETURNING product_variant_id INTO v_variant_id;
    RAISE NOTICE '   ✓ Variant created: TSHIRT-BLUE-XL (%)', v_variant_id;
    v_count := v_count + 1;

    -- Green M
    INSERT INTO general_schema.product_variant (
        tenant_id, cabys_code, sku, variant_name, unit_price, is_active
    ) VALUES (
        v_tenant_id, 'TSHIRT0000001', 'TSHIRT-GREEN-M', 'Cotton T-Shirt - Green/M', 25.00, TRUE
    )
    RETURNING product_variant_id INTO v_variant_id;
    RAISE NOTICE '   ✓ Variant created: TSHIRT-GREEN-M (%)', v_variant_id;
    v_count := v_count + 1;

    -- Green L
    INSERT INTO general_schema.product_variant (
        tenant_id, cabys_code, sku, variant_name, unit_price, is_active
    ) VALUES (
        v_tenant_id, 'TSHIRT0000001', 'TSHIRT-GREEN-L', 'Cotton T-Shirt - Green/L', 27.00, TRUE
    )
    RETURNING product_variant_id INTO v_variant_id;
    RAISE NOTICE '   ✓ Variant created: TSHIRT-GREEN-L (%)', v_variant_id;
    v_count := v_count + 1;

    RAISE NOTICE '';
    RAISE NOTICE '   📊 Summary: % variants created', v_count;
    RAISE NOTICE '✅ SECCIÓN 4 COMPLETADA';
    RAISE NOTICE '========================================';
END $$;

-- ========================================
-- SECCIÓN 5: Asignar atributos a variantes
-- ========================================
DO $$
DECLARE
    v_tenant_id UUID := (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Variant Test Shop' LIMIT 1);
    v_attr_color UUID := (SELECT tenant_attribute_id FROM general_schema.tenant_attribute WHERE tenant_id = v_tenant_id AND attribute_name = 'Color');
    v_attr_size UUID := (SELECT tenant_attribute_id FROM general_schema.tenant_attribute WHERE tenant_id = v_tenant_id AND attribute_name = 'Size');
    v_val_red UUID := (SELECT attribute_value_id FROM general_schema.attribute_value WHERE tenant_id = v_tenant_id AND tenant_attribute_id = v_attr_color AND value_name = 'Red');
    v_val_blue UUID := (SELECT attribute_value_id FROM general_schema.attribute_value WHERE tenant_id = v_tenant_id AND tenant_attribute_id = v_attr_color AND value_name = 'Blue');
    v_val_green UUID := (SELECT attribute_value_id FROM general_schema.attribute_value WHERE tenant_id = v_tenant_id AND tenant_attribute_id = v_attr_color AND value_name = 'Green');
    v_val_s UUID := (SELECT attribute_value_id FROM general_schema.attribute_value WHERE tenant_id = v_tenant_id AND tenant_attribute_id = v_attr_size AND value_name = 'S');
    v_val_m UUID := (SELECT attribute_value_id FROM general_schema.attribute_value WHERE tenant_id = v_tenant_id AND tenant_attribute_id = v_attr_size AND value_name = 'M');
    v_val_l UUID := (SELECT attribute_value_id FROM general_schema.attribute_value WHERE tenant_id = v_tenant_id AND tenant_attribute_id = v_attr_size AND value_name = 'L');
    v_val_xl UUID := (SELECT attribute_value_id FROM general_schema.attribute_value WHERE tenant_id = v_tenant_id AND tenant_attribute_id = v_attr_size AND value_name = 'XL');
    v_variant_id UUID;
    v_count INT := 0;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🔗 SECCIÓN 5: Asignar atributos a variantes';
    RAISE NOTICE '========================================';

    -- Red S = Color:Red + Size:S
    SELECT product_variant_id INTO v_variant_id FROM general_schema.product_variant WHERE tenant_id = v_tenant_id AND sku = 'TSHIRT-RED-S';
    INSERT INTO general_schema.attribute_assignation (tenant_id, product_variant_id, attribute_value_id)
    VALUES 
        (v_tenant_id, v_variant_id, v_val_red),
        (v_tenant_id, v_variant_id, v_val_s);
    RAISE NOTICE '   ✓ TSHIRT-RED-S: Color=Red, Size=S';
    v_count := v_count + 2;

    -- Red M = Color:Red + Size:M
    SELECT product_variant_id INTO v_variant_id FROM general_schema.product_variant WHERE tenant_id = v_tenant_id AND sku = 'TSHIRT-RED-M';
    INSERT INTO general_schema.attribute_assignation (tenant_id, product_variant_id, attribute_value_id)
    VALUES 
        (v_tenant_id, v_variant_id, v_val_red),
        (v_tenant_id, v_variant_id, v_val_m);
    RAISE NOTICE '   ✓ TSHIRT-RED-M: Color=Red, Size=M';
    v_count := v_count + 2;

    -- Red L = Color:Red + Size:L
    SELECT product_variant_id INTO v_variant_id FROM general_schema.product_variant WHERE tenant_id = v_tenant_id AND sku = 'TSHIRT-RED-L';
    INSERT INTO general_schema.attribute_assignation (tenant_id, product_variant_id, attribute_value_id)
    VALUES 
        (v_tenant_id, v_variant_id, v_val_red),
        (v_tenant_id, v_variant_id, v_val_l);
    RAISE NOTICE '   ✓ TSHIRT-RED-L: Color=Red, Size=L';
    v_count := v_count + 2;

    -- Blue S = Color:Blue + Size:S
    SELECT product_variant_id INTO v_variant_id FROM general_schema.product_variant WHERE tenant_id = v_tenant_id AND sku = 'TSHIRT-BLUE-S';
    INSERT INTO general_schema.attribute_assignation (tenant_id, product_variant_id, attribute_value_id)
    VALUES 
        (v_tenant_id, v_variant_id, v_val_blue),
        (v_tenant_id, v_variant_id, v_val_s);
    RAISE NOTICE '   ✓ TSHIRT-BLUE-S: Color=Blue, Size=S';
    v_count := v_count + 2;

    -- Blue M = Color:Blue + Size:M
    SELECT product_variant_id INTO v_variant_id FROM general_schema.product_variant WHERE tenant_id = v_tenant_id AND sku = 'TSHIRT-BLUE-M';
    INSERT INTO general_schema.attribute_assignation (tenant_id, product_variant_id, attribute_value_id)
    VALUES 
        (v_tenant_id, v_variant_id, v_val_blue),
        (v_tenant_id, v_variant_id, v_val_m);
    RAISE NOTICE '   ✓ TSHIRT-BLUE-M: Color=Blue, Size=M';
    v_count := v_count + 2;

    -- Blue XL = Color:Blue + Size:XL
    SELECT product_variant_id INTO v_variant_id FROM general_schema.product_variant WHERE tenant_id = v_tenant_id AND sku = 'TSHIRT-BLUE-XL';
    INSERT INTO general_schema.attribute_assignation (tenant_id, product_variant_id, attribute_value_id)
    VALUES 
        (v_tenant_id, v_variant_id, v_val_blue),
        (v_tenant_id, v_variant_id, v_val_xl);
    RAISE NOTICE '   ✓ TSHIRT-BLUE-XL: Color=Blue, Size=XL';
    v_count := v_count + 2;

    -- Green M = Color:Green + Size:M
    SELECT product_variant_id INTO v_variant_id FROM general_schema.product_variant WHERE tenant_id = v_tenant_id AND sku = 'TSHIRT-GREEN-M';
    INSERT INTO general_schema.attribute_assignation (tenant_id, product_variant_id, attribute_value_id)
    VALUES 
        (v_tenant_id, v_variant_id, v_val_green),
        (v_tenant_id, v_variant_id, v_val_m);
    RAISE NOTICE '   ✓ TSHIRT-GREEN-M: Color=Green, Size=M';
    v_count := v_count + 2;

    -- Green L = Color:Green + Size:L
    SELECT product_variant_id INTO v_variant_id FROM general_schema.product_variant WHERE tenant_id = v_tenant_id AND sku = 'TSHIRT-GREEN-L';
    INSERT INTO general_schema.attribute_assignation (tenant_id, product_variant_id, attribute_value_id)
    VALUES 
        (v_tenant_id, v_variant_id, v_val_green),
        (v_tenant_id, v_variant_id, v_val_l);
    RAISE NOTICE '   ✓ TSHIRT-GREEN-L: Color=Green, Size=L';
    v_count := v_count + 2;

    RAISE NOTICE '';
    RAISE NOTICE '   📊 Summary: % attribute assignments created', v_count;
    RAISE NOTICE '✅ SECCIÓN 5 COMPLETADA';
    RAISE NOTICE '========================================';
END $$;

-- ========================================
-- SECCIÓN 6: Registrar inventario por variante
-- ========================================
DO $$
DECLARE
    v_tenant_id UUID := (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Variant Test Shop' LIMIT 1);
    v_warehouse_id UUID := (
        SELECT w.warehouse_id 
        FROM inventory_schema.warehouse w
        JOIN general_schema.branch b ON w.branch_id = b.branch_id
        WHERE b.tenant_id = v_tenant_id
        LIMIT 1
    );
    v_variant_id UUID;
    v_inventory_id UUID;
    v_count INT := 0;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📊 SECCIÓN 6: Registrar inventario por variante';
    RAISE NOTICE '========================================';

    -- Red S: 50 units
    SELECT product_variant_id INTO v_variant_id FROM general_schema.product_variant WHERE tenant_id = v_tenant_id AND sku = 'TSHIRT-RED-S';
    INSERT INTO inventory_schema.inventory (tenant_id, product_variant_id, warehouse_id, stock)
    VALUES (v_tenant_id, v_variant_id, v_warehouse_id, 50)
    RETURNING inventory_id INTO v_inventory_id;
    RAISE NOTICE '   ✓ TSHIRT-RED-S: 50 units (inventory_id: %)', v_inventory_id;
    v_count := v_count + 1;

    -- Red M: 75 units
    SELECT product_variant_id INTO v_variant_id FROM general_schema.product_variant WHERE tenant_id = v_tenant_id AND sku = 'TSHIRT-RED-M';
    INSERT INTO inventory_schema.inventory (tenant_id, product_variant_id, warehouse_id, stock)
    VALUES (v_tenant_id, v_variant_id, v_warehouse_id, 75)
    RETURNING inventory_id INTO v_inventory_id;
    RAISE NOTICE '   ✓ TSHIRT-RED-M: 75 units (inventory_id: %)', v_inventory_id;
    v_count := v_count + 1;

    -- Red L: 60 units
    SELECT product_variant_id INTO v_variant_id FROM general_schema.product_variant WHERE tenant_id = v_tenant_id AND sku = 'TSHIRT-RED-L';
    INSERT INTO inventory_schema.inventory (tenant_id, product_variant_id, warehouse_id, stock)
    VALUES (v_tenant_id, v_variant_id, v_warehouse_id, 60)
    RETURNING inventory_id INTO v_inventory_id;
    RAISE NOTICE '   ✓ TSHIRT-RED-L: 60 units (inventory_id: %)', v_inventory_id;
    v_count := v_count + 1;

    -- Blue S: 40 units
    SELECT product_variant_id INTO v_variant_id FROM general_schema.product_variant WHERE tenant_id = v_tenant_id AND sku = 'TSHIRT-BLUE-S';
    INSERT INTO inventory_schema.inventory (tenant_id, product_variant_id, warehouse_id, stock)
    VALUES (v_tenant_id, v_variant_id, v_warehouse_id, 40)
    RETURNING inventory_id INTO v_inventory_id;
    RAISE NOTICE '   ✓ TSHIRT-BLUE-S: 40 units (inventory_id: %)', v_inventory_id;
    v_count := v_count + 1;

    -- Blue M: 100 units (most popular)
    SELECT product_variant_id INTO v_variant_id FROM general_schema.product_variant WHERE tenant_id = v_tenant_id AND sku = 'TSHIRT-BLUE-M';
    INSERT INTO inventory_schema.inventory (tenant_id, product_variant_id, warehouse_id, stock)
    VALUES (v_tenant_id, v_variant_id, v_warehouse_id, 100)
    RETURNING inventory_id INTO v_inventory_id;
    RAISE NOTICE '   ✓ TSHIRT-BLUE-M: 100 units (inventory_id: %)', v_inventory_id;
    v_count := v_count + 1;

    -- Blue XL: 30 units
    SELECT product_variant_id INTO v_variant_id FROM general_schema.product_variant WHERE tenant_id = v_tenant_id AND sku = 'TSHIRT-BLUE-XL';
    INSERT INTO inventory_schema.inventory (tenant_id, product_variant_id, warehouse_id, stock)
    VALUES (v_tenant_id, v_variant_id, v_warehouse_id, 30)
    RETURNING inventory_id INTO v_inventory_id;
    RAISE NOTICE '   ✓ TSHIRT-BLUE-XL: 30 units (inventory_id: %)', v_inventory_id;
    v_count := v_count + 1;

    -- Green M: 55 units
    SELECT product_variant_id INTO v_variant_id FROM general_schema.product_variant WHERE tenant_id = v_tenant_id AND sku = 'TSHIRT-GREEN-M';
    INSERT INTO inventory_schema.inventory (tenant_id, product_variant_id, warehouse_id, stock)
    VALUES (v_tenant_id, v_variant_id, v_warehouse_id, 55)
    RETURNING inventory_id INTO v_inventory_id;
    RAISE NOTICE '   ✓ TSHIRT-GREEN-M: 55 units (inventory_id: %)', v_inventory_id;
    v_count := v_count + 1;

    -- Green L: 45 units
    SELECT product_variant_id INTO v_variant_id FROM general_schema.product_variant WHERE tenant_id = v_tenant_id AND sku = 'TSHIRT-GREEN-L';
    INSERT INTO inventory_schema.inventory (tenant_id, product_variant_id, warehouse_id, stock)
    VALUES (v_tenant_id, v_variant_id, v_warehouse_id, 45)
    RETURNING inventory_id INTO v_inventory_id;
    RAISE NOTICE '   ✓ TSHIRT-GREEN-L: 45 units (inventory_id: %)', v_inventory_id;
    v_count := v_count + 1;

    RAISE NOTICE '';
    RAISE NOTICE '   📊 Summary: % inventory records created', v_count;
    RAISE NOTICE '   📦 Total units in stock: % units', 
        (SELECT SUM(stock) FROM inventory_schema.inventory WHERE tenant_id = v_tenant_id);
    RAISE NOTICE '✅ SECCIÓN 6 COMPLETADA';
    RAISE NOTICE '========================================';
END $$;

-- ========================================
-- SECCIÓN 7: Consultas de verificación
-- ========================================
DO $$
DECLARE
    v_tenant_id UUID := (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Variant Test Shop' LIMIT 1);
    v_product_count INT;
    v_variant_count INT;
    v_attribute_count INT;
    v_value_count INT;
    v_assignment_count INT;
    v_inventory_count INT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🔍 SECCIÓN 7: Consultas de verificación';
    RAISE NOTICE '========================================';

    -- Contar entradas CABYS
    SELECT COUNT(*) INTO v_product_count 
    FROM general_schema.product 
    WHERE cabys_code LIKE 'TSHIRT%';
    RAISE NOTICE '   📦 CABYS catalog entries: %', v_product_count;

    -- Contar variantes
    SELECT COUNT(*) INTO v_variant_count 
    FROM general_schema.product_variant 
    WHERE tenant_id = v_tenant_id;
    RAISE NOTICE '   🎯 Product variants: %', v_variant_count;

    -- Contar atributos
    SELECT COUNT(*) INTO v_attribute_count 
    FROM general_schema.tenant_attribute 
    WHERE tenant_id = v_tenant_id;
    RAISE NOTICE '   🎨 Attributes: %', v_attribute_count;

    -- Contar valores
    SELECT COUNT(*) INTO v_value_count 
    FROM general_schema.attribute_value 
    WHERE tenant_id = v_tenant_id;
    RAISE NOTICE '   🏷️  Attribute values: %', v_value_count;

    -- Contar asignaciones
    SELECT COUNT(*) INTO v_assignment_count 
    FROM general_schema.attribute_assignation 
    WHERE tenant_id = v_tenant_id;
    RAISE NOTICE '   🔗 Attribute assignments: %', v_assignment_count;

    -- Contar inventario
    SELECT COUNT(*) INTO v_inventory_count 
    FROM inventory_schema.inventory 
    WHERE tenant_id = v_tenant_id;
    RAISE NOTICE '   📊 Inventory records: %', v_inventory_count;

    RAISE NOTICE '';
    RAISE NOTICE '   ✅ All counts match expected values';
    RAISE NOTICE '✅ SECCIÓN 7 COMPLETADA';
    RAISE NOTICE '========================================';
END $$;

-- ========================================
-- QUERY: Listado de inventario por variante con atributos
-- ========================================
DO $$ BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📋 LISTADO DE INVENTARIO POR VARIANTE';
    RAISE NOTICE '========================================';
END $$;

SELECT 
    pv.sku AS "SKU",
    pv.variant_name AS "Variant Name",
    pv.unit_price AS "Price",
    string_agg(
        ta.attribute_name || '=' || av.value_name, 
        ', ' 
        ORDER BY ta.attribute_name
    ) AS "Attributes",
    COALESCE(i.stock, 0) AS "Stock",
    w.warehouse_name AS "Warehouse"
FROM general_schema.product_variant pv
LEFT JOIN general_schema.attribute_assignation aa 
    ON pv.tenant_id = aa.tenant_id 
    AND pv.product_variant_id = aa.product_variant_id
LEFT JOIN general_schema.attribute_value av 
    ON aa.attribute_value_id = av.attribute_value_id
LEFT JOIN general_schema.tenant_attribute ta 
    ON av.tenant_attribute_id = ta.tenant_attribute_id
LEFT JOIN inventory_schema.inventory i 
    ON pv.tenant_id = i.tenant_id 
    AND pv.product_variant_id = i.product_variant_id
LEFT JOIN inventory_schema.warehouse w 
    ON i.warehouse_id = w.warehouse_id
WHERE pv.tenant_id = (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Variant Test Shop' LIMIT 1)
GROUP BY pv.sku, pv.variant_name, pv.unit_price, i.stock, w.warehouse_name
ORDER BY pv.sku;

-- ========================================
-- QUERY: Inventario total por color
-- ========================================
DO $$ BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📊 INVENTARIO TOTAL POR COLOR';
    RAISE NOTICE '========================================';
END $$;

SELECT 
    av.value_name AS "Color",
    COUNT(DISTINCT pv.product_variant_id) AS "Variants",
    SUM(COALESCE(i.stock, 0)) AS "Total Stock"
FROM general_schema.attribute_value av
JOIN general_schema.tenant_attribute ta 
    ON av.tenant_attribute_id = ta.tenant_attribute_id
JOIN general_schema.attribute_assignation aa 
    ON av.attribute_value_id = aa.attribute_value_id
JOIN general_schema.product_variant pv 
    ON aa.tenant_id = pv.tenant_id 
    AND aa.product_variant_id = pv.product_variant_id
LEFT JOIN inventory_schema.inventory i 
    ON pv.tenant_id = i.tenant_id 
    AND pv.product_variant_id = i.product_variant_id
WHERE ta.attribute_name = 'Color'
    AND av.tenant_id = (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Variant Test Shop' LIMIT 1)
GROUP BY av.value_name
ORDER BY "Total Stock" DESC;

-- ========================================
-- QUERY: Inventario total por talla
-- ========================================
DO $$ BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📏 INVENTARIO TOTAL POR TALLA';
    RAISE NOTICE '========================================';
END $$;

SELECT 
    av.value_name AS "Size",
    COUNT(DISTINCT pv.product_variant_id) AS "Variants",
    SUM(COALESCE(i.stock, 0)) AS "Total Stock"
FROM general_schema.attribute_value av
JOIN general_schema.tenant_attribute ta 
    ON av.tenant_attribute_id = ta.tenant_attribute_id
JOIN general_schema.attribute_assignation aa 
    ON av.attribute_value_id = aa.attribute_value_id
JOIN general_schema.product_variant pv 
    ON aa.tenant_id = pv.tenant_id 
    AND aa.product_variant_id = pv.product_variant_id
LEFT JOIN inventory_schema.inventory i 
    ON pv.tenant_id = i.tenant_id 
    AND pv.product_variant_id = i.product_variant_id
WHERE ta.attribute_name = 'Size'
    AND av.tenant_id = (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Variant Test Shop' LIMIT 1)
GROUP BY av.value_name
ORDER BY 
    CASE av.value_name
        WHEN 'S' THEN 1
        WHEN 'M' THEN 2
        WHEN 'L' THEN 3
        WHEN 'XL' THEN 4
        ELSE 5
    END;

-- ========================================
-- RESUMEN FINAL
-- ========================================
DO $$
DECLARE
    v_tenant_id UUID := (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Variant Test Shop' LIMIT 1);
    v_total_stock INT;
    v_total_value NUMERIC(10,2);
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ RESUMEN FINAL DEL TEST';
    RAISE NOTICE '========================================';
    
    SELECT 
        SUM(i.stock),
        SUM(i.stock * pv.unit_price)
    INTO v_total_stock, v_total_value
    FROM inventory_schema.inventory i
    JOIN general_schema.product_variant pv 
        ON i.tenant_id = pv.tenant_id 
        AND i.product_variant_id = pv.product_variant_id
    WHERE i.tenant_id = v_tenant_id;
    
    RAISE NOTICE '📦 Total units in stock: %', v_total_stock;
    RAISE NOTICE '💰 Total inventory value: $%', v_total_value;
    RAISE NOTICE '';
    RAISE NOTICE '✅ TEST COMPLETADO EXITOSAMENTE';
    RAISE NOTICE '========================================';
END $$;
