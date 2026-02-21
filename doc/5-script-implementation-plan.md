# 5-Script Architecture Implementation Plan

## 🎯 Core Principles

### **Script Responsibility Matrix**
```
Script 0 — Teardown          : Full cleanup, remove all data/containers/certs
Script 1 — Setup & Config    : Interactive menu → writes .env manifest
Script 2 — Deploy Everything   : Pull images, create containers, link ALL services
                               including vector DB wiring, AppArmor profiles,
                               non-root users, Tailscale sidecar for OpenClaw
Script 3 — Operational Mgmt  : SSL renewal, Tailscale token refresh, 
                               service restart, config reload
Script 4 — Extend Platform   : Add new dockerized service to existing stack
                               (reads manifest, wires into Caddy + network)
```

---

## 🔧 Script 2 - Complete Deployment Engine

### **Phase 1: Pre-flight Setup**
```bash
setup_deployment_environment() {
    # Load .env and set global variables
    source /mnt/data/.env
    
    # Set vector DB configuration globally
    set_vectordb_config
    
    # Create Docker network
    docker network create ai_platform 2>/dev/null || true
    
    # Create all service directories
    for service in postgres redis qdrant weaviate chroma ollama \
                  n8n flowise anythingllm litellm dify openclaw \
                  openwebui grafana prometheus minio signal-cli-rest-api; do
        mkdir -p /mnt/data/$service
        mkdir -p /mnt/data/logs/$service
        chown -R 1000:1000 /mnt/data/$service
        chown -R 1000:1000 /mnt/data/logs/$service
    done
    
    # Setup AppArmor profiles
    setup_apparmor_profiles
}
```

### **Phase 2: Infrastructure First**
```bash
deploy_infrastructure() {
    echo "🏗️ Deploying Infrastructure Services..."
    
    # Deploy PostgreSQL with pgvector extension if needed
    if [ "${VECTOR_DB}" = "pgvector" ]; then
        deploy_postgres_with_pgvector
    else
        deploy_postgres
    fi
    
    # Deploy Redis
    deploy_redis
    
    # Deploy selected Vector DB
    case "${VECTOR_DB}" in
        qdrant) deploy_qdrant ;;
        weaviate) deploy_weaviate ;;
        chroma) deploy_chroma ;;
        pgvector) echo "pgvector uses PostgreSQL" ;;
    esac
    
    # Health gate: wait until infrastructure is ready
    wait_for_infrastructure_ready
}
```

### **Phase 3: AI Services with Vector DB Pre-wired**
```bash
deploy_ai_services() {
    echo "🤖 Deploying AI Services..."
    
    # Each service gets vector DB env vars AT CREATION TIME
    deploy_ollama           # No vector DB needed
    deploy_litellm           # Vector DB written to config.yaml
    deploy_anythingllm       # Vector DB env vars passed
    deploy_dify             # Vector DB env vars passed
    deploy_flowise
    deploy_openwebui
    deploy_n8n
    deploy_openclaw           # Tailscale sidecar + dedicated UID
}
```

---

## 🔗 Vector DB Integration - Central Configuration

### **Global Vector DB Switch Block**
```bash
# Called ONCE at top of script 2
set_vectordb_config() {
    case "${VECTOR_DB}" in
        qdrant)
            export VECTORDB_HOST="qdrant"
            export VECTORDB_PORT="6333"
            export VECTORDB_TYPE="qdrant"
            export VECTORDB_URL="http://qdrant:6333"
            export VECTORDB_COLLECTION="ai_platform"
            ;;
        pgvector)
            export VECTORDB_HOST="postgres"
            export VECTORDB_PORT="5432"
            export VECTORDB_TYPE="pgvector"
            export VECTORDB_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}"
            export VECTORDB_COLLECTION="ai_platform"
            ;;
        weaviate)
            export VECTORDB_HOST="weaviate"
            export VECTORDB_PORT="8080"
            export VECTORDB_TYPE="weaviate"
            export VECTORDB_URL="http://weaviate:8080"
            export VECTORDB_COLLECTION="AIPlatform"
            ;;
        chroma)
            export VECTORDB_HOST="chroma"
            export VECTORDB_PORT="8000"
            export VECTORDB_TYPE="chroma"
            export VECTORDB_URL="http://chroma:8000"
            export VECTORDB_COLLECTION="ai_platform"
            ;;
    esac
}
```

### **Service-Specific Vector DB Wiring**

