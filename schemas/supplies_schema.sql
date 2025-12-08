-- SCHEMA: supplies
drop schema if exists supplies_module cascade;
create schema if not exists supplies_module;
set search_path to supplies_module;

create table if not exists supplier(
    supplier_id uuid primary key default gen_random_uuid(),
    supplier_name varchar(255) not null,
    supplier_contact_info text,
    supplier_address text,
    supplier_notes text,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create unique index if not exists ux_supplier_name on supplies_module.supplier(supplier_name);

create table if not exists supplier_branch(
    supplier_branch_id uuid primary key default gen_random_uuid(),
    supplier_id uuid not null references supplies_module.supplier(supplier_id) on delete cascade,
    branch_id uuid not null references core.branch(branch_id) on delete cascade,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp,

    unique(supplier_id, branch_id)
);

create table if not exists supply_order_status(
    status_id serial primary key,
    status_name varchar(50) not null,
    description text,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into supply_order_status(status_name, description) values
('Pending', 'Order is pending'),
('Shipped', 'Order has been shipped'),
('Delivered', 'Order has been delivered'),
('Cancelled', 'Order has been cancelled')
on conflict do nothing;

create table if not exists supply_order(
    supply_order_id uuid primary key default gen_random_uuid(),
    supplier_id uuid not null references supplies_module.supplier(supplier_id) on delete cascade,
    warehouse_id uuid not null references inventory_module.warehouse(warehouse_id) on delete cascade,
    supply_order_date date default current_date,
    expected_delivery_date date,
    supply_order_status_id integer not null references supplies_module.supply_order_status(status_id) default 1,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table if not exists supply_order_item(
    supply_order_item_id uuid primary key default gen_random_uuid(),
    supply_order_id uuid not null references supplies_module.supply_order(supply_order_id) on delete cascade,
    tenant_id uuid not null,                                                         
    product_id uuid not null,
    quantity_ordered integer not null,
    unit_price numeric(12,3) not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp,

    foreign key (tenant_id, product_id) references core.product(tenant_id, product_id) on delete cascade
);

create table if not exists supply_order_tracking(
    supply_order_tracking_id uuid primary key default gen_random_uuid(),
    supply_order_id uuid not null references supplies_module.supply_order(supply_order_id) on delete cascade,
    previous_status_id int references supplies_module.supply_order_status(status_id),
    new_status_id int not null references supplies_module.supply_order_status(status_id),
    notes text,
    changed_at timestamp default current_timestamp
);

create table if not exists supplier_invoice(
    supplier_invoice_id uuid primary key default gen_random_uuid(),
    supply_order_id uuid not null references supplies_module.supply_order(supply_order_id) on delete cascade,
    invoice_number varchar(100) not null,
    invoice_date timestamp default current_timestamp,
    payment_condition varchar(10) not null default 'CREDIT', 
    due_date date,
    subtotal_amount numeric(12,3) not null,
    tax_rate numeric(5,2) not null default 13.00,
    tax_amount numeric(12,3) generated always as (round(subtotal_amount * (tax_rate / 100), 3)) stored,
    total_amount numeric(12,3) generated always as (
        subtotal_amount + round(subtotal_amount * (tax_rate / 100), 3)
    ) stored,    
    paid boolean default false,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp,
    
    check (payment_condition in ('CREDIT', 'IN_FULL'))
);

create table if not exists supplier_invoice_item(
    supplier_invoice_item_id uuid primary key default gen_random_uuid(),
    supplier_invoice_id uuid not null references supplies_module.supplier_invoice(supplier_invoice_id) on delete cascade,
    tenant_id uuid not null,                                                         
    product_id uuid not null,
    quantity_billed integer not null,
    unit_price numeric(12,3) not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp,

    foreign key (tenant_id, product_id) references core.product(tenant_id, product_id) on delete cascade
);

create table if not exists goods_receipt(
    goods_receipt_id uuid primary key default gen_random_uuid(),
    supply_order_id uuid not null references supplies_module.supply_order(supply_order_id) on delete cascade,
    received_date timestamp default current_timestamp,
    total_amount numeric(12,3) default 0,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table if not exists goods_receipt_item(
    goods_receipt_item_id uuid primary key default gen_random_uuid(),
    goods_receipt_id uuid not null references supplies_module.goods_receipt(goods_receipt_id) on delete cascade,
    tenant_id uuid not null,                                                         
    product_id uuid not null,
    quantity_received integer not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp,

    foreign key (tenant_id, product_id) references core.product(tenant_id, product_id) on delete cascade
);

create table if not exists account_payable_status(
    status_id serial primary key,
    status_name varchar(50) not null,
    description text,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into account_payable_status(status_name, description) values
('Pending', 'Payment is pending'),
('Partial Paid', 'Partial payment has been made'),
('Paid', 'Payment has been made'),
('Overdue', 'Payment is overdue')
on conflict do nothing;

create table if not exists account_payable(
    account_payable_id uuid primary key default gen_random_uuid(),
    supply_order_id uuid not null unique references supplies_module.supply_order(supply_order_id) on delete cascade,
    has_invoice boolean default true,
    subtotal_amount numeric(12,3) default 0,
    amount_due numeric(12,3) generated always as (subtotal_amount) stored,
    amount_paid numeric(12,3) default 0,
    balance_remaining numeric(12,3) generated always as (subtotal_amount - amount_paid) stored,
    due_date date not null,
    account_status integer not null default 1 references supplies_module.account_payable_status(status_id),
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table if not exists supply_order_payment(
    payment_id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references core.tenant(tenant_id) on delete cascade,
    account_payable_id uuid not null references supplies_module.account_payable(account_payable_id) on delete cascade,
    payment_date timestamp default current_timestamp,
    amount_paid numeric(12,3) not null,
    payment_method_id integer not null references core.payment_method(payment_method_id) on delete cascade,
    payment_reference varchar(100),  
    verified boolean default false,  
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table if not exists supply_order_payment_alert_type(
    payment_alert_type_id serial primary key,
    payment_alert_type_name varchar(50) not null,
    description text,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into supply_order_payment_alert_type(payment_alert_type_name, description) values
('Upcoming Due Date', 'Alert for upcoming payment due date'),
('Urgent Payment', 'Alert for urgent payments'),
('Overdue Payment', 'Alert for overdue payments')
on conflict do nothing;

create table if not exists supply_order_payment_alert(
    payment_alert_id uuid primary key default gen_random_uuid(),
    account_payable_id uuid not null references supplies_module.account_payable(account_payable_id) on delete cascade,
    payment_alert_type_id integer not null references supplies_module.supply_order_payment_alert_type(payment_alert_type_id),
    alert_date timestamp default current_timestamp,
    is_resolved boolean default false,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table if not exists supply_order_payment_alert_config(
    payment_alert_config_id uuid primary key default gen_random_uuid(),
    tenant_id uuid unique not null references core.tenant(tenant_id) on delete cascade,
    warning_days_before_due integer default 7,
    urgent_days_before_due integer default 3,
    email_notifications_enabled boolean default true,
    sms_notifications_enabled boolean default false,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table if not exists three_way_matching(
    matching_id uuid primary key default gen_random_uuid(),
    supply_order_id uuid not null references supplies_module.supply_order(supply_order_id) on delete cascade,
    goods_receipt_id uuid not null references supplies_module.goods_receipt(goods_receipt_id) on delete cascade,
    supplier_invoice_id uuid not null references supplies_module.supplier_invoice(supplier_invoice_id) on delete cascade,
    amounts_matched boolean default false,
    quantities_matched boolean default false,
    is_matched boolean default false,
    matched_at timestamp,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

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


create or replace procedure create_supplier_invoice(
    p_supply_order_id uuid,
    p_tenant_id uuid,                              
    p_subtotal_amount numeric(12,3),               
    p_payment_condition varchar(10) default 'CREDIT'
) 
language plpgsql 
as $$
declare
    v_supplier_invoice_id uuid;
    v_region_id int;
    v_rate_pct numeric;
    v_tax_rate numeric := 13.00; -- default fallback 13%
    v_tax_amount numeric(12,3);
    v_due_date date;
begin
    if not exists(select 1 from supplies_module.supply_order where supply_order_id = p_supply_order_id) then
        raise exception 'Supply order % not found', p_supply_order_id;
    end if;

    if exists(select 1 from supplies_module.supplier_invoice where supply_order_id = p_supply_order_id) then
        raise notice '⚠️  Invoice already exists for supply order %', p_supply_order_id;
        return;
    end if;

    if p_tenant_id is not null then
        select region_id into v_region_id
        from core.tenant
        where tenant_id = p_tenant_id;

        if v_region_id is not null then
            select rate_percentage into v_rate_pct
            from core.tax_rate
            where region_id = v_region_id
            limit 1;
        end if;
    end if;

    if v_rate_pct is not null then
        v_tax_rate := (v_rate_pct::numeric / 100.0);
    else
        select rate_percentage into v_rate_pct
        from core.tax_rate
        where region_id is null
        limit 1;

        if v_rate_pct is not null then
            v_tax_rate := (v_rate_pct::numeric / 100.0);
        else
            v_tax_rate := 0.13; -- Final fallback
        end if;
    end if;

    v_tax_amount := round(p_subtotal_amount * v_tax_rate, 3);


    select due_date into v_due_date
    from supplies_module.account_payable
    where supply_order_id = p_supply_order_id;

    if v_due_date is null then
        v_due_date := (current_date + interval '30 days')::date;
    end if;

    insert into supplies_module.supplier_invoice(
        supply_order_id,
        invoice_number,
        invoice_date,
        payment_condition,
        due_date,
        subtotal_amount,
        tax_rate
    ) values (
        p_supply_order_id,
        'INV-' || to_char(current_timestamp, 'YYYYMMDD-HH24MISS') || '-' || substring(p_supply_order_id::text, 1, 8),
        current_timestamp,
        p_payment_condition,
        v_due_date,
        p_subtotal_amount,                         
        v_tax_rate * 100                        
    ) returning supplier_invoice_id into v_supplier_invoice_id;

    raise notice '✅ Invoice created: %', v_supplier_invoice_id;

    insert into supplies_module.supplier_invoice_item(
        supplier_invoice_id,
        tenant_id,
        product_id,
        quantity_billed,
        unit_price,
        created_at,
        updated_at
    )
    select 
        v_supplier_invoice_id,
        tenant_id,
        product_id,
        quantity_ordered,
        unit_price,
        current_timestamp,
        current_timestamp
    from supplies_module.supply_order_item
    where supply_order_id = p_supply_order_id;

    raise notice '✅ Copied % items to supplier invoice', (
        select count(*) 
        from supplies_module.supplier_invoice_item 
        where supplier_invoice_id = v_supplier_invoice_id
    );

    return;
exception
    when others then
        raise notice '❌ Error creating supplier invoice: %', sqlerrm;
        raise;
end
$$;

create or replace function create_supply_order(
    p_supplier_id uuid,
    p_warehouse_id uuid,
    p_expected_delivery_date date,
    p_items jsonb,
    p_has_invoice boolean default false,
    p_payment_condition varchar(20) default 'IN_FULL'
)
returns uuid
language plpgsql
as $$
declare
    v_supply_order_id uuid;
    v_tenant_id uuid;
    v_branch_id uuid;              
    v_subtotal numeric(12, 3) := 0;
    v_item jsonb;
    v_product_id uuid;
    v_qty int;
    v_unit numeric(12,3);
begin
    select sb.branch_id into v_branch_id
    from supplies_module.supplier_branch sb
    where sb.supplier_id = p_supplier_id
    limit 1;

    if v_branch_id is null then
        raise exception 'No branch mapping found for supplier %', p_supplier_id;
    end if;

    select b.tenant_id into v_tenant_id
    from core.branch b
    where b.branch_id = v_branch_id;

    if v_tenant_id is null then
        raise exception 'Cannot determine tenant_id for supplier % (branch: %)', p_supplier_id, v_branch_id;
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
        for v_item in select * from jsonb_array_elements(p_items)
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

            v_subtotal := v_subtotal + (v_qty * v_unit);
        end loop;
    end if;

    insert into supplies_module.account_payable(
        supply_order_id,
        has_invoice,
        subtotal_amount,
        due_date,
        account_status
    ) values (
        v_supply_order_id,
        p_has_invoice,
        v_subtotal,
        (current_date + interval '30 days')::date,
        1  
    );

    raise notice '✅ Account payable created';
    raise notice '   Subtotal (no tax): $%', v_subtotal;
    raise notice '   Has invoice: %', p_has_invoice;

    if p_has_invoice then
        raise notice '✅ Creating supplier invoice via CALL...';
        call supplies_module.create_supplier_invoice(
            v_supply_order_id,
            v_tenant_id,
            v_subtotal,
            p_payment_condition
        );
        raise notice '✅ Supplier invoice created';
    else
        raise notice 'ℹ️  No invoice created (has_invoice = false)';
    end if;

    return v_supply_order_id;
exception
    when others then
        raise notice '❌ Error creating supply order: %', sqlerrm;
        raise;
end;
$$;

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

drop trigger if exists on_order_status_insert on supplies_module.supply_order;
create trigger on_order_status_insert
after update of supply_order_status_id on supplies_module.supply_order
for each row 
when (old.supply_order_status_id is distinct from new.supply_order_status_id)  
execute function update_order_status();

create or replace function check_account_payable_completion(
    _account_payable_id uuid
) returns boolean as $$
declare
    _amount_due numeric(12,3);
    _payments_total numeric(12,3);
    _pending_payments int;
    _current_status int;
begin
    select amount_due, account_status
    into _amount_due, _current_status
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
        raise notice '   ⏳ Account % has % unverified payments', _account_payable_id, _pending_payments;
        return false;
    end if;
    
    select coalesce(sum(amount_paid), 0) into _payments_total
    from supplies_module.supply_order_payment
    where account_payable_id = _account_payable_id
    and verified = true;
    
    if abs(_payments_total - _amount_due) <= 0.01 then
        update supplies_module.account_payable
        set amount_paid = _payments_total,
            account_status = 3,  
            updated_at = current_timestamp
        where account_payable_id = _account_payable_id;
        
        raise notice '   ✅ Account % marked as PAID', _account_payable_id;
        return true;
        
    elsif _payments_total > _amount_due then
        raise warning 'Overpayment detected: Expected $%, Paid $%', _amount_due, _payments_total;
        
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
        
        raise notice '   ⏳ Account % partially paid (shortage: $%)', 
            _account_payable_id, (_amount_due - _payments_total);
        return false;
    else
        raise notice '   ⏳ Account % still pending (no payments)', _account_payable_id;
        return false;
    end if;
    
exception
    when others then
        raise notice '   ❌ Error checking account completion: %', sqlerrm;
        return false;
end;
$$ language plpgsql;

create or replace procedure verify_supply_order_payment(
    _payment_id uuid
) as $$
declare
    _exists boolean;
    _already_verified boolean;
    _account_payable_id uuid;
    _amount_paid numeric(10,2);
    _payment_method varchar(50);
    _account_completed boolean;
begin
    select exists(
        select 1 
        from supplies_module.supply_order_payment
        where payment_id = _payment_id
    ) into _exists;
    
    if not _exists then
        raise exception 'Payment not found: %', _payment_id;
    end if;
    
    select verified, account_payable_id, amount_paid
    into _already_verified, _account_payable_id, _amount_paid
    from supplies_module.supply_order_payment
    where payment_id = _payment_id;
    
    if _already_verified then
        raise notice '⚠️  Payment % is already verified', _payment_id;
        return;
    end if;

    select pm.name into _payment_method
    from core.payment_method pm
    join supplies_module.supply_order_payment sop on pm.payment_method_id = sop.payment_method_id
    where sop.payment_id = _payment_id;
    
    update supplies_module.supply_order_payment
    set verified = true,
        updated_at = current_timestamp
    where payment_id = _payment_id;
    
    _account_completed := supplies_module.check_account_payable_completion(_account_payable_id);
    
exception
    when others then
        raise notice '❌ Payment verification failed: %', sqlerrm;
        raise;
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

create or replace function create_supplier_invoice()
returns trigger as $$ 
declare
    v_supplier_invoice_id uuid;
    v_supply_order_id uuid;
    v_supplier_id uuid;
    v_branch_id uuid;      
    v_tenant_id uuid;
    v_region_id int;
    v_rate_pct numeric;
    v_tax_rate numeric := 0.13; -- default fallback 13%
    v_subtotal numeric(12,3);
    v_tax_amount numeric(12,3);
    v_item record;
begin

    select supply_order_id into v_supply_order_id
    from supplies_module.account_payable
    where account_payable_id = new.account_payable_id;

    if v_supply_order_id is null then
        raise notice 'No supply_order found for account_payable %', new.account_payable_id;
        return new;
    end if;

    select supplier_id into v_supplier_id
    from supplies_module.supply_order
    where supply_order_id = v_supply_order_id;

    if v_supplier_id is null then
        raise notice 'No supplier found for supply_order %', v_supply_order_id;
        return new;
    end if;

    select sb.branch_id into v_branch_id
    from supplies_module.supplier_branch sb
    where sb.supplier_id = v_supplier_id
    limit 1;

    if v_branch_id is not null then
        select tenant_id into v_tenant_id
        from core.branch
        where branch_id = v_branch_id;
    end if;

    if v_tenant_id is not null then
        select region_id into v_region_id
        from core.tenant
        where tenant_id = v_tenant_id;
    end if;

    if v_region_id is not null then
        select rate_percentage into v_rate_pct
        from core.tax_rate
        where region_id = v_region_id
        limit 1;
    end if;

    if v_rate_pct is not null then
        v_tax_rate := (v_rate_pct::numeric / 100.0);
    else
        select rate_percentage into v_rate_pct
        from core.tax_rate
        where region_id is null
        limit 1;

        if v_rate_pct is not null then
            v_tax_rate := (v_rate_pct::numeric / 100.0);
        else
            v_tax_rate := 0.13;
        end if;
    end if;

    if exists(
        select 1 
        from supplies_module.supplier_invoice 
        where supply_order_id = v_supply_order_id
    ) then
        raise notice '⚠️  Supplier invoice already exists for supply order %', v_supply_order_id;
        return new;
    end if;

    v_subtotal := new.amount_due / (1 + v_tax_rate);
    v_tax_amount := new.amount_due - v_subtotal;

    insert into supplies_module.supplier_invoice(
        supplier_invoice_id,
        supply_order_id,
        invoice_number,
        invoice_date,
        due_date,
        subtotal_amount,
        tax_amount,
        created_at,
        updated_at
    ) values (
        gen_random_uuid(),
        v_supply_order_id,
        'INV-' || to_char(current_timestamp, 'YYYYMMDD-HH24MISS') || '-' || substring(v_supply_order_id::text, 1, 8),
        current_timestamp,
        new.due_date,
        round(v_subtotal, 3),
        round(v_tax_amount, 3),
        current_timestamp,
        current_timestamp
    ) returning supplier_invoice_id into v_supplier_invoice_id;

    raise notice '✅ Created supplier invoice % for supply order %', v_supplier_invoice_id, v_supply_order_id;

    for v_item in 
        select tenant_id, product_id, quantity_ordered, unit_price
        from supplies_module.supply_order_item
        where supply_order_id = v_supply_order_id
    loop
        insert into supplies_module.supplier_invoice_item(
            supplier_invoice_item_id,
            supplier_invoice_id,
            tenant_id,           
            product_id,
            quantity_billed,
            unit_price,
            created_at,
            updated_at
        ) values (
            gen_random_uuid(),
            v_supplier_invoice_id,
            v_item.tenant_id,    
            v_item.product_id,
            v_item.quantity_ordered,
            v_item.unit_price,
            current_timestamp,
            current_timestamp
        );
    end loop;

    raise notice '✅ Copied % items to supplier invoice', (
        select count(*) 
        from supplies_module.supplier_invoice_item 
        where supplier_invoice_id = v_supplier_invoice_id
    );

    return new;
end;
$$ language plpgsql;

create or replace function update_invoice_paid_status()
returns trigger as $$
declare
    v_has_invoice boolean;
begin
    if new.account_status = 3 and old.account_status is distinct from 3 then
        
        select has_invoice into v_has_invoice
        from supplies_module.account_payable
        where account_payable_id = new.account_payable_id;
        
        if v_has_invoice then
            update supplies_module.supplier_invoice
            set paid = true,
                updated_at = current_timestamp
            where supply_order_id = new.supply_order_id;
            
            raise notice '✅ Invoice marked as paid for order %', new.supply_order_id;
        else
            raise notice 'ℹ️  Order has no invoice (has_invoice = false)';
        end if;
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
    v_supply_order_id uuid := coalesce(new.supply_order_id, old.supply_order_id);
    v_exists boolean;
    v_item record;
    v_total numeric(12,3);
begin
    select exists(
        select 1 from supplies_module.goods_receipt where supply_order_id = v_supply_order_id
    ) into v_exists;

    if v_exists then
        raise notice 'ℹ️ Goods receipt already exists for supply_order %', v_supply_order_id;
        return new;
    end if;

    select si.total_amount
    into v_total
    from supplies_module.supplier_invoice si
    where si.supply_order_id = v_supply_order_id
    limit 1;

    if v_total is null then
        select coalesce(sum(quantity_ordered * unit_price), 0)
        into v_total
        from supplies_module.supply_order_item
        where supply_order_id = v_supply_order_id;
    end if;

    v_total := round(coalesce(v_total, 0)::numeric, 3);

    insert into supplies_module.goods_receipt(
        goods_receipt_id,
        supply_order_id,
        received_date,
        total_amount,
        created_at,
        updated_at
    ) values (
        gen_random_uuid(),
        v_supply_order_id,
        current_timestamp,
        v_total,
        current_timestamp,
        current_timestamp
    ) returning goods_receipt_id into v_goods_receipt_id;

    raise notice '✅ Goods receipt % created for supply_order % (total $%)', v_goods_receipt_id, v_supply_order_id, v_total;

    for v_item in 
        select tenant_id, product_id, quantity_ordered, unit_price
        from supplies_module.supply_order_item
        where supply_order_id = v_supply_order_id
    loop
        insert into supplies_module.goods_receipt_item(
            goods_receipt_item_id,
            goods_receipt_id,
            tenant_id,
            product_id,
            quantity_received,
            created_at,
            updated_at
        ) values (
            gen_random_uuid(),
            v_goods_receipt_id,
            v_item.tenant_id,
            v_item.product_id,
            v_item.quantity_ordered,
            current_timestamp,
            current_timestamp
        );
    end loop;

    raise notice '✅ Copied % items to goods_receipt', (
        select count(*) from supplies_module.goods_receipt_item where goods_receipt_id = v_goods_receipt_id
    );

    return new;
exception
    when others then
        raise notice '❌ Error creating goods receipt for order %: %', v_supply_order_id, sqlerrm;
        return new;
end;
$$ language plpgsql;

drop trigger if exists create_goods_receipt on supplies_module.supply_order;
create trigger create_goods_receipt
    after update of supply_order_status_id on supplies_module.supply_order
    for each row
    when (new.supply_order_status_id = 3 and old.supply_order_status_id is distinct from 3)
    execute function supplies_module.create_goods_receipt();

-- Update timestamp triggers

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