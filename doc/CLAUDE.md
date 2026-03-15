# WINDSURF.md — Final Implementation Plan
# Author: Claude (Architect Review of WINDSURF-IMPLEMENTATION.md)
# Status: APPROVED WITH MANDATORY CHANGES — do not implement without reading every pushback

---

## Executive Review of Windsurf's Plan

The WINDSURF-IMPLEMENTATION.md framework is **architecturally correct** on:
- Script 3 as sourced library with `(return 0 2>/dev/null) && return` guard
- UID-aware ownership in `prepare_directories()`
- Variable ordering in `.env` (primitives before derived)
- `generate_configs()` as the single entry point for all config generation
- Idempotent `generate_compose()` called by script 2

**7 mandatory changes before implementation.** Each one prevents a deployment failure
or violates a core principle. They are not style preferences — they are blocking issues.

---

## PUSHBACK 1 — `/opt/ai-platform` must go. Everything moves to `/mnt`.

### What Windsurf proposed
```bash
BASE_DIR="/opt/ai-platform"
ENV_FILE="${BASE_DIR}/.env"
```

### Why it must change
`/opt` is outside `/mnt`. The principle is **nothing outside `/mnt` as much as possible**.
The only justified exception is system packages installed by the OS package manager.
A `.env` file with secrets living in `/opt` is both a violation of the principle and
a security risk (world-readable by default on many systems).

### The fix — single source of truth, everything under `/mnt`
```bash
# In script 3, top of file — the ONLY place these are defined
MNT_ROOT="/mnt/data"
TENANT="${TENANT:-default}"
TENANT_DIR="${MNT_ROOT}/${TENANT}"
CONFIG_DIR="${TENANT_DIR}/configs"
DATA_DIR="${TENANT_DIR}/data"
LOGS_DIR="${TENANT_DIR}/logs"
COMPOSE_FILE="${TENANT_DIR}/docker-compose.yml"
ENV_FILE="${TENANT_DIR}/.env"          # ← under /mnt, not /opt

# Script 1 writes .env here during setup.
# All other scripts source it from here.
# No /opt path exists anywhere in the codebase.
```

The only reference to `/opt` that is acceptable is Docker's own installation path
(`/opt/containerd` etc.) which is managed by the OS, not by our scripts.

---

## PUSHBACK 2 — The postgres init script has a shell quoting bug that will silently fail.

### What Windsurf proposed
```bash
cat > "$out" <<'INITEOF'   # ← single-quoted heredoc = NO variable expansion
...
      CREATE ROLE aiplatform WITH LOGIN PASSWORD '${POSTGRES_PASSWORD}';
...
INITEOF
```

### Why it fails
The single-quoted `<<'INITEOF'` means `${POSTGRES_PASSWORD}` is written **literally**
into the script file — the postgres container will try to set the password to the
string `${POSTGRES_PASSWORD}` not the actual password. This will silently create a
role with a wrong password and every service connection will fail with auth errors.

### The fix — double-quoted heredoc with escaped inner dollars
```bash
generate_postgres_init() {
    local out="${CONFIG_DIR}/postgres/init-user-db.sh"
    mkdir -p "$(dirname "$out")"
    # Double-quoted: POSTGRES_PASSWORD expands NOW at generation time.
    # Inner \$\$ escapes are for the psql DO block's dollar-quoting.
    cat > "$out" <<EOF
#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 --username "\$POSTGRES_USER" --dbname "\$POSTGRES_DB" <<EOSQL
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'aiplatform') THEN
      CREATE ROLE aiplatform WITH LOGIN PASSWORD '${DB_PASSWORD}';
    END IF;
  END \$\$;
  SELECT 'CREATE DATABASE litellm   OWNER aiplatform'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='litellm')   \gexec
  SELECT 'CREATE DATABASE openwebui OWNER aiplatform'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='openwebui') \gexec
  SELECT 'CREATE DATABASE n8n       OWNER aiplatform'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='n8n')       \gexec
  GRANT ALL PRIVILEGES ON DATABASE litellm   TO aiplatform;
  GRANT ALL PRIVILEGES ON DATABASE openwebui TO aiplatform;
  GRANT ALL PRIVILEGES ON DATABASE n8n       TO aiplatform;
EOSQL
EOF
    chmod +x "$out"
    # postgres container runs as UID 70 — must be able to read this file
    chown 70:"${TENANT_GID:-1001}" "$out"
    log_success "Postgres init script written to ${out}"
}
```

