#!/usr/bin/env bash

# shellcheck source=/usr/local/bin/script-utils.sh
# shellcheck disable=SC1091
source /usr/local/bin/script-utils.sh

# Enable error handling
trap handle_error ERR

# Global variables
GATEWAY_ENCODING_KEY=${GATEWAY_ENCODING_KEY:-}
GATEWAY_ENCODING_KEY_ISHEX=false
password_input=""

###############################################################################
# Main function to process and encode the password
###############################################################################
main() {
  if [[ -t 0 && -z ${password_input} ]]; then
    read -rsp "Password: " password_input
    echo
  elif [[ -z ${password_input} ]]; then
    password_input=$(</dev/stdin)
  fi

  # Encrypt and encode the password
  local encoded_password
  encoded_password=$(encrypt_and_encode "${password_input}" "${GATEWAY_ENCODING_KEY}")
  echo -n "${encoded_password}"
}

###############################################################################
# Prechecks to ensure required commands are available
###############################################################################
prechecks() {
  local required_commands=(openssl xxd)

  for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
      log_error "$cmd is required but not available, aborting."
      exit 1
    fi
  done
}

###############################################################################
# Encrypts and encodes the input string using the provided encoding key
###############################################################################
encrypt_and_encode() {
    local to_encrypt="$1"
    local encoding_key="$2"
    local xxd_command=(xxd -c 0 -ps)
    local hex_encoding_key

    if [ "${GATEWAY_ENCODING_KEY_ISHEX}" = true ]; then
      hex_encoding_key="${encoding_key}"
    else
      hex_encoding_key=$(echo -n "$encoding_key" | "${xxd_command[@]}")
    fi

    # Suppress the "hex string is too long" message
    echo -n "${to_encrypt}" | openssl enc -des-ede3-ecb -K "${hex_encoding_key}" -nosalt 2>/dev/null | "${xxd_command[@]}"
}

###############################################################################
# Retrieves an environment variable from a file if available
###############################################################################
file_env() {
    local var="$1"
    local fileVar="${var}_FILE"
    local def="${2:-}"

    if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
        log_error "Both $var and $fileVar are set (but are exclusive)"
        exit 1
    fi

    local val="$def"
    if [ "${!var:-}" ]; then
        val="${!var}"
    elif [ "${!fileVar:-}" ]; then
        val="$(< "${!fileVar}")"
    fi

    if [[ -n "${val:-}" ]]; then
        export "$var"="$val"
    fi
    unset "$fileVar"
}

###############################################################################
# Print usage information
###############################################################################
usage() {
  echo "Produces an EncodedStringField value using the supplied encoding key."
  echo
  echo "Usage: $0 [-p <string>] [-e <encoding key env var>] [-k <encoding key>] [-x] [-h]"
  echo "  -p <string>       String to encrypt and encode (will prompt if not provided)"
  echo "  -e <env var>      Environment variable containing the encoding key"
  echo "  -k <string>       Encoding key (must be >=24 chars)"
  echo "  -x                Encoding key is already in hex format (e.g. abcdef0102...)"
  echo "  -h                Print this help message"
  echo
  echo "NOTE: the output does _not_ contain a trailing newline. Some shells may display a % character"
  echo "      at the end of the output, which can be ignored."
}

# Argument Processing
while getopts ":p:e:k:hx" opt; do
  case ${opt} in
    p) password_input=${OPTARG} ;;
    e) file_env "${OPTARG}"
       GATEWAY_ENCODING_KEY=${!OPTARG} ;;
    k) GATEWAY_ENCODING_KEY="${OPTARG}" ;;
    h) usage
       exit 0 ;;
    x) GATEWAY_ENCODING_KEY_ISHEX=true ;;
    \?) log_error "Invalid option: $OPTARG"
        usage
        exit 1 ;;
    :) log_error "Invalid option: $OPTARG requires an argument"
       usage
       exit 1 ;;
  esac
done

# Exit on missing encoding key
if [ -z "${GATEWAY_ENCODING_KEY}" ]; then
  log_error "Encoding key is required but was either unspecified or blank"
  usage
  exit 1
fi

# Run prechecks and the main routine
prechecks
main