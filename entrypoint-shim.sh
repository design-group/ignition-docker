#!/usr/bin/env bash

# shellcheck source=/usr/local/bin/script-utils.sh
# shellcheck disable=SC1091
source /usr/local/bin/script-utils.sh

# Enable error handling
trap handle_error ERR

args=("$@")

# Declare a map of any potential wrapper arguments to be passed into Ignition upon startup
declare -A wrapper_args_map=(
	["-Dignition.projects.scanFrequency"]=${PROJECT_SCAN_FREQUENCY:-10} # Disable console logging
)

# Declare a map of potential jvm arguments to be passed into Ignition upon startup, before the wrapper args
declare -A jvm_args_map=()

main() {
	log_info "Starting Ignition gateway initialization"

	# Create the data folder for Ignition for any upcoming symlinks
	mkdir -p "${IGNITION_INSTALL_LOCATION}"/data
	log_info "Created data folder: ${IGNITION_INSTALL_LOCATION}/data"

	if [ "$SYMLINK_PROJECTS" = "true" ] || [ "$SYMLINK_THEMES" = "true" ]; then
		# Create the working directory
		mkdir -p "${WORKING_DIRECTORY}"
		log_info "Created working directory: ${WORKING_DIRECTORY}"

		# Create the symlink for the projects folder if enabled
		[ "$SYMLINK_PROJECTS" = "true" ] && symlink_projects

		# Create the symlink for the themes folder if enabled
		[ "$SYMLINK_THEMES" = "true" ] && symlink_themes

		# If there are additional folders to symlink, run the function
		[ -n "$ADDITIONAL_DATA_FOLDERS" ] && setup_additional_folder_symlinks "$ADDITIONAL_DATA_FOLDERS"
	fi

	# If developer mode is enabled, add the developer mode wrapper arguments
	[ "$DEVELOPER_MODE" = "Y" ] && add_developer_mode_args

	create_dedicated_user

	# Handle gateway backup
	handle_gateway_backup

	# Copy any modules from the /modules directory into the user lib
	copy_modules_to_user_lib

	# Register admin password
	register_admin_password

	# Generate or use provided encoding key
	setup_encoding_key

	# Set opcua password
	opc_ua_password_sync

	# Add database connections
	add_database_connections

	# Add IDP adapters
    add_idp_adapters
	
	# Add tag providers
	add_tag_providers

	# Add images to the database
    add_images_to_idb

	if version_gte "$IGNITION_VERSION" "8.1.20"; then
		# Set co-branding configuration
		set_cobranding_properties
	fi

	# Set system properties
	set_system_properties

	# Add localization
	add_localization

	# Restore the final gateway backup
	restore_gateway_backup

	# Prepare arguments for launching Ignition
	prepare_launch_args

	# Launch Ignition
	launch_ignition "${args[@]}"
}

################################################################################
# Setup a dedicated user based off the UID and GID provided
################################################################################
create_dedicated_user() {
	# Setup dedicated user
	groupmod -g "${IGNITION_GID}" ignition
	usermod -u "${IGNITION_UID}" ignition
	chown -R "${IGNITION_UID}":"${IGNITION_GID}" /usr/local/bin/

	# If the /workdir folder exists, chown it to the dedicated user
	if [ -d "${WORKING_DIRECTORY}" ]; then
		chown -R "${IGNITION_UID}":"${IGNITION_GID}" "${WORKING_DIRECTORY}"
	fi
}

################################################################################
# Create the projects directory and symlink it to the host's projects directory
################################################################################
symlink_projects() {
	# If the project directory symlink isnt already there, create it
	if [ ! -L "${IGNITION_INSTALL_LOCATION}"/data/projects ]; then
		ln -s "${WORKING_DIRECTORY}"/projects "${IGNITION_INSTALL_LOCATION}"/data/
		mkdir -p "${WORKING_DIRECTORY}"/projects
	fi
}

################################################################################
# Create the themes directory and symlink it to the host's themes directory
################################################################################
symlink_themes() {
	# If the modules directory symlink isnt already there, create it
	if [ ! -L "${IGNITION_INSTALL_LOCATION}"/data/modules ]; then
		mkdir -p "${IGNITION_INSTALL_LOCATION}"/data
		ln -s "${WORKING_DIRECTORY}"/modules "${IGNITION_INSTALL_LOCATION}"/data/
		mkdir -p "${WORKING_DIRECTORY}"/modules
	fi
}

