# pg-18-partman-timescale

PostgreSQL 18 container with TimescaleDB and pg_partman for time-series and partitioned data workloads.

> **Note:** PostgreSQL 18 is currently in development. Consider using PostgreSQL 17 for production workloads until PostgreSQL 18 is officially released.

## Overview

pg-18-partman-timescale provides a ready-to-use PostgreSQL 18 image layered with:

- **TimescaleDB 2.23.0** — Hypertables with automatic time-based chunking, continuous aggregates, and compression for time-series data
- **pg_partman 5.2.4** — Automated partition management for tables that need lifecycle control outside of TimescaleDB's domain
- **pg_stat_statements** — Query performance monitoring and analysis

Use TimescaleDB for sensor readings, metrics, events, and other time-series data. Use pg_partman for audit logs, historical records, or any table that benefits from partition-based retention policies.

## Quick Start

### Using Pre-built Image

```bash
# Pull the multi-arch image (works on x86_64 and ARM64/Apple Silicon)
docker pull ghcr.io/darrenbuse/pg-18-partman-timescale:latest

docker run -d \
  --name pg-18-partman-timescale \
  -e POSTGRES_PASSWORD=changeme \
  -p 5432:5432 \
  ghcr.io/darrenbuse/pg-18-partman-timescale:latest
```

### Building Locally

```bash
docker build -t pg-18-partman-timescale .

docker run -d \
  --name pg-18-partman-timescale \
  -e POSTGRES_PASSWORD=changeme \
  -p 5432:5432 \
  pg-18-partman-timescale
```

Connect and verify:

```bash
docker exec -it pg-18-partman-timescale psql -U postgres -c "\dx"
```

You should see `timescaledb`, `pg_partman`, and `pg_stat_statements` listed.

## Usage

### TimescaleDB Hypertable

```sql
-- Create a standard table
CREATE TABLE sensor_readings (
  time        TIMESTAMPTZ NOT NULL,
  sensor_id   TEXT NOT NULL,
  temperature DOUBLE PRECISION,
  humidity    DOUBLE PRECISION
);

-- Convert to hypertable (automatic time-based partitioning)
SELECT create_hypertable('sensor_readings', by_range('time'));

-- Enable compression for older chunks
ALTER TABLE sensor_readings SET (
  timescaledb.compress,
  timescaledb.compress_segmentby = 'sensor_id'
);

SELECT add_compression_policy('sensor_readings', INTERVAL '7 days');

-- Optional: Add retention policy to drop chunks older than 90 days
SELECT add_retention_policy('sensor_readings', INTERVAL '90 days');
```

### pg_partman Managed Table

```sql
-- Create a partitioned table
CREATE TABLE audit_log (
  id         BIGINT GENERATED ALWAYS AS IDENTITY,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  action     TEXT NOT NULL,
  payload    JSONB
) PARTITION BY RANGE (created_at);

-- Register with pg_partman for automated management
SELECT partman.create_parent(
  p_parent_table := 'public.audit_log',
  p_control := 'created_at',
  p_interval := 'daily',
  p_premake := 7
);

-- Set retention policy (drop partitions older than 90 days)
UPDATE partman.part_config
SET retention = '90 days',
    retention_keep_table = false
WHERE parent_table = 'public.audit_log';
```

The pg_partman background worker runs hourly by default to create new partitions and enforce retention.

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_PASSWORD` | (required) | Superuser password |
| `POSTGRES_USER` | `postgres` | Superuser name |
| `POSTGRES_DB` | `postgres` | Default database |

### Custom Configuration

Mount configuration files to `/etc/postgresql/conf.d/`:

```bash
docker run -d \
  --name pg-18-partman-timescale \
  -e POSTGRES_PASSWORD=changeme \
  -v ./my-config.conf:/etc/postgresql/conf.d/my-config.conf:ro \
  -v pgdata:/var/lib/postgresql/data \
  -p 5432:5432 \
  pg-18-partman-timescale
```

See `conf.d/example.conf` for available options.

### pg_partman Background Worker

The background worker is configured via `postgresql.conf`:

```
pg_partman_bgw.interval = 3600    # seconds between runs
pg_partman_bgw.role = 'postgres'  # role to run maintenance as
pg_partman_bgw.dbname = 'postgres' # database(s) to maintain
```

For multiple databases, comma-separate them:

```
pg_partman_bgw.dbname = 'app_db,analytics_db'
```

## Production Considerations

### Data Persistence

Always mount a volume for data:

```bash
docker run -d \
  --name pg-18-partman-timescale \
  -e POSTGRES_PASSWORD=changeme \
  -v pgdata:/var/lib/postgresql/data \
  -p 5432:5432 \
  pg-18-partman-timescale
