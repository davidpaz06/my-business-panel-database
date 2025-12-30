-- ============================================
-- TEST: FLUJO COMPLETO RRHH MODULE - NOMINA (IDEMPOTENTE)
-- ============================================
-- Objetivo: Probar creación de empleado, nómina, ingresos, triggers y cierre de nómina.
-- ============================================

-- ========================================
-- SECCIÓN 0: Limpieza inicial (idempotente)
-- ========================================
DO $$
DECLARE
    v_email varchar := 'flow.test@test.com';
    v_doc_number varchar := 'FLW_TST_01';
    v_user_id uuid;
    v_employee_id uuid;
    v_paysheet_id uuid;
    v_detail_id uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧹 SECCIÓN 0: Limpieza inicial';
    RAISE NOTICE '========================================';

    -- Buscar y eliminar paysheet_detail, paysheet, income_register, income_concept, employee y user de prueba
    SELECT employee_id INTO v_employee_id
    FROM rrhh_module.employee
    WHERE email = v_email OR doc_number = v_doc_number
    LIMIT 1;

    IF v_employee_id IS NOT NULL THEN
        -- Eliminar income_register relacionados
        DELETE FROM rrhh_module.income_register
        WHERE detail_id IN (
            SELECT detail_id FROM rrhh_module.paysheet_detail WHERE employee_id = v_employee_id
        );

        -- Eliminar paysheet_detail relacionados
        DELETE FROM rrhh_module.paysheet_detail WHERE employee_id = v_employee_id;

        -- Eliminar paysheet relacionados
        DELETE FROM rrhh_module.paysheet
        WHERE paysheet_id IN (
            SELECT paysheet_id FROM rrhh_module.paysheet_detail WHERE employee_id = v_employee_id
        );

        -- Eliminar empleado
        DELETE FROM rrhh_module.employee WHERE employee_id = v_employee_id;
        RAISE NOTICE '   ✓ Empleado de prueba eliminado: %', v_employee_id;
    END IF;

    -- Eliminar usuario de prueba
    DELETE FROM core.users WHERE email = v_email;
    RAISE NOTICE '   ✓ Usuario de prueba eliminado: %', v_email;

    -- Eliminar conceptos de ingreso de prueba
    DELETE FROM rrhh_module.income_concept WHERE concept_name IN ('Salario De prueba 1', 'Salario de Prueba 2');
    RAISE NOTICE '   ✓ Conceptos de ingreso de prueba eliminados';

    RAISE NOTICE '✅ Limpieza completada';
    RAISE NOTICE '========================================';
END $$;

-- ========================================
-- SECCIÓN 1: Preparación de datos de prueba
-- ========================================
DO $$
DECLARE
    v_employee_id UUID;
    v_user_id UUID;
    v_branch_id UUID := (SELECT branch_id FROM core.branch LIMIT 1);
    v_schedule_id INTEGER := 1;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '👤 SECCIÓN 1: Creación de usuario, empleado y conceptos';
    RAISE NOTICE '========================================';

    -- Crear usuario de prueba
    INSERT INTO core.users(email, password_hash, role_id)
    VALUES ('flow.test@test.com', '948y3948yr98438r', 2)
    RETURNING user_id INTO v_user_id;

    -- Crear empleado de prueba
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

    -- Crear conceptos de ingreso de prueba
    INSERT INTO rrhh_module.income_concept(income_id, concept_name, calculation_type, ccss_apply, tax_apply)
    VALUES (1001, 'Salario De prueba 1', 'Fijo', FALSE, FALSE)
    ON CONFLICT (income_id) DO NOTHING;
    INSERT INTO rrhh_module.income_concept(income_id, concept_name, calculation_type, ccss_apply, tax_apply)
    VALUES (1002, 'Salario de Prueba 2', 'Variable', FALSE, FALSE)
    ON CONFLICT (income_id) DO NOTHING;

    RAISE NOTICE '   ✓ Usuario y empleado de prueba creados';
    RAISE NOTICE '   ✓ Conceptos de ingreso de prueba creados';

    RAISE NOTICE '✅ SECCIÓN 1 COMPLETADA';
    RAISE NOTICE '========================================';
