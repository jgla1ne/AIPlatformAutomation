# AI Platform Automation - Complete Refactoring Plan
**Version:** 102.0.0  
**Date:** 2026-02-09  
**Critical Issue:** Ollama API Timeout in Script 1  
**Root Cause Analysis:** Architecture mismatch between scripts

---

## 🔴 CRITICAL FAILURE ANALYSIS

### The Ollama API Timeout Issue

**Error:**
```
ℹ Waiting for Ollama API...
✗ Ollama API did not respond after 30 attempts
```

**Root Causes Identified:**

1. **Script 1 installs Ollama via curl script** which creates systemd service
2. **Service may be masked or not starting** due to:
   - Missing environment configuration
   - AppArmor blocking (Ubuntu 24.04)
   - Systemd service not properly enabled
   - Port 11434 already in use
   - Service starting but API not binding correctly

3. **Wait function assumes immediate readiness** but Ollama needs:
   - Time to initialize
   - Models to be ready (if pre-pulled)
   - Proper host binding configuration

### Verification Steps Missing:
```bash
# What's NOT being checked:
systemctl status ollama          # Service running?
journalctl -u ollama -n 50       # Service logs?
netstat -tulpn | grep 11434      # Port listening?
curl -v http://localhost:11434   # Connection details?
```

---

## 📊 CURRENT STATE ANALYSIS

### Script 0: Complete Cleanup ✅ GOOD
**File:** `0-complete-cleanup.sh`  
**Version:** v102.0.0  
**Status:** **PRODUCTION READY**

**What it does:**
- Stops all Docker containers with `ai-platform` label
- Removes networks, volumes, images
- Cleans `/opt/ai-platform/` directory
- Preserves essential tools (git, curl, docker)
- Comprehensive verification

**Issues:** None - this script is well-designed

**Recommendation:** ✅ **KEEP AS-IS**

---

### Script 1: System Setup 🔴 BROKEN
**File:** `1-setup-system.sh`  
**Version:** v3.1.0 (your implementation)  
**Status:** **FAILS AT OLLAMA API CHECK**

**Architecture Confusion:**

| What Script 1 SHOULD Do (README) | What It ACTUALLY Does | Problem |
|---|---|---|
| Install Docker | ✅ Does this | Good |
| Install NVIDIA Toolkit | ✅ Does this | Good |
| Install Ollama | ✅ Does this | Good |
| **Configure Ollama systemd** | ❌ **MISSING** | **CRITICAL** |
| **Pull default models** | ❌ **MISSING** | **CRITICAL** |
| **Wait for API properly** | ❌ **FLAWED** | **CRITICAL** |
| Service selection | ❌ **SHOULD NOT DO** | Scope creep |
| Domain config | ❌ **SHOULD NOT DO** | Scope creep |
| API key collection | ❌ **SHOULD NOT DO** | Scope creep |

**Why Ollama API Fails:**

1. **Ollama install script creates service but:**
   ```bash
   # What happens:
   curl -fsSL https://ollama.com/install.sh | sh
   # Creates: /etc/systemd/system/ollama.service
   # But may not:
   # - Configure OLLAMA_HOST=0.0.0.0:11434
   # - Start service immediately
   # - Handle AppArmor restrictions
   ```

2. **Missing configuration override:**
   ```bash
   # MISSING in current Script 1:
   mkdir -p /etc/systemd/system/ollama.service.d
   cat > /etc/systemd/system/ollama.service.d/override.conf << EOF
   [Service]
   Environment="OLLAMA_HOST=0.0.0.0:11434"
   Environment="OLLAMA_ORIGINS=*"
   Environment="OLLAMA_KEEP_ALIVE=5m"
   EOF
   systemctl daemon-reload
   systemctl restart ollama
   ```

3. **Flawed wait logic:**
   ```bash
   # Current wait is too simple:
   while [[ $attempt -lt $max_attempts ]]; do
       if curl -sf http://localhost:11434/api/tags &>/dev/null; then
           return 0
       fi
       sleep 2
   done
   
   # Should be:
   # 1. Check systemctl status first
   # 2. Check logs if failing
   # 3. Verify port binding
   # 4. Then check API
   ```

---

### Script 2: Deploy Services 🟡 MISALIGNED
**File:** `2-deploy-services.sh`  
**Version:** v75.2.2  
**Status:** **WORKS BUT WRONG ARCHITECTURE**

**What it does:**
- Assumes `.env` file exists (created by Script 1)
- Deploys services via `docker-compose.yml`
- Uses phases (databases → storage → proxy → LLM → monitoring)

**Critical Issues:**

