#!/usr/bin/env bash
# =============================================================================
# Script 1: System Setup Wizard
# =============================================================================
# PURPOSE: Interactive setup wizard for AI Platform
# USAGE:   sudo bash scripts/1-setup-system.sh
# =============================================================================

set -euo pipefail

# ─── Colours ─────────────────────────────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
NC='\033[0m'

# ─── Runtime vars (set after volume selection) ────────────────────────────────
DATA_ROOT=""
ENV_FILE=""
COMPOSE_DIR=""
CADDY_DIR=""
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}        🚀  AI Platform — System Setup Wizard                 ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    local step="${1}" total="${2}" title="${3}"
    echo ""
    echo -e "${CYAN}  ┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}  │${NC}  ${BOLD}[ STEP ${step} of ${total} ]${NC}  ${title}"
    echo -e "${CYAN}  └─────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

print_section() {
    local title="${1}"
    echo ""
    echo -e "${CYAN}  ┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}  │${NC}  ${BOLD}${title}${NC}"
    echo -e "${CYAN}  └─────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

print_divider() {
    echo ""
    echo -e "${DIM}  ════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ─── ask_service helper ──────────────────────────────────────────────────────
# Usage: ask_service "emoji" "Label" "Description" "VAR_NAME" "default"
ask_service() {
    local emoji="$1" name="$2" desc="$3" var="$4" default="$5"
    local prompt_default
    [ "${default}" = "y" ] && prompt_default="[Y/n]" || prompt_default="[y/N]"
    
    printf "  %s  %-20s - %-35s" "${emoji}" "${name}" "${desc}"
    read -p " ${prompt_default}: " answer
    answer="${answer:-${default}}"
    
    if [[ "${answer,,}" == "y" ]]; then
        export "${var}=true"
        echo "  ✅ ${name} enabled"
    else
        export "${var}=false"
        echo "  ❌ ${name} disabled"
    fi
}

# ─── Prerequisites ───────────────────────────────────────────────────────────
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log "ERROR" "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_prerequisites() {
    print_step "1" "9" "System Prerequisites"

    # Check Docker
    if ! command -v docker &> /dev/null; then
        log "ERROR" "Docker not installed. Install Docker first."
        exit 1
    fi

    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        log "ERROR" "Docker Compose not available. Install Docker Compose first."
        exit 1
    fi

    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log "ERROR" "Docker daemon is not running. Start Docker service first."
        exit 1
    fi

    log "SUCCESS" "Docker and Docker Compose are available"
}

# ─── EBS Volume Detection and Mounting ───────────────────────────────────────────
detect_and_mount_ebs() {
    print_step "2" "9" "EBS Volume Detection and Mounting"

    echo -e "  ${BOLD}💾  EBS Volume Detection${NC}"
    echo -e "  ${DIM}Scanning for available EBS volumes to mount${NC}"
    echo ""

    # List available block devices
    echo -e "  ${BOLD}Available Block Devices:${NC}"
    lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "^nvme|^xvd|^sd" | while read -r line; do
        echo -e "  ${CYAN}    ${line}${NC}"
    done
    echo ""

    # Find unmounted EBS volumes
    local unmounted_volumes=()
    while IFS= read -r device; do
        if ! lsblk -n -o MOUNTPOINT "${device}" | grep -q "."; then
            unmounted_volumes+=("${device}")
        fi
    done < <(lsblk -d -n -o NAME | grep -E "^nvme|^xvd|^sd")

    if [ ${#unmounted_volumes[@]} -eq 0 ]; then
        log "INFO" "No unmounted EBS volumes found"
        return
    fi

    echo -e "  ${BOLD}Unmounted EBS Volumes:${NC}"
    local idx=0
    for volume in "${unmounted_volumes[@]}"; do
        size=$(lsblk -d -n -o SIZE "/dev/${volume}")
        echo -e "  ${CYAN}  $((++idx))${NC}  /dev/${volume}  ${DIM}(${size})${NC}"
    done
    echo ""

    # Ask user to select volume to mount
    while true; do
        read -p "  ➤ Select EBS volume to mount [1-${idx}] (or skip): " choice
        if [[ -z "${choice}" ]]; then
            log "INFO" "Skipping EBS mount"
            break
        fi
        if [[ "${choice}" =~ ^[0-9]+$ ]] && [ "${choice}" -ge 1 ] && [ "${choice}" -le "${idx}" ]; then
            local selected_volume="${unmounted_volumes[$((choice-1))]}"
            local mount_point="/mnt/data"
            
            log "INFO" "Mounting /dev/${selected_volume} to ${mount_point}"
            
            # Create mount point if it doesn't exist
            sudo mkdir -p "${mount_point}"
            
            # Check if already mounted
            if mountpoint -q "${mount_point}" 2>/dev/null; then
                log "WARN" "${mount_point} is already mounted"
                break
            fi
            
            # Mount the volume
            if sudo mount "/dev/${selected_volume}" "${mount_point}" 2>/dev/null; then
                log "SUCCESS" "EBS volume mounted: /dev/${selected_volume} → ${mount_point}"
                
                # Add to /etc/fstab for persistence
                if ! grep -q "/dev/${selected_volume}" /etc/fstab; then
                    echo "/dev/${selected_volume}  ${mount_point}  ext4  defaults  0  2" | sudo tee -a /etc/fstab
                    log "INFO" "Added to /etc/fstab for persistence"
                fi
                break
            else
                log "ERROR" "Failed to mount /dev/${selected_volume}"
                echo -e "  ${DIM}You may need to format the volume first:${NC}"
                echo -e "  ${DIM}  sudo mkfs.ext4 /dev/${selected_volume}${NC}"
            fi
            break
        else
            echo "  ❌ Enter a number between 1 and ${idx}, or leave empty to skip"
        fi
    done
}

# ─── Data Volume Selection ───────────────────────────────────────────────────
select_data_volume() {
    print_step "4" "10" "Data Volume Selection"

    echo -e "  ${BOLD}💾  Available Mount Points${NC}"
    echo -e "  ${DIM}Select where to store AI platform data${NC}"
    echo ""

    # Enumerate available mounts
    local mounts=()
    local idx=0
    
    # Add /mnt if it's a mount point
    if mountpoint -q /mnt 2>/dev/null; then
        mounts+=("/mnt")
        echo -e "  ${CYAN}  $((++idx))${NC}  /mnt  ${DIM}$(findmnt /mnt -no SIZE -o SIZE || echo "Unknown size")${NC}"
    fi

    # Add other potential mount points
    while IFS= read -r mount; do
        if [[ "${mount}" != "/mnt" ]] && mountpoint -q "${mount}" 2>/dev/null; then
            mounts+=("${mount}")
            echo -e "  ${CYAN}  $((++idx))${NC}  ${mount}  ${DIM}$(findmnt "${mount}" -no SIZE -o SIZE || echo "Unknown size")${NC}"
        fi
    done < <(findmnt -l -n -o TARGET | grep -E '^/[^/]' | sort)

    # Add custom option
    echo -e "  ${CYAN}  $((++idx))${NC}  Custom path"
    echo ""

    while true; do
        read -p "  ➤ Select volume [1-${idx}]: " choice
        if [[ "${choice}" =~ ^[0-9]+$ ]] && [ "${choice}" -ge 1 ] && [ "${choice}" -le "${idx}" ]; then
            break
        fi
        echo "  ❌ Enter a number between 1 and ${idx}"
    done

    if [ "${choice}" -eq "${idx}" ]; then
        # Custom path
        while true; do
            read -p "  ➤ Enter custom path: " custom_path
            if [ -n "${custom_path}" ]; then
                DATA_ROOT="${custom_path}/${TENANT_ID}"
                break
            fi
            echo "  ❌ Path cannot be empty"
        done
    else
        DATA_ROOT="${mounts[$((choice-1))]}/${TENANT_ID}"
    fi

    # Set derived paths
    ENV_FILE="${DATA_ROOT}/.env"
    COMPOSE_DIR="${DATA_ROOT}/compose"
    CADDY_DIR="${DATA_ROOT}/caddy"

    log "SUCCESS" "Data will be stored in: ${DATA_ROOT}"
}

# ─── Hardware Detection ────────────────────────────────────────────────────
detect_gpu() {
    print_step "5" "10" "Hardware Detection"

    # Initialize GPU_TYPE to prevent unbound variable error
    GPU_TYPE="cpu"
    
    # Method 1: nvidia-smi
    if command -v nvidia-smi &>/dev/null && nvidia-smi &>/dev/null; then
        export GPU_TYPE="nvidia"
        GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
        log "INFO" "NVIDIA GPU detected: ${GPU_COUNT} GPU(s)"
        return
    fi

    # Method 2: lspci
    if command -v lspci &>/dev/null; then
        if lspci 2>/dev/null | grep -qi "nvidia"; then
            export GPU_TYPE="nvidia"
            log "WARN" "NVIDIA GPU found via lspci but nvidia-smi unavailable"
            log "WARN" "Install: sudo apt install nvidia-container-toolkit"
        elif lspci 2>/dev/null | grep -qi "amd.*display\|radeon"; then
            export GPU_TYPE="amd"
        fi
        return
    fi

    # Method 3: /proc/driver/nvidia
    if [ -d "/proc/driver/nvidia" ]; then
        export GPU_TYPE="nvidia"
        return
    fi

    export GPU_TYPE="cpu"
    log "INFO" "No GPU detected — using CPU mode"
}

# ─── DNS resolution check (used inside collect_identity) ─────────────────────
check_dns() {
    local domain="${1}"
    PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null \
             || curl -s --max-time 5 api.ipify.org 2>/dev/null \
             || echo "unknown")
    RESOLVED_IP=$(dig +short "${domain}" 2>/dev/null | grep -E '^[0-9]+\.' | tail -1 || echo "")

    if [ -z "${RESOLVED_IP}" ]; then
        log "WARN" "DNS for ${domain} did not resolve — self-signed TLS will be used"
        SSL_TYPE="selfsigned"
        DOMAIN_RESOLVES=false
    elif [ "${RESOLVED_IP}" = "${PUBLIC_IP}" ]; then
        log "SUCCESS" "DNS verified — ${domain} → ${PUBLIC_IP}"
        SSL_TYPE="acme"
        DOMAIN_RESOLVES=true
    else
        log "WARN" "DNS mismatch — expected ${PUBLIC_IP}, got ${RESOLVED_IP}"
        log "WARN" "Caddy will attempt ACME but may fail — check your DNS records"
        SSL_TYPE="acme"
        DOMAIN_RESOLVES=false
    fi
}

# ─── Rebuild collect_identity to use check_dns ───────────────────────────────
collect_identity() {
    print_step "2" "10" "Domain & Identity"

    echo -e "  ${BOLD}🌐  Domain Setup${NC}"
    echo -e "  ${DIM}DNS must already point to this server for automatic TLS to work${NC}"
    echo ""

    while true; do
        read -p "  ➤ Domain name (e.g. ai.example.com): " DOMAIN
        DOMAIN="${DOMAIN,,}"
        if [[ "${DOMAIN}" =~ ^[a-z0-9][a-z0-9.\-]{2,253}[a-z0-9]$ ]]; then
            break
        fi
        echo "  ❌ Invalid domain format — try again"
    done

    check_dns "${DOMAIN}"

    print_divider

    echo -e "  ${BOLD}🏷️   Tenant Identifier${NC}"
    echo -e "  ${DIM}Short ID used for naming, namespacing and branding${NC}"
    echo ""

    while true; do
        read -p "  ➤ Tenant ID (e.g. mycompany): " TENANT_ID
        TENANT_ID="${TENANT_ID,,}"
        if [[ "${TENANT_ID}" =~ ^[a-z][a-z0-9\-]{2,29}$ ]]; then
            break
        fi
        echo "  ❌ Must start with a letter, 3–30 chars, lowercase/numbers/hyphens only"
    done

    print_divider

    echo -e "  ${BOLD}📧  Admin Email${NC}"
    echo ""
    while true; do
        read -p "  ➤ Admin email address: " ADMIN_EMAIL
        if [[ "${ADMIN_EMAIL}" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
            break
        fi
        echo "  ❌ Invalid email format — try again"
    done
}

# ─── STEP 5: Stack selection ──────────────────────────────────────────────────
select_stack() {
    print_step "5" "9" "Service Stack Selection"

    echo -e "  ${BOLD}📦  Choose a service stack${NC}"
    echo -e "  ${DIM}Stacks are pre-configured bundles — you can customise in the next step${NC}"
    echo ""
    echo -e "  ${CYAN}  1)${NC}  🟢  ${BOLD}Minimal${NC}       — Ollama + Open WebUI only"
    echo -e "             ${DIM}Ideal for local LLM inference, low resource usage${NC}"
    echo ""
    echo -e "  ${CYAN}  2)${NC}  🔵  ${BOLD}Standard${NC}      — Minimal + n8n + Flowise + Qdrant + LiteLLM"
    echo -e "             ${DIM}Full AI automation stack, recommended starting point${NC}"
    echo ""
    echo -e "  ${CYAN}  3)${NC}  🟣  ${BOLD}Full${NC}          — Standard + AnythingLLM + Grafana + Prometheus + Authentik"
    echo -e "             ${DIM}Production-grade with observability and SSO${NC}"
    echo ""
    echo -e "  ${CYAN}  4)${NC}  ⚙️   ${BOLD}Custom${NC}        — Pick services individually"
    echo -e "             ${DIM}Full control over what gets deployed${NC}"
    echo ""

    while true; do
        read -p "  ➤ Select stack [1-4]: " stack_choice
        stack_choice="${stack_choice:-2}"
        case "${stack_choice}" in
            1|2|3|4) break ;;
            *) echo "  ❌ Enter 1, 2, 3 or 4" ;;
        esac
    done

    # ── Apply stack presets ───────────────────────────────────────────────────
    # First zero everything out
    ENABLE_OLLAMA=false
    ENABLE_OPENWEBUI=false
    ENABLE_ANYTHINGLLM=false
    ENABLE_DIFY=false
    ENABLE_N8N=false
    ENABLE_FLOWISE=false
    ENABLE_LITELLM=false
    ENABLE_QDRANT=false
    ENABLE_GRAFANA=false
    ENABLE_PROMETHEUS=false
    ENABLE_AUTHENTIK=false
    ENABLE_SIGNAL=false

    case "${stack_choice}" in
        1)  # Minimal
            ENABLE_OLLAMA=true
            ENABLE_OPENWEBUI=true
            STACK_NAME="minimal"
            log "SUCCESS" "Stack: Minimal — Ollama + Open WebUI"
            ;;
        2)  # Standard
            ENABLE_OLLAMA=true
            ENABLE_OPENWEBUI=true
            ENABLE_N8N=true
            ENABLE_FLOWISE=true
            ENABLE_LITELLM=true
            ENABLE_QDRANT=true
            STACK_NAME="standard"
            log "SUCCESS" "Stack: Standard"
            ;;
        3)  # Full
            ENABLE_OLLAMA=true
            ENABLE_OPENWEBUI=true
            ENABLE_N8N=true
            ENABLE_FLOWISE=true
            ENABLE_LITELLM=true
            ENABLE_QDRANT=true
            ENABLE_ANYTHINGLLM=true
            ENABLE_GRAFANA=true
            ENABLE_PROMETHEUS=true
            ENABLE_AUTHENTIK=true
            STACK_NAME="full"
            log "SUCCESS" "Stack: Full"
            ;;
        4)  # Custom — all off, user picks in next step
            STACK_NAME="custom"
            log "INFO" "Stack: Custom — configure individually below"
            ;;
    esac

    print_divider

    # ── Always offer fine-grained override ────────────────────────────────────
    if [ "${stack_choice}" != "4" ]; then
        echo -e "  ${DIM}Stack applied. Would you like to customise individual services?${NC}"
        echo ""
        read -p "  ➤ Customise service selection? [y/N]: " customise
        customise="${customise:-n}"
        [[ "${customise,,}" =~ ^y ]] && stack_choice=4
    fi

    if [ "${stack_choice}" = "4" ]; then
        echo ""
        echo -e "  ${BOLD}─── 🤖  AI / LLM ────────────────────────────────────────${NC}"
        ask_service "🦙" "Ollama"        "Local LLM engine"           "ENABLE_OLLAMA"        "$( [[ "${ENABLE_OLLAMA}" == "true" ]]        && echo y || echo n )"
        ask_service "🌐" "Open WebUI"    "Chat UI for Ollama"         "ENABLE_OPENWEBUI"     "$( [[ "${ENABLE_OPENWEBUI}" == "true" ]]     && echo y || echo n )"
        ask_service "🤖" "AnythingLLM"   "AI assistant & RAG"         "ENABLE_ANYTHINGLLM"   "$( [[ "${ENABLE_ANYTHINGLLM}" == "true" ]]   && echo y || echo n )"
        ask_service "🏗️ " "Dify"          "LLM app builder"            "ENABLE_DIFY"          "$( [[ "${ENABLE_DIFY}" == "true" ]]          && echo y || echo n )"
        ask_service "🔀" "LiteLLM"       "LLM proxy gateway"          "ENABLE_LITELLM"       "$( [[ "${ENABLE_LITELLM}" == "true" ]]       && echo y || echo n )"
        ask_service "🗄️ " "Qdrant"        "Vector database"            "ENABLE_QDRANT"        "$( [[ "${ENABLE_QDRANT}" == "true" ]]        && echo y || echo n )"

        echo ""
        echo -e "  ${BOLD}─── ⚡  Automation ──────────────────────────────────────${NC}"
        ask_service "🔄" "n8n"           "Workflow automation"         "ENABLE_N8N"           "$( [[ "${ENABLE_N8N}" == "true" ]]           && echo y || echo n )"
        ask_service "🌊" "Flowise"       "AI flow builder"             "ENABLE_FLOWISE"       "$( [[ "${ENABLE_FLOWISE}" == "true" ]]       && echo y || echo n )"

        echo ""
        echo -e "  ${BOLD}─── 📊  Observability ───────────────────────────────────${NC}"
        ask_service "📈" "Grafana"       "Metrics dashboard"           "ENABLE_GRAFANA"       "$( [[ "${ENABLE_GRAFANA}" == "true" ]]       && echo y || echo n )"
        ask_service "🔭" "Prometheus"    "Metrics collection"          "ENABLE_PROMETHEUS"    "$( [[ "${ENABLE_PROMETHEUS}" == "true" ]]    && echo y || echo n )"

        echo ""
        echo -e "  ${BOLD}─── 🔐  Security ────────────────────────────────────────${NC}"
        ask_service "🔑" "Authentik"     "SSO / identity provider"     "ENABLE_AUTHENTIK"     "$( [[ "${ENABLE_AUTHENTIK}" == "true" ]]     && echo y || echo n )"

        echo ""
        echo -e "  ${BOLD}─── 💬  Messaging ───────────────────────────────────────${NC}"
        ask_service "📱" "Signal API"    "Signal messaging bridge"     "ENABLE_SIGNAL"        "$( [[ "${ENABLE_SIGNAL}" == "true" ]]        && echo y || echo n )"
    fi
}

