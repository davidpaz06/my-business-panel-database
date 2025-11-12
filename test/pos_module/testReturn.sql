-- =====================================
-- SCRIPT DE PRUEBA: DEVOLUCIONES MÚLTIPLES
-- =====================================
-- Este script prueba el sistema completo de devoluciones:
-- 1. Preparación de datos (tenant, cliente, productos, factura)
-- 2. Creación de transacción de devolución
-- 3. Registro de productos devueltos (trigger automático)
-- 4. Verificación de resultados
-- =====================================

-- ========================================
-- SECCIÓN 1: Preparación completa de datos
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_customer_id uuid;
    v_product_a_id uuid;
    v_product_b_id uuid;
    v_product_c_id uuid;
    v_payment_id uuid;
    v_bill_id uuid;
    v_bill_product_a_id uuid;
    v_bill_product_b_id uuid;
    v_bill_product_c_id uuid;
begin
    raise notice '========================================';
    raise notice '🧪 TEST: Multiple returns from same bill';
    raise notice '========================================';
    raise notice '';
    raise notice '📋 SECCIÓN 1: Preparación de datos';
    raise notice '========================================';
    
    -- =====================================
    -- 1.1 Crear tenant
    -- =====================================
    insert into core.tenant (tenant_name, contact_email, is_subscribed)
    values ('Test Shop', 'test@shop.com', true)
    returning tenant_id into v_tenant_id;
    
    raise notice '✓ Tenant creado: %', v_tenant_id;
    
    -- =====================================
    -- 1.2 Crear cliente
    -- =====================================
    insert into core.tenant_customer (
        tenant_id, 
        first_name, 
        last_name, 
        document_number, 
        email, 
        phone
    )
    values (
        v_tenant_id, 
        'Jane', 
        'Smith',
        'DOC456', 
        'jane@test.com', 
        '555-0200'
    )
    returning tenant_customer_id into v_customer_id;
    
    raise notice '✓ Cliente creado: %', v_customer_id;
    
    -- =====================================
    -- 1.3 Crear productos
    -- =====================================
    insert into core.product (tenant_id, sku, product_name, unit_price)
    values (v_tenant_id, 'SKU-A', 'Product A', 10.00)
    returning product_id into v_product_a_id;
    
    insert into core.product (tenant_id, sku, product_name, unit_price)
    values (v_tenant_id, 'SKU-B', 'Product B', 20.00)
    returning product_id into v_product_b_id;
    
    insert into core.product (tenant_id, sku, product_name, unit_price)
    values (v_tenant_id, 'SKU-C', 'Product C', 15.00)
    returning product_id into v_product_c_id;
    
    raise notice '✓ Productos creados: 3';
    raise notice '  - Product A (SKU-A): $10.00';
    raise notice '  - Product B (SKU-B): $20.00';
    raise notice '  - Product C (SKU-C): $15.00';
    
    -- =====================================
    -- 1.4 Crear pago del cliente (SIN VERIFICAR)
    -- =====================================
    insert into pos_module.customer_payment (
        tenant_customer_id, 
        payment_method_id, 
        payment_amount, 
        currency_id, 
        verified  -- ⚠️ CAMBIO: Ahora FALSE
    )
    values (v_customer_id, 1, 140.00, 1, false)  -- ← CAMBIADO A FALSE
    returning customer_payment_id into v_payment_id;
    
    raise notice '✓ Pago creado: %', v_payment_id;
    raise notice '  Monto: $140.00 USD';
    raise notice '  Estado: Pendiente (no verificado)';
    
    -- =====================================
    -- 1.5 Verificar el pago (esto dispara el trigger)
    -- =====================================
    raise notice '';
    raise notice '🔄 Verificando pago...';
    
    update pos_module.customer_payment
    set verified = true
    where customer_payment_id = v_payment_id;
    
    raise notice '✓ Pago verificado';
    
    -- =====================================
    -- 1.6 Esperar a que se cree la factura (trigger automático)
    -- =====================================
    perform pg_sleep(0.5);
    
    select bill_id into v_bill_id
    from pos_module.bill
    where customer_payment_id = v_payment_id;
    
    if v_bill_id is null then
        raise exception 'Bill was not created automatically. Check trigger on_customer_payment_verified';
    end if;
    
    raise notice '✓ Factura creada automáticamente: %', v_bill_id;
    
    -- =====================================
    -- 1.7 Agregar productos a la factura
    -- =====================================
    insert into pos_module.bill_product (
        bill_id, 
        tenant_id, 
        product_id, 
        quantity, 
        unit_price
    )
    values (v_bill_id, v_tenant_id, v_product_a_id, 5, 10.00)
    returning bill_product_id into v_bill_product_a_id;
    
    insert into pos_module.bill_product (
        bill_id, 
        tenant_id, 
        product_id, 
        quantity, 
        unit_price
    )
    values (v_bill_id, v_tenant_id, v_product_b_id, 3, 20.00)
    returning bill_product_id into v_bill_product_b_id;
    
    insert into pos_module.bill_product (
        bill_id, 
        tenant_id, 
        product_id, 
        quantity, 
        unit_price
    )
    values (v_bill_id, v_tenant_id, v_product_c_id, 2, 15.00)
    returning bill_product_id into v_bill_product_c_id;
    
    raise notice '✓ Productos agregados a la factura:';
    raise notice '  - Product A: 5 units × $10.00 = $50.00';
    raise notice '  - Product B: 3 units × $20.00 = $60.00';
    raise notice '  - Product C: 2 units × $15.00 = $30.00';
    
    -- =====================================
    -- 1.8 Actualizar totales de la factura
    -- =====================================
    update pos_module.bill
    set subtotal_amount = 140.00,  -- 50 + 60 + 30
        tax_amount = 14.00,         -- 10%
        total_amount = 154.00
    where bill_id = v_bill_id;
    
    raise notice '✓ Factura actualizada:';
    raise notice '  Subtotal: $140.00';
    raise notice '  Tax (10%%): $14.00';
    raise notice '  Total: $154.00';
    raise notice '';
    raise notice '✅ SECCIÓN 1 FINALIZADA - Datos preparados correctamente';
    raise notice '========================================';
