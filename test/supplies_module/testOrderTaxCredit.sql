-- TEST: Orden de compra + factura (CREDIT) + pagos en 3 secciones (30%,50%,20%)
-- 1) Limpieza
-- 2) Crear tenant / branch / warehouse / proveedor / productos
-- 3) Crear orden con factura (create_supply_order)
-- 4) SECCIÓN A: Pago 30% (método 1) -> verificar
-- 5) SECCIÓN B: Pago 50% (método 2) -> verificar
-- 6) SECCIÓN C: Pago 20% (método 3) -> verificar y resumen final

-- ========================================
-- SECCIÓN 0: Limpieza inicial
-- ========================================
do $$
begin
    raise notice '🧹 SECCIÓN 0: Limpieza inicial (testOrderPaymentSplit)';
    delete from supplies_module.supply_order_payment where tenant_id in (
        select tenant_id from core.tenant where tenant_name = 'Tenant Test Supplies Split'
    );
    delete from supplies_module.supplier_invoice_item where supplier_invoice_id in (
        select supplier_invoice_id from supplies_module.supplier_invoice si
        join supplies_module.supply_order so on si.supply_order_id = so.supply_order_id
        join supplies_module.supplier_branch sb on so.supplier_id = sb.supplier_id
        join core.branch b on sb.branch_id = b.branch_id
        join core.tenant t on b.tenant_id = t.tenant_id
        where t.tenant_name = 'Tenant Test Supplies Split'
    );
    delete from supplies_module.supplier_invoice where supply_order_id in (
        select supply_order_id from supplies_module.supply_order so
        join supplies_module.supplier_branch sb on so.supplier_id = sb.supplier_id
        join core.branch b on sb.branch_id = b.branch_id
        join core.tenant t on b.tenant_id = t.tenant_id
        where t.tenant_name = 'Tenant Test Supplies Split'
    );
    delete from supplies_module.account_payable where supply_order_id in (
        select supply_order_id from supplies_module.supply_order so
        join supplies_module.supplier_branch sb on so.supplier_id = sb.supplier_id
        join core.branch b on sb.branch_id = b.branch_id
        join core.tenant t on b.tenant_id = t.tenant_id
        where t.tenant_name = 'Tenant Test Supplies Split'
    );
    delete from supplies_module.supply_order_item where supply_order_id in (
        select supply_order_id from supplies_module.supply_order so
        join supplies_module.supplier_branch sb on so.supplier_id = sb.supplier_id
        join core.branch b on sb.branch_id = b.branch_id
        join core.tenant t on b.tenant_id = t.tenant_id
        where t.tenant_name = 'Tenant Test Supplies Split'
    );
    delete from supplies_module.supply_order where supplier_id in (
        select supplier_id from supplies_module.supplier where supplier_name = 'Proveedor Test Split'
    );
    delete from supplies_module.supplier_branch where supplier_id in (
        select supplier_id from supplies_module.supplier where supplier_name = 'Proveedor Test Split'
    );
    delete from supplies_module.supplier where supplier_name = 'Proveedor Test Split';
    delete from inventory_module.warehouse where warehouse_name = 'Warehouse Test Split';
    delete from core.product where sku in ('SPT-001','SPT-002');
    delete from core.branch where branch_name = 'Branch Test Split';
    delete from core.tenant where tenant_name = 'Tenant Test Supplies Split';
    raise notice '✅ Limpieza completada';
end $$;

-- ========================================
-- SECCIÓN 1: Crear tenant, branch, warehouse, proveedor, productos
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_branch_id uuid;
    v_warehouse_id uuid;
    v_supplier_id uuid;
    v_prod1 uuid;
    v_prod2 uuid;
