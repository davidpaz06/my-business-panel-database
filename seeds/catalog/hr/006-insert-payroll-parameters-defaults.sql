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

-- La lista canonica de pisos legales vive en un solo lugar:
-- hr_schema.provision_tenant_payroll_parameters() (functions/hr).
-- El backend invoca ese mismo procedimiento al crear un tenant nuevo,
-- para que la provision no dependa de haber corrido este seed.
DO $$
DECLARE
	_tenant RECORD;
BEGIN
	FOR _tenant IN SELECT tenant_id FROM general_schema.tenant LOOP
		PERFORM hr_schema.provision_tenant_payroll_parameters(_tenant.tenant_id);
	END LOOP;
END $$;

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