# ─── Vector DB Selection ───────────────────────────────────────────────────
select_vector_db() {
    print_step "6" "10" "Vector Database Selection"

    echo -e "  ${BOLD}🗄️  Choose Vector Database${NC}"
    echo ""
    echo -e "  ${CYAN}  1)${NC}  Qdrant     ${DIM}(recommended, high-performance)${NC}"
    echo -e "  ${CYAN}  2)${NC}  Chroma     ${DIM}(lightweight, embedded)${NC}"
    echo -e "  ${CYAN}  3)${NC}  Weaviate   ${DIM}(GraphQL API, advanced)${NC}"
    echo -e "  ${CYAN}  4)${NC}  None       ${DIM}(use external vector DB)${NC}"
    echo ""

    while true; do
        read -p "  ➤ Select vector database [1-4]: " choice
        choice="${choice:-1}"
        case "${choice}" in
            1|2|3|4) break ;;
            *) echo "  ❌ Enter 1, 2, 3 or 4" ;;
        esac
    done

    case "${choice}" in
        1) VECTOR_DB="qdrant" ;;
        2) VECTOR_DB="chroma" ;;
        3) VECTOR_DB="weaviate" ;;
        4) VECTOR_DB="none" ;;
    esac

    log "SUCCESS" "Vector database: ${VECTOR_DB}"
}

