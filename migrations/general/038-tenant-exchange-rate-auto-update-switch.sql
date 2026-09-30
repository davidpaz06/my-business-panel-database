-- ============================================================
-- Migration: 038-tenant-exchange-rate-auto-update-switch
-- Schema: general
-- Date: 2026-09-30
-- Author: Claude (session work)
--
-- Why: feedback del cliente -- poder fijar la tasa de forma 100% manual
-- para evitar errores. La tasa base (BCV) es un ledger GLOBAL que el job
-- BcvRateSyncService alimenta; el job no sabe de tenants. El switch por
-- tenant decide que tasa consume cada uno:
--   * auto_update = TRUE  (default, sin fila): tasa efectiva = base BCV +
--     diferencial. El tenant sigue al job.
--   * auto_update = FALSE: tasa efectiva = ultima tasa manual del tenant.
--     Ignora la base (y por tanto al job) y el diferencial.
--
-- Cambios:
--   * tenant_exchange_config: una fila por tenant que ya toco el switch.
--     Sin fila = automatico, asi ningun tenant existente cambia de
--     comportamiento.
--   * tenant_manual_rate: ledger inmutable de tasas manuales por tenant.
--   * get_effective_exchange_rate(): ramifica por auto_update y devuelve
--     tres columnas nuevas (auto_update, manual_rate, manual_at). Cambia la
--     firma de retorno, por eso se hace DROP + CREATE.
-- ============================================================

SET search_path = general_schema;

CREATE TABLE IF NOT EXISTS general_schema.tenant_exchange_config (
    tenant_id    UUID PRIMARY KEY REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    auto_update  BOOLEAN NOT NULL DEFAULT TRUE,
    updated_by   UUID REFERENCES general_schema.users(user_id) ON DELETE SET NULL,
    updated_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE general_schema.tenant_exchange_config IS
    'Switch de actualizacion automatica de tasa por tenant. Sin fila = automatico (sigue la tasa base BCV + diferencial). auto_update = FALSE = el tenant usa su ultima tasa manual de tenant_manual_rate.';

CREATE TABLE IF NOT EXISTS general_schema.tenant_manual_rate (
    manual_rate_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id      UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    rate           NUMERIC(12,6) NOT NULL CHECK (rate > 0),
    effective_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by     UUID REFERENCES general_schema.users(user_id) ON DELETE SET NULL,
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_tenant_manual_rate_lookup
    ON general_schema.tenant_manual_rate(tenant_id, effective_at DESC);

COMMENT ON TABLE general_schema.tenant_manual_rate IS
    'Ledger inmutable de tasas manuales USD -> VES por tenant. La vigente es la de effective_at mas reciente; solo aplica cuando tenant_exchange_config.auto_update = FALSE.';

DROP FUNCTION IF EXISTS general_schema.get_effective_exchange_rate(UUID);

CREATE FUNCTION general_schema.get_effective_exchange_rate(_tenant_id UUID)
RETURNS TABLE (
    base_rate      NUMERIC(12,6),
    delta          NUMERIC(12,6),
    effective_rate NUMERIC(12,6),
    base_at        TIMESTAMP,
    delta_at       TIMESTAMP,
    auto_update    BOOLEAN,
    manual_rate    NUMERIC(12,6),
    manual_at      TIMESTAMP
) AS $$
    WITH cfg AS (
        SELECT COALESCE(
            (SELECT c.auto_update FROM general_schema.tenant_exchange_config c WHERE c.tenant_id = _tenant_id),
            TRUE
        ) AS auto_update
    ),
    base AS (
        SELECT er.rate AS base_rate, er.effective_at AS base_at
        FROM general_schema.exchange_rate er
        ORDER BY er.effective_at DESC, er.created_at DESC
        LIMIT 1
    ),
    d AS (
        SELECT ted.delta, ted.effective_at AS delta_at
        FROM general_schema.tenant_exchange_delta ted
        WHERE ted.tenant_id = _tenant_id
        ORDER BY ted.effective_at DESC, ted.created_at DESC
        LIMIT 1
    ),
    m AS (
        SELECT tmr.rate AS manual_rate, tmr.effective_at AS manual_at
        FROM general_schema.tenant_manual_rate tmr
        WHERE tmr.tenant_id = _tenant_id
        ORDER BY tmr.effective_at DESC, tmr.created_at DESC
        LIMIT 1
    )
    SELECT
        base.base_rate,
        CASE WHEN cfg.auto_update OR m.manual_rate IS NULL
             THEN COALESCE(d.delta, 0) ELSE 0 END::NUMERIC(12,6),
        CASE WHEN cfg.auto_update OR m.manual_rate IS NULL
             THEN base.base_rate + COALESCE(d.delta, 0)
             ELSE m.manual_rate END::NUMERIC(12,6),
        base.base_at,
        d.delta_at,
        cfg.auto_update,
        m.manual_rate,
        m.manual_at
    FROM cfg
    LEFT JOIN base ON TRUE
    LEFT JOIN d ON TRUE
    LEFT JOIN m ON TRUE;
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION general_schema.get_effective_exchange_rate(UUID) IS
    'Tasa vigente aplicable a un tenant. Automatico: base global + diferencial. Manual (auto_update = FALSE): ultima tasa de tenant_manual_rate, sin base ni diferencial. Fuente unica de verdad para toda la aplicacion.';

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- DROP FUNCTION IF EXISTS general_schema.get_effective_exchange_rate(UUID);
-- (recrear la version de la migracion 034, seccion 4)
-- DROP TABLE IF EXISTS general_schema.tenant_manual_rate;
-- DROP TABLE IF EXISTS general_schema.tenant_exchange_config;
