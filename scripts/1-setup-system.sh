#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ============================================================
# Script 1: System Setup & Configuration Collector
# Version: 99.0.0
# Commit: fix menus display before input, uuidgen->uuid-runtime,
#         port health check, full service/model/provider selection
# ============================================================

LOGFILE="/var/log/ai-platform-setup.log"
CONFIG_DIR="/opt/ai-platform"
ENV_FILE="${CONFIG_DIR}/.env"
LITELLM_CONFIG="${CONFIG_DIR}/litellm-config.yaml"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[OK]${NC} $1" | tee -a "$LOGFILE"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOGFILE"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOGFILE"; }
log_phase() {
    echo "" | tee -a "$LOGFILE"
    echo -e "${CYAN}▸ $1${NC}" | tee -a "$LOGFILE"
    echo "═══════════════════════════════════════" | tee -a "$LOGFILE"
}

gen_password() {
    local len="${1:-32}"
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$len" 2>/dev/null || \
    openssl rand -hex "$((len / 2))" 2>/dev/null || \
    date +%s%N | sha256sum | head -c "$len"
}

gen_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    elif [ -f /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    else
        gen_password 32 | sed 's/\(........\)\(....\)\(....\)\(....\)\(............\)/\1-\2-\3-\4-\5/'
    fi
}

# ============================================================
# PHASE 0: Pre-flight checks
# ============================================================
preflight_checks() {
    log_phase "PHASE 0: Pre-flight Checks"

    if [ "$(id -u)" -ne 0 ]; then
        log_error "Must run as root (sudo)"
        exit 1
    fi

    if [ -f "$ENV_FILE" ]; then
        echo -e "${YELLOW}Existing config found at ${ENV_FILE}${NC}"
        echo "    1) Overwrite (fresh setup)"
        echo "    2) Load and modify"
        echo "    3) Abort"
        echo ""
        read -rp "  Choose [1-3]: " env_choice
        case "$env_choice" in
            1) log_info "Starting fresh setup" ;;
            2) log_info "Loading existing config"; source "$ENV_FILE" ;;
            3) log_info "Aborted by user"; exit 0 ;;
            *) log_warn "Invalid choice, starting fresh" ;;
        esac
    fi

    mkdir -p "$CONFIG_DIR"
    mkdir -p "$(dirname "$LOGFILE")"
    touch "$LOGFILE"
    log_info "Pre-flight checks passed"
}

# ============================================================
# PHASE 1: Port health check
# ============================================================
declare -A DEFAULT_PORTS
DEFAULT_PORTS=(
    [ollama]=11434
    [openwebui]=3000
    [n8n]=5678
    [supabase_studio]=3001
    [supabase_api]=8000
    [supabase_db]=5432
    [supabase_auth]=9999
    [supabase_realtime]=4000
    [flowise]=3003
    [langfuse]=3004
    [dify]=3005
    [litellm]=4000
    [litellm_alt]=4001
    [qdrant]=6333
    [qdrant_grpc]=6334
    [chromadb]=8100
    [redis]=6379
    [caddy_http]=80
    [caddy_https]=443
    [crawl4ai]=4444
    [firecrawl]=3006
    [whisper]=9000
    [kokoro]=8880
    [searxng]=8888
    [neo4j_http]=7474
    [neo4j_bolt]=7687
    [docling]=5001
    [mongo]=27017
    [signalapi]=8080
    [minio]=9002
    [minio_console]=9003
    [grafana]=3007
    [prometheus]=9090
    [libretranslate]=5555
    [tailscale]=41641
)

port_health_check() {
    log_phase "PHASE 1: Port Health Check"
    echo "[INFO] Scanning for port conflicts before setup..."

    local conflicts=0
    local conflict_list=""

    for svc in $(echo "${!DEFAULT_PORTS[@]}" | tr ' ' '\n' | sort); do
        local port="${DEFAULT_PORTS[$svc]}"
        local in_use=""
        in_use=$(ss -tlnp 2>/dev/null | grep ":${port} " || true)
        if [ -n "$in_use" ]; then
            local proc=""
            proc=$(echo "$in_use" | grep -oP 'users:\(\(.*?\)\)' || echo "unknown")
            log_warn "Port ${port} (${svc}) is IN USE by: ${proc}"
            conflicts=$((conflicts + 1))
            conflict_list="${conflict_list}  ${port} -> ${svc}\n"
        fi
    done

    if [ "$conflicts" -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}Found ${conflicts} port conflict(s):${NC}"
        echo -e "$conflict_list"
        echo ""
        echo "    1) Continue anyway (will reassign ports later)"
        echo "    2) Stop conflicting services and continue"
        echo "    3) Abort"
        echo ""
        read -rp "  Choose [1-3]: " port_choice
        case "$port_choice" in
            1) log_info "Continuing with conflicts — will handle during port assignment" ;;
            2)
                log_info "Stopping conflicting services..."
                for svc in $(echo "${!DEFAULT_PORTS[@]}" | tr ' ' '\n'); do
                    local port="${DEFAULT_PORTS[$svc]}"
                    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
                        fuser -k "${port}/tcp" 2>/dev/null || true
                        log_info "Killed process on port ${port} (${svc})"
                    fi
                done
                sleep 2
                log_info "Services stopped"
                ;;
            3) log_info "Aborted by user"; exit 0 ;;
            *) log_warn "Invalid choice, continuing" ;;
        esac
    else
        log_info "No port conflicts detected — all clear"
    fi
}

