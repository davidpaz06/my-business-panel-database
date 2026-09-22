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
    p_payment_schedule_id INTEGER,
    p_branch_id UUID,
    p_identification_type_id INTEGER DEFAULT 1,
    p_duties_type_id INTEGER DEFAULT NULL
  )
 RETURNS UUID
 LANGUAGE plpgsql
AS $function$

DECLARE
  v_new_contract_id UUID;
  v_new_employee_id UUID;
BEGIN

  IF NOT EXISTS (SELECT 1 FROM hr_schema.payment_schedule WHERE payment_schedule_id = p_payment_schedule_id) THEN
    RAISE EXCEPTION 'Integrity error: payment_schedule_id (payment_schedule_id: %) doesnt exists', p_payment_schedule_id;
  END IF;

  INSERT INTO hr_schema.contract (tenant_id, start_date, end_date, hours, base_salary, duties, turn_type, turn_id, duties_type_id)
  VALUES (p_tenant_id, p_start_date, p_end_date, p_hours, p_base_salary, p_duties, p_turn_type, p_turn_id, p_duties_type_id)
  RETURNING contract_id INTO v_new_contract_id;

  v_new_employee_id := gen_random_uuid();

  -- hire_date toma la fecha de inicio del contrato. Es la base del computo
  -- de antiguedad (Art. 142 LOTTT) y vive en employee porque un trabajador
  -- puede encadenar contratos sin perder antiguedad.
  INSERT INTO hr_schema.employee (
    employee_id, user_id, first_name, last_name, doc_number,
    identification_type_id, phone, email, contract_id,
    payment_schedule_id, tenant_id, branch_id, hire_date
  )
  VALUES (
    v_new_employee_id,
    p_user_id,
    p_first_name,
    p_last_name,
    p_doc_number,
    p_identification_type_id,
    p_phone,
    p_email,
    v_new_contract_id,
    p_payment_schedule_id,
    p_tenant_id,
    p_branch_id,
    p_start_date
  );

  -- Abre el historial salarial (Art. 122): el salario integral necesita
  -- reconstruir la base vigente en cada trimestre.
  INSERT INTO hr_schema.salary_history (
    employee_id, tenant_id, monthly_salary, valid_from, reason
  )
  VALUES (
    v_new_employee_id,
    p_tenant_id,
    p_base_salary,
    p_start_date,
    'Salario inicial del contrato'
  );

  RETURN v_new_employee_id;

EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'Data Error: Document Number (%) or Email already exists.', p_doc_number;
  WHEN foreign_key_violation THEN
    RAISE EXCEPTION 'Integrity Error: Insert failed due to a non-existent FOREIGN KEY (payment_schedule_id, identification_type_id, or duties_type_id).';
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

-- ============================================================
-- generate_monthly_ccss: ELIMINADA en la migracion 009.
-- Era especifica de la Caja Costarricense de Seguro Social y ademas
-- estaba rota: referenciaba las columnas ccss_employee_deduction,
-- ccss_tenant_deduction y paysheet.payment_day, ninguna de las cuales
-- existe en el esquema.
-- Su equivalente venezolano (reporte de retenciones IVSS/INCES/FAOV)
-- requiere una especificacion de calculo que aun no existe.
-- ============================================================

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

DROP TRIGGER IF EXISTS trg_close_suspention_on_write ON hr_schema.suspention;
CREATE TRIGGER trg_close_suspention_on_write
BEFORE INSERT OR UPDATE ON hr_schema.suspention
FOR EACH ROW
EXECUTE FUNCTION hr_schema.close_suspention_trigger();

-- ============================================================
-- provision_tenant_payroll_concepts
-- Copia la plantilla payroll_concept_template a un tenant.
-- Idempotente POR FILA (ON CONFLICT (tenant_id, code) DO NOTHING,
-- migracion hr/030): re-invocarla sobre un tenant ya provisionado es
-- seguro y hace BACKFILL de codigos nuevos agregados a la plantilla
-- despues de su primer provisioning (ej. hr/004: DPAT, ALIM, OTRA).
-- Llamada durante el onboarding del tenant o bajo demanda.
-- ============================================================
CREATE OR REPLACE FUNCTION hr_schema.provision_tenant_payroll_concepts(_tenant_id UUID)
RETURNS INT AS $$
DECLARE
	_inserted INT := 0;
BEGIN
	-- Verificar que el tenant existe
	IF NOT EXISTS (SELECT 1 FROM general_schema.tenant WHERE tenant_id = _tenant_id) THEN
		RAISE EXCEPTION 'Tenant % not found', _tenant_id;
	END IF;

	-- is_active se toma de la plantilla, no se fuerza a TRUE: hay
	-- conceptos definidos pero no liberados (retenciones venezolanas
	-- sin especificacion de calculo) que deben provisionarse inactivos.
	INSERT INTO hr_schema.payroll_concept(
		tenant_id, name, type, calculation_method, is_taxable, is_active, base_value, code,
		article, salary_basis
	)
	SELECT
		_tenant_id, t.name, t.type, t.calculation_method, t.is_taxable, t.is_active, t.base_value, t.code,
		t.article, t.salary_basis
	FROM hr_schema.payroll_concept_template t
	ORDER BY t.template_id
	ON CONFLICT (tenant_id, code) DO NOTHING;

	GET DIAGNOSTICS _inserted = ROW_COUNT;

	IF _inserted = 0 THEN
		RAISE NOTICE 'Tenant % already has all template payroll concepts provisioned', _tenant_id;
	ELSE
		RAISE NOTICE 'Provisioned % payroll concepts for tenant %', _inserted, _tenant_id;
	END IF;

	RETURN _inserted;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- provision_tenant_payroll_parameters
