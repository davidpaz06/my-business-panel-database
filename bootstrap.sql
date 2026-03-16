
-- ======================================================
-- SCHEMA BOOTSTRAP FILE
-- ======================================================

\c mybusinesspaneldb;

BEGIN;

-- -----------------
-- DROP SCHEMAS
-- -----------------
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
\i schemas/general/general_schema.sql
\i schemas/pos/pos_schema.sql
\i schemas/inventory/inventory_schema.sql
\i schemas/purchase/purchase_schema.sql
\i schemas/hr/hr_schema.sql
\i schemas/accounting/accounting_schema.sql

-- -----------------
-- FUNCTIONS
-- -----------------
\i functions/general/general_functions.sql
\i functions/pos/pos_functions.sql
\i functions/inventory/inventory_functions.sql
\i functions/purchase/purchase_functions.sql
\i functions/hr/hr_functions.sql
\i functions/accounting/accounting_functions.sql

-- -----------------
-- SEEDS - CATALOG GENERAL
-- -----------------
\i seeds/catalog/general/001-insert-regions.sql
\i seeds/catalog/general/002-insert-document-types.sql
\i seeds/catalog/general/003-insert-customer-segments.sql
\i seeds/catalog/general/004-insert-customer_segment_margin_types.sql
\i seeds/catalog/general/005-insert-roles.sql
\i seeds/catalog/general/006-insert-currencies.sql
\i seeds/catalog/general/007-insert-tax-rates.sql
\i seeds/catalog/general/008-insert-subscription-types.sql
\i seeds/catalog/general/009-insert-payment_methods.sql
\i seeds/catalog/general/010-insert-account-payable-status.sql
\i seeds/catalog/general/011-insert-account-payable-types.sql

-- -----------------
-- SEEDS - CATALOG POS
-- -----------------
\i seeds/catalog/pos/001-insert-return-reason.sql
\i seeds/catalog/pos/002-insert-return-status.sql
\i seeds/catalog/pos/003-insert-promotion-types.sql
\i seeds/catalog/pos/004-insert-score-redemption-status.sql
\i seeds/catalog/pos/005-insert-score-transaction-types.sql
\i seeds/catalog/pos/006-insert-sale-conditions.sql
\i seeds/catalog/pos/007-insert-invoice-status.sql

-- -----------------
-- SEEDS - CATALOG PURCHASE
-- -----------------
\i seeds/catalog/purchase/001-insert-purchase-order-status.sql
\i seeds/catalog/purchase/002-insert-purchase-order-payment-alert-types.sql

-- -----------------
-- SEEDS - CATALOG INVENTORY
-- -----------------
\i seeds/catalog/inventory/001-insert-inventory_log_types.sql

-- -----------------
-- SEEDS - CATALOG HR
-- -----------------
\i seeds/catalog/hr/001-insert-payment-schedules.sql
\i seeds/catalog/hr/002-insert-paysheet-status.sql

-- -----------------
-- SEEDS - CATALOG ACCOUNTING
-- -----------------
\i seeds/catalog/accounting/001-insert-account-types.sql
\i seeds/catalog/accounting/002-insert-journal-entry-statuses.sql
\i seeds/catalog/accounting/003-insert-source-types.sql
\i seeds/catalog/accounting/004-insert-chart-of-accounts-template.sql

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
            'general_schema.product_category',  
            'general_schema.product',            
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
            'hr_schema.paysheet_status',
            'accounting_schema.account_type',
            'accounting_schema.journal_entry_status',
            'accounting_schema.source_type',
            'accounting_schema.chart_of_accounts_template'
        ])
    LOOP
        EXECUTE format('SELECT COUNT(*) FROM %s', v_table_name) INTO v_count;
        IF v_count = 0 THEN
            v_failed_tables := array_append(v_failed_tables, v_table_name);
        END IF;
    END LOOP;

    IF array_length(v_failed_tables, 1) > 0 THEN
        RAISE EXCEPTION 'Las siguientes tablas están vacías después del seeding: %',
            array_to_string(v_failed_tables, ', ');
    END IF;

    RAISE NOTICE 'Bootstrap completado exitosamente.';
END $$;

COMMIT;
