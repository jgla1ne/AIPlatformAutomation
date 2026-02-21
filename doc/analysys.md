## Analysis of Windsurf's Revised Plan

Windsurf correctly picked up the dynamic variable feedback but then **over-engineered into multi-tenancy prematurely**. Here's the precise assessment:

---

## ✅ What Windsurf Got Right

| Item | Status |
|------|--------|
| `BASE_DIR` variable instead of hardcoded `/mnt/data` | ✅ Correct direction |
| `DOMAIN_NAME` variable | ✅ Correct |
| `LOCALHOST` variable from `.env` | ✅ Correct |
| `TENANT_UID`/`OPENCLAW_UID` as variables | ✅ Correct |
| AppArmor profiles under tenant path (not `/etc/apparmor.d`) | ✅ Correct intent |
| Dynamic port variables from `.env` | ✅ Correct |

---

## ❌ What Windsurf Got Wrong — Over-Engineering

### Problem 1: Multi-tenancy is NOT in scope now

```
Windsurf built:                    What was actually asked:
/mnt/data/tenants/tenant-a/   ←→   /mnt/data/         (single stack)
tenant-${TENANT_NAME}.env     ←→   .env                (one env file)
docker network ai-platform-a  ←→   ai_platform         (one network)
per-tenant port ranges        ←→   ports from .env     (one set)
```

The **intent** expressed was: *eventually* spin multiple stacks on the same machine under different user profiles with dedicated EBS volumes. That's future architecture. **Current scope = single stack, single tenant.**

The correct response to that intent is: **build it clean and parameterized NOW so multi-tenancy is possible LATER without refactoring** — not implement multi-tenancy today.

### Problem 2: AppArmor profiles still go to `/etc/apparmor.d/`

AppArmor profiles **must** be loaded from `/etc/apparmor.d/` by the kernel — that's not configurable. However, the **source files** can live under `${BASE_DIR}` and be symlinked or copied to `/etc/apparmor.d/` at load time:

```bash
# Correct pattern:
setup_apparmor_profiles() {
    local profile_dir="${BASE_DIR}/apparmor"
    mkdir -p "${profile_dir}"
    
    # Write profiles to BASE_DIR (tenant-owned)
    cat > "${profile_dir}/ai-platform-default" << 'EOF'
    ...
    /mnt/data/** r,   # ← This still needs BASE_DIR substitution (see below)
EOF

    # Copy to system location for kernel loading
    cp "${profile_dir}/ai-platform-default" \
       /etc/apparmor.d/ai-platform-default
    
    apparmor_parser -r /etc/apparmor.d/ai-platform-default
}
```

**Key subtlety**: The AppArmor profile content itself has hardcoded paths like `/mnt/data/**` — these need `sed` substitution if `BASE_DIR` changes:

```bash
# After writing profile template, substitute BASE_DIR
sed -i "s|/mnt/data|${BASE_DIR}|g" \
    "${profile_dir}/ai-platform-default"
```

### Problem 3: The `tenants/` directory structure breaks current scripts

```bash
# Windsurf now has:
${BASE_DIR}/tenants/${TENANT_NAME}/data/
${BASE_DIR}/tenants/${TENANT_NAME}/logs/
${BASE_DIR}/tenants/${TENANT_NAME}/config/

# But all current scripts expect:
${BASE_DIR}/n8n/
${BASE_DIR}/dify/
${BASE_DIR}/postgres/
# etc.
```

This breaks scripts 0, 3, and 4 which all reference `${BASE_DIR}/{service}`.

### Problem 4: `get_next_free_port_for_tenant()` is hardcoded

```bash
# Windsurf wrote:
case "${tenant_name}" in
    tenant-a) echo "5000" ;;
    tenant-b) echo "5100" ;;   # ← Hardcoded tenant names
```

This defeats the purpose of dynamic configuration entirely.

---

## Correct Revised Instructions for Windsurf