-- Siembra los PISOS LEGALES de la LOTTT (Arts. 117, 118, 120, 131,
-- 142, 144, 154, 178, 190, 192) en hr_schema.payroll_parameters para
-- un tenant. Idempotente (ON CONFLICT DO NOTHING).
--
-- La LOTTT es de orden publico e irrenunciable (Arts. 2, 19): estos
-- valores son el MINIMO. Una convencion colectiva solo puede
-- mejorarlos (Arts. 18.2, 434), nunca reducirlos.
--
-- valid_from se fija en la vigencia de la LOTTT (07-05-2012) para que
-- cualquier calculo historico resuelva el parametro.
--
-- NO se siembran salario_minimo_nacional (Art. 129) ni tasa_activa_bcv
-- (Arts. 128, 142.f, 143): dependen de un decreto del Ejecutivo y de
-- un aviso del BCV, no tienen piso legal estable y deben cargarse por
-- tenant antes de la primera corrida.
--
-- Llamada durante el onboarding del tenant o bajo demanda.
-- ============================================================
CREATE OR REPLACE FUNCTION hr_schema.provision_tenant_payroll_parameters(_tenant_id UUID)
RETURNS INT AS $$
DECLARE
	_inserted INT := 0;
BEGIN
	IF NOT EXISTS (SELECT 1 FROM general_schema.tenant WHERE tenant_id = _tenant_id) THEN
		RAISE EXCEPTION 'Tenant % not found', _tenant_id;
	END IF;

	INSERT INTO hr_schema.payroll_parameters (tenant_id, param_key, param_value, valid_from, source)
	SELECT _tenant_id, p.param_key, p.param_value, DATE '2012-05-07', 'Piso legal LOTTT'
	FROM (
		VALUES
			-- Dias de utilidades (Art. 131): minimo 30, tope 120.
			('dias_utilidades',                    30.000000),
			-- Bono vacacional (Art. 192): 15 dias mas 1 por anio, tope 30.
			('dias_bono_vacacional_base',          15.000000),
			-- Vacaciones (Art. 190): 15 dias habiles mas 1 por anio, tope 30.
			('dias_vacaciones_base',               15.000000),
			-- Recargo nocturno (Art. 117): 30%.
			('recargo_nocturno',                    0.300000),
			-- Recargo de hora extraordinaria (Art. 118): 50%. Sin permiso
			-- de la Inspectoria se duplica (Art. 182), eso lo aplica el servicio.
			('recargo_hora_extra',                  0.500000),
			-- Recargo por feriado o descanso trabajado (Art. 120): 50%.
			('recargo_feriado',                     0.500000),
			-- Participacion en beneficios (Art. 131): 15% de los liquidos.
			('porcentaje_prestaciones_utilidades',  0.150000),
			-- Garantia de prestaciones (Art. 142.a): 15 dias por trimestre.
			('dias_garantia_trimestral',           15.000000),
			-- Dias adicionales por antiguedad (Art. 142.b): 2 por anio, tope 30.
			('dias_adicionales_por_anio',           2.000000),
			('tope_dias_adicionales',              30.000000),
			-- Retroactivo (Art. 142.c): 30 dias por anio.
			('dias_retroactivo_por_anio',          30.000000),
			-- Antiguedad menor a 3 meses (Art. 142.e): 5 dias por mes o fraccion.
			('dias_por_mes_antiguedad_corta',       5.000000),
			-- Anticipo de prestaciones (Art. 144): hasta 75% de la garantia.
			('tope_anticipo_prestaciones',          0.750000),
			-- Descuentos (Art. 154): 1/3 del periodo; 50% del credito al liquidar.
			('tope_descuento_periodo',              0.333333),
			('tope_compensacion_liquidacion',       0.500000),
			-- Plazo de pago de prestaciones (Art. 142.f): 5 dias.
			('dias_gracia_pago_prestaciones',       5.000000),
			-- Topes de horas extraordinarias (Art. 178).
			('tope_horas_dia',                     10.000000),
			('tope_horas_extra_semana',            10.000000),
			('tope_horas_extra_anio',             100.000000),
			-- Anio comercial para las alicuotas del salario integral (Art. 122).
			('dias_anio_comercial',               360.000000),
			-- Divisor del salario diario (Art. 113): salario mensual / 30.
			('divisor_salario_diario',             30.000000)
	) AS p(param_key, param_value)
	ON CONFLICT (tenant_id, param_key, valid_from) DO NOTHING;

	GET DIAGNOSTICS _inserted = ROW_COUNT;

	RAISE NOTICE 'Provisioned % payroll parameters for tenant %', _inserted, _tenant_id;
	RETURN _inserted;
END;
$$ LANGUAGE plpgsql;
