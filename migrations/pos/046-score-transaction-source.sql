-- ============================================================
-- Migration: 046-score-transaction-source
-- Schema: pos
-- Date: 2026-10-17
-- Author: Claude (session work)
--
-- Why: FNZ-FI-03 (my-business-panel-docs/MBP_Auditoria_Finanzas.md). La
-- grafica de crecimiento del programa de fidelidad solo contaba los puntos
-- otorgados al vender (invoice.points_accumulated). Los puntos proporcionales
-- que se otorgan al registrar cada cobro de una venta a credito o apartado
-- (grantProportionalLoyaltyPoints) solo sumaban al saldo del cliente y no
-- quedaban en ningun registro, ni se podian ubicar por sucursal.
--
-- score_transaction (el ledger de puntos, hasta ahora sin uso) recibe el
-- origen del movimiento: la venta y el cobro que lo generaron. El backend
-- escribe una fila 'earn' por cada otorgamiento de puntos de un cobro; la
-- sucursal se obtiene por la venta.
--
-- Filas existentes: sin cambios (las columnas nuevas son NULL).
-- ============================================================

SET search_path = pos_schema;

ALTER TABLE pos_schema.score_transaction
    ADD COLUMN IF NOT EXISTS sale_id UUID
        REFERENCES pos_schema.sale(sale_id) ON DELETE SET NULL;

ALTER TABLE pos_schema.score_transaction
    ADD COLUMN IF NOT EXISTS sale_collection_id UUID
        REFERENCES pos_schema.sale_collection(sale_collection_id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_score_transaction_sale
    ON pos_schema.score_transaction(sale_id)
    WHERE sale_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_score_transaction_tenant_created
    ON pos_schema.score_transaction(tenant_id, created_at);

COMMENT ON COLUMN pos_schema.score_transaction.sale_id IS
    'Venta que origino el movimiento de puntos (permite ubicar la sucursal).';
COMMENT ON COLUMN pos_schema.score_transaction.sale_collection_id IS
    'Cobro de CxC que otorgo los puntos proporcionales (FNZ-FI-03).';

-- ============================================================
-- Rollback (documentacion; no se ejecuta automaticamente):
--   DROP INDEX IF EXISTS pos_schema.idx_score_transaction_tenant_created;
--   DROP INDEX IF EXISTS pos_schema.idx_score_transaction_sale;
--   ALTER TABLE pos_schema.score_transaction DROP COLUMN IF EXISTS sale_collection_id;
--   ALTER TABLE pos_schema.score_transaction DROP COLUMN IF EXISTS sale_id;
-- ============================================================
