#!/usr/bin/env bash
# 1-setup-system.sh — Interactive tenant setup
# Generates /mnt/data/${TENANT_ID}/.env (complete, no duplicates)
# Nothing written outside /mnt/data/${TENANT_ID}/
set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }

# ── Tenant Identity ───────────────────────────────────────────
# Derive from current user's UID/GID automatically
TENANT_UID=$(id -u)
TENANT_GID=$(id -g)
TENANT_USER=$(id -un)
TENANT_ID="u${TENANT_UID}"
COMPOSE_PROJECT_NAME="aip-${TENANT_ID}"
DOCKER_NETWORK="${COMPOSE_PROJECT_NAME}_net"
DATA_ROOT="/mnt/data/${TENANT_ID}"

# Do NOT ask user for these — derive them. Multi-tenant safety.
echo "Tenant: ${TENANT_ID} (UID:${TENANT_UID} GID:${TENANT_GID})"
echo "Data root: ${DATA_ROOT}"

# ── Domain Configuration ──────────────────────────────────────
prompt_with_default() {
    local prompt=$1 default=$2 var_name=$3
    read -r -p "${prompt} [${default}]: " input
    eval "${var_name}='${input:-${default}}'"
}

prompt_with_default "Domain name" "ai.datasquiz.net" DOMAIN_NAME
prompt_with_default "SSL email" "hosting@datasquiz.net" SSL_EMAIL

# Test if domain resolves to this machine
PUBLIC_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || \
            curl -s --max-time 5 api.ipify.org 2>/dev/null || echo "unknown")

DOMAIN_RESOLVES=false
RESOLVED_IP=$(dig +short "${DOMAIN_NAME}" 2>/dev/null | tail -1 || echo "")
[ "${RESOLVED_IP}" = "${PUBLIC_IP}" ] && DOMAIN_RESOLVES=true

echo "Public IP: ${PUBLIC_IP}"
echo "Domain resolves: ${DOMAIN_RESOLVES} (resolves to: ${RESOLVED_IP:-none})"

if [ "${DOMAIN_RESOLVES}" = "true" ]; then
    DOMAIN="${DOMAIN_NAME}"
    PROXY_TYPE="caddy"
    SSL_TYPE="letsencrypt"
else
    echo "WARNING: Domain does not resolve to this machine."
    echo "Caddy will use self-signed certs until DNS propagates."
    DOMAIN="${PUBLIC_IP}"
    PROXY_TYPE="caddy"
    SSL_TYPE="selfsigned"
fi

# ── Hardware Detection ────────────────────────────────────────
GPU_TYPE="none"
GPU_DEVICE=""

if command -v nvidia-smi &>/dev/null && nvidia-smi --query-gpu=name --format=csv,noheader &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
    GPU_TYPE="nvidia"
    GPU_DEVICE="all"
    echo "GPU detected: NVIDIA — ${GPU_NAME}"
elif ls /dev/dri/renderD* &>/dev/null 2>&1; then
    GPU_TYPE="amd"
    GPU_DEVICE="/dev/dri/renderD128"
    echo "GPU detected: AMD/Intel (DRI)"
else
    GPU_TYPE="cpu"
    echo "No GPU detected — Ollama will run CPU only"
fi

# CPU info for sizing
CPU_CORES=$(nproc)
TOTAL_RAM_GB=$(awk '/MemTotal/{printf "%.0f", $2/1048576}' /proc/meminfo)
echo "CPU cores: ${CPU_CORES} | RAM: ${TOTAL_RAM_GB}GB"

# ── Service Selection ─────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo "  Select services to deploy"
echo "  (Enter y/n for each)"
echo "════════════════════════════════════════"

ask_service() {
    local name=$1 default=${2:-y}
    local prompt="  Deploy ${name}? [${default}]"
    read -r -p "${prompt}: " ans
    ans="${ans:-${default}}"
    [[ "${ans}" =~ ^[Yy] ]] && echo "true" || echo "false"
}

