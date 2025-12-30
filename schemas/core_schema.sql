create schema if not exists core;
set search_path to core;

create table if not exists region(
    region_id serial primary key,
    region_name varchar(100) unique not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into region(region_name) values
    ('Costa Rica'),
    ('Panama'),
    ('United States'),
    ('United Kingdom'),
    ('Japan')
on conflict do nothing;

create table if not exists tenant(
    tenant_id uuid primary key default gen_random_uuid(),
    tenant_name varchar(100) unique not null,
    region_id integer references core.region(region_id) on delete set null,
    contact_email varchar(100) not null,
    is_subscribed boolean default false,
    stripe_id varchar(255) unique default null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
alter table core.tenant
    add column if not exists stripe_id varchar(255) unique default null;

create table if not exists branch(
    branch_id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references core.tenant(tenant_id) on delete cascade,
    branch_name varchar(100) not null,
    branch_address text,
    contact_email varchar(100),
    is_main_branch boolean default false,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
create unique index if not exists unique_main_branch_per_tenant 
    on core.branch (tenant_id) 
    where is_main_branch = true;

create table if not exists document_type(
    document_type_id serial primary key, 
    type_name varchar(50) unique not null,
    description text,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into document_type(type_name, description) values
    ('passport', 'International travel document'),
    ('driver_license', 'Official driving permit'),
    ('national_id', 'Government issued identification card')
on conflict do nothing;

create table if not exists customer_segment(
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
    ('inactive', 5)
on conflict do nothing;

create table if not exists customer_segment_margin_type(
    customer_segment_margin_type_id serial primary key,
    type_name varchar(50) unique not null,
    description text,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into customer_segment_margin_type(type_name, description) values
    ('spending_based', 'Discounts based on total spending'),
    ('seniority_based', 'Discounts based on customer seniority'),
    ('frequency_based', 'Discounts based on a monthly basis purchase frequency'),
    ('free_selection', 'Customers can select products for free up to a limit')
on conflict do nothing;

create table if not exists customer_segment_margin(
    customer_segment_margin_id uuid primary key not null default gen_random_uuid(),
    tenant_id uuid not null references core.tenant(tenant_id) on delete cascade,
    customer_segment_id int not null references core.customer_segment(customer_segment_id) on delete cascade,
    customer_segment_margin_type_id int references core.customer_segment_margin_type(customer_segment_margin_type_id) on delete set null,
    spending_threshold numeric(10,2) check (spending_threshold >= 0),
    seniority_months int check (seniority_months >= 0),
    frequency_per_month int check (frequency_per_month >= 0)
);

create table if not exists tenant_customer(
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

alter table core.tenant_customer
    add column if not exists is_tenant boolean not null default false;

create table if not exists role(
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
    ('employee', 1)
on conflict do nothing;

create table if not exists users( 
    user_id uuid primary key default gen_random_uuid(),
    tenant_id uuid references core.tenant(tenant_id) on delete cascade,
    email varchar(100) unique not null,
    password_hash varchar(255) not null,
    role_id integer references core.role(role_id) on delete set null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table if not exists currency(
    currency_id serial primary key,
    currency_code char(3) unique not null,
    currency_name varchar(50) not null,
    symbol varchar(10) not null,
    -- exchange_rate_to_usd numeric(15,6) not null check (exchange_rate_to_usd > 0),
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into currency(currency_code, currency_name, symbol) values
('CRC', 'Costa Rican Colón', '₡'),
('USD', 'US Dollar', '$'),
('EUR', 'Euro', '€'),
('GBP', 'British Pound', '£'),
('JPY', 'Japanese Yen', '¥')
on conflict do nothing;

create table if not exists tax_rate(
    tax_rate_id serial primary key,
    region varchar(100) unique not null,
    region_id integer references core.region(region_id) on delete set null,
    rate_percentage numeric(5,2) not null check (rate_percentage >= 0 and rate_percentage <= 100),
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into core.tax_rate(region, region_id, rate_percentage) values
('CR Standard', (select region_id from core.region where region_name = 'Costa Rica'), 13.00),
('PA Standard', (select region_id from core.region where region_name = 'Panama'), 7.00),
('US Federal', (select region_id from core.region where region_name = 'United States'), 10.00),
('EU Standard', null, 20.00),
('UK Standard', (select region_id from core.region where region_name = 'United Kingdom'), 20.00),
('JP Standard', (select region_id from core.region where region_name = 'Japan'), 8.00)
on conflict do nothing;

create table if not exists subscription_type ( 
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
('Premium', 'Premium subscription plan', 12, 89.99)
on conflict do nothing;

create table if not exists payment_method(
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
('loyalty_points', 'Payment made via loyalty points'),
('credit', 'Payment made through a credit account')
on conflict do nothing;

create table if not exists tenant_payment(
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

create table if not exists subscription(
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

create table if not exists product_category(
    product_category_id serial primary key,
    category_name varchar(100) unique not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table if not exists product(
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

create table if not exists global_attribute (
    global_attribute_id serial primary key,
    attribute_name varchar(100) not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create unique index if not exists unique_attribute_name 
    on core.global_attribute (lower(attribute_name));

create table if not exists tenant_attribute (
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

create table if not exists product_attribute (
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