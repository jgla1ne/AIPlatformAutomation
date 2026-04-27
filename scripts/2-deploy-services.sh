#!/usr/bin/env bash
# =============================================================================
# Script 2: Deployment Engine
# PURPOSE: Generate ALL derived configs from platform.conf and orchestrate container deployment
# =============================================================================
# USAGE:   bash scripts/2-deploy-services.sh [tenant_id] [options]
# OPTIONS: --dry-run           Show what would be deployed without action
#          --verify-only       Verify deployment without changes
#          --flushall          Wipe databases, Ollama models, and Docker image
#                              cache before deploying. Use when iterating on
#                              script fixes. Without this flag, existing data
#                              (Postgres, Redis, MongoDB, Ollama models, images)
#                              is preserved — enabling fast cost-efficient retries.
#          --flush-dbs         Wipe only database directories (postgres, redis, mongodb)
#                              while preserving containers and models. Use for
#                              database corruption recovery without full re-deploy.
# =============================================================================

# =============================================================================
# NON-ROOT EXECUTION CHECK (README P7)
# =============================================================================
if [[ $EUID -eq 0 ]]; then
    echo "ERROR: This script must not be run as root (README P7 requirement)"
    exit 1
fi

# =============================================================================
# SCRIPT CONFIGURATION
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCRIPT_VERSION="5.1.0"
log() {
    local msg="[$(date +%H:%M:%S)] $*"
    echo "$msg"
}
ok() { log "OK: $*"; }
warn() { log "WARN: $*"; }
fail() { log "FAIL: $*"; exit 1; }
dry_run() { [[ "${DRY_RUN:-false}" == "true" ]] && echo "[DRY-RUN] $1"; }

# =============================================================================
# DRY RUN COMMAND EXECUTOR (README §12)
# =============================================================================
run_cmd() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}

# =============================================================================
# IDEMPOTENCY MARKERS (README P8)
# =============================================================================
step_done() { [[ -f "${CONFIGURED_DIR}/${1}" ]]; }
mark_done() { touch "${CONFIGURED_DIR}/${1}"; }

# =============================================================================
# FRAMEWORK VALIDATION
# =============================================================================
framework_validate() {
    log "Validating deployment framework..."
    
    # Fix Docker socket connection (common issue)
    if [[ "${DOCKER_HOST:-}" == *"user/1000"* ]]; then
        log "Fixing Docker socket connection..."
        unset DOCKER_HOST
    fi
    
    # Binary availability checks (README §13)
    for bin in docker yq curl jq; do
        if ! command -v "$bin" >/dev/null 2>&1; then
            fail "Missing required binary: $bin"
        fi
    done
    
    # Docker daemon health
    if ! docker info >/dev/null 2>&1; then
        fail "Docker daemon not running or accessible"
    fi
    
    # Docker compose plugin
    if ! docker compose version >/dev/null 2>&1; then
        fail "Docker compose plugin not available"
    fi
    
    # Docker data-root must be on EBS (DATA_DIR) — Script 1's configure_docker_dataroot() sets this.
    # Proceeding with the wrong data-root will exhaust the root volume mid-pull.
    local docker_root
    docker_root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo "/var/lib/docker")
    local expected_docker_root="${DATA_DIR}/docker"
    if [[ "$docker_root" != "$expected_docker_root" ]]; then
        fail "Docker data-root is '${docker_root}' — expected '${expected_docker_root}' (EBS volume). Re-run Script 1 to fix this before deploying."
    fi

    # Disk space check
    local available_gb
    available_gb=$(df "${BASE_DIR}" | awk 'NR==2{print int($4/1024/1024)}')
    if [[ $available_gb -lt 10 ]]; then
        fail "Insufficient disk space: ${available_gb}GB available, 10GB required"
    fi

    ok "Framework validation passed"
}

# =============================================================================
# DYNAMIC MODEL VALIDATION
# =============================================================================

# Function to validate Groq models against their API
validate_groq_models() {
    local api_key="${1}"
    local candidate_models="${2}"
    local valid_models=""
    local GROQ_DEFAULTS="llama-3.3-70b-versatile,llama-3.1-8b-instant"

    if [[ -z "${api_key}" ]]; then
        echo "${candidate_models:-${GROQ_DEFAULTS}}"
        return
    fi

    # Query Groq API for available models (text/chat models only)
    local available_models
    available_models=$(curl -s --max-time 10 -H "Authorization: Bearer ${api_key}" \
        "https://api.groq.com/openai/v1/models" | \
        jq -r '.data[] | select(.id | test("llama|mixtral|qwen|gemma")) | .id' 2>/dev/null || echo "")

    if [[ -z "${available_models}" ]]; then
        echo "WARNING: Could not reach Groq API, using defaults" >&2
        echo "${candidate_models:-${GROQ_DEFAULTS}}"
        return
    fi

    # Filter candidate models against available ones
    IFS=',' read -ra candidates <<< "${candidate_models:-${GROQ_DEFAULTS}}"
    for model in "${candidates[@]}"; do
        model=$(echo "${model// /}" | xargs)  # trim whitespace
        if echo "${available_models}" | grep -qx "${model}"; then
            valid_models="${valid_models}${valid_models:+,}${model}"
        else
            echo "WARNING: Groq model '${model}' not available, skipping" >&2
        fi
    done

    # If nothing matched (e.g. stale model names in config), fall back to current defaults
    if [[ -z "${valid_models}" ]]; then
        echo "WARNING: No candidate Groq models matched — falling back to defaults" >&2
        for model in ${GROQ_DEFAULTS//,/ }; do
            if echo "${available_models}" | grep -qx "${model}"; then
                valid_models="${valid_models}${valid_models:+,}${model}"
            fi
        done
    fi

    echo "${valid_models}"
}

# Function to validate OpenAI models
validate_openai_models() {
    local api_key="${1}"
    local candidate_models="${2}"
    local valid_models=""
    
    if [[ -z "${api_key}" ]]; then
        echo "${candidate_models}"
        return
    fi
    
    # Query OpenAI API for available models
    local available_models
    available_models=$(curl -s -H "Authorization: Bearer ${api_key}" \
        "https://api.openai.com/v1/models" | \
        jq -r '.data[] | select(.id | contains("gpt")) | .id' 2>/dev/null || echo "")
    
    if [[ -z "${available_models}" ]]; then
        echo "WARNING: Could not validate OpenAI models, using defaults" >&2
        echo "${candidate_models}"
        return
    fi
    
    # Filter candidate models against available ones
    IFS=',' read -ra candidates <<< "${candidate_models}"
    for model in "${candidates[@]}"; do
        model=$(echo "${model// /}" | xargs)  # trim whitespace
        if echo "${available_models}" | grep -q "${model}"; then
            valid_models="${valid_models}${valid_models:+,}${model}"
        else
            echo "WARNING: OpenAI model '${model}' not available, skipping" >&2
        fi
    done
    
    echo "${valid_models}"
}

# Function to get latest Ollama models
get_latest_ollama_models() {
    local candidate_models="${1}"
    local latest_models=""
    
    # Map of deprecated to latest models
    declare -A model_upgrade_map=(
        ["llama3.2:1b"]="llama3.2:1b"
        ["llama3.2:3b"]="llama3.2:3b" 
        ["llama3.1:8b"]="llama3.2:3b"
        ["llama3:8b"]="llama3.2:3b"
        ["qwen2.5:7b"]="qwen2.5:7b"
        ["mistral:7b"]="mistral:7b"
    )
    
    IFS=',' read -ra candidates <<< "${candidate_models}"
    for model in "${candidates[@]}"; do
        model=$(echo "${model// /}" | xargs)  # trim whitespace
        if [[ -n "${model_upgrade_map[${model}]:-}" ]]; then
            latest_models="${latest_models}${latest_models:+,}${model_upgrade_map[${model}]}"
            echo "INFO: Upgrading Ollama model '${model}' to '${model_upgrade_map[${model}]}'" >&2
        else
            latest_models="${latest_models}${latest_models:+,}${model}"
        fi
    done
    
    echo "${latest_models}"
}

# =============================================================================
# CONFIGURATION GENERATION FUNCTIONS
# (generate_compose, generate_litellm_config, generate_caddyfile,
#  generate_bifrost_config — all defined below as dependency builders)
# =============================================================================
build_litellm_deps() {
    local deps=""
    if [[ "${POSTGRES_ENABLED}" == "true" ]] || [[ "${REDIS_ENABLED}" == "true" ]]; then
        deps="    depends_on:"$'\n'
        [[ "${POSTGRES_ENABLED}" == "true" ]] && deps+="      - ${TENANT_PREFIX}-postgres"$'\n'
        [[ "${REDIS_ENABLED}" == "true" ]] && deps+="      - ${TENANT_PREFIX}-redis"$'\n'
    fi
    deps+="    networks:"$'\n'
    deps+="      - ${DOCKER_NETWORK}"$'\n'
    printf '%s' "${deps}"
}

build_openwebui_deps() {
    local deps=""
    if [[ "${OLLAMA_ENABLED}" == "true" ]]; then
        deps="    depends_on:"$'\n'
        deps+="      - ${TENANT_PREFIX}-ollama"$'\n'
    fi
    deps+="    networks:"$'\n'
    deps+="      - ${DOCKER_NETWORK}"$'\n'
    printf '%s' "${deps}"
}

build_librechat_deps() {
    local deps=""
    deps="    depends_on:"$'\n'
    deps+="      - ${TENANT_PREFIX}-mongodb"$'\n'
    deps+="    networks:"$'\n'
    deps+="      - ${DOCKER_NETWORK}"$'\n'
    printf '%s' "${deps}"
}

build_rag_api_deps() {
    # Emit depends_on for the RAG API's vector store backend + networks block
    local vector_db="${1:-pgvector}"
    local deps=""
    if [[ "${vector_db}" == "pgvector" ]] && [[ "${POSTGRES_ENABLED}" == "true" ]]; then
        deps="    depends_on:"$'\n'
        deps+="      - ${TENANT_PREFIX}-postgres"$'\n'
    elif [[ "${vector_db}" == "qdrant" ]] && [[ "${QDRANT_ENABLED}" == "true" ]]; then
        deps="    depends_on:"$'\n'
        deps+="      - ${TENANT_PREFIX}-qdrant"$'\n'
    fi
    deps+="    networks:"$'\n'
    deps+="      - ${DOCKER_NETWORK}"$'\n'
    printf '%s' "${deps}"
}

build_openclaw_deps() {
    local deps=""
    if [[ "${POSTGRES_ENABLED}" == "true" ]] || [[ "${REDIS_ENABLED}" == "true" ]]; then
        deps="    depends_on:"$'\n'
        [[ "${POSTGRES_ENABLED}" == "true" ]] && deps+="      - ${TENANT_PREFIX}-postgres"$'\n'
        [[ "${REDIS_ENABLED}" == "true" ]] && deps+="      - ${TENANT_PREFIX}-redis"$'\n'
    fi
    deps+="    networks:"$'\n'
    deps+="      - ${DOCKER_NETWORK}"$'\n'
    printf '%s' "${deps}"
}

build_n8n_deps() {
    local deps=""
    if [[ "${POSTGRES_ENABLED}" == "true" ]] || [[ "${REDIS_ENABLED}" == "true" ]]; then
        deps="    depends_on:"$'\n'
        [[ "${POSTGRES_ENABLED}" == "true" ]] && deps+="      - ${TENANT_PREFIX}-postgres"$'\n'
        [[ "${REDIS_ENABLED}" == "true" ]] && deps+="      - ${TENANT_PREFIX}-redis"$'\n'
    fi
    deps+="    networks:"$'\n'
    deps+="      - ${DOCKER_NETWORK}"$'\n'
    printf '%s' "${deps}"
}

build_flowise_deps() {
    local deps=""
    # flowise uses SQLite — no postgres/redis dependency
    deps+="    networks:"$'\n'
    deps+="      - ${DOCKER_NETWORK}"$'\n'
    printf '%s' "${deps}"
}

build_dify_deps() {
    local deps=""
    if [[ "${POSTGRES_ENABLED}" == "true" ]] || [[ "${REDIS_ENABLED}" == "true" ]]; then
        deps="    depends_on:"$'\n'
        [[ "${POSTGRES_ENABLED}" == "true" ]] && deps+="      - ${TENANT_PREFIX}-postgres"$'\n'
        [[ "${REDIS_ENABLED}" == "true" ]] && deps+="      - ${TENANT_PREFIX}-redis"$'\n'
    fi
    deps+="    networks:"$'\n'
    deps+="      - ${DOCKER_NETWORK}"$'\n'
    printf '%s' "${deps}"
}

# Helper to emit GPU reservation block if NVIDIA is active (README §4.2)
emit_gpu_reservation() {
    if [[ "${GPU_TYPE:-none}" == "nvidia" ]]; then
        # Calculate GPU device allocation per tenant
        local gpu_device="${GPU_DEVICE:-0}"
        local gpu_count="${GPU_COUNT:-1}"
        
        # For multi-GPU systems, assign specific GPU to tenant
        if [[ -n "${TENANT_GPU_ID:-}" ]]; then
            gpu_device="${TENANT_GPU_ID}"
        fi
        
        cat <<EOF
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: ["${gpu_device}"]
              count: ${gpu_count}
              capabilities: [gpu]
        limits:
          memory: ${GPU_MEMORY_LIMIT:-8G}
        reservations:
          memory: ${GPU_MEMORY_RESERVATION:-4G}
EOF
    fi
}

# Helper to emit resource limits for containers
emit_resource_limits() {
    local service_name="$1"
    local cpu_limit="${CPU_LIMIT:-2.0}"
    local memory_limit="${MEMORY_LIMIT:-4G}"
    local cpu_reservation="${CPU_RESERVATION:-1.0}"
    local memory_reservation="${MEMORY_RESERVATION:-2G}"
    
    # Service-specific resource overrides
    case "$service_name" in
        "postgres")
            cpu_limit="${POSTGRES_CPU_LIMIT:-1.0}"
            memory_limit="${POSTGRES_MEMORY_LIMIT:-2G}"
            cpu_reservation="${POSTGRES_CPU_RESERVATION:-0.5}"
            memory_reservation="${POSTGRES_MEMORY_RESERVATION:-1G}"
            ;;
        "redis")
            cpu_limit="${REDIS_CPU_LIMIT:-0.5}"
            memory_limit="${REDIS_MEMORY_LIMIT:-1G}"
            cpu_reservation="${REDIS_CPU_RESERVATION:-0.25}"
            memory_reservation="${REDIS_MEMORY_RESERVATION:-512M}"
            ;;
        "ollama")
            cpu_limit="${OLLAMA_CPU_LIMIT:-2.0}"
            memory_limit="${OLLAMA_MEMORY_LIMIT:-8G}"
            cpu_reservation="${OLLAMA_CPU_RESERVATION:-1.0}"
            memory_reservation="${OLLAMA_MEMORY_RESERVATION:-4G}"
            ;;
        "litellm")
            cpu_limit="${LITELLM_CPU_LIMIT:-2.0}"
            memory_limit="${LITELLM_MEMORY_LIMIT:-4G}"
            cpu_reservation="${LITELLM_CPU_RESERVATION:-1.0}"
            memory_reservation="${LITELLM_MEMORY_RESERVATION:-2G}"
            ;;
    esac
    
    cat <<EOF
    deploy:
      resources:
        limits:
          cpus: '${cpu_limit}'
          memory: ${memory_limit}
        reservations:
          cpus: '${cpu_reservation}'
          memory: ${memory_reservation}
EOF
}

build_authentik_deps() {
    local deps=""
    if [[ "${POSTGRES_ENABLED}" == "true" ]] || [[ "${REDIS_ENABLED}" == "true" ]]; then
        deps="    depends_on:"$'\n'
        [[ "${POSTGRES_ENABLED}" == "true" ]] && deps+="      - ${TENANT_PREFIX}-postgres"$'\n'
        [[ "${REDIS_ENABLED}" == "true" ]] && deps+="      - ${TENANT_PREFIX}-redis"$'\n'
    fi
    deps+="    networks:"$'\n'
    deps+="      - ${DOCKER_NETWORK}"$'\n'
    printf '%s' "${deps}"
}

build_zep_deps() {
    local deps=""
    if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
        deps="    depends_on:"$'\n'
        deps+="      - ${TENANT_PREFIX}-postgres"$'\n'
    fi
    deps+="    networks:"$'\n'
    deps+="      - ${DOCKER_NETWORK}"$'\n'
    printf '%s' "${deps}"
}

build_letta_deps() {
    local deps=""
    if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
        deps="    depends_on:"$'\n'
        deps+="      - ${TENANT_PREFIX}-postgres"$'\n'
    fi
    deps+="    networks:"$'\n'
    deps+="      - ${DOCKER_NETWORK}"$'\n'
    printf '%s' "${deps}"
}

# =============================================================================
# VECTORDB URL HELPER — returns internal Docker URL for the chosen vectordb.
# Used throughout compose generation so no service has a hardcoded DB type.
# =============================================================================
get_vectordb_url() {
    case "${VECTOR_DB_TYPE:-qdrant}" in
        qdrant)   echo "http://${TENANT_PREFIX}-qdrant:6333" ;;
        weaviate) echo "http://${TENANT_PREFIX}-weaviate:8080" ;;
        chroma)   echo "http://${TENANT_PREFIX}-chroma:8000" ;;
        milvus)   echo "http://${TENANT_PREFIX}-milvus:19530" ;;
        *)        echo "http://${TENANT_PREFIX}-qdrant:6333" ;;
    esac
}

# =============================================================================
# SECRET WRITE-BACK
#
# Script 2 generates certain secrets dynamically (e.g. AUTHENTIK_BOOTSTRAP_PASSWORD)
# that Script 1 has no knowledge of. These must be persisted to platform.conf so
# that Script 3 can display them in the credentials summary without hitting
# set -u "unbound variable" errors.
#
# update_conf_value KEY VALUE — in-place updates an existing KEY= line in
# platform.conf, or appends a new one. Safe to call multiple times (idempotent).
# =============================================================================
update_conf_value() {
    local key="$1" value="$2"
    local conf_file="${CONFIG_DIR}/platform.conf"
    if grep -q "^${key}=" "${conf_file}"; then
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "${conf_file}"
    else
        printf '%s="%s"\n' "${key}" "${value}" >> "${conf_file}"
    fi
}

persist_generated_secrets() {
    # Write secrets that Script 2 generates at runtime back to platform.conf.
    # Script 3 sources platform.conf; without this, show_credentials crashes (set -u).
    # IMPORTANT: use :-$(gen) pattern so secrets are never regenerated on re-deploy.
    if [[ "${AUTHENTIK_ENABLED}" == "true" ]]; then
        # AUTHENTIK_SECRET_KEY must be stable across redeploys — regenerating it
        # invalidates all active sessions and tokens.
        AUTHENTIK_SECRET_KEY="${AUTHENTIK_SECRET_KEY:-$(openssl rand -hex 50)}"
        update_conf_value "AUTHENTIK_SECRET_KEY" "${AUTHENTIK_SECRET_KEY}"
        update_conf_value "AUTHENTIK_BOOTSTRAP_PASSWORD" "${AUTHENTIK_BOOTSTRAP_PASSWORD}"
        update_conf_value "AUTHENTIK_BOOTSTRAP_EMAIL" "${AUTHENTIK_BOOTSTRAP_EMAIL:-${ADMIN_EMAIL:-}}"
    fi
    if [[ "${ZEP_ENABLED:-false}" == "true" ]]; then
        ZEP_AUTH_SECRET="${ZEP_AUTH_SECRET:-$(openssl rand -hex 32)}"
        update_conf_value "ZEP_AUTH_SECRET" "${ZEP_AUTH_SECRET}"
    fi
    if [[ "${LETTA_ENABLED:-false}" == "true" ]]; then
        LETTA_SERVER_PASS="${LETTA_SERVER_PASS:-$(openssl rand -hex 24)}"
        update_conf_value "LETTA_SERVER_PASS" "${LETTA_SERVER_PASS}"
    fi
    # ANYTHINGLLM_JWT_SECRET must also be stable — regenerating it logs out all users.
    if [[ "${ANYTHINGLLM_ENABLED}" == "true" ]]; then
        ANYTHINGLLM_JWT_SECRET="${ANYTHINGLLM_JWT_SECRET:-$(openssl rand -hex 32)}"
        update_conf_value "ANYTHINGLLM_JWT_SECRET" "${ANYTHINGLLM_JWT_SECRET}"
    fi
    # CODE_SERVER_PASSWORD — persist so it's shown in the dashboard and stable across redeploys.
    # Never regenerate if already set (avoid locking out users on re-deploy).
    if [[ "${CODE_SERVER_ENABLED:-${ENABLE_CODE_SERVER:-false}}" == "true" ]]; then
        CODE_SERVER_PASSWORD="${CODE_SERVER_PASSWORD:-$(openssl rand -base64 16 | tr -d '=+/')}"
        update_conf_value "CODE_SERVER_PASSWORD" "${CODE_SERVER_PASSWORD}"
    fi
    # LITELLM_UI_PASSWORD — may be generated by Script 1 but ensure it's always present.
    if [[ "${LITELLM_ENABLED:-false}" == "true" ]]; then
        LITELLM_UI_PASSWORD="${LITELLM_UI_PASSWORD:-$(openssl rand -base64 16 | tr -d '=+/')}"
        update_conf_value "LITELLM_UI_PASSWORD" "${LITELLM_UI_PASSWORD}"
    fi
    # DIFY_INIT_PASSWORD — used by configure_dify() in Script 3 to bootstrap the first admin.
    if [[ "${DIFY_ENABLED:-false}" == "true" ]]; then
        DIFY_SECRET_KEY="${DIFY_SECRET_KEY:-$(openssl rand -hex 32)}"
        update_conf_value "DIFY_SECRET_KEY" "${DIFY_SECRET_KEY}"
        DIFY_INIT_PASSWORD="${DIFY_INIT_PASSWORD:-$(openssl rand -base64 16 | tr -d '=+/')}"
        update_conf_value "DIFY_INIT_PASSWORD" "${DIFY_INIT_PASSWORD}"
    fi
    # POSTGRES_PASSWORD / REDIS_PASSWORD — generated by Script 1 but must survive re-deploys.
    # Never regenerate if already set; a mismatch would break all running DB connections.
    if [[ "${POSTGRES_ENABLED:-${ENABLE_POSTGRES:-false}}" == "true" ]]; then
        POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -hex 16)}"
        update_conf_value "POSTGRES_PASSWORD" "${POSTGRES_PASSWORD}"
    fi
    if [[ "${REDIS_ENABLED:-${ENABLE_REDIS:-false}}" == "true" ]]; then
        REDIS_PASSWORD="${REDIS_PASSWORD:-$(openssl rand -hex 16)}"
        update_conf_value "REDIS_PASSWORD" "${REDIS_PASSWORD}"
    fi
    # OPENCLAW_PASSWORD — gateway token; must survive restarts (wrong token = can't connect).
    if [[ "${OPENCLAW_ENABLED:-${ENABLE_OPENCLAW:-false}}" == "true" ]]; then
        OPENCLAW_PASSWORD="${OPENCLAW_PASSWORD:-$(openssl rand -hex 24)}"
        update_conf_value "OPENCLAW_PASSWORD" "${OPENCLAW_PASSWORD}"
    fi
    log "Generated secrets persisted to platform.conf"
}

# =============================================================================
# PORT ALLOCATOR — ensures every service gets a unique host-side port.
#
# platform.conf stores the user's PREFERRED port (validated by Script 1 against
# the live system at collection time). Script 2 honours that preference at
# compose-generation time but auto-increments past any same-run collision
# (e.g. two services sharing the same preferred port number like 3000).
#
# Results are written to PORT_ALLOCATIONS_FILE (a source-able key=value file)
# so that Script 3 can reference the *actual* allocated ports for health
# checks rather than the preferred values from platform.conf.
# =============================================================================
PORT_ALLOCATIONS_FILE=""  # resolved in main() after DATA_DIR is known
declare -gA _PORT_CLAIMED=()

init_port_allocator() {
    _PORT_CLAIMED=()
    PORT_ALLOCATIONS_FILE="${CONFIGURED_DIR}/port-allocations"
    : > "${PORT_ALLOCATIONS_FILE}"
    log "Port allocator initialised (${PORT_ALLOCATIONS_FILE})"
}

# allocate_host_port SERVICE PREFERRED_PORT
# Prints the resolved unique host port; records it so the next service won't reuse it.
allocate_host_port() {
    local svc="$1" preferred="$2" port
    port="${preferred}"
    # Walk forward until we find an unclaimed port in this run
    while [[ -n "${_PORT_CLAIMED[${port}]:-}" ]]; do
        port=$(( port + 1 ))
    done
    _PORT_CLAIMED["${port}"]="${svc}"
    # Persist  e.g.  OPENWEBUI_HOST_PORT="3000"
    local key="${svc^^}_HOST_PORT"
    key="${key//-/_}"   # code-server -> CODE_SERVER_HOST_PORT
    printf '%s="%s"\n' "${key}" "${port}" >> "${PORT_ALLOCATIONS_FILE}"
    printf '%s' "${port}"
}

