set search_path = pos_schema;

CREATE OR REPLACE FUNCTION check_sale_payment_completion(_sale_id uuid)
returns BOOLEAN as $$
declare
    _sale_total numeric(10,2);
    _payments_total numeric(10,2);
    _is_completed BOOLEAN;
    _pending_payments int;
BEGIN
        select total_amount, is_completed 
        into _sale_total, _is_completed
        from pos_schema.sale
        where sale_id = _sale_id;
        
        if _sale_total is null then
            raise exception 'Sale not found: %', _sale_id;
        end if;
        
        if _is_completed then
            return true;
        end if;
        
        select count(*) into _pending_payments
        from pos_schema.customer_payment
        where sale_id = _sale_id
        and verified = false;
        
        if _pending_payments > 0 then
            return false;
        end if;
        
        select coalesce(sum(payment_amount), 0) into _payments_total
        from pos_schema.customer_payment
        where sale_id = _sale_id
        and verified = true;
        
        raise notice '   Sale total (with tax): $%', _sale_total;
        raise notice '   Payments total: $%', _payments_total;
        raise notice '   Difference: $%', (_sale_total - _payments_total);
        
        if abs(_payments_total - _sale_total) <= 0.01 then
            update pos_schema.sale
            set is_completed = true,
                updated_at = current_timestamp
            where sale_id = _sale_id;
            
            raise notice '   Sale % marked as COMPLETED', _sale_id;
            return true;
            
        elsif _payments_total > _sale_total then
            raise warning 'Overpayment detected: Expected $%, Paid $%',
                _sale_total, _payments_total;
            return false;
            
        else
            raise notice '   Sale % still pending (shortage: $%)', 
                _sale_id, (_sale_total - _payments_total);
            return false;
        end if;
        
    exception
        when others then
            raise notice '   Error checking sale completion: %', sqlerrm;
            return false;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION link_sale_to_session()
returns trigger as $$
declare 
    _session_id uuid;
BEGIN
    select crs.cash_register_session_id into _session_id
    from pos_schema.cash_register_session crs
    join pos_schema.cash_register cr on crs.cash_register_id = cr.cash_register_id
    where cr.branch_id = new.branch_id
    and crs.is_active = true
    limit 1;
    
    if _session_id is not null then
        INSERT INTO pos_schema.cash_register_sale(
            cash_register_session_id,
            sale_id,
            transaction_time
        ) VALUES (
            _session_id,
            new.sale_id,
            current_timestamp
        )
        on conflict (sale_id) DO nothing;
        
        raise notice 'Sale % linked to session %', new.sale_id, _session_id;
    else
        raise warning 'No active cash register session for branch %', new.branch_id;
    end if;
    
    return new;
end;
$$ language plpgsql;

drop trigger if exists on_sale_completed_link_sale_to_session on pos_schema.sale;
create trigger on_sale_completed_link_sale_to_session
    after update of is_completed on pos_schema.sale
    for each row
    when (old.is_completed is false and new.is_completed is true)
    execute function link_sale_to_session();

CREATE OR REPLACE FUNCTION calculate_digital_sale_invoice_total()
returns trigger as $$
BEGIN
    new.total_amount := new.subtotal_amount + new.tax_amount;
    return new;
end;
$$ language plpgsql;

drop trigger if exists calculate_digital_sale_invoice_total_trigger on pos_schema.digital_sale_invoice;
create trigger calculate_digital_sale_invoice_total_trigger
    before insert or update on pos_schema.digital_sale_invoice
    for each row
    execute function calculate_digital_sale_invoice_total();

CREATE OR REPLACE FUNCTION calculate_total_price()
returns trigger as $$
BEGIN
    new.total_price := new.quantity * new.unit_price;
    return new;
end;
$$ language plpgsql;

drop trigger if exists calculate_total_price_return_product_trigger on pos_schema.return_product;
create trigger calculate_total_price_return_product_trigger
    before insert or update on pos_schema.return_product
    for each row
    execute function calculate_total_price();

CREATE OR REPLACE FUNCTION pos_schema.get_digital_sale_invoice(_sale_id uuid)
returns table (
    digital_sale_invoice_id uuid,
    sale_id uuid,
    tenant_customer_id uuid,
    currency_id INTEGER,
    subtotal_amount numeric(10,2),
    tax_amount numeric(10,2),
    total_amount numeric(10,2),
    created_at timestamp,
    updated_at timestamp
) as $$
BEGIN
    return query
    select 
        b.digital_sale_invoice_id,
        b.sale_id,
        b.tenant_customer_id,
        b.currency_id,
        b.subtotal_amount,
        b.tax_amount,
        b.total_amount,
        b.created_at,
        b.updated_at
    from pos_schema.digital_sale_invoice b
    where b.sale_id = _sale_id;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION create_digital_sale_invoice()
returns trigger as $$
declare
    _digital_sale_invoice_id uuid;
    _tenant_customer_id uuid;
    _tenant_id uuid;
    _currency_id INTEGER;
    _subtotal numeric(10,2);
    _tax numeric(10,2);
    _total numeric(10,2);
    _payment_ids uuid[];
    _cash_register_id uuid;
    _items_count int;
BEGIN
        raise notice 'Creating digital sale invoice for sale: %', new.sale_id;
        
        if exists(
            select 1 from pos_schema.digital_sale_invoice
            where sale_id = new.sale_id
        ) then
            raise notice 'Digital sale invoice already exists for sale: %', new.sale_id;
            return new;
        end if;
        
        _tenant_customer_id := (
            select tenant_customer_id 
            from pos_schema.customer_payment 
            where sale_id = new.sale_id 
            limit 1
        );
        
        select tenant_id into _tenant_id
        from general_schema.tenant_customer
        where tenant_customer_id = _tenant_customer_id;
        
        _currency_id := new.currency_id;

        -- Resolve cash register from active session in the branch
        SELECT cr.cash_register_id INTO _cash_register_id
        FROM pos_schema.cash_register_session crs
        JOIN pos_schema.cash_register cr ON crs.cash_register_id = cr.cash_register_id
        WHERE cr.branch_id = new.branch_id
        AND crs.is_active = true
        LIMIT 1;

        -- Insert invoice with placeholder totals (will be updated from items)
        INSERT INTO pos_schema.digital_sale_invoice (
            sale_id,              
            tenant_customer_id,
            currency_id,
            subtotal_amount,
            tax_amount,
            total_amount,
            cash_register_id
        ) VALUES (
            new.sale_id,         
            _tenant_customer_id,
            _currency_id,
            0,
            0,
            0,
            _cash_register_id
        ) returning digital_sale_invoice_id into _digital_sale_invoice_id;
        
        raise notice '   Digital sale invoice created: %', _digital_sale_invoice_id;
        raise notice '   Cash Register: %', _cash_register_id;

        INSERT INTO pos_schema.digital_sale_invoice_item (
            digital_sale_invoice_id,
            sale_item_id,
            tenant_id,
            product_variant_id,
            cabys_code,
            tax_rate_id,
            description,
            quantity,
            unit_price,
            subtotal,
            tax_rate_percentage,
            tax_amount,
            total_price
        )
        SELECT
            _digital_sale_invoice_id,
            si.sale_item_id,
            si.tenant_id,
            si.product_variant_id,
            pv.cabys_code,
            p.tax_rate_id,
            COALESCE(pv.variant_name, p.product_name, 'Product'),
            si.quantity,
            si.unit_price,
            si.total_price,
            COALESCE(tr.rate_percentage, 0),
            ROUND(si.total_price * COALESCE(tr.rate_percentage, 0) / 100, 2),
            si.total_price + ROUND(si.total_price * COALESCE(tr.rate_percentage, 0) / 100, 2)
        FROM pos_schema.sale_item si
        JOIN general_schema.product_variant pv 
            ON si.tenant_id = pv.tenant_id AND si.product_variant_id = pv.product_variant_id
        LEFT JOIN general_schema.product p ON pv.cabys_code = p.cabys_code
        LEFT JOIN general_schema.tax_rate tr ON p.tax_rate_id = tr.tax_rate_id
        WHERE si.sale_id = new.sale_id;

        GET DIAGNOSTICS _items_count = ROW_COUNT;
        raise notice '   % invoice item(s) created', _items_count;

        -- Update invoice totals from items (per-item tax)
        SELECT
            COALESCE(SUM(dsii.subtotal), 0),
            COALESCE(SUM(dsii.tax_amount), 0)
        INTO _subtotal, _tax
        FROM pos_schema.digital_sale_invoice_item dsii
        WHERE dsii.digital_sale_invoice_id = _digital_sale_invoice_id;

        _total := _subtotal + _tax;

        UPDATE pos_schema.digital_sale_invoice
        SET subtotal_amount = _subtotal,
            tax_amount = _tax,
            total_amount = _total
        WHERE digital_sale_invoice_id = _digital_sale_invoice_id;

        raise notice '   Subtotal: $%', _subtotal;
        raise notice '   Tax (per-item): $%', _tax;
        raise notice '   Total: $%', _total;
        
        -- Link verified payments
        select array_agg(customer_payment_id) into _payment_ids
        from pos_schema.customer_payment
        where sale_id = new.sale_id
        and verified = true;
        
        INSERT INTO pos_schema.digital_sale_invoice_payment(digital_sale_invoice_id, customer_payment_id, payment_amount)
        select 
            _digital_sale_invoice_id,
            customer_payment_id,
            payment_amount
        from pos_schema.customer_payment
        where customer_payment_id = any(_payment_ids);
        
        raise notice '   % payment(s) linked to digital sale invoice', array_length(_payment_ids, 1);
        raise notice '';
        raise notice 'Digital sale invoice creation completed successfully';
        raise notice '   Invoice ID: %', _digital_sale_invoice_id;
        raise notice '   Sale ID: %', new.sale_id;

        return new;
        
    exception
        when others then
            raise notice 'Error creating digital sale invoice: %', sqlerrm;
            return new;
