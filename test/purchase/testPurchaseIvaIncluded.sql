-- =====================================
-- TEST: IVA INCLUIDO EN EL COSTO DE COMPRAS
-- =====================================
-- Purpose: create_purchase_order() no debe sumar IVA sobre el costo del
--          producto (cost_price ya lo incluye). El IVA se desglosa:
--          base = bruto / (1 + tasa), iva = bruto - base, y base + iva = bruto.
-- Migration: migrations/purchase/041-purchase-order-cost-includes-iva.sql
-- Idempotent: limpia sus propios datos al inicio y al final.
-- =====================================

-- ========================================
-- SECTION 0: Cleanup
-- ========================================
DO $$
DECLARE
    v_tenant_ids uuid[];
    v_payable_ids uuid[];
BEGIN
    select array_agg(tenant_id) into v_tenant_ids
    from general_schema.tenant
    where tenant_name in ('IVA Test VE', 'IVA Test 13');

    select array_agg(pap.account_payable_id) into v_payable_ids
    from purchase_schema.purchase_account_payable pap
    join purchase_schema.purchase_order po on po.purchase_order_id = pap.purchase_order_id
    join purchase_schema.supplier s on s.supplier_id = po.supplier_id
    where s.supplier_name in ('IVA Test Supplier VE', 'IVA Test Supplier 13');

    delete from purchase_schema.purchase_order
    where supplier_id in (
        select supplier_id from purchase_schema.supplier
        where supplier_name in ('IVA Test Supplier VE', 'IVA Test Supplier 13')
    );
    delete from general_schema.account_payable where account_payable_id = any(v_payable_ids);
    delete from general_schema.product_variant where tenant_id = any(v_tenant_ids);
    delete from inventory_schema.warehouse
    where branch_id in (select branch_id from general_schema.branch where tenant_id = any(v_tenant_ids));
    delete from purchase_schema.supplier
    where supplier_name in ('IVA Test Supplier VE', 'IVA Test Supplier 13');
    delete from general_schema.branch where tenant_id = any(v_tenant_ids);
    delete from general_schema.tenant where tenant_id = any(v_tenant_ids);
    delete from general_schema.tax_rate where region = 'IVA Test Region 13';
    delete from general_schema.region where region_name = 'IVA Test Region 13';
END $$;

-- ========================================
-- SECTION 1: Setup
-- ========================================
DO $$
DECLARE
    v_ve_region int;
    v_test_region int;
    v_tenant uuid;
    v_branch uuid;
BEGIN
    select region_id into v_ve_region from general_schema.region where region_name = 'Venezuela';

    insert into general_schema.region (region_name) values ('IVA Test Region 13')
    returning region_id into v_test_region;
    insert into general_schema.tax_rate (region, region_id, rate_percentage)
    values ('IVA Test Region 13', v_test_region, 13.00);

    -- Tenant en Venezuela (la region tiene dos tarifas: Exento 0% e IVA 16%)
    insert into general_schema.tenant (tenant_name, region_id, identification, contact_email)
    values ('IVA Test VE', v_ve_region, 'IVA-TEST-VE', 'iva-ve@test.com')
    returning tenant_id into v_tenant;
    insert into general_schema.branch (tenant_id, branch_name) values (v_tenant, 'Sucursal VE')
    returning branch_id into v_branch;
    insert into inventory_schema.warehouse (branch_id, warehouse_name, warehouse_address)
    values (v_branch, 'Bodega VE', 'Direccion');
    insert into purchase_schema.supplier (supplier_name, added_by) values ('IVA Test Supplier VE', v_tenant);
    insert into general_schema.product_variant (tenant_id, sku, variant_name, cost_price, unit_price)
    values (v_tenant, 'IVA-VE-58', 'Producto costo 58', 58.00, 100.00),
           (v_tenant, 'IVA-VE-10', 'Producto costo 10', 10.00, 20.00);

    -- Tenant en una region con IVA 13% (caso reportado por el cliente)
    insert into general_schema.tenant (tenant_name, region_id, identification, contact_email)
    values ('IVA Test 13', v_test_region, 'IVA-TEST-13', 'iva-13@test.com')
    returning tenant_id into v_tenant;
    insert into general_schema.branch (tenant_id, branch_name) values (v_tenant, 'Sucursal 13')
    returning branch_id into v_branch;
    insert into inventory_schema.warehouse (branch_id, warehouse_name, warehouse_address)
    values (v_branch, 'Bodega 13', 'Direccion');
    insert into purchase_schema.supplier (supplier_name, added_by) values ('IVA Test Supplier 13', v_tenant);
    insert into general_schema.product_variant (tenant_id, sku, variant_name, cost_price, unit_price)
    values (v_tenant, 'IVA-13-113', 'Producto costo 113', 113.00, 200.00);
END $$;

-- ========================================
-- SECTION 2: Asserts
-- ========================================
DO $$
DECLARE
    v_order uuid;
    v_subtotal numeric;
    v_tax numeric;
    v_inv_subtotal numeric;
    v_inv_total numeric;
    v_rate numeric;
