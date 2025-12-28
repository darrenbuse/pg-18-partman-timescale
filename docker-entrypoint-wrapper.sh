#!/bin/bash
set -e

# pg-18-partman-timescale entrypoint wrapper
# Merges image init scripts with user-provided scripts

IMAGE_INIT_DIR="/opt/pg-init"
ENTRYPOINT_INITDB="/docker-entrypoint-initdb.d"

# Only merge scripts if this is a fresh database initialization
# (i.e., PGDATA is empty or doesn't exist)
if [ -z "$(ls -A "$PGDATA" 2>/dev/null)" ]; then
    # Ensure the target directory exists
    mkdir -p "$ENTRYPOINT_INITDB"

    # Copy image init scripts with prefixes that run first (00-, 01-)
    # User scripts should use higher prefixes (10-, 20-, etc.) to run after
    if [ -d "$IMAGE_INIT_DIR" ]; then
        for script in "$IMAGE_INIT_DIR"/*; do
            if [ -f "$script" ]; then
                scriptname=$(basename "$script")
                # Only copy if not already present (don't override user's versions)
                if [ ! -f "$ENTRYPOINT_INITDB/$scriptname" ]; then
                    cp "$script" "$ENTRYPOINT_INITDB/$scriptname"
                    # Ensure shell scripts are executable
                    if [[ "$scriptname" == *.sh ]]; then
                        chmod +x "$ENTRYPOINT_INITDB/$scriptname"
                    fi
                fi
            fi
        done
    fi
fi

# Execute the original postgres entrypoint
exec docker-entrypoint.sh "$@"
