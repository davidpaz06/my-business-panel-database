SET SEARCH_PATH TO general_schema;

INSERT INTO general_schema.currency(currency_code, currency_name, symbol) VALUES
('VES', 'Bolivar', 'Bs.'),
('USD', 'US Dollar', '$'),
('EUR', 'Euro', '€'),
('GBP', 'British Pound', '£'),
('JPY', 'Japanese Yen', '¥')
ON CONFLICT DO NOTHING;