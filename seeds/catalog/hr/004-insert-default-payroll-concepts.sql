-- ============================================================
-- Conceptos de Nomina Predeterminados (Costa Rica)
-- ============================================================
-- Este seed NO inserta directamente en payroll_concept
-- (esa tabla es por tenant). Popula la plantilla
-- payroll_concept_template que la funcion
-- provision_tenant_payroll_concepts() copia por tenant.
--
-- Convencion de valores:
--   - percentage: fraccion del salario base (0.1067 = 10.67%)
--   - formula:    parametro del codigo de calculo (ver mas abajo)
--   - fixed:      monto en colones
--   - manual:     se ingresa al procesar (base_value = 0)
--
-- Codigos de formula soportados (hr_schema strategy.context):
--   he  -> Horas extra (base_value = multiplicador, ej. 1.5)
--   vac -> Vacaciones   (base_value = divisor sobre ingresos de 50 semanas)
--   hol -> Aguinaldo    (base_value = divisor sobre salario anual, 12)
--   irs -> Renta/ISR    (tramos internos, base_value sin uso)
--   sub -> Incapacidad pago      (usa dias/porcentaje, base_value sin uso)
--   inc -> Incapacidad deduccion (usa dias, base_value sin uso)
-- ============================================================

SET SEARCH_PATH TO hr_schema;

-- Limpiar plantilla para re-seed limpio
TRUNCATE hr_schema.payroll_concept_template RESTART IDENTITY;

INSERT INTO hr_schema.payroll_concept_template
  (name, type, calculation_method, is_taxable, base_value, code)
VALUES
  -- -------------------------------------------------------
  -- INGRESOS (earning)
  -- -------------------------------------------------------
  ('Horas extra',          'earning',   'formula',    TRUE,  1.5,    'he'),
  ('Vacaciones',           'earning',   'formula',    TRUE,  25,     'vac'),
  ('Aguinaldo',            'earning',   'formula',    FALSE, 12,     'hol'),
  ('Comisiones',           'earning',   'manual',     TRUE,  0,      'COM'),
  ('Bonificacion',         'earning',   'fixed',      TRUE,  0,      'BON'),
  ('Subsidio incapacidad', 'earning',   'formula',    TRUE,  0,      'sub'),

  -- -------------------------------------------------------
  -- DEDUCCIONES (deduction)
  -- -------------------------------------------------------
  ('CCSS Empleado',        'deduction', 'percentage', FALSE, 0.1067, 'CCSS-EMP'),
  ('Impuesto sobre Renta', 'deduction', 'formula',    FALSE, 0,      'irs'),
  ('Deduccion incapacidad','deduction', 'formula',    FALSE, 0,      'inc');
