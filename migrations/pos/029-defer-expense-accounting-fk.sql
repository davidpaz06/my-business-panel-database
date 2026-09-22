-- ============================================================
-- Migracion: 029-defer-expense-accounting-fk
-- Contexto: bootstrap fresco (backup/database_backup.sql) fallaba por
--   completo con "schema accounting_schema does not exist". La FK
--   inline de pos_schema.expense.accounting_expense_id hacia
--   accounting_schema.expense se ejecutaba durante la carga de
--   pos_schema, pero accounting_schema carga AL FINAL (orden:
--   general -> pos -> purchase -> inventory -> hr -> accounting).
--   Al estar todo el bootstrap dentro de una sola transaccion, este
--   error abortaba y hacia ROLLBACK de TODO el schema, no solo de
--   pos_schema.
-- Por que: la tabla ya existia en produccion con esta FK inline
--   (nunca fallo porque nadie habia reconstruido desde cero). Se
--   sigue aqui el mismo patron ya usado para
--   general_schema.product_variant -> purchase_schema.supplier: la
--   columna se crea sin REFERENCES y la FK se agrega por separado
--   una vez que accounting_schema ya existe (ver
--   build-bootstrap.ps1, bloque CROSS-SCHEMA CONSTRAINTS accounting).
-- Actualizacion 2026-09-18: se detecto que algunos entornos (staging
--   incluido) corrieron migraciones fuera de orden y nunca llegaron a
--   ejecutar migrations/pos/003-expense-fixed-variable-and-accounting-link.sql,
--   por lo que la columna accounting_expense_id no existe ahi en
--   absoluto (no es solo la FK inline la que sobra). Esta migracion
--   ahora crea la columna si falta (IF NOT EXISTS, igual que 003) para
--   que sea autosuficiente sin importar el historico de cada entorno.
-- Autor/Fecha: 2026-09-18
-- ============================================================

ALTER TABLE pos_schema.expense
    ADD COLUMN IF NOT EXISTS accounting_expense_id UUID;

CREATE INDEX IF NOT EXISTS idx_expense_accounting_expense
    ON pos_schema.expense(accounting_expense_id)
    WHERE accounting_expense_id IS NOT NULL;

ALTER TABLE pos_schema.expense
    DROP CONSTRAINT IF EXISTS expense_accounting_expense_id_fkey;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'fk_expense_accounting_expense'
    ) THEN
        ALTER TABLE pos_schema.expense
            ADD CONSTRAINT fk_expense_accounting_expense
            FOREIGN KEY (accounting_expense_id) REFERENCES accounting_schema.expense(expense_id) ON DELETE SET NULL;
    END IF;
END $$;

-- Rollback (documentado, no automatico):
-- ALTER TABLE pos_schema.expense DROP CONSTRAINT IF EXISTS fk_expense_accounting_expense;
-- DROP INDEX IF EXISTS pos_schema.idx_expense_accounting_expense;
-- ALTER TABLE pos_schema.expense DROP COLUMN IF EXISTS accounting_expense_id;
-- -- Nota: revertir esto vuelve a romper un bootstrap desde cero, y borra
-- -- cualquier vinculo ya guardado entre gastos POS y su contraparte contable.