#### **deploy_litellm() - Config File Approach**
```bash
deploy_litellm() {
    mkdir -p /mnt/data/litellm/config
    chown -R 1000:1000 /mnt/data/litellm
    
    # Write base config with vector DB semantic cache
    cat > /mnt/data/litellm/config/config.yaml << 'LITELLM_EOF'
model_list:
  - model_name: ollama/llama3
    model: ollama/llama3
    litellm_params:
      api_base: http://ollama:11434

litellm_settings:
  database_url: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
  redis_url: redis://:6379
  redis_password: ${REDIS_PASSWORD}

general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  salt_key: ${LITELLM_SALT_KEY}
  cache_enabled: true
  cache_ttl: 3600
  rate_limit_enabled: true
  rate_limit_requests_per_minute: 60
  routing_strategy: local-first
LITELLM_EOF

    # Append vector DB semantic cache config
    case "${VECTOR_DB}" in
        qdrant)
            cat >> /mnt/data/litellm/config/config.yaml << 'QDRANT_EOF'

  cache_params:
    type: qdrant-semantic
    qdrant_host: ${VECTORDB_HOST}
    qdrant_port: ${VECTORDB_PORT}
    qdrant_collection_name: litellm_cache
    similarity_threshold: 0.8
QDRANT_EOF
            ;;
        redis|*)
            # Default: redis cache (always available)
            cat >> /mnt/data/litellm/config/config.yaml << 'REDIS_EOF'

  cache_params:
    type: redis
    host: redis
    port: 6379
REDIS_EOF
            ;;
    esac

    docker run -d \
        --name litellm \
        --network ai_platform \
        --restart unless-stopped \
        --security-opt apparmor=ai-platform-default \
        --user 1000:1000 \
        -p "${LITELLM_PORT}:4000" \
        -v /mnt/data/litellm/config.yaml:/app/config.yaml:ro \
        -v /mnt/data/litellm/logs:/app/logs \
        ghcr.io/berriai/litellm:main-latest \
        --config /app/config.yaml
}
```

#### **deploy_anythingllm() - Environment Variables Approach**
```bash
deploy_anythingllm() {
    mkdir -p /mnt/data/anythingllm
    chown -R 1000:1000 /mnt/data/anythingllm
    
    # Build vector DB env block based on global config
    local vectordb_env=()
    case "${VECTOR_DB}" in
        qdrant)
            vectordb_env=(
                -e "VECTOR_DB=qdrant"
                -e "QDRANT_ENDPOINT=${VECTORDB_URL}"
                -e "QDRANT_API_KEY="
            )
            ;;
        pgvector)
            vectordb_env=(
                -e "VECTOR_DB=pgvector"
                -e "PGVECTOR_CONNECTION_STRING=${VECTORDB_URL}"
            )
            ;;
        weaviate)
            vectordb_env=(
                -e "VECTOR_DB=weaviate"
                -e "WEAVIATE_ENDPOINT=${VECTORDB_URL}"
                -e "WEAVIATE_API_KEY="
            )
            ;;
        chroma)
            vectordb_env=(
                -e "VECTOR_DB=chroma"
                -e "CHROMA_ENDPOINT=${VECTORDB_URL}"
            )
            ;;
    esac

    docker run -d \
        --name anythingllm \
        --network ai_platform \
        --restart unless-stopped \
        --security-opt apparmor=ai-platform-default \
        --user 1000:1000 \
        -p "${ANYTHINGLLM_PORT}:3001" \
        -v /mnt/data/anythingllm:/app/server/storage \
        -e "STORAGE_DIR=/app/server/storage" \
        -e "LLM_PROVIDER=ollama" \
        -e "OLLAMA_BASE_PATH=http://ollama:11434" \
        -e "EMBEDDING_ENGINE=ollama" \
        -e "EMBEDDING_BASE_PATH=http://ollama:11434" \
        -e "JWT_SECRET=${JWT_SECRET}" \
        "${vectordb_env[@]}" \
        mintplexlabs/anythingllm:latest
}
```

---

## 🛡️ OpenClaw + Tailscale - Complete Implementation

