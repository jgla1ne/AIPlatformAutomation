# Windsurf Instructions: AI Platform Automation - Critical Fix Implementation

## Context
You are working on an AI Platform Automation system. The codebase is at:
- `scripts/1-setup-system.sh`
- `scripts/2-deploy-services.sh`
- `scripts/3-configure-services.sh`

**Current state: 22% functional. 6/8 services in restart loops. Do NOT deploy anything until all fixes are applied.**

---

## PHASE 1: Read & Understand Current State First

```
Open and read these files completely before making any changes:
1. scripts/1-setup-system.sh
2. scripts/2-deploy-services.sh
3. scripts/3-configure-services.sh
4. README.md
5. Any .env or .env.example files in the repo root
6. Any docker-compose.yml files present

Do not modify anything yet. Just read and confirm you understand the structure.
```

---

## PHASE 2: Fix `scripts/1-setup-system.sh` — Permission Framework

### Task 2.1 — Add strict error handling at the top if not present
```
In scripts/1-setup-system.sh, ensure the very first executable lines are:

set -euo pipefail
trap 'echo "[ERROR] Script failed on line $LINENO. Exit code: $?" | tee -a /tmp/ai-platform-setup.log' ERR

LOG_FILE="/tmp/ai-platform-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] Starting system setup..."
```

### Task 2.2 — Add or fix the DATA_ROOT variable
```
Find the variable that defines the base data path. It should be:

DATA_ROOT="${DATA_ROOT:-/mnt/data/datasquiz}"

If it is hardcoded anywhere else in the script, replace with this variable reference.
```

### Task 2.3 — Add complete directory creation with correct ownership
```
Find the section where directories are created (likely mkdir commands).
Replace or augment it with the following complete block.
Insert AFTER the DATA_ROOT variable is defined:

# --- Directory Structure Creation ---
echo "[INFO] Creating directory structure under $DATA_ROOT"

declare -A SERVICE_DIRS=(
  ["grafana"]="$DATA_ROOT/grafana/data $DATA_ROOT/grafana/logs $DATA_ROOT/grafana/plugins"
  ["prometheus"]="$DATA_ROOT/prometheus/data"
  ["qdrant"]="$DATA_ROOT/qdrant/storage $DATA_ROOT/qdrant/storage/snapshots"
  ["openwebui"]="$DATA_ROOT/openwebui/data"
  ["litellm"]="$DATA_ROOT/litellm/data"
  ["postgres"]="$DATA_ROOT/postgres/data"
  ["redis"]="$DATA_ROOT/redis/data"
  ["caddy"]="$DATA_ROOT/caddy/data $DATA_ROOT/caddy/config"
  ["n8n"]="$DATA_ROOT/n8n/data"
  ["flowise"]="$DATA_ROOT/flowise/data"
  ["anythingllm"]="$DATA_ROOT/anythingllm/data"
)

for service in "${!SERVICE_DIRS[@]}"; do
  for dir in ${SERVICE_DIRS[$service]}; do
    mkdir -p "$dir"
    echo "[INFO] Created: $dir"
  done
done
```

### Task 2.4 — Add correct ownership assignments IMMEDIATELY after directory creation
```
Add this block directly after the directory creation block above.
These UIDs match the official container images exactly - do not change them:

# --- Permission Framework (UID must match container image expectations) ---
echo "[INFO] Applying permission framework..."

# Grafana runs as UID 472, GID 472
chown -R 472:472 "$DATA_ROOT/grafana"
chmod -R 755 "$DATA_ROOT/grafana"

# Prometheus runs as UID 65534 (nobody)
chown -R 65534:65534 "$DATA_ROOT/prometheus"
chmod -R 755 "$DATA_ROOT/prometheus"

# Qdrant runs as UID 1000, GID 1001
chown -R 1000:1001 "$DATA_ROOT/qdrant"
chmod -R 755 "$DATA_ROOT/qdrant"
# Snapshots directory needs write permission
chmod 775 "$DATA_ROOT/qdrant/storage/snapshots"

# OpenWebUI runs as UID 1000
chown -R 1000:1000 "$DATA_ROOT/openwebui"
chmod -R 755 "$DATA_ROOT/openwebui"

# LiteLLM runs as UID 1000
chown -R 1000:1000 "$DATA_ROOT/litellm"
chmod -R 755 "$DATA_ROOT/litellm"

# PostgreSQL runs as UID 999
chown -R 999:999 "$DATA_ROOT/postgres"
chmod -R 700 "$DATA_ROOT/postgres/data"

# Redis runs as UID 999
chown -R 999:999 "$DATA_ROOT/redis"
chmod -R 755 "$DATA_ROOT/redis"

# Caddy runs as UID 0 (root) internally but we set safe defaults
chown -R root:root "$DATA_ROOT/caddy"
chmod -R 755 "$DATA_ROOT/caddy"

# N8N runs as UID 1000
chown -R 1000:1000 "$DATA_ROOT/n8n"
chmod -R 755 "$DATA_ROOT/n8n"

# Flowise runs as UID 1000
chown -R 1000:1000 "$DATA_ROOT/flowise"
chmod -R 755 "$DATA_ROOT/flowise"

# AnythingLLM runs as UID 1000
chown -R 1000:1000 "$DATA_ROOT/anythingllm"
chmod -R 755 "$DATA_ROOT/anythingllm"

echo "[INFO] Permission framework applied successfully."
```

### Task 2.5 — Add system resource validation
```
Find where system checks or validations occur. Add or replace with:

# --- System Resource Validation ---
echo "[INFO] Validating system resources..."

REQUIRED_RAM_GB=4
REQUIRED_DISK_GB=20

AVAILABLE_RAM_GB=$(awk '/MemAvailable/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
AVAILABLE_DISK_GB=$(df -BG "$DATA_ROOT" 2>/dev/null | awk 'NR==2 {gsub("G",""); print $4}' || df -BG / | awk 'NR==2 {gsub("G",""); print $4}')

echo "[INFO] Available RAM: ${AVAILABLE_RAM_GB}GB (Required: ${REQUIRED_RAM_GB}GB)"
echo "[INFO] Available Disk: ${AVAILABLE_DISK_GB}GB (Required: ${REQUIRED_DISK_GB}GB)"

if [[ $AVAILABLE_RAM_GB -lt $REQUIRED_RAM_GB ]]; then
  echo "[WARN] Low RAM detected. AI services may be unstable."
fi

if [[ $AVAILABLE_DISK_GB -lt $REQUIRED_DISK_GB ]]; then
  echo "[ERROR] Insufficient disk space. At least ${REQUIRED_DISK_GB}GB required."
  exit 1
fi
```

---

## PHASE 3: Fix `scripts/2-deploy-services.sh` — Health Checks & Compose

### Task 3.1 — Add strict error handling at the top if not present
```
In scripts/2-deploy-services.sh, ensure the very first executable lines are:

set -euo pipefail
trap 'echo "[ERROR] Deployment failed on line $LINENO. Exit code: $?" | tee -a /tmp/ai-platform-deploy.log' ERR

LOG_FILE="/tmp/ai-platform-deploy.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] Starting service deployment..."
```

