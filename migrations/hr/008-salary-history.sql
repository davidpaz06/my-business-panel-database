-- ============================================================
-- Migracion: 008-salary-history
-- Contexto: Migracion normativa Costa Rica -> Venezuela (LOTTT).
--   Crea el historial de salarios por empleado con vigencia temporal.
-- Por que: el Art. 122 define el salario integral como el ULTIMO
--   salario mas la alicuota de utilidades y la alicuota de bono
--   vacacional. El Art. 142.a exige ademas el salario integral
--   VIGENTE EN CADA TRIMESTRE para el deposito de la garantia, y el
--   Art. 142.b/c exige el ULTIMO salario integral para los dias
--   adicionales y el retroactivo. Con un unico contract.base_salary
--   mutable no se puede reconstruir ninguno de los dos: al cambiar
--   el sueldo se perdia la base historica y los depositos previos
--   quedaban sin respaldo auditable.
--   La LOTTT fija prescripcion de 10 anios para prestaciones
--   (Art. 51), por lo que el historial debe conservarse.
-- Base legal: Arts. 51, 104, 122, 142.
-- Autor/Fecha: 2026-08-27
-- NOTA: incluye un backfill de datos existentes (INSERT al final).
--   No es data de catalogo (esa vive en seeds/): es migracion de
--   datos ya presentes, mismo caso que
--   migrations/accounting/003-migrate-pos-expenses-to-accounting.sql.
--   Es idempotente por el NOT EXISTS.
-- ============================================================

CREATE TABLE IF NOT EXISTS hr_schema.salary_history (
	salary_history_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id) ON DELETE CASCADE,
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
	monthly_salary NUMERIC(18, 4) NOT NULL,
	valid_from DATE NOT NULL,
	valid_to DATE,
	reason VARCHAR(120),
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
	CONSTRAINT uq_salary_history_vigencia UNIQUE (employee_id, valid_from),
	CONSTRAINT chk_salary_history_positive CHECK (monthly_salary > 0),
	CONSTRAINT chk_salary_history_vigencia CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

COMMENT ON TABLE hr_schema.salary_history IS
	'Historial de salario mensual por empleado con vigencia temporal. Fuente del salario normal (Art. 104) y base del salario integral (Art. 122). valid_to NULL = vigente.';

COMMENT ON COLUMN hr_schema.salary_history.monthly_salary IS
	'Salario mensual. El salario diario es este monto entre 30 (Art. 113); el salario hora es el diario entre las horas de la jornada.';

COMMENT ON COLUMN hr_schema.salary_history.reason IS
	'Motivo del cambio para auditoria: aumento, decreto de salario minimo, ajuste por convencion colectiva, promocion.';

CREATE INDEX IF NOT EXISTS idx_salary_history_lookup
	ON hr_schema.salary_history (employee_id, valid_from DESC);

CREATE INDEX IF NOT EXISTS idx_salary_history_tenant
	ON hr_schema.salary_history (tenant_id);

-- Backfill: cada empleado existente arranca su historial con el
-- salario de su contrato vigente, desde su fecha de ingreso.
INSERT INTO hr_schema.salary_history (employee_id, tenant_id, monthly_salary, valid_from, reason)
SELECT
	e.employee_id,
	e.tenant_id,
	c.base_salary,
	e.hire_date,
	'Backfill migracion 008: salario inicial del contrato'
FROM hr_schema.employee e
INNER JOIN hr_schema.contract c ON c.contract_id = e.contract_id
WHERE c.base_salary > 0
	AND NOT EXISTS (
		SELECT 1 FROM hr_schema.salary_history sh
		WHERE sh.employee_id = e.employee_id
	);

-- ============================================================
-- Consulta canonica de resolucion (referencia para el backend):
--   SELECT monthly_salary FROM hr_schema.salary_history
--   WHERE employee_id = $1
--     AND valid_from <= $2 AND (valid_to IS NULL OR valid_to >= $2)
--   ORDER BY valid_from DESC LIMIT 1;
-- ============================================================

-- ============================================================
-- ROLLBACK (documentacion; no se ejecuta automaticamente)
-- ============================================================
-- DROP INDEX IF EXISTS hr_schema.idx_salary_history_tenant;
-- DROP INDEX IF EXISTS hr_schema.idx_salary_history_lookup;
-- DROP TABLE IF EXISTS hr_schema.salary_history;
