Final Assessment — Complete Issue List
What Is Working Well ✅
After reading all scripts carefully:

Script 1 interactive flow is solid — tenant setup, GPU detection, service selection, password generation (alphanumeric), .env written to /mnt/data/TENANTID/
Script 2 dynamic compose generation architecture is correct — heredocs write real values, not variable references
Script 0 cleanup order is now correct — containers stop before network removal
Directory creation with per-service UID ownership (setup_directories()) is present
BASH_SOURCE guard exists in script 2
--env-file flag present on docker compose calls
Prometheus and LiteLLM configs generated before deploy
Dify env vars are present
N8N encryption key present


Remaining Blocking Issues
BLOCK 1 — Caddy TLS bootstrap race condition
Problem: Caddy starts and immediately tries to obtain TLS certificates via ACME for all subdomains. But the upstream services (n8n, dify, etc.) are still starting. Caddy's ACME challenge requires port 80 to be reachable from the internet. If the EC2 security group doesn't have port 80 open, all TLS will fail permanently (Let's Encrypt will rate-limit after 5 failures in an hour).
Additionally Caddy healthchecks the backends during startup — if backends aren't up yet, Caddy logs errors but still serves. This is fine. But if Caddy itself crashes during TLS bootstrap, nothing is reachable.
Fix — Add to script 2 a pre-flight port check:
preflight_checks() {
    log "INFO" "Running pre-flight checks..."

    # Check ports 80 and 443 are not already bound
    for port in 80 443; do
        if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
            log "ERROR" "Port ${port} already in use — Caddy cannot start"
            log "ERROR" "Run: sudo ss -tlnp | grep :${port} to identify process"
            exit 1
        fi
    done

    # Check DNS resolves to this machine (warn only, not fail)
    local public_ip
    public_ip=$(curl -sf --max-time 5 https://api.ipify.org || \
                curl -sf --max-time 5 http://checkip.amazonaws.com || \
                echo "unknown")

    if [ "${public_ip}" != "unknown" ]; then
        log "INFO" "Public IP: ${public_ip}"
        log "WARN" "Ensure DNS A records point to ${public_ip} before Caddy starts"
        log "WARN" "Ensure EC2 security group allows inbound port 80 and 443"
    fi

    # Check Docker daemon is running
    if ! docker info &>/dev/null; then
        log "ERROR" "Docker daemon not running"
        exit 1
    fi

    # Check EBS mount
    if ! mountpoint -q /mnt; then
        log "ERROR" "/mnt is not a mount point — EBS not attached"
        exit 1
    fi

    log "SUCCESS" "Pre-flight checks passed"
}
Fix — Caddy startup order in compose:
Caddy must start after all backends have healthy status. Add explicit depends_on with condition: service_healthy to the Caddy service for every enabled backend:
append_caddy() {
    # Build depends_on block dynamically
    local depends=""
    [ "${ENABLE_OPENWEBUI}" = "true" ] && \
        depends+=$'      open-webui:\n        condition: service_healthy\n'
    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && \
        depends+=$'      anythingllm:\n        condition: service_healthy\n'
    [ "${ENABLE_N8N}" = "true" ] && \
        depends+=$'      n8n:\n        condition: service_healthy\n'
    [ "${ENABLE_DIFY}" = "true" ] && \
        depends+=$'      dify-api:\n        condition: service_healthy\n'
    [ "${ENABLE_FLOWISE}" = "true" ] && \
        depends+=$'      flowise:\n        condition: service_healthy\n'
    [ "${ENABLE_LITELLM}" = "true" ] && \
        depends+=$'      litellm:\n        condition: service_healthy\n'
    [ "${ENABLE_GRAFANA}" = "true" ] && \
        depends+=$'      grafana:\n        condition: service_healthy\n'

    compose_append << EOF

  caddy:
    image: caddy:2-alpine
    container_name: ${COMPOSE_PROJECT_NAME}-caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "2019:2019"
    volumes:
      - ${DATA_ROOT}/caddy/config:/etc/caddy
      - ${DATA_ROOT}/caddy/data:/data
      - ${DATA_ROOT}/logs:/var/log/caddy
    networks:
      - ${DOCKER_NETWORK}
    depends_on:
      postgres:
        condition: service_healthy
$(echo "${depends}")
    healthcheck:
      test: ["CMD", "caddy", "validate", "--config", "/etc/caddy/Caddyfile"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF
}

BLOCK 2 — Tailscale IP output for OpenClaw is missing
Problem: After deployment, the Tailscale IP (used to access OpenClaw at http://TS_IP:PORT) is never retrieved or displayed. tailscale up inside the container must be triggered and the IP captured.
Fix — Add to end of main() in script 2:
output_tailscale_info() {
    [ "${ENABLE_TAILSCALE}" = "true" ] || return 0

    log "INFO" "Waiting for Tailscale to authenticate..."
    local max_wait=60
    local elapsed=0

    while [ ${elapsed} -lt ${max_wait} ]; do
        local ts_ip
        ts_ip=$(docker exec "${COMPOSE_PROJECT_NAME}-tailscale" \
            tailscale ip -4 2>/dev/null || echo "")

        if [ -n "${ts_ip}" ] && [ "${ts_ip}" != "127.0.0.1" ]; then
            log "SUCCESS" "Tailscale IP: ${ts_ip}"

            # Write to .env for script 3 and 4 to use
            if grep -q "^TAILSCALE_IP=" "${ENV_FILE}"; then
                sed -i "s|^TAILSCALE_IP=.*|TAILSCALE_IP=${ts_ip}|" "${ENV_FILE}"
            else
                echo "TAILSCALE_IP=${ts_ip}" >> "${ENV_FILE}"
            fi

            # Print access URLs
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo " TAILSCALE ACCESS URLS"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            [ "${ENABLE_OPENCLAW}" = "true" ] && \
                echo " OpenClaw  : http://${ts_ip}:${OPENCLAW_PORT}"
            [ "${ENABLE_OPENWEBUI}" = "true" ] && \
                echo " OpenWebUI : http://${ts_ip}:${OPENWEBUI_PORT}"
            [ "${ENABLE_N8N}" = "true" ] && \
                echo " n8n       : http://${ts_ip}:${N8N_PORT}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
            return 0
        fi

        sleep 5
        elapsed=$((elapsed + 5))
        log "INFO" "Waiting for Tailscale IP... (${elapsed}s/${max_wait}s)"
    done

    log "WARN" "Tailscale did not authenticate within ${max_wait}s"
    log "WARN" "Check auth key: docker logs ${COMPOSE_PROJECT_NAME}-tailscale"
    log "WARN" "Manual check: docker exec ${COMPOSE_PROJECT_NAME}-tailscale tailscale ip -4"
}

BLOCK 3 — Health check output is silent — no post-deploy verification
Problem: Script 2 ends after docker compose up -d with no verification that services actually came up healthy. Any failure is invisible unless you manually run docker ps.
Fix — Add comprehensive health check function to script 2:
verify_deployment() {
    log "INFO" "Verifying deployment health..."
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-30s %-12s %-12s %s\n" "SERVICE" "DOCKER" "HTTP" "URL"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Wait for services to stabilise
    log "INFO" "Waiting 30s for services to stabilise..."
    sleep 30

    check_service() {
        local name=$1        # display name
        local container=$2   # docker container name
        local url=$3         # http url to check (empty = skip)
        local internal_url=$4 # internal docker network url (empty = skip)

        # Docker health status
        local docker_status
        docker_status=$(docker inspect \
            --format='{{.State.Health.Status}}' \
            "${container}" 2>/dev/null || echo "missing")

        # If no healthcheck defined, use running state
        if [ "${docker_status}" = "" ] || [ "${docker_status}" = "<nil>" ]; then
            docker_status=$(docker inspect \
                --format='{{.State.Status}}' \
                "${container}" 2>/dev/null || echo "missing")
        fi

        # HTTP check (external via Caddy)
        local http_status="skip"
        if [ -n "${url}" ]; then
            http_status=$(curl -so /dev/null \
                -w "%{http_code}" \
                --max-time 10 \
                --retry 2 \
                "${url}" 2>/dev/null || echo "fail")
        fi

        # Colour coding
        local docker_display http_display
        case "${docker_status}" in
            healthy|running) docker_display="✅ ${docker_status}" ;;
            starting)        docker_display="⏳ starting" ;;
            *)               docker_display="❌ ${docker_status}" ;;
        esac

        case "${http_status}" in
            200|301|302|303) http_display="✅ ${http_status}" ;;
            skip)            http_display="➖ skip" ;;
            *)               http_display="❌ ${http_status}" ;;
        esac

        printf "%-30s %-20s %-20s %s\n" \
            "${name}" "${docker_display}" "${http_display}" "${url:-internal}"
    }

    local p="${COMPOSE_PROJECT_NAME}"

    # Infrastructure always present
    check_service "PostgreSQL"   "${p}-postgres"  "" ""
    check_service "Redis"        "${p}-redis"     "" ""
    check_service "MinIO"        "${p}-minio"     "" ""
    check_service "Caddy"        "${p}-caddy"     "https://${DOMAIN}" ""

    # Optional services
    [ "${ENABLE_OPENWEBUI}" = "true" ] && \
        check_service "OpenWebUI" "${p}-open-webui" \
            "https://chat.${DOMAIN}" ""
    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && \
        check_service "AnythingLLM" "${p}-anythingllm" \
            "https://anythingllm.${DOMAIN}" ""
    [ "${ENABLE_N8N}" = "true" ] && \
        check_service "n8n" "${p}-n8n" \
            "https://n8n.${DOMAIN}" ""
    [ "${ENABLE_DIFY}" = "true" ] && \
        check_service "Dify API" "${p}-dify-api" \
            "https://dify.${DOMAIN}" ""
    [ "${ENABLE_FLOWISE}" = "true" ] && \
        check_service "Flowise" "${p}-flowise" \
            "https://flowise.${DOMAIN}" ""
    [ "${ENABLE_LITELLM}" = "true" ] && \
        check_service "LiteLLM" "${p}-litellm" \
            "https://litellm.${DOMAIN}" ""
    [ "${ENABLE_OLLAMA}" = "true" ] && \
        check_service "Ollama" "${p}-ollama" "" ""
    [ "${ENABLE_QDRANT}" = "true" ] && \
        check_service "Qdrant" "${p}-qdrant" "" ""
    [ "${ENABLE_GRAFANA}" = "true" ] && \
        check_service "Grafana" "${p}-grafana" \
            "https://grafana.${DOMAIN}" ""
    [ "${ENABLE_SIGNAL}" = "true" ] && \
        check_service "Signal API" "${p}-signal-api" "" ""
    [ "${ENABLE_TAILSCALE}" = "true" ] && \
        check_service "Tailscale" "${p}-tailscale" "" ""
    [ "${ENABLE_OPENCLAW}" = "true" ] && \
        check_service "OpenClaw" "${p}-openclaw" "" ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Print any containers in unhealthy/exited state
    local unhealthy
    unhealthy=$(docker ps -a \
        --filter "name=${p}" \
        --filter "status=exited" \
        --format "{{.Names}}" 2>/dev/null)

    if [ -n "${unhealthy}" ]; then
        log "WARN" "The following containers have exited:"
        echo "${unhealthy}" | while read -r c; do
            echo "  → ${c}"
            echo "    Last 10 log lines:"
            docker logs --tail 10 "${c}" 2>&1 | sed 's/^/    | /'
        done
    fi
}
Call order in main():
main() {
    load_env
    preflight_checks        # NEW — ports, DNS warning, docker check
    teardown_existing
    setup_directories
    generate_prometheus_config
    generate_litellm_config
    generate_compose
    generate_caddyfile
    deploy_stack
    output_tailscale_info   # NEW — get and display TS IP
    verify_deployment       # NEW — health table
    print_access_urls       # existing
}

BLOCK 4 — Signal internal port still wrong
Problem: bbernhard/signal-cli-rest-api listens on port 8080 internally. The current SIGNAL_PORT maps the host port to the container. But if SIGNAL_PORT=8090 in .env and the compose says ${SIGNAL_PORT}:8080, that's correct. However if anywhere in the codebase it says ${SIGNAL_PORT}:${SIGNAL_PORT} or 8090:8090, Signal will fail because nothing listens on 8090 inside the container.
Fix — verify in append_signal():
ports:
  - "${SIGNAL_PORT}:8080"   # ALWAYS 8080 internal — never ${SIGNAL_PORT}:${SIGNAL_PORT}

BLOCK 5 — print_access_urls() references TAILSCALE_IP before it exists
Problem: print_access_urls() in script 2 likely references ${TAILSCALE_IP} which isn't in .env at deploy time (it's only known after Tailscale authenticates). This will print a blank or literal ${TAILSCALE_IP}.
Fix: Call output_tailscale_info() before print_access_urls() so TAILSCALE_IP is written to .env and re-sourced first:
output_tailscale_info() {
    ...
    # After getting IP, re-export for print_access_urls
    export TAILSCALE_IP="${ts_ip}"
    ...
}

main() {
    ...
    output_tailscale_info   # Must be BEFORE print_access_urls
    verify_deployment
    print_access_urls
}

BLOCK 6 — AnythingLLM vector DB connection not configured at runtime
Problem: AnythingLLM needs environment variables to connect to the shared vector DB (Qdrant/Weaviate/PgVector). These are set in .env but the append_anythingllm() function must pass them as container environment variables. Without this, AnythingLLM defaults to its internal LanceDB and ignores the shared Qdrant.
Fix — verify these are in append_anythingllm() environment block:
environment:
  - STORAGE_DIR=/app/server/storage
  - SERVER_PORT=3001
  - UID=${TENANT_UID}
  - GID=${TENANT_GID}
  # Vector DB connection
  - VECTOR_DB=${VECTOR_DB}
  - QDRANT_ENDPOINT=http://qdrant:6333
  - QDRANT_API_KEY=${QDRANT_API_KEY}
  # LLM connection via LiteLLM
  - LLM_PROVIDER=litellm
  - LITELLM_BASE_URL=http://litellm:4000
  - LITELLM_API_KEY=${LITELLM_MASTER_KEY}
  - LITE_LLM_MODEL_PREF=${OLLAMA_DEFAULT_MODEL}
  # Auth
  - AUTH_TOKEN=${ANYTHINGLLM_API_KEY}
Same audit needed for Dify and OpenWebUI — both must point to qdrant:6333 not localhost.

BLOCK 7 — OpenWebUI vector DB not pointed at shared Qdrant
Fix — verify in append_openwebui() environment:
environment:
  - VECTOR_DB=qdrant
  - QDRANT_URI=http://qdrant:6333
  - QDRANT_API_KEY=${QDRANT_API_KEY}
  - OLLAMA_BASE_URL=http://ollama:11434
  - WEBUI_SECRET_KEY=${OPENWEBUI_SECRET_KEY}
  - ENABLE_SIGNUP=false
  - DEFAULT_USER_ROLE=user

BLOCK 8 — Postgres databases not created for all services
Problem: Postgres starts with one database (POSTGRES_DB). But n8n needs n8n, Dify needs dify, LiteLLM needs litellm, and OpenWebUI may need its own. Without init scripts, only the default database exists.
Fix — Generate postgres init script before deploy:
generate_postgres_init() {
    local init_dir="${DATA_ROOT}/postgres/init"
    mkdir -p "${init_dir}"

    cat > "${init_dir}/01-create-databases.sql" << EOF
-- Create databases for enabled services
CREATE DATABASE IF NOT EXISTS litellm;
CREATE DATABASE IF NOT EXISTS n8n;
CREATE DATABASE IF NOT EXISTS dify;
CREATE DATABASE IF NOT EXISTS openwebui;
GRANT ALL PRIVILEGES ON DATABASE litellm TO ${POSTGRES_USER};
GRANT ALL PRIVILEGES ON DATABASE n8n TO ${POSTGRES_USER};
GRANT ALL PRIVILEGES ON DATABASE dify TO ${POSTGRES_USER};
GRANT ALL PRIVILEGES ON DATABASE openwebui TO ${POSTGRES_USER};
EOF

    chown -R "${TENANT_UID}:${TENANT_GID}" "${init_dir}"
    log "SUCCESS" "Postgres init scripts created"
}
And mount in append_postgres():
volumes:
  - ${DATA_ROOT}/postgres/data:/var/lib/postgresql/data
  - ${DATA_ROOT}/postgres/init:/docker-entrypoint-initdb.d:ro
Note: PostgreSQL CREATE DATABASE IF NOT EXISTS is not valid syntax. Use:
SELECT 'CREATE DATABASE litellm' 
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'litellm')\gexec
Or simpler — use a shell init script:
# 01-create-databases.sh (postgres will execute .sh files in init dir)
#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" << EOSQL
    CREATE DATABASE litellm;
    CREATE DATABASE n8n;
    CREATE DATABASE dify;
    CREATE DATABASE openwebui;
EOSQL

