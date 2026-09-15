-- ============================================================
-- Dias feriados (Venezuela, LOTTT Art. 184)
-- ============================================================
-- Son dias feriados, a efectos de la LOTTT:
--   a) Los domingos.
--   b) 1 de enero; lunes y martes de carnaval; Jueves y Viernes
--      Santo; 1 de mayo; 24, 25 y 31 de diciembre.
--   c) Los declarados en la Ley de Fiestas Nacionales.
--   d) Hasta 3 al anio declarados por el Ejecutivo, los estados o
--      los municipios (source distinto de 'ley').
--
-- Los DOMINGOS no se siembran: son feriados por ley y se resuelven
-- por calculo de calendario. Sembrarlos serian 52 filas por anio
-- sin aportar informacion.
--
-- Convencion de la tabla:
--   is_recurring = TRUE  -> misma fecha cada anio (no requiere
--                           holiday_year, se resuelve por mes/dia).
--   is_recurring = FALSE -> fecha movil, requiere una fila por anio
--                           (carnaval y Semana Santa dependen de la
--                           fecha de Pascua).
--   tenant_id NULL       -> feriado nacional, aplica a todos.
--   source               -> 'ley' | 'ejecutivo' | 'estadal' | 'municipal'
--
-- El trabajo en dia feriado se paga con el dia mas la labor con
-- recargo del 50% sobre el salario normal (Art. 120).
-- ============================================================

SET SEARCH_PATH TO hr_schema;

-- Limpieza de los feriados de Costa Rica del esquema anterior.
DELETE FROM hr_schema.holiday WHERE tenant_id IS NULL;

-- ------------------------------------------------------------
-- Feriados recurrentes de fecha fija (Art. 184 literal b)
-- ------------------------------------------------------------
-- La columna date conserva un anio de referencia por compatibilidad
-- con el tipo TIMESTAMP; con is_recurring = TRUE el backend debe
-- resolver por mes y dia, ignorando el anio almacenado.

INSERT INTO hr_schema.holiday (date, holiday_name, is_freeday, is_payable, is_recurring, holiday_year, source)
VALUES
  ('2026-01-01', 'Ano Nuevo',                          TRUE, TRUE, TRUE, NULL, 'ley'),
  ('2026-05-01', 'Dia del Trabajador',                 TRUE, TRUE, TRUE, NULL, 'ley'),
  ('2026-12-24', 'Nochebuena',                         TRUE, TRUE, TRUE, NULL, 'ley'),
  ('2026-12-25', 'Navidad',                            TRUE, TRUE, TRUE, NULL, 'ley'),
  ('2026-12-31', 'Fin de Ano',                         TRUE, TRUE, TRUE, NULL, 'ley')
ON CONFLICT DO NOTHING;

-- ------------------------------------------------------------
-- Ley de Fiestas Nacionales (Art. 184 literal c)
-- ------------------------------------------------------------

INSERT INTO hr_schema.holiday (date, holiday_name, is_freeday, is_payable, is_recurring, holiday_year, source)
VALUES
  ('2026-04-19', 'Declaracion de la Independencia',    TRUE, TRUE, TRUE, NULL, 'ley'),
  ('2026-06-24', 'Batalla de Carabobo',                TRUE, TRUE, TRUE, NULL, 'ley'),
  ('2026-07-05', 'Dia de la Independencia',            TRUE, TRUE, TRUE, NULL, 'ley'),
  ('2026-07-24', 'Natalicio de Simon Bolivar',         TRUE, TRUE, TRUE, NULL, 'ley'),
  ('2026-10-12', 'Dia de la Resistencia Indigena',     TRUE, TRUE, TRUE, NULL, 'ley')
ON CONFLICT DO NOTHING;

-- ------------------------------------------------------------
-- Feriados de fecha movil (Art. 184 literal b)
-- ------------------------------------------------------------
-- Dependen de la fecha de Pascua y cambian cada anio, por lo que
-- requieren una fila por anio con is_recurring = FALSE.
-- Pascua 2026: 5 de abril.

INSERT INTO hr_schema.holiday (date, holiday_name, is_freeday, is_payable, is_recurring, holiday_year, source)
VALUES
  ('2026-02-16', 'Lunes de Carnaval',                  TRUE, TRUE, FALSE, 2026, 'ley'),
  ('2026-02-17', 'Martes de Carnaval',                 TRUE, TRUE, FALSE, 2026, 'ley'),
  ('2026-04-02', 'Jueves Santo',                       TRUE, TRUE, FALSE, 2026, 'ley'),
  ('2026-04-03', 'Viernes Santo',                      TRUE, TRUE, FALSE, 2026, 'ley')
ON CONFLICT DO NOTHING;

-- ============================================================
-- PENDIENTE OPERATIVO
-- Los feriados de fecha movil deben cargarse cada anio. Sin la
-- carga del anio en curso, carnaval y Semana Santa no se pagan con
-- el recargo del Art. 120.
--
-- Los feriados declarados por el Ejecutivo, estados o municipios
-- (source distinto de 'ley') se cargan por tenant y estan limitados
-- a 3 por anio en conjunto (Art. 184 literal d). Esa validacion vive
-- en la capa de aplicacion.
-- ============================================================
