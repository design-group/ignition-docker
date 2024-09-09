#!/usr/bin/env bash

# shellcheck source=/usr/local/bin/script-utils.sh
# shellcheck disable=SC1091
source /usr/local/bin/script-utils.sh

# Enable error handling
trap handle_error ERR

# Global variables
DB_LOCATION=${DB_LOCATION:-"${IGNITION_INSTALL_LOCATION}/data/db/config.idb"}

###############################################################################
# Main function to set system properties
###############################################################################
main() {
	set_properties
}

###############################################################################
# Function to set a system property
###############################################################################
set_system_property() {
	local name="$1"
	local value="$2"
	local is_blob="${3:-false}"

	if [ "$is_blob" = true ]; then
		# For BLOB data (JSON in our case), we write it directly to a temp file
		echo -n "$value" >/tmp/blob_data
		if sqlite3 "$DB_LOCATION" "UPDATE SYSPROPS SET \"$name\" = readfile('/tmp/blob_data')"; then
			log_info "Set system property: $name (BLOB)"
		else
			log_error "Failed to set system property: $name (BLOB)"
		fi
		rm /tmp/blob_data
	else
		# For regular string data, we escape single quotes
		value="${value//\'/\'\'}"
		if sqlite3 "$DB_LOCATION" "UPDATE SYSPROPS SET \"$name\" = '$value'"; then
			log_info "Set system property: $name"
		else
			log_error "Failed to set system property: $name"
		fi
	fi
}

###############################################################################
# Function to set permissions
###############################################################################
set_permissions() {
	local prop_name="$1"
	local permissions="$2"
	if [ -n "${permissions+x}" ]; then
		local json
		json=$(convert_permissions_to_json "$permissions")
		# Remove any newline characters and extra spaces
		json=$(echo "$json" | tr -d '\n' | tr -s ' ')
		set_system_property "$prop_name" "$json" true
	fi
}

###############################################################################
# Function to get auth profile ID
###############################################################################
get_auth_profile_id() {
	local profile_name="$1"
	sqlite3 "$DB_LOCATION" "SELECT AUTHPROFILES_ID FROM AUTHPROFILES WHERE NAME = '$profile_name';"
}

###############################################################################
# Main function to set properties
###############################################################################
set_properties() {
	if [ -n "${SYSTEM_USER_SOURCE:-}" ]; then
		local auth_profile_id
		auth_profile_id=$(get_auth_profile_id "$SYSTEM_USER_SOURCE")
		set_system_property "SYSTEMAUTHPROFILEID" "$auth_profile_id"
	fi

	[ -n "${SYSTEM_IDENTITY_PROVIDER:-}" ] && set_system_property "SYSTEMIDENTITYPROVIDER" "$SYSTEM_IDENTITY_PROVIDER"
	[ -n "${HOMEPAGE_URL:-}" ] && set_system_property "HOMEPAGEURL" "$HOMEPAGE_URL"
	[ -n "${DESIGNER_AUTH_STRATEGY:-}" ] && set_system_property "DESIGNERAUTHSTRATEGY" "$DESIGNER_AUTH_STRATEGY"

	set_permissions "CONFIGPERMISSIONS" "${CONFIG_PERMISSIONS:-}"
	set_permissions "STATUSPAGEPERMISSIONS" "${STATUS_PAGE_PERMISSIONS:-}"
	set_permissions "HOMEPAGEPERMISSIONS" "${HOME_PAGE_PERMISSIONS:-}"
	set_permissions "DESIGNERPERMISSIONS" "${DESIGNER_PERMISSIONS:-}"
	set_permissions "CREATEPROJECTPERMISSIONS" "${PROJECT_CREATION_PERMISSIONS:-}"
}

# Run the main function
main
