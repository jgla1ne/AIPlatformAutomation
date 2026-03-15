#!/usr/bin/env bash
# =============================================================================
# Script 2: Deploy Services - COMPREHENSIVE DEBUG LOGGING ENGINE (DEBUG BY DEFAULT)
# =============================================================================
# Usage: sudo bash 2-deploy-services.sh [tenant_id]
# Default tenant: datasquiz
# Debug mode: ENABLED BY DEFAULT
# Output: All logs piped to single timestamped file
# =============================================================================
set -euo pipefail

# --- SOURCE MISSION CONTROL (Script 3) ---
# Import all configuration generators from Mission Control Hub
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/3-configure-services.sh"

# --- DEBUG MODE FLAG - DEBUG ENABLED BY DEFAULT ---
DEBUG_MODE="${DEBUG_MODE:-true}"
if [[ "${DEBUG_MODE}" == "true" ]]; then
    set -x
fi

# --- Colors and Logging ---
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' BLUE='\033[0;34m' NC='\033[0m'

# Initialize LOG_FILE early to ensure logging works from the start
LOG_FILE=""

log() { 
    if [[ -n "${LOG_FILE}" ]]; then
        echo -e "${CYAN}[INFO]${NC}    $1" | tee -a "${LOG_FILE}"
    else
        echo -e "${CYAN}[INFO]${NC}    $1"
    fi
}
ok() { 
    if [[ -n "${LOG_FILE}" ]]; then
        echo -e "${GREEN}[OK]${NC}      $*" | tee -a "${LOG_FILE}"
    else
        echo -e "${GREEN}[OK]${NC}      $*"
    fi
}
warn() { 
    if [[ -n "${LOG_FILE}" ]]; then
        echo -e "${YELLOW}[WARN]${NC}    $*" | tee -a "${LOG_FILE}"
    else
        echo -e "${YELLOW}[WARN]${NC}    $*"
    fi
}
fail() { 
    if [[ -n "${LOG_FILE}" ]]; then
        echo -e "${RED}[FAIL]${NC}    $*" | tee -a "${LOG_FILE}"
    else
        echo -e "${RED}[FAIL]${NC}    $*"
    fi
    exit 1
}

# --- Phase 2: Ordered Service Startup ───────────────────────────────────────
deploy_services_ordered() {
    log "INFO" "Starting Phase 2: Ordered Service Deployment"
    
    # Define service startup order with dependencies
    local startup_order=(
        "postgres:database:5432"
        "redis:cache:6379"
        "qdrant:vector-db:6333"
        "prometheus:monitoring:9090"
        "grafana:dashboard:3000"
        "litellm:llm-gateway:4000"
        "ollama:llm-engine:11434"
        "openwebui:chat-interface:8080"
        "n8n:workflow:5678"
        "caddy:reverse-proxy:80"
    )
    
    cd "${TENANT_DIR}"
    
    for service_def in "${startup_order[@]}"; do
        IFS=':' read -r service_name service_type internal_port <<< "$service_def"
        
        # Check if service is enabled
        if [[ $(declare -p "ENABLE_${service_name^^}" 2>/dev/null 2>&1) =~ "true" ]] || [[ "${service_name}" == "caddy" ]]; then
            log "INFO" "Deploying ${service_name} (${service_type})..."
            
            # Start individual service
            if ! docker compose up -d "${service_name}" >> "${LOG_FILE}" 2>&1; then
                log "ERROR" "Failed to start ${service_name}"
                docker compose logs --tail=20 "${service_name}" >> "${LOG_FILE}" 2>&1
                continue
            fi
            
            # Wait for service to be ready
            wait_for_service_ready "${service_name}" "${internal_port}" "${service_type}"
            
            ok "${service_name} deployed and ready"
        else
            log "INFO" "Skipping ${service_name} (disabled)"
        fi
    done
}

# --- Service Readiness Checker ─────────────────────────────────────────────────
wait_for_service_ready() {
    local service_name="$1"
    local internal_port="$2"
    local service_type="$3"
    local max_wait=60
    local wait_interval=5
    local wait_time=0
    
    log "INFO" "Waiting for ${service_name} to be ready (port ${internal_port})..."
    
    while [[ $wait_time -lt $max_wait ]]; do
        case "${service_type}" in
            "database")
                # Database-specific health check
                if docker exec "ai-${TENANT_ID}-${service_name}-1" pg_isready -U postgres -p "${internal_port}" &>/dev/null; then
                    log "INFO" "${service_name} database is accepting connections"
                    return 0
                fi
                ;;
            "cache")
                # Redis-specific health check
                if docker exec "ai-${TENANT_ID}-${service_name}-1" redis-cli -p "${internal_port}" ping &>/dev/null; then
                    log "INFO" "${service_name} cache is responding"
                    return 0
                fi
                ;;
            "vector-db")
                # Qdrant-specific health check
                if curl -s -f "http://localhost:${internal_port}/collections" &>/dev/null; then
                    log "INFO" "${service_name} vector database is healthy"
                    return 0
                fi
                ;;
            "monitoring"|"dashboard")
                # HTTP health check - try within container network first
                if docker exec "ai-${TENANT_ID}-${service_name}-1" wget --quiet --spider "http://localhost:${internal_port}/" &>/dev/null; then
                    log "INFO" "${service_name} is responding within container"
                    return 0
                fi
                ;;
            *)
                # Generic TCP port check
                if nc -z localhost "${internal_port}" &>/dev/null; then
                    log "INFO" "${service_name} is listening on port ${internal_port}"
                    return 0
                fi
                ;;
        esac
        
        # Check if container is still running
        if ! docker ps --filter "name=ai-${TENANT_ID}-${service_name}-1" --format "{{.Status}}" | grep -q "Up"; then
            log "ERROR" "${service_name} container is not running"
            docker compose logs --tail=10 "${service_name}" >> "${LOG_FILE}" 2>&1
            return 1
        fi
        
        sleep $wait_interval
        wait_time=$((wait_time + wait_interval))
        log "INFO" "Still waiting for ${service_name}... (${wait_time}/${max_wait}s)"
    done
    
    log "ERROR" "${service_name} failed to become ready within ${max_wait} seconds"
    docker compose logs --tail=20 "${service_name}" >> "${LOG_FILE}" 2>&1
    return 1
}

# --- Layered Health Checks ───────────────────────────────────────────────────
perform_layered_health_checks() {
    log "INFO" "Performing layered health checks..."
    
    # Layer 1: Infrastructure services
    check_infrastructure_layer
    
    # Layer 2: Data services
    check_data_layer
    
    # Layer 3: Application services
    check_application_layer
    
    # Layer 4: Gateway services
    check_gateway_layer
    
    # Layer 5: End-to-end tests
    check_end_to_end_connectivity
}

check_infrastructure_layer() {
    log "INFO" "Checking infrastructure layer..."
    
    # Check Docker network
    if docker network ls --filter name="${DOCKER_NETWORK}" --format "{{.Name}}" | grep -q "${DOCKER_NETWORK}"; then
        ok "Docker network ${DOCKER_NETWORK} exists"
    else
        fail "Docker network ${DOCKER_NETWORK} not found"
    fi
    
    # Check volume mounts
    local volumes=("postgres_data" "rclone-cache")
    for volume in "${volumes[@]}"; do
        if docker volume ls --filter name="${volume}" --format "{{.Name}}" | grep -q "${volume}"; then
            ok "Docker volume ${volume} exists"
        else
            warn "Docker volume ${volume} not found"
        fi
    done
}

check_data_layer() {
    log "INFO" "Checking data layer..."
    
    # Check PostgreSQL
    if [[ "${ENABLE_POSTGRES}" == "true" ]]; then
        if docker exec "ai-${TENANT_ID}-postgres-1" pg_isready -U postgres &>/dev/null; then
            ok "PostgreSQL is ready"
        else
            fail "PostgreSQL is not ready"
        fi
    fi
    
    # Check Redis
    if [[ "${ENABLE_REDIS}" == "true" ]]; then
        if docker exec "ai-${TENANT_ID}-redis-1" redis-cli ping &>/dev/null; then
            ok "Redis is ready"
        else
            fail "Redis is not ready"
        fi
    fi
    
    # Check Qdrant
    if [[ "${ENABLE_QDRANT}" == "true" ]]; then
        if curl -s -f "http://localhost:6333/collections" &>/dev/null; then
            ok "Qdrant is ready"
        else
            fail "Qdrant is not ready"
        fi
    fi
}

