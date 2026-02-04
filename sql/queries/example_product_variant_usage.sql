-- ============================================================================
-- EXAMPLE: Product Variant Model Usage
-- Demonstrates how to create products with variants and attributes
-- ============================================================================

DO $$
DECLARE
    v_tenant_id UUID;
    v_product_id UUID;
    v_variant_id_red_s UUID;
    v_variant_id_red_m UUID;
    v_variant_id_blue_s UUID;
    v_variant_id_blue_m UUID;
    v_attr_color UUID;
    v_attr_size UUID;
    v_val_red UUID;
    v_val_blue UUID;
    v_val_s UUID;
    v_val_m UUID;
BEGIN
    -- Get an existing tenant for demo
    SELECT tenant_id INTO v_tenant_id 
    FROM general_schema.tenant 
    LIMIT 1;
    
    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'No tenant found. Create a tenant first.';
    END IF;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'PRODUCT VARIANT MODEL - EXAMPLE';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Tenant: %', v_tenant_id;
    RAISE NOTICE '';

    -- =============================================
    -- STEP 1: Create Base Product
    -- =============================================
    RAISE NOTICE '1. Creating base product...';
    
    INSERT INTO general_schema.product (
        tenant_id,
        sku,
        product_name,
        product_description,
        unit_price
    ) VALUES (
        v_tenant_id,
        'SHIRT-BASE',
        'Cotton T-Shirt',
        'Premium cotton t-shirt available in multiple colors and sizes',
        25.00
    )
    ON CONFLICT (tenant_id, sku) DO UPDATE 
    SET product_name = EXCLUDED.product_name
    RETURNING product_id INTO v_product_id;
    
    RAISE NOTICE '   ✓ Base product created: %', v_product_id;
    RAISE NOTICE '';

    -- =============================================
    -- STEP 2: Create/Get Tenant Attributes (using global templates)
    -- =============================================
    RAISE NOTICE '2. Setting up attributes...';
    
    -- Get or create Color attribute
    INSERT INTO general_schema.tenant_attribute (
        tenant_id,
        attribute_name,
        is_custom
    ) VALUES (
        v_tenant_id,
        'Color',
        TRUE  -- Custom attribute (no global template)
    )
    ON CONFLICT (tenant_id, lower(attribute_name)) DO NOTHING;
    
    SELECT tenant_attribute_id INTO v_attr_color
    FROM general_schema.tenant_attribute
    WHERE tenant_id = v_tenant_id AND lower(attribute_name) = 'color';
    
    -- Get or create Size attribute
    INSERT INTO general_schema.tenant_attribute (
        tenant_id,
        attribute_name,
        is_custom
    ) VALUES (
        v_tenant_id,
        'Size',
        TRUE
    )
    ON CONFLICT (tenant_id, lower(attribute_name)) DO NOTHING;
    
    SELECT tenant_attribute_id INTO v_attr_size
    FROM general_schema.tenant_attribute
    WHERE tenant_id = v_tenant_id AND lower(attribute_name) = 'size';
    
    RAISE NOTICE '   ✓ Color attribute: %', v_attr_color;
    RAISE NOTICE '   ✓ Size attribute: %', v_attr_size;
    RAISE NOTICE '';

    -- =============================================
    -- STEP 3: Create Attribute Values
    -- =============================================
    RAISE NOTICE '3. Creating attribute values...';
    
    -- Color values
    INSERT INTO general_schema.attribute_value (tenant_id, tenant_attribute_id, value_name)
    VALUES (v_tenant_id, v_attr_color, 'Red')
    ON CONFLICT (tenant_id, tenant_attribute_id, lower(value_name)) DO NOTHING;
    
    SELECT attribute_value_id INTO v_val_red
    FROM general_schema.attribute_value
    WHERE tenant_id = v_tenant_id AND tenant_attribute_id = v_attr_color AND lower(value_name) = 'red';
    
    INSERT INTO general_schema.attribute_value (tenant_id, tenant_attribute_id, value_name)
    VALUES (v_tenant_id, v_attr_color, 'Blue')
    ON CONFLICT (tenant_id, tenant_attribute_id, lower(value_name)) DO NOTHING;
    
    SELECT attribute_value_id INTO v_val_blue
    FROM general_schema.attribute_value
    WHERE tenant_id = v_tenant_id AND tenant_attribute_id = v_attr_color AND lower(value_name) = 'blue';
    
    -- Size values
    INSERT INTO general_schema.attribute_value (tenant_id, tenant_attribute_id, value_name)
    VALUES (v_tenant_id, v_attr_size, 'S')
    ON CONFLICT (tenant_id, tenant_attribute_id, lower(value_name)) DO NOTHING;
    
    SELECT attribute_value_id INTO v_val_s
    FROM general_schema.attribute_value
    WHERE tenant_id = v_tenant_id AND tenant_attribute_id = v_attr_size AND lower(value_name) = 's';
    
    INSERT INTO general_schema.attribute_value (tenant_id, tenant_attribute_id, value_name)
    VALUES (v_tenant_id, v_attr_size, 'M')
    ON CONFLICT (tenant_id, tenant_attribute_id, lower(value_name)) DO NOTHING;
    
    SELECT attribute_value_id INTO v_val_m
    FROM general_schema.attribute_value
    WHERE tenant_id = v_tenant_id AND tenant_attribute_id = v_attr_size AND lower(value_name) = 'm';
    
    RAISE NOTICE '   ✓ Red: %', v_val_red;
    RAISE NOTICE '   ✓ Blue: %', v_val_blue;
    RAISE NOTICE '   ✓ S: %', v_val_s;
    RAISE NOTICE '   ✓ M: %', v_val_m;
    RAISE NOTICE '';

    -- =============================================
    -- STEP 4: Create Product Variants (sellable SKUs)
    -- =============================================
    RAISE NOTICE '4. Creating product variants...';
    
    -- Red S
    INSERT INTO general_schema.product_variant (
        tenant_id, product_id, sku, variant_name, unit_price, is_active
    ) VALUES (
        v_tenant_id, v_product_id, 'SHIRT-RED-S', 'Cotton T-Shirt - Red/S', 25.00, TRUE
    )
    ON CONFLICT (tenant_id, sku) DO UPDATE SET variant_name = EXCLUDED.variant_name
    RETURNING product_variant_id INTO v_variant_id_red_s;
    
    -- Red M
    INSERT INTO general_schema.product_variant (
        tenant_id, product_id, sku, variant_name, unit_price, is_active
    ) VALUES (
        v_tenant_id, v_product_id, 'SHIRT-RED-M', 'Cotton T-Shirt - Red/M', 25.00, TRUE
    )
    ON CONFLICT (tenant_id, sku) DO UPDATE SET variant_name = EXCLUDED.variant_name
    RETURNING product_variant_id INTO v_variant_id_red_m;
    
    -- Blue S
    INSERT INTO general_schema.product_variant (
        tenant_id, product_id, sku, variant_name, unit_price, is_active
    ) VALUES (
        v_tenant_id, v_product_id, 'SHIRT-BLUE-S', 'Cotton T-Shirt - Blue/S', 25.00, TRUE
    )
    ON CONFLICT (tenant_id, sku) DO UPDATE SET variant_name = EXCLUDED.variant_name
    RETURNING product_variant_id INTO v_variant_id_blue_s;
    
    -- Blue M
    INSERT INTO general_schema.product_variant (
        tenant_id, product_id, sku, variant_name, unit_price, is_active
    ) VALUES (
        v_tenant_id, v_product_id, 'SHIRT-BLUE-M', 'Cotton T-Shirt - Blue/M', 27.00, TRUE  -- Slightly higher price for M
    )
    ON CONFLICT (tenant_id, sku) DO UPDATE SET variant_name = EXCLUDED.variant_name
    RETURNING product_variant_id INTO v_variant_id_blue_m;
    
    RAISE NOTICE '   ✓ SHIRT-RED-S: %', v_variant_id_red_s;
    RAISE NOTICE '   ✓ SHIRT-RED-M: %', v_variant_id_red_m;
    RAISE NOTICE '   ✓ SHIRT-BLUE-S: %', v_variant_id_blue_s;
    RAISE NOTICE '   ✓ SHIRT-BLUE-M: %', v_variant_id_blue_m;
    RAISE NOTICE '';

    -- =============================================
    -- STEP 5: Assign Attributes to Variants
    -- =============================================
    RAISE NOTICE '5. Assigning attributes to variants...';
    
    -- Red S = Color:Red + Size:S
    INSERT INTO general_schema.attribute_assignation (tenant_id, product_variant_id, attribute_value_id)
    VALUES 
        (v_tenant_id, v_variant_id_red_s, v_val_red),
        (v_tenant_id, v_variant_id_red_s, v_val_s)
    ON CONFLICT DO NOTHING;
    
    -- Red M = Color:Red + Size:M
    INSERT INTO general_schema.attribute_assignation (tenant_id, product_variant_id, attribute_value_id)
    VALUES 
        (v_tenant_id, v_variant_id_red_m, v_val_red),
        (v_tenant_id, v_variant_id_red_m, v_val_m)
    ON CONFLICT DO NOTHING;
    
    -- Blue S = Color:Blue + Size:S
    INSERT INTO general_schema.attribute_assignation (tenant_id, product_variant_id, attribute_value_id)
    VALUES 
        (v_tenant_id, v_variant_id_blue_s, v_val_blue),
        (v_tenant_id, v_variant_id_blue_s, v_val_s)
    ON CONFLICT DO NOTHING;
    
    -- Blue M = Color:Blue + Size:M
    INSERT INTO general_schema.attribute_assignation (tenant_id, product_variant_id, attribute_value_id)
    VALUES 
        (v_tenant_id, v_variant_id_blue_m, v_val_blue),
        (v_tenant_id, v_variant_id_blue_m, v_val_m)
    ON CONFLICT DO NOTHING;
    
    RAISE NOTICE '   ✓ All attribute assignments completed';
    RAISE NOTICE '';

    -- =============================================
    -- STEP 6: Query Example - Get all variants with attributes
    -- =============================================
    RAISE NOTICE '6. Query: Get all variants with their attributes';
    RAISE NOTICE '';
    
    RAISE NOTICE 'SKU            | Name                        | Price  | Attributes';
    RAISE NOTICE '---------------|-----------------------------| -------|------------------';
    
