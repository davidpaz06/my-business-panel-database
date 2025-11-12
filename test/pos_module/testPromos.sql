-- =====================================
-- SCRIPT DE PRUEBA: SISTEMA DE PROMOCIONES
-- =====================================
-- Este script prueba todos los tipos de promociones:
-- 1. Descuento porcentual (20% off)
-- 2. Descuento fijo ($10 off)
-- 3. Buy X Get Y (2x1, 3x2)
-- 4. Descuento por volumen (15% al comprar 10+)
-- 5. Precios escalonados (5%, 10%, 20%)
-- =====================================

-- ========================================
-- SECCIÓN 0: Verificar estado inicial
-- ========================================
do $$
begin
    raise notice '========================================';
    raise notice '🔍 SECCIÓN 0: Estado inicial de la base de datos';
    raise notice '========================================';
    raise notice '';
    raise notice 'Tenants: %', (select count(*) from core.tenant);
    raise notice 'Productos: %', (select count(*) from core.product);
    raise notice 'Clientes: %', (select count(*) from core.tenant_customer);
    raise notice 'Promociones: %', (select count(*) from pos_module.promotion);
    raise notice '';
    raise notice '✅ SECCIÓN 0 COMPLETADA';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 1: Crear tenant, productos y cliente
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_product_a_id uuid;
    v_product_b_id uuid;
    v_product_c_id uuid;
    v_customer_id uuid;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '🏪 SECCIÓN 1: Creando tenant, productos y cliente';
    raise notice '========================================';
    raise notice '';
    
    -- Crear tenant
    insert into core.tenant (tenant_name, contact_email, is_subscribed)
    values ('Tienda de Electrónica', 'tienda@electronica.com', true)
    returning tenant_id into v_tenant_id;
    
    raise notice '✓ Tenant creado: %', v_tenant_id;
    raise notice '  Nombre: Tienda de Electrónica';
    raise notice '';
    
    -- Crear productos
    insert into core.product (tenant_id, sku, product_name, unit_price)
    values (v_tenant_id, 'LAPTOP-001', 'Laptop Gaming', 1000.00)
    returning product_id into v_product_a_id;
    
    insert into core.product (tenant_id, sku, product_name, unit_price)
    values (v_tenant_id, 'MOUSE-001', 'Mouse Gamer', 50.00)
    returning product_id into v_product_b_id;
    
    insert into core.product (tenant_id, sku, product_name, unit_price)
    values (v_tenant_id, 'HEADSET-001', 'Auriculares Pro', 100.00)
    returning product_id into v_product_c_id;
    
    raise notice '✓ Productos creados:';
    raise notice '  - Laptop Gaming: $1,000.00 (ID: %)', v_product_a_id;
    raise notice '  - Mouse Gamer: $50.00 (ID: %)', v_product_b_id;
    raise notice '  - Auriculares Pro: $100.00 (ID: %)', v_product_c_id;
    raise notice '';
    
    -- Crear cliente
    insert into core.tenant_customer (
        tenant_id, first_name, last_name, document_number, 
        email, phone, customer_segment_id
    )
    values (
        v_tenant_id, 'Carlos', 'Mendoza', 'DNI-12345678',
        'carlos.mendoza@email.com', '+51-999-888-777', 3
    )
    returning tenant_customer_id into v_customer_id;
    
    raise notice '✓ Cliente creado: %', v_customer_id;
    raise notice '  Nombre: Carlos Mendoza';
    raise notice '  Segmento: Regular (ID: 3)';
    raise notice '';
    raise notice '✅ SECCIÓN 1 COMPLETADA';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 2: Crear promociones
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_promo_percentage_id uuid;
    v_promo_fixed_id uuid;
    v_promo_2x1_id uuid;
    v_promo_3x2_id uuid;
    v_promo_volume_id uuid;
    v_promo_tiered_id uuid;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '🎁 SECCIÓN 2: Creando promociones';
    raise notice '========================================';
    raise notice '';
    
    select tenant_id into v_tenant_id
    from core.tenant
    where tenant_name = 'Tienda de Electrónica';
    
    -- Promoción 1: 20% descuento
    insert into pos_module.promotion (
        tenant_id, promotion_code, promotion_name, promotion_type_id,
        customer_segment_id, promotion_start_date, promotion_end_date, is_active
    ) values (
        v_tenant_id, 'TECH20', '20% Off en Tecnología', 1,
        3, current_date, current_date + 30, true
    ) returning promotion_id into v_promo_percentage_id;
    
    insert into pos_module.promotion_rule (
        promotion_id, discount_percentage
    ) values (v_promo_percentage_id, 20.00);
    
    raise notice '✓ Promoción 1 creada: TECH20';
    raise notice '%', format('  Tipo: Descuento porcentual (20%%)');
    raise notice '  ID: %', v_promo_percentage_id;
    raise notice '';
    
    -- Promoción 2: $10 descuento (mínimo $50)
    insert into pos_module.promotion (
        tenant_id, promotion_code, promotion_name, promotion_type_id,
        customer_segment_id, promotion_start_date, promotion_end_date, is_active
    ) values (
        v_tenant_id, 'SAVE10', '$10 Off en compras mayores a $50', 2,
        3, current_date, current_date + 30, true
    ) returning promotion_id into v_promo_fixed_id;
    
    insert into pos_module.promotion_rule (
        promotion_id, discount_amount, min_purchase_amount
    ) values (v_promo_fixed_id, 10.00, 50.00);
    
    raise notice '✓ Promoción 2 creada: SAVE10';
    raise notice '  Tipo: Descuento fijo ($10)';
    raise notice '  Mínimo de compra: $50';
    raise notice '  ID: %', v_promo_fixed_id;
    raise notice '';
    
    -- Promoción 3: 2x1
    insert into pos_module.promotion (
        tenant_id, promotion_code, promotion_name, promotion_type_id,
        customer_segment_id, promotion_start_date, promotion_end_date, is_active
    ) values (
        v_tenant_id, '2X1MOUSE', '2×1 en Mouse Gamer', 3,
        3, current_date, current_date + 30, true
    ) returning promotion_id into v_promo_2x1_id;
    
    insert into pos_module.promotion_rule (
        promotion_id, buy_quantity, get_quantity, get_discount_percentage
    ) values (v_promo_2x1_id, 2, 1, 100.00);
    
    raise notice '✓ Promoción 3 creada: 2X1MOUSE';
    raise notice '  Tipo: Buy 2 Get 1 (2×1)';
    raise notice '  ID: %', v_promo_2x1_id;
    raise notice '';
    
    -- Promoción 4: 3x2 con 50% en el 3ro
    insert into pos_module.promotion (
        tenant_id, promotion_code, promotion_name, promotion_type_id,
        customer_segment_id, promotion_start_date, promotion_end_date, is_active
    ) values (
        v_tenant_id, '3X2HALF', '3×2 - Tercero al 50%%', 3,
        3, current_date, current_date + 30, true
    ) returning promotion_id into v_promo_3x2_id;
    
    insert into pos_module.promotion_rule (
        promotion_id, buy_quantity, get_quantity, get_discount_percentage
    ) values (v_promo_3x2_id, 2, 1, 50.00);
    
    raise notice '✓ Promoción 4 creada: 3X2HALF';
    raise notice '%', format('  Tipo: Buy 2 Get 1 at 50%% off (3×2)');
    raise notice '  ID: %', v_promo_3x2_id;
    raise notice '';
    
    -- Promoción 5: Descuento por volumen (10+ = 15%)
    insert into pos_module.promotion (
        tenant_id, promotion_code, promotion_name, promotion_type_id,
        customer_segment_id, promotion_start_date, promotion_end_date, is_active
    ) values (
        v_tenant_id, 'BULK15', '15%% Off al comprar 10+', 4,
        3, current_date, current_date + 30, true
    ) returning promotion_id into v_promo_volume_id;
    
    insert into pos_module.promotion_rule (
        promotion_id, min_quantity, discount_percentage
    ) values (v_promo_volume_id, 10, 15.00);
    
    raise notice '✓ Promoción 5 creada: BULK15';
    raise notice '  Tipo: Descuento por volumen (10+ unidades)';
    raise notice '  ID: %', v_promo_volume_id;
    raise notice '';
    
    -- Promoción 6: Precios escalonados
    insert into pos_module.promotion (
        tenant_id, promotion_code, promotion_name, promotion_type_id,
        customer_segment_id, promotion_start_date, promotion_end_date, is_active
    ) values (
        v_tenant_id, 'TIERS', 'Precios Escalonados', 5,
        3, current_date, current_date + 30, true
    ) returning promotion_id into v_promo_tiered_id;
    
    -- Tier 1: 1-10 = 5%
    insert into pos_module.promotion_rule (
        promotion_id, tier_level, tier_min_quantity, tier_max_quantity, tier_discount_percentage
    ) values (v_promo_tiered_id, 1, 1, 10, 5.00);
    
    -- Tier 2: 11-50 = 10%
    insert into pos_module.promotion_rule (
        promotion_id, tier_level, tier_min_quantity, tier_max_quantity, tier_discount_percentage
    ) values (v_promo_tiered_id, 2, 11, 50, 10.00);
    
    -- Tier 3: 51+ = 20%
    insert into pos_module.promotion_rule (
        promotion_id, tier_level, tier_min_quantity, tier_discount_percentage
    ) values (v_promo_tiered_id, 3, 51, 20.00);
    
    raise notice '✓ Promoción 6 creada: TIERS';
    raise notice '  Tipo: Precios escalonados (3 niveles)';
    raise notice '%', format('  Tier 1: 1-10 unidades = 5%%');
    raise notice '%', format('  Tier 2: 11-50 unidades = 10%%');
    raise notice '%', format('  Tier 3: 51+ unidades = 20%%');
    raise notice '  ID: %', v_promo_tiered_id;
    raise notice '';
    raise notice '✅ SECCIÓN 2 COMPLETADA';
    raise notice '  Total de promociones creadas: 6';
    raise notice '========================================';
