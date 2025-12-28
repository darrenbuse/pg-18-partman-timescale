# pg-18-partman-timescale
# PostgreSQL 18 with TimescaleDB and pg_partman for time-series and partitioned data workloads

FROM postgres:18-bookworm

LABEL maintainer="Darren"
LABEL description="PostgreSQL 18 with TimescaleDB and pg_partman"
LABEL version="1.0.0"
LABEL org.opencontainers.image.title="pg-18-partman-timescale"
LABEL org.opencontainers.image.description="PostgreSQL 18 with TimescaleDB and pg_partman for time-series and partitioned data"

# Build arguments for version pinning
ARG TIMESCALEDB_VERSION=2.23.0
ARG PARTMAN_VERSION=5.2.4

# Environment variables
ENV TIMESCALEDB_TELEMETRY=off

# Install TimescaleDB and build pg_partman in a single layer to minimize image size
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        make \
        gcc \
        libpq-dev \
        postgresql-server-dev-18 \
        git \
    # Add TimescaleDB repository
    && curl -fsSL https://packagecloud.io/timescale/timescaledb/gpgkey | gpg --dearmor -o /usr/share/keyrings/timescaledb.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/timescaledb.gpg] https://packagecloud.io/timescale/timescaledb/debian/ $(lsb_release -cs) main" > /etc/apt/sources.list.d/timescaledb.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        timescaledb-2-postgresql-18=${TIMESCALEDB_VERSION}~debian12 \
    # Build and install pg_partman from source
    && git clone --branch v${PARTMAN_VERSION} --depth 1 https://github.com/pgpartman/pg_partman.git /tmp/pg_partman \
    && cd /tmp/pg_partman \
    && make \
    && make install \
    # Clean up build dependencies and caches
    && apt-get purge -y --auto-remove \
        make \
        gcc \
        libpq-dev \
        postgresql-server-dev-18 \
        git \
        curl \
        gnupg \
    && rm -rf /tmp/pg_partman /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create configuration directory
RUN mkdir -p /etc/postgresql/conf.d

# Copy initialization scripts with proper permissions
COPY --chmod=755 ./initdb.d/*.sh /docker-entrypoint-initdb.d/
COPY ./initdb.d/*.sql /docker-entrypoint-initdb.d/

# Copy custom PostgreSQL configuration
COPY ./conf.d/ /etc/postgresql/conf.d/

# Expose PostgreSQL port
EXPOSE 5432

# Use SIGINT for fast shutdown (PostgreSQL handles this gracefully)
STOPSIGNAL SIGINT

# Health check with proper shell expansion
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD ["sh", "-c", "pg_isready -U \"${POSTGRES_USER:-postgres}\" -d \"${POSTGRES_DB:-postgres}\" -h localhost"]
