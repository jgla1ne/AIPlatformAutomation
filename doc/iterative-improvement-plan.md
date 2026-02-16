# AI Platform Automation - Focused Improvement Plan

**Date:** February 16, 2026  
**Status:** Script 1 working, Scripts 2-5 need fixes  
**Goal:** Minimal re-engineering to achieve complete end-to-end working deployment  
**Constraint:** Keep current implementation (domain=localhost, proxy type selection, etc.)

---

## Current State Assessment

### What Actually Works ✅
- **Script 1 (Setup):** ✅ Fully functional after syntax fixes
  - Hardware detection working
  - User input collection working  
  - .env generation working
  - Secret generation working
  - Volume detection working (EBS fdisk)
  - Domain configuration (localhost) working
  - Service selection working

- **Script 0 (Cleanup):** ✅ Fully functional
  - Removes all Docker resources
  - Handles /mnt/data cleanup properly

### What Needs Critical Fixes ❌
- **Script 1:** ❌ Generates incomplete compose file (skeleton only)
- **Script 2:** ❌ 5/13 services failing due to missing compose definitions
- **Script 3:** ❌ Skeleton only, missing post-deployment configuration
- **Script 4:** ❌ UI/catalog complete but no actual deployment logic

---

## Root Cause Analysis

### Issue 1: Script 1 Generates Empty Compose File ⚠️ CRITICAL
**Problem:** Script 1 generates skeleton compose file instead of complete service definitions
**Impact:** Script 2 can't deploy services that don't exist in compose file
**Fix:** Script 1 must generate COMPLETE compose file with all selected services

### Issue 2: Volume Mount Paths Not in .env
**Problem:** .env doesn't include volume path variables like POSTGRES_DATA
**Impact:** Services can't mount volumes, fail to start
**Fix:** Add volume path variables to .env generation

### Issue 3: Missing Service Dependencies
**Problem:** Services start before dependencies are healthy
**Impact:** Services fail because dependencies aren't ready
**Fix:** Add health checks and wait logic in Script 2

### Issue 4: Database Initialization Missing
**Problem:** Databases for litellm, dify, n8n don't exist
**Impact:** Services fail when trying to connect to non-existent databases
**Fix:** Add init scripts or Script 3 creates databases

---

## Minimal Fix Strategy (Maintaining Current Implementation)

### Phase 1: Fix Script 1 Compose Generation (CRITICAL - 2 hours)

**Objective:** Generate complete docker-compose.yml based on service selection

**Key Requirements:**
- Maintain current domain=localhost approach
- Keep proxy type selection functionality
- Preserve existing service selection logic
- Add complete service definitions with proper dependencies

**Implementation in Script 1 `generate_compose_templates()` function:**

```bash
generate_compose_templates() {
    log_phase "11" "🐳" "Compose Template Generation"
    
    # Generate complete compose file based on selected services
    cat > "$COMPOSE_FILE" <<'COMPOSE_HEADER'
version: '3.8'

networks:
  ai-platform:
    name: ai-platform
    driver: bridge
  ai-platform-internal:
    name: ai-platform-internal
    driver: bridge
    internal: true

volumes:
  postgres_data:
    driver: local
  redis_data:
    driver: local
  ollama_data:
    driver: local

services:
COMPOSE_HEADER

    # Always add core infrastructure
    add_postgres_service
    add_redis_service
    
    # Add selected services based on user selection
    [ "$ENABLE_OLLAMA" = true ] && add_ollama_service
    [ "$ENABLE_LITELLM" = true ] && add_litellm_service
    [ "$ENABLE_DIFY" = true ] && add_dify_services
    [ "$ENABLE_N8N" = true ] && add_n8n_service
    [ "$ENABLE_FLOWISE" = true ] && add_flowise_service
    [ "$ENABLE_ANYTHINGLLM" = true ] && add_anythingllm_service
    [ "$ENABLE_OPENWEBUI" = true ] && add_openwebui_service
    [ "$ENABLE_MONITORING" = true ] && add_monitoring_services
    
    chmod 644 "$COMPOSE_FILE"
    chown "${REAL_UID}:${REAL_GID}" "$COMPOSE_FILE"
    
    log_success "Docker Compose templates generated with non-root user mapping"
    mark_phase_complete "generate_compose_templates"
}
```

### Phase 2: Fix Script 2 Health Checks (CRITICAL - 1 hour)

**Objective:** Add proper health checking and error handling

**Implementation in Script 2 `deploy_service()` function:**

```bash
deploy_service() {
    local service="$1"
    
    echo -e "  🐳 ${BOLD}$service${NC}: "
    
    # Pull image
    if ! docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull "$service" >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}FAILED TO PULL${NC}"
        return 1
    fi
    
    # Start service
    if ! docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d "$service" >> "$LOG_FILE" 2>&1; then
        echo -e "${RED}FAILED TO START${NC}"
        docker compose -f "$COMPOSE_FILE" logs "$service" --tail 20
        return 1
    fi
    
    # Wait for health
    if wait_for_healthy "$service" 60; then
        echo -e "${GREEN}✓ HEALTHY${NC}"
        display_service_info "$service"
    else
        echo -e "${YELLOW}⚠ RUNNING (health check timeout)${NC}"
    fi
}

wait_for_healthy() {
    local service="$1"
    local timeout="${2:-30}"
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        local health=$(docker inspect --format='{{.State.Health.Status}}' "$service" 2>/dev/null || echo "no_healthcheck")
        
        if [ "$health" = "healthy" ]; then
            return 0
        elif [ "$health" = "unhealthy" ]; then
            return 1
        elif [ "$health" = "no_healthcheck" ]; then
            # No healthcheck defined, verify running for 10s
            if [ $elapsed -ge 10 ]; then
                return 0
            fi
        fi
        
        sleep 2
        elapsed=$((elapsed + 2))
    done
    
    return 1
}
```

