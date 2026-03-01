#!/usr/bin/env bash
set -euo pipefail

source "${ENV_FILE:-/mnt/data/u1001/.env}"

PROJECT_NAME="${COMPOSE_PROJECT_NAME}"
DOMAIN="${DOMAIN}"

log() { echo "[$(date '+%H:%M:%S')] [$1] $2"; }

wait_http() {
    local url=$1 name=$2 max=${3:-12}
    log "INFO" "Waiting for ${name}..."
    for i in $(seq 1 ${max}); do
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${url}" 2>/dev/null || echo "000")
        [[ "${code}" =~ ^(200|301|302|401|403)$ ]] && { log "SUCCESS" "${name} is up (${code})"; return 0; }
        sleep 10
    done
    log "WARN" "${name} did not respond after $((max*10))s — skipping integration"
    return 1
}

# ── 1. Qdrant Collections ──────────────────────────────────────
log "INFO" "Creating Qdrant collections..."

create_collection() {
    local name=$1 size=${2:-768}
    local resp
    resp=$(curl -s -o /dev/null -w "%{http_code}" \
        -X PUT "http://localhost:6333/collections/${name}" \
        -H "Content-Type: application/json" \
        -d "{\"vectors\":{\"size\":${size},\"distance\":\"Cosine\"}}" 2>/dev/null)
    log "INFO" "  Collection '${name}': HTTP ${resp}"
}

wait_http "http://localhost:6333/" "Qdrant" 6 && {
    create_collection "anythingllm_docs" 768
    create_collection "openclaw_docs" 768
    create_collection "dify_docs" 1536
    log "SUCCESS" "Qdrant collections ready"
}

# ── 2. Ollama Model Pull ───────────────────────────────────────
log "INFO" "Pulling Ollama embedding model (nomic-embed-text)..."
docker exec "${PROJECT_NAME}-ollama" \
    ollama pull nomic-embed-text:latest 2>/dev/null && \
    log "SUCCESS" "nomic-embed-text pulled" || \
    log "WARN" "nomic-embed-text pull failed — check ollama logs"

# ── 3. MinIO Buckets ───────────────────────────────────────────
log "INFO" "Creating MinIO buckets..."
docker exec "${PROJECT_NAME}-minio" sh -c "
    mc alias set local http://localhost:9000 \
        ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD} --quiet 2>/dev/null
    mc mb --ignore-existing local/aiplatform-docs 2>/dev/null
    mc mb --ignore-existing local/aiplatform-media 2>/dev/null
    mc mb --ignore-existing local/aiplatform-backups 2>/dev/null
    mc mb --ignore-existing local/dify 2>/dev/null
    mc mb --ignore-existing local/openclaw 2>/dev/null
    echo 'Buckets ready'
" && log "SUCCESS" "MinIO buckets created"

# ── 4. AnythingLLM Initial Configuration ──────────────────────
wait_http "http://localhost:5004/api/ping" "AnythingLLM" 12 && {
    log "INFO" "Configuring AnythingLLM LLM provider..."
    curl -s -X POST "http://localhost:5004/api/system/update-env" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${ANYTHINGLLM_JWT_SECRET}" \
        -d "{
            \"LLM_PROVIDER\": \"litellm\",
            \"LITELLM_BASE_URL\": \"http://litellm:4000\",
            \"LITELLM_API_KEY\": \"${LITELLM_MASTER_KEY}\",
            \"VECTOR_DB\": \"qdrant\",
            \"QDRANT_ENDPOINT\": \"http://qdrant:6333\",
            \"EMBEDDING_ENGINE\": \"ollama\",
            \"OLLAMA_BASE_PATH\": \"http://ollama:11434\",
            \"EMBEDDING_MODEL_PREF\": \"nomic-embed-text:latest\"
        }" 2>/dev/null | grep -o '"message":"[^"]*"' || true
    log "SUCCESS" "AnythingLLM configured"
}

# ── 5. Grafana Datasource ──────────────────────────────────────
wait_http "http://localhost:5001/api/health" "Grafana" 6 && {
    log "INFO" "Adding Prometheus datasource to Grafana..."
    curl -s -X POST "http://localhost:5001/api/datasources" \
        -H "Content-Type: application/json" \
        -u "ds-admin:${GRAFANA_PASSWORD}" \
        -d '{
            "name": "Prometheus",
            "type": "prometheus",
            "url": "http://prometheus:9090",
            "access": "proxy",
            "isDefault": true
        }' 2>/dev/null | grep -o '"message":"[^"]*"' || true
    log "SUCCESS" "Grafana datasource configured"
}

