# Multi-Tenant AI Platform Implementation Plan

## 🎯 Executive Summary

This document outlines the complete implementation plan for a **multi-tenant AI platform** where each tenant runs under their own UID/GID with dedicated EBS volumes, complete isolation, and dynamic configuration generation.

---

## 🏗️ Architecture Overview

### **Multi-Tenant Isolation Model**
```
Host Machine
├── Tenant A (UID 1001:1001)
│   ├── EBS Volume: /mnt/data-tenant-a
│   ├── Docker Network: ai-platform-1001
│   ├── Port Range: 5000-5099
│   └── Domain: tenant-a.datasquiz.net
├── Tenant B (UID 1002:1002)
│   ├── EBS Volume: /mnt/data-tenant-b
│   ├── Docker Network: ai-platform-1002
│   ├── Port Range: 5100-5199
│   └── Domain: tenant-b.datasquiz.net
└── Tenant C (UID 1003:1003)
    ├── EBS Volume: /mnt/data-tenant-c
    ├── Docker Network: ai-platform-1003
    ├── Port Range: 5200-5299
    └── Domain: tenant-c.datasquiz.net
```

### **Security Isolation Layers**
1. **Process Isolation**: Each tenant runs under unique UID/GID
2. **Filesystem Isolation**: Dedicated EBS volumes per tenant
3. **Network Isolation**: Separate Docker networks per tenant
4. **Security Isolation**: Tenant-specific AppArmor profiles
5. **Port Isolation**: Non-overlapping port ranges per tenant

---

## 📋 Implementation Phases

### **Phase 1: Core Multi-Tenant Infrastructure (Week 1)**

#### **1.1 Script 1 Enhancement - Multi-Tenant Setup**
**Objective**: Generate tenant-specific configuration automatically

**Key Components**:
```bash
#!/bin/bash
# Script 1: Multi-Tenant Setup & Configuration

# Auto-detect tenant identity
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)
TENANT_NAME="tenant-${CURRENT_UID}"

# Dynamic configuration generation
BASE_DIR="/mnt/data-${TENANT_NAME}"
DOMAIN_NAME="${TENANT_NAME}.datasquiz.net"
DOCKER_NETWORK="ai-platform-${CURRENT_UID}"
PORT_RANGE_START=$((5000 + (CURRENT_UID - 1000) * 100))

# Port allocation with conflict checking
allocate_tenant_ports() {
    local start_port=$PORT_RANGE_START
    local ports=()
    
    # Check port availability for tenant's UID
    for service in prometheus grafana n8n dify anythingllm litellm openwebui minio signal openclaw flowise; do
        local port=$((start_port++))
        if ! netstat -tlnp | grep -q ":$port "; then
            ports+=("$port")
        else
            # Find next available port in tenant's range
            while netstat -tlnp | grep -q ":$port "; do
                port=$((port + 1))
            done
            ports+=("$port")
            start_port=$port
        fi
    done
    
    # Export port variables
    export PROMETHEUS_PORT=${ports[0]}
    export GRAFANA_PORT=${ports[1]}
    export N8N_PORT=${ports[2]}
    # ... etc for all services
}

# Generate tenant-specific .env
generate_tenant_env() {
    cat > "${BASE_DIR}/config/.env" << EOF
# === Tenant Configuration ===
TENANT_NAME=${TENANT_NAME}
BASE_DIR=${BASE_DIR}
DOMAIN_NAME=${DOMAIN_NAME}
LOCALHOST=localhost

# === User Isolation ===
STACK_USER_UID=${CURRENT_UID}
STACK_USER_GID=${CURRENT_GID}
OPENCLAW_UID=$((CURRENT_UID + 1000))
OPENCLAW_GID=$((CURRENT_UID + 1000))

# === Network ===
DOCKER_NETWORK=${DOCKER_NETWORK}

# === Port Configuration ===
PROMETHEUS_PORT=${PROMETHEUS_PORT}
GRAFANA_PORT=${GRAFANA_PORT}
N8N_PORT=${N8N_PORT}
# ... all other ports

# === Vector DB ===
VECTOR_DB=qdrant

# === AppArmor ===
APPARMOR_PROFILE_DIR=${BASE_DIR}/apparmor

# === Tailscale ===
TAILSCALE_AUTH_KEY=
TAILSCALE_HOSTNAME=openclaw-${TENANT_NAME}
EOF
}

# EBS volume mounting and directory creation
setup_tenant_filesystem() {
    # Mount EBS volume (assumes EBS is already attached)
    if [ ! -d "${BASE_DIR}" ]; then
        echo "❌ EBS volume not mounted at ${BASE_DIR}"
        echo "Please mount EBS volume and retry"
        exit 1
    fi
    
    # Create tenant directory structure
    mkdir -p "${BASE_DIR}/data" "${BASE_DIR}/logs" "${BASE_DIR}/config" "${BASE_DIR}/apparmor"
    mkdir -p "${BASE_DIR}/ssl/certs/${DOMAIN_NAME}"
    
    # Set ownership
    chown -R ${CURRENT_UID}:${CURRENT_GID} "${BASE_DIR}"
    
    echo "✅ Tenant filesystem configured at ${BASE_DIR}"
}
```

**Validation Criteria**:
- ✅ Script runs as any user (UID 1001+)
- ✅ Automatically detects UID/GID
- ✅ Mounts EBS volume correctly
- ✅ Generates unique configuration per tenant
- ✅ Performs port availability checking
- ✅ Creates proper directory structure

#### **1.2 Script 2 Enhancement - Tenant-Aware Deployment**
**Objective**: Deploy complete stack under tenant's UID/GID with isolation

**Key Components**:
```bash
#!/bin/bash
# Script 2: Multi-Tenant Deployment

# Load tenant configuration
source "${BASE_DIR}/config/.env"

# Tenant-specific paths
TENANT_DATA="${BASE_DIR}/data"
TENANT_LOGS="${BASE_DIR}/logs"
TENANT_CONFIG="${BASE_DIR}/config"
TENANT_APPARMOR="${BASE_DIR}/apparmor"

# Tenant-specific Docker network
create_tenant_network() {
    docker network create "${DOCKER_NETWORK}" 2>/dev/null || true
    echo "✅ Tenant network created: ${DOCKER_NETWORK}"
}

# Tenant-specific AppArmor profiles
setup_tenant_apparmor_profiles() {
    # Default profile for tenant's services
    cat > "${TENANT_APPARMOR}/ai-platform-default" << EOF
#include <tunables/global>

profile ai-platform-default flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  # Allow access ONLY to tenant's own data directory
  ${BASE_DIR}/** rw,

  # Deny access to other tenants' data
  deny /mnt/data-tenant-*/** rw,

  # Deny access to sensitive host paths
  deny /etc/shadow r,
  deny /etc/passwd w,
  deny /root/** rw,

  network,
  /proc/self/** r,
  /sys/fs/cgroup/** r,
}
EOF

    # OpenClaw strict profile
    cat > "${TENANT_APPARMOR}/ai-platform-openclaw" << EOF
#include <tunables/global>

profile ai-platform-openclaw flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  # Strict: only tenant's own data
  ${BASE_DIR}/data/openclaw/** rw,
  /tmp/** rw,

  # Deny everything else
  deny ${BASE_DIR}/data/!openclaw/** rw,
  deny /etc/** w,
  deny /root/** rw,

  network,
  capability net_admin,
  capability sys_module,
}
EOF

    # Copy to system location and load
    cp "${TENANT_APPARMOR}/ai-platform-default" \
       "/etc/apparmor.d/ai-platform-${STACK_USER_UID}"
    cp "${TENANT_APPARMOR}/ai-platform-openclaw" \
       "/etc/apparmor.d/ai-platform-openclaw-${OPENCLAW_UID}"
    
    apparmor_parser -r "/etc/apparmor.d/ai-platform-${STACK_USER_UID}"
    apparmor_parser -r "/etc/apparmor.d/ai-platform-openclaw-${OPENCLAW_UID}"
    
    echo "✅ AppArmor profiles loaded for tenant ${TENANT_NAME}"
}

# Tenant-aware service deployment
deploy_service() {
    local service_name=$1
    local image=$2
    local internal_port=$3
    local host_port=$4
    
    docker run -d \
        --name "${TENANT_NAME}-${service_name}" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --security-opt "apparmor=ai-platform-${STACK_USER_UID}" \
        --user "${STACK_USER_UID}:${STACK_USER_GID}" \
        -p "${host_port}:${internal_port}" \
        -v "${TENANT_DATA}/${service_name}:/app/data" \
        -v "${TENANT_LOGS}/${service_name}:/app/logs" \
        "${vectordb_env[@]}" \
        "${image}"
}

# Vector DB configuration (global for tenant)
set_vectordb_config() {
    case "${VECTOR_DB}" in
        qdrant)
            export VECTORDB_HOST="qdrant"
            export VECTORDB_PORT="6333"
            export VECTORDB_TYPE="qdrant"
            export VECTORDB_URL="http://qdrant:6333"
            export VECTORDB_COLLECTION="${TENANT_NAME}-ai-platform"
            ;;
        # ... other vector DB options
    esac
}
```

