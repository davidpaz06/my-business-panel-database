SET SEARCH_PATH TO accounting_schema;

INSERT INTO accounting_schema.source_type(source_name, description) VALUES
('SALE_CASH', 'Venta al contado'),
('SALE_CREDIT', 'Venta a crédito'),
('SALE_COGS', 'Costo de venta asociado a una venta'),
('PURCHASE', 'Compra de inventario o servicios'),
('PAYMENT_RECEIVED', 'Pago recibido de cliente'),
('PAYMENT_MADE', 'Pago realizado a proveedor'),
('PAYROLL', 'Registro de nómina'),
('MANUAL', 'Asiento manual ingresado por el usuario'),
('ADJUSTMENT', 'Ajuste contable')
ON CONFLICT DO NOTHING;
