DROP SCHEMA IF EXISTS hr_schema CASCADE;
CREATE SCHEMA IF NOT EXISTS hr_schema;
SET SEARCH_PATH TO hr_schema;

-- MODULO DE EMPLEADO

CREATE TABLE IF NOT EXISTS payment_schedule(
	payment_schedule_id SERIAL PRIMARY KEY NOT NULL,
	description VARCHAR(100) NOT NULL,
	daycount INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS hr_schema.config (
  branch_id UUID PRIMARY KEY REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
  foul_expiration_months INTEGER DEFAULT 6,
  updated_at TIMESTAMP DEFAULT current_timestamp
);

CREATE TABLE IF NOT EXISTS hr_schema.turn (
  turn_id SERIAL PRIMARY KEY,
  branch_id UUID REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE NOT NULL,
  entry TIME NOT NULL,
  out TIME NOT NULL
);
-- insert into hr_schema.turn (branch_id, entry, out) values
-- ('64ff2bad-4012-42a6-8aa9-48dd67bfb8c6', '08:00:00', '16:00:00');

CREATE INDEX branch_turn_idx ON hr_schema.turn(branch_id);

CREATE TABLE IF NOT EXISTS hr_schema.duties_type (
	duties_type_id SERIAL PRIMARY KEY,
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
	name VARCHAR(150) NOT NULL,
	description TEXT,
	is_active BOOLEAN NOT NULL DEFAULT TRUE,
	created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_duties_type_tenant ON hr_schema.duties_type(tenant_id);

CREATE TABLE IF NOT EXISTS contract(
	contract_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id),
	start_date DATE NOT NULL,
	-- NULL = contrato por tiempo indefinido (regla general en Venezuela)
	end_date DATE,
	hours INTEGER NOT NULL,
	base_salary NUMERIC(19, 4) NOT NULL,
	duties TEXT,
	duties_type_id INTEGER REFERENCES hr_schema.duties_type(duties_type_id) ON DELETE SET NULL,
	-- Horas del turno vinculado (derivado de turn.entry/turn.out, Art. 173).
	-- NUMERIC porque un turno puede durar fracciones de hora (ej. 9:30-18:00 = 8.5h).
	turn_type NUMERIC(4, 2),
	turn_id INTEGER REFERENCES hr_schema.turn(turn_id) ON DELETE SET NULL,
	-- Tipo de jornada (Art. 173 LOTTT): diurna 8h/40h, nocturna 7h/35h, mixta 7.5h/37.5h
	journey_type VARCHAR(10) NOT NULL DEFAULT 'diurna',
	weekly_hours NUMERIC(5, 2) NOT NULL DEFAULT 40,
	CONSTRAINT chk_contract_journey_type CHECK (journey_type IN ('diurna', 'nocturna', 'mixta')),
	CONSTRAINT chk_contract_weekly_hours CHECK (weekly_hours > 0 AND weekly_hours <= 42)
);
--Indice para filtracion o busqueda por rango de precios
CREATE INDEX idx_contract_base_salary ON hr_schema.contract (base_salary);

CREATE TABLE IF NOT EXISTS employee(
	employee_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	user_id UUID REFERENCES general_schema.users(user_id) ON DELETE SET NULL,
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id),
	branch_id UUID NOT NULL REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
	first_name VARCHAR(100) NOT NULL,
	last_name VARCHAR(100) NOT NULL,
	doc_number VARCHAR(100) NOT NULL UNIQUE,
	identification_type_id INTEGER REFERENCES general_schema.identification_type(identification_type_id) ON DELETE SET NULL,
	phone VARCHAR(100) NOT NULL,
	email VARCHAR(100) NOT NULL UNIQUE,
	contract_id UUID NOT NULL REFERENCES hr_schema.contract(contract_id) ON DELETE CASCADE,
	payment_schedule_id INTEGER NOT NULL REFERENCES hr_schema.payment_schedule(payment_schedule_id),
	is_active BOOLEAN DEFAULT true,
	-- Fecha de ingreso: base del computo de antiguedad (Art. 142 LOTTT).
	-- Se desnormaliza desde contract.start_date porque un trabajador puede
	-- encadenar contratos sin perder antiguedad.
	hire_date DATE NOT NULL,
	-- NULL = relacion activa. Dispara el plazo de 5 dias del Art. 142.f.
	termination_date DATE,
	termination_type VARCHAR(30),
	termination_reason TEXT,
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
	CONSTRAINT chk_employee_termination_type CHECK (termination_type IS NULL OR termination_type IN (
		'despido_injustificado',
		'despido_justificado',
		'renuncia',
		'causa_ajena_al_trabajador',
		'vencimiento_contrato',
		'fallecimiento'
	)),
	CONSTRAINT chk_employee_termination_coherente CHECK (
		(termination_date IS NULL AND termination_type IS NULL)
		OR (termination_date IS NOT NULL AND termination_type IS NOT NULL)
	),
	CONSTRAINT chk_employee_fechas_relacion CHECK (termination_date IS NULL OR termination_date >= hire_date)
);

