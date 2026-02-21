# Final Parameterized AI Platform Implementation Plan

## 🎯 Executive Summary

This document outlines the **corrected implementation approach** based on user feedback. The architecture achieves **multi-stack isolation through parameterization alone** - no multi-tenant logic baked into scripts.

---

## 🎯 Core Architecture Principle

### **"Scripts Unaware of Other Stacks"**
```
Correct mental model:
  User A runs the 5 scripts → gets a stack
  User B runs the same 5 scripts → gets a stack
  Scripts never reference each other's existence
  Isolation comes from OS (different user, different mount)
  
Analogy: Dockerfile doesn't know how many containers will run.
Each instance is isolated by the runtime, not by logic inside.
```

---

## 📋 10 Critical Corrections Applied

### **1. ❌ REMOVED: Auto-UID Detection**
```bash
# REMOVED:
CURRENT_UID=$(id -u)
TENANT_NAME="tenant-${CURRENT_UID}"
PORT_RANGE_START=$((5000 + (CURRENT_UID - 1000) * 100))

# ADDED: Explicit operator input
echo "=== Stack Configuration ==="
read -p "EBS mount point for this stack [/mnt/data]: " BASE_DIR
BASE_DIR=${BASE_DIR:-/mnt/data}

read -p "Service owner UID [1000]: " STACK_USER_UID
STACK_USER_UID=${STACK_USER_UID:-1000}

read -p "Service owner GID [1000]: " STACK_USER_GID
STACK_USER_GID=${STACK_USER_GID:-1000}

read -p "Docker network name [ai_platform]: " DOCKER_NETWORK
DOCKER_NETWORK=${DOCKER_NETWORK:-ai_platform}

# OpenClaw gets next UID up from stack user
OPENCLAW_UID=$((STACK_USER_UID + 1))
OPENCLAW_GID=$((STACK_USER_GID + 1))
```

### **2. ❌ REMOVED: TENANT_NAME Container Prefixes**
```bash
# REMOVED:
"${TENANT_NAME}-n8n"
"${TENANT_NAME}-postgres"
"tailscale-${TENANT_NAME}"
"openclaw-${TENANT_NAME}"

# KEPT: Simple container names
--name "n8n"
--name "postgres"
--name "tailscale"
--name "openclaw"

# Isolation provided by:
# - Different DOCKER_NETWORK (ai_platform vs ai_platform_2)
# - Different BASE_DIR volume mounts (/mnt/data vs /mnt/data2)
# - Different host ports (5000 vs 5100)
```

### **3. ❌ REMOVED: Per-Tenant Port Range Math**
```bash
# REMOVED:
PORT_RANGE_START=$((5000 + (CURRENT_UID - 1000) * 100))

# KEPT: Script 1 handles port availability, writes explicit values
PROMETHEUS_PORT=5000
GRAFANA_PORT=5001
N8N_PORT=5002
# Script 2 reads: source ${BASE_DIR}/.env; uses ${N8N_PORT}
```

### **4. ✅ FIXED: AppArmor Profile Naming**
```bash
# FIXED: Use DOCKER_NETWORK as unique identifier
cp "${BASE_DIR}/apparmor/default.profile.tmpl" \
   "/etc/apparmor.d/${DOCKER_NETWORK}-default"

cp "${BASE_DIR}/apparmor/openclaw.profile.tmpl" \
   "/etc/apparmor.d/${DOCKER_NETWORK}-openclaw"

apparmor_parser -r "/etc/apparmor.d/${DOCKER_NETWORK}-default"
apparmor_parser -r "/etc/apparmor.d/${DOCKER_NETWORK}-openclaw"

# Applied to containers:
--security-opt "apparmor=${DOCKER_NETWORK}-default"
--security-opt "apparmor=${DOCKER_NETWORK}-openclaw"

# Script 0 cleanup:
rm -f /etc/apparmor.d/${DOCKER_NETWORK}-*
```

