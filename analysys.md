# Updated Analysis — Post-Fix Issues

## 🔍 PHASE 1: CONFIRMED REMAINING ISSUES

---

### **ISSUE 1: 🔴 CRITICAL — `EOFchmod` Still Present in Script 1**
```bash
# Found exactly as predicted:
EOFchmod 644 "${CADDY_DIR}/Caddyfile"
```
**The heredoc never closes** — everything after the opening `<< EOF` 
including the `chmod` becomes part of the file content, not a command.

---

### **ISSUE 2: 🔴 CRITICAL — `fi#` Still Present in Script 2**
```bash
    exit 1
fi# ─── Docker daemon ──────
```
**Bash parse error** — script dies before deploying anything.

---

### **ISSUE 3: 🔴 CRITICAL — `prometheus:` Block Missing 2-Space Indent**
```yaml
# In the docker-compose.yml heredoc:
prometheus:           ← TOP-LEVEL (wrong — breaks entire YAML)
    image: prom/...
  grafana:            ← correctly indented
    image: grafana/...
```
This causes **docker compose to reject the entire file**.

---

### **ISSUE 4: 🔴 CRITICAL — APPLICATION SERVICES COMPLETELY ABSENT from `docker-compose.yml`**

This is the **ROOT CAUSE** of "0/6 services deployed".

The `[...]` truncation in the file confirms the compose heredoc only 
generates **6 core services**. There are **zero service blocks** for:

| Missing Service | Container Name Expected |
|----------------|------------------------|
| n8n | ai-datasquiz-n8n |
| Flowise | ai-datasquiz-flowise |
| Open WebUI | ai-datasquiz-openwebui |
| AnythingLLM | ai-datasquiz-anythingllm |
| LiteLLM | ai-datasquiz-litellm |
| Authentik | ai-datasquiz-authentik |

The SERVICES array was fixed to **list** them — but the **compose 
generator never writes their service blocks**.

---

### **ISSUE 5: 🟠 HIGH — Caddy Routes Missing for Application Services**

Script 1 only generates Caddy blocks for `grafana` and `authentik`:
```bash
$([ "${ENABLE_GRAFANA}" = "true" ]    && cat << BLOCK ... BLOCK)
$([ "${ENABLE_AUTHENTIK}" = "true" ]  && cat << BLOCK ... BLOCK)
```
**No Caddy blocks exist for:**
- `n8n.${DOMAIN}`
- `flowise.${DOMAIN}`
- `openwebui.${DOMAIN}` / `chat.${DOMAIN}`
- `anythingllm.${DOMAIN}`
- `litellm.${DOMAIN}`

---

### **ISSUE 6: 🟠 HIGH — Ollama Restart Loop**

From the test report: `ai-datasquiz-ollama → RESTARTING`

Likely causes visible in script 2:
```bash
user: "${TENANT_UID}:${TENANT_GID}"   # ← GPU access requires root/video group
# Missing: runtime: nvidia  OR  deploy.resources.reservations.devices
# Missing: /dev/gpu bind mount
```

---

### **ISSUE 7: 🟡 MEDIUM — Hardcoded Username `jglaine`**
```bash
TENANT_UID=$(id -u jglaine)   # ← Hardcoded — breaks on any other server
TENANT_GID=$(id -g jglaine)
```
Should use `${TENANT_USER}` or `${SUDO_USER}` from the env file.

---

### **ISSUE 8: 🟡 MEDIUM — `main "$@"` Has No Newline Before It**
```bash
    fi
}main "$@"    ← closing brace and main() on same line
```
Script 3 last line — bash may fail to parse the final function close.

---

## 📊 COMPLETE ISSUE REGISTER

| # | Script | Severity | Category | Issue |
|---|--------|----------|----------|-------|
| 1 | `1` | 🔴 Critical | Syntax | `EOFchmod` — heredoc never closes |
| 2 | `2` | 🔴 Critical | Syntax | `fi#` — bash parse error |
| 3 | `2` | 🔴 Critical | YAML | `prometheus:` missing 2-space indent |
| 4 | `2` | 🔴 Critical | Missing Code | No compose blocks for n8n/flowise/openwebui/anythingllm/litellm/authentik |
| 5 | `1` | 🟠 High | Missing Code | No Caddy subdomain routes for app services |
| 6 | `2` | 🟠 High | Config | Ollama missing GPU runtime config |
| 7 | `2` | 🟠 High | Portability | Hardcoded `jglaine` username |
| 8 | `3` | 🟡 Medium | Syntax | `}main "$@"` missing newline |

---

## 🏗️ PHASE 2: WINDSURF IMPLEMENTATION PLAN

---

### **TASK 1 — Fix `EOFchmod` in Script 1**
**File:** `scripts/1-setup-system.sh`  
**Type:** Single line fix

