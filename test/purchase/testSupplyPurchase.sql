-- =====================================
-- TEST: FLUJO COMPLETO purchase_schema MODULE (idempotente)
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
set search_path = purchase_schema, general_schema;

-- ========================================
-- SECCIÓN 0: Limpieza inicial (idempotente)
-- ========================================
DO $$
BEGIN
    raise notice '========================================';
    raise notice '🧹 SECCIÓN 0: Limpieza inicial';
    raise notice '========================================';

    delete from purchase_schema.three_way_matching where purchase_order_id in (
        select so.purchase_order_id from purchase_schema.purchase_order so
        join purchase_schema.supplier s on so.supplier_id = s.supplier_id
        where s.supplier_name = 'Full Flow Supplier'
    );

    delete from purchase_schema.purchase_order_payment where purchase_account_payable_id in (
        select sap.purchase_account_payable_id from purchase_schema.purchase_account_payable sap
        join purchase_schema.purchase_order so on sap.purchase_order_id = so.purchase_order_id
        join purchase_schema.supplier s on so.supplier_id = s.supplier_id
        where s.supplier_name = 'Full Flow Supplier'
    );

    delete from purchase_schema.goods_receipt_item where goods_receipt_id in (
        select gr.goods_receipt_id from purchase_schema.goods_receipt gr
        join purchase_schema.purchase_order so on gr.purchase_order_id = so.purchase_order_id
        join purchase_schema.supplier s on so.supplier_id = s.supplier_id
        where s.supplier_name = 'Full Flow Supplier'
    );

    delete from purchase_schema.goods_receipt where purchase_order_id in (
        select so.purchase_order_id from purchase_schema.purchase_order so
        join purchase_schema.supplier s on so.supplier_id = s.supplier_id
        where s.supplier_name = 'Full Flow Supplier'
    );

    delete from purchase_schema.supplier_invoice_item where supplier_invoice_id in (
        select si.supplier_invoice_id from purchase_schema.supplier_invoice si
        join purchase_schema.purchase_order so on si.purchase_order_id = so.purchase_order_id
        join purchase_schema.supplier s on so.supplier_id = s.supplier_id
        where s.supplier_name = 'Full Flow Supplier'
    );

    delete from purchase_schema.supplier_invoice where purchase_order_id in (
        select so.purchase_order_id from purchase_schema.purchase_order so
        join purchase_schema.supplier s on so.supplier_id = s.supplier_id
        where s.supplier_name = 'Full Flow Supplier'
    );

    delete from purchase_schema.purchase_order_tracking where purchase_order_id in (
        select so.purchase_order_id from purchase_schema.purchase_order so
        join purchase_schema.supplier s on so.supplier_id = s.supplier_id
        where s.supplier_name = 'Full Flow Supplier'
    );

    delete from purchase_schema.purchase_account_payable where purchase_order_id in (
        select so.purchase_order_id from purchase_schema.purchase_order so
        join purchase_schema.supplier s on so.supplier_id = s.supplier_id
        where s.supplier_name = 'Full Flow Supplier'
    );

    delete from purchase_schema.purchase_order_item where purchase_order_id in (
        select so.purchase_order_id from purchase_schema.purchase_order so
        join purchase_schema.supplier s on so.supplier_id = s.supplier_id
        where s.supplier_name = 'Full Flow Supplier'
    );

    delete from purchase_schema.purchase_order where supplier_id in (
        select supplier_id from purchase_schema.supplier where supplier_name = 'Full Flow Supplier'
    );

    delete from purchase_schema.supplier_branch where supplier_id in (
        select supplier_id from purchase_schema.supplier where supplier_name = 'Full Flow Supplier'
    );

    delete from purchase_schema.supplier where supplier_name = 'Full Flow Supplier';
    delete from inventory_schema.warehouse where warehouse_name = 'Full Flow Warehouse';
    delete from general_schema.product_variant where tenant_id in (
        select tenant_id from general_schema.tenant where tenant_name = 'Full Flow Test Shop'
    );
    delete from general_schema.branch where branch_name = 'Full Flow Branch';
    delete from general_schema.tenant where tenant_name = 'Full Flow Test Shop';

    raise notice '✅ Limpieza completada';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 1: Preparación de datos maestros