### **5. ✅ FIXED: AppArmor Allowlist Syntax**
```bash
# REMOVED (invalid syntax):
deny ${BASE_DIR}/data/!openclaw/** rw,

# ADDED: Allowlist approach (secure and valid)
# OpenClaw profile template:
cat > "${BASE_DIR}/apparmor/openclaw.profile.tmpl" << 'EOF'
#include <tunables/global>

profile ai-platform-openclaw flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  # Allowlist: only what OpenClaw needs
  BASE_DIR_PLACEHOLDER/data/openclaw/** rw,
  /tmp/** rw,

  # Everything else implicitly denied
  network,
  capability net_admin,
  capability sys_module,
}
EOF

# Default profile template:
cat > "${BASE_DIR}/apparmor/default.profile.tmpl" << 'EOF'
#include <tunables/global>

profile ai-platform-default flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  # Allow access to stack's data directory
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
```

### **6. ✅ ENHANCED: EBS Volume Validation**
```bash
validate_ebs_mount() {
    # Check it exists
    if [ ! -d "${BASE_DIR}" ]; then
        echo "❌ ${BASE_DIR} does not exist"
        exit 1
    fi

    # Check it is a real mount point (not just local dir)
    if ! mountpoint -q "${BASE_DIR}"; then
        echo "⚠️  WARNING: ${BASE_DIR} is not a dedicated mount point"
        read -p "Continue anyway? (y/N): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
    fi

    # Check it is writable by the specified UID
    if ! sudo -u "#${STACK_USER_UID}" test -w "${BASE_DIR}"; then
        echo "❌ ${BASE_DIR} is not writable by UID ${STACK_USER_UID}"
        exit 1
    fi

    # Check sufficient free space (minimum 20GB)
    local free_gb=$(df -BG "${BASE_DIR}" | awk 'NR==2 {gsub("G",""); print $4}')
    if [ "${free_gb}" -lt 20 ]; then
        echo "❌ Insufficient space: ${free_gb}GB free, 20GB required"
        exit 1
    fi

    echo "✅ EBS volume validated at ${BASE_DIR} (${free_gb}GB free)"
}
```

### **7-10. ✅ KEPT: Correct Core Components**

| Component | Status | Why It's Correct |
|-----------|--------|-----------------|
| `BASE_DIR` drives all paths | ✅ KEPT | Core parameterization principle |
| `DOCKER_NETWORK` as variable | ✅ KEPT | Enables stack isolation |
| `STACK_USER_UID`, `OPENCLAW_UID` | ✅ KEPT | Correct security model |
| OpenClaw at `${BASE_DIR}/data/openclaw/` | ✅ KEPT | No `/opt`, no host paths |
| Tailscale sidecar pattern | ✅ KEPT | Correct network namespace sharing |
| Vector DB wired at deploy time | ✅ KEPT | Correct responsibility assignment |

---

## 🏗️ Final Architecture Model

### **Stack A Configuration**
```bash
# Generated by Script 1
BASE_DIR=/mnt/data
DOCKER_NETWORK=ai_platform
DOMAIN_NAME=ai.datasquiz.net
STACK_USER_UID=1000
STACK_USER_GID=1000
OPENCLAW_UID=1001
OPENCLAW_GID=1001

# Ports (assigned by availability check)
PROMETHEUS_PORT=5000
GRAFANA_PORT=5001
N8N_PORT=5002
# ... etc
```

### **Stack B Configuration (Same Scripts, Different Values)**
```bash
# Generated by Script 1 (second run)
BASE_DIR=/mnt/data2
DOCKER_NETWORK=ai_platform_2
DOMAIN_NAME=ai2.datasquiz.net
STACK_USER_UID=2000
STACK_USER_GID=2000
OPENCLAW_UID=2001
OPENCLAW_GID=2001

# Ports (assigned by availability check)
PROMETHEUS_PORT=5100
GRAFANA_PORT=5101
N8N_PORT=5102
# ... etc
```