end $$;

-- ========================================
-- SECCIÓN 2: Verificar estado inicial
-- ========================================
do $$
declare
    v_tenant_count int;
    v_customer_count int;
    v_product_count int;
    v_bill_count int;
    v_bill_product_count int;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '📊 SECCIÓN 2: Estado inicial de la base de datos';
    raise notice '========================================';
    
    select count(*) into v_tenant_count from core.tenant;
    select count(*) into v_customer_count from core.tenant_customer;
    select count(*) into v_product_count from core.product;
    select count(*) into v_bill_count from pos_module.bill;
    select count(*) into v_bill_product_count from pos_module.bill_product;
    
    raise notice '';
    raise notice 'Registros en la base de datos:';
    raise notice '  - Tenants: %', v_tenant_count;
    raise notice '  - Clientes: %', v_customer_count;
    raise notice '  - Productos: %', v_product_count;
    raise notice '  - Facturas: %', v_bill_count;
    raise notice '  - Productos en facturas: %', v_bill_product_count;
    
    if v_tenant_count = 0 or v_bill_count = 0 then
        raise exception 'Database is empty. Run SECTION 1 first.';
    end if;
    
    raise notice '';
    raise notice '✅ SECCIÓN 2 FINALIZADA';
    raise notice '========================================';
end $$;


-- Ver factura actual antes de devoluciones
select 
    '=== FACTURA ANTES DE DEVOLUCIONES ===' as seccion,
    b.bill_id,
    concat(tc.first_name, ' ', tc.last_name) as cliente,
    concat('$', b.subtotal_amount) as subtotal,
    concat('$', b.tax_amount) as impuesto,
    concat('$', b.total_amount) as total
