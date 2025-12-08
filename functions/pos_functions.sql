set search_path = pos_module;

create or replace function check_sale_payment_completion(_sale_id uuid)
returns boolean as $$
declare
    _sale_total numeric(10,2);
    _payments_total numeric(10,2);
    _is_completed boolean;
    _pending_payments int;
begin
        select total_amount, is_completed 
        into _sale_total, _is_completed
        from pos_module.sale
        where sale_id = _sale_id;
        
        if _sale_total is null then
            raise exception 'Sale not found: %', _sale_id;
        end if;
        
        if _is_completed then
            return true;
        end if;
        
        select count(*) into _pending_payments
        from pos_module.customer_payment
        where sale_id = _sale_id
        and verified = false;
        
        if _pending_payments > 0 then
            return false;
        end if;
        
        select coalesce(sum(payment_amount), 0) into _payments_total
        from pos_module.customer_payment
        where sale_id = _sale_id
        and verified = true;
        
        raise notice '   💰 Sale total (with tax): $%', _sale_total;
        raise notice '   💳 Payments total: $%', _payments_total;
        raise notice '   📊 Difference: $%', (_sale_total - _payments_total);
        
        if abs(_payments_total - _sale_total) <= 0.01 then
            update pos_module.sale
            set is_completed = true,
                updated_at = current_timestamp
            where sale_id = _sale_id;
            
            raise notice '   ✅ Sale % marked as COMPLETED', _sale_id;
            return true;
            
        elsif _payments_total > _sale_total then
            raise warning 'Overpayment detected: Expected $%, Paid $%',
                _sale_total, _payments_total;
            return false;
            
        else
            raise notice '   ⏳ Sale % still pending (shortage: $%)', 
                _sale_id, (_sale_total - _payments_total);
            return false;
        end if;
        
    exception
        when others then
            raise notice '   ❌ Error checking sale completion: %', sqlerrm;
            return false;
end;
$$ language plpgsql;

create or replace function link_sale_to_session()
returns trigger as $$
declare 
    _session_id uuid;
begin
    select crs.cash_register_session_id into _session_id
    from pos_module.cash_register_session crs
    join pos_module.cash_register cr on crs.cash_register_id = cr.cash_register_id
    where cr.branch_id = new.branch_id
    and crs.is_active = true
    limit 1;
    
    if _session_id is not null then
        insert into pos_module.cash_register_sale(
            cash_register_session_id,
            sale_id,
            transaction_time
        ) values (
            _session_id,
            new.sale_id,
            current_timestamp
        )
        on conflict (sale_id) do nothing;
        
        raise notice '✅ Sale % linked to session %', new.sale_id, _session_id;
    else
        raise warning 'No active cash register session for branch %', new.branch_id;
    end if;
    
    return new;
end;
$$ language plpgsql;

drop trigger if exists on_sale_completed_link_sale_to_session on pos_module.sale;
create trigger on_sale_completed_link_sale_to_session
    after update of is_completed on pos_module.sale
    for each row
    when (old.is_completed is false and new.is_completed is true)
    execute function link_sale_to_session();

create or replace function calculate_bill_total()
returns trigger as $$
begin
    new.total_amount := new.subtotal_amount + new.tax_amount;
    return new;
end;
$$ language plpgsql;

drop trigger if exists calculate_bill_total_trigger on pos_module.bill;
create trigger calculate_bill_total_trigger
    before insert or update on pos_module.bill
    for each row
    execute function calculate_bill_total();

create or replace function calculate_total_price()
returns trigger as $$
begin
    new.total_price := new.quantity * new.unit_price;
    return new;
end;
$$ language plpgsql;

drop trigger if exists calculate_total_price_return_product_trigger on pos_module.return_product;
create trigger calculate_total_price_return_product_trigger
    before insert or update on pos_module.return_product
    for each row
    execute function calculate_total_price();

create or replace function pos_module.get_bill(_sale_id uuid)
returns table (
    bill_id uuid,
    sale_id uuid,
    tenant_customer_id uuid,
    currency_id integer,
    subtotal_amount numeric(10,2),
    tax_amount numeric(10,2),
    total_amount numeric(10,2),
    created_at timestamp,
    updated_at timestamp
) as $$
begin
    return query
    select 
        b.bill_id,
        b.sale_id,
        b.tenant_customer_id,
        b.currency_id,
        b.subtotal_amount,
        b.tax_amount,
        b.total_amount,
        b.created_at,
        b.updated_at
    from pos_module.bill b
    where b.sale_id = _sale_id;
end;
$$ language plpgsql;

create or replace function create_bill()
returns trigger as $$
declare
    _bill_id uuid;
    _tenant_customer_id uuid;
    _tenant_id uuid;
    _currency_id integer;
    _subtotal numeric(10,2);
    _tax numeric(10,2);
    _total numeric(10,2);
    _payment_ids uuid[];
