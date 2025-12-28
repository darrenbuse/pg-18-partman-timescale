# pg-18-partman-timescale
# PostgreSQL 18 with TimescaleDB and pg_partman for time-series and partitioned data workloads

FROM postgres:18-bookworm

LABEL maintainer="Darren"
LABEL description="PostgreSQL 18 with TimescaleDB and pg_partman"
LABEL version="1.0.0"
LABEL org.opencontainers.image.title="pg-18-partman-timescale"
LABEL org.opencontainers.image.description="PostgreSQL 18 with TimescaleDB and pg_partman for time-series and partitioned data"

# Environment variables
ENV TIMESCALEDB_TELEMETRY=off

# Install TimescaleDB and pg_partman from packages
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
    # Add TimescaleDB repository
    && curl -fsSL https://packagecloud.io/timescale/timescaledb/gpgkey | gpg --dearmor -o /usr/share/keyrings/timescaledb.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/timescaledb.gpg] https://packagecloud.io/timescale/timescaledb/debian/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/timescaledb.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        timescaledb-2-postgresql-18 \
        postgresql-18-partman \
    # Clean up
    && apt-get purge -y --auto-remove \
        curl \
        gnupg \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create directories
RUN mkdir -p /etc/postgresql/conf.d /opt/pg-init

# Copy image init scripts to protected location (merged at runtime)
# Users can mount their own scripts to /docker-entrypoint-initdb.d/
COPY ./initdb.d/*.sh /opt/pg-init/
COPY ./initdb.d/*.sql /opt/pg-init/

# Copy custom PostgreSQL configuration
COPY ./conf.d/ /etc/postgresql/conf.d/

# Copy entrypoint wrapper that merges image scripts with user scripts
COPY docker-entrypoint-wrapper.sh /usr/local/bin/

# Set permissions (separated from COPY for legacy Docker compatibility)
RUN chmod +x /opt/pg-init/*.sh /usr/local/bin/docker-entrypoint-wrapper.sh \
    && chmod 644 /etc/postgresql/conf.d/*.conf 2>/dev/null || true

# Expose PostgreSQL port
EXPOSE 5432

# Use SIGINT for fast shutdown (PostgreSQL handles this gracefully)
STOPSIGNAL SIGINT

# Health check with proper shell expansion
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD ["sh", "-c", "pg_isready -U \"${POSTGRES_USER:-postgres}\" -d \"${POSTGRES_DB:-postgres}\" -h localhost"]

# Use wrapper entrypoint that merges init scripts
ENTRYPOINT ["docker-entrypoint-wrapper.sh"]
# Preload libraries via CMD (must be loaded at server start, not via init scripts)
CMD ["postgres", "-c", "shared_preload_libraries=timescaledb,pg_partman_bgw,pg_stat_statements"]