# ─── LLM Configuration ─────────────────────────────────────────────────────
collect_llm_config() {
    print_step "7" "10" "LLM Provider Configuration"

    echo -e "  ${BOLD}🔑  LLM Provider API Keys${NC}"
    echo -e "  ${DIM}Enter API keys for providers you want to use (leave blank to skip)${NC}"
    echo ""

    read -p "  ➤ OpenAI API key: " OPENAI_API_KEY
    read -p "  ➤ Google (Gemini) API key: " GOOGLE_API_KEY
    read -p "  ➤ Groq API key: " GROQ_API_KEY
    read -p "  ➤ OpenRouter API key: " OPENROUTER_API_KEY

    print_divider

    echo -e "  ${BOLD}🦙  Ollama Model Selection${NC}"
    echo -e "  ${DIM}Choose models appropriate for your available RAM${NC}"
    echo ""

    # Get system RAM for suggestion
    TOTAL_RAM_GB=$(awk '/MemTotal/{printf "%.0f", $2/1048576}' /proc/meminfo)
    
    echo -e "  ${DIM}System RAM: ${TOTAL_RAM_GB}GB${NC}"
    echo ""
    
    # Available models with RAM requirements
    echo -e "  ${BOLD}Available Models:${NC}"
    echo -e "  ${CYAN}  1)${NC} llama3.2:1b      ${DIM}~1GB RAM${NC}"
    echo -e "  ${CYAN}  2)${NC} llama3.2:3b      ${DIM}~4GB RAM${NC}"
    echo -e "  ${CYAN}  3)${NC} qwen2.5:7b       ${DIM}~8GB RAM${NC}"
    echo -e "  ${CYAN}  4)${NC} llama3.1:8b      ${DIM}~10GB RAM${NC}"
    echo -e "  ${CYAN}  5)${NC} llama3.1:70b     ${DIM}~50GB RAM${NC}"
    echo -e "  ${CYAN}  6)${NC} Custom model     ${DIM}Enter model name manually${NC}"
    echo ""
    
    echo -e "  ${DIM}Select models to download (comma-separated, e.g. 1,2,3)${NC}"
    read -p "  ➤ Models to install: " model_selection
    
    # Parse model selection
    OLLAMA_MODELS=""
    if [ -n "${model_selection}" ]; then
        for num in $(echo "${model_selection}" | tr ',' ' '); do
            case "${num}" in
                1) OLLAMA_MODELS="${OLLAMA_MODELS}llama3.2:1b " ;;
                2) OLLAMA_MODELS="${OLLAMA_MODELS}llama3.2:3b " ;;
                3) OLLAMA_MODELS="${OLLAMA_MODELS}qwen2.5:7b " ;;
                4) OLLAMA_MODELS="${OLLAMA_MODELS}llama3.1:8b " ;;
                5) OLLAMA_MODELS="${OLLAMA_MODELS}llama3.1:70b " ;;
                6) 
                    read -p "  ➤ Enter custom model name: " custom_model
                    [ -n "${custom_model}" ] && OLLAMA_MODELS="${OLLAMA_MODELS}${custom_model} "
                    ;;
            esac
        done
    fi
    
    # Set default model (first selected or suggested)
    if [ -n "${OLLAMA_MODELS}" ]; then
        OLLAMA_DEFAULT_MODEL=$(echo "${OLLAMA_MODELS}" | awk '{print $1}')
    else
        local suggested_model
        if [ "${TOTAL_RAM_GB}" -lt 8 ]; then
            suggested_model="llama3.2:1b"
        elif [ "${TOTAL_RAM_GB}" -lt 16 ]; then
            suggested_model="llama3.2:3b"
        elif [ "${TOTAL_RAM_GB}" -lt 32 ]; then
            suggested_model="qwen2.5:7b"
        else
            suggested_model="llama3.1:8b"
        fi
        OLLAMA_MODELS="${suggested_model}"
        OLLAMA_DEFAULT_MODEL="${suggested_model}"
    fi

    echo ""
    log "SUCCESS" "Models to download: ${OLLAMA_MODELS}"
    log "SUCCESS" "Default model: ${OLLAMA_DEFAULT_MODEL}"
}

