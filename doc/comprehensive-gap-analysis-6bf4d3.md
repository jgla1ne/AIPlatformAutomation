# AI Platform MVP Fix & Gap Analysis

**Date:** February 17, 2026  
**Goal:** Get complete end-to-end working deployment (Scripts 0→1→2→3→4)  
**Current Status:** Prometheus failing due to network label mismatch

---

## PART 1: IMMEDIATE FIX - Network Label Issue

### Problem Analysis

**Error:**
```
network ai_platform_internal was found but has incorrect label 
com.docker.compose.network set to "" (expected: "ai_platform_internal")
Container prometheus Error dependency prometheus failed to start
```

**Root Cause:**
Script 1 creates networks manually → Script 2's docker-compose expects Compose-managed networks → Label mismatch

**Critical Path Misalignment:**
```
Script 1 (Line ~820):
  docker network create ai-platform --driver bridge  ← Creates network WITHOUT Compose labels

Script 1 (Line ~1720):
  networks:
    ai-platform:
      name: ai-platform  ← Compose expects to CREATE this network
```

### Solution: Single-Point Network Management

**Let Docker Compose own network lifecycle** - Remove manual creation entirely.

---

## WINDSURF FIX INSTRUCTIONS

### File: `scripts/1-setup-system.sh`

#### Fix #1: Replace Network Creation Function (Lines ~820-850)

**FIND:**
```bash
create_docker_networks() {
    log_phase "PHASE 6: Creating Docker Networks"
    
    if [ "${SETUP_PHASES[networks]}" -eq 1 ]; then
        log_info "Docker networks already created - skipping"
        return 0
    fi
    
    local networks=("ai-platform" "ai-platform-internal" "ai-platform-monitoring")
    
    for network in "${networks[@]}"; do
        if docker network inspect "$network" &> /dev/null; then
            log_info "Network ${network} already exists"
        else
            docker network create "$network" --driver bridge
            log_success "Created network: ${network}"
        fi
    done
    
    save_state "networks"
    log_success "Docker networks configured"
}
```

**REPLACE WITH:**
```bash
create_docker_networks() {
    log_phase "PHASE 6: Preparing Docker Networks"
    
    if [ "${SETUP_PHASES[networks]}" -eq 1 ]; then
        log_info "Network preparation already completed - skipping"
        return 0
    fi
    
    # Clean up any pre-existing networks to prevent label conflicts
    # Docker Compose will create them with proper labels during deployment
    local networks=("ai-platform" "ai-platform-internal" "ai-platform-monitoring" "ai_platform_internal")
    
    log_info "Cleaning up any pre-existing networks..."
    
    for network in "${networks[@]}"; do
        if docker network inspect "$network" &> /dev/null 2>&1; then
            # Check if any containers are using this network
            local container_count=$(docker network inspect "$network" --format '{{len .Containers}}' 2>/dev/null || echo "0")
            
            if [ "$container_count" -eq 0 ]; then
                # Safe to remove - no containers attached
                if docker network rm "$network" &> /dev/null 2>&1; then
                    log_success "Removed pre-existing network: ${network}"
                else
                    log_warning "Could not remove network: ${network}"
                fi
            else
                log_warning "Network ${network} has ${container_count} active containers - skipping removal"
            fi
        fi
    done
    
    log_success "Network cleanup completed"
    log_info "Networks will be created by docker-compose with proper Compose labels"
    
    save_state "networks"
}
```

#### Fix #2: Update Compose Network Definitions (Lines ~1700-1750)

**FIND:**
```yaml
networks:
  ai-platform:
    name: ai-platform
    driver: bridge
  ai-platform-internal:
    name: ai-platform-internal
    driver: bridge
    internal: true
  ai-platform-monitoring:
    name: ai-platform-monitoring
    driver: bridge
```

**REPLACE WITH:**
```yaml
networks:
  ai-platform:
    name: ai-platform
    driver: bridge
    labels:
      com.docker.compose.project: ai-platform
      com.docker.compose.network: ai-platform
      ai-platform.network.type: public
  
  ai-platform-internal:
    name: ai-platform-internal
    driver: bridge
    internal: true
    labels:
      com.docker.compose.project: ai-platform
      com.docker.compose.network: ai-platform-internal
      ai-platform.network.type: internal
  
  ai-platform-monitoring:
    name: ai-platform-monitoring
    driver: bridge
    labels:
      com.docker.compose.project: ai-platform
      com.docker.compose.network: ai-platform-monitoring
      ai-platform.network.type: monitoring
```

