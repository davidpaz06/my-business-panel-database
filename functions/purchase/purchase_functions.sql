SET SEARCH_PATH = purchase_schema;

CREATE OR REPLACE FUNCTION calculate_purchase_order_total(
    p_purchase_order_id uuid
) returns numeric as $$
declare
    v_total numeric(12,3);
BEGIN
    select coalesce(sum(quantity_ordered * unit_price), 0)
    into v_total
    from purchase_schema.purchase_order_item
    where purchase_order_id = p_purchase_order_id;

    return round(v_total::numeric, 3);
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION create_purchase_order(
    p_supplier_id uuid,
    p_warehouse_id uuid,
    p_expected_delivery_date date,
    p_items jsonb default '[]'::jsonb,
    p_has_invoice BOOLEAN default true,
    p_payment_condition VARCHAR(10) default 'CREDIT'
) returns uuid as $$
declare
    v_purchase_order_id uuid;
    v_supplier_invoice_id uuid;
    v_item jsonb;
    v_tenant_id uuid;
    v_product_id uuid;
    v_qty INTEGER;
    v_unit numeric(12,3);
    v_subtotal numeric(12,3);
    v_tax_rate numeric(5,2);
    v_tax_amount numeric(12,3);
    v_account_payable_id uuid;
    v_account_payable_type_id int;
    v_due_date date;
BEGIN
    -- Obtener tenant_id desde la relación supplier -> supplier_branch -> branch
    select b.tenant_id into v_tenant_id
    from purchase_schema.supplier s
    join purchase_schema.supplier_branch sb on s.supplier_id = sb.supplier_id
    join general_schema.branch b on b.branch_id = sb.branch_id
    where s.supplier_id = p_supplier_id
    limit 1;

    if v_tenant_id is null then
        raise exception 'Cannot determine tenant_id for supplier %', p_supplier_id;
    end if;

    -- Crear la orden de compra
    INSERT INTO purchase_schema.purchase_order(
        supplier_id,
        warehouse_id,
        expected_delivery_date,
        purchase_order_status_id
    ) VALUES (
        p_supplier_id,
        p_warehouse_id,
        p_expected_delivery_date,
        1  -- Pending
    ) returning purchase_order_id into v_purchase_order_id;

    -- Insertar items si se proporcionaron
    if p_items is not null and jsonb_typeof(p_items) = 'array' and jsonb_array_length(p_items) > 0 then
        for v_item in select value from jsonb_array_elements(p_items)
        loop
            v_product_id := (v_item ->> 'product_variant_id')::uuid;
            v_qty := coalesce((v_item ->> 'quantity_ordered')::int, 0);
            v_unit := coalesce((v_item ->> 'unit_price')::numeric, 0);

            INSERT INTO purchase_schema.purchase_order_item(
                purchase_order_id,
                tenant_id,
                product_variant_id,
                quantity_ordered,
                unit_price
            ) VALUES (
                v_purchase_order_id,
                v_tenant_id,
                v_product_id,
                v_qty,
                v_unit
            );
        end loop;
    end if;

    -- Calcular subtotal de la orden
    v_subtotal := coalesce(purchase_schema.calculate_purchase_order_total(v_purchase_order_id), 0);

    -- Obtener tasa de impuesto del tenant
    select coalesce(tr.rate_percentage, 13.00) into v_tax_rate
    from general_schema.tenant t
    left join general_schema.tax_rate tr on tr.region_id = t.region_id
    where t.tenant_id = v_tenant_id
    limit 1;

    -- Calcular impuesto
    v_tax_amount := round(v_subtotal * (v_tax_rate / 100.0), 3);

    -- Calcular fecha de vencimiento (30 días por defecto)
    v_due_date := (current_date + interval '30 days')::date;

    -- Obtener el ID del tipo de cuenta por pagar 'goods_purchase'
    select account_payable_type_id into v_account_payable_type_id
    from general_schema.account_payable_type
    where type_name = 'goods_purchase'
    limit 1;

    if v_account_payable_type_id is null then
        raise exception 'Account payable type "goods_purchase" not found';
    end if;

    -- ✅ PASO 1: Crear registro en la tabla PADRE (general_schema.account_payable)
    INSERT INTO general_schema.account_payable(
        account_payable_type_id,
        has_invoice,
        has_tax,
        subtotal,
        amount_paid,
        is_paid,
        due_date
    ) VALUES (
        v_account_payable_type_id,
        p_has_invoice,
        true,  -- Las órdenes de suministro siempre tienen impuesto
        v_subtotal,
        0,  -- Inicial
        false,  -- Inicial
        v_due_date
    ) returning account_payable_id into v_account_payable_id;

    -- ✅ PASO 2: Crear registro en la tabla HIJA (purchase_account_payable)
    INSERT INTO purchase_schema.purchase_account_payable(
        account_payable_id,
        purchase_order_id,
        tax_amount,
        account_payable_status
    ) VALUES (
        v_account_payable_id,
        v_purchase_order_id,
        v_tax_amount,
        1  -- Pending
    );

    -- Crear factura si se requiere
    if p_has_invoice then
        INSERT INTO purchase_schema.supplier_invoice(
            purchase_order_id,
            invoice_number,
            invoice_date,
            payment_condition,
            due_date,
            subtotal_amount,
            tax_rate
        ) VALUES (
            v_purchase_order_id,
            'INV-' || to_char(current_timestamp, 'YYYYMMDD-HH24MISS') || '-' || substring(v_purchase_order_id::text, 1, 8),
            current_timestamp,
            p_payment_condition,
            v_due_date,
            v_subtotal,
            v_tax_rate
        ) returning supplier_invoice_id into v_supplier_invoice_id;

        -- Crear items de factura desde los items de la orden
        INSERT INTO purchase_schema.supplier_invoice_item(
            supplier_invoice_id,
            tenant_id,
            product_variant_id,
            quantity_billed,
            unit_price
        )
        select 
            v_supplier_invoice_id,
            tenant_id,
            product_variant_id,
            quantity_ordered,
            unit_price
        from purchase_schema.purchase_order_item
        where purchase_order_id = v_purchase_order_id;
    end if;

    return v_purchase_order_id;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION update_order_status()
