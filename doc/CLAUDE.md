Let me read all documents before responding.

---

# Revised Comprehensive Plan — Synthesis of All Models

## Meta-Analysis: What Each Model Got Right and Wrong

| Area | Claude | Windsurf | Gemini | Truth |
|------|--------|----------|--------|-------|
| Root cause diagnosis | Strong on DB provisioning | Strong on permissions | Strong on ordering | All partially correct |
| Non-root constraint | Mentioned | Partially implemented | Best coverage | Gemini closest |
| Script 3 modularity | Ignored it | Partially respected | Best respected | Gemini closest |
| Dify complexity | Correct 3-container | Incomplete | Correct | Both correct |
| Loki UID 10001 | Correct | Missed | Correct | Critical detail |
| Caddy container names | Confused | Used service names | Used service names | Service names work on shared network |
| Execution ordering | Good | Good | Best | Gemini closest |
| .env completeness | Best coverage | Partial | Partial | Claude closest |
| Signal bridge | Correctly excluded | Excluded | Excluded | All correct |

**The synthesized plan below takes the best from each model and resolves their conflicts.**

---

## Foundational Principles (Non-Negotiable)

1. **Stop before edit** — `docker compose down` before any docker-compose.yml change
2. **Volumes before containers** — mkdir + chown before docker compose up
3. **Databases before apps** — postgres healthy + DBs provisioned before any app starts
4. **Config files before containers** — LiteLLM config.yaml, SearXNG settings.yml, Loki config.yaml must exist before the container starts
5. **`.env` is single source of truth** — zero hardcoded credentials
6. **Non-root execution** — every container writing to a mounted volume needs `user:` set OR the volume pre-owned to match the container's runtime UID

---

## PHASE 0: Complete Stop

```bash
cd /mnt/data/datasquiz
sudo docker compose down --remove-orphans
sleep 10
# Verify nothing running:
sudo docker ps | grep "ai-datasquiz" && echo "WARNING: containers still running" || echo "OK: all stopped"
```

---

## PHASE 1: .env Audit and Completion

```bash
#!/bin/bash
ENV=/mnt/data/datasquiz/.env
DATA=/mnt/data/datasquiz

add_if_missing() {
    local key=$1 val=$2
    if ! grep -q "^${key}=" "$ENV" 2>/dev/null; then
        echo "${key}=${val}" | sudo tee -a "$ENV"
        echo "ADDED: $key"
    else
        echo "OK:    $key"
    fi
}

echo "=== ENV AUDIT AND COMPLETION ==="

# Core
add_if_missing "DOMAIN" "ai.datasquiz.net"
add_if_missing "DATA_PATH" "/mnt/data/datasquiz"

# Passwords that must already exist (warn if missing)
for var in POSTGRES_PASSWORD REDIS_PASSWORD; do
    val=$(grep "^${var}=" "$ENV" 2>/dev/null | cut -d= -f2-)
    [ -z "$val" ] && echo "CRITICAL MISSING: $var — must be set manually"
done

# Auto-generate all service credentials
add_if_missing "OPENWEBUI_SECRET_KEY"       "$(openssl rand -hex 32)"
add_if_missing "OPENWEBUI_DB_PASSWORD"      "$(openssl rand -hex 16)"
add_if_missing "FLOWISE_DB_PASSWORD"        "$(openssl rand -hex 16)"
add_if_missing "FLOWISE_USERNAME"           "admin"
add_if_missing "FLOWISE_PASSWORD"           "$(openssl rand -hex 12)"
add_if_missing "LITELLM_MASTER_KEY"         "sk-$(openssl rand -hex 16)"
add_if_missing "LITELLM_DB_PASSWORD"        "$(openssl rand -hex 16)"
add_if_missing "LITELLM_SALT_KEY"           "$(openssl rand -hex 32)"
add_if_missing "ANYTHINGLLM_DB_PASSWORD"    "$(openssl rand -hex 16)"
add_if_missing "ANYTHINGLLM_JWT_SECRET"     "$(openssl rand -hex 32)"
add_if_missing "DIFY_SECRET_KEY"            "$(openssl rand -hex 32)"
add_if_missing "DIFY_DB_PASSWORD"           "$(openssl rand -hex 16)"
add_if_missing "SEARXNG_SECRET_KEY"         "$(openssl rand -hex 32)"
add_if_missing "N8N_ENCRYPTION_KEY"         "$(openssl rand -hex 32)"
add_if_missing "N8N_DB_PASSWORD"            "$(openssl rand -hex 16)"
add_if_missing "AUTHENTIK_SECRET_KEY"       "$(openssl rand -hex 32)"
add_if_missing "AUTHENTIK_DB_PASSWORD"      "$(openssl rand -hex 16)"

echo ""
echo "=== FINAL ENV COUNTS ==="
echo "Total vars: $(wc -l < $ENV)"
echo "Empty vals: $(grep "^[^#].*=$" $ENV | wc -l)"
```