-- Indice para localizar egresos pendientes de liquidacion
CREATE INDEX idx_employee_termination_date ON hr_schema.employee (termination_date)
	WHERE termination_date IS NOT NULL;
	
--Indice para que se pueda garantizar que no haya empleados duplicados
CREATE UNIQUE INDEX idx_employee_doc_number ON hr_schema.employee (doc_number);

--Indice para JOINs de tipo de documento
CREATE INDEX idx_employee_identification_type ON hr_schema.employee (identification_type_id);

--Inidice para la recuperacion de cuentas o autenticacion del empleado
CREATE UNIQUE INDEX idx_employee_email ON hr_schema.employee (email);

--Indices destinados para la aceleracion de los JOINS
CREATE INDEX idx_employee_user_id ON hr_schema.employee (user_id);
CREATE INDEX idx_employee_contract_id ON hr_schema.employee (contract_id);
CREATE INDEX idx_employee_payment_schedule_id ON hr_schema.employee (payment_schedule_id);

--Indice que se utilizara unicamente para el proceso de nomina y generacion de reportes
CREATE INDEX idx_employee_is_active ON hr_schema.employee (is_active);

CREATE TABLE IF NOT EXISTS hr_schema.foul(
  foul_id SERIAL PRIMARY KEY,
  employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id),
  branch_id UUID NOT NULL REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
  identificator VARCHAR(50) UNIQUE NOT NULL, 
  foul_date DATE NOT NULL,
  foul_hour TIME NOT NULL,
  description TEXT
);

CREATE INDEX idx_look_employee ON hr_schema.foul(employee_id);
CREATE INDEX idx_look_period_fouls ON hr_schema.foul(foul_date);
CREATE INDEX idx_identificator_foul ON hr_schema.foul(identificator);

CREATE TABLE IF NOT EXISTS hr_schema.suspention (
  suspention_id SERIAL PRIMARY KEY,
  employee_id UUID REFERENCES hr_schema.employee(employee_id),
	branch_id UUID NOT NULL REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
  suspention_start DATE NOT NULL,
  suspention_end DATE NOT NULL,
  reason TEXT NOT NULL,
	is_active BOOLEAN DEFAULT TRUE,
	created_at TIMESTAMP DEFAULT current_timestamp
);

CREATE INDEX get_employee_suspention_idx ON hr_schema.suspention(employee_id);
CREATE INDEX get_suspentions_period_idx ON hr_schema.suspention(suspention_start, suspention_end);
CREATE INDEX idx_branch_suspention ON hr_schema.suspention(branch_id);

CREATE TABLE IF NOT EXISTS clocking(
	clocking_id SERIAL PRIMARY KEY NOT NULL,
	employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id),
	branch_id UUID NOT NULL REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
	clock_in TIMESTAMP,
	clock_out TIMESTAMP,
	turn_hours NUMERIC NOT NULL DEFAULT 0
);

-- Indice para buscar los turnos de un empleado dentro de un rango de fechas
CREATE INDEX idx_track_employee_hours_in ON hr_schema.clocking (employee_id, clock_in DESC);
-- Indice para ubicar turnos por sucursal
CREATE INDEX idx_track_hours_branch_id ON hr_schema.clocking (branch_id);

CREATE TABLE IF NOT EXISTS hr_schema.tardiness (
  tardiness_id SERIAL PRIMARY KEY,
  employee_id UUID REFERENCES hr_schema.employee(employee_id),
  branch_id UUID REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
  type VARCHAR(20) NOT NULL, -- "late" | "early"
  log TEXT,
  registered_at DATE DEFAULT NOW()
);

