#!/usr/bin/env bash

# shellcheck source=/usr/local/bin/script-utils.sh
# shellcheck disable=SC1091
source /usr/local/bin/script-utils.sh

# Enable error handling
trap handle_error ERR

# Global variables
DB_LOCATION=${DB_LOCATION:-"${IGNITION_INSTALL_LOCATION}/data/db/config.idb"}

###############################################################################
# Main function to process and add tag providers
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
			if add_tag_provider "$json_file"; then
				log_info "Successfully added tag provider from $json_file"
			else
				log_error "Failed to add tag provider from $json_file"
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
# Add a realtime tag provider
###############################################################################
add_realtime_provider() {
	local json_content="$1"
	local next_tag_provider_id="$2"
	local provider_id="$3"

	local name description enabled type_id allow_backfill enable_tag_reference_store

	name=$(echo "$json_content" | jq -r '.name')
	description=$(echo "$json_content" | jq -r '.description')
	enabled=$(echo "$json_content" | jq -r '.enabled')
	type_id=$(echo "$json_content" | jq -r '.type_id')
	allow_backfill=$(echo "$json_content" | jq -r '.allow_backfill')
	enable_tag_reference_store=$(echo "$json_content" | jq -r '.enable_tag_reference_store')

	# Insert into TAGPROVIDERSETTINGS
	sqlite3 "$DB_LOCATION" <<EOF
INSERT INTO TAGPROVIDERSETTINGS (
    TAGPROVIDERSETTINGS_ID, NAME, PROVIDERID, DESCRIPTION, ENABLED, TYPEID, ALLOWBACKFILL, ENABLETAGREFERENCESTORE
) VALUES (
    $next_tag_provider_id, '$name', '$provider_id', '$description', $enabled, '$type_id', $allow_backfill, $enable_tag_reference_store
);
EOF

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
    $next_tag_provider_id, '', '', '', '$read_permissions', false, '$write_permissions', '$edit_permissions'
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
    $next_tag_provider_id, '$server_name', '$provider_name', 'GatewayNetwork', '', '', '', true, 'Queried'
);
EOF
	fi
}

###############################################################################
# Add a historical tag provider
###############################################################################
add_historical_provider() {
	local json_content="$1"
	local next_tag_provider_id="$2"
	local provider_id="$3"

	local name description enabled type_id allow_backfill enable_tag_reference_store

	name=$(echo "$json_content" | jq -r '.name')
	description=$(echo "$json_content" | jq -r '.description')
	enabled=$(echo "$json_content" | jq -r '.enabled')
	type_id=$(echo "$json_content" | jq -r '.type_id')
	allow_backfill=$(echo "$json_content" | jq -r '.allow_backfill')
	enable_tag_reference_store=$(echo "$json_content" | jq -r '.enable_tag_reference_store')

	# Insert into TAGHISTORYPROVIDEREP
	sqlite3 "$DB_LOCATION" <<EOF
INSERT INTO TAGHISTORYPROVIDEREP (
    TAGHISTORYPROVIDEREP_ID, NAME, ENABLED, TYPE, DESCRIPTION
) VALUES (
    $next_tag_provider_id, '$name', $enabled, '$type_id', '$description'
);
EOF

	# Insert into TAGPROVIDERSETTINGS
	sqlite3 "$DB_LOCATION" <<EOF
INSERT INTO TAGPROVIDERSETTINGS (
    TAGPROVIDERSETTINGS_ID, NAME, PROVIDERID, DESCRIPTION, ENABLED, TYPEID, ALLOWBACKFILL, ENABLETAGREFERENCESTORE
) VALUES (
    $next_tag_provider_id, '$name', '$provider_id', '$description', $enabled, '$type_id', $allow_backfill, $enable_tag_reference_store
);
EOF

	# Insert into TAGHISTORIANPROVIDERSETTINGS
	sqlite3 "$DB_LOCATION" <<EOF
INSERT INTO TAGHISTORIANPROVIDERSETTINGS (
    PROFILEID, PARTITIONINGENABLED, PARTITIONSIZE, PARTITIONSIZEUNITS, OPTIMIZEDPARTITIONSENABLED,
    OPTIMIZEDWINDOWSIZESEC, PRUNINGENABLED, PRUNEAGE, PRUNEAGEUNITS, TRACKSCE, STALEMULTIPLIER
) VALUES (
    $next_tag_provider_id, true, 1, 'MONTH', false, 60, false, 1, 'YEAR', true, 2
);
EOF

	# Insert into specific tables based on provider type
	case "$type_id" in
	"widedb")
		local datasource_id
		datasource_id=$(echo "$json_content" | jq -r '.datasource_id')
		sqlite3 "$DB_LOCATION" <<EOF
INSERT INTO WIDEDBHISTORIANPROVIDERSETTINGS (PROFILEID, DATASOURCEID)
VALUES ($next_tag_provider_id, $datasource_id);
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
    $next_tag_provider_id, '$connection_a', '$connection_b', false, 1, 'MONTH'
);
EOF
		;;
	"EdgeHistorian")
		log_warning "EdgeHistorian provider type not yet supported"
		;;
	"RemoteHistorian")
		local server_name provider_name allow_storage max_grouping
		server_name=$(echo "$json_content" | jq -r '.server_name')
		provider_name=$(echo "$json_content" | jq -r '.provider_name')
		allow_storage=$(echo "$json_content" | jq -r '.allow_storage')
		max_grouping=$(echo "$json_content" | jq -r '.max_grouping')
		sqlite3 "$DB_LOCATION" <<EOF
INSERT INTO REMOTEHISTORIANSETTINGS (PROFILEID, SERVERNAME, PROVIDERNAME, ALLOWSTORAGE, MAXGROUPING)
VALUES ($next_tag_provider_id, '$server_name', '$provider_name', $allow_storage, $max_grouping);

INSERT INTO STOREANDFORWARDSYSSETTINGS (
    STOREANDFORWARDSYSSETTINGS_ID, NAME, BUFFERSIZE, ENABLEDISKSTORE, STOREMAXRECORDS, STOREWRITESIZE, STOREWRITETIME,
    FORWARDFROMSTORE, FORWARDWRITESIZE, FORWARDWRITETIME, ENABLESCHEDULE, FORWARDSCHEDULE, ISTHIRDPARTY
) VALUES (
    $next_tag_provider_id, '$name', 250, true, 25000, 25, 5000, false, 25, 1000, false, '', true
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
}

###############################################################################
# Add a tag provider from a JSON file
###############################################################################
add_tag_provider() {
	local json_file="$1"
	local json_content
	json_content=$(cat "$json_file")

	local provider_type
	provider_type=$(echo "$json_content" | jq -r '.provider_type')

	local provider_id
	provider_id=$(generate_uuid)

	local next_tag_provider_id
	next_tag_provider_id=$(get_next_id "TAGPROVIDERSETTINGS" "TAGPROVIDERSETTINGS_ID")

	if [[ "$provider_type" == "realtime" ]]; then
		add_realtime_provider "$json_content" "$next_tag_provider_id" "$provider_id"
	elif [[ "$provider_type" == "historical" ]]; then
		add_historical_provider "$json_content" "$next_tag_provider_id" "$provider_id"
	else
		log_error "Unknown provider type: $provider_type"
		return 1
	fi
}

# Run the main function
main
