-- ============================================================
-- Migracion: 013-severance-advance
-- Contexto: Migracion normativa Costa Rica -> Venezuela (LOTTT).
--   Crea los anticipos sobre la garantia de prestaciones.
-- Por que: el Art. 144 da al trabajador derecho a solicitar hasta el
--   75% de lo depositado como garantia, y solo para causales
--   taxativas (vivienda, hipoteca, educacion, salud). Esto obliga a
--   persistir cada anticipo por dos razones:
--   1. El tope del 75% se calcula contra el saldo depositado MENOS
--      los anticipos ya otorgados. Sin el historico, un trabajador
--      podria retirar el 75% repetidamente.
--   2. Los anticipos se restan del monto final en la liquidacion
--      (Art. 142). Un anticipo no registrado se paga dos veces.
--   La causal se persiste porque el Art. 144 la limita: un anticipo
--   sin causal valida es un retiro improcedente.
-- Base legal: Arts. 142, 144.
-- Autor/Fecha: 2026-08-27
-- ============================================================

CREATE TABLE IF NOT EXISTS hr_schema.severance_advance (
	advance_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id) ON DELETE CASCADE,
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
	requested_amount NUMERIC(18, 4) NOT NULL,
	approved_amount NUMERIC(18, 4),
	reason VARCHAR(20) NOT NULL,
	reason_detail TEXT,
	request_date DATE NOT NULL DEFAULT CURRENT_DATE,
	resolution_date DATE,
	status VARCHAR(15) NOT NULL DEFAULT 'pendiente',
	guarantee_balance_at_request NUMERIC(18, 4),
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
	CONSTRAINT chk_severance_advance_requested CHECK (requested_amount > 0),
	CONSTRAINT chk_severance_advance_approved CHECK (approved_amount IS NULL OR approved_amount >= 0),
	CONSTRAINT chk_severance_advance_reason CHECK (reason IN ('vivienda', 'hipoteca', 'educacion', 'salud')),
	CONSTRAINT chk_severance_advance_status CHECK (status IN ('pendiente', 'aprobado', 'rechazado')),
	CONSTRAINT chk_severance_advance_resolucion CHECK (
		status = 'pendiente'
		OR (resolution_date IS NOT NULL AND approved_amount IS NOT NULL)
	)
);

COMMENT ON TABLE hr_schema.severance_advance IS
	'Anticipos sobre la garantia de prestaciones (Art. 144). Tope del 75% del saldo depositado. Se descuentan del monto final en la liquidacion.';

COMMENT ON COLUMN hr_schema.severance_advance.reason IS
	'Causal taxativa del Art. 144: vivienda (construccion, adquisicion o mejora), hipoteca (liberacion), educacion, salud (gastos medicos propios o de la familia). No admite otras causales.';

COMMENT ON COLUMN hr_schema.severance_advance.guarantee_balance_at_request IS
	'Saldo de la garantia al momento de solicitar, para auditar el calculo del tope del 75% sin depender de un recalculo posterior.';

COMMENT ON COLUMN hr_schema.severance_advance.approved_amount IS
	'Monto efectivamente otorgado. Es el que se descuenta en la liquidacion final, no el solicitado.';

CREATE INDEX IF NOT EXISTS idx_severance_advance_employee
	ON hr_schema.severance_advance (employee_id, request_date DESC);

CREATE INDEX IF NOT EXISTS idx_severance_advance_tenant
	ON hr_schema.severance_advance (tenant_id);

-- Anticipos vigentes a descontar en la liquidacion.
CREATE INDEX IF NOT EXISTS idx_severance_advance_aprobados
	ON hr_schema.severance_advance (employee_id)
	WHERE status = 'aprobado';

-- ============================================================
-- Tope del Art. 144 (se valida en la capa de aplicacion):
--   saldo_depositado = SUM(severance_deposit.amount WHERE deposit_made)
--                    + SUM(severance_interest.amount WHERE capitalized)
--                    - SUM(severance_advance.approved_amount WHERE aprobado)
--   max_anticipo = saldo_depositado * 0.75
-- ============================================================

-- ============================================================
-- ROLLBACK (documentacion; no se ejecuta automaticamente)
-- ============================================================
-- DROP INDEX IF EXISTS hr_schema.idx_severance_advance_aprobados;
-- DROP INDEX IF EXISTS hr_schema.idx_severance_advance_tenant;
-- DROP INDEX IF EXISTS hr_schema.idx_severance_advance_employee;
-- DROP TABLE IF EXISTS hr_schema.severance_advance;
