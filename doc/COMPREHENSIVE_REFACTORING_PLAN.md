# 🔧 COMPREHENSIVE REFACTORING PLAN - ALL SCRIPTS

## Overview

This document outlines the complete refactoring strategy for all scripts in the AIPlatformAutomation project, ensuring consistency with the new modular architecture established in Script 1 v4.0.0.

---

## 📋 Current Script Inventory

| Script | Current Version | Purpose | Status |
|--------|----------------|---------|--------|
| 0-complete-cleanup.sh | v102.0.0 | System reset & cleanup | ❌ Needs refactoring |
| 1-setup-system.sh | v4.0.0 | Config collection & preparation | ✅ **REFACTORED** |
| 2-deploy-services.sh | v75.2.2 | Service deployment | ❌ Needs refactoring |
| 3-configure-services.sh | TBD | Service configuration | ❌ Needs creation |
| 4-add-service.sh | TBD | Add new services | ❌ Needs creation |

---

## 🎯 Core Principles (Apply to ALL Scripts)

### 1. **Separation of Concerns**
- Script 0: Cleanup only
- Script 1: Config collection only (✅ DONE)
- Script 2: Deployment only
- Script 3: Configuration only
- Script 4: Service addition only

### 2. **Metadata-Driven Execution**
All scripts after Script 1 read from:
```
/mnt/data/metadata/
├── configuration.json
├── selected_services.json
├── secrets.json
└── deployment_plan.json
```

### 3. **Modular File Structure**
All scripts work with:
```
/mnt/data/
├── compose/          # Individual service compose files
├── env/              # Individual service env files
├── config/           # Service-specific configs
└── metadata/         # Deployment metadata
```

### 4. **Idempotency**
- All scripts must be safely re-runnable
- State tracking for resumable operations
- Clear verification steps

### 5. **Error Handling**
- Comprehensive logging
- Clear error messages
- Rollback capabilities where applicable

---

## 📦 SCRIPT 0: COMPLETE CLEANUP (Refactoring Plan)

### Current Issues:
- ❌ References `/opt/ai-platform` (old structure)
- ❌ Doesn't clean `/mnt/data`
- ❌ Doesn't clean metadata files
- ❌ Not aligned with new modular structure

### Refactoring Goals:

#### Phase 1: Update Paths
```bash
# OLD
BASE_DIR="/opt/ai-platform"

# NEW
MNT_DATA="/mnt/data"
DEPLOY_BASE="/opt/ai-platform"
```

#### Phase 2: Enhanced Cleanup Targets

**NEW directories to clean:**
```bash
/mnt/data/
├── compose/     # Remove all *.yml files
├── env/         # Remove all *.env files
├── config/      # Remove all config directories
├── metadata/    # Remove all *.json files
└── logs/        # Remove log files
```

**Keep existing cleanup:**
- Docker containers with label: `ai-platform.service`
- Docker networks: `ai-platform*`
- Docker volumes: `ai-platform-*`
- `/opt/ai-platform/` (deployment directory)

#### Phase 3: Service-Aware Cleanup

Add detection for services by reading metadata:
```bash
# If metadata exists, read selected services
if [ -f "/mnt/data/metadata/selected_services.json" ]; then
    # Parse JSON and show what will be deleted
    # More targeted cleanup
fi
```

#### Phase 4: Cleanup Order
```
1. Stop all running containers
2. Remove containers (by label)
3. Remove networks
4. Remove volumes
5. Clean /mnt/data/ structure
6. Clean /opt/ai-platform/ (if exists)
7. Clean Docker images (optional)
8. Verify cleanup
```

#### New Features:
- **Dry-run mode**: Show what would be deleted without doing it
- **Selective cleanup**: Clean only certain services
- **Backup option**: Create backup before cleanup

### Expected Output Files:
```bash
/mnt/data/logs/cleanup-YYYYMMDD-HHMMSS.log
```

---

## 🚀 SCRIPT 2: DEPLOY SERVICES (Complete Refactoring)

### Current Issues:
- ❌ Hardcoded service list
- ❌ Monolithic deployment approach
- ❌ Doesn't read metadata
- ❌ Mixed responsibilities

