#!/bin/bash

# **1-setup-wizard.sh**
# **Interactive configuration wizard based on frontier patterns**
# **Produces /mnt/data/.env with service flags and dependencies**

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] INFO: $*${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARN: $*${NC}"; }
err() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR: $*${NC}"; exit 1; }
section() { echo -e "\n${BLUE}${BOLD}━━━ $* ━━━${NC}"; }
ask() { echo -e "${CYAN}$*${NC}"; }

PLATFORM_DIR="/mnt/data"
ENV_FILE="${PLATFORM_DIR}/.env"
LOG_FILE="${PLATFORM_DIR}/logs/setup.log"

# **── Root check ────────────────────────────────────────────────────────────────**
[[ $EUID -ne 0 ]] && err "Must run as root (sudo)"

# **── Logging setup ───────────────────────────────────────────────────────────**
mkdir -p "${PLATFORM_DIR}/logs"
touch "$LOG_FILE"

# **── Dependency check ──────────────────────────────────────────────────────────**
check_prerequisites() {
    section "Prerequisite Check"
    local missing=()
    
    command -v docker        &>/dev/null || missing+=("docker")
    command -v curl          &>/dev/null || missing+=("curl")
    command -v openssl       &>/dev/null || missing+=("openssl")
    docker compose version   &>/dev/null || missing+=("docker-compose-plugin")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        err "Missing prerequisites: ${missing[*]}\nRun 0-install-prerequisites.sh first"
    fi
    log "All prerequisites satisfied"
}

# **── Resource detection ────────────────────────────────────────────────────────**
detect_resources() {
    section "System Resource Detection"
    
    DETECTED_RAM_GB=$(awk '/MemTotal/{printf "%d", $2/1024/1024}' /proc/meminfo)
    DETECTED_DISK_GB=$(df "${PLATFORM_DIR}" --output=avail -BG 2>/dev/null | tail -1 | tr -d 'G ')
    DETECTED_CPUS=$(nproc)
    DETECTED_IP=$(hostname -I | awk '{print $1}')
    
    # GPU detection
    GPU_DETECTED=false
    GPU_NAME=""
    GPU_VRAM_GB=0
    
    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null 2>&1; then
        GPU_DETECTED=true
        GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
        GPU_VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1 | tr -d ' ')
        GPU_VRAM_GB=$(( GPU_VRAM_MB / 1024 ))
        log "GPU: ${GPU_NAME} (${GPU_VRAM_GB}GB VRAM)"
    fi
    
    log "RAM:  ${DETECTED_RAM_GB}GB"
    log "Disk: ${DETECTED_DISK_GB}GB available"
    log "CPUs: ${DETECTED_CPUS}"
    log "IP:   ${DETECTED_IP}"
    log "GPU:  ${GPU_DETECTED} ${GPU_NAME:+(${GPU_NAME})}"
}

# **── Secret generation ─────────────────────────────────────────────────────────**
gen_secret() { openssl rand -hex 32; }
gen_password() { openssl rand -base64 24 | tr -d '=+' | head -c 32; }

# **── Service selection ─────────────────────────────────────────────────────────**
declare -A SVC_DISPLAY=(
    [ollama]="Ollama (LLM Runtime)"
    [openwebui]="Open WebUI (Chat Interface)"
    [flowise]="Flowise (Visual Flow Builder)"
    [n8n]="n8n (Workflow Automation)"
    [dify]="Dify (AI Application Platform)"
    [anythingllm]="AnythingLLM (Knowledge Base)"
    [litellm]="LiteLLM (API Gateway)"
    [prometheus]="Prometheus (Monitoring)"
    [grafana]="Grafana (Visualization)"
    [redis]="Redis (Cache/Queue)"
    [postgres]="PostgreSQL (Database)"
    [minio]="MinIO (Object Storage)"
    [signal]="Signal API (Communication)"
    [openclaw]="OpenClaw (AI Assistant)"
)