-- ========================================
DO $$
declare
    v_tenant_id uuid;
    v_branch_id uuid;
    v_warehouse_id uuid;
    v_supplier_id uuid;
    v_prod1 uuid;
    v_prod2 uuid;
    v_prod3 uuid;
    v_warehouse_exists BOOLEAN;
BEGIN
    raise notice '';
    raise notice '========================================';
    raise notice '🏪 SECCIÓN 1: Preparación de datos maestros';
    raise notice '========================================';

    INSERT INTO general_schema.tenant (tenant_name, region_id, contact_email, is_subscribed)
    VALUES ('Full Flow Test Shop', 1, 'fullflow@test.local', true)
    ON CONFLICT DO NOTHING;
    select tenant_id into v_tenant_id from general_schema.tenant where tenant_name = 'Full Flow Test Shop' limit 1;
    raise notice '   ✓ Tenant creado: %', v_tenant_id;

    INSERT INTO general_schema.branch (tenant_id, branch_name, branch_address, is_main_branch)
    VALUES (v_tenant_id, 'Full Flow Branch', 'Calle Full Flow 123', true)
    ON CONFLICT DO NOTHING;
    select branch_id into v_branch_id from general_schema.branch where tenant_id = v_tenant_id and branch_name = 'Full Flow Branch' limit 1;
    raise notice '   ✓ Branch creada: %', v_branch_id;

    select exists(
        select 1 
        from information_schema.tables 
        where table_schema = 'inventory_schema' 
        and table_name = 'warehouse'
    ) into v_warehouse_exists;

    if not v_warehouse_exists then
        raise notice '   ⚠️ Creando esquema inventory_schema y tabla warehouse...';
        execute 'CREATE SCHEMA IF NOT EXISTS inventory_schema';
        execute '
            CREATE TABLE IF NOT EXISTS inventory_schema.warehouse(
                warehouse_id uuid PRIMARY KEY default gen_random_uuid(),
                branch_id uuid REFERENCES general_schema.branch(branch_id) on delete cascade,
                warehouse_name VARCHAR(255) not null,
                warehouse_address VARCHAR(255) not null,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )';
    end if;

    select warehouse_id into v_warehouse_id 
    from inventory_schema.warehouse 
    where warehouse_name = 'Full Flow Warehouse' 
    limit 1;
    
    if v_warehouse_id is null then
        INSERT INTO inventory_schema.warehouse (warehouse_name, branch_id, warehouse_address)
        VALUES ('Full Flow Warehouse', v_branch_id, 'Bodega Full Flow')
        returning warehouse_id into v_warehouse_id;
    else
        update inventory_schema.warehouse
        set branch_id = v_branch_id,
            warehouse_address = 'Bodega Full Flow'
        where warehouse_id = v_warehouse_id;
    end if;
    
    if v_warehouse_id is null then
        raise exception 'Failed to create or retrieve warehouse';
    end if;
    
    raise notice '   ✓ Warehouse creado: %', v_warehouse_id;

    INSERT INTO purchase_schema.supplier (supplier_name, supplier_contact_info, supplier_address)
    VALUES ('Full Flow Supplier', 'contact@fullflow.local', 'Proveedor Full Flow')
    on conflict (supplier_name) DO nothing;
    select supplier_id into v_supplier_id from purchase_schema.supplier where supplier_name = 'Full Flow Supplier' limit 1;

    INSERT INTO purchase_schema.supplier_branch (supplier_id, branch_id)
    VALUES (v_supplier_id, v_branch_id)
    ON CONFLICT DO NOTHING;
    raise notice '   ✓ Supplier creado: %', v_supplier_id;

    -- Crear entradas CABYS de prueba
    INSERT INTO general_schema.product (cabys_code, product_name)
    VALUES 
        ('FFTEST0000001', 'Producto Flow A CABYS'),
        ('FFTEST0000002', 'Producto Flow B CABYS'),
        ('FFTEST0000003', 'Producto Flow C CABYS')
    ON CONFLICT (cabys_code) DO NOTHING;

    -- Crear variantes de producto para el tenant
    INSERT INTO general_schema.product_variant (tenant_id, sku, variant_name, unit_price, cabys_code)
    VALUES 
        (v_tenant_id, 'FF-001', 'Producto Flow A', 500.00, 'FFTEST0000001'),
        (v_tenant_id, 'FF-002', 'Producto Flow B', 300.00, 'FFTEST0000002'),
        (v_tenant_id, 'FF-003', 'Producto Flow C', 200.00, 'FFTEST0000003')
    ON CONFLICT (tenant_id, sku) DO NOTHING;
    
    select product_variant_id into v_prod1 from general_schema.product_variant where tenant_id = v_tenant_id and sku = 'FF-001' limit 1;
    select product_variant_id into v_prod2 from general_schema.product_variant where tenant_id = v_tenant_id and sku = 'FF-002' limit 1;
    select product_variant_id into v_prod3 from general_schema.product_variant where tenant_id = v_tenant_id and sku = 'FF-003' limit 1;
    raise notice '   ✓ Productos creados: 3 items (FF-001, FF-002, FF-003)';

    raise notice '✅ SECCIÓN 1 COMPLETADA';
    raise notice '========================================';
