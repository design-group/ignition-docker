#!/usr/bin/env bash
set -euo pipefail

# Use the DB_LOCATION set by the entrypoint-shim.sh
DB_LOCATION=${DB_LOCATION:-"${IGNITION_INSTALL_LOCATION}/data/db/config.idb"}

for sql_file in /init-sql/*.sql; do
    if [ -f "$sql_file" ]; then
        echo "Executing SQL file: $sql_file"
        sqlite3 "$DB_LOCATION" < "$sql_file"
    fi
done