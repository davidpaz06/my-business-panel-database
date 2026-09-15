SET SEARCH_PATH TO general_schema;

-- Tasas IVA Venezuela (SENIAT). Un unico tramo general vigente al momento de
-- esta migracion; sin desglose de tarifas reducidas (pendiente de spec legal
-- propia, ver CLAUDE.md raiz - retenciones legales VE).
INSERT INTO general_schema.tax_rate (region, region_id, rate_percentage, rate_code, rate_name) VALUES
('VE Exento',   (SELECT region_id FROM general_schema.region WHERE region_name = 'Venezuela'), 0.00,  'EX', 'Exento'),
('VE Standard', (SELECT region_id FROM general_schema.region WHERE region_name = 'Venezuela'), 16.00, 'IVA', 'IVA General 16%'),
('PA Standard', (SELECT region_id FROM general_schema.region WHERE region_name = 'Panama'),     7.00,  NULL, NULL),
('US Federal',  (SELECT region_id FROM general_schema.region WHERE region_name = 'United States'), 10.00, NULL, NULL),
('EU Standard', NULL,                                                                            20.00, NULL, NULL),
('UK Standard', (SELECT region_id FROM general_schema.region WHERE region_name = 'United Kingdom'), 20.00, NULL, NULL),
('JP Standard', (SELECT region_id FROM general_schema.region WHERE region_name = 'Japan'),      8.00,  NULL, NULL)
ON CONFLICT (region, rate_percentage) DO UPDATE
  SET rate_code = EXCLUDED.rate_code,
      rate_name = EXCLUDED.rate_name;