from pos_module.bill b
join core.tenant_customer tc on b.tenant_customer_id = tc.tenant_customer_id
order by b.billed_at desc
limit 1;


-- Ver productos en la factura
select 
    '=== PRODUCTOS EN FACTURA ===' as seccion,
    p.product_name,
    bp.quantity as cantidad,
    concat('$', bp.unit_price) as precio_unitario,
    concat('$', bp.total_price) as precio_total
from pos_module.bill_product bp
join core.product p on bp.tenant_id = p.tenant_id and bp.product_id = p.product_id
join pos_module.bill b on bp.bill_id = b.bill_id
order by p.product_name;


-- ========================================
-- SECCIÓN 3: Crear transacción de devolución
-- ========================================
do $$
declare
    v_bill_id uuid;
    v_customer_id uuid;
    v_return_transaction_id uuid;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '🔄 SECCIÓN 3: Creando transacción de devolución';
    raise notice '========================================';
    
    -- Obtener bill_id del último bill creado
    select bill_id, tenant_customer_id 
    into v_bill_id, v_customer_id
    from pos_module.bill
    order by billed_at desc
    limit 1;
    
    if v_bill_id is null then
        raise exception 'No bill found. Run SECTION 1 first.';
    end if;
    
    raise notice '';
    raise notice 'Datos de la factura:';
    raise notice '  Bill ID: %', v_bill_id;
    raise notice '  Customer ID: %', v_customer_id;
    
    -- Crear transacción de devolución
    insert into pos_module.return_transaction (
        bill_id, 
        tenant_customer_id,
        total_refund_amount, 
        refund_method, 
        return_status
    )
    values (
        v_bill_id, 
        v_customer_id, 
        55.00,  -- Total a devolver
        1,      -- cash
        'pending'
    )
    returning return_transaction_id into v_return_transaction_id;
    
    raise notice '';
    raise notice '✓ Transacción de devolución creada:';
    raise notice '  Return Transaction ID: %', v_return_transaction_id;
    raise notice '  Monto total a devolver: $55.00';
    raise notice '  Método de reembolso: Efectivo';
    raise notice '  Estado: Pendiente';
    raise notice '';
    raise notice '✅ SECCIÓN 3 FINALIZADA';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 4: Registrar productos devueltos (trigger automático)
-- ========================================
do $$
declare
    v_return_transaction_id uuid;
    v_bill_product_a_id uuid;
    v_bill_product_b_id uuid;
    v_bill_product_c_id uuid;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '🔄 SECCIÓN 4: Registrando productos devueltos';
    raise notice '========================================';
    raise notice '';
    raise notice '⚠️  Al insertar cada producto devuelto, el trigger';
    raise notice '   update_on_return_trigger actualizará la factura automáticamente';
    raise notice '';
    
    -- Obtener IDs necesarios
    select return_transaction_id into v_return_transaction_id
    from pos_module.return_transaction
    order by return_date desc
    limit 1;
    
    if v_return_transaction_id is null then
        raise exception 'No return transaction found. Run SECTION 3 first.';
    end if;
    
    -- Obtener IDs de productos en la factura
    select bill_product_id into v_bill_product_a_id
    from pos_module.bill_product bp
    join core.product p on bp.tenant_id = p.tenant_id and bp.product_id = p.product_id
    where p.sku = 'SKU-A'
    limit 1;
    
    select bill_product_id into v_bill_product_b_id
    from pos_module.bill_product bp
    join core.product p on bp.tenant_id = p.tenant_id and bp.product_id = p.product_id
    where p.sku = 'SKU-B'
    limit 1;
    
    select bill_product_id into v_bill_product_c_id
    from pos_module.bill_product bp
    join core.product p on bp.tenant_id = p.tenant_id and bp.product_id = p.product_id
    where p.sku = 'SKU-C'
    limit 1;
    
    raise notice '🔄 Devolviendo productos (trigger se ejecutará 3 veces)...';
    raise notice '';
    
    -- ⚡ DEVOLVER 3 PRODUCTOS EN UNA SOLA TRANSACCIÓN
    -- Cada INSERT dispara el trigger update_on_return_trigger
    insert into pos_module.return_product (
        return_transaction_id, 
        bill_product_id, 
        quantity, 
        unit_price
    )
    values 
        (v_return_transaction_id, v_bill_product_a_id, 2, 10.00),  -- -$20
        (v_return_transaction_id, v_bill_product_b_id, 1, 20.00),  -- -$20
        (v_return_transaction_id, v_bill_product_c_id, 1, 15.00);  -- -$15
    
    raise notice '';
    raise notice '✅ SECCIÓN 4 FINALIZADA';
    raise notice '   Total devuelto: $55.00 (2×$10 + 1×$20 + 1×$15)';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 5: Verificar productos en factura después de devoluciones