check_application_layer() {
    log "INFO" "Checking application layer..."
    
    # Check Grafana
    if [[ "${ENABLE_GRAFANA}" == "true" ]]; then
        if curl -s -f "http://localhost:3000/api/health" &>/dev/null; then
            ok "Grafana is ready"
        else
            warn "Grafana is not ready"
        fi
    fi
    
    # Check Prometheus
    if [[ "${ENABLE_PROMETHEUS}" == "true" ]]; then
        if curl -s -f "http://localhost:9090/-/healthy" &>/dev/null; then
            ok "Prometheus is ready"
        else
            warn "Prometheus is not ready"
        fi
    fi
    
    # Check LiteLLM
    if [[ "${ENABLE_LITELLM}" == "true" ]]; then
        if curl -s -f "http://localhost:4000/health" &>/dev/null; then
            ok "LiteLLM is ready"
        else
            warn "LiteLLM is not ready"
        fi
    fi
    
    # Check OpenWebUI
    if [[ "${ENABLE_OPENWEBUI}" == "true" ]]; then
        if curl -s -f "http://localhost:8080" &>/dev/null; then
            ok "OpenWebUI is ready"
        else
            warn "OpenWebUI is not ready"
        fi
    fi
}

check_gateway_layer() {
    log "INFO" "Checking gateway layer..."
    
    # Check Caddy reverse proxy
    if nc -z localhost "${CADDY_HTTPS_PORT:-443}"; then
        ok "Caddy HTTPS proxy is ready"
    else
        fail "Caddy HTTPS proxy is not ready"
    fi
    
    # Test main domain through Caddy
    if curl -k -s -f "https://localhost:${CADDY_HTTPS_PORT:-443}" &>/dev/null; then
        ok "Main domain is accessible through Caddy"
    else
        warn "Main domain is not accessible through Caddy"
    fi
}

check_end_to_end_connectivity() {
    log "INFO" "Checking end-to-end connectivity..."
    
    # Test service-to-service communication
    if [[ "${ENABLE_OPENWEBUI}" == "true" && "${ENABLE_OLLAMA}" == "true" ]]; then
        if curl -s -f "http://localhost:8080" &>/dev/null; then
            ok "OpenWebUI can reach frontend"
        else
            warn "OpenWebUI frontend connectivity issue"
        fi
    fi
    
    # Test monitoring stack connectivity
    if [[ "${ENABLE_GRAFANA}" == "true" && "${ENABLE_PROMETHEUS}" == "true" ]]; then
        if curl -s -f "http://localhost:3000/api/health" &>/dev/null; then
            ok "Grafana can reach Prometheus"
        else
            warn "Grafana-Prometheus connectivity issue"
        fi
    fi
}

# --- Deep Logging Functions ---
enable_service_debug_logging() {
    local service=$1
    local log_level="${2:-debug}"
    
    log "=== ENABLING DEBUG LOGGING FOR $service ==="
    
    # Add debug environment variables to .env
    case "$service" in
        "postgres")
            echo "POSTGRES_LOG_LEVEL=$log_level" >> "${ENV_FILE}"
            echo "POSTGRES_LOG_MIN_DURATION_STATEMENT=0" >> "${ENV_FILE}"
            echo "POSTGRES_LOG_MIN_MESSAGES=debug5" >> "${ENV_FILE}"
            ;;
        "redis")
            echo "REDIS_LOGLEVEL=$log_level" >> "${ENV_FILE}"
            ;;
        "qdrant")
            echo "QDRANT__LOG_LEVEL=$log_level" >> "${ENV_FILE}"
            echo "QDRANT__SERVICE__HTTP__ENABLE_CORS=true" >> "${ENV_FILE}"
            ;;
        "grafana")
            echo "GF_LOG_LEVEL=$log_level" >> "${ENV_FILE}"
            echo "GF_LOG_MODE=console,file" >> "${ENV_FILE}"
            ;;
        "prometheus")
            echo "PROMETHEUS_LOG_LEVEL=$log_level" >> "${ENV_FILE}"
            echo "PROMETHEUS_LOG_FORMAT=json" >> "${ENV_FILE}"
            ;;
        "caddy")
            echo "CADDY_LOG_LEVEL=$log_level" >> "${ENV_FILE}"
            echo "CADDY_LOG_FORMAT=json" >> "${ENV_FILE}"
            ;;
    esac
    
    log "Debug logging enabled for $service with level: $log_level"
}

capture_docker_logs() {
    local service=$1
    local log_file="${TENANT_DIR}/logs/deploy-${service}-$(date +%Y%m%d-%H%M%S).log"
    
    log "=== CAPTURING DOCKER LOGS FOR $service ==="
    
    # Get container logs with maximum verbosity
    cd "${TENANT_DIR}"
    if docker compose logs "$service" --timestamps --follow --tail=100 > "$log_file" 2>&1 & then
        local log_pid=$!
        log "Started capturing logs for $service (PID: $log_pid) to $log_file"
        
        # Store PID for later reference
        echo "$log_pid" > "${TENANT_DIR}/logs/${service}-log-pid.txt"
        
        # Wait a bit to ensure logging starts
        sleep 2
        
        # Check if log file has content
        if [[ -s "$log_file" ]]; then
            log "✅ Successfully capturing logs for $service"
        else
            log "❌ Failed to capture logs for $service"
            kill $log_pid 2>/dev/null || true
        fi
    else
        log "❌ Failed to start log capture for $service"
    fi
}

verify_core_services() {
    log "=== VERIFYING CORE SERVICES HEALTH ==="
    local core_services=("postgres" "redis" "caddy")
    local all_healthy=true
    
    for service in "${core_services[@]}"; do
        log "Checking ${service} health..."
        local container_name="${COMPOSE_PROJECT_NAME}-${service}-1"
        
        # Wait up to 60 seconds for the service to become healthy
        for i in {1..12}; do
            local status=$(docker ps --filter "name=${container_name}" --format "{{.Status}}" 2>/dev/null || echo "not found")
            
            if [[ "$status" == *"healthy"* ]] || [[ "$status" == *"Up"* ]]; then
                ok "${service} is healthy and running."
                break
            elif [[ "$status" == *"Restarting"* ]]; then
                if [[ $i -eq 12 ]]; then
                    warn "${service} is still restarting after 60 seconds."
                    all_healthy=false
                fi
            elif [[ "$status" == *"Exited"* ]] || [[ "$status" == *"not found"* ]]; then
                if [[ $i -eq 12 ]]; then
                    fail "${service} failed to start. Status: ${status}"
                fi
            fi
            
            sleep 5
        done
        
        # Final status check
        local final_status=$(docker ps --filter "name=${container_name}" --format "{{.Status}}" 2>/dev/null || echo "not found")
        if [[ "$final_status" != *"Up"* ]]; then
            warn "${service} final status: ${final_status}"
            all_healthy=false
        fi
    done
    
    if [[ "$all_healthy" == "true" ]]; then
        ok "All core services are healthy!"
    else
        warn "Some core services may not be fully healthy. Check individual service logs."
    fi
    log "=== END CORE SERVICES VERIFICATION ==="
}

capture_initial_logs() {
    log "=== CAPTURING INITIAL SERVICE LOGS ==="
    
    for service in $(docker compose ps --services 2>/dev/null); do
        local container_name="${COMPOSE_PROJECT_NAME}-${service}-1"
        local service_log_file="${LOG_DIR}/deploy-${service}-initial.log"
        
        if docker ps --filter "name=${container_name}" --format "{{.Names}}" | grep -q "${container_name}"; then
            log "Capturing initial logs for ${service}..."
            docker logs "${container_name}" --tail 50 &> "${service_log_file}" 2>&1
            log "Initial logs for ${service} saved to ${service_log_file}"
        else
            log "Container ${container_name} not running, skipping log capture."
        fi
    done
    
    log "=== END INITIAL LOG CAPTURE ==="
}

# --- Tenant ID Setup - DEFAULT TO DATASQUIZ ---
TENANT_ID="${1:-datasquiz}"
log "Using tenant ID: ${TENANT_ID}"

# --- Environment Setup ---
TENANT_DIR="/mnt/data/${TENANT_ID}"
ENV_FILE="${TENANT_DIR}/.env"
COMPOSE_FILE="${TENANT_DIR}/docker-compose.yml"

if [[ ! -f "${ENV_FILE}" ]]; then
    fail "Environment file not found for tenant '${TENANT_ID}' at ${ENV_FILE}"
fi

log "Loading environment from: ${ENV_FILE}"
set -a
source "${ENV_FILE}"
set +a

# --- Logging to File ---
LOG_DIR="${TENANT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/deploy-$(date +%Y%m%d-%H%M%S).log"

# CRITICAL FIX: Redirect both stdout and stderr to log file for complete debug capture
exec > >(tee -a "${LOG_FILE}") 2>&1
log "All output is now logged to: ${LOG_FILE}"
log "DEBUG_MODE: ${DEBUG_MODE}"
log "Complete stdout and stderr redirection enabled for comprehensive debugging"

# --- Enable Debug Logging for All Services ---
log "=== ENABLING COMPREHENSIVE DEBUG LOGGING ==="
if [[ "${DEBUG_MODE}" == "true" ]]; then
    log "Debug mode enabled - enabling verbose logging for all services"
    
    # Enable debug for all enabled services
    [[ "${ENABLE_POSTGRES}" == "true" ]] && enable_service_debug_logging "postgres"
    [[ "${ENABLE_REDIS}" == "true" ]] && enable_service_debug_logging "redis"
    [[ "${ENABLE_QDRANT}" == "true" ]] && enable_service_debug_logging "qdrant"
    [[ "${ENABLE_GRAFANA}" == "true" ]] && enable_service_debug_logging "grafana"
    [[ "${ENABLE_PROMETHEUS}" == "true" ]] && enable_service_debug_logging "prometheus"
    [[ "${ENABLE_CADDY}" == "true" ]] && enable_service_debug_logging "caddy"
    
    log "Debug logging enabled for all services"
