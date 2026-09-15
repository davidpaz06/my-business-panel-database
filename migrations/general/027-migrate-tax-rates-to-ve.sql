-- Migration: 027-migrate-tax-rates-to-ve
-- What: Replace the Costa Rica-specific IVA tax_rate rows (keyed to Hacienda's
--       DGT-R-48-2016 CodigoTarifa: 01/05/06/07/08) with Venezuela's SENIAT IVA
--       rates: a single general rate (16%) and an exempt rate (0%). Other
--       regions' rows (Panama, US, EU, UK, Japan) are untouched.
-- Why:  Costa Rica -> Venezuela business migration. Requirement 3 or its
--       replacement mechanism (product.tax_rate_id, migrations/general/024)
--       needs real Venezuela rates to assign. Confirmed with the business: a
--       single 16% general rate, no reduced-rate breakdown yet (that requires
--       a legal spec not currently available — see CLAUDE.md raiz).
-- Context: Slice C (CABYS removal). Existing product rows referencing the old
--       CR tax_rate_id values fall back to NULL (product.tax_rate_id ON DELETE
--       SET NULL) and need re-tagging with a Venezuela rate — expected, since
--       CR rates are not valid for VE sales going forward.

-- ─────────────────────────────────────────────────────────────────────────────
-- FORWARD MIGRATION
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO general_schema.region(region_name, country_code)
VALUES ('Venezuela', '+58')
ON CONFLICT (region_name) DO NOTHING;

DELETE FROM general_schema.tax_rate
 WHERE rate_code IN ('01', '05', '06', '07', '08')
   AND region_id = (SELECT region_id FROM general_schema.region WHERE region_name = 'Costa Rica');

INSERT INTO general_schema.tax_rate (region, region_id, rate_percentage, rate_code, rate_name)
VALUES
    ('VE Exento',   (SELECT region_id FROM general_schema.region WHERE region_name = 'Venezuela'), 0.00,  'EX',  'Exento'),
    ('VE Standard', (SELECT region_id FROM general_schema.region WHERE region_name = 'Venezuela'), 16.00, 'IVA', 'IVA General 16%')
ON CONFLICT (region, rate_percentage) DO UPDATE
  SET rate_code = EXCLUDED.rate_code,
      rate_name = EXCLUDED.rate_name;


-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- DELETE FROM general_schema.tax_rate WHERE rate_code IN ('EX', 'IVA')
--   AND region_id = (SELECT region_id FROM general_schema.region WHERE region_name = 'Venezuela');
-- INSERT INTO general_schema.tax_rate (region, region_id, rate_percentage, rate_code, rate_name) VALUES
-- ('CR Exento',   (SELECT region_id FROM general_schema.region WHERE region_name = 'Costa Rica'), 0.00,  '01', 'Exento'),
-- ('CR IVA 1%',   (SELECT region_id FROM general_schema.region WHERE region_name = 'Costa Rica'), 1.00,  '05', 'IVA 1%'),
-- ('CR IVA 2%',   (SELECT region_id FROM general_schema.region WHERE region_name = 'Costa Rica'), 2.00,  '06', 'IVA 2%'),
-- ('CR IVA 4%',   (SELECT region_id FROM general_schema.region WHERE region_name = 'Costa Rica'), 4.00,  '07', 'IVA 4% - Servicios de Salud'),
-- ('CR Standard', (SELECT region_id FROM general_schema.region WHERE region_name = 'Costa Rica'), 13.00, '08', 'IVA General 13%');