begin
        raise notice '🧾 Creating bill for sale: %', new.sale_id;
        
        if exists(
            select 1 from pos_module.bill
            where sale_id = new.sale_id
        ) then
            raise notice '⚠️  Bill already exists for sale: %', new.sale_id;
            return new;
        end if;
        
        _tenant_customer_id := (
            select tenant_customer_id 
            from pos_module.customer_payment 
            where sale_id = new.sale_id 
            limit 1
        );
        
        select tenant_id into _tenant_id
        from core.tenant_customer
        where tenant_customer_id = _tenant_customer_id;
        
        _currency_id := new.currency_id;
        _subtotal := new.subtotal_amount;  
        _tax := new.tax_amount;            
        _total := new.total_amount;        
        
        raise notice '   Customer: %', _tenant_customer_id;
        raise notice '   Tenant: %', _tenant_id;
        raise notice '   Subtotal: $%', _subtotal;
        raise notice '   Tax: $%', _tax;
        raise notice '   Total: $%', _total;

        insert into pos_module.bill (
            sale_id,              
            tenant_customer_id,
            currency_id,
            subtotal_amount,
            tax_amount,
            total_amount
        ) values (
            new.sale_id,         
            _tenant_customer_id,
            _currency_id,
            _subtotal,
            _tax,
            _total
        ) returning bill_id into _bill_id;
        
        raise notice '   ✅ Bill created: %', _bill_id;
        
        select array_agg(customer_payment_id) into _payment_ids
        from pos_module.customer_payment
        where sale_id = new.sale_id
        and verified = true;
        
        insert into pos_module.bill_payment(bill_id, customer_payment_id, payment_amount)
        select 
            _bill_id,
            customer_payment_id,
            payment_amount
        from pos_module.customer_payment
        where customer_payment_id = any(_payment_ids);
        
        raise notice '   ✅ % payment(s) linked to bill', array_length(_payment_ids, 1);
        raise notice '';
        raise notice '🎉 Bill creation completed successfully';
        raise notice '   Bill ID: %', _bill_id;
        raise notice '   Sale ID: %', new.sale_id;

        return new;
        
    exception
        when others then
            raise notice '❌ Error creating bill: %', sqlerrm;
            return new;
end;
$$ language plpgsql;

drop trigger if exists on_sale_completed_create_bill on pos_module.sale;
create trigger on_sale_completed_create_bill
    after update of is_completed on pos_module.sale
    for each row
    when (old.is_completed is false and new.is_completed is true)
    execute function create_bill();

create or replace function update_on_return()
returns trigger as $$
declare
    _sale_item_record record;
    _bill_id uuid;
    _sale_id uuid;
    _total_returned numeric(10,2) := 0;
    _original_subtotal numeric(10,2);
    _original_tax numeric(10,2);
    _original_total numeric(10,2);
    _new_subtotal numeric(10,2);
    _new_tax numeric(10,2);
    _new_total numeric(10,2);
    _tax_rate numeric(5,2);
    _quantity_remaining integer;
    _sale_subtotal_after numeric(10,2);
    _region_name varchar;
    _tenant_id uuid;
begin
    select 
        si.sale_item_id,
        si.sale_id,
        si.quantity,
        si.unit_price,
        si.total_price,
        si.product_id,
        si.tenant_id
    into _sale_item_record
    from pos_module.sale_item si
    where si.sale_item_id = new.sale_item_id;

    if not found then
        raise exception 'Sale item not found: %', new.sale_item_id;
    end if;

    _sale_id := _sale_item_record.sale_id;

    -- get bill for sale
    select bill_id into _bill_id from pos_module.bill where sale_id = _sale_id limit 1;
    if _bill_id is null then
        raise exception 'Bill not found for sale: %', _sale_id;
    end if;

    raise notice '📄 Bill ID: %', _bill_id;
    raise notice '📦 Original sale item: qty=% unit=$% total=$%', _sale_item_record.quantity, _sale_item_record.unit_price, _sale_item_record.total_price;

    if new.quantity > _sale_item_record.quantity then
        raise exception 'Cannot return more items than purchased. Purchased: %, Attempting to return: %',
            _sale_item_record.quantity, new.quantity;
    end if;

    _quantity_remaining := _sale_item_record.quantity - new.quantity;
    raise notice '🔢 Return quantity: %  Remaining qty: %', new.quantity, _quantity_remaining;

    -- Update or remove sale_item to reconcile sale
    if _quantity_remaining = 0 then
        delete from pos_module.sale_item where sale_item_id = _sale_item_record.sale_item_id;
        raise notice '🗑️  Sale item removed (quantity = 0)';
    else
        update pos_module.sale_item
        set quantity = _quantity_remaining,
            total_price = _quantity_remaining * unit_price,
            updated_at = current_timestamp
        where sale_item_id = _sale_item_record.sale_item_id;
        raise notice '✏️  Sale item quantity updated from % to %', _sale_item_record.quantity, _quantity_remaining;
    end if;

    -- Update bill totals
    select subtotal_amount, tax_amount, total_amount into _original_subtotal, _original_tax, _original_total
    from pos_module.bill where bill_id = _bill_id;

    _total_returned := new.quantity * new.unit_price;
    raise notice '💰 Amount returned (line): $%', _total_returned;

    _new_subtotal := _original_subtotal - _total_returned;
    if _new_subtotal < 0 then _new_subtotal := 0; end if;

    -- determine tax rate by tenant -> region (fallback to 0 if not found)
    select t.tenant_id, r.region_name into _tenant_id, _region_name
    from core.tenant t
    join core.branch b on b.tenant_id = t.tenant_id
    join pos_module.sale s on s.branch_id = b.branch_id
    join core.region r on r.region_id = t.region_id
    where s.sale_id = _sale_id
    limit 1;

    select rate_percentage into _tax_rate from core.tax_rate where region = coalesce(_region_name, 'US Federal') limit 1;
    if _tax_rate is null then _tax_rate := 0; end if;

    _new_tax := round(_new_subtotal * (_tax_rate / 100), 2);
    _new_total := round(_new_subtotal + _new_tax, 2);

    update pos_module.bill
    set subtotal_amount = _new_subtotal,
        tax_amount = _new_tax,
        total_amount = _new_total,
        updated_at = current_timestamp
    where bill_id = _bill_id;

    raise notice '📊 Bill updated: subtotal $% tax $% total $%', _new_subtotal, _new_tax, _new_total;

    select coalesce(sum(si.total_price),0) into _sale_subtotal_after from pos_module.sale_item si where si.sale_id = _sale_id;
    _new_tax := round(_sale_subtotal_after * (_tax_rate / 100), 2);
    _new_total := round(_sale_subtotal_after + _new_tax, 2);

    update pos_module.sale
    set subtotal_amount = _sale_subtotal_after,
        tax_amount = _new_tax,
        total_amount = _new_total,
        updated_at = current_timestamp
    where sale_id = _sale_id;

    raise notice '🔁 Sale updated: subtotal $% tax $% total $%', _sale_subtotal_after, _new_tax, _new_total;

    return new;
