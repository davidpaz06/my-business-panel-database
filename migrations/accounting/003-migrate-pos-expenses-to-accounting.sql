-- ============================================================
-- Migración: 003-migrate-pos-expenses-to-accounting.sql
-- Schema:    accounting_schema (lee desde pos_schema)
-- Contexto:  Unifica las tablas de gasto del ERP. Antes del módulo
--            FNZ, los gastos vivían en pos_schema.expense_type y
--            pos_schema.expense (flujo de aprobación POS). Esta
--            migración consolida esos registros en las tablas
--            contables accounting_schema.expense_category y
--            accounting_schema.expense para que el módulo de
--            Finanzas muestre datos históricos completos.
--            Las tablas POS se conservan para compatibilidad hacia
--            atrás con el módulo de caja.
-- ============================================================

-- -------------------------------------------------------
-- PASO 1: Migrar tipos de gasto POS → expense_category
--
-- Mapeo:
--   expense_type.tenant_id          → expense_category.tenant_id
--   expense_type.expense_type_name  → expense_category.name
--   account_code generado           → '5-9-NNN' (rango reservado migración POS)
--   is_fixed = FALSE                → gastos POS tratados como variables
--
-- Se omite si ya existe categoría con el mismo nombre para ese tenant
-- (la provisión previa desde expense_category_template puede generar
--  coincidencias de nombre — en ese caso se reutiliza la categoría existente).
-- -------------------------------------------------------

INSERT INTO accounting_schema.expense_category
  (tenant_id, name, account_code, is_fixed, is_active)
SELECT
  et.tenant_id,
  et.expense_type_name,
  '5-9-' || LPAD(
    ROW_NUMBER() OVER (
      PARTITION BY et.tenant_id
      ORDER BY et.created_at, et.expense_type_id
    )::text,
    3, '0'
  ),
  FALSE,
  TRUE
FROM pos_schema.expense_type et
WHERE NOT EXISTS (
  SELECT 1
  FROM accounting_schema.expense_category ec
  WHERE ec.tenant_id = et.tenant_id
    AND ec.name = et.expense_type_name
);

-- -------------------------------------------------------
-- PASO 2: Migrar gastos aprobados POS → expense
--
-- Solo se migran registros con status = 'approved'.
-- Mapeo:
--   pos_schema.expense.expense_id       → notes ('pos:<uuid>') para trazabilidad
--   branch_id → general_schema.branch   → tenant_id
--   expense_type_name + tenant_id       → category_id (JOIN sobre categoría)
--   expense_amount                      → amount = total_amount (sin desglose de impuesto)
--   tax_amount                          = 0
--   currency_id                         = CRC (moneda base de Costa Rica)
--   expense_date                        = DATE(expense.created_at)
--   payment_method                      = 'CASH' (valor por defecto)
--   created_by                          = user_id
--
-- Idempotente: notes = 'pos:<expense_id>' identifica unívocamente cada
-- gasto migrado. Si la migración se corre dos veces, el NOT EXISTS lo filtra.
-- -------------------------------------------------------

INSERT INTO accounting_schema.expense
  (tenant_id, branch_id, category_id, description,
   amount, tax_amount, total_amount,
   currency_id, expense_date, payment_method,
   notes, created_by, created_at, updated_at)
SELECT
  b.tenant_id,
  e.branch_id,
  ec.category_id,
  et.expense_type_detail,
  e.expense_amount,
  0,
  e.expense_amount,
  (SELECT currency_id FROM general_schema.currency WHERE currency_code = 'CRC' LIMIT 1),
  DATE(e.created_at),
  'CASH',
  'pos:' || e.expense_id::text,
  e.user_id,
  e.created_at,
  e.updated_at
FROM pos_schema.expense e
INNER JOIN general_schema.branch b
  ON b.branch_id = e.branch_id
INNER JOIN pos_schema.expense_type et
  ON et.expense_type_id = e.expense_type_id
INNER JOIN accounting_schema.expense_category ec
  ON ec.tenant_id = b.tenant_id
  AND ec.name = et.expense_type_name
WHERE e.status = 'approved'
  AND e.expense_amount > 0
  AND NOT EXISTS (
    SELECT 1
    FROM accounting_schema.expense ae
    WHERE ae.notes = 'pos:' || e.expense_id::text
  );

-- ============================================================
-- ROLLBACK (comentado — no ejecutar automáticamente)
--
-- Elimina los registros migrados desde POS identificados por
-- el prefijo 'pos:' en el campo notes.
--
-- DELETE FROM accounting_schema.expense
-- WHERE notes LIKE 'pos:%';
--
-- DELETE FROM accounting_schema.expense_category
-- WHERE account_code LIKE '5-9-%'
--   AND NOT EXISTS (
--     SELECT 1 FROM accounting_schema.expense ae
--     WHERE ae.category_id = expense_category.category_id
--       AND ae.notes NOT LIKE 'pos:%'
--   );
-- ============================================================
