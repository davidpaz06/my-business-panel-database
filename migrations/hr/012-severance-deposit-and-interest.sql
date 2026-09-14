-- ============================================================
-- Migracion: 012-severance-deposit-and-interest
-- Contexto: Migracion normativa Costa Rica -> Venezuela (LOTTT).
--   Crea la garantia de prestaciones sociales y sus intereses.
--   Es el nucleo del modulo: el Art. 142 es el calculo de mayor
--   impacto economico y el de mayor riesgo legal.
-- Por que: en Costa Rica el auxilio de cesantia se calculaba solo al
--   final de la relacion, por lo que no habia nada que persistir
--   durante su vigencia. El Art. 142 venezolano funciona al reves:
--   la garantia se DEPOSITA trimestralmente y devenga intereses
--   mientras esta depositada, de modo que el sistema debe llevar el
--   saldo vivo. Dos exigencias concretas:
--   1. El deposito se hace con el salario integral DEL TRIMESTRE
--      (Art. 142.a), no con el salario final. Cada trimestre congela
--      su propia base; sin una fila por trimestre no hay forma de
--      reconstruirla despues de un aumento salarial.
--   2. La tasa de los intereses depende de donde este la garantia y
--      de si el patrono cumplio (Art. 143). Si NO deposito, la
--      garantia devenga la tasa ACTIVA del BCV como penalizacion.
--      Por eso deposit_made es un dato de negocio, no un flag
--      operativo: determina la tasa aplicable.
--   Los dias adicionales del Art. 142.b (2 por anio despues del
--   primer anio, tope 30) NO se persisten aqui: se derivan de la
--   antiguedad al momento del calculo, contra el ULTIMO salario
--   integral.
-- Base legal: Arts. 141, 142.a, 142.b, 143.
-- Autor/Fecha: 2026-08-27
-- ============================================================

-- ------------------------------------------------------------
-- 1. Deposito trimestral de la garantia (Art. 142.a)
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS hr_schema.severance_deposit (
	deposit_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id) ON DELETE CASCADE,
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
	quarter_start DATE NOT NULL,
	quarter_end DATE NOT NULL,
	days NUMERIC(5, 2) NOT NULL DEFAULT 15,
	integral_daily_salary NUMERIC(18, 4) NOT NULL,
	amount NUMERIC(18, 4) NOT NULL,
	deposit_made BOOLEAN NOT NULL DEFAULT FALSE,
	deposit_date DATE,
	location VARCHAR(20) NOT NULL,
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
	CONSTRAINT uq_severance_deposit_trimestre UNIQUE (employee_id, quarter_start),
	CONSTRAINT chk_severance_deposit_periodo CHECK (quarter_end > quarter_start),
	CONSTRAINT chk_severance_deposit_days CHECK (days > 0),
	CONSTRAINT chk_severance_deposit_amount CHECK (amount >= 0),
	CONSTRAINT chk_severance_deposit_salary CHECK (integral_daily_salary >= 0),
	CONSTRAINT chk_severance_deposit_location CHECK (location IN ('fideicomiso', 'fondo_nacional', 'contabilidad')),
	CONSTRAINT chk_severance_deposit_fecha CHECK (deposit_made = FALSE OR deposit_date IS NOT NULL)
);

COMMENT ON TABLE hr_schema.severance_deposit IS
	'Garantia de prestaciones sociales depositada por trimestre (Art. 142.a): 15 dias de salario integral por trimestre, adquiridos al iniciar el trimestre.';

COMMENT ON COLUMN hr_schema.severance_deposit.integral_daily_salary IS
	'Salario integral diario VIGENTE EN EL TRIMESTRE (Art. 122). Se congela al depositar: un aumento posterior no lo modifica. Es lo que hace reconstruible la Via 1 del Art. 142.';

COMMENT ON COLUMN hr_schema.severance_deposit.days IS
	'Dias depositados en el trimestre. Minimo legal 15 (Art. 142.a); admite mas por convencion colectiva.';

COMMENT ON COLUMN hr_schema.severance_deposit.deposit_made IS
	'FALSE = el patrono no realizo el deposito. Dispara la penalizacion del Art. 143: la garantia devenga la tasa ACTIVA del BCV, la mas alta, ademas de las sanciones de ley.';

