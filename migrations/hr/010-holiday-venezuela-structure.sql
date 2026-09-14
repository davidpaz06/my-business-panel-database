-- ============================================================
-- Migracion: 010-holiday-venezuela-structure
-- Contexto: Migracion normativa Costa Rica -> Venezuela (LOTTT).
--   Reestructura el catalogo de feriados para el Art. 184.
-- Por que: la tabla holiday guardaba una lista plana de fechas
--   absolutas de un unico anio, sin tenant y sin origen. El Art. 184
--   exige tres cosas que esa forma no soporta:
--   1. Distinguir el ORIGEN del feriado, porque el Ejecutivo, los
--      estados y los municipios pueden declarar hasta 3 feriados
--      adicionales POR ANIO. Sin el origen no se puede validar ese
--      tope ni saber que feriados aplican a una sucursal concreta.
--   2. Feriados recurrentes (1 de enero, 1 de mayo, 24/25/31 de
--      diciembre) frente a feriados de fecha movil (carnaval, Jueves
--      y Viernes Santo), que cambian de fecha cada anio.
--   3. Alcance por tenant: un feriado municipal no aplica a todos.
--   Los domingos tambien son dia feriado por el Art. 184, pero se
--   resuelven por calculo de calendario, no como filas sembradas.
-- Base legal: Arts. 120, 184, 188.
-- Autor/Fecha: 2026-08-27
-- DDL ONLY. Los feriados se siembran en
--   seeds/catalog/hr/003-insert-holidays.sql
-- ============================================================

ALTER TABLE hr_schema.holiday
	ADD COLUMN IF NOT EXISTS tenant_id UUID REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
	ADD COLUMN IF NOT EXISTS holiday_year INTEGER,
	ADD COLUMN IF NOT EXISTS is_recurring BOOLEAN NOT NULL DEFAULT FALSE,
	ADD COLUMN IF NOT EXISTS source VARCHAR(20);

COMMENT ON COLUMN hr_schema.holiday.tenant_id IS
	'NULL = feriado nacional, aplica a todos los tenants. Con valor = feriado estadal o municipal que solo aplica a ese tenant.';

COMMENT ON COLUMN hr_schema.holiday.holiday_year IS
	'Anio al que corresponde la fecha. NULL solo para feriados recurrentes de fecha fija. Los de fecha movil (carnaval, Semana Santa) requieren una fila por anio.';

COMMENT ON COLUMN hr_schema.holiday.is_recurring IS
	'TRUE = se repite cada anio en la misma fecha de calendario (1 enero, 1 mayo, 24/25/31 diciembre). FALSE = fecha movil, requiere fila por anio.';

COMMENT ON COLUMN hr_schema.holiday.source IS
	'Origen (Art. 184): ley = feriado de la LOTTT o Ley de Fiestas Nacionales; ejecutivo / estadal / municipal = declarados, limitados a 3 por anio en conjunto.';

COMMENT ON TABLE hr_schema.holiday IS
	'Dias feriados (Art. 184). Los domingos son feriados por ley y se resuelven por calculo de calendario, no se siembran. El trabajo en feriado se paga con el dia mas la labor con recargo del 50% (Art. 120).';

-- Los feriados preexistentes son de Costa Rica; el reseed los reemplaza.
UPDATE hr_schema.holiday
SET source = 'ley'
WHERE source IS NULL;

ALTER TABLE hr_schema.holiday
	ALTER COLUMN source SET NOT NULL,
	ALTER COLUMN source SET DEFAULT 'ley';

DO $$
BEGIN
	IF NOT EXISTS (
		SELECT 1 FROM pg_constraint WHERE conname = 'chk_holiday_source'
	) THEN
		ALTER TABLE hr_schema.holiday
			ADD CONSTRAINT chk_holiday_source
			CHECK (source IN ('ley', 'ejecutivo', 'estadal', 'municipal'));
	END IF;

	-- Un feriado no recurrente debe declarar a que anio pertenece.
	IF NOT EXISTS (
		SELECT 1 FROM pg_constraint WHERE conname = 'chk_holiday_year_requerido'
	) THEN
		ALTER TABLE hr_schema.holiday
			ADD CONSTRAINT chk_holiday_year_requerido
			CHECK (is_recurring = TRUE OR holiday_year IS NOT NULL);
	END IF;
END $$;

-- Resolucion de feriados aplicables a una fecha y tenant.
CREATE INDEX IF NOT EXISTS idx_holiday_lookup
	ON hr_schema.holiday (holiday_year, tenant_id);

CREATE INDEX IF NOT EXISTS idx_holiday_date
	ON hr_schema.holiday (date);

-- ============================================================
-- Tope del Art. 184: hasta 3 feriados declarados por anio entre
-- Ejecutivo, estados y municipios. No se puede expresar como CHECK
-- (requiere agregacion), se valida en la capa de aplicacion:
--   SELECT COUNT(*) FROM hr_schema.holiday
--   WHERE source IN ('ejecutivo','estadal','municipal')
--     AND holiday_year = $1
--     AND (tenant_id = $2 OR tenant_id IS NULL);
--   -- debe ser < 3 antes de insertar
-- ============================================================

-- ============================================================
-- ROLLBACK (documentacion; no se ejecuta automaticamente)
-- ============================================================
-- DROP INDEX IF EXISTS hr_schema.idx_holiday_date;
-- DROP INDEX IF EXISTS hr_schema.idx_holiday_lookup;
-- ALTER TABLE hr_schema.holiday DROP CONSTRAINT IF EXISTS chk_holiday_year_requerido;
-- ALTER TABLE hr_schema.holiday DROP CONSTRAINT IF EXISTS chk_holiday_source;
-- ALTER TABLE hr_schema.holiday DROP COLUMN IF EXISTS source;
-- ALTER TABLE hr_schema.holiday DROP COLUMN IF EXISTS is_recurring;
-- ALTER TABLE hr_schema.holiday DROP COLUMN IF EXISTS holiday_year;
-- ALTER TABLE hr_schema.holiday DROP COLUMN IF EXISTS tenant_id;
