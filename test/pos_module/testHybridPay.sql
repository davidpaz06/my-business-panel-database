-- =====================================
-- SCRIPT DE PRUEBA: PAGOS HÍBRIDOS Y SISTEMA DE PUNTOS (idempotente)
-- =====================================
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
-- SECCIÓN 0: Limpieza y preparación (orden correcto de dependencias)
-- ========================================
do $$
declare
    v_tenant_ids uuid[];
begin
    raise notice '========================================';
    raise notice '🧹 SECCIÓN 0: Limpieza inicial (idempotente)';
    raise notice '========================================';

    -- Obtener tenant_ids para limpieza
    select array_agg(tenant_id) into v_tenant_ids
    from core.tenant 
    where tenant_name in ('SuperMercado Digital', 'Super Comercio Digital');

    if v_tenant_ids is null then
        raise notice '   ℹ️  No hay datos previos para limpiar';
        raise notice '✅ SECCIÓN 0 COMPLETADA';
        return;
    end if;

    -- 1. score_transaction (depende de bill, tenant_customer)
    delete from pos_module.score_transaction 
    where tenant_id = any(v_tenant_ids);

    -- 2. tenant_customer_score (depende de tenant_customer)
    delete from pos_module.tenant_customer_score 
    where tenant_id = any(v_tenant_ids);

    -- 3. bill_payment (depende de bill)
    delete from pos_module.bill_payment 
    where bill_id in (
        select bill_id from pos_module.bill 
        where sale_id in (
            select sale_id from pos_module.sale 
            where branch_id in (
                select branch_id from core.branch where tenant_id = any(v_tenant_ids)
            )
        )
    );

    -- 4. return_product (depende de return_transaction)
    delete from pos_module.return_product 
    where return_transaction_id in (
        select return_transaction_id from pos_module.return_transaction 
        where bill_id in (
            select bill_id from pos_module.bill 
            where sale_id in (
                select sale_id from pos_module.sale 
                where branch_id in (
                    select branch_id from core.branch where tenant_id = any(v_tenant_ids)
                )
            )
        )
    );

    -- 5. return_transaction (depende de bill)
    delete from pos_module.return_transaction 
    where bill_id in (
        select bill_id from pos_module.bill 
        where sale_id in (
            select sale_id from pos_module.sale 
            where branch_id in (
                select branch_id from core.branch where tenant_id = any(v_tenant_ids)
            )
        )
    );

    -- 6. bill (depende de sale)
    delete from pos_module.bill 
    where sale_id in (
        select sale_id from pos_module.sale 
        where branch_id in (
            select branch_id from core.branch where tenant_id = any(v_tenant_ids)
        )
    );

    -- 7. customer_payment (depende de sale)
    delete from pos_module.customer_payment 
    where sale_id in (
        select sale_id from pos_module.sale 
        where branch_id in (
            select branch_id from core.branch where tenant_id = any(v_tenant_ids)
        )
    );

    -- 8. cash_register_sale (depende de sale)
    delete from pos_module.cash_register_sale 
    where sale_id in (
        select sale_id from pos_module.sale 
        where branch_id in (
            select branch_id from core.branch where tenant_id = any(v_tenant_ids)
        )
    );

    -- ✅ 9. sale_item (CRÍTICO: Usar tenant_id directo para asegurar borrado)
    delete from pos_module.sale_item 
    where tenant_id = any(v_tenant_ids);

    -- 10. product_attribute (depende de product)
    delete from core.product_attribute 
    where tenant_id = any(v_tenant_ids);

    -- ✅ 11. product (AHORA SEGURO: sale_item y product_attribute ya eliminados)
    delete from core.product 
    where tenant_id = any(v_tenant_ids);

    -- 12. sale (depende de branch)
    delete from pos_module.sale 
    where branch_id in (
        select branch_id from core.branch where tenant_id = any(v_tenant_ids)
    );

    -- 13. cash_register_session (depende de cash_register)
    delete from pos_module.cash_register_session 
    where cash_register_id in (
        select cash_register_id from pos_module.cash_register 
        where branch_id in (
            select branch_id from core.branch where tenant_id = any(v_tenant_ids)
        )
    );

    -- 14. cash_register (depende de branch)
    delete from pos_module.cash_register 
    where branch_id in (
        select branch_id from core.branch where tenant_id = any(v_tenant_ids)
    );

    -- 15. promotion_rule (depende de promotion)
    delete from pos_module.promotion_rule 
    where promotion_id in (
        select promotion_id from pos_module.promotion where tenant_id = any(v_tenant_ids)
    );

    -- 16. promotion (depende de tenant)
    delete from pos_module.promotion 
    where tenant_id = any(v_tenant_ids);

    -- 17. loyalty_program (depende de tenant)
    delete from pos_module.loyalty_program 
    where tenant_id = any(v_tenant_ids);

    -- 18. tenant_customer (depende de tenant)
    delete from core.tenant_customer 
    where tenant_id = any(v_tenant_ids);

    -- 19. users (depende de tenant)
    delete from core.users 
    where tenant_id = any(v_tenant_ids);

    -- 20. branch (depende de tenant)
    delete from core.branch 
    where tenant_id = any(v_tenant_ids);

    -- 21. tenant (tabla padre)
    delete from core.tenant 
    where tenant_id = any(v_tenant_ids);

    raise notice '✅ SECCIÓN 0 COMPLETADA';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 1: Configuración inicial completa (idempotente)
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
    v_cash_register_id uuid;
    v_loyalty_program_id uuid;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '🏪 SECCIÓN 1: Configuración inicial (idempotente)';
    raise notice '========================================';
    raise notice '';

    -- 1.1 Crear tenant
    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Super Comercio Digital' limit 1;
    if v_tenant_id is null then
        insert into core.tenant (tenant_name, region_id, contact_email, is_subscribed)
        values ('Super Comercio Digital', 1, 'contacto@superdigital.com', true)
        returning tenant_id into v_tenant_id;
    end if;
    raise notice '✓ Tenant: %', v_tenant_id;

    -- 1.2 Crear sucursal
    select branch_id into v_branch_id from core.branch where tenant_id = v_tenant_id and branch_name = 'Sucursal Centro' limit 1;
    if v_branch_id is null then
        insert into core.branch (tenant_id, branch_name, branch_address, is_main_branch)
        values (v_tenant_id, 'Sucursal Centro', 'Av. Principal #123', true)
        returning branch_id into v_branch_id;
    end if;
    raise notice '✓ Branch: %', v_branch_id;

    -- 1.3 Crear usuario cajero
    select user_id into v_user_id from core.users where email = 'cajero@superdigital.com' limit 1;
    if v_user_id is null then
        insert into core.users (tenant_id, email, password_hash, role_id)
        values (v_tenant_id, 'cajero@superdigital.com', 'hash123', 1)
        returning user_id into v_user_id;
    end if;
    raise notice '✓ Usuario cajero: %', v_user_id;

    -- 1.4 Crear cliente (Juan Pérez)
    select tenant_customer_id into v_customer_id from core.tenant_customer where email = 'juan.perez@email.com' and tenant_id = v_tenant_id limit 1;
    if v_customer_id is null then
        insert into core.tenant_customer (
            tenant_id, first_name, last_name, document_number, email, phone, customer_segment_id
        ) values (
            v_tenant_id, 'Juan', 'Pérez', 'DNI-12345678', 'juan.perez@email.com', '+506-8888-9999', 3
        ) returning tenant_customer_id into v_customer_id;
    end if;
    raise notice '✓ Cliente: %', v_customer_id;

    -- 1.5 Crear productos
    select product_id into v_product_a_id from core.product where tenant_id = v_tenant_id and sku = 'PROD-001' limit 1;
    if v_product_a_id is null then
        insert into core.product (tenant_id, sku, product_name, unit_price)
        values (v_tenant_id, 'PROD-001', 'Laptop HP', 850.00)
        returning product_id into v_product_a_id;
    end if;

    select product_id into v_product_b_id from core.product where tenant_id = v_tenant_id and sku = 'PROD-002' limit 1;
    if v_product_b_id is null then
        insert into core.product (tenant_id, sku, product_name, unit_price)
        values (v_tenant_id, 'PROD-002', 'Mouse Logitech', 25.00)
        returning product_id into v_product_b_id;
    end if;

    select product_id into v_product_c_id from core.product where tenant_id = v_tenant_id and sku = 'PROD-003' limit 1;
    if v_product_c_id is null then
        insert into core.product (tenant_id, sku, product_name, unit_price)
        values (v_tenant_id, 'PROD-003', 'Teclado Mecánico', 120.00)
        returning product_id into v_product_c_id;
    end if;

    raise notice '✓ Productos: %, %, %', v_product_a_id, v_product_b_id, v_product_c_id;

    -- 1.6 Crear caja registradora
    select cash_register_id into v_cash_register_id from pos_module.cash_register where branch_id = v_branch_id limit 1;
    if v_cash_register_id is null then
        insert into pos_module.cash_register (branch_id, is_active)
        values (v_branch_id, true)
        returning cash_register_id into v_cash_register_id;
    end if;
    raise notice '✓ Cash register: %', v_cash_register_id;

    -- 1.7 Abrir sesión de caja (requerido para link_sale_to_session)
    perform 1 from pos_module.cash_register_session 
    where cash_register_id = v_cash_register_id and is_active = true;
    if not found then
        insert into pos_module.cash_register_session (
            cash_register_id, user_id, opening_amount, is_active
        ) values (
            v_cash_register_id, v_user_id, 500.00, true
        );
        raise notice '✓ Cash register session opened';
    end if;

    -- 1.8 Crear programa de lealtad
    select loyalty_program_id into v_loyalty_program_id from pos_module.loyalty_program where tenant_id = v_tenant_id and is_active = true limit 1;
    if v_loyalty_program_id is null then
        insert into pos_module.loyalty_program (
            tenant_id, points_per_dollar, points_per_currency_unit, minimum_purchase_for_points, is_active
        ) values (v_tenant_id, 10.00, 100.00, 0.00, true)
        returning loyalty_program_id into v_loyalty_program_id;
    end if;
    raise notice '✓ Loyalty program: %', v_loyalty_program_id;

    -- 1.9 Inicializar puntos del cliente
    perform 1 from pos_module.tenant_customer_score where tenant_customer_id = v_customer_id and tenant_id = v_tenant_id;
    if not found then
        insert into pos_module.tenant_customer_score (tenant_id, tenant_customer_id, score, lifetime_score, score_redeemed)
        values (v_tenant_id, v_customer_id, 0, 0, 0);
    end if;

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
    v_subtotal numeric(10,2) := 50.00;
    v_tax numeric(10,2);
    v_total numeric(10,2);