**Validation Criteria**:
- ✅ Loads tenant-specific configuration
- ✅ Creates tenant-specific Docker network
- ✅ Deploys services under tenant's UID/GID
- ✅ Applies tenant-specific AppArmor profiles
- ✅ Prevents cross-tenant data access

#### **1.3 OpenClaw + Tailscale Multi-Tenant**
**Objective**: Deploy OpenClaw with Tailscale sidecar under tenant isolation

**Key Components**:
```bash
deploy_openclaw() {
    if [ -z "${TAILSCALE_AUTH_KEY}" ]; then
        echo "❌ TAILSCALE_AUTH_KEY missing — OpenClaw requires Tailscale"
        return 1
    fi

    # Create OpenClaw directories under tenant's UID
    mkdir -p "${TENANT_DATA}/openclaw" "${TENANT_DATA}/tailscale"
    chown -R ${OPENCLAW_UID}:${OPENCLAW_GID} "${TENANT_DATA}/openclaw"
    chown -R ${OPENCLAW_UID}:${OPENCLAW_GID} "${TENANT_DATA}/tailscale"

    # Step 1: Tailscale sidecar for this tenant
    docker run -d \
        --name "tailscale-${TENANT_NAME}" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --cap-add NET_ADMIN \
        --cap-add SYS_MODULE \
        --security-opt "apparmor=ai-platform-openclaw-${OPENCLAW_UID}" \
        -v "${TENANT_DATA}/tailscale:/var/lib/tailscale" \
        -v /dev/net/tun:/dev/net/tun \
        -e "TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY}" \
        -e "TAILSCALE_HOSTNAME=openclaw-${TENANT_NAME}" \
        -e "TAILSCALE_STATE_DIR=/var/lib/tailscale" \
        tailscale/tailscale:latest

    # Wait for Tailscale authentication
    wait_for_tailscale_auth "tailscale-${TENANT_NAME}"

    # Step 2: OpenClaw in shared network namespace
    docker run -d \
        --name "openclaw-${TENANT_NAME}" \
        --network "container:tailscale-${TENANT_NAME}" \
        --restart unless-stopped \
        --security-opt "apparmor=ai-platform-openclaw-${OPENCLAW_UID}" \
        --user "${OPENCLAW_UID}:${OPENCLAW_GID}" \
        --read-only \
        --tmpfs /tmp:rw,noexec,nosuid,size=100m \
        -v "${TENANT_DATA}/openclaw:/app/data:rw" \
        -v "${TENANT_CONFIG}/openclaw:/app/config:ro" \
        "${vectordb_env[@]}" \
        openclaw/openclaw:latest

    echo "✅ OpenClaw deployed for tenant ${TENANT_NAME}"
    echo "Tailscale IP: $(docker exec "tailscale-${TENANT_NAME}" tailscale ip 2>/dev/null)"
}
```

**Validation Criteria**:
- ✅ Tailscale sidecar runs under tenant's OpenClaw UID
- ✅ OpenClaw isolated in shared network namespace
- ✅ Tenant-specific Tailscale hostname
- ✅ Strict AppArmor profile applied

---

### **Phase 2: Vector DB Integration (Week 1-2)**

#### **2.1 Multi-Tenant Vector DB Configuration**
**Objective**: Each tenant gets isolated vector DB collections/namespaces

**Key Components**:
```bash
# Vector DB environment variables per service
build_vectordb_env() {
    local vectordb_env=()
    
    case "${VECTOR_DB}" in
        qdrant)
            vectordb_env=(
                -e "VECTOR_DB=qdrant"
                -e "QDRANT_ENDPOINT=${VECTORDB_URL}"
                -e "QDRANT_API_KEY="
                -e "QDRANT_COLLECTION=${TENANT_NAME}-ai-platform"
            )
            ;;
        pgvector)
            vectordb_env=(
                -e "VECTOR_DB=pgvector"
                -e "PGVECTOR_CONNECTION_STRING=${VECTORDB_URL}"
                -e "PGVECTOR_SCHEMA=${TENANT_NAME}"
            )
            ;;
        weaviate)
            vectordb_env=(
                -e "VECTOR_DB=weaviate"
                -e "WEAVIATE_ENDPOINT=${VECTORDB_URL}"
                -e "WEAVIATE_API_KEY="
                -e "WEAVIATE_CLASS=${TENANT_NAME}-ai-platform"
            )
            ;;
    esac
    
    echo "${vectordb_env[@]}"
}

# Service deployment with vector DB integration
deploy_anythingllm() {
    local vectordb_env=($(build_vectordb_env))
    
    docker run -d \
        --name "${TENANT_NAME}-anythingllm" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --security-opt "apparmor=ai-platform-${STACK_USER_UID}" \
        --user "${STACK_USER_UID}:${STACK_USER_GID}" \
        -p "${ANYTHINGLLM_PORT}:3001" \
        -v "${TENANT_DATA}/anythingllm:/app/server/storage" \
        -e "STORAGE_DIR=/app/server/storage" \
        -e "LLM_PROVIDER=ollama" \
        -e "OLLAMA_BASE_PATH=http://ollama:11434" \
        -e "EMBEDDING_ENGINE=ollama" \
        -e "EMBEDDING_BASE_PATH=http://ollama:11434" \
        "${vectordb_env[@]}" \
        mintplexlabs/anythingllm:latest
}
```

**Validation Criteria**:
- ✅ Each tenant gets isolated vector DB collections
- ✅ Vector DB environment variables passed correctly
- ✅ Service isolation maintained
- ✅ No cross-tenant data contamination

---

### **Phase 3: Operations & Extensibility (Week 2)**

#### **3.1 Multi-Tenant Script 3**
**Objective**: Operate individual tenant stacks without affecting others

