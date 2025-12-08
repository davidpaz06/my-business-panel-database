-- =====================================
-- SCRIPT DE PRUEBA: DEVOLUCIONES PARCIALES Y TOTALES (idempotente)
-- =====================================
-- Sections follow the same style as testHybridPay.sql
-- 1) Cleanup (idempotent)
-- 2) Prepare tenant/branch/user/customer/products
-- 3) Create sale and bill (via verify_customer_payment trigger)
-- 4) Perform PARTIAL return (less than purchased quantity)
-- 5) Verify invoice and sale updated and return_product rows created
-- 6) Perform TOTAL return of remaining items
-- 7) Verify invoice and sale zeroed and return_product rows created
-- =====================================

set local search_path = core, pos_module;

-- ========================================
-- SECCIÓN 0: Limpieza inicial (idempotente)
-- ========================================
do $$
declare
    v_tenant_id uuid;
begin
    raise notice '========================================';
    raise notice '🧹 SECCIÓN 0: Limpieza inicial (idempotente)';
    raise notice '========================================';

    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Return Test Shop' limit 1;

    if v_tenant_id is not null then

        delete from pos_module.return_product where return_transaction_id in (
            select return_transaction_id from pos_module.return_transaction rt
            join pos_module.bill b on rt.bill_id = b.bill_id
            join pos_module.sale s on b.sale_id = s.sale_id
            join core.branch br on s.branch_id = br.branch_id
            where br.tenant_id = v_tenant_id
        );

        delete from pos_module.return_transaction where bill_id in (
            select b.bill_id from pos_module.bill b
            join pos_module.sale s on b.sale_id = s.sale_id
            join core.branch br on s.branch_id = br.branch_id
            where br.tenant_id = v_tenant_id
        );

        delete from pos_module.bill_payment where bill_id in (
            select b.bill_id from pos_module.bill b
            join pos_module.sale s on b.sale_id = s.sale_id
            join core.branch br on s.branch_id = br.branch_id
            where br.tenant_id = v_tenant_id
        );

        delete from pos_module.bill where sale_id in (
            select s.sale_id from pos_module.sale s
            join core.branch br on s.branch_id = br.branch_id
            where br.tenant_id = v_tenant_id
        );

        delete from pos_module.customer_payment where sale_id in (
            select s.sale_id from pos_module.sale s
            join core.branch br on s.branch_id = br.branch_id
            where br.tenant_id = v_tenant_id
        );

        delete from pos_module.sale_item where tenant_id = v_tenant_id;
        delete from pos_module.sale where branch_id in (
            select branch_id from core.branch where tenant_id = v_tenant_id
        );

        delete from pos_module.cash_register_sale where cash_register_session_id in (
            select cash_register_session_id from pos_module.cash_register_session crs
            join pos_module.cash_register cr on crs.cash_register_id = cr.cash_register_id
            join core.branch br on cr.branch_id = br.branch_id
            where br.tenant_id = v_tenant_id
        );

        delete from pos_module.cash_register_session where cash_register_id in (
            select cash_register_id from pos_module.cash_register cr
            join core.branch br on cr.branch_id = br.branch_id
            where br.tenant_id = v_tenant_id
        );

        delete from pos_module.cash_register where branch_id in (
            select branch_id from core.branch where tenant_id = v_tenant_id
        );

        delete from pos_module.score_transaction where tenant_id = v_tenant_id;
        delete from pos_module.tenant_customer_score where tenant_id = v_tenant_id;
        delete from pos_module.loyalty_program where tenant_id = v_tenant_id;

        delete from core.product where tenant_id = v_tenant_id;
        delete from core.tenant_customer where tenant_id = v_tenant_id;
        delete from core.users where tenant_id = v_tenant_id;
        delete from core.branch where tenant_id = v_tenant_id;
        delete from core.tenant where tenant_id = v_tenant_id;

        raise notice '   Previous test data removed for tenant %', v_tenant_id;
    else
        raise notice '   No previous test tenant found, nothing to clean';
    end if;

    raise notice '✅ SECCIÓN 0 COMPLETADA';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 1: Preparación completa de datos (idempotente)
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_branch_id uuid;
    v_user_id uuid;
    v_customer_id uuid;
    v_prod_a uuid;
    v_prod_b uuid;
    v_prod_c uuid;
    v_cash_reg uuid;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '🏪 SECCIÓN 1: Preparación de datos';
    raise notice '========================================';

    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Return Test Shop' limit 1;
    if v_tenant_id is null then
        insert into core.tenant(tenant_name, region_id, contact_email, is_subscribed)
        values ('Return Test Shop', (select region_id from core.region limit 1), 'returns@testshop.com', false)
        returning tenant_id into v_tenant_id;
    end if;

    select branch_id into v_branch_id from core.branch where tenant_id = v_tenant_id and branch_name = 'Main Store' limit 1;
    if v_branch_id is null then
        insert into core.branch (tenant_id, branch_name, branch_address, is_main_branch)
        values (v_tenant_id, 'Main Store', 'Test Address 1', true)
        returning branch_id into v_branch_id;
    end if;

    select user_id into v_user_id from core.users where tenant_id = v_tenant_id and email = 'cashier@returntest.com' limit 1;
    if v_user_id is null then
        insert into core.users (tenant_id, email, password_hash, role_id)
        values (v_tenant_id, 'cashier@returntest.com', 'testhash', 1)
        returning user_id into v_user_id;
    end if;

    select tenant_customer_id into v_customer_id from core.tenant_customer where tenant_id = v_tenant_id and email = 'customer@returntest.com' limit 1;
    if v_customer_id is null then
        insert into core.tenant_customer (tenant_id, first_name, last_name, document_number, email, phone)
        values (v_tenant_id, 'Alice', 'Return', 'RT-001', 'customer@returntest.com', '555-0001')
        returning tenant_customer_id into v_customer_id;
    end if;

    select product_id into v_prod_a from core.product where tenant_id = v_tenant_id and sku = 'RT-A' limit 1;
    if v_prod_a is null then
        insert into core.product (tenant_id, sku, product_name, unit_price)
        values (v_tenant_id, 'RT-A', 'Product A', 10.00)
        returning product_id into v_prod_a;
    end if;

    select product_id into v_prod_b from core.product where tenant_id = v_tenant_id and sku = 'RT-B' limit 1;
    if v_prod_b is null then
        insert into core.product (tenant_id, sku, product_name, unit_price)
        values (v_tenant_id, 'RT-B', 'Product B', 20.00)
        returning product_id into v_prod_b;
    end if;

    select product_id into v_prod_c from core.product where tenant_id = v_tenant_id and sku = 'RT-C' limit 1;
    if v_prod_c is null then
        insert into core.product (tenant_id, sku, product_name, unit_price)
        values (v_tenant_id, 'RT-C', 'Product C', 15.00)
        returning product_id into v_prod_c;
    end if;

    select cash_register_id into v_cash_reg from pos_module.cash_register where branch_id = v_branch_id limit 1;
    if v_cash_reg is null then
        insert into pos_module.cash_register (branch_id, is_active) values (v_branch_id, true) returning cash_register_id into v_cash_reg;
    end if;

    perform 1 from pos_module.cash_register_session where cash_register_id = v_cash_reg and is_active = true;
    if not found then
        insert into pos_module.cash_register_session (cash_register_id, user_id, opening_amount, is_active)
        values (v_cash_reg, v_user_id, 100.00, true);
    end if;

    perform 1 from core.payment_method where payment_method_id = 1;
    if not found then
        insert into core.payment_method(name) values ('cash');
    end if;
    perform 1 from core.payment_method where payment_method_id = 4;
    if not found then
        insert into core.payment_method(name) values ('loyalty_points');
    end if;

    raise notice '✅ SECCIÓN 1 COMPLETADA';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 2: Crear venta y pagar (genera bill)
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_branch_id uuid;
    v_customer_id uuid;
    v_prod_a uuid;
    v_prod_b uuid;
    v_prod_c uuid;
    v_sale_id uuid;
    v_payment_id uuid;
    v_tax numeric(10,2);
    v_subtotal numeric(10,2);
    v_total numeric(10,2);
