#!/bin/bash
set -euxo pipefail

echo "[INFO] LiteLLM custom entrypoint started."
echo "[INFO] Forcing ownership of cache directory to user ${TENANT_UID}:${TENANT_GID}..."

# Create directory if it doesn't exist
mkdir -p /home/user/.cache/pip

# Change ownership and log result.
if chown -R "${TENANT_UID}:${TENANT_GID}" /home/user/.cache; then
  echo "[OK] Cache directory ownership set."
else
  echo "[FAIL] Could not set ownership on cache directory." >&2
  exit 1
fi

echo "[INFO] Handing over to original LiteLLM entrypoint..."
exec /entrypoint.sh
