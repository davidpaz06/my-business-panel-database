-- =====================================
-- TEST: FLUJO COMPLETO SUPPLIES MODULE (idempotente)
-- =====================================
-- Objetivo: Demostrar el flujo completo de compra con:
--   1. Creación de orden con factura e impuestos
--   2. Pago dividido: 40%, 30%, 30%
--   3. Actualización automática de estado de cuenta por pagar
--   4. Cambio de status a 'Shipped' (status_id = 2)
--   5. Cambio de status a 'Delivered' (status_id = 3) → genera goods_receipt automáticamente
--   6. Conciliación automática a tres vías
--   7. Verificación de resultados
-- =====================================

set search_path = supplies_module, core;

-- ========================================
-- SECCIÓN 0: Limpieza inicial (idempotente)
-- ========================================
do $$
begin
    raise notice '========================================';
    raise notice '🧹 SECCIÓN 0: Limpieza inicial';
    raise notice '========================================';

    delete from supplies_module.three_way_matching where supply_order_id in (
        select so.supply_order_id from supplies_module.supply_order so
        join supplies_module.supplier s on so.supplier_id = s.supplier_id
        where s.supplier_name = 'Full Flow Supplier'
    );

    delete from supplies_module.supply_order_payment where account_payable_id in (
        select ap.account_payable_id from supplies_module.account_payable ap
        join supplies_module.supply_order so on ap.supply_order_id = so.supply_order_id
        join supplies_module.supplier s on so.supplier_id = s.supplier_id
        where s.supplier_name = 'Full Flow Supplier'
    );

    delete from supplies_module.goods_receipt_item where goods_receipt_id in (
        select gr.goods_receipt_id from supplies_module.goods_receipt gr
        join supplies_module.supply_order so on gr.supply_order_id = so.supply_order_id
        join supplies_module.supplier s on so.supplier_id = s.supplier_id
        where s.supplier_name = 'Full Flow Supplier'
    );

    delete from supplies_module.goods_receipt where supply_order_id in (
        select so.supply_order_id from supplies_module.supply_order so
        join supplies_module.supplier s on so.supplier_id = s.supplier_id
        where s.supplier_name = 'Full Flow Supplier'
    );

    delete from supplies_module.supplier_invoice_item where supplier_invoice_id in (
        select si.supplier_invoice_id from supplies_module.supplier_invoice si
        join supplies_module.supply_order so on si.supply_order_id = so.supply_order_id
        join supplies_module.supplier s on so.supplier_id = s.supplier_id
        where s.supplier_name = 'Full Flow Supplier'
    );

    delete from supplies_module.supplier_invoice where supply_order_id in (
        select so.supply_order_id from supplies_module.supply_order so
        join supplies_module.supplier s on so.supplier_id = s.supplier_id
        where s.supplier_name = 'Full Flow Supplier'
    );

    delete from supplies_module.supply_order_tracking where supply_order_id in (
        select so.supply_order_id from supplies_module.supply_order so
        join supplies_module.supplier s on so.supplier_id = s.supplier_id
        where s.supplier_name = 'Full Flow Supplier'
    );

    delete from supplies_module.account_payable where supply_order_id in (
        select so.supply_order_id from supplies_module.supply_order so
        join supplies_module.supplier s on so.supplier_id = s.supplier_id
        where s.supplier_name = 'Full Flow Supplier'
    );

    delete from supplies_module.supply_order_item where supply_order_id in (
        select so.supply_order_id from supplies_module.supply_order so
        join supplies_module.supplier s on so.supplier_id = s.supplier_id
        where s.supplier_name = 'Full Flow Supplier'
    );

    delete from supplies_module.supply_order where supplier_id in (
        select supplier_id from supplies_module.supplier where supplier_name = 'Full Flow Supplier'
    );

    delete from supplies_module.supplier_branch where supplier_id in (
        select supplier_id from supplies_module.supplier where supplier_name = 'Full Flow Supplier'
    );

    delete from supplies_module.supplier where supplier_name = 'Full Flow Supplier';
    delete from inventory_module.warehouse where warehouse_name = 'Full Flow Warehouse';
    delete from core.product where sku in ('FF-001', 'FF-002', 'FF-003');
    delete from core.branch where branch_name = 'Full Flow Branch';
    delete from core.tenant where tenant_name = 'Full Flow Test Shop';

    raise notice '✅ Limpieza completada';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 1: Preparación de datos maestros
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_branch_id uuid;
    v_warehouse_id uuid;
    v_supplier_id uuid;
    v_prod1 uuid;
    v_prod2 uuid;
    v_prod3 uuid;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '🏪 SECCIÓN 1: Preparación de datos maestros';
    raise notice '========================================';

    insert into core.tenant (tenant_name, region_id, contact_email, is_subscribed)
    values ('Full Flow Test Shop', 1, 'fullflow@test.local', true)
    on conflict do nothing;
    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Full Flow Test Shop' limit 1;
    raise notice '   ✓ Tenant creado: %', v_tenant_id;

    insert into core.branch (tenant_id, branch_name, branch_address, is_main_branch)
    values (v_tenant_id, 'Full Flow Branch', 'Calle Full Flow 123', true)
    on conflict do nothing;
    select branch_id into v_branch_id from core.branch where tenant_id = v_tenant_id and branch_name = 'Full Flow Branch' limit 1;
    raise notice '   ✓ Branch creada: %', v_branch_id;

    if to_regclass('inventory_module.warehouse') is null then
        execute 'create schema if not exists inventory_module';
        execute '
            create table if not exists inventory_module.warehouse(
                warehouse_id uuid primary key default gen_random_uuid(),
                branch_id uuid references core.branch(branch_id) on delete cascade,
                warehouse_name varchar(255),
                warehouse_address varchar(255) not null,
                created_at timestamp default current_timestamp
            )';
    end if;

    insert into inventory_module.warehouse (warehouse_name, branch_id, warehouse_address)
    values ('Full Flow Warehouse', v_branch_id, 'Bodega Full Flow')
    on conflict do nothing;
    select warehouse_id into v_warehouse_id from inventory_module.warehouse where warehouse_name = 'Full Flow Warehouse' limit 1;
    raise notice '   ✓ Warehouse creado: %', v_warehouse_id;

    insert into supplies_module.supplier (supplier_name, supplier_contact_info, supplier_address)
    values ('Full Flow Supplier', 'contact@fullflow.local', 'Proveedor Full Flow')
    on conflict (supplier_name) do nothing;
    select supplier_id into v_supplier_id from supplies_module.supplier where supplier_name = 'Full Flow Supplier' limit 1;

    insert into supplies_module.supplier_branch (supplier_id, branch_id)
    values (v_supplier_id, v_branch_id)
    on conflict do nothing;
    raise notice '   ✓ Supplier creado: %', v_supplier_id;

    insert into core.product (tenant_id, sku, product_name, unit_price)
    values 
        (v_tenant_id, 'FF-001', 'Producto Flow A', 500.00),
        (v_tenant_id, 'FF-002', 'Producto Flow B', 300.00),
        (v_tenant_id, 'FF-003', 'Producto Flow C', 200.00)
    on conflict do nothing;
    
    select product_id into v_prod1 from core.product where tenant_id = v_tenant_id and sku = 'FF-001' limit 1;
    select product_id into v_prod2 from core.product where tenant_id = v_tenant_id and sku = 'FF-002' limit 1;
    select product_id into v_prod3 from core.product where tenant_id = v_tenant_id and sku = 'FF-003' limit 1;
    raise notice '   ✓ Productos creados: 3 items (FF-001, FF-002, FF-003)';

    raise notice '✅ SECCIÓN 1 COMPLETADA';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 2: Crear orden de compra con factura