end $$;

-- ========================================
-- SECCIÓN 2: Crear orden de compra con factura
-- ========================================
DO $$
declare
    v_supplier_id uuid;
    v_warehouse_id uuid;
    v_purchase_order_id uuid;
    v_tenant_id uuid;
    v_items jsonb;
    v_account_payable_id uuid;
    v_subtotal numeric(12,3);
    v_tax_amount numeric(12,3);
    v_total_amount numeric(12,3);
    v_supplier_invoice_id uuid;
    v_invoice_total numeric(12,3);
BEGIN
    raise notice '';
    raise notice '========================================';
    raise notice '📦 SECCIÓN 2: Crear orden de compra';
    raise notice '========================================';

    select supplier_id into v_supplier_id from purchase_schema.supplier where supplier_name = 'Full Flow Supplier' limit 1;
    select warehouse_id into v_warehouse_id from inventory_schema.warehouse where warehouse_name = 'Full Flow Warehouse' limit 1;
    select tenant_id into v_tenant_id from general_schema.tenant where tenant_name = 'Full Flow Test Shop' limit 1;

    v_items := jsonb_build_array(
        jsonb_build_object('product_variant_id', (select product_variant_id::text from general_schema.product_variant where tenant_id = v_tenant_id and sku = 'FF-001'), 'quantity_ordered', 2, 'unit_price', 500.00),
        jsonb_build_object('product_variant_id', (select product_variant_id::text from general_schema.product_variant where tenant_id = v_tenant_id and sku = 'FF-002'), 'quantity_ordered', 3, 'unit_price', 300.00),
        jsonb_build_object('product_variant_id', (select product_variant_id::text from general_schema.product_variant where tenant_id = v_tenant_id and sku = 'FF-003'), 'quantity_ordered', 5, 'unit_price', 200.00)
    );

    v_purchase_order_id := purchase_schema.create_purchase_order(
        v_supplier_id,
        v_warehouse_id,
        (current_date + interval '10 days')::date,
        v_items,
        true,
        'CREDIT'
    );

    select 
        ap.account_payable_id,
        ap.subtotal,
        sap.tax_amount,
        (ap.subtotal + sap.tax_amount) as total_amount
    into 
        v_account_payable_id,
        v_subtotal,
        v_tax_amount,
        v_total_amount
    from general_schema.account_payable ap
    join purchase_schema.purchase_account_payable sap on ap.account_payable_id = sap.account_payable_id
    where sap.purchase_order_id = v_purchase_order_id;

    select supplier_invoice_id, total_amount 
    into v_supplier_invoice_id, v_invoice_total
    from purchase_schema.supplier_invoice
    where purchase_order_id = v_purchase_order_id;

    raise notice '   ✓ purchase_schema Order ID: %', v_purchase_order_id;
    raise notice '   ✓ Account Payable ID: %', v_account_payable_id;
    raise notice '   ✓ Supplier Invoice ID: %', v_supplier_invoice_id;
    raise notice '';
    raise notice '   📊 Montos:';
    raise notice '      Subtotal: $%', v_subtotal;
    raise notice '      Tax (13%%): $%', v_tax_amount;
    raise notice '      Total a pagar: $%', v_total_amount;
    raise notice '';
    raise notice '   ✅ Factura generada automáticamente';
    raise notice '   ✅ Account payable creada con impuestos calculados';

    raise notice '✅ SECCIÓN 2 COMPLETADA';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 3: Pago inicial 40%