# ============================================================
# PHASE 2: System packages
# ============================================================
install_system_packages() {
    log_phase "PHASE 2: System Package Installation"

    export DEBIAN_FRONTEND=noninteractive

    log_info "Updating package lists..."
    apt-get update -qq

    local packages=(
        curl wget git jq yq unzip gnupg2 lsb-release
        ca-certificates apt-transport-https
        software-properties-common
        htop btop iotop ncdu tmux
        uuid-runtime openssl
        python3 python3-pip python3-venv
        net-tools dnsutils
        fail2ban ufw
        cron logrotate
    )

    log_info "Installing system packages..."
    for pkg in "${packages[@]}"; do
        if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            log_info "${pkg} already installed"
        else
            if apt-get install -y -qq "$pkg" 2>/dev/null; then
                log_info "${pkg} installed"
            else
                log_warn "${pkg} failed to install — skipping"
            fi
        fi
    done

    log_info "System packages phase complete"
}

# ============================================================
# PHASE 3: Docker installation
# ============================================================
install_docker() {
    log_phase "PHASE 3: Docker Installation"

    if command -v docker >/dev/null 2>&1; then
        local dv=""
        dv=$(docker --version 2>/dev/null || echo "unknown")
        log_info "Docker already installed: ${dv}"
    else
        log_info "Installing Docker..."
        curl -fsSL https://get.docker.com | bash
        log_info "Docker installed"
    fi

    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        local dcv=""
        dcv=$(docker compose version 2>/dev/null || echo "unknown")
        log_info "Docker Compose available: ${dcv}"
    else
        log_info "Installing Docker Compose plugin..."
        apt-get install -y -qq docker-compose-plugin 2>/dev/null || true
    fi

    systemctl enable docker
    systemctl start docker

    local real_user=""
    real_user="${SUDO_USER:-$USER}"
    if [ -n "$real_user" ] && [ "$real_user" != "root" ]; then
        usermod -aG docker "$real_user" 2>/dev/null || true
        log_info "Added ${real_user} to docker group"
    fi

    log_info "Docker phase complete"
}

# ============================================================
# PHASE 4: Domain & Infrastructure
# ============================================================
DOMAIN=""
REVERSE_PROXY=""
VECTOR_DB=""

collect_domain() {
    log_phase "PHASE 4: Domain & Infrastructure"

    read -rp "  Enter your domain (e.g., ai.example.com): " DOMAIN
    if [ -z "$DOMAIN" ]; then
        DOMAIN="localhost"
        log_warn "No domain entered — using localhost"
    else
        log_info "Domain: ${DOMAIN}"
    fi
}

collect_reverse_proxy() {
    echo ""
    echo "  Select reverse proxy:"
    echo "    1) caddy (recommended — auto-SSL)"
    echo "    2) nginx"
    echo "    3) traefik"
    echo "    4) none"
    echo ""
    read -rp "  Choose [1-4]: " proxy_choice

    case "$proxy_choice" in
        1) REVERSE_PROXY="caddy" ;;
        2) REVERSE_PROXY="nginx" ;;
        3) REVERSE_PROXY="traefik" ;;
        4) REVERSE_PROXY="none" ;;
        *) REVERSE_PROXY="caddy"; log_warn "Invalid choice — defaulting to caddy" ;;
    esac
    log_info "Reverse proxy: ${REVERSE_PROXY}"
}

collect_vector_db() {
    echo ""
    echo "  Select vector database:"
    echo "    1) qdrant (recommended)"
    echo "    2) chromadb"
    echo "    3) both"
    echo "    4) none"
    echo ""
    read -rp "  Choose [1-4]: " vdb_choice

    case "$vdb_choice" in
        1) VECTOR_DB="qdrant" ;;
        2) VECTOR_DB="chromadb" ;;
        3) VECTOR_DB="both" ;;
        4) VECTOR_DB="none" ;;
        *) VECTOR_DB="qdrant"; log_warn "Invalid choice — defaulting to qdrant" ;;
    esac
    log_info "Vector DB: ${VECTOR_DB}"
}

# ============================================================
# PHASE 5: Service Selection & Port Assignment
# ============================================================

# Service registry: name|default_port|description|category
SERVICE_REGISTRY=(
    "ollama|11434|Local LLM inference engine|core"
    "open-webui|3000|Chat UI for LLMs|core"
    "n8n|5678|Workflow automation|core"
    "litellm|4001|LLM proxy/router|core"
    "supabase|5432|Postgres + Auth + API|core"
    "flowise|3003|Visual LLM chain builder|agents"
    "langfuse|3004|LLM observability|agents"
    "dify|3005|LLM app builder|agents"
    "redis|6379|Cache and queue|infra"
    "crawl4ai|4444|AI web crawler|tools"
    "firecrawl|3006|Web scraper for LLMs|tools"
    "whisper|9000|Speech-to-text|tools"
    "kokoro-tts|8880|Text-to-speech|tools"
    "searxng|8888|Meta search engine|tools"
    "neo4j|7474|Graph database|tools"
    "docling|5001|Document processing|tools"
    "mongodb|27017|Document database|infra"
    "signal-api|8080|Signal messaging API|extras"
    "minio|9002|S3-compatible storage|infra"
    "grafana|3007|Monitoring dashboard|monitoring"
    "libretranslate|5555|Translation API|tools"
)

declare -A SELECTED_SERVICES
declare -A SERVICE_PORTS

