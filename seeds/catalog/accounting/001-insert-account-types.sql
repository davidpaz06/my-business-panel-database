SET SEARCH_PATH TO accounting_schema;

INSERT INTO accounting_schema.account_type(type_name, nature, description) VALUES
('Activo', 'DEBIT', 'Bienes y derechos de la empresa'),
('Pasivo', 'CREDIT', 'Obligaciones y deudas de la empresa'),
('Patrimonio', 'CREDIT', 'Capital y resultados acumulados'),
('Ingreso', 'CREDIT', 'Ingresos operativos y no operativos'),
('Gasto', 'DEBIT', 'Gastos operativos y administrativos'),
('Costo', 'DEBIT', 'Costos directos de producción y venta')
ON CONFLICT DO NOTHING;