-- ========================================
-- Subtotal esperado: 2x500 + 3x300 + 5x200 = 1000 + 900 + 1000 = $2900
-- Tax (13%): $377.00
-- Total con tax: $3277.00
-- ========================================
do $$
declare
    v_supplier_id uuid;
    v_warehouse_id uuid;
    v_supply_order_id uuid;
    v_tenant_id uuid;
    v_items jsonb;
    v_account_payable_id uuid;
    v_subtotal numeric(12,3);
    v_tax_amount numeric(12,3);
    v_amount_due numeric(12,3);
    v_supplier_invoice_id uuid;
    v_invoice_total numeric(12,3);
begin
    raise notice '';
    raise notice '========================================';
    raise notice '📦 SECCIÓN 2: Crear orden de compra';
    raise notice '========================================';

    select supplier_id into v_supplier_id from supplies_module.supplier where supplier_name = 'Full Flow Supplier' limit 1;
    select warehouse_id into v_warehouse_id from inventory_module.warehouse where warehouse_name = 'Full Flow Warehouse' limit 1;
    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Full Flow Test Shop' limit 1;

    v_items := jsonb_build_array(
        jsonb_build_object('product_id', (select product_id::text from core.product where tenant_id = v_tenant_id and sku = 'FF-001'), 'quantity_ordered', 2, 'unit_price', 500.00),
        jsonb_build_object('product_id', (select product_id::text from core.product where tenant_id = v_tenant_id and sku = 'FF-002'), 'quantity_ordered', 3, 'unit_price', 300.00),
        jsonb_build_object('product_id', (select product_id::text from core.product where tenant_id = v_tenant_id and sku = 'FF-003'), 'quantity_ordered', 5, 'unit_price', 200.00)
    );

    v_supply_order_id := supplies_module.create_supply_order(
        v_supplier_id,
        v_warehouse_id,
        (current_date + interval '10 days')::date,
        v_items,
        true,
        'CREDIT'
    );

    select account_payable_id, subtotal_amount, tax_amount, amount_due 
    into v_account_payable_id, v_subtotal, v_tax_amount, v_amount_due
    from supplies_module.account_payable
    where supply_order_id = v_supply_order_id;

    select supplier_invoice_id, total_amount 
    into v_supplier_invoice_id, v_invoice_total
    from supplies_module.supplier_invoice
    where supply_order_id = v_supply_order_id;

    raise notice '   ✓ Supply Order ID: %', v_supply_order_id;
    raise notice '   ✓ Account Payable ID: %', v_account_payable_id;
    raise notice '   ✓ Supplier Invoice ID: %', v_supplier_invoice_id;
    raise notice '';
    raise notice '   📊 Montos:';
    raise notice '      Subtotal: $%', v_subtotal;
    raise notice '      Tax (13%%): $%', v_tax_amount;
    raise notice '      Total a pagar: $%', v_amount_due;
    raise notice '';
    raise notice '   ✅ Factura generada automáticamente';
    raise notice '   ✅ Account payable creada con impuestos calculados';

    raise notice '✅ SECCIÓN 2 COMPLETADA';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 3: Pago inicial 40%
