#!/bin/sh
set -e

# OpenWebUI Entrypoint - Fix ownership issues at startup
# Ensures container can write to its own data directory

echo "[INFO] OpenWebUI entrypoint: Fixing permissions..."

# Create data directory and set ownership as root first
mkdir -p /app/backend/data
chown -R ${TENANT_UID}:${TENANT_GID} /app/backend/data

echo "[INFO] Permissions fixed. Starting OpenWebUI..."

# Execute original command as tenant user
exec su-exec ${TENANT_UID}:${TENANT_GID} /bin/bash -c "cd /app && npm start"