### NEW Architecture: Metadata-Driven Deployment

#### Core Workflow:
```
1. Read /mnt/data/metadata/deployment_plan.json
2. Validate all required files exist
3. Create final deployment structure
4. Merge compose files
5. Deploy services in order
6. Verify each service
7. Generate deployment report
```

### Detailed Phase Breakdown:

#### PHASE 1: Metadata Validation (NEW)
```bash
validate_metadata() {
    # Check all required metadata files exist
    required_files=(
        "configuration.json"
        "selected_services.json"
        "secrets.json"
        "deployment_plan.json"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "${METADATA_DIR}/${file}" ]; then
            log_error "Missing metadata: ${file}"
            exit 1
        fi
    done
}
```

#### PHASE 2: File Validation
```bash
validate_service_files() {
    local service=$1
    
    # Check compose file
    if [ ! -f "${COMPOSE_DIR}/${service}.yml" ]; then
        log_error "Missing compose: ${service}.yml"
        return 1
    fi
    
    # Check env file
    if [ ! -f "${ENV_DIR}/${service}.env" ]; then
        log_warning "Missing env: ${service}.env (using defaults)"
    fi
    
    # Validate compose syntax
    docker compose -f "${COMPOSE_DIR}/${service}.yml" config > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log_error "Invalid compose syntax: ${service}.yml"
        return 1
    fi
}
```

#### PHASE 3: Deployment Structure Creation
```bash
create_deployment_structure() {
    # Create deployment directories
    mkdir -p "${DEPLOY_BASE}"/{data,logs,backups,config}
    
    # Copy configs
    cp -r "${CONFIG_DIR}"/* "${DEPLOY_BASE}/config/"
    
    # Set permissions
    chown -R "${DEPLOY_USER}:${DEPLOY_GROUP}" "${DEPLOY_BASE}"
}
```

#### PHASE 4: Compose File Merging (NEW)
```bash
merge_compose_files() {
    log_info "Merging compose files..."
    
    local deployment_order=$(jq -r '.deployment_order[]' "${METADATA_DIR}/deployment_plan.json")
    local compose_args=""
    
    # Build compose file list
    for service in $deployment_order; do
        if [ -f "${COMPOSE_DIR}/${service}.yml" ]; then
            compose_args="${compose_args} -f ${COMPOSE_DIR}/${service}.yml"
            log_info "Added: ${service}.yml"
        fi
    done
    
    # Create merged compose file
    docker compose ${compose_args} config > "${DEPLOY_BASE}/docker-compose.yml"
    
    log_success "Merged compose file created"
}
```

#### PHASE 5: Service Deployment
```bash
deploy_services() {
    local deployment_order=$(jq -r '.deployment_order[]' "${METADATA_DIR}/deployment_plan.json")
    
    for service in $deployment_order; do
        log_phase "Deploying: ${service}"
        
        # Validate service files
        if ! validate_service_files "$service"; then
            log_error "Validation failed: ${service}"
            continue
        fi
        
        # Deploy service
        docker compose -f "${COMPOSE_DIR}/${service}.yml" \
                       --env-file "${ENV_DIR}/${service}.env" \
                       up -d
        
        # Wait for healthy
        wait_for_service_healthy "$service"
        
        # Verify service
        verify_service_deployment "$service"
        
        log_success "Deployed: ${service}"
    done
}
```

#### PHASE 6: Service Health Checks
```bash
wait_for_service_healthy() {
    local service=$1
    local max_wait=300  # 5 minutes
    local interval=5
    local elapsed=0
    
    log_info "Waiting for ${service} to be healthy..."
    
    while [ $elapsed -lt $max_wait ]; do
        if docker ps --filter "name=${service}" --filter "health=healthy" | grep -q "${service}"; then
            log_success "${service} is healthy"
            return 0
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
        echo -n "."
    done
    
    log_error "${service} failed to become healthy within ${max_wait}s"
    return 1
}
```

#### PHASE 7: Service Verification
```bash
verify_service_deployment() {
    local service=$1
    
    # Check container running
    if ! docker ps | grep -q "${service}"; then
        log_error "${service} container not running"
        return 1
    fi
    
    # Check port accessibility (if applicable)
    case "$service" in
        postgres)
            verify_postgres
            ;;
        redis)
            verify_redis
            ;;
        ollama)
            verify_ollama
            ;;
        # Add more service-specific checks
    esac
}
```

