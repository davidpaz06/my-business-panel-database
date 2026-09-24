SET SEARCH_PATH TO general_schema;

-- Metodo de pago dedicado para aplicar un credito de proveedor (originado por
-- una nota de credito de mercancia danada) contra una cuenta por pagar de
-- compras. Ver migrations/purchase/035-supplier-credit-from-damaged-goods.sql.
INSERT INTO general_schema.payment_method(name, description) VALUES
('supplier_credit', 'Aplicacion de credito de proveedor (nota de credito por mercancia danada)')
ON CONFLICT DO NOTHING;
