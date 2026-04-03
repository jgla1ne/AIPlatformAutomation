# AI Platform Automation

> **Simple and reliable over complex and clever.**  
> This is a local tool, not a production SaaS.

A fully automated, containerized AI platform that deploys LLM routing, vector databases, web UIs, automation tools, and monitoring with **zero manual configuration**. Built for local development and private cloud deployment.

---

## 🎯 **PLATFORM OVERVIEW**

### **Core Architecture**
```
Internet
    │
    │ HTTPS (443)
    ▼
┌─────────────────────────────────────────────────────────┐
│                    Reverse Proxy                         │
│         Caddy  ──or──  Nginx Proxy Manager              │
│         (automatic SSL via Let's Encrypt)               │
└────────────────────┬────────────────────────────────────┘
                     │ Internal Docker network
                     │ (${DOCKER_NETWORK})
        ┌────────────┼────────────────────────────┐
        │            │                            │
        ▼            ▼                            ▼
  ┌──────────┐ ┌───────────┐              ┌──────────────┐
  │ LiteLLM  │ │  Web UIs  │              │  Automation  │
  │  Proxy   │ │           │              │              │
  │          │ │ OpenWebUI │              │     N8N      │
  │ (unified │ │ LibreChat │              │   Flowise    │
  │  LLM API)│ │ OpenClaw  │              │    Dify      │
  │          │ │AnythingLLM│              │              │
  └────┬─────┘ └─────┬─────┘              └──────┬───────┘
       │             │                           │
       ▼             ▼                           ▼
  ┌──────────┐ ┌───────────┐              ┌──────────────┐
  │  Ollama  │ │ Authentik │              │  PostgreSQL  │
  │  (local  │ │   (SSO)   │              │    Redis     │
  │  models) │ └───────────┘              │   Qdrant     │
  └──────────┘                            │  Weaviate    │
        │                               │   Chroma     │
        ▼                               └──────┬───────┘
┌─────────────────┐                            │
│ Development     │                            ▼
│ Stack           │                    ┌──────────────────┐
│                 │                    │ Memory Layer     │
│ ┌─────────────┐ │                    │                 │
│ │ Code Server │ │                    │  Mem0           │
│ │ Continue.dev│ │                    │  (Persistence)  │
│ └─────────────┘ │                    └──────────────────┘
└─────────────────┘
```

### **Extended Architecture - All Services**
```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            COMPLETE PLATFORM STACK                             │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐             │
│  │  INFRASTRUCTURE  │  │      MEMORY     │  │      LLM        │             │
│  │                 │  │                 │  │                 │             │
│  │ PostgreSQL       │  │ Mem0            │  │ LiteLLM         │             │
│  │ Redis            │  │                 │  │ Ollama          │             │
│  │                 │  │                 │  │ Bifrost         │             │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘             │
│                                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐             │
│  │    WEB UIs      │  │ VECTOR DATABASES │  │   AUTOMATION    │             │
│  │                 │  │                 │  │                 │             │
│  │ OpenWebUI       │  │ Qdrant          │  │ N8N             │             │
│  │ LibreChat       │  │ Weaviate        │  │ Flowise         │             │
│  │ OpenClaw        │  │ Chroma          │  │ Dify            │             │
│  │ AnythingLLM     │  │                 │  │                 │             │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘             │
│                                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐             │
│  │   IDENTITY      │  │    MONITORING   │  │ WORKFLOW TOOLS  │             │
│  │                 │  │                 │  │                 │             │
│  │ Authentik       │  │ Grafana         │  │ SearXNG         │             │
│  │                 │  │ Prometheus      │  │ Code Server     │             │
│  │                 │  │                 │  │ Continue.dev    │             │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘             │
│                                                                                 │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐             │
│  │ INGESTION & SYNC│  │    ALERTING     │  │      PROXY       │             │
│  │                 │  │                 │  │                 │             │
│  │ Rclone          │  │ Signalbot       │  │ Caddy           │             │
│  │                 │  │                 │  │ Nginx PM        │             │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘             │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### **Memory & Context Persistence**
```
┌─────────────────────────────────────────────────────────┐
│                Memory Layer                           │
│         Mem0 (Per-Tenant Persistence)              │
│  ┌─────────────┐  ┌─────────────────────┐ │
│  │ Context     │  │ Ingestion        │ │
│  │ Storage    │  │ Pipeline         │ │
│  └─────────────┘  └─────────────────────┘ │
└────────────────────┬────────────────────────────┘
                   │
                   ▼
         ┌──────────────────┐
         │ Vector Databases │
         │ Qdrant/Weaviate │
         │    /Chroma      │
         └──────────────────┘
```

---

## 🔄 **SCRIPT ARCHITECTURE FLOW & INTEGRATION**

### **Script 1 → Script 2 → Script 3: Complete Data Flow**

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SCRIPT ARCHITECTURE FLOW                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  SCRIPT 1 (Collector)                                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ INPUT COLLECTION                                                     │   │
│  │ ┌─────────────┐  ┌─────────────────────┐  ┌─────────────────────┐ │   │
│  │ │ System      │  │ Service Selection   │  │ Credential Input   │ │   │
│  │ │ Detection   │  │ (Stack Presets)     │  │ (API Keys, etc.)   │ │   │
│  │ └─────────────┘  └─────────────────────┘  └─────────────────────┘ │   │
│  │           │                    │                    │               │   │
│  │           ▼                    ▼                    ▼               │   │
│  │ ┌─────────────────────────────────────────────────────────────────┐ │   │
│  │ │                platform.conf Generation                         │ │   │
│  │ │  ┌─────────────┐  ┌─────────────────────┐  ┌─────────────────┐ │ │   │
│  │ │  │ Variables   │  │ Service Enablement  │  │ Secret Generation│ │ │   │
│  │ │  │ (95 total)  │  │ Flags (true/false)  │  │ (auto-generated) │ │ │   │
│  │ │  └─────────────┘  └─────────────────────┘  └─────────────────┘ │ │   │
│  │  └─────────────────────────────────────────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                   │                                           │
│                                   ▼                                           │
│  SCRIPT 2 (Deployment Engine)                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ CONFIG GENERATION & CONTAINER DEPLOYMENT                             │   │
│  │ ┌─────────────┐  ┌─────────────────────┐  ┌─────────────────────┐ │   │
│  │ │ Read        │  │ Generate Derived    │  │ Container           │ │   │
│  │ │ platform.conf│  │ Config Files        │  │ Orchestration       │ │   │
│  │ └─────────────┘  └─────────────────────┘  └─────────────────────┘ │   │
│  │           │                    │                    │               │   │
│  │           ▼                    ▼                    ▼               │   │
│  │ ┌─────────────────────────────────────────────────────────────────┐ │   │
│  │ │           OUTPUT FILES FROM SCRIPT 2                             │ │   │
│  │ │  ┌─────────────┐  ┌─────────────────────┐  ┌─────────────────┐ │ │   │
│  │ │  │docker-compose│  │ Caddyfile/nginx.conf │  │ litellm/config  │ │ │   │
│  │ │  │.yml         │  │ (Proxy Configuration) │  │.yaml           │ │ │   │
│  │ │  └─────────────┘  └─────────────────────┘  └─────────────────┘ │ │   │
│  │ │  ┌─────────────┐  ┌─────────────────────┐  ┌─────────────────┐ │ │   │
│  │ │  │bifrost/     │  │ mem0/config.yaml    │  │ ingestion/      │ │ │   │
│  │ │  │config.yaml  │  │ (Memory Layer)       │  │ rclone.conf     │ │ │   │
│  │ │  └─────────────┘  └─────────────────────┘  └─────────────────┘ │ │   │
│  │ │  ┌─────────────────────────────────────────────────────────────┐ │ │   │
│  │ │  │              ALL CONTAINERS RUNNING & HEALTHY              │ │ │   │
│  │ │  └─────────────────────────────────────────────────────────────┘ │ │   │
│  │  └─────────────────────────────────────────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                   │                                           │
│                                   ▼                                           │
│  SCRIPT 3 (Mission Control Hub)                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │ SERVICE MANAGEMENT & CONFIGURATION                                   │   │
│  │ ┌─────────────┐  ┌─────────────────────┐  ┌─────────────────────┐ │   │
│  │ │ Health      │  │ Service             │  │ Credential          │ │   │
│  │ │ Monitoring   │  │ Configuration       │  │ Management          │ │   │
│  │ └─────────────┘  └─────────────────────┘  └─────────────────────┘ │   │
│  │           │                    │                    │               │   │
│  │           ▼                    ▼                    ▼               │   │
│  │ ┌─────────────────────────────────────────────────────────────────┐ │   │
│  │ │              PLATFORM OPERATIONS                                 │ │   │
│  │ │  ┌─────────────┐  ┌─────────────────────┐  ┌─────────────────┐ │ │   │
│  │ │  │ Service     │  │ Key Rotation &      │  │ End-to-End       │ │ │   │
│  │ │  │ Management  │  │ Security Ops        │  │ Testing          │ │ │   │
│  │ │  │ (Add/Remove) │  │ (Credentials)       │  │ (Verification)   │ │ │   │
│  │ │  └─────────────┘  └─────────────────────┘  └─────────────────┘ │ │   │
│  │  └─────────────────────────────────────────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### **Script 1 (Collector) → Script 2 (Deployment Engine) Data Flow**

**What Script 1 Generates for Script 2:**
```bash
# Core Platform Identity (Script 1 → Script 2)
TENANT_ID="datasquiz"                    # → Container naming: datasquiz-*
BASE_DIR="/mnt/datasquiz"                # → Volume mounts: /mnt/datasquiz/*
DOCKER_NETWORK="datasquiz-network"        # → Docker network creation
PUID="1000"                              # → Container user permissions
PGID="1000"                              # → Container group permissions

# Service Enablement Flags (Script 1 → Script 2)
POSTGRES_ENABLED="true"                  # → Include postgres service in compose
REDIS_ENABLED="true"                     # → Include redis service in compose  
LITELLM_ENABLED="true"                   # → Include litellm service in compose
OLLAMA_ENABLED="true"                    # → Include ollama service in compose
# ... (all 25 services)

# Configuration Variables (Script 1 → Script 2)
POSTGRES_PORT="5432"                     # → Container port mapping
LITELLM_PORT="4000"                      # → Container port mapping
OLLAMA_PORT="11434"                      # → Container port mapping
# ... (all port configurations)

# API Keys & Secrets (Script 1 → Script 2)
OPENAI_API_KEY="sk-..."                  # → LiteLLM provider configuration
ANTHROPIC_API_KEY="sk-ant-..."           # → LiteLLM provider configuration
POSTGRES_PASSWORD="generated-secure"     # → PostgreSQL container environment
# ... (all secrets and credentials)
```

**How Script 2 Uses Script 1 Output:**
```bash
# Script 2 reads platform.conf and generates:
generate_compose() {
    # Uses POSTGRES_ENABLED to include/exclude postgres service
    if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
        cat >> "${COMPOSE_FILE}" << EOF
  postgres:
    image: postgres:15-alpine
    container_name: ${TENANT_PREFIX}-postgres
    ports:
      - "${POSTGRES_PORT}:5432"
    environment:
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
EOF
    fi
}

generate_litellm_config() {
    # Uses API keys from Script 1 to configure LiteLLM
    cat > "${BASE_DIR}/config/litellm/config.yaml" << EOF
model_list:
  - model_name: openai-gpt-4
    litellm_params:
      model: gpt-4
      api_key: ${OPENAI_API_KEY}
  - model_name: anthropic-claude
    litellm_params:
      model: claude-3-sonnet-20240229
      api_key: ${ANTHROPIC_API_KEY}
EOF
}
```

### **Script 2 (Deployment Engine) → Script 3 (Mission Control) Data Flow**

**What Script 2 Provides to Script 3:**
```bash
# Running Containers (Script 2 → Script 3)
datasquiz-postgres    (healthy, port 5432)
datasquiz-redis       (healthy, port 6379)
datasquiz-litellm     (healthy, port 4000)
datasquiz-ollama      (healthy, port 11434)
datasquiz-openwebui   (healthy, port 3000)
# ... (all enabled services)

# Generated Configuration Files (Script 2 → Script 3)
/mnt/datasquiz/config/docker-compose.yml     # → Service health checks
/mnt/datasquiz/config/litellm/config.yaml     # → API endpoint verification
/mnt/datasquiz/config/caddy/Caddyfile         # → SSL certificate checks
/mnt/datasquiz/platform.conf                  # → Configuration validation
```

**How Script 3 Uses Script 2 Output:**
```bash
# Script 3 verifies containers are healthy
verify_containers_healthy() {
    # Check postgres container health
    if ! docker ps --format "{{.Names}}" | grep -q "^${TENANT_PREFIX}-postgres$"; then
        fail "PostgreSQL container not running"
    fi
    
    # Verify service endpoints are responding
    if ! curl -sf "http://localhost:${POSTGRES_PORT}/healthz" >/dev/null; then
        fail "PostgreSQL health check failed"
    fi
}

