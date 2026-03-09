#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Script 3: Mission Control - Complete Service Management Interface
# =============================================================================
# PURPOSE: Primary interface for managing, debugging, and configuring live platform
# USAGE:   sudo bash scripts/3-configure-services.sh <tenant_id> [action] [service/argument]
# ACTIONS:  --start, --stop, --restart, --logs, --status, --test-litellm, --set-routing, --enable-persistence
# =============================================================================

# --- Tenant ID Check & Environment Loading ---
if [[ -z "${1:-}" ]]; then
    echo "ERROR: TENANT_ID is required. Usage: sudo bash $0 <tenant_id> [action]" >&2
    exit 1
fi
TENANT_ID="$1"
TENANT_DIR="/mnt/data/${TENANT_ID}"
ENV_FILE="${TENANT_DIR}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
    echo "ERROR: Environment file not found for tenant '${TENANT_ID}'" >&2
    exit 1
fi
set -a; source "${ENV_FILE}"; set +a
cd "${TENANT_DIR}" # CRITICAL: Run all docker commands from here

# --- Logging Helpers ---
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' NC='\033[0m'
log() { echo -e "${CYAN}[INFO]${NC}    $*"; }
ok() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}    $*"; }
fail() { echo -e "${RED}[FAIL]${NC}    $*"; exit 1; }

# --- ACTION FUNCTIONS ---

# 1. Start/Stop/Restart Services
start_service() {
    log "Starting service: $1..."
    docker compose up -d "$1"
    ok "Service '$1' is starting. Check '--status'."
}
stop_service() {
    log "Stopping service: $1..."
    docker compose stop "$1"
    ok "Service '$1' stopped."
}
restart_service() {
    log "Restarting service: $1..."
    docker compose restart "$1"
    ok "Service '$1' is restarting."
}

# 2. View Service Logs (Your Request)
view_logs() {
    local SERVICE_NAME="$1"
    local LOG_FILE="${TENANT_DIR}/logs/${SERVICE_NAME}.log"
    log "Streaming logs for '$SERVICE_NAME'. Press Ctrl+C to exit."
    log "A copy of logs will be saved to: ${LOG_FILE}"
    # Use tee to write to file and show on screen
    docker compose logs -f "$SERVICE_NAME" | tee -a "${LOG_FILE}"
}

# 3. Comprehensive Health Status
show_status() {
    echo "--- AI Platform Status Dashboard for Tenant: ${TENANT_ID} ---"
    docker compose ps --format "table {{.Name}}\t{{.State}}\t{{.Status}}"
    echo ""
    log "--- Real-time Resource Usage (Press 'q' to quit) ---"
    docker stats
}

# 4. Test LiteLLM Routing (Your Request)
test_litellm_routing() {
    if ! docker compose ps | grep -q "litellm.*Up"; then
        fail "LiteLLM container is not running. Cannot perform test."
    fi
    log "Performing LiteLLM routing tests..."

    # Test 1: Local Model (Ollama)
    log "Testing route to LOCAL model (Ollama)..."
    if curl --silent --max-time 15 -X POST "http://localhost:${LITELLM_PORT}/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{
              "model": "ollama/'"${OLLAMA_DEFAULT_MODEL}"'",
              "messages": [{"role": "user", "content": "test"}]
            }' > /dev/null; then
        ok "✅ LiteLLM successfully routed request to Ollama."
    else
        fail "❌ FAILED to route request to Ollama via LiteLLM. Check LiteLLM and Ollama logs."
    fi

    # Test 2: Cloud Model (OpenAI)
    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        log "Testing route to CLOUD model (OpenAI)..."
        if curl --silent --max-time 20 -X POST "http://localhost:${LITELLM_PORT}/v1/chat/completions" \
            -H "Authorization: Bearer ${OPENAI_API_KEY}" \
            -H "Content-Type: application/json" \
            -d '{
                  "model": "gpt-3.5-turbo",
                  "messages": [{"role": "user", "content": "test"}]
                }' | grep -q "content"; then
            ok "✅ LiteLLM successfully routed request to OpenAI."
        else
            warn "⚠️ FAILED to route request to OpenAI via LiteLLM. Check API key and LiteLLM logs."
        fi
    else
        log "Skipping cloud model test (OPENAI_API_KEY not set)."
    fi
}

