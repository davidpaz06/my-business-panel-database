-- ============================================================
-- Migration: 045-journal-entry-currency
-- Schema: accounting
-- Date: 2026-10-15
-- Author: Claude (session work)
--
-- Why: FNZ-X-04 (my-business-panel-docs/MBP_Auditoria_Finanzas.md). El libro
-- contable no tenia moneda: asientos de ventas en Bs. y en USD, compras en
-- USD y costo de ventas en USD se registraban en las mismas cuentas sin
-- distincion, mezclando monedas en los saldos.
--
-- Regla: el libro se lleva en la moneda funcional (bolivares, VES). Las
-- lineas (journal_entry_line) quedan siempre en VES; el asiento guarda la
-- moneda del documento de origen y la tasa USD -> VES usada para convertirlo
-- (la vigente en la fecha del documento, general_schema.get_exchange_rate_at).
-- Documentos en VES: currency_id 1 y exchange_rate 1.
--
-- Los asientos existentes no se tocan (default VES / 1): en todos los
-- entornos revisados no habia ningun asiento, porque ningun tenant tenia el
-- plan de cuentas provisionado (ver AccountingJournalService).
-- ============================================================

SET search_path = accounting_schema;

ALTER TABLE accounting_schema.journal_entry
    ADD COLUMN IF NOT EXISTS currency_id INTEGER NOT NULL DEFAULT 1
        REFERENCES general_schema.currency(currency_id);

ALTER TABLE accounting_schema.journal_entry
    ADD COLUMN IF NOT EXISTS exchange_rate NUMERIC(18,8) NOT NULL DEFAULT 1;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_journal_entry_exchange_rate_positive'
    ) THEN
        ALTER TABLE accounting_schema.journal_entry
            ADD CONSTRAINT chk_journal_entry_exchange_rate_positive
            CHECK (exchange_rate > 0);
    END IF;
END $$;

COMMENT ON COLUMN accounting_schema.journal_entry.currency_id IS
    'Moneda del documento de origen. Las lineas del asiento estan siempre en VES (moneda funcional).';
COMMENT ON COLUMN accounting_schema.journal_entry.exchange_rate IS
    'Tasa USD -> VES usada para convertir el documento a VES (1 si el documento ya estaba en VES).';

-- ============================================================
-- Rollback (manual):
-- ALTER TABLE accounting_schema.journal_entry DROP CONSTRAINT IF EXISTS chk_journal_entry_exchange_rate_positive;
-- ALTER TABLE accounting_schema.journal_entry DROP COLUMN IF EXISTS exchange_rate;
-- ALTER TABLE accounting_schema.journal_entry DROP COLUMN IF EXISTS currency_id;
-- ============================================================
