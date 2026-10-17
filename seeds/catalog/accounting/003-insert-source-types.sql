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
('ADJUSTMENT', 'Ajuste contable'),
('EXPENSE', 'Registro de gasto operativo'),
('SALE_RETURN', 'Devolución de venta'),
('CREDIT_NOTE', 'Nota de crédito sobre una factura de venta'),
('DEBIT_NOTE', 'Nota de débito sobre una factura de venta'),
('IVA_WITHHOLDING', 'Comprobante de retención de IVA a proveedor')
ON CONFLICT DO NOTHING;
