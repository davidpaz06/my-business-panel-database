-- ============================================================
-- Migracion: 014-vacation-period
-- Contexto: Migracion normativa Costa Rica -> Venezuela (LOTTT).
--   Crea el periodo vacacional por anio de servicio.
-- Por que: el sistema no tenia ninguna tabla de vacaciones. El
--   concepto CR se calculaba al vuelo dividiendo los ingresos de 50
--   semanas, y se pagaba en cada corrida de nomina porque no habia
--   donde registrar el devengo ni el disfrute. En Venezuela eso no
--   es viable:
--   1. Los dias se ESCALONAN por antiguedad (Art. 190): 15 dias
--      habiles al cumplir el primer anio, mas 1 dia por cada anio
--      sucesivo, con tope de 15 adicionales (maximo 30, alcanzado al
--      anio 16). El derecho NACE al cumplir el anio: antes es cero.
--   2. El bono vacacional (Art. 192) es un concepto distinto que se
--      paga en la oportunidad de las vacaciones: 15 dias mas 1 por
--      anio, tope 30. Tiene caracter salarial, por lo que alimenta
--      la alicuota del salario integral (Art. 122).
--   3. Hay que distinguir lo CAUSADO de lo DISFRUTADO: si la
--      relacion termina sin disfrutar las vacaciones causadas, se
--      pagan al salario normal de la terminacion (Art. 195).
--   Una fila por anio de servicio, no por solicitud, porque el
--   derecho se causa anualmente.
-- Base legal: Arts. 121, 190, 192, 195, 196.
-- Autor/Fecha: 2026-08-27
-- ============================================================

CREATE TABLE IF NOT EXISTS hr_schema.vacation_period (
	vacation_period_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id) ON DELETE CASCADE,
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
	service_year INTEGER NOT NULL,
	period_start DATE NOT NULL,
	period_end DATE NOT NULL,
	days_earned NUMERIC(5, 2) NOT NULL,
	bonus_days_earned NUMERIC(5, 2) NOT NULL,
	days_taken NUMERIC(5, 2) NOT NULL DEFAULT 0,
	enjoyed_from DATE,
	enjoyed_to DATE,
	normal_daily_salary NUMERIC(18, 4),
	paid_amount NUMERIC(18, 4),
	bonus_paid_amount NUMERIC(18, 4),
	is_fractional BOOLEAN NOT NULL DEFAULT FALSE,
	status VARCHAR(15) NOT NULL DEFAULT 'causado',
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
	CONSTRAINT uq_vacation_period_anio UNIQUE (employee_id, service_year),
	CONSTRAINT chk_vacation_period_fechas CHECK (period_end > period_start),
	CONSTRAINT chk_vacation_days_earned CHECK (days_earned >= 0 AND days_earned <= 30),
	CONSTRAINT chk_vacation_bonus_days CHECK (bonus_days_earned >= 0 AND bonus_days_earned <= 30),
	CONSTRAINT chk_vacation_days_taken CHECK (days_taken >= 0 AND days_taken <= days_earned),
	CONSTRAINT chk_vacation_status CHECK (status IN ('causado', 'disfrutando', 'disfrutado', 'pagado')),
	CONSTRAINT chk_vacation_disfrute CHECK (enjoyed_to IS NULL OR enjoyed_from IS NOT NULL)
);

COMMENT ON TABLE hr_schema.vacation_period IS
	'Periodo vacacional por anio de servicio. Separa lo causado (Art. 190) de lo disfrutado: las vacaciones causadas y no disfrutadas se pagan al terminar la relacion (Art. 195).';

COMMENT ON COLUMN hr_schema.vacation_period.service_year IS
	'Anio de servicio cumplido, base del escalonamiento. El derecho nace al cumplir el anio 1; antes de eso solo procede la fraccion del Art. 196.';

COMMENT ON COLUMN hr_schema.vacation_period.days_earned IS
	'Dias habiles causados (Art. 190): 15 al cumplir el primer anio, +1 por cada anio sucesivo, tope de 15 adicionales (maximo 30, alcanzado al anio 16).';

COMMENT ON COLUMN hr_schema.vacation_period.bonus_days_earned IS
	'Dias de bono vacacional (Art. 192): minimo 15 mas 1 por anio de servicio, tope 30. Tiene caracter salarial y alimenta la alicuota del salario integral (Art. 122).';

COMMENT ON COLUMN hr_schema.vacation_period.normal_daily_salary IS
	'Salario normal diario usado para el pago. Base legal: salario normal del mes anterior al disfrute (Art. 121). En terminacion, el de la fecha de egreso (Art. 195).';

COMMENT ON COLUMN hr_schema.vacation_period.is_fractional IS
	'TRUE = periodo fraccionado por meses completos de servicio (Art. 196), cuando la relacion termina sin cumplir el anio.';

CREATE INDEX IF NOT EXISTS idx_vacation_period_employee
	ON hr_schema.vacation_period (employee_id, service_year DESC);

CREATE INDEX IF NOT EXISTS idx_vacation_period_tenant
	ON hr_schema.vacation_period (tenant_id);

-- Periodos causados pendientes de pago en la liquidacion (Art. 195).
CREATE INDEX IF NOT EXISTS idx_vacation_period_pendientes
	ON hr_schema.vacation_period (employee_id)
	WHERE status IN ('causado', 'disfrutado');

-- ============================================================
-- ROLLBACK (documentacion; no se ejecuta automaticamente)
-- ============================================================
-- DROP INDEX IF EXISTS hr_schema.idx_vacation_period_pendientes;
-- DROP INDEX IF EXISTS hr_schema.idx_vacation_period_tenant;
-- DROP INDEX IF EXISTS hr_schema.idx_vacation_period_employee;
-- DROP TABLE IF EXISTS hr_schema.vacation_period;
