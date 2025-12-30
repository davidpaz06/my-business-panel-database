-- SCHEMA: supplies
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
    subtotal_amount numeric(12,3) default 0,
    tax_amount numeric(12,3) default 0,
    total_amount numeric(12,3) generated always as (subtotal_amount + tax_amount) stored,
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
    -- supply_order_id uuid not null unique references supplies_module.supply_order(supply_order_id) on delete cascade,
    has_invoice boolean default true,
    has_tax boolean default true,
    subtotal_amount numeric(12,3) default 0,  
    -- tax_amount numeric(12,3) default 0,       
    -- amount_due numeric(12,3) generated always as (subtotal_amount + tax_amount) stored,  -- ✅ Total con tax
    amount_paid numeric(12,3) default 0,
    -- balance_remaining numeric(12,3) generated always as (subtotal_amount + tax_amount - amount_paid) stored,  -- ✅ Incluye tax
    -- due_date date not null,
    -- account_status integer not null default 1 references supplies_module.account_payable_status(status_id),
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
    ('Overdue Payment', 'Alert for overdue payments'),
    ('Reconciliation Mismatch', 'Alert for payment reconciliation issues')
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