---

## PUSHBACK 3 — LiteLLM is wired as a sidecar. It must be the **central AI bus** for ALL web services.

### What the README requires (core objective)
> "Centralized LiteLLM routing" — "Multiple AI applications consuming the same embeddings"

### What Windsurf's plan does
LiteLLM is deployed as just another service. OpenWebUI, AnythingLLM, n8n, Flowise
are deployed with no explicit wiring to LiteLLM. Each will default to its own
built-in model configuration and bypass the router entirely.

### The fix — every web service must point to LiteLLM via environment config

Add this to `generate_compose()` for every web service block. These are not optional:

**OpenWebUI** — must use LiteLLM as its OpenAI-compatible endpoint:
```yaml
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    restart: unless-stopped
    user: "1000:${TENANT_GID:-1001}"
    depends_on:
      litellm:
        condition: service_healthy
    environment:
      OPENAI_API_BASE_URL: "http://litellm:4000/v1"
      OPENAI_API_KEY: "${LITELLM_MASTER_KEY}"
      WEBUI_SECRET_KEY: "${JWT_SECRET}"
      DATABASE_URL: "${OPENWEBUI_DATABASE_URL}"
      # Vector DB wiring — routes through the selected vector backend
      VECTOR_DB: "${VECTOR_DB_TYPE:-qdrant}"
      QDRANT_URI: "http://qdrant:6333"
    volumes:
      - ${DATA_DIR}/openwebui:/app/backend/data
    ports:
      - "${PORT_OPENWEBUI:-3000}:8080"
```

**AnythingLLM** — must use LiteLLM as its LLM provider:
```yaml
  anythingllm:
    image: mintplexlabs/anythingllm:latest
    restart: unless-stopped
    user: "1000:${TENANT_GID:-1001}"
    depends_on:
      litellm:
        condition: service_healthy
    environment:
      LLM_PROVIDER: "openai"
      OPEN_AI_KEY: "${LITELLM_MASTER_KEY}"
      OPEN_AI_BASE_PATH: "http://litellm:4000/v1"
      EMBEDDING_ENGINE: "openai"
      EMBEDDING_BASE_PATH: "http://litellm:4000/v1"
      VECTOR_DB: "${VECTOR_DB_TYPE:-qdrant}"
      QDRANT_ENDPOINT: "http://qdrant:6333"
      STORAGE_DIR: "/app/server/storage"
    volumes:
      - ${DATA_DIR}/anythingllm:/app/server/storage
    ports:
      - "${PORT_ANYTHINGLLM:-3001}:3001"
```

**n8n** — must use LiteLLM for all AI nodes:
```yaml
  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    user: "1000:${TENANT_GID:-1001}"
    depends_on:
      litellm:
        condition: service_healthy
      postgres:
        condition: service_healthy
    environment:
      N8N_AI_OPENAI_API_KEY: "${LITELLM_MASTER_KEY}"
      N8N_AI_OPENAI_BASE_URL: "http://litellm:4000/v1"
      DB_TYPE: "postgresdb"
      DB_POSTGRESDB_HOST: "postgres"
      DB_POSTGRESDB_PORT: "5432"
      DB_POSTGRESDB_DATABASE: "n8n"
      DB_POSTGRESDB_USER: "${POSTGRES_USER}"
      DB_POSTGRESDB_PASSWORD: "${POSTGRES_PASSWORD}"
      N8N_ENCRYPTION_KEY: "${ENCRYPTION_KEY}"
      WEBHOOK_URL: "https://n8n.${DOMAIN}"
    volumes:
      - ${DATA_DIR}/n8n:/home/node/.n8n
    ports:
      - "${PORT_N8N:-5678}:5678"
```

