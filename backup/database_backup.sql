-- ======================================================
-- CONSOLIDATED BOOTSTRAP FILE
-- Generated: 2026-02-04 14:07:35
-- ======================================================
-- This file can be executed from any SQL client
-- ======================================================

BEGIN;

DROP SCHEMA IF EXISTS general_schema CASCADE;
DROP SCHEMA IF EXISTS pos_schema CASCADE;
DROP SCHEMA IF EXISTS inventory_schema CASCADE;
DROP SCHEMA IF EXISTS purchase_schema CASCADE;
DROP SCHEMA IF EXISTS hr_schema CASCADE;

-- -----------------
-- EXTENSIONS
-- -----------------
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- -----------------
-- TABLES
-- -----------------


-- =============================================
-- SCHEMA: GENERAL
-- Source: schemas/general/general_schema.sql
-- =============================================
CREATE SCHEMA IF NOT EXISTS general_schema;
SET SEARCH_PATH TO general_schema;

CREATE TABLE IF NOT EXISTS region(
    region_id SERIAL PRIMARY KEY,
    region_name VARCHAR(100) unique not null,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

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

CREATE TABLE IF NOT EXISTS product(
    tenant_id uuid not null REFERENCES general_schema.tenant(tenant_id) on delete cascade,
    product_id uuid not null default gen_random_uuid(),
    sku VARCHAR(50) not null,
    product_name VARCHAR(100) not null,
    product_name_tsv tsvector generated always as (to_tsvector('spanish', product_name)) stored,
    product_description text,
    product_category_id int REFERENCES general_schema.product_category(product_category_id) on delete set null,
    unit_price numeric(10,2) not null check (unit_price >= 0),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (tenant_id, product_id)   
) partition by hash (tenant_id);
DO $$
declare
    i int;
BEGIN
    for i in 0..7 loop
        execute format(
            'CREATE TABLE IF NOT EXISTS general_schema.product_p%s partition of general_schema.product for VALUES with (modulus 8, remainder %s);'
            , i, i);
    end loop;
end;
$$ language plpgsql;
CREATE UNIQUE INDEX IF NOT EXISTS idx_product_tenant_sku on general_schema.product(tenant_id, sku);
CREATE INDEX IF NOT EXISTS idx_product_tenant_btree on general_schema.product(tenant_id);
CREATE INDEX IF NOT EXISTS idx_product_name_fts on general_schema.product using gin ( product_name_tsv );

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
    product_id uuid NOT NULL,
    sku VARCHAR(100) NOT NULL,
    variant_name VARCHAR(255),
    unit_price numeric(10,2) CHECK (unit_price >= 0),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (tenant_id, product_variant_id),
    
    FOREIGN KEY (tenant_id, product_id) 
        REFERENCES general_schema.product(tenant_id, product_id) 
        ON DELETE CASCADE
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
CREATE INDEX IF NOT EXISTS idx_product_variant_product 
    ON general_schema.product_variant(tenant_id, product_id);
CREATE INDEX IF NOT EXISTS idx_product_variant_tenant_btree 
    ON general_schema.product_variant(tenant_id);
CREATE INDEX IF NOT EXISTS idx_product_variant_active 
    ON general_schema.product_variant(tenant_id, is_active) 
    WHERE is_active = true;

COMMENT ON TABLE general_schema.product_variant IS 
    'Specific sellable product variants linked to a base product. 
    Variants can have unique SKUs and prices.';

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



-- =============================================
-- SCHEMA: POS
-- Source: schemas/pos/pos_schema.sql
-- =============================================
CREATE SCHEMA IF NOT EXISTS pos_schema;
SET SEARCH_PATH TO pos_schema;

CREATE TABLE IF NOT EXISTS sale(
    sale_id uuid PRIMARY KEY default gen_random_uuid(),
    branch_id uuid not null REFERENCES general_schema.branch(branch_id) on delete cascade,  
    sale_date timestamp not null default current_timestamp,
    currency_id INTEGER REFERENCES general_schema.currency(currency_id) on delete set null,
    subtotal_amount numeric(10,2) not null default 0 check (subtotal_amount >= 0),
    tax_amount numeric(10,2) not null default 0 check (tax_amount >= 0),
    total_amount numeric(10,2) not null,
    is_completed BOOLEAN default false,
    created_at timestamp not null default current_timestamp,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_sale_branch_id on pos_schema.sale(branch_id);
CREATE INDEX IF NOT EXISTS idx_sale_sale_date on pos_schema.sale(sale_date);

CREATE TABLE IF NOT EXISTS sale_item(
    sale_item_id uuid PRIMARY KEY default gen_random_uuid(),
    sale_id uuid not null REFERENCES pos_schema.sale(sale_id) on delete cascade,
    tenant_id uuid not null, 
    product_variant_id uuid not null,  
    quantity INTEGER not null check (quantity > 0),
    unit_price numeric(10,2) not null check (unit_price >= 0),
    total_price numeric(10,2) not null,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (tenant_id, product_variant_id) 
        REFERENCES general_schema.product_variant(tenant_id, product_variant_id) 
        on delete restrict
);
CREATE INDEX IF NOT EXISTS idx_sale_item_product_variant 
    ON pos_schema.sale_item(tenant_id, product_variant_id);
CREATE INDEX IF NOT EXISTS idx_sale_item_sale_id 
    ON pos_schema.sale_item(sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_item_sale_variant 
    ON pos_schema.sale_item(sale_id, product_variant_id);

CREATE TABLE IF NOT EXISTS cash_register(
    cash_register_id uuid PRIMARY KEY default gen_random_uuid(),
    branch_id uuid not null REFERENCES general_schema.branch(branch_id) on delete cascade,
    is_active BOOLEAN default true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS cash_register_session(
    cash_register_session_id uuid PRIMARY KEY default gen_random_uuid(),
    cash_register_id uuid not null REFERENCES pos_schema.cash_register(cash_register_id) on delete cascade,
    user_id uuid not null REFERENCES general_schema.users(user_id) on delete set null,
    opened_at timestamp not null default current_timestamp,
    closed_at timestamp,
    opening_amount numeric(10,2) not null check (opening_amount >= 0),
    closing_amount numeric(10,2) check (closing_amount >= 0),
    is_active BOOLEAN default true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS cash_register_sale(
    cash_register_sale_id uuid PRIMARY KEY default gen_random_uuid(),
    cash_register_session_id uuid not null REFERENCES pos_schema.cash_register_session(cash_register_session_id) on delete cascade,
    sale_id uuid not null unique REFERENCES pos_schema.sale(sale_id) on delete cascade, 
    transaction_time timestamp not null default current_timestamp,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS customer_payment(
    customer_payment_id uuid PRIMARY KEY not null default gen_random_uuid(),
    tenant_customer_id uuid not null REFERENCES general_schema.tenant_customer(tenant_customer_id) on delete cascade,   
    sale_id uuid not null REFERENCES pos_schema.sale(sale_id) on delete cascade,
    payment_method_id INTEGER REFERENCES general_schema.payment_method(payment_method_id) on delete set null,
    is_points_redemption BOOLEAN default false,
    points_redeemed INTEGER default 0 check (points_redeemed >= 0),
    points_to_currency_rate numeric(10,4) default 0 check (points_to_currency_rate >= 0),
    payment_amount numeric(10,2) not null check (payment_amount > 0),
    payment_date timestamp not null default current_timestamp,
    currency_id INTEGER REFERENCES general_schema.currency(currency_id) on delete set null,
    verified BOOLEAN default false,
    created_at timestamp not null default current_timestamp,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    constraint check_points_redemption
    check (
        (is_points_redemption = true and points_redeemed is not null and points_redeemed > 0 and payment_method_id = 4) or
        (is_points_redemption = false)
    )
);

CREATE TABLE IF NOT EXISTS bill(
    bill_id uuid PRIMARY KEY default gen_random_uuid(),
    tenant_customer_id uuid REFERENCES general_schema.tenant_customer(tenant_customer_id) on delete set null,
    sale_id uuid not null REFERENCES pos_schema.sale(sale_id) on delete cascade,
    currency_id INTEGER REFERENCES general_schema.currency(currency_id) on delete set null,
    subtotal_amount numeric(10,2) not null check (subtotal_amount >= 0),
    tax_amount numeric(10,2) not null check (tax_amount >= 0),
    total_amount numeric(10,2) not null,    
    billed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
alter table pos_schema.bill
    add column if not exists due_date date;
CREATE INDEX IF NOT EXISTS idx_bill_sale_id on pos_schema.bill(sale_id);

CREATE TABLE IF NOT EXISTS bill_payment(
    bill_payment_id uuid PRIMARY KEY default gen_random_uuid(),
    bill_id uuid not null REFERENCES pos_schema.bill(bill_id) on delete cascade,
    customer_payment_id uuid not null REFERENCES pos_schema.customer_payment(customer_payment_id) on delete cascade,
    payment_amount numeric(10,2) not null check (payment_amount > 0),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    unique (bill_id, customer_payment_id)
);

CREATE TABLE IF NOT EXISTS return_reason(
    return_reason_id SERIAL PRIMARY KEY,
    reason_code VARCHAR(50) unique not null,
    reason_name VARCHAR(100) not null,
    description text,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS return_status(
    return_status_id SERIAL PRIMARY KEY,
    status_name VARCHAR(50) unique not null,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS return_transaction(
    return_transaction_id uuid PRIMARY KEY default gen_random_uuid(),
    bill_id uuid not null REFERENCES pos_schema.bill(bill_id) on delete cascade,
    tenant_customer_id uuid REFERENCES general_schema.tenant_customer(tenant_customer_id) on delete set null,
    total_refund_amount numeric(10,2) not null check (total_refund_amount >= 0),
    refund_method int REFERENCES general_schema.payment_method(payment_method_id) on delete set null,
    return_status_id INTEGER REFERENCES pos_schema.return_status(return_status_id) on delete set null,
    return_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_return_transaction_bill_id on pos_schema.return_transaction(bill_id);
CREATE INDEX IF NOT EXISTS idx_return_transaction_date on pos_schema.return_transaction(return_date);

CREATE TABLE IF NOT EXISTS return_product(
    return_product_id uuid PRIMARY KEY default gen_random_uuid(),
    return_transaction_id uuid not null REFERENCES pos_schema.return_transaction(return_transaction_id) on delete cascade,
    sale_item_id uuid not null REFERENCES pos_schema.sale_item(sale_item_id) on delete cascade,
    quantity INTEGER not null check (quantity > 0),
    unit_price numeric(10,2) not null check (unit_price >= 0),
    total_price numeric(10,2) not null,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_return_product_transaction_id on pos_schema.return_product(return_transaction_id);

CREATE TABLE IF NOT EXISTS promotion_type(
    promotion_type_id SERIAL PRIMARY KEY,
    type_name VARCHAR(50) unique not null,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS promotion(
    promotion_id uuid PRIMARY KEY default gen_random_uuid(),
    tenant_id uuid not null REFERENCES general_schema.tenant(tenant_id) on delete cascade,
    promotion_name VARCHAR(100) not null,
    promotion_code VARCHAR(50) not null,
    promotion_description text,
    promotion_type_id int REFERENCES pos_schema.promotion_type(promotion_type_id) on delete set null,
    customer_segment_id int REFERENCES general_schema.customer_segment(customer_segment_id) on delete set null,
    promotion_start_date date not null,
    promotion_end_date date not null,
    is_active BOOLEAN default false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    check (promotion_end_date > promotion_start_date)
);

CREATE TABLE IF NOT EXISTS promotion_rule(
    promotion_rule_id uuid PRIMARY KEY default gen_random_uuid(),
    promotion_id uuid not null REFERENCES pos_schema.promotion(promotion_id) on delete cascade,
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
    buy_quantity INTEGER,
    get_quantity INTEGER,
    get_discount_percentage numeric(5,2) default 100.00 check (
        get_discount_percentage is null or 
        (get_discount_percentage >= 0 and get_discount_percentage <= 100)
    ),  -- 100% = gratis, 50% = half price
    -- =====================================
    -- Volume discount
    -- =====================================
    min_quantity INTEGER,
    max_quantity INTEGER,
    -- =====================================
    -- Tiered pricing
    -- =====================================
    tier_level INTEGER,
    tier_min_quantity INTEGER,
    tier_max_quantity INTEGER,
    tier_price numeric(10,2),
    tier_discount_percentage numeric(5,2),
    -- =====================================
    -- Minimum purchase amount for promotion
    -- =====================================
    min_purchase_amount numeric(10,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

create type discount_result as (
    discount_amount numeric(10,2),
    discount_percentage numeric(5,2),
    rule_description text,
    success BOOLEAN
);

CREATE TABLE IF NOT EXISTS loyalty_program(
    loyalty_program_id uuid PRIMARY KEY default gen_random_uuid(),
    tenant_id uuid not null REFERENCES general_schema.tenant(tenant_id) on delete cascade,
    points_earned_per_currency_unit numeric(5,2) not null default 1.00 check (points_earned_per_currency_unit >= 0),
    points_redeemed_per_currency_unit numeric(10,2) not null default 100.00 check (points_redeemed_per_currency_unit > 0),
    minimum_purchase_for_points numeric(10,2) default 0 check (minimum_purchase_for_points >= 0),
    is_active BOOLEAN default true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS tenant_customer_score(
    tenant_id uuid not null REFERENCES general_schema.tenant(tenant_id) on delete cascade,
    tenant_customer_id uuid not null REFERENCES general_schema.tenant_customer(tenant_customer_id) on delete cascade,
    score INTEGER not null default 0 check (score >= 0),
    lifetime_score INTEGER not null default 0 check (lifetime_score >= 0),
    score_redeemed INTEGER not null default 0 check (score_redeemed >= 0),
    last_earned_at timestamp,
    last_redeemed_at timestamp,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (tenant_customer_id, tenant_id)
);

CREATE TABLE IF NOT EXISTS score_redemption_status(
    score_redemption_status_id SERIAL PRIMARY KEY,
    status_name VARCHAR(50) unique not null,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS score_transaction_type(
    score_transaction_type_id SERIAL PRIMARY KEY,
    type_name VARCHAR(50) unique not null,
    description text,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS score_transaction(
    score_transaction_id uuid PRIMARY KEY default gen_random_uuid(),
    tenant_id uuid not null REFERENCES general_schema.tenant(tenant_id) on delete cascade,
    tenant_customer_id uuid not null REFERENCES general_schema.tenant_customer(tenant_customer_id) on delete cascade,
    transaction_type_id int REFERENCES pos_schema.score_transaction_type(score_transaction_type_id) on delete set null,
    points INTEGER not null,
    bill_id uuid REFERENCES pos_schema.bill(bill_id) on delete set null,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS debtor (
    debtor_id uuid PRIMARY KEY default gen_random_uuid(),
    tenant_id uuid not null REFERENCES general_schema.tenant(tenant_id) on delete cascade,
    debt numeric(10, 2) not null default 0.00, -- ? Add check (debt >= 0) 
    missed_payments INTEGER not null default 0
);



-- =============================================
-- SCHEMA: INVENTORY
-- Source: schemas/inventory/inventory_schema.sql
-- =============================================
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



-- =============================================
-- SCHEMA: PURCHASE
-- Source: schemas/purchase/purchase_schema.sql
-- =============================================
-- SCHEMA: purchase
CREATE SCHEMA IF NOT EXISTS purchase_schema;
SET SEARCH_PATH TO purchase_schema;

CREATE TABLE IF NOT EXISTS supplier(
    supplier_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_name VARCHAR(255) not null,
    supplier_contact_info TEXT,
    supplier_address TEXT,
    supplier_notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_supplier_name on purchase_schema.supplier(supplier_name);

CREATE TABLE IF NOT EXISTS supplier_branch(
    supplier_branch_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id uuid not null REFERENCES purchase_schema.supplier(supplier_id) on delete cascade,
    branch_id uuid not null REFERENCES general_schema.branch(branch_id) on delete cascade,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    unique(supplier_id, branch_id)
);

CREATE TABLE IF NOT EXISTS purchase_order_status(
    status_id SERIAL PRIMARY KEY,
    status_name VARCHAR(50) not null,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS purchase_order(
    purchase_order_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_id uuid not null REFERENCES purchase_schema.supplier(supplier_id) on delete cascade,
    warehouse_id uuid not null REFERENCES inventory_schema.warehouse(warehouse_id) on delete cascade,
    purchase_order_date date DEFAULT CURRENT_date,
    expected_delivery_date date,
    purchase_order_status_id INTEGER not null REFERENCES purchase_schema.purchase_order_status(status_id) DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS purchase_order_item(
    purchase_order_item_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_order_id uuid not null REFERENCES purchase_schema.purchase_order(purchase_order_id) on delete cascade,
    tenant_id uuid not null,                                                         
    product_variant_id uuid not null,
    quantity_ordered INTEGER not null,
    unit_price NUMERIC(12,3) not null,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (tenant_id, product_variant_id) 
        REFERENCES general_schema.product_variant(tenant_id, product_variant_id) on delete cascade
);
CREATE INDEX IF NOT EXISTS idx_purchase_order_item_variant 
    ON purchase_schema.purchase_order_item(tenant_id, product_variant_id);

CREATE TABLE IF NOT EXISTS purchase_order_tracking(
    purchase_order_tracking_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_order_id uuid not null REFERENCES purchase_schema.purchase_order(purchase_order_id) on delete cascade,
    previous_status_id int REFERENCES purchase_schema.purchase_order_status(status_id),
    new_status_id int not null REFERENCES purchase_schema.purchase_order_status(status_id),
    notes TEXT,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS supplier_invoice(
    supplier_invoice_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_order_id uuid not null REFERENCES purchase_schema.purchase_order(purchase_order_id) on delete cascade,
    invoice_number VARCHAR(100) not null,
    invoice_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    payment_condition VARCHAR(10) not null DEFAULT 'CREDIT', 
    due_date date,
    subtotal_amount NUMERIC(12,3) not null,
    tax_rate NUMERIC(5,2) not null DEFAULT 13.00,
    tax_amount NUMERIC(12,3) generated always as (round(subtotal_amount * (tax_rate / 100), 3)) stored,
    total_amount NUMERIC(12,3) generated always as (
        subtotal_amount + round(subtotal_amount * (tax_rate / 100), 3)
    ) stored,    
    paid BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    check (payment_condition in ('CREDIT', 'IN_FULL'))
);

CREATE TABLE IF NOT EXISTS supplier_invoice_item(
    supplier_invoice_item_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_invoice_id uuid not null REFERENCES purchase_schema.supplier_invoice(supplier_invoice_id) on delete cascade,
    tenant_id uuid not null,                                                         
    product_variant_id uuid not null,
    quantity_billed INTEGER not null,
    unit_price NUMERIC(12,3) not null,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (tenant_id, product_variant_id) 
        REFERENCES general_schema.product_variant(tenant_id, product_variant_id) on delete cascade
);
CREATE INDEX IF NOT EXISTS idx_supplier_invoice_item_variant 
    ON purchase_schema.supplier_invoice_item(tenant_id, product_variant_id);

CREATE TABLE IF NOT EXISTS goods_receipt(
    goods_receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_order_id uuid not null REFERENCES purchase_schema.purchase_order(purchase_order_id) on delete cascade,
    received_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    subtotal_amount NUMERIC(12,3) DEFAULT 0,
    tax_amount NUMERIC(12,3) DEFAULT 0,
    total_amount NUMERIC(12,3) generated always as (subtotal_amount + tax_amount) stored,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS goods_receipt_item(
    goods_receipt_item_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    goods_receipt_id uuid not null REFERENCES purchase_schema.goods_receipt(goods_receipt_id) on delete cascade,
    tenant_id uuid not null,                                                         
    product_variant_id uuid not null,
    quantity_received INTEGER not null,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (tenant_id, product_variant_id) 
        REFERENCES general_schema.product_variant(tenant_id, product_variant_id) on delete cascade
);
CREATE INDEX IF NOT EXISTS idx_goods_receipt_item_variant 
    ON purchase_schema.goods_receipt_item(tenant_id, product_variant_id);

CREATE TABLE IF NOT EXISTS purchase_schema.purchase_account_payable(
    purchase_account_payable_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    account_payable_id uuid NOT NULL UNIQUE REFERENCES general_schema.account_payable(account_payable_id) ON DELETE CASCADE,
    purchase_order_id uuid NOT NULL UNIQUE REFERENCES purchase_schema.purchase_order(purchase_order_id) ON DELETE CASCADE,
    tax_amount NUMERIC(12,3) DEFAULT 0,
    account_payable_status INTEGER REFERENCES general_schema.account_payable_status(status_id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS purchase_schema.purchase_order_payment(
    purchase_order_payment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_account_payable_id uuid NOT NULL REFERENCES purchase_schema.purchase_account_payable(purchase_account_payable_id) ON DELETE CASCADE,
    payment_method_id INTEGER REFERENCES general_schema.payment_method(payment_method_id),
    amount_paid NUMERIC(12,3) NOT NULL CHECK (amount_paid > 0),
    payment_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    payment_reference VARCHAR(100),
    notes TEXT,
    verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_purchase_order_payment_payable ON purchase_schema.purchase_order_payment(purchase_account_payable_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_payment_verified ON purchase_schema.purchase_order_payment(verified);
CREATE INDEX IF NOT EXISTS idx_purchase_order_payment_date ON purchase_schema.purchase_order_payment(payment_date);

CREATE TABLE IF NOT EXISTS purchase_order_payment_alert_type(
    payment_alert_type_id SERIAL PRIMARY KEY,
    payment_alert_type_name VARCHAR(50) not null,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS purchase_schema.purchase_order_payment_alert(
    payment_alert_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_account_payable_id uuid not null REFERENCES purchase_schema.purchase_account_payable(purchase_account_payable_id) on delete cascade,
    payment_alert_type_id INTEGER not null REFERENCES purchase_schema.purchase_order_payment_alert_type(payment_alert_type_id),
    alert_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_resolved BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS purchase_order_payment_alert(
    payment_alert_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_account_payable_id uuid not null REFERENCES purchase_schema.purchase_account_payable(purchase_account_payable_id) on delete cascade,
    payment_alert_type_id INTEGER not null REFERENCES purchase_schema.purchase_order_payment_alert_type(payment_alert_type_id),
    alert_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_resolved BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS purchase_order_payment_alert_config(
    payment_alert_config_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid unique not null REFERENCES general_schema.tenant(tenant_id) on delete cascade,
    warning_days_before_due INTEGER DEFAULT 7,
    urgent_days_before_due INTEGER DEFAULT 3,
    email_notifications_enabled BOOLEAN DEFAULT true,
    sms_notifications_enabled BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS three_way_matching(
    matching_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_order_id uuid not null REFERENCES purchase_schema.purchase_order(purchase_order_id) on delete cascade,
    goods_receipt_id uuid not null REFERENCES purchase_schema.goods_receipt(goods_receipt_id) on delete cascade,
    supplier_invoice_id uuid not null REFERENCES purchase_schema.supplier_invoice(supplier_invoice_id) on delete cascade,
    amounts_matched BOOLEAN DEFAULT FALSE,
    quantities_matched BOOLEAN DEFAULT FALSE,
    is_matched BOOLEAN DEFAULT FALSE,
    matched_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);



-- =============================================
-- SCHEMA: HR
-- Source: schemas/hr/hr_schema.sql
-- =============================================
DROP SCHEMA IF EXISTS hr_schema CASCADE;
CREATE SCHEMA IF NOT EXISTS hr_schema;
SET SEARCH_PATH TO hr_schema;

-- MODULO DE EMPLEADO

CREATE TABLE IF NOT EXISTS payment_schedule(
	payment_schedule_id SERIAL PRIMARY KEY NOT NULL,
	description VARCHAR(100) NOT NULL,
	daycount INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS contract(
	contract_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id),
	start_date DATE NOT NULL,
	end_date DATE NOT NULL,
	hours INTEGER NOT NULL,
	base_salary NUMERIC(19, 4) NOT NULL,
	duties TEXT
);
--Indice para filtracion o busqueda por rango de precios
CREATE INDEX idx_contract_base_salary ON hr_schema.contract (base_salary);

CREATE TABLE IF NOT EXISTS employee(
	employee_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	user_id UUID NOT NULL REFERENCES general_schema.users(user_id) ON DELETE CASCADE,
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id),
	first_name VARCHAR(100) NOT NULL,
	last_name VARCHAR(100) NOT NULL,
	doc_number VARCHAR(100) NOT NULL UNIQUE,
	phone VARCHAR(100) NOT NULL,
	email VARCHAR(100) NOT NULL UNIQUE,
	contract_id UUID NOT NULL REFERENCES hr_schema.contract(contract_id) ON DELETE CASCADE,
	schedule_id INTEGER NOT NULL REFERENCES hr_schema.payment_schedule(payment_schedule_id),
	is_active BOOLEAN DEFAULT true,
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
	
--Indice para que se pueda garantizar que no haya empleados duplicados
CREATE UNIQUE INDEX idx_employee_doc_number ON hr_schema.employee (doc_number);

--Inidice para la recuperacion de cuentas o autenticacion del empleado
CREATE UNIQUE INDEX idx_employee_email ON hr_schema.employee (email);

--Indices destinados para la aceleracion de los JOINS
CREATE INDEX idx_employee_user_id ON hr_schema.employee (user_id);
CREATE INDEX idx_employee_contract_id ON hr_schema.employee (contract_id);
CREATE INDEX idx_employee_scheduled_id ON hr_schema.employee (schedule_id);

--Indice que se utilizara unicamente para el proceso de nomina y generacion de reportes
CREATE INDEX idx_employee_is_active ON hr_schema.employee (is_active);

CREATE TABLE IF NOT EXISTS clocking(
	clocking_id SERIAL PRIMARY KEY NOT NULL,
	employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id),
	branch_id UUID NOT NULL REFERENCES general_schema.branch(branch_id),
	clock_in TIMESTAMP,
	clock_out TIMESTAMP,
	turn_hours NUMERIC NOT NULL DEFAULT 0
);

-- Indice para buscar los turnos de un empleado dentro de un rango de fechas
CREATE INDEX idx_track_employee_hours_in ON hr_schema.clocking (employee_id, clock_in DESC);
-- Indice para ubicar turnos por sucursal
CREATE INDEX idx_track_hours_branch_id ON hr_schema.clocking (branch_id);

-- MODULO DE NOMINA

CREATE TABLE IF NOT EXISTS paysheet_status(
	status_id SERIAL PRIMARY KEY NOT NULL,
	status_description VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS payroll_concept(
	concept_id SERIAL PRIMARY KEY NOT NULL,
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id),
	name VARCHAR(100) NOT NULL,
	type VARCHAR(20) NOT NULL, -- 'earning' o 'deduction'
	calculation_method VARCHAR(30) NOT NULL, -- 'fixed', 'percentage', 'fromula', 'manual'
	is_taxable BOOLEAN DEFAULT TRUE,
	is_active BOOLEAN DEFAULT TRUE
);

-- Indice para filtracion por conceptos
-- FIXME: column "ccss_apply" does not exist 
-- CREATE INDEX IF NOT EXISTS idx_payroll_concept_apply ON hr_schema.payroll_concept(ccss_apply, tax_apply);

CREATE TABLE IF NOT EXISTS paysheet(
	paysheet_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id),
	branch_id UUID NOT NULL REFERENCES general_schema.branch(branch_id),
	period_start DATE NOT NULL,
	period_end DATE NOT NULL,
	payment_date TIMESTAMP,
	total_earnings NUMERIC(19, 4) NOT NULL DEFAULT 0,
	total_deductions NUMERIC(19, 4) NOT NULL DEFAULT 0,
	net_total NUMERIC(19, 4) NOT NULL DEFAULT 0,
	paysheet_status_id INTEGER NOT NULL REFERENCES hr_schema.paysheet_status(status_id),
	created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

--Indice para la consulta de nominas por periodo de pago
CREATE INDEX idx_paysheet_period_dates ON hr_schema.paysheet (tenant_id, period_start, period_end);

CREATE TABLE IF NOT EXISTS paysheet_detail(
	detail_id UUID NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
	paysheet_id UUID NOT NULL REFERENCES hr_schema.paysheet(paysheet_id) ON DELETE CASCADE,
	employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id),
	contract_id UUID NOT NULL REFERENCES hr_schema.contract(contract_id),
	payment_method_id INTEGER NOT NULL REFERENCES general_schema.payment_method(payment_method_id),
	gross_salary NUMERIC(19, 4) NOT NULL,
	total_earnings NUMERIC(19, 4) NOT NULL DEFAULT 0,
	total_deduction NUMERIC(19, 4) NOT NULL DEFAULT 0,
	net_salary NUMERIC(19, 4) NOT NULL,
	status VARCHAR(20) NOT NULL DEFAULT 'Pending',
	pay_date DATE NOT NULL,
  recalc_needed BOOLEAN DEFAULT TRUE NOT NULL
);

-- Indice para agilizar la busqueda de todos los detalles bajo un paysheet_id
CREATE INDEX idx_paysheet_detail_paysheet_id ON hr_schema.paysheet_detail(paysheet_id);
-- Indice compuesto para la consulta del historial de pagos a un empleado
CREATE INDEX idx_paysheet_detail_emp_paydate ON hr_schema.paysheet_detail (employee_id, pay_date DESC);

CREATE TABLE IF NOT EXISTS payroll_movement (
	movement_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	detail_id UUID NOT NULL REFERENCES hr_schema.paysheet_detail(detail_id) ON DELETE CASCADE,
	concept_id INTEGER NOT NULL REFERENCES hr_schema.payroll_concept(concept_id),
	base_amount NUMERIC(19, 4) NOT NULL,
	calculated_amount NUMERIC(19, 4) NOT NULL,
	description TEXT
);

-- Indice para agilizar la busqueda de todos los movimientos bajo un detail_id
CREATE INDEX idx_payroll_movement_detail_id ON hr_schema.payroll_movement(detail_id);



-- =============================================
-- FUNCTIONS: GENERAL
-- Source: functions/general/general_functions.sql
-- =============================================
set search_path = general_schema;

CREATE OR REPLACE PROCEDURE verify_tenant_payment(_payment_id uuid)
language plpgsql
as $$
declare
    _exists BOOLEAN;
    _already_verified BOOLEAN;
    _rows_updated int;
    _tenant_id uuid;
BEGIN
    select exists(
        select 1 
        from general_schema.tenant_payment 
        where tenant_payment_id = _payment_id
    ) into _exists;
    
    if not _exists then
        raise notice 'Payment with id: % does not exist.', _payment_id;
        raise exception 'Payment not found: %', _payment_id;
    end if;

    select coalesce(verified, false), tenant_id 
    into _already_verified, _tenant_id
    from general_schema.tenant_payment 
    where tenant_payment_id = _payment_id;
    
    if _already_verified then
        raise notice 'Payment % is already verified.', _payment_id;
        return;
    end if;

    update general_schema.tenant_payment
    set verified = true,
        updated_at = current_timestamp
    where tenant_payment_id = _payment_id
    and coalesce(verified, false) = false;
    
    get diagnostics _rows_updated = row_count;
    
    if _rows_updated > 0 then

        raise notice 'Payment verified successfully: %', _payment_id;
        raise notice 'Tenant: %', _tenant_id;
        raise notice 'Trigger will create subscription automatically';

    else
        raise notice 'No rows updated for payment: %', _payment_id;
        raise exception 'Failed to verify payment: %', _payment_id;
    end if;
        
exception
    when others then
        raise notice 'Payment verification failed: %', sqlerrm;
        raise;
end
$$;




CREATE OR REPLACE FUNCTION create_subscription()
returns trigger as $$
declare
    _subscription_type_id int;
    _exists BOOLEAN;
    _old_end_date date;
    _time_left interval;
    _new_start_date date;
    _new_end_date date;
    _tenant_id uuid;
    _plan_duration interval;
BEGIN
    _tenant_id := new.tenant_id;


    select exists(
        select 1 
        from general_schema.subscription 
        where tenant_payment_id = new.tenant_payment_id  
    ) into _exists;
    
    if _exists then
        raise notice 'Subscription already exists for payment: %', new.tenant_payment_id;
        return new;
    end if;


    select end_date into _old_end_date
    from general_schema.subscription
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
    from general_schema.subscription_type
    where subscription_type_id = _subscription_type_id;

    if _old_end_date is not null and _old_end_date > new.payment_date::date then
        _time_left := _old_end_date - new.payment_date::date;
        raise notice 'Remaining time: % days', extract(days from _time_left);

        _new_start_date := new.payment_date::date;
        _new_end_date := _old_end_date + _plan_duration;
        
        raise notice 'Adding remaining time to new subscription. New end date: %', _new_end_date;
        
    
        update general_schema.subscription 
        set is_active = false,
            updated_at = current_timestamp
        where tenant_id = _tenant_id
        and is_active = true;
    else
        _new_start_date := new.payment_date::date;
        _new_end_date := _new_start_date + _plan_duration;
    end if;


    INSERT INTO general_schema.subscription (
        tenant_id,
        subscription_type_id,
        tenant_payment_id,  
        start_date,
        end_date,
        is_active
    ) VALUES (
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

CREATE OR REPLACE FUNCTION enable_tenant()
returns trigger as $$
BEGIN

    update general_schema.tenant
    set is_subscribed = true,
        updated_at = current_timestamp
    where tenant_id = new.tenant_id;
    
    raise notice 'Tenant % activated', new.tenant_id;
    
    return new;
end;
$$ language plpgsql;

drop trigger if exists on_payment_verified on general_schema.tenant_payment;
create trigger on_payment_verified
    after update of verified on general_schema.tenant_payment  
    for each row
    when (old.verified is false and new.verified is true)
    execute function general_schema.create_subscription();

drop trigger if exists on_subscription_created on general_schema.subscription;
create trigger on_subscription_created
    after insert on general_schema.subscription
    for each row
    execute function general_schema.enable_tenant();

CREATE OR REPLACE FUNCTION update_timestamp()
returns trigger as $$
BEGIN
    new.updated_at = current_timestamp;
    return new;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION update_product_tsv()
returns trigger as $$
BEGIN
    new.product_name_tsv = to_tsvector('spanish', new.product_name);
    return new;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION general_schema.prevent_category_cycles()
RETURNS TRIGGER AS $$
DECLARE
    v_current_id INTEGER;
    v_visited INTEGER[];
    v_max_iterations INTEGER := 10;
    v_iteration INTEGER := 0;
BEGIN
    IF NEW.parent_category_id IS NULL THEN
        RETURN NEW;
    END IF;
    
    v_current_id := NEW.parent_category_id;
    v_visited := ARRAY[NEW.product_category_id];
    
    WHILE v_current_id IS NOT NULL AND v_iteration < v_max_iterations LOOP
        IF v_current_id = NEW.product_category_id THEN
            RAISE EXCEPTION 'Cycle detected: category % cannot be its own ancestor', 
                NEW.product_category_id;
        END IF;
        
        IF v_current_id = ANY(v_visited) THEN
            RAISE EXCEPTION 'Cycle detected in category hierarchy';
        END IF;
        
        v_visited := array_append(v_visited, v_current_id);
        
        SELECT parent_category_id INTO v_current_id
        FROM general_schema.product_category
        WHERE product_category_id = v_current_id;
        
        v_iteration := v_iteration + 1;
    END LOOP;
    
    IF v_iteration >= v_max_iterations THEN
        RAISE EXCEPTION 'Category hierarchy too deep or contains cycle';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION general_schema.prevent_category_cycles() IS 
    'Validates category hierarchy to prevent circular references (both direct and indirect cycles)';

DROP TRIGGER IF EXISTS trigger_prevent_category_cycles 
    ON general_schema.product_category;
CREATE TRIGGER trigger_prevent_category_cycles
    BEFORE INSERT OR UPDATE OF parent_category_id
    ON general_schema.product_category
    FOR EACH ROW
    EXECUTE FUNCTION general_schema.prevent_category_cycles();


CREATE OR REPLACE FUNCTION general_schema.update_category_hierarchy_level()
RETURNS TRIGGER AS $$
DECLARE
    v_parent_level INTEGER;
BEGIN
    IF NEW.parent_category_id IS NULL THEN
        NEW.hierarchy_level := 0;
    ELSE
        SELECT hierarchy_level INTO v_parent_level
        FROM general_schema.product_category
        WHERE product_category_id = NEW.parent_category_id;
        
        IF v_parent_level IS NULL THEN
            RAISE EXCEPTION 'Parent category % not found', NEW.parent_category_id;
        END IF;
        
        NEW.hierarchy_level := v_parent_level + 1;
        
        IF NEW.hierarchy_level > 5 THEN
            RAISE EXCEPTION 'Maximum category depth exceeded (max 5 levels)';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION general_schema.update_category_hierarchy_level() IS 
    'Automatically calculates and updates hierarchy_level based on parent category. Enforces max depth of 5 levels.';

DROP TRIGGER IF EXISTS trigger_update_category_hierarchy 
    ON general_schema.product_category;
CREATE TRIGGER trigger_update_category_hierarchy
    BEFORE INSERT OR UPDATE OF parent_category_id
    ON general_schema.product_category
    FOR EACH ROW
    EXECUTE FUNCTION general_schema.update_category_hierarchy_level();


CREATE OR REPLACE FUNCTION general_schema.get_subcategories(
    p_parent_category_id INTEGER DEFAULT NULL
)
RETURNS TABLE(
    category_id INTEGER,
    category_name VARCHAR(100),
    parent_id INTEGER,
    level INTEGER,
    full_path TEXT,
    product_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE category_tree AS (
        SELECT 
            pc.product_category_id,
            pc.category_name,
            pc.parent_category_id,
            pc.hierarchy_level,
            0 AS depth,
            pc.category_name::TEXT AS path
        FROM general_schema.product_category pc
        WHERE (p_parent_category_id IS NULL AND pc.parent_category_id IS NULL)
           OR (pc.parent_category_id = p_parent_category_id)
        
        UNION ALL
        
        SELECT 
            pc.product_category_id,
            pc.category_name,
            pc.parent_category_id,
            pc.hierarchy_level,
            ct.depth + 1,
            ct.path || ' > ' || pc.category_name
        FROM general_schema.product_category pc
        INNER JOIN category_tree ct 
            ON pc.parent_category_id = ct.product_category_id
    )
    SELECT 
        ct.product_category_id,
        ct.category_name,
        ct.parent_category_id,
        ct.hierarchy_level,
        ct.path,
        COUNT(p.product_id) AS product_count
    FROM category_tree ct
    LEFT JOIN general_schema.product p 
        ON p.product_category_id = ct.product_category_id
    GROUP BY ct.product_category_id, ct.category_name, ct.parent_category_id, 
             ct.hierarchy_level, ct.path, ct.depth
    ORDER BY ct.depth, ct.category_name;
END;
$$ LANGUAGE plpgsql STABLE;

drop trigger if exists update_branch_timestamp on general_schema.branch;
create trigger update_branch_timestamp before update on general_schema.branch
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_product_category_timestamp on general_schema.product_category;
create trigger update_product_category_timestamp before update on general_schema.product_category
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_product_tsv on general_schema.product;
create trigger update_product_tsv before insert or update on general_schema.product
for each row execute function general_schema.update_product_tsv();

drop trigger if exists update_product_timestamp on general_schema.product;
create trigger update_product_timestamp before update on general_schema.product
for each row execute function general_schema.update_timestamp();

-- Triggers for new variant model tables
drop trigger if exists update_attribute_value_timestamp on general_schema.attribute_value;
create trigger update_attribute_value_timestamp before update on general_schema.attribute_value
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_product_variant_timestamp on general_schema.product_variant;
create trigger update_product_variant_timestamp before update on general_schema.product_variant
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_tenant_timestamp on general_schema.tenant;
create trigger update_tenant_timestamp before update on general_schema.tenant
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_tenant_customer_timestamp on general_schema.tenant_customer;
create trigger update_tenant_customer_timestamp before update on general_schema.tenant_customer
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_users_timestamp on general_schema.users;
create trigger update_users_timestamp before update on general_schema.users
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_subscription_timestamp on general_schema.subscription;
create trigger update_subscription_timestamp before update on general_schema.subscription
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_tenant_payment_timestamp on general_schema.tenant_payment;
create trigger update_tenant_payment_timestamp before update on general_schema.tenant_payment
for each row execute function general_schema.update_timestamp();



-- =============================================
-- FUNCTIONS: POS
-- Source: functions/pos/pos_functions.sql
-- =============================================
set search_path = pos_schema;

CREATE OR REPLACE FUNCTION check_sale_payment_completion(_sale_id uuid)
returns BOOLEAN as $$
declare
    _sale_total numeric(10,2);
    _payments_total numeric(10,2);
    _is_completed BOOLEAN;
    _pending_payments int;
BEGIN
        select total_amount, is_completed 
        into _sale_total, _is_completed
        from pos_schema.sale
        where sale_id = _sale_id;
        
        if _sale_total is null then
            raise exception 'Sale not found: %', _sale_id;
        end if;
        
        if _is_completed then
            return true;
        end if;
        
        select count(*) into _pending_payments
        from pos_schema.customer_payment
        where sale_id = _sale_id
        and verified = false;
        
        if _pending_payments > 0 then
            return false;
        end if;
        
        select coalesce(sum(payment_amount), 0) into _payments_total
        from pos_schema.customer_payment
        where sale_id = _sale_id
        and verified = true;
        
        raise notice '   Sale total (with tax): $%', _sale_total;
        raise notice '   Payments total: $%', _payments_total;
        raise notice '   Difference: $%', (_sale_total - _payments_total);
        
        if abs(_payments_total - _sale_total) <= 0.01 then
            update pos_schema.sale
            set is_completed = true,
                updated_at = current_timestamp
            where sale_id = _sale_id;
            
            raise notice '   Sale % marked as COMPLETED', _sale_id;
            return true;
            
        elsif _payments_total > _sale_total then
            raise warning 'Overpayment detected: Expected $%, Paid $%',
                _sale_total, _payments_total;
            return false;
            
        else
            raise notice '   Sale % still pending (shortage: $%)', 
                _sale_id, (_sale_total - _payments_total);
            return false;
        end if;
        
    exception
        when others then
            raise notice '   Error checking sale completion: %', sqlerrm;
            return false;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION link_sale_to_session()
returns trigger as $$
declare 
    _session_id uuid;
BEGIN
    select crs.cash_register_session_id into _session_id
    from pos_schema.cash_register_session crs
    join pos_schema.cash_register cr on crs.cash_register_id = cr.cash_register_id
    where cr.branch_id = new.branch_id
    and crs.is_active = true
    limit 1;
    
    if _session_id is not null then
        INSERT INTO pos_schema.cash_register_sale(
            cash_register_session_id,
            sale_id,
            transaction_time
        ) VALUES (
            _session_id,
            new.sale_id,
            current_timestamp
        )
        on conflict (sale_id) DO nothing;
        
        raise notice 'Sale % linked to session %', new.sale_id, _session_id;
    else
        raise warning 'No active cash register session for branch %', new.branch_id;
    end if;
    
    return new;
end;
$$ language plpgsql;

drop trigger if exists on_sale_completed_link_sale_to_session on pos_schema.sale;
create trigger on_sale_completed_link_sale_to_session
    after update of is_completed on pos_schema.sale
    for each row
    when (old.is_completed is false and new.is_completed is true)
    execute function link_sale_to_session();

CREATE OR REPLACE FUNCTION calculate_bill_total()
returns trigger as $$
BEGIN
    new.total_amount := new.subtotal_amount + new.tax_amount;
    return new;
end;
$$ language plpgsql;

drop trigger if exists calculate_bill_total_trigger on pos_schema.bill;
create trigger calculate_bill_total_trigger
    before insert or update on pos_schema.bill
    for each row
    execute function calculate_bill_total();

CREATE OR REPLACE FUNCTION calculate_total_price()
returns trigger as $$
BEGIN
    new.total_price := new.quantity * new.unit_price;
    return new;
end;
$$ language plpgsql;

drop trigger if exists calculate_total_price_return_product_trigger on pos_schema.return_product;
create trigger calculate_total_price_return_product_trigger
    before insert or update on pos_schema.return_product
    for each row
    execute function calculate_total_price();

CREATE OR REPLACE FUNCTION pos_schema.get_bill(_sale_id uuid)
returns table (
    bill_id uuid,
    sale_id uuid,
    tenant_customer_id uuid,
    currency_id INTEGER,
    subtotal_amount numeric(10,2),
    tax_amount numeric(10,2),
    total_amount numeric(10,2),
    created_at timestamp,
    updated_at timestamp
) as $$
BEGIN
    return query
    select 
        b.bill_id,
        b.sale_id,
        b.tenant_customer_id,
        b.currency_id,
        b.subtotal_amount,
        b.tax_amount,
        b.total_amount,
        b.created_at,
        b.updated_at
    from pos_schema.bill b
    where b.sale_id = _sale_id;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION create_bill()
returns trigger as $$
declare
    _bill_id uuid;
    _tenant_customer_id uuid;
    _tenant_id uuid;
    _currency_id INTEGER;
    _subtotal numeric(10,2);
    _tax numeric(10,2);
    _total numeric(10,2);
    _payment_ids uuid[];
BEGIN
        raise notice 'Creating bill for sale: %', new.sale_id;
        
        if exists(
            select 1 from pos_schema.bill
            where sale_id = new.sale_id
        ) then
            raise notice 'Bill already exists for sale: %', new.sale_id;
            return new;
        end if;
        
        _tenant_customer_id := (
            select tenant_customer_id 
            from pos_schema.customer_payment 
            where sale_id = new.sale_id 
            limit 1
        );
        
        select tenant_id into _tenant_id
        from general_schema.tenant_customer
        where tenant_customer_id = _tenant_customer_id;
        
        _currency_id := new.currency_id;
        _subtotal := new.subtotal_amount;  
        _tax := new.tax_amount;            
        _total := new.total_amount;        
        
        raise notice '   Customer: %', _tenant_customer_id;
        raise notice '   Tenant: %', _tenant_id;
        raise notice '   Subtotal: $%', _subtotal;
        raise notice '   Tax: $%', _tax;
        raise notice '   Total: $%', _total;

        INSERT INTO pos_schema.bill (
            sale_id,              
            tenant_customer_id,
            currency_id,
            subtotal_amount,
            tax_amount,
            total_amount
        ) VALUES (
            new.sale_id,         
            _tenant_customer_id,
            _currency_id,
            _subtotal,
            _tax,
            _total
        ) returning bill_id into _bill_id;
        
        raise notice '   Bill created: %', _bill_id;
        
        select array_agg(customer_payment_id) into _payment_ids
        from pos_schema.customer_payment
        where sale_id = new.sale_id
        and verified = true;
        
        INSERT INTO pos_schema.bill_payment(bill_id, customer_payment_id, payment_amount)
        select 
            _bill_id,
            customer_payment_id,
            payment_amount
        from pos_schema.customer_payment
        where customer_payment_id = any(_payment_ids);
        
        raise notice '   % payment(s) linked to bill', array_length(_payment_ids, 1);
        raise notice '';
        raise notice 'Bill creation completed successfully';
        raise notice '   Bill ID: %', _bill_id;
        raise notice '   Sale ID: %', new.sale_id;

        return new;
        
    exception
        when others then
            raise notice 'Error creating bill: %', sqlerrm;
            return new;
end;
$$ language plpgsql;

drop trigger if exists on_sale_completed_create_bill on pos_schema.sale;
create trigger on_sale_completed_create_bill
    after update of is_completed on pos_schema.sale
    for each row
    when (old.is_completed is false and new.is_completed is true)
    execute function create_bill();

CREATE OR REPLACE FUNCTION update_on_return()
returns trigger as $$
declare
    _sale_item_record record;
    _bill_id uuid;
    _sale_id uuid;
    _total_returned numeric(10,2) := 0;
    _original_subtotal numeric(10,2);
    _original_tax numeric(10,2);
    _original_total numeric(10,2);
    _new_subtotal numeric(10,2);
    _new_tax numeric(10,2);
    _new_total numeric(10,2);
    _tax_rate numeric(5,2);
    _quantity_remaining INTEGER;
    _sale_subtotal_after numeric(10,2);
    _region_name VARCHAR;
    _tenant_id uuid;
BEGIN
    select 
        si.sale_item_id,
        si.sale_id,
        si.quantity,
        si.unit_price,
        si.total_price,
        si.product_variant_id,
        si.tenant_id
    into _sale_item_record
    from pos_schema.sale_item si
    where si.sale_item_id = new.sale_item_id;

    if not found then
        raise exception 'Sale item not found: %', new.sale_item_id;
    end if;

    _sale_id := _sale_item_record.sale_id;

    -- get bill for sale
    select bill_id into _bill_id from pos_schema.bill where sale_id = _sale_id limit 1;
    if _bill_id is null then
        raise exception 'Bill not found for sale: %', _sale_id;
    end if;

    raise notice 'Bill ID: %', _bill_id;
    raise notice 'Original sale item: qty=% unit=$% total=$%', _sale_item_record.quantity, _sale_item_record.unit_price, _sale_item_record.total_price;

    if new.quantity > _sale_item_record.quantity then
        raise exception 'Cannot return more items than purchased. Purchased: %, Attempting to return: %',
            _sale_item_record.quantity, new.quantity;
    end if;

    _quantity_remaining := _sale_item_record.quantity - new.quantity;
    raise notice 'Return quantity: %  Remaining qty: %', new.quantity, _quantity_remaining;

    -- Update or remove sale_item to reconcile sale
    if _quantity_remaining = 0 then
        delete from pos_schema.sale_item where sale_item_id = _sale_item_record.sale_item_id;
        raise notice 'Sale item removed (quantity = 0)';
    else
        update pos_schema.sale_item
        set quantity = _quantity_remaining,
            total_price = _quantity_remaining * unit_price,
            updated_at = current_timestamp
        where sale_item_id = _sale_item_record.sale_item_id;
        raise notice 'Sale item quantity updated from % to %', _sale_item_record.quantity, _quantity_remaining;
    end if;

    -- Update bill totals
    select subtotal_amount, tax_amount, total_amount into _original_subtotal, _original_tax, _original_total
    from pos_schema.bill where bill_id = _bill_id;

    _total_returned := new.quantity * new.unit_price;
    raise notice 'Amount returned (line): $%', _total_returned;

    _new_subtotal := _original_subtotal - _total_returned;
    if _new_subtotal < 0 then _new_subtotal := 0; end if;

    -- determine tax rate by tenant -> region (fallback to 0 if not found)
    select t.tenant_id, r.region_name into _tenant_id, _region_name
    from general_schema.tenant t
    join general_schema.branch b on b.tenant_id = t.tenant_id
    join pos_schema.sale s on s.branch_id = b.branch_id
    join general_schema.region r on r.region_id = t.region_id
    where s.sale_id = _sale_id
    limit 1;

    select rate_percentage into _tax_rate from general_schema.tax_rate where region = coalesce(_region_name, 'US Federal') limit 1;
    if _tax_rate is null then _tax_rate := 0; end if;

    _new_tax := round(_new_subtotal * (_tax_rate / 100), 2);
    _new_total := round(_new_subtotal + _new_tax, 2);

    update pos_schema.bill
    set subtotal_amount = _new_subtotal,
        tax_amount = _new_tax,
        total_amount = _new_total,
        updated_at = current_timestamp
    where bill_id = _bill_id;

    raise notice 'Bill updated: subtotal $% tax $% total $%', _new_subtotal, _new_tax, _new_total;

    select coalesce(sum(si.total_price),0) into _sale_subtotal_after from pos_schema.sale_item si where si.sale_id = _sale_id;
    _new_tax := round(_sale_subtotal_after * (_tax_rate / 100), 2);
    _new_total := round(_sale_subtotal_after + _new_tax, 2);

    update pos_schema.sale
    set subtotal_amount = _sale_subtotal_after,
        tax_amount = _new_tax,
        total_amount = _new_total,
        updated_at = current_timestamp
    where sale_id = _sale_id;

    raise notice 'Sale updated: subtotal $% tax $% total $%', _sale_subtotal_after, _new_tax, _new_total;

    return new;
end;
$$ language plpgsql;

drop trigger if exists update_on_return_trigger on pos_schema.return_product;
create trigger update_on_return_trigger
    after insert on pos_schema.return_product
    for each row
    execute function update_on_return();


CREATE OR REPLACE FUNCTION auto_toggle_promotions()
returns table(
    action text,
    promotion_id uuid,
    promo_code VARCHAR(50),
    promo_name VARCHAR(100)
) as $$
declare
    _now timestamp := current_timestamp;
    _promo record;
BEGIN
    raise notice 'AUTO-TOGGLE PROMOTIONS';
    raise notice 'Timestamp: %', _now;
    raise notice '';
    
    for _promo in
        select p.promotion_id, p.promo_code, p.promo_name, p.promo_start_date
        from pos_schema.promotion p
        where p.is_active = false
        and p.promo_start_date <= _now
        and p.promo_end_date > _now
    loop
        update pos_schema.promotion
        set is_active = true,
            updated_at = _now
        where promotion_id = _promo.promotion_id;
        
        raise notice 'ACTIVATED: % - % (started: %)', 
            _promo.promo_code, _promo.promo_name, _promo.promo_start_date;
        
        action := 'ACTIVATED';
        promotion_id := _promo.promotion_id;
        promo_code := _promo.promo_code;
        promo_name := _promo.promo_name;
        return next;
    end loop;
    
    for _promo in
        select p.promotion_id, p.promo_code, p.promo_name, p.promo_end_date
        from pos_schema.promotion p
        where p.is_active = true
        and p.promo_end_date <= _now
    loop
        update pos_schema.promotion
        set is_active = false,
            updated_at = _now
        where promotion_id = _promo.promotion_id;
        
        raise notice 'DEACTIVATED: % - % (ended: %)', 
            _promo.promo_code, _promo.promo_name, _promo.promo_end_date;
        
        action := 'DEACTIVATED';
        promotion_id := _promo.promotion_id;
        promo_code := _promo.promo_code;
        promo_name := _promo.promo_name;
        return next;
    end loop;
    
    raise notice '';
    raise notice 'AUTO-TOGGLE COMPLETED';
end;
$$ language plpgsql;

    CREATE OR REPLACE FUNCTION calculate_percentage_discount(
    _promotion_id uuid,
    _quantity INTEGER,
    _unit_price numeric(10,2),
    _total_purchase_amount numeric(10,2)
) returns pos_schema.discount_result as $$
declare
    _rule record;
    _total_price numeric(10,2);
    _discount numeric(10,2);
    _discount_pct numeric(5,2);
    _result pos_schema.discount_result;
BEGIN
    _total_price := _quantity * _unit_price;
    
    select * into _rule
    from pos_schema.promotion_rule
    where promotion_id = _promotion_id
    and discount_percentage is not null
    limit 1;
    
    if not found then
        raise notice '   No percentage discount rule found';
        _result.success := false;
        return _result;
    end if;
    
    if _rule.min_purchase_amount is not null then
        if _total_purchase_amount is null or _total_purchase_amount < _rule.min_purchase_amount then
            raise notice '   Minimum purchase amount not met: $% required, $% provided',
                _rule.min_purchase_amount, coalesce(_total_purchase_amount, 0);
            _result.success := false;
            return _result;
        end if;
    end if;
    
    _discount := _total_price * (_rule.discount_percentage / 100);
    _discount_pct := _rule.discount_percentage;
    
    raise notice '   Applied: % percent discount = $%', _rule.discount_percentage, _discount;
    
    _result.discount_amount := round(_discount, 2);
    _result.discount_percentage := round(_discount_pct, 2);
    _result.rule_description := format('%s%% off', _rule.discount_percentage);
    _result.success := true;
    
    return _result;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION calculate_fixed_discount(
    _promotion_id uuid,
    _quantity INTEGER,
    _unit_price numeric(10,2),
    _total_purchase_amount numeric(10,2)
) returns pos_schema.discount_result as $$
declare
    _rule record;
    _total_price numeric(10,2);
    _discount numeric(10,2);
    _discount_pct numeric(5,2);
    _result pos_schema.discount_result;
BEGIN
    _total_price := _quantity * _unit_price;
    
    select * into _rule
    from pos_schema.promotion_rule
    where promotion_id = _promotion_id
    and discount_amount is not null
    limit 1;
    
    if not found then
        raise notice '   No fixed discount rule found';
        _result.success := false;
        return _result;
    end if;
    
    if _rule.min_purchase_amount is not null then
        if _total_purchase_amount is null or _total_purchase_amount < _rule.min_purchase_amount then
            raise notice '   Minimum purchase amount not met: $% required',
                _rule.min_purchase_amount;
            _result.success := false;
            return _result;
        end if;
    end if;
    
    _discount := least(_rule.discount_amount, _total_price);
    _discount_pct := (_discount / _total_price) * 100;
    
    raise notice '   Applied: $% discount (max: $%)', _discount, _rule.discount_amount;
    
    _result.discount_amount := round(_discount, 2);
    _result.discount_percentage := round(_discount_pct, 2);
    _result.rule_description := format('$%s off', _rule.discount_amount);
    _result.success := true;
    
    return _result;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION calculate_buy_x_get_y_discount(
    _promotion_id uuid,
    _quantity INTEGER,
    _unit_price numeric(10,2),
    _total_purchase_amount numeric(10,2)
) returns pos_schema.discount_result as $$
declare
    _rule record;
    _total_price numeric(10,2);
    _discount numeric(10,2);
    _discount_pct numeric(5,2);
    _free_items INTEGER;
    _result pos_schema.discount_result;
BEGIN
    _total_price := _quantity * _unit_price;
    
    select * into _rule
    from pos_schema.promotion_rule
    where promotion_id = _promotion_id
    and buy_quantity is not null
    and get_quantity is not null
    limit 1;
    
    if not found then
        raise notice '   No buy_x_get_y rule found';
        _result.success := false;
        return _result;
    end if;
    
    if _quantity < _rule.buy_quantity then
        raise notice '   Minimum quantity not met: % required, % provided',
            _rule.buy_quantity, _quantity;
        _result.success := false;
        return _result;
    end if;
    
    _free_items := (_quantity / _rule.buy_quantity) * _rule.get_quantity;
    
    _discount := _free_items * _unit_price * (_rule.get_discount_percentage / 100);
    _discount_pct := (_discount / _total_price) * 100;
    
    raise notice '   Applied: Buy % get % = % free items × $% = $%',
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

CREATE OR REPLACE FUNCTION calculate_volume_discount(
    _promotion_id uuid,
    _quantity INTEGER,
    _unit_price numeric(10,2),
    _total_purchase_amount numeric(10,2)
) returns pos_schema.discount_result as $$
declare
    _rule record;
    _total_price numeric(10,2);
    _discount numeric(10,2);
    _discount_pct numeric(5,2);
    _result pos_schema.discount_result;
BEGIN
    _total_price := _quantity * _unit_price;
    
    select * into _rule
    from pos_schema.promotion_rule
    where promotion_id = _promotion_id
    and min_quantity is not null
    and discount_percentage is not null
    and (min_quantity <= _quantity)
    and (max_quantity is null or max_quantity >= _quantity)
    order by min_quantity desc
    limit 1;
    
    if not found then
        raise notice '   Quantity % does not match any volume tier', _quantity;
        _result.success := false;
        return _result;
    end if;
    
    _discount := _total_price * (_rule.discount_percentage / 100);
    _discount_pct := _rule.discount_percentage;
    
    raise notice '   Applied: Volume discount % percent (min: %, max: %) = $%',
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

CREATE OR REPLACE FUNCTION calculate_tiered_pricing_discount(
    _promotion_id uuid,
    _quantity INTEGER,
    _unit_price numeric(10,2),
    _total_purchase_amount numeric(10,2)
) returns pos_schema.discount_result as $$
declare
    _rule record;
    _total_price numeric(10,2);
    _discount numeric(10,2);
    _discount_pct numeric(5,2);
    _result pos_schema.discount_result;
BEGIN
    _total_price := _quantity * _unit_price;
    
    select * into _rule
    from pos_schema.promotion_rule
    where promotion_id = _promotion_id
    and tier_level is not null
    and tier_min_quantity <= _quantity
    and (tier_max_quantity is null or tier_max_quantity >= _quantity)
    order by tier_level desc
    limit 1;
    
    if not found then
        raise notice '   Quantity % does not match any tier', _quantity;
        _result.success := false;
        return _result;
    end if;
    
    if _rule.tier_price is not null then
        _discount := (_unit_price - _rule.tier_price) * _quantity;
        _discount_pct := ((_unit_price - _rule.tier_price) / _unit_price) * 100;
        
        raise notice '   Applied: Tier % - Fixed price $% per unit = $% discount',
            _rule.tier_level, _rule.tier_price, _discount;
        
        _result.rule_description := format('Tier %s: $%s per unit',
            _rule.tier_level,
            _rule.tier_price);
            
    elsif _rule.tier_discount_percentage is not null then
        _discount := _total_price * (_rule.tier_discount_percentage / 100);
        _discount_pct := _rule.tier_discount_percentage;
        
        raise notice '   Applied: Tier % - % percent discount = $%',
            _rule.tier_level, _rule.tier_discount_percentage, _discount;
        
        _result.rule_description := format('Tier %s: %s%% off',
            _rule.tier_level,
            _rule.tier_discount_percentage);
    else
        raise notice '   Tier found but no price or discount defined';
        _result.success := false;
        return _result;
    end if;
    
    _result.discount_amount := round(_discount, 2);
    _result.discount_percentage := round(_discount_pct, 2);
    _result.success := true;
    
    return _result;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION calculate_combo_discount(
    _promotion_id uuid,
    _quantity INTEGER,
    _unit_price numeric(10,2),
    _total_purchase_amount numeric(10,2)
) returns pos_schema.discount_result as $$
declare
    _result pos_schema.discount_result;
BEGIN
    raise notice '   Combo discounts require multiple products and should be calculated at cart level';
    _result.success := false;
    return _result;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION calculate_promotion_discount(
    _promotion_id uuid,
    _tenant_id uuid,
    _product_variant_id uuid,
    _quantity INTEGER,
    _unit_price numeric(10,2),
    _total_purchase_amount numeric(10,2) default null
) returns table(
    discount_amount numeric(10,2),
    discount_percentage numeric(5,2),
    promotion_type VARCHAR(50),
    rule_applied text
) as $$
declare
    _promo record;
    _type_name VARCHAR(50);
    _result pos_schema.discount_result;
BEGIN
    select 
        p.promotion_id,
        p.promotion_code,
        p.promotion_name,
        p.is_active,
        p.promotion_start_date,
        p.promotion_end_date,
        pt.type_name
    into _promo
    from pos_schema.promotion p
    join pos_schema.promotion_type pt on p.promotion_type_id = pt.promotion_type_id
    where p.promotion_id = _promotion_id
    and p.tenant_id = _tenant_id;
    
    if not found then
        raise notice 'Promotion not found: %', _promotion_id;
        return;
    end if;
    
    if not _promo.is_active then
        raise notice 'Promotion % is not active', _promo.promotion_code;
        return;
    end if;
    
    if current_timestamp not between _promo.promotion_start_date and _promo.promotion_end_date then
        raise notice 'Promotion % is not in valid date range', _promo.promotion_code;
        return;
    end if;
    
    _type_name := _promo.type_name;
    
    raise notice 'Calculating discount for promotion: % (%)', _promo.promotion_name, _type_name;
    raise notice '   Product Variant: %, Quantity: %, Unit Price: $%', _product_variant_id, _quantity, _unit_price;
    
    case _type_name
        when 'percentage_discount' then
            _result := pos_schema.calculate_percentage_discount(
                _promotion_id, _quantity, _unit_price, _total_purchase_amount
            );
            
        when 'fixed_amount_discount' then
            _result := pos_schema.calculate_fixed_discount(
                _promotion_id, _quantity, _unit_price, _total_purchase_amount
            );
            
        when 'buy_x_get_y' then
            _result := pos_schema.calculate_buy_x_get_y_discount(
                _promotion_id, _quantity, _unit_price, _total_purchase_amount
            );
            
        when 'volume_discount' then
            _result := pos_schema.calculate_volume_discount(
                _promotion_id, _quantity, _unit_price, _total_purchase_amount
            );
            
        when 'tiered_pricing' then
            _result := pos_schema.calculate_tiered_pricing_discount(
                _promotion_id, _quantity, _unit_price, _total_purchase_amount
            );
            
        when 'combo' then
            _result := pos_schema.calculate_combo_discount(
                _promotion_id, _quantity, _unit_price, _total_purchase_amount
            );
            
        when 'free_shipping' then
            raise notice '   Free shipping discount (not implemented for products)';
            return;
            
        else
            raise notice '   Unknown promotion type: %', _type_name;
            return;
    end case;
    
    if _result.success then
        return query select 
            _result.discount_amount,
            _result.discount_percentage,
            _type_name::VARCHAR(50),
            _result.rule_description;
    end if;

    return;
    
end;
$$ language plpgsql;

CREATE OR REPLACE PROCEDURE open_close_cash_register_session(
    _cash_register_id uuid,
    _action VARCHAR(10), 
    _amount numeric(10,2)
)
as $$
declare
    _session_id uuid;
    _session record;
    _rows_updated int;
BEGIN
        if _action = 'open' then
            select cash_register_session_id into _session_id
            from pos_schema.cash_register_session
            where cash_register_id = _cash_register_id
            and is_active = true
            limit 1;
            
            if _session_id is not null then
                raise exception 'Cash register % already has an open session: %', 
                    _cash_register_id, _session_id;
            end if;
            
            INSERT INTO pos_schema.cash_register_session (
                cash_register_id,
                opened_at,
                opening_amount,
                is_active,
                created_at,
                updated_at
            ) VALUES (
                _cash_register_id,
                current_timestamp,
                _amount,
                true,
                current_timestamp,
                current_timestamp
            ) returning cash_register_session_id into _session_id;
            
            raise notice 'Cash register % opened', _cash_register_id;
            raise notice '   Session ID: %', _session_id;
            raise notice '   Opening amount: $%', _amount;
            raise notice '   Opened at: %', current_timestamp;
            
        elsif _action = 'close' then
            update pos_schema.cash_register_session
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
            
            raise notice 'Cash register % closed', _cash_register_id;
            raise notice '   Session ID: %', _session.cash_register_session_id;
            raise notice '   Opening amount: $%', _session.opening_amount;
            raise notice '   Closing amount: $%', _session.closing_amount;
            raise notice '   Difference: $%', (_session.closing_amount - _session.opening_amount);
            raise notice '   Duration: %', (_session.closed_at - _session.opened_at);
            
        else
            raise exception 'Invalid action: %. Use "open" or "close"', _action;
        end if;
        
    exception
        when others then
            raise notice 'Error in cash register session: %', sqlerrm;
            raise;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION calculate_purchase_score(
_tenant_id uuid,
_tenant_customer_id uuid,
_purchase_amount numeric(10,2)
) returns INTEGER as $$
declare
    _minimum_purchase numeric(10,2);
    _points_earned_per_currency_unit numeric(5,2);
    _score INTEGER;
    _program_exists BOOLEAN;
BEGIN
        select exists(
            select 1 
            from pos_schema.loyalty_program 
            where tenant_id = _tenant_id 
            and is_active = true
        ) into _program_exists;
        
        if not _program_exists then
            raise notice 'No active loyalty program for tenant %', _tenant_id;
            return 0;
        end if;
        
        select 
            minimum_purchase_for_points, 
            points_earned_per_currency_unit 
        into 
            _minimum_purchase, 
            _points_earned_per_currency_unit 
        from pos_schema.loyalty_program 
        where tenant_id = _tenant_id
        and is_active = true
        limit 1;
        
        _score := floor(_purchase_amount * _points_earned_per_currency_unit);
        
        raise notice 'Points: $% × % = % pts',
            _purchase_amount, _points_earned_per_currency_unit, _score;
        
        return _score;
        
    exception
        when others then
            raise notice 'Error calculating points: %', sqlerrm;
            return 0;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION award_points()
returns trigger as $$
declare
    _tenant_id uuid;
    _tenant_customer_id uuid;
    _bill_id uuid;
    _points_earned INTEGER;
    _current_balance INTEGER;
    _cash_payments_total numeric(10,2);
    _points_already_awarded BOOLEAN;
BEGIN
        _bill_id := new.bill_id;
        
        select exists(
            select 1 
            from pos_schema.score_transaction 
            where bill_id = _bill_id 
            and transaction_type_id = 1  
        ) into _points_already_awarded;
        
        if _points_already_awarded then
            raise notice 'Points already awarded for bill %', _bill_id;
            return new;
        end if;
        
        select tenant_customer_id into _tenant_customer_id
        from pos_schema.bill
        where bill_id = _bill_id;
        
        if _tenant_customer_id is null then
            raise notice 'No customer found for bill %', _bill_id;
            return new;
        end if;
        
        select tenant_id into _tenant_id
        from general_schema.tenant_customer
        where tenant_customer_id = _tenant_customer_id;
        
        if _tenant_id is null then
            raise notice 'Tenant not found for customer %', _tenant_customer_id;
            return new;
        end if;
        
        select coalesce(sum(cp.payment_amount), 0) into _cash_payments_total
        from pos_schema.bill_payment bp
        join pos_schema.customer_payment cp on bp.customer_payment_id = cp.customer_payment_id
        where bp.bill_id = _bill_id
        and cp.is_points_redemption = false;
        
        raise notice 'Cash/card payments total: $%', _cash_payments_total;
        
        _points_earned := pos_schema.calculate_purchase_score(
            _tenant_id,
            _tenant_customer_id,
            _cash_payments_total
        );
        
        if _points_earned <= 0 then
            raise notice 'No points earned for this purchase (Bill: %)', _bill_id;
            return new;
        end if;
        
        INSERT INTO pos_schema.tenant_customer_score(
            tenant_id,
            tenant_customer_id,
            score,
            lifetime_score,
            last_earned_at
        ) VALUES (
            _tenant_id,
            _tenant_customer_id,
            _points_earned,
            _points_earned,
            current_timestamp
        )
        on conflict (tenant_customer_id, tenant_id)
        DO update set
            score = tenant_customer_score.score + _points_earned,
            lifetime_score = tenant_customer_score.lifetime_score + _points_earned,
            last_earned_at = current_timestamp
        returning score into _current_balance;
        
        INSERT INTO pos_schema.score_transaction(
            tenant_id,
            tenant_customer_id,
            transaction_type_id,
            points,
            bill_id,
            created_at
        ) VALUES (
            _tenant_id,
            _tenant_customer_id,
            1,  
            _points_earned,
            _bill_id,
            current_timestamp
        );
        
        raise notice 'Awarded % points to customer %', _points_earned, _tenant_customer_id;
        raise notice 'Bill: %', _bill_id;
        raise notice 'New balance: % points', _current_balance;
        
        return new;
        
    exception
        when others then
            raise notice 'Error awarding points: %', sqlerrm;
            return new;
end;
$$ language plpgsql;

drop trigger if exists on_purchase_billed on pos_schema.bill_payment;
create trigger on_purchase_billed
    after insert on pos_schema.bill_payment
    for each row
    execute function pos_schema.award_points();

CREATE OR REPLACE FUNCTION redeem_points(
_tenant_customer_id uuid,
_points_to_redeem INTEGER
) returns table(
    cash_value numeric(10,2),
    points_available INTEGER,
    success BOOLEAN,
    message text
) as $$
declare
    _points_redeemed_per_currency_unit numeric(10,2); 
    _tenant_id uuid;
    _current_points INTEGER;
    _cash_equivalent numeric(10,2);
BEGIN   
    select tenant_id into _tenant_id
    from general_schema.tenant_customer
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
    from pos_schema.tenant_customer_score
    where tenant_customer_id = _tenant_customer_id
    and tenant_id = _tenant_id;

    select points_redeemed_per_currency_unit into _points_redeemed_per_currency_unit
    from pos_schema.loyalty_program
    where tenant_id = _tenant_id
    and is_active = true
    limit 1;

    if _points_redeemed_per_currency_unit is null then
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

    _cash_equivalent := _points_to_redeem / _points_redeemed_per_currency_unit;

    update pos_schema.tenant_customer_score
    set score = score - _points_to_redeem,
        score_redeemed = score_redeemed + _points_to_redeem,
        last_redeemed_at = current_timestamp,
        updated_at = current_timestamp
    where tenant_customer_id = _tenant_customer_id
    and tenant_id = _tenant_id;

    INSERT INTO pos_schema.score_transaction(
        tenant_id,
        tenant_customer_id,
        transaction_type_id,
        points,
        created_at
    ) VALUES (
        _tenant_id,
        _tenant_customer_id,
        2,  
        -_points_to_redeem,  
        current_timestamp
    );

    return query select 
        round(_cash_equivalent, 2)::numeric(10,2),
        _current_points - _points_to_redeem,
        true,
        format('Redeemed %s points at rate %s pts/$1 = $%s', 
            _points_to_redeem, 
            _points_redeemed_per_currency_unit, 
            round(_cash_equivalent, 2))::text;
    exception
        when others then
            raise notice 'Error redeeming points: %', sqlerrm;
            return query select 
                0.00::numeric(10,2),
                coalesce(_current_points, 0),
                false,
                sqlerrm::text;
end;
$$ language plpgsql;

CREATE OR REPLACE PROCEDURE verify_customer_payment(_payment_id uuid)
as $$
declare
    _exists BOOLEAN;
    _already_verified BOOLEAN;
    _tenant_customer_id uuid;
    _sale_id uuid;
    _payment_amount numeric(10,2);
    _payment_method VARCHAR(50);
    _is_points_redemption BOOLEAN;
    _points_redeemed INTEGER;
    _redeem_result record;
    _sale_completed BOOLEAN;
BEGIN
    select exists(
        select 1 
        from pos_schema.customer_payment 
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
    from pos_schema.customer_payment 
    where customer_payment_id = _payment_id;
    
    if _already_verified then
        raise notice 'Payment % is already verified', _payment_id;
        return;
    end if;
    
    if _sale_id is null then
        raise exception 'Payment % has no associated sale', _payment_id;
    end if;
    
    raise notice 'Verifying payment: %', _payment_id;
    raise notice '   Sale: %', _sale_id;
    raise notice '   Customer: %', _tenant_customer_id;
    raise notice '   Amount: $%', _payment_amount;
    
    select name into _payment_method
    from general_schema.payment_method pm
    join pos_schema.customer_payment cp on pm.payment_method_id = cp.payment_method_id
    where cp.customer_payment_id = _payment_id;
    
    raise notice '   Method: %', _payment_method;
    raise notice '';
    
    if _is_points_redemption then
        raise notice 'Processing points redemption...';
        raise notice '   Points to redeem: %', _points_redeemed;
        
        select * into _redeem_result
        from pos_schema.redeem_points(
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
        
        raise notice '   Redeemed % points = $%', _points_redeemed, _payment_amount;
        raise notice '   %', _redeem_result.message;
        raise notice '   Remaining points: %', _redeem_result.points_available;
        raise notice '';
    end if;

    update pos_schema.customer_payment
    set verified = true,
        updated_at = current_timestamp
    where customer_payment_id = _payment_id;
    
    raise notice 'Payment verified successfully';
    raise notice '';
    
    raise notice 'Checking if sale is fully paid...';
    _sale_completed := pos_schema.check_sale_payment_completion(_sale_id);
    
    if _sale_completed then
        raise notice '';
        raise notice 'Sale % is COMPLETED - Trigger will create bill', _sale_id;
    else
        raise notice '';
        raise notice 'Sale % is PENDING - Waiting for more payments', _sale_id;
    end if;
    
    exception
        when others then
            raise notice '  Payment verification failed: %', sqlerrm;
            raise;
end;
$$ language plpgsql;      

-- ==========================
-- UPDATE TIMESTAMP TRIGGERS
-- ==========================

drop trigger if exists update_customer_payment_timestamp on pos_schema.customer_payment;
create trigger update_customer_payment_timestamp before update on pos_schema.customer_payment
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_bill_timestamp on pos_schema.bill;
create trigger update_bill_timestamp before update on pos_schema.bill
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_return_transaction_timestamp on pos_schema.return_transaction;
create trigger update_return_transaction_timestamp before update on pos_schema.return_transaction
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_return_product_timestamp on pos_schema.return_product;
create trigger update_return_product_timestamp before update on pos_schema.return_product
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_promotion_timestamp on pos_schema.promotion;
create trigger update_promotion_timestamp before update on pos_schema.promotion
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_promotion_rule_timestamp on pos_schema.promotion_rule;
create trigger update_promotion_rule_timestamp before update on pos_schema.promotion_rule
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_cash_register_session_timestamp on pos_schema.cash_register_session;
create trigger update_cash_register_session_timestamp before update on pos_schema.cash_register_session
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_cash_register_sale_timestamp on pos_schema.cash_register_sale;
create trigger update_cash_register_sale_timestamp before update on pos_schema.cash_register_sale
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_tenant_customer_score_timestamp on pos_schema.tenant_customer_score;
create trigger update_tenant_customer_score_timestamp before update on pos_schema.tenant_customer_score
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_score_transaction_timestamp on pos_schema.score_transaction;
create trigger update_score_transaction_timestamp before update on pos_schema.score_transaction
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_bill_payment_timestamp on pos_schema.bill_payment;
create trigger update_bill_payment_timestamp before update on pos_schema.bill_payment
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_sale_timestamp on pos_schema.sale;
create trigger update_sale_timestamp before update on pos_schema.sale
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_sale_item_timestamp on pos_schema.sale_item;
create trigger update_sale_item_timestamp before update on pos_schema.sale_item
for each row execute function general_schema.update_timestamp();





-- =============================================
-- FUNCTIONS: PURCHASE
-- Source: functions/purchase/purchase_functions.sql
-- =============================================
SET SEARCH_PATH = purchase_schema;

CREATE OR REPLACE FUNCTION calculate_purchase_order_total(
    p_purchase_order_id uuid
) returns numeric as $$
declare
    v_total numeric(12,3);
BEGIN
    select coalesce(sum(quantity_ordered * unit_price), 0)
    into v_total
    from purchase_schema.purchase_order_item
    where purchase_order_id = p_purchase_order_id;

    return round(v_total::numeric, 3);
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION create_purchase_order(
    p_supplier_id uuid,
    p_warehouse_id uuid,
    p_expected_delivery_date date,
    p_items jsonb default '[]'::jsonb,
    p_has_invoice BOOLEAN default true,
    p_payment_condition VARCHAR(10) default 'CREDIT'
) returns uuid as $$
declare
    v_purchase_order_id uuid;
    v_supplier_invoice_id uuid;
    v_item jsonb;
    v_tenant_id uuid;
    v_product_id uuid;
    v_qty INTEGER;
    v_unit numeric(12,3);
    v_subtotal numeric(12,3);
    v_tax_rate numeric(5,2);
    v_tax_amount numeric(12,3);
    v_account_payable_id uuid;
    v_account_payable_type_id int;
    v_due_date date;
BEGIN
    -- Obtener tenant_id desde la relación supplier -> supplier_branch -> branch
    select b.tenant_id into v_tenant_id
    from purchase_schema.supplier s
    join purchase_schema.supplier_branch sb on s.supplier_id = sb.supplier_id
    join general_schema.branch b on b.branch_id = sb.branch_id
    where s.supplier_id = p_supplier_id
    limit 1;

    if v_tenant_id is null then
        raise exception 'Cannot determine tenant_id for supplier %', p_supplier_id;
    end if;

    -- Crear la orden de compra
    INSERT INTO purchase_schema.purchase_order(
        supplier_id,
        warehouse_id,
        expected_delivery_date,
        purchase_order_status_id
    ) VALUES (
        p_supplier_id,
        p_warehouse_id,
        p_expected_delivery_date,
        1  -- Pending
    ) returning purchase_order_id into v_purchase_order_id;

    -- Insertar items si se proporcionaron
    if p_items is not null and jsonb_typeof(p_items) = 'array' and jsonb_array_length(p_items) > 0 then
        for v_item in select value from jsonb_array_elements(p_items)
        loop
            v_product_id := (v_item ->> 'product_variant_id')::uuid;
            v_qty := coalesce((v_item ->> 'quantity_ordered')::int, 0);
            v_unit := coalesce((v_item ->> 'unit_price')::numeric, 0);

            INSERT INTO purchase_schema.purchase_order_item(
                purchase_order_id,
                tenant_id,
                product_variant_id,
                quantity_ordered,
                unit_price
            ) VALUES (
                v_purchase_order_id,
                v_tenant_id,
                v_product_id,
                v_qty,
                v_unit
            );
        end loop;
    end if;

    -- Calcular subtotal de la orden
    v_subtotal := coalesce(purchase_schema.calculate_purchase_order_total(v_purchase_order_id), 0);

    -- Obtener tasa de impuesto del tenant
    select coalesce(tr.rate_percentage, 13.00) into v_tax_rate
    from general_schema.tenant t
    left join general_schema.tax_rate tr on tr.region_id = t.region_id
    where t.tenant_id = v_tenant_id
    limit 1;

    -- Calcular impuesto
    v_tax_amount := round(v_subtotal * (v_tax_rate / 100.0), 3);

    -- Calcular fecha de vencimiento (30 días por defecto)
    v_due_date := (current_date + interval '30 days')::date;

    -- Obtener el ID del tipo de cuenta por pagar 'goods_purchase'
    select account_payable_type_id into v_account_payable_type_id
    from general_schema.account_payable_type
    where type_name = 'goods_purchase'
    limit 1;

    if v_account_payable_type_id is null then
        raise exception 'Account payable type "goods_purchase" not found';
    end if;

    -- ✅ PASO 1: Crear registro en la tabla PADRE (general_schema.account_payable)
    INSERT INTO general_schema.account_payable(
        account_payable_type_id,
        has_invoice,
        has_tax,
        subtotal,
        amount_paid,
        is_paid,
        due_date
    ) VALUES (
        v_account_payable_type_id,
        p_has_invoice,
        true,  -- Las órdenes de suministro siempre tienen impuesto
        v_subtotal,
        0,  -- Inicial
        false,  -- Inicial
        v_due_date
    ) returning account_payable_id into v_account_payable_id;

    -- ✅ PASO 2: Crear registro en la tabla HIJA (purchase_account_payable)
    INSERT INTO purchase_schema.purchase_account_payable(
        account_payable_id,
        purchase_order_id,
        tax_amount,
        account_payable_status
    ) VALUES (
        v_account_payable_id,
        v_purchase_order_id,
        v_tax_amount,
        1  -- Pending
    );

    -- Crear factura si se requiere
    if p_has_invoice then
        INSERT INTO purchase_schema.supplier_invoice(
            purchase_order_id,
            invoice_number,
            invoice_date,
            payment_condition,
            due_date,
            subtotal_amount,
            tax_rate
        ) VALUES (
            v_purchase_order_id,
            'INV-' || to_char(current_timestamp, 'YYYYMMDD-HH24MISS') || '-' || substring(v_purchase_order_id::text, 1, 8),
            current_timestamp,
            p_payment_condition,
            v_due_date,
            v_subtotal,
            v_tax_rate
        ) returning supplier_invoice_id into v_supplier_invoice_id;

        -- Crear items de factura desde los items de la orden
        INSERT INTO purchase_schema.supplier_invoice_item(
            supplier_invoice_id,
            tenant_id,
            product_variant_id,
            quantity_billed,
            unit_price
        )
        select 
            v_supplier_invoice_id,
            tenant_id,
            product_variant_id,
            quantity_ordered,
            unit_price
        from purchase_schema.purchase_order_item
        where purchase_order_id = v_purchase_order_id;
    end if;

    return v_purchase_order_id;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION update_order_status()
returns trigger as $$
BEGIN
    INSERT INTO purchase_schema.purchase_order_tracking(
        purchase_order_id,
        previous_status_id,
        new_status_id,
        notes,
        changed_at
    ) VALUES (
        new.purchase_order_id,
        old.purchase_order_status_id,
        new.purchase_order_status_id,
        'Status updated via trigger',
        current_timestamp
    );

    return new;
end;
$$ language plpgsql;

drop trigger if exists on_order_status_update on purchase_schema.purchase_order;
create trigger on_order_status_update
after update of purchase_order_status_id on purchase_schema.purchase_order
for each row execute function update_order_status();

DROP FUNCTION IF EXISTS check_account_payable_completion(UUID);

CREATE OR REPLACE FUNCTION check_account_payable_completion(
    _account_payable_id UUID
) RETURNS BOOLEAN AS $$
DECLARE
    _subtotal NUMERIC(12,3);
    _tax_amount NUMERIC(12,3);
    _amount_due NUMERIC(12,3);
    _current_amount_paid NUMERIC(12,3);
    _payments_total NUMERIC(12,3);
    _balance NUMERIC(12,3);
    _pending_payments INT;
    _target_purchase_ap_id UUID;
BEGIN
    SELECT 
        ap.subtotal,
        sap.tax_amount,
        (ap.subtotal + COALESCE(sap.tax_amount, 0)) AS amount_due,
        ap.amount_paid,
        sap.purchase_account_payable_id
    INTO 
        _subtotal,
        _tax_amount,
        _amount_due,
        _current_amount_paid,
        _target_purchase_ap_id
    FROM general_schema.account_payable ap
    JOIN purchase_schema.purchase_account_payable sap 
        ON ap.account_payable_id = sap.account_payable_id
    WHERE ap.account_payable_id = _account_payable_id;

    IF _amount_due IS NULL THEN
        RAISE EXCEPTION 'Account payable not found: %', _account_payable_id;
    END IF;

    SELECT COUNT(*) INTO _pending_payments
    FROM purchase_schema.purchase_order_payment sop
    WHERE sop.purchase_account_payable_id = _target_purchase_ap_id
    AND sop.verified = FALSE;

    IF _pending_payments > 0 THEN
        RETURN FALSE;
    END IF;

    SELECT COALESCE(SUM(sop.amount_paid), 0) INTO _payments_total
    FROM purchase_schema.purchase_order_payment sop
    WHERE sop.purchase_account_payable_id = _target_purchase_ap_id
    AND sop.verified = TRUE;

    _balance := _amount_due - _payments_total;

    UPDATE general_schema.account_payable
    SET amount_paid = _payments_total,
        updated_at = CURRENT_TIMESTAMP
    WHERE account_payable_id = _account_payable_id;

    IF ABS(_balance) <= 0.01 OR _payments_total >= _amount_due THEN
        UPDATE general_schema.account_payable
        SET is_paid = TRUE,
            updated_at = CURRENT_TIMESTAMP
        WHERE account_payable_id = _account_payable_id;

        UPDATE purchase_schema.purchase_account_payable
        SET account_payable_status = 3,
            updated_at = CURRENT_TIMESTAMP
        WHERE account_payable_id = _account_payable_id;

        RETURN TRUE;

    ELSIF _payments_total > 0 THEN
        UPDATE purchase_schema.purchase_account_payable
        SET account_payable_status = 2,
            updated_at = CURRENT_TIMESTAMP
        WHERE account_payable_id = _account_payable_id;

        RETURN FALSE;

    ELSE
        RETURN FALSE;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION recalc_account_payable_on_payment()
returns trigger as $$
BEGIN
    if new.verified = true and (old.verified is null or old.verified = false) then
        perform purchase_schema.check_account_payable_completion(
            (select account_payable_id 
             from purchase_schema.purchase_account_payable 
             where purchase_account_payable_id = new.purchase_account_payable_id)
        );
    end if;
    return new;
end;
$$ language plpgsql;

drop trigger if exists recalc_account_payable_on_payment_trigger on purchase_schema.purchase_order_payment;
create trigger recalc_account_payable_on_payment_trigger
    after update of verified on purchase_schema.purchase_order_payment
    for each row
    execute function recalc_account_payable_on_payment();

CREATE OR REPLACE FUNCTION update_invoice_paid_status()
returns trigger as $$
declare
    v_is_paid BOOLEAN;
BEGIN
    if new.account_payable_status = 3 and old.account_payable_status is distinct from 3 then
        select is_paid into v_is_paid
        from general_schema.account_payable
        where account_payable_id = new.account_payable_id;
        
        if v_is_paid = true then
            update purchase_schema.supplier_invoice
            set paid = true,
                updated_at = current_timestamp
            where purchase_order_id = new.purchase_order_id;
        end if;
    end if;
    
    return new;
end;
$$ language plpgsql;

drop trigger if exists update_invoice_paid_status_trigger on purchase_schema.purchase_account_payable;
create trigger update_invoice_paid_status_trigger
    after update of account_payable_status on purchase_schema.purchase_account_payable
    for each row
    execute function purchase_schema.update_invoice_paid_status();

CREATE OR REPLACE FUNCTION create_goods_receipt()
returns trigger as $$
declare
    v_goods_receipt_id uuid;
    v_subtotal numeric(12,3);
    v_tax_amount numeric(12,3);
    v_item record;
BEGIN
    if new.purchase_order_status_id = 3 and old.purchase_order_status_id is distinct from 3 then
        if exists(
            select 1 
            from purchase_schema.goods_receipt 
            where purchase_order_id = new.purchase_order_id
        ) then
            return new;
        end if;

        select 
            ap.subtotal,
            sap.tax_amount
        into v_subtotal, v_tax_amount
        from general_schema.account_payable ap
        join purchase_schema.purchase_account_payable sap 
            on ap.account_payable_id = sap.account_payable_id
        where sap.purchase_order_id = new.purchase_order_id;

        INSERT INTO purchase_schema.goods_receipt(
            purchase_order_id,
            received_date,
            subtotal_amount,
            tax_amount
        ) VALUES (
            new.purchase_order_id,
            current_timestamp,
            v_subtotal,
            v_tax_amount
        ) returning goods_receipt_id into v_goods_receipt_id;

        for v_item in 
            select tenant_id, product_variant_id, quantity_ordered
            from purchase_schema.purchase_order_item
            where purchase_order_id = new.purchase_order_id
        loop
            INSERT INTO purchase_schema.goods_receipt_item(
                goods_receipt_id,
                tenant_id,
                product_variant_id,
                quantity_received
            ) VALUES (
                v_goods_receipt_id,
                v_item.tenant_id,
                v_item.product_variant_id,
                v_item.quantity_ordered
            );
        end loop;

        perform purchase_schema.execute_three_way_matching(new.purchase_order_id, v_goods_receipt_id);
    end if;

    return new;
end;
$$ language plpgsql;

drop trigger if exists create_goods_receipt_trigger on purchase_schema.purchase_order;
create trigger create_goods_receipt_trigger
    after update of purchase_order_status_id on purchase_schema.purchase_order
    for each row
    execute function purchase_schema.create_goods_receipt();

CREATE OR REPLACE FUNCTION execute_three_way_matching(
    p_purchase_order_id uuid,
    p_goods_receipt_id uuid
) returns void as $$
declare
    v_supplier_invoice_id uuid;
    v_order_subtotal numeric(12,3);
    v_order_tax numeric(12,3);
    v_order_total numeric(12,3);
    v_invoice_subtotal numeric(12,3);
    v_invoice_tax numeric(12,3);
    v_invoice_total numeric(12,3);
    v_receipt_subtotal numeric(12,3);
    v_receipt_tax numeric(12,3);
    v_receipt_total numeric(12,3);
    v_order_qty INTEGER;
    v_invoice_qty INTEGER;
    v_receipt_qty INTEGER;
    v_amounts_matched BOOLEAN;
    v_quantities_matched BOOLEAN;
BEGIN
    select supplier_invoice_id into v_supplier_invoice_id
    from purchase_schema.supplier_invoice
    where purchase_order_id = p_purchase_order_id;

    if v_supplier_invoice_id is null then
        return;
    end if;

    if exists(
        select 1 
        from purchase_schema.three_way_matching 
        where purchase_order_id = p_purchase_order_id
    ) then
        return;
    end if;

    select 
        ap.subtotal,
        sap.tax_amount,
        (ap.subtotal + sap.tax_amount) AS total_amount
    into 
        v_order_subtotal,
        v_order_tax,
        v_order_total
    from general_schema.account_payable ap
    join purchase_schema.purchase_account_payable sap 
        on ap.account_payable_id = sap.account_payable_id
    where sap.purchase_order_id = p_purchase_order_id;

    select 
        subtotal_amount,
        tax_amount,
        total_amount
    into 
        v_invoice_subtotal,
        v_invoice_tax,
        v_invoice_total
    from purchase_schema.supplier_invoice
    where supplier_invoice_id = v_supplier_invoice_id;

    select 
        subtotal_amount,
        tax_amount,
        total_amount
    into 
        v_receipt_subtotal,
        v_receipt_tax,
        v_receipt_total
    from purchase_schema.goods_receipt
    where goods_receipt_id = p_goods_receipt_id;

    select coalesce(sum(quantity_ordered), 0) into v_order_qty
    from purchase_schema.purchase_order_item
    where purchase_order_id = p_purchase_order_id;

    select coalesce(sum(quantity_billed), 0) into v_invoice_qty
    from purchase_schema.supplier_invoice_item
    where supplier_invoice_id = v_supplier_invoice_id;

    select coalesce(sum(quantity_received), 0) into v_receipt_qty
    from purchase_schema.goods_receipt_item
    where goods_receipt_id = p_goods_receipt_id;

    v_amounts_matched := (abs(v_order_subtotal - v_invoice_subtotal) <= 0.01) and 
                         (abs(v_order_subtotal - v_receipt_subtotal) <= 0.01) and
                         (abs(v_invoice_subtotal - v_receipt_subtotal) <= 0.01) and
                         (abs(v_order_tax - v_invoice_tax) <= 0.01) and
                         (abs(v_order_tax - v_receipt_tax) <= 0.01) and
                         (abs(v_invoice_tax - v_receipt_tax) <= 0.01) and
                         (abs(v_order_total - v_invoice_total) <= 0.01) and
                         (abs(v_order_total - v_receipt_total) <= 0.01) and
                         (abs(v_invoice_total - v_receipt_total) <= 0.01);
    
    v_quantities_matched := (v_order_qty = v_invoice_qty) and 
                            (v_order_qty = v_receipt_qty);

    INSERT INTO purchase_schema.three_way_matching(
        purchase_order_id,
        goods_receipt_id,
        supplier_invoice_id,
        amounts_matched,
        quantities_matched,
        is_matched,
        matched_at
    ) VALUES (
        p_purchase_order_id,
        p_goods_receipt_id,
        v_supplier_invoice_id,
        v_amounts_matched,
        v_quantities_matched,
        v_amounts_matched and v_quantities_matched,
        current_timestamp
    );
    
exception
    when others then
        raise exception 'Error executing three-way matching: %', sqlerrm;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION generate_payment_alerts()
returns void as $$
declare
    v_config record;
    v_account record;
    v_days_until_due INTEGER;
    v_alert_type_id INTEGER;
    v_existing_alert_id uuid;
BEGIN
    for v_config in 
        select 
            pac.tenant_id,
            pac.warning_days_before_due,
            pac.urgent_days_before_due
        from purchase_schema.purchase_order_payment_alert_config pac
    loop
        for v_account in
            select 
                ap.account_payable_id,
                ap.due_date,
                ap.is_paid,
                ap.amount_paid,
                ap.subtotal,
                sap.purchase_account_payable_id,
                sap.tax_amount,
                (ap.subtotal + coalesce(sap.tax_amount, 0) - ap.amount_paid) as balance_remaining,
                so.purchase_order_id
            from general_schema.account_payable ap
            join purchase_schema.purchase_account_payable sap 
                on ap.account_payable_id = sap.account_payable_id
            join purchase_schema.purchase_order so 
                on sap.purchase_order_id = so.purchase_order_id
            join purchase_schema.supplier s 
                on so.supplier_id = s.supplier_id
            join purchase_schema.supplier_branch sb 
                on s.supplier_id = sb.supplier_id
            join general_schema.branch b 
                on sb.branch_id = b.branch_id
            where b.tenant_id = v_config.tenant_id
            and ap.is_paid = false
            and (ap.subtotal + coalesce(sap.tax_amount, 0) - ap.amount_paid) > 0
        loop
            v_days_until_due := v_account.due_date - current_date;
            
  
            if v_days_until_due < 0 then
                v_alert_type_id := 3; 
            elsif v_days_until_due <= v_config.urgent_days_before_due then
                v_alert_type_id := 2; 
            elsif v_days_until_due <= v_config.warning_days_before_due then
                v_alert_type_id := 1; 
            else
                continue; 
            end if;
            
            select payment_alert_id into v_existing_alert_id
            from purchase_schema.purchase_order_payment_alert
            where purchase_account_payable_id = v_account.purchase_account_payable_id
            and payment_alert_type_id = v_alert_type_id
            and is_resolved = false
            limit 1;
            
            if v_existing_alert_id is null then
                INSERT INTO purchase_schema.purchase_order_payment_alert(
                    purchase_account_payable_id,
                    payment_alert_type_id,
                    alert_date,
                    is_resolved
                ) VALUES (
                    v_account.purchase_account_payable_id,
                    v_alert_type_id,
                    current_timestamp,
                    false
                );
            end if;
        end loop;
    end loop;
    
exception
    when others then
        raise exception 'Error generating payment alerts: %', sqlerrm;
end;
$$ language plpgsql;

drop function if exists get_pending_payment_alerts(uuid);

CREATE OR REPLACE FUNCTION get_pending_payment_alerts(p_tenant_id uuid)
returns table(
    payment_alert_id uuid,
    purchase_account_payable_id uuid,
    purchase_order_id uuid,
    supplier_name VARCHAR,
    invoice_number VARCHAR,
    alert_type VARCHAR,
    alert_type_description text,
    due_date date,
    days_until_due INTEGER,
    balance_remaining numeric,
    alert_date timestamp,
    created_at timestamp
) as $$
BEGIN
    return query
    select 
        spa.payment_alert_id,
        sap.purchase_account_payable_id,
        so.purchase_order_id,
        s.supplier_name,
        si.invoice_number,
        spat.payment_alert_type_name,
        spat.description,
        ap.due_date,
        (ap.due_date - current_date)::INTEGER as days_until_due,
        (ap.subtotal + coalesce(sap.tax_amount, 0) - ap.amount_paid) as balance_remaining,
        spa.alert_date,
        spa.created_at
    from purchase_schema.purchase_order_payment_alert spa
    join purchase_schema.purchase_order_payment_alert_type spat 
        on spa.payment_alert_type_id = spat.payment_alert_type_id
    join purchase_schema.purchase_account_payable sap 
        on spa.purchase_account_payable_id = sap.purchase_account_payable_id
    join general_schema.account_payable ap 
        on sap.account_payable_id = ap.account_payable_id
    join purchase_schema.purchase_order so 
        on sap.purchase_order_id = so.purchase_order_id
    join purchase_schema.supplier s 
        on so.supplier_id = s.supplier_id
    left join purchase_schema.supplier_invoice si 
        on so.purchase_order_id = si.purchase_order_id
    join purchase_schema.supplier_branch sb 
        on s.supplier_id = sb.supplier_id
    join general_schema.branch b 
        on sb.branch_id = b.branch_id
    where b.tenant_id = p_tenant_id
    and spa.is_resolved = false
    order by ap.due_date asc, spa.alert_date desc;
    
exception
    when others then
        raise exception 'Error fetching pending payment alerts: %', sqlerrm;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION resolve_payment_alert(p_alert_id uuid)
returns void as $$
BEGIN
    update purchase_schema.purchase_order_payment_alert
    set is_resolved = true,
        updated_at = current_timestamp
    where payment_alert_id = p_alert_id;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION auto_resolve_payment_alerts()
returns trigger as $$
declare
    v_is_paid BOOLEAN;
BEGIN
    if new.account_payable_status = 3 and old.account_payable_status is distinct from 3 then
        select is_paid into v_is_paid
        from general_schema.account_payable
        where account_payable_id = new.account_payable_id;
        
        if v_is_paid = true then
            update purchase_schema.purchase_order_payment_alert
            set is_resolved = true,
                updated_at = current_timestamp
            where purchase_account_payable_id = new.purchase_account_payable_id
            and is_resolved = false;
        end if;
    end if;
    
    return new;
end;
$$ language plpgsql;

drop trigger if exists auto_resolve_payment_alerts_trigger on purchase_schema.purchase_account_payable;
create trigger auto_resolve_payment_alerts_trigger
    after update of account_payable_status on purchase_schema.purchase_account_payable
    for each row
    execute function purchase_schema.auto_resolve_payment_alerts();

CREATE OR REPLACE FUNCTION initialize_payment_alert_config(
    p_tenant_id uuid,
    p_warning_days INTEGER default 7,
    p_urgent_days INTEGER default 3,
    p_email_enabled BOOLEAN default true,
    p_sms_enabled BOOLEAN default false
) returns uuid as $$
declare
    v_config_id uuid;
BEGIN
    INSERT INTO purchase_schema.purchase_order_payment_alert_config(
        tenant_id,
        warning_days_before_due,
        urgent_days_before_due,
        email_notifications_enabled,
        sms_notifications_enabled
    ) VALUES (
        p_tenant_id,
        p_warning_days,
        p_urgent_days,
        p_email_enabled,
        p_sms_enabled
    )
    on conflict (tenant_id) DO update
    set warning_days_before_due = excluded.warning_days_before_due,
        urgent_days_before_due = excluded.urgent_days_before_due,
        email_notifications_enabled = excluded.email_notifications_enabled,
        sms_notifications_enabled = excluded.sms_notifications_enabled,
        updated_at = current_timestamp
    returning payment_alert_config_id into v_config_id;
    
    return v_config_id;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION get_payment_alert_stats(p_tenant_id uuid)
returns table(
    total_alerts INTEGER,
    overdue_count INTEGER,
    urgent_count INTEGER,
    warning_count INTEGER,
    total_amount_at_risk numeric
) as $$
BEGIN
    return query
    select 
        count(*)::INTEGER as total_alerts,
        count(*) filter (where spat.payment_alert_type_id = 3)::INTEGER as overdue_count,
        count(*) filter (where spat.payment_alert_type_id = 2)::INTEGER as urgent_count,
        count(*) filter (where spat.payment_alert_type_id = 1)::INTEGER as warning_count,
        coalesce(sum(ap.subtotal + coalesce(sap.tax_amount, 0) - ap.amount_paid), 0) as total_amount_at_risk
    from purchase_schema.purchase_order_payment_alert spa
    join purchase_schema.purchase_order_payment_alert_type spat 
        on spa.payment_alert_type_id = spat.payment_alert_type_id
    join purchase_schema.purchase_account_payable sap 
        on spa.purchase_account_payable_id = sap.purchase_account_payable_id
    join general_schema.account_payable ap 
        on sap.account_payable_id = ap.account_payable_id
    join purchase_schema.purchase_order so 
        on sap.purchase_order_id = so.purchase_order_id
    join purchase_schema.supplier s 
        on so.supplier_id = s.supplier_id
    join purchase_schema.supplier_branch sb 
        on s.supplier_id = sb.supplier_id
    join general_schema.branch b 
        on sb.branch_id = b.branch_id
    where b.tenant_id = p_tenant_id
    and spa.is_resolved = false;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error calculating payment alert stats: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;


drop trigger if exists update_supplier_timestamp on purchase_schema.supplier;
create trigger update_supplier_timestamp before update on purchase_schema.supplier
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_purchase_order_timestamp on purchase_schema.purchase_order;
create trigger update_purchase_order_timestamp before update on purchase_schema.purchase_order
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_purchase_order_item_timestamp on purchase_schema.purchase_order_item;
create trigger update_purchase_order_item_timestamp before update on purchase_schema.purchase_order_item
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_supplier_invoice_timestamp on purchase_schema.supplier_invoice;
create trigger update_supplier_invoice_timestamp before update on purchase_schema.supplier_invoice
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_supplier_invoice_item_timestamp on purchase_schema.supplier_invoice_item;
create trigger update_supplier_invoice_item_timestamp before update on purchase_schema.supplier_invoice_item
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_goods_receipt_timestamp on purchase_schema.goods_receipt;
create trigger update_goods_receipt_timestamp before update on purchase_schema.goods_receipt
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_goods_receipt_item_timestamp on purchase_schema.goods_receipt_item;
create trigger update_goods_receipt_item_timestamp before update on purchase_schema.goods_receipt_item
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_account_payable_timestamp on purchase_schema.purchase_account_payable;
create trigger update_account_payable_timestamp before update on purchase_schema.purchase_account_payable
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_purchase_order_payment_timestamp on purchase_schema.purchase_order_payment;
create trigger update_purchase_order_payment_timestamp before update on purchase_schema.purchase_order_payment
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_purchase_order_payment_alert_timestamp on purchase_schema.purchase_order_payment_alert;
create trigger update_purchase_order_payment_alert_timestamp before update on purchase_schema.purchase_order_payment_alert
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_purchase_order_payment_alert_config_timestamp on purchase_schema.purchase_order_payment_alert_config;
create trigger update_purchase_order_payment_alert_config_timestamp before update on purchase_schema.purchase_order_payment_alert_config
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_three_way_matching_timestamp on purchase_schema.three_way_matching;
create trigger update_three_way_matching_timestamp before update on purchase_schema.three_way_matching
for each row execute function general_schema.update_timestamp();



-- =============================================
-- FUNCTIONS: HR
-- Source: functions/hr/hr_functions.sql
-- =============================================
SET SEARCH_PATH = hr_schema;

CREATE OR REPLACE FUNCTION hr_schema.create_new_employee(
  -- Parametros para la creacion del contrato
  p_start_date DATE,
  p_end_date DATE,
  p_hours INTEGER,
  p_base_salary DECIMAL(10, 2),
  p_duties TEXT,

  -- Parametros para la crecaion del empleado
  p_user_id UUID,
  p_tenant_id UUID,
  p_first_name VARCHAR(100),
  p_last_name VARCHAR(100),
  p_doc_number VARCHAR(100),
  p_phone VARCHAR(100),
  p_email VARCHAR(100),
  p_schedule_id INTEGER
)
RETURNS UUID AS $$

DECLARE
  v_new_contract_id UUID;
  v_new_employee_id UUID;
BEGIN

  IF NOT EXISTS (SELECT 1 FROM hr_schema.payment_schedule WHERE payment_schedule_id = p_schedule_id) THEN
    RAISE EXCEPTION 'Integrity error: schedule_id (schedule_id: %) doesnt exists', p_schedule_id;
  END IF;

  INSERT INTO hr_schema.contract (start_date, end_date, hours, base_salary, duties)
  VALUES (p_start_date, p_end_date, p_hours, p_base_salary, p_duties)
  RETURNING contract_id INTO v_new_contract_id;

  v_new_employee_id := gen_random_uuid();

  INSERT INTO hr_schema.employee (employee_id, user_id, first_name, last_name, doc_number, phone, email, contract_id, schedule_id, tenant_id)
  VALUES (
    v_new_employee_id,
    p_user_id,
    p_first_name,
    p_last_name,
    p_doc_number,
    p_phone,
    p_email,
    v_new_contract_id,
    p_schedule_id,
    p_tenant_id
  );

  RETURN v_new_employee_id;

EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'Data Error: Document Number (%) or Email already exists.', p_doc_number;
  WHEN foreign_key_violation THEN
    RAISE EXCEPTION 'Integrity Error: Insert failed, cause of the error a non existent FOREIGN KEY (user_id or schedule_id).';
  WHEN others THEN
    RAISE EXCEPTION 'Error creating employee or contract: %', SQLERRM;
END;
$$ LANGUAGE plpgsql; 

CREATE OR REPLACE FUNCTION update_gross_salary()
RETURNS TRIGGER AS $$
DECLARE
	v_detail_id UUID;
	v_new_gross_salary DECIMAL(10, 2);
BEGIN
	IF(TG_OP = 'DELETE') THEN 
		v_detail_id := OLD.detail_id;
	ELSE
		v_detail_id := NEW.detail_id;
	END IF;

	SELECT COALESCE(SUM(calculated_amount), 0)
	INTO v_new_gross_salary
	FROM hr_schema.income_register
	WHERE detail_id = v_detail_id;

	UPDATE hr_schema.paysheet_detail
	SET gross_salary = v_new_gross_salary,
  recalc_needed = TRUE
	WHERE detail_id = v_detail_id;

	RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- FIXME: relation "hr_schema.income_register" does not exist
-- DROP TRIGGER IF EXISTS update_gross_salary on hr_schema.income_register;
-- CREATE TRIGGER update_gross_salary
-- 	AFTER INSERT OR UPDATE OR DELETE ON hr_schema.income_register
-- 	FOR EACH ROW
-- 	EXECUTE FUNCTION update_gross_salary();

CREATE OR REPLACE FUNCTION hr_schema.update_paysheet_state (
    p_paysheet_id UUID
)
RETURNS VARCHAR AS $$
DECLARE
    v_pending_recalculations INTEGER;
    v_current_status_id INTEGER;
    v_completed_status_id INTEGER;
    v_completed_status_name VARCHAR(50) := 'Completed'; 
BEGIN
    -- Obtenemos el id del estado completado del catálogo
    SELECT status_id INTO v_completed_status_id
    FROM hr_schema.paysheet_status
    WHERE status_description = v_completed_status_name;

    IF v_completed_status_id IS NULL THEN
        RAISE EXCEPTION 'Error: Status with id % not found in db', v_completed_status_name;
    END IF;

    -- Obtenemos el id de estado actual de la nómina
    SELECT paysheet_status_id INTO v_current_status_id
    FROM hr_schema.paysheet
    WHERE paysheet_id = p_paysheet_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Error: Paysheet with id % not found.', p_paysheet_id;
    END IF;

    -- Chequeamos que ya fue completada
    IF v_current_status_id = v_completed_status_id THEN
        RETURN 'Paysheet already completed.';
    END IF;

    -- Revisamos si quedan calculos pendientes
    SELECT COUNT(*)
    INTO v_pending_recalculations
    FROM hr_schema.paysheet_detail
    WHERE paysheet_id = p_paysheet_id
      AND recalc_needed = TRUE;

    IF v_pending_recalculations > 0 THEN
        -- Si hay calculos pendientes, lanzamos una excepcion que termina el proceso
        RAISE EXCEPTION 'Integrity Error: Cant finish the paysheet process. % recalculations needed', v_pending_recalculations;
    END IF;

    --Si no hay pendientes, actualizamos el estado a 'Completed'
    UPDATE hr_schema.paysheet
    SET
        paysheet_status_id = v_completed_status_id
    WHERE paysheet_id = p_paysheet_id;

    RETURN 'Paysheet finished ' || p_paysheet_id;
END;
$$ LANGUAGE plpgsql;

-- Funcion para la generacion de reportes ccss mensuales de periodos especificos
CREATE OR REPLACE FUNCTION hr_schema.generate_monthly_ccss(
	p_year INTEGER,
	p_month INTEGER
)
RETURNS TABLE (
	total_employee NUMERIC(10, 2),
	total_tenant NUMERIC(10, 2),
	total NUMERIC(10, 2)
) AS $$
DECLARE
	v_status_completed_id INTEGER;
	v_completed_status VARCHAR(15) := 'Completed';
BEGIN
	SELECT status_id INTO v_status_completed_id
	FROM hr_schema.paysheet_status
	WHERE status_description = v_completed_status;

	IF v_status_completed_id IS NULL THEN
		RAISE EXCEPTION 'Status Completed not found in db.';
	END IF;

	RETURN QUERY
	SELECT
		COALESCE(SUM(pd.ccss_employee_deduction), 0) AS total_employee,
		COALESCE(SUM(pd.ccss_tenant_deduction), 0) AS total_tenant,
		COALESCE(SUM(pd.ccss_employee_deduction + ccss_tenant_deduction), 0) AS total
	FROM
		hr_schema.paysheet_detail pd
	INNER JOIN
		hr_schema.paysheet p ON pd.paysheet_id = p.paysheet_id
	WHERE
		EXTRACT(YEAR FROM p.payment_day) = p_year
		AND EXTRACT(MONTH FROM p.payment_day) = p_month
		AND p.paysheet_status_id = v_status_completed_id;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION hr_schema.validate_contract_dates()
RETURNS TRIGGER AS $$
BEGIN
	IF NEW.end_date IS NOT NULL AND NEW.end_date < NEW.start_date THEN
		RAISE EXCEPTION 'Integrity Error. The end of the contract must happen after it even starts.';
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS validate_contract_dates ON hr_schema.contract;
CREATE TRIGGER validate_contract_dates
BEFORE INSERT OR UPDATE ON hr_schema.contract
FOR EACH ROW
EXECUTE FUNCTION hr_schema.validate_contract_dates();

CREATE OR REPLACE FUNCTION hr_schema.protect_net_salary()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.net_salary IS DISTINCT FROM NEW.net_salary THEN
        PERFORM 1 FROM hr_schema.paysheet p
        	INNER JOIN hr_schema.paysheet_status ps ON p.paysheet_status_id = ps.status_id
        	WHERE p.paysheet_id = NEW.paysheet_id AND ps.status_description = 'Completed';
        
        IF FOUND THEN
             RAISE EXCEPTION 'Integrity Error: The Net Salary cannot be modified for a paysheet that is already COMPLETED.';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS protect_net_salary ON hr_schema.paysheet_detail;
CREATE TRIGGER protect_net_salary
BEFORE INSERT OR UPDATE ON hr_schema.paysheet_detail
FOR EACH ROW
EXECUTE FUNCTION hr_schema.protect_net_salary();



-- =============================================
-- SEED: REGIONS
-- Source: seeds/catalog/general/001-insert-regions.sql
-- =============================================
SET SEARCH_PATH TO general_schema;

INSERT INTO general_schema.region(region_name) VALUES
    ('Costa Rica'),
    ('Panama'),
    ('United States'),
    ('United Kingdom'),
    ('Japan')
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: DOCUMENT TYPES
-- Source: seeds/catalog/general/002-insert-document-types.sql
-- =============================================
SET SEARCH_PATH TO general_schema;

INSERT INTO general_schema.document_type(type_name, description) VALUES
    ('passport', 'International travel document'),
    ('driver_license', 'Official driving permit'),
    ('national_id', 'Government issued identification card')
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: CUSTOMER SEGMENTS
-- Source: seeds/catalog/general/003-insert-customer-segments.sql
-- =============================================
SET SEARCH_PATH TO general_schema;

INSERT INTO general_schema.customer_segment(segment_name, segment_hierarchy) VALUES
    ('vip', 1),
    ('loyal', 2),
    ('regular', 3),
    ('new', 4),
    ('inactive', 5)
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: CUSTOMER SEGMENT MARGIN TYPES
-- Source: seeds/catalog/general/004-insert-customer_segment_margin_types.sql
-- =============================================
SET SEARCH_PATH TO general_schema;

INSERT INTO general_schema.customer_segment_margin_type(type_name, description) VALUES
    ('spending_based', 'Discounts based on total spending'),
    ('seniority_based', 'Discounts based on customer seniority'),
    ('frequency_based', 'Discounts based on a monthly basis purchase frequency'),
    ('free_selection', 'Customers can select products for free up to a limit')
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: ROLES
-- Source: seeds/catalog/general/005-insert-roles.sql
-- =============================================
SET SEARCH_PATH TO general_schema;

INSERT INTO general_schema.role(role_name, role_hierarchy) VALUES
    ('superuser', 4),
    ('admin', 3),
    ('manager', 2),
    ('employee', 1)
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: CURRENCIES
-- Source: seeds/catalog/general/006-insert-currencies.sql
-- =============================================
SET SEARCH_PATH TO general_schema;

INSERT INTO general_schema.currency(currency_code, currency_name, symbol) VALUES
('CRC', 'Costa Rican Colón', '₡'),
('USD', 'US Dollar', '$'),
('EUR', 'Euro', '€'),
('GBP', 'British Pound', '£'),
('JPY', 'Japanese Yen', '¥')
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: TAX RATES
-- Source: seeds/catalog/general/007-insert-tax-rates.sql
-- =============================================
SET SEARCH_PATH TO general_schema;

INSERT INTO general_schema.tax_rate(region, region_id, rate_percentage) VALUES
('CR Standard', (select region_id from general_schema.region where region_name = 'Costa Rica'), 13.00),
('PA Standard', (select region_id from general_schema.region where region_name = 'Panama'), 7.00),
('US Federal', (select region_id from general_schema.region where region_name = 'United States'), 10.00),
('EU Standard', null, 20.00),
('UK Standard', (select region_id from general_schema.region where region_name = 'United Kingdom'), 20.00),
('JP Standard', (select region_id from general_schema.region where region_name = 'Japan'), 8.00)
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: SUBSCRIPTION TYPES
-- Source: seeds/catalog/general/008-insert-subscription-types.sql
-- =============================================
SET SEARCH_PATH TO general_schema;

INSERT INTO general_schema.subscription_type (subscription_type_name, subscription_type_detail, duration_months, subscription_type_cost) VALUES
('Basic', 'Basic subscription plan', 1, 9.99),
('Standard', 'Standard subscription plan', 6, 49.99),
('Premium', 'Premium subscription plan', 12, 89.99)
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: PAYMENT METHODS
-- Source: seeds/catalog/general/009-insert-payment_methods.sql
-- =============================================
SET SEARCH_PATH TO general_schema;

INSERT INTO general_schema.payment_method(name, description) VALUES
('cash', 'Payment made with cash'),
('debit_card', 'Payment made with debit card'),
('credit_card', 'Payment made with credit card'),
('loyalty_points', 'Payment made via loyalty points'),
('credit', 'Payment made through a credit account')
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: ACCOUNT PAYABLE STATUS
-- Source: seeds/catalog/general/010-insert-account-payable-status.sql
-- =============================================
SET SEARCH_PATH TO general_schema;

INSERT INTO general_schema.account_payable_status(status_name, description) VALUES
('Pending', 'Payment is pending'),
('Partial Paid', 'Partial payment has been made'),
('Paid', 'Payment has been made'),
('Overdue', 'Payment is overdue')
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: ACCOUNT PAYABLE TYPES
-- Source: seeds/catalog/general/011-insert-account-payable-types.sql
-- =============================================
SET SEARCH_PATH TO general_schema;

INSERT INTO general_schema.account_payable_type (type_name, description) VALUES
    ('goods_purchase', 'Purchases from suppliers for goods ordered'),
    ('utility_bill', 'Monthly utility bills such as electricity, water, internet'),
    ('rent_payment', 'Monthly rent payments for office or retail space'),
    ('tax_obligation', 'Taxes owed to government authorities'),
    ('loan_repayment', 'Repayments on business loans or lines of credit')
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: RETURN REASONS
-- Source: seeds/catalog/pos/001-insert-return-reason.sql
-- =============================================
SET SEARCH_PATH TO pos_schema;

INSERT INTO pos_schema.return_reason(reason_code, reason_name, description) VALUES
    ('DEFECT', 'Defecto de fábrica', 'El producto tiene un defecto de fabricación'),
    ('SIZE_CHANGE', 'Cambio de talla', 'El cliente requiere una talla diferente'),
    ('WRonG_PRODUCT', 'Producto equivocado', 'Se entregó un producto diferente al solicitado'),
    ('NOT_AS_DESCRIBED', 'No coincide con descripción', 'El producto no coincide con la descripción publicada'),
    ('DAMAGED', 'Producto dañado', 'El producto llegó dañado o roto'),
    ('EXPIRED', 'Producto vencido', 'El producto está vencido o caducado'),
    ('CUSTOMER_REGRET', 'Arrepentimiento', 'El cliente cambió de opinión'),
    ('OTHER', 'Otro motivo', 'Otro motivo no especificado')
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: RETURN STATUS
-- Source: seeds/catalog/pos/002-insert-return-status.sql
-- =============================================
SET SEARCH_PATH TO pos_schema;

INSERT INTO pos_schema.return_status(status_name) VALUES
    ('pending'),
    ('rejected'),
    ('processed')
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: PROMOTION TYPES
-- Source: seeds/catalog/pos/003-insert-promotion-types.sql
-- =============================================
SET SEARCH_PATH TO pos_schema;

INSERT INTO pos_schema.promotion_type(type_name) VALUES
    ('percentage_discount'),
    ('fixed_amount_discount'),
    ('buy_x_get_y'),
    ('volume_discount'),
    ('tiered_pricing'),
    ('combo'),
    ('free_shipping')
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: SCORE REDEMPTION STATUS
-- Source: seeds/catalog/pos/004-insert-score-redemption-status.sql
-- =============================================
SET SEARCH_PATH TO pos_schema;

INSERT INTO pos_schema.score_redemption_status(status_name) VALUES
    ('pending'),
    ('rejected'),
    ('processed')
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: SCORE TRANSACTION TYPES
-- Source: seeds/catalog/pos/005-insert-score-transaction-types.sql
-- =============================================
SET SEARCH_PATH TO pos_schema;

INSERT INTO pos_schema.score_transaction_type(type_name, description) VALUES
    ('earn', 'Points earned from purchases'),
    ('redeem', 'Points redeemed for rewards'),
    ('adjustment', 'Manual adjustment of points')
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: PURCHASE ORDER STATUS
-- Source: seeds/catalog/purchase/001-insert-purchase-order-status.sql
-- =============================================
SET SEARCH_PATH TO purchase_schema;

INSERT INTO purchase_schema.purchase_order_status(status_name, description) VALUES
('Pending', 'Order is pending'),
('Shipped', 'Order has been shipped'),
('Delivered', 'Order has been delivered'),
('Cancelled', 'Order has been cancelled')
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: PAYMENT ALERT TYPES
-- Source: seeds/catalog/purchase/002-insert-purchase-order-payment-alert-types.sql
-- =============================================
SET SEARCH_PATH TO purchase_schema;

INSERT INTO purchase_schema.purchase_order_payment_alert_type(payment_alert_type_name, description) VALUES
    ('Upcoming Due Date', 'Alert for upcoming payment due date'),
    ('Urgent Payment', 'Alert for urgent payments'),
    ('Overdue Payment', 'Alert for overdue payments'),
    ('Reconciliation Mismatch', 'Alert for payment reconciliation issues')
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: INVENTORY LOG TYPES
-- Source: seeds/catalog/inventory/001-insert-inventory_log_types.sql
-- =============================================
SET SEARCH_PATH TO inventory_schema;

INSERT INTO inventory_schema.inventory_log_type(inventory_log_type_name, inventory_log_type_description) VALUES
    ('IN', 'inventory added to inventory_schema'),
    ('OUT', 'inventory removed from inventory_schema')
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: PAYMENT SCHEDULES
-- Source: seeds/catalog/hr/001-insert-payment-schedules.sql
-- =============================================
SET SEARCH_PATH TO hr_schema;

INSERT INTO hr_schema.payment_schedule(description, daycount) VALUES
('Monthly', 30),
('Fortnight', 15),
('Weekly', 7),
('Daily', 1)
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: PAYSHEET STATUS
-- Source: seeds/catalog/hr/002-insert-paysheet-status.sql
-- =============================================
SET SEARCH_PATH TO hr_schema;

INSERT INTO hr_schema.paysheet_status(status_description) VALUES
('Pending'),
('Completed'),
('Canceled')
ON CONFLICT DO NOTHING;



-- -----------------
-- INTEGRITY CHECKS
-- -----------------
DO $$
DECLARE
    v_table_name TEXT;
    v_count INT;
    v_failed_tables TEXT[] := '{}';
BEGIN
    FOR v_table_name IN 
        SELECT unnest(ARRAY[
            'general_schema.region',
            'general_schema.role',
            'general_schema.document_type',
            'general_schema.currency',
            'general_schema.payment_method',
            'general_schema.subscription_type',
            'general_schema.customer_segment',
            'general_schema.customer_segment_margin_type',
            'general_schema.tax_rate',
            'general_schema.account_payable_status',
            'general_schema.account_payable_type',
            'pos_schema.return_reason',
            'pos_schema.return_status',
            'pos_schema.promotion_type',
            'pos_schema.score_redemption_status',
            'pos_schema.score_transaction_type',
            'inventory_schema.inventory_log_type',
            'purchase_schema.purchase_order_status',
            'purchase_schema.purchase_order_payment_alert_type',
            'hr_schema.payment_schedule',
            'hr_schema.paysheet_status'
        ])
    LOOP
        EXECUTE format('SELECT COUNT(*) FROM %s', v_table_name) INTO v_count;
        
        IF v_count = 0 THEN
            v_failed_tables := array_append(v_failed_tables, v_table_name);
        END IF;
    END LOOP;
    
    IF array_length(v_failed_tables, 1) > 0 THEN
        RAISE EXCEPTION 'The following tables are empty after seeding: %', 
            array_to_string(v_failed_tables, ', ');
    END IF;

    RAISE NOTICE 'Database bootstrap completed successfully!';
    RAISE NOTICE '   - All schemas created';
    RAISE NOTICE '   - All functions loaded';
    RAISE NOTICE '   - All catalog data seeded';
    RAISE NOTICE '   - Integrity checks passed';
END $$;

COMMIT;

-- ======================================================
-- END OF CONSOLIDATED BOOTSTRAP FILE
-- ======================================================