end;
$$ language plpgsql;

drop trigger if exists update_on_return_trigger on pos_module.return_product;
create trigger update_on_return_trigger
    after insert on pos_module.return_product
    for each row
    execute function update_on_return();


create or replace function auto_toggle_promotions()
returns table(
    action text,
    promotion_id uuid,
    promo_code varchar(50),
    promo_name varchar(100)
) as $$
declare
    _now timestamp := current_timestamp;
    _promo record;
begin
    raise notice '🔄 AUTO-TOGGLE PROMOTIONS';
    raise notice 'Timestamp: %', _now;
    raise notice '';
    
    for _promo in
        select p.promotion_id, p.promo_code, p.promo_name, p.promo_start_date
        from pos_module.promotion p
        where p.is_active = false
        and p.promo_start_date <= _now
        and p.promo_end_date > _now
    loop
        update pos_module.promotion
        set is_active = true,
            updated_at = _now
        where promotion_id = _promo.promotion_id;
        
        raise notice '✅ ACTIVATED: % - % (started: %)', 
            _promo.promo_code, _promo.promo_name, _promo.promo_start_date;
        
        action := 'ACTIVATED';
        promotion_id := _promo.promotion_id;
        promo_code := _promo.promo_code;
        promo_name := _promo.promo_name;
        return next;
    end loop;
    
    for _promo in
        select p.promotion_id, p.promo_code, p.promo_name, p.promo_end_date
        from pos_module.promotion p
        where p.is_active = true
        and p.promo_end_date <= _now
    loop
        update pos_module.promotion
        set is_active = false,
            updated_at = _now
        where promotion_id = _promo.promotion_id;
        
        raise notice '❌ DEACTIVATED: % - % (ended: %)', 
            _promo.promo_code, _promo.promo_name, _promo.promo_end_date;
        
        action := 'DEACTIVATED';
        promotion_id := _promo.promotion_id;
        promo_code := _promo.promo_code;
        promo_name := _promo.promo_name;
        return next;
    end loop;
    
    raise notice '';
    raise notice '✅ AUTO-TOGGLE COMPLETED';
end;
$$ language plpgsql;

    create or replace function calculate_percentage_discount(
    _promotion_id uuid,
    _quantity integer,
    _unit_price numeric(10,2),
    _total_purchase_amount numeric(10,2)
) returns pos_module.discount_result as $$
declare
    _rule record;
    _total_price numeric(10,2);
    _discount numeric(10,2);
    _discount_pct numeric(5,2);
    _result pos_module.discount_result;
begin
    _total_price := _quantity * _unit_price;
    
    select * into _rule
    from pos_module.promotion_rule
    where promotion_id = _promotion_id
    and discount_percentage is not null
    limit 1;
    
    if not found then
        raise notice '   ❌ No percentage discount rule found';
        _result.success := false;
        return _result;
    end if;
    
    if _rule.min_purchase_amount is not null then
        if _total_purchase_amount is null or _total_purchase_amount < _rule.min_purchase_amount then
            raise notice '   ⚠️  Minimum purchase amount not met: $% required, $% provided',
                _rule.min_purchase_amount, coalesce(_total_purchase_amount, 0);
            _result.success := false;
            return _result;
        end if;
    end if;
    
    _discount := _total_price * (_rule.discount_percentage / 100);
    _discount_pct := _rule.discount_percentage;
    
    raise notice '   ✅ Applied: % percent discount = $%', _rule.discount_percentage, _discount;
    
    _result.discount_amount := round(_discount, 2);
    _result.discount_percentage := round(_discount_pct, 2);
    _result.rule_description := format('%s%% off', _rule.discount_percentage);
    _result.success := true;
    
    return _result;
end;
$$ language plpgsql;