### Task 3.2 — Fix Prometheus health check
```
Find the Prometheus service definition in the docker-compose generation section.
The healthcheck block currently uses wget. Replace it entirely with:

healthcheck:
  test: ["CMD", "curl", "--fail", "--silent", "--max-time", "5", "http://localhost:9090/-/healthy"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 30s

If curl is also not guaranteed in the Prometheus image, use the HTTP check alternative:
  test: ["CMD-SHELL", "curl -sf http://localhost:9090/-/healthy || exit 1"]

Note: The prom/prometheus image includes wget in some versions but not all.
Using curl-based check OR removing the wget dependency is the correct fix.
If the image is prom/prometheus:latest, replace wget with:
  test: ["CMD-SHELL", "wget -q --spider http://localhost:9090/-/healthy 2>/dev/null || curl -sf http://localhost:9090/-/healthy || exit 1"]
```

### Task 3.3 — Fix LiteLLM health check
```
Find the LiteLLM service definition in the docker-compose generation section.
The /health endpoint does not exist. Replace the healthcheck with:

healthcheck:
  test: ["CMD", "curl", "--fail", "--silent", "--max-time", "10", "http://localhost:4000/v1/models"]
  interval: 30s
  timeout: 15s
  retries: 5
  start_period: 60s

If /v1/models also proves unreliable during testing, use this fallback:
  test: ["CMD-SHELL", "curl -sf http://localhost:4000/ > /dev/null 2>&1 || exit 1"]
```

### Task 3.4 — Fix Qdrant health check
```
Find the Qdrant service definition in the docker-compose generation section.
The /readyz endpoint is wrong. Replace the healthcheck with:

healthcheck:
  test: ["CMD", "curl", "--fail", "--silent", "--max-time", "5", "http://localhost:6333/"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 30s
```

### Task 3.5 — Fix Grafana health check and add environment variables
```
Find the Grafana service definition.

1. Verify the healthcheck uses the correct endpoint:
healthcheck:
  test: ["CMD", "curl", "--fail", "--silent", "--max-time", "5", "http://localhost:3000/api/health"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 45s

2. Ensure these environment variables are set in the Grafana service definition:
  environment:
    - GF_PATHS_DATA=/var/lib/grafana
    - GF_PATHS_LOGS=/var/log/grafana
    - GF_PATHS_PLUGINS=/var/lib/grafana/plugins
    - GF_DATABASE_TYPE=sqlite3
    - GF_DATABASE_PATH=/var/lib/grafana/grafana.db
    - GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER:-admin}
    - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}

3. Verify the volume mount maps to the correct internal path:
  volumes:
    - ${DATA_ROOT}/grafana/data:/var/lib/grafana
    - ${DATA_ROOT}/grafana/logs:/var/log/grafana
    - ${DATA_ROOT}/grafana/plugins:/var/lib/grafana/plugins
```

### Task 3.6 — Fix the Caddy dependency chain
```
Find the Caddy service definition in the compose generation.
Replace the depends_on section with a condition that doesn't block forever:

depends_on:
  postgres:
    condition: service_healthy
  redis:
    condition: service_healthy

Remove any depends_on entries for services that use restart loops
(grafana, prometheus, qdrant, openwebui, litellm).

Caddy is a reverse proxy. It can start independently and will route to
services as they become available. It does NOT need to wait for all
upstream services to be healthy before starting.

If the current implementation uses a script to wait for services,
replace the wait condition with a simple:
  restart: unless-stopped
```

### Task 3.7 — Add a pre-deployment validation function
```
Find where docker compose up is called. Add this validation BEFORE the compose up command:

# --- Pre-deployment Validation ---
echo "[INFO] Running pre-deployment validation..."

validate_env_var() {
  local var_name="$1"
  local var_value="${!var_name:-}"
  if [[ -z "$var_value" ]]; then
    echo "[ERROR] Required environment variable $var_name is not set."
    return 1
  fi
  echo "[OK] $var_name is set."
  return 0
}

VALIDATION_FAILED=0

REQUIRED_VARS=(
  "POSTGRES_PASSWORD"
  "REDIS_PASSWORD"
  "GRAFANA_ADMIN_PASSWORD"
  "LITELLM_MASTER_KEY"
  "LITELLM_SALT_KEY"
  "QDRANT_API_KEY"
  "DATA_ROOT"
)

for var in "${REQUIRED_VARS[@]}"; do
  validate_env_var "$var" || VALIDATION_FAILED=1
done

if [[ $VALIDATION_FAILED -eq 1 ]]; then
  echo "[ERROR] One or more required environment variables are missing."
  echo "[ERROR] Run scripts/3-configure-services.sh first to generate them."
  exit 1
fi

echo "[INFO] All required environment variables present."
```

### Task 3.8 — Fix the deploy order to be explicit
```
Find where docker compose up is executed.
Replace any single "docker compose up -d" call with an ordered startup:

# --- Ordered Service Startup ---
echo "[INFO] Starting core infrastructure services..."
docker compose up -d postgres redis
echo "[INFO] Waiting for core services to be healthy..."

# Wait for postgres
TIMEOUT=60
ELAPSED=0
until docker compose exec -T postgres pg_isready -U "${POSTGRES_USER:-postgres}" > /dev/null 2>&1; do
  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    echo "[ERROR] PostgreSQL failed to become ready within ${TIMEOUT}s"
    exit 1
  fi
  echo "[INFO] Waiting for PostgreSQL... (${ELAPSED}s/${TIMEOUT}s)"
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done
echo "[OK] PostgreSQL is ready."

# Wait for redis
ELAPSED=0
until docker compose exec -T redis redis-cli ping > /dev/null 2>&1; do
  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    echo "[ERROR] Redis failed to become ready within ${TIMEOUT}s"
    exit 1
  fi
  echo "[INFO] Waiting for Redis... (${ELAPSED}s/${TIMEOUT}s)"
  sleep 3
  ELAPSED=$((ELAPSED + 3))
done
echo "[OK] Redis is ready."

echo "[INFO] Starting application services..."
docker compose up -d grafana prometheus qdrant openwebui litellm

echo "[INFO] Waiting 30s for application services to initialize..."
sleep 30

echo "[INFO] Starting reverse proxy..."
docker compose up -d caddy

echo "[INFO] Deployment complete. Checking service status..."
docker compose ps
```

---

## PHASE 4: Fix `scripts/3-configure-services.sh` — Environment Variables

### Task 4.1 — Add strict error handling at the top if not present
```
In scripts/3-configure-services.sh, ensure the very first executable lines are:

set -euo pipefail
trap 'echo "[ERROR] Configuration failed on line $LINENO. Exit code: $?" | tee -a /tmp/ai-platform-config.log' ERR

LOG_FILE="/tmp/ai-platform-config.log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] Starting service configuration..."
```

