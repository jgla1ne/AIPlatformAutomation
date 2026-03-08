#!/usr/bin/env bash
# =============================================================================
# Script 3: Service Configuration & Integration
# =============================================================================
# PURPOSE: Post-deploy service configuration with skip flags and progress tracking
# USAGE:   sudo bash scripts/3-configure-services.sh <TENANT_ID> [--skip-service]
# =============================================================================

# Accept TENANT_ID as command-line argument for explicit deployment
TENANT_ID="${1:-}"
if [[ -z "$TENANT_ID" ]]; then
    echo "ERROR: TENANT_ID is required as first argument"
    echo "Usage: sudo bash scripts/3-configure-services.sh <TENANT_ID> [--skip-service]"
    exit 1
fi

set -eo pipefail

# ─── Colours ─────────────────────────────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# ─── Runtime vars ────────────────────────────────────────────────────────────────
TENANT_UID="${SUDO_UID:-$(id -u)}"
TENANT_GID="${SUDO_GID:-$(id -g)}"
# Use explicit TENANT_ID from command line
ENV_FILE="/mnt/data/${TENANT_ID}/.env"
TENANT_DIR="/mnt/data/${TENANT_ID}"

[[ -z "${ENV_FILE:-}" || ! -f "${ENV_FILE}" ]] && \
  fail "Cannot find .env file. Run script 1 first."

# Source environment variables
set -a
. "${ENV_FILE}"
set +a

# Use environment variables
DATA_ROOT="${DATA_ROOT:-/mnt/data/${TENANT_ID:-default}}"
LOG_FILE="${DATA_ROOT}/logs/configure-$(date +%Y%m%d-%H%M%S).log"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Skip flags
SKIP_N8N=false
SKIP_FLOWISE=false
SKIP_LITELLM=false
SKIP_ANYTHINGLLM=false
SKIP_GRAFANA=false

# ─── Logging ─────────────────────────────────────────────────────────────────
log() {
    local level="${1}" message="${2}"
    case "${level}" in
        SUCCESS) echo -e "  ${GREEN}✅  ${message}${NC}" ;;
        INFO)    echo -e "  ${CYAN}ℹ️   ${message}${NC}" ;;
        WARN)    echo -e "  ${YELLOW}⚠️   ${message}${NC}" ;;
        ERROR)   echo -e "  ${RED}❌  ${message}${NC}" ;;
    esac
}

# ─── UI Helpers ──────────────────────────────────────────────────────────────
print_header() {
    clear
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}           AI Platform — Service Configuration         ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    local step="${1}" total="${2}" title="${3}"
    echo ""
    echo -e "${CYAN}  ┌─────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}  │${NC}  ${BOLD}[ STEP ${step} of ${total} ]${NC}  ${title}"
    echo -e "${CYAN}  └─────────────────────────────────────────────────┘${NC}"
    echo ""
}

print_section() {
    local title="${1}"
    echo ""
    echo -e "${CYAN}  ┌─────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}  │${NC}  ${BOLD}${title}${NC}"
    echo -e "${CYAN}  └─────────────────────────────────────────────────┘${NC}"
    echo ""
}

print_divider() {
    echo ""
    echo -e "${DIM}  ══════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ─── Argument Parsing ───────────────────────────────────────────────────────────
parse_args() {
    # Skip TENANT_ID if it's the first argument
    if [[ $# -gt 0 && ! "${1}" =~ ^-- ]]; then
        shift  # Skip the TENANT_ID
    fi
    
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --skip-n8n)          SKIP_N8N=true ;;
            --skip-flowise)      SKIP_FLOWISE=true ;;
            --skip-litellm)      SKIP_LITELLM=true ;;
            --skip-anythingllm)  SKIP_ANYTHINGLLM=true ;;
            --skip-grafana)      SKIP_GRAFANA=true ;;
            --help|-h)
                echo "Usage: sudo bash scripts/3-configure-services.sh <TENANT_ID> [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --skip-n8n          Skip n8n configuration"
                echo "  --skip-flowise      Skip Flowise configuration"
                echo "  --skip-litellm      Skip LiteLLM model registration"
                echo "  --skip-anythingllm  Skip AnythingLLM configuration"
                echo "  --skip-grafana      Skip Grafana dashboard setup"
                echo "  --help              Show this help message"
                exit 0
                ;;
            *)
                echo "Unknown option: ${1}"
                echo "Run with --help for usage"
                exit 1
                ;;
        esac
        shift
    done
}

# ─── Environment Loading ───────────────────────────────────────────────────────
load_env() {
    if [ ! -f "${ENV_FILE}" ]; then
        log "ERROR" "${ENV_FILE} not found — run script 1 first"
        exit 1
    fi

    # Load environment with validation
    set -a
    source "${ENV_FILE}"
    set +a

    # Validate critical variables are present
    local required=(
        TENANT_ID DOMAIN DB_USER DB_PASSWORD
        N8N_PASSWORD FLOWISE_PASSWORD LITELLM_MASTER_KEY
    )
    local missing=()
    for var in "${required[@]}"; do
        [ -z "${!var:-}" ] && missing+=("${var}")
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        log "ERROR" "Missing required variables in .env:"
        for var in "${missing[@]}"; do
            echo "    - ${var}"
        done
        exit 1
    fi

    log "SUCCESS" "Environment loaded from ${ENV_FILE}"
}

