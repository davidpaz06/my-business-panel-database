SET SEARCH_PATH TO hr_schema;

INSERT INTO hr_schema.payment_schedule(description, daycount) VALUES
('Monthly', 30),
('Fortnight', 15),
('Weekly', 7),
('Daily', 1)
ON CONFLICT DO NOTHING;
