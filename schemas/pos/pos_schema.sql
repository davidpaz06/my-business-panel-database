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
    -- currency_id: currency the customer paid in (original currency).
    currency_id                INTEGER NOT NULL DEFAULT 1 REFERENCES general_schema.currency(currency_id),
    -- amount_paid: CRC-equivalent of the payment. Used by recalc SUM().
    amount_paid                NUMERIC(12,3) NOT NULL CHECK (amount_paid > 0),
    -- original_amount: amount stated in currency_id (what the customer handed over).
    original_amount            NUMERIC(12,3) DEFAULT 0
        CHECK (original_amount IS NULL OR original_amount > 0),
    -- exchange_rate: rate applied to convert original_amount to amount_paid (CRC).
    exchange_rate              NUMERIC(18,8) DEFAULT 1
        CHECK (exchange_rate IS NULL OR exchange_rate > 0),
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