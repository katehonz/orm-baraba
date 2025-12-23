-- U3__add_users_metadata.sql
-- Undo: remove JSONB columns from users table

DROP INDEX IF EXISTS idx_users_metadata;
ALTER TABLE users DROP COLUMN IF EXISTS metadata;
ALTER TABLE users DROP COLUMN IF EXISTS settings;