end;
$$ language plpgsql;

drop trigger if exists on_sale_completed_create_bill on pos_schema.sale;
drop trigger if exists on_sale_completed_create_digital_sale_invoice on pos_schema.sale;
create trigger on_sale_completed_create_digital_sale_invoice
    after update of is_completed on pos_schema.sale
    for each row
    when (old.is_completed is false and new.is_completed is true)
    execute function create_digital_sale_invoice();

CREATE OR REPLACE FUNCTION update_on_return()
returns trigger as $$
declare
    _sale_item_record record;
    _digital_sale_invoice_id uuid;
    _sale_id uuid;
    _total_returned numeric(10,2) := 0;
    _new_subtotal numeric(10,2);
    _new_tax numeric(10,2);
    _new_total numeric(10,2);
    _quantity_remaining INTEGER;
    _sale_subtotal_after numeric(10,2);
    _sale_tax_after numeric(10,2);
BEGIN
    select 
        si.sale_item_id,
        si.sale_id,
        si.quantity,
        si.unit_price,
        si.total_price,
        si.product_variant_id,
        si.tenant_id
    into _sale_item_record
    from pos_schema.sale_item si
    where si.sale_item_id = new.sale_item_id;

    if not found then
        raise exception 'Sale item not found: %', new.sale_item_id;
    end if;

    _sale_id := _sale_item_record.sale_id;

    -- get digital sale invoice for sale
    select digital_sale_invoice_id into _digital_sale_invoice_id from pos_schema.digital_sale_invoice where sale_id = _sale_id limit 1;
    if _digital_sale_invoice_id is null then
        raise exception 'Digital sale invoice not found for sale: %', _sale_id;
    end if;

    raise notice 'Digital Sale Invoice ID: %', _digital_sale_invoice_id;
    raise notice 'Original sale item: qty=% unit=$% total=$%', _sale_item_record.quantity, _sale_item_record.unit_price, _sale_item_record.total_price;

    if new.quantity > _sale_item_record.quantity then
        raise exception 'Cannot return more items than purchased. Purchased: %, Attempting to return: %',
            _sale_item_record.quantity, new.quantity;
    end if;

    _quantity_remaining := _sale_item_record.quantity - new.quantity;
    raise notice 'Return quantity: %  Remaining qty: %', new.quantity, _quantity_remaining;

    -- Update or remove sale_item (CASCADE deletes digital_sale_invoice_item if qty = 0)
    if _quantity_remaining = 0 then
        -- First, explicitly delete the corresponding digital_sale_invoice_item to ensure clean state
        delete from pos_schema.digital_sale_invoice_item 
        where digital_sale_invoice_id = _digital_sale_invoice_id
        and sale_item_id = _sale_item_record.sale_item_id;
        
        delete from pos_schema.sale_item where sale_item_id = _sale_item_record.sale_item_id;
        raise notice 'Sale item removed (quantity = 0)';
    else
        update pos_schema.sale_item
        set quantity = _quantity_remaining,
            total_price = _quantity_remaining * unit_price,
            updated_at = current_timestamp
        where sale_item_id = _sale_item_record.sale_item_id;
        raise notice 'Sale item quantity updated from % to %', _sale_item_record.quantity, _quantity_remaining;

        -- Update corresponding digital_sale_invoice_item with correct tax rate
        -- Resolve tax_rate the same way as create_digital_sale_invoice
        update pos_schema.digital_sale_invoice_item dii
        set quantity = _quantity_remaining,
            subtotal = _quantity_remaining * dii.unit_price,
            tax_rate_percentage = COALESCE(tr.rate_percentage, 0),
            tax_amount = ROUND((_quantity_remaining * dii.unit_price) * COALESCE(tr.rate_percentage, 0) / 100, 2),
            total_price = (_quantity_remaining * dii.unit_price)
                + ROUND((_quantity_remaining * dii.unit_price) * COALESCE(tr.rate_percentage, 0) / 100, 2),
            updated_at = current_timestamp
        from general_schema.product_variant pv
        left join general_schema.product p ON pv.cabys_code = p.cabys_code
        left join general_schema.tax_rate tr ON p.tax_rate_id = tr.tax_rate_id
        where dii.digital_sale_invoice_id = _digital_sale_invoice_id
        and dii.sale_item_id = _sale_item_record.sale_item_id
        and dii.tenant_id = pv.tenant_id
        and dii.product_variant_id = pv.product_variant_id;
    end if;

    -- Recalculate digital sale invoice totals from remaining items
    SELECT
        COALESCE(SUM(dsii.subtotal), 0),
        COALESCE(SUM(dsii.tax_amount), 0),
        COALESCE(SUM(dsii.total_price), 0)
    INTO _new_subtotal, _new_tax, _new_total
    FROM pos_schema.digital_sale_invoice_item dsii
    WHERE dsii.digital_sale_invoice_id = _digital_sale_invoice_id;

    update pos_schema.digital_sale_invoice
    set subtotal_amount = _new_subtotal,
        tax_amount = _new_tax,
        total_amount = _new_total,
        updated_at = current_timestamp
    where digital_sale_invoice_id = _digital_sale_invoice_id;

    raise notice 'Digital sale invoice updated: subtotal $% tax $% total $%', _new_subtotal, _new_tax, _new_total;

    -- Recalculate sale totals from remaining sale_items with per-item tax
    SELECT
        COALESCE(SUM(si.total_price), 0),
        COALESCE(SUM(ROUND(si.total_price * COALESCE(tr.rate_percentage, 0) / 100, 2)), 0)
    INTO _sale_subtotal_after, _sale_tax_after
    FROM pos_schema.sale_item si
    JOIN general_schema.product_variant pv
        ON si.tenant_id = pv.tenant_id AND si.product_variant_id = pv.product_variant_id
    LEFT JOIN general_schema.product p ON pv.cabys_code = p.cabys_code
    LEFT JOIN general_schema.tax_rate tr ON p.tax_rate_id = tr.tax_rate_id
    WHERE si.sale_id = _sale_id;

    _new_total := _sale_subtotal_after + _sale_tax_after;

    update pos_schema.sale
    set subtotal_amount = _sale_subtotal_after,
        tax_amount = _sale_tax_after,
        total_amount = _new_total,
        updated_at = current_timestamp
    where sale_id = _sale_id;

    raise notice 'Sale updated: subtotal $% tax $% total $%', _sale_subtotal_after, _sale_tax_after, _new_total;

    return new;