CREATE INDEX idx_emp_tardiness_srch ON hr_schema.tardiness(employee_id);
CREATE INDEX idx_brnch_tardiness_srch ON hr_schema.tardiness(branch_id);
CREATE INDEX idx_register_srch ON hr_schema.tardiness(registered_at);

-- Dias feriados (Art. 184 LOTTT). Los domingos son feriados por ley y se
-- resuelven por calculo de calendario, no se siembran como filas.
CREATE TABLE IF NOT EXISTS hr_schema.holiday (
  holiday_id SERIAL PRIMARY KEY NOT NULL,
  date TIMESTAMP NOT NULL,
  holiday_name VARCHAR(150) NOT NULL,
  is_freeday BOOLEAN NOT NULL DEFAULT TRUE,
  is_payable BOOLEAN NOT NULL DEFAULT TRUE,
  -- NULL = feriado nacional. Con valor = feriado estadal o municipal.
  tenant_id UUID REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
  -- NULL solo para recurrentes de fecha fija. Los moviles (carnaval,
  -- Semana Santa) requieren una fila por anio.
  holiday_year INTEGER,
  is_recurring BOOLEAN NOT NULL DEFAULT FALSE,
  -- Los declarados por ejecutivo/estados/municipios estan limitados a 3
  -- por anio en conjunto (Art. 184.d); el tope se valida en aplicacion.
  source VARCHAR(20) NOT NULL DEFAULT 'ley',
  CONSTRAINT chk_holiday_source CHECK (source IN ('ley', 'ejecutivo', 'estadal', 'municipal')),
  CONSTRAINT chk_holiday_year_requerido CHECK (is_recurring = TRUE OR holiday_year IS NOT NULL)
);

CREATE INDEX idx_holiday_lookup ON hr_schema.holiday (holiday_year, tenant_id);
CREATE INDEX idx_holiday_date ON hr_schema.holiday (date);

CREATE TABLE IF NOT EXISTS hr_schema.incapacity (
    incapacity_id SERIAL PRIMARY KEY,
    branch_id UUID  REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
    employee_id UUID  REFERENCES hr_schema.employee(employee_id),
    type VARCHAR(50),
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    percentage_to_pay DECIMAL(5, 2) NOT NULL,
    days_paying INTEGER DEFAULT 3,
    is_active BOOLEAN DEFAULT TRUE
);

CREATE INDEX search_branch_index ON hr_schema.incapacity(branch_id);
CREATE INDEX incapacity_search_idx ON hr_schema.incapacity(employee_id);
CREATE INDEX filter_by_periods_idx ON hr_schema.incapacity(period_start, period_end);

-- MODULO DE NOMINA

CREATE TABLE IF NOT EXISTS paysheet_status(
	status_id SERIAL PRIMARY KEY NOT NULL,
	status_description VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS payroll_concept(
	concept_id SERIAL PRIMARY KEY NOT NULL,
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id),
	name VARCHAR(100) NOT NULL,
	type VARCHAR(20) NOT NULL, -- 'earning' o 'deduction'
	calculation_method VARCHAR(30) NOT NULL, -- 'fixed', 'percentage', 'fromula', 'manual'
	is_taxable BOOLEAN DEFAULT TRUE,
	is_active BOOLEAN DEFAULT TRUE,
	base_value NUMERIC(19, 4) DEFAULT 0,
	code VARCHAR(10) NOT NULL,
	-- Articulo LOTTT que fundamenta el concepto; se imprime en el recibo (Art. 106)
	article VARCHAR(20),
	-- Regla de oro: normal (Art. 104) para recargos y beneficios del dia a dia;
	-- integral (Art. 122) para prestaciones e indemnizaciones. No intercambiables.
	salary_basis VARCHAR(10) NOT NULL DEFAULT 'normal',
	CONSTRAINT chk_payroll_concept_salary_basis CHECK (salary_basis IN ('normal', 'integral')),
	-- Permite backfill idempotente via ON CONFLICT en
	-- provision_tenant_payroll_concepts() cuando se agregan filas
	-- nuevas a la plantilla despues de que un tenant ya fue provisionado.
	CONSTRAINT uq_payroll_concept_tenant_code UNIQUE (tenant_id, code)
);

