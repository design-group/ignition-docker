#!/usr/bin/env bash

declare GATEWAY_ENCODING_KEY=${GATEWAY_ENCODING_KEY:-}
declare GATEWAY_ENCODING_KEY_ISHEX=false

###############################################################################
# Processes password input and translates to encoded string value
###############################################################################
function main() {
  if [[ -t 0 && -z ${password_input+x} ]]; then
    read -rsp "Password: " password_input
    echo
  elif [[ -z ${password_input+x} ]]; then
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
function prechecks() {
  local required_commands=(
    openssl
    xxd
  )

  for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
      echo "$cmd is required but not available, aborting."
      exit 1
    fi
  done
}

###############################################################################
# Encrypts and encodes the input string using the provided encoding key
# usage: encrypt_and_encode <to_encrypt_string> <encoding_key_string>
###############################################################################
function encrypt_and_encode() {
    local to_encrypt="$1"
    local encoding_key="$2"
    local xxd_command=( xxd -c 0 -ps )
    local hex_encoding_key
    if [ "${GATEWAY_ENCODING_KEY_ISHEX}" = true ]; then
      hex_encoding_key="${encoding_key}"
    else
      hex_encoding_key=$(echo -n "$encoding_key" | "${xxd_command[@]}")
    fi
    echo -n "${to_encrypt}" | openssl enc -des-ede3-ecb -K "${hex_encoding_key}" -nosalt | "${xxd_command[@]}"
}

###############################################################################
# Retrieves an environment variable from a file if available
# usage: file_env VAR [DEFAULT]
#    ie: file_env 'GATEWAY_ENCODING_KEY' 'example'
# (will allow for "$GATEWAY_ENCODING_KEY_FILE" to fill in the value of
#  "$GATEWAY_ENCODING_KEY" from a file, useful for Docker's secrets feature)
###############################################################################
file_env() {
    local var="$1"
    local fileVar="${var}_FILE"
    local def="${2:-}"
    if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
        error "both $var and $fileVar are set (but are exclusive)"
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
# Outputs to stderr and exits with error code
###############################################################################
function error() {
  >&2 info "ERROR: $*"
  exit 1
}

###############################################################################
# Print usage information
###############################################################################
function usage() {
  >&2 echo "Produces an EncodedStringField value using the supplied encoding key."
  >&2 echo
  >&2 echo "Usage: $0 [-p <string>] [-e <encoding key env var>] [-k <encoding key>] [-v] [-h]"
  >&2 echo "  -p <string>       String to encrypt and encode (will prompt if not provided)"
  >&2 echo "  -e <env var>      Environment variable containing the encoding key"
  >&2 echo "  -k <string>       Encoding key (must be >=24 chars)"
  >&2 echo "  -x                Encoding key is already in hex format (e.g. abcdef0102...)"
  >&2 echo "  -h                Print this help message"
  >&2 echo
  >&2 echo "NOTE: the output does _not_ contain a trailing newline.  Some shells may display a % character"
  >&2 echo "      at the end of the output, which can be ignored."
}

# Argument Processing
while getopts ":p:e:k:hx" opt; do
  case ${opt} in
    p)
      password_input=${OPTARG}
      ;;
    e)
      file_env "${OPTARG}"
      GATEWAY_ENCODING_KEY=${!OPTARG}
      ;;
    k)
      GATEWAY_ENCODING_KEY="${OPTARG}"
      ;;
    h)
      usage
      exit 0
      ;;
    x)
      GATEWAY_ENCODING_KEY_ISHEX=true
      ;;
    \?)
      echo "Invalid option: $OPTARG" >&2
      usage
      exit 1
      ;;
    :)
      echo "Invalid option: $OPTARG requires an argument" >&2
      usage
      exit 1
      ;;
  esac
done

# exit on missing encoding key
if [ -z "${GATEWAY_ENCODING_KEY}" ]; then
  echo "Encoding key is required but was either unspecified or blank" >&2
  usage
  exit 1
fi

# Run prechecks and the main routine
prechecks
main