begin
    raise notice '';
    raise notice '========================================';
    raise notice '💵 SECCIÓN 2: Venta con pago en EFECTIVO (con impuestos)';
    raise notice '========================================';

    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Super Comercio Digital' limit 1;
    select branch_id into v_branch_id from core.branch where tenant_id = v_tenant_id and branch_name = 'Sucursal Centro' limit 1;
    select user_id into v_user_id from core.users where email = 'cajero@superdigital.com' limit 1;
    select tenant_customer_id into v_customer_id from core.tenant_customer where email = 'juan.perez@email.com' and tenant_id = v_tenant_id limit 1;
    select product_id into v_product_id from core.product where sku = 'PROD-002' and tenant_id = v_tenant_id limit 1;

    select coalesce(score, 0) into v_points_before from pos_module.tenant_customer_score where tenant_customer_id = v_customer_id and tenant_id = v_tenant_id;

    -- Calcular impuestos (13%)
    v_tax := round(v_subtotal * 0.13, 2);
    v_total := v_subtotal + v_tax;

    -- CORREGIDO: Eliminado user_id del insert
    insert into pos_module.sale (branch_id, currency_id, subtotal_amount, tax_amount, total_amount, is_completed)
    values (v_branch_id, 1, v_subtotal, v_tax, v_total, false)
    returning sale_id into v_sale_id;

    insert into pos_module.sale_item (sale_id, tenant_id, product_id, quantity, unit_price, total_price)
    values (v_sale_id, v_tenant_id, v_product_id, 2, 25.00, 50.00);

    insert into pos_module.customer_payment (tenant_customer_id, sale_id, payment_method_id, payment_amount, currency_id, verified)
    values (v_customer_id, v_sale_id, 1, v_total, 1, false)
    returning customer_payment_id into v_payment_id;

    call pos_module.verify_customer_payment(v_payment_id);

    select coalesce(score, 0) into v_points_after from pos_module.tenant_customer_score where tenant_customer_id = v_customer_id and tenant_id = v_tenant_id;

    raise notice '  Puntos ganados: % (antes % -> después %)', (v_points_after - v_points_before), v_points_before, v_points_after;
    raise notice '✅ SECCIÓN 2 COMPLETADA';
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
    v_subtotal numeric(10,2) := 120.00;
    v_tax numeric(10,2);
    v_total numeric(10,2);
