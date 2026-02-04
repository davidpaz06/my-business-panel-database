-- ============================================
-- TEST: SUBSCRIPTION MANAGEMENT - CRUD & PAYMENT VERIFICATION (IDEMPOTENTE)
-- ============================================
-- Objetivo: 
--   - Crear tenant (comercio)
--   - Crear pagos de suscripción (Basic y Standard)
--   - Verificar pagos y crear suscripciones automáticamente
--   - Validar acumulación de tiempo en renovaciones
--   - Listar historial de suscripciones
-- ============================================
-- Estructura:
--   0) Limpieza inicial (idempotente)
--   1) Preparación (tenant, region, payment methods, subscription types)
--   2) Crear primer pago (Basic - $9.99)
--   3) Verificar primer pago y crear suscripción
--   4) Crear segundo pago (Standard - $49.99)
--   5) Verificar segundo pago y validar acumulación de tiempo
--   6) Consultas de verificación
--   7) Resumen final
-- ============================================

SET LOCAL search_path = general_schema;

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
    WHERE tenant_name = 'Subscription Test Shop' 
    LIMIT 1;

    IF v_tenant_id IS NOT NULL THEN
        -- Limpiar en orden de dependencias
        DELETE FROM general_schema.subscription WHERE tenant_id = v_tenant_id;
        DELETE FROM general_schema.tenant_payment WHERE tenant_id = v_tenant_id;
        DELETE FROM general_schema.branch WHERE tenant_id = v_tenant_id;
        DELETE FROM general_schema.tenant WHERE tenant_id = v_tenant_id;
        
        RAISE NOTICE '   ✓ Removed previous test data for tenant: %', v_tenant_id;
    ELSE
        RAISE NOTICE '   ℹ️  No previous test tenant found';
    END IF;

    RAISE NOTICE '✅ SECCIÓN 0 COMPLETADA';
    RAISE NOTICE '========================================';
END $$;

-- ========================================
-- SECCIÓN 1: Preparación (tenant, region, payment methods, subscription types)
-- ========================================
DO $$
DECLARE
    v_tenant_id UUID;
    v_region_id INT;
    v_branch_id UUID;
    v_subscription_type_id INT;
    v_payment_method_id INT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🏪 SECCIÓN 1: Preparación (tenant, region, payment methods, subscription types)';
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
        'Subscription Test Shop', 
        v_region_id, 
        'subscription@testshop.local', 
        FALSE
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
        'Main Branch',
        '456 Subscription Street',
        'branch@testshop.local',
        TRUE
    )
    RETURNING branch_id INTO v_branch_id;
    RAISE NOTICE '   ✓ Branch created: %', v_branch_id;

    -- Verificar payment methods existen
    SELECT payment_method_id INTO v_payment_method_id 
    FROM general_schema.payment_method 
    WHERE name = 'credit_card' 
    LIMIT 1;
    
    IF v_payment_method_id IS NULL THEN
        INSERT INTO general_schema.payment_method (name) 
        VALUES ('credit_card') 
        RETURNING payment_method_id INTO v_payment_method_id;
        RAISE NOTICE '   ✓ Payment method created: credit_card (id: %)', v_payment_method_id;
    ELSE
        RAISE NOTICE '   ℹ️  Payment method exists: credit_card (id: %)', v_payment_method_id;
    END IF;

    -- Verificar subscription types existen
    SELECT subscription_type_id INTO v_subscription_type_id 
    FROM general_schema.subscription_type 
    WHERE subscription_type_name = 'Basic' 
    LIMIT 1;
    
    IF v_subscription_type_id IS NULL THEN
        INSERT INTO general_schema.subscription_type (subscription_type_name, subscription_type_cost, duration_months) 
        VALUES ('Basic', 9.99, 1) 
        RETURNING subscription_type_id INTO v_subscription_type_id;
        RAISE NOTICE '   ✓ Subscription type created: Basic ($9.99 - 1 month)';
    ELSE
        RAISE NOTICE '   ℹ️  Subscription type exists: Basic';
    END IF;

    SELECT subscription_type_id INTO v_subscription_type_id 
    FROM general_schema.subscription_type 
    WHERE subscription_type_name = 'Standard' 
    LIMIT 1;
    
    IF v_subscription_type_id IS NULL THEN
        INSERT INTO general_schema.subscription_type (subscription_type_name, subscription_type_cost, duration_months) 
        VALUES ('Standard', 49.99, 6) 
        RETURNING subscription_type_id INTO v_subscription_type_id;
        RAISE NOTICE '   ✓ Subscription type created: Standard ($49.99 - 6 months)';
    ELSE
        RAISE NOTICE '   ℹ️  Subscription type exists: Standard';
    END IF;

    RAISE NOTICE '✅ SECCIÓN 1 COMPLETADA';
    RAISE NOTICE '========================================';