-- ========================================
DO $$
declare
    v_purchase_account_payable_id uuid;
    v_account_payable_id uuid;
    v_tenant_id uuid;
    v_payment_id uuid;
    v_subtotal numeric(12,3);
    v_tax_amount numeric(12,3);
    v_total_amount numeric(12,3);
    v_pay numeric(12,3);
    v_status int;
    v_status_name VARCHAR;
    v_paid numeric(12,3);
    v_balance numeric(12,3);
BEGIN
    raise notice '';
    raise notice '========================================';
    raise notice '💸 SECCIÓN 3: Pago inicial 40%%';
    raise notice '========================================';

    select 
        sap.purchase_account_payable_id,
        ap.account_payable_id,
        ap.subtotal,
        sap.tax_amount,
        (ap.subtotal + sap.tax_amount) as total_amount,
        t.tenant_id
    into 
        v_purchase_account_payable_id,
        v_account_payable_id,
        v_subtotal,
        v_tax_amount,
        v_total_amount,
        v_tenant_id
    from purchase_schema.purchase_account_payable sap
    join general_schema.account_payable ap on sap.account_payable_id = ap.account_payable_id
    join purchase_schema.purchase_order so on sap.purchase_order_id = so.purchase_order_id
    join purchase_schema.supplier s on so.supplier_id = s.supplier_id
    join purchase_schema.supplier_branch sb on s.supplier_id = sb.supplier_id
    join general_schema.branch b on sb.branch_id = b.branch_id
    join general_schema.tenant t on b.tenant_id = t.tenant_id
    where s.supplier_name = 'Full Flow Supplier'
    limit 1;

    v_pay := round(v_total_amount * 0.40, 3);

    raise notice '   💰 Total a pagar: $%', v_total_amount;
    raise notice '   💰 Pago 40%%: $%', v_pay;

    INSERT INTO purchase_schema.purchase_order_payment (
        purchase_account_payable_id, amount_paid, payment_method_id, payment_reference
    ) VALUES (
        v_purchase_account_payable_id, v_pay, 1, 'PAY-40PCT-CASH'
    ) returning purchase_order_payment_id into v_payment_id;

    raise notice '   ✓ Pago registrado: %', v_payment_id;

    select 
        sap.account_payable_status,
        aps.status_name,
        ap.amount_paid,
        (ap.subtotal + sap.tax_amount - ap.amount_paid) as balance_remaining
    into v_status, v_status_name, v_paid, v_balance
    from purchase_schema.purchase_account_payable sap
    join general_schema.account_payable ap on sap.account_payable_id = ap.account_payable_id
    join general_schema.account_payable_status aps on sap.account_payable_status = aps.status_id
    where sap.purchase_account_payable_id = v_purchase_account_payable_id;
    
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
DO $$
declare
    v_purchase_order_id uuid;
    v_old_status int;
    v_new_status int;
    v_old_status_name VARCHAR;
    v_new_status_name VARCHAR;
BEGIN
    raise notice '';
    raise notice '========================================';
    raise notice '🚚 SECCIÓN 4: Envío de mercancía';
    raise notice '========================================';

    select so.purchase_order_id, so.purchase_order_status_id, sos.status_name
    into v_purchase_order_id, v_old_status, v_old_status_name
    from purchase_schema.purchase_order so
    join purchase_schema.purchase_order_status sos on so.purchase_order_status_id = sos.status_id
    join purchase_schema.supplier s on so.supplier_id = s.supplier_id
    where s.supplier_name = 'Full Flow Supplier'
    limit 1;

    raise notice '   📦 Order ID: %', v_purchase_order_id;
    raise notice '   📊 Status anterior: % (%)', v_old_status_name, v_old_status;

    update purchase_schema.purchase_order
    set purchase_order_status_id = 2
    where purchase_order_id = v_purchase_order_id;

    select so.purchase_order_status_id, sos.status_name
    into v_new_status, v_new_status_name
    from purchase_schema.purchase_order so
    join purchase_schema.purchase_order_status sos on so.purchase_order_status_id = sos.status_id
    where so.purchase_order_id = v_purchase_order_id;

    raise notice '   ✓ Status actualizado: % (%)', v_new_status_name, v_new_status;
    raise notice '   ✅ Orden marcada como "Shipped"';

    raise notice '✅ SECCIÓN 4 COMPLETADA';
    raise notice '========================================';
