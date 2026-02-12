-- ============================================
-- TEST DE PROMOCIONES (IDEMPOTENTE)
-- Objetivo: demostrar promos por producto y por grupo (categoría)
-- Requisitos: usar las funciones y triggers del esquema (main.sql)
-- Ejecutar desde psql: \i testPromos_repeat.sql
-- ============================================

set search_path = general_schema, pos_schema;

-- ============================================
-- SECCIÓN 0: Limpieza idempotente (eliminar tenant de prueba si existe)
-- ============================================
DO $$
declare
    v_tenant_id uuid;
BEGIN
    select tenant_id into v_tenant_id from general_schema.tenant where tenant_name = 'Promos Test Shop' limit 1;
    if v_tenant_id is not null then
        RAISE NOTICE '%', format('🧹 Cleaning previous test tenant: %s', v_tenant_id);
        
        -- eliminar dependencias en orden seguro (sale_item antes de product)
        delete from pos_schema.bill_payment bp
        where bp.bill_id in (
            select b.bill_id from pos_schema.bill b
            join pos_schema.sale s on b.sale_id = s.sale_id
            join general_schema.branch br on s.branch_id = br.branch_id
            where br.tenant_id = v_tenant_id
        );

        delete from pos_schema.bill where sale_id in (
            select s.sale_id from pos_schema.sale s
            join general_schema.branch br on s.branch_id = br.branch_id
            where br.tenant_id = v_tenant_id
        );

        delete from pos_schema.customer_payment where sale_id in (
            select s.sale_id from pos_schema.sale s
            join general_schema.branch br on s.branch_id = br.branch_id
            where br.tenant_id = v_tenant_id
        );

        delete from pos_schema.sale_item where sale_id in (
            select s.sale_id from pos_schema.sale s
            join general_schema.branch br on s.branch_id = br.branch_id
            where br.tenant_id = v_tenant_id
        );

        delete from pos_schema.sale where branch_id in (
            select branch_id from general_schema.branch where tenant_id = v_tenant_id
        );

        delete from pos_schema.cash_register_sale where cash_register_session_id in (
            select cash_register_session_id from pos_schema.cash_register_session
            where cash_register_id in (
                select cash_register_id from pos_schema.cash_register
                where branch_id in (select branch_id from general_schema.branch where tenant_id = v_tenant_id)
            )
        );

        delete from pos_schema.cash_register_session where cash_register_id in (
            select cash_register_id from pos_schema.cash_register
            where branch_id in (select branch_id from general_schema.branch where tenant_id = v_tenant_id)
        );

        delete from pos_schema.cash_register where branch_id in (
            select branch_id from general_schema.branch where tenant_id = v_tenant_id
        );

        delete from pos_schema.promotion_rule where promotion_id in (
            select promotion_id from pos_schema.promotion where tenant_id = v_tenant_id
        );
        delete from pos_schema.promotion where tenant_id = v_tenant_id;

        delete from pos_schema.loyalty_program where tenant_id = v_tenant_id;
        delete from pos_schema.tenant_customer_score where tenant_id = v_tenant_id;
        delete from pos_schema.score_transaction where tenant_id = v_tenant_id;

        delete from general_schema.attribute_assignation where tenant_id = v_tenant_id;
        delete from general_schema.product_variant where tenant_id = v_tenant_id;
        DELETE FROM general_schema.product WHERE cabys_code LIKE 'PRTEST%';

        delete from general_schema.tenant_customer where tenant_id = v_tenant_id;
        delete from general_schema.users where tenant_id = v_tenant_id;
        delete from general_schema.branch where tenant_id = v_tenant_id;

        -- finalmente borrar tenant
        delete from general_schema.tenant where tenant_id = v_tenant_id;

        RAISE NOTICE '%', format('✅ Previous test data removed');
    else
        RAISE NOTICE '%', format('ℹ️  No previous test tenant found');
    end if;
end $$;


-- ============================================
-- SECCIÓN 1: Crear tenant, branch, cliente y productos (idempotente)
-- ============================================
DO $$
declare
    v_tenant_id uuid;
    v_branch_id uuid;
    v_customer_id uuid;
    v_prod_a uuid;
    v_prod_b uuid;
    v_prod_c uuid;
    v_currency_id int;
    v_payment_method_id int;
