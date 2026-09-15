SET SEARCH_PATH TO general_schema;

INSERT INTO general_schema.region(region_name, country_code) VALUES
    ('Venezuela',     '+58'),
    ('Costa Rica',    '+506'),
    ('Panama',        '+507'),
    ('United States', '+1'),
    ('United Kingdom','+44'),
    ('Japan',         '+81'),
    ('Spain',         '+34')
ON CONFLICT (region_name) DO UPDATE SET country_code = EXCLUDED.country_code;