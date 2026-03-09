#!/bin/sh
set -e

# Flowise Entrypoint - Fix user system access issues
# Ensures container can run without trying to access host user system

echo "[INFO] Flowise entrypoint: Starting application..."

# Create necessary directories and set permissions
mkdir -p /app/storage/logs /app/storage/uploads
chown -R ${TENANT_UID}:${TENANT_GID} /app/storage

echo "[INFO] Permissions fixed. Starting Flowise..."

# Execute original command as tenant user
exec su-exec ${TENANT_UID}:${TENANT_GID} /bin/bash -c "cd /app && npm start"