**GATE:** Zero empty values before proceeding.

---

## PHASE 2: Volume Creation With Correct Ownership

This is the single most important phase. Every permission error in the diagnosis traces to this being skipped or wrong.

```bash
#!/bin/bash
DATA=/mnt/data/datasquiz

# Format: "path" "uid:gid" "notes"
create_volume() {
    local path=$1 owner=$2
    sudo mkdir -p "$path"
    sudo chown -R "$owner" "$path"
    sudo chmod -R 755 "$path"
    echo "OK: $path ($owner)"
}

echo "=== VOLUME CREATION ==="

# Infrastructure (runs as root)
create_volume "$DATA/caddy/data"              "0:0"
create_volume "$DATA/caddy/config"            "0:0"
create_volume "$DATA/postgres"               "999:999"    # postgres official image UID
create_volume "$DATA/redis"                  "999:999"    # redis official image UID

# Applications (UID 1000 — standard non-root)
create_volume "$DATA/n8n"                    "1000:1000"
create_volume "$DATA/openwebui"              "1000:1000"
create_volume "$DATA/flowise"                "1000:1000"
create_volume "$DATA/flowise/logs"           "1000:1000"
create_volume "$DATA/flowise/storage"        "1000:1000"
create_volume "$DATA/anythingllm/storage"    "1000:1000"
create_volume "$DATA/litellm"                "1000:1000"
create_volume "$DATA/dify/storage"           "1000:1000"
create_volume "$DATA/dify/logs"              "1000:1000"
create_volume "$DATA/ollama"                 "1000:1000"
create_volume "$DATA/authentik/media"        "1000:1000"
create_volume "$DATA/authentik/certs"        "1000:1000"
create_volume "$DATA/grafana"                "472:472"    # grafana official image UID — NOT 1000

# Monitoring (specific UIDs from official images)
create_volume "$DATA/loki"                   "10001:10001" # loki official image UID
create_volume "$DATA/loki/data"              "10001:10001"
create_volume "$DATA/loki/data/chunks"       "10001:10001"
create_volume "$DATA/loki/data/rules"        "10001:10001"
create_volume "$DATA/loki/wal"               "10001:10001"
create_volume "$DATA/prometheus/data"        "65534:65534" # nobody — prometheus official

# SearXNG (977 inside container)
create_volume "$DATA/searxng"                "977:977"

# Tailscale
create_volume "$DATA/tailscale"              "0:0"

echo ""
echo "=== OWNERSHIP VERIFICATION ==="
ls -la $DATA/
```

**Critical UIDs that differ from 1000:**
- Grafana: **472**
- Loki: **10001**
- Prometheus: **65534** (nobody)
- SearXNG: **977**

Getting these wrong causes silent failures — container starts, appears healthy, but cannot write and crashes on first write attempt.

---

## PHASE 3: Configuration Files

All config files must exist **before** `docker compose up`. Containers that mount a config file at startup will fail if the file does not exist.

### 3.1 — LiteLLM config.yaml

```bash
sudo tee /mnt/data/datasquiz/litellm/config.yaml << 'EOF'
model_list:
  - model_name: ollama/llama3
    litellm_params:
      model: ollama/llama3
      api_base: http://ollama:11434

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/DATABASE_URL
  store_model_in_db: true

litellm_settings:
  drop_params: true
EOF
sudo chown 1000:1000 /mnt/data/datasquiz/litellm/config.yaml
```

### 3.2 — SearXNG settings.yml

```bash
DATA=/mnt/data/datasquiz
SEARXNG_SECRET=$(grep "^SEARXNG_SECRET_KEY=" $DATA/.env | cut -d= -f2-)

# Extract default config from image (avoids manual YAML writing)
sudo docker run --rm searxng/searxng:latest \
    cat /etc/searxng/settings.yml | sudo tee $DATA/searxng/settings.yml

# Inject secret key
sudo sed -i "s/ultrasecretkey/${SEARXNG_SECRET}/g" $DATA/searxng/settings.yml

# Set correct format for autocomplete and JSON output
sudo tee $DATA/searxng/limiter.toml << 'EOF'
[botdetection.ip_limit]
link_token = true
EOF

sudo chown -R 977:977 $DATA/searxng/

# Verify
grep "secret_key" $DATA/searxng/settings.yml
```