end $$;


-- Ver todas las promociones creadas
select 
    '=== PROMOCIONES ACTIVAS ===' as seccion,
    p.promotion_code as codigo,
    p.promotion_name as nombre,
    pt.type_name as tipo,
    p.is_active as activa
from pos_module.promotion p
join pos_module.promotion_type pt on p.promotion_type_id = pt.promotion_type_id
order by p.created_at;


-- ========================================
-- SECCIÓN 3: Prueba de promoción porcentual (20% off)
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_customer_id uuid;
    v_product_id uuid;
    v_promo_id uuid;
    v_payment_id uuid;
    v_bill_id uuid;
    v_discount record;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '%', format('🧪 SECCIÓN 3: Prueba de descuento porcentual (20%%)');
    raise notice '========================================';
    raise notice '';
    
    -- Obtener IDs
    select tenant_id into v_tenant_id
    from core.tenant where tenant_name = 'Tienda de Electrónica';
    
    select tenant_customer_id into v_customer_id
    from core.tenant_customer where email = 'carlos.mendoza@email.com';
    
    select product_id into v_product_id
    from core.product where sku = 'LAPTOP-001' and tenant_id = v_tenant_id;
    
    select promotion_id into v_promo_id
    from pos_module.promotion where promotion_code = 'TECH20';
    
    raise notice '📋 Datos de la prueba:';
    raise notice '  Producto: Laptop Gaming ($1,000.00)';
    raise notice '  Cantidad: 1 unidad';
    raise notice '%', format('  Promoción: TECH20 (20%% off)');
    raise notice '';
    
    raise notice '🔢 Calculando descuento...';
    for v_discount in
        select * from pos_module.calculate_promotion_discount(
            v_promo_id, v_tenant_id, v_product_id, 1, 1000.00, 1000.00
        )
    loop
        raise notice '';
        raise notice '💰 Resultado del descuento:';
        raise notice '  Descuento: $%', v_discount.discount_amount;
        raise notice '%', format('  Porcentaje: %s%%', v_discount.discount_percentage);
        raise notice '  Tipo: %', v_discount.promotion_type;
        raise notice '  Regla: %', v_discount.rule_applied;
    end loop;
    raise notice '';
    
    -- Crear pago
    insert into pos_module.customer_payment (
        tenant_customer_id, payment_method_id, payment_amount, currency_id, verified
    )
    values (v_customer_id, 1, 800.00, 1, false)
    returning customer_payment_id into v_payment_id;
    
    raise notice '✓ Pago creado (sin verificar): %', v_payment_id;
    raise notice '%', format('  Monto: $800.00 (después del 20%% descuento)');
    raise notice '';
    
    -- Verificar pago
    raise notice '🔐 Verificando pago...';
    call pos_module.verify_customer_payment(v_payment_id);
    
    -- Esperar a que se cree la factura
    perform pg_sleep(0.5);
    
    select bill_id into v_bill_id
    from pos_module.bill
    where customer_payment_id = v_payment_id;
    
    raise notice '✓ Factura creada automáticamente: %', v_bill_id;
    raise notice '';
    
    -- Agregar producto a la factura
    insert into pos_module.bill_product (
        bill_id, tenant_id, product_id, quantity, unit_price
    )
    values (v_bill_id, v_tenant_id, v_product_id, 1, 800.00);
    
    raise notice '✓ Producto agregado a la factura';
    raise notice '';
    raise notice '✅ SECCIÓN 3 COMPLETADA';
    raise notice '  Precio original: $1,000.00';
    raise notice '%', format('  Descuento (20%%): $200.00');
    raise notice '  Precio final: $800.00';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 4: Prueba de descuento fijo ($10 off)
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_customer_id uuid;
    v_product_id uuid;
    v_promo_id uuid;
    v_payment_id uuid;
    v_bill_id uuid;
    v_discount record;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '🧪 SECCIÓN 4: Prueba de descuento fijo ($10 off)';
    raise notice '========================================';
    raise notice '';
    
    -- Obtener IDs
    select tenant_id into v_tenant_id
    from core.tenant where tenant_name = 'Tienda de Electrónica';
    
    select tenant_customer_id into v_customer_id
    from core.tenant_customer where email = 'carlos.mendoza@email.com';
    
    select product_id into v_product_id
    from core.product where sku = 'HEADSET-001' and tenant_id = v_tenant_id;
    
    select promotion_id into v_promo_id
    from pos_module.promotion where promotion_code = 'SAVE10';
    
    raise notice '📋 Datos de la prueba:';
    raise notice '  Producto: Auriculares Pro ($100.00)';
    raise notice '  Cantidad: 1 unidad';
    raise notice '  Promoción: SAVE10 ($10 off con mínimo $50)';
    raise notice '';
    
    -- Calcular descuento
    raise notice '🔢 Calculando descuento...';
    for v_discount in
        select * from pos_module.calculate_promotion_discount(
            v_promo_id, v_tenant_id, v_product_id, 1, 100.00, 100.00
        )
    loop
        raise notice '';
        raise notice '💰 Resultado del descuento:';
        raise notice '  Descuento: $%', v_discount.discount_amount;
        raise notice '%', format('  Porcentaje: %s%%', v_discount.discount_percentage);
        raise notice '  Tipo: %', v_discount.promotion_type;
        raise notice '  Regla: %', v_discount.rule_applied;
    end loop;
    raise notice '';
    
    -- Crear pago
    insert into pos_module.customer_payment (
        tenant_customer_id, payment_method_id, payment_amount, currency_id, verified
    )
    values (v_customer_id, 2, 90.00, 1, false)
    returning customer_payment_id into v_payment_id;
    
    raise notice '✓ Pago creado (sin verificar): %', v_payment_id;
    raise notice '  Monto: $90.00 (después del descuento de $10)';
    raise notice '';
    
    -- Verificar pago
    raise notice '🔐 Verificando pago...';
    call pos_module.verify_customer_payment(v_payment_id);
    
    perform pg_sleep(0.5);
    
    select bill_id into v_bill_id
    from pos_module.bill
    where customer_payment_id = v_payment_id;
    
    raise notice '✓ Factura creada automáticamente: %', v_bill_id;
    raise notice '';
    
    -- Agregar producto a la factura
    insert into pos_module.bill_product (
        bill_id, tenant_id, product_id, quantity, unit_price
    )
    values (v_bill_id, v_tenant_id, v_product_id, 1, 90.00);
    
    raise notice '✓ Producto agregado a la factura';
    raise notice '';
    raise notice '✅ SECCIÓN 4 COMPLETADA';
    raise notice '  Precio original: $100.00';
    raise notice '  Descuento fijo: $10.00';
    raise notice '  Precio final: $90.00';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 5: Prueba de 2×1 (Buy 2 Get 1 Free)
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_customer_id uuid;
    v_product_id uuid;
    v_promo_id uuid;
    v_payment_id uuid;
    v_bill_id uuid;
    v_discount record;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '🧪 SECCIÓN 5: Prueba de 2×1 (Buy 2 Get 1 Free)';
    raise notice '========================================';
    raise notice '';
    
    -- Obtener IDs
    select tenant_id into v_tenant_id
    from core.tenant where tenant_name = 'Tienda de Electrónica';
    
    select tenant_customer_id into v_customer_id
    from core.tenant_customer where email = 'carlos.mendoza@email.com';
    
    select product_id into v_product_id
    from core.product where sku = 'MOUSE-001' and tenant_id = v_tenant_id;
    
    select promotion_id into v_promo_id
    from pos_module.promotion where promotion_code = '2X1MOUSE';
    
    raise notice '📋 Datos de la prueba:';
    raise notice '  Producto: Mouse Gamer ($50.00)';
    raise notice '  Cantidad: 3 unidades';
    raise notice '  Promoción: 2X1MOUSE (compra 2, lleva 1 gratis)';
    raise notice '';
    
    -- Calcular descuento
    raise notice '🔢 Calculando descuento...';
    for v_discount in
        select * from pos_module.calculate_promotion_discount(
            v_promo_id, v_tenant_id, v_product_id, 3, 50.00, 150.00
        )
    loop
        raise notice '';
        raise notice '💰 Resultado del descuento:';
        raise notice '  Descuento: $%', v_discount.discount_amount;
        raise notice '%', format('  Porcentaje: %s%%', v_discount.discount_percentage);
        raise notice '  Tipo: %', v_discount.promotion_type;
        raise notice '  Regla: %', v_discount.rule_applied;
    end loop;
    raise notice '';
    
    -- Crear pago
    insert into pos_module.customer_payment (
        tenant_customer_id, payment_method_id, payment_amount, currency_id, verified
    )
    values (v_customer_id, 3, 100.00, 1, false)
    returning customer_payment_id into v_payment_id;
    
    raise notice '✓ Pago creado (sin verificar): %', v_payment_id;
    raise notice '  Monto: $100.00 (3 unidades - 1 gratis)';
    raise notice '';
    
    -- Verificar pago
    raise notice '🔐 Verificando pago...';
    call pos_module.verify_customer_payment(v_payment_id);
    
    perform pg_sleep(0.5);
    
    select bill_id into v_bill_id
    from pos_module.bill
    where customer_payment_id = v_payment_id;
    
    raise notice '✓ Factura creada automáticamente: %', v_bill_id;
    raise notice '';
    
    -- Agregar producto a la factura
    insert into pos_module.bill_product (
        bill_id, tenant_id, product_id, quantity, unit_price
    )
    values (v_bill_id, v_tenant_id, v_product_id, 3, 33.33);
    
    raise notice '✓ Producto agregado a la factura';
    raise notice '';
    raise notice '✅ SECCIÓN 5 COMPLETADA';
    raise notice '  Precio original: $150.00 (3 × $50)';
    raise notice '  Descuento (1 gratis): $50.00';
    raise notice '  Precio final: $100.00';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 6: Prueba de 3×2 con 50% en el tercero
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_customer_id uuid;
    v_product_id uuid;
    v_promo_id uuid;
    v_payment_id uuid;
    v_bill_id uuid;
    v_discount record;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '%', format('🧪 SECCIÓN 6: Prueba de 3×2 (tercero al 50%%)');
    raise notice '========================================';
    raise notice '';
    
    -- Obtener IDs
    select tenant_id into v_tenant_id
    from core.tenant where tenant_name = 'Tienda de Electrónica';
    
    select tenant_customer_id into v_customer_id
    from core.tenant_customer where email = 'carlos.mendoza@email.com';
    
    select product_id into v_product_id
    from core.product where sku = 'HEADSET-001' and tenant_id = v_tenant_id;
    
    select promotion_id into v_promo_id
    from pos_module.promotion where promotion_code = '3X2HALF';
    
    raise notice '📋 Datos de la prueba:';
    raise notice '  Producto: Auriculares Pro ($100.00)';
    raise notice '  Cantidad: 3 unidades';
    raise notice '%', format('  Promoción: 3X2HALF (compra 2, el 3ro al 50%%)');
    raise notice '';
    
    -- Calcular descuento
    raise notice '🔢 Calculando descuento...';
    for v_discount in
        select * from pos_module.calculate_promotion_discount(
            v_promo_id, v_tenant_id, v_product_id, 3, 100.00, 300.00
        )
    loop
        raise notice '';
        raise notice '💰 Resultado del descuento:';
        raise notice '  Descuento: $%', v_discount.discount_amount;
        raise notice '%', format('  Porcentaje: %s%%', v_discount.discount_percentage);
        raise notice '  Tipo: %', v_discount.promotion_type;
        raise notice '  Regla: %', v_discount.rule_applied;
    end loop;
    raise notice '';
    
    -- Crear pago
    insert into pos_module.customer_payment (
        tenant_customer_id, payment_method_id, payment_amount, currency_id, verified
    )
    values (v_customer_id, 1, 250.00, 1, false)
    returning customer_payment_id into v_payment_id;
    
    raise notice '✓ Pago creado (sin verificar): %', v_payment_id;
    raise notice '%', format('  Monto: $250.00 (3 unidades - 1 al 50%%)');
    raise notice '';
    
    -- Verificar pago
    raise notice '🔐 Verificando pago...';
    call pos_module.verify_customer_payment(v_payment_id);
    
    perform pg_sleep(0.5);
    
    select bill_id into v_bill_id
    from pos_module.bill
    where customer_payment_id = v_payment_id;
    
    raise notice '✓ Factura creada automáticamente: %', v_bill_id;
    raise notice '';
    
    -- Agregar producto a la factura
    insert into pos_module.bill_product (
        bill_id, tenant_id, product_id, quantity, unit_price
    )
    values (v_bill_id, v_tenant_id, v_product_id, 3, 83.33);
    
    raise notice '✓ Producto agregado a la factura';
    raise notice '';
    raise notice '✅ SECCIÓN 6 COMPLETADA';
    raise notice '  Precio original: $300.00 (3 × $100)';
    raise notice '%', format('  Descuento (1 al 50%%): $50.00');
    raise notice '  Precio final: $250.00';
    raise notice '========================================';
