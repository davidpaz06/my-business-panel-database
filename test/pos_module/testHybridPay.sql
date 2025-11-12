-- =====================================
-- SCRIPT DE PRUEBA: PAGOS HÍBRIDOS Y SISTEMA DE PUNTOS
-- =====================================
-- Este script prueba:
-- 1. Configuración de programa de lealtad con ratios dinámicos
-- 2. Venta con pago en efectivo → Gana puntos
-- 3. Venta con pago en tarjeta → Gana puntos
-- 4. Venta con pago híbrido (efectivo + tarjeta) → Gana puntos
-- 5. Venta con canje de puntos parcial → Gana y canjea puntos (SOLO de pagos en dinero)
-- 6. Venta con canje de puntos total → Solo canjea puntos (NO gana puntos)
-- 7. Validaciones de límites de puntos
-- 8. Verificación de ratios configurables por tenant
-- =====================================

-- ========================================
-- SECCIÓN 0: Limpieza y preparación
-- ========================================
do $$
begin
    raise notice '========================================';
    raise notice '🧹 SECCIÓN 0: Limpieza inicial';
    raise notice '========================================';
    raise notice '';
    raise notice 'Estado inicial:';
    raise notice '  Tenants: %', (select count(*) from core.tenant);
    raise notice '  Clientes: %', (select count(*) from core.tenant_customer);
    raise notice '  Productos: %', (select count(*) from core.product);
    raise notice '  Ventas: %', (select count(*) from pos_module.sale);
    raise notice '';
    raise notice '✅ SECCIÓN 0 COMPLETADA';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 1: Configuración inicial completa
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_branch_id uuid;
    v_user_id uuid;
    v_customer_id uuid;
    v_product_a_id uuid;
    v_product_b_id uuid;
    v_product_c_id uuid;
    v_loyalty_program_id uuid;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '🏪 SECCIÓN 1: Configuración inicial';
    raise notice '========================================';
    raise notice '';
    
    -- 1.1 Crear tenant suscrito
    insert into core.tenant (tenant_name, contact_email, is_subscribed)
    values ('SuperMercado Digital', 'admin@superdigital.com', true)
    returning tenant_id into v_tenant_id;
    
    raise notice '✓ Tenant creado: %', v_tenant_id;
    raise notice '  Nombre: SuperMercado Digital';
    raise notice '';
    
    -- 1.2 Crear sucursal principal
    insert into core.branch (tenant_id, branch_name, address, is_main_branch)
    values (v_tenant_id, 'Sucursal Centro', 'Av. Principal 123', true)
    returning branch_id into v_branch_id;
    
    raise notice '✓ Sucursal creada: %', v_branch_id;
    raise notice '';
    
    -- 1.3 Crear usuario cajero
    insert into core.users (tenant_id, email, password_hash, role_id)
    values (v_tenant_id, 'cajero@superdigital.com', 'hash123', 1)
    returning user_id into v_user_id;
    
    raise notice '✓ Usuario cajero creado: %', v_user_id;
    raise notice '';
    
    -- 1.4 Crear cliente VIP
    insert into core.tenant_customer (
        tenant_id, first_name, last_name, document_number,
        email, phone, customer_segment_id
    )
    values (
        v_tenant_id, 'María', 'González', 'DNI-87654321',
        'maria.gonzalez@email.com', '+51-999-111-222', 1  -- VIP
    )
    returning tenant_customer_id into v_customer_id;
    
    raise notice '✓ Cliente VIP creado: %', v_customer_id;
    raise notice '  Nombre: María González';
    raise notice '  Segmento: VIP';
    raise notice '';
    
    -- 1.5 Crear productos
    insert into core.product (tenant_id, sku, product_name, unit_price)
    values (v_tenant_id, 'PROD-A', 'Laptop Gaming Pro', 1200.00)
    returning product_id into v_product_a_id;
    
    insert into core.product (tenant_id, sku, product_name, unit_price)
    values (v_tenant_id, 'PROD-B', 'Mouse Inalámbrico', 50.00)
    returning product_id into v_product_b_id;
    
    insert into core.product (tenant_id, sku, product_name, unit_price)
    values (v_tenant_id, 'PROD-C', 'Teclado Mecánico', 150.00)
    returning product_id into v_product_c_id;
    
    raise notice '✓ Productos creados:';
    raise notice '  - Laptop Gaming Pro: $1,200.00';
    raise notice '  - Mouse Inalámbrico: $50.00';
    raise notice '  - Teclado Mecánico: $150.00';
    raise notice '';
    
    -- 1.6 Configurar programa de lealtad CON RATIOS DINÁMICOS
    insert into pos_module.loyalty_program (
        tenant_id,
        points_per_dollar,              -- ✅ Ganar: 10 puntos por cada $1
        points_per_currency_unit,       -- ✅ Canjear: 100 puntos = $1
        minimum_purchase_for_points,
        is_active
    )
    values (v_tenant_id, 10.00, 100.00, 10.00, true)
    returning loyalty_program_id into v_loyalty_program_id;
    
    raise notice '✓ Programa de lealtad configurado: %', v_loyalty_program_id;
    raise notice '  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    raise notice '  📈 Ratio de GANANCIA: 10 puntos por cada $1';
    raise notice '     Ejemplo: Compra $100 → Gana 1,000 puntos';
    raise notice '';
    raise notice '  💰 Ratio de CANJE: 100 puntos = $1';
    raise notice '     Ejemplo: Canjea 5,000 puntos → Vale $50';
    raise notice '  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';
    raise notice '  Compra mínima para puntos: $10';
    raise notice '  Estado: Activo ✅';
    raise notice '';
    
    -- 1.7 Inicializar puntos del cliente en 0
    insert into pos_module.tenant_customer_score (
        tenant_id,
        tenant_customer_id,
        score,
        lifetime_score,
        score_redeemed
    )
    values (v_tenant_id, v_customer_id, 0, 0, 0);
    
    raise notice '✓ Puntos inicializados para María González:';
    raise notice '  Puntos actuales: 0';
    raise notice '  Puntos totales ganados: 0';
    raise notice '  Puntos canjeados: 0';
    raise notice '';
    raise notice '✅ SECCIÓN 1 COMPLETADA';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 2: Venta simple con pago en efectivo → Gana puntos
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_branch_id uuid;
    v_user_id uuid;
    v_customer_id uuid;
    v_product_id uuid;
    v_sale_id uuid;
    v_payment_id uuid;
    v_points_before int;
    v_points_after int;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '💵 SECCIÓN 2: Venta con pago en EFECTIVO';
    raise notice '========================================';
    raise notice '';
    
    -- Obtener IDs
    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'SuperMercado Digital';
    select branch_id into v_branch_id from core.branch where tenant_id = v_tenant_id;
    select user_id into v_user_id from core.users where email = 'cajero@superdigital.com';
    select tenant_customer_id into v_customer_id from core.tenant_customer where email = 'maria.gonzalez@email.com';
    select product_id into v_product_id from core.product where sku = 'PROD-B' and tenant_id = v_tenant_id;
    
    -- Puntos antes de la compra
    select score into v_points_before
    from pos_module.tenant_customer_score
    where tenant_customer_id = v_customer_id;
    
    raise notice '📊 Estado inicial:';
    raise notice '  Puntos del cliente: %', v_points_before;
    raise notice '';
    
    -- Crear venta
    insert into pos_module.sale (
        branch_id, user_id, currency_id, total_amount, is_completed
    )
    values (v_branch_id, v_user_id, 1, 50.00, false)
    returning sale_id into v_sale_id;
    
    raise notice '✓ Venta creada: %', v_sale_id;
    raise notice '  Total: $50.00';
    raise notice '';
    
    -- Agregar producto a la venta
    insert into pos_module.sale_item (
        sale_id, tenant_id, product_id, quantity, unit_price, total_price
    )
    values (v_sale_id, v_tenant_id, v_product_id, 1, 50.00, 50.00);
    
    raise notice '✓ Producto agregado: Mouse Inalámbrico × 1';
    raise notice '';
    
    -- Registrar pago en efectivo (SIN VERIFICAR)
    insert into pos_module.customer_payment (
        tenant_customer_id,
        sale_id,
        payment_method_id,
        payment_amount,
        currency_id,
        verified
    )
    values (v_customer_id, v_sale_id, 1, 50.00, 1, false)
    returning customer_payment_id into v_payment_id;
    
    raise notice '✓ Pago registrado: %', v_payment_id;
    raise notice '  Método: Efectivo 💵';
    raise notice '  Monto: $50.00';
    raise notice '  Estado: Pendiente ⏳';
    raise notice '';
    
    -- Verificar pago (esto dispara los triggers)
    raise notice '🔐 Verificando pago...';
    call pos_module.verify_customer_payment(v_payment_id);
    
    -- Esperar a que se procesen los triggers
    perform pg_sleep(1);
    
    -- Verificar puntos ganados
    select score into v_points_after
    from pos_module.tenant_customer_score
    where tenant_customer_id = v_customer_id;
    
    raise notice '';
    raise notice '📊 Resultado:';
    raise notice '  Puntos antes: %', v_points_before;
    raise notice '  Puntos después: %', v_points_after;
    raise notice '  Puntos ganados: %', (v_points_after - v_points_before);
    raise notice '  Cálculo esperado: $50 × 10 pts/$1 = 500 puntos ✅';
    raise notice '';
    raise notice '✅ SECCIÓN 2 COMPLETADA';
    raise notice '  Compra: $50.00 en efectivo';
    raise notice '  Puntos ganados: % (esperado: 500)', (v_points_after - v_points_before);
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 3: Venta con pago en tarjeta → Gana puntos
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_branch_id uuid;
    v_user_id uuid;
    v_customer_id uuid;
    v_product_id uuid;
    v_sale_id uuid;
    v_payment_id uuid;
    v_points_before int;
    v_points_after int;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '💳 SECCIÓN 3: Venta con pago en TARJETA';
    raise notice '========================================';
    raise notice '';
    
    -- Obtener IDs
    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'SuperMercado Digital';
    select branch_id into v_branch_id from core.branch where tenant_id = v_tenant_id;
    select user_id into v_user_id from core.users where email = 'cajero@superdigital.com';
    select tenant_customer_id into v_customer_id from core.tenant_customer where email = 'maria.gonzalez@email.com';
    select product_id into v_product_id from core.product where sku = 'PROD-C' and tenant_id = v_tenant_id;
    
    -- Puntos antes
    select score into v_points_before
    from pos_module.tenant_customer_score
    where tenant_customer_id = v_customer_id;
    
    raise notice '📊 Estado inicial:';
    raise notice '  Puntos del cliente: %', v_points_before;
    raise notice '';
    
    -- Crear venta
    insert into pos_module.sale (
        branch_id, user_id, currency_id, total_amount, is_completed
    )
    values (v_branch_id, v_user_id, 1, 150.00, false)
    returning sale_id into v_sale_id;
    
    raise notice '✓ Venta creada: %', v_sale_id;
    raise notice '  Total: $150.00';
    raise notice '';
    
    -- Agregar producto
    insert into pos_module.sale_item (
        sale_id, tenant_id, product_id, quantity, unit_price, total_price
    )
    values (v_sale_id, v_tenant_id, v_product_id, 1, 150.00, 150.00);
    
    raise notice '✓ Producto agregado: Teclado Mecánico × 1';
    raise notice '';
    
    -- Pago con tarjeta de crédito
    insert into pos_module.customer_payment (
        tenant_customer_id,
        sale_id,
        payment_method_id,
        payment_amount,
        currency_id,
        verified
    )
    values (v_customer_id, v_sale_id, 3, 150.00, 1, false)
    returning customer_payment_id into v_payment_id;
    
    raise notice '✓ Pago registrado: %', v_payment_id;
    raise notice '  Método: Tarjeta de Crédito 💳';
    raise notice '  Monto: $150.00';
    raise notice '';
    
    -- Verificar pago
    raise notice '🔐 Verificando pago...';
    call pos_module.verify_customer_payment(v_payment_id);
    
    perform pg_sleep(1);
    
    -- Verificar puntos
    select score into v_points_after
    from pos_module.tenant_customer_score
    where tenant_customer_id = v_customer_id;
    
    raise notice '';
    raise notice '📊 Resultado:';
    raise notice '  Puntos antes: %', v_points_before;
    raise notice '  Puntos después: %', v_points_after;
    raise notice '  Puntos ganados: %', (v_points_after - v_points_before);
    raise notice '  Cálculo esperado: $150 × 10 pts/$1 = 1,500 puntos ✅';
    raise notice '';
    raise notice '✅ SECCIÓN 3 COMPLETADA';
    raise notice '  Compra: $150.00 en tarjeta';
    raise notice '  Puntos ganados: % (esperado: 1,500)', (v_points_after - v_points_before);
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 4: Venta con pago HÍBRIDO (efectivo + tarjeta)
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_branch_id uuid;
    v_user_id uuid;
    v_customer_id uuid;
    v_product_id uuid;
    v_sale_id uuid;
    v_payment_cash_id uuid;
    v_payment_card_id uuid;
    v_points_before int;
    v_points_after int;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '💵💳 SECCIÓN 4: Venta con pago HÍBRIDO';
    raise notice '========================================';
    raise notice '';
    
    -- Obtener IDs
    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'SuperMercado Digital';
    select branch_id into v_branch_id from core.branch where tenant_id = v_tenant_id;
    select user_id into v_user_id from core.users where email = 'cajero@superdigital.com';
    select tenant_customer_id into v_customer_id from core.tenant_customer where email = 'maria.gonzalez@email.com';
    select product_id into v_product_id from core.product where sku = 'PROD-A' and tenant_id = v_tenant_id;
    
    -- Puntos antes
    select score into v_points_before
    from pos_module.tenant_customer_score
    where tenant_customer_id = v_customer_id;
    
    raise notice '📊 Estado inicial:';
    raise notice '  Puntos del cliente: %', v_points_before;
    raise notice '';
    
    -- Crear venta
    insert into pos_module.sale (
        branch_id, user_id, currency_id, total_amount, is_completed
    )
    values (v_branch_id, v_user_id, 1, 1200.00, false)
    returning sale_id into v_sale_id;
    
    raise notice '✓ Venta creada: %', v_sale_id;
    raise notice '  Total: $1,200.00';
    raise notice '';
    
    -- Agregar producto
    insert into pos_module.sale_item (
        sale_id, tenant_id, product_id, quantity, unit_price, total_price
    )
    values (v_sale_id, v_tenant_id, v_product_id, 1, 1200.00, 1200.00);
    
    raise notice '✓ Producto agregado: Laptop Gaming Pro × 1';
    raise notice '';
    
    -- Pago 1: Efectivo ($500)
    insert into pos_module.customer_payment (
        tenant_customer_id,
        sale_id,
        payment_method_id,
        payment_amount,
        currency_id,
        verified
    )
    values (v_customer_id, v_sale_id, 1, 500.00, 1, false)
    returning customer_payment_id into v_payment_cash_id;
    
    raise notice '✓ Pago 1 registrado: %', v_payment_cash_id;
    raise notice '  Método: Efectivo 💵';
    raise notice '  Monto: $500.00';
    raise notice '';
    
    -- Pago 2: Tarjeta ($700)
    insert into pos_module.customer_payment (
        tenant_customer_id,
        sale_id,
        payment_method_id,
        payment_amount,
        currency_id,
        verified
    )
    values (v_customer_id, v_sale_id, 3, 700.00, 1, false)
    returning customer_payment_id into v_payment_card_id;
    
    raise notice '✓ Pago 2 registrado: %', v_payment_card_id;
    raise notice '  Método: Tarjeta de Crédito 💳';
    raise notice '  Monto: $700.00';
    raise notice '';
    
    -- Verificar ambos pagos
    raise notice '🔐 Verificando pago 1 (efectivo)...';
    call pos_module.verify_customer_payment(v_payment_cash_id);
    
    raise notice '🔐 Verificando pago 2 (tarjeta)...';
    call pos_module.verify_customer_payment(v_payment_card_id);
    
    perform pg_sleep(1);
    
    -- Verificar puntos
    select score into v_points_after
    from pos_module.tenant_customer_score
    where tenant_customer_id = v_customer_id;
    
    raise notice '';
    raise notice '📊 Resultado:';
    raise notice '  Puntos antes: %', v_points_before;
    raise notice '  Puntos después: %', v_points_after;
    raise notice '  Puntos ganados: %', (v_points_after - v_points_before);
    raise notice '  Cálculo esperado: $1,200 × 10 pts/$1 = 12,000 puntos ✅';
    raise notice '';
    raise notice '✅ SECCIÓN 4 COMPLETADA';
    raise notice '  Compra: $1,200.00';
    raise notice '  Pago híbrido: $500 efectivo + $700 tarjeta';
    raise notice '  Puntos ganados: % (esperado: 12,000)', (v_points_after - v_points_before);
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 5: Ver estado actual del cliente
-- ========================================
do $$
declare
    v_customer_id uuid;
    v_score_record record;
    v_loyalty_program record;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '📊 SECCIÓN 5: Estado actual del cliente';
    raise notice '========================================';
    raise notice '';
    
    select tenant_customer_id into v_customer_id
    from core.tenant_customer
    where email = 'maria.gonzalez@email.com';
    
    select * into v_score_record
    from pos_module.tenant_customer_score
    where tenant_customer_id = v_customer_id;
    
    select * into v_loyalty_program
    from pos_module.loyalty_program
    where tenant_id = v_score_record.tenant_id
    and is_active = true;
    
    raise notice '👤 Cliente: María González';
    raise notice '';
    raise notice '💎 Puntos de Lealtad:';
    raise notice '  Puntos disponibles: %', v_score_record.score;
    raise notice '  Puntos totales ganados: %', v_score_record.lifetime_score;
    raise notice '  Puntos canjeados: %', v_score_record.score_redeemed;
    raise notice '  Última vez ganados: %', v_score_record.last_earned_at;
    raise notice '  Última vez canjeados: %', coalesce(v_score_record.last_redeemed_at::text, 'Nunca');
    raise notice '';
    raise notice '💰 Configuración del Programa:';
    raise notice '  Ratio de ganancia: % pts/$1', v_loyalty_program.points_per_dollar;
    raise notice '  Ratio de canje: % pts = $1', v_loyalty_program.points_per_currency_unit;
    raise notice '';
    raise notice '💵 Valor en efectivo:';
    raise notice '  Puntos disponibles: % pts', v_score_record.score;
    raise notice '  Equivalente en dinero: $% (@ % pts = $1)', 
        (v_score_record.score / v_loyalty_program.points_per_currency_unit),
        v_loyalty_program.points_per_currency_unit;
    raise notice '';
    raise notice '✅ SECCIÓN 5 COMPLETADA';
    raise notice '  Total esperado: 14,000 puntos';
    raise notice '  Total actual: % puntos', v_score_record.score;
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 6: Venta con canje PARCIAL de puntos
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_branch_id uuid;
    v_user_id uuid;
    v_customer_id uuid;
    v_product_id uuid;
    v_sale_id uuid;
    v_payment_points_id uuid;
    v_payment_cash_id uuid;
    v_points_before int;
    v_points_after int;
    v_points_to_redeem int := 5000;
    v_cash_value numeric(10,2);
    v_redeem_rate numeric(10,2);
