CREATE SCHEMA IF NOT EXISTS inventory_schema;
SET SEARCH_PATH TO inventory_schema;

CREATE TABLE IF NOT EXISTS warehouse (
    warehouse_id uuid PRIMARY KEY default gen_random_uuid(),
    branch_id uuid not null REFERENCES general_schema.branch(branch_id) on delete cascade,
    warehouse_name VARCHAR(255) not null,
    warehouse_address text not null,
    is_branch BOOLEAN default false not null,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS inventory(
    inventory_id uuid PRIMARY KEY default gen_random_uuid(),
    tenant_id uuid not null,                                                         
    product_variant_id uuid not null,
    warehouse_id uuid not null REFERENCES inventory_schema.warehouse(warehouse_id) on delete cascade,
    stock INTEGER not null,
    expiration_date timestamp check (expiration_date is null or expiration_date > current_timestamp),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (tenant_id, product_variant_id) 
        REFERENCES general_schema.product_variant(tenant_id, product_variant_id) on delete cascade  
);
CREATE INDEX IF NOT EXISTS idx_inventory_product_variant 
    ON inventory_schema.inventory(tenant_id, product_variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_warehouse 
    ON inventory_schema.inventory(warehouse_id);
CREATE INDEX IF NOT EXISTS idx_inventory_tenant 
    ON inventory_schema.inventory(tenant_id);
CREATE INDEX IF NOT EXISTS idx_warehouse_is_branch 
    ON inventory_schema.warehouse(is_branch);

CREATE INDEX IF NOT EXISTS idx_warehouse_branch_sales 
    ON inventory_schema.warehouse(branch_id, is_branch)
    WHERE is_branch = TRUE;

CREATE UNIQUE INDEX IF NOT EXISTS uq_warehouse_branch_sales_floor 
    ON inventory_schema.warehouse(branch_id)
    WHERE is_branch = TRUE;

CREATE TABLE IF NOT EXISTS inventory_log_type(
    inventory_log_type_id SERIAL PRIMARY KEY,
    inventory_log_type_name VARCHAR(50) not null unique, 
    inventory_log_type_description text,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS inventory_log(
    inventory_log_id uuid PRIMARY KEY default gen_random_uuid(),
    inventory_log_type_id INTEGER not null REFERENCES inventory_schema.inventory_log_type(inventory_log_type_id) on delete cascade,
    warehouse_id uuid not null REFERENCES inventory_schema.warehouse(warehouse_id) on delete cascade,
    tenant_id uuid not null,                                                         
    product_variant_id uuid not null,
    quantity INTEGER not null,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (tenant_id, product_variant_id) 
        REFERENCES general_schema.product_variant(tenant_id, product_variant_id) on delete cascade  
);
CREATE INDEX IF NOT EXISTS idx_inventory_log_product_variant 
    ON inventory_schema.inventory_log(tenant_id, product_variant_id);
CREATE INDEX IF NOT EXISTS idx_inventory_log_warehouse 
    ON inventory_schema.inventory_log(warehouse_id);

CREATE TABLE IF NOT EXISTS inventory_transfer(
    inventory_transfer_id uuid PRIMARY KEY default gen_random_uuid(),
    from_warehouse_id uuid not null REFERENCES inventory_schema.warehouse(warehouse_id) on delete cascade,
    to_warehouse_id uuid not null REFERENCES inventory_schema.warehouse(warehouse_id) on delete cascade,
    inventory_transfer_departure_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    inventory_transfer_arrival_date timestamp,
    transfer_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS inventory_transfer_product(
    inventory_transfer_product_id uuid PRIMARY KEY default gen_random_uuid(),
    inventory_transfer_id uuid not null REFERENCES inventory_schema.inventory_transfer(inventory_transfer_id) on delete cascade,
    tenant_id uuid not null,                                                         
    product_variant_id uuid not null,
    quantity INTEGER not null,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (tenant_id, product_variant_id) 
        REFERENCES general_schema.product_variant(tenant_id, product_variant_id) on delete cascade  
);
CREATE INDEX IF NOT EXISTS idx_transfer_product_variant 
    ON inventory_schema.inventory_transfer_product(tenant_id, product_variant_id);

CREATE TABLE IF NOT EXISTS discrepancy_count(
    discrepancy_count_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid not null,                                                         
    product_variant_id uuid not null,
    warehouse_id uuid NOT NULL REFERENCES inventory_schema.warehouse(warehouse_id) ON DELETE CASCADE,
    stored_quantity INTEGER NOT NULL,
    physical_quantity INTEGER NOT NULL,
    discrepancy_reason text,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (tenant_id, product_variant_id) 
        REFERENCES general_schema.product_variant(tenant_id, product_variant_id) ON DELETE CASCADE  
);
CREATE INDEX IF NOT EXISTS idx_discrepancy_product_variant 
    ON inventory_schema.discrepancy_count(tenant_id, product_variant_id);