# ─── Port Configuration ────────────────────────────────────────────────────
collect_ports() {
    print_step "8" "10" "Port Configuration"

    echo -e "  ${BOLD}🔌  Service Ports${NC}"
    echo -e "  ${DIM}Configure ports for each enabled service${NC}"
    echo ""

    # Default ports
    local d_n8n="5678"
    local d_flowise="3000"
    local d_openwebui="8080"
    local d_anythingllm="3001"
    local d_litellm="4000"
    local d_grafana="3000"
    local d_prometheus="9090"
    local d_ollama="11434"
    local d_qdrant="6333"
    local d_signal="8080"

    read_port() {
        local service="${1}" default="${2}" varname="${3}"
        while true; do
            read -p "  ➤ ${service} port [${default}]: " input
            if [ -z "${input}" ]; then
                eval "${varname}=${default}"
                break
            elif [[ "${input}" =~ ^[0-9]+$ ]] && [ "${input}" -ge 1024 ] && [ "${input}" -le 65535 ]; then
                if ss -tuln 2>/dev/null | grep -q ":${input} "; then
                    log "WARN" "Port ${input} is already in use — choose another"
                else
                    eval "${varname}=${input}"
                    break
                fi
            else
                echo "  ❌ Enter a valid port (1024–65535)"
            fi
        done
    }

    [ "${ENABLE_N8N}" = "true" ]         && read_port "n8n"         "${d_n8n}"         "N8N_PORT"
    [ "${ENABLE_FLOWISE}" = "true" ]     && read_port "Flowise"     "${d_flowise}"     "FLOWISE_PORT"
    [ "${ENABLE_OPENWEBUI}" = "true" ]   && read_port "Open WebUI"  "${d_openwebui}"   "OPENWEBUI_PORT"
    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && read_port "AnythingLLM" "${d_anythingllm}" "ANYTHINGLLM_PORT"
    [ "${ENABLE_LITELLM}" = "true" ]     && read_port "LiteLLM"     "${d_litellm}"     "LITELLM_PORT"
    [ "${ENABLE_GRAFANA}" = "true" ]     && read_port "Grafana"     "${d_grafana}"     "GRAFANA_PORT"
    [ "${ENABLE_PROMETHEUS}" = "true" ]  && read_port "Prometheus"  "${d_prometheus}"  "PROMETHEUS_PORT"
    [ "${ENABLE_OLLAMA}" = "true" ]      && read_port "Ollama"      "${d_ollama}"      "OLLAMA_PORT"
    [ "${ENABLE_QDRANT}" = "true" ]      && read_port "Qdrant"      "${d_qdrant}"      "QDRANT_PORT"
    [ "${ENABLE_SIGNAL}" = "true" ]      && read_port "Signal API"  "${d_signal}"      "SIGNAL_PORT"

    # Set safe defaults for disabled services
    N8N_PORT="${N8N_PORT:-${d_n8n}}"
    FLOWISE_PORT="${FLOWISE_PORT:-${d_flowise}}"
    OPENWEBUI_PORT="${OPENWEBUI_PORT:-${d_openwebui}}"
    ANYTHINGLLM_PORT="${ANYTHINGLLM_PORT:-${d_anythingllm}}"
    LITELLM_PORT="${LITELLM_PORT:-${d_litellm}}"
    GRAFANA_PORT="${GRAFANA_PORT:-${d_grafana}}"
    PROMETHEUS_PORT="${PROMETHEUS_PORT:-${d_prometheus}}"
    OLLAMA_PORT="${OLLAMA_PORT:-${d_ollama}}"
    QDRANT_PORT="${QDRANT_PORT:-${d_qdrant}}"
    SIGNAL_PORT="${SIGNAL_PORT:-${d_signal}}"

    log "SUCCESS" "Ports configured"
}

