-- ============================================================
-- Migracion: 009-payroll-concept-lottt-metadata
-- Contexto: Migracion normativa Costa Rica -> Venezuela (LOTTT).
--   Agrega trazabilidad legal a los conceptos de nomina y elimina
--   los artefactos especificos de Costa Rica.
-- Por que:
--   1. La "regla de oro" del calculo venezolano es que cada concepto
--      se calcula sobre una base salarial concreta y no
--      intercambiable: salario NORMAL para los conceptos del dia a
--      dia (recargos, vacaciones, bono vacacional) y salario
--      INTEGRAL para prestaciones e indemnizaciones (Arts. 104, 122).
--      Usar la base equivocada es el error de calculo mas comun, por
--      lo que la base deja de ser implicita en el codigo y pasa a ser
--      un dato del concepto.
--   2. El recibo de pago debe ser auditable y desglosado (Art. 106).
--      Guardar el articulo en el concepto permite emitir el recibo y
--      defender el calculo ante un reclamo laboral (prescripcion de
--      10 anios para prestaciones, Art. 51).
--   3. hr_schema.generate_monthly_ccss se elimina: es especifica de
--      la Caja Costarricense de Seguro Social y ademas estaba rota
--      (referenciaba las columnas ccss_employee_deduction,
--      ccss_tenant_deduction y paysheet.payment_day, ninguna de las
--      cuales existe en el esquema actual).
-- Base legal: Arts. 51, 104, 106, 122.
-- Autor/Fecha: 2026-08-27
-- DDL ONLY. Los conceptos LOTTT se siembran en
--   seeds/catalog/hr/004-insert-default-payroll-concepts.sql
-- ============================================================

-- ------------------------------------------------------------
-- 1. Trazabilidad legal y base salarial en los conceptos
-- ------------------------------------------------------------

ALTER TABLE hr_schema.payroll_concept
	ADD COLUMN IF NOT EXISTS article VARCHAR(20),
	ADD COLUMN IF NOT EXISTS salary_basis VARCHAR(10);

ALTER TABLE hr_schema.payroll_concept_template
	ADD COLUMN IF NOT EXISTS article VARCHAR(20),
	ADD COLUMN IF NOT EXISTS salary_basis VARCHAR(10),
	ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

COMMENT ON COLUMN hr_schema.payroll_concept_template.is_active IS
	'Estado con el que el concepto se provisiona al tenant. FALSE para conceptos definidos pero no liberados: hoy las retenciones venezolanas (IVSS, INCES, FAOV, Paro Forzoso, ISLR), que carecen de especificacion de calculo y se activan cuando se defina.';

COMMENT ON COLUMN hr_schema.payroll_concept.article IS
	'Articulo de la LOTTT que fundamenta el concepto (ej. 117, 118, 142.b, 190). Se imprime en el desglose del recibo (Art. 106).';

COMMENT ON COLUMN hr_schema.payroll_concept.salary_basis IS
	'Base salarial sobre la que se calcula: normal (Art. 104) para recargos, vacaciones y bono vacacional; integral (Art. 122) para prestaciones e indemnizaciones. Nunca intercambiables.';

COMMENT ON COLUMN hr_schema.payroll_concept_template.article IS
	'Articulo de la LOTTT que fundamenta el concepto. Se copia al tenant via provision_tenant_payroll_concepts().';

COMMENT ON COLUMN hr_schema.payroll_concept_template.salary_basis IS
	'Base salarial: normal (Art. 104) o integral (Art. 122).';

-- Los conceptos existentes son de Costa Rica y seran reemplazados por
-- el reseed. Se les asigna base normal para poder aplicar el NOT NULL.
UPDATE hr_schema.payroll_concept
SET salary_basis = 'normal'
WHERE salary_basis IS NULL;

UPDATE hr_schema.payroll_concept_template
SET salary_basis = 'normal'
WHERE salary_basis IS NULL;

ALTER TABLE hr_schema.payroll_concept
	ALTER COLUMN salary_basis SET NOT NULL,
	ALTER COLUMN salary_basis SET DEFAULT 'normal';

ALTER TABLE hr_schema.payroll_concept_template
	ALTER COLUMN salary_basis SET NOT NULL,
	ALTER COLUMN salary_basis SET DEFAULT 'normal';

DO $$
BEGIN
	IF NOT EXISTS (
		SELECT 1 FROM pg_constraint WHERE conname = 'chk_payroll_concept_salary_basis'
	) THEN
		ALTER TABLE hr_schema.payroll_concept
			ADD CONSTRAINT chk_payroll_concept_salary_basis
			CHECK (salary_basis IN ('normal', 'integral'));
	END IF;

	IF NOT EXISTS (
		SELECT 1 FROM pg_constraint WHERE conname = 'chk_payroll_concept_template_salary_basis'
	) THEN
		ALTER TABLE hr_schema.payroll_concept_template
			ADD CONSTRAINT chk_payroll_concept_template_salary_basis
			CHECK (salary_basis IN ('normal', 'integral'));
	END IF;
END $$;

COMMENT ON TABLE hr_schema.payroll_concept_template IS
	'Plantilla de conceptos de nomina (Venezuela, LOTTT). Copiada a payroll_concept por tenant via provision_tenant_payroll_concepts(). Los valores percentage se almacenan como fraccion (ej. 0.30 = 30%).';

-- ------------------------------------------------------------
-- 2. Baja de artefactos de Costa Rica
-- ------------------------------------------------------------

-- Especifica de la CCSS y ademas rota: referencia columnas inexistentes.
-- Su equivalente venezolano (retenciones IVSS/INCES/FAOV) requiere una
-- especificacion propia que aun no existe.
DROP FUNCTION IF EXISTS hr_schema.generate_monthly_ccss(INTEGER, INTEGER);

-- ============================================================
-- ROLLBACK (documentacion; no se ejecuta automaticamente)
-- ============================================================
-- La funcion generate_monthly_ccss se restaura desde
--   functions/hr/hr_functions.sql en el commit anterior a esta migracion.
-- ALTER TABLE hr_schema.payroll_concept_template DROP COLUMN IF EXISTS is_active;
-- ALTER TABLE hr_schema.payroll_concept_template DROP CONSTRAINT IF EXISTS chk_payroll_concept_template_salary_basis;
-- ALTER TABLE hr_schema.payroll_concept DROP CONSTRAINT IF EXISTS chk_payroll_concept_salary_basis;
-- ALTER TABLE hr_schema.payroll_concept_template DROP COLUMN IF EXISTS salary_basis;
-- ALTER TABLE hr_schema.payroll_concept_template DROP COLUMN IF EXISTS article;
-- ALTER TABLE hr_schema.payroll_concept DROP COLUMN IF EXISTS salary_basis;
-- ALTER TABLE hr_schema.payroll_concept DROP COLUMN IF EXISTS article;