### **deploy_openclaw() - Sidecar Pattern**
```bash
deploy_openclaw() {
    if [ -z "${TAILSCALE_AUTH_KEY}" ]; then
        echo "❌ TAILSCALE_AUTH_KEY missing — OpenClaw requires Tailscale"
        return 1
    fi

    mkdir -p /mnt/data/tailscale
    mkdir -p /mnt/data/openclaw
    
    # OpenClaw runs as dedicated UID 2000 — isolated from other services
    chown -R 2000:2000 /mnt/data/openclaw
    chown -R 2000:2000 /mnt/data/tailscale

    # Step 1: Tailscale sidecar — owns network namespace
    docker run -d \
        --name tailscale-openclaw \
        --network ai_platform \
        --restart unless-stopped \
        --cap-add NET_ADMIN \
        --cap-add SYS_MODULE \
        --security-opt apparmor=ai-platform-tailscale \
        -v /mnt/data/tailscale:/var/lib/tailscale \
        -v /dev/net/tun:/dev/net/tun \
        -e "TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY}" \
        -e "TAILSCALE_HOSTNAME=openclaw-${HOSTNAME}" \
        -e "TAILSCALE_STATE_DIR=/var/lib/tailscale" \
        tailscale/tailscale:latest

    # Wait for Tailscale to authenticate
    echo "Waiting for Tailscale auth..."
    local retries=0
    until docker exec tailscale-openclaw tailscale status \
          --json 2>/dev/null | grep -q '"Online":true'; do
        sleep 3
        retries=$((retries + 1))
        if [ "$retries" -ge 20 ]; then
            echo "❌ Tailscale failed to authenticate after 60s"
            return 1
        fi
    done
    echo "✅ Tailscale authenticated"

    # Step 2: OpenClaw shares Tailscale's network namespace
    # This means OpenClaw's traffic routes through Tailscale
    # AND OpenClaw is reachable on Tailscale IP
    docker run -d \
        --name openclaw \
        --network container:tailscale-openclaw \
        --restart unless-stopped \
        --security-opt apparmor=ai-platform-openclaw \
        --user 2000:2000 \
        --read-only \
        --tmpfs /tmp:rw,noexec,nosuid,size=100m \
        -v /mnt/data/openclaw:/app/data:rw \
        -v /mnt/data/openclaw/config:/app/config:ro \
        "${vectordb_env[@]}" \
        openclaw/openclaw:latest

    # Step 3: Caddy can still reach OpenClaw via ai_platform network
    # because tailscale-openclaw IS on ai_platform
    # Caddy → tailscale-openclaw:18789 → (shared netns) → openclaw
    echo "OpenClaw deployed via Tailscale sidecar"
    echo "Tailscale IP: $(docker exec tailscale-openclaw tailscale ip 2>/dev/null)"
}
```

---

## 🛡️ AppArmor Profiles - Built into Script 2

### **setup_apparmor_profiles() - Complete Implementation**
```bash
setup_apparmor_profiles() {
    if ! command -v apparmor_parser &>/dev/null; then
        echo "⚠️  AppArmor not available — skipping profiles"
        return 0
    fi

    # Default profile: all AI services except openclaw
    cat > /etc/apparmor.d/ai-platform-default << 'APPARMOR_EOF'
#include <tunables/global>

profile ai-platform-default flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  # Allow read of own data directory only
  /mnt/data/** r,

  # Deny access to sensitive host paths
  deny /etc/shadow r,
  deny /etc/passwd w,
  deny /root/** rw,
  deny /home/** rw,
  deny /proc/sysrq-trigger rw,

  # Network allowed (Docker handles this)
  network,

  # Allow container runtime needs
  /proc/self/** r,
  /sys/fs/cgroup/** r,
}
APPARMOR_EOF

    # OpenClaw profile: stricter — own data dir only, read-only everything else
    cat > /etc/apparmor.d/ai-platform-openclaw << 'APPARMOR_EOF'
#include <tunables/global>

profile ai-platform-openclaw flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  # Strict: only its own data dir
  /mnt/data/openclaw/** rw,
  /tmp/** rw,

  # Deny everything else
  deny /mnt/data/anythingllm/** rw,
  deny /mnt/data/dify/** rw,
  deny /mnt/data/n8n/** rw,
  deny /mnt/data/postgres/** rw,
  deny /etc/** w,
  deny /root/** rw,
  deny /home/** rw,

  network,
  capability net_admin,
  capability sys_module,
}
APPARMOR_EOF

    # Tailscale profile: needs NET_ADMIN, tun device
    cat > /etc/apparmor.d/ai-platform-tailscale << 'APPARMOR_EOF'
#include <tunables/global>

profile ai-platform-tailscale flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  /mnt/data/tailscale/** rw,
  /dev/net/tun rw,
  /proc/sys/net/** r,

  deny /mnt/data/openclaw/** rw,
  deny /etc/shadow r,

  network,
  capability net_admin,
  capability sys_module,
}
APPARMOR_EOF

    # Load all profiles
    apparmor_parser -r /etc/apparmor.d/ai-platform-default
    apparmor_parser -r /etc/apparmor.d/ai-platform-openclaw
    apparmor_parser -r /etc/apparmor.d/ai-platform-tailscale

    echo "✅ AppArmor profiles loaded"
}
```

---

## 🔧 Script 3 - Operations Only