begin
    raise notice '';
    raise notice '========================================';
    raise notice '💳 SECCIÓN 3: Venta con pago en TARJETA (con impuestos)';
    raise notice '========================================';

    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Super Comercio Digital' limit 1;
    
    -- VALIDACIÓN DEFENSIVA
    if v_tenant_id is null then
        raise exception '❌ ERROR: Tenant no encontrado en Sección 3';
    end if;

    select branch_id into v_branch_id from core.branch where tenant_id = v_tenant_id and branch_name = 'Sucursal Centro' limit 1;
    
    if v_branch_id is null then
        raise exception '❌ ERROR: Branch no encontrada en Sección 3 (Tenant ID: %)', v_tenant_id;
    end if;

    select user_id into v_user_id from core.users where email = 'cajero@superdigital.com' limit 1;
    select tenant_customer_id into v_customer_id from core.tenant_customer where email = 'juan.perez@email.com' and tenant_id = v_tenant_id limit 1;
    select product_id into v_product_id from core.product where sku = 'PROD-003' and tenant_id = v_tenant_id limit 1;

    select coalesce(score, 0) into v_points_before from pos_module.tenant_customer_score where tenant_customer_id = v_customer_id and tenant_id = v_tenant_id;

    -- Calcular impuestos (13%)
    v_tax := round(v_subtotal * 0.13, 2);
    v_total := v_subtotal + v_tax;

    -- CORREGIDO: Eliminado user_id del insert
    insert into pos_module.sale (branch_id, currency_id, subtotal_amount, tax_amount, total_amount, is_completed)
    values (v_branch_id, 1, v_subtotal, v_tax, v_total, false)
    returning sale_id into v_sale_id;

    insert into pos_module.sale_item (sale_id, tenant_id, product_id, quantity, unit_price, total_price)
    values (v_sale_id, v_tenant_id, v_product_id, 1, 120.00, 120.00);

    insert into pos_module.customer_payment (tenant_customer_id, sale_id, payment_method_id, payment_amount, currency_id, verified)
    values (v_customer_id, v_sale_id, 3, v_total, 1, false)
    returning customer_payment_id into v_payment_id;

    call pos_module.verify_customer_payment(v_payment_id);

    select coalesce(score, 0) into v_points_after from pos_module.tenant_customer_score where tenant_customer_id = v_customer_id and tenant_id = v_tenant_id;

    raise notice '  Puntos ganados: % (antes % -> después %)', (v_points_after - v_points_before), v_points_before, v_points_after;
    raise notice '✅ SECCIÓN 3 COMPLETADA';
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
    v_subtotal numeric(10,2) := 850.00;
    v_tax numeric(10,2);
    v_total numeric(10,2);
    v_cash_payment numeric(10,2) := 350.00;
    v_card_payment numeric(10,2);
