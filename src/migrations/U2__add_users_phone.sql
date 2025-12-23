-- U2__add_users_phone.sql
-- Undo migration: remove phone column
ALTER TABLE users DROP COLUMN IF EXISTS phone;