**Flowise** — must use LiteLLM:
```yaml
  flowise:
    image: flowiseai/flowise:latest
    restart: unless-stopped
    user: "1000:${TENANT_GID:-1001}"
    depends_on:
      litellm:
        condition: service_healthy
    environment:
      OPENAI_API_KEY: "${LITELLM_MASTER_KEY}"
      OPENAI_API_BASE: "http://litellm:4000/v1"
      DATABASE_PATH: "/root/.flowise"
      FLOWISE_USERNAME: "admin"
      FLOWISE_PASSWORD: "${ADMIN_PASSWORD}"
      SECRETKEY_PATH: "/root/.flowise"
    volumes:
      - ${DATA_DIR}/flowise:/root/.flowise
    ports:
      - "${PORT_FLOWISE:-3001}:3000"
```

### Add to `.env` generation in `generate_env()`
```bash
# ─── LiteLLM Routing Strategy (collected in script 1) ─────────────────────
LITELLM_ROUTING_STRATEGY=${LITELLM_ROUTING_STRATEGY:-least-busy}
# Options: least-busy | latency-based-routing | cost-based-routing | simple-shuffle

# ─── Vector DB Selection (collected in script 1) ──────────────────────────
VECTOR_DB_TYPE=${VECTOR_DB_TYPE:-qdrant}
# Options: qdrant | weaviate | milvus
```

### Add to `collect_domain_config()` in script 1 — two new questions
```bash
echo ""
echo "🔀 LiteLLM Routing Strategy:"
echo "  1) least-busy     (default — spread load)"
echo "  2) latency-based  (fastest model wins)"
echo "  3) cost-based     (cheapest model wins)"
read -p "  Choose [1]: " route_choice
case "${route_choice:-1}" in
    2) LITELLM_ROUTING_STRATEGY="latency-based-routing" ;;
    3) LITELLM_ROUTING_STRATEGY="cost-based-routing" ;;
    *) LITELLM_ROUTING_STRATEGY="least-busy" ;;
esac

echo ""
echo "🗃️  Vector Database:"
echo "  1) Qdrant     (default — lightweight, fast)"
echo "  2) Weaviate   (GraphQL API, hybrid search)"
read -p "  Choose [1]: " vdb_choice
case "${vdb_choice:-1}" in
    2) VECTOR_DB_TYPE="weaviate" ; ENABLE_WEAVIATE=true ; ENABLE_QDRANT=false ;;
    *) VECTOR_DB_TYPE="qdrant"   ; ENABLE_QDRANT=true ;;
esac
```

### Update `generate_litellm_config()` — use routing strategy from `.env`
```bash
cat >> "$out" <<EOF
router_settings:
  routing_strategy: ${LITELLM_ROUTING_STRATEGY:-least-busy}
  fallbacks:
    - gpt-4o: ["gpt-4o-mini", "claude-3-5-sonnet", "llama3-groq"]
    - claude-3-5-sonnet: ["gpt-4o", "gpt-4o-mini"]
  model_group_alias:
    default: "${OLLAMA_MODELS%,*}"
EOF
```

---

## PUSHBACK 4 — The `_check()` function in `health_dashboard()` is broken for Postgres/Redis.

### What Windsurf proposed
```bash
_check "Postgres" "$(docker compose -f "$COMPOSE_FILE" exec -T postgres pg_isready ... && echo ok || echo fail)"
```

### Why it fails
`_check` calls `curl -sf` on its second argument. Passing `ok` or `fail` as a URL
to curl will throw an error. The function logic is inconsistent — some services
use HTTP URLs, others use shell commands.

