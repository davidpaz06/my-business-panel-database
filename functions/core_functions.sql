create or replace procedure core.verify_tenant_payment(_payment_id uuid)
language plpgsql
as $$
declare
    _exists boolean;
    _already_verified boolean;
    _rows_updated int;
    _tenant_id uuid;
begin
    select exists(
        select 1 
        from core.tenant_payment 
        where tenant_payment_id = _payment_id
    ) into _exists;
    
    if not _exists then
        raise notice 'Payment with id: % does not exist.', _payment_id;
        raise exception 'Payment not found: %', _payment_id;
    end if;

    select coalesce(verified, false), tenant_id 
    into _already_verified, _tenant_id
    from core.tenant_payment 
    where tenant_payment_id = _payment_id;
    
    if _already_verified then
        raise notice 'Payment % is already verified.', _payment_id;
        return;
    end if;

    update core.tenant_payment
    set verified = true,
        updated_at = current_timestamp
    where tenant_payment_id = _payment_id
    and coalesce(verified, false) = false;
    
    get diagnostics _rows_updated = row_count;
    
    if _rows_updated > 0 then

        raise notice '✅ Payment verified successfully: %', _payment_id;
        raise notice 'Tenant: %', _tenant_id;
        raise notice 'Trigger will create subscription automatically';

    else
        raise notice 'No rows updated for payment: %', _payment_id;
        raise exception 'Failed to verify payment: %', _payment_id;
    end if;
        
exception
    when others then
        raise notice '❌ Payment verification failed: %', sqlerrm;
        raise;
end
$$;




create or replace function core.create_subscription()
returns trigger as $$
declare
    _subscription_type_id int;
    _exists boolean;
    _old_end_date date;
    _time_left interval;
    _new_start_date date;
    _new_end_date date;
    _tenant_id uuid;
    _plan_duration interval;
begin
    _tenant_id := new.tenant_id;


    select exists(
        select 1 
        from core.subscription 
        where tenant_payment_id = new.tenant_payment_id  
    ) into _exists;
    
    if _exists then
        raise notice 'Subscription already exists for payment: %', new.tenant_payment_id;
        return new;
    end if;


    select end_date into _old_end_date
    from core.subscription
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
    from core.subscription_type
    where subscription_type_id = _subscription_type_id;

    if _old_end_date is not null and _old_end_date > new.payment_date::date then
        _time_left := _old_end_date - new.payment_date::date;
        raise notice 'Remaining time: % days', extract(days from _time_left);

        _new_start_date := new.payment_date::date;
        _new_end_date := _old_end_date + _plan_duration;
        
        raise notice 'Adding remaining time to new subscription. New end date: %', _new_end_date;
        
    
        update core.subscription 
        set is_active = false,
            updated_at = current_timestamp
        where tenant_id = _tenant_id
        and is_active = true;
    else
        _new_start_date := new.payment_date::date;
        _new_end_date := _new_start_date + _plan_duration;
    end if;


    insert into core.subscription (
        tenant_id,
        subscription_type_id,
        tenant_payment_id,  
        start_date,
        end_date,
        is_active
    ) values (
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

create or replace function core.enable_tenant()
returns trigger as $$
begin

    update core.tenant
    set is_subscribed = true,
        updated_at = current_timestamp
    where tenant_id = new.tenant_id;
    
    raise notice 'Tenant % activated', new.tenant_id;
    
    return new;
end;
$$ language plpgsql;

drop trigger if exists on_payment_verified on core.tenant_payment;
create trigger on_payment_verified
    after update of verified on core.tenant_payment  
    for each row
    when (old.verified is false and new.verified is true)
    execute function core.create_subscription();

drop trigger if exists on_subscription_created on core.subscription;
create trigger on_subscription_created
    after insert on core.subscription
    for each row
    execute function core.enable_tenant();

create or replace function core.update_timestamp()
returns trigger as $$
begin
    new.updated_at = current_timestamp;
    return new;
end;
$$ language plpgsql;

create or replace function core.update_product_tsv()
returns trigger as $$
begin
    new.product_name_tsv = to_tsvector('spanish', new.product_name);
    return new;
end;
$$ language plpgsql;

drop trigger if exists update_branch_timestamp on core.branch;
create trigger update_branch_timestamp before update on core.branch
for each row execute function core.update_timestamp();

drop trigger if exists update_product_category_timestamp on core.product_category;
create trigger update_product_category_timestamp before update on core.product_category
for each row execute function core.update_timestamp();

drop trigger if exists update_product_tsv on core.product;
create trigger update_product_tsv before insert or update on core.product
for each row execute function core.update_product_tsv();

drop trigger if exists update_product_timestamp on core.product;
create trigger update_product_timestamp before update on core.product
for each row execute function core.update_timestamp();

drop trigger if exists update_product_attribute_timestamp on core.product_attribute;
create trigger update_product_attribute_timestamp before update on core.product_attribute
for each row execute function core.update_timestamp();

drop trigger if exists update_tenant_timestamp on core.tenant;
create trigger update_tenant_timestamp before update on core.tenant
for each row execute function core.update_timestamp();

drop trigger if exists update_tenant_customer_timestamp on core.tenant_customer;
create trigger update_tenant_customer_timestamp before update on core.tenant_customer
for each row execute function core.update_timestamp();

drop trigger if exists update_users_timestamp on core.users;
create trigger update_users_timestamp before update on core.users
for each row execute function core.update_timestamp();

drop trigger if exists update_subscription_timestamp on core.subscription;
create trigger update_subscription_timestamp before update on core.subscription
for each row execute function core.update_timestamp();

drop trigger if exists update_tenant_payment_timestamp on core.tenant_payment;
create trigger update_tenant_payment_timestamp before update on core.tenant_payment
for each row execute function core.update_timestamp();