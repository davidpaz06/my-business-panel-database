-- =====================================
-- TEST: PAYMENT ALERTS SYSTEM
-- =====================================
-- Purpose: Test the payment alert generation and management system
-- =====================================

set search_path = purchase_schema, general_schema;

-- ========================================
-- SECTION 0: Cleanup
-- ========================================
DO $$
BEGIN
    delete from purchase_schema.purchase_order_payment_alert 
    where purchase_account_payable_id in (
        select sap.purchase_account_payable_id
        from purchase_schema.purchase_account_payable sap
        join purchase_schema.purchase_order so on sap.purchase_order_id = so.purchase_order_id
        join purchase_schema.supplier s on so.supplier_id = s.supplier_id
        where s.supplier_name = 'Alert Test Supplier'
    );
    
    delete from purchase_schema.purchase_order_payment 
    where purchase_account_payable_id in (
        select sap.purchase_account_payable_id
        from purchase_schema.purchase_account_payable sap
        join purchase_schema.purchase_order so on sap.purchase_order_id = so.purchase_order_id
        join purchase_schema.supplier s on so.supplier_id = s.supplier_id
        where s.supplier_name = 'Alert Test Supplier'
    );
    
    delete from purchase_schema.purchase_order 
    where supplier_id in (
        select supplier_id from purchase_schema.supplier 
        where supplier_name = 'Alert Test Supplier'
    );
    
    delete from purchase_schema.supplier_branch 
    where supplier_id in (
        select supplier_id from purchase_schema.supplier 
        where supplier_name = 'Alert Test Supplier'
    );
    
    delete from purchase_schema.supplier 
    where supplier_name = 'Alert Test Supplier';
    
    delete from general_schema.product_variant 
    where tenant_id in (
        select tenant_id from general_schema.tenant 
        where tenant_name = 'Alert Test Business'
    );
    
    delete from inventory_schema.warehouse 
    where branch_id in (
        select branch_id from general_schema.branch 
        where tenant_id in (
            select tenant_id from general_schema.tenant 
            where tenant_name = 'Alert Test Business'
        )
    );
    
    delete from general_schema.branch 
    where tenant_id in (
        select tenant_id from general_schema.tenant 
        where tenant_name = 'Alert Test Business'
    );
    
    delete from purchase_schema.purchase_order_payment_alert_config 
    where tenant_id in (
        select tenant_id from general_schema.tenant 
        where tenant_name = 'Alert Test Business'
    );
    
    delete from general_schema.tenant 
    where tenant_name = 'Alert Test Business';
end $$;

-- ========================================
-- SECTION 1: Setup test data
-- ========================================
DO $$
declare
    v_tenant_id uuid;
    v_branch_id uuid;
    v_warehouse_id uuid;
    v_supplier_id uuid;
    v_product_id uuid;
    v_config_id uuid;
BEGIN
    raise notice '========================================';
    raise notice '🔧 SETUP: Creating test data';
    raise notice '========================================';

    -- Create tenant
    INSERT INTO general_schema.tenant(tenant_name, region_id, contact_email)
    VALUES ('Alert Test Business', 1, 'test@alerts.com')
    returning tenant_id into v_tenant_id;

    -- Create branch
    INSERT INTO general_schema.branch(tenant_id, branch_name, contact_email)
    VALUES (v_tenant_id, 'Main Branch', 'branch@alerts.com')
    returning branch_id into v_branch_id;

    -- Create warehouse
    INSERT INTO inventory_schema.warehouse(branch_id, warehouse_name, warehouse_address)
    VALUES (v_branch_id, 'Main Warehouse', 'Main Warehouse Address')
    returning warehouse_id into v_warehouse_id;

    -- Create supplier
    INSERT INTO purchase_schema.supplier(supplier_name)
    VALUES ('Alert Test Supplier')
    returning supplier_id into v_supplier_id;

    INSERT INTO purchase_schema.supplier_branch(supplier_id, branch_id)
    VALUES (v_supplier_id, v_branch_id);

    -- Create CABYS entry
    INSERT INTO general_schema.product(cabys_code, product_name)
    VALUES ('ALERT00000001', 'Producto de prueba alertas')
    ON CONFLICT (cabys_code) DO NOTHING;

    -- Create product variant
    INSERT INTO general_schema.product_variant(tenant_id, sku, variant_name, unit_price, cabys_code)
    VALUES (v_tenant_id, 'TEST-ALERT-001', 'Test Product', 100.00, 'ALERT00000001')
    returning product_variant_id into v_product_id;

    -- Initialize alert configuration (7 days warning, 3 days urgent)
    select purchase_schema.initialize_payment_alert_config(
        v_tenant_id,
        7,  -- warning days
        3,  -- urgent days
        true,
        false
    ) into v_config_id;

    raise notice '✓ Tenant: %', v_tenant_id;
    raise notice '✓ Branch: %', v_branch_id;
    raise notice '✓ Warehouse: %', v_warehouse_id;
    raise notice '✓ Supplier: %', v_supplier_id;
    raise notice '✓ Product: %', v_product_id;
    raise notice '✓ Alert config: %', v_config_id;
    raise notice '✓ Setup completed';
    raise notice '========================================';