# Script 3 configures services using generated configs
configure_litellm() {
    # Use LiteLLM config generated by Script 2
    local litellm_config="${BASE_DIR}/config/litellm/config.yaml"
    
    # Wait for service to be ready (deployed by Script 2)
    if ! wait_for_service "LiteLLM" "http://localhost:${LITELLM_PORT}/health" "${TENANT_PREFIX}-litellm"; then
        fail "LiteLLM failed to start"
    fi
    
    # Configure provider models using API keys from platform.conf
    log "Configuring LiteLLM providers..."
    # ... configuration logic

# Step 2: Service Deployment
./scripts/2-deploy-services.sh      # Deployment Engine - generates configs, deploys containers

# Step 3: Service Configuration & Management
./scripts/3-configure-services.sh   # Mission Control Hub - service management, health, credentials
generate_proxy_config()      # Caddyfile or nginx.conf generation
generate_litellm_config()    # LLM provider routing configuration
generate_bifrost_config()    # Optional LLM gateway config
generate_mem0_config()       # Memory persistence configuration
generate_ingestion_config()   # Rclone + pipeline configuration

# Utility functions
build_dependency_string()     # Service dependency resolution
validate_configuration()      # Pre-deployment validation
wait_for_healthy()          # Container health checking
rollback_on_failure()       # Deployment rollback
```

**Deployment Flow:**
1. **Configuration Validation** - Verify platform.conf integrity
2. **Dependency Resolution** - Build service startup order
3. **Config Generation** - Create all derived configs from platform.conf
4. **Container Orchestration** - Start services in dependency order
5. **Health Verification** - Wait for all services to be healthy
6. **Status Reporting** - Provide deployment summary

### **Script 3 — `3-configure-services.sh` (Mission Control Hub)**

**Job:** Service management, health monitoring, credentials, key rotation, and post-deployment configuration.

```
Input  → platform.conf + running containers
Options → --verify-only     Only verify deployment, don't configure
         --health-check    Show detailed health status
         --show-credentials Print all service credentials
         --rotate-keys [service] Regenerate secrets for one service
         --dry-run         Show what would be done
Output → Configured services with:
         - Service health monitoring and status
         - Credential management and display
         - Key rotation and security operations
         - Service restart and recovery
         - End-to-end platform verification
```

**Mission Control Functions:**
```bash
# Service management and monitoring
verify_containers_healthy()    # Comprehensive health checking
show_health_status()           # Detailed health status display
framework_validate()           # Framework validation and fixes

# Credential and security management
show_credentials()             # Display all service credentials
rotate_keys()                 # Regenerate secrets for specific service
generate_secret()              # Secure random secret generation

# Service configuration
configure_ollama()            # Model pulling and setup
configure_litellm()          # LLM provider setup
configure_openwebui()        # User accounts and themes
configure_librechat()        # Authentication setup
configure_openclaw()         # Terminal configuration
configure_qdrant()           # Vector database setup
configure_n8n()             # Workflows and credentials
configure_flowise()          # Chatbot setup
configure_dify()             # AI platform setup
configure_authentik()        # SSO and user management
configure_signalbot()        # Notification setup
configure_bifrost()         # LLM gateway configuration

# Platform operations
restart_service()            # Restart specific service
add_service()               # Add new service to platform
remove_service()            # Remove service from platform
disable_service()           # Temporarily disable service
enable_service()            # Re-enable disabled service

# Verification and testing
verify_service_health()      # Generic service health verification
verify_database_connectivity() # Database connection testing
verify_api_endpoints()       # API endpoint availability
verify_ssl_certificates()    # SSL certificate validation
verify_integrations()        # Cross-service integration testing

# End-to-end testing
test_llm_pipeline()         # LiteLLM → Ollama → OpenAI flow
test_rag_pipeline()          # Document ingestion → vector DB → query
test_authentication()         # SSO → web UI login flow
test_monitoring()           # Metrics collection → alerting
test_development_stack()     # Code Server → Continue.dev → LLM
```

### **🔧 SHARED UTILITY FUNCTIONS (CORRECTED ARCHITECTURE)**

**Mission Control Hub (Script 3) provides all cross-script utilities - NO separate shared file!**

```bash
# =============================================================================
# MISSION CONTROL UTILITY FUNCTIONS (Script 3 - Single Source of Truth)
# =============================================================================
# All utility functions reside in Script 3 - NO external shared files
# Scripts 1 & 2 call Script 3 functions for operations
# =============================================================================

# System Operations (Scripts 1, 2, 3 source these from Script 3)
check_dependencies()           # Verify required binaries (docker, curl, jq, etc.)
check_docker_group()         # Validate user in docker group
check_non_root()             # Enforce non-root execution (except Script 0)
detect_system_resources()     # RAM, disk, GPU detection
validate_port_conflicts()    # Check port availability before deployment
resolve_hostname()            # DNS resolution validation
check_ssl()                 # SSL certificate verification

# Docker Operations (Scripts 2, 3 source from Script 3)
docker_health_check()         # Container health verification
wait_for_service()           # Service readiness waiting
docker_pull()                # Image pulling with timeout
docker_logs()                 # Log collection and filtering

# Configuration Management (Scripts 1, 2, 3 source from Script 3)
load_platform_conf()         # Safe platform.conf loading
validate_configuration()      # Pre-deployment validation
generate_secret()            # Secure random secret generation
backup_configuration()       # Config backup before changes

# Directory Operations (Scripts 1, 2 source from Script 3)
create_directories()         # Platform directory structure creation
setup_permissions()          # File/directory permissions
mount_ebs_volume()         # EBS volume detection and mounting
update_fstab()               # Persistent mount configuration

# Network Operations (Scripts 1, 2, 3 source from Script 3)
validate_domain()            # Domain name validation
test_connectivity()           # Network connectivity testing
wait_for_port()             # Port availability waiting
configure_dns()              # DNS resolution setup

# Service Management (Mission Control - Script 3 only)
restart_service()            # Restart specific service
add_service()               # Add new service to platform
remove_service()            # Remove service from platform
disable_service()           # Temporarily disable service
enable_service()            # Re-enable disabled service

# Health Verification (Scripts 2, 3 source from Script 3)
verify_service_health()      # Generic service health verification
verify_database_connectivity() # Database connection testing
verify_api_endpoints()       # API endpoint availability
verify_integrations()        # Cross-service integration testing
```

**Configuration Variables (Generated by Script 1, used by all scripts):**
```bash
# Platform Paths (ALL under /mnt/${TENANT_ID}/ - NO EXCEPTIONS)
BASE_DIR="/mnt/${TENANT_ID}"
CONFIG_DIR="${BASE_DIR}/config"
DATA_DIR="${BASE_DIR}/data"
LOG_DIR="${BASE_DIR}/logs"
COMPOSE_FILE="${CONFIG_DIR}/docker-compose.yml"
CONFIGURED_DIR="${BASE_DIR}/.configured"

# Docker Configuration
DOCKER_NETWORK="${TENANT_ID}-network"
TENANT_PREFIX="${TENANT_ID}"
DOCKER_USER_ID="${PLATFORM_PREFIX}${TENANT_ID}"
DOCKER_GROUP_ID="${PLATFORM_PREFIX}${TENANT_ID}"

# Service Container Names (Dynamic based on TENANT_ID)
POSTGRES_CONTAINER="${TENANT_PREFIX}-postgres"
REDIS_CONTAINER="${TENANT_PREFIX}-redis"
OLLAMA_CONTAINER="${TENANT_PREFIX}-ollama"
LITELLM_CONTAINER="${TENANT_PREFIX}-litellm"
OPENWEBUI_CONTAINER="${TENANT_PREFIX}-openwebui"
QDRANT_CONTAINER="${TENANT_PREFIX}-qdrant"
N8N_CONTAINER="${TENANT_PREFIX}-n8n"
CODESERVER_CONTAINER="${TENANT_PREFIX}-codeserver"

# Service Ports (Dynamic from platform.conf - OVERRIDABLE PER TENANT)
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
REDIS_PORT="${REDIS_PORT:-6379}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
LITELLM_PORT="${LITELLM_PORT:-4000}"
OPENWEBUI_PORT="${OPENWEBUI_PORT:-3000}"
QDRANT_PORT="${QDRANT_PORT:-6333}"
N8N_PORT="${N8N_PORT:-5678}"
CODESERVER_PORT="${CODESERVER_PORT:-8443}"
```

**Logging Strategy (ALL under /mnt/${TENANT_ID}/logs/ - NO /tmp USAGE):**
```bash
# Tenant-specific logging - NOTHING outside /mnt/${TENANT_ID}/
LOG_DIR="${BASE_DIR}/logs"
mkdir -p "${LOG_DIR}"

# Per-service log files (DYNAMIC paths)
POSTGRES_LOG="${LOG_DIR}/postgres.log"
REDIS_LOG="${LOG_DIR}/redis.log"
OLLAMA_LOG="${LOG_DIR}/ollama.log"
LITELLM_LOG="${LOG_DIR}/litellm.log"
OPENWEBUI_LOG="${LOG_DIR}/openwebui.log"
QDRANT_LOG="${LOG_DIR}/qdrant.log"
N8N_LOG="${LOG_DIR}/n8n.log"
CODESERVER_LOG="${LOG_DIR}/codeserver.log"

# Logging function used by all scripts (writes to tenant directory ONLY)
log() {
    local msg="[$(date +%H:%M:%S)] $*"
    echo "$msg"
    echo "$msg" >> "${LOG_DIR}/platform.log" 2>/dev/null || true
}
```

### **📁 EBS VOLUME DETECTION & MOUNTING**

**Script 1 handles complete EBS volume lifecycle:**
```bash
# Step 1: EBS Detection (Script 1)
detect_ebs_volumes() {
    echo "Available block devices:"
    lsblk -f -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "nvme|sd|vd" | while read -r name size type mount; do
        if [[ -z "$mount" ]] && [[ "$type" == "disk" ]]; then
            echo "  [$count] /dev/$name ${size} (unformatted — available)"
            count=$((count + 1))
        fi
    done
    
    echo "  [$count] Use existing /mnt/${TENANT_ID}/ on OS disk (no separate volume)"
    
    read -p "Select EBS volume [1-$count, or 0 for OS disk]: " choice
    
    if [[ "$choice" =~ ^[1-9]$ ]]; then
        EBS_DEVICE=$(lsblk -f -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "nvme|sd|vd" | sed -n "${choice}p" | awk '{print "/dev/"$1}')
        echo "Selected EBS device: $EBS_DEVICE"
    fi
}

# Step 2: Volume Formatting (Script 1)
format_ebs_volume() {
    if [[ -n "$EBS_DEVICE" ]] && [[ ! -b "$EBS_DEVICE" ]]; then
        echo "Formatting EBS volume: $EBS_DEVICE"
        read -p "CONFIRM: Format $EBS_DEVICE as ext4? [yes/N]: " confirm
        
        if [[ "$confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
            mkfs.ext4 -F "$EBS_DEVICE" || fail "Failed to format $EBS_DEVICE"
            echo "EBS volume formatted successfully"
        else
            fail "EBS volume formatting cancelled"
        fi
    fi
}

# Step 3: Mount Point Creation (Script 1)
create_mount_point() {
    local mount_point="/mnt/${TENANT_ID}"
    echo "Creating mount point: $mount_point"
    mkdir -p "$mount_point"
    chmod 755 "$mount_point"
}

# Step 4: UUID Detection (Script 1)
detect_volume_uuid() {
    if [[ -n "$EBS_DEVICE" ]]; then
        VOLUME_UUID=$(blkid -s -o UUID "$EBS_DEVICE") || fail "Failed to detect UUID for $EBS_DEVICE"
        echo "EBS volume UUID: $VOLUME_UUID"
    fi
}

# Step 5: fstab Update (Script 1)
update_fstab() {
    if [[ -n "$VOLUME_UUID" ]]; then
        local fstab_entry="UUID=${VOLUME_UUID}  /mnt/${TENANT_ID}  ext4  defaults,nofail  0  0"
        
        # Backup original fstab
        cp /etc/fstab /etc/fstab.backup
        
        # Add new entry (avoid duplicates)
        if ! grep -q "UUID=${VOLUME_UUID}" /etc/fstab; then
            echo "$fstab_entry" >> /etc/fstab
            echo "Added to fstab: $fstab_entry"
        else
            echo "EBS volume already in fstab"
        fi
        
        # Reload systemd daemons
        systemctl daemon-reload || warn "Failed to reload systemd daemons"
    fi
}

# Step 6: Mount Volume (Script 1)
mount_ebs_volume() {
    if [[ -n "$VOLUME_UUID" ]]; then
        echo "Mounting EBS volume..."
        mount "/mnt/${TENANT_ID}" 2>/dev/null || {
            echo "EBS volume already mounted or mount failed"
            echo "Checking current mount status..."
            mount | grep "/mnt/${TENANT_ID}"
        }
        
        if mount | grep -q "/mnt/${TENANT_ID}"; then
            echo "EBS volume mounted successfully"
            echo "Mount point: /mnt/${TENANT_ID}"
            echo "Device: $EBS_DEVICE (UUID: $VOLUME_UUID)"
        else
            fail "Failed to mount EBS volume"
        fi
    fi
}
```

### **🌐 DNS RESOLUTION & VALIDATION**

**Complete DNS workflow before TLS configuration:**
```bash
# Step 1: Domain Validation (Script 1)
validate_domain() {
    local domain="$1"
    
    # Basic domain format validation
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        fail "Invalid domain format: $domain"
    fi
    
    echo "Domain validation passed: $domain"
}

# Step 2: DNS Resolution Test (Script 1)
test_dns_resolution() {
    local domain="$1"
    local expected_ip="$2"
    
    echo "Testing DNS resolution for $domain..."
    
    # Test A record resolution
    local resolved_ip
    if ! resolved_ip=$(dig +short "$domain" 2>/dev/null); then
        fail "DNS resolution failed for $domain"
    fi
    
    echo "DNS resolution: $domain → $resolved_ip"
    
    # Compare with expected IP (optional)
    if [[ -n "$expected_ip" ]]; then
        if [[ "$resolved_ip" != "$expected_ip" ]]; then
            warning "DNS IP mismatch: $domain resolves to $resolved_ip, expected $expected_ip"
            echo "This may cause TLS certificate issues"
        else
            echo "DNS resolution matches expected IP: $resolved_ip"
        fi
    fi
}

# Step 3: Public IP Detection (Script 1)
detect_public_ip() {
    local public_ip
    public_ip=$(curl -s https://checkip.amazonaws.com 2>/dev/null) || \
               public_ip=$(curl -s https://ipinfo.io/ip 2>/dev/null) || \
               public_ip=$(curl -s https://api.ipify.org 2>/dev/null) || \
               fail "Failed to detect public IP"
    
    echo "Detected public IP: $public_ip"
    echo "$public_ip"
}

# Step 4: Complete DNS Validation (Script 1)
validate_dns_setup() {
    local domain="$1"
    
    echo "=== DNS VALIDATION FOR $domain ==="
    
    # Detect public IP
    local public_ip
    public_ip=$(detect_public_ip)
    
    # Validate domain format
    validate_domain "$domain"
    
    # Test DNS resolution
    test_dns_resolution "$domain" "$public_ip"
    
    # Test reverse DNS (optional)
    echo "Testing reverse DNS lookup..."
    local reverse_dns
    if reverse_dns=$(dig -x "$public_ip" +short 2>/dev/null); then
        echo "Reverse DNS: $public_ip → $reverse_dns"
        if [[ "$reverse_dns" != "$domain" ]]; then
            warning "Reverse DNS mismatch: $public_ip → $reverse_dns (expected $domain)"
        fi
    else
        echo "Reverse DNS lookup failed for $public_ip"
    fi
    
    echo "=== DNS VALIDATION COMPLETE ==="
}
```

### **🔧 SCRIPT 1 INTERACTIVE INPUT COLLECTION**

**Complete CLI input collection with validation and options:**

```bash
# =============================================================================
# SCRIPT 1: COMPLETE INTERACTIVE INPUT COLLECTION
# =============================================================================
echo "=== AI PLATFORM SETUP - INTERACTIVE CONFIGURATION ==="

# =============================================================================
# IDENTITY & TENANT CONFIGURATION
# =============================================================================
echo "=== IDENTITY CONFIGURATION ==="

# Platform prefix selection
echo "Select platform prefix:"
echo "  1) ai- (default for AI Platform)"
echo "  2) prod- (production environment)"
echo "  3) staging- (staging environment)"
echo "  4) dev- (development environment)"
echo "  5) Custom prefix"

read -p "Platform prefix [1-5]: " prefix_choice

case "${prefix_choice}" in
    1) PLATFORM_PREFIX="ai-" ;;
    2) PLATFORM_PREFIX="prod-" ;;
    3) PLATFORM_PREFIX="staging-" ;;
    4) PLATFORM_PREFIX="dev-" ;;
    5) 
        read -p "Custom prefix [end with -]: " PLATFORM_PREFIX
        if [[ ! "$PLATFORM_PREFIX" =~ -$ ]]; then
            fail "Custom prefix must end with '-'"
        fi
        ;;
    *) 
        PLATFORM_PREFIX="ai-"
        echo "Default selected: ai-"
        ;;
esac

# Tenant ID
read -p "Tenant ID [required, alphanumeric]: " TENANT_ID
if [[ ! "$TENANT_ID" =~ ^[a-zA-Z0-9]+$ ]]; then
    fail "Tenant ID must be alphanumeric only"
fi
: "${TENANT_ID:?TENANT_ID is required}"

# Domain configuration
read -p "Base domain [required, e.g., example.com]: " DOMAIN
if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
    fail "Invalid domain format: $DOMAIN"
fi
: "${DOMAIN:?DOMAIN is required}"

echo "Identity Configuration:"
echo "  Platform Prefix: $PLATFORM_PREFIX"
echo "  Tenant ID: $TENANT_ID"
echo "  Full Tenant Name: ${PLATFORM_PREFIX}${TENANT_ID}"
echo "  Base Domain: $DOMAIN"

# =============================================================================
# STORAGE CONFIGURATION
# =============================================================================
echo ""
echo "=== STORAGE CONFIGURATION ==="

# EBS volume selection
echo "Select storage type:"
echo "  1) Use EBS volume (recommended for production)"
echo "  2) Use OS disk (not recommended for production)"

read -p "Storage type [1-2]: " storage_choice

case "${storage_choice}" in
    1)
        USE_EBS="true"
        echo "EBS volume selected - running detection..."
        detect_ebs_volumes
        create_mount_point
        format_ebs_volume
        detect_volume_uuid
        update_fstab
        mount_ebs_volume
        ;;
    2)
        USE_EBS="false"
        echo "OS disk selected - creating /mnt/${TENANT_ID}..."
        mkdir -p "/mnt/${TENANT_ID}"
        chmod 755 "/mnt/${TENANT_ID}"
        ;;
    *)
        USE_EBS="true"
        echo "Default selected: EBS volume"
        detect_ebs_volumes
        create_mount_point
        format_ebs_volume
        detect_volume_uuid
        update_fstab
        mount_ebs_volume
        ;;
esac

# =============================================================================
# STACK PRESET SELECTION
# =============================================================================
echo ""
echo "=== STACK PRESET SELECTION ==="

echo "Select stack preset:"
echo "  1) minimal - PostgreSQL, Redis, LiteLLM, Ollama, OpenWebUI, Qdrant, Caddy"
echo "  2) dev - minimal + Code Server, Continue.dev, n8n, Flowise, Mem0"
echo "  3) standard - dev + LibreChat, Dify, Grafana, Prometheus, Authentik"
echo "  4) full - All 25 services enabled"
echo "  5) custom - All services disabled, enable individually"

read -p "Stack preset [1-5]: " preset_choice

case "${preset_choice}" in
    1) 
        STACK_PRESET="minimal"
        apply_preset_defaults "minimal"
        ;;
    2) 
        STACK_PRESET="dev"
        apply_preset_defaults "dev"
        ;;
    3) 
        STACK_PRESET="standard"
        apply_preset_defaults "standard"
        ;;
    4) 
        STACK_PRESET="full"
        apply_preset_defaults "full"
        ;;
    5) 
        STACK_PRESET="custom"
        apply_preset_defaults "custom"
        ;;
    *) 
        STACK_PRESET="minimal"
        echo "Default selected: minimal"
        apply_preset_defaults "minimal"
        ;;
esac

echo "Stack preset: $STACK_PRESET"

# =============================================================================
# LLM GATEWAY CONFIGURATION
# =============================================================================
echo ""
echo "=== LLM GATEWAY CONFIGURATION ==="

echo "Select LLM gateway:"
echo "  1) LiteLLM (multi-provider router)"
echo "  2) Bifrost (lightweight Go router)"
echo "  3) Direct Ollama (single LLM only)"

read -p "LLM gateway [1-3]: " gateway_choice

case "${gateway_choice}" in
    1)
        LLM_PROXY_TYPE="litellm"
        echo "LiteLLM selected - configuring multi-provider routing..."
        configure_litellm_providers
        ;;
    2)
        LLM_PROXY_TYPE="bifrost"
        echo "Bifrost selected - lightweight Go router..."
        ;;
    3)
        LLM_PROXY_TYPE="direct"
        echo "Direct Ollama selected - single LLM mode..."
        ;;
    *)
        LLM_PROXY_TYPE="litellm"
        echo "Default selected: LiteLLM"
        configure_litellm_providers
        ;;
esac

# =============================================================================
# VECTOR DATABASE CONFIGURATION
# =============================================================================
echo ""
echo "=== VECTOR DATABASE CONFIGURATION ==="

echo "Select vector database:"
echo "  1) Qdrant (default, high performance)"
echo "  2) Weaviate (GraphQL API)"
echo "  3) ChromaDB (Python-native)"
echo "  4) Milvus (enterprise scale)"

read -p "Vector database [1-4]: " vector_choice

case "${vector_choice}" in
    1) 
        VECTOR_DB_TYPE="qdrant"
        echo "Qdrant selected - high performance vector database"
        ;;
    2) 
        VECTOR_DB_TYPE="weaviate"
        echo "Weaviate selected - GraphQL API vector database"
        ;;
    3) 
        VECTOR_DB_TYPE="chroma"
        echo "ChromaDB selected - Python-native vector database"
        ;;
    4) 
        VECTOR_DB_TYPE="milvus"
        echo "Milvus selected - enterprise scale vector database"
        ;;
    *) 
        VECTOR_DB_TYPE="qdrant"
        echo "Default selected: Qdrant"
        ;;
esac

# =============================================================================
# MEMORY LAYER CONFIGURATION
# =============================================================================
echo ""
echo "=== MEMORY LAYER CONFIGURATION ==="

echo "Enable Mem0 for persistent conversation memory?"
echo "  1) Enable Mem0 (recommended for production)"
echo "  2) Disable Mem0 (simpler setup)"

read -p "Memory layer [1-2]: " memory_choice

case "${memory_choice}" in
    1)
        MEM0_ENABLED="true"
        echo "Mem0 enabled - persistent conversation memory"
        ;;
    2)
        MEM0_ENABLED="false"
        echo "Mem0 disabled - no persistent memory"
        ;;
    *)
        MEM0_ENABLED="true"
        echo "Default selected: Mem0 enabled"
        ;;
esac

