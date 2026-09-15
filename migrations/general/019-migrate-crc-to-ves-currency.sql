-- Migration: 019-migrate-crc-to-ves-currency
-- What: Repoint the CRC currency row to VES (Bolivar). currency_id stays the same
--       (1, from SERIAL insertion order) so every DEFAULT 1 / implicit base-currency
--       assumption elsewhere (purchase_order.currency_id, sale_collection.currency_id)
--       keeps working without a cascade of ID changes.
-- Why:  Costa Rica -> Venezuela business migration. The app's base currency changes
--       from Colon (CRC) to Bolivar (VES), coexisting with USD which is unchanged.
-- Context: Part of the general-module CR->VE migration (Slice A: currency).

-- ─────────────────────────────────────────────────────────────────────────────
-- FORWARD MIGRATION
-- ─────────────────────────────────────────────────────────────────────────────

UPDATE general_schema.currency
   SET currency_code = 'VES',
       currency_name = 'Bolivar',
       symbol        = 'Bs.'
 WHERE currency_code = 'CRC'
   AND NOT EXISTS (
       SELECT 1 FROM general_schema.currency WHERE currency_code = 'VES'
   );


-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- UPDATE general_schema.currency
--    SET currency_code = 'CRC',
--        currency_name = 'Costa Rican Colón',
--        symbol        = '₡'
--  WHERE currency_code = 'VES';