end $$;

-- ========================================
-- SECTION 2: Create orders with different due dates
-- ========================================
DO $$
declare
    v_tenant_id uuid;
    v_supplier_id uuid;
    v_warehouse_id uuid;
    v_product_id uuid;
    v_order_overdue uuid;
    v_order_urgent uuid;
    v_order_warning uuid;
    v_order_ok uuid;
BEGIN
    raise notice '';
    raise notice '========================================';
    raise notice '📦 SECTION 2: Creating orders with varying due dates';
    raise notice '========================================';

    select t.tenant_id into v_tenant_id
    from general_schema.tenant t
    where t.tenant_name = 'Alert Test Business';

    select s.supplier_id into v_supplier_id
    from purchase_schema.supplier s
    where s.supplier_name = 'Alert Test Supplier';

    select w.warehouse_id into v_warehouse_id
    from inventory_schema.warehouse w
    join general_schema.branch b on w.branch_id = b.branch_id
    where b.tenant_id = v_tenant_id
    limit 1;

    select pv.product_variant_id into v_product_id
    from general_schema.product_variant pv
    where pv.tenant_id = v_tenant_id
    and pv.sku = 'TEST-ALERT-001'
    limit 1;

    -- Order 1: Overdue (due 5 days ago)
    select purchase_schema.create_purchase_order(
        v_supplier_id,
        v_warehouse_id,
        (current_date - interval '5 days')::date,
        jsonb_build_array(
            jsonb_build_object('product_variant_id', v_product_id::text, 'quantity_ordered', 10, 'unit_price', 100.00)
        ),
        true,
        'CREDIT'
    ) into v_order_overdue;

    update general_schema.account_payable
    set due_date = current_date - interval '5 days'
    where account_payable_id = (
        select account_payable_id 
        from purchase_schema.purchase_account_payable 
        where purchase_order_id = v_order_overdue
    );

    -- Order 2: Urgent (due in 2 days)
    select purchase_schema.create_purchase_order(
        v_supplier_id,
        v_warehouse_id,
        (current_date + interval '2 days')::date,
        jsonb_build_array(
            jsonb_build_object('product_variant_id', v_product_id::text, 'quantity_ordered', 5, 'unit_price', 200.00)
        ),
        true,
        'CREDIT'
    ) into v_order_urgent;

    update general_schema.account_payable
    set due_date = current_date + interval '2 days'
    where account_payable_id = (
        select account_payable_id 
        from purchase_schema.purchase_account_payable 
        where purchase_order_id = v_order_urgent
    );

    -- Order 3: Warning (due in 5 days)
    select purchase_schema.create_purchase_order(
        v_supplier_id,
        v_warehouse_id,
        (current_date + interval '5 days')::date,
        jsonb_build_array(
            jsonb_build_object('product_variant_id', v_product_id::text, 'quantity_ordered', 8, 'unit_price', 150.00)
        ),
        true,
        'CREDIT'
    ) into v_order_warning;

    update general_schema.account_payable
    set due_date = current_date + interval '5 days'
    where account_payable_id = (
        select account_payable_id 
        from purchase_schema.purchase_account_payable 
        where purchase_order_id = v_order_warning
    );

    -- Order 4: OK (due in 15 days - no alert needed)
    select purchase_schema.create_purchase_order(
        v_supplier_id,
        v_warehouse_id,
        (current_date + interval '15 days')::date,
        jsonb_build_array(
            jsonb_build_object('product_variant_id', v_product_id::text, 'quantity_ordered', 3, 'unit_price', 300.00)
        ),
        true,
        'CREDIT'
    ) into v_order_ok;

    raise notice '✓ Overdue order created (due 5 days ago)';
    raise notice '✓ Urgent order created (due in 2 days)';
    raise notice '✓ Warning order created (due in 5 days)';
    raise notice '✓ OK order created (due in 15 days - no alert)';
    raise notice '========================================';
end $$;

-- ========================================
-- SECTION 3: Generate alerts
-- ========================================
DO $$
BEGIN
    raise notice '';
    raise notice '========================================';
    raise notice '🔔 SECTION 3: Generating payment alerts';
    raise notice '========================================';

    perform purchase_schema.generate_payment_alerts();

    raise notice '✓ Alerts generated';
    raise notice '========================================';
end $$;