# =============================================================================
# BACKUP CONFIGURATION
# =============================================================================
echo ""
echo "=== BACKUP CONFIGURATION ==="

echo "Enable automated backups?"
echo "  1) Enable backups (recommended for production)"
echo "  2) Disable backups (simpler setup)"

read -p "Backup configuration [1-2]: " backup_choice

case "${backup_choice}" in
    1)
        ENABLE_BACKUP="true"
        echo "Backups enabled - configuring automated backup schedule..."
        configure_backup_settings
        ;;
    2)
        ENABLE_BACKUP="false"
        echo "Backups disabled - no automated backups"
        ;;
    *)
        ENABLE_BACKUP="true"
        echo "Default selected: backups enabled"
        configure_backup_settings
        ;;
esac

# =============================================================================
# INGESTION CONFIGURATION
# =============================================================================
echo ""
echo "=== INGESTION CONFIGURATION ==="

echo "Enable data ingestion pipeline?"
echo "  1) Enable ingestion (Rclone + automated processing)"
echo "  2) Disable ingestion (manual data loading only)"

read -p "Ingestion configuration [1-2]: " ingestion_choice

case "${ingestion_choice}" in
    1)
        ENABLE_INGESTION="true"
        echo "Ingestion enabled - configuring Rclone and pipeline..."
        configure_ingestion_settings
        ;;
    2)
        ENABLE_INGESTION="false"
        echo "Ingestion disabled - manual data loading only"
        ;;
    *)
        ENABLE_INGESTION="true"
        echo "Default selected: ingestion enabled"
        configure_ingestion_settings
        ;;
esac

# =============================================================================
# TLS CONFIGURATION (previously added)
# =============================================================================
echo ""
echo "=== TLS CERTIFICATE CONFIGURATION ==="
# ... (TLS configuration from previous section)

# =============================================================================
# SERVICE ENABLEMENT (CUSTOM MODE)
# =============================================================================
if [[ "$STACK_PRESET" == "custom" ]]; then
    echo ""
    echo "=== CUSTOM SERVICE ENABLEMENT ==="
    
    # Infrastructure services
    echo "Infrastructure services:"
    read -p "Enable PostgreSQL? [Y/n]: " enable_postgres
    POSTGRES_ENABLED="${enable_postgres:-Y}"
    
    read -p "Enable Redis? [Y/n]: " enable_redis
    REDIS_ENABLED="${enable_redis:-Y}"
    
    # LLM services
    echo ""
    echo "LLM services:"
    read -p "Enable LiteLLM? [Y/n]: " enable_litellm
    LITELLM_ENABLED="${enable_litellm:-Y}"
    
    read -p "Enable Ollama? [Y/n]: " enable_ollama
    OLLAMA_ENABLED="${enable_ollama:-Y}"
    
    # Web UIs
    echo ""
    echo "Web UIs:"
    read -p "Enable Open WebUI? [Y/n]: " enable_openwebui
    OPENWEBUI_ENABLED="${enable_openwebui:-Y}"
    
    read -p "Enable LibreChat? [y/N]: " enable_librechat
    LIBRECHAT_ENABLED="${enable_librechat:-N}"
    
    # Continue with all other services...
    echo "Configuring remaining services..."
    # ... (service enablement logic)
fi

# =============================================================================
# API KEY COLLECTION
# =============================================================================
echo ""
echo "=== API KEY COLLECTION ==="

echo "Configure LLM provider API keys (leave empty to disable):"

# OpenAI
read -p "OpenAI API key [optional]: " OPENAI_API_KEY
if [[ -n "$OPENAI_API_KEY" ]]; then
    echo "OpenAI provider enabled"
    OPENAI_PROVIDER_ENABLED="true"
else
    echo "OpenAI provider disabled"
    OPENAI_PROVIDER_ENABLED="false"
fi

# Anthropic
read -p "Anthropic API key [optional]: " ANTHROPIC_API_KEY
if [[ -n "$ANTHROPIC_API_KEY" ]]; then
    echo "Anthropic provider enabled"
    ANTHROPIC_PROVIDER_ENABLED="true"
else
    echo "Anthropic provider disabled"
    ANTHROPIC_PROVIDER_ENABLED="false"
fi

# Google
read -p "Google API key [optional]: " GOOGLE_API_KEY
if [[ -n "$GOOGLE_API_KEY" ]]; then
    echo "Google provider enabled"
    GOOGLE_PROVIDER_ENABLED="true"
else
    echo "Google provider disabled"
    GOOGLE_PROVIDER_ENABLED="false"
fi

# Groq
read -p "Groq API key [optional]: " GROQ_API_KEY
if [[ -n "$GROQ_API_KEY" ]]; then
    echo "Groq provider enabled"
    GROQ_PROVIDER_ENABLED="true"
else
    echo "Groq provider disabled"
    GROQ_PROVIDER_ENABLED="false"
fi

# OpenRouter
read -p "OpenRouter API key [optional]: " OPENROUTER_API_KEY
if [[ -n "$OPENROUTER_API_KEY" ]]; then
    echo "OpenRouter provider enabled"
    OPENROUTER_PROVIDER_ENABLED="true"
else
    echo "OpenRouter provider disabled"
    OPENROUTER_PROVIDER_ENABLED="false"
fi

# =============================================================================
# PORT CONFIGURATION
# =============================================================================
echo ""
echo "=== PORT CONFIGURATION ==="

echo "Configure service ports (press Enter for defaults):"

read -p "PostgreSQL port [5432]: " POSTGRES_PORT
POSTGRES_PORT="${POSTGRES_PORT:-5432}"

read -p "Redis port [6379]: " REDIS_PORT
REDIS_PORT="${REDIS_PORT:-6379}"

read -p "LiteLLM port [4000]: " LITELLM_PORT
LITELLM_PORT="${LITELLM_PORT:-4000}"

read -p "Ollama port [11434]: " OLLAMA_PORT
OLLAMA_PORT="${OLLAMA_PORT:-11434}"

read -p "OpenWebUI port [3000]: " OPENWEBUI_PORT
OPENWEBUI_PORT="${OPENWEBUI_PORT:-3000}"

# Continue with all other ports...
echo "Configuring remaining service ports..."

# =============================================================================
# FINAL VALIDATION & SUMMARY
# =============================================================================
echo ""
echo "=== CONFIGURATION SUMMARY ==="

echo "Identity:"
echo "  Platform Prefix: $PLATFORM_PREFIX"
echo "  Tenant ID: $TENANT_ID"
echo "  Base Domain: $DOMAIN"
echo "  Full Tenant Name: ${PLATFORM_PREFIX}${TENANT_ID}"

echo ""
echo "Configuration:"
echo "  Stack Preset: $STACK_PRESET"
echo "  LLM Gateway: $LLM_PROXY_TYPE"
echo "  Vector DB: $VECTOR_DB_TYPE"
echo "  Memory Layer: $MEM0_ENABLED"
echo "  TLS Mode: $TLS_MODE"
echo "  Backups: $ENABLE_BACKUP"
echo "  Ingestion: $ENABLE_INGESTION"

echo ""
echo "Enabled Providers:"
[[ "$OPENAI_PROVIDER_ENABLED" == "true" ]] && echo "  • OpenAI"
[[ "$ANTHROPIC_PROVIDER_ENABLED" == "true" ]] && echo "  • Anthropic"
[[ "$GOOGLE_PROVIDER_ENABLED" == "true" ]] && echo "  • Google"
[[ "$GROQ_PROVIDER_ENABLED" == "true" ]] && echo "  • Groq"
[[ "$OPENROUTER_PROVIDER_ENABLED" == "true" ]] && echo "  • OpenRouter"

echo ""
echo "Key Ports:"
echo "  PostgreSQL: $POSTGRES_PORT"
echo "  Redis: $REDIS_PORT"
echo "  LiteLLM: $LITELLM_PORT"
echo "  Ollama: $OLLAMA_PORT"
echo "  OpenWebUI: $OPENWEBUI_PORT"

echo ""
read -p "Confirm configuration and proceed? [yes/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Configuration cancelled"
    exit 1
fi

echo "=== INTERACTIVE CONFIGURATION COMPLETE ==="
```

**Script 1 Input Collection Summary:**

| Section | Input Method | Validation | Default | Purpose |
|---------|---------------|-------------|----------|---------|
| **Identity** | Interactive prompts | Format validation | ai- | Platform prefix, tenant ID, domain |
| **Storage** | Menu selection | Volume detection | EBS volume | EBS vs OS disk storage |
| **Stack Preset** | Menu selection | Preset application | minimal | Service bundle selection |
| **LLM Gateway** | Menu selection | Provider configuration | LiteLLM | LLM routing strategy |
| **Vector DB** | Menu selection | Service compatibility | Qdrant | RAG backend selection |
| **Memory Layer** | Menu selection | Service integration | Mem0 enabled | Conversation persistence |
| **TLS** | Menu selection | Certificate validation | Let's Encrypt | SSL/TLS configuration |
| **API Keys** | Secure prompts | Key format validation | Empty (disabled) | LLM provider access |
| **Ports** | Interactive prompts | Conflict checking | Service defaults | Port customization |
| **Backup** | Menu selection | Storage validation | Enabled | Data protection |
| **Ingestion** | Menu selection | Service integration | Enabled | Data pipeline |

### **🔒 TLS CERTIFICATE MANAGEMENT**

**Script 1 provides complete TLS configuration options:**

```bash
# =============================================================================
# TLS MODE SELECTION (Script 1 - Interactive Input Collection)
# =============================================================================
echo "=== TLS CERTIFICATE CONFIGURATION ==="
echo "Select TLS mode for ${DOMAIN}:"
echo "  1) Let's Encrypt (automatic - requires public DNS)"
echo "  2) Manual Certificate (provide cert/key files)"
echo "  3) Self-Signed Certificate (development/testing)"
echo "  4) No TLS (HTTP only - not recommended for production)"

read -p "TLS mode [1-4]: " tls_mode

case "${tls_mode}" in
    1)
        TLS_MODE="letsencrypt"
        echo "Let's Encrypt selected - requires:"
        echo "  • Public domain ${DOMAIN}"
        echo "  • DNS pointing to this server"
        echo "  • Email for certificate registration"
        
        read -p "Email for Let's Encrypt: " LETSENCRYPT_EMAIL
        : "${LETSENCRYPT_EMAIL:?Email required for Let's Encrypt}"
        
        echo "Let's Encrypt configuration:"
        echo "  Domain: ${DOMAIN}"
        echo "  Email: ${LETSENCRYPT_EMAIL}"
        echo "  Auto-renewal: enabled"
        ;;
    2)
        TLS_MODE="manual"
        echo "Manual certificate selected - requires:"
        echo "  • Certificate file (.crt or .pem)"
        echo "  • Private key file (.key)"
        
        read -p "Certificate file path: " MANUAL_CERT_FILE
        read -p "Private key file path: " MANUAL_KEY_FILE
        
        # Validate files exist
        if [[ ! -f "$MANUAL_CERT_FILE" ]]; then
            fail "Certificate file not found: $MANUAL_CERT_FILE"
        fi
        
        if [[ ! -f "$MANUAL_KEY_FILE" ]]; then
            fail "Private key file not found: $MANUAL_KEY_FILE"
        fi
        
        echo "Manual TLS configuration:"
        echo "  Certificate: $MANUAL_CERT_FILE"
        echo "  Private Key: $MANUAL_KEY_FILE"
        echo "  Domain: ${DOMAIN}"
        ;;
    3)
        TLS_MODE="selfsigned"
        echo "Self-signed certificate selected - generates:"
        echo "  • 365-day certificate"
        echo "  • RSA 2048-bit key"
        echo "  • Browser warnings (expected)"
        
        read -p "Certificate country [US]: " CERT_COUNTRY
        read -p "Certificate state [State]: " CERT_STATE
        read -p "Certificate city [City]: " CERT_CITY
        read -p "Certificate organization [AI Platform]: " CERT_ORG
        
        CERT_COUNTRY="${CERT_COUNTRY:-US}"
        CERT_STATE="${CERT_STATE:-State}"
        CERT_CITY="${CERT_CITY:-City}"
        CERT_ORG="${CERT_ORG:-AI Platform}"
        
        echo "Self-signed TLS configuration:"
        echo "  Domain: ${DOMAIN}"
        echo "  Country: $CERT_COUNTRY"
        echo "  State: $CERT_STATE"
        echo "  City: $CERT_CITY"
        echo "  Organization: $CERT_ORG"
        echo "  Validity: 365 days"
        ;;
    4)
        TLS_MODE="none"
        echo "No TLS selected - WARNING:"
        echo "  • HTTP only (port 80)"
        echo "  • No encryption"
        echo "  • Not recommended for production"
        echo "  • Browsers may show warnings"
        
        read -p "Continue without TLS? [yes/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
            echo "TLS configuration cancelled"
            return 1
        fi
        
        echo "No TLS configuration:"
        echo "  Protocol: HTTP only"
        echo "  Port: 80"
        echo "  Domain: ${DOMAIN}"
        ;;
    *)
        fail "Invalid TLS mode: $tls_mode (must be 1-4)"
        ;;
esac

# Set TLS variables for platform.conf
TLS_MODE="${TLS_MODE}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"
MANUAL_CERT_FILE="${MANUAL_CERT_FILE:-}"
MANUAL_KEY_FILE="${MANUAL_KEY_FILE:-}"
CERT_COUNTRY="${CERT_COUNTRY:-US}"
CERT_STATE="${CERT_STATE:-State}"
CERT_CITY="${CERT_CITY:-City}"
CERT_ORG="${CERT_ORG:-AI Platform}"

