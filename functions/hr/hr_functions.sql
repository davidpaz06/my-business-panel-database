SET SEARCH_PATH = hr_schema;

CREATE OR REPLACE FUNCTION hr_schema.create_new_employee(
    p_start_date DATE,
    p_end_date DATE,
    p_hours INTEGER,
    p_base_salary NUMERIC,
    p_duties TEXT,
    p_turn_type INTEGER,
    p_turn_id INTEGER,
    p_user_id UUID,
    p_tenant_id UUID,
    p_first_name CHARACTER VARYING,
    p_last_name CHARACTER VARYING,
    p_doc_number CHARACTER VARYING,
    p_phone CHARACTER VARYING,
    p_email CHARACTER VARYING,
    p_schedule_id INTEGER,
    p_branch_id UUID
  )
 RETURNS UUID
 LANGUAGE plpgsql
AS $function$

DECLARE
  v_new_contract_id UUID;
  v_new_employee_id UUID;
BEGIN

  IF NOT EXISTS (SELECT 1 FROM hr_schema.payment_schedule WHERE payment_schedule_id = p_schedule_id) THEN
    RAISE EXCEPTION 'Integrity error: schedule_id (schedule_id: %) doesnt exists', p_schedule_id;
  END IF;

  INSERT INTO hr_schema.contract (tenant_id, start_date, end_date, hours, base_salary, duties, turn_type, turn_id)
  VALUES (p_tenant_id, p_start_date, p_end_date, p_hours, p_base_salary, p_duties, p_turn_type, p_turn_id)
  RETURNING contract_id INTO v_new_contract_id;

  v_new_employee_id := gen_random_uuid();

  INSERT INTO hr_schema.employee (employee_id, user_id, first_name, last_name, doc_number, phone, email, contract_id, schedule_id, tenant_id, branch_id)
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
    RAISE EXCEPTION 'Integrity Error: Insert failed, cause of the error a non existent FOREIGN KEY (user_id or schedule_id).';
  WHEN others THEN
    RAISE EXCEPTION 'Error creating employee or contract: %', SQLERRM;
END;
$function$; 

CREATE OR REPLACE FUNCTION hr_schema.update_paysheet_state (
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
    FROM hr_schema.paysheet_status
    WHERE status_description = v_completed_status_name;

    IF v_completed_status_id IS NULL THEN
        RAISE EXCEPTION 'Error: Status with id % not found in db', v_completed_status_name;
    END IF;

    -- Obtenemos el id de estado actual de la nómina
    SELECT status_id INTO v_current_status_id
    FROM hr_schema.paysheet
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
    FROM hr_schema.paysheet_detail
    WHERE paysheet_id = p_paysheet_id
      AND recalc_needed = TRUE;

    IF v_pending_recalculations > 0 THEN
        -- Si hay calculos pendientes, lanzamos una excepcion que termina el proceso
        RAISE EXCEPTION 'Integrity Error: Cant finish the paysheet process. % recalculations needed', v_pending_recalculations;
    END IF;

    --Si no hay pendientes, actualizamos el estado a 'Completed'
    UPDATE hr_schema.paysheet
    SET
      status_id = v_completed_status_id
    WHERE paysheet_id = p_paysheet_id;

    RETURN 'Paysheet finished ' || p_paysheet_id;
END;
$$ LANGUAGE plpgsql;

-- Funcion para la generacion de reportes ccss mensuales de periodos especificos
CREATE OR REPLACE FUNCTION hr_schema.generate_monthly_ccss(
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
	FROM hr_schema.paysheet_status
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
		hr_schema.paysheet_detail pd
	INNER JOIN
		hr_schema.paysheet p ON pd.paysheet_id = p.paysheet_id
	WHERE
		EXTRACT(YEAR FROM p.payment_day) = p_year
		AND EXTRACT(MONTH FROM p.payment_day) = p_month
		AND p.status_id = v_status_completed_id;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION hr_schema.validate_contract_dates()
RETURNS TRIGGER AS $$
BEGIN
	IF NEW.end_date IS NOT NULL AND NEW.end_date < NEW.start_date THEN
		RAISE EXCEPTION 'Integrity Error. The end of the contract must happen after it even starts.';
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS validate_contract_dates ON hr_schema.contract;
CREATE TRIGGER validate_contract_dates
BEFORE INSERT OR UPDATE ON hr_schema.contract
FOR EACH ROW
EXECUTE FUNCTION hr_schema.validate_contract_dates();

CREATE OR REPLACE FUNCTION hr_schema.protect_net_salary()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.net_salary IS DISTINCT FROM NEW.net_salary THEN
        PERFORM 1 FROM hr_schema.paysheet p
        	INNER JOIN hr_schema.paysheet_status ps ON p.status_id = ps.status_id
        	WHERE p.paysheet_id = NEW.paysheet_id AND ps.status_description = 'Completed';
        
        IF FOUND THEN
             RAISE EXCEPTION 'Integrity Error: The Net Salary cannot be modified for a paysheet that is already COMPLETED.';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS protect_net_salary ON hr_schema.paysheet_detail;
CREATE TRIGGER protect_net_salary
BEFORE INSERT OR UPDATE ON hr_schema.paysheet_detail
FOR EACH ROW
EXECUTE FUNCTION hr_schema.protect_net_salary();

CREATE OR REPLACE FUNCTION hr_schema.close_suspention()
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  UPDATE hr_schema.suspention
  SET is_active = false
  WHERE suspention_end IS NOT NULL
    AND suspention_end <= NOW()
    AND is_active = TRUE
  RETURNING 1 INTO v_count;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION hr_schema.close_suspention_trigger()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  
  IF NEW.suspention_end IS NOT NULL AND NEW.suspention_end <= NOW() THEN
    NEW.is_active := FALSE;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_close_suspention_on_write
BEFORE INSERT OR UPDATE ON hr_schema.suspention
FOR EACH ROW
EXECUTE FUNCTION hr_schema.close_suspention_trigger();
