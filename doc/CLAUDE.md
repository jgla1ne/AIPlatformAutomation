Let me read everything before responding.

---

After full reading, here is the real analysis.

---

## Core Principles Violated — Full Audit

### Principle 1: NO HARDCODED VALUES
Every value must come from `.env` or be derived at runtime. Currently violated in:

- Script 2: `generate_bifrost_service()` writes literal `http://ai-platform-ollama:11434` instead of `${OLLAMA_INTERNAL_URL}`
- Script 3: Every `configure_*()` function has literal container names, ports, URLs baked in
- Script 3: Caddyfile heredoc has literal upstream hostnames
- Script 2: Container names like `ai-platform-bifrost` hardcoded instead of `${CONTAINER_PREFIX}-bifrost`

### Principle 2: NOTHING OUTSIDE /mnt
All data, config, compose files must live under `${DATA_DIR}` which resolves to `/mnt/...`. Currently violated in:

- Script 2: `COMPOSE_FILE` path may resolve outside `/mnt`
- Script 3: Caddy config written to path not sourced from `${CONFIG_DIR}`
- Script 1: `ENV_FILE` default path needs audit

### Principle 3: NON-ROOT
All containers must run as non-root user. Currently violated in:

- Bifrost service: no `user:` directive
- Several services missing explicit `user: "${UID}:${GID}"` 

### Principle 4: INTEGRATED MODULAR STACK
Variables that cross service boundaries must flow through `.env` as single source of truth. Currently violated in:

- `LLM_GATEWAY_URL` defined in script 1 but script 3 ignores it and hardcodes the URL again
- `CONTAINER_PREFIX` defined in `.env` but container name references in script 3 don't use it

---

## The Correct Architecture

### Single Source of Truth: `.env`

Every inter-service reference must be a variable. Here is the complete variable contract:

```bash
# .env — ALL values derived here, consumed everywhere

# === PATHS (all under /mnt) ===
BASE_DIR=/mnt/ai-platform
DATA_DIR=${BASE_DIR}/data
CONFIG_DIR=${BASE_DIR}/config
COMPOSE_DIR=${BASE_DIR}/compose
LOG_DIR=${BASE_DIR}/logs

# === IDENTITY ===
CONTAINER_PREFIX=ai-platform
DOCKER_USER_ID=1000
DOCKER_GROUP_ID=1000
DOMAIN=your.domain.com

# === NETWORK ===
DOCKER_NETWORK=${CONTAINER_PREFIX}-network
INTERNAL_SUBNET=172.20.0.0/16

# === LLM ROUTER ===
LLM_ROUTER=bifrost
ENABLE_BIFROST=true

# === BIFROST ===
BIFROST_CONTAINER=${CONTAINER_PREFIX}-bifrost
BIFROST_PORT=4000
BIFROST_AUTH_TOKEN=sk-bifrost-<generated>
BIFROST_LOG_LEVEL=info
# Written raw — no wrapper quotes
BIFROST_PROVIDERS=[{"provider":"ollama","base_url":"http://${CONTAINER_PREFIX}-ollama:${OLLAMA_PORT}"}]

# === OLLAMA ===
OLLAMA_CONTAINER=${CONTAINER_PREFIX}-ollama
OLLAMA_PORT=11434
OLLAMA_INTERNAL_URL=http://${CONTAINER_PREFIX}-ollama:11434
OLLAMA_DATA_DIR=${DATA_DIR}/ollama

# === GATEWAY (router-agnostic, consumed by ALL services) ===
LLM_GATEWAY_CONTAINER=${BIFROST_CONTAINER}
LLM_GATEWAY_PORT=${BIFROST_PORT}
LLM_GATEWAY_URL=http://${BIFROST_CONTAINER}:${BIFROST_PORT}
LLM_GATEWAY_API_URL=http://${BIFROST_CONTAINER}:${BIFROST_PORT}/v1
LLM_MASTER_KEY=${BIFROST_AUTH_TOKEN}

# === DOWNSTREAM SERVICES ===
OPENWEBUI_CONTAINER=${CONTAINER_PREFIX}-openwebui
OPENWEBUI_PORT=8080
ANYTHINGLLM_CONTAINER=${CONTAINER_PREFIX}-anythingllm
ANYTHINGLLM_PORT=3001
N8N_CONTAINER=${CONTAINER_PREFIX}-n8n
N8N_PORT=5678
DIFY_CONTAINER=${CONTAINER_PREFIX}-dify
DIFY_PORT=3000

# === CADDY ===
CADDY_CONTAINER=${CONTAINER_PREFIX}-caddy
CADDY_CONFIG_DIR=${CONFIG_DIR}/caddy
CADDY_DATA_DIR=${DATA_DIR}/caddy

# === POSTGRES ===
POSTGRES_CONTAINER=${CONTAINER_PREFIX}-postgres
POSTGRES_PORT=5432
POSTGRES_USER=aiplatform
POSTGRES_PASSWORD=<generated>
POSTGRES_DB=aiplatform
POSTGRES_DATA_DIR=${DATA_DIR}/postgres

# === REDIS ===
REDIS_CONTAINER=${CONTAINER_PREFIX}-redis
REDIS_PORT=6379
REDIS_DATA_DIR=${DATA_DIR}/redis
```