end $$;


-- ========================================
-- SECCIÓN 5: Pago parcial 30%
-- ========================================
DO $$
declare
    v_purchase_account_payable_id uuid;
    v_account_payable_id uuid;
    v_tenant_id uuid;
    v_payment_id uuid;
    v_subtotal numeric(12,3);
    v_tax_amount numeric(12,3);
    v_total_amount numeric(12,3);
    v_pay numeric(12,3);
    v_status int;
    v_status_name VARCHAR;
    v_paid numeric(12,3);
    v_balance numeric(12,3);
BEGIN
    raise notice '';
    raise notice '========================================';
    raise notice '💸 SECCIÓN 5: Pago parcial 30%%';
    raise notice '========================================';

    select 
        sap.purchase_account_payable_id,
        ap.account_payable_id,
        ap.subtotal,
        sap.tax_amount,
        (ap.subtotal + sap.tax_amount) as total_amount,
        t.tenant_id
    into 
        v_purchase_account_payable_id,
        v_account_payable_id,
        v_subtotal,
        v_tax_amount,
        v_total_amount,
        v_tenant_id
    from purchase_schema.purchase_account_payable sap
    join general_schema.account_payable ap on sap.account_payable_id = ap.account_payable_id
    join purchase_schema.purchase_order so on sap.purchase_order_id = so.purchase_order_id
    join purchase_schema.supplier s on so.supplier_id = s.supplier_id
    join purchase_schema.supplier_branch sb on s.supplier_id = sb.supplier_id
    join general_schema.branch b on sb.branch_id = b.branch_id
    join general_schema.tenant t on b.tenant_id = t.tenant_id
    where s.supplier_name = 'Full Flow Supplier'
    limit 1;

    v_pay := round(v_total_amount * 0.30, 3);

    raise notice '   💰 Pago 30%%: $%', v_pay;

    INSERT INTO purchase_schema.purchase_order_payment (
        purchase_account_payable_id, amount_paid, payment_method_id, payment_reference
    ) VALUES (
        v_purchase_account_payable_id, v_pay, 2, 'PAY-30PCT-DEBIT'
    ) returning purchase_order_payment_id into v_payment_id;

    raise notice '   ✓ Pago registrado: %', v_payment_id;

    select 
        sap.account_payable_status,
        aps.status_name,
        ap.amount_paid,
        (ap.subtotal + sap.tax_amount - ap.amount_paid) as balance_remaining
    into v_status, v_status_name, v_paid, v_balance
    from purchase_schema.purchase_account_payable sap
    join general_schema.account_payable ap on sap.account_payable_id = ap.account_payable_id
    join general_schema.account_payable_status aps on sap.account_payable_status = aps.status_id
    where sap.purchase_account_payable_id = v_purchase_account_payable_id;
    
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
DO $$
declare
    v_purchase_account_payable_id uuid;
    v_account_payable_id uuid;
    v_tenant_id uuid;
    v_payment_id uuid;
    v_subtotal numeric(12,3);
    v_tax_amount numeric(12,3);
    v_total_amount numeric(12,3);
    v_paid_so_far numeric(12,3);
    v_remaining numeric(12,3);
    v_pay numeric(12,3);
    v_status int;
    v_status_name VARCHAR;
    v_paid numeric(12,3);
    v_balance numeric(12,3);
    v_invoice_paid BOOLEAN;
    v_is_paid BOOLEAN;
