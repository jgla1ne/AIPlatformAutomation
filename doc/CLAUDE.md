Let me fetch the current scripts to give precise fixes.

**Scripts:**
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/0-complete-cleanup.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/1-setup-system.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/2-deploy-services.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/3-configure-services.sh

---

After reviewing the scripts and diagnostic output:

---

```markdown
# CLAUDE.md — Deployment Triage: Root Cause & Surgical Fixes
**Date:** 2025-07
**Status:** CRITICAL — Multiple root causes, all fixable

---

## 🔴 ROOT CAUSE ANALYSIS

The diagnostic reveals **4 distinct failure layers** that must be fixed in order.
Do NOT attempt scripts 2/3 until each layer is resolved.

---

## LAYER 1: Script 1 hangs at "Collecting tenant configuration"

**Root cause:** Script 1 uses `read` for interactive input. When run via 
Windsurf's execution context (non-interactive shell / piped stdin), `read` 
blocks forever.

**Exact fix in Script 1:**

Every `read` call must have a `-t` timeout and a fallback default:
```bash
# BEFORE (hangs):
read -p "Enter tenant name: " TENANT_NAME

# AFTER (safe in all execution contexts):
read -t 30 -p "Enter tenant name [datasquiz]: " TENANT_NAME
TENANT_NAME="${TENANT_NAME:-datasquiz}"
```

Apply this pattern to EVERY `read` call in Script 1. The timeout is 30 seconds;
if no input arrives, the default is used. This makes Script 1 runnable both
interactively and non-interactively.

**Additionally:** Script 1 must be run in a real TTY. Windsurf should execute:
```bash
sudo bash scripts/1-setup-system.sh
```
in a proper terminal session, not a piped/spawned subprocess. If Windsurf cannot
guarantee a TTY, all defaults must be codified so the script self-completes.

---

## LAYER 2: Permission denied — Ollama & OpenWebUI

**Root cause:** Containers are running as non-root but the mounted host 
directories are owned by root.

**Diagnostic confirmation:**
```bash
ls -la /mnt/datasquiz/
# Expect: directories owned by root:root with 750 permissions
```

**Exact fix in Script 1** — directory creation block must set correct ownership:
```bash
# After creating directories:
BASE_DIR="/mnt/datasquiz"

mkdir -p "${BASE_DIR}"/{ollama,postgres,qdrant,redis,open-webui,n8n,flowise,litellm}

# Ollama runs as uid 1000 inside container:
chown -R 1000:1000 "${BASE_DIR}/ollama"

# OpenWebUI runs as uid 1000:
chown -R 1000:1000 "${BASE_DIR}/open-webui"

# Postgres runs as uid 999:
chown -R 999:999 "${BASE_DIR}/postgres"

# Qdrant runs as uid 1000:
chown -R 1000:1000 "${BASE_DIR}/qdrant"

# Set permissive base for others:
chmod -R 755 "${BASE_DIR}"
```

**For OpenWebUI secret key specifically** — the file must exist and be readable:
```bash
WEBUI_SECRET_FILE="${BASE_DIR}/open-webui/secret_key"
if [ ! -f "${WEBUI_SECRET_FILE}" ]; then
  openssl rand -hex 32 > "${WEBUI_SECRET_FILE}"
  chown 1000:1000 "${WEBUI_SECRET_FILE}"
  chmod 600 "${WEBUI_SECRET_FILE}"
fi
```

---

## LAYER 3: Containers not on the correct network

**Root cause:** `docker-compose.yml` declares the network but some services
are missing the `networks:` key under their service definition. Docker falls
back to the default bridge, breaking inter-service DNS.

**Diagnostic:**
```bash
docker network inspect config_ai-datasquiz-network
# Confirms: only redis and open-webui connected
```

**Exact fix in `docker-compose.yml`** — every service MUST declare:
```yaml
services:
  ollama:
    networks:
      - ai-platform-network
  
  postgres:
    networks:
      - ai-platform-network
  
  qdrant:
    networks:
      - ai-platform-network
  
  redis:
    networks:
      - ai-platform-network
  
  open-webui:
    networks:
      - ai-platform-network

  # ... every service must have this block

networks:
  ai-platform-network:
    driver: bridge