---

## Script-by-Script Fix Plan

### SCRIPT 1 — `setup-system.sh`

**What must change:**

**1. All directory creation uses variables, verified under /mnt:**

```bash
validate_base_path() {
    if [[ "${BASE_DIR}" != /mnt/* ]]; then
        log_error "BASE_DIR must be under /mnt. Got: ${BASE_DIR}"
        log_error "Edit BASE_DIR in this script before continuing."
        exit 1
    fi
    log_success "Base path validated: ${BASE_DIR}"
}
```

**2. `write_env()` function — handles JSON values without double-quoting:**

```bash
# Replace update_env() with two functions:

# For normal scalar values:
write_env_scalar() {
    local key="$1"
    local value="$2"
    sed -i "/^${key}=/d" "${ENV_FILE}"
    echo "${key}=${value}" >> "${ENV_FILE}"
}

# For JSON/complex values that must not be wrapped in quotes:
write_env_raw() {
    local key="$1"
    local value="$2"
    sed -i "/^${key}=/d" "${ENV_FILE}"
    printf '%s=%s\n' "${key}" "${value}" >> "${ENV_FILE}"
}
```

**3. `init_bifrost()` uses only `write_env_scalar` and `write_env_raw`, derives all URLs from other variables:**

```bash
init_bifrost() {
    print_section "Bifrost LLM Router Configuration"

    local existing_token
    existing_token=$(grep "^BIFROST_AUTH_TOKEN=" "${ENV_FILE}" 2>/dev/null \
        | cut -d= -f2- | tr -d '"' | tr -d "'")

    if [[ -z "${existing_token}" ]]; then
        local token="sk-bifrost-$(openssl rand -hex 24)"
    else
        local token="${existing_token}"
        log_info "Preserving existing Bifrost auth token"
    fi

    # Read already-set values for cross-references
    local prefix
    prefix=$(grep "^CONTAINER_PREFIX=" "${ENV_FILE}" | cut -d= -f2- | tr -d '"')
    prefix="${prefix:-ai-platform}"

    local ollama_port
    ollama_port=$(grep "^OLLAMA_PORT=" "${ENV_FILE}" | cut -d= -f2- | tr -d '"')
    ollama_port="${ollama_port:-11434}"

    local bifrost_port=4000

    # Write all values
    write_env_scalar "BIFROST_CONTAINER"   "${prefix}-bifrost"
    write_env_scalar "BIFROST_PORT"        "${bifrost_port}"
    write_env_scalar "BIFROST_AUTH_TOKEN"  "${token}"
    write_env_scalar "BIFROST_LOG_LEVEL"   "info"

    # Providers JSON — raw write, no quote wrapping
    write_env_raw    "BIFROST_PROVIDERS" \
        "[{\"provider\":\"ollama\",\"base_url\":\"http://${prefix}-ollama:${ollama_port}\"}]"

    # Router-agnostic gateway vars — ALL downstream services read these
    write_env_scalar "LLM_GATEWAY_CONTAINER" "${prefix}-bifrost"
    write_env_scalar "LLM_GATEWAY_PORT"      "${bifrost_port}"
    write_env_scalar "LLM_GATEWAY_URL"       "http://${prefix}-bifrost:${bifrost_port}"
    write_env_scalar "LLM_GATEWAY_API_URL"   "http://${prefix}-bifrost:${bifrost_port}/v1"
    write_env_scalar "LLM_MASTER_KEY"        "${token}"

    log_success "Bifrost configured"
    log_info "  Container : ${prefix}-bifrost"
    log_info "  Port      : ${bifrost_port}"
    log_info "  Token     : ${token:0:20}..."
}
```