returns trigger as $$
BEGIN
    INSERT INTO purchase_schema.purchase_order_tracking(
        purchase_order_id,
        previous_status_id,
        new_status_id,
        notes,
        changed_at
    ) VALUES (
        new.purchase_order_id,
        old.purchase_order_status_id,
        new.purchase_order_status_id,
        'Status updated via trigger',
        current_timestamp
    );

    return new;
end;
$$ language plpgsql;

drop trigger if exists on_order_status_update on purchase_schema.purchase_order;
create trigger on_order_status_update
after update of purchase_order_status_id on purchase_schema.purchase_order
for each row execute function update_order_status();

DROP FUNCTION IF EXISTS check_account_payable_completion(UUID);

CREATE OR REPLACE FUNCTION check_account_payable_completion(
    _account_payable_id UUID
) RETURNS BOOLEAN AS $$
DECLARE
    _subtotal NUMERIC(12,3);
    _tax_amount NUMERIC(12,3);
    _amount_due NUMERIC(12,3);
    _current_amount_paid NUMERIC(12,3);
    _payments_total NUMERIC(12,3);
    _balance NUMERIC(12,3);
    _target_purchase_ap_id UUID;
BEGIN
    SELECT 
        ap.subtotal,
        sap.tax_amount,
        (ap.subtotal + COALESCE(sap.tax_amount, 0)) AS amount_due,
        ap.amount_paid,
        sap.purchase_account_payable_id
    INTO 
        _subtotal,
        _tax_amount,
        _amount_due,
        _current_amount_paid,
        _target_purchase_ap_id
    FROM general_schema.account_payable ap
    JOIN purchase_schema.purchase_account_payable sap 
        ON ap.account_payable_id = sap.account_payable_id
    WHERE ap.account_payable_id = _account_payable_id;

    IF _amount_due IS NULL THEN
        RAISE EXCEPTION 'Account payable not found: %', _account_payable_id;
    END IF;

    SELECT COALESCE(SUM(sop.amount_paid), 0) INTO _payments_total
    FROM purchase_schema.purchase_order_payment sop
    WHERE sop.purchase_account_payable_id = _target_purchase_ap_id;

    _balance := _amount_due - _payments_total;

    UPDATE general_schema.account_payable
    SET amount_paid = _payments_total,
        updated_at = CURRENT_TIMESTAMP
    WHERE account_payable_id = _account_payable_id;

    IF ABS(_balance) <= 0.01 OR _payments_total >= _amount_due THEN
        UPDATE general_schema.account_payable
        SET is_paid = TRUE,
            updated_at = CURRENT_TIMESTAMP
        WHERE account_payable_id = _account_payable_id;

        UPDATE purchase_schema.purchase_account_payable
        SET account_payable_status = 3,
            updated_at = CURRENT_TIMESTAMP
        WHERE account_payable_id = _account_payable_id;

        RETURN TRUE;

    ELSIF _payments_total > 0 THEN
        UPDATE purchase_schema.purchase_account_payable
        SET account_payable_status = 2,
            updated_at = CURRENT_TIMESTAMP
        WHERE account_payable_id = _account_payable_id;

        RETURN FALSE;

    ELSE
        RETURN FALSE;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION recalc_account_payable_on_payment()
