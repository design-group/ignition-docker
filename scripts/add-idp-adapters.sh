#!/usr/bin/env bash

# shellcheck source=/usr/local/bin/script-utils.sh
# shellcheck disable=SC1091
source /usr/local/bin/script-utils.sh

# Enable error handling
trap handle_error ERR

# Global variables
DB_LOCATION=${DB_LOCATION:-"${IGNITION_INSTALL_LOCATION}/data/db/config.idb"}

###############################################################################
# Main function to process and add/update IDP adapters
###############################################################################
main() {
	if [ "$#" -ne 0 ]; then
		usage
		exit 1
	fi

	if [ -d "/init-idp-adapters" ]; then
		for adapter_file in /init-idp-adapters/*.json; do
			if [ -f "$adapter_file" ]; then
				update_or_add_idp_adapter "$adapter_file"
			fi
		done
	fi
}

###############################################################################
# Update or add an IDP adapter from a JSON file
###############################################################################
update_or_add_idp_adapter() {
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

	# Check if an adapter with this name already exists
	local existing_id
	existing_id=$(sqlite3 "$DB_LOCATION" "SELECT IDP_ADAPTERS_ID FROM IDP_ADAPTERS WHERE JSON_EXTRACT(CONFIG, '$.name') = '$adapter_name'")

	if [ -n "$existing_id" ]; then
		# Update existing adapter
		if sqlite3 "$DB_LOCATION" "UPDATE IDP_ADAPTERS SET CONFIG = '$json_content' WHERE IDP_ADAPTERS_ID = $existing_id;"; then
			log_info "Successfully updated IDP adapter '$adapter_name' with ID $existing_id"
		else
			log_error "Failed to update IDP adapter '$adapter_name'"
			return 1
		fi
	else
		# Insert new adapter
		local next_id
		next_id=$(sqlite3 "$DB_LOCATION" "SELECT COALESCE(MAX(IDP_ADAPTERS_ID)+1, 1) FROM IDP_ADAPTERS")

		if sqlite3 "$DB_LOCATION" "INSERT INTO IDP_ADAPTERS (IDP_ADAPTERS_ID, CONFIG) VALUES ($next_id, '$json_content');"; then
			log_info "Successfully added new IDP adapter '$adapter_name' with ID $next_id"
		else
			log_error "Failed to add new IDP adapter '$adapter_name'"
			return 1
		fi
	fi
}

###############################################################################
# Print usage information
###############################################################################
usage() {
	echo "Usage: $0"
	echo "Adds or updates IDP adapters from JSON files in the /init-idp-adapters directory"
}

# Run the main function
main "$@"