# ─── Generate secrets (preserve on re-run) ───────────────────────────────────
generate_secrets() {
    print_step "9" "10" "Generating Secrets"

    load_existing_secret() {
        local key="${1}" default="${2}"
        if [ -f "${ENV_FILE}" ]; then
            local val
            val=$(grep "^${key}=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2- || echo "")
            [ -n "${val}" ] && echo "${val}" && return
        fi
        echo "${default}"
    }

    DB_PASSWORD=$(load_existing_secret    "DB_PASSWORD"                "$(openssl rand -hex 32)")
    REDIS_PASSWORD=$(load_existing_secret "REDIS_PASSWORD"             "$(openssl rand -hex 32)")
    N8N_ENCRYPTION_KEY=$(load_existing_secret "N8N_ENCRYPTION_KEY"     "$(openssl rand -hex 32)")
    FLOWISE_SECRET_KEY=$(load_existing_secret "FLOWISE_SECRET_KEY"     "$(openssl rand -hex 32)")
    LITELLM_MASTER_KEY=$(load_existing_secret "LITELLM_MASTER_KEY"     "sk-$(openssl rand -hex 32)")
    ANYTHINGLLM_JWT_SECRET=$(load_existing_secret "ANYTHINGLLM_JWT_SECRET" "$(openssl rand -hex 32)")
    ANYTHINGLLM_AUTH_TOKEN=$(load_existing_secret "ANYTHINGLLM_AUTH_TOKEN" "$(openssl rand -hex 16)")
    GRAFANA_PASSWORD=$(load_existing_secret "GRAFANA_PASSWORD"          "$(openssl rand -hex 16)")
    AUTHENTIK_SECRET_KEY=$(load_existing_secret "AUTHENTIK_SECRET_KEY" "$(openssl rand -hex 32)")
    QDRANT_API_KEY=$(load_existing_secret   "QDRANT_API_KEY"            "$(openssl rand -hex 32)")
    N8N_API_KEY=$(load_existing_secret      "N8N_API_KEY"               "n8n-$(openssl rand -hex 16)")
    N8N_PASSWORD=$(load_existing_secret     "N8N_PASSWORD"              "$(openssl rand -hex 12)")
    FLOWISE_PASSWORD=$(load_existing_secret "FLOWISE_PASSWORD"          "$(openssl rand -hex 12)")
    AUTHENTIK_BOOTSTRAP_PASSWORD=$(load_existing_secret "AUTHENTIK_BOOTSTRAP_PASSWORD" "$(openssl rand -hex 12)")

    log "SUCCESS" "Secrets ready (preserved from prior run where available)"
}

# ─── Write .env ───────────────────────────────────────────────────────────────
write_env() {
    mkdir -p "${DATA_ROOT}"
    chmod 700 "${DATA_ROOT}"

    cat > "${ENV_FILE}" << EOF
# ════════════════════════════════════════════════════════════════════════════
# AI Platform — Environment Configuration
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# ════════════════════════════════════════════════════════════════════════════

# ─── Platform Identity ────────────────────────────────────────────────────────
TENANT_ID=${TENANT_ID}
DOMAIN=${DOMAIN}
ADMIN_EMAIL=${ADMIN_EMAIL}
DATA_ROOT=${DATA_ROOT}
SSL_TYPE=${SSL_TYPE}

# ─── Hardware ─────────────────────────────────────────────────────────────────
GPU_TYPE=${GPU_TYPE}
GPU_COUNT=${GPU_COUNT:-0}
OLLAMA_GPU_LAYERS=${GPU_LAYERS:-auto}
CPU_CORES=${CPU_CORES:-$(nproc)}
TOTAL_RAM_GB=${TOTAL_RAM_GB:-$(awk '/MemTotal/{printf "%.0f", $2/1048576}' /proc/meminfo)}

# ─── Ollama ───────────────────────────────────────────────────────────────────
OLLAMA_DEFAULT_MODEL=${OLLAMA_DEFAULT_MODEL:-}
OLLAMA_MODELS="${OLLAMA_MODELS}"

# ─── Vector Database ──────────────────────────────────────────────────────────
VECTOR_DB=${VECTOR_DB:-qdrant}
VECTOR_DB_HOST=${VECTOR_DB_HOST:-qdrant}
VECTOR_DB_PORT=${VECTOR_DB_PORT:-6333}
VECTOR_DB_URL=${VECTOR_DB_URL:-http://qdrant:6333}

# ─── LLM Providers ────────────────────────────────────────────────────────────
LLM_PROVIDERS=${LLM_PROVIDERS:-local}
OPENAI_API_KEY=${OPENAI_API_KEY:-}
GOOGLE_API_KEY=${GOOGLE_API_KEY:-}
GROQ_API_KEY=${GROQ_API_KEY:-}
OPENROUTER_API_KEY=${OPENROUTER_API_KEY:-}

# ─── Database ─────────────────────────────────────────────────────────────────
DB_USER=platform
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=platform

# ─── Redis ────────────────────────────────────────────────────────────────────
REDIS_PASSWORD=${REDIS_PASSWORD}

# ─── n8n ──────────────────────────────────────────────────────────────────────
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_API_KEY=${N8N_API_KEY}
N8N_USER=admin@${DOMAIN}
N8N_PASSWORD=${N8N_PASSWORD}

# ─── Flowise ──────────────────────────────────────────────────────────────────
FLOWISE_SECRET_KEY=${FLOWISE_SECRET_KEY}
FLOWISE_USER=admin
FLOWISE_PASSWORD=${FLOWISE_PASSWORD}

# ─── LiteLLM ──────────────────────────────────────────────────────────────────
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}

# ─── AnythingLLM ──────────────────────────────────────────────────────────────
ANYTHINGLLM_JWT_SECRET=${ANYTHINGLLM_JWT_SECRET}
ANYTHINGLLM_AUTH_TOKEN=${ANYTHINGLLM_AUTH_TOKEN}

# ─── Grafana ──────────────────────────────────────────────────────────────────
GRAFANA_USER=admin
GRAFANA_PASSWORD=${GRAFANA_PASSWORD}

# ─── Authentik ────────────────────────────────────────────────────────────────
AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}
AUTHENTIK_BOOTSTRAP_EMAIL=${ADMIN_EMAIL}
AUTHENTIK_BOOTSTRAP_PASSWORD=${AUTHENTIK_BOOTSTRAP_PASSWORD}

# ─── Qdrant ───────────────────────────────────────────────────────────────────
QDRANT_API_KEY=${QDRANT_API_KEY}

# ─── Ports ────────────────────────────────────────────────────────────────────
CADDY_HTTP_PORT=80
CADDY_HTTPS_PORT=443
N8N_PORT=${N8N_PORT}
FLOWISE_PORT=${FLOWISE_PORT}
OPENWEBUI_PORT=${OPENWEBUI_PORT}
ANYTHINGLLM_PORT=${ANYTHINGLLM_PORT}
LITELLM_PORT=${LITELLM_PORT}
GRAFANA_PORT=${GRAFANA_PORT}
PROMETHEUS_PORT=${PROMETHEUS_PORT}
OLLAMA_PORT=${OLLAMA_PORT}
QDRANT_PORT=${QDRANT_PORT}
SIGNAL_PORT=${SIGNAL_PORT}

# ─── Service Flags ────────────────────────────────────────────────────────────
ENABLE_OLLAMA=${ENABLE_OLLAMA}
ENABLE_OPENWEBUI=${ENABLE_OPENWEBUI}
ENABLE_ANYTHINGLLM=${ENABLE_ANYTHINGLLM}
ENABLE_DIFY=${ENABLE_DIFY}
ENABLE_N8N=${ENABLE_N8N}
ENABLE_FLOWISE=${ENABLE_FLOWISE}
ENABLE_LITELLM=${ENABLE_LITELLM}
ENABLE_QDRANT=${ENABLE_QDRANT}
ENABLE_GRAFANA=${ENABLE_GRAFANA}
ENABLE_PROMETHEUS=${ENABLE_PROMETHEUS}
ENABLE_AUTHENTIK=${ENABLE_AUTHENTIK}
ENABLE_SIGNAL=${ENABLE_SIGNAL}
EOF

    chmod 600 "${ENV_FILE}"
    log "SUCCESS" "Configuration written to ${ENV_FILE}"
}

