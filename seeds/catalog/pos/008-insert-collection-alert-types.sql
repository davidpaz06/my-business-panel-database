INSERT INTO pos_schema.sale_collection_alert_type (collection_alert_type_name, description) VALUES
    ('Upcoming Due Date', 'Alert for upcoming collection due date'),
    ('Urgent Collection', 'Alert for urgent collections near due date'),
    ('Overdue Collection', 'Alert for overdue collections past due date')
ON CONFLICT DO NOTHING;