echo "=== TLS CONFIGURATION COMPLETE ==="
```

**Script 2 implements the selected TLS configuration:**

```bash
# Let's Encrypt Automatic (TLS_MODE=letsencrypt)
configure_letsencrypt() {
    local domain="$1"
    local email="$2"
    
    echo "Configuring Let's Encrypt for $domain..."
    
    # Generate Caddyfile with automatic TLS
    cat > "${CONFIG_DIR}/caddy/Caddyfile" << EOF
{
    email ${email}
    auto_https {
        protocols tls1.2 tls1.3
    }
    
    # Global options
    admin localhost:2019
    
    # Main domain
    ${domain} {
        encode gzip zstd
        log {
            output file ${LOG_DIR}/caddy/access.log
            level INFO
        }
        
        # Proxy to all services
        handle_path /api/* {
            reverse_proxy ${TENANT_PREFIX}-litellm:4000
        }
        
        handle_path / {
            reverse_proxy ${TENANT_PREFIX}-openwebui:3000
        }
        
        # Add other service routes...
    }
}
EOF
    
    echo "Let's Encrypt configuration generated for $domain"
}

# Manual Certificate (TLS_MODE=manual)
configure_manual_tls() {
    local domain="$1"
    local cert_file="$2"
    local key_file="$3"
    
    echo "Configuring manual TLS for $domain..."
    
    # Validate certificate files exist
    if [[ ! -f "$cert_file" ]]; then
        fail "Certificate file not found: $cert_file"
    fi
    
    if [[ ! -f "$key_file" ]]; then
        fail "Private key file not found: $key_file"
    fi
    
    # Generate Caddyfile with manual TLS
    cat > "${CONFIG_DIR}/caddy/Caddyfile" << EOF
{
    admin localhost:2019
    
    ${domain} {
        encode gzip zstd
        log {
            output file ${LOG_DIR}/caddy/access.log
            level INFO
        }
        
        tls ${cert_file} ${key_file}
        
        # Service routes...
        handle_path /api/* {
            reverse_proxy ${TENANT_PREFIX}-litellm:4000
        }
        
        handle_path / {
            reverse_proxy ${TENANT_PREFIX}-openwebui:3000
        }
    }
}
EOF
    
    echo "Manual TLS configuration generated for $domain"
}

# Self-Signed Certificate (TLS_MODE=selfsigned)
configure_selfsigned_tls() {
    local domain="$1"
    
    echo "Generating self-signed certificate for $domain..."
    
    # Generate self-signed certificate
    local cert_dir="${CONFIG_DIR}/ssl"
    mkdir -p "$cert_dir"
    
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$cert_dir/server.key" \
        -out "$cert_dir/server.crt" \
        -subj "/C=${CERT_COUNTRY}/ST=${CERT_STATE}/L=${CERT_CITY}/O=${CERT_ORG}/OU=AI Platform/CN=$domain" \
        2>/dev/null || fail "Failed to generate self-signed certificate"
    
    echo "Self-signed certificate generated: $cert_dir/server.crt"
    
    # Generate Caddyfile with self-signed TLS
    cat > "${CONFIG_DIR}/caddy/Caddyfile" << EOF
{
    admin localhost:2019
    
    ${domain} {
        encode gzip zstd
        log {
            output file ${LOG_DIR}/caddy/access.log
            level INFO
        }
        
        tls ${cert_dir}/server.crt ${cert_dir}/server.key {
            # Accept self-signed certificates in development
            on_demand
        }
        
        # Service routes...
        handle_path /api/* {
            reverse_proxy ${TENANT_PREFIX}-litellm:4000
        }
        
        handle_path / {
            reverse_proxy ${TENANT_PREFIX}-openwebui:3000
        }
    }
}
EOF
    
    echo "Self-signed TLS configuration generated for $domain"
}

# No TLS (TLS_MODE=none)
configure_no_tls() {
    local domain="$1"
    
    echo "Configuring HTTP-only for $domain..."
    
    # Generate Caddyfile without TLS
    cat > "${CONFIG_DIR}/caddy/Caddyfile" << EOF
{
    admin localhost:2019
    
    # Disable automatic HTTPS
    auto_https off
    
    ${domain}:80 {
        encode gzip zstd
        log {
            output file ${LOG_DIR}/caddy/access.log
            level INFO
        }
        
        # Service routes...
        handle_path /api/* {
            reverse_proxy ${TENANT_PREFIX}-litellm:4000
        }
        
        handle_path / {
            reverse_proxy ${TENANT_PREFIX}-openwebui:3000
        }
    }
}
EOF
    
    echo "HTTP-only configuration generated for $domain"
}
```

**TLS Configuration Summary:**

| TLS Mode | Script 1 Input | Script 2 Implementation | Use Case | Security Level |
|-----------|---------------|------------------------|-----------|---------------|
| **Let's Encrypt** | Email + DNS validation | Automatic cert generation + renewal | Production with public domain | 🔒 High |
| **Manual** | Certificate + key file paths | Load provided cert/key | Production with custom certificates | 🔒 High |
| **Self-Signed** | Org details + domain | Generate 365-day cert | Development/internal testing | ⚠️ Medium |
| **None** | Confirmation only | HTTP-only configuration | Local development only | ❌ Low |

### **🚨 PORT CONFLICT PRE-CHECKING**

**Comprehensive port validation before deployment:**
```bash
# Port conflict detection (Script 1)
check_port_conflicts() {
    echo "Checking for port conflicts..."
    
    # Collect all required ports from platform.conf
    local required_ports=()
    
    # Infrastructure ports
    [[ "${POSTGRES_ENABLED}" == "true" ]] && required_ports+=("${POSTGRES_PORT:-5432}")
    [[ "${REDIS_ENABLED}" == "true" ]] && required_ports+=("${REDIS_PORT:-6379}")
    
    # Service ports
    [[ "${LITELLM_ENABLED}" == "true" ]] && required_ports+=("${LITELLM_PORT:-4000}")
    [[ "${OLLAMA_ENABLED}" == "true" ]] && required_ports+=("${OLLAMA_PORT:-11434}")
    [[ "${OPENWEBUI_ENABLED}" == "true" ]] && required_ports+=("${OPENWEBUI_PORT:-3000}")
    [[ "${QDRANT_ENABLED}" == "true" ]] && required_ports+=("${QDRANT_PORT:-6333}")
    [[ "${N8N_ENABLED}" == "true" ]] && required_ports+=("${N8N_PORT:-5678}")
    [[ "${CODESERVER_ENABLED}" == "true" ]] && required_ports+=("${CODESERVER_PORT:-8443}")
    
    # Add all other enabled service ports...
    
    # Check each port against currently listening ports
    local conflicts=()
    for port in "${required_ports[@]}"; do
        if ss -tlnp 2>/dev/null | grep -q ":$port "; then
            local pid=$(ss -tlnp 2>/dev/null | grep ":$port " | head -1 | awk '{print $7}')
            local process=$(ps -p "$pid" -o comm= 2>/dev/null)
            conflicts+=("Port $port: already in use by $process (PID $pid)")
        fi
    done
    
    # Report conflicts
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        echo "❌ PORT CONFLICTS DETECTED:"
        printf '%s\n' "${conflicts[@]}"
        echo ""
        echo "Options:"
        echo "  1. Change conflicting ports in platform.conf"
        echo "  2. Stop conflicting processes"
        echo "  3. Use different tenant ID"
        fail "Port conflicts must be resolved before deployment"
    else
        echo "✅ No port conflicts detected for required ports"
        echo "Required ports: ${required_ports[*]}"
    fi
}

# Port availability waiting (Scripts 2, 3)
wait_for_port() {
    local port="$1"
    local timeout="${2:-30}"
    local service="${3:-service}"
    
    echo "Waiting for port $port to become available..."
    local waited=0
    while ! ss -tlnp 2>/dev/null | grep -q ":$port "; do
        if [[ $waited -ge $timeout ]]; then
            fail "Port $port did not become available within ${timeout}s"
        fi
        sleep 1
        waited=$((waited + 1))
    done
    
    echo "Port $port is available for $service"
}
```

### **📊 DYNAMIC SERVICE PORT REFERENCE**

| Service | Internal Port | Host Port Variable | Protocol | Subdomain Variable | Health Check | Dynamic URL |
|---------|---------------|------------------|----------|-------------------|--------------|-------------|
| **Infrastructure** | | | | | | |
| PostgreSQL | 5432 | ${POSTGRES_PORT} | TCP | postgres.${DOMAIN} | `/healthz` | http://postgres.${DOMAIN}:${POSTGRES_PORT} |
| Redis | 6379 | ${REDIS_PORT} | TCP | redis.${DOMAIN} | TCP socket | redis://${TENANT_PREFIX}-redis:${REDIS_PORT} |
| **LLM Gateway** | | | | | | |
| LiteLLM | 4000 | ${LITELLM_PORT} | HTTP | llm.${DOMAIN} | `/health` | http://llm.${DOMAIN}:${LITELLM_PORT} |
| Bifrost | 8181 | ${BIFROST_PORT} | HTTP | llm.${DOMAIN} | `/healthz` | http://llm.${DOMAIN}:${BIFROST_PORT} |
| **Local LLM** | | | | | | |
| Ollama | 11434 | ${OLLAMA_PORT} | HTTP | ollama.${DOMAIN} | `/api/tags` | http://ollama.${DOMAIN}:${OLLAMA_PORT} |
| **Web UIs** | | | | | | |
| Open WebUI | 3000 | ${OPENWEBUI_PORT} | HTTP | chat.${DOMAIN} | `/` | https://chat.${DOMAIN} |
| LibreChat | 3010 | ${LIBRECHAT_PORT} | HTTP | librechat.${DOMAIN} | `/` | https://librechat.${DOMAIN} |
| Dify | 5001 | ${DIFY_WEB_PORT} | HTTP | dify.${DOMAIN} | `/health` | https://dify.${DOMAIN} |
| AnythingLLM | 3001 | ${ANYTHINGLLM_PORT} | HTTP | anything.${DOMAIN} | `/` | https://anything.${DOMAIN} |
| OpenClaw | 3002 | ${OPENCLAW_PORT} | HTTP | openclaw.${DOMAIN} | `/` | https://openclaw.${DOMAIN} |
| **Vector Databases** | | | | | | |
| Qdrant | 6333/6334 | ${QDRANT_REST_PORT} | HTTP/GRPC | qdrant.${DOMAIN} | `/health` | http://qdrant.${DOMAIN}:${QDRANT_REST_PORT} |
| Weaviate | 8080 | ${WEAVIATE_PORT} | HTTP | weaviate.${DOMAIN} | `/v1/.well-known/ready` | https://weaviate.${DOMAIN} |
| ChromaDB | 8000 | ${CHROMA_PORT} | HTTP | chroma.${DOMAIN} | `/api/v1/heartbeat` | https://chroma.${DOMAIN} |
| Milvus | 19530 | ${MILVUS_PORT} | HTTP | milvus.${DOMAIN} | `/healthz` | https://milvus.${DOMAIN} |
| **Automation** | | | | | | |
| n8n | 5678 | ${N8N_PORT} | HTTP | n8n.${DOMAIN} | `/healthz` | https://n8n.${DOMAIN} |
| Flowise | 3100 | ${FLOWISE_PORT} | HTTP | flowise.${DOMAIN} | `/api/v1/ping` | https://flowise.${DOMAIN} |
| **Identity** | | | | | | |
| Authentik | 9000 | ${AUTHENTIK_PORT} | HTTP | auth.${DOMAIN} | `/` | https://auth.${DOMAIN} |
| **Monitoring** | | | | | | |
| Grafana | 3030 | ${GRAFANA_PORT} | HTTP | monitor.${DOMAIN} | `/api/health` | https://monitor.${DOMAIN} |
| Prometheus | 9090 | ${PROMETHEUS_PORT} | HTTP | prometheus.${DOMAIN} | `/-/healthy` | http://prometheus.${DOMAIN}:${PROMETHEUS_PORT} |
| **Development** | | | | | | |
| Code Server | 8443 | ${CODESERVER_PORT} | HTTP | code.${DOMAIN} | `/healthz` | https://code.${DOMAIN} |
| Continue.dev | 3000 | ${CONTINUE_PORT} | HTTP | continue.${DOMAIN} | `/` | https://continue.${DOMAIN} |
| **Ingestion** | | | | | | |
| Rclone | 5572 | ${RCLONE_PORT} | HTTP | rclone.${DOMAIN} | N/A | https://rclone.${DOMAIN} |
| **Memory Layer** | | | | | | |
| Mem0 | 8765 | ${MEM0_PORT} | HTTP | mem0.${DOMAIN} | `/health` | http://mem0.${DOMAIN}:${MEM0_PORT} |

### **🏥 MISSION CONTROL HEALTH DASHBOARD**

**Complete platform health verification and URL generation:**
```bash
# Generate health dashboard (Script 3 --health-check)
bash scripts/3-configure-services.sh ${TENANT_ID} --health-check

# Expected output:
╔════════════════════════════════════════════════════════╗
║                    PLATFORM HEALTH DASHBOARD                      ║
╚══════════════════════════════════════════════════════════╝

  Tenant: ${TENANT_ID}
  Domain: ${DOMAIN}
  Network: ${DOCKER_NETWORK}
  Base Dir: ${BASE_DIR}

Core Infrastructure:
  PostgreSQL    🟢 ${POSTGRES_STATUS}    http://postgres.${DOMAIN}:${POSTGRES_PORT}
  Redis       🟢 ${REDIS_STATUS}       redis://${TENANT_PREFIX}-redis:${REDIS_PORT}
  Caddy       🟢 ${CADDY_STATUS}      https://${DOMAIN}

AI Runtime:
  LiteLLM     🟢 ${LITELLM_STATUS}    http://llm.${DOMAIN}:${LITELLM_PORT}
  Ollama      🟢 ${OLLAMA_STATUS}     http://ollama.${DOMAIN}:${OLLAMA_PORT}
  Qdrant      🟢 ${QDRANT_STATUS}    http://qdrant.${DOMAIN}:${QDRANT_PORT}

Web Interfaces:
  OpenWebUI   🟢 ${OPENWEBUI_STATUS}  https://chat.${DOMAIN}
  LibreChat   🟢 ${LIBRECHAT_STATUS} https://librechat.${DOMAIN}
  Dify        🟢 ${DIFY_STATUS}       https://dify.${DOMAIN}

Development:
  Code Server 🟢 ${CODESERVER_STATUS} https://code.${DOMAIN}
  Grafana     🟢 ${GRAFANA_STATUS}    https://monitor.${DOMAIN}

Service Tests:
  • LLM Pipeline: curl -s http://llm.${DOMAIN}:${LITELLM_PORT}/v1/models \
                   -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" | jq '.data[].id'
  • Vector DB: curl -s http://qdrant.${DOMAIN}:${QDRANT_PORT}/health
  • Memory: curl -s http://mem0.${DOMAIN}:${MEM0_PORT}/health
  • Full Stack: Test complete LLM → Vector DB → Web UI flow
```

### **NON-NEGOTIABLE: UNBOUND VARIABLES**

**Every variable MUST be bound before use. No unbound variables allowed.**

```bash
# ✅ CORRECT: Variable is always bound before use
if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
    # POSTGRES_PASSWORD is guaranteed to be set
    echo "Configuring PostgreSQL with password: ${POSTGRES_PASSWORD}"
fi

# ❌ FORBIDDEN: Unbound variable access
echo "Database password: ${POSTGRES_PASSWORD}"  # FAILS if POSTGRES_ENABLED=false

# ✅ CORRECT: Safe variable access with defaults
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(generate_password 20)}"
echo "Using PostgreSQL password: ${POSTGRES_PASSWORD}"

# ✅ CORRECT: Explicit variable validation
: "${TENANT_ID:?TENANT_ID is required}"
: "${BASE_DIR:?BASE_DIR is required}"
: "${DOCKER_NETWORK:?DOCKER_NETWORK is required}"
```

**Variable Binding Rules:**
1. **All variables must be set in platform.conf** or have safe defaults
2. **No conditional variable access** without validation
3. **Required parameters must use `:?` syntax** for immediate failure
4. **Optional parameters must use `:-` syntax** for default values
5. **All scripts source platform.conf** before variable access
6. **No hardcoded fallback values** in scripts (except system defaults)

**Validation Pattern:**
```bash
# Script 1: Generate with validation
generate_platform_conf() {
    # Required variables - fail if missing
    : "${TENANT_ID:?Tenant ID required}"
    : "${DOMAIN:?Domain required}"
    
    # Optional variables - with safe defaults
    POSTGRES_ENABLED="${POSTGRES_ENABLED:-false}"
    REDIS_ENABLED="${REDIS_ENABLED:-false}"
    
    # Generate secrets only if needed
    if [[ "${POSTGRES_ENABLED}" == "true" ]]; then
        POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(generate_password 20)}"
    fi
}

# Script 2: Load and validate
load_and_validate() {
    source "${BASE_DIR}/platform.conf"
    
    # Validate all required variables are set
    local required_vars=("TENANT_ID" "DOMAIN" "BASE_DIR" "DOCKER_NETWORK")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            fail "Required variable not set: $var"
        fi
    done
}
```

---

## 🎯 **GROUNDED TRUTH - LESSONS LEARNED & PRINCIPLES**

### **Core Architectural Principles (Non-Negotiable)**

1. **🔧 4-Script Modular Architecture**
   - **Script 0**: Nuclear cleanup (root execution allowed)
   - **Script 1**: Input collection ONLY (writes platform.conf)
   - **Script 2**: Deployment engine (reads platform.conf, deploys containers)
   - **Script 3**: Mission Control Hub (service management, health, configuration)
   - **NO cross-script boundaries** - each script has single responsibility

2. **📁 Data Confinement** 
   - **ALL data under `/mnt/${TENANT_ID}/`** - no exceptions
   - **Shared config in `/etc/ai-platform.env`** - system-wide only
   - **No data in `/opt`, `/tmp`, or user home directories**
   - **Bind mounts only** - no named volumes except system caches

3. **🔑 Single Source of Truth**
   - **platform.conf is ONLY source of truth** - no mission-control.json
   - **All scripts source platform.conf** - no direct variable access
   - **Generated configs are DERIVED** - not primary sources
   - **No .env files** - all secrets inline in docker-compose

4. **🚪 Zero Root Execution**
   - **All scripts reject root execution** (except Script 0)
   - **Tenant user runs all operations** with sudo for system tasks
   - **Containers run as tenant UID/GID** where possible
   - **Docker group membership required** for container operations

5. **🌐 Network Architecture**
   - **Single Docker bridge network per tenant**
   - **Reverse proxy handles all external access** (ports 80/443 only)
   - **All services bind to 127.0.0.1** internally
   - **Subdomain routing via proxy** - no direct port exposure

6. **📊 Complete Service Integration**
   - **All services auto-wired** - no manual configuration
   - **LLM proxy routes to all providers** (local-first strategy)
   - **Vector DBs available to all AI services**
   - **Authentication unified across all web UIs**

### **Implementation Anti-Patterns (Never Do These)**

1. **❌ Cross-Script Function Calls**
   ```bash
   # WRONG: Script 2 calling Script 3 functions directly
   source "${SCRIPT_DIR}/3-configure-services.sh"
   configure_ollama
   
   # CORRECT: Script 3 handles its own configuration
   # Script 2 only deploys containers
   ```

2. **❌ Hardcoded Service Dependencies**
   ```bash
   # WRONG: Hardcoded service URLs
   LLM_GATEWAY_URL="http://localhost:4000"
   
   # CORRECT: Use platform.conf variables
   LLM_GATEWAY_URL="http://localhost:${LITELLM_PORT}"
   ```

3. **❌ External Configuration Files**
   ```bash
   # WRONG: Separate config files
   . /etc/ai-platform/secrets
   
   # CORRECT: Everything in platform.conf
   source "${BASE_DIR}/platform.conf"
   ```

4. **❌ Mixed Data Locations**
   ```bash
   # WRONG: Data scattered across filesystem
   LOG_FILE="/tmp/ai-platform.log"
   CONFIG_DIR="/opt/ai-platform"
   
   # CORRECT: All data under tenant directory
   LOG_FILE="${LOG_DIR}/platform.log"
   CONFIG_DIR="${BASE_DIR}/config"
   ```

### **Deployment Success Patterns**

1. **✅ Pre-Deployment Validation**
   - Check all required binaries available
   - Validate Docker daemon running
   - Verify user in docker group
   - Check port conflicts before deployment
   - Validate DNS resolution for domains

2. **✅ Atomic Deployment Steps**
   - Generate all configs before starting any containers
   - Start services in dependency order
   - Wait for health checks before dependent services
   - Mark completion only after full verification

3. **✅ Post-Deployment Verification**
   - Test all service endpoints
   - Verify cross-service integrations
   - Validate SSL certificates
   - Test complete LLM pipeline flow
   - Generate access URLs and credentials

### **Troubleshooting Principles**

1. **🔍 Check Dependencies First**
   - Is Docker daemon running?
   - Is user in docker group?
   - Are required binaries available?
   - Is platform.conf present and valid?

2. **📋 Verify Configuration Chain**
   - Did Script 1 complete successfully?
   - Did Script 2 deploy all containers?
   - Are all containers healthy?
   - Are ports correctly mapped?

3. **🌐 Test Network Layer**
   - Can containers reach each other?
   - Is reverse proxy routing correctly?
   - Are SSL certificates valid?
   - Are DNS records pointing correctly?

4. **🔧 Check Service Health**
   - Are health checks passing?
   - Are logs showing errors?
   - Are all dependencies satisfied?
   - Are resources sufficient?

### **Future-Proofing Guidelines**

1. **🏗️ Maintain Modularity**
   - Each service independently configurable
   - No required service dependencies
   - Pluggable architecture for new services
   - Consistent configuration patterns

2. **🔄 Enable Service Management**
   - Add/remove services without full redeploy
   - Runtime configuration changes
   - Hot-reload where possible
   - Graceful service restarts

3. **📈 Preserve Backward Compatibility**
   - Migration paths for configuration changes
   - Version detection in platform.conf
   - Graceful handling of deprecated variables
   - Clear upgrade documentation

---

## 🚀 **QUICK START**

### **📊 COMPLETE SERVICE PORT REFERENCE**

| Service | Internal Port | Host Port | Protocol | Subdomain | Health Check | Notes |
|---------|---------------|------------|----------|------------|--------------|-------|
| **Infrastructure** | | | | | | |
| PostgreSQL | 5432 | ${POSTGRES_PORT} | TCP | postgres.${DOMAIN} | `/healthz` |
| Redis | 6379 | ${REDIS_PORT} | TCP | redis.${DOMAIN} | TCP socket |
| **LLM Gateway** | | | | | | |
| LiteLLM | 4000 | ${LITELLM_PORT} | HTTP | llm.${DOMAIN} | `/health` |
| Bifrost | 8181 | ${BIFROST_PORT} | HTTP | llm.${DOMAIN} | `/healthz` |
| **Local LLM** | | | | | | |
| Ollama | 11434 | ${OLLAMA_PORT} | HTTP | ollama.${DOMAIN} | `/api/tags` |
| **Web UIs** | | | | | | |
| Open WebUI | 3000 | ${OPENWEBUI_PORT} | HTTP | chat.${DOMAIN} | `/` |
| LibreChat | 3010 | ${LIBRECHAT_PORT} | HTTP | librechat.${DOMAIN} | `/` |
| Dify | 5001 | ${DIFY_WEB_PORT} | HTTP | dify.${DOMAIN} | `/health` |
| AnythingLLM | 3001 | ${ANYTHINGLLM_PORT} | HTTP | anything.${DOMAIN} | `/` |
| OpenClaw | 3002 | ${OPENCLAW_PORT} | HTTP | openclaw.${DOMAIN} | `/` |
| **Vector Databases** | | | | | | |
| Qdrant | 6333/6334 | ${QDRANT_REST_PORT} | HTTP/GRPC | qdrant.${DOMAIN} | `/health` |
| Weaviate | 8080 | ${WEAVIATE_PORT} | HTTP | weaviate.${DOMAIN} | `/v1/.well-known/ready` |
| ChromaDB | 8000 | ${CHROMA_PORT} | HTTP | chroma.${DOMAIN} | `/api/v1/heartbeat` |
| Milvus | 19530 | ${MILVUS_PORT} | HTTP | milvus.${DOMAIN} | `/healthz` |
| **Automation** | | | | | | |
| n8n | 5678 | ${N8N_PORT} | HTTP | n8n.${DOMAIN} | `/healthz` |
| Flowise | 3100 | ${FLOWISE_PORT} | HTTP | flowise.${DOMAIN} | `/api/v1/ping` |
| **Identity** | | | | | | |
| Authentik | 9000 | ${AUTHENTIK_PORT} | HTTP | auth.${DOMAIN} | `/` |
| **Monitoring** | | | | | | |
| Grafana | 3030 | ${GRAFANA_PORT} | HTTP | monitor.${DOMAIN} | `/api/health` |
| Prometheus | 9090 | ${PROMETHEUS_PORT} | HTTP | prometheus.${DOMAIN} | `/-/healthy` |
| **Development** | | | | | | |
| Code Server | 8443 | ${CODESERVER_PORT} | HTTP | code.${DOMAIN} | `/healthz` |
| Continue.dev | 3000 | ${CONTINUE_PORT} | HTTP | continue.${DOMAIN} | `/` |
| **Ingestion** | | | | | | |
| Rclone | 5572 | ${RCLONE_PORT} | HTTP | rclone.${DOMAIN} | N/A |
| **Memory Layer** | | | | | | |
| Mem0 | 8765 | ${MEM0_PORT} | HTTP | mem0.${DOMAIN} | `/health` |

### **📁 COMPLETE DATA LAYOUT ARCHITECTURE**

```
/mnt/${TENANT_ID}/                    # EBS mount point - ALL PLATFORM DATA
├── platform.conf                     # Single source of truth (generated by Script 1)
├── config/                          # Generated configs (read-only in containers)
│   ├── docker-compose.yml           # Generated by Script 2
│   ├── caddy/
│   │   └── Caddyfile             # Reverse proxy configuration
│   ├── nginx/
│   │   └── nginx.conf             # Nginx configuration (alternative)
│   ├── litellm/
│   │   └── config.yaml            # LLM routing configuration
│   ├── bifrost/
│   │   └── config.yaml            # LLM gateway configuration
│   ├── mem0/
│   │   ├── config.yaml            # Memory layer configuration
│   │   └── server.py             # FastAPI server (generated)
│   ├── postgres/
│   │   └── init.sql              # Database initialization (generated)
│   ├── qdrant/
│   │   └── config.yaml            # Vector DB configuration
│   ├── n8n/
│   │   └── .env                  # n8n configuration (generated)
│   ├── grafana/
│   │   ├── dashboards/           # Pre-imported dashboards
│   │   └── provisioning/         # Auto-provisioning config
│   ├── prometheus/
│   │   └── prometheus.yml         # Metrics collection config
│   └── ingestion/
│       ├── rclone.conf            # Cloud storage sync config
│       └── pipeline.yaml           # Automated processing config
├── data/                            # Runtime data (writable by containers)
│   ├── postgres/                   # PostgreSQL data files
│   ├── redis/                      # Redis persistence files
│   ├── qdrant/                    # Vector database storage
│   ├── weaviate/                  # Weaviate data
│   ├── chroma/                    # ChromaDB data
│   ├── milvus/                    # Milvus data
│   ├── ollama/                    # LLM models and data
│   ├── mem0/                      # Memory layer storage
│   ├── openwebui/                 # Web UI data
│   ├── librechat/                 # Web UI data
│   ├── dify/                      # Web UI data
│   ├── anythingllm/                # Web UI data
│   ├── openclaw/                  # Browser session data
│   ├── n8n/                       # Workflow data
│   ├── flowise/                    # Workflow data
│   ├── authentik/                  # Identity data
│   ├── grafana/                    # Monitoring data
│   ├── prometheus/                 # Metrics data
│   ├── codeserver/                 # Development environment
│   ├── signalbot/                  # Messaging gateway data
│   └── ingestion/                 # Ingestion pipeline state
├── logs/                            # Application logs (per-service)
│   ├── platform.log               # Main platform log
│   ├── deploy-*.log              # Deployment logs
│   ├── postgres.log               # PostgreSQL logs
│   ├── redis.log                  # Redis logs
│   ├── ollama.log                # Ollama logs
│   ├── litellm.log               # LiteLLM logs
│   ├── bifrost.log               # Bifrost logs
│   ├── mem0.log                  # Mem0 logs
│   ├── qdrant.log                # Qdrant logs
│   ├── openwebui.log             # Web UI logs
│   ├── n8n.log                   # n8n logs
│   ├── grafana.log                # Grafana logs
│   └── prometheus.log             # Prometheus logs
└── .configured/                      # Idempotency markers
    ├── deploy-services            # Script 2 completion marker
    ├── configure-services          # Script 3 completion marker
    ├── configure-ollama           # Per-service markers
    ├── configure-litellm
    ├── configure-openwebui
    ├── configure-qdrant
    └── ... (one per configured service)
```

### **🔧 COMPLETE SOFTWARE STACK CATALOGUE**

| Category | Service | Container Image | Default Port | Purpose | Integration |
|----------|---------|-----------------|--------------|---------|------------|
| **Infrastructure** | PostgreSQL | postgres:15-alpine | 5432 | Primary database for n8n, Dify, Authentik |
| | Redis | redis:7-alpine | 6379 | Cache and session storage |
| **LLM Gateway** | LiteLLM | litellm/litellm:main | 4000 | LLM routing and load balancing |
| | Bifrost | ghcr.io/maximhq/bifrost:latest | 8181 | Lightweight Go-based LLM proxy |
| **Local LLM** | Ollama | ollama/ollama:latest | 11434 | Local LLM inference |
| **Memory Layer** | Mem0 | python:3.11-slim | 8765 | Per-tenant conversation memory |
| **Web UIs** | Open WebUI | ghcr.io/open-webui/open-webui:main | 3000 | AI chat interface |
| | LibreChat | ghcr.io/danny-avila/librechat:latest | 3010 | Alternative AI chat interface |
| | Dify | langgenius/dify:latest | 5001 | Complete AI application platform |
| | AnythingLLM | mintplexlabs/anythingllm:latest | 3001 | Document AI and chat interface |
| | OpenClaw | ghcr.io/openclaw/openclaw:latest | 3002 | Web-based terminal/browser |
| **Vector Databases** | Qdrant | qdrant/qdrant:latest | 6333 | High-performance vector database |
| | Weaviate | semitechnologies/weaviate:latest | 8080 | GraphQL-based vector database |
| | ChromaDB | chromadb/chroma:latest | 8000 | Lightweight vector database |
| | Milvus | milvusdb/milvus:latest | 19530 | Enterprise-scale vector database |
| **Automation** | n8n | n8nio/n8n:latest | 5678 | Workflow automation platform |
| | Flowise | flowise/flowise:latest | 3100 | AI workflow builder |
| **Identity** | Authentik | ghcr.io/goauthentik/server:latest | 9000 | SSO and identity management |
| **Monitoring** | Grafana | grafana/grafana:latest | 3030 | Metrics visualization |
| | Prometheus | prom/prometheus:latest | 9090 | Metrics collection |
| **Development** | Code Server | linuxserver/code-server:latest | 8443 | VS Code in browser |
| | Continue.dev | continue-dev/continue:latest | 3000 | AI-powered development assistant |
| **Ingestion** | Rclone | rclone/rclone:latest | 5572 | Cloud storage synchronization |
| **Reverse Proxy** | Caddy | caddy:2-alpine | 80/443 | Automatic HTTPS and routing |
| | Nginx | nginx:alpine | 80/443 | High-performance reverse proxy |

### **🚀 STACK PRESETS (Complete Reference)**

| Preset | Services Enabled | Use Case | Resource Requirements |
|--------|-----------------|-----------|---------------------|
| **minimal** | PostgreSQL, Redis, LiteLLM, Ollama, Open WebUI, Qdrant, Caddy | Basic AI chat with local LLM |
| **dev** | minimal + Code Server, Continue.dev, n8n, Flowise, Mem0 | Development environment with AI tools |
| **standard** | dev + LibreChat, Dify, Grafana, Prometheus, Authentik | Standard production setup |
| **full** | All 25 services enabled | Complete enterprise AI platform |
| **custom** | All services disabled, enable individually | Custom configuration |

### **🚀 4-SCRIPT DEPLOYMENT FRAMEWORK**

**Complete deployment sequence with proper ordering and validation:**
```bash
# =============================================================================
# STEP 0: NUCLEAR CLEANUP (Always run first)
# =============================================================================
# Purpose: Complete system reset - remove all containers, data, and configured markers
# Usage: sudo bash scripts/0-complete-cleanup.sh
# =============================================================================
echo "=== AI PLATFORM NUCLEAR CLEANUP ==="

# Remove all containers for all tenants
echo "Stopping and removing all AI Platform containers..."
docker ps -a --format "table {{.Names}}\t{{.Status}}" | \
    grep -E "ai-.*|prod-.*|staging-.*" | \
    while read -r container status; do
        echo "Removing container: $container (status: $status)"
        docker stop "$container" 2>/dev/null || true
        docker rm "$container" 2>/dev/null || true
    done

# Remove all Docker networks
echo "Removing AI Platform networks..."
docker network ls --format "table {{.Name}}" | \
    grep -E "ai-.*|prod-.*|staging-.*" | \
    while read -r network; do
        echo "Removing network: $network"
        docker network rm "$network" 2>/dev/null || true
    done

# Remove all platform volumes (data loss warning!)
echo "WARNING: This will remove ALL AI Platform data volumes!"
read -p "Continue with data loss? [yes/N]: " confirm

if [[ "$confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Removing platform volumes..."
    docker volume ls --format "table {{.Name}}" | \
        grep -E "ai-.*|prod-.*|staging-.*|postgres_data|redis_data|qdrant_data" | \
        while read -r volume; do
            echo "Removing volume: $volume"
            docker volume rm "$volume" 2>/dev/null || true
        done
else
    echo "Volume cleanup cancelled"
fi

# Remove all configured markers
echo "Removing idempotency markers..."
find /mnt -maxdepth 1 -type d -name "ai-*" -o -name "prod-*" -o -name "staging-*" | \
    while read -r tenant_dir; do
        if [[ -d "$tenant_dir/.configured" ]]; then
            echo "Removing markers for: $tenant_dir"
            rm -rf "$tenant_dir/.configured"
        fi
    done

echo "=== NUCLEAR CLEANUP COMPLETE ==="

# =============================================================================
# STEP 1: SYSTEM SETUP & INPUT COLLECTION
# =============================================================================
# Purpose: Collect ALL inputs, generate platform.conf, create tenant user, mount EBS
# Usage: sudo bash scripts/1-setup-system.sh
# =============================================================================
echo "=== AI PLATFORM SYSTEM SETUP ==="

# Source Mission Control utilities
source "${SCRIPT_DIR}/3-configure-services.sh"

# System validation
check_dependencies
check_docker_group
check_non_root

# Identity collection
echo "Collecting tenant identity..."
read -p "Platform prefix [ai-]: " PLATFORM_PREFIX
PLATFORM_PREFIX="${PLATFORM_PREFIX:-ai-}"

read -p "Tenant ID [required]: " TENANT_ID
: "${TENANT_ID:?TENANT_ID is required}"

read -p "Base domain [required]: " DOMAIN
: "${DOMAIN:?DOMAIN is required}"

# EBS volume detection and mounting
echo "=== EBS VOLUME SETUP ==="
detect_ebs_volumes
create_mount_point
format_ebs_volume
detect_volume_uuid
update_fstab
mount_ebs_volume

# DNS validation
echo "=== DNS VALIDATION ==="
validate_dns_setup "$DOMAIN"

# Service selection and configuration
echo "=== SERVICE CONFIGURATION ==="
# ... (collect all 95+ variables with validation)

# Generate platform.conf
echo "Generating platform.conf..."
write_platform_conf

# Create tenant user
echo "Creating tenant user: ${PLATFORM_PREFIX}${TENANT_ID}"
if ! id "${PLATFORM_PREFIX}${TENANT_ID}" &>/dev/null; then
    useradd -m -s /bin/bash "${PLATFORM_PREFIX}${TENANT_ID}"
    usermod -aG docker "${PLATFORM_PREFIX}${TENANT_ID}"
    echo "Tenant user created: ${PLATFORM_PREFIX}${TENANT_ID}"
else
    echo "Tenant user already exists: ${PLATFORM_PREFIX}${TENANT_ID}"
fi

echo "=== SYSTEM SETUP COMPLETE ==="

# =============================================================================
# STEP 2: DEPLOYMENT ENGINE
# =============================================================================
# Purpose: Generate ALL derived configs, deploy containers in dependency order
# Usage: sudo -u ${PLATFORM_PREFIX}${TENANT_ID} bash scripts/2-deploy-services.sh
# =============================================================================
echo "=== AI PLATFORM DEPLOYMENT ==="

# Source platform.conf and validate
load_platform_conf
validate_configuration

# Source Mission Control utilities
source "${SCRIPT_DIR}/3-configure-services.sh"

# Pre-deployment validation
echo "=== PRE-DEPLOYMENT VALIDATION ==="
check_port_conflicts
validate_domain "$DOMAIN"

# Generate ALL configurations
echo "=== CONFIG GENERATION ==="
generate_caddy_config
generate_litellm_config
generate_bifrost_config
generate_mem0_config
generate_postgres_init
# ... (generate all service configs)

# Generate docker-compose.yml
echo "=== DOCKER COMPOSE GENERATION ==="
generate_compose

# Deploy containers in dependency order
echo "=== CONTAINER DEPLOYMENT ==="
docker-compose -f "${COMPOSE_FILE}" pull
docker-compose -f "${COMPOSE_FILE}" up -d

# Wait for core infrastructure
echo "=== INFRASTRUCTURE HEALTH WAIT ==="
wait_for_service "PostgreSQL" "postgres://${TENANT_PREFIX}-postgres:5432" "${TENANT_PREFIX}-postgres"
wait_for_service "Redis" "redis://${TENANT_PREFIX}-redis:6379" "${TENANT_PREFIX}-redis"

# Wait for LLM gateway
if [[ "${LITELLM_ENABLED}" == "true" ]]; then
    wait_for_service "LiteLLM" "http://localhost:${LITELLM_PORT}/health" "${TENANT_PREFIX}-litellm"
fi

if [[ "${BIFROST_ENABLED}" == "true" ]]; then
    wait_for_service "Bifrost" "http://localhost:${BIFROST_PORT}/healthz" "${TENANT_PREFIX}-bifrost"
fi

# Mark deployment complete
touch "${CONFIGURED_DIR}/deploy-services"
echo "=== DEPLOYMENT COMPLETE ==="

# =============================================================================
# STEP 3: MISSION CONTROL HUB
# =============================================================================
# Purpose: Service management, health monitoring, configuration, credentials
# Usage: sudo -u ${PLATFORM_PREFIX}${TENANT_ID} bash scripts/3-configure-services.sh [options]
# =============================================================================
echo "=== AI PLATFORM MISSION CONTROL ==="

# Source platform.conf
load_platform_conf

# Parse command line options
case "${1:-}" in
    --health-check)
        echo "=== PLATFORM HEALTH DASHBOARD ==="
        show_health_dashboard
        ;;
    --start*)
        local service="${1#--start=}"
        echo "Starting service: $service"
        restart_service "$service"
        ;;
    --stop*)
        local service="${1#--stop=}"
        echo "Stopping service: $service"
        docker-compose -f "${COMPOSE_FILE}" stop "$service"
        ;;
    --restart*)
        local service="${1#--restart=}"
        echo "Restarting service: $service"
        restart_service "$service"
        ;;
    --add*)
        local service="${1#--add=}"
        echo "Adding service: $service"
        add_service "$service"
        ;;
    --remove*)
        local service="${1#--remove=}"
        echo "Removing service: $service"
        remove_service "$service"
        ;;
    --show-credentials)
        echo "=== PLATFORM CREDENTIALS ==="
        show_credentials
        ;;
    --rotate-keys*)
        local service="${1#--rotate-keys=}"
        echo "Rotating keys for: $service"
        rotate_service_keys "$service"
        ;;
    --verify-only)
        echo "=== VERIFICATION ONLY MODE ==="
        verify_all_services
        ;;
    "")
        echo "=== FULL CONFIGURATION & HEALTH ==="
        configure_all_enabled_services
        verify_all_services
        ;;
    *)
        echo "Unknown option: $1"
        echo "Available: --health-check, --start, --stop, --restart, --add, --remove, --show-credentials, --rotate-keys, --verify-only"
        exit 1
        ;;
esac

echo "=== MISSION CONTROL COMPLETE ==="
```

### **🎯 DEPLOYMENT SUCCESS METRICS**

**Complete verification checklist:**
- [ ] Script 0 completed successfully (clean slate)
- [ ] Script 1 completed successfully (platform.conf generated)
- [ ] Script 2 completed successfully (containers deployed)
- [ ] Script 3 completed successfully (services configured)
- [ ] All services healthy and accessible
- [ ] DNS resolution working
- [ ] TLS certificates valid
- [ ] EBS volume mounted and persistent
- [ ] Port conflicts resolved
- [ ] Cross-service integrations working

**Platform ready for production use!** 🚀

# Step 2: Service Deployment
./scripts/2-deploy-services.sh      # Deployment Engine - generates configs, deploys containers

# Step 3: Service Configuration & Management
./scripts/3-configure-services.sh   # Mission Control Hub - service management, health, credentials
```

### **P6 — Non-root execution everywhere**

**Core Principle**: The tenant can use sudo to deploy these scripts, however all services should run as tenant uid/gid as much as possible (some may require root or docker group membership). Any AI service should run as non-root docker service as much as possible.

**Implementation Requirements:**
- All scripts check for non-root execution and fail if run as root (except cleanup script)
- All containers run with `user: "${PUID}:${PGID}"` where possible
- Services requiring root privileges are explicitly documented and justified
- Docker group membership is validated before deployment
- File permissions are set to tenant ownership throughout

### **TEMPLATES & EXAMPLES**

**Complete Production Template (Full Reference):**
```bash
#!/bin/bash
# =============================================================================
# AI Platform Production Template
# =============================================================================
# Usage: ./scripts/1-setup-system.sh --template prod-template.conf
# =============================================================================

# ── SECTION 1: PLATFORM IDENTITY ────────────────────────────────────────────
TENANT_ID="datasquiz"
BASE_DOMAIN="datasquiz.example.com"
PLATFORM_ARCH="linux/amd64"
PUID="1000"
PGID="1000"

# ── SECTION 2: DEPLOYMENT SETTINGS ────────────────────────────────────────────
STACK_PRESET="full"
LLM_PROXY_TYPE="litellm"
PROXY_TYPE="caddy"
BASE_DIR="/mnt/datasquiz"
DOCKER_NETWORK="datasquiz-network"

# ── SECTION 3: INFRASTRUCTURE SERVICES ────────────────────────────────────────
POSTGRES_ENABLED="true"
POSTGRES_PORT="5432"
POSTGRES_USER="platform"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
POSTGRES_DB="platform"

REDIS_ENABLED="true"
REDIS_PORT="6379"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"

# ── SECTION 4: DEVELOPMENT STACK ──────────────────────────────────────────────
CODE_SERVER_ENABLED="true"
CODE_SERVER_PORT="8443"
CODE_SERVER_PASSWORD="${CODE_SERVER_PASSWORD:-}"
CODE_SERVER_PROXY_DOMAIN="codeserver.datasquiz.example.com"

CONTINUE_ENABLED="true"
CONTINUE_PORT="3000"
CONTINUE_API_KEY="${CONTINUE_API_KEY:-}"
CONTINUE_LITELM_URL="http://litellm:4000"

# ── SECTION 5: LLM LAYER ───────────────────────────────────────────────────────
OLLAMA_ENABLED="true"
OLLAMA_PORT="11434"
OLLAMA_DEFAULT_MODEL="llama3.2"
OLLAMA_RUNTIME="cpu"
OLLAMA_PULL_DEFAULT_MODEL="true"

# LiteLLM Configuration
LITELLM_ENABLED="true"
LITELLM_PORT="4000"
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-}"
LITELLM_DATABASE_URL="postgresql://platform:${POSTGRES_PASSWORD:-}@postgres:5432/litellm"

# Provider Enablement
ENABLE_OPENAI="true"
ENABLE_ANTHROPIC="true"
ENABLE_GOOGLE="false"
ENABLE_GROQ="true"
ENABLE_OPENROUTER="false"

# Provider API Keys
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
GOOGLE_API_KEY="${GOOGLE_API_KEY:-}"
GROQ_API_KEY="${GROQ_API_KEY:-}"
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"

# ── SECTION 6: WEB UI LAYER ─────────────────────────────────────────────────────
OPENWEBUI_ENABLED="true"
OPENWEBUI_PORT="3000"
OPENWEBUI_PROXY_DOMAIN="chat.datasquiz.example.com"

LIBRECHAT_ENABLED="true"
LIBRECHAT_PORT="3080"
LIBRECHAT_PROXY_DOMAIN="librechat.datasquiz.example.com"

OPENCLAW_ENABLED="true"
OPENCLAW_PORT="8080"
OPENCLAW_PROXY_DOMAIN="terminal.datasquiz.example.com"

ANYTHINGLLM_ENABLED="true"
ANYTHINGLLM_PORT="3001"
ANYTHINGLLM_PROXY_DOMAIN="anything.datasquiz.example.com"

# ── SECTION 7: VECTOR DATABASES ───────────────────────────────────────────────
QDRANT_ENABLED="true"
QDRANT_PORT="6333"
QDRANT_PROXY_DOMAIN="qdrant.datasquiz.example.com"

WEAVIATE_ENABLED="true"
WEAVIATE_PORT="8080"
WEAVIATE_PROXY_DOMAIN="weaviate.datasquiz.example.com"

CHROMA_ENABLED="true"
CHROMA_PORT="8000"
CHROMA_PROXY_DOMAIN="chroma.datasquiz.example.com"

# ── SECTION 8: AUTOMATION LAYER ────────────────────────────────────────────────
N8N_ENABLED="true"
N8N_PORT="5678"
N8N_PROXY_DOMAIN="n8n.datasquiz.example.com"

FLOWISE_ENABLED="true"
FLOWISE_PORT="3010"
FLOWISE_PROXY_DOMAIN="flowise.datasquiz.example.com"

DIFY_ENABLED="true"
DIFY_PORT="5000"
DIFY_PROXY_DOMAIN="dify.datasquiz.example.com"

# ── SECTION 9: IDENTITY LAYER ───────────────────────────────────────────────────
AUTHENTIK_ENABLED="true"
AUTHENTIK_PORT="9000"
AUTHENTIK_PROXY_DOMAIN="auth.datasquiz.example.com"
AUTHENTIK_SECRET_KEY="${AUTHENTIK_SECRET_KEY:-}"
AUTHENTIK_BOOTSTRAP_PASSWORD="${AUTHENTIK_BOOTSTRAP_PASSWORD:-}"
AUTHENTIK_BOOTSTRAP_EMAIL="admin@datasquiz.example.com"

# ── SECTION 10: MONITORING LAYER ────────────────────────────────────────────────
GRAFANA_ENABLED="true"
GRAFANA_PORT="3001"
GRAFANA_PROXY_DOMAIN="grafana.datasquiz.example.com"

PROMETHEUS_ENABLED="true"
PROMETHEUS_PORT="9090"
PROMETHEUS_PROXY_DOMAIN="prometheus.datasquiz.example.com"

# ── SECTION 11: WORKFLOW TOOLS LAYER ─────────────────────────────────────────────
SEARXNG_ENABLED="true"
SEARXNG_PORT="8080"
SEARXNG_PROXY_DOMAIN="search.datasquiz.example.com"

# ── SECTION 12: INGESTION & SYNC LAYER ───────────────────────────────────────────
RCLONE_ENABLED="true"
RCLONE_CONFIG="${RCLONE_CONFIG:-}"

# ── SECTION 13: ALERTING LAYER ───────────────────────────────────────────────────
SIGNALBOT_ENABLED="true"
SIGNALBOT_PORT="8080"
SIGNAL_PHONE="+15551234567"
SIGNAL_RECIPIENT="+15559876543"

# ── SECTION 14: PROXY LAYER ────────────────────────────────────────────────────
CADDY_ENABLED="true"
CADDY_HTTP_PORT="80"
CADDY_HTTPS_PORT="443"

NGINXPM_ENABLED="false"
NGINXPM_PORT="81"

# ── SECTION 15: MEMORY LAYER ────────────────────────────────────────────────────
MEM0_ENABLED="true"
MEM0_PORT="8000"
MEM0_API_KEY="${MEM0_API_KEY:-}"
MEM0_DATABASE_URL="postgresql://platform:${POSTGRES_PASSWORD:-}@postgres:5432/mem0"

# ── SECTION 16: BIFROST LLM GATEWAY ────────────────────────────────────────────
BIFROST_ENABLED="false"
BIFROST_PORT="8090"
BIFROST_API_KEY="${BIFROST_API_KEY:-}"
```

**Minimal Development Template:**
```bash
#!/bin/bash
TENANT_ID="dev"
BASE_DOMAIN="dev.localhost"
STACK_PRESET="minimal"
LLM_PROXY_TYPE="litellm"
PROXY_TYPE="caddy"
BASE_DIR="${HOME}/ai-platform/dev"

# Core services only
POSTGRES_ENABLED="true"
REDIS_ENABLED="true"
LITELLM_ENABLED="true"
OLLAMA_ENABLED="true"
OPENWEBUI_ENABLED="true"
QDRANT_ENABLED="true"
CADDY_ENABLED="true"
MEM0_ENABLED="true"
```
VECTOR_DB_TYPE="qdrant"
MEM0_ENABLED="true"
ENABLE_BACKUP="true"
BACKUP_PROVIDER="s3"
AWS_S3_BUCKET="datasquiz-backups"
EOF

# Deploy with template
./scripts/1-setup-system.sh --template prod-template.conf
```

---

## 📋 **SCRIPT 1 - COMPLETE INPUT GROUPINGS**

### **🏗️ SECTION 1: TENANT CONFIGURATION**
```bash
section "1. Tenant Configuration"

prompt_default TENANT_ID "Tenant identifier" "datasquiz"
prompt_default PREFIX "Container name prefix" "ai"
prompt_default BASE_DOMAIN "Base domain" "datasquiz.example.com"
validate_domain "$BASE_DOMAIN"

# TLS Configuration
prompt_default TLS_MODE "TLS mode" "letsencrypt" "letsencrypt,selfsigned,provided,none"
case "$TLS_MODE" in
    "letsencrypt")
        prompt_required TLS_EMAIL "Let's Encrypt email address"
        ;;
    "selfsigned")
        warn "Self-signed certificates will be generated"
        ;;
    "provided")
        warn "You must provide certificates in /mnt/${TENANT_ID}/config/ssl/"
        ;;
    "none")
        warn "No TLS - only for development"
        ;;
esac
```

### **🤖 SECTION 2: LLM PROXY ARCHITECTURE CHOICE**
```bash
section "2. LLM Proxy Architecture"

prompt_default LLM_PROXY_TYPE "Choose LLM proxy" "litellm" "litellm,bifrost"
case "$LLM_PROXY_TYPE" in
    "litellm")
        LITELLM_ENABLED="true"
        BIFROST_ENABLED="false"
        log "Selected LiteLLM as primary LLM proxy"
        ;;
    "bifrost")
        LITELLM_ENABLED="false"
        BIFROST_ENABLED="true"
        log "Selected Bifrost as alternative LLM proxy"
        ;;
    *)
        fail "Invalid proxy choice: $LLM_PROXY_TYPE"
        ;;
esac
```

### **📦 SECTION 3: STACK PRESET SELECTION**
```bash
section "3. Stack Preset"

prompt_default STACK_PRESET "Choose stack preset" "full" "minimal,standard,full,custom"
apply_stack_preset "$STACK_PRESET"

# Preset Implementation (README P8 compliance)
service_enabled_by_preset() {
    local service="$1"
    case "${STACK_PRESET}" in
        minimal)  case "${service}" in
                    postgres|redis|litellm|ollama|openwebui|qdrant|caddy|mem0)
                        return 0 ;; *) return 1 ;; esac ;;
        standard) case "${service}" in
                    postgres|redis|litellm|ollama|openwebui|qdrant|caddy|mem0|\
                    librechat|openclaw|n8n|flowise)
                        return 0 ;; *) return 1 ;; esac ;;
        full)     return 0 ;;
        custom)   return 1 ;;
    esac
}
```

### **🧠 SECTION 4: MEMORY & CONTEXT PERSISTENCE**
```bash
section "4. Memory & Context Persistence"

prompt_default MEM0_ENABLED "Enable Mem0 memory service" "true"
if [[ "$MEM0_ENABLED" == "true" ]]; then
    prompt_default MEM0_PORT "Mem0 service port" "8001"
    validate_port_range "$MEM0_PORT" "Mem0"
    
    prompt_default MEMORY_RETENTION_DAYS "Memory retention days" "365"
    prompt_default MAX_CONTEXT_SIZE "Max context size (tokens)" "10000"
    
    log "Mem0 will provide per-tenant memory persistence"
fi
```

### **📡 SECTION 5: VECTOR DATABASE SELECTION**
```bash
section "5. Vector Database Selection"

prompt_default VECTOR_DB_TYPE "Choose vector database" "qdrant" "qdrant,weaviate,chroma"
case "$VECTOR_DB_TYPE" in
    "qdrant")
        QDRANT_ENABLED="true"
        WEAVIATE_ENABLED="false"
        CHROMA_ENABLED="false"
        log "Selected Qdrant as primary vector database"
        ;;
    "weaviate")
        QDRANT_ENABLED="false"
        WEAVIATE_ENABLED="true"
        CHROMA_ENABLED="false"
        log "Selected Weaviate as vector database"
        ;;
    "chroma")
        QDRANT_ENABLED="false"
        WEAVIATE_ENABLED="false"
        CHROMA_ENABLED="true"
        log "Selected Chroma as vector database"
        ;;
    *)
        fail "Invalid vector database choice: $VECTOR_DB_TYPE"
        ;;
esac
```

### **🌐 SECTION 6: NETWORK CONFIGURATION**
```bash
section "6. Network Configuration"

prompt_default DOCKER_NETWORK "Docker network name" "${PREFIX}${TENANT_ID}_net"
prompt_default DOCKER_SUBNET "Docker network subnet" "172.20.0.0/16"
prompt_default DOCKER_GATEWAY "Docker network gateway" "172.20.0.1"

# Set recommended MTU based on host MTU
if [[ "$HOST_MTU" -le 1500 ]]; then
    RECOMMENDED_MTU=$((HOST_MTU - 50))
else
    RECOMMENDED_MTU="1450"
fi

prompt_default DOCKER_MTU "Docker network MTU (recommended: $RECOMMENDED_MTU)" "$RECOMMENDED_MTU"
validate_port_range "$DOCKER_MTU" "Docker MTU"
```

### **🔌 SECTION 7: PORT CONFIGURATION**
```bash
section "7. Port Configuration"

# Infrastructure Services
if [[ "$POSTGRES_ENABLED" == "true" ]]; then
    prompt_default POSTGRES_PORT "PostgreSQL port" "5432"
    validate_port_range "$POSTGRES_PORT" "PostgreSQL"
fi

if [[ "$REDIS_ENABLED" == "true" ]]; then
    prompt_default REDIS_PORT "Redis port" "6379"
    validate_port_range "$REDIS_PORT" "Redis"
fi

# LLM Layer
if [[ "$LITELLM_ENABLED" == "true" ]]; then
    prompt_default LITELLM_PORT "LiteLLM port" "4000"
    validate_port_range "$LITELLM_PORT" "LiteLLM"
fi

if [[ "$BIFROST_ENABLED" == "true" ]]; then
    prompt_default BIFROST_PORT "Bifrost port" "8090"
    validate_port_range "$BIFROST_PORT" "Bifrost"
fi

if [[ "$OLLAMA_ENABLED" == "true" ]]; then
    prompt_default OLLAMA_PORT "Ollama port" "11434"
    validate_port_range "$OLLAMA_PORT" "Ollama"
fi

# Memory Layer
if [[ "$MEM0_ENABLED" == "true" ]]; then
    prompt_default MEM0_PORT "Mem0 port" "8001"
    validate_port_range "$MEM0_PORT" "Mem0"
fi

# Web UI Layer
if [[ "$OPENWEBUI_ENABLED" == "true" ]]; then
    prompt_default OPENWEBUI_PORT "Open WebUI port" "3000"
    validate_port_range "$OPENWEBUI_PORT" "Open WebUI"
fi

if [[ "$LIBRECHAT_ENABLED" == "true" ]]; then
    prompt_default LIBRECHAT_PORT "LibreChat port" "3080"
    validate_port_range "$LIBRECHAT_PORT" "LibreChat"
fi

if [[ "$OPENCLAW_ENABLED" == "true" ]]; then
    prompt_default OPENCLAW_PORT "OpenClaw port" "3001"
    validate_port_range "$OPENCLAW_PORT" "OpenClaw"
fi

# Vector Databases
if [[ "$QDRANT_ENABLED" == "true" ]]; then
    prompt_default QDRANT_PORT "Qdrant port" "6333"
    validate_port_range "$QDRANT_PORT" "Qdrant"
fi

if [[ "$WEAVIATE_ENABLED" == "true" ]]; then
    prompt_default WEAVIATE_PORT "Weaviate port" "8080"
    validate_port_range "$WEAVIATE_PORT" "Weaviate"
fi

if [[ "$CHROMA_ENABLED" == "true" ]]; then
    prompt_default CHROMA_PORT "Chroma port" "8000"
    validate_port_range "$CHROMA_PORT" "Chroma"
fi

# Automation Layer
if [[ "$N8N_ENABLED" == "true" ]]; then
    prompt_default N8N_PORT "N8N port" "5678"
    validate_port_range "$N8N_PORT" "N8N"
fi

if [[ "$FLOWISE_ENABLED" == "true" ]]; then
    prompt_default FLOWISE_PORT "Flowise port" "3030"
    validate_port_range "$FLOWISE_PORT" "Flowise"
fi

if [[ "$DIFY_ENABLED" == "true" ]]; then
    prompt_default DIFY_PORT "Dify port" "3040"
    validate_port_range "$DIFY_PORT" "Dify"
fi

# Identity Layer
if [[ "$AUTHENTIK_ENABLED" == "true" ]]; then
    prompt_default AUTHENTIK_PORT "Authentik port" "9000"
    validate_port_range "$AUTHENTIK_PORT" "Authentik"
fi

# Monitoring Layer
if [[ "$GRAFANA_ENABLED" == "true" ]]; then
    prompt_default GRAFANA_PORT "Grafana port" "3001"
    validate_port_range "$GRAFANA_PORT" "Grafana"
fi

if [[ "$PROMETHEUS_ENABLED" == "true" ]]; then
    prompt_default PROMETHEUS_PORT "Prometheus port" "9090"
    validate_port_range "$PROMETHEUS_PORT" "Prometheus"
fi

# Workflow Tools
if [[ "$SEARXNG_ENABLED" == "true" ]]; then
    prompt_default SEARXNG_PORT "SearXNG port" "8080"
    validate_port_range "$SEARXNG_PORT" "SearXNG"
fi

if [[ "$CODE_SERVER_ENABLED" == "true" ]]; then
    prompt_default CODE_SERVER_PASSWORD "Code Server password" ""
    prompt_default CODE_SERVER_PROXY_DOMAIN "Code Server proxy domain" ""
fi

if [[ "$CONTINUE_ENABLED" == "true" ]]; then
    prompt_secret CONTINUE_API_KEY "Continue.dev API key"
    prompt_default CONTINUE_LITELM_URL "Continue.dev LiteLLM URL" "http://litellm:4000"
    log "Continue.dev configured with LiteLLM integration"
fi

# Alerting Layer
if [[ "$SIGNALBOT_ENABLED" == "true" ]]; then
    prompt_default SIGNALBOT_PORT "Signalbot port" "8080"
    validate_port_range "$SIGNALBOT_PORT" "Signalbot"
fi

# Proxy Layer
if [[ "$NGINXPM_ENABLED" == "true" ]]; then
    prompt_default NGINXPM_PORT "Nginx Proxy Manager port" "81"
    validate_port_range "$NGINXPM_PORT" "Nginx Proxy Manager"
fi
```

### **🤖 SECTION 8: LLM CONFIGURATION**
```bash
section "8. LLM Configuration"

if [[ "$OLLAMA_ENABLED" == "true" ]]; then
    # GPU runtime configuration
    if [[ "$GPU_TYPE" == "nvidia" ]]; then
        OLLAMA_RUNTIME="nvidia"
        log "Auto-configured Ollama for NVIDIA GPU"
    elif [[ "$GPU_TYPE" == "amd" ]]; then
        OLLAMA_RUNTIME="amd"
        log "Auto-configured Ollama for AMD GPU"
    else
        OLLAMA_RUNTIME="cpu"
        log "Ollama will run on CPU"
    fi
    
    prompt_default OLLAMA_DEFAULT_MODEL "Default model to pull" "llama3.2"
    prompt_yesno OLLAMA_PULL_DEFAULT_MODEL "Pull default model after deployment?" "y"
fi
```

### **🔀 SECTION 9: LLM PROXY CONFIGURATION**
```bash
section "9. LLM Proxy Configuration"

if [[ "$LITELLM_ENABLED" == "true" ]]; then
    prompt_secret LITELLM_MASTER_KEY "LiteLLM master key"
    prompt_default LITELLM_DATABASE_URL "LiteLLM database URL" "postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/litellm"
    
    # External LLM providers
    prompt_yesno ENABLE_OPENAI "Enable OpenAI provider?" "n"
    if [[ "$ENABLE_OPENAI" == "true" ]]; then
        prompt_secret OPENAI_API_KEY "OpenAI API key"
        prompt_default OPENAI_API_BASE "OpenAI API base URL" "https://api.openai.com/v1"
        prompt_default OPENAI_API_VERSION "OpenAI API version" "2023-07-01-preview"
    fi
    
    prompt_yesno ENABLE_ANTHROPIC "Enable Anthropic provider?" "n"
    if [[ "$ENABLE_ANTHROPIC" == "true" ]]; then
        prompt_secret ANTHROPIC_API_KEY "Anthropic API key"
    fi
    
    prompt_yesno ENABLE_GOOGLE "Enable Google provider?" "n"
    if [[ "$ENABLE_GOOGLE" == "true" ]]; then
        prompt_secret GOOGLE_API_KEY "Google API key"
    fi
    
    prompt_yesno ENABLE_GROQ "Enable Groq provider?" "n"
    if [[ "$ENABLE_GROQ" == "true" ]]; then
        prompt_secret GROQ_API_KEY "Groq API key"
    fi
    
    prompt_yesno ENABLE_OPENROUTER "Enable OpenRouter provider?" "n"
    if [[ "$ENABLE_OPENROUTER" == "true" ]]; then
        prompt_secret OPENROUTER_API_KEY "OpenRouter API key"
    fi
fi

if [[ "$BIFROST_ENABLED" == "true" ]]; then
    prompt_secret BIFROST_API_KEY "Bifrost API key"
fi
```

### **🌐 SECTION 10: WEB UI CONFIGURATION**
```bash
section "10. Web UI Configuration"

if [[ "$OPENWEBUI_ENABLED" == "true" ]]; then
    # Open WebUI connects to LiteLLM, not directly to Ollama
    prompt_default OPENWEBUI_OLLAMA_API_BASE_URL "Open WebUI LLM API URL" "http://litellm:4000"
fi

if [[ "$LIBRECHAT_ENABLED" == "true" ]]; then
    prompt_secret LIBRECHAT_JWT_SECRET "LibreChat JWT secret"
    prompt_secret LIBRECHAT_CRYPT_KEY "LibreChat crypt key"
fi

if [[ "$OPENCLAW_ENABLED" == "true" ]]; then
    # OpenClaw configuration (minimal)
    log "OpenClaw will use default configuration"
fi
```

### **🧠 SECTION 11: MEMORY CONFIGURATION**
```bash
section "11. Memory Configuration"

if [[ "$MEM0_ENABLED" == "true" ]]; then
    prompt_secret MEM0_API_KEY "Mem0 API key"
    prompt_default MEM0_MAX_MEMORY "Max memory entries per user" "1000"
    prompt_default MEM0_CONTEXT_WINDOW "Context window size" "10000"
    prompt_default MEM0_RETENTION_POLICY "Retention policy" "lru" "lru,fifo,random"
    
    log "Mem0 configured with persistence and context management"
fi
```

### **📡 SECTION 12: VECTOR DATABASE CONFIGURATION**
```bash
section "12. Vector Database Configuration"

if [[ "$QDRANT_ENABLED" == "true" ]]; then
    prompt_secret QDRANT_API_KEY "Qdrant API key"
    log "Qdrant configured with API key protection"
fi

if [[ "$WEAVIATE_ENABLED" == "true" ]]; then
    log "Weaviate will use default configuration"
fi

if [[ "$CHROMA_ENABLED" == "true" ]]; then
    log "Chroma will use default configuration"
fi
```

### **🔧 SECTION 13: AUTOMATION CONFIGURATION**
```bash
section "13. Automation Configuration"

if [[ "$N8N_ENABLED" == "true" ]]; then
    prompt_default N8N_WEBHOOK_URL "N8N webhook URL" "https://${BASE_DOMAIN}/n8n"
fi

if [[ "$FLOWISE_ENABLED" == "true" ]]; then
    prompt_default FLOWISE_USERNAME "Flowise username" "admin"
    prompt_secret FLOWISE_PASSWORD "Flowise password"
fi

if [[ "$DIFY_ENABLED" == "true" ]]; then
    prompt_secret DIFY_INIT_PASSWORD "Dify initial password"
fi
```

### **🔐 SECTION 14: IDENTITY CONFIGURATION**
```bash
section "14. Identity Configuration"

if [[ "$AUTHENTIK_ENABLED" == "true" ]]; then
    prompt_secret AUTHENTIK_BOOTSTRAP_PASSWORD "Authentik bootstrap password"
    prompt_default AUTHENTIK_BOOTSTRAP_EMAIL "Authentik bootstrap email" "admin@${BASE_DOMAIN}"
fi
```

### **📊 SECTION 15: MONITORING CONFIGURATION**
```bash
section "15. Monitoring Configuration"

prompt_yesno ENABLE_MONITORING "Enable monitoring stack?" "n"
if [[ "$ENABLE_MONITORING" == "true" ]]; then
    prompt_yesno GRAFANA_ENABLED "Enable Grafana?" "y"
    prompt_yesno PROMETHEUS_ENABLED "Enable Prometheus?" "y"
fi
```

### **🛠️ SECTION 16: WORKFLOW TOOLS CONFIGURATION**
```bash
section "16. Workflow Tools Configuration"

prompt_yesno SEARXNG_ENABLED "Enable SearXNG search?" "n"
if [[ "$SEARXNG_ENABLED" == "true" ]]; then
    prompt_secret SEARXNG_SECRET_KEY "SearXNG secret key"
fi

prompt_yesno CODE_SERVER_ENABLED "Enable code server?" "n"
if [[ "$CODE_SERVER_ENABLED" == "true" ]]; then
    log "Code Server will use default configuration"
fi
```

### **📡 SECTION 17: ALERTING CONFIGURATION**
```bash
section "17. Alerting Configuration"

prompt_yesno SIGNALBOT_ENABLED "Enable Signal gateway?" "n"
if [[ "$SIGNALBOT_ENABLED" == "true" ]]; then
    prompt_required SIGNAL_PHONE_NUMBER "Signal phone number (E.164 format)"
    validate_e164 "$SIGNAL_PHONE_NUMBER"
    
    prompt_required SIGNAL_RECIPIENT "Signal recipient number (E.164 format)"
    validate_e164 "$SIGNAL_RECIPIENT"
fi
```

### **💾 SECTION 18: INGESTION PIPELINE CONFIGURATION**
```bash
section "18. Automated Ingestion Pipeline"

prompt_yesno ENABLE_INGESTION "Enable automated ingestion pipeline?" "n"
if [[ "$ENABLE_INGESTION" == "true" ]]; then
    prompt_default INGESTION_METHOD "Ingestion method" "rclone" "rclone,gdrive,s3,azure,local"
    prompt_default INGESTION_SCHEDULE "Ingestion schedule (cron)" "0 */6 * * *"
    prompt_default INGESTION_SOURCE "Ingestion source path" "/mnt/${TENANT_ID}/ingestion"
    
    case "$INGESTION_METHOD" in
        "rclone")
            prompt_default RCLONE_ENABLED "Enable Rclone sync service?" "y"
            if [[ "$RCLONE_ENABLED" == "true" ]]; then
                prompt_default RCLONE_REMOTE "Rclone remote name" "gdrive"
                prompt_default RCLONE_POLL_INTERVAL "Sync interval (minutes)" "5"
                prompt_default RCLONE_TRANSFERS "Parallel transfers" "4"
                prompt_default RCLONE_CHECKERS "Parallel checkers" "8"
                prompt_default RCLONE_VFS_CACHE "VFS cache mode" "writes" "writes,off,full"
            fi
            ;;
        "gdrive")
            prompt_default GDRIVE_CLIENT_ID "Google Drive Client ID" ""
            prompt_default GDRIVE_CLIENT_SECRET "Google Drive Client Secret" ""
            prompt_default GDRIVE_REFRESH_TOKEN "Google Drive Refresh Token" ""
            prompt_default GDRIVE_ROOT_ID "Google Drive Root Folder ID" ""
            ;;
        "s3")
            prompt_default AWS_S3_BUCKET "AWS S3 bucket" "ingestion-bucket"
            prompt_default AWS_S3_PREFIX "S3 prefix" "ingestion/"
            prompt_default AWS_S3_REGION "AWS region" "us-east-1"
            ;;
        "azure")
            prompt_default AZURE_STORAGE_ACCOUNT "Azure storage account" "ingestionaccount"
            prompt_default AZURE_CONTAINER "Azure container" "ingestion"
            ;;
        "local")
            prompt_default LOCAL_SOURCE "Local source path" "/mnt/${TENANT_ID}/local-ingestion"
            prompt_default LOCAL_WATCH "Watch for changes?" "y"
            ;;
    esac
    
    # Ingestion processing options
    prompt_default INGESTION_CHUNK_SIZE "Document chunk size" "1000"
    prompt_default INGESTION_CHUNK_OVERLAP "Chunk overlap" "200"
    prompt_default INGESTION_VECTOR_MODEL "Vectorization model" "all-MiniLM-L6-v2"
    prompt_default INGESTION_DEDUPLICATE "Deduplicate documents?" "y"
    prompt_default INGESTION_SUPPORTED_FORMATS "Supported formats" "pdf,txt,md,docx,csv"
