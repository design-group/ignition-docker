#!/usr/bin/env bash

# shellcheck source=/usr/local/bin/script-utils.sh
# shellcheck disable=SC1091
source /usr/local/bin/script-utils.sh

# Enable error handling
trap handle_error ERR

# Global variables
DB_LOCATION=${DB_LOCATION:-"${IGNITION_INSTALL_LOCATION}/data/db/config.idb"}
LOCALIZATION_DIR="/localization"
PROPERTIES_JSON="${LOCALIZATION_DIR}/properties.json"
TEMP_SQL_FILE="/tmp/localization_batch.sql"
BATCH_SIZE=1100

###############################################################################
# Main function to process localization files and update database
###############################################################################
main() {
    if [ ! -d "$LOCALIZATION_DIR" ]; then
        log_warning "Localization directory $LOCALIZATION_DIR not found. Skipping localization processing."
        return 0
    fi

    setup_translation_settings
    process_localization_files
}

###############################################################################
# Setup translation settings in the database
###############################################################################
setup_translation_settings() {
    local is_case_insensitive is_ignore_whitespace is_ignore_punctuation is_ignore_tags

    if [ -f "$PROPERTIES_JSON" ]; then
        is_case_insensitive=$(jq -r '.caseInsensitive // false' "$PROPERTIES_JSON")
        is_ignore_whitespace=$(jq -r '.ignoreWhitespace // false' "$PROPERTIES_JSON")
        is_ignore_punctuation=$(jq -r '.ignorePunctuation // false' "$PROPERTIES_JSON")
        is_ignore_tags=$(jq -r '.ignoreTags // false' "$PROPERTIES_JSON")
    else
        is_case_insensitive=false
        is_ignore_whitespace=false
        is_ignore_punctuation=false
        is_ignore_tags=false
    fi

    sqlite3 "$DB_LOCATION" <<EOF
INSERT OR REPLACE INTO TRANSLATIONSETTINGS (
    TRANSLATIONSETTINGS_ID, ISCASEINSENSATIVE, IGNOREWHITESPACE, IGNOREPUNCTUATION, IGNORETAGS
) VALUES (
    0, $is_case_insensitive, $is_ignore_whitespace, $is_ignore_punctuation, $is_ignore_tags
);
EOF
}

###############################################################################
# Process all localization files in the directory
###############################################################################
process_localization_files() {
    local file
    for file in "$LOCALIZATION_DIR"/*; do
        if [ -f "$file" ]; then
            local extension="${file##*.}"
            case "${extension,,}" in # Convert to lowercase for case-insensitive comparison
            properties)
                process_properties_file "$file"
                ;;
            xml)
                process_xml_file "$file"
                ;;
            json)
                # if its the `properties.json` file, then ignore it, else warn
                if [ "$file" != "$PROPERTIES_JSON" ]; then
                    log_warning "Unsupported file type: $file"
                fi
                ;;
            *)
                log_warning "Unsupported file type: $file"
                ;;
            esac
        fi
    done
}

###############################################################################
# Process a .properties file
###############################################################################
process_properties_file() {
    local file="$1"
    local locale
    locale=$(sed -n 's/^#Locale: //p' "$file" | tr -d '\r')

    if [ -z "$locale" ]; then
        log_error "Locale not found in file: $file"
        return 1
    fi

    log_info "Processing .properties file: $file (Locale: $locale)"

    # Read file content into an array
    mapfile -t lines < "$file"

    # Initialize batch processing
    echo "BEGIN TRANSACTION;" > "$TEMP_SQL_FILE"
    local count=0

    # Process each line
    for line in "${lines[@]}"; do
        # Ignore comments and empty lines
        [[ $line == \#* ]] && continue
        [[ -z $line ]] && continue

        # Split line into key and value
        IFS='=' read -r key value <<< "$line"

        key=${key// /}
        value=${value#"${value%%[![:space:]]*}"}
        insert_or_update_translation "$key" "$value" "$locale"

        ((count++))
        if [ $count -eq $BATCH_SIZE ]; then
            execute_batch
            count=0
        fi
    done

    # Execute any remaining statements
    if [ $count -gt 0 ]; then
        execute_batch
    fi
}

###############################################################################
# Process an XML file
###############################################################################
process_xml_file() {
    local file="$1"
    local locale
    locale=$(sed -n 's/.*<comment>Locale: \(.*\)<\/comment>.*/\1/p' "$file")

    if [ -z "$locale" ]; then
        log_error "Locale not found in file: $file"
        return 1
    fi

    log_info "Processing XML file: $file (Locale: $locale)"

    # Initialize batch processing
    echo "BEGIN TRANSACTION;" > "$TEMP_SQL_FILE"
    local count=0

    sed -n 's/.*<entry key="\([^"]*\)">\(.*\)<\/entry>.*/\1=\2/p' "$file" | while IFS='=' read -r key value; do
        insert_or_update_translation "$key" "$value" "$locale"
        
        ((count++))
        if [ $count -eq $BATCH_SIZE ]; then
            execute_batch
            count=0
        fi
    done

    # Execute any remaining statements
    if [ $count -gt 0 ]; then
        execute_batch
    fi
}