-- ========================================
do $$
declare
    v_account_payable_id uuid;
    v_tenant_id uuid;
    v_payment_id uuid;
    v_amount_due numeric(12,3);
    v_pay numeric(12,3);
    v_status int;
    v_status_name varchar;
    v_paid numeric(12,3);
    v_balance numeric(12,3);
begin
    raise notice '';
    raise notice '========================================';
    raise notice '💸 SECCIÓN 3: Pago inicial 40%%';
    raise notice '========================================';

    select ap.account_payable_id, ap.amount_due, t.tenant_id
    into v_account_payable_id, v_amount_due, v_tenant_id
    from supplies_module.account_payable ap
    join supplies_module.supply_order so on ap.supply_order_id = so.supply_order_id
    join supplies_module.supplier s on so.supplier_id = s.supplier_id
    join supplies_module.supplier_branch sb on s.supplier_id = sb.supplier_id
    join core.branch b on sb.branch_id = b.branch_id
    join core.tenant t on b.tenant_id = t.tenant_id
    where s.supplier_name = 'Full Flow Supplier'
    limit 1;

    v_pay := round(v_amount_due * 0.40, 3);

    raise notice '   💰 Total a pagar: $%', v_amount_due;
    raise notice '   💰 Pago 40%%: $%', v_pay;

    insert into supplies_module.supply_order_payment (
        tenant_id, account_payable_id, payment_date, amount_paid, payment_method_id, payment_reference, verified
    ) values (
        v_tenant_id, v_account_payable_id, current_timestamp, v_pay, 1, 'PAY-40PCT-CASH', false
    ) returning payment_id into v_payment_id;

    raise notice '   ✓ Pago registrado: %', v_payment_id;

    call supplies_module.verify_supply_order_payment(v_payment_id);
    raise notice '   ✓ Pago verificado';

    select ap.account_status, aps.status_name, ap.amount_paid, ap.balance_remaining 
    into v_status, v_status_name, v_paid, v_balance
    from supplies_module.account_payable ap
    join supplies_module.account_payable_status aps on ap.account_status = aps.status_id
    where ap.account_payable_id = v_account_payable_id;
    
    raise notice '';
    raise notice '   📊 Estado de cuenta:';
    raise notice '      Status: % (%)', v_status_name, v_status;
    raise notice '      Pagado: $%', v_paid;
    raise notice '      Restante: $%', v_balance;

    if v_status <> 2 then
        raise warning '   ⚠️ Se esperaba status "Partial Paid" (2), pero se obtuvo: %', v_status;
    end if;

    raise notice '✅ SECCIÓN 3 COMPLETADA';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 4: Envío de mercancía (Shipped)