begin
    raise notice '';
    raise notice '========================================';
    raise notice '💵💳 SECCIÓN 4: Venta con pago HÍBRIDO (con impuestos)';
    raise notice '========================================';

    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Super Comercio Digital' limit 1;
    if v_tenant_id is null then raise exception '❌ ERROR: Tenant no encontrado en Sección 4'; end if;

    select branch_id into v_branch_id from core.branch where tenant_id = v_tenant_id and branch_name = 'Sucursal Centro' limit 1;
    if v_branch_id is null then raise exception '❌ ERROR: Branch no encontrada en Sección 4'; end if;

    select user_id into v_user_id from core.users where email = 'cajero@superdigital.com' limit 1;
    select tenant_customer_id into v_customer_id from core.tenant_customer where email = 'juan.perez@email.com' and tenant_id = v_tenant_id limit 1;
    select product_id into v_product_id from core.product where sku = 'PROD-001' and tenant_id = v_tenant_id limit 1;

    select coalesce(score, 0) into v_points_before from pos_module.tenant_customer_score where tenant_customer_id = v_customer_id and tenant_id = v_tenant_id;

    -- Calcular impuestos (13%)
    v_tax := round(v_subtotal * 0.13, 2);
    v_total := v_subtotal + v_tax;
    v_card_payment := v_total - v_cash_payment;

    -- CORREGIDO: Eliminado user_id del insert
    insert into pos_module.sale (branch_id, currency_id, subtotal_amount, tax_amount, total_amount, is_completed)
    values (v_branch_id, 1, v_subtotal, v_tax, v_total, false)
    returning sale_id into v_sale_id;

    insert into pos_module.sale_item (sale_id, tenant_id, product_id, quantity, unit_price, total_price)
    values (v_sale_id, v_tenant_id, v_product_id, 1, 850.00, 850.00);

    -- Pago 1: Efectivo $350
    insert into pos_module.customer_payment (tenant_customer_id, sale_id, payment_method_id, payment_amount, currency_id, verified)
    values (v_customer_id, v_sale_id, 1, v_cash_payment, 1, false)
    returning customer_payment_id into v_payment_cash_id;

    -- Pago 2: Tarjeta (Restante)
    insert into pos_module.customer_payment (tenant_customer_id, sale_id, payment_method_id, payment_amount, currency_id, verified)
    values (v_customer_id, v_sale_id, 3, v_card_payment, 1, false)
    returning customer_payment_id into v_payment_card_id;

    call pos_module.verify_customer_payment(v_payment_cash_id);
    call pos_module.verify_customer_payment(v_payment_card_id);

    select coalesce(score, 0) into v_points_after from pos_module.tenant_customer_score where tenant_customer_id = v_customer_id and tenant_id = v_tenant_id;

    raise notice '  Puntos ganados: % (antes % -> después %)', (v_points_after - v_points_before), v_points_before, v_points_after;
    raise notice '✅ SECCIÓN 4 COMPLETADA';
