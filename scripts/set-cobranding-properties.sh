#!/usr/bin/env bash

# shellcheck source=/usr/local/bin/script-utils.sh
# shellcheck disable=SC1091
source /usr/local/bin/script-utils.sh

# Enable error handling
trap handle_error ERR

# Global variables
DB_LOCATION=${DB_LOCATION:-"${IGNITION_INSTALL_LOCATION}/data/db/config.idb"}
CO_BRANDING_DIR="/co-branding"
CO_BRANDING_JSON="${CO_BRANDING_DIR}/co-branding.json"

###############################################################################
# Main function to process co-branding configuration
###############################################################################
main() {
	if [ ! -f "$CO_BRANDING_JSON" ]; then
		log_warning "Co-branding configuration file not found: $CO_BRANDING_JSON"
		return 1
	fi

	process_cobranding
}

###############################################################################
# Get image MIME type
###############################################################################
get_image_type() {
	local image_path="$1"
	local file_extension="${image_path##*.}"
	case "${file_extension,,}" in
	png) echo "image/png" ;;
	svg) echo "image/svg+xml" ;;
	*) echo "application/octet-stream" ;; # Default MIME type for unknown files
	esac
}

###############################################################################
# Get image name
###############################################################################
get_image_name() {
	local image_path="$1"
	basename "$image_path"
}

###############################################################################
# Get image dimensions
###############################################################################
get_image_dimensions() {
	local file_path="$1"
	local file_type="$2"

	if [ "$file_type" = "image/svg+xml" ]; then
		echo "0 0"
	else
		file "$file_path" | grep -oP '\d+\s*x\s*\d+' | sed 's/x/ /' || echo "0 0"
	fi
}

###############################################################################
# Check if COBRANDING row exists
###############################################################################
check_cobranding_exists() {
	local count
	count=$(sqlite3 "$DB_LOCATION" "SELECT COUNT(*) FROM COBRANDING WHERE ID = 0;")
	[ "$count" -gt 0 ]
}

###############################################################################
# Insert or update COBRANDING table
###############################################################################
upsert_cobranding() {
	local enabled="$1"
	local background_color="$2"
	local text_color="$3"
	local button_color="$4"
	local button_text_color="$5"
	local logo_path="$6"
	local favicon_path="$7"
	local app_icon_path="$8"
	local logo_type="$9"
	local favicon_type="${10}"
	local app_icon_type="${11}"
	local logo_name="${12}"
	local favicon_name="${13}"
	local app_icon_name="${14}"
	local favicon_size="${15}"
	local app_icon_size="${16}"

	local sql_statement

	if check_cobranding_exists; then
		# Update existing row
		sql_statement="UPDATE COBRANDING SET
            ENABLED = $enabled,
            BACKGROUNDCOLOR = '$background_color',
            TEXTCOLOR = '$text_color',
            BUTTONCOLOR = '$button_color',
            BUTTONTEXTCOLOR = '$button_text_color',
            LOGO = CASE WHEN '$logo_path' = 'NULL' THEN NULL ELSE readfile('$logo_path') END,
            FAVICON = CASE WHEN '$favicon_path' = 'NULL' THEN NULL ELSE readfile('$favicon_path') END,
            APPICON = CASE WHEN '$app_icon_path' = 'NULL' THEN NULL ELSE readfile('$app_icon_path') END,
            LOGOTYPE = '$logo_type',
            LOGONAME = '$logo_name',
            FAVICONNAME = '$favicon_name',
            APPICONNAME = '$app_icon_name',
            FAVICONSIZE = '$favicon_size',
            APPICONSIZE = '$app_icon_size'
        WHERE ID = 0;"
	else
		# Insert new row
		sql_statement="INSERT INTO COBRANDING (
            ID, ENABLED, BACKGROUNDCOLOR, TEXTCOLOR, BUTTONCOLOR, BUTTONTEXTCOLOR,
            LOGO, FAVICON, APPICON, LOGOTYPE, LOGONAME, FAVICONNAME, APPICONNAME, FAVICONSIZE, APPICONSIZE
        ) VALUES (
            0, $enabled, '$background_color', '$text_color', '$button_color', '$button_text_color',
            CASE WHEN '$logo_path' = 'NULL' THEN NULL ELSE readfile('$logo_path') END,
            CASE WHEN '$favicon_path' = 'NULL' THEN NULL ELSE readfile('$favicon_path') END,
            CASE WHEN '$app_icon_path' = 'NULL' THEN NULL ELSE readfile('$app_icon_path') END,
            '$logo_type', '$logo_name', '$favicon_name', '$app_icon_name', '$favicon_size', '$app_icon_size'
        );"
	fi

	# Execute the SQL statement
	if sqlite3 "$DB_LOCATION" "$sql_statement"; then
		log_info "Co-branding configuration updated successfully"
	else
		log_error "Failed to update co-branding configuration"
		return 1
	fi
}

