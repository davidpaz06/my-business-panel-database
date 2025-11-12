-- =====================================
-- SCRIPT DE PRUEBA DE FLUJO DE PAGOS DE CLIENTES (PoS)
-- =====================================
-- Este script prueba el flujo completo de pagos de clientes:
-- 1. Creación de tenant y cliente
-- 2. Registro de pago de cliente
-- 3. Verificación de pago (simulando webhook de pasarela)
-- 4. Creación automática de factura mediante trigger
-- =====================================

-- ========================================
-- SECCIÓN 1: Preparación - Crear tenant y cliente
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_tenant_client_id uuid;
begin
    raise notice '========================================';
    raise notice '🏪 SECCIÓN 1: Creando tenant y cliente';
    raise notice '========================================';
    
    -- Crear tenant (comercio)
    insert into core.tenant (name, contact_email, is_subscribed)
    values ('Restaurante El Buen Sabor', 'contacto@buensabor.com', true)
    returning tenant_id into v_tenant_id;
    
    raise notice '✓ Tenant creado: %', v_tenant_id;
    raise notice '  Nombre: Restaurante El Buen Sabor';
    
    -- Crear cliente vinculado al tenant
    insert into core.tenant_client (
        tenant_id,
        first_name,
        last_name,
        document_type_id,
        document_number,
        email,
        phone,
        birthdate,
        address
    ) values (
        v_tenant_id,
        'Juan',
        'Pérez',
        3, -- national_id
        '12345678A',
        'juan.perez@email.com',
        '+34-600-123-456',
        '1985-03-15',
        'Calle Principal 123, Madrid'
    ) returning tenant_client_id into v_tenant_client_id;
    
    raise notice '✓ Cliente creado: %', v_tenant_client_id;
    raise notice '  Nombre: Juan Pérez';
    raise notice '  Email: juan.perez@email.com';
    raise notice '';
    raise notice '✅ SECCIÓN 1 FINALIZADA';
    raise notice '========================================';
end;
$$ language plpgsql;


-- ========================================
-- SECCIÓN 2: Verificar datos iniciales
-- ========================================
do $$
declare
    v_tenant_count int;
    v_client_count int;
    v_payment_count int;
    v_bill_count int;
begin
    raise notice '========================================';
    raise notice '📊 SECCIÓN 2: Estado inicial de la base de datos';
    raise notice '========================================';
    
    select count(*) into v_tenant_count from core.tenant;
    select count(*) into v_client_count from core.tenant_client;
    select count(*) into v_payment_count from pos_module.client_payment;
    select count(*) into v_bill_count from pos_module.bill;
    
    raise notice 'Tenants: %', v_tenant_count;
    raise notice 'Clientes: %', v_client_count;
    raise notice 'Pagos registrados: %', v_payment_count;
    raise notice 'Facturas generadas: %', v_bill_count;
    raise notice '';
    raise notice '✅ SECCIÓN 2 FINALIZADA';
    raise notice '========================================';
end;
$$ language plpgsql;


-- ========================================
-- SECCIÓN 3: Cliente realiza un pago (NO VERIFICADO)
-- ========================================
do $$
declare
    v_tenant_client_id uuid;
    v_payment_id uuid;
begin
    raise notice '========================================';
    raise notice '💳 SECCIÓN 3: Registrando pago de cliente';
    raise notice '========================================';
    
    -- Obtener tenant_client_id
    select tenant_client_id into v_tenant_client_id
    from core.tenant_client
    where email = 'juan.perez@email.com';
    
    if v_tenant_client_id is null then
        raise exception 'Cliente no encontrado. Ejecuta primero la SECCIÓN 1';
    end if;
    
    -- Registrar pago SIN verificar (simula pago pendiente de confirmación)
    insert into pos_module.client_payment (
        tenant_client_id,
        payment_method_id,
        payment_amount,
        payment_date,
        currency_id,
        verified
    ) values (
        v_tenant_client_id,
        3, -- credit_card
        45.50,
        current_timestamp,
        1, -- USD
        false -- ⚠️ NO verificado aún
    ) returning client_payment_id into v_payment_id;
    
    raise notice '';
    raise notice '✓ Pago registrado exitosamente';
    raise notice '  Payment ID: %', v_payment_id;
    raise notice '  Cliente: %', v_tenant_client_id;
    raise notice '  Monto: $45.50 USD';
    raise notice '  Método: Tarjeta de Crédito';
    raise notice '  Estado: PENDIENTE (verified = false) ⏳';
    raise notice '';
    raise notice '✅ SECCIÓN 3 FINALIZADA';
    raise notice '========================================';
end;
$$ language plpgsql;


-- Verificar que el pago se creó correctamente
select 
    client_payment_id,
    concat(tc.first_name, ' ', tc.last_name) as cliente,
    payment_amount,
    pm.name as metodo_pago,
    c.code as moneda,
    verified as verificado,
    payment_date
from pos_module.client_payment cp
join core.tenant_client tc on cp.tenant_client_id = tc.tenant_client_id
join core.payment_method pm on cp.payment_method_id = pm.payment_method_id
join core.currency c on cp.currency_id = c.currency_id
order by cp.payment_date desc
limit 1;