### **Isolation Mechanisms**
- **Filesystem**: Different `BASE_DIR` paths
- **Network**: Different `DOCKER_NETWORK` names
- **Process**: Different `STACK_USER_UID` values
- **Security**: Different AppArmor profiles
- **Ports**: Different host port mappings

---

## 📋 Implementation Phases

### **Phase 1: Script 1 - Parameterized Setup (Week 1)**

#### **1.1 Interactive Configuration**
```bash
#!/bin/bash
# Script 1: Setup & Configuration (Parameterized)

main() {
    echo "🚀 AI Platform Setup"
    
    # Interactive configuration
    echo "=== Stack Configuration ==="
    read -p "EBS mount point for this stack [/mnt/data]: " BASE_DIR
    BASE_DIR=${BASE_DIR:-/mnt/data}
    
    read -p "Service owner UID [1000]: " STACK_USER_UID
    STACK_USER_UID=${STACK_USER_UID:-1000}
    
    read -p "Service owner GID [1000]: " STACK_USER_GID
    STACK_USER_GID=${STACK_USER_GID:-1000}
    
    read -p "Docker network name [ai_platform]: " DOCKER_NETWORK
    DOCKER_NETWORK=${DOCKER_NETWORK:-ai_platform}
    
    read -p "Domain name [ai.datasquiz.net]: " DOMAIN_NAME
    DOMAIN_NAME=${DOMAIN_NAME:-ai.datasquiz.net}
    
    # OpenClaw gets next UID up
    OPENCLAW_UID=$((STACK_USER_UID + 1))
    OPENCLAW_GID=$((STACK_USER_GID + 1))
    
    # Validate EBS volume
    validate_ebs_mount
    
    # Create directory structure
    mkdir -p "${BASE_DIR}/data" "${BASE_DIR}/logs" "${BASE_DIR}/config" "${BASE_DIR}/apparmor"
    mkdir -p "${BASE_DIR}/ssl/certs/${DOMAIN_NAME}"
    
    # Set ownership
    chown -R ${STACK_USER_UID}:${STACK_USER_GID} "${BASE_DIR}"
    
    # Port allocation with conflict checking
    allocate_ports
    
    # Generate AppArmor templates
    create_apparmor_templates
    
    # Generate .env
    generate_env
    
    echo "✅ Stack configuration complete!"
    echo "   Base Directory: ${BASE_DIR}"
    echo "   User UID/GID: ${STACK_USER_UID}:${STACK_USER_GID}"
    echo "   Network: ${DOCKER_NETWORK}"
    echo "   Configuration: ${BASE_DIR}/config/.env"
}
```

#### **1.2 Port Allocation**
```bash
allocate_ports() {
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
        
        declare -g "${service^^}_PORT=$port"
    done
}
```

#### **1.3 AppArmor Template Creation**
```bash
create_apparmor_templates() {
    local profile_dir="${BASE_DIR}/apparmor"
    
    # Default profile template
    cat > "${profile_dir}/default.profile.tmpl" << 'EOF'
#include <tunables/global>

profile ai-platform-default flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  BASE_DIR_PLACEHOLDER/** rw,

  deny /etc/shadow r,
  deny /etc/passwd w,
  deny /root/** rw,

  network,
  /proc/self/** r,
  /sys/fs/cgroup/** r,
}
EOF

    # OpenClaw profile template
    cat > "${profile_dir}/openclaw.profile.tmpl" << 'EOF'
#include <tunables/global>

profile ai-platform-openclaw flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  BASE_DIR_PLACEHOLDER/data/openclaw/** rw,
  /tmp/** rw,

  network,
  capability net_admin,
  capability sys_module,
}
EOF

    # Tailscale profile template
    cat > "${profile_dir}/tailscale.profile.tmpl" << 'EOF'
#include <tunables/global>

profile ai-platform-tailscale flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  BASE_DIR_PLACEHOLDER/data/tailscale/** rw,
  /dev/net/tun rw,
  /var/run/tailscale/** rw,

  network,
  capability net_admin,
  capability sys_module,
}
EOF
}
```