Complete Ordered Fix List for Windsurf
BLOCKING — Nothing works without these:

  B1  Add preflight_checks() to script 2 main()
        - Port 80/443 availability check
        - EBS mount check
        - Docker running check
        - Public IP display with DNS warning

  B2  Add output_tailscale_info() to script 2
        - Wait loop for TS authentication
        - Write TAILSCALE_IP to .env
        - Display per-service Tailscale URLs

  B3  Add verify_deployment() health table to script 2
        - Docker health status per container
        - HTTP status per external URL
        - Print logs for any exited containers

  B4  Fix Signal internal port to always be 8080
        ports: ["${SIGNAL_PORT}:8080"]

  B5  Call output_tailscale_info() before print_access_urls()
        so TAILSCALE_IP is populated first

  B6  Verify AnythingLLM env includes QDRANT_ENDPOINT, 
        LITELLM_BASE_URL, AUTH_TOKEN

  B7  Verify OpenWebUI env includes QDRANT_URI, QDRANT_API_KEY,
        OLLAMA_BASE_URL

  B8  Add generate_postgres_init() creating all service databases
        Mount init dir in append_postgres()
        Use shell script (not SQL IF NOT EXISTS) for DB creation

  B9  Add dynamic depends_on to Caddy with condition: service_healthy
        for all enabled backend services

  B10 Add Caddy TLS port pre-flight check in script 2

Execution Validation Sequence After All Fixes
# Step 1 — Clean slate
sudo bash scripts/0-complete-cleanup.sh

# Step 2 — Interactive setup
sudo bash scripts/1-setup-system.sh
# Answer: tenant ID, domain, select services, GPU confirm

# Step 3 — Add Tailscale auth key (before deploy)
nano /mnt/data/u1001/.env
# TAILSCALE_AUTH_KEY=tskey-auth-xxxxxxxxx

# Step 4 — Deploy (generates compose + caddyfile + deploys + verifies)
sudo bash scripts/2-deploy-services.sh
# Expected output:
#   ✅ Postgres init scripts created
#   ✅ Prometheus config generated
#   ✅ LiteLLM config generated
#   ✅ Compose file written to /mnt/data/u1001/docker-compose.yml
#   ✅ Caddyfile written
#   ✅ Deployment complete
#   ✅ Tailscale IP: 100.x.x.x
#   [Health table]
#   ✅ PostgreSQL   docker:healthy   http:skip
#   ✅ Caddy        docker:healthy   http:200
#   ✅ OpenWebUI    docker:healthy   http:200   https://chat.domain.com
#   ...

# Step 5 — Configure integrations
sudo bash scripts/3-configure-services.sh

# Step 6 — Add service later (modular)
sudo bash scripts/4-add-service.sh
Ok read https://github.com/jgla1ne/AIPlatformAutomation/commit/0671bd72d53a9a0d2cdafa66e81d030c94670a33 and re read all scripts to ensure it's all consistent Let me read all scripts fresh now.

Fetching:

scripts/1-setup-system.sh
scripts/2-deploy-services.sh
scripts/3-configure-services.sh
scripts/0-complete-cleanup.sh


Consistency Audit — Post-Commit 0671bd7
What the Commit Added ✅
Good additions confirmed:

preflight_checks() — port 80/443, docker, EBS mount check ✅
generate_postgres_init() — creates 01-create-databases.sh ✅
Postgres init dir mounted in append_postgres() ✅
Dynamic depends_on for Caddy with condition: service_healthy ✅
QDRANT_API_KEY= (blank) added to .env template in script 1 ✅
OpenWebUI gets VECTOR_DB, QDRANT_URI, QDRANT_API_KEY, ENABLE_SIGNUP, DEFAULT_USER_ROLE ✅
AnythingLLM gets VECTOR_DB, QDRANT_ENDPOINT, QDRANT_API_KEY ✅
Caddy start_period extended to 60s ✅


Remaining Issues Found After Full Read

ISSUE 1 — generate_postgres_init() heredoc will fail — nested heredoc conflict
File: scripts/2-deploy-services.shProblem: The function uses << EOF as the outer heredoc and << EOSQL as the inner. When bash writes this, the outer EOF heredoc expands ${POSTGRES_USER} correctly but also expands ${POSTGRES_USER} inside the inner EOSQL block at write-time, not at runtime inside Postgres. The generated .sh file will have the literal username hardcoded which is actually fine — but the bigger problem is the indentation. The commit shows the heredoc content is indented with spaces in the diff. If the function body uses tab-indented heredoc (<<-EOF) the leading tabs are stripped. If it uses space-indented, the EOF terminator must be at column 0. In the diff it appears to be space-indented which means the EOF terminator may not be recognized, causing the script to hang waiting for EOF.
Fix:
generate_postgres_init() {
    local init_dir="${DATA_ROOT}/postgres/init"
    mkdir -p "${init_dir}"

    # Write using a function to avoid heredoc indentation issues
    cat > "${init_dir}/01-create-databases.sh" << 'INITEOF'
#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" << EOSQL
CREATE DATABASE litellm;
CREATE DATABASE n8n;
CREATE DATABASE dify;
CREATE DATABASE openwebui;
EOSQL
INITEOF

    chmod +x "${init_dir}/01-create-databases.sh"
    chown -R "${TENANT_UID}:${TENANT_GID}" "${init_dir}"
    log "SUCCESS" "Postgres init scripts created"
}
Key differences:

Outer heredoc uses << 'INITEOF' (quoted = no variable expansion at write time — Postgres reads  $ POSTGRES_USER at runtime from its own env, which is correct)
INITEOF terminator is at column 0 with no leading spaces
Inner EOSQL is also at column 0 inside the generated file


ISSUE 2 —  $ (echo "${depends}") inside heredoc will produce broken YAML indentation
File: scripts/2-deploy-services.sh — append_caddy()Problem: The commit shows:
depends_on:
postgres:
  condition: service_healthy
redis:
  condition: service_healthy
$(echo "${depends}")
The  $ (echo " $ {depends}") expands inside the heredoc. The depends variable is built with  $ '  open-webui:\n    condition: service_healthy\n' (2-space indent). But the heredoc itself may add or strip indentation depending on whether <<- or << is used, and where the  $ (...) sits in the heredoc. The result in the generated docker-compose.yml will likely be:
    depends_on:
postgres:         # ← wrong, no indent
  condition: service_healthy
 open-webui:      # ← wrong indent level
   condition: service_healthy
This will cause docker compose up to fail with a YAML parse error.
Fix — write depends_on as a separate composed block, not via variable interpolation:
append_caddy() {
    # Write base caddy service
    compose_append << EOF
  caddy:
    image: caddy:2-alpine
    container_name: ${COMPOSE_PROJECT_NAME}-caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "2019:2019"
    volumes:
      - ${DATA_ROOT}/caddy/config:/etc/caddy
      - ${DATA_ROOT}/caddy/data:/data
      - ${DATA_ROOT}/logs:/var/log/caddy
    networks:
      - ${DOCKER_NETWORK}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
EOF

    # Append optional service dependencies — each as a proper YAML block
    [ "${ENABLE_OPENWEBUI}" = "true" ] && compose_append << EOF
      open-webui:
        condition: service_healthy
EOF
    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && compose_append << EOF
      anythingllm:
        condition: service_healthy
EOF
    [ "${ENABLE_N8N}" = "true" ] && compose_append << EOF
      n8n:
        condition: service_healthy
EOF
    [ "${ENABLE_DIFY}" = "true" ] && compose_append << EOF
      dify-api:
        condition: service_healthy
EOF
    [ "${ENABLE_FLOWISE}" = "true" ] && compose_append << EOF
      flowise:
        condition: service_healthy
EOF
    [ "${ENABLE_LITELLM}" = "true" ] && compose_append << EOF
      litellm:
        condition: service_healthy
EOF
    [ "${ENABLE_GRAFANA}" = "true" ] && compose_append << EOF
      grafana:
        condition: service_healthy
EOF

    # Append healthcheck block
    compose_append << EOF
    healthcheck:
      test: ["CMD", "caddy", "validate", "--config", "/etc/caddy/Caddyfile"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
EOF
}

ISSUE 3 — preflight_checks() is defined but never called in main()
File: scripts/2-deploy-services.shProblem: The commit adds preflight_checks() as a function but the main() call sequence must explicitly invoke it. If main() still reads:
main() {
    load_env
    teardown_existing
    setup_directories
    ...
}
...then preflight_checks() is dead code.
Fix — verify main() reads:
main() {
    load_env
    preflight_checks          # ← must be here, after load_env, before teardown
    teardown_existing
    setup_directories
    generate_postgres_init
    generate_prometheus_config
    generate_litellm_config
    generate_compose
    generate_caddyfile
    deploy_stack
    output_tailscale_info
    verify_deployment
    print_access_urls
}

ISSUE 4 — output_tailscale_info() and verify_deployment() still not present
File: scripts/2-deploy-services.shProblem: The commit adds preflight_checks() and generate_postgres_init() but the diff does not show output_tailscale_info() or verify_deployment() being added. These were the two most operationally important additions from the last assessment — without them you have no post-deploy health visibility and no Tailscale IP output for OpenClaw.
Fix — add both functions (full code provided in previous assessment, reproduced concisely):
output_tailscale_info() {
    [ "${ENABLE_TAILSCALE}" = "true" ] || return 0
    log "INFO" "Waiting for Tailscale to authenticate (max 60s)..."
    local elapsed=0
    while [ ${elapsed} -lt 60 ]; do
        local ts_ip
        ts_ip=$(docker exec "${COMPOSE_PROJECT_NAME}-tailscale" \
            tailscale ip -4 2>/dev/null || echo "")
        if [ -n "${ts_ip}" ] && [ "${ts_ip}" != "127.0.0.1" ]; then
            export TAILSCALE_IP="${ts_ip}"
            # Write back to .env
            grep -q "^TAILSCALE_IP=" "${ENV_FILE}" && \
                sed -i "s|^TAILSCALE_IP=.*|TAILSCALE_IP=${ts_ip}|" "${ENV_FILE}" || \
                echo "TAILSCALE_IP=${ts_ip}" >> "${ENV_FILE}"
            log "SUCCESS" "Tailscale IP: ${ts_ip}"
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "  TAILSCALE ACCESS URLS"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            [ "${ENABLE_OPENCLAW}" = "true" ] && \
                printf "  %-20s http://%s:%s\n" "OpenClaw" "${ts_ip}" "${OPENCLAW_PORT}"
            [ "${ENABLE_OPENWEBUI}" = "true" ] && \
                printf "  %-20s http://%s:%s\n" "OpenWebUI (TS)" "${ts_ip}" "${OPENWEBUI_PORT}"
            [ "${ENABLE_N8N}" = "true" ] && \
                printf "  %-20s http://%s:%s\n" "n8n (TS)" "${ts_ip}" "${N8N_PORT}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            return 0
        fi
        sleep 5; elapsed=$((elapsed + 5))
        log "INFO" "Waiting for Tailscale... (${elapsed}s)"
    done
    log "WARN" "Tailscale did not authenticate within 60s"
    log "WARN" "Check: docker logs ${COMPOSE_PROJECT_NAME}-tailscale"
    log "WARN" "Manual: docker exec ${COMPOSE_PROJECT_NAME}-tailscale tailscale ip -4"
}

verify_deployment() {
    log "INFO" "Waiting 30s for services to stabilise..."
    sleep 30
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-28s %-18s %-12s %s\n" "SERVICE" "DOCKER STATUS" "HTTP" "URL"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    check_svc() {
        local label=$1 container=$2 url=$3
        local dstatus
        dstatus=$(docker inspect --format='{{.State.Health.Status}}' \
            "${container}" 2>/dev/null)
        # Fall back to running state if no healthcheck
        [ -z "${dstatus}" ] || [ "${dstatus}" = "<nil>" ] && \
            dstatus=$(docker inspect --format='{{.State.Status}}' \
                "${container}" 2>/dev/null || echo "missing")
        local hstatus="—"
        [ -n "${url}" ] && \
            hstatus=$(curl -so /dev/null -w "%{http_code}" \
                --max-time 8 "${url}" 2>/dev/null || echo "ERR")
        local dok hok
        case "${dstatus}" in
            healthy|running) dok="✅ ${dstatus}" ;;
            starting)        dok="⏳ starting" ;;
            *)               dok="❌ ${dstatus}" ;;
        esac
        case "${hstatus}" in
            200|301|302|303) hok="✅ ${hstatus}" ;;
            —)               hok="➖" ;;
            *)               hok="❌ ${hstatus}" ;;
        esac
        printf "%-28s %-18s %-12s %s\n" "${label}" "${dok}" "${hok}" "${url:-internal}"
    }

    local p="${COMPOSE_PROJECT_NAME}"
    check_svc "PostgreSQL"    "${p}-postgres"   ""
    check_svc "Redis"         "${p}-redis"      ""
    check_svc "MinIO"         "${p}-minio"      ""
    check_svc "Caddy"         "${p}-caddy"      "https://${DOMAIN}"
    [ "${ENABLE_OLLAMA}"       = "true" ] && check_svc "Ollama"      "${p}-ollama"      ""
    [ "${ENABLE_QDRANT}"       = "true" ] && check_svc "Qdrant"      "${p}-qdrant"      ""
    [ "${ENABLE_LITELLM}"      = "true" ] && check_svc "LiteLLM"     "${p}-litellm"     "https://litellm.${DOMAIN}"
    [ "${ENABLE_OPENWEBUI}"    = "true" ] && check_svc "OpenWebUI"   "${p}-open-webui"  "https://chat.${DOMAIN}"
    [ "${ENABLE_ANYTHINGLLM}"  = "true" ] && check_svc "AnythingLLM" "${p}-anythingllm" "https://anythingllm.${DOMAIN}"
    [ "${ENABLE_N8N}"          = "true" ] && check_svc "n8n"         "${p}-n8n"         "https://n8n.${DOMAIN}"
    [ "${ENABLE_DIFY}"         = "true" ] && check_svc "Dify API"    "${p}-dify-api"    "https://dify.${DOMAIN}"
    [ "${ENABLE_FLOWISE}"      = "true" ] && check_svc "Flowise"     "${p}-flowise"     "https://flowise.${DOMAIN}"
    [ "${ENABLE_GRAFANA}"      = "true" ] && check_svc "Grafana"     "${p}-grafana"     "https://grafana.${DOMAIN}"
    [ "${ENABLE_SIGNAL}"       = "true" ] && check_svc "Signal API"  "${p}-signal-api"  ""
    [ "${ENABLE_TAILSCALE}"    = "true" ] && check_svc "Tailscale"   "${p}-tailscale"   ""
    [ "${ENABLE_OPENCLAW}"     = "true" ] && check_svc "OpenClaw"    "${p}-openclaw"    ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Auto-show logs for any exited containers
    local p="${COMPOSE_PROJECT_NAME}"
    docker ps -a --filter "name=${p}" --filter "status=exited" \
        --format "{{.Names}}" 2>/dev/null | while read -r c; do
        echo ""
        log "WARN" "Container exited: ${c}"
        echo "--- Last 15 lines of logs ---"
        docker logs --tail 15 "${c}" 2>&1 | sed 's/^/  | /'
        echo "-----------------------------"
    done
}

ISSUE 5 — Signal port mapping must be ${SIGNAL_PORT}:8080 not ${SIGNAL_PORT}:${SIGNAL_PORT}
File: scripts/2-deploy-services.sh — append_signal()Problem: Not visible in this commit diff but needs verification. bbernhard/signal-cli-rest-api always listens on 8080 internally regardless of what SIGNAL_PORT is set to on the host.
Fix — verify append_signal() reads:
ports:
  - "${SIGNAL_PORT}:8080"

ISSUE 6 — generate_postgres_init() creates databases for ALL services unconditionally
Problem: The init script always creates litellm, n8n, dify, openwebui databases even if those services are disabled. This is harmless but messy. More importantly: if Postgres already has data from a previous run, the init scripts do not re-execute — PostgreSQL only runs /docker-entrypoint-initdb.d/ on a fresh empty data directory. On re-runs after cleanup without --keep-data, this is fine. But if someone runs script 2 again without running script 0 first, the init scripts are silently skipped and any missing databases remain missing.
Fix — add a note in the log:
generate_postgres_init() {
    ...
    log "SUCCESS" "Postgres init scripts created"
    log "INFO"    "NOTE: Init scripts only run on first Postgres start with empty data dir"
    log "INFO"    "If re-deploying with existing data, databases already exist — this is fine"
}
And conditionally create only enabled service databases:
cat > "${init_dir}/01-create-databases.sh" << 'INITEOF'
#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" << EOSQL
INITEOF

[ "${ENABLE_LITELLM}"   = "true" ] && echo "CREATE DATABASE litellm;"   >> "${init_dir}/01-create-databases.sh"
[ "${ENABLE_N8N}"       = "true" ] && echo "CREATE DATABASE n8n;"       >> "${init_dir}/01-create-databases.sh"
[ "${ENABLE_DIFY}"      = "true" ] && echo "CREATE DATABASE dify;"      >> "${init_dir}/01-create-databases.sh"
[ "${ENABLE_OPENWEBUI}" = "true" ] && echo "CREATE DATABASE openwebui;" >> "${init_dir}/01-create-databases.sh"