1. **Path Mismatch:**
   ```bash
   # Script 2 expects:
   BASE_DIR="/home/$REAL_USER/ai-platform"
   
   # Script 0 cleans:
   /opt/ai-platform/
   
   # README specifies:
   /mnt/data/ai-platform/
   
   # THREE DIFFERENT PATHS!
   ```

2. **Missing .env Generation:**
   - Script 2 ASSUMES `.env` exists
   - Script 1 doesn't generate it properly
   - No interactive questionnaire

3. **No docker-compose.yml Generation:**
   - Script 2 assumes it exists
   - Who creates it? Nobody!

4. **Service Deployment Order:**
   ```bash
   # Current: postgres → redis → qdrant → minio → caddy → ollama → litellm
   # Problem: Ollama is containerized here, but Script 1 installed it as systemd
   # CONFLICT: Two Ollama installations!
   ```

---

### Script 3: Configure Services 🟡 INCOMPLETE
**File:** `3-configure-services.sh`  
**Version:** Unknown  
**Status:** **SKELETON ONLY**

**What it does:**
- Configures Tailscale
- Sets up Google Drive rclone
- Creates systemd timers for sync
- Configures LiteLLM routing

**Missing:**
- Dify admin account creation
- N8N workflow setup
- Open WebUI model connections
- API endpoint validation

---

### Script 4: Add Service 🔴 MISSING
**File:** `4-add-service.sh`  
**Version:** Not found  
**Status:** **DOESN'T EXIST**

---

## 🎯 ARCHITECTURAL DECISION: README vs REALITY

### README Architecture (v76.3.0)
```
ROOT: /mnt/data/ai-platform/
├── config/          # All .env, .yaml configs
├── docker/          # docker-compose.*.yml (ONE PER SERVICE)
├── data/            # Persistent volumes
├── logs/            # Script logs
├── scripts/         # Convenience scripts
└── backups/         # Backup files

Ollama: systemd service on host (NOT containerized)
Docker: External networks created before services
Config: master.env + per-service env files
```

### Current Implementation Reality
```
Multiple paths:
- /opt/ai-platform/           (Script 0)
- /home/$USER/ai-platform/    (Script 2)
- /mnt/data/ai-platform/      (My v4.0.0)

Ollama: Installed TWICE (systemd + container)
Config: Partial .env in Script 1, assumed in Script 2
Docker: Monolithic docker-compose.yml (not per-service)
```

---

## 🔧 COMPLETE REFACTORING PLAN

### Decision: **Follow README v76.3.0 Architecture**

**Why:**
1. Most complete specification
2. Modular per-service approach
3. Clear separation of concerns
4. Proper Ollama as systemd (not containerized)
5. Documented in 76 version iterations

---

## 📋 SCRIPT 0: No Changes Needed ✅

**Current v102.0.0 is GOOD**

Only update paths to align:
```bash
# Change:
local base_dir="/opt/ai-platform"

# To:
local base_dir="/mnt/data/ai-platform"
```

---

## 📋 SCRIPT 1: Complete Rewrite Required 🔴

### Script 1 v5.0.0 - System Setup ONLY

**Single Responsibility:** Prepare system for deployment

**Phases:**

#### Phase 1: Hardware Detection & Profiling
```bash
detect_hardware() {
    # CPU: cores, model
    # RAM: total GB
    # Disk: free GB, total GB, type (SSD/HDD)
    # GPU: model, VRAM MB, driver version
}

classify_system_tier() {
    if [[ GPU_VRAM >= 16000 && RAM >= 32 ]]; then
        TIER="performance"
        MODELS="llama3.1:8b,nomic-embed-text,codellama:13b"
    elif [[ GPU_VRAM >= 6000 && RAM >= 16 ]]; then
        TIER="standard"
        MODELS="llama3.1:8b,nomic-embed-text"
    else
        TIER="minimal"
        MODELS="llama3.2:3b,nomic-embed-text"
    fi
}

write_hardware_profile() {
    cat > ${ROOT_PATH}/config/hardware-profile.env << EOF
CPU_CORES=${CPU_CORES}
CPU_MODEL="${CPU_MODEL}"
TOTAL_RAM_GB=${TOTAL_RAM_GB}
DISK_FREE_GB=${DISK_FREE_GB}
DISK_TOTAL_GB=${DISK_TOTAL_GB}
DISK_TYPE=${DISK_TYPE}
GPU_AVAILABLE=${GPU_AVAILABLE}
GPU_MODEL="${GPU_MODEL}"
GPU_VRAM_MB=${GPU_VRAM_MB}
GPU_DRIVER_VERSION="${GPU_DRIVER_VERSION}"
SYSTEM_TIER=${SYSTEM_TIER}
DEFAULT_MODELS="${DEFAULT_MODELS}"
EOF
}
```

