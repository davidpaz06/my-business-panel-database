-- ============================================================
-- Migration: 035-supplier-credit-from-damaged-goods
-- Schema: purchase
-- Date: 2026-09-24
-- Author: Claude (session work)
--
-- Why: MBP_Cambios_CR_a_Venezuela.md, seccion 5 (Modulo POS) -- gap detectado
-- en auditoria 2026-09-24: la nota de credito de venta por "mercancia danada"
-- (pos_schema.credit_debit_note.reason_kind = 'mercancia_danada') no tenia
-- ningun vinculo con el modulo de Compras. El doc pide explicitamente que
-- ese monto quede disponible para descontarse en la proxima orden al
-- distribuidor/proveedor.
--
-- Diseno: la nota de venta es a nivel de factura completa, no de item, asi
-- que no se puede inferir con certeza cual proveedor origino la mercancia
-- danada -- el usuario que registra la nota selecciona el proveedor
-- explicitamente (backend/frontend). Esta migracion solo crea el saldo de
-- credito del lado de Compras; la seleccion de proveedor vive en el DTO de
-- pos_schema.credit_debit_note (capa de aplicacion, no de schema).
-- ============================================================

CREATE TABLE IF NOT EXISTS purchase_schema.supplier_credit(
    supplier_credit_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    supplier_id         uuid NOT NULL REFERENCES purchase_schema.supplier(supplier_id) ON DELETE CASCADE,
    -- Nota de venta (pos_schema) que origino el credito. Una nota solo puede
    -- generar un credito de proveedor (UNIQUE).
    source_note_id      uuid NOT NULL UNIQUE REFERENCES pos_schema.credit_debit_note(note_id) ON DELETE CASCADE,
    original_amount     NUMERIC(12,3) NOT NULL CHECK (original_amount > 0),
    remaining_amount     NUMERIC(12,3) NOT NULL CHECK (remaining_amount >= 0),
    status              VARCHAR(10) NOT NULL DEFAULT 'AVAILABLE'
                             CHECK (status IN ('AVAILABLE', 'APPLIED', 'VOIDED')),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    CHECK (remaining_amount <= original_amount)
);

CREATE INDEX IF NOT EXISTS idx_supplier_credit_supplier
    ON purchase_schema.supplier_credit(supplier_id, status);
CREATE INDEX IF NOT EXISTS idx_supplier_credit_tenant
    ON purchase_schema.supplier_credit(tenant_id);

COMMENT ON TABLE purchase_schema.supplier_credit IS
    'Saldo a favor del tenant frente a un proveedor, originado por una nota de credito de venta por mercancia danada (pos_schema.credit_debit_note). Aplicable contra el balance de una purchase_account_payable via supplier_credit_application.';

-- Traza de cada aplicacion del credito contra una cuenta por pagar de
-- compras. Se apoya en el mecanismo ya existente de purchase_order_payment
-- (metodo de pago dedicado 'supplier_credit', ver seeds/catalog/general/015)
-- para que recalc_account_payable_on_payment() recalcule el balance sin
-- duplicar esa logica aqui.
CREATE TABLE IF NOT EXISTS purchase_schema.supplier_credit_application(
    supplier_credit_application_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    supplier_credit_id             uuid NOT NULL REFERENCES purchase_schema.supplier_credit(supplier_credit_id) ON DELETE CASCADE,
    purchase_account_payable_id    uuid NOT NULL REFERENCES purchase_schema.purchase_account_payable(purchase_account_payable_id) ON DELETE CASCADE,
    purchase_order_payment_id      uuid NOT NULL REFERENCES purchase_schema.purchase_order_payment(purchase_order_payment_id) ON DELETE CASCADE,
    amount_applied                 NUMERIC(12,3) NOT NULL CHECK (amount_applied > 0),
    applied_by                     uuid REFERENCES general_schema.users(user_id) ON DELETE SET NULL,
    created_at                     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_supplier_credit_application_credit
    ON purchase_schema.supplier_credit_application(supplier_credit_id);
CREATE INDEX IF NOT EXISTS idx_supplier_credit_application_payable
    ON purchase_schema.supplier_credit_application(purchase_account_payable_id);

-- Si la nota de venta que origino el credito se anula, el credito se anula
-- tambien -- pero SOLO si todavia no se aplico nada (remaining_amount =
-- original_amount). Si ya se aplico parcial o totalmente contra una orden de
-- compra, ese movimiento ya afecto un balance real de compras y anularlo
-- automaticamente requeriria revertir pagos ya contabilizados -- se deja
-- como accion manual deliberada, documentada aqui.
CREATE OR REPLACE FUNCTION purchase_schema.void_supplier_credit_on_note_void()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT (NEW.is_voided = TRUE AND OLD.is_voided = FALSE) THEN
        RETURN NEW;
    END IF;

    UPDATE purchase_schema.supplier_credit
    SET status = 'VOIDED',
        remaining_amount = 0,
        updated_at = CURRENT_TIMESTAMP
    WHERE source_note_id = NEW.note_id
      AND status = 'AVAILABLE'
      AND remaining_amount = original_amount;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS void_supplier_credit_on_note_void_trigger ON pos_schema.credit_debit_note;
CREATE TRIGGER void_supplier_credit_on_note_void_trigger
AFTER UPDATE OF is_voided ON pos_schema.credit_debit_note
FOR EACH ROW
EXECUTE FUNCTION purchase_schema.void_supplier_credit_on_note_void();

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- DROP TRIGGER IF EXISTS void_supplier_credit_on_note_void_trigger ON pos_schema.credit_debit_note;
-- DROP FUNCTION IF EXISTS purchase_schema.void_supplier_credit_on_note_void();
-- DROP TABLE IF EXISTS purchase_schema.supplier_credit_application;
-- DROP TABLE IF EXISTS purchase_schema.supplier_credit;
