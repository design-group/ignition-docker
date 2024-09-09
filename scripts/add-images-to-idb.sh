#!/usr/bin/env bash

# shellcheck source=/usr/local/bin/script-utils.sh
# shellcheck disable=SC1091
source /usr/local/bin/script-utils.sh

# Enable error handling
trap handle_error ERR

# Global variables
DB_LOCATION=${DB_LOCATION:-"${IGNITION_INSTALL_LOCATION}/data/db/config.idb"}
IMAGE_DIR="/idb-images"

###############################################################################
# Main function to process and add/update images in IDB
###############################################################################
main() {
	if [ ! -d "$IMAGE_DIR" ]; then
		log_warning "Image directory $IMAGE_DIR not found. Skipping image processing."
		return 0
	fi

	log_info "Processing images in $IMAGE_DIR"
	process_directory "$IMAGE_DIR"
}

###############################################################################
# Get image dimensions
###############################################################################
get_image_dimensions() {
	local file_path="$1"
	local file_type="$2"

	if [ "$file_type" = "SVG" ]; then
		echo "0 0"
	else
		file "$file_path" | grep -oP '\d+\s*x\s*\d+' | sed 's/x/ /' || echo "0 0"
	fi
}

###############################################################################
# Ensure trailing slash in path
###############################################################################
ensure_trailing_slash() {
	local path="$1"
	[[ "$path" != */ ]] && path="${path}/"
	echo "$path"
}

###############################################################################
# Add or update an item (file or directory) in the database
###############################################################################
update_or_add_item_to_db() {
	local item_path="$1"
	local relative_path="${item_path#"${IMAGE_DIR}"/}"
	local item_name
	item_name=$(basename "$item_path")
	local parent_dir
	parent_dir=$(dirname "$relative_path")
	local file_type
	local width=0
	local height=0
	local file_size=0
	local data_value="NULL"

	# Set parent to NULL if it's in the root directory, otherwise ensure trailing slash
	local parent_value
	if [ "$parent_dir" = "." ]; then
		parent_value="NULL"
	else
		parent_value="'$(ensure_trailing_slash "$parent_dir")'"
	fi

	if [ -d "$item_path" ]; then
		file_type="NULL"
		relative_path=$(ensure_trailing_slash "$relative_path")
	else
		local file_extension="${item_name##*.}"
		case "${file_extension,,}" in
		png) file_type="'PNG'" ;;
		jpg | jpeg) file_type="'JPG'" ;;
		gif) file_type="'GIF'" ;;
		svg) file_type="'SVG'" ;;
		*)
			log_warning "Unsupported file type: $file_extension"
			return
			;;
		esac
		read -r width height < <(get_image_dimensions "$item_path" "${file_type//\'/}")
		file_size=$(stat -c%s "$item_path")
		data_value="readfile('$item_path')"
	fi

	# Check if the item already exists in the database
	local existing_item
	existing_item=$(sqlite3 "$DB_LOCATION" "SELECT COUNT(*) FROM IMAGES WHERE PATH='$relative_path'")

	local sql_statement
	if [ "$existing_item" -eq 0 ]; then
		# Insert new item
		sql_statement="INSERT INTO IMAGES (PATH, TYPE, DESCRIPTION, PARENT, DATA, WIDTH, HEIGHT, SIZE) VALUES ('$relative_path', $file_type, '', $parent_value, $data_value, $width, $height, $file_size);"
		log_info "Adding new item: $relative_path"
	else
		# Update existing item
		sql_statement="UPDATE IMAGES SET TYPE=$file_type, PARENT=$parent_value, DATA=$data_value, WIDTH=$width, HEIGHT=$height, SIZE=$file_size WHERE PATH='$relative_path';"
		log_info "Updating existing item: $relative_path"
	fi

	if sqlite3 "$DB_LOCATION" "$sql_statement"; then
		log_info "Successfully processed item: $relative_path"
	else
		log_error "Failed to process item: $relative_path"
	fi
}

###############################################################################
# Process a directory recursively
###############################################################################
process_directory() {
	local dir="$1"

	# Skip processing if the directory is named "Builtin"
	if [[ "$(basename "$dir")" == "Builtin" ]]; then
		log_info "Skipping Builtin directory: $dir"
		return
	fi

	# Add or update the directory itself in the database, except for the root directory
	if [ "$dir" != "$IMAGE_DIR" ]; then
		update_or_add_item_to_db "$dir"
	fi

	# Process all files and subdirectories
	for item in "$dir"/*; do
		if [ -d "$item" ]; then
			process_directory "$item"
		elif [ -f "$item" ]; then
			update_or_add_item_to_db "$item"
		fi
	done
}

# Run the main function
main