### Task 4.2 — Add complete environment variable generation
```
Find where .env file is written or environment variables are generated.
Add the following complete block. Use append-or-set pattern to avoid 
overwriting values the user has already configured:

ENV_FILE="${ENV_FILE:-.env}"

# Helper: set a variable only if not already defined in .env
set_env_if_missing() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
    echo "[SKIP] $key already set in $ENV_FILE"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
    echo "[SET]  $key added to $ENV_FILE"
  fi
}

echo "[INFO] Ensuring all required environment variables are present in $ENV_FILE"
touch "$ENV_FILE"

# Core paths
set_env_if_missing "DATA_ROOT" "/mnt/data/datasquiz"
set_env_if_missing "COMPOSE_PROJECT_NAME" "ai-platform"

# PostgreSQL
set_env_if_missing "POSTGRES_USER" "aiplatform"
set_env_if_missing "POSTGRES_DB" "aiplatform"
set_env_if_missing "POSTGRES_PASSWORD" "$(openssl rand -hex 24)"

# Redis
set_env_if_missing "REDIS_PASSWORD" "$(openssl rand -hex 24)"

# Grafana
set_env_if_missing "GRAFANA_ADMIN_USER" "admin"
set_env_if_missing "GRAFANA_ADMIN_PASSWORD" "$(openssl rand -hex 16)"

# LiteLLM
set_env_if_missing "LITELLM_MASTER_KEY" "sk-$(openssl rand -hex 32)"
set_env_if_missing "LITELLM_SALT_KEY" "$(openssl rand -hex 32)"

# Qdrant
set_env_if_missing "QDRANT_API_KEY" "$(openssl rand -hex 32)"

# Flowise
set_env_if_missing "FLOWISE_SECRET_KEY" "$(openssl rand -hex 32)"
set_env_if_missing "FLOWISE_PASSWORD" "$(openssl rand -hex 16)"

# AnythingLLM
set_env_if_missing "ANYTHINGLLM_JWT_SECRET" "$(openssl rand -hex 32)"

# N8N
set_env_if_missing "N8N_ENCRYPTION_KEY" "$(openssl rand -hex 32)"
set_env_if_missing "N8N_USER_MANAGEMENT_JWT_SECRET" "$(openssl rand -hex 32)"

# Authentik
set_env_if_missing "AUTHENTIK_SECRET_KEY" "$(openssl rand -hex 50)"
set_env_if_missing "AUTHENTIK_POSTGRES_DB" "authentik"
set_env_if_missing "AUTHENTIK_POSTGRES_USER" "authentik"
set_env_if_missing "AUTHENTIK_POSTGRES_PASSWORD" "$(openssl rand -hex 24)"

echo "[INFO] Environment variable generation complete."
echo "[INFO] Review $ENV_FILE before proceeding."
```

### Task 4.3 — Add post-deployment health verification
```
At the END of scripts/3-configure-services.sh, after all configuration,
add this health verification block:

# --- Post-Deployment Health Verification ---
echo ""
echo "================================================"
echo " POST-DEPLOYMENT HEALTH VERIFICATION"
echo "================================================"

SERVICES=("postgres" "redis" "grafana" "prometheus" "qdrant" "openwebui" "litellm" "caddy")
ALL_HEALTHY=true

for service in "${SERVICES[@]}"; do
  STATUS=$(docker compose ps --format json "$service" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Health', d.get('State', 'unknown')))" 2>/dev/null || echo "unknown")
  
  if [[ "$STATUS" == "healthy" ]] || [[ "$STATUS" == "running" ]]; then
    echo "[✅] $service: $STATUS"
  else
    echo "[❌] $service: $STATUS"
    ALL_HEALTHY=false
  fi
done

echo ""
if $ALL_HEALTHY; then
  echo "[SUCCESS] All services are healthy."
else
  echo "[WARNING] Some services are not healthy."
  echo "[INFO] Check logs with: docker compose logs [service-name]"
  echo "[INFO] Check status with: docker compose ps"
fi

echo ""
echo "================================================"
echo " CONFIGURED CREDENTIALS LOCATION: $ENV_FILE"
echo " LOGS: /tmp/ai-platform-config.log"
echo "================================================"
```

---

## PHASE 5: Create a New Emergency Fix Script

### Task 5.1 — Create `scripts/0-emergency-fix.sh`
```
Create a NEW file at scripts/0-emergency-fix.sh with exactly this content:

#!/usr/bin/env bash
# Emergency fix script for restart loop recovery
# Run this when services are in restart loops
# Usage: sudo bash scripts/0-emergency-fix.sh

set -euo pipefail
trap 'echo "[ERROR] Emergency fix failed on line $LINENO"' ERR

DATA_ROOT="${DATA_ROOT:-/mnt/data/datasquiz}"

echo "================================================"
echo " EMERGENCY FIX: AI Platform Restart Loop Recovery"
echo " $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "================================================"
echo ""

# Step 1: Stop everything cleanly
echo "[STEP 1] Stopping all containers..."
docker compose down --remove-orphans 2>/dev/null || true
echo "[OK] All containers stopped."
echo ""

# Step 2: Apply permissions
echo "[STEP 2] Applying permission fixes..."

apply_permissions() {
  local dir="$1"
  local uid="$2"
  local gid="$3"
  local mode="${4:-755}"
  
  if [[ -d "$dir" ]]; then
    chown -R "${uid}:${gid}" "$dir"
    chmod -R "$mode" "$dir"
    echo "[OK] $dir -> ${uid}:${gid} (${mode})"
  else
    mkdir -p "$dir"
    chown -R "${uid}:${gid}" "$dir"
    chmod -R "$mode" "$dir"
    echo "[CREATED] $dir -> ${uid}:${gid} (${mode})"
  fi
}

apply_permissions "$DATA_ROOT/grafana"         472   472   755
apply_permissions "$DATA_ROOT/grafana/data"    472   472   755
apply_permissions "$DATA_ROOT/grafana/logs"    472   472   755
apply_permissions "$DATA_ROOT/grafana/plugins" 472   472   755
apply_permissions "$DATA_ROOT/prometheus"      65534 65534 755
apply_permissions "$DATA_ROOT/prometheus/data" 65534 65534 755
apply_permissions "$DATA_ROOT/qdrant"          1000  1001  755
apply_permissions "$DATA_ROOT/qdrant/storage"  1000  1001  755
apply_permissions "$DATA_ROOT/qdrant/storage/snapshots" 1000 1001 775
apply_permissions "$DATA_ROOT/openwebui"       1000  1000  755
apply_permissions "$DATA_ROOT/litellm"         1000  1000  755
apply_permissions "$DATA_ROOT/n8n"             1000  1000  755
apply_permissions "$DATA_ROOT/flowise"         1000  1000  755
apply_permissions "$DATA_ROOT/anythingllm"     1000  1000  755
apply_permissions "$DATA_ROOT/postgres"        999   999   700
apply_permissions "$DATA_ROOT/redis"           999   999   755
apply_permissions "$DATA_ROOT/caddy"           0     0     755

echo ""
echo "[STEP 2] Permissions applied."
echo ""

# Step 3: Verify .env completeness
echo "[STEP 3] Checking .env file..."
ENV_FILE="${ENV_FILE:-.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[ERROR] .env file not found at $ENV_FILE"
  echo "[ERROR] Run scripts/3-configure-services.sh first"
  exit 1
fi

MISSING_VARS=()
REQUIRED_VARS=(
  "POSTGRES_PASSWORD"
  "REDIS_PASSWORD" 
  "GRAFANA_ADMIN_PASSWORD"
  "LITELLM_MASTER_KEY"
  "LITELLM_SALT_KEY"
  "QDRANT_API_KEY"
  "DATA_ROOT"
)

for var in "${REQUIRED_VARS[@]}"; do
  if ! grep -q "^${var}=" "$ENV_FILE"; then
    MISSING_VARS+=("$var")
  fi
done

if [[ ${#MISSING_VARS[@]} -gt 0 ]]; then
  echo "[WARNING] Missing variables in .env:"
  for var in "${MISSING_VARS[@]}"; do
    echo "  - $var"
  done
  echo "[INFO] Run scripts/3-configure-services.sh to auto-generate missing values"
  echo ""
  read -r -p "Continue anyway? [y/N] " response
  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    exit 1
  fi
else
  echo "[OK] All required variables present in $ENV_FILE"
fi

echo ""

# Step 4: Start in correct order
echo "[STEP 4] Starting services in dependency order..."
echo ""

echo "[INFO] Starting: postgres, redis"
docker compose up -d postgres redis

echo "[INFO] Waiting for PostgreSQL to be ready (max 60s)..."
TIMEOUT=60
ELAPSED=0
until docker compose exec -T postgres pg_isready -U "${POSTGRES_USER:-aiplatform}" > /dev/null 2>&1; do
  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    echo "[ERROR] PostgreSQL did not become ready. Check: docker compose logs postgres"
    exit 1
  fi
  sleep 3
  ELAPSED=$((ELAPSED + 3))
  echo "  ... ${ELAPSED}s"
done
echo "[OK] PostgreSQL ready."

echo "[INFO] Waiting for Redis to be ready (max 30s)..."
TIMEOUT=30
ELAPSED=0
until docker compose exec -T redis redis-cli ping > /dev/null 2>&1; do
  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    echo "[ERROR] Redis did not become ready. Check: docker compose logs redis"
    exit 1
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
  echo "  ... ${ELAPSED}s"
done
echo "[OK] Redis ready."

echo ""
echo "[INFO] Starting application services..."
docker compose up -d grafana prometheus qdrant openwebui litellm

echo "[INFO] Allowing 45s for application services to initialize..."
sleep 45

echo ""
echo "[INFO] Starting reverse proxy..."
docker compose up -d caddy

echo ""
echo "================================================"
echo " FINAL SERVICE STATUS"
echo "================================================"
docker compose ps
echo ""

echo "================================================"
echo " EMERGENCY FIX COMPLETE"
echo " Monitor with: watch -n 5 docker compose ps"
echo " View logs with: docker compose logs -f [service]"
echo "================================================"
```

