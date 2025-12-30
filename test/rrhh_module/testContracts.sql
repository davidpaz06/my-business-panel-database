-- ============================================
-- TEST: FLUJO COMPLETO RRHH MODULE (IDEMPOTENTE)
-- ============================================
-- Objetivo: Probar creación de empleado y contrato, y validación de fechas vía trigger.
-- ============================================

-- ========================================
-- SECCIÓN 0: Limpieza inicial (idempotente)
-- ========================================
DO $$
DECLARE
    v_email varchar := 'juan.perez@test.com';
    v_doc_number varchar := '701230456';
    v_employee_id uuid;
    v_contract_id uuid;
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE '🧹 SECCIÓN 0: Limpieza inicial';
    RAISE NOTICE '========================================';

    -- Buscar empleado de prueba
    SELECT employee_id, contract_id INTO v_employee_id, v_contract_id
    FROM rrhh_module.employee
    WHERE email = v_email OR doc_number = v_doc_number
    LIMIT 1;

    -- Eliminar empleado y contrato de prueba si existen
    IF v_employee_id IS NOT NULL THEN
        DELETE FROM rrhh_module.employee WHERE employee_id = v_employee_id;
        RAISE NOTICE '   ✓ Empleado de prueba eliminado: %', v_employee_id;
    END IF;
    IF v_contract_id IS NOT NULL THEN
        DELETE FROM rrhh_module.contract WHERE contract_id = v_contract_id;
        RAISE NOTICE '   ✓ Contrato de prueba eliminado: %', v_contract_id;
    END IF;

    RAISE NOTICE '✅ Limpieza completada';
    RAISE NOTICE '========================================';
END $$;

-- ========================================
-- SECCIÓN 1: Creación de empleado y contrato
-- ========================================
DO $$
DECLARE
    v_employee_id UUID;
    v_user UUID := (SELECT user_id FROM core.users LIMIT 1);
    v_schedule_id INTEGER := 1;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '👤 SECCIÓN 1: Creación de empleado y contrato';
    RAISE NOTICE '========================================';

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
        RAISE NOTICE '   ✓ Empleado creado con id: %', v_employee_id;
    ELSE
        RAISE EXCEPTION 'Error. No se creó el empleado';
    END IF;

    RAISE NOTICE '✅ SECCIÓN 1 COMPLETADA';
    RAISE NOTICE '========================================';
END $$ LANGUAGE plpgsql;

-- ========================================
-- SECCIÓN 2: Validación de trigger de fechas
-- ========================================
DO $$
DECLARE
    v_employee_id UUID;
    v_contract_id UUID;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🛡️ SECCIÓN 2: Validación de trigger de fechas';
    RAISE NOTICE '========================================';

    -- Buscar empleado y contrato recién creados
    SELECT employee_id, contract_id INTO v_employee_id, v_contract_id
    FROM rrhh_module.employee
    WHERE email = 'juan.perez@test.com'
    LIMIT 1;

    IF v_contract_id IS NULL THEN
        RAISE EXCEPTION 'No se encontró contrato para el empleado de prueba';
    END IF;

    RAISE NOTICE '   Forzando falla del trigger (end_date < start_date)';
    BEGIN
        UPDATE rrhh_module.contract
        SET end_date = '2025-09-01'
        WHERE contract_id = v_contract_id;

        RAISE EXCEPTION '❌ Fallo de prueba: Se permitió la actualización inválida del contrato';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLSTATE = 'P0001' THEN
                RAISE NOTICE '   ✅ EXITO. Actualización bloqueada por trigger de validación de fechas';
            ELSE
                RAISE EXCEPTION 'Se lanzó una excepción inesperada: %', SQLERRM;
            END IF;
    END;

    RAISE NOTICE '✅ SECCIÓN 2 COMPLETADA';
    RAISE NOTICE '========================================';
END $$ LANGUAGE plpgsql;

-- ========================================
-- SECCIÓN 3: Resumen final
-- ========================================
DO $$
DECLARE
    v_employee_id UUID;
    v_contract_id UUID;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '📊 SECCIÓN 3: RESUMEN FINAL';
    RAISE NOTICE '========================================';

    SELECT employee_id, contract_id INTO v_employee_id, v_contract_id
    FROM rrhh_module.employee
    WHERE email = 'juan.perez@test.com'
    LIMIT 1;

    RAISE NOTICE '   Empleado de prueba: %', v_employee_id;
    RAISE NOTICE '   Contrato de prueba: %', v_contract_id;

    RAISE NOTICE '';
    RAISE NOTICE '┌────────────────────────────────────────────┐';
    RAISE NOTICE '│  ✅ TEST RRHH FINALIZADO EXITOSAMENTE      │';
    RAISE NOTICE '└────────────────────────────────────────────┘';
    RAISE NOTICE '';
END $$ LANGUAGE plpgsql;