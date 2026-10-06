-- =====================================
-- TEST: IVA INCLUIDO AL EDITAR LA FACTURA DEL PROVEEDOR
-- =====================================
-- Purpose: update_supplier_invoice() no debe sumar IVA sobre el costo. Los items
--          de la factura cargan el costo con IVA incluido, pero
--          supplier_invoice.subtotal_amount es la base (tax_amount y
--          total_amount son columnas generadas que suman el IVA encima).
--          Editar la factura con el mismo costo debe dejar los mismos totales
--          que tenia al crearse la orden.
-- Migration: migrations/purchase/043-supplier-invoice-edit-iva-included.sql
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
    where tenant_name = 'Factura Prov IVA Test';

    select array_agg(pap.account_payable_id) into v_payable_ids
    from purchase_schema.purchase_account_payable pap
    join purchase_schema.purchase_order po on po.purchase_order_id = pap.purchase_order_id
    join purchase_schema.supplier s on s.supplier_id = po.supplier_id
    where s.supplier_name = 'Factura Prov IVA Supplier';

    delete from purchase_schema.purchase_order
    where supplier_id in (
        select supplier_id from purchase_schema.supplier
        where supplier_name = 'Factura Prov IVA Supplier'
    );
    delete from general_schema.account_payable where account_payable_id = any(v_payable_ids);
    delete from general_schema.product_variant where tenant_id = any(v_tenant_ids);
    delete from inventory_schema.warehouse
    where branch_id in (select branch_id from general_schema.branch where tenant_id = any(v_tenant_ids));
    delete from purchase_schema.supplier where supplier_name = 'Factura Prov IVA Supplier';
    delete from general_schema.branch where tenant_id = any(v_tenant_ids);
    delete from general_schema.tenant where tenant_id = any(v_tenant_ids);
END $$;

-- ========================================
-- SECTION 1: Setup
-- ========================================
DO $$
DECLARE
    v_ve_region int;
    v_tenant uuid;
    v_branch uuid;
BEGIN
    select region_id into v_ve_region from general_schema.region where region_name = 'Venezuela';

    insert into general_schema.tenant (tenant_name, region_id, identification, contact_email)
    values ('Factura Prov IVA Test', v_ve_region, 'FPI-TEST-VE', 'fpi-ve@test.com')
    returning tenant_id into v_tenant;
    insert into general_schema.branch (tenant_id, branch_name) values (v_tenant, 'Sucursal FPI')
    returning branch_id into v_branch;
    insert into inventory_schema.warehouse (branch_id, warehouse_name, warehouse_address)
    values (v_branch, 'Bodega FPI', 'Direccion');
    insert into purchase_schema.supplier (supplier_name, added_by) values ('Factura Prov IVA Supplier', v_tenant);
    insert into general_schema.product_variant (tenant_id, sku, variant_name, cost_price, unit_price)
    values (v_tenant, 'FPI-58', 'Producto costo 58', 58.00, 100.00);
END $$;

-- ========================================
-- SECTION 2: Asserts
-- ========================================
DO $$
DECLARE
    v_order uuid;
    v_invoice uuid;
    v_variant uuid;
    v_tenant uuid;
    v_subtotal numeric;
    v_tax numeric;
    v_total numeric;
    v_order_total numeric;