declare -A SVC_DESCRIPTION=(
    [ollama]="Runs local LLM models (llama, mistral, etc.)"
    [openwebui]="ChatGPT-like interface for Ollama + OpenAI"
    [flowise]="Drag-and-drop LLM flow builder (LangChain)"
    [n8n]="No-code workflow automation with AI nodes"
    [dify]="Complete AI application development platform"
    [anythingllm]="Private knowledge base and document Q&A"
    [litellm]="Unified API gateway for multiple LLM providers"
    [prometheus]="Metrics collection and monitoring"
    [grafana]="Data visualization and dashboards"
    [redis]="Required by n8n, litellm, and session storage"
    [postgres]="Primary database for AI applications"
    [minio]="S3-compatible object storage"
    [signal]="Signal Messenger API integration"
    [openclaw]="Advanced AI assistant and automation"
)

declare -A SVC_MIN_RAM=(
    [ollama]=4 [openwebui]=1 [flowise]=1 [n8n]=1 [dify]=2
    [anythingllm]=1 [litellm]=1 [prometheus]=1 [grafana]=1
    [redis]=0 [postgres]=1 [minio]=1 [signal]=0 [openclaw]=1
)

declare -A SVC_DEFAULT_ENABLED=(
    [ollama]=true [openwebui]=true [flowise]=true [n8n]=true [dify]=true
    [anythingllm]=true [litellm]=true [prometheus]=true [grafana]=true
    [redis]=true [postgres]=true [minio]=true [signal]=true [openclaw]=true
)

SERVICE_ORDER=(postgres redis ollama openwebui flowise n8n dify anythingllm litellm prometheus grafana minio signal openclaw)
declare -A SERVICE_ENABLED

select_services() {
    section "Service Selection"
    
    echo ""
    echo "  Available services (RAM budget: ${DETECTED_RAM_GB}GB):"
    echo ""
    printf "  %-4s %-30s %-8s %s\n" "Sel" "Service" "Min RAM" "Description"
    printf "  %-4s %-30s %-8s %s\n" "---" "-------" "-------" "-----------"
    
    local total_min_ram=0
    for svc in "${SERVICE_ORDER[@]}"; do
        local min_ram="${SVC_MIN_RAM[$svc]}"
        local default="${SVC_DEFAULT_ENABLED[$svc]}"
        local flag="[Y]"
        [[ "$default" != "true" ]] && flag="[n]"
        [[ $min_ram -gt $DETECTED_RAM_GB ]] && flag="[!] LOW RAM"
        printf "  %-4s %-30s %-8s %s\n" \
            "$flag" "${SVC_DISPLAY[$svc]}" "${min_ram}GB" "${SVC_DESCRIPTION[$svc]}"
    done
    
    echo ""
    echo "  Options:"
    echo "    a) Accept all defaults (recommended)"
    echo "    c) Custom selection"
    echo "    m) Minimal (Ollama + Open WebUI only)"
    echo ""
    ask "Choice [a/c/m] (default: a):"
    read -r sel_choice
    sel_choice="${sel_choice:-a}"
    
    case "${sel_choice,,}" in
        a)
            log "Using default service selection"
            for svc in "${SERVICE_ORDER[@]}"; do
                SERVICE_ENABLED[$svc]="${SVC_DEFAULT_ENABLED[$svc]}"
            done
            ;;
        m)
            log "Minimal selection: Ollama + Open WebUI"
            for svc in "${SERVICE_ORDER[@]}"; do
                SERVICE_ENABLED[$svc]=false
            done
            SERVICE_ENABLED[ollama]=true
            SERVICE_ENABLED[openwebui]=true
            ;;
        c)
            log "Custom selection:"
            for svc in "${SERVICE_ORDER[@]}"; do
                local default="${SVC_DEFAULT_ENABLED[$svc]}"
                local default_label="Y/n"
                [[ "$default" != "true" ]] && default_label="y/N"
                ask "  Enable ${SVC_DISPLAY[$svc]}? [${default_label}]:"
                read -r ans
                if [[ -z "$ans" ]]; then
                    SERVICE_ENABLED[$svc]="$default"
                else
                    SERVICE_ENABLED[$svc]=$([[ "${ans,,}" == "y" ]] && echo true || echo false)
                fi
                log "  ${SVC_DISPLAY[$svc]}: ${SERVICE_ENABLED[$svc]}"
            done
            ;;
        *)
            err "Invalid choice"
            ;;
    esac
    
    # Enforce dependencies
    if [[ "${SERVICE_ENABLED[postgres]:-false}" == "true" ]]; then
        log "PostgreSQL enabled - database available"
    fi
    
    if [[ "${SERVICE_ENABLED[redis]:-false}" != "true" ]]; then
        if [[ "${SERVICE_ENABLED[n8n]:-false}" == "true" ]] || [[ "${SERVICE_ENABLED[litellm]:-false}" == "true" ]]; then
            warn "Redis is required by n8n/litellm - enabling automatically"
            SERVICE_ENABLED[redis]=true
        fi
    fi
    
    # Show final selection
    echo ""
    log "Final service selection:"
    for svc in "${SERVICE_ORDER[@]}"; do
        local status="${SERVICE_ENABLED[$svc]:-false}"
        local icon="✓"; [[ "$status" != "true" ]] && icon="✗"
        log "  ${icon} ${SVC_DISPLAY[$svc]}"
    done
}