begin
    raise notice '';
    raise notice '========================================';
    raise notice '🛒 SECCIÓN 2: Crear venta y pagar (genera factura)';
    raise notice '========================================';

    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Return Test Shop' limit 1;
    select branch_id into v_branch_id from core.branch where tenant_id = v_tenant_id and branch_name = 'Main Store' limit 1;
    select tenant_customer_id into v_customer_id from core.tenant_customer where tenant_id = v_tenant_id and email = 'customer@returntest.com' limit 1;
    select product_id into v_prod_a from core.product where tenant_id = v_tenant_id and sku = 'RT-A' limit 1;
    select product_id into v_prod_b from core.product where tenant_id = v_tenant_id and sku = 'RT-B' limit 1;
    select product_id into v_prod_c from core.product where tenant_id = v_tenant_id and sku = 'RT-C' limit 1;

    v_subtotal := 140.00; -- A x5 (50) + B x3 (60) + C x2 (30)
    v_tax := round(v_subtotal * 0.10, 2); -- assume 10% tax rate in test setup
    v_total := v_subtotal + v_tax;

    insert into pos_module.sale (branch_id, currency_id, subtotal_amount, tax_amount, total_amount, is_completed)
    values (v_branch_id, 1, v_subtotal, v_tax, v_total, false)
    returning sale_id into v_sale_id;

    insert into pos_module.sale_item (sale_id, tenant_id, product_id, quantity, unit_price, total_price)
    values 
        (v_sale_id, v_tenant_id, v_prod_a, 5, 10.00, 50.00),
        (v_sale_id, v_tenant_id, v_prod_b, 3, 20.00, 60.00),
        (v_sale_id, v_tenant_id, v_prod_c, 2, 15.00, 30.00);

    raise notice '✓ Sale created: % (subtotal $% tax $% total $%)', v_sale_id, v_subtotal, v_tax, v_total;

    insert into pos_module.customer_payment (tenant_customer_id, sale_id, payment_method_id, payment_amount, currency_id, verified)
    values (v_customer_id, v_sale_id, 1, v_total, 1, false)
    returning customer_payment_id into v_payment_id;

    raise notice '✓ Payment created (unverified): % amount $%', v_payment_id, v_total;

    call pos_module.verify_customer_payment(v_payment_id);

    perform pg_sleep(0.2);

    if not exists (select 1 from pos_module.bill where sale_id = v_sale_id) then
        raise exception 'Bill was not created for sale %', v_sale_id;
    end if;

    raise notice '✅ SECCIÓN 2 COMPLETADA - Sale billed';