COMMENT ON COLUMN hr_schema.severance_deposit.location IS
	'Ubicacion de la garantia (Art. 143), determina la tasa: fideicomiso / fondo_nacional = rendimiento del fideicomiso o fondo; contabilidad = tasa promedio entre activa y pasiva del BCV, requiere autorizacion escrita del trabajador.';

CREATE INDEX IF NOT EXISTS idx_severance_deposit_employee
	ON hr_schema.severance_deposit (employee_id, quarter_start DESC);

CREATE INDEX IF NOT EXISTS idx_severance_deposit_tenant
	ON hr_schema.severance_deposit (tenant_id);

-- Localizar trimestres incumplidos para aplicar la penalizacion del Art. 143.
CREATE INDEX IF NOT EXISTS idx_severance_deposit_pendientes
	ON hr_schema.severance_deposit (employee_id)
	WHERE deposit_made = FALSE;

-- ------------------------------------------------------------
-- 2. Intereses sobre la garantia depositada (Art. 143)
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS hr_schema.severance_interest (
	interest_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	deposit_id UUID REFERENCES hr_schema.severance_deposit(deposit_id) ON DELETE CASCADE,
	employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id) ON DELETE CASCADE,
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
	period_month DATE NOT NULL,
	balance_base NUMERIC(18, 4) NOT NULL,
	applied_rate NUMERIC(10, 6) NOT NULL,
	rate_kind VARCHAR(20) NOT NULL,
	amount NUMERIC(18, 4) NOT NULL,
	capitalized BOOLEAN NOT NULL DEFAULT FALSE,
	paid_at DATE,
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
	CONSTRAINT uq_severance_interest_periodo UNIQUE (employee_id, deposit_id, period_month),
	CONSTRAINT chk_severance_interest_rate CHECK (applied_rate >= 0),
	CONSTRAINT chk_severance_interest_amount CHECK (amount >= 0),
	CONSTRAINT chk_severance_interest_rate_kind CHECK (rate_kind IN ('fideicomiso', 'promedio_activa_pasiva', 'activa_bcv'))
);

COMMENT ON TABLE hr_schema.severance_interest IS
	'Intereses mensuales sobre la garantia depositada (Art. 143). Se calculan mensualmente y se pagan al cumplir cada anio, salvo que el trabajador decida capitalizarlos por escrito.';

COMMENT ON COLUMN hr_schema.severance_interest.applied_rate IS
	'Tasa efectivamente aplicada en el mes. Se persiste el valor usado, no la tasa vigente hoy: la tasa del BCV cambia y el recalculo historico debe ser reproducible.';

COMMENT ON COLUMN hr_schema.severance_interest.rate_kind IS
	'Origen de la tasa (Art. 143): fideicomiso = rendimiento del fideicomiso o fondo; promedio_activa_pasiva = garantia en la contabilidad de la entidad; activa_bcv = penalizacion por trimestre sin deposito.';

COMMENT ON COLUMN hr_schema.severance_interest.capitalized IS
	'TRUE = el trabajador solicito por escrito capitalizar los intereses en vez de cobrarlos al cumplir el anio (Art. 143).';

COMMENT ON COLUMN hr_schema.severance_interest.period_month IS
	'Primer dia del mes liquidado. Los intereses se devengan mensualmente.';

CREATE INDEX IF NOT EXISTS idx_severance_interest_employee
	ON hr_schema.severance_interest (employee_id, period_month DESC);

CREATE INDEX IF NOT EXISTS idx_severance_interest_deposit
	ON hr_schema.severance_interest (deposit_id);

-- ============================================================
-- ROLLBACK (documentacion; no se ejecuta automaticamente)
-- ============================================================
-- DROP INDEX IF EXISTS hr_schema.idx_severance_interest_deposit;
-- DROP INDEX IF EXISTS hr_schema.idx_severance_interest_employee;
-- DROP TABLE IF EXISTS hr_schema.severance_interest;
-- DROP INDEX IF EXISTS hr_schema.idx_severance_deposit_pendientes;
-- DROP INDEX IF EXISTS hr_schema.idx_severance_deposit_tenant;
-- DROP INDEX IF EXISTS hr_schema.idx_severance_deposit_employee;
-- DROP TABLE IF EXISTS hr_schema.severance_deposit;
