# Test: retencion de IVA en compras (migracion accounting/047)

Cubre FNZ-IV-06. Modelo parametrizable: no hay porcentajes ni sujetos por
defecto. Idempotente: todo corre dentro de una transaccion con `ROLLBACK`.

## Script

```sql
BEGIN;

-- 1. Estructura (migracion 047 aplicada).
SELECT
    (SELECT COUNT(*) FROM information_schema.columns
      WHERE table_schema = 'general_schema' AND table_name = 'tenant'
        AND column_name = 'is_iva_withholding_agent') AS tenant_flag,
    (SELECT COUNT(*) FROM information_schema.columns
      WHERE table_schema = 'purchase_schema' AND table_name = 'supplier'
        AND column_name = 'iva_retention_percentage') AS supplier_pct,
    (SELECT COUNT(*) FROM information_schema.tables
      WHERE table_schema = 'accounting_schema' AND table_name = 'iva_withholding') AS voucher_table;
-- Esperado: 1, 1, 1.

-- 2. Defaults: ningun tenant retiene y ningun proveedor tiene porcentaje.
SELECT COUNT(*) AS agentes FROM general_schema.tenant WHERE is_iva_withholding_agent;
SELECT COUNT(*) AS proveedores_con_retencion
FROM purchase_schema.supplier WHERE iva_retention_percentage <> 0;
-- Esperado: 0 y 0 (en una DB recien migrada).

-- 3. El porcentaje esta acotado a 0-100.
DO $$
BEGIN
    UPDATE purchase_schema.supplier SET iva_retention_percentage = 101
    WHERE supplier_id = (SELECT supplier_id FROM purchase_schema.supplier LIMIT 1);
    RAISE EXCEPTION 'debio fallar el CHECK de porcentaje';
EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK: CHECK chk_supplier_iva_retention_pct rechaza 101';
END $$;

-- 4. Un comprobante vigente por factura y correlativo unico por tenant.
WITH ctx AS (
    SELECT sup.added_by AS tenant_id, si.supplier_invoice_id, sup.supplier_id,
           si.invoice_number
    FROM purchase_schema.supplier_invoice si
    JOIN purchase_schema.purchase_order po ON po.purchase_order_id = si.purchase_order_id
    JOIN purchase_schema.supplier sup ON sup.supplier_id = po.supplier_id
    LIMIT 1
)
INSERT INTO accounting_schema.iva_withholding
    (tenant_id, voucher_number, supplier_invoice_id, supplier_id, invoice_number,
     taxable_base, iva_amount, retention_percentage, retained_amount)
SELECT tenant_id, 1, supplier_invoice_id, supplier_id, invoice_number, 100, 16, 75, 12
FROM ctx;

-- Segundo comprobante vigente para la misma factura: debe fallar
-- (uq_iva_withholding_active_invoice).
-- Despues de anular el primero, si se puede emitir otro con numero nuevo.

ROLLBACK;
```

## Pruebas automatizadas

- `my-business-panel-backend/src/contexts/finances/modules/iva/iva-withholding.service.spec.ts`:
  calculo del monto retenido, correlativo, rechazo si el tenant no es agente, si
  el proveedor no tiene porcentaje, si la factura no tiene IVA, atomicidad con el
  asiento y anulacion.
- `accounting-journal.returns-notes.spec.ts`: el asiento (Dr CxP, Cr Retenciones
  por Pagar).

## Pendiente de la especificacion legal

El formato impreso del comprobante, los plazos para enterar lo retenido y la
lista de sujetos obligados no estan modelados: dependen de la providencia
vigente del SENIAT.
