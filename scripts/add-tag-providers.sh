#!/usr/bin/env bash

# shellcheck source=/usr/local/bin/script-utils.sh
# shellcheck disable=SC1091
source /usr/local/bin/script-utils.sh

# Enable error handling
trap handle_error ERR

# Global variables
DB_LOCATION=${DB_LOCATION:-"${IGNITION_INSTALL_LOCATION}/data/db/config.idb"}

###############################################################################
# Main function to process and add/update tag providers
###############################################################################
main() {
	process_tag_provider_files
}

###############################################################################
# Process all JSON files in the /tag-providers directory
###############################################################################
process_tag_provider_files() {
	local json_file
	for json_file in /tag-providers/*.json; do
		if [ -f "$json_file" ]; then
			if ! update_or_add_tag_provider "$json_file"; then
				log_error "Failed to process tag provider from $json_file"
			fi
		fi
	done
}

###############################################################################
# Generate a UUID
###############################################################################
generate_uuid() {
	cat /proc/sys/kernel/random/uuid
}

###############################################################################
# Update or add a realtime tag provider
###############################################################################
update_or_add_realtime_provider() {
	local json_content="$1"
	local provider_id="$2"
	local name description enabled type_id allow_backfill enable_tag_reference_store

	name=$(echo "$json_content" | jq -r '.name')
	description=$(echo "$json_content" | jq -r '.description')
	enabled=$(echo "$json_content" | jq -r '.enabled')
	type_id=$(echo "$json_content" | jq -r '.type_id')
	allow_backfill=$(echo "$json_content" | jq -r '.allow_backfill')
	enable_tag_reference_store=$(echo "$json_content" | jq -r '.enable_tag_reference_store')

	# Check if provider already exists
	local existing_id
	existing_id=$(sqlite3 "$DB_LOCATION" "SELECT TAGPROVIDERSETTINGS_ID FROM TAGPROVIDERSETTINGS WHERE NAME='$name' AND TYPEID='$type_id';")

	if [ -n "$existing_id" ]; then
		# Update existing provider
		sqlite3 "$DB_LOCATION" <<EOF
UPDATE TAGPROVIDERSETTINGS SET
    DESCRIPTION='$description', ENABLED=$enabled, ALLOWBACKFILL=$allow_backfill, ENABLETAGREFERENCESTORE=$enable_tag_reference_store
WHERE TAGPROVIDERSETTINGS_ID=$existing_id;
EOF
		log_info "Updated existing realtime tag provider: $name"
	else
		# Insert new provider
		local new_id
		new_id=$(get_next_id "TAGPROVIDERSETTINGS" "TAGPROVIDERSETTINGS_ID")
		sqlite3 "$DB_LOCATION" <<EOF
INSERT INTO TAGPROVIDERSETTINGS (
    TAGPROVIDERSETTINGS_ID, NAME, PROVIDERID, DESCRIPTION, ENABLED, TYPEID, ALLOWBACKFILL, ENABLETAGREFERENCESTORE
) VALUES (
    $new_id, '$name', '$provider_id', '$description', $enabled, '$type_id', $allow_backfill, $enable_tag_reference_store
);
EOF
		log_info "Added new realtime tag provider: $name with ID: $new_id"

		# Insert into INTERNALTAGPROVIDER for Standard Tag Provider
		if [[ "$type_id" == "STANDARD" ]]; then
			local read_permissions write_permissions edit_permissions

			read_permissions=$(convert_permissions_to_json "$(echo "$json_content" | jq -r '.read_permissions')")
			write_permissions=$(convert_permissions_to_json "$(echo "$json_content" | jq -r '.write_permissions')")
			edit_permissions=$(convert_permissions_to_json "$(echo "$json_content" | jq -r '.edit_permissions')")

			sqlite3 "$DB_LOCATION" <<EOF
INSERT INTO INTERNALTAGPROVIDER (
	PROFILEID, DEFAULTDATASOURCEID, VERSIONID, VERSIONREVISION, READPERMISSIONS, READONLY, WRITEPERMISSIONS, EDITPERMISSIONS
) VALUES (
	$new_id, '', '', '', '$read_permissions', false, '$write_permissions', '$edit_permissions'
);
EOF
		fi

		# Insert into GANTAGPROVIDERSETTINGS for Remote Tag Provider
		if [[ "$type_id" == "gantagprovider" ]]; then
			local server_name provider_name
			server_name=$(echo "$json_content" | jq -r '.server_name')
			provider_name=$(echo "$json_content" | jq -r '.provider_name')

			sqlite3 "$DB_LOCATION" <<EOF
INSERT INTO GANTAGPROVIDERSETTINGS (
	PROFILEID, SERVERNAME, PROVIDERNAME, HISTORYMODE, HISTORYDATASOURCEID, HISTORYDRIVERNAME, HISTORYPROVIDERNAME, ALARMSTATUSENABLED, ALARMMODE
) VALUES (
	$new_id, '$server_name', '$provider_name', 'GatewayNetwork', '', '', '', true, 'Queried'
);
EOF
		fi
	fi
}

###############################################################################
# Get datasource ID from name
###############################################################################
get_datasource_id() {
	local datasource_name="$1"
	local datasource_id

	datasource_id=$(sqlite3 "$DB_LOCATION" "SELECT DATASOURCES_ID FROM DATASOURCES WHERE NAME='$datasource_name';")

	if [ -z "$datasource_id" ]; then
		log_error "Datasource with name '$datasource_name' not found"
		return 1
	fi

	echo "$datasource_id"
}

###############################################################################
# Update or add a historical tag provider
###############################################################################
update_or_add_historical_provider() {
	local json_content="$1"
	local provider_id="$2"
	local name description enabled type_id allow_backfill enable_tag_reference_store

	name=$(echo "$json_content" | jq -r '.name')
	description=$(echo "$json_content" | jq -r '.description')
	enabled=$(echo "$json_content" | jq -r '.enabled')
	type_id=$(echo "$json_content" | jq -r '.type_id')
	allow_backfill=$(echo "$json_content" | jq -r '.allow_backfill')
	enable_tag_reference_store=$(echo "$json_content" | jq -r '.enable_tag_reference_store')

	# Check if provider already exists
	local existing_id
	existing_id=$(sqlite3 "$DB_LOCATION" "SELECT TAGHISTORYPROVIDEREP_ID FROM TAGHISTORYPROVIDEREP WHERE NAME='$name' AND TYPE='$type_id';")

	if [ -n "$existing_id" ]; then
		# Update existing provider
		sqlite3 "$DB_LOCATION" <<EOF
UPDATE TAGHISTORYPROVIDEREP SET
    DESCRIPTION='$description', ENABLED=$enabled
WHERE TAGHISTORYPROVIDEREP_ID=$existing_id;

UPDATE TAGPROVIDERSETTINGS SET
    DESCRIPTION='$description', ENABLED=$enabled, ALLOWBACKFILL=$allow_backfill, ENABLETAGREFERENCESTORE=$enable_tag_reference_store
WHERE TAGPROVIDERSETTINGS_ID=$existing_id;
EOF
		log_info "Updated existing historical tag provider: $name"
	else
		# Insert new provider
		local new_history_id new_provider_id
		new_history_id=$(get_next_id "TAGHISTORYPROVIDEREP" "TAGHISTORYPROVIDEREP_ID")
		new_provider_id=$(get_next_id "TAGPROVIDERSETTINGS" "TAGPROVIDERSETTINGS_ID")
		sqlite3 "$DB_LOCATION" <<EOF
INSERT INTO TAGHISTORYPROVIDEREP (
    TAGHISTORYPROVIDEREP_ID, NAME, ENABLED, TYPE, DESCRIPTION
) VALUES (
    $new_history_id, '$name', $enabled, '$type_id', '$description'
);

INSERT INTO TAGPROVIDERSETTINGS (
    TAGPROVIDERSETTINGS_ID, NAME, PROVIDERID, DESCRIPTION, ENABLED, TYPEID, ALLOWBACKFILL, ENABLETAGREFERENCESTORE
) VALUES (
    $new_provider_id, '$name', '$provider_id', '$description', $enabled, '$type_id', $allow_backfill, $enable_tag_reference_store
);

INSERT INTO TAGHISTORIANPROVIDERSETTINGS (
    PROFILEID, PARTITIONINGENABLED, PARTITIONSIZE, PARTITIONSIZEUNITS, OPTIMIZEDPARTITIONSENABLED,
    OPTIMIZEDWINDOWSIZESEC, PRUNINGENABLED, PRUNEAGE, PRUNEAGEUNITS, TRACKSCE, STALEMULTIPLIER
) VALUES (
    $new_history_id, true, 1, 'MONTH', false, 60, false, 1, 'YEAR', true, 2
);
EOF
		log_info "Added new historical tag provider: $name with History ID: $new_history_id and Provider ID: $new_provider_id"

		# Insert into specific tables based on provider type
		case "$type_id" in
		"widedb")
			local datasource_name datasource_id
			datasource_name=$(echo "$json_content" | jq -r '.datasource_name')

			if [ -n "$datasource_name" ]; then
				datasource_id=$(get_datasource_id "$datasource_name")
				if ! get_datasource_id "$datasource_name"; then
					return 1
				fi
			else
				datasource_id=$(echo "$json_content" | jq -r '.datasource_id')
			fi

			# Check if datasource exists
			local datasource_exists
			datasource_exists=$(sqlite3 "$DB_LOCATION" "SELECT COUNT(*) FROM DATASOURCES WHERE DATASOURCES_ID=$datasource_id;")

			if [ "$datasource_exists" -eq 0 ]; then
				log_error "Datasource with ID $datasource_id does not exist. Cannot create widedb provider."
				return 1
			fi

			sqlite3 "$DB_LOCATION" <<EOF
INSERT INTO WIDEDBHISTORIANPROVIDERSETTINGS (PROFILEID, DATASOURCEID)
VALUES ($new_history_id, $datasource_id);
EOF
			;;
		"SplittingProvider")
			local connection_a connection_b
			connection_a=$(echo "$json_content" | jq -r '.connection_a')
			connection_b=$(echo "$json_content" | jq -r '.connection_b')
			sqlite3 "$DB_LOCATION" <<EOF
INSERT INTO TAGHISTORYSPLITTERSETTINGS (
	PROFILEID, CONNECTIONA, CONNECTIONB, QUERYLIMITENABLED, QUERYLIMITSIZE, QUERYLIMITUNITS
) VALUES (
	$new_history_id, '$connection_a', '$connection_b', false, 1, 'MONTH'
);
EOF
			;;
		"EdgeHistorian")
			# Pass, as the EdgeHistorian doesn't have special tables
			;;
		"RemoteHistorian")
			local server_name provider_name allow_storage max_grouping
			server_name=$(echo "$json_content" | jq -r '.server_name')
			provider_name=$(echo "$json_content" | jq -r '.provider_name')
			allow_storage=$(echo "$json_content" | jq -r '.allow_storage')
			max_grouping=$(echo "$json_content" | jq -r '.max_grouping')
			sqlite3 "$DB_LOCATION" <<EOF
INSERT INTO REMOTEHISTORIANSETTINGS (PROFILEID, SERVERNAME, PROVIDERNAME, ALLOWSTORAGE, MAXGROUPING)
VALUES ($new_history_id, '$server_name', '$provider_name', $allow_storage, $max_grouping);

INSERT INTO STOREANDFORWARDSYSSETTINGS (
	STOREANDFORWARDSYSSETTINGS_ID, NAME, BUFFERSIZE, ENABLEDISKSTORE, STOREMAXRECORDS, STOREWRITESIZE, STOREWRITETIME,
	FORWARDFROMSTORE, FORWARDWRITESIZE, FORWARDWRITETIME, ENABLESCHEDULE, FORWARDSCHEDULE, ISTHIRDPARTY
) VALUES (
	$new_history_id, '$name', 250, true, 25000, 25, 5000, false, 25, 1000, false, '', true
);
EOF
			;;
		"history_sim")
			log_warning "history_sim provider type not yet supported"
			;;
		*)
			log_error "Unknown historical provider type: $type_id"
			return 1
			;;
		esac
	fi
}

###############################################################################
# Set default values for tag provider settings
###############################################################################
set_default_values() {
    local json_content="$1"

    # Set default values
    local defaults='{
        "enabled": true,
        "allow_backfill": true,
        "enable_tag_reference_store": true,
        "read_permissions": "AllOf,",
        "write_permissions": "AllOf,",
        "edit_permissions": "AllOf,",
        "allow_storage": true,
        "max_grouping": 0
    }'

    # Merge defaults with existing content, giving priority to existing values
    echo "$json_content" | jq --argjson defaults "$defaults" '$defaults * .'
}

###############################################################################
# Update or add a tag provider from a JSON file
###############################################################################
update_or_add_tag_provider() {
	local json_file="$1"
	local json_content
	json_content=$(cat "$json_file")

	local type_id
	type_id=$(echo "$json_content" | jq -r '.type_id')

	# Hardcoded map of tag provider types
	local provider_type
	case "$type_id" in
	"STANDARD" | "gantagprovider")
		provider_type="realtime"
		;;
	"widedb" | "EdgeHistorian" | "RemoteHistorian" | "SplittingProvider")
		provider_type="historical"
		;;
	*)
		log_error "Unknown provider type: $type_id"
		return 1
		;;
	esac

	# Set default values
	json_content=$(set_default_values "$json_content")

	local provider_id
	provider_id=$(generate_uuid)

	if [[ "$provider_type" == "realtime" ]]; then
		update_or_add_realtime_provider "$json_content" "$provider_id"
	elif [[ "$provider_type" == "historical" ]]; then
		update_or_add_historical_provider "$json_content" "$provider_id"
	else
		log_error "Unknown provider type: $provider_type"
		return 1
	fi
}

# Run the main function
main