```

The network name must be IDENTICAL across all service definitions and the
top-level `networks:` declaration. The current network `config_ai-datasquiz-network`
suggests the compose project name is `config` — this is wrong. 

**Fix:** Ensure `docker-compose.yml` is in `/mnt/datasquiz/` or the project
name is explicitly set:
```bash
# In Script 2, replace bare docker compose calls with:
docker compose -p datasquiz -f /mnt/datasquiz/docker-compose.yml up -d
```
This ensures the network is named `datasquiz_ai-platform-network`, not
`config_ai-datasquiz-network`.

---

## LAYER 4: Postgres and Qdrant restart loops

**Root cause A (Postgres):** Data directory permissions (fixed by Layer 2 above).
Postgres also fails if it finds a partially initialized data directory.

**Root cause B (Qdrant):** Same permission issue + Qdrant may have a corrupted
storage directory from the broken previous run.

**Fix:** Script 0 (cleanup) must wipe data directories cleanly. Confirm it does:
```bash
# Script 0 must include:
rm -rf "${BASE_DIR}/postgres/*"
rm -rf "${BASE_DIR}/qdrant/*"
# NOT rmdir — must wipe contents, preserve directory
```

**Verify Postgres env vars are present:**
```bash
docker compose exec postgres env | grep POSTGRES
# Must show POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD
```
If missing → `.env` file not being passed to compose. Check Script 2:
```bash
# Script 2 must use:
docker compose --env-file /mnt/datasquiz/platform.conf -f docker-compose.yml up -d
# OR docker-compose.yml must have: env_file: /mnt/datasquiz/platform.conf
```

---

## LAYER 5: LiteLLM Exited (1)

**Root cause:** LiteLLM requires a valid `config.yaml`. If missing or malformed
it exits immediately.

**Fix in Script 2** — generate minimal LiteLLM config before `docker compose up`:
```bash
LITELLM_CONFIG="/mnt/datasquiz/litellm/config.yaml"
if [ ! -f "${LITELLM_CONFIG}" ]; then
  cat > "${LITELLM_CONFIG}" << 'EOF'
model_list:
  - model_name: ollama/llama3.2
    litellm_params:
      model: ollama/llama3.2
      api_base: http://ollama:11434

litellm_settings:
  drop_params: true
  max_budget: null
EOF
fi
```

---

## 📋 CORRECT EXECUTION SEQUENCE

Given the current broken state, follow this exact sequence:

### Step 0: Clean slate
```bash
sudo bash scripts/0-complete-cleanup.sh datasquiz
# Verify:
docker ps -a | grep -v CONTAINER  # should be empty
ls /mnt/datasquiz/                 # should be empty or not exist
```

### Step 1: Run in a REAL terminal with TTY
```bash
# Windsurf must exec this in an interactive terminal session:
sudo bash scripts/1-setup-system.sh
# Watch for "platform.conf created" confirmation before proceeding
# Verify:
cat /mnt/datasquiz/platform.conf   # must exist and have values
ls -la /mnt/datasquiz/ollama/      # must be owned by 1000:1000
```

### Step 2: Deploy
```bash
sudo bash scripts/2-deploy-services.sh
# Wait 60 seconds, then check:
docker compose -p datasquiz ps
# All containers should show "Up" not "Restarting"
```

### Step 3: Configure
```bash
sudo bash scripts/3-configure-services.sh
```

---

## 🔑 PLATFORM.CONF — MUST EXIST BEFORE SCRIPT 2

This is the single most important file. Script 2 cannot work without it.

Minimum required contents:
```bash
TENANT_NAME=datasquiz
BASE_DIR=/mnt/datasquiz
DOMAIN=datasquiz.local

# Database
POSTGRES_USER=datasquiz
POSTGRES_PASSWORD=<generated>
POSTGRES_DB=datasquiz

# Services selected
DEPLOY_OLLAMA=true
DEPLOY_OPENWEBUI=true
DEPLOY_N8N=true
DEPLOY_LITELLM=true
DEPLOY_QDRANT=true

# Ollama
OLLAMA_MODEL=llama3.2

# OpenWebUI
WEBUI_SECRET_KEY=<generated>
```

---

## ✅ GO/NO-GO CHECKLIST BEFORE SCRIPT 2

| Check | Command | Required Result |
|-------|---------|----------------|
| Cleanup complete | `docker ps -a` | No containers |
| platform.conf exists | `cat /mnt/datasquiz/platform.conf` | Has TENANT_NAME |
| Directory ownership | `ls -la /mnt/datasquiz/ollama` | uid 1000 |
| Postgres dir clean | `ls /mnt/datasquiz/postgres` | Empty |
| Qdrant dir clean | `ls /mnt/datasquiz/qdrant` | Empty |
| LiteLLM config exists | `cat /mnt/datasquiz/litellm/config.yaml` | Valid YAML |

**Do not proceed to Script 2 until all 6 pass.**
```