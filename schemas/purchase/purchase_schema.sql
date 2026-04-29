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