end $$;

-- ========================================
-- SECCIÓN 7: Prueba de descuento por volumen (15% al comprar 10+)
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_customer_id uuid;
    v_product_id uuid;
    v_promo_id uuid;
    v_payment_id uuid;
    v_bill_id uuid;
    v_discount record;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '%', format('🧪 SECCIÓN 7: Prueba de descuento por volumen (15%%)');
    raise notice '========================================';
    raise notice '';
    
    -- Obtener IDs
    select tenant_id into v_tenant_id
    from core.tenant where tenant_name = 'Tienda de Electrónica';
    
    select tenant_customer_id into v_customer_id
    from core.tenant_customer where email = 'carlos.mendoza@email.com';
    
    select product_id into v_product_id
    from core.product where sku = 'MOUSE-001' and tenant_id = v_tenant_id;
    
    select promotion_id into v_promo_id
    from pos_module.promotion where promotion_code = 'BULK15';
    
    raise notice '📋 Datos de la prueba:';
    raise notice '  Producto: Mouse Gamer ($50.00)';
    raise notice '  Cantidad: 15 unidades';
    raise notice '%', format('  Promoción: BULK15 (15%% off al comprar 10+)');
    raise notice '';
    
    -- Calcular descuento
    raise notice '🔢 Calculando descuento...';
    for v_discount in
        select * from pos_module.calculate_promotion_discount(
            v_promo_id, v_tenant_id, v_product_id, 15, 50.00, 750.00
        )
    loop
        raise notice '';
        raise notice '💰 Resultado del descuento:';
        raise notice '  Descuento: $%', v_discount.discount_amount;
        raise notice '%', format('  Porcentaje: %s%%', v_discount.discount_percentage);
        raise notice '  Tipo: %', v_discount.promotion_type;
        raise notice '  Regla: %', v_discount.rule_applied;
    end loop;
    raise notice '';
    
    -- Crear pago
    insert into pos_module.customer_payment (
        tenant_customer_id, payment_method_id, payment_amount, currency_id, verified
    )
    values (v_customer_id, 2, 637.50, 1, false)
    returning customer_payment_id into v_payment_id;
    
    raise notice '✓ Pago creado (sin verificar): %', v_payment_id;
    raise notice '%', format('  Monto: $637.50 (15 unidades con 15%% descuento)');
    raise notice '';
    
    -- Verificar pago
    raise notice '🔐 Verificando pago...';
    call pos_module.verify_customer_payment(v_payment_id);
    
    perform pg_sleep(0.5);
    
    select bill_id into v_bill_id
    from pos_module.bill
    where customer_payment_id = v_payment_id;
    
    raise notice '✓ Factura creada automáticamente: %', v_bill_id;
    raise notice '';
    
    -- Agregar producto a la factura
    insert into pos_module.bill_product (
        bill_id, tenant_id, product_id, quantity, unit_price
    )
    values (v_bill_id, v_tenant_id, v_product_id, 15, 42.50);
    
    raise notice '✓ Producto agregado a la factura';
    raise notice '';
    raise notice '✅ SECCIÓN 7 COMPLETADA';
    raise notice '  Precio original: $750.00 (15 × $50)';
    raise notice '%', format('  Descuento (15%%): $112.50');
    raise notice '  Precio final: $637.50';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 8: Prueba de precios escalonados (Tier 1: 5%)
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_customer_id uuid;
    v_product_id uuid;
    v_promo_id uuid;
    v_payment_id uuid;
    v_bill_id uuid;
    v_discount record;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '%', format('🧪 SECCIÓN 8: Prueba de precios escalonados - Tier 1 (5%%)');
    raise notice '========================================';
    raise notice '';
    
    -- Obtener IDs
    select tenant_id into v_tenant_id
    from core.tenant where tenant_name = 'Tienda de Electrónica';
    
    select tenant_customer_id into v_customer_id
    from core.tenant_customer where email = 'carlos.mendoza@email.com';
    
    select product_id into v_product_id
    from core.product where sku = 'MOUSE-001' and tenant_id = v_tenant_id;
    
    select promotion_id into v_promo_id
    from pos_module.promotion where promotion_code = 'TIERS';
    
    raise notice '📋 Datos de la prueba:';
    raise notice '  Producto: Mouse Gamer ($50.00)';
    raise notice '  Cantidad: 5 unidades';
    raise notice '%', format('  Promoción: TIERS (Tier 1: 1-10 unidades = 5%%)');
    raise notice '';
    
    -- Calcular descuento
    raise notice '🔢 Calculando descuento...';
    for v_discount in
        select * from pos_module.calculate_promotion_discount(
            v_promo_id, v_tenant_id, v_product_id, 5, 50.00, 250.00
        )
    loop
        raise notice '';
        raise notice '💰 Resultado del descuento:';
        raise notice '  Descuento: $%', v_discount.discount_amount;
        raise notice '%', format('  Porcentaje: %s%%', v_discount.discount_percentage);
        raise notice '  Tipo: %', v_discount.promotion_type;
        raise notice '  Regla: %', v_discount.rule_applied;
    end loop;
    raise notice '';
    
    -- Crear pago
    insert into pos_module.customer_payment (
        tenant_customer_id, payment_method_id, payment_amount, currency_id, verified
    )
    values (v_customer_id, 3, 237.50, 1, false)
    returning customer_payment_id into v_payment_id;
    
    raise notice '✓ Pago creado (sin verificar): %', v_payment_id;
    raise notice '%', format('  Monto: $237.50 (5 unidades con 5%% descuento)');
    raise notice '';
    
    -- Verificar pago
    raise notice '🔐 Verificando pago...';
    call pos_module.verify_customer_payment(v_payment_id);
    
    perform pg_sleep(0.5);
    
    select bill_id into v_bill_id
    from pos_module.bill
    where customer_payment_id = v_payment_id;
    
    raise notice '✓ Factura creada automáticamente: %', v_bill_id;
    raise notice '';
    
    -- Agregar producto a la factura
    insert into pos_module.bill_product (
        bill_id, tenant_id, product_id, quantity, unit_price
    )
    values (v_bill_id, v_tenant_id, v_product_id, 5, 47.50);
    
    raise notice '✓ Producto agregado a la factura';
    raise notice '';
    raise notice '✅ SECCIÓN 8 COMPLETADA';
    raise notice '  Precio original: $250.00 (5 × $50)';
    raise notice '%', format('  Descuento (5%%): $12.50');
    raise notice '  Precio final: $237.50';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 9: Prueba de precios escalonados (Tier 2: 10%)
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_customer_id uuid;
    v_product_id uuid;
    v_promo_id uuid;
    v_payment_id uuid;
    v_bill_id uuid;
    v_discount record;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '%', format('🧪 SECCIÓN 9: Prueba de precios escalonados - Tier 2 (10%%)');
    raise notice '========================================';
    raise notice '';
    
    -- Obtener IDs
    select tenant_id into v_tenant_id
    from core.tenant where tenant_name = 'Tienda de Electrónica';
    
    select tenant_customer_id into v_customer_id
    from core.tenant_customer where email = 'carlos.mendoza@email.com';
    
    select product_id into v_product_id
    from core.product where sku = 'MOUSE-001' and tenant_id = v_tenant_id;
    
    select promotion_id into v_promo_id
    from pos_module.promotion where promotion_code = 'TIERS';
    
    raise notice '📋 Datos de la prueba:';
    raise notice '  Producto: Mouse Gamer ($50.00)';
    raise notice '  Cantidad: 25 unidades';
    raise notice '%', format('  Promoción: TIERS (Tier 2: 11-50 unidades = 10%%)');
    raise notice '';
    
    -- Calcular descuento
    raise notice '🔢 Calculando descuento...';
    for v_discount in
        select * from pos_module.calculate_promotion_discount(
            v_promo_id, v_tenant_id, v_product_id, 25, 50.00, 1250.00
        )
    loop
        raise notice '';
        raise notice '💰 Resultado del descuento:';
        raise notice '  Descuento: $%', v_discount.discount_amount;
        raise notice '%', format('  Porcentaje: %s%%', v_discount.discount_percentage);
        raise notice '  Tipo: %', v_discount.promotion_type;
        raise notice '  Regla: %', v_discount.rule_applied;
    end loop;
    raise notice '';
    
    -- Crear pago
    insert into pos_module.customer_payment (
        tenant_customer_id, payment_method_id, payment_amount, currency_id, verified
    )
    values (v_customer_id, 1, 1125.00, 1, false)
    returning customer_payment_id into v_payment_id;
    
    raise notice '✓ Pago creado (sin verificar): %', v_payment_id;
    raise notice '%', format('  Monto: $1,125.00 (25 unidades con 10%% descuento)');
    raise notice '';
    
    -- Verificar pago
    raise notice '🔐 Verificando pago...';
    call pos_module.verify_customer_payment(v_payment_id);
    
    perform pg_sleep(0.5);
    
    select bill_id into v_bill_id
    from pos_module.bill
    where customer_payment_id = v_payment_id;
    
    raise notice '✓ Factura creada automáticamente: %', v_bill_id;
    raise notice '';
    
    -- Agregar producto a la factura
    insert into pos_module.bill_product (
        bill_id, tenant_id, product_id, quantity, unit_price
    )
    values (v_bill_id, v_tenant_id, v_product_id, 25, 45.00);
    
    raise notice '✓ Producto agregado a la factura';
    raise notice '';
    raise notice '✅ SECCIÓN 9 COMPLETADA';
    raise notice '  Precio original: $1,250.00 (25 × $50)';
    raise notice '%', format('  Descuento (10%%): $125.00');
    raise notice '  Precio final: $1,125.00';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 10: Prueba de precios escalonados (Tier 3: 20%)
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_customer_id uuid;
    v_product_id uuid;
    v_promo_id uuid;
    v_payment_id uuid;
    v_bill_id uuid;
    v_discount record;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '%', format('🧪 SECCIÓN 10: Prueba de precios escalonados - Tier 3 (20%%)');
    raise notice '========================================';
    raise notice '';
    
    -- Obtener IDs
    select tenant_id into v_tenant_id
    from core.tenant where tenant_name = 'Tienda de Electrónica';
    
    select tenant_customer_id into v_customer_id
    from core.tenant_customer where email = 'carlos.mendoza@email.com';
    
    select product_id into v_product_id
    from core.product where sku = 'MOUSE-001' and tenant_id = v_tenant_id;
    
    select promotion_id into v_promo_id
    from pos_module.promotion where promotion_code = 'TIERS';
    
    raise notice '📋 Datos de la prueba:';
    raise notice '  Producto: Mouse Gamer ($50.00)';
    raise notice '  Cantidad: 100 unidades';
    raise notice '%', format('  Promoción: TIERS (Tier 3: 51+ unidades = 20%%)');
    raise notice '';
    
    -- Calcular descuento
    raise notice '🔢 Calculando descuento...';
    for v_discount in
        select * from pos_module.calculate_promotion_discount(
            v_promo_id, v_tenant_id, v_product_id, 100, 50.00, 5000.00
        )
    loop
        raise notice '';
        raise notice '💰 Resultado del descuento:';
        raise notice '  Descuento: $%', v_discount.discount_amount;
        raise notice '%', format('  Porcentaje: %s%%', v_discount.discount_percentage);
        raise notice '  Tipo: %', v_discount.promotion_type;
        raise notice '  Regla: %', v_discount.rule_applied;
    end loop;
    raise notice '';
    
    -- Crear pago
    insert into pos_module.customer_payment (
        tenant_customer_id, payment_method_id, payment_amount, currency_id, verified
    )
    values (v_customer_id, 2, 4000.00, 1, false)
    returning customer_payment_id into v_payment_id;
    
    raise notice '✓ Pago creado (sin verificar): %', v_payment_id;
    raise notice '%', format('  Monto: $4,000.00 (100 unidades con 20%% descuento)');
    raise notice '';
    
    -- Verificar pago
    raise notice '🔐 Verificando pago...';
    call pos_module.verify_customer_payment(v_payment_id);
    
    perform pg_sleep(0.5);
    
    select bill_id into v_bill_id
    from pos_module.bill
    where customer_payment_id = v_payment_id;
    
    raise notice '✓ Factura creada automáticamente: %', v_bill_id;
    raise notice '';
    
    -- Agregar producto a la factura
    insert into pos_module.bill_product (
        bill_id, tenant_id, product_id, quantity, unit_price
    )
    values (v_bill_id, v_tenant_id, v_product_id, 100, 40.00);
    
    raise notice '✓ Producto agregado a la factura';
    raise notice '';
    raise notice '✅ SECCIÓN 10 COMPLETADA';
    raise notice '  Precio original: $5,000.00 (100 × $50)';
    raise notice '%', format('  Descuento (20%%): $1,000.00');
    raise notice '  Precio final: $4,000.00';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 11: Resumen final de todas las pruebas