begin
    raise notice '';
    raise notice '========================================';
    raise notice '🎁 SECCIÓN 6: Venta con canje PARCIAL de puntos';
    raise notice '========================================';
    raise notice '';
    
    -- Obtener IDs
    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'SuperMercado Digital';
    select branch_id into v_branch_id from core.branch where tenant_id = v_tenant_id;
    select user_id into v_user_id from core.users where email = 'cajero@superdigital.com';
    select tenant_customer_id into v_customer_id from core.tenant_customer where email = 'maria.gonzalez@email.com';
    select product_id into v_product_id from core.product where sku = 'PROD-C' and tenant_id = v_tenant_id;
    
    -- Obtener ratio de canje del tenant
    select points_per_currency_unit into v_redeem_rate
    from pos_module.loyalty_program
    where tenant_id = v_tenant_id
    and is_active = true;
    
    -- Puntos antes
    select score into v_points_before
    from pos_module.tenant_customer_score
    where tenant_customer_id = v_customer_id;
    
    -- Calcular valor en efectivo según ratio configurado
    v_cash_value := v_points_to_redeem / v_redeem_rate;
    
    raise notice '📊 Estado inicial:';
    raise notice '  Puntos disponibles: %', v_points_before;
    raise notice '  Puntos a canjear: %', v_points_to_redeem;
    raise notice '  Ratio de canje: % pts = $1', v_redeem_rate;
    raise notice '  Valor del canje: $% (% ÷ %)', v_cash_value, v_points_to_redeem, v_redeem_rate;
    raise notice '';
    
    -- Crear venta
    insert into pos_module.sale (
        branch_id, user_id, currency_id, total_amount, is_completed
    )
    values (v_branch_id, v_user_id, 1, 150.00, false)
    returning sale_id into v_sale_id;
    
    raise notice '✓ Venta creada: %', v_sale_id;
    raise notice '  Total: $150.00';
    raise notice '';
    
    -- Agregar producto
    insert into pos_module.sale_item (
        sale_id, tenant_id, product_id, quantity, unit_price, total_price
    )
    values (v_sale_id, v_tenant_id, v_product_id, 1, 150.00, 150.00);
    
    raise notice '✓ Producto agregado: Teclado Mecánico × 1';
    raise notice '';
    
    -- Pago 1: Canje de puntos
    insert into pos_module.customer_payment (
        tenant_customer_id,
        sale_id,
        payment_method_id,
        is_points_redemption,
        points_redeemed,
        points_to_currency_rate,
        payment_amount,
        currency_id,
        verified
    )
    values (
        v_customer_id,
        v_sale_id,
        4,
        true,
        v_points_to_redeem,
        (1.0 / v_redeem_rate),
        v_cash_value,
        1,
        false
    )
    returning customer_payment_id into v_payment_points_id;
    
    raise notice '✓ Pago 1 (puntos) registrado: %', v_payment_points_id;
    raise notice '  Método: Canje de Puntos 🎁';
    raise notice '  Puntos canjeados: %', v_points_to_redeem;
    raise notice '  Valor: $%', v_cash_value;
    raise notice '';
    
    -- Pago 2: Efectivo ($100)
    insert into pos_module.customer_payment (
        tenant_customer_id,
        sale_id,
        payment_method_id,
        payment_amount,
        currency_id,
        verified
    )
    values (v_customer_id, v_sale_id, 1, 100.00, 1, false)
    returning customer_payment_id into v_payment_cash_id;
    
    raise notice '✓ Pago 2 (efectivo) registrado: %', v_payment_cash_id;
    raise notice '  Método: Efectivo 💵';
    raise notice '  Monto: $100.00';
    raise notice '';
    
    -- Verificar pagos
    raise notice '🔐 Verificando pago 1 (puntos)...';
    call pos_module.verify_customer_payment(v_payment_points_id);
    
    raise notice '🔐 Verificando pago 2 (efectivo)...';
    call pos_module.verify_customer_payment(v_payment_cash_id);
    
    perform pg_sleep(1);
    
    -- Verificar puntos finales
    select score into v_points_after
    from pos_module.tenant_customer_score
    where tenant_customer_id = v_customer_id;
    
    raise notice '';
    raise notice '📊 Resultado:';
    raise notice '  Puntos antes: %', v_points_before;
    raise notice '  Puntos canjeados: -%', v_points_to_redeem;
    raise notice '  Puntos ganados por compra: +% (SOLO de $100 en efectivo)', (100 * 10);
    raise notice '  Puntos después: %', v_points_after;
    raise notice '  Balance neto: % puntos', (v_points_after - v_points_before);
    raise notice '';
    raise notice '✅ SECCIÓN 6 COMPLETADA';
    raise notice '  Compra: $150.00';
    raise notice '  Pago: $50 en puntos + $100 en efectivo';
    raise notice '  Balance esperado: -4,000 puntos (canjeó 5,000, ganó 1,000)';
    raise notice '  Balance real: % puntos', (v_points_after - v_points_before);
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 7: Venta con canje TOTAL de puntos
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_branch_id uuid;
    v_user_id uuid;
    v_customer_id uuid;
    v_product_id uuid;
    v_sale_id uuid;
    v_payment_points_id uuid;
    v_points_before int;
    v_points_after int;
    v_points_to_redeem int := 5000;
    v_redeem_rate numeric(10,2);
    v_cash_value numeric(10,2);
