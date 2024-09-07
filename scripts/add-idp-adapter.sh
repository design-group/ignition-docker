#!/usr/bin/env bash
set -euo pipefail

DB_LOCATION=${DB_LOCATION:-"${IGNITION_INSTALL_LOCATION}/data/db/config.idb"}

add_idp_adapter() {
	local json_file="$1"

	if [ ! -f "$json_file" ]; then
		echo "IDP adapter file not found: $json_file"
		return 1
	fi

	# Read the JSON content
	local json_content
	json_content=$(tr -d '\n' <"$json_file" | tr -s ' ')

	# Extract the name from the JSON (assuming it's in a "name" field)
	local adapter_name
	adapter_name=$(echo "$json_content" | jq -r '.name // "Unknown"')

	# Get the next available ID
	local next_id
	next_id=$(sqlite3 "$DB_LOCATION" "SELECT COALESCE(MAX(IDP_ADAPTERS_ID)+1, 1) FROM IDP_ADAPTERS")

	# Insert into the database
	sqlite3 "$DB_LOCATION" <<EOF
INSERT INTO IDP_ADAPTERS (IDP_ADAPTERS_ID, CONFIG)
VALUES ($next_id, '$json_content');
EOF
	echo "Added IDP adapter: $adapter_name with ID: $next_id"
}

# Check if a file path is provided
if [ "$#" -ne 1 ]; then
	echo "Usage: $0 <path_to_json_file>"
	exit 1
fi

add_idp_adapter "$1"