fi
```

### **💾 SECTION 19: BACKUP CONFIGURATION**
```bash
section "19. Backup Configuration"

prompt_yesno ENABLE_BACKUP "Enable automated backups?" "n"
if [[ "$ENABLE_BACKUP" == "true" ]]; then
    prompt_default BACKUP_SCHEDULE "Backup schedule (cron format)" "0 2 * * *"
    prompt_default BACKUP_RETENTION "Backup retention days" "7"
    
    prompt_default BACKUP_PROVIDER "Backup provider" "local" "local,gdrive,s3,azure"
    case "$BACKUP_PROVIDER" in
        "gdrive")
            prompt_default RCLONE_GDRIVE_SA_CREDENTIALS_FILE "Google Drive service account JSON" "/mnt/${TENANT_ID}/config/gdrive-sa.json"
            ;;
        "s3")
            prompt_default AWS_S3_BUCKET "AWS S3 bucket name" ""
            prompt_default AWS_S3_REGION "AWS S3 region" "us-east-1"
            ;;
        "azure")
            prompt_default AZURE_STORAGE_ACCOUNT "Azure storage account" ""
            prompt_default AZURE_STORAGE_CONTAINER "Azure storage container" ""
            ;;
    esac
fi
```

---

## 📊 **COMPLETE SERVICE CATALOGUE**

### **Infrastructure Layer** (Always deployed)
| Service | Container name | Default port | Image | Description |
|---|---|---|---|---|
| PostgreSQL | `${TENANT_PREFIX}-postgres` | 5432 | `postgres:15-alpine` | Primary database |
| Redis | `${TENANT_PREFIX}-redis` | 6379 | `redis:7-alpine` | Cache & session store |

### **Memory Layer** (Per-tenant persistence)
| Service | Container name | Default port | Image | Description |
|---|---|---|---|---|
| Mem0 | `${TENANT_PREFIX}-mem0` | 8001 | `python:3.11-slim` | Memory context persistence |

### **LLM Layer** (AI capabilities)
| Service | Container name | Default port | Image | Description |
|---|---|---|---|---|
| LiteLLM | `${TENANT_PREFIX}-litellm` | 4000 | `ghcr.io/berriai/litellm:main-stable` | Unified LLM proxy |
| Ollama | `${TENANT_PREFIX}-ollama` | 11434 | `ollama/ollama:latest` | Local model inference |
| Bifrost | `${TENANT_PREFIX}-bifrost` | 8090 | `bifrost/bifrost:latest` | Alternative LLM gateway |

### **Web UI Layer** (User interfaces)
| Service | Container name | Default port | Image | Description |
|---|---|---|---|---|
| Open WebUI | `${TENANT_PREFIX}-openwebui` | 3000 | `ghcr.io/open-webui/open-webui:main` | Web chat interface |
| LibreChat | `${TENANT_PREFIX}-librechat` | 3080 | `ghcr.io/danny-avila/librechat:latest` | Multi-provider chat |
| OpenClaw | `${TENANT_PREFIX}-openclaw` | 3001 | `openclaw/openclaw:latest` | Chat interface |

### **Vector Database Layer** (RAG & search)
| Service | Container name | Default port | Image | Description |
|---|---|---|---|---|
| Qdrant | `${TENANT_PREFIX}-qdrant` | 6333 | `qdrant/qdrant:latest` | Vector similarity search |
| Weaviate | `${TENANT_PREFIX}-weaviate` | 8080 | `semitechnologies/weaviate:latest` | Alternative vector DB |
| Chroma | `${TENANT_PREFIX}-chroma` | 8000 | `chromadb/chroma:latest` | Alternative vector DB |

### **Automation Layer** (Workflow & integration)
| Service | Container name | Default port | Image | Description |
|---|---|---|---|---|
| N8N | `${TENANT_PREFIX}-n8n` | 5678 | `n8nio/n8n:latest` | Workflow automation |
| Flowise | `${TENANT_PREFIX}-flowise` | 3030 | `flowiseai/flowise:latest` | AI workflow builder |
| Dify | `${TENANT_PREFIX}-dify` | 3040 | `langgenius/dify-web:latest` | AI application platform |

### **Identity Layer** (Authentication)
| Service | Container name | Default port | Image | Description |
|---|---|---|---|---|
| Authentik | `${TENANT_PREFIX}-authentik` | 9000 | `ghcr.io/goauthentik/server:latest` | SSO & identity management |

### **Monitoring Layer** (Observability)
| Service | Container name | Default port | Image | Description |
|---|---|---|---|---|
| Grafana | `${TENANT_PREFIX}-grafana` | 3001 | `grafana/grafana:latest` | Metrics dashboard |
| Prometheus | `${TENANT_PREFIX}-prometheus` | 9090 | `prom/prometheus:latest` | Metrics collection |

### **Workflow Tools Layer** (Productivity)
| Service | Container name | Default port | Image | Description |
|---|---|---|---|---|
| SearXNG | `${TENANT_PREFIX}-searxng` | 8080 | `searxng/searxng:latest` | Privacy-focused search |
| Code Server | `${TENANT_PREFIX}-codeserver` | 8443 | `codercom/code-server:latest` | VS Code in browser |
| Continue.dev | `${TENANT_PREFIX}-continue` | 3000 | `continue/continue:latest` | AI-powered development |

### **Ingestion & Sync Layer** (Data pipeline)
| Service | Container name | Default port | Image | Description |
|---|---|---|---|---|
| Rclone | `${TENANT_PREFIX}-rclone` | N/A | `rclone/rclone:latest` | Cloud storage sync |

### **Alerting Layer** (Notifications)
| Service | Container name | Default port | Image | Description |
|---|---|---|---|---|
| Signalbot | `${TENANT_PREFIX}-signalbot` | 8080 | `bbernhard/signal-cli-rest-api:latest` | Signal notifications |

### **Proxy Layer** (SSL termination)
| Service | Container name | Ports | Image | Description |
|---|---|---|---|---|
| Caddy | `${TENANT_PREFIX}-caddy` | 80, 443 | `caddy:2-alpine` | Automatic SSL |
| Nginx PM | `${TENANT_PREFIX}-nginx` | 80, 443, 81 | `jc21/nginx-proxy-manager:latest` | Managed proxy |

---

## 📦 **STACK PRESETS**

| Service | `minimal` | `standard` | `full` | `custom` |
|---|---|---|---|---|
| **Infrastructure** | | | | | |
| PostgreSQL | ✅ | ✅ | ✅ | prompt |
| Redis | ✅ | ✅ | ✅ | prompt |
| **Memory Layer** | | | | | |
| Mem0 | ✅ | ✅ | ✅ | prompt |
| **LLM Layer** | | | | | |
| LiteLLM | ✅ | ✅ | ✅ | prompt |
| Ollama | ✅ | ✅ | ✅ | prompt |
| **Web UI Layer** | | | | | |
| Open WebUI | ✅ | ✅ | ✅ | prompt |
| LibreChat | ❌ | ✅ | ✅ | prompt |
| OpenClaw | ❌ | ✅ | ✅ | prompt |
| **Vector Databases** | | | | | |
| Qdrant | ✅ | ✅ | ✅ | prompt |
| Weaviate | ❌ | ❌ | ✅ | prompt |
| Chroma | ❌ | ❌ | ✅ | prompt |
| **Automation** | | | | | |
| N8N | ❌ | ✅ | ✅ | prompt |
| Flowise | ❌ | ✅ | ✅ | prompt |
| Dify | ❌ | ❌ | ✅ | prompt |
| **Identity** | | | | | |
| Authentik | ❌ | ❌ | ✅ | prompt |
| **Monitoring** | | | | | |
| Grafana | ❌ | ❌ | ✅ | prompt |
| Prometheus | ❌ | ❌ | ✅ | prompt |
| **Workflow Tools** | | | | | |
| SearXNG | ❌ | ❌ | ✅ | prompt |
| Code Server | ❌ | ❌ | ✅ | prompt |
| Continue.dev | ❌ | ❌ | ✅ | prompt |
| **Ingestion & Sync** | | | | | |
| Rclone | ❌ | ❌ | ✅ | prompt |
| **Alerting** | | | | | |
| Signalbot | ❌ | ❌ | ✅ | prompt |
| **Proxy** | | | | | |
| Caddy | ✅ | ✅ | ✅ | prompt |
| Nginx PM | ❌ | ❌ | ✅ | prompt |

---

## 📁 **DIRECTORY STRUCTURE**

```
/mnt/${TENANT_ID}/                  ← EBS mount point (or fallback: ~/ai-platform/${TENANT_ID})
├── platform.conf                   ← THE source of truth (chmod 600)
├── .configured/                    ← Idempotency marker files
│   ├── compose_generated
│   ├── postgres_init
│   ├── authentik_bootstrap
│   ├── mem0_configured
│   └── ...
├── logs/                           ← Script execution logs (timestamped)
├── config/                         ← All generated config files
│   ├── docker-compose.yml          ← Generated by script 2
│   ├── caddy/
│   │   └── Caddyfile               ← Generated by script 2
│   ├── nginx/
│   │   └── nginx.conf              ← Generated by script 2 (if NPM selected)
│   ├── litellm/
│   │   └── config.yaml             ← Generated by script 2
│   ├── bifrost/
│   │   └── config.yaml             ← Generated by script 2
│   ├── mem0/
│   │   └── config.yaml             ← Generated by script 2
│   └── ingestion/
│       ├── rclone.conf             ← Rclone configuration
│       └── pipeline.yaml           ← Ingestion pipeline config
└── data/                           ← All persistent container data (bind mounts)
    ├── postgres/
    ├── redis/
    ├── ollama/
    ├── qdrant/
    ├── weaviate/
    ├── chroma/
    ├── litellm/
    ├── bifrost/
    ├── mem0/
    │   └── .mem0/               ← Memory persistence
    ├── openwebui/
    ├── librechat/
    ├── openclaw/
    ├── n8n/
    ├── flowise/
    ├── dify/
    ├── authentik/
    ├── grafana/
    ├── prometheus/
    ├── searxng/
    ├── codeserver/
    ├── signalbot/
    └── ingestion/                   ← Automated ingestion data
    ├── rclone/               ← Rclone sync cache
    ├── gdrive/              ← Google Drive synced files
    ├── s3/                  ← S3 downloaded files
    ├── azure/               ← Azure blob files
    └── processed/           ← Processed documents