# **── Port configuration ───────────────────────────────────────────────────────────**
configure_ports() {
    section "Port Configuration"
    
    declare -gA DEFAULT_PORTS=(
        [postgres]=5432 [redis]=6379 [ollama]=11434 [openwebui]=5006
        [flowise]=3002 [n8n]=5002 [dify]=5003 [anythingllm]=5004
        [litellm]=5005 [prometheus]=9090 [grafana]=5001
        [minio]=5007 [signal]=8090 [openclaw]=8083
    )
    
    echo ""
    ask "Customize ports? [y/N] (default: N):"
    read -r port_ans
    
    declare -gA FINAL_PORTS
    if [[ "${port_ans,,}" == "y" ]]; then
        for svc in "${!DEFAULT_PORTS[@]}"; do
            if [[ "${SERVICE_ENABLED[$svc]:-false}" == "true" ]]; then
                ask "  ${svc} port [${DEFAULT_PORTS[$svc]}]:"
                read -r p
                FINAL_PORTS[$svc]="${p:-${DEFAULT_PORTS[$svc]}}"
            fi
        done
    else
        for svc in "${!DEFAULT_PORTS[@]}"; do
            FINAL_PORTS[$svc]="${DEFAULT_PORTS[$svc]}"
        done
    fi
    
    # Log enabled service ports
    for svc in "${SERVICE_ORDER[@]}"; do
        if [[ "${SERVICE_ENABLED[$svc]:-false}" == "true" ]]; then
            log "  ${svc}: ${FINAL_PORTS[$svc]:-N/A}"
        fi
    done
}

# **── Domain configuration ───────────────────────────────────────────────────────────**
configure_domain() {
    section "Domain Configuration"
    
    echo ""
    echo "  1) Local IP only (http://${DETECTED_IP}) - no DNS required"
    echo "  2) Custom domain (https://yourdomain.com) - requires DNS + SSL"
    echo ""
    ask "Select deployment mode [1-2] (default: 2):"
    read -r mode_choice
    mode_choice="${mode_choice:-2}"
    
    case "$mode_choice" in
        1)
            DEPLOYMENT_MODE="local"
            BASE_DOMAIN="${DETECTED_IP}"
            USE_SSL=false
            log "Mode: Local IP (${DETECTED_IP})"
            ;;
        2)
            DEPLOYMENT_MODE="domain"
            ask "Enter your domain (e.g. ai.datasquiz.net):"
            read -r BASE_DOMAIN
            [[ -z "$BASE_DOMAIN" ]] && err "Domain cannot be empty"
            USE_SSL=true
            log "Mode: Domain (${BASE_DOMAIN}, SSL=${USE_SSL})"
            ;;
        *)
            err "Invalid choice: ${mode_choice}"
            ;;
    esac
}