ENABLE_OPENWEBUI=$(ask_service "Open WebUI (Chat UI)" "y")
ENABLE_ANYTHINGLLM=$(ask_service "AnythingLLM (RAG + Docs)" "y")
ENABLE_DIFY=$(ask_service "Dify (LLM App Builder)" "y")
ENABLE_N8N=$(ask_service "n8n (Workflow Automation)" "y")
ENABLE_FLOWISE=$(ask_service "Flowise (AI Flows)" "y")
ENABLE_OPENCLAW=$(ask_service "OpenClaw (AI Agent)" "n")
ENABLE_LITELLM=$(ask_service "LiteLLM (LLM Proxy)" "y")
ENABLE_OLLAMA=$(ask_service "Ollama (Local LLMs)" "y")
ENABLE_GRAFANA=$(ask_service "Grafana + Prometheus (Monitoring)" "y")
ENABLE_SIGNAL=$(ask_service "Signal API (Messaging)" "n")
ENABLE_TAILSCALE=$(ask_service "Tailscale (VPN access)" "n")
ENABLE_RCLONE=$(ask_service "Rclone/GDrive sync" "n")

# ── Vector Database Selection ─────────────────────────────────
echo ""
echo "  Select Vector Database:"
echo "  1) Qdrant (recommended)"
echo "  2) Chroma"
echo "  3) Weaviate"
echo "  4) None (use external)"
read -r -p "  Choice [1]: " vdb_choice
vdb_choice="${vdb_choice:-1}"

case "${vdb_choice}" in
    1) VECTOR_DB="qdrant"
       VECTOR_DB_HOST="qdrant"
       VECTOR_DB_PORT="6333"
       VECTOR_DB_URL="http://qdrant:6333"
       ENABLE_QDRANT=true ;;
    2) VECTOR_DB="chroma"
       VECTOR_DB_HOST="chroma"
       VECTOR_DB_PORT="8000"
       VECTOR_DB_URL="http://chroma:8000"
       ENABLE_QDRANT=false ;;
    3) VECTOR_DB="weaviate"
       VECTOR_DB_HOST="weaviate"
       VECTOR_DB_PORT="8080"
       VECTOR_DB_URL="http://weaviate:8080"
       ENABLE_QDRANT=false ;;
    4) VECTOR_DB="none"
       ENABLE_QDRANT=false ;;
esac

# ── LLM Provider Configuration ───────────────────────────────
echo ""
echo "  LLM Providers (enter API keys, leave blank to skip):"
read -r -p "  OpenAI API key: " OPENAI_API_KEY
read -r -p "  Google (Gemini) API key: " GOOGLE_API_KEY  
read -r -p "  Groq API key: " GROQ_API_KEY
read -r -p "  OpenRouter API key: " OPENROUTER_API_KEY

# Determine active providers
LLM_PROVIDERS="local"
[ -n "${OPENAI_API_KEY}" ] && LLM_PROVIDERS="${LLM_PROVIDERS},openai"
[ -n "${GOOGLE_API_KEY}" ] && LLM_PROVIDERS="${LLM_PROVIDERS},google"
[ -n "${GROQ_API_KEY}" ] && LLM_PROVIDERS="${LLM_PROVIDERS},groq"
[ -n "${OPENROUTER_API_KEY}" ] && LLM_PROVIDERS="${LLM_PROVIDERS},openrouter"

# Ollama models (only if ollama enabled)
if [ "${ENABLE_OLLAMA}" = "true" ]; then
    echo ""
    echo "  Default Ollama model to pull (e.g. llama3.2:3b for low RAM, qwen2.5:7b for 16GB+):"
    echo "  Detected RAM: ${TOTAL_RAM_GB}GB"
    
    if [ "${TOTAL_RAM_GB}" -ge 32 ]; then
        DEFAULT_MODEL="qwen2.5:14b"
    elif [ "${TOTAL_RAM_GB}" -ge 16 ]; then
        DEFAULT_MODEL="llama3.2:8b"
    else
        DEFAULT_MODEL="llama3.2:3b"
    fi
    
    read -r -p "  Ollama default model [${DEFAULT_MODEL}]: " OLLAMA_DEFAULT_MODEL
    OLLAMA_DEFAULT_MODEL="${OLLAMA_DEFAULT_MODEL:-${DEFAULT_MODEL}}"
fi

# ── Port Assignment (Conflict-Free)
# Base port offset from UID to avoid multi-tenant conflicts
# UID 1001 → ports 5001-5020
# UID 1002 → ports 5021-5040
PORT_BASE=$(( (TENANT_UID - 1000) * 20 + 5000 ))