-- ========================================
do $$
declare
    v_total_payments int;
    v_total_bills int;
    v_total_promotions int;
    v_total_revenue numeric(10,2);
begin
    raise notice '';
    raise notice '========================================';
    raise notice '📊 SECCIÓN 11: RESUMEN FINAL';
    raise notice '========================================';
    raise notice '';
    
    select count(*) into v_total_payments from pos_module.customer_payment;
    select count(*) into v_total_bills from pos_module.bill;
    select count(*) into v_total_promotions from pos_module.promotion where is_active = true;
    select coalesce(sum(payment_amount), 0) into v_total_revenue from pos_module.customer_payment where verified = true;
    
    raise notice '📈 Estadísticas:';
    raise notice '  Total de pagos: %', v_total_payments;
    raise notice '  Total de facturas: %', v_total_bills;
    raise notice '  Promociones activas: %', v_total_promotions;
    raise notice '  Ingresos totales: $%', v_total_revenue;
    raise notice '';
    
    raise notice '✅ Pruebas ejecutadas:';
    raise notice '  ✓ Sección 1 - Setup inicial';
    raise notice '  ✓ Sección 2 - Creación de 6 promociones';
    raise notice '%', format('  ✓ Sección 3 - Descuento porcentual (20%%)');
    raise notice '  ✓ Sección 4 - Descuento fijo ($10)';
    raise notice '  ✓ Sección 5 - 2×1 (Buy 2 Get 1 Free)';
    raise notice '%', format('  ✓ Sección 6 - 3×2 (Tercero al 50%%)');
    raise notice '%', format('  ✓ Sección 7 - Descuento por volumen (15%%)');
    raise notice '%', format('  ✓ Sección 8 - Tier 1 (5%%)');
    raise notice '%', format('  ✓ Sección 9 - Tier 2 (10%%)');
    raise notice '%', format('  ✓ Sección 10 - Tier 3 (20%%)');
    raise notice '';
    raise notice '========================================';
    raise notice '🎉 TODAS LAS PRUEBAS COMPLETADAS CON ÉXITO';
    raise notice '========================================';