### Testing the Fix

```bash
# 1. Clean everything
sudo ./0-complete-cleanup.sh
# Type: DELETE EVERYTHING

# 2. Run Script 1 with fix
sudo ./1-setup-system.sh
# Should complete without creating networks

# 3. Verify no networks exist yet
docker network ls | grep ai-platform
# Should return empty

# 4. Deploy (creates networks with proper labels)
sudo ./2-deploy-services.sh

# 5. Verify networks have correct labels
docker network inspect ai-platform-internal --format '{{.Labels}}' | grep com.docker.compose
# Should show: com.docker.compose.network=ai-platform-internal
```

---

## PART 2: GAP ANALYSIS - Scripts Alignment

### Current Architecture Overview

```
Script 0 (Cleanup) ────────────────────────────────┐
   ↓ Removes all Docker resources                  │
   ↓ Clears /opt/ai-platform                       │
   ↓                                                │
Script 1 (Setup/Collect) ─────────────────────────┤
   ↓ Detects hardware                               │ Working
   ↓ Collects config (domain, API keys)            │ But has
   ↓ Generates .env                                 │ network
   ↓ Creates docker-compose.yml skeleton           │ issue
   ↓                                                │
Script 2 (Deploy) ────────────────────────────────┤
   ↓ Reads docker-compose.yml                      │ PATH
   ↓ Deploys services in phases                    │ MISMATCH!
   ↓ Shows status                                   │
   ↓                                                │
Script 3 (Configure) ─────────────────────────────┤
   ↓ Minimal (~100 lines)                          │ Incomplete
   ↓ Tailscale, GDrive stubs only                  │
   ↓                                                │
Script 4 (Add Service) ───────────────────────────┘
   Template only, no AI services
```

### Critical Gaps Identified

#### Gap 1: PATH MISMATCH 🔴 **CRITICAL**

**Script 1:**
```bash
BASE_DIR="/opt/ai-platform"
ENV_FILE="${BASE_DIR}/.env"
COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"
```

**Script 2:**
```bash
BASE_DIR="/home/$REAL_USER/ai-platform"
DEPLOY_ROOT="$BASE_DIR/deployment"
COMPOSE_FILE="$STACK_DIR/docker-compose.yml"  # Different location!
```

**Impact:** Script 2 cannot find files created by Script 1

**Fix Required:** Align both scripts to use same base directory

#### Gap 2: Compose File is Skeleton Only

**Script 1 generates:**
```yaml
services:
  placeholder:
    image: hello-world
```

**Script 2 expects:** Actual service definitions (postgres, redis, ollama, etc.)

**Impact:** Script 2 has nothing to deploy

**Fix Required:** Script 1 must generate complete compose file

#### Gap 3: Network Label Mismatch (Current Issue)

Already covered in Part 1 - networks need Compose labels

#### Gap 4: Script 3 is Incomplete

**Current:** ~100 lines, only stubs
**Needed:** Database init, service config, integration tests

#### Gap 5: No Health Checking

**Script 2** assumes success but doesn't verify containers are actually healthy

---

## PART 3: MVP IMPLEMENTATION PLAN

### Phase 1: Fix Critical Path (Today - 2 hours)

#### Step 1.1: Align Base Directory

**In Script 1** (Line ~40):
```bash
# CHANGE FROM:
BASE_DIR="/opt/ai-platform"

# CHANGE TO:
REAL_USER="${SUDO_USER:-$USER}"
BASE_DIR="/home/$REAL_USER/ai-platform"
```

**In Script 2** (Line ~12):
```bash
# ALREADY CORRECT:
REAL_USER="${SUDO_USER:-$USER}"
BASE_DIR="/home/$REAL_USER/ai-platform"
```

**Verify both scripts use:**
- Same BASE_DIR
- Same .env location
- Same compose file location

#### Step 1.2: Fix Network Creation (From Part 1)

Apply the network fixes already detailed above.

#### Step 1.3: Generate Actual Compose File

**In Script 1, replace `generate_docker_compose()` function:**