```

### Memory Tuning

Adjust shared_buffers and other memory settings based on available RAM. A reasonable starting point:

| Available RAM | shared_buffers | effective_cache_size | work_mem |
|---------------|----------------|----------------------|----------|
| 4 GB          | 1 GB           | 3 GB                 | 32 MB    |
| 8 GB          | 2 GB           | 6 GB                 | 64 MB    |
| 16 GB         | 4 GB           | 12 GB                | 128 MB   |

### Backups

Use `pg_dump` or `pg_basebackup` as normal. For TimescaleDB-specific considerations, see the [TimescaleDB backup documentation](https://docs.timescale.com/self-hosted/latest/backup-and-restore/).

```bash
# Logical backup
docker exec pg-18-partman-timescale pg_dump -U postgres -Fc mydb > backup.dump

# Restore (create database first if it doesn't exist)
docker exec pg-18-partman-timescale createdb -U postgres mydb
docker exec -i pg-18-partman-timescale pg_restore -U postgres -d mydb < backup.dump
```

### High Availability

This image is suitable for single-node deployments. For HA setups, consider:

- PostgreSQL streaming replication with a standby
- Patroni for automated failover
- TimescaleDB's multi-node capabilities (if applicable to your workload)

### Monitoring

The container includes a health check. For deeper monitoring:

- Use `pg_stat_statements` for query analysis
- TimescaleDB provides `timescaledb_information` views for chunk and compression stats
- pg_partman logs maintenance activity to the PostgreSQL log

```sql
-- Check TimescaleDB chunk info
SELECT * FROM timescaledb_information.chunks;

-- Check pg_partman configuration
SELECT * FROM partman.part_config;

-- Query performance analysis
SELECT query, calls, mean_exec_time, total_exec_time
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

### Security

This image creates two roles for partition management:

- `partman_user` — Read-only access to partition configuration
- `partman_admin` — Full partition management privileges

```sql
-- Connect to your application database
\c mydb

-- Create an application role with minimal privileges
CREATE ROLE app_user WITH LOGIN PASSWORD 'secure_password';
GRANT CONNECT ON DATABASE mydb TO app_user;
GRANT USAGE ON SCHEMA public TO app_user;
GRANT SELECT, INSERT ON sensor_readings TO app_user;

-- Grant partition read access if needed
GRANT partman_user TO app_user;

-- Grant partition admin access to DBAs
GRANT partman_admin TO dba_user;
```

Additional security recommendations:

- Change the default password immediately
- Consider network-level isolation (don't expose 5432 publicly)
- Use SSL for connections in production

## Docker Compose Example

```yaml
services:
  db:
    build: .
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: myapp
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./conf.d/custom.conf:/etc/postgresql/conf.d/custom.conf:ro
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

volumes:
  pgdata:
```

## Troubleshooting

### Extensions not loading

Check that shared_preload_libraries is configured correctly:

```sql
SHOW shared_preload_libraries;
-- Should show: timescaledb,pg_partman_bgw,pg_stat_statements
```

### pg_partman not creating partitions

Verify the background worker is running:

```sql
SELECT * FROM pg_stat_activity WHERE backend_type = 'pg_partman maintenance worker';
```

Check pg_partman configuration:

```sql
SELECT parent_table, partition_interval, premake, retention
FROM partman.part_config;
```

### TimescaleDB compression not working

Ensure the compression policy is set and check job status:

```sql
SELECT * FROM timescaledb_information.jobs
WHERE proc_name = 'policy_compression';
```

## CI/CD

This repository includes a GitHub Action that automatically builds and publishes multi-architecture images:

- **Platforms:** linux/amd64 (x86_64), linux/arm64 (Apple Silicon, AWS Graviton)
- **Registry:** GitHub Container Registry (ghcr.io)
- **Security:** Trivy vulnerability scanning with results in GitHub Security tab
- **Triggers:** Push to main, version tags (v*), pull requests

### Version Tags

| Tag | Description |
|-----|-------------|
| `latest` | Latest build from main branch |
| `v1.0.0` | Specific version release |
| `v1.0` | Latest patch of v1.0.x |
| `v1` | Latest minor of v1.x.x |
| `sha-abc123` | Specific commit build |

## Versions

- PostgreSQL: 18 (bookworm)
- TimescaleDB: 2.23.0
- pg_partman: 5.2.4

## License

This Dockerfile and associated scripts are provided as-is. PostgreSQL, TimescaleDB, and pg_partman are subject to their respective licenses.