create or replace function calculate_fixed_discount(
    _promotion_id uuid,
    _quantity integer,
    _unit_price numeric(10,2),
    _total_purchase_amount numeric(10,2)
) returns pos_module.discount_result as $$
declare
    _rule record;
    _total_price numeric(10,2);
    _discount numeric(10,2);
    _discount_pct numeric(5,2);
    _result pos_module.discount_result;
begin
    _total_price := _quantity * _unit_price;
    
    select * into _rule
    from pos_module.promotion_rule
    where promotion_id = _promotion_id
    and discount_amount is not null
    limit 1;
    
    if not found then
        raise notice '   ❌ No fixed discount rule found';
        _result.success := false;
        return _result;
    end if;
    
    if _rule.min_purchase_amount is not null then
        if _total_purchase_amount is null or _total_purchase_amount < _rule.min_purchase_amount then
            raise notice '   ⚠️  Minimum purchase amount not met: $% required',
                _rule.min_purchase_amount;
            _result.success := false;
            return _result;
        end if;
    end if;
    
    _discount := least(_rule.discount_amount, _total_price);
    _discount_pct := (_discount / _total_price) * 100;
    
    raise notice '   ✅ Applied: $% discount (max: $%)', _discount, _rule.discount_amount;
    
    _result.discount_amount := round(_discount, 2);
    _result.discount_percentage := round(_discount_pct, 2);
    _result.rule_description := format('$%s off', _rule.discount_amount);
    _result.success := true;
    
    return _result;
end;
$$ language plpgsql;

create or replace function calculate_buy_x_get_y_discount(
    _promotion_id uuid,
    _quantity integer,
    _unit_price numeric(10,2),
    _total_purchase_amount numeric(10,2)
) returns pos_module.discount_result as $$
declare
    _rule record;
    _total_price numeric(10,2);
    _discount numeric(10,2);
    _discount_pct numeric(5,2);
    _free_items integer;
    _result pos_module.discount_result;
begin
    _total_price := _quantity * _unit_price;
    
    select * into _rule
    from pos_module.promotion_rule
    where promotion_id = _promotion_id
    and buy_quantity is not null
    and get_quantity is not null
    limit 1;
    
    if not found then
        raise notice '   ❌ No buy_x_get_y rule found';
        _result.success := false;
        return _result;
    end if;
    
    if _quantity < _rule.buy_quantity then
        raise notice '   ⚠️  Minimum quantity not met: % required, % provided',
            _rule.buy_quantity, _quantity;
        _result.success := false;
        return _result;
    end if;
    
    _free_items := (_quantity / _rule.buy_quantity) * _rule.get_quantity;
    
    _discount := _free_items * _unit_price * (_rule.get_discount_percentage / 100);
    _discount_pct := (_discount / _total_price) * 100;
    
    raise notice '   ✅ Applied: Buy % get % = % free items × $% = $%',
        _rule.buy_quantity, _rule.get_quantity, _free_items, _unit_price, _discount;
    
    _result.discount_amount := round(_discount, 2);
    _result.discount_percentage := round(_discount_pct, 2);
    _result.rule_description := format('Buy %s get %s (%s%% off)',
        _rule.buy_quantity,
        _rule.get_quantity,
        _rule.get_discount_percentage);
    _result.success := true;
    
    return _result;
end;
$$ language plpgsql;

create or replace function calculate_volume_discount(
    _promotion_id uuid,
    _quantity integer,
    _unit_price numeric(10,2),
    _total_purchase_amount numeric(10,2)
) returns pos_module.discount_result as $$
declare
    _rule record;
    _total_price numeric(10,2);
    _discount numeric(10,2);
    _discount_pct numeric(5,2);
    _result pos_module.discount_result;
begin
    _total_price := _quantity * _unit_price;
    
    select * into _rule
    from pos_module.promotion_rule
    where promotion_id = _promotion_id
    and min_quantity is not null
    and discount_percentage is not null
    and (min_quantity <= _quantity)
    and (max_quantity is null or max_quantity >= _quantity)
    order by min_quantity desc
    limit 1;
    
    if not found then
        raise notice '   ⚠️  Quantity % does not match any volume tier', _quantity;
        _result.success := false;
        return _result;
    end if;
    
    _discount := _total_price * (_rule.discount_percentage / 100);
    _discount_pct := _rule.discount_percentage;
    
    raise notice '   ✅ Applied: Volume discount % percent (min: %, max: %) = $%',
        _rule.discount_percentage, _rule.min_quantity, 
        coalesce(_rule.max_quantity::text, 'unlimited'), _discount;
    
    _result.discount_amount := round(_discount, 2);
    _result.discount_percentage := round(_discount_pct, 2);
    _result.rule_description := format('%s%% off for %s+ items',
        _rule.discount_percentage,
        _rule.min_quantity);
    _result.success := true;
    
    return _result;
end;
$$ language plpgsql;

create or replace function calculate_tiered_pricing_discount(
    _promotion_id uuid,
    _quantity integer,
    _unit_price numeric(10,2),
    _total_purchase_amount numeric(10,2)
) returns pos_module.discount_result as $$
declare
    _rule record;
    _total_price numeric(10,2);
    _discount numeric(10,2);
    _discount_pct numeric(5,2);
    _result pos_module.discount_result;
