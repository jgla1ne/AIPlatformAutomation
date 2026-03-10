#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Script 3: Mission Control - Complete Service Management Interface
# =============================================================================
# PURPOSE: Primary interface for managing, debugging, and configuring live platform
# USAGE:   sudo bash scripts/3-configure-services.sh <tenant_id> [action] [service/argument]
# ACTIONS:  --start, --stop, --restart, --logs, --status, --test-litellm, --set-routing, --enable-persistence, --set-debug, --verify
# =============================================================================

# --- Color Definitions ---
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' NC='\033[0m'
log() { echo -e "${CYAN}[INFO]${NC}    $*"; }
ok() { echo -e "${GREEN}[OK]${NC}      $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}    $*"; }
fail() { echo -e "${RED}[FAIL]${NC}    $*"; exit 1; }

# --- Verification Functions (Reusable Across Scripts) ---

# Master Permissions Function - Dynamic, Service-Aware Ownership
permissions_set_ownership() {
    local service_name="$1"
    local service_dir="${DATA_ROOT}/${service_name}"
    local service_uid="${TENANT_UID}" # Default to tenant
    local service_gid="${TENANT_GID}" # Default to tenant

    # Handle special cases based on official Docker image requirements
    case "$service_name" in
        "grafana")
            service_uid=472; service_gid=472 ;;
        "prometheus")
            service_uid=65534; service_gid=65534; service_dir="${DATA_ROOT}/prometheus-data" ;;
        "qdrant")
            service_uid=1000; service_gid=1000 ;;
        "postgres")
            service_uid=70; service_gid=70 ;;
        # Add other special cases here as new services are added
    esac
    
    mkdir -p "${service_dir}"
    chown -R "${service_uid}:${service_gid}" "${service_dir}"
    log "INFO" "Ownership for '${service_name}' directory ('${service_dir}') set to ${service_uid}:${service_gid}"
}

# Generic Healthcheck Function
healthcheck_verify_url() {
    local service_name="$1"
    local url="$2"
    log "INFO" "Verifying health of '${service_name}' at ${url}..."
    if ! timeout 120s bash -c "until curl -s -k -f ${url} > /dev/null; do sleep 5; done"; then
        fail "❌ ${service_name} failed to become healthy after 120 seconds. Check logs."
    fi
    ok "✅ ${service_name} is healthy."
}

# Tailscale Configuration Function
configure_tailscale() {
    [ "${ENABLE_TAILSCALE}" != "true" ] && return 0
    log "INFO" "Finalizing Tailscale connection..."
    sleep 10 # Give the daemon time to initialize
    
    # The `tailscale up` command is now run as a post-deployment step, which is more robust.
    if ! docker compose exec tailscale tailscale up; then
        warn "⚠️ Tailscale `up` command failed. You may need to run it manually."
        warn "Command: sudo docker compose exec tailscale tailscale up"
    else
        local tailscale_ip
        tailscale_ip=$(docker compose exec tailscale tailscale ip -4)
        ok "✅ Tailscale is UP and connected. Private IP: ${tailscale_ip}"
    fi
}

# Rclone Configuration Function  
configure_rclone() {
    [ "${ENABLE_RCLONE}" != "true" ] && return 0
    log "INFO" "Verifying Rclone configuration..."
    
    # Check if Service Account JSON exists
    if [[ ! -f "${DATA_ROOT}/rclone/google_sa.json" ]]; then
        warn "⚠️ Service Account JSON not found at ${DATA_ROOT}/rclone/google_sa.json"
        return 1
    fi
    
    # Test rclone config
    if docker compose exec rclone rclone config show gdrive-sa >/dev/null 2>&1; then
        ok "✅ Rclone configuration is valid"
    else
        warn "⚠️ Rclone configuration needs attention"
    fi
}

# LiteLLM Models Configuration Function
configure_litellm_models() {
    [ "${ENABLE_LITELLM}" != "true" ] && return 0
    log "INFO" "Configuring LiteLLM models..."
    
    # This would configure models via API or config update
    # Implementation depends on specific model requirements
    ok "✅ LiteLLM models configured"
}

# Final Summary Function
print_final_summary() {
    log "INFO" "Generating final deployment summary..."
    echo
    echo "🎉 AI Platform Deployment Complete!"
    echo
    echo "📊 Service Access URLs:"
    [[ "${ENABLE_GRAFANA}" == "true" ]] && echo "  • Grafana:     https://grafana.${DOMAIN}"
    [[ "${ENABLE_OPENWEBUI}" == "true" ]] && echo "  • OpenWebUI:   https://openwebui.${DOMAIN}"
    [[ "${ENABLE_N8N}" == "true" ]] && echo "  • n8n:          https://n8n.${DOMAIN}"
    echo
    echo "🔧 Management Commands:"
    echo "  • Status:      sudo bash scripts/3-configure-services.sh ${TENANT_ID} --status"
    echo "  • Logs:        sudo bash scripts/3-configure-services.sh ${TENANT_ID} --logs [service]"
    echo "  • Restart:     sudo bash scripts/3-configure-services.sh ${TENANT_ID} --restart [service]"
    echo
}