###############################################################################
# Process co-branding configuration
###############################################################################
process_cobranding() {
	local enabled background_color text_color button_color button_text_color
	local logo_path favicon_path app_icon_path
	local logo_type favicon_type app_icon_type
	local logo_name favicon_name app_icon_name
	local favicon_size app_icon_size

	enabled=$(jq -r '.enabled // false' "$CO_BRANDING_JSON")
	background_color=$(jq -r '.backgroundColor // "#697077"' "$CO_BRANDING_JSON")
	text_color=$(jq -r '.textColor // "#FFFFFF"' "$CO_BRANDING_JSON")
	button_color=$(jq -r '.buttonColor // "#0C7BB3"' "$CO_BRANDING_JSON")
	button_text_color=$(jq -r '.buttonTextColor // "#FFFFFF"' "$CO_BRANDING_JSON")
	logo_path=$(jq -r '.logoPath // "NULL"' "$CO_BRANDING_JSON")
	favicon_path=$(jq -r '.faviconPath // "NULL"' "$CO_BRANDING_JSON")
	app_icon_path=$(jq -r '.appIconPath // "NULL"' "$CO_BRANDING_JSON")

	if [ -f "$logo_path" ]; then
		logo_type=$(get_image_type "$logo_path")
		logo_name=$(get_image_name "$logo_path")
	else
		logo_path="NULL"
		logo_type="NULL"
		logo_name="NULL"
	fi

	if [ -f "$favicon_path" ]; then
		favicon_type=$(get_image_type "$favicon_path")
		favicon_name=$(get_image_name "$favicon_path")
		read -r favicon_width favicon_height < <(get_image_dimensions "$favicon_path" "$favicon_type")
		favicon_size="${favicon_width}x${favicon_height}"
	else
		favicon_path="NULL"
		favicon_type="NULL"
		favicon_name="NULL"
		favicon_size="NULL"
	fi

	if [ -f "$app_icon_path" ]; then
		app_icon_type=$(get_image_type "$app_icon_path")
		app_icon_name=$(get_image_name "$app_icon_path")
		read -r app_icon_width app_icon_height < <(get_image_dimensions "$app_icon_path" "$app_icon_type")
		app_icon_size="${app_icon_width}x${app_icon_height}"
	else
		app_icon_path="NULL"
		app_icon_type="NULL"
		app_icon_name="NULL"
		app_icon_size="NULL"
	fi

	upsert_cobranding "$enabled" \
		"$background_color" \
		"$text_color" \
		"$button_color" \
		"$button_text_color" \
		"$logo_path" \
		"$favicon_path" \
		"$app_icon_path" \
		"$logo_type" \
		"$favicon_type" \
		"$app_icon_type" \
		"$logo_name" \
		"$favicon_name" \
		"$app_icon_name" \
		"$favicon_size" \
		"$app_icon_size"
}

# Run the main function
main