#### PHASE 8: Deployment Report
```bash
generate_deployment_report() {
    cat > "${DEPLOY_BASE}/deployment-report.json" <<EOF
{
    "timestamp": "$(date -Iseconds)",
    "version": "4.0.0",
    "services_deployed": $(docker ps --filter "label=ai-platform.service" --format "{{.Names}}" | jq -R . | jq -s .),
    "containers_running": $(docker ps --filter "label=ai-platform.service" -q | wc -l),
    "networks_created": $(docker network ls --filter "name=ai-platform" --format "{{.Name}}" | jq -R . | jq -s .),
    "volumes_created": $(docker volume ls --filter "name=ai-platform" --format "{{.Name}}" | jq -R . | jq -s .)
}
EOF
}
```

### Key Features:
- ✅ Reads deployment plan from metadata
- ✅ Validates all files before deployment
- ✅ Merges individual compose files
- ✅ Deploys services in correct order
- ✅ Health checks for each service
- ✅ Comprehensive error handling
- ✅ Deployment report generation

---

## ⚙️ SCRIPT 3: CONFIGURE SERVICES (NEW - Create from Scratch)

### Purpose:
Post-deployment configuration of services (database initialization, API connections, integrations)

### Workflow:
```
1. Read deployed services from metadata
2. Initialize databases (create schemas, users)
3. Configure service integrations
4. Set up proxy routes
5. Initialize vector databases
6. Configure monitoring
7. Verify configurations
```

### Phase Breakdown:

#### PHASE 1: Database Initialization
```bash
initialize_databases() {
    log_phase "Database Initialization"
    
    # Load database credentials from secrets
    source_secrets
    
    # PostgreSQL initialization
    if service_is_deployed "postgres"; then
        initialize_postgres
    fi
    
    # Redis initialization
    if service_is_deployed "redis"; then
        initialize_redis
    fi
    
    # Vector DB initialization
    local vector_db=$(get_vector_db_type)
    case "$vector_db" in
        qdrant)
            initialize_qdrant
            ;;
        weaviate)
            initialize_weaviate
            ;;
        milvus)
            initialize_milvus
            ;;
    esac
}
```

#### PHASE 2: PostgreSQL Service Databases
```bash
initialize_postgres() {
    log_info "Initializing PostgreSQL databases..."
    
    # Wait for postgres ready
    wait_for_postgres
    
    # Create databases for each service
    if service_is_deployed "n8n"; then
        create_service_database "n8n" "${N8N_DB_USER}" "${N8N_DB_PASSWORD}" "${N8N_DB_NAME}"
    fi
    
    if service_is_deployed "dify"; then
        create_service_database "dify" "${DIFY_DB_USER}" "${DIFY_DB_PASSWORD}" "${DIFY_DB_NAME}"
    fi
    
    if service_is_deployed "flowise"; then
        create_service_database "flowise" "${FLOWISE_DB_USER}" "${FLOWISE_DB_PASSWORD}" "${FLOWISE_DB_NAME}"
    fi
    
    if service_is_deployed "litellm"; then
        create_service_database "litellm" "${LITELLM_DB_USER}" "${LITELLM_DB_PASSWORD}" "${LITELLM_DB_NAME}"
    fi
    
    if service_is_deployed "langfuse"; then
        create_service_database "langfuse" "${LANGFUSE_DB_USER}" "${LANGFUSE_DB_PASSWORD}" "${LANGFUSE_DB_NAME}"
    fi
}

create_service_database() {
    local service=$1
    local db_user=$2
    local db_password=$3
    local db_name=$4
    
    log_info "Creating database for ${service}..."
    
    docker exec ai-platform-postgres psql -U postgres <<EOF
CREATE DATABASE ${db_name};
CREATE USER ${db_user} WITH ENCRYPTED PASSWORD '${db_password}';
GRANT ALL PRIVILEGES ON DATABASE ${db_name} TO ${db_user};
EOF
    
    log_success "Database created: ${db_name}"
}
```