returns trigger as $$
BEGIN
    perform purchase_schema.check_account_payable_completion(
        (select account_payable_id 
         from purchase_schema.purchase_account_payable 
         where purchase_account_payable_id = new.purchase_account_payable_id)
    );
    return new;
end;
$$ language plpgsql;

drop trigger if exists recalc_account_payable_on_payment_trigger on purchase_schema.purchase_order_payment;
create trigger recalc_account_payable_on_payment_trigger
    after insert or update of amount_paid on purchase_schema.purchase_order_payment
    for each row
    execute function recalc_account_payable_on_payment();

CREATE OR REPLACE FUNCTION update_invoice_paid_status()
returns trigger as $$
declare
    v_is_paid BOOLEAN;
BEGIN
    if new.account_payable_status = 3 and old.account_payable_status is distinct from 3 then
        select is_paid into v_is_paid
        from general_schema.account_payable
        where account_payable_id = new.account_payable_id;
        
        if v_is_paid = true then
            update purchase_schema.supplier_invoice
            set paid = true,
                updated_at = current_timestamp
            where purchase_order_id = new.purchase_order_id;
        end if;
    end if;
    
    return new;
end;
$$ language plpgsql;

drop trigger if exists update_invoice_paid_status_trigger on purchase_schema.purchase_account_payable;
create trigger update_invoice_paid_status_trigger
    after update of account_payable_status on purchase_schema.purchase_account_payable
    for each row
    execute function purchase_schema.update_invoice_paid_status();

CREATE OR REPLACE FUNCTION create_goods_receipt()
returns trigger as $$
declare
    v_goods_receipt_id uuid;
    v_subtotal numeric(12,3);
    v_tax_amount numeric(12,3);
    v_item record;
BEGIN
    if new.purchase_order_status_id = 3 and old.purchase_order_status_id is distinct from 3 then
        if exists(
            select 1 
            from purchase_schema.goods_receipt 
            where purchase_order_id = new.purchase_order_id
        ) then
            return new;
        end if;

        select 
            ap.subtotal,
            sap.tax_amount
        into v_subtotal, v_tax_amount
        from general_schema.account_payable ap
        join purchase_schema.purchase_account_payable sap 
            on ap.account_payable_id = sap.account_payable_id
        where sap.purchase_order_id = new.purchase_order_id;

        INSERT INTO purchase_schema.goods_receipt(
            purchase_order_id,
            received_date,
            subtotal_amount,
            tax_amount
        ) VALUES (
            new.purchase_order_id,
            current_timestamp,
            v_subtotal,
            v_tax_amount
        ) returning goods_receipt_id into v_goods_receipt_id;

        for v_item in 
            select tenant_id, product_variant_id, quantity_ordered
            from purchase_schema.purchase_order_item
            where purchase_order_id = new.purchase_order_id
        loop
            INSERT INTO purchase_schema.goods_receipt_item(
                goods_receipt_id,
                tenant_id,
                product_variant_id,
                quantity_received
            ) VALUES (
                v_goods_receipt_id,
                v_item.tenant_id,
                v_item.product_variant_id,
                v_item.quantity_ordered
            );
        end loop;

        perform purchase_schema.execute_three_way_matching(new.purchase_order_id, v_goods_receipt_id);
    end if;

    return new;
