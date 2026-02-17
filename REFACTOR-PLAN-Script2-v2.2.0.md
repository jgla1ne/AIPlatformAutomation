# Script 2 Refactor Plan v2.2.0
**Based on Comprehensive Gap Analysis - February 17, 2026**

---

## 🎯 EXECUTIVE SUMMARY

**Current State:** Script 2 progresses through phases but fails due to 4 distinct infrastructure/permissions issues. All business logic (compose structure, proxy generation, service ordering) is working correctly.

**Root Causes:** Infrastructure and permission issues, not business logic failures.

---

## 🚨 CRITICAL ISSUES IDENTIFIED

### **Issue 1: Prometheus Config Missing (CRITICAL)**
- **Problem:** Prometheus crashes immediately - no `/etc/prometheus/prometheus.yml`
- **Impact:** Blocks entire monitoring stack
- **Fix:** Generate config before container start

### **Issue 2: Grafana Volume Permissions (CRITICAL)**
- **Problem:** Grafana runs as UID 472, host volume owned by root
- **Impact:** Permission denied, blocks metrics UI
- **Fix:** Pre-create volume and chown to 472:472

### **Issue 3: Ollama Volume Path (CRITICAL)**
- **Problem:** Ollama writes to `/.ollama` (root path)
- **Impact:** Permission denied, blocks all AI services
- **Fix:** Correct volume mount to user-writable path

### **Issue 4: Redis Health Check (HIGH)**
- **Problem:** Health check uses `localhost:6379` from outside container
- **Impact:** Spurious timeout warnings
- **Fix:** Use in-container `docker exec redis redis-cli ping`

---

## 🔧 DETAILED FIX IMPLEMENTATION

### **Fix 1: Prometheus Config Generation**

**Location:** `scripts/2-deploy-services.sh` - Config Generation section

```bash
generate_prometheus_config() {
    local config_dir="${DATA_ROOT}/config/prometheus"
    mkdir -p "${config_dir}"
    
    cat > "${config_dir}/prometheus.yml" <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres:5432']
  - job_name: 'redis'
    static_configs:
      - targets: ['redis:6379']
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
EOF
    
    log_info "Prometheus config generated at ${config_dir}/prometheus.yml"
}
```

**Integration:** Call immediately after proxy config generation:
```bash
# In deployment setup phase (before docker compose up prometheus):
generate_prometheus_config
```

**Compose Volume Mount:**
```yaml
prometheus:
  volumes:
  - ./config/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
  - ./volumes/prometheus:/prometheus
```

---

### **Fix 2: Grafana Volume Permissions**

**Location:** `scripts/2-deploy-services.sh` - Permissions Setup section

```bash
fix_grafana_permissions() {
    local grafana_vol="${DATA_ROOT}/volumes/grafana"
    mkdir -p "${grafana_vol}"
    
    # Grafana's internal UID is 472
    chown -R 472:472 "${grafana_vol}"
    chmod 755 "${grafana_vol}"
    
    log_info "Grafana volume permissions set (UID 472)"
}
```

**Integration:** Add to permissions setup block:
```bash
log_debug "Fixing volume permissions..."
fix_postgres_volume_permissions
fix_redis_volume_permissions
fix_grafana_permissions  # ← ADD THIS
fix_ollama_permissions  # ← ADD THIS
```

---

### **Fix 3: Ollama Volume Path**

**Location:** `docker-compose.yml` - Ollama service definition

**Current (WRONG):**
```yaml
ollama:
  volumes:
    - /.ollama:/ollama  # ← ROOT PATH - WRONG
```

**Corrected:**
```yaml
ollama:
  environment:
    - OLLAMA_HOME=/ollama_data
  volumes:
    - ./volumes/ollama:/ollama_data  # ← USER PATH - CORRECT
  user: "${RUNNING_UID}:${RUNNING_GID}"
```

**Permission Fix Function:**
```bash
fix_ollama_permissions() {
    local ollama_vol="${DATA_ROOT}/volumes/ollama"
    mkdir -p "${ollama_vol}"
    chown -R "${RUNNING_UID}:${RUNNING_GID}" "${ollama_vol}"
    chmod 755 "${ollama_vol}"
    
    log_info "Ollama volume permissions set"
}
```

---

### **Fix 4: Redis Health Check**

**Location:** `scripts/2-deploy-services.sh` - Enhanced Wait Mechanisms

**Current (WRONG):**
```bash
wait_for_port localhost 6379 60  # ← FROM OUTSIDE CONTAINER
```