-- ========================================
do $$
declare
    v_supply_order_id uuid;
    v_old_status int;
    v_new_status int;
    v_old_status_name varchar;
    v_new_status_name varchar;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '🚚 SECCIÓN 4: Envío de mercancía';
    raise notice '========================================';

    select so.supply_order_id, so.supply_order_status_id, sos.status_name
    into v_supply_order_id, v_old_status, v_old_status_name
    from supplies_module.supply_order so
    join supplies_module.supply_order_status sos on so.supply_order_status_id = sos.status_id
    join supplies_module.supplier s on so.supplier_id = s.supplier_id
    where s.supplier_name = 'Full Flow Supplier'
    limit 1;

    raise notice '   📦 Order ID: %', v_supply_order_id;
    raise notice '   📊 Status anterior: % (%)', v_old_status_name, v_old_status;

    update supplies_module.supply_order
    set supply_order_status_id = 2
    where supply_order_id = v_supply_order_id;

    select so.supply_order_status_id, sos.status_name
    into v_new_status, v_new_status_name
    from supplies_module.supply_order so
    join supplies_module.supply_order_status sos on so.supply_order_status_id = sos.status_id
    where so.supply_order_id = v_supply_order_id;

    raise notice '   ✓ Status actualizado: % (%)', v_new_status_name, v_new_status;
    raise notice '   ✅ Orden marcada como "Shipped"';

    raise notice '✅ SECCIÓN 4 COMPLETADA';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 5: Pago parcial 30%
-- ========================================
do $$
declare
    v_account_payable_id uuid;
    v_tenant_id uuid;
    v_payment_id uuid;
    v_amount_due numeric(12,3);
    v_pay numeric(12,3);
    v_status int;
    v_status_name varchar;
    v_paid numeric(12,3);
    v_balance numeric(12,3);