end;
$$ language plpgsql;

drop trigger if exists update_on_return_trigger on pos_schema.return_product;
create trigger update_on_return_trigger
    after insert on pos_schema.return_product
    for each row
    execute function update_on_return();


CREATE OR REPLACE FUNCTION auto_toggle_promotions()
returns table(
    action text,
    promotion_id uuid,
    promo_code VARCHAR(50),
    promo_name VARCHAR(100)
) as $$
declare
    _now timestamp := current_timestamp;
    _promo record;
BEGIN
    raise notice 'AUTO-TOGGLE PROMOTIONS';
    raise notice 'Timestamp: %', _now;
    raise notice '';
    
    for _promo in
        select p.promotion_id, p.promo_code, p.promo_name, p.promo_start_date
        from pos_schema.promotion p
        where p.is_active = false
        and p.promo_start_date <= _now
        and p.promo_end_date > _now
    loop
        update pos_schema.promotion
        set is_active = true,
            updated_at = _now
        where promotion_id = _promo.promotion_id;
        
        raise notice 'ACTIVATED: % - % (started: %)', 
            _promo.promo_code, _promo.promo_name, _promo.promo_start_date;
        
        action := 'ACTIVATED';
        promotion_id := _promo.promotion_id;
        promo_code := _promo.promo_code;
        promo_name := _promo.promo_name;
        return next;
    end loop;
    
    for _promo in
        select p.promotion_id, p.promo_code, p.promo_name, p.promo_end_date
        from pos_schema.promotion p
        where p.is_active = true
        and p.promo_end_date <= _now
    loop
        update pos_schema.promotion
        set is_active = false,
            updated_at = _now
        where promotion_id = _promo.promotion_id;
        
        raise notice 'DEACTIVATED: % - % (ended: %)', 
            _promo.promo_code, _promo.promo_name, _promo.promo_end_date;
        
        action := 'DEACTIVATED';
        promotion_id := _promo.promotion_id;
        promo_code := _promo.promo_code;
        promo_name := _promo.promo_name;
        return next;
    end loop;
    
    raise notice '';
    raise notice 'AUTO-TOGGLE COMPLETED';
end;
$$ language plpgsql;

    CREATE OR REPLACE FUNCTION calculate_percentage_discount(
    _promotion_id uuid,
    _quantity INTEGER,
    _unit_price numeric(10,2),
    _total_purchase_amount numeric(10,2)
) returns pos_schema.discount_result as $$
declare
    _rule record;
    _total_price numeric(10,2);
    _discount numeric(10,2);
    _discount_pct numeric(5,2);
    _result pos_schema.discount_result;
BEGIN
    _total_price := _quantity * _unit_price;
    
    select * into _rule
    from pos_schema.promotion_rule
    where promotion_id = _promotion_id
    and discount_percentage is not null
    limit 1;
    
    if not found then
        raise notice '   No percentage discount rule found';
        _result.success := false;
        return _result;
    end if;
    
    if _rule.min_purchase_amount is not null then
        if _total_purchase_amount is null or _total_purchase_amount < _rule.min_purchase_amount then
            raise notice '   Minimum purchase amount not met: $% required, $% provided',
                _rule.min_purchase_amount, coalesce(_total_purchase_amount, 0);
            _result.success := false;
            return _result;
        end if;
    end if;
    
    _discount := _total_price * (_rule.discount_percentage / 100);
    _discount_pct := _rule.discount_percentage;
    
    raise notice '   Applied: % percent discount = $%', _rule.discount_percentage, _discount;
    
    _result.discount_amount := round(_discount, 2);
    _result.discount_percentage := round(_discount_pct, 2);
    _result.rule_description := format('%s%% off', _rule.discount_percentage);
    _result.success := true;
    
    return _result;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION calculate_fixed_discount(
    _promotion_id uuid,
    _quantity INTEGER,
    _unit_price numeric(10,2),
    _total_purchase_amount numeric(10,2)
) returns pos_schema.discount_result as $$
declare
    _rule record;
    _total_price numeric(10,2);
    _discount numeric(10,2);
    _discount_pct numeric(5,2);
    _result pos_schema.discount_result;
BEGIN
    _total_price := _quantity * _unit_price;
    
    select * into _rule
    from pos_schema.promotion_rule
    where promotion_id = _promotion_id
    and discount_amount is not null
    limit 1;
    
    if not found then
        raise notice '   No fixed discount rule found';
        _result.success := false;
        return _result;
    end if;
    
    if _rule.min_purchase_amount is not null then
        if _total_purchase_amount is null or _total_purchase_amount < _rule.min_purchase_amount then
            raise notice '   Minimum purchase amount not met: $% required',
                _rule.min_purchase_amount;
            _result.success := false;
            return _result;
        end if;
    end if;
    
    _discount := least(_rule.discount_amount, _total_price);
    _discount_pct := (_discount / _total_price) * 100;
    
    raise notice '   Applied: $% discount (max: $%)', _discount, _rule.discount_amount;
    
    _result.discount_amount := round(_discount, 2);
    _result.discount_percentage := round(_discount_pct, 2);
    _result.rule_description := format('$%s off', _rule.discount_amount);
    _result.success := true;
    
    return _result;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION calculate_buy_x_get_y_discount(
    _promotion_id uuid,
    _quantity INTEGER,
    _unit_price numeric(10,2),
    _total_purchase_amount numeric(10,2)
) returns pos_schema.discount_result as $$
declare
    _rule record;
    _total_price numeric(10,2);
    _discount numeric(10,2);
    _discount_pct numeric(5,2);
    _free_items INTEGER;
    _result pos_schema.discount_result;
BEGIN
    _total_price := _quantity * _unit_price;
    
    select * into _rule
    from pos_schema.promotion_rule
    where promotion_id = _promotion_id
    and buy_quantity is not null
    and get_quantity is not null
    limit 1;
    
    if not found then
        raise notice '   No buy_x_get_y rule found';
        _result.success := false;
        return _result;
    end if;
    
    if _quantity < _rule.buy_quantity then
        raise notice '   Minimum quantity not met: % required, % provided',
            _rule.buy_quantity, _quantity;
        _result.success := false;
        return _result;
    end if;
    
    _free_items := (_quantity / _rule.buy_quantity) * _rule.get_quantity;
    
    _discount := _free_items * _unit_price * (_rule.get_discount_percentage / 100);
    _discount_pct := (_discount / _total_price) * 100;
    
    raise notice '   Applied: Buy % get % = % free items × $% = $%',
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

CREATE OR REPLACE FUNCTION calculate_volume_discount(
    _promotion_id uuid,
    _quantity INTEGER,
    _unit_price numeric(10,2),
    _total_purchase_amount numeric(10,2)
) returns pos_schema.discount_result as $$
declare
    _rule record;
    _total_price numeric(10,2);
    _discount numeric(10,2);
    _discount_pct numeric(5,2);
    _result pos_schema.discount_result;
