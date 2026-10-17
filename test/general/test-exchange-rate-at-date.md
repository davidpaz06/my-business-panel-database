# Test: tasa de cambio en una fecha (get_exchange_rate_at)

Migracion: `migrations/general/044-exchange-rate-at-date.sql` (FNZ-X-02).

Verifica que `general_schema.get_exchange_rate_at(tenant, instante)` reconstruye la tasa vigente en una fecha pasada a partir del ledger (base global, diferencial del tenant, tasa manual) y del historial del switch automatico/manual que alimenta `trg_tenant_exchange_config_history`.

Idempotente: todo corre en una transaccion con `ROLLBACK` y usa fechas sinteticas en 2090, asi no depende de las tasas reales. Supone que el tenant elegido no tiene diferenciales ni tasas manuales con fecha posterior a 2090-01-01.

## Script

```sql
BEGIN;
-- Escenario aislado: tenant de prueba existente + ledger sintetico en el futuro lejano
-- para no depender de las tasas reales.
CREATE TEMP TABLE t AS SELECT tenant_id FROM general_schema.tenant LIMIT 1;
DELETE FROM general_schema.tenant_exchange_config_history WHERE tenant_id = (SELECT tenant_id FROM t);
DELETE FROM general_schema.tenant_exchange_config WHERE tenant_id = (SELECT tenant_id FROM t);
INSERT INTO general_schema.exchange_rate (from_currency_id, to_currency_id, rate, effective_at, source) VALUES
  (2, 1, 100, '2090-01-01 12:00', 'TEST'),
  (2, 1, 200, '2090-02-01 12:00', 'TEST');
INSERT INTO general_schema.tenant_exchange_delta (tenant_id, delta, effective_at, source)
  SELECT tenant_id, 5, '2090-01-15 12:00', 'TEST' FROM t;
INSERT INTO general_schema.tenant_manual_rate (tenant_id, rate, effective_at)
  SELECT tenant_id, 999, '2090-03-01 12:00' FROM t;
-- El tenant pasa a manual el 2090-03-05 (el trigger siembra el estado previo automatico).
INSERT INTO general_schema.tenant_exchange_config (tenant_id, auto_update, updated_at)
  SELECT tenant_id, FALSE, '2090-03-05 12:00' FROM t;

SELECT
  general_schema.get_exchange_rate_at(tenant_id, '2090-01-10') = 100 AS base_sin_delta,
  general_schema.get_exchange_rate_at(tenant_id, '2090-01-20') = 105 AS base_mas_delta,
  general_schema.get_exchange_rate_at(tenant_id, '2090-02-10') = 205 AS nueva_base,
  general_schema.get_exchange_rate_at(tenant_id, '2090-03-02') = 205 AS manual_cargada_pero_modo_auto,
  general_schema.get_exchange_rate_at(tenant_id, '2090-03-06') = 999 AS modo_manual,
  (SELECT count(*) FROM general_schema.tenant_exchange_config_history h WHERE h.tenant_id = t.tenant_id) = 2 AS historial_sembrado
FROM t;

-- Vuelve a automatico: las fechas posteriores usan base + delta otra vez.
UPDATE general_schema.tenant_exchange_config SET auto_update = TRUE, updated_at = '2090-03-10 12:00'
WHERE tenant_id = (SELECT tenant_id FROM t);
SELECT
  general_schema.get_exchange_rate_at(tenant_id, '2090-03-06') = 999 AS sigue_manual_en_su_fecha,
  general_schema.get_exchange_rate_at(tenant_id, '2090-03-11') = 205 AS vuelve_a_auto
FROM t;
ROLLBACK;
```

## Resultado esperado

Todas las columnas en `t`:

| Columna | Que verifica |
| ------- | ------------ |
| base_sin_delta | Antes del primer diferencial: solo la base (100). |
| base_mas_delta | Base + diferencial vigente (100 + 5). |
| nueva_base | Cambio de base mantiene el diferencial (200 + 5). |
| manual_cargada_pero_modo_auto | Una tasa manual cargada no aplica mientras el tenant esta en automatico. |
| modo_manual | Despues del cambio a manual se usa la tasa manual (999). |
| historial_sembrado | El primer cambio siembra el estado previo (automatico, -infinity) + el nuevo. |
| sigue_manual_en_su_fecha | Volver a automatico no reescribe el pasado. |
| vuelve_a_auto | Fechas posteriores vuelven a base + diferencial. |

Ejecutado contra la DB local el 2026-10-15: todas en `t`.
