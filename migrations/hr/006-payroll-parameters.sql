-- ============================================================
-- Migracion: 006-payroll-parameters
-- Contexto: Migracion de la base normativa laboral de Costa Rica
--   a Venezuela (LOTTT, Gaceta Oficial N 6.076 Ext. 07-05-2012).
--   Crea la tabla de parametros de nomina con vigencia temporal
--   por tenant.
-- Por que: varias magnitudes de la LOTTT cambian por decreto del
--   Ejecutivo (salario minimo), por publicacion del BCV (tasa
--   activa) o por convencion colectiva (dias de utilidades, bono
--   vacacional, recargos). Ninguna puede quedar hardcodeada.
--   La LOTTT es de orden publico e irrenunciable (Arts. 2, 19): una
--   convencion colectiva solo puede MEJORAR el minimo legal, nunca
--   reducirlo (Arts. 18.2, 434). Por eso el valor se guarda por
--   tenant y el piso legal se valida en la capa de aplicacion.
-- Base legal: Arts. 128, 129, 131, 143, 190, 192, 117, 118.
-- Autor/Fecha: 2026-08-27
-- DDL ONLY. Los valores por defecto viven en
--   seeds/catalog/hr/006-insert-payroll-parameters-defaults.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS hr_schema.payroll_parameters (
	parameter_id UUID PRIMARY KEY NOT NULL DEFAULT gen_random_uuid(),
	tenant_id UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
	param_key VARCHAR(60) NOT NULL,
	param_value NUMERIC(18, 6) NOT NULL,
	valid_from DATE NOT NULL,
	valid_to DATE,
	source VARCHAR(120),
	created_at TIMESTAMP NOT NULL DEFAULT NOW(),
	CONSTRAINT uq_payroll_parameter_vigencia UNIQUE (tenant_id, param_key, valid_from),
	CONSTRAINT chk_payroll_parameter_value_positive CHECK (param_value >= 0),
	CONSTRAINT chk_payroll_parameter_vigencia CHECK (valid_to IS NULL OR valid_to >= valid_from)
);

COMMENT ON TABLE hr_schema.payroll_parameters IS
	'Parametros de nomina LOTTT con vigencia temporal por tenant. valid_to NULL = vigente. Resolver siempre a una fecha dada, nunca leer el ultimo registro sin filtrar por vigencia.';

COMMENT ON COLUMN hr_schema.payroll_parameters.param_key IS
	'Clave del parametro: salario_minimo_nacional (Art. 129), tasa_activa_bcv (Arts. 128/143), dias_utilidades (Art. 131), dias_bono_vacacional_base (Art. 192), dias_vacaciones_base (Art. 190), recargo_nocturno (Art. 117), recargo_hora_extra (Art. 118), porcentaje_prestaciones_utilidades (Art. 131).';

COMMENT ON COLUMN hr_schema.payroll_parameters.param_value IS
	'Valor numerico. Los porcentajes se almacenan como fraccion (0.30 = 30%). Los dias se almacenan como entero expresado en NUMERIC.';

COMMENT ON COLUMN hr_schema.payroll_parameters.source IS
	'Origen del valor para auditoria: Decreto N ..., CCT 2025, Aviso BCV ..., Piso legal LOTTT.';

-- Indice de resolucion temporal: la consulta canonica filtra por
-- tenant + clave y ordena por vigencia descendente.
CREATE INDEX IF NOT EXISTS idx_payroll_parameters_lookup
	ON hr_schema.payroll_parameters (tenant_id, param_key, valid_from DESC);

-- ============================================================
-- Consulta canonica de resolucion (referencia para el backend):
--   SELECT param_value FROM hr_schema.payroll_parameters
--   WHERE tenant_id = $1 AND param_key = $2
--     AND valid_from <= $3 AND (valid_to IS NULL OR valid_to >= $3)
--   ORDER BY valid_from DESC LIMIT 1;
-- ============================================================

-- ============================================================
-- ROLLBACK (documentacion; no se ejecuta automaticamente)
-- ============================================================
-- DROP INDEX IF EXISTS hr_schema.idx_payroll_parameters_lookup;
-- DROP TABLE IF EXISTS hr_schema.payroll_parameters;
