-- ============================================================
-- Migracion: 016-settlement
-- Contexto: Migracion normativa Costa Rica -> Venezuela (LOTTT).
--   Crea la liquidacion final y su desglose auditable.
-- Por que: es el punto donde convergen todos los calculos y el de
--   mayor exposicion legal. Tres exigencias definen el diseno:
--   1. El Art. 142.d obliga a calcular las prestaciones por DOS
--      vias independientes y pagar la MAYOR: la garantia acumulada
--      (142.a + 142.b) frente al retroactivo de 30 dias por anio
--      (142.c). Se persisten AMBOS montos y cual se eligio, no solo
--      el ganador: ante un reclamo hay que poder demostrar por que
--      se pago ese monto, y la prescripcion de prestaciones es de
--      10 anios (Art. 51). Recalcular anios despues con parametros
--      distintos no reconstruye la decision original.
--   2. El recibo debe ir desglosado por concepto (Art. 106). Cada
--      renglon guarda su base, sus dias, su articulo y el texto de
--      la formula, de modo que la liquidacion se explique sola.
--   3. La mora es parte de la liquidacion, no un ajuste posterior:
--      si el pago excede los 5 dias siguientes al egreso se generan
--      intereses a la tasa activa del BCV desde el dia 6 (Art. 142.f).
--      Por eso payment_date y mora_amount viven en la cabecera.
--   La indemnizacion del Art. 92 (monto igual a las prestaciones en
--   despido injustificado) se registra como un renglon mas del
--   desglose, no como columna: asi el total siempre es la suma
--   verificable de sus partes.
-- Base legal: Arts. 51, 92, 106, 141, 142, 144, 154, 195, 196.
-- Autor/Fecha: 2026-08-27
-- ============================================================

-- ------------------------------------------------------------
-- 1. Cabecera de la liquidacion
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS hr_schema.settlement (
	settlement_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id) ON DELETE CASCADE,
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
	branch_id UUID REFERENCES general_schema.branch(branch_id) ON DELETE SET NULL,
	termination_date DATE NOT NULL,
	payment_due_date DATE NOT NULL,
	payment_date DATE,
	hire_date DATE NOT NULL,
	complete_years INTEGER NOT NULL,
	remainder_months INTEGER NOT NULL,
	last_integral_daily_salary NUMERIC(18, 4) NOT NULL,
	last_normal_daily_salary NUMERIC(18, 4) NOT NULL,
	via1_amount NUMERIC(18, 4),
	via2_amount NUMERIC(18, 4),
	selected_via VARCHAR(20),
	severance_amount NUMERIC(18, 4),
	advances_deducted NUMERIC(18, 4) NOT NULL DEFAULT 0,
	deductions_amount NUMERIC(18, 4) NOT NULL DEFAULT 0,
	subtotal NUMERIC(18, 4),
	mora_days INTEGER NOT NULL DEFAULT 0,
	mora_rate NUMERIC(10, 6),
	mora_amount NUMERIC(18, 4) NOT NULL DEFAULT 0,
	total NUMERIC(18, 4),
	status VARCHAR(15) NOT NULL DEFAULT 'borrador',
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
	CONSTRAINT uq_settlement_employee UNIQUE (employee_id, termination_date),
	CONSTRAINT chk_settlement_fechas CHECK (termination_date >= hire_date),
	CONSTRAINT chk_settlement_antiguedad CHECK (complete_years >= 0 AND remainder_months >= 0 AND remainder_months <= 11),
	CONSTRAINT chk_settlement_selected_via CHECK (selected_via IS NULL OR selected_via IN ('garantia', 'retroactivo', 'antiguedad_corta')),
	CONSTRAINT chk_settlement_status CHECK (status IN ('borrador', 'calculada', 'pagada', 'anulada')),
	CONSTRAINT chk_settlement_mora CHECK (mora_days >= 0 AND mora_amount >= 0),
	CONSTRAINT chk_settlement_pagada CHECK (status <> 'pagada' OR payment_date IS NOT NULL)
);

COMMENT ON TABLE hr_schema.settlement IS
	'Liquidacion final de la relacion laboral. Persiste el resultado de ambas vias del Art. 142 y la via elegida para que la decision sea auditable durante los 10 anios de prescripcion (Art. 51).';

COMMENT ON COLUMN hr_schema.settlement.payment_due_date IS
	'Fecha limite de pago: 5 dias siguientes a la terminacion (Art. 142.f). Pasada esa fecha corren intereses de mora a tasa activa BCV desde el dia 6.';

COMMENT ON COLUMN hr_schema.settlement.via1_amount IS
	'Via 1 (Art. 142.a + 142.b): garantia trimestral acumulada mas los dias adicionales por antiguedad.';