begin
    _total_price := _quantity * _unit_price;
    
    select * into _rule
    from pos_module.promotion_rule
    where promotion_id = _promotion_id
    and tier_level is not null
    and tier_min_quantity <= _quantity
    and (tier_max_quantity is null or tier_max_quantity >= _quantity)
    order by tier_level desc
    limit 1;
    
    if not found then
        raise notice '   ⚠️  Quantity % does not match any tier', _quantity;
        _result.success := false;
        return _result;
    end if;
    
    if _rule.tier_price is not null then
        _discount := (_unit_price - _rule.tier_price) * _quantity;
        _discount_pct := ((_unit_price - _rule.tier_price) / _unit_price) * 100;
        
        raise notice '   ✅ Applied: Tier % - Fixed price $% per unit = $% discount',
            _rule.tier_level, _rule.tier_price, _discount;
        
        _result.rule_description := format('Tier %s: $%s per unit',
            _rule.tier_level,
            _rule.tier_price);
            
    elsif _rule.tier_discount_percentage is not null then
        _discount := _total_price * (_rule.tier_discount_percentage / 100);
        _discount_pct := _rule.tier_discount_percentage;
        
        raise notice '   ✅ Applied: Tier % - % percent discount = $%',
            _rule.tier_level, _rule.tier_discount_percentage, _discount;
        
        _result.rule_description := format('Tier %s: %s%% off',
            _rule.tier_level,
            _rule.tier_discount_percentage);
    else
        raise notice '   ❌ Tier found but no price or discount defined';
        _result.success := false;
        return _result;
    end if;
    
    _result.discount_amount := round(_discount, 2);
    _result.discount_percentage := round(_discount_pct, 2);
    _result.success := true;
    
    return _result;
end;
$$ language plpgsql;

create or replace function calculate_combo_discount(
    _promotion_id uuid,
    _quantity integer,
    _unit_price numeric(10,2),
    _total_purchase_amount numeric(10,2)
) returns pos_module.discount_result as $$
declare
    _result pos_module.discount_result;
begin
    raise notice '   ℹ️  Combo discounts require multiple products and should be calculated at cart level';
    _result.success := false;
    return _result;
end;
$$ language plpgsql;

create or replace function calculate_promotion_discount(
    _promotion_id uuid,
    _tenant_id uuid,
    _product_id uuid,
    _quantity integer,
    _unit_price numeric(10,2),
    _total_purchase_amount numeric(10,2) default null
) returns table(
    discount_amount numeric(10,2),
    discount_percentage numeric(5,2),
    promotion_type varchar(50),
    rule_applied text
) as $$
declare
    _promo record;
    _type_name varchar(50);
    _result pos_module.discount_result;
begin
    select 
        p.promotion_id,
        p.promotion_code,
        p.promotion_name,
        p.is_active,
        p.promotion_start_date,
        p.promotion_end_date,
        pt.type_name
    into _promo
    from pos_module.promotion p
    join pos_module.promotion_type pt on p.promotion_type_id = pt.promotion_type_id
    where p.promotion_id = _promotion_id
    and p.tenant_id = _tenant_id;
    
    if not found then
        raise notice '❌ Promotion not found: %', _promotion_id;
        return;
    end if;
    
    if not _promo.is_active then
        raise notice '❌ Promotion % is not active', _promo.promotion_code;
        return;
    end if;
    
    if current_timestamp not between _promo.promotion_start_date and _promo.promotion_end_date then
        raise notice '❌ Promotion % is not in valid date range', _promo.promotion_code;
        return;
    end if;
    
    _type_name := _promo.type_name;
    
    raise notice '🎯 Calculating discount for promotion: % (%)', _promo.promotion_name, _type_name;
    raise notice '   Product: %, Quantity: %, Unit Price: $%', _product_id, _quantity, _unit_price;
    
    case _type_name
        when 'percentage_discount' then
            _result := pos_module.calculate_percentage_discount(
                _promotion_id, _quantity, _unit_price, _total_purchase_amount
            );
            
        when 'fixed_amount_discount' then
            _result := pos_module.calculate_fixed_discount(
                _promotion_id, _quantity, _unit_price, _total_purchase_amount
            );
            
        when 'buy_x_get_y' then
            _result := pos_module.calculate_buy_x_get_y_discount(
                _promotion_id, _quantity, _unit_price, _total_purchase_amount
            );
            
        when 'volume_discount' then
            _result := pos_module.calculate_volume_discount(
                _promotion_id, _quantity, _unit_price, _total_purchase_amount
            );
            
        when 'tiered_pricing' then
            _result := pos_module.calculate_tiered_pricing_discount(
                _promotion_id, _quantity, _unit_price, _total_purchase_amount
            );
            
        when 'combo' then
            _result := pos_module.calculate_combo_discount(
                _promotion_id, _quantity, _unit_price, _total_purchase_amount
            );
            
        when 'free_shipping' then
            raise notice '   ℹ️  Free shipping discount (not implemented for products)';
            return;
            
        else
            raise notice '   ❌ Unknown promotion type: %', _type_name;
            return;
    end case;
    
    if _result.success then
        return query select 
            _result.discount_amount,
            _result.discount_percentage,
            _type_name::varchar(50),
            _result.rule_description;
    end if;

    return;
    
