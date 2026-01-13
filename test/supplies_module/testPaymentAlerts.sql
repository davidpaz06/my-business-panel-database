-- =====================================
-- TEST: PAYMENT ALERTS SYSTEM
-- =====================================
-- Purpose: Test the payment alert generation and management system
-- =====================================

set search_path = supplies_module, core;

-- ========================================
-- SECTION 0: Cleanup
-- ========================================
do $$
begin
    delete from supplies_module.supply_order_payment_alert 
    where supplies_account_payable_id in (
        select sap.supplies_account_payable_id
        from supplies_module.supplies_account_payable sap
        join supplies_module.supply_order so on sap.supply_order_id = so.supply_order_id
        join supplies_module.supplier s on so.supplier_id = s.supplier_id
        where s.supplier_name = 'Alert Test Supplier'
    );
    
    delete from supplies_module.supply_order_payment 
    where supplies_account_payable_id in (
        select sap.supplies_account_payable_id
        from supplies_module.supplies_account_payable sap
        join supplies_module.supply_order so on sap.supply_order_id = so.supply_order_id
        join supplies_module.supplier s on so.supplier_id = s.supplier_id
        where s.supplier_name = 'Alert Test Supplier'
    );
    
    delete from supplies_module.supply_order 
    where supplier_id in (
        select supplier_id from supplies_module.supplier 
        where supplier_name = 'Alert Test Supplier'
    );
    
    delete from supplies_module.supplier_branch 
    where supplier_id in (
        select supplier_id from supplies_module.supplier 
        where supplier_name = 'Alert Test Supplier'
    );
    
    delete from supplies_module.supplier 
    where supplier_name = 'Alert Test Supplier';
    
    delete from core.product 
    where tenant_id in (
        select tenant_id from core.tenant 
        where tenant_name = 'Alert Test Business'
    );
    
    delete from inventory_module.warehouse 
    where branch_id in (
        select branch_id from core.branch 
        where tenant_id in (
            select tenant_id from core.tenant 
            where tenant_name = 'Alert Test Business'
        )
    );
    
    delete from core.branch 
    where tenant_id in (
        select tenant_id from core.tenant 
        where tenant_name = 'Alert Test Business'
    );
    
    delete from supplies_module.supply_order_payment_alert_config 
    where tenant_id in (
        select tenant_id from core.tenant 
        where tenant_name = 'Alert Test Business'
    );
    
    delete from core.tenant 
    where tenant_name = 'Alert Test Business';
end $$;

-- ========================================
-- SECTION 1: Setup test data
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_branch_id uuid;
    v_warehouse_id uuid;
    v_supplier_id uuid;
    v_product_id uuid;
    v_config_id uuid;