BEGIN
    select tenant_id into v_tenant from general_schema.tenant where tenant_name = 'Factura Prov IVA Test';
    select product_variant_id into v_variant from general_schema.product_variant
    where tenant_id = v_tenant and sku = 'FPI-58';

    -- Orden de 2 x 58.00 = 116.00 con IVA (base 100.000 + IVA 16.000)
    v_order := purchase_schema.create_purchase_order(
        (select supplier_id from purchase_schema.supplier where supplier_name = 'Factura Prov IVA Supplier'),
        (select w.warehouse_id from inventory_schema.warehouse w where w.warehouse_name = 'Bodega FPI'),
        current_date + 30,
        jsonb_build_array(jsonb_build_object('product_variant_id', v_variant::text, 'quantity_ordered', 2)),
        true, 'CREDIT', current_date + 30);

    select si.supplier_invoice_id into v_invoice
    from purchase_schema.supplier_invoice si where si.purchase_order_id = v_order;

    -- La edicion de factura solo se permite con la orden enviada (status 2)
    update purchase_schema.purchase_order set purchase_order_status_id = 2 where purchase_order_id = v_order;

    -- Caso 1: editar con el mismo costo y cantidad no cambia los totales
    perform purchase_schema.update_supplier_invoice(
        v_invoice,
        jsonb_build_array(jsonb_build_object(
            'product_variant_id', v_variant::text, 'quantity_billed', 2, 'unit_price', 58.00)),
        v_tenant);

    select subtotal_amount, tax_amount, total_amount into v_subtotal, v_tax, v_total
    from purchase_schema.supplier_invoice where supplier_invoice_id = v_invoice;

    if v_subtotal <> 100.000 or v_tax <> 16.000 or v_total <> 116.000 then
        raise exception 'FAIL caso 1: subtotal=% tax=% total=% (esperado 100.000 / 16.000 / 116.000)',
            v_subtotal, v_tax, v_total;
    end if;
    raise notice 'OK caso 1: factura editada 2 x 58.00 -> base 100.000 + IVA 16.000 = 116.000 (sin IVA doble)';

    -- Caso 2: la factura editada coincide con la orden (lo compara el three-way matching)
    select ap.subtotal + pap.tax_amount into v_order_total
    from purchase_schema.purchase_account_payable pap
    join general_schema.account_payable ap on ap.account_payable_id = pap.account_payable_id
    where pap.purchase_order_id = v_order;

    if abs(v_order_total - v_total) > 0.01 then
        raise exception 'FAIL caso 2: orden=% factura=% (deben coincidir)', v_order_total, v_total;
    end if;
    raise notice 'OK caso 2: total de la factura editada = total de la orden (%)', v_order_total;

    -- Caso 3: la factura se edita a otra cantidad: 3 x 58.00 = 174.00 -> base 150.000, IVA 24.000
    perform purchase_schema.update_supplier_invoice(
        v_invoice,
        jsonb_build_array(jsonb_build_object(
            'product_variant_id', v_variant::text, 'quantity_billed', 3, 'unit_price', 58.00)),
        v_tenant);

    select subtotal_amount, tax_amount, total_amount into v_subtotal, v_tax, v_total
    from purchase_schema.supplier_invoice where supplier_invoice_id = v_invoice;

    if v_subtotal <> 150.000 or v_tax <> 24.000 or v_total <> 174.000 then
        raise exception 'FAIL caso 3: subtotal=% tax=% total=% (esperado 150.000 / 24.000 / 174.000)',
            v_subtotal, v_tax, v_total;
    end if;
    raise notice 'OK caso 3: factura editada 3 x 58.00 -> base 150.000 + IVA 24.000 = 174.000';
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
    where tenant_name = 'Factura Prov IVA Test';

    select array_agg(pap.account_payable_id) into v_payable_ids
    from purchase_schema.purchase_account_payable pap
    join purchase_schema.purchase_order po on po.purchase_order_id = pap.purchase_order_id
    join purchase_schema.supplier s on s.supplier_id = po.supplier_id
    where s.supplier_name = 'Factura Prov IVA Supplier';

    delete from purchase_schema.purchase_order
    where supplier_id in (
        select supplier_id from purchase_schema.supplier
        where supplier_name = 'Factura Prov IVA Supplier'
    );
    delete from general_schema.account_payable where account_payable_id = any(v_payable_ids);
    delete from general_schema.product_variant where tenant_id = any(v_tenant_ids);
    delete from inventory_schema.warehouse
    where branch_id in (select branch_id from general_schema.branch where tenant_id = any(v_tenant_ids));
    delete from purchase_schema.supplier where supplier_name = 'Factura Prov IVA Supplier';
    delete from general_schema.branch where tenant_id = any(v_tenant_ids);
    delete from general_schema.tenant where tenant_id = any(v_tenant_ids);

    raise notice 'SECTION 3: cleanup completed';
END $$;