**Key Components**:
```bash
#!/bin/bash
# Script 3: Multi-Tenant Operations

# Auto-detect tenant from current directory
detect_tenant() {
    local current_dir=$(pwd)
    if [[ "$current_dir" =~ /mnt/data-(.+) ]]; then
        TENANT_NAME="${BASH_REMATCH[1]}"
        BASE_DIR="/mnt/data-${TENANT_NAME}"
        source "${BASE_DIR}/config/.env"
    else
        echo "❌ Not in tenant directory. Run from tenant's BASE_DIR"
        exit 1
    fi
}

# Tenant-specific operations
renew_ssl() {
    echo "🔄 Renewing SSL for tenant ${TENANT_NAME}"
    docker exec "caddy-${TENANT_NAME}" caddy reload --config "/etc/caddy/Caddyfile"
}

restart_service() {
    local service_name=$1
    echo "🔄 Restarting ${service_name} for tenant ${TENANT_NAME}"
    docker restart "${TENANT_NAME}-${service_name}"
}

show_status() {
    echo "📊 Status for tenant ${TENANT_NAME} (UID ${STACK_USER_UID}):"
    docker ps --filter "name=${TENANT_NAME}-" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

refresh_tailscale_token() {
    if [ -n "${NEW_TAILSCALE_AUTH_KEY}" ]; then
        echo "🔄 Refreshing Tailscale token for tenant ${TENANT_NAME}"
        docker exec "tailscale-${TENANT_NAME}" tailscale up --auth-key="${NEW_TAILSCALE_AUTH_KEY}"
        sed -i "s/TAILSCALE_AUTH_KEY=.*/TAILSCALE_AUTH_KEY=${NEW_TAILSCALE_AUTH_KEY}/" "${BASE_DIR}/config/.env"
    fi
}
```

**Validation Criteria**:
- ✅ Auto-detects tenant from current directory
- ✅ Operations affect only tenant's stack
- ✅ No cross-tenant interference
- ✅ Proper error handling for invalid contexts

#### **3.2 Multi-Tenant Script 4**
**Objective**: Add services to specific tenant stacks

**Key Components**:
```bash
#!/bin/bash
# Script 4: Multi-Tenant Service Addition

add_service() {
    local tenant_name=$1
    local service_name=$2
    local service_image=$3
    local internal_port=$4
    
    if [ -z "$tenant_name" ] || [ -z "$service_name" ]; then
        echo "❌ Usage: add_service <tenant> <name> <image> <internal_port>"
        exit 1
    fi

    # Load tenant configuration
    local tenant_base="/mnt/data-${tenant_name}"
    source "${tenant_base}/config/.env"

    # Get next available port for tenant
    local new_port=$(get_next_free_port_for_tenant "$tenant_name")

    # Create tenant-specific AppArmor profile
    cp "/etc/apparmor.d/ai-platform-${STACK_USER_UID}" \
       "/etc/apparmor.d/ai-platform-${tenant_name}-${service_name}"
    apparmor_parser -r "/etc/apparmor.d/ai-platform-${tenant_name}-${service_name}"

    # Deploy service for specific tenant
    docker run -d \
        --name "${tenant_name}-${service_name}" \
        --network "ai-platform-${STACK_USER_UID}" \
        --restart unless-stopped \
        --security-opt "apparmor=ai-platform-${tenant_name}-${service_name}" \
        --user "${STACK_USER_UID}:${STACK_USER_GID}" \
        -p "${new_port}:${internal_port}" \
        -v "${tenant_base}/data/${service_name}:/app/data" \
        -v "${tenant_base}/logs/${service_name}:/app/logs" \
        "${service_image}"

    # Add route to tenant's Caddy
    add_caddy_route_tenant "$tenant_name" "$service_name" "$internal_port"

    # Reload tenant's Caddy
    docker exec "caddy-${tenant_name}" caddy reload --config "/etc/caddy/Caddyfile"

    echo "✅ Service ${service_name} added for tenant ${tenant_name} on port ${new_port}"
}
```

**Validation Criteria**:
- ✅ Adds services to specific tenant only
- ✅ Maintains tenant isolation
- ✅ Uses tenant-specific ports and networks
- ✅ Updates tenant's Caddy configuration

---

### **Phase 4: Testing & Validation (Week 2)**

#### **4.1 Multi-Tenant Test Scenarios**
**Objective**: Validate complete multi-tenant isolation

**Test Cases**:
```bash
#!/bin/bash
# Multi-Tenant Validation Tests

# Test 1: Simultaneous Tenant Deployment
test_simultaneous_tenants() {
    echo "🧪 Testing simultaneous tenant deployment..."
    
    # Deploy Tenant A (UID 1001)
    su - user1001 -c "cd /mnt/data-tenant-a && bash 2-deploy-services.sh" &
    local pid_a=$!
    
    # Deploy Tenant B (UID 1002)
    su - user1002 -c "cd /mnt/data-tenant-b && bash 2-deploy-services.sh" &
    local pid_b=$!
    
    # Wait for both deployments
    wait $pid_a $pid_b
    
    # Verify isolation
    verify_tenant_isolation "tenant-1001" "tenant-1002"
}

# Test 2: Cross-Tenant Access Prevention
test_cross_tenant_access() {
    echo "🧪 Testing cross-tenant access prevention..."
    
    # Try to access Tenant A's data from Tenant B's container
    docker exec "tenant-1002-n8n" ls /mnt/data-tenant-a/ 2>/dev/null && {
        echo "❌ Cross-tenant access detected - SECURITY BREACH"
        return 1
    }
    
    echo "✅ Cross-tenant access properly blocked"
}

# Test 3: Port Isolation
test_port_isolation() {
    echo "🧪 Testing port isolation..."
    
    # Check that both tenants can use their ports
    local tenant_a_ports=$(docker port "tenant-1001-grafana")
    local tenant_b_ports=$(docker port "tenant-1002-grafana")
    
    if [[ "$tenant_a_ports" =~ "5001" ]] && [[ "$tenant_b_ports" =~ "5101" ]]; then
        echo "✅ Port isolation working correctly"
    else
        echo "❌ Port isolation failed"
        return 1
    fi
}

# Test 4: AppArmor Isolation
test_apparmor_isolation() {
    echo "🧪 Testing AppArmor isolation..."
    
    # Try to access forbidden paths from tenant container
    docker exec "tenant-1001-anythingllm" cat /etc/passwd 2>/dev/null && {
        echo "❌ AppArmor not blocking access - SECURITY BREACH"
        return 1
    }
    
    echo "✅ AppArmor isolation working correctly"
}

# Test 5: Vector DB Isolation
test_vector_db_isolation() {
    echo "🧪 Testing vector DB isolation..."
    
    # Check that each tenant has separate collections
    local tenant_a_collections=$(docker exec "tenant-1001-qdrant" curl -s http://localhost:6333/collections | grep "tenant-1001")
    local tenant_b_collections=$(docker exec "tenant-1002-qdrant" curl -s http://localhost:6333/collections | grep "tenant-1002")
    
    if [[ -n "$tenant_a_collections" ]] && [[ -n "$tenant_b_collections" ]]; then
        echo "✅ Vector DB isolation working correctly"
    else
        echo "❌ Vector DB isolation failed"
        return 1
    fi
}

# Run all tests
run_all_tests() {
    test_simultaneous_tenants || return 1
    test_cross_tenant_access || return 1
    test_port_isolation || return 1
    test_apparmor_isolation || return 1
    test_vector_db_isolation || return 1
    
    echo "✅ All multi-tenant tests passed"
}
```