### **Script 3 Responsibilities (Stripped to Ops)**
```bash
#!/bin/bash
# Script 3: Post-Deployment Configuration & Management
# ONLY operational functions - NO deployment work

source /mnt/data/.env

# SSL Certificate Management
renew_ssl() {
    echo "🔄 Renewing SSL certificates..."
    docker exec caddy caddy reload --config /etc/caddy/Caddyfile
}

# Tailscale Token Refresh
refresh_tailscale_token() {
    echo "🔄 Refreshing Tailscale token..."
    if [ -n "${NEW_TAILSCALE_AUTH_KEY}" ]; then
        docker exec tailscale-openclaw tailscale up --auth-key=${NEW_TAILSCALE_AUTH_KEY}
        # Update .env
        sed -i "s/TAILSCALE_AUTH_KEY=.*/TAILSCALE_AUTH_KEY=${NEW_TAILSCALE_AUTH_KEY}/" /mnt/data/.env
    fi
}

# Individual Service Restart
restart_service() {
    local service_name=$1
    echo "🔄 Restarting service: $service_name"
    docker restart $service_name
}

# Caddy Configuration Reload
reload_caddy() {
    echo "🔄 Reloading Caddy configuration..."
    docker exec caddy caddy reload --config /etc/caddy/Caddyfile
}

# Rotate Secrets
rotate_secrets() {
    echo "🔄 Rotating secrets..."
    # Generate new secrets and update .env
    # Restart affected services
}

# Show Platform Status
show_status() {
    echo "📊 Platform Status:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo ""
    echo "🔍 Health Checks:"
    for service in grafana prometheus n8n; do
        local status=$(curl -s -o /dev/null -w "%{http_code}" \
            http://localhost/$service/health 2>/dev/null)
        echo "$service: HTTP $status"
    done
}

# Menu system
case "${1}" in
    renew) renew_ssl ;;
    tailscale) refresh_tailscale_token ;;
    restart) restart_service "${2}" ;;
    reload) reload_caddy ;;
    status) show_status ;;
    *) 
        echo "Usage: $0 {renew|tailscale|restart|reload|status}"
        exit 1
        ;;
esac
```

---

## ➕ Script 4 - Service Extensibility

### **add_service() - Complete Pattern**
```bash
add_service() {
    local SERVICE_NAME=$1
    local SERVICE_IMAGE=$2
    local INTERNAL_PORT=$3
    
    if [ -z "$SERVICE_NAME" ] || [ -z "$SERVICE_IMAGE" ]; then
        echo "❌ Usage: add_service <name> <image> <internal_port>"
        return 1
    fi

    # 1. Load existing .env
    source /mnt/data/.env

    # 2. Assign next available port from firewall range
    local NEW_PORT=$(get_next_free_port)

    # 3. Create AppArmor profile (copy default)
    cp /etc/apparmor.d/ai-platform-default \
       /etc/apparmor.d/ai-platform-${SERVICE_NAME}
    apparmor_parser -r /etc/apparmor.d/ai-platform-${SERVICE_NAME}

    # 4. Deploy container with standard pattern
    docker run -d \
        --name ${SERVICE_NAME} \
        --network ai_platform \
        --restart unless-stopped \
        --security-opt apparmor=ai-platform-${SERVICE_NAME} \
        --user 1000:1000 \
        -p ${NEW_PORT}:${INTERNAL_PORT} \
        -v /mnt/data/${SERVICE_NAME}:/app/data \
        "${vectordb_env[@]}" \
        ${SERVICE_IMAGE}

    # 5. Add Caddy route
    add_caddy_route "${SERVICE_NAME}" "${INTERNAL_PORT}"

    # 6. Reload Caddy (no restart needed)
    docker exec caddy caddy reload --config /etc/caddy/Caddyfile

    # 7. Write new service to manifest
    echo "${SERVICE_NAME}=${NEW_PORT}" >> /mnt/data/config/.env

    echo "✅ Service $SERVICE_NAME added on port $NEW_PORT"
}

add_caddy_route() {
    local name=$1
    local port=$2
    # Insert before closing brace of Caddyfile
    sed -i "/respond \"AI Platform\"/i\\
    handle_path /${name}/* {\\
        reverse_proxy ${name}:${port}\\
    }\\
+" /mnt/data/caddy/Caddyfile
}

get_next_free_port() {
    # Find next available port in firewall range 5000-5009
    for port in {5000..5009}; do
        if ! netstat -tlnp | grep -q ":$port "; then
            echo $port
            return 0
        fi
    done
    echo "❌ No free ports available in 5000-5009 range"
    return 1
}
```

---

## 🧹 Script 0 - Complete Teardown

