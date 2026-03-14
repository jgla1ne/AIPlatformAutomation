Let me read all files carefully before responding.

---

# Comprehensive Implementation Plan — Zero Services Unturned

## Executive Summary of Current State

From the comprehensive analysis, here is the **exact truth**:

| Service | HTTP | Root Cause | Category |
|---------|------|-----------|----------|
| Grafana | 302 ✓ | — | Working |
| N8N | 200 ✓ | — | Working |
| Authentik | 302 ✓ | — | Working |
| Caddy | — | Config gaps | Infrastructure |
| OpenWebUI | 502 | DATABASE_URL not resolving | Config |
| Flowise | 502 | EACCES on logs dir | Permissions |
| LiteLLM | 502 | Missing LITELLM_MASTER_KEY + config.yaml | Config |
| AnythingLLM | 502 | SQLite→PostgreSQL migration conflict | Data |
| Dify API | 502 | SECRET_KEY missing + Redis URL format | Config |
| Dify Web | 502 | CONSOLE_API_URL not set | Config |
| SearXNG | 502 | settings.yml missing/misconfigured | Config |
| Ollama | 200 ✓ internal | No models pulled | Data |
| Prometheus | 502 | scrape config unreachable targets | Config |
| Loki | 502 | filesystem permissions on /loki | Permissions |
| Signal Bridge | 502 | registration not completed | Process |
| Qdrant | — | Likely healthy, not exposed via Caddy | Config |
| Weaviate | — | Likely healthy, not exposed via Caddy | Config |
| PostgreSQL | ✓ internal | — | Working |
| Redis | ✓ internal | — | Working |

---

## Core Principles — Non-Negotiable Constraints

Before every fix, these must be honored from the scripts:

1. **Non-root execution** — All containers must run as UID 1000 or their designated user. No service should run as root inside the container when a data volume is mounted.
2. **Script 3 modularity** — Configure-services.sh is structured as independent functions per service. Fixes must slot into that pattern, not bypass it.
3. **`.env` as single source of truth** — No credentials hardcoded in docker-compose.yml. Every password, key, and URL must come from `.env`.
4. **Network isolation** — `ai-datasquiz-net` is the application network. Tailscale and OpenClaw have their own network. These must not be mixed.
5. **Caddy as sole TLS terminator** — No service should expose ports directly to the internet. Everything routes through Caddy.
6. **Data persistence** — All mounts under `/mnt/data/datasquiz/`. Volume paths must exist with correct ownership before container start.

---

## Part 1: Pre-Flight — `.env` Must Be Complete

Every downstream failure traces back to missing `.env` values. This must be validated first, once, before touching any service.

### The Complete `.env` Specification

```bash
# Run this audit — every line marked MISSING must be added before proceeding
cat << 'AUDIT' > /tmp/env_audit.sh
#!/bin/bash
ENV=/mnt/data/datasquiz/.env
required_vars=(
  # Core
  "DOMAIN"
  "DATA_PATH"
  # PostgreSQL
  "POSTGRES_PASSWORD"
  # Redis
  "REDIS_PASSWORD"
  # Grafana
  "GRAFANA_PASSWORD"
  # N8N
  "N8N_ENCRYPTION_KEY"
  "N8N_DB_PASSWORD"
  # Authentik
  "AUTHENTIK_SECRET_KEY"
  "AUTHENTIK_DB_PASSWORD"
  "AUTHENTIK_REDIS_PASSWORD"
  # OpenWebUI
  "OPENWEBUI_DB_PASSWORD"
  "OPENWEBUI_SECRET_KEY"
  # Flowise
  "FLOWISE_DB_PASSWORD"
  "FLOWISE_USERNAME"
  "FLOWISE_PASSWORD"
  # LiteLLM
  "LITELLM_MASTER_KEY"
  "LITELLM_DB_PASSWORD"
  "LITELLM_SALT_KEY"
  # AnythingLLM
  "ANYTHINGLLM_DB_PASSWORD"
  "ANYTHINGLLM_JWT_SECRET"
  # Dify
  "DIFY_SECRET_KEY"
  "DIFY_DB_PASSWORD"
  "DIFY_REDIS_PASSWORD"
  # SearXNG
  "SEARXNG_SECRET_KEY"
  # Signal
  "SIGNAL_PHONE_NUMBER"
)

echo "=== ENV AUDIT ==="
missing=0
for var in "${required_vars[@]}"; do
  val=$(grep "^${var}=" $ENV 2>/dev/null | cut -d= -f2-)
  if [ -z "$val" ]; then
    echo "MISSING: $var"
    missing=$((missing + 1))
  else
    echo "OK:      $var"
  fi
done
echo ""
echo "Missing count: $missing"
AUDIT
chmod +x /tmp/env_audit.sh
sudo bash /tmp/env_audit.sh
```