Make the file executable:
chmod +x scripts/0-emergency-fix.sh
```

---

## PHASE 6: Validation & Testing Instructions for Windsurf

```
After making ALL changes above, perform these validation steps:

1. VERIFY all scripts have `set -euo pipefail` as first executable line
   - Check: scripts/1-setup-system.sh
   - Check: scripts/2-deploy-services.sh  
   - Check: scripts/3-configure-services.sh
   - Check: scripts/0-emergency-fix.sh

2. VERIFY health check fixes are in place in script 2:
   - Prometheus: uses curl, NOT wget
   - LiteLLM: uses /v1/models endpoint, NOT /health
   - Qdrant: uses / endpoint, NOT /readyz
   - Grafana: uses /api/health endpoint

3. VERIFY permission assignments in script 1:
   - Grafana: 472:472
   - Prometheus: 65534:65534
   - Qdrant: 1000:1001
   - OpenWebUI: 1000:1000
   - PostgreSQL: 999:999

4. VERIFY these variables are generated in script 3:
   - AUTHENTIK_SECRET_KEY
   - LITELLM_MASTER_KEY
   - LITELLM_SALT_KEY
   - QDRANT_API_KEY
   - FLOWISE_SECRET_KEY
   - ANYTHINGLLM_JWT_SECRET
   - N8N_ENCRYPTION_KEY

5. VERIFY Caddy depends_on only postgres and redis, not all services

6. VERIFY 0-emergency-fix.sh exists and is executable

7. DO NOT run any scripts. Only make the code changes.
   The user will run: sudo bash scripts/0-emergency-fix.sh
   as the first step after your changes are complete.
```

---

## Summary of Changes Made

| File | Changes |
|------|---------|
| `scripts/1-setup-system.sh` | Error handling, DATA_ROOT var, directory creation, permission framework, resource validation |
| `scripts/2-deploy-services.sh` | Error handling, health check fixes (4 services), Caddy dependency fix, ordered startup, pre-deploy validation |
| `scripts/3-configure-services.sh` | Error handling, complete env var generation (10+ vars), post-deploy health verification |
| `scripts/0-emergency-fix.sh` | **NEW FILE** — Emergency recovery: stop → fix permissions → validate env → ordered startup |
# Windsurf Instructions: Phase 2 — Deep Fix & Hardening

## Context Reminder
You have completed Phase 1 fixes. Now implement deep hardening, missing service configurations, monitoring, and self-healing. **Still do not run anything.**

---

## PHASE 7: Complete Docker Compose Service Definitions

### Task 7.1 — Audit all service definitions for missing required fields
```
In scripts/2-deploy-services.sh, find where docker-compose content is generated.
For EVERY service block, verify these fields exist. Add any that are missing:

Required fields for every service:
  - image: (pinned version tag, NOT :latest where possible)
  - container_name: (explicit name)
  - restart: unless-stopped
  - healthcheck: (correct endpoint per Phase 1 fixes)
  - logging: (with size limits)
  - networks: (ai-platform network)
  - environment: (no hardcoded secrets, all from ${VAR})
  - volumes: (all under ${DATA_ROOT})
  - labels: (for Caddy routing)
```

### Task 7.2 — Add logging limits to every service
```
Find every service definition in the compose generation.
Add this logging block to EVERY service that is missing it:

    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
        tag: "{{.Name}}"

This prevents disk exhaustion from restart loops filling logs.
```

### Task 7.3 — Add resource limits to every service
```
Find every service definition in the compose generation.
Add deploy.resources limits to prevent any single service 
consuming all available RAM (7.635GiB total on this system):

For Grafana:
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
        reservations:
          memory: 128M

For Prometheus:
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
        reservations:
          memory: 128M

For Qdrant:
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '1.0'
        reservations:
          memory: 256M

For OpenWebUI:
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '1.0'
        reservations:
          memory: 256M

For LiteLLM:
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
        reservations:
          memory: 128M

For PostgreSQL:
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
        reservations:
          memory: 256M

For Redis:
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.25'
        reservations:
          memory: 64M

For Caddy:
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.25'
        reservations:
          memory: 64M

For N8N:
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
        reservations:
          memory: 128M

For Flowise:
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
        reservations:
          memory: 128M

For AnythingLLM:
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '1.0'
        reservations:
          memory: 256M
```

### Task 7.4 — Add complete network definition
```
Find the networks section at the bottom of the compose generation.
Replace or add:

networks:
  ai-platform:
    name: ai-platform
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
          gateway: 172.20.0.1

volumes:
  postgres_data:
    driver: local
  redis_data:
    driver: local
```

### Task 7.5 — Fix complete Grafana service definition
```
Find the Grafana service block in compose generation.
Replace the entire Grafana service definition with:

  grafana:
    image: grafana/grafana:10.4.2
    container_name: grafana
    restart: unless-stopped
    user: "472:472"
    environment:
      - GF_PATHS_DATA=/var/lib/grafana
      - GF_PATHS_LOGS=/var/log/grafana
      - GF_PATHS_PLUGINS=/var/lib/grafana/plugins
      - GF_DATABASE_TYPE=sqlite3
      - GF_DATABASE_PATH=/var/lib/grafana/grafana.db
      - GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER:-admin}
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
      - GF_SERVER_ROOT_URL=https://grafana.${DOMAIN}
      - GF_SERVER_DOMAIN=grafana.${DOMAIN}
      - GF_ANALYTICS_REPORTING_ENABLED=false
      - GF_ANALYTICS_CHECK_FOR_UPDATES=false
      - GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource
    volumes:
      - ${DATA_ROOT}/grafana/data:/var/lib/grafana
      - ${DATA_ROOT}/grafana/logs:/var/log/grafana
      - ${DATA_ROOT}/grafana/plugins:/var/lib/grafana/plugins
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "curl", "--fail", "--silent", "--max-time", "5", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 45s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
        reservations:
          memory: 128M
    labels:
      - "caddy=grafana.${DOMAIN}"
      - "caddy.reverse_proxy=:3000"
