-- ============================================================
-- Migration: 032-credit-debit-notes
-- Schema: pos
-- Date: 2026-09-22
-- Author: Claude (session work)
--
-- Why: MBP_Cambios_CR_a_Venezuela.md, seccion 5 (Modulo POS): al crear una
-- factura de venta debe poder marcarse como Nota de Credito (ajusta/corrige
-- el valor de una factura ya emitida: devoluciones, descuentos, errores,
-- mercancia danada) o Nota de Debito (aumenta el monto de una factura ya
-- emitida sin anularla: mora, cargos adicionales) -- confirmado con el
-- usuario: aplica sobre pos_schema.invoice (factura de venta al cliente),
-- no sobre facturas de compra.
--
-- La factura original NUNCA se edita ni anula -- la nota es un registro de
-- ajuste aparte, auditable, con su propia numeracion. El saldo real del
-- cliente se calcula sumando/restando las notas activas sobre el total de
-- la factura, igual que ya se hace con sale_account_receivable.tax_amount
-- (ver migrations/pos/031 y accounts-receivable.queries.ts).
-- ============================================================

CREATE TABLE IF NOT EXISTS pos_schema.credit_debit_note (
    note_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    note_number     SERIAL,
    tenant_id       UUID NOT NULL REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
    invoice_id      UUID NOT NULL REFERENCES pos_schema.invoice(invoice_id) ON DELETE CASCADE,
    note_type       VARCHAR(10) NOT NULL CHECK (note_type IN ('credit', 'debit')),
    -- devolucion | descuento | error | mercancia_danada (credit);
    -- mora | cargo_adicional | otro (debit, y comodin para credit).
    reason_kind     VARCHAR(30) NOT NULL,
    description     TEXT,
    amount          NUMERIC(10,2) NOT NULL CHECK (amount > 0),
    currency_id     INTEGER REFERENCES general_schema.currency(currency_id) ON DELETE SET NULL,
    is_voided       BOOLEAN NOT NULL DEFAULT FALSE,
    voided_at       TIMESTAMP,
    created_by      UUID REFERENCES general_schema.users(user_id) ON DELETE SET NULL,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_credit_debit_note_invoice
    ON pos_schema.credit_debit_note(invoice_id);
CREATE INDEX IF NOT EXISTS idx_credit_debit_note_tenant
    ON pos_schema.credit_debit_note(tenant_id);

COMMENT ON TABLE pos_schema.credit_debit_note IS
    'Notas de credito/debito sobre facturas de venta (Venezuela). No editan ni anulan pos_schema.invoice -- son un registro de ajuste separado y auditable.';

-- Si la factura de la nota pertenece a una venta con cuenta por cobrar
-- abierta (credito/apartado), la nota debe reflejarse en lo que el cliente
-- todavia debe -- mismo patron que la reconciliacion de devoluciones
-- (migrations/pos/031): ajusta account_receivable.subtotal y reusa
-- check_account_receivable_completion() para is_paid/status.
CREATE OR REPLACE FUNCTION pos_schema.apply_credit_debit_note_to_ar()
RETURNS TRIGGER AS $$
DECLARE
    _sale_id uuid;
    _ar_id uuid;
    _delta numeric(10,2);
BEGIN
    IF NEW.is_voided THEN
        RETURN NEW;
    END IF;

    SELECT sale_id INTO _sale_id FROM pos_schema.invoice WHERE invoice_id = NEW.invoice_id;
    IF _sale_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT ar.account_receivable_id INTO _ar_id
    FROM general_schema.account_receivable ar
    JOIN pos_schema.sale_account_receivable sar
        ON sar.account_receivable_id = ar.account_receivable_id
    WHERE sar.sale_id = _sale_id;

    IF _ar_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- credito reduce lo que el cliente debe, debito lo aumenta.
    _delta := CASE WHEN NEW.note_type = 'credit' THEN -NEW.amount ELSE NEW.amount END;

    UPDATE general_schema.account_receivable
    SET subtotal = GREATEST(subtotal + _delta, 0),
        updated_at = CURRENT_TIMESTAMP
    WHERE account_receivable_id = _ar_id;

    PERFORM pos_schema.check_account_receivable_completion(_ar_id);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS apply_credit_debit_note_to_ar_trigger ON pos_schema.credit_debit_note;
CREATE TRIGGER apply_credit_debit_note_to_ar_trigger
AFTER INSERT ON pos_schema.credit_debit_note
FOR EACH ROW
EXECUTE FUNCTION pos_schema.apply_credit_debit_note_to_ar();

-- Anular una nota debe revertir su efecto sobre la cuenta por cobrar --
-- mismo delta, signo invertido. Sin esto, anular una nota mal cargada deja
-- el saldo del cliente permanentemente desviado (el mismo tipo de bug que
-- esta migracion arregla para las devoluciones).
CREATE OR REPLACE FUNCTION pos_schema.revert_credit_debit_note_on_void()
RETURNS TRIGGER AS $$
DECLARE
    _sale_id uuid;
    _ar_id uuid;
    _delta numeric(10,2);
BEGIN
    IF NOT (NEW.is_voided = TRUE AND OLD.is_voided = FALSE) THEN
        RETURN NEW;
    END IF;

    SELECT sale_id INTO _sale_id FROM pos_schema.invoice WHERE invoice_id = NEW.invoice_id;
    IF _sale_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT ar.account_receivable_id INTO _ar_id
    FROM general_schema.account_receivable ar
    JOIN pos_schema.sale_account_receivable sar
        ON sar.account_receivable_id = ar.account_receivable_id
    WHERE sar.sale_id = _sale_id;

    IF _ar_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Signo invertido respecto a apply_credit_debit_note_to_ar: anular un
    -- credito devuelve lo que se habia restado; anular un debito quita lo
    -- que se habia sumado.
    _delta := CASE WHEN NEW.note_type = 'credit' THEN NEW.amount ELSE -NEW.amount END;

    UPDATE general_schema.account_receivable
    SET subtotal = GREATEST(subtotal + _delta, 0),
        updated_at = CURRENT_TIMESTAMP
    WHERE account_receivable_id = _ar_id;

    PERFORM pos_schema.check_account_receivable_completion(_ar_id);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS revert_credit_debit_note_on_void_trigger ON pos_schema.credit_debit_note;
CREATE TRIGGER revert_credit_debit_note_on_void_trigger
AFTER UPDATE OF is_voided ON pos_schema.credit_debit_note
FOR EACH ROW
EXECUTE FUNCTION pos_schema.revert_credit_debit_note_on_void();

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- DROP TRIGGER IF EXISTS revert_credit_debit_note_on_void_trigger ON pos_schema.credit_debit_note;
-- DROP FUNCTION IF EXISTS pos_schema.revert_credit_debit_note_on_void();
-- DROP TRIGGER IF EXISTS apply_credit_debit_note_to_ar_trigger ON pos_schema.credit_debit_note;
-- DROP FUNCTION IF EXISTS pos_schema.apply_credit_debit_note_to_ar();
-- DROP TABLE IF EXISTS pos_schema.credit_debit_note;