################################################################################
# Setup any additional folder symlinks for things like the /configs folder
# Arguments:
#   $1 - Comma separated list of folders to symlink
################################################################################
setup_additional_folder_symlinks() {
	# ADDITIONAL_FOLDERS will be a comma delimited string of file paths to create symlinks for
	local ADDITIONAL_FOLDERS="${1}"

	# Split the ADDITIONAL_FOLDERS string into an array
	IFS=',' read -ra ADDITIONAL_FOLDERS_ARRAY <<<"${ADDITIONAL_FOLDERS}"

	# Loop through the array and create symlinks for each folder
	for ADDITIONAL_FOLDER in "${ADDITIONAL_FOLDERS_ARRAY[@]}"; do
		# If the symlink and folder don't exist, create them
		if [ ! -L "${IGNITION_INSTALL_LOCATION}"/data/"${ADDITIONAL_FOLDER}" ]; then
			log_info "Creating symlink for ${ADDITIONAL_FOLDER}"
			ln -s "${WORKING_DIRECTORY}"/"${ADDITIONAL_FOLDER}" "${IGNITION_INSTALL_LOCATION}"/data/

			log_info "Creating workdir folder for ${ADDITIONAL_FOLDER}"
			mkdir -p "${WORKING_DIRECTORY}"/"${ADDITIONAL_FOLDER}"
		fi
	done
}



################################################################################
# Enable the developer mode java args so that its easier to upload custom modules
################################################################################
add_developer_mode_args() {
	wrapper_args_map+=(["-Dia.developer.moduleupload"]="true")
	wrapper_args_map+=(["-Dignition.allowunsignedmodules"]="true")
}

################################################################################
# Creates a random encoding key if one is not provided
################################################################################
setup_encoding_key() {
	# Check if the file is empty or doesn't exist
	if [ ! -s "$GATEWAY_ENCODING_KEY_FILE" ] && [ -z "$GATEWAY_ENCODING_KEY" ]; then
		# Generate a 24-byte (48 hex characters) random key
		openssl rand -hex 24 > "$GATEWAY_ENCODING_KEY_FILE"
		log_warning "No encoded key was provided, the following was generated: $(cat "$GATEWAY_ENCODING_KEY_FILE")"
	fi

	# If the GATEWAY_ENCODING_KEY is not empty, use it
	if [ -n "$GATEWAY_ENCODING_KEY" ]; then
		echo "$GATEWAY_ENCODING_KEY" > "$GATEWAY_ENCODING_KEY_FILE"
	fi

	GATEWAY_ENCODING_KEY=$(cat "$GATEWAY_ENCODING_KEY_FILE")
	export GATEWAY_ENCODING_KEY
	export GATEWAY_ENCODING_KEY_ISHEX=true

	# If we are prior to the `GATEWAY_ENCODING_KEY` being created, we need to add a jvm arg
	if ! version_gte "$IGNITION_VERSION" "8.1.38"; then
		wrapper_args_map+=(["-DencodingKey"]="$GATEWAY_ENCODING_KEY")
	fi
}

################################################################################
# Handle the gateway backup, either using the default or user-provided one
################################################################################
handle_gateway_backup() {
	local backup_file="/tmp/gateway_backup.gwbk"

	# Check if user provided a backup file
	if [[ " ${args[*]} " =~ " -r " ]]; then
		local user_backup
		user_backup=$(echo "${args[*]}" | sed -n 's/.*-r \([^ ]*\).*/\1/p')
		if [ -f "$user_backup" ]; then
			cp "$user_backup" "$backup_file"
		else
			log_info "User-provided backup file not found. Using default backup."
			cp /base.gwbk "$backup_file"
		fi
	else
		cp /base.gwbk "$backup_file"
	fi

	# Extract the config.idb from the backup
	mkdir -p "${IGNITION_INSTALL_LOCATION}/data/db"
	if unzip -p "$backup_file" db_backup_sqlite.idb >"${IGNITION_INSTALL_LOCATION}/data/db/config.idb"; then
		log_info "Successfully extracted config.idb from backup"
	else
		log_error "Failed to extract config.idb from backup"
		exit 1
	fi

	# Set the DB_LOCATION variable for other scripts to use
	export DB_LOCATION="${IGNITION_INSTALL_LOCATION}/data/db/config.idb"
}

