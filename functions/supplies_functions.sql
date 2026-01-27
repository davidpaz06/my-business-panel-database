create or replace function calculate_supply_order_total(
    p_supply_order_id uuid
) returns numeric as $$
declare
    v_total numeric(12,3);
begin
    select coalesce(sum(quantity_ordered * unit_price), 0)
    into v_total
    from supplies_module.supply_order_item
    where supply_order_id = p_supply_order_id;

    return round(v_total::numeric, 3);
end;
$$ language plpgsql;

create or replace function create_supply_order(
    p_supplier_id uuid,
    p_warehouse_id uuid,
    p_expected_delivery_date date,
    p_items jsonb default '[]'::jsonb,
    p_has_invoice boolean default true,
    p_payment_condition varchar(10) default 'CREDIT'
) returns uuid as $$
declare
    v_supply_order_id uuid;
    v_supplier_invoice_id uuid;
    v_item jsonb;
    v_tenant_id uuid;
    v_product_id uuid;
    v_qty integer;
    v_unit numeric(12,3);
    v_subtotal numeric(12,3);
    v_tax_rate numeric(5,2);
    v_tax_amount numeric(12,3);
    v_account_payable_id uuid;
    v_account_payable_type_id int;
    v_due_date date;
begin
    -- Obtener tenant_id desde la relación supplier -> supplier_branch -> branch
    select b.tenant_id into v_tenant_id
    from supplies_module.supplier s
    join supplies_module.supplier_branch sb on s.supplier_id = sb.supplier_id
    join core.branch b on b.branch_id = sb.branch_id
    where s.supplier_id = p_supplier_id
    limit 1;

    if v_tenant_id is null then
        raise exception 'Cannot determine tenant_id for supplier %', p_supplier_id;
    end if;

    -- Crear la orden de compra
    insert into supplies_module.supply_order(
        supplier_id,
        warehouse_id,
        expected_delivery_date,
        supply_order_status_id
    ) values (
        p_supplier_id,
        p_warehouse_id,
        p_expected_delivery_date,
        1  -- Pending
    ) returning supply_order_id into v_supply_order_id;

    -- Insertar items si se proporcionaron
    if p_items is not null and jsonb_typeof(p_items) = 'array' and jsonb_array_length(p_items) > 0 then
        for v_item in select value from jsonb_array_elements(p_items)
        loop
            v_product_id := (v_item ->> 'product_id')::uuid;
            v_qty := coalesce((v_item ->> 'quantity_ordered')::int, 0);
            v_unit := coalesce((v_item ->> 'unit_price')::numeric, 0);

            insert into supplies_module.supply_order_item(
                supply_order_id,
                tenant_id,
                product_id,
                quantity_ordered,
                unit_price
            ) values (
                v_supply_order_id,
                v_tenant_id,
                v_product_id,
                v_qty,
                v_unit
            );
        end loop;
    end if;

    -- Calcular subtotal de la orden
    v_subtotal := coalesce(supplies_module.calculate_supply_order_total(v_supply_order_id), 0);

    -- Obtener tasa de impuesto del tenant
    select coalesce(tr.rate_percentage, 13.00) into v_tax_rate
    from core.tenant t
    left join core.tax_rate tr on tr.region_id = t.region_id
    where t.tenant_id = v_tenant_id
    limit 1;

    -- Calcular impuesto
    v_tax_amount := round(v_subtotal * (v_tax_rate / 100.0), 3);

    -- Calcular fecha de vencimiento (30 días por defecto)
    v_due_date := (current_date + interval '30 days')::date;

    -- Obtener el ID del tipo de cuenta por pagar 'goods_purchase'
    select account_payable_type_id into v_account_payable_type_id
    from core.account_payable_type
    where type_name = 'goods_purchase'
    limit 1;

    if v_account_payable_type_id is null then
        raise exception 'Account payable type "goods_purchase" not found';
    end if;

    -- ✅ PASO 1: Crear registro en la tabla PADRE (core.account_payable)
    insert into core.account_payable(
        account_payable_type_id,
        has_invoice,
        has_tax,
        subtotal,
        amount_paid,
        is_paid,
        due_date
    ) values (
        v_account_payable_type_id,
        p_has_invoice,
        true,  -- Las órdenes de suministro siempre tienen impuesto
        v_subtotal,
        0,  -- Inicial
        false,  -- Inicial
        v_due_date
    ) returning account_payable_id into v_account_payable_id;

    -- ✅ PASO 2: Crear registro en la tabla HIJA (supplies_account_payable)
    insert into supplies_module.supplies_account_payable(
        account_payable_id,
        supply_order_id,
        tax_amount,
        account_payable_status
    ) values (
        v_account_payable_id,
        v_supply_order_id,
        v_tax_amount,
        1  -- Pending
    );

    -- Crear factura si se requiere
    if p_has_invoice then
        insert into supplies_module.supplier_invoice(
            supply_order_id,
            invoice_number,
            invoice_date,
            payment_condition,
            due_date,
            subtotal_amount,
            tax_rate
        ) values (
            v_supply_order_id,
            'INV-' || to_char(current_timestamp, 'YYYYMMDD-HH24MISS') || '-' || substring(v_supply_order_id::text, 1, 8),
            current_timestamp,
            p_payment_condition,
            v_due_date,
            v_subtotal,
            v_tax_rate
        ) returning supplier_invoice_id into v_supplier_invoice_id;

        -- Crear items de factura desde los items de la orden
        insert into supplies_module.supplier_invoice_item(
            supplier_invoice_id,
            tenant_id,
            product_id,
            quantity_billed,
            unit_price
        )
        select 
            v_supplier_invoice_id,
            tenant_id,
            product_id,
            quantity_ordered,
            unit_price
        from supplies_module.supply_order_item
        where supply_order_id = v_supply_order_id;
    end if;

    return v_supply_order_id;
