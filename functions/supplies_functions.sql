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
begin
    select b.tenant_id into v_tenant_id
    from supplies_module.supplier s
    join supplies_module.supplier_branch sb on s.supplier_id = sb.supplier_id
    join core.branch b on b.branch_id = sb.branch_id
    where s.supplier_id = p_supplier_id
    limit 1;

    if v_tenant_id is null then
        raise exception 'Cannot determine tenant_id for supplier %', p_supplier_id;
    end if;

    insert into supplies_module.supply_order(
        supplier_id,
        warehouse_id,
        expected_delivery_date,
        supply_order_status_id
    ) values (
        p_supplier_id,
        p_warehouse_id,
        p_expected_delivery_date,
        1
    ) returning supply_order_id into v_supply_order_id;

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

    v_subtotal := coalesce(supplies_module.calculate_supply_order_total(v_supply_order_id), 0);

    select coalesce(tr.rate_percentage, 13.00) into v_tax_rate
    from core.tenant t
    left join core.tax_rate tr on tr.region_id = t.region_id
    where t.tenant_id = v_tenant_id
    limit 1;

    v_tax_amount := round(v_subtotal * (v_tax_rate / 100.0), 3);

    insert into supplies_module.account_payable(
        supply_order_id,
        has_invoice,
        subtotal_amount,
        tax_amount,
        due_date,
        account_status
    ) values (
        v_supply_order_id,
        p_has_invoice,
        v_subtotal,
        v_tax_amount,
        (current_date + interval '30 days')::date,
        1
    );

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
            (current_date + interval '30 days')::date,
            v_subtotal,
            v_tax_rate
        ) returning supplier_invoice_id into v_supplier_invoice_id;

        for v_item in 
            select jsonb_build_object(
                'tenant_id', tenant_id,
                'product_id', product_id,
                'quantity_ordered', quantity_ordered,
                'unit_price', unit_price
            ) as value
            from supplies_module.supply_order_item
            where supply_order_id = v_supply_order_id
        loop
            insert into supplies_module.supplier_invoice_item(
                supplier_invoice_id,
                tenant_id,
                product_id,
                quantity_billed,
                unit_price
            ) values (
                v_supplier_invoice_id,
                (v_item ->> 'tenant_id')::uuid,
                (v_item ->> 'product_id')::uuid,
                (v_item ->> 'quantity_ordered')::integer,
                (v_item ->> 'unit_price')::numeric
            );
        end loop;
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

create or replace function check_account_payable_completion(
    _account_payable_id uuid
) returns boolean as $$
declare
    _amount_due numeric(12,3);
    _payments_total numeric(12,3);
    _pending_payments int;
begin
    select amount_due
    into _amount_due
    from supplies_module.account_payable
    where account_payable_id = _account_payable_id;
    
    if _amount_due is null then
        raise exception 'Account payable not found: %', _account_payable_id;
    end if;
    
    select count(*) into _pending_payments
    from supplies_module.supply_order_payment
    where account_payable_id = _account_payable_id
    and verified = false;
    
    if _pending_payments > 0 then
        return false;
    end if;
    
    select coalesce(sum(amount_paid), 0) into _payments_total
    from supplies_module.supply_order_payment
    where account_payable_id = _account_payable_id
    and verified = true;
    
    if abs(_payments_total - _amount_due) <= 0.01 or _payments_total > _amount_due then
        update supplies_module.account_payable
        set amount_paid = _payments_total,
            account_status = 3,
            updated_at = current_timestamp
        where account_payable_id = _account_payable_id;
        
        return true;
    elsif _payments_total > 0 then
        update supplies_module.account_payable
        set amount_paid = _payments_total,
            account_status = 2,
            updated_at = current_timestamp
        where account_payable_id = _account_payable_id;
        
        return false;
    else
        return false;
    end if;
    
exception
    when others then
        return false;
end;
$$ language plpgsql;

create or replace procedure supplies_module.verify_supply_order_payment(
    _payment_id uuid
) as $$
declare
    _exists boolean;
    _already_verified boolean;
    _account_payable_id uuid;