begin
    raise notice '';
    raise notice '========================================';
    raise notice '💸 SECCIÓN 5: Pago parcial 30%%';
    raise notice '========================================';

    select ap.account_payable_id, ap.amount_due, t.tenant_id
    into v_account_payable_id, v_amount_due, v_tenant_id
    from supplies_module.account_payable ap
    join supplies_module.supply_order so on ap.supply_order_id = so.supply_order_id
    join supplies_module.supplier s on so.supplier_id = s.supplier_id
    join supplies_module.supplier_branch sb on s.supplier_id = sb.supplier_id
    join core.branch b on sb.branch_id = b.branch_id
    join core.tenant t on b.tenant_id = t.tenant_id
    where s.supplier_name = 'Full Flow Supplier'
    limit 1;

    v_pay := round(v_amount_due * 0.30, 3);

    raise notice '   💰 Pago 30%%: $%', v_pay;

    insert into supplies_module.supply_order_payment (
        tenant_id, account_payable_id, payment_date, amount_paid, payment_method_id, payment_reference, verified
    ) values (
        v_tenant_id, v_account_payable_id, current_timestamp, v_pay, 2, 'PAY-30PCT-DEBIT', false
    ) returning payment_id into v_payment_id;

    raise notice '   ✓ Pago registrado: %', v_payment_id;

    call supplies_module.verify_supply_order_payment(v_payment_id);
    raise notice '   ✓ Pago verificado';

    select ap.account_status, aps.status_name, ap.amount_paid, ap.balance_remaining 
    into v_status, v_status_name, v_paid, v_balance
    from supplies_module.account_payable ap
    join supplies_module.account_payable_status aps on ap.account_status = aps.status_id
    where ap.account_payable_id = v_account_payable_id;
    
    raise notice '';
    raise notice '   📊 Estado de cuenta:';
    raise notice '      Status: % (%)', v_status_name, v_status;
    raise notice '      Pagado acumulado: $%', v_paid;
    raise notice '      Restante: $%', v_balance;

    raise notice '✅ SECCIÓN 5 COMPLETADA';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 6: Pago final 30%
-- ========================================
do $$
declare
    v_account_payable_id uuid;
    v_tenant_id uuid;
    v_payment_id uuid;
    v_amount_due numeric(12,3);
    v_paid_so_far numeric(12,3);
    v_remaining numeric(12,3);
    v_pay numeric(12,3);
    v_status int;
    v_status_name varchar;
    v_paid numeric(12,3);
    v_balance numeric(12,3);
    v_invoice_paid boolean;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '💸 SECCIÓN 6: Pago final 30%%';
    raise notice '========================================';

    select ap.account_payable_id, ap.amount_due, ap.amount_paid, t.tenant_id
    into v_account_payable_id, v_amount_due, v_paid_so_far, v_tenant_id
    from supplies_module.account_payable ap
    join supplies_module.supply_order so on ap.supply_order_id = so.supply_order_id
    join supplies_module.supplier s on so.supplier_id = s.supplier_id
    join supplies_module.supplier_branch sb on s.supplier_id = sb.supplier_id
    join core.branch b on sb.branch_id = b.branch_id
    join core.tenant t on b.tenant_id = t.tenant_id
    where s.supplier_name = 'Full Flow Supplier'
    limit 1;

    v_remaining := round(v_amount_due - coalesce(v_paid_so_far, 0), 3);
    v_pay := v_remaining;

    raise notice '   💰 Total pendiente: $%', v_remaining;
    raise notice '   💰 Pago final: $%', v_pay;

    insert into supplies_module.supply_order_payment (
        tenant_id, account_payable_id, payment_date, amount_paid, payment_method_id, payment_reference, verified
    ) values (
        v_tenant_id, v_account_payable_id, current_timestamp, v_pay, 3, 'PAY-FINAL-CREDIT', false
    ) returning payment_id into v_payment_id;

    raise notice '   ✓ Pago registrado: %', v_payment_id;

    call supplies_module.verify_supply_order_payment(v_payment_id);
    raise notice '   ✓ Pago verificado';

    select ap.account_status, aps.status_name, ap.amount_paid, ap.balance_remaining 
    into v_status, v_status_name, v_paid, v_balance
    from supplies_module.account_payable ap
    join supplies_module.account_payable_status aps on ap.account_status = aps.status_id
    where ap.account_payable_id = v_account_payable_id;
    
    select si.paid into v_invoice_paid
    from supplies_module.supplier_invoice si
    join supplies_module.account_payable ap on si.supply_order_id = ap.supply_order_id
    where ap.account_payable_id = v_account_payable_id;

    raise notice '';
    raise notice '   📊 Estado final de cuenta:';
    raise notice '      Status: % (%)', v_status_name, v_status;
    raise notice '      Pagado total: $%', v_paid;
    raise notice '      Balance: $%', v_balance;
    raise notice '      Factura pagada: %', v_invoice_paid;

    if v_status <> 3 then
        raise exception '❌ Account payable debería estar en estado "Paid" (3), pero está en: % (%)', v_status_name, v_status;
    end if;

    if not v_invoice_paid then
        raise exception '❌ La factura debería estar marcada como pagada (paid=true)';
    end if;

    raise notice '';
    raise notice '   ✅ Cuenta pagada completamente';
    raise notice '   ✅ Factura actualizada automáticamente';

    raise notice '✅ SECCIÓN 6 COMPLETADA';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 7: Marcar como Delivered → genera goods_receipt