#### Phase 2: Docker Installation
```bash
install_docker() {
    # Remove conflicting packages
    apt-get remove -y docker.io docker-doc docker-compose podman-docker
    
    # Add Docker GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Add repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list
    
    # Install
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
    
    # Configure daemon
    cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "default-address-pools": [{
    "base": "172.20.0.0/14",
    "size": 24
  }]
}
EOF
    
    systemctl enable docker
    systemctl start docker
}
```

#### Phase 3: NVIDIA Container Toolkit
```bash
install_nvidia_toolkit() {
    [[ "${GPU_AVAILABLE}" != "true" ]] && return 0
    
    # Verify driver
    nvidia-smi || {
        log_error "Install NVIDIA driver first: sudo apt install nvidia-driver-535"
        exit 1
    }
    
    # Add repo
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    apt-get update
    apt-get install -y nvidia-container-toolkit
    
    # Configure Docker
    nvidia-ctk runtime configure --runtime=docker
    systemctl restart docker
    
    # Test
    docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi
}
```

#### Phase 4: Ollama Installation (FIXED)
```bash
install_ollama() {
    # Install via official script
    curl -fsSL https://ollama.com/install.sh | sh
    
    # CRITICAL FIX: Configure systemd override
    mkdir -p /etc/systemd/system/ollama.service.d
    
    cat > /etc/systemd/system/ollama.service.d/override.conf << EOF
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_ORIGINS=*"
Environment="OLLAMA_KEEP_ALIVE=5m"
EOF
    
    # Handle AppArmor (Ubuntu 24.04)
    if command -v aa-status &>/dev/null && aa-status --enabled 2>/dev/null; then
        cat > /etc/apparmor.d/usr.local.bin.ollama << 'EOF'
#include <tunables/global>
/usr/local/bin/ollama flags=(unconfined) {
    userns,
}
EOF
        apparmor_parser -r /etc/apparmor.d/usr.local.bin.ollama
    fi
    
    # Enable and start
    systemctl daemon-reload
    systemctl enable ollama
    systemctl start ollama
    
    # BETTER WAIT LOGIC
    wait_for_ollama
}

wait_for_ollama() {
    log_info "Waiting for Ollama service..."
    
    local max_attempts=30
    local attempt=0
    
    # First, verify systemd service is running
    for ((i=0; i<10; i++)); do
        if systemctl is-active --quiet ollama; then
            log_success "Ollama systemd service is active"
            break
        fi
        sleep 1
    done
    
    if ! systemctl is-active --quiet ollama; then
        log_error "Ollama service failed to start"
        log_error "Check logs: journalctl -u ollama -n 50"
        systemctl status ollama
        exit 1
    fi
    
    # Check port binding
    log_info "Verifying port 11434 is listening..."
    for ((i=0; i<10; i++)); do
        if netstat -tuln | grep -q ':11434'; then
            log_success "Port 11434 is open"
            break
        fi
        sleep 1
    done
    
    # Now check API
    log_info "Waiting for Ollama API..."
    while [[ ${attempt} -lt ${max_attempts} ]]; do
        if curl -sf http://localhost:11434/api/tags &>/dev/null; then
            log_success "Ollama API is responding"
            return 0
        fi
        
        # Show progress
        if [[ $((attempt % 5)) -eq 0 ]]; then
            log_info "API check ${attempt}/${max_attempts}..."
        fi
        
        attempt=$((attempt + 1))
        sleep 2
    done
    
    # Failure diagnostics
    log_error "Ollama API did not respond after ${max_attempts} attempts"
    log_error "Service status:"
    systemctl status ollama
    log_error "Last 20 lines of logs:"
    journalctl -u ollama -n 20 --no-pager
    log_error "Port check:"
    netstat -tuln | grep 11434 || echo "Port 11434 not listening"
    exit 1
}
```

#### Phase 5: Model Pull
```bash
pull_ollama_models() {
    log_section "Pulling Ollama Models (tier: ${SYSTEM_TIER})"
    
    IFS=',' read -ra MODELS <<< "${DEFAULT_MODELS}"
    
    for model in "${MODELS[@]}"; do
        model=$(echo "${model}" | xargs)
        
        if ollama list 2>/dev/null | grep -q "^${model}"; then
            log_success "Model ${model} already available"
            continue
        fi
        
        log_info "Pulling ${model}..."
        if ollama pull "${model}"; then
            log_success "Model ${model} pulled successfully"
        else
            log_warning "Failed to pull ${model} — continuing"
        fi
    done
    
    log_info "Available models:"
    ollama list
}
```