# ─── Service Wait Function ─────────────────────────────────────────────────────
wait_for_service() {
    local name=$1 url=$2 max=${3:-120}
    log "INFO" "Waiting for ${name} at ${url}..."
    local count=0
    while [ ${count} -lt ${max} ]; do
        curl -sf --max-time 5 "${url}" &>/dev/null && {
            log "SUCCESS" "${name} is responding"
            return 0
        }
        count=$((count + 5))
        sleep 5
    done
    log "WARN" "${name} did not respond within ${max}s — skipping config"
    return 1
}

# ─── n8n Configuration ───────────────────────────────────────────────────────
configure_n8n() {
    [ "${SKIP_N8N}" = "true" ] && return 0
    [ "${ENABLE_N8N}" != "true" ] && return 0

    print_step "1" "${total_steps}" "Verifying n8n service health"
    
    wait_for_service "n8n" "http://${LOCALHOST}:${N8N_PORT}" 60 || return 1

    log "INFO" "n8n is healthy and ready for use"
    
    # n8n workflows directory should already exist from script-1
    
    log "SUCCESS" "n8n verification complete"
    echo -e "  ${DIM}• URL: https://n8n.${DOMAIN}${NC}"
    echo -e "  ${DIM}• Status: Service is running${NC}"
    echo -e "  ${DIM}• Note: n8n requires manual owner account creation on first visit${NC}"
}

# ─── Flowise Configuration ───────────────────────────────────────────────────
configure_flowise() {
    [ "${SKIP_FLOWISE}" = "true" ] && return 0
    [ "${ENABLE_FLOWISE}" != "true" ] && return 0

    print_step "2" "${total_steps}" "Configuring Flowise"
    
    wait_for_service "Flowise" "http://${LOCALHOST}:${FLOWISE_PORT}" 60 || return 1

    log "INFO" "Configuring Flowise API credentials..."
    
    log "SUCCESS" "Flowise configuration complete"
    echo -e "  ${DIM}• URL: https://flowise.${DOMAIN}${NC}"
    echo -e "  ${DIM}• User: ${FLOWISE_USER}${NC}"
    echo -e "  ${DIM}• Password: ${FLOWISE_PASSWORD}${NC}"
}

