-- SCHEMA: core schema for common tables
create schema if not exists core;
set search_path to core;

create table tenant(
    tenant_id uuid primary key default gen_random_uuid(),
    tenant_name varchar(100) unique not null,
    contact_email varchar(100) not null,
    is_subscribed boolean default false,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
    -- TODO: preguntar si se necesita más info sobre el tenant
);

create table branch(
    branch_id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references core.tenant(tenant_id) on delete cascade,
    branch_name varchar(100) not null,
    address text,
    contact_email varchar(100),
    is_main_branch boolean default false,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
create unique index unique_main_branch_per_tenant 
    on core.branch (tenant_id) 
    where is_main_branch = true;

create table document_type(
    document_type_id serial primary key, 
    type_name varchar(50) unique not null,
    description text,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into document_type(type_name, description) values
    ('passport', 'International travel document'),
    ('driver_license', 'Official driving permit'),
    ('national_id', 'Government issued identification card');

    create table customer_segment(
    customer_segment_id serial primary key,
    segment_name varchar(100) unique not null,
    segment_hierarchy integer not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into customer_segment(segment_name, segment_hierarchy) values
    ('vip', 1),
    ('loyal', 2),
    ('regular', 3),
    ('new', 4),
    ('inactive', 5);

create table customer_segment_margin_type(
    customer_segment_margin_type_id serial primary key,
    type_name varchar(50) unique not null,
    description text,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into customer_segment_margin_type(type_name, description) values
    ('spending_based', 'Discounts based on total spending'),
    ('seniority_based', 'Discounts based on customer seniority'),
    ('frequency_based', 'Discounts based on a monthly basis purchase frequency');

create table customer_segment_margin(
    customer_segment_margin_id uuid primary key not null default gen_random_uuid(),
    tenant_id uuid not null references core.tenant(tenant_id) on delete cascade,
    customer_segment_id int not null references core.customer_segment(customer_segment_id) on delete cascade,
    customer_segment_margin_type_id int references core.customer_segment_margin_type(customer_segment_margin_type_id) on delete set null,
    spending_threshold numeric(10,2) check (spending_threshold >= 0),
    seniority_months int check (seniority_months >= 0),
    frequency_per_month int check (frequency_per_month >= 0)
);

-- n:m table to link customers to tenants
create table tenant_customer(
    tenant_customer_id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references core.tenant(tenant_id) on delete cascade,  
    first_name varchar(100) not null,
    last_name varchar(100) not null,
    document_type_id integer references core.document_type(document_type_id) on delete set null,  
    document_number varchar(50) not null,
    email varchar(255) not null,
    phone varchar(50) not null,
    birthdate date,
    address text,
    customer_segment_id int default 4 references core.customer_segment(customer_segment_id) on delete set null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp,
    
    unique(tenant_id, document_number),   
    unique(tenant_id, email),             
    unique(tenant_id, phone)    
);

create table role(
    role_id serial primary key,
    role_name varchar(50) unique not null,
    role_hierarchy integer not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into role(role_name, role_hierarchy) values
    ('superuser', 4),
    ('admin', 3),
    ('manager', 2),
    ('employee', 1);

create table users( 
    user_id uuid primary key default gen_random_uuid(),
    tenant_id uuid references core.tenant(tenant_id) on delete cascade,
    email varchar(100) unique not null,
    password_hash varchar(255) not null,
    role_id integer references core.role(role_id) on delete set null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table currency(
    currency_id serial primary key,
    currency_id_code char(3) unique not null,
    currency_name varchar(50) not null,
    symbol varchar(10) not null,
    exchange_rate_to_usd numeric(15,6) not null check (exchange_rate_to_usd > 0),
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into currency(currency_id_code, currency_name, symbol, exchange_rate_to_usd) values
('USD', 'US Dollar', '$', 1.000000),
('EUR', 'Euro', '€', 1.100000),
('GBP', 'British Pound', '£', 1.250000),
('JPY', 'Japanese Yen', '¥', 0.009000);

create table tax_rate(
    tax_rate_id serial primary key,
    region varchar(100) unique not null,
    rate_percentage numeric(5,2) not null check (rate_percentage >= 0 and rate_percentage <= 100),
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into tax_rate(region, rate_percentage) values
('US Federal', 10.00),
('EU Standard', 20.00),
('UK Standard', 20.00),
('JP Standard', 8.00);

create table subscription_type ( 
    subscription_type_id serial primary key,
    subscription_type_name varchar(25) not null,
    subscription_type_detail text not null,
    duration_months int not null,
    subscription_type_cost numeric(5,2)
    -- TODO: corroborar como se gestionarán las suscripciones del SaaS
);
insert into subscription_type (subscription_type_name, subscription_type_detail, duration_months, subscription_type_cost) values
('Basic', 'Basic subscription plan', 1, 9.99),
('Standard', 'Standard subscription plan', 6, 49.99),
('Premium', 'Premium subscription plan', 12, 89.99);

create table payment_method(
    payment_method_id serial primary key,
    name varchar(50) unique not null,
    description text,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into payment_method(name, description) values
('cash', 'Payment made with cash'),
('debit_card', 'Payment made with debit card'),
('credit_card', 'Payment made with credit card'),
('loyalty_points', 'Payment made via loyalty points');

create table tenant_payment(
    tenant_payment_id uuid primary key default gen_random_uuid(),
    tenant_id uuid references core.tenant(tenant_id) on delete cascade,
    payment_method_id integer references core.payment_method(payment_method_id) on delete set null,
    payment_amount numeric(10,2) not null check (payment_amount >= 0),
    payment_date timestamp default current_timestamp,
    details varchar(255),
    verified boolean default false,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table subscription(
    subscription_id uuid primary key default gen_random_uuid(),
    tenant_id uuid references core.tenant(tenant_id) on delete cascade,
    subscription_type_id integer references core.subscription_type(subscription_type_id) on delete set null,
    tenant_payment_id uuid references core.tenant_payment(tenant_payment_id) on delete set null,
    start_date date not null,
    end_date date not null,
    is_active boolean default true,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp,
    
    check (end_date > start_date)
);

create table product_category(
    product_category_id serial primary key,
    category_name varchar(100) unique not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table product(
    tenant_id uuid not null references core.tenant(tenant_id) on delete cascade,
    product_id uuid not null default gen_random_uuid(),
    sku varchar(50) not null,
    product_name varchar(100) not null,
    product_name_tsv tsvector generated always as (to_tsvector('spanish', product_name)) stored,
    product_description text,
    product_category_id int references core.product_category(product_category_id) on delete set null,
    unit_price numeric(10,2) not null check (unit_price >= 0),
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp,

    primary key (tenant_id, product_id)   
) partition by hash (tenant_id);
do $$
declare
    i int;
begin
    for i in 0..7 loop
        execute format(
            'create table if not exists core.product_p%s partition of core.product for values with (modulus 8, remainder %s);'
            , i, i);
    end loop;
end;
$$ language plpgsql;
create unique index if not exists idx_product_tenant_sku on core.product(tenant_id, sku);
create index if not exists idx_product_tenant_btree on core.product(tenant_id);
create index if not exists idx_product_name_fts on core.product using gin ( product_name_tsv );

create table global_attribute (
    global_attribute_id serial primary key,
    attribute_name varchar(100) not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create unique index unique_attribute_name 
    on core.global_attribute (lower(attribute_name));

create table tenant_attribute (
    tenant_attribute_id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references core.tenant(tenant_id) on delete cascade,
    global_attribute_id int references core.global_attribute(global_attribute_id) on delete set null,
    attribute_name varchar(100) not null,
    is_custom boolean default false,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp,

    check (
        (global_attribute_id is not null and is_custom = false) or
        (global_attribute_id is null and is_custom = true)
    )
);

create unique index if not exists unique_tenant_attribute_name 
    on core.tenant_attribute (tenant_id, lower(attribute_name));

create table product_attribute (
    tenant_id uuid not null references core.tenant(tenant_id) on delete cascade,
    product_id uuid not null,
    tenant_attribute_id uuid not null references core.tenant_attribute(tenant_attribute_id) on delete cascade,
    value text not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp,

    primary key (tenant_id, product_id, tenant_attribute_id),

    foreign key (tenant_id, product_id) 
        references core.product(tenant_id, product_id) 
        on delete cascade
);

-- =====================================
-- FUNCTIONS AND TRIGGERS
-- =====================================

create or replace procedure verify_tenant_payment(_payment_id uuid)
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
        from tenant_payment 
        where tenant_payment_id = _payment_id
    ) into _exists;
    
    if not _exists then
        raise notice 'Payment with id: % does not exist.', _payment_id;
        raise exception 'Payment not found: %', _payment_id;
    end if;

    select coalesce(verified, false), tenant_id 
    into _already_verified, _tenant_id
    from tenant_payment 
    where tenant_payment_id = _payment_id;
    
    if _already_verified then
        raise notice 'Payment % is already verified.', _payment_id;
        return;
    end if;

    update tenant_payment
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

create or replace function create_subscription()
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
        from subscription 
        where tenant_payment_id = new.tenant_payment_id  
    ) into _exists;
    
    if _exists then
        raise notice 'Subscription already exists for payment: %', new.tenant_payment_id;
        return new;
    end if;

    select end_date into _old_end_date
    from subscription
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
    from subscription_type
    where subscription_type_id = _subscription_type_id;

    if _old_end_date is not null and _old_end_date > new.payment_date::date then
        _time_left := _old_end_date - new.payment_date::date;
        raise notice 'Remaining time: % days', extract(days from _time_left);

        _new_start_date := new.payment_date::date;
        _new_end_date := _old_end_date + _plan_duration;
        
        raise notice 'Adding remaining time to new subscription. New end date: %', _new_end_date;
        
        update subscription 
        set is_active = false,
            updated_at = current_timestamp
        where tenant_id = _tenant_id
        and is_active = true;
    else
        _new_start_date := new.payment_date::date;
        _new_end_date := _new_start_date + _plan_duration;
    end if;

    insert into subscription (
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

drop trigger if exists on_payment_verified on tenant_payment;
create trigger on_payment_verified
    after update of verified on tenant_payment  
    for each row
    when (old.verified is false and new.verified is true)
    execute function create_subscription();

create or replace function enable_tenant()
returns trigger as $$
begin
    update tenant
    set is_subscribed = true,
        updated_at = current_timestamp
    where tenant_id = new.tenant_id;
    
    raise notice 'Tenant % activated', new.tenant_id;
    
    return new;
end;
$$ language plpgsql;

drop trigger if exists on_subscription_created on subscription;
create trigger on_subscription_created
    after insert on subscription
    for each row
    execute function enable_tenant();

create or replace function update_timestamp()
returns trigger as $$
begin
    new.updated_at = current_timestamp;
    return new;
end;
$$ language plpgsql;

create or replace function update_product_tsv()
returns trigger as $$
begin
    new.product_name_tsv = to_tsvector('spanish', new.product_name);
    return new;
end;
$$ language plpgsql;

drop trigger if exists update_branch_timestamp on core.branch;
create trigger update_branch_timestamp before update on core.branch
for each row execute function update_timestamp();

drop trigger if exists update_product_category_timestamp on core.product_category;
create trigger update_product_category_timestamp before update on core.product_category
for each row execute function update_timestamp();

drop trigger if exists update_product_tsv on core.product;
create trigger update_product_tsv before insert or update on core.product
for each row execute function update_product_tsv();

drop trigger if exists update_product_timestamp on core.product;
create trigger update_product_timestamp before update on core.product
for each row execute function update_timestamp();

drop trigger if exists update_product_attribute_timestamp on core.product_attribute;
create trigger update_product_attribute_timestamp before update on core.product_attribute
for each row execute function update_timestamp();

drop trigger if exists update_tenant_timestamp on tenant;
create trigger update_tenant_timestamp before update on tenant
for each row execute function update_timestamp();

drop trigger if exists update_tenant_customer_timestamp on tenant_customer;
create trigger update_tenant_customer_timestamp before update on tenant_customer
for each row execute function update_timestamp();

drop trigger if exists update_users_timestamp on users;
create trigger update_users_timestamp before update on users
for each row execute function update_timestamp();

drop trigger if exists update_subscription_timestamp on subscription;
create trigger update_subscription_timestamp before update on subscription
for each row execute function update_timestamp();

drop trigger if exists update_tenant_payment_timestamp on tenant_payment;
create trigger update_tenant_payment_timestamp before update on tenant_payment
for each row execute function update_timestamp();