```

### Task 7.6 — Fix complete Prometheus service definition
```
Find the Prometheus service block in compose generation.
Replace the entire Prometheus service definition with:

  prometheus:
    image: prom/prometheus:v2.51.2
    container_name: prometheus
    restart: unless-stopped
    user: "65534:65534"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
      - '--storage.tsdb.retention.size=5GB'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--web.enable-lifecycle'
      - '--web.enable-admin-api'
    volumes:
      - ${DATA_ROOT}/prometheus/data:/prometheus
      - ${DATA_ROOT}/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost:9090/-/healthy 2>/dev/null || curl -sf http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
        reservations:
          memory: 128M
    labels:
      - "caddy=prometheus.${DOMAIN}"
      - "caddy.reverse_proxy=:9090"
```

### Task 7.7 — Fix complete Qdrant service definition
```
Find the Qdrant service block in compose generation.
Replace the entire Qdrant service definition with:

  qdrant:
    image: qdrant/qdrant:v1.9.2
    container_name: qdrant
    restart: unless-stopped
    user: "1000:1001"
    environment:
      - QDRANT__SERVICE__API_KEY=${QDRANT_API_KEY}
      - QDRANT__SERVICE__ENABLE_TLS=false
      - QDRANT__STORAGE__STORAGE_PATH=/qdrant/storage
      - QDRANT__STORAGE__SNAPSHOTS_PATH=/qdrant/storage/snapshots
      - QDRANT__LOG_LEVEL=INFO
    volumes:
      - ${DATA_ROOT}/qdrant/storage:/qdrant/storage
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "curl", "--fail", "--silent", "--max-time", "5", "http://localhost:6333/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '1.0'
        reservations:
          memory: 256M
    labels:
      - "caddy=qdrant.${DOMAIN}"
      - "caddy.reverse_proxy=:6333"
```

### Task 7.8 — Fix complete LiteLLM service definition
```
Find the LiteLLM service block in compose generation.
Replace the entire LiteLLM service definition with:

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      - LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
      - LITELLM_SALT_KEY=${LITELLM_SALT_KEY}
      - DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
      - REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379
      - STORE_MODEL_IN_DB=True
      - LITELLM_LOG=INFO
    volumes:
      - ${DATA_ROOT}/litellm/data:/app/data
      - ${DATA_ROOT}/litellm/config.yaml:/app/config.yaml:ro
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "curl", "--fail", "--silent", "--max-time", "10", "http://localhost:4000/v1/models"]
      interval: 30s
      timeout: 15s
      retries: 5
      start_period: 60s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
        reservations:
          memory: 128M
    labels:
      - "caddy=litellm.${DOMAIN}"
      - "caddy.reverse_proxy=:4000"
```

### Task 7.9 — Fix complete OpenWebUI service definition
```
Find the OpenWebUI service block in compose generation.
Replace the entire OpenWebUI service definition with:

  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: openwebui
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      - WEBUI_SECRET_KEY=${OPENWEBUI_SECRET_KEY}
      - DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/openwebui
      - WEBUI_URL=https://chat.${DOMAIN}
      - ENABLE_SIGNUP=${OPENWEBUI_ENABLE_SIGNUP:-false}
      - DEFAULT_LOCALE=en
      - LITELLM_API_BASE_URL=http://litellm:4000
      - LITELLM_API_KEY=${LITELLM_MASTER_KEY}
    volumes:
      - ${DATA_ROOT}/openwebui/data:/app/backend/data
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD", "curl", "--fail", "--silent", "--max-time", "10", "http://localhost:8080/health"]
      interval: 30s
      timeout: 15s
      retries: 5
      start_period: 60s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '1.0'
        reservations:
          memory: 256M
    labels:
      - "caddy=chat.${DOMAIN}"
      - "caddy.reverse_proxy=:8080"
```

---

## PHASE 8: Generate Missing Config Files

### Task 8.1 — Add Prometheus config generation to script 1
```
In scripts/1-setup-system.sh, find where config files are created
OR add a new section labeled "# --- Generate Service Config Files ---"

Add this block to generate the Prometheus config:

PROMETHEUS_CONFIG="$DATA_ROOT/prometheus/prometheus.yml"

if [[ ! -f "$PROMETHEUS_CONFIG" ]]; then
  echo "[INFO] Generating Prometheus configuration..."
  cat > "$PROMETHEUS_CONFIG" << 'PROMETHEUS_EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitor: 'ai-platform'

rule_files: []

alerting:
  alertmanagers:
    - static_configs:
        - targets: []

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

  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres-exporter:9187']

  - job_name: 'redis'
    static_configs:
      - targets: ['redis-exporter:9121']
PROMETHEUS_EOF

  chown 65534:65534 "$PROMETHEUS_CONFIG"
  chmod 644 "$PROMETHEUS_CONFIG"
  echo "[OK] Prometheus configuration created at $PROMETHEUS_CONFIG"
else
  echo "[SKIP] Prometheus configuration already exists."
fi
```

### Task 8.2 — Add LiteLLM config generation to script 1
```
In scripts/1-setup-system.sh, in the same config generation section, add:

LITELLM_CONFIG="$DATA_ROOT/litellm/config.yaml"

if [[ ! -f "$LITELLM_CONFIG" ]]; then
  echo "[INFO] Generating LiteLLM configuration..."
  cat > "$LITELLM_CONFIG" << 'LITELLM_EOF'
model_list:
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY

  - model_name: gpt-4o-mini
    litellm_params:
      model: openai/gpt-4o-mini
      api_key: os.environ/OPENAI_API_KEY

  - model_name: claude-3-5-sonnet
    litellm_params:
      model: anthropic/claude-3-5-sonnet-20241022
      api_key: os.environ/ANTHROPIC_API_KEY

  - model_name: ollama/llama3
    litellm_params:
      model: ollama/llama3
      api_base: http://ollama:11434

litellm_settings:
  drop_params: true
  set_verbose: false
  cache: true
  cache_params:
    type: redis
    host: redis
    port: 6379
    password: os.environ/REDIS_PASSWORD

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/DATABASE_URL
  store_model_in_db: true
LITELLM_EOF

  chown 1000:1000 "$LITELLM_CONFIG"
  chmod 644 "$LITELLM_CONFIG"
  echo "[OK] LiteLLM configuration created at $LITELLM_CONFIG"
else
  echo "[SKIP] LiteLLM configuration already exists."
fi
```

### Task 8.3 — Add Caddy config generation to script 1
```
In scripts/1-setup-system.sh, in the same config generation section, add:

CADDYFILE="$DATA_ROOT/caddy/Caddyfile"

if [[ ! -f "$CADDYFILE" ]]; then
  echo "[INFO] Generating Caddyfile..."
  
  # Load DOMAIN from .env if not already in environment
  if [[ -z "${DOMAIN:-}" ]]; then
    if [[ -f ".env" ]]; then
      DOMAIN=$(grep "^DOMAIN=" .env | cut -d'=' -f2 | tr -d '"' | tr -d "'")
    fi
    DOMAIN="${DOMAIN:-localhost}"
  fi
  
  cat > "$CADDYFILE" << CADDY_EOF
{
  admin :2019
  email admin@${DOMAIN}
  
  # Global TLS settings
  acme_ca https://acme-v02.api.letsencrypt.org/directory
}

