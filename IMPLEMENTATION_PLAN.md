# IMPLEMENTATION PLAN - AI Platform Fixes
## Based on AI Architect Review in doc/CLAUDE.md

**Phase 1: Script 1 - Foundation Fixes**
**Phase 2: Script 2 - Deployment Fixes** 
**Phase 3: Script 3 - Mission Control Fixes**

Each phase will be committed/pushed individually with sanity checks.

---

## PHASE 1: Script 1 (1-setup-system.sh) - Foundation Fixes

### 1.1 Tenant Collection & Path Derivation
**Location**: Top of `main()` function (after line 26)
**Changes**: Add tenant collection FIRST, before any other variables

```bash
# Collect tenant identity FIRST - before any other variables
if [ -z "${TENANT:-}" ]; then
    read -p "Tenant ID (e.g. datasquiz, no spaces): " TENANT_NAME
    TENANT_NAME="${TENANT_NAME// /_}"   # sanitise
else
    TENANT_NAME="${TENANT}"
fi

# ALL paths derive from this single variable - no exceptions
DATA_ROOT="/mnt/data/${TENANT_NAME}"
BASE_DIR="/opt/ai-platform"
CONFIG_DIR="${DATA_ROOT}/configs"
DATA_DIR="${DATA_ROOT}/data"
LOGS_DIR="${DATA_ROOT}/logs"
COMPOSE_FILE="${DATA_ROOT}/docker-compose.yml"
ENV_FILE="${BASE_DIR}/.env"
```

### 1.2 Environment File Generation - Dependency Order
**Location**: `generate_env_file()` function
**Changes**: Write variables in dependency order with resolved values

### 1.3 PostgreSQL Init Script - Honour Env Variables
**Location**: `generate_postgres_init()` function
**Changes**: Create per-service databases with correct ownership

### 1.4 Docker Compose Generation - Real Services
**Location**: `generate_docker_compose()` function
**Changes**: Generate actual service blocks based on ENABLE_* flags

### 1.5 Directory Creation - UID-Aware Ownership
**Location**: `create_directory_structure()` function
**Changes**: Set ownership to match container UIDs

---

## PHASE 2: Script 2 (2-deploy-services.sh) - Deployment Fixes

### 2.1 Path Resolution - Single Source of Truth
**Location**: Top of script
**Changes**: Remove path guessing, use .env as single source

### 2.2 Service Detection - Replace Broken Logic
**Location**: Replace `service_exists()` function
**Changes**: Use `service_is_enabled()` based on ENABLE_* flags

### 2.3 Database Provisioning - Critical Missing Step
**Location**: New function `provision_databases()`
**Changes**: Wait for postgres, create per-service databases

### 2.4 Deployment Order - Correct Sequence
**Location**: `main()` function
**Changes**: Infra → DB Provision → Services → Monitoring

---

## PHASE 3: Script 3 (3-configure-services.sh) - Mission Control Fixes

### 3.1 Color Variables - Fix Undefined References
**Location**: Top of script
**Changes**: Define all color variables

### 3.2 Optional Function Guards - Prevent Crashes
**Location**: Wrap optional functions
**Changes**: Guard GDrive, Tailscale operations

### 3.3 Path References - Fix Compose Path
**Location**: Multiple functions
**Changes**: Use `${COMPOSE_FILE}` from .env

### 3.4 Main Function Call - Actually Execute
**Location**: End of script
**Changes**: Add `main "$@"` call

---

## SANITY CHECKS AFTER EACH PHASE

### After Phase 1:
```bash
# 1. .env is readable and has correct values
grep "POSTGRES_USER\|POSTGRES_DB\|LITELLM_DATABASE_URL\|COMPOSE_FILE" /opt/ai-platform/.env

# 2. Compose file exists at path referenced in .env
source /opt/ai-platform/.env && ls -la "${COMPOSE_FILE}"

# 3. Postgres init script exists and has variables resolved
cat /mnt/data/<tenant>/configs/postgres/init-all-databases.sh | head -20
```

### After Phase 2:
```bash
# 4. After deploying: all per-service databases exist
docker compose exec postgres psql -U ${POSTGRES_USER} -c "\l" | grep -E "litellm|openwebui|n8n"

# 5. Services start without unbound variable errors
bash -x scripts/2-deploy-services.sh 2>&1 | grep -E "unbound|not set"
```

### After Phase 3:
```bash
# 6. Script 3 exits cleanly with no errors
bash -x scripts/3-configure-services.sh 2>&1 | tail -20

# 7. Optional functions are properly guarded
scripts/3-configure-services.sh --help 2>&1 | grep -E "GDrive|Tailscale"
```

---

## IMPLEMENTATION SEQUENCE

### Step 1: Phase 1 Implementation
- Modify `scripts/1-setup-system.sh`
- Commit: "Phase 1: Foundation fixes - tenant collection, path derivation, env ordering"
- Push to origin
- Run sanity checks

### Step 2: Phase 2 Implementation  
- Modify `scripts/2-deploy-services.sh`
- Commit: "Phase 2: Deployment fixes - path resolution, DB provisioning, service detection"
- Push to origin
- Run sanity checks

### Step 3: Phase 3 Implementation
- Modify `scripts/3-configure-services.sh`
- Commit: "Phase 3: Mission control fixes - color vars, guards, main call"
- Push to origin
- Run sanity checks

### Step 4: Integration Testing
- Fresh deployment test with new tenant
- Verify all services start healthy
- Full stack validation

---

## CRITICAL SUCCESS CRITERIA

1. **No Unbound Variables**: All scripts run without `unbound variable` errors
2. **Correct Paths**: All services find their configuration files
3. **Database Provisioning**: Per-service databases created automatically
4. **Service Independence**: Services can start without hard dependencies
5. **Deterministic Deployment**: Same inputs produce same outputs every time

---

## RISKS & MITIGATIONS

### Risk 1: Breaking Live Deployment
**Mitigation**: Test with new tenant name first
**Backup**: Current working state is in git

### Risk 2: Environment Variable Conflicts
**Mitigation**: Clear all inherited vars at script start
**Validation**: Check .env file contents after generation

### Risk 3: Permission Issues
**Mitigation**: UID-aware directory creation
**Validation**: Check container logs for permission denied

---

## ESTIMATED TIMELINE

- **Phase 1**: 2-3 hours (foundation is complex)
- **Phase 2**: 1-2 hours (deployment logic)
- **Phase 3**: 1 hour (mission control fixes)
- **Integration Testing**: 2-3 hours
- **Total**: 6-9 hours

---

## NEXT ACTIONS

1. **Start Phase 1** - Begin with tenant collection fixes
2. **Commit After Each Phase** - Maintain git history
3. **Run Sanity Checks** - Verify each phase before proceeding
4. **Document Progress** - Update implementation plan as needed

This plan ensures we address ALL root causes identified by the AI architect while maintaining script structure and following core principles.