### **Script 0 Enhancements**
```bash
#!/bin/bash
# Script 0: Complete Platform Teardown

echo "🧹 Complete AI Platform Teardown..."

# Stop and remove ALL containers
docker stop $(docker ps -q) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true

# Remove ALL networks
docker network prune -f 2>/dev/null || true

# Remove ALL data directories
read -p "Remove ALL data directories? (y/N): " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    rm -rf /mnt/data/*
    echo "✅ All data removed"
else
    echo "📁 Data directories preserved"
fi

# Remove ALL certificates and configs
rm -rf /etc/ssl/certs/ai.datasquiz.net/* 2>/dev/null || true
rm -rf /mnt/data/config/* 2>/dev/null || true

echo "✅ Platform completely torn down"
```

---

## 🎯 Implementation Priority

### **Phase 1: Core Infrastructure (Week 1)**
1. ✅ **Script 2 - Phase 1 & 2**: Infrastructure + vector DB wiring
2. ✅ **AppArmor profiles**: Built into deployment process
3. ✅ **Non-root containers**: Standard `--user 1000:1000`

### **Phase 2: Service Integration (Week 1-2)**
1. ✅ **Script 2 - Phase 3**: All AI services with vector DB
2. ✅ **OpenClaw + Tailscale**: Complete sidecar pattern
3. ✅ **Caddy deployment**: Last, after all services ready

### **Phase 3: Operations & Extensibility (Week 2)**
1. ✅ **Script 3**: Ops-only functions
2. ✅ **Script 4**: Service addition pattern
3. ✅ **Script 0**: Complete teardown

---

## 📊 Success Criteria

### **Technical Success**
- ✅ All services run as non-root (except OpenClaw: UID 2000)
- ✅ All services have AppArmor profiles
- ✅ Vector DB linked at deployment time
- ✅ OpenClaw accessible via Tailscale
- ✅ Caddy routes to all services
- ✅ SSL certificates auto-renew

### **Operational Success**
- ✅ Platform extensible via Script 4
- ✅ Operations manageable via Script 3
- ✅ Complete teardown via Script 0
- ✅ 5-script architecture maintained
- ✅ No manual intervention needed

---

## 🔧 Dynamic Configuration - Multi-Tenant Architecture

### **Core Dynamic Variables**
```bash
# From .env - all dynamic, no hardcoded values
BASE_DIR=${BASE_DIR:-/mnt/data}
DOMAIN_NAME=${DOMAIN_NAME:-ai.datasquiz.net}
LOCALHOST=${LOCALHOST:-localhost}

# Vector DB - selected in Script 1, used everywhere
VECTOR_DB=${VECTOR_DB:-qdrant}

# User profiles - each tenant runs under different UID
TENANT_UID=${TENANT_UID:-1000}
TENANT_GID=${TENANT_GID:-1000}
OPENCLAW_UID=${OPENCLAW_UID:-2000}
OPENCLAW_GID=${OPENCLAW_GID:-2000}

# Dynamic port ranges - allocated by Script 1
PROMETHEUS_PORT=${PROMETHEUS_PORT:-5000}
GRAFANA_PORT=${GRAFANA_PORT:-5001}
N8N_PORT=${N8N_PORT:-5002}
# ... etc for all services
```

### **Multi-Tenant Directory Structure**
```bash
# Each tenant gets isolated filesystem
${BASE_DIR}/
├── tenants/
│   ├── tenant-a/          # UID 1000:1000
│   │   ├── data/
│   │   ├── logs/
│   │   └── config/
│   ├── tenant-b/          # UID 2000:2000  
│   │   ├── data/
│   │   ├── logs/
│   │   └── config/
│   └── tenant-c/          # UID 3000:3000
│       ├── data/
│       ├── logs/
│       └── config/
├── shared/               # Common resources
│   ├── ssl/certs/
│   └── config/
└── stacks/               # Stack definitions
    ├── tenant-a-stack.yml
    ├── tenant-b-stack.yml
    └── tenant-c-stack.yml
```

---

## 🔧 Script 2 - Dynamic Deployment Engine

### **Phase 1: Dynamic Environment Setup**
```bash
setup_deployment_environment() {
    # Load tenant profile
    source ${BASE_DIR}/config/tenant-${TENANT_NAME}.env
    
    # Set tenant-specific paths
    TENANT_DIR="${BASE_DIR}/tenants/${TENANT_NAME}"
    TENANT_DATA="${TENANT_DIR}/data"
    TENANT_LOGS="${TENANT_DIR}/logs"
    TENANT_CONFIG="${TENANT_DIR}/config"
    
    # Create tenant directories with correct ownership
    mkdir -p "${TENANT_DATA}" "${TENANT_LOGS}" "${TENANT_CONFIG}"
    chown -R ${TENANT_UID}:${TENANT_GID} "${TENANT_DIR}"
    
    # Set vector DB configuration globally
    set_vectordb_config
    
    # Create tenant-specific Docker network
    docker network create "ai-platform-${TENANT_NAME}" 2>/dev/null || true
    
    # Setup AppArmor profiles for tenant
    setup_tenant_apparmor_profiles "${TENANT_NAME}"
}
```