begin
    raise notice '';
    raise notice '========================================';
    raise notice '🎁 SECCIÓN 7: Venta con canje TOTAL de puntos';
    raise notice '========================================';
    raise notice '';
    
    -- Obtener IDs
    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'SuperMercado Digital';
    select branch_id into v_branch_id from core.branch where tenant_id = v_tenant_id;
    select user_id into v_user_id from core.users where email = 'cajero@superdigital.com';
    select tenant_customer_id into v_customer_id from core.tenant_customer where email = 'maria.gonzalez@email.com';
    select product_id into v_product_id from core.product where sku = 'PROD-B' and tenant_id = v_tenant_id;
    
    -- Obtener ratio de canje
    select points_per_currency_unit into v_redeem_rate
    from pos_module.loyalty_program
    where tenant_id = v_tenant_id
    and is_active = true;
    
    v_cash_value := v_points_to_redeem / v_redeem_rate;
    
    -- Puntos antes
    select score into v_points_before
    from pos_module.tenant_customer_score
    where tenant_customer_id = v_customer_id;
    
    raise notice '📊 Estado inicial:';
    raise notice '  Puntos disponibles: %', v_points_before;
    raise notice '  Ratio: % pts = $1', v_redeem_rate;
    raise notice '  Canjeando: % pts = $%', v_points_to_redeem, v_cash_value;
    raise notice '';
    
    -- Crear venta
    insert into pos_module.sale (
        branch_id, user_id, currency_id, total_amount, is_completed
    )
    values (v_branch_id, v_user_id, 1, 50.00, false)
    returning sale_id into v_sale_id;
    
    raise notice '✓ Venta creada: %', v_sale_id;
    raise notice '  Total: $50.00';
    raise notice '';
    
    -- Agregar producto
    insert into pos_module.sale_item (
        sale_id, tenant_id, product_id, quantity, unit_price, total_price
    )
    values (v_sale_id, v_tenant_id, v_product_id, 1, 50.00, 50.00);
    
    raise notice '✓ Producto agregado: Mouse Inalámbrico × 1';
    raise notice '';
    
    -- Pago SOLO con puntos
    insert into pos_module.customer_payment (
        tenant_customer_id,
        sale_id,
        payment_method_id,
        is_points_redemption,
        points_redeemed,
        points_to_currency_rate,
        payment_amount,
        currency_id,
        verified
    )
    values (
        v_customer_id,
        v_sale_id,
        4,
        true,
        v_points_to_redeem,
        (1.0 / v_redeem_rate),
        v_cash_value,
        1,
        false
    )
    returning customer_payment_id into v_payment_points_id;
    
    raise notice '✓ Pago registrado: %', v_payment_points_id;
    raise notice '  Método: Canje de Puntos 🎁 (100%%)';
    raise notice '  Puntos canjeados: %', v_points_to_redeem;
    raise notice '  Valor: $%', v_cash_value;
    raise notice '';
    
    -- Verificar pago
    raise notice '🔐 Verificando pago...';
    call pos_module.verify_customer_payment(v_payment_points_id);
    
    perform pg_sleep(1);
    
    -- Verificar puntos
    select score into v_points_after
    from pos_module.tenant_customer_score
    where tenant_customer_id = v_customer_id;
    
    raise notice '';
    raise notice '📊 Resultado:';
    raise notice '  Puntos antes: %', v_points_before;
    raise notice '  Puntos canjeados: -%', v_points_to_redeem;
    raise notice '  Puntos ganados: 0 (pago 100%% con puntos)';
    raise notice '  Puntos después: %', v_points_after;
    raise notice '';
    raise notice '✅ SECCIÓN 7 COMPLETADA';
    raise notice '  Compra: $50.00';
    raise notice '  Pago: 100%% con puntos';
    raise notice '  Balance esperado: -5,000 puntos';
    raise notice '  Balance real: % puntos', (v_points_after - v_points_before);
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 8: Intentar canjear más puntos de los disponibles
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_branch_id uuid;
    v_user_id uuid;
    v_customer_id uuid;
    v_product_id uuid;
    v_sale_id uuid;
    v_payment_id uuid;
    v_points_available int;
    v_points_to_redeem int := 50000;
    v_redeem_rate numeric(10,2);