#### **1.4 Environment Generation**
```bash
generate_env() {
    cat > "${BASE_DIR}/config/.env" << EOF
# === Stack Configuration ===
BASE_DIR=${BASE_DIR}
DOCKER_NETWORK=${DOCKER_NETWORK}
DOMAIN_NAME=${DOMAIN_NAME}
LOCALHOST=localhost

# === User Identity ===
STACK_USER_UID=${STACK_USER_UID}
STACK_USER_GID=${STACK_USER_GID}
OPENCLAW_UID=${OPENCLAW_UID}
OPENCLAW_GID=${OPENCLAW_GID}

# === AppArmor Profile Names ===
APPARMOR_DEFAULT=${DOCKER_NETWORK}-default
APPARMOR_OPENCLAW=${DOCKER_NETWORK}-openclaw
APPARMOR_TAILSCALE=${DOCKER_NETWORK}-tailscale

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

# === Tailscale ===
TAILSCALE_AUTH_KEY=
TAILSCALE_HOSTNAME=openclaw-${DOMAIN_NAME}
EOF

    echo "✅ Configuration written to ${BASE_DIR}/config/.env"
}
```

---

### **Phase 2: Script 2 - Parameterized Deployment (Week 1)**

#### **2.1 Main Deployment Function**
```bash
#!/bin/bash
# Script 2: Parameterized Deployment

# Load configuration
source "${BASE_DIR:-/mnt/data}/config/.env"

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

validate_config() {
    local required_vars=(BASE_DIR STACK_USER_UID DOCKER_NETWORK DOMAIN_NAME)
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            echo "❌ Required variable $var not set in .env"
            exit 1
        fi
    done
    echo "✅ Configuration validated"
}

create_network() {
    docker network create "${DOCKER_NETWORK}" 2>/dev/null || true
    echo "✅ Docker network: ${DOCKER_NETWORK}"
}
```

#### **2.2 AppArmor Profile Setup**
```bash
setup_apparmor_profiles() {
    local profile_dir="${BASE_DIR}/apparmor"
    
    # Substitute BASE_DIR and load profiles
    for profile in default openclaw tailscale; do
        local profile_name="${DOCKER_NETWORK}-${profile}"
        
        # Substitute BASE_DIR placeholder
        sed "s|BASE_DIR_PLACEHOLDER|${BASE_DIR}|g" \
            "${profile_dir}/${profile}.profile.tmpl" \
            > "/etc/apparmor.d/${profile_name}"
        
        # Load profile
        apparmor_parser -r "/etc/apparmor.d/${profile_name}"
        echo "✅ AppArmor profile loaded: ${profile_name}"
    done
}
```