### 3.3 — Loki config.yaml

```bash
sudo tee /mnt/data/datasquiz/loki/config.yaml << 'EOF'
auth_enabled: false

server:
  http_listen_port: 3100

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
EOF
sudo chown 10001:10001 /mnt/data/datasquiz/loki/config.yaml
```

### 3.4 — Prometheus prometheus.yml

```bash
sudo tee /mnt/data/datasquiz/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ['localhost:9090']

  - job_name: caddy
    static_configs:
      - targets: ['caddy:2019']
EOF
# NOTE: Only add targets you have confirmed are running.
# Adding unreachable targets causes Prometheus to report unhealthy.
sudo chown 65534:65534 /mnt/data/datasquiz/prometheus/prometheus.yml
```

### 3.5 — Caddyfile

```bash
DOMAIN="ai.datasquiz.net"

sudo tee /mnt/data/datasquiz/caddy/Caddyfile << EOF
{
    admin 0.0.0.0:2019
    email admin@datasquiz.net
}

grafana.${DOMAIN} {
    reverse_proxy grafana:3000
}

n8n.${DOMAIN} {
    reverse_proxy n8n:5678
}

auth.${DOMAIN} {
    reverse_proxy authentik-server:9000
}

openwebui.${DOMAIN} {
    reverse_proxy openwebui:8080
}

flowise.${DOMAIN} {
    reverse_proxy flowise:3000
}

litellm.${DOMAIN} {
    reverse_proxy litellm:4000
}

anythingllm.${DOMAIN} {
    reverse_proxy anythingllm:3001
}

dify.${DOMAIN} {
    reverse_proxy /console/api/* dify-api:5001
    reverse_proxy /api/* dify-api:5001
    reverse_proxy /v1/* dify-api:5001
    reverse_proxy /files/* dify-api:5001
    reverse_proxy * dify-web:3000
}

searxng.${DOMAIN} {
    reverse_proxy searxng:8080
}

prometheus.${DOMAIN} {
    reverse_proxy prometheus:9090
}

loki.${DOMAIN} {
    reverse_proxy loki:3100
}
EOF
```

**Note on service names vs container names in Caddyfile:** On a Docker network, the service name (e.g., `grafana`) resolves via Docker's internal DNS. The container name (`ai-datasquiz-grafana-1`) also resolves. Use service names — they are cleaner and match docker-compose.yml service definitions.

---

## PHASE 4: docker-compose.yml — Complete Service Definitions

Every service below has been verified against the three model plans and the actual failure evidence. This is the complete set of changes.

### 4.1 — Networks Definition

```yaml
networks:
  ai-datasquiz-net:
    driver: bridge
  tailscale-net:
    driver: bridge
```

### 4.2 — Infrastructure Services (postgres, redis must have healthchecks)

```yaml
postgres:
  image: postgres:15
  container_name: ai-datasquiz-postgres-1
  restart: unless-stopped
  networks:
    - ai-datasquiz-net
  volumes:
    - /mnt/data/datasquiz/postgres:/var/lib/postgresql/data
  environment:
    - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    - POSTGRES_USER=postgres
    - POSTGRES_DB=postgres
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U postgres"]
    interval: 10s
    timeout: 5s
    retries: 5

redis:
  image: redis:7-alpine
  container_name: ai-datasquiz-redis-1
  restart: unless-stopped
  networks:
    - ai-datasquiz-net
  volumes:
    - /mnt/data/datasquiz/redis:/data
  command: redis-server --requirepass ${REDIS_PASSWORD}
  healthcheck:
    test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
    interval: 10s
    timeout: 5s
    retries: 5
```

### 4.3 — OpenWebUI

```yaml
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
    - OLLAMA_BASE_URL=http://ollama:11434
  depends_on:
    postgres:
      condition: service_healthy
```

### 4.4 — Flowise

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
    - APIKEY_PATH=/root/.flowise
  depends_on:
    postgres:
      condition: service_healthy
```

### 4.5 — LiteLLM

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
  command: ["--config", "/app/config.yaml", "--port", "4000"]
  depends_on:
    postgres:
      condition: service_healthy
```