begin
    select exists(
        select 1 
        from supplies_module.supply_order_payment
        where payment_id = _payment_id
    ) into _exists;
    
    if not _exists then
        raise exception 'Payment not found: %', _payment_id;
    end if;
    
    select verified, account_payable_id
    into _already_verified, _account_payable_id
    from supplies_module.supply_order_payment
    where payment_id = _payment_id;
    
    if _already_verified then
        return;
    end if;
    
    update supplies_module.supply_order_payment
    set verified = true,
        updated_at = current_timestamp
    where payment_id = _payment_id;
    
    perform supplies_module.check_account_payable_completion(_account_payable_id);
end;
$$ language plpgsql;

create or replace function recalc_account_payable_on_payment()
returns trigger as $$
declare
    _account_payable_id uuid;
begin
    _account_payable_id := coalesce(new.account_payable_id, old.account_payable_id);
    
    perform supplies_module.check_account_payable_completion(_account_payable_id);
    
    return coalesce(new, old);
end;
$$ language plpgsql;

drop trigger if exists recalc_account_payable_on_payment_trigger on supplies_module.supply_order_payment;
create trigger recalc_account_payable_on_payment_trigger
    after insert or update of verified or delete on supplies_module.supply_order_payment
    for each row
    execute function supplies_module.recalc_account_payable_on_payment();

create or replace function update_invoice_paid_status()
returns trigger as $$
begin
    if new.account_status = 3 and old.account_status is distinct from 3 then
        update supplies_module.supplier_invoice
        set paid = true,
            updated_at = current_timestamp
        where supply_order_id = new.supply_order_id;
    end if;
    
    return new;
end;
$$ language plpgsql;

drop trigger if exists update_invoice_paid_status_trigger on supplies_module.account_payable;
create trigger update_invoice_paid_status_trigger
    after update of account_status on supplies_module.account_payable
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

        select subtotal_amount, tax_amount 
        into v_subtotal, v_tax_amount
        from supplies_module.account_payable
        where supply_order_id = new.supply_order_id;

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
    end if;

    return new;
end;
$$ language plpgsql;

drop trigger if exists create_goods_receipt_trigger on supplies_module.supply_order;
create trigger create_goods_receipt_trigger
    after update of supply_order_status_id on supplies_module.supply_order
    for each row
    execute function supplies_module.create_goods_receipt();

create or replace function perform_three_way_matching()
returns trigger as $$
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
    where supply_order_id = new.supply_order_id;

    if v_supplier_invoice_id is null then
        return new;
    end if;

    if exists(
        select 1 
        from supplies_module.three_way_matching 
        where supply_order_id = new.supply_order_id
    ) then
        return new;
    end if;

    select 
        subtotal_amount,
        tax_amount,
        amount_due
    into 
        v_order_subtotal,
        v_order_tax,
        v_order_total
    from supplies_module.account_payable
    where supply_order_id = new.supply_order_id;

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

    v_receipt_subtotal := new.subtotal_amount;
    v_receipt_tax := new.tax_amount;
    v_receipt_total := new.total_amount;

    select coalesce(sum(quantity_ordered), 0) into v_order_qty
    from supplies_module.supply_order_item
    where supply_order_id = new.supply_order_id;

    select coalesce(sum(quantity_billed), 0) into v_invoice_qty
    from supplies_module.supplier_invoice_item
    where supplier_invoice_id = v_supplier_invoice_id;

    select coalesce(sum(quantity_received), 0) into v_receipt_qty
    from supplies_module.goods_receipt_item
    where goods_receipt_id = new.goods_receipt_id;

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
        new.supply_order_id,
        new.goods_receipt_id,
        v_supplier_invoice_id,
        v_amounts_matched,
        v_quantities_matched,
        v_amounts_matched and v_quantities_matched,
        current_timestamp
    );

    return new;
end;
$$ language plpgsql;

drop trigger if exists perform_three_way_matching_trigger on supplies_module.goods_receipt;
create trigger perform_three_way_matching_trigger
    after insert on supplies_module.goods_receipt
    for each row
    execute function supplies_module.perform_three_way_matching();

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

drop trigger if exists update_account_payable_timestamp on supplies_module.account_payable;
create trigger update_account_payable_timestamp before update on supplies_module.account_payable
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

-- drop trigger if exists update_three_way_matching_timestamp on supplies_module.three_way_matching;
-- create trigger update_three_way_matching_timestamp before update on supplies_module.three_way_matching
-- for each row execute function core.update_timestamp();