end;
$$ language plpgsql;

drop trigger if exists create_goods_receipt_trigger on purchase_schema.purchase_order;
create trigger create_goods_receipt_trigger
    after update of purchase_order_status_id on purchase_schema.purchase_order
    for each row
    execute function purchase_schema.create_goods_receipt();

CREATE OR REPLACE FUNCTION execute_three_way_matching(
    p_purchase_order_id uuid,
    p_goods_receipt_id uuid
) returns void as $$
declare
    v_supplier_invoice_id uuid;
    v_order_subtotal numeric(12,3);
    v_order_tax numeric(12,3);
    v_order_total numeric(12,3);
    v_invoice_subtotal numeric(12,3);
    v_invoice_tax numeric(12,3);
    v_invoice_total numeric(12,3);
    v_receipt_subtotal numeric(12,3);
    v_receipt_tax numeric(12,3);
    v_receipt_total numeric(12,3);
    v_order_qty INTEGER;
    v_invoice_qty INTEGER;
    v_receipt_qty INTEGER;
    v_amounts_matched BOOLEAN;
    v_quantities_matched BOOLEAN;
BEGIN
    select supplier_invoice_id into v_supplier_invoice_id
    from purchase_schema.supplier_invoice
    where purchase_order_id = p_purchase_order_id;

    if v_supplier_invoice_id is null then
        return;
    end if;

    if exists(
        select 1 
        from purchase_schema.three_way_matching 
        where purchase_order_id = p_purchase_order_id
    ) then
        return;
    end if;

    select 
        ap.subtotal,
        sap.tax_amount,
        (ap.subtotal + sap.tax_amount) AS total_amount
    into 
        v_order_subtotal,
        v_order_tax,
        v_order_total
    from general_schema.account_payable ap
    join purchase_schema.purchase_account_payable sap 
        on ap.account_payable_id = sap.account_payable_id
    where sap.purchase_order_id = p_purchase_order_id;

    select 
        subtotal_amount,
        tax_amount,
        total_amount
    into 
        v_invoice_subtotal,
        v_invoice_tax,
        v_invoice_total
    from purchase_schema.supplier_invoice
    where supplier_invoice_id = v_supplier_invoice_id;

    select 
        subtotal_amount,
        tax_amount,
        total_amount
    into 
        v_receipt_subtotal,
        v_receipt_tax,
        v_receipt_total
    from purchase_schema.goods_receipt
    where goods_receipt_id = p_goods_receipt_id;

    select coalesce(sum(quantity_ordered), 0) into v_order_qty
    from purchase_schema.purchase_order_item
    where purchase_order_id = p_purchase_order_id;

    select coalesce(sum(quantity_billed), 0) into v_invoice_qty
    from purchase_schema.supplier_invoice_item
    where supplier_invoice_id = v_supplier_invoice_id;

    select coalesce(sum(quantity_received), 0) into v_receipt_qty
    from purchase_schema.goods_receipt_item
    where goods_receipt_id = p_goods_receipt_id;

    v_amounts_matched := (abs(v_order_subtotal - v_invoice_subtotal) <= 0.01) and 
                         (abs(v_order_subtotal - v_receipt_subtotal) <= 0.01) and
                         (abs(v_invoice_subtotal - v_receipt_subtotal) <= 0.01) and
                         (abs(v_order_tax - v_invoice_tax) <= 0.01) and
                         (abs(v_order_tax - v_receipt_tax) <= 0.01) and
                         (abs(v_invoice_tax - v_receipt_tax) <= 0.01) and
                         (abs(v_order_total - v_invoice_total) <= 0.01) and
                         (abs(v_order_total - v_receipt_total) <= 0.01) and
                         (abs(v_invoice_total - v_receipt_total) <= 0.01);
    
    v_quantities_matched := (v_order_qty = v_invoice_qty) and 
                            (v_order_qty = v_receipt_qty);

    INSERT INTO purchase_schema.three_way_matching(
        purchase_order_id,
        goods_receipt_id,
        supplier_invoice_id,
        amounts_matched,
        quantities_matched,
        is_matched,
        matched_at
    ) VALUES (
        p_purchase_order_id,
        p_goods_receipt_id,
        v_supplier_invoice_id,
        v_amounts_matched,
        v_quantities_matched,
        v_amounts_matched and v_quantities_matched,
        current_timestamp
    );
    