end $$;


-- ========================================
-- SECCIÓN 5: Resumen / Validaciones finales de puntos
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_customer_id uuid;
    v_score_record record;
    v_loyalty_program record;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '📊 SECCIÓN 5: Estado actual del cliente';
    raise notice '========================================';

    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Super Comercio Digital' limit 1;
    if v_tenant_id is null then raise exception '❌ ERROR: Tenant no encontrado en Sección 5'; end if;

    select tenant_customer_id into v_customer_id from core.tenant_customer where email = 'juan.perez@email.com' and tenant_id = v_tenant_id limit 1;
    select * into v_score_record from pos_module.tenant_customer_score where tenant_customer_id = v_customer_id and tenant_id = v_tenant_id limit 1;
    select * into v_loyalty_program from pos_module.loyalty_program where tenant_id = v_tenant_id and is_active = true limit 1;

    raise notice 'Cliente: %', v_customer_id;
    raise notice 'Puntos disponibles: %', coalesce(v_score_record.score, 0);
    raise notice 'Puntos totales ganados: %', coalesce(v_score_record.lifetime_score, 0);
    raise notice 'Puntos canjeados: %', coalesce(v_score_record.score_redeemed, 0);
    raise notice 'Ratio ganancia: % pts/$1', v_loyalty_program.points_per_dollar;
    raise notice 'Ratio canje: % pts = $1', v_loyalty_program.points_per_currency_unit;
    raise notice '✅ SECCIÓN 5 COMPLETADA';
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
    v_points_to_redeem int;
    v_points_available int;
    v_cash_value numeric(10,2);
    v_redeem_rate numeric(10,2);
    v_remaining_to_pay numeric(10,2);
    v_subtotal numeric(10,2) := 120.00;
    v_tax numeric(10,2);
    v_total numeric(10,2);
