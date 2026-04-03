# AI Platform Automation - Refactoring Blueprint v1.0
# North Star: Unified README.md as Platform Definition

## 🎯 REFACTORING OBJECTIVES

### Primary Goals
- **Ground all scripts in unified README.md** as definitive platform specification
- **Eliminate architectural drift** between scripts and documentation
- **Implement strict 4-script modular boundaries** with clear responsibilities
- **Enforce non-root execution** with proper permission handling
- **Standardize all configurations** under `/mnt/${TENANT_ID}/` only
- **Complete Mission Control Hub** capabilities in Script 3
- **Implement complete Script 1 interactive input collection**
- **Add comprehensive validation and error handling**

### Success Metrics
- All scripts fully implement README specifications
- Zero configuration drift between scripts and docs
- Complete end-to-end deployment success
- All 25 services properly configured and manageable
- Mission Control Hub provides full platform management

## 📋 CURRENT STATE ANALYSIS

### Script 0: Nuclear Cleanup
**Status**: ✅ Mostly correct
**Issues**: 
- DATA_DIR validation needs `/mnt` and `/opt` support
- Missing systemctl daemon-reload after fstab updates
- Incomplete container removal patterns

### Script 1: System Setup & Input Collection
**Status**: ⚠️ Major gaps vs README
**Missing**:
- Complete interactive input collection (identity, storage, stack presets, TLS, API keys)
- EBS volume detection and mounting workflow
- DNS resolution and validation
- Port conflict pre-checking
- Proper platform.conf generation with all 95+ variables
- Tenant user creation with proper permissions

### Script 2: Deployment Engine
**Status**: ⚠️ Partial implementation
**Missing**:
- Complete configuration generation for all services
- Proper dependency ordering in docker-compose.yml
- GPU support validation and configuration
- Service-specific health waiting
- Complete port binding and network configuration

### Script 3: Mission Control Hub
**Status**: ⚠️ Incomplete capabilities
**Missing**:
- Complete service management functions (add, remove, disable, enable)
- Health dashboard generation with dynamic URLs
- Credential management and key rotation
- End-to-end integration testing
- Complete shared utility functions library

## 🏗️ REFACTORING PLAN

### Phase 1: Foundation (Script 0 & Shared Utilities)
**Priority**: Critical - Must be done first

#### Script 0 Enhancements
```bash
# Enhanced nuclear cleanup with complete removal
enhanced_cleanup() {
    # 1. Remove all platform containers (all tenants)
    # 2. Remove all platform networks
    # 3. Remove all platform volumes (with confirmation)
    # 4. Remove all configured markers
    # 5. Clean up both /mnt and /opt paths
    # 6. Reload systemd daemons if needed
}
```

#### Shared Utilities Library (Script 3)
```bash
# Complete utility functions for all scripts
# System Operations
check_dependencies() { ... }
check_docker_group() { ... }
check_non_root() { ... }
detect_system_resources() { ... }

# Docker Operations
docker_health_check() { ... }
wait_for_service() { ... }
docker_pull() { ... }

# Configuration Management
load_platform_conf() { ... }
validate_configuration() { ... }
generate_secret() { ... }

# Directory Operations
create_directories() { ... }
setup_permissions() { ... }
mount_ebs_volume() { ... }

# Network Operations
validate_domain() { ... }
test_connectivity() { ... }
configure_dns() { ... }

# Service Management (Mission Control only)
restart_service() { ... }
add_service() { ... }
remove_service() { ... }
disable_service() { ... }
enable_service() { ... }
```

### Phase 2: Input Collection (Script 1)
**Priority**: Critical - Foundation for everything else

#### Complete Interactive Input Collection
```bash
# 1. Identity Configuration
collect_identity() {
    # Platform prefix selection (ai-, prod-, staging-, dev-, custom)
    # Tenant ID validation (alphanumeric only)
    # Domain validation (format + DNS resolution)
}

# 2. Storage Configuration
configure_storage() {
    # EBS volume detection and selection
    # Volume formatting and mounting
    # fstab updates and persistence
    # OS disk fallback option
}

# 3. Stack Preset Selection
select_stack_preset() {
    # minimal, dev, standard, full, custom
    # Apply preset defaults automatically
    # Custom service enablement if needed
}

# 4. LLM Gateway Configuration
configure_llm_gateway() {
    # LiteLLM (multi-provider)
    # Bifrost (lightweight Go)
    # Direct Ollama (single LLM)
}

# 5. Vector Database Selection
configure_vector_db() {
    # Qdrant, Weaviate, ChromaDB, Milvus
    # Service compatibility validation
}

# 6. TLS Configuration
configure_tls() {
    # Let's Encrypt (automatic)
    # Manual certificate (file paths)
    # Self-signed (org details)
    # No TLS (HTTP only)
}

# 7. API Key Collection
collect_api_keys() {
    # OpenAI, Anthropic, Google, Groq, OpenRouter
    # Provider enable/disable based on key presence
}

# 8. Port Configuration
configure_ports() {
    # All service ports with defaults
    # Conflict detection and validation
}

# 9. Final Validation
validate_and_generate_conf() {
    # Complete configuration summary
    # User confirmation
    # platform.conf generation with all 95+ variables
}
```

### Phase 3: Deployment Engine (Script 2)
**Priority**: High - Core platform deployment

#### Complete Configuration Generation
```bash
# Generate all service configurations
generate_all_configs() {
    # Caddy configuration (TLS-aware)
    # LiteLLM configuration (multi-provider)
    # Bifrost configuration (lightweight)
    # All Web UI configurations
    # Vector database configurations
    # Database configurations
    # Monitoring configurations
}

# Generate complete docker-compose.yml
generate_compose() {
    # Service dependency ordering
    # Network configuration
    # Volume mounting
    # Port binding
    # Environment variables
    # Health checks
    # GPU support
}
```