end;
$$ language plpgsql;

create or replace function update_order_status()
returns trigger as $$
begin
    insert into supplies_module.supply_order_tracking(
        supply_order_id,
        previous_status_id,
        new_status_id,
        notes,
        changed_at
    ) values (
        new.supply_order_id,
        old.supply_order_status_id,
        new.supply_order_status_id,
        'Status updated via trigger',
        current_timestamp
    );

    return new;
end;
$$ language plpgsql;

drop trigger if exists on_order_status_update on supplies_module.supply_order;
create trigger on_order_status_update
after update of supply_order_status_id on supplies_module.supply_order
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
    _pending_payments INT;
    _target_supplies_ap_id UUID;
BEGIN
    SELECT 
        ap.subtotal,
        sap.tax_amount,
        (ap.subtotal + COALESCE(sap.tax_amount, 0)) AS amount_due,
        ap.amount_paid,
        sap.supplies_account_payable_id
    INTO 
        _subtotal,
        _tax_amount,
        _amount_due,
        _current_amount_paid,
        _target_supplies_ap_id
    FROM core.account_payable ap
    JOIN supplies_module.supplies_account_payable sap 
        ON ap.account_payable_id = sap.account_payable_id
    WHERE ap.account_payable_id = _account_payable_id;

    IF _amount_due IS NULL THEN
        RAISE EXCEPTION 'Account payable not found: %', _account_payable_id;
    END IF;

    SELECT COUNT(*) INTO _pending_payments
    FROM supplies_module.supply_order_payment sop
    WHERE sop.supplies_account_payable_id = _target_supplies_ap_id
    AND sop.verified = FALSE;

    IF _pending_payments > 0 THEN
        RETURN FALSE;
    END IF;

    SELECT COALESCE(SUM(sop.amount_paid), 0) INTO _payments_total
    FROM supplies_module.supply_order_payment sop
    WHERE sop.supplies_account_payable_id = _target_supplies_ap_id
    AND sop.verified = TRUE;

    _balance := _amount_due - _payments_total;

    UPDATE core.account_payable
    SET amount_paid = _payments_total,
        updated_at = CURRENT_TIMESTAMP
    WHERE account_payable_id = _account_payable_id;

    IF ABS(_balance) <= 0.01 OR _payments_total >= _amount_due THEN
        UPDATE core.account_payable
        SET is_paid = TRUE,
            updated_at = CURRENT_TIMESTAMP
        WHERE account_payable_id = _account_payable_id;

        UPDATE supplies_module.supplies_account_payable
        SET account_payable_status = 3,
            updated_at = CURRENT_TIMESTAMP
        WHERE account_payable_id = _account_payable_id;

        RETURN TRUE;

    ELSIF _payments_total > 0 THEN
        UPDATE supplies_module.supplies_account_payable
        SET account_payable_status = 2,
            updated_at = CURRENT_TIMESTAMP
        WHERE account_payable_id = _account_payable_id;

        RETURN FALSE;

    ELSE
        RETURN FALSE;
    END IF;