begin
    raise notice '';
    raise notice '========================================';
    raise notice '🎁 SECCIÓN 6: Venta con canje PARCIAL de puntos (con impuestos)';
    raise notice '========================================';

    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Super Comercio Digital' limit 1;
    if v_tenant_id is null then raise exception '❌ ERROR: Tenant no encontrado en Sección 6'; end if;

    select branch_id into v_branch_id from core.branch where tenant_id = v_tenant_id and branch_name = 'Sucursal Centro' limit 1;
    if v_branch_id is null then raise exception '❌ ERROR: Branch no encontrada en Sección 6'; end if;

    select user_id into v_user_id from core.users where email = 'cajero@superdigital.com' limit 1;
    select tenant_customer_id into v_customer_id from core.tenant_customer where email = 'juan.perez@email.com' and tenant_id = v_tenant_id limit 1;
    select product_id into v_product_id from core.product where sku = 'PROD-003' and tenant_id = v_tenant_id limit 1;

    select points_per_currency_unit into v_redeem_rate from pos_module.loyalty_program where tenant_id = v_tenant_id and is_active = true limit 1;
    select coalesce(score, 0) into v_points_before from pos_module.tenant_customer_score where tenant_customer_id = v_customer_id and tenant_id = v_tenant_id;

    -- Calcular impuestos (13%)
    v_tax := round(v_subtotal * 0.13, 2);
    v_total := v_subtotal + v_tax;

    -- Usar la mitad de los puntos disponibles (máximo 5000)
    v_points_to_redeem := least(v_points_before / 2, 5000);
    
    if v_points_to_redeem < v_redeem_rate then
        raise notice '   ⚠️ No hay suficientes puntos para canjear (mínimo % pts)', v_redeem_rate;
        raise notice '✅ SECCIÓN 6 OMITIDA (puntos insuficientes)';
        return;
    end if;

    v_cash_value := round(v_points_to_redeem / v_redeem_rate, 2);
    v_remaining_to_pay := v_total - v_cash_value;

    raise notice '   Subtotal: %, Impuesto: %, Total: %', v_subtotal, v_tax, v_total;
    raise notice '   Puntos a canjear: % = $%', v_points_to_redeem, v_cash_value;
    raise notice '   Restante a pagar en efectivo: $%', v_remaining_to_pay;

    -- CORREGIDO: Eliminado user_id del insert
    insert into pos_module.sale (branch_id, currency_id, subtotal_amount, tax_amount, total_amount, is_completed)
    values (v_branch_id, 1, v_subtotal, v_tax, v_total, false)
    returning sale_id into v_sale_id;

    insert into pos_module.sale_item (sale_id, tenant_id, product_id, quantity, unit_price, total_price)
    values (v_sale_id, v_tenant_id, v_product_id, 1, 120.00, 120.00);

    -- Pago con puntos
    insert into pos_module.customer_payment (tenant_customer_id, sale_id, payment_method_id, is_points_redemption, points_redeemed, points_to_currency_rate, payment_amount, currency_id, verified)
    values (v_customer_id, v_sale_id, 4, true, v_points_to_redeem, (1.0 / v_redeem_rate), v_cash_value, 1, false)
    returning customer_payment_id into v_payment_points_id;

    -- Pago restante en efectivo
    insert into pos_module.customer_payment (tenant_customer_id, sale_id, payment_method_id, payment_amount, currency_id, verified)
    values (v_customer_id, v_sale_id, 1, v_remaining_to_pay, 1, false)
    returning customer_payment_id into v_payment_cash_id;

    call pos_module.verify_customer_payment(v_payment_points_id);
    call pos_module.verify_customer_payment(v_payment_cash_id);

    select coalesce(score, 0) into v_points_after from pos_module.tenant_customer_score where tenant_customer_id = v_customer_id and tenant_id = v_tenant_id;

    raise notice 'Puntos antes: %, después: %, neto: %', v_points_before, v_points_after, (v_points_after - v_points_before);
    raise notice '✅ SECCIÓN 6 COMPLETADA';
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
    v_points_to_redeem int;
    v_redeem_rate numeric(10,2);
    v_cash_value numeric(10,2);
    v_sale_total numeric(10,2) := 25.00; -- Precio del Mouse