### 4.6 — AnythingLLM

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
    - VECTOR_DB=lancedb
    - STORAGE_DIR=/app/server/storage
    - UID=1000
    - GID=1000
  depends_on:
    postgres:
      condition: service_healthy
```

### 4.7 — Dify (Three Containers)

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
    redis:
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
    redis:
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
  depends_on:
    - dify-api
```

### 4.8 — SearXNG

```yaml
searxng:
  image: searxng/searxng:latest
  container_name: ai-datasquiz-searxng-1
  restart: unless-stopped
  networks:
    - ai-datasquiz-net
  volumes:
    - /mnt/data/datasquiz/searxng:/etc/searxng:rw
  environment:
    - SEARXNG_BASE_URL=https://searxng.ai.datasquiz.net/
  # Note: secret key is in settings.yml, not env var for this image
```

### 4.9 — Loki

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

### 4.10 — Prometheus

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
    - --config.file=/etc/prometheus/prometheus.yml
    - --storage.tsdb.path=/prometheus
```

### 4.11 — Grafana (already working — preserve, add Loki datasource env)

```yaml
grafana:
  image: grafana/grafana:latest
  container_name: ai-datasquiz-grafana-1
  restart: unless-stopped
  user: "472:472"
  networks:
    - ai-datasquiz-net
  volumes:
    - /mnt/data/datasquiz/grafana:/var/lib/grafana
  environment:
    - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
    - GF_DATABASE_TYPE=postgres
    - GF_DATABASE_HOST=postgres:5432
    - GF_DATABASE_NAME=grafana
    - GF_DATABASE_USER=grafana
    - GF_DATABASE_PASSWORD=${GRAFANA_DB_PASSWORD:-${GRAFANA_PASSWORD}}
  depends_on:
    postgres:
      condition: service_healthy
```

### 4.12 — Ollama

```yaml
ollama:
  image: ollama/ollama:latest
  container_name: ai-datasquiz-ollama-1
  restart: unless-stopped
  networks:
    - ai-datasquiz-net
  volumes:
    - /mnt/data/datasquiz/ollama:/root/.ollama
  # GPU support — include only if GPU is available:
  # deploy:
  #   resources:
  #     reservations:
  #       devices:
  #         - driver: nvidia
  #           count: all
  #           capabilities: [gpu]
```

---

## PHASE 5: Database Provisioning

```bash
#!/bin/bash
# Run after postgres is healthy
DATA=/mnt/data/datasquiz
ENV=$DATA/.env
PG="ai-datasquiz-postgres-1"

get_env() { grep "^${1}=" "$ENV" | cut -d= -f2-; }

provision_db() {
    local db=$1 user=$2 pass=$3
    sudo docker exec $PG psql -U postgres << SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${user}') THEN
    CREATE USER ${user} WITH PASSWORD '${pass}';
  END IF;
END
\$\$;
SELECT 'CREATE DATABASE ${db} OWNER ${user}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${db}')\gexec
GRANT ALL PRIVILEGES ON DATABASE ${db} TO ${user};
SQL
    echo "Provisioned: $db ($user)"
}

# Wait for postgres
until sudo docker exec $PG pg_isready -U postgres; do
    echo "Waiting for postgres..."
    sleep 3
done

provision_db "n8n"         "n8n"         "$(get_env N8N_DB_PASSWORD)"
provision_db "authentik"   "authentik"   "$(get_env AUTHENTIK_DB_PASSWORD)"
provision_db "openwebui"   "openwebui"   "$(get_env OPENWEBUI_DB_PASSWORD)"
provision_db "flowise"     "flowise"     "$(get_env FLOWISE_DB_PASSWORD)"
provision_db "litellm"     "litellm"     "$(get_env LITELLM_DB_PASSWORD)"
provision_db "anythingllm" "anythingllm" "$(get_env ANYTHINGLLM_DB_PASSWORD)"
provision_db "dify"        "dify"        "$(get_env DIFY_DB_PASSWORD)"
provision_db "grafana"     "grafana"     "$(get_env GRAFANA_PASSWORD)"

echo ""
echo "=== All Databases ==="
sudo docker exec $PG psql -U postgres -c "\l" | grep -v "template\|postgres"
```

---

## PHASE 6: AnythingLLM SQLite Cleanup

```bash
# Must run BEFORE anythingllm container starts
sudo find /mnt/data/datasquiz/anythingllm/ -name "*.db" -delete 2>/dev/null
sudo find /mnt/data/datasquiz/anythingllm/ -name "*.sqlite" -delete 2>/dev/null
sudo chown -R 1000:1000 /mnt/data/datasquiz/anythingllm/
echo "AnythingLLM SQLite artifacts removed"
```

---

## PHASE 7: Startup Sequence

```bash
#!/bin/bash
COMPOSE=/mnt/data/datasquiz/docker-compose.yml