```
CORRECTION TO PREVIOUS PLAN:

REMOVE all multi-tenancy implementation. The architecture supports
it EVENTUALLY but is NOT being built now.

CURRENT SCOPE: Single stack, single user, single .env

The correct way to support future multi-tenancy is:
1. Use ${BASE_DIR} everywhere instead of /mnt/data
2. Use ${STACK_USER_UID}/${STACK_USER_GID} instead of 1000:1000
3. Use ${OPENCLAW_UID}/${OPENCLAW_GID} instead of 2000:2000
4. Use ${DOCKER_NETWORK} instead of ai_platform
5. Use ${DOMAIN_NAME} instead of ai.datasquiz.net
6. Use ${LOCALHOST} instead of localhost

When a second stack is needed later, a new .env with different
values (BASE_DIR=/mnt/data2, STACK_USER_UID=3000, etc.) will
create a fully isolated stack WITHOUT any code changes.

DIRECTORY STRUCTURE stays flat:
${BASE_DIR}/n8n/
${BASE_DIR}/dify/
${BASE_DIR}/postgres/
${BASE_DIR}/caddy/
${BASE_DIR}/apparmor/       ← profile source files live here
${BASE_DIR}/.env

NOT:
${BASE_DIR}/tenants/tenant-a/data/n8n/   ← Remove this
```

---

## Corrected `.env` Variables Windsurf Should Use

```bash
# .env — written by Script 1, consumed by all others

# === Infrastructure ===
BASE_DIR=/mnt/data
DOCKER_NETWORK=ai_platform
DOMAIN_NAME=ai.datasquiz.net
LOCALHOST=localhost

# === User isolation (future multi-tenancy ready) ===
STACK_USER_UID=1000
STACK_USER_GID=1000
OPENCLAW_UID=2000
OPENCLAW_GID=2000

# === AppArmor ===
APPARMOR_PROFILE_DIR=${BASE_DIR}/apparmor
# Profiles written here, symlinked to /etc/apparmor.d/

# === Vector DB ===
VECTOR_DB=qdrant

# === Ports (all dynamic from Script 1) ===
PROMETHEUS_PORT=5000
GRAFANA_PORT=5001
N8N_PORT=5002
DIFY_PORT=5003
ANYTHINGLLM_PORT=5004
LITELLM_PORT=5005
OPENWEBUI_PORT=5006
MINIO_S3_PORT=5007
MINIO_CONSOLE_PORT=5008
SIGNAL_PORT=5009
OPENCLAW_PORT=5010
FLOWISE_PORT=5011

# === Tailscale ===
TAILSCALE_AUTH_KEY=
TAILSCALE_HOSTNAME=openclaw-${HOSTNAME}
```

---

## Corrected Script 2 Pattern (No Tenant References)

```bash
#!/bin/bash
# Script 2 — Deploy Everything
# All values from ${BASE_DIR}/.env — NO hardcoded paths or ports

source "${BASE_DIR:-/mnt/data}/.env"

set_vectordb_config()    # Sets VECTORDB_HOST, VECTORDB_PORT, VECTORDB_URL
setup_apparmor_profiles() # Writes to ${BASE_DIR}/apparmor, loads to /etc/apparmor.d
deploy_infrastructure()   # postgres, redis, selected vector DB — health gated
deploy_ai_services()      # All services with vectordb_env[], non-root users
deploy_openclaw()         # Tailscale sidecar + --user ${OPENCLAW_UID}:${OPENCLAW_GID}
deploy_caddy()            # Last — all backends must exist
validate_deployment()     # curl ${LOCALHOST}/health per service
```

---

## The One-Line Test for Correctness

When Windsurf's script 2 is complete, this command should work:

```bash
# Future: spin second isolated stack with ZERO code changes
BASE_DIR=/mnt/data2 \
STACK_USER_UID=3000 \
DOCKER_NETWORK=ai_platform_2 \
DOMAIN_NAME=ai2.datasquiz.net \
bash 2-deploy-services.sh
```

# === Analysis of Windsurf's Revised Plan ===

Windsurf correctly picked up on dynamic variable feedback but then **over-engineered into multi-tenancy prematurely**. Here's the precise assessment:

---

## ✅ What Windsurf Got Right

| Item | Status |
|------|--------|
| `BASE_DIR` variable instead of hardcoded `/mnt/data` | ✅ Correct direction |
| `DOMAIN_NAME` variable | ✅ Correct |
| `LOCALHOST` variable | ✅ Correct |
| Dynamic port variables from `.env` | ✅ Correct |
| AppArmor profiles under tenant path (not `/etc/apparmor.d`) | ✅ Correct intent |

---

## ❌ What Windsurf Got Wrong — Over-Engineering

### Problem 1: Multi-Tenancy Is NOT In Current Scope

```
Windsurf built:                    What was actually asked:
/mnt/data/tenants/tenant-a/   ←→   /mnt/data/         (single stack)
tenant-${TENANT_NAME}.env     ←→   .env                 (one env file)
ai-platform-tenant-a              ←→   ai_platform           (one network)
per-tenant port ranges            ←→   ports from .env       (one set)
```