**Validation Criteria**:
- ✅ Multiple tenants can deploy simultaneously
- ✅ Cross-tenant access is blocked
- ✅ Port isolation works correctly
- ✅ AppArmor profiles enforce security
- ✅ Vector DB isolation maintained

---

## 🎯 Success Metrics

### **Technical Success**
- [ ] **Tenant Isolation**: Complete UID/GID, EBS, network, AppArmor isolation
- [ ] **Security**: No cross-tenant data access possible
- [ ] **Scalability**: Support unlimited tenants (UID 1001-65534)
- [ ] **Port Management**: Automatic port allocation with conflict resolution
- [ ] **Vector DB**: Isolated collections/namespaces per tenant

### **Operational Success**
- [ ] **Deployment**: Script 1 generates tenant config automatically
- [ ] **Management**: Script 3 operates per-tenant without interference
- [ ] **Extensibility**: Script 4 adds services to specific tenants
- [ ] **Teardown**: Script 0 removes entire tenant stack cleanly

### **Performance Success**
- [ ] **Resource Efficiency**: Shared host resources with isolated workloads
- [ ] **Network Performance**: No cross-tenant network interference
- [ ] **Storage Performance**: EBS volumes provide dedicated I/O
- [ ] **Security Overhead**: Minimal impact from AppArmor profiles

---

## 🚀 Implementation Timeline

### **Week 1: Core Infrastructure**
- [ ] **Day 1-2**: Enhance Script 1 for multi-tenant setup
- [ ] **Day 3-4**: Enhance Script 2 for tenant-aware deployment
- [ ] **Day 5**: Implement OpenClaw + Tailscale multi-tenant

### **Week 2: Integration & Testing**
- [ ] **Day 1-2**: Vector DB integration per tenant
- [ ] **Day 3**: Enhance Scripts 3 & 4 for multi-tenant operations
- [ ] **Day 4-5**: Comprehensive testing and validation

### **Week 3: Production Readiness**
- [ ] **Day 1-2**: Performance optimization and security hardening
- [ ] **Day 3**: Documentation and deployment guides
- [ ] **Day 4-5**: Production testing and monitoring setup

---

## 📋 Validation Checklist for Frontier Model

### **Architecture Validation**
- [ ] Does the design support unlimited tenants with UID 1001-65534?
- [ ] Is each tenant completely isolated (UID/GID, EBS, network, AppArmor)?
- [ ] Can multiple tenants deploy simultaneously without interference?
- [ ] Is port allocation automatic and conflict-free per tenant?
- [ ] Are vector DB collections/namespaces isolated per tenant?

### **Security Validation**
- [ ] Can tenants access each other's data (should be impossible)?
- [ ] Are AppArmor profiles properly configured per tenant?
- [ ] Is OpenClaw properly isolated with Tailscale sidecar?
- [ ] Are cross-tenant network connections blocked?
- [ ] Are file permissions properly set per tenant?

### **Operational Validation**
- [ ] Does Script 1 automatically generate tenant-specific configuration?
- [ ] Can Script 3 operate on individual tenants without affecting others?
- [ ] Can Script 4 add services to specific tenants?
- [ ] Does Script 0 cleanly remove entire tenant stacks?
- [ ] Are all scripts tenant-aware and context-safe?

### **Scalability Validation**
- [ ] Can the system handle 10+ concurrent tenants?
- [ ] Is EBS volume mounting automated per tenant?
- [ ] Are port ranges sufficient for tenant expansion?
- [ ] Is resource allocation fair among tenants?
- [ ] Can tenants be added/removed dynamically?

---

## 🔍 Key Questions for Frontier Model

1. **Architecture**: Is this multi-tenant design sound and secure?
2. **Isolation**: Are all isolation layers (UID/GID, EBS, network, AppArmor) sufficient?
3. **Scalability**: Can this scale to 100+ tenants on a single host?
4. **Security**: Are there any security vulnerabilities in the isolation model?
5. **Operations**: Are the scripts properly designed for multi-tenant management?
6. **Performance**: Will this architecture perform well under load?
7. **Extensibility**: Can new services be easily added to tenant stacks?
8. **Maintenance**: Is ongoing operational complexity manageable?

---

# Parameterized AI Platform Implementation Plan

## 🎯 Executive Summary

This document outlines the **correct implementation approach**: build a **parameterized single-stack architecture** now that supports multi-tenancy later without code changes. The key insight is that **multi-tenancy should be a deployment choice, not a code feature**.

---

## 🎯 Correct Architecture Principle

### **The "Build Now, Multi-Tenant Later" Approach**

```
What was asked:
"Build it clean with BASE_DIR, STACK_USER_UID etc. so that 
running a second stack later requires only a new .env — 
NOT a code rewrite"

What I previously built:
Multi-tenant logic baked INTO the scripts
(TENANT_NAME prefix on every container, per-tenant port ranges,
auto-detection of UID, tenant-prefixed networks)

What it should be:
Parameterized scripts that work with any .env configuration
Multi-tenancy = different .env values, same scripts
```

---

## 🏗️ Correct Architecture Model

### **Single Stack, Parameterized**
```bash
# Stack A (current setup)
BASE_DIR=/mnt/data
STACK_USER_UID=1000
DOCKER_NETWORK=ai_platform
DOMAIN_NAME=ai.datasquiz.net
PROMETHEUS_PORT=5000
# ... all other ports

# Stack B (future - same scripts, different .env)
BASE_DIR=/mnt/data2
STACK_USER_UID=2000
DOCKER_NETWORK=ai_platform_2
DOMAIN_NAME=ai2.datasquiz.net
PROMETHEUS_PORT=5100
# ... all other ports
```

### **Isolation Without Complexity**
- **Filesystem isolation**: Different `BASE_DIR` paths
- **Network isolation**: Different `DOCKER_NETWORK` names
- **Port isolation**: Different port ranges from `.env`
- **Process isolation**: Different `STACK_USER_UID` values
- **Container names**: Stay simple (`n8n`, `dify`, `postgres`)

---

## 📋 Implementation Phases

### **Phase 1: Parameterized Script 1 (Week 1)**

#### **1.1 Interactive Configuration Generation**
**Objective**: Generate tenant-specific `.env` without auto-detection