```

---

## 🔄 **AUTOMATED INGESTION PIPELINE**

### **Pipeline Types**

#### **Rclone Service Ingestion**
```yaml
# config/ingestion/pipeline.yaml
ingestion:
  type: rclone_service
  enabled: true
  remote: "gdrive"
  sync_interval: "5m"
  transfers: 4
  checkers: 8
  vfs_cache_mode: "writes"
  schedule: "0 */6 * * *"
  retention_days: 30
  transformations:
    - type: vectorize
      model: "all-MiniLM-L6-v2"
      target: "qdrant"
    - type: chunk
      size: 1000
      overlap: 200
    - type: deduplicate
      method: "hash"
```

#### **Google Drive Direct Ingestion**
```yaml
ingestion:
  type: gdrive
  client_id: "${GDRIVE_CLIENT_ID}"
  client_secret: "${GDRIVE_CLIENT_SECRET}"
  refresh_token: "${GDRIVE_REFRESH_TOKEN}"
  root_id: "${GDRIVE_ROOT_ID}"
  schedule: "0 */6 * * *"
  transformations:
    - type: extract
      formats: ["pdf", "docx", "txt", "md", "csv"]
    - type: vectorize
      model: "text-embedding-ada-002"
      target: "qdrant"
```

#### **Cloud Storage Ingestion**
```yaml
ingestion:
  type: aws_s3
  bucket: "ingestion-bucket"
  prefix: "documents/"
  region: "us-east-1"
  schedule: "0 */6 * * *"
  transformations:
    - type: extract
      formats: ["pdf", "docx", "txt"]
    - type: vectorize
      model: "text-embedding-ada-002"
      target: "qdrant"