-- Plantilla de conceptos de nomina predeterminados (NO scoped por tenant).
-- La funcion provision_tenant_payroll_concepts() la copia a payroll_concept por tenant.
CREATE TABLE IF NOT EXISTS hr_schema.payroll_concept_template(
	template_id SERIAL PRIMARY KEY NOT NULL,
	name VARCHAR(100) NOT NULL,
	type VARCHAR(20) NOT NULL, -- 'earning' o 'deduction'
	calculation_method VARCHAR(30) NOT NULL, -- 'fixed', 'percentage', 'formula', 'manual'
	is_taxable BOOLEAN DEFAULT TRUE,
	base_value NUMERIC(19, 4) DEFAULT 0,
	code VARCHAR(10) NOT NULL UNIQUE,
	article VARCHAR(20),
	salary_basis VARCHAR(10) NOT NULL DEFAULT 'normal',
	-- FALSE para conceptos definidos pero no liberados: hoy las retenciones
	-- venezolanas (IVSS, INCES, FAOV, Paro Forzoso, ISLR), sin especificacion
	-- de calculo. Se provisionan inactivas al tenant.
	is_active BOOLEAN NOT NULL DEFAULT TRUE,
	CONSTRAINT chk_payroll_concept_template_salary_basis CHECK (salary_basis IN ('normal', 'integral'))
);

COMMENT ON TABLE hr_schema.payroll_concept_template IS
	'Plantilla de conceptos de nomina (Venezuela, LOTTT). Copiada a payroll_concept por tenant via provision_tenant_payroll_concepts(). Los valores percentage se almacenan como fraccion (ej. 0.30 = 30%).';

CREATE TABLE IF NOT EXISTS paysheet(
	paysheet_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id),
	branch_id UUID NOT NULL REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
	period_start DATE NOT NULL,
	period_end DATE NOT NULL,
	payment_date TIMESTAMP,
	total_earnings NUMERIC(19, 4) NOT NULL DEFAULT 0,
	total_deductions NUMERIC(19, 4) NOT NULL DEFAULT 0,
	net_total NUMERIC(19, 4) NOT NULL DEFAULT 0,
	status_id INTEGER NOT NULL REFERENCES hr_schema.paysheet_status(status_id),
	created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

--Indice para la consulta de nominas por periodo de pago
CREATE INDEX idx_paysheet_period_dates ON hr_schema.paysheet (tenant_id, period_start, period_end);

CREATE TABLE IF NOT EXISTS paysheet_detail(
	detail_id UUID NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
	paysheet_id UUID NOT NULL REFERENCES hr_schema.paysheet(paysheet_id) ON DELETE CASCADE,
	employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id),
	contract_id UUID NOT NULL REFERENCES hr_schema.contract(contract_id),
	payment_method_id INTEGER NOT NULL REFERENCES general_schema.payment_method(payment_method_id),
	gross_salary NUMERIC(19, 4) NOT NULL,
	total_earnings NUMERIC(19, 4) NOT NULL DEFAULT 0,
	total_deduction NUMERIC(19, 4) NOT NULL DEFAULT 0,
	net_salary NUMERIC(19, 4) NOT NULL,
	status VARCHAR(20) NOT NULL DEFAULT 'Pending',
	pay_date DATE NOT NULL,
  recalc_needed BOOLEAN DEFAULT TRUE NOT NULL
);

-- Indice para agilizar la busqueda de todos los detalles bajo un paysheet_id
CREATE INDEX idx_paysheet_detail_paysheet_id ON hr_schema.paysheet_detail(paysheet_id);
-- Indice compuesto para la consulta del historial de pagos a un empleado
CREATE INDEX idx_paysheet_detail_emp_paydate ON hr_schema.paysheet_detail (employee_id, pay_date DESC);

CREATE TABLE IF NOT EXISTS payroll_movement (
	movement_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	detail_id UUID NOT NULL REFERENCES hr_schema.paysheet_detail(detail_id) ON DELETE CASCADE,
	concept_id INTEGER NOT NULL REFERENCES hr_schema.payroll_concept(concept_id),
	base_amount NUMERIC(19, 4) NOT NULL,
	calculated_amount NUMERIC(19, 4) NOT NULL,
	description TEXT
);

-- Indice para agilizar la busqueda de todos los movimientos bajo un detail_id
CREATE INDEX idx_payroll_movement_detail_id ON hr_schema.payroll_movement(detail_id);

