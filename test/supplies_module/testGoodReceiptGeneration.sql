-- TEST: Generación automática de goods_receipt al actualizar status a 'Delivered'
-- 1) Limpieza inicial
-- 2) Crear tenant / branch / warehouse / proveedor / productos
-- 3) Crear orden de compra (PENDING)
-- 4) Verificar que NO existe goods_receipt
-- 5) Actualizar status a 'Delivered' (status_id = 3)
-- 6) Verificar creación automática de goods_receipt y montos/items
-- 7) Verificar idempotencia (no duplicar goods_receipt)
-- 8) Resumen final

-- ========================================
-- SECCIÓN 0: Limpieza inicial
-- ========================================
do $$
begin
    raise notice '🧹 SECCIÓN 0: Limpieza inicial (testGoodsReceiptGeneration)';

    delete from supplies_module.goods_receipt where supply_order_id in (
        select so.supply_order_id from supplies_module.supply_order so
        join supplies_module.supplier_branch sb on so.supplier_id = sb.supplier_id
        join core.branch b on sb.branch_id = b.branch_id
        join core.tenant t on b.tenant_id = t.tenant_id
        where t.tenant_name = 'Tenant Test Goods Receipt'
    );

    delete from supplies_module.goods_receipt_item where goods_receipt_id in (
        select gr.goods_receipt_id from supplies_module.goods_receipt gr
        join supplies_module.supply_order so on gr.supply_order_id = so.supply_order_id
        join supplies_module.supplier_branch sb on so.supplier_id = sb.supplier_id
        join core.branch b on sb.branch_id = b.branch_id
        join core.tenant t on b.tenant_id = t.tenant_id
        where t.tenant_name = 'Tenant Test Goods Receipt'
    );

    delete from supplies_module.supplier_invoice_item where supplier_invoice_id in (
        select si.supplier_invoice_id from supplies_module.supplier_invoice si
        join supplies_module.supply_order so on si.supply_order_id = so.supply_order_id
        join supplies_module.supplier_branch sb on so.supplier_id = sb.supplier_id
        join core.branch b on sb.branch_id = b.branch_id
        join core.tenant t on b.tenant_id = t.tenant_id
        where t.tenant_name = 'Tenant Test Goods Receipt'
    );

    delete from supplies_module.supplier_invoice where supply_order_id in (
        select so.supply_order_id from supplies_module.supply_order so
        join supplies_module.supplier_branch sb on so.supplier_id = sb.supplier_id
        join core.branch b on sb.branch_id = b.branch_id
        join core.tenant t on b.tenant_id = t.tenant_id
        where t.tenant_name = 'Tenant Test Goods Receipt'
    );

    delete from supplies_module.account_payable where supply_order_id in (
        select so.supply_order_id from supplies_module.supply_order so
        join supplies_module.supplier_branch sb on so.supplier_id = sb.supplier_id
        join core.branch b on sb.branch_id = b.branch_id
        join core.tenant t on b.tenant_id = t.tenant_id
        where t.tenant_name = 'Tenant Test Goods Receipt'
    );

    delete from supplies_module.supply_order_item where supply_order_id in (
        select so.supply_order_id from supplies_module.supply_order so
        join supplies_module.supplier_branch sb on so.supplier_id = sb.supplier_id
        join core.branch b on sb.branch_id = b.branch_id
        join core.tenant t on b.tenant_id = t.tenant_id
        where t.tenant_name = 'Tenant Test Goods Receipt'
    );

    delete from supplies_module.supply_order where supplier_id in (
        select supplier_id from supplies_module.supplier where supplier_name = 'Proveedor Test Goods Receipt'
    );

    delete from supplies_module.supplier_branch where supplier_id in (
        select supplier_id from supplies_module.supplier where supplier_name = 'Proveedor Test Goods Receipt'
    );

    delete from supplies_module.supplier where supplier_name = 'Proveedor Test Goods Receipt';
    delete from inventory_module.warehouse where warehouse_name = 'Warehouse Test Goods Receipt';
    delete from core.product where sku in ('GR-001','GR-002');
    delete from core.branch where branch_name = 'Branch Test Goods Receipt';
    delete from core.tenant where tenant_name = 'Tenant Test Goods Receipt';

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
    raise notice '🏗️ SECCIÓN 1: Creación de datos maestros';

    insert into core.tenant (tenant_name, region_id, contact_email, is_subscribed)
    values ('Tenant Test Goods Receipt', 1, 'goodsreceipt@example.com', true)
    on conflict do nothing;
    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Tenant Test Goods Receipt' limit 1;

    insert into core.branch (tenant_id, branch_name, branch_address, is_main_branch)
    values (v_tenant_id, 'Branch Test Goods Receipt', 'Calle Receipt 123', true)
    on conflict do nothing;
    select branch_id into v_branch_id from core.branch where tenant_id = v_tenant_id and branch_name = 'Branch Test Goods Receipt' limit 1;

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
    values ('Warehouse Test Goods Receipt', v_branch_id, 'Dirección Warehouse Receipt')
    on conflict do nothing;
    select warehouse_id into v_warehouse_id from inventory_module.warehouse where warehouse_name = 'Warehouse Test Goods Receipt' and branch_id = v_branch_id limit 1;

    -- Supplier (idempotente) y mapping supplier_branch
    insert into supplies_module.supplier (supplier_name, supplier_contact_info, supplier_address)
    values ('Proveedor Test Goods Receipt', 'contact@goodsreceipt.local', 'Dirección Proveedor Receipt')
    on conflict (supplier_name) do nothing
    returning supplier_id into v_supplier_id;

    if v_supplier_id is null then
        select supplier_id into v_supplier_id from supplies_module.supplier where supplier_name = 'Proveedor Test Goods Receipt' limit 1;
    end if;

    insert into supplies_module.supplier_branch (supplier_id, branch_id)
    values (v_supplier_id, v_branch_id)
    on conflict do nothing;

    -- Productos
    insert into core.product (tenant_id, sku, product_name, unit_price)
    values (v_tenant_id, 'GR-001', 'Producto GR A', 150.00)
    on conflict do nothing;
    select product_id into v_prod1 from core.product where tenant_id = v_tenant_id and sku = 'GR-001' limit 1;

    insert into core.product (tenant_id, sku, product_name, unit_price)
    values (v_tenant_id, 'GR-002', 'Producto GR B', 80.00)
    on conflict do nothing;
    select product_id into v_prod2 from core.product where tenant_id = v_tenant_id and sku = 'GR-002' limit 1;

    raise notice '  Tenant: %, Branch: %, Warehouse: %, Supplier: %', v_tenant_id, v_branch_id, v_warehouse_id, v_supplier_id;
    raise notice '  Productos: %, %', v_prod1, v_prod2;
    raise notice '✅ SECCIÓN 1 completada';
