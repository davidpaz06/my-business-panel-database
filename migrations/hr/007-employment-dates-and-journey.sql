-- ============================================================
-- Migracion: 007-employment-dates-and-journey
-- Contexto: Migracion normativa Costa Rica -> Venezuela (LOTTT).
--   Agrega al empleado las fechas y causal de terminacion de la
--   relacion laboral, y al contrato el tipo de jornada.
-- Por que:
--   1. La antiguedad es el insumo central del Art. 142 (prestaciones)
--      y no se podia derivar: employee no tenia fecha de ingreso
--      propia ni fecha de egreso.
--   2. El Art. 92 (indemnizacion por despido injustificado) exige
--      distinguir la causal de terminacion.
--   3. contract.end_date era NOT NULL, lo que forzaba todo contrato
--      a plazo fijo. En Venezuela el contrato por tiempo indefinido
--      es la regla general, por lo que la columna pasa a NULLABLE.
--   4. El Art. 173 fija limites de jornada distintos segun sea
--      diurna, nocturna o mixta; sin el tipo de jornada no se puede
--      determinar a partir de que hora una hora es extraordinaria.
-- Base legal: Arts. 92, 142, 173, 175, 176.
-- Autor/Fecha: 2026-08-27
-- Incluye backfill de filas existentes (mismo criterio que
--   migrations/pos/002-add-sale-collection-multicurrency.sql).
-- ============================================================

-- ------------------------------------------------------------
-- 1. Fechas y causal de terminacion en employee
-- ------------------------------------------------------------

ALTER TABLE hr_schema.employee
	ADD COLUMN IF NOT EXISTS hire_date DATE,
	ADD COLUMN IF NOT EXISTS termination_date DATE,
	ADD COLUMN IF NOT EXISTS termination_type VARCHAR(30),
	ADD COLUMN IF NOT EXISTS termination_reason TEXT;

COMMENT ON COLUMN hr_schema.employee.hire_date IS
	'Fecha de ingreso efectiva. Base del computo de antiguedad (Art. 142). Se desnormaliza desde contract.start_date porque un trabajador puede encadenar contratos sin perder antiguedad.';

COMMENT ON COLUMN hr_schema.employee.termination_date IS
	'Fecha de egreso. NULL = relacion activa. Dispara el plazo de 5 dias del Art. 142.f para el pago de prestaciones.';

COMMENT ON COLUMN hr_schema.employee.termination_type IS
	'Causal de terminacion. despido_injustificado activa la indemnizacion del Art. 92 (monto igual a las prestaciones). fallecimiento activa el reparto entre herederos del Art. 145.';

-- Backfill: los empleados existentes toman la fecha de inicio de su contrato.
UPDATE hr_schema.employee e
SET hire_date = c.start_date
FROM hr_schema.contract c
WHERE e.contract_id = c.contract_id
	AND e.hire_date IS NULL;

ALTER TABLE hr_schema.employee
	ALTER COLUMN hire_date SET NOT NULL;

DO $$
BEGIN
	IF NOT EXISTS (
		SELECT 1 FROM pg_constraint WHERE conname = 'chk_employee_termination_type'
	) THEN
		ALTER TABLE hr_schema.employee
			ADD CONSTRAINT chk_employee_termination_type
			CHECK (termination_type IS NULL OR termination_type IN (
				'despido_injustificado',
				'despido_justificado',
				'renuncia',
				'causa_ajena_al_trabajador',
				'vencimiento_contrato',
				'fallecimiento'
			));
	END IF;

	IF NOT EXISTS (
		SELECT 1 FROM pg_constraint WHERE conname = 'chk_employee_termination_coherente'
	) THEN
		ALTER TABLE hr_schema.employee
			ADD CONSTRAINT chk_employee_termination_coherente
			CHECK (
				(termination_date IS NULL AND termination_type IS NULL)
				OR (termination_date IS NOT NULL AND termination_type IS NOT NULL)
			);
	END IF;

	IF NOT EXISTS (
		SELECT 1 FROM pg_constraint WHERE conname = 'chk_employee_fechas_relacion'
	) THEN
		ALTER TABLE hr_schema.employee
			ADD CONSTRAINT chk_employee_fechas_relacion
			CHECK (termination_date IS NULL OR termination_date >= hire_date);
	END IF;
END $$;