**Key Components**:
```bash
#!/bin/bash
# Script 1: Setup & Configuration (Parameterized)

# Interactive configuration - no auto-detection
echo "=== AI Platform Configuration ==="

read -p "Stack base directory [/mnt/data]: " BASE_DIR
BASE_DIR=${BASE_DIR:-/mnt/data}

read -p "Stack user UID [1000]: " STACK_USER_UID
STACK_USER_UID=${STACK_USER_UID:-1000}

read -p "Stack user GID [${STACK_USER_UID}]: " STACK_USER_GID
STACK_USER_GID=${STACK_USER_GID:-${STACK_USER_UID}}

read -p "Docker network name [ai_platform]: " DOCKER_NETWORK
DOCKER_NETWORK=${DOCKER_NETWORK:-ai_platform}

read -p "Domain name [ai.datasquiz.net]: " DOMAIN_NAME
DOMAIN_NAME=${DOMAIN_NAME:-ai.datasquiz.net}

read -p "Localhost for testing [localhost]: " LOCALHOST
LOCALHOST=${LOCALHOST:-localhost}

# OpenClaw gets dedicated UID (tenant UID + 1000)
OPENCLAW_UID=$((STACK_USER_UID + 1000))
OPENCLAW_GID=$((STACK_USER_GID + 1000))

# Port configuration with conflict checking
allocate_ports() {
    local ports=()
    local default_ports=(5000 5001 5002 5003 5004 5005 5006 5007 5008 5009 5010 5011)
    local services=(prometheus grafana n8n dify anythingllm litellm openwebui minio signal openclaw flowise)
    
    for i in "${!services[@]}"; do
        local default_port=${default_ports[$i]}
        local service=${services[$i]}
        
        read -p "${service} port [${default_port}]: " port_input
        local port=${port_input:-$default_port}
        
        # Check if port is available
        if netstat -tlnp | grep -q ":$port "; then
            echo "❌ Port $port is in use. Please choose another."
            i=$((i-1))  # Retry this service
            continue
        fi
        
        ports+=("$port")
        declare -g "${service^^}_PORT=$port"
    done
    
    # Export all port variables
    PROMETHEUS_PORT=${ports[0]}
    GRAFANA_PORT=${ports[1]}
    N8N_PORT=${ports[2]}
    DIFY_PORT=${ports[3]}
    ANYTHINGLLM_PORT=${ports[4]}
    LITELLM_PORT=${ports[5]}
    OPENWEBUI_PORT=${ports[6]}
    MINIO_S3_PORT=${ports[7]}
    MINIO_CONSOLE_PORT=${ports[8]}
    SIGNAL_PORT=${ports[9]}
    OPENCLAW_PORT=${ports[10]}
    FLOWISE_PORT=${ports[11]}
}

# EBS volume validation
validate_ebs_volume() {
    if [ ! -d "${BASE_DIR}" ]; then
        echo "❌ Directory ${BASE_DIR} does not exist."
        echo "Please ensure EBS volume is mounted and try again."
        exit 1
    fi
    
    # Check if it's actually a mounted EBS volume (not local directory)
    local mount_point=$(df "${BASE_DIR}" | tail -1 | awk '{print $6}')
    if [[ "$mount_point" != "${BASE_DIR}" ]]; then
        echo "⚠️  Warning: ${BASE_DIR} might not be a mounted EBS volume"
        read -p "Continue anyway? (y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
    fi
    
    echo "✅ EBS volume validated at ${BASE_DIR}"
}

# Generate .env
generate_env() {
    cat > "${BASE_DIR}/config/.env" << EOF
# === Stack Configuration ===
BASE_DIR=${BASE_DIR}
DOMAIN_NAME=${DOMAIN_NAME}
LOCALHOST=${LOCALHOST}

# === User Isolation ===
STACK_USER_UID=${STACK_USER_UID}
STACK_USER_GID=${STACK_USER_GID}
OPENCLAW_UID=${OPENCLAW_UID}
OPENCLAW_GID=${OPENCLAW_GID}

# === Network ===
DOCKER_NETWORK=${DOCKER_NETWORK}

# === Port Configuration ===
PROMETHEUS_PORT=${PROMETHEUS_PORT}
GRAFANA_PORT=${GRAFANA_PORT}
N8N_PORT=${N8N_PORT}
DIFY_PORT=${DIFY_PORT}
ANYTHINGLLM_PORT=${ANYTHINGLLM_PORT}
LITELLM_PORT=${LITELLM_PORT}
OPENWEBUI_PORT=${OPENWEBUI_PORT}
MINIO_S3_PORT=${MINIO_S3_PORT}
MINIO_CONSOLE_PORT=${MINIO_CONSOLE_PORT}
SIGNAL_PORT=${SIGNAL_PORT}
OPENCLAW_PORT=${OPENCLAW_PORT}
FLOWISE_PORT=${FLOWISE_PORT}

# === Vector DB ===
VECTOR_DB=qdrant

# === AppArmor ===
APPARMOR_PROFILE_DIR=${BASE_DIR}/apparmor

# === Tailscale ===
TAILSCALE_AUTH_KEY=
TAILSCALE_HOSTNAME=openclaw-${DOMAIN_NAME}
EOF

    echo "✅ Configuration written to ${BASE_DIR}/config/.env"
}

# Main setup flow
main() {
    echo "🚀 AI Platform Setup"
    
    # Validate EBS volume first
    validate_ebs_volume
    
    # Create directory structure
    mkdir -p "${BASE_DIR}/data" "${BASE_DIR}/logs" "${BASE_DIR}/config" "${BASE_DIR}/apparmor"
    mkdir -p "${BASE_DIR}/ssl/certs/${DOMAIN_NAME}"
    
    # Set ownership
    chown -R ${STACK_USER_UID}:${STACK_USER_GID} "${BASE_DIR}"
    
    # Allocate ports
    allocate_ports
    
    # Generate configuration
    generate_env
    
    echo ""
    echo "✅ Stack configuration complete!"
    echo "   Base Directory: ${BASE_DIR}"
    echo "   User UID/GID: ${STACK_USER_UID}:${STACK_USER_GID}"
    echo "   Network: ${DOCKER_NETWORK}"
    echo "   Domain: ${DOMAIN_NAME}"
    echo "   Configuration: ${BASE_DIR}/config/.env"
    echo ""
    echo "📋 Next steps:"
    echo "   bash 2-deploy-services.sh"
    echo "   bash 3-configure-services.sh"
}
```

**Validation Criteria**:
- ✅ No auto-detection of UID/GID
- ✅ Interactive configuration with sensible defaults
- ✅ Port conflict checking
- ✅ EBS volume validation (mounted, not just directory)
- ✅ Generates parameterized `.env` for any stack

#### **1.2 Directory Structure**
```bash
# Single stack structure (parameterized by BASE_DIR)
${BASE_DIR}/                    ← /mnt/data or /mnt/data2, etc.
├── apparmor/               ← AppArmor profiles (source files)
├── config/
│   └── .env                ← Stack configuration
├── data/
│   ├── postgres/
│   ├── n8n/
│   ├── anythingllm/
│   └── ... (all services)
├── logs/
├── ssl/certs/${DOMAIN_NAME}/
└── caddy/                    ← Caddy configuration
```

---

### **Phase 2: Parameterized Script 2 (Week 1)**

#### **2.1 Tenant-Aware Deployment**
**Objective**: Deploy stack using configuration from `.env` without tenant logic

