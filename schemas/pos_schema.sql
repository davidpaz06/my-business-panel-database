create schema if not exists pos_module;
set search_path to pos_module;

create table if not exists sale(
    sale_id uuid primary key default gen_random_uuid(),
    branch_id uuid not null references core.branch(branch_id) on delete cascade,  
    sale_date timestamp not null default current_timestamp,
    currency_id integer references core.currency(currency_id) on delete set null,
    subtotal_amount numeric(10,2) not null default 0 check (subtotal_amount >= 0),
    tax_amount numeric(10,2) not null default 0 check (tax_amount >= 0),
    total_amount numeric(10,2) not null,
    is_completed boolean default false,
    created_at timestamp not null default current_timestamp,
    updated_at timestamp default current_timestamp
);
create index if not exists idx_sale_branch_id on pos_module.sale(branch_id);
create index if not exists idx_sale_sale_date on pos_module.sale(sale_date);

create table if not exists sale_item(
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
create index if not exists idx_sale_item_product_id on pos_module.sale_item(product_id);
create index if not exists idx_sale_item_sale_id on pos_module.sale_item(sale_id);
create index if not exists idx_sale_item_tenant_product on pos_module.sale_item(tenant_id, product_id);

create table if not exists cash_register(
    cash_register_id uuid primary key default gen_random_uuid(),
    branch_id uuid not null references core.branch(branch_id) on delete cascade,
    is_active boolean default true,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table if not exists cash_register_session(
    cash_register_session_id uuid primary key default gen_random_uuid(),
    cash_register_id uuid not null references pos_module.cash_register(cash_register_id) on delete cascade,
    user_id uuid not null references core.users(user_id) on delete set null,
    opened_at timestamp not null default current_timestamp,
    closed_at timestamp,
    opening_amount numeric(10,2) not null check (opening_amount >= 0),
    closing_amount numeric(10,2) check (closing_amount >= 0),
    is_active boolean default true,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table if not exists cash_register_sale(
    cash_register_sale_id uuid primary key default gen_random_uuid(),
    cash_register_session_id uuid not null references pos_module.cash_register_session(cash_register_session_id) on delete cascade,
    sale_id uuid not null unique references pos_module.sale(sale_id) on delete cascade, 
    transaction_time timestamp not null default current_timestamp,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table if not exists customer_payment(
    customer_payment_id uuid primary key not null default gen_random_uuid(),
    tenant_customer_id uuid not null references core.tenant_customer(tenant_customer_id) on delete cascade,   
    sale_id uuid not null references pos_module.sale(sale_id) on delete cascade,
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

create table if not exists bill(
    bill_id uuid primary key default gen_random_uuid(),
    tenant_customer_id uuid references core.tenant_customer(tenant_customer_id) on delete set null,
    sale_id uuid not null references pos_module.sale(sale_id) on delete cascade,
    currency_id integer references core.currency(currency_id) on delete set null,
    subtotal_amount numeric(10,2) not null check (subtotal_amount >= 0),
    tax_amount numeric(10,2) not null check (tax_amount >= 0),
    total_amount numeric(10,2) not null,    
    billed_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
alter table pos_module.bill
    add column if not exists due_date date;
create index if not exists idx_bill_sale_id on pos_module.bill(sale_id);

create table if not exists bill_payment(
    bill_payment_id uuid primary key default gen_random_uuid(),
    bill_id uuid not null references pos_module.bill(bill_id) on delete cascade,
    customer_payment_id uuid not null references pos_module.customer_payment(customer_payment_id) on delete cascade,
    payment_amount numeric(10,2) not null check (payment_amount > 0),
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp,

    unique (bill_id, customer_payment_id)
);

create table if not exists return_reason(
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
    ('WRonG_PRODUCT', 'Producto equivocado', 'Se entregó un producto diferente al solicitado'),
    ('NOT_AS_DESCRIBED', 'No coincide con descripción', 'El producto no coincide con la descripción publicada'),
    ('DAMAGED', 'Producto dañado', 'El producto llegó dañado o roto'),
    ('EXPIRED', 'Producto vencido', 'El producto está vencido o caducado'),
    ('CUSTOMER_REGRET', 'Arrepentimiento', 'El cliente cambió de opinión'),
    ('OTHER', 'Otro motivo', 'Otro motivo no especificado')
on conflict do nothing;

create table if not exists return_status(
    return_status_id serial primary key,
    status_name varchar(50) unique not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into return_status(status_name) values
    ('pending'),
    ('rejected'),
    ('processed')
on conflict do nothing;

drop table if exists return_transaction cascade;
create table if not exists return_transaction(
    return_transaction_id uuid primary key default gen_random_uuid(),
    bill_id uuid not null references pos_module.bill(bill_id) on delete cascade,
    tenant_customer_id uuid references core.tenant_customer(tenant_customer_id) on delete set null,
    total_refund_amount numeric(10,2) not null check (total_refund_amount >= 0),
    refund_method int references core.payment_method(payment_method_id) on delete set null,
    return_status_id integer references pos_module.return_status(return_status_id) on delete set null,
    return_date timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
create index if not exists idx_return_transaction_bill_id on pos_module.return_transaction(bill_id);
create index if not exists idx_return_transaction_date on pos_module.return_transaction(return_date);

create table if not exists return_product(
    return_product_id uuid primary key default gen_random_uuid(),
    return_transaction_id uuid not null references pos_module.return_transaction(return_transaction_id) on delete cascade,
    sale_item_id uuid not null references pos_module.sale_item(sale_item_id) on delete cascade,
    quantity integer not null check (quantity > 0),
    unit_price numeric(10,2) not null check (unit_price >= 0),
    total_price numeric(10,2) not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
create index if not exists idx_return_product_transaction_id on pos_module.return_product(return_transaction_id);

create table if not exists promotion_type(
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
    ('free_shipping')
on conflict do nothing;

create table if not exists promotion(
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

create table if not exists promotion_rule(
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

drop type if exists discount_result cascade;
create type discount_result as (
    discount_amount numeric(10,2),
    discount_percentage numeric(5,2),
    rule_description text,
    success boolean
);

create table if not exists loyalty_program(
    loyalty_program_id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references core.tenant(tenant_id) on delete cascade,
    points_earned_per_currency_unit numeric(5,2) not null default 1.00 check (points_earned_per_currency_unit >= 0),
    points_redeemed_per_currency_unit numeric(10,2) not null default 100.00 check (points_redeemed_per_currency_unit > 0),
    minimum_purchase_for_points numeric(10,2) default 0 check (minimum_purchase_for_points >= 0),
    is_active boolean default true,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table if not exists tenant_customer_score(
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

create table if not exists score_redemption_status(
    score_redemption_status_id serial primary key,
    status_name varchar(50) unique not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into score_redemption_status(status_name) values
    ('pending'),
    ('rejected'),
    ('processed')
on conflict do nothing;

create table if not exists score_transaction_type(
    score_transaction_type_id serial primary key,
    type_name varchar(50) unique not null,
    description text,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into score_transaction_type(type_name, description) values
    ('earn', 'Points earned from purchases'),
    ('redeem', 'Points redeemed for rewards'),
    ('adjustment', 'Manual adjustment of points')
on conflict do nothing;

create table if not exists score_transaction(
    score_transaction_id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references core.tenant(tenant_id) on delete cascade,
    tenant_customer_id uuid not null references core.tenant_customer(tenant_customer_id) on delete cascade,
    transaction_type_id int references pos_module.score_transaction_type(score_transaction_type_id) on delete set null,
    points integer not null,
    bill_id uuid references pos_module.bill(bill_id) on delete set null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table if not exists debtor (
    debtor_id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references core.tenant(tenant_id) on delete cascade,
    debt numeric(10, 2) not null default 0.00, -- Add check (debt >= 0) ?
    missed_payments integer not null default 0
)