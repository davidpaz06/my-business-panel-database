create schema if not exists inventory_module;
set search_path to inventory_module;

create table warehouse(
    warehouse_id uuid primary key default gen_random_uuid(),
    branch_id uuid not null references core.branch(branch_id) on delete cascade,
    warehouse_name varchar(255) not null,
    warehouse_address text not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table inventory(
    inventory_id uuid primary key default gen_random_uuid(),
    product_id uuid not null references core.product(product_id) on delete cascade,
    warehouse_id uuid not null references inventory_module.warehouse(warehouse_id) on delete cascade,
    stock integer not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table inventory_movement_type(
    inventory_movement_type_id serial primary key,
    inventory_movement_type_name varchar(50) not null unique, 
    inventory_movement_type_description text,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into inventory_movement_type (inventory_movement_type_name, inventory_movement_type_description) values
('IN', 'inventory added to inventory_module'),
('OUT', 'inventory removed from inventory_module'),

create table inventory_movement(
    inventory_movement_id uuid primary key default gen_random_uuid(),
    inventory_movement_type_id integer not null references inventory_module.inventory_movement_type(inventory_movement_type_id) on delete cascade,
    supply_order_id uuid references supplies.supply_order(supply_order_id) on delete set null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table inventory_transfer(
    inventory_transfer_id uuid primary key default gen_random_uuid(),
    from_warehouse_id uuid not null references inventory_module.warehouse(warehouse_id) on delete cascade,
    to_warehouse_id uuid not null references inventory_module.warehouse(warehouse_id) on delete cascade,
    inventory_transfer_departure_date timestamp default current_timestamp,
    inventory_transfer_arrival_date timestamp,
    transfer_date timestamp default current_timestamp,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table inventory_transfer_product(
    inventory_transfer_product_id uuid primary key default gen_random_uuid(),
    inventory_transfer_id uuid not null references inventory_module.inventory_transfer(inventory_transfer_id) on delete cascade,
    product_id uuid not null references core.product(product_id) on delete cascade,
    quantity integer not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);


-- ==========================================================================
--                          FUNCTIONS AND TRIGGERS
-- ==========================================================================