-- ============================================================
-- MODULO LOTTT (Venezuela)
-- ============================================================
-- Estructuras de la Ley Organica del Trabajo, los Trabajadores y las
-- Trabajadoras (Gaceta Oficial N 6.076 Extraordinario, 07-05-2012).
-- Migraciones 006 a 018.
-- ============================================================

-- ------------------------------------------------------------
-- Parametros de nomina con vigencia temporal por tenant
-- ------------------------------------------------------------
-- Ninguna magnitud legal puede quedar hardcodeada: cambian por decreto
-- del Ejecutivo, por publicacion del BCV o por convencion colectiva.
-- La LOTTT es de orden publico (Arts. 2, 19): una convencion solo puede
-- MEJORAR el minimo legal, nunca reducirlo (Arts. 18.2, 434).
CREATE TABLE IF NOT EXISTS hr_schema.payroll_parameters (
	parameter_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
	param_key VARCHAR(60) NOT NULL,
	param_value NUMERIC(18, 6) NOT NULL,
	valid_from DATE NOT NULL,
	valid_to DATE, -- NULL = vigente
	source VARCHAR(120),
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
	CONSTRAINT uq_payroll_parameter_vigencia UNIQUE (tenant_id, param_key, valid_from),
	CONSTRAINT chk_payroll_parameter_value_positive CHECK (param_value >= 0),
	CONSTRAINT chk_payroll_parameter_vigencia CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

CREATE INDEX idx_payroll_parameters_lookup
	ON hr_schema.payroll_parameters (tenant_id, param_key, valid_from DESC);

-- ------------------------------------------------------------
-- Historial de salarios (Arts. 104, 122, 142)
-- ------------------------------------------------------------
-- El Art. 142.a exige el salario integral VIGENTE EN CADA TRIMESTRE, y el
-- Art. 142.b/c el ULTIMO salario integral. Con un unico base_salary mutable
-- no se puede reconstruir ninguno de los dos.
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

CREATE INDEX idx_salary_history_lookup ON hr_schema.salary_history (employee_id, valid_from DESC);
CREATE INDEX idx_salary_history_tenant ON hr_schema.salary_history (tenant_id);

-- ------------------------------------------------------------
-- Horas con recargo (Arts. 117, 118, 120, 178, 182)
-- ------------------------------------------------------------
-- Una fila por evento: permite factores concurrentes (30% nocturno, 50%
-- extra, 50% feriado) y el control de los topes acumulados del Art. 178.
CREATE TABLE IF NOT EXISTS hr_schema.overtime_record (
	overtime_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id) ON DELETE CASCADE,
	branch_id UUID NOT NULL REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
	clocking_id INTEGER REFERENCES hr_schema.clocking(clocking_id) ON DELETE SET NULL,
	work_date DATE NOT NULL,
	kind VARCHAR(20) NOT NULL,
	hours NUMERIC(5, 2) NOT NULL,
	-- Factor efectivo del momento, no el parametro vigente hoy: el recalculo
	-- historico debe ser reproducible. Extra autorizada 1.50; sin permiso de
	-- Inspectoria 2.00 (Art. 182, doble recargo).
	rate_factor NUMERIC(4, 2) NOT NULL,
	inspectoria_authorized BOOLEAN NOT NULL DEFAULT FALSE,
	authorization_ref VARCHAR(120),
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
	CONSTRAINT chk_overtime_hours_positive CHECK (hours > 0),
	CONSTRAINT chk_overtime_rate_factor CHECK (rate_factor > 0),
	CONSTRAINT chk_overtime_kind CHECK (kind IN ('nocturna', 'extra', 'feriado', 'descanso'))
);

CREATE INDEX idx_overtime_employee_date ON hr_schema.overtime_record (employee_id, work_date DESC);
CREATE INDEX idx_overtime_tenant_date ON hr_schema.overtime_record (tenant_id, work_date);
CREATE INDEX idx_overtime_kind ON hr_schema.overtime_record (employee_id, kind, work_date);