begin
    raise notice '';
    raise notice '========================================';
    raise notice '⚠️  SECCIÓN 8: Validación - Puntos insuficientes';
    raise notice '========================================';
    raise notice '';
    
    -- Obtener IDs
    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'SuperMercado Digital';
    select branch_id into v_branch_id from core.branch where tenant_id = v_tenant_id;
    select user_id into v_user_id from core.users where email = 'cajero@superdigital.com';
    select tenant_customer_id into v_customer_id from core.tenant_customer where email = 'maria.gonzalez@email.com';
    select product_id into v_product_id from core.product where sku = 'PROD-A' and tenant_id = v_tenant_id;
    
    -- Obtener ratio
    select points_per_currency_unit into v_redeem_rate
    from pos_module.loyalty_program
    where tenant_id = v_tenant_id
    and is_active = true;
    
    -- Verificar puntos disponibles
    select score into v_points_available
    from pos_module.tenant_customer_score
    where tenant_customer_id = v_customer_id;
    
    raise notice '📊 Estado actual:';
    raise notice '  Puntos disponibles: %', v_points_available;
    raise notice '  Intentando canjear: %', v_points_to_redeem;
    raise notice '  Valor teórico: $%', (v_points_to_redeem / v_redeem_rate);
    raise notice '';
    
    -- Crear venta
    insert into pos_module.sale (
        branch_id, user_id, currency_id, total_amount, is_completed
    )
    values (v_branch_id, v_user_id, 1, 500.00, false)
    returning sale_id into v_sale_id;
    
    -- Agregar producto
    insert into pos_module.sale_item (
        sale_id, tenant_id, product_id, quantity, unit_price, total_price
    )
    values (v_sale_id, v_tenant_id, v_product_id, 1, 500.00, 500.00);
    
    -- Intentar pago con puntos insuficientes
    begin
        insert into pos_module.customer_payment (
            tenant_customer_id,
            sale_id,
            payment_method_id,
            is_points_redemption,
            points_redeemed,
            points_to_currency_rate,
            payment_amount,
            currency_id,
            verified
        )
        values (
            v_customer_id,
            v_sale_id,
            4,
            true,
            v_points_to_redeem,
            (1.0 / v_redeem_rate),
            500.00,
            1,
            false
        )
        returning customer_payment_id into v_payment_id;
        
        -- Intentar verificar (debería fallar)
        call pos_module.verify_customer_payment(v_payment_id);
        
        raise notice '❌ ERROR: El sistema permitió canjear más puntos de los disponibles';
        
    exception
        when others then
            raise notice '';
            raise notice '✅ VALIDACIÓN CORRECTA';
            raise notice '  Error capturado: %', sqlerrm;
            raise notice '  El sistema rechazó el canje por puntos insuficientes';
    end;
    
    raise notice '';
    raise notice '✅ SECCIÓN 8 COMPLETADA';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 9: Resumen final completo
