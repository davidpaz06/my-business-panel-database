SET SEARCH_PATH TO general_schema;

-- Sistema bimonetario Venezuela: solo Bolivar y Dolar. EUR/GBP/JPY se
-- eliminaron del catalogo (migrations/general/034) -- el sistema maneja
-- una unica tasa de conversion USD -> VES, ver
-- general_schema.exchange_rate + tenant_exchange_delta.
INSERT INTO general_schema.currency(currency_code, currency_name, symbol) VALUES
('VES', 'Bolivar', 'Bs.'),
('USD', 'US Dollar', '$')
ON CONFLICT DO NOTHING;