end;
$$ language plpgsql;

create or replace procedure open_close_cash_register_session(
    _cash_register_id uuid,
    _action varchar(10), 
    _amount numeric(10,2)
)
as $$
declare
    _session_id uuid;
    _session record;
    _rows_updated int;
begin
        if _action = 'open' then
            select cash_register_session_id into _session_id
            from pos_module.cash_register_session
            where cash_register_id = _cash_register_id
            and is_active = true
            limit 1;
            
            if _session_id is not null then
                raise exception 'Cash register % already has an open session: %', 
                    _cash_register_id, _session_id;
            end if;
            
            insert into pos_module.cash_register_session (
                cash_register_id,
                opened_at,
                opening_amount,
                is_active,
                created_at,
                updated_at
            ) values (
                _cash_register_id,
                current_timestamp,
                _amount,
                true,
                current_timestamp,
                current_timestamp
            ) returning cash_register_session_id into _session_id;
            
            raise notice '✅ Cash register % opened', _cash_register_id;
            raise notice '   Session ID: %', _session_id;
            raise notice '   Opening amount: $%', _amount;
            raise notice '   Opened at: %', current_timestamp;
            
        elsif _action = 'close' then
            update pos_module.cash_register_session
            set closed_at = current_timestamp,
                closing_amount = _amount,
                is_active = false,
                updated_at = current_timestamp
            where cash_register_id = _cash_register_id
            and is_active = true
            returning 
                cash_register_session_id,
                opening_amount,
                closing_amount,
                opened_at,
                closed_at
            into _session;
            
            get diagnostics _rows_updated = row_count;
            
            if _rows_updated = 0 then
                raise exception 'Cash register % is not open or does not exist', 
                    _cash_register_id;
            end if;
            
            raise notice '✅ Cash register % closed', _cash_register_id;
            raise notice '   Session ID: %', _session.cash_register_session_id;
            raise notice '   Opening amount: $%', _session.opening_amount;
            raise notice '   Closing amount: $%', _session.closing_amount;
            raise notice '   Difference: $%', (_session.closing_amount - _session.opening_amount);
            raise notice '   Duration: %', (_session.closed_at - _session.opened_at);
            
        else
            raise exception 'Invalid action: %. Use "open" or "close"', _action;
        end if;
        
    exception
        when others then
            raise notice '❌ Error in cash register session: %', sqlerrm;
            raise;
end;
$$ language plpgsql;

create or replace function calculate_purchase_score(
_tenant_id uuid,
_tenant_customer_id uuid,
_purchase_amount numeric(10,2)
) returns integer as $$
declare
    _minimum_purchase numeric(10,2);
    _points_per_dollar numeric(5,2);
    _score integer;
    _program_exists boolean;
begin
        select exists(
            select 1 
            from pos_module.loyalty_program 
            where tenant_id = _tenant_id 
            and is_active = true
        ) into _program_exists;
        
        if not _program_exists then
            raise notice '⚠️  No active loyalty program for tenant %', _tenant_id;
            return 0;
        end if;
        
        select 
            minimum_purchase_for_points, 
            points_per_dollar 
        into 
            _minimum_purchase, 
            _points_per_dollar 
        from pos_module.loyalty_program 
        where tenant_id = _tenant_id
        and is_active = true
        limit 1;
        
        _score := floor(_purchase_amount * _points_per_dollar);
        
        raise notice '✅ Points: $% × % = % pts',
            _purchase_amount, _points_per_dollar, _score;
        
        return _score;
        
    exception
        when others then
            raise notice '❌ Error calculating points: %', sqlerrm;
            return 0;
end;
$$ language plpgsql;

create or replace function award_points()
returns trigger as $$
declare
    _tenant_id uuid;
    _tenant_customer_id uuid;
    _bill_id uuid;
    _points_earned integer;
    _current_balance integer;
    _cash_payments_total numeric(10,2);
    _points_already_awarded boolean;
