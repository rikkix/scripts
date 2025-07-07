#!/bin/bash
# Refined Backup Script (with -L and excludes)
# This script backs up various directories and Docker volumes, following symlinks
# and skipping some files to avoid permission errors.

set -euo pipefail

HOSTNAME="$(hostname)"

# Define the remote backup path (adjust to your own as needed)
REMOTE="backup:daily/${HOSTNAME}"

# Use gzip compression for tar archives (default: false)
USE_GZIP=false

# Create universal temp directory
UNIVERSAL_TMP="/tmp/server-backup-$$"
mkdir -p "$UNIVERSAL_TMP"

# Configuration file for volume exclusions
VOLUME_EXCLUDES_CONF="/etc/server-backup/volume-excludes.conf"

# Configuration file for app exclusions
APP_EXCLUDES_CONF="/etc/server-backup/app-excludes.conf"

# Cleanup function
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -rf "$UNIVERSAL_TMP"
}

# Set trap to cleanup on exit or failure
trap cleanup EXIT INT TERM

##########################################
# Logging functions for better output   #
##########################################
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1"
}

log_success() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [✓] $1"
}

log_skip() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [SKIP] $1"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" >&2
}

##########################################
# Function to check if a volume should be excluded
##########################################
is_volume_excluded() {
    local volume_name="$1"
    
    # If config file doesn't exist, don't exclude anything
    if [ ! -f "$VOLUME_EXCLUDES_CONF" ]; then
        return 1
    fi
    
    # Read exclusion patterns from config file
    while IFS= read -r pattern || [ -n "$pattern" ]; do
        # Skip empty lines and comments
        if [[ -z "$pattern" || "$pattern" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Remove leading/trailing whitespace
        pattern=$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Check if volume name matches the pattern using shell wildcards
        if [[ "$volume_name" == $pattern ]]; then
            return 0  # Volume should be excluded
        fi
    done < "$VOLUME_EXCLUDES_CONF"
    
    return 1  # Volume should not be excluded
}

##########################################
# Function to check if an app should be excluded
##########################################
is_app_excluded() {
    local app_name="$1"
    
    # If config file doesn't exist, don't exclude anything
    if [ ! -f "$APP_EXCLUDES_CONF" ]; then
        return 1
    fi
    
    # Read exclusion patterns from config file
    while IFS= read -r pattern || [ -n "$pattern" ]; do
        # Skip empty lines and comments
        if [[ -z "$pattern" || "$pattern" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Remove leading/trailing whitespace
        pattern=$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Check if app name matches the pattern using shell wildcards
        if [[ "$app_name" == $pattern ]]; then
            return 0  # App should be excluded
        fi
    done < "$APP_EXCLUDES_CONF"
    
    return 1  # App should not be excluded
}

##########################################
# Universal function to copy file to remote
# Automatically adds $REMOTE/ prefix to avoid forgetting
##########################################
copy_to_remote() {
    local local_file="$1"
    local sub_path="$2"  # optional subdirectory like "apps/" or "docker-volumes/"

    local remote_path="$REMOTE/"
    if [ -n "$sub_path" ]; then
        remote_path="${REMOTE}/${sub_path}"
    fi

    log_info "Uploading $(basename "$local_file") to remote storage..."
    rclone copy "$local_file" "$remote_path"
    log_success "Uploaded $(basename "$local_file")"
}

##########################################
# Create tar archive and copy to remote  #
# to avoid listing operations            #
##########################################
backup_with_tar() {
    local src="$1"
    local remote_path="$2"  # full path like "nginx" or "apps/myapp"
    local excludes=("${@:3}")  # remaining arguments as exclude patterns

    # Set file extension and tar options based on compression setting
    local tar_ext="tar"
    local tar_compress_flag=""
    if [ "$USE_GZIP" = true ]; then
        tar_ext="tar.gz"
        tar_compress_flag="z"
    fi

    local tar_name="$(basename "$remote_path").${tar_ext}"
    local temp_tar="$UNIVERSAL_TMP/${tar_name}"
    local remote_dir="$(dirname "$remote_path")"

    log_info "Creating archive: $tar_name"

    # Create tar archive
    if [ ${#excludes[@]} -eq 0 ]; then
        tar -c${tar_compress_flag}f "$temp_tar" -C "$(dirname "$src")" "$(basename "$src")"
    else
        # Create exclude file for complex excludes
        local exclude_file="$UNIVERSAL_TMP/exclude_$$"
        printf '%s\n' "${excludes[@]}" > "$exclude_file"
        tar -c${tar_compress_flag}f "$temp_tar" -C "$(dirname "$src")" --exclude-from="$exclude_file" "$(basename "$src")"
        rm -f "$exclude_file"
    fi

    # Copy tar to remote using universal function
    if [ "$remote_dir" = "." ]; then
        copy_to_remote "$temp_tar" ""
    else
        copy_to_remote "$temp_tar" "$remote_dir/"
    fi

    # Clean up local tar
    rm -f "$temp_tar"
}

backup_nginx() {
    log_info "Starting nginx configuration backup..."
    if [ -d /etc/nginx/sites-available/ ]; then
        backup_with_tar "/etc/nginx" "nginx" "ssl/nginx.key"
        log_success "Nginx configuration backed up"
    else
        log_skip "No nginx configuration found"
    fi
}

backup_srv() {
    log_info "Starting /srv backup..."
    if [ -d /srv/ ] && [ -n "$(ls -A /srv/ 2>/dev/null)" ]; then
        backup_with_tar "/srv" "srv"
        log_success "/srv backed up"
    else
        log_skip "/srv is empty or does not exist"
    fi
}

backup_apps() {
    log_info "Starting applications backup from /opt/apps..."
    if [ -d /opt/apps/ ] && [ -n "$(ls -A /opt/apps/ 2>/dev/null)" ]; then
        # Create separate tar for each app using universal function
        for app_dir in /opt/apps/*/; do
            if [ -d "$app_dir" ]; then
                local app_name="$(basename "$app_dir")"
                
                # Check if app should be excluded
                if is_app_excluded "$app_name"; then
                    log_skip "App excluded by configuration: $app_name"
                    continue
                fi
                
                log_info "Backing up app: $app_name"
                backup_with_tar "$app_dir" "apps/$app_name"
                log_success "App $app_name backed up"
            fi
        done
    else
        log_skip "/opt/apps is empty or does not exist"
    fi
}

backup_docker_volumes() {
    if ! command -v docker >/dev/null 2>&1; then
        log_skip "Docker not found, skipping Docker volumes"
        return
    fi

    log_info "Starting Docker volumes backup..."
    local VOLUMES
    VOLUMES="$(docker volume ls -q)"
    if [ -z "$VOLUMES" ]; then
        log_skip "No Docker volumes found"
        return
    fi

    # Create separate tar for each volume
    for VOLUME in $VOLUMES; do
        # Check if volume should be excluded
        if is_volume_excluded "$VOLUME"; then
            log_skip "Docker volume excluded by configuration: $VOLUME"
            continue
        fi
        
        log_info "Backing up Docker volume: $VOLUME"

        # Use universal temp directory
        local TMPDIR="$UNIVERSAL_TMP"

        # Set file extension and tar options based on compression setting
        local tar_ext="tar"
        local tar_compress_flag=""
        if [ "$USE_GZIP" = true ]; then
            tar_ext="tar.gz"
            tar_compress_flag="z"
        fi

        # Create tar archive using pipe to avoid permission issues
        local tar_name="docker-volumes/${VOLUME}.${tar_ext}"
        local temp_tar="${TMPDIR}/${VOLUME}.${tar_ext}"

        log_info "Creating archive for volume: $VOLUME"
        docker run --rm \
            -v "$VOLUME":/volume \
            alpine tar -c${tar_compress_flag} -C /volume . > "$temp_tar"

        # Copy to remote using universal function
        copy_to_remote "$temp_tar" "docker-volumes/"
        log_success "Docker volume $VOLUME backed up"

        # Clean up temp tar file (directory cleanup handled by trap)
        rm -f "$temp_tar"
    done
}

backup_git_repos() {
    log_info "Starting git repositories backup..."
    if [ -d /home/git/repos/ ] && [ -n "$(ls -A /home/git/repos/ 2>/dev/null)" ]; then
        backup_with_tar "/home/git/repos" "git-repos"
        log_success "Git repositories backed up"
    else
        log_skip "/home/git/repos is empty or does not exist"
    fi
}

##############
# Main logic #
##############

log_info "Starting server backup process..."
log_info "Hostname: $HOSTNAME"
log_info "Remote destination: $REMOTE"
echo

backup_nginx
backup_srv
backup_apps
backup_docker_volumes
backup_git_repos

echo
log_success "Backup completed successfully!"