### The fix — separate the two check types cleanly
```bash
_check_http() {
    local name="$1" url="$2"
    if curl -sf --max-time 5 "$url" > /dev/null 2>&1; then
        printf "  ${GREEN}🟢 %-22s${NC} %s\n" "$name" "$url"
    else
        printf "  ${RED}🔴 %-22s${NC} %s\n" "$name" "$url"
    fi
}

_check_cmd() {
    local name="$1"; shift
    if "$@" > /dev/null 2>&1; then
        printf "  ${GREEN}🟢 %-22s${NC} %s\n" "$name" "$(docker compose -f "$COMPOSE_FILE" ps --format "{{.Status}}" "$name" 2>/dev/null | head -1)"
    else
        printf "  ${RED}🔴 %-22s${NC} %s\n" "$name" "not responding"
    fi
}

health_dashboard() {
    set -a; source "$ENV_FILE"; set +a
    local ts ip=""
    ts=$(date '+%Y-%m-%d %H:%M:%S')

    # Tailscale IP
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q tailscale; then
        ip=$(docker compose -f "$COMPOSE_FILE" exec -T tailscale \
             tailscale ip -4 2>/dev/null | tr -d ' \n' || true)
    fi

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  AI PLATFORM HEALTH DASHBOARD — ${ts}    ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    printf "  %-14s %s\n" "Domain:"       "https://${DOMAIN}"
    printf "  %-14s %s\n" "Tailscale IP:" "${ip:-NOT CONNECTED}"
    printf "  %-14s %s\n" "Tenant:"       "${TENANT}"
    printf "  %-14s %s\n" "Data:"         "${TENANT_DIR}"
    echo ""
    echo -e "  ${BOLD}Infrastructure${NC}"
    _check_cmd  "postgres"   docker compose -f "$COMPOSE_FILE" exec -T postgres \
                             pg_isready -U "${POSTGRES_USER}" -q
    _check_cmd  "redis"      docker compose -f "$COMPOSE_FILE" exec -T redis \
                             redis-cli -a "${REDIS_PASSWORD}" ping
    [[ "${ENABLE_QDRANT:-false}"    == "true" ]] && \
        _check_http "qdrant"     "http://localhost:${PORT_QDRANT:-6333}/collections"
    echo ""
    echo -e "  ${BOLD}Monitoring${NC}"
    [[ "${ENABLE_MONITORING:-false}" == "true" ]] && {
        _check_http "prometheus" "http://localhost:${PORT_PROMETHEUS:-9090}/-/healthy"
        _check_http "grafana"    "http://localhost:${PORT_GRAFANA:-3002}/api/health"
    }
    _check_http "caddy"      "http://localhost:2019/metrics"
    echo ""
    echo -e "  ${BOLD}AI Services${NC}"
    [[ "${ENABLE_LITELLM:-false}"    == "true" ]] && \
        _check_http "litellm"    "http://localhost:${PORT_LITELLM:-4000}/health/liveliness"
    [[ "${ENABLE_OLLAMA:-false}"     == "true" ]] && \
        _check_http "ollama"     "http://localhost:11434/"
    echo ""
    echo -e "  ${BOLD}Web Services (all routed via LiteLLM)${NC}"
    [[ "${ENABLE_OPENWEBUI:-false}"  == "true" ]] && \
        _check_http "open-webui"     "http://localhost:${PORT_OPENWEBUI:-3000}/"
    [[ "${ENABLE_N8N:-false}"        == "true" ]] && \
        _check_http "n8n"            "http://localhost:${PORT_N8N:-5678}/healthz"
    [[ "${ENABLE_FLOWISE:-false}"    == "true" ]] && \
        _check_http "flowise"        "http://localhost:${PORT_FLOWISE:-3001}/"
    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && \
        _check_http "anythingllm"    "http://localhost:${PORT_ANYTHINGLLM:-3003}/"
    echo ""
    echo -e "  ${BOLD}Quick Tests${NC}"
    echo -e "  LiteLLM models:"
    echo -e "    curl -s http://localhost:${PORT_LITELLM:-4000}/v1/models \\"
    echo -e "      -H 'Authorization: Bearer \${LITELLM_MASTER_KEY}' | jq '.data[].id'"
    echo ""
    log_write INFO "Health dashboard printed at ${ts}"
}
```

---

## PUSHBACK 5 — The CLI dispatcher is too thin. Script 3 must cover the full service lifecycle.

### What Windsurf proposed
```bash
case "$cmd" in
    deploy|health|generate|compose|dirs|env) ... ;;
```

### What the README requires
> "Modular service lifecycle management" — "Support incremental extensibility
> without full redeployment"