BEGIN
    raise notice '';
    raise notice '========================================';
    raise notice '💸 SECCIÓN 6: Pago final 30%%';
    raise notice '========================================';

    select 
        sap.purchase_account_payable_id,
        ap.account_payable_id,
        ap.subtotal,
        sap.tax_amount,
        (ap.subtotal + sap.tax_amount) as total_amount,
        ap.amount_paid,
        t.tenant_id
    into 
        v_purchase_account_payable_id,
        v_account_payable_id,
        v_subtotal,
        v_tax_amount,
        v_total_amount,
        v_paid_so_far,
        v_tenant_id
    from purchase_schema.purchase_account_payable sap
    join general_schema.account_payable ap on sap.account_payable_id = ap.account_payable_id
    join purchase_schema.purchase_order so on sap.purchase_order_id = so.purchase_order_id
    join purchase_schema.supplier s on so.supplier_id = s.supplier_id
    join purchase_schema.supplier_branch sb on s.supplier_id = sb.supplier_id
    join general_schema.branch b on sb.branch_id = b.branch_id
    join general_schema.tenant t on b.tenant_id = t.tenant_id
    where s.supplier_name = 'Full Flow Supplier'
    limit 1;

    v_remaining := round(v_total_amount - coalesce(v_paid_so_far, 0), 3);
    v_pay := v_remaining;

    raise notice '   💰 Total pendiente: $%', v_remaining;
    raise notice '   💰 Pago final: $%', v_pay;

    INSERT INTO purchase_schema.purchase_order_payment (
        purchase_account_payable_id, amount_paid, payment_method_id, payment_reference
    ) VALUES (
        v_purchase_account_payable_id, v_pay, 3, 'PAY-FINAL-CREDIT'
    ) returning purchase_order_payment_id into v_payment_id;

    raise notice '   ✓ Pago registrado: %', v_payment_id;

    select 
        sap.account_payable_status,
        aps.status_name,
        ap.amount_paid,
        ap.is_paid,
        (ap.subtotal + sap.tax_amount - ap.amount_paid) as balance_remaining
    into v_status, v_status_name, v_paid, v_is_paid, v_balance
    from purchase_schema.purchase_account_payable sap
    join general_schema.account_payable ap on sap.account_payable_id = ap.account_payable_id
    join general_schema.account_payable_status aps on sap.account_payable_status = aps.status_id
    where sap.purchase_account_payable_id = v_purchase_account_payable_id;
    
    select si.paid into v_invoice_paid
    from purchase_schema.supplier_invoice si
    join purchase_schema.purchase_account_payable sap on si.purchase_order_id = sap.purchase_order_id
    where sap.purchase_account_payable_id = v_purchase_account_payable_id;

    raise notice '';
    raise notice '   📊 Estado final de cuenta:';
    raise notice '      Status: % (%)', v_status_name, v_status;
    raise notice '      Pagado total: $%', v_paid;
    raise notice '      Balance: $%', v_balance;
    raise notice '      Is Paid (general_schema): %', v_is_paid;
    raise notice '      Factura pagada: %', v_invoice_paid;

    if v_status <> 3 then
        raise exception '❌ Account payable debería estar en estado "Paid" (3), pero está en: % (%)', v_status_name, v_status;
    end if;

    if not v_is_paid then
        raise exception '❌ La cuenta debería estar marcada como is_paid=true en general_schema.account_payable';
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
DO $$
declare
    v_purchase_order_id uuid;
    v_old_status int;
    v_old_status_name VARCHAR;
    v_new_status int;
    v_new_status_name VARCHAR;
    v_goods_receipt_id uuid;
    v_goods_receipt_total numeric(12,3);
    v_items_count int;
