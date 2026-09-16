-- ============================================================
-- Migracion: 019-contract-turn-type-fractional-hours
-- Contexto: QA de HR-VE-01 (jornada, Art. 173 LOTTT) en preproduccion.
-- Por que: contract.turn_type era INTEGER, por lo que un turno con
--   minutos (ej. 09:30-18:00 = 8 horas y 30 minutos) no se podia
--   representar sin truncar. turn_type deja de aceptar entrada libre
--   desde el frontend: el backend ahora lo deriva de turn.entry/out
--   via classifyJourney() al guardar el contrato, por lo que necesita
--   precision fraccionaria igual que weekly_hours (NUMERIC(5,2)).
-- Base legal: Art. 173 (limites de jornada por tipo diurna/nocturna/mixta).
-- Autor/Fecha: 2026-09-16
-- ============================================================

ALTER TABLE hr_schema.contract
	ALTER COLUMN turn_type TYPE NUMERIC(4, 2);

-- Rollback (documentado, no automatico):
-- ALTER TABLE hr_schema.contract ALTER COLUMN turn_type TYPE INTEGER;
-- -- Nota: trunca cualquier fraccion de hora ya guardada (ej. 8.50 -> 8).