BEGIN
    RAISE NOTICE '%', format('🏗️  SECCIÓN 1: Creación de datos maestros');

    -- Tenant
    INSERT INTO general_schema.tenant(tenant_name, contact_email, region_id, is_subscribed)
    VALUES ('Promos Test Shop', 'promos@testshop.local', (select region_id from general_schema.region limit 1), false)
    returning tenant_id into v_tenant_id;
    if v_tenant_id is null then
        select tenant_id into v_tenant_id from general_schema.tenant where tenant_name = 'Promos Test Shop' limit 1;
    end if;
    RAISE NOTICE '%', format('  Tenant: %s', v_tenant_id);

    -- Branch
    INSERT INTO general_schema.branch (tenant_id, branch_name, branch_address, is_main_branch)
    VALUES (v_tenant_id, 'Main Branch', 'Address Test', true)
    returning branch_id into v_branch_id;
    if v_branch_id is null then
        select branch_id into v_branch_id from general_schema.branch where tenant_id = v_tenant_id and branch_name = 'Main Branch' limit 1;
    end if;
    RAISE NOTICE '%', format('  Branch: %s', v_branch_id);

    -- Customer
    INSERT INTO general_schema.tenant_customer(
        tenant_id, first_name, last_name, document_number, email, phone, customer_segment_id
    ) VALUES (
        v_tenant_id, 'Test', 'Cliente', 'PT-001', 'test.client@promos.local', '+000-000-000', 3
    ) returning tenant_customer_id into v_customer_id;
    if v_customer_id is null then
        select tenant_customer_id into v_customer_id from general_schema.tenant_customer where tenant_id = v_tenant_id and email = 'test.client@promos.local' limit 1;
    end if;
    RAISE NOTICE '%', format('  Customer: %s', v_customer_id);

    -- Productos: catálogo CABYS controlado para las pruebas
    -- A: Laptop (categoria Electronics), B: Mouse, C: Cable (misma categoría B y C para demo de grupo)
    INSERT INTO general_schema.product (cabys_code, product_name)
    VALUES ('PRTEST0000001', 'Productos de prueba promos')
    ON CONFLICT (cabys_code) DO NOTHING;

    INSERT INTO general_schema.product_variant (tenant_id, cabys_code, sku, variant_name, unit_price, is_active)
    VALUES (v_tenant_id, 'PRTEST0000001', 'PR-A', 'Laptop Test', 1000.00, true)
    returning product_variant_id into v_prod_a;
    if v_prod_a is null then
        select product_variant_id into v_prod_a from general_schema.product_variant where tenant_id = v_tenant_id and sku = 'PR-A' limit 1;
    end if;

    INSERT INTO general_schema.product_variant (tenant_id, cabys_code, sku, variant_name, unit_price, is_active)
    VALUES (v_tenant_id, 'PRTEST0000001', 'PR-B', 'Mouse Test', 100.00, true)
    returning product_variant_id into v_prod_b;
    if v_prod_b is null then
        select product_variant_id into v_prod_b from general_schema.product_variant where tenant_id = v_tenant_id and sku = 'PR-B' limit 1;
    end if;

    INSERT INTO general_schema.product_variant (tenant_id, cabys_code, sku, variant_name, unit_price, is_active)
    VALUES (v_tenant_id, 'PRTEST0000001', 'PR-C', 'Cable Test', 50.00, true)
    returning product_variant_id into v_prod_c;
    if v_prod_c is null then
        select product_variant_id into v_prod_c from general_schema.product_variant where tenant_id = v_tenant_id and sku = 'PR-C' limit 1;
    end if;

    RAISE NOTICE '%', format('  Products created: A=%s B=%s C=%s', v_prod_a, v_prod_b, v_prod_c);

    -- currency and payment_method safe-retrieval (fall back to any existing)
    select currency_id into v_currency_id from general_schema.currency limit 1;
    if v_currency_id is null then
        INSERT INTO general_schema.currency(currency_id_code, currency_name, symbol, exchange_rate_to_usd)
        VALUES ('USD', 'US Dollar', '$', 1.0)
        returning currency_id into v_currency_id;
    end if;

    select payment_method_id into v_payment_method_id from general_schema.payment_method where name = 'cash' limit 1;
    if v_payment_method_id is null then
        INSERT INTO general_schema.payment_method(name, description) VALUES ('cash', 'Cash payment') returning payment_method_id into v_payment_method_id;
    end if;

    RAISE NOTICE '%', format('  Currency id: %s, Cash payment_method_id: %s', v_currency_id, v_payment_method_id);

    RAISE NOTICE '%', format('✅ SECCIÓN 1 completada');