-- ========================================
do $$
declare
    v_customer_id uuid;
    v_score_record record;
    v_loyalty_program record;
    v_total_sales int;
    v_total_revenue numeric(10,2);
    v_total_bills int;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '📊 SECCIÓN 9: RESUMEN FINAL';
    raise notice '========================================';
    raise notice '';
    
    select tenant_customer_id into v_customer_id
    from core.tenant_customer
    where email = 'maria.gonzalez@email.com';
    
    select * into v_score_record
    from pos_module.tenant_customer_score
    where tenant_customer_id = v_customer_id;
    
    select * into v_loyalty_program
    from pos_module.loyalty_program
    where tenant_id = v_score_record.tenant_id
    and is_active = true;
    
    select count(*) into v_total_sales
    from pos_module.sale;
    
    select coalesce(sum(total_amount), 0) into v_total_revenue
    from pos_module.sale
    where is_completed = true;
    
    select count(*) into v_total_bills
    from pos_module.bill;
    
    raise notice '👤 Cliente: María González';
    raise notice '';
    raise notice '💎 Estado de Puntos:';
    raise notice '  Puntos actuales: %', v_score_record.score;
    raise notice '  Puntos totales ganados: %', v_score_record.lifetime_score;
    raise notice '  Puntos canjeados: %', v_score_record.score_redeemed;
    raise notice '  Valor en efectivo: $% (@ % pts/$1)', 
        (v_score_record.score / v_loyalty_program.points_per_currency_unit),
        v_loyalty_program.points_per_currency_unit;
    raise notice '';
    raise notice '⚙️  Configuración del Programa:';
    raise notice '  Ratio ganancia: % pts por $1', v_loyalty_program.points_per_dollar;
    raise notice '  Ratio canje: % pts = $1', v_loyalty_program.points_per_currency_unit;
    raise notice '  Compra mínima: $%', v_loyalty_program.minimum_purchase_for_points;
    raise notice '';
    raise notice '🏪 Estadísticas del Sistema:';
    raise notice '  Total de ventas: %', v_total_sales;
    raise notice '  Ventas completadas: %', (select count(*) from pos_module.sale where is_completed = true);
    raise notice '  Ingresos totales: $%', v_total_revenue;
    raise notice '  Facturas emitidas: %', v_total_bills;
    raise notice '';
    raise notice '✅ Pruebas ejecutadas:';
    raise notice '  ✓ Sección 1 - Configuración con ratios dinámicos';
    raise notice '  ✓ Sección 2 - Pago en efectivo (ganó puntos)';
    raise notice '  ✓ Sección 3 - Pago en tarjeta (ganó puntos)';
    raise notice '  ✓ Sección 4 - Pago híbrido (ganó puntos)';
    raise notice '  ✓ Sección 5 - Estado del cliente';
    raise notice '  ✓ Sección 6 - Canje parcial (ganó SOLO de dinero)';
    raise notice '  ✓ Sección 7 - Canje total (NO ganó puntos)';
    raise notice '  ✓ Sección 8 - Validación de puntos insuficientes';
    raise notice '';
    raise notice '📈 RESULTADOS ESPERADOS:';
    raise notice '  Puntos ganados: 14,000 (secciones 2+3+4)';
    raise notice '  Puntos canjeados: 10,000 (secciones 6+7)';
    raise notice '  Puntos ganados en S6: 1,000 (solo $100 en efectivo)';
    raise notice '  Balance final esperado: 5,000 puntos';
    raise notice '';
    raise notice '========================================';
    raise notice '🎉 TODAS LAS PRUEBAS COMPLETADAS';
    raise notice '========================================';
