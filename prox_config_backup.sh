#!/bin/bash

###########################
# Configuration Variables #
###########################

DEFAULT_BACK_DIR="/mnt/pve/media/ROXMOX_BACKUP"
BACKUP_DIR=${BACK_DIR:-$DEFAULT_BACK_DIR}
MAX_BACKUPS=5

###########################

# Exit on error
set -e

# Ensure backup directory exists
if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "Error: Backup directory does not exist, exiting."
    exit 1
fi

# Generate timestamp and filenames
NOW=$(date +%Y-%m-%d.%H.%M.%S)
HOSTNAME=$(hostname)
BACKUP_FILENAME="pve_${HOSTNAME}_${NOW}.tar.gz"
TEMP_DIR=$(mktemp -d)

# Temporary cleanup function
function clean_up {
    # Remove temporary directory
    rm -rf "$TEMP_DIR"
}

trap clean_up EXIT

# Stop necessary Proxmox services before backup
echo "Stopping Proxmox services..."
services=( "pvestatd" "pvedaemon" "pve-cluster" )
for service in "${services[@]}"; do
    systemctl stop "$service"
    echo "$service stopped."
done

# Backup critical system files
echo "Creating backup for $HOSTNAME..."

# Create individual backups for each critical directory
mkdir -p "$TEMP_DIR/backup"

tar -czf "$TEMP_DIR/backup/pve-cluster-backup.tar.gz" /var/lib/pve-cluster
tar -czf "$TEMP_DIR/backup/ssh-backup.tar.gz" /root/.ssh
tar -czf "$TEMP_DIR/backup/corosync-backup.tar.gz" /etc/corosync
tar -czf "$TEMP_DIR/backup/pve-backup.tar.gz" /etc/pve
cp /etc/hosts "$TEMP_DIR/backup/hosts.backup"
cp /etc/network/interfaces "$TEMP_DIR/backup/interfaces.backup"

# Combine all backups into one tarball
tar -czf "$TEMP_DIR/$BACKUP_FILENAME" -C "$TEMP_DIR/backup" .

# Debugging: Check if the backup file is created in TEMP_DIR
echo "Temporary backup file: $TEMP_DIR/$BACKUP_FILENAME"
ls -l "$TEMP_DIR"

# Handle backup cleanup: Delete backups older than 90 days
echo "Cleaning up backups older than 90 days..."
find "$BACKUP_DIR" -type f -name "*_${HOSTNAME}_*.tar.gz" -mtime +90 -exec rm -v {} \;

# Move the new backup to the backup directory
echo "Moving backup to $BACKUP_DIR..."
if mv "$TEMP_DIR/$BACKUP_FILENAME" "$BACKUP_DIR/"; then
    echo "Backup successfully moved to $BACKUP_DIR"
else
    echo "Failed to move backup file."
    exit 1
fi

# Restart Proxmox services after backup
echo "Restarting Proxmox services..."
for service in "${services[@]}"; do
    systemctl start "$service"
    echo "$service started."
done

# Cleanup temporary files
clean_up

echo "Backup completed successfully."