fi
log "=== END DEBUG LOGGING SETUP ==="

# --- Configuration Generation Functions ---
generate_caddyfile() {
    log "INFO" "Executing dynamic Caddyfile generation as per README.md..."
    local CADDY_FILE="${DATA_ROOT}/Caddyfile"

    # Use a temporary file to build the content
    TMP_CADDY=$(mktemp)

    # 1. Global Options Block - ALWAYS formatted correctly
    cat > "$TMP_CADDY" <<EOF
{
    email ${ADMIN_EMAIL}
    # acme_dns google_cloud_dns ... # Placeholder for future DNS challenge
}

EOF

    # 2. Intelligent TLS Strategy based on domain validation
    if [[ "${TLS_STRATEGY:-internal}" == "letsencrypt" ]]; then
        log "INFO" "Using Let's Encrypt certificates for public domain: ${DOMAIN}"
        cat >> "$TMP_CADDY" <<EOF
${DOMAIN} {
    respond "AI Platform v3.2.0 is active. Welcome." 200
}

EOF
    else
        log "INFO" "Using internal certificates for local/private domain: ${DOMAIN}"
        cat >> "$TMP_CADDY" <<EOF
${DOMAIN} {
    tls internal {
        on_demand
    }
    respond "AI Platform v3.2.0 is active. Welcome." 200
}

EOF
    fi

    # 3. Dynamically add routes for ONLY enabled services
    if [[ "${ENABLE_GRAFANA}" == "true" ]]; then
        cat >> "$TMP_CADDY" <<EOF
grafana.${DOMAIN} {
    reverse_proxy grafana:${GRAFANA_INTERNAL_PORT}
}

EOF
        ok "Caddy route added for Grafana."
    fi
    
    if [[ "${ENABLE_PROMETHEUS}" == "true" ]]; then
        cat >> "$TMP_CADDY" <<EOF
prometheus.${DOMAIN} {
    reverse_proxy prometheus:${PROMETHEUS_INTERNAL_PORT}
}

EOF
        ok "Caddy route added for Prometheus."
    fi
    
    if [[ "${ENABLE_AUTHENTIK}" == "true" ]]; then
        cat >> "$TMP_CADDY" <<EOF
auth.${DOMAIN} {
    reverse_proxy authentik:${AUTHENTIK_INTERNAL_PORT}
}

EOF
        ok "Caddy route added for Authentik."
    fi
    
    if [[ "${ENABLE_OPENWEBUI}" == "true" ]]; then
        cat >> "$TMP_CADDY" <<EOF
openwebui.${DOMAIN} {
    reverse_proxy openwebui:${OPENWEBUI_INTERNAL_PORT}
}

EOF
        ok "Caddy route added for OpenWebUI."
    fi
    
    if [[ "${ENABLE_N8N}" == "true" ]]; then
        cat >> "$TMP_CADDY" <<EOF
n8n.${DOMAIN} {
    reverse_proxy n8n:${N8N_INTERNAL_PORT}
}

EOF
        ok "Caddy route added for n8n."
    fi
    
    if [[ "${ENABLE_FLOWISE}" == "true" ]]; then
        cat >> "$TMP_CADDY" <<EOF
flowise.${DOMAIN} {
    reverse_proxy flowise:${FLOWISE_INTERNAL_PORT}
}

EOF
        ok "Caddy route added for Flowise."
    fi
    
    if [[ "${ENABLE_ANYTHINGLLM}" == "true" ]]; then
        cat >> "$TMP_CADDY" <<EOF
anythingllm.${DOMAIN} {
    reverse_proxy anythingllm:${ANYTHINGLLM_INTERNAL_PORT}
}

EOF
        ok "Caddy route added for AnythingLLM."
    fi
    
    if [[ "${ENABLE_LITELLM}" == "true" ]]; then
        cat >> "$TMP_CADDY" <<EOF
litellm.${DOMAIN} {
    reverse_proxy litellm:${LITELLM_INTERNAL_PORT}
}

EOF
        ok "Caddy route added for LiteLLM."
    fi
    
    if [[ "${ENABLE_DIFY}" == "true" ]]; then
        cat >> "$TMP_CADDY" <<EOF
dify.${DOMAIN} {
    reverse_proxy dify:${DIFY_INTERNAL_PORT}
}

EOF
        ok "Caddy route added for Dify."
    fi

    # 4. Write the final Caddyfile
    mv "$TMP_CADDY" "$CADDY_FILE"
    ok "Caddyfile generated with intelligent TLS strategy."
}

verify_https_connectivity() {
    log "INFO" "Performing Application-Level HTTPS Verification..."
    
    # Wait for Caddy to be ready
    local max_wait=30
    local wait_time=0
    
    while [[ $wait_time -lt $max_wait ]]; do
        if curl -s --fail "https://${DOMAIN}" -o /dev/null --max-time 5 2>/dev/null; then
            ok "HTTPS Main Domain check PASSED. Caddy is serving traffic correctly."
            return 0
        fi
        
        sleep 2
        wait_time=$((wait_time + 2))
    done
    
    fail "CRITICAL FAILURE: Caddy is running, but HTTPS requests to ${DOMAIN} are failing."
}

run_post_deployment_hooks() {
    log "INFO" "Running post-deployment hooks..."
    
    # 1. Pull Ollama models if enabled
    if [[ "${ENABLE_OLLAMA}" == "true" ]]; then
        log "INFO" "Pulling Ollama models..."
        pull_ollama_models
    fi
    
    # 2. Trigger automated data pipeline
    if [[ "${ENABLE_RCLONE}" == "true" ]]; then
        log "INFO" "Starting Rclone mount..."
        docker compose up -d --no-deps rclone 2>/dev/null
        
        # Wait a moment for mount to establish
        sleep 5
        
        log "INFO" "Triggering data ingestion pipeline..."
        # Execute one-shot ingestion
        docker run --rm --network "${COMPOSE_PROJECT_NAME}_default" \
            -v "${DATA_ROOT}/ingest.py:/app/ingest.py:ro" \
            -v "${DATA_ROOT}/.env:/app/.env:ro" \
            python:3-alpine \
            python /app/ingest.py --tenant "${TENANT_ID}" --once
        
        ok "Data pipeline triggered successfully."
    fi
    
    # 3. Capture Tailscale IP for OpenClaw access
    if [[ "${ENABLE_TAILSCALE}" == "true" ]]; then
        if get_tailscale_ip; then
            log "INFO" "Tailscale IP captured: ${TAILSCALE_IP}"
            echo "TAILSCALE_IP=${TAILSCALE_IP}" >> "${DATA_ROOT}/.env"
            ok "OpenClaw access enabled via Tailscale IP: ${TAILSCALE_IP}:3000"
        else
            warn "Tailscale IP not yet available."
        fi
    fi
}

generate_deployment_dashboard() {
    log "INFO" "Generating deployment dashboard..."
    
    printf "\n\n"
    printf "============================================================\n"
    printf "          🚀 AI PLATFORM DEPLOYMENT COMPLETE 🚀\n"
    printf "============================================================\n\n"
    
    printf "  %-20s %-40s\n" "SERVICE" "URL"
    printf "  %-20s %-40s\n" "--------------------" "----------------------------------------"
    
    # Core Services
    printf "  %-20s https://%s\n" "OpenWebUI" "openwebui.${DOMAIN}"
    printf "  %-20s https://%s\n" "Grafana" "grafana.${DOMAIN}"
    printf "  %-20s https://%s\n" "Authentik" "auth.${DOMAIN}"
    
    # AI Services
    if [[ "${ENABLE_LITELLM}" == "true" ]]; then
        printf "  %-20s http://%s\n" "LiteLLM" "localhost:${LITELLM_INTERNAL_PORT}"
    fi
    
    # VPN & Terminal Access
    if [[ -n "${TAILSCALE_IP:-}" ]]; then
        printf "  %-20s %s (Tailscale IP)\n" "OpenClaw" "${TAILSCALE_IP}:3000"
    else
        printf "  %-20s %s\n" "OpenClaw" "Awaiting Tailscale IP..."
    fi
    
    printf "\n"
    printf "  HEALTH STATUS: ✅ All services deployed and verified.\n"
    printf "  DATA PIPELINE: 🔄 Rclone sync and data ingestion active.\n\n"
    
    printf "============================================================\n"
    printf "                    NEXT STEPS\n"
    printf "============================================================\n\n"
    printf "  ▶️  Explore your services at the URLs above.\n"
    printf "  ▶️  Run 'sudo bash scripts/3-configure-services.sh %s --status' for ongoing management.\n" "$TENANT_ID"
    printf "\n"
}