collect_services() {
    log_phase "PHASE 5: Service Selection"

    echo ""
    echo "  Available services to deploy:"
    echo "  ─────────────────────────────────────"
    echo ""

    local idx=1
    local svc_names=()
    local svc_ports=()
    local svc_descs=()
    local svc_cats=()

    for entry in "${SERVICE_REGISTRY[@]}"; do
        local sname=""
        local sport=""
        local sdesc=""
        local scat=""
        sname=$(echo "$entry" | cut -d'|' -f1)
        sport=$(echo "$entry" | cut -d'|' -f2)
        sdesc=$(echo "$entry" | cut -d'|' -f3)
        scat=$(echo "$entry" | cut -d'|' -f4)

        svc_names+=("$sname")
        svc_ports+=("$sport")
        svc_descs+=("$sdesc")
        svc_cats+=("$scat")

        printf "    %2d) %-18s :%s  [%s]  %s\n" "$idx" "$sname" "$sport" "$scat" "$sdesc"
        idx=$((idx + 1))
    done

    echo ""
    echo "  Enter service numbers separated by spaces, commas, or ranges"
    echo "  Examples:  1 2 3 5    or    1-6,8,10-12    or    all"
    echo ""
    read -rp "  Select services: " svc_input

    if [ -z "$svc_input" ]; then
        svc_input="all"
        log_warn "No selection — defaulting to ALL services"
    fi

    # Parse selection
    local selected_indices=()

    if [ "$svc_input" = "all" ] || [ "$svc_input" = "ALL" ]; then
        local i=0
        while [ "$i" -lt "${#svc_names[@]}" ]; do
            selected_indices+=("$i")
            i=$((i + 1))
        done
    else
        # Replace commas with spaces
        svc_input=$(echo "$svc_input" | tr ',' ' ')
        for token in $svc_input; do
            if echo "$token" | grep -q '-'; then
                local range_start=""
                local range_end=""
                range_start=$(echo "$token" | cut -d'-' -f1)
                range_end=$(echo "$token" | cut -d'-' -f2)
                local r="$range_start"
                while [ "$r" -le "$range_end" ]; do
                    selected_indices+=("$((r - 1))")
                    r=$((r + 1))
                done
            else
                selected_indices+=("$((token - 1))")
            fi
        done
    fi

    echo ""
    echo "  Selected services:"
    for si in "${selected_indices[@]}"; do
        if [ "$si" -ge 0 ] && [ "$si" -lt "${#svc_names[@]}" ]; then
            local sn="${svc_names[$si]}"
            local sp="${svc_ports[$si]}"
            SELECTED_SERVICES["$sn"]=1
            SERVICE_PORTS["$sn"]="$sp"
            echo "    ✓ ${sn} (port ${sp})"
        fi
    done

    local total="${#SELECTED_SERVICES[@]}"
    log_info "Selected ${total} services"
}

# ============================================================
# PHASE 5b: Port Assignment & Conflict Resolution
# ============================================================
assign_ports() {
    log_phase "PHASE 5b: Port Assignment"

    echo ""
    echo "  Review and customize port assignments:"
    echo "  (Press Enter to keep default, or type new port)"
    echo ""

    for svc in $(echo "${!SELECTED_SERVICES[@]}" | tr ' ' '\n' | sort); do
        local current_port="${SERVICE_PORTS[$svc]}"
        local conflict=""
        conflict=$(ss -tlnp 2>/dev/null | grep ":${current_port} " || true)

        local status=""
        if [ -n "$conflict" ]; then
            status="${RED}IN USE${NC}"
        else
            status="${GREEN}available${NC}"
        fi

        echo -e "    ${svc} — port ${current_port} [${status}]"
        read -rp "      New port (Enter=keep ${current_port}): " new_port

        if [ -n "$new_port" ]; then
            SERVICE_PORTS["$svc"]="$new_port"
            log_info "${svc} port changed to ${new_port}"
        fi
    done

    log_info "Port assignment complete"
}

# ============================================================
# PHASE 6: LLM Provider & API Key Collection
# ============================================================

declare -A LLM_PROVIDERS
declare -a SELECTED_MODELS
GOOGLE_PROJECT_ID=""
GOOGLE_AUTH_METHOD=""
GOOGLE_JSON_PATH=""