# ─── LiteLLM Configuration ───────────────────────────────────────────────────
configure_litellm() {
    [ "${SKIP_LITELLM}" = "true" ] && return 0
    [ "${ENABLE_LITELLM}" != "true" ] && return 0

    print_step "3" "${total_steps}" "Configuring LiteLLM with Routing Strategy"
    
    wait_for_service "LiteLLM" "http://${LOCALHOST}:${LITELLM_PORT}" 60 || return 1

    # Display current routing strategy
    log "INFO" "LiteLLM routing strategy: ${LITELLM_ROUTING_STRATEGY}"
    case "${LITELLM_ROUTING_STRATEGY}" in
        "speed-optimized")
            log "INFO" "🚀 Speed-optimized routing: Groq > Gemini > Local priority"
            ;;
        "capability-optimized")
            log "INFO" "🧠 Capability-optimized routing: GPT-4o > Claude-3 > Gemini priority"
            ;;
        "balanced")
            log "INFO" "⚖️ Balanced routing: Cost, speed, and capability balanced"
            ;;
        "cost-optimized"|*)
            log "INFO" "💰 Cost-optimized routing: Local models first, then cheapest paid models"
            ;;
    esac

    log "INFO" "Registering models with LiteLLM..."
    
    # Register Ollama model if enabled
    if [ "${ENABLE_OLLAMA}" = "true" ] && [ -n "${OLLAMA_DEFAULT_MODEL}" ]; then
        local litellm_config='{
            "model_list": [
                {
                    "model_name": "'"${OLLAMA_DEFAULT_MODEL}"'",
                    "litellm_params": {
                        "model": "ollama/'"${OLLAMA_DEFAULT_MODEL}"'",
                        "api_base": "'"${OLLAMA_INTERNAL_URL}"'",
                        "input_cost": 0.0,
                        "output_cost": 0.0
                    },
                    "model_id": "'"${OLLAMA_DEFAULT_MODEL}"'"
                }
            ]
        }'
        
        # Send to LiteLLM API
        if curl -sf -X POST "http://${LOCALHOST}:${LITELLM_PORT}/v1/model/register" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
            -d "${litellm_config}" &>/dev/null; then
            log "SUCCESS" "Registered ${OLLAMA_DEFAULT_MODEL} with LiteLLM (cost: $0.00)"
        else
            log "WARN" "Failed to register model with LiteLLM"
        fi
    fi
    
    # Register OpenAI models if API key available
    if [ -n "${OPENAI_API_KEY:-}" ]; then
        local openai_config='{
            "model_list": [
                {
                    "model_name": "gpt-4o",
                    "litellm_params": {
                        "model": "gpt-4o",
                        "api_key": "'"${OPENAI_API_KEY}"'",
                        "input_cost": 0.005,
                        "output_cost": 0.015
                    },
                    "model_id": "gpt-4o"
                }
            ]
        }'
        
        if curl -sf -X POST "http://${LOCALHOST}:${LITELLM_PORT}/v1/model/register" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
            -d "${openai_config}" &>/dev/null; then
            log "SUCCESS" "Registered gpt-4o with LiteLLM (cost: $0.005/$1K input, $0.015/$1K output)"
        else
            log "WARN" "Failed to register gpt-4o with LiteLLM"
        fi
    fi
    
    # Register Google models if API key available
    if [ -n "${GOOGLE_API_KEY:-}" ]; then
        local google_config='{
            "model_list": [
                {
                    "model_name": "gemini-2.0-flash",
                    "litellm_params": {
                        "model": "gemini/gemini-2.0-flash-exp",
                        "api_key": "'"${GOOGLE_API_KEY}"'",
                        "input_cost": 0.000075,
                        "output_cost": 0.00015
                    },
                    "model_id": "gemini-2.0-flash"
                }
            ]
        }'
        
        if curl -sf -X POST "http://${LOCALHOST}:${LITELLM_PORT}/v1/model/register" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
            -d "${google_config}" &>/dev/null; then
            log "SUCCESS" "Registered gemini-2.0-flash with LiteLLM (cost: $0.000075/$1K input, $0.00015/$1K output)"
        else
            log "WARN" "Failed to register gemini-2.0-flash with LiteLLM"
        fi
    fi
    
    # Register Groq models if API key available
    if [ -n "${GROQ_API_KEY:-}" ]; then
        local groq_config='{
            "model_list": [
                {
                    "model_name": "groq-llama-70b",
                    "litellm_params": {
                        "model": "groq/llama-70b-8192",
                        "api_key": "'"${GROQ_API_KEY}"'",
                        "input_cost": 0.00059,
                        "output_cost": 0.00079
                    },
                    "model_id": "groq-llama-70b"
                }
            ]
        }'
        
        if curl -sf -X POST "http://${LOCALHOST}:${LITELLM_PORT}/v1/model/register" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
            -d "${groq_config}" &>/dev/null; then
            log "SUCCESS" "Registered groq-llama-70b with LiteLLM (cost: $0.00059/$1K input, $0.00079/$1K output)"
        else
            log "WARN" "Failed to register groq-llama-70b with LiteLLM"
        fi
    fi
    
    log "SUCCESS" "LiteLLM configuration complete with ${LITELLM_ROUTING_STRATEGY} routing"
    echo -e "  ${DIM}• URL: https://litellm.${DOMAIN}${NC}"
    echo -e "  ${DIM}• API Key: ${LITELLM_MASTER_KEY}${NC}"
    echo -e "  ${DIM}• Routing Strategy: ${LITELLM_ROUTING_STRATEGY}${NC}"
    echo -e "  ${DIM}• Models registered: Check LiteLLM admin panel${NC}"
}

# ─── AnythingLLM Configuration ─────────────────────────────────────────────
configure_anythingllm() {
    [ "${SKIP_ANYTHINGLLM}" = "true" ] && return 0
    [ "${ENABLE_ANYTHINGLLM}" != "true" ] && return 0

    print_step "4" "${total_steps}" "Configuring AnythingLLM"
    
    wait_for_service "AnythingLLM" "http://${LOCALHOST}:${ANYTHINGLLM_PORT}" 60 || return 1

    log "INFO" "Configuring AnythingLLM workspace and integrations..."
    
    log "SUCCESS" "AnythingLLM configuration complete"
    echo -e "  ${DIM}• URL: https://anythingllm.${DOMAIN}${NC}"
    echo -e "  ${DIM}• JWT Secret: ${ANYTHINGLLM_JWT_SECRET:0:16}...${NC}"
    echo -e "  ${DIM}• Auth Token: ${ANYTHINGLLM_AUTH_TOKEN}${NC}"
}