-- ========================================
do $$
declare
    v_product_a_qty int;
    v_product_b_qty int;
    v_product_c_qty int;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '📦 SECCIÓN 5: Verificar productos en factura';
    raise notice '========================================';
    
    -- Obtener cantidades actuales de productos en factura
    select coalesce(bp.quantity, 0) into v_product_a_qty
    from pos_module.bill_product bp
    join core.product p on bp.tenant_id = p.tenant_id and bp.product_id = p.product_id
    where p.sku = 'SKU-A'
    limit 1;
    
    select coalesce(bp.quantity, 0) into v_product_b_qty
    from pos_module.bill_product bp
    join core.product p on bp.tenant_id = p.tenant_id and bp.product_id = p.product_id
    where p.sku = 'SKU-B'
    limit 1;
    
    select coalesce(bp.quantity, 0) into v_product_c_qty
    from pos_module.bill_product bp
    join core.product p on bp.tenant_id = p.tenant_id and bp.product_id = p.product_id
    where p.sku = 'SKU-C'
    limit 1;
    
    raise notice '';
    raise notice 'Cantidades actuales en factura:';
    raise notice '  - Product A: % units (esperado: 3)', v_product_a_qty;
    raise notice '  - Product B: % units (esperado: 2)', v_product_b_qty;
    raise notice '  - Product C: % units (esperado: 1)', v_product_c_qty;
    
    -- Validar
    if v_product_a_qty = 3 and v_product_b_qty = 2 and v_product_c_qty = 1 then
        raise notice '';
        raise notice '✅ Cantidades actualizadas correctamente';
    else
        raise notice '';
        raise notice '❌ ERROR: Cantidades incorrectas';
    end if;
    
    raise notice '';
    raise notice '✅ SECCIÓN 5 FINALIZADA';
    raise notice '========================================';
end $$;


-- Ver productos actuales en factura
select 
    '=== PRODUCTOS DESPUÉS DE DEVOLUCIÓN ===' as seccion,
    p.product_name,
    bp.quantity as cantidad_actual,
    concat('$', bp.unit_price) as precio_unitario,
    concat('$', bp.total_price) as precio_total
from pos_module.bill_product bp
join core.product p on bp.tenant_id = p.tenant_id and bp.product_id = p.product_id
order by p.product_name;


