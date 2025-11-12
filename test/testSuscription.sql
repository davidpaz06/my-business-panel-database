-- =====================================
-- SCRIPT DE PRUEBA MANUAL POR SECCIONES
-- =====================================
-- Este script permite ejecutar cada sección por separado
-- para verificar el flujo completo del sistema de suscripciones
-- =====================================

-- ========================================
-- SECCIÓN 1: Crear un comercio (tenant)
-- ========================================
-- Ejecuta solo esta sección primero
do $$
declare
    v_tenant_id uuid;
begin
    insert into core.tenant (name, contact_email)
    values ('Comercio de Prueba', 'comercio@prueba.com')
    returning tenant_id into v_tenant_id;
    
    raise notice '========================================';
    raise notice '✅ SECCIÓN 1: Tenant creado exitosamente';
    raise notice '========================================';
    raise notice 'Tenant ID: %', v_tenant_id;
    raise notice 'Nombre: Comercio de Prueba';
    raise notice 'Email: comercio@prueba.com';
    raise notice 'Estado inicial: is_subscribed = false';
    raise notice '========================================';
end $$;

-- Verificar que el tenant se creó correctamente
select 
    tenant_id,
    name,
    contact_email,
    is_subscribed,
    created_at
from core.tenant
where name = 'Comercio de Prueba';


-- ========================================
-- SECCIÓN 2: Crear primer pago (Basic - $9.99)
-- ========================================
-- Ejecuta esta sección después de verificar que el tenant existe
do $$
declare
    v_tenant_id uuid;
    v_payment_id uuid;
begin
    -- Obtener el tenant_id
    select tenant_id into v_tenant_id
    from core.tenant
    where name = 'Comercio de Prueba';
    
    if v_tenant_id is null then
        raise exception 'Tenant no encontrado. Ejecuta primero la SECCIÓN 1';
    end if;
    
    -- Crear pago SIN verificar
    insert into core.tenant_payment (
        tenant_id,
        payment_method_id,
        payment_amount,
        payment_date,
        details,
        verified
    ) values (
        v_tenant_id,
        3,  -- credit_card
        9.99,
        current_timestamp,
        'Suscripción Basic - 1 mes',
        false  -- ⚠️ NO verificado
    ) returning tenant_payment_id into v_payment_id;
    
    raise notice '========================================';
    raise notice '✅ SECCIÓN 2: Primer pago creado';
    raise notice '========================================';
    raise notice 'Payment ID: %', v_payment_id;
    raise notice 'Monto: $9.99 (Basic - 1 mes)';
    raise notice 'Verificado: false ❌';
    raise notice 'Fecha: %', current_timestamp;
    raise notice '========================================';
end $$;

-- Verificar que el pago se creó SIN verificar
select 
    tenant_payment_id,
    t.name as tenant_name,
    payment_amount,
    pm.name as payment_method,
    verified,
    payment_date,
    details
from core.tenant_payment tp
join core.tenant t on tp.tenant_id = t.tenant_id
join core.payment_method pm on tp.payment_method_id = pm.payment_method_id
where t.name = 'Comercio de Prueba'
order by tp.created_at desc
limit 1;


-- ========================================
-- SECCIÓN 3: Verificar primer pago
-- ========================================
-- Esta sección llama al procedimiento verify_payment
do $$
declare
    v_payment_id uuid;
begin
    -- Obtener el ID del último pago no verificado
    select tenant_payment_id into v_payment_id
    from core.tenant_payment tp
    join core.tenant t on tp.tenant_id = t.tenant_id
    where t.name = 'Comercio de Prueba'
      and verified = false
    order by tp.created_at desc
    limit 1;
    
    if v_payment_id is null then
        raise exception 'No hay pagos pendientes de verificar. Ejecuta primero la SECCIÓN 2';
    end if;
    
    raise notice '========================================';
    raise notice '🔄 SECCIÓN 3: Verificando primer pago...';
    raise notice '========================================';
    raise notice 'Payment ID a verificar: %', v_payment_id;
    raise notice '';
    
    -- Llamar al procedimiento verify_payment
    call core.verify_payment(v_payment_id);
    
end $$;

-- Verificar que se creó la suscripción automáticamente
select 
    s.subscription_id,
    t.name as tenant_name,
    st.subscription_type_name,
    st.subscription_type_cost,
    s.start_date,
    s.end_date,
    s.is_active,
    (s.end_date - current_date) as days_remaining,
    s.created_at
from core.subscription s
join core.tenant t on s.tenant_id = t.tenant_id
join core.subscription_type st on s.subscription_type_id = st.subscription_type_id
where t.name = 'Comercio de Prueba'
order by s.created_at desc;