**Corrected:**
```bash
wait_for_redis() {
    local max_attempts=60
    local attempt=0
    
    log_info "Waiting for Redis to respond..."
    
    while [ $attempt -lt $max_attempts ]; do
        if docker exec redis redis-cli ping 2>/dev/null | grep -q PONG; then
            log_success "Redis is ready"
            return 0
        fi
        sleep 1
        ((attempt++))
    done
    
    log_error "Redis failed to respond to ping"
    return 1
}
```

**Integration:** Update deployment function:
```bash
"redis")
    if wait_for_redis; then
        echo -e "${GREEN}✓ HEALTHY${NC}"
    else
        echo -e "${YELLOW}⚠ RUNNING (health check timeout)${NC}"
    fi
    ;;
```

---

## 📋 CORRECTED DEPLOYMENT ORDER

### **Phase 0: Pre-Deployment Setup**
1. **Generate configs** (Prometheus, SSL, etc.)
2. **Fix permissions** (Grafana, Ollama, PostgreSQL, Redis)
3. **Create volumes** (All service volumes)

### **Phase 1: Core Infrastructure**
1. **PostgreSQL** (wait for healthy)
2. **Redis** (wait for ping response)

### **Phase 2: Monitoring Stack**
1. **Prometheus** (config exists, wait for healthy)
2. **Grafana** (permissions fixed, wait for healthy)

### **Phase 3: AI Services**
1. **Ollama** (volume fixed, wait for API response)
2. **LiteLLM** (depends on Ollama, PostgreSQL)
3. **OpenWebUI** (depends on Ollama)
4. **AnythingLLM** (depends on PostgreSQL)
5. **Dify** (depends on PostgreSQL, Redis)

### **Phase 4: Application Services**
1. **n8n** (depends on PostgreSQL, Redis)
2. **Flowise** (depends on PostgreSQL)

### **Phase 5: Storage & Network**
1. **MinIO** (independent)
2. **Tailscale** (independent)
3. **OpenClaw** (depends on LiteLLM, n8n)

### **Phase 6: Proxy Layer**
1. **Caddy** (generate config, start last)

---

## 🔧 IMPLEMENTATION CHECKLIST

### **Scripts/2-deploy-services.sh Changes:**
- [ ] Add `generate_prometheus_config()` function
- [ ] Add `fix_grafana_permissions()` function  
- [ ] Add `fix_ollama_permissions()` function
- [ ] Add `wait_for_redis()` function
- [ ] Update deployment order with new phases
- [ ] Integrate config generation in setup phase
- [ ] Update permissions setup block
- [ ] Fix Redis health check calls

### **Docker Compose Changes:**
- [ ] Fix Ollama volume mount (`/.ollama` → `./volumes/ollama:/ollama_data`)
- [ ] Add OLLAMA_HOME environment variable
- [ ] Add Prometheus config volume mount
- [ ] Verify Grafana volume mount path

### **Validation Steps:**
- [ ] Prometheus config generated before container start
- [ ] Grafana volume owned by UID 472
- [ ] Ollama volume owned by RUNNING_UID
- [ ] Redis responds to ping from inside container
- [ ] All services start without permission errors

---

## 🎯 SUCCESS CRITERIA

### **Gate 1: Infrastructure Ready**
- ✅ Prometheus config exists at start
- ✅ All volumes pre-created with correct ownership
- ✅ No permission errors in deployment logs

### **Gate 2: Core Services Healthy**
- ✅ PostgreSQL responds to `pg_isready`
- ✅ Redis responds to `redis-cli ping`

### **Gate 3: Monitoring Stack Running**
- ✅ Prometheus healthy (config loaded)
- ✅ Grafana healthy (no permission errors)

### **Gate 4: AI Services Ready**
- ✅ Ollama API accessible (`/api/tags`)
- ✅ LiteLLM healthy (depends on Ollama)
- ✅ All AI services responding

### **Gate 5: Full System Operational**
- ✅ All 15 services deployed
- ✅ No "permission denied" errors
- ✅ Health checks passing
- ✅ Proxy serving traffic

---

## 🚀 IMPLEMENTATION PRIORITY

### **Priority 1: Critical Infrastructure (Day 1)**
1. Prometheus config generation
2. Volume permission fixes
3. Redis health check fix

### **Priority 2: Service Dependencies (Day 1)**
1. Ollama volume path fix
2. Deployment order corrections
3. Enhanced wait mechanisms

### **Priority 3: Validation & Testing (Day 2)**
1. End-to-end deployment testing
2. Service accessibility verification
3. Error handling validation

---

## 📊 EXPECTED OUTCOME

**After Refactor:**
- ✅ Zero infrastructure failures
- ✅ All services start successfully
- ✅ Health checks pass
- ✅ No permission errors
- ✅ Complete 15-service deployment
- ✅ Ready for Script 3

**Result:** Script 2 v2.2.0 - Production Ready

---

**Status:** Ready for implementation with detailed fix specifications
