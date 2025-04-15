#!/bin/bash
# Refined Backup Script (with -L and excludes)
# This script backs up various directories and Docker volumes, following symlinks
# and skipping some files to avoid permission errors.

set -euo pipefail

HOSTNAME="$(hostname)"

# Define the remote backup path (adjust to your own as needed)
REMOTE="bk:syncvault/${HOSTNAME}"
REMOTE_DATA="${REMOTE}/data"

##########################################
# Single place to run rclone sync, with  #
# support for extra arguments/excludes.  #
##########################################
sync_rclone() {
    local src="$1"
    local dest="$2"
    shift 2  # shift off the source/destination

    # Use -L (or --copy-links) to follow symlinks.
    # Pass any extra arguments through ($@).
    rclone sync -L "$src" "$dest" "$@"
}

backup_nginx() {
    echo "Backing up nginx configuration..."
    # If you only want to back up if certain files exist:
    if [ -d /etc/nginx/sites-available/ ]; then
        # Example: exclude the SSL private key to avoid permission issues
        sync_rclone "/etc/nginx/" "${REMOTE}/nginx/" \
            --exclude "ssl/nginx.key"
    else
        echo "No nginx configuration found."
    fi
}

backup_srv() {
    echo "Backing up /srv..."
    if [ -d /srv/ ] && [ -n "$(ls -A /srv/ 2>/dev/null)" ]; then
        # No exclude example here, but you can add if needed
        sync_rclone "/srv/" "${REMOTE}/srv/"
    else
        echo "  /srv is empty or does not exist, skipping."
    fi
}

backup_apps() {
    echo "Backing up applications from /opt/apps..."
    if [ -d /opt/apps/ ] && [ -n "$(ls -A /opt/apps/ 2>/dev/null)" ]; then
        sync_rclone "/opt/apps/" "${REMOTE}/apps/"
    else
        echo "  /opt/apps is empty or does not exist, skipping."
    fi
}

backup_docker_volumes() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "Docker not found, skipping Docker volumes."
        return
    fi

    echo "Backing up Docker volumes..."
    local VOLUMES
    VOLUMES="$(docker volume ls -q)"
    if [ -z "$VOLUMES" ]; then
        echo "  No Docker volumes found, skipping."
        return
    fi

    local TMPDIR
    TMPDIR="$(mktemp -d)"
    trap 'rm -rf "$TMPDIR"' RETURN

    # Copy volume contents into a temp directory
    for VOLUME in $VOLUMES; do
        echo "  Backing up volume: $VOLUME"
        # Use cp -a to preserve ownership, timestamps, etc.
        docker run --rm \
            -v "$VOLUME":/volume \
            -v "$TMPDIR":/backup \
            alpine sh -c "cp -a /volume/ /backup/$VOLUME/"
    done

    # Now sync from the staging directory to the remote
    echo "  Syncing Docker volumes to remote..."
    sync_rclone "$TMPDIR/" "${REMOTE_DATA}/docker-volumes/"
}

backup_git_repos() {
    echo "Backing up git repositories..."
    if [ -d /home/git/repos/ ] && [ -n "$(ls -A /home/git/repos/ 2>/dev/null)" ]; then
        sync_rclone "/home/git/repos/" "${REMOTE_DATA}/git-repos/"
    else
        echo "  /home/git/repos is empty or does not exist, skipping."
    fi
}

##############
# Main logic #
##############

backup_nginx
backup_srv
backup_apps
backup_docker_volumes
backup_git_repos

echo "Backup completed successfully."