echo "=== STEP 1: Infrastructure ==="
sudo docker compose -f $COMPOSE up -d postgres redis
sleep 20

# Gate
sudo docker exec ai-datasquiz-postgres-1 pg_isready -U postgres || { echo "FATAL: postgres not ready"; exit 1; }
sudo docker exec ai-datasquiz-redis-1 redis-cli -a "$(grep REDIS_PASSWORD /mnt/data/datasquiz/.env | cut -d= -f2-)" ping | grep -q PONG || { echo "FATAL: redis not ready"; exit 1; }
echo "Infrastructure: OK"

echo "=== STEP 2: Database provisioning ==="
# Run provision_db block from Phase 5

echo "=== STEP 3: Caddy ==="
sudo docker compose -f $COMPOSE up -d caddy
sleep 5

echo "=== STEP 4: Auth services ==="
sudo docker compose -f $COMPOSE up -d authentik-server authentik-worker
sleep 15

echo "=== STEP 5: Application services ==="
sudo docker compose -f $COMPOSE up -d \
    n8n \
    openwebui \
    flowise \
    litellm \
    anythingllm \
    dify-api dify-worker dify-web \
    searxng \
    ollama

sleep 45

echo "=== STEP 6: Monitoring ==="
sudo docker compose -f $COMPOSE up -d loki prometheus grafana

sleep 20

echo "=== CONTAINER STATE ==="
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.RestartCount}}" | grep "ai-datasquiz"
```

---

## PHASE 8: Script 3 Modular Configuration

Script 3 must follow this pattern for every service. The following functions are the additions/fixes needed.

### wait_for_service helper (add to top of script 3 if not present):

```bash
wait_for_service() {
    local url=$1
    local timeout=${2:-60}
    local waited=0
    echo "Waiting for $url..."
    while ! curl -sf "$url" > /dev/null 2>&1; do
        sleep 3
        waited=$((waited + 3))
        if [ $waited -ge $timeout ]; then
            echo "TIMEOUT: $url not ready after ${timeout}s"
            return 1
        fi
    done
    echo "Ready: $url"
    return 0
}
```

### configure_ollama:

```bash
configure_ollama() {
    log "INFO" "Configuring Ollama..."
    wait_for_service "http://ollama:11434/api/tags" 60 || return 1

    # Pull base model in background — this takes 5-15 minutes
    sudo docker exec ai-datasquiz-ollama-1 ollama pull llama3.2:3b &
    local pull_pid=$!
    log "INFO" "Ollama: llama3.2:3b pull started (PID $pull_pid) — runs in background"
    log "INFO" "Monitor with: docker exec ai-datasquiz-ollama-1 ollama list"
}
```

### configure_litellm:

```bash
configure_litellm() {
    log "INFO" "Configuring LiteLLM..."
    local master_key
    master_key=$(get_env LITELLM_MASTER_KEY)

    wait_for_service "http://litellm:4000/health/liveliness" 90 || return 1
    log "SUCCESS" "LiteLLM ready — access with key: $master_key"
}
```

### configure_anythingllm:

```bash
configure_anythingllm() {
    log "INFO" "Configuring AnythingLLM..."
    wait_for_service "http://anythingllm:3001/api/ping" 90 || return 1

    # Set up via API only if not already configured
    local response
    response=$(curl -sf http://anythingllm:3001/api/v1/auth 2>/dev/null)
    if echo "$response" | grep -q "multi_user_mode"; then
        log "INFO" "AnythingLLM: already configured"
    else
        log "WARN" "AnythingLLM: requires manual setup at https://anythingllm.ai.datasquiz.net"
    fi
}
```

### configure_dify:

```bash
configure_dify() {
    log "INFO" "Configuring Dify..."
    wait_for_service "http://dify-api:5001/health" 120 || return 1
    wait_for_service "http://dify-web:3000" 60 || return 1
    log "SUCCESS" "Dify ready — complete setup at https://dify.ai.datasquiz.net"
}
```

---

## PHASE 9: Verification

```bash
#!/bin/bash
DOMAIN="ai.datasquiz.net"
DATA=/mnt/data/datasquiz

echo "============================================"
echo "PLATFORM VERIFICATION"
echo "============================================"

echo ""
echo "=== Container Health ==="
sudo docker ps --format "table {{.Names}}\t{{.Status}}" | grep "ai-datasquiz" | \
    awk '{
        if ($0 ~ /Up/) print "✓ " $0
        else if ($0 ~ /Restarting/) print "⚠ " $0
        else print "✗ " $0
    }'

