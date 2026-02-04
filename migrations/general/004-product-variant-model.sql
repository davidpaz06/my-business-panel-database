-- ============================================================================
-- MIGRATION: Product Variant Model Integration
-- Date: 2026-02-04
-- Description: Integrates the new product variant model into the database.
--              - product table adopts base_product functionality (same name)
--              - attribute_value replaces variant (key-value pairs per tenant)
--              - product_variant replaces detailed_product (sellable variants)
--              - attribute_assignation links variants to attribute values
--              - Updates inventory and all dependent tables to use product_variant_id
-- ============================================================================

BEGIN;

SET SEARCH_PATH TO general_schema;

DROP TABLE IF EXISTS general_schema.product_attribute CASCADE;

CREATE TABLE IF NOT EXISTS general_schema.attribute_value (
    attribute_value_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id uuid NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    tenant_attribute_id uuid NOT NULL REFERENCES general_schema.tenant_attribute(tenant_attribute_id) ON DELETE CASCADE,
    value_name VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_attribute_value_unique 
    ON general_schema.attribute_value(tenant_id, tenant_attribute_id, lower(value_name));

CREATE INDEX IF NOT EXISTS idx_attribute_value_by_attribute 
    ON general_schema.attribute_value(tenant_attribute_id);

CREATE INDEX IF NOT EXISTS idx_attribute_value_tenant 
    ON general_schema.attribute_value(tenant_id);

COMMENT ON TABLE general_schema.attribute_value IS 
    'Stores attribute values (e.g., "Red", "S", "XL") for tenant attributes. 
    Forms key-value pairs with tenant_attribute.';

CREATE TABLE IF NOT EXISTS general_schema.product_variant (
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
    'Sellable product variants with unique SKUs. 
    References base product and has assigned attributes.';

CREATE TABLE IF NOT EXISTS general_schema.attribute_assignation (
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
    'Links product variants to their attribute values. 
    Query by product_variant_id to get all attributes.';

SET SEARCH_PATH TO inventory_schema;

ALTER TABLE inventory_schema.inventory 
    DROP CONSTRAINT IF EXISTS inventory_tenant_id_product_id_fkey;

ALTER TABLE inventory_schema.inventory 
    ADD COLUMN IF NOT EXISTS product_variant_id uuid;

ALTER TABLE inventory_schema.inventory 
    ALTER COLUMN product_id DROP NOT NULL;

ALTER TABLE inventory_schema.inventory 
    ADD CONSTRAINT inventory_product_variant_fkey 
    FOREIGN KEY (tenant_id, product_variant_id) 
    REFERENCES general_schema.product_variant(tenant_id, product_variant_id) 
    ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_inventory_product_variant 
    ON inventory_schema.inventory(tenant_id, product_variant_id);

ALTER TABLE inventory_schema.inventory_log 
    DROP CONSTRAINT IF EXISTS inventory_log_tenant_id_product_id_fkey;

ALTER TABLE inventory_schema.inventory_log 
    ADD COLUMN IF NOT EXISTS product_variant_id uuid;

ALTER TABLE inventory_schema.inventory_log 
    ALTER COLUMN product_id DROP NOT NULL;

ALTER TABLE inventory_schema.inventory_log 
    ADD CONSTRAINT inventory_log_product_variant_fkey 
    FOREIGN KEY (tenant_id, product_variant_id) 
    REFERENCES general_schema.product_variant(tenant_id, product_variant_id) 
    ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_inventory_log_product_variant 
    ON inventory_schema.inventory_log(tenant_id, product_variant_id);

ALTER TABLE inventory_schema.inventory_transfer_product 
    DROP CONSTRAINT IF EXISTS inventory_transfer_product_tenant_id_product_id_fkey;

ALTER TABLE inventory_schema.inventory_transfer_product 
    ADD COLUMN IF NOT EXISTS product_variant_id uuid;

ALTER TABLE inventory_schema.inventory_transfer_product 
    ALTER COLUMN product_id DROP NOT NULL;

ALTER TABLE inventory_schema.inventory_transfer_product 
    ADD CONSTRAINT inventory_transfer_product_variant_fkey 
    FOREIGN KEY (tenant_id, product_variant_id) 
    REFERENCES general_schema.product_variant(tenant_id, product_variant_id) 
    ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_transfer_product_variant 
    ON inventory_schema.inventory_transfer_product(tenant_id, product_variant_id);

ALTER TABLE inventory_schema.discrepancy_count 
    DROP CONSTRAINT IF EXISTS discrepancy_count_tenant_id_product_id_fkey;

ALTER TABLE inventory_schema.discrepancy_count 
    ADD COLUMN IF NOT EXISTS product_variant_id uuid;

ALTER TABLE inventory_schema.discrepancy_count 
    ALTER COLUMN product_id DROP NOT NULL;

ALTER TABLE inventory_schema.discrepancy_count 
    ADD CONSTRAINT discrepancy_count_product_variant_fkey 
    FOREIGN KEY (tenant_id, product_variant_id) 
    REFERENCES general_schema.product_variant(tenant_id, product_variant_id) 
    ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_discrepancy_product_variant 
    ON inventory_schema.discrepancy_count(tenant_id, product_variant_id);

SET SEARCH_PATH TO pos_schema;

ALTER TABLE pos_schema.sale_item 
    DROP CONSTRAINT IF EXISTS sale_item_tenant_id_product_id_fkey;

ALTER TABLE pos_schema.sale_item 
    ADD COLUMN IF NOT EXISTS product_variant_id uuid;

ALTER TABLE pos_schema.sale_item 
    ALTER COLUMN product_id DROP NOT NULL;

ALTER TABLE pos_schema.sale_item 
    ADD CONSTRAINT sale_item_product_variant_fkey 
    FOREIGN KEY (tenant_id, product_variant_id) 
    REFERENCES general_schema.product_variant(tenant_id, product_variant_id) 
    ON DELETE RESTRICT;

DROP INDEX IF EXISTS pos_schema.idx_sale_item_product_id;
DROP INDEX IF EXISTS pos_schema.idx_sale_item_tenant_product;

CREATE INDEX IF NOT EXISTS idx_sale_item_product_variant 
    ON pos_schema.sale_item(tenant_id, product_variant_id);

CREATE INDEX IF NOT EXISTS idx_sale_item_sale_variant 
    ON pos_schema.sale_item(sale_id, product_variant_id);

SET SEARCH_PATH TO purchase_schema;

ALTER TABLE purchase_schema.purchase_order_item 
    DROP CONSTRAINT IF EXISTS purchase_order_item_tenant_id_product_id_fkey;

ALTER TABLE purchase_schema.purchase_order_item 
    ADD COLUMN IF NOT EXISTS product_variant_id uuid;

ALTER TABLE purchase_schema.purchase_order_item 
    ALTER COLUMN product_id DROP NOT NULL;

ALTER TABLE purchase_schema.purchase_order_item 
    ADD CONSTRAINT purchase_order_item_product_variant_fkey 
    FOREIGN KEY (tenant_id, product_variant_id) 
    REFERENCES general_schema.product_variant(tenant_id, product_variant_id) 
    ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_purchase_order_item_variant 
    ON purchase_schema.purchase_order_item(tenant_id, product_variant_id);

ALTER TABLE purchase_schema.supplier_invoice_item 
    DROP CONSTRAINT IF EXISTS supplier_invoice_item_tenant_id_product_id_fkey;

ALTER TABLE purchase_schema.supplier_invoice_item 
    ADD COLUMN IF NOT EXISTS product_variant_id uuid;

ALTER TABLE purchase_schema.supplier_invoice_item 
    ALTER COLUMN product_id DROP NOT NULL;

ALTER TABLE purchase_schema.supplier_invoice_item 
    ADD CONSTRAINT supplier_invoice_item_product_variant_fkey 
    FOREIGN KEY (tenant_id, product_variant_id) 
    REFERENCES general_schema.product_variant(tenant_id, product_variant_id) 
    ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_supplier_invoice_item_variant 
    ON purchase_schema.supplier_invoice_item(tenant_id, product_variant_id);

ALTER TABLE purchase_schema.goods_receipt_item 
    DROP CONSTRAINT IF EXISTS goods_receipt_item_tenant_id_product_id_fkey;

ALTER TABLE purchase_schema.goods_receipt_item 
    ADD COLUMN IF NOT EXISTS product_variant_id uuid;

ALTER TABLE purchase_schema.goods_receipt_item 
    ALTER COLUMN product_id DROP NOT NULL;

ALTER TABLE purchase_schema.goods_receipt_item 
    ADD CONSTRAINT goods_receipt_item_product_variant_fkey 
    FOREIGN KEY (tenant_id, product_variant_id) 
    REFERENCES general_schema.product_variant(tenant_id, product_variant_id) 
    ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_goods_receipt_item_variant 
    ON purchase_schema.goods_receipt_item(tenant_id, product_variant_id);

COMMENT ON COLUMN general_schema.product.product_id IS 
    'Base product ID. Acts as the parent for all product variants.';

COMMENT ON COLUMN inventory_schema.inventory.product_variant_id IS 
    'References the specific product variant. Inventory is tracked per variant.';

COMMENT ON COLUMN pos_schema.sale_item.product_variant_id IS 
    'References the specific product variant sold.';

COMMENT ON COLUMN purchase_schema.purchase_order_item.product_variant_id IS 
    'References the specific product variant ordered.';

COMMIT;

-- ============================================================================
-- POST-MIGRATION NOTES:
-- 
-- 1. Data Migration Required:
--    - If you have existing product data, you need to:
--      a. Create product_variant records for each product (1:1 initially)
--      b. Update inventory records to reference product_variant_id
--      c. Update pos.sale_item records to reference product_variant_id
--      d. Update purchase tables to reference product_variant_id
--    
-- 2. After data migration, you can drop the old product_id columns:
--    ALTER TABLE inventory_schema.inventory DROP COLUMN product_id;
--    ALTER TABLE inventory_schema.inventory_log DROP COLUMN product_id;
--    ALTER TABLE inventory_schema.inventory_transfer_product DROP COLUMN product_id;
--    ALTER TABLE inventory_schema.discrepancy_count DROP COLUMN product_id;
--    ALTER TABLE pos_schema.sale_item DROP COLUMN product_id;
--    ALTER TABLE purchase_schema.purchase_order_item DROP COLUMN product_id;
--    ALTER TABLE purchase_schema.supplier_invoice_item DROP COLUMN product_id;
--    ALTER TABLE purchase_schema.goods_receipt_item DROP COLUMN product_id;
--
-- 3. Model Summary:
--    product (base product)
--      └── product_variant (sellable SKU)
--            └── attribute_assignation (many-to-many)
--                  └── attribute_value (e.g., "Red", "XL")
--                        └── tenant_attribute (e.g., "Color", "Size")
--                              └── global_attribute (template)
-- ============================================================================
