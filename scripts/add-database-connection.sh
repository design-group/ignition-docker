#!/usr/bin/env bash
set -euo pipefail

DB_LOCATION=${DB_LOCATION:-"${IGNITION_INSTALL_LOCATION}/data/db/config.idb"}

if [ -z "${GATEWAY_ENCODING_KEY:-}" ]; then
    echo "Error: GATEWAY_ENCODING_KEY is not set"
    exit 1
fi

encode_password() {
    local password="$1"
    local encoded_password
    encoded_password=$(/usr/local/bin/encode-password.sh -k "$GATEWAY_ENCODING_KEY" -p "$password")
    if ! add_database_connection "$@"; then
        echo "Error: Failed to encode password. Error was: $encoded_password" >&2
        return 1
    fi
    echo "$encoded_password"
}

get_translator_id() {
    local translator_name="$1"
    local translator_id
    translator_id=$(sqlite3 "$DB_LOCATION" "SELECT DBTRANSLATORS_ID FROM DBTRANSLATORS WHERE NAME='$translator_name';")
    echo "$translator_id"
}

add_database_connection() {
    local name="$1"
    local type="$2"
    local description="$3"
    local connect_url="$4"
    local username="$5"
    local password="$6"
    local connection_props="${7:-}"

    # Get translator ID
    local translator_id
	translator_id=$(get_translator_id "$type")
    if [ -z "$translator_id" ]; then
        echo "Error: Driver '$type' not found" >&2
        return 1
    fi

    # Default values
    local driver_id="$translator_id"
    local include_schema_in_table_name="false"
    local enabled="true"
    local connection_reset_params=""
    local default_transaction_level="DEFAULT"
    local pool_init_size=0
    local pool_max_active=8
    local pool_max_idle=8
    local pool_min_idle=0
    local pool_max_wait=5000
    local validation_query="SELECT 1"
    local test_on_borrow="true"
    local test_on_return="false"
    local test_while_idle="false"
    local eviction_rate=-1
    local eviction_tests=3
    local eviction_time=1800000
    local failover_profile_id=""
    local failover_mode="STANDARD"
    local slow_query_log_threshold=60000
    local validation_sleep_time=10000

    local encoded_password
    if ! encoded_password=$(encode_password "$password"); then
        echo "Failed to add database connection due to password encoding error." >&2
        return 1
    fi

    local next_datasource_id
	next_datasource_id=$(sqlite3 "$DB_LOCATION" "SELECT COALESCE(MAX(DATASOURCES_ID)+1, 1) FROM DATASOURCES")	
	
    sqlite3 "$DB_LOCATION" <<EOF
INSERT INTO DATASOURCES (
    DATASOURCES_ID, NAME, DESCRIPTION, DRIVERID, TRANSLATORID, INCLUDESCHEMAINTABLENAME,
    CONNECTURL, USERNAME, PASSWORD, PASSWORDE, ENABLED, CONNECTIONPROPS,
    CONNECTIONRESETPARAMS, DEFAULTTRANSACTIONLEVEL, POOLINITSIZE, POOLMAXACTIVE,
    POOLMAXIDLE, POOLMINIDLE, POOLMAXWAIT, VALIDATIONQUERY, TESTONBORROW,
    TESTONRETURN, TESTWHILEIDLE, EVICTIONRATE, EVICTIONTESTS, EVICTIONTIME,
    FAILOVERPROFILEID, FAILOVERMODE, SLOWQUERYLOGTHRESHOLD, VALIDATIONSLEEPTIME
) VALUES (
    $next_datasource_id, '$name', '$description', $driver_id, $translator_id, '$include_schema_in_table_name',
    '$connect_url', '$username', '', '$encoded_password', '$enabled', '$connection_props',
    '$connection_reset_params', '$default_transaction_level', $pool_init_size, $pool_max_active,
    $pool_max_idle, $pool_min_idle, $pool_max_wait, '$validation_query', '$test_on_borrow',
    '$test_on_return', '$test_while_idle', $eviction_rate, $eviction_tests, $eviction_time,
    '$failover_profile_id', '$failover_mode', $slow_query_log_threshold, $validation_sleep_time
);
UPDATE SEQUENCES SET val=$next_datasource_id WHERE name='DATASOURCES_SEQ';
EOF

    echo "Database connection '$name' added successfully."
}

# Usage
if [ "$#" -lt 6 ]; then
    echo "Usage: $0 <name> <type> <description> <connect_url> <username> <password> <connection_props>"
    exit 1
fi

add_database_connection "$@"