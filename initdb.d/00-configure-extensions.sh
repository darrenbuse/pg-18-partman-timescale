#!/bin/bash
set -e

# Configure extension settings for TimescaleDB and pg_partman BGW
# Note: shared_preload_libraries is set via CMD in Dockerfile (must be at server start)

# Write static configuration (using quoted heredoc to prevent expansion)
cat >> "${PGDATA}/postgresql.conf" <<'STATIC_EOF'

# pg-18-partman-timescale configuration
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
