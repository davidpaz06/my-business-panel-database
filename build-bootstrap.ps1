# ======================================================
# BUILD CONSOLIDATED BOOTSTRAP SCRIPT
# ======================================================
# This script generates a single SQL file from all schema,
# function, and seed files for easy execution in any SQL client
# ======================================================

$outputFile = "backup/database_backup.sql"
$encoding = [System.Text.Encoding]::UTF8

# Crear carpeta backup si no existe
$backupDir = "backup"
if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    Write-Host "Created backup directory: $backupDir" -ForegroundColor Green
}

# Limpiar archivo de salida
if (Test-Path $outputFile) {
    Remove-Item $outputFile
    Write-Host "Previous backup removed" -ForegroundColor Gray
}

Write-Host "`nGenerating consolidated bootstrap file..." -ForegroundColor Cyan

# Header
@"
-- ======================================================
-- CONSOLIDATED BOOTSTRAP FILE
-- Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
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

"@ | Out-File -FilePath $outputFile -Encoding UTF8

# Función para agregar contenido de archivo
function Add-FileContent {
    param($filePath, $sectionName)
    
    if (Test-Path $filePath) {
        Write-Host "  [+] $sectionName" -ForegroundColor Green
        "`n-- =============================================" | Out-File -FilePath $outputFile -Append -Encoding UTF8
        "-- $sectionName" | Out-File -FilePath $outputFile -Append -Encoding UTF8
        "-- Source: $filePath" | Out-File -FilePath $outputFile -Append -Encoding UTF8
        "-- =============================================" | Out-File -FilePath $outputFile -Append -Encoding UTF8
        Get-Content $filePath -Encoding UTF8 | Out-File -FilePath $outputFile -Append -Encoding UTF8
        "`n" | Out-File -FilePath $outputFile -Append -Encoding UTF8
    } else {
        Write-Host "  [!] File not found: $filePath" -ForegroundColor Red
    }
}

# SCHEMAS
Write-Host "`nAdding schemas..." -ForegroundColor Yellow
Add-FileContent "schemas/general/general_schema.sql" "SCHEMA: GENERAL"
Add-FileContent "schemas/pos/pos_schema.sql" "SCHEMA: POS"
Add-FileContent "schemas/inventory/inventory_schema.sql" "SCHEMA: INVENTORY"
Add-FileContent "schemas/purchase/purchase_schema.sql" "SCHEMA: PURCHASE"

# Cross-schema FK applied after purchase_schema exists
Write-Host "  [+] Cross-schema constraints" -ForegroundColor Green
@"

-- =============================================
-- CROSS-SCHEMA CONSTRAINTS
-- Applied after all referenced schemas exist
-- =============================================
ALTER TABLE general_schema.product_variant
    ADD CONSTRAINT fk_product_variant_supplier
    FOREIGN KEY (supplier_id) REFERENCES purchase_schema.supplier(supplier_id) ON DELETE SET NULL;

"@ | Out-File -FilePath $outputFile -Append -Encoding UTF8

Add-FileContent "schemas/hr/hr_schema.sql" "SCHEMA: HR"
Add-FileContent "schemas/accounting/accounting_schema.sql" "SCHEMA: ACCOUNTING"

# FUNCTIONS
Write-Host "`nAdding functions..." -ForegroundColor Yellow
Add-FileContent "functions/general/general_functions.sql" "FUNCTIONS: GENERAL"
Add-FileContent "functions/pos/pos_functions.sql" "FUNCTIONS: POS"

# Check if inventory functions exist
if (Test-Path "functions/inventory/inventory_functions.sql") {
    Add-FileContent "functions/inventory/inventory_functions.sql" "FUNCTIONS: INVENTORY"
} else {
    Write-Host "  [i] No inventory functions file found (skipping)" -ForegroundColor Gray
}

Add-FileContent "functions/purchase/purchase_functions.sql" "FUNCTIONS: PURCHASE"
Add-FileContent "functions/hr/hr_functions.sql" "FUNCTIONS: HR"
Add-FileContent "functions/accounting/accounting_functions.sql" "FUNCTIONS: ACCOUNTING"

# SEEDS - GENERAL
Write-Host "`nAdding general catalog seeds..." -ForegroundColor Yellow
Add-FileContent "seeds/catalog/general/001-insert-regions.sql" "SEED: REGIONS"
Add-FileContent "seeds/catalog/general/002-insert-document-types.sql" "SEED: DOCUMENT TYPES"
Add-FileContent "seeds/catalog/general/003-insert-customer-segments.sql" "SEED: CUSTOMER SEGMENTS"
Add-FileContent "seeds/catalog/general/004-insert-customer_segment_margin_types.sql" "SEED: CUSTOMER SEGMENT MARGIN TYPES"
Add-FileContent "seeds/catalog/general/005-insert-roles.sql" "SEED: ROLES"
Add-FileContent "seeds/catalog/general/006-insert-currencies.sql" "SEED: CURRENCIES"
Add-FileContent "seeds/catalog/general/007-insert-tax-rates.sql" "SEED: TAX RATES"
Add-FileContent "seeds/catalog/general/008-insert-subscription-types.sql" "SEED: SUBSCRIPTION TYPES"
Add-FileContent "seeds/catalog/general/009-insert-payment_methods.sql" "SEED: PAYMENT METHODS"
Add-FileContent "seeds/catalog/general/010-insert-account-payable-status.sql" "SEED: ACCOUNT PAYABLE STATUS"
Add-FileContent "seeds/catalog/general/011-insert-account-payable-types.sql" "SEED: ACCOUNT PAYABLE TYPES"
Add-FileContent "seeds/catalog/general/012-insert-branch-locations.sql" "SEED: BRANCH LOCATIONS"
Add-FileContent "seeds/catalog/general/013-insert-account-receivable-status.sql" "SEED: ACCOUNT RECEIVABLE STATUS"
Add-FileContent "seeds/catalog/general/014-insert-account-receivable-types.sql" "SEED: ACCOUNT RECEIVABLE TYPES"

