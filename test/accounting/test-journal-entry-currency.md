# Test: moneda del libro contable y provision del plan de cuentas

Migracion: `migrations/accounting/045-journal-entry-currency.sql` (FNZ-X-04).
Seed: `seeds/catalog/accounting/004` (cuentas `5-9` y `5-9-001`).

Verifica que:

1. `provision_tenant_accounts` copia la plantilla completa al tenant, incluida la cuenta de respaldo `5-9-001 Otros Gastos Operativos`, y es idempotente.
2. `journal_entry` guarda la moneda del documento y la tasa usada, y rechaza tasas no positivas.

Idempotente: corre en una transaccion con `ROLLBACK`.

## Script

```sql
BEGIN;
CREATE TEMP TABLE t AS SELECT tenant_id FROM general_schema.tenant LIMIT 1;
DELETE FROM accounting_schema.chart_of_accounts WHERE tenant_id = (SELECT tenant_id FROM t)
  AND NOT EXISTS (SELECT 1 FROM accounting_schema.journal_entry je WHERE je.tenant_id = (SELECT tenant_id FROM t));

SELECT accounting_schema.provision_tenant_accounts(tenant_id) > 0 AS provisiona FROM t;
SELECT accounting_schema.provision_tenant_accounts(tenant_id) = 0 AS idempotente FROM t;
-- En una sentencia aparte: un SELECT no ve filas insertadas por una funcion
-- llamada en la misma sentencia.
SELECT EXISTS (SELECT 1 FROM accounting_schema.chart_of_accounts c
               WHERE c.tenant_id = t.tenant_id AND c.account_code = '5-9-001'
                 AND c.allows_transactions) AS tiene_otros_gastos
FROM t;

INSERT INTO accounting_schema.journal_entry (tenant_id, source_type_id, description, currency_id, exchange_rate)
SELECT tenant_id, (SELECT source_type_id FROM accounting_schema.source_type WHERE source_name = 'MANUAL'),
       'test moneda', 2, 853.4993
FROM t;
SELECT currency_id = 2 AND exchange_rate = 853.4993 AS guarda_moneda_y_tasa
FROM accounting_schema.journal_entry WHERE description = 'test moneda';

SAVEPOINT s;
INSERT INTO accounting_schema.journal_entry (tenant_id, source_type_id, description, exchange_rate)
SELECT tenant_id, (SELECT source_type_id FROM accounting_schema.source_type WHERE source_name = 'MANUAL'), 'tasa invalida', 0
FROM t;  -- debe fallar: chk_journal_entry_exchange_rate_positive
ROLLBACK TO SAVEPOINT s;
ROLLBACK;
```

## Resultado esperado

`provisiona`, `idempotente`, `tiene_otros_gastos` y `guarda_moneda_y_tasa` en `t`; el insert con tasa 0 falla por `chk_journal_entry_exchange_rate_positive`.

El flujo completo de asientos (venta con cobro mixto, costo en USD convertido a VES, cobro de CxC, gasto con cuenta de respaldo, asiento secundario en savepoint) se verifico desde el backend contra la DB local el 2026-10-15.