# ── 6. Tailscale Status ────────────────────────────────────────
log "INFO" "Checking Tailscale..."
TS_IP=$(docker exec "${PROJECT_NAME}-tailscale" tailscale ip -4 2>/dev/null || echo "")
if [ -z "${TS_IP}" ]; then
    log "WARN" "Tailscale not connected."
    log "WARN" "Action required:"
    log "WARN" "  1. Get auth key: https://login.tailscale.com/admin/settings/keys"
    log "WARN" "  2. Add to .env: TAILSCALE_AUTH_KEY=tskey-auth-xxxxx"
    log "WARN" "  3. docker rm -f ${PROJECT_NAME}-tailscale"
    log "WARN" "  4. docker compose -f ${COMPOSE_FILE} up -d tailscale"
else
    log "SUCCESS" "Tailscale IP: ${TS_IP}"
fi

# ── 7. Rclone GDrive Setup ────────────────────────────────────
log "INFO" "Checking rclone/GDrive..."
if [ "${GDRIVE_ENABLED:-false}" = "true" ]; then
    RCLONE_CONF="/mnt/data/u1001/rclone/config/rclone.conf"
    if [ ! -f "${RCLONE_CONF}" ]; then
        log "WARN" "rclone.conf not found at ${RCLONE_CONF}"
        log "WARN" "GDrive OAuth required. Run:"
        log "WARN" "  sudo bash scripts/setup-rclone.sh"
        log "WARN" "  (This will be provided separately)"
    else
        log "SUCCESS" "rclone.conf exists — GDrive configured"
        docker exec "${PROJECT_NAME}-rclone" \
            rclone lsd ${GDRIVE_RCLONE_REMOTE:-gdrive-u1001}: \
            --max-depth 1 2>/dev/null && \
            log "SUCCESS" "GDrive connection verified" || \
            log "WARN" "GDrive connection failed — check rclone.conf"
    fi
fi

# ── 8. Final URL Dashboard ────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         AI PLATFORM — INTEGRATION COMPLETE                   ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo ""
echo "  URLs:"

check_url() {
    local name=$1 url=$2
    local code
    code=$(curl -o /dev/null -s -w "%{http_code}" \
        --max-time 8 --connect-timeout 5 "${url}" 2>/dev/null || echo "000")
    local icon="❌"
    [[ "${code}" =~ ^(200|301|302|401|403)$ ]] && icon="✅"
    printf "  %s  %-20s  %s  [%s]\n" "${icon}" "${name}" "${url}" "${code}"
}

check_url "AnythingLLM"   "https://anythingllm.${DOMAIN}"
check_url "OpenClaw"      "https://openclaw.${DOMAIN}"
check_url "Open WebUI"    "https://openwebui.${DOMAIN}"
check_url "Dify"          "https://dify.${DOMAIN}"
check_url "n8n"           "https://n8n.${DOMAIN}"
check_url "Flowise"       "https://flowise.${DOMAIN}"
check_url "LiteLLM"       "https://litellm.${DOMAIN}/health"
check_url "Grafana"       "https://grafana.${DOMAIN}"
check_url "MinIO"         "https://minio.${DOMAIN}"

echo ""
echo "  Tailscale: ${TS_IP:-not connected}"
echo "  Domain: ${DOMAIN}"
echo "╚══════════════════════════════════════════════════════════════╝"