### Auto-generate Missing Values

```bash
# Add any missing vars — safe to run, will not overwrite existing values
ENV=/mnt/data/datasquiz/.env

add_if_missing() {
  local key=$1
  local val=$2
  if ! grep -q "^${key}=" $ENV 2>/dev/null; then
    echo "${key}=${val}" | sudo tee -a $ENV
    echo "Added: $key"
  fi
}

# Generate secure values
add_if_missing "OPENWEBUI_SECRET_KEY" "$(openssl rand -hex 32)"
add_if_missing "OPENWEBUI_DB_PASSWORD" "$(openssl rand -hex 16)"
add_if_missing "FLOWISE_DB_PASSWORD" "$(openssl rand -hex 16)"
add_if_missing "FLOWISE_USERNAME" "admin"
add_if_missing "FLOWISE_PASSWORD" "$(openssl rand -hex 12)"
add_if_missing "LITELLM_MASTER_KEY" "sk-$(openssl rand -hex 16)"
add_if_missing "LITELLM_DB_PASSWORD" "$(openssl rand -hex 16)"
add_if_missing "LITELLM_SALT_KEY" "$(openssl rand -hex 32)"
add_if_missing "ANYTHINGLLM_DB_PASSWORD" "$(openssl rand -hex 16)"
add_if_missing "ANYTHINGLLM_JWT_SECRET" "$(openssl rand -hex 32)"
add_if_missing "DIFY_SECRET_KEY" "$(openssl rand -hex 32)"
add_if_missing "DIFY_DB_PASSWORD" "$(openssl rand -hex 16)"
add_if_missing "DIFY_REDIS_PASSWORD" "$(openssl rand -hex 16)"
add_if_missing "SEARXNG_SECRET_KEY" "$(openssl rand -hex 32)"
```

---

## Part 2: Database Pre-Provisioning

Every service with PostgreSQL will fail on first start if its database does not exist. This must run **before** any application container starts.

```bash
#!/bin/bash
# Run ONCE after PostgreSQL is healthy
POSTGRES_CONTAINER="ai-datasquiz-postgres-1"
ENV=/mnt/data/datasquiz/.env

get_env() { grep "^${1}=" $ENV | cut -d= -f2-; }

POSTGRES_PASSWORD=$(get_env POSTGRES_PASSWORD)

provision_db() {
  local dbname=$1
  local username=$2
  local password=$3

  sudo docker exec $POSTGRES_CONTAINER psql -U postgres << SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${username}') THEN
    CREATE USER ${username} WITH PASSWORD '${password}';
  END IF;
END
\$\$;

SELECT 'CREATE DATABASE ${dbname} OWNER ${username}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${dbname}')\gexec
GRANT ALL PRIVILEGES ON DATABASE ${dbname} TO ${username};
SQL
  echo "Provisioned: $dbname / $username"
}

# Provision all databases
provision_db "n8n"         "n8n"         "$(get_env N8N_DB_PASSWORD)"
provision_db "authentik"   "authentik"   "$(get_env AUTHENTIK_DB_PASSWORD)"
provision_db "openwebui"   "openwebui"   "$(get_env OPENWEBUI_DB_PASSWORD)"
provision_db "flowise"     "flowise"     "$(get_env FLOWISE_DB_PASSWORD)"
provision_db "litellm"     "litellm"     "$(get_env LITELLM_DB_PASSWORD)"
provision_db "anythingllm" "anythingllm" "$(get_env ANYTHINGLLM_DB_PASSWORD)"
provision_db "dify"        "dify"        "$(get_env DIFY_DB_PASSWORD)"

echo ""
echo "=== Database List ==="
sudo docker exec $POSTGRES_CONTAINER psql -U postgres -c "\l" | grep -E "n8n|authentik|openwebui|flowise|litellm|anythingllm|dify"
```

---

## Part 3: Volume Pre-Creation With Correct Ownership