################################################################################
# Copy any modules from the /modules directory into the user lib
################################################################################
copy_modules_to_user_lib() {
	# Check if there are any .modl files in the modules directory, if not exit
	if ! ls /modules/*.modl 1>/dev/null 2>&1; then
		log_info "No additional modules found in the /modules directory"
		return
	fi

	# Copy the modules from the modules folder into the ignition modules folder
	cp -r /modules/*.modl "${IGNITION_INSTALL_LOCATION}"/user-lib/modules/

	# Register the modules each in the gateway, so that their certificates are trusted
	for module in /modules/*.modl; do
		if [ -f "$module" ]; then
			/usr/local/bin/register-module.sh -f "$module" -d "$DB_LOCATION"
		fi
	done
}

################################################################################
# Set the credentials via the register-password.sh script, so that the gateway does not
# arbitrary build up temp user sources repeatedly
################################################################################
register_admin_password() {
	echo "$GATEWAY_ADMIN_PASSWORD" >/tmp/admin_password
	/usr/local/bin/register-password.sh -u "$GATEWAY_ADMIN_USERNAME" -f /tmp/admin_password -d "$DB_LOCATION"
	rm /tmp/admin_password

	# Unset the username:password from the environment variable so that the regular entrypoint doesn't catch it
	unset GATEWAY_ADMIN_PASSWORD
	unset GATEWAY_ADMIN_USERNAME
}

################################################################################
# Set the credentials via the register-password.sh script, so that the gateway does not
# arbitrary build up temp user sources repeatedly
################################################################################
opc_ua_password_sync() {
	/usr/local/bin/sync-opcua-password.sh
}

################################################################################
# Register any user provided database connections
################################################################################
add_database_connections() {
    if [ -d "/init-db-connections" ]; then
        /usr/local/bin/add-database-connection.sh
    fi
}

################################################################################
# Create any IDP adapters from the /init-idp-adapters directory
################################################################################
add_idp_adapters() {
    if [ -d "/init-idp-adapters" ]; then
		/usr/local/bin/add-idp-adapters.sh
	fi
}

################################################################################
# Add tag providers from JSON files in the /tag-providers directory
################################################################################
add_tag_providers() {
    if [ -d "/tag-providers" ]; then
        /usr/local/bin/add-tag-providers.sh
    fi
}

################################################################################
# Add images to the internal database
################################################################################
add_images_to_idb() {
	if [ -d "/idb-images" ]; then
    	/usr/local/bin/add-images-to-idb.sh
	fi
}

################################################################################
# Set co-branding configuration
################################################################################
set_cobranding_properties() {
	if [ -d "/co-branding" ]; then
		/usr/local/bin/set-cobranding-properties.sh
	fi
}



################################################################################
# Set any default gateway system properties
################################################################################
set_system_properties() {
	# Set system properties
	/usr/local/bin/set-system-properties.sh
}

###############################################################################
# Add localization
###############################################################################
add_localization() {
    /usr/local/bin/add-localization.sh
}


################################################################################
# Restore the final gateway backup
################################################################################
restore_gateway_backup() {
    local backup_file="/tmp/gateway_backup.gwbk"

    # Update the config.idb in the backup
    if zip -j -u "$backup_file" "$DB_LOCATION" > /dev/null 2>&1; then
        log_info "Updated gateway backup with latest configuration"
    else
        log_error "Failed to update gateway backup"
    fi

    # Add the -r option to the args if it's not already there
    if [[ ! " ${args[*]} " =~ " -r " ]]; then
        args+=("-r" "$backup_file")
    fi
}


################################################################################
# Prepare the launch arguments for Ignition by converting the associative arrays to index arrays
################################################################################
prepare_launch_args() {
	# Convert wrapper args associative array to index array prior to launch
	local wrapper_args=()
	for key in "${!wrapper_args_map[@]}"; do
		wrapper_args+=("${key}=${wrapper_args_map[${key}]}")
		log_info "Collected wrapper arg: ${key}=${wrapper_args_map[${key}]}"
	done

	# Convert jvm args associative array to index array prior to launch
	local jvm_args=()
	for key in "${!jvm_args_map[@]}"; do
		jvm_args+=("${key}" "${jvm_args_map[${key}]}")
		log_info "Collected JVM arg: ${key} ${jvm_args_map[${key}]}"
	done

	# If "--" is already in the args, insert any jvm args before it, else if it isn't there just append the jvm args
	if [[ " ${args[*]} " =~ " -- " ]]; then
		# Insert the jvm args before the "--" in the args array
		args=("${args[@]/#-- /-- ${jvm_args[*]} }")
	else
		# Append the jvm args to the args array
		args+=("${jvm_args[@]}")
	fi

	# If "--" is not already in the args, make sure you append it before the wrapper args
	[[ ! " ${args[*]} " =~ " -- " ]] && args+=("--")

	# Append the wrapper args to the provided args
	args+=("${wrapper_args[@]}")
}

################################################################################
# Start the official images entrypoint script
################################################################################
launch_ignition() {
	# Run the entrypoint
	# Check if docker-entrypoint is not in bin directory
	if [ ! -e /usr/local/bin/docker-entrypoint.sh ]; then
		# Run the original entrypoint script
		mv docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
	fi

	log_info "Launching Ignition with args: $*"
	exec docker-entrypoint.sh "$@"
}

main "${args[@]}"