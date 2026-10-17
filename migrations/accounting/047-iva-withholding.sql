-- ============================================================
-- Migration: 047-iva-withholding
-- Schema: accounting (toca general y purchase)
-- Date: 2026-10-17
-- Author: Claude (session work)
--
-- Why: FNZ-IV-06 (my-business-panel-docs/MBP_Auditoria_Finanzas.md). El modulo
-- de IVA no modelaba retenciones. Se agrega un modelo PARAMETRIZABLE de
-- retencion de IVA en compras (el tenant como agente de retencion):
--
--   - general_schema.tenant.is_iva_withholding_agent: si el tenant retiene.
--   - purchase_schema.supplier.iva_retention_percentage: porcentaje del IVA de
--     cada factura del proveedor que se retiene (0 = no se retiene).
--   - accounting_schema.iva_withholding: comprobante de retencion, uno por
--     factura de proveedor, con correlativo propio por tenant.
--
-- IMPORTANTE: el modelo NO asume porcentajes ni quienes son sujetos de
-- retencion (la normativa del SENIAT lo define y cambia): ambos son datos que
-- carga el contador. Los valores por defecto no retienen nada. El formato del
-- comprobante (campos, impresion) esta pendiente de la especificacion legal.
--
-- Filas existentes: sin cambios (defaults FALSE / 0).
-- ============================================================

ALTER TABLE general_schema.tenant
    ADD COLUMN IF NOT EXISTS is_iva_withholding_agent BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE purchase_schema.supplier
    ADD COLUMN IF NOT EXISTS iva_retention_percentage NUMERIC(5,2) NOT NULL DEFAULT 0;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_supplier_iva_retention_pct'
    ) THEN
        ALTER TABLE purchase_schema.supplier
            ADD CONSTRAINT chk_supplier_iva_retention_pct
            CHECK (iva_retention_percentage >= 0 AND iva_retention_percentage <= 100);
    END IF;
END $$;

COMMENT ON COLUMN general_schema.tenant.is_iva_withholding_agent IS
    'El tenant actua como agente de retencion de IVA en sus compras (FNZ-IV-06).';
COMMENT ON COLUMN purchase_schema.supplier.iva_retention_percentage IS
    'Porcentaje del IVA de cada factura del proveedor que se retiene (0-100). Dato cargado por el contador; 0 = sin retencion.';

CREATE TABLE IF NOT EXISTS accounting_schema.iva_withholding (
    withholding_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id            UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    voucher_number       INTEGER NOT NULL,
    supplier_invoice_id  UUID NOT NULL REFERENCES purchase_schema.supplier_invoice(supplier_invoice_id),
    supplier_id          UUID NOT NULL REFERENCES purchase_schema.supplier(supplier_id),
    invoice_number       VARCHAR(100) NOT NULL,
    taxable_base         NUMERIC(14,3) NOT NULL,
    iva_amount           NUMERIC(14,3) NOT NULL,
    retention_percentage NUMERIC(5,2) NOT NULL,
    retained_amount      NUMERIC(14,3) NOT NULL,
    currency_id          INTEGER NOT NULL DEFAULT 2 REFERENCES general_schema.currency(currency_id),
    exchange_rate        NUMERIC(18,8),
    issued_at            TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_voided            BOOLEAN NOT NULL DEFAULT FALSE,
    voided_at            TIMESTAMP,
    created_by           UUID REFERENCES general_schema.users(user_id) ON DELETE SET NULL,
    created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT chk_iva_withholding_pct CHECK (retention_percentage > 0 AND retention_percentage <= 100),
    CONSTRAINT chk_iva_withholding_amounts CHECK (retained_amount >= 0 AND iva_amount >= 0)
);

-- Correlativo por tenant, sin huecos reutilizables: un comprobante anulado
-- conserva su numero.
CREATE UNIQUE INDEX IF NOT EXISTS uq_iva_withholding_tenant_number
    ON accounting_schema.iva_withholding(tenant_id, voucher_number);

-- Una factura de proveedor tiene a lo sumo un comprobante vigente.
CREATE UNIQUE INDEX IF NOT EXISTS uq_iva_withholding_active_invoice
    ON accounting_schema.iva_withholding(supplier_invoice_id)
    WHERE is_voided = FALSE;

CREATE INDEX IF NOT EXISTS idx_iva_withholding_tenant_issued
    ON accounting_schema.iva_withholding(tenant_id, issued_at);

COMMENT ON TABLE accounting_schema.iva_withholding IS
    'Comprobantes de retencion de IVA practicados a proveedores (FNZ-IV-06). Montos en currency_id (USD: las compras estan en USD); exchange_rate = tasa USD -> VES al emitir.';

-- ============================================================
-- Rollback (documentacion; no se ejecuta automaticamente):
--   DROP TABLE IF EXISTS accounting_schema.iva_withholding;
--   ALTER TABLE purchase_schema.supplier DROP CONSTRAINT IF EXISTS chk_supplier_iva_retention_pct;
--   ALTER TABLE purchase_schema.supplier DROP COLUMN IF EXISTS iva_retention_percentage;
--   ALTER TABLE general_schema.tenant DROP COLUMN IF EXISTS is_iva_withholding_agent;
-- ============================================================
