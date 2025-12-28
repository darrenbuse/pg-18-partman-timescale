-- pg-18-partman-timescale: Enable TimescaleDB and pg_partman extensions
-- This script runs after the database is created

\set ON_ERROR_STOP on

BEGIN;

-- Create partman schema (recommended isolation)
CREATE SCHEMA IF NOT EXISTS partman;

-- Enable TimescaleDB
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;

-- Enable pg_partman in its own schema
CREATE EXTENSION IF NOT EXISTS pg_partman SCHEMA partman;

-- Enable pg_stat_statements for query performance monitoring
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Create roles for partition management (instead of granting to PUBLIC)
DO $$
BEGIN
    -- Role for applications that need to read partition config
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'partman_user') THEN
        CREATE ROLE partman_user NOLOGIN;
    END IF;

    -- Role for DBAs/operators who manage partitions
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'partman_admin') THEN
        CREATE ROLE partman_admin NOLOGIN;
    END IF;
END
$$;

-- Grant read-only access to partman_user
GRANT USAGE ON SCHEMA partman TO partman_user;
GRANT SELECT ON ALL TABLES IN SCHEMA partman TO partman_user;

-- Grant full access to partman_admin
GRANT ALL ON SCHEMA partman TO partman_admin;
GRANT ALL ON ALL TABLES IN SCHEMA partman TO partman_admin;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA partman TO partman_admin;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA partman TO partman_admin;

-- Set default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA partman GRANT SELECT ON TABLES TO partman_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA partman GRANT ALL ON TABLES TO partman_admin;

-- Grant partman_admin to postgres superuser (for BGW operations)
GRANT partman_admin TO postgres;

COMMIT;

-- Usage instructions (as comments):
-- To grant partition management to an application user:
--   GRANT partman_user TO app_user;      -- read-only access
--   GRANT partman_admin TO dba_user;     -- full management access
