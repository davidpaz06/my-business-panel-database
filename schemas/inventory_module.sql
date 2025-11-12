-- SCHEMA: inventory 
create schema if not exists inventory;
set search_path to inventory;

create table warehouse(
    warehouse_id uuid primary key default gen_random_uuid(),
    branch_id uuid not null references core.branch(branch_id) on delete cascade,
    warehouse_name varchar(255) not null,
    warehouse_address text not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table stock(
    stock_id uuid primary key default gen_random_uuid(),
    product_id uuid not null references core.product(product_id) on delete cascade,
    warehouse_id uuid not null references inventory.warehouse(warehouse_id) on delete cascade,
    quantity integer not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table stock_movement_type(
    stock_movement_type_id serial primary key,
    stock_movement_type_name varchar(50) not null unique, 
    stock_movement_type_description text,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into stock_movement_type (stock_movement_type_name, stock_movement_type_description) values
('IN', 'Stock added to inventory'),
('OUT', 'Stock removed from inventory'),

create table stock_movement(
    stock_movement_id uuid primary key default gen_random_uuid(),
    stock_movement_type_id integer not null references inventory.stock_movement_type(stock_movement_type_id) on delete cascade,
    supply_order_id uuid references supplies.supply_order(supply_order_id) on delete set null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table stock_transfer(
    stock_transfer_id uuid primary key default gen_random_uuid(),
    from_warehouse_id uuid not null references inventory.warehouse(warehouse_id) on delete cascade,
    to_warehouse_id uuid not null references inventory.warehouse(warehouse_id) on delete cascade,
    stock_transfer_departure_date timestamp default current_timestamp,
    stock_transfer_arrival_date timestamp,
    transfer_date timestamp default current_timestamp,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table stock_transfer_product(
    stock_transfer_product_id uuid primary key default gen_random_uuid(),
    stock_transfer_id uuid not null references inventory.stock_transfer(stock_transfer_id) on delete cascade,
    product_id uuid not null references core.product(product_id) on delete cascade,
    quantity integer not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

