#!/usr/bin/env bash

# shellcheck source=/usr/local/bin/script-utils.sh
# shellcheck disable=SC1091
source /usr/local/bin/script-utils.sh

# Enable error handling
trap handle_error ERR

# Global variables
DB_LOCATION=${DB_LOCATION:-"${IGNITION_INSTALL_LOCATION}/data/db/config.idb"}
TRUNCATE_TABLES=${TRUNCATE_TABLES:-false}
DISABLE_ENTRIES=${DISABLE_ENTRIES:-true}
REENCODING_PASSWORD=${REENCODING_PASSWORD:-}

###############################################################################
# Main function to handle existing passwords in the IDB
###############################################################################
main() {
	if [ "$TRUNCATE_TABLES" = true ]; then
		truncate_tables
	elif [ "$DISABLE_ENTRIES" = true ]; then
		disable_entries
	else
		log_error "No action specified. Set either TRUNCATE_TABLES=true or DISABLE_ENTRIES=true"
		exit 1
	fi
}

###############################################################################
# Check if a table exists in the database
###############################################################################
table_exists() {
	local table_name="$1"
	local count
	count=$(sqlite3 "$DB_LOCATION" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='$table_name';")
	[ "$count" -eq 1 ]
}

###############################################################################
# Truncate relevant tables
###############################################################################
truncate_tables() {
	log_info "Truncating tables with password information"

	local tables=(
		"DATASOURCES"
		"SMTPSETTINGS"
		"CLASSICSMTPEMAILPROFILES"
		"EMAILNOTIFICATIONSETTINGS"
		"AUTHPROFILEPROPERTIES_AD"
		"AUTHPROFILEPROPERTIES_ADHYBRID"
		"AUTHPROFILEPROPERTIES_ADTODB"
		"ALERTNOTIFICATIONPROFILEPROPERTIES_BASIC"
		"ALERTNOTIFICATIONPROFILEPROPERTIES_DISTRIBUTION"
		"UACONNECTIONSETTINGS"
	)

	for table in "${tables[@]}"; do
		if table_exists "$table"; then
			sqlite3 "$DB_LOCATION" "DELETE FROM $table;"
		fi
	done

	if table_exists "SYSPROPS"; then
		sqlite3 "$DB_LOCATION" "UPDATE SYSPROPS SET ERRORREPORTPASSWORDE = NULL;"
	fi
}

###############################################################################
# Disable entries and reset passwords
###############################################################################
disable_entries() {
    log_info "Disabling entries and resetting passwords"

	 local encoded_password
	if [ -z "$REENCODING_PASSWORD" ]; then
		log_info "REENCODING_PASSWORD is not set. Generating a random password for re-encoding."

		local random_password
		random_password=$(openssl rand -base64 8)
	
		log_info "Random password: $random_password"
    	encoded_password=$(encode_password "$random_password")
	else
		log_info "REENCODING_PASSWORD is set. Using the provided password for re-encoding."
		encoded_password=$(encode_password "$REENCODING_PASSWORD")
	fi

    local updates=(
        "UPDATE DATASOURCES SET ENABLED = False, PASSWORDE = '$encoded_password'"
        "UPDATE SMTPSETTINGS SET PASSWORD = '$encoded_password'"
        "UPDATE CLASSICSMTPEMAILPROFILES SET PASSWORD = '$encoded_password'"
		"UPDATE EMAILNOTIFICATIONSETTINGS SET PASSWORDE = '$encoded_password'"
        "UPDATE AUTHPROFILEPROPERTIES_AD SET CONNECTIONPASSWORDE = '$encoded_password'"
        "UPDATE AUTHPROFILEPROPERTIES_ADHYBRID SET CONNECTIONPASSWORDE = '$encoded_password'"
        "UPDATE AUTHPROFILEPROPERTIES_ADTODB SET CONNECTIONPASSWORDE = '$encoded_password'"
        "UPDATE ALERTNOTIFICATIONPROFILEPROPERTIES_BASIC SET PASSWORD = '$encoded_password'"
        "UPDATE ALERTNOTIFICATIONPROFILEPROPERTIES_DISTRIBUTION SET PASSWORD = '$encoded_password'"
        "UPDATE SYSPROPS SET ERRORREPORTPASSWORDE = '$encoded_password'"
        "UPDATE UACONNECTIONSETTINGS SET ENABLED = False, PASSWORDE = '$encoded_password'"
    )

    for update in "${updates[@]}"; do
        local table_name
        table_name=$(echo "$update" | sed -n 's/UPDATE \([^ ]*\).*/\1/p')
        if table_exists "$table_name"; then
            if ! sqlite3 "$DB_LOCATION" "$update"; then
                log_warning "Failed to update table: $table_name"
            fi
        fi
    done
}

###############################################################################
# Print usage information
###############################################################################
usage() {
	echo "Usage: $0 [-t|-d]"
	echo "  -t  Truncate tables (TRUNCATE_TABLES=true)"
	echo "  -d  Disable entries and reset passwords (DISABLE_ENTRIES=true)"
	echo "  -h  Show this help message"
}

# Argument processing
while getopts ":tdh" opt; do
	case ${opt} in
	t)
		TRUNCATE_TABLES=true
		DISABLE_ENTRIES=false
		;;
	d)
		DISABLE_ENTRIES=true
		TRUNCATE_TABLES=false
		;;
	h)
		usage
		exit 0
		;;
	\?)
		log_error "Invalid option: $OPTARG"
		usage
		exit 1
		;;
	esac
done

# Run the main function
main