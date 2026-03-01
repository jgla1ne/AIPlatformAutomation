#!/usr/bin/env bash
# 3-configure-services.sh
# Post-deploy configuration — runs after all containers are healthy
# Reads .env, configures service integrations
set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*" >&2; exit 1; }

# ─────────────────────────────────────────────────────────────
# BOOTSTRAP
# ─────────────────────────────────────────────────────────────
TENANT_UID=$(id -u)
TENANT_ID="u${TENANT_UID}"
DATA_ROOT="/mnt/data/${TENANT_ID}"
ENV_FILE="${DATA_ROOT}/.env"
LOG_FILE="${DATA_ROOT}/logs/configure-$(date +%Y%m%d-%H%M%S).log"

[ ! -f "${ENV_FILE}" ] && {
    echo "ERROR: ${ENV_FILE} not found — run script 1 first"
    exit 1
}

# Load env (no duplicates since script 1 now writes clean)
set -a; source "${ENV_FILE}"; set +a

mkdir -p "${DATA_ROOT}/logs"

wait_for_service() {
    local name=$1 url=$2 max=${3:-120}
    log "Waiting for ${name} at ${url}..."
    local count=0
    while [ ${count} -lt ${max} ]; do
        curl -sf --max-time 5 "${url}" &>/dev/null && {
            ok "${name} is responding"
            return 0
        }
        count=$(( count + 5 ))
        sleep 5
    done
    warn "${name} did not respond within ${max}s — skipping config"
    return 1
}

# ─────────────────────────────────────────────────────────────
# MINIO — Create buckets
# ─────────────────────────────────────────────────────────────
configure_minio() {
    log "Configuring MinIO..."
    wait_for_service "minio" "http://localhost:${MINIO_PORT}/minio/health/live" || return
    
    # Use mc inside minio container
    docker exec "${COMPOSE_PROJECT_NAME}-minio" \
        sh -c "
            mc alias set local http://localhost:9000 \
                ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD} --quiet 2>/dev/null
            for bucket in aiplatform-docs aiplatform-media aiplatform-backups; do
                mc mb local/\${bucket} --ignore-existing --quiet 2>/dev/null && \
                    echo \"Bucket \${bucket} ready\" || true
            done
        " 2>&1 | tee -a "${LOG_FILE}"

    ok "MinIO buckets configured"
}

# ─────────────────────────────────────────────────────────────
# QDRANT — Create collections per enabled service
# ─────────────────────────────────────────────────────────────
configure_qdrant() {
    [ "${VECTOR_DB}" = "qdrant" ] || return 0
    log "Configuring Qdrant collections..."
    wait_for_service "qdrant" "http://localhost:${QDRANT_PORT}/" || return
    
    create_collection() {
        local name=$1
        local size=${2:-1536}
        curl -sf -X PUT \
            "http://localhost:${QDRANT_PORT}/collections/${name}" \
            -H "Content-Type: application/json" \
            -d "{
                \"vectors\": {
                    \"size\": ${size},
                    \"distance\": \"Cosine\"
                }
            }" 2>/dev/null && \
            ok "Collection '${name}' created" || \
            log "Collection '${name}' already exists"
    }

    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && create_collection "anythingllm" 1536
    [ "${ENABLE_OPENWEBUI}" = "true" ] && create_collection "openwebui" 1536
    [ "${ENABLE_DIFY}" = "true" ] && create_collection "dify" 1536
    [ "${ENABLE_OPENCLAW}" = "true" ] && create_collection "openclaw" 1536

    ok "Qdrant collections configured"
}

# ─────────────────────────────────────────────────────────────
# OLLAMA — Pull default model
# ─────────────────────────────────────────────────────────────
configure_ollama() {
    [ "${ENABLE_OLLAMA}" = "true" ] || return 0
    log "Configuring Ollama — pulling ${OLLAMA_DEFAULT_MODEL}..."
    wait_for_service "ollama" "http://localhost:${OLLAMA_PORT}/api/tags" || return
    
    docker exec "${COMPOSE_PROJECT_NAME}-ollama" \
        ollama pull "${OLLAMA_DEFAULT_MODEL}" 2>&1 | tee -a "${LOG_FILE}"

    # Pull embedding model (needed by AnythingLLM + OpenWebUI)
    docker exec "${COMPOSE_PROJECT_NAME}-ollama" \
        ollama pull nomic-embed-text:latest 2>&1 | tee -a "${LOG_FILE}"

    ok "Ollama models ready"
}