exception
    when others then
        raise exception 'Error executing three-way matching: %', sqlerrm;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION generate_payment_alerts()
returns void as $$
declare
    v_config record;
    v_account record;
    v_days_until_due INTEGER;
    v_alert_type_id INTEGER;
    v_existing_alert_id uuid;
BEGIN
    for v_config in 
        select 
            pac.tenant_id,
            pac.warning_days_before_due,
            pac.urgent_days_before_due
        from purchase_schema.purchase_order_payment_alert_config pac
    loop
        for v_account in
            select 
                ap.account_payable_id,
                ap.due_date,
                ap.is_paid,
                ap.amount_paid,
                ap.subtotal,
                sap.purchase_account_payable_id,
                sap.tax_amount,
                (ap.subtotal + coalesce(sap.tax_amount, 0) - ap.amount_paid) as balance_remaining,
                so.purchase_order_id
            from general_schema.account_payable ap
            join purchase_schema.purchase_account_payable sap 
                on ap.account_payable_id = sap.account_payable_id
            join purchase_schema.purchase_order so 
                on sap.purchase_order_id = so.purchase_order_id
            join purchase_schema.supplier s 
                on so.supplier_id = s.supplier_id
            join purchase_schema.supplier_branch sb 
                on s.supplier_id = sb.supplier_id
            join general_schema.branch b 
                on sb.branch_id = b.branch_id
            where b.tenant_id = v_config.tenant_id
            and ap.is_paid = false
            and (ap.subtotal + coalesce(sap.tax_amount, 0) - ap.amount_paid) > 0
        loop
            v_days_until_due := v_account.due_date - current_date;
            
  
            if v_days_until_due < 0 then
                v_alert_type_id := 3; 
            elsif v_days_until_due <= v_config.urgent_days_before_due then
                v_alert_type_id := 2; 
            elsif v_days_until_due <= v_config.warning_days_before_due then
                v_alert_type_id := 1; 
            else
                continue; 
            end if;
            
            select payment_alert_id into v_existing_alert_id
            from purchase_schema.purchase_order_payment_alert
            where purchase_account_payable_id = v_account.purchase_account_payable_id
            and payment_alert_type_id = v_alert_type_id
            and is_resolved = false
            limit 1;
            
            if v_existing_alert_id is null then
                INSERT INTO purchase_schema.purchase_order_payment_alert(
                    purchase_account_payable_id,
                    payment_alert_type_id,
                    alert_date,
                    is_resolved
                ) VALUES (
                    v_account.purchase_account_payable_id,
                    v_alert_type_id,
                    current_timestamp,
                    false
                );
            end if;
        end loop;
    end loop;
    
exception
    when others then
        raise exception 'Error generating payment alerts: %', sqlerrm;
end;
$$ language plpgsql;

drop function if exists get_pending_payment_alerts(uuid);