-- ========================================
-- SECCIÓN 6: Verificar totales de la factura
-- ========================================
do $$
declare
    v_bill record;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '💰 SECCIÓN 6: Verificar totales de factura';
    raise notice '========================================';
    
    -- Obtener totales actuales de la factura
    select 
        subtotal_amount, 
        tax_amount, 
        total_amount
    into v_bill
    from pos_module.bill
    order by billed_at desc
    limit 1;
    
    raise notice '';
    raise notice 'Totales actuales de la factura:';
    raise notice '  Subtotal: $% (esperado: $85.00)', v_bill.subtotal_amount;
    raise notice '  Tax: $% (esperado: $8.50)', v_bill.tax_amount;
    raise notice '  Total: $% (esperado: $93.50)', v_bill.total_amount;
    raise notice '';
    
    -- Cálculo esperado:
    -- Original: $140.00 subtotal
    -- Devuelto: 2×$10 + 1×$20 + 1×$15 = $55.00
    -- Nuevo: $140 - $55 = $85.00 subtotal
    -- Tax (10%): $85 × 0.10 = $8.50
    -- Total: $85 + $8.50 = $93.50
    
    if v_bill.subtotal_amount = 85.00 and 
       v_bill.tax_amount = 8.50 and 
       v_bill.total_amount = 93.50 then
        raise notice '✅ TOTALES CORRECTOS';
    else
        raise notice '❌ ERROR: Totales incorrectos';
        raise notice '';
        raise notice 'Diferencias:';
        raise notice '  Subtotal: % (diff: $%)', 
            v_bill.subtotal_amount, 
            v_bill.subtotal_amount - 85.00;
        raise notice '  Tax: % (diff: $%)', 
            v_bill.tax_amount, 
            v_bill.tax_amount - 8.50;
        raise notice '  Total: % (diff: $%)', 
            v_bill.total_amount, 
            v_bill.total_amount - 93.50;
    end if;
    
    raise notice '';
    raise notice '✅ SECCIÓN 6 FINALIZADA';
    raise notice '========================================';
end $$;


-- Ver factura después de devoluciones
select 
    '=== FACTURA DESPUÉS DE DEVOLUCIONES ===' as seccion,
    b.bill_id,
    concat(tc.first_name, ' ', tc.last_name) as cliente,
    concat('$', b.subtotal_amount) as subtotal,
    concat('$', b.tax_amount) as impuesto,
    concat('$', b.total_amount) as total
from pos_module.bill b
join core.tenant_customer tc on b.tenant_customer_id = tc.tenant_customer_id
order by b.billed_at desc
limit 1;


-- ========================================
-- SECCIÓN 7: Resumen final y validación completa
-- ========================================
do $$
declare
    v_original_subtotal numeric(10,2) := 140.00;
    v_original_tax numeric(10,2) := 14.00;
    v_original_total numeric(10,2) := 154.00;
    
    v_current_subtotal numeric(10,2);
    v_current_tax numeric(10,2);
    v_current_total numeric(10,2);
    
    v_return_count int;
    v_return_total numeric(10,2);
