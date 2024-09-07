#!/usr/bin/env bash
set -euo pipefail

DB_LOCATION=${DB_LOCATION:-"${IGNITION_INSTALL_LOCATION}/data/db/config.idb"}

# Function to convert permission string to JSON
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
	IFS=',' read -ra permission_array <<<"$permissions"
	local json="{\"type\":\"$type\",\"securityLevels\":["
	local first=true

	for permission in "${permission_array[@]}"; do
		if [ "$first" = true ]; then
			first=false
		else
			json="${json},"
		fi

		local IFS='/'
		IFS='/' read -ra levels <<<"$permission"
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

# Function to set a system property
set_system_property() {
	local name="$1"
	local value="$2"
	local is_blob="${3:-false}"

	if [ "$is_blob" = true ]; then
		# For BLOB data (JSON in our case), we write it directly to a temp file
		echo -n "$value" >/tmp/blob_data
		sqlite3 "$DB_LOCATION" <<EOF
UPDATE SYSPROPS SET "$name" = readfile('/tmp/blob_data');
EOF
		rm /tmp/blob_data
		echo "Set system property: $name (BLOB)"
	else
		# For regular string data, we escape single quotes
		value="${value//\'/\'\'}"
		sqlite3 "$DB_LOCATION" <<EOF
UPDATE SYSPROPS SET "$name" = '$value';
EOF
		echo "Set system property: $name"
	fi
}

# Function to set permissions
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

# Function to get auth profile ID
get_auth_profile_id() {
	local profile_name="$1"
	sqlite3 "$DB_LOCATION" "SELECT AUTHPROFILES_ID FROM AUTHPROFILES WHERE NAME = '$profile_name';"
}

# Main function to set properties
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

	echo "System properties set successfully."
}

# Call the main function
set_properties