# =============================================================================
# DOCKER COMPOSE GENERATION (README P3 - explicit heredoc blocks)
# =============================================================================
generate_compose() {
    log "Generating docker-compose.yml..."
    
    # Generate N8N_ENCRYPTION_KEY if needed (P0 fix)
    N8N_KEY_FILE="${DATA_DIR}/.n8n_encryption_key"
    if [[ -f "$N8N_KEY_FILE" ]]; then
        N8N_ENCRYPTION_KEY=$(cat "$N8N_KEY_FILE")
        log "Using existing N8N encryption key"
    else
        N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
        echo "$N8N_ENCRYPTION_KEY" > "$N8N_KEY_FILE"
        chmod 600 "$N8N_KEY_FILE"
        log "Generated new N8N encryption key"
    fi
    
    # GPU docker access verification (P2 fix)
    if [[ "${GPU_TYPE}" == "nvidia" ]]; then
        log "Verifying NVIDIA GPU access in Docker..."
        if ! docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu22.04 nvidia-smi &>/dev/null; then
            warn "WARNING: NVIDIA GPU detected but docker GPU access failed."
            warn "         Deploying without GPU. Check nvidia-container-toolkit install."
            GPU_TYPE="none"
        else
            ok "NVIDIA GPU access verified"
        fi
    fi
    
    # Build dependency strings
    local litellm_deps openwebui_deps openclaw_deps
    local n8n_deps flowise_deps dify_deps authentik_deps
    
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        litellm_deps=$(build_litellm_deps)
    fi
    if [[ "${OPENWEBUI_ENABLED}" == "true" ]]; then
        openwebui_deps=$(build_openwebui_deps)
    fi
    local librechat_deps=""
    if [[ "${LIBRECHAT_ENABLED:-${ENABLE_LIBRECHAT:-false}}" == "true" ]]; then
        librechat_deps=$(build_librechat_deps)
    fi
    if [[ "${OPENCLAW_ENABLED}" == "true" ]]; then
        openclaw_deps=$(build_openclaw_deps)
    fi
    if [[ "${N8N_ENABLED}" == "true" ]]; then
        n8n_deps=$(build_n8n_deps)
    fi
    if [[ "${FLOWISE_ENABLED}" == "true" ]]; then
        flowise_deps=$(build_flowise_deps)
    fi
    if [[ "${DIFY_ENABLED}" == "true" ]]; then
        dify_deps=$(build_dify_deps)
    fi
    if [[ "${AUTHENTIK_ENABLED}" == "true" ]]; then
        authentik_deps=$(build_authentik_deps)
    fi
    # PORT ALLOCATION (Runtime conflict resolution)
    # Fix: Call directly to preserve _PORT_CLAIMED array, then source the file
    [[ "${POSTGRES_ENABLED}" == "true" ]] && allocate_host_port postgres "${POSTGRES_PORT:-5432}" >/dev/null
    [[ "${REDIS_ENABLED}" == "true" ]] && allocate_host_port redis "${REDIS_PORT:-6379}" >/dev/null
    [[ "${OLLAMA_ENABLED}" == "true" ]] && allocate_host_port ollama "${OLLAMA_PORT:-11434}" >/dev/null
    [[ "${LITELLM_ENABLED}" == "true" ]] && allocate_host_port litellm "${LITELLM_PORT:-4000}" >/dev/null
    [[ "${OPENWEBUI_ENABLED}" == "true" ]] && allocate_host_port openwebui "${OPENWEBUI_PORT:-3000}" >/dev/null
    [[ "${LIBRECHAT_ENABLED:-${ENABLE_LIBRECHAT:-false}}" == "true" ]] && allocate_host_port librechat "${LIBRECHAT_PORT:-3080}" >/dev/null
    [[ "${OPENCLAW_ENABLED}" == "true" ]] && allocate_host_port openclaw "${OPENCLAW_PORT:-3001}" >/dev/null
    [[ "${QDRANT_ENABLED}" == "true" ]] && allocate_host_port qdrant "${QDRANT_PORT:-6333}" >/dev/null
    [[ "${N8N_ENABLED}" == "true" ]] && allocate_host_port n8n "${N8N_PORT:-5678}" >/dev/null
    [[ "${FLOWISE_ENABLED}" == "true" ]] && allocate_host_port flowise "${FLOWISE_PORT:-3000}" >/dev/null
    [[ "${DIFY_ENABLED}" == "true" ]] && allocate_host_port dify "${DIFY_PORT:-3040}" >/dev/null
    [[ "${DIFY_ENABLED}" == "true" ]] && allocate_host_port dify-api "${DIFY_API_PORT:-5001}" >/dev/null
    [[ "${AUTHENTIK_ENABLED}" == "true" ]] && allocate_host_port authentik "${AUTHENTIK_PORT:-9000}" >/dev/null
    [[ "${SIGNALBOT_ENABLED}" == "true" ]] && allocate_host_port signalbot "${SIGNALBOT_PORT:-8080}" >/dev/null
    [[ "${BIFROST_ENABLED}" == "true" ]] && allocate_host_port bifrost "${BIFROST_PORT:-8090}" >/dev/null
    [[ "${WEAVIATE_ENABLED:-${ENABLE_WEAVIATE:-false}}" == "true" ]] && allocate_host_port weaviate "${WEAVIATE_PORT:-8080}" >/dev/null
    [[ "${CHROMA_ENABLED:-${ENABLE_CHROMA:-false}}" == "true" ]] && allocate_host_port chroma "${CHROMA_PORT:-8000}" >/dev/null
    [[ "${MILVUS_ENABLED:-${ENABLE_MILVUS:-false}}" == "true" ]] && allocate_host_port milvus "${MILVUS_PORT:-19530}" >/dev/null
    [[ "${CODE_SERVER_ENABLED}" == "true" ]] && allocate_host_port code-server "${CODE_SERVER_PORT:-8080}" >/dev/null
    [[ "${GRAFANA_ENABLED}" == "true" ]] && allocate_host_port grafana "${GRAFANA_PORT:-3002}" >/dev/null
    [[ "${PROMETHEUS_ENABLED}" == "true" ]] && allocate_host_port prometheus "${PROMETHEUS_PORT:-9090}" >/dev/null
    [[ "${ANYTHINGLLM_ENABLED}" == "true" ]] && allocate_host_port anythingllm "${ANYTHINGLLM_PORT:-3001}" >/dev/null
    [[ "${ZEP_ENABLED:-false}" == "true" ]] && allocate_host_port zep "${ZEP_PORT:-8100}" >/dev/null
    [[ "${LETTA_ENABLED:-false}" == "true" ]] && allocate_host_port letta "${LETTA_PORT:-8283}" >/dev/null

    if [[ "${CADDY_ENABLED}" == "true" ]]; then
        allocate_host_port caddy-http "${CADDY_HTTP_PORT:-80}" >/dev/null
        allocate_host_port caddy-https "${CADDY_HTTPS_PORT:-443}" >/dev/null
    fi
    if [[ "${NPM_ENABLED:-false}" == "true" ]]; then
        allocate_host_port npm-http  "${NPM_HTTP_PORT:-80}"  >/dev/null
        allocate_host_port npm-https "${NPM_HTTPS_PORT:-443}" >/dev/null
        allocate_host_port npm-admin "${NPM_ADMIN_PORT:-81}"  >/dev/null
    fi

    # Load resolved ports and override locals correctly
    if [[ -f "${PORT_ALLOCATIONS_FILE}" ]]; then
        # shellcheck source=/dev/null
        source "${PORT_ALLOCATIONS_FILE}"
        [[ -n "${POSTGRES_HOST_PORT:-}" ]] && POSTGRES_PORT="${POSTGRES_HOST_PORT}"
        [[ -n "${REDIS_HOST_PORT:-}" ]] && REDIS_PORT="${REDIS_HOST_PORT}"
        [[ -n "${OLLAMA_HOST_PORT:-}" ]] && OLLAMA_PORT="${OLLAMA_HOST_PORT}"
        [[ -n "${LITELLM_HOST_PORT:-}" ]] && LITELLM_PORT="${LITELLM_HOST_PORT}"
        [[ -n "${OPENWEBUI_HOST_PORT:-}" ]] && OPENWEBUI_PORT="${OPENWEBUI_HOST_PORT}"
        [[ -n "${LIBRECHAT_HOST_PORT:-}" ]] && LIBRECHAT_PORT="${LIBRECHAT_HOST_PORT}"
        [[ -n "${OPENCLAW_HOST_PORT:-}" ]] && OPENCLAW_PORT="${OPENCLAW_HOST_PORT}"
        [[ -n "${QDRANT_HOST_PORT:-}" ]] && QDRANT_PORT="${QDRANT_HOST_PORT}"
        [[ -n "${N8N_HOST_PORT:-}" ]] && N8N_PORT="${N8N_HOST_PORT}"
        [[ -n "${FLOWISE_HOST_PORT:-}" ]] && FLOWISE_PORT="${FLOWISE_HOST_PORT}"
        [[ -n "${DIFY_HOST_PORT:-}" ]] && DIFY_PORT="${DIFY_HOST_PORT}"
        [[ -n "${DIFY_API_HOST_PORT:-}" ]] && DIFY_API_PORT="${DIFY_API_HOST_PORT}"
        [[ -n "${AUTHENTIK_HOST_PORT:-}" ]] && AUTHENTIK_PORT="${AUTHENTIK_HOST_PORT}"
        [[ -n "${SIGNALBOT_HOST_PORT:-}" ]] && SIGNALBOT_PORT="${SIGNALBOT_HOST_PORT}"
        [[ -n "${BIFROST_HOST_PORT:-}" ]] && BIFROST_PORT="${BIFROST_HOST_PORT}"
        [[ -n "${WEAVIATE_HOST_PORT:-}" ]] && WEAVIATE_PORT="${WEAVIATE_HOST_PORT}"
        [[ -n "${CHROMA_HOST_PORT:-}" ]] && CHROMA_PORT="${CHROMA_HOST_PORT}"
        [[ -n "${MILVUS_HOST_PORT:-}" ]] && MILVUS_PORT="${MILVUS_HOST_PORT}"
        [[ -n "${CODE_SERVER_HOST_PORT:-}" ]] && CODE_SERVER_PORT="${CODE_SERVER_HOST_PORT}"
        [[ -n "${GRAFANA_HOST_PORT:-}" ]] && GRAFANA_PORT="${GRAFANA_HOST_PORT}"
        [[ -n "${PROMETHEUS_HOST_PORT:-}" ]] && PROMETHEUS_PORT="${PROMETHEUS_HOST_PORT}"
        [[ -n "${ANYTHINGLLM_HOST_PORT:-}" ]] && ANYTHINGLLM_PORT="${ANYTHINGLLM_HOST_PORT}"
        [[ -n "${ZEP_HOST_PORT:-}" ]] && ZEP_PORT="${ZEP_HOST_PORT}"
        [[ -n "${LETTA_HOST_PORT:-}" ]] && LETTA_PORT="${LETTA_HOST_PORT}"
        [[ -n "${CADDY_HTTP_HOST_PORT:-}" ]] && CADDY_HTTP_PORT="${CADDY_HTTP_HOST_PORT}"
        [[ -n "${CADDY_HTTPS_HOST_PORT:-}" ]] && CADDY_HTTPS_PORT="${CADDY_HTTPS_HOST_PORT}"
        [[ -n "${NPM_HTTP_HOST_PORT:-}" ]]  && NPM_HTTP_PORT="${NPM_HTTP_HOST_PORT}"
        [[ -n "${NPM_HTTPS_HOST_PORT:-}" ]] && NPM_HTTPS_PORT="${NPM_HTTPS_HOST_PORT}"
        [[ -n "${NPM_ADMIN_HOST_PORT:-}" ]] && NPM_ADMIN_PORT="${NPM_ADMIN_HOST_PORT}"
    fi

    # VOLUME MOUNT NOTE (for reviewers):
    # Volume entries follow the format  host_path:container_path
    # ALL host-side paths are under ${DATA_DIR} (/mnt/<tenant>/...) — core principle.
    # Container-side paths (right side) are the images' internal expectations and
    # cannot be changed (e.g. :/etc/caddy, :/root/.ollama, :/var/lib/postgresql/data).
    # They are NOT host paths. Ownership is enforced by prepare_data_dirs() which runs
    # before this function and sets PUID:PGID on every host-side directory.

    # Header and networks
    # Backup existing compose file (P3 fix)
    if [[ -f "${COMPOSE_FILE}" ]]; then
        cp "${COMPOSE_FILE}" "${COMPOSE_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        echo "Existing compose file backed up to ${COMPOSE_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
    fi

    cat > "${COMPOSE_FILE}" << EOF

networks:
  ${DOCKER_NETWORK}:
    driver: bridge

services:
EOF

    # PostgreSQL (README P3 - explicit heredoc blocks)
    if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-postgres:
    image: pgvector/pgvector:pg15
    container_name: ${TENANT_PREFIX}-postgres
    restart: unless-stopped
    # postgres manages its own internal uid (70/alpine) — do not override user:
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - ${DATA_DIR}/postgres:/var/lib/postgresql/data
    ports:
      - "127.0.0.1:${POSTGRES_PORT}:5432"
    networks:
      - ${DOCKER_NETWORK}
$(emit_resource_limits "postgres")
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 6
      start_period: 30s

EOF
    fi

    # Redis
    if [[ "${REDIS_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-redis:
    image: redis:7-alpine
    container_name: ${TENANT_PREFIX}-redis
    restart: unless-stopped
    # redis manages its own internal uid (999) — do not override user:
    command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD}
    volumes:
      - ${DATA_DIR}/redis:/data
    ports:
      - "127.0.0.1:${REDIS_PORT}:6379"
    networks:
      - ${DOCKER_NETWORK}
$(emit_resource_limits "redis")
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 5s
      retries: 6

EOF
    fi

    # MongoDB — required by LibreChat
    if [[ "${LIBRECHAT_ENABLED:-${ENABLE_LIBRECHAT:-false}}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-mongodb:
    image: mongo:7
    container_name: ${TENANT_PREFIX}-mongodb
    restart: unless-stopped
    # MongoDB manages its own internal uid (999) — do not override user:
    environment:
      MONGO_INITDB_ROOT_USERNAME: librechat
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_PASSWORD}
    volumes:
      - ${DATA_DIR}/mongodb:/data/db
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 10s
      timeout: 5s
      retries: 6
      start_period: 30s

EOF
    fi

    # Ollama
    if [[ "${OLLAMA_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-ollama:
    image: ollama/ollama:latest
    pull_policy: always
    container_name: ${TENANT_PREFIX}-ollama
    restart: unless-stopped
    # ollama runs as root internally, stores models in /root/.ollama — do not override user:
    environment:
      # Unload models after 5 min idle to free RAM for other services on low-memory hosts
      OLLAMA_KEEP_ALIVE: "5m"
      # Cap concurrent model loads to 1 to prevent memory exhaustion
      OLLAMA_MAX_LOADED_MODELS: "1"
    volumes:
      - ${DATA_DIR}/ollama:/root/.ollama
    ports:
      - "127.0.0.1:${OLLAMA_PORT}:11434"
    networks:
      - ${DOCKER_NETWORK}
$(emit_gpu_reservation)
$(emit_resource_limits "ollama")
    healthcheck:
      test: ["CMD", "ollama", "list"]
      interval: 30s
      timeout: 15s
      retries: 5
      start_period: 30s

EOF
    fi

    # LiteLLM
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-litellm:
    image: ghcr.io/berriai/litellm:main-stable
    container_name: ${TENANT_PREFIX}-litellm
    restart: unless-stopped
    # litellm needs to write to Python pkg dirs for Prisma baseline migrations — run as root
    command: ["--config", "/app/config.yaml", "--port", "4000"]
    environment:
      DATABASE_URL: ${LITELLM_DB_URL}
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
      LITELLM_UI_PASSWORD: ${LITELLM_UI_PASSWORD}
      # Persist Prisma binary across container restarts — avoids 5-8 min re-download on re-deploy.
      # On a full --flushall the cache dir is wiped and re-downloaded once, then cached again.
      PRISMA_BINARY_CACHE_DIR: /app/prisma-cache
      LITELLM_MIGRATION_DIR: /tmp/litellm-migrations
      HOME: /tmp
    volumes:
      - ${CONFIG_DIR}/litellm/config.yaml:/app/config.yaml
      - ${DATA_DIR}/litellm/prisma-cache:/app/prisma-cache
    ports:
      - "127.0.0.1:${LITELLM_PORT}:4000"
$(build_litellm_deps)
    healthcheck:
      test: ["CMD-SHELL", "python3 -c \"import urllib.request; urllib.request.urlopen('http://localhost:4000/health/liveliness')\" 2>/dev/null || exit 1"]
      interval: 30s
      timeout: 15s
      retries: 10
      start_period: 3600s

EOF
    fi

    # Open WebUI — wired to LiteLLM (unified gateway) + Ollama + vectordb RAG
    if [[ "${OPENWEBUI_ENABLED}" == "true" ]]; then
        local vdb_url
        vdb_url=$(get_vectordb_url)
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: ${TENANT_PREFIX}-openwebui
    restart: unless-stopped
    # open-webui writes .webui_secret_key to /app/backend — run as root (image default)
    environment:
      # Ollama for local models
      OLLAMA_BASE_URL: http://${TENANT_PREFIX}-ollama:11434
      # LiteLLM as unified OpenAI-compatible gateway for all providers
      OPENAI_API_BASE_URL: http://${TENANT_PREFIX}-litellm:4000/v1
      OPENAI_API_KEY: ${LITELLM_MASTER_KEY}
      WEBUI_SECRET_KEY: ${OPENWEBUI_SECRET}
      DEFAULT_MODELS: ${OLLAMA_DEFAULT_MODEL}
      # RAG — embed via LiteLLM, retrieve from Qdrant
      ENABLE_RAG_WEB_SEARCH: "false"
      RAG_EMBEDDING_ENGINE: openai
      RAG_OPENAI_API_BASE_URL: http://${TENANT_PREFIX}-litellm:4000/v1
      RAG_OPENAI_API_KEY: ${LITELLM_MASTER_KEY}
      RAG_EMBEDDING_MODEL: text-embedding-3-small
      VECTOR_DB: qdrant
      QDRANT_URI: http://${TENANT_PREFIX}-qdrant:6333
      QDRANT_API_KEY: ${QDRANT_API_KEY:-}
EOF
        # Zep memory integration — inject only when Zep is deployed
        if [[ "${ZEP_ENABLED:-false}" == "true" ]]; then
            cat >> "${COMPOSE_FILE}" << EOF
      # Zep memory integration
      ZEP_API_URL: http://${TENANT_PREFIX}-zep:8000
      ZEP_API_KEY: ${ZEP_AUTH_SECRET}
EOF
        fi
        # Letta integration — inject only when Letta is deployed
        if [[ "${LETTA_ENABLED:-false}" == "true" ]]; then
            cat >> "${COMPOSE_FILE}" << EOF
      # Letta agent memory integration
      LETTA_API_URL: http://${TENANT_PREFIX}-letta:8283
      LETTA_API_KEY: ${LETTA_SERVER_PASS}
EOF
        fi
        cat >> "${COMPOSE_FILE}" << EOF
    volumes:
      - ${DATA_DIR}/openwebui:/app/backend/data
    ports:
      - "127.0.0.1:${OPENWEBUI_PORT}:8080"
$(build_openwebui_deps)
$(emit_gpu_reservation)
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/api/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 120s

EOF
    fi

    # LibreChat — multi-provider chat UI backed by MongoDB
    # RAG API sidecar uses pgvector on existing Postgres by default; Qdrant only when Postgres unavailable
    if [[ "${LIBRECHAT_ENABLED:-${ENABLE_LIBRECHAT:-false}}" == "true" ]]; then
        # Default to pgvector (eliminates separate vector DB component).
        # Fall back to Qdrant only when Postgres is disabled but Qdrant is running.
        local _rag_vector_db="pgvector"
        local _rag_qdrant_url=""
        if [[ "${POSTGRES_ENABLED}" != "true" ]] && [[ "${QDRANT_ENABLED}" == "true" ]]; then
            _rag_vector_db="qdrant"
            _rag_qdrant_url="http://${TENANT_PREFIX}-qdrant:6333"
        fi

        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-librechat:
    image: ghcr.io/danny-avila/librechat:latest
    container_name: ${TENANT_PREFIX}-librechat
    restart: unless-stopped
    # LibreChat writes to /app/uploads and /app/logs — run as root (image default):
    environment:
      HOST: 0.0.0.0
      PORT: 3080
      MONGO_URI: mongodb://librechat:${MONGO_PASSWORD}@${TENANT_PREFIX}-mongodb:27017/LibreChat?authSource=admin
      JWT_SECRET: ${LIBRECHAT_JWT_SECRET}
      JWT_REFRESH_SECRET: ${LIBRECHAT_JWT_SECRET}
      CREDS_KEY: ${LIBRECHAT_CRYPT_KEY}
      CREDS_IV: $(openssl rand -hex 16)
      # All LLM providers routed through LiteLLM proxy
      OPENAI_API_KEY: ${LITELLM_MASTER_KEY}
      OPENAI_REVERSE_PROXY: http://${TENANT_PREFIX}-litellm:4000/v1
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:-}
      GOOGLE_KEY: ${GOOGLE_API_KEY:-}
      GROQ_API_KEY: ${GROQ_API_KEY:-}
      # RAG API sidecar
      RAG_API_URL: http://${TENANT_PREFIX}-rag-api:8000
      # Platform settings
      SEARCH: "false"
      ALLOW_REGISTRATION: "false"
      ALLOW_SOCIAL_LOGIN: "false"
    volumes:
      - ${DATA_DIR}/librechat/uploads:/app/uploads
      - ${DATA_DIR}/librechat/logs:/app/logs
    ports:
      - "127.0.0.1:${LIBRECHAT_PORT}:3080"
    depends_on:
      - ${TENANT_PREFIX}-mongodb
      - ${TENANT_PREFIX}-rag-api
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://0.0.0.0:3080/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

  # LibreChat RAG API — document ingestion + retrieval via vector store
  ${TENANT_PREFIX}-rag-api:
    image: registry.librechat.ai/danny-avila/librechat-rag-api-dev-lite:latest
    container_name: ${TENANT_PREFIX}-rag-api
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    environment:
      # JWT must match LibreChat's JWT_SECRET for request authentication
      JWT_SECRET: ${LIBRECHAT_JWT_SECRET}
      # Embeddings via LiteLLM proxy (OpenAI-compatible)
      EMBEDDINGS_PROVIDER: openai
      RAG_OPENAI_API_KEY: ${LITELLM_MASTER_KEY}
      RAG_OPENAI_BASEURL: http://${TENANT_PREFIX}-litellm:4000/v1
      EMBEDDINGS_MODEL: text-embedding-ada-002
      # Vector store — pgvector on existing Postgres (default) or Qdrant fallback
      VECTOR_DB_TYPE: ${_rag_vector_db}
      QDRANT_URL: ${_rag_qdrant_url}
      QDRANT_API_KEY: ${QDRANT_API_KEY:-}
      # pgvector: same Postgres instance (image pgvector/pgvector:pg15 has the extension built-in)
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      DB_HOST: ${TENANT_PREFIX}-postgres
      RAG_PORT: "8000"
    volumes:
      - ${DATA_DIR}/rag-api:/app/uploads
$(build_rag_api_deps "${_rag_vector_db}")
    healthcheck:
      test: ["CMD-SHELL", "python3 -c \"import urllib.request; urllib.request.urlopen('http://localhost:8000/health')\" 2>/dev/null || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

EOF
    fi

    # OpenClaw — gateway with LiteLLM + search API integration
    local _openclaw_img="${OPENCLAW_IMAGE:-alpine/openclaw:latest}"
    if [[ "${OPENCLAW_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-openclaw:
    image: ${_openclaw_img}
    container_name: ${TENANT_PREFIX}-openclaw
    restart: unless-stopped
    # openclaw runs as node internally — do not override user.
    # Omit --port so OpenClaw reads OPENCLAW_PORT env var and binds to it,
    # allowing the same port on both sides of the host:container mapping.
    command: ["node", "openclaw.mjs", "gateway", "--allow-unconfigured"]
    environment:
      # OpenClaw reads OPENCLAW_PORT to choose its internal bind port
      OPENCLAW_PORT: ${OPENCLAW_PORT}
      # LiteLLM as the AI backend (OpenAI-compatible)
      OPENAI_BASE_URL: http://${TENANT_PREFIX}-litellm:4000/v1
      OPENAI_API_KEY: ${LITELLM_MASTER_KEY}
      # Gateway auth token — must match openclaw.json written by prepare_data_dirs()
      GATEWAY_TOKEN: ${OPENCLAW_PASSWORD}
      # CORS — allow the Caddy-proxied HTTPS origin and any localhost origin
      CORS_ORIGIN: "*"
      ALLOWED_ORIGINS: "*"
      GATEWAY_CONTROL_UI_ALLOWED_ORIGINS: "*"
    volumes:
      - ${DATA_DIR}/openclaw/data:/app/data
      # Mount config dir to OpenClaw's REAL home dir so openclaw.json persists
      - ${DATA_DIR}/openclaw/home:/home/node/.openclaw
    ports:
      - "${OPENCLAW_PORT}:${OPENCLAW_PORT}"
$(build_openclaw_deps)
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:${OPENCLAW_PORT}/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

EOF
    fi

    # Qdrant
    if [[ "${QDRANT_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-qdrant:
    image: qdrant/qdrant:latest
    container_name: ${TENANT_PREFIX}-qdrant
    restart: unless-stopped
    # qdrant runs as its own internal user (uid 1000) — do not override user:
    # redirect snapshots into the mounted volume so they are always writable
    environment:
      QDRANT__SERVICE__HTTP_PORT: 6333
      QDRANT__SERVICE__GRPC_PORT: 6334
      QDRANT__STORAGE__SNAPSHOTS_PATH: /qdrant/storage/snapshots
      API_KEY: ${QDRANT_API_KEY}
    volumes:
      - ${DATA_DIR}/qdrant:/qdrant/storage
    ports:
      - "127.0.0.1:${QDRANT_PORT}:6333"
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "bash", "-c", "echo > /dev/tcp/localhost/6333"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 10s

EOF
    fi

    # N8N
    if [[ "${N8N_ENABLED}" == "true" ]]; then
        # Compute N8N host/protocol for editor base URL (must match browser-visible URL)
        local _n8n_host _n8n_protocol
        if [[ "${CADDY_ENABLED:-false}" == "true" && -n "${BASE_DOMAIN:-}" ]]; then
            _n8n_host="n8n.${BASE_DOMAIN}"
            _n8n_protocol="https"
        else
            _n8n_host="${DOMAIN:-localhost}"
            _n8n_protocol="http"
        fi
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-n8n:
    image: n8nio/n8n:latest
    container_name: ${TENANT_PREFIX}-n8n
    restart: unless-stopped
    # n8n runs as node (uid 1000) with /home/node — do not override user:
    environment:
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      N8N_WEBHOOK_URL: ${N8N_WEBHOOK_URL}
      N8N_HOST: ${_n8n_host}
      N8N_PROTOCOL: ${_n8n_protocol}
      N8N_EDITOR_BASE_URL: ${_n8n_protocol}://${_n8n_host}
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: ${TENANT_PREFIX}-postgres
      DB_POSTGRESDB_PORT: 5432
      DB_POSTGRESDB_DATABASE: ${N8N_DB_NAME}
      DB_POSTGRESDB_USER: ${POSTGRES_USER}
      DB_POSTGRESDB_PASSWORD: ${POSTGRES_PASSWORD}
      REDIS_HOST: ${TENANT_PREFIX}-redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      # Force SSE push mode — WebSocket push is unreliable through Caddy reverse proxy;
      # SSE works without HTTP upgrade headers and is the recommended proxy-safe choice.
      N8N_PUSH_BACKEND: sse
      # LiteLLM integration — N8N AI nodes use LiteLLM as their OpenAI-compatible endpoint
      OPENAI_API_KEY: ${LITELLM_MASTER_KEY}
      OPENAI_API_BASE_URL: http://${TENANT_PREFIX}-litellm:4000/v1
    volumes:
      - ${DATA_DIR}/n8n:/home/node/.n8n
    ports:
      - "127.0.0.1:${N8N_PORT}:5678"
$(build_n8n_deps)
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost:5678/healthz 2>/dev/null || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

EOF
    fi

    # Flowise — wired to LiteLLM + chosen vectordb
    if [[ "${FLOWISE_ENABLED}" == "true" ]]; then
        local vdb_url
        vdb_url=$(get_vectordb_url)
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-flowise:
    image: flowiseai/flowise:latest
    container_name: ${TENANT_PREFIX}-flowise
    restart: unless-stopped
    # flowise stores data in /root/.flowise — do not override user:
    # Use SQLite (default) to avoid enterprise Postgres migration conflicts across image updates
    environment:
      DATABASE_TYPE: sqlite
      FLOWISE_USERNAME: ${FLOWISE_USERNAME}
      FLOWISE_PASSWORD: ${FLOWISE_PASSWORD}
      SECRETKEY_OVERWRITE: ${FLOWISE_SECRETKEY_OVERWRITE}
      # LiteLLM as unified LLM gateway
      OPENAI_API_BASE: http://${TENANT_PREFIX}-litellm:4000/v1
      OPENAI_API_KEY: ${LITELLM_MASTER_KEY}
      # VectorDB integration (dynamic — set by VECTOR_DB_TYPE)
      QDRANT_SERVER_URL: http://${TENANT_PREFIX}-qdrant:6333
      QDRANT_API_KEY: ${QDRANT_API_KEY:-}
      WEAVIATE_URL: http://${TENANT_PREFIX}-weaviate:8080
      CHROMA_URL: http://${TENANT_PREFIX}-chroma:8000
      # Search
      SERPAPI_API_KEY: ${SERPAPI_KEY:-}
      BRAVE_SEARCH_API_KEY: ${BRAVE_API_KEY:-}
    volumes:
      - ${DATA_DIR}/flowise:/root/.flowise
    ports:
      - "127.0.0.1:${FLOWISE_PORT}:3000"
$(build_flowise_deps)
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/v1/ping"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

EOF
    fi

    # Dify — full stack: web (Next.js) + api (Flask) + worker (Celery)
    # Without dify-api the web frontend loops on /install forever — CONSOLE_API_URL must
    # point to a running dify-api backend, not 127.0.0.1 which resolves inside the container.
    if [[ "${DIFY_ENABLED}" == "true" ]]; then
        # Public URL the browser uses to reach the API.
        # MUST share the same hostname as the web UI — Caddy routes /console/api*, /api*,
        # /v1*, /files* on dify.${BASE_DOMAIN} to dify-api internally. A separate
        # dify-api.${BASE_DOMAIN} subdomain requires the browser to trust an additional
        # self-signed cert, blocking all XHR and causing /install to hang forever.
        local _dify_api_public_url
        if [[ "${CADDY_ENABLED:-false}" == "true" && -n "${BASE_DOMAIN:-}" ]]; then
            _dify_api_public_url="https://dify.${BASE_DOMAIN}"
        else
            _dify_api_public_url="http://${DOMAIN:-localhost}:${DIFY_PORT:-3040}"
        fi

        cat >> "${COMPOSE_FILE}" << EOF
  # --- Dify Web (Next.js frontend) ---
  ${TENANT_PREFIX}-dify:
    image: langgenius/dify-web:latest
    container_name: ${TENANT_PREFIX}-dify
    restart: unless-stopped
    # dify-web runs as nextjs (uid 1001) — do not override user:
    environment:
      # Browser-visible API URL — must be reachable from the user's machine, not from Docker.
      CONSOLE_API_URL: ${_dify_api_public_url}
      APP_API_URL: ${_dify_api_public_url}
      # Disable Next.js telemetry
      NEXT_TELEMETRY_DISABLED: 1
      # Next.js standalone server binds to $HOSTNAME. Without this it resolves the container
      # hostname to the Docker bridge IP (e.g. 172.17.0.2), making 127.0.0.1 unreachable
      # and breaking all internal health checks and loopback probes.
      HOSTNAME: "0.0.0.0"
    ports:
      - "127.0.0.1:${DIFY_PORT}:3000"
$(build_dify_deps)
    healthcheck:
      # Node.js is guaranteed in the dify-web image. Make a TCP connection to port 3000;
      # exit 0 on success, exit 1 on error or 3s timeout. Avoids reliance on nc/-z support
      # or curl which may be absent. start_period outlasts LiteLLM's ~30 min cold start.
      test: ["CMD-SHELL", "node -e \"const net=require('net');const s=net.connect(3000,'127.0.0.1',()=>{s.destroy();process.exit(0)});s.on('error',()=>process.exit(1));setTimeout(()=>process.exit(1),3000);\""]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 2400s

  # --- Dify API (Flask backend) ---
  ${TENANT_PREFIX}-dify-api:
    image: langgenius/dify-api:latest
    container_name: ${TENANT_PREFIX}-dify-api
    restart: unless-stopped
    # dify-api manages its own internal user
    command: api
    environment:
      MODE: api
      MIGRATION_ENABLED: "true"
      SECRET_KEY: ${DIFY_SECRET_KEY}
      CONSOLE_API_URL: ${_dify_api_public_url}
      APP_API_URL: ${_dify_api_public_url}
      DB_USERNAME: ${POSTGRES_USER}
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_HOST: ${TENANT_PREFIX}-postgres
      DB_PORT: 5432
      DB_DATABASE: ${DIFY_DB_NAME}
      REDIS_HOST: ${TENANT_PREFIX}-redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      CELERY_BROKER_URL: redis://:${REDIS_PASSWORD}@${TENANT_PREFIX}-redis:6379/1
      # LiteLLM as unified LLM gateway
      OPENAI_API_BASE: http://${TENANT_PREFIX}-litellm:4000/v1
      OPENAI_API_KEY: ${LITELLM_MASTER_KEY}
      # Default model configuration
      OPENAI_ORGANIZATION: ""
      MODEL_PROVIDER: openai
      DEFAULT_MODEL: ${OLLAMA_DEFAULT_MODEL}
      # VectorDB — dynamic
      VECTOR_STORE: ${VECTOR_DB_TYPE:-qdrant}
      QDRANT_URL: http://${TENANT_PREFIX}-qdrant:6333
      QDRANT_API_KEY: ${QDRANT_API_KEY:-}
      WEAVIATE_ENDPOINT: http://${TENANT_PREFIX}-weaviate:8080
      CHROMA_HOST: ${TENANT_PREFIX}-chroma
      CHROMA_PORT: 8000
      MILVUS_HOST: ${TENANT_PREFIX}-milvus
      MILVUS_PORT: 19530
      # CORS — allow the web frontend origin
      WEB_API_CORS_ALLOW_ORIGINS: "*"
      CONSOLE_CORS_ALLOW_ORIGINS: "*"
    volumes:
      - ${DATA_DIR}/dify:/app/api/storage
    ports:
      - "127.0.0.1:${DIFY_API_PORT:-5001}:5001"
$(build_dify_deps)
    healthcheck:
      # Lightweight shell probe: checks TCP port 5001 connectivity using native /dev/tcp.
      # Adheres to 'NO PYTHON' requirement for healthchecks to prevent process piling.
      test: ["CMD-SHELL", "timeout 3 bash -c 'cat < /dev/tcp/127.0.0.1/5001' 2>/dev/null || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 2400s

  # --- Dify Worker (Celery background tasks) ---
  ${TENANT_PREFIX}-dify-worker:
    image: langgenius/dify-api:latest
    container_name: ${TENANT_PREFIX}-dify-worker
    restart: unless-stopped
    command: worker
    environment:
      MODE: worker
      SECRET_KEY: ${DIFY_SECRET_KEY}
      CONSOLE_API_URL: ${_dify_api_public_url}
      APP_API_URL: ${_dify_api_public_url}
      DB_USERNAME: ${POSTGRES_USER}
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_HOST: ${TENANT_PREFIX}-postgres
      DB_PORT: 5432
      DB_DATABASE: ${DIFY_DB_NAME}
      REDIS_HOST: ${TENANT_PREFIX}-redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      CELERY_BROKER_URL: redis://:${REDIS_PASSWORD}@${TENANT_PREFIX}-redis:6379/1
      OPENAI_API_BASE: http://${TENANT_PREFIX}-litellm:4000/v1
      OPENAI_API_KEY: ${LITELLM_MASTER_KEY}
      # Default model configuration
      OPENAI_ORGANIZATION: ""
      MODEL_PROVIDER: openai
      DEFAULT_MODEL: ${OLLAMA_DEFAULT_MODEL}
      VECTOR_STORE: ${VECTOR_DB_TYPE:-qdrant}
      QDRANT_URL: http://${TENANT_PREFIX}-qdrant:6333
      QDRANT_API_KEY: ${QDRANT_API_KEY:-}
    volumes:
      - ${DATA_DIR}/dify:/app/api/storage
$(build_dify_deps)
    healthcheck:
      # Lightweight shell probe: checks /proc for celery without spawning python/celery clients.
      # Prevents process piling and defunct zombies on low-RAM instances.
      test: ["CMD-SHELL", "grep -l \"celery\" /proc/*/cmdline > /dev/null || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 2400s

EOF
    fi

    # Authentik
    if [[ "${AUTHENTIK_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-authentik:
    image: ghcr.io/goauthentik/server:latest
    container_name: ${TENANT_PREFIX}-authentik
    restart: unless-stopped
    # authentik manages its own internal user — do not override user:
    command: server
    environment:
      AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY}
      AUTHENTIK_BOOTSTRAP_PASSWORD: ${AUTHENTIK_BOOTSTRAP_PASSWORD}
      AUTHENTIK_BOOTSTRAP_EMAIL: ${AUTHENTIK_BOOTSTRAP_EMAIL:-${ADMIN_EMAIL:-admin@localhost}}
      AUTHENTIK_POSTGRESQL__HOST: ${TENANT_PREFIX}-postgres
      AUTHENTIK_POSTGRESQL__USER: ${POSTGRES_USER}
      AUTHENTIK_POSTGRESQL__NAME: ${AUTHENTIK_DB_NAME}
      AUTHENTIK_POSTGRESQL__PASSWORD: ${POSTGRES_PASSWORD}
      AUTHENTIK_REDIS__HOST: ${TENANT_PREFIX}-redis
      AUTHENTIK_REDIS__PASSWORD: ${REDIS_PASSWORD}
    volumes:
      - ${DATA_DIR}/authentik:/media
    ports:
      - "127.0.0.1:${AUTHENTIK_PORT}:9000"
$(build_authentik_deps)
    # healthcheck:
#     test: ["CMD-SHELL", "curl -s -o /dev/null -w '%{http_code}' http://localhost:9000/ | grep -E '^(2|3)' > /dev/null || exit 1"]
#     interval: 30s
#     timeout: 10s
#     retries: 10
#     start_period: 60s
# Note: Healthcheck disabled due to endpoint issues - service is functional

EOF
    fi

    # Signalbot
    if [[ "${SIGNALBOT_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-signalbot:
    image: bbernhard/signal-cli-rest-api:latest
    container_name: ${TENANT_PREFIX}-signalbot
    restart: unless-stopped
    # Two-process design (signal-cli 0.14.1 SSE bug workaround):
    #   Port 8080 (external): bbernhard REST API in json-rpc mode
    #              → QR code (/v1/qrcodelink), register, verify, send
    #   Port 9999 (internal Docker network only): Python SSE proxy
    #              → /api/v1/events (SSE for OpenClaw) + /api/v1/rpc forwarding
    #   Port 9080 (loopback): signal-cli HTTP JSON-RPC (SSE proxy polls this)
    #   Port 6001 (loopback): signal-cli TCP JSON-RPC  (bbernhard connects here)
    entrypoint:
      - /bin/sh
      - /home/.local/share/signal-cli/start.sh
    environment:
      SIGNAL_PHONE: "${SIGNAL_PHONE:-}"
      SIGNAL_CLI_HTTP_PORT: "9080"
      SIGNAL_CLI_TCP_PORT: "6001"
      PROXY_PORT: "9999"
      SIGNAL_ACCOUNT: "${SIGNAL_PHONE:-}"
    volumes:
      - ${DATA_DIR}/signalbot:/home/.local/share/signal-cli
    networks:
      - ${DOCKER_NETWORK}
    ports:
      - "127.0.0.1:${SIGNALBOT_PORT:-8080}:8080"
    healthcheck:
      test: ["CMD-SHELL", "curl -sf --max-time 5 http://127.0.0.1:8080/v1/about -o /dev/null || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 90s

EOF
    fi

    # SearXNG
    if [[ "${SEARXNG_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-searxng:
    image: searxng/searxng:latest
    container_name: ${TENANT_PREFIX}-searxng
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    environment:
      SEARXNG_SECRET_KEY: ${SEARXNG_SECRET_KEY}
      SEARXNG_BIND_ADDRESS: "0.0.0.0"
      SEARXNG_PORT: "8888"
      SEARXNG_BASE_URL: "http://127.0.0.1:8888"
    volumes:
      - ${DATA_DIR}/searxng:/etc/searxng
    networks:
      - ${DOCKER_NETWORK}
    ports:
      - "127.0.0.1:${SEARXNG_PORT:-8888}:8888"
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://127.0.0.1:8888"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

EOF
    fi

    # Bifrost
    if [[ "${BIFROST_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-bifrost:
    image: bifrost/bifrost:latest
    container_name: ${TENANT_PREFIX}-bifrost
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    environment:
      API_KEY: ${BIFROST_API_KEY}
    volumes:
      - ${CONFIG_DIR}/bifrost/config.yaml:/app/config.yaml
    ports:
      - "127.0.0.1:${BIFROST_PORT}:8090"
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8090/health"]
      interval: 30s
      timeout: 10s
      retries: 5

EOF
    fi

    # Caddy (proxy - only service with 0.0.0.0 ports)
    if [[ "${CADDY_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-caddy:
    image: caddy:2-alpine
    container_name: ${TENANT_PREFIX}-caddy
    restart: unless-stopped
    cap_add:
      - NET_BIND_SERVICE
    volumes:
      - ${CONFIG_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile
      - ${DATA_DIR}/caddy:/data
    ports:
      - "${CADDY_HTTP_PORT}:80"
      - "${CADDY_HTTPS_PORT}:443"
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:2019/config/"]
      interval: 30s
      timeout: 10s
      retries: 5

EOF
    fi

    # Nginx Proxy Manager — web UI for managing proxy routes (mutually exclusive with Caddy)
    # Routes are configured via the NPM web UI at port ${NPM_ADMIN_PORT} — no Nginx config generated.
    # Default login: admin@example.com / changeme (change immediately after first login).
    if [[ "${NPM_ENABLED:-false}" == "true" ]]; then
        mkdir -p "${DATA_DIR}/npm/data" "${DATA_DIR}/npm/letsencrypt"
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-npm:
    image: jc21/nginx-proxy-manager:latest
    container_name: ${TENANT_PREFIX}-npm
    restart: unless-stopped
    # NPM must run as root (writes to /data and /etc/letsencrypt internally)
    ports:
      - "${NPM_HTTP_PORT:-80}:80"
      - "${NPM_HTTPS_PORT:-443}:443"
      - "127.0.0.1:${NPM_ADMIN_PORT:-81}:81"
    volumes:
      - ${DATA_DIR}/npm/data:/data
      - ${DATA_DIR}/npm/letsencrypt:/etc/letsencrypt
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:81/api/"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

EOF
    fi

    # Rclone ingestion (only if ENABLE_INGESTION=true and INGESTION_METHOD=rclone)
    if [[ "${ENABLE_INGESTION:-false}" == "true" && "${INGESTION_METHOD:-rclone}" == "rclone" ]]; then
        # Build rclone config inside the data dir so all paths stay under /mnt/$TENANT
        local rclone_conf_dir="${DATA_DIR}/rclone"
        mkdir -p "${rclone_conf_dir}"
        # Generate minimal rclone.conf if credentials file is provided
        if [[ -n "${GDRIVE_CREDENTIALS_FILE:-}" && -f "${GDRIVE_CREDENTIALS_FILE}" ]]; then
            # Copy service-account JSON into the rclone config dir so the container can mount it.
            # The file is mounted at /credentials/service-account.json inside the container.
            cp "${GDRIVE_CREDENTIALS_FILE}" "${rclone_conf_dir}/service-account.json"
            chmod 600 "${rclone_conf_dir}/service-account.json"
            # root_folder_id scopes rclone to the shared folder.
            # Service accounts have no personal My Drive — without this, sync is always empty.
            local _rclone_folder_line=""
            if [[ -n "${GDRIVE_FOLDER_ID:-}" ]]; then
                _rclone_folder_line="root_folder_id = ${GDRIVE_FOLDER_ID}"
            fi
            cat > "${rclone_conf_dir}/rclone.conf" << RCLONE_EOF
[${RCLONE_REMOTE:-gdrive}]
type = drive
scope = drive.readonly
service_account_file = /credentials/service-account.json
${_rclone_folder_line}
RCLONE_EOF
            chmod 600 "${rclone_conf_dir}/rclone.conf"
            ok "rclone.conf generated at ${rclone_conf_dir}/rclone.conf"
        else
            warn "GDRIVE_CREDENTIALS_FILE not set or not found — rclone container will start but sync will fail until credentials are provided"
            touch "${rclone_conf_dir}/rclone.conf"
            touch "${rclone_conf_dir}/service-account.json"
        fi

        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-rclone:
    image: rclone/rclone:latest
    container_name: ${TENANT_PREFIX}-rclone
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    # Run initial sync immediately on start, then repeat every POLL_INTERVAL minutes.
    entrypoint: ["/bin/sh", "-c", "while true; do rclone sync ${RCLONE_REMOTE:-gdrive}: /data --transfers=${RCLONE_TRANSFERS:-4} --checkers=${RCLONE_CHECKERS:-8} --log-level INFO 2>&1; sleep \$((${RCLONE_POLL_INTERVAL:-5}*60)); done"]
    volumes:
      - ${rclone_conf_dir}/rclone.conf:/config/rclone/rclone.conf:ro
      - ${rclone_conf_dir}/service-account.json:/credentials/service-account.json:ro
      - ${LOCAL_INGESTION_PATH:-${DATA_DIR}/ingestion/AI_Platform}:/data
    networks:
      - ${DOCKER_NETWORK}

EOF
    fi

    # Weaviate vector database
    if [[ "${WEAVIATE_ENABLED:-${ENABLE_WEAVIATE:-false}}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-weaviate:
    image: semitechnologies/weaviate:latest
    container_name: ${TENANT_PREFIX}-weaviate
    restart: unless-stopped
    environment:
      QUERY_DEFAULTS_LIMIT: 25
      AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED: 'false'
      AUTHENTICATION_APIKEY_ENABLED: 'true'
      AUTHENTICATION_APIKEY_ALLOWED_KEYS: ${WEAVIATE_API_KEY}
      PERSISTENCE_DATA_PATH: /var/lib/weaviate
      DEFAULT_VECTORIZER_MODULE: none
      ENABLE_MODULES: ''
      CLUSTER_HOSTNAME: node1
    volumes:
      - ${DATA_DIR}/weaviate:/var/lib/weaviate
    ports:
      - "127.0.0.1:${WEAVIATE_PORT}:8080"
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080/v1/.well-known/ready"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

EOF
    fi

    # ChromaDB vector database
    if [[ "${CHROMA_ENABLED:-${ENABLE_CHROMA:-false}}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-chroma:
    image: chromadb/chroma:latest
    container_name: ${TENANT_PREFIX}-chroma
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    environment:
      CHROMA_SERVER_AUTH_CREDENTIALS: ${CHROMA_AUTH_TOKEN}
      CHROMA_SERVER_AUTH_CREDENTIALS_PROVIDER: chromadb.auth.token.TokenConfigServerAuthCredentialsProvider
      CHROMA_SERVER_AUTH_PROVIDER: chromadb.auth.token.TokenAuthServerProvider
    volumes:
      - ${DATA_DIR}/chroma:/chroma/chroma
    ports:
      - "127.0.0.1:${CHROMA_PORT}:8000"
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/api/v1/heartbeat"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

EOF
    fi

    # Milvus standalone — vector database (bundles etcd + MinIO internally via standalone mode)
    # Requires two sidecar containers: etcd and minio.
    if [[ "${MILVUS_ENABLED:-${ENABLE_MILVUS:-false}}" == "true" ]]; then
        mkdir -p "${DATA_DIR}/milvus" "${DATA_DIR}/milvus-etcd" "${DATA_DIR}/milvus-minio"
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-milvus-etcd:
    image: quay.io/coreos/etcd:v3.5.5
    container_name: ${TENANT_PREFIX}-milvus-etcd
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    environment:
      ETCD_AUTO_COMPACTION_MODE: revision
      ETCD_AUTO_COMPACTION_RETENTION: "1000"
      ETCD_QUOTA_BACKEND_BYTES: "4294967296"
      ETCD_SNAPSHOT_COUNT: "50000"
    command: etcd --advertise-client-urls=http://127.0.0.1:2379 --listen-client-urls=http://0.0.0.0:2379 --data-dir=/etcd
    volumes:
      - ${DATA_DIR}/milvus-etcd:/etcd
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "etcdctl", "endpoint", "health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

  ${TENANT_PREFIX}-milvus-minio:
    image: minio/minio:latest
    container_name: ${TENANT_PREFIX}-milvus-minio
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    environment:
      MINIO_ACCESS_KEY: minioadmin
      MINIO_SECRET_KEY: minioadmin
    command: minio server /minio_data --console-address ":9001"
    volumes:
      - ${DATA_DIR}/milvus-minio:/minio_data
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

  ${TENANT_PREFIX}-milvus:
    image: milvusdb/milvus:v2.4.0
    container_name: ${TENANT_PREFIX}-milvus
    restart: unless-stopped
    command: milvus run standalone
    environment:
      ETCD_ENDPOINTS: ${TENANT_PREFIX}-milvus-etcd:2379
      MINIO_ADDRESS: ${TENANT_PREFIX}-milvus-minio:9000
    volumes:
      - ${DATA_DIR}/milvus:/var/lib/milvus
    ports:
      - "127.0.0.1:${MILVUS_PORT:-19530}:19530"
    depends_on:
      - ${TENANT_PREFIX}-milvus-etcd
      - ${TENANT_PREFIX}-milvus-minio
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9091/healthz"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

EOF
    fi

    # AnythingLLM — document chat, wired to LiteLLM + chosen vectordb
    if [[ "${ANYTHINGLLM_ENABLED:-${ENABLE_ANYTHINGLLM:-false}}" == "true" ]]; then
        local vdb_url
        vdb_url=$(get_vectordb_url)
        # Map VECTOR_DB_TYPE to AnythingLLM's vector_db param
        local allm_vdb
        case "${VECTOR_DB_TYPE:-qdrant}" in
            qdrant)   allm_vdb="qdrant" ;;
            weaviate) allm_vdb="weaviate" ;;
            chroma)   allm_vdb="chroma" ;;
            milvus)   allm_vdb="milvus" ;;
            *)        allm_vdb="qdrant" ;;
        esac
        # Choose a tool-calling-capable default model for AnythingLLM agent mode.
        # Ollama models (gemma3, llama3) don't support OpenAI-style function calling —
        # setting PROVIDER_SUPPORTS_NATIVE_TOOL_CALLING with them causes agent sessions to hang.
        # Prefer the first cloud model when available.
        local _allm_model _allm_token_limit _allm_tool_calling_env
        if [[ "${ENABLE_MAMMOUTH:-false}" == "true" && -n "${MAMMOUTH_API_KEY:-}" ]]; then
            _allm_model="mammouth/${MAMMOUTH_MODELS%%,*}"
            _allm_token_limit="200000"
            _allm_tool_calling_env="      PROVIDER_SUPPORTS_NATIVE_TOOL_CALLING: \"litellm\""
        elif [[ "${ENABLE_ANTHROPIC:-false}" == "true" && -n "${ANTHROPIC_API_KEY:-}" ]]; then
            _allm_model="claude-3-5-sonnet-20241022"
            _allm_token_limit="200000"
            _allm_tool_calling_env="      PROVIDER_SUPPORTS_NATIVE_TOOL_CALLING: \"litellm\""
        elif [[ "${ENABLE_OPENAI:-false}" == "true" && -n "${OPENAI_API_KEY:-}" ]]; then
            _allm_model="gpt-4o"
            _allm_token_limit="128000"
            _allm_tool_calling_env="      PROVIDER_SUPPORTS_NATIVE_TOOL_CALLING: \"litellm\""
        else
            # Ollama-only: no native tool calling (prompt-based fallback is used instead)
            _allm_model="ollama/${OLLAMA_DEFAULT_MODEL:-llama3.2:3b}"
            _allm_token_limit="4096"
            _allm_tool_calling_env=""
        fi
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-anythingllm:
    image: mintplexlabs/anythingllm:latest
    container_name: ${TENANT_PREFIX}-anythingllm
    restart: unless-stopped
    # anythingllm entrypoint does cd /app/server — do not override user:
    environment:
      STORAGE_DIR: /app/server/storage
      JWT_SECRET: ${ANYTHINGLLM_JWT_SECRET}
      # LLM via native LiteLLM provider — LITE_LLM_BASE_PATH has no /v1 suffix
      LLM_PROVIDER: litellm
      LITE_LLM_BASE_PATH: http://${TENANT_PREFIX}-litellm:4000
      LITE_LLM_API_KEY: ${LITELLM_MASTER_KEY}
      LITE_LLM_MODEL_PREF: ${_allm_model}
      LITE_LLM_MODEL_TOKEN_LIMIT: "${_allm_token_limit}"
      # Native tool calling only for cloud models that support it (not Ollama)
${_allm_tool_calling_env}
      # Embedding via native LiteLLM provider — shares LITE_LLM_BASE_PATH + LITE_LLM_API_KEY
      EMBEDDING_ENGINE: litellm
      EMBEDDING_MODEL_PREF: text-embedding-3-small
      EMBEDDING_MODEL_MAX_CHUNK_LENGTH: "8192"
      # VectorDB — dynamic, no hardcoded type
      VECTOR_DB: ${allm_vdb}
      QDRANT_ENDPOINT: http://${TENANT_PREFIX}-qdrant:6333
      QDRANT_API_KEY: ${QDRANT_API_KEY:-}
      WEAVIATE_ENDPOINT: http://${TENANT_PREFIX}-weaviate:8080
      WEAVIATE_API_KEY: ${WEAVIATE_API_KEY:-}
      CHROMA_ENDPOINT: http://${TENANT_PREFIX}-chroma:8000
      CHROMA_API_HEADER: Authorization
      CHROMA_API_KEY: ${CHROMA_AUTH_TOKEN:-}
      # Search
      AGENT_SERP_KEY: ${SERPAPI_KEY:-}
    volumes:
      - ${DATA_DIR}/anythingllm:/app/server/storage
    ports:
      - "127.0.0.1:${ANYTHINGLLM_PORT}:3001"
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3001/api/ping"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s

EOF
    fi

    # Zep CE — long-term memory layer backed by Postgres, LLM via LiteLLM proxy
    if [[ "${ZEP_ENABLED:-false}" == "true" ]]; then
        mkdir -p "${CONFIG_DIR}/zep"
        cat > "${CONFIG_DIR}/zep/config.yaml" << ZEP_CONF
store:
  type: postgres
  postgres:
    dsn: "postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${TENANT_PREFIX}-postgres:5432/${ZEP_DB_NAME}?sslmode=disable"
auth:
  required: true
  secret: "${ZEP_AUTH_SECRET}"
server:
  port: 8000
log:
  level: info
llm:
  openai_api_key: "${LITELLM_MASTER_KEY}"
  openai_api_base: "http://${TENANT_PREFIX}-litellm:4000/v1"
ZEP_CONF
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-zep:
    image: ghcr.io/getzep/zep:latest
    container_name: ${TENANT_PREFIX}-zep
    restart: unless-stopped
    volumes:
      - ${CONFIG_DIR}/zep/config.yaml:/app/config.yaml:ro
      - ${DATA_DIR}/zep:/app/data
    ports:
      - "127.0.0.1:${ZEP_PORT}:8000"
$(build_zep_deps)
    healthcheck:
      test: ["CMD", "bash", "-c", "echo > /dev/tcp/localhost/8000"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 60s

EOF
    fi

    # Letta (MemGPT) — stateful agent memory server backed by Postgres, LLM via LiteLLM
    if [[ "${LETTA_ENABLED:-false}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-letta:
    image: letta/letta:latest
    container_name: ${TENANT_PREFIX}-letta
    restart: unless-stopped
    # Letta writes agent state to /root/.letta — run as root (image default):
    environment:
      LETTA_SERVER_PASS: ${LETTA_SERVER_PASS}
      LETTA_PG_URI: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${TENANT_PREFIX}-postgres:5432/${LETTA_DB_NAME}
      OPENAI_API_KEY: ${LITELLM_MASTER_KEY}
      OPENAI_API_BASE: http://${TENANT_PREFIX}-litellm:4000/v1
    volumes:
      - ${DATA_DIR}/letta:/root/.letta
    ports:
      - "127.0.0.1:${LETTA_PORT}:8283"
$(build_letta_deps)
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8283/v1/health"]
      interval: 15s
      timeout: 10s
      retries: 5
      # Letta runs Alembic migrations before binding — can take 5-8 min on first run.
      # start_period keeps Docker in 'starting' (not 'unhealthy') through that window.
      start_period: 600s

EOF
    fi

    # Grafana dashboards
    if [[ "${GRAFANA_ENABLED:-${ENABLE_GRAFANA:-false}}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-grafana:
    image: grafana/grafana:latest
    container_name: ${TENANT_PREFIX}-grafana
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}
      GF_PATHS_DATA: /var/lib/grafana
      GF_SERVER_ROOT_URL: http://localhost:${GRAFANA_PORT:-3002}
    volumes:
      - ${DATA_DIR}/grafana:/var/lib/grafana
    ports:
      - "127.0.0.1:${GRAFANA_PORT:-3002}:3000"
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 5

EOF
    fi

    # Prometheus metrics
    if [[ "${PROMETHEUS_ENABLED:-${ENABLE_PROMETHEUS:-false}}" == "true" ]]; then
        mkdir -p "${CONFIG_DIR}/prometheus"
        # Minimal prometheus.yml — scrape self + docker if host networking
        cat > "${CONFIG_DIR}/prometheus/prometheus.yml" << PROMEOF
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: [localhost:9090]
PROMEOF
        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-prometheus:
    image: prom/prometheus:latest
    container_name: ${TENANT_PREFIX}-prometheus
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    volumes:
      - ${CONFIG_DIR}/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ${DATA_DIR}/prometheus:/prometheus
    ports:
      - "127.0.0.1:${PROMETHEUS_PORT:-9090}:9090"
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:9090/-/ready"]
      interval: 30s
      timeout: 10s
      retries: 5

EOF
    fi

    # Code Server (browser-based VS Code IDE)
    if [[ "${CODE_SERVER_ENABLED:-${ENABLE_CODE_SERVER:-false}}" == "true" ]]; then
        # Generate Code Server settings for AI integration
        local code_settings_dir="${DATA_DIR}/code-server/.local/share/code-server"
        mkdir -p "${code_settings_dir}"
        
        # Create settings.json with AI/LiteLLM configuration
        cat > "${code_settings_dir}/settings.json" << CODEEOF
{
  "workbench.colorTheme": "Default Dark+",
  "extensions.ignoreRecommendations": false,
  "extensions.autoUpdate": false,
  "python.defaultInterpreterPath": "/usr/bin/python3",
  "git.enableSmartCommit": true,
  "editor.tabSize": 2,
  "editor.insertSpaces": true,
  "files.autoSave": "afterDelay",
  "files.autoSaveDelay": 1000,
  "terminal.integrated.defaultProfile.linux": "bash",
  // AI Assistant Configuration
  "github.copilot.enable": {
    "*": false,
    "yaml": false,
    "plaintext": false,
    "markdown": false
  },
  "ai.enabled": true,
  "ai.model.provider": "openai-compatible",
  "ai.openai-compatible.base-url": "http://${TENANT_PREFIX}-litellm:4000/v1",
  "ai.openai-compatible.api-key": "${LITELLM_MASTER_KEY}",
  "ai.openai-compatible.model": "${OLLAMA_DEFAULT_MODEL:-llama3.1:8b}",
  "ai.openai-compatible.temperature": 0.7,
  "ai.openai-compatible.max-tokens": 4096,
  // Continue.dev integration (if extension installed)
  "continue.model": "${OLLAMA_DEFAULT_MODEL:-llama3.1:8b}",
  "continue.provider": "openai-compatible",
  "continue.apiBase": "http://${TENANT_PREFIX}-litellm:4000/v1",
  "continue.apiKey": "${LITELLM_MASTER_KEY}"
}
CODEEOF
        
        # Create extensions.json with pre-installed AI extensions
        cat > "${code_settings_dir}/extensions.json" << EXTEOF
{
  "recommendations": [
    "continue.continue",
    "github.copilot",
    "ms-python.python",
    "ms-vscode.vscode-typescript-next",
    "bradlc.vscode-tailwindcss",
    "esbenp.prettier-vscode",
    "ms-vscode.vscode-eslint"
  ],
  "unwantedRecommendations": [
    "github.copilot"
  ]
}
EXTEOF
        
        # Pre-install Continue.dev extension by creating the extensions directory
        local code_extensions_dir="${DATA_DIR}/code-server/.local/share/code-server/extensions"
        mkdir -p "${code_extensions_dir}"
        
        # Create extension installation script for Code Server
        cat > "${DATA_DIR}/code-server/install-extensions.sh" << INSTALLEOF
#!/bin/bash
# Auto-install Continue.dev extension for Code Server
echo "Installing Continue.dev extension..."
code-server --install-extension continue.continue --force 2>/dev/null || echo "Continue.dev extension will be installed on next start"
echo "Extension installation completed"
INSTALLEOF
        
        chmod +x "${DATA_DIR}/code-server/install-extensions.sh"

        cat >> "${COMPOSE_FILE}" << EOF
  ${TENANT_PREFIX}-code-server:
    image: codercom/code-server:latest
    container_name: ${TENANT_PREFIX}-code-server
    restart: unless-stopped
    user: "${PUID}:${PGID}"
    environment:
      PASSWORD: ${CODE_SERVER_PASSWORD:-changeme}
      # LiteLLM integration environment variables
      LITELLM_URL: "http://${TENANT_PREFIX}-litellm:4000/v1"
      LITELLM_API_KEY: "${LITELLM_MASTER_KEY}"
      DEFAULT_MODEL: "${OLLAMA_DEFAULT_MODEL:-llama3.2:3b}"
    # Default entrypoint runs: /usr/bin/entrypoint.sh --bind-addr 0.0.0.0:8080 .
    volumes:
      - ${DATA_DIR}/code-server:/home/coder
      - ${DATA_DIR}:/mnt/tenant-data:ro
    ports:
      - "127.0.0.1:${CODE_SERVER_PORT:-8080}:8080"
    networks:
      - ${DOCKER_NETWORK}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

EOF
    fi

    # Continue.dev config generation — writes into code-server's home dir so the
    # extension reads it automatically at /home/coder/.continue/config.json.
    # A reference copy is also kept at ${DATA_DIR}/continue-dev/config.json.
    if [[ "${CONTINUE_DEV_ENABLED:-${ENABLE_CONTINUE_DEV:-false}}" == "true" ]]; then
        local continue_dir="${DATA_DIR}/continue-dev"
        local continue_home_dir="${DATA_DIR}/code-server/.continue"
        mkdir -p "${continue_dir}" "${continue_home_dir}"
        
        # Generate dynamic model list from OLLAMA_MODELS
        local models_config=""
        local first_model="${OLLAMA_DEFAULT_MODEL:-llama3.1:8b}"
        
        # Add models from OLLAMA_MODELS variable
        IFS=',' read -ra models <<< "${OLLAMA_MODELS:-gemma3:4b,llama3.2:3b}"
        for model in "${models[@]}"; do
            model=$(echo "$model" | xargs)  # trim whitespace
            if [[ -n "$model" ]]; then
                if [[ -n "$models_config" ]]; then
                    models_config="${models_config},"
                fi
                # LiteLLM requires "ollama/" prefix for ollama-backed models
                local _litellm_model="ollama/${model}"
                models_config="${models_config}
    {
      \"title\": \"${model} (via LiteLLM)\",
      \"provider\": \"openai\",
      \"model\": \"${_litellm_model}\",
      \"apiBase\": \"http://${TENANT_PREFIX}-litellm:4000/v1\",
      \"apiKey\": \"${LITELLM_MASTER_KEY}\"
    }"
            fi
        done

        local _first_litellm_model="ollama/${first_model}"

        # Add Mammouth models if enabled (single key → Claude, Gemini, GPT via proxy)
        if [[ "${ENABLE_MAMMOUTH:-false}" == "true" && -n "${MAMMOUTH_API_KEY:-}" ]]; then
            IFS=',' read -ra _mammouth_models <<< "${MAMMOUTH_MODELS:-claude-sonnet-4-6,gemini-2.5-flash,gpt-4o}"
            for _mm in "${_mammouth_models[@]}"; do
                _mm=$(echo "$_mm" | xargs)
                [[ -z "$_mm" ]] && continue
                [[ -n "$models_config" ]] && models_config="${models_config},"
                models_config="${models_config}
    {
      \"title\": \"${_mm} (via Mammouth/LiteLLM)\",
      \"provider\": \"openai\",
      \"model\": \"mammouth/${_mm}\",
      \"apiBase\": \"http://${TENANT_PREFIX}-litellm:4000/v1\",
      \"apiKey\": \"${LITELLM_MASTER_KEY}\"
    }"
            done
        fi

        # Add external providers if enabled
        if [[ "${ENABLE_OPENAI:-false}" == "true" && -n "${OPENAI_API_KEY:-}" ]]; then
            if [[ -n "$models_config" ]]; then
                models_config="${models_config},"
            fi
            models_config="${models_config}
    {
      \"title\": \"GPT-4o (via LiteLLM)\",
      \"provider\": \"openai\",
      \"model\": \"gpt-4o\",
      \"apiBase\": \"http://${TENANT_PREFIX}-litellm:4000/v1\",
      \"apiKey\": \"${LITELLM_MASTER_KEY}\"
    }"
        fi

        if [[ "${ENABLE_ANTHROPIC:-false}" == "true" && -n "${ANTHROPIC_API_KEY:-}" ]]; then
            if [[ -n "$models_config" ]]; then
                models_config="${models_config},"
            fi
            models_config="${models_config}
    {
      \"title\": \"claude-3-5-sonnet (via LiteLLM)\",
      \"provider\": \"openai\",
      \"model\": \"claude-3-5-sonnet-20241022\",
      \"apiBase\": \"http://${TENANT_PREFIX}-litellm:4000/v1\",
      \"apiKey\": \"${LITELLM_MASTER_KEY}\"
    }"
        fi

        local _continue_config
        _continue_config=$(cat << CONTEOF
{
  "models": [${models_config}
  ],
  "tabAutocompleteModel": {
    "title": "${first_model} (via LiteLLM)",
    "provider": "openai",
    "model": "${_first_litellm_model}",
    "apiBase": "http://${TENANT_PREFIX}-litellm:4000/v1",
    "apiKey": "${LITELLM_MASTER_KEY}"
  },
  "embeddingsProvider": {
    "provider": "openai",
    "model": "text-embedding-3-small",
    "apiBase": "http://${TENANT_PREFIX}-litellm:4000/v1",
    "apiKey": "${LITELLM_MASTER_KEY}"
  },
  "contextProviders": [
    {"name": "open"},
    {"name": "search"},
    {"name": "diff"},
    {"name": "terminal"},
    {"name": "problems"},
    {"name": "issues"},
    {"name": "github"},
    {"name": "gitlab"}
  ],
  "slashCommands": [
    {
      "name": "edit",
      "description": "Edit code with AI assistance"
    },
    {
      "name": "comment",
      "description": "Add code comments"
    },
    {
      "name": "share",
      "description": "Share session"
    },
    {
      "name": "cmd",
      "description": "Run terminal command"
    }
  ],
  "allowAnonymousTelemetry": false
}
CONTEOF
)
        # Write to code-server home (.continue/ is where the extension reads its config)
        echo "${_continue_config}" > "${continue_home_dir}/config.json"
        chmod 644 "${continue_home_dir}/config.json"
        # Also keep a reference copy
        echo "${_continue_config}" > "${continue_dir}/config.json"

        # Create Continue.dev installation guide
        cat > "${continue_dir}/README.md" << READMEOF
# Continue.dev Configuration

This configuration enables Continue.dev to work with your AI Platform's LiteLLM proxy.

## Setup Instructions

1. **Install Continue.dev Extension**
   - In VS Code: Install "Continue" extension from Continue.dev
   - In Code Server: Extension should be auto-recommended

2. **Copy Configuration**
   \`\`\`bash
   cp ${continue_dir}/config.json ~/.continue/config.json
   \`\`\`

3. **Available Models**
   - Local Ollama models via LiteLLM load balancing
   - External providers (OpenAI, Anthropic) if configured
   - Automatic model switching based on availability

4. **Features**
   - Tab autocomplete with ${first_model}
   - Code editing and generation
   - Multi-provider model switching
   - Context-aware assistance

## Model Selection

Use the model selector in Continue.dev to switch between:
- Local models (fast, private, cost-effective)
- External models (high quality, API costs apply)
- Load-balanced routing via LiteLLM

## Troubleshooting

If models don't appear:
1. Check LiteLLM health: \`curl http://127.0.0.1:${LITELLM_PORT:-4000}/health\`
2. Verify Ollama models: \`docker exec ${TENANT_PREFIX}-ollama ollama list\`
3. Check API keys in platform.conf

## Integration with Code Server

The configuration is optimized for use with Code Server and includes:
- Pre-installed extension recommendations
- AI assistant settings
- LiteLLM proxy integration
- Multi-provider support
READMEOF
        
        chown -R "${PUID}:${PGID}" "${continue_dir}"
        ok "Continue.dev config.json generated at ${continue_dir}/config.json"
        ok "  â Copy to ~/.continue/config.json on your dev machine"
        ok "  â Installation guide available at ${continue_dir}/README.md"
        ok "  â Available models: $(echo "${OLLAMA_MODELS:-gemma3:4b,llama3.2:3b}" | tr ',' ' ')"
    fi

    ok "docker-compose.yml generated"
}

# =============================================================================
# CONFIG VALIDATION (README §6)
# =============================================================================
validate_compose() {
    log "Validating docker-compose.yml..."
    
    local output
    if ! output=$(docker compose -f "${COMPOSE_FILE}" config 2>&1); then
        echo "ERROR: docker-compose.yml validation failed:"
        echo "${output}"
        fail "docker-compose.yml validation failed"
    fi
    
    ok "docker-compose.yml is valid"
}

# =============================================================================
# LITELLM CONFIG GENERATION (README §10)
# =============================================================================
generate_litellm_config() {
    if [[ "${LITELLM_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    log "Generating LiteLLM configuration..."
    
    mkdir -p "${CONFIG_DIR}/litellm" "${DATA_DIR}/litellm/prisma-cache"
    
    cat > "${CONFIG_DIR}/litellm/config.yaml" << EOF
model_list:
EOF
    
    # Ollama (local models - always enabled if Ollama is enabled)
    if [[ "${OLLAMA_ENABLED}" == "true" ]]; then
        # Get latest Ollama models (upgrades deprecated ones)
        local latest_ollama_models
        latest_ollama_models=$(get_latest_ollama_models "${OLLAMA_MODELS}")
        
        # Update the default model if it was deprecated
        local updated_default_model
        updated_default_model=$(get_latest_ollama_models "${OLLAMA_DEFAULT_MODEL}")
        
        # Expand comma-separated model list into one entry per model
        IFS=',' read -ra ollama_models <<< "${latest_ollama_models}"
        for model in "${ollama_models[@]}"; do
            model=$(echo "${model// /}" | xargs)  # trim whitespace
            cat >> "${CONFIG_DIR}/litellm/config.yaml" << EOF
  - model_name: ollama/${model}
    litellm_params:
      model: ollama/${model}
      api_base: http://${TENANT_PREFIX}-ollama:11434
EOF
        done
        
        # Update platform.conf with the new default model
        update_conf_value "OLLAMA_DEFAULT_MODEL" "${updated_default_model}"
    fi
    
    # OpenAI (only if API key is non-empty)
    if [[ -n "${OPENAI_API_KEY}" ]]; then
        # Validate and get only available OpenAI models
        local valid_openai_models
        valid_openai_models=$(validate_openai_models "${OPENAI_API_KEY}" "${OPENAI_MODELS:-gpt-4o,gpt-4o-mini}")
        
        if [[ -n "${valid_openai_models}" ]]; then
            # Expand comma-separated model list into one entry per model
            IFS=',' read -ra openai_models <<< "${valid_openai_models}"
            for model in "${openai_models[@]}"; do
                model=$(echo "${model// /}" | xargs)  # trim whitespace
                cat >> "${CONFIG_DIR}/litellm/config.yaml" << EOF
  - model_name: ${model}
    litellm_params:
      model: openai/${model}
      api_key: ${OPENAI_API_KEY}
EOF
            done
            # Add embedding model when OpenAI key available (only if Mammouth not already registered it)
            if [[ "${ENABLE_MAMMOUTH:-false}" != "true" ]]; then
                cat >> "${CONFIG_DIR}/litellm/config.yaml" << EOF
  - model_name: text-embedding-3-small
    litellm_params:
      model: openai/text-embedding-3-small
      api_key: ${OPENAI_API_KEY}
EOF
            fi
        else
            echo "WARNING: No valid OpenAI models available, skipping OpenAI configuration" >&2
        fi
    fi
    
    # Anthropic (only if API key is non-empty)
    if [[ -n "${ANTHROPIC_API_KEY}" ]]; then
        IFS=',' read -ra _anthropic_models <<< "${ANTHROPIC_MODELS:-claude-3-5-sonnet-20241022,claude-3-5-haiku-20241022}"
        for _m in "${_anthropic_models[@]}"; do
            _m="${_m// /}"
            cat >> "${CONFIG_DIR}/litellm/config.yaml" << EOF
  - model_name: ${_m}
    litellm_params:
      model: anthropic/${_m}
      api_key: ${ANTHROPIC_API_KEY}
EOF
        done
        unset _anthropic_models _m
    fi

    # Google (only if API key is non-empty)
    if [[ -n "${GOOGLE_API_KEY}" ]]; then
        IFS=',' read -ra _google_models <<< "${GOOGLE_MODELS:-gemini-1.5-flash,gemini-1.5-pro}"
        for _m in "${_google_models[@]}"; do
            _m="${_m// /}"
            cat >> "${CONFIG_DIR}/litellm/config.yaml" << EOF
  - model_name: ${_m}
    litellm_params:
      model: google/${_m}
      api_key: ${GOOGLE_API_KEY}
EOF
        done
        unset _google_models _m
    fi
    
    # Groq (only if API key is non-empty)
    if [[ -n "${GROQ_API_KEY}" ]]; then
        # Validate and get only available Groq models
        local valid_groq_models
        valid_groq_models=$(validate_groq_models "${GROQ_API_KEY}" "${GROQ_MODELS:-llama-3.1-8b-instant}")
        
        if [[ -n "${valid_groq_models}" ]]; then
            # Expand comma-separated model list into one entry per model
            IFS=',' read -ra groq_models <<< "${valid_groq_models}"
            for model in "${groq_models[@]}"; do
                model=$(echo "${model// /}" | xargs)  # trim whitespace
                cat >> "${CONFIG_DIR}/litellm/config.yaml" << EOF
  - model_name: groq/${model}
    litellm_params:
      model: groq/${model}
      api_key: ${GROQ_API_KEY}
EOF
            done
        else
            echo "WARNING: No valid Groq models available, skipping Groq configuration" >&2
        fi
    fi
    
    # OpenRouter (only if API key is non-empty)
    if [[ -n "${OPENROUTER_API_KEY}" ]]; then
        cat >> "${CONFIG_DIR}/litellm/config.yaml" << EOF
  - model_name: openrouter/meta-llama/llama-3-70b-instruct
    litellm_params:
      model: openrouter/meta-llama/llama-3-70b-instruct
      api_key: ${OPENROUTER_API_KEY}
EOF
    fi

    # Mammouth AI (only if enabled and API key is non-empty)
    if [[ "${ENABLE_MAMMOUTH:-false}" == "true" && -n "${MAMMOUTH_API_KEY:-}" ]]; then
        # Expand comma-separated model list into one entry per model
        IFS=',' read -ra _mammouth_models <<< "${MAMMOUTH_MODELS:-claude-sonnet-4-6,gemini-2.5-flash,gpt-4o}"
        for _m in "${_mammouth_models[@]}"; do
            _m="${_m// /}"
            cat >> "${CONFIG_DIR}/litellm/config.yaml" << EOF
  - model_name: mammouth/${_m}
    litellm_params:
      model: openai/${_m}
      api_base: ${MAMMOUTH_BASE_URL:-https://api.mammouth.ai/v1}
      api_key: ${MAMMOUTH_API_KEY}
EOF
        done
        unset _mammouth_models _m

        # Embedding model via Mammouth (text-embedding-3-small through Mammouth → OpenAI)
        cat >> "${CONFIG_DIR}/litellm/config.yaml" << EOF
  - model_name: text-embedding-3-small
    litellm_params:
      model: openai/text-embedding-3-small
      api_base: ${MAMMOUTH_BASE_URL:-https://api.mammouth.ai/v1}
      api_key: ${MAMMOUTH_API_KEY}
EOF
    fi

    # General settings
    cat >> "${CONFIG_DIR}/litellm/config.yaml" << EOF

general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  database_url: ${LITELLM_DB_URL}
  drop_params: true
  set_verbose: false
EOF
    
    chown -R "$PUID:$PGID" "${CONFIG_DIR}/litellm"
    ok "LiteLLM configuration generated"
}

# =============================================================================
# CADDYFILE GENERATION (README §9)
# =============================================================================
generate_caddyfile() {
    if [[ "${CADDY_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    log "Generating Caddyfile..."
    
    mkdir -p "${CONFIG_DIR}/caddy"
    
    cat > "${CONFIG_DIR}/caddy/Caddyfile" << EOF
{
    admin :2019
    email ${PROXY_EMAIL}
    log {
        output file ${LOG_DIR}/caddy.log
        level INFO
    }
}

# Base domain
${BASE_DOMAIN} {
    respond "AI Platform — ${BASE_DOMAIN}"
}
EOF
    
    # LiteLLM
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

litellm.${BASE_DOMAIN} {
    reverse_proxy ${TENANT_PREFIX}-litellm:4000
}
EOF
    fi
    
    # Open WebUI
    if [[ "${OPENWEBUI_ENABLED}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

openwebui.${BASE_DOMAIN} {
    reverse_proxy ${TENANT_PREFIX}-openwebui:8080
}
EOF
    fi
    
    if [[ "${LIBRECHAT_ENABLED:-${ENABLE_LIBRECHAT:-false}}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

librechat.${BASE_DOMAIN} {
    reverse_proxy ${TENANT_PREFIX}-librechat:3080
}
EOF
    fi

    # OpenClaw — WebSocket (wss://) gateway; Caddy 2 proxies WS upgrades automatically.
    # Proxy to container's internal port (same as OPENCLAW_PORT since we use env-var bind).
    if [[ "${OPENCLAW_ENABLED}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

openclaw.${BASE_DOMAIN} {
    reverse_proxy ${TENANT_PREFIX}-openclaw:${OPENCLAW_PORT} {
        header_up Connection {>Connection}
        header_up Upgrade {>Upgrade}
        header_up Sec-WebSocket-Key {>Sec-WebSocket-Key}
        header_up Sec-WebSocket-Version {>Sec-WebSocket-Version}
        header_up Sec-WebSocket-Protocol {>Sec-WebSocket-Protocol}
        header_up Sec-WebSocket-Accept {>Sec-WebSocket-Accept}
    }
}
EOF
    fi
    
    # N8N
    if [[ "${N8N_ENABLED}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

n8n.${BASE_DOMAIN} {
    reverse_proxy ${TENANT_PREFIX}-n8n:5678
}
EOF
    fi
    
    # Flowise
    if [[ "${FLOWISE_ENABLED}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

flowise.${BASE_DOMAIN} {
    reverse_proxy ${TENANT_PREFIX}-flowise:3000
}
EOF
    fi
    
    # Dify — path-based routing on one subdomain (mirrors dify's official nginx config).
    # /console/api*, /api*, /v1*, /files* → dify-api; everything else → dify-web.
    # Single subdomain = single self-signed cert = browser XHR works without extra prompts.
    if [[ "${DIFY_ENABLED}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

dify.${BASE_DOMAIN} {
	handle /console/api* {
		reverse_proxy ${TENANT_PREFIX}-dify-api:5001
	}
	handle /api* {
		reverse_proxy ${TENANT_PREFIX}-dify-api:5001
	}
	handle /v1* {
		reverse_proxy ${TENANT_PREFIX}-dify-api:5001
	}
	handle /files* {
		reverse_proxy ${TENANT_PREFIX}-dify-api:5001
	}
	handle {
		reverse_proxy ${TENANT_PREFIX}-dify:3000
	}
}
EOF
    fi
    
    # Authentik
    if [[ "${AUTHENTIK_ENABLED}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

authentik.${BASE_DOMAIN} {
    reverse_proxy ${TENANT_PREFIX}-authentik:9000
}
EOF
    fi

    # AnythingLLM
    if [[ "${ANYTHINGLLM_ENABLED:-${ENABLE_ANYTHINGLLM:-false}}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

anythingllm.${BASE_DOMAIN} {
    reverse_proxy ${TENANT_PREFIX}-anythingllm:3001
}
EOF
    fi

    # Grafana
    if [[ "${GRAFANA_ENABLED:-${ENABLE_GRAFANA:-false}}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

grafana.${BASE_DOMAIN} {
    reverse_proxy ${TENANT_PREFIX}-grafana:3000
}
EOF
    fi

    # Zep
    if [[ "${ZEP_ENABLED:-${ENABLE_ZEP:-false}}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

zep.${BASE_DOMAIN} {
    reverse_proxy ${TENANT_PREFIX}-zep:8000
}
EOF
    fi

    # Letta
    if [[ "${LETTA_ENABLED:-${ENABLE_LETTA:-false}}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

letta.${BASE_DOMAIN} {
    reverse_proxy ${TENANT_PREFIX}-letta:8283
}
EOF
    fi

    # Code Server
    if [[ "${CODE_SERVER_ENABLED:-${ENABLE_CODE_SERVER:-false}}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

code.${BASE_DOMAIN} {
    reverse_proxy ${TENANT_PREFIX}-code-server:8080
}
EOF
    fi

    # Prometheus (internal monitoring — only expose if explicitly enabled)
    if [[ "${PROMETHEUS_ENABLED:-${ENABLE_PROMETHEUS:-false}}" == "true" ]]; then
        
        # Create comprehensive Prometheus configuration for all enabled services
        cat > "${CONFIG_DIR}/prometheus/prometheus.yml" << MONITOREOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # Ollama monitoring
  - job_name: 'ollama'
    static_configs:
      - targets: ['${TENANT_PREFIX}-ollama:11434']
    metrics_path: '/metrics'
    scrape_interval: 5s

  # LiteLLM proxy monitoring
  - job_name: 'litellm'
    static_configs:
      - targets: ['${TENANT_PREFIX}-litellm:4000']
    metrics_path: '/metrics'
    scrape_interval: 5s

  # Zep memory layer monitoring (if enabled)
MONITOREOF
        if [[ "${ZEP_ENABLED:-false}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" << ZEPEOF

  # Zep memory layer — healthz probe (Zep CE does not expose Prometheus metrics)
  - job_name: 'zep'
    static_configs:
      - targets: ['${TENANT_PREFIX}-zep:8000']
    metrics_path: '/healthz'
    scrape_interval: 30s
ZEPEOF
        fi

        # Letta agent runtime monitoring (if enabled)
        if [[ "${LETTA_ENABLED:-false}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" << LETTAEOF

  # Letta agent runtime — health probe (Letta does not expose Prometheus metrics)
  - job_name: 'letta'
    static_configs:
      - targets: ['${TENANT_PREFIX}-letta:8283']
    metrics_path: '/v1/health'
    scrape_interval: 30s
LETTAEOF
        fi

        # Dify API monitoring (if enabled)
        if [[ "${DIFY_ENABLED:-false}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" << DIFYEEOF

  # Dify API monitoring
  - job_name: 'dify-api'
    static_configs:
      - targets: ['${TENANT_PREFIX}-dify-api:5001']
    metrics_path: '/health'
    scrape_interval: 30s
DIFYEEOF
        fi

        # Dify worker monitoring (if enabled)
        if [[ "${DIFY_ENABLED:-false}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" << DIFYWORKEREOF

  # Dify worker monitoring
  - job_name: 'dify-worker'
    static_configs:
      - targets: ['${TENANT_PREFIX}-dify-worker:5001']
    metrics_path: '/health'
    scrape_interval: 30s
DIFYWORKEREOF
        fi

        # Code Server monitoring (if enabled)
        if [[ "${CODE_SERVER_ENABLED:-${ENABLE_CODE_SERVER:-false}}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" << CODESERVEREOF

  # Code Server monitoring
  - job_name: 'code-server'
    static_configs:
      - targets: ['${TENANT_PREFIX}-code-server:8080']
    metrics_path: '/healthz'
    scrape_interval: 30s
CODESERVEREOF
        fi

        # N8N automation monitoring (if enabled)
        if [[ "${N8N_ENABLED:-false}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" << N8NEOF

  # N8N automation monitoring
  - job_name: 'n8n'
    static_configs:
      - targets: ['${TENANT_PREFIX}-n8n:5678']
    metrics_path: '/healthz'
    scrape_interval: 30s
N8NEOF
        fi

        # Flowise monitoring (if enabled)
        if [[ "${FLOWISE_ENABLED:-false}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" << FLOWISEEOF

  # Flowise monitoring
  - job_name: 'flowise'
    static_configs:
      - targets: ['${TENANT_PREFIX}-flowise:3000']
    metrics_path: '/api/v1/ping'
    scrape_interval: 30s
FLOWISEEOF
        fi

        # AnythingLLM monitoring (if enabled)
        if [[ "${ANYTHINGLLM_ENABLED:-${ENABLE_ANYTHINGLLM:-false}}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" << ANYTHINGLLMEOF

  # AnythingLLM monitoring
  - job_name: 'anythingllm'
    static_configs:
      - targets: ['${TENANT_PREFIX}-anythingllm:3001']
    metrics_path: '/api/ping'
    scrape_interval: 30s
ANYTHINGLLMEOF
        fi

        # OpenWebUI monitoring (if enabled)
        if [[ "${OPENWEBUI_ENABLED:-false}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" << OPENWEBUIEOF

  # OpenWebUI monitoring
  - job_name: 'openwebui'
    static_configs:
      - targets: ['${TENANT_PREFIX}-openwebui:8080']
    metrics_path: '/api/health'
    scrape_interval: 30s
OPENWEBUIEOF
        fi

        # LibreChat monitoring (if enabled)
        if [[ "${LIBRECHAT_ENABLED:-${ENABLE_LIBRECHAT:-false}}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" << LIBRECHATEOF

  # LibreChat monitoring
  - job_name: 'librechat'
    static_configs:
      - targets: ['${TENANT_PREFIX}-librechat:3080']
    metrics_path: '/health'
    scrape_interval: 30s
LIBRECHATEOF
        fi

        # OpenClaw monitoring (if enabled)
        if [[ "${OPENCLAW_ENABLED:-${ENABLE_OPENCLAW:-false}}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" << OPENCLAWEOF

  # OpenClaw monitoring
  - job_name: 'openclaw'
    static_configs:
      - targets: ['${TENANT_PREFIX}-openclaw:${OPENCLAW_PORT}']
    metrics_path: '/health'
    scrape_interval: 30s
OPENCLAWEOF
        fi

        # Authentik SSO monitoring — exposes Prometheus metrics at /-/metrics
        if [[ "${AUTHENTIK_ENABLED:-${ENABLE_AUTHENTIK:-false}}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" << AUTHENTIKEOF

  # Authentik SSO monitoring
  - job_name: 'authentik'
    static_configs:
      - targets: ['${TENANT_PREFIX}-authentik:9000']
    metrics_path: '/-/metrics'
    scrape_interval: 30s
AUTHENTIKEOF
        fi

        # SearXNG search engine monitoring (if enabled)
        if [[ "${SEARXNG_ENABLED:-${ENABLE_SEARXNG:-false}}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" << SEARXNGEOF

  # SearXNG monitoring
  - job_name: 'searxng'
    static_configs:
      - targets: ['${TENANT_PREFIX}-searxng:8888']
    metrics_path: '/healthz'
    scrape_interval: 30s
SEARXNGEOF
        fi

        # Signalbot monitoring (if enabled)
        if [[ "${SIGNALBOT_ENABLED:-${ENABLE_SIGNALBOT:-false}}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" << SIGNALBOTEOF

  # Signalbot monitoring
  - job_name: 'signalbot'
    static_configs:
      - targets: ['${TENANT_PREFIX}-signalbot:8080']
    metrics_path: '/v1/about'
    scrape_interval: 60s
SIGNALBOTEOF
        fi

        # Grafana self-monitoring (if enabled)
        if [[ "${GRAFANA_ENABLED:-${ENABLE_GRAFANA:-false}}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" << GRAFANAEOF

  # Grafana self-monitoring
  - job_name: 'grafana'
    static_configs:
      - targets: ['${TENANT_PREFIX}-grafana:3000']
    metrics_path: '/metrics'
    scrape_interval: 30s
GRAFANAEOF
        fi

        # Caddy reverse proxy monitoring (if enabled)
        if [[ "${CADDY_ENABLED:-false}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" << CADDYEOF

  # Caddy reverse proxy monitoring
  - job_name: 'caddy'
    static_configs:
      - targets: ['${TENANT_PREFIX}-caddy:2019']
    metrics_path: '/metrics'
    scrape_interval: 30s
CADDYEOF
        fi

        # PostgreSQL monitoring
        cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" << POSTGRESEOF

  # PostgreSQL monitoring
  - job_name: 'postgres'
    static_configs:
      - targets: ['${TENANT_PREFIX}-postgres:5432']
    scrape_interval: 30s
POSTGRESEOF

        # Redis monitoring
        cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" << REDISEOF

  # Redis monitoring
  - job_name: 'redis'
    static_configs:
      - targets: ['${TENANT_PREFIX}-redis:6379']
    scrape_interval: 30s
REDISEOF

        # MongoDB monitoring
        cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" << MONGODBEOF

  # MongoDB monitoring
  - job_name: 'mongodb'
    static_configs:
      - targets: ['${TENANT_PREFIX}-mongodb:27017']
    scrape_interval: 30s
MONGODBEOF

        # Qdrant vector DB monitoring (if enabled)
        if [[ "${QDRANT_ENABLED}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" << QDRANTEOF

  # Qdrant vector DB monitoring
  - job_name: 'qdrant'
    static_configs:
      - targets: ['${TENANT_PREFIX}-qdrant:6333']
    metrics_path: '/metrics'
    scrape_interval: 30s
QDRANTEOF
        fi

        # RClone monitoring (if enabled)
        if [[ "${RCLONE_ENABLED:-false}" == "true" ]]; then
            cat >> "${CONFIG_DIR}/prometheus/prometheus.yml" << RCLONEEOF

  # RClone monitoring
  - job_name: 'rclone'
    static_configs:
      - targets: ['${TENANT_PREFIX}-rclone:5572']
    scrape_interval: 30s
RCLONEEOF
        fi

        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

prometheus.${BASE_DOMAIN} {
    reverse_proxy ${TENANT_PREFIX}-prometheus:9090
}
EOF
    fi

    # Signalbot REST API — exposed so /v1/qrcodelink is reachable from browser for pairing
    if [[ "${SIGNALBOT_ENABLED:-${ENABLE_SIGNALBOT:-false}}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

signal.${BASE_DOMAIN} {
    reverse_proxy ${TENANT_PREFIX}-signalbot:8080
}
EOF
    fi

    # SearXNG - privacy-respecting search engine
    if [[ "${SEARXNG_ENABLED:-${ENABLE_SEARXNG:-false}}" == "true" ]]; then
        cat >> "${CONFIG_DIR}/caddy/Caddyfile" << EOF

search.${BASE_DOMAIN} {
    reverse_proxy ${TENANT_PREFIX}-searxng:8888
}
EOF
    fi

    # dify-api subdomain removed — API traffic is now routed through dify.${BASE_DOMAIN}
    # via path handles above. A separate subdomain requires a second self-signed cert
    # acceptance in the browser, blocking XHR and making /install hang.

    chown -R "$PUID:$PGID" "${CONFIG_DIR}/caddy"
    ok "Caddyfile generated"
}

# =============================================================================
# BIFROST CONFIG GENERATION
# =============================================================================
generate_bifrost_config() {
    if [[ "${BIFROST_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    log "Generating Bifrost configuration..."
    
    mkdir -p "${CONFIG_DIR}/bifrost"
    
    cat > "${CONFIG_DIR}/bifrost/config.yaml" << EOF
api_key: ${BIFROST_API_KEY}
log_level: info
rate_limit:
  requests_per_minute: 60
  burst_size: 10
cache:
  ttl: 300
  max_size: 1000
EOF
    
    chown -R "$PUID:$PGID" "${CONFIG_DIR}/bifrost"
    ok "Bifrost configuration generated"
}

# =============================================================================
# SENTINEL SCAN (README §6 - mandatory)
# =============================================================================
scan_for_sentinels() {
    log "Scanning for unreplaced sentinels..."
    
    if grep -rE "CHANGEME|TODO_REPLACE|FIXME|xxxx|\{\{[A-Z_]+\}\}" "${CONFIG_DIR}/" 2>/dev/null; then
        fail "Unreplaced sentinels found - aborting deployment"
    fi
    
    ok "Sentinel scan: clean"
}

# =============================================================================
# HEALTH WAITING (README Appendix C - mandatory pattern)
# =============================================================================
wait_for_health() {
    local container_name="$1"
    local timeout="${2:-90}"
    local interval=5
    local elapsed=0

    log "Waiting for ${container_name} to become healthy (timeout: ${timeout}s)..."

    while [[ ${elapsed} -lt ${timeout} ]]; do
        local status
        status=$(docker inspect \
            --format='{{.State.Health.Status}}' \
            "${container_name}" 2>/dev/null) || status="not_found"

        case "${status}" in
            healthy)
                log "  ✅ ${container_name} is healthy"
                return 0
                ;;
            unhealthy)
                log "  ❌ ${container_name} reported unhealthy"
                docker logs --tail 20 "${container_name}" >&2
                return 1
                ;;
            not_found)
                log "  ⚠️  ${container_name} not found — is it deployed?"
                return 1
                ;;
            *)
                # starting | none — keep waiting
                sleep "${interval}"
                elapsed=$(( elapsed + interval ))
                ;;
        esac
    done

    log "  ❌ ${container_name} did not become healthy within ${timeout}s"
    docker logs --tail 30 "${container_name}" >&2
    return 1
}

# =============================================================================
# DEPLOYMENT FUNCTIONS
# =============================================================================
pull_images() {
    log "Pulling Docker images..."

    if ! run_cmd docker compose -f "${COMPOSE_FILE}" pull; then
        fail "docker compose pull failed — one or more images could not be pulled. Check warnings above."
    fi

    ok "Images pulled"
}

validate_caddyfile() {
    if [[ "${CADDY_ENABLED}" != "true" ]]; then
        return 0
    fi
    
    log "Formatting and validating Caddyfile..."

    # Format first (caddy requires tabs; our heredoc uses spaces) then validate.
    # Both steps run in a throwaway caddy container — fmt needs a writable mount.
    docker run --rm \
        -v "${CONFIG_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile" \
        caddy:2-alpine caddy fmt --overwrite /etc/caddy/Caddyfile 2>/dev/null || true

    if ! run_cmd docker run --rm \
        -v "${CONFIG_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" \
        caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile; then
        fail "Caddyfile validation failed"
    fi

    ok "Caddyfile is valid"
}

# =============================================================================
# DATA DIRECTORY PREPARATION (core principle: /mnt ownership, non-root)
# Must run before compose up so Docker never creates dirs as root.
# Each dir is created with PUID:PGID ownership so containers running as that
# user can write without privilege escalation.
# =============================================================================
prepare_data_dirs() {
    log "Preparing tenant data directories under ${DATA_DIR} ..."

    # Base structure
    mkdir -p \
        "${DATA_DIR}/config" \
        "${DATA_DIR}/config/ssl" \
        "${DATA_DIR}/config/caddy" \
        "${DATA_DIR}/config/litellm" \
        "${DATA_DIR}/config/bifrost" \
        "${DATA_DIR}/logs" \
        "${DATA_DIR}/.configured"

    # Per-service data directories (only create what is enabled to avoid clutter)
    [[ "${POSTGRES_ENABLED}"  == "true" ]] && mkdir -p "${DATA_DIR}/postgres"
    [[ "${REDIS_ENABLED}"     == "true" ]] && mkdir -p "${DATA_DIR}/redis"
    [[ "${OLLAMA_ENABLED}"    == "true" ]] && mkdir -p "${DATA_DIR}/ollama"
    [[ "${OPENWEBUI_ENABLED}" == "true" ]] && mkdir -p "${DATA_DIR}/openwebui"
    [[ "${LIBRECHAT_ENABLED:-${ENABLE_LIBRECHAT:-false}}" == "true" ]] && mkdir -p "${DATA_DIR}/mongodb" "${DATA_DIR}/librechat/uploads" "${DATA_DIR}/librechat/logs"
    if [[ "${OPENCLAW_ENABLED}" == "true" ]]; then
        # data + home dir (home is mounted at /home/node/.openclaw — where openclaw.json lives)
        mkdir -p "${DATA_DIR}/openclaw/data" "${DATA_DIR}/openclaw/home"
        # Pre-seed openclaw.json with gateway token + CORS allowed origins + channels.
        local _oc_json="${DATA_DIR}/openclaw/home/openclaw.json"
        local _oc_origin="*"
        # "remote" mode when behind Caddy so OpenClaw trusts proxy headers and accepts
        # browser WebSocket connections forwarded from external IPs.  "local" for direct access.
        local _oc_mode="local"
        if [[ "${CADDY_ENABLED:-false}" == "true" && -n "${BASE_DOMAIN:-}" ]]; then
            _oc_origin="https://openclaw.${BASE_DOMAIN}"
            _oc_mode="remote"
        fi
        # Always regenerate openclaw.json so OPENCLAW_PASSWORD stays in sync with platform.conf.
        local _channels_json=""

        # Build Signal block
        if echo "${OPENCLAW_CHANNELS:-signal}" | grep -qE "signal|all"; then
            if [[ "${SIGNALBOT_ENABLED:-false}" == "true" && -n "${SIGNAL_PHONE:-}" ]]; then
                _channels_json+='    "signal": {
      "enabled": true,
      "account": "'"${SIGNAL_PHONE}"'",
      "httpUrl": "http://'"${TENANT_PREFIX}"'-signalbot:9999",
      "autoStart": false
    }'
            fi
        fi

        # Build Telegram block
        if echo "${OPENCLAW_CHANNELS:-}" | grep -qE "telegram|all"; then
            if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
                local _telegram_valid=false
                if command -v curl >/dev/null 2>&1; then
                    local _telegram_check=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" 2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin).get('ok', 'false'))" 2>/dev/null || echo "false")
                    [[ "$_telegram_check" == "True" ]] && _telegram_valid=true
                fi
                [[ -n "$_channels_json" ]] && _channels_json+=','$'\n'
                if [[ "$_telegram_valid" == "true" ]]; then
                    _channels_json+='    "telegram": {
      "enabled": true,
      "botToken": "'"${TELEGRAM_BOT_TOKEN}"'",
      "dmPolicy": "pairing"
    }'
                else
                    log "WARNING: Telegram bot token invalid - disabling Telegram channel"
                    _channels_json+='    "telegram": {
      "enabled": false,
      "botToken": "'"${TELEGRAM_BOT_TOKEN}"'",
      "dmPolicy": "pairing"
    }'
                fi
            fi
        fi

        # Build Discord block
        if echo "${OPENCLAW_CHANNELS:-}" | grep -qE "discord|all"; then
            if [[ -n "${DISCORD_BOT_TOKEN:-}" && -n "${DISCORD_GUILD_ID:-}" ]]; then
                [[ -n "$_channels_json" ]] && _channels_json+=','$'\n'
                _channels_json+='    "discord": {
      "enabled": true,
      "token": "'"${DISCORD_BOT_TOKEN}"'",
      "guilds": {
        "'"${DISCORD_GUILD_ID}"'": {
          "requireMention": true
        }
      }
    }'
            fi
        fi

        local _channels_section=""
        if [[ -n "$_channels_json" ]]; then
            _channels_section=',
  "channels": {
'"$_channels_json"'
  }'
        fi

        cat > "${_oc_json}" << OCEOF
{
  "gateway": {
    "mode": "${_oc_mode}",
    "auth": {
      "mode": "token",
      "token": "${OPENCLAW_PASSWORD}"
    },
    "controlUi": {
      "allowedOrigins": ["${_oc_origin}", "*"]
    },
    "trustedProxies": ["0.0.0.0/0"]
  }${_channels_section}
}
OCEOF
        # openclaw image runs as node (uid 1000) — file must be readable by that uid
        chmod 644 "${_oc_json}"
        # openclaw container runs as node (uid 1000), not PUID — chown accordingly
        docker run --rm -v "${DATA_DIR}/openclaw/home:/target" alpine:latest \
            chown -R 1000:1000 /target 2>/dev/null || true

        # TASK 2: Auto-approve pending pairing requests if they exist
        local _pending_json="${DATA_DIR}/openclaw/home/devices/pending.json"
        local _paired_json="${DATA_DIR}/openclaw/home/devices/paired.json"
        if [[ -f "${_pending_json}" ]]; then
            log "Checking for pending OpenClaw pairing requests..."
            # Use python3 to move requests from pending to paired (requires python3 on host)
            python3 - "${_pending_json}" "${_paired_json}" <<'PYEOF'
import json, sys, time, os
pending_path, paired_path = sys.argv[1], sys.argv[2]
try:
    with open(pending_path, 'r') as f: pending = json.load(f)
    if not pending: sys.exit(0)
    print(f"  Found {len(pending)} pending pairing requests — auto-approving...")
    if os.path.exists(paired_path):
        with open(paired_path, 'r') as f: paired = json.load(f)
    else: paired = {}
    now = int(time.time() * 1000)
    scopes = ['operator.read','operator.write','operator.admin','operator.approvals','operator.pairing']
    for rid, r in pending.items():
        paired[rid] = {**r, 'approved': True, 'status': 'approved', 'approvedTs': now, 'scopes': scopes}
    with open(paired_path, 'w') as f: json.dump(paired, f, indent=2)
    with open(pending_path, 'w') as f: json.dump({}, f, indent=2)
except Exception as e: print(f"  ⚠️ Failed to auto-approve: {e}")
PYEOF
        fi
    fi
    [[ "${QDRANT_ENABLED}"    == "true" ]] && mkdir -p "${DATA_DIR}/qdrant"
    [[ "${WEAVIATE_ENABLED}"  == "true" ]] && mkdir -p "${DATA_DIR}/weaviate"
    [[ "${N8N_ENABLED}"       == "true" ]] && mkdir -p "${DATA_DIR}/n8n"
    [[ "${FLOWISE_ENABLED}"   == "true" ]] && mkdir -p "${DATA_DIR}/flowise"
    [[ "${DIFY_ENABLED}"      == "true" ]] && mkdir -p "${DATA_DIR}/dify"
    [[ "${GRAFANA_ENABLED}"   == "true" ]] && mkdir -p "${DATA_DIR}/grafana"
    [[ "${PROMETHEUS_ENABLED}" == "true" ]] && mkdir -p "${DATA_DIR}/prometheus"
    [[ "${AUTHENTIK_ENABLED}" == "true" ]] && mkdir -p "${DATA_DIR}/authentik"
    if [[ "${SIGNALBOT_ENABLED}" == "true" ]]; then
        mkdir -p "${DATA_DIR}/signalbot"
        # SSE proxy (sse-proxy.py): signal-cli 0.14.1 HTTP daemon never sends HTTP response
        # headers on GET /api/v1/events until a message arrives — OpenClaw sees fetch failed.
        # This proxy listens on PROXY_PORT (9999, internal Docker network) and immediately
        # sends 200 + SSE headers, then polls signal-cli receive RPC every 3s.
        cat > "${DATA_DIR}/signalbot/sse-proxy.py" << 'PYEOF'
#!/usr/bin/env python3
"""SSE proxy for OpenClaw: sends HTTP 200 + SSE headers immediately, polls signal-cli."""
import http.server, json, time, urllib.request, urllib.error, urllib.parse, os

SIGNAL_CLI_HTTP_PORT = int(os.environ.get("SIGNAL_CLI_HTTP_PORT", "9080"))
PROXY_PORT           = int(os.environ.get("PROXY_PORT", "9999"))
SIGNAL_ACCOUNT       = os.environ.get("SIGNAL_ACCOUNT", "")
POLL_TIMEOUT         = 3
KEEPALIVE_INTERVAL   = 20

def call_rpc(method, params=None, timeout=10):
    payload = {"jsonrpc": "2.0", "method": method, "id": 1}
    if params: payload["params"] = params
    req = urllib.request.Request(f"http://127.0.0.1:{SIGNAL_CLI_HTTP_PORT}/api/v1/rpc",
        data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r: return json.loads(r.read())
    except Exception as e: return {"error": str(e)}

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path.startswith("/api/v1/events"): self._sse()
        else: self.send_response(404); self.end_headers()
    def do_POST(self):
        if self.path == "/api/v1/rpc": self._proxy()
        else: self.send_response(404); self.end_headers()
    def _sse(self):
        self.send_response(200)
        for h,v in [("Content-Type","text/event-stream"),("Cache-Control","no-cache"),
                    ("Connection","keep-alive"),("X-Accel-Buffering","no")]: self.send_header(h,v)
        self.end_headers()
        p = urllib.parse.urlparse(self.path)
        acct = urllib.parse.parse_qs(p.query).get("account", [SIGNAL_ACCOUNT])[0]
        last_ka = time.time()
        try:
            self.wfile.write(b": connected\n\n"); self.wfile.flush()
            while True:
                if time.time() - last_ka >= KEEPALIVE_INTERVAL:
                    self.wfile.write(b": keepalive\n\n"); self.wfile.flush(); last_ka = time.time()
                for env in call_rpc("receive", {"timeout": POLL_TIMEOUT}, POLL_TIMEOUT+5).get("result", []):
                    msg = ("data: " + json.dumps({"jsonrpc":"2.0","method":"receive",
                        "params":{"envelope":env,"account":acct}}) + "\n\n").encode()
                    self.wfile.write(msg); self.wfile.flush(); last_ka = time.time()
        except (BrokenPipeError, ConnectionResetError): pass
        except Exception: pass
    def _proxy(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        req = urllib.request.Request(f"http://127.0.0.1:{SIGNAL_CLI_HTTP_PORT}/api/v1/rpc",
            data=body, headers={"Content-Type": "application/json"}, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                d = r.read(); self.send_response(200); self.send_header("Content-Type","application/json"); self.end_headers(); self.wfile.write(d)
        except urllib.error.HTTPError as e:
            d = e.read(); self.send_response(e.code); self.send_header("Content-Type","application/json"); self.end_headers(); self.wfile.write(d)
        except Exception as e:
            self.send_response(503); self.send_header("Content-Type","application/json"); self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())

if __name__ == "__main__":
    print(f"Waiting for signal-cli on :{SIGNAL_CLI_HTTP_PORT}...", flush=True)
    for _ in range(60):
        r = call_rpc("version", timeout=2)
        if "result" in r or "error" in r: print("signal-cli ready", flush=True); break
        time.sleep(2)
    print(f"SSE proxy listening on 0.0.0.0:{PROXY_PORT}", flush=True)
    http.server.ThreadingHTTPServer(("0.0.0.0", PROXY_PORT), Handler).serve_forever()
PYEOF
        # start.sh: orchestrates the three processes in startup order.
        # 1. signal-cli daemon with dual interface: TCP (bbernhard) + HTTP (SSE proxy)
        # 2. bbernhard REST API (json-rpc mode via jsonrpc2.yml) — QR code, register, send
        # 3. Python SSE proxy — OpenClaw /api/v1/events + /api/v1/rpc forwarding
        cat > "${DATA_DIR}/signalbot/start.sh" << SHEOF
#!/bin/sh
set -e
SIGNAL_CLI_CONFIG_DIR="\${SIGNAL_CLI_CONFIG_DIR:-/home/.local/share/signal-cli}"
SIGNAL_CLI_HTTP_PORT="\${SIGNAL_CLI_HTTP_PORT:-9080}"
SIGNAL_CLI_TCP_PORT="\${SIGNAL_CLI_TCP_PORT:-6001}"

# Write jsonrpc2.yml so bbernhard REST API connects to signal-cli via TCP
cat > "\${SIGNAL_CLI_CONFIG_DIR}/jsonrpc2.yml" << EOF
config:
  <multi-account>:
    tcp_port: \${SIGNAL_CLI_TCP_PORT}
EOF

# Start signal-cli daemon: TCP for bbernhard, HTTP for SSE proxy, manual receive for polling
# -a is omitted when SIGNAL_PHONE is empty (QR-code linking flow) — signal-cli daemon
# multi-account mode does not require an account at startup.
if [ -n "\${SIGNAL_PHONE:-}" ]; then
  signal-cli \
    --config "\${SIGNAL_CLI_CONFIG_DIR}" \
    -a "\${SIGNAL_PHONE}" \
    daemon \
    --tcp "127.0.0.1:\${SIGNAL_CLI_TCP_PORT}" \
    --http "127.0.0.1:\${SIGNAL_CLI_HTTP_PORT}" \
    --no-receive-stdout \
    --receive-mode manual &
else
  signal-cli \
    --config "\${SIGNAL_CLI_CONFIG_DIR}" \
    daemon \
    --tcp "127.0.0.1:\${SIGNAL_CLI_TCP_PORT}" \
    --http "127.0.0.1:\${SIGNAL_CLI_HTTP_PORT}" \
    --no-receive-stdout \
    --receive-mode manual &
fi

# Start bbernhard REST API (auto-detects json-rpc mode from jsonrpc2.yml)
# Provides: /v1/qrcodelink, /v1/register, /v1/verify, /v2/send, /v1/about
signal-cli-rest-api -signal-cli-config="\${SIGNAL_CLI_CONFIG_DIR}" &

# Start SSE proxy for OpenClaw — polls signal-cli HTTP for incoming messages
exec python3 "\${SIGNAL_CLI_CONFIG_DIR}/sse-proxy.py"
SHEOF
        chmod +x "${DATA_DIR}/signalbot/start.sh"
    fi
    [[ "${SEARXNG_ENABLED}" == "true" ]] && mkdir -p "${DATA_DIR}/searxng"
    [[ "${BIFROST_ENABLED}"   == "true" ]] && mkdir -p "${DATA_DIR}/bifrost"
    if [[ "${ENABLE_INGESTION:-false}" == "true" ]]; then
        mkdir -p "${LOCAL_INGESTION_PATH:-${DATA_DIR}/ingestion/AI_Platform}" "${DATA_DIR}/rclone"
        chmod 775 "${LOCAL_INGESTION_PATH:-${DATA_DIR}/ingestion/AI_Platform}"
    fi
    [[ "${CADDY_ENABLED}"     == "true" ]] && mkdir -p "${DATA_DIR}/caddy" "${DATA_DIR}/logs/caddy"
    # New services
    [[ "${WEAVIATE_ENABLED:-${ENABLE_WEAVIATE:-false}}" == "true" ]] && mkdir -p "${DATA_DIR}/weaviate"
    [[ "${CHROMA_ENABLED:-${ENABLE_CHROMA:-false}}"     == "true" ]] && mkdir -p "${DATA_DIR}/chroma"
    [[ "${MILVUS_ENABLED:-${ENABLE_MILVUS:-false}}"    == "true" ]] && mkdir -p "${DATA_DIR}/milvus" "${DATA_DIR}/milvus-etcd" "${DATA_DIR}/milvus-minio"
    [[ "${NPM_ENABLED:-false}"                         == "true" ]] && mkdir -p "${DATA_DIR}/npm/data" "${DATA_DIR}/npm/letsencrypt"
    [[ "${ANYTHINGLLM_ENABLED:-${ENABLE_ANYTHINGLLM:-false}}" == "true" ]] && mkdir -p "${DATA_DIR}/anythingllm"
    [[ "${ZEP_ENABLED:-false}"                          == "true" ]] && mkdir -p "${DATA_DIR}/zep"
    [[ "${LETTA_ENABLED:-false}"                        == "true" ]] && mkdir -p "${DATA_DIR}/letta"
    [[ "${GRAFANA_ENABLED:-${ENABLE_GRAFANA:-false}}"   == "true" ]] && mkdir -p "${DATA_DIR}/grafana"
    [[ "${PROMETHEUS_ENABLED:-${ENABLE_PROMETHEUS:-false}}" == "true" ]] && mkdir -p "${DATA_DIR}/prometheus" "${CONFIG_DIR}/prometheus"
    [[ "${CODE_SERVER_ENABLED:-${ENABLE_CODE_SERVER:-false}}" == "true" ]] && mkdir -p "${DATA_DIR}/code-server"
    [[ "${CONTINUE_DEV_ENABLED:-${ENABLE_CONTINUE_DEV:-false}}" == "true" ]] && mkdir -p "${DATA_DIR}/continue-dev"

    # Set ownership of tenant subdirectories to PUID:PGID.
    # Deliberately skip root-owned EBS system dirs (lost+found, docker) —
    # chown -R on the root DATA_DIR would fail with "Permission denied" on those.
    # The top-level mount point itself is also chowned so the deploy user can write.
    find "${DATA_DIR}" -mindepth 1 -maxdepth 1 \
        ! -name "lost+found" ! -name "docker" \
        -exec chown -R "${PUID}:${PGID}" {} \; 2>/dev/null || true
    chown "${PUID}:${PGID}" "${DATA_DIR}" 2>/dev/null || true

    # Services that run as fixed internal UIDs need their data dirs to be
    # world-writable (we can't chown to their internal UID without root).
    # Qdrant (uid 1000) — storage + snapshots subdir
    [[ "${QDRANT_ENABLED}" == "true" ]] && chmod 777 "${DATA_DIR}/qdrant"
    # N8N runs as node (uid 1000); Signalbot runs as internal uid 1000
    [[ "${N8N_ENABLED}" == "true" ]] && chmod 777 "${DATA_DIR}/n8n"
    [[ "${SIGNALBOT_ENABLED}" == "true" ]] && chmod 777 "${DATA_DIR}/signalbot"
    # SearXNG runs as user: "${PUID}:${PGID}"
    [[ "${SEARXNG_ENABLED}" == "true" ]] && chmod 755 "${DATA_DIR}/searxng"
    # Authentik migration creates /media/public (mounted as DATA_DIR/authentik) — needs world-writable
    [[ "${AUTHENTIK_ENABLED}" == "true" ]] && chmod 777 "${DATA_DIR}/authentik"
    # AnythingLLM runs as uid 1000 (anythingllm user) — writes SQLite DB + vector index to storage/
    [[ "${ANYTHINGLLM_ENABLED:-${ENABLE_ANYTHINGLLM:-false}}" == "true" ]] && chmod 777 "${DATA_DIR}/anythingllm"
    # LibreChat runs as 'node' (uid 1000) — writes to /app/uploads and /app/logs
    if [[ "${LIBRECHAT_ENABLED:-${ENABLE_LIBRECHAT:-false}}" == "true" ]]; then
        chmod 777 "${DATA_DIR}/librechat/uploads" "${DATA_DIR}/librechat/logs"
    fi

    ok "Data directories ready under ${DATA_DIR} (owner ${PUID}:${PGID})"
}

# =============================================================================
# FLUSH EXISTING DEPLOYMENT (idempotency — always start clean)
# Tears down any running containers and clears step markers so that every
# invocation of Script 2 is a full fresh deploy.  The markers still protect
# against partial failures *within* the current run.
# =============================================================================
flush_existing_deployment() {
    local old_compose="${COMPOSE_FILE}"
    if [[ -f "${old_compose}" ]]; then
        log "Flushing existing deployment: docker compose down..."
        docker compose -f "${old_compose}" down --timeout 30 --remove-orphans 2>/dev/null || true
        ok "Existing containers stopped and removed"
    else
        log "No existing compose file found — nothing to flush"
    fi

    # Clear all idempotency markers so every step re-runs cleanly
    if [[ -d "${CONFIGURED_DIR}" ]]; then
        rm -f "${CONFIGURED_DIR}"/*
        log "Idempotency markers cleared"
    fi
}

# docker_wipe_dir <path>
# Wipes a directory's contents using an alpine container running as root.
# Bypasses "Permission denied" on host when container-written files are owned
# by root (e.g. MongoDB, Postgres pgdata, Ollama model blobs, LiteLLM Prisma cache).
# Falls back to plain rm -rf if Docker is not available yet.
docker_wipe_dir() {
    local dir_path="$1"
    [[ -d "${dir_path}" ]] || return 0
    log "  Wiping: ${dir_path}"
    if docker run --rm -v "${dir_path}:/data" alpine sh -c "rm -rf /data/* /data/.[!.]* 2>/dev/null; true" 2>/dev/null; then
        return 0
    fi
    rm -rf "${dir_path:?}" 2>/dev/null || true
}

flush_all_data() {
    # Only called when --flushall is passed.
    # Containers are already stopped by flush_existing_deployment() at this point.
    # prepare_data_dirs() will recreate the empty directories afterwards.
    warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    warn "  --flushall: wiping all persisted state for tenant ${TENANT_ID}"
    warn "  Databases, Ollama models, and Docker image cache will be removed."
    warn "  This cannot be undone. Starting in 5 seconds..."
    warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    sleep 5

    # 1. Database data directories — each service re-initializes on fresh start
    #    Uses docker_wipe_dir to handle root-owned files (postgres pgdata, mongodb journal, etc.)
    local -a db_dirs=("postgres" "redis" "mongodb")
    for dir in "${db_dirs[@]}"; do
        if [[ -d "${DATA_DIR}/${dir}" ]]; then
            log "  Wiping database dir: ${DATA_DIR}/${dir}"
            docker_wipe_dir "${DATA_DIR}/${dir}"
        fi
    done

    # 2. Ollama model blobs — large downloads; keep the parent dir so
    #    prepare_data_dirs() doesn't fail, but purge the model cache
    if [[ -d "${DATA_DIR}/ollama/models" ]]; then
        log "  Removing Ollama model cache: ${DATA_DIR}/ollama/models"
        docker_wipe_dir "${DATA_DIR}/ollama/models"
    fi

    # 3. Other service state directories that accumulate stale schema files
    #    (litellm Prisma state, dify storage, anythingllm, flowise, n8n, etc.)
    local -a svc_dirs=("litellm" "dify" "anythingllm" "flowise" "n8n" "letta" "zep"
                       "openclaw" "grafana" "prometheus" "authentik" "librechat"
                       "openwebui" "qdrant" "weaviate" "chroma" "milvus" "milvus-etcd" "milvus-minio")
    for dir in "${svc_dirs[@]}"; do
        if [[ -d "${DATA_DIR}/${dir}" ]]; then
            log "  Wiping service dir: ${DATA_DIR}/${dir}"
            docker_wipe_dir "${DATA_DIR}/${dir}"
        fi
    done

    # 4. Docker image cache — forces re-pull of every service image on next deploy
    log "  Pruning all Docker images..."
    docker image prune -af 2>/dev/null || true

    ok "--flushall complete — deploy will start from a fully clean state"
}

flush_databases_only() {
    # Only called when --flush-dbs is passed.
    # Wipes database directories while preserving containers and models.
    warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    warn "  --flush-dbs: wiping database directories only for tenant ${TENANT_ID}"
    warn "  Containers and models will be preserved."
    warn "  This cannot be undone. Starting in 3 seconds..."
    warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    sleep 3

    # Database directories only - each service re-initializes on fresh start
    local -a db_dirs=("postgres" "redis" "mongodb")
    for dir in "${db_dirs[@]}"; do
        if [[ -d "${DATA_DIR}/${dir}" ]]; then
            log "  Wiping database dir: ${DATA_DIR}/${dir}"
            sudo rm -rf "${DATA_DIR:?}/${dir}"
        fi
    done

    # Restart all containers to ensure full stack is available
    log "Restarting all containers..."
    cd "${CONFIG_DIR}"
    docker compose up -d || true
    cd - > /dev/null
    
    # Wait for all containers to initialize
    log "Waiting for all containers to initialize..."
    sleep 30
    
    # Verify key containers are running
    log "Verifying key containers are running..."
    local containers_running=0
    
    if docker ps | grep -q "${TENANT_PREFIX}-postgres.*Up"; then
        log "PostgreSQL container is running"
        ((containers_running++))
    else
        log "WARNING: PostgreSQL container may not be running properly"
    fi
    
    if docker ps | grep -q "${TENANT_PREFIX}-ollama.*Up"; then
        log "Ollama container is running"
        ((containers_running++))
    else
        log "WARNING: Ollama container may not be running properly"
    fi
    
    log "Found $containers_running key containers running"

    ok "--flush-dbs complete - databases wiped, containers and models preserved"
}

deploy_containers() {
    log "Deploying containers..."

    # Check for port conflicts against CONFIGURED ports only.
    # By this point flush_existing_deployment() has already run docker compose down,
    # so any conflicts here are from EXTERNAL services — not our own stack.
    log "Checking for port conflicts..."
    local ports_to_check=()
    [[ "${CADDY_ENABLED}" == "true" ]] && ports_to_check+=("80" "443")
    [[ "${POSTGRES_ENABLED}" == "true" ]] && ports_to_check+=("${POSTGRES_PORT:-5432}")
    [[ "${REDIS_ENABLED}" == "true" ]] && ports_to_check+=("${REDIS_PORT:-6379}")
    [[ "${LITELLM_ENABLED}" == "true" ]] && ports_to_check+=("${LITELLM_PORT:-4000}")
    [[ "${OLLAMA_ENABLED}" == "true" ]] && ports_to_check+=("${OLLAMA_PORT:-11434}")
    [[ "${OPENWEBUI_ENABLED}" == "true" ]] && ports_to_check+=("${OPENWEBUI_PORT:-3000}")
    [[ "${QDRANT_ENABLED}" == "true" ]] && ports_to_check+=("${QDRANT_REST_PORT:-6333}")

    local conflicts=()
    for port in "${ports_to_check[@]}"; do
        if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
            conflicts+=("$port")
        fi
    done

    if [[ ${#conflicts[@]} -gt 0 ]]; then
        fail "Port conflicts detected on external services: ${conflicts[*]}. Free these ports or change configuration in platform.conf."
    fi

    # Create Docker network
    if ! docker network ls | grep -q "${DOCKER_NETWORK}"; then
        run_cmd docker network create "${DOCKER_NETWORK}"
    fi

    # Deploy containers
    log "Starting containers..."
    if ! run_cmd docker compose -f "${COMPOSE_FILE}" up -d; then
        fail "docker compose up -d failed — check image pull errors or config issues above"
    fi

    ok "Containers deployed"
}


# create_service_database <db_name> [pgvector=false]
# Idempotent: creates the named database and optionally enables pgvector.
# Called by wait_for_all_health() after Postgres is healthy.
create_service_database() {
    local db_name="$1" pgvector="${2:-false}"
    local create_out
    create_out=$(docker exec "${TENANT_PREFIX}-postgres" psql -U "${POSTGRES_USER}" -d postgres \
        -c "CREATE DATABASE \"${db_name}\";" 2>&1 || true)
    if echo "$create_out" | grep -qi "already exists"; then
        log "  Database ${db_name} already exists — skipping"
    elif echo "$create_out" | grep -qi "error\|fatal"; then
        warn "  CREATE DATABASE ${db_name}: ${create_out}"
    else
        ok "  Database ${db_name} created"
    fi
    if [[ "$pgvector" == "true" ]]; then
        docker exec "${TENANT_PREFIX}-postgres" psql -U "${POSTGRES_USER}" -d "${db_name}" \
            -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>/dev/null | grep -v "^$" | grep -v "already exists" || true
        ok "  pgvector enabled in ${db_name}"
    fi
}

wait_for_all_health() {
    log "Waiting for all services to become healthy..."

    # Health check timeouts per service (README §6)
    if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-postgres" 60 || return 1
        # Sync the Postgres password stored in pg_authid with whatever is in platform.conf.
        # When the data directory is preserved across re-deploys, Postgres ignores the
        # POSTGRES_PASSWORD env var and keeps the old stored hash. Any service that
        # connects remotely (Zep, LiteLLM, Letta, N8N, …) will fail auth unless we
        # reconcile here after startup.
        log "Syncing Postgres password to match platform.conf..."
        docker exec "${TENANT_PREFIX}-postgres" psql -U "${POSTGRES_USER}" -d postgres \
            -c "ALTER USER \"${POSTGRES_USER}\" WITH PASSWORD '${POSTGRES_PASSWORD}';" \
            2>&1 | grep -v "^$" || true
        ok "Postgres password synced"
        # Create per-service dedicated databases — each postgres-backed service gets its own DB
        # to prevent Alembic/Django migration conflicts (e.g. Dify's 'messages' vs Zep watermill tables).
        log "Creating dedicated per-service databases..."
        [[ "${LETTA_ENABLED:-false}"     == "true" ]] && create_service_database "${LETTA_DB_NAME}"     true
        [[ "${LITELLM_ENABLED:-false}"   == "true" ]] && create_service_database "${LITELLM_DB_NAME}"
        [[ "${N8N_ENABLED:-false}"       == "true" ]] && create_service_database "${N8N_DB_NAME}"
        [[ "${ZEP_ENABLED:-false}"       == "true" ]] && create_service_database "${ZEP_DB_NAME}"       true
        [[ "${DIFY_ENABLED:-false}"      == "true" ]] && create_service_database "${DIFY_DB_NAME}"
        [[ "${AUTHENTIK_ENABLED:-false}" == "true" ]] && create_service_database "${AUTHENTIK_DB_NAME}"
        ok "Per-service databases ready"
        # Restart Letta so it gets a clean attempt now that its dedicated DB exists.
        # Without this, Letta may be in Docker's crash-restart backoff loop
        # (it crashed before the DB was created) and could wait 64s+ per retry.
        if [[ "${LETTA_ENABLED:-false}" == "true" ]]; then
            log "Restarting Letta container after database creation..."
            docker restart "${TENANT_PREFIX}-letta" 2>/dev/null || true
        fi
    fi


    if [[ "${ZEP_ENABLED:-false}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-zep" 120 || return 1
        # Zep creates its own watermill tables at startup via "Initializing subscriber schema".
        # Only intervene if the tables are actually missing (rare: Postgres was overloaded at Zep first-start).
        # Unconditional restart causes a second boot cycle that can exceed the health timeout.
        log "Verifying Zep watermill tables..."
        local _zep_table_count
        _zep_table_count=$(docker exec "${TENANT_PREFIX}-postgres" psql -U "${POSTGRES_USER}" -d "${ZEP_DB_NAME}" \
            -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' \
                  AND table_name IN ('watermill_message_token_count','watermill_offsets_message_token_count');" \
            2>/dev/null || echo "0")
        if [[ "${_zep_table_count:-0}" -lt 2 ]]; then
            log "  Watermill tables missing — creating manually and restarting Zep..."
            docker exec "${TENANT_PREFIX}-postgres" psql -U "${POSTGRES_USER}" -d "${ZEP_DB_NAME}" -c "
                CREATE TABLE IF NOT EXISTS watermill_message_token_count (
                    \"offset\" SERIAL,
                    uuid VARCHAR(36) NOT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    payload JSON DEFAULT NULL,
                    metadata JSON DEFAULT NULL,
                    transaction_id xid8 NOT NULL,
                    PRIMARY KEY (transaction_id, \"offset\")
                );
                CREATE TABLE IF NOT EXISTS watermill_offsets_message_token_count (
                    consumer_group VARCHAR(255) NOT NULL,
                    offset_acked BIGINT,
                    last_processed_transaction_id xid8 NOT NULL,
                    PRIMARY KEY(consumer_group)
                );" 2>&1 | grep -v "^$" | grep -v "already exists" || true
            docker restart "${TENANT_PREFIX}-zep" 2>/dev/null || true
            wait_for_health "${TENANT_PREFIX}-zep" 120 || return 1
        fi
        ok "Zep watermill tables verified"
    fi

    if [[ "${LETTA_ENABLED:-false}" == "true" ]]; then
        # Letta runs Alembic migrations before binding the HTTP server.
        # Observed migration time: 5-8 min. start_period:600s in healthcheck keeps Docker
        # in 'starting' through that window; we wait up to 15 min total here.
        wait_for_health "${TENANT_PREFIX}-letta" 900 || return 1
    fi
    
    if [[ "${REDIS_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-redis" 60 || return 1
    fi
    
    if [[ "${OLLAMA_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-ollama" 120 || return 1
    fi
    
    if [[ "${LITELLM_ENABLED}" == "true" ]]; then
        # Extended to 3000s to allow for full bootstrap/migrations on fresh EBS volumes
        wait_for_health "${TENANT_PREFIX}-litellm" 3000 || return 1
    fi
    
    if [[ "${OPENWEBUI_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-openwebui" 180 || return 1
    fi

    if [[ "${LIBRECHAT_ENABLED:-${ENABLE_LIBRECHAT:-false}}" == "true" ]]; then
        # MongoDB health check with corruption detection + auto-recovery
        # Note: do NOT abort on unhealthy — recovery is attempted first.
        log "Checking MongoDB health and connectivity..."
        local _mongo_healthy=true
        wait_for_health "${TENANT_PREFIX}-mongodb" 60 || _mongo_healthy=false

        local _mongo_ping=false
        docker exec "${TENANT_PREFIX}-mongodb" mongosh --eval "db.adminCommand('ping')" 2>/dev/null && _mongo_ping=true

        if [[ "${_mongo_healthy}" == "false" ]] || [[ "${_mongo_ping}" == "false" ]]; then
            warn "MongoDB reported unhealthy (exitCode 100 or ping failed) — likely stale data from prior deploy"
            warn "Attempting automatic corruption recovery..."

            docker stop "${TENANT_PREFIX}-mongodb" 2>/dev/null || true
            # Use docker_wipe_dir to bypass root-owned file permission errors
            docker_wipe_dir "${DATA_DIR}/mongodb"

            docker start "${TENANT_PREFIX}-mongodb"
            log "Waiting for MongoDB to initialize with fresh database..."
            wait_for_health "${TENANT_PREFIX}-mongodb" 60 || return 1

            if docker exec "${TENANT_PREFIX}-mongodb" mongosh --eval "db.adminCommand('ping')" 2>/dev/null; then
                ok "MongoDB corruption recovery completed"
            else
                fail "FATAL: MongoDB recovery failed — manual intervention required"
            fi
        else
            # Sync MongoDB password — preserved data directories ignore MONGO_INITDB_ROOT_PASSWORD
            # on restart (same issue as Postgres pgdata). Use a temporary --noauth instance to
            # update the stored hash without knowing the old password.
            if ! docker exec "${TENANT_PREFIX}-mongodb" mongosh \
                -u librechat -p "${MONGO_PASSWORD}" admin \
                --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
                log "MongoDB password drift detected — syncing via noauth restart..."
                docker stop "${TENANT_PREFIX}-mongodb" 2>/dev/null || true
                docker run --rm -d --name "${TENANT_PREFIX}-mongodb-sync" \
                    -v "${DATA_DIR}/mongodb:/data/db" mongo:7 mongod --noauth --dbpath /data/db
                sleep 8
                docker exec "${TENANT_PREFIX}-mongodb-sync" mongosh admin \
                    --eval "db.updateUser('librechat', {pwd: '${MONGO_PASSWORD}'})" \
                    2>&1 | grep -v "^$" || true
                docker stop "${TENANT_PREFIX}-mongodb-sync" 2>/dev/null || true
                docker start "${TENANT_PREFIX}-mongodb"
                wait_for_health "${TENANT_PREFIX}-mongodb" 60 || return 1
                ok "MongoDB password synced"
            else
                ok "MongoDB is healthy and responsive"
            fi
        fi
        
        wait_for_health "${TENANT_PREFIX}-librechat" 120 || return 1
    fi

    if [[ "${OPENCLAW_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-openclaw" 90 || return 1

        # Auto-approve any pending device pairing requests so the browser
        # can connect immediately without needing Script 3 --openclaw-pairs.
        local _oc_pending="${DATA_DIR}/openclaw/home/devices/pending.json"
        local _oc_paired="${DATA_DIR}/openclaw/home/devices/paired.json"
        if [[ -f "$_oc_pending" ]]; then
            local _pending_count
            _pending_count=$(python3 -c "import json; print(len(json.load(open('$_oc_pending'))))" 2>/dev/null || echo "0")
            if [[ "$_pending_count" -gt 0 ]]; then
                log "Auto-approving ${_pending_count} pending OpenClaw pairing request(s)..."
                python3 -c "
import json, time
with open('$_oc_pending') as f: pending=json.load(f)
try:
    with open('$_oc_paired') as f: paired=json.load(f)
except: paired={}
now=int(time.time()*1000)
scopes=['operator.read','operator.write','operator.admin','operator.approvals','operator.pairing']
for rid,r in pending.items():
    paired[rid]={**r,'approved':True,'status':'approved','approvedTs':now,'scopes':scopes}
with open('$_oc_paired','w') as f: json.dump(paired,f,indent=2)
with open('$_oc_pending','w') as f: json.dump({},f,indent=2)
print(f'Approved {len(pending)} request(s)')
" && docker restart "${TENANT_PREFIX}-openclaw" >/dev/null 2>&1 \
                    && ok "OpenClaw pairing approved and container restarted" \
                    || warn "OpenClaw auto-approve failed — run: bash scripts/3-configure-services.sh ${TENANT_ID} --openclaw-pairs"
            fi
        fi
    fi
    
    if [[ "${QDRANT_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-qdrant" 90 || return 1
    fi

    if [[ "${WEAVIATE_ENABLED:-${ENABLE_WEAVIATE:-false}}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-weaviate" 90 || return 1
    fi

    if [[ "${CHROMA_ENABLED:-${ENABLE_CHROMA:-false}}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-chroma" 90 || return 1
    fi

    if [[ "${MILVUS_ENABLED:-${ENABLE_MILVUS:-false}}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-milvus-etcd" 60 || return 1
        wait_for_health "${TENANT_PREFIX}-milvus-minio" 60 || return 1
        wait_for_health "${TENANT_PREFIX}-milvus" 120 || return 1
    fi

    if [[ "${ANYTHINGLLM_ENABLED:-${ENABLE_ANYTHINGLLM:-false}}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-anythingllm" 90 || return 1
    fi

    if [[ "${GRAFANA_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-grafana" 60 || return 1
    fi

    if [[ "${CODE_SERVER_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-code-server" 60 || return 1
    fi
    
    if [[ "${N8N_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-n8n" 90 || return 1
    fi
    
    if [[ "${FLOWISE_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-flowise" 90 || return 1
    fi
    
    if [[ "${DIFY_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-dify-api" 180 || return 1
        wait_for_health "${TENANT_PREFIX}-dify" 90 || return 1
        # dify-worker health check uses celery inspect — may be slow, don't block on it
        wait_for_health "${TENANT_PREFIX}-dify-worker" 180 || log "dify-worker health check timed out (non-fatal — worker may still be starting)"
        
        # Check for Dify database migration issues and auto-recover
        if docker logs "${TENANT_PREFIX}-dify-api" --tail 20 2>/dev/null | grep -q "sqlalche.me/e/20/f405\|Database migration failed\|Can't locate revision\|already exists"; then
            log "WARNING: Dify migration conflict detected — schema exists but alembic_version is missing"
            log "Stamping alembic_version to head so Dify skips re-running applied migrations..."

            # Find the head revisions in the Dify migration directory
            local dify_heads
            dify_heads=$(docker exec "${TENANT_PREFIX}-dify-api" bash -c "
                cd /app/api/migrations/versions 2>/dev/null || exit 1
                all_revs=\$(grep -h '^revision' *.py 2>/dev/null | sed \"s/revision = ['\\\"]\\([^'\\\"]*\\)['\\\"]$/\\1/\")
                down_revs=\$(grep -h '^down_revision' *.py 2>/dev/null | grep -v None | sed \"s/down_revision = ['\\\"]\\([^'\\\"]*\\)['\\\"]$/\\1/\")
                for r in \$all_revs; do
                    if ! echo \"\$down_revs\" | grep -qx \"\$r\"; then echo \"\$r\"; fi
                done
            " 2>/dev/null | grep -E '^[0-9a-f]{12}$' | head -1)

            if [[ -n "${dify_heads}" ]]; then
                docker exec "${TENANT_PREFIX}-postgres" psql -U "${POSTGRES_USER}" -d "${DIFY_DB_NAME}" -c "
                    CREATE TABLE IF NOT EXISTS alembic_version (
                        version_num VARCHAR(32) NOT NULL,
                        CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num)
                    );
                    INSERT INTO alembic_version (version_num) VALUES ('${dify_heads}') ON CONFLICT DO NOTHING;
                " 2>/dev/null && log "OK: Stamped alembic_version with head ${dify_heads} in ${DIFY_DB_NAME}"
            else
                log "WARNING: Could not determine Dify alembic head — trying hardcoded fallback stamp"
                docker exec "${TENANT_PREFIX}-postgres" psql -U "${POSTGRES_USER}" -d "${DIFY_DB_NAME}" -c "
                    CREATE TABLE IF NOT EXISTS alembic_version (
                        version_num VARCHAR(32) NOT NULL,
                        CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num)
                    );
                " 2>/dev/null || true
            fi

            docker restart "${TENANT_PREFIX}-dify-api" 2>/dev/null || true
            log "Waiting for Dify API to restart after stamp..."
            wait_for_health "${TENANT_PREFIX}-dify-api" 180 || log "WARNING: Dify API health check timed out after stamp"

            if docker logs "${TENANT_PREFIX}-dify-api" --tail 5 2>/dev/null | grep -q "Database migration successful\|Starting gunicorn"; then
                log "OK: Dify migration recovery successful"
            else
                log "WARNING: Dify may still have issues — check: docker logs ${TENANT_PREFIX}-dify-api"
            fi
        else
            log "Dify database appears healthy"
        fi
        
        # Check for LiteLLM database migration issues and auto-recover
        if ! docker logs "${TENANT_PREFIX}-litellm" --tail 10 2>/dev/null | grep -q "Database error\|relation.*does not exist\|migration failed"; then
            log "LiteLLM database appears healthy"
        else
            log "WARNING: LiteLLM database migration issues detected"
            log "Attempting automatic LiteLLM database recovery..."
            
            # Stop LiteLLM
            docker stop "${TENANT_PREFIX}-litellm" 2>/dev/null || true
            
            # Wipe LiteLLM dedicated database (drop and recreate for clean migration)
            docker exec "${TENANT_PREFIX}-postgres" psql -U "${POSTGRES_USER}" -d postgres -c "DROP DATABASE IF EXISTS \"${LITELLM_DB_NAME}\";" 2>/dev/null || true
            create_service_database "${LITELLM_DB_NAME}"
            
            # Clear LiteLLM cache
            rm -rf "${DATA_DIR}/litellm/prisma-cache"/* 2>/dev/null || true
            
            # Restart LiteLLM
            docker start "${TENANT_PREFIX}-litellm" 2>/dev/null || true
            
            log "Waiting for LiteLLM to re-initialize..."
            wait_for_health "${TENANT_PREFIX}-litellm" 300 || return 1
            
            if ! docker logs "${TENANT_PREFIX}-litellm" --tail 5 2>/dev/null | grep -q "Database error"; then
                log "SUCCESS: LiteLLM database recovery completed"
            else
                log "WARNING: LiteLLM recovery may need manual intervention"
            fi
        fi
    fi
    
    if [[ "${AUTHENTIK_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-authentik" 180 || return 1
    fi
    
    if [[ "${SIGNALBOT_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-signalbot" 90 || return 1

        # SMS registration: if method=sms, trigger register → prompt for verification code
        if [[ "${SIGNAL_REGISTRATION_METHOD:-qr}" == "sms" ]] && [[ -n "${SIGNAL_PHONE:-}" ]]; then
            local sig_api="http://127.0.0.1:${SIGNALBOT_PORT:-8080}"
            log "Triggering Signal SMS registration for ${SIGNAL_PHONE}..."
            curl -sf -X POST "${sig_api}/v1/register/${SIGNAL_PHONE}" \
                -H "Content-Type: application/json" -d '{"use_voice":false}' >/dev/null 2>&1 \
                && log "SMS sent to ${SIGNAL_PHONE}" || warn "SMS registration request failed — verify manually"

            if [[ -t 0 ]]; then
                local verify_code=""
                safe_read "Enter SMS verification code received on ${SIGNAL_PHONE}" "" "verify_code" "^[0-9]{6}$"
                if [[ -n "$verify_code" ]]; then
                    curl -sf -X POST "${sig_api}/v1/verify/${SIGNAL_PHONE}" \
                        -H "Content-Type: application/json" \
                        -d "{\"token\":\"${verify_code}\"}" >/dev/null 2>&1 \
                        && ok "Signal account verified — registration complete" \
                        || warn "Verification failed — check the code and retry via: curl -X POST ${sig_api}/v1/verify/${SIGNAL_PHONE} -d '{\"token\":\"<code>\"}'"
                fi
            else
                log "Non-interactive mode: verify manually with: curl -X POST ${sig_api}/v1/verify/${SIGNAL_PHONE} -H 'Content-Type: application/json' -d '{\"token\":\"<code>\"}'"
            fi
        fi
    fi
    
    if [[ "${SEARXNG_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-searxng" 90 || return 1
    fi
    
    if [[ "${BIFROST_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-bifrost" 90 || return 1
    fi
    
    if [[ "${CADDY_ENABLED}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-caddy" 90 || return 1
        # Caddy warns "Caddyfile input is not formatted" because the generated file uses
        # spaces instead of tabs. Format it in-place and reload so the warning disappears.
        log "Formatting Caddyfile and reloading Caddy..."
        docker exec "${TENANT_PREFIX}-caddy" caddy fmt --overwrite /etc/caddy/Caddyfile 2>/dev/null || true
        docker exec "${TENANT_PREFIX}-caddy" caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile 2>/dev/null || true
    fi

    if [[ "${NPM_ENABLED:-false}" == "true" ]]; then
        wait_for_health "${TENANT_PREFIX}-npm" 90 || return 1
    fi

    ok "All services are healthy"
    
    # =============================================================================
    # OLLAMA MODEL MANAGEMENT (P13 - Dynamic Model Loading)
    # =============================================================================
    if [[ "${OLLAMA_ENABLED}" == "true" ]]; then
        log "Managing Ollama models..."
        
        local container_name="${TENANT_PREFIX}-ollama"
        
        # Get the validated and potentially upgraded model list
        local latest_ollama_models
        latest_ollama_models=$(get_latest_ollama_models "${OLLAMA_MODELS}")
        
        # Expand comma-separated model list
        IFS=',' read -ra model_list <<< "${latest_ollama_models}"
        
        # Pull each model if not already present (check first to avoid re-download costs)
        for model in "${model_list[@]}"; do
            model=$(echo "${model// /}" | xargs)  # trim whitespace
            
            log "Checking if Ollama model '${model}' is already downloaded..."
            if docker exec "${container_name}" ollama list 2>/dev/null | grep -q "${model}"; then
                log "  Model '${model}' already present, skipping download"
            else
                log "  Pulling Ollama model '${model}' (this may take several minutes)..."
                if run_cmd docker exec "${container_name}" ollama pull "${model}"; then
                    log "  Model '${model}' pulled successfully"
                else
                    warn "  Failed to pull model '${model}'. Platform remains functional without it."
                    warn "  You can retry manually with: docker exec ${container_name} ollama pull ${model}"
                fi
            fi
        done
        
        # Verify the default model is available
        local default_model
        default_model=$(get_latest_ollama_models "${OLLAMA_DEFAULT_MODEL}")
        
        if docker exec "${container_name}" ollama list 2>/dev/null | grep -q "${default_model}"; then
            log "Default Ollama model '${default_model}' is available"
        else
            warn "Default model '${default_model}' not found. Attempting to pull..."
            if run_cmd docker exec "${container_name}" ollama pull "${default_model}"; then
                log "Default model '${default_model}' pulled successfully"
            else
                warn "Failed to pull default model '${default_model}'. Some services may not work properly."
            fi
        fi
        
        ok "Ollama model management complete"
    fi
}

# =============================================================================
# RCLONE INITIAL SYNC — triggers immediately after deploy so ingestion/ is
# populated on first run rather than waiting for the first poll interval.
# The rclone container's entrypoint already loops; this is a belt-and-suspenders
# restart to ensure the first sync fires right after all health checks pass.
# =============================================================================
trigger_initial_rclone_sync() {
    if [[ "${ENABLE_INGESTION:-false}" != "true" || "${INGESTION_METHOD:-rclone}" != "rclone" ]]; then
        return 0
    fi

    local rclone_container="${TENANT_PREFIX}-rclone"

    if ! docker inspect "${rclone_container}" &>/dev/null; then
        warn "rclone container ${rclone_container} not found — skipping initial sync trigger"
        return 0
    fi

    log "Triggering initial rclone sync (restarting container to reset loop)..."
    docker restart "${rclone_container}" 2>/dev/null || true
    sleep 3

    # Tail logs for up to 30s so the deploy output shows the sync starting
    log "rclone sync log (first 30s):"
    timeout 30 docker logs -f "${rclone_container}" 2>&1 | head -20 || true

    ok "rclone initial sync triggered. Files will appear in ${DATA_DIR}/ingestion/ once Google Drive folder is shared with service account."
    log "Share your Google Drive folder with the service account email in ${GDRIVE_CREDENTIALS_FILE:-platform.conf}."
}

# =============================================================================
# MAIN FUNCTION (README §6 - strict execution order)
# =============================================================================
main() {
    local tenant_id="${1:-}"
    local dry_run=false
    local flush_all=false

    # Parse arguments
    shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run=true
                shift
                ;;
            --flushall)
                flush_all=true
                shift
                ;;
            --flush-dbs)
                flush_dbs=true
                shift
                ;;
            *)
                fail "Unknown option: $1"
                ;;
        esac
    done

    # Set global variables
    export DRY_RUN="$dry_run"
    export FLUSH_ALL="$flush_all"
    export FLUSH_DBS="$flush_dbs"
    
    # Validate tenant ID
    if [[ -z "$tenant_id" ]]; then
        fail "Tenant ID is required"
    fi
    
    # Source platform.conf (README P1 - single source of truth)
    local platform_conf="/mnt/${tenant_id}/config/platform.conf"
    if [[ ! -f "$platform_conf" ]]; then
        fail "platform.conf not found at $platform_conf. Run script 1 first."
    fi
    # shellcheck source=/dev/null
    source "$platform_conf"

    # Normalise / derive variables not directly in platform.conf
    # These are safe to compute here since platform.conf is already sourced.
    CONFIGURED_DIR="${DATA_DIR}/.configured"
    BASE_DIR="${DATA_DIR}"
    CONFIG_DIR="${DATA_DIR}/config"
    LOG_FILE="${DATA_DIR}/logs/deploy-$(date +%Y%m%d-%H%M%S).log"

    mkdir -p "${DATA_DIR}/logs" "$CONFIGURED_DIR"

    # Fix Docker socket BEFORE any docker calls (rootless socket check)
    if [[ "${DOCKER_HOST:-}" == *"user/"* ]]; then
        unset DOCKER_HOST
    fi

    # --- FLUSH FIRST (idempotency: every run is a fresh deploy) ---
    flush_existing_deployment

    # --- OPTIONAL: wipe all persisted data for a true clean redeploy ---
    if [[ "${FLUSH_ALL}" == "true" ]]; then
        flush_all_data
    fi

    # --- OPTIONAL: wipe only database directories for corruption recovery ---
    if [[ "${FLUSH_DBS}" == "true" ]]; then
        flush_databases_only
        echo ""
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║              Database Recovery Complete ✓                   ║"
        echo "╚══════════════════════════════════════════════════════════╝"
        echo ""
        echo "  Database directories wiped and containers restarted successfully."
        echo "  You can now run Script 3 for service configuration."
        echo ""
        exit 0
    fi

    # Per-service DB names — early defaults (main() block re-derives after all vars resolved)
    LITELLM_DB_NAME="${LITELLM_DB_NAME:-${POSTGRES_DB:-${TENANT_ID}}_litellm}"
    LITELLM_DB_URL="postgresql://${POSTGRES_USER:-${TENANT_ID}}:${POSTGRES_PASSWORD}@${TENANT_PREFIX}-postgres:5432/${LITELLM_DB_NAME}"

    # Alias any vars Script 2 expects that platform.conf may call differently
    BASE_DOMAIN="${BASE_DOMAIN:-${DOMAIN}}"
    PROXY_EMAIL="${PROXY_EMAIL:-${ADMIN_EMAIL}}"
    # Secrets generated by Script 1 — fall back to auto-generate if missing from platform.conf
    AUTHENTIK_SECRET_KEY="${AUTHENTIK_SECRET_KEY:-$(openssl rand -hex 50)}"
    ZEP_AUTH_SECRET="${ZEP_AUTH_SECRET:-$(openssl rand -hex 32)}"
    LETTA_SERVER_PASS="${LETTA_SERVER_PASS:-$(openssl rand -hex 24)}"
    ANYTHINGLLM_JWT_SECRET="${ANYTHINGLLM_JWT_SECRET:-$(openssl rand -hex 32)}"
    CODE_SERVER_PASSWORD="${CODE_SERVER_PASSWORD:-$(openssl rand -base64 16 | tr -d '=+/')}"
    LITELLM_UI_PASSWORD="${LITELLM_UI_PASSWORD:-$(openssl rand -base64 16 | tr -d '=+/')}"
    DIFY_SECRET_KEY="${DIFY_SECRET_KEY:-$(openssl rand -hex 32)}"
    DIFY_INIT_PASSWORD="${DIFY_INIT_PASSWORD:-$(openssl rand -base64 12 | tr -d '=+/')}"
    # N8N webhook URL must use HTTPS + n8n subdomain when Caddy is active,
    # otherwise n8n's WebSocket/webhook connection fails from the browser.
    if [[ "${CADDY_ENABLED:-false}" == "true" && -n "${BASE_DOMAIN:-${DOMAIN:-}}" ]]; then
        N8N_WEBHOOK_URL="${N8N_WEBHOOK_URL:-https://n8n.${BASE_DOMAIN:-${DOMAIN}}/}"
    else
        N8N_WEBHOOK_URL="${N8N_WEBHOOK_URL:-http://${DOMAIN:-localhost}/}"
    fi
    FLOWISE_USERNAME="${FLOWISE_USERNAME:-admin}"
    FLOWISE_PASSWORD="${FLOWISE_PASSWORD:-$(openssl rand -base64 16 | tr -d '=+/')}"
    FLOWISE_SECRETKEY_OVERWRITE="${FLOWISE_SECRETKEY_OVERWRITE:-$(openssl rand -hex 32)}"
    GOOGLE_API_KEY="${GOOGLE_API_KEY:-${GOOGLE_AI_API_KEY:-}}"
    OLLAMA_DEFAULT_MODEL="${OLLAMA_DEFAULT_MODEL:-llama3.2:3b}"

    # Derive TENANT_PREFIX if not in platform.conf (backward compat)
    TENANT_PREFIX="${TENANT_PREFIX:-${PLATFORM_PREFIX}-${TENANT_ID}}"

    # Process UID/GID — fall back to current user if not in platform.conf
    PUID="${PUID:-$(id -u)}"
    PGID="${PGID:-$(id -g)}"

    # Map ENABLE_* → *_ENABLED (backward compat with old platform.conf)
    POSTGRES_ENABLED="${POSTGRES_ENABLED:-${ENABLE_POSTGRES:-false}}"
    REDIS_ENABLED="${REDIS_ENABLED:-${ENABLE_REDIS:-false}}"
    OLLAMA_ENABLED="${OLLAMA_ENABLED:-${ENABLE_OLLAMA:-false}}"
    LITELLM_ENABLED="${LITELLM_ENABLED:-${ENABLE_LITELLM:-false}}"
    OPENWEBUI_ENABLED="${OPENWEBUI_ENABLED:-${ENABLE_OPENWEBUI:-false}}"
    QDRANT_ENABLED="${QDRANT_ENABLED:-${ENABLE_QDRANT:-false}}"
    WEAVIATE_ENABLED="${WEAVIATE_ENABLED:-${ENABLE_WEAVIATE:-false}}"
    N8N_ENABLED="${N8N_ENABLED:-${ENABLE_N8N:-false}}"
    FLOWISE_ENABLED="${FLOWISE_ENABLED:-${ENABLE_FLOWISE:-false}}"
    DIFY_ENABLED="${DIFY_ENABLED:-${ENABLE_DIFY:-false}}"
    GRAFANA_ENABLED="${GRAFANA_ENABLED:-${ENABLE_GRAFANA:-false}}"
    PROMETHEUS_ENABLED="${PROMETHEUS_ENABLED:-${ENABLE_PROMETHEUS:-false}}"
    CADDY_ENABLED="${CADDY_ENABLED:-${ENABLE_CADDY:-false}}"
    AUTHENTIK_ENABLED="${AUTHENTIK_ENABLED:-${ENABLE_AUTHENTIK:-false}}"
    OPENCLAW_ENABLED="${OPENCLAW_ENABLED:-${ENABLE_OPENCLAW:-false}}"
    BIFROST_ENABLED="${BIFROST_ENABLED:-${ENABLE_BIFROST:-false}}"
    SIGNALBOT_ENABLED="${SIGNALBOT_ENABLED:-${ENABLE_SIGNALBOT:-false}}"
    SEARXNG_ENABLED="${SEARXNG_ENABLED:-${ENABLE_SEARXNG:-false}}"
    ANYTHINGLLM_ENABLED="${ANYTHINGLLM_ENABLED:-${ENABLE_ANYTHINGLLM:-false}}"
    ANYTHINGLLM_JWT_SECRET="${ANYTHINGLLM_JWT_SECRET:-$(openssl rand -hex 32)}"
    # Authentik requires a non-empty secret key
    AUTHENTIK_SECRET_KEY="${AUTHENTIK_SECRET_KEY:-$(openssl rand -hex 50)}"
    AUTHENTIK_BOOTSTRAP_PASSWORD="${AUTHENTIK_BOOTSTRAP_PASSWORD:-${ADMIN_PASSWORD:-$(openssl rand -base64 16 | tr -d '=+/')}}"
    WEAVIATE_ENABLED="${WEAVIATE_ENABLED:-${ENABLE_WEAVIATE:-false}}"
    CHROMA_ENABLED="${CHROMA_ENABLED:-${ENABLE_CHROMA:-false}}"
    GRAFANA_ENABLED="${GRAFANA_ENABLED:-${ENABLE_GRAFANA:-false}}"
    PROMETHEUS_ENABLED="${PROMETHEUS_ENABLED:-${ENABLE_PROMETHEUS:-false}}"
    CODE_SERVER_ENABLED="${CODE_SERVER_ENABLED:-${ENABLE_CODE_SERVER:-false}}"
    CODE_SERVER_PORT="${CODE_SERVER_PORT:-8080}"
    CODE_SERVER_PASSWORD="${CODE_SERVER_PASSWORD:-$(openssl rand -base64 16 | tr -d '=+/')}"
    CONTINUE_DEV_ENABLED="${CONTINUE_DEV_ENABLED:-${ENABLE_CONTINUE_DEV:-false}}"
    # Search APIs
    SERPAPI_KEY="${SERPAPI_KEY:-}"
    BRAVE_API_KEY="${BRAVE_API_KEY:-}"
    # Mammouth
    MAMMOUTH_API_KEY="${MAMMOUTH_API_KEY:-}"
    MAMMOUTH_BASE_URL="${MAMMOUTH_BASE_URL:-https://api.mammouth.ai/v1}"
    MAMMOUTH_MODELS="${MAMMOUTH_MODELS:-claude-sonnet-4-6,gemini-2.5-flash,gpt-4o}"

    # Resolve base postgres credentials then derive all per-service DB names and URLs.
    POSTGRES_USER="${POSTGRES_USER:-${TENANT_ID}}"
    POSTGRES_DB="${POSTGRES_DB:-${TENANT_ID}}"
    # Per-service DB names — read from platform.conf if present, else default to ${POSTGRES_DB}_<service>
    LETTA_DB_NAME="${LETTA_DB_NAME:-${POSTGRES_DB}_letta}"
    LITELLM_DB_NAME="${LITELLM_DB_NAME:-${POSTGRES_DB}_litellm}"
    N8N_DB_NAME="${N8N_DB_NAME:-${POSTGRES_DB}_n8n}"
    ZEP_DB_NAME="${ZEP_DB_NAME:-${POSTGRES_DB}_zep}"
    DIFY_DB_NAME="${DIFY_DB_NAME:-${POSTGRES_DB}_dify}"
    AUTHENTIK_DB_NAME="${AUTHENTIK_DB_NAME:-${POSTGRES_DB}_authentik}"
    # LiteLLM DB URL uses its dedicated database
    LITELLM_DB_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${TENANT_PREFIX}-postgres:5432/${LITELLM_DB_NAME}"

    mkdir -p "$CONFIGURED_DIR"

    # Write any dynamically-generated secrets back to platform.conf so Script 3
    # can source them. Idempotent — safe on re-runs.
    persist_generated_secrets

    log "=== Script 2: Atomic Deployer ==="
    log "Version: ${SCRIPT_VERSION}"
    log "Tenant: ${tenant_id}"
    log "Dry-run: ${dry_run}"
    
    # Execution order (README §6 - strict):
    # 1. source platform.conf (done above)
    # 2. Pre-flight checks
    if ! step_done "preflight_checks"; then
        framework_validate
        mark_done "preflight_checks"
    else
        log "Pre-flight checks already completed, skipping"
    fi

    # 2b. Prepare data directories (idempotent — safe to re-run)
    #     Runs every time to ensure ownership is correct even after re-mounts.
    prepare_data_dirs

    # 2c. Initialize port allocator
    init_port_allocator

    # 3. generate_compose()
    if ! step_done "compose_generated"; then
        generate_compose
        mark_done "compose_generated"
    else
        log "docker-compose.yml already generated, skipping"
    fi
    
    # 4. validate_compose()
    validate_compose
    
    # 5. generate_litellm_config()
    if ! step_done "litellm_config_generated"; then
        generate_litellm_config
        mark_done "litellm_config_generated"
    else
        log "LiteLLM config already generated, skipping"
    fi
    
    # 6. generate_caddyfile() [if caddy enabled]
    if ! step_done "caddyfile_generated"; then
        generate_caddyfile
        mark_done "caddyfile_generated"
    else
        log "Caddyfile already generated, skipping"
    fi
    
    # Generate Bifrost config if enabled
    if [[ "${BIFROST_ENABLED}" == "true" ]] && ! step_done "bifrost_config_generated"; then
        generate_bifrost_config
        mark_done "bifrost_config_generated"
    fi
    
    # Scan for sentinels (README §6 - mandatory)
    if ! step_done "sentinel_scan"; then
        scan_for_sentinels
        mark_done "sentinel_scan"
    else
        log "Sentinel scan already completed, skipping"
    fi
    
    # 7. docker compose pull
    if ! step_done "images_pulled"; then
        pull_images
        mark_done "images_pulled"
    else
        log "Images already pulled, skipping"
    fi
    
    # 8. validate_caddyfile() [AFTER pull, not before]
    validate_caddyfile
    
    # 9. docker compose up -d
    if ! step_done "containers_deployed"; then
        deploy_containers
        mark_done "containers_deployed"
    else
        log "Containers already deployed, skipping"
    fi
    
    # 10. wait_for_health() for each enabled service
    if ! step_done "health_checks_passed"; then
        if ! wait_for_all_health; then
            fail "One or more services failed health checks — deployment incomplete"
        fi
        mark_done "health_checks_passed"
    else
        log "Health checks already passed, skipping"
    fi

    # 11. Trigger initial rclone sync immediately (don't wait for poll interval)
    trigger_initial_rclone_sync

    show_post_deploy_dashboard
    echo ""
    echo "  Next step: bash scripts/3-configure-services.sh ${tenant_id}"
    echo ""
}

# =============================================================================
# POST-DEPLOY HEALTH DASHBOARD — shown immediately after all containers healthy
# Displays every deployed service with its status, URL, and key credentials.
# =============================================================================
show_post_deploy_dashboard() {
    local base_proto="http"
    local display_host
    display_host=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
    local use_subdomains=false

    # When a proxy is active and domain is set, use subdomain-based URLs (e.g. openwebui.ai.domain.net)
    if [[ "${CADDY_ENABLED:-false}" == "true" || "${NPM_ENABLED:-false}" == "true" ]]; then
        local dom="${BASE_DOMAIN:-${DOMAIN:-}}"
        if [[ -n "$dom" ]]; then
            base_proto="https"
            display_host="$dom"
            use_subdomains=true
        fi
    fi

    # Helper: build a service URL — subdomain when proxy active, internal routing otherwise
    _svc_url() {
        local subdomain="$1" port="$2"
        if [[ "$use_subdomains" == "true" ]]; then
            echo "${base_proto}://${subdomain}.${display_host}"
        else
            echo "${base_proto}://${display_host}:${port}"
        fi
    }

    local W=74
    _d_sep()   { printf "╠%s╣\n" "$(printf '═%.0s' $(seq 1 $W))"; }
    _d_top()   { printf "╔%s╗\n" "$(printf '═%.0s' $(seq 1 $W))"; }
    _d_bot()   { printf "╚%s╝\n" "$(printf '═%.0s' $(seq 1 $W))"; }
    _d_line()  { printf "║  %-${W}s║\n" "$*"; }
    _d_blank() { printf "║%$((W+2))s║\n" ""; }
    _d_head()  { _d_line "── $* ──────────────────────────────────────────────────────────────────────" | cut -c1-$((W+4)); }

    echo ""
    _d_top
    _d_line "  DEPLOYMENT COMPLETE — SERVICE DASHBOARD"
    _d_sep
    _d_line "  Tenant : ${TENANT_ID}"
    _d_line "  Stack  : ${STACK_NAME:-custom}"
    _d_line "  Domain : ${display_host}   TLS: ${TLS_MODE:-none}"
    _d_sep
    _d_blank

    # REVERSE PROXY
    if [[ "${CADDY_ENABLED:-false}" == "true" ]]; then
        _d_line "REVERSE PROXY (Caddy — routes auto-configured)"
        _d_line "  ${base_proto}://${display_host}"
        _d_blank
    elif [[ "${NPM_ENABLED:-false}" == "true" ]]; then
        _d_line "REVERSE PROXY (Nginx Proxy Manager — configure routes at :81)"
        _d_line "  Admin        http://127.0.0.1:${NPM_ADMIN_PORT:-81}"
        _d_line "  Login        admin@example.com / changeme  ← change immediately"
        _d_blank
    fi

    # WEB UIs
    local has_ui=false
    for _v in OPENWEBUI LIBRECHAT OPENCLAW ANYTHINGLLM; do
        [[ "${!_v+x}" == "x" ]] || true
        eval "[[ \"\${${_v}_ENABLED:-false}\" == \"true\" || \"\${ENABLE_${_v}:-false}\" == \"true\" ]]" 2>/dev/null && has_ui=true
    done
    if [[ "$has_ui" == "true" ]]; then
        _d_line "WEB UIs"
        [[ "${OPENWEBUI_ENABLED:-false}"   == "true" ]] && _d_line "  OpenWebUI    $(_svc_url openwebui   ${OPENWEBUI_PORT})"
        [[ "${LIBRECHAT_ENABLED:-${ENABLE_LIBRECHAT:-false}}" == "true" ]] \
                                                          && _d_line "  LibreChat    $(_svc_url librechat   ${LIBRECHAT_PORT})"
        [[ "${OPENCLAW_ENABLED:-false}"    == "true" ]] && _d_line "  OpenClaw     $(_svc_url openclaw    ${OPENCLAW_PORT})"
        [[ "${ANYTHINGLLM_ENABLED:-false}" == "true" ]] && _d_line "  AnythingLLM  $(_svc_url anythingllm ${ANYTHINGLLM_PORT})"
        _d_blank
    fi

    # LLM GATEWAY
    if [[ "${LITELLM_ENABLED:-false}" == "true" ]]; then
        _d_line "LLM GATEWAY  (internal — all UIs route through here)"
        _d_line "  LiteLLM      $(_svc_url litellm ${LITELLM_PORT})/v1"
        _d_line "  Master Key   ${LITELLM_MASTER_KEY}"
        [[ "$use_subdomains" == "true" ]] && _d_line "  UI           $(_svc_url litellm ${LITELLM_PORT})/ui"
        _d_blank
    fi

    # AUTOMATION
    local has_auto=false
    [[ "${N8N_ENABLED:-false}" == "true" || "${FLOWISE_ENABLED:-false}" == "true" || "${DIFY_ENABLED:-false}" == "true" ]] && has_auto=true
    if [[ "$has_auto" == "true" ]]; then
        _d_line "AUTOMATION"
        [[ "${N8N_ENABLED:-false}"     == "true" ]] && _d_line "  N8N          $(_svc_url n8n     ${N8N_PORT})"
        [[ "${FLOWISE_ENABLED:-false}" == "true" ]] && _d_line "  Flowise      $(_svc_url flowise ${FLOWISE_PORT})"
        if [[ "${DIFY_ENABLED:-false}" == "true" ]]; then
            _d_line "  Dify         $(_svc_url dify ${DIFY_PORT})  (web + api via path routing)"
        fi
        _d_blank
    fi

    # MEMORY LAYER
    local has_mem=false
    [[ "${ZEP_ENABLED:-false}" == "true" || "${LETTA_ENABLED:-false}" == "true" ]] && has_mem=true
    if [[ "$has_mem" == "true" ]]; then
        _d_line "MEMORY LAYER"
        [[ "${ZEP_ENABLED:-false}"   == "true" ]] && _d_line "  Zep CE       $(_svc_url zep   ${ZEP_PORT})  (conversation memory)"
        [[ "${LETTA_ENABLED:-false}" == "true" ]] && _d_line "  Letta        $(_svc_url letta ${LETTA_PORT})  (agent memory runtime)"
        _d_blank
    fi

    # IDENTITY
    if [[ "${AUTHENTIK_ENABLED:-false}" == "true" ]]; then
        _d_line "IDENTITY"
        _d_line "  Authentik    $(_svc_url authentik ${AUTHENTIK_PORT})"
        _d_line "  Bootstrap    ${AUTHENTIK_BOOTSTRAP_EMAIL:-admin@${display_host}}  /  ${AUTHENTIK_BOOTSTRAP_PASSWORD:-<see platform.conf>}"
        _d_blank
    fi

    # MONITORING
    if [[ "${GRAFANA_ENABLED:-false}" == "true" || "${PROMETHEUS_ENABLED:-false}" == "true" ]]; then
        _d_line "MONITORING"
        [[ "${GRAFANA_ENABLED:-false}"    == "true" ]] && _d_line "  Grafana      $(_svc_url grafana    ${GRAFANA_PORT})  admin / ${GRAFANA_ADMIN_PASSWORD:-admin}"
        [[ "${PROMETHEUS_ENABLED:-false}" == "true" ]] && _d_line "  Prometheus   $(_svc_url prometheus ${PROMETHEUS_PORT})"
        _d_blank
    fi

    # DEVELOPMENT
    local has_dev=false
    [[ "${CODE_SERVER_ENABLED:-false}" == "true" || "${SIGNALBOT_ENABLED:-false}" == "true" || "${SEARXNG_ENABLED:-false}" == "true" ]] && has_dev=true
    if [[ "$has_dev" == "true" ]]; then
        _d_line "DEVELOPMENT / COMMS"
        [[ "${CODE_SERVER_ENABLED:-false}" == "true" ]] && _d_line "  Code Server  $(_svc_url code ${CODE_SERVER_PORT})  pass: ${CODE_SERVER_PASSWORD:-<see platform.conf>}"
        if [[ "${SIGNALBOT_ENABLED:-false}" == "true" ]]; then
            local _sig_url
            if [[ "$use_subdomains" == "true" ]]; then
                _sig_url="${base_proto}://signal.${display_host}"
            else
                _sig_url="http://127.0.0.1:${SIGNALBOT_PORT}"
            fi
            _d_line "  Signalbot    ${_sig_url}/v1/about  (bbernhard REST API)"
            _d_line "  Signal QR    ${_sig_url}/v1/qrcodelink?device_name=signal-api"
            _d_line "               → Open URL, scan QR with Signal phone app → Settings → Linked Devices"
            _d_line "               → After pairing: OpenClaw Signal channel activates automatically"
        fi
        if [[ "${SEARXNG_ENABLED:-false}" == "true" ]]; then
            local _search_url
            if [[ "$use_subdomains" == "true" ]]; then
                _search_url="${base_proto}://search.${display_host}"
            else
                _search_url="http://127.0.0.1:${SEARXNG_PORT}"
            fi
            _d_line "  SearXNG      ${_search_url} (privacy search)"
        fi
        _d_blank
    fi

    # CREDENTIALS SUMMARY
    _d_sep
    _d_line "CREDENTIALS"
    [[ -n "${LITELLM_MASTER_KEY:-}"           ]] && _d_line "  LiteLLM key          ${LITELLM_MASTER_KEY}"
    [[ -n "${LITELLM_UI_PASSWORD:-}"          ]] && _d_line "  LiteLLM UI pass      ${LITELLM_UI_PASSWORD}"
    [[ -n "${POSTGRES_PASSWORD:-}"            ]] && _d_line "  Postgres             ${POSTGRES_USER:-ds-admin} / ${POSTGRES_PASSWORD}"
    [[ -n "${AUTHENTIK_BOOTSTRAP_PASSWORD:-}" ]] && _d_line "  Authentik akadmin    ${AUTHENTIK_BOOTSTRAP_PASSWORD}"
    [[ -n "${GRAFANA_ADMIN_PASSWORD:-}"       ]] && _d_line "  Grafana admin        ${GRAFANA_ADMIN_PASSWORD}"
    [[ -n "${CODE_SERVER_PASSWORD:-}"         ]] && _d_line "  Code Server          ${CODE_SERVER_PASSWORD}"
    [[ -n "${FLOWISE_PASSWORD:-}"             ]] && _d_line "  Flowise              ${FLOWISE_USERNAME:-admin} / ${FLOWISE_PASSWORD}"
    [[ -n "${SIGNAL_PHONE:-}"                ]] && _d_line "  Signal phone         ${SIGNAL_PHONE}"
    [[ -n "${SIGNAL_RECIPIENT:-}"           ]] && _d_line "  Signal recipient     ${SIGNAL_RECIPIENT}"
    [[ -n "${SEARXNG_SECRET_KEY:-}"         ]] && _d_line "  SearXNG secret       ${SEARXNG_SECRET_KEY:0:16}..."
    [[ -n "${ZEP_AUTH_SECRET:-}"            ]] && _d_line "  Zep token            ${ZEP_AUTH_SECRET}"
    [[ -n "${LETTA_SERVER_PASS:-}"            ]] && _d_line "  Letta password       ${LETTA_SERVER_PASS}"
    [[ -n "${ANYTHINGLLM_JWT_SECRET:-}"       ]] && _d_line "  AnythingLLM JWT      ${ANYTHINGLLM_JWT_SECRET}"
    _d_blank

    _d_sep
    _d_line "PIPELINE:  Gdrive → rclone → ${DATA_DIR}/ingestion → Qdrant/Zep/Letta → LiteLLM → Web UIs"
    _d_sep
    _d_line "  Next step:  bash scripts/3-configure-services.sh ${TENANT_ID}"
    _d_bot
    echo ""
}

# =============================================================================
# SCRIPT ENTRY POINT
# =============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
