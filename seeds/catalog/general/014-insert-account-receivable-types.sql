INSERT INTO general_schema.account_receivable_type (type_name, description) VALUES
    ('venta_credito', 'Venta a crédito a cliente registrado'),
    ('venta_apartado', 'Venta con apartado — inventario reservado hasta liquidar saldo')
ON CONFLICT (type_name) DO NOTHING;