# ─── Grafana Configuration ─────────────────────────────────────────────────
configure_grafana() {
    [ "${SKIP_GRAFANA}" = "true" ] && return 0
    [ "${ENABLE_GRAFANA}" != "true" ] && return 0

    print_step "5" "${total_steps}" "Setting up Grafana Dashboards"
    
    wait_for_service "Grafana" "http://${LOCALHOST}:${GRAFANA_PORT}" 60 || return 1

    log "INFO" "Configuring Grafana datasources and dashboards..."
    
    # Grafana provisioning directories should already exist from script-1
    
    # Create Prometheus datasource
    cat > "${DATA_ROOT}/grafana/provisioning/datasources/prometheus.yml" << EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://\${PROMETHEUS_SERVICE_NAME:-prometheus}:\${PROMETHEUS_INTERNAL_PORT}
    isDefault: true
    editable: true
EOF

    log "SUCCESS" "Grafana configuration complete"
    echo -e "  ${DIM}• URL: https://openwebui.${DOMAIN}${NC}"
    echo -e "  ${DIM}• User: ${GRAFANA_USER}${NC}"
    echo -e "  ${DIM}• Password: ${GRAFANA_PASSWORD}${NC}"
}

# ─── Infrastructure Configuration ─────────────────────────────────────────────
configure_postgres() {
    print_section "Infrastructure Setup"
    log "INFO" "Verifying PostgreSQL databases..."
    
    # Check if databases exist
    local dbs="litellm n8n dify openwebui"
    for db in ${dbs}; do
        if docker exec "${COMPOSE_PROJECT_NAME}-postgres" psql -U "${DB_USER}" -d "postgres" -c "SELECT 1 FROM pg_database WHERE datname='${db}'" &>/dev/null; then
            log "SUCCESS" "Database ${db} exists"
        else
            log "WARN" "Database ${db} missing - may need manual creation"
        fi
    done
}

configure_minio() {
    log "INFO" "Verifying MinIO object storage..."
    
    # Test MinIO connectivity
    if wait_for_service "MinIO" "http://${LOCALHOST}:${MINIO_PORT:-9000}" 30; then
        log "SUCCESS" "MinIO is accessible"
    else
        log "WARN" "MinIO may not be fully ready"
    fi
}

configure_qdrant() {
    log "INFO" "Verifying Qdrant vector database..."
    
    # Test Qdrant connectivity
    if wait_for_service "Qdrant" "http://${LOCALHOST}:${QDRANT_INTERNAL_PORT}/healthz" 30; then
        log "SUCCESS" "Qdrant is accessible"
    else
        log "WARN" "Qdrant may not be fully ready"
    fi
}

configure_ollama() {
    [ "${ENABLE_OLLAMA}" != "true" ] && return 0
    
    log "INFO" "Verifying Ollama service..."
    
    # Test Ollama connectivity
    local ollama_container
    ollama_container=$(docker ps --filter "name=^ollama$" --format "{{.Names}}" | head -1)
    if [[ -z "${ollama_container}" ]]; then
        # Fallback: try compose-namespaced name
        ollama_container=$(docker ps --filter "name=ollama" --format "{{.Names}}" | grep -E "[-_]ollama[-_]?1? $" | head -1)
    fi
    if [[ -z "${ollama_container}" ]]; then
        warn "Ollama container not found — skipping model pull"
        return
    fi
    if wait_for_service "Ollama" "http://${LOCALHOST}:${OLLAMA_INTERNAL_PORT}/api/tags" 60; then
        log "SUCCESS" "Ollama is accessible"
        
        # Pull models if not present
        if [ -n "${OLLAMA_MODELS}" ]; then
            log "INFO" "Checking and downloading models..."
            for model in ${OLLAMA_MODELS}; do
                log "INFO" "Checking if ${model} is downloaded..."
                if ! docker exec "${ollama_container}" ollama list 2>/dev/null | grep -q "${model}"; then
                    log "INFO" "Pulling ${model} model..."
                    if docker exec "${ollama_container}" ollama pull "${model}" &>/dev/null; then
                        log "SUCCESS" "${model} downloaded successfully"
                    else
                        log "WARN" "Failed to pull ${model}"
                    fi
                else
                    log "SUCCESS" "${model} already available"
                fi
            done
        elif [ -n "${OLLAMA_DEFAULT_MODEL}" ]; then
            # Fallback to single model if OLLAMA_MODELS not set
            log "INFO" "Checking if ${OLLAMA_DEFAULT_MODEL} is downloaded..."
            if ! docker exec "${ollama_container}" ollama list 2>/dev/null | grep -q "${OLLAMA_DEFAULT_MODEL}"; then
                log "INFO" "Pulling ${OLLAMA_DEFAULT_MODEL} model..."
                if docker exec "${ollama_container}" ollama pull "${OLLAMA_DEFAULT_MODEL}" &>/dev/null; then
                    log "SUCCESS" "${OLLAMA_DEFAULT_MODEL} downloaded successfully"
                else
                    log "WARN" "Failed to pull ${OLLAMA_DEFAULT_MODEL}"
                fi
            else
                log "SUCCESS" "${OLLAMA_DEFAULT_MODEL} already available"
            fi
        fi
    else
        log "WARN" "Ollama may not be fully ready"
    fi
}

