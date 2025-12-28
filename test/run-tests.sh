#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

CONTAINER_NAME="pg-18-partman-timescale-test"
IMAGE_NAME="pg-18-partman-timescale:test"
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$TEST_DIR")"

echo -e "${YELLOW}=== pg-18-partman-timescale Test Suite ===${NC}"

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT

# Build the image
echo -e "\n${YELLOW}Building image...${NC}"
docker build -t "$IMAGE_NAME" "$PROJECT_DIR"

# Run container with custom init scripts mounted
echo -e "\n${YELLOW}Starting container with custom init scripts...${NC}"
docker run -d \
    --name "$CONTAINER_NAME" \
    -e POSTGRES_PASSWORD=testpassword \
    -v "$TEST_DIR/init-scripts:/docker-entrypoint-initdb.d" \
    "$IMAGE_NAME"

# Wait for PostgreSQL to be ready
echo -e "\n${YELLOW}Waiting for PostgreSQL to be ready...${NC}"
for i in {1..30}; do
    if docker exec "$CONTAINER_NAME" pg_isready -U postgres > /dev/null 2>&1; then
        echo -e "${GREEN}PostgreSQL is ready!${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}Timeout waiting for PostgreSQL${NC}"
        docker logs "$CONTAINER_NAME"
        exit 1
    fi
    sleep 2
done

# Give it a moment for init scripts to complete
sleep 3

# Run tests
TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local name="$1"
    local query="$2"
    local expected="$3"

    result=$(docker exec "$CONTAINER_NAME" psql -U postgres -tAc "$query" 2>/dev/null || echo "ERROR")

    if [[ "$result" == *"$expected"* ]]; then
        echo -e "  ${GREEN}✓${NC} $name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${RED}✗${NC} $name (expected: $expected, got: $result)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

run_sql() {
    docker exec "$CONTAINER_NAME" psql -U postgres -c "$1" > /dev/null 2>&1 || true
}

echo -e "\n${YELLOW}=== Extension Installation Tests ===${NC}"

# Test 1: TimescaleDB extension exists
run_test "TimescaleDB extension installed" \
    "SELECT extname FROM pg_extension WHERE extname = 'timescaledb';" \
    "timescaledb"

# Test 2: pg_partman extension exists
run_test "pg_partman extension installed" \
    "SELECT extname FROM pg_extension WHERE extname = 'pg_partman';" \
    "pg_partman"

# Test 3: pg_stat_statements extension exists
run_test "pg_stat_statements extension installed" \
    "SELECT extname FROM pg_extension WHERE extname = 'pg_stat_statements';" \
    "pg_stat_statements"

# Test 4: partman schema exists
run_test "partman schema exists" \
    "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'partman';" \
    "partman"

# Test 5: partman_user role exists
run_test "partman_user role exists" \
    "SELECT rolname FROM pg_roles WHERE rolname = 'partman_user';" \
    "partman_user"

# Test 6: partman_admin role exists
run_test "partman_admin role exists" \
    "SELECT rolname FROM pg_roles WHERE rolname = 'partman_admin';" \
    "partman_admin"

# Test 7: shared_preload_libraries configured correctly
run_test "shared_preload_libraries configured" \
    "SHOW shared_preload_libraries;" \
    "timescaledb"

echo -e "\n${YELLOW}=== Custom Init Script Tests ===${NC}"

# Test 8: Custom init script ran (init_test table exists)
run_test "Custom init script created table" \
    "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'init_test');" \
    "t"

# Test 9: Custom init script inserted data
run_test "Custom init script inserted data" \
    "SELECT script_name FROM public.init_test LIMIT 1;" \
    "10-custom-setup.sql"

# Test 10: Custom user was created
run_test "Custom user created by init script" \
    "SELECT rolname FROM pg_roles WHERE rolname = 'test_app_user';" \
    "test_app_user"

echo -e "\n${YELLOW}=== TimescaleDB Functional Tests ===${NC}"

# Create a test hypertable
echo -e "  Creating TimescaleDB hypertable..."
run_sql "CREATE TABLE IF NOT EXISTS sensor_data (
    time TIMESTAMPTZ NOT NULL,
    sensor_id TEXT NOT NULL,
    temperature DOUBLE PRECISION
);"
run_sql "SELECT create_hypertable('sensor_data', by_range('time'), if_not_exists => TRUE);"

# Test 11: Hypertable was created
run_test "TimescaleDB hypertable created" \
    "SELECT hypertable_name FROM timescaledb_information.hypertables WHERE hypertable_name = 'sensor_data';" \
    "sensor_data"

# Insert test data
run_sql "INSERT INTO sensor_data (time, sensor_id, temperature) VALUES
    (now() - interval '1 hour', 'sensor-1', 22.5),
    (now(), 'sensor-1', 23.0);"

# Test 12: Data inserted into hypertable
run_test "TimescaleDB hypertable accepts data" \
    "SELECT COUNT(*) FROM sensor_data;" \
    "2"

# Test 13: Chunks created
run_test "TimescaleDB chunks created" \
    "SELECT COUNT(*) > 0 FROM timescaledb_information.chunks WHERE hypertable_name = 'sensor_data';" \
    "t"

# Test compression setup
run_sql "ALTER TABLE sensor_data SET (timescaledb.compress, timescaledb.compress_segmentby = 'sensor_id');"

# Test 14: Compression enabled
run_test "TimescaleDB compression enabled" \
    "SELECT compression_enabled FROM timescaledb_information.hypertables WHERE hypertable_name = 'sensor_data';" \
    "t"

echo -e "\n${YELLOW}=== pg_partman Functional Tests ===${NC}"

# Create a partitioned table
echo -e "  Creating pg_partman managed table..."
run_sql "CREATE TABLE IF NOT EXISTS audit_log (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    action TEXT NOT NULL
) PARTITION BY RANGE (created_at);"

# Register with pg_partman
run_sql "SELECT partman.create_parent(
    p_parent_table := 'public.audit_log',
    p_control := 'created_at',
    p_interval := '1 day',
    p_premake := 3
);"

# Test 15: pg_partman configuration exists
run_test "pg_partman config created" \
    "SELECT parent_table FROM partman.part_config WHERE parent_table = 'public.audit_log';" \
    "public.audit_log"

# Test 16: Partitions were created
run_test "pg_partman created partitions" \
    "SELECT COUNT(*) >= 1 FROM pg_tables WHERE tablename LIKE 'audit_log_p%';" \
    "t"

# Insert test data
run_sql "INSERT INTO audit_log (action) VALUES ('test_action');"

# Test 17: Data inserted into partitioned table
run_test "pg_partman table accepts data" \
    "SELECT COUNT(*) FROM audit_log;" \
    "1"

# Test 18: pg_partman background worker configured
run_test "pg_partman BGW configured" \
    "SHOW pg_partman_bgw.interval;" \
    "3600"

# Print summary
echo -e "\n${YELLOW}=== Test Summary ===${NC}"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "\n${RED}Some tests failed!${NC}"
    echo -e "\n${YELLOW}Container logs:${NC}"
    docker logs "$CONTAINER_NAME" 2>&1 | tail -50
    exit 1
else
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
fi