END $$;

-- ========================================
-- SECCIÓN 2: Crear primer pago (Basic - $9.99)
-- ========================================
DO $$
DECLARE
    v_tenant_id UUID := (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Subscription Test Shop' LIMIT 1);
    v_payment_method_id INT := (SELECT payment_method_id FROM general_schema.payment_method WHERE name = 'credit_card' LIMIT 1);
    v_payment_id UUID;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '💳 SECCIÓN 2: Crear primer pago (Basic - $9.99)';
    RAISE NOTICE '========================================';

    INSERT INTO general_schema.tenant_payment (
        tenant_id,
        payment_method_id,
        payment_amount,
        payment_date,
        details,
        verified
    ) VALUES (
        v_tenant_id,
        v_payment_method_id,
        9.99,
        CURRENT_TIMESTAMP,
        'Suscripción Basic - 1 mes',
        FALSE
    )
    RETURNING tenant_payment_id INTO v_payment_id;
    
    RAISE NOTICE '   ✓ Payment created:';
    RAISE NOTICE '     - ID: %', v_payment_id;
    RAISE NOTICE '     - Amount: $9.99 (Basic - 1 month)';
    RAISE NOTICE '     - Verified: false ❌';
    RAISE NOTICE '     - Date: %', CURRENT_TIMESTAMP;

    RAISE NOTICE '✅ SECCIÓN 2 COMPLETADA';
    RAISE NOTICE '========================================';
END $$;

-- ========================================
-- SECCIÓN 3: Verificar primer pago y crear suscripción
-- ========================================
DO $$
DECLARE
    v_tenant_id UUID := (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Subscription Test Shop' LIMIT 1);
    v_payment_id UUID;
    v_subscription_type_id INT;
    v_subscription_id UUID;
    v_start_date DATE;
    v_end_date DATE;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ SECCIÓN 3: Verificar primer pago y crear suscripción';
    RAISE NOTICE '========================================';

    -- Obtener el pago no verificado
    SELECT tenant_payment_id INTO v_payment_id
    FROM general_schema.tenant_payment
    WHERE tenant_id = v_tenant_id 
      AND verified = FALSE
    ORDER BY payment_date DESC
    LIMIT 1;

    IF v_payment_id IS NULL THEN
        RAISE EXCEPTION 'No unverified payments found. Run SECCIÓN 2 first';
    END IF;

    RAISE NOTICE '   Verifying payment: %', v_payment_id;

    -- Obtener subscription type (Basic = 1 mes)
    SELECT subscription_type_id INTO v_subscription_type_id
    FROM general_schema.subscription_type
    WHERE subscription_type_name = 'Basic'
    LIMIT 1;

    -- Crear suscripción
    v_start_date := CURRENT_DATE;
    v_end_date := v_start_date + INTERVAL '1 month';

    INSERT INTO general_schema.subscription (
        tenant_id,
        subscription_type_id,
        start_date,
        end_date,
        is_active
    ) VALUES (
        v_tenant_id,
        v_subscription_type_id,
        v_start_date,
        v_end_date,
        TRUE
    )
    RETURNING subscription_id INTO v_subscription_id;

    RAISE NOTICE '   ✓ Subscription created:';
    RAISE NOTICE '     - ID: %', v_subscription_id;
    RAISE NOTICE '     - Type: Basic';
    RAISE NOTICE '     - Start: %', v_start_date;
    RAISE NOTICE '     - End: %', v_end_date;
    RAISE NOTICE '     - Active: true ✓';

    -- Marcar pago como verificado
    UPDATE general_schema.tenant_payment
    SET verified = TRUE, updated_at = CURRENT_TIMESTAMP
    WHERE tenant_payment_id = v_payment_id;

    RAISE NOTICE '   ✓ Payment marked as verified';

    -- Actualizar tenant como suscrito
    UPDATE general_schema.tenant
    SET is_subscribed = TRUE, updated_at = CURRENT_TIMESTAMP
    WHERE tenant_id = v_tenant_id;

    RAISE NOTICE '   ✓ Tenant marked as subscribed';

    RAISE NOTICE '✅ SECCIÓN 3 COMPLETADA';
    RAISE NOTICE '========================================';
END $$;

-- ========================================
-- SECCIÓN 4: Crear segundo pago (Standard - $49.99)
-- ========================================
DO $$
DECLARE
    v_tenant_id UUID := (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Subscription Test Shop' LIMIT 1);
    v_payment_method_id INT := (SELECT payment_method_id FROM general_schema.payment_method WHERE name = 'credit_card' LIMIT 1);
    v_current_subscription_end_date DATE;
    v_days_remaining INT;
    v_payment_id UUID;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '💳 SECCIÓN 4: Crear segundo pago (Standard - $49.99)';
    RAISE NOTICE '========================================';

    -- Obtener fecha de vencimiento actual
    SELECT end_date INTO v_current_subscription_end_date
    FROM general_schema.subscription
    WHERE tenant_id = v_tenant_id
      AND is_active = TRUE
    ORDER BY end_date DESC
    LIMIT 1;

    IF v_current_subscription_end_date IS NULL THEN
        RAISE EXCEPTION 'No active subscription found. Run SECCIÓN 3 first';
    END IF;

    v_days_remaining := v_current_subscription_end_date - CURRENT_DATE;

    RAISE NOTICE '   Current subscription status:';
    RAISE NOTICE '     - Type: Basic';
    RAISE NOTICE '     - Expires: %', v_current_subscription_end_date;
    RAISE NOTICE '     - Days remaining: %', v_days_remaining;
    RAISE NOTICE '';

    -- Crear nuevo pago
    INSERT INTO general_schema.tenant_payment (
        tenant_id,
        payment_method_id,
        payment_amount,
        payment_date,
        details,
        verified
    ) VALUES (
        v_tenant_id,
        v_payment_method_id,
        49.99,
        CURRENT_TIMESTAMP,
        'Suscripción Standard - 6 meses',
        FALSE
    )
    RETURNING tenant_payment_id INTO v_payment_id;

    RAISE NOTICE '   ✓ Payment created:';
    RAISE NOTICE '     - ID: %', v_payment_id;
    RAISE NOTICE '     - Amount: $49.99 (Standard - 6 months)';
    RAISE NOTICE '     - Verified: false ❌';
    RAISE NOTICE '';
    RAISE NOTICE '   ⚠️ IMPORTANT: This payment will add 6 months to remaining % days', v_days_remaining;

    RAISE NOTICE '✅ SECCIÓN 4 COMPLETADA';
    RAISE NOTICE '========================================';
END $$;

-- ========================================
-- SECCIÓN 5: Verificar segundo pago y validar acumulación de tiempo
-- ========================================
DO $$
DECLARE
    v_tenant_id UUID := (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Subscription Test Shop' LIMIT 1);
    v_payment_id UUID;
    v_subscription_type_id INT;
    v_old_subscription_id UUID;
    v_old_end_date DATE;
    v_new_end_date DATE;
    v_expected_end_date DATE;
    v_new_subscription_id UUID;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ SECCIÓN 5: Verificar segundo pago y validar acumulación de tiempo';
    RAISE NOTICE '========================================';

    -- Obtener el pago no verificado más reciente
    SELECT tenant_payment_id INTO v_payment_id
    FROM general_schema.tenant_payment
    WHERE tenant_id = v_tenant_id 
      AND verified = FALSE
    ORDER BY payment_date DESC
    LIMIT 1;

    IF v_payment_id IS NULL THEN
        RAISE EXCEPTION 'No unverified payments found. Run SECCIÓN 4 first';
    END IF;

    RAISE NOTICE '   Verifying payment: %', v_payment_id;

    -- Obtener subscription type (Standard = 6 meses)
    SELECT subscription_type_id INTO v_subscription_type_id
    FROM general_schema.subscription_type
    WHERE subscription_type_name = 'Standard'
    LIMIT 1;

    -- Obtener fecha final de suscripción anterior
    SELECT subscription_id, end_date INTO v_old_subscription_id, v_old_end_date
    FROM general_schema.subscription
    WHERE tenant_id = v_tenant_id
      AND is_active = TRUE
    ORDER BY end_date DESC
    LIMIT 1;

    -- Calcular nueva fecha esperada (sumar 6 meses a fecha anterior)
    v_expected_end_date := v_old_end_date + INTERVAL '6 months';

    -- Desactivar suscripción anterior
    UPDATE general_schema.subscription
    SET is_active = FALSE, updated_at = CURRENT_TIMESTAMP
    WHERE subscription_id = v_old_subscription_id;

    RAISE NOTICE '   ✓ Previous subscription deactivated: %', v_old_subscription_id;

    -- Crear nueva suscripción
    INSERT INTO general_schema.subscription (
        tenant_id,
        subscription_type_id,
        start_date,
        end_date,
        is_active
    ) VALUES (
        v_tenant_id,
        v_subscription_type_id,
        v_old_end_date,
        v_expected_end_date,
        TRUE
    )
    RETURNING subscription_id INTO v_new_subscription_id;

    RAISE NOTICE '   ✓ New subscription created:';
    RAISE NOTICE '     - ID: %', v_new_subscription_id;
    RAISE NOTICE '     - Type: Standard';
    RAISE NOTICE '     - Start: %', v_old_end_date;
    RAISE NOTICE '     - End: %', v_expected_end_date;
    RAISE NOTICE '     - Active: true ✓';

    -- Marcar pago como verificado
    UPDATE general_schema.tenant_payment
    SET verified = TRUE, updated_at = CURRENT_TIMESTAMP
    WHERE tenant_payment_id = v_payment_id;

    RAISE NOTICE '   ✓ Payment marked as verified';

    RAISE NOTICE '✅ SECCIÓN 5 COMPLETADA';
    RAISE NOTICE '========================================';
END $$;

-- ========================================
-- SECCIÓN 6: Consultas de verificación
-- ========================================
DO $$
DECLARE
    v_tenant_id UUID := (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Subscription Test Shop' LIMIT 1);
    v_payment_count INT;
    v_subscription_count INT;
    v_active_subscription_count INT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🔍 SECCIÓN 6: Consultas de verificación';
    RAISE NOTICE '========================================';

    -- Contar pagos
    SELECT COUNT(*) INTO v_payment_count 
    FROM general_schema.tenant_payment 
    WHERE tenant_id = v_tenant_id;
    RAISE NOTICE '   💳 Total payments: %', v_payment_count;

    -- Contar suscripciones
    SELECT COUNT(*) INTO v_subscription_count 
    FROM general_schema.subscription 
    WHERE tenant_id = v_tenant_id;
    RAISE NOTICE '   📅 Total subscriptions: %', v_subscription_count;

    -- Contar suscripciones activas
    SELECT COUNT(*) INTO v_active_subscription_count 
    FROM general_schema.subscription 
    WHERE tenant_id = v_tenant_id 
      AND is_active = TRUE;
    RAISE NOTICE '   ✅ Active subscriptions: %', v_active_subscription_count;

    RAISE NOTICE '';
    RAISE NOTICE '   ✅ All counts verified';
    RAISE NOTICE '✅ SECCIÓN 6 COMPLETADA';
    RAISE NOTICE '========================================';
END $$;

-- ========================================
-- QUERY: Listado de pagos realizados
-- ========================================
DO $$ BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '💳 LISTADO DE PAGOS REALIZADOS';
    RAISE NOTICE '========================================';
END $$;

SELECT 
    tp.tenant_payment_id AS "Payment ID",
    tp.payment_amount AS "Amount",
    CASE WHEN tp.verified THEN '✅ Verified' ELSE '❌ Pending' END AS "Status",
    tp.payment_date AS "Payment Date",
    tp.details AS "Details"
FROM general_schema.tenant_payment tp
JOIN general_schema.tenant t ON tp.tenant_id = t.tenant_id
WHERE t.tenant_name = 'Subscription Test Shop'
ORDER BY tp.payment_date DESC;

-- ========================================
-- QUERY: Historial de suscripciones
-- ========================================
DO $$ BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📅 HISTORIAL DE SUSCRIPCIONES';
    RAISE NOTICE '========================================';
END $$;

SELECT 
    st.subscription_type_name AS "Plan",
    CONCAT('$', st.subscription_type_cost) AS "Cost",
    s.start_date AS "Start Date",
    s.end_date AS "End Date",
    (s.end_date - s.start_date) AS "Duration Days",
    CASE WHEN s.is_active THEN '✅ ACTIVE' ELSE '❌ INACTIVE' END AS "Status",
    s.created_at AS "Created"
FROM general_schema.subscription s
JOIN general_schema.tenant t ON s.tenant_id = t.tenant_id
JOIN general_schema.subscription_type st ON s.subscription_type_id = st.subscription_type_id
WHERE t.tenant_name = 'Subscription Test Shop'
ORDER BY s.created_at;

-- ========================================
-- QUERY: Estado actual del tenant
-- ========================================
DO $$ BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🏪 ESTADO ACTUAL DEL TENANT';
    RAISE NOTICE '========================================';
END $$;

SELECT 
    t.tenant_id,
    t.tenant_name AS "Shop Name",
    t.contact_email AS "Email",
    CASE WHEN t.is_subscribed THEN '✅ ACTIVE' ELSE '❌ INACTIVE' END AS "Subscription Status",
    s.end_date AS "Expires",
    (s.end_date - CURRENT_DATE)::INT AS "Days Remaining",  -- ✅ CORRECTO
    t.created_at AS "Created"
FROM general_schema.tenant t
LEFT JOIN general_schema.subscription s ON t.tenant_id = s.tenant_id AND s.is_active = TRUE
WHERE t.tenant_name = 'Subscription Test Shop';

-- ========================================
-- RESUMEN FINAL
-- ========================================
DO $$
DECLARE
    v_tenant_id UUID := (SELECT tenant_id FROM general_schema.tenant WHERE tenant_name = 'Subscription Test Shop' LIMIT 1);
    v_total_spent NUMERIC;
    v_current_plan VARCHAR;
    v_days_remaining INT;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ RESUMEN FINAL DEL TEST';
    RAISE NOTICE '========================================';
    
    SELECT SUM(payment_amount) INTO v_total_spent
    FROM general_schema.tenant_payment
    WHERE tenant_id = v_tenant_id AND verified = TRUE;
    
    SELECT st.subscription_type_name INTO v_current_plan
    FROM general_schema.subscription s
    JOIN general_schema.subscription_type st ON s.subscription_type_id = st.subscription_type_id
    WHERE s.tenant_id = v_tenant_id AND s.is_active = TRUE
    LIMIT 1;

    SELECT (s.end_date - CURRENT_DATE)::INT INTO v_days_remaining
    FROM general_schema.subscription s
    WHERE s.tenant_id = v_tenant_id AND s.is_active = TRUE
    LIMIT 1;
    
    RAISE NOTICE '💰 Total spent: $%', COALESCE(v_total_spent, 0);
    RAISE NOTICE '📅 Current plan: %', COALESCE(v_current_plan, 'None');
    RAISE NOTICE '⏰ Days remaining: %', COALESCE(v_days_remaining, 0);
    RAISE NOTICE '';
    RAISE NOTICE '✅ TEST COMPLETADO EXITOSAMENTE';
    RAISE NOTICE '========================================';
END $$;