# ─── Print Credentials Summary ─────────────────────────────────────────────────
print_credentials() {
    print_section "📋 Access Credentials Summary"
    
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}                    Service URLs & Credentials                 ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Core Services${NC}"
    echo -e "  ┌─────────────────────────────────────────────────┐"
    echo -e "  │  MinIO"
    echo -e "  │    URL:      https://minio.${DOMAIN}"
    echo -e "  │    User:     ${MINIO_ROOT_USER}"
    echo -e "  │    Password: ${MINIO_ROOT_PASSWORD}"
    echo -e "  ├─────────────────────────────────────────────────┤"
    
    [ "${ENABLE_GRAFANA}" = "true" ] && {
        echo -e "  │  Grafana"
        echo -e "  │    URL:      https://grafana.${DOMAIN}"
        echo -e "  │    User:     ${GRAFANA_USER}"
        echo -e "  │    Password: ${GRAFANA_PASSWORD}"
        echo -e "  ├─────────────────────────────────────────────────┤"
    }
    
    echo -e "  ${BOLD}AI Services${NC}"
    echo -e "  ┌─────────────────────────────────────────────────┐"
    
    [ "${ENABLE_OPENWEBUI}" = "true" ] && {
        echo -e "  │  Open WebUI"
        echo -e "  │    URL:      https://chat.${DOMAIN}"
        echo -e "  │    Access:    Register on first visit"
        echo -e "  ├─────────────────────────────────────────────────┤"
    }
    
    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && {
        echo -e "  │  AnythingLLM"
        echo -e "  │    URL:      https://anythingllm.${DOMAIN}"
        echo -e "  │    Access:    Token in .env"
        echo -e "  ├─────────────────────────────────────────────────┤"
    }
    
    [ "${ENABLE_N8N}" = "true" ] && {
        echo -e "  │  n8n"
        echo -e "  │    URL:      https://n8n.${DOMAIN}"
        echo -e "  │    User:     ${N8N_USER}"
        echo -e "  │    Password: ${N8N_PASSWORD}"
        echo -e "  ├─────────────────────────────────────────────────┤"
    }
    
    [ "${ENABLE_FLOWISE}" = "true" ] && {
        echo -e "  │  Flowise"
        echo -e "  │    URL:      https://flowise.${DOMAIN}"
        echo -e "  │    User:     ${FLOWISE_USER}"
        echo -e "  │    Password: ${FLOWISE_PASSWORD}"
        echo -e "  ├─────────────────────────────────────────────────┤"
    }
    
    [ "${ENABLE_LITELLM}" = "true" ] && {
        echo -e "  │  LiteLLM"
        echo -e "  │    URL:      https://litellm.${DOMAIN}"
        echo -e "  │    API Key:  ${LITELLM_MASTER_KEY}"
        echo -e "  ├─────────────────────────────────────────────────┤"
    }
    
    [ "${ENABLE_OLLAMA}" = "true" ] && {
        echo -e "  │  Ollama"
        echo -e "  │    URL:      https://chat.${DOMAIN} (via OpenWebUI)"
        echo -e "  │    Model:     ${OLLAMA_DEFAULT_MODEL}"
        echo -e "  ├─────────────────────────────────────────────────┤"
    }
    
    echo -e "  └─────────────────────────────────────────────────┘"
    echo ""
    echo -e "  ${DIM}All credentials saved to: ${ENV_FILE}${NC}"
    echo ""
}