BEGIN
    _total_price := _quantity * _unit_price;
    
    select * into _rule
    from pos_schema.promotion_rule
    where promotion_id = _promotion_id
    and min_quantity is not null
    and discount_percentage is not null
    and (min_quantity <= _quantity)
    and (max_quantity is null or max_quantity >= _quantity)
    order by min_quantity desc
    limit 1;
    
    if not found then
        raise notice '   Quantity % does not match any volume tier', _quantity;
        _result.success := false;
        return _result;
    end if;
    
    _discount := _total_price * (_rule.discount_percentage / 100);
    _discount_pct := _rule.discount_percentage;
    
    raise notice '   Applied: Volume discount % percent (min: %, max: %) = $%',
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

CREATE OR REPLACE FUNCTION calculate_tiered_pricing_discount(
    _promotion_id uuid,
    _quantity INTEGER,
    _unit_price numeric(10,2),
    _total_purchase_amount numeric(10,2)
) returns pos_schema.discount_result as $$
declare
    _rule record;
    _total_price numeric(10,2);
    _discount numeric(10,2);
    _discount_pct numeric(5,2);
    _result pos_schema.discount_result;
BEGIN
    _total_price := _quantity * _unit_price;
    
    select * into _rule
    from pos_schema.promotion_rule
    where promotion_id = _promotion_id
    and tier_level is not null
    and tier_min_quantity <= _quantity
    and (tier_max_quantity is null or tier_max_quantity >= _quantity)
    order by tier_level desc
    limit 1;
    
    if not found then
        raise notice '   Quantity % does not match any tier', _quantity;
        _result.success := false;
        return _result;
    end if;
    
    if _rule.tier_price is not null then
        _discount := (_unit_price - _rule.tier_price) * _quantity;
        _discount_pct := ((_unit_price - _rule.tier_price) / _unit_price) * 100;
        
        raise notice '   Applied: Tier % - Fixed price $% per unit = $% discount',
            _rule.tier_level, _rule.tier_price, _discount;
        
        _result.rule_description := format('Tier %s: $%s per unit',
            _rule.tier_level,
            _rule.tier_price);
            
    elsif _rule.tier_discount_percentage is not null then
        _discount := _total_price * (_rule.tier_discount_percentage / 100);
        _discount_pct := _rule.tier_discount_percentage;
        
        raise notice '   Applied: Tier % - % percent discount = $%',
            _rule.tier_level, _rule.tier_discount_percentage, _discount;
        
        _result.rule_description := format('Tier %s: %s%% off',
            _rule.tier_level,
            _rule.tier_discount_percentage);
    else
        raise notice '   Tier found but no price or discount defined';
        _result.success := false;
        return _result;
    end if;
    
    _result.discount_amount := round(_discount, 2);
    _result.discount_percentage := round(_discount_pct, 2);
    _result.success := true;
    
    return _result;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION calculate_combo_discount(
    _promotion_id uuid,
    _quantity INTEGER,
    _unit_price numeric(10,2),
    _total_purchase_amount numeric(10,2)
) returns pos_schema.discount_result as $$
declare
    _result pos_schema.discount_result;
BEGIN
    raise notice '   Combo discounts require multiple products and should be calculated at cart level';
    _result.success := false;
    return _result;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION calculate_promotion_discount(
    _promotion_id uuid,
    _tenant_id uuid,
    _product_variant_id uuid,
    _quantity INTEGER,
    _unit_price numeric(10,2),
    _total_purchase_amount numeric(10,2) default null
) returns table(
    discount_amount numeric(10,2),
    discount_percentage numeric(5,2),
    promotion_type VARCHAR(50),
    rule_applied text
) as $$
declare
    _promo record;
    _type_name VARCHAR(50);
    _result pos_schema.discount_result;
BEGIN
    select 
        p.promotion_id,
        p.promotion_code,
        p.promotion_name,
        p.is_active,
        p.promotion_start_date,
        p.promotion_end_date,
        pt.type_name
    into _promo
    from pos_schema.promotion p
    join pos_schema.promotion_type pt on p.promotion_type_id = pt.promotion_type_id
    where p.promotion_id = _promotion_id
    and p.tenant_id = _tenant_id;
    
    if not found then
        raise notice 'Promotion not found: %', _promotion_id;
        return;
    end if;
    
    if not _promo.is_active then
        raise notice 'Promotion % is not active', _promo.promotion_code;
        return;
    end if;
    
    if current_timestamp not between _promo.promotion_start_date and _promo.promotion_end_date then
        raise notice 'Promotion % is not in valid date range', _promo.promotion_code;
        return;
    end if;
    
    _type_name := _promo.type_name;
    
    raise notice 'Calculating discount for promotion: % (%)', _promo.promotion_name, _type_name;
    raise notice '   Product Variant: %, Quantity: %, Unit Price: $%', _product_variant_id, _quantity, _unit_price;
    
    case _type_name
        when 'percentage_discount' then
            _result := pos_schema.calculate_percentage_discount(
                _promotion_id, _quantity, _unit_price, _total_purchase_amount
            );
            
        when 'fixed_amount_discount' then
            _result := pos_schema.calculate_fixed_discount(
                _promotion_id, _quantity, _unit_price, _total_purchase_amount
            );
            
        when 'buy_x_get_y' then
            _result := pos_schema.calculate_buy_x_get_y_discount(
                _promotion_id, _quantity, _unit_price, _total_purchase_amount
            );
            
        when 'volume_discount' then
            _result := pos_schema.calculate_volume_discount(
                _promotion_id, _quantity, _unit_price, _total_purchase_amount
            );
            
        when 'tiered_pricing' then
            _result := pos_schema.calculate_tiered_pricing_discount(
                _promotion_id, _quantity, _unit_price, _total_purchase_amount
            );
            
        when 'combo' then
            _result := pos_schema.calculate_combo_discount(
                _promotion_id, _quantity, _unit_price, _total_purchase_amount
            );
            
        when 'free_shipping' then
            raise notice '   Free shipping discount (not implemented for products)';
            return;
            
        else
            raise notice '   Unknown promotion type: %', _type_name;
            return;
    end case;
    
    if _result.success then
        return query select 
            _result.discount_amount,
            _result.discount_percentage,
            _type_name::VARCHAR(50),
            _result.rule_description;
    end if;

    return;
    
end;
$$ language plpgsql;

CREATE OR REPLACE PROCEDURE open_close_cash_register_session(
    _cash_register_id uuid,
    _action VARCHAR(10), 
    _amount numeric(10,2),
    _user_id uuid
)
as $$
declare
    _session_id uuid;
    _session record;
    _rows_updated int;
BEGIN
        if _action = 'open' then
            select cash_register_session_id into _session_id
            from pos_schema.cash_register_session
            where cash_register_id = _cash_register_id
            and is_active = true
            limit 1;
            
            if _session_id is not null then
                raise exception 'Cash register % already has an open session: %', 
                    _cash_register_id, _session_id;
            end if;
            
            INSERT INTO pos_schema.cash_register_session (
                cash_register_id,
                user_id,
                opened_at,
                opening_amount,
                is_active,
                created_at,
                updated_at
            ) VALUES (
                _cash_register_id,
                _user_id,
                current_timestamp,
                _amount,
                true,
                current_timestamp,
                current_timestamp
            ) returning cash_register_session_id into _session_id;
            
            raise notice 'Cash register % opened', _cash_register_id;
            raise notice '   Session ID: %', _session_id;
            raise notice '   Opening amount: $%', _amount;
            raise notice '   Opened at: %', current_timestamp;
            
        elsif _action = 'close' then
            update pos_schema.cash_register_session
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
            
            raise notice 'Cash register % closed', _cash_register_id;
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
            raise notice 'Error in cash register session: %', sqlerrm;
            raise;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION calculate_purchase_score(
_tenant_id uuid,
_tenant_customer_id uuid,
_purchase_amount numeric(10,2)
) returns INTEGER as $$
declare
    _minimum_purchase numeric(10,2);
    _points_earned_per_currency_unit numeric(5,2);
    _score INTEGER;
    _program_exists BOOLEAN;