#### Enhanced Deployment Process
```bash
deploy_platform() {
    # 1. Pre-deployment validation
    # 2. Pull all required images
    # 3. Create networks and volumes
    # 4. Deploy in dependency order
    # 5. Wait for core infrastructure
    # 6. Wait for LLM services
    # 7. Wait for web services
    # 8. Verify all integrations
}
```

### Phase 4: Mission Control Hub (Script 3)
**Priority**: High - Platform management and operations

#### Complete Service Management
```bash
# Service lifecycle management
restart_service() { ... }
add_service() { ... }
remove_service() { ... }
disable_service() { ... }
enable_service() { ... }

# Health monitoring and dashboard
generate_health_dashboard() {
    # Dynamic URL generation
    # Service status indicators
    # Health check commands
    # Integration testing
}

# Credential management
show_credentials() { ... }
rotate_service_keys() { ... }

# End-to-end testing
verify_all_services() { ... }
test_integrations() { ... }
```

## 📁 FILE STRUCTURE REORGANIZATION

### Script Headers (Standardized)
```bash
#!/bin/bash
# =============================================================================
# AI Platform Automation - Script X: [Script Name]
# =============================================================================
# Purpose: [Clear purpose description]
# Usage: [Usage examples]
# Dependencies: [Required binaries and files]
# =============================================================================
```

### Configuration File Structure
```
/mnt/${TENANT_ID}/
├── config/
│   ├── platform.conf          # Generated by Script 1
│   ├── docker-compose.yml     # Generated by Script 2
│   ├── caddy/
│   │   └── Caddyfile       # Generated by Script 2
│   ├── litellm/
│   │   └── config.yaml     # Generated by Script 2
│   └── [other service configs]
├── data/
│   ├── postgres/
│   ├── redis/
│   ├── qdrant/
│   └── [service data]
├── logs/
│   ├── platform.log         # Unified platform log
│   ├── postgres.log
│   ├── redis.log
│   └── [service logs]
└── .configured/
    ├── setup-system         # Script 1 completion marker
    ├── deploy-services      # Script 2 completion marker
    └── configure-services   # Script 3 completion marker
```

## 🔧 IMPLEMENTATION SEQUENCE

### Step 1: Commit Current State
```bash
git add -A
git commit -m "Commit current state before refactoring - unified README as north star"
git tag -a "v1.0-refactoring-start" -m "Starting refactoring based on unified README"
```

### Step 2: Refactor Script 0
- Enhance cleanup with complete removal patterns
- Add proper DATA_DIR validation for `/mnt` and `/opt`
- Add systemctl daemon-reload
- Test with various scenarios

### Step 3: Refactor Script 1
- Implement complete interactive input collection
- Add EBS volume detection and mounting
- Add DNS resolution and validation
- Add TLS configuration with all 4 modes
- Add API key collection for all providers
- Add port configuration and conflict checking
- Generate complete platform.conf with all variables

### Step 4: Refactor Script 2
- Implement complete configuration generation
- Add proper dependency ordering
- Add GPU support validation
- Add service health waiting
- Generate complete docker-compose.yml

### Step 5: Refactor Script 3
- Implement complete Mission Control Hub
- Add all service management functions
- Add health dashboard generation
- Add credential management
- Add end-to-end testing

### Step 6: Integration Testing
- Test complete deployment workflow
- Verify all services start correctly
- Test Mission Control capabilities
- Validate all README specifications implemented

### Step 7: Final Commit
```bash
git add -A
git commit -m "Complete refactoring implementation - all scripts aligned with unified README"
git tag -a "v1.0-refactoring-complete" -m "Refactoring complete - platform ready for production"
```

## 🎯 SUCCESS CRITERIA

### Functional Requirements
- [ ] Script 0: Complete cleanup of all platform components
- [ ] Script 1: Complete interactive input collection with validation
- [ ] Script 2: Complete deployment with proper dependency ordering
- [ ] Script 3: Complete Mission Control Hub capabilities
- [ ] All scripts implement README specifications exactly
- [ ] Zero configuration drift between scripts and documentation

### Technical Requirements
- [ ] Non-root execution enforced everywhere
- [ ] All data under `/mnt/${TENANT_ID}/` only
- [ ] Complete EBS volume lifecycle management
- [ ] Complete TLS configuration with all modes
- [ ] Complete service management capabilities
- [ ] Dynamic health dashboard with real URLs
- [ ] End-to-end integration testing

### Quality Requirements
- [ ] Comprehensive error handling and validation
- [ ] Consistent logging across all scripts
- [ ] Clear user feedback and progress indication
- [ ] Proper permission handling
- [ ] Complete documentation inline with code

## 📋 TESTING STRATEGY

### Unit Testing
- Test each script function individually
- Validate input collection and validation
- Test configuration generation
- Test service management operations

### Integration Testing
- Test complete 4-script deployment sequence
- Verify service dependencies and startup order
- Test cross-service integrations
- Validate health dashboard accuracy

### Scenario Testing
- Test with different stack presets
- Test with different TLS modes
- Test with and without EBS volumes
- Test with various service combinations

### Production Readiness Testing
- Test on clean system (fresh install)
- Test on system with existing tenants
- Test upgrade scenarios
- Test error recovery and cleanup

---

**This blueprint serves as the definitive guide for refactoring the AI Platform Automation scripts to align with the unified README.md as the north star platform specification.**
