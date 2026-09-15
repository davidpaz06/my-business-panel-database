-- ============================================================
-- Migracion: 015-profit-sharing
-- Contexto: Migracion normativa Costa Rica -> Venezuela (LOTTT).
--   Crea el reparto de utilidades y la bonificacion de fin de anio.
--   Sustituye por completo al aguinaldo costarricense.
-- Por que: el aguinaldo CR era una division simple (salario anual
--   entre 12) que se resolvia con una formula y no necesitaba
--   tablas. Las utilidades venezolanas son un reparto colectivo y
--   requieren estado persistente:
--   1. El monto a repartir sale del 15% de los BENEFICIOS LIQUIDOS
--      del ejercicio (Art. 131), un dato contable del tenant que no
--      existe en RRHH. Se recibe del contexto de finanzas.
--   2. La cuota de cada trabajador es proporcional a su salario
--      devengado sobre la sumatoria de TODOS los salarios devengados
--      (Art. 136). No se puede calcular por empleado de forma
--      aislada: hace falta el periodo completo cerrado.
--   3. Sobre esa cuota se aplican topes por trabajador (Art. 131):
--      minimo 30 dias y maximo 120 dias de salario, prorrateados por
--      meses completos si no laboro todo el anio.
--   4. La bonificacion de fin de anio (Art. 132) es un ANTICIPO
--      obligatorio de minimo 30 dias, pagadero en los primeros 15
--      dias de diciembre e imputable a las utilidades. Si al cierre
--      no hubo beneficios, lo entregado no esta sujeto a repeticion:
--      no se le cobra de vuelta al trabajador. Por eso el anticipo
--      se registra por separado del monto final.
--   No se imputan perdidas de ejercicios anteriores (Art. 135).
-- Base legal: Arts. 131, 132, 135, 136, 137, 140.
-- Autor/Fecha: 2026-08-27
-- ============================================================

-- ------------------------------------------------------------
-- 1. Ejercicio anual de reparto (por tenant)
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS hr_schema.profit_sharing_period (
	profit_period_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
	fiscal_year INTEGER NOT NULL,
	fiscal_year_start DATE NOT NULL,
	fiscal_year_end DATE NOT NULL,
	liquid_benefits NUMERIC(18, 4),
	distribution_percentage NUMERIC(5, 4) NOT NULL DEFAULT 0.15,
	distributable_amount NUMERIC(18, 4),
	total_earned_salaries NUMERIC(18, 4),
	is_non_profit BOOLEAN NOT NULL DEFAULT FALSE,
	status VARCHAR(15) NOT NULL DEFAULT 'abierto',
	closed_at TIMESTAMP,
	payment_deadline DATE,
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
	CONSTRAINT uq_profit_sharing_period_anio UNIQUE (tenant_id, fiscal_year),
	CONSTRAINT chk_profit_period_fechas CHECK (fiscal_year_end > fiscal_year_start),
	CONSTRAINT chk_profit_period_porcentaje CHECK (distribution_percentage >= 0.15),
	CONSTRAINT chk_profit_period_status CHECK (status IN ('abierto', 'calculado', 'cerrado')),
	CONSTRAINT chk_profit_period_cierre CHECK (status <> 'cerrado' OR closed_at IS NOT NULL)
);

COMMENT ON TABLE hr_schema.profit_sharing_period IS
	'Ejercicio anual de reparto de utilidades por tenant (Art. 131). El pago vence dentro de los 2 meses siguientes al cierre del ejercicio (Art. 137).';

COMMENT ON COLUMN hr_schema.profit_sharing_period.liquid_benefits IS
	'Beneficios liquidos del ejercicio. Proviene del cierre contable (contexto finances), no de RRHH. No se imputan perdidas de ejercicios anteriores (Art. 135).';

COMMENT ON COLUMN hr_schema.profit_sharing_period.distribution_percentage IS
	'Porcentaje a repartir. Minimo legal 0.15 (Art. 131); admite mas por convencion colectiva, nunca menos.';

COMMENT ON COLUMN hr_schema.profit_sharing_period.total_earned_salaries IS
	'Sumatoria de los salarios devengados por todos los trabajadores en el ejercicio. Denominador del cociente del Art. 136.';

