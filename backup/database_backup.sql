-- ======================================================
-- CONSOLIDATED BOOTSTRAP FILE
-- Generated: 2026-05-22 03:37:15
-- ======================================================
-- This file can be executed from any SQL client
-- ======================================================

BEGIN;

DROP SCHEMA IF EXISTS general_schema CASCADE;
DROP SCHEMA IF EXISTS pos_schema CASCADE;
DROP SCHEMA IF EXISTS inventory_schema CASCADE;
DROP SCHEMA IF EXISTS purchase_schema CASCADE;
DROP SCHEMA IF EXISTS hr_schema CASCADE;
DROP SCHEMA IF EXISTS accounting_schema CASCADE;

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
    country_code VARCHAR(5),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_type
        WHERE typname = 'tax_regime'
          AND typnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'general_schema')
    ) THEN
        CREATE TYPE general_schema.tax_regime AS ENUM ('traditional', 'simplified');
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS tenant(
    tenant_id uuid PRIMARY KEY default gen_random_uuid(),
    tenant_name VARCHAR(100) unique not null,
    region_id INTEGER REFERENCES general_schema.region(region_id) on delete set null,
    identification VARCHAR(21) unique not null,
    identification_type_id INTEGER, -- FK added after identification_type table via ALTER TABLE below
    econ_activity VARCHAR(10),
    sign text,
    contact_email VARCHAR(100) not null,
    contact_phone VARCHAR(20),
    is_subscribed BOOLEAN default false,
    stripe_id VARCHAR(255) unique default null,
    tax_regime general_schema.tax_regime NOT NULL DEFAULT 'traditional',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON COLUMN general_schema.tenant.tax_regime IS
    'Tenant tax regime: traditional (régimen general IVA) or simplified (régimen simplificado, Decreto 38 MH).';

CREATE TABLE IF NOT EXISTS tenant_hacienda_config (
    tenant_hacienda_config_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL UNIQUE REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    hacienda_username TEXT NOT NULL,
    hacienda_password TEXT NOT NULL,
    hacienda_client_id VARCHAR(20) NOT NULL DEFAULT 'api-prod',
    p12_base64 TEXT NOT NULL,
    p12_password TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_tenant_hacienda_config_tenant
    ON general_schema.tenant_hacienda_config(tenant_id);  

CREATE TABLE IF NOT EXISTS branch(
    branch_id uuid PRIMARY KEY default gen_random_uuid(),
    tenant_id uuid not null REFERENCES general_schema.tenant(tenant_id) on delete cascade,
    branch_name VARCHAR(100) not null,
    branch_address text,
    branch_number VARCHAR(20),
    contact_email VARCHAR(100),
    is_main_branch BOOLEAN default false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS unique_main_branch_per_tenant
    on general_schema.branch (tenant_id)
    where is_main_branch = true;

-- Dirección estructurada del branch para facturación electrónica (DGT-R-48-2016)
CREATE TABLE IF NOT EXISTS branch_location (
    branch_location_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    branch_id UUID NOT NULL UNIQUE REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
    provincia  VARCHAR(1)  NOT NULL DEFAULT '1',   -- 1=San José … 7=Limón
    canton     VARCHAR(2)  NOT NULL DEFAULT '01',
    distrito   VARCHAR(2)  NOT NULL DEFAULT '01',
    otras_senas TEXT       NOT NULL DEFAULT '',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP          DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_branch_location_branch_id
    ON general_schema.branch_location(branch_id);

CREATE TABLE IF NOT EXISTS identification_type(
    identification_type_id SERIAL PRIMARY KEY,
    type_name VARCHAR(50) unique not null,
    description text,
    ident_code VARCHAR(3) not null, -- Campo requerido para la facturacion
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- FK from tenant to identification_type (deferred because tenant is defined first)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'tenant_identification_type_id_fkey'
          AND conrelid = 'general_schema.tenant'::regclass
    ) THEN
        ALTER TABLE general_schema.tenant
            ADD CONSTRAINT tenant_identification_type_id_fkey
            FOREIGN KEY (identification_type_id)
            REFERENCES general_schema.identification_type(identification_type_id)
            ON DELETE SET NULL;
    END IF;
END $$;

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
    identification_type_id INTEGER REFERENCES general_schema.identification_type(identification_type_id) on delete set null,
    document_number VARCHAR(50) not null,
    econ_activity VARCHAR(6),
    email VARCHAR(255),
    phone VARCHAR(50),
    birthdate date,
    address text,
    is_tenant BOOLEAN default false,
    is_wholesale BOOLEAN DEFAULT false,
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

CREATE TABLE IF NOT EXISTS exchange_rate (
    exchange_rate_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    from_currency_id INTEGER NOT NULL REFERENCES general_schema.currency(currency_id),
    to_currency_id   INTEGER NOT NULL REFERENCES general_schema.currency(currency_id),
    rate             NUMERIC(12,6) NOT NULL CHECK (rate > 0),
    effective_date   DATE NOT NULL,
    source           VARCHAR(50) DEFAULT 'MANUAL',
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(from_currency_id, to_currency_id, effective_date),
    CHECK (from_currency_id <> to_currency_id)
);

CREATE INDEX IF NOT EXISTS idx_exchange_rate_lookup
    ON general_schema.exchange_rate(from_currency_id, to_currency_id, effective_date DESC);

CREATE TABLE IF NOT EXISTS tax_rate(
    tax_rate_id SERIAL PRIMARY KEY,
    region VARCHAR(100),
    region_id INTEGER REFERENCES general_schema.region(region_id) on delete set null,
    rate_percentage numeric(5,2) not null check (rate_percentage >= 0 and rate_percentage <= 100),
    rate_code VARCHAR(10),
    rate_name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_tax_rate_region_percentage
    ON general_schema.tax_rate(region, rate_percentage);

COMMENT ON TABLE general_schema.tax_rate IS
    'Stores tax rate entries for both regional taxes and CABYS product-level IVA rates.
     - Regional rates: region + region_id populated.
     - CABYS IVA rates: rate_code + rate_name populated, region nullable.';



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

-- Códigos de un solo uso que el superusuario emite para que ciertas
-- personas se registren en el onboarding sin pagar Stripe. La
-- transacción de onboarding marca is_used = TRUE y deja el tenant_id
-- que consumió el código.
CREATE TABLE IF NOT EXISTS special_code (
    special_code_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(64) UNIQUE NOT NULL,
    description TEXT,
    created_by UUID REFERENCES general_schema.users(user_id) ON DELETE SET NULL,
    is_used BOOLEAN NOT NULL DEFAULT FALSE,
    tenant_id UUID REFERENCES general_schema.tenant(tenant_id) ON DELETE SET NULL,
    used_at TIMESTAMP,
    expires_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT special_code_used_consistency
        CHECK (
            (is_used = FALSE AND tenant_id IS NULL AND used_at IS NULL) OR
            (is_used = TRUE  AND tenant_id IS NOT NULL AND used_at IS NOT NULL)
        )
);

CREATE INDEX IF NOT EXISTS idx_special_code_is_used
    ON general_schema.special_code(is_used);
CREATE INDEX IF NOT EXISTS idx_special_code_tenant
    ON general_schema.special_code(tenant_id)
    WHERE tenant_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS product_category(
    product_category_id VARCHAR(13) PRIMARY KEY NOT NULL,
    category_name TEXT not null,
    parent_category_id VARCHAR(13)                                    
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
    product_name TEXT NOT NULL,
    product_name_tsv tsvector GENERATED ALWAYS AS (to_tsvector('spanish', product_name)) STORED,
    product_category_id VARCHAR(13) REFERENCES general_schema.product_category(product_category_id) ON DELETE SET NULL,
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
    cost_price NUMERIC(12,3) DEFAULT 0 CHECK (cost_price >= 0),
    weighted_avg_cost NUMERIC(12,3) DEFAULT 0 CHECK (weighted_avg_cost >= 0),
    last_purchase_date TIMESTAMP,
    is_active BOOLEAN DEFAULT true,
    is_composite BOOLEAN NOT NULL DEFAULT false,
    includes_iva BOOLEAN NOT NULL DEFAULT false,
    supplier_id UUID,
    giftable BOOLEAN DEFAULT FALSE,
    giftable_from NUMERIC(10,2) CHECK (giftable_from IS NULL OR giftable_from >= 0),
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
CREATE INDEX IF NOT EXISTS idx_product_variant_supplier
    ON general_schema.product_variant(supplier_id)
    WHERE supplier_id IS NOT NULL;

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

-- ============================================================================
-- PRODUCT VARIANT COMPOSITION (six-pack / batch / kit)
-- ============================================================================
CREATE TABLE IF NOT EXISTS product_variant_composition (
    tenant_id                  uuid    NOT NULL,
    parent_product_variant_id  uuid    NOT NULL,
    child_product_variant_id   uuid    NOT NULL,
    quantity                   numeric(12,3) NOT NULL CHECK (quantity > 0),
    created_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (tenant_id, parent_product_variant_id, child_product_variant_id),
    CHECK (parent_product_variant_id <> child_product_variant_id),
    FOREIGN KEY (tenant_id, parent_product_variant_id)
        REFERENCES general_schema.product_variant(tenant_id, product_variant_id)
        ON DELETE CASCADE,
    FOREIGN KEY (tenant_id, child_product_variant_id)
        REFERENCES general_schema.product_variant(tenant_id, product_variant_id)
        ON DELETE RESTRICT
) PARTITION BY HASH (tenant_id);

DO $$ DECLARE i INT; BEGIN
  FOR i IN 0..7 LOOP
    EXECUTE format(
      'CREATE TABLE IF NOT EXISTS general_schema.product_variant_composition_p%s
       PARTITION OF general_schema.product_variant_composition
       FOR VALUES WITH (MODULUS 8, REMAINDER %s);', i, i);
  END LOOP;
END $$ LANGUAGE plpgsql;

CREATE INDEX IF NOT EXISTS idx_pvc_parent
    ON general_schema.product_variant_composition (tenant_id, parent_product_variant_id);
CREATE INDEX IF NOT EXISTS idx_pvc_child
    ON general_schema.product_variant_composition (tenant_id, child_product_variant_id);

COMMENT ON TABLE general_schema.product_variant_composition IS
    'Composite product variants: parent explodes into N children with a quantity ratio.';

-- ── Composite delete cascade trigger ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION general_schema.cascade_delete_composite_children()
RETURNS TRIGGER AS $$
DECLARE
    v_child_id UUID;
BEGIN
    IF OLD.is_composite THEN
        FOR v_child_id IN
            SELECT child_product_variant_id
            FROM general_schema.product_variant_composition
            WHERE tenant_id = OLD.tenant_id
              AND parent_product_variant_id = OLD.product_variant_id
        LOOP
            -- Remove ALL composition rows where this variant appears as a child
            -- (from any parent). Required to satisfy ON DELETE RESTRICT before
            -- deleting the variant row itself.
            DELETE FROM general_schema.product_variant_composition
            WHERE tenant_id = OLD.tenant_id
              AND child_product_variant_id = v_child_id;

            -- Delete the child variant. If the child is_composite, this DELETE
            -- fires the trigger recursively, cascading to its own children.
            DELETE FROM general_schema.product_variant
            WHERE tenant_id = OLD.tenant_id
              AND product_variant_id = v_child_id;
        END LOOP;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER trg_cascade_delete_composite_children
    BEFORE DELETE ON general_schema.product_variant
    FOR EACH ROW EXECUTE FUNCTION general_schema.cascade_delete_composite_children();

-- ============================================================================
-- TENANT PRODUCT GROUPING (departments, families, brands, etc.)
-- ============================================================================
CREATE TABLE IF NOT EXISTS tenant_product_group_type (
    tenant_product_group_type_id  uuid    NOT NULL DEFAULT gen_random_uuid(),
    tenant_id                     uuid    NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    type_name                     VARCHAR(80) NOT NULL,
    description                   TEXT,
    is_active                     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at                    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at                    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (tenant_id, tenant_product_group_type_id),
    UNIQUE (tenant_id, type_name)
);

CREATE INDEX IF NOT EXISTS idx_tpgt_tenant
    ON general_schema.tenant_product_group_type(tenant_id);

COMMENT ON TABLE general_schema.tenant_product_group_type IS
    'Classification dimensions per tenant (e.g., Department, Family, Brand).';

CREATE TABLE IF NOT EXISTS tenant_product_group (
    tenant_product_group_id       uuid    NOT NULL DEFAULT gen_random_uuid(),
    tenant_id                     uuid    NOT NULL,
    tenant_product_group_type_id  uuid    NOT NULL,
    parent_group_id               uuid,
    group_name                    VARCHAR(120) NOT NULL,
    hierarchy_level               INTEGER NOT NULL DEFAULT 0 CHECK (hierarchy_level >= 0),
    is_active                     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at                    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at                    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (tenant_id, tenant_product_group_id),
    FOREIGN KEY (tenant_id, tenant_product_group_type_id)
        REFERENCES general_schema.tenant_product_group_type(tenant_id, tenant_product_group_type_id) ON DELETE CASCADE,
    FOREIGN KEY (tenant_id, parent_group_id)
        REFERENCES general_schema.tenant_product_group(tenant_id, tenant_product_group_id) ON DELETE CASCADE,
    CHECK (parent_group_id IS NULL OR parent_group_id <> tenant_product_group_id),
    UNIQUE (tenant_id, tenant_product_group_type_id, parent_group_id, group_name)
);

CREATE INDEX IF NOT EXISTS idx_tpg_parent
    ON general_schema.tenant_product_group(tenant_id, parent_group_id) WHERE parent_group_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tpg_type
    ON general_schema.tenant_product_group(tenant_id, tenant_product_group_type_id);

COMMENT ON TABLE general_schema.tenant_product_group IS
    'Hierarchical group nodes within a classification dimension.';

CREATE TABLE IF NOT EXISTS product_variant_group_assignment (
    tenant_id                  uuid NOT NULL,
    product_variant_id         uuid NOT NULL,
    tenant_product_group_id    uuid NOT NULL,
    created_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (tenant_id, product_variant_id, tenant_product_group_id),
    FOREIGN KEY (tenant_id, product_variant_id)
        REFERENCES general_schema.product_variant(tenant_id, product_variant_id) ON DELETE CASCADE,
    FOREIGN KEY (tenant_id, tenant_product_group_id)
        REFERENCES general_schema.tenant_product_group(tenant_id, tenant_product_group_id) ON DELETE CASCADE
) PARTITION BY HASH (tenant_id);

DO $$ DECLARE i INT; BEGIN
  FOR i IN 0..7 LOOP
    EXECUTE format(
      'CREATE TABLE IF NOT EXISTS general_schema.product_variant_group_assignment_p%s
       PARTITION OF general_schema.product_variant_group_assignment
       FOR VALUES WITH (MODULUS 8, REMAINDER %s);', i, i);
  END LOOP;
END $$ LANGUAGE plpgsql;

CREATE INDEX IF NOT EXISTS idx_pvga_group
    ON general_schema.product_variant_group_assignment(tenant_id, tenant_product_group_id);

COMMENT ON TABLE general_schema.product_variant_group_assignment IS
    'M2M between product variants and tenant groups (variants can belong across dimensions).';

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


CREATE TABLE IF NOT EXISTS general_schema.exoneration_type (
    code VARCHAR(2) PRIMARY KEY,
    description VARCHAR(100) NOT NULL
);

CREATE TABLE IF NOT EXISTS general_schema.exoneration_institution (
    code VARCHAR(2) PRIMARY KEY,
    name VARCHAR(100) NOT NULL
);


CREATE TABLE IF NOT EXISTS general_schema.tax_exoneration (
    exoneration_id SERIAL PRIMARY KEY,
    
    exoneration_type_code VARCHAR(2) NOT NULL REFERENCES general_schema.exoneration_type(code),
    other_document_type VARCHAR(100) NULL,
    document_number VARCHAR(40) NOT NULL,
    
    article INTEGER NULL,
    clause INTEGER NULL,
    
    institution_code VARCHAR(2) NOT NULL REFERENCES general_schema.exoneration_institution(code),
    other_institution_name VARCHAR(160) NULL,
    
    issue_date TIMESTAMP NOT NULL,
    exonerated_rate NUMERIC(4,2) NOT NULL,
    exoneration_amount NUMERIC(18,5) NOT NULL
);

CREATE TABLE IF NOT EXISTS product_cost_history (
    cost_history_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id          UUID NOT NULL,
    product_variant_id UUID NOT NULL,
    purchase_order_id  UUID,
    unit_cost          NUMERIC(12,3) NOT NULL CHECK (unit_cost >= 0),
    currency_id        INTEGER REFERENCES general_schema.currency(currency_id),
    exchange_rate      NUMERIC(12,6),
    unit_cost_converted NUMERIC(12,3),
    quantity           INTEGER NOT NULL CHECK (quantity > 0),
    effective_date     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (tenant_id, product_variant_id)
        REFERENCES general_schema.product_variant(tenant_id, product_variant_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_product_cost_history_variant
    ON general_schema.product_cost_history(tenant_id, product_variant_id, effective_date DESC);

CREATE TABLE IF NOT EXISTS general_schema.account_receivable_status (
    status_id   SERIAL PRIMARY KEY,
    status_name VARCHAR(50) NOT NULL,
    description TEXT,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS general_schema.account_receivable_type (
    account_receivable_type_id SERIAL PRIMARY KEY,
    type_name                  VARCHAR(50) UNIQUE NOT NULL,
    description                TEXT,
    created_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS general_schema.account_receivable (
    account_receivable_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_receivable_type_id INT REFERENCES general_schema.account_receivable_type(account_receivable_type_id) ON DELETE SET NULL,
    account_status             INTEGER NOT NULL DEFAULT 1 REFERENCES general_schema.account_receivable_status(status_id),
    tenant_id                  UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    tenant_customer_id         UUID REFERENCES general_schema.tenant_customer(tenant_customer_id) ON DELETE SET NULL,
    has_invoice                BOOLEAN DEFAULT TRUE,
    has_tax                    BOOLEAN DEFAULT FALSE,
    subtotal                   NUMERIC(12,3) NOT NULL CHECK (subtotal >= 0),
    amount_paid                NUMERIC(12,3) DEFAULT 0 CHECK (amount_paid >= 0),
    balance_remaining          NUMERIC(12,3) GENERATED ALWAYS AS (subtotal - amount_paid) STORED,
    is_paid                    BOOLEAN DEFAULT FALSE,
    due_date                   DATE NOT NULL,
    created_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_account_receivable_tenant
    ON general_schema.account_receivable(tenant_id);

CREATE INDEX IF NOT EXISTS idx_account_receivable_status
    ON general_schema.account_receivable(tenant_id, account_status);

CREATE INDEX IF NOT EXISTS idx_account_receivable_due_date
    ON general_schema.account_receivable(tenant_id, due_date);

CREATE INDEX IF NOT EXISTS idx_account_receivable_customer
    ON general_schema.account_receivable(tenant_customer_id)
    WHERE tenant_customer_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_product_cost_history_purchase
    ON general_schema.product_cost_history(purchase_order_id);



-- =============================================
-- SCHEMA: POS
-- Source: schemas/pos/pos_schema.sql
-- =============================================
CREATE SCHEMA IF NOT EXISTS pos_schema;
SET SEARCH_PATH TO pos_schema;

CREATE TABLE IF NOT EXISTS sale_condition (
    condition_code VARCHAR(3) PRIMARY KEY,
    condition_desc TEXT
);

CREATE TABLE IF NOT EXISTS sale(
    sale_id uuid PRIMARY KEY default gen_random_uuid(),
    branch_id uuid not null REFERENCES general_schema.branch(branch_id) on delete cascade,
    tenant_customer_id uuid REFERENCES general_schema.tenant_customer(tenant_customer_id),
    sale_condition VARCHAR(3) not null REFERENCES pos_schema.sale_condition(condition_code),
    sale_date timestamp not null default current_timestamp,
    currency_id INTEGER REFERENCES general_schema.currency(currency_id) on delete set null,
    subtotal_amount numeric(10,2) not null default 0 check (subtotal_amount >= 0),
    tax_amount numeric(10,2) not null default 0 check (tax_amount >= 0),
    total_amount numeric(10,2) not null,
    is_completed BOOLEAN default false,
    has_electronic_invoice BOOLEAN DEFAULT FALSE,
    is_refunded BOOLEAN NOT NULL DEFAULT false,
    seller_user_id uuid REFERENCES general_schema.users(user_id) ON DELETE SET NULL,
    created_at timestamp not null default current_timestamp,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_sale_branch_id on pos_schema.sale(branch_id);
CREATE INDEX IF NOT EXISTS idx_sale_sale_date on pos_schema.sale(sale_date);
CREATE INDEX IF NOT EXISTS idx_sale_is_refunded on pos_schema.sale(branch_id, is_refunded);

CREATE TABLE IF NOT EXISTS sale_item(
    sale_item_id uuid PRIMARY KEY default gen_random_uuid(),
    sale_id uuid not null REFERENCES pos_schema.sale(sale_id) on delete cascade,
    tenant_id uuid not null,
    product_variant_id uuid,
    quantity INTEGER not null check (quantity > 0),
    unit_price numeric(10,2) not null check (unit_price >= 0),
    total_price numeric(10,2) not null,
    cost_price_at_sale NUMERIC(12,3),
    sale_price_type VARCHAR(20) DEFAULT 'NORMAL' CHECK (sale_price_type IN ('NORMAL', 'PROMO', 'SEGMENT', 'MANUAL', 'ROYALTY')),
    promotion_id uuid, -- FK to pos_schema.promotion added via ALTER TABLE below (forward reference)
    royalty_option_id uuid, -- FK to pos_schema.royalty_option added via ALTER TABLE below (forward reference)
    royalty_rule_id uuid, -- FK to pos_schema.royalty_rule added via ALTER TABLE below (forward reference)
    original_price NUMERIC(10,2),
    discount_applied NUMERIC(10,2) DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT sale_item_product_variant_fkey
    FOREIGN KEY (tenant_id, product_variant_id)
        REFERENCES general_schema.product_variant(tenant_id, product_variant_id)
        ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_sale_item_product_variant
    ON pos_schema.sale_item(tenant_id, product_variant_id);
CREATE INDEX IF NOT EXISTS idx_sale_item_sale_id
    ON pos_schema.sale_item(sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_item_sale_variant
    ON pos_schema.sale_item(sale_id, product_variant_id);
CREATE INDEX IF NOT EXISTS idx_sale_item_royalty_option
    ON pos_schema.sale_item(royalty_option_id)
    WHERE royalty_option_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sale_item_royalty_rule
    ON pos_schema.sale_item(royalty_rule_id)
    WHERE royalty_rule_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS cash_register(
    cash_register_id uuid PRIMARY KEY default gen_random_uuid(),
    branch_id uuid not null REFERENCES general_schema.branch(branch_id) on delete cascade,
    register_name VARCHAR(100),
    is_active BOOLEAN default true,
    cash_register_key VARCHAR(64),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON COLUMN pos_schema.cash_register.cash_register_key IS
    'Optional plain-text key required for non-admin users to open/close a session. NULL = no key required.';

CREATE TABLE IF NOT EXISTS cash_register_session(
    cash_register_session_id uuid PRIMARY KEY default gen_random_uuid(),
    cash_register_id uuid not null REFERENCES pos_schema.cash_register(cash_register_id) on delete cascade,
    user_id uuid not null REFERENCES general_schema.users(user_id) on delete set null,
    opened_at timestamp not null default current_timestamp,
    closed_at timestamp,
    opening_amount numeric(10,2) not null check (opening_amount >= 0),
    closing_amount numeric(10,2) check (closing_amount >= 0),
    is_active BOOLEAN default true,
    cash_sales_amount     NUMERIC(14, 2),
    debit_sales_amount    NUMERIC(14, 2),
    credit_sales_amount   NUMERIC(14, 2),
    transfer_sales_amount NUMERIC(14, 2),
    points_sales_amount   NUMERIC(14, 2),
    total_sales_amount    NUMERIC(14, 2),
    user_cash_amount      NUMERIC(14, 2),
    user_debit_amount     NUMERIC(14, 2),
    user_credit_amount    NUMERIC(14, 2),
    user_transfer_amount  NUMERIC(14, 2),
    mismatch              BOOLEAN DEFAULT FALSE,
    mismatch_amount       NUMERIC(14, 2),
    mismatch_type         VARCHAR(10) CHECK (mismatch_type IN ('surplus', 'shortage')),
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
    -- nullable: walk-in/anonymous sales pay without a registered customer
    tenant_customer_id uuid REFERENCES general_schema.tenant_customer(tenant_customer_id) on delete cascade,
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
        (is_points_redemption = true and points_redeemed is not null and points_redeemed > 0 and payment_method_id = 5) or
        (is_points_redemption = false)
    )
);

CREATE TABLE IF NOT EXISTS digital_sale_invoice(
    digital_sale_invoice_id uuid PRIMARY KEY default gen_random_uuid(),
    tenant_customer_id uuid REFERENCES general_schema.tenant_customer(tenant_customer_id) on delete set null,
    sale_id uuid not null REFERENCES pos_schema.sale(sale_id) on delete cascade,
    currency_id INTEGER REFERENCES general_schema.currency(currency_id) on delete set null,
    subtotal_amount numeric(10,2) not null check (subtotal_amount >= 0),
    tax_amount numeric(10,2) not null check (tax_amount >= 0),
    total_amount numeric(10,2) not null,
    due_date DATE DEFAULT CURRENT_DATE,
    cash_register_session_id UUID REFERENCES pos_schema.cash_register_session(cash_register_session_id) ON DELETE SET NULL,
    points_accumulated INTEGER DEFAULT 0,
    ad_message TEXT,
    amount_paid NUMERIC(10,2) DEFAULT 0,
    change_amount NUMERIC(10,2) DEFAULT 0,
    invoiced_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_digital_sale_invoice_sale_id on pos_schema.digital_sale_invoice(sale_id);
CREATE INDEX IF NOT EXISTS idx_digital_sale_invoice_cash_register_session
    ON pos_schema.digital_sale_invoice(cash_register_session_id);

CREATE TABLE IF NOT EXISTS digital_sale_invoice_item(
    digital_sale_invoice_item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    digital_sale_invoice_id UUID NOT NULL
        REFERENCES pos_schema.digital_sale_invoice(digital_sale_invoice_id) ON DELETE CASCADE,
    sale_item_id UUID NOT NULL
        REFERENCES pos_schema.sale_item(sale_item_id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL,
    product_variant_id UUID,
    cabys_code VARCHAR(13)
        REFERENCES general_schema.product(cabys_code) ON DELETE SET NULL,
    tax_rate_id INTEGER
        REFERENCES general_schema.tax_rate(tax_rate_id) ON DELETE SET NULL,
    description VARCHAR(255),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    subtotal NUMERIC(10,2) NOT NULL,
    tax_rate_percentage NUMERIC(5,2) NOT NULL DEFAULT 0,
    tax_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
    total_price NUMERIC(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT digital_sale_invoice_item_product_variant_fkey
    FOREIGN KEY (tenant_id, product_variant_id)
        REFERENCES general_schema.product_variant(tenant_id, product_variant_id)
        ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_digital_invoice_item_invoice
    ON pos_schema.digital_sale_invoice_item(digital_sale_invoice_id);
CREATE INDEX IF NOT EXISTS idx_digital_invoice_item_sale_item
    ON pos_schema.digital_sale_invoice_item(sale_item_id);
CREATE INDEX IF NOT EXISTS idx_digital_invoice_item_variant
    ON pos_schema.digital_sale_invoice_item(tenant_id, product_variant_id);
CREATE INDEX IF NOT EXISTS idx_digital_invoice_item_tax_rate
    ON pos_schema.digital_sale_invoice_item(tax_rate_id);

CREATE TABLE IF NOT EXISTS digital_sale_invoice_payment(
    digital_sale_invoice_payment_id uuid PRIMARY KEY default gen_random_uuid(),
    digital_sale_invoice_id uuid not null REFERENCES pos_schema.digital_sale_invoice(digital_sale_invoice_id) on delete cascade,
    customer_payment_id uuid not null REFERENCES pos_schema.customer_payment(customer_payment_id) on delete cascade,
    payment_amount numeric(10,2) not null check (payment_amount > 0),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    unique (digital_sale_invoice_id, customer_payment_id)
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
    digital_sale_invoice_id uuid REFERENCES pos_schema.digital_sale_invoice(digital_sale_invoice_id) on delete cascade,
    electronic_sale_invoice_id uuid, -- FK to pos_schema.electronic_sale_invoice added via ALTER TABLE below (forward reference)
    tenant_customer_id uuid REFERENCES general_schema.tenant_customer(tenant_customer_id) on delete set null,
    total_refund_amount numeric(10,2) not null check (total_refund_amount >= 0),
    refund_method int REFERENCES general_schema.payment_method(payment_method_id) on delete set null,
    return_status_id INTEGER REFERENCES pos_schema.return_status(return_status_id) on delete set null,
    description TEXT NOT NULL,
    return_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_return_transaction_invoice CHECK (
        digital_sale_invoice_id IS NOT NULL OR electronic_sale_invoice_id IS NOT NULL
    )
);
CREATE INDEX IF NOT EXISTS idx_return_transaction_digital_sale_invoice_id on pos_schema.return_transaction(digital_sale_invoice_id);
CREATE INDEX IF NOT EXISTS idx_return_transaction_electronic_sale_invoice_id on pos_schema.return_transaction(electronic_sale_invoice_id);
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
    is_universal BOOLEAN NOT NULL DEFAULT TRUE,
    promotion_start_date date not null,
    promotion_end_date date not null,
    is_active BOOLEAN default false,
    is_default BOOLEAN NOT NULL DEFAULT false,
    is_stackable BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    check (promotion_end_date > promotion_start_date)
);

-- Junction table: specific segment targeting when is_universal = false
CREATE TABLE IF NOT EXISTS promotion_customer_segment (
    promotion_id        uuid    NOT NULL REFERENCES pos_schema.promotion(promotion_id) ON DELETE CASCADE,
    customer_segment_id INTEGER NOT NULL REFERENCES general_schema.customer_segment(customer_segment_id) ON DELETE CASCADE,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (promotion_id, customer_segment_id)
);

CREATE INDEX IF NOT EXISTS idx_promo_seg_promo
    ON pos_schema.promotion_customer_segment(promotion_id);
CREATE INDEX IF NOT EXISTS idx_promo_seg_segment
    ON pos_schema.promotion_customer_segment(customer_segment_id);

CREATE INDEX IF NOT EXISTS idx_promotion_active_default
    ON pos_schema.promotion(tenant_id, is_active, is_default)
    WHERE is_active = TRUE AND is_default = TRUE;

-- FK deferred: sale_item.promotion_id -> promotion (promotion defined after sale_item)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'sale_item_promotion_id_fkey'
          AND conrelid = 'pos_schema.sale_item'::regclass
    ) THEN
        ALTER TABLE pos_schema.sale_item
            ADD CONSTRAINT sale_item_promotion_id_fkey
            FOREIGN KEY (promotion_id)
            REFERENCES pos_schema.promotion(promotion_id)
            ON DELETE SET NULL;
    END IF;
END $$;

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

CREATE TYPE pos_schema.discount_result AS (
    discount_amount numeric(10,2),
    discount_percentage numeric(5,2),
    rule_description text,
    success BOOLEAN
);

-- ============================================================================
-- PROMOTION TARGETING (variants or tenant groups)
-- ============================================================================
CREATE TABLE IF NOT EXISTS promotion_target (
    promotion_target_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    promotion_id               uuid NOT NULL REFERENCES pos_schema.promotion(promotion_id) ON DELETE CASCADE,
    tenant_id                  uuid NOT NULL,
    target_type                VARCHAR(20) NOT NULL CHECK (target_type IN ('VARIANT','GROUP')),
    target_product_variant_id  uuid,
    target_group_id            uuid,
    created_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CHECK (
      (target_type = 'VARIANT' AND target_product_variant_id IS NOT NULL AND target_group_id IS NULL) OR
      (target_type = 'GROUP'   AND target_group_id IS NOT NULL AND target_product_variant_id IS NULL)
    ),
    FOREIGN KEY (tenant_id, target_product_variant_id)
        REFERENCES general_schema.product_variant(tenant_id, product_variant_id) ON DELETE CASCADE,
    FOREIGN KEY (tenant_id, target_group_id)
        REFERENCES general_schema.tenant_product_group(tenant_id, tenant_product_group_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_promo_target_promo
    ON pos_schema.promotion_target(promotion_id);
CREATE INDEX IF NOT EXISTS idx_promo_target_variant
    ON pos_schema.promotion_target(tenant_id, target_product_variant_id) WHERE target_product_variant_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_promo_target_group
    ON pos_schema.promotion_target(tenant_id, target_group_id) WHERE target_group_id IS NOT NULL;

COMMENT ON TABLE pos_schema.promotion_target IS
    'Targets a promotion to either a specific variant or a tenant group. Mutually exclusive via CHECK constraint.';

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
    digital_sale_invoice_id uuid REFERENCES pos_schema.digital_sale_invoice(digital_sale_invoice_id) on delete set null,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS debtor (
    debtor_id uuid PRIMARY KEY default gen_random_uuid(),
    tenant_id uuid not null REFERENCES general_schema.tenant(tenant_id) on delete cascade,
    debt numeric(10, 2) not null default 0.00, -- ? Add check (debt >= 0) 
    missed_payments INTEGER not null default 0
);

CREATE TABLE IF NOT EXISTS invoice_status (
    status_id INTEGER PRIMARY KEY,
    description VARCHAR(50) NOT NULL
);

CREATE TABLE IF NOT EXISTS electronic_sale_invoice (
    electronic_sale_invoice_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_id UUID NOT NULL REFERENCES pos_schema.sale(sale_id) ON DELETE CASCADE,
    status_id INTEGER REFERENCES pos_schema.invoice_status(status_id),
    key_number VARCHAR(50) NOT NULL UNIQUE,
    consecutive_number VARCHAR(20) NOT NULL,
    -- Issuer information (required)
    -- issue_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- issuer_name VARCHAR(150) NOT NULL,
    -- issuer_identification VARCHAR(20) NOT NULL,
    -- issuer_identification_type VARCHAR(2) NOT NULL,  -- 01=Individual, 02=Legal Entity, 03=DIMEX, 04=NITE
    -- issuer_email VARCHAR(200),
    -- issuer_phone VARCHAR(20),
    -- Receiver information (optional for consumer final)
    -- receiver_name VARCHAR(150),
    -- receiver_identification VARCHAR(20),
    -- receiver_identification_type VARCHAR(2),
    -- receiver_email VARCHAR(200),
    -- sale details
    payment_method VARCHAR(2) NOT NULL DEFAULT '01',  -- 01=Cash, 02=Card, 03=Check, 04=Transfer
    credit_days VARCHAR(10),
    -- Tax breakdown (required)
    -- total_taxed_services NUMERIC(18,5) DEFAULT 0,
    -- total_exempt_services NUMERIC(18,5) DEFAULT 0,
    -- total_exonerated_services NUMERIC(18,5) DEFAULT 0,
    -- total_taxed_goods NUMERIC(18,5) DEFAULT 0,
    -- total_exempt_goods NUMERIC(18,5) DEFAULT 0,
    -- total_exonerated_goods NUMERIC(18,5) DEFAULT 0,
    -- total_taxable NUMERIC(18,5) DEFAULT 0,
    -- total_exempt NUMERIC(18,5) DEFAULT 0,
    -- total_exonerated NUMERIC(18,5) DEFAULT 0,
    -- total_sale NUMERIC(18,5) NOT NULL DEFAULT 0,
    -- total_discounts NUMERIC(18,5) DEFAULT 0,
    -- total_net_sale NUMERIC(18,5) NOT NULL DEFAULT 0,
    -- total_tax NUMERIC(18,5) DEFAULT 0,
    -- total_voucher NUMERIC(18,5) NOT NULL DEFAULT 0,
    -- XML digital signature
    xml_signed TEXT,
    -- Hacienda response
    hacienda_response_xml TEXT,
    hacienda_response_date TIMESTAMP,
    -- Async status polling (cron-based reconciliation, migration 011 + 032)
    check_attempts INT NOT NULL DEFAULT 0,
    next_check_at TIMESTAMP,
    -- Metadata
    -- currency_id INTEGER REFERENCES general_schema.currency(currency_id) ON DELETE SET NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_electronic_sale_invoice_sale_id
    ON pos_schema.electronic_sale_invoice(sale_id);
CREATE INDEX IF NOT EXISTS idx_electronic_sale_invoice_key_number
    ON pos_schema.electronic_sale_invoice(key_number);
-- #2: columna issue_date no existe en esta versión del schema; se indexa created_at
CREATE INDEX IF NOT EXISTS idx_electronic_sale_invoice_created_at
    ON pos_schema.electronic_sale_invoice(created_at);
-- Cron picks pending invoices due for re-check; partial index keeps it tiny.
CREATE INDEX IF NOT EXISTS idx_electronic_invoice_pending_check
    ON pos_schema.electronic_sale_invoice(next_check_at)
    WHERE status_id = 1;

-- FK deferred: return_transaction.electronic_sale_invoice_id -> electronic_sale_invoice
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'return_transaction_electronic_sale_invoice_id_fkey'
          AND conrelid = 'pos_schema.return_transaction'::regclass
    ) THEN
        ALTER TABLE pos_schema.return_transaction
            ADD CONSTRAINT return_transaction_electronic_sale_invoice_id_fkey
            FOREIGN KEY (electronic_sale_invoice_id)
            REFERENCES pos_schema.electronic_sale_invoice(electronic_sale_invoice_id)
            ON DELETE CASCADE;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS electronic_sale_invoice_items (
    electronic_sale_invoice_item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    electronic_sale_invoice_id UUID NOT NULL REFERENCES pos_schema.electronic_sale_invoice(electronic_sale_invoice_id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL,
    product_variant_id UUID,
    sale_item_id uuid NOT NULL REFERENCES pos_schema.sale_item(sale_item_id) ON DELETE CASCADE,
    line_number INTEGER NOT NULL,
    -- cabys_code VARCHAR(13) NOT NULL REFERENCES general_schema.product(cabys_code) ON DELETE RESTRICT,
    -- description VARCHAR(200) NOT NULL,  -- Product description
    -- Quantity and units
    -- quantity NUMERIC(16,3) NOT NULL,
    -- unit_of_measure VARCHAR(20) NOT NULL DEFAULT 'Unid',
    -- commercial_unit_of_measure VARCHAR(20),
    -- Pricing
    -- unit_price NUMERIC(18,5) NOT NULL,
    -- total_amount NUMERIC(18,5) NOT NULL,
    -- Discounts (optional)
    discount_amount NUMERIC(18,5) DEFAULT 0,
    discount_nature VARCHAR(80),
    -- Subtotal
    -- subtotal NUMERIC(18,5) NOT NULL,
    -- Tax (IVA)
    tax_rate_id INTEGER REFERENCES general_schema.tax_rate(tax_rate_id),
    tax_exoneration_id INTEGER REFERENCES general_schema.tax_exoneration(exoneration_id),
    -- tax_code VARCHAR(2) DEFAULT '01',     -- 01 = IVA
    -- tax_rate_code VARCHAR(2) DEFAULT '08', -- 08 = Standard rate 13%
    -- tax_rate NUMERIC(5,2) DEFAULT 13.00,
    -- tax_amount NUMERIC(18,5) DEFAULT 0,
    -- tax_exemption_amount NUMERIC(18,5) DEFAULT 0,
    -- Exemption (optional)
    -- exemption_document_type VARCHAR(2),
    -- exemption_document_number VARCHAR(40),
    -- exemption_institution VARCHAR(160),
    -- exemption_date TIMESTAMP,
    -- exemption_percentage NUMERIC(3,0),
    -- Line total
    -- total_line_amount NUMERIC(18,5) NOT NULL,

    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_electronic_item_product_variant
    FOREIGN KEY (tenant_id, product_variant_id)
        REFERENCES general_schema.product_variant(tenant_id, product_variant_id)
        ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_electronic_invoice_items_invoice
    ON pos_schema.electronic_sale_invoice_items(electronic_sale_invoice_id);
CREATE INDEX IF NOT EXISTS idx_electronic_invoice_items_variant
    ON pos_schema.electronic_sale_invoice_items(tenant_id, product_variant_id);

-- ── Royalties ─────────────────────────────────────────────────────────────────
-- A royalty_rule defines a minimum purchase amount. It is not bound to a
-- single dimension: any of its options may target any tenant_product_group
-- across dimensions. Selecting a group implicitly includes its descendants
-- in the tenant_product_group hierarchy at query time (resolved via
-- recursive CTE in the application layer).
--
-- A variant becomes eligible as a gift when product_variant.giftable = true
-- AND the variant is assigned (directly or transitively) to a group selected
-- by the option. There is no specific-product targeting table.

CREATE TABLE IF NOT EXISTS pos_schema.royalty_rule (
    royalty_rule_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    min_amount       NUMERIC(14,2) NOT NULL CHECK (min_amount > 0),
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_royalty_rule_tenant
    ON pos_schema.royalty_rule(tenant_id, min_amount ASC);

-- Explicit dimensions the rule applies to. Without this row in
-- royalty_rule_dimension, the dimension is excluded from the rule
-- regardless of any leftover options.
CREATE TABLE IF NOT EXISTS pos_schema.royalty_rule_dimension (
    royalty_rule_id              UUID NOT NULL
        REFERENCES pos_schema.royalty_rule(royalty_rule_id) ON DELETE CASCADE,
    tenant_id                    UUID NOT NULL,
    tenant_product_group_type_id UUID NOT NULL,
    created_at                   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (royalty_rule_id, tenant_product_group_type_id),
    CONSTRAINT fk_royalty_rule_dim_type
        FOREIGN KEY (tenant_id, tenant_product_group_type_id)
        REFERENCES general_schema.tenant_product_group_type(tenant_id, tenant_product_group_type_id)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_royalty_rule_dimension_rule
    ON pos_schema.royalty_rule_dimension(royalty_rule_id);

CREATE INDEX IF NOT EXISTS idx_royalty_rule_dimension_type
    ON pos_schema.royalty_rule_dimension(tenant_id, tenant_product_group_type_id);

CREATE TABLE IF NOT EXISTS pos_schema.royalty_option (
    royalty_option_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    royalty_rule_id           UUID NOT NULL REFERENCES pos_schema.royalty_rule(royalty_rule_id) ON DELETE CASCADE,
    tenant_id                 UUID NOT NULL,
    tenant_product_group_id   UUID NOT NULL,
    quantity                  INT NOT NULL CHECK (quantity > 0),
    created_at                TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (royalty_rule_id, tenant_product_group_id),
    CONSTRAINT fk_royalty_option_group FOREIGN KEY (tenant_id, tenant_product_group_id)
        REFERENCES general_schema.tenant_product_group(tenant_id, tenant_product_group_id) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_royalty_option_rule
    ON pos_schema.royalty_option(royalty_rule_id);

-- FK deferred: sale_item.royalty_option_id / royalty_rule_id (defined here, applied to sale_item above)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'sale_item_royalty_option_id_fkey'
          AND conrelid = 'pos_schema.sale_item'::regclass
    ) THEN
        ALTER TABLE pos_schema.sale_item
            ADD CONSTRAINT sale_item_royalty_option_id_fkey
            FOREIGN KEY (royalty_option_id)
            REFERENCES pos_schema.royalty_option(royalty_option_id)
            ON DELETE SET NULL;
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'sale_item_royalty_rule_id_fkey'
          AND conrelid = 'pos_schema.sale_item'::regclass
    ) THEN
        ALTER TABLE pos_schema.sale_item
            ADD CONSTRAINT sale_item_royalty_rule_id_fkey
            FOREIGN KEY (royalty_rule_id)
            REFERENCES pos_schema.royalty_rule(royalty_rule_id)
            ON DELETE SET NULL;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS pos_schema.session_group_sales (
    session_group_sales_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    cash_register_session_id uuid NOT NULL
        REFERENCES pos_schema.cash_register_session(cash_register_session_id)
        ON DELETE CASCADE,
    tenant_product_group_id  uuid NOT NULL,
    group_name               VARCHAR(200) NOT NULL,
    total_amount             NUMERIC(14, 2) NOT NULL,
    UNIQUE (cash_register_session_id, tenant_product_group_id)
);

CREATE INDEX IF NOT EXISTS idx_session_group_sales_session
    ON pos_schema.session_group_sales(cash_register_session_id);

CREATE TABLE IF NOT EXISTS pos_schema.expense_type (
    expense_type_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL,
    expense_type_name   VARCHAR(100) NOT NULL,
    expense_type_detail TEXT,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_expense_type_tenant
    ON pos_schema.expense_type(tenant_id);

CREATE TABLE IF NOT EXISTS pos_schema.expense (
    expense_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    expense_type_id   uuid NOT NULL REFERENCES pos_schema.expense_type(expense_type_id) ON DELETE RESTRICT,
    expense_amount    NUMERIC(14, 2) NOT NULL CHECK (expense_amount > 0),
    branch_id         uuid NOT NULL,
    user_id           uuid NOT NULL,
    status            TEXT DEFAULT 'approved',
    rejection_reason  TEXT,
    created_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_expense_type_fk ON pos_schema.expense(expense_type_id);
CREATE INDEX IF NOT EXISTS idx_expense_branch   ON pos_schema.expense(branch_id);

CREATE TABLE IF NOT EXISTS pos_schema.sale_account_receivable (
    sale_account_receivable_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_receivable_id      UUID NOT NULL UNIQUE REFERENCES general_schema.account_receivable(account_receivable_id) ON DELETE CASCADE,
    sale_id                    UUID NOT NULL UNIQUE REFERENCES pos_schema.sale(sale_id) ON DELETE CASCADE,
    tax_amount                 NUMERIC(12,3) DEFAULT 0,
    account_receivable_status  INTEGER REFERENCES general_schema.account_receivable_status(status_id),
    created_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS pos_schema.sale_collection (
    sale_collection_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_account_receivable_id UUID NOT NULL REFERENCES pos_schema.sale_account_receivable(sale_account_receivable_id) ON DELETE CASCADE,
    payment_method_id          INTEGER REFERENCES general_schema.payment_method(payment_method_id),
    currency_id                INTEGER NOT NULL DEFAULT 1 REFERENCES general_schema.currency(currency_id),
    amount_paid                NUMERIC(12,3) NOT NULL CHECK (amount_paid > 0),
    payment_date               TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    payment_reference          VARCHAR(100),
    notes                      TEXT,
    created_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_sale_collection_receivable
    ON pos_schema.sale_collection(sale_account_receivable_id);

CREATE INDEX IF NOT EXISTS idx_sale_collection_date
    ON pos_schema.sale_collection(payment_date);

CREATE TABLE IF NOT EXISTS pos_schema.sale_collection_alert_type (
    collection_alert_type_id   SERIAL PRIMARY KEY,
    collection_alert_type_name VARCHAR(50) NOT NULL,
    description                TEXT,
    created_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS pos_schema.sale_collection_alert (
    collection_alert_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sale_account_receivable_id UUID NOT NULL REFERENCES pos_schema.sale_account_receivable(sale_account_receivable_id) ON DELETE CASCADE,
    collection_alert_type_id   INTEGER NOT NULL REFERENCES pos_schema.sale_collection_alert_type(collection_alert_type_id),
    alert_date                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_resolved                BOOLEAN DEFAULT FALSE,
    created_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at                 TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS pos_schema.sale_collection_alert_config (
    collection_alert_config_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                   UUID UNIQUE NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    warning_days_before_due     INTEGER DEFAULT 7,
    urgent_days_before_due      INTEGER DEFAULT 3,
    email_notifications_enabled BOOLEAN DEFAULT TRUE,
    sms_notifications_enabled   BOOLEAN DEFAULT FALSE,
    created_at                  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at                  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_expense_user     ON pos_schema.expense(user_id);
CREATE INDEX IF NOT EXISTS idx_expense_status   ON pos_schema.expense(status);



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
    /*implementacion */
    is_applied BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (tenant_id, product_variant_id) 
        REFERENCES general_schema.product_variant(tenant_id, product_variant_id) ON DELETE CASCADE  
);
CREATE INDEX IF NOT EXISTS idx_discrepancy_product_variant 
    ON inventory_schema.discrepancy_count(tenant_id, product_variant_id);

/*implementacion */
CREATE INDEX IF NOT EXISTS idx_discrepancy_pending
    ON inventory_schema.discrepancy_count(warehouse_id, tenant_id)
    WHERE is_applied = FALSE;

CREATE TABLE IF NOT EXISTS inventory_transfer_request_status (
    inventory_transfer_request_status_id SERIAL PRIMARY KEY,
    status_name VARCHAR(50) NOT NULL UNIQUE,
    status_description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO inventory_schema.inventory_transfer_request_status (inventory_transfer_request_status_id, status_name, status_description) VALUES
    (1, 'pending',   'Solicitud pendiente de aprobación'),
    (2, 'approved',  'Solicitud aprobada y transferencia ejecutada'),
    (3, 'rejected',  'Solicitud rechazada'),
    (4, 'cancelled', 'Solicitud cancelada')
ON CONFLICT (inventory_transfer_request_status_id) DO UPDATE SET
    status_name = EXCLUDED.status_name,
    status_description = EXCLUDED.status_description;

CREATE TABLE IF NOT EXISTS inventory_transfer_request (
    inventory_transfer_request_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL,
    from_warehouse_id uuid NOT NULL REFERENCES inventory_schema.warehouse(warehouse_id) ON DELETE CASCADE,
    to_warehouse_id uuid NOT NULL REFERENCES inventory_schema.warehouse(warehouse_id) ON DELETE CASCADE,
    inventory_transfer_request_status_id INTEGER NOT NULL REFERENCES inventory_schema.inventory_transfer_request_status(inventory_transfer_request_status_id),
    requested_by_user_id uuid,
    approved_by_user_id uuid,
    rejection_reason TEXT,
    inventory_transfer_id uuid REFERENCES inventory_schema.inventory_transfer(inventory_transfer_id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS inventory_transfer_request_product (
    inventory_transfer_request_product_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    inventory_transfer_request_id uuid NOT NULL REFERENCES inventory_schema.inventory_transfer_request(inventory_transfer_request_id) ON DELETE CASCADE,
    tenant_id uuid NOT NULL,
    product_variant_id uuid NOT NULL,
    amount INTEGER NOT NULL CHECK (amount > 0),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (tenant_id, product_variant_id)
        REFERENCES general_schema.product_variant(tenant_id, product_variant_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_transfer_request_tenant ON inventory_schema.inventory_transfer_request(tenant_id);
CREATE INDEX IF NOT EXISTS idx_transfer_request_from_warehouse ON inventory_schema.inventory_transfer_request(from_warehouse_id);
CREATE INDEX IF NOT EXISTS idx_transfer_request_to_warehouse ON inventory_schema.inventory_transfer_request(to_warehouse_id);
CREATE INDEX IF NOT EXISTS idx_transfer_request_product_request ON inventory_schema.inventory_transfer_request_product(inventory_transfer_request_id);
CREATE INDEX IF NOT EXISTS idx_transfer_request_product_variant ON inventory_schema.inventory_transfer_request_product(tenant_id, product_variant_id);



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
    added_by uuid REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_supplier_name on purchase_schema.supplier(supplier_name);

CREATE INDEX IF NOT EXISTS idx_supplier_added_by ON purchase_schema.supplier(added_by);

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
    currency_id INTEGER NOT NULL DEFAULT 1 REFERENCES general_schema.currency(currency_id),
    amount_paid NUMERIC(12,3) NOT NULL CHECK (amount_paid > 0),
    payment_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    payment_reference VARCHAR(100),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_purchase_order_payment_payable ON purchase_schema.purchase_order_payment(purchase_account_payable_id);
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
-- CROSS-SCHEMA CONSTRAINTS
-- Applied after all referenced schemas exist
-- =============================================
ALTER TABLE general_schema.product_variant
    ADD CONSTRAINT fk_product_variant_supplier
    FOREIGN KEY (supplier_id) REFERENCES purchase_schema.supplier(supplier_id) ON DELETE SET NULL;


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

CREATE TABLE IF NOT EXISTS hr_schema.config (
  branch_id UUID PRIMARY KEY REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
  foul_expiration_months INTEGER DEFAULT 6,
  updated_at TIMESTAMP DEFAULT current_timestamp
);

CREATE TABLE IF NOT EXISTS hr_schema.turn (
  turn_id SERIAL PRIMARY KEY,
  branch_id UUID REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE NOT NULL,
  entry TIME NOT NULL,
  out TIME NOT NULL
);
-- insert into hr_schema.turn (branch_id, entry, out) values
-- ('64ff2bad-4012-42a6-8aa9-48dd67bfb8c6', '08:00:00', '16:00:00');

CREATE INDEX branch_turn_idx ON hr_schema.turn(branch_id);

CREATE TABLE IF NOT EXISTS hr_schema.duties_type (
	duties_type_id SERIAL PRIMARY KEY,
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
	name VARCHAR(150) NOT NULL,
	description TEXT,
	is_active BOOLEAN NOT NULL DEFAULT TRUE,
	created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_duties_type_tenant ON hr_schema.duties_type(tenant_id);

CREATE TABLE IF NOT EXISTS contract(
	contract_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id),
	start_date DATE NOT NULL,
	end_date DATE NOT NULL,
	hours INTEGER NOT NULL,
	base_salary NUMERIC(19, 4) NOT NULL,
	duties TEXT,
	duties_type_id INTEGER REFERENCES hr_schema.duties_type(duties_type_id) ON DELETE SET NULL,
	turn_type INTEGER,
	turn_id INTEGER REFERENCES hr_schema.turn(turn_id) ON DELETE SET NULL
);
--Indice para filtracion o busqueda por rango de precios
CREATE INDEX idx_contract_base_salary ON hr_schema.contract (base_salary);

CREATE TABLE IF NOT EXISTS employee(
	employee_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	user_id UUID REFERENCES general_schema.users(user_id) ON DELETE SET NULL,
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id),
	branch_id UUID NOT NULL REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
	first_name VARCHAR(100) NOT NULL,
	last_name VARCHAR(100) NOT NULL,
	doc_number VARCHAR(100) NOT NULL UNIQUE,
	identification_type_id INTEGER REFERENCES general_schema.identification_type(identification_type_id) ON DELETE SET NULL,
	phone VARCHAR(100) NOT NULL,
	email VARCHAR(100) NOT NULL UNIQUE,
	contract_id UUID NOT NULL REFERENCES hr_schema.contract(contract_id) ON DELETE CASCADE,
	payment_schedule_id INTEGER NOT NULL REFERENCES hr_schema.payment_schedule(payment_schedule_id),
	is_active BOOLEAN DEFAULT true,
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
	
--Indice para que se pueda garantizar que no haya empleados duplicados
CREATE UNIQUE INDEX idx_employee_doc_number ON hr_schema.employee (doc_number);

--Indice para JOINs de tipo de documento
CREATE INDEX idx_employee_identification_type ON hr_schema.employee (identification_type_id);

--Inidice para la recuperacion de cuentas o autenticacion del empleado
CREATE UNIQUE INDEX idx_employee_email ON hr_schema.employee (email);

--Indices destinados para la aceleracion de los JOINS
CREATE INDEX idx_employee_user_id ON hr_schema.employee (user_id);
CREATE INDEX idx_employee_contract_id ON hr_schema.employee (contract_id);
CREATE INDEX idx_employee_payment_schedule_id ON hr_schema.employee (payment_schedule_id);

--Indice que se utilizara unicamente para el proceso de nomina y generacion de reportes
CREATE INDEX idx_employee_is_active ON hr_schema.employee (is_active);

CREATE TABLE IF NOT EXISTS hr_schema.foul(
  foul_id SERIAL PRIMARY KEY,
  employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id),
  branch_id UUID NOT NULL REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
  identificator VARCHAR(50) UNIQUE NOT NULL, 
  foul_date DATE NOT NULL,
  foul_hour TIME NOT NULL,
  description TEXT
);

CREATE INDEX idx_look_employee ON hr_schema.foul(employee_id);
CREATE INDEX idx_look_period_fouls ON hr_schema.foul(foul_date);
CREATE INDEX idx_identificator_foul ON hr_schema.foul(identificator);

CREATE TABLE IF NOT EXISTS hr_schema.suspention (
  suspention_id SERIAL PRIMARY KEY,
  employee_id UUID REFERENCES hr_schema.employee(employee_id),
	branch_id UUID NOT NULL REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
  suspention_start DATE NOT NULL,
  suspention_end DATE NOT NULL,
  reason TEXT NOT NULL,
	is_active BOOLEAN DEFAULT TRUE,
	created_at TIMESTAMP DEFAULT current_timestamp
);

CREATE INDEX get_employee_suspention_idx ON hr_schema.suspention(employee_id);
CREATE INDEX get_suspentions_period_idx ON hr_schema.suspention(suspention_start, suspention_end);
CREATE INDEX idx_branch_suspention ON hr_schema.suspention(branch_id);

CREATE TABLE IF NOT EXISTS clocking(
	clocking_id SERIAL PRIMARY KEY NOT NULL,
	employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id),
	branch_id UUID NOT NULL REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
	clock_in TIMESTAMP,
	clock_out TIMESTAMP,
	turn_hours NUMERIC NOT NULL DEFAULT 0
);

-- Indice para buscar los turnos de un empleado dentro de un rango de fechas
CREATE INDEX idx_track_employee_hours_in ON hr_schema.clocking (employee_id, clock_in DESC);
-- Indice para ubicar turnos por sucursal
CREATE INDEX idx_track_hours_branch_id ON hr_schema.clocking (branch_id);

CREATE TABLE IF NOT EXISTS hr_schema.tardiness (
  tardiness_id SERIAL PRIMARY KEY,
  employee_id UUID REFERENCES hr_schema.employee(employee_id),
  branch_id UUID REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
  type VARCHAR(20) NOT NULL, -- "late" | "early"
  log TEXT,
  registered_at DATE DEFAULT NOW()
);

CREATE INDEX idx_emp_tardiness_srch ON hr_schema.tardiness(employee_id);
CREATE INDEX idx_brnch_tardiness_srch ON hr_schema.tardiness(branch_id);
CREATE INDEX idx_register_srch ON hr_schema.tardiness(registered_at);

CREATE TABLE IF NOT EXISTS hr_schema.holiday (
  holiday_id SERIAL PRIMARY KEY NOT NULL,
  date TIMESTAMP NOT NULL,
  holiday_name VARCHAR(150) NOT NULL,
  is_freeday BOOLEAN NOT NULL DEFAULT TRUE,
  is_payable BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS hr_schema.incapacity (
    incapacity_id SERIAL PRIMARY KEY,
    branch_id UUID  REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
    employee_id UUID  REFERENCES hr_schema.employee(employee_id),
    type VARCHAR(50),
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    percentage_to_pay DECIMAL(5, 2) NOT NULL,
    days_paying INTEGER DEFAULT 3,
    is_active BOOLEAN DEFAULT TRUE
);

CREATE INDEX search_branch_index ON hr_schema.incapacity(branch_id);
CREATE INDEX incapacity_search_idx ON hr_schema.incapacity(employee_id);
CREATE INDEX filter_by_periods_idx ON hr_schema.incapacity(period_start, period_end);

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
	is_active BOOLEAN DEFAULT TRUE,
	base_value NUMERIC(19, 4) DEFAULT 0,
	code VARCHAR(10) NOT NULL
);

-- Indice para filtracion por conceptos
-- FIXME: column "ccss_apply" does not exist 
-- CREATE INDEX IF NOT EXISTS idx_payroll_concept_apply ON hr_schema.payroll_concept(ccss_apply, tax_apply);

CREATE TABLE IF NOT EXISTS paysheet(
	paysheet_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id),
	branch_id UUID NOT NULL REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
	period_start DATE NOT NULL,
	period_end DATE NOT NULL,
	payment_date TIMESTAMP,
	total_earnings NUMERIC(19, 4) NOT NULL DEFAULT 0,
	total_deductions NUMERIC(19, 4) NOT NULL DEFAULT 0,
	net_total NUMERIC(19, 4) NOT NULL DEFAULT 0,
	status_id INTEGER NOT NULL REFERENCES hr_schema.paysheet_status(status_id),
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
-- SCHEMA: ACCOUNTING
-- Source: schemas/accounting/accounting_schema.sql
-- =============================================
-- SCHEMA: accounting
-- Módulo 4.1 - Contabilidad General y Registros Automatizados
CREATE SCHEMA IF NOT EXISTS accounting_schema;
SET SEARCH_PATH TO accounting_schema;

-- -------------------------------------------------------
-- CATÁLOGOS
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS account_type (
    account_type_id SERIAL PRIMARY KEY,
    type_name VARCHAR(50) UNIQUE NOT NULL,
    nature VARCHAR(10) NOT NULL CHECK (nature IN ('DEBIT', 'CREDIT')),
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE accounting_schema.account_type IS
    'Types of accounts following NIIF for PYMES: Activo, Pasivo, Patrimonio, Ingreso, Gasto, Costo.
     Nature indicates the normal balance side (DEBIT for assets/expenses, CREDIT for liabilities/equity/income).';

CREATE TABLE IF NOT EXISTS journal_entry_status (
    status_id SERIAL PRIMARY KEY,
    status_name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS source_type (
    source_type_id SERIAL PRIMARY KEY,
    source_name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE accounting_schema.source_type IS
    'Catalog of transaction source types that trigger journal entries (SALE, PURCHASE, PAYMENT, MANUAL, etc.).';

-- -------------------------------------------------------
-- CENTRO DE COSTOS
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS cost_center (
    cost_center_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    center_code VARCHAR(20) NOT NULL,
    center_name VARCHAR(100) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(tenant_id, center_code)
);

CREATE INDEX IF NOT EXISTS idx_cost_center_tenant
    ON accounting_schema.cost_center(tenant_id);

-- -------------------------------------------------------
-- PLAN DE CUENTAS (Chart of Accounts)
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS chart_of_accounts (
    account_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    account_code VARCHAR(20) NOT NULL,
    account_name VARCHAR(150) NOT NULL,
    account_type_id INTEGER NOT NULL REFERENCES accounting_schema.account_type(account_type_id),
    parent_account_id UUID REFERENCES accounting_schema.chart_of_accounts(account_id) ON DELETE SET NULL,
    cost_center_id UUID REFERENCES accounting_schema.cost_center(cost_center_id) ON DELETE SET NULL,
    is_active BOOLEAN DEFAULT TRUE,
    is_system BOOLEAN DEFAULT FALSE,
    allows_transactions BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(tenant_id, account_code),
    CONSTRAINT chk_no_self_parent CHECK (account_id != parent_account_id)
);

CREATE INDEX IF NOT EXISTS idx_coa_tenant
    ON accounting_schema.chart_of_accounts(tenant_id);
CREATE INDEX IF NOT EXISTS idx_coa_parent
    ON accounting_schema.chart_of_accounts(parent_account_id)
    WHERE parent_account_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_coa_type
    ON accounting_schema.chart_of_accounts(account_type_id);
CREATE INDEX IF NOT EXISTS idx_coa_tenant_active
    ON accounting_schema.chart_of_accounts(tenant_id, is_active)
    WHERE is_active = TRUE;

COMMENT ON COLUMN accounting_schema.chart_of_accounts.is_system IS
    'TRUE = account was created from the NIIF template during tenant onboarding. Cannot be deleted by the user.';
COMMENT ON COLUMN accounting_schema.chart_of_accounts.allows_transactions IS
    'FALSE = header/parent account used only for grouping. Journal entry lines can only reference accounts where this is TRUE.';

-- -------------------------------------------------------
-- ASIENTOS CONTABLES (Journal Entries)
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS journal_entry (
    entry_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    entry_number SERIAL,
    source_type_id INTEGER NOT NULL REFERENCES accounting_schema.source_type(source_type_id),
    source_id UUID,
    entry_date DATE NOT NULL DEFAULT CURRENT_DATE,
    description TEXT,
    status_id INTEGER NOT NULL DEFAULT 1 REFERENCES accounting_schema.journal_entry_status(status_id),
    total_debit NUMERIC(14,4) NOT NULL DEFAULT 0 CHECK (total_debit >= 0),
    total_credit NUMERIC(14,4) NOT NULL DEFAULT 0 CHECK (total_credit >= 0),
    created_by UUID REFERENCES general_schema.users(user_id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(tenant_id, entry_number)
);

CREATE INDEX IF NOT EXISTS idx_je_tenant
    ON accounting_schema.journal_entry(tenant_id);
CREATE INDEX IF NOT EXISTS idx_je_date
    ON accounting_schema.journal_entry(tenant_id, entry_date);
CREATE INDEX IF NOT EXISTS idx_je_source
    ON accounting_schema.journal_entry(source_type_id, source_id)
    WHERE source_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_je_status
    ON accounting_schema.journal_entry(status_id);

COMMENT ON COLUMN accounting_schema.journal_entry.source_id IS
    'UUID of the originating transaction (sale_id, purchase_order_id, etc.). NULL for manual entries.';
COMMENT ON COLUMN accounting_schema.journal_entry.total_debit IS
    'Denormalized sum of all debit lines. Must equal total_credit for a balanced entry.';

-- -------------------------------------------------------
-- LÍNEAS DE ASIENTO (Journal Entry Lines)
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS journal_entry_line (
    line_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entry_id UUID NOT NULL REFERENCES accounting_schema.journal_entry(entry_id) ON DELETE CASCADE,
    account_id UUID NOT NULL REFERENCES accounting_schema.chart_of_accounts(account_id),
    cost_center_id UUID REFERENCES accounting_schema.cost_center(cost_center_id) ON DELETE SET NULL,
    debit_amount NUMERIC(14,4) NOT NULL DEFAULT 0,
    credit_amount NUMERIC(14,4) NOT NULL DEFAULT 0,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_positive_amounts CHECK (debit_amount >= 0 AND credit_amount >= 0),
    CONSTRAINT chk_single_side CHECK (NOT (debit_amount > 0 AND credit_amount > 0))
);

CREATE INDEX IF NOT EXISTS idx_jel_entry
    ON accounting_schema.journal_entry_line(entry_id);
CREATE INDEX IF NOT EXISTS idx_jel_account
    ON accounting_schema.journal_entry_line(account_id);

COMMENT ON CONSTRAINT chk_single_side ON accounting_schema.journal_entry_line IS
    'Each line must be either a debit or a credit, never both. This enforces clean double-entry bookkeeping.';

-- -------------------------------------------------------
-- REGLAS DE MAPEO CONTABLE (Accounting Mapping Rules)
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS accounting_mapping_rule (
    rule_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    source_type_id INTEGER NOT NULL REFERENCES accounting_schema.source_type(source_type_id),
    rule_name VARCHAR(100) NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(tenant_id, source_type_id, rule_name)
);

CREATE TABLE IF NOT EXISTS accounting_mapping_rule_line (
    rule_line_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    rule_id UUID NOT NULL REFERENCES accounting_schema.accounting_mapping_rule(rule_id) ON DELETE CASCADE,
    account_id UUID NOT NULL REFERENCES accounting_schema.chart_of_accounts(account_id),
    side VARCHAR(6) NOT NULL CHECK (side IN ('DEBIT', 'CREDIT')),
    amount_field VARCHAR(50) NOT NULL,
    line_order INTEGER NOT NULL DEFAULT 0,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(rule_id, line_order)
);

CREATE INDEX IF NOT EXISTS idx_amrl_rule
    ON accounting_schema.accounting_mapping_rule_line(rule_id);

COMMENT ON TABLE accounting_schema.accounting_mapping_rule IS
    'Defines which accounts to debit/credit for each transaction type. Used by generar_asiento() to automate journal entries.';
COMMENT ON COLUMN accounting_schema.accounting_mapping_rule_line.amount_field IS
    'References the field from the source transaction to use as the amount (e.g., total_amount, tax_amount, subtotal_amount).';

-- -------------------------------------------------------
-- CATEGORÍAS DE GASTO (Expense Categories)
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS expense_category (
    category_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    account_code VARCHAR(20) NOT NULL,
    parent_category_id UUID REFERENCES accounting_schema.expense_category(category_id) ON DELETE SET NULL,
    is_fixed BOOLEAN DEFAULT TRUE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(tenant_id, name),
    CONSTRAINT chk_no_self_parent_cat CHECK (category_id != parent_category_id)
);

CREATE INDEX IF NOT EXISTS idx_expense_cat_tenant
    ON accounting_schema.expense_category(tenant_id);
CREATE INDEX IF NOT EXISTS idx_expense_cat_active
    ON accounting_schema.expense_category(tenant_id, is_active)
    WHERE is_active = TRUE;

COMMENT ON TABLE accounting_schema.expense_category IS
    'Expense categories that map to chart of accounts codes. is_fixed=TRUE for recurring/fixed expenses, FALSE for variable.';
COMMENT ON COLUMN accounting_schema.expense_category.account_code IS
    'References chart_of_accounts.account_code for the tenant. Used to resolve the debit account in journal entries.';

-- -------------------------------------------------------
-- GASTOS (Expenses)
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS expense (
    expense_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    branch_id UUID NOT NULL REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES accounting_schema.expense_category(category_id),
    description TEXT,
    amount NUMERIC(14,4) NOT NULL CHECK (amount > 0),
    tax_amount NUMERIC(14,4) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    total_amount NUMERIC(14,4) NOT NULL CHECK (total_amount > 0),
    currency_id INTEGER NOT NULL REFERENCES general_schema.currency(currency_id),
    expense_date DATE NOT NULL DEFAULT CURRENT_DATE,
    payment_method VARCHAR(20) NOT NULL DEFAULT 'CASH'
        CHECK (payment_method IN ('CASH', 'BANK', 'CREDIT_CARD', 'CHECK', 'TRANSFER')),
    reference_number VARCHAR(50),
    notes TEXT,
    created_by UUID REFERENCES general_schema.users(user_id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_expense_tenant
    ON accounting_schema.expense(tenant_id);
CREATE INDEX IF NOT EXISTS idx_expense_branch
    ON accounting_schema.expense(branch_id);
CREATE INDEX IF NOT EXISTS idx_expense_date
    ON accounting_schema.expense(tenant_id, expense_date);
CREATE INDEX IF NOT EXISTS idx_expense_category
    ON accounting_schema.expense(category_id);

COMMENT ON TABLE accounting_schema.expense IS
    'Individual expense records. Each expense generates a journal entry via generateExpenseJournal().';
COMMENT ON COLUMN accounting_schema.expense.payment_method IS
    'Determines the credit account in journal entries: CASH→Caja General, BANK/TRANSFER/CHECK→Bancos, CREDIT_CARD→CxP.';

-- -------------------------------------------------------
-- PERÍODO FISCAL (Fiscal Period)
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS fiscal_period (
    period_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    is_closed BOOLEAN DEFAULT FALSE,
    closed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(tenant_id, name),
    CONSTRAINT chk_period_dates CHECK (end_date > start_date)
);

CREATE INDEX IF NOT EXISTS idx_fiscal_period_tenant
    ON accounting_schema.fiscal_period(tenant_id);
CREATE INDEX IF NOT EXISTS idx_fiscal_period_dates
    ON accounting_schema.fiscal_period(tenant_id, start_date, end_date);

COMMENT ON TABLE accounting_schema.fiscal_period IS
    'Fiscal periods for financial reporting. is_closed prevents modifications to journal entries within the period.';



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
    v_current_id VARCHAR(13);
    v_visited VARCHAR(13)[];
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
        
        IF NEW.hierarchy_level > 10 THEN
            RAISE EXCEPTION 'Maximum category depth exceeded (max 10 levels)';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION general_schema.update_category_hierarchy_level() IS
    'Automatically calculates and updates hierarchy_level based on parent category. Enforces max depth of 10 levels.';

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
        COUNT(p.cabys_code) AS product_count
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

drop trigger if exists update_product_timestamp on general_schema.product;
create trigger update_product_timestamp before update on general_schema.product
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_unit_measure_timestamp on general_schema.unit_measure;
create trigger update_unit_measure_timestamp before update on general_schema.unit_measure
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_commercial_unit_measure_timestamp on general_schema.commercial_unit_measure;
create trigger update_commercial_unit_measure_timestamp before update on general_schema.commercial_unit_measure
for each row execute function general_schema.update_timestamp();

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

-- -----------------------------------------------------------------
-- Currency conversion function
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION general_schema.convert_currency(
    p_amount           NUMERIC,
    p_from_currency_id INTEGER,
    p_to_currency_id   INTEGER,
    p_date             DATE DEFAULT CURRENT_DATE
) RETURNS NUMERIC
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_rate NUMERIC(12,6);
BEGIN
    IF p_from_currency_id = p_to_currency_id THEN
        RETURN p_amount;
    END IF;

    SELECT er.rate INTO v_rate
    FROM general_schema.exchange_rate er
    WHERE er.from_currency_id = p_from_currency_id
      AND er.to_currency_id   = p_to_currency_id
      AND er.effective_date   <= p_date
    ORDER BY er.effective_date DESC
    LIMIT 1;

    IF v_rate IS NULL THEN
        SELECT (1.0 / er.rate) INTO v_rate
        FROM general_schema.exchange_rate er
        WHERE er.from_currency_id = p_to_currency_id
          AND er.to_currency_id   = p_from_currency_id
          AND er.effective_date   <= p_date
        ORDER BY er.effective_date DESC
        LIMIT 1;
    END IF;

    IF v_rate IS NULL THEN
        RAISE EXCEPTION 'No exchange rate found for currency % -> % on or before %',
            p_from_currency_id, p_to_currency_id, p_date;
    END IF;

    RETURN ROUND(p_amount * v_rate, 3);
END;
$$;

-- -----------------------------------------------------------------
-- Update product cost on purchase receipt (weighted average cost)
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION general_schema.update_product_cost_on_receipt(
    p_tenant_id          UUID,
    p_product_variant_id UUID,
    p_purchase_order_id  UUID,
    p_quantity           INTEGER,
    p_unit_cost          NUMERIC(12,3),
    p_currency_id        INTEGER DEFAULT NULL,
    p_exchange_rate_val  NUMERIC(12,6) DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
    v_current_stock INTEGER;
    v_current_avg   NUMERIC(12,3);
    v_new_avg       NUMERIC(12,3);
    v_cost_converted NUMERIC(12,3);
BEGIN
    IF p_exchange_rate_val IS NOT NULL AND p_exchange_rate_val > 0 THEN
        v_cost_converted := ROUND(p_unit_cost * p_exchange_rate_val, 3);
    ELSE
        v_cost_converted := p_unit_cost;
    END IF;

    SELECT COALESCE(SUM(i.stock), 0) INTO v_current_stock
    FROM inventory_schema.inventory i
    WHERE i.tenant_id = p_tenant_id
      AND i.product_variant_id = p_product_variant_id;

    SELECT COALESCE(pv.weighted_avg_cost, 0) INTO v_current_avg
    FROM general_schema.product_variant pv
    WHERE pv.tenant_id = p_tenant_id
      AND pv.product_variant_id = p_product_variant_id;

    IF (v_current_stock + p_quantity) > 0 THEN
        v_new_avg := ROUND(
            (v_current_stock * v_current_avg + p_quantity * v_cost_converted)
            / (v_current_stock + p_quantity),
            3
        );
    ELSE
        v_new_avg := v_cost_converted;
    END IF;

    UPDATE general_schema.product_variant
    SET cost_price = v_cost_converted,
        weighted_avg_cost = v_new_avg,
        last_purchase_date = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP
    WHERE tenant_id = p_tenant_id
      AND product_variant_id = p_product_variant_id;

    INSERT INTO general_schema.product_cost_history (
        tenant_id, product_variant_id, purchase_order_id,
        unit_cost, currency_id, exchange_rate, unit_cost_converted,
        quantity, effective_date
    ) VALUES (
        p_tenant_id, p_product_variant_id, p_purchase_order_id,
        p_unit_cost, p_currency_id, p_exchange_rate_val, v_cost_converted,
        p_quantity, CURRENT_TIMESTAMP
    );
END;
$$;



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

CREATE OR REPLACE FUNCTION calculate_digital_sale_invoice_total()
returns trigger as $$
BEGIN
    new.total_amount := new.subtotal_amount + new.tax_amount;
    return new;
end;
$$ language plpgsql;

drop trigger if exists calculate_digital_sale_invoice_total_trigger on pos_schema.digital_sale_invoice;
create trigger calculate_digital_sale_invoice_total_trigger
    before insert or update on pos_schema.digital_sale_invoice
    for each row
    execute function calculate_digital_sale_invoice_total();

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

CREATE OR REPLACE FUNCTION pos_schema.get_digital_sale_invoice(_sale_id uuid)
returns table (
    digital_sale_invoice_id uuid,
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
        b.digital_sale_invoice_id,
        b.sale_id,
        b.tenant_customer_id,
        b.currency_id,
        b.subtotal_amount,
        b.tax_amount,
        b.total_amount,
        b.created_at,
        b.updated_at
    from pos_schema.digital_sale_invoice b
    where b.sale_id = _sale_id;
end;
$$ language plpgsql;

CREATE OR REPLACE FUNCTION create_digital_sale_invoice()
returns trigger as $$
declare
    _digital_sale_invoice_id uuid;
    _tenant_customer_id uuid;
    _tenant_id uuid;
    _currency_id INTEGER;
    _subtotal numeric(10,2);
    _tax numeric(10,2);
    _total numeric(10,2);
    _payment_ids uuid[];
    _cash_register_id uuid;
    _items_count int;
BEGIN
        raise notice 'Creating digital sale invoice for sale: %', new.sale_id;
        
        if exists(
            select 1 from pos_schema.digital_sale_invoice
            where sale_id = new.sale_id
        ) then
            raise notice 'Digital sale invoice already exists for sale: %', new.sale_id;
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

        -- Resolve cash register from active session in the branch
        SELECT cr.cash_register_id INTO _cash_register_id
        FROM pos_schema.cash_register_session crs
        JOIN pos_schema.cash_register cr ON crs.cash_register_id = cr.cash_register_id
        WHERE cr.branch_id = new.branch_id
        AND crs.is_active = true
        LIMIT 1;

        -- Insert invoice with placeholder totals (will be updated from items)
        INSERT INTO pos_schema.digital_sale_invoice (
            sale_id,              
            tenant_customer_id,
            currency_id,
            subtotal_amount,
            tax_amount,
            total_amount,
            cash_register_id
        ) VALUES (
            new.sale_id,         
            _tenant_customer_id,
            _currency_id,
            0,
            0,
            0,
            _cash_register_id
        ) returning digital_sale_invoice_id into _digital_sale_invoice_id;
        
        raise notice '   Digital sale invoice created: %', _digital_sale_invoice_id;
        raise notice '   Cash Register: %', _cash_register_id;

        INSERT INTO pos_schema.digital_sale_invoice_item (
            digital_sale_invoice_id,
            sale_item_id,
            tenant_id,
            product_variant_id,
            cabys_code,
            tax_rate_id,
            description,
            quantity,
            unit_price,
            subtotal,
            tax_rate_percentage,
            tax_amount,
            total_price
        )
        SELECT
            _digital_sale_invoice_id,
            si.sale_item_id,
            si.tenant_id,
            si.product_variant_id,
            pv.cabys_code,
            p.tax_rate_id,
            COALESCE(pv.variant_name, p.product_name, 'Product'),
            si.quantity,
            si.unit_price,
            si.total_price,
            COALESCE(tr.rate_percentage, 0),
            ROUND(si.total_price * COALESCE(tr.rate_percentage, 0) / 100, 2),
            si.total_price + ROUND(si.total_price * COALESCE(tr.rate_percentage, 0) / 100, 2)
        FROM pos_schema.sale_item si
        JOIN general_schema.product_variant pv 
            ON si.tenant_id = pv.tenant_id AND si.product_variant_id = pv.product_variant_id
        LEFT JOIN general_schema.product p ON pv.cabys_code = p.cabys_code
        LEFT JOIN general_schema.tax_rate tr ON p.tax_rate_id = tr.tax_rate_id
        WHERE si.sale_id = new.sale_id;

        GET DIAGNOSTICS _items_count = ROW_COUNT;
        raise notice '   % invoice item(s) created', _items_count;

        -- Update invoice totals from items (per-item tax)
        SELECT
            COALESCE(SUM(dsii.subtotal), 0),
            COALESCE(SUM(dsii.tax_amount), 0)
        INTO _subtotal, _tax
        FROM pos_schema.digital_sale_invoice_item dsii
        WHERE dsii.digital_sale_invoice_id = _digital_sale_invoice_id;

        _total := _subtotal + _tax;

        UPDATE pos_schema.digital_sale_invoice
        SET subtotal_amount = _subtotal,
            tax_amount = _tax,
            total_amount = _total
        WHERE digital_sale_invoice_id = _digital_sale_invoice_id;

        raise notice '   Subtotal: $%', _subtotal;
        raise notice '   Tax (per-item): $%', _tax;
        raise notice '   Total: $%', _total;
        
        -- Link verified payments
        select array_agg(customer_payment_id) into _payment_ids
        from pos_schema.customer_payment
        where sale_id = new.sale_id
        and verified = true;
        
        INSERT INTO pos_schema.digital_sale_invoice_payment(digital_sale_invoice_id, customer_payment_id, payment_amount)
        select 
            _digital_sale_invoice_id,
            customer_payment_id,
            payment_amount
        from pos_schema.customer_payment
        where customer_payment_id = any(_payment_ids);
        
        raise notice '   % payment(s) linked to digital sale invoice', array_length(_payment_ids, 1);
        raise notice '';
        raise notice 'Digital sale invoice creation completed successfully';
        raise notice '   Invoice ID: %', _digital_sale_invoice_id;
        raise notice '   Sale ID: %', new.sale_id;

        return new;
        
    exception
        when others then
            raise notice 'Error creating digital sale invoice: %', sqlerrm;
            return new;
end;
$$ language plpgsql;

drop trigger if exists on_sale_completed_create_bill on pos_schema.sale;
drop trigger if exists on_sale_completed_create_digital_sale_invoice on pos_schema.sale;
create trigger on_sale_completed_create_digital_sale_invoice
    after update of is_completed on pos_schema.sale
    for each row
    when (old.is_completed is false and new.is_completed is true)
    execute function create_digital_sale_invoice();

CREATE OR REPLACE FUNCTION update_on_return()
returns trigger as $$
declare
    _sale_item_record record;
    _digital_sale_invoice_id uuid;
    _sale_id uuid;
    _total_returned numeric(10,2) := 0;
    _new_subtotal numeric(10,2);
    _new_tax numeric(10,2);
    _new_total numeric(10,2);
    _quantity_remaining INTEGER;
    _sale_subtotal_after numeric(10,2);
    _sale_tax_after numeric(10,2);
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

    -- get digital sale invoice for sale
    select digital_sale_invoice_id into _digital_sale_invoice_id from pos_schema.digital_sale_invoice where sale_id = _sale_id limit 1;
    if _digital_sale_invoice_id is null then
        raise exception 'Digital sale invoice not found for sale: %', _sale_id;
    end if;

    raise notice 'Digital Sale Invoice ID: %', _digital_sale_invoice_id;
    raise notice 'Original sale item: qty=% unit=$% total=$%', _sale_item_record.quantity, _sale_item_record.unit_price, _sale_item_record.total_price;

    if new.quantity > _sale_item_record.quantity then
        raise exception 'Cannot return more items than purchased. Purchased: %, Attempting to return: %',
            _sale_item_record.quantity, new.quantity;
    end if;

    _quantity_remaining := _sale_item_record.quantity - new.quantity;
    raise notice 'Return quantity: %  Remaining qty: %', new.quantity, _quantity_remaining;

    -- Update or remove sale_item (CASCADE deletes digital_sale_invoice_item if qty = 0)
    if _quantity_remaining = 0 then
        -- First, explicitly delete the corresponding digital_sale_invoice_item to ensure clean state
        delete from pos_schema.digital_sale_invoice_item 
        where digital_sale_invoice_id = _digital_sale_invoice_id
        and sale_item_id = _sale_item_record.sale_item_id;
        
        delete from pos_schema.sale_item where sale_item_id = _sale_item_record.sale_item_id;
        raise notice 'Sale item removed (quantity = 0)';
    else
        update pos_schema.sale_item
        set quantity = _quantity_remaining,
            total_price = _quantity_remaining * unit_price,
            updated_at = current_timestamp
        where sale_item_id = _sale_item_record.sale_item_id;
        raise notice 'Sale item quantity updated from % to %', _sale_item_record.quantity, _quantity_remaining;

        -- Update corresponding digital_sale_invoice_item with correct tax rate
        -- Resolve tax_rate the same way as create_digital_sale_invoice
        update pos_schema.digital_sale_invoice_item dii
        set quantity = _quantity_remaining,
            subtotal = _quantity_remaining * dii.unit_price,
            tax_rate_percentage = COALESCE(tr.rate_percentage, 0),
            tax_amount = ROUND((_quantity_remaining * dii.unit_price) * COALESCE(tr.rate_percentage, 0) / 100, 2),
            total_price = (_quantity_remaining * dii.unit_price)
                + ROUND((_quantity_remaining * dii.unit_price) * COALESCE(tr.rate_percentage, 0) / 100, 2),
            updated_at = current_timestamp
        from general_schema.product_variant pv
        left join general_schema.product p ON pv.cabys_code = p.cabys_code
        left join general_schema.tax_rate tr ON p.tax_rate_id = tr.tax_rate_id
        where dii.digital_sale_invoice_id = _digital_sale_invoice_id
        and dii.sale_item_id = _sale_item_record.sale_item_id
        and dii.tenant_id = pv.tenant_id
        and dii.product_variant_id = pv.product_variant_id;
    end if;

    -- Recalculate digital sale invoice totals from remaining items
    SELECT
        COALESCE(SUM(dsii.subtotal), 0),
        COALESCE(SUM(dsii.tax_amount), 0),
        COALESCE(SUM(dsii.total_price), 0)
    INTO _new_subtotal, _new_tax, _new_total
    FROM pos_schema.digital_sale_invoice_item dsii
    WHERE dsii.digital_sale_invoice_id = _digital_sale_invoice_id;

    update pos_schema.digital_sale_invoice
    set subtotal_amount = _new_subtotal,
        tax_amount = _new_tax,
        total_amount = _new_total,
        updated_at = current_timestamp
    where digital_sale_invoice_id = _digital_sale_invoice_id;

    raise notice 'Digital sale invoice updated: subtotal $% tax $% total $%', _new_subtotal, _new_tax, _new_total;

    -- Recalculate sale totals from remaining sale_items with per-item tax
    SELECT
        COALESCE(SUM(si.total_price), 0),
        COALESCE(SUM(ROUND(si.total_price * COALESCE(tr.rate_percentage, 0) / 100, 2)), 0)
    INTO _sale_subtotal_after, _sale_tax_after
    FROM pos_schema.sale_item si
    JOIN general_schema.product_variant pv
        ON si.tenant_id = pv.tenant_id AND si.product_variant_id = pv.product_variant_id
    LEFT JOIN general_schema.product p ON pv.cabys_code = p.cabys_code
    LEFT JOIN general_schema.tax_rate tr ON p.tax_rate_id = tr.tax_rate_id
    WHERE si.sale_id = _sale_id;

    _new_total := _sale_subtotal_after + _sale_tax_after;

    update pos_schema.sale
    set subtotal_amount = _sale_subtotal_after,
        tax_amount = _sale_tax_after,
        total_amount = _new_total,
        updated_at = current_timestamp
    where sale_id = _sale_id;

    raise notice 'Sale updated: subtotal $% tax $% total $%', _sale_subtotal_after, _sale_tax_after, _new_total;

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
    _amount numeric(10,2),
    _user_id uuid
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
                user_id,
                opened_at,
                opening_amount,
                is_active,
                created_at,
                updated_at
            ) VALUES (
                _cash_register_id,
                _user_id,
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
    _digital_sale_invoice_id uuid;
    _points_earned INTEGER;
    _current_balance INTEGER;
    _cash_payments_total numeric(10,2);
    _points_already_awarded BOOLEAN;
BEGIN
        _digital_sale_invoice_id := new.digital_sale_invoice_id;
        
        select exists(
            select 1 
            from pos_schema.score_transaction 
            where digital_sale_invoice_id = _digital_sale_invoice_id 
            and transaction_type_id = 1  
        ) into _points_already_awarded;
        
        if _points_already_awarded then
            raise notice 'Points already awarded for digital sale invoice %', _digital_sale_invoice_id;
            return new;
        end if;
        
        select tenant_customer_id into _tenant_customer_id
        from pos_schema.digital_sale_invoice
        where digital_sale_invoice_id = _digital_sale_invoice_id;
        
        if _tenant_customer_id is null then
            raise notice 'No customer found for digital sale invoice %', _digital_sale_invoice_id;
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
        from pos_schema.digital_sale_invoice_payment bp
        join pos_schema.customer_payment cp on bp.customer_payment_id = cp.customer_payment_id
        where bp.digital_sale_invoice_id = _digital_sale_invoice_id
        and cp.is_points_redemption = false;
        
        raise notice 'Cash/card payments total: $%', _cash_payments_total;
        
        _points_earned := pos_schema.calculate_purchase_score(
            _tenant_id,
            _tenant_customer_id,
            _cash_payments_total
        );
        
        if _points_earned <= 0 then
            raise notice 'No points earned for this purchase (Invoice: %)', _digital_sale_invoice_id;
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
            digital_sale_invoice_id,
            created_at
        ) VALUES (
            _tenant_id,
            _tenant_customer_id,
            1,  
            _points_earned,
            _digital_sale_invoice_id,
            current_timestamp
        );
        
        raise notice 'Awarded % points to customer %', _points_earned, _tenant_customer_id;
        raise notice 'Invoice: %', _digital_sale_invoice_id;
        raise notice 'New balance: % points', _current_balance;
        
        return new;
        
    exception
        when others then
            raise notice 'Error awarding points: %', sqlerrm;
            return new;
end;
$$ language plpgsql;

drop trigger if exists on_purchase_billed on pos_schema.digital_sale_invoice_payment;
drop trigger if exists on_purchase_billed on pos_schema.digital_sale_invoice_payment;
drop trigger if exists on_invoice_payment_award_points on pos_schema.digital_sale_invoice_payment;
create trigger on_invoice_payment_award_points
    after insert on pos_schema.digital_sale_invoice_payment
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

drop trigger if exists update_bill_timestamp on pos_schema.digital_sale_invoice;
drop trigger if exists update_digital_sale_invoice_timestamp on pos_schema.digital_sale_invoice;
create trigger update_digital_sale_invoice_timestamp before update on pos_schema.digital_sale_invoice
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_digital_sale_invoice_item_timestamp on pos_schema.digital_sale_invoice_item;
create trigger update_digital_sale_invoice_item_timestamp before update on pos_schema.digital_sale_invoice_item
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

drop trigger if exists update_digital_sale_invoice_payment_timestamp on pos_schema.digital_sale_invoice_payment;
drop trigger if exists update_digital_sale_invoice_payment_timestamp on pos_schema.digital_sale_invoice_payment;
create trigger update_digital_sale_invoice_payment_timestamp before update on pos_schema.digital_sale_invoice_payment
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_sale_timestamp on pos_schema.sale;
create trigger update_sale_timestamp before update on pos_schema.sale
for each row execute function general_schema.update_timestamp();

drop trigger if exists update_sale_item_timestamp on pos_schema.sale_item;
create trigger update_sale_item_timestamp before update on pos_schema.sale_item
for each row execute function general_schema.update_timestamp();

CREATE OR REPLACE FUNCTION pos_schema.close_cash_register_session(
    p_session_id     uuid,
    p_closing_amount numeric,
    p_user_cash      numeric DEFAULT 0,
    p_user_debit     numeric DEFAULT 0,
    p_user_credit    numeric DEFAULT 0,
    p_user_transfer  numeric DEFAULT 0
)
RETURNS pos_schema.cash_register_session
LANGUAGE plpgsql
AS $$
DECLARE
    v_session             pos_schema.cash_register_session%ROWTYPE;
    v_system_cash         NUMERIC(14, 2) := 0;
    v_system_debit        NUMERIC(14, 2) := 0;
    v_system_credit       NUMERIC(14, 2) := 0;
    v_system_transfer     NUMERIC(14, 2) := 0;
    v_system_points       NUMERIC(14, 2) := 0;
    v_system_total_sales  NUMERIC(14, 2) := 0;
    v_diff_cash           NUMERIC(14, 2);
    v_diff_debit          NUMERIC(14, 2);
    v_diff_credit         NUMERIC(14, 2);
    v_diff_transfer       NUMERIC(14, 2);
    v_mismatch            BOOLEAN        := FALSE;
    v_mismatch_amt        NUMERIC(14, 2) := 0;
    v_mismatch_type       VARCHAR(10)    := NULL;
BEGIN
    SELECT * INTO v_session
    FROM pos_schema.cash_register_session
    WHERE cash_register_session_id = p_session_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session not found: %', p_session_id;
    END IF;

    IF NOT v_session.is_active THEN
        RAISE EXCEPTION 'Session % is already closed', p_session_id;
    END IF;

    INSERT INTO pos_schema.session_payment_method_sales
        (cash_register_session_id, payment_method_id, total_amount)
    SELECT
        p_session_id,
        cp.payment_method_id,
        COALESCE(SUM(cp.payment_amount), 0)
    FROM pos_schema.customer_payment cp
    INNER JOIN pos_schema.cash_register_sale crs ON crs.sale_id = cp.sale_id
    WHERE crs.cash_register_session_id = p_session_id
    GROUP BY cp.payment_method_id
    ON CONFLICT (cash_register_session_id, payment_method_id)
    DO UPDATE SET total_amount = EXCLUDED.total_amount;

    -- Single aggregate: guaranteed one row, zero for missing methods
    SELECT
        COALESCE(SUM(total_amount) FILTER (WHERE payment_method_id = 1), 0),
        COALESCE(SUM(total_amount) FILTER (WHERE payment_method_id = 2), 0),
        COALESCE(SUM(total_amount) FILTER (WHERE payment_method_id = 3), 0),
        COALESCE(SUM(total_amount) FILTER (WHERE payment_method_id = 4), 0),
        COALESCE(SUM(total_amount) FILTER (WHERE payment_method_id = 5), 0),
        COALESCE(SUM(total_amount), 0)
    INTO
        v_system_cash,
        v_system_debit,
        v_system_credit,
        v_system_transfer,
        v_system_points,
        v_system_total_sales
    FROM pos_schema.session_payment_method_sales
    WHERE cash_register_session_id = p_session_id;

    -- Per-method diff (cash must cover opening float + cash sales)
    v_diff_cash     := p_user_cash     - (v_session.opening_amount + v_system_cash);
    v_diff_debit    := p_user_debit    - v_system_debit;
    v_diff_credit   := p_user_credit   - v_system_credit;
    v_diff_transfer := p_user_transfer - v_system_transfer;

    IF ABS(v_diff_cash)     > 0.01
    OR ABS(v_diff_debit)    > 0.01
    OR ABS(v_diff_credit)   > 0.01
    OR ABS(v_diff_transfer) > 0.01
    THEN
        v_mismatch     := TRUE;
        v_mismatch_amt := v_diff_cash + v_diff_debit + v_diff_credit + v_diff_transfer;
        v_mismatch_type := CASE WHEN v_mismatch_amt > 0 THEN 'surplus' ELSE 'shortage' END;
    END IF;

    INSERT INTO pos_schema.session_group_sales
        (cash_register_session_id, tenant_product_group_id, group_name, total_amount)
    SELECT
        p_session_id,
        tpg.tenant_product_group_id,
        tpg.group_name,
        ROUND(SUM(si.total_price), 2)
    FROM pos_schema.sale_item si
    INNER JOIN pos_schema.cash_register_sale crs_link
        ON crs_link.sale_id = si.sale_id
    INNER JOIN general_schema.product_variant_group_assignment pvga
        ON  pvga.product_variant_id = si.product_variant_id
        AND pvga.tenant_id          = si.tenant_id
    INNER JOIN general_schema.tenant_product_group tpg
        ON tpg.tenant_product_group_id = pvga.tenant_product_group_id
    WHERE crs_link.cash_register_session_id = p_session_id
    GROUP BY tpg.tenant_product_group_id, tpg.group_name
    ON CONFLICT (cash_register_session_id, tenant_product_group_id)
    DO UPDATE SET total_amount = EXCLUDED.total_amount;

    UPDATE pos_schema.cash_register_session
    SET
        closed_at             = NOW(),
        closing_amount        = p_closing_amount,
        is_active             = FALSE,
        cash_sales_amount     = v_system_cash,
        debit_sales_amount    = v_system_debit,
        credit_sales_amount   = v_system_credit,
        transfer_sales_amount = v_system_transfer,
        points_sales_amount   = v_system_points,
        total_sales_amount    = v_system_total_sales,
        user_cash_amount      = p_user_cash,
        user_debit_amount     = p_user_debit,
        user_credit_amount    = p_user_credit,
        user_transfer_amount  = p_user_transfer,
        mismatch              = v_mismatch,
        mismatch_amount       = ABS(v_mismatch_amt),
        mismatch_type         = v_mismatch_type,
        updated_at            = NOW()
    WHERE cash_register_session_id = p_session_id
    RETURNING * INTO v_session;

    RETURN v_session;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- CxC (Cuentas por Cobrar) — Collection subsystem functions
-- Mirror of the AP alert functions in functions/purchase/purchase_functions.sql
-- ─────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS check_account_receivable_completion(UUID);

CREATE OR REPLACE FUNCTION check_account_receivable_completion(_account_receivable_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    _subtotal       NUMERIC(12,3);
    _tax_amount     NUMERIC(12,3);
    _amount_due     NUMERIC(12,3);
    _payments_total NUMERIC(12,3);
    _balance        NUMERIC(12,3);
    _target_sar_id  UUID;
BEGIN
    SELECT
        ar.subtotal,
        sar.tax_amount,
        (ar.subtotal + COALESCE(sar.tax_amount, 0)) AS amount_due,
        sar.sale_account_receivable_id
    INTO
        _subtotal,
        _tax_amount,
        _amount_due,
        _target_sar_id
    FROM general_schema.account_receivable ar
    JOIN pos_schema.sale_account_receivable sar
        ON ar.account_receivable_id = sar.account_receivable_id
    WHERE ar.account_receivable_id = _account_receivable_id;

    IF _amount_due IS NULL THEN
        RAISE EXCEPTION 'Account receivable not found: %', _account_receivable_id;
    END IF;

    SELECT COALESCE(SUM(sc.amount_paid), 0) INTO _payments_total
    FROM pos_schema.sale_collection sc
    WHERE sc.sale_account_receivable_id = _target_sar_id;

    _balance := _amount_due - _payments_total;

    UPDATE general_schema.account_receivable
    SET amount_paid = _payments_total,
        updated_at  = CURRENT_TIMESTAMP
    WHERE account_receivable_id = _account_receivable_id;

    IF ABS(_balance) <= 0.01 OR _payments_total >= _amount_due THEN
        UPDATE general_schema.account_receivable
        SET is_paid    = TRUE,
            updated_at = CURRENT_TIMESTAMP
        WHERE account_receivable_id = _account_receivable_id;

        UPDATE pos_schema.sale_account_receivable
        SET account_receivable_status = 3,
            updated_at                = CURRENT_TIMESTAMP
        WHERE account_receivable_id = _account_receivable_id;

        RETURN TRUE;

    ELSIF _payments_total > 0 THEN
        UPDATE pos_schema.sale_account_receivable
        SET account_receivable_status = 2,
            updated_at                = CURRENT_TIMESTAMP
        WHERE account_receivable_id = _account_receivable_id;

        RETURN FALSE;

    ELSE
        RETURN FALSE;
    END IF;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION recalc_account_receivable_on_collection() RETURNS TRIGGER AS $$
BEGIN
    PERFORM pos_schema.check_account_receivable_completion(
        (SELECT ar.account_receivable_id
         FROM general_schema.account_receivable ar
         JOIN pos_schema.sale_account_receivable sar
             ON ar.account_receivable_id = sar.account_receivable_id
         WHERE sar.sale_account_receivable_id = NEW.sale_account_receivable_id)
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


DROP TRIGGER IF EXISTS recalc_account_receivable_on_collection_trigger ON pos_schema.sale_collection;

CREATE TRIGGER recalc_account_receivable_on_collection_trigger
AFTER INSERT OR UPDATE OF amount_paid ON pos_schema.sale_collection
FOR EACH ROW EXECUTE FUNCTION pos_schema.recalc_account_receivable_on_collection();


CREATE OR REPLACE FUNCTION auto_resolve_collection_alerts() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.account_receivable_status = 3 AND OLD.account_receivable_status IS DISTINCT FROM 3 THEN
        UPDATE pos_schema.sale_collection_alert
        SET is_resolved = TRUE,
            updated_at  = CURRENT_TIMESTAMP
        WHERE sale_account_receivable_id = NEW.sale_account_receivable_id
          AND is_resolved = FALSE;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


DROP TRIGGER IF EXISTS auto_resolve_collection_alerts_trigger ON pos_schema.sale_account_receivable;

CREATE TRIGGER auto_resolve_collection_alerts_trigger
AFTER UPDATE OF account_receivable_status ON pos_schema.sale_account_receivable
FOR EACH ROW EXECUTE FUNCTION pos_schema.auto_resolve_collection_alerts();


CREATE OR REPLACE FUNCTION generate_collection_alerts() RETURNS VOID AS $$
DECLARE
    v_config        RECORD;
    v_account       RECORD;
    v_days_until_due INTEGER;
    v_alert_type_id INTEGER;
    v_existing_id   UUID;
BEGIN
    FOR v_config IN
        SELECT tenant_id, warning_days_before_due, urgent_days_before_due
        FROM pos_schema.sale_collection_alert_config
    LOOP
        FOR v_account IN
            SELECT
                ar.account_receivable_id,
                ar.due_date,
                ar.is_paid,
                ar.amount_paid,
                ar.subtotal,
                sar.sale_account_receivable_id,
                sar.tax_amount,
                (ar.subtotal + COALESCE(sar.tax_amount, 0) - ar.amount_paid) AS balance_remaining
            FROM general_schema.account_receivable ar
            JOIN pos_schema.sale_account_receivable sar
                ON ar.account_receivable_id = sar.account_receivable_id
            WHERE ar.tenant_id = v_config.tenant_id
              AND ar.is_paid = FALSE
              AND (ar.subtotal + COALESCE(sar.tax_amount, 0) - ar.amount_paid) > 0
        LOOP
            v_days_until_due := v_account.due_date - CURRENT_DATE;

            IF v_days_until_due < 0 THEN
                v_alert_type_id := 3;
            ELSIF v_days_until_due <= v_config.urgent_days_before_due THEN
                v_alert_type_id := 2;
            ELSIF v_days_until_due <= v_config.warning_days_before_due THEN
                v_alert_type_id := 1;
            ELSE
                CONTINUE;
            END IF;

            SELECT collection_alert_id INTO v_existing_id
            FROM pos_schema.sale_collection_alert
            WHERE sale_account_receivable_id = v_account.sale_account_receivable_id
              AND collection_alert_type_id = v_alert_type_id
              AND is_resolved = FALSE
            LIMIT 1;

            IF v_existing_id IS NULL THEN
                INSERT INTO pos_schema.sale_collection_alert(
                    sale_account_receivable_id,
                    collection_alert_type_id,
                    alert_date,
                    is_resolved
                ) VALUES (
                    v_account.sale_account_receivable_id,
                    v_alert_type_id,
                    CURRENT_TIMESTAMP,
                    FALSE
                );
            END IF;
        END LOOP;
    END LOOP;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error generating collection alerts: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;


DROP FUNCTION IF EXISTS get_pending_collection_alerts(UUID);

CREATE OR REPLACE FUNCTION get_pending_collection_alerts(p_tenant_id UUID)
RETURNS TABLE(
    collection_alert_id        UUID,
    sale_account_receivable_id UUID,
    sale_id                    UUID,
    customer_name              VARCHAR,
    alert_type                 VARCHAR,
    alert_type_description     TEXT,
    due_date                   DATE,
    days_until_due             INTEGER,
    balance_remaining          NUMERIC,
    alert_date                 TIMESTAMP,
    created_at                 TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        sca.collection_alert_id,
        sar.sale_account_receivable_id,
        sar.sale_id,
        (tc.first_name || ' ' || tc.last_name)::VARCHAR AS customer_name,
        scat.collection_alert_type_name,
        scat.description,
        ar.due_date,
        (ar.due_date - CURRENT_DATE)::INTEGER AS days_until_due,
        (ar.subtotal + COALESCE(sar.tax_amount, 0) - ar.amount_paid) AS balance_remaining,
        sca.alert_date,
        sca.created_at
    FROM pos_schema.sale_collection_alert sca
    JOIN pos_schema.sale_collection_alert_type scat
        ON sca.collection_alert_type_id = scat.collection_alert_type_id
    JOIN pos_schema.sale_account_receivable sar
        ON sca.sale_account_receivable_id = sar.sale_account_receivable_id
    JOIN general_schema.account_receivable ar
        ON sar.account_receivable_id = ar.account_receivable_id
    LEFT JOIN general_schema.tenant_customer tc
        ON ar.tenant_customer_id = tc.tenant_customer_id
    WHERE ar.tenant_id = p_tenant_id
      AND sca.is_resolved = FALSE
    ORDER BY ar.due_date ASC, sca.alert_date DESC;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error fetching pending collection alerts: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION resolve_collection_alert(p_alert_id UUID) RETURNS VOID AS $$
BEGIN
    UPDATE pos_schema.sale_collection_alert
    SET is_resolved = TRUE,
        updated_at  = CURRENT_TIMESTAMP
    WHERE collection_alert_id = p_alert_id;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION initialize_collection_alert_config(
    p_tenant_id     UUID,
    p_warning_days  INTEGER DEFAULT 7,
    p_urgent_days   INTEGER DEFAULT 3,
    p_email_enabled BOOLEAN DEFAULT TRUE,
    p_sms_enabled   BOOLEAN DEFAULT FALSE
) RETURNS UUID AS $$
DECLARE
    v_config_id UUID;
BEGIN
    INSERT INTO pos_schema.sale_collection_alert_config(
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
    ON CONFLICT (tenant_id) DO UPDATE
    SET warning_days_before_due     = EXCLUDED.warning_days_before_due,
        urgent_days_before_due      = EXCLUDED.urgent_days_before_due,
        email_notifications_enabled = EXCLUDED.email_notifications_enabled,
        sms_notifications_enabled   = EXCLUDED.sms_notifications_enabled,
        updated_at                  = CURRENT_TIMESTAMP
    RETURNING collection_alert_config_id INTO v_config_id;

    RETURN v_config_id;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION get_collection_alert_stats(p_tenant_id UUID)
RETURNS TABLE(
    total_alerts        INTEGER,
    overdue_count       INTEGER,
    urgent_count        INTEGER,
    warning_count       INTEGER,
    total_amount_at_risk NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*)::INTEGER AS total_alerts,
        COUNT(*) FILTER (WHERE scat.collection_alert_type_id = 3)::INTEGER AS overdue_count,
        COUNT(*) FILTER (WHERE scat.collection_alert_type_id = 2)::INTEGER AS urgent_count,
        COUNT(*) FILTER (WHERE scat.collection_alert_type_id = 1)::INTEGER AS warning_count,
        COALESCE(SUM(ar.subtotal + COALESCE(sar.tax_amount, 0) - ar.amount_paid), 0) AS total_amount_at_risk
    FROM pos_schema.sale_collection_alert sca
    JOIN pos_schema.sale_collection_alert_type scat
        ON sca.collection_alert_type_id = scat.collection_alert_type_id
    JOIN pos_schema.sale_account_receivable sar
        ON sca.sale_account_receivable_id = sar.sale_account_receivable_id
    JOIN general_schema.account_receivable ar
        ON sar.account_receivable_id = ar.account_receivable_id
    WHERE ar.tenant_id = p_tenant_id
      AND sca.is_resolved = FALSE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error calculating collection alert stats: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;


DROP TRIGGER IF EXISTS update_sale_account_receivable_timestamp ON pos_schema.sale_account_receivable;

CREATE TRIGGER update_sale_account_receivable_timestamp
BEFORE UPDATE ON pos_schema.sale_account_receivable
FOR EACH ROW EXECUTE FUNCTION general_schema.update_timestamp();


DROP TRIGGER IF EXISTS update_sale_collection_timestamp ON pos_schema.sale_collection;

CREATE TRIGGER update_sale_collection_timestamp
BEFORE UPDATE ON pos_schema.sale_collection
FOR EACH ROW EXECUTE FUNCTION general_schema.update_timestamp();


DROP TRIGGER IF EXISTS update_sale_collection_alert_timestamp ON pos_schema.sale_collection_alert;

CREATE TRIGGER update_sale_collection_alert_timestamp
BEFORE UPDATE ON pos_schema.sale_collection_alert
FOR EACH ROW EXECUTE FUNCTION general_schema.update_timestamp();


DROP TRIGGER IF EXISTS update_sale_collection_alert_config_timestamp ON pos_schema.sale_collection_alert_config;

CREATE TRIGGER update_sale_collection_alert_config_timestamp
BEFORE UPDATE ON pos_schema.sale_collection_alert_config
FOR EACH ROW EXECUTE FUNCTION general_schema.update_timestamp();


DROP TRIGGER IF EXISTS update_account_receivable_timestamp ON general_schema.account_receivable;

CREATE TRIGGER update_account_receivable_timestamp
BEFORE UPDATE ON general_schema.account_receivable
FOR EACH ROW EXECUTE FUNCTION general_schema.update_timestamp();




-- =============================================
-- FUNCTIONS: PURCHASE
-- Source: functions/purchase/purchase_functions.sql
-- =============================================

SET SEARCH_PATH = purchase_schema;


CREATE OR REPLACE FUNCTION calculate_purchase_order_total(p_purchase_order_id uuid) returns numeric as $$
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


CREATE OR REPLACE FUNCTION create_purchase_order(p_supplier_id uuid, p_warehouse_id uuid, p_expected_delivery_date date, p_items jsonb default '[]'::jsonb, p_has_invoice BOOLEAN default true, p_payment_condition VARCHAR(10) default 'CREDIT') returns uuid as $$
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
    select s.added_by into v_tenant_id
    from purchase_schema.supplier s
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

        -- ✅ MC1: Actualizar supplier_id en product_variant si no tiene proveedor asignado
        -- Para cada product_variant que se está comprando y que no tiene supplier_id,
        -- asignar el supplier_id de esta orden de compra
        UPDATE general_schema.product_variant
        SET
            supplier_id = p_supplier_id,
            updated_at = CURRENT_TIMESTAMP
        WHERE
            tenant_id = v_tenant_id
            AND product_variant_id IN (
                SELECT (value ->> 'product_variant_id')::uuid
                FROM jsonb_array_elements(p_items)
            )
            AND supplier_id IS NULL;

        -- ✅ MC1 (Extended): Si el producto es compuesto, heredar supplier_id a componentes
        -- Para cada producto compuesto que recibió supplier_id, asignar el mismo supplier_id
        -- a todos sus componentes que no tengan proveedor asignado
        UPDATE general_schema.product_variant child
        SET
            supplier_id = p_supplier_id,
            updated_at = CURRENT_TIMESTAMP
        WHERE
            child.tenant_id = v_tenant_id
            AND child.supplier_id IS NULL
            AND child.product_variant_id IN (
                SELECT pvc.child_product_variant_id
                FROM general_schema.product_variant_composition pvc
                WHERE pvc.tenant_id = v_tenant_id
                  AND pvc.parent_product_variant_id IN (
                      SELECT (value ->> 'product_variant_id')::uuid
                      FROM jsonb_array_elements(p_items)
                  )
            );
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


CREATE OR REPLACE FUNCTION update_order_status() returns trigger as $$
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


create trigger on_order_status_update after
update of purchase_order_status_id on purchase_schema.purchase_order
for each row execute function update_order_status();


DROP FUNCTION IF EXISTS check_account_payable_completion(UUID);


CREATE OR REPLACE FUNCTION check_account_payable_completion(_account_payable_id UUID) RETURNS BOOLEAN AS $$
DECLARE
    _subtotal NUMERIC(12,3);
    _tax_amount NUMERIC(12,3);
    _amount_due NUMERIC(12,3);
    _current_amount_paid NUMERIC(12,3);
    _payments_total NUMERIC(12,3);
    _balance NUMERIC(12,3);
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

    SELECT COALESCE(SUM(sop.amount_paid), 0) INTO _payments_total
    FROM purchase_schema.purchase_order_payment sop
    WHERE sop.purchase_account_payable_id = _target_purchase_ap_id;

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


CREATE OR REPLACE FUNCTION recalc_account_payable_on_payment() returns trigger as $$
BEGIN
    perform purchase_schema.check_account_payable_completion(
        (select account_payable_id
         from purchase_schema.purchase_account_payable
         where purchase_account_payable_id = new.purchase_account_payable_id)
    );
    return new;
end;
$$ language plpgsql;


drop trigger if exists recalc_account_payable_on_payment_trigger on purchase_schema.purchase_order_payment;


create trigger recalc_account_payable_on_payment_trigger after
insert
or
update of amount_paid on purchase_schema.purchase_order_payment
for each row execute function recalc_account_payable_on_payment();


CREATE OR REPLACE FUNCTION update_invoice_paid_status() returns trigger as $$
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


create trigger update_invoice_paid_status_trigger after
update of account_payable_status on purchase_schema.purchase_account_payable
for each row execute function purchase_schema.update_invoice_paid_status();


CREATE OR REPLACE FUNCTION purchase_schema.upsert_inventory_stock(p_tenant_id UUID, p_product_variant_id UUID, p_warehouse_id UUID, p_quantity INTEGER, p_log_in_type_id INTEGER) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    v_existing_id UUID;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RETURN;
    END IF;

    SELECT inventory_id INTO v_existing_id
    FROM inventory_schema.inventory
    WHERE tenant_id = p_tenant_id
      AND product_variant_id = p_product_variant_id
      AND warehouse_id = p_warehouse_id
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
        UPDATE inventory_schema.inventory
        SET stock = stock + p_quantity,
            updated_at = CURRENT_TIMESTAMP
        WHERE inventory_id = v_existing_id;
    ELSE
        INSERT INTO inventory_schema.inventory(
            tenant_id, product_variant_id, warehouse_id, stock
        ) VALUES (
            p_tenant_id, p_product_variant_id, p_warehouse_id, p_quantity
        );
    END IF;

    IF p_log_in_type_id IS NOT NULL THEN
        INSERT INTO inventory_schema.inventory_log(
            inventory_log_type_id, warehouse_id, tenant_id,
            product_variant_id, quantity
        ) VALUES (
            p_log_in_type_id, p_warehouse_id, p_tenant_id,
            p_product_variant_id, p_quantity
        );
    END IF;
END;
$$;


CREATE OR REPLACE FUNCTION purchase_schema.apply_inventory_on_delivery(p_purchase_order_id UUID) RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    v_warehouse_id UUID;
    v_log_in_type_id INTEGER;
    v_item RECORD;
    v_component RECORD;
    v_is_composite BOOLEAN;
    v_total_qty INTEGER;
    v_target_is_branch BOOLEAN;
BEGIN
    SELECT po.warehouse_id INTO v_warehouse_id
    FROM purchase_schema.purchase_order po
    WHERE po.purchase_order_id = p_purchase_order_id;

    IF v_warehouse_id IS NULL THEN
        RAISE EXCEPTION 'apply_inventory_on_delivery: warehouse not found for PO %', p_purchase_order_id;
    END IF;

    -- Determine if the target warehouse is a branch (sales floor).
    -- Composite products (lotes) are only expanded into their components
    -- when delivered to a branch warehouse. A regular warehouse (bodega)
    -- receives the lot as a single intact unit.
    SELECT w.is_branch INTO v_target_is_branch
    FROM inventory_schema.warehouse w
    WHERE w.warehouse_id = v_warehouse_id;

    SELECT inventory_log_type_id INTO v_log_in_type_id
    FROM inventory_schema.inventory_log_type
    WHERE inventory_log_type_name = 'IN'
    LIMIT 1;

    FOR v_item IN
        SELECT poi.tenant_id, poi.product_variant_id, poi.quantity_ordered
        FROM purchase_schema.purchase_order_item poi
        WHERE poi.purchase_order_id = p_purchase_order_id
    LOOP
        SELECT pv.is_composite INTO v_is_composite
        FROM general_schema.product_variant pv
        WHERE pv.tenant_id = v_item.tenant_id
          AND pv.product_variant_id = v_item.product_variant_id;

        -- Only disaggregate (expand) the lot if the product is composite
        -- AND the destination warehouse is a branch (is_branch = true).
        -- Non-branch warehouses (bodegas) store the lot as a whole unit.
        IF v_is_composite IS TRUE AND v_target_is_branch IS TRUE THEN
            FOR v_component IN
                SELECT pvc.child_product_variant_id, pvc.quantity AS component_qty
                FROM general_schema.product_variant_composition pvc
                WHERE pvc.tenant_id = v_item.tenant_id
                  AND pvc.parent_product_variant_id = v_item.product_variant_id
            LOOP
                v_total_qty := v_item.quantity_ordered * v_component.component_qty;

                PERFORM purchase_schema.upsert_inventory_stock(
                    v_item.tenant_id,
                    v_component.child_product_variant_id,
                    v_warehouse_id,
                    v_total_qty,
                    v_log_in_type_id
                );
            END LOOP;
        ELSE
            -- Non-branch warehouse OR non-composite product: insert as-is.
            PERFORM purchase_schema.upsert_inventory_stock(
                v_item.tenant_id,
                v_item.product_variant_id,
                v_warehouse_id,
                v_item.quantity_ordered,
                v_log_in_type_id
            );
        END IF;
    END LOOP;
END;
$$;


CREATE OR REPLACE FUNCTION create_goods_receipt() returns trigger as $$
declare
    v_goods_receipt_id uuid;
    v_subtotal numeric(12,3);
    v_tax_amount numeric(12,3);
    v_item record;
BEGIN
    if new.purchase_order_status_id = 3 and old.purchase_order_status_id is distinct from 3 then
        if not exists(
            select 1
            from purchase_schema.goods_receipt
            where purchase_order_id = new.purchase_order_id
        ) then
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

        -- Push items into inventory at the destination warehouse. The
        -- 'IS DISTINCT FROM 3' guard above ensures this only runs once
        -- per real status transition.
        perform purchase_schema.apply_inventory_on_delivery(new.purchase_order_id);
    end if;

    return new;
end;
$$ language plpgsql;


drop trigger if exists create_goods_receipt_trigger on purchase_schema.purchase_order;


create trigger create_goods_receipt_trigger after
update of purchase_order_status_id on purchase_schema.purchase_order
for each row execute function purchase_schema.create_goods_receipt();


CREATE OR REPLACE FUNCTION execute_three_way_matching(p_purchase_order_id uuid, p_goods_receipt_id uuid) returns void as $$
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


CREATE OR REPLACE FUNCTION generate_payment_alerts() returns void as $$
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


CREATE OR REPLACE FUNCTION get_pending_payment_alerts(p_tenant_id uuid) returns table(payment_alert_id uuid, purchase_account_payable_id uuid, purchase_order_id uuid, supplier_name VARCHAR, invoice_number VARCHAR, alert_type VARCHAR, alert_type_description text, due_date date, days_until_due INTEGER, balance_remaining numeric, alert_date timestamp, created_at timestamp) as $$
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


CREATE OR REPLACE FUNCTION resolve_payment_alert(p_alert_id uuid) returns void as $$
BEGIN
    update purchase_schema.purchase_order_payment_alert
    set is_resolved = true,
        updated_at = current_timestamp
    where payment_alert_id = p_alert_id;
end;
$$ language plpgsql;


CREATE OR REPLACE FUNCTION auto_resolve_payment_alerts() returns trigger as $$
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


create trigger auto_resolve_payment_alerts_trigger after
update of account_payable_status on purchase_schema.purchase_account_payable
for each row execute function purchase_schema.auto_resolve_payment_alerts();


CREATE OR REPLACE FUNCTION initialize_payment_alert_config(p_tenant_id uuid, p_warning_days INTEGER default 7, p_urgent_days INTEGER default 3, p_email_enabled BOOLEAN default true, p_sms_enabled BOOLEAN default false) returns uuid as $$
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


CREATE OR REPLACE FUNCTION get_payment_alert_stats(p_tenant_id uuid) returns table(total_alerts INTEGER, overdue_count INTEGER, urgent_count INTEGER, warning_count INTEGER, total_amount_at_risk numeric) as $$
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


create trigger update_supplier_timestamp
before
update on purchase_schema.supplier
for each row execute function general_schema.update_timestamp();


drop trigger if exists update_purchase_order_timestamp on purchase_schema.purchase_order;


create trigger update_purchase_order_timestamp
before
update on purchase_schema.purchase_order
for each row execute function general_schema.update_timestamp();


drop trigger if exists update_purchase_order_item_timestamp on purchase_schema.purchase_order_item;


create trigger update_purchase_order_item_timestamp
before
update on purchase_schema.purchase_order_item
for each row execute function general_schema.update_timestamp();


drop trigger if exists update_supplier_invoice_timestamp on purchase_schema.supplier_invoice;


create trigger update_supplier_invoice_timestamp
before
update on purchase_schema.supplier_invoice
for each row execute function general_schema.update_timestamp();


drop trigger if exists update_supplier_invoice_item_timestamp on purchase_schema.supplier_invoice_item;


create trigger update_supplier_invoice_item_timestamp
before
update on purchase_schema.supplier_invoice_item
for each row execute function general_schema.update_timestamp();


drop trigger if exists update_goods_receipt_timestamp on purchase_schema.goods_receipt;


create trigger update_goods_receipt_timestamp
before
update on purchase_schema.goods_receipt
for each row execute function general_schema.update_timestamp();


drop trigger if exists update_goods_receipt_item_timestamp on purchase_schema.goods_receipt_item;


create trigger update_goods_receipt_item_timestamp
before
update on purchase_schema.goods_receipt_item
for each row execute function general_schema.update_timestamp();


drop trigger if exists update_account_payable_timestamp on purchase_schema.purchase_account_payable;


create trigger update_account_payable_timestamp
before
update on purchase_schema.purchase_account_payable
for each row execute function general_schema.update_timestamp();


drop trigger if exists update_purchase_order_payment_timestamp on purchase_schema.purchase_order_payment;


create trigger update_purchase_order_payment_timestamp
before
update on purchase_schema.purchase_order_payment
for each row execute function general_schema.update_timestamp();


drop trigger if exists update_purchase_order_payment_alert_timestamp on purchase_schema.purchase_order_payment_alert;


create trigger update_purchase_order_payment_alert_timestamp
before
update on purchase_schema.purchase_order_payment_alert
for each row execute function general_schema.update_timestamp();


drop trigger if exists update_purchase_order_payment_alert_config_timestamp on purchase_schema.purchase_order_payment_alert_config;


create trigger update_purchase_order_payment_alert_config_timestamp
before
update on purchase_schema.purchase_order_payment_alert_config
for each row execute function general_schema.update_timestamp();


drop trigger if exists update_three_way_matching_timestamp on purchase_schema.three_way_matching;


create trigger update_three_way_matching_timestamp
before
update on purchase_schema.three_way_matching
for each row execute function general_schema.update_timestamp();



-- =============================================
-- FUNCTIONS: HR
-- Source: functions/hr/hr_functions.sql
-- =============================================
SET SEARCH_PATH = hr_schema;

CREATE OR REPLACE FUNCTION hr_schema.create_new_employee(
    p_start_date DATE,
    p_end_date DATE,
    p_hours INTEGER,
    p_base_salary NUMERIC,
    p_duties TEXT,
    p_turn_type INTEGER,
    p_turn_id INTEGER,
    p_user_id UUID,
    p_tenant_id UUID,
    p_first_name CHARACTER VARYING,
    p_last_name CHARACTER VARYING,
    p_doc_number CHARACTER VARYING,
    p_phone CHARACTER VARYING,
    p_email CHARACTER VARYING,
    p_payment_schedule_id INTEGER,
    p_branch_id UUID,
    p_identification_type_id INTEGER DEFAULT 1,
    p_duties_type_id INTEGER DEFAULT NULL
  )
 RETURNS UUID
 LANGUAGE plpgsql
AS $function$

DECLARE
  v_new_contract_id UUID;
  v_new_employee_id UUID;
BEGIN

  IF NOT EXISTS (SELECT 1 FROM hr_schema.payment_schedule WHERE payment_schedule_id = p_payment_schedule_id) THEN
    RAISE EXCEPTION 'Integrity error: payment_schedule_id (payment_schedule_id: %) doesnt exists', p_payment_schedule_id;
  END IF;

  INSERT INTO hr_schema.contract (tenant_id, start_date, end_date, hours, base_salary, duties, turn_type, turn_id, duties_type_id)
  VALUES (p_tenant_id, p_start_date, p_end_date, p_hours, p_base_salary, p_duties, p_turn_type, p_turn_id, p_duties_type_id)
  RETURNING contract_id INTO v_new_contract_id;

  v_new_employee_id := gen_random_uuid();

  INSERT INTO hr_schema.employee (
    employee_id, user_id, first_name, last_name, doc_number,
    identification_type_id, phone, email, contract_id,
    payment_schedule_id, tenant_id, branch_id
  )
  VALUES (
    v_new_employee_id,
    p_user_id,
    p_first_name,
    p_last_name,
    p_doc_number,
    p_identification_type_id,
    p_phone,
    p_email,
    v_new_contract_id,
    p_payment_schedule_id,
    p_tenant_id,
    p_branch_id
  );

  RETURN v_new_employee_id;

EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'Data Error: Document Number (%) or Email already exists.', p_doc_number;
  WHEN foreign_key_violation THEN
    RAISE EXCEPTION 'Integrity Error: Insert failed due to a non-existent FOREIGN KEY (payment_schedule_id, identification_type_id, or duties_type_id).';
  WHEN others THEN
    RAISE EXCEPTION 'Error creating employee or contract: %', SQLERRM;
END;
$function$;

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
    SELECT status_id INTO v_current_status_id
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
      status_id = v_completed_status_id
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
		AND p.status_id = v_status_completed_id;

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
        	INNER JOIN hr_schema.paysheet_status ps ON p.status_id = ps.status_id
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

CREATE OR REPLACE FUNCTION hr_schema.close_suspention()
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  UPDATE hr_schema.suspention
  SET is_active = false
  WHERE suspention_end IS NOT NULL
    AND suspention_end <= NOW()
    AND is_active = TRUE
  RETURNING 1 INTO v_count;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION hr_schema.close_suspention_trigger()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  
  IF NEW.suspention_end IS NOT NULL AND NEW.suspention_end <= NOW() THEN
    NEW.is_active := FALSE;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_close_suspention_on_write
BEFORE INSERT OR UPDATE ON hr_schema.suspention
FOR EACH ROW
EXECUTE FUNCTION hr_schema.close_suspention_trigger();



-- =============================================
-- FUNCTIONS: ACCOUNTING
-- Source: functions/accounting/accounting_functions.sql
-- =============================================
SET SEARCH_PATH TO accounting_schema;

-- ============================================================
-- validate_journal_balance
-- Validates that a journal entry's debit and credit totals match.
-- Returns TRUE if balanced, raises exception if not.
-- ============================================================
CREATE OR REPLACE FUNCTION validate_journal_balance(_entry_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    _total_debit NUMERIC(14,4);
    _total_credit NUMERIC(14,4);
    _line_count INT;
BEGIN
    SELECT count(*),
           coalesce(sum(debit_amount), 0),
           coalesce(sum(credit_amount), 0)
    INTO _line_count, _total_debit, _total_credit
    FROM accounting_schema.journal_entry_line
    WHERE entry_id = _entry_id;

    IF _line_count = 0 THEN
        RAISE EXCEPTION 'Journal entry % has no lines', _entry_id;
    END IF;

    IF _line_count < 2 THEN
        RAISE EXCEPTION 'Journal entry % must have at least 2 lines (debit and credit)', _entry_id;
    END IF;

    IF _total_debit != _total_credit THEN
        RAISE EXCEPTION 'Journal entry % is unbalanced: debits=% credits=%',
            _entry_id, _total_debit, _total_credit;
    END IF;

    -- Update denormalized totals on the journal entry
    UPDATE accounting_schema.journal_entry
    SET total_debit = _total_debit,
        total_credit = _total_credit,
        updated_at = CURRENT_TIMESTAMP
    WHERE entry_id = _entry_id;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- confirm_journal_entry
-- Validates balance and transitions entry from Borrador → Confirmado
-- ============================================================
CREATE OR REPLACE FUNCTION confirm_journal_entry(_entry_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    _current_status INT;
    _status_borrador INT;
    _status_confirmado INT;
BEGIN
    SELECT status_id INTO _status_borrador
    FROM accounting_schema.journal_entry_status
    WHERE status_name = 'Borrador';

    SELECT status_id INTO _status_confirmado
    FROM accounting_schema.journal_entry_status
    WHERE status_name = 'Confirmado';

    SELECT status_id INTO _current_status
    FROM accounting_schema.journal_entry
    WHERE entry_id = _entry_id;

    IF _current_status IS NULL THEN
        RAISE EXCEPTION 'Journal entry % not found', _entry_id;
    END IF;

    IF _current_status != _status_borrador THEN
        RAISE EXCEPTION 'Journal entry % is not in Borrador status (current status_id=%)',
            _entry_id, _current_status;
    END IF;

    -- Validate balance before confirming
    PERFORM accounting_schema.validate_journal_balance(_entry_id);

    UPDATE accounting_schema.journal_entry
    SET status_id = _status_confirmado,
        updated_at = CURRENT_TIMESTAMP
    WHERE entry_id = _entry_id;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- void_journal_entry
-- Transitions entry from Confirmado → Anulado.
-- Creates a reversal entry automatically.
-- ============================================================
CREATE OR REPLACE FUNCTION void_journal_entry(_entry_id UUID, _voided_by UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    _current_status INT;
    _status_confirmado INT;
    _status_anulado INT;
    _entry RECORD;
    _reversal_id UUID;
    _source_type_adj INT;
BEGIN
    SELECT status_id INTO _status_confirmado
    FROM accounting_schema.journal_entry_status
    WHERE status_name = 'Confirmado';

    SELECT status_id INTO _status_anulado
    FROM accounting_schema.journal_entry_status
    WHERE status_name = 'Anulado';

    SELECT * INTO _entry
    FROM accounting_schema.journal_entry
    WHERE entry_id = _entry_id;

    IF _entry IS NULL THEN
        RAISE EXCEPTION 'Journal entry % not found', _entry_id;
    END IF;

    IF _entry.status_id != _status_confirmado THEN
        RAISE EXCEPTION 'Only confirmed entries can be voided (entry % has status_id=%)',
            _entry_id, _entry.status_id;
    END IF;

    -- Get ADJUSTMENT source type for the reversal
    SELECT source_type_id INTO _source_type_adj
    FROM accounting_schema.source_type
    WHERE source_name = 'ADJUSTMENT';

    -- Mark original as voided
    UPDATE accounting_schema.journal_entry
    SET status_id = _status_anulado,
        updated_at = CURRENT_TIMESTAMP
    WHERE entry_id = _entry_id;

    -- Create reversal entry (swap debits and credits)
    INSERT INTO accounting_schema.journal_entry(
        tenant_id, source_type_id, source_id, entry_date,
        description, status_id, total_debit, total_credit, created_by
    ) VALUES (
        _entry.tenant_id, _source_type_adj, _entry_id, CURRENT_DATE,
        'Reversión de asiento ' || _entry.entry_number,
        _status_confirmado, _entry.total_debit, _entry.total_credit, _voided_by
    ) RETURNING entry_id INTO _reversal_id;

    -- Copy lines with swapped debit/credit
    INSERT INTO accounting_schema.journal_entry_line(
        entry_id, account_id, cost_center_id, debit_amount, credit_amount, description
    )
    SELECT _reversal_id, account_id, cost_center_id,
           credit_amount AS debit_amount,
           debit_amount AS credit_amount,
           'Reversión: ' || coalesce(description, '')
    FROM accounting_schema.journal_entry_line
    WHERE entry_id = _entry_id;

    RETURN _reversal_id;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- provision_tenant_accounts
-- Copies the chart of accounts template to a specific tenant.
-- Called during tenant onboarding.
-- ============================================================
CREATE OR REPLACE FUNCTION provision_tenant_accounts(_tenant_id UUID)
RETURNS INT AS $$
DECLARE
    _template RECORD;
    _parent_id UUID;
    _inserted INT := 0;
    _account_map JSONB := '{}';
BEGIN
    -- Check tenant exists
    IF NOT EXISTS (SELECT 1 FROM general_schema.tenant WHERE tenant_id = _tenant_id) THEN
        RAISE EXCEPTION 'Tenant % not found', _tenant_id;
    END IF;

    -- Check if tenant already has accounts
    IF EXISTS (SELECT 1 FROM accounting_schema.chart_of_accounts WHERE tenant_id = _tenant_id LIMIT 1) THEN
        RAISE NOTICE 'Tenant % already has chart of accounts provisioned', _tenant_id;
        RETURN 0;
    END IF;

    -- Insert accounts in order (parents first) using the template
    FOR _template IN
        SELECT * FROM accounting_schema.chart_of_accounts_template
        ORDER BY account_code
    LOOP
        -- Resolve parent
        _parent_id := NULL;
        IF _template.parent_code IS NOT NULL THEN
            _parent_id := (_account_map ->> _template.parent_code)::UUID;
        END IF;

        INSERT INTO accounting_schema.chart_of_accounts(
            tenant_id, account_code, account_name, account_type_id,
            parent_account_id, is_active, is_system, allows_transactions
        ) VALUES (
            _tenant_id, _template.account_code, _template.account_name, _template.account_type_id,
            _parent_id, TRUE, TRUE, _template.allows_transactions
        ) RETURNING account_id INTO _parent_id;

        -- Store in map for child resolution
        _account_map := _account_map || jsonb_build_object(_template.account_code, _parent_id::TEXT);
        _inserted := _inserted + 1;
    END LOOP;

    RAISE NOTICE 'Provisioned % accounts for tenant %', _inserted, _tenant_id;
    RETURN _inserted;
END;
$$ LANGUAGE plpgsql;



-- =============================================
-- SEED: REGIONS
-- Source: seeds/catalog/general/001-insert-regions.sql
-- =============================================
SET SEARCH_PATH TO general_schema;

INSERT INTO general_schema.region(region_name, country_code) VALUES
    ('Costa Rica',    '+506'),
    ('Panama',        '+507'),
    ('United States', '+1'),
    ('United Kingdom','+44'),
    ('Japan',         '+81'),
    ('Spain',         '+34')
ON CONFLICT (region_name) DO UPDATE SET country_code = EXCLUDED.country_code;



-- =============================================
-- SEED: DOCUMENT TYPES
-- Source: seeds/catalog/general/002-insert-document-types.sql
-- =============================================
SET SEARCH_PATH TO general_schema;

INSERT INTO general_schema.identification_type(type_name, description, ident_code) VALUES
    ('Cedula Fisica', 'Tarjeta de identificacion en fisico', '01'),
    ('Cedula Juridica', 'Numero de identificacion asignado por el Registro Nacional', '02'),
    ('DIMEX', 'Documento de Identidad Migratorio para Extranjeros', '03'),
    ('NITE', 'Numero de Identificacion Tributaria Especial', '04'),
    ('Extranjero No Domiciliado', 'Cliente o proveedor sin residencia en el pais', '05'),
    ('No Contribuyente', 'Persona no inscrita en el DGT', '06')
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

-- Tasas IVA Costa Rica según DGT-R-48-2016 (CodigoTarifa v4.4)
-- rate_code = CodigoTarifa requerido por Hacienda en <Impuesto><CodigoTarifa>
INSERT INTO general_schema.tax_rate (region, region_id, rate_percentage, rate_code, rate_name) VALUES
('CR Exento',   (SELECT region_id FROM general_schema.region WHERE region_name = 'Costa Rica'), 0.00,  '01', 'Exento'),
('CR IVA 1%',   (SELECT region_id FROM general_schema.region WHERE region_name = 'Costa Rica'), 1.00,  '05', 'IVA 1%'),
('CR IVA 2%',   (SELECT region_id FROM general_schema.region WHERE region_name = 'Costa Rica'), 2.00,  '06', 'IVA 2%'),
('CR IVA 4%',   (SELECT region_id FROM general_schema.region WHERE region_name = 'Costa Rica'), 4.00,  '07', 'IVA 4% - Servicios de Salud'),
('CR Standard', (SELECT region_id FROM general_schema.region WHERE region_name = 'Costa Rica'), 13.00, '08', 'IVA General 13%'),
('PA Standard', (SELECT region_id FROM general_schema.region WHERE region_name = 'Panama'),     7.00,  NULL, NULL),
('US Federal',  (SELECT region_id FROM general_schema.region WHERE region_name = 'United States'), 10.00, NULL, NULL),
('EU Standard', NULL,                                                                            20.00, NULL, NULL),
('UK Standard', (SELECT region_id FROM general_schema.region WHERE region_name = 'United Kingdom'), 20.00, NULL, NULL),
('JP Standard', (SELECT region_id FROM general_schema.region WHERE region_name = 'Japan'),      8.00,  NULL, NULL)
ON CONFLICT (region, rate_percentage) DO UPDATE
  SET rate_code = EXCLUDED.rate_code,
      rate_name = EXCLUDED.rate_name;



-- =============================================
-- SEED: SUBSCRIPTION TYPES
-- Source: seeds/catalog/general/008-insert-subscription-types.sql
-- =============================================
SET search_path TO general_schema;

INSERT INTO general_schema.subscription_type (subscription_type_name, subscription_type_detail, duration_months, subscription_type_cost) VALUES
('Plan Completo', 'Acceso total a la plataforma', 1, 99.99)
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
('credit', 'Payment made through a credit account'),
('bank_transfer', 'Payment made through bank transfer')
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
-- SEED: BRANCH LOCATIONS
-- Source: seeds/catalog/general/012-insert-branch-locations.sql
-- =============================================
-- ======================================================
-- SEED: general/012-insert-branch-locations.sql
-- ======================================================
-- Descripción: Llena la tabla territorio_catalog con TODOS los territorios
--              de Costa Rica según División del Territorio 2007
--              (Provincia, Cantón y Distrito)
-- Fuente: División del Territorio de Costa Rica Por: Provincia, Cantón y Distrito
--         Según: Código 2007
-- ======================================================

BEGIN;

-- Crear tabla de catálogo de territorios si no existe
CREATE TABLE IF NOT EXISTS general_schema.territorio_catalog (
    territorio_id SERIAL PRIMARY KEY,
    codigo VARCHAR(5) UNIQUE NOT NULL,  -- PPCDD (Provincia, Cantón, Distrito)
    provincia VARCHAR(1) NOT NULL,      -- 1-7
    canton VARCHAR(2) NOT NULL,         -- 01-XX
    distrito VARCHAR(2) NOT NULL,       -- 01-XX
    provincia_nombre VARCHAR(100) NOT NULL,
    canton_nombre VARCHAR(100) NOT NULL,
    distrito_nombre VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Crear índices para búsquedas rápidas
CREATE INDEX IF NOT EXISTS idx_territorio_codigo ON general_schema.territorio_catalog(codigo);
CREATE INDEX IF NOT EXISTS idx_territorio_provincia ON general_schema.territorio_catalog(provincia);
CREATE INDEX IF NOT EXISTS idx_territorio_canton ON general_schema.territorio_catalog(canton);

-- Insertar TODOS los territorios de Costa Rica
INSERT INTO general_schema.territorio_catalog (codigo, provincia, canton, distrito, provincia_nombre, canton_nombre, distrito_nombre)
VALUES
-- PROVINCIA 1: SAN JOSE
-- CANTON 101: SAN JOSE
('10101', '1', '01', '01', 'San José', 'San José', 'Carmen'),
('10102', '1', '01', '02', 'San José', 'San José', 'Merced'),
('10103', '1', '01', '03', 'San José', 'San José', 'Hospital'),
('10104', '1', '01', '04', 'San José', 'San José', 'Catedral'),
('10105', '1', '01', '05', 'San José', 'San José', 'Zapote'),
('10106', '1', '01', '06', 'San José', 'San José', 'San Francisco de Dos Ríos'),
('10107', '1', '01', '07', 'San José', 'San José', 'Uruca'),
('10108', '1', '01', '08', 'San José', 'San José', 'Mata Redonda'),
('10109', '1', '01', '09', 'San José', 'San José', 'Pavas'),
('10110', '1', '01', '10', 'San José', 'San José', 'Hatillo'),
('10111', '1', '01', '11', 'San José', 'San José', 'San Sebastián'),
-- CANTON 102: ESCAZU
('10201', '1', '02', '01', 'San José', 'Escazú', 'Escazú'),
('10202', '1', '02', '02', 'San José', 'Escazú', 'San Antonio'),
('10203', '1', '02', '03', 'San José', 'Escazú', 'San Rafael'),
-- CANTON 103: DESAMPARADOS
('10301', '1', '03', '01', 'San José', 'Desamparados', 'Desamparados'),
('10302', '1', '03', '02', 'San José', 'Desamparados', 'San Miguel'),
('10303', '1', '03', '03', 'San José', 'Desamparados', 'San Juan de Dios'),
('10304', '1', '03', '04', 'San José', 'Desamparados', 'San Rafael Arriba'),
('10305', '1', '03', '05', 'San José', 'Desamparados', 'San Antonio'),
('10306', '1', '03', '06', 'San José', 'Desamparados', 'Frailes'),
('10307', '1', '03', '07', 'San José', 'Desamparados', 'Patarrá'),
('10308', '1', '03', '08', 'San José', 'Desamparados', 'San Cristóbal'),
('10309', '1', '03', '09', 'San José', 'Desamparados', 'Rosario'),
('10310', '1', '03', '10', 'San José', 'Desamparados', 'Damas'),
('10311', '1', '03', '11', 'San José', 'Desamparados', 'San Rafael Abajo'),
('10312', '1', '03', '12', 'San José', 'Desamparados', 'Gravilias'),
('10313', '1', '03', '13', 'San José', 'Desamparados', 'Los Guido'),
-- CANTON 104: PURISCAL
('10401', '1', '04', '01', 'San José', 'Puriscal', 'Santiago'),
('10402', '1', '04', '02', 'San José', 'Puriscal', 'Mercedes Sur'),
('10403', '1', '04', '03', 'San José', 'Puriscal', 'Barbacoas'),
('10404', '1', '04', '04', 'San José', 'Puriscal', 'Grifo Alto'),
('10405', '1', '04', '05', 'San José', 'Puriscal', 'San Rafael'),
('10406', '1', '04', '06', 'San José', 'Puriscal', 'Candelaria'),
('10407', '1', '04', '07', 'San José', 'Puriscal', 'Desamparaditos'),
('10408', '1', '04', '08', 'San José', 'Puriscal', 'San Antonio'),
('10409', '1', '04', '09', 'San José', 'Puriscal', 'Chires'),
-- CANTON 105: TARRAZU
('10501', '1', '05', '01', 'San José', 'Tarrazú', 'San Marcos'),
('10502', '1', '05', '02', 'San José', 'Tarrazú', 'San Lorenzo'),
('10503', '1', '05', '03', 'San José', 'Tarrazú', 'San Carlos'),
-- CANTON 106: ASERRI
('10601', '1', '06', '01', 'San José', 'Aserrí', 'Aserrí'),
('10602', '1', '06', '02', 'San José', 'Aserrí', 'Tarbaca o Praga'),
('10603', '1', '06', '03', 'San José', 'Aserrí', 'Vuelta de Jorco'),
('10604', '1', '06', '04', 'San José', 'Aserrí', 'San Gabriel'),
('10605', '1', '06', '05', 'San José', 'Aserrí', 'La Legua'),
('10606', '1', '06', '06', 'San José', 'Aserrí', 'Monterrey'),
('10607', '1', '06', '07', 'San José', 'Aserrí', 'Salitrillos'),
-- CANTON 107: MORA
('10701', '1', '07', '01', 'San José', 'Mora', 'Colón'),
('10702', '1', '07', '02', 'San José', 'Mora', 'Guayabo'),
('10703', '1', '07', '03', 'San José', 'Mora', 'Tabarcia'),
('10704', '1', '07', '04', 'San José', 'Mora', 'Piedras Negras'),
('10705', '1', '07', '05', 'San José', 'Mora', 'Picagres'),
-- CANTON 108: GOICOECHEA
('10801', '1', '08', '01', 'San José', 'Goicoechea', 'Guadalupe'),
('10802', '1', '08', '02', 'San José', 'Goicoechea', 'San Francisco'),
('10803', '1', '08', '03', 'San José', 'Goicoechea', 'Calle Blancos'),
('10804', '1', '08', '04', 'San José', 'Goicoechea', 'Mata de Plátano'),
('10805', '1', '08', '05', 'San José', 'Goicoechea', 'Ipís'),
('10806', '1', '08', '06', 'San José', 'Goicoechea', 'Rancho Redondo'),
('10807', '1', '08', '07', 'San José', 'Goicoechea', 'Purral'),
-- CANTON 109: SANTA ANA
('10901', '1', '09', '01', 'San José', 'Santa Ana', 'Santa Ana'),
('10902', '1', '09', '02', 'San José', 'Santa Ana', 'Salitral'),
('10903', '1', '09', '03', 'San José', 'Santa Ana', 'Pozos o Concepción'),
('10904', '1', '09', '04', 'San José', 'Santa Ana', 'Uruca o San Joaquín'),
('10905', '1', '09', '05', 'San José', 'Santa Ana', 'Piedades'),
('10906', '1', '09', '06', 'San José', 'Santa Ana', 'Brasil'),
-- CANTON 110: ALAJUELITA
('11001', '1', '10', '01', 'San José', 'Alajuelita', 'Alajuelita'),
('11002', '1', '10', '02', 'San José', 'Alajuelita', 'San Josecito'),
('11003', '1', '10', '03', 'San José', 'Alajuelita', 'San Antonio'),
('11004', '1', '10', '04', 'San José', 'Alajuelita', 'Concepción'),
('11005', '1', '10', '05', 'San José', 'Alajuelita', 'San Felipe'),
-- CANTON 111: CORONADO
('11101', '1', '11', '01', 'San José', 'Coronado', 'San Isidro'),
('11102', '1', '11', '02', 'San José', 'Coronado', 'San Rafael'),
('11103', '1', '11', '03', 'San José', 'Coronado', 'Dulce Nombre o Jesús'),
('11104', '1', '11', '04', 'San José', 'Coronado', 'Patalillo'),
('11105', '1', '11', '05', 'San José', 'Coronado', 'Cascajal'),
-- CANTON 112: ACOSTA
('11201', '1', '12', '01', 'San José', 'Acosta', 'San Ignacio'),
('11202', '1', '12', '02', 'San José', 'Acosta', 'Guaitil'),
('11203', '1', '12', '03', 'San José', 'Acosta', 'Palmichal'),
('11204', '1', '12', '04', 'San José', 'Acosta', 'Cangrejal'),
('11205', '1', '12', '05', 'San José', 'Acosta', 'Sabanillas'),
-- CANTON 113: TIBAS
('11301', '1', '13', '01', 'San José', 'Tibás', 'San Juan'),
('11302', '1', '13', '02', 'San José', 'Tibás', 'Cinco Esquinas'),
('11303', '1', '13', '03', 'San José', 'Tibás', 'Anselmo Llorente'),
('11304', '1', '13', '04', 'San José', 'Tibás', 'León XIII'),
('11305', '1', '13', '05', 'San José', 'Tibás', 'Colima'),
-- CANTON 114: MORAVIA
('11401', '1', '14', '01', 'San José', 'Moravia', 'San Vicente'),
('11402', '1', '14', '02', 'San José', 'Moravia', 'San Jerónimo'),
('11403', '1', '14', '03', 'San José', 'Moravia', 'La Trinidad'),
-- CANTON 115: MONTES DE OCA
('11501', '1', '15', '01', 'San José', 'Montes de Oca', 'San Pedro'),
('11502', '1', '15', '02', 'San José', 'Montes de Oca', 'Sabanilla'),
('11503', '1', '15', '03', 'San José', 'Montes de Oca', 'Mercedes o Betania'),
('11504', '1', '15', '04', 'San José', 'Montes de Oca', 'San Rafael'),
-- CANTON 116: TURRUBARES
('11601', '1', '16', '01', 'San José', 'Turrubares', 'San Pablo'),
('11602', '1', '16', '02', 'San José', 'Turrubares', 'San Pedro'),
('11603', '1', '16', '03', 'San José', 'Turrubares', 'San Juan de Mata'),
('11604', '1', '16', '04', 'San José', 'Turrubares', 'San Luis'),
('11605', '1', '16', '05', 'San José', 'Turrubares', 'Carara'),
-- CANTON 117: DOTA
('11701', '1', '17', '01', 'San José', 'Dota', 'Santa María'),
('11702', '1', '17', '02', 'San José', 'Dota', 'Jardín'),
('11703', '1', '17', '03', 'San José', 'Dota', 'Copey'),
-- CANTON 118: CURRIDABAT
('11801', '1', '18', '01', 'San José', 'Curridabat', 'Curridabat'),
('11802', '1', '18', '02', 'San José', 'Curridabat', 'Granadilla'),
('11803', '1', '18', '03', 'San José', 'Curridabat', 'Sánchez'),
('11804', '1', '18', '04', 'San José', 'Curridabat', 'Tirrases'),
-- CANTON 119: PEREZ ZELEDON
('11901', '1', '19', '01', 'San José', 'Pérez Zeledón', 'San Isidro'),
('11902', '1', '19', '02', 'San José', 'Pérez Zeledón', 'General'),
('11903', '1', '19', '03', 'San José', 'Pérez Zeledón', 'Daniel Flores'),
('11904', '1', '19', '04', 'San José', 'Pérez Zeledón', 'Rivas'),
('11905', '1', '19', '05', 'San José', 'Pérez Zeledón', 'San Pedro'),
('11906', '1', '19', '06', 'San José', 'Pérez Zeledón', 'Platanares'),
('11907', '1', '19', '07', 'San José', 'Pérez Zeledón', 'Pejibaye'),
('11908', '1', '19', '08', 'San José', 'Pérez Zeledón', 'Cajón o Carmen'),
('11909', '1', '19', '09', 'San José', 'Pérez Zeledón', 'Barú'),
('11910', '1', '19', '10', 'San José', 'Pérez Zeledón', 'Río Nuevo'),
('11911', '1', '19', '11', 'San José', 'Pérez Zeledón', 'Páramo'),
-- CANTON 120: LEON CORTES
('12001', '1', '20', '01', 'San José', 'León Cortés', 'San Pablo'),
('12002', '1', '20', '02', 'San José', 'León Cortés', 'San Andrés'),
('12003', '1', '20', '03', 'San José', 'León Cortés', 'Llano Bonito'),
('12004', '1', '20', '04', 'San José', 'León Cortés', 'San Isidro'),
('12005', '1', '20', '05', 'San José', 'León Cortés', 'Santa Cruz'),
('12006', '1', '20', '06', 'San José', 'León Cortés', 'San Antonio'),

-- PROVINCIA 2: ALAJUELA
-- CANTON 201: ALAJUELA
('20101', '2', '01', '01', 'Alajuela', 'Alajuela', 'Alajuela'),
('20102', '2', '01', '02', 'Alajuela', 'Alajuela', 'San José'),
('20103', '2', '01', '03', 'Alajuela', 'Alajuela', 'Carrizal'),
('20104', '2', '01', '04', 'Alajuela', 'Alajuela', 'San Antonio'),
('20105', '2', '01', '05', 'Alajuela', 'Alajuela', 'Guácima'),
('20106', '2', '01', '06', 'Alajuela', 'Alajuela', 'San Isidro'),
('20107', '2', '01', '07', 'Alajuela', 'Alajuela', 'Sabanilla'),
('20108', '2', '01', '08', 'Alajuela', 'Alajuela', 'San Rafael'),
('20109', '2', '01', '09', 'Alajuela', 'Alajuela', 'Río Segundo'),
('20110', '2', '01', '10', 'Alajuela', 'Alajuela', 'Desamparados'),
('20111', '2', '01', '11', 'Alajuela', 'Alajuela', 'Turrucares'),
('20112', '2', '01', '12', 'Alajuela', 'Alajuela', 'Tambor'),
('20113', '2', '01', '13', 'Alajuela', 'Alajuela', 'La Garita'),
('20114', '2', '01', '14', 'Alajuela', 'Alajuela', 'Sarapiquí'),
-- CANTON 202: SAN RAMON
('20201', '2', '02', '01', 'Alajuela', 'San Ramón', 'San Ramón'),
('20202', '2', '02', '02', 'Alajuela', 'San Ramón', 'Santiago'),
('20203', '2', '02', '03', 'Alajuela', 'San Ramón', 'San Juan'),
('20204', '2', '02', '04', 'Alajuela', 'San Ramón', 'Piedades Norte'),
('20205', '2', '02', '05', 'Alajuela', 'San Ramón', 'Piedades Sur'),
('20206', '2', '02', '06', 'Alajuela', 'San Ramón', 'San Rafael'),
('20207', '2', '02', '07', 'Alajuela', 'San Ramón', 'San Isidro'),
('20208', '2', '02', '08', 'Alajuela', 'San Ramón', 'Ángeles'),
('20209', '2', '02', '09', 'Alajuela', 'San Ramón', 'Alfaro'),
('20210', '2', '02', '10', 'Alajuela', 'San Ramón', 'Volio'),
('20211', '2', '02', '11', 'Alajuela', 'San Ramón', 'Concepción'),
('20212', '2', '02', '12', 'Alajuela', 'San Ramón', 'Zapotal'),
('20213', '2', '02', '13', 'Alajuela', 'San Ramón', 'San Isidro de Peñas Blancas'),
-- CANTON 203: GRECIA
('20301', '2', '03', '01', 'Alajuela', 'Grecia', 'Grecia'),
('20302', '2', '03', '02', 'Alajuela', 'Grecia', 'San Isidro'),
('20303', '2', '03', '03', 'Alajuela', 'Grecia', 'San José'),
('20304', '2', '03', '04', 'Alajuela', 'Grecia', 'San Roque'),
('20305', '2', '03', '05', 'Alajuela', 'Grecia', 'Tácares'),
('20306', '2', '03', '06', 'Alajuela', 'Grecia', 'Río Cuarto'),
('20307', '2', '03', '07', 'Alajuela', 'Grecia', 'Puente Piedra'),
('20308', '2', '03', '08', 'Alajuela', 'Grecia', 'Bolívar'),
-- CANTON 204: SAN MATEO
('20401', '2', '04', '01', 'Alajuela', 'San Mateo', 'San Mateo'),
('20402', '2', '04', '02', 'Alajuela', 'San Mateo', 'Desmonte'),
('20403', '2', '04', '03', 'Alajuela', 'San Mateo', 'Jesús María'),
-- CANTON 205: ATENAS
('20501', '2', '05', '01', 'Alajuela', 'Atenas', 'Atenas'),
('20502', '2', '05', '02', 'Alajuela', 'Atenas', 'Jesús'),
('20503', '2', '05', '03', 'Alajuela', 'Atenas', 'Mercedes'),
('20504', '2', '05', '04', 'Alajuela', 'Atenas', 'San Isidro'),
('20505', '2', '05', '05', 'Alajuela', 'Atenas', 'Concepción'),
('20506', '2', '05', '06', 'Alajuela', 'Atenas', 'San José'),
('20507', '2', '05', '07', 'Alajuela', 'Atenas', 'Santa Eulalia'),
('20508', '2', '05', '08', 'Alajuela', 'Atenas', 'Escobal'),
-- CANTON 206: NARANJO
('20601', '2', '06', '01', 'Alajuela', 'Naranjo', 'Naranjo'),
('20602', '2', '06', '02', 'Alajuela', 'Naranjo', 'San Miguel'),
('20603', '2', '06', '03', 'Alajuela', 'Naranjo', 'San José'),
('20604', '2', '06', '04', 'Alajuela', 'Naranjo', 'Cirrí Sur'),
('20605', '2', '06', '05', 'Alajuela', 'Naranjo', 'San Jerónimo'),
('20606', '2', '06', '06', 'Alajuela', 'Naranjo', 'San Juan'),
('20607', '2', '06', '07', 'Alajuela', 'Naranjo', 'Rosario'),
-- CANTON 207: PALMARES
('20701', '2', '07', '01', 'Alajuela', 'Palmares', 'Palmares'),
('20702', '2', '07', '02', 'Alajuela', 'Palmares', 'Zaragoza'),
('20703', '2', '07', '03', 'Alajuela', 'Palmares', 'Buenos Aires'),
('20704', '2', '07', '04', 'Alajuela', 'Palmares', 'Santiago'),
('20705', '2', '07', '05', 'Alajuela', 'Palmares', 'Candelaria'),
('20706', '2', '07', '06', 'Alajuela', 'Palmares', 'Esquipulas'),
('20707', '2', '07', '07', 'Alajuela', 'Palmares', 'La Granja'),
-- CANTON 208: POAS
('20801', '2', '08', '01', 'Alajuela', 'Poás', 'San Pedro'),
('20802', '2', '08', '02', 'Alajuela', 'Poás', 'San Juan'),
('20803', '2', '08', '03', 'Alajuela', 'Poás', 'San Rafael'),
('20804', '2', '08', '04', 'Alajuela', 'Poás', 'Carrillos'),
('20805', '2', '08', '05', 'Alajuela', 'Poás', 'Sabana Redonda'),
-- CANTON 209: OROTINA
('20901', '2', '09', '01', 'Alajuela', 'Orotina', 'Orotina'),
('20902', '2', '09', '02', 'Alajuela', 'Orotina', 'Mastate'),
('20903', '2', '09', '03', 'Alajuela', 'Orotina', 'Hacienda Vieja'),
('20904', '2', '09', '04', 'Alajuela', 'Orotina', 'Coyolar'),
('20905', '2', '09', '05', 'Alajuela', 'Orotina', 'Ceiba'),
-- CANTON 210: SAN CARLOS
('21001', '2', '10', '01', 'Alajuela', 'San Carlos', 'Quesada'),
('21002', '2', '10', '02', 'Alajuela', 'San Carlos', 'Florencia'),
('21003', '2', '10', '03', 'Alajuela', 'San Carlos', 'Buenavista'),
('21004', '2', '10', '04', 'Alajuela', 'San Carlos', 'Aguas Zarcas'),
('21005', '2', '10', '05', 'Alajuela', 'San Carlos', 'Venecia'),
('21006', '2', '10', '06', 'Alajuela', 'San Carlos', 'Pital'),
('21007', '2', '10', '07', 'Alajuela', 'San Carlos', 'Fortuna'),
('21008', '2', '10', '08', 'Alajuela', 'San Carlos', 'Tigra'),
('21009', '2', '10', '09', 'Alajuela', 'San Carlos', 'Palmera'),
('21010', '2', '10', '10', 'Alajuela', 'San Carlos', 'Venado'),
('21011', '2', '10', '11', 'Alajuela', 'San Carlos', 'Cutris'),
('21012', '2', '10', '12', 'Alajuela', 'San Carlos', 'Monterrey'),
('21013', '2', '10', '13', 'Alajuela', 'San Carlos', 'Pocosol'),
-- CANTON 211: ALFARO RUIZ
('21101', '2', '11', '01', 'Alajuela', 'Alfaro Ruiz', 'Zarcero'),
('21102', '2', '11', '02', 'Alajuela', 'Alfaro Ruiz', 'Laguna'),
('21103', '2', '11', '03', 'Alajuela', 'Alfaro Ruiz', 'Tapezco'),
('21104', '2', '11', '04', 'Alajuela', 'Alfaro Ruiz', 'Guadalupe'),
('21105', '2', '11', '05', 'Alajuela', 'Alfaro Ruiz', 'Palmira'),
('21106', '2', '11', '06', 'Alajuela', 'Alfaro Ruiz', 'Zapote'),
('21107', '2', '11', '07', 'Alajuela', 'Alfaro Ruiz', 'Brisas'),
-- CANTON 212: VALVERDE VEGA
('21201', '2', '12', '01', 'Alajuela', 'Valverde Vega', 'Sarchí Norte'),
('21202', '2', '12', '02', 'Alajuela', 'Valverde Vega', 'Sarchí Sur'),
('21203', '2', '12', '03', 'Alajuela', 'Valverde Vega', 'Toro Amarillo'),
('21204', '2', '12', '04', 'Alajuela', 'Valverde Vega', 'San Pedro'),
('21205', '2', '12', '05', 'Alajuela', 'Valverde Vega', 'Rodríguez'),
-- CANTON 213: UPALA
('21301', '2', '13', '01', 'Alajuela', 'Upala', 'Upala'),
('21302', '2', '13', '02', 'Alajuela', 'Upala', 'Aguas Claras'),
('21303', '2', '13', '03', 'Alajuela', 'Upala', 'San José o Pizote'),
('21304', '2', '13', '04', 'Alajuela', 'Upala', 'Bijagua'),
('21305', '2', '13', '05', 'Alajuela', 'Upala', 'Delicias'),
('21306', '2', '13', '06', 'Alajuela', 'Upala', 'Dos Ríos'),
('21307', '2', '13', '07', 'Alajuela', 'Upala', 'Yolillal'),
-- CANTON 214: LOS CHILES
('21401', '2', '14', '01', 'Alajuela', 'Los Chiles', 'Los Chiles'),
('21402', '2', '14', '02', 'Alajuela', 'Los Chiles', 'Caño Negro'),
('21403', '2', '14', '03', 'Alajuela', 'Los Chiles', 'Amparo'),
('21404', '2', '14', '04', 'Alajuela', 'Los Chiles', 'San Jorge'),
-- CANTON 215: GUATUSO
('21501', '2', '15', '01', 'Alajuela', 'Guatuso', 'San Rafael'),
('21502', '2', '15', '02', 'Alajuela', 'Guatuso', 'Buenavista'),
('21503', '2', '15', '03', 'Alajuela', 'Guatuso', 'Cote'),

-- PROVINCIA 3: CARTAGO
-- CANTON 301: CARTAGO
('30101', '3', '01', '01', 'Cartago', 'Cartago', 'Oriental'),
('30102', '3', '01', '02', 'Cartago', 'Cartago', 'Occidental'),
('30103', '3', '01', '03', 'Cartago', 'Cartago', 'Carmen'),
('30104', '3', '01', '04', 'Cartago', 'Cartago', 'San Nicolás'),
('30105', '3', '01', '05', 'Cartago', 'Cartago', 'Aguacaliente (San Francisco)'),
('30106', '3', '01', '06', 'Cartago', 'Cartago', 'Guadalupe (Arenilla)'),
('30107', '3', '01', '07', 'Cartago', 'Cartago', 'Corralillo'),
('30108', '3', '01', '08', 'Cartago', 'Cartago', 'Tierra Blanca'),
('30109', '3', '01', '09', 'Cartago', 'Cartago', 'Dulce Nombre'),
('30110', '3', '01', '10', 'Cartago', 'Cartago', 'Llano Grande'),
('30111', '3', '01', '11', 'Cartago', 'Cartago', 'Quebradilla'),
-- CANTON 302: PARAISO
('30201', '3', '02', '01', 'Cartago', 'Paraíso', 'Paraíso'),
('30202', '3', '02', '02', 'Cartago', 'Paraíso', 'Santiago'),
('30203', '3', '02', '03', 'Cartago', 'Paraíso', 'Orosi'),
('30204', '3', '02', '04', 'Cartago', 'Paraíso', 'Cachí'),
('30205', '3', '02', '05', 'Cartago', 'Paraíso', 'Llanos de Sta Lucia'),
-- CANTON 303: LA UNION
('30301', '3', '03', '01', 'Cartago', 'La Unión', 'Tres Ríos'),
('30302', '3', '03', '02', 'Cartago', 'La Unión', 'San Diego'),
('30303', '3', '03', '03', 'Cartago', 'La Unión', 'San Juan'),
('30304', '3', '03', '04', 'Cartago', 'La Unión', 'San Rafael'),
('30305', '3', '03', '05', 'Cartago', 'La Unión', 'Concepción'),
('30306', '3', '03', '06', 'Cartago', 'La Unión', 'Dulce Nombre'),
('30307', '3', '03', '07', 'Cartago', 'La Unión', 'San Ramón'),
('30308', '3', '03', '08', 'Cartago', 'La Unión', 'Río Azul'),
-- CANTON 304: JIMENEZ
('30401', '3', '04', '01', 'Cartago', 'Jiménez', 'Juan Viñas'),
('30402', '3', '04', '02', 'Cartago', 'Jiménez', 'Tucurrique'),
('30403', '3', '04', '03', 'Cartago', 'Jiménez', 'Pejibaye'),
-- CANTON 305: TURRIALBA
('30501', '3', '05', '01', 'Cartago', 'Turrialba', 'Turrialba'),
('30502', '3', '05', '02', 'Cartago', 'Turrialba', 'La Suiza'),
('30503', '3', '05', '03', 'Cartago', 'Turrialba', 'Peralta'),
('30504', '3', '05', '04', 'Cartago', 'Turrialba', 'Santa Cruz'),
('30505', '3', '05', '05', 'Cartago', 'Turrialba', 'Santa Teresita'),
('30506', '3', '05', '06', 'Cartago', 'Turrialba', 'Pavones'),
('30507', '3', '05', '07', 'Cartago', 'Turrialba', 'Tuis'),
('30508', '3', '05', '08', 'Cartago', 'Turrialba', 'Tayutic'),
('30509', '3', '05', '09', 'Cartago', 'Turrialba', 'Santa Rosa'),
('30510', '3', '05', '10', 'Cartago', 'Turrialba', 'Tres Equis'),
('30511', '3', '05', '11', 'Cartago', 'Turrialba', 'La Isabel'),
('30512', '3', '05', '12', 'Cartago', 'Turrialba', 'Chirripo'),
-- CANTON 306: ALVARADO
('30601', '3', '06', '01', 'Cartago', 'Alvarado', 'Pacayas'),
('30602', '3', '06', '02', 'Cartago', 'Alvarado', 'Cervantes'),
('30603', '3', '06', '03', 'Cartago', 'Alvarado', 'Capellades'),
-- CANTON 307: OREAMUNO
('30701', '3', '07', '01', 'Cartago', 'Oreamuno', 'San Rafael'),
('30702', '3', '07', '02', 'Cartago', 'Oreamuno', 'Cot'),
('30703', '3', '07', '03', 'Cartago', 'Oreamuno', 'Potrero Cerrado'),
('30704', '3', '07', '04', 'Cartago', 'Oreamuno', 'Cipreses'),
('30705', '3', '07', '05', 'Cartago', 'Oreamuno', 'Santa Rosa'),
-- CANTON 308: EL GUARCO
('30801', '3', '08', '01', 'Cartago', 'El Guarco', 'El Tejar'),
('30802', '3', '08', '02', 'Cartago', 'El Guarco', 'San Isidro'),
('30803', '3', '08', '03', 'Cartago', 'El Guarco', 'Tobosi'),
('30804', '3', '08', '04', 'Cartago', 'El Guarco', 'Patio de Agua'),

-- PROVINCIA 4: HEREDIA
-- CANTON 401: HEREDIA
('40101', '4', '01', '01', 'Heredia', 'Heredia', 'Heredia'),
('40102', '4', '01', '02', 'Heredia', 'Heredia', 'Mercedes'),
('40103', '4', '01', '03', 'Heredia', 'Heredia', 'San Francisco'),
('40104', '4', '01', '04', 'Heredia', 'Heredia', 'Ulloa'),
('40105', '4', '01', '05', 'Heredia', 'Heredia', 'Vara Blanca'),
-- CANTON 402: BARVA
('40201', '4', '02', '01', 'Heredia', 'Barva', 'Barva'),
('40202', '4', '02', '02', 'Heredia', 'Barva', 'San Pedro'),
('40203', '4', '02', '03', 'Heredia', 'Barva', 'San Pablo'),
('40204', '4', '02', '04', 'Heredia', 'Barva', 'San Roque'),
('40205', '4', '02', '05', 'Heredia', 'Barva', 'Santa Lucía'),
('40206', '4', '02', '06', 'Heredia', 'Barva', 'San José de la Montaña'),
-- CANTON 403: SANTO DOMINGO
('40301', '4', '03', '01', 'Heredia', 'Santo Domingo', 'Santo Domingo'),
('40302', '4', '03', '02', 'Heredia', 'Santo Domingo', 'San Vicente'),
('40303', '4', '03', '03', 'Heredia', 'Santo Domingo', 'San Miguel'),
('40304', '4', '03', '04', 'Heredia', 'Santo Domingo', 'Paracito'),
('40305', '4', '03', '05', 'Heredia', 'Santo Domingo', 'Santo Tomás'),
('40306', '4', '03', '06', 'Heredia', 'Santo Domingo', 'Santa Rosa'),
('40307', '4', '03', '07', 'Heredia', 'Santo Domingo', 'Tures'),
('40308', '4', '03', '08', 'Heredia', 'Santo Domingo', 'Pará'),
-- CANTON 404: SANTA BARBARA
('40401', '4', '04', '01', 'Heredia', 'Santa Bárbara', 'Santa Bárbara'),
('40402', '4', '04', '02', 'Heredia', 'Santa Bárbara', 'San Pedro'),
('40403', '4', '04', '03', 'Heredia', 'Santa Bárbara', 'San Juan'),
('40404', '4', '04', '04', 'Heredia', 'Santa Bárbara', 'Jesús'),
('40405', '4', '04', '05', 'Heredia', 'Santa Bárbara', 'Santo Domingo del Roble'),
('40406', '4', '04', '06', 'Heredia', 'Santa Bárbara', 'Puraba'),
-- CANTON 405: SAN RAFAEL
('40501', '4', '05', '01', 'Heredia', 'San Rafael', 'San Rafael'),
('40502', '4', '05', '02', 'Heredia', 'San Rafael', 'San Josecito'),
('40503', '4', '05', '03', 'Heredia', 'San Rafael', 'Santiago'),
('40504', '4', '05', '04', 'Heredia', 'San Rafael', 'Ángeles'),
('40505', '4', '05', '05', 'Heredia', 'San Rafael', 'Concepción'),
-- CANTON 406: SAN ISIDRO
('40601', '4', '06', '01', 'Heredia', 'San Isidro', 'San Isidro'),
('40602', '4', '06', '02', 'Heredia', 'San Isidro', 'San José'),
('40603', '4', '06', '03', 'Heredia', 'San Isidro', 'Concepción'),
('40604', '4', '06', '04', 'Heredia', 'San Isidro', 'San Francisco'),
-- CANTON 407: BELEN
('40701', '4', '07', '01', 'Heredia', 'Belén', 'San Antonio'),
('40702', '4', '07', '02', 'Heredia', 'Belén', 'La Rivera'),
('40703', '4', '07', '03', 'Heredia', 'Belén', 'Asunción'),
-- CANTON 408: FLORES
('40801', '4', '08', '01', 'Heredia', 'Flores', 'San Joaquín'),
('40802', '4', '08', '02', 'Heredia', 'Flores', 'Barrantes'),
('40803', '4', '08', '03', 'Heredia', 'Flores', 'Llorente'),
-- CANTON 409: SAN PABLO
('40901', '4', '09', '01', 'Heredia', 'San Pablo', 'San Pablo'),
-- CANTON 410: SARAPIQUI
('41001', '4', '10', '01', 'Heredia', 'Sarapiquí', 'Puerto Viejo'),
('41002', '4', '10', '02', 'Heredia', 'Sarapiquí', 'La Virgen'),
('41003', '4', '10', '03', 'Heredia', 'Sarapiquí', 'Horquetas'),
('41004', '4', '10', '04', 'Heredia', 'Sarapiquí', 'Llanuras del Gaspar'),
('41005', '4', '10', '05', 'Heredia', 'Sarapiquí', 'Cureña'),

-- PROVINCIA 5: GUANACASTE
-- CANTON 501: LIBERIA
('50101', '5', '01', '01', 'Guanacaste', 'Liberia', 'Liberia'),
('50102', '5', '01', '02', 'Guanacaste', 'Liberia', 'Cañas Dulces'),
('50103', '5', '01', '03', 'Guanacaste', 'Liberia', 'Mayorga'),
('50104', '5', '01', '04', 'Guanacaste', 'Liberia', 'Nacascolo'),
('50105', '5', '01', '05', 'Guanacaste', 'Liberia', 'Curubande'),
-- CANTON 502: NICOYA
('50201', '5', '02', '01', 'Guanacaste', 'Nicoya', 'Nicoya'),
('50202', '5', '02', '02', 'Guanacaste', 'Nicoya', 'Mansión'),
('50203', '5', '02', '03', 'Guanacaste', 'Nicoya', 'San Antonio'),
('50204', '5', '02', '04', 'Guanacaste', 'Nicoya', 'Quebrada Honda'),
('50205', '5', '02', '05', 'Guanacaste', 'Nicoya', 'Sámara'),
('50206', '5', '02', '06', 'Guanacaste', 'Nicoya', 'Nosara'),
('50207', '5', '02', '07', 'Guanacaste', 'Nicoya', 'Belén de Nosarita'),
-- CANTON 503: SANTA CRUZ
('50301', '5', '03', '01', 'Guanacaste', 'Santa Cruz', 'Santa Cruz'),
('50302', '5', '03', '02', 'Guanacaste', 'Santa Cruz', 'Bolsón'),
('50303', '5', '03', '03', 'Guanacaste', 'Santa Cruz', 'Veintisiete de Abril'),
('50304', '5', '03', '04', 'Guanacaste', 'Santa Cruz', 'Tempate'),
('50305', '5', '03', '05', 'Guanacaste', 'Santa Cruz', 'Cartagena'),
('50306', '5', '03', '06', 'Guanacaste', 'Santa Cruz', 'Cuajiniquil'),
('50307', '5', '03', '07', 'Guanacaste', 'Santa Cruz', 'Diriá'),
('50308', '5', '03', '08', 'Guanacaste', 'Santa Cruz', 'Cabo Velas'),
('50309', '5', '03', '09', 'Guanacaste', 'Santa Cruz', 'Tamarindo'),
-- CANTON 504: BAGACES
('50401', '5', '04', '01', 'Guanacaste', 'Bagaces', 'Bagaces'),
('50402', '5', '04', '02', 'Guanacaste', 'Bagaces', 'Fortuna'),
('50403', '5', '04', '03', 'Guanacaste', 'Bagaces', 'Mogote'),
('50404', '5', '04', '04', 'Guanacaste', 'Bagaces', 'Río Naranjo'),
-- CANTON 505: CARRILLO
('50501', '5', '05', '01', 'Guanacaste', 'Carrillo', 'Filadelfia'),
('50502', '5', '05', '02', 'Guanacaste', 'Carrillo', 'Palmira'),
('50503', '5', '05', '03', 'Guanacaste', 'Carrillo', 'Sardinal'),
('50504', '5', '05', '04', 'Guanacaste', 'Carrillo', 'Belén'),
-- CANTON 506: CAÑAS
('50601', '5', '06', '01', 'Guanacaste', 'Cañas', 'Cañas'),
('50602', '5', '06', '02', 'Guanacaste', 'Cañas', 'Palmira'),
('50603', '5', '06', '03', 'Guanacaste', 'Cañas', 'San Miguel'),
('50604', '5', '06', '04', 'Guanacaste', 'Cañas', 'Bebedero'),
('50605', '5', '06', '05', 'Guanacaste', 'Cañas', 'Porozal'),
-- CANTON 507: ABANGARES
('50701', '5', '07', '01', 'Guanacaste', 'Abangares', 'Juntas'),
('50702', '5', '07', '02', 'Guanacaste', 'Abangares', 'Sierra'),
('50703', '5', '07', '03', 'Guanacaste', 'Abangares', 'San Juan'),
('50704', '5', '07', '04', 'Guanacaste', 'Abangares', 'Colorado'),
-- CANTON 508: TILARAN
('50801', '5', '08', '01', 'Guanacaste', 'Tilarán', 'Tilarán'),
('50802', '5', '08', '02', 'Guanacaste', 'Tilarán', 'Quebrada Grande'),
('50803', '5', '08', '03', 'Guanacaste', 'Tilarán', 'Tronadora'),
('50804', '5', '08', '04', 'Guanacaste', 'Tilarán', 'Santa Rosa'),
('50805', '5', '08', '05', 'Guanacaste', 'Tilarán', 'Líbano'),
('50806', '5', '08', '06', 'Guanacaste', 'Tilarán', 'Tierras Morenas'),
('50807', '5', '08', '07', 'Guanacaste', 'Tilarán', 'Arenal'),
-- CANTON 509: NANDAYURE
('50901', '5', '09', '01', 'Guanacaste', 'Nandayure', 'Carmona'),
('50902', '5', '09', '02', 'Guanacaste', 'Nandayure', 'Santa Rita'),
('50903', '5', '09', '03', 'Guanacaste', 'Nandayure', 'Zapotal'),
('50904', '5', '09', '04', 'Guanacaste', 'Nandayure', 'San Pablo'),
('50905', '5', '09', '05', 'Guanacaste', 'Nandayure', 'Porvenir'),
('50906', '5', '09', '06', 'Guanacaste', 'Nandayure', 'Bejuco'),
-- CANTON 510: LA CRUZ
('51001', '5', '10', '01', 'Guanacaste', 'La Cruz', 'La Cruz'),
('51002', '5', '10', '02', 'Guanacaste', 'La Cruz', 'Santa Cecilia'),
('51003', '5', '10', '03', 'Guanacaste', 'La Cruz', 'Garita'),
('51004', '5', '10', '04', 'Guanacaste', 'La Cruz', 'Santa Elena'),
-- CANTON 511: HOJANCHA
('51101', '5', '11', '01', 'Guanacaste', 'Hojancha', 'Hojancha'),
('51102', '5', '11', '02', 'Guanacaste', 'Hojancha', 'Monte Romo'),
('51103', '5', '11', '03', 'Guanacaste', 'Hojancha', 'Puerto Carrillo'),
('51104', '5', '11', '04', 'Guanacaste', 'Hojancha', 'Huacas'),

-- PROVINCIA 6: PUNTARENAS
-- CANTON 601: PUNTARENAS
('60101', '6', '01', '01', 'Puntarenas', 'Puntarenas', 'Puntarenas'),
('60102', '6', '01', '02', 'Puntarenas', 'Puntarenas', 'Pitahaya'),
('60103', '6', '01', '03', 'Puntarenas', 'Puntarenas', 'Chomes'),
('60104', '6', '01', '04', 'Puntarenas', 'Puntarenas', 'Lepanto'),
('60105', '6', '01', '05', 'Puntarenas', 'Puntarenas', 'Paquera'),
('60106', '6', '01', '06', 'Puntarenas', 'Puntarenas', 'Manzanillo'),
('60107', '6', '01', '07', 'Puntarenas', 'Puntarenas', 'Guacimal'),
('60108', '6', '01', '08', 'Puntarenas', 'Puntarenas', 'Barranca'),
('60109', '6', '01', '09', 'Puntarenas', 'Puntarenas', 'Monte Verde'),
('60110', '6', '01', '10', 'Puntarenas', 'Puntarenas', 'Isla del Coco'),
('60111', '6', '01', '11', 'Puntarenas', 'Puntarenas', 'Cóbano'),
('60112', '6', '01', '12', 'Puntarenas', 'Puntarenas', 'Chacarita'),
('60113', '6', '01', '13', 'Puntarenas', 'Puntarenas', 'Chira (Isla)'),
('60114', '6', '01', '14', 'Puntarenas', 'Puntarenas', 'Acapulco'),
('60115', '6', '01', '15', 'Puntarenas', 'Puntarenas', 'El Roble'),
('60116', '6', '01', '16', 'Puntarenas', 'Puntarenas', 'Arancibia'),
-- CANTON 602: ESPARZA
('60201', '6', '02', '01', 'Puntarenas', 'Esparza', 'Espíritu Santo'),
('60202', '6', '02', '02', 'Puntarenas', 'Esparza', 'San Juan Grande'),
('60203', '6', '02', '03', 'Puntarenas', 'Esparza', 'Macacona'),
('60204', '6', '02', '04', 'Puntarenas', 'Esparza', 'San Rafael'),
('60205', '6', '02', '05', 'Puntarenas', 'Esparza', 'San Jerónimo'),
-- CANTON 603: BUENOS AIRES
('60301', '6', '03', '01', 'Puntarenas', 'Buenos Aires', 'Buenos Aires'),
('60302', '6', '03', '02', 'Puntarenas', 'Buenos Aires', 'Volcán'),
('60303', '6', '03', '03', 'Puntarenas', 'Buenos Aires', 'Potrero Grande'),
('60304', '6', '03', '04', 'Puntarenas', 'Buenos Aires', 'Boruca'),
('60305', '6', '03', '05', 'Puntarenas', 'Buenos Aires', 'Pilas'),
('60306', '6', '03', '06', 'Puntarenas', 'Buenos Aires', 'Colinas o Bajo de Maíz'),
('60307', '6', '03', '07', 'Puntarenas', 'Buenos Aires', 'Chánguena'),
('60308', '6', '03', '08', 'Puntarenas', 'Buenos Aires', 'Bioley'),
('60309', '6', '03', '09', 'Puntarenas', 'Buenos Aires', 'Brunka'),
-- CANTON 604: MONTES DE ORO
('60401', '6', '04', '01', 'Puntarenas', 'Montes de Oro', 'Miramar'),
('60402', '6', '04', '02', 'Puntarenas', 'Montes de Oro', 'Unión'),
('60403', '6', '04', '03', 'Puntarenas', 'Montes de Oro', 'San Isidro'),
-- CANTON 605: OSA
('60501', '6', '05', '01', 'Puntarenas', 'Osa', 'Puerto Cortés'),
('60502', '6', '05', '02', 'Puntarenas', 'Osa', 'Palmar'),
('60503', '6', '05', '03', 'Puntarenas', 'Osa', 'Sierpe'),
('60504', '6', '05', '04', 'Puntarenas', 'Osa', 'Bahía Ballena'),
('60505', '6', '05', '05', 'Puntarenas', 'Osa', 'Piedras Blancas'),
-- CANTON 606: AGUIRRE
('60601', '6', '06', '01', 'Puntarenas', 'Aguirre', 'Quepos'),
('60602', '6', '06', '02', 'Puntarenas', 'Aguirre', 'Savegre'),
('60603', '6', '06', '03', 'Puntarenas', 'Aguirre', 'Naranjito'),
-- CANTON 607: GOLFITO
('60701', '6', '07', '01', 'Puntarenas', 'Golfito', 'Golfito'),
('60702', '6', '07', '02', 'Puntarenas', 'Golfito', 'Puerto Jiménez'),
('60703', '6', '07', '03', 'Puntarenas', 'Golfito', 'Guaycará'),
('60704', '6', '07', '04', 'Puntarenas', 'Golfito', 'Pavones o Villa Conte'),
-- CANTON 608: COTO BRUS
('60801', '6', '08', '01', 'Puntarenas', 'Coto Brus', 'San Vito'),
('60802', '6', '08', '02', 'Puntarenas', 'Coto Brus', 'Sabalito'),
('60803', '6', '08', '03', 'Puntarenas', 'Coto Brus', 'Agua Buena'),
('60804', '6', '08', '04', 'Puntarenas', 'Coto Brus', 'Limoncito'),
('60805', '6', '08', '05', 'Puntarenas', 'Coto Brus', 'Pittier'),
-- CANTON 609: PARRITA
('60901', '6', '09', '01', 'Puntarenas', 'Parrita', 'Parrita'),
-- CANTON 610: CORREDORES
('61001', '6', '10', '01', 'Puntarenas', 'Corredores', 'Corredores'),
('61002', '6', '10', '02', 'Puntarenas', 'Corredores', 'La Cuesta'),
('61003', '6', '10', '03', 'Puntarenas', 'Corredores', 'Paso Canoas'),
('61004', '6', '10', '04', 'Puntarenas', 'Corredores', 'Laurel'),
-- CANTON 611: GARABITO
('61101', '6', '11', '01', 'Puntarenas', 'Garabito', 'Jacó'),
('61102', '6', '11', '02', 'Puntarenas', 'Garabito', 'Tárcoles'),

-- PROVINCIA 7: LIMON
-- CANTON 701: LIMON
('70101', '7', '01', '01', 'Limón', 'Limón', 'Limón'),
('70102', '7', '01', '02', 'Limón', 'Limón', 'Valle La Estrella'),
('70103', '7', '01', '03', 'Limón', 'Limón', 'Río Blanco'),
('70104', '7', '01', '04', 'Limón', 'Limón', 'Matama'),
-- CANTON 702: POCOCI
('70201', '7', '02', '01', 'Limón', 'Pococí', 'Guápiles'),
('70202', '7', '02', '02', 'Limón', 'Pococí', 'Jiménez'),
('70203', '7', '02', '03', 'Limón', 'Pococí', 'Rita'),
('70204', '7', '02', '04', 'Limón', 'Pococí', 'Roxana'),
('70205', '7', '02', '05', 'Limón', 'Pococí', 'Cariari'),
('70206', '7', '02', '06', 'Limón', 'Pococí', 'Colorado'),
-- CANTON 703: SIQUIRRES
('70301', '7', '03', '01', 'Limón', 'Siquirres', 'Siquirres'),
('70302', '7', '03', '02', 'Limón', 'Siquirres', 'Pacuarito'),
('70303', '7', '03', '03', 'Limón', 'Siquirres', 'Florida'),
('70304', '7', '03', '04', 'Limón', 'Siquirres', 'Germania'),
('70305', '7', '03', '05', 'Limón', 'Siquirres', 'Cairo'),
('70306', '7', '03', '06', 'Limón', 'Siquirres', 'Alegría'),
-- CANTON 704: TALAMANCA
('70401', '7', '04', '01', 'Limón', 'Talamanca', 'Bratsi'),
('70402', '7', '04', '02', 'Limón', 'Talamanca', 'Sixaola'),
('70403', '7', '04', '03', 'Limón', 'Talamanca', 'Cahuita'),
('70404', '7', '04', '04', 'Limón', 'Talamanca', 'Telire'),
-- CANTON 705: MATINA
('70501', '7', '05', '01', 'Limón', 'Matina', 'Matina'),
('70502', '7', '05', '02', 'Limón', 'Matina', 'Batán'),
('70503', '7', '05', '03', 'Limón', 'Matina', 'Carrandí'),
-- CANTON 706: GUACIMO
('70601', '7', '06', '01', 'Limón', 'Guácimo', 'Guácimo'),
('70602', '7', '06', '02', 'Limón', 'Guácimo', 'Mercedes'),
('70603', '7', '06', '03', 'Limón', 'Guácimo', 'Pocora'),
('70604', '7', '06', '04', 'Limón', 'Guácimo', 'Río Jiménez'),
('70605', '7', '06', '05', 'Limón', 'Guácimo', 'Duacari')
ON CONFLICT (codigo) DO NOTHING;

COMMIT;



-- =============================================
-- SEED: ACCOUNT RECEIVABLE STATUS
-- Source: seeds/catalog/general/013-insert-account-receivable-status.sql
-- =============================================
INSERT INTO general_schema.account_receivable_status (status_name, description) VALUES
    ('Pending',      'Payment is pending'),
    ('Partial Paid', 'Partial payment has been received'),
    ('Paid',         'Payment has been received in full'),
    ('Overdue',      'Payment is overdue')
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: ACCOUNT RECEIVABLE TYPES
-- Source: seeds/catalog/general/014-insert-account-receivable-types.sql
-- =============================================
INSERT INTO general_schema.account_receivable_type (type_name, description) VALUES
    ('venta_credito', 'Venta a crédito a cliente registrado'),
    ('venta_apartado', 'Venta con apartado — inventario reservado hasta liquidar saldo')
ON CONFLICT (type_name) DO NOTHING;



-- =============================================
-- SEED: RETURN REASONS
-- Source: seeds/catalog/pos/001-insert-return-reason.sql
-- =============================================
SET SEARCH_PATH TO pos_schema;

INSERT INTO pos_schema.return_reason(reason_code, reason_name, description) VALUES
    ('DEFECT', 'Defecto de fábrica', 'El producto tiene un defecto de fabricación'),
    ('SIZE_CHANGE', 'Cambio de talla', 'El cliente requiere una talla diferente'),
    ('WRONG_PRODUCT', 'Producto equivocado', 'Se entregó un producto diferente al solicitado'),
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
-- SEED: SALE CONDITIONS
-- Source: seeds/catalog/pos/006-insert-sale-conditions.sql
-- =============================================
INSERT INTO pos_schema.sale_condition (condition_code, condition_desc) VALUES
  ('01', 'Contado'),
  ('02', 'Credito'),
  ('03', 'Consignacion'),
  ('04', 'Apartado'),
  ('05', 'Arrendamiento con opcion de compra'),
  ('06', 'Arrendamiento en funcion financiera'),
  ('07', 'Cobro a favor de un tercero'),
  ('08', 'Servicios prestados al estado a credito'),
  ('09', 'Pago del servicio prestado al estado'),
  ('10', 'Venta a credito hasta 90 dias'),
  ('11', 'Pago de venta a credito en IVA hasta 90 dias'),
  ('99', 'Otros') 
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: INVOICE STATUS
-- Source: seeds/catalog/pos/007-insert-invoice-status.sql
-- =============================================
-- Seed: pos_schema.invoice_status
-- status_id values are fixed constants referenced in application code
--   1 = pendiente  → recién generada, aún no enviada o sin respuesta de Hacienda
--   2 = aceptada   → Hacienda confirmó la factura
--   3 = rechazada  → Hacienda rechazó la factura
--   4 = timeout    → agotó los reintentos del cron sin resolución

INSERT INTO pos_schema.invoice_status (status_id, description)
VALUES
  (1, 'pendiente'),
  (2, 'aceptada'),
  (3, 'rechazada'),
  (4, 'timeout')
ON CONFLICT (status_id) DO NOTHING;



-- =============================================
-- SEED: COLLECTION ALERT TYPES
-- Source: seeds/catalog/pos/008-insert-collection-alert-types.sql
-- =============================================
INSERT INTO pos_schema.sale_collection_alert_type (collection_alert_type_name, description) VALUES
    ('Upcoming Due Date', 'Alert for upcoming collection due date'),
    ('Urgent Collection', 'Alert for urgent collections near due date'),
    ('Overdue Collection', 'Alert for overdue collections past due date')
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



-- =============================================
-- SEED: HOLIDAYS
-- Source: seeds/catalog/hr/003-insert-holidays.sql
-- =============================================
INSERT INTO hr_schema.holiday (date, holiday_name) VALUES 
('2026-01-01', 'Ano Nuevo'),
('2026-04-09', 'Jueves Santo'),
('2026-04-10', 'Viernes Santo'),
('2026-04-11', 'Juan Santamaria'),
('2026-05-01', 'Dia del Trabajador'),
('2026-07-25', 'Anexión del Partido de Nicoya'),
('2026-08-02', 'Dia de la Virgen de los Ángeles'),
('2026-08-15', 'Dia de la Madre'),
('2026-09-15', 'Dia de la Independencia'),
('2026-12-25', 'Navidad');



-- =============================================
-- SEED: ACCOUNTING ENTRY TYPES
-- Source: seeds/catalog/accounting/001-insert-account-types.sql
-- =============================================
SET SEARCH_PATH TO accounting_schema;

INSERT INTO accounting_schema.account_type(type_name, nature, description) VALUES
('Activo', 'DEBIT', 'Bienes y derechos de la empresa'),
('Pasivo', 'CREDIT', 'Obligaciones y deudas de la empresa'),
('Patrimonio', 'CREDIT', 'Capital y resultados acumulados'),
('Ingreso', 'CREDIT', 'Ingresos operativos y no operativos'),
('Gasto', 'DEBIT', 'Gastos operativos y administrativos'),
('Costo', 'DEBIT', 'Costos directos de producción y venta')
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: JOURNAL ENTRY STATUSES
-- Source: seeds/catalog/accounting/002-insert-journal-entry-statuses.sql
-- =============================================
SET SEARCH_PATH TO accounting_schema;

INSERT INTO accounting_schema.journal_entry_status(status_name, description) VALUES
('Borrador', 'Asiento en estado de borrador, pendiente de confirmación'),
('Confirmado', 'Asiento confirmado y registrado en el libro mayor'),
('Anulado', 'Asiento anulado, no afecta los estados financieros')
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: SOURCE TYPES
-- Source: seeds/catalog/accounting/003-insert-source-types.sql
-- =============================================
SET SEARCH_PATH TO accounting_schema;

INSERT INTO accounting_schema.source_type(source_name, description) VALUES
('SALE_CASH', 'Venta al contado'),
('SALE_CREDIT', 'Venta a crédito'),
('SALE_COGS', 'Costo de venta asociado a una venta'),
('PURCHASE', 'Compra de inventario o servicios'),
('PAYMENT_RECEIVED', 'Pago recibido de cliente'),
('PAYMENT_MADE', 'Pago realizado a proveedor'),
('PAYROLL', 'Registro de nómina'),
('MANUAL', 'Asiento manual ingresado por el usuario'),
('ADJUSTMENT', 'Ajuste contable'),
('EXPENSE', 'Registro de gasto operativo')
ON CONFLICT DO NOTHING;



-- =============================================
-- SEED: CHART OF ACCOUNTS TEMPLATE
-- Source: seeds/catalog/accounting/004-insert-chart-of-accounts-template.sql
-- =============================================
-- ============================================================
-- Plan de Cuentas Plantilla NIIF para PYMES (Costa Rica)
-- ============================================================
-- Este seed NO inserta directamente en chart_of_accounts
-- (esa tabla es por tenant). En su lugar, popula una tabla
-- temporal de plantilla que la función provision_tenant_accounts()
-- usa para copiar cuentas al crear un nuevo tenant.
-- ============================================================

SET SEARCH_PATH TO accounting_schema;

CREATE TABLE IF NOT EXISTS accounting_schema.chart_of_accounts_template (
    template_id SERIAL PRIMARY KEY,
    account_code VARCHAR(20) NOT NULL UNIQUE,
    account_name VARCHAR(150) NOT NULL,
    account_type_id INTEGER NOT NULL REFERENCES accounting_schema.account_type(account_type_id),
    parent_code VARCHAR(20),
    allows_transactions BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE accounting_schema.chart_of_accounts_template IS
    'Template chart of accounts based on NIIF for PYMES (Costa Rica).
     Copied to chart_of_accounts per tenant via provision_tenant_accounts().';

-- Limpiar template para re-seed limpio
TRUNCATE accounting_schema.chart_of_accounts_template RESTART IDENTITY;

-- -------------------------------------------------------
-- 1. ACTIVOS
-- -------------------------------------------------------
INSERT INTO accounting_schema.chart_of_accounts_template(account_code, account_name, account_type_id, parent_code, allows_transactions) VALUES
-- Grupo principal
('1',       'Activos',                          1, NULL,    FALSE),

-- Activo Corriente
('1-1',     'Activo Corriente',                 1, '1',     FALSE),
('1-1-001', 'Caja General',                     1, '1-1',   TRUE),
('1-1-002', 'Bancos',                           1, '1-1',   TRUE),
('1-1-003', 'Cuentas por Cobrar Clientes',      1, '1-1',   TRUE),
('1-1-004', 'Documentos por Cobrar',            1, '1-1',   TRUE),
('1-1-005', 'IVA Crédito Fiscal',               1, '1-1',   TRUE),
('1-1-006', 'Anticipo a Proveedores',           1, '1-1',   TRUE),
('1-1-007', 'Inventario de Mercadería',         1, '1-1',   TRUE),
('1-1-008', 'Inventario de Materia Prima',      1, '1-1',   TRUE),

-- Activo No Corriente
('1-2',     'Activo No Corriente',              1, '1',     FALSE),
('1-2-001', 'Terrenos',                         1, '1-2',   TRUE),
('1-2-002', 'Edificios',                        1, '1-2',   TRUE),
('1-2-003', 'Mobiliario y Equipo',              1, '1-2',   TRUE),
('1-2-004', 'Equipo de Cómputo',                1, '1-2',   TRUE),
('1-2-005', 'Vehículos',                        1, '1-2',   TRUE),
('1-2-006', 'Depreciación Acumulada',           1, '1-2',   TRUE),

-- -------------------------------------------------------
-- 2. PASIVOS
-- -------------------------------------------------------
('2',       'Pasivos',                          2, NULL,    FALSE),

-- Pasivo Corriente
('2-1',     'Pasivo Corriente',                 2, '2',     FALSE),
('2-1-001', 'Cuentas por Pagar Proveedores',    2, '2-1',   TRUE),
('2-1-002', 'Documentos por Pagar',             2, '2-1',   TRUE),
('2-1-003', 'IVA Débito Fiscal',                2, '2-1',   TRUE),
('2-1-004', 'Retenciones por Pagar',            2, '2-1',   TRUE),
('2-1-005', 'Salarios por Pagar',               2, '2-1',   TRUE),
('2-1-006', 'Cargas Sociales por Pagar',        2, '2-1',   TRUE),
('2-1-007', 'Impuesto sobre la Renta por Pagar',2, '2-1',   TRUE),
('2-1-008', 'Anticipos de Clientes',            2, '2-1',   TRUE),

-- Pasivo No Corriente
('2-2',     'Pasivo No Corriente',              2, '2',     FALSE),
('2-2-001', 'Préstamos Bancarios LP',           2, '2-2',   TRUE),
('2-2-002', 'Hipotecas por Pagar',              2, '2-2',   TRUE),

-- -------------------------------------------------------
-- 3. PATRIMONIO
-- -------------------------------------------------------
('3',       'Patrimonio',                       3, NULL,    FALSE),
('3-1',     'Capital Social',                   3, '3',     TRUE),
('3-2',     'Reserva Legal',                    3, '3',     TRUE),
('3-3',     'Utilidades Retenidas',             3, '3',     TRUE),
('3-4',     'Utilidad del Período',             3, '3',     TRUE),
('3-5',     'Pérdida del Período',              3, '3',     TRUE),

-- -------------------------------------------------------
-- 4. INGRESOS
-- -------------------------------------------------------
('4',       'Ingresos',                         4, NULL,    FALSE),
('4-1',     'Ingresos Operativos',              4, '4',     FALSE),
('4-1-001', 'Ingresos por Ventas',              4, '4-1',   TRUE),
('4-1-002', 'Devoluciones sobre Ventas',        4, '4-1',   TRUE),
('4-1-003', 'Descuentos sobre Ventas',          4, '4-1',   TRUE),
('4-2',     'Ingresos No Operativos',           4, '4',     FALSE),
('4-2-001', 'Ingresos por Intereses',           4, '4-2',   TRUE),
('4-2-002', 'Otros Ingresos',                   4, '4-2',   TRUE),

-- -------------------------------------------------------
-- 5. GASTOS
-- -------------------------------------------------------
('5',       'Gastos',                           5, NULL,    FALSE),
('5-1',     'Gastos Operativos',                5, '5',     FALSE),
('5-1-001', 'Salarios y Sueldos',               5, '5-1',   TRUE),
('5-1-002', 'Cargas Sociales',                  5, '5-1',   TRUE),
('5-1-003', 'Alquiler',                         5, '5-1',   TRUE),
('5-1-004', 'Servicios Públicos',               5, '5-1',   TRUE),
('5-1-005', 'Depreciación',                     5, '5-1',   TRUE),
('5-1-006', 'Seguros',                          5, '5-1',   TRUE),
('5-1-007', 'Suministros de Oficina',           5, '5-1',   TRUE),
('5-1-008', 'Mantenimiento y Reparaciones',     5, '5-1',   TRUE),
('5-1-009', 'Publicidad y Mercadeo',            5, '5-1',   TRUE),
('5-1-010', 'Gastos de Viaje',                  5, '5-1',   TRUE),
('5-2',     'Gastos Financieros',               5, '5',     FALSE),
('5-2-001', 'Intereses Pagados',                5, '5-2',   TRUE),
('5-2-002', 'Comisiones Bancarias',             5, '5-2',   TRUE),
('5-2-003', 'Diferencial Cambiario',            5, '5-2',   TRUE),
('5-3',     'Gastos Variables',                 5, '5',     FALSE),
('5-3-001', 'Comisiones por Ventas',            5, '5-3',   TRUE),
('5-3-002', 'Empaque y Embalaje',               5, '5-3',   TRUE),
('5-3-003', 'Transporte y Envíos',              5, '5-3',   TRUE),
('5-3-004', 'Materiales de Producción',         5, '5-3',   TRUE),

-- -------------------------------------------------------
-- 6. COSTOS
-- -------------------------------------------------------
('6',       'Costos',                           6, NULL,    FALSE),
('6-1',     'Costo de Ventas',                  6, '6',     TRUE),
('6-2',     'Costo de Producción',              6, '6',     TRUE),
('6-3',     'Costo de Mano de Obra Directa',    6, '6',     TRUE);



-- =============================================
-- SEED: EXPENSE CATEGORY TEMPLATE
-- Source: seeds/catalog/accounting/005-insert-expense-category-template.sql
-- =============================================
-- ============================================================
-- Expense Category Template
-- ============================================================
-- Template table for expense categories, copied to per-tenant
-- expense_category via provision_tenant_expense_categories().
-- Maps each category to a chart of accounts code.
-- ============================================================

SET SEARCH_PATH TO accounting_schema;

CREATE TABLE IF NOT EXISTS accounting_schema.expense_category_template (
    template_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    account_code VARCHAR(20) NOT NULL,
    is_fixed BOOLEAN DEFAULT TRUE,
    parent_name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE accounting_schema.expense_category_template IS
    'Template expense categories based on NIIF for PYMES (Costa Rica).
     Copied to expense_category per tenant via provision_tenant_expense_categories().';

TRUNCATE accounting_schema.expense_category_template RESTART IDENTITY;

INSERT INTO accounting_schema.expense_category_template(name, account_code, is_fixed, parent_name) VALUES
-- Gastos Operativos Fijos
('Salarios y Sueldos',               '5-1-001', TRUE,  NULL),
('Cargas Sociales',                   '5-1-002', TRUE,  NULL),
('Alquiler',                          '5-1-003', TRUE,  NULL),
('Servicios Públicos',                '5-1-004', TRUE,  NULL),
('Depreciación',                      '5-1-005', TRUE,  NULL),
('Seguros',                           '5-1-006', TRUE,  NULL),
('Suministros de Oficina',            '5-1-007', TRUE,  NULL),
('Mantenimiento y Reparaciones',      '5-1-008', TRUE,  NULL),
('Publicidad y Mercadeo',             '5-1-009', TRUE,  NULL),
('Gastos de Viaje',                   '5-1-010', TRUE,  NULL),

-- Gastos Financieros
('Intereses Pagados',                 '5-2-001', TRUE,  NULL),
('Comisiones Bancarias',              '5-2-002', TRUE,  NULL),
('Diferencial Cambiario',             '5-2-003', TRUE,  NULL),

-- Gastos Variables
('Comisiones por Ventas',             '5-3-001', FALSE, NULL),
('Empaque y Embalaje',                '5-3-002', FALSE, NULL),
('Transporte y Envíos',               '5-3-003', FALSE, NULL),
('Materiales de Producción',          '5-3-004', FALSE, NULL);



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
            'general_schema.identification_type',
            'general_schema.currency',
            'general_schema.payment_method',
            'general_schema.subscription_type',
            'general_schema.customer_segment',
            'general_schema.customer_segment_margin_type',
            'general_schema.tax_rate',
            'general_schema.account_payable_status',
            'general_schema.account_payable_type',
            'general_schema.account_receivable_status',
            'general_schema.account_receivable_type',
            'general_schema.territorio_catalog',
            'pos_schema.return_reason',
            'pos_schema.return_status',
            'pos_schema.promotion_type',
            'pos_schema.score_redemption_status',
            'pos_schema.score_transaction_type',
            'pos_schema.sale_condition',
            'pos_schema.invoice_status',
            'pos_schema.sale_collection_alert_type',
            'inventory_schema.inventory_log_type',
            'purchase_schema.purchase_order_status',
            'purchase_schema.purchase_order_payment_alert_type',
            'hr_schema.payment_schedule',
            'hr_schema.paysheet_status',
            'hr_schema.holiday',
            'accounting_schema.account_type',
            'accounting_schema.journal_entry_status',
            'accounting_schema.source_type'
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