Every permission error (Flowise, Loki, AnythingLLM) comes from volumes not existing with correct ownership before container start. Script 1 must create these. If it did not, run this now:

```bash
#!/bin/bash
DATA=/mnt/data/datasquiz

# Structure: "path:owner_uid:owner_gid"
declare -A volume_owners=(
  ["$DATA/flowise"]="1000:1000"
  ["$DATA/flowise/logs"]="1000:1000"
  ["$DATA/flowise/storage"]="1000:1000"
  ["$DATA/n8n"]="1000:1000"
  ["$DATA/openwebui"]="1000:1000"
  ["$DATA/anythingllm"]="1000:1000"
  ["$DATA/anythingllm/storage"]="1000:1000"
  ["$DATA/loki"]="10001:10001"
  ["$DATA/loki/data"]="10001:10001"
  ["$DATA/loki/wal"]="10001:10001"
  ["$DATA/litellm"]="1000:1000"
  ["$DATA/dify/storage"]="1000:1000"
  ["$DATA/dify/logs"]="1000:1000"
  ["$DATA/searxng"]="977:977"
  ["$DATA/prometheus"]="65534:65534"
  ["$DATA/prometheus/data"]="65534:65534"
  ["$DATA/ollama"]="1000:1000"
  ["$DATA/caddy/data"]="0:0"
  ["$DATA/caddy/config"]="0:0"
)

for path in "${!volume_owners[@]}"; do
  owner="${volume_owners[$path]}"
  sudo mkdir -p "$path"
  sudo chown -R "$owner" "$path"
  echo "Created/owned: $path ($owner)"
done
```

**Critical note on Loki:** Loki's official image uses UID 10001. Using 1000 will cause it to fail silently. This is the most common Loki permission mistake.

---

## Part 4: Service-by-Service Docker Compose Fixes

The following are the **exact docker-compose.yml changes** required. These replace what is currently broken.

### 4.1 — OpenWebUI

**Problem:** `DATABASE_URL` not resolving because variable substitution fails when the variable is nested inside a connection string.

```yaml
# docker-compose.yml — openwebui service
openwebui:
  image: ghcr.io/open-webui/open-webui:latest
  container_name: ai-datasquiz-openwebui-1
  restart: unless-stopped
  networks:
    - ai-datasquiz-net
  volumes:
    - /mnt/data/datasquiz/openwebui:/app/backend/data
  environment:
    - DATABASE_URL=postgresql://openwebui:${OPENWEBUI_DB_PASSWORD}@postgres:5432/openwebui
    - WEBUI_SECRET_KEY=${OPENWEBUI_SECRET_KEY}
    - WEBUI_AUTH=true
    - ENABLE_SIGNUP=true
    - OLLAMA_BASE_URL=http://ollama:11434
  depends_on:
    postgres:
      condition: service_healthy
```

**Why the variable fails:** Docker Compose does not expand variables inside quoted strings in some edge cases. Using the `KEY=value` list format (not the `KEY: value` map format) ensures expansion works correctly.

### 4.2 — Flowise

```yaml
flowise:
  image: flowiseai/flowise:latest
  container_name: ai-datasquiz-flowise-1
  restart: unless-stopped
  user: "1000:1000"
  networks:
    - ai-datasquiz-net
  volumes:
    - /mnt/data/datasquiz/flowise:/root/.flowise
  environment:
    - DATABASE_TYPE=postgres
    - DATABASE_HOST=postgres
    - DATABASE_PORT=5432
    - DATABASE_NAME=flowise
    - DATABASE_USER=flowise
    - DATABASE_PASSWORD=${FLOWISE_DB_PASSWORD}
    - FLOWISE_USERNAME=${FLOWISE_USERNAME}
    - FLOWISE_PASSWORD=${FLOWISE_PASSWORD}
    - SECRETKEY_PATH=/root/.flowise
    - LOG_PATH=/root/.flowise/logs
  depends_on:
    postgres:
      condition: service_healthy
```

**Why `user: "1000:1000"` is critical:** Without this, the container starts as root, creates files owned by root, and then the Flowise process (which drops to 1000 internally) cannot write to them. Setting user at compose level ensures all file creation happens as 1000 from the start.

### 4.3 — LiteLLM

