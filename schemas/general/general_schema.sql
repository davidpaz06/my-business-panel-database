CREATE SCHEMA IF NOT EXISTS general_schema;
SET SEARCH_PATH TO general_schema;

CREATE TABLE IF NOT EXISTS region(
    region_id SERIAL PRIMARY KEY,
    region_name VARCHAR(100) unique not null,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- TODO: AGREGAR CAMPOS:
--      CODIGO DE ACTIVIDAD ECONOMICA
CREATE TABLE IF NOT EXISTS tenant(
    tenant_id uuid PRIMARY KEY default gen_random_uuid(),
    tenant_name VARCHAR(100) unique not null,
    region_id INTEGER REFERENCES general_schema.region(region_id) on delete set null,
    contact_email VARCHAR(100) not null,
    is_subscribed BOOLEAN default false,
    stripe_id VARCHAR(255) unique default null,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS branch(
    branch_id uuid PRIMARY KEY default gen_random_uuid(),
    tenant_id uuid not null REFERENCES general_schema.tenant(tenant_id) on delete cascade,
    branch_name VARCHAR(100) not null,
    branch_address text,
    contact_email VARCHAR(100),
    is_main_branch BOOLEAN default false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS unique_main_branch_per_tenant 
    on general_schema.branch (tenant_id) 
    where is_main_branch = true;

CREATE TABLE IF NOT EXISTS document_type(
    document_type_id SERIAL PRIMARY KEY, 
    type_name VARCHAR(50) unique not null,
    description text,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS customer_segment(
    customer_segment_id SERIAL PRIMARY KEY,
    segment_name VARCHAR(100) unique not null,
    segment_hierarchy INTEGER not null,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

CREATE TABLE IF NOT EXISTS customer_segment_margin_type(
    customer_segment_margin_type_id SERIAL PRIMARY KEY,
    type_name VARCHAR(50) unique not null,
    description text,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS customer_segment_margin(
    customer_segment_margin_id uuid PRIMARY KEY not null default gen_random_uuid(),
    tenant_id uuid not null REFERENCES general_schema.tenant(tenant_id) on delete cascade,
    customer_segment_id int not null REFERENCES general_schema.customer_segment(customer_segment_id) on delete cascade,
    customer_segment_margin_type_id int REFERENCES general_schema.customer_segment_margin_type(customer_segment_margin_type_id) on delete set null,
    spending_threshold numeric(10,2) check (spending_threshold >= 0),
    seniority_months int check (seniority_months >= 0),
    frequency_per_month int check (frequency_per_month >= 0)
);

CREATE TABLE IF NOT EXISTS tenant_customer(
    tenant_customer_id uuid PRIMARY KEY default gen_random_uuid(),
    tenant_id uuid not null REFERENCES general_schema.tenant(tenant_id) on delete cascade,  
    first_name VARCHAR(100) not null,
    last_name VARCHAR(100) not null,
    document_type_id INTEGER REFERENCES general_schema.document_type(document_type_id) on delete set null,  
    document_number VARCHAR(50) not null,
    email VARCHAR(255) not null,
    phone VARCHAR(50) not null,
    birthdate date,
    address text,
    is_tenant BOOLEAN default false,
    customer_segment_id int default 4 REFERENCES general_schema.customer_segment(customer_segment_id) on delete set null,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    unique(tenant_id, document_number),   
    unique(tenant_id, email),             
    unique(tenant_id, phone)    
);

CREATE TABLE IF NOT EXISTS role(
    role_id SERIAL PRIMARY KEY,
    role_name VARCHAR(50) unique not null,
    role_hierarchy INTEGER not null,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS users( 
    user_id uuid PRIMARY KEY default gen_random_uuid(),
    tenant_id uuid REFERENCES general_schema.tenant(tenant_id) on delete cascade,
    email VARCHAR(100) unique not null,
    password_hash VARCHAR(255) not null,
    role_id INTEGER REFERENCES general_schema.role(role_id) on delete set null,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS currency(
    currency_id SERIAL PRIMARY KEY,
    currency_code char(3) unique not null,
    currency_name VARCHAR(50) not null,
    symbol VARCHAR(10) not null,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- TODO: AGREGAR SEED DE TAX RATES DE CABYS (0, 1, 2, 4, 13, 15, 18, 27)
CREATE TABLE IF NOT EXISTS tax_rate(
    tax_rate_id SERIAL PRIMARY KEY,
    region VARCHAR(100) unique not null,
    region_id INTEGER REFERENCES general_schema.region(region_id) on delete set null,
    rate_percentage numeric(5,2) not null check (rate_percentage >= 0 and rate_percentage <= 100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS subscription_type ( 
    subscription_type_id SERIAL PRIMARY KEY,
    subscription_type_name VARCHAR(25) not null,
    subscription_type_detail text not null,
    duration_months int not null,
    subscription_type_cost numeric(5,2)
    -- TODO: corroborar como se gestionarán las suscripciones del SaaS
);

CREATE TABLE IF NOT EXISTS payment_method(
    payment_method_id SERIAL PRIMARY KEY,
    name VARCHAR(50) unique not null,
    description text,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS tenant_payment(
    tenant_payment_id uuid PRIMARY KEY default gen_random_uuid(),
    tenant_id uuid REFERENCES general_schema.tenant(tenant_id) on delete cascade,
    payment_method_id INTEGER REFERENCES general_schema.payment_method(payment_method_id) on delete set null,
    payment_amount numeric(10,2) not null check (payment_amount >= 0),
    payment_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    details VARCHAR(255),
    verified BOOLEAN default false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS subscription(
    subscription_id uuid PRIMARY KEY default gen_random_uuid(),
    tenant_id uuid REFERENCES general_schema.tenant(tenant_id) on delete cascade,
    subscription_type_id INTEGER REFERENCES general_schema.subscription_type(subscription_type_id) on delete set null,
    tenant_payment_id uuid REFERENCES general_schema.tenant_payment(tenant_payment_id) on delete set null,
    start_date date not null,
    end_date date not null,
    is_active BOOLEAN default true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    check (end_date > start_date)
);

CREATE TABLE IF NOT EXISTS product_category(
    product_category_id SERIAL PRIMARY KEY,
    category_name VARCHAR(100) unique not null,
    parent_category_id INTEGER                                    
        REFERENCES general_schema.product_category(product_category_id)
        ON DELETE CASCADE,
    hierarchy_level INTEGER DEFAULT 0 CHECK (hierarchy_level >= 0),  
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT chk_no_self_reference                              
        CHECK (product_category_id != parent_category_id)
);

CREATE INDEX IF NOT EXISTS idx_product_category_parent 
    ON general_schema.product_category(parent_category_id) 
    WHERE parent_category_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_product_category_hierarchy 
    ON general_schema.product_category(parent_category_id, hierarchy_level);

CREATE TABLE IF NOT EXISTS unit_measure(
    unit_measure_id SERIAL PRIMARY KEY,
    unit_name VARCHAR(50) UNIQUE NOT NULL,
    symbol VARCHAR(10),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS commercial_unit_measure(
    commercial_unit_measure_id SERIAL PRIMARY KEY,
    unit_name VARCHAR(50) UNIQUE NOT NULL,
    symbol VARCHAR(10),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS product(
    cabys_code VARCHAR(13) PRIMARY KEY,
    product_name VARCHAR(255) NOT NULL,
    product_name_tsv tsvector GENERATED ALWAYS AS (to_tsvector('spanish', product_name)) STORED,
    product_category_id INT REFERENCES general_schema.product_category(product_category_id) ON DELETE SET NULL,
    tax_rate_id INT REFERENCES general_schema.tax_rate(tax_rate_id) ON DELETE SET NULL,
    unit_measure_id INT REFERENCES general_schema.unit_measure(unit_measure_id) ON DELETE SET NULL,
    commercial_unit_measure_id INT REFERENCES general_schema.commercial_unit_measure(commercial_unit_measure_id) ON DELETE SET NULL,
    is_exonerated BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_product_name_fts 
    ON general_schema.product USING gin(product_name_tsv);
CREATE INDEX IF NOT EXISTS idx_product_category 
    ON general_schema.product(product_category_id) 
    WHERE product_category_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_product_tax_rate 
    ON general_schema.product(tax_rate_id) 
    WHERE tax_rate_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS global_attribute (
    global_attribute_id SERIAL PRIMARY KEY,
    attribute_name VARCHAR(100) not null,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS unique_attribute_name 
    on general_schema.global_attribute (lower(attribute_name));

CREATE TABLE IF NOT EXISTS tenant_attribute (
    tenant_attribute_id uuid PRIMARY KEY default gen_random_uuid(),
    tenant_id uuid not null REFERENCES general_schema.tenant(tenant_id) on delete cascade,
    global_attribute_id int REFERENCES general_schema.global_attribute(global_attribute_id) on delete set null,
    attribute_name VARCHAR(100) not null,
    is_custom BOOLEAN default false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    check (
        (global_attribute_id is not null and is_custom = false) or
        (global_attribute_id is null and is_custom = true)
    )
);

CREATE UNIQUE INDEX IF NOT EXISTS unique_tenant_attribute_name 
    on general_schema.tenant_attribute (tenant_id, lower(attribute_name));

CREATE TABLE IF NOT EXISTS attribute_value (
    attribute_value_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    tenant_attribute_id uuid NOT NULL REFERENCES general_schema.tenant_attribute(tenant_attribute_id) ON DELETE CASCADE,
    value_name VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON COLUMN general_schema.attribute_value.value_name IS 
    'Value for the attribute (e.g., Color: Red, Size: Medium)';

CREATE UNIQUE INDEX IF NOT EXISTS idx_attribute_value_unique 
    ON general_schema.attribute_value(tenant_id, tenant_attribute_id, lower(value_name));
CREATE INDEX IF NOT EXISTS idx_attribute_value_by_attribute 
    ON general_schema.attribute_value(tenant_attribute_id);
CREATE INDEX IF NOT EXISTS idx_attribute_value_tenant 
    ON general_schema.attribute_value(tenant_id);

CREATE TABLE IF NOT EXISTS product_variant (
    tenant_id uuid NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    product_variant_id uuid NOT NULL DEFAULT gen_random_uuid(),
    cabys_code VARCHAR(13) REFERENCES general_schema.product(cabys_code) ON DELETE SET NULL,
    sku VARCHAR(100) NOT NULL,
    variant_name VARCHAR(255),
    unit_price numeric(10,2) CHECK (unit_price >= 0),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (tenant_id, product_variant_id)
) PARTITION BY HASH (tenant_id);

DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 0..7 LOOP
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS general_schema.product_variant_p%s 
             PARTITION OF general_schema.product_variant 
             FOR VALUES WITH (MODULUS 8, REMAINDER %s);',
            i, i
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE UNIQUE INDEX IF NOT EXISTS idx_product_variant_tenant_sku 
    ON general_schema.product_variant(tenant_id, sku);
CREATE INDEX IF NOT EXISTS idx_product_variant_cabys 
    ON general_schema.product_variant(cabys_code);
CREATE INDEX IF NOT EXISTS idx_product_variant_tenant_btree 
    ON general_schema.product_variant(tenant_id);
CREATE INDEX IF NOT EXISTS idx_product_variant_active 
    ON general_schema.product_variant(tenant_id, is_active) 
    WHERE is_active = true;

COMMENT ON TABLE general_schema.product_variant IS 
    'Tenant-specific sellable product variants linked to a CABYS catalog entry. 
    Variants have unique SKUs and prices per tenant.';

CREATE TABLE IF NOT EXISTS attribute_assignation (
    tenant_id uuid NOT NULL,
    product_variant_id uuid NOT NULL,
    attribute_value_id uuid NOT NULL REFERENCES general_schema.attribute_value(attribute_value_id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (tenant_id, product_variant_id, attribute_value_id),
    
    FOREIGN KEY (tenant_id, product_variant_id) 
        REFERENCES general_schema.product_variant(tenant_id, product_variant_id) 
        ON DELETE CASCADE
) PARTITION BY HASH (tenant_id);

DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 0..7 LOOP
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS general_schema.attribute_assignation_p%s 
             PARTITION OF general_schema.attribute_assignation 
             FOR VALUES WITH (MODULUS 8, REMAINDER %s);',
            i, i
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE INDEX IF NOT EXISTS idx_attr_assignation_variant 
    ON general_schema.attribute_assignation(tenant_id, product_variant_id);
CREATE INDEX IF NOT EXISTS idx_attr_assignation_value 
    ON general_schema.attribute_assignation(attribute_value_id);

COMMENT ON TABLE general_schema.attribute_assignation IS 
    'Links product variants to their attribute values (e.g., Color: Red, Size: Medium).';

CREATE TABLE IF NOT EXISTS account_payable_status(
    status_id SERIAL PRIMARY KEY,
    status_name VARCHAR(50) not null,
    description text,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS account_payable_type (
    account_payable_type_id SERIAL PRIMARY KEY,
    type_name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS general_schema.account_payable (
    account_payable_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_payable_type_id INT REFERENCES general_schema.account_payable_type(account_payable_type_id) ON DELETE SET NULL,
    account_status INTEGER not null default 1 REFERENCES general_schema.account_payable_status(status_id),
    has_invoice BOOLEAN DEFAULT FALSE,
    has_tax BOOLEAN DEFAULT FALSE,
    subtotal NUMERIC(12,3) NOT NULL CHECK (subtotal >= 0),
    amount_paid NUMERIC(12,3) DEFAULT 0 CHECK (amount_paid >= 0),
    balance_remaining NUMERIC(12,3) GENERATED ALWAYS AS (subtotal - amount_paid) STORED,
    is_paid BOOLEAN DEFAULT FALSE,
    due_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