#### Phase 6: Validation
```bash
validate_system() {
    local errors=0
    
    # Docker
    docker info &>/dev/null || ((errors++))
    docker compose version &>/dev/null || ((errors++))
    
    # GPU (if detected)
    if [[ "${GPU_AVAILABLE}" == "true" ]]; then
        docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi &>/dev/null || ((errors++))
    fi
    
    # Ollama
    systemctl is-active --quiet ollama || ((errors++))
    curl -sf http://localhost:11434/api/tags &>/dev/null || ((errors++))
    
    # Models
    local model_count=$(ollama list 2>/dev/null | tail -n +2 | wc -l)
    [[ ${model_count} -gt 0 ]] || log_warning "No models pulled"
    
    # Hardware profile
    [[ -f "${CONFIG_PATH}/hardware-profile.env" ]] || ((errors++))
    
    if [[ ${errors} -gt 0 ]]; then
        log_error "Validation failed with ${errors} errors"
        exit 1
    fi
    
    log_success "System validation passed"
}
```

**Output:**
- ✅ Docker Engine installed
- ✅ NVIDIA Container Toolkit (if GPU)
- ✅ Ollama systemd service running
- ✅ Default models pulled
- ✅ `hardware-profile.env` written

**Does NOT:**
- ❌ Ask about services
- ❌ Collect domain/SSL
- ❌ Collect API keys
- ❌ Generate .env
- ❌ Generate docker-compose files

---

## 📋 SCRIPT 2: Complete Rewrite Required 🔴

### Script 2 v5.0.0 - Platform Deployment

**Single Responsibility:** Interactive questionnaire + config generation + container deployment

**Phases:**

#### Phase 1: Pre-flight Checks
```bash
preflight_checks() {
    # Verify Script 1 completed
    [[ -f "${CONFIG_PATH}/hardware-profile.env" ]] || {
        log_error "Run 1-setup-system.sh first"
        exit 1
    }
    
    # Load hardware profile
    source "${CONFIG_PATH}/hardware-profile.env"
    
    # Verify Docker
    docker info &>/dev/null || exit 1
    
    # Verify Ollama
    systemctl is-active --quiet ollama || exit 1
    curl -sf http://localhost:11434/api/tags &>/dev/null || exit 1
}
```

#### Phase 2: Interactive Questionnaire
```bash
run_questionnaire() {
    log_section "Platform Configuration"
    
    # Network
    detect_ip
    read -p "Domain name or IP [${DETECTED_IP}]: " DOMAIN_NAME
    DOMAIN_NAME=${DOMAIN_NAME:-${DETECTED_IP}}
    
    # SSL mode
    if [[ "${DOMAIN_NAME}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        SSL_MODE="selfsigned"
    else
        echo "SSL mode: 1) Let's Encrypt  2) Self-signed  3) None"
        read -p "Choice [1]: " ssl_choice
        case ${ssl_choice:-1} in
            1) SSL_MODE="letsencrypt" ;;
            2) SSL_MODE="selfsigned" ;;
            3) SSL_MODE="none" ;;
        esac
    fi
    
    # Admin credentials
    read -p "Admin email: " ADMIN_EMAIL
    read -sp "Admin password: " ADMIN_PASSWORD
    echo
    
    # API keys (optional)
    read -sp "OpenAI API key (optional): " OPENAI_API_KEY
    echo
    read -sp "Anthropic API key (optional): " ANTHROPIC_API_KEY
    echo
    
    # Service selection
    echo "Core services (required):"
    echo "  ✓ LiteLLM (AI Gateway)"
    echo "  ✓ Open WebUI"
    echo "  ✓ PostgreSQL, Redis, Qdrant"
    echo
    echo "Optional services:"
    read -p "Install Dify? [y/N]: " ENABLE_DIFY
    read -p "Install N8N? [y/N]: " ENABLE_N8N
    read -p "Install Flowise? [y/N]: " ENABLE_FLOWISE
    read -p "Install Monitoring (Prometheus/Grafana)? [Y/n]: " ENABLE_MONITORING
    
    # Confirmation
    echo
    echo "Summary:"
    echo "  Domain: ${DOMAIN_NAME}"
    echo "  SSL: ${SSL_MODE}"
    echo "  System: ${SYSTEM_TIER}"
    read -p "Proceed? [Y/n]: " confirm
    [[ "${confirm}" =~ ^[Nn]$ ]] && exit 0
}
```

#### Phase 3: Credential Generation
```bash
generate_credentials() {
    # Auto-generate all passwords
    POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=')
    REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=')
    QDRANT_API_KEY=$(openssl rand -base64 32 | tr -d '/+=')
    DIFY_SECRET_KEY=$(openssl rand -hex 32)
    N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
    LITELLM_MASTER_KEY="sk-litellm-$(openssl rand -base64 24 | tr -d '/+=')"
    
    # Save to credentials file
    cat > "${CONFIG_PATH}/credentials.env" << EOF
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
QDRANT_API_KEY=${QDRANT_API_KEY}
DIFY_SECRET_KEY=${DIFY_SECRET_KEY}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
EOF
    chmod 600 "${CONFIG_PATH}/credentials.env"
}
```