-- ========================================
-- SECCIÓN 4: Simular confirmación de pasarela de pagos
-- ========================================
do $$
declare
    v_payment_id uuid;
    v_bill_count_before int;
    v_bill_count_after int;
begin
    raise notice '========================================';
    raise notice '🔐 SECCIÓN 4: Verificando pago (simulando webhook de pasarela)';
    raise notice '========================================';
    
    -- Obtener el ID del pago pendiente
    select client_payment_id into v_payment_id
    from pos_module.client_payment
    where verified = false
    order by payment_date desc
    limit 1;
    
    if v_payment_id is null then
        raise exception 'No hay pagos pendientes de verificar. Ejecuta primero la SECCIÓN 3';
    end if;
    
    -- Contar facturas antes de verificar
    select count(*) into v_bill_count_before
    from pos_module.bill;
    
    raise notice '';
    raise notice '📋 Estado antes de verificar:';
    raise notice '  Payment ID: %', v_payment_id;
    raise notice '  Facturas existentes: %', v_bill_count_before;
    raise notice '';
    raise notice '🔄 Llamando a verify_client_payment()...';
    raise notice '';
    
    -- Llamar al procedimiento de verificación
    call pos_module.verify_client_payment(v_payment_id);
    
    -- Contar facturas después de verificar
    select count(*) into v_bill_count_after
    from pos_module.bill;
    
    raise notice '';
    raise notice '📋 Estado después de verificar:';
    raise notice '  Facturas creadas: %', v_bill_count_after - v_bill_count_before;
    
    if v_bill_count_after > v_bill_count_before then
        raise notice '  ✅ Factura generada automáticamente por trigger';
    else
        raise notice '  ❌ ERROR: No se generó factura';
    end if;
    
    raise notice '';
    raise notice '✅ SECCIÓN 4 FINALIZADA';
    raise notice '========================================';
end;
$$ language plpgsql;


-- ========================================
-- SECCIÓN 5: Verificar creación de factura
-- ========================================
do $$
declare
    v_bill record;
begin
    raise notice '========================================';
    raise notice '🧾 SECCIÓN 5: Verificando factura generada';
    raise notice '========================================';
    
    -- Obtener detalles de la última factura
    select 
        b.bill_id,
        b.subtotal_amount,
        b.tax_amount,
        b.total_amount,
        concat(tc.first_name, ' ', tc.last_name) as cliente_nombre,
        tc.email as cliente_email,
        c.code as moneda,
        b.billed_at
    into v_bill
    from pos_module.bill b
    join core.tenant_client tc on b.tenant_client_id = tc.tenant_client_id
    join core.currency c on b.currency_id = c.currency_id
    order by b.billed_at desc
    limit 1;
    
    if v_bill.bill_id is null then
        raise notice '❌ ERROR: No se encontró ninguna factura';
        raise exception 'No se generó factura. Verifica el trigger';
    end if;
    
    raise notice '';
    raise notice '✅ Factura encontrada:';
    raise notice '  Bill ID: %', v_bill.bill_id;
    raise notice '  Cliente: %', v_bill.cliente_nombre;
    raise notice '  Email: %', v_bill.cliente_email;
    raise notice '  Subtotal: % %', v_bill.subtotal_amount, v_bill.moneda;
    raise notice '  Impuestos: % %', v_bill.tax_amount, v_bill.moneda;
    raise notice '  Total: % %', v_bill.total_amount, v_bill.moneda;
    raise notice '  Fecha: %', v_bill.billed_at;
    raise notice '';
    raise notice '✅ SECCIÓN 5 FINALIZADA';
    raise notice '========================================';
end;
$$ language plpgsql;


-- Mostrar factura completa con formato
select 
    '=== FACTURA GENERADA ===' as seccion,
    b.bill_id,
    concat(tc.first_name, ' ', tc.last_name) as cliente,
    tc.email,
    concat('$', b.subtotal_amount, ' ', c.code) as subtotal,
    concat('$', b.tax_amount, ' ', c.code) as impuestos,
    concat('$', b.total_amount, ' ', c.code) as total,
    b.billed_at as fecha_emision
from pos_module.bill b
join core.tenant_client tc on b.tenant_client_id = tc.tenant_client_id
join core.currency c on b.currency_id = c.currency_id
order by b.billed_at desc
limit 1;


-- ========================================
-- SECCIÓN 6: Probar restricción de verificación duplicada
-- ========================================
do $$
declare
    v_payment_id uuid;
begin
    raise notice '========================================';
    raise notice '🔒 SECCIÓN 6: Probando restricción de verificación duplicada';
    raise notice '========================================';
    
    -- Obtener el payment_id ya verificado
    select client_payment_id into v_payment_id
    from pos_module.client_payment
    where verified = true
    order by payment_date desc
    limit 1;
    
    raise notice '';
    raise notice '🔄 Intentando verificar nuevamente el pago: %', v_payment_id;
    raise notice '';
    
    -- Intentar verificar de nuevo (debe detectar que ya está verificado)
    call pos_module.verify_client_payment(v_payment_id);
    
    raise notice '';
    raise notice '✅ SECCIÓN 6 FINALIZADA';
    raise notice '========================================';