-- Verificar que el tenant está activo
select 
    tenant_id,
    name,
    is_subscribed,
    updated_at
from core.tenant
where name = 'Comercio de Prueba';


-- ========================================
-- SECCIÓN 4: Crear segundo pago (Standard - $49.99)
-- ========================================
-- Ejecuta esta sección ANTES de que expire la primera suscripción
do $$
declare
    v_tenant_id uuid;
    v_payment_id uuid;
    v_current_subscription_end_date date;
    v_days_remaining int;
begin
    -- Obtener tenant_id
    select tenant_id into v_tenant_id
    from core.tenant
    where name = 'Comercio de Prueba';
    
    if v_tenant_id is null then
        raise exception 'Tenant no encontrado';
    end if;
    
    -- Obtener información de la suscripción actual
    select end_date into v_current_subscription_end_date
    from core.subscription
    where tenant_id = v_tenant_id
      and is_active = true
    order by end_date desc
    limit 1;
    
    if v_current_subscription_end_date is null then
        raise exception 'No hay suscripción activa. Ejecuta primero las SECCIONES 1, 2 y 3';
    end if;
    
    v_days_remaining := v_current_subscription_end_date - current_date;
    
    raise notice '========================================';
    raise notice '📊 Estado actual antes del segundo pago';
    raise notice '========================================';
    raise notice 'Suscripción actual vence: %', v_current_subscription_end_date;
    raise notice 'Días restantes: %', v_days_remaining;
    raise notice '';
    
    -- Crear segundo pago SIN verificar
    insert into core.tenant_payment (
        tenant_id,
        payment_method_id,
        payment_amount,
        payment_date,
        details,
        verified
    ) values (
        v_tenant_id,
        3,
        49.99,
        current_timestamp,
        'Suscripción Standard - 6 meses',
        false  -- ⚠️ NO verificado
    ) returning tenant_payment_id into v_payment_id;
    
    raise notice '========================================';
    raise notice '✅ SECCIÓN 4: Segundo pago creado';
    raise notice '========================================';
    raise notice 'Payment ID: %', v_payment_id;
    raise notice 'Monto: $49.99 (Standard - 6 meses)';
    raise notice 'Verificado: false ❌';
    raise notice 'Fecha: %', current_timestamp;
    raise notice '========================================';
    raise notice '';
    raise notice '⚠️ IMPORTANTE: Este pago debe sumar los % días restantes', v_days_remaining;
    raise notice 'Nueva fecha de vencimiento esperada: %', v_current_subscription_end_date + interval '6 months';
    raise notice '========================================';
end $$;

-- Ver todos los pagos
select 
    tenant_payment_id,
    payment_amount,
    verified,
    payment_date,
    details,
    created_at
from core.tenant_payment tp
join core.tenant t on tp.tenant_id = t.tenant_id
where t.name = 'Comercio de Prueba'
order by tp.created_at;


-- ========================================
-- SECCIÓN 5: Verificar segundo pago
-- ========================================
do $$
declare
    v_payment_id uuid;
    v_old_end_date date;
    v_days_remaining int;
begin
    -- Obtener el último pago no verificado
    select tenant_payment_id into v_payment_id
    from core.tenant_payment tp
    join core.tenant t on tp.tenant_id = t.tenant_id
    where t.name = 'Comercio de Prueba'
      and verified = false
    order by tp.created_at desc
    limit 1;
    
    if v_payment_id is null then
        raise exception 'No hay pagos pendientes. Ejecuta primero la SECCIÓN 4';
    end if;
    
    -- ✅ CORRECCIÓN: Calificar is_active con el alias de la tabla
    select end_date into v_old_end_date
    from core.subscription s
    join core.tenant t on s.tenant_id = t.tenant_id
    where t.name = 'Comercio de Prueba'
      and s.is_active = true  -- ✅ CAMBIADO: Especificar que es de 'subscription'
    order by s.end_date desc  -- ✅ TAMBIÉN calificar end_date por consistencia
    limit 1;
    
    v_days_remaining := v_old_end_date - current_date;
    
    raise notice '========================================';
    raise notice '🔄 SECCIÓN 5: Verificando segundo pago...';
    raise notice '========================================';
    raise notice 'Payment ID: %', v_payment_id;
    raise notice 'Suscripción actual vence: %', v_old_end_date;
    raise notice 'Días que deben sumarse: %', v_days_remaining;
    raise notice '';
    
    -- Verificar el pago
    call core.verify_payment(v_payment_id);
    
end $$;