### The fix — complete CLI dispatcher
```bash
(return 0 2>/dev/null) && return   # sourced — stop here, export functions

main() {
    local cmd="${1:-help}"
    shift || true
    case "$cmd" in
        # ── Deployment ──────────────────────────────────────────────
        deploy)         deploy_service "${1:?usage: deploy <service>}" ;;
        deploy-all)     bash "$(dirname "$0")/2-deploy-services.sh" ;;
        stop)           stop_service   "${1:?usage: stop <service>}" ;;
        stop-all)       docker compose -f "$COMPOSE_FILE" down ;;
        restart)        reconfigure_service "${1:?usage: restart <service>}" ;;

        # ── Configuration ────────────────────────────────────────────
        generate)       generate_configs ;;
        compose)        generate_compose ;;
        dirs)           prepare_directories ;;
        env)            echo "Re-run script 1 to regenerate .env safely" ;;

        # ── Health & Monitoring ──────────────────────────────────────
        health)         health_dashboard ;;
        status)         docker compose -f "$COMPOSE_FILE" ps ;;
        logs)           docker compose -f "$COMPOSE_FILE" logs --tail=50 "${1:-}" ;;
        logs-on)        log_enable  "${1:?usage: logs-on <service>}" ;;
        logs-off)       log_disable "${1:?usage: logs-off <service>}" ;;

        # ── External Wiring ──────────────────────────────────────────
        tailscale)      configure_tailscale ;;
        gdrive)         setup_gdrive_rclone && create_ingestion_systemd ;;

        # ── Service Reconfiguration ──────────────────────────────────
        reconfigure)    reconfigure_service "${1:?usage: reconfigure <service>}" ;;
        enable)         enable_service  "${1:?usage: enable <service>}" ;;
        disable)        disable_service "${1:?usage: disable <service>}" ;;

        # ── Help ─────────────────────────────────────────────────────
        help|*)
            echo ""
            echo "Usage: $0 <command> [service]"
            echo ""
            echo "  Deployment:    deploy <svc>  stop <svc>  restart <svc>  deploy-all  stop-all"
            echo "  Configuration: generate  compose  dirs"
            echo "  Health:        health  status  logs [svc]  logs-on <svc>  logs-off <svc>"
            echo "  Wiring:        tailscale  gdrive"
            echo "  Lifecycle:     enable <svc>  disable <svc>  reconfigure <svc>"
            echo ""
            ;;
    esac
}

main "$@"
```

### Add `enable_service()` and `disable_service()` to the function library
```bash
enable_service() {
    local svc="$1"
    local flag="ENABLE_$(echo "$svc" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
    log_info "Enabling ${svc} (sets ${flag}=true in .env)..."
    grep -q "^${flag}=" "$ENV_FILE" \
        && sed -i "s|^${flag}=.*|${flag}=true|" "$ENV_FILE" \
        || echo "${flag}=true" >> "$ENV_FILE"
    generate_configs
    generate_compose
    deploy_service "$svc"
    log_success "${svc} enabled and deployed"
}

disable_service() {
    local svc="$1"
    local flag="ENABLE_$(echo "$svc" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
    log_info "Disabling ${svc}..."
    stop_service "$svc"
    grep -q "^${flag}=" "$ENV_FILE" \
        && sed -i "s|^${flag}=.*|${flag}=false|" "$ENV_FILE" \
        || echo "${flag}=false" >> "$ENV_FILE"
    log_success "${svc} stopped and disabled"
}

stop_service() {
    local svc="$1"
    docker compose -f "$COMPOSE_FILE" stop "$svc" \
        && log_success "${svc} stopped" \
        || log_warning "${svc} was not running"
}

reconfigure_service() {
    local svc="$1"
    log_info "Reconfiguring ${svc}..."
    generate_configs
    generate_compose
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" \
        up -d --force-recreate "$svc" \
        >> "${LOGS_DIR}/deploy-$(date +%Y%m%d).log" 2>&1
    log_success "${svc} reconfigured"
}
```

---

## PUSHBACK 6 — The Caddy TLS block is missing. Windsurf removed it silently.

### What Windsurf proposed
```
grafana.${DOMAIN}    { reverse_proxy grafana:3000 }
```
No TLS directive. Caddy will attempt HTTPS by default (ACME) for any non-localhost
domain, which is correct — **but only if the email is configured in the global block**.
For local/self-signed (`USE_LETSENCRYPT=false`) this will hang waiting for ACME
challenges that will never come.

