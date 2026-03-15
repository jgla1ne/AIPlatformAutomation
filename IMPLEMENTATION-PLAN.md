# AI Platform Architecture Recovery Plan
# Grounded in README.md Core Principles
# Implementation Phases with Commit/Push Strategy

## **🎯 EXECUTIVE SUMMARY**

**Objective**: Fix 6 architectural violations to achieve 100% deterministic deployment
**Approach**: Systematic phase-based fixes aligned with README.md modular architecture
**Timeline**: 4 implementation phases with validation after each phase

---

## **📊 CURRENT STATE ANALYSIS**

### **Root Cause Synthesis (CHATGPT.md + CLAUDE.md)**

| Violation | Impact | Phase Fix Required |
|----------|--------|-------------------|
| Broken Deployment Lifecycle | Non-deterministic startup | All phases |
| Environment Variable Gaps | Service failures | Phase 1 |
| Database Bootstrap Failure | Connection errors | Phase 1 |
| LiteLLM Model Mismatch | Gateway restart loop | Phase 1+3 |
| Storage Permission Issues | Service write failures | Phase 2 |
| Network/Routing Failures | Services unreachable | Phase 2+3 |

### **README.md Compliance Status**
✅ **Core Principles Intact**: 5 scripts only, zero hardcodes, modular architecture
❌ **Implementation Violations**: Phase boundaries blurred, missing configurations

---

## **🔧 IMPLEMENTATION PLAN**

### **PHASE 1: Foundation Fixes (Script 1)**
**Focus**: Complete environment generation and database bootstrap

#### **1.1 PostgreSQL Bootstrap Fix**
```bash
# Target: scripts/1-setup-system.sh -> generate_postgres_init()
# Action: Replace SQL with executable shell script
```

**Changes Required:**
- Create `postgres/init-user-db.sh` with proper user/database creation
- Remove hardcoded `ds-admin` references
- Add idempotent database creation for all services

#### **1.2 Environment Variable Completeness**
```bash
# Target: scripts/1-setup-system.sh -> generate_env_file()
# Action: Add missing derived variables
```

**Variables to Add:**
```bash
# Derived Connection Strings
DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}
LITELLM_DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/litellm
OPENWEBUI_DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/openwebui

# Service Configuration
TENANT=${BASE_DOMAIN}
OPENWEBUI_DB_PASSWORD=${DB_PASSWORD}
REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379

# Service Ports (for health dashboard)
PORT_LITELLM=4000
PORT_OPENWEBUI=3000
PORT_N8N=5678
PORT_GRAFANA=3002
PORT_PROMETHEUS=9090
PORT_QDRANT=6333
```

#### **1.3 LiteLLM Config Generation Fix**
```bash
# Target: scripts/1-setup-system.sh -> generate_litellm_config()
# Action: Use os.environ/VAR_NAME syntax, remove shell expansions
```

**Config Pattern:**
```yaml
model_list:
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: os.environ/OPENAI_API_KEY  # Runtime env var, not hardcoded
```

---

### **PHASE 2: Deployment Fixes (Script 2)**
**Focus**: Container startup, permissions, and health checks

#### **2.1 Qdrant Storage Permissions**
```bash
# Target: scripts/2-deploy-services.sh -> pre-deployment block
# Action: Set ownership before container start
```

**Code Addition:**
```bash
# Fix Qdrant storage ownership before deployment
QDRANT_STORAGE="${DATA_DIR}/qdrant"
mkdir -p "${QDRANT_STORAGE}" "${QDRANT_STORAGE}/snapshots"
chown -R 1000:1001 "${QDRANT_STORAGE}"
chmod -R 750 "${QDRANT_STORAGE}"
```

#### **2.2 Caddy Dependency Cleanup**
```bash
# Target: scripts/2-deploy-services.sh -> add_caddy()
# Action: Remove application service dependencies
```

**Dependency Change:**
```yaml
caddy:
  depends_on:
    postgres:
      condition: service_healthy
    redis:
      condition: service_healthy
    # Remove: openwebui, grafana, prometheus, qdrant
```

#### **2.3 Health Check Corrections**
```bash
# Target: All service definitions in script 2
# Action: Fix broken endpoints
```

**Corrections:**
- Qdrant: `/readyz` → `/collections`
- LiteLLM: `/health` → `/health/liveliness`
- Caddy: `/config/` → `/metrics`

#### **2.4 UID/GID Variable References**
```bash
# Target: All service definitions
# Action: Replace hardcoded UIDs with env vars
```

**Pattern:**
```yaml
# Before: user: "1000:1001"
# After:  user: "${QDRANT_UID:-1000}:${TENANT_GID:-1001}"
```

---

### **PHASE 3: Configuration Fixes (Script 3)**
**Focus**: Service configuration without violating boundaries

#### **3.1 LiteLLM Configuration Removal**
```bash
# Target: scripts/3-configure-services.sh
# Action: Delete configure_litellm_routing() entirely
```

**Replacement:**
```bash
verify_litellm() {
    echo "[INFO] Waiting for LiteLLM to become healthy..."
    for i in $(seq 1 18); do
        if curl -sf "http://localhost:${PORT_LITELLM:-4000}/health/liveliness" > /dev/null 2>&1; then
            echo "[OK] LiteLLM is healthy"
            return 0
        fi
        sleep 10
    done
    echo "[WARN] LiteLLM did not become healthy within 3 minutes"
}
```

#### **3.2 Tailscale Integration Fix**
```bash
# Target: scripts/3-configure-services.sh -> configure_tailscale()
# Action: Use existing compose service, not new container
```