```yaml
litellm:
  image: ghcr.io/berriai/litellm:main-latest
  container_name: ai-datasquiz-litellm-1
  restart: unless-stopped
  networks:
    - ai-datasquiz-net
  volumes:
    - /mnt/data/datasquiz/litellm/config.yaml:/app/config.yaml:ro
  environment:
    - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
    - DATABASE_URL=postgresql://litellm:${LITELLM_DB_PASSWORD}@postgres:5432/litellm
    - LITELLM_SALT_KEY=${LITELLM_SALT_KEY}
    - STORE_MODEL_IN_DB=True
  command: ["--config", "/app/config.yaml", "--port", "4000", "--detailed_debug"]
  depends_on:
    postgres:
      condition: service_healthy
```

**Required config.yaml — create before starting:**
```bash
sudo mkdir -p /mnt/data/datasquiz/litellm
sudo tee /mnt/data/datasquiz/litellm/config.yaml << 'EOF'
model_list:
  - model_name: ollama-llama3
    litellm_params:
      model: ollama/llama3
      api_base: http://ollama:11434

litellm_settings:
  drop_params: true
  set_verbose: false

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/DATABASE_URL
EOF
```

### 4.4 — AnythingLLM

```yaml
anythingllm:
  image: mintplexlabs/anythingllm:latest
  container_name: ai-datasquiz-anythingllm-1
  restart: unless-stopped
  user: "1000:1000"
  networks:
    - ai-datasquiz-net
  volumes:
    - /mnt/data/datasquiz/anythingllm/storage:/app/server/storage
  environment:
    - DATABASE_CONNECTION_STRING=postgresql://anythingllm:${ANYTHINGLLM_DB_PASSWORD}@postgres:5432/anythingllm
    - JWT_SECRET=${ANYTHINGLLM_JWT_SECRET}
    - SIG_KEY_PAIR=${ANYTHINGLLM_JWT_SECRET}
    - VECTOR_DB=lancedb
    - STORAGE_DIR=/app/server/storage
  depends_on:
    postgres:
      condition: service_healthy
```

**Before starting — remove SQLite artifacts:**
```bash
sudo find /mnt/data/datasquiz/anythingllm/ -name "*.db" -delete
sudo find /mnt/data/datasquiz/anythingllm/ -name "*.sqlite" -delete
sudo chown -R 1000:1000 /mnt/data/datasquiz/anythingllm/
```

### 4.5 — Dify (Three Containers Required)

Dify is architecturally the most complex service. It requires three containers that must all be defined:

```yaml
dify-api:
  image: langgenius/dify-api:latest
  container_name: ai-datasquiz-dify-api-1
  restart: unless-stopped
  networks:
    - ai-datasquiz-net
  volumes:
    - /mnt/data/datasquiz/dify/storage:/app/api/storage
  environment:
    - MODE=api
    - SECRET_KEY=${DIFY_SECRET_KEY}
    - DATABASE_URL=postgresql://dify:${DIFY_DB_PASSWORD}@postgres:5432/dify
    - REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379/0
    - CELERY_BROKER_URL=redis://:${REDIS_PASSWORD}@redis:6379/1
    - STORAGE_TYPE=local
    - STORAGE_LOCAL_PATH=/app/api/storage
    - CONSOLE_WEB_URL=https://dify.ai.datasquiz.net
    - CONSOLE_API_URL=https://dify.ai.datasquiz.net
    - SERVICE_API_URL=https://dify.ai.datasquiz.net
    - APP_WEB_URL=https://dify.ai.datasquiz.net
  depends_on:
    postgres:
      condition: service_healthy

dify-worker:
  image: langgenius/dify-api:latest
  container_name: ai-datasquiz-dify-worker-1
  restart: unless-stopped
  networks:
    - ai-datasquiz-net
  volumes:
    - /mnt/data/datasquiz/dify/storage:/app/api/storage
  environment:
    - MODE=worker
    - SECRET_KEY=${DIFY_SECRET_KEY}
    - DATABASE_URL=postgresql://dify:${DIFY_DB_PASSWORD}@postgres:5432/dify
    - REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379/0
    - CELERY_BROKER_URL=redis://:${REDIS_PASSWORD}@redis:6379/1
    - STORAGE_TYPE=local
    - STORAGE_LOCAL_PATH=/app/api/storage
  depends_on:
    postgres:
      condition: service_healthy

dify-web:
  image: langgenius/dify-web:latest
  container_name: ai-datasquiz-dify-web-1
  restart: unless-stopped
  networks:
    - ai-datasquiz-net
  environment:
    - CONSOLE_API_URL=https://dify.ai.datasquiz.net
    - APP_API_URL=https://dify.ai.datasquiz.net
```