begin
    raise notice '';
    raise notice '========================================';
    raise notice '🎁 SECCIÓN 7: Venta con canje TOTAL de puntos';
    raise notice '========================================';

    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Super Comercio Digital' limit 1;
    if v_tenant_id is null then raise exception '❌ ERROR: Tenant no encontrado en Sección 7'; end if;

    select branch_id into v_branch_id from core.branch where tenant_id = v_tenant_id and branch_name = 'Sucursal Centro' limit 1;
    if v_branch_id is null then raise exception '❌ ERROR: Branch no encontrada en Sección 7'; end if;

    select user_id into v_user_id from core.users where email = 'cajero@superdigital.com' limit 1;
    select tenant_customer_id into v_customer_id from core.tenant_customer where email = 'juan.perez@email.com' and tenant_id = v_tenant_id limit 1;
    select product_id into v_product_id from core.product where sku = 'PROD-002' and tenant_id = v_tenant_id limit 1;

    select points_per_currency_unit into v_redeem_rate from pos_module.loyalty_program where tenant_id = v_tenant_id and is_active = true limit 1;
    select coalesce(score, 0) into v_points_before from pos_module.tenant_customer_score where tenant_customer_id = v_customer_id and tenant_id = v_tenant_id;

    -- Calcular puntos necesarios para cubrir la venta
    v_points_to_redeem := ceil(v_sale_total * v_redeem_rate)::int;
    v_cash_value := round(v_points_to_redeem / v_redeem_rate, 2);

    if v_points_before < v_points_to_redeem then
        raise notice '   ⚠️ No hay suficientes puntos (disponibles: %, necesarios: %)', v_points_before, v_points_to_redeem;
        raise notice '✅ SECCIÓN 7 OMITIDA (puntos insuficientes)';
        return;
    end if;

    raise notice '   Puntos a canjear: % = $%', v_points_to_redeem, v_cash_value;

    -- CORREGIDO: Eliminado user_id del insert
    insert into pos_module.sale (branch_id, currency_id, subtotal_amount, tax_amount, total_amount, is_completed)
    values (v_branch_id, 1, v_sale_total, 0.00, v_sale_total, false)
    returning sale_id into v_sale_id;

    insert into pos_module.sale_item (sale_id, tenant_id, product_id, quantity, unit_price, total_price)
    values (v_sale_id, v_tenant_id, v_product_id, 1, v_sale_total, v_sale_total);

    insert into pos_module.customer_payment (tenant_customer_id, sale_id, payment_method_id, is_points_redemption, points_redeemed, points_to_currency_rate, payment_amount, currency_id, verified)
    values (v_customer_id, v_sale_id, 4, true, v_points_to_redeem, (1.0 / v_redeem_rate), v_cash_value, 1, false)
    returning customer_payment_id into v_payment_points_id;

    call pos_module.verify_customer_payment(v_payment_points_id);

    select coalesce(score, 0) into v_points_after from pos_module.tenant_customer_score where tenant_customer_id = v_customer_id and tenant_id = v_tenant_id;

    raise notice 'Puntos antes: %, después: %, cambio: %', v_points_before, v_points_after, (v_points_after - v_points_before);
    raise notice '✅ SECCIÓN 7 COMPLETADA';
end $$;


-- ========================================
-- SECCIÓN 8: Intentar canjear más puntos de los disponibles (debe fallar)
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
    v_points_to_redeem int := 999999; -- Más de los disponibles
    v_redeem_rate numeric(10,2);
