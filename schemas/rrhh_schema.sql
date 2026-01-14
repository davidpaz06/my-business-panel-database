drop schema if exists rrhh_module cascade;
CREATE SCHEMA IF NOT EXISTS rrhh_module;
SET search_path to rrhh_module;

-- MODULO DE EMPLEADO

CREATE TABLE IF NOT EXISTS payment_schedule(
	payment_schedule_id SERIAL PRIMARY KEY NOT NULL,
	description VARCHAR(100) NOT NULL,
	daycount INTEGER NOT NULL
);
INSERT INTO rrhh_module.payment_schedule(description, daycount) VALUES
('Monthly', 30),
('Fortnight', 15),
('Weekly', 7),
('Daily', 1)
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS contract(
	contract_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	tenant_id UUID NOT NULL REFERENCES core.tenant(tenant_id),
	start_date DATE NOT NULL,
	end_date DATE NOT NULL,
	hours INTEGER NOT NULL,
	base_salary NUMERIC(19, 4) NOT NULL,
	duties TEXT
);
--Indice para filtracion o busqueda por rango de precios
CREATE INDEX idx_contract_base_salary ON rrhh_module.contract (base_salary);

CREATE TABLE IF NOT EXISTS employee(
	employee_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	user_id UUID NOT NULL REFERENCES core.users(user_id) ON DELETE CASCADE,
	tenant_id UUID NOT NULL REFERENCES core.tenant(tenant_id),
	first_name VARCHAR(100) NOT NULL,
	last_name VARCHAR(100) NOT NULL,
	doc_number VARCHAR(100) NOT NULL UNIQUE,
	phone VARCHAR(100) NOT NULL,
	email VARCHAR(100) NOT NULL UNIQUE,
	contract_id UUID NOT NULL REFERENCES rrhh_module.contract(contract_id) ON DELETE CASCADE,
	schedule_id INTEGER NOT NULL REFERENCES rrhh_module.payment_schedule(payment_schedule_id),
	is_active BOOLEAN DEFAULT true,
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

ALTER TABLE rrhh_module.employee
	ADD COLUMN IF NOT EXISTS tenant_id UUID NOT NULL REFERENCES core.tenant(tenant_id);
	
--Indice para que se pueda garantizar que no haya empleados duplicados
CREATE UNIQUE INDEX idx_employee_doc_number ON rrhh_module.employee (doc_number);

--Inidice para la recuperacion de cuentas o autenticacion del empleado
CREATE UNIQUE INDEX idx_employee_email ON rrhh_module.employee (email);

--Indices destinados para la aceleracion de los JOINS
CREATE INDEX idx_employee_user_id ON rrhh_module.employee (user_id);
CREATE INDEX idx_employee_contract_id ON rrhh_module.employee (contract_id);
CREATE INDEX idx_employee_scheduled_id ON rrhh_module.employee (schedule_id);

--Indice que se utilizara unicamente para el proceso de nomina y generacion de reportes
CREATE INDEX idx_employee_is_active ON rrhh_module.employee (is_active);

CREATE TABLE IF NOT EXISTS clocking(
	clocking_id SERIAL PRIMARY KEY NOT NULL,
	employee_id UUID NOT NULL REFERENCES rrhh_module.employee(employee_id),
	branch_id UUID NOT NULL REFERENCES core.branch(branch_id),
	clock_in TIMESTAMP,
	clock_out TIMESTAMP,
	turn_hours NUMERIC NOT NULL DEFAULT 0
);

-- Indice para buscar los turnos de un empleado dentro de un rango de fechas
CREATE INDEX idx_track_employee_hours_in ON rrhh_module.clocking (employee_id, clock_in DESC);
-- Indice para ubicar turnos por sucursal
CREATE INDEX idx_track_hours_branch_id ON rrhh_module.clocking (branch_id);

-- MODULO DE NOMINA

CREATE TABLE IF NOT EXISTS paysheet_status(
	status_id SERIAL PRIMARY KEY NOT NULL,
	status_description VARCHAR(100)
);
INSERT INTO rrhh_module.paysheet_status(status_description) VALUES
('Pending'),
('Completed'),
('Canceled')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS payroll_concept(
	concept_id SERIAL PRIMARY KEY NOT NULL,
	tenant_id UUID NOT NULL REFERENCES core.tenant(tenant_id),
	name VARCHAR(100) NOT NULL,
	type VARCHAR(20) NOT NULL, -- 'earning' o 'deduction'
	calculation_method VARCHAR(30) NOT NULL, -- 'fixed', 'percentage', 'fromula', 'manual'
	is_taxable BOOLEAN DEFAULT TRUE,
	is_active BOOLEAN DEFAULT TRUE
)

--Indice para filtracion por conceptos
CREATE INDEX idx_income_concept_apply ON rrhh_module.income_concept(ccss_apply, tax_apply);

CREATE TABLE IF NOT EXISTS paysheet(
	paysheet_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	tenant_id UUID NOT NULL REFERENCES core.tenant(tenant_id),
	branch_id UUID NOT NULL REFERENCES core.branch(branch_id),
	period_start DATE NOT NULL,
	period_end DATE NOT NULL,
	payment_date TIMESTAMP,
	total_earnings NUMERIC(19, 4) NOT NULL DEFAULT 0,
	total_deductions NUMERIC(19, 4) NOT NULL DEFAULT 0,
	net_total NUMERIC(19, 4) NOT NULL DEFAULT 0,
	paysheet_status_id INTEGER NOT NULL REFERENCES rrhh_module.paysheet_status(status_id)
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
);

--Indice para la consulta de nominas por periodo de pago
CREATE INDEX idx_paysheet_period_dates ON rrhh_module.paysheet (tenant_id, period_start, period_end);

CREATE TABLE IF NOT EXISTS paysheet_detail(
	detail_id UUID NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
	paysheet_id UUID NOT NULL REFERENCES rrhh_module.paysheet(paysheet_id) ON DELETE CASCADE,
	employee_id UUID NOT NULL REFERENCES rrhh_module.employee(employee_id),
	contract_id UUID NOT NULL REFERENCES rrhh_module.contract(contract_id),
	payment_method_id INTEGER NOT NULL REFERENCES core.payment_method(payment_method_id),
	gross_salary NUMERIC(19, 4) NOT NULL,
	total_earnings NUMERIC(19, 4) NOT NULL DEFAULT 0,
	total_deduction NUMERIC(19, 4) NOT NULL DEFAULT 0,
	net_salary NUMERIC(19, 4) NOT NULL,
	status VARCHAR(20) NOT NULL DEFAULT 'Pending',
	pay_date DATE NOT NULL,
  recalc_needed BOOLEAN DEFAULT TRUE NOT NULL
);

-- Indice para agilizar la busqueda de todos los detalles bajo un paysheet_id
CREATE INDEX idx_paysheet_detail_paysheet_id ON rrhh_module.paysheet_detail(paysheet_id);
-- Indice compuesto para la consulta del historial de pagos a un empleado
CREATE INDEX idx_paysheet_detail_emp_paydate ON rrhh_module.paysheet_detail (employee_id, pay_date DESC);

CREATE TABLE IF NOT EXISTS payroll_movement (
	movement_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	detail_id UUID NOT NULL REFERENCES rrhh_module.paysheet_detail(detail_id) ON DELETE CASCADE,
	concept_id INTEGER NOT NULL REFERENCES rrhh_module.payroll_concept(concept_id),
	base_amount NUMERIC(19, 4) NOT NULL,
	calculated_amount NUMERIC(19, 4) NOT NULL,
	description TEXT
);

-- Indice para agilizar la busqueda de todos los movimientos bajo un detail_id
CREATE INDEX idx_payroll_movement_detail_id ON rrhh_module.payroll_movement(detail_id);