### **Service Deployment with Dynamic Paths**
```bash
deploy_litellm() {
    local service_name="litellm"
    local internal_port="4000"
    local host_port="${LITELLM_PORT}"
    
    # Use tenant-specific paths
    mkdir -p "${TENANT_CONFIG}/${service_name}"
    chown -R ${TENANT_UID}:${TENANT_GID} "${TENANT_CONFIG}/${service_name}"
    
    # Write config with dynamic vector DB settings
    cat > "${TENANT_CONFIG}/${service_name}/config.yaml" << 'LITELLM_EOF'
model_list:
  - model_name: ollama/llama3
    model: ollama/llama3
    litellm_params:
      api_base: http://ollama:11434

litellm_settings:
  database_url: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
  redis_url: redis://:6379
  redis_password: ${REDIS_PASSWORD}

general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  salt_key: ${LITELLM_SALT_KEY}
  cache_enabled: true
  cache_ttl: 3600
  rate_limit_enabled: true
  rate_limit_requests_per_minute: 60
  routing_strategy: local-first
LITELLM_EOF

    # Append vector DB semantic cache config
    case "${VECTOR_DB}" in
        qdrant)
            cat >> "${TENANT_CONFIG}/${service_name}/config.yaml" << 'QDRANT_EOF'

  cache_params:
    type: qdrant-semantic
    qdrant_host: ${VECTORDB_HOST}
    qdrant_port: ${VECTORDB_PORT}
    qdrant_collection_name: ${TENANT_NAME}-litellm-cache
    similarity_threshold: 0.8
QDRANT_EOF
            ;;
        redis|*)
            cat >> "${TENANT_CONFIG}/${service_name}/config.yaml" << 'REDIS_EOF'

  cache_params:
    type: redis
    host: redis
    port: 6379
REDIS_EOF
            ;;
    esac

    docker run -d \
        --name "${TENANT_NAME}-${service_name}" \
        --network "ai-platform-${TENANT_NAME}" \
        --restart unless-stopped \
        --security-opt "apparmor=ai-platform-${TENANT_NAME}" \
        --user "${TENANT_UID}:${TENANT_GID}" \
        -p "${host_port}:${internal_port}" \
        -v "${TENANT_CONFIG}/${service_name}/config.yaml:/app/config.yaml:ro" \
        -v "${TENANT_LOGS}/${service_name}:/app/logs" \
        -v "${TENANT_DATA}/${service_name}:/app/data" \
        ghcr.io/berriai/litellm:main-latest \
        --config "/app/config.yaml"
}
```

---

## 🛡️ AppArmor Profiles - Tenant-Specific

### **setup_tenant_apparmor_profiles()**
```bash
setup_tenant_apparmor_profiles() {
    local tenant_name=$1
    
    if ! command -v apparmor_parser &>/dev/null; then
        echo "⚠️  AppArmor not available — skipping profiles"
        return 0
    fi

    # Tenant-specific default profile
    cat > "/etc/apparmor.d/ai-platform-${tenant_name}" << 'APPARMOR_EOF'
#include <tunables/global>

profile ai-platform-${tenant_name} flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  # Allow read of tenant's own data directory only
  ${TENANT_DATA}/** r,

  # Allow access to shared resources
  ${BASE_DIR}/shared/** r,

  # Deny access to other tenants' data
  deny ${BASE_DIR}/tenants/!${tenant_name}/** rw,

  # Deny access to sensitive host paths
  deny /etc/shadow r,
  deny /etc/passwd w,
  deny /root/** rw,

  network,
  /proc/self/** r,
  /sys/fs/cgroup/** r,
}
APPARMOR_EOF

    # OpenClaw gets stricter profile if it's this tenant
    if [ "${tenant_name}" = "openclaw-tenant" ]; then
        cat > "/etc/apparmor.d/ai-platform-openclaw" << 'APPARMOR_EOF'
#include <tunables/global>

profile ai-platform-openclaw flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  # Strict: only its own data dir
  ${TENANT_DATA}/** rw,
  /tmp/** rw,

  # Deny everything else
  deny ${BASE_DIR}/tenants/!openclaw-tenant/** rw,
  deny /etc/** w,
  deny /root/** rw,

  network,
  capability net_admin,
  capability sys_module,
}
APPARMOR_EOF
    fi

    # Load tenant profile
    apparmor_parser -r "/etc/apparmor.d/ai-platform-${tenant_name}"
    
    echo "✅ AppArmor profile loaded for tenant: ${tenant_name}"
}
```

---

## 🛡️ OpenClaw + Tailscale - Tenant Isolation

