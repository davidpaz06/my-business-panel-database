-- Migration: 028-migrate-identification-types-to-ve
-- What: Replace the Costa Rica identification_type catalog (Cedula Fisica,
--       Cedula Juridica, DIMEX, NITE, Extranjero No Domiciliado, No Contribuyente)
--       with Venezuela's identification types: Cedula de Identidad (V), Cedula
--       de Identidad Extranjero (E), RIF Persona Juridica (J), RIF Ente
--       Gubernamental (G), Pasaporte (P). Reuses the existing rows (UPDATE by
--       type_name -> new type_name) so tenant/tenant_customer rows already
--       pointing at identification_type_id 1-6 keep a valid, now VE-meaningful
--       reference instead of being orphaned.
-- Why:  Costa Rica -> Venezuela business migration. The catalog's ident_code
--       column was documented as "required for facturacion" (Hacienda) — that
--       requirement is gone (migrations/pos/020, /pos/021), so ident_code is now
--       just a short internal code for the identification type, not a Hacienda
--       tipo-identificacion value.
-- Context: Slice D (identification types) of the general-module CR->VE
--       migration. No VE equivalent exists for "No Contribuyente" (a Costa Rica
--       DGT registration concept) — not carried over; confirm with the business
--       before adding a VE analog if one turns out to be needed.

-- ─────────────────────────────────────────────────────────────────────────────
-- FORWARD MIGRATION
-- ─────────────────────────────────────────────────────────────────────────────

COMMENT ON COLUMN general_schema.identification_type.ident_code IS
    'Short internal code for the identification type. No longer tied to any Hacienda tipo-identificacion requirement.';

UPDATE general_schema.identification_type
   SET type_name = 'Cedula de Identidad',
       description = 'Cedula de identidad venezolana (persona natural)',
       ident_code = 'V'
 WHERE type_name = 'Cedula Fisica';

UPDATE general_schema.identification_type
   SET type_name = 'RIF Persona Juridica',
       description = 'Registro de Informacion Fiscal de persona juridica',
       ident_code = 'J'
 WHERE type_name = 'Cedula Juridica';

UPDATE general_schema.identification_type
   SET type_name = 'Cedula de Identidad Extranjero',
       description = 'Cedula de identidad venezolana para extranjero residente',
       ident_code = 'E'
 WHERE type_name = 'DIMEX';

UPDATE general_schema.identification_type
   SET type_name = 'RIF Ente Gubernamental',
       description = 'Registro de Informacion Fiscal de ente gubernamental',
       ident_code = 'G'
 WHERE type_name = 'NITE';

UPDATE general_schema.identification_type
   SET type_name = 'Pasaporte',
       description = 'Pasaporte de extranjero no residente',
       ident_code = 'P'
 WHERE type_name = 'Extranjero No Domiciliado';

DELETE FROM general_schema.identification_type
 WHERE type_name = 'No Contribuyente';


-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- UPDATE general_schema.identification_type SET type_name = 'Cedula Fisica', description = 'Tarjeta de identificacion en fisico', ident_code = '01' WHERE type_name = 'Cedula de Identidad';
-- UPDATE general_schema.identification_type SET type_name = 'Cedula Juridica', description = 'Numero de identificacion asignado por el Registro Nacional', ident_code = '02' WHERE type_name = 'RIF Persona Juridica';
-- UPDATE general_schema.identification_type SET type_name = 'DIMEX', description = 'Documento de Identidad Migratorio para Extranjeros', ident_code = '03' WHERE type_name = 'Cedula de Identidad Extranjero';
-- UPDATE general_schema.identification_type SET type_name = 'NITE', description = 'Numero de Identificacion Tributaria Especial', ident_code = '04' WHERE type_name = 'RIF Ente Gubernamental';
-- UPDATE general_schema.identification_type SET type_name = 'Extranjero No Domiciliado', description = 'Cliente o proveedor sin residencia en el pais', ident_code = '05' WHERE type_name = 'Pasaporte';
-- INSERT INTO general_schema.identification_type(type_name, description, ident_code) VALUES ('No Contribuyente', 'Persona no inscrita en el DGT', '06');
