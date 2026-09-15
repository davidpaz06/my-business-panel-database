-- Migration: 022-drop-hacienda-config
-- What: Drop tenant_hacienda_config (Hacienda fiscal credentials: username/password,
--       client_id, P12 certificate) and branch_location (structured CR address for
--       DGT-R-48-2016 e-invoicing: provincia/canton/distrito/otras_senas).
-- Why:  Costa Rica -> Venezuela business migration. Requirement 1: remove
--       everything related to Hacienda electronic invoicing. Neither table has any
--       use outside that flow. A future SENIAT-based e-invoicing module (mechanism
--       — fiscal machine vs XML — not yet confirmed) will introduce its own tables
--       shaped around Venezuela's actual requirements rather than reusing these.
-- Context: Slice B (invoice consolidation) of the general-module CR->VE migration.

-- ─────────────────────────────────────────────────────────────────────────────
-- FORWARD MIGRATION
-- ─────────────────────────────────────────────────────────────────────────────

DROP TABLE IF EXISTS general_schema.tenant_hacienda_config;

DROP TABLE IF EXISTS general_schema.branch_location;


-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK (commented — apply manually to undo)
-- ─────────────────────────────────────────────────────────────────────────────
-- CREATE TABLE general_schema.branch_location (
--     branch_location_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
--     branch_id UUID NOT NULL UNIQUE REFERENCES general_schema.branch(branch_id) ON DELETE CASCADE,
--     provincia  VARCHAR(1)  NOT NULL DEFAULT '1',
--     canton     VARCHAR(2)  NOT NULL DEFAULT '01',
--     distrito   VARCHAR(2)  NOT NULL DEFAULT '01',
--     otras_senas TEXT       NOT NULL DEFAULT '',
--     created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
--     updated_at TIMESTAMP          DEFAULT CURRENT_TIMESTAMP
-- );
-- CREATE INDEX idx_branch_location_branch_id ON general_schema.branch_location(branch_id);
--
-- CREATE TABLE general_schema.tenant_hacienda_config (
--     tenant_hacienda_config_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
--     tenant_id UUID NOT NULL UNIQUE REFERENCES general_schema.tenant(tenant_id) ON DELETE CASCADE,
--     hacienda_username TEXT NOT NULL,
--     hacienda_password TEXT NOT NULL,
--     hacienda_client_id VARCHAR(20) NOT NULL DEFAULT 'api-prod',
--     p12_base64 TEXT NOT NULL,
--     p12_password TEXT NOT NULL,
--     is_active BOOLEAN NOT NULL DEFAULT TRUE,
--     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
--     updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
-- );
-- CREATE INDEX idx_tenant_hacienda_config_tenant ON general_schema.tenant_hacienda_config(tenant_id);