```bash
generate_docker_compose() {
    log_phase "PHASE 14: Generating Docker Compose Configuration"
    
    if [ "${SETUP_PHASES[compose]}" -eq 1 ]; then
        log_info "Docker Compose already generated - skipping"
        return 0
    fi
    
    log_info "Generating complete docker-compose.yml..."
    
    # Create base structure
    cat > "$COMPOSE_FILE" <<'COMPOSE_HEADER'
version: '3.8'

networks:
  ai-platform:
    name: ai-platform
    driver: bridge
    labels:
      com.docker.compose.project: ai-platform
      com.docker.compose.network: ai-platform
  
  ai-platform-internal:
    name: ai-platform-internal
    driver: bridge
    internal: true
    labels:
      com.docker.compose.project: ai-platform
      com.docker.compose.network: ai-platform-internal
  
  ai-platform-monitoring:
    name: ai-platform-monitoring
    driver: bridge
    labels:
      com.docker.compose.project: ai-platform
      com.docker.compose.network: ai-platform-monitoring

volumes:
  postgres_data:
  redis_data:
  ollama_data:

services:
COMPOSE_HEADER

    # Add core infrastructure (always deployed)
    add_postgres_service
    add_redis_service
    
    # Add selected services
    [ "$ENABLE_QDRANT" = true ] && add_qdrant_service
    [ "$ENABLE_OLLAMA" = true ] && add_ollama_service
    [ "$ENABLE_LITELLM" = true ] && add_litellm_service
    [ "$ENABLE_OPENWEBUI" = true ] && add_openwebui_service
    [ "$ENABLE_MONITORING" = true ] && add_monitoring_services
    
    chmod 644 "$COMPOSE_FILE"
    chown "${REAL_UID}:${REAL_GID}" "$COMPOSE_FILE"
    
    log_success "Docker Compose generated with actual services"
    save_state "compose"
}

add_postgres_service() {
    cat >> "$COMPOSE_FILE" <<'EOF'
  postgres:
    image: postgres:15-alpine
    container_name: postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - ai-platform-internal
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
    labels:
      - "ai-platform.service=postgres"

EOF
}

add_redis_service() {
    cat >> "$COMPOSE_FILE" <<'EOF'
  redis:
    image: redis:7-alpine
    container_name: redis
    restart: unless-stopped
    command: redis-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - redis_data:/data
    networks:
      - ai-platform-internal
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 3s
      retries: 5
    labels:
      - "ai-platform.service=redis"

EOF
}

add_qdrant_service() {
    cat >> "$COMPOSE_FILE" <<'EOF'
  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    restart: unless-stopped
    volumes:
      - ${DATA_DIR}/qdrant:/qdrant/storage
    networks:
      - ai-platform-internal
      - ai-platform
    ports:
      - "6333:6333"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      - "ai-platform.service=qdrant"

EOF
}

add_ollama_service() {
    cat >> "$COMPOSE_FILE" <<EOF
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    volumes:
      - ollama_data:/root/.ollama
    networks:
      - ai-platform-internal
      - ai-platform
    ports:
      - "11434:11434"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      - "ai-platform.service=ollama"

EOF
}

add_litellm_service() {
    cat >> "$COMPOSE_FILE" <<'EOF'
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
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
      DATABASE_URL: postgresql://${POSTGRES_USER}:${DB_PASSWORD}@postgres:5432/${POSTGRES_DB}
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
    volumes:
      - ${CONFIG_DIR}/litellm/config.yaml:/app/config.yaml:ro
    networks:
      - ai-platform-internal
      - ai-platform
    ports:
      - "8010:4000"
    command: ["--config", "/app/config.yaml", "--port", "4000"]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      - "ai-platform.service=litellm"

EOF
}

add_openwebui_service() {
    cat >> "$COMPOSE_FILE" <<'EOF'
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: unless-stopped
    depends_on:
      - ollama
    environment:
      OLLAMA_BASE_URL: http://ollama:11434
    volumes:
      - ${DATA_DIR}/open-webui:/app/backend/data
    networks:
      - ai-platform
    ports:
      - "8080:8080"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      - "ai-platform.service=open-webui"

EOF
}

add_monitoring_services() {
    cat >> "$COMPOSE_FILE" <<'EOF'
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    volumes:
      - ${CONFIG_DIR}/prometheus:/etc/prometheus
      - ${DATA_DIR}/prometheus:/prometheus
    networks:
      - ai-platform-monitoring
    ports:
      - "9090:9090"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      - "ai-platform.service=prometheus"

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    depends_on:
      prometheus:
        condition: service_healthy
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${ADMIN_PASSWORD}
    volumes:
      - ${DATA_DIR}/grafana:/var/lib/grafana
    networks:
      - ai-platform-monitoring
      - ai-platform
    ports:
      - "3000:3000"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    labels:
      - "ai-platform.service=grafana"

EOF
}
```

