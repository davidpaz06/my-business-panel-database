-- TEST: Orden de compra (CONTADO) sin factura/impuesto + pago único (IN_FULL)
-- 1) Limpieza
-- 2) Crear tenant / branch / warehouse / proveedor / productos
-- 3) Crear orden con has_invoice = false, payment_condition = 'IN_FULL'
-- 4) Insertar pago 100% (método cash) -> verificar
-- 5) Resumen final

-- ========================================
-- SECCIÓN 0: Limpieza inicial
-- ========================================
do $$
begin
    raise notice '🧹 SECCIÓN 0: Limpieza inicial (testOrderCashNoTax)';
    delete from supplies_module.supply_order_payment where tenant_id in (
        select tenant_id from core.tenant where tenant_name = 'Tenant Test Supplies Cash NoTax'
    );
    delete from supplies_module.account_payable where supply_order_id in (
        select supply_order_id from supplies_module.supply_order so
        join supplies_module.supplier_branch sb on so.supplier_id = sb.supplier_id
        join core.branch b on sb.branch_id = b.branch_id
        join core.tenant t on b.tenant_id = t.tenant_id
        where t.tenant_name = 'Tenant Test Supplies Cash NoTax'
    );
    delete from supplies_module.supply_order_item where supply_order_id in (
        select supply_order_id from supplies_module.supply_order so
        join supplies_module.supplier_branch sb on so.supplier_id = sb.supplier_id
        join core.branch b on sb.branch_id = b.branch_id
        join core.tenant t on b.tenant_id = t.tenant_id
        where t.tenant_name = 'Tenant Test Supplies Cash NoTax'
    );
    delete from supplies_module.supply_order where supplier_id in (
        select supplier_id from supplies_module.supplier where supplier_name = 'Proveedor Test Cash NoTax'
    );
    delete from supplies_module.supplier_branch where supplier_id in (
        select supplier_id from supplies_module.supplier where supplier_name = 'Proveedor Test Cash NoTax'
    );
    delete from supplies_module.supplier where supplier_name = 'Proveedor Test Cash NoTax';
    delete from inventory_module.warehouse where warehouse_name = 'Warehouse Test Cash NoTax';
    delete from core.product where sku in ('CNT-001','CNT-002');
    delete from core.branch where branch_name = 'Branch Test Cash NoTax';
    delete from core.tenant where tenant_name = 'Tenant Test Supplies Cash NoTax';
    raise notice '✅ Limpieza completada';
end $$;

-- ========================================
-- SECCIÓN 1: Crear datos maestros
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
    raise notice '🏗️ SECCIÓN 1: Creación de datos maestros (cash, no tax)';

    -- Tenant (idempotente)
    insert into core.tenant (tenant_name, region_id, contact_email, is_subscribed)
    values ('Tenant Test Supplies Cash NoTax', 1, 'cashnotax@example.com', true)
    on conflict do nothing;
    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Tenant Test Supplies Cash NoTax' limit 1;

    -- Branch (idempotente)
    insert into core.branch (tenant_id, branch_name, branch_address, is_main_branch)
    values (v_tenant_id, 'Branch Test Cash NoTax', 'Calle Contado 1', true)
    on conflict do nothing;
    select branch_id into v_branch_id from core.branch where tenant_id = v_tenant_id and branch_name = 'Branch Test Cash NoTax' limit 1;

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

    -- Warehouse insert idempotente (incluye warehouse_address)
    insert into inventory_module.warehouse (warehouse_name, branch_id, warehouse_address)
    values ('Warehouse Test Cash NoTax', v_branch_id, 'Dirección Test Cash NoTax')
    on conflict do nothing;
    select warehouse_id into v_warehouse_id from inventory_module.warehouse where warehouse_name = 'Warehouse Test Cash NoTax' and branch_id = v_branch_id limit 1;

    -- Supplier (idempotente)
    insert into supplies_module.supplier (supplier_name, supplier_contact_info, supplier_address)
    values ('Proveedor Test Cash NoTax', 'contact@cashnotax.local', 'Dirección Proveedor Cash NoTax')
    on conflict do nothing
    returning supplier_id into v_supplier_id;

    insert into supplies_module.supplier_branch (supplier_id, branch_id)
    values (v_supplier_id, v_branch_id)
    on conflict do nothing;
    -- Productos (idempotentes)
    insert into core.product (tenant_id, sku, product_name, unit_price)
    values (v_tenant_id, 'CNT-001', 'Producto CNT A', 200.00)
    on conflict do nothing;
    select product_id into v_prod1 from core.product where tenant_id = v_tenant_id and sku = 'CNT-001' limit 1;

    insert into core.product (tenant_id, sku, product_name, unit_price)
    values (v_tenant_id, 'CNT-002', 'Producto CNT B', 75.00)
    on conflict do nothing;
    select product_id into v_prod2 from core.product where tenant_id = v_tenant_id and sku = 'CNT-002' limit 1;

    raise notice '  Tenant: %, Branch: %, Warehouse: %, Supplier: %', v_tenant_id, v_branch_id, v_warehouse_id, v_supplier_id;
    raise notice '  Productos: %, %', v_prod1, v_prod2;
    raise notice '✅ SECCIÓN 1 completada';