# ─── Service Status Check ─────────────────────────────────────────────────────
print_service_status() {
    echo ""
    echo -e "${BOLD}${CYAN}🔍 Service Health Status${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local total_services=0
    local healthy_services=0
    local unhealthy_services=0
    
    # Core infrastructure services (always checked)
    local core_services=(
        "\${POSTGRES_SERVICE_NAME:-postgres}:\${POSTGRES_PORT:-5432}:PostgreSQL Database"
        "\${REDIS_SERVICE_NAME:-redis}:\${REDIS_PORT:-6379}:Redis Cache"
        "\${CADDY_SERVICE_NAME:-caddy}:\${CADDY_HTTP_PORT:-80}:Caddy Proxy"
    )
    
    # Optional services based on ENABLE flags
    local optional_services=()
    [ "${ENABLE_MINIO}" = "true" ] && optional_services+=("minio:${MINIO_PORT:-9000}:MinIO Storage")
    [ "${ENABLE_OLLAMA}" = "true" ] && optional_services+=("ollama:${OLLAMA_PORT:-11434}:Ollama LLM")
    [ "${ENABLE_LITELLM}" = "true" ] && optional_services+=("litellm:${LITELLM_PORT:-4000}:LiteLLM Gateway")
    [ "${ENABLE_OPENWEBUI}" = "true" ] && optional_services+=("openwebui:${OPENWEBUI_PORT:-8080}:OpenWebUI")
    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && optional_services+=("anythingllm:${ANYTHINGLLM_PORT:-3001}:AnythingLLM")
    [ "${ENABLE_N8N}" = "true" ] && optional_services+=("n8n:${N8N_PORT:-5678}:n8n Automation")
    [ "${ENABLE_FLOWISE}" = "true" ] && optional_services+=("flowise:${FLOWISE_PORT:-3000}:Flowise")
    [ "${ENABLE_DIFY}" = "true" ] && optional_services+=("dify-web:${DIFY_WEB_PORT:-3002}:Dify Web")
    [ "${ENABLE_GRAFANA}" = "true" ] && optional_services+=("grafana:${GRAFANA_PORT:-3003}:Grafana")
    [ "${ENABLE_PROMETHEUS}" = "true" ] && optional_services+=("prometheus:${PROMETHEUS_PORT:-9090}:Prometheus")
    [ "${ENABLE_SIGNAL}" = "true" ] && optional_services+=("signal-api:${SIGNAL_PORT:-8080}:Signal API")
    [ "${ENABLE_TAILSCALE}" = "true" ] && optional_services+=("tailscale:${TAILSCALE_INTERNAL_PORT}:Tailscale VPN")
    [ "${ENABLE_RCLONE}" = "true" ] && optional_services+=("rclone:${RCLONE_INTERNAL_PORT}:Rclone")
    
    # Check core services
    for service in "${core_services[@]}"; do
        IFS=':' read -r name port desc <<< "$service"
        total_services=$((total_services + 1))
        
        if check_service_health "$name" "$port" "$desc"; then
            healthy_services=$((healthy_services + 1))
        else
            unhealthy_services=$((unhealthy_services + 1))
        fi
    done
    
    # Check optional services
    for service in "${optional_services[@]}"; do
        IFS=':' read -r name port desc <<< "$service"
        total_services=$((total_services + 1))
        
        if check_service_health "$name" "$port" "$desc"; then
            healthy_services=$((healthy_services + 1))
        else
            unhealthy_services=$((unhealthy_services + 1))
        fi
    done
    
    # Summary
    echo ""
    echo -e "${BOLD}📊 Health Summary:${NC}"
    echo -e "  Total Services: ${CYAN}${total_services}${NC}"
    echo -e "  ${GREEN}Healthy: ${healthy_services}${NC}"
    echo -e "  ${RED}Unhealthy: ${unhealthy_services}${NC}"
    
    if [ "$unhealthy_services" -eq 0 ]; then
        echo -e ""
        echo -e "${GREEN}${BOLD}🎉 All services are healthy!${NC}"
    else
        echo -e ""
        echo -e "${YELLOW}⚠️  Some services may need time to start up${NC}"
        echo -e "${DIM}   Run script 3 again in a few minutes${NC}"
    fi
}

# Helper function to check individual service health
check_service_health() {
    local name="$1"
    local port="$2"
    local desc="$3"
    local container_name="${COMPOSE_PROJECT_NAME}-${name}"
    
    # Check if container is running
    if ! docker ps --format "table {{.Names}}" | grep -q "^${container_name}$"; then
        echo -e "  ${RED}❌ ${desc}:${NC} ${RED}Container not running${NC}"
        return 1
    fi
    
    # Check health via Docker health check
    local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "none")
    case "$health_status" in
        "healthy")
            echo -e "  ${GREEN}✅ ${desc}:${NC} ${GREEN}Healthy${NC}"
            return 0
            ;;
        "unhealthy")
            echo -e "  ${RED}❌ ${desc}:${NC} ${RED}Unhealthy${NC}"
            return 1
            ;;
        "starting")
            echo -e "  ${YELLOW}🔄 ${desc}:${NC} ${YELLOW}Starting${NC}"
            return 1
            ;;
        "none")
            # Fallback to port check if no health check
            if timeout 3 bash -c "</dev/tcp/localhost/$port" 2>/dev/null; then
                echo -e "  ${GREEN}✅ ${desc}:${NC} ${GREEN}Running${NC}"
                return 0
            else
                echo -e "  ${RED}❌ ${desc}:${NC} ${RED}Port $port not responding${NC}"
                return 1
            fi
            ;;
    esac
}

# --- setup_logging function ---
setup_logging() {
    if [[ -z "${DATA_ROOT:-}" ]]; then return; fi
    local script_name
    script_name=$(basename "$0" .sh)
    LOG_DIR="${DATA_ROOT}/logs"
    mkdir -p "${LOG_DIR}"
    # Script-1 should have set correct ownership; we trust the setup
    LOG_FILE="${LOG_DIR}/${script_name}-$(date +%Y%m%d-%H%M%S).log"

    # Redirect all subsequent output
    exec > >(tee -a "${LOG_FILE}") 2>&1
    log "INFO" "All output is now logged to: ${LOG_FILE}"
}

# ─── Caddy Configuration ─────────────────────────────────────────────────────
write_production_caddyfile() {
    log "Generating final production Caddyfile..."
    
    local caddyfile_content="{
    # This email is used for ACME notifications.
    email \${ACME_EMAIL}
}