-- Indice para localizar egresos pendientes de liquidacion.
CREATE INDEX IF NOT EXISTS idx_employee_termination_date
	ON hr_schema.employee (termination_date)
	WHERE termination_date IS NOT NULL;

-- ------------------------------------------------------------
-- 2. Contrato indefinido y tipo de jornada
-- ------------------------------------------------------------

-- El contrato por tiempo indefinido es la regla general en Venezuela.
ALTER TABLE hr_schema.contract
	ALTER COLUMN end_date DROP NOT NULL;

COMMENT ON COLUMN hr_schema.contract.end_date IS
	'Fecha de vencimiento. NULL = contrato por tiempo indefinido (regla general en Venezuela).';

ALTER TABLE hr_schema.contract
	ADD COLUMN IF NOT EXISTS journey_type VARCHAR(10),
	ADD COLUMN IF NOT EXISTS weekly_hours NUMERIC(5, 2);

COMMENT ON COLUMN hr_schema.contract.journey_type IS
	'Tipo de jornada (Art. 173): diurna (5:00-19:00, 8h/40h), nocturna (19:00-5:00, 7h/35h), mixta (7.5h/37.5h). Si la jornada mixta tiene mas de 4 horas nocturnas se reputa nocturna en su totalidad.';

COMMENT ON COLUMN hr_schema.contract.weekly_hours IS
	'Horas semanales pactadas. No puede superar el maximo legal del journey_type salvo los regimenes de excepcion de los Arts. 175 y 176.';

-- Backfill: los contratos existentes se asumen de jornada diurna.
UPDATE hr_schema.contract
SET journey_type = 'diurna'
WHERE journey_type IS NULL;

UPDATE hr_schema.contract
SET weekly_hours = 40
WHERE weekly_hours IS NULL;

ALTER TABLE hr_schema.contract
	ALTER COLUMN journey_type SET NOT NULL,
	ALTER COLUMN journey_type SET DEFAULT 'diurna',
	ALTER COLUMN weekly_hours SET NOT NULL,
	ALTER COLUMN weekly_hours SET DEFAULT 40;

DO $$
BEGIN
	IF NOT EXISTS (
		SELECT 1 FROM pg_constraint WHERE conname = 'chk_contract_journey_type'
	) THEN
		ALTER TABLE hr_schema.contract
			ADD CONSTRAINT chk_contract_journey_type
			CHECK (journey_type IN ('diurna', 'nocturna', 'mixta'));
	END IF;

	IF NOT EXISTS (
		SELECT 1 FROM pg_constraint WHERE conname = 'chk_contract_weekly_hours'
	) THEN
		ALTER TABLE hr_schema.contract
			ADD CONSTRAINT chk_contract_weekly_hours
			CHECK (weekly_hours > 0 AND weekly_hours <= 42);
	END IF;
END $$;

-- ============================================================
-- ROLLBACK (documentacion; no se ejecuta automaticamente)
-- ============================================================
-- ALTER TABLE hr_schema.contract DROP CONSTRAINT IF EXISTS chk_contract_weekly_hours;
-- ALTER TABLE hr_schema.contract DROP CONSTRAINT IF EXISTS chk_contract_journey_type;
-- ALTER TABLE hr_schema.contract DROP COLUMN IF EXISTS weekly_hours;
-- ALTER TABLE hr_schema.contract DROP COLUMN IF EXISTS journey_type;
-- ALTER TABLE hr_schema.contract ALTER COLUMN end_date SET NOT NULL;
-- DROP INDEX IF EXISTS hr_schema.idx_employee_termination_date;
-- ALTER TABLE hr_schema.employee DROP CONSTRAINT IF EXISTS chk_employee_fechas_relacion;
-- ALTER TABLE hr_schema.employee DROP CONSTRAINT IF EXISTS chk_employee_termination_coherente;
-- ALTER TABLE hr_schema.employee DROP CONSTRAINT IF EXISTS chk_employee_termination_type;
-- ALTER TABLE hr_schema.employee DROP COLUMN IF EXISTS termination_reason;
-- ALTER TABLE hr_schema.employee DROP COLUMN IF EXISTS termination_type;
-- ALTER TABLE hr_schema.employee DROP COLUMN IF EXISTS termination_date;
-- ALTER TABLE hr_schema.employee DROP COLUMN IF EXISTS hire_date;
