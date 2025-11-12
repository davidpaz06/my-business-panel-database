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










-- SCHEMA: pos_module   
create schema if not exists pos_module;
set search_path to pos_module;

create table sale(
    sale_id uuid primary key default gen_random_uuid(),
    branch_id uuid not null references core.branch(branch_id) on delete cascade,  
    sale_date timestamp not null default current_timestamp,
    user_id uuid not null references core.users(user_id) on delete set null,
    currency_id integer references core.currency(currency_id) on delete set null,
    total_amount numeric(10,2) not null,
    is_completed boolean default false,
    created_at timestamp not null default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table sale_item(
    sale_item_id uuid primary key default gen_random_uuid(),
    sale_id uuid not null references pos_module.sale(sale_id) on delete cascade,
    tenant_id uuid not null, 
    product_id uuid not null,  
    quantity integer not null check (quantity > 0),
    unit_price numeric(10,2) not null check (unit_price >= 0),
    total_price numeric(10,2) not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp,
    
    foreign key (tenant_id, product_id) 
        references core.product(tenant_id, product_id) 
        on delete restrict
);

create table customer_payment(
    customer_payment_id uuid primary key not null default gen_random_uuid(),
    tenant_customer_id uuid not null references core.tenant_customer(tenant_customer_id) on delete cascade,   
    sale_id uuid not null references pos_module.sale(sale_id) on delete set null,
    payment_method_id integer references core.payment_method(payment_method_id) on delete set null,
    is_points_redemption boolean default false,
    points_redeemed integer default 0 check (points_redeemed >= 0),
    points_to_currency_rate numeric(10,4) default 0 check (points_to_currency_rate >= 0),
    payment_amount numeric(10,2) not null check (payment_amount > 0),
    payment_date timestamp not null default current_timestamp,
    currency_id integer references core.currency(currency_id) on delete set null,
    verified boolean default false,
    created_at timestamp not null default current_timestamp,
    updated_at timestamp default current_timestamp,

    constraint check_points_redemption
    check (
        (is_points_redemption = true and points_redeemed is not null and points_redeemed > 0 and payment_method_id = 4) or
        (is_points_redemption = false)
    )
);


create table bill(
    bill_id uuid primary key default gen_random_uuid(),
    tenant_customer_id uuid references core.tenant_customer(tenant_customer_id) on delete set null,
    currency_id integer references core.currency(currency_id) on delete set null,
    subtotal_amount numeric(10,2) not null check (subtotal_amount >= 0),
    tax_amount numeric(10,2) not null check (tax_amount >= 0),
    total_amount numeric(10,2) not null,    
    billed_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table bill_payment(
    bill_payment_id uuid primary key default gen_random_uuid(),
    bill_id uuid not null references pos_module.bill(bill_id) on delete cascade,
    customer_payment_id uuid not null references pos_module.customer_payment(customer_payment_id) on delete cascade,
    payment_amount numeric(10,2) not null check (payment_amount > 0),
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp,

    unique (bill_id, customer_payment_id)
);

create table bill_product(
    bill_product_id uuid primary key default gen_random_uuid(),
    bill_id uuid not null references pos_module.bill(bill_id) on delete cascade,
    tenant_id uuid not null,
    product_id uuid not null,  
    quantity integer not null check (quantity > 0),
    unit_price numeric(10,2) not null check (unit_price >= 0),
    total_price numeric(10,2) not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp,
    
    foreign key (tenant_id, product_id) 
        references core.product(tenant_id, product_id) 
        on delete restrict
);

create table return_reason(
    return_reason_id serial primary key,
    reason_code varchar(50) unique not null,
    reason_name varchar(100) not null,
    description text,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

insert into return_reason(reason_code, reason_name, description) values
    ('DEFECT', 'Defecto de fábrica', 'El producto tiene un defecto de fabricación'),
    ('SIZE_CHANGE', 'Cambio de talla', 'El cliente requiere una talla diferente'),
    ('WRONG_PRODUCT', 'Producto equivocado', 'Se entregó un producto diferente al solicitado'),
    ('NOT_AS_DESCRIBED', 'No coincide con descripción', 'El producto no coincide con la descripción publicada'),
    ('DAMAGED', 'Producto dañado', 'El producto llegó dañado o roto'),
    ('EXPIRED', 'Producto vencido', 'El producto está vencido o caducado'),
    ('CUSTOMER_REGRET', 'Arrepentimiento', 'El cliente cambió de opinión'),
    ('OTHER', 'Otro motivo', 'Otro motivo no especificado');

create type return_status as enum (
    'pending',      
    'rejected',     
    'processed'
);

create table return_transaction(
    return_transaction_id uuid primary key default gen_random_uuid(),
    bill_id uuid not null references pos_module.bill(bill_id) on delete cascade,
    tenant_customer_id uuid references core.tenant_customer(tenant_customer_id) on delete set null,
    total_refund_amount numeric(10,2) not null check (total_refund_amount >= 0),
    refund_method int references core.payment_method(payment_method_id) on delete set null,
    return_status return_status default 'pending',
    return_date timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table return_product(
    return_product_id uuid primary key default gen_random_uuid(),
    return_transaction_id uuid not null references pos_module.return_transaction(return_transaction_id) on delete cascade,
    bill_product_id uuid not null references pos_module.bill_product(bill_product_id) on delete cascade,
    quantity integer not null check (quantity > 0),
    unit_price numeric(10,2) not null check (unit_price >= 0),
    total_price numeric(10,2) not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table promotion_type(
    promotion_type_id serial primary key,
    type_name varchar(50) unique not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into promotion_type(type_name) values
    ('percentage_discount'),
    ('fixed_amount_discount'),
    ('buy_x_get_y'),
    ('volume_discount'),
    ('tiered_pricing'),
    ('combo'),
    ('free_shipping');

create table promotion(
    promotion_id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references core.tenant(tenant_id) on delete cascade,
    promotion_name varchar(100) not null,
    promotion_code varchar(50) not null,
    promotion_description text,
    promotion_type_id int references pos_module.promotion_type(promotion_type_id) on delete set null,
    customer_segment_id int references core.customer_segment(customer_segment_id) on delete set null,
    promotion_start_date date not null,
    promotion_end_date date not null,
    is_active boolean default false,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp,

    check (promotion_end_date > promotion_start_date)
);

create table promotion_rule(
    promotion_rule_id uuid primary key default gen_random_uuid(),
    promotion_id uuid not null references pos_module.promotion(promotion_id) on delete cascade,
    -- =====================================
    -- Fixed amount or percentage discount
    -- =====================================
    discount_percentage numeric(5,2) check (
        discount_percentage is null or 
        (discount_percentage >= 0 and discount_percentage <= 100)
    ),
    discount_amount numeric(10,2) check (
        discount_amount is null or 
        discount_amount >= 0
    ),
    -- =====================================
    -- Buy X get Y (2x1, 3x2, etc.)
    -- =====================================
    buy_quantity integer,
    get_quantity integer,
    get_discount_percentage numeric(5,2) default 100.00 check (
        get_discount_percentage is null or 
        (get_discount_percentage >= 0 and get_discount_percentage <= 100)
    ),  -- 100% = gratis, 50% = half price
    -- =====================================
    -- Volume discount
    -- =====================================
    min_quantity integer,
    max_quantity integer,
    -- =====================================
    -- Tiered pricing
    -- =====================================
    tier_level integer,
    tier_min_quantity integer,
    tier_max_quantity integer,
    tier_price numeric(10,2),
    tier_discount_percentage numeric(5,2),
    -- =====================================
    -- Minimum purchase amount for promotion
    -- =====================================
    min_purchase_amount numeric(10,2),
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create type discount_result as (
    discount_amount numeric(10,2),
    discount_percentage numeric(5,2),
    rule_description text,
    success boolean
);

create table cash_register(
    cash_register_id uuid primary key default gen_random_uuid(),
    branch_id uuid not null references core.branch(branch_id) on delete cascade,
    user_id uuid not null references core.users(user_id) on delete set null,
    is_active boolean default true,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table cash_register_session(
    cash_register_session_id uuid primary key default gen_random_uuid(),
    cash_register_id uuid not null references pos_module.cash_register(cash_register_id) on delete cascade,
    opened_at timestamp not null default current_timestamp,
    closed_at timestamp,
    opening_amount numeric(10,2) not null check (opening_amount >= 0),
    closing_amount numeric(10,2) check (closing_amount >= 0),
    is_active boolean default true,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table cash_transaction(
    cash_transaction_id uuid primary key default gen_random_uuid(),
    cash_register_session_id uuid not null references pos_module.cash_register_session(cash_register_session_id) on delete cascade,
    transaction_type varchar(50) not null,  
    amount numeric(10,2) not null,
    transaction_time timestamp not null default current_timestamp,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table loyalty_program(
    loyalty_program_id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references core.tenant(tenant_id) on delete cascade,
    points_per_dollar numeric(5,2) not null default 1.00 check (points_per_dollar >= 0),
    points_per_currency_unit numeric(10,2) not null default 100.00 check (points_per_currency_unit > 0),
    minimum_purchase_for_points numeric(10,2) default 0 check (minimum_purchase_for_points >= 0),
    is_active boolean default true,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table tenant_customer_score(
    tenant_id uuid not null references core.tenant(tenant_id) on delete cascade,
    tenant_customer_id uuid not null references core.tenant_customer(tenant_customer_id) on delete cascade,
    score integer not null default 0 check (score >= 0),
    lifetime_score integer not null default 0 check (lifetime_score >= 0),
    score_redeemed integer not null default 0 check (score_redeemed >= 0),
    last_earned_at timestamp,
    last_redeemed_at timestamp,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp,

    primary key (tenant_customer_id, tenant_id)
);

create table score_redemption_status(
    score_redemption_status_id serial primary key,
    status_name varchar(50) unique not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into score_redemption_status(status_name) values
    ('pending'),
    ('rejected'),
    ('processed');

create table score_transaction_type(
    score_transaction_type_id serial primary key,
    type_name varchar(50) unique not null,
    description text,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into score_transaction_type(type_name, description) values
    ('earn', 'Points earned from purchases'),
    ('redeem', 'Points redeemed for rewards'),
    ('adjustment', 'Manual adjustment of points');

create table score_transaction(
    score_transaction_id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references core.tenant(tenant_id) on delete cascade,
    tenant_customer_id uuid not null references core.tenant_customer(tenant_customer_id) on delete cascade,
    transaction_type_id int references pos_module.score_transaction_type(score_transaction_type_id) on delete set null,
    points integer not null,
    bill_id uuid references pos_module.bill(bill_id) on delete set null,
    created_at timestamp default current_timestamp
);

-- =====================================
-- FUNCTIONS AND TRIGGERS
-- =====================================

create or replace function check_sale_payment_completion(_sale_id uuid)
returns boolean as $$
declare
    _sale_total numeric(10,2);
    _payments_total numeric(10,2);
    _is_completed boolean;
    _pending_payments int;
begin
    select total_amount, is_completed into _sale_total, _is_completed
    from pos_module.sale
    where sale_id = _sale_id;
    
    if _sale_total is null then
        raise exception 'Sale not found: %', _sale_id;
    end if;
    
    if _is_completed then
        raise notice '   ℹ️  Sale % is already completed', _sale_id;
        return true;
    end if;
    
    select count(*) into _pending_payments
    from pos_module.customer_payment
    where sale_id = _sale_id
    and verified = false;
    
    if _pending_payments > 0 then
        raise notice '   ⚠️  Sale % has % pending payment(s)', _sale_id, _pending_payments;
        return false;
    end if;
    
    select coalesce(sum(payment_amount), 0) into _payments_total
    from pos_module.customer_payment
    where sale_id = _sale_id
    and verified = true;
    
    raise notice '   💰 Sale total: $%', _sale_total;
    raise notice '   💳 Payments total: $%', _payments_total;
    raise notice '   📊 Difference: $%', (_sale_total - _payments_total);
    
    -- Validar si los pagos cubren el total (tolerancia de $0.01)
    if abs(_payments_total - _sale_total) <= 0.01 then
        update pos_module.sale
        set is_completed = true,
            updated_at = current_timestamp
        where sale_id = _sale_id;
        
        raise notice '   ✅ Sale % marked as COMPLETED', _sale_id;
        return true;
    elsif _payments_total > _sale_total then
        raise warning 'Overpayment detected: Sale total $%, Payments total $%',
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

-- Trigger for bill_product
drop trigger if exists calculate_total_price_bill_product_trigger on pos_module.bill_product;
create trigger calculate_total_price_bill_product_trigger
    before insert or update on pos_module.bill_product
    for each row
    execute function calculate_total_price();

-- Trigger for return_product 
drop trigger if exists calculate_total_price_return_product_trigger on pos_module.return_product;
create trigger calculate_total_price_return_product_trigger
    before insert or update on pos_module.return_product
    for each row
    execute function calculate_total_price();

create or replace function create_bill()
returns trigger as $$
declare
    _bill_id uuid;
    _tenant_customer_id uuid;
    _tenant_id uuid;
    _currency_id integer;
    _total_amount numeric(10,2);
    _payment_ids uuid[];
    _products_count integer;
begin
    raise notice '🧾 Creating bill for sale: %', new.sale_id;
    
    if exists(
        select 1 
        from pos_module.bill_payment bp
        join pos_module.customer_payment cp on bp.customer_payment_id = cp.customer_payment_id
        where cp.sale_id = new.sale_id
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
    _total_amount := new.total_amount;
    
    raise notice '   Customer: %', _tenant_customer_id;
    raise notice '   Tenant: %', _tenant_id;
    raise notice '   Total: $%', _total_amount;

    insert into pos_module.bill (
        tenant_customer_id,
        currency_id,
        subtotal_amount,
        tax_amount,
        total_amount
    ) values (
        _tenant_customer_id,
        _currency_id,
        _total_amount,
        0.00,
        _total_amount
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
    
    insert into pos_module.bill_product(
        bill_id,
        tenant_id,
        product_id,
        quantity,
        unit_price,
        total_price
    )
    select
        _bill_id,
        _tenant_id,
        si.product_id,
        si.quantity,
        si.unit_price,
        si.total_price
    from pos_module.sale_item si
    where si.sale_id = new.sale_id;
    
    get diagnostics _products_count = row_count;
    
    raise notice '   ✅ % product(s) added to bill', _products_count;
    raise notice '';
    raise notice '🎉 Bill creation completed successfully';
    raise notice '   Bill ID: %', _bill_id;
    raise notice '   Products: %', _products_count;
    raise notice '   Payments: %', array_length(_payment_ids, 1);
    raise notice '   Total: $%', _total_amount;

    return new;
    
exception
    when others then
        raise notice '❌ Error creating bill: %', sqlerrm;
        raise notice '   SQLSTATE: %', SQLSTATE;
        return new;
end;
$$ language plpgsql;

drop trigger if exists on_sale_completed on pos_module.sale;
create trigger on_sale_completed
    after update of is_completed on pos_module.sale
    for each row
    when (old.is_completed is false and new.is_completed is true)
    execute function pos_module.create_bill();

create or replace function update_on_return()
returns trigger as $$
declare
_bill_id uuid;
_bill_product_record record;
_total_returned numeric(10,2) := 0;
_original_subtotal numeric(10,2);
_original_tax numeric(10,2);
_original_total numeric(10,2);
_new_subtotal numeric(10,2);
_new_tax numeric(10,2);
_new_total numeric(10,2);
_tax_rate numeric(5,2);
_quantity_remaining integer;
begin
select bp.bill_id into _bill_id
from pos_module.bill_product bp
where bp.bill_product_id = new.bill_product_id;

if _bill_id is null then
    raise exception 'Bill not found for bill_product_id: %', new.bill_product_id;
end if;

raise notice '📄 Bill ID: %', _bill_id;

select 
    bp.bill_product_id,
    bp.quantity,
    bp.unit_price,
    bp.total_price
into _bill_product_record
from pos_module.bill_product bp
where bp.bill_product_id = new.bill_product_id;

raise notice '📦 Original product in bill:';
raise notice '   Quantity: %', _bill_product_record.quantity;
raise notice '   Unit price: $%', _bill_product_record.unit_price;
raise notice '   Total price: $%', _bill_product_record.total_price;

if new.quantity > _bill_product_record.quantity then
    raise exception 'Cannot return more items than purchased. Purchased: %, Attempting to return: %',
        _bill_product_record.quantity, new.quantity;
end if;

_quantity_remaining := _bill_product_record.quantity - new.quantity;

raise notice '🔢 Return quantity: %', new.quantity;
raise notice '🔢 Remaining quantity: %', _quantity_remaining;

if _quantity_remaining = 0 then
    delete from pos_module.bill_product
    where bill_product_id = new.bill_product_id;

    raise notice '🗑️  Product completely removed from bill (quantity = 0)';
else
    update pos_module.bill_product
    set quantity = _quantity_remaining,
        total_price = _quantity_remaining * unit_price,
        updated_at = current_timestamp
    where bill_product_id = new.bill_product_id;

    raise notice '✏️  Product quantity updated from % to %', 
        _bill_product_record.quantity, _quantity_remaining;
end if;

select subtotal_amount, tax_amount, total_amount
into _original_subtotal, _original_tax, _original_total
from pos_module.bill
where bill_id = _bill_id;

raise notice '';
raise notice '📊 Original bill totals:';
raise notice '   Subtotal: $%', _original_subtotal;
raise notice '   Tax: $%', _original_tax;
raise notice '   Total: $%', _original_total;

_total_returned := new.quantity * new.unit_price;

raise notice '';
raise notice '💰 Amount returned: $%', _total_returned;

_new_subtotal := _original_subtotal - _total_returned;

if _new_subtotal < 0 then
    _new_subtotal := 0;
    raise warning 'Subtotal became negative, setting to 0';
end if;

select rate_percentage into _tax_rate
from core.tax_rate
where region = 'US Federal'  -- TODO: Hacer dinámico según tenant
limit 1;

if _tax_rate is null then
    _tax_rate := 0;
    raise warning 'Tax rate not found, using 0%%';
end if;

_new_tax := _new_subtotal * (_tax_rate / 100);
_new_total := _new_subtotal + _new_tax;

raise notice '';
raise notice '📊 New bill totals:';
raise notice '   Subtotal: $%', _new_subtotal;
raise notice '   Tax: $%', _new_tax;
raise notice '   Total: $%', _new_total;

update pos_module.bill
set subtotal_amount = _new_subtotal,
    tax_amount = _new_tax,
    total_amount = _new_total,
    updated_at = current_timestamp
where bill_id = _bill_id;

raise notice '';
raise notice '✅ Bill % updated successfully', _bill_id;

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

create or replace function open_close_cash_register_session(
_cash_register_id uuid,
_action varchar(10), 
_amount numeric(10,2)
) returns void as $$
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
    -- El trigger ahora recibe NEW de bill_payment
    _bill_id := new.bill_id;
    
    -- ✅ Verificar si ya se otorgaron puntos para esta factura
    select exists(
        select 1 
        from pos_module.score_transaction 
        where bill_id = _bill_id 
        and transaction_type_id = 1  -- 'earn'
    ) into _points_already_awarded;
    
    if _points_already_awarded then
        raise notice '   ℹ️  Points already awarded for bill %', _bill_id;
        return new;
    end if;
    
    -- Obtener tenant_customer_id de la factura
    select tenant_customer_id into _tenant_customer_id
    from pos_module.bill
    where bill_id = _bill_id;
    
    if _tenant_customer_id is null then
        raise notice '   ⚠️  No customer found for bill %', _bill_id;
        return new;
    end if;
    
    -- Obtener tenant_id
    select tenant_id into _tenant_id
    from core.tenant_customer
    where tenant_customer_id = _tenant_customer_id;
    
    if _tenant_id is null then
        raise notice '   ⚠️  Tenant not found for customer %', _tenant_customer_id;
        return new;
    end if;
    
    -- ✅ AHORA SÍ: Calcular total de pagos en efectivo/tarjeta (los datos YA EXISTEN)
    select coalesce(sum(cp.payment_amount), 0) into _cash_payments_total
    from pos_module.bill_payment bp
    join pos_module.customer_payment cp on bp.customer_payment_id = cp.customer_payment_id
    where bp.bill_id = _bill_id
    and cp.is_points_redemption = false;
    
    raise notice '💵 Cash/card payments total: $%', _cash_payments_total;
    
    -- Calcular puntos
    _points_earned := pos_module.calculate_purchase_score(
        _tenant_id,
        _tenant_customer_id,
        _cash_payments_total
    );
    
    if _points_earned <= 0 then
        raise notice '   ℹ️  No points earned for this purchase (Bill: %)', _bill_id;
        return new;
    end if;
    
    -- Otorgar puntos
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
    
    -- Registrar transacción
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
        1,  -- 'earn'
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
        2,  -- 'redeem'
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

drop trigger if exists update_bill_product_timestamp on pos_module.bill_product;
create trigger update_bill_product_timestamp before update on pos_module.bill_product
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

drop trigger if exists update_cash_transaction_timestamp on pos_module.cash_transaction;
create trigger update_cash_transaction_timestamp before update on pos_module.cash_transaction
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