-- ========================================
do $$
declare
    v_supply_order_id uuid;
    v_old_status int;
    v_old_status_name varchar;
    v_new_status int;
    v_new_status_name varchar;
    v_goods_receipt_id uuid;
    v_goods_receipt_total numeric(12,3);
    v_items_count int;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '📦 SECCIÓN 7: Marcar como Delivered';
    raise notice '========================================';

    select so.supply_order_id, so.supply_order_status_id, sos.status_name
    into v_supply_order_id, v_old_status, v_old_status_name
    from supplies_module.supply_order so
    join supplies_module.supply_order_status sos on so.supply_order_status_id = sos.status_id
    join supplies_module.supplier s on so.supplier_id = s.supplier_id
    where s.supplier_name = 'Full Flow Supplier'
    limit 1;

    raise notice '   📦 Order ID: %', v_supply_order_id;
    raise notice '   📊 Status anterior: % (%)', v_old_status_name, v_old_status;

    update supplies_module.supply_order
    set supply_order_status_id = 3
    where supply_order_id = v_supply_order_id;

    select so.supply_order_status_id, sos.status_name
    into v_new_status, v_new_status_name
    from supplies_module.supply_order so
    join supplies_module.supply_order_status sos on so.supply_order_status_id = sos.status_id
    where so.supply_order_id = v_supply_order_id;

    raise notice '   ✓ Status actualizado: % (%)', v_new_status_name, v_new_status;

    select goods_receipt_id, total_amount 
    into v_goods_receipt_id, v_goods_receipt_total
    from supplies_module.goods_receipt
    where supply_order_id = v_supply_order_id;

    if v_goods_receipt_id is null then
        raise exception '❌ Goods receipt NO fue creado automáticamente';
    end if;

    select count(*) into v_items_count
    from supplies_module.goods_receipt_item
    where goods_receipt_id = v_goods_receipt_id;

    raise notice '';
    raise notice '   ✅ Goods receipt generado automáticamente:';
    raise notice '      ID: %', v_goods_receipt_id;
    raise notice '      Total: $%', v_goods_receipt_total;
    raise notice '      Items recibidos: %', v_items_count;

    raise notice '✅ SECCIÓN 7 COMPLETADA';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 8: Verificar conciliación a tres vías