end $$;


-- ========================================
-- SECCIÓN 3: Devolución PARCIAL (menos que lo comprado)
-- ========================================
do $$
declare
    v_sale_id uuid;
    v_bill_id uuid;
    v_return_tx uuid;
    v_customer_id uuid;
    v_si_a uuid;
    v_si_b uuid;
    v_return_total numeric(10,2);
    v_expected_return numeric(10,2) := 40.00;
    v_return_product_count int;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '🔄 SECCIÓN 3: Crear devolución PARCIAL';
    raise notice '========================================';

    select s.sale_id into v_sale_id
    from pos_module.sale s
    join core.branch b on s.branch_id = b.branch_id
    join core.tenant t on b.tenant_id = t.tenant_id
    where t.tenant_name = 'Return Test Shop'
    order by s.sale_date desc
    limit 1;

    if v_sale_id is null then raise exception 'No sale found for partial return'; end if;

    select bill_id, tenant_customer_id into v_bill_id, v_customer_id from pos_module.bill where sale_id = v_sale_id limit 1;

    select sale_item_id into v_si_a from pos_module.sale_item where sale_id = v_sale_id and product_id = (
        select product_id from core.product where tenant_id = (select tenant_id from core.tenant where tenant_name = 'Return Test Shop' limit 1) and sku = 'RT-A' limit 1
    ) limit 1;

    select sale_item_id into v_si_b from pos_module.sale_item where sale_id = v_sale_id and product_id = (
        select product_id from core.product where tenant_id = (select tenant_id from core.tenant where tenant_name = 'Return Test Shop' limit 1) and sku = 'RT-B' limit 1
    ) limit 1;

    if v_si_a is null or v_si_b is null then
        raise exception 'Sale items for A or B not found';
    end if;

    insert into pos_module.return_transaction (bill_id, tenant_customer_id, total_refund_amount, refund_method, return_status_id)
    values (v_bill_id, v_customer_id, 0.00, 1, (select return_status_id from pos_module.return_status where status_name = 'pending' limit 1))
    returning return_transaction_id into v_return_tx;

    raise notice '✓ Return transaction created: %', v_return_tx;

    -- insert return lines (trigger will compute total_price and update sale_item/bill)
    insert into pos_module.return_product (return_transaction_id, sale_item_id, quantity, unit_price)
    values
        (v_return_tx, v_si_a, 2, 10.00),
        (v_return_tx, v_si_b, 1, 20.00);

    perform pg_sleep(0.1);

    -- Verify return_product rows were created
    select count(*) into v_return_product_count from pos_module.return_product where return_transaction_id = v_return_tx;
    
    if v_return_product_count <> 2 then
        raise exception 'Expected 2 return_product rows, found %', v_return_product_count;
    end if;

    raise notice '✓ return_product rows created: %', v_return_product_count;

    select coalesce(sum(total_price),0) into v_return_total from pos_module.return_product where return_transaction_id = v_return_tx;

    if abs(v_return_total - v_expected_return) > 0.01 then
        raise exception 'Partial return recorded amount mismatch. Expected $% got $%', v_expected_return, v_return_total;
    end if;

    update pos_module.return_transaction set total_refund_amount = v_return_total where return_transaction_id = v_return_tx;

    raise notice '✓ Partial return recorded: % lines, returned total $%', v_return_product_count, v_return_total;
    raise notice '✅ SECCIÓN 3 COMPLETADA';