#### PHASE 3: Service Integrations
```bash
configure_service_integrations() {
    log_phase "Configuring Service Integrations"
    
    # LiteLLM → Ollama integration
    if service_is_deployed "litellm" && service_is_deployed "ollama"; then
        configure_litellm_ollama
    fi
    
    # OpenWebUI → Ollama integration
    if service_is_deployed "openwebui" && service_is_deployed "ollama"; then
        configure_openwebui_ollama
    fi
    
    # Dify → Vector DB integration
    if service_is_deployed "dify"; then
        configure_dify_vectordb
    fi
    
    # N8N → PostgreSQL integration
    if service_is_deployed "n8n"; then
        configure_n8n_database
    fi
}
```

#### PHASE 4: Proxy Configuration
```bash
configure_proxy_routes() {
    local proxy_type=$(get_proxy_type)
    
    case "$proxy_type" in
        nginx)
            configure_nginx_routes
            ;;
        traefik)
            configure_traefik_routes
            ;;
        caddy)
            configure_caddy_routes
            ;;
        none)
            log_info "No proxy configured"
            ;;
    esac
}

configure_nginx_routes() {
    log_info "Configuring Nginx routes..."
    
    local base_domain=$(get_base_domain)
    
    # Create site configs for each service
    if service_is_deployed "openwebui"; then
        create_nginx_site "openwebui" "chat.${base_domain}" "3000"
    fi
    
    if service_is_deployed "litellm"; then
        create_nginx_site "litellm" "api.${base_domain}" "8000"
    fi
    
    if service_is_deployed "n8n"; then
        create_nginx_site "n8n" "n8n.${base_domain}" "5678"
    fi
    
    # Reload Nginx
    docker exec ai-platform-nginx nginx -s reload
}
```

#### PHASE 5: Vector Database Setup
```bash
initialize_qdrant() {
    log_info "Initializing Qdrant..."
    
    wait_for_service_healthy "qdrant"
    
    # Create default collections for each service
    if service_is_deployed "dify"; then
        create_qdrant_collection "dify_knowledge" 1536
    fi
    
    if service_is_deployed "anythingllm"; then
        create_qdrant_collection "anythingllm_docs" 1536
    fi
}

create_qdrant_collection() {
    local name=$1
    local vector_size=$2
    
    curl -X PUT "http://localhost:6333/collections/${name}" \
         -H "Content-Type: application/json" \
         -d "{
           \"vectors\": {
             \"size\": ${vector_size},
             \"distance\": \"Cosine\"
           }
         }"
}
```

#### PHASE 6: Monitoring Setup
```bash
configure_monitoring() {
    if ! service_is_deployed "monitoring"; then
        return 0
    fi
    
    log_info "Configuring monitoring stack..."
    
    # Configure Prometheus targets
    configure_prometheus_targets
    
    # Import Grafana dashboards
    import_grafana_dashboards
    
    # Configure Loki log sources
    configure_loki_sources
}
```

#### PHASE 7: Configuration Verification
```bash
verify_configurations() {
    log_phase "Verifying Configurations"
    
    local errors=0
    
    # Verify database connections
    for service in $(get_deployed_services); do
        if requires_database "$service"; then
            if ! verify_database_connection "$service"; then
                log_error "Database connection failed: ${service}"
                errors=$((errors + 1))
            fi
        fi
    done
    
    # Verify service integrations
    if ! verify_service_integrations; then
        log_error "Service integration verification failed"
        errors=$((errors + 1))
    fi
    
    # Verify proxy routes
    if ! verify_proxy_routes; then
        log_error "Proxy route verification failed"
        errors=$((errors + 1))
    fi
    
    if [ $errors -eq 0 ]; then
        log_success "All configurations verified"
        return 0
    else
        log_error "Configuration verification failed with ${errors} error(s)"
        return 1
    fi
}
```

---

## ➕ SCRIPT 4: ADD SERVICE (NEW - Create from Scratch)

### Purpose:
Add new services to an existing deployment without full redeployment

### Workflow:
```
1. Read current deployment state
2. Prompt for new service selection
3. Check compatibility
4. Generate service files
5. Update metadata
6. Deploy new service
7. Configure integrations
8. Verify deployment
```