-- ------------------------------------------------------------
-- Garantia de prestaciones sociales (Arts. 142.a, 142.b, 143)
-- ------------------------------------------------------------
-- 15 dias de salario integral por trimestre, adquiridos al iniciar el
-- trimestre. Cada trimestre congela su propia base salarial.
CREATE TABLE IF NOT EXISTS hr_schema.severance_deposit (
	deposit_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id) ON DELETE CASCADE,
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
	quarter_start DATE NOT NULL,
	quarter_end DATE NOT NULL,
	days NUMERIC(5, 2) NOT NULL DEFAULT 15,
	integral_daily_salary NUMERIC(18, 4) NOT NULL,
	amount NUMERIC(18, 4) NOT NULL,
	-- FALSE dispara la penalizacion del Art. 143: tasa ACTIVA del BCV.
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

CREATE INDEX idx_severance_deposit_employee ON hr_schema.severance_deposit (employee_id, quarter_start DESC);
CREATE INDEX idx_severance_deposit_tenant ON hr_schema.severance_deposit (tenant_id);
CREATE INDEX idx_severance_deposit_pendientes ON hr_schema.severance_deposit (employee_id)
	WHERE deposit_made = FALSE;

-- Intereses mensuales sobre la garantia depositada (Art. 143).
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

CREATE INDEX idx_severance_interest_employee ON hr_schema.severance_interest (employee_id, period_month DESC);
CREATE INDEX idx_severance_interest_deposit ON hr_schema.severance_interest (deposit_id);

-- Anticipos sobre la garantia: hasta 75%, causales taxativas (Art. 144).
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

CREATE INDEX idx_severance_advance_employee ON hr_schema.severance_advance (employee_id, request_date DESC);
CREATE INDEX idx_severance_advance_tenant ON hr_schema.severance_advance (tenant_id);
CREATE INDEX idx_severance_advance_aprobados ON hr_schema.severance_advance (employee_id)
	WHERE status = 'aprobado';

-- ------------------------------------------------------------
-- Vacaciones y bono vacacional (Arts. 121, 190, 192, 195, 196)
-- ------------------------------------------------------------
-- Una fila por anio de servicio: el derecho se causa anualmente y hay que
-- distinguir lo causado de lo disfrutado (Art. 195).
CREATE TABLE IF NOT EXISTS hr_schema.vacation_period (
	vacation_period_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id) ON DELETE CASCADE,
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
	service_year INTEGER NOT NULL,
	period_start DATE NOT NULL,
	period_end DATE NOT NULL,
	-- Art. 190: 15 dias habiles al cumplir el anio 1, +1 por anio, tope 30.
	days_earned NUMERIC(5, 2) NOT NULL,
	-- Art. 192: 15 dias +1 por anio, tope 30. Caracter salarial.
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

CREATE INDEX idx_vacation_period_employee ON hr_schema.vacation_period (employee_id, service_year DESC);
CREATE INDEX idx_vacation_period_tenant ON hr_schema.vacation_period (tenant_id);
CREATE INDEX idx_vacation_period_pendientes ON hr_schema.vacation_period (employee_id)
	WHERE status IN ('causado', 'disfrutado');

-- ------------------------------------------------------------
-- Utilidades y bonificacion de fin de anio (Arts. 131, 132, 136, 137, 140)
-- ------------------------------------------------------------
-- Reparto colectivo: la cuota de cada trabajador depende de la sumatoria de
-- TODOS los salarios devengados (Art. 136), por lo que requiere el periodo
-- completo cerrado.
CREATE TABLE IF NOT EXISTS hr_schema.profit_sharing_period (
	profit_period_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
	fiscal_year INTEGER NOT NULL,
	fiscal_year_start DATE NOT NULL,
	fiscal_year_end DATE NOT NULL,
	-- Proviene del cierre contable (contexto finances). No se imputan
	-- perdidas de ejercicios anteriores (Art. 135).
	liquid_benefits NUMERIC(18, 4),
	distribution_percentage NUMERIC(5, 4) NOT NULL DEFAULT 0.15,
	distributable_amount NUMERIC(18, 4),
	total_earned_salaries NUMERIC(18, 4),
	-- Entidades sin fines de lucro: exentas del reparto, obligadas a la
	-- bonificacion de fin de anio de minimo 30 dias (Art. 140).
	is_non_profit BOOLEAN NOT NULL DEFAULT FALSE,
	status VARCHAR(15) NOT NULL DEFAULT 'abierto',
	closed_at TIMESTAMP,
	payment_deadline DATE, -- 2 meses tras el cierre (Art. 137)
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
	CONSTRAINT uq_profit_sharing_period_anio UNIQUE (tenant_id, fiscal_year),
	CONSTRAINT chk_profit_period_fechas CHECK (fiscal_year_end > fiscal_year_start),
	CONSTRAINT chk_profit_period_porcentaje CHECK (distribution_percentage >= 0.15),
	CONSTRAINT chk_profit_period_status CHECK (status IN ('abierto', 'calculado', 'cerrado')),
	CONSTRAINT chk_profit_period_cierre CHECK (status <> 'cerrado' OR closed_at IS NOT NULL)
);