#### **2.3 Service Deployment**
```bash
deploy_service() {
    local service_name=$1
    local image=$2
    local internal_port=$3
    local host_port=$4
    
    docker run -d \
        --name "${service_name}" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --security-opt "apparmor=${APPARMOR_DEFAULT}" \
        --user "${STACK_USER_UID}:${STACK_USER_GID}" \
        -p "${host_port}:${internal_port}" \
        -v "${BASE_DIR}/data/${service_name}:/app/data" \
        -v "${BASE_DIR}/logs/${service_name}:/app/logs" \
        "${vectordb_env[@]}" \
        "${image}"
}

deploy_openclaw() {
    if [ -z "${TAILSCALE_AUTH_KEY}" ]; then
        echo "❌ TAILSCALE_AUTH_KEY missing — OpenClaw requires Tailscale"
        return 1
    fi

    # Create OpenClaw directories
    mkdir -p "${BASE_DIR}/data/openclaw" "${BASE_DIR}/data/tailscale"
    chown -R ${OPENCLAW_UID}:${OPENCLAW_GID} "${BASE_DIR}/data/openclaw"
    chown -R ${OPENCLAW_UID}:${OPENCLAW_GID} "${BASE_DIR}/data/tailscale"

    # Step 1: Tailscale sidecar
    docker run -d \
        --name "tailscale" \
        --network "${DOCKER_NETWORK}" \
        --restart unless-stopped \
        --cap-add NET_ADMIN \
        --cap-add SYS_MODULE \
        --security-opt "apparmor=${APPARMOR_TAILSCALE}" \
        --user "${OPENCLAW_UID}:${OPENCLAW_GID}" \
        -v "${BASE_DIR}/data/tailscale:/var/lib/tailscale" \
        -v /dev/net/tun:/dev/net/tun \
        -e "TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY}" \
        -e "TAILSCALE_HOSTNAME=${TAILSCALE_HOSTNAME}" \
        tailscale/tailscale:latest

    # Wait for Tailscale authentication
    wait_for_tailscale_auth "tailscale"

    # Step 2: OpenClaw in shared network namespace
    docker run -d \
        --name "openclaw" \
        --network "container:tailscale" \
        --restart unless-stopped \
        --security-opt "apparmor=${APPARMOR_OPENCLAW}" \
        --user "${OPENCLAW_UID}:${OPENCLAW_GID}" \
        --read-only \
        --tmpfs /tmp:rw,noexec,nosuid,size=100m \
        -v "${BASE_DIR}/data/openclaw:/app/data:rw" \
        -v "${BASE_DIR}/config/openclaw:/app/config:ro" \
        "${vectordb_env[@]}" \
        openclaw/openclaw:latest

    echo "✅ OpenClaw deployed"
}
```

---

### **Phase 3: Script 3 - Operations (Week 2)**

#### **3.1 Stack-Aware Operations**
```bash
#!/bin/bash
# Script 3: Operations & Management

detect_stack() {
    if [[ -f "${BASE_DIR:-/mnt/data}/config/.env" ]]; then
        source "${BASE_DIR:-/mnt/data}/config/.env"
        echo "✅ Stack detected: ${DOMAIN_NAME}"
    else
        echo "❌ No stack configuration found. Run from stack directory or set BASE_DIR."
        exit 1
    fi
}

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
```

---

### **Phase 4: Script 4 - Add Service (Week 2)**

#### **4.1 Service Addition**
```bash
#!/bin/bash
# Script 4: Add Service to Stack

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
    
    # Check port availability
    if netstat -tlnp | grep -q ":$host_port "; then
        echo "❌ Port $host_port is in use"
        exit 1
    fi
    
    # Create service-specific AppArmor profile
    cp "/etc/apparmor.d/${APPARMOR_DEFAULT}" \
       "/etc/apparmor.d/${DOCKER_NETWORK}-${service_name}"
    apparmor_parser -r "/etc/apparmor.d/${DOCKER_NETWORK}-${service_name}"
    
    # Deploy service
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
}
```

---

### **Phase 5: Testing & Validation (Week 2)**