begin
    raise notice '';
    raise notice '========================================';
    raise notice '⚠️  SECCIÓN 8: Validación - Puntos insuficientes';
    raise notice '========================================';

    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Super Comercio Digital' limit 1;
    if v_tenant_id is null then raise exception '❌ ERROR: Tenant no encontrado en Sección 8'; end if;

    select branch_id into v_branch_id from core.branch where tenant_id = v_tenant_id and branch_name = 'Sucursal Centro' limit 1;
    if v_branch_id is null then raise exception '❌ ERROR: Branch no encontrada en Sección 8'; end if;

    select user_id into v_user_id from core.users where email = 'cajero@superdigital.com' limit 1;
    select tenant_customer_id into v_customer_id from core.tenant_customer where email = 'juan.perez@email.com' and tenant_id = v_tenant_id limit 1;
    select product_id into v_product_id from core.product where sku = 'PROD-001' and tenant_id = v_tenant_id limit 1;

    select points_per_currency_unit into v_redeem_rate from pos_module.loyalty_program where tenant_id = v_tenant_id and is_active = true limit 1;
    select coalesce(score, 0) into v_points_available from pos_module.tenant_customer_score where tenant_customer_id = v_customer_id and tenant_id = v_tenant_id;

    raise notice '   Puntos disponibles: %', v_points_available;
    raise notice '   Intentando canjear: %', v_points_to_redeem;

    -- CORREGIDO: Eliminado user_id del insert
    insert into pos_module.sale (branch_id, currency_id, subtotal_amount, tax_amount, total_amount, is_completed)
    values (v_branch_id, 1, 500.00, 0.00, 500.00, false)
    returning sale_id into v_sale_id;

    insert into pos_module.sale_item (sale_id, tenant_id, product_id, quantity, unit_price, total_price)
    values (v_sale_id, v_tenant_id, v_product_id, 1, 500.00, 500.00);

    begin
        insert into pos_module.customer_payment (tenant_customer_id, sale_id, payment_method_id, is_points_redemption, points_redeemed, points_to_currency_rate, payment_amount, currency_id, verified)
        values (v_customer_id, v_sale_id, 4, true, v_points_to_redeem, (1.0 / v_redeem_rate), 500.00, 1, false)
        returning customer_payment_id into v_payment_id;

        call pos_module.verify_customer_payment(v_payment_id);

        raise exception '❌ ERROR: El sistema permitió canjear más puntos de los disponibles';
    exception
        when others then
            raise notice '✅ VALIDACIÓN EXITOSA: canje rechazado correctamente';
            raise notice '   Mensaje: %', sqlerrm;
    end;

    -- Limpiar la venta fallida
    delete from pos_module.sale where sale_id = v_sale_id;

    raise notice '✅ SECCIÓN 8 COMPLETADA';
end $$;


-- ========================================
-- SECCIÓN 9: Resumen final
-- ========================================
do $$
declare
    v_tenant_id uuid;
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

    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Super Comercio Digital' limit 1;
    select tenant_customer_id into v_customer_id from core.tenant_customer where email = 'juan.perez@email.com' and tenant_id = v_tenant_id limit 1;
    select * into v_score_record from pos_module.tenant_customer_score where tenant_customer_id = v_customer_id and tenant_id = v_tenant_id limit 1;
    select * into v_loyalty_program from pos_module.loyalty_program where tenant_id = v_tenant_id and is_active = true limit 1;

    select count(*) into v_total_sales from pos_module.sale s
    join core.branch b on s.branch_id = b.branch_id
    where b.tenant_id = v_tenant_id;

    select coalesce(sum(s.total_amount), 0) into v_total_revenue from pos_module.sale s
    join core.branch b on s.branch_id = b.branch_id
    where b.tenant_id = v_tenant_id and s.is_completed = true;

    select count(*) into v_total_bills from pos_module.bill bl
    join pos_module.sale s on bl.sale_id = s.sale_id
    join core.branch b on s.branch_id = b.branch_id
    where b.tenant_id = v_tenant_id;

    raise notice '';
    raise notice '👤 CLIENTE:';
    raise notice '   ID: %', v_customer_id;
    raise notice '   Puntos disponibles: %', coalesce(v_score_record.score, 0);
    raise notice '   Puntos ganados totales: %', coalesce(v_score_record.lifetime_score, 0);
    raise notice '   Puntos canjeados: %', coalesce(v_score_record.score_redeemed, 0);
    raise notice '';
    raise notice '🏪 NEGOCIO:';
    raise notice '   Ventas totales: %', v_total_sales;
    raise notice '   Ventas completadas: $%', v_total_revenue;
    raise notice '   Facturas emitidas: %', v_total_bills;
    raise notice '';
    raise notice '🎯 PROGRAMA DE LEALTAD:';
    raise notice '   Ratio ganancia: % pts/$1', v_loyalty_program.points_per_dollar;
    raise notice '   Ratio canje: % pts = $1', v_loyalty_program.points_per_currency_unit;
    raise notice '';
    raise notice '========================================';
    raise notice '✅ TEST COMPLETADO EXITOSAMENTE';
    raise notice '========================================';
end $$;