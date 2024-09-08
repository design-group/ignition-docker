#!/usr/bin/env bash

# shellcheck source=/usr/local/bin/script-utils.sh
# shellcheck disable=SC1091
source /usr/local/bin/script-utils.sh

# Enable error handling
trap handle_error ERR

# Global variables
declare -u AUTH_SALT
GATEWAY_ADMIN_USERNAME=""
SECRET_LOCATION=""
DB_LOCATION=""
DB_FILE=""
verbose=0

###############################################################################
# Main function to register the password
###############################################################################
main() {
	if [ ! -f "${SECRET_LOCATION}" ]; then
		return 0 # Silently exit if there is no secret at target path
	elif [ ! -f "${DB_LOCATION}" ]; then
		log_warning "${DB_FILE} not found, skipping password registration"
		return 0
	fi

	register_password
}

###############################################################################
# Updates the target Config DB with the target username and salted pw hash
###############################################################################
register_password() {
	log_info "Registering Admin Password with Configuration DB"

	local password_hash password_input

	# Generate Salted PW Hash
	password_input="$(<"${SECRET_LOCATION}")"
	if [[ "${password_input}" =~ ^\[[0-9A-F]{8,}][0-9a-f]{64}$ ]]; then
		[ "$verbose" = 1 ] && log_info "Password is already hashed"
		password_hash="${password_input}"
	else
		password_hash=$(generate_salted_hash "$password_input")
	fi

	# Update INTERNALUSERTABLE
	sqlite3 "${DB_LOCATION}" "UPDATE INTERNALUSERTABLE SET USERNAME='${GATEWAY_ADMIN_USERNAME}', PASSWORD='${password_hash}' WHERE PROFILEID=1 AND USERID=1;"

	log_info "Admin password registered successfully"
}

###############################################################################
# Processes password input and translates to salted hash
###############################################################################
generate_salted_hash() {
	local password_input="$1"
	local auth_password

	[ "$verbose" = 1 ] && log_info "Generating salted hash with salt: ${AUTH_SALT}"
	auth_pwsalthash=$(printf %s "${password_input}${AUTH_SALT}" | sha256sum - | cut -c -64)
	auth_password="[${AUTH_SALT}]${auth_pwsalthash}"

	echo "${auth_password}"
}

###############################################################################
# Print usage information
###############################################################################
usage() {
	echo "Usage: $0 -u <string> -f <path/to/file> -d <path/to/db> [-s <salt_method>] [-v]"
	echo "  -u <string>        Gateway Admin Username"
	echo "  -f <path/to/file>  Path to secret file containing password or salted hash"
	echo "  -d <path/to/db>    Path to Ignition Configuration DB"
	echo "  -s <salt method>   Salt method, either 'timestamp' or 'random' (default)"
	echo "  -v                 Enable verbose mode"
	echo "  -h                 Display this help message"
}

# Argument Processing
while getopts ":hvu:f:d:s:" opt; do
	case "$opt" in
	v) verbose=1 ;;
	u) GATEWAY_ADMIN_USERNAME="${OPTARG}" ;;
	f) SECRET_LOCATION="${OPTARG}" ;;
	d)
		DB_LOCATION="${OPTARG}"
		DB_FILE=$(basename "${DB_LOCATION}")
		;;
	s) case "${OPTARG}" in
		timestamp) AUTH_SALT=$(date +%s | sha256sum | head -c 8) ;;
		random) ;; # no-op, default will be set below
		*)
			log_error "Invalid salt method: ${OPTARG}"
			usage
			exit 1
			;;
		esac ;;
	h)
		usage
		exit 0
		;;
	\?)
		log_error "Invalid option: -${OPTARG}"
		usage
		exit 1
		;;
	:)
		log_error "Option -${OPTARG} requires an argument"
		usage
		exit 1
		;;
	esac
done

shift $((OPTIND - 1))

# Check for required arguments
if [ -z "${GATEWAY_ADMIN_USERNAME:-}" ] || [ -z "${SECRET_LOCATION:-}" ] || [ -z "${DB_LOCATION:-}" ]; then
	log_error "Missing required arguments"
	usage
	exit 1
fi

# Set default for AUTH_SALT if not already set
if [[ -z ${AUTH_SALT+x} ]]; then
	AUTH_SALT=$(od -An -v -t x1 -N 4 /dev/random | tr -d ' ')
fi

# Run the main function
main
