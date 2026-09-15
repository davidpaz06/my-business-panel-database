SET SEARCH_PATH TO general_schema;

INSERT INTO general_schema.identification_type(type_name, description, ident_code) VALUES
    ('Cedula de Identidad', 'Cedula de identidad venezolana (persona natural)', 'V'),
    ('RIF Persona Juridica', 'Registro de Informacion Fiscal de persona juridica', 'J'),
    ('Cedula de Identidad Extranjero', 'Cedula de identidad venezolana para extranjero residente', 'E'),
    ('RIF Ente Gubernamental', 'Registro de Informacion Fiscal de ente gubernamental', 'G'),
    ('Pasaporte', 'Pasaporte de extranjero no residente', 'P')
ON CONFLICT DO NOTHING;