COMMENT ON COLUMN hr_schema.settlement.via2_amount IS
	'Via 2 (Art. 142.c): retroactivo de 30 dias por anio de servicio o fraccion superior a 6 meses, al ultimo salario integral.';

COMMENT ON COLUMN hr_schema.settlement.selected_via IS
	'Via aplicada (Art. 142.d): se paga la MAYOR entre garantia y retroactivo. antiguedad_corta = relacion menor a 3 meses, que sustituye ambos esquemas por 5 dias de salario por mes o fraccion (Art. 142.e).';

COMMENT ON COLUMN hr_schema.settlement.remainder_months IS
	'Meses de la fraccion de anio. Si supera 6, el retroactivo redondea a un anio completo (Art. 142.c).';

COMMENT ON COLUMN hr_schema.settlement.last_integral_daily_salary IS
	'Ultimo salario integral diario (Art. 122). Base de prestaciones e indemnizaciones. Nunca usar el salario normal aqui.';

COMMENT ON COLUMN hr_schema.settlement.last_normal_daily_salary IS
	'Ultimo salario normal diario (Art. 104). Base de vacaciones y bono vacacional pendientes (Art. 195).';

COMMENT ON COLUMN hr_schema.settlement.mora_rate IS
	'Tasa activa BCV aplicada a la mora. Se persiste la usada; la tasa vigente cambia y el recalculo debe ser reproducible.';

COMMENT ON COLUMN hr_schema.settlement.advances_deducted IS
	'Anticipos de garantia otorgados (Art. 144) que se restan del monto final.';

CREATE INDEX IF NOT EXISTS idx_settlement_employee
	ON hr_schema.settlement (employee_id, termination_date DESC);

CREATE INDEX IF NOT EXISTS idx_settlement_tenant
	ON hr_schema.settlement (tenant_id, termination_date DESC);

-- Liquidaciones vencidas sin pagar: generan mora (Art. 142.f).
CREATE INDEX IF NOT EXISTS idx_settlement_pendientes
	ON hr_schema.settlement (payment_due_date)
	WHERE payment_date IS NULL AND status <> 'anulada';

-- ------------------------------------------------------------
-- 2. Desglose por concepto (Art. 106)
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS hr_schema.settlement_item (
	settlement_item_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	settlement_id UUID NOT NULL REFERENCES hr_schema.settlement(settlement_id) ON DELETE CASCADE,
	code VARCHAR(15) NOT NULL,
	concept_name VARCHAR(120) NOT NULL,
	article VARCHAR(20) NOT NULL,
	salary_basis VARCHAR(10) NOT NULL,
	base_amount NUMERIC(18, 4) NOT NULL,
	days NUMERIC(7, 2),
	amount NUMERIC(18, 4) NOT NULL,
	formula_text TEXT,
	sort_order INTEGER NOT NULL DEFAULT 0,
	CONSTRAINT chk_settlement_item_salary_basis CHECK (salary_basis IN ('normal', 'integral')),
	CONSTRAINT chk_settlement_item_base CHECK (base_amount >= 0)
);

COMMENT ON TABLE hr_schema.settlement_item IS
	'Desglose auditable de la liquidacion (Art. 106). Un renglon por concepto, con su base, dias, articulo y formula legible. El total de la cabecera debe ser la suma verificable de estos renglones.';

COMMENT ON COLUMN hr_schema.settlement_item.code IS
	'Codigo estable del caso de uso (HR-VE-05, HR-VE-14, ...) para trazar el renglon contra la especificacion.';

COMMENT ON COLUMN hr_schema.settlement_item.article IS
	'Articulo de la LOTTT que fundamenta el renglon. Se imprime en el recibo.';

COMMENT ON COLUMN hr_schema.settlement_item.amount IS
	'Monto del renglon. Negativo para los que restan: anticipos (Art. 144) y descuentos (Art. 154).';

COMMENT ON COLUMN hr_schema.settlement_item.formula_text IS
	'Formula en texto legible para el recibo, por ejemplo: 30 dias x 4 anios x salario integral diario 125.4000.';

CREATE INDEX IF NOT EXISTS idx_settlement_item_settlement
	ON hr_schema.settlement_item (settlement_id, sort_order);

-- ============================================================
-- ROLLBACK (documentacion; no se ejecuta automaticamente)
-- ============================================================
-- DROP INDEX IF EXISTS hr_schema.idx_settlement_item_settlement;
-- DROP TABLE IF EXISTS hr_schema.settlement_item;
-- DROP INDEX IF EXISTS hr_schema.idx_settlement_pendientes;
-- DROP INDEX IF EXISTS hr_schema.idx_settlement_tenant;
-- DROP INDEX IF EXISTS hr_schema.idx_settlement_employee;
-- DROP TABLE IF EXISTS hr_schema.settlement;