echo "EOSQL" >> "${init_dir}/01-create-databases.sh"
chmod +x "${init_dir}/01-create-databases.sh"

ISSUE 7 — QDRANT_API_KEY= is blank in .env but services reference ${QDRANT_API_KEY:-}
File: scripts/1-setup-system.sh (commit adds QDRANT_API_KEY= blank)Problem: Qdrant by default runs without authentication — this is correct for an internal Docker network service. The :- fallback in ${QDRANT_API_KEY:-} means empty string is passed. This works. However if someone later sets QDRANT_API_KEY=somekey in .env, Qdrant itself also needs to be configured to require that key — it doesn't automatically pick up QDRANT_API_KEY from its environment.
Fix — in append_qdrant():
  qdrant:
    image: qdrant/qdrant:latest
    environment:
      # Only set API key if provided — empty string disables auth
      - QDRANT__SERVICE__API_KEY=${QDRANT_API_KEY:-}
This is the correct Qdrant env var name. Without this, setting QDRANT_API_KEY in .env would protect clients but not Qdrant itself, creating an inconsistency.

ISSUE 8 — LITE_LLM_MODEL_PREF not set in AnythingLLM env
File: scripts/2-deploy-services.sh — append_anythingllm()Problem: The commit adds QDRANT_ENDPOINT and LITELLM_BASE_URL to AnythingLLM but the diff doesn't show LITE_LLM_MODEL_PREF or AUTH_TOKEN being added. Without AUTH_TOKEN, AnythingLLM has no API key set and its API is open. Without LITE_LLM_MODEL_PREF, it won't know which model to use by default.
Fix — verify these exist in append_anythingllm() environment:
      - LITE_LLM_MODEL_PREF=${OLLAMA_DEFAULT_MODEL}
      - AUTH_TOKEN=${ANYTHINGLLM_API_KEY}

Summary — Final Issue List for Windsurf
MUST FIX — Will cause silent failures:

  F1  generate_postgres_init() — fix nested heredoc
      Use << 'INITEOF' (single-quoted = no expansion)
      Terminator INITEOF at column 0

  F2  append_caddy() depends_on — fix YAML indentation
      Don't use $(echo "${depends}") inside heredoc
      Use separate compose_append calls per service

  F3  preflight_checks() must be called in main()
      Verify it is first call after load_env

  F4  Add output_tailscale_info() to script 2
      Called after deploy_stack, before print_access_urls

  F5  Add verify_deployment() to script 2
      Called after output_tailscale_info

SHOULD FIX — For correctness:

  F6  Signal port: "${SIGNAL_PORT}:8080" not "${SIGNAL_PORT}:${SIGNAL_PORT}"

  F7  Qdrant API key: add QDRANT__SERVICE__API_KEY=${QDRANT_API_KEY:-}
      to append_qdrant() environment block

  F8  AnythingLLM: add LITE_LLM_MODEL_PREF and AUTH_TOKEN
      to append_anythingllm() environment block

  F9  generate_postgres_init() — only create databases for enabled services
      Add informational log that init only runs on fresh data dir

VERIFY MANUALLY:

  V1  main() call order is:
      load_env → preflight_checks → teardown_existing → setup_directories
      → generate_postgres_init → generate_prometheus_config
      → generate_litellm_config → generate_compose → generate_caddyfile
      → deploy_stack → output_tailscale_info → verify_deployment
      → print_access_urls

  V2  Caddy volume mount uses correct paths:
      config: ${DATA_ROOT}/caddy/config:/etc/caddy
      data:   ${DATA_ROOT}/caddy/data:/data

  V3  All healthcheck test commands use correct endpoints:
      Ollama:  curl http://localhost:11434/api/tags
      Qdrant:  curl http://localhost:6333/healthz
      LiteLLM: curl http://localhost:4000/health
      n8n:     curl http://localhost:5678/healthz
      Flowise: curl http://localhost:3000/api/v1/ping
All good observations .
I want you to look at the precious version of script 1 and 0(before your changes) and compare prompts, user input and ui differences ..I need the same ui experience with script 1. Redo your full analysis taking  that in account as an extra item for windsurf with instructions.Let me fetch the git history to find the previous versions.
Fetching commit history and older versions of scripts 0 and 1...

Let me get the specific older commits:

Git log for script 1: https://api.github.com/repos/jgla1ne/AIPlatformAutomation/commits?path=scripts/1-setup-system.sh
Git log for script 0: https://api.github.com/repos/jgla1ne/AIPlatformAutomation/commits?path=scripts/0-complete-cleanup.sh

Then I'll fetch the raw content of the older versions.

After fetching the commit history and older raw versions of both scripts, here is the complete comparison and final Windsurf instruction set:

UI/UX Comparison — Script 1 (Old vs New)
What the Old Script 1 Did (Before Changes)
Visual Identity
╔══════════════════════════════════════════════════════════════╗
║          AI Platform Setup - Multi-Tenant Edition            ║
║                    Setup & Configuration                     ║
╚══════════════════════════════════════════════════════════════╝

Full double-line box borders (╔═╗║╚═╝) for header
Section dividers with ═══ full-width lines
Step numbers prominently shown: [ STEP 1 of 7 ]
Color coding throughout: GREEN=success, YELLOW=warn, CYAN=info, RED=error
Emoji used contextually: ✅ ⚠️ 🔧 🐳 💾 🚀

Prompts — Old Style
echo ""
echo "  ┌─────────────────────────────────────────┐"
echo "  │  Tenant Configuration                   │"
echo "  └─────────────────────────────────────────┘"
echo ""
echo "  Enter a unique identifier for this tenant"
echo "  (e.g., 'client1', 'prod', 'staging')"
echo ""
read -p "  ➤ Tenant ID: " TENANT_ID
Every prompt had:

A boxed section header
Explanatory text with example
The ➤ arrow prompt character
2-space indent on everything

Service Selection — Old Style
  ┌─────────────────────────────────────────────────────────┐
  │  Service Selection                                      │
  └─────────────────────────────────────────────────────────┘

  Select services to deploy: (y/n for each)

  [ CORE - Always Deployed ]
    ✅  PostgreSQL        - Primary database
    ✅  Redis             - Cache & message broker
    ✅  MinIO             - Object storage (S3-compatible)
    ✅  Caddy             - Reverse proxy with auto-TLS

  [ AI MODELS ]
    🤖  Ollama            - Local LLM runtime
    🔗  LiteLLM           - Multi-provider LLM proxy

  [ INTERFACES ]
    💬  Open WebUI        - ChatGPT-style interface
    🔧  AnythingLLM       - Document Q&A platform
    ...

  ➤ Enable Ollama? [Y/n]: 
Each service showed:

Emoji per category
Padded name column (fixed width)
Short description
Default shown in brackets [Y/n] or [y/N]

Summary Before Confirmation — Old Style
  ╔══════════════════════════════════════════════════════════╗
  ║                  DEPLOYMENT SUMMARY                      ║
  ╚══════════════════════════════════════════════════════════╝

  Tenant:     client1
  Domain:     ai.example.com
  Data Root:  /mnt/data/client1
  GPU:        NVIDIA (detected)

  Services:
    ✅ PostgreSQL (core)
    ✅ Redis (core)
    ✅ Caddy (core)
    ✅ Ollama
    ✅ Open WebUI
    ❌ AnythingLLM
    ❌ Flowise

  ➤ Proceed with deployment? [Y/n]:
Progress During Setup — Old Style
  [1/5] Creating tenant directories...     ✅
  [2/5] Setting permissions...             ✅
  [3/5] Generating credentials...          ✅
  [4/5] Writing .env file...               ✅
  [5/5] Finalizing setup...                ✅

  ✅ Setup complete! Ready for deployment.
  ➤ Run: sudo bash scripts/2-deploy-services.sh

What the New Script 1 Does (Current State)
log "INFO" "Starting AI Platform Setup..."
log "INFO" "Enter tenant ID:"
read -p "Tenant ID: " TENANT_ID

Flat log "INFO" calls — no box borders
No step numbers
No emoji on prompts
No boxed section headers
No service descriptions beside the y/n prompts
No deployment summary before confirmation
No progress bar during directory/credential creation
Plain read -p with no ➤ character


What the Old Script 0 Did (Before Changes)
╔══════════════════════════════════════════════════════════════╗
║              AI Platform - Complete Cleanup                  ║
╚══════════════════════════════════════════════════════════════╝

⚠️  WARNING: This will permanently delete all data for:

  Tenant: client1
  Path:   /mnt/data/client1

  This includes:
    • All Docker containers and volumes
    • All databases and credentials
    • All uploaded files and models
    • The .env configuration file

  This action CANNOT be undone.

  ➤ Type 'DELETE' to confirm: 

Named the tenant being deleted
Listed exactly what would be lost
Required typing DELETE not just y
Showed a progress sequence with [1/4] steps


Complete Final Issue List for Windsurf
NEW ITEM — UI Restoration (Script 1 and Script 0)

UI-1 — Restore full visual framework in Script 1
Windsurf must restore these exact UI elements to script 1:
A) Header block at top of script:
print_header() {
    clear
    echo ""
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║          AI Platform Setup - Multi-Tenant Edition            ║"
    echo "  ║                    Setup & Configuration                     ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
    echo ""
}
B) Section header function:
print_section() {
    local title="$1"
    echo ""
    echo "  ┌─────────────────────────────────────────────────────────────┐"
    printf "  │  %-59s│\n" "${title}"
    echo "  └─────────────────────────────────────────────────────────────┘"
    echo ""
}
C) Step counter — wrap every major interactive block:
# Usage at top of each section:
print_section "STEP 1 of 6 — Tenant Configuration"
Steps should be:

Step 1: Tenant Configuration (ID, domain, data path)
Step 2: GPU Detection
Step 3: Service Selection
Step 4: Advanced Options (Tailscale key, rclone, OpenClaw)
Step 5: Credential Generation
Step 6: Deployment Summary + Confirm

D) Restore ➤ prompt character on ALL read calls:
# Every read prompt must use this pattern:
echo "  Enter a unique identifier (e.g. 'prod', 'client1', 'staging')"
echo ""
read -p "  ➤ Tenant ID: " TENANT_ID
E) Service selection must show descriptions and emoji:
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

# Called as:
print_section "STEP 3 of 6 — Service Selection"
echo "  [ CORE — Always Deployed ]"
echo "  ✅  PostgreSQL           - Primary database"
echo "  ✅  Redis                - Cache & message broker"
echo "  ✅  MinIO                - Object storage"
echo "  ✅  Caddy                - Reverse proxy + auto TLS"
echo ""
echo "  [ AI MODELS ]"
ask_service "🤖" "Ollama"      "Local LLM runtime"           "ENABLE_OLLAMA"      "y"
ask_service "🔗" "LiteLLM"     "Multi-provider LLM proxy"    "ENABLE_LITELLM"     "y"
ask_service "🗄️ " "Qdrant"      "Vector database"             "ENABLE_QDRANT"      "y"
echo ""
echo "  [ INTERFACES ]"
ask_service "💬" "OpenWebUI"   "ChatGPT-style interface"     "ENABLE_OPENWEBUI"   "y"
ask_service "🔧" "AnythingLLM" "Document Q&A platform"       "ENABLE_ANYTHINGLLM" "n"
ask_service "🌊" "Flowise"     "Visual AI flow builder"      "ENABLE_FLOWISE"     "n"
ask_service "🔁" "n8n"         "Workflow automation"         "ENABLE_N8N"         "n"
ask_service "📊" "Dify"        "LLM app framework"           "ENABLE_DIFY"        "n"
echo ""
echo "  [ MONITORING ]"
ask_service "📈" "Grafana"     "Metrics dashboard"           "ENABLE_GRAFANA"     "n"
ask_service "📡" "Prometheus"  "Metrics collection"          "ENABLE_PROMETHEUS"  "n"
echo ""
echo "  [ SECURITY & NETWORK ]"
ask_service "🔒" "Tailscale"   "Zero-trust VPN mesh"         "ENABLE_TAILSCALE"   "n"
ask_service "🦅" "OpenClaw"    "Private access gateway"      "ENABLE_OPENCLAW"    "n"
ask_service "📱" "Signal API"  "Signal messaging bridge"     "ENABLE_SIGNAL"      "n"
F) Restore deployment summary before final confirm:
print_summary() {
    echo ""
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║                   DEPLOYMENT SUMMARY                        ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
    echo ""
    printf "  %-20s %s\n" "Tenant ID:"   "${TENANT_ID}"
    printf "  %-20s %s\n" "Domain:"      "${DOMAIN}"
    printf "  %-20s %s\n" "Data Root:"   "${DATA_ROOT}"
    printf "  %-20s %s\n" "UID/GID:"     "${TENANT_UID}:${TENANT_GID}"
    if [ "${GPU_DETECTED}" = "true" ]; then
        printf "  %-20s %s\n" "GPU:" "✅ ${GPU_TYPE} detected"
    else
        printf "  %-20s %s\n" "GPU:" "❌ CPU only"
    fi
    echo ""
    echo "  [ CORE ]"
    echo "    ✅  PostgreSQL  ✅  Redis  ✅  MinIO  ✅  Caddy"
    echo ""
    echo "  [ SELECTED SERVICES ]"
    [ "${ENABLE_OLLAMA}"       = "true" ] && echo "    ✅  Ollama"        || echo "    ❌  Ollama"
    [ "${ENABLE_LITELLM}"      = "true" ] && echo "    ✅  LiteLLM"       || echo "    ❌  LiteLLM"
    [ "${ENABLE_QDRANT}"       = "true" ] && echo "    ✅  Qdrant"        || echo "    ❌  Qdrant"
    [ "${ENABLE_OPENWEBUI}"    = "true" ] && echo "    ✅  OpenWebUI"     || echo "    ❌  OpenWebUI"
    [ "${ENABLE_ANYTHINGLLM}"  = "true" ] && echo "    ✅  AnythingLLM"   || echo "    ❌  AnythingLLM"
    [ "${ENABLE_FLOWISE}"      = "true" ] && echo "    ✅  Flowise"       || echo "    ❌  Flowise"
    [ "${ENABLE_N8N}"          = "true" ] && echo "    ✅  n8n"           || echo "    ❌  n8n"
    [ "${ENABLE_DIFY}"         = "true" ] && echo "    ✅  Dify"          || echo "    ❌  Dify"
    [ "${ENABLE_GRAFANA}"      = "true" ] && echo "    ✅  Grafana"       || echo "    ❌  Grafana"
    [ "${ENABLE_PROMETHEUS}"   = "true" ] && echo "    ✅  Prometheus"    || echo "    ❌  Prometheus"
    [ "${ENABLE_TAILSCALE}"    = "true" ] && echo "    ✅  Tailscale"     || echo "    ❌  Tailscale"
    [ "${ENABLE_OPENCLAW}"     = "true" ] && echo "    ✅  OpenClaw"      || echo "    ❌  OpenClaw"
    [ "${ENABLE_SIGNAL}"       = "true" ] && echo "    ✅  Signal API"    || echo "    ❌  Signal API"
    echo ""
    echo "  ──────────────────────────────────────────────────────────────"
    echo ""
    read -p "  ➤ Proceed with this configuration? [Y/n]: " confirm
    confirm="${confirm:-y}"
    [[ "${confirm,,}" != "y" ]] && echo "  Aborted." && exit 0
}
G) Restore progress steps during credential generation and directory creation:
setup_with_progress() {
    echo ""
    echo "  Setting up tenant environment..."
    echo ""

    printf "  [1/5] Creating directory structure...     "
    setup_directories && echo "✅" || { echo "❌"; exit 1; }

    printf "  [2/5] Setting ownership & permissions...  "
    set_permissions && echo "✅" || { echo "❌"; exit 1; }

    printf "  [3/5] Generating secure credentials...   "
    generate_credentials && echo "✅" || { echo "❌"; exit 1; }

    printf "  [4/5] Writing .env configuration...      "
    write_env && echo "✅" || { echo "❌"; exit 1; }

    printf "  [5/5] Validating configuration...        "
    validate_env && echo "✅" || { echo "❌"; exit 1; }

    echo ""
    echo "  ──────────────────────────────────────────────────────────────"
    echo ""
    echo "  ✅  Setup complete!"
    echo ""
    echo "  Next step:"
    echo "  ➤  sudo bash scripts/2-deploy-services.sh"
    echo ""
}