collect_llm_providers() {
    log_phase "PHASE 6: LLM Providers & API Keys"

    echo ""
    echo "  Select external LLM providers (enter numbers, e.g. 1 3 5):"
    echo "    1) OpenAI          (GPT-4o, o1, o3)"
    echo "    2) Anthropic       (Claude 3.5/4 Sonnet, Opus)"
    echo "    3) Google Gemini   (Gemini 2.5 Pro/Flash)"
    echo "    4) DeepSeek        (DeepSeek-V3, R1)"
    echo "    5) Groq            (Llama, Mixtral — fast inference)"
    echo "    6) OpenRouter      (Multi-provider gateway)"
    echo "    7) Mistral         (Mistral Large, Codestral)"
    echo "    8) None / skip"
    echo ""
    read -rp "  Select providers: " provider_input

    if [ -z "$provider_input" ] || [ "$provider_input" = "8" ]; then
        log_info "No external LLM providers selected"
        return
    fi

    for num in $provider_input; do
        case "$num" in
            1)
                echo ""
                read -rp "    OpenAI API key: " oai_key
                if [ -n "$oai_key" ]; then
                    LLM_PROVIDERS[openai]="$oai_key"
                    log_info "OpenAI API key collected"
                fi
                ;;
            2)
                echo ""
                read -rp "    Anthropic API key: " anth_key
                if [ -n "$anth_key" ]; then
                    LLM_PROVIDERS[anthropic]="$anth_key"
                    log_info "Anthropic API key collected"
                fi
                ;;
            3)
                echo ""
                echo "    Google Gemini auth method:"
                echo "      a) API key"
                echo "      b) Service account JSON file"
                echo "      c) OAuth (gcloud CLI)"
                echo ""
                read -rp "    Choose [a/b/c]: " gauth
                case "$gauth" in
                    a|A)
                        read -rp "    Google API key: " gkey
                        read -rp "    Google Project ID: " gproj
                        if [ -n "$gkey" ]; then
                            LLM_PROVIDERS[google]="$gkey"
                            GOOGLE_PROJECT_ID="$gproj"
                            GOOGLE_AUTH_METHOD="api_key"
                            log_info "Google API key + project collected"
                        fi
                        ;;
                    b|B)
                        read -rp "    Path to service account JSON: " gjson
                        read -rp "    Google Project ID: " gproj
                        if [ -n "$gjson" ] && [ -f "$gjson" ]; then
                            GOOGLE_JSON_PATH="$gjson"
                            GOOGLE_PROJECT_ID="$gproj"
                            GOOGLE_AUTH_METHOD="service_account"
                            LLM_PROVIDERS[google]="service_account"
                            cp "$gjson" "${CONFIG_DIR}/google-credentials.json"
                            chmod 600 "${CONFIG_DIR}/google-credentials.json"
                            log_info "Google service account JSON copied"
                        else
                            log_warn "JSON file not found — skipping Google"
                        fi
                        ;;
                    c|C)
                        read -rp "    Google Project ID: " gproj
                        GOOGLE_PROJECT_ID="$gproj"
                        GOOGLE_AUTH_METHOD="oauth"
                        LLM_PROVIDERS[google]="oauth"
                        log_info "Google OAuth — ensure gcloud is configured"
                        ;;
                    *)
                        log_warn "Invalid Google auth choice — skipping"
                        ;;
                esac
                ;;
            4)
                echo ""
                read -rp "    DeepSeek API key: " ds_key
                if [ -n "$ds_key" ]; then
                    LLM_PROVIDERS[deepseek]="$ds_key"
                    log_info "DeepSeek API key collected"
                fi
                ;;
            5)
                echo ""
                read -rp "    Groq API key: " groq_key
                if [ -n "$groq_key" ]; then
                    LLM_PROVIDERS[groq]="$groq_key"
                    log_info "Groq API key collected"
                fi
                ;;
            6)
                echo ""
                read -rp "    OpenRouter API key: " or_key
                if [ -n "$or_key" ]; then
                    LLM_PROVIDERS[openrouter]="$or_key"
                    log_info "OpenRouter API key collected"
                fi
                ;;
            7)
                echo ""
                read -rp "    Mistral API key: " mis_key
                if [ -n "$mis_key" ]; then
                    LLM_PROVIDERS[mistral]="$mis_key"
                    log_info "Mistral API key collected"
                fi
                ;;
            *)
                log_warn "Unknown provider number: ${num}"
                ;;
        esac
    done

    local pcount="${#LLM_PROVIDERS[@]}"
    log_info "Collected ${pcount} LLM provider(s)"
}

# ============================================================
# PHASE 6b: Local Model Selection (Ollama)
# ============================================================
collect_models() {
    log_phase "PHASE 6b: Local Model Selection (Ollama)"

    if [ -z "${SELECTED_SERVICES[ollama]+x}" ]; then
        log_info "Ollama not selected — skipping model selection"
        return
    fi

    echo ""
    echo "  Select models to pull (by VRAM tier):"
    echo ""
    echo "  ── Small (< 8GB VRAM) ──────────────"
    echo "    1)  llama3.2:3b              (2.0 GB)"
    echo "    2)  phi3:mini                (2.3 GB)"
    echo "    3)  gemma2:2b                (1.6 GB)"
    echo "    4)  qwen2.5:3b               (2.0 GB)"
    echo "    5)  nomic-embed-text          (0.3 GB)"
    echo "    6)  all-minilm                (0.1 GB)"
    echo ""
    echo "  ── Medium (8-16GB VRAM) ────────────"
    echo "    7)  llama3.1:8b              (4.7 GB)"
    echo "    8)  mistral:7b               (4.1 GB)"
    echo "    9)  codellama:7b             (3.8 GB)"
    echo "   10)  deepseek-coder-v2:16b    (8.9 GB)"
    echo "   11)  gemma2:9b                (5.4 GB)"
    echo "   12)  qwen2.5:7b               (4.4 GB)"
    echo ""
    echo "  ── Large (24GB+ VRAM) ──────────────"
    echo "   13)  llama3.1:70b             (40 GB)"
    echo "   14)  mixtral:8x7b             (26 GB)"
    echo "   15)  codellama:34b            (19 GB)"
    echo "   16)  qwen2.5:72b              (41 GB)"
    echo "   17)  deepseek-v3:671b          (custom)"
    echo ""
    echo "  ── Specialized ─────────────────────"
    echo "   18)  llava:7b                 (4.5 GB) [vision]"
    echo "   19)  bakllava                 (4.3 GB) [vision]"
    echo "   20)  dolphin-mixtral          (26 GB)  [uncensored]"
    echo "   21)  wizard-vicuna-uncensored (4.0 GB) [uncensored]"
    echo ""
    echo "  Enter numbers (e.g. 1 5 7 11), 'small', 'medium', 'all', or 'none'"
    echo ""
    read -rp "  Select models: " model_input

    # Model name lookup
    local model_names=(
        "llama3.2:3b"
        "phi3:mini"
        "gemma2:2b"
        "qwen2.5:3b"
        "nomic-embed-text"
        "all-minilm"
        "llama3.1:8b"
        "mistral:7b"
        "codellama:7b"
        "deepseek-coder-v2:16b"
        "gemma2:9b"
        "qwen2.5:7b"
        "llama3.1:70b"
        "mixtral:8x7b"
        "codellama:34b"
        "qwen2.5:72b"
        "deepseek-v3:671b"
        "llava:7b"
        "bakllava"
        "dolphin-mixtral"
        "wizard-vicuna-uncensored"
    )

    SELECTED_MODELS=()

    case "$model_input" in
        none|NONE|"")
            log_info "No models selected — can pull later"
            return
            ;;
        small|SMALL)
            SELECTED_MODELS=("${model_names[@]:0:6}")
            ;;
        medium|MEDIUM)
            SELECTED_MODELS=("${model_names[@]:0:12}")
            ;;
        all|ALL)
            SELECTED_MODELS=("${model_names[@]}")
            ;;
        *)
            for num in $model_input; do
                local midx=$((num - 1))
                if [ "$midx" -ge 0 ] && [ "$midx" -lt "${#model_names[@]}" ]; then
                    SELECTED_MODELS+=("${model_names[$midx]}")
                else
                    log_warn "Invalid model number: ${num}"
                fi
            done
            ;;
    esac

    echo ""
    echo "  Selected models:"
    for m in "${SELECTED_MODELS[@]}"; do
        echo "    ✓ ${m}"
    done
    log_info "Selected ${#SELECTED_MODELS[@]} model(s)"
}

