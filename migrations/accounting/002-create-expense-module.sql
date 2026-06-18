-- ============================================================
-- Migración: 002-create-expense-module.sql
-- Schema:    accounting_schema
-- Contexto:  Crea las tablas del módulo de gastos contables:
--            expense_category_template, expense_category, expense,
--            fiscal_period. Necesarias para los endpoints analíticos
--            de /expense/analytics/*.
-- ============================================================

SET search_path TO accounting_schema;

-- -------------------------------------------------------
-- PLANTILLA DE CATEGORÍAS DE GASTO
-- (DDL aquí para que exista antes de correr el seed 005)
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS accounting_schema.expense_category_template (
    template_id   SERIAL PRIMARY KEY,
    name          VARCHAR(100) NOT NULL UNIQUE,
    account_code  VARCHAR(20)  NOT NULL,
    is_fixed      BOOLEAN      DEFAULT TRUE,
    parent_name   VARCHAR(100),
    created_at    TIMESTAMP    DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE accounting_schema.expense_category_template IS
    'Plantilla de categorías de gasto basada en NIIF para PYMES (Costa Rica).
     Se copia a expense_category por tenant vía provisionCategories().';

-- -------------------------------------------------------
-- CATEGORÍAS DE GASTO (por tenant)
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS accounting_schema.expense_category (
    category_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id          UUID         NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    name               VARCHAR(100) NOT NULL,
    account_code       VARCHAR(20)  NOT NULL,
    parent_category_id UUID         REFERENCES accounting_schema.expense_category(category_id) ON DELETE SET NULL,
    is_fixed           BOOLEAN      DEFAULT TRUE,
    is_active          BOOLEAN      DEFAULT TRUE,
    created_at         TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(tenant_id, name),
    CONSTRAINT chk_no_self_parent_cat CHECK (category_id != parent_category_id)
);

CREATE INDEX IF NOT EXISTS idx_expense_cat_tenant
    ON accounting_schema.expense_category(tenant_id);
CREATE INDEX IF NOT EXISTS idx_expense_cat_active
    ON accounting_schema.expense_category(tenant_id, is_active)
    WHERE is_active = TRUE;

COMMENT ON TABLE accounting_schema.expense_category IS
    'Categorías de gasto por tenant. is_fixed=TRUE para gastos fijos, FALSE para variables.';
COMMENT ON COLUMN accounting_schema.expense_category.account_code IS
    'Referencia a chart_of_accounts.account_code del tenant. Determina la cuenta débito en asientos contables.';

-- -------------------------------------------------------
-- GASTOS
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS accounting_schema.expense (
    expense_id       UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID           NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    branch_id        UUID           NOT NULL REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
    category_id      UUID           NOT NULL REFERENCES accounting_schema.expense_category(category_id),
    description      TEXT,
    amount           NUMERIC(14,4)  NOT NULL CHECK (amount > 0),
    tax_amount       NUMERIC(14,4)  NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    total_amount     NUMERIC(14,4)  NOT NULL CHECK (total_amount > 0),
    currency_id      INTEGER        NOT NULL REFERENCES general_schema.currency(currency_id),
    expense_date     DATE           NOT NULL DEFAULT CURRENT_DATE,
    payment_method   VARCHAR(20)    NOT NULL DEFAULT 'CASH'
        CHECK (payment_method IN ('CASH', 'BANK', 'CREDIT_CARD', 'CHECK', 'TRANSFER')),
    reference_number VARCHAR(50),
    notes            TEXT,
    created_by       UUID           REFERENCES general_schema.users(user_id) ON DELETE SET NULL,
    created_at       TIMESTAMP      DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP      DEFAULT CURRENT_TIMESTAMP
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
    'Registros de gastos individuales. Cada gasto genera un asiento contable vía generateExpenseJournal().';
COMMENT ON COLUMN accounting_schema.expense.payment_method IS
    'Determina la cuenta crédito en el asiento: CASH→Caja General, BANK/TRANSFER/CHECK→Bancos, CREDIT_CARD→CxP.';

-- -------------------------------------------------------
-- PERÍODO FISCAL
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS accounting_schema.fiscal_period (
    period_id  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id  UUID        NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    name       VARCHAR(100) NOT NULL,
    start_date DATE        NOT NULL,
    end_date   DATE        NOT NULL,
    is_closed  BOOLEAN     DEFAULT FALSE,
    closed_at  TIMESTAMP,
    created_at TIMESTAMP   DEFAULT CURRENT_TIMESTAMP,

    UNIQUE(tenant_id, name),
    CONSTRAINT chk_period_dates CHECK (end_date > start_date)
);

CREATE INDEX IF NOT EXISTS idx_fiscal_period_tenant
    ON accounting_schema.fiscal_period(tenant_id);
CREATE INDEX IF NOT EXISTS idx_fiscal_period_dates
    ON accounting_schema.fiscal_period(tenant_id, start_date, end_date);

COMMENT ON TABLE accounting_schema.fiscal_period IS
    'Períodos fiscales para reportes financieros. is_closed impide modificar asientos dentro del período.';

-- ============================================================
-- ROLLBACK (comentado — no ejecutar automáticamente)
-- DROP TABLE IF EXISTS accounting_schema.expense CASCADE;
-- DROP TABLE IF EXISTS accounting_schema.expense_category CASCADE;
-- DROP TABLE IF EXISTS accounting_schema.expense_category_template CASCADE;
-- DROP TABLE IF EXISTS accounting_schema.fiscal_period CASCADE;
-- ============================================================
