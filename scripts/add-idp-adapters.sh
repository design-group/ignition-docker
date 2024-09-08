#!/usr/bin/env bash

# shellcheck source=/usr/local/bin/script-utils.sh
# shellcheck disable=SC1091
source /usr/local/bin/script-utils.sh

# Enable error handling
trap handle_error ERR

# Global variables
DB_LOCATION=${DB_LOCATION:-"${IGNITION_INSTALL_LOCATION}/data/db/config.idb"}

###############################################################################
# Main function to process and add IDP adapters
###############################################################################
main() {
	if [ "$#" -ne 0 ]; then
		usage
		exit 1
	fi

	if [ -d "/init-idp-adapters" ]; then	
        for adapter_file in /init-idp-adapters/*.json; do
            if [ -f "$adapter_file" ]; then
                add_idp_adapter "$adapter_file"
            fi
        done
    fi	
}

###############################################################################
# Add an IDP adapter from a JSON file
###############################################################################
add_idp_adapter() {
	local json_file="$1"

	if [ ! -f "$json_file" ]; then
		log_error "IDP adapter file not found: $json_file"
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
	if sqlite3 "$DB_LOCATION" "INSERT INTO IDP_ADAPTERS (IDP_ADAPTERS_ID, CONFIG) VALUES ($next_id, '$json_content');"; then
		log_info "Successfully added IDP adapter '$adapter_name' with ID $next_id"
	else
		log_error "Failed to add IDP adapter '$adapter_name'"
		return 1
	fi
}

###############################################################################
# Print usage information
###############################################################################
usage() {
	echo "Usage: $0"
	echo "Adds an IDP adapter from the specified JSON file"
}

# Run the main function
main "$@"
