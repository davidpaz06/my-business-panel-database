DO $$
DECLARE
	v_employee_id UUID;
	v_delete_employee_id UUID;
	v_user UUID := (SELECT user_id FROM core.users LIMIT 1);
	v_schedule_id INTEGER := 1;
BEGIN
	RAISE NOTICE 'Comenzando prueba para la creacion de empleado y contrato.';

	v_employee_id := rrhh_module.create_new_employee(
		p_start_date => '2025-10-01',
        p_end_date => '2026-10-01',
        p_hours => 45,
        p_base_salary => 2500.50,
        p_duties => 'Software Engineer Duties',
        p_user_id => v_user,
        p_first_name => 'Juan',
        p_last_name => 'Perez',
        p_doc_number => '701230456',
        p_phone => '88887777',
        p_email => 'juan.perez@test.com',
        p_schedule_id => v_schedule_id
	);

	IF v_employee_id IS NOT NULL THEN
		RAISE NOTICE 'Empleado creado con id: %', v_employee_id;
	ELSE
		RAISE EXCEPTION 'Error. No se creo el empleado';
	END IF;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE
	v_temp_contract_id UUID;
	v_initial_contract_id UUID;
	v_employee_id UUID := (SELECT employee_id FROM rrhh_module.employee LIMIT 1);
BEGIN
	RAISE NOTICE 'Comenzando prueba de trigger de validacion.';
	SELECT contract_id INTO v_initial_contract_id
	FROM rrhh_module.employee
	WHERE employee_id = v_employee_id;

	RAISE NOTICE 'Forzando falla del trigger';
	UPDATE rrhh_module.contract
	SET end_date = '2025-09-01'
	WHERE contract_id = v_initial_contract_id;

	RAISE EXCEPTION 'Fallo de prueba: Se permitio la creacion del contrato';
EXCEPTION
	WHEN OTHERS THEN
		IF SQLSTATE = 'P0001' THEN
			RAISE NOTICE 'EXITO. Actualizacion bloqueada por error de logica del contrato';
		ELSE
			RAISE EXCEPTION 'Se lanzo una excepcion inesperada: %', SQLERRM;
		END IF;
END;
$$ LANGUAGE plpgsql;