**Caddy routing for Dify** must proxy to `dify-web` for frontend and `dify-api` for API paths:
```
dify.ai.datasquiz.net {
    reverse_proxy /console/api/* dify-api:5001
    reverse_proxy /api/* dify-api:5001
    reverse_proxy /v1/* dify-api:5001
    reverse_proxy /files/* dify-api:5001
    reverse_proxy * dify-web:3000
}
```

### 4.6 — SearXNG

```yaml
searxng:
  image: searxng/searxng:latest
  container_name: ai-datasquiz-searxng-1
  restart: unless-stopped
  user: "977:977"
  networks:
    - ai-datasquiz-net
  volumes:
    - /mnt/data/datasquiz/searxng:/etc/searxng:rw
  environment:
    - SEARXNG_BASE_URL=https://searxng.ai.datasquiz.net/
    - SEARXNG_SECRET=${SEARXNG_SECRET_KEY}
```

**settings.yml must exist with correct secret:**
```bash
DATA=/mnt/data/datasquiz
sudo mkdir -p $DATA/searxng

# Extract default settings from image:
sudo docker run --rm searxng/searxng cat /etc/searxng/settings.yml | sudo tee $DATA/searxng/settings.yml

# Inject actual secret key:
SEARXNG_SECRET=$(grep "^SEARXNG_SECRET_KEY=" $DATA/.env | cut -d= -f2-)
sudo sed -i "s/ultrasecretkey/${SEARXNG_SECRET}/" $DATA/searxng/settings.yml

# SearXNG needs this specific JSON format for limiter:
sudo tee $DATA/searxng/limiter.toml << 'EOF'
[botdetection.ip_limit]
link_token = true
EOF

sudo chown -R 977:977 $DATA/searxng/
```

### 4.7 — Loki

```yaml
loki:
  image: grafana/loki:latest
  container_name: ai-datasquiz-loki-1
  restart: unless-stopped
  user: "10001:10001"
  networks:
    - ai-datasquiz-net
  volumes:
    - /mnt/data/datasquiz/loki:/loki
    - /mnt/data/datasquiz/loki/config.yaml:/etc/loki/config.yaml:ro
  command: -config.file=/etc/loki/config.yaml
```

**Loki config.yaml:**
```bash
sudo mkdir -p /mnt/data/datasquiz/loki/data /mnt/data/datasquiz/loki/wal
sudo tee /mnt/data/datasquiz/loki/config.yaml << 'EOF'
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  instance_addr: 127.0.0.1
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/data/chunks
      rules_directory: /loki/data/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2020-10-24
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

ruler:
  alertmanager_url: http://localhost:9093
EOF

sudo chown -R 10001:10001 /mnt/data/datasquiz/loki/
```

### 4.8 — Prometheus

```yaml
prometheus:
  image: prom/prometheus:latest
  container_name: ai-datasquiz-prometheus-1
  restart: unless-stopped
  user: "65534:65534"
  networks:
    - ai-datasquiz-net
  volumes:
    - /mnt/data/datasquiz/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    - /mnt/data/datasquiz/prometheus/data:/prometheus
  command:
    - '--config.file=/etc/prometheus/prometheus.yml'
    - '--storage.tsdb.path=/prometheus'
    - '--web.console.libraries=/etc/prometheus/console_libraries'
    - '--web.console.templates=/etc/prometheus/consoles'
```

**prometheus.yml — only scrape reachable targets:**
```bash
sudo tee /mnt/data/datasquiz/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'caddy'
    static_configs:
      - targets: ['caddy:2019']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  # Add other targets only after confirming their metrics endpoints are live
EOF

sudo chown -R 65534:65534 /mnt/data/datasquiz/prometheus/
```

**Critical:** Prometheus scraping targets that do not exist causes it to report unhealthy. Only add targets you have confirmed are running and exposing `/metrics`.

---

## Part 5: Caddyfile — Complete Configuration

The diagnosis shows Caddy only reliably serves Grafana. The Caddyfile must be complete and use container names (not IPs) as upstreams.