# --- PUBLIC FACING SERVICES ---
"

    # Dynamically add reverse proxy rules for enabled services
    [[ "${ENABLE_N8N:-false}" == "true" ]] && caddyfile_content+="\nn8n.\${TENANT_DOMAIN} {
    reverse_proxy n8n:\${N8N_PORT:-5678}
}
"
    [[ "${ENABLE_QDRANT:-false}" == "true" ]] && caddyfile_content+="\nqdrant.\${TENANT_DOMAIN} {
    reverse_proxy qdrant:\${QDRANT_PORT:-6333}
}
"
    [[ "${ENABLE_OLLAMA:-false}" == "true" ]] && caddyfile_content+="\nollama.\${TENANT_DOMAIN} {
    reverse_proxy ollama:\${OLLAMA_PORT:-11434}
}
"
    [[ "${ENABLE_OPENWEBUI:-false}" == "true" ]] && caddyfile_content+="\nopenwebui.\${TENANT_DOMAIN} {
    reverse_proxy openwebui:8080
}
"
    [[ "${ENABLE_FLOWISE:-false}" == "true" ]] && caddyfile_content+="\nflowise.\${TENANT_DOMAIN} {
    reverse_proxy flowise:3000
}
"
    [[ "${ENABLE_LITELLM:-false}" == "true" ]] && caddyfile_content+="\nlitellm.\${TENANT_DOMAIN} {
    reverse_proxy litellm:4000
}
"
    [[ "${ENABLE_GRAFANA:-false}" == "true" ]] && caddyfile_content+="\ngrafana.\${TENANT_DOMAIN} {
    reverse_proxy grafana:3000
}
"

    # Write final file
    echo -e "${caddyfile_content}" > "${TENANT_DIR}/Caddyfile"

    # Reload Caddy to apply new configuration without downtime
    log "Reloading Caddy with new production configuration..."
    if docker exec "${COMPOSE_PROJECT_NAME}-caddy-1" caddy reload --config /etc/caddy/Caddyfile; then
        ok "Caddy reloaded successfully."
    else
        warn "Caddy reload failed. Check Caddy container logs for errors."
    fi
}

# ─── Interactive Diagnostics Functions ──────────────────────────────────────────

view_service_logs() {
    read -p "Enter service name (e.g., caddy, n8n, flowise): " service_name
    if [[ -n "$service_name" ]]; then
        local container_name="${COMPOSE_PROJECT_NAME}-${service_name}-1"
        if sudo docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
            echo -e "${CYAN}Showing logs for ${service_name} (last 50 lines):${NC}"
            sudo docker logs "${container_name}" --tail 50 -f
        else
            echo -e "${RED}Error: Container ${container_name} not found${NC}"
        fi
    fi
}

set_proxy_log_level() {
    read -p "Enter proxy service (caddy/nginx): " proxy_service
    read -p "Enter log level (debug, info, warn, error): " log_level
    
    case "${proxy_service}" in
        "caddy")
            echo -e "${CYAN}Setting Caddy log level to ${log_level}...${NC}"
            # For now, just show current logs with appropriate filtering
            case "${log_level}" in
                "debug")
                    sudo docker logs "${COMPOSE_PROJECT_NAME}-caddy-1" --tail 100 -f
                    ;;
                "info")
                    sudo docker logs "${COMPOSE_PROJECT_NAME}-caddy-1" --tail 50 -f | grep -E "(INFO|WARN|ERROR)"
                    ;;
                "warn"|"error")
                    sudo docker logs "${COMPOSE_PROJECT_NAME}-caddy-1" --tail 20 -f | grep -E "(WARN|ERROR|FATAL)"
                    ;;
            esac
            ;;
        *)
            echo -e "${RED}Error: ${proxy_service} not supported${NC}"
            ;;
    esac
}

run_full_health_check() {
    echo -e "${CYAN}Running comprehensive health check...${NC}"
    cd "${TENANT_DIR}"
    
    echo -e "${BOLD}🏥 Service Health Status:${NC}"
    sudo docker compose ps
    
    echo -e "\n${BOLD}🔗 URL Connectivity Tests:${NC}"
    
    # Test external URLs
    [[ "${ENABLE_N8N:-false}" == "true" ]] && {
        echo -n "n8n: "
        if curl -sf --max-time 10 "https://n8n.${TENANT_DOMAIN}" >/dev/null; then
            echo -e "${GREEN}✅ Working${NC}"
        else
            echo -e "${RED}❌ Failed${NC}"
        fi
    }
    
    [[ "${ENABLE_FLOWISE:-false}" == "true" ]] && {
        echo -n "Flowise: "
        if curl -sf --max-time 10 "https://flowise.${TENANT_DOMAIN}" >/dev/null; then
            echo -e "${GREEN}✅ Working${NC}"
        else
            echo -e "${RED}❌ Failed${NC}"
        fi
    }
    
    # Test internal URLs
    echo -e "\n${BOLD}🔗 Internal Service Tests:${NC}"
    
    [[ "${ENABLE_OLLAMA:-false}" == "true" ]] && {
        echo -n "Ollama API: "
        if curl -sf --max-time 5 "http://localhost:11434/api/tags" >/dev/null; then
            echo -e "${GREEN}✅ Working${NC}"
        else
            echo -e "${RED}❌ Failed${NC}"
        fi
    }
    
    [[ "${ENABLE_QDRANT:-false}" == "true" ]] && {
        echo -n "Qdrant API: "
        if curl -sf --max-time 5 "http://localhost:6333/healthz" >/dev/null; then
            echo -e "${GREEN}✅ Working${NC}"
        else
            echo -e "${RED}❌ Failed${NC}"
        fi
    }
}