# ─── Create directory structure ──────────────────────────────────────────────
create_directories() {
    local dirs=(
        "${DATA_ROOT}/compose"
        "${DATA_ROOT}/caddy"
        "${DATA_ROOT}/caddy/config"
        "${DATA_ROOT}/postgres"
        "${DATA_ROOT}/redis"
        "${DATA_ROOT}/ollama"
        "${DATA_ROOT}/n8n"
        "${DATA_ROOT}/flowise"
        "${DATA_ROOT}/anythingllm"
        "${DATA_ROOT}/qdrant"
        "${DATA_ROOT}/litellm"
        "${DATA_ROOT}/grafana"
        "${DATA_ROOT}/prometheus"
        "${DATA_ROOT}/authentik/media"
        "${DATA_ROOT}/authentik/certs"
        "${DATA_ROOT}/openwebui"
        "${DATA_ROOT}/signal"
        "${DATA_ROOT}/backups"
        "${DATA_ROOT}/logs"
    )

    local total="${#dirs[@]}"
    local idx=0
    for dir in "${dirs[@]}"; do
        idx=$((idx + 1))
        mkdir -p "${dir}"
        printf "  ${DIM}[%2d/%d]${NC} Created %s\n" "${idx}" "${total}" "${dir}"
    done

    log "SUCCESS" "Directory structure ready"
}

