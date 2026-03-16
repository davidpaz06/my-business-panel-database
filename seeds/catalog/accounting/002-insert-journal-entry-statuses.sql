SET SEARCH_PATH TO accounting_schema;

INSERT INTO accounting_schema.journal_entry_status(status_name, description) VALUES
('Borrador', 'Asiento en estado de borrador, pendiente de confirmación'),
('Confirmado', 'Asiento confirmado y registrado en el libro mayor'),
('Anulado', 'Asiento anulado, no afecta los estados financieros')
ON CONFLICT DO NOTHING;