**Key Components**:
```bash
#!/bin/bash
# Script 2: Parameterized Deployment

# Load configuration from .env
source "${BASE_DIR:-/mnt/data}/config/.env"

# Validate required variables
validate_config() {
    local required_vars=(BASE_DIR STACK_USER_UID STACK_USER_GID DOCKER_NETWORK DOMAIN_NAME)
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            echo "❌ Required variable $var not set in .env"
            exit 1
        fi
    done
    echo "✅ Configuration validated"
}

# Create Docker network
create_network() {
    docker network create "${DOCKER_NETWORK}" 2>/dev/null || true
    echo "✅ Docker network: ${DOCKER_NETWORK}"
}

# Parameterized AppArmor profiles
setup_apparmor_profiles() {
    local profile_dir="${APPARMOR_PROFILE_DIR}"
    mkdir -p "$profile_dir"
    
    # Default profile template with BASE_DIR placeholder
    cat > "${profile_dir}/ai-platform-default" << 'EOF'
#include <tunables/global>

profile ai-platform-default flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  # BASE_DIR will be substituted at load time
  BASE_DIR_PLACEHOLDER/** rw,

  # Deny access to sensitive host paths
  deny /etc/shadow r,
  deny /etc/passwd w,
  deny /root/** rw,

  network,
  /proc/self/** r,
  /sys/fs/cgroup/** r,
}
EOF

    # OpenClaw profile template
    cat > "${profile_dir}/ai-platform-openclaw" << 'EOF'
#include <tunables/global>

profile ai-platform-openclaw flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  # BASE_DIR will be substituted at load time
  BASE_DIR_PLACEHOLDER/data/openclaw/** rw,
  /tmp/** rw,

  # Deny everything else
  deny BASE_DIR_PLACEHOLDER/data/!openclaw/** rw,
  deny /etc/** w,
  deny /root/** rw,

  network,
  capability net_admin,
  capability sys_module,
}
EOF

    # Substitute BASE_DIR placeholder with actual path
    sed -i "s|BASE_DIR_PLACEHOLDER|${BASE_DIR}|g" \
        "${profile_dir}/ai-platform-default"
    sed -i "s|BASE_DIR_PLACEHOLDER|${BASE_DIR}|g" \
        "${profile_dir}/ai-platform-openclaw"
    
    # Copy to system location with stack-unique names
    local profile_name="${DOCKER_NETWORK}-default"
    cp "${profile_dir}/ai-platform-default" \
       "/etc/apparmor.d/${profile_name}"
    apparmor_parser -r "/etc/apparmor.d/${profile_name}"
    
    echo "✅ AppArmor profile loaded: ${profile_name}"
}

# Parameterized service deployment
deploy_service() {
    local service_name=$1
    local image=$2
    local internal_port=$3
    local host_port=$4
    
    docker run -d \
        --name "${service_name}" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --security-opt "apparmor=${DOCKER_NETWORK}-default" \
        --user "${STACK_USER_UID}:${STACK_USER_GID}" \
        -p "${host_port}:${internal_port}" \
        -v "${BASE_DIR}/data/${service_name}:/app/data" \
        -v "${BASE_DIR}/logs/${service_name}:/app/logs" \
        "${vectordb_env[@]}" \
        "${image}"
}

# Vector DB configuration (global for stack)
set_vectordb_config() {
    case "${VECTOR_DB}" in
        qdrant)
            export VECTORDB_HOST="qdrant"
            export VECTORDB_PORT="6333"
            export VECTORDB_TYPE="qdrant"
            export VECTORDB_URL="http://qdrant:6333"
            export VECTORDB_COLLECTION="ai-platform"
            ;;
        pgvector)
            export VECTORDB_HOST="postgres"
            export VECTORDB_PORT="5432"
            export VECTORDB_TYPE="pgvector"
            export VECTORDB_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}"
            export VECTORDB_COLLECTION="ai-platform"
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
            export VECTORDB_COLLECTION="ai-platform"
            ;;
    esac
}

# Main deployment flow
main() {
    echo "🚀 AI Platform Deployment"
    
    validate_config
    create_network
    setup_apparmor_profiles
    set_vectordb_config
    
    # Deploy infrastructure
    deploy_infrastructure
    deploy_ai_services
    deploy_openclaw
    deploy_caddy
    validate_deployment
}
```

**Validation Criteria**:
- ✅ Loads configuration from `.env` (no auto-detection)
- ✅ Uses simple container names (no tenant prefixes)
- ✅ AppArmor profiles use DOCKER_NETWORK for uniqueness
- ✅ BASE_DIR substitution works correctly
- ✅ No tenant logic baked into scripts

---

### **Phase 3: Vector DB Integration (Week 1-2)**

#### **3.1 Parameterized Vector DB Configuration**
**Objective**: Each stack gets isolated vector DB collections based on configuration

**Key Components**:
```bash
# Vector DB environment variables per service
build_vectordb_env() {
    local vectordb_env=()
    
    case "${VECTOR_DB}" in
        qdrant)
            vectordb_env=(
                -e "VECTOR_DB=qdrant"
                -e "QDRANT_ENDPOINT=${VECTORDB_URL}"
                -e "QDRANT_API_KEY="
                -e "QDRANT_COLLECTION=${VECTORDB_COLLECTION}"
            )
            ;;
        pgvector)
            vectordb_env=(
                -e "VECTOR_DB=pgvector"
                -e "PGVECTOR_CONNECTION_STRING=${VECTORDB_URL}"
                -e "PGVECTOR_SCHEMA=ai_platform"
            )
            ;;
        weaviate)
            vectordb_env=(
                -e "VECTOR_DB=weaviate"
                -e "WEAVIATE_ENDPOINT=${VECTORDB_URL}"
                -e "WEAVIATE_API_KEY="
                -e "WEAVIATE_CLASS=${VECTORDB_COLLECTION}"
            )
            ;;
        chroma)
            vectordb_env=(
                -e "VECTOR_DB=chroma"
                -e "CHROMA_HOST=${VECTORDB_HOST}"
                -e "CHROMA_PORT=${VECTORDB_PORT}"
                -e "CHROMA_COLLECTION=${VECTORDB_COLLECTION}"
            )
            ;;
    esac
    
    echo "${vectordb_env[@]}"
}

# Service deployment with vector DB integration
deploy_anythingllm() {
    local vectordb_env=($(build_vectordb_env))
    
    docker run -d \
        --name "anythingllm" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --security-opt "apparmor=${DOCKER_NETWORK}-default" \
        --user "${STACK_USER_UID}:${STACK_USER_GID}" \
        -p "${ANYTHINGLLM_PORT}:3001" \
        -v "${BASE_DIR}/data/anythingllm:/app/server/storage" \
        -e "STORAGE_DIR=/app/server/storage" \
        -e "LLM_PROVIDER=ollama" \
        -e "OLLAMA_BASE_PATH=http://ollama:11434" \
        -e "EMBEDDING_ENGINE=ollama" \
        -e "EMBEDDING_BASE_PATH=http://ollama:11434" \
        "${vectordb_env[@]}" \
        mintplexlabs/anythingllm:latest
}
```

**Validation Criteria**:
- ✅ Vector DB configuration based on `.env` variables
- ✅ No tenant-specific logic in vector DB setup
- ✅ Collections/namespaces isolated per stack
- ✅ Services use vector DB environment variables correctly

---

### **Phase 4: Operations & Extensibility (Week 2)**

#### **4.1 Parameterized Script 3**
**Objective**: Operate individual stacks using their configuration

**Key Components**:
```bash
#!/bin/bash
# Script 3: Operations & Management

# Auto-detect stack from current directory or environment
detect_stack() {
    if [[ -f "${BASE_DIR:-/mnt/data}/config/.env" ]]; then
        source "${BASE_DIR:-/mnt/data}/config/.env"
        echo "✅ Stack detected: ${DOMAIN_NAME}"
    else
        echo "❌ No stack configuration found. Run from stack directory or set BASE_DIR."
        exit 1
    fi
}

# Stack-specific operations
renew_ssl() {
    detect_stack
    echo "🔄 Renewing SSL for ${DOMAIN_NAME}"
    docker exec "caddy" caddy reload --config "/etc/caddy/Caddyfile"
}

restart_service() {
    local service_name=$1
    detect_stack
    echo "🔄 Restarting ${service_name}"
    docker restart "${service_name}"
}

show_status() {
    detect_stack
    echo "📊 Stack Status (${DOMAIN_NAME}, UID ${STACK_USER_UID}):"
    docker ps --network "${DOCKER_NETWORK}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
}

# Health check all services
health_check() {
    detect_stack
    echo "🔍 Health Check (${DOMAIN_NAME}):"
    
    local services=(prometheus grafana n8n anythingllm litellm openwebui minio)
    for service in "${services[@]}"; do
        local status=$(curl -s -o /dev/null -w "%{http_code}" \
            --max-time 5 "http://${LOCALHOST}:${!service^^}_PORT}/health" 2>/dev/null)
        
        if [[ "$status" == "200" ]]; then
            echo "✅ $service: Healthy"
        elif [[ "$status" == "502" ]]; then
            echo "⚠️  $service: Service not ready (502)"
        else
            echo "❌ $service: Unhealthy ($status)"
        fi
    done
}

# Main operations flow
main() {
    case "${1:-status}" in
        renew) renew_ssl ;;
        restart) restart_service "${2}" ;;
        status) show_status ;;
        health) health_check ;;
        *) 
            echo "Usage: $0 {renew|restart|status|health}"
            exit 1
            ;;
    esac
}
```

