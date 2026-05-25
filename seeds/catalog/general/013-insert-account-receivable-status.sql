INSERT INTO general_schema.account_receivable_status (status_name, description) VALUES
    ('Pending',      'Payment is pending'),
    ('Partial Paid', 'Partial payment has been received'),
    ('Paid',         'Payment has been received in full'),
    ('Overdue',      'Payment is overdue')
ON CONFLICT DO NOTHING;
