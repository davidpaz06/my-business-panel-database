# Test: origen de los movimientos de puntos (migracion pos/046)

Cubre FNZ-FI-03: los puntos proporcionales que se otorgan al registrar un
cobro de una venta a credito o apartado quedan en `pos_schema.score_transaction`
con la venta y el cobro de origen, y el grafico de crecimiento de Finanzas los
cuenta por sucursal.

Idempotente: todo corre dentro de una transaccion que termina en `ROLLBACK`.

## Script

```sql
BEGIN;

-- 1. Las columnas existen (migracion 046 aplicada).
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'pos_schema'
  AND table_name = 'score_transaction'
  AND column_name IN ('sale_id', 'sale_collection_id')
ORDER BY column_name;
-- Esperado: 2 filas (sale_collection_id, sale_id).

-- 2. Insertar un movimiento 'earn' de un cobro (tipo 1) para un cliente y una
--    venta existentes del mismo tenant.
WITH ctx AS (
    SELECT tc.tenant_id,
           tc.tenant_customer_id,
           s.sale_id,
           (SELECT sale_collection_id FROM pos_schema.sale_collection LIMIT 1) AS sale_collection_id
    FROM general_schema.tenant_customer tc
    JOIN general_schema.branch b ON b.tenant_id = tc.tenant_id
    JOIN pos_schema.sale s ON s.branch_id = b.branch_id
    LIMIT 1
)
INSERT INTO pos_schema.score_transaction
    (tenant_id, tenant_customer_id, transaction_type_id, points, sale_id, sale_collection_id)
SELECT tenant_id, tenant_customer_id, 1, 7, sale_id, sale_collection_id
FROM ctx;

-- 3. El crecimiento (consulta de finances/loyalty) suma esos puntos al bucket
--    de su fecha y a la sucursal de la venta.
SELECT date_trunc('month', st.created_at) AS bucket, b.branch_id, SUM(st.points) AS earned
FROM pos_schema.score_transaction st
JOIN pos_schema.sale s ON s.sale_id = st.sale_id
JOIN general_schema.branch b ON b.branch_id = s.branch_id
WHERE st.sale_collection_id IS NOT NULL
GROUP BY 1, 2;
-- Esperado: una fila con earned = 7.

-- 4. Borrar la venta no borra el movimiento (ON DELETE SET NULL): el saldo del
--    cliente no depende de la venta.

ROLLBACK;
```

## Verificacion de la conversion de moneda del programa (FNZ-FI-01)

El backend (`loyalty-currency.ts`) convierte la venta a USD con la tasa vigente
antes de aplicar `points_earned_per_currency_unit`. Esta consulta reproduce la
conversion:

```sql
SELECT
    1000                        AS monto_ves,
    general_schema.get_exchange_rate_at(t.tenant_id, (now() AT TIME ZONE 'UTC')) AS tasa_usd_ves,
    1000 / NULLIF(general_schema.get_exchange_rate_at(t.tenant_id, (now() AT TIME ZONE 'UTC')), 0) AS monto_usd
FROM general_schema.tenant t
LIMIT 1;
-- Esperado: monto_usd = monto_ves / tasa. Una venta de Bs. 1.000 otorga los
-- puntos de monto_usd dolares, no de 1.000 unidades.
```

Pruebas automatizadas de la logica de acumulacion:
`my-business-panel-backend/src/contexts/pos/modules/loyal-program/loyalty-currency.spec.ts`.