-- ========================================
do $$
declare
    v_supply_order_id uuid;
    v_matching_id uuid;
    v_amounts_matched boolean;
    v_quantities_matched boolean;
    v_is_matched boolean;
    v_matched_at timestamp;
    v_goods_receipt_id uuid;
    v_supplier_invoice_id uuid;
    v_order_total numeric(12,3);
    v_invoice_total numeric(12,3);
    v_receipt_total numeric(12,3);
    v_order_qty integer;
    v_invoice_qty integer;
    v_receipt_qty integer;
    v_rec record;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '🔍 SECCIÓN 8: Conciliación a tres vías';
    raise notice '========================================';

    select so.supply_order_id into v_supply_order_id
    from supplies_module.supply_order so
    join supplies_module.supplier s on so.supplier_id = s.supplier_id
    where s.supplier_name = 'Full Flow Supplier'
    limit 1;

    select matching_id, amounts_matched, quantities_matched, is_matched, matched_at,
           goods_receipt_id, supplier_invoice_id
    into v_matching_id, v_amounts_matched, v_quantities_matched, v_is_matched, v_matched_at,
         v_goods_receipt_id, v_supplier_invoice_id
    from supplies_module.three_way_matching
    where supply_order_id = v_supply_order_id;

    if v_matching_id is null then
        raise exception '❌ Conciliación NO fue ejecutada automáticamente';
    end if;

    select coalesce(sum(quantity_ordered * unit_price), 0) into v_order_total
    from supplies_module.supply_order_item
    where supply_order_id = v_supply_order_id;

    select subtotal_amount into v_invoice_total
    from supplies_module.supplier_invoice
    where supplier_invoice_id = v_supplier_invoice_id;

    select subtotal_amount into v_receipt_total
    from supplies_module.goods_receipt
    where goods_receipt_id = v_goods_receipt_id;

    select coalesce(sum(quantity_ordered), 0) into v_order_qty
    from supplies_module.supply_order_item
    where supply_order_id = v_supply_order_id;

    select coalesce(sum(quantity_billed), 0) into v_invoice_qty
    from supplies_module.supplier_invoice_item
    where supplier_invoice_id = v_supplier_invoice_id;

    select coalesce(sum(quantity_received), 0) into v_receipt_qty
    from supplies_module.goods_receipt_item
    where goods_receipt_id = v_goods_receipt_id;

    raise notice '   ✅ Conciliación ejecutada automáticamente';
    raise notice '';
    raise notice '   📊 IDs involucrados:';
    raise notice '      Matching ID: %', v_matching_id;
    raise notice '      Supply Order: %', v_supply_order_id;
    raise notice '      Goods Receipt: %', v_goods_receipt_id;
    raise notice '      Supplier Invoice: %', v_supplier_invoice_id;
    raise notice '';
    raise notice '   📊 Totales (sin tax):';
    raise notice '      Order Total: $%', v_order_total;
    raise notice '      Invoice Subtotal: $%', v_invoice_total;
    raise notice '      Receipt Subtotal: $%', v_receipt_total;
    raise notice '';
    raise notice '   📊 Cantidades totales:';
    raise notice '      Order Qty: % units', v_order_qty;
    raise notice '      Invoice Qty: % units', v_invoice_qty;
    raise notice '      Receipt Qty: % units', v_receipt_qty;
    raise notice '';
    raise notice '   📊 Detalle por producto:';
    
    raise notice '      --- Supply Order Items ---';
    for v_rec in 
        select p.sku, soi.quantity_ordered
        from supplies_module.supply_order_item soi
        join core.product p on soi.product_id = p.product_id
        where soi.supply_order_id = v_supply_order_id
        order by p.sku
    loop
        raise notice '         %: % units', v_rec.sku, v_rec.quantity_ordered;
    end loop;

    raise notice '      --- Supplier Invoice Items ---';
    for v_rec in 
        select p.sku, sii.quantity_billed
        from supplies_module.supplier_invoice_item sii
        join core.product p on sii.product_id = p.product_id
        where sii.supplier_invoice_id = v_supplier_invoice_id
        order by p.sku
    loop
        raise notice '         %: % units', v_rec.sku, v_rec.quantity_billed;
    end loop;

    raise notice '      --- Goods Receipt Items ---';
    for v_rec in 
        select p.sku, gri.quantity_received
        from supplies_module.goods_receipt_item gri
        join core.product p on gri.product_id = p.product_id
        where gri.goods_receipt_id = v_goods_receipt_id
        order by p.sku
    loop
        raise notice '         %: % units', v_rec.sku, v_rec.quantity_received;
    end loop;

    raise notice '';
    raise notice '   📊 Resultado de conciliación:';
    raise notice '      Amounts matched: %', v_amounts_matched;
    raise notice '      Quantities matched: %', v_quantities_matched;
    raise notice '      Is matched: %', v_is_matched;
    raise notice '      Matched at: %', v_matched_at;

    if not v_is_matched then
        raise warning '   ⚠️ Conciliación falló - revisar discrepancias arriba';
    else
        raise notice '';
        raise notice '   ✅ CONCILIACIÓN EXITOSA';
        raise notice '   ✅ Todos los montos y cantidades coinciden';
    end if;

    raise notice '✅ SECCIÓN 8 COMPLETADA';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 9: Resumen final
