#!/usr/bin/env bash

# shellcheck source=/usr/local/bin/script-utils.sh
# shellcheck disable=SC1091
source /usr/local/bin/script-utils.sh

# Enable error handling
trap handle_error ERR

# Global variables
DB_LOCATION=${DB_LOCATION:-"${IGNITION_INSTALL_LOCATION}/data/db/config.idb"}
OPC_SERVER_PASSWORD=${OPC_SERVER_PASSWORD:-"password"}

###############################################################################
# Main function to synchronize the OPC UA server password
###############################################################################
main() {
	if [ ! -f "${DB_LOCATION}" ]; then
		log_warning "${DB_LOCATION} not found, skipping OPC UA password sync"
		return 0
	fi

	sync_opc_ua_password
}

###############################################################################
# Function to encode password using GATEWAY_ENCODING_KEY
###############################################################################
encode_password() {
	local password="$1"
	local encoded_password
	encoded_password=$(/usr/local/bin/encode-password.sh -k "$GATEWAY_ENCODING_KEY" -p "$password")
	echo "$encoded_password"
}

###############################################################################
# Function to generate salted hash for internal user
###############################################################################
generate_salted_hash() {
	local password="$1"
	local auth_salt
	auth_salt=$(od -An -v -t x1 -N 4 /dev/random | tr -d ' ')
	local auth_pwsalthash
	auth_pwsalthash=$(printf %s "${password}${auth_salt}" | sha256sum - | cut -c -64)
	echo "[${auth_salt}]${auth_pwsalthash}"
}

###############################################################################
# Synchronize the OPC UA server password with the internal user password
###############################################################################
sync_opc_ua_password() {
	# Retrieve OPC UA connection settings
	local opc_ua_settings server_settings_id username current_password
	opc_ua_settings=$(sqlite3 "${DB_LOCATION}" "SELECT SERVERSETTINGSID, USERNAME, PASSWORD FROM OPCUACONNECTIONSETTINGS WHERE ENDPOINTURL='opc.tcp://localhost:62541'")
	IFS='|' read -r server_settings_id username current_password <<<"$opc_ua_settings"

	if [ -z "$server_settings_id" ]; then
		log_error "OPC UA connection for opc.tcp://localhost:62541 not found"
		return 1
	fi

	# Check if the current password matches the expected password
	local encoded_current_password update_required=false
	encoded_current_password=$(encode_password "$OPC_SERVER_PASSWORD")
	if [ "$current_password" != "$encoded_current_password" ]; then
		log_info "Current OPC Server password does not match the expected value. Will update with new password."
		update_required=true
	fi

	if [ "$update_required" = true ]; then
		# Generate new password hash for internal user
		local new_password_hash
		new_password_hash=$(generate_salted_hash "$OPC_SERVER_PASSWORD")

		# Update internal user password
		sqlite3 "${DB_LOCATION}" "UPDATE INTERNALUSERTABLE SET PASSWORD='$new_password_hash' WHERE USERNAME='$username'"

		# Encode password for OPC UA connection
		local encoded_password
		encoded_password=$(encode_password "$OPC_SERVER_PASSWORD")

		# Update OPC UA connection password
		sqlite3 "${DB_LOCATION}" "UPDATE OPCUACONNECTIONSETTINGS SET PASSWORD='$encoded_password', KEYSTOREALIASPASSWORD='$encoded_password' WHERE SERVERSETTINGSID=$server_settings_id"

		log_info "Password updated successfully for user $username in both INTERNALUSERTABLE and OPCUACONNECTIONSETTINGS"
	fi
}

###############################################################################
# Print usage information
###############################################################################
usage() {
	echo "Usage: $0 [-h]"
	echo "Synchronizes the OPC UA server password with the internal user password"
	echo "  -h  Show this help message"
}

# Argument Processing
while getopts ":h" opt; do
	case ${opt} in
	h)
		usage
		exit 0
		;;
	\?)
		log_error "Invalid option: -$OPTARG"
		usage
		exit 1
		;;
	esac
done
shift $((OPTIND - 1))

# Run the main function
main