end $$;


-- ============================================
-- SECCIÓN 2: Venta BASE (sin promoción) - pago contado y verificado
-- - misma canasta será reutilizada para pruebas de promos
-- ============================================
DO $$
declare
    v_tenant_id uuid := (select tenant_id from general_schema.tenant where tenant_name = 'Promos Test Shop' limit 1);
    v_branch_id uuid := (select branch_id from general_schema.branch where tenant_id = v_tenant_id limit 1);
    v_customer_id uuid := (select tenant_customer_id from general_schema.tenant_customer where tenant_id = v_tenant_id limit 1);
    v_prod_a uuid := (select product_variant_id from general_schema.product_variant where tenant_id = v_tenant_id and sku = 'PR-A' limit 1);
    v_prod_b uuid := (select product_variant_id from general_schema.product_variant where tenant_id = v_tenant_id and sku = 'PR-B' limit 1);
    v_prod_c uuid := (select product_variant_id from general_schema.product_variant where tenant_id = v_tenant_id and sku = 'PR-C' limit 1);
    v_sale_id uuid;
    v_payment_id uuid;
    v_currency_id int := (select currency_id from general_schema.currency limit 1);
    v_payment_method_id int := (select payment_method_id from general_schema.payment_method where name = 'cash' limit 1);
    v_subtotal numeric(12,2);
    v_tax_rate numeric(5,2) := coalesce((select rate_percentage from general_schema.tax_rate where region = 'US Federal' limit 1), 0);
    v_tax numeric(12,2);
    v_total numeric(12,2);
BEGIN
    RAISE NOTICE '%', format('🛒 SECCIÓN 2: Creating base sale (no promo)');

    -- Remove any previous sales/payments for this tenant to keep idempotence at sale-level
    delete from pos_schema.bill_payment bp where bp.bill_id in (select b.bill_id from pos_schema.bill b join pos_schema.sale s on b.sale_id = s.sale_id join general_schema.branch br on s.branch_id = br.branch_id where br.tenant_id = v_tenant_id);
    delete from pos_schema.bill where sale_id in (select s.sale_id from pos_schema.sale s join general_schema.branch br on s.branch_id = br.branch_id where br.tenant_id = v_tenant_id);
    delete from pos_schema.customer_payment where sale_id in (select s.sale_id from pos_schema.sale s join general_schema.branch br on s.branch_id = br.branch_id where br.tenant_id = v_tenant_id);
    delete from pos_schema.sale_item where sale_id in (select s.sale_id from pos_schema.sale s join general_schema.branch br on s.branch_id = br.branch_id where br.tenant_id = v_tenant_id);
    delete from pos_schema.sale where branch_id in (select branch_id from general_schema.branch where tenant_id = v_tenant_id);

    -- Sale composition (same for all promo tests)
    -- 1 x Laptop ($1000) + 2 x Mouse ($50) + 3 x Cable ($10)
    v_subtotal := 1 * 1000.00 + 2 * 50.00 + 3 * 10.00;
    v_tax := round(v_subtotal * (v_tax_rate / 100), 2);
    v_total := v_subtotal + v_tax;

    INSERT INTO pos_schema.sale(branch_id, currency_id, subtotal_amount, tax_amount, total_amount, is_completed)
    VALUES (v_branch_id, v_currency_id, v_subtotal, v_tax, v_total, false)
    returning sale_id into v_sale_id;

    -- sale items (tenant_id required)
    INSERT INTO pos_schema.sale_item(sale_id, tenant_id, product_variant_id, quantity, unit_price, total_price)
    VALUES
        (v_sale_id, v_tenant_id, v_prod_a, 1, 1000.00, 1000.00),
        (v_sale_id, v_tenant_id, v_prod_b, 2, 50.00, 100.00),
        (v_sale_id, v_tenant_id, v_prod_c, 3, 10.00, 30.00);

    -- create a customer_payment and verify it (cash)
    INSERT INTO pos_schema.customer_payment(tenant_customer_id, sale_id, payment_method_id, payment_amount, currency_id, verified)
    VALUES (v_customer_id, v_sale_id, v_payment_method_id, v_total, v_currency_id, false)
    returning customer_payment_id into v_payment_id;

    -- Use the existing procedure to verify (this will mark sale completed and create bill)
    call pos_schema.verify_customer_payment(v_payment_id);
    perform pg_sleep(0.2);

    RAISE NOTICE '%', format('  Base sale created: sale_id=%s payment_id=%s subtotal=$%s tax=$%s total=$%s', v_sale_id, v_payment_id, v_subtotal, v_tax, v_total);

    RAISE NOTICE '%', format('✅ SECCIÓN 2 completada - Base sale ready');