### The fix — explicit TLS handling in `generate_caddyfile()`
```bash
generate_caddyfile() {
    local out="${CONFIG_DIR}/caddy/Caddyfile"
    mkdir -p "$(dirname "$out")"

    # Choose TLS directive once based on USE_LETSENCRYPT
    local tls_line
    if [[ "${USE_LETSENCRYPT:-false}" == "true" ]]; then
        tls_line="tls ${ADMIN_EMAIL}"       # ACME with Let's Encrypt
    else
        tls_line="tls internal"             # Caddy self-signed — no ACME hang
    fi

    cat > "$out" <<EOF
{
    admin 0.0.0.0:2019
    email ${ADMIN_EMAIL:-admin@${DOMAIN}}
}

grafana.${DOMAIN} {
    ${tls_line}
    reverse_proxy grafana:3000
}
prometheus.${DOMAIN} {
    ${tls_line}
    reverse_proxy prometheus:9090
}
EOF
    # Append enabled services
    [[ "${ENABLE_LITELLM:-false}"     == "true" ]] && cat >> "$out" <<EOF
litellm.${DOMAIN} {
    ${tls_line}
    reverse_proxy litellm:4000
}
EOF
    [[ "${ENABLE_OPENWEBUI:-false}"   == "true" ]] && cat >> "$out" <<EOF
chat.${DOMAIN} {
    ${tls_line}
    reverse_proxy open-webui:8080
}
EOF
    [[ "${ENABLE_N8N:-false}"         == "true" ]] && cat >> "$out" <<EOF
n8n.${DOMAIN} {
    ${tls_line}
    reverse_proxy n8n:5678
}
EOF
    [[ "${ENABLE_FLOWISE:-false}"     == "true" ]] && cat >> "$out" <<EOF
flowise.${DOMAIN} {
    ${tls_line}
    reverse_proxy flowise:3000
}
EOF
    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && cat >> "$out" <<EOF
anythingllm.${DOMAIN} {
    ${tls_line}
    reverse_proxy anythingllm:3001
}
EOF
    log_success "Caddyfile written to ${out}"
}
```

---

## PUSHBACK 7 — Script 2 deployment order is missing Ollama before LiteLLM.

### What Windsurf proposed
```bash
[[ "${ENABLE_LITELLM:-false}" == "true" ]] && deploy_service litellm
deploy_service caddy
[[ "${ENABLE_OLLAMA:-false}"  == "true" ]] && deploy_service ollama
```

### Why it matters
LiteLLM's config.yaml lists `api_base: http://ollama:11434`. If Ollama is not running
when LiteLLM starts, LiteLLM will fail health checks on model load. For `start_period: 90s`
this may recover — but it generates avoidable restart loops and log noise. Ollama must
start before LiteLLM, and LiteLLM must be healthy before any web service starts.

### The correct deployment order in script 2 `main()`
```bash
main() {
    log_info "=== DEPLOY START ==="

    [[ -f "$ENV_FILE" ]] || { log_error ".env not found at ${ENV_FILE}. Run script 1 first."; exit 1; }

    # 1. Regenerate all config files and compose (idempotent)
    prepare_directories
    generate_configs
    generate_compose

    # 2. Infra layer — must be healthy before anything else
    deploy_service postgres
    deploy_service redis
    provision_databases          # waits until postgres ready, verifies DBs

    # 3. Vector DB
    [[ "${ENABLE_QDRANT:-false}"     == "true" ]] && deploy_service qdrant

    # 4. Local LLM runtime — BEFORE LiteLLM
    [[ "${ENABLE_OLLAMA:-false}"     == "true" ]] && deploy_service ollama

    # 5. AI gateway — depends on postgres, redis; optionally ollama
    [[ "${ENABLE_LITELLM:-false}"    == "true" ]] && deploy_service litellm

    # 6. Monitoring — independent of AI services
    [[ "${ENABLE_MONITORING:-false}" == "true" ]] && {
        deploy_service prometheus
        deploy_service grafana
    }

    # 7. Reverse proxy — depends only on infra (postgres, redis healthy)
    deploy_service caddy

    # 8. Web services — AFTER litellm is healthy
    [[ "${ENABLE_OPENWEBUI:-false}"   == "true" ]] && deploy_service open-webui
    [[ "${ENABLE_N8N:-false}"         == "true" ]] && deploy_service n8n
    [[ "${ENABLE_FLOWISE:-false}"     == "true" ]] && deploy_service flowise
    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && deploy_service anythingllm

    # 9. External wiring (non-blocking — skip gracefully if not configured)
    configure_tailscale
    [[ -n "${GDRIVE_CLIENT_ID:-}" ]] && setup_gdrive_rclone && create_ingestion_systemd

    # 10. Health dashboard — script 2 STOPS after this
    health_dashboard

    log_info "=== DEPLOY COMPLETE ==="
}
```