begin
    raise notice '🏗️ SECCIÓN 1: Creación de datos maestros';

    -- Tenant (idempotente)
    insert into core.tenant (tenant_name, region_id, contact_email, is_subscribed)
    values ('Tenant Test Supplies Split', 1, 'supplystest@example.com', true)
    on conflict do nothing;
    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Tenant Test Supplies Split' limit 1;
    raise notice '  Tenant creado/recuperado: %', v_tenant_id;

    -- Branch (idempotente)
    insert into core.branch (tenant_id, branch_name, branch_address, is_main_branch)
    values (v_tenant_id, 'Branch Test Split', 'Calle Test 1', true)
    on conflict do nothing;
    select branch_id into v_branch_id from core.branch where tenant_id = v_tenant_id and branch_name = 'Branch Test Split' limit 1;
    raise notice '  Branch creado/recuperado: %', v_branch_id;

    -- Warehouse (crear si no existe la tabla inventory_module.warehouse)
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

    -- Warehouse insert idempotente (incluye warehouse_address para NOT NULL)
    insert into inventory_module.warehouse (warehouse_name, branch_id, warehouse_address)
    values ('Warehouse Test Split', v_branch_id, 'Dirección Test Split')
    on conflict do nothing;
    select warehouse_id into v_warehouse_id from inventory_module.warehouse where warehouse_name = 'Warehouse Test Split' and branch_id = v_branch_id limit 1;
    raise notice '  Warehouse creado/recuperado: %', v_warehouse_id;

    -- Supplier (idempotente) -> ahora insertamos supplier y mapping en supplier_branch
    insert into supplies_module.supplier (supplier_name, supplier_contact_info, supplier_address)
    values ('Proveedor Test Split', 'contact@suppliertest.local', 'Dirección Proveedor Test')
    on conflict do nothing;
    select supplier_id into v_supplier_id from supplies_module.supplier where supplier_name = 'Proveedor Test Split' limit 1;

    -- Crear mapping supplier_branch (idempotente)
    insert into supplies_module.supplier_branch (supplier_id, branch_id)
    values (v_supplier_id, v_branch_id)
    on conflict do nothing;
    raise notice '  Supplier creado/recuperado: % (mapped to branch %)', v_supplier_id, v_branch_id;

    -- Productos (idempotentes)
    insert into core.product (tenant_id, sku, product_name, unit_price)
    values (v_tenant_id, 'SPT-001', 'Producto SPT A', 100.00)
    on conflict do nothing;
    select product_id into v_prod1 from core.product where tenant_id = v_tenant_id and sku = 'SPT-001' limit 1;

    insert into core.product (tenant_id, sku, product_name, unit_price)
    values (v_tenant_id, 'SPT-002', 'Producto SPT B', 50.00)
    on conflict do nothing;
    select product_id into v_prod2 from core.product where tenant_id = v_tenant_id and sku = 'SPT-002' limit 1;

    raise notice '  Productos creados/recuperados: %, %', v_prod1, v_prod2;
    raise notice '✅ SECCIÓN 1 completada';
end $$;

-- ========================================
-- SECCIÓN 2: Crear orden de compra con factura (CREDIT) usando create_supply_order
-- ========================================
do $$
declare
    v_supplier_id uuid;
    v_warehouse_id uuid;
    v_supply_order_id uuid;
    v_tenant_id uuid;
    v_items jsonb;
    v_account_payable_id uuid;
    v_amount_due numeric(12,3);
    v_supplier_invoice_id uuid;
    v_invoice_total numeric(12,3);