end $$;


-- ============================================
-- Helper: función local para crear promoción y regla
-- ============================================
-- Not created as permanent DB function; se usa un DO block por cada promo.


-- ============================================
-- SECCIÓN 3: Crear promociones por tipo y probarlas
-- Para cada promoción:
--  - crear promotion + rule
--  - calcular descuento con pos_schema.calculate_promotion_discount
--  - simular venta idéntica a la base pero cobrando monto = subtotal - descuento
--  - verificar factura resultante
-- ============================================

-- Lista de pruebas: percentage, fixed, buy_x_get_y, volume, tiered_pricing, combo (combo no aplica a un solo producto)
-- Nota: promotion_type ids se obtienen por name (seguro con los inserts del esquema)

-- 3.1 Descuento porcentual (20 percent)
DO $$
declare
    v_tenant_id uuid := (select tenant_id from general_schema.tenant where tenant_name = 'Promos Test Shop' limit 1);
    v_type_id int := (select promotion_type_id from pos_schema.promotion_type where type_name = 'percentage_discount' limit 1);
    v_promo_id uuid;
    v_rule_id uuid;
    v_discount record;
    v_subtotal numeric(12,2) := (select subtotal_amount from pos_schema.sale s join general_schema.branch br on s.branch_id = br.branch_id where br.tenant_id = v_tenant_id order by s.sale_date desc limit 1);
BEGIN
    RAISE NOTICE ''; 
    RAISE NOTICE '%', format('--- 3.1 Percentage discount (20 percent) ---');

    INSERT INTO pos_schema.promotion(tenant_id, promotion_code, promotion_name, promotion_type_id, promotion_start_date, promotion_end_date, is_active, customer_segment_id)
    VALUES (v_tenant_id, 'PT-PERC', '20 percent OFF Demo', v_type_id, current_date - 1, current_date + 30, true, 3)
    returning promotion_id into v_promo_id;

    -- insert rule
    INSERT INTO pos_schema.promotion_rule(promotion_id, discount_percentage)
    VALUES (coalesce(v_promo_id, (select promotion_id from pos_schema.promotion where tenant_id = v_tenant_id and promotion_code = 'PT-PERC' limit 1)), 20.00);

    -- calcular descuento para el conjunto (usar producto A como ejemplo de producto aplicable)
    for v_discount in select * from pos_schema.calculate_promotion_discount(
            (select promotion_id from pos_schema.promotion where tenant_id = v_tenant_id and promotion_code = 'PT-PERC' limit 1),
            v_tenant_id,
            (select product_variant_id from general_schema.product_variant where tenant_id = v_tenant_id and sku = 'PR-A' limit 1),
            1, 1000.00, v_subtotal
        )
    loop
        RAISE NOTICE '%', format('  Discount result: amount=$%s pct=%s rule=%s', v_discount.discount_amount, v_discount.discount_percentage, v_discount.rule_applied);
    end loop;

    RAISE NOTICE '%', format('--- End 3.1 ---');
