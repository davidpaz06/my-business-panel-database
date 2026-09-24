SET SEARCH_PATH TO general_schema;

INSERT INTO general_schema.payment_method(name, description) VALUES
('cash', 'Payment made with cash'),
('debit_card', 'Payment made with debit card'),
('credit_card', 'Payment made with credit card'),
('loyalty_points', 'Payment made via loyalty points'),
('credit', 'Payment made through a credit account'),
('bank_transfer', 'Payment made through bank transfer'),
('pago_movil', 'Pago movil interbancario (Venezuela)')
ON CONFLICT DO NOTHING;