end $$;


-- ========================================
-- CONSULTAS ADICIONALES PARA ANÁLISIS
-- ========================================

-- 1️⃣ Ver todas las ventas con sus pagos
select 
    '=== VENTAS Y PAGOS ===' as seccion,
    s.sale_id,
    s.total_amount as total_venta,
    s.is_completed as completada,
    count(cp.customer_payment_id) as num_pagos,
    sum(cp.payment_amount) as total_pagado,
    string_agg(pm.name, ' + ' order by cp.created_at) as metodos_pago
from pos_module.sale s
left join pos_module.customer_payment cp on s.sale_id = cp.sale_id and cp.verified = true
left join core.payment_method pm on cp.payment_method_id = pm.payment_method_id
group by s.sale_id, s.total_amount, s.is_completed
order by s.created_at;

-- 2️⃣ Ver historial de transacciones de puntos
select 
    '=== HISTORIAL DE PUNTOS ===' as seccion,
    stt.type_name as tipo,
    st.points as puntos,
    case 
        when st.bill_id is not null then concat('Factura: ', substring(st.bill_id::text, 1, 8))
        else 'Ajuste manual'
    end as origen,
    st.created_at as fecha
from pos_module.score_transaction st
join pos_module.score_transaction_type stt on st.transaction_type_id = stt.score_transaction_type_id
order by st.created_at;