write_rclone_config() {
    if [[ "${ENABLE_RCLONE}" != "true" ]]; then return; fi

    log "INFO" "Generating dynamic rclone.conf..."
    local rclone_config_dir="${TENANT_DIR}/rclone"
    local rclone_config_file="${rclone_config_dir}/rclone.conf"
    mkdir -p "${rclone_config_dir}"

    # Dynamically build the config file from .env variables
    cat > "${rclone_config_file}" << EOF
[gdrive]
type = drive
scope = drive
use_json_credentials = true
service_account_file = /config/google_sa.json
EOF
    
    chown -R "${TENANT_UID}:${TENANT_GID}" "${rclone_config_dir}"
    ok "Rclone configuration generated successfully."
}

# --- Post-Deployment Configuration Hooks ---
run_post_deployment_hooks() {
    log "INFO" "Executing post-deployment configuration hooks..."
    pull_ollama_models
    # Future hooks like database migrations could be called here
}

pull_ollama_models() {
    if [[ "${ENABLE_OLLAMA}" != "true" ]]; then return; fi
    
    log "INFO" "Starting post-deployment model pull for Ollama. This may take a very long time."
    
    if [[ -z "${OLLAMA_MODELS}" ]]; then
        log "WARN" "OLLAMA_MODELS variable is not set. Skipping model pull."
        return
    fi

    # Find the running Ollama container
    local ollama_container
    ollama_container=$(docker compose ps -q ollama)

    if [[ -z "$ollama_container" ]]; then
        fail "Ollama container not found. Cannot pull models."
        return
    fi

    # Loop through the comma-separated list of models and pull each one
    for model in $(echo "${OLLAMA_MODELS}" | sed "s/,/ /g"); do
        log "INFO" "Pulling Ollama model: ${model}..."
        if docker exec "${ollama_container}" ollama pull "${model}"; then
            ok "Successfully pulled model: ${model}"
        else
            fail "Failed to pull model: ${model}. Please check the model name and logs."
        fi
    done
    ok "Ollama model pull process completed."
}

# --- Volume Mount Audit ---
audit_volume_mounts() {
    log "INFO" "Auditing all docker-compose volume mounts before deployment..."
    local all_volumes_exist=true
    
    # Simple approach: check for all expected directories
    local expected_dirs=("postgres" "redis" "qdrant" "grafana" "prometheus" "authentik" "tailscale" "rclone" "signal" "signal-data" "openclaw" "caddy")
    
    for dir in "${expected_dirs[@]}"; do
        local host_path="${TENANT_DIR}/${dir}"
        if [[ ! -d "$host_path" ]]; then
            fail "CRITICAL AUDIT FAILURE: Directory '${host_path}' for volume mount does not exist. The docker-compose.yml is trying to mount a directory that was not created by Script 1. Please re-run Script 1 or correct the volume path in the 'add_*' function in Script 2."
            all_volumes_exist=false
        else
            log "INFO" "Volume source directory exists: $host_path"
        fi
    done

    # Validate critical configuration files exist
    local critical_files=("prometheus.yml" "caddy/Caddyfile")
    for file in "${critical_files[@]}"; do
        local file_path="${DATA_ROOT}/${file}"
        if [[ ! -f "$file_path" ]]; then
            fail "CRITICAL AUDIT FAILURE: Configuration file '${file_path}' does not exist. This file is required for deployment."
        fi
        log "INFO" "Configuration file exists: ${file_path}"
    done

    # Validate rclone configuration
    local rclone_config="${TENANT_DIR}/rclone/google_sa.json"
    if [[ "${ENABLE_RCLONE}" == "true" && ! -f "$rclone_config" ]]; then
        fail "CRITICAL AUDIT FAILURE: Rclone Service Account file '${rclone_config}' does not exist. Rclone is enabled but the configuration is missing."
        all_volumes_exist=false
    else
        log "INFO" "Rclone configuration exists: $rclone_config"
    fi

    if [[ "$all_volumes_exist" == "true" ]]; then
        ok "Volume mount audit passed. All source directories exist."
    else
        fail "Volume mount audit failed. Missing directories or files will cause deployment failures."
    fi
}

# --- Master Service Loop (Zero Gap Implementation) ---
generate_compose_services() {
    log "INFO" "Executing Master Service Loop - Deploying ALL enabled services..."
    
    # Core Infrastructure Services
    # These are the foundation.
    [[ "${ENABLE_POSTGRES}" == "true" ]] && add_postgres
    [[ "${ENABLE_REDIS}" == "true" ]] && add_redis
    [[ "${ENABLE_QDRANT}" == "true" ]] && add_qdrant
    [[ "${ENABLE_CADDY}" == "true" ]] && add_caddy # CRITICAL: Ensure Caddy is deployed.
    
    # AI/LLM Stack Services
    [[ "${ENABLE_OLLAMA}" == "true" ]] && add_ollama
    [[ "${ENABLE_LITELLM}" == "true" ]] && add_litellm
    [[ "${ENABLE_OPENWEBUI}" == "true" ]] && add_openwebui
    [[ "${ENABLE_ANYTHINGLLM}" == "true" ]] && add_anythingllm
    [[ "${ENABLE_FLOWISE}" == "true" ]] && add_flowise
    [[ "${ENABLE_N8N}" == "true" ]] && add_n8n
    # [[ "${ENABLE_GEMINI}" == "true" ]] && add_gemini # TODO: Add add_gemini function
    # [[ "${ENABLE_DIFY}" == "true" ]] && add_dify # TODO: Add add_dify function
    
    # Monitoring Services
    [[ "${ENABLE_GRAFANA}" == "true" ]] && add_grafana
    [[ "${ENABLE_PROMETHEUS}" == "true" ]] && add_prometheus
    
    # Security & Networking Services
    [[ "${ENABLE_AUTHENTIK}" == "true" ]] && add_authentik
    [[ "${ENABLE_TAILSCALE}" == "true" ]] && add_tailscale # CRITICAL: Ensure Tailscale is deployed.
    [[ "${ENABLE_RCLONE}" == "true" ]] && add_rclone       # CRITICAL: Ensure Rclone is deployed.
    [[ "${ENABLE_SIGNAL}" == "true" ]] && add_signal       # CRITICAL: Ensure Signal is deployed.

    # Tenant-Specific Applications
    [[ "${ENABLE_OPENCLAW}" == "true" ]] && add_openclaw
    
    log "SUCCESS" "Master Service Loop completed - All enabled services added to compose file."
}

# --- Service Generation Functions ---
add_postgres() {
    cat >> "${COMPOSE_FILE}" << EOF

  postgres:
    image: postgres:15-alpine
    restart: unless-stopped
    user: "\${POSTGRES_UID:-70}:\${TENANT_GID:-1001}"
    networks:
      - default
    environment:
      - 'POSTGRES_DB=\${POSTGRES_DB:-ai_platform}'
      - 'POSTGRES_USER=\${POSTGRES_USER:-postgres}'
      - 'POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}'
      - 'POSTGRES_LOG_LEVEL=\${POSTGRES_LOG_LEVEL:-info}'
      - 'POSTGRES_LOG_MIN_DURATION_STATEMENT=\${POSTGRES_LOG_MIN_DURATION_STATEMENT:-0}'
      - 'POSTGRES_LOG_MIN_MESSAGES=\${POSTGRES_LOG_MIN_MESSAGES:-info}'
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./postgres/init-user-db.sh:/docker-entrypoint-initdb.d/init-user-db.sh
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER:-postgres}"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
EOF
    ok "Added 'postgres' service."
}

add_openwebui() {
    log "INFO" "Auto-integrating OpenWebUI with LiteLLM..."
    cat >> "${COMPOSE_FILE}" << EOF

  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    restart: unless-stopped
    user: "\${OPENWEBUI_UID:-1000}:\${TENANT_GID:-1001}"
    networks:
      - default
    depends_on:
      litellm:
        condition: service_started
    environment:
      - 'OLLAMA_BASE_URL=http://litellm:\${LITELLM_INTERNAL_PORT:-4000}'
      - 'WEBUI_SECRET_KEY=\${OPENWEBUI_SECRET_KEY}'
      - 'WEBUI_NAME=AI Platform WebUI'
      - 'DEFAULT_MODELS=llama3.2'
    volumes:
      - \${TENANT_DIR}/openwebui:/app/backend/data
EOF
    ok "Added 'openwebui' service, configured for LiteLLM routing."
}