**Implementation:**
```bash
configure_tailscale() {
    [[ -n "${TAILSCALE_AUTH_KEY:-}" ]] || { echo "[INFO] TAILSCALE_AUTHKEY not set — skipping"; return 0; }
    
    echo "[INFO] Authenticating Tailscale (compose service)..."
    docker compose exec -T tailscale tailscale up \
        --authkey="${TAILSCALE_AUTH_KEY}" \
        --hostname="${TENANT:-ai-platform}" \
        --accept-routes
    
    # Capture IP for dashboard
    TAILSCALE_IP=$(docker compose exec -T tailscale tailscale ip -4 2>/dev/null | tr -d ' \n' || echo "")
    if [[ -n "$TAILSCALE_IP" ]]; then
        echo "TAILSCALE_IP=${TAILSCALE_IP}" >> "${ENV_FILE}"
    fi
}
```

#### **3.3 Health Dashboard Implementation**
```bash
# Target: scripts/3-configure-services.sh -> print_health_dashboard()
# Action: Real endpoint testing with proper port variables
```

**Dashboard Features:**
- Tailscale IP display
- Service health checks
- URL accessibility tests
- LiteLLM model verification

---

### **PHASE 4: Integration & Validation**
**Focus**: End-to-end testing and documentation

#### **4.1 README.md Review Updates**
```bash
# Target: README.md
# Action: Update deployment results section
```

**Updates:**
- Current deployment status (75% → 100%)
- Fixed issues summary
- Validation metrics

#### **4.2 Architecture Documentation**
```bash
# Target: doc/ARCHITECTURE-FIXES.md
# Action: Create comprehensive fix documentation
```

**Content:**
- Before/after comparisons
- Fix validation checklist
- Troubleshooting guide

---

## **🚀 EXECUTION SEQUENCE**

### **Pre-Implementation**
```bash
# 1. Current state backup
git checkout -b architecture-recovery

# 2. Validate current issues
docker compose ps
grep -rn "ds-admin" scripts/ 2>/dev/null
```

### **Implementation Steps**
```bash
# Phase 1: Foundation Fixes
echo "=== PHASE 1: Foundation Fixes ==="
# Edit scripts/1-setup-system.sh
git add scripts/1-setup-system.sh
git commit -m "Phase 1: Complete environment generation and database bootstrap"
git push origin main

# Phase 2: Deployment Fixes  
echo "=== PHASE 2: Deployment Fixes ==="
# Edit scripts/2-deploy-services.sh
git add scripts/2-deploy-services.sh
git commit -m "Phase 2: Container permissions, health checks, and dependency cleanup"
git push origin main

# Phase 3: Configuration Fixes
echo "=== PHASE 3: Configuration Fixes ==="
# Edit scripts/3-configure-services.sh
git add scripts/3-configure-services.sh
git commit -m "Phase 3: Service configuration without boundary violations"
git push origin main

# Phase 4: Integration & Documentation
echo "=== PHASE 4: Integration & Documentation ==="
# Update README.md and create documentation
git add README.md doc/
git commit -m "Phase 4: Documentation updates and architecture validation"
git push origin main
```

### **Post-Implementation Validation**
```bash
# Clean deployment test
docker compose down -v
bash scripts/1-setup-system.sh
bash scripts/2-deploy-services.sh
bash scripts/3-configure-services.sh

# Expected result: 100% service health
docker compose ps
```

---

## **📋 VALIDATION CHECKLIST**

### **README.md Compliance**
- [ ] 5 scripts only (0-3)
- [ ] Zero hardcoded values
- [ ] Dynamic compose generation
- [ ] Non-root execution
- [ ] Data confinement
- [ ] True modularity

### **Technical Validation**
- [ ] All environment variables defined
- [ ] PostgreSQL databases created automatically
- [ ] LiteLLM starts without config overwrite
- [ ] Qdrant permissions correct
- [ ] Caddy starts independently
- [ ] Health dashboard functional
- [ ] Tailscale IP displayed

### **Service Health Targets**
- [ ] PostgreSQL: healthy
- [ ] Redis: healthy
- [ ] Qdrant: healthy
- [ ] LiteLLM: healthy
- [ ] Grafana: healthy
- [ ] Prometheus: healthy
- [ ] Caddy: running
- [ ] Tailscale: connected

---

## **🎯 EXPECTED OUTCOMES**

### **Deployment Success Rate**
- **Before**: 75% (5/6 services)
- **After**: 100% (6/6 services)

### **Architecture Compliance**
- **Before**: 6 violations
- **After**: 0 violations

### **Deterministic Deployment**
- **Before**: Non-deterministic (random failures)
- **After**: Deterministic (repeatable success)

### **Service Discovery**
- **Before**: Partial (only n8n, grafana visible)
- **After**: Complete (all services accessible)

---

## **🔄 ROLLBACK STRATEGY**

If any phase introduces issues:
```bash
# Rollback to last working commit
git log --oneline -5  # Identify last good commit
git revert <commit-hash>  # Revert problematic commit
git push origin main
```

---

## **📊 SUCCESS METRICS**

1. **Zero Docker warnings** (no undefined variables)
2. **Zero permission errors** (all services write to storage)
3. **Zero restart loops** (all services stable)
4. **Complete health dashboard** (all services monitored)
5. **Deterministic deployment** (repeatable success)

---

**This plan maintains README.md core principles while systematically fixing all identified architectural violations. Each phase is independently testable and commit-ready.**