CREATE INDEX idx_profit_sharing_period_tenant ON hr_schema.profit_sharing_period (tenant_id, fiscal_year DESC);

CREATE TABLE IF NOT EXISTS hr_schema.profit_sharing_detail (
	profit_detail_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	profit_period_id UUID NOT NULL REFERENCES hr_schema.profit_sharing_period(profit_period_id) ON DELETE CASCADE,
	employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id) ON DELETE CASCADE,
	earned_salary NUMERIC(18, 4) NOT NULL,
	complete_months INTEGER NOT NULL,
	daily_salary NUMERIC(18, 4) NOT NULL,
	raw_quota NUMERIC(18, 4),
	-- Topes del Art. 131: minimo 30 dias, maximo 120, prorrateados.
	min_cap NUMERIC(18, 4) NOT NULL,
	max_cap NUMERIC(18, 4) NOT NULL,
	final_amount NUMERIC(18, 4),
	-- Bonificacion de fin de anio ya entregada (Art. 132). Si no hubo
	-- beneficios, NO esta sujeta a repeticion.
	advance_paid NUMERIC(18, 4) NOT NULL DEFAULT 0,
	advance_paid_at DATE,
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
	CONSTRAINT uq_profit_sharing_detail UNIQUE (profit_period_id, employee_id),
	CONSTRAINT chk_profit_detail_meses CHECK (complete_months >= 0 AND complete_months <= 12),
	CONSTRAINT chk_profit_detail_caps CHECK (max_cap >= min_cap),
	CONSTRAINT chk_profit_detail_advance CHECK (advance_paid >= 0)
);

CREATE INDEX idx_profit_sharing_detail_period ON hr_schema.profit_sharing_detail (profit_period_id);
CREATE INDEX idx_profit_sharing_detail_employee ON hr_schema.profit_sharing_detail (employee_id);

-- ------------------------------------------------------------
-- Liquidacion final (Arts. 92, 106, 142, 144, 154, 195)
-- ------------------------------------------------------------
-- Persiste AMBAS vias del Art. 142 y cual se eligio: ante un reclamo hay
-- que demostrar por que se pago ese monto, y la prescripcion de
-- prestaciones es de 10 anios (Art. 51).
CREATE TABLE IF NOT EXISTS hr_schema.settlement (
	settlement_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id) ON DELETE CASCADE,
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
	branch_id UUID REFERENCES general_schema.branch(branch_id) ON DELETE SET NULL,
	termination_date DATE NOT NULL,
	payment_due_date DATE NOT NULL, -- egreso + 5 dias (Art. 142.f)
	payment_date DATE,
	hire_date DATE NOT NULL,
	complete_years INTEGER NOT NULL,
	-- Si supera 6, el retroactivo redondea a anio completo (Art. 142.c)
	remainder_months INTEGER NOT NULL,
	last_integral_daily_salary NUMERIC(18, 4) NOT NULL, -- Art. 122
	last_normal_daily_salary NUMERIC(18, 4) NOT NULL,   -- Art. 104
	via1_amount NUMERIC(18, 4), -- garantia acumulada (142.a + 142.b)
	via2_amount NUMERIC(18, 4), -- retroactivo (142.c)
	selected_via VARCHAR(20),   -- se paga la MAYOR (142.d)
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

CREATE INDEX idx_settlement_employee ON hr_schema.settlement (employee_id, termination_date DESC);
CREATE INDEX idx_settlement_tenant ON hr_schema.settlement (tenant_id, termination_date DESC);
CREATE INDEX idx_settlement_pendientes ON hr_schema.settlement (payment_due_date)
	WHERE payment_date IS NULL AND status <> 'anulada';