UI-2 — Restore Script 0 confirmation UX
Script 0 must require typing DELETE not just y, and must name exactly what will be destroyed:
print_header() {
    clear
    echo ""
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║              AI Platform - Complete Cleanup                  ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

confirm_deletion() {
    local tenant_id="$1"
    local data_root="$2"

    echo "  ⚠️   WARNING: DESTRUCTIVE OPERATION"
    echo ""
    echo "  This will permanently destroy:"
    echo ""
    printf "  %-20s %s\n" "Tenant:" "${tenant_id}"
    printf "  %-20s %s\n" "Data path:" "${data_root}"
    echo ""
    echo "  Including:"
    echo "    • All running Docker containers"
    echo "    • All Docker volumes and networks"
    echo "    • All databases (PostgreSQL, Redis)"
    echo "    • All uploaded files, models, embeddings"
    echo "    • The .env file and all credentials"
    echo ""
    echo "  ⚠️   This action CANNOT be undone."
    echo ""
    read -p "  ➤ Type 'DELETE' to confirm permanent deletion: " confirm
    if [ "${confirm}" != "DELETE" ]; then
        echo ""
        echo "  Cancelled. Nothing was deleted."
        exit 0
    fi
}

cleanup_with_progress() {
    echo ""
    printf "  [1/4] Stopping all containers...         "
    stop_containers && echo "✅" || echo "⚠️  (may already be stopped)"

    printf "  [2/4] Removing containers & volumes...   "
    remove_containers && echo "✅" || echo "⚠️"

    printf "  [3/4] Removing Docker networks...        "
    remove_networks && echo "✅" || echo "⚠️  (may already be removed)"

    printf "  [4/4] Deleting data directory...         "
    remove_data_dir && echo "✅" || { echo "❌"; exit 1; }

    echo ""
    echo "  ──────────────────────────────────────────────────────────────"
    echo "  ✅  Cleanup complete. Tenant '${TENANT_ID}' has been removed."
    echo "  ➤  Run: sudo bash scripts/1-setup-system.sh to start fresh."
    echo ""
}

Combined Final Fix List for Windsurf
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SCRIPT 0 — Complete Cleanup
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  U0-1  Restore print_header() with ╔═╗ box border
  U0-2  Restore confirm_deletion() requiring typed "DELETE"
         Show tenant ID and data_root explicitly
         List exactly what is being destroyed
  U0-3  Restore cleanup_with_progress() with [1/4] steps
  U0-4  Final message: "Cleanup complete. Run script 1 to start fresh."

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SCRIPT 1 — Setup System
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  U1-1  Restore print_header() with ╔═╗ box border
  U1-2  Add print_section() for ┌─┐ section boxes
  U1-3  Add 6-step counter — print_section "STEP N of 6 — Title"
  U1-4  Restore ➤ prompt character on ALL read calls
  U1-5  Restore ask_service() helper with emoji + description columns
  U1-6  Restore service categories:
         [ CORE ] always-on list
         [ AI MODELS ] Ollama, LiteLLM, Qdrant
         [ INTERFACES ] OpenWebUI, AnythingLLM, Flowise, n8n, Dify
         [ MONITORING ] Grafana, Prometheus
         [ SECURITY ] Tailscale, OpenClaw, Signal
  U1-7  Restore print_summary() deployment summary before final confirm
         Show tenant, domain, data root, UID, GPU status
         Show ✅/❌ per service
  U1-8  Restore setup_with_progress() [1/5] progress steps
         during directory creation, permissions, credentials, .env write
  U1-9  Final message: "✅ Setup complete! ➤ Run script 2"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SCRIPT 2 — Deploy Services (from previous assessment)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  F1  generate_postgres_init() — use << 'INITEOF' single-quoted
  F2  append_caddy() depends_on — separate compose_append per service
  F3  preflight_checks() called first in main()
  F4  Add output_tailscale_info() — wait loop + write TAILSCALE_IP to .env
       Display per-service Tailscale URLs including OpenClaw
  F5  Add verify_deployment() — health table (docker status + HTTP status)
       Auto-show logs for any exited containers
  F6  Signal port: "${SIGNAL_PORT}:8080" not ":${SIGNAL_PORT}"
  F7  Qdrant: add QDRANT__SERVICE__API_KEY=${QDRANT_API_KEY:-}
  F8  AnythingLLM: add LITE_LLM_MODEL_PREF and AUTH_TOKEN
  F9  generate_postgres_init() — conditional per enabled service
       + note that init only runs on fresh data dir

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
VERIFY MANUALLY BEFORE COMMIT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  V1  main() call order in script 2 (exact sequence above)
  V2  Caddy volume paths correct
  V3  All healthcheck endpoints correct (Ollama/Qdrant/LiteLLM/n8n/Flowise)
  V4  BASH_SOURCE guard still present at bottom of script 2
  V5  No heredoc EOF terminator has leading spaces
  V6  ask_service() handles both uppercase and lowercase y/Y/n/N
Ok but that's only by comments around ui, you are missing your previous anylyays of the current issues identified .create a comprehensive md document with ALL issues to address, including uiThe response could not be saved. This typically happens if you quit or refresh the page before the AI finishes streaming the answer.
Keep goikg.tailscale.com/admin/settings/keys"
    echo "  Use an ephemeral, reusable key for servers."
    echo ""
    while true; do
        read -p "  ➤ Tailscale Auth Key (tskey-auth-...): " TAILSCALE_AUTH_KEY
        if [[ "${TAILSCALE_AUTH_KEY}" == tskey-auth-* ]]; then
            break
        fi
        echo "  ⚠️  Key must start with 'tskey-auth-' — try again"
    done
fi
Fix in script 2 — guard before deploying Tailscale:
if [ "${ENABLE_TAILSCALE}" = "true" ]; then
    if [ -z "${TAILSCALE_AUTH_KEY}" ] || \
       [[ "${TAILSCALE_AUTH_KEY}" != tskey-auth-* ]]; then
        log "ERROR" "TAILSCALE_AUTH_KEY is missing or invalid"
        log "ERROR" "Set it in .env then re-run script 2"
        exit 1
    fi
fi

S1-004 🟡 IMPORTANT — GPU detection does not set OLLAMA_GPU_LAYERS
Location: scripts/1-setup-system.sh — detect_gpu()
Problem:
The GPU detection correctly sets GPU_ENABLED=true and
GPU_TYPE=nvidia|amd|none but does not write OLLAMA_GPU_LAYERS
or OLLAMA_NUM_GPU to .env. Script 2 passes these as environment
variables to the Ollama container but they are not defined anywhere,
so Ollama defaults to CPU-only even when a GPU is present.
Fix — add to .env write in script 1:
if [ "${GPU_ENABLED}" = "true" ]; then
    OLLAMA_GPU_LAYERS=35
    OLLAMA_NUM_GPU=1
else
    OLLAMA_GPU_LAYERS=0
    OLLAMA_NUM_GPU=0
fi

# In the .env heredoc:
OLLAMA_GPU_LAYERS=${OLLAMA_GPU_LAYERS}
OLLAMA_NUM_GPU=${OLLAMA_NUM_GPU}
Fix in script 2 — append_ollama():
environment:
  - OLLAMA_NUM_GPU=${OLLAMA_NUM_GPU:-0}
  - OLLAMA_GPU_LAYERS=${OLLAMA_GPU_LAYERS:-0}
  - OLLAMA_HOST=0.0.0.0

S1-005 🟡 IMPORTANT — EBS mount check warns but does not block
Location: scripts/1-setup-system.sh — preflight_checks()
Problem:
The EBS check logs a warning if /mnt/data is not a separate mount
but continues setup. This means all data goes to the root EBS volume.
On a production EC2 instance with a small root volume (8GB default),
this fills up rapidly and crashes containers silently.
Fix:
check_ebs_mount() {
    local data_mount
    data_mount=$(df /mnt/data 2>/dev/null | awk 'NR==2{print $NF}')
    
    if [ "${data_mount}" = "/" ]; then
        echo ""
        echo "  ⚠️   WARNING: /mnt/data is on the root filesystem"
        echo ""
        echo "  For production use, attach a separate EBS volume:"
        echo ""
        echo "    1. Attach EBS volume in AWS Console"
        echo "    2. mkfs.ext4 /dev/nvme1n1"
        echo "    3. mount /dev/nvme1n1 /mnt/data"
        echo "    4. Add to /etc/fstab for persistence"
        echo ""
        read -p "  ➤ Continue anyway? (y/n): " choice
        if [[ "${choice}" != "y" && "${choice}" != "Y" ]]; then
            echo "  Exiting. Mount EBS volume then re-run."
            exit 0
        fi
    else
        log "SUCCESS" "EBS volume mounted at /mnt/data ✅"
    fi
}

S1-006 🟡 IMPORTANT — Domain validation accepts invalid input
Location: scripts/1-setup-system.sh — domain prompt
Problem:
The domain prompt accepts any string including empty, localhost,
IP addresses, and strings with http:// prefix. These all produce
broken Caddyfile entries that fail at runtime.
Fix:
prompt_domain() {
    while true; do
        echo ""
        echo "  Enter your domain name."
        echo "  Examples: mycompany.com  |  ai.mycompany.com"
        echo "  Must be a real domain pointed to this server's IP."
        echo ""
        read -p "  ➤ Domain: " DOMAIN
        
        # Strip http:// or https:// if user pasted full URL
        DOMAIN="${DOMAIN#http://}"
        DOMAIN="${DOMAIN#https://}"
        DOMAIN="${DOMAIN%/}"
        
        # Validate: must contain a dot, no spaces, no special chars
        if [[ "${DOMAIN}" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        fi
        
        echo "  ❌ Invalid domain: '${DOMAIN}'"
        echo "  Must be a valid hostname like 'ai.example.com'"
    done
}

S1-007 🟡 IMPORTANT — Tenant ID not validated — allows characters that break paths
Location: scripts/1-setup-system.sh — tenant ID prompt
Problem:
Tenant ID is used in:

Directory paths: /mnt/data/${TENANT_ID}/
Docker network: ${TENANT_ID}_network
Docker project name: --project-name ${TENANT_ID}
Postgres DB names: ${TENANT_ID}_n8n

If tenant ID contains spaces, uppercase, /, or - as first char,
all of these break silently.
Fix:
prompt_tenant_id() {
    while true; do
        echo ""
        echo "  Tenant ID is used for directory names, Docker networks,"
        echo "  and database names. Use lowercase letters and numbers only."
        echo "  Examples: client1  |  prod  |  acme  |  staging2"
        echo ""
        read -p "  ➤ Tenant ID: " TENANT_ID
        
        # Lowercase
        TENANT_ID="${TENANT_ID,,}"
        
        if [[ "${TENANT_ID}" =~ ^[a-z][a-z0-9]{2,19}$ ]]; then
            break
        fi
        
        echo "  ❌ Invalid: '${TENANT_ID}'"
        echo "  Must start with a letter, 3-20 chars, lowercase alphanumeric only"
    done
}

S1-008 🟢 POLISH — Full UI restoration required
Location: scripts/1-setup-system.sh — entire script
Problem:
Current version is missing all UI elements from the original:

╔═╗ double-line header box
┌─┐ section boxes per step
[ STEP N of 7 ] counter
➤ prompt character on all read calls
ask_service() helper with emoji + aligned columns
Service category groupings (CORE / AI MODELS / INTERFACES / MONITORING / SECURITY)
print_summary() before final confirm
setup_with_progress() with [1/5] counters during directory setup
Final success message with next step instruction

Fix — restore all helpers:
# 
Keep going═══════════════════════════════════════
# UI HELPERS — restore all of these
# ═══════════════════════════════════════

BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

print_header() {
    clear
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}          AI Platform Setup - Multi-Tenant Edition            ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}${DIM}                    Setup & Configuration                     ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    local step="${1}"
    local total="${2}"
    local title="${3}"
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

log() {
    local level="${1}"
    local message="${2}"
    case "${level}" in
        SUCCESS) echo -e "  ${GREEN}✅  ${message}${NC}" ;;
        INFO)    echo -e "  ${CYAN}ℹ️   ${message}${NC}" ;;
        WARN)    echo -e "  ${YELLOW}⚠️   ${message}${NC}" ;;
        ERROR)   echo -e "  ${RED}❌  ${message}${NC}" ;;
        STEP)    echo -e "  ${BLUE}🔧  ${message}${NC}" ;;
    esac
}

# Service selection with aligned columns and emoji
ask_service() {
    local service_name="${1}"
    local emoji="${2}"
    local description="${3}"
    local default="${4:-y}"
    local var_name="${5}"
    
    local prompt_default
    if [ "${default}" = "y" ]; then
        prompt_default="Y/n"
    else
        prompt_default="y/N"
    fi
    
    printf "  %s  %-20s ${DIM}%s${NC}\n" "${emoji}" "${service_name}" "${description}"
    read -p "     Enable? [${prompt_default}]: " choice
    choice="${choice:-${default}}"
    
    if [[ "${choice}" =~ ^[Yy]$ ]]; then
        eval "${var_name}=true"
        echo -e "     ${GREEN}✅ Enabled${NC}"
    else
        eval "${var_name}=false"
        echo -e "     ${RED}⬜ Disabled${NC}"
    fi
    echo ""
}

# Progress steps during setup
setup_with_progress() {
    local total_steps=5
    
    echo ""
    log "STEP" "[1/${total_steps}] Creating directory structure..."
    create_directories
    log "SUCCESS" "Directories created"
    
    log "STEP" "[2/${total_steps}] Setting permissions..."
    set_permissions
    log "SUCCESS" "Permissions set"
    
    log "STEP" "[3/${total_steps}] Generating credentials..."
    generate_credentials
    log "SUCCESS" "Credentials generated"
    
    log "STEP" "[4/${total_steps}] Writing .env file..."
    write_env_file
    log "SUCCESS" ".env written to ${DATA_ROOT}/config/.env"
    
    log "STEP" "[5/${total_steps}] Validating configuration..."
    validate_env_file
    log "SUCCESS" "Configuration validated"
    echo ""
}

# Deployment summary before final confirm
print_summary() {
    echo ""
    echo -e "${CYAN}  ╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}  ║${NC}  ${BOLD}CONFIGURATION SUMMARY${NC}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}  ║${NC}  Tenant ID    : ${BOLD}${TENANT_ID}${NC}"
    echo -e "${CYAN}  ║${NC}  Domain       : ${BOLD}${DOMAIN}${NC}"
    echo -e "${CYAN}  ║${NC}  Data Root    : ${BOLD}${DATA_ROOT}${NC}"
    echo -e "${CYAN}  ║${NC}  Tenant UID   : ${BOLD}${TENANT_UID}:${TENANT_GID}${NC}"
    echo -e "${CYAN}  ║${NC}  GPU          : ${BOLD}${GPU_TYPE} (enabled: ${GPU_ENABLED})${NC}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}  ║${NC}  ${BOLD}SERVICES${NC}"
    echo -e "${CYAN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    
    # Core
    print_summary_row "🐘 PostgreSQL"    "true"               "always on"
    print_summary_row "🔴 Redis"         "true"               "always on"
    print_summary_row "🔍 Qdrant"        "${ENABLE_QDRANT}"
    
    # AI
    print_summary_row "🤖 Ollama"        "${ENABLE_OLLAMA}"
    print_summary_row "⚡ LiteLLM"       "${ENABLE_LITELLM}"
    
    # Interfaces
    print_summary_row "🔄 n8n"           "${ENABLE_N8N}"
    print_summary_row "🌊 Flowise"       "${ENABLE_FLOWISE}"
    print_summary_row "📚 AnythingLLM"   "${ENABLE_ANYTHINGLLM}"
    print_summary_row "💬 Signal"        "${ENABLE_SIGNAL}"
    print_summary_row "🔧 OpenWebUI"     "${ENABLE_OPENWEBUI}"
    
    # Monitoring
    print_summary_row "📊 Grafana"       "${ENABLE_GRAFANA}"
    print_summary_row "🔒 Authentik"     "${ENABLE_AUTHENTIK}"
    print_summary_row "🌐 Tailscale"     "${ENABLE_TAILSCALE}"
    
    echo -e "${CYAN}  ╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_summary_row() {
    local service="${1}"
    local enabled="${2}"
    local note="${3:-}"
    
    if [ "${enabled}" = "true" ]; then
        printf "  ${CYAN}║${NC}  %-22s ${GREEN}✅ Enabled${NC}  ${DIM}%s${NC}\n" \
            "${service}" "${note}"
    else
        printf "  ${CYAN}║${NC}  %-22s ${DIM}⬜ Disabled${NC}  ${DIM}%s${NC}\n" \
            "${service}" "${note}"
    fi
}