BEGIN
    raise notice '';
    raise notice '========================================';
    raise notice '📦 SECCIÓN 7: Marcar como Delivered';
    raise notice '========================================';

    select so.purchase_order_id, so.purchase_order_status_id, sos.status_name
    into v_purchase_order_id, v_old_status, v_old_status_name
    from purchase_schema.purchase_order so
    join purchase_schema.purchase_order_status sos on so.purchase_order_status_id = sos.status_id
    join purchase_schema.supplier s on so.supplier_id = s.supplier_id
    where s.supplier_name = 'Full Flow Supplier'
    limit 1;

    raise notice '   📦 Order ID: %', v_purchase_order_id;
    raise notice '   📊 Status anterior: % (%)', v_old_status_name, v_old_status;

    update purchase_schema.purchase_order
    set purchase_order_status_id = 3
    where purchase_order_id = v_purchase_order_id;

    select so.purchase_order_status_id, sos.status_name
    into v_new_status, v_new_status_name
    from purchase_schema.purchase_order so
    join purchase_schema.purchase_order_status sos on so.purchase_order_status_id = sos.status_id
    where so.purchase_order_id = v_purchase_order_id;

    raise notice '   ✓ Status actualizado: % (%)', v_new_status_name, v_new_status;

    select goods_receipt_id, total_amount 
    into v_goods_receipt_id, v_goods_receipt_total
    from purchase_schema.goods_receipt
    where purchase_order_id = v_purchase_order_id;

    if v_goods_receipt_id is null then
        raise exception '❌ Goods receipt NO fue creado automáticamente';
    end if;

    select count(*) into v_items_count
    from purchase_schema.goods_receipt_item
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
DO $$
declare
    v_purchase_order_id uuid;
    v_matching_id uuid;
    v_amounts_matched BOOLEAN;
    v_quantities_matched BOOLEAN;
    v_is_matched BOOLEAN;
    v_matched_at timestamp;
    v_goods_receipt_id uuid;
    v_supplier_invoice_id uuid;
    v_order_total numeric(12,3);
    v_invoice_total numeric(12,3);
    v_receipt_total numeric(12,3);
    v_order_qty INTEGER;
    v_invoice_qty INTEGER;
    v_receipt_qty INTEGER;
    v_rec record;
BEGIN
    raise notice '';
    raise notice '========================================';
    raise notice '🔍 SECCIÓN 8: Conciliación a tres vías';
    raise notice '========================================';

    select so.purchase_order_id into v_purchase_order_id
    from purchase_schema.purchase_order so
    join purchase_schema.supplier s on so.supplier_id = s.supplier_id
    where s.supplier_name = 'Full Flow Supplier'
    limit 1;

    select matching_id, amounts_matched, quantities_matched, is_matched, matched_at,
           goods_receipt_id, supplier_invoice_id
    into v_matching_id, v_amounts_matched, v_quantities_matched, v_is_matched, v_matched_at,
         v_goods_receipt_id, v_supplier_invoice_id
    from purchase_schema.three_way_matching
    where purchase_order_id = v_purchase_order_id;

    if v_matching_id is null then
        raise exception '❌ Conciliación NO fue ejecutada automáticamente';
    end if;

    select coalesce(sum(quantity_ordered * unit_price), 0) into v_order_total
    from purchase_schema.purchase_order_item
    where purchase_order_id = v_purchase_order_id;

    select subtotal_amount into v_invoice_total
    from purchase_schema.supplier_invoice
    where supplier_invoice_id = v_supplier_invoice_id;

    select subtotal_amount into v_receipt_total
    from purchase_schema.goods_receipt
    where goods_receipt_id = v_goods_receipt_id;

    select coalesce(sum(quantity_ordered), 0) into v_order_qty
    from purchase_schema.purchase_order_item
    where purchase_order_id = v_purchase_order_id;

    select coalesce(sum(quantity_billed), 0) into v_invoice_qty
    from purchase_schema.supplier_invoice_item
    where supplier_invoice_id = v_supplier_invoice_id;

    select coalesce(sum(quantity_received), 0) into v_receipt_qty
    from purchase_schema.goods_receipt_item
    where goods_receipt_id = v_goods_receipt_id;

    raise notice '   ✅ Conciliación ejecutada automáticamente';
    raise notice '';
    raise notice '   📊 IDs involucrados:';
    raise notice '      Matching ID: %', v_matching_id;
    raise notice '      purchase_schema Order: %', v_purchase_order_id;
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
    
    raise notice '      --- purchase_schema Order Items ---';
    for v_rec in 
        select pv.sku, soi.quantity_ordered
        from purchase_schema.purchase_order_item soi
        join general_schema.product_variant pv on soi.product_variant_id = pv.product_variant_id
        where soi.purchase_order_id = v_purchase_order_id
        order by pv.sku
    loop
        raise notice '         %: % units', v_rec.sku, v_rec.quantity_ordered;
    end loop;

    raise notice '      --- Supplier Invoice Items ---';
    for v_rec in 
        select pv.sku, sii.quantity_billed
        from purchase_schema.supplier_invoice_item sii
        join general_schema.product_variant pv on sii.product_variant_id = pv.product_variant_id
        where sii.supplier_invoice_id = v_supplier_invoice_id
        order by pv.sku
    loop
        raise notice '         %: % units', v_rec.sku, v_rec.quantity_billed;
    end loop;

    raise notice '      --- Goods Receipt Items ---';
    for v_rec in 
        select pv.sku, gri.quantity_received
        from purchase_schema.goods_receipt_item gri
        join general_schema.product_variant pv on gri.product_variant_id = pv.product_variant_id
        where gri.goods_receipt_id = v_goods_receipt_id
        order by pv.sku
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
DO $$
declare
    v_purchase_order_id uuid;
    v_order_status VARCHAR;
    v_account_status VARCHAR;
    v_is_paid BOOLEAN;
    v_invoice_paid BOOLEAN;
    v_goods_receipt_exists BOOLEAN;
    v_matching_exists BOOLEAN;
    v_subtotal numeric(12,3);
    v_tax_amount numeric(12,3);
    v_amount_paid numeric(12,3);
    v_balance numeric(12,3);
    v_invoice_total numeric(12,3);
    v_receipt_total numeric(12,3);
    v_payments_count int;
    v_is_matched BOOLEAN;
