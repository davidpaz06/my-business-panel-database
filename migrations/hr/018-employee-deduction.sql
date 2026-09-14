-- ============================================================
-- Migracion: 018-employee-deduction
-- Contexto: Migracion normativa Costa Rica -> Venezuela (LOTTT).
--   Crea las deducciones al salario con sus limites legales.
--   Ultima migracion de la Fase 3.
-- Por que: el salario esta protegido por la LOTTT y no se le puede
--   descontar libremente. El sistema no tenia donde registrar una
--   deduccion individual (payroll_concept es un catalogo de
--   conceptos del tenant, no una obligacion de un trabajador
--   concreto). Tres reglas obligan a esta tabla:
--   1. Tope del Art. 154: las deudas del trabajador con el patrono
--      solo son amortizables por cantidades que NO excedan la
--      tercera parte de una semana o un mes de trabajo, segun el
--      caso. Al terminar la relacion el patrono puede compensar el
--      saldo pendiente hasta el 50% del credito a favor. Son dos
--      topes distintos segun el momento, por lo que hay que llevar
--      el saldo pendiente de cada deuda.
--   2. La cuota sindical requiere AUTORIZACION EXPRESA del
--      trabajador (Arts. 412, 413) y se entrega a la organizacion
--      sindical mediante cheque a su nombre. Sin la autorizacion
--      registrada el descuento es improcedente.
--   3. El salario y las prestaciones son inembargables salvo por
--      pension alimentaria (Art. 152). La pension alimentaria es
--      por tanto una categoria distinta, no sujeta a los topes
--      ordinarios del Art. 154.
-- Base legal: Arts. 102, 152, 154, 412, 413.
-- Autor/Fecha: 2026-08-27
-- ============================================================

CREATE TABLE IF NOT EXISTS hr_schema.employee_deduction (
	deduction_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id) ON DELETE CASCADE,
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
	kind VARCHAR(20) NOT NULL,
	description VARCHAR(200) NOT NULL,
	total_amount NUMERIC(18, 4) NOT NULL,
	installment_amount NUMERIC(18, 4),
	outstanding_balance NUMERIC(18, 4) NOT NULL,
	authorized BOOLEAN NOT NULL DEFAULT FALSE,
	authorization_date DATE,
	authorization_ref VARCHAR(120),
	union_organization VARCHAR(200),
	start_date DATE NOT NULL DEFAULT CURRENT_DATE,
	end_date DATE,
	is_active BOOLEAN NOT NULL DEFAULT TRUE,
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
	CONSTRAINT chk_employee_deduction_kind CHECK (kind IN ('deuda_patrono', 'sindical', 'alimentaria', 'otra')),
	CONSTRAINT chk_employee_deduction_total CHECK (total_amount > 0),
	CONSTRAINT chk_employee_deduction_balance CHECK (outstanding_balance >= 0 AND outstanding_balance <= total_amount),
	CONSTRAINT chk_employee_deduction_installment CHECK (installment_amount IS NULL OR installment_amount > 0),
	CONSTRAINT chk_employee_deduction_fechas CHECK (end_date IS NULL OR end_date >= start_date),
	-- Arts. 412/413: la cuota sindical exige autorizacion expresa.
	CONSTRAINT chk_employee_deduction_sindical_autorizada CHECK (
		kind <> 'sindical'
		OR (authorized = TRUE AND authorization_date IS NOT NULL)
	),
	CONSTRAINT chk_employee_deduction_autorizacion CHECK (
		authorized = FALSE OR authorization_date IS NOT NULL
	)
);

COMMENT ON TABLE hr_schema.employee_deduction IS
	'Deducciones al salario por trabajador con sus limites legales. El tope ordinario es 1/3 del periodo durante la relacion y 50% del credito a favor en la liquidacion (Art. 154).';

COMMENT ON COLUMN hr_schema.employee_deduction.kind IS
	'deuda_patrono = deuda del trabajador con la entidad, sujeta al tope de 1/3 (Art. 154); sindical = cuota ordinaria o extraordinaria, requiere autorizacion expresa (Arts. 412, 413); alimentaria = pension alimentaria, unica excepcion a la inembargabilidad del salario (Art. 152) y no sujeta al tope ordinario.';

COMMENT ON COLUMN hr_schema.employee_deduction.outstanding_balance IS
	'Saldo pendiente. Es el que se compensa hasta el 50% del credito a favor del trabajador al terminar la relacion (Art. 154).';

COMMENT ON COLUMN hr_schema.employee_deduction.installment_amount IS
	'Cuota por periodo de nomina. No puede exceder 1/3 del salario del periodo durante la relacion (Art. 154); el tope se valida en la capa de aplicacion porque depende del salario vigente.';

COMMENT ON COLUMN hr_schema.employee_deduction.union_organization IS
	'Organizacion sindical destinataria. El Art. 412 exige entregar lo descontado mediante cheque a nombre de la organizacion.';

COMMENT ON COLUMN hr_schema.employee_deduction.authorization_ref IS
	'Referencia del documento de autorizacion del trabajador. Obligatoria para la cuota sindical (Art. 413).';

CREATE INDEX IF NOT EXISTS idx_employee_deduction_employee
	ON hr_schema.employee_deduction (employee_id);

CREATE INDEX IF NOT EXISTS idx_employee_deduction_tenant
	ON hr_schema.employee_deduction (tenant_id);

-- Deducciones vigentes a aplicar en la corrida de nomina.
CREATE INDEX IF NOT EXISTS idx_employee_deduction_activas
	ON hr_schema.employee_deduction (employee_id, kind)
	WHERE is_active = TRUE AND outstanding_balance > 0;

-- ============================================================
-- Topes del Art. 154 (se validan en la capa de aplicacion porque
-- dependen del salario vigente del periodo):
--   Durante la relacion:  installment_amount <= salario_periodo / 3
--   En la liquidacion:    SUM(outstanding_balance) <= credito_a_favor * 0.50
-- La pension alimentaria (kind = 'alimentaria') NO esta sujeta a
-- estos topes: es la unica excepcion a la inembargabilidad del
-- salario y las prestaciones (Art. 152).
-- ============================================================

-- ============================================================
-- ROLLBACK (documentacion; no se ejecuta automaticamente)
-- ============================================================
-- DROP INDEX IF EXISTS hr_schema.idx_employee_deduction_activas;
-- DROP INDEX IF EXISTS hr_schema.idx_employee_deduction_tenant;
-- DROP INDEX IF EXISTS hr_schema.idx_employee_deduction_employee;
-- DROP TABLE IF EXISTS hr_schema.employee_deduction;
