set search_path = general_schema;

CREATE OR REPLACE PROCEDURE verify_tenant_payment(_payment_id uuid)
language plpgsql
as $$
declare
    _exists BOOLEAN;
    _already_verified BOOLEAN;
    _rows_updated int;
    _tenant_id uuid;
BEGIN
    select exists(
        select 1 
        from general_schema.tenant_payment 
        where tenant_payment_id = _payment_id
    ) into _exists;
    
    if not _exists then
        raise notice 'Payment with id: % does not exist.', _payment_id;
        raise exception 'Payment not found: %', _payment_id;
    end if;

    select coalesce(verified, false), tenant_id 
    into _already_verified, _tenant_id
    from general_schema.tenant_payment 
    where tenant_payment_id = _payment_id;
    
    if _already_verified then
        raise notice 'Payment % is already verified.', _payment_id;
        return;
    end if;

    update general_schema.tenant_payment
    set verified = true,
        updated_at = current_timestamp
    where tenant_payment_id = _payment_id
    and coalesce(verified, false) = false;
    
    get diagnostics _rows_updated = row_count;
    
    if _rows_updated > 0 then

        raise notice 'Payment verified successfully: %', _payment_id;
        raise notice 'Tenant: %', _tenant_id;
        raise notice 'Trigger will create subscription automatically';

    else
        raise notice 'No rows updated for payment: %', _payment_id;
        raise exception 'Failed to verify payment: %', _payment_id;
    end if;
        
exception
    when others then
        raise notice 'Payment verification failed: %', sqlerrm;
        raise;
end
$$;




CREATE OR REPLACE FUNCTION create_subscription()
returns trigger as $$
declare
    _subscription_type_id int;
    _exists BOOLEAN;
    _old_end_date date;
    _time_left interval;
    _new_start_date date;
    _new_end_date date;
    _tenant_id uuid;
    _plan_duration interval;
BEGIN
    _tenant_id := new.tenant_id;


    select exists(
        select 1 
        from general_schema.subscription 
        where tenant_payment_id = new.tenant_payment_id  
    ) into _exists;
    
    if _exists then
        raise notice 'Subscription already exists for payment: %', new.tenant_payment_id;
        return new;
    end if;


    select end_date into _old_end_date
    from general_schema.subscription
    where tenant_id = _tenant_id
    and is_active = true
    order by end_date desc
    limit 1;

    _subscription_type_id := case
        when new.payment_amount = 0 then 1         
        when new.payment_amount between 5 and 15 then 1   
        when new.payment_amount between 40 and 60 then 2  
        when new.payment_amount between 80 and 100 then 3  
        else 1 
    end;
    

    select (duration_months || ' months')::interval into _plan_duration
    from general_schema.subscription_type
    where subscription_type_id = _subscription_type_id;

    if _old_end_date is not null and _old_end_date > new.payment_date::date then
        _time_left := _old_end_date - new.payment_date::date;
        raise notice 'Remaining time: % days', extract(days from _time_left);

        _new_start_date := new.payment_date::date;
        _new_end_date := _old_end_date + _plan_duration;
        
        raise notice 'Adding remaining time to new subscription. New end date: %', _new_end_date;
        
    
        update general_schema.subscription 
        set is_active = false,
            updated_at = current_timestamp
        where tenant_id = _tenant_id
        and is_active = true;
    else
        _new_start_date := new.payment_date::date;
        _new_end_date := _new_start_date + _plan_duration;
    end if;


    INSERT INTO general_schema.subscription (
        tenant_id,
        subscription_type_id,
        tenant_payment_id,  
        start_date,
        end_date,
        is_active
    ) VALUES (
        _tenant_id,
        _subscription_type_id,
        new.tenant_payment_id,  
        _new_start_date,
        _new_end_date,
        true
    );

    raise notice 'Subscription created for tenant % from % to %', 
                _tenant_id, _new_start_date, _new_end_date;

    return new;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION enable_tenant()
returns trigger as $$
BEGIN

    update general_schema.tenant
    set is_subscribed = true,
        updated_at = current_timestamp
    where tenant_id = new.tenant_id;
    
    raise notice 'Tenant % activated', new.tenant_id;
    
    return new;
end;
$$ language plpgsql;

drop trigger if exists on_payment_verified on general_schema.tenant_payment;
create trigger on_payment_verified
    after update of verified on general_schema.tenant_payment  
    for each row
    when (old.verified is false and new.verified is true)
    execute function general_schema.create_subscription();

drop trigger if exists on_subscription_created on general_schema.subscription;
create trigger on_subscription_created
    after insert on general_schema.subscription
    for each row
    execute function general_schema.enable_tenant();

CREATE OR REPLACE FUNCTION update_timestamp()
returns trigger as $$
BEGIN
    new.updated_at = current_timestamp;
    return new;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION update_product_tsv()
returns trigger as $$
BEGIN
    new.product_name_tsv = to_tsvector('spanish', new.product_name);
    return new;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION general_schema.prevent_category_cycles()
RETURNS TRIGGER AS $$
DECLARE
    v_current_id INTEGER;
    v_visited INTEGER[];
    v_max_iterations INTEGER := 10;
    v_iteration INTEGER := 0;