#### Phase 4: master.env Generation
```bash
generate_master_env() {
    HOST_IP=$(hostname -I | awk '{print $1}')
    
    cat > "${CONFIG_PATH}/master.env" << EOF
# AI Platform Master Configuration
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Paths
ROOT_PATH=/mnt/data/ai-platform
CONFIG_PATH=/mnt/data/ai-platform/config
DOCKER_PATH=/mnt/data/ai-platform/docker
DATA_PATH=/mnt/data/ai-platform/data

# Network
DOMAIN_NAME=${DOMAIN_NAME}
HOST_IP=${HOST_IP}
SSL_MODE=${SSL_MODE}

# Hardware (from Script 1)
SYSTEM_TIER=${SYSTEM_TIER}
GPU_AVAILABLE=${GPU_AVAILABLE}
CPU_CORES=${CPU_CORES}
TOTAL_RAM_GB=${TOTAL_RAM_GB}

# Admin
ADMIN_EMAIL=${ADMIN_EMAIL}
ADMIN_PASSWORD=${ADMIN_PASSWORD}

# PostgreSQL
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_USER=postgres
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=${REDIS_PASSWORD}

# Qdrant
QDRANT_HOST=qdrant
QDRANT_PORT=6333
QDRANT_API_KEY=${QDRANT_API_KEY}

# Ollama (systemd service on host)
OLLAMA_HOST=${HOST_IP}
OLLAMA_PORT=11434
OLLAMA_BASE_URL=http://${HOST_IP}:11434

# LiteLLM
LITELLM_HOST=litellm
LITELLM_PORT=4000
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}

# API Keys (optional)
OPENAI_API_KEY=${OPENAI_API_KEY:-}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}

# Service Flags
ENABLE_DIFY=${ENABLE_DIFY:-false}
ENABLE_N8N=${ENABLE_N8N:-false}
ENABLE_FLOWISE=${ENABLE_FLOWISE:-false}
ENABLE_MONITORING=${ENABLE_MONITORING:-true}
EOF
}
```

#### Phase 5: Docker Compose Generation (Per-Service)
```bash
generate_compose_postgres() {
    cat > "${DOCKER_PATH}/docker-compose.postgres.yml" << 'EOF'
services:
  postgres:
    image: postgres:16-alpine
    container_name: postgres
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ai_platform
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ${CONFIG_PATH}/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    networks:
      - ai-backend
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

volumes:
  postgres_data:

networks:
  ai-backend:
    external: true
EOF
}

generate_compose_litellm() {
    cat > "${DOCKER_PATH}/docker-compose.litellm.yml" << 'EOF'
services:
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm
    environment:
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
      DATABASE_URL: postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/litellm
      OLLAMA_API_BASE: ${OLLAMA_BASE_URL}
      OPENAI_API_KEY: ${OPENAI_API_KEY}
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
    volumes:
      - ${CONFIG_PATH}/litellm/config.yaml:/app/config.yaml:ro
    networks:
      - ai-platform
      - ai-backend
    ports:
      - "4000:4000"
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    restart: unless-stopped

networks:
  ai-platform:
    external: true
  ai-backend:
    external: true
EOF
}

# Similar for all services...
```

#### Phase 6: LiteLLM Config Generation
```bash
generate_litellm_config() {
    cat > "${CONFIG_PATH}/litellm/config.yaml" << EOF
model_list:
  # Ollama (local)
  - model_name: llama3.1
    litellm_params:
      model: ollama/llama3.1:8b
      api_base: ${OLLAMA_BASE_URL}
  
  - model_name: nomic-embed-text
    litellm_params:
      model: ollama/nomic-embed-text
      api_base: ${OLLAMA_BASE_URL}
EOF

    if [[ -n "${OPENAI_API_KEY}" ]]; then
        cat >> "${CONFIG_PATH}/litellm/config.yaml" << EOF

  # OpenAI
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: ${OPENAI_API_KEY}
EOF
    fi

    if [[ -n "${ANTHROPIC_API_KEY}" ]]; then
        cat >> "${CONFIG_PATH}/litellm/config.yaml" << EOF

  # Anthropic
  - model_name: claude-sonnet-4
    litellm_params:
      model: anthropic/claude-sonnet-4-20250514
      api_key: ${ANTHROPIC_API_KEY}
EOF
    fi

    cat >> "${CONFIG_PATH}/litellm/config.yaml" << 'EOF'

litellm_settings:
  drop_params: true
  set_verbose: false
  cache: true
  cache_params:
    type: redis
    host: ${REDIS_HOST}
    port: ${REDIS_PORT}
    password: ${REDIS_PASSWORD}

general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  database_url: "postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/litellm"
EOF
}
```