```
FIND (exact string):
EOFchmod 644 "${CADDY_DIR}/Caddyfile"

REPLACE WITH:
EOF
chmod 644 "${CADDY_DIR}/Caddyfile"
```

---

### **TASK 2 — Fix `fi#` in Script 2**
**File:** `scripts/2-deploy-services.sh`  
**Type:** Single line fix

```
FIND (exact string):
    exit 1
fi# ─── Docker daemon

REPLACE WITH:
    exit 1
fi

# ─── Docker daemon
```

---

### **TASK 3 — Fix Prometheus YAML Indentation in Script 2**
**File:** `scripts/2-deploy-services.sh`  
**Type:** Indentation fix inside heredoc

```
FIND (inside the docker-compose.yml heredoc):
prometheus:
    image: prom/prometheus:latest
    container_name: ai-datasquiz-prometheus

REPLACE WITH:
  prometheus:
    image: prom/prometheus:latest
    container_name: ai-datasquiz-prometheus
```

---

### **TASK 4 — Fix Hardcoded Username in Script 2**
**File:** `scripts/2-deploy-services.sh`  
**Type:** Variable substitution

```
FIND:
TENANT_UID=$(id -u jglaine)
TENANT_GID=$(id -g jglaine)

REPLACE WITH:
TENANT_UID=$(id -u "${TENANT_USER:-${SUDO_USER:-$(logname)}}")
TENANT_GID=$(id -g "${TENANT_USER:-${SUDO_USER:-$(logname)}}")
```

---

### **TASK 5 — Add Missing Service Blocks to docker-compose.yml**
**File:** `scripts/2-deploy-services.sh`  
**Type:** Large addition — insert BEFORE the `networks:` block at the end of the heredoc

Add the following 6 service blocks **conditionally** based on ENABLE_ flags:

```bash
# ── n8n ──────────────────────────────────────────────────────────────
$([ "${ENABLE_N8N:-true}" = "true" ] && cat << BLOCK

  n8n:
    image: n8nio/n8n:latest
    container_name: ${COMPOSE_PROJECT_NAME}-n8n
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    ports:
      - "${N8N_PORT:-5678}:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_USER:-admin}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD}
      - N8N_HOST=n8n.${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://n8n.${DOMAIN}
      - GENERIC_TIMEZONE=${TIMEZONE:-UTC}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=${COMPOSE_PROJECT_NAME}-postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
    volumes:
      - ${PLATFORM_DIR}/n8n:/home/node/.n8n
    networks:
      - ${COMPOSE_PROJECT_NAME}-net
    depends_on:
      - postgres
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
BLOCK
)

# ── Flowise ──────────────────────────────────────────────────────────
$([ "${ENABLE_FLOWISE:-true}" = "true" ] && cat << BLOCK

  flowise:
    image: flowiseai/flowise:latest
    container_name: ${COMPOSE_PROJECT_NAME}-flowise
    restart: unless-stopped
    user: "${TENANT_UID}:${TENANT_GID}"
    ports:
      - "${FLOWISE_PORT:-3001}:3000"
    environment:
      - FLOWISE_USERNAME=${FLOWISE_USER:-admin}
      - FLOWISE_PASSWORD=${FLOWISE_PASSWORD}
      - DATABASE_PATH=/root/.flowise
      - APIKEY_PATH=/root/.flowise
      - SECRETKEY_PATH=/root/.flowise
      - LOG_PATH=/root/.flowise/logs
    volumes:
      - ${PLATFORM_DIR}/flowise:/root/.flowise
    networks:
      - ${COMPOSE_PROJECT_NAME}-net
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:3000"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
BLOCK
)

# ── Open WebUI ───────────────────────────────────────────────────────
$([ "${ENABLE_OPENWEBUI:-true}" = "true" ] && cat << BLOCK

  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: ${COMPOSE_PROJECT_NAME}-openwebui
    restart: unless-stopped
    ports:
      - "${OPENWEBUI_PORT:-3003}:8080"
    environment:
      - OLLAMA_BASE_URL=http://${COMPOSE_PROJECT_NAME}-ollama:11434
      - WEBUI_SECRET_KEY=${OPENWEBUI_SECRET_KEY:-$(openssl rand -hex 32)}
    volumes:
      - ${PLATFORM_DIR}/openwebui:/app/backend/data
    networks:
      - ${COMPOSE_PROJECT_NAME}-net
    depends_on:
      - ollama
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
BLOCK
)

# ── AnythingLLM ──────────────────────────────────────────────────────
$([ "${ENABLE_ANYTHINGLLM:-true}" = "true" ] && cat << BLOCK

  anythingllm:
    image: mintplexlabs/anythingllm:latest
    container_name: ${COMPOSE_PROJECT_NAME}-anythingllm
    restart: unless-stopped
    ports:
      - "${ANYTHINGLLM_PORT:-3004}:3001"
    environment:
      - STORAGE_DIR=/app/server/storage
      - JWT_SECRET=${ANYTHINGLLM_JWT_SECRET:-$(openssl rand -hex 32)}
      - LLM_PROVIDER=ollama
      - OLLAMA_BASE_PATH=http://${COMPOSE_PROJECT_NAME}-ollama:11434
      - VECTOR_DB=qdrant
      - QDRANT_ENDPOINT=http://${COMPOSE_PROJECT_NAME}-qdrant:6333
    volumes:
      - ${PLATFORM_DIR}/anythingllm:/app/server/storage
    networks:
      - ${COMPOSE_PROJECT_NAME}-net
    depends_on:
      - ollama
      - qdrant
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3001/api/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
BLOCK
)

# ── LiteLLM ──────────────────────────────────────────────────────────
$([ "${ENABLE_LITELLM:-true}" = "true" ] && cat << BLOCK

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: ${COMPOSE_PROJECT_NAME}-litellm
    restart: unless-stopped
    ports:
      - "${LITELLM_PORT:-4000}:4000"
    environment:
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${COMPOSE_PROJECT_NAME}-postgres:5432/litellm
      - STORE_MODEL_IN_DB=True
    volumes:
      - ${PLATFORM_DIR}/litellm:/app/config
    networks:
      - ${COMPOSE_PROJECT_NAME}-net
    depends_on:
      - postgres
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s
BLOCK
)

# ── Authentik ────────────────────────────────────────────────────────
$([ "${ENABLE_AUTHENTIK:-false}" = "true" ] && cat << BLOCK

  authentik-server:
    image: ghcr.io/goauthentik/server:latest
    container_name: ${COMPOSE_PROJECT_NAME}-authentik
    restart: unless-stopped
    command: server
    ports:
      - "${AUTHENTIK_PORT:-9000}:9000"
    environment:
      - AUTHENTIK_REDIS__HOST=${COMPOSE_PROJECT_NAME}-redis
      - AUTHENTIK_POSTGRESQL__HOST=${COMPOSE_PROJECT_NAME}-postgres
      - AUTHENTIK_POSTGRESQL__USER=${POSTGRES_USER}
      - AUTHENTIK_POSTGRESQL__PASSWORD=${POSTGRES_PASSWORD}
      - AUTHENTIK_POSTGRESQL__NAME=authentik
      - AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY:-$(openssl rand -hex 32)}
      - AUTHENTIK_BOOTSTRAP_PASSWORD=${AUTHENTIK_BOOTSTRAP_PASSWORD}
      - AUTHENTIK_BOOTSTRAP_EMAIL=${ADMIN_EMAIL}
    volumes:
      - ${PLATFORM_DIR}/authentik/media:/media
      - ${PLATFORM_DIR}/authentik/custom-templates:/templates
    networks:
      - ${COMPOSE_PROJECT_NAME}-net
    depends_on:
      - postgres
      - redis
BLOCK
)
```

Also add to **directory creation block**:
```bash
mkdir -p "${PLATFORM_DIR}/n8n"
mkdir -p "${PLATFORM_DIR}/flowise"
mkdir -p "${PLATFORM_DIR}/openwebui"
mkdir -p "${PLATFORM_DIR}/anythingllm"
mkdir -p "${PLATFORM_DIR}/litellm"
mkdir -p "${PLATFORM_DIR}/authentik/media"
mkdir -p "${PLATFORM_DIR}/authentik/custom-templates"
```

---

### **TASK 6 — Add Caddy Subdomain Routes in Script 1**
**File:** `scripts/1-setup-system.sh`  
**Type:** Addition — insert before the `EOFchmod` line (which will be fixed to `EOF`)

```bash
$([ "${ENABLE_N8N:-true}" = "true" ] && cat << BLOCK
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
$([ "${ENABLE_FLOWISE:-true}" = "true" ] && cat << BLOCK
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
$([ "${ENABLE_OPENWEBUI:-true}" = "true" ] && cat << BLOCK
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
$([ "${ENABLE_ANYTHINGLLM:-true}" = "true" ] && cat << BLOCK
docs.${DOMAIN} {
    reverse_proxy anythingllm:3001 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
BLOCK
)
$([ "${ENABLE_LITELLM:-true}" = "true" ] && cat << BLOCK
api.${DOMAIN} {
    reverse_proxy litellm:4000 {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}
BLOCK
)
```

---

### **TASK 7 — Fix Ollama GPU Runtime in Script 2**
**File:** `scripts/2-deploy-services.sh`  
**Type:** Add GPU config to Ollama service block

