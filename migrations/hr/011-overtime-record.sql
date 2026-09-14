-- ============================================================
-- Migracion: 011-overtime-record
-- Contexto: Migracion normativa Costa Rica -> Venezuela (LOTTT).
--   Crea el registro de horas con recargo (nocturnas, extras,
--   feriados y dias de descanso).
-- Por que: hoy las horas se derivan de hr_schema.clocking restando
--   la jornada, lo que solo permite un unico factor de recargo y no
--   deja rastro de por que se pago. La LOTTT exige tres cosas que
--   ese calculo derivado no soporta:
--   1. Factores distintos y concurrentes: 30% nocturno (Art. 117),
--      50% hora extra (Art. 118), 50% sobre el dia en feriado
--      (Art. 120). Una misma jornada puede acumular varios.
--   2. Topes acumulados que hay que poder consultar ANTES de
--      autorizar: 10 h/dia, 10 h/semana y 100 h/anio (Art. 178).
--      Sin una fila por evento no hay como sumar el acumulado anual.
--   3. Permiso de la Inspectoria del Trabajo. Las horas extra
--      laboradas sin autorizacion se pagan con el DOBLE del recargo
--      (Art. 182), es decir 100% en vez de 50%. El estado del
--      permiso cambia el monto, por lo que es un dato del registro.
-- Base legal: Arts. 117, 118, 120, 178, 182, 188.
-- Autor/Fecha: 2026-08-27
-- ============================================================

CREATE TABLE IF NOT EXISTS hr_schema.overtime_record (
	overtime_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id) ON DELETE CASCADE,
	branch_id UUID NOT NULL REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
	clocking_id INTEGER REFERENCES hr_schema.clocking(clocking_id) ON DELETE SET NULL,
	work_date DATE NOT NULL,
	kind VARCHAR(20) NOT NULL,
	hours NUMERIC(5, 2) NOT NULL,
	rate_factor NUMERIC(4, 2) NOT NULL,
	inspectoria_authorized BOOLEAN NOT NULL DEFAULT FALSE,
	authorization_ref VARCHAR(120),
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
	CONSTRAINT chk_overtime_hours_positive CHECK (hours > 0),
	CONSTRAINT chk_overtime_rate_factor CHECK (rate_factor > 0),
	CONSTRAINT chk_overtime_kind CHECK (kind IN ('nocturna', 'extra', 'feriado', 'descanso'))
);

COMMENT ON TABLE hr_schema.overtime_record IS
	'Horas con recargo por evento. Base de los Arts. 117 (nocturno 30%), 118 (extra 50%), 120 (feriado/descanso 50% sobre el dia) y del control de topes del Art. 178.';

COMMENT ON COLUMN hr_schema.overtime_record.kind IS
	'nocturna = recargo del 30% (Art. 117); extra = hora extraordinaria (Art. 118); feriado = labor en dia feriado (Art. 120); descanso = labor en dia de descanso (Arts. 120, 188).';

COMMENT ON COLUMN hr_schema.overtime_record.rate_factor IS
	'Factor aplicado sobre el valor hora normal. Se persiste el factor efectivo del momento, no el parametro vigente hoy, para que el recalculo historico sea reproducible. Hora extra autorizada = 1.50; sin autorizacion de Inspectoria = 2.00 (Art. 182, doble recargo).';

COMMENT ON COLUMN hr_schema.overtime_record.inspectoria_authorized IS
	'FALSE en horas extra implica el doble del recargo (Art. 182). No aplica a kind nocturna.';

COMMENT ON COLUMN hr_schema.overtime_record.clocking_id IS
	'Marcaje que origino el registro, cuando proviene del reloj. NULL si fue cargado manualmente.';

-- Acumulados por dia, semana y anio para validar los topes del Art. 178.
CREATE INDEX IF NOT EXISTS idx_overtime_employee_date
	ON hr_schema.overtime_record (employee_id, work_date DESC);

CREATE INDEX IF NOT EXISTS idx_overtime_tenant_date
	ON hr_schema.overtime_record (tenant_id, work_date);

CREATE INDEX IF NOT EXISTS idx_overtime_kind
	ON hr_schema.overtime_record (employee_id, kind, work_date);

-- ============================================================
-- Topes del Art. 178 (se validan en la capa de aplicacion, requieren
-- agregacion y no pueden expresarse como CHECK):
--   jornada + extras <= 10 h/dia
--   <= 10 h extra/semana
--   <= 100 h extra/anio
-- Consulta de acumulado anual:
--   SELECT COALESCE(SUM(hours), 0) FROM hr_schema.overtime_record
--   WHERE employee_id = $1 AND kind = 'extra'
--     AND work_date >= date_trunc('year', $2::date)
--     AND work_date <  date_trunc('year', $2::date) + INTERVAL '1 year';
-- ============================================================

-- ============================================================
-- ROLLBACK (documentacion; no se ejecuta automaticamente)
-- ============================================================
-- DROP INDEX IF EXISTS hr_schema.idx_overtime_kind;
-- DROP INDEX IF EXISTS hr_schema.idx_overtime_tenant_date;
-- DROP INDEX IF EXISTS hr_schema.idx_overtime_employee_date;
-- DROP TABLE IF EXISTS hr_schema.overtime_record;