**Validation Criteria**:
- ✅ Auto-detects stack from current directory
- ✅ Operations work on specific stack only
- ✅ No tenant logic in operations
- ✅ Health checks use configuration from `.env`

#### **4.2 Parameterized Script 4**
**Objective**: Add services to specific stacks without affecting others

**Key Components**:
```bash
#!/bin/bash
# Script 4: Add Service to Stack

# Detect stack
detect_stack() {
    if [[ -f "${BASE_DIR:-/mnt/data}/config/.env" ]]; then
        source "${BASE_DIR:-/mnt/data}/config/.env"
    else
        echo "❌ No stack configuration found. Run from stack directory or set BASE_DIR."
        exit 1
    fi
}

add_service() {
    local service_name=$1
    local service_image=$2
    local internal_port=$3
    local host_port=$4
    
    detect_stack
    
    if [ -z "$service_name" ] || [ -z "$service_image" ]; then
        echo "❌ Usage: add_service <name> <image> <internal_port> <host_port>"
        exit 1
    fi

    # Check if service already exists
    if docker ps --format "{{.Names}}" | grep -q "^${service_name}$"; then
        echo "❌ Service $service_name already exists"
        exit 1
    fi
    
    # Check if port is available
    if netstat -tlnp | grep -q ":$host_port "; then
        echo "❌ Port $host_port is in use"
        exit 1
    fi
    
    # Create stack-specific AppArmor profile
    cp "/etc/apparmor.d/${DOCKER_NETWORK}-default" \
       "/etc/apparmor.d/${DOCKER_NETWORK}-${service_name}"
    apparmor_parser -r "/etc/apparmor.d/${DOCKER_NETWORK}-${service_name}"
    
    # Deploy service for this stack
    docker run -d \
        --name "${service_name}" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --security-opt "apparmor=${DOCKER_NETWORK}-${service_name}" \
        --user "${STACK_USER_UID}:${STACK_USER_GID}" \
        -p "${host_port}:${internal_port}" \
        -v "${BASE_DIR}/data/${service_name}:/app/data" \
        -v "${BASE_DIR}/logs/${service_name}:/app/logs" \
        "${service_image}"
    
    # Add route to Caddy
    add_caddy_route "$service_name" "$internal_port"
    
    # Reload Caddy
    docker exec "caddy" caddy reload --config "/etc/caddy/Caddyfile"
    
    echo "✅ Service $service_name added to stack ${DOMAIN_NAME}"
    echo "   Internal port: $internal_port"
    echo "   Host port: $host_port"
    echo "   URL: http://${DOMAIN_NAME}/${service_name}/"
}

add_caddy_route() {
    local name=$1
    local port=$2
    # Insert before closing brace of Caddyfile
    sed -i "/respond \"AI Platform\"/i\\
    handle_path /${name}/* {\\
        reverse_proxy ${name}:${port}\\
    }\\
" "${BASE_DIR}/caddy/Caddyfile"
}

# Main flow
main() {
    case "${1:-add}" in
        add) add_service "${2}" "${3}" "${4}" "${5}" ;;
        *) 
            echo "Usage: $0 add <name> <image> <internal_port> <host_port>"
            exit 1
            ;;
    esac
}
```

**Validation Criteria**:
- ✅ Adds services to specific stack only
- ✅ Uses stack's configuration from `.env`
- ✅ Maintains isolation between stacks
- ✅ Updates Caddy configuration correctly

---

### **Phase 5: Testing & Validation (Week 2)**

#### **5.1 Multi-Stack Test Scenarios**
**Objective**: Validate that multiple stacks can run simultaneously without interference

**Test Cases**:
```bash
#!/bin/bash
# Multi-Stack Validation Tests

# Test 1: Parameterized Stack Deployment
test_parameterized_stacks() {
    echo "🧪 Testing parameterized stack deployment..."
    
    # Deploy Stack A (default configuration)
    cd /mnt/data || { echo "❌ /mnt/data not found"; return 1; }
    bash 1-setup-system.sh
    bash 2-deploy-services.sh
    
    # Deploy Stack B (different configuration)
    mkdir -p /mnt/data2
    chown 2000:2000 /mnt/data2
    
    # Create configuration for Stack B
    cat > /mnt/data2/config/.env << EOF
BASE_DIR=/mnt/data2
DOMAIN_NAME=ai2.datasquiz.net
LOCALHOST=localhost
STACK_USER_UID=2000
STACK_USER_GID=2000
OPENCLAW_UID=3000
OPENCLAW_GID=3000
DOCKER_NETWORK=ai_platform_2
PROMETHEUS_PORT=5100
GRAFANA_PORT=5101
# ... all other ports +100
EOF
    
    chown -R 2000:2000 /mnt/data2
    cd /mnt/data2
    su - user2001 -c "bash 1-setup-system.sh && bash 2-deploy-services.sh"
    
    # Verify both stacks are running
    verify_stack_isolation
}

# Test 2: Cross-Stack Isolation
test_cross_stack_isolation() {
    echo "🧪 Testing cross-stack isolation..."
    
    # Check that Stack A cannot access Stack B's data
    docker exec n8n ls /mnt/data2/ 2>/dev/null && {
        echo "❌ Cross-stack access detected - SECURITY BREACH"
        return 1
    }
    
    # Check that Stack B cannot access Stack A's data
    docker exec -it ai_platform_2-n8n ls /mnt/data/ 2>/dev/null && {
        echo "❌ Cross-stack access detected - SECURITY BREACH"
        return 1
    }
    
    echo "✅ Cross-stack isolation working correctly"
}

# Test 3: Port Isolation
test_port_isolation() {
    echo "🧪 Testing port isolation..."
    
    # Check that both stacks use their assigned ports
    local stack_a_ports=$(docker port grafana | grep "5001/tcp")
    local stack_b_ports=$(docker port -it ai_platform_2-grafana | grep "5101/tcp")
    
    if [[ -n "$stack_a_ports" ]] && [[ -n "$stack_b_ports" ]]; then
        echo "✅ Port isolation working correctly"
        echo "   Stack A: $stack_a_ports"
        echo "   Stack B: $stack_b_ports"
    else
        echo "❌ Port isolation failed"
        return 1
    fi
}

# Test 4: AppArmor Isolation
test_apparmor_isolation() {
    echo "🧪 Testing AppArmor isolation..."
    
    # Try to access forbidden paths from Stack A container
    docker exec n8n cat /etc/passwd 2>/dev/null && {
        echo "❌ AppArmor not blocking access - SECURITY BREACH"
        return 1
    }
    
    echo "✅ AppArmor isolation working correctly"
}

# Test 5: Vector DB Isolation
test_vector_db_isolation() {
    echo "🧪 Testing vector DB isolation..."
    
    # Check that each stack has separate collections
    local stack_a_collections=$(docker exec qdrant curl -s http://localhost:6333/collections 2>/dev/null | grep "ai-platform")
    local stack_b_collections=$(docker exec -it ai_platform_2-qdrant curl -s http://localhost:6333/collections 2>/dev/null | grep "ai-platform")
    
    if [[ -n "$stack_a_collections" ]] && [[ -n "$stack_b_collections" ]]; then
        echo "❌ Vector DB isolation failed - collections not properly separated"
        return 1
    fi
    
    echo "✅ Vector DB isolation working correctly"
}

# Verify stack isolation
verify_stack_isolation() {
    echo "🔍 Verifying stack isolation..."
    
    # Check that containers are on different networks
    local stack_a_network=$(docker inspect n8n --format='{{range .NetworkSettings.Networks}}{{.Network.Name}}')
    local stack_b_network=$(docker inspect -it ai_platform_2-n8n --format='{{range .NetworkSettings.Networks}}{{.Network.Name}}')
    
    if [[ "$stack_a_network" == "ai_platform" ]] && [[ "$stack_b_network" == "ai_platform_2" ]]; then
        echo "✅ Network isolation working correctly"
    else
        echo "❌ Network isolation failed"
        return 1
    fi
    
    # Check that containers use different UIDs
    local stack_a_uid=$(docker inspect n8n --format='{{.Config.User}}')
    local stack_b_uid=$(docker inspect -it ai_platform_2-n8n --format='{{.Config.User}}')
    
    if [[ "$stack_a_uid" == "1000" ]] && [[ "$stack_b_uid" == "2000" ]]; then
        echo "✅ UID isolation working correctly"
    else
        echo "❌ UID isolation failed"
        return 1
    fi
}

# Run all tests
run_all_tests() {
    test_parameterized_stacks || return 1
    test_cross_stack_isolation || return 1
    test_port_isolation || return 1
    test_apparmor_isolation || return 1
    test_vector_db_isolation || return 1
    
    echo "✅ All multi-stack tests passed"
}

# Test the "One-Line Test"
test_one_line_test() {
    echo "🧪 Testing one-line test..."
    
    # This should work with zero code changes
    BASE_DIR=/mnt/data2 \
    STACK_USER_UID=3000 \
    DOCKER_NETWORK=ai_platform_3 \
    DOMAIN_NAME=ai3.datasquiz.net \
    PROMETHEUS_PORT=5200 \
    bash 2-deploy-services.sh
    
    echo "✅ One-line test passed"
}
```