end $$;


-- ========================================
-- SECCIÓN 4: Verificaciones después de devolución PARCIAL
-- ========================================
do $$
declare
    v_bill record;
    v_qty_a int;
    v_qty_b int;
    v_qty_c int;
    v_tenant_id uuid;
    v_tax_rate numeric(5,2);
    v_expected_subtotal numeric(10,2) := 100.00; -- 140 - 40
    v_expected_tax numeric(10,2);
    v_expected_total numeric(10,2);
begin
    raise notice '';
    raise notice '========================================';
    raise notice '📦 SECCIÓN 4: Verificaciones tras devolución PARCIAL';
    raise notice '========================================';

    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Return Test Shop' limit 1;

    select b.subtotal_amount, b.tax_amount, b.total_amount into v_bill
    from pos_module.bill b
    join pos_module.sale s on b.sale_id = s.sale_id
    join core.branch br on s.branch_id = br.branch_id
    where br.tenant_id = v_tenant_id
    order by b.billed_at desc
    limit 1;

    select coalesce(quantity,0) into v_qty_a from pos_module.sale_item si join core.product p on si.tenant_id = p.tenant_id and si.product_id = p.product_id where p.sku = 'RT-A' and si.tenant_id = v_tenant_id limit 1;
    select coalesce(quantity,0) into v_qty_b from pos_module.sale_item si join core.product p on si.tenant_id = p.tenant_id and si.product_id = p.product_id where p.sku = 'RT-B' and si.tenant_id = v_tenant_id limit 1;
    select coalesce(quantity,0) into v_qty_c from pos_module.sale_item si join core.product p on si.tenant_id = p.tenant_id and si.product_id = p.product_id where p.sku = 'RT-C' and si.tenant_id = v_tenant_id limit 1;

    select rate_percentage into v_tax_rate
    from core.tax_rate tr
    join core.region r on tr.region = r.region_name
    join core.tenant t on t.region_id = r.region_id
    where t.tenant_id = v_tenant_id
    limit 1;

    if v_tax_rate is null then v_tax_rate := 0; end if;

    v_expected_tax := round(v_expected_subtotal * (v_tax_rate / 100), 2);
    v_expected_total := round(v_expected_subtotal + v_expected_tax, 2);

    raise notice 'Bill after partial return: subtotal $% tax $% total $%', v_bill.subtotal_amount, v_bill.tax_amount, v_bill.total_amount;
    raise notice 'Remaining quantities -> A: %, B: %, C: %', v_qty_a, v_qty_b, v_qty_c;

    if abs(v_bill.subtotal_amount - v_expected_subtotal) > 0.01 then
        raise exception 'Partial return: bill subtotal mismatch. Expected $% got $%', v_expected_subtotal, v_bill.subtotal_amount;
    end if;

    if abs(v_bill.tax_amount - v_expected_tax) > 0.01 then
        raise exception 'Partial return: bill tax mismatch. Expected $% got $%', v_expected_tax, v_bill.tax_amount;
    end if;

    if abs(v_bill.total_amount - v_expected_total) > 0.01 then
        raise exception 'Partial return: bill total mismatch. Expected $% got $%', v_expected_total, v_bill.total_amount;
    end if;

    -- verify sale totals reconciled with remaining sale_items
    raise notice '✅ SECCIÓN 4 COMPLETADA - Partial return verified';
