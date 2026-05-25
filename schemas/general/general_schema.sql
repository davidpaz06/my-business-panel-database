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