-- ========================================
-- SECTION 4: View pending alerts
-- ========================================
DO $$
declare
    v_tenant_id uuid;
    v_alert record;
    v_count INTEGER := 0;
BEGIN
    raise notice '';
    raise notice '========================================';
    raise notice '📋 SECTION 4: Pending payment alerts';
    raise notice '========================================';

    select t.tenant_id into v_tenant_id
    from general_schema.tenant t
    where t.tenant_name = 'Alert Test Business';

    for v_alert in 
        select * from purchase_schema.get_pending_payment_alerts(v_tenant_id)
    loop
        v_count := v_count + 1;
        raise notice '';
        raise notice 'Alert #%:', v_count;
        raise notice '  Type: % (%)', v_alert.alert_type, v_alert.alert_type_description;
        raise notice '  Supplier: %', v_alert.supplier_name;
        raise notice '  Invoice: %', v_alert.invoice_number;
        raise notice '  Due date: %', v_alert.due_date;
        raise notice '  Days until due: %', v_alert.days_until_due;
        raise notice '  Balance: $%', v_alert.balance_remaining;
        raise notice '  Alert created: %', v_alert.alert_date;
    end loop;

    raise notice '';
    raise notice '✓ Total alerts: %', v_count;
    raise notice '========================================';
end $$;

-- ========================================
-- SECTION 5: View alert statistics
-- ========================================
DO $$
declare
    v_tenant_id uuid;
    v_stats record;
BEGIN
    raise notice '';
    raise notice '========================================';
    raise notice '📊 SECTION 5: Alert statistics';
    raise notice '========================================';

    select t.tenant_id into v_tenant_id
    from general_schema.tenant t
    where t.tenant_name = 'Alert Test Business';

    select * into v_stats
    from purchase_schema.get_payment_alert_stats(v_tenant_id);

    raise notice 'Total alerts: %', v_stats.total_alerts;
    raise notice 'Overdue payments: %', v_stats.overdue_count;
    raise notice 'Urgent payments: %', v_stats.urgent_count;
    raise notice 'Warning alerts: %', v_stats.warning_count;
    raise notice 'Total amount at risk: $%', v_stats.total_amount_at_risk;
    raise notice '========================================';
end $$;

-- ========================================
-- SECTION 6: Test auto-resolve on payment
-- ========================================
DO $$
declare
    v_tenant_id uuid;
    v_purchase_account_payable_id uuid;
    v_payment_id uuid;
    v_alerts_before INTEGER;
    v_alerts_after INTEGER;
BEGIN
    raise notice '';
    raise notice '========================================';
    raise notice '💰 SECTION 6: Auto-resolve alerts on payment';
    raise notice '========================================';

    select t.tenant_id into v_tenant_id
    from general_schema.tenant t
    where t.tenant_name = 'Alert Test Business';

    -- Get overdue account
    select sap.purchase_account_payable_id into v_purchase_account_payable_id
    from purchase_schema.purchase_account_payable sap
    join general_schema.account_payable ap on sap.account_payable_id = ap.account_payable_id
    join purchase_schema.purchase_order so on sap.purchase_order_id = so.purchase_order_id
    join purchase_schema.supplier s on so.supplier_id = s.supplier_id
    join purchase_schema.supplier_branch sb on s.supplier_id = sb.supplier_id
    join general_schema.branch b on sb.branch_id = b.branch_id
    where b.tenant_id = v_tenant_id
    and ap.due_date < current_date
    limit 1;

    select count(*)::INTEGER into v_alerts_before
    from purchase_schema.purchase_order_payment_alert
    where purchase_account_payable_id = v_purchase_account_payable_id
    and is_resolved = false;

    raise notice 'Alerts before payment: %', v_alerts_before;

    -- Make full payment
    INSERT INTO purchase_schema.purchase_order_payment(
        purchase_account_payable_id,
        amount_paid,
        payment_method_id,
        payment_reference
    ) 
    select 
        v_purchase_account_payable_id,
        (ap.subtotal + coalesce(sap.tax_amount, 0)),
        1,
        'FULL-PAYMENT-TEST'
    from purchase_schema.purchase_account_payable sap
    join general_schema.account_payable ap on sap.account_payable_id = ap.account_payable_id
    where sap.purchase_account_payable_id = v_purchase_account_payable_id
    returning purchase_order_payment_id into v_payment_id;

    select count(*)::INTEGER into v_alerts_after
    from purchase_schema.purchase_order_payment_alert
    where purchase_account_payable_id = v_purchase_account_payable_id
    and is_resolved = false;

    raise notice '✓ Payment made and verified';
    raise notice 'Alerts after payment: %', v_alerts_after;
    raise notice '✓ Alerts auto-resolved: %', (v_alerts_before - v_alerts_after);
    raise notice '========================================';
end $$;