# Health check endpoint
:2019 {
  metrics /metrics
}

# OpenWebUI - Main chat interface
chat.${DOMAIN} {
  reverse_proxy openwebui:8080 {
    health_uri /health
    health_interval 30s
    health_timeout 10s
  }
  tls {
    protocols tls1.2 tls1.3
  }
  encode gzip
  log {
    output file /data/logs/chat-access.log {
      roll_size 10mb
      roll_keep 3
    }
  }
}

# Grafana - Monitoring
grafana.${DOMAIN} {
  reverse_proxy grafana:3000
  tls {
    protocols tls1.2 tls1.3
  }
  encode gzip
}

# Prometheus - Metrics
prometheus.${DOMAIN} {
  reverse_proxy prometheus:9090
  tls {
    protocols tls1.2 tls1.3
  }
  basicauth {
    admin {env.GRAFANA_ADMIN_PASSWORD_HASH}
  }
}

# LiteLLM - LLM Gateway
litellm.${DOMAIN} {
  reverse_proxy litellm:4000
  tls {
    protocols tls1.2 tls1.3
  }
  encode gzip
}

# Qdrant - Vector Database
qdrant.${DOMAIN} {
  reverse_proxy qdrant:6333
  tls {
    protocols tls1.2 tls1.3
  }
  encode gzip
}

# N8N - Workflow Automation
n8n.${DOMAIN} {
  reverse_proxy n8n:5678
  tls {
    protocols tls1.2 tls1.3
  }
  encode gzip
}

# Flowise - AI Workflows
flowise.${DOMAIN} {
  reverse_proxy flowise:3000
  tls {
    protocols tls1.2 tls1.3
  }
  encode gzip
}

# AnythingLLM
anythingllm.${DOMAIN} {
  reverse_proxy anythingllm:3001
  tls {
    protocols tls1.2 tls1.3
  }
  encode gzip
}
CADDY_EOF

  mkdir -p "$DATA_ROOT/caddy/logs"
  chown -R root:root "$DATA_ROOT/caddy"
  chmod 644 "$CADDYFILE"
  echo "[OK] Caddyfile created at $CADDYFILE"
else
  echo "[SKIP] Caddyfile already exists."
fi
```

---

## PHASE 9: Add Self-Healing & Monitoring Script

### Task 9.1 — Create `scripts/4-monitor-health.sh`
```
Create a NEW file at scripts/4-monitor-health.sh with exactly this content:

#!/usr/bin/env bash
# Continuous health monitoring and auto-recovery
# Usage: 
#   One-time check:  bash scripts/4-monitor-health.sh
#   Daemon mode:     bash scripts/4-monitor-health.sh --daemon
#   Install as cron: bash scripts/4-monitor-health.sh --install-cron

set -euo pipefail

DAEMON_MODE=false
INSTALL_CRON=false
CHECK_INTERVAL=60
MAX_RESTART_ATTEMPTS=3
ALERT_EMAIL="${ALERT_EMAIL:-}"
LOG_FILE="/var/log/ai-platform-health.log"
RESTART_TRACKER="/tmp/ai-platform-restart-counts"

# Parse arguments
for arg in "$@"; do
  case $arg in
    --daemon)     DAEMON_MODE=true ;;
    --install-cron) INSTALL_CRON=true ;;
    --interval=*) CHECK_INTERVAL="${arg#*=}" ;;
  esac
done

# --- Logging ---
log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp
  timestamp="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# --- Alert Function ---
send_alert() {
  local subject="$1"
  local body="$2"
  
  log "ALERT" "$subject"
  
  if [[ -n "$ALERT_EMAIL" ]] && command -v mail &>/dev/null; then
    echo "$body" | mail -s "[AI Platform] $subject" "$ALERT_EMAIL"
  fi
  
  # Write to alert file for external monitoring pickup
  echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $subject: $body" \
    >> /tmp/ai-platform-alerts.log
}

# --- Restart Counter ---
get_restart_count() {
  local service="$1"
  mkdir -p "$RESTART_TRACKER"
  local count_file="$RESTART_TRACKER/$service"
  if [[ -f "$count_file" ]]; then
    cat "$count_file"
  else
    echo "0"
  fi
}

increment_restart_count() {
  local service="$1"
  mkdir -p "$RESTART_TRACKER"
  local count_file="$RESTART_TRACKER/$service"
  local current
  current=$(get_restart_count "$service")
  echo $((current + 1)) > "$count_file"
}

reset_restart_count() {
  local service="$1"
  mkdir -p "$RESTART_TRACKER"
  echo "0" > "$RESTART_TRACKER/$service"
}

# --- Service Health Check ---
check_service_health() {
  local service="$1"
  local status
  
  status=$(docker compose ps --format json "$service" 2>/dev/null \
    | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list):
        data = data[0] if data else {}
    health = data.get('Health', '')
    state = data.get('State', 'unknown')
    if health == 'healthy':
        print('healthy')
    elif health == 'unhealthy':
        print('unhealthy')
    elif state == 'running' and health == '':
        print('running-no-healthcheck')
    elif state == 'restarting':
        print('restarting')
    elif state == 'exited':
        print('exited')
    else:
        print(f'unknown:{state}')
except Exception as e:
    print(f'error:{e}')
" 2>/dev/null || echo "not-running")
  
  echo "$status"
}

# --- Auto Recovery ---
attempt_recovery() {
  local service="$1"
  local issue="$2"
  
  local restart_count
  restart_count=$(get_restart_count "$service")
  
  if [[ $restart_count -ge $MAX_RESTART_ATTEMPTS ]]; then
    log "ERROR" "Service $service has failed $restart_count times. Manual intervention required."
    send_alert "CRITICAL: $service requires manual intervention" \
      "Service $service has been restarted $restart_count times and is still failing. Issue: $issue"
    return 1
  fi
  
  log "WARN" "Attempting recovery for $service (attempt $((restart_count + 1))/$MAX_RESTART_ATTEMPTS). Issue: $issue"
  
  # Apply permission fix before restart for known permission-sensitive services
  case "$service" in
    grafana)
      DATA_ROOT="${DATA_ROOT:-/mnt/data/datasquiz}"
      chown -R 472:472 "$DATA_ROOT/grafana" 2>/dev/null || true
      ;;
    qdrant)
      DATA_ROOT="${DATA_ROOT:-/mnt/data/datasquiz}"
      chown -R 1000:1001 "$DATA_ROOT/qdrant" 2>/dev/null || true
      chmod 775 "$DATA_ROOT/qdrant/storage/snapshots" 2>/dev/null || true
      ;;
    openwebui)
      DATA_ROOT="${DATA_ROOT:-/mnt/data/datasquiz}"
      chown -R 1000:1000 "$DATA_ROOT/openwebui" 2>/dev/null || true
      ;;
    prometheus)
      DATA_ROOT="${DATA_ROOT:-/mnt/data/datasquiz}"
      chown -R 65534:65534 "$DATA_ROOT/prometheus" 2>/dev/null || true
      ;;
  esac
  
  # Restart the service
  docker compose restart "$service" 2>/dev/null || docker compose up -d "$service" 2>/dev/null || true
  increment_restart_count "$service"
  
  # Wait and verify
  sleep 15
  local new_status
  new_status=$(check_service_health "$service")
  
  if [[ "$new_status" == "healthy" ]] || [[ "$new_status" == "running-no-healthcheck" ]]; then
    log "INFO" "Recovery successful for $service. Status: $new_status"
    reset_restart_count "$service"
    return 0
  else
    log "WARN" "Recovery attempt for $service did not resolve issue. Status: $new_status"
    return 1
  fi
}