```

#### **Local File Ingestion**
```yaml
ingestion:
  type: local
  source: "/mnt/${TENANT_ID}/local-ingestion"
  schedule: "*/5 * * * *"
  watch: true
  transformations:
    - type: vectorize
      model: "all-MiniLM-L6-v2"
      target: "qdrant"
    - type: deduplicate
      method: "hash"
```

### **Integration with Memory Layer**
```yaml
memory_integration:
  enabled: true
  service: "mem0"
  config:
    api_endpoint: "http://mem0:8001"
    api_key: "${MEM0_API_KEY}"
    context_window: 10000
    retention_days: 365
  ingestion_mapping:
    document_id: "memory_id"
    content: "data"
    metadata: "tags"
```

---

## 🔧 **TEMPLATED DEPLOYMENT**

### **Template File Structure**
```bash
# Location: /mnt/${TENANT_ID}/config/template.conf
# Usage: ./scripts/1-setup-system.sh --template template.conf

# =============================================================================
# AI Platform Template Configuration
# Template Version: 1.0.0
# =============================================================================

# ── SECTION 1: TENANT CONFIGURATION ────────────────────────────────────────
TENANT_ID="datasquiz"
PREFIX="ai"
BASE_DOMAIN="datasquiz.example.com"
TLS_MODE="letsencrypt"
PROXY_EMAIL="admin@datasquiz.example.com"

