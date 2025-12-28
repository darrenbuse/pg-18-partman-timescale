-- Test custom init script
-- This should run AFTER the image's built-in scripts (00- and 01-)

-- Create a test table to verify this script ran
CREATE TABLE IF NOT EXISTS public.init_test (
    id SERIAL PRIMARY KEY,
    script_name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Insert a record to prove this script executed
INSERT INTO public.init_test (script_name) VALUES ('10-custom-setup.sql');

-- Create a test user to verify custom user creation works
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'test_app_user') THEN
        CREATE ROLE test_app_user WITH LOGIN PASSWORD 'test_password';
    END IF;
END
$$;

GRANT CONNECT ON DATABASE postgres TO test_app_user;