#### Phase 7: Network Creation
```bash
create_docker_networks() {
    docker network create ai-platform --driver bridge 2>/dev/null || true
    docker network create ai-backend --driver bridge 2>/dev/null || true
}
```

#### Phase 8: Service Deployment
```bash
deploy_services() {
    log_section "Deploying Services"
    
    # Create networks first
    create_docker_networks
    
    # Deploy infrastructure tier
    log_info "Deploying infrastructure tier..."
    docker compose -f "${DOCKER_PATH}/docker-compose.postgres.yml" up -d
    docker compose -f "${DOCKER_PATH}/docker-compose.redis.yml" up -d
    docker compose -f "${DOCKER_PATH}/docker-compose.qdrant.yml" up -d
    
    # Wait for health
    wait_for_service "postgres" "pg_isready"
    wait_for_service "redis" "redis-cli ping"
    
    # Deploy AI tier
    log_info "Deploying AI tier..."
    docker compose -f "${DOCKER_PATH}/docker-compose.litellm.yml" up -d
    docker compose -f "${DOCKER_PATH}/docker-compose.open-webui.yml" up -d
    
    # Optional services
    if [[ "${ENABLE_DIFY}" == "true" ]]; then
        docker compose -f "${DOCKER_PATH}/docker-compose.dify.yml" up -d
    fi
    
    if [[ "${ENABLE_N8N}" == "true" ]]; then
        docker compose -f "${DOCKER_PATH}/docker-compose.n8n.yml" up -d
    fi
    
    # Monitoring
    if [[ "${ENABLE_MONITORING}" == "true" ]]; then
        docker compose -f "${DOCKER_PATH}/docker-compose.prometheus.yml" up -d
        docker compose -f "${DOCKER_PATH}/docker-compose.grafana.yml" up -d
    fi
    
    # Reverse proxy (last)
    docker compose -f "${DOCKER_PATH}/docker-compose.caddy.yml" up -d
}
```

**Output:**
- ✅ All configs generated in `/mnt/data/ai-platform/config/`
- ✅ Per-service docker-compose files in `/mnt/data/ai-platform/docker/`
- ✅ All containers running
- ✅ Networks created
- ✅ Services healthy

---

## 📋 SCRIPT 3: Focused Rewrite 🟡

### Script 3 v5.0.0 - Service Configuration

**Single Responsibility:** Configure running services via APIs

**Phases:**

#### Phase 1: Wait for Services
```bash
wait_for_all_services() {
    log_section "Waiting for Services to be Healthy"
    
    local services=(
        "postgres:5432"
        "redis:6379"
        "litellm:4000"
        "open-webui:8080"
    )
    
    [[ "${ENABLE_DIFY}" == "true" ]] && services+=("dify-api:5001")
    [[ "${ENABLE_N8N}" == "true" ]] && services+=("n8n:5678")
    
    for svc in "${services[@]}"; do
        local name="${svc%:*}"
        local port="${svc#*:}"
        wait_for_service "${name}" "${port}"
    done
}
```

#### Phase 2: Configure Dify
```bash
configure_dify() {
    [[ "${ENABLE_DIFY}" != "true" ]] && return 0
    
    log_info "Configuring Dify..."
    
    # Create admin account
    curl -X POST http://localhost:5001/console/api/setup \
        -H "Content-Type: application/json" \
        -d '{
            "email": "'"${ADMIN_EMAIL}"'",
            "password": "'"${ADMIN_PASSWORD}"'",
            "name": "Admin"
        }'
    
    # Connect model providers
    # Add Ollama models
    # Configure embeddings
}
```

#### Phase 3: Configure N8N
```bash
configure_n8n() {
    [[ "${ENABLE_N8N}" != "true" ]] && return 0
    
    log_info "Configuring N8N..."
    
    # Set admin credentials
    # Import default workflows (if any)
}
```

#### Phase 4: Validate Integrations
```bash
validate_integrations() {
    # Test LiteLLM → Ollama connection
    curl -X POST http://localhost:4000/v1/chat/completions \
        -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "llama3.1",
            "messages": [{"role": "user", "content": "test"}]
        }'
    
    # Test Open WebUI → LiteLLM
    # Test Dify → LiteLLM (if enabled)
}
```

---

## 📋 SCRIPT 4: New Implementation Required 🔴

### Script 4 v5.0.0 - Add Services

**Single Responsibility:** Add optional services post-deployment

