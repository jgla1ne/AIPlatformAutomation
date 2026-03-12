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

# --- DEBUG MODE FLAG - DEBUG ENABLED BY DEFAULT ---
DEBUG_MODE="${DEBUG_MODE:-true}"
if [[ "${DEBUG_MODE}" == "true" ]]; then
    set -x
fi

# --- Colors and Logging ---
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' BLUE='\033[0;34m' NC='\033[0m'
LOG_FILE=""  # Initialize LOG_FILE early

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
write_caddyfile() {
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

    # 2. Main Domain Route
    cat >> "$TMP_CADDY" <<EOF
${DOMAIN} {
    # Add the tls directive here
    tls internal {
        on_demand
    }
    respond "AI Platform v3.2.0 is active. Welcome." 200
}

EOF

    # 3. Dynamically add routes for ONLY enabled services
    if [[ "${ENABLE_GRAFANA}" == "true" ]]; then
        cat >> "$TMP_CADDY" <<EOF
grafana.${DOMAIN} {
    tls internal
    reverse_proxy grafana:${GRAFANA_INTERNAL_PORT}
}

EOF
        ok "Caddy route added for Grafana."
    fi
    
    if [[ "${ENABLE_PROMETHEUS}" == "true" ]]; then
        cat >> "$TMP_CADDY" <<EOF
prometheus.${DOMAIN} {
    tls internal
    reverse_proxy prometheus:${PROMETHEUS_INTERNAL_PORT}
}

EOF
        ok "Caddy route added for Prometheus."
    fi
    
    if [[ "${ENABLE_QDRANT}" == "true" ]]; then
        cat >> "$TMP_CADDY" <<EOF
qdrant.${DOMAIN} {
    tls internal
    reverse_proxy qdrant:${QDRANT_INTERNAL_PORT}
}

EOF
        ok "Caddy route added for Qdrant."
    fi
    
    if [[ "${ENABLE_OLLAMA}" == "true" ]]; then
        cat >> "$TMP_CADDY" <<EOF
ollama.${DOMAIN} {
    tls internal
    reverse_proxy ollama:${OLLAMA_INTERNAL_PORT}
}

EOF
        ok "Caddy route added for Ollama."
    fi
    
    if [[ "${ENABLE_OPENWEBUI}" == "true" ]]; then
        cat >> "$TMP_CADDY" <<EOF
openwebui.${DOMAIN} {
    tls internal
    reverse_proxy openwebui:${OPENWEBUI_INTERNAL_PORT}
}

EOF
        ok "Caddy route added for OpenWebUI."
    fi

    # 4. Atomically move the file and set ownership
    mv "$TMP_CADDY" "$CADDY_FILE"
    log "INFO" "Caddyfile generated successfully."
    # TODO: Fix Docker volume mount issue for caddy fmt
    # docker run --rm -v "${CADDY_FILE}:/etc/caddy/Caddyfile" caddy:2 caddy fmt --overwrite
    
    chown "${TENANT_UID}:${TENANT_GID}" "$CADDY_FILE"
    log "SUCCESS" "Dynamic Caddyfile generation complete."
}

write_prometheus_config() {
    log "INFO" "Writing Prometheus configuration..."
    
    cat > "${DATA_ROOT}/prometheus.yml" << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOF
    
    log "SUCCESS" "Prometheus configuration written to ${DATA_ROOT}/prometheus.yml"
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

    if [[ "$all_volumes_exist" == "true" ]]; then
        ok "Volume mount audit passed. All source directories exist."
    else
        exit 1 # Halt deployment
    fi
}

# --- Master Service Loop (Zero Gap Implementation) ---
generate_compose_services() {
    log "INFO" "Executing Master Service Loop - Deploying ALL enabled services..."
    
    # Core Infrastructure Services
    [[ "${ENABLE_POSTGRES}" == "true" ]] && add_postgres
    [[ "${ENABLE_REDIS}" == "true" ]] && add_redis
    [[ "${ENABLE_QDRANT}" == "true" ]] && add_qdrant
    
    # AI/LLM Stack Services
    [[ "${ENABLE_OLLAMA}" == "true" ]] && add_ollama
    [[ "${ENABLE_LITELLM}" == "true" ]] && add_litellm
    [[ "${ENABLE_OPENWEBUI}" == "true" ]] && add_openwebui
    [[ "${ENABLE_ANYTHINGLLM}" == "true" ]] && add_anythingllm
    [[ "${ENABLE_FLOWISE}" == "true" ]] && add_flowise
    [[ "${ENABLE_N8N}" == "true" ]] && add_n8n
    
    # Monitoring Services
    [[ "${ENABLE_GRAFANA}" == "true" ]] && add_grafana
    [[ "${ENABLE_PROMETHEUS}" == "true" ]] && add_prometheus
    
    # Security & Networking Services
    [[ "${ENABLE_AUTHENTIK}" == "true" ]] && add_authentik
    [[ "${ENABLE_TAILSCALE}" == "true" ]] && add_tailscale
    [[ "${ENABLE_RCLONE}" == "true" ]] && add_rclone
    [[ "${ENABLE_SIGNAL}" == "true" ]] && add_signal
    [[ "${ENABLE_OPENCLAW}" == "true" ]] && add_openclaw
    
    # Caddy is always required for reverse proxy
    add_caddy
    
    ok "Master Service Loop completed - All enabled services added to compose file."
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
      - ./postgres:/var/lib/postgresql/data
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
    user: "\${OLLAMA_UID:-1000}:\${TENANT_GID:-1001}"
    networks:
      - default
    environment:
      - 'OLLAMA_HOST=0.0.0.0'
      - 'OLLAMA_PORT=\${OLLAMA_INTERNAL_PORT:-11434}'
    volumes:
      - ./ollama:/root/.ollama  # CRITICAL: Mounts to a subdir INSIDE the tenant's data root
EOF

    # Add GPU deployment if enabled
    if [[ "${ENABLE_GPU}" == "true" ]]; then
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

add_litellm() {
    log "INFO" "Auto-integrating LiteLLM with Ollama and Qdrant..."
    cat >> "${COMPOSE_FILE}" << EOF

  litellm:
    image: ghcr.io/berriai/litellm:main
    restart: unless-stopped
    user: "\${LITELLM_UID:-1000}:\${TENANT_GID:-1001}"
    networks:
      - default
    environment:
      - 'LITELLM_CONFIG_YAML=/app/config.yaml'
      - 'QDRANT_API_KEY=\${QDRANT_API_KEY}'
      - 'LITELLM_MASTER_KEY=\${LITELLM_MASTER_KEY}'
      - 'LITELLM_PORT=\${LITELLM_INTERNAL_PORT:-4000}'
    volumes:
      - \${TENANT_DIR}/litellm-config.yaml:/app/config.yaml
EOF
    ok "Added 'litellm' service with full auto-integration."
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
    user: "\${RCLONE_UID:-1000}:\${TENANT_GID:-1001}"
    networks:
      - default
    environment:
      - 'RCLONE_CONFIG_GDRIVE_TYPE=drive'
      - 'RCLONE_CONFIG_GDRIVE_SCOPE=drive'
      - 'RCLONE_CONFIG_GDRIVE_USE_JSON_AUTH=true'
      - 'RCLONE_CONFIG_GDRIVE_SERVICE_ACCOUNT_FILE=/config/google_sa.json'
    volumes:
      - ./rclone:/config/rclone
      - ./gdrive:/mnt/gdrive
    command: ["rclone", "mount", "gdrive:", "/mnt/gdrive", "--vfs-cache-mode", "writes", "--allow-non-empty", "--log-level", "INFO"]
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
      - 'DATABASE_URL=postgresql://\${POSTGRES_USER:-postgres}:\${POSTGRES_PASSWORD}@postgres:5432/\${POSTGRES_DB:-ai_platform}'
      - 'QDRANT_URL=http://qdrant:6333'
      - 'QDRANT_API_KEY=\${QDRANT_API_KEY}'
      - 'OLLAMA_BASE_URL=http://ollama:11434'
      - 'OPENAI_API_KEY=\${OPENAI_API_KEY}'
      - 'ANTHROPIC_API_KEY=\${ANTHROPIC_API_KEY}'
    volumes:
      - ./litellm:/app/config
EOF
    ok "Added 'litellm' service with auto-integration."
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
    volumes:
      - ./openwebui:/app/backend/data
EOF
    ok "Added 'openwebui' service, configured for LiteLLM routing."
}

add_authentik() {
    if [[ "${ENABLE_AUTHENTIK}" != "true" ]]; then return; fi
    
    log "INFO" "Adding 'authentik' service..."
    mkdir -p "${TENANT_DIR}/authentik"
    chown "${TENANT_UID}:${TENANT_GID}" "${TENANT_DIR}/authentik"

    cat >> "${COMPOSE_FILE}" << EOF

  authentik:
    image: ghcr.io/goauthentik/server:latest
    restart: unless-stopped
    user: "\${AUTHENTIK_UID:-1000}:\${TENANT_GID:-1001}"
    networks:
      - default
    environment:
      - 'AUTHENTIK_SECRET_KEY=\${AUTHENTIK_SECRET_KEY}'
      - 'AUTHENTIK_POSTGRES_NAME=authentik'
      - 'AUTHENTIK_POSTGRES_USER=authentik'
      - 'AUTHENTIK_POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}'
      - 'AUTHENTIK_POSTGRES_HOST=postgres'
      - 'AUTHENTIK_POSTGRES_PORT=5432'
    volumes:
      - ./authentik:/media
      - ./authentik:/templates
    depends_on:
      postgres:
        condition: service_healthy
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
    user: "\${SIGNAL_UID:-1000}:\${TENANT_GID:-1001}"
    networks:
      - default
    ports:
      - "8080:8080"
    volumes:
      - ./signal-data:/home/.local/share/signal-cli
    environment:
      - 'SIGNAL_PHONE_NUMBER=\${SIGNAL_PHONE_NUMBER}'
      - 'SIGNAL_VERIFICATION_CODE=\${SIGNAL_VERIFICATION_CODE}'
EOF
    ok "Added 'signal' service with recommended configuration."
}

add_openclaw() {
    if [[ "${ENABLE_OPENCLAW}" != "true" ]]; then return; fi
    
    log "INFO" "Adding 'openclaw' service with proper configuration..."
    mkdir -p "${TENANT_DIR}/openclaw"
    chown "${TENANT_UID}:${TENANT_GID}" "${TENANT_DIR}/openclaw"

    cat >> "${COMPOSE_FILE}" << EOF

  openclaw:
    image: moltenbot/openclaw:latest
    restart: unless-stopped
    user: "\${OPENCLAW_UID:-1000}:\${TENANT_GID:-1001}"
    networks:
      - default
    ports:
      - "3000:3000"
    depends_on:
      - signal
    environment:
      - 'OPENAI_API_KEY=\${OPENAI_API_KEY}'
    volumes:
      - ./openclaw:/data
EOF
    ok "Added 'openclaw' service with proper configuration."
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
      - 'DATABASE_TYPE=\${DATABASE_TYPE:-postgres}'
      - 'DATABASE_HOST=postgres'
      - 'DATABASE_PORT=5432'
      - 'DATABASE_NAME=\${POSTGRES_DB:-ai_platform}'
      - 'DATABASE_USER=\${POSTGRES_USER:-postgres}'
      - 'DATABASE_PASSWORD=\${POSTGRES_PASSWORD}'
      - 'QDRANT_ENDPOINT=http://qdrant:6333'
      - 'QDRANT_API_KEY=\${QDRANT_API_KEY}'
      - 'LLM_PROVIDER=\${LLM_PROVIDER:-litellm}'
      - 'LLM_BASE_URL=http://litellm:4000'
      - 'ANYTHINGLLM_JWT_SECRET=\${ANYTHINGLLM_JWT_SECRET}'
    volumes:
      - ./anythingllm:/app/server/storage
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
    chown "${TENANT_UID}:${TENANT_GID}" "${TENANT_DIR}/n8n"

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
    volumes:
      - \${TENANT_DIR}/qdrant:/qdrant/storage
EOF
    ok "Added 'qdrant' service."
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
EOF
    ok "Added 'grafana' service."
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
      - \${TENANT_DIR}/prometheus.yml:/etc/prometheus/prometheus.yml
      - \${TENANT_DIR}/prometheus-data:/prometheus
EOF
    ok "Added 'prometheus' service."
}

add_caddy() {
    cat >> "${COMPOSE_FILE}" << EOF

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    user: "${CADDY_UID:-1001}:${TENANT_GID:-1001}"
    networks:
      - default
    environment:
      - CADDY_LOG_LEVEL=${CADDY_LOG_LEVEL:-info}
      - CADDY_LOG_FORMAT=${CADDY_LOG_FORMAT:-json}
    volumes:
      - \${TENANT_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile
      - \${TENANT_DIR}/caddy/data:/data
    ports:
      - "${CADDY_HTTP_PORT:-80}:80"
      - "${CADDY_HTTPS_PORT:-443}:443"
      - "${CADDY_HTTPS_PORT:-443}:443/udp"
EOF
    ok "Added 'caddy' service."
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
    test_results+=("INTERNAL: http://localhost:80 - $(curl -s -f http://localhost:80 >/dev/null 2>&1 && echo "✅ HEALTHY" || echo "❌ UNHEALTHY")")
    
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
    log "INFO" "Executing Pre-flight Configuration Generation..."
    write_caddyfile
    write_prometheus_config
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
EOF

    # --- Start Services ---
    log "Starting deployment with docker compose..."
    cd "${TENANT_DIR}"
    
    # CRITICAL: Audit all volume mounts before deployment
    audit_volume_mounts
    
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
    
    log "Starting all services in detached mode..."
    log "Executing docker compose up -d... Output logged to ${LOG_FILE}"
    if ! docker compose up -d >> "${LOG_FILE}" 2>&1; then
        log "=== DEPLOYMENT FAILURE DEBUG ==="
        log "Docker compose logs:"
        docker compose logs --tail=50 >> "${LOG_FILE}" 2>&1
        log "=== END DEPLOYMENT FAILURE DEBUG ==="
        fail "Docker Compose failed to start. Please check the logs above."
    fi

    # Wait for services to initialize
    log "Waiting for services to initialize..."
    sleep 10

    # Verify core services health
    verify_core_services

    log "INFO" "Performing Caddy Post-Deployment Health Check..."
    # Wait up to 30 seconds for Caddy ports to be bound to the host
    for i in {1..6}; do
        if nc -z localhost "${CADDY_HTTP_PORT:-80}"; then
            break
        fi
        log "INFO" "Waiting for Caddy HTTP port to become available..."
        sleep 5
    done

    if nc -z localhost "${CADDY_HTTP_PORT:-80}"; then
        ok "Caddy HTTP Port ${CADDY_HTTP_PORT:-80} is open and accessible from the host."
    else
        fail "CRITICAL FAILURE: Caddy HTTP Port is NOT accessible. Port mapping has failed."
        exit 1
    fi

    # Capture initial service logs
    capture_initial_logs

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

    # --- Final Health Check ---
    log "=== FINAL HEALTH CHECK ==="
    log "Running comprehensive health check to verify complete deployment..."
    bash "/home/jglaine/AIPlatformAutomation/scripts/3-configure-services.sh" "${TENANT_ID}" --health

    ok "Deployment completed with comprehensive logging engine."
    log "Debug logs available in: ${LOG_DIR}/deploy-*.log"
    log "Service-specific logs available in: ${LOG_DIR}/deploy-<service>-*.log"
    log "Next Step: Run 'sudo bash scripts/3-configure-services.sh ${TENANT_ID}'"
}

# Call main function to execute the script
main
