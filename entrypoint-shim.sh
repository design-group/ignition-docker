#!/usr/bin/env bash

# shellcheck source=/usr/local/bin/script-utils.sh
# shellcheck disable=SC1091
source /usr/local/bin/script-utils.sh

# Enable error handling
trap handle_error ERR

args=("$@")

# Declare a map of wrapper arguments
declare -A wrapper_args_map=(
    ["-Dignition.projects.scanFrequency"]=${PROJECT_SCAN_FREQUENCY:-10}
)

# Declare a map of JVM arguments
declare -A jvm_args_map=()

main() {
    log_info "Starting Ignition gateway initialization"

    # Create the data folder for Ignition
    mkdir -p "${IGNITION_INSTALL_LOCATION}/data"
    log_info "Created data folder: ${IGNITION_INSTALL_LOCATION}/data"

    if [ "$SYMLINK_PROJECTS" = "true" ] || [ "$SYMLINK_THEMES" = "true" ]; then
        mkdir -p "${WORKING_DIRECTORY}"
        log_info "Created working directory: ${WORKING_DIRECTORY}"

        [ "$SYMLINK_PROJECTS" = "true" ] && symlink_projects
        [ "$SYMLINK_THEMES" = "true" ] && symlink_themes
        [ -n "$ADDITIONAL_DATA_FOLDERS" ] && setup_additional_folder_symlinks "$ADDITIONAL_DATA_FOLDERS"
    fi

    # Handle gateway backup to extract config.idb
    handle_gateway_backup

    # Copy and register modules
    if [ -d "/modules" ]; then
        copy_modules_to_user_lib
    fi

    # Developer mode args
    [ "$DEVELOPER_MODE" = "Y" ] && add_developer_mode_args

    # Create dedicated user
    create_dedicated_user

    # Prepare launch arguments
    prepare_launch_args

    # Launch Ignition
    entrypoint "${args[@]}"
}

################################################################################
# Setup a dedicated user based off the UID and GID provided
################################################################################
create_dedicated_user() {
    groupmod -g "${IGNITION_GID}" ignition
    usermod -u "${IGNITION_UID}" ignition
    chown -R "${IGNITION_UID}":"${IGNITION_GID}" /usr/local/bin/
    [ -d "${WORKING_DIRECTORY}" ] && chown -R "${IGNITION_UID}":"${IGNITION_GID}" "${WORKING_DIRECTORY}"
}

################################################################################
# Create the projects directory and symlink it
################################################################################
symlink_projects() {
    if [ ! -L "${IGNITION_INSTALL_LOCATION}/data/projects" ]; then
        ln -s "${WORKING_DIRECTORY}/projects" "${IGNITION_INSTALL_LOCATION}/data/"
        mkdir -p "${WORKING_DIRECTORY}/projects"
    fi
}

################################################################################
# Create the themes directory and symlink it
################################################################################
symlink_themes() {
    if [ ! -L "${IGNITION_INSTALL_LOCATION}/data/modules" ]; then
        mkdir -p "${IGNITION_INSTALL_LOCATION}/data"
        ln -s "${WORKING_DIRECTORY}/modules" "${IGNITION_INSTALL_LOCATION}/data/"
        mkdir -p "${WORKING_DIRECTORY}/modules"
    fi
}

################################################################################
# Setup additional folder symlinks
################################################################################
setup_additional_folder_symlinks() {
    local ADDITIONAL_FOLDERS="${1}"
    IFS=',' read -ra ADDITIONAL_FOLDERS_ARRAY <<< "${ADDITIONAL_FOLDERS}"
    for ADDITIONAL_FOLDER in "${ADDITIONAL_FOLDERS_ARRAY[@]}"; do
        if [ ! -L "${IGNITION_INSTALL_LOCATION}/data/${ADDITIONAL_FOLDER}" ]; then
            log_info "Creating symlink for ${ADDITIONAL_FOLDER}"
            ln -s "${WORKING_DIRECTORY}/${ADDITIONAL_FOLDER}" "${IGNITION_INSTALL_LOCATION}/data/"
            log_info "Creating workdir folder for ${ADDITIONAL_FOLDER}"
            mkdir -p "${WORKING_DIRECTORY}/${ADDITIONAL_FOLDER}"
        fi
    done
}

################################################################################
# Copy and register modules
################################################################################
copy_modules_to_user_lib() {
    if ! ls /modules/*.modl 1>/dev/null 2>&1; then
        log_info "No additional modules found in /modules"
        return
    fi

    cp -r /modules/*.modl "${IGNITION_INSTALL_LOCATION}/user-lib/modules/"
    for module in /modules/*.modl; do
        if [ -f "$module" ]; then
            /usr/local/bin/register-module.sh -f "$module" -d "$DB_LOCATION"
        fi
    done
}

################################################################################
# Handle gateway backup to extract config.idb
################################################################################
handle_gateway_backup() {
    local backup_file="/tmp/gateway_backup.gwbk"
    if [[ " ${args[*]} " =~ " -r " ]]; then
        local user_backup
        user_backup=$(echo "${args[*]}" | sed -n 's/.*-r \([^ ]*\).*/\1/p')
        if [ -f "$user_backup" ]; then
            cp "$user_backup" "$backup_file"
        else
            log_info "User-provided backup not found. Using default."
            cp /base.gwbk "$backup_file"
        fi
    else
        cp /base.gwbk "$backup_file"
    fi

    mkdir -p "${IGNITION_INSTALL_LOCATION}/data/db"
    if unzip -p "$backup_file" db_backup_sqlite.idb > "${IGNITION_INSTALL_LOCATION}/data/db/config.idb"; then
        log_info "Extracted config.idb from backup"
    else
        log_error "Failed to extract config.idb"
        exit 1
    fi

    export DB_LOCATION="${IGNITION_INSTALL_LOCATION}/data/db/config.idb"
}

################################################################################
# Enable developer mode args
################################################################################
add_developer_mode_args() {
    wrapper_args_map+=(["-Dia.developer.moduleupload"]="true")
    wrapper_args_map+=(["-Dignition.allowunsignedmodules"]="true")
}

################################################################################
# Prepare launch arguments
################################################################################
prepare_launch_args() {
    local wrapper_args=()
    for key in "${!wrapper_args_map[@]}"; do
        wrapper_args+=("${key}=${wrapper_args_map[${key}]}")
        log_info "Collected wrapper arg: ${key}=${wrapper_args_map[${key}]}"
    done

    local jvm_args=()
    for key in "${!jvm_args_map[@]}"; do
        jvm_args+=("${key}" "${jvm_args_map[${key}]}")
        log_info "Collected JVM arg: ${key} ${jvm_args_map[${key}]}"
    done

    if [[ " ${args[*]} " =~ " -- " ]]; then
        args=("${args[@]/#-- /-- ${jvm_args[*]} }")
    else
        args+=("${jvm_args[@]}")
    fi

    [[ ! " ${args[*]} " =~ " -- " ]] && args+=("--")
    args+=("${wrapper_args[@]}")
}

################################################################################
# Execute the entrypoint
################################################################################
entrypoint() {
    if [ ! -e /usr/local/bin/docker-entrypoint.sh ]; then
        mv docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
    fi

    log_info "Launching Ignition with args: $*"
    exec docker-entrypoint.sh "$@"
}

main "${args[@]}"