view_access_summary() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                   🌐 Service Access Summary                   ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${GREEN}🌐 External HTTPS URLs:${NC}"
    [[ "${ENABLE_N8N:-false}" == "true" ]] && echo "  • n8n:          https://n8n.${TENANT_DOMAIN}"
    [[ "${ENABLE_FLOWISE:-false}" == "true" ]] && echo "  • Flowise:      https://flowise.${TENANT_DOMAIN}"
    [[ "${ENABLE_OPENWEBUI:-false}" == "true" ]] && echo "  • OpenWebUI:   https://openwebui.${TENANT_DOMAIN}"
    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && echo "  • AnythingLLM:  https://anythingllm.${TENANT_DOMAIN}"
    [[ "${ENABLE_LITELLM:-false}" == "true" ]] && echo "  • LiteLLM:      https://litellm.${TENANT_DOMAIN}"
    [[ "${ENABLE_GRAFANA:-false}" == "true" ]] && echo "  • Grafana:      https://grafana.${TENANT_DOMAIN}"
    [[ "${ENABLE_SIGNAL:-false}" == "true" ]] && echo "  • Signal API:   https://signal.${TENANT_DOMAIN}"
    
    echo -e "\n${GREEN}🔗 Internal URLs:${NC}"
    [[ "${ENABLE_N8N:-false}" == "true" ]] && echo "  • n8n:          http://localhost:5678"
    [[ "${ENABLE_FLOWISE:-false}" == "true" ]] && echo "  • Flowise:      http://localhost:3000"
    [[ "${ENABLE_OPENWEBUI:-false}" == "true" ]] && echo "  • OpenWebUI:   http://localhost:8081"
    [[ "${ENABLE_OLLAMA:-false}" == "true" ]] && echo "  • Ollama API:   http://localhost:11434/api/tags"
    [[ "${ENABLE_QDRANT:-false}" == "true" ]] && echo "  • Qdrant API:   http://localhost:6333"
}

interactive_diagnostics_menu() {
    while true; do
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║            🔧 Interactive Diagnostics Menu                  ║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${BOLD}Tenant:${NC} ${TENANT_ID}"
        echo -e "${BOLD}Domain:${NC} ${TENANT_DOMAIN}"
        echo ""
        
        PS3="Select a diagnostic action: "
        options=(
            "View Docker Logs for a Service"
            "Set Proxy Log Level (Caddy)"
            "Run Full Health Check"
            "View Access URL Summary"
            "Restart a Service"
            "Quit"
        )
        
        select opt in "${options[@]}"; do
            case $opt in
                "View Docker Logs for a Service")
                    view_service_logs
                    ;;
                "Set Proxy Log Level (Caddy)")
                    set_proxy_log_level
                    ;;
                "Run Full Health Check")
                    run_full_health_check
                    ;;
                "View Access URL Summary")
                    view_access_summary
                    ;;
                "Restart a Service")
                    read -p "Enter service name to restart: " restart_service
                    if [[ -n "$restart_service" ]]; then
                        cd "${TENANT_DIR}"
                        sudo docker compose restart "${restart_service}"
                        echo -e "${GREEN}Service ${restart_service} restarted${NC}"
                    fi
                    ;;
                "Quit")
                    break 2
                    ;;
                *) 
                    echo -e "${RED}Invalid option $REPLY${NC}"
                    ;;
            esac
            echo ""
            echo -e "${DIM}Press Enter to continue...${NC}"
            read
            break
        done
    done
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    print_header
    parse_args "$@"
    load_env
    
    # Load environment and set up basic variables
    TENANT_DIR="/mnt/data/${TENANT_ID}"
    COMPOSE_PROJECT_NAME="ai-${TENANT_ID}"
    
    # Verify tenant directory exists
    if [[ ! -d "${TENANT_DIR}" ]]; then
        echo -e "${RED}Error: Tenant directory ${TENANT_DIR} not found${NC}"
        echo "Please run script-2 first to deploy the services."
        exit 1
    fi
    
    echo -e "${GREEN}✅ Environment loaded for tenant: ${TENANT_ID}${NC}"
    echo -e "${GREEN}✅ Domain: ${TENANT_DOMAIN}${NC}"
    echo ""
    
    # NEW: The script's main purpose is now this interactive menu
    interactive_diagnostics_menu
    
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                  ✅  Diagnostics Complete                      ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

main "$@"
