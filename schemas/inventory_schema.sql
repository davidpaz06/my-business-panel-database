create schema if not exists inventory_module;
set search_path to inventory_module;

create table if not exists warehouse (
    warehouse_id uuid primary key default gen_random_uuid(),
    branch_id uuid not null references core.branch(branch_id) on delete cascade,
    warehouse_name varchar(255) not null,
    warehouse_address text not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table if not exists inventory(
    inventory_id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null,                                                         
    product_id uuid not null,
    warehouse_id uuid not null references inventory_module.warehouse(warehouse_id) on delete cascade,
    stock integer not null,
    expiration_date timestamp check (expiration_date is null or expiration_date > current_timestamp),
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp,

    foreign key (tenant_id, product_id) references core.product(tenant_id, product_id) on delete cascade  
);

create table if not exists inventory_log_type(
    inventory_log_type_id serial primary key,
    inventory_log_type_name varchar(50) not null unique, 
    inventory_log_type_description text,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);
insert into inventory_log_type (inventory_log_type_name, inventory_log_type_description) values
    ('IN', 'inventory added to inventory_module'),
    ('OUT', 'inventory removed from inventory_module')
on conflict do nothing;

create table if not exists inventory_log(
    inventory_log_id uuid primary key default gen_random_uuid(),
    inventory_log_type_id integer not null references inventory_module.inventory_log_type(inventory_log_type_id) on delete cascade,
    supply_order_id uuid references supplies_module.supply_order(supply_order_id) on delete set null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table if not exists inventory_transfer(
    inventory_transfer_id uuid primary key default gen_random_uuid(),
    from_warehouse_id uuid not null references inventory_module.warehouse(warehouse_id) on delete cascade,
    to_warehouse_id uuid not null references inventory_module.warehouse(warehouse_id) on delete cascade,
    inventory_transfer_departure_date timestamp default current_timestamp,
    inventory_transfer_arrival_date timestamp,
    transfer_date timestamp default current_timestamp,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp
);

create table if not exists inventory_transfer_product(
    inventory_transfer_product_id uuid primary key default gen_random_uuid(),
    inventory_transfer_id uuid not null references inventory_module.inventory_transfer(inventory_transfer_id) on delete cascade,
    tenant_id uuid not null,                                                         
    product_id uuid not null,
    quantity integer not null,
    created_at timestamp default current_timestamp,
    updated_at timestamp default current_timestamp,
    
    foreign key (tenant_id, product_id) references core.product(tenant_id, product_id) on delete cascade  
);

CREATE TABLE IF NOT EXISTS discrepancy_count(
    discrepancy_count_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid not null,                                                         
    product_id uuid not null,
    warehouse_id uuid NOT NULL REFERENCES inventory_module.warehouse(warehouse_id) ON DELETE CASCADE,
    stored_quantity integer NOT NULL,
    physical_quantity integer NOT NULL,
    discrepancy_reason text,
    created_at timestamp DEFAULT current_timestamp,
    updated_at timestamp DEFAULT current_timestamp,

    FOREIGN KEY (tenant_id, product_id) REFERENCES core.product(tenant_id, product_id) ON DELETE CASCADE  
);