end $$;


-- 3.2 Descuento fijo ($10 off si >= $50)
DO $$
declare
    v_tenant_id uuid := (select tenant_id from general_schema.tenant where tenant_name = 'Promos Test Shop' limit 1);
    v_type_id int := (select promotion_type_id from pos_schema.promotion_type where type_name = 'fixed_amount_discount' limit 1);
    v_promo_id uuid;    -- Variable declarada para capturar el ID
    v_discount record;  -- Variable para el loop de resultados
BEGIN
    RAISE NOTICE ''; 
    RAISE NOTICE '%', format('--- 3.2 Fixed amount discount ($10 off, min $50) ---');

    INSERT INTO pos_schema.promotion(tenant_id, promotion_code, promotion_name, promotion_type_id, promotion_start_date, promotion_end_date, is_active, customer_segment_id)
    VALUES (v_tenant_id, 'PT-FIX', '$10 OFF Demo', v_type_id, current_date - 1, current_date + 30, true, 3)
    returning promotion_id into v_promo_id; -- Capturamos en variable válida

    -- rule
    INSERT INTO pos_schema.promotion_rule(promotion_id, discount_amount, min_purchase_amount)
    VALUES (v_promo_id, 10.00, 50.00);

    -- calcular descuento sobre producto C (precio bajo pero subtotal global mayor)
    for v_discount in select * from pos_schema.calculate_promotion_discount(
            v_promo_id,
            v_tenant_id,
            (select product_variant_id from general_schema.product_variant where tenant_id = v_tenant_id and sku = 'PR-C' limit 1),
            3, 10.00, (select subtotal_amount from pos_schema.sale s join general_schema.branch br on s.branch_id = br.branch_id where br.tenant_id = v_tenant_id order by s.sale_date desc limit 1)
        )
    loop
        RAISE NOTICE '%', format('  Fixed Discount result: amount=$%s rule=%s', v_discount.discount_amount, v_discount.rule_applied);
    end loop;

    RAISE NOTICE '%', format('--- End 3.2 ---');
end $$;


-- 3.3 Buy X Get Y (2x1 sobre Mouse - PR-B)
DO $$
declare
    v_tenant_id uuid := (select tenant_id from general_schema.tenant where tenant_name = 'Promos Test Shop' limit 1);
    v_type_id int := (select promotion_type_id from pos_schema.promotion_type where type_name = 'buy_x_get_y' limit 1);
    v_promo_id uuid;
    v_discount record; -- CORRECCIÓN: Variable agregada
BEGIN
    RAISE NOTICE ''; 
    RAISE NOTICE '%', format('--- 3.3 Buy X Get Y (2x1) ---');

    INSERT INTO pos_schema.promotion(tenant_id, promotion_code, promotion_name, promotion_type_id, promotion_start_date, promotion_end_date, is_active, customer_segment_id)
    VALUES (v_tenant_id, 'PT-2X1', '2x1 Demo', v_type_id, current_date - 1, current_date + 30, true, 3)
    returning promotion_id into v_promo_id;

    INSERT INTO pos_schema.promotion_rule(promotion_id, buy_quantity, get_quantity, get_discount_percentage)
    VALUES (v_promo_id, 2, 1, 100.00);

    -- calcular descuento para 3 unidades de PR-B (esperado 1 gratis)
    for v_discount in select * from pos_schema.calculate_promotion_discount(
            v_promo_id, v_tenant_id,
            (select product_variant_id from general_schema.product_variant where tenant_id = v_tenant_id and sku = 'PR-B' limit 1),
            3, 50.00, (select subtotal_amount from pos_schema.sale s join general_schema.branch br on s.branch_id = br.branch_id where br.tenant_id = v_tenant_id order by s.sale_date desc limit 1)
        )
    loop
        RAISE NOTICE '%', format('  2x1 Discount: $%s (%s percent) rule=%s', v_discount.discount_amount, v_discount.discount_percentage, v_discount.rule_applied);
    end loop;

    RAISE NOTICE '%', format('--- End 3.3 ---');