### Phase Breakdown:

#### PHASE 1: Current State Analysis
```bash
analyze_current_deployment() {
    log_phase "Analyzing Current Deployment"
    
    # Read current services
    local current_services=$(jq -r '.deployment_order[]' "${METADATA_DIR}/deployment_plan.json")
    
    echo "Currently deployed services:"
    for service in $current_services; do
        echo "  ✓ ${service}"
    done
    
    # Check available services
    local available_services=(
        "ollama" "litellm" "openwebui" "anythingllm" "dify"
        "n8n" "flowise" "signal-api" "gdrive" "langfuse"
        "prometheus" "grafana" "loki"
    )
    
    echo ""
    echo "Available services to add:"
    for service in "${available_services[@]}"; do
        if ! echo "$current_services" | grep -q "^${service}$"; then
            echo "  • ${service}"
        fi
    done
}
```

#### PHASE 2: Service Selection
```bash
select_new_service() {
    echo ""
    read -p "Enter service name to add: " new_service
    
    # Validate service exists
    if ! service_is_valid "$new_service"; then
        log_error "Unknown service: ${new_service}"
        exit 1
    fi
    
    # Check if already deployed
    if service_is_deployed "$new_service"; then
        log_error "Service already deployed: ${new_service}"
        exit 1
    fi
    
    # Check dependencies
    if ! check_service_dependencies "$new_service"; then
        log_error "Missing dependencies for ${new_service}"
        exit 1
    fi
    
    log_success "Selected: ${new_service}"
}
```

#### PHASE 3: File Generation
```bash
generate_service_files() {
    local service=$1
    
    log_info "Generating files for ${service}..."
    
    # Generate compose file
    generate_compose_file_for_service "$service"
    
    # Generate env file
    generate_env_file_for_service "$service"
    
    # Generate configs (if needed)
    generate_config_for_service "$service"
    
    log_success "Files generated for ${service}"
}
```

#### PHASE 4: Metadata Update
```bash
update_metadata() {
    local service=$1
    
    log_info "Updating metadata..."
    
    # Update selected_services.json
    jq --arg service "$service" \
       '.ai_services[$service] = true' \
       "${METADATA_DIR}/selected_services.json" > /tmp/selected.json
    mv /tmp/selected.json "${METADATA_DIR}/selected_services.json"
    
    # Update deployment_plan.json
    local new_order=$(jq -r '.deployment_order[]' "${METADATA_DIR}/deployment_plan.json")
    new_order="${new_order}
${service}"
    
    jq --arg order "$new_order" \
       '.deployment_order = ($order | split("\n"))' \
       "${METADATA_DIR}/deployment_plan.json" > /tmp/plan.json
    mv /tmp/plan.json "${METADATA_DIR}/deployment_plan.json"
    
    log_success "Metadata updated"
}
```

#### PHASE 5: Service Deployment
```bash
deploy_new_service() {
    local service=$1
    
    log_info "Deploying ${service}..."
    
    # Deploy using compose file
    docker compose -f "${COMPOSE_DIR}/${service}.yml" \
                   --env-file "${ENV_DIR}/${service}.env" \
                   up -d
    
    # Wait for healthy
    wait_for_service_healthy "$service"
    
    log_success "Deployed: ${service}"
}
```

#### PHASE 6: Service Configuration
```bash
configure_new_service() {
    local service=$1
    
    log_info "Configuring ${service}..."
    
    # Database initialization (if needed)
    if requires_database "$service"; then
        initialize_service_database "$service"
    fi
    
    # Service-specific configuration
    case "$service" in
        litellm)
            configure_litellm
            ;;
        n8n)
            configure_n8n
            ;;
        dify)
            configure_dify
            ;;
        # Add more services
    esac
    
    # Update proxy routes
    update_proxy_routes "$service"
    
    log_success "Configured: ${service}"
}
```