begin
    raise notice '📦 SECCIÓN 2: Crear orden con factura (CREDIT)';

    select supplier_id into v_supplier_id from supplies_module.supplier where supplier_name = 'Proveedor Test Split' limit 1;
    select warehouse_id into v_warehouse_id from inventory_module.warehouse where warehouse_name = 'Warehouse Test Split' limit 1;
    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Tenant Test Supplies Split' limit 1;

    if v_supplier_id is null or v_warehouse_id is null or v_tenant_id is null then
        raise exception 'Datos maestros faltantes';
    end if;

    -- Items: 2 unidades del producto A ($100) y 5 unidades del producto B ($50)
    v_items := jsonb_build_array(
        jsonb_build_object('product_id', (select product_id::text from core.product where tenant_id = v_tenant_id and sku = 'SPT-001' limit 1),
                           'quantity_ordered', 2, 'unit_price', 100.00),
        jsonb_build_object('product_id', (select product_id::text from core.product where tenant_id = v_tenant_id and sku = 'SPT-002' limit 1),
                           'quantity_ordered', 5, 'unit_price', 50.00)
    );

    -- Crear orden sin factura primero (has_invoice = false para evitar el error)
    v_supply_order_id := supplies_module.create_supply_order(
        v_supplier_id,
        v_warehouse_id,
        (current_date + interval '7 days')::date,
        v_items,
        true,      -- has_invoice = true para indicar que habrá factura
        'CREDIT'    -- payment condition
    );

    -- Obtener account_payable creado
    select account_payable_id, subtotal_amount into v_account_payable_id, v_amount_due
    from supplies_module.account_payable
    where supply_order_id = v_supply_order_id
    limit 1;

    raise notice '  Supply order: %', v_supply_order_id;
    raise notice '  Account payable: % (subtotal / amount_due = $%)', v_account_payable_id, v_amount_due;

    -- Crear factura manualmente usando CALL (es un procedimiento)
    call supplies_module.create_supplier_invoice(
        v_supply_order_id,
        v_tenant_id,
        v_amount_due,
        'CREDIT'
    );

    -- Recuperar invoice recién creado
    select supplier_invoice_id, total_amount into v_supplier_invoice_id, v_invoice_total
    from supplies_module.supplier_invoice
    where supply_order_id = v_supply_order_id
    limit 1;

    -- Actualizar account_payable para marcar que tiene factura
    update supplies_module.account_payable
    set has_invoice = true
    where account_payable_id = v_account_payable_id;

    raise notice '  Supplier invoice: % (total = $%)', v_supplier_invoice_id, v_invoice_total;
    raise notice '✅ SECCIÓN 2 completada';
end $$;

-- ========================================
-- SECCIÓN 3: Pago 30% (método 1) -> verificar
-- ========================================
do $$
declare
    v_account_payable_id uuid;
    v_tenant_id uuid;
    v_payment_id uuid;
    v_amount_due numeric(12,3);
    v_pay numeric(12,3);
    v_method int := 1; -- assuming 1 = cash
    v_status int; -- ✅ Nueva variable para account_status
    v_paid numeric(12,3); -- ✅ Nueva variable para amount_paid
    v_balance numeric(12,3); -- ✅ Nueva variable para balance_remaining
begin
    raise notice '💸 SECCIÓN 3: Pago 30%% con método %', v_method;

    select account_payable_id, subtotal_amount into v_account_payable_id, v_amount_due
    from supplies_module.account_payable ap
    join supplies_module.supply_order so on ap.supply_order_id = so.supply_order_id
    join supplies_module.supplier_branch sb on so.supplier_id = sb.supplier_id
    join core.branch b on sb.branch_id = b.branch_id
    join core.tenant t on b.tenant_id = t.tenant_id
    where t.tenant_name = 'Tenant Test Supplies Split'
    limit 1;

    if v_account_payable_id is null then
        raise exception 'Account payable no encontrado';
    end if;

    v_pay := round(v_amount_due * 0.30, 3);

    insert into supplies_module.supply_order_payment (
        tenant_id, account_payable_id, payment_date, amount_paid, payment_method_id, payment_reference, verified
    )
    values (
        (select tenant_id from core.tenant where tenant_name = 'Tenant Test Supplies Split'),
        v_account_payable_id,
        current_timestamp,
        v_pay,
        v_method,
        'PAY-30PCT',
        false
    )
    returning payment_id into v_payment_id;

    raise notice '  Pago creado (30%%): % -> $%', v_payment_id, v_pay;

    -- Verificar pago (cascada: check_account_payable_completion)
    call supplies_module.verify_supply_order_payment(v_payment_id);

    -- Mostrar estado actual (✅ CORREGIDO)
    raise notice '  Estado account_payable después del pago 30%%:';
    select account_status, amount_paid, balance_remaining 
    into v_status, v_paid, v_balance
    from supplies_module.account_payable 
    where account_payable_id = v_account_payable_id;
    
    raise notice '    account_status = %, amount_paid = $%, balance_remaining = $%', 
                 v_status, v_paid, v_balance;

    raise notice '✅ SECCIÓN 3 completada';
end $$;

-- ========================================
-- SECCIÓN 4: Pago 50% (método 2) -> verificar
-- ========================================
do $$
declare
    v_account_payable_id uuid;
    v_payment_id uuid;
    v_amount_due numeric(12,3);
    v_pay numeric(12,3);
    v_method int := 2; -- assuming 2 = debit_card
