-- ============================================================
-- Migration: 034-bimonetary-exchange-rate-ledger
-- Schema: general
-- Date: 2026-09-22
-- Author: Claude (session work)
--
-- Why: readaptacion a Venezuela -- el sistema es bimonetario (USD/VES) y
-- debe tener UNA sola tasa vigente por tenant, no multiples filas
-- compitiendo. Estado previo:
--   * currency traia EUR/GBP/JPY (cero filas de negocio los usaban).
--   * exchange_rate permitia N filas por par y era editable/borrable
--     (service con update/delete) -- ni ledger inmutable ni tasa unica.
--   * UNIQUE(from,to,effective_date) con effective_date DATE impedia mas
--     de un cambio el mismo dia, incompatible con "se agrega un registro
--     cada vez que cambia la tasa".
--
-- Modelo nuevo:
--   * exchange_rate: ledger GLOBAL e inmutable de la tasa base (BCV).
--     Una sola direccion, USD -> VES, forzada por CHECK. effective_at
--     pasa a TIMESTAMP para admitir varios cambios el mismo dia.
--   * tenant_exchange_delta: ledger POR TENANT e inmutable del
--     diferencial que el tenant suma/resta a la tasa base. Default 0.
--     Persiste hasta que se cargue otro delta (0 = restablecer).
--   * tenant_exchange_rate_ledger (vista): une ambos en una linea de
--     tiempo por tenant, mostrando base + delta + tasa efectiva en cada
--     registro -- el ledger que ve el usuario.
--   * get_effective_exchange_rate(tenant): resolvedor unico de la tasa
--     vigente. Toda la aplicacion debe pasar por aqui.
--
-- La tasa efectiva = base + delta. Ej: base 850, delta +20 -> 870.
-- El delta puede ser negativo (cobrar por debajo de la tasa).
-- ============================================================

SET search_path = general_schema;

-- ── 1. Catalogo de monedas: solo VES y USD ──────────────────────────────
-- Se borran solo si ninguna fila de negocio las referencia (verificado en
-- dev y Supabase: cero uso). Si alguna base tuviera datos, el DELETE no
-- borra nada y el CHECK de abajo tampoco falla -- queda para revisar.
DELETE FROM general_schema.currency c
WHERE c.currency_code IN ('EUR', 'GBP', 'JPY')
  AND NOT EXISTS (SELECT 1 FROM pos_schema.sale                        x WHERE x.currency_id = c.currency_id)
  AND NOT EXISTS (SELECT 1 FROM pos_schema.customer_payment            x WHERE x.currency_id = c.currency_id)
  AND NOT EXISTS (SELECT 1 FROM pos_schema.invoice                     x WHERE x.currency_id = c.currency_id)
  AND NOT EXISTS (SELECT 1 FROM pos_schema.sale_collection             x WHERE x.currency_id = c.currency_id)
  AND NOT EXISTS (SELECT 1 FROM pos_schema.credit_debit_note           x WHERE x.currency_id = c.currency_id)
  AND NOT EXISTS (SELECT 1 FROM purchase_schema.purchase_order_payment x WHERE x.currency_id = c.currency_id)
  AND NOT EXISTS (SELECT 1 FROM general_schema.product_cost_history    x WHERE x.currency_id = c.currency_id)
  AND NOT EXISTS (SELECT 1 FROM accounting_schema.expense              x WHERE x.currency_id = c.currency_id)
  AND NOT EXISTS (SELECT 1 FROM general_schema.exchange_rate           x WHERE x.from_currency_id = c.currency_id OR x.to_currency_id = c.currency_id);

-- ── 2. exchange_rate -> ledger global inmutable de la tasa base ─────────
-- effective_date (DATE) -> effective_at (TIMESTAMP): varios cambios por dia.
-- El UNIQUE original impedia mas de un cambio de tasa el mismo dia. El
-- nombre real quedo truncado por el limite de 63 chars de Postgres, se
-- busca por definicion en vez de por nombre para no depender de eso.
DO $$
DECLARE
  _c text;
BEGIN
  SELECT conname INTO _c
  FROM pg_constraint
  WHERE conrelid = 'general_schema.exchange_rate'::regclass
    AND contype = 'u'
  LIMIT 1;

  IF _c IS NOT NULL THEN
    EXECUTE format('ALTER TABLE general_schema.exchange_rate DROP CONSTRAINT %I', _c);
  END IF;
