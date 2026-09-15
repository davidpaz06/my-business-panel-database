-- Migration: 020-drop-electronic-invoicing
-- What: Drop the Hacienda electronic-invoicing subsystem: electronic_sale_invoice,
--       electronic_sale_invoice_items, invoice_status (catalog only consumed by
--       electronic_sale_invoice), sale.has_electronic_invoice, and
--       return_transaction.electronic_sale_invoice_id (+ its deferred FK and the
--       either/or CHECK that allowed a return to reference it).
-- Why:  Costa Rica -> Venezuela business migration. Requirement 1: remove
--       everything related to Hacienda (DGT-R-48-2016 XML-signed) electronic
--       invoicing. Only the digital invoice concept survives (renamed to
--       pos_schema.invoice in migration 021).
-- Context: Slice B (invoice consolidation) of the general-module CR->VE migration.
--       No function/trigger in functions/pos/pos_functions.sql references
--       electronic_sale_invoice (verified), so this is pure DDL — no function
--       rewrite needed for this migration.

-- ─────────────────────────────────────────────────────────────────────────────
-- FORWARD MIGRATION
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE pos_schema.return_transaction
    DROP CONSTRAINT IF EXISTS chk_return_transaction_invoice;

ALTER TABLE pos_schema.return_transaction
    DROP CONSTRAINT IF EXISTS return_transaction_electronic_sale_invoice_id_fkey;

ALTER TABLE pos_schema.return_transaction
    DROP COLUMN IF EXISTS electronic_sale_invoice_id;

DROP TABLE IF EXISTS pos_schema.electronic_sale_invoice_items;

DROP TABLE IF EXISTS pos_schema.electronic_sale_invoice;

DROP TABLE IF EXISTS pos_schema.invoice_status;

ALTER TABLE pos_schema.sale
    DROP COLUMN IF EXISTS has_electronic_invoice;


-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- ALTER TABLE pos_schema.sale ADD COLUMN has_electronic_invoice BOOLEAN DEFAULT FALSE;
--
-- CREATE TABLE pos_schema.invoice_status (
--     status_id INTEGER PRIMARY KEY,
--     description VARCHAR(50) NOT NULL
-- );
--
-- CREATE TABLE pos_schema.electronic_sale_invoice (
--     electronic_sale_invoice_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
--     sale_id UUID NOT NULL REFERENCES pos_schema.sale(sale_id) ON DELETE CASCADE,
--     status_id INTEGER REFERENCES pos_schema.invoice_status(status_id),
--     key_number VARCHAR(50) NOT NULL UNIQUE,
--     consecutive_number VARCHAR(20) NOT NULL,
--     payment_method VARCHAR(2) NOT NULL DEFAULT '01',
--     credit_days VARCHAR(10),
--     xml_signed TEXT,
--     hacienda_response_xml TEXT,
--     hacienda_response_date TIMESTAMP,
--     check_attempts INT NOT NULL DEFAULT 0,
--     next_check_at TIMESTAMP,
--     created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
--     updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
-- );
-- CREATE INDEX idx_electronic_sale_invoice_sale_id ON pos_schema.electronic_sale_invoice(sale_id);
-- CREATE INDEX idx_electronic_sale_invoice_key_number ON pos_schema.electronic_sale_invoice(key_number);
-- CREATE INDEX idx_electronic_sale_invoice_created_at ON pos_schema.electronic_sale_invoice(created_at);
-- CREATE INDEX idx_electronic_invoice_pending_check ON pos_schema.electronic_sale_invoice(next_check_at) WHERE status_id = 1;
--
-- CREATE TABLE pos_schema.electronic_sale_invoice_items (
--     electronic_sale_invoice_item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
--     electronic_sale_invoice_id UUID NOT NULL REFERENCES pos_schema.electronic_sale_invoice(electronic_sale_invoice_id) ON DELETE CASCADE,
--     tenant_id UUID NOT NULL,
--     product_variant_id UUID,
--     sale_item_id uuid NOT NULL REFERENCES pos_schema.sale_item(sale_item_id) ON DELETE CASCADE,
--     line_number INTEGER NOT NULL,
--     discount_amount NUMERIC(18,5) DEFAULT 0,
--     discount_nature VARCHAR(80),
--     tax_rate_id INTEGER REFERENCES general_schema.tax_rate(tax_rate_id),
--     tax_exoneration_id INTEGER REFERENCES general_schema.tax_exoneration(exoneration_id),
--     created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
--     updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
--     CONSTRAINT fk_electronic_item_product_variant FOREIGN KEY (tenant_id, product_variant_id)
--         REFERENCES general_schema.product_variant(tenant_id, product_variant_id) ON DELETE SET NULL
-- );
-- CREATE INDEX idx_electronic_invoice_items_invoice ON pos_schema.electronic_sale_invoice_items(electronic_sale_invoice_id);
-- CREATE INDEX idx_electronic_invoice_items_variant ON pos_schema.electronic_sale_invoice_items(tenant_id, product_variant_id);
--
-- ALTER TABLE pos_schema.return_transaction ADD COLUMN electronic_sale_invoice_id uuid;
-- ALTER TABLE pos_schema.return_transaction
--     ADD CONSTRAINT return_transaction_electronic_sale_invoice_id_fkey
--     FOREIGN KEY (electronic_sale_invoice_id)
--     REFERENCES pos_schema.electronic_sale_invoice(electronic_sale_invoice_id)
--     ON DELETE CASCADE;
-- ALTER TABLE pos_schema.return_transaction
--     ADD CONSTRAINT chk_return_transaction_invoice CHECK (
--         digital_sale_invoice_id IS NOT NULL OR electronic_sale_invoice_id IS NOT NULL
--     );