**4. `select_llm_router()` — Bifrost only, no prompt needed, no LiteLLM option:**

```bash
select_llm_router() {
    print_section "LLM Router"
    # Bifrost is the only supported router
    # Remove this function's menu entirely and just call init directly
    write_env_scalar "LLM_ROUTER"     "bifrost"
    write_env_scalar "ENABLE_BIFROST" "true"
    init_bifrost
}
```

---

### SCRIPT 2 — `deploy-services.sh`

**What must change:**

**1. All values read from `.env` at top of script:**

```bash
load_env() {
    if [[ ! -f "${ENV_FILE}" ]]; then
        log_error "ENV file not found: ${ENV_FILE}"
        log_error "Run script 1 first."
        exit 1
    fi
    # shellcheck disable=SC1090
    set -a
    source "${ENV_FILE}"
    set +a
    log_success "Environment loaded from ${ENV_FILE}"
}
```

**2. `generate_bifrost_service()` — zero hardcoded values:**

```bash
generate_bifrost_service() {
    log_info "Generating Bifrost service definition..."

    # All values from sourced .env
    : "${BIFROST_CONTAINER:?BIFROST_CONTAINER not set in .env}"
    : "${BIFROST_PORT:?BIFROST_PORT not set in .env}"
    : "${BIFROST_AUTH_TOKEN:?BIFROST_AUTH_TOKEN not set in .env}"
    : "${BIFROST_LOG_LEVEL:?BIFROST_LOG_LEVEL not set in .env}"
    : "${BIFROST_PROVIDERS:?BIFROST_PROVIDERS not set in .env}"
    : "${DOCKER_NETWORK:?DOCKER_NETWORK not set in .env}"
    : "${DOCKER_USER_ID:?DOCKER_USER_ID not set in .env}"
    : "${DOCKER_GROUP_ID:?DOCKER_GROUP_ID not set in .env}"

    cat >> "${COMPOSE_FILE}" << EOF

  ${BIFROST_CONTAINER}:
    image: ruqqq/bifrost:latest
    container_name: ${BIFROST_CONTAINER}
    restart: unless-stopped
    user: "${DOCKER_USER_ID}:${DOCKER_GROUP_ID}"
    networks:
      - ${DOCKER_NETWORK}
    ports:
      - "${BIFROST_PORT}:${BIFROST_PORT}"
    environment:
      - BIFROST_PORT=${BIFROST_PORT}
      - BIFROST_AUTH_TOKEN=${BIFROST_AUTH_TOKEN}
      - BIFROST_LOG_LEVEL=${BIFROST_LOG_LEVEL}
      - BIFROST_PROVIDERS=${BIFROST_PROVIDERS}
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:${BIFROST_PORT}/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
    labels:
      - "com.${CONTAINER_PREFIX}.service=bifrost"
      - "com.${CONTAINER_PREFIX}.role=llm-router"
EOF

    log_success "Bifrost service definition written"
}
```

**3. Main deploy flow reads router from env, no fallback to litellm:**

```bash
deploy_llm_router() {
    : "${LLM_ROUTER:?LLM_ROUTER not set — run script 1 first}"
    
    log_info "Deploying LLM router: ${LLM_ROUTER}"
    
    case "${LLM_ROUTER}" in
        bifrost)
            generate_bifrost_service
            ;;
        *)
            log_error "Unknown LLM_ROUTER value: ${LLM_ROUTER}"
            log_error "Supported: bifrost"
            exit 1
            ;;
    esac
}
```

