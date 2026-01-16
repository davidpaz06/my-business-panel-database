CREATE OR REPLACE FUNCTION rrhh_module.create_new_employee(
  -- Parametros para la creacion del contrato
  p_start_date DATE,
  p_end_date DATE,
  p_hours INTEGER,
  p_base_salary DECIMAL(10, 2),
  p_duties TEXT,

  -- Parametros para la crecaion del empleado
  p_user_id UUID,
  p_tenant_id UUID,
  p_branch_id UUID,
  p_first_name VARCHAR(100),
  p_last_name VARCHAR(100),
  p_doc_number VARCHAR(100),
  p_phone VARCHAR(100),
  p_email VARCHAR(100),
  p_schedule_id INTEGER
)
RETURNS UUID AS $$

DECLARE
  v_new_contract_id UUID;
  v_new_employee_id UUID;
BEGIN

  IF NOT EXISTS (SELECT 1 FROM rrhh_module.payment_schedule WHERE payment_schedule_id = p_schedule_id) THEN
    RAISE EXCEPTION 'Integrity error: schedule_id (schedule_id: %) doesnt exists', p_schedule_id;
  END IF;

  INSERT INTO rrhh_module.contract (start_date, end_date, hours, base_salary, duties)
  VALUES (p_start_date, p_end_date, p_hours, p_base_salary, p_duties)
  RETURNING contract_id INTO v_new_contract_id;

  v_new_employee_id := gen_random_uuid();

  INSERT INTO rrhh_module.employee (employee_id, user_id, first_name, last_name, doc_number, phone, email, contract_id, schedule_id, tenant_id, branch_id)
  VALUES (
    v_new_employee_id,
    p_user_id,
    p_first_name,
    p_last_name,
    p_doc_number,
    p_phone,
    p_email,
    v_new_contract_id,
    p_schedule_id,
    p_tenant_id,
    p_branch_id
  );

  RETURN v_new_employee_id;

EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'Data Error: Document Number (%) or Email already exists.', p_doc_number;
  WHEN foreign_key_violation THEN
    RAISE EXCEPTION 'Integrity Error: Insert failed, cause of the error a non existent foreign key (user_id or schedule_id).';
  WHEN others THEN
    RAISE EXCEPTION 'Error creating employee or contract: %', SQLERRM;
END;
$$ LANGUAGE plpgsql; 

CREATE OR REPLACE FUNCTION rrhh_module.update_paysheet_state (
    p_paysheet_id UUID
)
RETURNS VARCHAR AS $$
DECLARE
    v_pending_recalculations INTEGER;
    v_current_status_id INTEGER;
    v_completed_status_id INTEGER;
    v_completed_status_name VARCHAR(50) := 'Completed'; 
BEGIN
    -- Obtenemos el id del estado completado del catálogo
    SELECT status_id INTO v_completed_status_id
    FROM rrhh_module.paysheet_status
    WHERE status_description = v_completed_status_name;

    IF v_completed_status_id IS NULL THEN
        RAISE EXCEPTION 'Error: Status with id % not found in db', v_completed_status_name;
    END IF;

    -- Obtenemos el id de estado actual de la nómina
    SELECT paysheet_status_id INTO v_current_status_id
    FROM rrhh_module.paysheet
    WHERE paysheet_id = p_paysheet_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Error: Paysheet with id % not found.', p_paysheet_id;
    END IF;

    -- Chequeamos que ya fue completada
    IF v_current_status_id = v_completed_status_id THEN
        RETURN 'Paysheet already completed.';
    END IF;

    -- Revisamos si quedan calculos pendientes
    SELECT COUNT(*)
    INTO v_pending_recalculations
    FROM rrhh_module.paysheet_detail
    WHERE paysheet_id = p_paysheet_id
      AND recalc_needed = TRUE;

    IF v_pending_recalculations > 0 THEN
        -- Si hay calculos pendientes, lanzamos una excepcion que termina el proceso
        RAISE EXCEPTION 'Integrity Error: Cant finish the paysheet process. % recalculations needed', v_pending_recalculations;
    END IF;

    --Si no hay pendientes, actualizamos el estado a 'Completed'
    UPDATE rrhh_module.paysheet
    SET
        paysheet_status_id = v_completed_status_id
    WHERE paysheet_id = p_paysheet_id;

    RETURN 'Paysheet finished ' || p_paysheet_id;
END;
$$ LANGUAGE plpgsql;

-- Funcion para la generacion de reportes ccss mensuales de periodos especificos
CREATE OR REPLACE FUNCTION rrhh_module.generate_monthly_ccss(
	p_year INTEGER,
	p_month INTEGER
)
RETURNS TABLE (
	total_employee NUMERIC(10, 2),
	total_tenant NUMERIC(10, 2),
	total NUMERIC(10, 2)
) AS $$
DECLARE
	v_status_completed_id INTEGER;
	v_completed_status VARCHAR(15) := 'Completed';
BEGIN
	SELECT status_id INTO v_status_completed_id
	FROM rrhh_module.paysheet_status
	WHERE status_description = v_completed_status;

	IF v_status_completed_id IS NULL THEN
		RAISE EXCEPTION 'Status Completed not found in db.';
	END IF;

	RETURN QUERY
	SELECT
		COALESCE(SUM(pd.ccss_employee_deduction), 0) AS total_employee,
		COALESCE(SUM(pd.ccss_tenant_deduction), 0) AS total_tenant,
		COALESCE(SUM(pd.ccss_employee_deduction + ccss_tenant_deduction), 0) AS total
	FROM
		rrhh_module.paysheet_detail pd
	INNER JOIN
		rrhh_module.paysheet p ON pd.paysheet_id = p.paysheet_id
	WHERE
		EXTRACT(YEAR FROM p.payment_day) = p_year
		AND EXTRACT(MONTH FROM p.payment_day) = p_month
		AND p.paysheet_status_id = v_status_completed_id;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION rrhh_module.validate_contract_dates()
RETURNS TRIGGER AS $$
BEGIN
	IF NEW.end_date IS NOT NULL AND NEW.end_date < NEW.start_date THEN
		RAISE EXCEPTION 'Integrity Error. The end of the contract must happen after it even starts.';
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS validate_contract_dates ON rrhh_module.contract;
CREATE TRIGGER validate_contract_dates
BEFORE INSERT OR UPDATE ON rrhh_module.contract
FOR EACH ROW
EXECUTE FUNCTION rrhh_module.validate_contract_dates();

CREATE OR REPLACE FUNCTION rrhh_module.protect_net_salary()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.net_salary IS DISTINCT FROM NEW.net_salary THEN
        PERFORM 1 FROM rrhh_module.paysheet p
        	INNER JOIN rrhh_module.paysheet_status ps ON p.paysheet_status_id = ps.status_id
        	WHERE p.paysheet_id = NEW.paysheet_id AND ps.status_description = 'Completed';
        
        IF FOUND THEN
             RAISE EXCEPTION 'Integrity Error: The Net Salary cannot be modified for a paysheet that is already COMPLETED.';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS protect_net_salary ON rrhh_module.paysheet_detail;
CREATE TRIGGER protect_net_salary
BEFORE INSERT OR UPDATE ON rrhh_module.paysheet_detail
FOR EACH ROW
EXECUTE FUNCTION rrhh_module.protect_net_salary();