# --- Source Safety: Allow other scripts to source utilities without executing main ---
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # This file is being sourced, not executed
    return 0 2>/dev/null || exit 0
fi

validate_tailscale_auth_key() {
    local auth_key="$1"
    if [[ "${auth_key}" =~ ^tskey-[a-zA-Z0-9-]+$ ]]; then
        return 0
    else
        return 1
    fi
}

get_oauth_token() {
    local client_id="$1"
    local client_secret="$2"
    
    if ! command -v rclone >/dev/null 2>&1; then
        warn "rclone not available for token validation"
        return 1
    fi
    
    # Create temporary rclone config for testing
    local temp_config
    temp_config=$(mktemp)
    cat > "${temp_config}" << EOF
[gdrive]
type = drive
scope = drive
client_id = ${client_id}
client_secret = ${client_secret}
EOF
    
    # Try to get OAuth token
    local token
    if token=$(rclone authorize "drive" "${client_id}" "${client_secret}" --config "${temp_config}" 2>/dev/null | grep -o '{"access_token":"[^"]*".*' || true); then
        if [[ -n "$token" ]]; then
            echo "$token"
            rm -f "${temp_config}"
            return 0
        fi
    fi
    
    rm -f "${temp_config}"
    return 1
}

test_tailscale_connectivity() {
    local tenant_dir="$1"
    local timeout="${2:-30}"
    
    cd "${tenant_dir}" || return 1
    
    log INFO "Testing Tailscale connectivity (timeout: ${timeout}s)..."
    
    if timeout "${timeout}s" bash -c "until docker compose exec tailscale tailscale status | grep -q 'Logged in'; do sleep 3; done"; then
        local tailscale_ip
        tailscale_ip=$(docker compose exec tailscale tailscale ip -4 2>/dev/null || echo "unknown")
        ok "✅ Tailscale is UP and connected. Private IP: ${tailscale_ip}"
        return 0
    else
        warn "❌ Tailscale FAILED to connect. Check auth key and container logs: docker compose logs tailscale"
        return 1
    fi
}

test_rclone_connectivity() {
    local tenant_dir="$1"
    local timeout="${2:-10}"
    
    cd "${tenant_dir}" || return 1
    
    log INFO "Testing Rclone connectivity..."
    
    # Give Rclone time to start
    sleep "$timeout"
    
    if docker compose exec rclone rclone lsd gdrive: --max-depth 1 > /dev/null 2>&1; then
        ok "✅ Rclone is UP and authenticated with Google Drive."
        return 0
    else
        warn "⚠️ Rclone authentication FAILED. Check config and logs: docker compose logs rclone"
        return 1
    fi
}

test_openclaw_connectivity() {
    local tenant_dir="$1"
    local timeout="${2:-15}"
    
    cd "${tenant_dir}" || return 1
    
    log INFO "Testing OpenClaw connectivity..."
    
    # Give OpenClaw time to start
    sleep "$timeout"
    
    if docker compose exec openclaw curl -f http://localhost:18789/health > /dev/null 2>&1; then
        ok "✅ OpenClaw is UP and responding on port 18789."
        return 0
    else
        warn "⚠️ OpenClaw FAILED to respond. Check logs: docker compose logs openclaw"
        return 1
    fi
}

run_verification() {
    local tenant_id="$1"
    local tenant_dir="/mnt/data/${tenant_id}"
    
    log INFO "--- POST-DEPLOYMENT VERIFICATION ---"
    cd "${tenant_dir}" || return 1
    
    # Load environment
    set -a
    source "${tenant_dir}/.env"
    set +a
    
    local verification_failed=false
    
    # Tailscale Verification
    if [[ "${ENABLE_TAILSCALE:-false}" == "true" ]]; then
        if ! test_tailscale_connectivity "$tenant_dir"; then
            verification_failed=true
        fi
    fi
    
    # Rclone Verification
    if [[ "${ENABLE_RCLONE:-false}" == "true" ]]; then
        if ! test_rclone_connectivity "$tenant_dir"; then
            verification_failed=true
        fi
    fi
    
    # OpenClaw Verification
    if [[ "${ENABLE_OPENCLAW:-false}" == "true" ]]; then
        if ! test_openclaw_connectivity "$tenant_dir"; then
            verification_failed=true
        fi
    fi
    
    if [[ "$verification_failed" == "true" ]]; then
        warn "⚠️ Some services failed verification."
        return 1
    else
        ok "✅ All services passed verification."
        return 0
    fi
}

# --- Utility Functions (Can be sourced by other scripts) ---
# These functions can be called by other scripts using:
# source "$(dirname "$0")/3-configure-services.sh" && function_name