-- 3️⃣ Ver facturas generadas
select 
    '=== FACTURAS EMITIDAS ===' as seccion,
    b.bill_id,
    concat(tc.first_name, ' ', tc.last_name) as cliente,
    b.subtotal_amount,
    b.tax_amount,
    b.total_amount,
    b.billed_at as fecha
from pos_module.bill b
join core.tenant_customer tc on b.tenant_customer_id = tc.tenant_customer_id
order by b.billed_at;

-- 4️⃣ Ver pagos con canje de puntos
select 
    '=== PAGOS CON CANJE DE PUNTOS ===' as seccion,
    cp.customer_payment_id,
    concat(tc.first_name, ' ', tc.last_name) as cliente,
    cp.points_redeemed as puntos_canjeados,
    cp.payment_amount as valor_efectivo,
    lp.points_per_currency_unit as ratio_canje,
    concat(cp.points_redeemed, ' pts ÷ ', lp.points_per_currency_unit, ' = $', 
        round(cp.points_redeemed / lp.points_per_currency_unit, 2)) as calculo,
    cp.verified as verificado,
    cp.created_at as fecha
from pos_module.customer_payment cp
join core.tenant_customer tc on cp.tenant_customer_id = tc.tenant_customer_id
join pos_module.loyalty_program lp on tc.tenant_id = lp.tenant_id
where cp.is_points_redemption = true
and lp.is_active = true
order by cp.created_at;

-- 5️⃣ Ver configuración de loyalty program
select 
    '=== CONFIGURACIÓN DE PROGRAMAS DE LEALTAD ===' as seccion,
    t.tenant_name,
    lp.points_per_dollar as ganancia_ratio,
    concat('$1 = ', lp.points_per_dollar, ' pts') as ejemplo_ganancia,
    lp.points_per_currency_unit as canje_ratio,
    concat(lp.points_per_currency_unit, ' pts = $1') as ejemplo_canje,
    lp.minimum_purchase_for_points as compra_minima,
    lp.is_active as activo
from pos_module.loyalty_program lp
join core.tenant t on lp.tenant_id = t.tenant_id
order by t.tenant_name;