# 5. Change LiteLLM Routing Strategy (Your Request)
set_litellm_routing() {
    local NEW_STRATEGY="$1"
    if [[ ! "$NEW_STRATEGY" =~ ^(cost-optimized|speed-optimized|balanced|capability-optimized)$ ]]; then
        fail "Invalid strategy. Must be one of: cost-optimized, speed-optimized, balanced, capability-optimized."
    fi
    log "Updating LiteLLM routing strategy to: ${NEW_STRATEGY}"
    # Use sed for a safe, idempotent replacement in .env file
    sed -i "s/^LITELLM_ROUTING_STRATEGY=.*/LITELLM_ROUTING_STRATEGY=${NEW_STRATEGY}/" "${ENV_FILE}"
    ok "Strategy updated in ${ENV_FILE}. Restarting LiteLLM to apply changes..."
    restart_service "litellm"
}

# 6. Enable Platform Persistence (Action 3.2)
enable_persistence() {
    local SERVICE_FILE="/etc/systemd/system/aip-tenant-${TENANT_ID}.service"
    log "Creating systemd service for tenant '${TENANT_ID}' for boot persistence..."

    cat > "${SERVICE_FILE}" << EOF
[Unit]
Description=AI Platform Tenant - ${TENANT_ID}
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=${TENANT_DIR}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "aip-tenant-${TENANT_ID}.service"
    
    ok "Systemd service created at ${SERVICE_FILE}"
    log "The full stack for tenant '${TENANT_ID}' will now start automatically on server boot."
}

# --- Main Script Logic (The "Router") ---
main() {
    ACTION=${2:---status} # Default to --status
    SERVICE=${3:-}
    
    case "$ACTION" in
        --start)
            [ -z "$SERVICE" ] && fail "Usage: $0 $TENANT_ID --start <service_name>"
            start_service "$SERVICE"
            ;;
        --stop)
            [ -z "$SERVICE" ] && fail "Usage: $0 $TENANT_ID --stop <service_name>"
            stop_service "$SERVICE"
            ;;
        --restart)
            [ -z "$SERVICE" ] && fail "Usage: $0 $TENANT_ID --restart <service_name>"
            restart_service "$SERVICE"
            ;;
        --logs)
            [ -z "$SERVICE" ] && fail "Usage: $0 $TENANT_ID --logs <service_name>"
            view_logs "$SERVICE"
            ;;
        --status)
            show_status
            ;;
        --test-litellm)
            test_litellm_routing
            ;;
        --set-routing)
            [ -z "$SERVICE" ] && fail "Usage: $0 $TENANT_ID --set-routing <strategy>"
            set_litellm_routing "$SERVICE"
            ;;
        --enable-persistence)
            enable_persistence
            ;;
        *)
            echo "AI Platform Mission Control for Tenant: ${TENANT_ID}"
            echo "Usage: sudo bash $0 ${TENANT_ID} [action] [service/argument]"
            echo ""
            echo "Actions:"
            echo "  --status                   Display health and resource dashboard."
            echo "  --start <service_name>     Start a specific service (e.g., 'n8n')."
            echo "  --stop <service_name>      Stop a specific service."
            echo "  --restart <service_name>   Restart a specific service."
            echo "  --logs <service_name>      Stream logs for a service and save to a file."
            echo "  --test-litellm             Verify LiteLLM routing to local and cloud models."
            echo "  --set-routing <strategy>   Change LiteLLM routing (e.g., 'cost-optimized')."
            echo "  --enable-persistence        Create systemd service for auto-boot."
            ;;
    esac
}

main "$@"