end $$;


-- 3.4 Volume discount (15 percent para 10+ unidades) -- (aplica si compramos at least 10 items)
DO $$
declare
    v_tenant_id uuid := (select tenant_id from general_schema.tenant where tenant_name = 'Promos Test Shop' limit 1);
    v_type_id int := (select promotion_type_id from pos_schema.promotion_type where type_name = 'volume_discount' limit 1);
    v_promo_id uuid;
    v_discount record; -- CORRECCIÓN: Variable agregada
BEGIN
    RAISE NOTICE ''; 
    RAISE NOTICE '%', format('--- 3.4 Volume discount (15 percent para 10+) ---');

    INSERT INTO pos_schema.promotion(tenant_id, promotion_code, promotion_name, promotion_type_id, promotion_start_date, promotion_end_date, is_active, customer_segment_id)
    VALUES (v_tenant_id, 'PT-BULK', 'Bulk 15 percent Demo', v_type_id, current_date - 1, current_date + 30, true, 3)
    returning promotion_id into v_promo_id;

    INSERT INTO pos_schema.promotion_rule(promotion_id, min_quantity, discount_percentage)
    VALUES (v_promo_id, 10, 15.00);

    -- calcular descuento simulando 15 unidades de PR-B
    for v_discount in select * from pos_schema.calculate_promotion_discount(
            v_promo_id, v_tenant_id,
            (select product_variant_id from general_schema.product_variant where tenant_id = v_tenant_id and sku = 'PR-B' limit 1),
            15, 50.00, 15 * 50.00
        )
    loop
        RAISE NOTICE '%', format('  Volume Discount: $%s (%s percent) rule=%s', v_discount.discount_amount, v_discount.discount_percentage, v_discount.rule_applied);
    end loop;

    RAISE NOTICE '%', format('--- End 3.4 ---');
end $$;


-- 3.5 Tiered pricing (3 niveles) - demostración con PR-B
DO $$
declare
    v_tenant_id uuid := (select tenant_id from general_schema.tenant where tenant_name = 'Promos Test Shop' limit 1);
    v_type_id int := (select promotion_type_id from pos_schema.promotion_type where type_name = 'tiered_pricing' limit 1);
    v_promo_id uuid;
    v_discount record; -- CORRECCIÓN: Variable agregada
BEGIN
    RAISE NOTICE ''; 
    RAISE NOTICE '%', format('--- 3.5 Tiered pricing (levels) ---');

    INSERT INTO pos_schema.promotion(tenant_id, promotion_code, promotion_name, promotion_type_id, promotion_start_date, promotion_end_date, is_active, customer_segment_id)
    VALUES (v_tenant_id, 'PT-TIER', 'Tiered Demo', v_type_id, current_date - 1, current_date + 30, true, 3)
    returning promotion_id into v_promo_id;

    -- Tier 1: 1-10 = 5%
    INSERT INTO pos_schema.promotion_rule(promotion_id, tier_level, tier_min_quantity, tier_max_quantity, tier_discount_percentage)
    VALUES (v_promo_id, 1, 1, 10, 5.00);
    -- Tier 2: 11-50 = 10%
    INSERT INTO pos_schema.promotion_rule(promotion_id, tier_level, tier_min_quantity, tier_max_quantity, tier_discount_percentage)
    VALUES (v_promo_id, 2, 11, 50, 10.00);
    -- Tier 3: 51+ = 20%
    INSERT INTO pos_schema.promotion_rule(promotion_id, tier_level, tier_min_quantity, tier_discount_percentage)
    VALUES (v_promo_id, 3, 51, 20.00);

    -- calcular ejemplo Tier 2 (25 unidades)
    for v_discount in select * from pos_schema.calculate_promotion_discount(
            v_promo_id, v_tenant_id,
            (select product_variant_id from general_schema.product_variant where tenant_id = v_tenant_id and sku = 'PR-B' limit 1),
            25, 50.00, 25 * 50.00
        )
    loop
        RAISE NOTICE '%', format('  Tiered Discount (25 units): $%s (%s percent) rule=%s', v_discount.discount_amount, v_discount.discount_percentage, v_discount.rule_applied);
    end loop;

    RAISE NOTICE '%', format('--- End 3.5 ---');
