#!/usr/bin/env bash
# Google Drive Backup Sync Script v100.0.0

source "$(dirname "$0")/../.env"

LOG_FILE="${LOG_DIR}/gdrive-sync-$(date +%Y%m%d-%H%M%S).log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "Starting Google Drive backup sync..."

if [[ -z "$GDRIVE_FOLDER_ID" ]]; then
    log "ERROR: GDRIVE_FOLDER_ID not configured"
    exit 1
fi

# Backup data directory
rclone sync \
    --config="${CONFIG_DIR}/gdrive/rclone.conf" \
    --drive-shared-with-me \
    --exclude=".tmp/**" \
    --log-file="$LOG_FILE" \
    "${DATA_DIR}" \
    "gdrive:${GDRIVE_FOLDER_ID}"

log "Backup sync complete"