# ─────────────────────────────────────────────────────────────
# LITELLM — Register models
# ─────────────────────────────────────────────────────────────
configure_litellm() {
    [ "${ENABLE_LITELLM}" = "true" ] || return 0
    log "Configuring LiteLLM models..."
    wait_for_service "litellm" "http://localhost:${LITELLM_PORT}/health" || return
    
    add_model() {
        local model_name=$1
        local litellm_model=$2
        local api_base=${3:-""}
        local api_key=${4:-""}

        local payload="{
            \"model_name\": \"${model_name}\",
            \"litellm_params\": {
                \"model\": \"${litellm_model}\"
                $([ -n "${api_base}" ] && echo ",\"api_base\": \"${api_base}\"" || echo "")
                $([ -n "${api_key}" ] && echo ",\"api_key\": \"${api_key}\"" || echo "")
            }
        }"

        curl -sf -X POST \
            "http://localhost:${LITELLM_PORT}/model/new" \
            -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
            -H "Content-Type: application/json" \
            -d "${payload}" 2>/dev/null && \
            ok "Model registered: ${model_name}" || \
            warn "Model registration failed: ${model_name}"
    }

    # Local Ollama models
    if [ "${ENABLE_OLLAMA}" = "true" ]; then
        add_model "${OLLAMA_DEFAULT_MODEL}" \
            "ollama/${OLLAMA_DEFAULT_MODEL}" \
            "http://ollama:11434" \
            ""
        add_model "nomic-embed-text" \
            "ollama/nomic-embed-text:latest" \
            "http://ollama:11434" \
            ""
    fi

    # External providers (only if key set)
    [ -n "${OPENAI_API_KEY:-}" ] && \
        add_model "gpt-4o" "gpt-4o" "" "${OPENAI_API_KEY}"
    [ -n "${OPENAI_API_KEY:-}" ] && \
        add_model "gpt-4o-mini" "gpt-4o-mini" "" "${OPENAI_API_KEY}"
    [ -n "${GOOGLE_API_KEY:-}" ] && \
        add_model "gemini-2.0-flash" "gemini/gemini-2.0-flash-exp" "" "${GOOGLE_API_KEY}"
    [ -n "${GROQ_API_KEY:-}" ] && \
        add_model "llama-3.3-70b-groq" "groq/llama-3.3-70b-versatile" "" "${GROQ_API_KEY}"
    [ -n "${OPENROUTER_API_KEY:-}" ] && \
        add_model "claude-3.5-sonnet" \
            "openrouter/anthropic/claude-3.5-sonnet" \
            "https://openrouter.ai/api/v1" \
            "${OPENROUTER_API_KEY}"

    ok "LiteLLM configuration complete"
}

# ─────────────────────────────────────────────────────────────
# POSTGRES — Create per-service databases
# ─────────────────────────────────────────────────────────────
configure_postgres() {
    log "Configuring PostgreSQL databases..."
    wait_for_service "postgres" "http://localhost/nonexistent" 10 || true
    
    # Wait using pg_isready instead of HTTP
    local attempts=0
    while [ ${attempts} -lt 30 ]; do
        docker exec "${COMPOSE_PROJECT_NAME}-postgres" \
            pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" &>/dev/null && break
        attempts=$(( attempts + 1 ))
        sleep 5
    done

    create_db() {
        local dbname=$1
        docker exec "${COMPOSE_PROJECT_NAME}-postgres" \
            psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
            -c "CREATE DATABASE ${dbname} OWNER ${POSTGRES_USER};" \
            2>/dev/null && \
            ok "Database '${dbname}' created" || \
            log "Database '${dbname}' already exists"
    }

    [ "${ENABLE_N8N}" = "true" ] && create_db "n8n"
    [ "${ENABLE_DIFY}" = "true" ] && create_db "dify"
    [ "${ENABLE_LITELLM}" = "true" ] && create_db "litellm"

    ok "PostgreSQL configured"
}

# ─────────────────────────────────────────────────────────────
# GRAFANA — Add Prometheus datasource
# ─────────────────────────────────────────────────────────────
configure_grafana() {
    [ "${ENABLE_GRAFANA}" = "true" ] || return 0
    log "Configuring Grafana..."
    wait_for_service "grafana" "http://localhost:${GRAFANA_PORT}/api/health" || return
    
    curl -sf -X POST \
        "http://localhost:${GRAFANA_PORT}/api/datasources" \
        -u "${GRAFANA_ADMIN_USER}:${GRAFANA_PASSWORD}" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"Prometheus\",
            \"type\": \"prometheus\",
            \"url\": \"http://prometheus:9090\",
            \"access\": \"proxy\",
            \"isDefault\": true
        }" 2>/dev/null && \
        ok "Grafana Prometheus datasource added" || \
        log "Datasource already configured"
}

# ─────────────────────────────────────────────────────────────
# PRINT CREDENTIALS SUMMARY
# ─────────────────────────────────────────────────────────────
print_credentials() {
    local border="═════════════════════════════════════════════════"
    echo ""
    echo "${border}"
    echo "  Configuration Complete — ${TENANT_ID}"
    echo "${border}"
    echo ""
    echo "  Service Credentials:"
    echo ""
    echo "  ┌─────────────────────────────────────────────────"
    echo "  │  MinIO"
    echo "  │    URL:      https://minio.${DOMAIN}"
    echo "  │    User:     ${MINIO_ROOT_USER}"
    echo "  │    Password: ${MINIO_ROOT_PASSWORD}"
    echo "  ├─────────────────────────────────────────────────"
    [ "${ENABLE_GRAFANA}" = "true" ] && {
    echo "  │  Grafana"
    echo "  │    URL:      https://grafana.${DOMAIN}"
    echo "  │    User:     ${GRAFANA_ADMIN_USER}"
    echo "  │    Password: ${GRAFANA_PASSWORD}"
    echo "  ├─────────────────────────────────────────────────"
    }
    [ "${ENABLE_FLOWISE}" = "true" ] && {
    echo "  │  Flowise"
    echo "  │    URL:      https://flowise.${DOMAIN}"
    echo "  │    User:     ${FLOWISE_USERNAME}"
    echo "  │    Password: ${FLOWISE_PASSWORD}"
    echo "  ├─────────────────────────────────────────────────"
    }
    [ "${ENABLE_LITELLM}" = "true" ] && {
    echo "  │  LiteLLM"
    echo "  │    URL:      https://litellm.${DOMAIN}"
    echo "  │    API Key:  ${LITELLM_MASTER_KEY}"
    echo "  ├─────────────────────────────────────────────────"
    }
    echo "  │  All credentials saved to: ${ENV_FILE}"
    echo "  └─────────────────────────────────────────────────"
    echo ""
    echo "${border}"
}

# ─────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────
main() {
    log "Starting service configuration for ${TENANT_ID}"

    configure_postgres
    configure_minio
    configure_qdrant
    configure_ollama
    configure_litellm
    configure_grafana

    print_credentials
    ok "All configuration complete"
}

main "$@"