echo ""
echo "=== Database Connectivity ==="
for svc in n8n openwebui flowise litellm anythingllm dify authentik grafana; do
    result=$(sudo docker exec ai-datasquiz-postgres-1 \
        psql -U postgres -c "\l" 2>/dev/null | grep "^$svc " | wc -l)
    [ "$result" -gt "0" ] && echo "✓ $svc DB exists" || echo "✗ $svc DB MISSING"
done

echo ""
echo "=== HTTP Endpoints ==="
declare -A expected=(
    ["grafana"]=302
    ["n8n"]=200
    ["auth"]=302
    ["openwebui"]=200
    ["flowise"]=200
    ["litellm"]=200
    ["anythingllm"]=200
    ["dify"]=200
    ["searxng"]=200
    ["prometheus"]=200
    ["loki"]=200
)
all_pass=true
for svc in "${!expected[@]}"; do
    code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "https://${svc}.${DOMAIN}")
    exp="${expected[$svc]}"
    if [ "$code" = "$exp" ] || [ "$code" = "200" ] || [ "$code" = "301" ] || [ "$code" = "302" ]; then
        echo "✓ $svc: HTTP $code"
    else
        echo "✗ $svc: HTTP $code (expected ~$exp)"
        all_pass=false
    fi
done

echo ""
if $all_pass; then
    echo "============================================"
    echo "ALL SERVICES HEALTHY"
    echo "============================================"
else
    echo "============================================"
    echo "FAILURES DETECTED — running log inspection"
    echo "============================================"
    for svc in "${!expected[@]}"; do
        code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 "https://${svc}.${DOMAIN}")
        if [ "$code" != "200" ] && [ "$code" != "301" ] && [ "$code" != "302" ]; then
            cname=$(sudo docker ps --format "{{.Names}}" | grep -i "$svc" | head -1)
            echo ""
            echo "--- LOGS: $svc ($cname) ---"
            [ -n "$cname" ] && sudo docker logs "$cname" --tail 25 2>&1 || echo "Container not found"
        fi
    done
fi
```

---

## Signal Bridge — Deferred (Correct Decision)

Signal bridge requires a manual step that cannot be automated:

1. Platform must be fully running
2. Run: `docker exec ai-datasquiz-signal-1 signal-cli -u +YOURNUMBER register`
3. Receive SMS with code
4. Run: `docker exec ai-datasquiz-signal-1 signal-cli -u +YOURNUMBER verify CODE`

This cannot happen until all other services are healthy. It is correctly excluded from automated deployment and belongs in a post-deployment runbook.

---

## Summary of Changes vs Each Model's Plan

| Fix | Claude | Windsurf | Gemini | This Plan |
|-----|--------|----------|--------|-----------|
| Grafana UID 472 | ✓ | ✗ | ✓ | ✓ |
| Loki UID 10001 | ✓ | ✗ | ✓ | ✓ |
| Prometheus UID 65534 | ✓ | ✗ | ✓ | ✓ |
| SearXNG UID 977 | ✓ | ✗ | ✓ | ✓ |
| Flowise `user: "1000:1000"` | ✓ | ✗ | ✓ | ✓ |
| AnythingLLM SQLite cleanup | ✓ | ✓ | ✓ | ✓ |
| Dify 3-container split | ✓ | ✗ | ✓ | ✓ |
| Dify Caddy path routing | ✓ | ✗ | ✗ | ✓ |
| LiteLLM config.yaml pre-create | ✓ | ✓ | ✓ | ✓ |
| SearXNG extract from image | ✗ | ✗ | ✗ | ✓ |
| postgres/redis healthchecks | ✓ | ✓ | ✓ | ✓ |
| Script 3 wait_for_service | ✗ | ✗ | ✓ | ✓ |
| DB provisioning idempotent | ✓ | ✓ | ✓ | ✓ |
| Stop before edit enforcement | ✗ | ✓ | ✓ | ✓ |
| Prometheus minimal scrape config | ✓ | ✗ | ✓ | ✓ |