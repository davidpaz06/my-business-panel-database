-- ============================================================
-- Migration: 044-exchange-rate-at-date
-- Schema: general
-- Date: 2026-10-15
-- Author: Claude (session work)
--
-- Why: FNZ-X-02 (my-business-panel-docs/MBP_Auditoria_Finanzas.md). Finanzas
-- convertia todos los montos historicos con la tasa del dia: en una economia
-- con devaluacion, una venta en Bs. de hace 90 dias mostrada en USD (o al
-- reves) quedaba distorsionada. Cada monto debe convertirse con la tasa
-- vigente en la fecha de la transaccion.
--
-- El ledger de tasas ya es historico (exchange_rate, tenant_exchange_delta,
-- tenant_manual_rate tienen effective_at), pero el switch automatico/manual
-- (tenant_exchange_config) es una sola fila por tenant: no se sabe en que
-- modo estaba un tenant en una fecha pasada.
--
-- Cambios:
--   * tenant_exchange_config_history: historial del switch, alimentado por
--     trigger (no lo escribe el backend). Al primer cambio registrado de un
--     tenant se siembra tambien su estado anterior con effective_at =
--     '-infinity', para que las fechas previas resuelvan bien.
--   * get_exchange_rate_at(tenant, instante): tasa USD -> VES vigente para
--     ese tenant en ese instante (mismas reglas que
--     get_effective_exchange_rate, pero mirando solo filas con
--     effective_at <= instante). Antes de la primera tasa base cargada usa
--     la mas antigua disponible.
--   * Indices por effective_at para que la funcion se pueda llamar por fila.
--
-- Convencion de tiempo: los timestamps se guardan en UTC (staging y
-- produccion corren en UTC); el instante que recibe la funcion tambien.
-- ============================================================

SET search_path = general_schema;

CREATE TABLE IF NOT EXISTS general_schema.tenant_exchange_config_history (
    history_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    auto_update   BOOLEAN NOT NULL,
    effective_at  TIMESTAMP NOT NULL,
    changed_by    UUID REFERENCES general_schema.users(user_id) ON DELETE SET NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_tenant_exchange_config_history_lookup
    ON general_schema.tenant_exchange_config_history(tenant_id, effective_at DESC);

COMMENT ON TABLE general_schema.tenant_exchange_config_history IS
    'Historial inmutable del switch automatico/manual de tasa por tenant (lo escribe trg_tenant_exchange_config_history). Lo usa get_exchange_rate_at para saber en que modo estaba el tenant en una fecha pasada.';

CREATE INDEX IF NOT EXISTS idx_exchange_rate_effective_at
    ON general_schema.exchange_rate(effective_at DESC, created_at DESC);

CREATE OR REPLACE FUNCTION general_schema.record_tenant_exchange_config_history()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.auto_update IS NOT DISTINCT FROM OLD.auto_update THEN
        RETURN NEW;
    END IF;

    -- Primer cambio registrado del tenant: sembrar el estado anterior para que
    -- las fechas previas no tomen el modo nuevo. Sin fila previa el tenant era
    -- automatico (default); en un UPDATE el estado anterior es OLD.
    IF NOT EXISTS (
        SELECT 1 FROM general_schema.tenant_exchange_config_history h
        WHERE h.tenant_id = NEW.tenant_id
    ) THEN
        INSERT INTO general_schema.tenant_exchange_config_history
            (tenant_id, auto_update, effective_at, changed_by)
        VALUES (
            NEW.tenant_id,
            CASE WHEN TG_OP = 'UPDATE' THEN OLD.auto_update ELSE TRUE END,
            '-infinity'::timestamp,
            NULL
        );
    END IF;

    INSERT INTO general_schema.tenant_exchange_config_history
        (tenant_id, auto_update, effective_at, changed_by)
    VALUES (NEW.tenant_id, NEW.auto_update, NEW.updated_at, NEW.updated_by);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_tenant_exchange_config_history
    ON general_schema.tenant_exchange_config;
CREATE TRIGGER trg_tenant_exchange_config_history
AFTER INSERT OR UPDATE OF auto_update ON general_schema.tenant_exchange_config
FOR EACH ROW EXECUTE FUNCTION general_schema.record_tenant_exchange_config_history();

-- Tasa USD -> VES vigente para un tenant en un instante (UTC).
-- Modo: ultimo registro del historial <= instante; si el tenant no tiene
-- historial (cambio el switch antes de esta migracion), su modo actual.
-- Automatico: base global + diferencial vigentes en el instante.
-- Manual: ultima tasa manual <= instante; si aun no habia ninguna, base +
-- diferencial (misma regla que get_effective_exchange_rate).
-- Antes de la primera tasa base cargada se usa la mas antigua disponible.
-- NULL solo si no hay ninguna tasa base en el sistema.
CREATE OR REPLACE FUNCTION general_schema.get_exchange_rate_at(
    _tenant_id UUID,
    _at        TIMESTAMP
)
RETURNS NUMERIC(12,6) AS $$
    WITH mode AS (
        SELECT COALESCE(
            (SELECT h.auto_update
             FROM general_schema.tenant_exchange_config_history h
             WHERE h.tenant_id = _tenant_id AND h.effective_at <= _at
             ORDER BY h.effective_at DESC, h.created_at DESC
             LIMIT 1),
            (SELECT c.auto_update
             FROM general_schema.tenant_exchange_config c
             WHERE c.tenant_id = _tenant_id),
            TRUE
        ) AS auto_update
    ),
    base AS (
        SELECT COALESCE(
            (SELECT er.rate FROM general_schema.exchange_rate er
             WHERE er.effective_at <= _at
             ORDER BY er.effective_at DESC, er.created_at DESC
             LIMIT 1),
            (SELECT er.rate FROM general_schema.exchange_rate er
             ORDER BY er.effective_at ASC, er.created_at ASC
             LIMIT 1)
        ) AS rate
    ),
    d AS (
        SELECT COALESCE(
            (SELECT ted.delta FROM general_schema.tenant_exchange_delta ted
             WHERE ted.tenant_id = _tenant_id AND ted.effective_at <= _at
             ORDER BY ted.effective_at DESC, ted.created_at DESC
             LIMIT 1),
            0
        ) AS delta
    ),
    m AS (
        SELECT (SELECT tmr.rate FROM general_schema.tenant_manual_rate tmr
                WHERE tmr.tenant_id = _tenant_id AND tmr.effective_at <= _at
                ORDER BY tmr.effective_at DESC, tmr.created_at DESC
                LIMIT 1) AS rate
    )
    SELECT (CASE
                WHEN mode.auto_update OR m.rate IS NULL THEN base.rate + d.delta
                ELSE m.rate
            END)::NUMERIC(12,6)
    FROM mode, base, d, m;
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION general_schema.get_exchange_rate_at(UUID, TIMESTAMP) IS
    'Tasa USD -> VES vigente para un tenant en un instante UTC, segun el ledger de tasas y el historial del switch automatico/manual. Para convertir montos historicos (Finanzas, FNZ-X-02).';

-- ============================================================
-- Rollback (manual):
-- DROP FUNCTION IF EXISTS general_schema.get_exchange_rate_at(UUID, TIMESTAMP);
-- DROP TRIGGER IF EXISTS trg_tenant_exchange_config_history ON general_schema.tenant_exchange_config;
-- DROP FUNCTION IF EXISTS general_schema.record_tenant_exchange_config_history();
-- DROP INDEX IF EXISTS general_schema.idx_exchange_rate_effective_at;
-- DROP TABLE IF EXISTS general_schema.tenant_exchange_config_history;
-- ============================================================