```bash
#!/usr/bin/env bash
# Script 4: Add Optional Services

add_service_menu() {
    echo "Available Services:"
    echo "  1) Flowise (Visual LLM Flow Builder)"
    echo "  2) MLflow (ML Experiment Tracking)"
    echo "  3) JupyterHub (Notebooks)"
    echo "  4) Milvus (Alternative Vector DB)"
    echo "  5) Custom service from compose file"
    echo "  6) Exit"
    
    read -p "Select service [1-6]: " choice
    
    case ${choice} in
        1) add_flowise ;;
        2) add_mlflow ;;
        3) add_jupyterhub ;;
        4) add_milvus ;;
        5) add_custom ;;
        6) exit 0 ;;
    esac
}

add_flowise() {
    # Generate docker-compose.flowise.yml
    # Deploy
    # Configure
}
```

---

## 🎯 IMPLEMENTATION TIMELINE

### Week 1: Core Fix
- [ ] **Day 1:** Fix Script 1 Ollama installation (Phases 4-6)
- [ ] **Day 2:** Test Script 1 on clean Ubuntu 24.04
- [ ] **Day 3:** Update Script 0 path to `/mnt/data/ai-platform`
- [ ] **Day 4:** Begin Script 2 questionnaire
- [ ] **Day 5:** Complete Script 2 credential generation

### Week 2: Complete Deployment
- [ ] **Day 6:** Script 2 config file generation
- [ ] **Day 7:** Script 2 per-service docker-compose files
- [ ] **Day 8:** Script 2 deployment logic
- [ ] **Day 9:** Test complete 0→1→2 flow
- [ ] **Day 10:** Bug fixes

### Week 3: Configuration & Extension
- [ ] **Day 11:** Script 3 service configuration
- [ ] **Day 12:** Script 3 API integrations
- [ ] **Day 13:** Script 4 add-service menu
- [ ] **Day 14:** End-to-end testing
- [ ] **Day 15:** Documentation update

---

## 🚨 IMMEDIATE FIX FOR OLLAMA ISSUE

### Quick Patch for Current Script 1

Add this BEFORE `wait_for_ollama()`:

```bash
# CRITICAL FIX: Configure Ollama systemd
configure_ollama_systemd() {
    log_info "Configuring Ollama systemd service..."
    
    # Create override directory
    mkdir -p /etc/systemd/system/ollama.service.d
    
    # Create override configuration
    cat > /etc/systemd/system/ollama.service.d/override.conf << 'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_ORIGINS=*"
Environment="OLLAMA_KEEP_ALIVE=5m"
EOF
    
    # Reload and restart
    systemctl daemon-reload
    systemctl restart ollama
    
    # Give it time to start
    sleep 5
    
    log_success "Ollama systemd configured"
}

# Add AppArmor fix
fix_apparmor_for_ollama() {
    if ! command -v aa-status &>/dev/null; then
        return 0
    fi
    
    if ! aa-status --enabled 2>/dev/null; then
        return 0
    fi
    
    log_info "Configuring AppArmor for Ollama..."
    
    cat > /etc/apparmor.d/usr.local.bin.ollama << 'EOF'
#include <tunables/global>

/usr/local/bin/ollama flags=(unconfined) {
    userns,
}
EOF
    
    apparmor_parser -r /etc/apparmor.d/usr.local.bin.ollama 2>/dev/null || true
}

# Then in install_ollama(), add AFTER the curl install:
install_ollama() {
    # ... existing curl install ...
    
    configure_ollama_systemd  # ADD THIS
    fix_apparmor_for_ollama   # ADD THIS
    
    wait_for_ollama
}
```

### Enhanced wait_for_ollama():

```bash
wait_for_ollama() {
    log_info "Verifying Ollama installation..."
    
    # Step 1: Check systemd service
    log_info "Step 1/3: Checking systemd service..."
    for i in {1..10}; do
        if systemctl is-active --quiet ollama; then
            log_success "Ollama service is active"
            break
        fi
        [[ $i -eq 10 ]] && {
            log_error "Ollama service failed to start"
            systemctl status ollama --no-pager
            journalctl -u ollama -n 30 --no-pager
            exit 1
        }
        sleep 1
    done
    
    # Step 2: Check port binding
    log_info "Step 2/3: Checking port 11434..."
    for i in {1..10}; do
        if ss -tuln | grep -q ':11434'; then
            log_success "Port 11434 is listening"
            break
        fi
        [[ $i -eq 10 ]] && {
            log_error "Port 11434 not bound"
            ss -tuln | grep 11434 || echo "No process on port 11434"
            exit 1
        }
        sleep 1
    done
    
    # Step 3: Check API
    log_info "Step 3/3: Checking API response..."
    local max_attempts=30
    for attempt in $(seq 1 ${max_attempts}); do
        if curl -sf http://localhost:11434/api/tags &>/dev/null; then
            log_success "Ollama API is responding"
            return 0
        fi
        
        [[ $((attempt % 5)) -eq 0 ]] && log_info "Attempt ${attempt}/${max_attempts}..."
        sleep 2
    done
    
    # Complete failure diagnostics
    log_error "Ollama API timeout after ${max_attempts} attempts"
    echo ""
    log_error "=== DIAGNOSTICS ==="
    echo "Service status:"
    systemctl status ollama --no-pager
    echo ""
    echo "Last 30 log lines:"
    journalctl -u ollama -n 30 --no-pager
    echo ""
    echo "Port check:"
    ss -tuln | grep 11434 || echo "Port 11434 not listening"
    echo ""
    echo "Process check:"
    ps aux | grep ollama
    echo ""
    echo "Test connection:"
    curl -v http://localhost:11434/api/tags
    
    exit 1
}
```