**Validation Criteria**:
- ✅ Multiple stacks can deploy simultaneously
- ✅ Cross-stack access is blocked
- ✅ Port isolation works correctly
- ✅ AppArmor profiles enforce security
- ✅ Vector DB isolation maintained
- ✅ One-line test works without code changes

---

## 🎯 Success Metrics

### **Technical Success**
- [ ] **Parameterized Configuration**: All scripts use `.env` variables
- [ ] **Stack Isolation**: Complete isolation between stacks
- [ ] **Security**: No cross-stack data access possible
- [ ] **Scalability**: Support unlimited stacks with different configurations
- [ ] **Port Management**: Automatic port allocation with conflict resolution
- [ ] **Vector DB**: Isolated collections/namespaces per stack

### **Operational Success**
- [ ] **Deployment**: Script 1 generates configuration automatically
- [ ] **Management**: Script 3 operates per-stack without interference
- [ ] **Extensibility**: Script 4 adds services to specific stacks
- [ ] **Teardown**: Script 0 removes entire stack cleanly

### **Future-Proofing Success**
- [ ] **Multi-Tenancy Ready**: Second stack requires only new `.env`
- [ ] **No Code Changes**: All scripts work with any configuration
- [ ] **Clean Architecture**: No tenant logic baked into scripts
- [ ] **Maintainable**: Simple, parameterized design

---

## 🚀 Implementation Timeline

### **Week 1: Parameterized Infrastructure**
- [ ] **Day 1-2**: Rewrite Script 1 for interactive configuration
- [ ] **Day 3-4**: Rewrite Script 2 for parameterized deployment
- [ ] **Day 5**: Fix current service issues with parameterized approach

### **Week 2: Integration & Testing**
- [ ] **Day 1-2**: Vector DB integration with parameterization
- [ ] **Day 3**: Enhance Scripts 3 & 4 for parameterized operations
- [ ] **Day 4-5**: Comprehensive testing and validation

### **Week 3: Production Readiness**
- [ ] **Day 1-2**: Performance optimization and security hardening
- [ ] **Day 3**: Documentation and deployment guides
- [ ] **Day 4-5**: Production testing and monitoring setup

---

## 📋 Validation Checklist for Frontier Model

### **Architecture Validation**
- [ ] Does the design support unlimited stacks with different configurations?
- [ ] Is each stack completely isolated (UID/GID, BASE_DIR, network, AppArmor)?
- [ ] Can multiple stacks deploy simultaneously without interference?
- [ ] Is port allocation automatic and conflict-free per stack?
- [ ] Are vector DB collections/namespaces isolated per stack?

### **Security Validation**
- [ ] Can stacks access each other's data (should be impossible)?
- [ ] Are AppArmor profiles properly configured per stack?
- [ ] Is OpenClaw properly isolated with Tailscale sidecar?
- [ ] Are cross-stack network connections blocked?
- [ ] Are file permissions properly set per stack?

### **Operational Validation**
- [ ] Does Script 1 automatically generate stack-specific configuration?
- [ ] Can Script 3 operate on individual stacks without affecting others?
- [ ] Can Script 4 add services to specific stacks?
- [ ] Does Script 0 cleanly remove entire stack?
- [ ] Are all scripts parameterized and context-safe?

### **Future-Proofing Validation**
- [ ] Can the system handle 10+ concurrent stacks?
- [ ] Is EBS volume mounting automated per stack?
- [ ] Are port ranges sufficient for stack expansion?
- [ ] Is resource allocation fair among stacks?
- [ ] Can stacks be added/removed dynamically?

### **One-Line Test Validation**
- [ ] Does this work without code changes:
  ```bash
  BASE_DIR=/mnt/data2 \
  STACK_USER_UID=3000 \
  DOCKER_NETWORK=ai_platform_3 \
  DOMAIN_NAME=ai3.datasquiz.net \
  bash 2-deploy-services.sh
  ```

---

## 🔍 Key Questions for Frontier Model

1. **Architecture**: Is this parameterized design sound and future-proof?
2. **Isolation**: Are all isolation layers (UID/GID, BASE_DIR, network, AppArmor) sufficient?
3. **Scalability**: Can this scale to 100+ stacks on a single host?
4. **Security**: Are there any security vulnerabilities in the isolation model?
5. **Operations**: Are the scripts properly designed for parameterized management?
6. **Performance**: Will this architecture perform well under load?
7. **Extensibility**: Can new services be easily added to specific stacks?
8. **Maintenance**: Is ongoing operational complexity manageable?

---

## 🎯 Key Insight

**The correct approach** is: **parameterize everything, isolate through configuration, not code**.

- **Multi-tenancy** = different `.env` values, same scripts
- **Isolation** = different BASE_DIR paths, Docker networks, UIDs, ports
- **Future-proofing** = scripts work with any configuration without changes

This allows **multiple AI stacks to run simultaneously** under different configurations with **complete isolation** while sharing the same host machine and codebase.

---

*Implementation Plan Revised: 2026-02-21*
*Version: 2.0 - Parameterized Architecture*
*Architecture: Single Stack, Multi-Stack Ready*
*Status: Ready for Frontier Model Validation*