# ── SECTION 2: LLM PROXY ARCHITECTURE ────────────────────────────────────────
LLM_PROXY_TYPE="litellm"  # litellm or bifrost

# ── SECTION 3: STACK PRESET ─────────────────────────────────────────────────
STACK_PRESET="full"  # minimal, standard, full, custom

# ── SECTION 4: MEMORY LAYER ──────────────────────────────────────────────────
MEM0_ENABLED="true"
MEM0_PORT="8001"
MEM0_API_KEY="\${MEM0_API_KEY:-}"
MEMORY_RETENTION_DAYS="365"
MAX_CONTEXT_SIZE="10000"

# ── SECTION 5: VECTOR DATABASE SELECTION ────────────────────────────────────
VECTOR_DB_TYPE="qdrant"  # qdrant, weaviate, chroma

# ── SECTION 6: NETWORK CONFIGURATION ────────────────────────────────────────
DOCKER_NETWORK="datasquiz_network"
DOCKER_SUBNET="172.20.0.0/16"
DOCKER_GATEWAY="172.20.0.1"
DOCKER_MTU="1450"

# ── SECTION 7: INFRASTRUCTURE SERVICES ────────────────────────────────────────
POSTGRES_ENABLED="true"
POSTGRES_PORT="5432"
POSTGRES_USER="platform"
POSTGRES_PASSWORD="\${POSTGRES_PASSWORD:-}"
POSTGRES_DB="platform"

REDIS_ENABLED="true"
REDIS_PORT="6379"
REDIS_PASSWORD="\${REDIS_PASSWORD:-}"

# ── SECTION 8: DEVELOPMENT STACK ──────────────────────────────────────────────────
CODE_SERVER_ENABLED="true"
CODE_SERVER_PORT="8443"
CODE_SERVER_PASSWORD="\${CODE_SERVER_PASSWORD:-}"
CODE_SERVER_PROXY_DOMAIN=""

CONTINUE_ENABLED="true"
CONTINUE_PORT="3000"
CONTINUE_API_KEY="\${CONTINUE_API_KEY:-}"
CONTINUE_LITELM_URL="http://litellm:4000"

# ── SECTION 9: LLM LAYER ───────────────────────────────────────────────────────
OLLAMA_ENABLED="true"
OLLAMA_PORT="11434"
OLLAMA_DEFAULT_MODEL="llama3.2"
OLLAMA_RUNTIME="cpu"
OLLAMA_PULL_DEFAULT_MODEL="true"

# LiteLLM Configuration
LITELLM_ENABLED="true"
LITELLM_PORT="4000"
LITELLM_MASTER_KEY="\${LITELLM_MASTER_KEY:-}"
LITELLM_DATABASE_URL="postgresql://platform:\${POSTGRES_PASSWORD:-}@postgres:5432/litellm"

# Provider Enablement
ENABLE_OPENAI="true"
ENABLE_ANTHROPIC="true"
ENABLE_GOOGLE="false"
ENABLE_GROQ="true"
ENABLE_OPENROUTER="false"

# Provider API Keys
OPENAI_API_KEY="\${OPENAI_API_KEY:-}"
ANTHROPIC_API_KEY="\${ANTHROPIC_API_KEY:-}"
GOOGLE_API_KEY="\${GOOGLE_API_KEY:-}"
GROQ_API_KEY="\${GROQ_API_KEY:-}"
OPENROUTER_API_KEY="\${OPENROUTER_API_KEY:-}"

# ── SECTION 9: INGESTION PIPELINE ────────────────────────────────────────────
ENABLE_INGESTION="true"
INGESTION_METHOD="rclone"
INGESTION_SCHEDULE="0 */6 * * *"
INGESTION_SOURCE="/mnt/datasquiz/ingestion"

# Rclone Service Configuration
RCLONE_ENABLED="true"
RCLONE_REMOTE="gdrive"
RCLONE_POLL_INTERVAL="5"
RCLONE_TRANSFERS="4"
RCLONE_CHECKERS="8"
RCLONE_VFS_CACHE="writes"

# Google Drive Direct Configuration (alternative)
GDRIVE_CLIENT_ID="\${GDRIVE_CLIENT_ID:-}"
GDRIVE_CLIENT_SECRET="\${GDRIVE_CLIENT_SECRET:-}"
GDRIVE_REFRESH_TOKEN="\${GDRIVE_REFRESH_TOKEN:-}"
GDRIVE_ROOT_ID="\${GDRIVE_ROOT_ID:-}"

# Ingestion Processing
INGESTION_CHUNK_SIZE="1000"
INGESTION_CHUNK_OVERLAP="200"
INGESTION_VECTOR_MODEL="all-MiniLM-L6-v2"
INGESTION_DEDUPLICATE="true"
INGESTION_SUPPORTED_FORMATS="pdf,txt,md,docx,csv"

# ── SECTION 10: MONITORING ───────────────────────────────────────────────────
ENABLE_MONITORING="true"
GRAFANA_ENABLED="true"
PROMETHEUS_ENABLED="true"

# ... (complete template continues for all 22 services)
```

### **Environment Variable Support**
```bash
# Secure deployment with environment variables
POSTGRES_PASSWORD="secure123" \
OPENAI_API_KEY="sk-proj-..." \
MEM0_API_KEY="mem0-key-..." \
./scripts/1-setup-system.sh --template prod-template.conf
```

---

## 🏗️ **CORE PRINCIPLES**

### **P1 — `platform.conf` is the one and only source of truth**
- Script 1 writes it
- Scripts 0, 2, 3 source it
- Never edited by scripts 0, 2, 3
- Never regenerated

### **P2 — Script boundaries are strict**
- No cross-script calls
- Each script has atomic responsibility
- Clear input/output contracts

### **P3 — Explicit heredoc blocks for compose generation**
- No templating engines
- No `.env` files
- All configuration inline

### **P4 — No `.env` files**
- Secrets passed inline in `environment:` blocks
- No `envsubst` on generated files

### **P5 — Ports bind to `127.0.0.1` only**
- Except reverse proxy (80/443)
- All internal services localhost-only

### **P6 — Non-root execution everywhere**
- Scripts run as non-root
- `sudo` only where necessary
- User in docker group

### **P7 — Idempotency via marker files**
- `${CONFIGURED_DIR}/service_name` markers
- Skip if already configured
- Clear markers in cleanup script

### **P8 — `set -euo pipefail` everywhere**
- Exit on error
- Exit on unset variables
- Pipe failures detected

### **P9 — Bind mounts only**
- No named Docker volumes
- All persistent data uses bind mounts
- `/mnt/${TENANT_ID}/data/` structure

### **P10 — Dual logging**
- Timestamped log files
- Simultaneous stdout output
- `${LOG_DIR}/script-name-timestamp.log`

### **P11 — No `/opt` usage**
- EBS mount: `/mnt/${TENANT_ID}/`
- Fallback: `~/ai-platform/${TENANT_ID}/`
- Never system directories

---

## 🎯 **DEPLOYMENT OUTCOMES**

### **✅ Minimal Stack**
- Core LLM capabilities
- Basic web interface
- Vector database
- Memory persistence
- **Resource usage**: ~4GB RAM, ~20GB disk

### **✅ Standard Stack**
- Multiple web interfaces
- Workflow automation
- Advanced monitoring
- Rclone sync service
- **Resource usage**: ~8GB RAM, ~50GB disk

### **✅ Full Stack**
- Complete AI platform
- All integrations
- Enterprise monitoring
- Full automation
- Complete ingestion pipeline
- **Resource usage**: ~16GB RAM, ~100GB disk

### **🔄 Automated Ingestion**
- Continuous document processing
- Vector database population
- Memory context enrichment
- Multi-source support:
  - **Rclone Service**: Continuous cloud sync
  - **Google Drive**: Direct API integration
  - **AWS S3**: Cloud storage ingestion
  - **Azure Blob**: Microsoft cloud storage
  - **Local Files**: File system watching

---

## 📚 **TEMPLATES & EXAMPLES**

### **Production Template**
```bash
# Create production template
cat > /tmp/prod-template.conf << 'EOF'
TENANT_ID="production"
BASE_DOMAIN="ai.company.com"
LLM_PROXY_TYPE="litellm"
STACK_PRESET="full"
VECTOR_DB_TYPE="qdrant"
MEM0_ENABLED="true"
ENABLE_BACKUP="true"
BACKUP_PROVIDER="s3"
AWS_S3_BUCKET="company-ai-backups"
ENABLE_INGESTION="true"
INGESTION_TYPE="aws_s3"
AWS_S3_BUCKET="company-documents"
EOF

# Deploy
./scripts/1-setup-system.sh --template /tmp/prod-template.conf
```

### **Development Template**
```bash
# Create development template
cat > /tmp/dev-template.conf << 'EOF'
TENANT_ID="dev"
BASE_DOMAIN="dev.local"
LLM_PROXY_TYPE="litellm"
STACK_PRESET="minimal"
VECTOR_DB_TYPE="qdrant"
MEM0_ENABLED="true"
TLS_MODE="selfsigned"
ENABLE_BACKUP="false"
ENABLE_INGESTION="false"
EOF

# Deploy
./scripts/1-setup-system.sh --template /tmp/dev-template.conf
```

---

## 🔒 **SECURITY CONSIDERATIONS**

### **Credential Management**
- Use environment variables for sensitive data
- Template files with 600 permissions
- No hardcoded secrets in scripts

### **Network Security**
- All services in isolated Docker network
- Only proxy exposed to internet
- Internal services localhost-only

### **Data Protection**
- Bind mounts with proper permissions
- User:1000:1000 for containers
- Encrypted backups for cloud storage

---

## 📞 **TROUBLESHOOTING**

### **Common Issues**
1. **Permission denied** - User not in docker group
2. **Port conflicts** - Services already running
3. **Memory errors** - Insufficient RAM for models
4. **Disk space** - Not enough space for models/data

### **Debug Mode**
```bash
# Enable verbose logging
DEBUG=true ./scripts/1-setup-system.sh

# Dry run mode
./scripts/1-setup-system.sh --template template.conf --dry-run
```

---

## 🎉 **CONCLUSION**

This AI Platform Automation provides:
- **25 services** across 11 functional layers
- **Complete memory persistence** with Mem0 integration
- **Automated ingestion pipeline** for continuous data processing
- **Development stack** with Code Server and Continue.dev
- **Templated deployment** for production environments
- **Strict framework compliance** with zero manual configuration
- **Enterprise-grade monitoring** and observability
- **Full Docker compliance** with official images

**Result**: A fully operational, self-contained AI platform that scales from development to production deployments while maintaining simplicity and reliability over complexity.

---

*Version: 2.1.0 | Last Updated: 2026-04-02 | Total Variables: 95*