END $$;

-- ========================================
-- SECCIÓN 2: Creación de nómina y detalle
-- ========================================
DO $$
DECLARE
    v_employee_id UUID := (SELECT employee_id FROM rrhh_module.employee WHERE email = 'flow.test@test.com' LIMIT 1);
    v_paysheet_id UUID := gen_random_uuid();
    v_detail_id UUID := gen_random_uuid();
    v_branch_id UUID := (SELECT branch_id FROM core.branch LIMIT 1);
    v_pending_status INTEGER;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📝 SECCIÓN 2: Creación de nómina y detalle';
    RAISE NOTICE '========================================';

    -- Obtener status 'Pending'
    SELECT status_id INTO v_pending_status
    FROM rrhh_module.paysheet_status 
    WHERE status_description = 'Pending' 
    LIMIT 1;

    IF v_pending_status IS NULL THEN
        RAISE EXCEPTION 'No se encontró el estado Pending en paysheet_status';
    END IF;

    -- Crear nómina de prueba
    INSERT INTO rrhh_module.paysheet (paysheet_id, branch_id, period_start_date, period_end_date, payment_day, payment_amount, paysheet_status_id)
    VALUES (v_paysheet_id, v_branch_id, '2025-12-01', '2025-12-31', '2025-12-31'::DATE, 0.00, v_pending_status);

    -- Crear detalle de nómina
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

    -- Guardar ids en variables de sesión para siguientes secciones
    PERFORM set_config('test.paysheet_id', v_paysheet_id::TEXT, FALSE);
    PERFORM set_config('test.detail_id', v_detail_id::TEXT, FALSE);

    RAISE NOTICE '   ✓ Nómina y detalle creados';
    RAISE NOTICE '✅ SECCIÓN 2 COMPLETADA';
    RAISE NOTICE '========================================';
END $$;

-- ========================================
-- SECCIÓN 3: Prueba de triggers de ingreso y validación
-- ========================================
DO $$
DECLARE
    v_detail_id UUID := current_setting('test.detail_id')::UUID;
    v_gross_salary_expected NUMERIC(10, 2) := 2500.00;
    v_calculated_gross_salary NUMERIC(10, 2);
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '⚡ SECCIÓN 3: Prueba de triggers de ingreso y validación';
    RAISE NOTICE '========================================';

    -- Inserción válida de ingreso
    INSERT INTO rrhh_module.income_register (detail_id, concept_id, base_quantity, calculated_amount)
    VALUES(v_detail_id, 1001, 1 ,v_gross_salary_expected);

    SELECT gross_salary INTO v_calculated_gross_salary
    FROM rrhh_module.paysheet_detail
    WHERE detail_id = v_detail_id;

    IF v_calculated_gross_salary = v_gross_salary_expected AND (
        SELECT recalc_needed FROM rrhh_module.paysheet_detail
        WHERE detail_id = v_detail_id
    ) = TRUE THEN
        RAISE NOTICE '   ✓ Salario bruto actualizado y recalc_needed marcado como TRUE';
    ELSE
        RAISE EXCEPTION 'El trigger no actualizó el salario o recalc_needed';
    END IF;
	
    -- Prueba con salario negativo (debe fallar)
    BEGIN
        INSERT INTO rrhh_module.income_register (detail_id, concept_id, base_quantity, calculated_amount)
        VALUES (v_detail_id, 1002, 1.00, -3000.00);

        RAISE EXCEPTION 'Se permitió la creación de un salario bruto negativo';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            RAISE NOTICE '   ✓ Inserción negativa bloqueada por trigger de integridad';
        WHEN SQLSTATE '23514' THEN
            RAISE NOTICE '   ✓ Inserción negativa bloqueada por restricción CHECK de gross_salary';
        WHEN OTHERS THEN
            RAISE EXCEPTION 'Excepción inesperada durante la prueba de trigger: %.', SQLERRM;
    END;

    RAISE NOTICE '✅ SECCIÓN 3 COMPLETADA';
    RAISE NOTICE '========================================';