# Fixed internal ports (never change — these are container-internal)
POSTGRES_INTERNAL_PORT=5432
REDIS_INTERNAL_PORT=6379
OLLAMA_INTERNAL_PORT=11434
QDRANT_INTERNAL_PORT=6333
CHROMA_INTERNAL_PORT=8000
N8N_INTERNAL_PORT=5678
FLOWISE_INTERNAL_PORT=3000
ANYTHINGLLM_INTERNAL_PORT=3001
OPENWEBUI_INTERNAL_PORT=8080
LITELLM_INTERNAL_PORT=4000
DIFY_API_INTERNAL_PORT=5001
DIFY_WEB_INTERNAL_PORT=3000
OPENCLAW_INTERNAL_PORT=8082
GRAFANA_INTERNAL_PORT=3000
PROMETHEUS_INTERNAL_PORT=9090
MINIO_INTERNAL_PORT=9000
MINIO_CONSOLE_INTERNAL_PORT=9001
SIGNAL_INTERNAL_PORT=8080
TAILSCALE_INTERNAL_PORT=41641

# Host port mappings (tenant-scoped, no conflicts)
CADDY_HTTP_PORT=80       # Must be 80 (only one tenant can use this per server)
CADDY_HTTPS_PORT=443     # Must be 443
LITELLM_PORT=$(( PORT_BASE + 5 ))
OPENWEBUI_PORT=$(( PORT_BASE + 6 ))
GRAFANA_PORT=$(( PORT_BASE + 1 ))
PROMETHEUS_PORT=$(( PORT_BASE ))
ANYTHINGLLM_PORT=$(( PORT_BASE + 4 ))
DIFY_API_PORT=$(( PORT_BASE + 3 ))
DIFY_WEB_PORT=$(( PORT_BASE + 12 ))
N8N_PORT=$(( PORT_BASE + 2 ))
FLOWISE_PORT=$(( PORT_BASE - 2000 ))  # Flowise: 3000
OLLAMA_PORT=11434
QDRANT_PORT=6333
MINIO_PORT=9000
MINIO_CONSOLE_PORT=9001
OPENCLAW_PORT=$(( PORT_BASE + 7789 ))
SIGNAL_PORT=$(( PORT_BASE + 85 ))

# Check all ports are free
check_port() {
    local port=$1
    ss -tlnp 2>/dev/null | grep -q ":${port} " && {
        echo "ERROR: Port ${port} already in use"
        return 1
    }
    return 0
}

for port in ${LITELLM_PORT} ${OPENWEBUI_PORT} ${GRAFANA_PORT} ${N8N_PORT} ${ANYTHINGLLM_PORT}; do
    check_port "${port}" || {
        echo "Port conflict detected. Re-run after freeing ports or use a different UID."
        exit 1
    }
done

# ── Secret Generation ─────────────────────────────────────────
generate_secret() {
    openssl rand -hex 32
}

generate_password() {
    # Alphanumeric only — safe in heredocs, YAML, env vars
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32
}

# Only generate if not already in existing .env
ENV_FILE="${DATA_ROOT}/.env"

