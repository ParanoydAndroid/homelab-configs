function get_homepage_config(){
# This function retrieves the file paths of a list of files that must
# be backed up in order to restore the homepage configuration.
# The function should one argument, which is the path to the base data folder.
# the function should get a list of the absolute path of files in the root directory that end in .yaml
# the function should return the list of files so the caller can save them.
    local base_data_folder="${1:-"/volume1/docker/homepage/data"}"
    local config_files=()
    
    # Check if the base data folder exists
    if [[ ! -d "$base_data_folder" ]]; then
        echo "Error: Base data folder '$base_data_folder' does not exist."
        return 1
    fi
    
    # Find all .yaml and .yml files in the root directory of the base data folder
    while IFS= read -r -d '' file; do
        config_files+=("$file")
    done < <(find "$base_data_folder" -maxdepth 1 -type f \( -name "*.yaml" -o -name "*.yml" \) -print0)
    
    # Return the list of config files
    printf "%s\n" "${config_files[@]}"
}