-- ============================================================
-- Migration: 033-fix-invoice-item-payment-pk-rename
-- Schema: pos
-- Date: 2026-09-22
-- Author: Claude (session work)
--
-- Why: migrations/pos/021-rename-digital-invoice-to-invoice.sql renombro la
-- tabla y la FK hacia el padre en invoice_item/invoice_payment, pero nunca
-- renombro la PK PROPIA de esas dos tablas -- se quedaron en
-- digital_sale_invoice_item_id / digital_sale_invoice_payment_id, mientras
-- el archivo fuente (schemas/pos/pos_schema.sql) y todo el codigo del
-- backend ya asumen invoice_item_id / invoice_payment_id desde esa misma
-- migracion. Encontrado en la auditoria de ventas a credito (readaptacion
-- Venezuela): GET /invoice/sale/:saleId (pos.queries.ts#getInvoiceBySaleId)
-- fallaba con "column dii.invoice_item_id does not exist" -- error 500 para
-- CUALQUIER venta con factura, en cualquier tenant. Bloqueaba tambien la UI
-- de notas de credito/debito (seccion 5 del doc), que se muestra en el
-- mismo modal de detalle de factura.
--
-- Solo se renombran las COLUMNAS (lo unico que rompe queries por nombre).
-- Los nombres de constraint/indice quedan con el prefijo legado
-- digital_sale_invoice_* -- cosmetico, no rompe nada funcional, y evita
-- adivinar nombres exactos de constraints no verificados. Ninguna FK
-- externa referencia estas PKs (verificado: sin confrelid apuntando a
-- estas tablas), asi que el rename de columna es de bajo riesgo.
-- ============================================================

ALTER TABLE pos_schema.invoice_item
    RENAME COLUMN digital_sale_invoice_item_id TO invoice_item_id;

ALTER TABLE pos_schema.invoice_payment
    RENAME COLUMN digital_sale_invoice_payment_id TO invoice_payment_id;

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- ALTER TABLE pos_schema.invoice_payment RENAME COLUMN invoice_payment_id TO digital_sale_invoice_payment_id;
-- ALTER TABLE pos_schema.invoice_item RENAME COLUMN invoice_item_id TO digital_sale_invoice_item_id;