# --- Main Health Check Loop ---
run_health_check() {
  local SERVICES=("postgres" "redis" "grafana" "prometheus" "qdrant" "openwebui" "litellm" "caddy")
  local issues_found=0
  
  log "INFO" "Running health check for ${#SERVICES[@]} services..."
  
  for service in "${SERVICES[@]}"; do
    local status
    status=$(check_service_health "$service")
    
    case "$status" in
      "healthy")
        log "INFO" "[$service] ✅ healthy"
        reset_restart_count "$service"
        ;;
      "running-no-healthcheck")
        log "INFO" "[$service] ✅ running (no healthcheck configured)"
        reset_restart_count "$service"
        ;;
      "restarting")
        log "WARN" "[$service] ⚠️  restarting - attempting recovery"
        issues_found=$((issues_found + 1))
        attempt_recovery "$service" "restart loop detected" || true
        ;;
      "unhealthy")
        log "WARN" "[$service] ❌ unhealthy - attempting recovery"
        issues_found=$((issues_found + 1))
        attempt_recovery "$service" "health check failing" || true
        ;;
      "exited")
        log "ERROR" "[$service] 💀 exited - attempting restart"
        issues_found=$((issues_found + 1))
        attempt_recovery "$service" "container exited unexpectedly" || true
        ;;
      "not-running")
        log "WARN" "[$service] ⚪ not running - skipping"
        ;;
      *)
        log "WARN" "[$service] ❓ unknown status: $status"
        ;;
    esac
  done
  
  if [[ $issues_found -eq 0 ]]; then
    log "INFO" "All services healthy. No action required."
  else
    log "WARN" "Found $issues_found service(s) with issues. Recovery attempted."
  fi
  
  # Log resource summary
  log "INFO" "Resource usage summary:"
  docker stats --no-stream --format \
    "  {{.Name}}: CPU={{.CPUPerc}} MEM={{.MemUsage}}" 2>/dev/null \
    | tee -a "$LOG_FILE" || true
}

# --- Install as Cron Job ---
install_cron() {
  local SCRIPT_PATH
  SCRIPT_PATH="$(realpath "$0")"
  local CRON_LINE="*/5 * * * * root bash $SCRIPT_PATH >> $LOG_FILE 2>&1"
  local CRON_FILE="/etc/cron.d/ai-platform-health"
  
  echo "$CRON_LINE" > "$CRON_FILE"
  chmod 644 "$CRON_FILE"
  
  log "INFO" "Health monitor installed as cron job at $CRON_FILE"
  log "INFO" "Runs every 5 minutes. Logs at $LOG_FILE"
  echo "[OK] Cron job installed. View with: cat $CRON_FILE"
}

# --- Daemon Mode ---
run_daemon() {
  log "INFO" "Starting health monitor daemon (interval: ${CHECK_INTERVAL}s)"
  while true; do
    run_health_check
    sleep "$CHECK_INTERVAL"
  done
}

# --- Entry Point ---
if $INSTALL_CRON; then
  install_cron
elif $DAEMON_MODE; then
  run_daemon
else
  run_health_check
fi
```

Make the file executable:
chmod +x scripts/4-monitor-health.sh
```

---

## PHASE 10: Add Missing Environment Variables to Script 3

### Task 10.1 — Add all remaining service variables
```
In scripts/3-configure-services.sh, find the set_env_if_missing block 
from Phase 4. Add these additional variables immediately after 
the existing ones:

# Domain configuration
set_env_if_missing "DOMAIN" "localhost"
set_env_if_missing "ACME_EMAIL" "admin@localhost"

# OpenWebUI
set_env_if_missing "OPENWEBUI_SECRET_KEY" "$(openssl rand -hex 32)"
set_env_if_missing "OPENWEBUI_ENABLE_SIGNUP" "false"

# OpenAI (placeholder - user must fill in)
set_env_if_missing "OPENAI_API_KEY" "sk-placeholder-replace-with-real-key"

# Anthropic (placeholder - user must fill in)
set_env_if_missing "ANTHROPIC_API_KEY" "sk-ant-placeholder-replace-with-real-key"

# N8N full config
set_env_if_missing "N8N_HOST" "n8n.${DOMAIN:-localhost}"
set_env_if_missing "N8N_PORT" "5678"
set_env_if_missing "N8N_PROTOCOL" "https"
set_env_if_missing "N8N_BASIC_AUTH_ACTIVE" "true"
set_env_if_missing "N8N_BASIC_AUTH_USER" "admin"
set_env_if_missing "N8N_BASIC_AUTH_PASSWORD" "$(openssl rand -hex 16)"

# Flowise full config
set_env_if_missing "FLOWISE_USERNAME" "admin"
set_env_if_missing "FLOWISE_PORT" "3000"

# Postgres databases for individual services
set_env_if_missing "OPENWEBUI_DB_NAME" "openwebui"
set_env_if_missing "N8N_DB_NAME" "n8n"
set_env_if_missing "LITELLM_DB_NAME" "litellm"
```

### Task 10.2 — Add database initialization to script 3
```
In scripts/3-configure-services.sh, add this block AFTER 
the environment variable generation section.
This creates required databases for services that need their own DB:

# --- Database Initialization ---
echo "[INFO] Initializing service databases..."

init_database() {
  local db_name="$1"
  local max_attempts=10
  local attempt=0
  
  # Wait for postgres to be available
  until docker compose exec -T postgres pg_isready \
    -U "${POSTGRES_USER:-aiplatform}" > /dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [[ $attempt -ge $max_attempts ]]; then
      echo "[ERROR] PostgreSQL not ready after $max_attempts attempts. Skipping $db_name."
      return 1
    fi
    echo "[INFO] Waiting for PostgreSQL... attempt $attempt/$max_attempts"
    sleep 5
  done
  
  # Create database if it doesn't exist
  docker compose exec -T postgres psql \
    -U "${POSTGRES_USER:-aiplatform}" \
    -tc "SELECT 1 FROM pg_database WHERE datname='${db_name}'" \
    | grep -q 1 || \
  docker compose exec -T postgres psql \
    -U "${POSTGRES_USER:-aiplatform}" \
    -c "CREATE DATABASE ${db_name};" && \
  echo "[OK] Database '$db_name' ready." || \
  echo "[SKIP] Database '$db_name' may already exist."
}

# Only run if postgres is running
if docker compose ps postgres 2>/dev/null | grep -q "running\|healthy"; then
  init_database "openwebui"
  init_database "litellm"
  init_database "n8n"
  init_database "authentik"
  echo "[INFO] Database initialization complete."
else
  echo "[WARN] PostgreSQL not running. Skipping database initialization."
  echo "[WARN] Run this script again after services are deployed."
fi
```

---

## PHASE 11: Update `scripts/0-emergency-fix.sh` with Idempotency Check

