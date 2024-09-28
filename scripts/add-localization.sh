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

main() {
    if [ ! -d "$LOCALIZATION_DIR" ]; then
        log_warning "Localization directory $LOCALIZATION_DIR not found. Skipping localization processing."
        return 0
	fi

    setup_translation_settings
    process_localization_files
}

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

process_localization_files() {
    local file
    echo "BEGIN TRANSACTION;" > "$TEMP_SQL_FILE"
    for file in "$LOCALIZATION_DIR"/*; do
        if [ -f "$file" ]; then
            local extension="${file##*.}"
            case "${extension,,}" in
            properties)
                process_properties_file "$file"
                ;;
            xml)
                process_xml_file "$file"
                ;;
            json)
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
    echo "COMMIT;" >> "$TEMP_SQL_FILE"
    sqlite3 "$DB_LOCATION" < "$TEMP_SQL_FILE"
}

process_properties_file() {
    local file="$1"
    local locale
    locale=$(sed -n 's/^#Locale: //p' "$file" | tr -d '\r')

    if [ -z "$locale" ]; then
        log_error "Locale not found in file: $file"
        return 1
    fi

    log_info "Processing .properties file: $file (Locale: $locale)"

    sed -n '/^[^#]/s/^\([^=]*\)=\(.*\)$/\1|\2/p' "$file" | while IFS='|' read -r key value; do
        insert_or_update_translation "$key" "$value" "$locale"
    done
}

process_xml_file() {
    local file="$1"
    local locale
    locale=$(sed -n 's/.*<comment>Locale: \(.*\)<\/comment>.*/\1/p' "$file")

    if [ -z "$locale" ]; then
        log_error "Locale not found in file: $file"
        return 1
    fi

    log_info "Processing XML file: $file (Locale: $locale)"

    sed -n 's/.*<entry key="\([^"]*\)">\(.*\)<\/entry>.*/\1|\2/p' "$file" | while IFS='|' read -r key value; do
        insert_or_update_translation "$key" "$value" "$locale"
    done
}

insert_or_update_translation() {
    local key="$1"
    local value="$2"
    local locale="$3"

    key="${key//\'/\'\'}"
    value="${value//\'/\'\'}"

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
EOF
}

main