end $$;

-- ========================================
-- SECCIÓN 2: Crear orden de compra (status PENDING)
-- ========================================
do $$
declare
    v_supplier_id uuid;
    v_warehouse_id uuid;
    v_supply_order_id uuid;
    v_tenant_id uuid;
    v_items jsonb;
    v_current_status int;
begin
    raise notice '📦 SECCIÓN 2: Crear orden de compra (PENDING)';

    select supplier_id into v_supplier_id from supplies_module.supplier where supplier_name = 'Proveedor Test Goods Receipt' limit 1;
    select warehouse_id into v_warehouse_id from inventory_module.warehouse where warehouse_name = 'Warehouse Test Goods Receipt' limit 1;
    select tenant_id into v_tenant_id from core.tenant where tenant_name = 'Tenant Test Goods Receipt' limit 1;

    if v_supplier_id is null or v_warehouse_id is null or v_tenant_id is null then
        raise exception 'Datos maestros faltantes';
    end if;

    v_items := jsonb_build_array(
        jsonb_build_object('product_id', (select product_id::text from core.product where tenant_id = v_tenant_id and sku = 'GR-001' limit 1),
                           'quantity_ordered', 3, 'unit_price', 150.00),
        jsonb_build_object('product_id', (select product_id::text from core.product where tenant_id = v_tenant_id and sku = 'GR-002' limit 1),
                           'quantity_ordered', 4, 'unit_price', 80.00)
    );

    v_supply_order_id := supplies_module.create_supply_order(
        v_supplier_id,
        v_warehouse_id,
        (current_date + interval '5 days')::date,
        v_items,
        false,      -- has_invoice = false
        'IN_FULL'   -- payment condition
    );

    select supply_order_status_id into v_current_status
    from supplies_module.supply_order
    where supply_order_id = v_supply_order_id;

    raise notice '  Supply order creado: %', v_supply_order_id;
    raise notice '  Status actual: % (1 = Pending)', v_current_status;
    raise notice '✅ SECCIÓN 2 completada';