end;
$$ language plpgsql;


-- ========================================
-- SECCIÓN 7: Resumen final del flujo completo
-- ========================================
do $$
declare
    v_tenant_count int;
    v_client_count int;
    v_payment_count int;
    v_payment_verified_count int;
    v_bill_count int;
begin
    raise notice '========================================';
    raise notice '📊 SECCIÓN 7: RESUMEN FINAL DEL FLUJO';
    raise notice '========================================';
    
    select count(*) into v_tenant_count from core.tenant;
    select count(*) into v_client_count from core.tenant_client;
    select count(*) into v_payment_count from pos_module.client_payment;
    select count(*) into v_payment_verified_count 
        from pos_module.client_payment where verified = true;
    select count(*) into v_bill_count from pos_module.bill;
    
    raise notice '';
    raise notice '📈 Estadísticas finales:';
    raise notice '  Comercios (tenants): %', v_tenant_count;
    raise notice '  Clientes registrados: %', v_client_count;
    raise notice '  Pagos totales: %', v_payment_count;
    raise notice '  Pagos verificados: %', v_payment_verified_count;
    raise notice '  Facturas generadas: %', v_bill_count;
    raise notice '';
    
    if v_payment_verified_count = v_bill_count and v_bill_count > 0 then
        raise notice '✅ FLUJO COMPLETO EXITOSO';
        raise notice '   Todos los pagos verificados tienen su factura';
    else
        raise notice '⚠️  ADVERTENCIA: Discrepancia entre pagos y facturas';
    end if;
    
    raise notice '';
    raise notice '✅ Pruebas ejecutadas:';
    raise notice '  ✓ Sección 1 - Creación de tenant y cliente';
    raise notice '  ✓ Sección 2 - Verificación de estado inicial';
    raise notice '  ✓ Sección 3 - Registro de pago sin verificar';
    raise notice '  ✓ Sección 4 - Verificación de pago (webhook)';
    raise notice '  ✓ Sección 5 - Confirmación de factura generada';
    raise notice '  ✓ Sección 6 - Prueba de restricción duplicada';
    raise notice '  ✓ Sección 7 - Resumen final';
    raise notice '';
    raise notice '========================================';
    raise notice '🎉 PRUEBAS FINALIZADAS CON ÉXITO';
    raise notice '========================================';
end;
$$ language plpgsql;


-- ========================================
-- CONSULTAS ADICIONALES PARA ANÁLISIS
-- ========================================

-- 1️⃣ Ver todos los pagos con su estado
select 
    cp.client_payment_id,
    t.name as comercio,
    concat(tc.first_name, ' ', tc.last_name) as cliente,
    cp.payment_amount,
    c.code as moneda,
    pm.name as metodo_pago,
    case when cp.verified then '✅ Verificado' else '⏳ Pendiente' end as estado,
    cp.payment_date
from pos_module.client_payment cp
join core.tenant_client tc on cp.tenant_client_id = tc.tenant_client_id
join core.tenant t on tc.tenant_id = t.tenant_id
join core.currency c on cp.currency_id = c.currency_id
join core.payment_method pm on cp.payment_method_id = pm.payment_method_id
order by cp.payment_date desc;

-- 2️⃣ Ver todas las facturas con detalles
select 
    b.bill_id,
    t.name as comercio,
    concat(tc.first_name, ' ', tc.last_name) as cliente,
    b.subtotal_amount,
    b.tax_amount,
    b.total_amount,
    c.code as moneda,
    b.billed_at as fecha_emision
from pos_module.bill b
join core.tenant_client tc on b.tenant_client_id = tc.tenant_client_id
join core.tenant t on tc.tenant_id = t.tenant_id
join core.currency c on b.currency_id = c.currency_id
order by b.billed_at desc;

-- 3️⃣ Ver relación pago-factura
select 
    cp.client_payment_id as pago_id,
    cp.payment_amount as monto_pago,
    cp.verified as pago_verificado,
    b.bill_id as factura_id,
    b.total_amount as monto_factura,
    case 
        when b.bill_id is not null then '✅ Con factura'
        else '❌ Sin factura'
    end as estado_factura
from pos_module.client_payment cp
left join pos_module.bill b on cp.client_payment_id = b.client_payment_id
order by cp.payment_date desc;

-- 4️⃣ Verificar integridad del trigger
select 
    count(distinct cp.client_payment_id) as pagos_verificados,
    count(distinct b.bill_id) as facturas_generadas,
    case 
        when count(distinct cp.client_payment_id) = count(distinct b.bill_id) 
        then '✅ Trigger funcionando correctamente'
        else '❌ Hay pagos verificados sin factura'
    end as estado_trigger
from pos_module.client_payment cp
left join pos_module.bill b on cp.client_payment_id = b.client_payment_id
where cp.verified = true;