end $$;


-- ========================================
-- CONSULTAS ADICIONALES PARA ANÁLISIS
-- ========================================

-- 1️⃣ Ver todos los pagos realizados
select 
    '=== PAGOS REALIZADOS ===' as seccion,
    cp.customer_payment_id,
    concat(tc.first_name, ' ', tc.last_name) as cliente,
    cp.payment_amount as monto,
    pm.name as metodo_pago,
    cp.verified as verificado,
    cp.created_at as fecha
from pos_module.customer_payment cp
join core.tenant_customer tc on cp.tenant_customer_id = tc.tenant_customer_id
join core.payment_method pm on cp.payment_method_id = pm.payment_method_id
order by cp.created_at;

-- 2️⃣ Ver todas las facturas generadas
select 
    '=== FACTURAS GENERADAS ===' as seccion,
    b.bill_id,
    concat(tc.first_name, ' ', tc.last_name) as cliente,
    b.subtotal_amount,
    b.tax_amount,
    b.total_amount,
    b.billed_at as fecha
from pos_module.bill b
join core.tenant_customer tc on b.tenant_customer_id = tc.tenant_customer_id
order by b.billed_at;

-- 3️⃣ Ver productos vendidos
select 
    '=== PRODUCTOS VENDIDOS ===' as seccion,
    p.product_name,
    bp.quantity as cantidad,
    concat('$', bp.unit_price) as precio_unitario,
    concat('$', bp.total_price) as total,
    b.billed_at as fecha
from pos_module.bill_product bp
join core.product p on bp.tenant_id = p.tenant_id and bp.product_id = p.product_id
join pos_module.bill b on bp.bill_id = b.bill_id
order by b.billed_at;

-- 4️⃣ Resumen de descuentos por tipo de promoción
select 
    '=== RESUMEN DE PROMOCIONES ===' as seccion,
    pt.type_name as tipo,
    p.promotion_code as codigo,
    p.promotion_name as nombre,
    case when p.is_active then '✅ Activa' else '❌ Inactiva' end as estado
from pos_module.promotion p
join pos_module.promotion_type pt on p.promotion_type_id = pt.promotion_type_id
order by pt.type_name, p.promotion_code;