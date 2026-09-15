-- ============================================================
-- Conceptos de Nomina Predeterminados (Venezuela, LOTTT)
-- ============================================================
-- Este seed NO inserta directamente en payroll_concept
-- (esa tabla es por tenant). Popula la plantilla
-- payroll_concept_template que la funcion
-- provision_tenant_payroll_concepts() copia por tenant.
--
-- Convencion de valores:
--   - percentage: fraccion del salario base (0.30 = 30%)
--   - formula:    parametro del codigo de calculo (ver mas abajo)
--   - fixed:      monto en bolivares
--   - manual:     se ingresa al procesar (base_value = 0)
--
-- salary_basis (regla de oro del calculo venezolano):
--   - normal   (Art. 104) -> recargos, feriados, vacaciones, bono
--                            vacacional. Conceptos del dia a dia.
--   - integral (Art. 122) -> prestaciones e indemnizaciones.
--   NUNCA intercambiables. Usar la base equivocada es el error de
--   calculo mas frecuente.
--
-- Codigos de formula soportados por la PLANILLA MENSUAL
-- (hr_schema strategy.context / payroll.service.ts):
--   bn   -> Bono nocturno   (horas ponderadas desde overtime_record)  Art. 117
--   he   -> Horas extra     (horas ponderadas desde overtime_record)  Art. 118
--   fer  -> Feriado trabajado (horas ponderadas desde overtime_record) Art. 120
--
-- Los siguientes codigos de formula existen en el template pero se
-- siembran is_active = FALSE porque NO se calculan por planilla
-- mensual, sino por su modulo dedicado (ver seccion correspondiente
-- mas abajo): vac, bvac (vacations.service.ts), util, bfa
-- (profit-sharing.service.ts), ant (severance-advance.service.ts).
-- ============================================================

SET SEARCH_PATH TO hr_schema;

-- Limpiar plantilla para re-seed limpio.
-- Elimina los conceptos de Costa Rica (CCSS-EMP, irs, hol, vac CR).
TRUNCATE hr_schema.payroll_concept_template RESTART IDENTITY;

INSERT INTO hr_schema.payroll_concept_template
  (name, type, calculation_method, is_taxable, base_value, code, article, salary_basis, is_active)
VALUES
  -- -------------------------------------------------------
  -- INGRESOS (earning)
  -- -------------------------------------------------------
  -- Recargos de jornada. Base: salario normal (Art. 104).
  ('Bono nocturno',            'earning',   'formula',    TRUE,  0.30, 'bn',   '117',   'normal', TRUE),
  ('Horas extra',              'earning',   'formula',    TRUE,  0.50, 'he',   '118',   'normal', TRUE),
  ('Feriado trabajado',        'earning',   'formula',    TRUE,  0.50, 'fer',  '120',   'normal', TRUE),

  -- -------------------------------------------------------
  -- BENEFICIOS ANUALES - NO SE PROCESAN EN LA PLANILLA MENSUAL
  -- -------------------------------------------------------
  -- Se siembran INACTIVAS (is_active = FALSE). No son conceptos de
  -- formula mensual: vacaciones/bono vacacional se causan y disfrutan
  -- via hr_schema.vacation_period (vacations.service.ts), utilidades y
  -- bonificacion de fin de anio via hr_schema.profit_sharing_period
  -- (profit-sharing.service.ts), y el anticipo de prestaciones via
  -- hr_schema.severance_advance (severance-advance.service.ts). Esos
  -- modulos ya calculan correctamente por Arts. 190/192/131/132/144;
  -- activarlas aqui hace que el motor de planilla mensual intente
  -- recalcularlas con una formula generica y de codigo desconocido.
  ('Vacaciones',               'earning',   'formula',    TRUE,  15,   'vac',  '190',   'normal', FALSE),
  ('Bono vacacional',          'earning',   'formula',    TRUE,  15,   'bvac', '192',   'normal', FALSE),
  ('Utilidades',               'earning',   'formula',    TRUE,  30,   'util', '131',   'normal', FALSE),
  ('Bonificacion fin de ano',  'earning',   'formula',    TRUE,  30,   'bfa',  '132',   'normal', FALSE),

  -- Percepciones variables.
  ('Comisiones',               'earning',   'manual',     TRUE,  0,    'COM',  '104',   'normal', TRUE),
  ('Bonificacion',             'earning',   'fixed',      TRUE,  0,    'BON',  '104',   'normal', TRUE),

  -- -------------------------------------------------------
  -- DEDUCCIONES (deduction)
  -- -------------------------------------------------------
  -- Anticipo sobre la garantia de prestaciones (Art. 144): se gestiona
  -- via hr_schema.severance_advance, no como formula de planilla mensual.
  ('Anticipo de prestaciones', 'deduction', 'formula',    FALSE, 0,    'ant',  '144',   'integral', FALSE),

  -- Cuota sindical: requiere autorizacion expresa (Arts. 412, 413).
  ('Cuota sindical',           'deduction', 'manual',     FALSE, 0,    'SIND', '412',   'normal', TRUE),

  -- -------------------------------------------------------
  -- RETENCIONES LEGALES - DEFINIDAS PERO NO LIBERADAS
  -- -------------------------------------------------------
  -- Se siembran INACTIVAS (is_active = FALSE) y con base_value = 0.
  -- Motivo: la especificacion tecnico-legal que sustenta esta
  -- migracion (MBP_Nomina_LOTTT_Venezuela.md) cubre prestaciones,
  -- beneficios, jornada y mora, pero NO define las retenciones
  -- mensuales venezolanas: ni sus porcentajes, ni sus bases de
  -- calculo, ni sus topes en unidades tributarias.
  --
  -- Quedan registradas para que el hueco sea visible y trazable, no
  -- para que se calculen. Activarlas con valores inventados produce
  -- retenciones incorrectas y contingencia frente al SENIAT, el
  -- IVSS y el BANAVIH.
  --
  -- ANTES DE ACTIVARLAS hace falta una especificacion propia que
  -- defina, para cada una: base de calculo, porcentaje vigente,
  -- tope, periodicidad y quien retiene.
  ('IVSS',                     'deduction', 'percentage', FALSE, 0,    'IVSS', 'PEND',  'normal', FALSE),
  ('Paro Forzoso',             'deduction', 'percentage', FALSE, 0,    'RPE',  'PEND',  'normal', FALSE),
  ('FAOV',                     'deduction', 'percentage', FALSE, 0,    'FAOV', 'PEND',  'normal', FALSE),
  ('INCES',                    'deduction', 'percentage', FALSE, 0,    'INCE', 'PEND',  'normal', FALSE),
  ('ISLR',                     'deduction', 'formula',    FALSE, 0,    'islr', 'PEND',  'normal', FALSE);

-- ============================================================
-- ADVERTENCIA OPERATIVA
-- Con las retenciones inactivas, la corrida de nomina mensual
-- produce un salario neto SIN deducciones legales. Es correcto para
-- desarrollo y para los calculos de prestaciones, vacaciones y
-- utilidades, pero NO es liberable a produccion.
-- ============================================================