END $$;

-- ========================================
-- SECCIÓN 4: Cierre e integridad de nómina
-- ========================================
DO $$
DECLARE
    v_paysheet_id UUID := current_setting('test.paysheet_id')::UUID;
    v_detail_id UUID := current_setting('test.detail_id')::UUID;
    v_ccss_employee_deduction NUMERIC(10, 2) := 150.00;
    v_ccss_tenant_deduction NUMERIC(10, 3) := 300.00;
    v_net_salary_expected NUMERIC(10, 2) := 2050.00;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🔒 SECCIÓN 4: Cierre e integridad de nómina';
    RAISE NOTICE '========================================';

    -- Intentar cerrar nómina con recalc_needed = TRUE (debe fallar)
    BEGIN
        PERFORM rrhh_module.update_paysheet_state(v_paysheet_id);
        RAISE EXCEPTION 'Cierre de nómina permitido, revisar función.';
    EXCEPTION
        WHEN SQLSTATE 'P0001' THEN
            RAISE NOTICE '   ✓ Cierre bloqueado por integridad (recalc_needed = TRUE)';
        WHEN OTHERS THEN
            RAISE EXCEPTION 'Excepción inesperada en cierre fallido: %', SQLERRM;
    END;

    -- Simular motor de cálculo: corregir recalc_needed y deducciones
    UPDATE rrhh_module.paysheet_detail
    SET recalc_needed = FALSE,
        ccss_employee_deduction = v_ccss_employee_deduction,
        ccss_tenant_deduction = v_ccss_tenant_deduction,
        net_salary = v_net_salary_expected
    WHERE detail_id = v_detail_id;

    -- Intentar cierre exitoso
    PERFORM rrhh_module.update_paysheet_state(v_paysheet_id);

    -- Verificar estado
    IF NOT EXISTS (
        SELECT 1 FROM rrhh_module.paysheet
        WHERE paysheet_id = v_paysheet_id AND paysheet_status_id = (
            SELECT status_id FROM rrhh_module.paysheet_status WHERE status_description = 'Completed' LIMIT 1
        )
    ) THEN
        RAISE EXCEPTION 'El estado de la nómina no se actualizó a COMPLETED';
    ELSE
        RAISE NOTICE '   ✓ Cierre exitoso';
    END IF;

    RAISE NOTICE '✅ SECCIÓN 4 COMPLETADA';
    RAISE NOTICE '========================================';
END $$;

-- ========================================
-- SECCIÓN 5: Reporte CCSS y resumen final
-- ========================================
DO $$
DECLARE
    v_ccss_employee_deduction NUMERIC(10, 2) := 150.00;
    v_ccss_tenant_deduction NUMERIC(10, 3) := 300.00;
    v_report_total_ccss NUMERIC(10, 2);
    v_expected_total NUMERIC(10, 2);
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📊 SECCIÓN 5: Reporte CCSS y resumen final';
    RAISE NOTICE '========================================';

    v_expected_total := v_ccss_employee_deduction + v_ccss_tenant_deduction;

    -- Reporte generado para Diciembre 2025
    SELECT total INTO v_report_total_ccss
    FROM rrhh_module.generate_monthly_ccss(2025, 12);

    IF v_report_total_ccss = v_expected_total THEN
        RAISE NOTICE '   ✓ Reporte CCSS incluye la nómina. Total Reportado: %', v_report_total_ccss;
    ELSE
        RAISE EXCEPTION 'El reporte CCSS falló en la agregación. Esperado: %, Obtenido: %.',
            v_expected_total, v_report_total_ccss;
    END IF;

    RAISE NOTICE '';
    RAISE NOTICE '┌────────────────────────────────────────────┐';
    RAISE NOTICE '│  ✅ TEST NOMINA FINALIZADO EXITOSAMENTE    │';
    RAISE NOTICE '└────────────────────────────────────────────┘';
    RAISE NOTICE '';
END $$;