### Phase 3: Fix Script 3 Database Initialization (CRITICAL - 1 hour)

**Objective:** Initialize databases and configure services

**Implementation in Script 3:**

```bash
#!/bin/bash
# Script 3: Post-Deployment Configuration
# Purpose: Initialize databases, configure services, test integrations

set -euo pipefail

# Load environment
source "/mnt/data/ai-platform/deployment/.secrets/.env"

initialize_databases() {
    log_phase "1" "🗄️" "Database Initialization"
    
    # Wait for postgres to be fully ready
    log_info "Waiting for PostgreSQL..."
    local retries=0
    while [ $retries -lt 30 ]; do
        if docker exec postgres pg_isready -U aiplatform &>/dev/null; then
            log_success "PostgreSQL ready"
            break
        fi
        sleep 2
        retries=$((retries + 1))
    done
    
    # Create databases for each service
    log_info "Creating databases..."
    
    docker exec postgres psql -U aiplatform -c "CREATE DATABASE litellm;" 2>/dev/null || log_info "  litellm database already exists"
    docker exec postgres psql -U aiplatform -c "CREATE DATABASE dify;" 2>/dev/null || log_info "  dify database already exists"
    docker exec postgres psql -U aiplatform -c "CREATE DATABASE n8n;" 2>/dev/null || log_info "  n8n database already exists"
    docker exec postgres psql -U aiplatform -c "CREATE DATABASE flowise;" 2>/dev/null || log_info "  flowise database already exists"
    
    log_success "Databases initialized"
}

configure_litellm() {
    log_phase "2" "🔗" "LiteLLM Configuration"
    
    # Initialize LiteLLM database
    log_info "Initializing LiteLLM database schema..."
    docker exec litellm python -c "from litellm.proxy.proxy_server import initialize; initialize()" 2>/dev/null || true
    
    # Test LiteLLM health
    log_info "Testing LiteLLM API..."
    if curl -s -f http://localhost:8010/health &>/dev/null; then
        log_success "LiteLLM API responding"
    else
        log_error "LiteLLM API not responding"
        return 1
    fi
}

# Main execution
main() {
    initialize_databases
    configure_litellm
    log_success "Post-deployment configuration completed"
}

main "$@"
```

---

## Success Criteria

### Phase 1 Success (Script 1):
- ✅ Complete docker-compose.yml generated with all selected services
- ✅ All service definitions include proper dependencies
- ✅ Volume paths correctly defined in .env
- ✅ Non-root user mapping preserved
- ✅ Domain=localhost configuration maintained

### Phase 2 Success (Script 2):
- ✅ All 13 services deploy without errors
- ✅ Health checks pass for all services
- ✅ Dependencies properly ordered
- ✅ Clear success/failure reporting
- ✅ Logs captured for troubleshooting

### Phase 3 Success (Script 3):
- ✅ Databases created for all services
- ✅ LiteLLM database schema initialized
- ✅ Service integrations tested
- ✅ All services responding to health checks

---

## Implementation Constraints

### Maintain Current Features:
- ✅ Domain=localhost (keep as-is)
- ✅ Proxy type selection (keep as-is)
- ✅ Service selection UI (keep as-is)
- ✅ Non-root user mapping (keep as-is)
- ✅ Volume detection (keep as-is)
- ✅ 5-script architecture (keep as-is)

### Minimal Changes Only:
- ✅ Fix compose generation in Script 1
- ✅ Add health checks in Script 2
- ✅ Add database init in Script 3
- ✅ No major refactoring
- ✅ Preserve existing code structure

---

## Testing Plan

### Test Sequence:
1. **Script 1 Test:** Verify complete compose file generation
2. **Script 2 Test:** Deploy all services with health checks
3. **Script 3 Test:** Initialize databases and configure services
4. **Integration Test:** Verify all services communicate
5. **End-to-End Test:** Full deployment pipeline

### Success Metrics:
- **Zero deployment errors** in Script 2
- **All 13 services healthy** after deployment
- **Proper service integration** (LiteLLM → Ollama, etc.)
- **Maintained compatibility** with existing .env format

---

## Timeline

- **Phase 1:** 2 hours (Script 1 compose generation)
- **Phase 2:** 1 hour (Script 2 health checks)
- **Phase 3:** 1 hour (Script 3 database init)
- **Testing:** 1 hour (integration testing)
- **Total:** 5 hours to achieve zero deployment errors

This plan focuses on minimal, targeted fixes while preserving all existing functionality and implementation specifics.