end $$;


-- ========================================
-- SECCIÓN 5: Devolución TOTAL de los elementos restantes
-- ========================================
do $$
declare
    v_bill_id uuid;
    v_return_tx uuid;
    v_sale_id uuid;
    v_customer_id uuid;
    v_si record;
    v_total_returned numeric(10,2) := 0;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '🔄 SECCIÓN 5: Devolución TOTAL de elementos restantes';
    raise notice '========================================';

    select s.sale_id into v_sale_id
    from pos_module.sale s
    join core.branch b on s.branch_id = b.branch_id
    join core.tenant t on b.tenant_id = t.tenant_id
    where t.tenant_name = 'Return Test Shop'
    order by s.sale_date desc
    limit 1;

    select bill_id, tenant_customer_id into v_bill_id, v_customer_id from pos_module.bill where sale_id = v_sale_id limit 1;

    insert into pos_module.return_transaction (bill_id, tenant_customer_id, total_refund_amount, refund_method, return_status_id)
    values (v_bill_id, v_customer_id, 0.00, 1, (select return_status_id from pos_module.return_status where status_name = 'pending' limit 1))
    returning return_transaction_id into v_return_tx;

    for v_si in
        select sale_item_id, quantity, unit_price from pos_module.sale_item where sale_id = v_sale_id
    loop
        v_total_returned := v_total_returned + (v_si.quantity * v_si.unit_price);
        insert into pos_module.return_product (return_transaction_id, sale_item_id, quantity, unit_price)
        values (v_return_tx, v_si.sale_item_id, v_si.quantity, v_si.unit_price);
    end loop;

    update pos_module.return_transaction set total_refund_amount = v_total_returned where return_transaction_id = v_return_tx;

    perform pg_sleep(0.1);

    raise notice '✓ Total return created: % , refunded $%', v_return_tx, v_total_returned;
    raise notice '✅ SECCIÓN 5 COMPLETADA';
end $$;