END;
$$ LANGUAGE plpgsql;

-- =============================================
-- QUERY: List all variants with their attributes
-- =============================================
SELECT 
    pv.sku,
    pv.variant_name,
    pv.unit_price,
    string_agg(ta.attribute_name || ': ' || av.value_name, ', ' ORDER BY ta.attribute_name) AS attributes
FROM general_schema.product_variant pv
LEFT JOIN general_schema.attribute_assignation aa 
    ON pv.tenant_id = aa.tenant_id AND pv.product_variant_id = aa.product_variant_id
LEFT JOIN general_schema.attribute_value av 
    ON aa.attribute_value_id = av.attribute_value_id
LEFT JOIN general_schema.tenant_attribute ta 
    ON av.tenant_attribute_id = ta.tenant_attribute_id
WHERE pv.sku LIKE 'SHIRT-%'
GROUP BY pv.sku, pv.variant_name, pv.unit_price
ORDER BY pv.sku;

-- =============================================
-- QUERY: Find all variants by attribute value (e.g., all "Red" items)
-- =============================================
-- SELECT 
--     pv.sku,
--     pv.variant_name,
--     pv.unit_price
-- FROM general_schema.product_variant pv
-- JOIN general_schema.attribute_assignation aa 
--     ON pv.tenant_id = aa.tenant_id AND pv.product_variant_id = aa.product_variant_id
-- JOIN general_schema.attribute_value av 
--     ON aa.attribute_value_id = av.attribute_value_id
-- WHERE av.value_name = 'Red'
-- ORDER BY pv.sku;

-- =============================================
-- QUERY: Get base product with all its variants
-- =============================================
-- SELECT 
--     p.product_name AS base_product,
--     p.sku AS base_sku,
--     COUNT(pv.product_variant_id) AS variant_count,
--     array_agg(pv.sku ORDER BY pv.sku) AS variant_skus
-- FROM general_schema.product p
-- LEFT JOIN general_schema.product_variant pv 
--     ON p.tenant_id = pv.tenant_id AND p.product_id = pv.product_id
-- WHERE p.sku = 'SHIRT-BASE'
-- GROUP BY p.product_id, p.product_name, p.sku;
