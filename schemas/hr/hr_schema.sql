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
	end_date DATE NOT NULL,
	hours INTEGER NOT NULL,
	base_salary NUMERIC(19, 4) NOT NULL,
	duties TEXT,
	duties_type_id INTEGER REFERENCES hr_schema.duties_type(duties_type_id) ON DELETE SET NULL,
	turn_type INTEGER,
	turn_id INTEGER REFERENCES hr_schema.turn(turn_id) ON DELETE SET NULL
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
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
	
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

CREATE TABLE IF NOT EXISTS hr_schema.holiday (
  holiday_id SERIAL PRIMARY KEY NOT NULL,
  date TIMESTAMP NOT NULL,
  holiday_name VARCHAR(150) NOT NULL,
  is_freeday BOOLEAN NOT NULL DEFAULT TRUE,
  is_payable BOOLEAN NOT NULL DEFAULT TRUE
);

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
	code VARCHAR(10) NOT NULL
);

-- Indice para filtracion por conceptos
-- FIXME: column "ccss_apply" does not exist
-- CREATE INDEX IF NOT EXISTS idx_payroll_concept_apply ON hr_schema.payroll_concept(ccss_apply, tax_apply);

-- Plantilla de conceptos de nomina predeterminados (NO scoped por tenant).
-- La funcion provision_tenant_payroll_concepts() la copia a payroll_concept por tenant.
CREATE TABLE IF NOT EXISTS hr_schema.payroll_concept_template(
	template_id SERIAL PRIMARY KEY NOT NULL,
	name VARCHAR(100) NOT NULL,
	type VARCHAR(20) NOT NULL, -- 'earning' o 'deduction'
	calculation_method VARCHAR(30) NOT NULL, -- 'fixed', 'percentage', 'formula', 'manual'
	is_taxable BOOLEAN DEFAULT TRUE,
	base_value NUMERIC(19, 4) DEFAULT 0,
	code VARCHAR(10) NOT NULL UNIQUE
);

COMMENT ON TABLE hr_schema.payroll_concept_template IS
	'Plantilla de conceptos de nomina (Costa Rica). Copiada a payroll_concept por tenant via provision_tenant_payroll_concepts(). Los valores percentage se almacenan como fraccion (ej. 0.1067 = 10.67%).';

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
