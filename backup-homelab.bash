#!/usr/bin/env bash

# This script is used to backup the homelab configuration files and data.
# Specifically, it will make up a backup archive.
#
# 1. Traverse the docker directory and copy all files that aren't /data directories into the backup archive.
# 2. Copy the existing port mapping file into the backup archive.
# 3. Copy the readme into each backup
# 4. Move the backup archive to the backup directory.

set -euo pipefail 
source "$(dirname "$0")/tools.sh"

# Define the backup directory and archive name
BACKUP_DIR="/docker/backup/homelab"
ARCHIVE_NAME="$(date +%Y%m%d)_homelab_config.tar.gz"

DOCKER_CONFIGS_DIR="/volume1/docker"
# Create the backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"


# all_files should be the extra files plus the files in the docker directory
# All the files to backup.  This is the non-data files in the docker directory
# Plus any extra files returned from the various get_config calls in the tools script.

all_files=("README.md")  # Start with the readme file

# Collect all files in the docker directory, excluding /data directories
while IFS= read -r -d '' file; do
    all_files+=("$file")
done < <(find "$DOCKER_CONFIGS_DIR" -type f -not -path '*/data/*' -print0)

# Collect extra files from the tools script

# Homepage requires extra files to be backed up
# This function returns a list of files that need to be backed up for the homepage configuration
local extra_files=$(get_homepage_config "$DOCKER_CONFIGS_DIR/homepage/data")
for file in $extra_files; do
    all_files+=("$file")
done

# Now the backup archive will be created from all_files
tar -czf "$BACKUP_DIR/$ARCHIVE_NAME" "${all_files[@]}"

# Move the backup archive to the backup directory
mv "$BACKUP_DIR/$ARCHIVE_NAME" "$BACKUP_DIR/"

# Print a message indicating the backup was successful
echo "Backup completed successfully. Archive created at: $BACKUP_DIR/$ARCHIVE_NAME"