# ============================================================
# PHASE 7: Tailscale Configuration
# ============================================================
TAILSCALE_ENABLED="no"
TAILSCALE_AUTH_KEY=""

collect_tailscale() {
    log_phase "PHASE 7: Tailscale VPN"

    echo ""
    echo "  Enable Tailscale VPN for secure access?"
    echo "    1) Yes"
    echo "    2) No"
    echo ""
    read -rp "  Choose [1-2]: " ts_choice

    if [ "$ts_choice" = "1" ]; then
        TAILSCALE_ENABLED="yes"
        echo ""
        echo "  Tailscale requires an AUTH KEY (not API key)"
        echo "  Generate at: https://login.tailscale.com/admin/settings/keys"
        echo "  Format: tskey-auth-XXXXXXXXXX"
        echo ""
        read -rp "  Tailscale auth key: " TAILSCALE_AUTH_KEY

        if [ -n "$TAILSCALE_AUTH_KEY" ]; then
            # Validate format
            if echo "$TAILSCALE_AUTH_KEY" | grep -q "^tskey-auth-"; then
                log_info "Tailscale auth key format valid"
            else
                log_warn "Key doesn't match tskey-auth-* format — may fail"
                echo "  Continue anyway? [y/N]: "
                read -rp "" ts_continue
                if [ "$ts_continue" != "y" ] && [ "$ts_continue" != "Y" ]; then
                    TAILSCALE_AUTH_KEY=""
                    log_warn "Tailscale auth key cleared — will configure in Script 3"
                fi
            fi
        else
            log_warn "No auth key — Tailscale will be configured in Script 3"
        fi

        # Install Tailscale
        if command -v tailscale >/dev/null 2>&1; then
            log_info "Tailscale already installed"
        else
            log_info "Installing Tailscale..."
            curl -fsSL https://tailscale.com/install.sh | bash 2>/dev/null || true
        fi

        # Authenticate if key provided
        if [ -n "$TAILSCALE_AUTH_KEY" ]; then
            log_info "Authenticating Tailscale..."
            if tailscale up --authkey="$TAILSCALE_AUTH_KEY" --hostname="$(hostname)" 2>/dev/null; then
                log_info "Tailscale authenticated successfully"
            else
                log_warn "Tailscale auth failed — will retry in Script 3"
            fi
        fi
    else
        TAILSCALE_ENABLED="no"
        log_info "Tailscale skipped"
    fi
}

# ============================================================
# PHASE 8: Extras
# ============================================================
GDRIVE_SYNC="no"
SIGNAL_API="no"
OPENCLAW="no"

collect_extras() {
    log_phase "PHASE 8: Additional Features"

    echo ""
    read -rp "  Enable Google Drive sync? [y/N]: " gd
    if [ "$gd" = "y" ] || [ "$gd" = "Y" ]; then
        GDRIVE_SYNC="yes"
    fi

    if [ -n "${SELECTED_SERVICES[signal-api]+x}" ]; then
        SIGNAL_API="yes"
    else
        read -rp "  Enable Signal messaging API? [y/N]: " sig
        if [ "$sig" = "y" ] || [ "$sig" = "Y" ]; then
            SIGNAL_API="yes"
            SELECTED_SERVICES[signal-api]=1
            SERVICE_PORTS[signal-api]=8080
        fi
    fi

    read -rp "  Enable OpenClaw (open-source Claude)? [y/N]: " oc
    if [ "$oc" = "y" ] || [ "$oc" = "Y" ]; then
        OPENCLAW="yes"
    fi

    log_info "Extras: GDrive=${GDRIVE_SYNC}, Signal=${SIGNAL_API}, OpenClaw=${OPENCLAW}"
}

# ============================================================
# PHASE 9: Generate All Credentials
# ============================================================
declare -A CREDENTIALS