```yaml
# FIND (inside ollama service block):
    networks:
      - ${COMPOSE_PROJECT_NAME}-net

# REPLACE WITH:
    networks:
      - ${COMPOSE_PROJECT_NAME}-net
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
```

Also add a **GPU availability check** before compose up:
```bash
# After Docker daemon check:
if command -v nvidia-smi &>/dev/null; then
    log "GPU detected: $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"
    GPU_AVAILABLE=true
else
    warn "No NVIDIA GPU detected — Ollama will run in CPU mode"
    GPU_AVAILABLE=false
fi
```

---

### **TASK 8 — Fix `}main "$@"` in Script 3**
**File:** `scripts/3-configure-services.sh`

```
FIND (exact, last line):
    fi
}main "$@"

REPLACE WITH:
    fi
}

main "$@"
```

---

## 📋 COMPLETE WINDSURF PROMPT

```
Implement the following 8 fixes to the AI Platform Automation scripts.
Make ONLY the specified changes. Do not refactor or rename anything.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FILE: scripts/1-setup-system.sh
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

FIX 1 — EOFchmod heredoc collision (CRITICAL):
  Find:    EOFchmod 644 "${CADDY_DIR}/Caddyfile"
  Replace: EOF\nchmod 644 "${CADDY_DIR}/Caddyfile"

FIX 5 — Add Caddy subdomain routes for app services:
  Insert the n8n/flowise/openwebui/anythingllm/litellm Caddy blocks
  immediately BEFORE the line: EOF (the newly fixed heredoc close)
  Use conditional $([ "${ENABLE_X}" = "true" ] && cat << BLOCK...BLOCK)
  pattern already used in the file for grafana and authentik.
  
  Subdomains to add:
    n8n.DOMAIN        → n8n:5678
    flowise.DOMAIN    → flowise:3000
    chat.DOMAIN       → openwebui:8080
    docs.DOMAIN       → anythingllm:3001
    api.DOMAIN        → litellm:4000

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FILE: scripts/2-deploy-services.sh
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

FIX 2 — fi# syntax error (CRITICAL):
  Find:    exit 1\nfi# ─── Docker daemon
  Replace: exit 1\nfi\n\n# ─── Docker daemon

FIX 3 — prometheus YAML indent (CRITICAL):
  Find:    ^prometheus:\n    image: prom/prometheus:latest
  Replace: ^  prometheus:\n    image: prom/prometheus:latest

FIX 4 — Hardcoded username:
  Find:    TENANT_UID=$(id -u jglaine)
           TENANT_GID=$(id -g jglaine)
  Replace: TENANT_UID=$(id -u "${TENANT_USER:-${SUDO_USER:-$(logname)}}")
           TENANT_GID=$(id -g "${TENANT_USER:-${SUDO_USER:-$(logname)}}")

FIX 6 — Add missing service directories (before chown line):
  Add: mkdir -p for n8n, flowise, openwebui, anythingllm, 
       litellm, authentik/media, authentik/custom-templates

FIX 6b — Add missing service blocks to docker-compose heredoc:
  Insert BEFORE the networks: section at the end of the heredoc.
  Add conditional service blocks for:
    n8n, flowise, openwebui, anythingllm, litellm, authentik-server
  Each block must:
    - Be wrapped in $([ "${ENABLE_X:-true}" = "true" ] && cat << BLOCK...BLOCK)
    - Use ${COMPOSE_PROJECT_NAME} for container names and network
    - Use ${PLATFORM_DIR} for volumes
    - Include healthcheck, restart: unless-stopped
    - Include depends_on where appropriate (postgres, redis, ollama, qdrant)

FIX 7 — Add Ollama GPU runtime:
  In the ollama service block, add after the networks section:
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FILE: scripts/3-configure-services.sh
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

FIX 8 — }main on same line:
  Find:    }main "$@"
  Replace: }\n\nmain "$@"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
VALIDATION — Run after all changes:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

bash -n scripts/1-setup-system.sh
bash -n scripts/2-deploy-services.sh  
bash -n scripts/3-configure-services.sh
grep -c "container_name" scripts/2-deploy-services.sh  # expect ≥12
grep "EOFchmod\|fi#\|}main\|jglaine" scripts/*.sh      # expect 0 results
```

---

## ✅ EXPECTED OUTCOME AFTER ALL FIXES

| Check | Before | After |
|-------|--------|-------|
| bash -n all scripts | ❌ Parse errors | ✅ Clean |
| Services deployed | 6/12 | ✅ 12/12 |
| Subdomains routed | 2/7 | ✅ 7/7 |
| Ollama GPU | ❌ Restart loop | ✅ GPU enabled |
| Variable expansion | ✅ Already fixed | ✅ Maintained |
| Portability | ❌ Hardcoded user | ✅ Dynamic |