### **deploy_openclaw() - Multi-Tenant**
```bash
deploy_openclaw() {
    if [ -z "${TAILSCALE_AUTH_KEY}" ]; then
        echo "❌ TAILSCALE_AUTH_KEY missing — OpenClaw requires Tailscale"
        return 1
    fi

    # OpenClaw gets dedicated tenant directory
    local openclaw_tenant="openclaw-tenant"
    local openclaw_dir="${BASE_DIR}/tenants/${openclaw_tenant}"
    
    mkdir -p "${openclaw_dir}/data" "${openclaw_dir}/config"
    chown -R ${OPENCLAW_UID}:${OPENCLAW_GID} "${openclaw_dir}"

    # Step 1: Tailscale sidecar for this tenant
    docker run -d \
        --name "tailscale-${openclaw_tenant}" \
        --network "ai-platform-${openclaw_tenant}" \
        --restart unless-stopped \
        --cap-add NET_ADMIN \
        --cap-add SYS_MODULE \
        --security-opt "apparmor=ai-platform-tailscale" \
        -v "${openclaw_dir}/tailscale:/var/lib/tailscale" \
        -v /dev/net/tun:/dev/net/tun \
        -e "TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY}" \
        -e "TAILSCALE_HOSTNAME=openclaw-${openclaw_tenant}" \
        -e "TAILSCALE_STATE_DIR=/var/lib/tailscale" \
        tailscale/tailscale:latest

    # Wait for Tailscale to authenticate
    echo "Waiting for Tailscale auth for ${openclaw_tenant}..."
    wait_for_tailscale_auth "tailscale-${openclaw_tenant}"

    # Step 2: OpenClaw container in tenant network
    docker run -d \
        --name "${openclaw_tenant}" \
        --network "container:tailscale-${openclaw_tenant}" \
        --restart unless-stopped \
        --security-opt "apparmor=ai-platform-openclaw" \
        --user "${OPENCLAW_UID}:${OPENCLAW_GID}" \
        --read-only \
        --tmpfs /tmp:rw,noexec,nosuid,size=100m \
        -v "${openclaw_dir}/data:/app/data:rw" \
        -v "${openclaw_dir}/config:/app/config:ro" \
        "${vectordb_env[@]}" \
        openclaw/openclaw:latest

    echo "✅ OpenClaw deployed for tenant: ${openclaw_tenant}"
    echo "Tailscale IP: $(docker exec "tailscale-${openclaw_tenant}" tailscale ip 2>/dev/null)"
}
```

---

## 🧹 Script 3 - Multi-Tenant Operations

### **Tenant-Aware Operations**
```bash
# SSL renewal for specific tenant
renew_ssl() {
    local tenant_name=${1:-default}
    echo "🔄 Renewing SSL certificates for tenant: ${tenant_name}"
    docker exec "caddy-${tenant_name}" caddy reload --config "/etc/caddy/Caddyfile"
}

# Restart service for specific tenant
restart_service() {
    local tenant_name=$1
    local service_name=$2
    echo "🔄 Restarting service: ${service_name} for tenant: ${tenant_name}"
    docker restart "${tenant_name}-${service_name}"
}

# Reload Caddy for specific tenant
reload_caddy() {
    local tenant_name=${1:-default}
    echo "🔄 Reloading Caddy for tenant: ${tenant_name}"
    docker exec "caddy-${tenant_name}" caddy reload --config "/etc/caddy/Caddyfile"
}

# Show status for all tenants
show_status() {
    echo "📊 Multi-Tenant Platform Status:"
    
    # List all tenants
    for tenant_dir in "${BASE_DIR}/tenants"/*; do
        if [ -d "$tenant_dir" ]; then
            local tenant_name=$(basename "$tenant_dir")
            echo "=== Tenant: ${tenant_name} ==="
            docker ps --filter "name=${tenant_name}-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        fi
    done
}
```

---

## ➕ Script 4 - Multi-Tenant Service Addition