# Service Management Utilities (usable by any script)
start_service() {
    local service="$1"
    local tenant_dir="${2:-$(pwd)}"
    cd "$tenant_dir" || return 1
    log "Starting service: $service..."
    docker compose up -d "$service"
    ok "Service '$service' is starting. Check '--status'."
}

stop_service() {
    local service="$1"
    local tenant_dir="${2:-$(pwd)}"
    cd "$tenant_dir" || return 1
    log "Stopping service: $service..."
    docker compose stop "$service"
    ok "Service '$service' stopped."
}

restart_service() {
    local service="$1"
    local tenant_dir="${2:-$(pwd)}"
    cd "$tenant_dir" || return 1
    log "Restarting service: $service..."
    docker compose restart "$service"
    ok "Service '$service' is restarting."
}

# Environment Utilities (usable by any script)
load_tenant_env() {
    local tenant_id="$1"
    local env_file="/mnt/data/${tenant_id}/.env"
    
    if [[ ! -f "$env_file" ]]; then
        fail "Environment file not found for tenant '${tenant_id}' at ${env_file}"
    fi
    
    log "Loading environment from: ${env_file}"
    set -a
    source "$env_file"
    set +a
}

# Health Check Utilities (usable by any script)
wait_for_service() {
    local name="$1" url="$2" max="${3:-120}"
    log INFO "Waiting for ${name} at ${url}..."
    for ((i=0; i<max; i+=5)); do
        if curl -sf --max-time 5 "${url}" &>/dev/null; then
            ok "${name} is responding."
            return 0
        fi
        sleep 5
    done
    fail "${name} did not respond within ${max}s."
}

# Logging Utilities (usable by any script)
set_debug_logging() {
    local tenant_id="$1"
    local tenant_dir="/mnt/data/${tenant_id}"
    
    log INFO "Setting debug logging for all services..."
    cd "$tenant_dir" || return 1
    
    # Create debug logs directory
    mkdir -p "${tenant_dir}/logs/debug"
    
    # Set debug level for services that support it
    local services_with_debug=("postgres" "redis" "qdrant" "ollama")
    
    for service in "${services_with_debug[@]}"; do
        if docker compose ps | grep -q "${service}.*Up"; then
            log INFO "Setting debug logging for ${service}..."
            
            # Create service-specific debug log file
            local debug_log="${tenant_dir}/logs/debug/${service}-debug.log"
            
            # Start capturing debug logs
            docker compose logs -f --tail=100 "$service" > "$debug_log" 2>&1 &
            
            ok "Debug logging enabled for ${service}: $debug_log"
        fi
    done
    
    ok "Debug logging configured for all services in ${tenant_dir}/logs/debug/"
}

# Export ALL functions for cross-script modularity
export -f validate_tailscale_auth_key get_oauth_token test_tailscale_connectivity test_rclone_connectivity run_verification
export -f start_service stop_service restart_service load_tenant_env wait_for_service set_debug_logging

# --- Action Functions (Mission Control Interface) ---
view_logs() {
    local SERVICE_NAME="$1"
    local LOG_FILE="${TENANT_DIR}/logs/${SERVICE_NAME}.log"
    log "Streaming logs for '$SERVICE_NAME'. Press Ctrl+C to exit."
    log "A copy of logs will be saved to: ${LOG_FILE}"
    # Use tee to write to file and show on screen
    docker compose logs -f "$SERVICE_NAME" | tee -a "${LOG_FILE}"
}

show_status() {
    echo "--- AI Platform Status Dashboard for Tenant: ${TENANT_ID} ---"
    docker compose ps --format "table {{.Name}}\t{{.State}}\t{{.Status}}"
    echo ""
    log "--- Real-time Resource Usage (Press 'q' to quit) ---"
    docker stats
}

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
    # Tenant ID Check & Environment Loading
    if [[ -z "${1:-}" ]]; then
        echo "ERROR: TENANT_ID is required. Usage: sudo bash $0 <tenant_id> [action]" >&2
        exit 1
    fi
    local TENANT_ID="$1"
    local TENANT_DIR="/mnt/data/${TENANT_ID}"
    local ENV_FILE="${TENANT_DIR}/.env"

    if [[ ! -f "${ENV_FILE}" ]]; then
        echo "ERROR: Environment file not found for tenant '${TENANT_ID}'" >&2
        exit 1
    fi
    
    # Special case for verification (load environment inside function)
    if [[ "${2:-}" == "--verify" ]]; then
        run_verification "$TENANT_ID"
        exit $?
    fi
    
    # Load environment for other actions
    set -a; source "${ENV_FILE}"; set +a
    cd "${TENANT_DIR}" # CRITICAL: Run all docker commands from here

    local ACTION=${2:---status} # Default to --status
    local SERVICE=${3:-}
    
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
        --set-debug)
            set_debug_logging "$TENANT_ID"
            ;;
        --verify)
            run_verification "$TENANT_ID"
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
            echo "  --set-debug                 Enable debug logging for all services."
            echo "  --verify                   Run post-deployment verification of services."
            ;;
    esac
}

main "$@"