BEGIN
    IF NEW.parent_category_id IS NULL THEN
        RETURN NEW;
    END IF;
    
    v_current_id := NEW.parent_category_id;
    v_visited := ARRAY[NEW.product_category_id];
    
    WHILE v_current_id IS NOT NULL AND v_iteration < v_max_iterations LOOP
        IF v_current_id = NEW.product_category_id THEN
            RAISE EXCEPTION 'Cycle detected: category % cannot be its own ancestor', 
                NEW.product_category_id;
        END IF;
        
        IF v_current_id = ANY(v_visited) THEN
            RAISE EXCEPTION 'Cycle detected in category hierarchy';
        END IF;
        
        v_visited := array_append(v_visited, v_current_id);
        
        SELECT parent_category_id INTO v_current_id
        FROM general_schema.product_category
        WHERE product_category_id = v_current_id;
        
        v_iteration := v_iteration + 1;
    END LOOP;
    
    IF v_iteration >= v_max_iterations THEN
        RAISE EXCEPTION 'Category hierarchy too deep or contains cycle';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION general_schema.prevent_category_cycles() IS 
    'Validates category hierarchy to prevent circular references (both direct and indirect cycles)';

DROP TRIGGER IF EXISTS trigger_prevent_category_cycles 
    ON general_schema.product_category;
CREATE TRIGGER trigger_prevent_category_cycles
    BEFORE INSERT OR UPDATE OF parent_category_id
    ON general_schema.product_category
    FOR EACH ROW
    EXECUTE FUNCTION general_schema.prevent_category_cycles();


CREATE OR REPLACE FUNCTION general_schema.update_category_hierarchy_level()
RETURNS TRIGGER AS $$
DECLARE
    v_parent_level INTEGER;
BEGIN
    IF NEW.parent_category_id IS NULL THEN
        NEW.hierarchy_level := 0;
    ELSE
        SELECT hierarchy_level INTO v_parent_level
        FROM general_schema.product_category
        WHERE product_category_id = NEW.parent_category_id;
        
        IF v_parent_level IS NULL THEN
            RAISE EXCEPTION 'Parent category % not found', NEW.parent_category_id;
        END IF;
        
        NEW.hierarchy_level := v_parent_level + 1;
        
        IF NEW.hierarchy_level > 5 THEN
            RAISE EXCEPTION 'Maximum category depth exceeded (max 5 levels)';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION general_schema.update_category_hierarchy_level() IS 
    'Automatically calculates and updates hierarchy_level based on parent category. Enforces max depth of 5 levels.';

DROP TRIGGER IF EXISTS trigger_update_category_hierarchy 
    ON general_schema.product_category;
CREATE TRIGGER trigger_update_category_hierarchy
    BEFORE INSERT OR UPDATE OF parent_category_id
    ON general_schema.product_category
    FOR EACH ROW
    EXECUTE FUNCTION general_schema.update_category_hierarchy_level();


CREATE OR REPLACE FUNCTION general_schema.get_subcategories(
    p_parent_category_id INTEGER DEFAULT NULL
)
RETURNS TABLE(
    category_id INTEGER,
    category_name VARCHAR(100),
    parent_id INTEGER,
    level INTEGER,
    full_path TEXT,
    product_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE category_tree AS (
        SELECT 
            pc.product_category_id,
            pc.category_name,
            pc.parent_category_id,
            pc.hierarchy_level,
            0 AS depth,
            pc.category_name::TEXT AS path
        FROM general_schema.product_category pc
        WHERE (p_parent_category_id IS NULL AND pc.parent_category_id IS NULL)
           OR (pc.parent_category_id = p_parent_category_id)
        
        UNION ALL
        
        SELECT 
            pc.product_category_id,
            pc.category_name,
            pc.parent_category_id,
            pc.hierarchy_level,
            ct.depth + 1,
            ct.path || ' > ' || pc.category_name
        FROM general_schema.product_category pc
        INNER JOIN category_tree ct 
            ON pc.parent_category_id = ct.product_category_id
    )
    SELECT 
        ct.product_category_id,
        ct.category_name,
        ct.parent_category_id,
        ct.hierarchy_level,
        ct.path,
        COUNT(p.cabys_code) AS product_count
    FROM category_tree ct
    LEFT JOIN general_schema.product p 
        ON p.product_category_id = ct.product_category_id
    GROUP BY ct.product_category_id, ct.category_name, ct.parent_category_id, 
             ct.hierarchy_level, ct.path, ct.depth
    ORDER BY ct.depth, ct.category_name;
END;
$$ LANGUAGE plpgsql STABLE;

drop trigger if exists update_branch_timestamp on general_schema.branch;
create trigger update_branch_timestamp before update on general_schema.branch
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_product_category_timestamp on general_schema.product_category;
create trigger update_product_category_timestamp before update on general_schema.product_category
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_product_timestamp on general_schema.product;
create trigger update_product_timestamp before update on general_schema.product
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_unit_measure_timestamp on general_schema.unit_measure;
create trigger update_unit_measure_timestamp before update on general_schema.unit_measure
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_commercial_unit_measure_timestamp on general_schema.commercial_unit_measure;
create trigger update_commercial_unit_measure_timestamp before update on general_schema.commercial_unit_measure
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_attribute_value_timestamp on general_schema.attribute_value;
create trigger update_attribute_value_timestamp before update on general_schema.attribute_value
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_product_variant_timestamp on general_schema.product_variant;
create trigger update_product_variant_timestamp before update on general_schema.product_variant
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_tenant_timestamp on general_schema.tenant;
create trigger update_tenant_timestamp before update on general_schema.tenant
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_tenant_customer_timestamp on general_schema.tenant_customer;
create trigger update_tenant_customer_timestamp before update on general_schema.tenant_customer
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_users_timestamp on general_schema.users;
create trigger update_users_timestamp before update on general_schema.users
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_subscription_timestamp on general_schema.subscription;
create trigger update_subscription_timestamp before update on general_schema.subscription
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_tenant_payment_timestamp on general_schema.tenant_payment;
create trigger update_tenant_payment_timestamp before update on general_schema.tenant_payment
for each row execute function general_schema.update_timestamp();