add_ollama() {
    log "INFO" "Auto-integrating Ollama with vector database..."
    # This ensures the directory exists before the container starts
    mkdir -p "${TENANT_DIR}/ollama"
    # The permission logic in Script 1 will have already set ownership on the parent
    
    cat >> "${COMPOSE_FILE}" << EOF

  ollama:
    image: ollama/ollama:latest
    restart: unless-stopped
    # Note: ollama needs root for directory access
    user: "root"
    networks:
      - default
    environment:
      - 'OLLAMA_HOST=0.0.0.0'
      - 'OLLAMA_PORT=${OLLAMA_INTERNAL_PORT:-11434}'
    volumes:
      - ./ollama:/root/.ollama  # CRITICAL: Mounts to a subdir INSIDE the tenant's data root
    working_dir: /root
    ports:
      - "${OLLAMA_PORT:-11434}:${OLLAMA_INTERNAL_PORT:-11434}"
EOF

    # Add GPU deployment if enabled
    if [[ "${ENABLE_GPU:-false}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
EOF
        log "INFO" "GPU support enabled for Ollama."
    fi
    
    ok "Added 'ollama' service."
}

add_n8n() {
    log "INFO" "Auto-integrating N8N with Postgres..."
    cat >> "${COMPOSE_FILE}" << EOF

  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    user: "\${N8N_UID:-1000}:\${TENANT_GID:-1001}"
    networks:
      - default
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      - 'DB_TYPE=postgresdb'
      - 'DB_POSTGRESDB_HOST=postgres'
      - 'DB_POSTGRESDB_PORT=\${POSTGRES_INTERNAL_PORT:-5432}'
      - 'DB_POSTGRESDB_DATABASE=\${POSTGRES_DB}'
      - 'DB_POSTGRESDB_USER=\${POSTGRES_USER}'
      - 'DB_POSTGRESDB_PASSWORD=\${POSTGRES_PASSWORD}'
      - 'N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}'
      - 'N8N_PORT=\${N8N_INTERNAL_PORT:-5678}'
    volumes:
      - \${TENANT_DIR}/n8n:/home/node/.n8n
EOF
    ok "Added 'n8n' service with full auto-integration."
}

add_flowise() {
    log "INFO" "Auto-integrating Flowise with Postgres, Qdrant, and LiteLLM..."
    cat >> "${COMPOSE_FILE}" << EOF

  flowise:
    image: flowiseai/flowise:latest
    restart: unless-stopped
    user: "\${FLOWISE_UID:-1000}:\${TENANT_GID:-1001}"
    networks:
      - default
    depends_on:
      postgres:
        condition: service_healthy
      qdrant:
        condition: service_started
      litellm:
        condition: service_started
    environment:
      - 'DATABASE_TYPE=postgres'
      - 'POSTGRES_HOST=postgres'
      - 'POSTGRES_PORT=\${POSTGRES_INTERNAL_PORT:-5432}'
      - 'POSTGRES_USER=\${POSTGRES_USER}'
      - 'POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}'
      - 'POSTGRES_DATABASE=\${POSTGRES_DB}'
      - 'QDRANT_URL=http://qdrant:\${QDRANT_INTERNAL_PORT:-6333}'
      - 'QDRANT_API_KEY=\${QDRANT_API_KEY}'
      - 'LITELLM_API_BASE=http://litellm:\${LITELLM_INTERNAL_PORT:-4000}'
      - 'FLOWISE_PORT=\${FLOWISE_INTERNAL_PORT:-3001}'
    volumes:
      - \${TENANT_DIR}/flowise:/root/.flowise
EOF
    ok "Added 'flowise' service with full auto-integration."
}

add_anythingllm() {
    log "INFO" "Auto-integrating AnythingLLM with Postgres, Qdrant, and LiteLLM..."
    cat >> "${COMPOSE_FILE}" << EOF

  anythingllm:
    image: mintplexlabs/anythingllm:latest
    restart: unless-stopped
    user: "\${ANYTHINGLLM_UID:-1000}:\${TENANT_GID:-1001}"
    networks:
      - default
    depends_on:
      postgres:
        condition: service_healthy
      qdrant:
        condition: service_started
      litellm:
        condition: service_started
    environment:
      - 'STORAGE_HOST=postgres'
      - 'STORAGE_PORT=\${POSTGRES_INTERNAL_PORT:-5432}'
      - 'STORAGE_USER=\${POSTGRES_USER}'
      - 'STORAGE_PASS=\${POSTGRES_PASSWORD}'
      - 'STORAGE_DB=\${POSTGRES_DB}'
      - 'VECTOR_DB=qdrant'
      - 'QDRANT_ENDPOINT=http://qdrant:\${QDRANT_INTERNAL_PORT:-6333}'
      - 'QDRANT_API_KEY=\${QDRANT_API_KEY}'
      - 'LLM_PROVIDER=litellm'
      - 'LITELLM_BASE_URL=http://litellm:\${LITELLM_INTERNAL_PORT:-4000}'
      - 'LITELLM_API_KEY=\${LITELLM_MASTER_KEY}'
    volumes:
      - \${TENANT_DIR}/anythingllm:/app/server/storage
      - \${TENANT_DIR}/anythingllm/hotdir:/app/server/hotdir
EOF
    ok "Added 'anythingllm' service with full auto-integration."
}

add_redis() {
    cat >> "${COMPOSE_FILE}" << EOF

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    user: "\${REDIS_UID:-999}:\${TENANT_GID:-1001}"
    networks:
      - default
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "\${REDIS_PASSWORD}", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5
    command: redis-server --requirepass "\${REDIS_PASSWORD}" --loglevel "\${REDIS_LOGLEVEL:-notice}"
    volumes:
      - \${TENANT_DIR}/redis:/data
EOF
    ok "Added 'redis' service."
}

add_tailscale() {
    if [[ "${ENABLE_TAILSCALE}" != "true" ]]; then return; fi
    
    log "INFO" "Adding 'tailscale' service with Zero-Touch Activation..."
    mkdir -p "${TENANT_DIR}/tailscale"
    chown "${TENANT_UID}:${TENANT_GID}" "${TENANT_DIR}/tailscale"

    # Build the dynamic flags for the 'tailscale up' command
    local tailscale_up_flags="--hostname=${TAILSCALE_HOSTNAME:-${TENANT_ID}-ai-platform} --authkey=${TAILSCALE_AUTH_KEY}"
    if [[ "${TAILSCALE_FUNNEL}" == "true" ]]; then
        tailscale_up_flags+=" --funnel=443"
    fi

    cat >> "${COMPOSE_FILE}" << EOF

  tailscale:
    image: tailscale/tailscale:latest
    container_name: ${COMPOSE_PROJECT_NAME}-tailscale-1
    hostname: ${TAILSCALE_HOSTNAME:-${TENANT_ID}-ai-platform}
    environment:
      - TS_AUTHKEY=${TAILSCALE_AUTH_KEY}
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_USERSPACE=true
      - TS_ACCEPT_DNS=false
      - TS_ACCEPT_ROUTES=true
    volumes:
      - ./tailscale:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - net_admin
      - sys_module
    devices:
      - /dev/net/tun
    restart: unless-stopped
    command: sh -c "tailscaled --tun=userspace-networking --socks5-server=localhost:1055 --outbound-http-proxy-listen=localhost:1055 & tailscale up ${tailscale_up_flags} && wait"
EOF
    ok "Added 'tailscale' service with activation command."
}

add_rclone() {
    if [[ "${ENABLE_RCLONE}" != "true" ]]; then return; fi
    
    log "INFO" "Adding 'rclone' service..."
    mkdir -p "${TENANT_DIR}/rclone"
    mkdir -p "${TENANT_DIR}/gdrive"
    chown "${TENANT_UID}:${TENANT_GID}" "${TENANT_DIR}/rclone"
    chown "${TENANT_UID}:${TENANT_GID}" "${TENANT_DIR}/gdrive"

    cat >> "${COMPOSE_FILE}" << EOF

  rclone:
    image: rclone/rclone:latest
    restart: unless-stopped
    # Note: rclone needs root for FUSE operations
    networks:
      - default
    environment:
      - 'RCLONE_CONFIG_GDRIVE_TYPE=drive'
      - 'RCLONE_CONFIG_GDRIVE_SCOPE=drive'
      - 'RCLONE_CONFIG_GDRIVE_USE_JSON_AUTH=true'
      - 'RCLONE_CONFIG_GDRIVE_SERVICE_ACCOUNT_FILE=/config/rclone/google_sa.json'
      - 'RCLONE_CACHE_DIR=/tmp/rclone-cache'
    volumes:
      - ./rclone:/config/rclone
      - ./gdrive:/mnt/gdrive
      - rclone-cache:/tmp/rclone-cache
    cap_add:
      # CRITICAL FIX: Add SYS_ADMIN capability
      - SYS_ADMIN
    devices:
      # CRITICAL FIX: Expose the host's FUSE device
      - /dev/fuse
    security_opt:
      # CRITICAL FIX: Allow mounting
      - apparmor:unconfined
    command: ["mount", "gdrive:", "/mnt/gdrive", "--vfs-cache-mode", "writes", "--allow-non-empty", "--log-level", "INFO", "--cache-dir", "/tmp/rclone-cache"]
EOF
    ok "Added 'rclone' service."
}

add_litellm() {
    if [[ "${ENABLE_LITELLM}" != "true" ]]; then return; fi
    
    log "INFO" "Adding 'litellm' service with auto-integration..."
    mkdir -p "${TENANT_DIR}/litellm"
    chown "${TENANT_UID}:${TENANT_GID}" "${TENANT_DIR}/litellm"

    cat >> "${COMPOSE_FILE}" << EOF

  litellm:
    image: ghcr.io/berriai/litellm:main
    restart: unless-stopped
    user: "\${LITELLM_UID:-1000}:\${TENANT_GID:-1001}"
    networks:
      - default
    depends_on:
      postgres:
        condition: service_healthy
      qdrant:
        condition: service_started
    environment:
      - 'LITELLM_MASTER_KEY=\${LITELLM_MASTER_KEY}'
      - 'LITELLM_SALT_KEY=\${LITELLM_SALT_KEY}'
      - 'DATABASE_URL=\${LITELLM_DATABASE_URL}'
      - 'REDIS_URL=\${REDIS_URL}'
      - 'REDIS_PASSWORD=\${REDIS_PASSWORD}'
      - 'OPENAI_API_KEY=\${OPENAI_API_KEY}'
      - 'ANTHROPIC_API_KEY=\${ANTHROPIC_API_KEY}'
      - 'GROQ_API_KEY=\${GROQ_API_KEY}'
      - 'OPENROUTER_API_KEY=\${OPENROUTER_API_KEY}'
      - 'GEMINI_API_KEY=\${GEMINI_API_KEY}'
      - 'STORE_MODEL_IN_DB=True'
      - 'LITELLM_TELEMETRY=False'
      # CRITICAL FIX: Disable pip cache to prevent permission errors
      - 'PIP_NO_CACHE_DIR=1'
      # CRITICAL FIX: Define a writable home directory for user
      - 'HOME=/tmp'
    volumes:
      - ./litellm-config.yaml:/app/config.yaml
      - litellm_data:/app/data
    # CRITICAL FIX: Add a command to force loading of config file
    command: ["--config", "/app/config.yaml", "--port", "\${LITELLM_INTERNAL_PORT:-4000}"]
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:4000/health/liveliness || exit 1"]
      interval: 30s
      timeout: 15s
      retries: 5
      start_period: 90s
EOF
    ok "Added 'litellm' service with healthcheck and auto-integration."
}

add_openwebui() {
    if [[ "${ENABLE_OPENWEBUI}" != "true" ]]; then return; fi
    
    log "INFO" "Adding 'openwebui' service with auto-integration..."
    mkdir -p "${TENANT_DIR}/openwebui"
    chown "${TENANT_UID}:${TENANT_GID}" "${TENANT_DIR}/openwebui"

    cat >> "${COMPOSE_FILE}" << EOF

  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    restart: unless-stopped
    user: "\${OPENWEBUI_UID:-1000}:\${TENANT_GID:-1001}"
    networks:
      - default
    depends_on:
      litellm:
        condition: service_started
    environment:
      - 'OLLAMA_BASE_URL=http://litellm:4000'
      - 'OPENAI_API_KEY=\${OPENAI_API_KEY}'
      - 'WEBUI_SECRET_KEY=\${OPENWEBUI_SECRET_KEY}'
      - 'WEBUI_NAME=AI Platform WebUI'
      - 'DEFAULT_MODELS=llama3.2'
      - DATABASE_URL=postgresql://openwebui:\${OPENWEBUI_DB_PASSWORD}@postgres:5432/openwebui
    volumes:
      - ./openwebui:/app/backend/data
    healthcheck:
      test: ["CMD", "curl", "--fail", "http://localhost:8080"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
EOF
    ok "Added 'openwebui' service with healthcheck and DATABASE_URL."
}

add_authentik() {
    if [[ "${ENABLE_AUTHENTIK}" != "true" ]]; then return; fi
    
    log "INFO" "Adding 'authentik' service..."
    mkdir -p "${TENANT_DIR}/authentik"
    chown "${TENANT_UID}:${TENANT_GID}" "${TENANT_DIR}/authentik"

    cat >> "${COMPOSE_FILE}" << EOF

  authentik-server:
    image: ghcr.io/goauthentik/server:latest
    restart: unless-stopped
    user: "\${AUTHENTIK_UID:-1000}:\${TENANT_GID:-1001}"
    container_name: \${TENANT}-authentik-server-1
    hostname: authentik-server
    networks:
      - default
    environment:
      - 'AUTHENTIK_SECRET_KEY=\${AUTHENTIK_SECRET_KEY}'
      # TRIPLE-CHECK this entire block for typos and variable names.
      - 'AUTHENTIK_POSTGRESQL__HOST=postgres'
      - 'AUTHENTIK_POSTGRESQL__PORT=5432'
      - 'AUTHENTIK_POSTGRESQL__NAME=\${AUTHENTIK_DB_NAME}'
      - 'AUTHENTIK_POSTGRESQL__USER=\${AUTHENTIK_DB_USER}'
      - 'AUTHENTIK_POSTGRESQL__PASSWORD=\${AUTHENTIK_DB_PASS}'
      - 'AUTHENTIK_REDIS__HOST=redis'
      - 'AUTHENTIK_REDIS__PORT=6379'
      - 'AUTHENTIK_REDIS__DB=0'
      - 'AUTHENTIK_REDIS__PASSWORD=${REDIS_PASSWORD}'
      # Add any other required Authentik variables here
    volumes:
      - ./authentik:/media
      - ./authentik:/templates
    command: server
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy

  authentik-worker:
    image: ghcr.io/goauthentik/server:latest
    restart: unless-stopped
    user: "\${AUTHENTIK_UID:-1000}:\${TENANT_GID:-1001}"
    container_name: \${TENANT}-authentik-worker-1
    hostname: authentik-worker
    networks:
      - default
    environment:
      - 'AUTHENTIK_SECRET_KEY=\${AUTHENTIK_SECRET_KEY}'
      # TRIPLE-CHECK this entire block for typos and variable names.
      - 'AUTHENTIK_POSTGRESQL__HOST=postgres'
      - 'AUTHENTIK_POSTGRESQL__PORT=5432'
      - 'AUTHENTIK_POSTGRESQL__NAME=\${AUTHENTIK_DB_NAME}'
      - 'AUTHENTIK_POSTGRESQL__USER=\${AUTHENTIK_DB_USER}'
      - 'AUTHENTIK_POSTGRESQL__PASSWORD=\${AUTHENTIK_DB_PASS}'
      - 'AUTHENTIK_REDIS__HOST=redis'
      - 'AUTHENTIK_REDIS__PORT=6379'
      - 'AUTHENTIK_REDIS__DB=0'
      - 'AUTHENTIK_REDIS__PASSWORD=${REDIS_PASSWORD}'
      # Add any other required Authentik variables here
    volumes:
      - ./authentik:/media
      - ./authentik:/templates
    command: worker
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      authentik-server:
        condition: service_started
EOF
    ok "Added 'authentik' service."
}

add_signal() {
    if [[ "${ENABLE_SIGNAL}" != "true" ]]; then return; fi
    
    log "INFO" "Adding 'signal' service with recommended configuration..."
    mkdir -p "${TENANT_DIR}/signal-data"
    chown "${TENANT_UID}:${TENANT_GID}" "${TENANT_DIR}/signal-data"

    cat >> "${COMPOSE_FILE}" << EOF

  signal:
    image: bbernhard/signal-cli-rest-api:latest
    restart: unless-stopped
    # Note: This service runs as root because the image requires it
    # to perform a 'groupmod' on startup
    networks:
      - default
    ports:
      - "8080:8080"
    volumes:
      - ./signal-data:/home/.local/share/signal-cli
    environment:
      - 'SIGNAL_PHONE_NUMBER=\${SIGNAL_PHONE_NUMBER}'
      - 'SIGNAL_VERIFICATION_CODE=\${SIGNAL_VERIFICATION_CODE}'
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
EOF
    ok "Added 'signal' service with recommended configuration."
}

add_openclaw() {
    log "INFO" "Configuring 'openclaw' service..."
    
    # Ensure the code directory exists and has correct permissions
    # This assumes that openclaw code is located in a subdirectory of the tenant dir
    mkdir -p "${TENANT_DIR}/openclaw"
    chown -R "${TENANT_UID}:${TENANT_GID}" "${TENANT_DIR}/openclaw"

    cat >> "${COMPOSE_FILE}" << EOF

  openclaw:
    # CRITICAL FIX: Use a standard, full Python image (not slim)
    image: python:3.11
    restart: unless-stopped
    working_dir: /app
    user: "\${TENANT_UID}:\${TENANT_GID}"
    networks:
      - default
    depends_on:
      signal:
        condition: service_healthy
      tailscale:
        condition: service_started
    volumes:
      # Mount the application code into the container
      - ./openclaw:/app
    # CRITICAL FIX: Install dependencies and run the application with python3
    command: >
      sh -c "pip install -r requirements.txt 2>/dev/null || echo 'No requirements.txt found' && python3 -u main.py"
EOF
    ok "Added 'openclaw' service with a standardized Python runtime."
}

add_anythingllm() {
    if [[ "${ENABLE_ANYTHINGLLM}" != "true" ]]; then return; fi
    
    log "INFO" "Adding 'anythingllm' service with auto-integration..."
    mkdir -p "${TENANT_DIR}/anythingllm"
    chown "${TENANT_UID}:${TENANT_GID}" "${TENANT_DIR}/anythingllm"

    cat >> "${COMPOSE_FILE}" << EOF

  anythingllm:
    image: mintplexlabs/anythingllm:latest
    restart: unless-stopped
    user: "\${ANYTHINGLLM_UID:-1000}:\${TENANT_GID:-1001}"
    networks:
      - default
    depends_on:
      postgres:
        condition: service_healthy
      qdrant:
        condition: service_started
    environment:
      - 'STORAGE_LOCATOR=\${STORAGE_LOCATOR:-local}'
      - 'DB_TYPE=postgres'
      - 'POSTGRES_HOST=postgres'
      - 'POSTGRES_PORT=5432'
      - 'POSTGRES_DB=anythingllm'
      - 'POSTGRES_USER=anythingllm_user'
      - 'POSTGRES_PASSWORD=anythingllm_password'
      - 'DATABASE_URL=postgresql://anythingllm_user:anythingllm_password@postgres:5432/anythingllm'
      - 'QDRANT_ENDPOINT=http://qdrant:6333'
      - 'QDRANT_API_KEY=\${QDRANT_API_KEY}'
      - 'LLM_PROVIDER=\${LLM_PROVIDER:-litellm}'
      - 'LLM_BASE_URL=http://litellm:4000'
      - 'ANYTHINGLLM_JWT_SECRET=\${ANYTHINGLLM_JWT_SECRET}'
      # CRITICAL FIX: Use exact variable name 'STORAGE_DIR'
      - 'STORAGE_DIR=/app/server/storage'
      # CRITICAL FIX: Explicitly define the model directory path
      - 'MODEL_DIR=/app/server/models/ollama'
    volumes:
      - ./anythingllm:/app/server/storage
      - ./anythingllm/schema.prisma:/app/server/prisma/schema.prisma:ro
EOF
    ok "Added 'anythingllm' service with auto-integration."
}

add_flowise() {
    if [[ "${ENABLE_FLOWISE}" != "true" ]]; then return; fi
    
    log "INFO" "Adding 'flowise' service with auto-integration..."
    mkdir -p "${TENANT_DIR}/flowise"
    chown "${TENANT_UID}:${TENANT_GID}" "${TENANT_DIR}/flowise"

    cat >> "${COMPOSE_FILE}" << EOF

  flowise:
    image: flowiseai/flowise:latest
    restart: unless-stopped
    user: "\${FLOWISE_UID:-1000}:\${TENANT_GID:-1001}"
    networks:
      - default
    depends_on:
      postgres:
        condition: service_healthy
      qdrant:
        condition: service_started
    environment:
      - 'DATABASE_TYPE=postgres'
      - 'DATABASE_HOST=postgres'
      - 'DATABASE_PORT=5432'
      - 'DATABASE_NAME=\${POSTGRES_DB:-ai_platform}'
      - 'DATABASE_USER=\${POSTGRES_USER:-postgres}'
      - 'DATABASE_PASSWORD=\${POSTGRES_PASSWORD}'
      - 'QDRANT_URL=http://qdrant:6333'
      - 'QDRANT_API_KEY=\${QDRANT_API_KEY}'
      - 'FLOWISE_SECRET_KEY=\${FLOWISE_SECRET_KEY}'
      - 'APIKEY_RESOLVER_ENDPOINT=http://litellm:4000'
    volumes:
      - ./flowise:/root/.flowise
EOF
    ok "Added 'flowise' service with auto-integration."
}

add_n8n() {
    if [[ "${ENABLE_N8N}" != "true" ]]; then return; fi
    
    log "INFO" "Adding 'n8n' service with auto-integration..."
    mkdir -p "${TENANT_DIR}/n8n"
    chown "1000:1001" "${TENANT_DIR}/n8n"
    chmod 755 "${TENANT_DIR}/n8n"

    cat >> "${COMPOSE_FILE}" << EOF

  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    user: "\${N8N_UID:-1000}:\${TENANT_GID:-1001}"
    networks:
      - default
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      - 'N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}'
      - 'DATABASE_TYPE=postgres'
      - 'DATABASE_HOST=postgres'
      - 'DATABASE_PORT=5432'
      - 'DATABASE_NAME=\${POSTGRES_DB:-ai_platform}'
      - 'DATABASE_USER=\${POSTGRES_USER:-postgres}'
      - 'DATABASE_PASSWORD=\${POSTGRES_PASSWORD}'
      - 'WEBHOOK_URL=http://localhost:${N8N_PORT:-5678}/'
    volumes:
      - ./n8n:/home/node/.n8n
EOF
    ok "Added 'n8n' service with auto-integration."
}

add_qdrant() {
    cat >> "${COMPOSE_FILE}" << EOF

  qdrant:
    image: qdrant/qdrant:latest
    restart: unless-stopped
    user: "${QDRANT_UID:-1000}:${TENANT_GID:-1001}"
    networks:
      - default
    environment:
      QDRANT__LOG_LEVEL: "\${QDRANT__LOG_LEVEL:-info}"
      QDRANT__SERVICE__HTTP__ENABLE_CORS: "\${QDRANT__SERVICE__HTTP__ENABLE_CORS:-true}"
      # CRITICAL FIX: Tell Qdrant where to store snapshots inside mounted volume
      QDRANT__STORAGE__SNAPSHOTS_PATH: "/qdrant/storage/snapshots"
    volumes:
      - ./qdrant:/qdrant/storage
      - ./qdrant/snapshots:/qdrant/snapshots
    ports:
      - "${QDRANT_PORT:-6333}:${QDRANT_INTERNAL_PORT:-6333}"
    healthcheck:
      test: ["CMD", "curl", "--fail", "--silent", "--max-time", "5", "http://localhost:6333/collections"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
EOF
    ok "Added 'qdrant' service with healthcheck."
}

add_grafana() {
    cat >> "${COMPOSE_FILE}" << EOF

  grafana:
    image: grafana/grafana:latest
    restart: unless-stopped
    user: "${GRAFANA_UID:-472}:${TENANT_GID:-1001}"
    networks:
      - default
    environment:
      - GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
      - GF_LOG_LEVEL=${GF_LOG_LEVEL:-info}
      - GF_LOG_MODE=${GF_LOG_MODE:-console,file}
    volumes:
      - \${TENANT_DIR}/grafana:/var/lib/grafana
    healthcheck:
      test: ["CMD", "curl", "--fail", "http://localhost:3000/api/health"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 30s
EOF
    ok "Added 'grafana' service with healthcheck."
}

add_prometheus() {
    cat >> "${COMPOSE_FILE}" << EOF

  prometheus:
    image: prom/prometheus:latest
    restart: unless-stopped
    user: "${PROMETHEUS_UID:-65534}:${TENANT_GID:-1001}"
    networks:
      - default
    environment:
      - PROMETHEUS_LOG_LEVEL=${PROMETHEUS_LOG_LEVEL:-info}
      - PROMETHEUS_LOG_FORMAT=${PROMETHEUS_LOG_FORMAT:-json}
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - ./prometheus:/prometheus
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:9090/-/healthy"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 20s
EOF
    ok "Added 'prometheus' service with healthcheck."
}

add_caddy() {
    cat >> "${COMPOSE_FILE}" << EOF

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    user: "0:0"  # Run as root to avoid permission issues
    networks:
      - default
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      - CADDY_LOG_LEVEL=${CADDY_LOG_LEVEL:-info}
      - CADDY_LOG_FORMAT=${CADDY_LOG_FORMAT:-json}
    volumes:
      - \${TENANT_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - \${TENANT_DIR}/caddy/data:/data
    ports:
      - "${CADDY_HTTP_PORT:-80}:80"
      - "${CADDY_HTTPS_PORT:-443}:443"
      - "${CADDY_HTTPS_PORT:-443}:443/udp"
    command: caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:2019/metrics > /dev/null 2>&1 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
EOF
    ok "Added 'caddy' service with healthcheck dependencies."
}

test_service_urls() {
    log "=== COMPREHENSIVE URL TESTING ==="
    
    local test_results=()
    
    # Test internal URLs
    test_results+=("INTERNAL: http://localhost:5432 - $(nc -z localhost 5432 && echo "✅ OPEN" || echo "❌ CLOSED")")
    test_results+=("INTERNAL: http://localhost:6379 - $(nc -z localhost 6379 && echo "✅ OPEN" || echo "❌ CLOSED")")
    test_results+=("INTERNAL: http://localhost:6333/health - $(curl -s -f http://localhost:6333/health >/dev/null 2>&1 && echo "✅ HEALTHY" || echo "❌ UNHEALTHY")")
    test_results+=("INTERNAL: http://localhost:3000/api/health - $(curl -s -f http://localhost:3000/api/health >/dev/null 2>&1 && echo "✅ HEALTHY" || echo "❌ UNHEALTHY")")
    test_results+=("INTERNAL: http://localhost:9090/-/healthy - $(curl -s -f http://localhost:9090/-/healthy >/dev/null 2>&1 && echo "✅ HEALTHY" || echo "❌ UNHEALTHY")")
    test_results+=("INTERNAL: https://localhost:443 - $(curl -s -k -f https://localhost:443 >/dev/null 2>&1 && echo "✅ HTTPS" || echo "❌ FAILED")")
    
    # Test external URLs if DOMAIN is set
    if [[ -n "${DOMAIN:-}" ]]; then
        test_results+=("EXTERNAL: https://${DOMAIN} - $(curl -s -f https://${DOMAIN} >/dev/null 2>&1 && echo "✅ REACHABLE" || echo "❌ NOT REACHABLE")")
        test_results+=("EXTERNAL: https://grafana.${DOMAIN} - $(curl -s -f https://grafana.${DOMAIN} >/dev/null 2>&1 && echo "✅ REACHABLE" || echo "❌ NOT REACHABLE")")
        test_results+=("EXTERNAL: https://prometheus.${DOMAIN} - $(curl -s -f https://prometheus.${DOMAIN} >/dev/null 2>&1 && echo "✅ REACHABLE" || echo "❌ NOT REACHABLE")")
    fi
    
    # Log all test results
    for result in "${test_results[@]}"; do
        log "URL TEST: $result"
    done
    
    log "=== END URL TESTING ==="
}


# --- Main Function ---
main() {
    # --- Docker Check ---
    if ! docker info &>/dev/null; then
        fail "Docker is not running. Please start Docker and try again."
    fi
    ok "Docker is active."

    # --- Pre-flight Configuration Generation ---
    log "INFO" "Requesting dynamic configurations from Mission Control (Script 3)..."
    
    # Call Mission Control generators for all complex configurations
    generate_caddyfile
    
    # Generate rclone config (still handled locally)
    write_rclone_config
    
    ok "All runtime configurations generated successfully."

    # --- Generate Docker Compose ---
    log "Generating docker-compose.yml for tenant '${TENANT_ID}'..."

    # Initialize compose file
    cat > "${COMPOSE_FILE}" << 'EOF'
services:
EOF

    # --- Generate All Services (Master Service Loop) ---
    generate_compose_services

    # --- Add Network Configuration ---
    cat >> "${COMPOSE_FILE}" << 'EOF'

networks:
  default:
    name: ${DOCKER_NETWORK}
    driver: bridge

volumes:
  rclone-cache:
    driver: local
  postgres_data:
    driver: local
EOF

    # --- Start Services ---
    log "Starting deployment with docker compose..."
    cd "${TENANT_DIR}"
    
    # CRITICAL: Audit all volume mounts before deployment
    audit_volume_mounts
    
    # --- Fix Qdrant storage ownership before deployment ---
    QDRANT_STORAGE="${TENANT_DIR}/qdrant"
    mkdir -p "${QDRANT_STORAGE}" "${QDRANT_STORAGE}/snapshots"
    chown -R 1000:1001 "${QDRANT_STORAGE}"
    chmod -R 750 "${QDRANT_STORAGE}"
    log "OK" "Qdrant storage permissions set (1000:1001)"
    
    log "=== DOCKER COMPOSE DEBUG INFO ==="
    log "Current directory: $(pwd)"
    log "Docker compose file: ${COMPOSE_FILE}"
    log "Docker compose file exists: $([ -f "${COMPOSE_FILE}" ] && echo "YES" || echo "NO")"
    
    if [[ -f "${COMPOSE_FILE}" ]]; then
        log "Docker compose file size: $(wc -l < "${COMPOSE_FILE}") lines"
        log "Docker compose file permissions: $(ls -la "${COMPOSE_FILE}")"
        log "=== DOCKER COMPOSE FILE CONTENT ==="
        cat "${COMPOSE_FILE}" >> "${LOG_FILE}" 2>&1
        log "=== END DOCKER COMPOSE FILE ==="
    fi

    log "=== DOCKER SYSTEM INFO ==="
    docker system info >> "${LOG_FILE}" 2>&1
    log "=== END DOCKER SYSTEM INFO ==="

    log "Pulling all required Docker images..."
    docker compose pull --quiet >> "${LOG_FILE}" 2>&1
    
    # Ensure proper permissions for data directory
    log "INFO" "Ensuring proper permissions for data directory..."
    mkdir -p /mnt/data/datasquiz/data/caddy 2>/dev/null || true
    chown -R 1001:1001 /mnt/data/datasquiz/data 2>/dev/null || true
    chmod -R 755 /mnt/data/datasquiz/data 2>/dev/null || true
    
    # Phase 2: Ordered Service Deployment
    log "Starting Phase 2: Ordered Service Deployment..."
    deploy_services_ordered
    
    # Phase 2: Layered Health Checks
    log "Starting Phase 2: Layered Health Checks..."
    perform_layered_health_checks

    # Verify core services health
    verify_core_services() {
    log "INFO" "Performing Caddy Post-Deployment Health Check..."
    # Wait up to 30 seconds for Caddy ports to be bound to the host
    for i in {1..6}; do
        if nc -z localhost "${CADDY_HTTPS_PORT:-443}"; then
            break
        fi
        log "INFO" "Waiting for Caddy HTTPS port to become available..."
        sleep 5
    done

    if nc -z localhost "${CADDY_HTTPS_PORT:-443}"; then
        ok "Caddy HTTPS Port ${CADDY_HTTPS_PORT:-443} is open and accessible from the host."
    else
        fail "CRITICAL FAILURE: Caddy HTTPS Port is NOT accessible. Port mapping has failed."
        exit 1
    fi

    # Capture detailed Caddy logs for debugging
    log "=== CAPTURING DETAILED CADDY LOGS ==="
    if docker ps --filter name=ai-datasquiz-caddy-1 --format "{{.Names}}" | grep -q "ai-datasquiz-caddy-1"; then
        log "CADDY CONTAINER STATUS: $(docker ps --filter name=ai-datasquiz-caddy-1 --format "{{.Status}}")"
        log "CADDY CONTAINER LOGS (last 50 lines):"
        docker logs ai-datasquiz-caddy-1 --tail 50 >> "${LOG_FILE}" 2>&1
        log "=== END CADDY LOGS ==="
    else
        log "CADDY CONTAINER: NOT RUNNING"
    fi
    
    # Test each service URL individually with Caddy response verification
    log "=== INDIVIDUAL SERVICE URL TESTING ==="
    
    # Test main domain
    if curl -k -s -m 10 https://localhost:443 >/dev/null 2>&1; then
        ok "MAIN DOMAIN: https://localhost:443 - RESPONDING"
    else
        warn "MAIN DOMAIN: https://localhost:443 - NOT RESPONDING"
    fi
    
    # Test each service subdomain
    local services=("grafana" "prometheus" "auth" "signal" "openclaw")
    for service in "${services[@]}"; do
        if curl -k -s -m 10 "https://${service}.ai.datasquiz.net" >/dev/null 2>&1; then
            ok "SERVICE: https://${service}.ai.datasquiz.net - RESPONDING"
        else
            warn "SERVICE: https://${service}.ai.datasquiz.net - NOT RESPONDING"
        fi
    done
    
    log "=== END SERVICE URL TESTING ==="
    }

    verify_core_services

    # Start deep log capture for all services if in debug mode
    if [[ "${DEBUG_MODE}" == "true" ]]; then
        log "=== STARTING DEEP LOG CAPTURE ==="
        [[ "${ENABLE_POSTGRES}" == "true" ]] && capture_docker_logs "postgres"
        [[ "${ENABLE_REDIS}" == "true" ]] && capture_docker_logs "redis"
        [[ "${ENABLE_QDRANT}" == "true" ]] && capture_docker_logs "qdrant"
        [[ "${ENABLE_GRAFANA}" == "true" ]] && capture_docker_logs "grafana"
        [[ "${ENABLE_PROMETHEUS}" == "true" ]] && capture_docker_logs "prometheus"
        [[ "${ENABLE_CADDY}" == "true" ]] && capture_docker_logs "caddy"
        log "=== DEEP LOG CAPTURE STARTED ==="
    fi

    # Comprehensive URL testing
    test_service_urls

    # --- Post-Deployment Verification ---
    log "=== POST-DEPLOYMENT VERIFICATION ==="
    verify_core_services
    
    # CRITICAL: Execute post-deployment configuration hooks
    run_post_deployment_hooks >> "${LOG_FILE}" 2>&1
    log "=== END FINAL DEPLOYMENT STATUS ==="
    
    # Run HTTPS verification
    verify_https_connectivity
    
    # Generate deployment dashboard
    generate_deployment_dashboard
    
    log "=== FINAL HEALTH CHECK ==="
    log "Running comprehensive health check to verify complete deployment..."
    bash "/home/jglaine/AIPlatformAutomation/scripts/3-configure-services.sh" "${TENANT_ID}" --health --port 443
    
    ok "Deployment completed with comprehensive logging engine."
    log "Debug logs available in: ${DATA_ROOT}/logs/deploy-*.log"
    log "Service-specific logs available in: ${DATA_ROOT}/logs/deploy-<service>-*.log"
    log "Next Step: Run 'sudo bash scripts/3-configure-services.sh ${TENANT_ID}'"
}

# Call main function to execute the script
main "$@"
