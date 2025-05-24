#!/usr/bin/env bash

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging functions
log_info() {
    echo "idb-config | $(date +"%Y/%m/%d %H:%M:%S") | $*"
}

log_warning() {
    echo "idb-config | $(date +"%Y/%m/%d %H:%M:%S") | WARNING: $*" >&2
}

log_error() {
    echo "idb-config | $(date +"%Y/%m/%d %H:%M:%S") | ERROR: $*" >&2
}

# Error handling
handle_error() {
    local exit_code=$?
    log_error "An error occurred in ${BASH_SOURCE[1]} at line ${BASH_LINENO[0]}. Exit code: $exit_code"
}

# Version comparison function
version_gte() {
    local version=$1
    local required=$2
    if [[ "$(printf '%s\n' "$required" "$version" | sort -V | head -n1)" = "$required" ]]; then
        return 0
    else
        return 1
    fi
}

# Encoding utilities
encode_password() {
    local password="$1"
    local encoded_password
    encoded_password=$(/usr/local/bin/encode-password.sh -k "$GATEWAY_ENCODING_KEY" -p "$password")
    echo "$encoded_password"
}

generate_salted_hash() {
    local password="$1"
    local auth_salt
    auth_salt=$(od -An -v -t x1 -N 4 /dev/random | tr -d ' ')
    local auth_pwsalthash
    auth_pwsalthash=$(printf %s "${password}${auth_salt}" | sha256sum - | cut -c -64)
    echo "[${auth_salt}]${auth_pwsalthash}"
}

###############################################################################
# Get the next available ID for a table
###############################################################################
get_next_id() {
    local table_name="$1"
    local id_column="$2"
    local next_id
    next_id=$(sqlite3 "$DB_LOCATION" "SELECT COALESCE(MAX($id_column), 0) + 1 FROM $table_name;")
    
    # Ensure the ID is unique
    while [[ $(sqlite3 "$DB_LOCATION" "SELECT COUNT(*) FROM $table_name WHERE $id_column = $next_id;") -ne 0 ]]; do
        next_id=$((next_id + 1))
    done
    
    echo "$next_id"
}

# Argument parsing
parse_args() {
    while getopts ":h$1" opt; do
        case ${opt} in
            h )
                usage
                return 0
                ;;
            \? )
                log_error "Invalid option: $OPTARG"
                usage
                return 1
                ;;
            : )
                log_error "Invalid option: $OPTARG requires an argument"
                usage
                return 1
                ;;
        esac
    done
    shift $((OPTIND -1))
}

# Usage function (to be overridden in individual scripts)
usage() {
    echo "Usage: $0 [-h]"
    echo "  -h  Show this help message"
}

# Permissions conversion
convert_permissions_to_json() {
    local permissions="$1"
    local type="AnyOf" # Default type

    if [ -z "$permissions" ]; then
        echo '{"type":"AnyOf","securityLevels":[]}'
        return
    fi

    # Check if the permissions string starts with AnyOf or AllOf
    if [[ "$permissions" == AnyOf,* ]]; then
        type="AnyOf"
        permissions="${permissions#AnyOf,}"
    elif [[ "$permissions" == AllOf,* ]]; then
        type="AllOf"
        permissions="${permissions#AllOf,}"
    fi

    local IFS=','
    read -ra permission_array <<<"$permissions"
    local json="{\"type\":\"$type\",\"securityLevels\":["
    local first=true

    for permission in "${permission_array[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            json="${json},"
        fi

        local IFS='/'
        read -ra levels <<<"$permission"
        local current_json='{'
        for ((i = 0; i < ${#levels[@]}; i++)); do
            if [ $i -eq $((${#levels[@]} - 1)) ]; then
                current_json="${current_json}\"name\":\"${levels[i]}\",\"children\":[]"
            else
                current_json="${current_json}\"name\":\"${levels[i]}\",\"children\":[{"
            fi
        done
        for ((i = 0; i < ${#levels[@]} - 1; i++)); do
            current_json="${current_json}}]"
        done
        json="${json}${current_json}}"
    done

    json="${json}]}"
    echo "$json"
}

# Export functions and variables
export -f log_info log_warning log_error handle_error encode_password generate_salted_hash get_next_id parse_args usage convert_permissions_to_json version_gte
export SCRIPT_DIR