# SEEDS - POS
Write-Host "`nAdding POS catalog seeds..." -ForegroundColor Yellow
Add-FileContent "seeds/catalog/pos/001-insert-return-reason.sql" "SEED: RETURN REASONS"
Add-FileContent "seeds/catalog/pos/002-insert-return-status.sql" "SEED: RETURN STATUS"
Add-FileContent "seeds/catalog/pos/003-insert-promotion-types.sql" "SEED: PROMOTION TYPES"
Add-FileContent "seeds/catalog/pos/004-insert-score-redemption-status.sql" "SEED: SCORE REDEMPTION STATUS"
Add-FileContent "seeds/catalog/pos/005-insert-score-transaction-types.sql" "SEED: SCORE TRANSACTION TYPES"
Add-FileContent "seeds/catalog/pos/006-insert-sale-conditions.sql" "SEED: SALE CONDITIONS"
Add-FileContent "seeds/catalog/pos/007-insert-invoice-status.sql" "SEED: INVOICE STATUS"
Add-FileContent "seeds/catalog/pos/008-insert-collection-alert-types.sql" "SEED: COLLECTION ALERT TYPES"

# SEEDS - PURCHASE
Write-Host "`nAdding purchase catalog seeds..." -ForegroundColor Yellow
Add-FileContent "seeds/catalog/purchase/001-insert-purchase-order-status.sql" "SEED: PURCHASE ORDER STATUS"
Add-FileContent "seeds/catalog/purchase/002-insert-purchase-order-payment-alert-types.sql" "SEED: PAYMENT ALERT TYPES"

# SEEDS - INVENTORY
Write-Host "`nAdding inventory catalog seeds..." -ForegroundColor Yellow
Add-FileContent "seeds/catalog/inventory/001-insert-inventory_log_types.sql" "SEED: INVENTORY LOG TYPES"

# SEEDS - HR
Write-Host "`nAdding HR catalog seeds..." -ForegroundColor Yellow
Add-FileContent "seeds/catalog/hr/001-insert-payment-schedules.sql" "SEED: PAYMENT SCHEDULES"
Add-FileContent "seeds/catalog/hr/002-insert-paysheet-status.sql" "SEED: PAYSHEET STATUS"
Add-FileContent "seeds/catalog/hr/003-insert-holidays.sql" "SEED: HOLIDAYS"

# SEEDS - ACCOUNTING
Write-Host "`nAdding accounting catalog seeds..." -ForegroundColor Yellow
Add-FileContent "seeds/catalog/accounting/001-insert-account-types.sql" "SEED: ACCOUNTING ENTRY TYPES"
Add-FileContent "seeds/catalog/accounting/002-insert-journal-entry-statuses.sql" "SEED: JOURNAL ENTRY STATUSES"
Add-FileContent "seeds/catalog/accounting/003-insert-source-types.sql" "SEED: SOURCE TYPES"
Add-FileContent "seeds/catalog/accounting/004-insert-chart-of-accounts-template.sql" "SEED: CHART OF ACCOUNTS TEMPLATE"
Add-FileContent "seeds/catalog/accounting/005-insert-expense-category-template.sql" "SEED: EXPENSE CATEGORY TEMPLATE"

# INTEGRITY CHECKS
Write-Host "`nAdding integrity checks..." -ForegroundColor Yellow
@"

-- -----------------
-- INTEGRITY CHECKS
-- -----------------
DO `$`$
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
END `$`$;

COMMIT;

-- ======================================================
-- END OF CONSOLIDATED BOOTSTRAP FILE
-- ======================================================
"@ | Out-File -FilePath $outputFile -Append -Encoding UTF8

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Database backup generated successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Location: $outputFile" -ForegroundColor Cyan
Write-Host "Size: $((Get-Item $outputFile).Length / 1KB) KB" -ForegroundColor Gray

Write-Host "`nExecution options:" -ForegroundColor Yellow
Write-Host "  1. From psql:" -ForegroundColor White
Write-Host "     psql -U postgres -d mybusinesspaneldb -f $outputFile" -ForegroundColor Gray
Write-Host "  2. From pgAdmin/DBeaver:" -ForegroundColor White
Write-Host "     Open the file and execute the complete content" -ForegroundColor Gray
Write-Host "  3. Copy & paste:" -ForegroundColor White
Write-Host "     Copy content to any SQL client" -ForegroundColor Gray
Write-Host "`n" -ForegroundColor White