**The intent expressed was**: *eventually* spin multiple stacks on same machine under different user profiles with dedicated EBS volumes. That's **future architecture**.

**Current scope**: Single stack, single tenant, single `.env` file.

### Problem 2: Breaking Current Scripts

```
Current scripts expect:
${BASE_DIR}/n8n/           ←→   /mnt/data/n8n/
${BASE_DIR}/dify/           ←→   /mnt/data/dify/
${BASE_DIR}/postgres/        ←→   /mnt/data/postgres/

Windsurf's multi-tenant version:
${BASE_DIR}/tenants/tenant-a/n8n/   ←→   BREAKS all existing scripts
${BASE_DIR}/tenants/tenant-a/.env    ←→   BREAKS script 1 env loading
```

### Problem 3: AppArmor Path Issues

```
Windsurf wrote: profiles to ${BASE_DIR}/apparmor/  ←→   Correct location
But then: sed -i "s|/mnt/data|${BASE_DIR}|g" "${profile_dir}/ai-platform-default"

This creates BROKEN AppArmor profiles because:
1. `${BASE_DIR}` is not expanded when written to file
2. The path `/mnt/data/** r,` becomes literal string, not variable substitution
```

**Correct pattern**: Write profiles with literal paths, then copy/symlink to system location.

---

## 🎯 Grounded Implementation Guidance

### **Current Scope: Single Stack, Single Tenant**

Build toward the **correct single-stack architecture** without breaking existing functionality:

```bash
# === Script 1 - Setup & Config ===
# Interactive menu → writes ONE .env manifest
# NO tenant selection - single stack only

# === Script 2 - Deploy Everything ===
source "${BASE_DIR:-/mnt/data}/.env"    # Load the ONE .env
# Use ${BASE_DIR} everywhere - NO tenant directories
# Deploy to ai_network (NOT tenant-specific networks)
# Use STACK_USER_UID=1000:1000 for all services
# Use OPENCLAW_UID=2000:2000 only for OpenClaw

# === Script 3 - Operations ===
# Ops-only functions for the single stack
# NO tenant-aware operations needed

# === Script 4 - Add Service ===
# Add to existing single stack
# NO tenant selection
```

### **The One-Line Test**

When Script 2 is complete, this should work:

```bash
BASE_DIR=/mnt/data \
STACK_USER_UID=1000 \
DOCKER_NETWORK=ai_platform \
DOMAIN_NAME=ai.datasquiz.net \
bash 2-deploy-services.sh
```

If any hardcoded value in the script prevents this from working, it's a bug. **Build toward it now without implementing multi-tenancy.**

---

## 📋 Implementation Priority

### **Phase 1: Fix Current Issues (Week 1)**
1. ✅ **Fix remaining service issues** (n8n, flowise, etc.)
2. ✅ **Get all services working via proxy URLs**
3. ✅ **Ensure dynamic .env variables work correctly**

### **Phase 2: Clean Architecture (Week 1-2)**
1. ✅ **Remove hardcoded values** from all scripts
2. ✅ **Use BASE_DIR variable** everywhere
3. ✅ **Maintain single-stack architecture**

### **Future Multi-Tenancy (Later)**
1. ✅ **Design for extensibility** - don't break current scripts
2. ✅ **Plan migration path** - when ready, implement without breaking existing functionality

---

## 🎯 Key Insight

# === CORRECTED ANALYSIS: Multi-Tenancy Architecture ===

## 🎯 Understanding the Correct Multi-Tenancy Model

You're absolutely right - I missed the key point. Here's the **correct architecture**:

### **Multi-Tenancy Flow**
```
1. New tenant wants AI platform
2. Tenant runs Script 1 (as their own user)
3. Script 1:
   - Mounts dedicated EBS volume for tenant
   - Creates tenant-specific UID/GID (e.g., 1001:1001, 1002:1002, etc.)
   - Sets BASE_DIR to tenant's EBS mount point
   - Generates .env with tenant-specific ports
   - Performs port availability check for tenant's UID
4. Tenant runs Script 2 (as their own user)
5. Script 2 deploys entire stack under tenant's UID/GID
6. Multiple stacks run simultaneously under different UIDs
```

---

## 🏗️ Correct Multi-Tenant Architecture

### **Per-Tenant Isolation**
```bash
# Tenant A (UID 1001:1001) - EBS mounted at /mnt/data-tenant-a
BASE_DIR=/mnt/data-tenant-a
STACK_USER_UID=1001
STACK_USER_GID=1001
DOMAIN_NAME=tenant-a.datasquiz.net
DOCKER_NETWORK=ai-platform-1001
PORT_RANGE_START=5000

# Tenant B (UID 1002:1002) - EBS mounted at /mnt/data-tenant-b  
BASE_DIR=/mnt/data-tenant-b
STACK_USER_UID=1002
STACK_USER_GID=1002
DOMAIN_NAME=tenant-b.datasquiz.net
DOCKER_NETWORK=ai-platform-1002
PORT_RANGE_START=5100

# Tenant C (UID 1003:1003) - EBS mounted at /mnt/data-tenant-c
BASE_DIR=/mnt/data-tenant-c
STACK_USER_UID=1003
STACK_USER_GID=1003
DOMAIN_NAME=tenant-c.datasquiz.net
DOCKER_NETWORK=ai-platform-1003
PORT_RANGE_START=5200
```

### **Directory Structure per Tenant**
```bash
# Each tenant gets their own EBS volume with complete isolation
/mnt/data-tenant-a/          ← Tenant A's EBS volume
├── apparmor/               ← AppArmor profiles for UID 1001
├── config/
│   └── .env                ← Tenant A's configuration
├── data/
│   ├── postgres/
│   ├── n8n/
│   ├── anythingllm/
│   └── ... (all services)
├── logs/
└── ssl/certs/tenant-a.datasquiz.net/

/mnt/data-tenant-b/          ← Tenant B's EBS volume (completely separate)
├── apparmor/               ← AppArmor profiles for UID 1002
├── config/
│   └── .env                ← Tenant B's configuration
├── data/
│   ├── postgres/
│   ├── n8n/
│   ├── anythingllm/
│   └── ... (all services)
└── logs/
```

---

## 🔧 Script 1 - Multi-Tenant Setup

### **Enhanced Script 1 for Multi-Tenancy**
```bash
#!/bin/bash
# Script 1: Multi-Tenant Setup & Configuration

# Get current user's UID/GID
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

# Determine tenant-specific configuration
TENANT_NAME="tenant-${CURRENT_UID}"
BASE_DIR="/mnt/data-${TENANT_NAME}"
DOMAIN_NAME="${TENANT_NAME}.datasquiz.net"

# Assign port range based on UID
PORT_RANGE_START=$((5000 + (CURRENT_UID - 1000) * 100))

# Create tenant directory structure
mkdir -p "${BASE_DIR}/data" "${BASE_DIR}/logs" "${BASE_DIR}/config" "${BASE_DIR}/apparmor"

# Generate tenant-specific .env
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
DOCKER_NETWORK=ai-platform-${CURRENT_UID}

# === Port Configuration ===
PROMETHEUS_PORT=$((PORT_RANGE_START + 0))
GRAFANA_PORT=$((PORT_RANGE_START + 1))
N8N_PORT=$((PORT_RANGE_START + 2))
DIFY_PORT=$((PORT_RANGE_START + 3))
ANYTHINGLLM_PORT=$((PORT_RANGE_START + 4))
LITELLM_PORT=$((PORT_RANGE_START + 5))
OPENWEBUI_PORT=$((PORT_RANGE_START + 6))
MINIO_S3_PORT=$((PORT_RANGE_START + 7))
MINIO_CONSOLE_PORT=$((PORT_RANGE_START + 8))
SIGNAL_PORT=$((PORT_RANGE_START + 9))
OPENCLAW_PORT=$((PORT_RANGE_START + 10))
FLOWISE_PORT=$((PORT_RANGE_START + 11))

# === Vector DB ===
VECTOR_DB=qdrant

# === AppArmor ===
APPARMOR_PROFILE_DIR=${BASE_DIR}/apparmor

# === Tailscale ===
TAILSCALE_AUTH_KEY=
TAILSCALE_HOSTNAME=openclaw-${TENANT_NAME}
EOF

echo "✅ Tenant ${TENANT_NAME} configured"
echo "   UID/GID: ${CURRENT_UID}:${CURRENT_GID}"
echo "   Base Dir: ${BASE_DIR}"
echo "   Domain: ${DOMAIN_NAME}"
echo "   Port Range: ${PORT_RANGE_START}-${PORT_RANGE_START + 99}"
```

---

## 🔧 Script 2 - Multi-Tenant Deployment

### **Tenant-Aware Deployment**
```bash
#!/bin/bash
# Script 2: Multi-Tenant Deployment

# Load tenant configuration
source "${BASE_DIR}/config/.env"

# Set tenant-specific paths
TENANT_DATA="${BASE_DIR}/data"
TENANT_LOGS="${BASE_DIR}/logs"
TENANT_CONFIG="${BASE_DIR}/config"
TENANT_APPARMOR="${BASE_DIR}/apparmor"

# Create tenant directories with correct ownership
mkdir -p "${TENANT_DATA}" "${TENANT_LOGS}" "${TENANT_CONFIG}" "${TENANT_APPARMOR}"
chown -R ${STACK_USER_UID}:${STACK_USER_GID} "${BASE_DIR}"

# Create tenant-specific Docker network
docker network create "${DOCKER_NETWORK}" 2>/dev/null || true

# Set vector DB configuration globally
set_vectordb_config

# Setup tenant-specific AppArmor profiles
setup_tenant_apparmor_profiles

# Deploy all services under tenant's UID/GID
deploy_infrastructure
deploy_ai_services
deploy_openclaw
deploy_caddy
validate_deployment
```

---

## 🛡️ Multi-Tenant AppArmor Profiles

### **Tenant-Specific Security**
```bash
setup_tenant_apparmor_profiles() {
    # Create tenant-specific AppArmor profiles
    cat > "${TENANT_APPARMOR}/ai-platform-default" << 'EOF'
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

    # OpenClaw gets stricter profile
    cat > "${TENANT_APPARMOR}/ai-platform-openclaw" << 'EOF'
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

    # Copy to system location for kernel loading
    cp "${TENANT_APPARMOR}/ai-platform-default" \
       "/etc/apparmor.d/ai-platform-${STACK_USER_UID}"
    cp "${TENANT_APPARMOR}/ai-platform-openclaw" \
       "/etc/apparmor.d/ai-platform-openclaw-${OPENCLAW_UID}"

    # Load profiles
    apparmor_parser -r "/etc/apparmor.d/ai-platform-${STACK_USER_UID}"
    apparmor_parser -r "/etc/apparmor.d/ai-platform-openclaw-${OPENCLAW_UID}"

    echo "✅ AppArmor profiles loaded for tenant ${TENANT_NAME}"
}
```

---

## 🛡️ Multi-Tenant OpenClaw + Tailscale

### **Per-Tenant Isolation**
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

    # Wait for Tailscale to authenticate
    wait_for_tailscale_auth "tailscale-${TENANT_NAME}"

    # Step 2: OpenClaw runs under dedicated UID with strict isolation
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
}
```

---

## 🧹 Multi-Tenant Operations

### **Script 3 - Per-Tenant Management**
```bash
#!/bin/bash
# Script 3: Multi-Tenant Operations

# Load tenant configuration
source "${BASE_DIR}/config/.env"

# Operations work on tenant's specific stack
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
```

---

## 🎯 Multi-Tenant Success Criteria

### **Technical Success**
- ✅ **Complete tenant isolation**: Separate UID/GID, EBS volumes, networks
- ✅ **No cross-tenant access**: AppArmor profiles prevent data leakage
- ✅ **Dynamic configuration**: Script 1 generates tenant-specific .env
- ✅ **Port isolation**: Each tenant gets dedicated port range
- ✅ **Security**: OpenClaw runs under dedicated UID with strict isolation

### **Operational Success**
- ✅ **Scalable**: Unlimited tenants with automatic UID/GID assignment
- ✅ **Isolated operations**: Script 3 works per-tenant
- ✅ **Extensible**: Script 4 adds services to specific tenants
- ✅ **Clean teardown**: Script 0 removes entire tenant stack

### **The Multi-Tenant Test**
```bash
# Tenant A (UID 1001)
su - user1001 -c "bash 1-setup-system.sh && bash 2-deploy-services.sh"

# Tenant B (UID 1002) 
su - user1002 -c "bash 1-setup-system.sh && bash 2-deploy-services.sh"

# Both run simultaneously with complete isolation
```

---

## 🎯 Key Insight

**The correct multi-tenancy model** is:
- **Per-tenant UID/GID** for process isolation
- **Per-tenant EBS volumes** for data isolation  
- **Per-tenant configuration** generated by Script 1
- **Per-tenant networks** for network isolation
- **Per-tenant AppArmor profiles** for security isolation

This allows **multiple AI stacks to run simultaneously** under different users with **complete isolation** while sharing the same host machine.