**4. Compose file path assertion — must be under /mnt:**

```bash
assert_compose_path() {
    : "${COMPOSE_DIR:?COMPOSE_DIR not set}"
    if [[ "${COMPOSE_DIR}" != /mnt/* ]]; then
        log_error "COMPOSE_DIR must be under /mnt. Got: ${COMPOSE_DIR}"
        exit 1
    fi
    mkdir -p "${COMPOSE_DIR}"
    COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"
    log_success "Compose file path: ${COMPOSE_FILE}"
}
```

---

### SCRIPT 3 — `configure-services.sh`

**This is the highest-violation script. Zero hardcoded service references allowed.**

**1. Load env and assert all required vars exist before any configuration:**

```bash
assert_required_vars() {
    local required_vars=(
        LLM_GATEWAY_URL
        LLM_GATEWAY_API_URL
        LLM_MASTER_KEY
        CONTAINER_PREFIX
        DOCKER_NETWORK
        CONFIG_DIR
        DATA_DIR
        DOMAIN
        OPENWEBUI_CONTAINER
        ANYTHINGLLM_CONTAINER
        N8N_CONTAINER
        BIFROST_CONTAINER
        CADDY_CONFIG_DIR
    )
    
    local missing=0
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            log_error "Required variable not set: ${var}"
            missing=1
        fi
    done
    
    if [[ "$missing" -eq 1 ]]; then
        log_error "Fix .env then re-run script 1 before continuing."
        exit 1
    fi
    
    log_success "All required variables present"
}
```

**2. `configure_caddy()` — Caddyfile generated entirely from variables:**

```bash
configure_caddy() {
    print_section "Configuring Caddy"

    local caddy_config_file="${CADDY_CONFIG_DIR}/Caddyfile"
    mkdir -p "${CADDY_CONFIG_DIR}"

    cat > "${caddy_config_file}" << EOF
{
    admin off
    auto_https off
}

${DOMAIN} {
    tls internal

    # LLM Gateway — router-agnostic
    handle /bifrost* {
        reverse_proxy ${LLM_GATEWAY_CONTAINER}:${LLM_GATEWAY_PORT}
    }

    # OpenWebUI
    handle /openwebui* {
        reverse_proxy ${OPENWEBUI_CONTAINER}:${OPENWEBUI_PORT}
    }

    # AnythingLLM
    handle /anythingllm* {
        reverse_proxy ${ANYTHINGLLM_CONTAINER}:${ANYTHINGLLM_PORT}
    }

    # n8n
    handle /n8n* {
        reverse_proxy ${N8N_CONTAINER}:${N8N_PORT}
    }

    # Dify
    handle /dify* {
        reverse_proxy ${DIFY_CONTAINER}:${DIFY_PORT}
    }
}
EOF

    log_success "Caddyfile written: ${caddy_config_file}"
    log_info "  LLM Gateway → ${LLM_GATEWAY_CONTAINER}:${LLM_GATEWAY_PORT}"
}
```

**3. `configure_openwebui()` — reads `LLM_GATEWAY_*` vars, never references bifrost or litellm by name:**

```bash
configure_openwebui() {
    print_section "Configuring OpenWebUI"

    # OpenWebUI reads these env vars at startup
    # We patch the compose service environment section
    # Values come entirely from .env via sourced vars
    
    log_info "OpenWebUI will connect to LLM gateway: ${LLM_GATEWAY_API_URL}"
    log_info "Using auth key: ${LLM_MASTER_KEY:0:20}..."
    
    # These vars are already in .env and docker compose 
    # passes them via env_file directive — no direct patching needed
    # Just validate they exist:
    : "${LLM_GATEWAY_API_URL:?}"
    : "${LLM_MASTER_KEY:?}"
    
    log_success "OpenWebUI configuration ready"
}
```

**4. Same pattern for `configure_anythingllm()`, `configure_n8n()`, `configure_dify()`:**