CREATE OR REPLACE FUNCTION get_pending_payment_alerts(p_tenant_id uuid)
returns table(
    payment_alert_id uuid,
    purchase_account_payable_id uuid,
    purchase_order_id uuid,
    supplier_name VARCHAR,
    invoice_number VARCHAR,
    alert_type VARCHAR,
    alert_type_description text,
    due_date date,
    days_until_due INTEGER,
    balance_remaining numeric,
    alert_date timestamp,
    created_at timestamp
) as $$
BEGIN
    return query
    select 
        spa.payment_alert_id,
        sap.purchase_account_payable_id,
        so.purchase_order_id,
        s.supplier_name,
        si.invoice_number,
        spat.payment_alert_type_name,
        spat.description,
        ap.due_date,
        (ap.due_date - current_date)::INTEGER as days_until_due,
        (ap.subtotal + coalesce(sap.tax_amount, 0) - ap.amount_paid) as balance_remaining,
        spa.alert_date,
        spa.created_at
    from purchase_schema.purchase_order_payment_alert spa
    join purchase_schema.purchase_order_payment_alert_type spat 
        on spa.payment_alert_type_id = spat.payment_alert_type_id
    join purchase_schema.purchase_account_payable sap 
        on spa.purchase_account_payable_id = sap.purchase_account_payable_id
    join general_schema.account_payable ap 
        on sap.account_payable_id = ap.account_payable_id
    join purchase_schema.purchase_order so 
        on sap.purchase_order_id = so.purchase_order_id
    join purchase_schema.supplier s 
        on so.supplier_id = s.supplier_id
    left join purchase_schema.supplier_invoice si 
        on so.purchase_order_id = si.purchase_order_id
    join purchase_schema.supplier_branch sb 
        on s.supplier_id = sb.supplier_id
    join general_schema.branch b 
        on sb.branch_id = b.branch_id
    where b.tenant_id = p_tenant_id
    and spa.is_resolved = false
    order by ap.due_date asc, spa.alert_date desc;
    
exception
    when others then
        raise exception 'Error fetching pending payment alerts: %', sqlerrm;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION resolve_payment_alert(p_alert_id uuid)
returns void as $$
BEGIN
    update purchase_schema.purchase_order_payment_alert
    set is_resolved = true,
        updated_at = current_timestamp
    where payment_alert_id = p_alert_id;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION auto_resolve_payment_alerts()
returns trigger as $$
declare
    v_is_paid BOOLEAN;
BEGIN
    if new.account_payable_status = 3 and old.account_payable_status is distinct from 3 then
        select is_paid into v_is_paid
        from general_schema.account_payable
        where account_payable_id = new.account_payable_id;
        
        if v_is_paid = true then
            update purchase_schema.purchase_order_payment_alert
            set is_resolved = true,
                updated_at = current_timestamp
            where purchase_account_payable_id = new.purchase_account_payable_id
            and is_resolved = false;
        end if;
    end if;
    
    return new;
end;
$$ language plpgsql;

drop trigger if exists auto_resolve_payment_alerts_trigger on purchase_schema.purchase_account_payable;
create trigger auto_resolve_payment_alerts_trigger
    after update of account_payable_status on purchase_schema.purchase_account_payable
    for each row
    execute function purchase_schema.auto_resolve_payment_alerts();

CREATE OR REPLACE FUNCTION initialize_payment_alert_config(
    p_tenant_id uuid,
    p_warning_days INTEGER default 7,
    p_urgent_days INTEGER default 3,
    p_email_enabled BOOLEAN default true,
    p_sms_enabled BOOLEAN default false
) returns uuid as $$
declare
    v_config_id uuid;
BEGIN
    INSERT INTO purchase_schema.purchase_order_payment_alert_config(
        tenant_id,
        warning_days_before_due,
        urgent_days_before_due,
        email_notifications_enabled,
        sms_notifications_enabled
    ) VALUES (
        p_tenant_id,
        p_warning_days,
        p_urgent_days,
        p_email_enabled,
        p_sms_enabled
    )
    on conflict (tenant_id) DO update
    set warning_days_before_due = excluded.warning_days_before_due,
        urgent_days_before_due = excluded.urgent_days_before_due,
        email_notifications_enabled = excluded.email_notifications_enabled,
        sms_notifications_enabled = excluded.sms_notifications_enabled,
        updated_at = current_timestamp
    returning payment_alert_config_id into v_config_id;
    
    return v_config_id;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION get_payment_alert_stats(p_tenant_id uuid)
