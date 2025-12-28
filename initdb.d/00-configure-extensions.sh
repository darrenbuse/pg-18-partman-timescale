#!/bin/bash
set -e

# Configure shared_preload_libraries for TimescaleDB and pg_partman BGW
# This runs before PostgreSQL starts for the first time

# Write static configuration (using quoted heredoc to prevent expansion)
cat >> "${PGDATA}/postgresql.conf" <<'STATIC_EOF'

# pg-18-partman-timescale configuration
# Extensions requiring shared_preload_libraries
shared_preload_libraries = 'timescaledb,pg_partman_bgw,pg_stat_statements'

# TimescaleDB settings
timescaledb.telemetry_level = off

# pg_partman background worker settings
pg_partman_bgw.interval = 3600

# Include additional configuration files
include_dir = '/etc/postgresql/conf.d'
STATIC_EOF

# Append dynamic configuration with proper variable expansion
# These use the environment variables set at container runtime
echo "pg_partman_bgw.role = '${POSTGRES_USER:-postgres}'" >> "${PGDATA}/postgresql.conf"
echo "pg_partman_bgw.dbname = '${POSTGRES_DB:-postgres}'" >> "${PGDATA}/postgresql.conf"