END $$;

ALTER TABLE general_schema.exchange_rate
    ADD COLUMN IF NOT EXISTS effective_at TIMESTAMP;

UPDATE general_schema.exchange_rate
   SET effective_at = COALESCE(effective_at, effective_date::timestamp)
 WHERE effective_at IS NULL;

ALTER TABLE general_schema.exchange_rate
    ALTER COLUMN effective_at SET NOT NULL,
    ALTER COLUMN effective_at SET DEFAULT CURRENT_TIMESTAMP;

-- effective_date queda como columna generada para no romper queries viejas
-- que la seleccionan; deja de ser la clave de unicidad.
ALTER TABLE general_schema.exchange_rate
    ALTER COLUMN effective_date DROP NOT NULL,
    ALTER COLUMN effective_date SET DEFAULT CURRENT_DATE;

-- Una sola direccion posible: USD -> VES. Postgres no admite subqueries en
-- un CHECK, y hardcodear los currency_id es fragil (la secuencia puede
-- diferir entre entornos), asi que se valida por trigger contra el catalogo.
CREATE OR REPLACE FUNCTION general_schema.assert_exchange_rate_usd_ves()
RETURNS TRIGGER AS $$
DECLARE
    _usd INTEGER;
    _ves INTEGER;
BEGIN
    SELECT currency_id INTO _usd FROM general_schema.currency WHERE currency_code = 'USD';
    SELECT currency_id INTO _ves FROM general_schema.currency WHERE currency_code = 'VES';

    IF NEW.from_currency_id IS DISTINCT FROM _usd OR NEW.to_currency_id IS DISTINCT FROM _ves THEN
        RAISE EXCEPTION 'exchange_rate solo admite el par USD -> VES (recibido from=%, to=%)',
            NEW.from_currency_id, NEW.to_currency_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS assert_exchange_rate_usd_ves_trigger ON general_schema.exchange_rate;
CREATE TRIGGER assert_exchange_rate_usd_ves_trigger
BEFORE INSERT OR UPDATE ON general_schema.exchange_rate
FOR EACH ROW EXECUTE FUNCTION general_schema.assert_exchange_rate_usd_ves();

CREATE INDEX IF NOT EXISTS idx_exchange_rate_effective_at
    ON general_schema.exchange_rate(effective_at DESC);

COMMENT ON TABLE general_schema.exchange_rate IS
    'Ledger global e inmutable de la tasa base USD -> VES (BCV). Nunca se edita ni se borra: cada cambio es una fila nueva. La tasa vigente es la de effective_at mas reciente. El diferencial por tenant vive en tenant_exchange_delta; usar get_effective_exchange_rate() para resolver la tasa aplicable.';