-- ========================================
-- SECCIÓN 6: Verificar resultados finales
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_old_end_date date;
    v_new_end_date date;
    v_expected_end_date date;
    v_days_difference int;
    v_subscription_record record;
    v_tenant_is_active boolean;  -- ✅ Nueva variable
begin
    -- Obtener tenant_id
    select tenant_id into v_tenant_id
    from core.tenant
    where name = 'Comercio de Prueba';
    
    -- Obtener fechas
    select s.end_date into v_old_end_date
    from core.subscription s
    where s.tenant_id = v_tenant_id
      and s.is_active = false
    order by s.created_at desc
    limit 1 offset 0;
    
    select s.end_date into v_new_end_date
    from core.subscription s
    where s.tenant_id = v_tenant_id
      and s.is_active = true
    order by s.created_at desc
    limit 1;
    
    v_expected_end_date := v_old_end_date + interval '6 months';
    v_days_difference := v_new_end_date - v_expected_end_date;
    
    raise notice '========================================';
    raise notice '📊 RESULTADOS FINALES';
    raise notice '========================================';
    raise notice '';
    raise notice '1️⃣ SUSCRIPCIÓN ANTERIOR (INACTIVA):';
    raise notice '   Tipo: Basic (1 mes)';
    raise notice '   Vencimiento: %', v_old_end_date;
    raise notice '   Estado: is_active = false ✓';
    raise notice '';
    raise notice '2️⃣ SUSCRIPCIÓN ACTUAL (ACTIVA):';
    raise notice '   Tipo: Standard (6 meses)';
    raise notice '   Vencimiento: %', v_new_end_date;
    raise notice '   Estado: is_active = true ✓';
    raise notice '';
    raise notice '3️⃣ VERIFICACIÓN DE SUMA DE TIEMPO:';
    raise notice '   Fecha esperada: %', v_expected_end_date;
    raise notice '   Fecha obtenida: %', v_new_end_date;
    
    if v_new_end_date = v_expected_end_date then
        raise notice '   ✅ CORRECTO: El tiempo restante se sumó correctamente';
    else
        raise notice '   ❌ ERROR: Diferencia de % días', v_days_difference;
    end if;
    
    raise notice '';
    raise notice '4️⃣ TODAS LAS SUSCRIPCIONES DEL TENANT:';
    for v_subscription_record in (
        select 
            st.subscription_type_name,
            s.start_date,
            s.end_date,
            s.is_active,
            (s.end_date - s.start_date) as duration_days
        from core.subscription s
        join core.subscription_type st on s.subscription_type_id = st.subscription_type_id
        where s.tenant_id = v_tenant_id
        order by s.created_at
    ) loop
        raise notice '   - Tipo: %, Inicio: %, Fin: %, Activa: %, Duración: % días', 
                     v_subscription_record.subscription_type_name,
                     v_subscription_record.start_date,
                     v_subscription_record.end_date,
                     v_subscription_record.is_active,
                     v_subscription_record.duration_days;
    end loop;
    
    raise notice '';
    raise notice '5️⃣ ESTADO DEL TENANT:';
    
    -- ✅ CORRECCIÓN: Usar variable del tipo correcto
    select t.is_subscribed into v_tenant_is_active
    from core.tenant t
    where t.tenant_id = v_tenant_id;
    
    raise notice '   is_subscribed: %', case when v_tenant_is_active then 'true ✓' else 'false ✗' end;
    
    raise notice '========================================';
end $$;

-- Vista resumida de todo
select 
    '=== TENANT ===' as seccion,
    t.name,
    t.is_subscribed,
    t.created_at
from core.tenant t
where t.name = 'Comercio de Prueba'

union all

select 
    '=== PAGOS ===' as seccion,
    concat('$', tp.payment_amount, ' - ', tp.details) as name,
    tp.verified::text as is_subscribed,
    tp.payment_date as created_at
from core.tenant_payment tp
join core.tenant t on tp.tenant_id = t.tenant_id
where t.name = 'Comercio de Prueba'
order by created_at;

-- Vista detallada de suscripciones
select 
    st.subscription_type_name as plan,
    concat('$', st.subscription_type_cost) as costo,
    s.start_date,
    s.end_date,
    (s.end_date - s.start_date) as duracion_dias,
    case when s.is_active then '✅ ACTIVA' else '❌ INACTIVA' end as estado,
    s.created_at
from core.subscription s
join core.tenant t on s.tenant_id = t.tenant_id
join core.subscription_type st on s.subscription_type_id = st.subscription_type_id
where t.name = 'Comercio de Prueba'
order by s.created_at;