generate_credentials() {
    log_phase "PHASE 9: Credential Generation"

    CREDENTIALS=(
        [POSTGRES_PASSWORD]="$(gen_password 32)"
        [REDIS_PASSWORD]="$(gen_password 32)"
        [JWT_SECRET]="$(gen_password 64)"
        [ANON_KEY]="$(gen_password 40)"
        [SERVICE_ROLE_KEY]="$(gen_password 40)"
        [SUPABASE_DB_PASSWORD]="$(gen_password 32)"
        [N8N_ENCRYPTION_KEY]="$(gen_password 32)"
        [LITELLM_MASTER_KEY]="sk-$(gen_password 40)"
        [LANGFUSE_SECRET_KEY]="sk-lf-$(gen_password 32)"
        [LANGFUSE_PUBLIC_KEY]="pk-lf-$(gen_password 32)"
        [LANGFUSE_SALT]="$(gen_password 32)"
        [FLOWISE_PASSWORD]="$(gen_password 24)"
        [GRAFANA_ADMIN_PASSWORD]="$(gen_password 24)"
        [MINIO_ROOT_PASSWORD]="$(gen_password 32)"
        [MONGO_PASSWORD]="$(gen_password 32)"
        [NEO4J_PASSWORD]="$(gen_password 24)"
        [DIFY_SECRET_KEY]="$(gen_password 32)"
        [OPENWEBUI_SECRET]="$(gen_password 32)"
        [WEBHOOK_SECRET]="$(gen_password 32)"
        [ENCRYPTION_KEY]="$(gen_password 32)"
        [INSTANCE_ID]="$(gen_uuid)"
    )

    log_info "Generated ${#CREDENTIALS[@]} credentials"
}

# ============================================================
# PHASE 10: Write .env file
# ============================================================
write_env_file() {
    log_phase "PHASE 10: Writing Configuration"

    mkdir -p "$CONFIG_DIR"

    if [ -f "$ENV_FILE" ]; then
        cp "$ENV_FILE" "${ENV_FILE}.bak.${TIMESTAMP}"
        log_info "Backed up existing .env"
    fi

    cat > "$ENV_FILE" << ENVEOF
# ============================================================
# AI Platform Configuration
# Generated: $(date -Iseconds)
# Script: 1-setup-system.sh v99.0.0
# ============================================================

# Domain & Proxy
DOMAIN=${DOMAIN}
REVERSE_PROXY=${REVERSE_PROXY}
VECTOR_DB=${VECTOR_DB}

# Tailscale
TAILSCALE_ENABLED=${TAILSCALE_ENABLED}
TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY}

# Extras
GDRIVE_SYNC=${GDRIVE_SYNC}
SIGNAL_API=${SIGNAL_API}
OPENCLAW=${OPENCLAW}

# ── Service Ports ──
ENVEOF

    for svc in $(echo "${!SERVICE_PORTS[@]}" | tr ' ' '\n' | sort); do
        local port="${SERVICE_PORTS[$svc]}"
        local varname=""
        varname=$(echo "${svc}" | tr '-' '_' | tr '[:lower:]' '[:upper:]')
        echo "${varname}_PORT=${port}" >> "$ENV_FILE"
    done

    cat >> "$ENV_FILE" << ENVEOF2

# ── Selected Services ──
SELECTED_SERVICES=$(echo "${!SELECTED_SERVICES[@]}" | tr ' ' ',')

# ── Selected Models ──
SELECTED_MODELS=$(printf '%s,' "${SELECTED_MODELS[@]}" | sed 's/,$//')

# ── LLM Provider API Keys ──
ENVEOF2

    for provider in $(echo "${!LLM_PROVIDERS[@]}" | tr ' ' '\n' | sort); do
        local varname=""
        varname=$(echo "${provider}" | tr '[:lower:]' '[:upper:]')
        echo "${varname}_API_KEY=${LLM_PROVIDERS[$provider]}" >> "$ENV_FILE"
    done

    if [ -n "$GOOGLE_PROJECT_ID" ]; then
        echo "GOOGLE_PROJECT_ID=${GOOGLE_PROJECT_ID}" >> "$ENV_FILE"
        echo "GOOGLE_AUTH_METHOD=${GOOGLE_AUTH_METHOD}" >> "$ENV_FILE"
    fi

    cat >> "$ENV_FILE" << ENVEOF3

# ── Generated Credentials ──
ENVEOF3

    for cred in $(echo "${!CREDENTIALS[@]}" | tr ' ' '\n' | sort); do
        echo "${cred}=${CREDENTIALS[$cred]}" >> "$ENV_FILE"
    done

    chmod 600 "$ENV_FILE"
    log_info "Configuration written to ${ENV_FILE}"
}