COMMENT ON COLUMN hr_schema.profit_sharing_period.is_non_profit IS
	'TRUE = entidad sin fines de lucro. Exenta del reparto de utilidades, pero obligada a la bonificacion de fin de anio de minimo 30 dias (Art. 140).';

COMMENT ON COLUMN hr_schema.profit_sharing_period.payment_deadline IS
	'Fecha limite de pago: 2 meses despues del cierre del ejercicio (Art. 137).';

CREATE INDEX IF NOT EXISTS idx_profit_sharing_period_tenant
	ON hr_schema.profit_sharing_period (tenant_id, fiscal_year DESC);

-- ------------------------------------------------------------
-- 2. Cuota por trabajador
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS hr_schema.profit_sharing_detail (
	profit_detail_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	profit_period_id UUID NOT NULL REFERENCES hr_schema.profit_sharing_period(profit_period_id) ON DELETE CASCADE,
	employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id) ON DELETE CASCADE,
	earned_salary NUMERIC(18, 4) NOT NULL,
	complete_months INTEGER NOT NULL,
	daily_salary NUMERIC(18, 4) NOT NULL,
	raw_quota NUMERIC(18, 4),
	min_cap NUMERIC(18, 4) NOT NULL,
	max_cap NUMERIC(18, 4) NOT NULL,
	final_amount NUMERIC(18, 4),
	advance_paid NUMERIC(18, 4) NOT NULL DEFAULT 0,
	advance_paid_at DATE,
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
	CONSTRAINT uq_profit_sharing_detail UNIQUE (profit_period_id, employee_id),
	CONSTRAINT chk_profit_detail_meses CHECK (complete_months >= 0 AND complete_months <= 12),
	CONSTRAINT chk_profit_detail_caps CHECK (max_cap >= min_cap),
	CONSTRAINT chk_profit_detail_advance CHECK (advance_paid >= 0)
);

COMMENT ON TABLE hr_schema.profit_sharing_detail IS
	'Cuota de utilidades por trabajador (Arts. 131, 136). Persiste la cuota bruta y los topes por separado para que el clamp sea auditable.';

COMMENT ON COLUMN hr_schema.profit_sharing_detail.raw_quota IS
	'Cuota antes de aplicar topes: cociente del Art. 136 (monto repartible / sumatoria de salarios devengados) multiplicado por el salario devengado del trabajador.';

COMMENT ON COLUMN hr_schema.profit_sharing_detail.min_cap IS
	'Tope minimo (Art. 131): 30 dias de salario, prorrateado por meses completos si no laboro todo el anio.';

COMMENT ON COLUMN hr_schema.profit_sharing_detail.max_cap IS
	'Tope maximo (Art. 131): 120 dias (4 meses) de salario, prorrateado por meses completos.';

COMMENT ON COLUMN hr_schema.profit_sharing_detail.final_amount IS
	'Monto final tras aplicar los topes sobre la cuota bruta.';

COMMENT ON COLUMN hr_schema.profit_sharing_detail.advance_paid IS
	'Bonificacion de fin de anio ya entregada (Art. 132), imputable a estas utilidades. Si al cierre no hubo beneficios, lo entregado NO esta sujeto a repeticion: no genera saldo en contra del trabajador.';

CREATE INDEX IF NOT EXISTS idx_profit_sharing_detail_period
	ON hr_schema.profit_sharing_detail (profit_period_id);

CREATE INDEX IF NOT EXISTS idx_profit_sharing_detail_employee
	ON hr_schema.profit_sharing_detail (employee_id);

-- ============================================================
-- ROLLBACK (documentacion; no se ejecuta automaticamente)
-- ============================================================
-- DROP INDEX IF EXISTS hr_schema.idx_profit_sharing_detail_employee;
-- DROP INDEX IF EXISTS hr_schema.idx_profit_sharing_detail_period;
-- DROP TABLE IF EXISTS hr_schema.profit_sharing_detail;
-- DROP INDEX IF EXISTS hr_schema.idx_profit_sharing_period_tenant;
-- DROP TABLE IF EXISTS hr_schema.profit_sharing_period;