end $$;

-- ========================================
-- SECCIÓN 3: Verificar que NO existe goods_receipt (antes de Delivered)
-- ========================================
do $$
declare
    v_supply_order_id uuid;
    v_goods_receipt_count int;
begin
    raise notice '🔍 SECCIÓN 3: Verificar ausencia de goods_receipt (antes de Delivered)';

    select so.supply_order_id into v_supply_order_id
    from supplies_module.supply_order so
    join supplies_module.supplier_branch sb on so.supplier_id = sb.supplier_id
    join core.branch b on sb.branch_id = b.branch_id
    join core.tenant t on b.tenant_id = t.tenant_id
    where t.tenant_name = 'Tenant Test Goods Receipt'
    limit 1;

    if v_supply_order_id is null then
        raise exception 'Supply order no encontrado';
    end if;

    select count(*) into v_goods_receipt_count
    from supplies_module.goods_receipt
    where supply_order_id = v_supply_order_id;

    if v_goods_receipt_count > 0 then
        raise exception '❌ ERROR: Goods receipt ya existe (no debería existir aún)';
    end if;

    raise notice '  ✅ Confirmado: No existe goods_receipt para order %', v_supply_order_id;
    raise notice '✅ SECCIÓN 3 completada';
end $$;

-- ========================================
-- SECCIÓN 4: Actualizar status a 'Delivered' (trigger goods_receipt)
-- ========================================
do $$
declare
    v_supply_order_id uuid;
    v_old_status int;
    v_new_status int;
begin
    raise notice '🚚 SECCIÓN 4: Actualizar status a Delivered (status_id = 3)';

    select so.supply_order_id, so.supply_order_status_id into v_supply_order_id, v_old_status
    from supplies_module.supply_order so
    join supplies_module.supplier_branch sb on so.supplier_id = sb.supplier_id
    join core.branch b on sb.branch_id = b.branch_id
    join core.tenant t on b.tenant_id = t.tenant_id
    where t.tenant_name = 'Tenant Test Goods Receipt'
    limit 1;

    if v_supply_order_id is null then
        raise exception 'Supply order no encontrado';
    end if;

    raise notice '  Supply order: %', v_supply_order_id;
    raise notice '  Status anterior: %', v_old_status;

    update supplies_module.supply_order
    set supply_order_status_id = 3,
        updated_at = current_timestamp
    where supply_order_id = v_supply_order_id;

    select supply_order_status_id into v_new_status
    from supplies_module.supply_order
    where supply_order_id = v_supply_order_id;

    raise notice '  Status actualizado: %', v_new_status;
    raise notice '✅ SECCIÓN 4 completada';
end $$;

-- ========================================
-- SECCIÓN 5: Verificar creación automática de goods_receipt y contenidos
-- ========================================
do $$
declare
    v_supply_order_id uuid;
    v_goods_receipt_id uuid;
    v_received_date timestamp;
    v_goods_receipt_count int;
    v_expected_total numeric(12,3);
    v_gr_total numeric(12,3);
    v_items_expected int;
    v_items_copied int;
    v_mismatch_count int;