returns table(
    total_alerts INTEGER,
    overdue_count INTEGER,
    urgent_count INTEGER,
    warning_count INTEGER,
    total_amount_at_risk numeric
) as $$
BEGIN
    return query
    select 
        count(*)::INTEGER as total_alerts,
        count(*) filter (where spat.payment_alert_type_id = 3)::INTEGER as overdue_count,
        count(*) filter (where spat.payment_alert_type_id = 2)::INTEGER as urgent_count,
        count(*) filter (where spat.payment_alert_type_id = 1)::INTEGER as warning_count,
        coalesce(sum(ap.subtotal + coalesce(sap.tax_amount, 0) - ap.amount_paid), 0) as total_amount_at_risk
    from purchase_schema.purchase_order_payment_alert spa
    join purchase_schema.purchase_order_payment_alert_type spat 
        on spa.payment_alert_type_id = spat.payment_alert_type_id
    join purchase_schema.purchase_account_payable sap 
        on spa.purchase_account_payable_id = sap.purchase_account_payable_id
    join general_schema.account_payable ap 
        on sap.account_payable_id = ap.account_payable_id
    join purchase_schema.purchase_order so 
        on sap.purchase_order_id = so.purchase_order_id
    join purchase_schema.supplier s 
        on so.supplier_id = s.supplier_id
    join purchase_schema.supplier_branch sb 
        on s.supplier_id = sb.supplier_id
    join general_schema.branch b 
        on sb.branch_id = b.branch_id
    where b.tenant_id = p_tenant_id
    and spa.is_resolved = false;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error calculating payment alert stats: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;


drop trigger if exists update_supplier_timestamp on purchase_schema.supplier;
create trigger update_supplier_timestamp before update on purchase_schema.supplier
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_purchase_order_timestamp on purchase_schema.purchase_order;
create trigger update_purchase_order_timestamp before update on purchase_schema.purchase_order
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_purchase_order_item_timestamp on purchase_schema.purchase_order_item;
create trigger update_purchase_order_item_timestamp before update on purchase_schema.purchase_order_item
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_supplier_invoice_timestamp on purchase_schema.supplier_invoice;
create trigger update_supplier_invoice_timestamp before update on purchase_schema.supplier_invoice
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_supplier_invoice_item_timestamp on purchase_schema.supplier_invoice_item;
create trigger update_supplier_invoice_item_timestamp before update on purchase_schema.supplier_invoice_item
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_goods_receipt_timestamp on purchase_schema.goods_receipt;
create trigger update_goods_receipt_timestamp before update on purchase_schema.goods_receipt
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_goods_receipt_item_timestamp on purchase_schema.goods_receipt_item;
create trigger update_goods_receipt_item_timestamp before update on purchase_schema.goods_receipt_item
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_account_payable_timestamp on purchase_schema.purchase_account_payable;
create trigger update_account_payable_timestamp before update on purchase_schema.purchase_account_payable
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_purchase_order_payment_timestamp on purchase_schema.purchase_order_payment;
create trigger update_purchase_order_payment_timestamp before update on purchase_schema.purchase_order_payment
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_purchase_order_payment_alert_timestamp on purchase_schema.purchase_order_payment_alert;
create trigger update_purchase_order_payment_alert_timestamp before update on purchase_schema.purchase_order_payment_alert
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_purchase_order_payment_alert_config_timestamp on purchase_schema.purchase_order_payment_alert_config;
create trigger update_purchase_order_payment_alert_config_timestamp before update on purchase_schema.purchase_order_payment_alert_config
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_three_way_matching_timestamp on purchase_schema.three_way_matching;
create trigger update_three_way_matching_timestamp before update on purchase_schema.three_way_matching
for each row execute function general_schema.update_timestamp();