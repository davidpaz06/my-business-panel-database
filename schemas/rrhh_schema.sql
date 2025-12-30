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
('daily', 1)
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS contract(
	contract_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	start_date DATE NOT NULL,
	end_date DATE NOT NULL,
	hours INTEGER NOT NULL,
	base_salary NUMERIC(10, 2) NOT NULL,
	duties TEXT
);
--Indice para filtracion o busqueda por rango de precios
CREATE INDEX idx_contract_base_salary ON rrhh_module.contract (base_salary);

CREATE TABLE IF NOT EXISTS employee(
	employee_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	user_id UUID NOT NULL REFERENCES core.users(user_id) ON DELETE CASCADE,
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
	turn_hours INTEGER NOT NULL DEFAULT 0
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

-- Catalogo de deducciones, este catalogo sera consumido unicamente por el backend
CREATE TABLE IF NOT EXISTS deduction(
	deduction_id SERIAL PRIMARY KEY NOT NULL,
	deduction_name VARCHAR(100) NOT NULL,
	employee_percentage INTEGER NOT NULL,
	tenant_percentage INTEGER,
	is_current BOOLEAN DEFAULT true NOT NULL 
);

-- Catalogo que ayuda a la uniformidad de los calculos
CREATE TABLE IF NOT EXISTS income_concept(
	income_id SERIAL PRIMARY KEY NOT NULL,
	concept_name VARCHAR(100) NOT NULL,
	calculation_type VARCHAR(50) NOT NULL, -- Fijo, Variable o Acumulable
	ccss_apply BOOLEAN,
	tax_apply BOOLEAN
);

--Indice para filtracion por conceptos
CREATE INDEX idx_income_concept_apply ON rrhh_module.income_concept(ccss_apply, tax_apply);

CREATE TABLE IF NOT EXISTS paysheet(
	paysheet_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	branch_id UUID NOT NULL REFERENCES core.branch(branch_id),
	period_start_date DATE NOT NULL,
	period_end_date DATE NOT NULL,
	payment_day TIMESTAMP,
	payment_amount INTEGER NOT NULL DEFAULT 0,
	paysheet_status_id INTEGER NOT NULL REFERENCES rrhh_module.paysheet_status(status_id)
);

--Indice para la consulta de nominas por periodo de pago
CREATE INDEX idx_paysheet_period_dates ON rrhh_module.paysheet (period_start_date, period_end_date);

CREATE TABLE IF NOT EXISTS paysheet_detail(
	detail_id UUID NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
	paysheet_id UUID NOT NULL REFERENCES rrhh_module.paysheet(paysheet_id),
	employee_id UUID NOT NULL REFERENCES rrhh_module.employee(employee_id),
	payment_method_id INTEGER NOT NULL REFERENCES core.payment_method(payment_method_id),
	gross_salary NUMERIC(10, 2) CHECK (gross_salary >= 0) NOT NULL,
	ccss_employee_deduction NUMERIC(10, 2) DEFAULT 0,
	ccss_tenant_deduction NUMERIC(10, 2) DEFAULT 0,
	income_tax_amount NUMERIC(10, 2) NOT NULL DEFAULT 0,
	total_deduction NUMERIC(10, 2) NOT NULL DEFAULT 0,
	net_salary NUMERIC(12, 3) NOT NULL,
	pay_date DATE NOT NULL,
  recalc_needed BOOLEAN DEFAULT TRUE NOT NULL
);

-- Indice para agilizar la busqueda de todos los detalles bajo un paysheet_id
CREATE INDEX idx_paysheet_detail_paysheet_id ON rrhh_module.paysheet_detail(paysheet_id);
-- Indice compuesto para la consulta del historial de pagos a un empleado
CREATE INDEX idx_paysheet_detail_emp_paydate ON rrhh_module.paysheet_detail (employee_id, pay_date DESC);

CREATE TABLE IF NOT EXISTS income_register(
	income_register_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	detail_id UUID NOT NULL REFERENCES rrhh_module.paysheet_detail(detail_id),
	concept_id INTEGER NOT NULL REFERENCES rrhh_module.income_concept(income_id),
	base_quantity NUMERIC(10, 2) NOT NULL,
	calculated_amount NUMERIC(10, 2) NOT NULL
);

-- Indice para agilizar Joins
CREATE INDEX idx_income_register_detail_id ON rrhh_module.income_register(detail_id);
CREATE INDEX idx_income_register_concept_id ON rrhh_module.income_register(concept_id);