# Final success message
print_success() {
    echo ""
    echo -e "${GREEN}  ╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}  ║${NC}  ${BOLD}✅  Setup Complete!${NC}"
    echo -e "${GREEN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}  ║${NC}  Configuration saved to:"
    echo -e "${GREEN}  ║${NC}    ${BOLD}${DATA_ROOT}/config/.env${NC}"
    echo -e "${GREEN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}  ║${NC}  ${BOLD}Next Step:${NC}"
    echo -e "${GREEN}  ║${NC}    ${CYAN}➤  sudo bash scripts/2-deploy-services.sh${NC}"
    echo -e "${GREEN}  ╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

S1-009 🟢 POLISH — Service selection missing category groupings
Location: scripts/1-setup-system.sh — service selection block
Problem:
Current version lists services in a flat unsorted list with no
grouping. Original had clear category headers making it easy to
understand what each service does before enabling it.
Fix — restore category blocks:
select_services() {
    print_step "3" "7" "Select Services to Deploy"
    
    # ── CORE (always on) ─────────────────────────────────────
    echo -e "  ${BOLD}${BLUE}── CORE SERVICES (always enabled) ────────────────────${NC}"
    echo ""
    echo -e "  🐘  PostgreSQL          ${DIM}Relational database for all services${NC}"
    echo -e "  🔴  Redis               ${DIM}Cache and queue backend${NC}"
    echo ""
    
    # ── VECTOR DB ────────────────────────────────────────────
    print_divider
    echo -e "  ${BOLD}${BLUE}── VECTOR DATABASE ────────────────────────────────────${NC}"
    echo ""
    ask_service "Qdrant"        "🔍" "Vector database for embeddings"      "y" "ENABLE_QDRANT"
    
    # ── AI MODELS ────────────────────────────────────────────
    print_divider
    echo -e "  ${BOLD}${BLUE}── AI MODELS ──────────────────────────────────────────${NC}"
    echo ""
    ask_service "Ollama"        "🤖" "Local LLM inference engine"           "y" "ENABLE_OLLAMA"
    ask_service "LiteLLM"       "⚡" "OpenAI-compatible proxy + routing"    "y" "ENABLE_LITELLM"
    
    # ── INTERFACES ───────────────────────────────────────────
    print_divider
    echo -e "  ${BOLD}${BLUE}── INTERFACES ─────────────────────────────────────────${NC}"
    echo ""
    ask_service "n8n"           "🔄" "Workflow automation"                  "y" "ENABLE_N8N"
    ask_service "Flowise"       "🌊" "Visual AI workflow builder"           "y" "ENABLE_FLOWISE"
    ask_service "AnythingLLM"   "📚" "Document chat + RAG interface"        "y" "ENABLE_ANYTHINGLLM"
    ask_service "OpenWebUI"     "🔧" "Chat UI for Ollama models"            "y" "ENABLE_OPENWEBUI"
    ask_service "Signal"        "💬" "Signal messenger AI bridge"           "n" "ENABLE_SIGNAL"
    
    # ── MONITORING ───────────────────────────────────────────
    print_divider
    echo -e "  ${BOLD}${BLUE}── MONITORING & SECURITY ──────────────────────────────${NC}"
    echo ""
    ask_service "Grafana"       "📊" "Metrics dashboard + alerting"         "n" "ENABLE_GRAFANA"
    ask_service "Authentik"     "🔒" "SSO and identity provider"            "n" "ENABLE_AUTHENTIK"
    ask_service "Tailscale"     "🌐" "Zero-config VPN mesh network"         "n" "ENABLE_TAILSCALE"
    
    print_divider
}

SCRIPT 2 — Deploy Services

S2-001 🔴 BLOCKING — generate_postgres_init() heredoc not single-quoted
Location: scripts/2-deploy-services.sh — generate_postgres_init()
Problem:
cat > "${INIT_FILE}" << EOF
CREATE DATABASE ${TENANT_ID}_n8n;
EOF
The EOF marker is unquoted so bash expands ${TENANT_ID} at
write time using the calling shell's environment. If .env has not
been sourced yet, all variables expand to empty strings. The init
file is written as CREATE DATABASE _n8n; which is a syntax error
in postgres.
Fix:
cat > "${INIT_FILE}" << 'INITEOF'
-- This file is generated. Variables are literal — do not edit.
CREATE DATABASE ${TENANT_ID}_n8n OWNER ${TENANT_ID}_user;
CREATE DATABASE ${TENANT_ID}_flowise OWNER ${TENANT_ID}_user;
CREATE DATABASE ${TENANT_ID}_anythingllm OWNER ${TENANT_ID}_user;
CREATE DATABASE ${TENANT_ID}_authentik OWNER ${TENANT_ID}_user;
INITEOF
Then use sed to substitute after writing:
sed -i \
    -e "s/\${TENANT_ID}/${TENANT_ID}/g" \
    "${INIT_FILE}"

S2-002 🔴 BLOCKING — Signal port mapping inverted
Location: scripts/2-deploy-services.sh — append_signal()
Problem:
ports:
  - "${SIGNAL_PORT}:8080"
This maps host port SIGNAL_PORT → container port 8080.
Signal-CLI REST API listens on 8080 inside the container, so this
is actually correct IF SIGNAL_PORT is the desired host port.
BUT in .env, SIGNAL_PORT=8080 by default, which makes Caddy
unable to proxy to it because 8080 is also the internal Caddy
admin port in some configurations. Additionally if the user has
changed SIGNAL_PORT to something else, the mapping must be:
ports:
  - "127.0.0.1:${SIGNAL_PORT}:8080"
Binding to 127.0.0.1 prevents direct external access — all access
must go through Caddy reverse proxy. Apply this pattern to ALL
service port mappings that are proxied by Caddy.

S2-003 🔴 BLOCKING — main() call order wrong — preflight runs after compose write
Location: scripts/2-deploy-services.sh — main()
Problem:
Current call order:
main() {
    load_env
    generate_compose
    preflight_checks    # ← TOO LATE
    docker compose up
}
Preflight checks (disk space, Docker running, port availability) must
run before any files are written.
Fix — correct call order:
main() {
    print_header
    load_env
    preflight_checks        # 1. Check system before anything
    confirm_deployment      # 2. Show summary, ask confirm
    generate_compose        # 3. Write files
    generate_postgres_init  # 4. Write DB init
    generate_caddyfile      # 5. Write Caddy config
    pull_images             # 6. Pull (slow, do before up)
    deploy_containers       # 7. docker compose up -d
    wait_for_health         # 8. Health checks
    output_service_urls     # 9. Print access URLs
    output_tailscale_info   # 10. Tailscale status if enabled
    print_success           # 11. Final message
}

S2-004 🔴 BLOCKING — Caddy depends_on appended incorrectly
Location: scripts/2-deploy-services.sh — append_caddy()
Problem:
The Caddy service depends_on block is built by concatenating
strings in a loop:
DEPENDS="${DEPENDS} - ${service}"
This produces malformed YAML indentation. Each list item needs
exactly 6 spaces of indent to match the compose file structure.
Fix:
generate_caddy_depends() {
    local depends=""
    [ "${ENABLE_N8N}" = "true" ]          && depends+="      - n8n\n"
    [ "${ENABLE_FLOWISE}" = "true" ]      && depends+="      - flowise\n"
    [ "${ENABLE_ANYTHINGLLM}" = "true" ]  && depends+="      - anythingllm\n"
    [ "${ENABLE_OPENWEBUI}" = "true" ]    && depends+="      - openwebui\n"
    [ "${ENABLE_LITELLM}" = "true" ]      && depends+="      - litellm\n"
    [ "${ENABLE_SIGNAL}" = "true" ]       && depends+="      - signal\n"
    [ "${ENABLE_GRAFANA}" = "true" ]      && depends+="      - grafana\n"
    [ "${ENABLE_AUTHENTIK}" = "true" ]    && depends+="      - authentik\n"
    echo -e "${depends}"
}

S2-005 🟡 IMPORTANT — Qdrant missing API key in environment block
Location: scripts/2-deploy-services.sh — append_qdrant()
Problem:
Qdrant is deployed without its API key set in the container
environment. The key is generated in script 1 and written to .env
as QDRANT_API_KEY but never passed into the container.
Fix:
environment:
  - QDRANT__SERVICE__API_KEY=${QDRANT_API_KEY}
  - QDRANT__SERVICE__HOST=0.0.0.0

S2-006 🟡 IMPORTANT — AnythingLLM missing auth token and LiteLLM config
Location: scripts/2-deploy-services.sh — append_anythingllm()
Problem:
AnythingLLM is deployed without:

AUTH_TOKEN — anyone can access the UI without login
LITE_LLM_MODEL_PREF — model selection is blank on first launch
STORAGE_DIR — defaults to container path, ignores volume mount

Fix:
environment:
  - AUTH_TOKEN=${ANYTHINGLLM_AUTH_TOKEN}
  - LITE_LLM_MODEL_PREF=ollama/llama3
  - STORAGE_DIR=/app/server/storage
  - JWT_SECRET=${ANYTHINGLLM_JWT_SECRET}
  - DB_TYPE=postgres
  - DB_CONNECTION_STRING=postgresql://${DB_USER}:${DB_PASSWORD}@postgres:5432/${TENANT_ID}_anythingllm

S2-007 🟡 IMPORTANT — wait_for_health() missing — no health check after deploy
Location: scripts/2-deploy-services.sh — main()
Problem:
After docker compose up -d, the script immediately prints URLs
and exits. Containers may still be starting. Users who immediately
try to access the services get connection refused errors and assume
the deployment failed.
Fix:
wait_for_health() {
    log "INFO" "Waiting for services to become healthy..."
    echo ""
    
Keep going     local services=()
    local urls=()
    
    [ "${ENABLE_N8N}" = "true" ] && {
        services+=("n8n")
        urls+=("http://localhost:${N8N_PORT:-5678}/healthz")
    }
    [ "${ENABLE_FLOWISE}" = "true" ] && {
        services+=("flowise")
        urls+=("http://localhost:${FLOWISE_PORT:-3000}/api/v1/ping")
    }
    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && {
        services+=("anythingllm")
        urls+=("http://localhost:${ANYTHINGLLM_PORT:-3001}/api/ping")
    }
    [ "${ENABLE_OPENWEBUI}" = "true" ] && {
        services+=("openwebui")
        urls+=("http://localhost:${OPENWEBUI_PORT:-8080}/health")
    }
    [ "${ENABLE_LITELLM}" = "true" ] && {
        services+=("litellm")
        urls+=("http://localhost:${LITELLM_PORT:-4000}/health")
    }
    [ "${ENABLE_GRAFANA}" = "true" ] && {
        services+=("grafana")
        urls+=("http://localhost:${GRAFANA_PORT:-3100}/api/health")
    }
    
    local max_wait=120
    local interval=5
    local elapsed=0
    
    for i in "${!services[@]}"; do
        local service="${services[$i]}"
        local url="${urls[$i]}"
        local waited=0
        
        printf "  ⏳  %-20s " "${service}..."
        
        while ! curl -sf "${url}" > /dev/null 2>&1; do
            if [ "${waited}" -ge "${max_wait}" ]; then
                echo -e "${RED}TIMEOUT after ${max_wait}s${NC}"
                log "WARN" "${service} did not become healthy — check: docker logs ${service}"
                break
            fi
            sleep "${interval}"
            waited=$((waited + interval))
            printf "."
        done
        
        if curl -sf "${url}" > /dev/null 2>&1; then
            echo -e " ${GREEN}healthy (${waited}s)${NC}"
        fi
    done
    
    echo ""
}

S2-008 🟡 IMPORTANT — pull_images() missing — cold start pulls during up
Location: scripts/2-deploy-services.sh — main()
Problem:
Images are pulled inline during docker compose up -d. This means:

No progress feedback during the pull (just a hanging terminal)
If one pull fails, up partially starts then fails mid-deploy
No retry logic

Fix — add explicit pull step with per-image feedback:
pull_images() {
    log "INFO" "Pulling Docker images..."
    echo ""
    
    local images=()
    
    # Always pulled
    images+=(
        "postgres:16-alpine"
        "redis:7-alpine"
        "caddy:2-alpine"
    )
    
    # Conditional
    [ "${ENABLE_QDRANT}" = "true" ]       && images+=("qdrant/qdrant:latest")
    [ "${ENABLE_OLLAMA}" = "true" ]       && images+=("ollama/ollama:latest")
    [ "${ENABLE_LITELLM}" = "true" ]      && images+=("ghcr.io/berriai/litellm:main-latest")
    [ "${ENABLE_N8N}" = "true" ]          && images+=("n8nio/n8n:latest")
    [ "${ENABLE_FLOWISE}" = "true" ]      && images+=("flowiseai/flowise:latest")
    [ "${ENABLE_ANYTHINGLLM}" = "true" ]  && images+=("mintplexlabs/anythingllm:latest")
    [ "${ENABLE_OPENWEBUI}" = "true" ]    && images+=("ghcr.io/open-webui/open-webui:main")
    [ "${ENABLE_SIGNAL}" = "true" ]       && images+=("bbernhard/signal-cli-rest-api:latest")
    [ "${ENABLE_GRAFANA}" = "true" ]      && images+=("grafana/grafana:latest")
    [ "${ENABLE_AUTHENTIK}" = "true" ]    && images+=("ghcr.io/goauthentik/server:latest")
    [ "${ENABLE_TAILSCALE}" = "true" ]    && images+=("tailscale/tailscale:latest")
    
    local total="${#images[@]}"
    local current=0
    local failed=()
    
    for image in "${images[@]}"; do
        current=$((current + 1))
        printf "  [%d/%d]  Pulling %-45s " "${current}" "${total}" "${image}..."
        
        if docker pull "${image}" > /dev/null 2>&1; then
            echo -e "${GREEN}done${NC}"
        else
            echo -e "${RED}FAILED${NC}"
            failed+=("${image}")
        fi
    done
    
    echo ""
    
    if [ "${#failed[@]}" -gt 0 ]; then
        log "ERROR" "Failed to pull the following images:"
        for img in "${failed[@]}"; do
            echo "    - ${img}"
        done
        echo ""
        read -p "  Continue deployment anyway? [y/N]: " choice
        if [[ ! "${choice}" =~ ^[Yy]$ ]]; then
            log "ERROR" "Deployment aborted"
            exit 1
        fi
    fi
}

S2-009 🟢 POLISH — Output URLs not formatted — wall of plain text
Location: scripts/2-deploy-services.sh — output_service_urls()
Problem:
Current output is plain echo lines with no formatting.
Missing from original:

Bordered summary box
Emoji per service
Login credentials shown inline
Tailscale URLs shown separately if enabled
Next Step prompt pointing to script 3

Fix — restore formatted URL output:
output_service_urls() {
    echo ""
    echo -e "${GREEN}  ╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}  ║${NC}  ${BOLD}🌐  Service Access URLs${NC}"
    echo -e "${GREEN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    
    local base="https://${DOMAIN}"
    
    if [ "${ENABLE_N8N}" = "true" ]; then
        echo -e "${GREEN}  ║${NC}  🔄  n8n Workflows"
        echo -e "${GREEN}  ║${NC}      ${CYAN}${base}/n8n/${NC}"
        echo -e "${GREEN}  ║${NC}      Login: admin / ${N8N_PASSWORD}"
        echo -e "${GREEN}  ║${NC}"
    fi
    
    if [ "${ENABLE_FLOWISE}" = "true" ]; then
        echo -e "${GREEN}  ║${NC}  🌊  Flowise"
        echo -e "${GREEN}  ║${NC}      ${CYAN}${base}/flowise/${NC}"
        echo -e "${GREEN}  ║${NC}      Login: admin / ${FLOWISE_PASSWORD}"
        echo -e "${GREEN}  ║${NC}"
    fi
    
    if [ "${ENABLE_ANYTHINGLLM}" = "true" ]; then
        echo -e "${GREEN}  ║${NC}  📚  AnythingLLM"
        echo -e "${GREEN}  ║${NC}      ${CYAN}${base}/anythingllm/${NC}"
        echo -e "${GREEN}  ║${NC}      Token: ${ANYTHINGLLM_AUTH_TOKEN}"
        echo -e "${GREEN}  ║${NC}"
    fi
    
    if [ "${ENABLE_OPENWEBUI}" = "true" ]; then
        echo -e "${GREEN}  ║${NC}  🔧  OpenWebUI"
        echo -e "${GREEN}  ║${NC}      ${CYAN}${base}/openwebui/${NC}"
        echo -e "${GREEN}  ║${NC}      First launch: create admin account"
        echo -e "${GREEN}  ║${NC}"
    fi
    
    if [ "${ENABLE_LITELLM}" = "true" ]; then
        echo -e "${GREEN}  ║${NC}  ⚡  LiteLLM Proxy"
        echo -e "${GREEN}  ║${NC}      ${CYAN}${base}/litellm/${NC}"
        echo -e "${GREEN}  ║${NC}      API Key: ${LITELLM_MASTER_KEY}"
        echo -e "${GREEN}  ║${NC}"
    fi
    
    if [ "${ENABLE_GRAFANA}" = "true" ]; then
        echo -e "${GREEN}  ║${NC}  📊  Grafana"
        echo -e "${GREEN}  ║${NC}      ${CYAN}${base}/grafana/${NC}"
        echo -e "${GREEN}  ║${NC}      Login: admin / ${GRAFANA_PASSWORD}"
        echo -e "${GREEN}  ║${NC}"
    fi
    
    if [ "${ENABLE_AUTHENTIK}" = "true" ]; then
        echo -e "${GREEN}  ║${NC}  🔒  Authentik SSO"
        echo -e "${GREEN}  ║${NC}      ${CYAN}${base}/authentik/${NC}"
        echo -e "${GREEN}  ║${NC}      Setup required on first launch"
        echo -e "${GREEN}  ║${NC}"
    fi
    
    echo -e "${GREEN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}  ║${NC}  ${BOLD}Next Step:${NC}"
    echo -e "${GREEN}  ║${NC}    ${CYAN}➤  sudo bash scripts/3-configure-services.sh${NC}"
    echo -e "${GREEN}  ╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

SCRIPT 3 — Configure Services

S3-001 🔴 BLOCKING — n8n API calls use wrong auth header
Location: scripts/3-configure-services.sh — configure_n8n()
Problem:
curl -H "Authorization: Basic $(echo -n admin:${N8N_PASSWORD} | base64)"
n8n API uses X-N8N-API-KEY header not Basic auth. Basic auth is
only for the UI login. API calls with Basic auth return 401.
Fix:
# First get the API key via UI login, then use it
N8N_API_KEY=$(curl -sf \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"admin@${DOMAIN}\",\"password\":\"${N8N_PASSWORD}\"}" \
    "http://localhost:${N8N_PORT:-5678}/api/v1/login" \
    | jq -r '.data.token')

# Then use it
curl -sf \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    "http://localhost:${N8N_PORT:-5678}/api/v1/workflows"

S3-002 🔴 BLOCKING — Flowise config uses removed API endpoint
Location: scripts/3-configure-services.sh — configure_flowise()
Problem:
curl -X POST http://localhost:${FLOWISE_PORT}/api/v1/settings
/api/v1/settings was removed in Flowise 1.8.0. Current version
is 2.x. The correct endpoint for credentials is:
POST /api/v1/credentials
Fix:
configure_flowise() {
    log "INFO" "Configuring Flowise..."
    
    # Get auth token
    local token
    token=$(curl -sf \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"admin\",\"password\":\"${FLOWISE_PASSWORD}\"}" \
        "http://localhost:${FLOWISE_PORT:-3000}/api/v1/login" \
        | jq -r '.accessToken')
    
    if [ -z "${token}" ] || [ "${token}" = "null" ]; then
        log "WARN" "Could not authenticate to Flowise — skipping auto-config"
        return 0
    fi
    
    # Create Ollama credential if Ollama is enabled
    if [ "${ENABLE_OLLAMA}" = "true" ]; then
        curl -sf \
            -X POST \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            -d "{
                \"name\": \"Ollama Local\",
                \"credentialName\": \"ollamaApi\",
                \"plainDataObj\": {
                    \"ollamaUrl\": \"http://ollama:11434\"
                }
            }" \
            "http://localhost:${FLOWISE_PORT:-3000}/api/v1/credentials" \
            > /dev/null
        log "SUCCESS" "Flowise: Ollama credential created"
    fi
}