#### PHASE 7: Integration Testing
```bash
test_new_service() {
    local service=$1
    
    log_info "Testing ${service}..."
    
    # Test container health
    if ! docker ps --filter "name=${service}" --filter "health=healthy" | grep -q "${service}"; then
        log_error "Service not healthy: ${service}"
        return 1
    fi
    
    # Test service endpoint
    if ! test_service_endpoint "$service"; then
        log_error "Endpoint test failed: ${service}"
        return 1
    fi
    
    # Test integrations
    if ! test_service_integrations "$service"; then
        log_error "Integration test failed: ${service}"
        return 1
    fi
    
    log_success "All tests passed: ${service}"
}
```

---

## 🔄 Script Interdependencies

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  Script 0 (Cleanup)                                         │
│    • Cleans /mnt/data/                                      │
│    • Removes all containers/networks/volumes                │
│    • Resets system state                                    │
│    └─→ Prepares for fresh installation                      │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Script 1 (Setup) ✅ DONE                                   │
│    • Collects configuration                                 │
│    • Generates modular files                                │
│    • Creates metadata                                       │
│    └─→ Outputs to /mnt/data/                                │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Script 2 (Deploy)                                          │
│    • Reads metadata from /mnt/data/metadata/                │
│    • Merges compose files                                   │
│    • Deploys services                                       │
│    └─→ Creates /opt/ai-platform/                            │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Script 3 (Configure)                                       │
│    • Reads deployment state                                 │
│    • Initializes databases                                  │
│    • Configures integrations                                │
│    └─→ Makes services fully functional                      │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Script 4 (Add Service)                                     │
│    • Reads current deployment                               │
│    • Adds new service                                       │
│    • Updates metadata                                       │
│    └─→ Extends existing deployment                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 📊 Shared Library (NEW - Create)

### Purpose:
Common functions used across all scripts

### File: `scripts/lib/common.sh`

```bash
#!/bin/bash

#==============================================================================
# SHARED LIBRARY FOR AI PLATFORM AUTOMATION
# Version: 4.0.0
# Purpose: Common functions for all scripts
#==============================================================================

# Paths
export MNT_DATA="/mnt/data"
export COMPOSE_DIR="${MNT_DATA}/compose"
export ENV_DIR="${MNT_DATA}/env"
export CONFIG_DIR="${MNT_DATA}/config"
export METADATA_DIR="${MNT_DATA}/metadata"
export DEPLOY_BASE="/opt/ai-platform"

# Metadata readers
get_base_domain() {
    jq -r '.network.base_domain' "${METADATA_DIR}/configuration.json"
}

get_proxy_type() {
    jq -r '.network.proxy_type' "${METADATA_DIR}/configuration.json"
}

get_vector_db_type() {
    jq -r '.core_infrastructure.vector_db' "${METADATA_DIR}/selected_services.json"
}

get_deployed_services() {
    jq -r '.deployment_order[]' "${METADATA_DIR}/deployment_plan.json"
}

service_is_deployed() {
    local service=$1
    docker ps --filter "name=${service}" --format "{{.Names}}" | grep -q "^ai-platform-${service}$"
}

# Secret management
load_secrets() {
    if [ -f "${METADATA_DIR}/secrets.json" ]; then
        export DB_MASTER_PASSWORD=$(jq -r '.db_master_password' "${METADATA_DIR}/secrets.json")
        export ADMIN_PASSWORD=$(jq -r '.admin_password' "${METADATA_DIR}/secrets.json")
        export JWT_SECRET=$(jq -r '.jwt_secret' "${METADATA_DIR}/secrets.json")
        # Load more secrets as needed
    fi
}

# Service validation
service_is_valid() {
    local service=$1
    local valid_services=(
        "postgres" "redis" "qdrant" "weaviate" "milvus"
        "nginx" "traefik" "caddy"
        "ollama" "litellm" "openwebui" "anythingllm" "dify"
        "n8n" "flowise" "signal-api" "gdrive"
        "langfuse" "prometheus" "grafana" "loki"
    )
    
    for valid in "${valid_services[@]}"; do
        if [ "$service" = "$valid" ]; then
            return 0
        fi
    done
    return 1
}

# More common functions...
```

---

## 🧪 Testing Strategy

### Unit Testing (Per Script)
Each script should have:
- Dry-run mode
- Validation-only mode
- Verbose logging