-- Desglose auditable por concepto (Art. 106). El total de la cabecera debe
-- ser la suma verificable de estos renglones.
CREATE TABLE IF NOT EXISTS hr_schema.settlement_item (
	settlement_item_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	settlement_id UUID NOT NULL REFERENCES hr_schema.settlement(settlement_id) ON DELETE CASCADE,
	code VARCHAR(15) NOT NULL, -- HR-VE-XX
	concept_name VARCHAR(120) NOT NULL,
	article VARCHAR(20) NOT NULL,
	salary_basis VARCHAR(10) NOT NULL,
	base_amount NUMERIC(18, 4) NOT NULL,
	days NUMERIC(7, 2),
	-- Negativo para los que restan: anticipos (Art. 144), descuentos (Art. 154)
	amount NUMERIC(18, 4) NOT NULL,
	formula_text TEXT,
	sort_order INTEGER NOT NULL DEFAULT 0,
	CONSTRAINT chk_settlement_item_salary_basis CHECK (salary_basis IN ('normal', 'integral')),
	CONSTRAINT chk_settlement_item_base CHECK (base_amount >= 0)
);

CREATE INDEX idx_settlement_item_settlement ON hr_schema.settlement_item (settlement_id, sort_order);

-- ------------------------------------------------------------
-- Beneficiarios por fallecimiento (Art. 145)
-- ------------------------------------------------------------
-- Reparto en partes iguales entre los reclamantes validos, SIN preferencia
-- entre parentescos. El divisor se fija al cerrar la ventana de 3 meses.
CREATE TABLE IF NOT EXISTS hr_schema.employee_beneficiary (
	beneficiary_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	employee_id UUID NOT NULL REFERENCES hr_schema.employee(employee_id) ON DELETE CASCADE,
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
	settlement_id UUID REFERENCES hr_schema.settlement(settlement_id) ON DELETE SET NULL,
	full_name VARCHAR(200) NOT NULL,
	doc_number VARCHAR(100) NOT NULL,
	identification_type_id INTEGER REFERENCES general_schema.identification_type(identification_type_id) ON DELETE SET NULL,
	relationship VARCHAR(20) NOT NULL,
	birth_date DATE,
	claim_date DATE,
	validated BOOLEAN NOT NULL DEFAULT FALSE,
	validated_at DATE,
	share_percentage NUMERIC(7, 4),
	share_amount NUMERIC(18, 4),
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
	CONSTRAINT uq_employee_beneficiary_doc UNIQUE (employee_id, doc_number),
	CONSTRAINT chk_beneficiary_relationship CHECK (relationship IN ('hijo', 'conyuge', 'pareja_estable', 'padre', 'madre', 'nieto_huerfano')),
	CONSTRAINT chk_beneficiary_share CHECK (share_percentage IS NULL OR (share_percentage > 0 AND share_percentage <= 100)),
	CONSTRAINT chk_beneficiary_validacion CHECK (validated = FALSE OR validated_at IS NOT NULL)
);

CREATE INDEX idx_beneficiary_employee ON hr_schema.employee_beneficiary (employee_id);
CREATE INDEX idx_beneficiary_settlement ON hr_schema.employee_beneficiary (settlement_id);
CREATE INDEX idx_beneficiary_tenant ON hr_schema.employee_beneficiary (tenant_id);

-- ------------------------------------------------------------
-- Deducciones al salario (Arts. 152, 154, 412, 413)
-- ------------------------------------------------------------
-- Tope de 1/3 del periodo durante la relacion y 50% del credito a favor en
-- la liquidacion (Art. 154). La cuota sindical exige autorizacion expresa.
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
	-- Arts. 412/413: la cuota sindical exige autorizacion expresa
	CONSTRAINT chk_employee_deduction_sindical_autorizada CHECK (
		kind <> 'sindical'
		OR (authorized = TRUE AND authorization_date IS NOT NULL)
	),
	CONSTRAINT chk_employee_deduction_autorizacion CHECK (
		authorized = FALSE OR authorization_date IS NOT NULL
	)
);

CREATE INDEX idx_employee_deduction_employee ON hr_schema.employee_deduction (employee_id);
CREATE INDEX idx_employee_deduction_tenant ON hr_schema.employee_deduction (tenant_id);
CREATE INDEX idx_employee_deduction_activas ON hr_schema.employee_deduction (employee_id, kind)
	WHERE is_active = TRUE AND outstanding_balance > 0;