BEGIN
    raise notice '';
    raise notice '========================================';
    raise notice '📊 SECCIÓN 9: RESUMEN FINAL';
    raise notice '========================================';

    select 
        so.purchase_order_id,
        sos.status_name,
        aps.status_name,
        ap.is_paid,
        si.paid,
        ap.subtotal,
        sap.tax_amount,
        ap.amount_paid,
        (ap.subtotal + sap.tax_amount - ap.amount_paid) as balance_remaining,
        si.total_amount,
        gr.total_amount
    into 
        v_purchase_order_id,
        v_order_status,
        v_account_status,
        v_is_paid,
        v_invoice_paid,
        v_subtotal,
        v_tax_amount,
        v_amount_paid,
        v_balance,
        v_invoice_total,
        v_receipt_total
    from purchase_schema.purchase_order so
    join purchase_schema.purchase_order_status sos on so.purchase_order_status_id = sos.status_id
    join purchase_schema.purchase_account_payable sap on so.purchase_order_id = sap.purchase_order_id
    join general_schema.account_payable ap on sap.account_payable_id = ap.account_payable_id
    join general_schema.account_payable_status aps on sap.account_payable_status = aps.status_id
    join purchase_schema.supplier_invoice si on so.purchase_order_id = si.purchase_order_id
    join purchase_schema.goods_receipt gr on so.purchase_order_id = gr.purchase_order_id
    join purchase_schema.supplier s on so.supplier_id = s.supplier_id
    where s.supplier_name = 'Full Flow Supplier'
    limit 1;

    select count(*) into v_payments_count
    from purchase_schema.purchase_order_payment sop
    join purchase_schema.purchase_account_payable sap on sop.purchase_account_payable_id = sap.purchase_account_payable_id
    where sap.purchase_order_id = v_purchase_order_id;

    v_goods_receipt_exists := exists(
        select 1 from purchase_schema.goods_receipt 
        where purchase_order_id = v_purchase_order_id
    );
    
    v_matching_exists := exists(
        select 1 from purchase_schema.three_way_matching 
        where purchase_order_id = v_purchase_order_id
    );

    if v_matching_exists then
        select is_matched into v_is_matched
        from purchase_schema.three_way_matching
        where purchase_order_id = v_purchase_order_id;
    end if;

    raise notice '';
    raise notice '┌─────────────────────────────────────────────────────┐';
    raise notice '│           RESUMEN DE FLUJO COMPLETO                 │';
    raise notice '└─────────────────────────────────────────────────────┘';
    raise notice '';
    raise notice '📦 ORDEN DE COMPRA:';
    raise notice '   ID: %', v_purchase_order_id;
    raise notice '   Status: %', v_order_status;
    raise notice '';
    raise notice '💰 CUENTA POR PAGAR:';
    raise notice '   Subtotal: $%', v_subtotal;
    raise notice '   Tax (13%%): $%', v_tax_amount;
    raise notice '   Total: $%', (v_subtotal + v_tax_amount);
    raise notice '   Pagado: $%', v_amount_paid;
    raise notice '   Balance: $%', v_balance;
    raise notice '   Status: %', v_account_status;
    raise notice '   Is Paid (general_schema): %', v_is_paid;
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