-- SCHEMA: supplies
create schema if not exists supplies;
set search_path to supplies;

create table supplier(
    supplier_id uuid primary key default gen_random_uuid(),
    branch_id uuid not null references core.branch(branch_id) on delete cascade,
    supplier_name varchar(255) not null,
    supplier_contact_info text,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table supply_order(
    supply_order_id uuid primary key default gen_random_uuid(),
    supplier_id uuid not null references supplier(supplier_id) on delete cascade,
    warehouse_id uuid not null references inventory.warehouse(warehouse_id) on delete cascade,
    supply_order_date timestamp default current_timestamp,
    expected_delivery_date timestamp,
    supply_order_status varchar(50) not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table supply_order_item(
    supply_order_item_id uuid primary key default gen_random_uuid(),
    supply_order_id uuid not null references supply_order(supply_order_id) on delete cascade,
    product_id uuid not null references core.product(product_id) on delete cascade,
    quantity integer not null,
    unit_price numeric(10,2) not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table supply_receipt(
    supply_receipt_id uuid primary key default gen_random_uuid(),
    supply_order_id uuid not null references supply_order(supply_order_id) on delete cascade,
    receipt_date timestamp default current_timestamp,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table account_type(
    account_type_id serial primary key,
    account_type_name varchar(50) not null unique, 
    account_type_description text,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into account_type (account_type_name, account_type_description) values
('payable', 'Accounts payable'),
('receivable', 'Accounts receivable');

create table account(
    account_id uuid primary key default gen_random_uuid(),
    supply_order_id uuid references supply_order(supply_order_id) on delete set null,
    account_type_id integer not null references supplies.account_type(account_type_id) on delete cascade,
    account_balance numeric(15,2) default 0.00,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