# ============================================================
# PHASE 10b: Generate LiteLLM config.yaml
# ============================================================
generate_litellm_config() {
    log_phase "PHASE 10b: LiteLLM Configuration"

    if [ -z "${SELECTED_SERVICES[litellm]+x}" ]; then
        log_info "LiteLLM not selected — skipping config generation"
        return
    fi

    cat > "$LITELLM_CONFIG" << 'LITEEOF'
# LiteLLM Proxy Configuration
# Auto-generated by Script 1

general_settings:
  master_key: MASTER_KEY_PLACEHOLDER
  database_url: postgresql://litellm:POSTGRES_PW_PLACEHOLDER@supabase-db:5432/litellm

model_list:
LITEEOF

    # Replace placeholders
    sed -i "s|MASTER_KEY_PLACEHOLDER|${CREDENTIALS[LITELLM_MASTER_KEY]}|g" "$LITELLM_CONFIG"
    sed -i "s|POSTGRES_PW_PLACEHOLDER|${CREDENTIALS[POSTGRES_PASSWORD]}|g" "$LITELLM_CONFIG"

    # Add Ollama models
    if [ -n "${SELECTED_SERVICES[ollama]+x}" ]; then
        for model in "${SELECTED_MODELS[@]}"; do
            cat >> "$LITELLM_CONFIG" << MODELEOF
  - model_name: ${model}
    litellm_params:
      model: ollama/${model}
      api_base: http://ollama:11434
MODELEOF
        done
    fi

    # Add external providers
    if [ -n "${LLM_PROVIDERS[openai]+x}" ]; then
        cat >> "$LITELLM_CONFIG" << 'OAIEOF'
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY
  - model_name: gpt-4o-mini
    litellm_params:
      model: openai/gpt-4o-mini
      api_key: os.environ/OPENAI_API_KEY
OAIEOF
    fi

    if [ -n "${LLM_PROVIDERS[anthropic]+x}" ]; then
        cat >> "$LITELLM_CONFIG" << 'ANTHEOF'
  - model_name: claude-sonnet-4
    litellm_params:
      model: anthropic/claude-sonnet-4-20250514
      api_key: os.environ/ANTHROPIC_API_KEY
  - model_name: claude-3.5-sonnet
    litellm_params:
      model: anthropic/claude-3-5-sonnet-20241022
      api_key: os.environ/ANTHROPIC_API_KEY
ANTHEOF
    fi

    if [ -n "${LLM_PROVIDERS[google]+x}" ]; then
        cat >> "$LITELLM_CONFIG" << 'GEMEOF'
  - model_name: gemini-2.5-pro
    litellm_params:
      model: gemini/gemini-2.5-pro-preview-06-05
      api_key: os.environ/GOOGLE_API_KEY
  - model_name: gemini-2.5-flash
    litellm_params:
      model: gemini/gemini-2.5-flash-preview-05-20
      api_key: os.environ/GOOGLE_API_KEY
GEMEOF
    fi

    if [ -n "${LLM_PROVIDERS[deepseek]+x}" ]; then
        cat >> "$LITELLM_CONFIG" << 'DSEOF'
  - model_name: deepseek-chat
    litellm_params:
      model: deepseek/deepseek-chat
      api_key: os.environ/DEEPSEEK_API_KEY
  - model_name: deepseek-reasoner
    litellm_params:
      model: deepseek/deepseek-reasoner
      api_key: os.environ/DEEPSEEK_API_KEY
DSEOF
    fi

    if [ -n "${LLM_PROVIDERS[groq]+x}" ]; then
        cat >> "$LITELLM_CONFIG" << 'GROQEOF'
  - model_name: groq-llama-70b
    litellm_params:
      model: groq/llama-3.3-70b-versatile
      api_key: os.environ/GROQ_API_KEY
  - model_name: groq-mixtral
    litellm_params:
      model: groq/mixtral-8x7b-32768
      api_key: os.environ/GROQ_API_KEY
GROQEOF
    fi

    if [ -n "${LLM_PROVIDERS[openrouter]+x}" ]; then
        cat >> "$LITELLM_CONFIG" << 'OREOF'
  - model_name: openrouter-auto
    litellm_params:
      model: openrouter/auto
      api_key: os.environ/OPENROUTER_API_KEY
OREOF
    fi

    if [ -n "${LLM_PROVIDERS[mistral]+x}" ]; then
        cat >> "$LITELLM_CONFIG" << 'MISEOF'
  - model_name: mistral-large
    litellm_params:
      model: mistral/mistral-large-latest
      api_key: os.environ/MISTRAL_API_KEY
MISEOF
    fi

    chmod 600 "$LITELLM_CONFIG"
    log_info "LiteLLM config written to ${LITELLM_CONFIG}"
}

# ============================================================
# PHASE 11: System Hardening
# ============================================================
harden_system() {
    log_phase "PHASE 11: System Hardening"

    # UFW firewall
    if command -v ufw >/dev/null 2>&1; then
        log_info "Configuring UFW firewall..."
        ufw --force reset >/dev/null 2>&1 || true
        ufw default deny incoming >/dev/null 2>&1
        ufw default allow outgoing >/dev/null 2>&1
        ufw allow 22/tcp >/dev/null 2>&1
        ufw allow 80/tcp >/dev/null 2>&1
        ufw allow 443/tcp >/dev/null 2>&1

        if [ "$TAILSCALE_ENABLED" = "yes" ]; then
            ufw allow 41641/udp >/dev/null 2>&1
            ufw allow in on tailscale0 >/dev/null 2>&1
        fi

        ufw --force enable >/dev/null 2>&1
        log_info "UFW firewall enabled"
    fi

    # Fail2ban
    if command -v fail2ban-server >/dev/null 2>&1; then
        systemctl enable fail2ban >/dev/null 2>&1 || true
        systemctl start fail2ban >/dev/null 2>&1 || true
        log_info "Fail2ban enabled"
    fi

    # SSH hardening
    if [ -f /etc/ssh/sshd_config ]; then
        local ssh_changed=0
        if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config 2>/dev/null; then
            sed -i 's/^PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
            ssh_changed=1
        fi
        if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config 2>/dev/null; then
            sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
            ssh_changed=1
        fi
        if [ "$ssh_changed" -eq 1 ]; then
            systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
            log_info "SSH hardened"
        else
            log_info "SSH already hardened"
        fi
    fi

    # Docker daemon settings
    mkdir -p /etc/docker
    if [ ! -f /etc/docker/daemon.json ]; then
        cat > /etc/docker/daemon.json << 'DOCKERJSON'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65536,
      "Soft": 65536
    }
  },
  "storage-driver": "overlay2"
}
DOCKERJSON
        systemctl restart docker 2>/dev/null || true
        log_info "Docker daemon configured"
    else
        log_info "Docker daemon.json already exists — skipping"
    fi

    # Sysctl tuning
    local sysctl_file="/etc/sysctl.d/99-ai-platform.conf"
    if [ ! -f "$sysctl_file" ]; then
        cat > "$sysctl_file" << 'SYSCTLEOF'
# AI Platform sysctl tuning
vm.swappiness=10
vm.overcommit_memory=1
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_tw_reuse=1
fs.file-max=2097152
fs.inotify.max_user_watches=524288
SYSCTLEOF
        sysctl -p "$sysctl_file" >/dev/null 2>&1 || true
        log_info "Sysctl tuning applied"
    else
        log_info "Sysctl already configured"
    fi

    log_info "System hardening complete"
}

