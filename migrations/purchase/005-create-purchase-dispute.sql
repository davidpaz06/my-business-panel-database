-- Migration: 005-create-purchase-dispute
-- What: New table purchase_schema.purchase_dispute to formalize the
--       proveedor-discrepancy workflow (open/resolved states, notify flag).
-- Why:  MBP_Cambios_CR_a_Venezuela.md seccion 3: "Discrepancias con el
--       proveedor: Boton de 'reportar discrepancia' (mercancia incompleta o
--       precio distinto al pactado) que abre un workflow con estados
--       abierta/resuelta y envia notificacion al proveedor."
-- Context: Fase 5 del plan de migracion del modulo de Compras. Alcance
--       confirmado con el usuario: solo workflow interno (tabla + estados +
--       bandera notify_supplier_pending); sin integracion real de envio de
--       email/SMS en esta fase (esos canales de hecho se ocultan igual en la
--       config de alertas de pago, ver 006-... / cambios de frontend).

-- ─────────────────────────────────────────────────────────────────────────────
-- FORWARD MIGRATION
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS purchase_schema.purchase_dispute(
    dispute_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    purchase_order_id uuid NOT NULL REFERENCES purchase_schema.purchase_order(purchase_order_id) ON DELETE CASCADE,
    supplier_invoice_id uuid REFERENCES purchase_schema.supplier_invoice(supplier_invoice_id) ON DELETE SET NULL,
    tenant_id uuid NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    dispute_type VARCHAR(20) NOT NULL,
    description TEXT NOT NULL,
    status VARCHAR(10) NOT NULL DEFAULT 'OPEN',
    notify_supplier_pending BOOLEAN NOT NULL DEFAULT TRUE,
    resolution_notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CHECK (dispute_type IN ('MISSING_GOODS', 'PRICE_MISMATCH')),
    CHECK (status IN ('OPEN', 'RESOLVED'))
);

CREATE INDEX IF NOT EXISTS idx_purchase_dispute_order
    ON purchase_schema.purchase_dispute(purchase_order_id);

CREATE INDEX IF NOT EXISTS idx_purchase_dispute_tenant_status
    ON purchase_schema.purchase_dispute(tenant_id, status);

COMMENT ON TABLE purchase_schema.purchase_dispute IS
    'Workflow de discrepancias con el proveedor (mercancia incompleta o precio distinto al pactado). notify_supplier_pending es una bandera de UI/estado interno; no dispara envio real de email/SMS en esta fase.';

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- DROP INDEX IF EXISTS purchase_schema.idx_purchase_dispute_tenant_status;
-- DROP INDEX IF EXISTS purchase_schema.idx_purchase_dispute_order;
-- DROP TABLE IF EXISTS purchase_schema.purchase_dispute;
