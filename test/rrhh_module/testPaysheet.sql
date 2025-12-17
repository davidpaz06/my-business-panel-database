DO $$
DECLARE
	v_employee_id UUID;
	v_paysheet_id UUID := gen_random_uuid();
	v_detail_id UUID := gen_random_uuid();
	v_user_id UUID;
	v_branch_id UUID := (SELECT branch_id FROM core.branch LIMIT 1);

	v_pending_status INTEGER;
	v_completed_status INTEGER;
	v_schedule_id INTEGER := 1;
BEGIN
	RAISE NOTICE '<======> Preparacion de datos para la prueba <======>';

	PERFORM set_config('test.paysheet_id', v_paysheet_id::TEXT, FALSE);
	PERFORM set_config('test.detail_id', v_detail_id::TEXT, FALSE);

	SELECT status_id INTO v_pending_status
	FROM rrhh_module.paysheet_status
	WHERE status_description = 'Pending';
	
	SELECT status_id INTO v_completed_status
	FROM rrhh_module.paysheet_status
	WHERE status_description = 'Completed';

	IF v_pending_status IS NULL OR v_completed_status IS NULL THEN
		RAISE EXCEPTION 'Alguno de los estados no fue encontrado';
	END IF;

	-- Empleado de prueba
	INSERT INTO core.users(email, password_hash, role_id)
	VALUES ('employee.test@gmail.com', '948y3948yr98438r', 2)
	RETURNING user_id INTO v_user_id;

	v_employee_id := rrhh_module.create_new_employee(
		p_start_date => '2025-01-01',
		p_end_date => '2026-01-01',
		p_hours => 40,
		p_base_salary => 2000.00,
		p_duties => 'Full Flow Test',
        p_user_id => v_user_id,
		p_first_name => 'Flow',
		p_last_name => 'Test', 
        p_doc_number => 'FLW_TST_01',
		p_phone => '55554444',
		p_email => 'flow.test@test.com',
		p_schedule_id => v_schedule_id
	);
	--Nomina de prueba y detalle para el empleado
	INSERT INTO rrhh_module.paysheet (paysheet_id, branch_id, period_start_date, period_end_date, payment_day, payment_amount, paysheet_status_id)
	VALUES (v_paysheet_id, v_branch_id, '2025-12-01', '2025-12-31', '2025-12-31'::DATE, 0.00, v_pending_status);
	
	INSERT INTO rrhh_module.paysheet_detail (
        detail_id, 
        paysheet_id, 
        employee_id, 
        payment_method_id, 
        gross_salary, 
        ccss_employee_deduction, 
        ccss_tenant_deduction, 
        income_tax_amount, 
        total_deduction,   
        net_salary,
        pay_date,
        recalc_needed
    )
    VALUES (
        v_detail_id, 
        v_paysheet_id, 
        v_employee_id, 
        2,
        0.00, 
        0.00, 
        0.00, 
        0.00, 
        0.00, 
        0.00,
        '2025-12-31'::DATE,
        TRUE
    );

	INSERT INTO rrhh_module.income_concept(income_id, concept_name, calculation_type, ccss_apply, tax_apply)
	VALUES (1001, 'Salario De prueba 1', 'Fijo', FALSE, FALSE), (1002, 'Salario de Prueba 2', 'Variable', FALSE, FALSE);

	RAISE NOTICE 'Inicializacion Completada.';
END$$;

DO $$
DECLARE
	v_detail_id UUID := current_setting('test.detail_id')::UUID;
	v_gross_salary_expected NUMERIC(10, 2) := 2500.00;
	v_calculated_gross_salary NUMERIC(10, 2);