# ─── Write Caddyfile ─────────────────────────────────────────────────────────
write_caddyfile() {
    # shellcheck source=/dev/null
    source "${ENV_FILE}"

    cat > "${CADDY_DIR}/Caddyfile" << EOF
# AI Platform Caddyfile
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

{
    email ${ADMIN_EMAIL}
    acme_ca https://acme-v02.api.letsencrypt.org/directory
    acme_ca_root /etc/ssl/certs/ca-certificates.crt
}

$([ "${ENABLE_N8N}" = "true" ] && cat << 'BLOCK'
n8n.${DOMAIN} {
    reverse_proxy n8n:5678 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
BLOCK
)
$([ "${ENABLE_FLOWISE}" = "true" ] && cat << 'BLOCK'
flowise.${DOMAIN} {
    reverse_proxy flowise:3000 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
BLOCK
)
$([ "${ENABLE_OPENWEBUI}" = "true" ] && cat << 'BLOCK'
chat.${DOMAIN} {
    reverse_proxy openwebui:8080 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
BLOCK
)
$([ "${ENABLE_ANYTHINGLLM}" = "true" ] && cat << 'BLOCK'
anythingllm.${DOMAIN} {
    reverse_proxy anythingllm:3001 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
BLOCK
)
$([ "${ENABLE_LITELLM}" = "true" ] && cat << 'BLOCK'
litellm.${DOMAIN} {
    reverse_proxy litellm:4000 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
BLOCK
)
$([ "${ENABLE_GRAFANA}" = "true" ] && cat << 'BLOCK'
grafana.${DOMAIN} {
    reverse_proxy grafana:3000 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
BLOCK
)
$([ "${ENABLE_AUTHENTIK}" = "true" ] && cat << 'BLOCK'
auth.${DOMAIN} {
    reverse_proxy authentik-server:9000 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}
    }
}
BLOCK
)
EOF

    # Replace placeholder with actual domain
    sed -i "s/DOMAIN/${DOMAIN}/g" "${CADDY_DIR}/Caddyfile"
    chmod 644 "${CADDY_DIR}/Caddyfile"
    log "SUCCESS" "Caddyfile written"
}

# ─── Pre-commit summary ───────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}                   📋  Configuration Summary                  ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    printf "  ${BOLD}%-22s${NC} %s\n" "Data root:"    "${DATA_ROOT}"
    printf "  ${BOLD}%-22s${NC} %s\n" "Domain:"       "${DOMAIN}"
    printf "  ${BOLD}%-22s${NC} %s\n" "Tenant ID:"    "${TENANT_ID}"
    printf "  ${BOLD}%-22s${NC} %s\n" "Admin email:"  "${ADMIN_EMAIL}"
    printf "  ${BOLD}%-22s${NC} %s\n" "SSL:"          "${SSL_TYPE}"
    printf "  ${BOLD}%-22s${NC} %s\n" "GPU:"          "${GPU_TYPE} (layers: ${GPU_LAYERS:-auto})"
    printf "  ${BOLD}%-22s${NC} %s\n" "Vector DB:"    "${VECTOR_DB:-none}"
    printf "  ${BOLD}%-22s${NC} %s\n" "LLM providers:" "${LLM_PROVIDERS:-local}"
    echo ""
    echo -e "  ${BOLD}Enabled services:${NC}"
    [ "${ENABLE_OLLAMA}" = "true" ]      && echo -e "    ${GREEN}✓${NC}  Ollama       (models: ${OLLAMA_MODELS:-auto})"
    [ "${ENABLE_OPENWEBUI}" = "true" ]   && echo -e "    ${GREEN}✓${NC}  Open WebUI   :${OPENWEBUI_PORT}"
    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && echo -e "    ${GREEN}✓${NC}  AnythingLLM  :${ANYTHINGLLM_PORT}"
    [ "${ENABLE_DIFY}" = "true" ]        && echo -e "    ${GREEN}✓${NC}  Dify"
    [ "${ENABLE_N8N}" = "true" ]         && echo -e "    ${GREEN}✓${NC}  n8n          :${N8N_PORT}"
    [ "${ENABLE_FLOWISE}" = "true" ]     && echo -e "    ${GREEN}✓${NC}  Flowise      :${FLOWISE_PORT}"
    [ "${ENABLE_LITELLM}" = "true" ]     && echo -e "    ${GREEN}✓${NC}  LiteLLM      :${LITELLM_PORT}"
    [ "${ENABLE_QDRANT}" = "true" ]      && echo -e "    ${GREEN}✓${NC}  Qdrant       :${QDRANT_PORT}"
    [ "${ENABLE_GRAFANA}" = "true" ]     && echo -e "    ${GREEN}✓${NC}  Grafana      :${GRAFANA_PORT}"
      [ "${ENABLE_PROMETHEUS}" = "true" ]  && echo -e "    ${GREEN}✓${NC}  Prometheus   :${PROMETHEUS_PORT}"
    [ "${ENABLE_AUTHENTIK}" = "true" ]   && echo -e "    ${GREEN}✓${NC}  Authentik"
    [ "${ENABLE_SIGNAL}" = "true" ]      && echo -e "    ${GREEN}✓${NC}  Signal API   :${SIGNAL_PORT}"
    echo ""

    print_divider

    echo -e "  ${YELLOW}⚠️   Review the above before confirming.${NC}"
    echo -e "  ${DIM}This will write ${ENV_FILE} and create directory structure.${NC}"
    echo ""
    read -p "  ➤ Confirm and write configuration? [Y/n]: " confirm
    confirm="${confirm:-y}"
    if [[ ! "${confirm,,}" =~ ^y ]]; then
        log "INFO" "Aborted — no changes made"
        exit 0
    fi
}

# ─── Final launch prompt ──────────────────────────────────────────────────────
offer_next_step() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}                   ✅  Setup Complete                         ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Configuration saved to: ${BOLD}${ENV_FILE}${NC}"
    echo ""
    echo -e "  ${BOLD}Next steps:${NC}"
    echo ""
    echo -e "    ${CYAN}2)${NC}  Deploy services"
    echo -e "        ${DIM}sudo bash scripts/2-deploy-services.sh${NC}"
    echo ""
    echo -e "    ${CYAN}3)${NC}  Configure services (post-deploy API setup)"
    echo -e "        ${DIM}sudo bash scripts/3-configure-services.sh${NC}"
    echo ""
    read -p "  ➤ Run script 2 (deploy services) now? [Y/n]: " run_next
    run_next="${run_next:-y}"
    if [[ "${run_next,,}" =~ ^y ]]; then
        if [ -f "${SCRIPTS_DIR}/2-deploy-services.sh" ]; then
            bash "${SCRIPTS_DIR}/2-deploy-services.sh"
        else
            log "ERROR" "2-deploy-services.sh not found at ${SCRIPTS_DIR}"
            exit 1
        fi
    else
        echo ""
        log "INFO" "Run script 2 when ready:"
        echo ""
        echo "    sudo bash scripts/2-deploy-services.sh"
        echo ""
    fi
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    print_header
    check_root
    check_prerequisites      # Step 1
    collect_identity         # Step 2
    detect_and_mount_ebs     # Step 3 - NEW: EBS detection and mounting
    select_data_volume       # Step 4
    detect_gpu               # Step 5
    select_stack             # Step 6
    select_vector_db         # Step 7
    collect_llm_config       # Step 8
    collect_ports            # Step 9
    generate_secrets         # Step 10
    print_summary
    write_env
    create_directories
    write_caddyfile
    offer_next_step
}

main "$@"