```bash
sudo tee /mnt/data/datasquiz/caddy/Caddyfile << 'EOF'
{
    admin 0.0.0.0:2019
    email admin@datasquiz.net
}

grafana.ai.datasquiz.net {
    reverse_proxy ai-datasquiz-grafana-1:3000
}

n8n.ai.datasquiz.net {
    reverse_proxy ai-datasquiz-n8n-1:5678
}

auth.ai.datasquiz.net {
    reverse_proxy ai-datasquiz-authentik-server-1:9000
}

openwebui.ai.datasquiz.net {
    reverse_proxy ai-datasquiz-openwebui-1:8080
}

flowise.ai.datasquiz.net {
    reverse_proxy ai-datasquiz-flowise-1:3000
}

litellm.ai.datasquiz.net {
    reverse_proxy ai-datasquiz-litellm-1:4000
}

anythingllm.ai.datasquiz.net {
    reverse_proxy ai-datasquiz-anythingllm-1:3001
}

dify.ai.datasquiz.net {
    reverse_proxy /console/api/* ai-datasquiz-dify-api-1:5001
    reverse_proxy /api/* ai-datasquiz-dify-api-1:5001
    reverse_proxy /v1/* ai-datasquiz-dify-api-1:5001
    reverse_proxy /files/* ai-datasquiz-dify-api-1:5001
    reverse_proxy * ai-datasquiz-dify-web-1:3000
}

searxng.ai.datasquiz.net {
    reverse_proxy ai-datasquiz-searxng-1:8080
}

prometheus.ai.datasquiz.net {
    reverse_proxy ai-datasquiz-prometheus-1:9090
}

loki.ai.datasquiz.net {
    reverse_proxy ai-datasquiz-loki-1:3100
}
EOF
```

**Reload Caddy without restart:**
```bash
sudo docker exec ai-datasquiz-caddy-1 caddy reload --config /etc/caddy/Caddyfile
# If reload fails, check syntax first:
sudo docker exec ai-datasquiz-caddy-1 caddy validate --config /etc/caddy/Caddyfile
```

**Why Caddy was only serving Grafana:** Container name resolution in Docker uses the container name as the DNS hostname on the shared network. If Caddyfile used service names (e.g., `grafana`) instead of container names (e.g., `ai-datasquiz-grafana-1`), only services where the name happened to match would resolve. Grafana worked because it was the one that matched. **Use the exact container name.**

Actually — this is the reverse. Service names work if Caddy is on the same network. The real reason was that all other services were returning 502 due to application-level failures, not Caddy routing failures. Verify by checking: if you `curl http://ai-datasquiz-n8n-1:5678` from within the Caddy container and get a response, Caddy can reach it.

```bash
# Test from inside Caddy:
sudo docker exec ai-datasquiz-caddy-1 wget -qO- http://ai-datasquiz-grafana-1:3000/api/health
sudo docker exec ai-datasquiz-caddy-1 wget -qO- http://ai-datasquiz-n8n-1:5678/healthz 2>&1 | head -5
sudo docker exec ai-datasquiz-caddy-1 wget -qO- http://ai-datasquiz-openwebui-1:8080/ 2>&1 | head -5
```

---

## Part 6: Script 3 Integration — Modular Configuration

Script 3 is structured as independent service configuration functions. The following additions integrate cleanly with that pattern.

### Pattern for every new service function in script 3:

```bash
configure_SERVICE_NAME() {
    log "INFO" "Configuring SERVICE_NAME..."
    
    # 1. Verify container is running
    if ! docker ps --format "{{.Names}}" | grep -q "ai-datasquiz-service-1"; then
        log "ERROR" "SERVICE container not running — skipping configuration"
        return 1
    fi
    
    # 2. Wait for service to be ready (not just running)
    local max_wait=60
    local waited=0
    while ! curl -sf http://localhost:PORT/health > /dev/null 2>&1; do
        sleep 2
        waited=$((waited + 2))
        if [ $waited -ge $max_wait ]; then
            log "ERROR" "SERVICE did not become ready in ${max_wait}s"
            return 1
        fi
    done
    
    # 3. Apply configuration via API
    # ...service-specific API calls...
    
    log "SUCCESS" "SERVICE configured"
}
```

### Specific script 3 additions needed:

**LiteLLM — register Ollama models after both are running:**
```bash
configure_litellm() {
    log "INFO" "Configuring LiteLLM..."
    local master_key=$(get_env LITELLM_MASTER_KEY)
    
    # Wait for LiteLLM API
    wait_for_service "http://ai-datasquiz-litellm-1:4000/health/liveliness" 60
    
    # Add Ollama as a model provider
    curl -sf -X POST "https://litellm.ai.datasquiz.net/model/new" \
        -H "Authorization: Bearer ${master_key}" \
        -H "Content-Type: application/json" \
        -d '{
            "model_name": "ollama-llama3",
            "litellm_params": {
                "model": "ollama/llama3",
                "api_base": "http://ai-datasquiz-ollama-1:11434"
            }
        }' && log "SUCCESS" "LiteLLM: Ollama model registered" \
          || log "WARN" "LiteLLM: Model registration failed — manual setup required"
}
```

**Ollama — pull base model:**
```bash
configure_ollama() {
    log "INFO" "Configuring Ollama — pulling base model..."
    
    # Wait for Ollama API
    wait_for_service "http://ai-datasquiz-ollama-1:11434/api/tags" 60
    
    # Pull llama3 (this takes time — run in background or with timeout)
    docker exec ai-datasquiz-ollama-1 ollama pull llama3 &
    log "INFO" "Ollama: llama3 pull initiated (background) — check with: docker exec ai-datasquiz-ollama-1 ollama list"
}
```

---

## Part 7: Tailscale & OpenClaw — Separate Network

From the README and scripts, Tailscale and OpenClaw must be on their own network, not `ai-datasquiz-net`.

**The current failure pattern:** Both containers are likely on the main network and conflicting with the app stack's networking.

```yaml
# Networks definition in docker-compose.yml must include:
networks:
  ai-datasquiz-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.18.0.0/16
  
  tailscale-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.19.0.0/16

# Tailscale service:
tailscale:
  image: tailscale/tailscale:latest
  container_name: ai-datasquiz-tailscale-1
  restart: unless-stopped
  cap_add:
    - NET_ADMIN
    - NET_RAW
  volumes:
    - /mnt/data/datasquiz/tailscale:/var/lib/tailscale
    - /dev/net/tun:/dev/net/tun
  environment:
    - TS_AUTHKEY=${TAILSCALE_AUTHKEY}
    - TS_ROUTES=172.18.0.0/16
    - TS_STATE_DIR=/var/lib/tailscale
  networks:
    - tailscale-net
  # NOT on ai-datasquiz-net — Tailscale routes to it via TS_ROUTES
```

---

## Part 8: RClone Sync

RClone is failing to sync because it is either not configured or the config file is not being read by the container.

```bash
# Verify rclone config exists:
ls -la /mnt/data/datasquiz/rclone/
cat /mnt/data/datasquiz/rclone/rclone.conf 2>/dev/null || echo "CONFIG MISSING"

# Test rclone connectivity manually first:
sudo docker run --rm \
    -v /mnt/data/datasquiz/rclone:/config/rclone \
    rclone/rclone:latest \
    lsd remote: 2>&1 | head -20
```

RClone as a sync service needs either a cron job or a separate container running `rclone sync` on a schedule. If script 2 deploys rclone as a one-shot container, it will exit immediately after running and not repeat.

The correct pattern for persistent sync:
```yaml
rclone:
  image: rclone/rclone:latest
  container_name: ai-datasquiz-rclone-1
  restart: unless-stopped
  volumes:
    - /mnt/data/datasquiz/rclone:/config/rclone:ro
    - /mnt/data/datasquiz:/data:ro
  entrypoint: ["/bin/sh", "-c"]
  command:
    - |
      while true; do
        rclone sync /data remote:datasquiz-backup --log-level INFO
        sleep 3600
      done
```

---

## Part 9: The Complete Ordered Execution Plan

This is the exact sequence Windsurf must follow. No step should be skipped. Each has a gate check.

```
PHASE 0: Stop everything cleanly
PHASE 1: Audit and complete .env
PHASE 2: Create all volumes with correct ownership
PHASE 3: Verify/fix docker-compose.yml for all services
PHASE 4: Start infrastructure (postgres, redis, caddy)
PHASE 5: Provision all databases
PHASE 6: Start application services (in dependency order)
PHASE 7: Reload Caddy with complete Caddyfile
PHASE 8: Run script 3 configuration
PHASE 9: HTTP verification of all endpoints
PHASE 10: Resolve any remaining 502s by log inspection
```

