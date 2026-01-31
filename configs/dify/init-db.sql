-- Dify Database Initialization
CREATE DATABASE dify;
\c dify;

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "btree_gin";

-- Grant permissions
GRANT ALL PRIVILEGES ON DATABASE dify TO postgres;