### Phase 2: Add Health Checking to Script 2 (30 minutes)

**Replace `deploy_group()` function in Script 2:**

```bash
deploy_group() {
    local services=("$@")
    local failed=0
    
    for svc in "${services[@]}"; do
        if ! service_exists "$svc"; then
            echo -e "  ${YELLOW}⚠${NC} Service $svc not defined in compose - skipping"
            continue
        fi
        
        local image=$(grep -A 5 "  $svc:" "$COMPOSE_FILE" | grep "image:" | awk '{print $2}')
        
        echo -n -e "  🐳 ${BOLD}$svc${NC}: "
        
        # Deploy with error checking
        if ! docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d "$svc" >> "$LOG_FILE" 2>&1; then
            echo -e "${RED}FAILED${NC}"
            echo -e "     Error deploying $svc - check $LOG_FILE"
            docker compose -f "$COMPOSE_FILE" logs "$svc" --tail 20
            failed=$((failed + 1))
            continue
        fi
        
        # Wait for health check
        if wait_for_healthy "$svc" 60; then
            echo -e "${GREEN}✓ HEALTHY${NC}"
        else
            echo -e "${YELLOW}⚠ TIMEOUT${NC} (started but health check failed)"
        fi
    done
    
    return $failed
}

wait_for_healthy() {
    local service=$1
    local timeout=$2
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if ! docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
            sleep 2
            elapsed=$((elapsed + 2))
            continue
        fi
        
        local health=$(docker inspect --format='{{.State.Health.Status}}' "$service" 2>/dev/null || echo "none")
        
        case $health in
            healthy) return 0 ;;
            unhealthy) return 1 ;;
            none)
                # No healthcheck - verify running for 10s
                [ $elapsed -ge 10 ] && return 0
                ;;
        esac
        
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    return 1
}
```

### Phase 3: Create Minimal Script 3 (1 hour)

**Complete rewrite of Script 3:**

```bash
#!/bin/bash
set -euo pipefail

# Paths (align with Script 1 & 2)
REAL_USER="${SUDO_USER:-$USER}"
BASE_DIR="/home/$REAL_USER/ai-platform"
ENV_FILE="$BASE_DIR/.env"

# Load config
source "$ENV_FILE"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}→${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }

# Initialize databases
log_info "Initializing PostgreSQL databases..."
docker exec postgres psql -U aiplatform -c "CREATE DATABASE litellm;" 2>/dev/null || true
docker exec postgres psql -U aiplatform -c "CREATE DATABASE dify;" 2>/dev/null || true
log_success "Databases created"

# Pull Ollama models
if [ "$ENABLE_OLLAMA" = "true" ]; then
    log_info "Pulling Ollama models..."
    for model in ${OLLAMA_MODELS//,/ }; do
        docker exec ollama ollama pull "$model" &
    done
    wait
    log_success "Models pulled"
fi

# Test LiteLLM
if [ "$ENABLE_LITELLM" = "true" ]; then
    log_info "Testing LiteLLM..."
    if curl -sf http://localhost:8010/health &>/dev/null; then
        log_success "LiteLLM responding"
    fi
fi

echo ""
log_success "Configuration complete!"
echo ""
echo "Access URLs:"
[ "$ENABLE_OPENWEBUI" = "true" ] && echo "  Open WebUI: http://localhost:8080"
[ "$ENABLE_LITELLM" = "true" ] && echo "  LiteLLM:    http://localhost:8010"
echo ""
```

---

## PART 4: MVP EXECUTION CHECKLIST

### Prerequisites
- [ ] Fresh Ubuntu 22.04+ system
- [ ] Root/sudo access
- [ ] Internet connection
- [ ] At least 50GB free disk space

### Step-by-Step Execution

#### Step 1: Apply Fixes (Windsurf Tasks)

```bash
# Clone repo
git clone https://github.com/jgla1ne/AIPlatformAutomation.git
cd AIPlatformAutomation/scripts
```

**Task 1.1:** Fix Script 1 paths
- Line ~40: Change `BASE_DIR="/opt/ai-platform"` to use $REAL_USER home
- Verify: `BASE_DIR="/home/$REAL_USER/ai-platform"`

