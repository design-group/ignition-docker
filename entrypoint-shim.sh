#!/usr/bin/env bash

args=("$@")

# Declare a map of any potential wrapper arguments to be passed into Ignition upon startup
declare -A wrapper_args_map=( 
    ["-Dignition.projects.scanFrequency"]=${PROJECT_SCAN_FREQUENCY:-10}  # Disable console logging
)

# Declare a map of potential jvm arguments to be passed into Ignition upon startup, before the wrapper args
declare -A jvm_args_map=()

main() {  
    # Create the data folder for Ignition for any upcoming symlinks
    mkdir -p "${IGNITION_INSTALL_LOCATION}"/data

	if [ "$SYMLINK_PROJECTS" = "true" ] || [ "$SYMLINK_THEMES" = "true" ]; then
		# Create the working directory
		mkdir -p "${WORKING_DIRECTORY}"

		# Create the symlink for the projects folder if enabled
		if [ "$SYMLINK_PROJECTS" = "true" ]; then
			symlink_projects
		fi

		# Create the symlink for the themes folder if enabled
		if [ "$SYMLINK_THEMES" = "true" ]; then
			symlink_themes
		fi

		# If there are additional folders to symlink, run the function
		if [ -n "$ADDITIONAL_DATA_FOLDERS" ]; then
			setup_additional_folder_symlinks "$ADDITIONAL_DATA_FOLDERS";
		fi
	fi

    # If there are any modules mapped into the /modules directory, copy them to the user lib
    if [ -d "/modules" ]; then
        copy_modules_to_user_lib
    fi

	# If developer mode is enabled, add the developer mode wrapper arguments
	if [ "$DEVELOPER_MODE" = "Y" ]; then
		add_developer_mode_args
	fi

     # Convert wrapper args associative array to index array prior to launch
    local wrapper_args=( )
    for key in "${!wrapper_args_map[@]}"; do
        wrapper_args+=( "${key}=${wrapper_args_map[${key}]}")
    done

	# Convert jvm args associative array to index array prior to launch
	local jvm_args=( )
	for key in "${!jvm_args_map[@]}"; do
		jvm_args+=( "${key}" "${jvm_args_map[${key}]}" )
	done

	# If "--" is already in the args, insert any jvm args before it, else if it isnt there just append the jvm args
	if [[ " ${args[*]} " =~ " -- " ]]; then
		# Insert the jvm args before the "--" in the args array
		args=("${args[@]/#-- /-- ${jvm_args[*]} }")
	else
		# Append the jvm args to the args array
		args+=( "${jvm_args[@]}" )
	fi
	
    # If "--" is not alraedy in the args, make sure you append it before the wrapper args
	if [[ ! " ${args[*]} " =~ " -- " ]]; then
		args+=( "--" )
	fi

    # Append the wrapper args to the provided args
    args+=("${wrapper_args[@]}")

	# Create the dedicated user
	create_dedicated_user

    entrypoint "${args[@]}"
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
    IFS=',' read -ra ADDITIONAL_FOLDERS_ARRAY <<< "${ADDITIONAL_FOLDERS}"

    # Loop through the array and create symlinks for each folder
    for ADDITIONAL_FOLDER in "${ADDITIONAL_FOLDERS_ARRAY[@]}"; do
        # If the symlink and folder don't exist, create them
        if [ ! -L "${IGNITION_INSTALL_LOCATION}"/data/"${ADDITIONAL_FOLDER}" ]; then
            echo "Creating symlink for ${ADDITIONAL_FOLDER}"
            ln -s "${WORKING_DIRECTORY}"/"${ADDITIONAL_FOLDER}" "${IGNITION_INSTALL_LOCATION}"/data/

            echo "Creating workdir folder for ${ADDITIONAL_FOLDER}"
            mkdir -p "${WORKING_DIRECTORY}"/"${ADDITIONAL_FOLDER}"
        fi
    done
}

################################################################################
# Copy any modules from the /modules directory into the user lib
################################################################################
copy_modules_to_user_lib() {
    # Copy the modules from the modules folder into the ignition modules folder
	cp -r /modules/* "${IGNITION_INSTALL_LOCATION}"/user-lib/modules/
}

################################################################################
# Enable the developer mode java args so that its easier to upload custom modules
################################################################################
add_developer_mode_args() {
	wrapper_args_map+=( ["-Dia.developer.moduleupload"]="true" )
	wrapper_args_map+=( ["-Dignition.allowunsignedmodules"]="true" )
}

################################################################################
# Execute the entrypoint for the container
################################################################################
entrypoint() {

    # Run the entrypoint
    # Check if docker-entrpoint is not in bin directory
    if [ ! -e /usr/local/bin/docker-entrypoint.sh ]; then
        # Run the original entrypoint script
        mv docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
    fi

    echo "Running entrypoint with args $*"
    exec docker-entrypoint.sh "$@"
}


main "${args[*]}"