begin
    raise notice '✅ SECCIÓN 5: Verificar creación automática de goods_receipt y contenidos';

    select so.supply_order_id into v_supply_order_id
    from supplies_module.supply_order so
    join supplies_module.supplier_branch sb on so.supplier_id = sb.supplier_id
    join core.branch b on sb.branch_id = b.branch_id
    join core.tenant t on b.tenant_id = t.tenant_id
    where t.tenant_name = 'Tenant Test Goods Receipt'
    limit 1;

    select count(*) into v_goods_receipt_count
    from supplies_module.goods_receipt
    where supply_order_id = v_supply_order_id;

    if v_goods_receipt_count = 0 then
        raise exception '❌ ERROR: Goods receipt NO fue creado por el trigger';
    elsif v_goods_receipt_count > 1 then
        raise exception '❌ ERROR: Múltiples goods_receipt creados (debería ser 1)';
    end if;

    select goods_receipt_id, received_date, total_amount into v_goods_receipt_id, v_received_date, v_gr_total
    from supplies_module.goods_receipt
    where supply_order_id = v_supply_order_id
    limit 1;

    -- expected total via helper function (sum of quantity * unit_price)
    select supplies_module.calculate_supply_order_total(v_supply_order_id) into v_expected_total;

    if round(v_expected_total::numeric,3) is distinct from round(v_gr_total::numeric,3) then
        raise exception '❌ ERROR: Total mismatch. expected $% vs goods_receipt $%', v_expected_total, v_gr_total;
    end if;

    -- items count check
    select count(*) into v_items_expected from supplies_module.supply_order_item where supply_order_id = v_supply_order_id;
    select count(*) into v_items_copied from supplies_module.goods_receipt_item where goods_receipt_id = v_goods_receipt_id;

    if v_items_expected <> v_items_copied then
        raise exception '❌ ERROR: Items count mismatch. expected % items vs copied % items', v_items_expected, v_items_copied;
    end if;

    -- verify quantities match per product
    select count(*) into v_mismatch_count
    from (
        select soi.product_id, soi.quantity_ordered as q_ordered, gri.quantity_received as q_received
        from supplies_module.supply_order_item soi
        left join supplies_module.goods_receipt_item gri on gri.product_id = soi.product_id and gri.goods_receipt_id = v_goods_receipt_id
        where soi.supply_order_id = v_supply_order_id
    ) t
    where q_ordered is distinct from q_received;

    if v_mismatch_count > 0 then
        raise exception '❌ ERROR: Hay discrepancias en cantidades entre supply_order_item y goods_receipt_item';
    end if;

    raise notice '  ✅ Goods receipt creado: %', v_goods_receipt_id;
    raise notice '  Fecha de recepción: %', v_received_date;
    raise notice '  Total verificado: $%', v_gr_total;
    raise notice '  Items verificados: %', v_items_copied;
    raise notice '✅ SECCIÓN 5 completada';
end $$;

-- ========================================
-- SECCIÓN 6: Verificar idempotencia (no duplicar goods_receipt)
-- ========================================
do $$
declare
    v_supply_order_id uuid;
    v_before int;
    v_after int;
begin
    raise notice '🔁 SECCIÓN 6: Verificar idempotencia (no duplicar goods_receipt)';

    select so.supply_order_id into v_supply_order_id
    from supplies_module.supply_order so
    join supplies_module.supplier_branch sb on so.supplier_id = sb.supplier_id
    join core.branch b on sb.branch_id = b.branch_id
    join core.tenant t on b.tenant_id = t.tenant_id
    where t.tenant_name = 'Tenant Test Goods Receipt'
    limit 1;

    select count(*) into v_before from supplies_module.goods_receipt where supply_order_id = v_supply_order_id;

    update supplies_module.supply_order
    set supply_order_status_id = 3,
        updated_at = current_timestamp
    where supply_order_id = v_supply_order_id;

    select count(*) into v_after from supplies_module.goods_receipt where supply_order_id = v_supply_order_id;

    if v_after <> v_before then
        raise exception '❌ ERROR: Goods receipt duplicado (no idempotente)';
    end if;

    raise notice '  ✅ Idempotencia confirmada: No se duplicó goods_receipt';
    raise notice '✅ SECCIÓN 6 completada';
end $$;

-- ========================================
-- SECCIÓN 7: Resumen final
-- ========================================
do $$
declare
    v_supply_order_id uuid;
    v_status int;
    v_status_name varchar;
    v_goods_receipt_id uuid;
    v_received_date timestamp;
    v_total numeric(12,3);
begin
    raise notice '📋 SECCIÓN 7: RESUMEN FINAL';

    select so.supply_order_id, so.supply_order_status_id, sos.status_name
    into v_supply_order_id, v_status, v_status_name
    from supplies_module.supply_order so
    join supplies_module.supply_order_status sos on so.supply_order_status_id = sos.status_id
    join supplies_module.supplier_branch sb on so.supplier_id = sb.supplier_id
    join core.branch b on sb.branch_id = b.branch_id
    join core.tenant t on b.tenant_id = t.tenant_id
    where t.tenant_name = 'Tenant Test Goods Receipt'
    limit 1;

    select goods_receipt_id, received_date, total_amount into v_goods_receipt_id, v_received_date, v_total
    from supplies_module.goods_receipt where supply_order_id = v_supply_order_id;

    raise notice '  Supply Order: %', v_supply_order_id;
    raise notice '  Status: % (%)', v_status, v_status_name;
    raise notice '  Goods Receipt: %', v_goods_receipt_id;
    raise notice '  Received Date: %', v_received_date;
    raise notice '  Total: $%', v_total;
    raise notice '✅ TEST COMPLETADO';
end $$;