end $$;

-- ========================================
-- SECCIÓN 2: Crear orden CONTADO sin factura (has_invoice = false)
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
begin
    raise notice '📦 SECCIÓN 2: Crear orden CONTADO (no invoice → sin impuesto)';

    select supplier_id into v_supplier_id from supplies_module.supplier where supplier_name = 'Proveedor Test Cash NoTax' limit 1;
    select warehouse_id into v_warehouse_id from inventory_module.warehouse where warehouse_name = 'Warehouse Test Cash NoTax' limit 1;
    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Tenant Test Supplies Cash NoTax' limit 1;

    if v_supplier_id is null or v_warehouse_id is null or v_tenant_id is null then
        raise exception 'Datos maestros faltantes';
    end if;

    v_items := jsonb_build_array(
        jsonb_build_object('product_id', (select product_id::text from core.product where tenant_id = v_tenant_id and sku = 'CNT-001' limit 1),
                           'quantity_ordered', 1, 'unit_price', 200.00),
        jsonb_build_object('product_id', (select product_id::text from core.product where tenant_id = v_tenant_id and sku = 'CNT-002' limit 1),
                           'quantity_ordered', 2, 'unit_price', 75.00)
    );

    -- p_has_invoice = false para no crear supplier_invoice (sin impuestos)
    v_supply_order_id := supplies_module.create_supply_order(
        v_supplier_id,
        v_warehouse_id,
        (current_date + interval '3 days')::date,
        v_items,
        false,      -- has_invoice = false -> no invoice / no tax
        'IN_FULL'   -- payment condition = contado
    );

    select account_payable_id, subtotal_amount into v_account_payable_id, v_amount_due
    from supplies_module.account_payable
    where supply_order_id = v_supply_order_id
    limit 1;

    raise notice '  Supply order: %', v_supply_order_id;
    raise notice '  Account payable: % (amount_due = $%)', v_account_payable_id, v_amount_due;
    raise notice '✅ SECCIÓN 2 completada';
end $$;

-- ========================================
-- SECCIÓN 3: Pago completo 100% (método efectivo) -> verificar
-- ========================================
do $$
declare
    v_account_payable_id uuid;
    v_payment_id uuid;
    v_amount_due numeric(12,3);
    v_pay numeric(12,3);
    v_method int := 1; -- 1 = cash (ajustar si es necesario)
    v_status int; -- ✅ Nueva variable para account_status
    v_paid numeric(12,3); -- ✅ Nueva variable para amount_paid
    v_balance numeric(12,3); -- ✅ Nueva variable para balance_remaining
begin

    select account_payable_id, subtotal_amount into v_account_payable_id, v_amount_due
    from supplies_module.account_payable ap
    join supplies_module.supply_order so on ap.supply_order_id = so.supply_order_id
    join supplies_module.supplier_branch sb on so.supplier_id = sb.supplier_id
    join core.branch b on sb.branch_id = b.branch_id
    join core.tenant t on b.tenant_id = t.tenant_id
    where t.tenant_name = 'Tenant Test Supplies Cash NoTax'
    limit 1;

    if v_account_payable_id is null then
        raise exception 'Account payable no encontrado';
    end if;

    v_pay := round(v_amount_due, 3);

    insert into supplies_module.supply_order_payment (
        tenant_id, account_payable_id, payment_date, amount_paid, payment_method_id, payment_reference, verified
    )
    values (
        (select tenant_id from core.tenant where tenant_name = 'Tenant Test Supplies Cash NoTax'),
        v_account_payable_id,
        current_timestamp,
        v_pay,
        v_method,
        'PAY-IN_FULL',
        false
    )
    returning payment_id into v_payment_id;

    raise notice '  Pago creado (100%%): % -> $%', v_payment_id, v_pay;

    -- Verificar pago (dispara check_account_payable_completion)
    call supplies_module.verify_supply_order_payment(v_payment_id);

    perform pg_sleep(0.3); -- dar tiempo a triggers

    raise notice '📋 RESUMEN FINAL (account_payable):';
    -- ✅ CORREGIDO: usar variables separadas y obtener balance de la columna generada
    select account_payable_id, subtotal_amount, amount_paid, balance_remaining, account_status
    into v_account_payable_id, v_amount_due, v_paid, v_balance, v_status
    from supplies_module.account_payable 
    where account_payable_id = v_account_payable_id;

    raise notice '  Account: %', v_account_payable_id;
    raise notice '  Subtotal (amount_due): $%', v_amount_due;
    raise notice '  Amount paid: $%', v_paid;
    raise notice '  Balance remaining: $%', v_balance;
    raise notice '  Status: %', v_status;
    raise notice '✅ SECCIÓN 3 completada';
end $$;