begin
        _bill_id := new.bill_id;
        
        select exists(
            select 1 
            from pos_module.score_transaction 
            where bill_id = _bill_id 
            and transaction_type_id = 1  
        ) into _points_already_awarded;
        
        if _points_already_awarded then
            raise notice '   ℹ️  Points already awarded for bill %', _bill_id;
            return new;
        end if;
        
        select tenant_customer_id into _tenant_customer_id
        from pos_module.bill
        where bill_id = _bill_id;
        
        if _tenant_customer_id is null then
            raise notice '   ⚠️  No customer found for bill %', _bill_id;
            return new;
        end if;
        
        select tenant_id into _tenant_id
        from core.tenant_customer
        where tenant_customer_id = _tenant_customer_id;
        
        if _tenant_id is null then
            raise notice '   ⚠️  Tenant not found for customer %', _tenant_customer_id;
            return new;
        end if;
        
        select coalesce(sum(cp.payment_amount), 0) into _cash_payments_total
        from pos_module.bill_payment bp
        join pos_module.customer_payment cp on bp.customer_payment_id = cp.customer_payment_id
        where bp.bill_id = _bill_id
        and cp.is_points_redemption = false;
        
        raise notice '💵 Cash/card payments total: $%', _cash_payments_total;
        
        _points_earned := pos_module.calculate_purchase_score(
            _tenant_id,
            _tenant_customer_id,
            _cash_payments_total
        );
        
        if _points_earned <= 0 then
            raise notice '   ℹ️  No points earned for this purchase (Bill: %)', _bill_id;
            return new;
        end if;
        
        insert into pos_module.tenant_customer_score(
            tenant_id,
            tenant_customer_id,
            score,
            lifetime_score,
            last_earned_at
        ) values (
            _tenant_id,
            _tenant_customer_id,
            _points_earned,
            _points_earned,
            current_timestamp
        )
        on conflict (tenant_customer_id, tenant_id)
        do update set
            score = tenant_customer_score.score + _points_earned,
            lifetime_score = tenant_customer_score.lifetime_score + _points_earned,
            last_earned_at = current_timestamp
        returning score into _current_balance;
        
        insert into pos_module.score_transaction(
            tenant_id,
            tenant_customer_id,
            transaction_type_id,
            points,
            bill_id,
            created_at
        ) values (
            _tenant_id,
            _tenant_customer_id,
            1,  
            _points_earned,
            _bill_id,
            current_timestamp
        );
        
        raise notice '   ✅ Awarded % points to customer %', _points_earned, _tenant_customer_id;
        raise notice '   Bill: %', _bill_id;
        raise notice '   New balance: % points', _current_balance;
        
        return new;
        
    exception
        when others then
            raise notice '   ❌ Error awarding points: %', sqlerrm;
            return new;
end;
$$ language plpgsql;

drop trigger if exists on_purchase_billed on pos_module.bill_payment;
create trigger on_purchase_billed
    after insert on pos_module.bill_payment
    for each row
    execute function pos_module.award_points();

create or replace function redeem_points(
_tenant_customer_id uuid,
_points_to_redeem integer
) returns table(
    cash_value numeric(10,2),
    points_available integer,
    success boolean,
    message text
) as $$
declare
    _points_per_currency_unit numeric(10,2); 
    _tenant_id uuid;
    _current_points integer;
    _cash_equivalent numeric(10,2);
begin   
    select tenant_id into _tenant_id
    from core.tenant_customer
    where tenant_customer_id = _tenant_customer_id;

    if _tenant_id is null then
        return query select 
            0.00::numeric(10,2),
            0,
            false,
            'Customer not found'::text;
        return;
    end if; 

    select score into _current_points
    from pos_module.tenant_customer_score
    where tenant_customer_id = _tenant_customer_id
    and tenant_id = _tenant_id;

    select points_per_currency_unit into _points_per_currency_unit
    from pos_module.loyalty_program
    where tenant_id = _tenant_id
    and is_active = true
    limit 1;

    if _points_per_currency_unit is null then
        return query select 
            0.00::numeric(10,2),
            coalesce(_current_points, 0),
            false,
            'No active loyalty program found'::text;
        return;
    end if;

    if _current_points is null or _current_points = 0 or _current_points < _points_to_redeem then
        return query select 
            0.00::numeric(10,2),
            coalesce(_current_points, 0),
            false,
            format('Insufficient points. Available: %s, Required: %s', 
                coalesce(_current_points, 0), _points_to_redeem)::text;
        return;
    end if;

    _cash_equivalent := _points_to_redeem / _points_per_currency_unit;

    update pos_module.tenant_customer_score
    set score = score - _points_to_redeem,
        score_redeemed = score_redeemed + _points_to_redeem,
        last_redeemed_at = current_timestamp,
        updated_at = current_timestamp
    where tenant_customer_id = _tenant_customer_id
    and tenant_id = _tenant_id;

    insert into pos_module.score_transaction(
        tenant_id,
        tenant_customer_id,
        transaction_type_id,
        points,
        created_at
    ) values (
        _tenant_id,
        _tenant_customer_id,
        2,  
        -_points_to_redeem,  
        current_timestamp
    );

    return query select 
        round(_cash_equivalent, 2)::numeric(10,2),
        _current_points - _points_to_redeem,
        true,
        format('Redeemed %s points at rate %s pts/$1 = $%s', 
            _points_to_redeem, 
            _points_per_currency_unit, 
            round(_cash_equivalent, 2))::text;
    exception
        when others then
            raise notice '❌ Error redeeming points: %', sqlerrm;
            return query select 
                0.00::numeric(10,2),
                coalesce(_current_points, 0),
                false,
                sqlerrm::text;
end;
$$ language plpgsql;

create or replace procedure verify_customer_payment(_payment_id uuid)
as $$
declare
    _exists boolean;
    _already_verified boolean;
    _tenant_customer_id uuid;
    _sale_id uuid;
    _payment_amount numeric(10,2);
    _payment_method varchar(50);
    _is_points_redemption boolean;
    _points_redeemed integer;
    _redeem_result record;
    _sale_completed boolean;
