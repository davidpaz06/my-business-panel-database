-- Migration: 003-expense-fixed-variable-and-accounting-link
-- What:  Three structural changes to pos_schema.expense_type and pos_schema.expense:
--        1. Add is_fixed to expense_type to classify expense types as fixed or variable.
--        2. Add currency_id to expense to support multicurrency amounts (CRC/USD/other).
--        3. Add accounting_expense_id to expense to link a POS-registered expense with
--           its counterpart record in accounting_schema.expense.
-- Why:   The finances module (Task 1) requires expenses to be separable into fixed vs
--        variable (R1). POS spontaneous expenses (variable by nature) must integrate
--        with the accounting expense subsystem without breaking the existing POS flow.
--        Multicurrency is required because tenants may operate in USD and display amounts
--        in CRC using the tenant-configured exchange rate.
-- Context: pos_schema.expense_type is the POS catalog of expense types (employee-facing).
--          accounting_schema.expense is the full accounting record (finance module-facing).
--          The link (accounting_expense_id) lets the finance view aggregate both sources.

-- ─────────────────────────────────────────────────────────────────────────────
-- FORWARD MIGRATION
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Classify expense types as fixed or variable
ALTER TABLE pos_schema.expense_type
    ADD COLUMN IF NOT EXISTS is_fixed BOOLEAN NOT NULL DEFAULT TRUE;

-- 2. Support multicurrency on POS expenses
ALTER TABLE pos_schema.expense
    ADD COLUMN IF NOT EXISTS currency_id INTEGER
        REFERENCES general_schema.currency(currency_id) ON DELETE SET NULL;

-- 3. Link POS expense to its accounting counterpart
ALTER TABLE pos_schema.expense
    ADD COLUMN IF NOT EXISTS accounting_expense_id UUID
        REFERENCES accounting_schema.expense(expense_id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_expense_accounting_expense
    ON pos_schema.expense(accounting_expense_id)
    WHERE accounting_expense_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (do not run; documentation only)
-- ─────────────────────────────────────────────────────────────────────────────
-- DROP INDEX IF EXISTS pos_schema.idx_expense_accounting_expense;
-- ALTER TABLE pos_schema.expense DROP COLUMN IF EXISTS accounting_expense_id;
-- ALTER TABLE pos_schema.expense DROP COLUMN IF EXISTS currency_id;
-- ALTER TABLE pos_schema.expense_type DROP COLUMN IF EXISTS is_fixed;