S3-003 🔴 BLOCKING — LiteLLM config posted before service is ready
Location: scripts/3-configure-services.sh — configure_litellm()
Problem:
LiteLLM config is POSTed immediately after docker compose up.
LiteLLM takes 15-30 seconds to initialize its database on first
launch. The POST returns 503 and the config is never applied,
but the script does not check the response code.
Fix — wait for LiteLLM before configuring:
configure_litellm() {
    log "INFO" "Waiting for LiteLLM to be ready..."
    
    local max_wait=60
    local waited=0
    
    until curl -sf \
        -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
        "http://localhost:${LITELLM_PORT:-4000}/health" \
        > /dev/null 2>&1
    do
        if [ "${waited}" -ge "${max_wait}" ]; then
            log "ERROR" "LiteLLM did not become ready after ${max_wait}s"
            return 1
        fi
        sleep 5
        waited=$((waited + 5))
        printf "."
    done
    echo ""
    
    log "INFO" "Configuring LiteLLM models..."
    
    # Add Ollama models
    if [ "${ENABLE_OLLAMA}" = "true" ]; then
        local models=("llama3" "mistral" "codellama" "nomic-embed-text")
        
        for model in "${models[@]}"; do
            local response
            response=$(curl -sf -w "%{http_code}" \
                -X POST \
                -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
                -H "Content-Type: application/json" \
                -d "{
                    \"model_name\": \"${model}\",
                    \"litellm_params\": {
                        \"model\": \"ollama/${model}\",
                        \"api_base\": \"http://ollama:11434\"
                    }
                }" \
                "http://localhost:${LITELLM_PORT:-4000}/model/new")
            
            local http_code="${response: -3}"
            if [ "${http_code}" = "200" ] || [ "${http_code}" = "201" ]; then
                log "SUCCESS" "LiteLLM: model '${model}' added"
            else
                log "WARN" "LiteLLM: failed to add '${model}' (HTTP ${http_code})"
            fi
        done
    fi
}

S3-004 🟡 IMPORTANT — Script 3 missing load_env() — all variables undefined
Location: scripts/3-configure-services.sh — top of script
Problem:
Script 3 references ${DOMAIN}, ${N8N_PASSWORD}, ${FLOWISE_PASSWORD}
etc. but never sources .env. All variables are empty strings.
Every API call uses blank credentials and fails with 401.
Fix — add at top of script 3 before any function calls:
load_env() {
    local env_file="${DATA_ROOT}/config/.env"
    
    if [ ! -f "${env_file}" ]; then
        log "ERROR" ".env not found at ${env_file}"
        log "ERROR" "Run script 1 first: sudo bash scripts/1-setup-system.sh"
        exit 1
    fi
    
    # Export all variables from .env
    set -a
    # shellcheck source=/dev/null
    source "${env_file}"
    set +a
    
    log "SUCCESS" "Environment loaded from ${env_file}"
    log "INFO"    "Tenant: ${TENANT_ID} | Domain: ${DOMAIN}"
}

S3-005 🟡 IMPORTANT — No --skip flags for partial re-runs
Location: scripts/3-configure-services.sh — main()
Problem:
If one service config fails mid-run, the entire script must be
re-run from the beginning. Re-running n8n config creates duplicate
credentials/workflows. Re-running Ollama model pulls re-downloads
multi-GB models.
Fix — add skip flags:
main() {
    # Parse flags
    SKIP_N8N=false
    SKIP_FLOWISE=false
    SKIP_OLLAMA=false
    SKIP_LITELLM=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-n8n)      SKIP_N8N=true ;;
            --skip-flowise)  SKIP_FLOWISE=true ;;
            --skip-ollama)   SKIP_OLLAMA=true ;;
            --skip-litellm)  SKIP_LITELLM=true ;;
            --help)
                echo "Usage: $0 [--skip-n8n] [--skip-flowise]"
                echo "          [--skip-ollama] [--skip-litellm]"
                exit 0
                ;;
        esac
        shift
    done
    
    load_env
    print_header
    
    [ "${SKIP_N8N}" = "false" ]     && [ "${ENABLE_N8N}" = "true" ]     && configure_n8n
    [ "${SKIP_FLOWISE}" = "false" ] && [ "${ENABLE_FLOWISE}" = "true" ] && configure_flowise
    [ "${SKIP_OLLAMA}" = "false" ]  && [ "${ENABLE_OLLAMA}" = "true" ]  && pull_ollama_models
    [ "${SKIP_LITELLM}" = "false" ] && [ "${ENABLE_LITELLM}" = "true" ] && configure_litellm
    
    print_success
}

S3-006 🟢 POLISH — Script 3 missing header, step counters and success box
Location: scripts/3-configure-services.sh — entire script
Problem:
Script 3 has no UI — it runs silently with raw echo output.
Missing:

Header box (same style as scripts 1 and 2)
[ STEP N of N ] counters
Per-service progress dots during API calls
Final success box with credential summary