```bash
#!/bin/bash
# ============================================================
# PHASE 0: Clean stop
# ============================================================
echo "=== PHASE 0: Stopping all services ==="
sudo docker compose -f /mnt/data/datasquiz/docker-compose.yml down --remove-orphans
sleep 5

# ============================================================
# PHASE 1: .env audit (run env_audit.sh from Part 1)
# ============================================================
echo "=== PHASE 1: ENV audit ==="
# Run env_audit.sh — fix any MISSING before continuing
# GATE: Zero MISSING lines before proceeding

# ============================================================
# PHASE 2: Volume ownership
# ============================================================
echo "=== PHASE 2: Volume ownership ==="
# Run volume ownership block from Part 3
# GATE: ls -la /mnt/data/datasquiz/ shows correct owners

# ============================================================
# PHASE 3: Config files
# ============================================================
echo "=== PHASE 3: Config files ==="
# LiteLLM config.yaml
# SearXNG settings.yml
# Loki config.yaml
# Prometheus prometheus.yml
# Caddyfile
# GATE: All files exist and are non-empty

# ============================================================
# PHASE 4: Start infrastructure
# ============================================================
echo "=== PHASE 4: Infrastructure ==="
sudo docker compose -f /mnt/data/datasquiz/docker-compose.yml up -d postgres redis
sleep 15

# GATE: postgres healthy
sudo docker exec ai-datasquiz-postgres-1 pg_isready -U postgres
# Must return: accepting connections

# ============================================================
# PHASE 5: Database provisioning
# ============================================================
echo "=== PHASE 5: Database provisioning ==="
# Run provision_db block from Part 2
# GATE: \l shows all databases

# ============================================================
# PHASE 6: Application services
# ============================================================
echo "=== PHASE 6: Application services ==="
# Start Caddy first (it doesn't depend on apps, apps don't depend on it)
sudo docker compose -f /mnt/data/datasquiz/docker-compose.yml up -d caddy
sleep 5

# Start apps
sudo docker compose -f /mnt/data/datasquiz/docker-compose.yml up -d \
    n8n authentik-server authentik-worker \
    openwebui flowise litellm anythingllm \
    dify-api dify-worker dify-web \
    searxng ollama loki prometheus grafana

sleep 45

# GATE: Container state check
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep "ai-datasquiz"

# ============================================================
# PHASE 7: Caddy reload
# ============================================================
echo "=== PHASE 7: Caddy reload ==="
sudo docker exec ai-datasquiz-caddy-1 caddy validate --config /etc/caddy/Caddyfile
sudo docker exec ai-datasquiz-caddy-1 caddy reload --config /etc/caddy/Caddyfile

# ============================================================
# PHASE 8: Script 3
# ============================================================
echo "=== PHASE 8: Script 3 configuration ==="
sudo bash /mnt/data/datasquiz/scripts/3-configure-services.sh

# ============================================================
# PHASE 9: HTTP verification
# ============================================================
echo "=== PHASE 9: HTTP verification ==="
services=(grafana n8n auth openwebui flowise litellm anythingllm dify searxng prometheus)
for svc in "${services[@]}"; do
    code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 https://${svc}.ai.datasquiz.net)
    echo "$svc: HTTP $code"
done

# ============================================================
# PHASE 10: Log inspection for any remaining 502s
# ============================================================
echo "=== PHASE 10: Log inspection ==="
for svc in "${services[@]}"; do
    code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 https://${svc}.ai.datasquiz.net)
    if [ "$code" = "502" ] || [ "$code" = "000" ]; then
        echo ""
        echo "=== INVESTIGATING: $svc (HTTP $code) ==="
        # Find container name
        cname=$(sudo docker ps --format "{{.Names}}" | grep "$svc" | head -1)
        if [ -n "$cname" ]; then
            sudo docker logs $cname --tail 20 2>&1
        else
            echo "Container not found for $svc"
        fi
    fi
done
```

---

## What To Report Back

After running the complete plan, report exactly:

```
1. ENV audit output (count of MISSING vars)
2. Database list output (\l from postgres)
3. docker ps output — all ai-datasquiz containers
4. HTTP verification output — all 10 services
5. For any service still at 502: last 20 lines of its container logs
```

**Success threshold:** All 10 services returning 200 or 302. Signal bridge is excluded as it requires manual phone registration after the platform is running.