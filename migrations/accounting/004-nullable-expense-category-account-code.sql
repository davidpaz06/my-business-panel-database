-- ============================================================
-- Migración: 004-nullable-expense-category-account-code.sql
-- Schema:    accounting_schema
-- Contexto:  El campo account_code en expense_category era NOT NULL
--            pero el flujo de alta de categorías todavía no requiere
--            que el usuario conozca el código contable. Se elimina la
--            restricción NOT NULL para permitir categorías sin código
--            hasta que se asigne desde el catálogo de cuentas.
-- ============================================================

ALTER TABLE accounting_schema.expense_category
    ALTER COLUMN account_code DROP NOT NULL;

-- ============================================================
-- ROLLBACK (comentado)
--
-- ALTER TABLE accounting_schema.expense_category
--     ALTER COLUMN account_code SET NOT NULL;
--
-- Nota: el rollback fallará si existen filas con account_code IS NULL.
-- Asignar un valor antes de ejecutar:
--   UPDATE accounting_schema.expense_category
--   SET account_code = 'PENDIENTE'
--   WHERE account_code IS NULL;
-- ============================================================