###############################################################################
# Insert or update a translation in the database
###############################################################################
insert_or_update_translation() {
    local key="$1"
    local value="$2"
    local locale="$3"

    # Escape single quotes in key and value
    key="${key//\'/\'\'}"
    value="${value//\'/\'\'}"

    # Append SQL statements to the temporary file
    cat <<EOF >> "$TEMP_SQL_FILE"
INSERT OR IGNORE INTO TRANSLATIONTERMS (TRANSLATIONTERMS_ID, TERMID, TEXTVALUE, LOCALE)
SELECT (SELECT COALESCE(MAX(TRANSLATIONTERMS_ID), 0) + 1 FROM TRANSLATIONTERMS),
       (SELECT COALESCE(MAX(TERMID), 0) + 1 FROM TRANSLATIONTERMS),
       '$key', NULL
WHERE NOT EXISTS (SELECT 1 FROM TRANSLATIONTERMS WHERE TEXTVALUE='$key' AND LOCALE IS NULL);

INSERT OR REPLACE INTO TRANSLATIONTERMS (TRANSLATIONTERMS_ID, TERMID, TEXTVALUE, LOCALE)
SELECT (SELECT COALESCE(MAX(TRANSLATIONTERMS_ID), 0) + 1 FROM TRANSLATIONTERMS),
       (SELECT TERMID FROM TRANSLATIONTERMS WHERE TEXTVALUE='$key' AND LOCALE IS NULL),
       '$value', '$locale';

UPDATE SEQUENCES SET val = (SELECT MAX(TRANSLATIONTERMS_ID) FROM TRANSLATIONTERMS) WHERE name='TRANSLATIONTERMS_SEQ';
EOF
}

###############################################################################
# Execute the batch of SQL statements
###############################################################################
execute_batch() {
    echo "COMMIT;" >> "$TEMP_SQL_FILE"
    sqlite3 "$DB_LOCATION" < "$TEMP_SQL_FILE"
    echo "BEGIN TRANSACTION;" > "$TEMP_SQL_FILE"
}

###############################################################################
# Get the next available ID for a table
###############################################################################
get_next_id() {
    local table_name="$1"
    local id_column="$2"
    local next_id
    next_id=$(sqlite3 "$DB_LOCATION" "SELECT COALESCE(MAX($id_column), 0) + 1 FROM $table_name;")

    # Ensure the ID is unique
    while [[ $(sqlite3 "$DB_LOCATION" "SELECT COUNT(*) FROM $table_name WHERE $id_column = $next_id;") -ne 0 ]]; do
        next_id=$((next_id + 1))
    done

    echo "$next_id"
}

# Run the main function
main