---

## Summary: What Windsurf Keeps vs What Changes

### KEEP from WINDSURF-IMPLEMENTATION.md (correct as-is)
- `(return 0 2>/dev/null) && return` guard on script 3 `main()` ✅
- `generate_configs()` as single entry point ✅
- `generate_compose()` building YAML dynamically from flags ✅
- UID-aware `prepare_directories()` structure ✅
- Variable ordering in `.env` (primitives first, derived after) ✅
- `log_write()` as the single log writer used by all scripts ✅
- Script 1 stripped to interactive collector + `source` of script 3 ✅
- Script 2 as idempotent deployer calling `health_dashboard` then stopping ✅
- `provision_databases()` waiting loop ✅

### MANDATORY CHANGES (implement all 7 before merging)
1. Move `ENV_FILE` from `/opt/ai-platform/.env` to `/mnt/data/${TENANT}/.env` — **nothing outside /mnt**
2. Fix postgres init heredoc quoting — `<<'INITEOF'` → `<<EOF` with correct escaping
3. Wire ALL web services to LiteLLM via env config — OpenWebUI, AnythingLLM, n8n, Flowise
4. Fix `health_dashboard()` — separate `_check_http()` and `_check_cmd()` functions
5. Expand CLI dispatcher with full lifecycle: `enable`, `disable`, `reconfigure`, `stop-all`, `logs`
6. Add explicit `tls internal` / `tls ${ADMIN_EMAIL}` to every Caddyfile block
7. Fix deployment order: Ollama → LiteLLM → web services (never reverse)

---

## Implementation Checklist for Windsurf

```
[ ] 3-configure-services.sh
    [ ] ENV_FILE="${TENANT_DIR}/.env" (not /opt)
    [ ] No /opt paths anywhere
    [ ] postgres init uses <<EOF not <<'INITEOF'
    [ ] generate_caddyfile() has tls_line in every server block
    [ ] generate_litellm_config() uses LITELLM_ROUTING_STRATEGY from .env
    [ ] All web service compose blocks have LiteLLM env wiring
    [ ] health_dashboard() uses _check_http() and _check_cmd() separately
    [ ] CLI dispatcher has full command set including enable/disable/reconfigure
    [ ] enable_service() and disable_service() functions present
    [ ] (return 0 2>/dev/null) && return guard present

[ ] 1-setup-system.sh
    [ ] source "${SCRIPT_DIR}/3-configure-services.sh" as second line
    [ ] Routing strategy question added to collect_domain_config()
    [ ] Vector DB selection question added to collect_domain_config()
    [ ] TENANT_NAME question added
    [ ] ADMIN_EMAIL question added (used by Caddy + Let's Encrypt)
    [ ] generate_env / prepare_directories / generate_configs called from main()
    [ ] No function definitions that duplicate script 3

[ ] 2-deploy-services.sh
    [ ] source "${SCRIPT_DIR}/3-configure-services.sh" as second line
    [ ] ENV_FILE check uses /mnt/data path
    [ ] Deployment order: postgres → redis → qdrant → ollama → litellm → monitoring → caddy → web
    [ ] health_dashboard() called as final step
    [ ] Script stops after health_dashboard (no interactive prompts)

[ ] Verification (run after edits, before committing)
    [ ] grep -r "/opt/ai-platform" scripts/  → zero matches
    [ ] grep "docker run" scripts/3-configure-services.sh → zero matches
    [ ] grep "OPENAI_API_BASE\|LLM_PROVIDER\|OPEN_AI_BASE" generated compose → present for web svcs
    [ ] bash -n scripts/3-configure-services.sh → no syntax errors
    [ ] bash -n scripts/1-setup-system.sh → no syntax errors
    [ ] bash -n scripts/2-deploy-services.sh → no syntax errors
```