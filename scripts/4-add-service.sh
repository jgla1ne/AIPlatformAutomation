#!/usr/bin/env bash
# 4-add-service.sh
# Adds a single service to an existing deployment
# Usage: sudo bash scripts/4-add-service.sh [service_name]
set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }

# ─── Runtime vars ────────────────────────────────────────────────────────────────
TENANT_UID="${SUDO_UID:-$(id -u)}"
TENANT_GID="${SUDO_GID:-$(id -g)}"
# Load environment from .env file
if [[ -n "${TENANT_DIR:-}" && -f "${TENANT_DIR}/.env" ]]; then
  ENV_FILE="${TENANT_DIR}/.env"
elif [[ -f "$(dirname "${BASH_SOURCE[0]}")/../.env" ]]; then
  ENV_FILE="$(dirname "${BASH_SOURCE[0]}")/../.env"
else
  ENV_FILE="$(sudo ls -t /mnt/data/*/.env 2>/dev/null | head -1)"
fi

[ ! -f "${ENV_FILE}" ] && {
    echo "ERROR: Run script 1 first"
    exit 1
}

# Source environment variables
set -a; source "${ENV_FILE}"; set +a

# Use environment variables
DATA_ROOT="${DATA_ROOT:-/mnt/data/${TENANT_ID:-default}}"

# Source the service append functions from script 2
# (script 2 must export them or we duplicate just the needed one)
SCRIPT2_DIR="$(dirname "$0")"

AVAILABLE_SERVICES="openwebui anythingllm dify n8n flowise openclaw \
    litellm ollama grafana signal tailscale rclone authentik minio prometheus qdrant"

SERVICE="${1:-}"

if [ -z "${SERVICE}" ]; then
    echo "Available services:"
    for svc in ${AVAILABLE_SERVICES}; do
        current_val=$(grep "^ENABLE_${svc^^}=" "${ENV_FILE}" 2>/dev/null | \
            cut -d= -f2 || echo "false")
        printf "  %-20s currently: %s\n" "${svc}" "${current_val}"
    done
    echo ""
    read -r -p "Which service to add? " SERVICE
fi

SERVICE=$(echo "${SERVICE}" | tr '[:upper:]' '[:lower:]')
ENV_KEY="ENABLE_$(echo "${SERVICE}" | tr '[:lower:]' '[:upper:]')"

# Validate service name
if [[ ! " ${AVAILABLE_SERVICES} " =~ " ${SERVICE} " ]]; then
    fail "Unknown service: ${SERVICE}. Available: ${AVAILABLE_SERVICES}"
fi

# Update .env
if grep -q "^${ENV_KEY}=" "${ENV_FILE}"; then
    sed -i "s/^${ENV_KEY}=.*/${ENV_KEY}=true/" "${ENV_FILE}"
else
    echo "${ENV_KEY}=true" >> "${ENV_FILE}"
fi

echo "Enabled ${SERVICE} in ${ENV_FILE}"
echo "Re-running script 2 to regenerate and redeploy..."

# Re-run script 2 to regenerate compose file and redeploy
exec bash "${SCRIPT2_DIR}/2-deploy-services.sh"