### Integration Testing (Cross-Script)
Test the full workflow:
```bash
# Full deployment test
./0-complete-cleanup.sh --yes
./1-setup-system.sh --automated
./2-deploy-services.sh --verify
./3-configure-services.sh --verify
```

### Rollback Testing
Each script should support:
- State save points
- Rollback to previous state
- Error recovery

---

## 📝 Documentation Updates

### Per-Script Documentation
Each script needs:
```
scripts/
├── 0-complete-cleanup.sh
│   └── docs/
│       ├── README.md
│       ├── EXAMPLES.md
│       └── TROUBLESHOOTING.md
├── 1-setup-system.sh (✅ DONE)
├── 2-deploy-services.sh
│   └── docs/
└── (etc)
```

### Central Documentation
Update main docs:
- README.md (architecture overview)
- DEPLOYMENT-GUIDE.md (step-by-step)
- TROUBLESHOOTING.md (common issues)
- ARCHITECTURE.md (system design)

---

## ⏱️ Implementation Timeline

### Phase 1: Core Scripts (Week 1)
- ✅ Script 1 (DONE)
- Script 0 refactoring
- Script 2 refactoring

### Phase 2: Configuration (Week 2)
- Script 3 creation
- Service templates
- Integration configs

### Phase 3: Extensions (Week 3)
- Script 4 creation
- Shared library
- Testing utilities

### Phase 4: Documentation (Week 4)
- Per-script docs
- Central docs
- Video tutorials

---

## 🎯 Success Criteria

### Script 0
- ✅ Cleans all /mnt/data/ files
- ✅ Removes all Docker resources
- ✅ Provides dry-run mode
- ✅ Creates cleanup report

### Script 1
- ✅ **COMPLETE** - All requirements met

### Script 2
- ✅ Reads metadata correctly
- ✅ Merges compose files
- ✅ Deploys in correct order
- ✅ Verifies each service
- ✅ Creates deployment report

### Script 3
- ✅ Initializes all databases
- ✅ Configures service integrations
- ✅ Sets up proxy routes
- ✅ Verifies configurations

### Script 4
- ✅ Adds services without redeployment
- ✅ Updates metadata correctly
- ✅ Configures new services
- ✅ Tests integrations

---

## 🔐 Security Considerations

### All Scripts Must:
1. Never log secrets
2. Use 600 permissions for credential files
3. Validate all inputs
4. Sanitize user-provided data
5. Use prepared statements for SQL
6. Avoid eval with user input

### Specific Requirements:
- Script 0: Verify deletion targets before cleanup
- Script 1: Encrypt secrets at rest (✅ DONE)
- Script 2: Validate compose files before deployment
- Script 3: Use parameterized database queries
- Script 4: Verify service compatibility

---

## 📊 Monitoring & Observability

### Each Script Should Log:
- Start/end timestamps
- Phase execution times
- Errors with context
- Warnings with suggestions
- Success confirmations

### Centralized Logging:
```
/mnt/data/logs/
├── cleanup-YYYYMMDD-HHMMSS.log
├── setup-YYYYMMDD-HHMMSS.log
├── deployment-YYYYMMDD-HHMMSS.log
├── configuration-YYYYMMDD-HHMMSS.log
└── add-service-YYYYMMDD-HHMMSS.log
```

---

## 🚀 Next Steps

1. **Review this plan** - Validate approach and priorities
2. **Refactor Script 0** - Align with new structure
3. **Refactor Script 2** - Implement metadata-driven deployment
4. **Create Script 3** - Build configuration automation
5. **Create Script 4** - Build service addition workflow
6. **Create shared library** - Extract common functions
7. **Test end-to-end** - Validate full workflow
8. **Document everything** - Create comprehensive docs

---

## 📋 Summary

This comprehensive refactoring plan ensures:
- ✅ Consistent architecture across all scripts
- ✅ Metadata-driven execution
- ✅ Modular file structure
- ✅ Clear separation of concerns
- ✅ Comprehensive error handling
- ✅ Full idempotency
- ✅ Complete observability
- ✅ Extensible design

All scripts will work together seamlessly to provide a production-ready, maintainable, and scalable AI platform automation system.