begin
    raise notice '💸 SECCIÓN 4: Pago 50%% con método %', v_method;

    select account_payable_id, subtotal_amount into v_account_payable_id, v_amount_due
    from supplies_module.account_payable ap
    join supplies_module.supply_order so on ap.supply_order_id = so.supply_order_id
    join supplies_module.supplier_branch sb on so.supplier_id = sb.supplier_id
    join core.branch b on sb.branch_id = b.branch_id
    join core.tenant t on b.tenant_id = t.tenant_id
    where t.tenant_name = 'Tenant Test Supplies Split'
    limit 1;

    if v_account_payable_id is null then
        raise exception 'Account payable no encontrado';
    end if;

    -- Pagar 50% del TOTAL original (no de lo restante) para probar parcial acumulado
    v_pay := round((v_amount_due * 0.50), 3);

    insert into supplies_module.supply_order_payment (
        tenant_id, account_payable_id, payment_date, amount_paid, payment_method_id, payment_reference, verified
    )
    values (
        (select tenant_id from core.tenant where tenant_name = 'Tenant Test Supplies Split'),
        v_account_payable_id,
        current_timestamp,
        v_pay,
        v_method,
        'PAY-50PCT',
        false
    )
    returning payment_id into v_payment_id;

    raise notice '  Pago creado (50%%): % -> $%', v_payment_id, v_pay;

    call supplies_module.verify_supply_order_payment(v_payment_id);

    raise notice '✅ SECCIÓN 4 completada';
end $$;

-- ========================================
-- SECCIÓN 5: Pago 20% (método 3) -> verificar (cierre)
-- ========================================
do $$
declare
    v_account_payable_id uuid;
    v_payment_id uuid;
    v_amount_due numeric(12,3);
    v_paid_so_far numeric(12,3);
    v_remaining numeric(12,3);
    v_pay numeric(12,3);
    v_method int := 3; -- assuming 3 = credit_card
begin
    raise notice '💸 SECCIÓN 5: Pago 20%% con método % (cierre)', v_method;

    select account_payable_id, subtotal_amount, amount_paid into v_account_payable_id, v_amount_due, v_paid_so_far
    from supplies_module.account_payable ap
    join supplies_module.supply_order so on ap.supply_order_id = so.supply_order_id
    join supplies_module.supplier_branch sb on so.supplier_id = sb.supplier_id
    join core.branch b on sb.branch_id = b.branch_id
    join core.tenant t on b.tenant_id = t.tenant_id
    where t.tenant_name = 'Tenant Test Supplies Split'
    limit 1;

    if v_account_payable_id is null then
        raise exception 'Account payable no encontrado';
    end if;

    v_remaining := round(v_amount_due - coalesce(v_paid_so_far,0), 3);
    v_pay := round(v_amount_due * 0.20, 3);

    -- Si rounding produce ligero excedente/deficit, ajustamos para no dejar centavos pendientes
    if v_pay > v_remaining then
        v_pay := v_remaining;
    end if;

    insert into supplies_module.supply_order_payment (
        tenant_id, account_payable_id, payment_date, amount_paid, payment_method_id, payment_reference, verified
    )
    values (
        (select tenant_id from core.tenant where tenant_name = 'Tenant Test Supplies Split'),
        v_account_payable_id,
        current_timestamp,
        v_pay,
        v_method,
        'PAY-20PCT',
        false
    )
    returning payment_id into v_payment_id;

    raise notice '  Pago creado (20%%): % -> $%', v_payment_id, v_pay;

    call supplies_module.verify_supply_order_payment(v_payment_id);

    raise notice '';
    raise notice '📋 RESUMEN FINAL (account_payable):';
    select account_payable_id, subtotal_amount, amount_paid, balance_remaining, account_status
    into v_account_payable_id, v_amount_due, v_paid_so_far, v_remaining, v_method
    from supplies_module.account_payable where account_payable_id = v_account_payable_id;

    raise notice '  Account: %', v_account_payable_id;
    raise notice '  Subtotal (amount_due): $%', v_amount_due;
    raise notice '  Amount paid: $%', v_paid_so_far;
    raise notice '  Balance remaining: $%', v_remaining;
    raise notice '  Status: %', v_method;

    raise notice '✅ SECCIÓN 5 completada';
end $$;