begin
    select exists(
        select 1 
        from pos_module.customer_payment 
        where customer_payment_id = _payment_id
    ) into _exists;
    
    if not _exists then
        raise exception 'Payment not found: %', _payment_id;
    end if;

    select 
        coalesce(verified, false), 
        tenant_customer_id,
        sale_id,
        payment_amount,
        is_points_redemption,
        points_redeemed
    into 
        _already_verified, 
        _tenant_customer_id,
        _sale_id,
        _payment_amount,
        _is_points_redemption,
        _points_redeemed
    from pos_module.customer_payment 
    where customer_payment_id = _payment_id;
    
    if _already_verified then
        raise notice '⚠️  Payment % is already verified', _payment_id;
        return;
    end if;
    
    if _sale_id is null then
        raise exception 'Payment % has no associated sale', _payment_id;
    end if;
    
    raise notice '💳 Verifying payment: %', _payment_id;
    raise notice '   Sale: %', _sale_id;
    raise notice '   Customer: %', _tenant_customer_id;
    raise notice '   Amount: $%', _payment_amount;
    
    select name into _payment_method
    from core.payment_method pm
    join pos_module.customer_payment cp on pm.payment_method_id = cp.payment_method_id
    where cp.customer_payment_id = _payment_id;
    
    raise notice '   Method: %', _payment_method;
    raise notice '';
    
    if _is_points_redemption then
        raise notice '🎁 Processing points redemption...';
        raise notice '   Points to redeem: %', _points_redeemed;
        
        select * into _redeem_result
        from pos_module.redeem_points(
            _tenant_customer_id,
            _points_redeemed
        );
        
        if not _redeem_result.success then
            raise exception 'Points redemption failed: %', _redeem_result.message;
        end if;
        
        if abs(_redeem_result.cash_value - _payment_amount) > 0.01 then
            raise exception 'Points cash value ($%) does not match payment amount ($%)',
                _redeem_result.cash_value, _payment_amount;
        end if;
        
        raise notice '   ✅ Redeemed % points = $%', _points_redeemed, _payment_amount;
        raise notice '   %', _redeem_result.message;
        raise notice '   Remaining points: %', _redeem_result.points_available;
        raise notice '';
    end if;

    update pos_module.customer_payment
    set verified = true,
        updated_at = current_timestamp
    where customer_payment_id = _payment_id;
    
    raise notice '✅ Payment verified successfully';
    raise notice '';
    
    raise notice '🔍 Checking if sale is fully paid...';
    _sale_completed := pos_module.check_sale_payment_completion(_sale_id);
    
    if _sale_completed then
        raise notice '';
        raise notice '🎉 Sale % is COMPLETED - Trigger will create bill', _sale_id;
    else
        raise notice '';
        raise notice '⏳ Sale % is PENDING - Waiting for more payments', _sale_id;
    end if;
    
    exception
        when others then
            raise notice '❌ Payment verification failed: %', sqlerrm;
            raise;
end;
$$ language plpgsql;      

-- ==========================
-- UPDATE TIMESTAMP TRIGGERS
-- ==========================

drop trigger if exists update_customer_payment_timestamp on pos_module.customer_payment;
create trigger update_customer_payment_timestamp before update on pos_module.customer_payment
for each row execute function core.update_timestamp();

drop trigger if exists update_bill_timestamp on pos_module.bill;
create trigger update_bill_timestamp before update on pos_module.bill
for each row execute function core.update_timestamp();

drop trigger if exists update_return_transaction_timestamp on pos_module.return_transaction;
create trigger update_return_transaction_timestamp before update on pos_module.return_transaction
for each row execute function core.update_timestamp();

drop trigger if exists update_return_product_timestamp on pos_module.return_product;
create trigger update_return_product_timestamp before update on pos_module.return_product
for each row execute function core.update_timestamp();

drop trigger if exists update_promotion_timestamp on pos_module.promotion;
create trigger update_promotion_timestamp before update on pos_module.promotion
for each row execute function core.update_timestamp();

drop trigger if exists update_promotion_rule_timestamp on pos_module.promotion_rule;
create trigger update_promotion_rule_timestamp before update on pos_module.promotion_rule
for each row execute function core.update_timestamp();

drop trigger if exists update_cash_register_session_timestamp on pos_module.cash_register_session;
create trigger update_cash_register_session_timestamp before update on pos_module.cash_register_session
for each row execute function core.update_timestamp();

drop trigger if exists update_cash_register_sale_timestamp on pos_module.cash_register_sale;
create trigger update_cash_register_sale_timestamp before update on pos_module.cash_register_sale
for each row execute function core.update_timestamp();

drop trigger if exists update_tenant_customer_score_timestamp on pos_module.tenant_customer_score;
create trigger update_tenant_customer_score_timestamp before update on pos_module.tenant_customer_score
for each row execute function core.update_timestamp();

drop trigger if exists update_score_transaction_timestamp on pos_module.score_transaction;
create trigger update_score_transaction_timestamp before update on pos_module.score_transaction
for each row execute function core.update_timestamp();

drop trigger if exists update_bill_payment_timestamp on pos_module.bill_payment;
create trigger update_bill_payment_timestamp before update on pos_module.bill_payment
for each row execute function core.update_timestamp();

drop trigger if exists update_sale_timestamp on pos_module.sale;
create trigger update_sale_timestamp before update on pos_module.sale
for each row execute function core.update_timestamp();

drop trigger if exists update_sale_item_timestamp on pos_module.sale_item;
create trigger update_sale_item_timestamp before update on pos_module.sale_item
for each row execute function core.update_timestamp();


