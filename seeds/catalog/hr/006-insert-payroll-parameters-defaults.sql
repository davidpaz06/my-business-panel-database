-- ============================================================
-- Parametros de Nomina - Pisos Legales (Venezuela, LOTTT)
-- ============================================================
-- Siembra los MINIMOS LEGALES de hr_schema.payroll_parameters para
-- todos los tenants existentes.
--
-- La LOTTT es de orden publico e irrenunciable (Arts. 2, 19). Una
-- convencion colectiva solo puede MEJORAR el minimo legal, nunca
-- reducirlo (Arts. 18.2, 434). Estos valores son por tanto el PISO:
-- el sistema debe aceptar valores superiores por tenant y rechazar
-- valores inferiores.
--
-- Convencion: los porcentajes se almacenan como fraccion
-- (0.30 = 30%); los dias como entero expresado en NUMERIC.
--
-- valid_from se fija en la fecha de vigencia de la LOTTT
-- (7 de mayo de 2012, Gaceta Oficial N 6.076 Extraordinario) para
-- que cualquier calculo historico posterior resuelva el parametro.
-- ============================================================

SET SEARCH_PATH TO hr_schema;

INSERT INTO hr_schema.payroll_parameters (tenant_id, param_key, param_value, valid_from, source)
SELECT
	t.tenant_id,
	p.param_key,
	p.param_value,
	DATE '2012-05-07',
	'Piso legal LOTTT'
FROM general_schema.tenant t
CROSS JOIN (
	VALUES
		-- Dias de utilidades (Art. 131): minimo 30, tope 120.
		('dias_utilidades',                    30.000000),

		-- Bono vacacional (Art. 192): 15 dias mas 1 por anio, tope 30.
		('dias_bono_vacacional_base',          15.000000),

		-- Vacaciones (Art. 190): 15 dias habiles mas 1 por anio,
		-- tope de 15 adicionales (maximo 30).
		('dias_vacaciones_base',               15.000000),

		-- Recargo nocturno (Art. 117): 30% sobre el salario diurno.
		('recargo_nocturno',                    0.300000),

		-- Recargo de hora extraordinaria (Art. 118): 50%.
		-- Sin permiso de la Inspectoria del Trabajo se duplica
		-- (Art. 182): el factor 2.0 lo aplica el servicio, no este
		-- parametro.
		('recargo_hora_extra',                  0.500000),

		-- Recargo por feriado o dia de descanso trabajado (Art. 120):
		-- el dia mas la labor con recargo del 50%.
		('recargo_feriado',                     0.500000),

		-- Participacion en beneficios (Art. 131): al menos el 15% de
		-- los beneficios liquidos del ejercicio.
		('porcentaje_prestaciones_utilidades',  0.150000),

		-- Garantia de prestaciones (Art. 142.a): 15 dias por trimestre.
		('dias_garantia_trimestral',           15.000000),

		-- Dias adicionales por antiguedad (Art. 142.b): 2 por anio
		-- despues del primer anio, tope 30.
		('dias_adicionales_por_anio',           2.000000),
		('tope_dias_adicionales',              30.000000),

		-- Retroactivo (Art. 142.c): 30 dias por anio de servicio.
		('dias_retroactivo_por_anio',          30.000000),

		-- Antiguedad menor a 3 meses (Art. 142.e): 5 dias de salario
		-- por mes trabajado o fraccion.
		('dias_por_mes_antiguedad_corta',       5.000000),

		-- Anticipo de prestaciones (Art. 144): hasta el 75% de lo
		-- depositado como garantia.
		('tope_anticipo_prestaciones',          0.750000),

		-- Descuentos (Art. 154): hasta 1/3 del periodo durante la
		-- relacion; hasta 50% del credito a favor en la liquidacion.
		('tope_descuento_periodo',              0.333333),
		('tope_compensacion_liquidacion',       0.500000),

		-- Plazo de pago de prestaciones (Art. 142.f): 5 dias
		-- siguientes a la terminacion. Pasado ese plazo corren
		-- intereses de mora.
		('dias_gracia_pago_prestaciones',       5.000000),

		-- Topes de horas extraordinarias (Art. 178).
		('tope_horas_dia',                     10.000000),
		('tope_horas_extra_semana',            10.000000),
		('tope_horas_extra_anio',             100.000000),

		-- Base del anio comercial para el prorrateo de alicuotas
		-- del salario integral (Art. 122).
		('dias_anio_comercial',               360.000000),

		-- Divisor del salario diario (Art. 113): salario mensual / 30.
		('divisor_salario_diario',             30.000000)
) AS p(param_key, param_value)
ON CONFLICT (tenant_id, param_key, valid_from) DO NOTHING;

-- ============================================================
-- PARAMETROS SIN VALOR POR DEFECTO - CARGA OBLIGATORIA
-- ============================================================
-- Los siguientes NO se siembran porque no tienen un piso legal
-- estable: dependen de un acto externo y cambian en el tiempo.
-- Deben cargarse por tenant ANTES de la primera corrida.
--
--   salario_minimo_nacional (Art. 129)
--     Lo fija el Ejecutivo por decreto. Sin el no se puede validar
--     que un salario respete el minimo ni calcular la diferencia y
--     los intereses del Art. 130.
--
--   tasa_activa_bcv (Arts. 128, 142.f, 143)
--     La determina el BCV tomando como referencia los seis
--     principales bancos del pais. Se usa para: penalizar
--     trimestres sin deposito (Art. 143), la mora del pago final
--     (Art. 142.f) y la mora del salario ordinario (Art. 128).
--     El calculo debe usar la tasa VIGENTE EN CADA TRAMO temporal
--     de la mora, no una tasa fija, por lo que requiere carga
--     periodica con su vigencia.
--
--   tasa_promedio_activa_pasiva_bcv (Art. 143)
--     Aplica cuando la garantia esta acreditada en la contabilidad
--     de la entidad con autorizacion escrita del trabajador.
--
-- Ejemplo de carga:
--   INSERT INTO hr_schema.payroll_parameters
--     (tenant_id, param_key, param_value, valid_from, source)
--   VALUES
--     ('<tenant_id>', 'tasa_activa_bcv', 0.585000, '2026-08-01',
--      'Aviso BCV agosto 2026');
-- ============================================================