# **── Write .env file ────────────────────────────────────────────────────────────**
write_env_file() {
    section "Writing Configuration"
    
    mkdir -p "${PLATFORM_DIR}/configs" "${PLATFORM_DIR}/secrets"
    chmod 700 "${PLATFORM_DIR}/secrets"
    
    cat > "$ENV_FILE" << EOF
# ============================================================
# AI Platform Configuration
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# DO NOT COMMIT TO VERSION CONTROL
# ============================================================

# ─── Platform ───────────────────────────────────────────────────────────────────
PLATFORM_DIR=${PLATFORM_DIR}
DEPLOYMENT_MODE=${DEPLOYMENT_MODE}
BASE_DOMAIN=${BASE_DOMAIN}
USE_SSL=${USE_SSL}
SERVER_IP=${DETECTED_IP}

# ─── System Resources ───────────────────────────────────────────────────────────
DETECTED_RAM_GB=${DETECTED_RAM_GB}
DETECTED_DISK_GB=${DETECTED_DISK_GB}
DETECTED_CPUS=${DETECTED_CPUS}
GPU_DETECTED=${GPU_DETECTED}
GPU_NAME=${GPU_NAME:-none}
GPU_VRAM_GB=${GPU_VRAM_GB:-0}

# ─── Service Enablement Flags ───────────────────────────────────────────────────
# These flags drive ALL downstream scripts
EOF

    # Add service flags
    for svc in "${SERVICE_ORDER[@]}"; do
        local flag_name="SERVICE_${svc^^}_ENABLED"
        echo "${flag_name}=${SERVICE_ENABLED[$svc]:-false}" >> "$ENV_FILE"
    done
    
    # Add ports
    cat >> "$ENV_FILE" << EOF

# ─── Port Assignments ───────────────────────────────────────────────────────────
EOF
    
    for svc in "${!FINAL_PORTS[@]}"; do
        if [[ "${SERVICE_ENABLED[$svc]:-false}" == "true" ]]; then
            local port_name="${svc^^}_PORT"
            echo "${port_name}=${FINAL_PORTS[$svc]}" >> "$ENV_FILE"
        fi
    done
    
    # Add secrets
    cat >> "$ENV_FILE" << EOF

# ─── Security ───────────────────────────────────────────────────────────────────
ADMIN_PASSWORD=$(gen_password)
LITELLM_MASTER_KEY=$(gen_secret)
LITELLM_SALT_KEY=$(gen_secret)
ENCRYPTION_KEY=$(gen_secret)
DIFY_SECRET_KEY=$(gen_secret)
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=$(gen_password)
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$(gen_password)
REDIS_PASSWORD=

# ─── User Configuration ───────────────────────────────────────────────────────────
RUNNING_USER=jglaine
RUNNING_UID=1001
RUNNING_GID=1001
BIND_IP=0.0.0.0

# ─── Timezone ───────────────────────────────────────────────────────────────────
TIMEZONE=UTC

EOF
    
    chmod 600 "$ENV_FILE"
    log "Configuration written to: $ENV_FILE"
}

# **── Summary ───────────────────────────────────────────────────────────────────────**
show_summary() {
    section "Configuration Summary"
    echo ""
    log "Platform directory : ${PLATFORM_DIR}"
    log "Deployment mode   : ${DEPLOYMENT_MODE}"
    log "Base domain/IP   : ${BASE_DOMAIN}"
    log "SSL              : ${USE_SSL}"
    echo ""
    log "Selected services:"
    for svc in "${SERVICE_ORDER[@]}"; do
        local enabled="${SERVICE_ENABLED[$svc]:-false}"
        local icon="✓"; [[ "$enabled" != "true" ]] && icon="✗"
        printf " %s %s\n" "$icon" "${SVC_DISPLAY[$svc]}"
    done
    echo ""
    log "Config file: $ENV_FILE"
    echo ""
    log "Next step: sudo bash 2-deploy-enhanced.sh"
}

# **── Main ──────────────────────────────────────────────────────────────────────────**
main() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo " ╔═══════════════════════════════════════╗"
    echo " ║ AI Platform Setup Wizard (Frontier Style) ║"
    echo " ╚═══════════════════════════════════════╝"
    echo -e "${NC}"
    
    check_prerequisites
    detect_resources
    configure_domain
    select_services
    configure_ports
    write_env_file
    show_summary
}

main "$@"