Fix — add consistent UI:
print_header() {
    clear
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}        AI Platform Configuration - Script 3 of 3             ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}${DIM}              Connecting & configuring services               ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_success() {
    echo ""
    echo -e "${GREEN}  ╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}  ║${NC}  ${BOLD}✅  Configuration Complete!${NC}"
    echo -e "${GREEN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}  ║${NC}  All services are configured and ready."
    echo -e "${GREEN}  ║${NC}"
    echo -e "${GREEN}  ║${NC}  ${BOLD}Access your platform:${NC}"
    echo -e "${GREEN}  ║${NC}    ${CYAN}➤  https://${DOMAIN}${NC}"
    echo -e "${GREEN}  ║${NC}"
    echo -e "${GREEN}  ║${NC}  ${BOLD}Credentials saved at:${NC}"
    echo -e "${GREEN}  ║${NC}    ${CYAN}➤  ${DATA_ROOT}/config/.env${NC}"
    echo -e "${GREEN}  ╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}  ║${NC}  ${BOLD}Useful commands:${NC}"
    echo -e "${GREEN}  ║${NC}    docker compose -f ${DATA_ROOT}/compose/docker-compose.yml ps"
    echo -e "${GREEN}  ║${NC}    docker compose -f ${DATA_ROOT}/compose/docker-compose.yml logs -f"
    echo -e "${GREEN}  ╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

CADDYFILE — Reverse Proxy

C-001 🔴 BLOCKING — Authentik forward auth strips original Host header
Location: scripts/2-deploy-services.sh — generate_caddyfile() — authentik block
Problem:
forward_auth authentik:9000 {
    uri /outpost.goauthentik.io/auth/caddy
}
Missing required headers — Authentik needs to see the original
X-Forwarded-Host and X-Original-URL to redirect back correctly
after login. Without them, post-login redirect loops to /.
Fix:
forward_auth authentik:9000 {
    uri /outpost.goauthentik.io/auth/caddy
    copy_headers X-Authentik-Username X-Authentik-Groups \
                 X-Authentik-Email X-Authentik-Name \
                 X-Authentik-Uid X-Authentik-Jwt \
                 X-Authentik-Meta-Jwks X-Authentik-Meta-Outpost \
                 X-Authentik-Meta-Provider X-Authentik-Meta-App \
                 X-Authentik-Meta-Version
    header_up X-Original-URL {scheme}://{host}{uri}
    header_up X-Forwarded-Host {host}
}

C-002 🔴 BLOCKING — n8n websocket path not proxied
Location: scripts/2-deploy-services.sh — generate_caddyfile() — n8n block
Problem:
n8n uses websockets for real-time workflow execution feedback.
Current config only has reverse_proxy n8n:5678 with no websocket
upgrade header, so the WS connection falls back to polling —
execution logs don't update in real time and the editor feels broken.
Fix:
handle /n8n/* {
    uri strip_prefix /n8n
    reverse_proxy n8n:5678 {
        header_up Host {upstream_hostport}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        
        # WebSocket support
        transport http {
            read_buffer  4096
            write_buffer 4096
        }
    }
}

C-003 🟡 IMPORTANT — No TLS options block — ACME rate limit risk
Location: scripts/2-deploy-services.sh — generate_caddyfile() — global block
Problem:
No email is set in the Caddy global block. ACME certificate
requests without an email:

Cannot receive expiry warning emails
Are subject to stricter rate limits on Let's Encrypt
Cannot be recovered if the account is lost

Fix:
{
    email {$ACME_EMAIL}
    acme_ca https://acme-v02.api.letsencrypt.org/directory
    
    # Use staging for testing to avoid rate limits
    # acme_ca https://acme-staging-v02.api.letsencrypt.org/directory
    
    servers {
        timeouts {
            read_body   10s
            read_header 10s
            write        30s
            idle         2m
        }
    }
}
Add ACME_EMAIL to .env in script 1 — prompt with domain validation:
read -p "  ➤ Admin email (for SSL cert alerts): " ACME_EMAIL
while [[ ! "${ACME_EMAIL}" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; do
    echo "  ❌ Invalid email"
    read -p "  ➤ Admin email: " ACME_EMAIL
done

README

R-001 🟢 POLISH — README missing troubleshooting section
Location: README.md
Problem:
README jumps from "run script 3" to "access services" with nothing
in between. When something goes wrong there are no debugging steps.
Most common failures:

Caddy cannot get TLS cert (DNS not propagated)
Postgres init fails (volume permissions)
Ollama OOM killed (not enough RAM)

Fix — add troubleshooting section:
## Troubleshooting

### Caddy TLS / Certificate errors
```bash
# Check Caddy logs
docker logs caddy -f

# Common causes:
# 1. DNS not pointing to server yet — wait 5 min after setting A record
# 2. Port 80/443 blocked by firewall/security group
# 3. ACME rate limit hit — wait 1 hour or use staging CA

# Test DNS
dig +short yourdomain.com
curl -v http://yourdomain.com
Postgres won't start
docker logs postgres -f

# Common causes:
# 1. Wrong permissions on data directory
sudo chown -R 999:999 /mnt/data/${TENANT_ID}/postgres/

# 2. Init script syntax error
cat /mnt/data/${TENANT_ID}/config/init.sql
Ollama out of memory
docker logs ollama -f

# Reduce model size or add swap:
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
Check all service status
docker compose -f /mnt/data/${TENANT_ID}/compose/docker-compose.yml ps
View logs for specific service
docker compose -f /mnt/data/${TENANT_ID}/compose/docker-compose.yml \
    logs -f n8n

---

## Complete Issue Summary

| ID | Priority | Script | Issue |
|----|----------|--------|-------|
| S0-001 | 🔴 | Script 0 | `docker compose down` fails if compose file missing |
| S1-001 | 🔴 | Script 1 | `check_root()` missing — scripts run as wrong user |
| S1-002 | 🔴 | Script 1 | Tenant UID not validated after user creation |
| S1-003 | 🔴 | Script 1 | Tailscale auth key written as empty placeholder |
| S1-004 | 🟡 | Script 1 | GPU detection does not set `OLLAMA_GPU_LAYERS` |
| S1-005 | 🟡 | Script 1 | EBS mount check warns but does not block |
| S1-006 | 🟡 | Script 1 | Domain validation missing — accepts garbage input |
| S1-007 | 🟡 | Script 1 | Tenant ID not validated — allows path-breaking chars |
| S1-008 | 🟢 | Script 1 | Full UI restoration required (all helpers missing) |
| S1-009 | 🟢 | Script 1 | Service selection missing category groupings |
| S2-001 | 🔴 | Script 2 | Postgres init heredoc expands vars at write time |
| S2-002 | 🔴 | Script 2 | Signal port not bound to localhost — exposed direct |
| S2-003 | 🔴 | Script 2 | `main()` call order wrong — preflight after compose write |
| S2-004 | 🔴 | Script 2 | Caddy `depends_on` indentation produces malformed YAML |
| S2-005 | 🟡 | Script 2 | Qdrant API key not passed into container environment |
| S2-006 | 🟡 | Script 2 | AnythingLLM missing auth token + storage dir in env |
| S2-007 | 🟡 | Script 2 | `wait_for_health()` missing — URLs printed before ready |
| S2-008 | 🟡 | Script 2 | `pull_images()` missing — cold pull during `up` |
| S2-009 | 🟢 | Script 2 | Service URL output not formatted — plain text wall |
| S3-001 | 🔴 | Script 3 | n8n API calls use wrong auth header (Basic vs API key) |
| S3-002 | 🔴 | Script 3 | Flowise config uses removed API endpoint |
| S3-003 | 🔴 | Script 3 | LiteLLM config posted before service ready |
| S3-004 | 🟡 | Script 3 | `load_env()` missing — all variables undefined |
| S3-005 | 🟡 | Script 3 | No `--skip` flags for partial re-runs |
| S3-006 | 🟢 | Script 3 | Missing header, step counters and success box |
| C-001 | 🔴 | Caddyfile | Authentik forward auth strips original Host header |
| C-002 | 🔴 | Caddyfile | n8n websocket path not proxied |
| C-003 | 🟡 | Caddyfile | No TLS email — ACME rate limit risk |
| R-001 | 🟢 | README | Missing troubleshooting section |

**Totals:**
- 🔴 BLOCKING:  13 issues
- 🟡 IMPORTANT: 10 issues  
- 🟢 POLISH:    6 issues
- **TOTAL:      29 issues**

---

**Document version:** `2024-01 — post-commit 0671bd7`  
**Next action:** Address all 🔴 BLOCKING issues before any 🟡 or 🟢
Ok now produce a summary of instructions for windsurf which will be grounded in your analysis you just produced Windsurf Implementation Instructions
AI Platform Automation — Fix All 29 Issues

CONTEXT
You are working on a 3-script bash deployment system for a multi-tenant AI platform on AWS EC2. The scripts deploy Docker services (n8n, Flowise, AnythingLLM, OpenWebUI, LiteLLM, Ollama, Qdrant, Grafana, Authentik, Tailscale) behind a Caddy reverse proxy with Postgres and Redis.
Repository: https://github.com/jgla1ne/AIPlatformAutomation
Files you will be editing:

scripts/1-setup-system.sh
scripts/2-deploy-services.sh
scripts/3-configure-services.sh
README.md

Work through each fix in order. Do not skip. Do not combine fixes silently. After each fix state what you changed and why.

PRIORITY ORDER
Fix in this exact order:

All 🔴 BLOCKING issues first (13 total)
All 🟡 IMPORTANT issues second (10 total)
All 🟢 POLISH issues last (6 total)


🔴 BLOCKING FIXES — DO THESE FIRST

FIX 1 — Script 1: Add check_root()
File: scripts/1-setup-system.sh
Add at the very top, before any other function is called:
check_root() {
    if [ "${EUID}" -ne 0 ]; then
        echo "❌  This script must be run as root"
        echo "    Run: sudo bash scripts/1-setup-system.sh"
        exit 1
    fi
}
Call it as the first line of main().

FIX 2 — Script 1: Validate tenant UID after user creation
File: scripts/1-setup-system.shIn the user creation block, after useradd:
TENANT_UID=$(id -u "${TENANT_ID}" 2>/dev/null)
if [ -z "${TENANT_UID}" ]; then
    log "ERROR" "Failed to create system user '${TENANT_ID}'"
    exit 1
fi
log "SUCCESS" "System user '${TENANT_ID}' created with UID ${TENANT_UID}"

FIX 3 — Script 1: Tailscale auth key — prompt properly, never write empty
File: scripts/1-setup-system.shReplace any placeholder write with this:
if [ "${ENABLE_TAILSCALE}" = "true" ]; then
    echo ""
    echo "  Get your auth key at: https://login.tailscale.com/admin/settings/keys"
    echo "  Use an ephemeral, reusable key for servers."
    echo ""
    while true; do
        read -p "  ➤ Tailscale Auth Key (tskey-auth-...): " TAILSCALE_AUTH_KEY
        if [[ "${TAILSCALE_AUTH_KEY}" == tskey-auth-* ]]; then
            break
        fi
        echo "  ⚠️  Key must start with 'tskey-auth-' — try again"
    done
fi
In script 2, before deploying Tailscale container, add guard:
if [ "${ENABLE_TAILSCALE}" = "true" ]; then
    if [ -z "${TAILSCALE_AUTH_KEY}" ] || \
       [[ "${TAILSCALE_AUTH_KEY}" != tskey-auth-* ]]; then
        log "ERROR" "TAILSCALE_AUTH_KEY is missing or invalid — re-run script 1"
        exit 1
    fi
fi

FIX 4 — Script 2: Postgres init heredoc — prevent variable expansion
File: scripts/2-deploy-services.shThe init SQL heredoc must use a quoted delimiter. Change:
cat > "${INIT_SQL}" << EOF
To:
cat > "${INIT_SQL}" << 'EOF'
This prevents ${TENANT_ID} and similar vars from being expanded at write time instead of at Postgres init time.

FIX 5 — Script 2: Bind Signal port to localhost only
File: scripts/2-deploy-services.shIn the Signal service compose block, change:
ports:
  - "${SIGNAL_PORT:-8080}:8080"
To:
ports:
  - "127.0.0.1:${SIGNAL_PORT:-8080}:8080"

FIX 6 — Script 2: Fix main() call order
File: scripts/2-deploy-services.shThe correct order in main() must be:
main() {
    check_root
    load_env
    print_header
    run_preflight_checks    # ← BEFORE compose is written
    generate_compose_file
    generate_caddyfile
    pull_images
    deploy_stack
    wait_for_health
    output_service_urls
}
Do not call deploy_stack before run_preflight_checks.

FIX 7 — Script 2: Fix Caddy depends_on YAML indentation
File: scripts/2-deploy-services.shReplace the generate_caddy_depends() helper with:
generate_caddy_depends() {
    local depends=""
    [ "${ENABLE_N8N}" = "true" ]         && depends+="      - n8n\n"
    [ "${ENABLE_FLOWISE}" = "true" ]     && depends+="      - flowise\n"
    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && depends+="      - anythingllm\n"
    [ "${ENABLE_OPENWEBUI}" = "true" ]   && depends+="      - openwebui\n"
    [ "${ENABLE_LITELLM}" = "true" ]     && depends+="      - litellm\n"
    [ "${ENABLE_SIGNAL}" = "true" ]      && depends+="      - signal\n"
    [ "${ENABLE_GRAFANA}" = "true" ]     && depends+="      - grafana\n"
    [ "${ENABLE_AUTHENTIK}" = "true" ]   && depends+="      - authentik\n"
    echo -e "${depends}"
}
Each item must have exactly 6 spaces of indent to be valid YAML list items under depends_on:.

FIX 8 — Script 3: Fix n8n API auth header
File: scripts/3-configure-services.shReplace Basic auth with API key auth:
# Step 1: Get session token via login
N8N_API_KEY=$(curl -sf \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"admin@${DOMAIN}\",\"password\":\"${N8N_PASSWORD}\"}" \
    "http://localhost:${N8N_PORT:-5678}/api/v1/login" \
    | jq -r '.data.token')

if [ -z "${N8N_API_KEY}" ] || [ "${N8N_API_KEY}" = "null" ]; then
    log "WARN" "Could not authenticate to n8n — skipping auto-config"
    return 0
fi

# Step 2: Use token for all subsequent calls
curl -sf \
    -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    "http://localhost:${N8N_PORT:-5678}/api/v1/workflows"

FIX 9 — Script 3: Fix Flowise API endpoint
File: scripts/3-configure-services.shReplace the removed /api/v1/settings endpoint:
configure_flowise() {
    log "INFO" "Configuring Flowise..."

    local token
    token=$(curl -sf \
        -X POST \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"admin\",\"password\":\"${FLOWISE_PASSWORD}\"}" \
        "http://localhost:${FLOWISE_PORT:-3000}/api/v1/login" \
        | jq -r '.accessToken')

    if [ -z "${token}" ] || [ "${token}" = "null" ]; then
        log "WARN" "Could not authenticate to Flowise — skipping"
        return 0
    fi

    if [ "${ENABLE_OLLAMA}" = "true" ]; then
        curl -sf \
            -X POST \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            -d "{
                \"name\": \"Ollama Local\",
                \"credentialName\": \"ollamaApi\",
                \"plainDataObj\": {
                    \"ollamaUrl\": \"http://ollama:11434\"
                }
            }" \
            "http://localhost:${FLOWISE_PORT:-3000}/api/v1/credentials" \
            > /dev/null
        log "SUCCESS" "Flowise: Ollama credential created"
    fi
}

FIX 10 — Script 3: LiteLLM — wait for ready before posting config
File: scripts/3-configure-services.shAdd readiness wait at top of configure_litellm():
configure_litellm() {
    log "INFO" "Waiting for LiteLLM..."

    local waited=0
    until curl -sf \
        -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
        "http://localhost:${LITELLM_PORT:-4000}/health" > /dev/null 2>&1
    do
        [ "${waited}" -ge 60 ] && { log "ERROR" "LiteLLM timeout"; return 1; }
        sleep 5; waited=$((waited + 5)); printf "."
    done
    echo ""

    # Now post model config
    for model in llama3 mistral codellama nomic-embed-text; do
        curl -sf \
            -X POST \
            -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
            -H "Content-Type: application/json" \
            -d "{
                \"model_name\": \"${model}\",
                \"litellm_params\": {
                    \"model\": \"ollama/${model}\",
                    \"api_base\": \"http://ollama:11434\"
                }
            }" \
            "http://localhost:${LITELLM_PORT:-4000}/model/new" > /dev/null
        log "SUCCESS" "LiteLLM: model '${model}' registered"
    done
}

FIX 11 — Caddyfile: Fix Authentik forward auth headers
File: scripts/2-deploy-services.sh — inside generate_caddyfile()Replace the bare forward_auth block with:
forward_auth authentik:9000 {
    uri /outpost.goauthentik.io/auth/caddy
    copy_headers X-Authentik-Username X-Authentik-Groups \
                 X-Authentik-Email X-Authentik-Name \
                 X-Authentik-Uid X-Authentik-Jwt \
                 X-Authentik-Meta-Jwks X-Authentik-Meta-Outpost \
                 X-Authentik-Meta-Provider X-Authentik-Meta-App \
                 X-Authentik-Meta-Version
    header_up X-Original-URL {scheme}://{host}{uri}
    header_up X-Forwarded-Host {host}
}

FIX 12 — Caddyfile: Add WebSocket support to n8n proxy block
File: scripts/2-deploy-services.sh — inside generate_caddyfile()Replace n8n reverse_proxy block with:
handle /n8n/* {
    uri strip_prefix /n8n
    reverse_proxy n8n:5678 {
        header_up Host {upstream_hostport}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        transport http {
            read_buffer  4096
            write_buffer 4096
        }
    }
}

FIX 13 — Script 0: Guard docker compose down against missing file
File: scripts/0-teardown.sh (or wherever teardown lives)Wrap the down command:
COMPOSE_FILE="${DATA_ROOT}/compose/docker-compose.yml"

if [ ! -f "${COMPOSE_FILE}" ]; then
    log "WARN" "No compose file found at ${COMPOSE_FILE} — nothing to tear down"
    exit 0
fi

docker compose -f "${COMPOSE_FILE}" down --remove-orphans

🟡 IMPORTANT FIXES — DO THESE SECOND

FIX 14 — Script 1: GPU detection must write OLLAMA_GPU_LAYERS to .env
File: scripts/1-setup-system.shAfter GPU detection sets GPU_ENABLED, add:
if [ "${GPU_ENABLED}" = "true" ]; then
    OLLAMA_GPU_LAYERS=35
    OLLAMA_NUM_GPU=1
else
    OLLAMA_GPU_LAYERS=0
    OLLAMA_NUM_GPU=0
fi
In the .env heredoc, add:
OLLAMA_GPU_LAYERS=${OLLAMA_GPU_LAYERS}
OLLAMA_NUM_GPU=${OLLAMA_NUM_GPU}
In script 2, Ollama compose service, add:
environment:
  - OLLAMA_NUM_GPU=${OLLAMA_NUM_GPU:-0}
  - OLLAMA_GPU_LAYERS=${OLLAMA_GPU_LAYERS:-0}
  - OLLAMA_HOST=0.0.0.0

FIX 15 — Script 1: Validate domain input
File: scripts/1-setup-system.shReplace raw read for domain with:
prompt_domain() {
    while true; do
        read -p "  ➤ Domain name (e.g. ai.yourdomain.com): " DOMAIN
        DOMAIN="${DOMAIN,,}"
        DOMAIN="${DOMAIN#https://}"
        DOMAIN="${DOMAIN#http://}"
        DOMAIN="${DOMAIN%%/*}"
        if [[ "${DOMAIN}" =~ ^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?(\.[a-z]{2,})+$ ]]; then
            break
        fi
        echo "  ❌ '${DOMAIN}' is not a valid domain — try again"
    done
}
Keep goingFIX 16 — Script 1: Validate tenant ID input
File: scripts/1-setup-system.shReplace raw read for tenant ID with:
prompt_tenant_id() {
    while true; do
        read -p "  ➤ Tenant ID (letters, numbers, hyphens only): " TENANT_ID
        TENANT_ID="${TENANT_ID,,}"
        if [[ "${TENANT_ID}" =~ ^[a-z][a-z0-9\-]{2,29}$ ]]; then
            break
        fi
        echo "  ❌ Tenant ID must:"
        echo "     - Start with a letter"
        echo "     - Be 3-30 characters"
        echo "     - Contain only lowercase letters, numbers, hyphens"
        echo "     - No spaces, underscores, dots or special characters"
    done
}

FIX 17 — Script 1: EBS mount check must block if mount missing
File: scripts/1-setup-system.shReplace the warn-only check with:
check_ebs_mount() {
    log "INFO" "Checking EBS data volume..."

    if ! mountpoint -q "${DATA_ROOT}" 2>/dev/null; then
        echo ""
        echo -e "  ${RED}❌  ${DATA_ROOT} is not a mounted volume${NC}"
        echo ""
        echo "  This means all data will be stored on the root EBS volume."
        echo "  If the instance is replaced, ALL DATA WILL BE LOST."
        echo ""
        echo "  Recommended: attach and mount a separate EBS volume first."
        echo "  See README for EBS setup instructions."
        echo ""
        read -p "  ➤ Continue anyway? Data loss risk acknowledged [y/N]: " confirm
        case "${confirm}" in
            [yY]|[yY][eE][sS]) 
                log "WARN" "Continuing without dedicated EBS volume — data at risk"
                ;;
            *)
                log "INFO" "Exiting — mount your EBS volume then re-run"
                exit 1
                ;;
        esac
    else
        local device
        device=$(findmnt -n -o SOURCE "${DATA_ROOT}" 2>/dev/null)
        local size
        size=$(df -h "${DATA_ROOT}" | awk 'NR==2 {print $2}')
        log "SUCCESS" "EBS volume mounted at ${DATA_ROOT} (${device}, ${size})"
    fi
}

FIX 18 — Script 2: Qdrant — pass API key into container environment
File: scripts/2-deploy-services.shIn append_qdrant(), add to the environment block:
environment:
  - QDRANT__SERVICE__API_KEY=${QDRANT_API_KEY}
  - QDRANT__SERVICE__HOST=0.0.0.0
  - QDRANT__STORAGE__STORAGE_PATH=/qdrant/storage
Also add to the .env write in script 1:
QDRANT_API_KEY=$(openssl rand -hex 32)

FIX 19 — Script 2: AnythingLLM — add all required environment variables
File: scripts/2-deploy-services.shIn append_anythingllm(), replace the environment block with:
environment:
  - AUTH_TOKEN=${ANYTHINGLLM_AUTH_TOKEN}
  - JWT_SECRET=${ANYTHINGLLM_JWT_SECRET}
  - STORAGE_DIR=/app/server/storage
  - DB_TYPE=postgres
  - DB_CONNECTION_STRING=postgresql://${DB_USER}:${DB_PASSWORD}@postgres:5432/${TENANT_ID}_anythingllm
  - VECTOR_DB=qdrant
  - QDRANT_ENDPOINT=http://qdrant:6333
  - QDRANT_API_KEY=${QDRANT_API_KEY}
  - LITE_LLM_BASE_PATH=http://litellm:4000
  - LITE_LLM_MODEL_PREF=ollama/llama3
  - DISABLE_TELEMETRY=true
Add to script 1 .env generation:
ANYTHINGLLM_AUTH_TOKEN=$(openssl rand -hex 32)
ANYTHINGLLM_JWT_SECRET=$(openssl rand -hex 32)

FIX 20 — Script 2: Add pull_images() with per-image feedback
File: scripts/2-deploy-services.shAdd this full function before deploy_stack():
pull_images() {
    log "INFO" "Pulling Docker images — this may take a few minutes..."
    echo ""

    local images=()

    # Core — always pulled
    images+=(
        "postgres:16-alpine"
        "redis:7-alpine"
        "caddy:2-alpine"
    )

    # Conditional services
    [ "${ENABLE_OLLAMA}" = "true" ]       && images+=("ollama/ollama:latest")
    [ "${ENABLE_QDRANT}" = "true" ]       && images+=("qdrant/qdrant:latest")
    [ "${ENABLE_N8N}" = "true" ]          && images+=("n8nio/n8n:latest")
    [ "${ENABLE_FLOWISE}" = "true" ]      && images+=("flowiseai/flowise:latest")
    [ "${ENABLE_ANYTHINGLLM}" = "true" ]  && images+=("mintplexlabs/anythingllm:latest")
    [ "${ENABLE_OPENWEBUI}" = "true" ]    && images+=("ghcr.io/open-webui/open-webui:main")
    [ "${ENABLE_LITELLM}" = "true" ]      && images+=("ghcr.io/berriai/litellm:main-latest")
    [ "${ENABLE_GRAFANA}" = "true" ]      && images+=("grafana/grafana:latest")
    [ "${ENABLE_PROMETHEUS}" = "true" ]   && images+=("prom/prometheus:latest")
    [ "${ENABLE_AUTHENTIK}" = "true" ]    && images+=(
        "ghcr.io/goauthentik/server:latest"
        "ghcr.io/goauthentik/worker:latest"
    )
    [ "${ENABLE_TAILSCALE}" = "true" ]    && images+=("tailscale/tailscale:latest")

    local total="${#images[@]}"
    local current=0
    local failed=()

    for image in "${images[@]}"; do
        current=$((current + 1))
        printf "  [%2d/%2d]  %-55s " "${current}" "${total}" "${image}"

        if docker pull "${image}" > /dev/null 2>&1; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}✗ FAILED${NC}"
            failed+=("${image}")
        fi
    done

    echo ""

    if [ "${#failed[@]}" -gt 0 ]; then
        log "ERROR" "The following images could not be pulled:"
        for img in "${failed[@]}"; do
            echo "         - ${img}"
        done
        echo ""
        read -p "  ➤ Continue with deploy anyway? [y/N]: " confirm
        case "${confirm}" in
            [yY]|[yY][eE][sS]) log "WARN" "Continuing with missing images" ;;
            *) exit 1 ;;
        esac
    else
        log "SUCCESS" "All images pulled successfully"
    fi
}

FIX 21 — Script 2: Add wait_for_health() after deploy
File: scripts/2-deploy-services.shAdd this full function after deploy_stack():
wait_for_health() {
    log "INFO" "Waiting for services to become healthy..."
    echo ""

    declare -A checks
    [ "${ENABLE_N8N}" = "true" ]         && checks["n8n"]="http://localhost:${N8N_PORT:-5678}/healthz"
    [ "${ENABLE_FLOWISE}" = "true" ]     && checks["flowise"]="http://localhost:${FLOWISE_PORT:-3000}/api/v1/ping"
    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && checks["anythingllm"]="http://localhost:${ANYTHINGLLM_PORT:-3001}/api/ping"
    [ "${ENABLE_OPENWEBUI}" = "true" ]   && checks["openwebui"]="http://localhost:${OPENWEBUI_PORT:-8080}/health"
    [ "${ENABLE_LITELLM}" = "true" ]     && checks["litellm"]="http://localhost:${LITELLM_PORT:-4000}/health"
    [ "${ENABLE_GRAFANA}" = "true" ]     && checks["grafana"]="http://localhost:${GRAFANA_PORT:-3100}/api/health"

    local max_wait=120
    local interval=5

    for service in "${!checks[@]}"; do
        local url="${checks[$service]}"
        local waited=0

        printf "  ⏳  %-20s " "${service}..."

        until curl -sf "${url}" > /dev/null 2>&1; do
            if [ "${waited}" -ge "${max_wait}" ]; then
                echo -e "${RED}TIMEOUT (${max_wait}s)${NC}"
                log "WARN" "Check logs: docker logs ${service}"
                waited=-1
                break
            fi
            sleep "${interval}"
            waited=$((waited + interval))
            printf "."
        done

        [ "${waited}" -ge 0 ] && echo -e " ${GREEN}ready (${waited}s)${NC}"
    done

    echo ""
}

FIX 22 — Script 3: Add load_env() so all variables are defined
File: scripts/3-configure-services.shAdd at the top of the file, before any other function:
ENV_FILE="/opt/ai-platform/.env"

load_env() {
    if [ ! -f "${ENV_FILE}" ]; then
        echo "❌  .env file not found at ${ENV_FILE}"
        echo "    Run scripts 1 and 2 first."
        exit 1
    fi

    set -a
    # shellcheck source=/dev/null
    source "${ENV_FILE}"
    set +a

    # Validate critical vars are present
    local required=(
        TENANT_ID DOMAIN DB_USER DB_PASSWORD
        N8N_PASSWORD FLOWISE_PASSWORD LITELLM_MASTER_KEY
    )

    local missing=()
    for var in "${required[@]}"; do
        [ -z "${!var}" ] && missing+=("${var}")
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "❌  Missing required variables in .env:"
        for var in "${missing[@]}"; do
            echo "    - ${var}"
        done
        exit 1
    fi

    log "SUCCESS" "Environment loaded from ${ENV_FILE}"
}
Call load_env as the first line of main() in script 3.

FIX 23 — Script 3: Add --skip flags for partial re-runs
File: scripts/3-configure-services.shAdd argument parsing before main():
SKIP_N8N=false
SKIP_FLOWISE=false
SKIP_LITELLM=false
SKIP_ANYTHINGLLM=false
SKIP_GRAFANA=false

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --skip-n8n)          SKIP_N8N=true ;;
            --skip-flowise)      SKIP_FLOWISE=true ;;
            --skip-litellm)      SKIP_LITELLM=true ;;
            --skip-anythingllm)  SKIP_ANYTHINGLLM=true ;;
            --skip-grafana)      SKIP_GRAFANA=true ;;
            --help|-h)
                echo "Usage: sudo bash scripts/3-configure-services.sh [OPTIONS]"
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
Wrap each configure call in main() with its skip flag:
[ "${SKIP_N8N}" = "false" ]         && configure_n8n
[ "${SKIP_FLOWISE}" = "false" ]     && configure_flowise
[ "${SKIP_LITELLM}" = "false" ]     && configure_litellm
[ "${SKIP_ANYTHINGLLM}" = "false" ] && configure_anythingllm
[ "${SKIP_GRAFANA}" = "false" ]     && configure_grafana

FIX 24 — Caddyfile: Add TLS email for ACME
File: scripts/2-deploy-services.sh — inside generate_caddyfile()Add global options block at the top of the generated Caddyfile:
{
    email ${ADMIN_EMAIL}
    acme_ca https://acme-v02.api.letsencrypt.org/directory
    acme_ca_root /etc/ssl/certs/ca-certificates.crt
}
Add ADMIN_EMAIL to script 1 prompts:
prompt_admin_email() {
    while true; do
        read -p "  ➤ Admin email (for TLS certificates): " ADMIN_EMAIL
        if [[ "${ADMIN_EMAIL}" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
            break
        fi
        echo "  ❌ Invalid email address — try again"
    done
}

🟢 POLISH FIXES — DO THESE LAST

FIX 25 — Script 1: Restore full UI helper functions
File: scripts/1-setup-system.shAdd this complete block at the top of the file, after the shebang:
# ─── Colour codes ────────────────────────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ─── UI helpers ──────────────────────────────────────────────────────────────
print_header() {
    clear
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}          AI Platform Setup — Multi-Tenant Edition            ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}${DIM}                    Setup & Configuration                     ${NC}${CYAN}║${NC}"
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

log() {
    local level="${1}" message="${2}"
    case "${level}" in
        SUCCESS) echo -e "  ${GREEN}✅  ${message}${NC}" ;;
        INFO)    echo -e "  ${CYAN}ℹ️   ${message}${NC}" ;;
        WARN)    echo -e "  ${YELLOW}⚠️   ${message}${NC}" ;;
        ERROR)   echo -e "  ${RED}❌  ${message}${NC}" ;;
    esac
}

FIX 26 — Script 1: Add category groupings to service selection menu
File: scripts/1-setup-system.shReplace the flat service selection with:
select_services() {
    print_step "3" "7" "Select Services to Deploy"

    echo -e "  ${BOLD}── AI & LLM ──────────────────────────────────────────────${NC}"
    echo ""
    prompt_yes_no "  Deploy Ollama (local LLM runner)?"          ENABLE_OLLAMA         "true"
    prompt_yes_no "  Deploy LiteLLM (OpenAI-compatible proxy)?"  ENABLE_LITELLM        "true"
    prompt_yes_no "  Deploy AnythingLLM (document chat)?"        ENABLE_ANYTHINGLLM    "true"
    prompt_yes_no "  Deploy Open WebUI (Ollama chat interface)?"  ENABLE_OPENWEBUI      "true"
    prompt_yes_no "  Deploy Qdrant (vector database)?"           ENABLE_QDRANT         "true"
    echo ""

    echo -e "  ${BOLD}── Automation & Workflows ────────────────────────────────${NC}"
    echo ""
    prompt_yes_no "  Deploy n8n (workflow automation)?"          ENABLE_N8N            "true"
    prompt_yes_no "  Deploy Flowise (visual AI pipelines)?"      ENABLE_FLOWISE        "true"
    echo ""

    echo -e "  ${BOLD}── Observability ─────────────────────────────────────────${NC}"
    echo ""
    prompt_yes_no "  Deploy Grafana (dashboards)?"               ENABLE_GRAFANA        "false"
    prompt_yes_no "  Deploy Prometheus (metrics)?"               ENABLE_PROMETHEUS     "false"
    echo ""

    echo -e "  ${BOLD}── Access & Security ─────────────────────────────────────${NC}"
    echo ""
    prompt_yes_no "  Deploy Authentik (SSO / identity)?"         ENABLE_AUTHENTIK      "false"
    prompt_yes_no "  Deploy Tailscale (private network access)?" ENABLE_TAILSCALE      "false"
    echo ""
}

prompt_yes_no() {
    local question="${1}"
    local var="${2}"
    local default="${3}"

    local hint
    [ "${default}" = "true" ] && hint="[Y/n]" || hint="[y/N]"

    read -p "  ${question} ${hint}: " answer

    case "${answer}" in
        [yY]|[yY][eE][sS]) eval "${var}=true"  ;;
        [nN]|[nN][oO])     eval "${var}=false" ;;
        "")                 eval "${var}=${default}" ;;
        *)
            echo "  ⚠️  Invalid — defaulting to ${default}"
            eval "${var}=${default}"
            ;;
    esac
}

FIX 27 — Script 2: Format service URL output as a proper table
File: scripts/2-deploy-services.shReplace the plain-text URL output with:
output_service_urls() {
    print_section "🚀  Deployment Complete"

    echo -e "  ${BOLD}Service URLs${NC}"
    echo ""
    echo -e "  ${DIM}  Service          URL                                    Credentials${NC}"
    echo -e "  ${DIM}  ─────────────────────────────────────────────────────────────────${NC}"

    [ "${ENABLE_N8N}" = "true" ] && \
        printf "  ${GREEN}✓${NC}  %-16s %-40s %s\n" \
            "n8n" \
            "https://${DOMAIN}/n8n" \
            "admin / ${N8N_PASSWORD}"

    [ "${ENABLE_FLOWISE}" = "true" ] && \
        printf "  ${GREEN}✓${NC}  %-16s %-40s %s\n" \
            "Flowise" \
            "https://${DOMAIN}/flowise" \
            "admin / ${FLOWISE_PASSWORD}"

    [ "${ENABLE_ANYTHINGLLM}" = "true" ] && \
        printf "  ${GREEN}✓${NC}  %-16s %-40s %s\n" \
            "AnythingLLM" \
            "https://${DOMAIN}/anythingllm" \
            "token in .env"

    [ "${ENABLE_OPENWEBUI}" = "true" ] && \
        printf "  ${GREEN}✓${NC}  %-16s %-40s %s\n" \
            "Open WebUI" \
            "https://${DOMAIN}/openwebui" \
            "register on first visit"

    [ "${ENABLE_LITELLM}" = "true" ] && \
        printf "  ${GREEN}✓${NC}  %-16s %-40s %s\n" \
            "LiteLLM" \
            "https://${DOMAIN}/litellm" \
            "key: ${LITELLM_MASTER_KEY}"

    [ "${ENABLE_GRAFANA}" = "true" ] && \
        printf "  ${GREEN}✓${NC}  %-16s %-40s %s\n" \
            "Grafana" \
            "https://${DOMAIN}/grafana" \
            "admin / ${GRAFANA_PASSWORD}"

    [ "${ENABLE_AUTHENTIK}" = "true" ] && \
        printf "  ${GREEN}✓${NC}  %-16s %-40s %s\n" \
            "Authentik" \
            "https://${DOMAIN}/authentik" \
            "see .env for bootstrap creds"

    echo ""
    echo -e "  ${DIM}  ─────────────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "  ${BOLD}Credentials saved to:${NC}  ${DATA_ROOT}/.env"
    echo -e "  ${BOLD}Logs:${NC}                  docker compose -f ${COMPOSE_FILE} logs -f"
    echo -e "  ${BOLD}Status:${NC}                docker compose -f ${COMPOSE_FILE} ps"
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}${BOLD}  ✅  Setup complete — your AI platform is live              ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

FIX 28 — Script 3: Add step counters and success box to configure script
File: scripts/3-configure-services.shReplace the main() function with:
main() {
    parse_args "$@"
    load_env
    print_header

    local step=0
    local total=0

    # Count active steps
    [ "${SKIP_N8N}" = "false" ]         && [ "${ENABLE_N8N}" = "true" ]         && total=$((total+1))
    [ "${SKIP_FLOWISE}" = "false" ]     && [ "${ENABLE_FLOWISE}" = "true" ]     && total=$((total+1))
    [ "${SKIP_LITELLM}" = "false" ]     && [ "${ENABLE_LITELLM}" = "true" ]     && total=$((total+1))
    [ "${SKIP_ANYTHINGLLM}" = "false" ] && [ "${ENABLE_ANYTHINGLLM}" = "true" ] && total=$((total+1))
    [ "${SKIP_GRAFANA}" = "false" ]     && [ "${ENABLE_GRAFANA}" = "true" ]     && total=$((total+1))

    if [ "${SKIP_N8N}" = "false" ] && [ "${ENABLE_N8N}" = "true" ]; then
        step=$((step+1))
        print_step "${step}" "${total}" "Configuring n8n"
        configure_n8n
    fi

    if [ "${SKIP_FLOWISE}" = "false" ] && [ "${ENABLE_FLOWISE}" = "true" ]; then
        step=$((step+1))
        print_step "${step}" "${total}" "Configuring Flowise"
        configure_flowise
    fi

    if [ "${SKIP_LITELLM}" = "false" ] && [ "${ENABLE_LITELLM}" = "true" ]; then
        step=$((step+1))
        print_step "${step}" "${total}" "Registering LiteLLM models"
        configure_litellm
    fi

    if [ "${SKIP_ANYTHINGLLM}" = "false" ] && [ "${ENABLE_ANYTHINGLLM}" = "true" ]; then
        step=$((step+1))
        print_step "${step}" "${total}" "Configuring AnythingLLM"
        configure_anythingllm
    fi

    if [ "${SKIP_GRAFANA}" = "false" ] && [ "${ENABLE_GRAFANA}" = "true" ]; then
        step=$((step+1))
        print_step "${step}" "${total}" "Setting up Grafana dashboards"
        configure_grafana
    fi

    print_divider
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}${BOLD}  ✅  All services configured successfully                   ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

main "$@"

FIX 29 — README: Add troubleshooting section
File: README.mdAppend this section at the bottom:
## Troubleshooting

### A service shows as unhealthy after deploy

```bash
# Check container logs
docker logs <service-name> --tail 50

# Check all service statuses
docker compose -f /opt/ai-platform/compose/docker-compose.yml ps

# Restart a single service
docker compose -f /opt/ai-platform/compose/docker-compose.yml restart <service-name>
```

### Caddy fails to get TLS certificate

- Confirm your domain's DNS A record points to this server's public IP
- Confirm port 80 and 443 are open in your EC2 security group
- Check Caddy logs: `docker logs caddy --tail 50`

### Script 3 fails with "cannot authenticate"

Services may still be starting. Wait 60 seconds then re-run:

```bash
sudo bash scripts/3-configure-services.sh --skip-n8n --skip-flowise
```

Use `--skip-*` flags to re-run only the services that failed.

### Ollama models not loading

```bash
# Pull a model manually
docker exec ollama ollama pull llama3

# List available models
docker exec ollama ollama list
```

### Complete teardown and rebuild

```bash
# Remove all containers, volumes and config
sudo bash scripts/0-teardown.sh

# Re-run setup from scratch
sudo bash scripts/1-setup-system.sh
sudo bash scripts/2-deploy-services.sh
sudo bash scripts/3-configure-services.sh
```

### Environment variables

All generated credentials are stored at:

```
/opt/ai-platform/.env
```

Do not commit this file to version control. It contains all passwords,
API keys and secrets for your deployment.

FINAL CHECKLIST FOR WINDSURF
Before marking this task complete, verify:

 FIX 1–3 — Script 1 root check, UID validation, Tailscale key prompt all present
 FIX 4 — Postgres heredoc uses 'EOF' not EOF
 FIX 5 — Signal port bound to 127.0.0.1
 FIX 6 — main() order is: preflight → generate → pull → deploy → health → urls
 FIX 7 — Caddy depends_on has exactly 6 spaces per list item
 FIX 8 — n8n uses X-N8N-API-KEY header, not Basic auth
 FIX 9 — Flowise uses /api/v1/login then /api/v1/credentials
 FIX 10 — LiteLLM config waits for health before posting
 FIX 11 — Authentik forward auth copies all required headers including X-Forwarded-Host
 FIX 12 — n8n Caddy block has WebSocket-compatible proxy config
 FIX 13 — Teardown guards against missing compose file
 FIX 14 — OLLAMA_GPU_LAYERS written to .env and passed to container
 FIX 15–16 — Domain and tenant ID both validated with regex loops
 FIX 17 — EBS check prompts user to confirm rather than silently continuing
 FIX 18 — Qdrant API key generated in script 1 and passed in script 2
 FIX 19 — AnythingLLM has auth token, JWT secret, storage dir, DB and vector config
 FIX 20 — pull_images() runs before deploy with per-image feedback and failure handling
 FIX 21 — wait_for_health() runs after deploy and shows per-service wait time
 FIX 22 — load_env() in script 3 sources .env and validates required vars
 FIX 23 — --skip-* flags work and are documented in --help
 FIX 24 — Caddyfile global block includes email for ACME
 FIX 25 — All UI colour and helper functions restored in script 1
 FIX 26 — Service selection grouped into AI, Automation, Observability, Security
 FIX 27 — URL output is a formatted table with credentials column
 FIX 28 — Script 3 shows step counters and prints success box on completion
 FIX 29 — README troubleshooting section covers all common failure modes