-- ── 3. Ledger de diferencial por tenant ─────────────────────────────────
CREATE TABLE IF NOT EXISTS general_schema.tenant_exchange_delta (
    delta_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    -- Monto en VES que se suma (o resta, si es negativo) a la tasa base.
    -- 0 = restablecer, el tenant opera a la tasa base pelada.
    delta         NUMERIC(12,6) NOT NULL DEFAULT 0,
    effective_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source        VARCHAR(50) DEFAULT 'MANUAL',
    created_by    UUID REFERENCES general_schema.users(user_id) ON DELETE SET NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_tenant_exchange_delta_lookup
    ON general_schema.tenant_exchange_delta(tenant_id, effective_at DESC);

COMMENT ON TABLE general_schema.tenant_exchange_delta IS
    'Ledger inmutable del diferencial de tasa por tenant. Cada cambio es una fila nueva; la vigente es la de effective_at mas reciente. Sin filas = delta 0.';

-- ── 4. Resolvedor unico de la tasa vigente ──────────────────────────────
CREATE OR REPLACE FUNCTION general_schema.get_effective_exchange_rate(_tenant_id UUID)
RETURNS TABLE (
    base_rate      NUMERIC(12,6),
    delta          NUMERIC(12,6),
    effective_rate NUMERIC(12,6),
    base_at        TIMESTAMP,
    delta_at       TIMESTAMP
) AS $$
    WITH base AS (
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
    )
    SELECT
        base.base_rate,
        COALESCE(d.delta, 0)::NUMERIC(12,6),
        (base.base_rate + COALESCE(d.delta, 0))::NUMERIC(12,6),
        base.base_at,
        d.delta_at
    FROM base LEFT JOIN d ON TRUE;
$$ LANGUAGE sql STABLE;

COMMENT ON FUNCTION general_schema.get_effective_exchange_rate(UUID) IS
    'Tasa vigente aplicable a un tenant: base global + su diferencial. Fuente unica de verdad para toda la aplicacion.';

-- ── 5. Vista del ledger combinado por tenant ────────────────────────────
-- Cada evento (cambio de base o de delta) es una fila, mostrando los tres
-- valores vigentes en ese momento. Postgres no soporta IGNORE NULLS en
-- window functions, se usa el patron gaps-and-islands para arrastrar el
-- ultimo valor conocido de cada serie.
CREATE OR REPLACE VIEW general_schema.tenant_exchange_rate_ledger AS
WITH eventos AS (
    SELECT
        t.tenant_id,
        er.effective_at,
        er.created_at,
        'base'::text          AS change_kind,
        er.rate               AS base_rate,
        NULL::numeric         AS delta,
        er.source
    FROM general_schema.exchange_rate er
    CROSS JOIN general_schema.tenant t
    UNION ALL
    SELECT
        ted.tenant_id,
        ted.effective_at,
        ted.created_at,
        'delta'::text,
        NULL::numeric,
        ted.delta,
        ted.source
    FROM general_schema.tenant_exchange_delta ted
),
islas AS (
    SELECT
        e.*,
        count(e.base_rate) OVER (PARTITION BY e.tenant_id ORDER BY e.effective_at, e.created_at) AS grp_base,
        count(e.delta)     OVER (PARTITION BY e.tenant_id ORDER BY e.effective_at, e.created_at) AS grp_delta
    FROM eventos e
),
arrastrado AS (
    SELECT
        i.tenant_id,
        i.effective_at,
        i.created_at,
        i.change_kind,
        i.source,
        max(i.base_rate) OVER (PARTITION BY i.tenant_id, i.grp_base)  AS base_rate,
        max(i.delta)     OVER (PARTITION BY i.tenant_id, i.grp_delta) AS delta
    FROM islas i
)
SELECT
    a.tenant_id,
    a.effective_at,
    a.change_kind,
    a.source,
    a.base_rate,
    COALESCE(a.delta, 0)                          AS delta,
    (a.base_rate + COALESCE(a.delta, 0))          AS effective_rate,
    a.created_at
FROM arrastrado a
WHERE a.base_rate IS NOT NULL
ORDER BY a.tenant_id, a.effective_at DESC, a.created_at DESC;

COMMENT ON VIEW general_schema.tenant_exchange_rate_ledger IS
    'Historial completo de la tasa por tenant: cada cambio de tasa base o de diferencial, con base/delta/efectiva vigentes en ese momento.';

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- DROP VIEW IF EXISTS general_schema.tenant_exchange_rate_ledger;
-- DROP FUNCTION IF EXISTS general_schema.get_effective_exchange_rate(UUID);
-- DROP TABLE IF EXISTS general_schema.tenant_exchange_delta;
-- ALTER TABLE general_schema.exchange_rate DROP CONSTRAINT IF EXISTS chk_exchange_rate_usd_to_ves;
-- DROP INDEX IF EXISTS general_schema.idx_exchange_rate_effective_at;
-- ALTER TABLE general_schema.exchange_rate DROP COLUMN IF EXISTS effective_at;
-- ALTER TABLE general_schema.exchange_rate ALTER COLUMN effective_date SET NOT NULL;
-- ALTER TABLE general_schema.exchange_rate ADD CONSTRAINT exchange_rate_from_currency_id_to_currency_id_effective_date_key UNIQUE (from_currency_id, to_currency_id, effective_date);
-- INSERT INTO general_schema.currency(currency_code, currency_name, symbol) VALUES ('EUR','Euro','€'),('GBP','British Pound','£'),('JPY','Japanese Yen','¥') ON CONFLICT DO NOTHING;