load_existing_secret() {
    local key=$1 default=$2
    if [ -f "${ENV_FILE}" ]; then
        val=$(grep "^${key}=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2- || echo "")
        [ -n "${val}" ] && echo "${val}" && return
    fi
    echo "${default}"
}

POSTGRES_PASSWORD=$(load_existing_secret "POSTGRES_PASSWORD" "$(generate_password)")
REDIS_PASSWORD=$(load_existing_secret "REDIS_PASSWORD" "$(generate_password)")
MINIO_ROOT_PASSWORD=$(load_existing_secret "MINIO_ROOT_PASSWORD" "$(generate_password)")
LITELLM_MASTER_KEY=$(load_existing_secret "LITELLM_MASTER_KEY" "sk-$(generate_secret)")
LITELLM_SALT_KEY=$(load_existing_secret "LITELLM_SALT_KEY" "$(generate_secret)")
ANYTHINGLLM_JWT_SECRET=$(load_existing_secret "ANYTHINGLLM_JWT_SECRET" "$(generate_secret)")
FLOWISE_PASSWORD=$(load_existing_secret "FLOWISE_PASSWORD" "$(generate_password)")
GRAFANA_PASSWORD=$(load_existing_secret "GRAFANA_PASSWORD" "$(generate_password)")
N8N_ENCRYPTION_KEY=$(load_existing_secret "N8N_ENCRYPTION_KEY" "$(generate_secret)")
OPENCLAW_SECRET=$(load_existing_secret "OPENCLAW_SECRET" "$(generate_secret)")
DIFY_SECRET_KEY=$(load_existing_secret "DIFY_SECRET_KEY" "$(generate_secret)")
DIFY_INNER_API_KEY=$(load_existing_secret "DIFY_INNER_API_KEY" "$(generate_secret)")
ADMIN_PASSWORD=$(load_existing_secret "ADMIN_PASSWORD" "$(generate_password)")

# ── Directory Creation ───────────────────────────────────────
# EVERYTHING under /mnt/data/${TENANT_ID}/
# Nothing in /var /etc /home (except the scripts themselves)

create_dirs() {
    local base="${DATA_ROOT}"
    
    # Core
    mkdir -p "${base}/postgres"
    mkdir -p "${base}/redis"
    mkdir -p "${base}/caddy/config"
    mkdir -p "${base}/caddy/data"
    mkdir -p "${base}/logs"
    
    # Services (only if enabled)
    [ "${ENABLE_OLLAMA}" = "true" ] && mkdir -p "${base}/ollama"
    [ "${ENABLE_OPENWEBUI}" = "true" ] && mkdir -p "${base}/openwebui"
    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && mkdir -p "${base}/anythingllm"
    [ "${ENABLE_DIFY}" = "true" ] && {
        mkdir -p "${base}/dify/storage"
        mkdir -p "${base}/dify-sandbox"
    }
    [ "${ENABLE_N8N}" = "true" ] && mkdir -p "${base}/n8n"
    [ "${ENABLE_FLOWISE}" = "true" ] && mkdir -p "${base}/flowise"
    [ "${ENABLE_OPENCLAW}" = "true" ] && {
        mkdir -p "${base}/openclaw/data"
        mkdir -p "${base}/openclaw/config"
    }
    [ "${ENABLE_LITELLM}" = "true" ] && mkdir -p "${base}/litellm"
    [ "${ENABLE_GRAFANA}" = "true" ] && {
        mkdir -p "${base}/grafana"
        mkdir -p "${base}/prometheus"
    }
    [ "${ENABLE_SIGNAL}" = "true" ] && mkdir -p "${base}/signal-api"
    [ "${ENABLE_TAILSCALE}" = "true" ] && mkdir -p "${base}/tailscale"
    [ "${ENABLE_RCLONE}" = "true" ] && {
        mkdir -p "${base}/rclone/config"
        mkdir -p "${base}/gdrive"
    }
    [ "${VECTOR_DB}" = "qdrant" ] && mkdir -p "${base}/qdrant"
    [ "${VECTOR_DB}" = "chroma" ] && mkdir -p "${base}/chroma"
    [ "${ENABLE_MINIO:-true}" = "true" ] && mkdir -p "${base}/minio"
    
    # Set ownership to tenant UID (non-root)
    chown -R "${TENANT_UID}:${TENANT_GID}" "${base}"
    
    echo "Directories created under ${base}"
}

create_dirs

# ── Write .env (Single Block, No Duplicates) ────────────────
write_env() {
    mkdir -p "${DATA_ROOT}"
    
    cat > "${ENV_FILE}" << ENVEOF
# AI Platform Environment — Generated $(date -u +%Y-%m-%dT%H:%M:%SZ)
# DO NOT EDIT MANUALLY — Re-run scripts/1-setup-system.sh

# ═════════════════════════════════════════════════════════════
# TENANT IDENTITY
# ═════════════════════════════════════════════════════════════
TENANT_ID=${TENANT_ID}
TENANT_USER=${TENANT_USER}
TENANT_UID=${TENANT_UID}
TENANT_GID=${TENANT_GID}
COMPOSE_PROJECT_NAME=${COMPOSE_PROJECT_NAME}
DOCKER_NETWORK=${DOCKER_NETWORK}
DATA_ROOT=${DATA_ROOT}
COMPOSE_FILE=${DATA_ROOT}/docker-compose.yml

# ═════════════════════════════════════════════════════════════
# NETWORK + DOMAIN
# ═════════════════════════════════════════════════════════════════
DOMAIN=${DOMAIN}
DOMAIN_NAME=${DOMAIN_NAME}
DOMAIN_RESOLVES=${DOMAIN_RESOLVES}
PUBLIC_IP=${PUBLIC_IP}
SSL_EMAIL=${SSL_EMAIL}
SSL_TYPE=${SSL_TYPE}
PROXY_TYPE=${PROXY_TYPE}

# ═════════════════════════════════════════════════════════════
# HARDWARE
# ═══════════════════════════════════════════════════════════════
GPU_TYPE=${GPU_TYPE}
GPU_DEVICE=${GPU_DEVICE}
CPU_CORES=${CPU_CORES}
TOTAL_RAM_GB=${TOTAL_RAM_GB}

# ═════════════════════════════════════════════════════════════
# SERVICE SELECTION (true/false)
# ═══════════════════════════════════════════════════════════
ENABLE_OPENWEBUI=${ENABLE_OPENWEBUI}
ENABLE_ANYTHINGLLM=${ENABLE_ANYTHINGLLM}
ENABLE_DIFY=${ENABLE_DIFY}
ENABLE_N8N=${ENABLE_N8N}
ENABLE_FLOWISE=${ENABLE_FLOWISE}
ENABLE_OPENCLAW=${ENABLE_OPENCLAW}
ENABLE_LITELLM=${ENABLE_LITELLM}
ENABLE_OLLAMA=${ENABLE_OLLAMA}
ENABLE_GRAFANA=${ENABLE_GRAFANA}
ENABLE_SIGNAL=${ENABLE_SIGNAL}
ENABLE_TAILSCALE=${ENABLE_TAILSCALE}
ENABLE_RCLONE=${ENABLE_RCLONE}
ENABLE_MINIO=true
ENABLE_POSTGRES=true
ENABLE_REDIS=true

# ═════════════════════════════════════════════════════════════
# VECTOR DATABASE
# ═════════════════════════════════════════════════════════════
VECTOR_DB=${VECTOR_DB}
VECTOR_DB_HOST=${VECTOR_DB_HOST}
VECTOR_DB_PORT=${VECTOR_DB_PORT}
VECTOR_DB_URL=${VECTOR_DB_URL}
ENABLE_QDRANT=${ENABLE_QDRANT}

# ═════════════════════════════════════════════════════════════
# HOST PORT MAPPINGS (each defined exactly once)
# ═════════════════════════════════════════════════════════════
CADDY_HTTP_PORT=80
CADDY_HTTPS_PORT=443
POSTGRES_PORT=${POSTGRES_PORT:-5432}
REDIS_PORT=${REDIS_PORT:-6379}
OLLAMA_PORT=${OLLAMA_PORT}
QDRANT_PORT=${QDRANT_PORT}
MINIO_PORT=${MINIO_PORT}
MINIO_CONSOLE_PORT=${MINIO_CONSOLE_PORT}
LITELLM_PORT=${LITELLM_PORT}
OPENWEBUI_PORT=${OPENWEBUI_PORT}
ANYTHINGLLM_PORT=${ANYTHINGLLM_PORT}
DIFY_API_PORT=${DIFY_API_PORT}
DIFY_WEB_PORT=${DIFY_WEB_PORT}
N8N_PORT=${N8N_PORT}
FLOWISE_PORT=${FLOWISE_PORT}
GRAFANA_PORT=${GRAFANA_PORT}
PROMETHEUS_PORT=${PROMETHEUS_PORT}
OPENCLAW_PORT=${OPENCLAW_PORT}
SIGNAL_PORT=${SIGNAL_PORT}

# ═════════════════════════════════════════════════════════════════
# INTERNAL PORTS (container-to-container, never change)
# ═══════════════════════════════════════════════════════════════
POSTGRES_INTERNAL_PORT=5432
REDIS_INTERNAL_PORT=6379
OLLAMA_INTERNAL_PORT=11434
QDRANT_INTERNAL_PORT=6333
N8N_INTERNAL_PORT=5678
FLOWISE_INTERNAL_PORT=3000
ANYTHINGLLM_INTERNAL_PORT=3001
OPENWEBUI_INTERNAL_PORT=8080
LITELLM_INTERNAL_PORT=4000
DIFY_API_INTERNAL_PORT=5001
DIFY_WEB_INTERNAL_PORT=3000
OPENCLAW_INTERNAL_PORT=8082
GRAFANA_INTERNAL_PORT=3000
PROMETHEUS_INTERNAL_PORT=9090
MINIO_INTERNAL_PORT=9000
MINIO_CONSOLE_INTERNAL_PORT=9001
SIGNAL_INTERNAL_PORT=8080

# ═══════════════════════════════════════════════════════════════
# DATABASE CREDENTIALS
# ═════════════════════════════════════════════════════════════════
POSTGRES_USER=ds-admin
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=aiplatform
REDIS_USER=ds-admin
REDIS_PASSWORD=${REDIS_PASSWORD}

# ═══════════════════════════════════════════════════════════════
# MINIO
# ═══════════════════════════════════════════════════════════════════
MINIO_ROOT_USER=ds-admin
MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}
MINIO_DEFAULT_BUCKETS=aiplatform-docs,aiplatform-media,aiplatform-backups

# ═══════════════════════════════════════════════════════════════
# SERVICE CREDENTIALS + SECRETS
# ═════════════════════════════════════════════════════════════════
ADMIN_PASSWORD=${ADMIN_PASSWORD}
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
LITELLM_SALT_KEY=${LITELLM_SALT_KEY}
ANYTHINGLLM_JWT_SECRET=${ANYTHINGLLM_JWT_SECRET}
FLOWISE_USERNAME=ds-admin
FLOWISE_PASSWORD=${FLOWISE_PASSWORD}
GRAFANA_ADMIN_USER=ds-admin
GRAFANA_PASSWORD=${GRAFANA_PASSWORD}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
OPENCLAW_SECRET=${OPENCLAW_SECRET}
OPENCLAW_ADMIN_USER=ds-admin
DIFY_SECRET_KEY=${DIFY_SECRET_KEY}
DIFY_INNER_API_KEY=${DIFY_INNER_API_KEY}

# ═════════════════════════════════════════════════════════════════
# LLM PROVIDERS
# ═════════════════════════════════════════════════════════════════
LLM_PROVIDERS=${LLM_PROVIDERS}
OPENAI_API_KEY=${OPENAI_API_KEY:-}
GOOGLE_API_KEY=${GOOGLE_API_KEY:-}
GROQ_API_KEY=${GROQ_API_KEY:-}
OPENROUTER_API_KEY=${OPENROUTER_API_KEY:-}

# ═══════════════════════════════════════════════════════════════
# OLLAMA
# ═══════════════════════════════════════════════════════════════
OLLAMA_DEFAULT_MODEL=${OLLAMA_DEFAULT_MODEL:-llama3.2:3b}

# ═════════════════════════════════════════════════════════════════
# OPENCLAVE
# ═════════════════════════════════════════════════════════════════
OPENCLAVE_IMAGE=openclaw:latest

# ═════════════════════════════════════════════════════════════════
# TAILSCALE
# ═════════════════════════════════════════════════════════════════
TAILSCALE_AUTH_KEY=
TAILSCALE_HOSTNAME=${TENANT_ID}
TAILSCALE_IP=pending
TAILSCALE_EXTRA_ARGS=

# ═════════════════════════════════════════════════════════════════
# SIGNAL
# ═══════════════════════════════════════════════════════════════
SIGNAL_PHONE=

# ═════════════════════════════════════════════════════════════════
# RCLONE / GDRIVE
# ═══════════════════════════════════════════════════════════════════
GDRIVE_ENABLED=${ENABLE_RCLONE}
GDRIVE_RCLONE_REMOTE=gdrive-${TENANT_ID}
GDRIVE_SYNC_INTERVAL=3600
RCLONE_MOUNT_POINT=${DATA_ROOT}/gdrive
RCLONE_OAUTH_CLIENT_ID=
ENVEOF

    chmod 600 "${ENV_FILE}"
    chown "${TENANT_UID}:${TENANT_GID}" "${ENV_FILE}"
    echo "Environment written to ${ENV_FILE}"
}

write_env

ok "Setup complete for tenant ${TENANT_ID}"
echo "Next: sudo bash scripts/2-deploy-services.sh"