END;
$$ LANGUAGE plpgsql;

create or replace function recalc_account_payable_on_payment()
returns trigger as $$
begin
    if new.verified = true and (old.verified is null or old.verified = false) then
        perform supplies_module.check_account_payable_completion(
            (select account_payable_id 
             from supplies_module.supplies_account_payable 
             where supplies_account_payable_id = new.supplies_account_payable_id)
        );
    end if;
    return new;
end;
$$ language plpgsql;

drop trigger if exists recalc_account_payable_on_payment_trigger on supplies_module.supply_order_payment;
create trigger recalc_account_payable_on_payment_trigger
    after update of verified on supplies_module.supply_order_payment
    for each row
    execute function recalc_account_payable_on_payment();

create or replace function update_invoice_paid_status()
returns trigger as $$
declare
    v_is_paid boolean;
begin
    if new.account_payable_status = 3 and old.account_payable_status is distinct from 3 then
        select is_paid into v_is_paid
        from core.account_payable
        where account_payable_id = new.account_payable_id;
        
        if v_is_paid = true then
            update supplies_module.supplier_invoice
            set paid = true,
                updated_at = current_timestamp
            where supply_order_id = new.supply_order_id;
        end if;
    end if;
    
    return new;
end;
$$ language plpgsql;

drop trigger if exists update_invoice_paid_status_trigger on supplies_module.supplies_account_payable;
create trigger update_invoice_paid_status_trigger
    after update of account_payable_status on supplies_module.supplies_account_payable
    for each row
    execute function supplies_module.update_invoice_paid_status();

create or replace function create_goods_receipt()
returns trigger as $$
declare
    v_goods_receipt_id uuid;
    v_subtotal numeric(12,3);
    v_tax_amount numeric(12,3);
    v_item record;
begin
    if new.supply_order_status_id = 3 and old.supply_order_status_id is distinct from 3 then
        if exists(
            select 1 
            from supplies_module.goods_receipt 
            where supply_order_id = new.supply_order_id
        ) then
            return new;
        end if;

        select 
            ap.subtotal,
            sap.tax_amount
        into v_subtotal, v_tax_amount
        from core.account_payable ap
        join supplies_module.supplies_account_payable sap 
            on ap.account_payable_id = sap.account_payable_id
        where sap.supply_order_id = new.supply_order_id;

        insert into supplies_module.goods_receipt(
            supply_order_id,
            received_date,
            subtotal_amount,
            tax_amount
        ) values (
            new.supply_order_id,
            current_timestamp,
            v_subtotal,
            v_tax_amount
        ) returning goods_receipt_id into v_goods_receipt_id;

        for v_item in 
            select tenant_id, product_id, quantity_ordered
            from supplies_module.supply_order_item
            where supply_order_id = new.supply_order_id
        loop
            insert into supplies_module.goods_receipt_item(
                goods_receipt_id,
                tenant_id,
                product_id,
                quantity_received
            ) values (
                v_goods_receipt_id,
                v_item.tenant_id,
                v_item.product_id,
                v_item.quantity_ordered
            );
        end loop;

        perform supplies_module.execute_three_way_matching(new.supply_order_id, v_goods_receipt_id);
    end if;

    return new;
end;
$$ language plpgsql;

drop trigger if exists create_goods_receipt_trigger on supplies_module.supply_order;
create trigger create_goods_receipt_trigger
    after update of supply_order_status_id on supplies_module.supply_order
    for each row
    execute function supplies_module.create_goods_receipt();