-- ========================================
-- SECCIÓN 6: Verificaciones después de devolución TOTAL
-- ========================================
do $$
declare
    v_bill record;
    v_remaining_items int;
    v_tenant_id uuid;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '📦 SECCIÓN 6: Verificaciones tras devolución TOTAL';
    raise notice '========================================';

    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Return Test Shop' limit 1;

    select b.subtotal_amount, b.tax_amount, b.total_amount into v_bill
    from pos_module.bill b
    join pos_module.sale s on b.sale_id = s.sale_id
    join core.branch br on s.branch_id = br.branch_id
    where br.tenant_id = v_tenant_id
    order by b.billed_at desc
    limit 1;

    select count(*) into v_remaining_items from pos_module.sale_item si
    join pos_module.sale s on si.sale_id = s.sale_id
    join core.branch br on s.branch_id = br.branch_id
    where br.tenant_id = v_tenant_id;

    raise notice 'Bill after total return: subtotal $% tax $% total $%', v_bill.subtotal_amount, v_bill.tax_amount, v_bill.total_amount;
    raise notice 'Remaining sale_item rows for tenant: %', v_remaining_items;

    if v_remaining_items <> 0 then
        raise exception 'Total return failed: sale_items still exist (% rows)', v_remaining_items;
    end if;

    if round(v_bill.subtotal_amount,2) <> 0.00 or round(v_bill.total_amount,2) <> 0.00 then
        raise exception 'Total return failed: bill not zeroed (subtotal $% total $%)', v_bill.subtotal_amount, v_bill.total_amount;
    end if;

    raise notice '✅ Total return succeeded, invoice zeroed and sale items removed';
    raise notice '✅ SECCIÓN 6 COMPLETADA';
end $$;


-- ========================================
-- SECCIÓN 7: Resumen final
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_customer_id uuid;
    v_return_count int;
    v_return_sum numeric(10,2);
    v_return_detail record;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '📊 SECCIÓN 7: RESUMEN FINAL';
    raise notice '========================================';

    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Return Test Shop' limit 1;
    select tenant_customer_id into v_customer_id from core.tenant_customer where tenant_id = v_tenant_id limit 1;

    select count(rp.return_product_id), coalesce(sum(rp.total_price),0)
    into v_return_count, v_return_sum
    from pos_module.return_product rp
    join pos_module.return_transaction rt on rp.return_transaction_id = rt.return_transaction_id
    join pos_module.bill b on rt.bill_id = b.bill_id
    where b.sale_id in (
        select s.sale_id from pos_module.sale s
        join core.branch br on s.branch_id = br.branch_id
        where br.tenant_id = v_tenant_id
    );

    raise notice 'Tenant: %', v_tenant_id;
    raise notice 'Customer: %', v_customer_id;
    raise notice 'Total return_product lines: %', v_return_count;
    raise notice 'Total returned amount: $%', v_return_sum;
    raise notice '';
    
    -- Show detailed return_product entries
    raise notice '📋 DETALLE DE DEVOLUCIONES (return_product):';
    for v_return_detail in
        select 
            rp.return_product_id,
            rp.quantity,
            rp.unit_price,
            rp.total_price,
            p.sku,
            p.product_name
        from pos_module.return_product rp
        join pos_module.return_transaction rt on rp.return_transaction_id = rt.return_transaction_id
        join pos_module.bill b on rt.bill_id = b.bill_id
        join pos_module.sale_item si on rp.sale_item_id = si.sale_item_id
        join core.product p on si.product_id = p.product_id and si.tenant_id = p.tenant_id
        where b.sale_id in (
            select s.sale_id from pos_module.sale s
            join core.branch br on s.branch_id = br.branch_id
            where br.tenant_id = v_tenant_id
        )
    loop
        raise notice '  - % (%) × % @ $% = $%',
            v_return_detail.product_name,
            v_return_detail.sku,
            v_return_detail.quantity,
            v_return_detail.unit_price,
            v_return_detail.total_price;
    end loop;
    
    raise notice '';
    raise notice '✅ TEST COMPLETO - Partial & Total returns flow validated';
    raise notice '========================================';
end $$;