---

## 📝 TESTING CHECKLIST

### Script 0 ✅
- [ ] Cleans `/mnt/data/ai-platform/` (updated path)
- [ ] Removes Docker containers with label
- [ ] Removes networks and volumes
- [ ] Preserves Docker, git, curl
- [ ] Shows summary

### Script 1 🔴
- [ ] Detects hardware correctly
- [ ] Classifies tier (minimal/standard/performance)
- [ ] Installs Docker + Compose
- [ ] Installs NVIDIA toolkit (if GPU)
- [ ] Installs Ollama with systemd override
- [ ] Configures AppArmor
- [ ] **Service starts successfully**
- [ ] **Port 11434 listens**
- [ ] **API responds within 60s**
- [ ] Pulls default models
- [ ] Writes `hardware-profile.env`
- [ ] Passes validation

### Script 2 🔴
- [ ] Reads `hardware-profile.env`
- [ ] Runs interactive questionnaire
- [ ] Generates all credentials
- [ ] Generates `master.env`
- [ ] Generates per-service compose files
- [ ] Generates LiteLLM config
- [ ] Generates Prometheus/Grafana configs
- [ ] Creates Docker networks
- [ ] Deploys all services
- [ ] All containers healthy

### Script 3 🟡
- [ ] Waits for all services
- [ ] Configures Dify (if enabled)
- [ ] Configures N8N (if enabled)
- [ ] Validates LiteLLM → Ollama connection
- [ ] Validates integrations

### Script 4 🔴
- [ ] Shows service menu
- [ ] Deploys optional services
- [ ] Integrates with existing platform

---

## 🎯 SUCCESS CRITERIA

**Platform is COMPLETE when:**

1. ✅ User runs `sudo ./0-complete-cleanup.sh` → system clean
2. ✅ User runs `sudo ./1-setup-system.sh` → Docker, NVIDIA, **Ollama API responds**, models pulled
3. ✅ User runs `sudo ./2-deploy-services.sh` → answers questions → ALL containers running
4. ✅ User runs `sudo ./3-configure-services.sh` → services configured via APIs
5. ✅ User can access:
   - `http://localhost:4000/docs` (LiteLLM)
   - `http://localhost:8080` (Open WebUI)
   - `http://localhost:11434/api/tags` (Ollama)
6. ✅ User can send chat request through LiteLLM → Ollama
7. ✅ Zero manual configuration required

---

## 📦 DELIVERABLES

### This Analysis Document ✅
**File:** `COMPLETE_REFACTORING_PLAN.md`

### Updated Scripts (To Create)
1. **`1-setup-system-v5.0.0.sh`** - Fixed Ollama installation
2. **`2-deploy-services-v5.0.0.sh`** - Complete rewrite
3. **`3-configure-services-v5.0.0.sh`** - API configuration
4. **`4-add-service-v5.0.0.sh`** - New implementation
5. **`0-complete-cleanup-v5.0.0.sh`** - Path fix only

### Migration Guide
**File:** `MIGRATION_v4_to_v5.md`

---

## 🚀 NEXT STEPS

1. **IMMEDIATE:** Apply Ollama fix to current Script 1
2. **Day 1-2:** Test fixed Script 1 on clean VM
3. **Day 3-5:** Implement Script 2 v5.0.0
4. **Day 6-8:** Implement Script 3 v5.0.0
5. **Day 9:** End-to-end testing
6. **Day 10:** Release v5.0.0

---

**Document Version:** 1.0.0  
**Status:** Ready for Implementation  
**Estimated Effort:** 10 days (80 hours)  
**Risk Level:** Medium-High (major refactor)  
**Compatibility:** Breaking changes (v4 → v5)