### **add_service() - Tenant-Aware**
```bash
add_service() {
    local tenant_name=$1
    local service_name=$2
    local service_image=$3
    local internal_port=$4
    
    if [ -z "$tenant_name" ] || [ -z "$service_name" ]; then
        echo "❌ Usage: add_service <tenant> <name> <image> <internal_port>"
        return 1
    fi

    # Load tenant configuration
    source "${BASE_DIR}/config/tenant-${tenant_name}.env"

    # Assign next available port for this tenant
    local new_port=$(get_next_free_port_for_tenant "$tenant_name")

    # Create tenant-specific AppArmor profile
    cp "/etc/apparmor.d/ai-platform-default" \
       "/etc/apparmor.d/ai-platform-${tenant_name}-${service_name}"
    apparmor_parser -r "/etc/apparmor.d/ai-platform-${tenant_name}-${service_name}"

    # Deploy container for specific tenant
    local tenant_dir="${BASE_DIR}/tenants/${tenant_name}"
    docker run -d \
        --name "${tenant_name}-${service_name}" \
        --network "ai-platform-${tenant_name}" \
        --restart unless-stopped \
        --security-opt "apparmor=ai-platform-${tenant_name}-${service_name}" \
        --user "${TENANT_UID}:${TENANT_GID}" \
        -p "${new_port}:${internal_port}" \
        -v "${tenant_dir}/data/${service_name}:/app/data" \
        -v "${tenant_dir}/logs/${service_name}:/app/logs" \
        "${vectordb_env[@]}" \
        "${service_image}"

    # Add route to tenant's Caddy
    add_caddy_route_tenant "${tenant_name}" "${service_name}" "${internal_port}"

    # Reload tenant's Caddy
    docker exec "caddy-${tenant_name}" caddy reload --config "/etc/caddy/Caddyfile"

    # Update tenant manifest
    echo "${service_name}=${new_port}" >> "${BASE_DIR}/config/tenant-${tenant_name}.env"

    echo "✅ Service ${service_name} added for tenant ${tenant_name} on port ${new_port}"
}

get_next_free_port_for_tenant() {
    local tenant_name=$1
    # Each tenant gets different port range to avoid conflicts
    case "${tenant_name}" in
        tenant-a) echo "5000" ;;
        tenant-b) echo "5100" ;;
        tenant-c) echo "5200" ;;
        *) echo "5300" ;;
    esac
}
```

---

## 🧹 Script 0 - Multi-Tenant Teardown

### **Complete Multi-Tenant Cleanup**
```bash
#!/bin/bash
# Script 0: Multi-Tenant Platform Teardown

echo "🧹 Multi-Tenant Platform Teardown..."

# Stop and remove ALL containers across all tenants
docker stop $(docker ps -q --format "{{.Names}}") 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true

# Remove ALL tenant networks
for network in $(docker network ls --format "{{.Name}}" | grep "ai-platform-"); do
    docker network rm "$network" 2>/dev/null || true
done

# Remove ALL tenant directories (with confirmation)
read -p "Remove ALL tenant data directories? (y/N): " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    rm -rf "${BASE_DIR}/tenants/*"
    echo "✅ All tenant data removed"
else
    echo "📁 Tenant data directories preserved"
fi

# Remove shared resources
rm -rf "${BASE_DIR}/shared/ssl/certs/${DOMAIN_NAME}/*" 2>/dev/null || true
rm -rf "${BASE_DIR}/shared/config/*" 2>/dev/null || true

echo "✅ Multi-tenant platform completely torn down"
```

---

## 🎯 Revised Implementation Priority

### **Phase 1: Dynamic Multi-Tenant Base (Week 1)**
1. ✅ **Dynamic .env loading** - BASE_DIR, tenant profiles
2. ✅ **Tenant directory structure** - isolated filesystems
3. ✅ **Dynamic port allocation** - per-tenant ranges
4. ✅ **Tenant-specific AppArmor** - /mnt/data/tenants/tenant-a/

### **Phase 2: Multi-Tenant Services (Week 1-2)**
1. ✅ **Vector DB per tenant** - isolated collections
2. ✅ **OpenClaw + Tailscale** - tenant-isolated
3. ✅ **Non-root containers** - tenant-specific UIDs
4. ✅ **Dynamic Caddy per tenant** - separate instances

### **Phase 3: Multi-Tenant Operations (Week 2)**
1. ✅ **Tenant-aware operations** - restart/reload per tenant
2. ✅ **Service addition per tenant** - extensible multi-tenant
3. ✅ **Complete teardown** - all tenants cleaned

---

## 📊 Success Criteria - Multi-Tenant

### **Technical Success**
- ✅ **Dynamic configuration**: No hardcoded values, all from .env
- ✅ **Tenant isolation**: Separate filesystems, networks, UIDs
- ✅ **Vector DB per tenant**: Isolated collections/namespaces
- ✅ **Security**: Tenant-specific AppArmor profiles
- ✅ **Extensibility**: Add services to any tenant

### **Operational Success**
- ✅ **Multi-tenant management**: Script 3 handles multiple tenants
- ✅ **Service addition**: Script 4 adds to specific tenants
- ✅ **Complete isolation**: Tenants cannot access each other's data
- ✅ **Scalability**: Support unlimited tenants with dynamic resources

---

*Implementation Plan Revised: 2026-02-21*
*Version: 2.0 - Multi-Tenant Dynamic*
*Architecture: 5-Script Model with Dynamic Configuration*
*Priority: Tenant Isolation + Dynamic Configuration*
