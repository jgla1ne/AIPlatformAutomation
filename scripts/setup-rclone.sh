#!/usr/bin/env bash
# setup-rclone.sh — Interactive GDrive OAuth via tunnel
set -euo pipefail

source "${1:-/mnt/data/u1001/.env}"

RCLONE_CONFIG_DIR="/mnt/data/u1001/rclone/config"
RCLONE_CONF="${RCLONE_CONFIG_DIR}/rclone.conf"
REMOTE_NAME="${GDRIVE_RCLONE_REMOTE:-gdrive-u1001}"
CLIENT_ID="${RCLONE_OAUTH_CLIENT_ID:-}"
MOUNT_POINT="${RCLONE_MOUNT_POINT:-/mnt/data/u1001/gdrive}"

mkdir -p "${RCLONE_CONFIG_DIR}" "${MOUNT_POINT}"

echo "════════════════════════════════════════════════════"
echo "  Rclone GDrive OAuth Setup"
echo "════════════════════════════════════════════════════"
echo ""

if [ -f "${RCLONE_CONF}" ]; then
    echo "rclone.conf already exists at ${RCLONE_CONF}"
    echo "To reconfigure, delete it first."
    exit 0
fi

echo "This requires a browser. We will start rclone on port 53682."
echo "If you have SSH tunnel access, run on your LOCAL machine:"
echo "  ssh -L 53682:localhost:53682 ubuntu@${PUBLIC_IP:-your-server}"
echo ""
echo "Press Enter when tunnel is ready (or skip if on desktop)..."
read -r

# Run rclone config non-interactively where possible
rclone config create "${REMOTE_NAME}" drive \
    client_id="${CLIENT_ID}" \
    scope="drive" \
    --config="${RCLONE_CONF}" 2>/dev/null || {
    echo ""
    echo "Interactive config needed. Running rclone config..."
    echo "When prompted for 'remote name' enter: ${REMOTE_NAME}"
    RCLONE_CONFIG="${RCLONE_CONF}" rclone config
}

echo ""
echo "Testing connection..."
rclone --config="${RCLONE_CONF}" lsd "${REMOTE_NAME}:" --max-depth 1 && {
    echo "✅ GDrive connected successfully"
    echo ""
    echo "Now run: sudo docker compose -f ${COMPOSE_FILE} up -d rclone"
} || {
    echo "❌ Connection failed — check credentials and try again"
}
