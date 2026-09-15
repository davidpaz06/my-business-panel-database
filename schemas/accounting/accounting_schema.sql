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
    account_code VARCHAR(20),
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
