#!/usr/bin/env bash

# shellcheck source=/usr/local/bin/script-utils.sh
# shellcheck disable=SC1091
source /usr/local/bin/script-utils.sh

# Enable error handling
trap handle_error ERR

# Global variables
DB_LOCATION=${DB_LOCATION:-"${IGNITION_INSTALL_LOCATION}/data/db/config.idb"}

###############################################################################
# Main function to process and add database connections
###############################################################################
main() {
	if [ -z "${GATEWAY_ENCODING_KEY:-}" ]; then
		log_error "GATEWAY_ENCODING_KEY is not set"
		exit 1
	fi
	process_connection_files
}

###############################################################################
# Process all JSON files in the /init-db-connections directory
###############################################################################
process_connection_files() {
	local json_file
	for json_file in /init-db-connections/*.json; do
		if [ -f "$json_file" ]; then
			if update_or_add_database_connection "$json_file"; then
				log_info "Successfully processed database connection from $json_file"
			else
				log_error "Failed to process database connection from $json_file"
			fi
		fi
	done
}

###############################################################################
# Encode password using GATEWAY_ENCODING_KEY
###############################################################################
encode_password() {
	local password="$1"
	local encoded_password
	encoded_password=$(/usr/local/bin/encode-password.sh -k "$GATEWAY_ENCODING_KEY" -p "$password")
	echo "$encoded_password"
}

###############################################################################
# Get translator ID for a given translator name
###############################################################################
get_translator_id() {
	local translator_name="$1"
	local translator_id
	translator_id=$(sqlite3 "$DB_LOCATION" "SELECT DBTRANSLATORS_ID FROM DBTRANSLATORS WHERE NAME='$translator_name';")
	echo "$translator_id"
}

###############################################################################
# Update or add a database connection from a JSON file
###############################################################################
update_or_add_database_connection() {
	local json_file="$1"
	local json_content
	json_content=$(cat "$json_file")

	local name type description connect_url username password connection_props
	name=$(echo "$json_content" | jq -r '.name')
	type=$(echo "$json_content" | jq -r '.type')
	description=$(echo "$json_content" | jq -r '.description')
	connect_url=$(echo "$json_content" | jq -r '.connect_url')
	username=$(echo "$json_content" | jq -r '.username')
	password=$(echo "$json_content" | jq -r '.password')
	connection_props=$(echo "$json_content" | jq -r '.connection_props // ""')

	# Get translator ID
	local translator_id
	translator_id=$(get_translator_id "$type")
	if [ -z "$translator_id" ]; then
		log_error "Driver '$type' not found"
		return 1
	fi

	# Encode password
	local encoded_password
	encoded_password=$(encode_password "$password")

	# Check if datasource with the same name exists
	local existing_id
	existing_id=$(sqlite3 "$DB_LOCATION" "SELECT DATASOURCES_ID FROM DATASOURCES WHERE NAME='$name'")

	if [ -n "$existing_id" ]; then
		# Update existing datasource
		sqlite3 "$DB_LOCATION" <<EOF
UPDATE DATASOURCES SET
    DESCRIPTION='$description',
    DRIVERID=$translator_id,
    TRANSLATORID=$translator_id,
    CONNECTURL='$connect_url',
    USERNAME='$username',
    PASSWORDE='$encoded_password',
    CONNECTIONPROPS='$connection_props'
WHERE DATASOURCES_ID=$existing_id;
EOF
		log_info "Updated existing datasource: $name"
	else
		# Insert new datasource
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
    $next_datasource_id, '$name', '$description', $translator_id, $translator_id, 'false',
    '$connect_url', '$username', '', '$encoded_password', 'true', '$connection_props',
    '', 'DEFAULT', 0, 8, 8, 0, 5000, 'SELECT 1', 'true',
    'false', 'false', -1, 3, 1800000, '', 'STANDARD', 60000, 10000
);
UPDATE SEQUENCES SET val=$next_datasource_id WHERE name='DATASOURCES_SEQ';
EOF
	fi
}

# Run the main function
main