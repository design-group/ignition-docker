#!/usr/bin/env bash

# shellcheck source=/usr/local/bin/script-utils.sh
# shellcheck disable=SC1091
source /usr/local/bin/script-utils.sh

# Enable error handling
trap handle_error ERR

# Global variables
MODULE_LOCATION=""
DB_LOCATION=""
DB_FILE=""

###############################################################################
# Main function to register the module
###############################################################################
main() {
  if [ ! -f "${MODULE_LOCATION}" ]; then
    log_info "No module file found at ${MODULE_LOCATION}, skipping module registration"
    return 0
  elif [ ! -f "${DB_LOCATION}" ]; then
    log_warning "${DB_FILE} not found, skipping module registration"
    return 0
  fi

  register_module
}

###############################################################################
# Register the module with the target Config DB
###############################################################################
register_module() {
    # Populate CERTIFICATES table
    populate_certificates_table

    # Populate EULAS table
    populate_eulas_table
}

###############################################################################
# Populate the CERTIFICATES table
###############################################################################
populate_certificates_table() {
    local cert_info subject_name thumbprint next_certificates_id thumbprint_already_exists
    cert_info=$(unzip -qq -c "${MODULE_LOCATION}" certificates.p7b | keytool -printcert -v | head -n 9)
    thumbprint=$(echo "${cert_info}" | grep -A 2 "Certificate fingerprints" | grep SHA1 | cut -d : -f 2- | sed -e 's/://g' | awk '{$1=$1;print tolower($0)}')
    subject_name=$(echo "${cert_info}" | grep -m 1 -Po '^Owner: CN=\K(.+?)(?=, (OU|O|L|ST|C)=)' | sed -e 's/"//g')
    next_certificates_id=$(sqlite3 "${DB_LOCATION}" "SELECT COALESCE(MAX(CERTIFICATES_ID)+1,1) FROM CERTIFICATES")
    thumbprint_already_exists=$(sqlite3 "${DB_LOCATION}" "SELECT 1 FROM CERTIFICATES WHERE lower(hex(THUMBPRINT)) = '${thumbprint}'")
    
    if [ "${thumbprint_already_exists}" != "1" ]; then
      log_info "Inserting new module certificate with ID ${next_certificates_id} for subject '${subject_name}'"
      sqlite3 "${DB_LOCATION}" "INSERT INTO CERTIFICATES (CERTIFICATES_ID, THUMBPRINT, SUBJECTNAME) VALUES (${next_certificates_id}, x'${thumbprint}', '${subject_name}'); UPDATE SEQUENCES SET val=${next_certificates_id} WHERE name='CERTIFICATES_SEQ';"
    fi
}

###############################################################################
# Populate the EULAS table
###############################################################################
populate_eulas_table() {
    local next_eulas_id license_crc32 module_id
    local -i module_id_check
    next_eulas_id=$(sqlite3 "${DB_LOCATION}" "SELECT COALESCE(MAX(EULAS_ID)+1,1) FROM EULAS")
    license_filename=$(unzip -qq -c "${MODULE_LOCATION}" module.xml | grep -oP '(?<=<license>).*(?=</license)')
    license_crc32=$(unzip -qq -c "${MODULE_LOCATION}" "${license_filename}" | gzip -c | tail -c8 | od -t u4 -N 4 -A n | cut -c 2-)
    module_id=$(unzip -qq -c "${MODULE_LOCATION}" module.xml | grep -oP '(?<=<id>).*(?=</id)')
    module_id_check=$(sqlite3 "${DB_LOCATION}" "SELECT CASE WHEN CRC=${license_crc32} THEN -1 ELSE 1 END FROM EULAS WHERE MODULEID='${module_id}'")
    
    if (( module_id_check == 1 )); then
      log_info "Removing previous EULAS entries for MODULEID='${module_id}'"
      sqlite3 "${DB_LOCATION}" "DELETE FROM EULAS WHERE MODULEID='${module_id}';"
    fi
    
    if (( module_id_check >= 0 )); then
      sqlite3 "${DB_LOCATION}" "INSERT INTO EULAS (EULAS_ID, MODULEID, CRC) VALUES (${next_eulas_id}, '${module_id}', ${license_crc32}); UPDATE SEQUENCES SET val=${next_eulas_id} WHERE name='EULAS_SEQ';"
    fi
}

###############################################################################
# Print usage information
###############################################################################
usage() {
  echo "Usage: $0 -f <path/to/module> -d <path/to/db> [-v]"
  echo "  -f <path>  Path to the module file"
  echo "  -d <path>  Path to the database file"
  echo "  -h         Display this help message"
}

# Argument Processing
while getopts ":hf:d:" opt; do
  case "$opt" in
  f) MODULE_LOCATION="${OPTARG}" ;;
  d)
    DB_LOCATION="${OPTARG}"
    DB_FILE=$(basename "${DB_LOCATION}")
    ;;
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

# Shift positional args based on number consumed by getopts
shift $((OPTIND-1))

# Check for required arguments
if [ -z "${MODULE_LOCATION:-}" ] || [ -z "${DB_LOCATION:-}" ]; then
  log_error "Missing required arguments"
  usage
  exit 1
fi

# Run the main function
main