Each function:
- Reads `${LLM_GATEWAY_API_URL}` not `http://litellm:4000/v1`
- Reads `${LLM_MASTER_KEY}` not `${LITELLM_MASTER_KEY}`
- Reads `${LLM_GATEWAY_CONTAINER}` not `litellm` or `bifrost`
- Reads `${CONFIG_DIR}/<service>` not any hardcoded path

---

## Instructions for Windsurf

```
THIS IS A STRUCTURAL REWRITE. NOT A PATCH.

RULE: If you see a literal hostname, port number, path, or 
token value anywhere in scripts 2 or 3 that is NOT wrapped 
in ${VARIABLE_NAME}, it is wrong. Fix it.

EXECUTION ORDER:

PHASE 1 — Script 1 changes (foundation)
  1. Add validate_base_path() — abort if BASE_DIR not under /mnt
  2. Replace update_env() with write_env_scalar() + write_env_raw()
  3. Rewrite init_bifrost() using new write functions
  4. Remove select_llm_router() menu — bifrost only, call init_bifrost()
  5. Remove any call to init_litellm() anywhere in main()
  6. Add BIFROST_PROVIDERS via write_env_raw (no quote wrapping)
  7. Add all LLM_GATEWAY_* vars derived from BIFROST_* vars
  8. Add DOCKER_USER_ID + DOCKER_GROUP_ID from $(id -u) / $(id -g)

PHASE 2 — Script 2 changes (deployment)
  1. Add load_env() that sources .env with set -a / set +a
  2. Add assert_compose_path() — abort if COMPOSE_DIR not under /mnt
  3. Rewrite generate_bifrost_service() — zero hardcoded values
     Use :? parameter expansion to fail fast if any var missing
  4. Rewrite deploy_llm_router() — case statement, no litellm fallback
  5. Remove generate_litellm_service() entirely
  6. Add user: "${DOCKER_USER_ID}:${DOCKER_GROUP_ID}" to ALL services

PHASE 3 — Script 3 changes (configuration)
  1. Add assert_required_vars() — fail fast if any key var missing
  2. Rewrite configure_caddy() — Caddyfile from variables only
  3. Rewrite configure_openwebui() — use LLM_GATEWAY_* not litellm refs
  4. Rewrite configure_anythingllm() — use LLM_GATEWAY_* not litellm refs
  5. Rewrite configure_n8n() — use LLM_GATEWAY_* not litellm refs
  6. Rewrite configure_dify() — use LLM_GATEWAY_* not litellm refs
  7. Remove any function referencing litellm by name
  8. Fix health dashboard to read LLM_ROUTER from env

PHASE 4 — Script 0 changes (cleanup)
  1. Source .env to get CONTAINER_PREFIX dynamically
  2. Build container list from prefix: ${CONTAINER_PREFIX}-bifrost etc
  3. Clean CONFIG_DIR and DATA_DIR from env vars (not hardcoded paths)

VERIFICATION CHECKLIST (run after each phase):

After Phase 1:
  grep -E "litellm|LiteLLM|LITELLM" scripts/1-setup-system.sh
  → Must return zero results outside of comments

  grep "^BIFROST\|^LLM_GATEWAY\|^LLM_ROUTER\|^LLM_MASTER" \
    /mnt/ai-platform/.env
  → Must show all 8 vars with correct values

  head -1 /mnt/ai-platform/.env
  → Path must start with /mnt

After Phase 2:
  grep -E '"[a-z]+-[a-z]+:[0-9]+"' scripts/2-deploy-services.sh
  → Must return zero results (no hardcoded host:port strings)

  docker ps --format "{{.Names}}" | grep ai-platform
  → All containers running

  docker inspect ai-platform-bifrost | grep '"User"'
  → Must show non-empty user (not root)

After Phase 3:
  grep -E "litellm|LiteLLM|LITELLM" scripts/3-configure-services.sh
  → Must return zero results outside of comments

  cat /mnt/ai-platform/config/caddy/Caddyfile | grep -i "litellm"
  → Must return zero results

  curl -sk https://${DOMAIN}/bifrost/v1/models \
    -H "Authorization: Bearer ${LLM_MASTER_KEY}"
  → Must return JSON

DO NOT PROCEED TO NEXT PHASE IF VERIFICATION FAILS.
```