BEGIN
    -- Caso 1 (Venezuela 16%): 2 x 58.00 = 116.00 con IVA -> base 100.000, IVA 16.000
    v_order := purchase_schema.create_purchase_order(
        (select supplier_id from purchase_schema.supplier where supplier_name = 'IVA Test Supplier VE'),
        (select w.warehouse_id from inventory_schema.warehouse w where w.warehouse_name = 'Bodega VE'),
        current_date + 30,
        jsonb_build_array(jsonb_build_object(
            'product_variant_id', (select product_variant_id from general_schema.product_variant where sku = 'IVA-VE-58')::text,
            'quantity_ordered', 2)),
        true, 'CREDIT', current_date + 30);

    select ap.subtotal, pap.tax_amount
    into v_subtotal, v_tax
    from purchase_schema.purchase_account_payable pap
    join general_schema.account_payable ap on ap.account_payable_id = pap.account_payable_id
    where pap.purchase_order_id = v_order;

    if v_subtotal <> 100.000 or v_tax <> 16.000 then
        raise exception 'FAIL caso 1: subtotal=% tax=% (esperado 100.000 / 16.000)', v_subtotal, v_tax;
    end if;
    if v_subtotal + v_tax <> 116.000 then
        raise exception 'FAIL caso 1: total=% (esperado 116.000, el costo capturado)', v_subtotal + v_tax;
    end if;

    select si.subtotal_amount, si.total_amount, si.tax_rate
    into v_inv_subtotal, v_inv_total, v_rate
    from purchase_schema.supplier_invoice si where si.purchase_order_id = v_order;
    if v_inv_subtotal <> 100.000 or v_rate <> 16.00 or abs(v_inv_total - 116.000) > 0.01 then
        raise exception 'FAIL caso 1 factura: subtotal=% total=% rate=%', v_inv_subtotal, v_inv_total, v_rate;
    end if;
    raise notice 'OK caso 1: Venezuela 16%% -> base 100.000 + IVA 16.000 = 116.000 (factura coincide)';

    -- Caso 2 (redondeo): 3 x 10.00 = 30.00 -> base 25.862, IVA 4.138, suma exacta 30.000
    v_order := purchase_schema.create_purchase_order(
        (select supplier_id from purchase_schema.supplier where supplier_name = 'IVA Test Supplier VE'),
        (select w.warehouse_id from inventory_schema.warehouse w where w.warehouse_name = 'Bodega VE'),
        current_date + 30,
        jsonb_build_array(jsonb_build_object(
            'product_variant_id', (select product_variant_id from general_schema.product_variant where sku = 'IVA-VE-10')::text,
            'quantity_ordered', 3)),
        true, 'CREDIT', current_date + 30);

    select ap.subtotal, pap.tax_amount
    into v_subtotal, v_tax
    from purchase_schema.purchase_account_payable pap
    join general_schema.account_payable ap on ap.account_payable_id = pap.account_payable_id
    where pap.purchase_order_id = v_order;

    if v_subtotal <> 25.862 or v_tax <> 4.138 or v_subtotal + v_tax <> 30.000 then
        raise exception 'FAIL caso 2: subtotal=% tax=% (esperado 25.862 / 4.138 / suma 30.000)', v_subtotal, v_tax;
    end if;
    raise notice 'OK caso 2: redondeo -> base 25.862 + IVA 4.138 = 30.000';

    -- Caso 3 (cliente, IVA 13%): costo 113.00 con IVA -> total 113.00, no 127.69 ni 26%
    v_order := purchase_schema.create_purchase_order(
        (select supplier_id from purchase_schema.supplier where supplier_name = 'IVA Test Supplier 13'),
        (select w.warehouse_id from inventory_schema.warehouse w where w.warehouse_name = 'Bodega 13'),
        current_date + 30,
        jsonb_build_array(jsonb_build_object(
            'product_variant_id', (select product_variant_id from general_schema.product_variant where sku = 'IVA-13-113')::text,
            'quantity_ordered', 1)),
        true, 'CREDIT', current_date + 30);

    select ap.subtotal, pap.tax_amount
    into v_subtotal, v_tax
    from purchase_schema.purchase_account_payable pap
    join general_schema.account_payable ap on ap.account_payable_id = pap.account_payable_id
    where pap.purchase_order_id = v_order;

    if v_subtotal <> 100.000 or v_tax <> 13.000 then
        raise exception 'FAIL caso 3: subtotal=% tax=% (esperado 100.000 / 13.000)', v_subtotal, v_tax;
    end if;
    raise notice 'OK caso 3: IVA 13%% -> base 100.000 + IVA 13.000 = 113.000 (sin doble IVA)';
END $$;

-- ========================================
-- SECTION 3: Cleanup
-- ========================================
DO $$
DECLARE
    v_tenant_ids uuid[];
    v_payable_ids uuid[];
BEGIN
    select array_agg(tenant_id) into v_tenant_ids
    from general_schema.tenant
    where tenant_name in ('IVA Test VE', 'IVA Test 13');

    select array_agg(pap.account_payable_id) into v_payable_ids
    from purchase_schema.purchase_account_payable pap
    join purchase_schema.purchase_order po on po.purchase_order_id = pap.purchase_order_id
    join purchase_schema.supplier s on s.supplier_id = po.supplier_id
    where s.supplier_name in ('IVA Test Supplier VE', 'IVA Test Supplier 13');

    delete from purchase_schema.purchase_order
    where supplier_id in (
        select supplier_id from purchase_schema.supplier
        where supplier_name in ('IVA Test Supplier VE', 'IVA Test Supplier 13')
    );
    delete from general_schema.account_payable where account_payable_id = any(v_payable_ids);
    delete from general_schema.product_variant where tenant_id = any(v_tenant_ids);
    delete from inventory_schema.warehouse
    where branch_id in (select branch_id from general_schema.branch where tenant_id = any(v_tenant_ids));
    delete from purchase_schema.supplier
    where supplier_name in ('IVA Test Supplier VE', 'IVA Test Supplier 13');
    delete from general_schema.branch where tenant_id = any(v_tenant_ids);
    delete from general_schema.tenant where tenant_id = any(v_tenant_ids);
    delete from general_schema.tax_rate where region = 'IVA Test Region 13';
    delete from general_schema.region where region_name = 'IVA Test Region 13';
END $$;