end $$;


-- 3.6 Combo (informativo; no aplica a single-product tests)
DO $$
declare
    v_tenant_id uuid := (select tenant_id from general_schema.tenant where tenant_name = 'Promos Test Shop' limit 1);
    v_type_id int := (select promotion_type_id from pos_schema.promotion_type where type_name = 'combo' limit 1);
BEGIN
    RAISE NOTICE ''; 
    RAISE NOTICE '%', format('--- 3.6 Combo (cart-level - informational) ---');

    INSERT INTO pos_schema.promotion(tenant_id, promotion_code, promotion_name, promotion_type_id, promotion_start_date, promotion_end_date, is_active, customer_segment_id)
    VALUES (v_tenant_id, 'PT-COMB', 'Combo Demo', v_type_id, current_date - 1, current_date + 30, true, 3)
    ON CONFLICT DO NOTHING;

    RAISE NOTICE '%', format('  Combo promotions require cart-level calculation; use calculate_promotion_discount for individual products but business logic for combos must be done at cart-level');
    RAISE NOTICE '%', format('--- End 3.6 ---');
end $$;


-- ============================================
-- SECCIÓN 4: Ejecutar ventas de control por cada promoción
-- - Se reutiliza la canasta base pero se aplica el descuento calculado y se genera un pago por el monto final.
-- - Cada ejecución crea sale + payment + triggers => bill. Resultados se muestran.
-- ============================================
DO $$
declare
    v_tenant_id uuid := (select tenant_id from general_schema.tenant where tenant_name = 'Promos Test Shop' limit 1);
    v_customer_id uuid := (select tenant_customer_id from general_schema.tenant_customer where tenant_id = v_tenant_id limit 1);
    v_currency_id int := (select currency_id from general_schema.currency limit 1);
    v_payment_method_id int := (select payment_method_id from general_schema.payment_method where name = 'cash' limit 1);
    v_prod_a uuid := (select product_variant_id from general_schema.product_variant where tenant_id = v_tenant_id and sku = 'PR-A' limit 1);
    v_prod_b uuid := (select product_variant_id from general_schema.product_variant where tenant_id = v_tenant_id and sku = 'PR-B' limit 1);
    v_prod_c uuid := (select product_variant_id from general_schema.product_variant where tenant_id = v_tenant_id and sku = 'PR-C' limit 1);
    v_promotion record;
    v_sale_id uuid;
    v_payment_id uuid;
    v_subtotal numeric(12,2);
    v_tax_rate numeric(5,2) := coalesce((select rate_percentage from general_schema.tax_rate where region = 'US Federal' limit 1), 0);
    v_tax numeric(12,2);
    v_total_before numeric(12,2);
    v_discount_amount numeric(12,2);
    v_total_after numeric(12,2);
    v_discount_rec record;