create or replace function execute_three_way_matching(
    p_supply_order_id uuid,
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
    v_order_qty integer;
    v_invoice_qty integer;
    v_receipt_qty integer;
    v_amounts_matched boolean;
    v_quantities_matched boolean;
begin
    select supplier_invoice_id into v_supplier_invoice_id
    from supplies_module.supplier_invoice
    where supply_order_id = p_supply_order_id;

    if v_supplier_invoice_id is null then
        return;
    end if;

    if exists(
        select 1 
        from supplies_module.three_way_matching 
        where supply_order_id = p_supply_order_id
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
    from core.account_payable ap
    join supplies_module.supplies_account_payable sap 
        on ap.account_payable_id = sap.account_payable_id
    where sap.supply_order_id = p_supply_order_id;

    select 
        subtotal_amount,
        tax_amount,
        total_amount
    into 
        v_invoice_subtotal,
        v_invoice_tax,
        v_invoice_total
    from supplies_module.supplier_invoice
    where supplier_invoice_id = v_supplier_invoice_id;

    select 
        subtotal_amount,
        tax_amount,
        total_amount
    into 
        v_receipt_subtotal,
        v_receipt_tax,
        v_receipt_total
    from supplies_module.goods_receipt
    where goods_receipt_id = p_goods_receipt_id;

    select coalesce(sum(quantity_ordered), 0) into v_order_qty
    from supplies_module.supply_order_item
    where supply_order_id = p_supply_order_id;

    select coalesce(sum(quantity_billed), 0) into v_invoice_qty
    from supplies_module.supplier_invoice_item
    where supplier_invoice_id = v_supplier_invoice_id;

    select coalesce(sum(quantity_received), 0) into v_receipt_qty
    from supplies_module.goods_receipt_item
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

    insert into supplies_module.three_way_matching(
        supply_order_id,
        goods_receipt_id,
        supplier_invoice_id,
        amounts_matched,
        quantities_matched,
        is_matched,
        matched_at
    ) values (
        p_supply_order_id,
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

create or replace function generate_payment_alerts()
returns void as $$
declare
    v_config record;
    v_account record;
    v_days_until_due integer;
    v_alert_type_id integer;
    v_existing_alert_id uuid;
begin
    for v_config in 
        select 
            pac.tenant_id,
            pac.warning_days_before_due,
            pac.urgent_days_before_due
        from supplies_module.supply_order_payment_alert_config pac
    loop
        for v_account in
            select 
                ap.account_payable_id,
                ap.due_date,
                ap.is_paid,
                ap.amount_paid,
                ap.subtotal,
                sap.supplies_account_payable_id,
                sap.tax_amount,
                (ap.subtotal + coalesce(sap.tax_amount, 0) - ap.amount_paid) as balance_remaining,
                so.supply_order_id
            from core.account_payable ap
            join supplies_module.supplies_account_payable sap 
                on ap.account_payable_id = sap.account_payable_id
            join supplies_module.supply_order so 
                on sap.supply_order_id = so.supply_order_id
            join supplies_module.supplier s 
                on so.supplier_id = s.supplier_id
            join supplies_module.supplier_branch sb 
                on s.supplier_id = sb.supplier_id
            join core.branch b 
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
            from supplies_module.supply_order_payment_alert
            where supplies_account_payable_id = v_account.supplies_account_payable_id
            and payment_alert_type_id = v_alert_type_id
            and is_resolved = false
            limit 1;
            
            if v_existing_alert_id is null then
                insert into supplies_module.supply_order_payment_alert(
                    supplies_account_payable_id,
                    payment_alert_type_id,
                    alert_date,
                    is_resolved
                ) values (
                    v_account.supplies_account_payable_id,
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

create or replace function get_pending_payment_alerts(p_tenant_id uuid)
returns table(
    payment_alert_id uuid,
    supplies_account_payable_id uuid,
    supply_order_id uuid,
    supplier_name varchar,
    invoice_number varchar,
    alert_type varchar,
    alert_type_description text,
    due_date date,
    days_until_due integer,
    balance_remaining numeric,
    alert_date timestamp,
    created_at timestamp
) as $$
begin
    return query
    select 
        spa.payment_alert_id,
        sap.supplies_account_payable_id,
        so.supply_order_id,
        s.supplier_name,
        si.invoice_number,
        spat.payment_alert_type_name,
        spat.description,
        ap.due_date,
        (ap.due_date - current_date)::integer as days_until_due,
        (ap.subtotal + coalesce(sap.tax_amount, 0) - ap.amount_paid) as balance_remaining,
        spa.alert_date,
        spa.created_at
    from supplies_module.supply_order_payment_alert spa
    join supplies_module.supply_order_payment_alert_type spat 
        on spa.payment_alert_type_id = spat.payment_alert_type_id
    join supplies_module.supplies_account_payable sap 
        on spa.supplies_account_payable_id = sap.supplies_account_payable_id
    join core.account_payable ap 
        on sap.account_payable_id = ap.account_payable_id
    join supplies_module.supply_order so 
        on sap.supply_order_id = so.supply_order_id
    join supplies_module.supplier s 
        on so.supplier_id = s.supplier_id
    left join supplies_module.supplier_invoice si 
        on so.supply_order_id = si.supply_order_id
    join supplies_module.supplier_branch sb 
        on s.supplier_id = sb.supplier_id
    join core.branch b 
        on sb.branch_id = b.branch_id
    where b.tenant_id = p_tenant_id
    and spa.is_resolved = false
    order by ap.due_date asc, spa.alert_date desc;
    
exception
    when others then
        raise exception 'Error fetching pending payment alerts: %', sqlerrm;
end;
$$ language plpgsql;

create or replace function resolve_payment_alert(p_alert_id uuid)
returns void as $$
begin
    update supplies_module.supply_order_payment_alert
    set is_resolved = true,
        updated_at = current_timestamp
    where payment_alert_id = p_alert_id;
end;
$$ language plpgsql;

create or replace function auto_resolve_payment_alerts()
returns trigger as $$
declare
    v_is_paid boolean;
begin
    if new.account_payable_status = 3 and old.account_payable_status is distinct from 3 then
        select is_paid into v_is_paid
        from core.account_payable
        where account_payable_id = new.account_payable_id;
        
        if v_is_paid = true then
            update supplies_module.supply_order_payment_alert
            set is_resolved = true,
                updated_at = current_timestamp
            where supplies_account_payable_id = new.supplies_account_payable_id
            and is_resolved = false;
        end if;
    end if;
    
    return new;
end;
$$ language plpgsql;

drop trigger if exists auto_resolve_payment_alerts_trigger on supplies_module.supplies_account_payable;
create trigger auto_resolve_payment_alerts_trigger
    after update of account_payable_status on supplies_module.supplies_account_payable
    for each row
    execute function supplies_module.auto_resolve_payment_alerts();

create or replace function initialize_payment_alert_config(
    p_tenant_id uuid,
    p_warning_days integer default 7,
    p_urgent_days integer default 3,
    p_email_enabled boolean default true,
    p_sms_enabled boolean default false
) returns uuid as $$
declare
    v_config_id uuid;
begin
    insert into supplies_module.supply_order_payment_alert_config(
        tenant_id,
        warning_days_before_due,
        urgent_days_before_due,
        email_notifications_enabled,
        sms_notifications_enabled
    ) values (
        p_tenant_id,
        p_warning_days,
        p_urgent_days,
        p_email_enabled,
        p_sms_enabled
    )
    on conflict (tenant_id) do update
    set warning_days_before_due = excluded.warning_days_before_due,
        urgent_days_before_due = excluded.urgent_days_before_due,
        email_notifications_enabled = excluded.email_notifications_enabled,
        sms_notifications_enabled = excluded.sms_notifications_enabled,
        updated_at = current_timestamp
    returning payment_alert_config_id into v_config_id;
    
    return v_config_id;
end;
$$ language plpgsql;

create or replace function get_payment_alert_stats(p_tenant_id uuid)
returns table(
    total_alerts integer,
    overdue_count integer,
    urgent_count integer,
    warning_count integer,
    total_amount_at_risk numeric
) as $$
begin
    return query
    select 
        count(*)::integer as total_alerts,
        count(*) filter (where spat.payment_alert_type_id = 3)::integer as overdue_count,
        count(*) filter (where spat.payment_alert_type_id = 2)::integer as urgent_count,
        count(*) filter (where spat.payment_alert_type_id = 1)::integer as warning_count,
        coalesce(sum(ap.subtotal + coalesce(sap.tax_amount, 0) - ap.amount_paid), 0) as total_amount_at_risk
    from supplies_module.supply_order_payment_alert spa
    join supplies_module.supply_order_payment_alert_type spat 
        on spa.payment_alert_type_id = spat.payment_alert_type_id
    join supplies_module.supplies_account_payable sap 
        on spa.supplies_account_payable_id = sap.supplies_account_payable_id
    join core.account_payable ap 
        on sap.account_payable_id = ap.account_payable_id
    join supplies_module.supply_order so 
        on sap.supply_order_id = so.supply_order_id
    join supplies_module.supplier s 
        on so.supplier_id = s.supplier_id
    join supplies_module.supplier_branch sb 
        on s.supplier_id = sb.supplier_id
    join core.branch b 
        on sb.branch_id = b.branch_id
    where b.tenant_id = p_tenant_id
    and spa.is_resolved = false;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error calculating payment alert stats: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;


drop trigger if exists update_supplier_timestamp on supplies_module.supplier;
create trigger update_supplier_timestamp before update on supplies_module.supplier
for each row execute function core.update_timestamp();

drop trigger if exists update_supply_order_timestamp on supplies_module.supply_order;
create trigger update_supply_order_timestamp before update on supplies_module.supply_order
for each row execute function core.update_timestamp();

drop trigger if exists update_supply_order_item_timestamp on supplies_module.supply_order_item;
create trigger update_supply_order_item_timestamp before update on supplies_module.supply_order_item
for each row execute function core.update_timestamp();

drop trigger if exists update_supplier_invoice_timestamp on supplies_module.supplier_invoice;
create trigger update_supplier_invoice_timestamp before update on supplies_module.supplier_invoice
for each row execute function core.update_timestamp();

drop trigger if exists update_supplier_invoice_item_timestamp on supplies_module.supplier_invoice_item;
create trigger update_supplier_invoice_item_timestamp before update on supplies_module.supplier_invoice_item
for each row execute function core.update_timestamp();

drop trigger if exists update_goods_receipt_timestamp on supplies_module.goods_receipt;
create trigger update_goods_receipt_timestamp before update on supplies_module.goods_receipt
for each row execute function core.update_timestamp();

drop trigger if exists update_goods_receipt_item_timestamp on supplies_module.goods_receipt_item;
create trigger update_goods_receipt_item_timestamp before update on supplies_module.goods_receipt_item
for each row execute function core.update_timestamp();

drop trigger if exists update_account_payable_timestamp on supplies_module.supplies_account_payable;
create trigger update_account_payable_timestamp before update on supplies_module.supplies_account_payable
for each row execute function core.update_timestamp();

drop trigger if exists update_supply_order_payment_timestamp on supplies_module.supply_order_payment;
create trigger update_supply_order_payment_timestamp before update on supplies_module.supply_order_payment
for each row execute function core.update_timestamp();

drop trigger if exists update_supply_order_payment_alert_timestamp on supplies_module.supply_order_payment_alert;
create trigger update_supply_order_payment_alert_timestamp before update on supplies_module.supply_order_payment_alert
for each row execute function core.update_timestamp();

drop trigger if exists update_supply_order_payment_alert_config_timestamp on supplies_module.supply_order_payment_alert_config;
create trigger update_supply_order_payment_alert_config_timestamp before update on supplies_module.supply_order_payment_alert_config
for each row execute function core.update_timestamp();

drop trigger if exists update_three_way_matching_timestamp on supplies_module.three_way_matching;
create trigger update_three_way_matching_timestamp before update on supplies_module.three_way_matching
for each row execute function core.update_timestamp();