begin
    raise notice '========================================';
    raise notice '🔧 SETUP: Creating test data';
    raise notice '========================================';

    -- Create tenant
    insert into core.tenant(tenant_name, region_id, contact_email)
    values ('Alert Test Business', 1, 'test@alerts.com')
    returning tenant_id into v_tenant_id;

    -- Create branch
    insert into core.branch(tenant_id, branch_name, contact_email)
    values (v_tenant_id, 'Main Branch', 'branch@alerts.com')
    returning branch_id into v_branch_id;

    -- Create warehouse
    insert into inventory_module.warehouse(branch_id, warehouse_name, warehouse_address)
    values (v_branch_id, 'Main Warehouse', 'Main Warehouse Address')
    returning warehouse_id into v_warehouse_id;

    -- Create supplier
    insert into supplies_module.supplier(supplier_name)
    values ('Alert Test Supplier')
    returning supplier_id into v_supplier_id;

    insert into supplies_module.supplier_branch(supplier_id, branch_id)
    values (v_supplier_id, v_branch_id);

    -- Create product
    insert into core.product(tenant_id, product_name, sku, unit_price)
    values (v_tenant_id, 'Test Product', 'TEST-ALERT-001', 100.00)
    returning product_id into v_product_id;

    -- Initialize alert configuration (7 days warning, 3 days urgent)
    select supplies_module.initialize_payment_alert_config(
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
do $$
declare
    v_tenant_id uuid;
    v_supplier_id uuid;
    v_warehouse_id uuid;
    v_product_id uuid;
    v_order_overdue uuid;
    v_order_urgent uuid;
    v_order_warning uuid;
    v_order_ok uuid;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '📦 SECTION 2: Creating orders with varying due dates';
    raise notice '========================================';

    select t.tenant_id into v_tenant_id
    from core.tenant t
    where t.tenant_name = 'Alert Test Business';

    select s.supplier_id into v_supplier_id
    from supplies_module.supplier s
    where s.supplier_name = 'Alert Test Supplier';

    select w.warehouse_id into v_warehouse_id
    from inventory_module.warehouse w
    join core.branch b on w.branch_id = b.branch_id
    where b.tenant_id = v_tenant_id
    limit 1;

    select p.product_id into v_product_id
    from core.product p
    where p.tenant_id = v_tenant_id
    and p.sku = 'TEST-ALERT-001'
    limit 1;

    -- Order 1: Overdue (due 5 days ago)
    select supplies_module.create_supply_order(
        v_supplier_id,
        v_warehouse_id,
        (current_date - interval '5 days')::date,
        jsonb_build_array(
            jsonb_build_object('product_id', v_product_id::text, 'quantity_ordered', 10, 'unit_price', 100.00)
        ),
        true,
        'CREDIT'
    ) into v_order_overdue;

    update core.account_payable
    set due_date = current_date - interval '5 days'
    where account_payable_id = (
        select account_payable_id 
        from supplies_module.supplies_account_payable 
        where supply_order_id = v_order_overdue
    );

    -- Order 2: Urgent (due in 2 days)
    select supplies_module.create_supply_order(
        v_supplier_id,
        v_warehouse_id,
        (current_date + interval '2 days')::date,
        jsonb_build_array(
            jsonb_build_object('product_id', v_product_id::text, 'quantity_ordered', 5, 'unit_price', 200.00)
        ),
        true,
        'CREDIT'
    ) into v_order_urgent;

    update core.account_payable
    set due_date = current_date + interval '2 days'
    where account_payable_id = (
        select account_payable_id 
        from supplies_module.supplies_account_payable 
        where supply_order_id = v_order_urgent
    );

    -- Order 3: Warning (due in 5 days)
    select supplies_module.create_supply_order(
        v_supplier_id,
        v_warehouse_id,
        (current_date + interval '5 days')::date,
        jsonb_build_array(
            jsonb_build_object('product_id', v_product_id::text, 'quantity_ordered', 8, 'unit_price', 150.00)
        ),
        true,
        'CREDIT'
    ) into v_order_warning;

    update core.account_payable
    set due_date = current_date + interval '5 days'
    where account_payable_id = (
        select account_payable_id 
        from supplies_module.supplies_account_payable 
        where supply_order_id = v_order_warning
    );

    -- Order 4: OK (due in 15 days - no alert needed)
    select supplies_module.create_supply_order(
        v_supplier_id,
        v_warehouse_id,
        (current_date + interval '15 days')::date,
        jsonb_build_array(
            jsonb_build_object('product_id', v_product_id::text, 'quantity_ordered', 3, 'unit_price', 300.00)
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
do $$
begin
    raise notice '';
    raise notice '========================================';
    raise notice '🔔 SECTION 3: Generating payment alerts';
    raise notice '========================================';

    perform supplies_module.generate_payment_alerts();

    raise notice '✓ Alerts generated';
    raise notice '========================================';
end $$;

-- ========================================
-- SECTION 4: View pending alerts
-- ========================================
do $$
declare
    v_tenant_id uuid;
    v_alert record;
    v_count integer := 0;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '📋 SECTION 4: Pending payment alerts';
    raise notice '========================================';

    select t.tenant_id into v_tenant_id
    from core.tenant t
    where t.tenant_name = 'Alert Test Business';

    for v_alert in 
        select * from supplies_module.get_pending_payment_alerts(v_tenant_id)
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
do $$
declare
    v_tenant_id uuid;
    v_stats record;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '📊 SECTION 5: Alert statistics';
    raise notice '========================================';

    select t.tenant_id into v_tenant_id
    from core.tenant t
    where t.tenant_name = 'Alert Test Business';

    select * into v_stats
    from supplies_module.get_payment_alert_stats(v_tenant_id);

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
do $$
declare
    v_tenant_id uuid;
    v_supplies_account_payable_id uuid;
    v_payment_id uuid;
    v_alerts_before integer;
    v_alerts_after integer;
begin
    raise notice '';
    raise notice '========================================';
    raise notice '💰 SECTION 6: Auto-resolve alerts on payment';
    raise notice '========================================';

    select t.tenant_id into v_tenant_id
    from core.tenant t
    where t.tenant_name = 'Alert Test Business';

    -- Get overdue account
    select sap.supplies_account_payable_id into v_supplies_account_payable_id
    from supplies_module.supplies_account_payable sap
    join core.account_payable ap on sap.account_payable_id = ap.account_payable_id
    join supplies_module.supply_order so on sap.supply_order_id = so.supply_order_id
    join supplies_module.supplier s on so.supplier_id = s.supplier_id
    join supplies_module.supplier_branch sb on s.supplier_id = sb.supplier_id
    join core.branch b on sb.branch_id = b.branch_id
    where b.tenant_id = v_tenant_id
    and ap.due_date < current_date
    limit 1;

    select count(*)::integer into v_alerts_before
    from supplies_module.supply_order_payment_alert
    where supplies_account_payable_id = v_supplies_account_payable_id
    and is_resolved = false;

    raise notice 'Alerts before payment: %', v_alerts_before;

    -- Make full payment
    insert into supplies_module.supply_order_payment(
        tenant_id,
        supplies_account_payable_id,
        amount_paid,
        payment_method_id,
        payment_reference,
        verified
    ) 
    select 
        v_tenant_id,
        v_supplies_account_payable_id,
        (ap.subtotal + coalesce(sap.tax_amount, 0)),
        1,
        'FULL-PAYMENT-TEST',
        false
    from supplies_module.supplies_account_payable sap
    join core.account_payable ap on sap.account_payable_id = ap.account_payable_id
    where sap.supplies_account_payable_id = v_supplies_account_payable_id
    returning payment_id into v_payment_id;

    call supplies_module.verify_supply_order_payment(v_payment_id);

    select count(*)::integer into v_alerts_after
    from supplies_module.supply_order_payment_alert
    where supplies_account_payable_id = v_supplies_account_payable_id
    and is_resolved = false;

    raise notice '✓ Payment made and verified';
    raise notice 'Alerts after payment: %', v_alerts_after;
    raise notice '✓ Alerts auto-resolved: %', (v_alerts_before - v_alerts_after);
    raise notice '========================================';
end $$;