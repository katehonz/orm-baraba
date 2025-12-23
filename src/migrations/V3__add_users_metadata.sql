-- V3__add_users_metadata.sql
-- Add JSONB metadata column to users table

ALTER TABLE users ADD COLUMN metadata JSONB DEFAULT '{}';

-- Create GIN index for fast JSONB queries
CREATE INDEX idx_users_metadata ON users USING GIN (metadata);

-- Example: Add settings JSONB column
ALTER TABLE users ADD COLUMN settings JSONB DEFAULT '{"theme": "light", "notifications": true}';