**Task 1.2:** Fix Script 1 networks
- Lines ~820-850: Replace `create_docker_networks()` with cleanup version
- Lines ~1700-1750: Add Compose labels to network definitions

**Task 1.3:** Fix Script 1 compose generation
- Lines ~1700-1826: Replace skeleton with actual service functions
- Add: `add_postgres_service()`, `add_redis_service()`, etc.

**Task 1.4:** Fix Script 2 health checks
- Lines ~60-90: Replace `deploy_group()` with error-checking version
- Add: `wait_for_healthy()` function

**Task 1.5:** Rewrite Script 3
- Replace entire file with minimal working version (100→400 lines)

#### Step 2: Test Clean Deployment

```bash
# Start fresh
sudo ./0-complete-cleanup.sh
# Type: DELETE EVERYTHING

# Run setup
sudo ./1-setup-system.sh
# Answer prompts:
# - Domain: test.local
# - SSL: n (no)
# - Services: y, y, y (LiteLLM, Ollama, OpenWebUI)
# - Monitoring: y

# Verify outputs
ls -la /home/$USER/ai-platform/
# Should see: .env, docker-compose.yml, config/, data/

# Check compose has services
grep -c "image:" /home/$USER/ai-platform/docker-compose.yml
# Should show: 6 or more (not just 1 for placeholder)

# Deploy
sudo ./2-deploy-services.sh
# Should deploy: postgres, redis, ollama, litellm, open-webui, prometheus, grafana

# Configure
sudo ./3-configure-services.sh
# Should: create databases, pull models, test connections

# Verify
docker ps
# Should show 7 running containers

# Test endpoints
curl http://localhost:11434  # Ollama
curl http://localhost:8010/health  # LiteLLM
curl http://localhost:8080  # OpenWebUI
```

#### Step 3: Validate MVP

**Success Criteria:**
- ✅ All 5 scripts execute without errors
- ✅ 7+ containers running and healthy
- ✅ OpenWebUI accessible at localhost:8080
- ✅ Can chat with local Ollama models
- ✅ Prometheus/Grafana showing metrics
- ✅ No network label errors

---

## PART 5: QUICK REFERENCE - File Locations

### Script 1 Critical Lines

```
Line ~40:  BASE_DIR definition
Line ~820: create_docker_networks() function
Line ~1700: generate_docker_compose() function
```

### Script 2 Critical Lines

```
Line ~12:  BASE_DIR definition (must match Script 1)
Line ~60:  deploy_group() function
Line ~100: Main deployment phases
```

### Script 3 - Complete Rewrite Needed

Replace entire file with minimal version provided above.

---

## PART 6: Troubleshooting

### If networks still fail:

```bash
# Emergency nuclear option
docker network prune -f
docker system prune -af --volumes
sudo ./0-complete-cleanup.sh
# Then re-run Scripts 1→2
```

### If compose file is empty:

```bash
# Check Script 1 completed
cat /home/$USER/ai-platform/docker-compose.yml
# Should have multiple services, not just placeholder

# If still skeleton, Script 1 didn't generate properly
# Check: ${ENABLE_OLLAMA} etc are "true" not empty
source /home/$USER/ai-platform/.env
echo $ENABLE_OLLAMA  # Should print "true"
```

### If Script 2 can't find files:

```bash
# Verify paths match
grep "BASE_DIR=" scripts/1-setup-system.sh
grep "BASE_DIR=" scripts/2-deploy-services.sh
# Both should show same path

# Check .env exists where Script 2 looks
ls -la /home/$USER/ai-platform/.env
ls -la /home/$USER/ai-platform/deployment/.secrets/.env
```

---

## Summary for Windsurf

**Priority 1 (Do First):**
1. Fix BASE_DIR alignment in Script 1 (line ~40)
2. Fix network creation in Script 1 (lines ~820-850, ~1700-1750)
3. Replace compose skeleton with actual services (lines ~1700-1826)

**Priority 2 (Do Second):**
4. Add health checks to Script 2 deploy_group() (lines ~60-90)

**Priority 3 (Do Third):**
5. Rewrite Script 3 with minimal working version

**Expected Result:**
Complete working end-to-end deployment in 3 script runs, 7+ healthy containers, accessible UIs.

**Time Estimate:** 4-6 hours total implementation