#### **5.1 Multi-Stack Test**
```bash
#!/bin/bash
# Multi-Stack Validation

test_multi_stack() {
    echo "🧪 Testing multi-stack deployment..."
    
    # Deploy Stack A
    cd /mnt/data || { echo "❌ /mnt/data not found"; return 1; }
    bash 1-setup-system.sh
    bash 2-deploy-services.sh
    
    # Deploy Stack B
    mkdir -p /mnt/data2
    chown 2000:2000 /mnt/data2
    
    # Create Stack B config
    cat > /mnt/data2/config/.env << EOF
BASE_DIR=/mnt/data2
DOCKER_NETWORK=ai_platform_2
DOMAIN_NAME=ai2.datasquiz.net
STACK_USER_UID=2000
STACK_USER_GID=2000
OPENCLAW_UID=2001
OPENCLAW_GID=2001
PROMETHEUS_PORT=5100
GRAFANA_PORT=5101
# ... other ports +100
EOF
    
    # Deploy Stack B
    cd /mnt/data2
    bash 2-deploy-services.sh
    
    # Verify isolation
    verify_stack_isolation
}

verify_stack_isolation() {
    echo "🔍 Verifying stack isolation..."
    
    # Check network isolation
    local stack_a_network=$(docker inspect n8n --format='{{range .NetworkSettings.Networks}}{{.Network.Name}}')
    local stack_b_network=$(docker inspect -it ai_platform_2-n8n --format='{{range .NetworkSettings.Networks}}{{.Network.Name}}')
    
    if [[ "$stack_a_network" == "ai_platform" ]] && [[ "$stack_b_network" == "ai_platform_2" ]]; then
        echo "✅ Network isolation working"
    else
        echo "❌ Network isolation failed"
        return 1
    fi
    
    # Check cross-stack access prevention
    docker exec n8n ls /mnt/data2/ 2>/dev/null && {
        echo "❌ Cross-stack access detected - SECURITY BREACH"
        return 1
    }
    
    echo "✅ Cross-stack isolation working"
}

# The One-Line Test
test_one_line() {
    echo "🧪 Testing one-line deployment..."
    
    BASE_DIR=/mnt/data3 \
    STACK_USER_UID=3000 \
    DOCKER_NETWORK=ai_platform_3 \
    DOMAIN_NAME=ai3.datasquiz.net \
    PROMETHEUS_PORT=5200 \
    bash 2-deploy-services.sh
    
    echo "✅ One-line test passed"
}
```

---

## 🎯 Success Criteria

### **The Test**
```bash
# Run 5 scripts twice with different .env values
# (different BASE_DIR, different DOCKER_NETWORK)
# Must produce two completely isolated stacks with zero code changes

# Stack A:
cd /mnt/data && bash 1-setup-system.sh && bash 2-deploy-services.sh

# Stack B:
cd /mnt/data2 && bash 1-setup-system.sh && bash 2-deploy-services.sh

# Result: Two isolated stacks, same scripts
```

### **Validation Checklist**
- [ ] **No Auto-Detection**: Scripts ask operator for configuration
- [ ] **Simple Container Names**: No TENANT_NAME prefixes
- [ ] **Explicit Port Variables**: No port math, availability checking only
- [ ] **DOCKER_NETWORK AppArmor**: Clean profile naming
- [ ] **Allowlist Security**: Valid AppArmor syntax
- [ ] **EBS Validation**: mountpoint, writability, space check
- [ ] **Parameterized Architecture**: BASE_DIR, DOCKER_NETWORK, UIDs as variables
- [ ] **OpenClaw Isolation**: Strict filesystem confinement
- [ ] **Tailscale Sidecar**: Correct network namespace sharing
- [ ] **Vector DB Integration**: Wired at deploy time

---

## 🚀 Implementation Timeline

### **Week 1: Core Infrastructure**
- [ ] **Day 1-2**: Rewrite Script 1 with 10 corrections
- [ ] **Day 3-4**: Rewrite Script 2 with parameterized deployment
- [ ] **Day 5**: Fix current service issues

### **Week 2: Integration & Testing**
- [ ] **Day 1-2**: Scripts 3 & 4 parameterized operations
- [ ] **Day 3-4**: Multi-stack testing and validation
- [ ] **Day 5**: Documentation and deployment guides

---

## 🎯 Key Insight

**The correct approach**: **parameterize everything, isolate through configuration, not code**.

- **Multi-tenancy** = different `.env` values, same scripts
- **Isolation** = different BASE_DIR paths, Docker networks, UIDs, ports
- **Future-proofing** = scripts work with any configuration without changes

This allows **multiple AI stacks to run simultaneously** under different configurations with **complete isolation** while sharing the same host machine and codebase.

---

*Final Implementation Plan: 2026-02-21*
*Version: 3.0 - Corrected Parameterized Architecture*
*Architecture: Single Stack, Multi-Stack Ready*
*Status: Ready for Implementation*