BEGIN
    RAISE NOTICE ''; 

    -- Recompute base subtotal for the three items (same as base sale)
    v_subtotal := 1 * 1000.00 + 2 * 50.00 + 3 * 10.00;
    v_tax := round(v_subtotal * (v_tax_rate / 100), 2);
    v_total_before := v_subtotal + v_tax;

    for v_promotion in
        select promotion_id, promotion_code, pt.type_name
        from pos_schema.promotion p
        join pos_schema.promotion_type pt on p.promotion_type_id = pt.promotion_type_id
        where p.tenant_id = v_tenant_id
          and p.promotion_code like 'PT-%'
    loop
        RAISE NOTICE ''; 
        RAISE NOTICE '%', format('--- Promo: %s (%s type = %s ) ---', v_promotion.promotion_code, v_promotion.promotion_id, v_promotion.type_name);

        -- calcular descuento aproximado sumando descuentos por producto (ejemplo: aplicamos al item A en la demo)
        -- Para mostrar el efecto sobre la misma canasta, calculamos descuento por cada producto y sumamos.
        v_discount_amount := 0;
        -- producto A
        for v_discount_rec in select * from pos_schema.calculate_promotion_discount(v_promotion.promotion_id, v_tenant_id, v_prod_a, 1, 1000.00, v_subtotal) loop
            v_discount_amount := v_discount_amount + coalesce(v_discount_rec.discount_amount,0);
        end loop;
        -- producto B (2 unidades)
        for v_discount_rec in select * from pos_schema.calculate_promotion_discount(v_promotion.promotion_id, v_tenant_id, v_prod_b, 2, 50.00, v_subtotal) loop
            v_discount_amount := v_discount_amount + coalesce(v_discount_rec.discount_amount,0);
        end loop;
        -- producto C (3 unidades)
        for v_discount_rec in select * from pos_schema.calculate_promotion_discount(v_promotion.promotion_id, v_tenant_id, v_prod_c, 3, 10.00, v_subtotal) loop
            v_discount_amount := v_discount_amount + coalesce(v_discount_rec.discount_amount,0);
        end loop;

        v_total_after := v_total_before - v_discount_amount;
        if v_total_after < 0 then v_total_after := 0; end if;

        RAISE NOTICE '%', format('  Base subtotal: $%s tax: $%s total before: $%s', v_subtotal, v_tax, v_total_before);
        RAISE NOTICE '%', format('  Calculated discount(total across items): $%s', v_discount_amount);
        RAISE NOTICE '%', format('  Total to charge after discount: $%s', v_total_after);

        -- create sale + items (this sale is independent from base sale)
        INSERT INTO pos_schema.sale(branch_id, currency_id, subtotal_amount, tax_amount, total_amount, is_completed)
        VALUES ((select branch_id from general_schema.branch where tenant_id = v_tenant_id limit 1), v_currency_id, v_subtotal, v_tax, v_total_before, false)
        returning sale_id into v_sale_id;

        INSERT INTO pos_schema.sale_item(sale_id, tenant_id, product_variant_id, quantity, unit_price, total_price)
        VALUES
            (v_sale_id, v_tenant_id, v_prod_a, 1, 1000.00, 1000.00),
            (v_sale_id, v_tenant_id, v_prod_b, 2, 50.00, 100.00),
            (v_sale_id, v_tenant_id, v_prod_c, 3, 10.00, 30.00);

        -- payment equal to total_after (simulate applying discount externally)
        INSERT INTO pos_schema.customer_payment(tenant_customer_id, sale_id, payment_method_id, payment_amount, currency_id, verified)
        VALUES (v_customer_id, v_sale_id, v_payment_method_id, v_total_after, v_currency_id, false)
        returning customer_payment_id into v_payment_id;

        call pos_schema.verify_customer_payment(v_payment_id);
        perform pg_sleep(0.15);

        RAISE NOTICE '%', format('  Sale created: %s Payment: %s Charged: $%s', v_sale_id, v_payment_id, v_total_after);

        -- log resulting bill totals
        RAISE NOTICE '%', format('  RESULTING BILL (latest):');
        RAISE NOTICE '%', format('    subtotal=$%s tax=$%s total=$%s',
            (select subtotal_amount from pos_schema.bill where sale_id = v_sale_id limit 1),
            (select tax_amount from pos_schema.bill where sale_id = v_sale_id limit 1),
            (select total_amount from pos_schema.bill where sale_id = v_sale_id limit 1));

        RAISE NOTICE '%', format('--- End Promo %s ---', v_promotion.promotion_code);
    end loop;

    RAISE NOTICE '%', format('✅ SECCIÓN 4 completada - ventas por promotion ejecutadas');
end $$;


-- ============================================
-- SECCIÓN 5: Resumen final de las promociones creadas
-- ============================================
select
    p.promotion_code,
    p.promotion_name,
    pt.type_name,
    p.is_active,
    p.promotion_start_date,
    p.promotion_end_date
from pos_schema.promotion p
join pos_schema.promotion_type pt on p.promotion_type_id = pt.promotion_type_id
where tenant_id = (select tenant_id from general_schema.tenant where tenant_name = 'Promos Test Shop' limit 1)
order by p.created_at;