begin
    raise notice '';
    raise notice '========================================';
    raise notice '📊 SECCION 7: RESUMEN FINAL';
    raise notice '========================================';
    
    -- Obtener datos actuales
    select 
        subtotal_amount, 
        tax_amount, 
        total_amount
    into v_current_subtotal, v_current_tax, v_current_total
    from pos_module.bill
    order by billed_at desc
    limit 1;
    
    -- Obtener estadísticas de devoluciones
    select 
        count(*),
        sum(total_price)
    into v_return_count, v_return_total
    from pos_module.return_product;
    
    raise notice '';
    raise notice '========================================';
    raise notice '📈 COMPARACION DE FACTURA';
    raise notice '========================================';
    raise notice '';
    raise notice 'Estado ORIGINAL:';
    raise notice '  - Subtotal: $%', v_original_subtotal;
    raise notice '  - Tax (10%%): $%', v_original_tax;
    raise notice '  - Total: $%', v_original_total;
    raise notice '';
    raise notice 'DEVOLUCIONES:';
    raise notice '  - Productos devueltos: %', v_return_count;
    raise notice '  - Monto total devuelto: $%', v_return_total;
    raise notice '  - Breakdown:';
    raise notice '    • Product A: 2 x $10.00 = $20.00';
    raise notice '    • Product B: 1 x $20.00 = $20.00';
    raise notice '    • Product C: 1 x $15.00 = $15.00';
    raise notice '';
    raise notice 'Estado ACTUAL:';
    raise notice '  - Subtotal: $%', v_current_subtotal;
    raise notice '  - Tax (10%%): $%', v_current_tax;
    raise notice '  - Total: $%', v_current_total;
    raise notice '';
    raise notice 'CAMBIOS:';
    raise notice '  - Subtotal: $% -> $% (-$%)', 
        v_original_subtotal, 
        v_current_subtotal,
        v_original_subtotal - v_current_subtotal;
    raise notice '  - Tax: $% -> $% (-$%)', 
        v_original_tax, 
        v_current_tax,
        v_original_tax - v_current_tax;
    raise notice '  - Total: $% -> $% (-$%)', 
        v_original_total, 
        v_current_total,
        v_original_total - v_current_total;
    raise notice '';
    raise notice '========================================';
    raise notice '';
    
    -- Validación final
    if v_current_subtotal = 85.00 and 
       v_current_tax = 8.50 and 
       v_current_total = 93.50 and
       v_return_count = 3 and
       v_return_total = 55.00 then
        raise notice '✅✅✅ TODAS LAS PRUEBAS PASARON ✅✅✅';
        raise notice '';
        raise notice 'El sistema de devoluciones funciona correctamente:';
        raise notice '  ✓ Productos actualizados en factura';
        raise notice '  ✓ Cantidades recalculadas correctamente';
        raise notice '  ✓ Subtotal actualizado';
        raise notice '  ✓ Impuesto recalculado proporcionalmente';
        raise notice '  ✓ Total correcto';
        raise notice '  ✓ Trigger ejecutado para cada producto devuelto';
    else
        raise notice '❌ ALGUNAS PRUEBAS FALLARON';
        raise notice '';
        raise notice 'Valores actuales vs esperados:';
        raise notice '  Subtotal: $% (esperado: $85.00)', v_current_subtotal;
        raise notice '  Tax: $% (esperado: $8.50)', v_current_tax;
        raise notice '  Total: $% (esperado: $93.50)', v_current_total;
        raise notice '  Returns: % (esperado: 3)', v_return_count;
        raise notice '  Return total: $% (esperado: $55.00)', v_return_total;
    end if;
    
    raise notice '';
    raise notice '✅ SECCION 7 FINALIZADA';
    raise notice '========================================';
    raise notice '';
    raise notice '🎉 PRUEBAS COMPLETADAS';
    raise notice '========================================';
end $$;

-- ========================================
-- CONSULTAS ADICIONALES PARA ANÁLISIS
-- ========================================

-- 1️⃣ Ver todas las devoluciones registradas
select 
    '=== DEVOLUCIONES REGISTRADAS ===' as seccion,
    p.product_name,
    rp.quantity as cantidad_devuelta,
    concat('$', rp.unit_price) as precio_unitario,
    concat('$', rp.total_price) as total_devuelto,
    rp.created_at as fecha
from pos_module.return_product rp
join pos_module.bill_product bp on rp.bill_product_id = bp.bill_product_id
join core.product p on bp.tenant_id = p.tenant_id and bp.product_id = p.product_id
order by rp.created_at;

-- 2️⃣ Ver historial completo de la factura
select 
    '=== HISTORIAL DE FACTURA ===' as seccion,
    'Original' as estado,
    '$140.00' as subtotal,
    '$14.00' as tax,
    '$154.00' as total
union all
select 
    '=== HISTORIAL DE FACTURA ===' as seccion,
    'Actual' as estado,
    concat('$', subtotal_amount) as subtotal,
    concat('$', tax_amount) as tax,
    concat('$', total_amount) as total
from pos_module.bill
order by estado desc;

-- 3️⃣ Ver transacción de devolución completa
select 
    '=== TRANSACCIÓN DE DEVOLUCIÓN ===' as seccion,
    rt.return_transaction_id,
    concat(tc.first_name, ' ', tc.last_name) as cliente,
    concat('$', rt.total_refund_amount) as monto_reembolso,
    pm.name as metodo_reembolso,
    rt.return_status as estado,
    rt.return_date as fecha
from pos_module.return_transaction rt
join core.tenant_customer tc on rt.tenant_customer_id = tc.tenant_customer_id
join core.payment_method pm on rt.refund_method = pm.payment_method_id;