# ============================================================
# PHASE 12: Final Health Check
# ============================================================
final_health_check() {
    log_phase "PHASE 12: Final Health Check"

    local checks_passed=0
    local checks_failed=0

    # Docker
    if docker info >/dev/null 2>&1; then
        log_info "Docker: running"
        checks_passed=$((checks_passed + 1))
    else
        log_error "Docker: not running"
        checks_failed=$((checks_failed + 1))
    fi

    # Docker Compose
    if docker compose version >/dev/null 2>&1; then
        log_info "Docker Compose: available"
        checks_passed=$((checks_passed + 1))
    else
        log_error "Docker Compose: not available"
        checks_failed=$((checks_failed + 1))
    fi

    # .env file
    if [ -f "$ENV_FILE" ]; then
        log_info "Config file: ${ENV_FILE} exists"
        checks_passed=$((checks_passed + 1))
    else
        log_error "Config file: missing"
        checks_failed=$((checks_failed + 1))
    fi

    # LiteLLM config
    if [ -n "${SELECTED_SERVICES[litellm]+x}" ]; then
        if [ -f "$LITELLM_CONFIG" ]; then
            log_info "LiteLLM config: ${LITELLM_CONFIG} exists"
            checks_passed=$((checks_passed + 1))
        else
            log_error "LiteLLM config: missing"
            checks_failed=$((checks_failed + 1))
        fi
    fi

    # Tailscale
    if [ "$TAILSCALE_ENABLED" = "yes" ]; then
        if command -v tailscale >/dev/null 2>&1; then
            local ts_status=""
            ts_status=$(tailscale status 2>/dev/null | head -1 || echo "unknown")
            log_info "Tailscale: ${ts_status}"
            checks_passed=$((checks_passed + 1))
        else
            log_warn "Tailscale: not installed"
            checks_failed=$((checks_failed + 1))
        fi
    fi

    # UFW
    if command -v ufw >/dev/null 2>&1; then
        local ufw_status=""
        ufw_status=$(ufw status 2>/dev/null | head -1 || echo "unknown")
        log_info "Firewall: ${ufw_status}"
        checks_passed=$((checks_passed + 1))
    fi

    echo ""
    log_info "Health check: ${checks_passed} passed, ${checks_failed} failed"
}

# ============================================================
# PHASE 13: Summary
# ============================================================
print_summary() {
    local svc_count="${#SELECTED_SERVICES[@]}"
    local model_count="${#SELECTED_MODELS[@]}"
    local provider_count="${#LLM_PROVIDERS[@]}"

    echo ""
    echo "============================================================"
    echo "  SCRIPT 1 COMPLETE — System Setup Finished"
    echo "============================================================"
    echo ""
    echo "  Domain       : ${DOMAIN}"
    echo "  Proxy        : ${REVERSE_PROXY}"
    echo "  Vector DB    : ${VECTOR_DB}"
    echo "  Services     : ${svc_count} selected"
    echo "  Models       : ${model_count} selected"
    echo "  LLM Providers: ${provider_count} configured"
    echo "  Tailscale    : ${TAILSCALE_ENABLED}"
    echo "  GDrive Sync  : ${GDRIVE_SYNC}"
    echo "  Signal API   : ${SIGNAL_API}"
    echo "  OpenClaw     : ${OPENCLAW}"
    echo ""
    echo "  Config file  : ${ENV_FILE}"
    echo "  LiteLLM conf : ${LITELLM_CONFIG}"
    echo "  Log file     : ${LOGFILE}"
    echo ""
    echo "  Selected services:"
    for svc in $(echo "${!SELECTED_SERVICES[@]}" | tr ' ' '\n' | sort); do
        echo "    • ${svc} (port ${SERVICE_PORTS[$svc]})"
    done
    echo ""
    if [ "${#SELECTED_MODELS[@]}" -gt 0 ]; then
        echo "  Selected models:"
        for m in "${SELECTED_MODELS[@]}"; do
            echo "    • ${m}"
        done
        echo ""
    fi
    if [ "${#LLM_PROVIDERS[@]}" -gt 0 ]; then
        echo "  LLM Providers:"
        for p in $(echo "${!LLM_PROVIDERS[@]}" | tr ' ' '\n' | sort); do
            echo "    • ${p}"
        done
        echo ""
    fi
    echo "  ▸ Next step: Run ./2-deploy-stack.sh"
    echo "============================================================"
}

# ============================================================
# MAIN
# ============================================================
main() {
    echo ""
    echo "============================================================"
    echo "  AI Platform Setup — Script 1: System Configuration"
    echo "  Version 99.0.0"
    echo "============================================================"

    preflight_checks
    port_health_check
    install_system_packages
    install_docker
    collect_domain
    collect_reverse_proxy
    collect_vector_db
    collect_services
    assign_ports
    collect_llm_providers
    collect_models
    collect_tailscale
    collect_extras
    generate_credentials
    write_env_file
    generate_litellm_config
    harden_system
    final_health_check
    print_summary
}

main "$@"

cd ~/AIPlatformAutomation/scripts

# Backup
cp 1-setup-system.sh 1-setup-system.sh.bak.$(date +%s)

# Create the new file - paste ALL 6 parts above in order into nano:
nano 1-setup-system.sh
# Paste Part 1, then Part 2, then 3, 4, 5, 6 — in sequence
# Save with Ctrl+O, Enter, Ctrl+X

# Make executable
chmod +x 1-setup-system.sh

# Syntax check
bash -n 1-setup-system.sh && echo "✅ SYNTAX OK" || echo "❌ SYNTAX ERROR"

# Run
sudo bash 1-setup-system.sh