BEGIN
	RAISE NOTICE '<======> Prueba de calculo y trigger <======>';
	-- Cabe recordar que el motor encargado de todos los calculos estara
	-- en el backend por lo que en estas pruebas no se haran mas que simulaciones
	-- y se asumiran que los datos recibidos ya fueron procesados por el motor de calculo

	-- Ejecucion exitosa del trigger
	RAISE NOTICE 'Insercion de ingreso (%).', v_gross_salary_expected;

	INSERT INTO rrhh_module.income_register (detail_id, concept_id, base_quantity, calculated_amount)
	VALUES(v_detail_id, 1001, 1 ,v_gross_salary_expected);

	SELECT gross_salary INTO v_calculated_gross_salary
	FROM rrhh_module.paysheet_detail
	WHERE detail_id = v_detail_id;

	IF v_calculated_gross_salary = v_gross_salary_expected AND (
		SELECT recalc_needed FROM rrhh_module.paysheet_detail
		WHERE detail_id = v_detail_id
	) = TRUE THEN
		RAISE NOTICE 'Salario bruto actualizado y recalc_needed marcado como TRUE';
	ELSE
		RAISE EXCEPTION 'El trigger no actualizo el salario o recalc_needed';
	END IF;

	-- Prueba con Salario Negativo
	RAISE NOTICE '<=====> Causando falla del trigger de actualizacion y de integridad <=====>';
	-- Hacer que gross salary pase a ser un numero negativo

	BEGIN
		INSERT INTO rrhh_module.income_register (detail_id, concept_id, base_quantity, calculated_amount)
		VALUES (v_detail_id, 2, 1.00,-3000.00);

		RAISE EXCEPTION 'Se permitio la creacion de un salario bruto negativo';
	EXCEPTION
		WHEN SQLSTATE 'P0001' THEN
			RAISE EXCEPTION 'La insercion fue bloqueada por el chequeo de salario bruto. Exito';
		WHEN OTHERS THEN
			RAISE EXCEPTION 'Excepcion inesperada durante la prueba de fallo de trigger: %.', SQLERRM;
	END;
END $$;

DO $$
DECLARE
	v_paysheet_id UUID := current_setting('test.paysheet_id')::UUID;
	v_detail_id UUID := current_setting('test.detail_id')::UUID;
	v_ccss_employee_deduction NUMERIC(10, 2) := 150.00;
	v_ccss_tenant_deduction NUMERIC(10, 3) := 300.00;
	v_net_salary_expected NUMERIC(10, 2) := 2050.00;
BEGIN
	RAISE NOTICE '<=====> Cierre e integridad de nomina <=====>';

	RAISE NOTICE 'Cierre de nomina cuando se necesitan recalculaciones (Error)';
	BEGIN
		PERFORM rrhh_module.update_paysheet_state(v_paysheet_id);

		RAISE EXCEPTION 'Cierre de nomina permitido, revisar funcion.';
	EXCEPTION
		WHEN SQLSTATE 'P0001' THEN
			RAISE NOTICE 'Cierre bloqueado por excepcion de integridad (recalc_needed = TRUE)';
		WHEN OTHERS THEN
			RAISE EXCEPTION 'Excepcion inesperada en cierre fallido: %', SQLERRM;

	END;

	RAISE NOTICE 'Simulacion de Motor de Calculo (Correccion en recalc_needed)';

	UPDATE rrhh_module.paysheet_detail
	SET recalc_needed = FALSE,
		ccss_employee_deduction = v_ccss_employee_deduction,
		ccss_tenant_deduction = v_ccss_tenant_deduction,
		net_salary = v_net_salary_expected
	WHERE detail_id = v_detail_id;

	RAISE NOTICE 'Intentado cierre exitoso';

	PERFORM rrhh_module.update_paysheet_state(v_paysheet_id);

	-- Verificacion de estado
	PERFORM 1 FROM rrhh_module.paysheet
	WHERE paysheet_id = v_paysheet_id AND paysheet_status_id = (
		SELECT status_id FROM rrhh_module.paysheet_status
		WHERE status_description = 'Completed'
	);

	IF NOT FOUND THEN
		RAISE EXCEPTION 'El estado de la nomina no se actualizo a COMPLETED';
	ELSE
		RAISE NOTICE 'Cierre exitoso';
	END IF;

END $$;

DO $$
DECLARE
	v_ccss_employee_deduction NUMERIC(10, 2) := 150.00;
	v_ccss_tenant_deduction NUMERIC(10, 3) := 300.00;
	v_report_total_ccss NUMERIC(10, 2);
	v_expected_total NUMERIC(10, 2);
BEGIN
	RAISE NOTICE '<=====> Reporte para CCSS <=====>';

	v_expected_total := v_ccss_employee_deduction + v_ccss_tenant_deduction;

	--Reporte generado para Diciembre 2025
	SELECT total FROM rrhh_module.generate_monthly_ccss(2025, 12) INTO v_report_total_ccss;

	IF v_report_total_ccss = v_expected_total THEN
		RAISE NOTICE 'Reporte CCSS incluye la nomina. Total Reportado: %', v_report_total_ccss;
	ELSE
		RAISE EXCEPTION 'El reporte ccss fallos en la agregacion. Esperado: %s, Obtenido: %s.',
			v_expected_total, v_report_total_ccss;
	END IF;

	RAISE NOTICE '<=====> Pruebas Unitarias finalizadas <=====>';

END $$;		