### Task 11.1 — Add idempotency and system state detection
```
In scripts/0-emergency-fix.sh, find the very beginning after the 
set -euo pipefail block. Add this system state detection block:

# --- System State Detection ---
detect_current_state() {
  echo ""
  echo "================================================"
  echo " CURRENT SYSTEM STATE DETECTION"
  echo "================================================"
  
  # Check if docker compose is available
  if ! command -v docker &>/dev/null; then
    echo "[ERROR] Docker is not installed. Run scripts/1-setup-system.sh first."
    exit 1
  fi
  
  # Count running containers
  RUNNING=$(docker compose ps --status running 2>/dev/null | grep -c "Up" || echo "0")
  RESTARTING=$(docker compose ps --status restarting 2>/dev/null | grep -c "Restarting" || echo "0")
  
  echo "[INFO] Running containers: $RUNNING"
  echo "[INFO] Restarting containers: $RESTARTING"
  
  # Check disk space on DATA_ROOT
  if [[ -d "$DATA_ROOT" ]]; then
    DISK_USAGE=$(df -h "$DATA_ROOT" | awk 'NR==2 {print $5}' | tr -d '%')
    echo "[INFO] Disk usage at $DATA_ROOT: ${DISK_USAGE}%"
    if [[ $DISK_USAGE -gt 90 ]]; then
      echo "[WARN] Disk usage above 90%. May cause service failures."
    fi
  fi
  
  # Check available memory
  AVAILABLE_MEM=$(awk '/MemAvailable/ {printf "%.0f", $2/1024}' /proc/meminfo)
  echo "[INFO] Available memory: ${AVAILABLE_MEM}MB"
  if [[ $AVAILABLE_MEM -lt 512 ]]; then
    echo "[WARN] Less than 512MB available. Services may fail to start."
  fi
  
  echo "================================================"
  echo ""
}

detect_current_state
```

### Task 11.2 — Add post-fix verification to emergency script
```
In scripts/0-emergency-fix.sh, at the very END of the file, 
before the final echo statements, add:

# --- Post-Fix Verification ---
echo ""
echo "================================================"
echo " POST-FIX VERIFICATION (waiting 30s for services)"
echo "================================================"
sleep 30

HEALTHY=0
UNHEALTHY=0
RESTARTING=0

SERVICES=("postgres" "redis" "grafana" "prometheus" "qdrant" "openwebui" "litellm" "caddy")

for service in "${SERVICES[@]}"; do
  STATUS=$(docker compose ps --format "{{.Status}}" "$service" 2>/dev/null || echo "not found")
  
  if echo "$STATUS" | grep -qi "healthy\|Up"; then
    echo "[✅] $service: $STATUS"
    HEALTHY=$((HEALTHY + 1))
  elif echo "$STATUS" | grep -qi "restarting"; then
    echo "[🔄] $service: STILL RESTARTING - check logs"
    RESTARTING=$((RESTARTING + 1))
  else
    echo "[❌] $service: $STATUS"
    UNHEALTHY=$((UNHEALTHY + 1))
  fi
done

echo ""
echo "Results: $HEALTHY healthy, $RESTARTING restarting, $UNHEALTHY unhealthy"
echo ""

if [[ $RESTARTING -gt 0 ]] || [[ $UNHEALTHY -gt 0 ]]; then
  echo "[ACTION REQUIRED] Some services still failing."
  echo ""
  echo "Debug commands:"
  echo "  docker compose logs --tail=50 grafana"
  echo "  docker compose logs --tail=50 qdrant"
  echo "  docker compose logs --tail=50 openwebui"
  echo "  docker compose logs --tail=50 litellm"
  echo "  docker compose logs --tail=50 prometheus"
  echo ""
  echo "Check permissions:"
  echo "  ls -la $DATA_ROOT/grafana"
  echo "  ls -la $DATA_ROOT/qdrant/storage"
  echo "  ls -la $DATA_ROOT/openwebui"
fi
```

---

## PHASE 12: Final Validation Checklist for Windsurf

```
After completing ALL phases above, perform this final audit:

SCRIPT STRUCTURE VERIFICATION
==============================
□ scripts/0-emergency-fix.sh  — EXISTS, executable, has set -euo pipefail
□ scripts/1-setup-system.sh   — Has permission framework, config generation
□ scripts/2-deploy-services.sh — Has fixed health checks, ordered startup
□ scripts/3-configure-services.sh — Has all env vars, DB init
□ scripts/4-monitor-health.sh — EXISTS, executable, has daemon mode

HEALTH CHECK VERIFICATION
==========================
□ Prometheus  — uses curl OR wget fallback, correct /-/healthy endpoint
□ LiteLLM     — uses /v1/models endpoint, 60s start_period
□ Qdrant      — uses / endpoint (root), NOT /readyz
□ Grafana     — uses /api/health endpoint
□ OpenWebUI   — uses /health endpoint, 60s start_period

PERMISSION UID VERIFICATION
============================
□ Grafana     — user: "472:472"
□ Prometheus  — user: "65534:65534"
□ Qdrant      — user: "1000:1001"
□ OpenWebUI   — user: "1000:1000"
□ LiteLLM     — user: "1000:1000"
□ PostgreSQL  — data dir: 999:999, mode 700
□ Redis       — data dir: 999:999

ENVIRONMENT VARIABLE VERIFICATION
===================================
□ AUTHENTIK_SECRET_KEY     — auto-generated
□ LITELLM_MASTER_KEY       — auto-generated with sk- prefix
□ LITELLM_SALT_KEY         — auto-generated
□ QDRANT_API_KEY           — auto-generated
□ FLOWISE_SECRET_KEY       — auto-generated
□ ANYTHINGLLM_JWT_SECRET   — auto-generated
□ N8N_ENCRYPTION_KEY       — auto-generated
□ OPENWEBUI_SECRET_KEY     — auto-generated
□ DOMAIN                   — set (default: localhost)
□ DATA_ROOT                — set (default: /mnt/data/datasquiz)

COMPOSE DEFINITION VERIFICATION
=================================
□ All services have logging limits (max-size: 10m, max-file: 3)
□ All services have memory limits
□ All services on ai-platform network
□ Caddy depends_on only postgres + redis (NOT all services)
□ Network defined with subnet 172.20.0.0/16

CONFIG FILE VERIFICATION
=========================
□ Prometheus config generated at $DATA_ROOT/prometheus/prometheus.yml
□ LiteLLM config generated at $DATA_ROOT/litellm/config.yaml
□ Caddyfile generated at $DATA_ROOT/caddy/Caddyfile

FINAL INSTRUCTION TO WINDSURF
==============================
After all checks pass:
1. Show a summary of every file modified and every file created
2. Show the line count diff for each modified file
3. Do NOT run any scripts
4. Output this exact message when done:

"✅ All fixes applied. To recover the system, run:
   sudo bash scripts/0-emergency-fix.sh
   
   Then monitor with:
   bash scripts/4-monitor-health.sh --daemon
   
   Or install as cron:
   sudo bash scripts/4-monitor-health.sh --install-cron"
```

---

## Complete Execution Order (For User Reference After Windsurf Finishes)

```bash
# Step 1: Apply system fixes (permissions, directories, configs)
sudo bash scripts/1-setup-system.sh

# Step 2: Generate all environment variables
bash scripts/3-configure-services.sh

# Step 3: Edit .env to add your real API keys
nano .env
# Replace OPENAI_API_KEY and ANTHROPIC_API_KEY placeholders

# Step 4: Deploy services
sudo bash scripts/2-deploy-services.sh

# Step 5: If anything is still broken, run emergency fix
sudo bash scripts/0-emergency-fix.sh

# Step 6: Initialize databases and configure services
bash scripts/3-configure-services.sh

# Step 7: Install continuous health monitoring
sudo bash scripts/4-monitor-health.sh --install-cron

# Step 8: Verify everything
docker compose ps
docker compose logs -f --tail=20
```