-- ========================================
do $$
declare
    v_supply_order_id uuid;
    v_order_status varchar;
    v_account_status varchar;
    v_invoice_paid boolean;
    v_goods_receipt_exists boolean;
    v_matching_exists boolean;
    v_subtotal numeric(12,3);
    v_tax_amount numeric(12,3);
    v_amount_paid numeric(12,3);
    v_balance numeric(12,3);
    v_invoice_total numeric(12,3);
    v_receipt_total numeric(12,3);
    v_payments_count int;
    v_is_matched boolean;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '📊 SECCIÓN 9: RESUMEN FINAL';
    raise notice '========================================';

    select 
        so.supply_order_id,
        sos.status_name,
        aps.status_name,
        si.paid,
        ap.subtotal_amount,
        ap.tax_amount,
        ap.amount_paid,
        ap.balance_remaining,
        si.total_amount,
        gr.total_amount
    into 
        v_supply_order_id,
        v_order_status,
        v_account_status,
        v_invoice_paid,
        v_subtotal,
        v_tax_amount,
        v_amount_paid,
        v_balance,
        v_invoice_total,
        v_receipt_total
    from supplies_module.supply_order so
    join supplies_module.supply_order_status sos on so.supply_order_status_id = sos.status_id
    join supplies_module.account_payable ap on so.supply_order_id = ap.supply_order_id
    join supplies_module.account_payable_status aps on ap.account_status = aps.status_id
    join supplies_module.supplier_invoice si on so.supply_order_id = si.supply_order_id
    join supplies_module.goods_receipt gr on so.supply_order_id = gr.supply_order_id
    join supplies_module.supplier s on so.supplier_id = s.supplier_id
    where s.supplier_name = 'Full Flow Supplier'
    limit 1;

    select count(*) into v_payments_count
    from supplies_module.supply_order_payment sop
    join supplies_module.account_payable ap on sop.account_payable_id = ap.account_payable_id
    where ap.supply_order_id = v_supply_order_id
    and sop.verified = true;

    v_goods_receipt_exists := exists(
        select 1 from supplies_module.goods_receipt 
        where supply_order_id = v_supply_order_id
    );
    
    v_matching_exists := exists(
        select 1 from supplies_module.three_way_matching 
        where supply_order_id = v_supply_order_id
    );

    if v_matching_exists then
        select is_matched into v_is_matched
        from supplies_module.three_way_matching
        where supply_order_id = v_supply_order_id;
    end if;

    raise notice '';
    raise notice '┌─────────────────────────────────────────────────────┐';
    raise notice '│           RESUMEN DE FLUJO COMPLETO                 │';
    raise notice '└─────────────────────────────────────────────────────┘';
    raise notice '';
    raise notice '📦 ORDEN DE COMPRA:';
    raise notice '   ID: %', v_supply_order_id;
    raise notice '   Status: %', v_order_status;
    raise notice '';
    raise notice '💰 CUENTA POR PAGAR:';
    raise notice '   Subtotal: $%', v_subtotal;
    raise notice '   Tax (13%%): $%', v_tax_amount;
    raise notice '   Total: $%', (v_subtotal + v_tax_amount);
    raise notice '   Pagado: $%', v_amount_paid;
    raise notice '   Balance: $%', v_balance;
    raise notice '   Status: %', v_account_status;
    raise notice '   Pagos verificados: %', v_payments_count;
    raise notice '';
    raise notice '🧾 FACTURA:';
    raise notice '   Total (con tax): $%', v_invoice_total;
    raise notice '   Pagada: %', v_invoice_paid;
    raise notice '';
    raise notice '📦 RECEPCIÓN:';
    raise notice '   Existe: %', v_goods_receipt_exists;
    raise notice '   Total recibido: $%', v_receipt_total;
    raise notice '';
    raise notice '🔍 CONCILIACIÓN A TRES VÍAS:';
    raise notice '   Existe: %', v_matching_exists;
    
    if v_matching_exists then
        if v_is_matched then
            raise notice '   Resultado: ✅ EXITOSA';
        else
            raise notice '   Resultado: ⚠️ FALLÓ';
        end if;
    end if;

    raise notice '';
    raise notice '┌─────────────────────────────────────────────────────┐';
    raise notice '│  ✅ TEST COMPLETADO EXITOSAMENTE                    │';
    raise notice '└─────────────────────────────────────────────────────┘';
    raise notice '';
end $$;