BEGIN
        select exists(
            select 1 
            from pos_schema.loyalty_program 
            where tenant_id = _tenant_id 
            and is_active = true
        ) into _program_exists;
        
        if not _program_exists then
            raise notice 'No active loyalty program for tenant %', _tenant_id;
            return 0;
        end if;
        
        select 
            minimum_purchase_for_points, 
            points_earned_per_currency_unit 
        into 
            _minimum_purchase, 
            _points_earned_per_currency_unit 
        from pos_schema.loyalty_program 
        where tenant_id = _tenant_id
        and is_active = true
        limit 1;
        
        _score := floor(_purchase_amount * _points_earned_per_currency_unit);
        
        raise notice 'Points: $% × % = % pts',
            _purchase_amount, _points_earned_per_currency_unit, _score;
        
        return _score;
        
    exception
        when others then
            raise notice 'Error calculating points: %', sqlerrm;
            return 0;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION award_points()
returns trigger as $$
declare
    _tenant_id uuid;
    _tenant_customer_id uuid;
    _digital_sale_invoice_id uuid;
    _points_earned INTEGER;
    _current_balance INTEGER;
    _cash_payments_total numeric(10,2);
    _points_already_awarded BOOLEAN;
BEGIN
        _digital_sale_invoice_id := new.digital_sale_invoice_id;
        
        select exists(
            select 1 
            from pos_schema.score_transaction 
            where digital_sale_invoice_id = _digital_sale_invoice_id 
            and transaction_type_id = 1  
        ) into _points_already_awarded;
        
        if _points_already_awarded then
            raise notice 'Points already awarded for digital sale invoice %', _digital_sale_invoice_id;
            return new;
        end if;
        
        select tenant_customer_id into _tenant_customer_id
        from pos_schema.digital_sale_invoice
        where digital_sale_invoice_id = _digital_sale_invoice_id;
        
        if _tenant_customer_id is null then
            raise notice 'No customer found for digital sale invoice %', _digital_sale_invoice_id;
            return new;
        end if;
        
        select tenant_id into _tenant_id
        from general_schema.tenant_customer
        where tenant_customer_id = _tenant_customer_id;
        
        if _tenant_id is null then
            raise notice 'Tenant not found for customer %', _tenant_customer_id;
            return new;
        end if;
        
        select coalesce(sum(cp.payment_amount), 0) into _cash_payments_total
        from pos_schema.digital_sale_invoice_payment bp
        join pos_schema.customer_payment cp on bp.customer_payment_id = cp.customer_payment_id
        where bp.digital_sale_invoice_id = _digital_sale_invoice_id
        and cp.is_points_redemption = false;
        
        raise notice 'Cash/card payments total: $%', _cash_payments_total;
        
        _points_earned := pos_schema.calculate_purchase_score(
            _tenant_id,
            _tenant_customer_id,
            _cash_payments_total
        );
        
        if _points_earned <= 0 then
            raise notice 'No points earned for this purchase (Invoice: %)', _digital_sale_invoice_id;
            return new;
        end if;
        
        INSERT INTO pos_schema.tenant_customer_score(
            tenant_id,
            tenant_customer_id,
            score,
            lifetime_score,
            last_earned_at
        ) VALUES (
            _tenant_id,
            _tenant_customer_id,
            _points_earned,
            _points_earned,
            current_timestamp
        )
        on conflict (tenant_customer_id, tenant_id)
        DO update set
            score = tenant_customer_score.score + _points_earned,
            lifetime_score = tenant_customer_score.lifetime_score + _points_earned,
            last_earned_at = current_timestamp
        returning score into _current_balance;
        
        INSERT INTO pos_schema.score_transaction(
            tenant_id,
            tenant_customer_id,
            transaction_type_id,
            points,
            digital_sale_invoice_id,
            created_at
        ) VALUES (
            _tenant_id,
            _tenant_customer_id,
            1,  
            _points_earned,
            _digital_sale_invoice_id,
            current_timestamp
        );
        
        raise notice 'Awarded % points to customer %', _points_earned, _tenant_customer_id;
        raise notice 'Invoice: %', _digital_sale_invoice_id;
        raise notice 'New balance: % points', _current_balance;
        
        return new;
        
    exception
        when others then
            raise notice 'Error awarding points: %', sqlerrm;
            return new;
end;
$$ language plpgsql;

drop trigger if exists on_purchase_billed on pos_schema.digital_sale_invoice_payment;
drop trigger if exists on_purchase_billed on pos_schema.digital_sale_invoice_payment;
drop trigger if exists on_invoice_payment_award_points on pos_schema.digital_sale_invoice_payment;
create trigger on_invoice_payment_award_points
    after insert on pos_schema.digital_sale_invoice_payment
    for each row
    execute function pos_schema.award_points();

CREATE OR REPLACE FUNCTION redeem_points(
_tenant_customer_id uuid,
_points_to_redeem INTEGER
) returns table(
    cash_value numeric(10,2),
    points_available INTEGER,
    success BOOLEAN,
    message text
) as $$
declare
    _points_redeemed_per_currency_unit numeric(10,2); 
    _tenant_id uuid;
    _current_points INTEGER;
    _cash_equivalent numeric(10,2);
BEGIN   
    select tenant_id into _tenant_id
    from general_schema.tenant_customer
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
    from pos_schema.tenant_customer_score
    where tenant_customer_id = _tenant_customer_id
    and tenant_id = _tenant_id;

    select points_redeemed_per_currency_unit into _points_redeemed_per_currency_unit
    from pos_schema.loyalty_program
    where tenant_id = _tenant_id
    and is_active = true
    limit 1;

    if _points_redeemed_per_currency_unit is null then
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

    _cash_equivalent := _points_to_redeem / _points_redeemed_per_currency_unit;

    update pos_schema.tenant_customer_score
    set score = score - _points_to_redeem,
        score_redeemed = score_redeemed + _points_to_redeem,
        last_redeemed_at = current_timestamp,
        updated_at = current_timestamp
    where tenant_customer_id = _tenant_customer_id
    and tenant_id = _tenant_id;

    INSERT INTO pos_schema.score_transaction(
        tenant_id,
        tenant_customer_id,
        transaction_type_id,
        points,
        created_at
    ) VALUES (
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
            _points_redeemed_per_currency_unit, 
            round(_cash_equivalent, 2))::text;
    exception
        when others then
            raise notice 'Error redeeming points: %', sqlerrm;
            return query select 
                0.00::numeric(10,2),
                coalesce(_current_points, 0),
                false,
                sqlerrm::text;
end;
$$ language plpgsql;

CREATE OR REPLACE PROCEDURE verify_customer_payment(_payment_id uuid)
as $$
declare
    _exists BOOLEAN;
    _already_verified BOOLEAN;
    _tenant_customer_id uuid;
    _sale_id uuid;
    _payment_amount numeric(10,2);
    _payment_method VARCHAR(50);
    _is_points_redemption BOOLEAN;
    _points_redeemed INTEGER;
    _redeem_result record;
    _sale_completed BOOLEAN;
