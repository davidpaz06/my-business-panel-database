-- ============================================================
-- Migracion: 005-payroll-concept-template
-- Contexto: Modulo de Nomina (HR). Agrega la tabla plantilla de
--   conceptos de nomina predeterminados (Costa Rica). La tabla NO
--   esta scoped por tenant; la funcion
--   hr_schema.provision_tenant_payroll_concepts() la copia a
--   payroll_concept por tenant durante el onboarding o bajo demanda.
-- Por que: cada tenant arrancaba con payroll_concept vacio, sin las
--   deducciones legales (CCSS, Renta) ni los conceptos base.
-- Autor/Fecha: 2026-06-18
-- DDL ONLY. Los datos de la plantilla viven en
--   seeds/catalog/hr/004-insert-default-payroll-concepts.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS hr_schema.payroll_concept_template(
	template_id SERIAL PRIMARY KEY NOT NULL,
	name VARCHAR(100) NOT NULL,
	type VARCHAR(20) NOT NULL, -- 'earning' o 'deduction'
	calculation_method VARCHAR(30) NOT NULL, -- 'fixed', 'percentage', 'formula', 'manual'
	is_taxable BOOLEAN DEFAULT TRUE,
	base_value NUMERIC(19, 4) DEFAULT 0,
	code VARCHAR(10) NOT NULL UNIQUE
);

COMMENT ON TABLE hr_schema.payroll_concept_template IS
	'Plantilla de conceptos de nomina (Costa Rica). Copiada a payroll_concept por tenant via provision_tenant_payroll_concepts(). Los valores percentage se almacenan como fraccion (ej. 0.1067 = 10.67%).';

-- ============================================================
-- ROLLBACK (documentacion; no se ejecuta automaticamente)
-- ============================================================
-- DROP FUNCTION IF EXISTS hr_schema.provision_tenant_payroll_concepts(UUID);
-- DROP TABLE IF EXISTS hr_schema.payroll_concept_template;
