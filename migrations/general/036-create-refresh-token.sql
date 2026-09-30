-- ============================================================
-- Migration: 036-create-refresh-token
-- Schema: general
-- Date: 2026-09-29
-- Author: Claude (session work)
--
-- Why: auth robusto -- login solo emitia un JWT de larga duracion sin forma
-- de revocarlo (logout solo borraba la cookie, el token seguia siendo
-- valido hasta expirar). Esta tabla persiste los refresh tokens emitidos
-- (hasheados, nunca en texto plano) para poder revocarlos individualmente
-- o todos los de un usuario (logout, deteccion de reuso, desactivacion de
-- cuenta), y para soportar rotacion en cada refresh.
-- ============================================================

CREATE TABLE IF NOT EXISTS general_schema.refresh_token(
    refresh_token_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          uuid NOT NULL REFERENCES general_schema.users(user_id) ON DELETE CASCADE,
    token_hash       VARCHAR(255) NOT NULL,
    expires_at       TIMESTAMP NOT NULL,
    revoked          BOOLEAN NOT NULL DEFAULT false,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_refresh_token_user_id ON general_schema.refresh_token(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_token_revoked ON general_schema.refresh_token(revoked);

-- ============================================================
-- Rollback (documentacion, no se ejecuta automaticamente):
--
-- DROP INDEX IF EXISTS general_schema.idx_refresh_token_revoked;
-- DROP INDEX IF EXISTS general_schema.idx_refresh_token_user_id;
-- DROP TABLE IF EXISTS general_schema.refresh_token;
-- ============================================================