BEGIN
    select exists(
        select 1 
        from pos_schema.customer_payment 
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
    from pos_schema.customer_payment 
    where customer_payment_id = _payment_id;
    
    if _already_verified then
        raise notice 'Payment % is already verified', _payment_id;
        return;
    end if;
    
    if _sale_id is null then
        raise exception 'Payment % has no associated sale', _payment_id;
    end if;
    
    raise notice 'Verifying payment: %', _payment_id;
    raise notice '   Sale: %', _sale_id;
    raise notice '   Customer: %', _tenant_customer_id;
    raise notice '   Amount: $%', _payment_amount;
    
    select name into _payment_method
    from general_schema.payment_method pm
    join pos_schema.customer_payment cp on pm.payment_method_id = cp.payment_method_id
    where cp.customer_payment_id = _payment_id;
    
    raise notice '   Method: %', _payment_method;
    raise notice '';
    
    if _is_points_redemption then
        raise notice 'Processing points redemption...';
        raise notice '   Points to redeem: %', _points_redeemed;
        
        select * into _redeem_result
        from pos_schema.redeem_points(
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
        
        raise notice '   Redeemed % points = $%', _points_redeemed, _payment_amount;
        raise notice '   %', _redeem_result.message;
        raise notice '   Remaining points: %', _redeem_result.points_available;
        raise notice '';
    end if;

    update pos_schema.customer_payment
    set verified = true,
        updated_at = current_timestamp
    where customer_payment_id = _payment_id;
    
    raise notice 'Payment verified successfully';
    raise notice '';
    
    raise notice 'Checking if sale is fully paid...';
    _sale_completed := pos_schema.check_sale_payment_completion(_sale_id);
    
    if _sale_completed then
        raise notice '';
        raise notice 'Sale % is COMPLETED - Trigger will create bill', _sale_id;
    else
        raise notice '';
        raise notice 'Sale % is PENDING - Waiting for more payments', _sale_id;
    end if;
    
    exception
        when others then
            raise notice '  Payment verification failed: %', sqlerrm;
            raise;
end;
$$ language plpgsql;      

-- ==========================
-- UPDATE TIMESTAMP TRIGGERS
-- ==========================

drop trigger if exists update_customer_payment_timestamp on pos_schema.customer_payment;
create trigger update_customer_payment_timestamp before update on pos_schema.customer_payment
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_bill_timestamp on pos_schema.digital_sale_invoice;
drop trigger if exists update_digital_sale_invoice_timestamp on pos_schema.digital_sale_invoice;
create trigger update_digital_sale_invoice_timestamp before update on pos_schema.digital_sale_invoice
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_digital_sale_invoice_item_timestamp on pos_schema.digital_sale_invoice_item;
create trigger update_digital_sale_invoice_item_timestamp before update on pos_schema.digital_sale_invoice_item
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_return_transaction_timestamp on pos_schema.return_transaction;
create trigger update_return_transaction_timestamp before update on pos_schema.return_transaction
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_return_product_timestamp on pos_schema.return_product;
create trigger update_return_product_timestamp before update on pos_schema.return_product
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_promotion_timestamp on pos_schema.promotion;
create trigger update_promotion_timestamp before update on pos_schema.promotion
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_promotion_rule_timestamp on pos_schema.promotion_rule;
create trigger update_promotion_rule_timestamp before update on pos_schema.promotion_rule
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_cash_register_session_timestamp on pos_schema.cash_register_session;
create trigger update_cash_register_session_timestamp before update on pos_schema.cash_register_session
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_cash_register_sale_timestamp on pos_schema.cash_register_sale;
create trigger update_cash_register_sale_timestamp before update on pos_schema.cash_register_sale
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_tenant_customer_score_timestamp on pos_schema.tenant_customer_score;
create trigger update_tenant_customer_score_timestamp before update on pos_schema.tenant_customer_score
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_score_transaction_timestamp on pos_schema.score_transaction;
create trigger update_score_transaction_timestamp before update on pos_schema.score_transaction
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_digital_sale_invoice_payment_timestamp on pos_schema.digital_sale_invoice_payment;
drop trigger if exists update_digital_sale_invoice_payment_timestamp on pos_schema.digital_sale_invoice_payment;
create trigger update_digital_sale_invoice_payment_timestamp before update on pos_schema.digital_sale_invoice_payment
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_sale_timestamp on pos_schema.sale;
create trigger update_sale_timestamp before update on pos_schema.sale
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_sale_item_timestamp on pos_schema.sale_item;
create trigger update_sale_item_timestamp before update on pos_schema.sale_item
for each row execute function general_schema.update_timestamp();

CREATE OR REPLACE FUNCTION pos_schema.close_cash_register_session(
    p_session_id     uuid,
    p_closing_amount numeric,
    p_user_cash      numeric DEFAULT 0,
    p_user_debit     numeric DEFAULT 0,
    p_user_credit    numeric DEFAULT 0,
    p_user_transfer  numeric DEFAULT 0
)
RETURNS pos_schema.cash_register_session
LANGUAGE plpgsql
AS $$
DECLARE
    v_session             pos_schema.cash_register_session%ROWTYPE;
    v_system_cash         NUMERIC(14, 2) := 0;
    v_system_debit        NUMERIC(14, 2) := 0;
    v_system_credit       NUMERIC(14, 2) := 0;
    v_system_transfer     NUMERIC(14, 2) := 0;
    v_system_points       NUMERIC(14, 2) := 0;
    v_system_total_sales  NUMERIC(14, 2) := 0;
    v_diff_cash           NUMERIC(14, 2);
    v_diff_debit          NUMERIC(14, 2);
    v_diff_credit         NUMERIC(14, 2);
    v_diff_transfer       NUMERIC(14, 2);
    v_mismatch            BOOLEAN        := FALSE;
    v_mismatch_amt        NUMERIC(14, 2) := 0;
    v_mismatch_type       VARCHAR(10)    := NULL;
BEGIN
    SELECT * INTO v_session
    FROM pos_schema.cash_register_session
    WHERE cash_register_session_id = p_session_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session not found: %', p_session_id;
    END IF;

    IF NOT v_session.is_active THEN
        RAISE EXCEPTION 'Session % is already closed', p_session_id;
    END IF;

    INSERT INTO pos_schema.session_payment_method_sales
        (cash_register_session_id, payment_method_id, total_amount)
    SELECT
        p_session_id,
        cp.payment_method_id,
        COALESCE(SUM(cp.payment_amount), 0)
    FROM pos_schema.customer_payment cp
    INNER JOIN pos_schema.cash_register_sale crs ON crs.sale_id = cp.sale_id
    WHERE crs.cash_register_session_id = p_session_id
    GROUP BY cp.payment_method_id
    ON CONFLICT (cash_register_session_id, payment_method_id)
    DO UPDATE SET total_amount = EXCLUDED.total_amount;

    -- Single aggregate: guaranteed one row, zero for missing methods
    SELECT
        COALESCE(SUM(total_amount) FILTER (WHERE payment_method_id = 1), 0),
        COALESCE(SUM(total_amount) FILTER (WHERE payment_method_id = 2), 0),
        COALESCE(SUM(total_amount) FILTER (WHERE payment_method_id = 3), 0),
        COALESCE(SUM(total_amount) FILTER (WHERE payment_method_id = 4), 0),
        COALESCE(SUM(total_amount) FILTER (WHERE payment_method_id = 5), 0),
        COALESCE(SUM(total_amount), 0)
    INTO
        v_system_cash,
        v_system_debit,
        v_system_credit,
        v_system_transfer,
        v_system_points,
        v_system_total_sales
    FROM pos_schema.session_payment_method_sales
    WHERE cash_register_session_id = p_session_id;

    -- Per-method diff (cash must cover opening float + cash sales)
    v_diff_cash     := p_user_cash     - (v_session.opening_amount + v_system_cash);
    v_diff_debit    := p_user_debit    - v_system_debit;
    v_diff_credit   := p_user_credit   - v_system_credit;
    v_diff_transfer := p_user_transfer - v_system_transfer;

    IF ABS(v_diff_cash)     > 0.01
    OR ABS(v_diff_debit)    > 0.01
    OR ABS(v_diff_credit)   > 0.01
    OR ABS(v_diff_transfer) > 0.01
    THEN
        v_mismatch     := TRUE;
        v_mismatch_amt := v_diff_cash + v_diff_debit + v_diff_credit + v_diff_transfer;
        v_mismatch_type := CASE WHEN v_mismatch_amt > 0 THEN 'surplus' ELSE 'shortage' END;
    END IF;

    INSERT INTO pos_schema.session_group_sales
        (cash_register_session_id, tenant_product_group_id, group_name, total_amount)
    SELECT
        p_session_id,
        tpg.tenant_product_group_id,
        tpg.group_name,
        ROUND(SUM(si.total_price), 2)
    FROM pos_schema.sale_item si
    INNER JOIN pos_schema.cash_register_sale crs_link
        ON crs_link.sale_id = si.sale_id
    INNER JOIN general_schema.product_variant_group_assignment pvga
        ON  pvga.product_variant_id = si.product_variant_id
        AND pvga.tenant_id          = si.tenant_id
    INNER JOIN general_schema.tenant_product_group tpg
        ON tpg.tenant_product_group_id = pvga.tenant_product_group_id
    WHERE crs_link.cash_register_session_id = p_session_id
    GROUP BY tpg.tenant_product_group_id, tpg.group_name
    ON CONFLICT (cash_register_session_id, tenant_product_group_id)
    DO UPDATE SET total_amount = EXCLUDED.total_amount;

    UPDATE pos_schema.cash_register_session
    SET
        closed_at             = NOW(),
        closing_amount        = p_closing_amount,
        is_active             = FALSE,
        cash_sales_amount     = v_system_cash,
        debit_sales_amount    = v_system_debit,
        credit_sales_amount   = v_system_credit,
        transfer_sales_amount = v_system_transfer,
        points_sales_amount   = v_system_points,
        total_sales_amount    = v_system_total_sales,
        user_cash_amount      = p_user_cash,
        user_debit_amount     = p_user_debit,
        user_credit_amount    = p_user_credit,
        user_transfer_amount  = p_user_transfer,
        mismatch              = v_mismatch,
        mismatch_amount       = ABS(v_mismatch_amt),
        mismatch_type         = v_mismatch_type,
        updated_at            = NOW()
    WHERE cash_register_session_id = p_session_id
    RETURNING * INTO v_session;

    RETURN v_session;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- CxC (Cuentas por Cobrar) — Collection subsystem functions
-- Mirror of the AP alert functions in functions/purchase/purchase_functions.sql
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS check_account_receivable_completion(UUID);

CREATE OR REPLACE FUNCTION check_account_receivable_completion(_account_receivable_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    _subtotal       NUMERIC(12,3);
    _tax_amount     NUMERIC(12,3);
    _amount_due     NUMERIC(12,3);
    _payments_total NUMERIC(12,3);
    _balance        NUMERIC(12,3);
    _target_sar_id  UUID;
BEGIN
    SELECT
        ar.subtotal,
        sar.tax_amount,
        (ar.subtotal + COALESCE(sar.tax_amount, 0)) AS amount_due,
        sar.sale_account_receivable_id
    INTO
        _subtotal,
        _tax_amount,
        _amount_due,
        _target_sar_id
    FROM general_schema.account_receivable ar
    JOIN pos_schema.sale_account_receivable sar
        ON ar.account_receivable_id = sar.account_receivable_id
    WHERE ar.account_receivable_id = _account_receivable_id;

    IF _amount_due IS NULL THEN
        RAISE EXCEPTION 'Account receivable not found: %', _account_receivable_id;
    END IF;

    SELECT COALESCE(SUM(sc.amount_paid), 0) INTO _payments_total
    FROM pos_schema.sale_collection sc
    WHERE sc.sale_account_receivable_id = _target_sar_id;

    _balance := _amount_due - _payments_total;

    UPDATE general_schema.account_receivable
    SET amount_paid = _payments_total,
        updated_at  = CURRENT_TIMESTAMP
    WHERE account_receivable_id = _account_receivable_id;

    IF ABS(_balance) <= 0.01 OR _payments_total >= _amount_due THEN
        UPDATE general_schema.account_receivable
        SET is_paid    = TRUE,
            updated_at = CURRENT_TIMESTAMP
        WHERE account_receivable_id = _account_receivable_id;

        UPDATE pos_schema.sale_account_receivable
        SET account_receivable_status = 3,
            updated_at                = CURRENT_TIMESTAMP
        WHERE account_receivable_id = _account_receivable_id;

        RETURN TRUE;

    ELSIF _payments_total > 0 THEN
        UPDATE pos_schema.sale_account_receivable
        SET account_receivable_status = 2,
            updated_at                = CURRENT_TIMESTAMP
        WHERE account_receivable_id = _account_receivable_id;

        RETURN FALSE;

    ELSE
        RETURN FALSE;
    END IF;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION recalc_account_receivable_on_collection() RETURNS TRIGGER AS $$
BEGIN
    PERFORM pos_schema.check_account_receivable_completion(
        (SELECT ar.account_receivable_id
         FROM general_schema.account_receivable ar
         JOIN pos_schema.sale_account_receivable sar
             ON ar.account_receivable_id = sar.account_receivable_id
         WHERE sar.sale_account_receivable_id = NEW.sale_account_receivable_id)
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


DROP TRIGGER IF EXISTS recalc_account_receivable_on_collection_trigger ON pos_schema.sale_collection;

CREATE TRIGGER recalc_account_receivable_on_collection_trigger
AFTER INSERT OR UPDATE OF amount_paid ON pos_schema.sale_collection
FOR EACH ROW EXECUTE FUNCTION pos_schema.recalc_account_receivable_on_collection();


CREATE OR REPLACE FUNCTION auto_resolve_collection_alerts() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.account_receivable_status = 3 AND OLD.account_receivable_status IS DISTINCT FROM 3 THEN
        UPDATE pos_schema.sale_collection_alert
        SET is_resolved = TRUE,
            updated_at  = CURRENT_TIMESTAMP
        WHERE sale_account_receivable_id = NEW.sale_account_receivable_id
          AND is_resolved = FALSE;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


DROP TRIGGER IF EXISTS auto_resolve_collection_alerts_trigger ON pos_schema.sale_account_receivable;

CREATE TRIGGER auto_resolve_collection_alerts_trigger
AFTER UPDATE OF account_receivable_status ON pos_schema.sale_account_receivable
FOR EACH ROW EXECUTE FUNCTION pos_schema.auto_resolve_collection_alerts();


CREATE OR REPLACE FUNCTION generate_collection_alerts() RETURNS VOID AS $$
DECLARE
    v_config        RECORD;
    v_account       RECORD;
    v_days_until_due INTEGER;
    v_alert_type_id INTEGER;
    v_existing_id   UUID;
BEGIN
    FOR v_config IN
        SELECT tenant_id, warning_days_before_due, urgent_days_before_due
        FROM pos_schema.sale_collection_alert_config
    LOOP
        FOR v_account IN
            SELECT
                ar.account_receivable_id,
                ar.due_date,
                ar.is_paid,
                ar.amount_paid,
                ar.subtotal,
                sar.sale_account_receivable_id,
                sar.tax_amount,
                (ar.subtotal + COALESCE(sar.tax_amount, 0) - ar.amount_paid) AS balance_remaining
            FROM general_schema.account_receivable ar
            JOIN pos_schema.sale_account_receivable sar
                ON ar.account_receivable_id = sar.account_receivable_id
            WHERE ar.tenant_id = v_config.tenant_id
              AND ar.is_paid = FALSE
              AND (ar.subtotal + COALESCE(sar.tax_amount, 0) - ar.amount_paid) > 0
        LOOP
            v_days_until_due := v_account.due_date - CURRENT_DATE;

            IF v_days_until_due < 0 THEN
                v_alert_type_id := 3;
            ELSIF v_days_until_due <= v_config.urgent_days_before_due THEN
                v_alert_type_id := 2;
            ELSIF v_days_until_due <= v_config.warning_days_before_due THEN
                v_alert_type_id := 1;
            ELSE
                CONTINUE;
            END IF;

            SELECT collection_alert_id INTO v_existing_id
            FROM pos_schema.sale_collection_alert
            WHERE sale_account_receivable_id = v_account.sale_account_receivable_id
              AND collection_alert_type_id = v_alert_type_id
              AND is_resolved = FALSE
            LIMIT 1;

            IF v_existing_id IS NULL THEN
                INSERT INTO pos_schema.sale_collection_alert(
                    sale_account_receivable_id,
                    collection_alert_type_id,
                    alert_date,
                    is_resolved
                ) VALUES (
                    v_account.sale_account_receivable_id,
                    v_alert_type_id,
                    CURRENT_TIMESTAMP,
                    FALSE
                );
            END IF;
        END LOOP;
    END LOOP;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error generating collection alerts: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;


DROP FUNCTION IF EXISTS get_pending_collection_alerts(UUID);

CREATE OR REPLACE FUNCTION get_pending_collection_alerts(p_tenant_id UUID)
RETURNS TABLE(
    collection_alert_id        UUID,
    sale_account_receivable_id UUID,
    sale_id                    UUID,
    customer_name              VARCHAR,
    alert_type                 VARCHAR,
    alert_type_description     TEXT,
    due_date                   DATE,
    days_until_due             INTEGER,
    balance_remaining          NUMERIC,
    alert_date                 TIMESTAMP,
    created_at                 TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        sca.collection_alert_id,
        sar.sale_account_receivable_id,
        sar.sale_id,
        (tc.first_name || ' ' || tc.last_name)::VARCHAR AS customer_name,
        scat.collection_alert_type_name,
        scat.description,
        ar.due_date,
        (ar.due_date - CURRENT_DATE)::INTEGER AS days_until_due,
        (ar.subtotal + COALESCE(sar.tax_amount, 0) - ar.amount_paid) AS balance_remaining,
        sca.alert_date,
        sca.created_at
    FROM pos_schema.sale_collection_alert sca
    JOIN pos_schema.sale_collection_alert_type scat
        ON sca.collection_alert_type_id = scat.collection_alert_type_id
    JOIN pos_schema.sale_account_receivable sar
        ON sca.sale_account_receivable_id = sar.sale_account_receivable_id
    JOIN general_schema.account_receivable ar
        ON sar.account_receivable_id = ar.account_receivable_id
    LEFT JOIN general_schema.tenant_customer tc
        ON ar.tenant_customer_id = tc.tenant_customer_id
    WHERE ar.tenant_id = p_tenant_id
      AND sca.is_resolved = FALSE
    ORDER BY ar.due_date ASC, sca.alert_date DESC;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error fetching pending collection alerts: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION resolve_collection_alert(p_alert_id UUID) RETURNS VOID AS $$
BEGIN
    UPDATE pos_schema.sale_collection_alert
    SET is_resolved = TRUE,
        updated_at  = CURRENT_TIMESTAMP
    WHERE collection_alert_id = p_alert_id;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION initialize_collection_alert_config(
    p_tenant_id     UUID,
    p_warning_days  INTEGER DEFAULT 7,
    p_urgent_days   INTEGER DEFAULT 3,
    p_email_enabled BOOLEAN DEFAULT TRUE,
    p_sms_enabled   BOOLEAN DEFAULT FALSE
) RETURNS UUID AS $$
DECLARE
    v_config_id UUID;
BEGIN
    INSERT INTO pos_schema.sale_collection_alert_config(
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
    ON CONFLICT (tenant_id) DO UPDATE
    SET warning_days_before_due     = EXCLUDED.warning_days_before_due,
        urgent_days_before_due      = EXCLUDED.urgent_days_before_due,
        email_notifications_enabled = EXCLUDED.email_notifications_enabled,
        sms_notifications_enabled   = EXCLUDED.sms_notifications_enabled,
        updated_at                  = CURRENT_TIMESTAMP
    RETURNING collection_alert_config_id INTO v_config_id;

    RETURN v_config_id;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION get_collection_alert_stats(p_tenant_id UUID)
RETURNS TABLE(
    total_alerts        INTEGER,
    overdue_count       INTEGER,
    urgent_count        INTEGER,
    warning_count       INTEGER,
    total_amount_at_risk NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*)::INTEGER AS total_alerts,
        COUNT(*) FILTER (WHERE scat.collection_alert_type_id = 3)::INTEGER AS overdue_count,
        COUNT(*) FILTER (WHERE scat.collection_alert_type_id = 2)::INTEGER AS urgent_count,
        COUNT(*) FILTER (WHERE scat.collection_alert_type_id = 1)::INTEGER AS warning_count,
        COALESCE(SUM(ar.subtotal + COALESCE(sar.tax_amount, 0) - ar.amount_paid), 0) AS total_amount_at_risk
    FROM pos_schema.sale_collection_alert sca
    JOIN pos_schema.sale_collection_alert_type scat
        ON sca.collection_alert_type_id = scat.collection_alert_type_id
    JOIN pos_schema.sale_account_receivable sar
        ON sca.sale_account_receivable_id = sar.sale_account_receivable_id
    JOIN general_schema.account_receivable ar
        ON sar.account_receivable_id = ar.account_receivable_id
    WHERE ar.tenant_id = p_tenant_id
      AND sca.is_resolved = FALSE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error calculating collection alert stats: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;


DROP TRIGGER IF EXISTS update_sale_account_receivable_timestamp ON pos_schema.sale_account_receivable;

CREATE TRIGGER update_sale_account_receivable_timestamp
BEFORE UPDATE ON pos_schema.sale_account_receivable
FOR EACH ROW EXECUTE FUNCTION general_schema.update_timestamp();


DROP TRIGGER IF EXISTS update_sale_collection_timestamp ON pos_schema.sale_collection;

CREATE TRIGGER update_sale_collection_timestamp
BEFORE UPDATE ON pos_schema.sale_collection
FOR EACH ROW EXECUTE FUNCTION general_schema.update_timestamp();


DROP TRIGGER IF EXISTS update_sale_collection_alert_timestamp ON pos_schema.sale_collection_alert;

CREATE TRIGGER update_sale_collection_alert_timestamp
BEFORE UPDATE ON pos_schema.sale_collection_alert
FOR EACH ROW EXECUTE FUNCTION general_schema.update_timestamp();


DROP TRIGGER IF EXISTS update_sale_collection_alert_config_timestamp ON pos_schema.sale_collection_alert_config;

CREATE TRIGGER update_sale_collection_alert_config_timestamp
BEFORE UPDATE ON pos_schema.sale_collection_alert_config
FOR EACH ROW EXECUTE FUNCTION general_schema.update_timestamp();


DROP TRIGGER IF EXISTS update_account_receivable_timestamp ON general_schema.account_receivable;

CREATE TRIGGER update_account_receivable_timestamp
BEFORE UPDATE ON general_schema.account_receivable
FOR EACH ROW EXECUTE FUNCTION general_schema.update_timestamp();

