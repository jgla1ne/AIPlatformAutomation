# AI PLATFORM DEPLOYMENT — COMPLETE REFERENCE v76.3.0

> **Document Version:** 76.3.0
> **Date:** 2025-01-27
> **Compatibility:** Ubuntu 24.04 LTS (Noble Numbat)
> **Architecture:** Single-node, Docker-based, GPU-optional
> **Script Flow:** 0-cleanup → 1-setup → 2-deploy → 3-configure → 4-add

---

## Table of Contents

### Part 1 — Architecture & Foundation
- [Section 1: Architecture Overview](#section-1-architecture-overview)
- [Section 2: Design Philosophy](#section-2-design-philosophy)
- [Section 3: Prerequisites & Assumptions](#section-3-prerequisites-assumptions)
- [Section 4: Script Inventory & Flow](#section-4-script-inventory--flow)

### Part 2 — Script 0: Cleanup
- [Section 5: Script 0 — Cleanup System](#section-5-script-0--cleanup-system)

### Part 3 — Script 1: System Setup
- [Section 6: Script 1 — Structure & Phases](#section-6-script-1--structure--phases)
- [Section 7: Phase 1 — Hardware Detection & Profiling](#section-7-phase-1--hardware-detection--profiling)
- [Section 8: Phase 2 — Docker Engine Installation](#section-8-phase-2--docker-engine-installation)
- [Section 9: Phase 3 — NVIDIA Container Toolkit](#section-9-phase-3--nvidia-container-toolkit)
- [Section 10: Phase 4 — Ollama Installation & Model Pull](#section-10-phase-4--ollama-installation--model-pull)
- [Section 11: Phase 5 — Validation & Handoff](#section-11-phase-5--validation--handoff)

### Part 4 — Script 2: Deploy Platform
- [Section 12: Script 2 — Structure & Phases](#section-12-script-2--structure--phases)
- [Section 13: Phase 1 — Interactive Questionnaire](#section-13-phase-1--interactive-questionnaire)
- [Section 14: Phase 2 — Credential Generation](#section-14-phase-2--credential-generation)
- [Section 15: Phase 3 — master.env Generation](#section-15-phase-3--masterenv-generation)
- [Section 16: Phase 4 — Service Environment Files](#section-16-phase-4--service-environment-files)
- [Section 17: Phase 5 — PostgreSQL Initialization](#section-17-phase-5--postgresql-initialization)
- [Section 18: Phase 6 — Redis Configuration](#section-18-phase-6--redis-configuration)
- [Section 19: Phase 7 — LiteLLM Configuration](#section-19-phase-7--litellm-configuration)
- [Section 20: Phase 8 — Dify Configuration Files](#section-20-phase-8--dify-configuration-files)
- [Section 21: Phase 9 — Docker Compose Files (per service)](#section-21-phase-9--docker-compose-files-per-service)
- [Section 22: Phase 10 — Caddyfile Generation](#section-22-phase-10--caddyfile-generation)
- [Section 23: Phase 11 — Monitoring Stack Configuration](#section-23-phase-11--monitoring-stack-configuration)
- [Section 24: Phase 12 — Convenience Scripts](#section-24-phase-12--convenience-scripts)
- [Section 25: Phase 13 — Deploy All Services](#section-25-phase-13--deploy-all-services)

### Part 5 — Script 3: Configure Services
- [Section 26: Script 3 — Structure & Phases](#section-26-script-3--structure--phases)
- [Section 27: Phase 1 — Wait for All Services Healthy](#section-27-phase-1--wait-for-all-services-healthy)
- [Section 28: Phase 2 — Configure Dify via API](#section-28-phase-2--configure-dify-via-api)
- [Section 29: Phase 3 — Configure n8n via API](#section-29-phase-3--configure-n8n-via-api)
- [Section 30: Phase 4 — Configure OpenWebUI](#section-30-phase-4--configure-openwebui)
- [Section 31: Phase 5 — Validate All Integrations](#section-31-phase-5--validate-all-integrations)

### Part 6 — Script 4: Add Services
- [Section 32: Script 4 — Structure & Purpose](#section-32-script-4--structure--purpose)

### Part 7 — Reference Material
- [Section 33: Complete File Manifest](#section-33-complete-file-manifest)
- [Section 34: Environment Variable Reference](#section-34-environment-variable-reference)
- [Section 35: Port Map](#section-35-port-map)
- [Section 36: Post-Deployment Verification Checklist](#section-36-post-deployment-verification-checklist)
- [Section 37: Architecture Diagram](#section-37-architecture-diagram)

---

## Section 1: Architecture Overview

### 1.1 Platform Components

The AI Platform deploys the following services on a single Ubuntu 24.04 node:

| Layer | Service | Purpose | Container Name |
|-------|---------|---------|----------------|
| **Reverse Proxy** | Caddy 2 | HTTPS termination, routing, auto-TLS | `caddy` |
| **AI Gateway** | LiteLLM | Unified API gateway for all LLM providers | `litellm` |
| **AI Runtime** | Ollama | Local model inference (GPU/CPU) | System service (not containerized) |
| **AI Platform** | Dify | AI application builder (API + Web + Worker + Sandbox) | `dify-api`, `dify-web`, `dify-worker`, `dify-sandbox` |
| **Automation** | n8n | Workflow automation | `n8n` |
| **Chat UI** | Open WebUI | Chat interface for local/remote models | `open-webui` |
| **Flow Builder** | Flowise | Visual LLM flow builder | `flowise` |
| **Auth** | SuperTokens | Authentication service | `supertokens` |
| **Database** | PostgreSQL 16 | Shared database (multi-schema) | `postgres` |
| **Cache** | Redis 7 | Caching, queues, sessions | `redis` |
| **Vector DB** | Qdrant | Vector similarity search | `qdrant` |
| **Monitoring** | Prometheus + Grafana | Metrics collection + dashboards | `prometheus`, `grafana` |

### 1.2 Network Architecture

```text
Internet
    │
    ▼
┌─────────┐
│  Caddy   │ :80, :443 (or :3080 in local mode)
└────┬─────┘
     │ Internal Docker Network (ai-platform)
     ├──→ LiteLLM        :4000
     ├──→ Dify Web        :3000
     ├──→ Dify API        :5001
     ├──→ n8n             :5678
     ├──→ Open WebUI      :8080
     ├──→ Flowise         :3001
     ├──→ Grafana         :3100
     ├──→ Prometheus      :9090
     │
     │ Backend Network (ai-backend)
     ├──→ PostgreSQL      :5432
     ├──→ Redis           :6379
     ├──→ Qdrant          :6333
     ├──→ SuperTokens     :3567
     └──→ Dify Sandbox    :8194

1.3 Ollama — System Service (Not Containerized)
Ollama runs as a systemd service on the host, NOT inside Docker. This is a deliberate architectural decision:
Direct GPU access — No Docker GPU passthrough overhead
Shared across services — LiteLLM, Dify, Open WebUI, and Flowise all connect to Ollama via http://host.docker.internal:11434 or http://${HOST_IP}:11434
Independent lifecycle — Can pull models without restarting containers
Script 1 installs and configures Ollama
Script 2 references it in container environment variables
1.4 Docker Compose Strategy — One Compose Per Service
Each service gets its own docker-compose.<service>.yml file. This provides:
Independent lifecycle — Restart one service without affecting others
Easier debugging — Isolate failures to specific services
Modular deployment — Add/remove services without editing a monolithic file
Clear ownership — Each compose file manages exactly one concern
All compose files share external networks (ai-platform, ai-backend) created before any service starts.
1.5 Directory Structure
/opt/ai-platform/                          ← ROOT_PATH
├── docker/
│   ├── docker-compose.postgres.yml
│   ├── docker-compose.redis.yml
│   ├── docker-compose.qdrant.yml
│   ├── docker-compose.supertokens.yml
│   ├── docker-compose.litellm.yml
│   ├── docker-compose.dify.yml            ← Contains api, web, worker, sandbox
│   ├── docker-compose.n8n.yml
│   ├── docker-compose.open-webui.yml
│   ├── docker-compose.flowise.yml
│   ├── docker-compose.caddy.yml
│   ├── docker-compose.prometheus.yml
│   └── docker-compose.grafana.yml
├── config/
│   ├── master.env
│   ├── postgres/
│   │   └── init-databases.sql
│   ├── redis/
│   │   └── redis.conf
│   ├── litellm/
│   │   └── litellm-config.yaml
│   ├── dify/
│   │   ├── api.env
│   │   ├── worker.env
│   │   └── sandbox.env
│   ├── n8n/
│   │   └── n8n.env
│   ├── open-webui/
│   │   └── open-webui.env
│   ├── flowise/
│   │   └── flowise.env
│   ├── supertokens/
│   │   └── supertokens.env
│   ├── caddy/
│   │   └── Caddyfile
│   ├── prometheus/
│   │   ├── prometheus.yml
│   │   └── alert-rules.yml
│   └── grafana/
│       ├── grafana.env
│       ├── provisioning/
│       │   ├── datasources/
│       │   │   └── prometheus.yml
│       │   └── dashboards/
│       │       ├── dashboard.yml
│       │       └── ai-platform.json
│       └── grafana.ini
├── data/
│   ├── postgres/
│   ├── redis/
│   ├── qdrant/
│   ├── dify/
│   ├── n8n/
│   ├── open-webui/
│   ├── flowise/
│   ├── caddy/
│   ├── prometheus/
│   └── grafana/
├── backups/
├── logs/
│   ├── script-0.log
│   ├── script-1.log
│   ├── script-2.log
│   ├── script-3.log
│   └── script-4.log
├── scripts/
│   ├── ai-status.sh
│   ├── ai-logs.sh
│   ├── ai-backup.sh
│   ├── ai-restore.sh
│   ├── ai-update.sh
│   ├── ai-models.sh
│   └── ai-troubleshoot.sh
└── .env                                   ← Symlink to config/master.env


Section 2: Design Philosophy
2.1 Core Principles
Idempotent Execution — Every script can be run multiple times safely. Functions check current state before making changes.


Fail-Fast with Recovery — Scripts stop on first error (set -euo pipefail), but include trap handlers that save state for re-run.


Transparent Logging — Every action is logged to both terminal (colored) and file (plain). Log files are saved to ${ROOT_PATH}/logs/.


User Confirmation — Destructive operations require explicit confirmation. Non-destructive operations proceed automatically.


Configuration-Driven — All runtime values come from master.env. No hardcoded values in compose files or app configs.


One Compose Per Service — Modular, independent lifecycle per container group.


2.2 Logging Standard
All scripts use a common logging pattern:
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

LOG_FILE="${ROOT_PATH}/logs/script-N.log"

log_info()    { echo -e "${GREEN}[INFO]${NC}  $ 1" | tee -a " $ LOG_FILE"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $ 1" | tee -a " $ LOG_FILE"; }
log_error()   { echo -e "${RED}[ERROR]${NC}  $ 1" | tee -a " $ LOG_FILE"; }
log_section() { echo -e "\n${CYAN}========================================${NC}" | tee -a " $ LOG_FILE"
                echo -e " $ {CYAN}   $ 1 $ {NC}" | tee -a " $ LOG_FILE"
                echo -e " $ {CYAN}========================================${NC}\n" | tee -a "$LOG_FILE"; }

2.3 Error Handling Standard
set -euo pipefail

trap 'error_handler $? $LINENO  $ BASH_COMMAND' ERR

error_handler() {
    local exit_code= $ 1
    local line_number= $ 2
    local command= $ 3
    log_error "Command failed at line ${line_number}: ${command} (exit code: ${exit_code})"
    log_error "Log file: ${LOG_FILE}"
    exit "${exit_code}"
}

2.4 Idempotency Pattern
Every function follows this pattern:
install_something() {
    if something_already_installed; then
        log_info "Something already installed, skipping"
        return 0
    fi
    # ... perform installation ...
    log_info "Something installed successfully"
}


Section 3: Prerequisites & Assumptions
3.1 System Requirements
Copy table
Requirement
Minimum
Recommended
OS
Ubuntu 24.04 LTS
Ubuntu 24.04 LTS
CPU
4 cores
8+ cores
RAM
16 GB
32+ GB
Disk
50 GB free
100+ GB free (SSD/NVMe)
GPU
None (CPU-only mode)
NVIDIA with 8+ GB VRAM
Network
Internet access
Internet access
User
sudo privileges
sudo privileges

3.2 What Must Exist Before Script 0
Ubuntu 24.04 fresh install or existing system
User with sudo access
Internet connectivity
git installed (to clone the repository)
3.3 What Script 0 Produces
Clean system: previous Docker, Ollama, NVIDIA container toolkit removed
Directory /opt/ai-platform/ created with proper ownership
Ready for Script 1
3.4 What Script 1 Produces
Hardware profile detected and saved
Docker Engine + Docker Compose installed and running
NVIDIA Container Toolkit installed (if GPU detected)
Ollama installed as systemd service with configured models
AppArmor profiles configured for Docker
System validated and ready for Script 2
3.5 What Script 2 Produces
User preferences collected (domain, providers, passwords)
All credentials generated
master.env with all 80+ variables
All service environment files
All docker-compose.<service>.yml files
Caddyfile, LiteLLM config, Prometheus config, Grafana provisioning
PostgreSQL init SQL, Redis config
All convenience scripts
ALL containers started and running
3.6 What Script 3 Produces
All services verified healthy
Dify configured (admin account, model providers connected)
n8n configured (initial workflows optional)
Open WebUI configured (Ollama connection verified)
All integrations tested and validated
3.7 What Script 4 Produces
Additional optional services deployed
Additional models pulled
Custom integrations configured

Section 4: Script Inventory & Flow
4.1 Execution Order
┌──────────────────┐
│  0-cleanup.sh    │  Purge & reset (optional, for re-installs)
└────────┬─────────┘
         ▼
┌──────────────────┐
│  1-setup-system  │  Hardware, Docker, NVIDIA, Ollama, validation
└────────┬─────────┘
         ▼
┌──────────────────┐
│  2-deploy-platform│  Questionnaire → generate configs → deploy containers
└────────┬─────────┘
         ▼
┌──────────────────┐
│  3-configure-svc │  Wait healthy → configure Dify, n8n, WebUI via APIs
└────────┬─────────┘
         ▼
┌──────────────────┐
│  4-add-services  │  Optional: extra services, models, integrations
└────────┴─────────┘

4.2 Inter-Script Communication
Scripts communicate via:
File system — Each script reads outputs from previous scripts:


Script 1 writes: ${ROOT_PATH}/config/hardware-profile.env
Script 2 reads hardware profile, writes all configs + composes
Script 3 reads master.env for URLs, credentials
Exit codes — Each script exits 0 on success, non-zero on failure


Log files — Each script writes to ${ROOT_PATH}/logs/script-N.log


4.3 Common Variables
All scripts share these base variables:
ROOT_PATH="/opt/ai-platform"
CONFIG_PATH="${ROOT_PATH}/config"
DOCKER_PATH="${ROOT_PATH}/docker"
DATA_PATH="${ROOT_PATH}/data"
LOG_PATH="${ROOT_PATH}/logs"
SCRIPTS_PATH="${ROOT_PATH}/scripts"
BACKUP_PATH="${ROOT_PATH}/backups"

---

## Section 5: Script 0 — Cleanup System

### 5.1 Purpose

`0-cleanup.sh` removes all traces of a previous installation so the system can be re-provisioned cleanly. It is **optional** — only needed when re-installing or resetting.

### 5.2 Safety

The script requires explicit confirmation before proceeding. It distinguishes between:

- **Soft reset** — Stop containers, remove configs, keep data volumes
- **Hard reset** — Remove everything including data volumes

### 5.3 Execution

```bash
sudo bash 0-cleanup.sh          # Interactive — asks which mode
sudo bash 0-cleanup.sh --hard   # Non-interactive hard reset
sudo bash 0-cleanup.sh --soft   # Non-interactive soft reset

5.4 Cleanup Phases
Phase 1: Stop & Remove Containers
  ├── Find all docker-compose.*.yml files in /opt/ai-platform/docker/
  ├── For each: docker compose -f <file> down --remove-orphans
  ├── docker container prune -f
  └── Remove external networks (ai-platform, ai-backend)

Phase 2: Remove Docker Volumes (hard mode only)
  ├── docker volume ls --filter label=com.docker.compose.project
  ├── docker volume rm <each volume>
  └── docker volume prune -f

Phase 3: Stop Ollama (optional)
  ├── systemctl stop ollama
  ├── systemctl disable ollama
  └── Note: does NOT uninstall Ollama binary (Script 1 handles install)

Phase 4: Remove Configuration Files
  ├── rm -rf /opt/ai-platform/config/*
  ├── rm -rf /opt/ai-platform/docker/*
  ├── rm -rf /opt/ai-platform/scripts/*
  └── rm -rf /opt/ai-platform/logs/*

Phase 5: Remove Data Directories (hard mode only)
  ├── rm -rf /opt/ai-platform/data/*
  └── rm -rf /opt/ai-platform/backups/*

Phase 6: Recreate Directory Structure
  ├── mkdir -p /opt/ai-platform/{config,docker,data,logs,scripts,backups}
  └── chown -R ${SUDO_USER:- $ USER}: $ {SUDO_USER:-$USER} /opt/ai-platform/

5.5 What It Does NOT Remove
Docker Engine itself (Script 1 manages this)
NVIDIA drivers or Container Toolkit (Script 1 manages this)
Ollama binary (Script 1 manages this)
System packages
User accounts
5.6 Pseudocode
#!/usr/bin/env bash
set -euo pipefail

ROOT_PATH="/opt/ai-platform"
LOG_FILE="${ROOT_PATH}/logs/script-0.log"

# Source logging functions (same pattern as Section 2.2)

parse_arguments() {
    CLEANUP_MODE="interactive"
    while [[  $ # -gt 0 ]]; do
        case " $ 1" in
            --hard) CLEANUP_MODE="hard" ;;
            --soft) CLEANUP_MODE="soft" ;;
            --help) show_help; exit 0 ;;
            *) log_error "Unknown option:  $ 1"; exit 1 ;;
        esac
        shift
    done
}

confirm_cleanup() {
    if [[ " $ CLEANUP_MODE" == "interactive" ]]; then
        echo ""
        echo "Select cleanup mode:"
        echo "  1) Soft reset — remove configs, keep data"
        echo "  2) Hard reset — remove EVERYTHING"
        echo "  3) Cancel"
        read -rp "Choice [1-3]: " choice
        case "$choice" in
            1) CLEANUP_MODE="soft" ;;
            2) CLEANUP_MODE="hard" ;;
            *) log_info "Cancelled."; exit 0 ;;
        esac
    fi

    log_warn "This will perform a ${CLEANUP_MODE} reset."
    read -rp "Type YES to confirm: " confirm
    [[ " $ confirm" == "YES" ]] || { log_info "Cancelled."; exit 0; }
}

stop_containers() {
    log_section "Stopping All Containers"
    if [[ -d " $ {ROOT_PATH}/docker" ]]; then
        for compose_file in "${ROOT_PATH}"/docker/docker-compose.*.yml; do
            [[ -f " $ compose_file" ]] || continue
            local service_name
            service_name= $ (basename "$compose_file" | sed 's/docker-compose\.$ .* $ \.yml/\1/')
            log_info "Stopping ${service_name}..."
            docker compose -f " $ compose_file" down --remove-orphans 2>/dev/null || true
        done
    fi
    docker container prune -f 2>/dev/null || true
}

remove_networks() {
    log_section "Removing Docker Networks"
    docker network rm ai-platform 2>/dev/null || true
    docker network rm ai-backend 2>/dev/null || true
}

remove_volumes() {
    if [[ " $ CLEANUP_MODE" == "hard" ]]; then
        log_section "Removing Docker Volumes"
        docker volume prune -f 2>/dev/null || true
    fi
}

stop_ollama() {
    log_section "Stopping Ollama"
    if systemctl is-active --quiet ollama 2>/dev/null; then
        systemctl stop ollama
        systemctl disable ollama
        log_info "Ollama stopped and disabled"
    else
        log_info "Ollama not running"
    fi
}

remove_configs() {
    log_section "Removing Configuration Files"
    rm -rf "${ROOT_PATH}/config"/*
    rm -rf "${ROOT_PATH}/docker"/*
    rm -rf "${ROOT_PATH}/scripts"/*
    rm -rf "${ROOT_PATH}/logs"/*
    log_info "Configuration files removed"
}

remove_data() {
    if [[ " $ CLEANUP_MODE" == "hard" ]]; then
        log_section "Removing All Data"
        rm -rf " $ {ROOT_PATH}/data"/*
        rm -rf "${ROOT_PATH}/backups"/*
        log_info "All data removed"
    fi
}

recreate_directories() {
    log_section "Recreating Directory Structure"
    local dirs=(config docker data logs scripts backups
                config/postgres config/redis config/litellm
                config/dify config/n8n config/open-webui
                config/flowise config/supertokens config/caddy
                config/prometheus config/grafana
                config/grafana/provisioning
                config/grafana/provisioning/datasources
                config/grafana/provisioning/dashboards
                data/postgres data/redis data/qdrant data/dify
                data/n8n data/open-webui data/flowise
                data/caddy data/prometheus data/grafana)

    for dir in "${dirs[@]}"; do
        mkdir -p "${ROOT_PATH}/${dir}"
    done

    local owner="${SUDO_USER:- $ USER}"
    chown -R " $ {owner}:${owner}" "${ROOT_PATH}"
    log_info "Directory structure recreated"
}

# --- Main ---
parse_arguments " $ @"
mkdir -p " $ {ROOT_PATH}/logs"
confirm_cleanup
stop_containers
remove_networks
remove_volumes
stop_ollama
remove_configs
remove_data
recreate_directories
log_section "Cleanup Complete (${CLEANUP_MODE} mode)"


Section 6: Script 1 — Structure & Phases
6.1 Purpose
1-setup-system.sh prepares the bare Ubuntu 24.04 system to host the AI platform. It detects hardware, installs Docker, configures GPU support if available, installs Ollama, pulls models, and validates everything.
6.2 Execution
sudo bash 1-setup-system.sh

6.3 Phase Map
Script 1: Setup System
│
├── Phase 1: Hardware Detection & Profiling
│   ├── Detect CPU (cores, model)
│   ├── Detect RAM (total, available)
│   ├── Detect Disk (total, free, type)
│   ├── Detect GPU (model, VRAM, driver version)
│   ├── Classify system tier (minimal / standard / performance)
│   └── Write hardware-profile.env
│
├── Phase 2: Docker Engine Installation
│   ├── Remove conflicting packages
│   ├── Add Docker GPG key and repository
│   ├── Install docker-ce, docker-ce-cli, containerd, compose plugin
│   ├── Configure Docker daemon (logging, storage driver)
│   ├── Add current user to docker group
│   └── Verify Docker works
│
├── Phase 3: NVIDIA Container Toolkit (if GPU detected)
│   ├── Verify NVIDIA driver is installed
│   ├── Add NVIDIA container toolkit repository
│   ├── Install nvidia-container-toolkit
│   ├── Configure Docker runtime for nvidia
│   ├── Restart Docker daemon
│   └── Test GPU passthrough with nvidia-smi in container
│
├── Phase 4: Ollama Installation & Model Pull
│   ├── Install Ollama via official script
│   ├── Configure Ollama environment (OLLAMA_HOST, OLLAMA_ORIGINS)
│   ├── Configure AppArmor for Ollama (if AppArmor active)
│   ├── Start and enable Ollama systemd service
│   ├── Wait for Ollama API to respond
│   ├── Pull default models (based on hardware tier)
│   └── Verify models loaded
│
└── Phase 5: Validation & Handoff
    ├── Verify Docker daemon is running
    ├── Verify Docker Compose is available
    ├── Verify GPU passthrough (if applicable)
    ├── Verify Ollama is running and responding
    ├── Verify models are available
    ├── Write validation summary
    └── Print next-steps instructions


Section 7: Phase 1 — Hardware Detection & Profiling
7.1 Detection Logic
detect_hardware() {
    log_section "Detecting Hardware"

    # CPU
    CPU_CORES= $ (nproc)
    CPU_MODEL= $ (grep -m1 'model name' /proc/cpuinfo | cut -d':' -f2 | xargs)
    log_info "CPU: ${CPU_MODEL} (${CPU_CORES} cores)"

    # Memory
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print  $ 2}')
    TOTAL_RAM_GB= $ (( TOTAL_RAM_KB / 1024 / 1024 ))
    log_info "RAM: ${TOTAL_RAM_GB} GB"

    # Disk
    DISK_FREE_GB=$(df -BG / | tail -1 | awk '{print  $ 4}' | tr -d 'G')
    DISK_TOTAL_GB= $ (df -BG / | tail -1 | awk '{print  $ 2}' | tr -d 'G')
    # Detect SSD vs HDD
    ROOT_DEVICE= $ (findmnt -n -o SOURCE / | sed 's/[0-9]* $ //' | xargs basename 2>/dev/null || echo "unknown")
    DISK_TYPE="unknown"
    if [[ -f "/sys/block/ $ {ROOT_DEVICE}/queue/rotational" ]]; then
        if [[  $ (cat "/sys/block/ $ {ROOT_DEVICE}/queue/rotational") == "0" ]]; then
            DISK_TYPE="ssd"
        else
            DISK_TYPE="hdd"
        fi
    fi
    log_info "Disk: ${DISK_FREE_GB} GB free / ${DISK_TOTAL_GB} GB total (${DISK_TYPE})"

    # GPU
    GPU_AVAILABLE="false"
    GPU_MODEL="none"
    GPU_VRAM_MB="0"
    GPU_DRIVER_VERSION="none"

    if command -v nvidia-smi &>/dev/null; then
        if nvidia-smi &>/dev/null; then
            GPU_AVAILABLE="true"
            GPU_MODEL= $ (nvidia-smi --query-gpu=name --format=csv,noheader | head -1 | xargs)
            GPU_VRAM_MB= $ (nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1 | xargs)
            GPU_DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1 | xargs)
            log_info "GPU: ${GPU_MODEL} (${GPU_VRAM_MB} MB VRAM, driver ${GPU_DRIVER_VERSION})"
        fi
    fi

    if [[ "$GPU_AVAILABLE" == "false" ]]; then
        log_info "GPU: None detected — CPU-only mode"
    fi
}

7.2 System Tier Classification
classify_system_tier() {
    # Tier determines default model selection and resource limits
    if [[ " $ GPU_AVAILABLE" == "true" && " $ GPU_VRAM_MB" -ge 16000 && " $ TOTAL_RAM_GB" -ge 32 ]]; then
        SYSTEM_TIER="performance"
        DEFAULT_MODELS="llama3.1:8b,nomic-embed-text,codellama:13b"
    elif [[ " $ GPU_AVAILABLE" == "true" && " $ GPU_VRAM_MB" -ge 6000 && " $ TOTAL_RAM_GB" -ge 16 ]]; then
        SYSTEM_TIER="standard"
        DEFAULT_MODELS="llama3.1:8b,nomic-embed-text"
    else
        SYSTEM_TIER="minimal"
        DEFAULT_MODELS="llama3.2:3b,nomic-embed-text"
    fi

    log_info "System tier: ${SYSTEM_TIER}"
    log_info "Default models: ${DEFAULT_MODELS}"
}

7.3 Hardware Profile Output
write_hardware_profile() {
    local profile_file="${CONFIG_PATH}/hardware-profile.env"
    cat > "$profile_file" << EOF
# Hardware Profile — Generated by 1-setup-system.sh
# Generated:  $ (date -u +"%Y-%m-%dT%H:%M:%SZ")

CPU_CORES= $ {CPU_CORES}
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
    log_info "Hardware profile written to ${profile_file}"
}


Section 8: Phase 2 — Docker Engine Installation
8.1 Installation Logic
install_docker() {
    log_section "Installing Docker Engine"

    # Idempotency check
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        local docker_version
        docker_version=$(docker --version)
        log_info "Docker already installed: ${docker_version}"
        return 0
    fi

    # Remove conflicting packages
    log_info "Removing conflicting packages..."
    local conflicting_packages=(
        docker.io docker-doc docker-compose docker-compose-v2
        podman-docker containerd runc
    )
    for pkg in "${conflicting_packages[@]}"; do
        apt-get remove -y " $ pkg" 2>/dev/null || true
    done

    # Install prerequisites
    log_info "Installing prerequisites..."
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release

    # Add Docker GPG key
    log_info "Adding Docker GPG key..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Add Docker repository
    log_info "Adding Docker repository..."
    echo \
        "deb [arch= $ (dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu \
         $ (. /etc/os-release && echo " $ VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    log_info "Installing Docker packages..."
    apt-get update -y
    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    # Add user to docker group
    local target_user="${SUDO_USER:- $ USER}"
    if ! groups " $ target_user" | grep -q docker; then
        usermod -aG docker "$target_user"
        log_info "Added ${target_user} to docker group"
    fi

    # Configure Docker daemon
    configure_docker_daemon

    # Start and enable
    systemctl enable docker
    systemctl start docker

    log_info "Docker installed: $(docker --version)"
}

8.2 Docker Daemon Configuration
configure_docker_daemon() {
    log_info "Configuring Docker daemon..."
    mkdir -p /etc/docker

    cat > /etc/docker/daemon.json << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "live-restore": true,
    "default-address-pools": [
        {
            "base": "172.20.0.0/14",
            "size": 24
        }
    ]
}
EOF

    log_info "Docker daemon configured"
}

8.3 Docker Verification
verify_docker() {
    log_info "Verifying Docker installation..."

    # Test docker daemon
    if ! docker info &>/dev/null; then
        log_error "Docker daemon is not responding"
        return 1
    fi

    # Test docker compose
    if ! docker compose version &>/dev/null; then
        log_error "Docker Compose plugin not available"
        return 1
    fi

    # Test container execution
    if ! docker run --rm hello-world &>/dev/null; then
        log_error "Docker cannot run containers"
        return 1
    fi

    log_info "Docker verification passed"
}


Section 9: Phase 3 — NVIDIA Container Toolkit
9.1 Installation Logic
install_nvidia_toolkit() {
    log_section "NVIDIA Container Toolkit"

    # Skip if no GPU
    if [[ "$GPU_AVAILABLE" != "true" ]]; then
        log_info "No GPU detected — skipping NVIDIA Container Toolkit"
        return 0
    fi

    # Idempotency check
    if dpkg -l | grep -q nvidia-container-toolkit && \
       docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi &>/dev/null; then
        log_info "NVIDIA Container Toolkit already installed and working"
        return 0
    fi

    # Verify NVIDIA driver is present
    if ! nvidia-smi &>/dev/null; then
        log_error "NVIDIA driver not installed. Install GPU drivers first."
        log_error "Run: sudo apt install nvidia-driver-535 (or appropriate version)"
        return 1
    fi

    # Add NVIDIA Container Toolkit repository
    log_info "Adding NVIDIA Container Toolkit repository..."
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
        gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null

    # Install
    log_info "Installing nvidia-container-toolkit..."
    apt-get update -y
    apt-get install -y nvidia-container-toolkit

    # Configure Docker runtime
    log_info "Configuring NVIDIA Docker runtime..."
    nvidia-ctk runtime configure --runtime=docker

    # Restart Docker to apply runtime changes
    systemctl restart docker

    # Test GPU passthrough
    log_info "Testing GPU passthrough..."
    if docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi; then
        log_info "GPU passthrough test PASSED"
    else
        log_error "GPU passthrough test FAILED"
        return 1
    fi

    log_info "NVIDIA Container Toolkit installed and configured"
}


Section 10: Phase 4 — Ollama Installation & Model Pull
10.1 Installation Logic
install_ollama() {
    log_section "Installing Ollama"

    # Idempotency check
    if command -v ollama &>/dev/null && systemctl is-active --quiet ollama; then
        log_info "Ollama already installed and running"
        configure_ollama_env
        return 0
    fi

    # Install via official script
    log_info "Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh

    # Configure environment
    configure_ollama_env

    # Handle AppArmor if active
    configure_ollama_apparmor

    # Start and enable
    systemctl daemon-reload
    systemctl enable ollama
    systemctl start ollama

    # Wait for API to respond
    wait_for_ollama

    log_info "Ollama installed and running"
}

10.2 Ollama Environment Configuration
configure_ollama_env() {
    log_info "Configuring Ollama environment..."

    # Create override directory
    mkdir -p /etc/systemd/system/ollama.service.d

    # Detect host IP for container access
    HOST_IP=$(hostname -I | awk '{print $1}')

    cat > /etc/systemd/system/ollama.service.d/override.conf << EOF
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_ORIGINS=*"
Environment="OLLAMA_KEEP_ALIVE=5m"
EOF

    systemctl daemon-reload
    log_info "Ollama configured: listening on 0.0.0.0:11434"
}

10.3 AppArmor Configuration
configure_ollama_apparmor() {
    # Check if AppArmor is active
    if ! command -v aa-status &>/dev/null; then
        log_info "AppArmor not installed — skipping"
        return 0
    fi

    if ! aa-status --enabled 2>/dev/null; then
        log_info "AppArmor not enabled — skipping"
        return 0
    fi

    log_info "Configuring AppArmor for Ollama..."

    # Check if Ollama is being blocked by AppArmor
    if aa-status 2>/dev/null | grep -q ollama; then
        log_info "Ollama AppArmor profile already exists"
        return 0
    fi

    # Create permissive profile for Ollama if it gets blocked
    # This is needed on some Ubuntu 24.04 installations
    cat > /etc/apparmor.d/usr.local.bin.ollama << 'EOF'
#include <tunables/global>

/usr/local/bin/ollama flags=(unconfined) {
  userns,
}
EOF

    # Reload AppArmor
    apparmor_parser -r /etc/apparmor.d/usr.local.bin.ollama 2>/dev/null || true
    log_info "AppArmor profile configured for Ollama"
}

10.4 Wait for Ollama
wait_for_ollama() {
    log_info "Waiting for Ollama API..."
    local max_attempts=30
    local attempt=0

    while [[ $attempt -lt  $ max_attempts ]]; do
        if curl -sf http://localhost:11434/api/tags &>/dev/null; then
            log_info "Ollama API is ready"
            return 0
        fi
        attempt= $ ((attempt + 1))
        sleep 2
    done

    log_error "Ollama API did not respond after ${max_attempts} attempts"
    return 1
}

10.5 Model Pull
pull_ollama_models() {
    log_section "Pulling Ollama Models"

    # DEFAULT_MODELS is set by classify_system_tier()
    IFS=',' read -ra MODELS <<< " $ DEFAULT_MODELS"

    for model in " $ {MODELS[@]}"; do
        model= $ (echo " $ model" | xargs)  # trim whitespace
        log_info "Pulling model: ${model}..."

        # Check if already pulled
        if ollama list 2>/dev/null | grep -q "^${model}"; then
            log_info "Model ${model} already available"
            continue
        fi

        if ollama pull "$model"; then
            log_info "Model ${model} pulled successfully"
        else
            log_warn "Failed to pull model ${model} — continuing"
        fi
    done

    # List all available models
    log_info "Available models:"
    ollama list
}


Section 11: Phase 5 — Validation & Handoff
11.1 Validation Logic
validate_system() {
    log_section "System Validation"

    local errors=0

    # Docker
    if docker info &>/dev/null; then
        log_info "✓ Docker daemon running"
    else
        log_error "✗ Docker daemon not running"
        errors= $ ((errors + 1))
    fi

    # Docker Compose
    if docker compose version &>/dev/null; then
        log_info "✓ Docker Compose available"
    else
        log_error "✗ Docker Compose not available"
        errors= $ ((errors + 1))
    fi

    # GPU (if detected)
    if [[ " $ GPU_AVAILABLE" == "true" ]]; then
        if docker run --rm --gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi &>/dev/null; then
            log_info "✓ GPU passthrough working"
        else
            log_error "✗ GPU passthrough failed"
            errors= $ ((errors + 1))
        fi
    fi

    # Ollama
    if curl -sf http://localhost:11434/api/tags &>/dev/null; then
        log_info "✓ Ollama API responding"
    else
        log_error "✗ Ollama API not responding"
        errors= $ ((errors + 1))
    fi

    # Models
    local model_count
    model_count= $ (ollama list 2>/dev/null | tail -n +2 | wc -l)
    if [[ "$model_count" -gt 0 ]]; then
        log_info "✓ ${model_count} model(s) available"
    else
        log_warn "⚠ No models available (pull may have failed)"
    fi

    # Directory structure
    if [[ -d "${ROOT_PATH}/config" && -d "${ROOT_PATH}/docker" && -d "${ROOT_PATH}/data" ]]; then
        log_info "✓ Directory structure intact"
    else
        log_error "✗ Directory structure incomplete"
        errors= $ ((errors + 1))
    fi

    # Hardware profile
    if [[ -f " $ {CONFIG_PATH}/hardware-profile.env" ]]; then
        log_info "✓ Hardware profile saved"
    else
        log_error "✗ Hardware profile missing"
        errors=$((errors + 1))
    fi

    # Summary
    echo ""
    if [[ $errors -eq 0 ]]; then
        log_section "VALIDATION PASSED — System Ready"
        echo ""
        log_info "Next step: Run 2-deploy-platform.sh"
        echo ""
        echo "  sudo bash 2-deploy-platform.sh"
        echo ""
    else
        log_error "VALIDATION FAILED — ${errors} error(s) found"
        log_error "Fix the issues above and re-run this script"
        exit 1
    fi
}

11.2 Handoff Summary
At the end of Script 1, the following exists on the system:
Copy table
Component
State
Location
Docker Engine
Running
systemd service
Docker Compose
Available
Plugin for docker CLI
NVIDIA Container Toolkit
Installed (if GPU)
Docker runtime configured
Ollama
Running
systemd service, port 11434
Models
Pulled
~/.ollama/models/
Hardware Profile
Written
${CONFIG_PATH}/hardware-profile.env
Directory Structure
Created
/opt/ai-platform/*
Log File
Written
${ROOT_PATH}/logs/script-1.log

---

## Section 12: Script 2 — Overview & Structure

### 12.1 Purpose

`2-deploy-platform.sh` is the primary deployment script. It collects user preferences via an interactive questionnaire, generates ALL configuration files, creates ALL docker-compose files (one per service), then deploys every container.

### 12.2 Execution

```bash
sudo bash 2-deploy-platform.sh

12.3 Phase Map
Script 2: Deploy Platform
│
├── Phase 1: Pre-flight Checks
│   ├── Verify running as root
│   ├── Verify Docker is running
│   ├── Verify Ollama is running
│   ├── Source hardware-profile.env
│   └── Verify previous script completed
│
├── Phase 2: Interactive Questionnaire
│   ├── Domain / IP configuration
│   ├── SSL mode (Caddy auto vs self-signed vs none)
│   ├── Provider API keys (OpenAI, Anthropic, etc.)
│   ├── Admin email and password preferences
│   └── Optional service toggles
│
├── Phase 3: Credential Generation
│   ├── Generate all passwords (32-char random)
│   ├── Generate all secret keys
│   ├── Generate all API tokens
│   └── Write credentials.env (restricted permissions)
│
├── Phase 4: Configuration File Generation
│   ├── master.env (all variables)
│   ├── Per-service .env files
│   ├── PostgreSQL init SQL
│   ├── Redis configuration
│   ├── LiteLLM config.yaml
│   ├── Caddyfile
│   ├── Prometheus config
│   ├── Grafana provisioning files
│   └── Convenience scripts
│
├── Phase 5: Docker Compose Generation
│   ├── Docker networks creation
│   ├── docker-compose.postgres.yml
│   ├── docker-compose.redis.yml
│   ├── docker-compose.qdrant.yml
│   ├── docker-compose.supertokens.yml
│   ├── docker-compose.litellm.yml
│   ├── docker-compose.dify-api.yml
│   ├── docker-compose.dify-worker.yml
│   ├── docker-compose.dify-web.yml
│   ├── docker-compose.dify-sandbox.yml
│   ├── docker-compose.n8n.yml
│   ├── docker-compose.open-webui.yml
│   ├── docker-compose.flowise.yml
│   ├── docker-compose.caddy.yml
│   ├── docker-compose.prometheus.yml
│   └── docker-compose.grafana.yml
│
├── Phase 6: Deployment
│   ├── Create Docker networks
│   ├── Deploy infrastructure tier (postgres, redis, qdrant, supertokens)
│   ├── Wait for infrastructure healthy
│   ├── Deploy AI tier (litellm, dify-api, dify-worker, dify-web, dify-sandbox)
│   ├── Wait for AI tier healthy
│   ├── Deploy application tier (n8n, open-webui, flowise)
│   ├── Wait for application tier healthy
│   ├── Deploy front tier (caddy)
│   └── Deploy monitoring tier (prometheus, grafana)
│
└── Phase 7: Post-Deploy Validation
    ├── Verify all containers running
    ├── Verify all health checks passing
    ├── Print access URLs
    └── Print next-steps (run script 3)


Section 13: Phase 1 — Pre-flight Checks
13.1 Preflight Logic
preflight_checks() {
    log_section "Pre-flight Checks"

    local errors=0

    # Root check
    if [[  $ EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi

    # Docker
    if ! docker info &>/dev/null; then
        log_error "Docker is not running. Run 1-setup-system.sh first."
        errors= $ ((errors + 1))
    else
        log_info "✓ Docker is running"
    fi

    # Docker Compose
    if ! docker compose version &>/dev/null; then
        log_error "Docker Compose not available. Run 1-setup-system.sh first."
        errors= $ ((errors + 1))
    else
        log_info "✓ Docker Compose available"
    fi

    # Ollama
    if ! curl -sf http://localhost:11434/api/tags &>/dev/null; then
        log_error "Ollama is not running. Run 1-setup-system.sh first."
        errors= $ ((errors + 1))
    else
        log_info "✓ Ollama is running"
    fi

    # Hardware profile
    if [[ ! -f "${CONFIG_PATH}/hardware-profile.env" ]]; then
        log_error "Hardware profile not found. Run 1-setup-system.sh first."
        errors= $ ((errors + 1))
    else
        source " $ {CONFIG_PATH}/hardware-profile.env"
        log_info "✓ Hardware profile loaded (tier: ${SYSTEM_TIER})"
    fi

    # Disk space check (need at least 20GB free for images)
    local free_gb
    free_gb=$(df -BG /var/lib/docker 2>/dev/null | tail -1 | awk '{print  $ 4}' | tr -d 'G')
    if [[ -n " $ free_gb" && " $ free_gb" -lt 20 ]]; then
        log_error "Less than 20GB free in /var/lib/docker — need space for images"
        errors= $ ((errors + 1))
    else
        log_info "✓ Disk space OK (${free_gb}GB free)"
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Pre-flight failed with ${errors} error(s)"
        exit 1
    fi

    log_info "All pre-flight checks passed"
}


Section 14: Phase 2 — Interactive Questionnaire
14.1 Design Principles
Every question has a sensible default (press Enter to accept)
Passwords are never displayed on screen (use read -s)
Input is validated before proceeding
All answers stored in variables for later use
14.2 Questionnaire Logic
run_questionnaire() {
    log_section "Platform Configuration"
    echo ""
    echo "Answer the following questions to configure your platform."
    echo "Press Enter to accept [default] values."
    echo ""

    # --- Network Configuration ---
    echo "─── Network Configuration ───"
    echo ""

    # Domain or IP
    local detected_ip
    detected_ip=$(hostname -I | awk '{print  $ 1}')

    read -rp "Domain name or IP address [ $ {detected_ip}]: " USER_DOMAIN
    USER_DOMAIN="${USER_DOMAIN:- $ detected_ip}"

    # Determine if domain or IP
    if [[ " $ USER_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        DOMAIN_MODE="ip"
        DOMAIN_NAME=" $ USER_DOMAIN"
        log_info "Mode: IP-based access ( $ {DOMAIN_NAME})"
    else
        DOMAIN_MODE="domain"
        DOMAIN_NAME=" $ USER_DOMAIN"
        log_info "Mode: Domain-based access ( $ {DOMAIN_NAME})"
    fi

    # SSL mode
    echo ""
    if [[ " $ DOMAIN_MODE" == "domain" ]]; then
        echo "SSL Certificate Mode:"
        echo "  1) Automatic (Let's Encrypt via Caddy) — recommended for public domains"
        echo "  2) Self-signed — for internal/private domains"
        echo "  3) None (HTTP only) — not recommended"
        read -rp "SSL mode [1]: " ssl_choice
        case " $ {ssl_choice:-1}" in
            1) SSL_MODE="letsencrypt" ;;
            2) SSL_MODE="selfsigned" ;;
            3) SSL_MODE="none" ;;
            *) SSL_MODE="letsencrypt" ;;
        esac
    else
        echo "IP-based access: SSL will use self-signed certificate"
        SSL_MODE="selfsigned"
    fi
    log_info "SSL mode: ${SSL_MODE}"

    # --- Admin Configuration ---
    echo ""
    echo "─── Admin Configuration ───"
    echo ""

    read -rp "Admin email address [admin@${DOMAIN_NAME}]: " ADMIN_EMAIL
    ADMIN_EMAIL="${ADMIN_EMAIL:-admin@${DOMAIN_NAME}}"

    echo ""
    while true; do
        read -srp "Admin password (min 12 chars): " ADMIN_PASSWORD
        echo ""
        if [[ ${#ADMIN_PASSWORD} -ge 12 ]]; then
            read -srp "Confirm admin password: " ADMIN_PASSWORD_CONFIRM
            echo ""
            if [[ " $ ADMIN_PASSWORD" == " $ ADMIN_PASSWORD_CONFIRM" ]]; then
                break
            else
                echo "Passwords do not match. Try again."
            fi
        else
            echo "Password must be at least 12 characters. Try again."
        fi
    done
    log_info "Admin credentials configured"

    # --- LLM Provider API Keys ---
    echo ""
    echo "─── LLM Provider API Keys (optional — press Enter to skip) ───"
    echo ""

    read -srp "OpenAI API key: " OPENAI_API_KEY
    echo ""
    OPENAI_API_KEY="${OPENAI_API_KEY:-}"
    if [[ -n " $ OPENAI_API_KEY" ]]; then
        OPENAI_ENABLED="true"
        log_info "OpenAI: configured"
    else
        OPENAI_ENABLED="false"
        log_info "OpenAI: skipped"
    fi

    read -srp "Anthropic API key: " ANTHROPIC_API_KEY
    echo ""
    ANTHROPIC_API_KEY=" $ {ANTHROPIC_API_KEY:-}"
    if [[ -n " $ ANTHROPIC_API_KEY" ]]; then
        ANTHROPIC_ENABLED="true"
        log_info "Anthropic: configured"
    else
        ANTHROPIC_ENABLED="false"
        log_info "Anthropic: skipped"
    fi

    read -srp "Google AI (Gemini) API key: " GOOGLE_API_KEY
    echo ""
    GOOGLE_API_KEY=" $ {GOOGLE_API_KEY:-}"
    if [[ -n " $ GOOGLE_API_KEY" ]]; then
        GOOGLE_ENABLED="true"
        log_info "Google AI: configured"
    else
        GOOGLE_ENABLED="false"
        log_info "Google AI: skipped"
    fi

    # --- Optional Services ---
    echo ""
    echo "─── Optional Services ───"
    echo ""

    read -rp "Enable Flowise? (visual workflow builder) [y/N]: " enable_flowise
    FLOWISE_ENABLED="false"
    [[ " $ {enable_flowise,,}" == "y" ]] && FLOWISE_ENABLED="true"
    log_info "Flowise: ${FLOWISE_ENABLED}"

    read -rp "Enable Grafana monitoring? [Y/n]: " enable_grafana
    GRAFANA_ENABLED="true"
    [[ "${enable_grafana,,}" == "n" ]] && GRAFANA_ENABLED="false"
    log_info "Grafana: ${GRAFANA_ENABLED}"

    # --- Summary ---
    echo ""
    echo "─── Configuration Summary ───"
    echo ""
    echo "  Domain/IP:     ${DOMAIN_NAME} (${DOMAIN_MODE} mode)"
    echo "  SSL:           ${SSL_MODE}"
    echo "  Admin email:   ${ADMIN_EMAIL}"
    echo "  OpenAI:        ${OPENAI_ENABLED}"
    echo "  Anthropic:     ${ANTHROPIC_ENABLED}"
    echo "  Google AI:     ${GOOGLE_ENABLED}"
    echo "  Flowise:       ${FLOWISE_ENABLED}"
    echo "  Grafana:       ${GRAFANA_ENABLED}"
    echo "  System tier:   ${SYSTEM_TIER}"
    echo ""
    read -rp "Proceed with this configuration? [Y/n]: " confirm
    if [[ "${confirm,,}" == "n" ]]; then
        log_info "Cancelled by user"
        exit 0
    fi
}


Section 15: Phase 3 — Credential Generation
15.1 Generation Functions
generate_password() {
    # Generate a random password of specified length
    local length="${1:-32}"
    openssl rand -base64 48 | tr -dc 'A-Za-z0-9!@# $ %' | head -c " $ length"
}

generate_hex_key() {
    # Generate a hex key (for secret keys)
    local length="${1:-64}"
    openssl rand -hex "$((length / 2))"
}

generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

15.2 Credential Generation Logic
generate_all_credentials() {
    log_section "Generating Credentials"

    # Database passwords
    POSTGRES_PASSWORD= $ (generate_password 32)
    REDIS_PASSWORD= $ (generate_password 32)
    QDRANT_API_KEY= $ (generate_password 32)

    # Service-specific database passwords
    DIFY_DB_PASSWORD= $ (generate_password 32)
    N8N_DB_PASSWORD= $ (generate_password 32)
    LITELLM_DB_PASSWORD= $ (generate_password 32)
    SUPERTOKENS_DB_PASSWORD= $ (generate_password 32)
    FLOWISE_DB_PASSWORD= $ (generate_password 32)
    GRAFANA_DB_PASSWORD= $ (generate_password 32)

    # Secret keys
    DIFY_SECRET_KEY= $ (generate_hex_key 64)
    N8N_ENCRYPTION_KEY= $ (generate_hex_key 64)
    LITELLM_MASTER_KEY="sk-litellm- $ (generate_password 32)"
    LITELLM_ADMIN_KEY="sk-admin- $ (generate_password 32)"
    FLOWISE_SECRET_KEY= $ (generate_hex_key 64)
    SUPERTOKENS_API_KEY= $ (generate_password 32)

    # Dify-specific keys
    DIFY_INIT_PASSWORD= $ (generate_password 16)
    DIFY_SANDBOX_KEY= $ (generate_hex_key 32)
    DIFY_STORAGE_KEY= $ (generate_hex_key 32)

    # Grafana
    GRAFANA_ADMIN_PASSWORD= $ (generate_password 24)

    # Inter-service tokens
    N8N_WEBHOOK_SECRET= $ (generate_hex_key 32)

    log_info "All credentials generated (${credential_count} items)"
}

15.3 Credentials File Output
write_credentials_file() {
    local cred_file="${CONFIG_PATH}/credentials.env"

    cat > "$cred_file" << EOF
# Platform Credentials — Generated by 2-deploy-platform.sh
# Generated:  $ (date -u +"%Y-%m-%dT%H:%M:%SZ")
# WARNING: This file contains sensitive data. Restrict access.

# --- Database Passwords ---
POSTGRES_PASSWORD= $ {POSTGRES_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
QDRANT_API_KEY=${QDRANT_API_KEY}

# --- Service Database Passwords ---
DIFY_DB_PASSWORD=${DIFY_DB_PASSWORD}
N8N_DB_PASSWORD=${N8N_DB_PASSWORD}
LITELLM_DB_PASSWORD=${LITELLM_DB_PASSWORD}
SUPERTOKENS_DB_PASSWORD=${SUPERTOKENS_DB_PASSWORD}
FLOWISE_DB_PASSWORD=${FLOWISE_DB_PASSWORD}
GRAFANA_DB_PASSWORD=${GRAFANA_DB_PASSWORD}

# --- Secret Keys ---
DIFY_SECRET_KEY=${DIFY_SECRET_KEY}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
LITELLM_ADMIN_KEY=${LITELLM_ADMIN_KEY}
FLOWISE_SECRET_KEY=${FLOWISE_SECRET_KEY}
SUPERTOKENS_API_KEY=${SUPERTOKENS_API_KEY}

# --- Dify-Specific ---
DIFY_INIT_PASSWORD=${DIFY_INIT_PASSWORD}
DIFY_SANDBOX_KEY=${DIFY_SANDBOX_KEY}
DIFY_STORAGE_KEY=${DIFY_STORAGE_KEY}

# --- Grafana ---
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}

# --- Inter-Service Tokens ---
N8N_WEBHOOK_SECRET=${N8N_WEBHOOK_SECRET}

# --- Admin (user-provided) ---
ADMIN_EMAIL=${ADMIN_EMAIL}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
EOF

    chmod 600 "$cred_file"
    log_info "Credentials written to ${cred_file} (mode 600)"
}


Section 16: Phase 4 — master.env Generation
16.1 Purpose
master.env is the single source of truth for ALL platform variables. Every docker-compose file, every service config, and every convenience script references this file.
16.2 Generation Logic
generate_master_env() {
    log_section "Generating master.env"

    local master_file="${CONFIG_PATH}/master.env"

    # Detect host IP
    HOST_IP=$(hostname -I | awk '{print  $ 1}')

    # Set protocol based on SSL mode
    if [[ " $ SSL_MODE" == "none" ]]; then
        URL_PROTOCOL="http"
    else
        URL_PROTOCOL="https"
    fi

    cat > "$master_file" << EOF
# ╔══════════════════════════════════════════════════════════╗
# ║  AI PLATFORM — MASTER ENVIRONMENT FILE                  ║
# ║  Generated:  $ (date -u +"%Y-%m-%dT%H:%M:%SZ")                       ║
# ║  Do not edit manually — regenerate with Script 2        ║
# ╚══════════════════════════════════════════════════════════╝

# ── Paths ──
ROOT_PATH=/opt/ai-platform
CONFIG_PATH=/opt/ai-platform/config
DOCKER_PATH=/opt/ai-platform/docker
DATA_PATH=/opt/ai-platform/data
LOG_PATH=/opt/ai-platform/logs
SCRIPTS_PATH=/opt/ai-platform/scripts
BACKUP_PATH=/opt/ai-platform/backups

# ── Network ──
DOMAIN_MODE= $ {DOMAIN_MODE}
DOMAIN_NAME=${DOMAIN_NAME}
HOST_IP=${HOST_IP}
SSL_MODE=${SSL_MODE}
URL_PROTOCOL=${URL_PROTOCOL}

# ── Hardware ──
SYSTEM_TIER=${SYSTEM_TIER}
GPU_AVAILABLE=${GPU_AVAILABLE}
GPU_VRAM_MB=${GPU_VRAM_MB}
CPU_CORES=${CPU_CORES}
TOTAL_RAM_GB=${TOTAL_RAM_GB}

# ── Feature Flags ──
OPENAI_ENABLED=${OPENAI_ENABLED}
ANTHROPIC_ENABLED=${ANTHROPIC_ENABLED}
GOOGLE_ENABLED=${GOOGLE_ENABLED}
FLOWISE_ENABLED=${FLOWISE_ENABLED}
GRAFANA_ENABLED=${GRAFANA_ENABLED}

# ── Admin ──
ADMIN_EMAIL=${ADMIN_EMAIL}
ADMIN_PASSWORD=${ADMIN_PASSWORD}

# ── Provider API Keys ──
OPENAI_API_KEY=${OPENAI_API_KEY:-}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
GOOGLE_API_KEY=${GOOGLE_API_KEY:-}

# ── PostgreSQL ──
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_USER=postgres
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_SHARED_DB=ai_platform

# Service-specific database names
DIFY_DB_NAME=dify
DIFY_DB_USER=dify
DIFY_DB_PASSWORD=${DIFY_DB_PASSWORD}

N8N_DB_NAME=n8n
N8N_DB_USER=n8n
N8N_DB_PASSWORD=${N8N_DB_PASSWORD}

LITELLM_DB_NAME=litellm
LITELLM_DB_USER=litellm
LITELLM_DB_PASSWORD=${LITELLM_DB_PASSWORD}

SUPERTOKENS_DB_NAME=supertokens
SUPERTOKENS_DB_USER=supertokens
SUPERTOKENS_DB_PASSWORD=${SUPERTOKENS_DB_PASSWORD}

FLOWISE_DB_NAME=flowise
FLOWISE_DB_USER=flowise
FLOWISE_DB_PASSWORD=${FLOWISE_DB_PASSWORD}

GRAFANA_DB_NAME=grafana
GRAFANA_DB_USER=grafana
GRAFANA_DB_PASSWORD=${GRAFANA_DB_PASSWORD}

# ── Redis ──
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=${REDIS_PASSWORD}

# ── Qdrant ──
QDRANT_HOST=qdrant
QDRANT_PORT=6333
QDRANT_GRPC_PORT=6334
QDRANT_API_KEY=${QDRANT_API_KEY}

# ── SuperTokens ──
SUPERTOKENS_HOST=supertokens
SUPERTOKENS_PORT=3567
SUPERTOKENS_API_KEY=${SUPERTOKENS_API_KEY}

# ── Ollama ──
OLLAMA_HOST=${HOST_IP}
OLLAMA_PORT=11434
OLLAMA_BASE_URL=http://${HOST_IP}:11434

# ── LiteLLM ──
LITELLM_HOST=litellm
LITELLM_PORT=4000
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
LITELLM_ADMIN_KEY=${LITELLM_ADMIN_KEY}
LITELLM_BASE_URL=http://litellm:4000

# ── Dify ──
DIFY_API_HOST=dify-api
DIFY_API_PORT=5001
DIFY_WEB_HOST=dify-web
DIFY_WEB_PORT=3000
DIFY_SECRET_KEY=${DIFY_SECRET_KEY}
DIFY_INIT_PASSWORD=${DIFY_INIT_PASSWORD}
DIFY_SANDBOX_KEY=${DIFY_SANDBOX_KEY}
DIFY_STORAGE_KEY=${DIFY_STORAGE_KEY}

# ── n8n ──
N8N_HOST=n8n
N8N_PORT=5678
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_WEBHOOK_SECRET=${N8N_WEBHOOK_SECRET}
N8N_EXTERNAL_URL=${URL_PROTOCOL}://${DOMAIN_NAME}:5678

# ── Open WebUI ──
OPEN_WEBUI_HOST=open-webui
OPEN_WEBUI_PORT=3001

# ── Flowise ──
FLOWISE_HOST=flowise
FLOWISE_PORT=3002
FLOWISE_SECRET_KEY=${FLOWISE_SECRET_KEY}

# ── Caddy ──
CADDY_HTTP_PORT=80
CADDY_HTTPS_PORT=443

# ── Prometheus ──
PROMETHEUS_HOST=prometheus
PROMETHEUS_PORT=9090

# ── Grafana ──
GRAFANA_HOST=grafana
GRAFANA_PORT=3003
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}

# ── Docker Networks ──
NETWORK_FRONTEND=ai-platform
NETWORK_BACKEND=ai-backend

# ── Container Image Versions ──
POSTGRES_IMAGE=postgres:16-alpine
REDIS_IMAGE=redis:7-alpine
QDRANT_IMAGE=qdrant/qdrant:v1.7.4
SUPERTOKENS_IMAGE=registry.supertokens.io/supertokens/supertokens-postgresql:9.0
LITELLM_IMAGE=ghcr.io/berriai/litellm:main-latest
DIFY_API_IMAGE=langgenius/dify-api:0.15.3
DIFY_WEB_IMAGE=langgenius/dify-web:0.15.3
DIFY_SANDBOX_IMAGE=langgenius/dify-sandbox:0.2.10
N8N_IMAGE=docker.n8n.io/n8nio/n8n:latest
OPEN_WEBUI_IMAGE=ghcr.io/open-webui/open-webui:main
FLOWISE_IMAGE=flowiseai/flowise:latest
CADDY_IMAGE=caddy:2-alpine
PROMETHEUS_IMAGE=prom/prometheus:v2.48.0
GRAFANA_IMAGE=grafana/grafana:10.2.0
EOF

    chmod 600 "$master_file"
    log_info "master.env written to ${master_file} (mode 600)"
}


Section 17: Phase 4 — Service Environment Files
17.1 Purpose
Each service gets its own .env file containing only the variables it needs. These are referenced by the per-service docker-compose files.
17.2 PostgreSQL Init SQL
generate_postgres_init() {
    log_info "Generating PostgreSQL init script..."

    cat > "${CONFIG_PATH}/postgres/init-databases.sql" << EOF
-- AI Platform — PostgreSQL Database Initialization
-- Generated by 2-deploy-platform.sh

-- Create service roles and databases

-- Dify
CREATE USER ${DIFY_DB_USER} WITH PASSWORD '${DIFY_DB_PASSWORD}';
CREATE DATABASE ${DIFY_DB_NAME} OWNER ${DIFY_DB_USER};
GRANT ALL PRIVILEGES ON DATABASE ${DIFY_DB_NAME} TO ${DIFY_DB_USER};

-- n8n
CREATE USER ${N8N_DB_USER} WITH PASSWORD '${N8N_DB_PASSWORD}';
CREATE DATABASE ${N8N_DB_NAME} OWNER ${N8N_DB_USER};
GRANT ALL PRIVILEGES ON DATABASE ${N8N_DB_NAME} TO ${N8N_DB_USER};

-- LiteLLM
CREATE USER ${LITELLM_DB_USER} WITH PASSWORD '${LITELLM_DB_PASSWORD}';
CREATE DATABASE ${LITELLM_DB_NAME} OWNER ${LITELLM_DB_USER};
GRANT ALL PRIVILEGES ON DATABASE ${LITELLM_DB_NAME} TO ${LITELLM_DB_USER};

-- SuperTokens
CREATE USER ${SUPERTOKENS_DB_USER} WITH PASSWORD '${SUPERTOKENS_DB_PASSWORD}';
CREATE DATABASE ${SUPERTOKENS_DB_NAME} OWNER ${SUPERTOKENS_DB_USER};
GRANT ALL PRIVILEGES ON DATABASE ${SUPERTOKENS_DB_NAME} TO ${SUPERTOKENS_DB_USER};

-- Flowise (conditional — always create, service may not be deployed)
CREATE USER ${FLOWISE_DB_USER} WITH PASSWORD '${FLOWISE_DB_PASSWORD}';
CREATE DATABASE ${FLOWISE_DB_NAME} OWNER ${FLOWISE_DB_USER};
GRANT ALL PRIVILEGES ON DATABASE ${FLOWISE_DB_NAME} TO ${FLOWISE_DB_USER};

-- Grafana
CREATE USER ${GRAFANA_DB_USER} WITH PASSWORD '${GRAFANA_DB_PASSWORD}';
CREATE DATABASE ${GRAFANA_DB_NAME} OWNER ${GRAFANA_DB_USER};
GRANT ALL PRIVILEGES ON DATABASE ${GRAFANA_DB_NAME} TO ${GRAFANA_DB_USER};

-- Grant schema permissions (required for some services)
\c ${DIFY_DB_NAME}
GRANT ALL ON SCHEMA public TO ${DIFY_DB_USER};

\c ${N8N_DB_NAME}
GRANT ALL ON SCHEMA public TO ${N8N_DB_USER};

\c ${LITELLM_DB_NAME}
GRANT ALL ON SCHEMA public TO ${LITELLM_DB_USER};

\c ${SUPERTOKENS_DB_NAME}
GRANT ALL ON SCHEMA public TO ${SUPERTOKENS_DB_USER};

\c ${FLOWISE_DB_NAME}
GRANT ALL ON SCHEMA public TO ${FLOWISE_DB_USER};

\c ${GRAFANA_DB_NAME}
GRANT ALL ON SCHEMA public TO ${GRAFANA_DB_USER};
EOF

    log_info "PostgreSQL init script generated"
}

17.3 Redis Configuration
generate_redis_config() {
    log_info "Generating Redis configuration..."

    cat > "${CONFIG_PATH}/redis/redis.conf" << EOF
# AI Platform — Redis Configuration
# Generated by 2-deploy-platform.sh

# Network
bind 0.0.0.0
port 6379
protected-mode yes
requirepass ${REDIS_PASSWORD}

# Memory
maxmemory 256mb
maxmemory-policy allkeys-lru

# Persistence
appendonly yes
appendfsync everysec
save 900 1
save 300 10
save 60 10000

# Logging
loglevel notice

# Security
rename-command FLUSHDB ""
rename-command FLUSHALL ""
rename-command DEBUG ""
EOF

    log_info "Redis configuration generated"
}

17.4 LiteLLM Configuration
generate_litellm_config() {
    log_info "Generating LiteLLM configuration..."

    cat > "${CONFIG_PATH}/litellm/config.yaml" << EOF
# AI Platform — LiteLLM Proxy Configuration
# Generated by 2-deploy-platform.sh

model_list:
EOF

    # Always add Ollama models
    cat >> "${CONFIG_PATH}/litellm/config.yaml" << EOF
  # --- Ollama Models (local) ---
  - model_name: llama3.1
    litellm_params:
      model: ollama/llama3.1:8b
      api_base: ${OLLAMA_BASE_URL}
      stream: true

  - model_name: nomic-embed-text
    litellm_params:
      model: ollama/nomic-embed-text
      api_base: ${OLLAMA_BASE_URL}
EOF

    # Conditional: OpenAI
    if [[ " $ OPENAI_ENABLED" == "true" ]]; then
        cat >> " $ {CONFIG_PATH}/litellm/config.yaml" << EOF

  # --- OpenAI Models ---
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: ${OPENAI_API_KEY}

  - model_name: gpt-4o-mini
    litellm_params:
      model: openai/gpt-4o-mini
      api_key: ${OPENAI_API_KEY}

  - model_name: text-embedding-3-small
    litellm_params:
      model: openai/text-embedding-3-small
      api_key: ${OPENAI_API_KEY}
EOF
    fi

    # Conditional: Anthropic
    if [[ " $ ANTHROPIC_ENABLED" == "true" ]]; then
        cat >> " $ {CONFIG_PATH}/litellm/config.yaml" << EOF

  # --- Anthropic Models ---
  - model_name: claude-sonnet-4-20250514
    litellm_params:
      model: anthropic/claude-sonnet-4-20250514
      api_key: ${ANTHROPIC_API_KEY}

  - model_name: claude-3-5-haiku
    litellm_params:
      model: anthropic/claude-3-5-haiku-20241022
      api_key: ${ANTHROPIC_API_KEY}
EOF
    fi

    # Conditional: Google
    if [[ " $ GOOGLE_ENABLED" == "true" ]]; then
        cat >> " $ {CONFIG_PATH}/litellm/config.yaml" << EOF

  # --- Google AI Models ---
  - model_name: gemini-2.0-flash
    litellm_params:
      model: gemini/gemini-2.0-flash
      api_key: ${GOOGLE_API_KEY}

  - model_name: gemini-2.5-pro
    litellm_params:
      model: gemini/gemini-2.5-pro-preview-06-05
      api_key: ${GOOGLE_API_KEY}
EOF
    fi

    # General settings
    cat >> "${CONFIG_PATH}/litellm/config.yaml" << EOF

# --- General Settings ---
litellm_settings:
  drop_params: true
  set_verbose: false
  cache: true
  cache_params:
    type: redis
    host: ${REDIS_HOST}
    port: ${REDIS_PORT}
    password: ${REDIS_PASSWORD}
  success_callback: ["prometheus"]
  failure_callback: ["prometheus"]
  max_budget: 100.0
  budget_duration: "30d"

general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  database_url: "postgresql://${LITELLM_DB_USER}:${LITELLM_DB_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${LITELLM_DB_NAME}"
  alerting:
    - "webhook"
  alerting_threshold: 300
EOF

    log_info "LiteLLM configuration generated"
}

---

## Section 12: Script 2 — Overview & Structure

### 12.1 Purpose

`2-deploy-platform.sh` is the primary deployment script. It collects user preferences via an interactive questionnaire, generates ALL configuration files, creates ALL docker-compose files (one per service), then deploys every container.

### 12.2 Execution

```bash
sudo bash 2-deploy-platform.sh

12.3 Phase Map
Script 2: Deploy Platform
│
├── Phase 1: Pre-flight Checks
│   ├── Verify running as root
│   ├── Verify Docker is running
│   ├── Verify Ollama is running
│   ├── Source hardware-profile.env
│   └── Verify previous script completed
│
├── Phase 2: Interactive Questionnaire
│   ├── Domain / IP configuration
│   ├── SSL mode (Caddy auto vs self-signed vs none)
│   ├── Provider API keys (OpenAI, Anthropic, etc.)
│   ├── Admin email and password preferences
│   └── Optional service toggles
│
├── Phase 3: Credential Generation
│   ├── Generate all passwords (32-char random)
│   ├── Generate all secret keys
│   ├── Generate all API tokens
│   └── Write credentials.env (restricted permissions)
│
├── Phase 4: Configuration File Generation
│   ├── master.env (all variables)
│   ├── Per-service .env files
│   ├── PostgreSQL init SQL
│   ├── Redis configuration
│   ├── LiteLLM config.yaml
│   ├── Caddyfile
│   ├── Prometheus config
│   ├── Grafana provisioning files
│   └── Convenience scripts
│
├── Phase 5: Docker Compose Generation
│   ├── Docker networks creation
│   ├── docker-compose.postgres.yml
│   ├── docker-compose.redis.yml
│   ├── docker-compose.qdrant.yml
│   ├── docker-compose.supertokens.yml
│   ├── docker-compose.litellm.yml
│   ├── docker-compose.dify-api.yml
│   ├── docker-compose.dify-worker.yml
│   ├── docker-compose.dify-web.yml
│   ├── docker-compose.dify-sandbox.yml
│   ├── docker-compose.n8n.yml
│   ├── docker-compose.open-webui.yml
│   ├── docker-compose.flowise.yml
│   ├── docker-compose.caddy.yml
│   ├── docker-compose.prometheus.yml
│   └── docker-compose.grafana.yml
│
├── Phase 6: Deployment
│   ├── Create Docker networks
│   ├── Deploy infrastructure tier (postgres, redis, qdrant, supertokens)
│   ├── Wait for infrastructure healthy
│   ├── Deploy AI tier (litellm, dify-api, dify-worker, dify-web, dify-sandbox)
│   ├── Wait for AI tier healthy
│   ├── Deploy application tier (n8n, open-webui, flowise)
│   ├── Wait for application tier healthy
│   ├── Deploy front tier (caddy)
│   └── Deploy monitoring tier (prometheus, grafana)
│
└── Phase 7: Post-Deploy Validation
    ├── Verify all containers running
    ├── Verify all health checks passing
    ├── Print access URLs
    └── Print next-steps (run script 3)


Section 13: Phase 1 — Pre-flight Checks
13.1 Preflight Logic
preflight_checks() {
    log_section "Pre-flight Checks"

    local errors=0

    # Root check
    if [[  $ EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi

    # Docker
    if ! docker info &>/dev/null; then
        log_error "Docker is not running. Run 1-setup-system.sh first."
        errors= $ ((errors + 1))
    else
        log_info "✓ Docker is running"
    fi

    # Docker Compose
    if ! docker compose version &>/dev/null; then
        log_error "Docker Compose not available. Run 1-setup-system.sh first."
        errors= $ ((errors + 1))
    else
        log_info "✓ Docker Compose available"
    fi

    # Ollama
    if ! curl -sf http://localhost:11434/api/tags &>/dev/null; then
        log_error "Ollama is not running. Run 1-setup-system.sh first."
        errors= $ ((errors + 1))
    else
        log_info "✓ Ollama is running"
    fi

    # Hardware profile
    if [[ ! -f "${CONFIG_PATH}/hardware-profile.env" ]]; then
        log_error "Hardware profile not found. Run 1-setup-system.sh first."
        errors= $ ((errors + 1))
    else
        source " $ {CONFIG_PATH}/hardware-profile.env"
        log_info "✓ Hardware profile loaded (tier: ${SYSTEM_TIER})"
    fi

    # Disk space check (need at least 20GB free for images)
    local free_gb
    free_gb=$(df -BG /var/lib/docker 2>/dev/null | tail -1 | awk '{print  $ 4}' | tr -d 'G')
    if [[ -n " $ free_gb" && " $ free_gb" -lt 20 ]]; then
        log_error "Less than 20GB free in /var/lib/docker — need space for images"
        errors= $ ((errors + 1))
    else
        log_info "✓ Disk space OK (${free_gb}GB free)"
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Pre-flight failed with ${errors} error(s)"
        exit 1
    fi

    log_info "All pre-flight checks passed"
}


Section 14: Phase 2 — Interactive Questionnaire
14.1 Design Principles
Every question has a sensible default (press Enter to accept)
Passwords are never displayed on screen (use read -s)
Input is validated before proceeding
All answers stored in variables for later use
14.2 Questionnaire Logic
run_questionnaire() {
    log_section "Platform Configuration"
    echo ""
    echo "Answer the following questions to configure your platform."
    echo "Press Enter to accept [default] values."
    echo ""

    # --- Network Configuration ---
    echo "─── Network Configuration ───"
    echo ""

    # Domain or IP
    local detected_ip
    detected_ip=$(hostname -I | awk '{print  $ 1}')

    read -rp "Domain name or IP address [ $ {detected_ip}]: " USER_DOMAIN
    USER_DOMAIN="${USER_DOMAIN:- $ detected_ip}"

    # Determine if domain or IP
    if [[ " $ USER_DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        DOMAIN_MODE="ip"
        DOMAIN_NAME=" $ USER_DOMAIN"
        log_info "Mode: IP-based access ( $ {DOMAIN_NAME})"
    else
        DOMAIN_MODE="domain"
        DOMAIN_NAME=" $ USER_DOMAIN"
        log_info "Mode: Domain-based access ( $ {DOMAIN_NAME})"
    fi

    # SSL mode
    echo ""
    if [[ " $ DOMAIN_MODE" == "domain" ]]; then
        echo "SSL Certificate Mode:"
        echo "  1) Automatic (Let's Encrypt via Caddy) — recommended for public domains"
        echo "  2) Self-signed — for internal/private domains"
        echo "  3) None (HTTP only) — not recommended"
        read -rp "SSL mode [1]: " ssl_choice
        case " $ {ssl_choice:-1}" in
            1) SSL_MODE="letsencrypt" ;;
            2) SSL_MODE="selfsigned" ;;
            3) SSL_MODE="none" ;;
            *) SSL_MODE="letsencrypt" ;;
        esac
    else
        echo "IP-based access: SSL will use self-signed certificate"
        SSL_MODE="selfsigned"
    fi
    log_info "SSL mode: ${SSL_MODE}"

    # --- Admin Configuration ---
    echo ""
    echo "─── Admin Configuration ───"
    echo ""

    read -rp "Admin email address [admin@${DOMAIN_NAME}]: " ADMIN_EMAIL
    ADMIN_EMAIL="${ADMIN_EMAIL:-admin@${DOMAIN_NAME}}"

    echo ""
    while true; do
        read -srp "Admin password (min 12 chars): " ADMIN_PASSWORD
        echo ""
        if [[ ${#ADMIN_PASSWORD} -ge 12 ]]; then
            read -srp "Confirm admin password: " ADMIN_PASSWORD_CONFIRM
            echo ""
            if [[ " $ ADMIN_PASSWORD" == " $ ADMIN_PASSWORD_CONFIRM" ]]; then
                break
            else
                echo "Passwords do not match. Try again."
            fi
        else
            echo "Password must be at least 12 characters. Try again."
        fi
    done
    log_info "Admin credentials configured"

    # --- LLM Provider API Keys ---
    echo ""
    echo "─── LLM Provider API Keys (optional — press Enter to skip) ───"
    echo ""

    read -srp "OpenAI API key: " OPENAI_API_KEY
    echo ""
    OPENAI_API_KEY="${OPENAI_API_KEY:-}"
    if [[ -n " $ OPENAI_API_KEY" ]]; then
        OPENAI_ENABLED="true"
        log_info "OpenAI: configured"
    else
        OPENAI_ENABLED="false"
        log_info "OpenAI: skipped"
    fi

    read -srp "Anthropic API key: " ANTHROPIC_API_KEY
    echo ""
    ANTHROPIC_API_KEY=" $ {ANTHROPIC_API_KEY:-}"
    if [[ -n " $ ANTHROPIC_API_KEY" ]]; then
        ANTHROPIC_ENABLED="true"
        log_info "Anthropic: configured"
    else
        ANTHROPIC_ENABLED="false"
        log_info "Anthropic: skipped"
    fi

    read -srp "Google AI (Gemini) API key: " GOOGLE_API_KEY
    echo ""
    GOOGLE_API_KEY=" $ {GOOGLE_API_KEY:-}"
    if [[ -n " $ GOOGLE_API_KEY" ]]; then
        GOOGLE_ENABLED="true"
        log_info "Google AI: configured"
    else
        GOOGLE_ENABLED="false"
        log_info "Google AI: skipped"
    fi

    # --- Optional Services ---
    echo ""
    echo "─── Optional Services ───"
    echo ""

    read -rp "Enable Flowise? (visual workflow builder) [y/N]: " enable_flowise
    FLOWISE_ENABLED="false"
    [[ " $ {enable_flowise,,}" == "y" ]] && FLOWISE_ENABLED="true"
    log_info "Flowise: ${FLOWISE_ENABLED}"

    read -rp "Enable Grafana monitoring? [Y/n]: " enable_grafana
    GRAFANA_ENABLED="true"
    [[ "${enable_grafana,,}" == "n" ]] && GRAFANA_ENABLED="false"
    log_info "Grafana: ${GRAFANA_ENABLED}"

    # --- Summary ---
    echo ""
    echo "─── Configuration Summary ───"
    echo ""
    echo "  Domain/IP:     ${DOMAIN_NAME} (${DOMAIN_MODE} mode)"
    echo "  SSL:           ${SSL_MODE}"
    echo "  Admin email:   ${ADMIN_EMAIL}"
    echo "  OpenAI:        ${OPENAI_ENABLED}"
    echo "  Anthropic:     ${ANTHROPIC_ENABLED}"
    echo "  Google AI:     ${GOOGLE_ENABLED}"
    echo "  Flowise:       ${FLOWISE_ENABLED}"
    echo "  Grafana:       ${GRAFANA_ENABLED}"
    echo "  System tier:   ${SYSTEM_TIER}"
    echo ""
    read -rp "Proceed with this configuration? [Y/n]: " confirm
    if [[ "${confirm,,}" == "n" ]]; then
        log_info "Cancelled by user"
        exit 0
    fi
}


Section 15: Phase 3 — Credential Generation
15.1 Generation Functions
generate_password() {
    # Generate a random password of specified length
    local length="${1:-32}"
    openssl rand -base64 48 | tr -dc 'A-Za-z0-9!@# $ %' | head -c " $ length"
}

generate_hex_key() {
    # Generate a hex key (for secret keys)
    local length="${1:-64}"
    openssl rand -hex "$((length / 2))"
}

generate_uuid() {
    cat /proc/sys/kernel/random/uuid
}

15.2 Credential Generation Logic
generate_all_credentials() {
    log_section "Generating Credentials"

    # Database passwords
    POSTGRES_PASSWORD= $ (generate_password 32)
    REDIS_PASSWORD= $ (generate_password 32)
    QDRANT_API_KEY= $ (generate_password 32)

    # Service-specific database passwords
    DIFY_DB_PASSWORD= $ (generate_password 32)
    N8N_DB_PASSWORD= $ (generate_password 32)
    LITELLM_DB_PASSWORD= $ (generate_password 32)
    SUPERTOKENS_DB_PASSWORD= $ (generate_password 32)
    FLOWISE_DB_PASSWORD= $ (generate_password 32)
    GRAFANA_DB_PASSWORD= $ (generate_password 32)

    # Secret keys
    DIFY_SECRET_KEY= $ (generate_hex_key 64)
    N8N_ENCRYPTION_KEY= $ (generate_hex_key 64)
    LITELLM_MASTER_KEY="sk-litellm- $ (generate_password 32)"
    LITELLM_ADMIN_KEY="sk-admin- $ (generate_password 32)"
    FLOWISE_SECRET_KEY= $ (generate_hex_key 64)
    SUPERTOKENS_API_KEY= $ (generate_password 32)

    # Dify-specific keys
    DIFY_INIT_PASSWORD= $ (generate_password 16)
    DIFY_SANDBOX_KEY= $ (generate_hex_key 32)
    DIFY_STORAGE_KEY= $ (generate_hex_key 32)

    # Grafana
    GRAFANA_ADMIN_PASSWORD= $ (generate_password 24)

    # Inter-service tokens
    N8N_WEBHOOK_SECRET= $ (generate_hex_key 32)

    log_info "All credentials generated (${credential_count} items)"
}

15.3 Credentials File Output
write_credentials_file() {
    local cred_file="${CONFIG_PATH}/credentials.env"

    cat > "$cred_file" << EOF
# Platform Credentials — Generated by 2-deploy-platform.sh
# Generated:  $ (date -u +"%Y-%m-%dT%H:%M:%SZ")
# WARNING: This file contains sensitive data. Restrict access.

# --- Database Passwords ---
POSTGRES_PASSWORD= $ {POSTGRES_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
QDRANT_API_KEY=${QDRANT_API_KEY}

# --- Service Database Passwords ---
DIFY_DB_PASSWORD=${DIFY_DB_PASSWORD}
N8N_DB_PASSWORD=${N8N_DB_PASSWORD}
LITELLM_DB_PASSWORD=${LITELLM_DB_PASSWORD}
SUPERTOKENS_DB_PASSWORD=${SUPERTOKENS_DB_PASSWORD}
FLOWISE_DB_PASSWORD=${FLOWISE_DB_PASSWORD}
GRAFANA_DB_PASSWORD=${GRAFANA_DB_PASSWORD}

# --- Secret Keys ---
DIFY_SECRET_KEY=${DIFY_SECRET_KEY}
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
LITELLM_ADMIN_KEY=${LITELLM_ADMIN_KEY}
FLOWISE_SECRET_KEY=${FLOWISE_SECRET_KEY}
SUPERTOKENS_API_KEY=${SUPERTOKENS_API_KEY}

# --- Dify-Specific ---
DIFY_INIT_PASSWORD=${DIFY_INIT_PASSWORD}
DIFY_SANDBOX_KEY=${DIFY_SANDBOX_KEY}
DIFY_STORAGE_KEY=${DIFY_STORAGE_KEY}

# --- Grafana ---
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}

# --- Inter-Service Tokens ---
N8N_WEBHOOK_SECRET=${N8N_WEBHOOK_SECRET}

# --- Admin (user-provided) ---
ADMIN_EMAIL=${ADMIN_EMAIL}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
EOF

    chmod 600 "$cred_file"
    log_info "Credentials written to ${cred_file} (mode 600)"
}


Section 16: Phase 4 — master.env Generation
16.1 Purpose
master.env is the single source of truth for ALL platform variables. Every docker-compose file, every service config, and every convenience script references this file.
16.2 Generation Logic
generate_master_env() {
    log_section "Generating master.env"

    local master_file="${CONFIG_PATH}/master.env"

    # Detect host IP
    HOST_IP=$(hostname -I | awk '{print  $ 1}')

    # Set protocol based on SSL mode
    if [[ " $ SSL_MODE" == "none" ]]; then
        URL_PROTOCOL="http"
    else
        URL_PROTOCOL="https"
    fi

    cat > "$master_file" << EOF
# ╔══════════════════════════════════════════════════════════╗
# ║  AI PLATFORM — MASTER ENVIRONMENT FILE                  ║
# ║  Generated:  $ (date -u +"%Y-%m-%dT%H:%M:%SZ")                       ║
# ║  Do not edit manually — regenerate with Script 2        ║
# ╚══════════════════════════════════════════════════════════╝

# ── Paths ──
ROOT_PATH=/opt/ai-platform
CONFIG_PATH=/opt/ai-platform/config
DOCKER_PATH=/opt/ai-platform/docker
DATA_PATH=/opt/ai-platform/data
LOG_PATH=/opt/ai-platform/logs
SCRIPTS_PATH=/opt/ai-platform/scripts
BACKUP_PATH=/opt/ai-platform/backups

# ── Network ──
DOMAIN_MODE= $ {DOMAIN_MODE}
DOMAIN_NAME=${DOMAIN_NAME}
HOST_IP=${HOST_IP}
SSL_MODE=${SSL_MODE}
URL_PROTOCOL=${URL_PROTOCOL}

# ── Hardware ──
SYSTEM_TIER=${SYSTEM_TIER}
GPU_AVAILABLE=${GPU_AVAILABLE}
GPU_VRAM_MB=${GPU_VRAM_MB}
CPU_CORES=${CPU_CORES}
TOTAL_RAM_GB=${TOTAL_RAM_GB}

# ── Feature Flags ──
OPENAI_ENABLED=${OPENAI_ENABLED}
ANTHROPIC_ENABLED=${ANTHROPIC_ENABLED}
GOOGLE_ENABLED=${GOOGLE_ENABLED}
FLOWISE_ENABLED=${FLOWISE_ENABLED}
GRAFANA_ENABLED=${GRAFANA_ENABLED}

# ── Admin ──
ADMIN_EMAIL=${ADMIN_EMAIL}
ADMIN_PASSWORD=${ADMIN_PASSWORD}

# ── Provider API Keys ──
OPENAI_API_KEY=${OPENAI_API_KEY:-}
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
GOOGLE_API_KEY=${GOOGLE_API_KEY:-}

# ── PostgreSQL ──
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_USER=postgres
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_SHARED_DB=ai_platform

# Service-specific database names
DIFY_DB_NAME=dify
DIFY_DB_USER=dify
DIFY_DB_PASSWORD=${DIFY_DB_PASSWORD}

N8N_DB_NAME=n8n
N8N_DB_USER=n8n
N8N_DB_PASSWORD=${N8N_DB_PASSWORD}

LITELLM_DB_NAME=litellm
LITELLM_DB_USER=litellm
LITELLM_DB_PASSWORD=${LITELLM_DB_PASSWORD}

SUPERTOKENS_DB_NAME=supertokens
SUPERTOKENS_DB_USER=supertokens
SUPERTOKENS_DB_PASSWORD=${SUPERTOKENS_DB_PASSWORD}

FLOWISE_DB_NAME=flowise
FLOWISE_DB_USER=flowise
FLOWISE_DB_PASSWORD=${FLOWISE_DB_PASSWORD}

GRAFANA_DB_NAME=grafana
GRAFANA_DB_USER=grafana
GRAFANA_DB_PASSWORD=${GRAFANA_DB_PASSWORD}

# ── Redis ──
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=${REDIS_PASSWORD}

# ── Qdrant ──
QDRANT_HOST=qdrant
QDRANT_PORT=6333
QDRANT_GRPC_PORT=6334
QDRANT_API_KEY=${QDRANT_API_KEY}

# ── SuperTokens ──
SUPERTOKENS_HOST=supertokens
SUPERTOKENS_PORT=3567
SUPERTOKENS_API_KEY=${SUPERTOKENS_API_KEY}

# ── Ollama ──
OLLAMA_HOST=${HOST_IP}
OLLAMA_PORT=11434
OLLAMA_BASE_URL=http://${HOST_IP}:11434

# ── LiteLLM ──
LITELLM_HOST=litellm
LITELLM_PORT=4000
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
LITELLM_ADMIN_KEY=${LITELLM_ADMIN_KEY}
LITELLM_BASE_URL=http://litellm:4000

# ── Dify ──
DIFY_API_HOST=dify-api
DIFY_API_PORT=5001
DIFY_WEB_HOST=dify-web
DIFY_WEB_PORT=3000
DIFY_SECRET_KEY=${DIFY_SECRET_KEY}
DIFY_INIT_PASSWORD=${DIFY_INIT_PASSWORD}
DIFY_SANDBOX_KEY=${DIFY_SANDBOX_KEY}
DIFY_STORAGE_KEY=${DIFY_STORAGE_KEY}

# ── n8n ──
N8N_HOST=n8n
N8N_PORT=5678
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_WEBHOOK_SECRET=${N8N_WEBHOOK_SECRET}
N8N_EXTERNAL_URL=${URL_PROTOCOL}://${DOMAIN_NAME}:5678

# ── Open WebUI ──
OPEN_WEBUI_HOST=open-webui
OPEN_WEBUI_PORT=3001

# ── Flowise ──
FLOWISE_HOST=flowise
FLOWISE_PORT=3002
FLOWISE_SECRET_KEY=${FLOWISE_SECRET_KEY}

# ── Caddy ──
CADDY_HTTP_PORT=80
CADDY_HTTPS_PORT=443

# ── Prometheus ──
PROMETHEUS_HOST=prometheus
PROMETHEUS_PORT=9090

# ── Grafana ──
GRAFANA_HOST=grafana
GRAFANA_PORT=3003
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}

# ── Docker Networks ──
NETWORK_FRONTEND=ai-platform
NETWORK_BACKEND=ai-backend

# ── Container Image Versions ──
POSTGRES_IMAGE=postgres:16-alpine
REDIS_IMAGE=redis:7-alpine
QDRANT_IMAGE=qdrant/qdrant:v1.7.4
SUPERTOKENS_IMAGE=registry.supertokens.io/supertokens/supertokens-postgresql:9.0
LITELLM_IMAGE=ghcr.io/berriai/litellm:main-latest
DIFY_API_IMAGE=langgenius/dify-api:0.15.3
DIFY_WEB_IMAGE=langgenius/dify-web:0.15.3
DIFY_SANDBOX_IMAGE=langgenius/dify-sandbox:0.2.10
N8N_IMAGE=docker.n8n.io/n8nio/n8n:latest
OPEN_WEBUI_IMAGE=ghcr.io/open-webui/open-webui:main
FLOWISE_IMAGE=flowiseai/flowise:latest
CADDY_IMAGE=caddy:2-alpine
PROMETHEUS_IMAGE=prom/prometheus:v2.48.0
GRAFANA_IMAGE=grafana/grafana:10.2.0
EOF

    chmod 600 "$master_file"
    log_info "master.env written to ${master_file} (mode 600)"
}


Section 17: Phase 4 — Service Environment Files
17.1 Purpose
Each service gets its own .env file containing only the variables it needs. These are referenced by the per-service docker-compose files.
17.2 PostgreSQL Init SQL
generate_postgres_init() {
    log_info "Generating PostgreSQL init script..."

    cat > "${CONFIG_PATH}/postgres/init-databases.sql" << EOF
-- AI Platform — PostgreSQL Database Initialization
-- Generated by 2-deploy-platform.sh

-- Create service roles and databases

-- Dify
CREATE USER ${DIFY_DB_USER} WITH PASSWORD '${DIFY_DB_PASSWORD}';
CREATE DATABASE ${DIFY_DB_NAME} OWNER ${DIFY_DB_USER};
GRANT ALL PRIVILEGES ON DATABASE ${DIFY_DB_NAME} TO ${DIFY_DB_USER};

-- n8n
CREATE USER ${N8N_DB_USER} WITH PASSWORD '${N8N_DB_PASSWORD}';
CREATE DATABASE ${N8N_DB_NAME} OWNER ${N8N_DB_USER};
GRANT ALL PRIVILEGES ON DATABASE ${N8N_DB_NAME} TO ${N8N_DB_USER};

-- LiteLLM
CREATE USER ${LITELLM_DB_USER} WITH PASSWORD '${LITELLM_DB_PASSWORD}';
CREATE DATABASE ${LITELLM_DB_NAME} OWNER ${LITELLM_DB_USER};
GRANT ALL PRIVILEGES ON DATABASE ${LITELLM_DB_NAME} TO ${LITELLM_DB_USER};

-- SuperTokens
CREATE USER ${SUPERTOKENS_DB_USER} WITH PASSWORD '${SUPERTOKENS_DB_PASSWORD}';
CREATE DATABASE ${SUPERTOKENS_DB_NAME} OWNER ${SUPERTOKENS_DB_USER};
GRANT ALL PRIVILEGES ON DATABASE ${SUPERTOKENS_DB_NAME} TO ${SUPERTOKENS_DB_USER};

-- Flowise (conditional — always create, service may not be deployed)
CREATE USER ${FLOWISE_DB_USER} WITH PASSWORD '${FLOWISE_DB_PASSWORD}';
CREATE DATABASE ${FLOWISE_DB_NAME} OWNER ${FLOWISE_DB_USER};
GRANT ALL PRIVILEGES ON DATABASE ${FLOWISE_DB_NAME} TO ${FLOWISE_DB_USER};

-- Grafana
CREATE USER ${GRAFANA_DB_USER} WITH PASSWORD '${GRAFANA_DB_PASSWORD}';
CREATE DATABASE ${GRAFANA_DB_NAME} OWNER ${GRAFANA_DB_USER};
GRANT ALL PRIVILEGES ON DATABASE ${GRAFANA_DB_NAME} TO ${GRAFANA_DB_USER};

-- Grant schema permissions (required for some services)
\c ${DIFY_DB_NAME}
GRANT ALL ON SCHEMA public TO ${DIFY_DB_USER};

\c ${N8N_DB_NAME}
GRANT ALL ON SCHEMA public TO ${N8N_DB_USER};

\c ${LITELLM_DB_NAME}
GRANT ALL ON SCHEMA public TO ${LITELLM_DB_USER};

\c ${SUPERTOKENS_DB_NAME}
GRANT ALL ON SCHEMA public TO ${SUPERTOKENS_DB_USER};

\c ${FLOWISE_DB_NAME}
GRANT ALL ON SCHEMA public TO ${FLOWISE_DB_USER};

\c ${GRAFANA_DB_NAME}
GRANT ALL ON SCHEMA public TO ${GRAFANA_DB_USER};
EOF

    log_info "PostgreSQL init script generated"
}

17.3 Redis Configuration
generate_redis_config() {
    log_info "Generating Redis configuration..."

    cat > "${CONFIG_PATH}/redis/redis.conf" << EOF
# AI Platform — Redis Configuration
# Generated by 2-deploy-platform.sh

# Network
bind 0.0.0.0
port 6379
protected-mode yes
requirepass ${REDIS_PASSWORD}

# Memory
maxmemory 256mb
maxmemory-policy allkeys-lru

# Persistence
appendonly yes
appendfsync everysec
save 900 1
save 300 10
save 60 10000

# Logging
loglevel notice

# Security
rename-command FLUSHDB ""
rename-command FLUSHALL ""
rename-command DEBUG ""
EOF

    log_info "Redis configuration generated"
}

17.4 LiteLLM Configuration
generate_litellm_config() {
    log_info "Generating LiteLLM configuration..."

    cat > "${CONFIG_PATH}/litellm/config.yaml" << EOF
# AI Platform — LiteLLM Proxy Configuration
# Generated by 2-deploy-platform.sh

model_list:
EOF

    # Always add Ollama models
    cat >> "${CONFIG_PATH}/litellm/config.yaml" << EOF
  # --- Ollama Models (local) ---
  - model_name: llama3.1
    litellm_params:
      model: ollama/llama3.1:8b
      api_base: ${OLLAMA_BASE_URL}
      stream: true

  - model_name: nomic-embed-text
    litellm_params:
      model: ollama/nomic-embed-text
      api_base: ${OLLAMA_BASE_URL}
EOF

    # Conditional: OpenAI
    if [[ " $ OPENAI_ENABLED" == "true" ]]; then
        cat >> " $ {CONFIG_PATH}/litellm/config.yaml" << EOF

  # --- OpenAI Models ---
  - model_name: gpt-4o
    litellm_params:
      model: openai/gpt-4o
      api_key: ${OPENAI_API_KEY}

  - model_name: gpt-4o-mini
    litellm_params:
      model: openai/gpt-4o-mini
      api_key: ${OPENAI_API_KEY}

  - model_name: text-embedding-3-small
    litellm_params:
      model: openai/text-embedding-3-small
      api_key: ${OPENAI_API_KEY}
EOF
    fi

    # Conditional: Anthropic
    if [[ " $ ANTHROPIC_ENABLED" == "true" ]]; then
        cat >> " $ {CONFIG_PATH}/litellm/config.yaml" << EOF

  # --- Anthropic Models ---
  - model_name: claude-sonnet-4-20250514
    litellm_params:
      model: anthropic/claude-sonnet-4-20250514
      api_key: ${ANTHROPIC_API_KEY}

  - model_name: claude-3-5-haiku
    litellm_params:
      model: anthropic/claude-3-5-haiku-20241022
      api_key: ${ANTHROPIC_API_KEY}
EOF
    fi

    # Conditional: Google
    if [[ " $ GOOGLE_ENABLED" == "true" ]]; then
        cat >> " $ {CONFIG_PATH}/litellm/config.yaml" << EOF

  # --- Google AI Models ---
  - model_name: gemini-2.0-flash
    litellm_params:
      model: gemini/gemini-2.0-flash
      api_key: ${GOOGLE_API_KEY}

  - model_name: gemini-2.5-pro
    litellm_params:
      model: gemini/gemini-2.5-pro-preview-06-05
      api_key: ${GOOGLE_API_KEY}
EOF
    fi

    # General settings
    cat >> "${CONFIG_PATH}/litellm/config.yaml" << EOF

# --- General Settings ---
litellm_settings:
  drop_params: true
  set_verbose: false
  cache: true
  cache_params:
    type: redis
    host: ${REDIS_HOST}
    port: ${REDIS_PORT}
    password: ${REDIS_PASSWORD}
  success_callback: ["prometheus"]
  failure_callback: ["prometheus"]
  max_budget: 100.0
  budget_duration: "30d"

general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  database_url: "postgresql://${LITELLM_DB_USER}:${LITELLM_DB_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${LITELLM_DB_NAME}"
  alerting:
    - "webhook"
  alerting_threshold: 300
EOF

    log_info "LiteLLM configuration generated"
}

---

## Section 18: Phase 4 — Caddyfile Generation

### 18.1 Purpose

Caddy serves as the reverse proxy / TLS termination layer. The Caddyfile routes traffic to each service based on port or path.

### 18.2 IP-Based Caddyfile (port routing)

When running in IP mode, each service gets its own port on the host.

```bash
generate_caddyfile() {
    log_info "Generating Caddyfile..."

    mkdir -p "${CONFIG_PATH}/caddy"

    if [[ " $ DOMAIN_MODE" == "ip" ]]; then
        generate_caddyfile_ip
    else
        generate_caddyfile_domain
    fi

    log_info "Caddyfile generated"
}

generate_caddyfile_ip() {
    cat > " $ {CONFIG_PATH}/caddy/Caddyfile" << 'CADDYEOF'
# AI Platform — Caddyfile (IP mode)
# Generated by 2-deploy-platform.sh
# Each service on its own port with self-signed TLS

{
    auto_https disable_redirects
    admin off
    log {
        level INFO
        output file /data/logs/caddy.log {
            roll_size 10mb
            roll_keep 5
        }
    }
}

CADDYEOF

    # Dify Web — port 443 (main entry)
    cat >> "${CONFIG_PATH}/caddy/Caddyfile" << EOF
:443 {
    tls internal
    reverse_proxy dify-web:3000
    handle_path /api/* {
        reverse_proxy dify-api:5001
    }
    handle_path /console/api/* {
        reverse_proxy dify-api:5001
    }
    handle_path /v1/* {
        reverse_proxy dify-api:5001
    }
    handle_path /files/* {
        reverse_proxy dify-api:5001
    }
}

# n8n — port 5678
:5678 {
    tls internal
    reverse_proxy n8n:5678
}

# Open WebUI — port 3001
:3001 {
    tls internal
    reverse_proxy open-webui:8080
}

# LiteLLM — port 4000
:4000 {
    tls internal
    reverse_proxy litellm:4000
}
EOF

    # Conditional: Flowise
    if [[ " $ FLOWISE_ENABLED" == "true" ]]; then
        cat >> " $ {CONFIG_PATH}/caddy/Caddyfile" << EOF

# Flowise — port 3002
:3002 {
    tls internal
    reverse_proxy flowise:3000
}
EOF
    fi

    # Conditional: Grafana
    if [[ " $ GRAFANA_ENABLED" == "true" ]]; then
        cat >> " $ {CONFIG_PATH}/caddy/Caddyfile" << EOF

# Grafana — port 3003
:3003 {
    tls internal
    reverse_proxy grafana:3000
}
EOF
    fi
}

18.3 Domain-Based Caddyfile (subdomain routing)
generate_caddyfile_domain() {
    local tls_directive
    if [[ "$SSL_MODE" == "letsencrypt" ]]; then
        tls_directive="tls ${ADMIN_EMAIL}"
    elif [[ " $ SSL_MODE" == "selfsigned" ]]; then
        tls_directive="tls internal"
    else
        tls_directive=""
    fi

    cat > " $ {CONFIG_PATH}/caddy/Caddyfile" << EOF
# AI Platform — Caddyfile (Domain mode)
# Generated by 2-deploy-platform.sh

{
    email ${ADMIN_EMAIL}
    log {
        level INFO
        output file /data/logs/caddy.log {
            roll_size 10mb
            roll_keep 5
        }
    }
}

# Dify — main domain
${DOMAIN_NAME} {
    ${tls_directive}
    reverse_proxy dify-web:3000

    handle_path /api/* {
        reverse_proxy dify-api:5001
    }
    handle_path /console/api/* {
        reverse_proxy dify-api:5001
    }
    handle_path /v1/* {
        reverse_proxy dify-api:5001
    }
    handle_path /files/* {
        reverse_proxy dify-api:5001
    }
}

# n8n
n8n.${DOMAIN_NAME} {
    ${tls_directive}
    reverse_proxy n8n:5678
}

# Open WebUI
chat.${DOMAIN_NAME} {
    ${tls_directive}
    reverse_proxy open-webui:8080
}

# LiteLLM
llm.${DOMAIN_NAME} {
    ${tls_directive}
    reverse_proxy litellm:4000
}
EOF

    if [[ " $ FLOWISE_ENABLED" == "true" ]]; then
        cat >> " $ {CONFIG_PATH}/caddy/Caddyfile" << EOF

# Flowise
flow.${DOMAIN_NAME} {
    ${tls_directive}
    reverse_proxy flowise:3000
}
EOF
    fi

    if [[ " $ GRAFANA_ENABLED" == "true" ]]; then
        cat >> " $ {CONFIG_PATH}/caddy/Caddyfile" << EOF

# Grafana
grafana.${DOMAIN_NAME} {
    ${tls_directive}
    reverse_proxy grafana:3000
}
EOF
    fi
}


Section 19: Phase 4 — Prometheus & Grafana Configuration
19.1 Prometheus Configuration
generate_prometheus_config() {
    log_info "Generating Prometheus configuration..."

    mkdir -p "${CONFIG_PATH}/prometheus"

    cat > "${CONFIG_PATH}/prometheus/prometheus.yml" << EOF
# AI Platform — Prometheus Configuration
# Generated by 2-deploy-platform.sh

global:
  scrape_interval: 15s
  evaluation_interval: 15s
  scrape_timeout: 10s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'litellm'
    static_configs:
      - targets: ['litellm:4000']
    metrics_path: /metrics

  - job_name: 'caddy'
    static_configs:
      - targets: ['caddy:2019']
    metrics_path: /metrics

  - job_name: 'docker'
    static_configs:
      - targets: ['${HOST_IP}:9323']

  - job_name: 'node'
    static_configs:
      - targets: ['${HOST_IP}:9100']
EOF

    log_info "Prometheus configuration generated"
}

19.2 Grafana Provisioning
generate_grafana_provisioning() {
    log_info "Generating Grafana provisioning..."

    mkdir -p "${CONFIG_PATH}/grafana/provisioning/datasources"
    mkdir -p "${CONFIG_PATH}/grafana/provisioning/dashboards"
    mkdir -p "${CONFIG_PATH}/grafana/dashboards"

    # Datasource provisioning
    cat > "${CONFIG_PATH}/grafana/provisioning/datasources/prometheus.yml" << EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
EOF

    # Dashboard provisioning config
    cat > "${CONFIG_PATH}/grafana/provisioning/dashboards/default.yml" << EOF
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: 'AI Platform'
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: false
EOF

    log_info "Grafana provisioning generated"
}


Section 20: Phase 5 — Docker Compose Files (Infrastructure Tier)
20.1 Design Principles
One file per service — enables individual restart/update
All files reference the same external networks
Environment variables inline (not via env_file) to avoid path issues
Health checks on every service
Named volumes with consistent naming: ai-platform-<service>-data
Resource limits based on SYSTEM_TIER
20.2 Network Creation
create_docker_networks() {
    log_section "Creating Docker Networks"

    # Frontend network (services + Caddy)
    if ! docker network inspect ai-platform &>/dev/null; then
        docker network create ai-platform
        log_info "Created network: ai-platform"
    else
        log_info "Network ai-platform already exists"
    fi

    # Backend network (infrastructure only)
    if ! docker network inspect ai-backend &>/dev/null; then
        docker network create ai-backend
        log_info "Created network: ai-backend"
    else
        log_info "Network ai-backend already exists"
    fi
}

20.3 Docker Compose — PostgreSQL
generate_compose_postgres() {
    log_info "Generating docker-compose.postgres.yml..."

    cat > "${DOCKER_PATH}/docker-compose.postgres.yml" << EOF
# AI Platform — PostgreSQL
# Generated by 2-deploy-platform.sh

services:
  postgres:
    image: ${POSTGRES_IMAGE}
    container_name: ai-platform-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_SHARED_DB}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - ai-platform-postgres-data:/var/lib/postgresql/data
      - ${CONFIG_PATH}/postgres/init-databases.sql:/docker-entrypoint-initdb.d/init-databases.sql:ro
    networks:
      - ai-backend
    ports:
      - "127.0.0.1:5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    deploy:
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 256M

volumes:
  ai-platform-postgres-data:
    name: ai-platform-postgres-data

networks:
  ai-backend:
    external: true
EOF

    log_info "docker-compose.postgres.yml generated"
}

20.4 Docker Compose — Redis
generate_compose_redis() {
    log_info "Generating docker-compose.redis.yml..."

    cat > "${DOCKER_PATH}/docker-compose.redis.yml" << EOF
# AI Platform — Redis
# Generated by 2-deploy-platform.sh

services:
  redis:
    image: ${REDIS_IMAGE}
    container_name: ai-platform-redis
    restart: unless-stopped
    command: redis-server /usr/local/etc/redis/redis.conf
    volumes:
      - ai-platform-redis-data:/data
      - ${CONFIG_PATH}/redis/redis.conf:/usr/local/etc/redis/redis.conf:ro
    networks:
      - ai-backend
    ports:
      - "127.0.0.1:6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 64M

volumes:
  ai-platform-redis-data:
    name: ai-platform-redis-data

networks:
  ai-backend:
    external: true
EOF

    log_info "docker-compose.redis.yml generated"
}

20.5 Docker Compose — Qdrant
generate_compose_qdrant() {
    log_info "Generating docker-compose.qdrant.yml..."

    cat > "${DOCKER_PATH}/docker-compose.qdrant.yml" << EOF
# AI Platform — Qdrant Vector Database
# Generated by 2-deploy-platform.sh

services:
  qdrant:
    image: ${QDRANT_IMAGE}
    container_name: ai-platform-qdrant
    restart: unless-stopped
    environment:
      QDRANT__SERVICE__API_KEY: ${QDRANT_API_KEY}
      QDRANT__SERVICE__GRPC_PORT: 6334
    volumes:
      - ai-platform-qdrant-data:/qdrant/storage
    networks:
      - ai-backend
    ports:
      - "127.0.0.1:6333:6333"
      - "127.0.0.1:6334:6334"
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:6333/healthz || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 15s
    deploy:
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 256M

volumes:
  ai-platform-qdrant-data:
    name: ai-platform-qdrant-data

networks:
  ai-backend:
    external: true
EOF

    log_info "docker-compose.qdrant.yml generated"
}

20.6 Docker Compose — SuperTokens
generate_compose_supertokens() {
    log_info "Generating docker-compose.supertokens.yml..."

    cat > "${DOCKER_PATH}/docker-compose.supertokens.yml" << EOF
# AI Platform — SuperTokens Authentication
# Generated by 2-deploy-platform.sh

services:
  supertokens:
    image: ${SUPERTOKENS_IMAGE}
    container_name: ai-platform-supertokens
    restart: unless-stopped
    environment:
      POSTGRESQL_CONNECTION_URI: "postgresql://${SUPERTOKENS_DB_USER}:${SUPERTOKENS_DB_PASSWORD}@postgres:5432/${SUPERTOKENS_DB_NAME}"
      API_KEYS: ${SUPERTOKENS_API_KEY}
    networks:
      - ai-backend
    ports:
      - "127.0.0.1:3567:3567"
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:3567/hello || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    depends_on:
      postgres:
        condition: service_healthy
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 128M

networks:
  ai-backend:
    external: true
EOF

    log_info "docker-compose.supertokens.yml generated"
}


Section 21: Phase 5 — Docker Compose Files (AI Tier)
21.1 Docker Compose — LiteLLM
generate_compose_litellm() {
    log_info "Generating docker-compose.litellm.yml..."

    cat > "${DOCKER_PATH}/docker-compose.litellm.yml" << EOF
# AI Platform — LiteLLM Proxy
# Generated by 2-deploy-platform.sh

services:
  litellm:
    image: ${LITELLM_IMAGE}
    container_name: ai-platform-litellm
    restart: unless-stopped
    command: --config /app/config.yaml --port 4000
    environment:
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
      LITELLM_ADMIN_KEY: ${LITELLM_ADMIN_KEY}
      DATABASE_URL: "postgresql://${LITELLM_DB_USER}:${LITELLM_DB_PASSWORD}@postgres:5432/${LITELLM_DB_NAME}"
      REDIS_HOST: ${REDIS_HOST}
      REDIS_PORT: ${REDIS_PORT}
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      STORE_MODEL_IN_DB: "True"
    volumes:
      - ${CONFIG_PATH}/litellm/config.yaml:/app/config.yaml:ro
    networks:
      - ai-platform
      - ai-backend
    ports:
      - "127.0.0.1:4000:4000"
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:4000/health/liveliness || exit 1"]
      interval: 15s
      timeout: 10s
      retries: 5
      start_period: 45s
    extra_hosts:
      - "host.docker.internal:host-gateway"
    deploy:
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 256M

networks:
  ai-platform:
    external: true
  ai-backend:
    external: true
EOF

    log_info "docker-compose.litellm.yml generated"
}

21.2 Docker Compose — Dify API
generate_compose_dify_api() {
    log_info "Generating docker-compose.dify-api.yml..."

    cat > "${DOCKER_PATH}/docker-compose.dify-api.yml" << EOF
# AI Platform — Dify API Server
# Generated by 2-deploy-platform.sh

services:
  dify-api:
    image: ${DIFY_API_IMAGE}
    container_name: ai-platform-dify-api
    restart: unless-stopped
    environment:
      MODE: api
      LOG_LEVEL: INFO
      SECRET_KEY: ${DIFY_SECRET_KEY}
      INIT_PASSWORD: ${DIFY_INIT_PASSWORD}
      CONSOLE_WEB_URL: ${URL_PROTOCOL}://${DOMAIN_NAME}
      CONSOLE_API_URL: ${URL_PROTOCOL}://${DOMAIN_NAME}
      SERVICE_API_URL: ${URL_PROTOCOL}://${DOMAIN_NAME}
      APP_WEB_URL: ${URL_PROTOCOL}://${DOMAIN_NAME}
      FILES_URL: ""
      FILES_ACCESS_TIMEOUT: 300

      # Database
      DB_USERNAME: ${DIFY_DB_USER}
      DB_PASSWORD: ${DIFY_DB_PASSWORD}
      DB_HOST: ${POSTGRES_HOST}
      DB_PORT: ${POSTGRES_PORT}
      DB_DATABASE: ${DIFY_DB_NAME}

      # Redis
      REDIS_HOST: ${REDIS_HOST}
      REDIS_PORT: ${REDIS_PORT}
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      REDIS_DB: 0
      REDIS_USE_SSL: "false"

      # Celery (uses Redis)
      CELERY_BROKER_URL: "redis://:${REDIS_PASSWORD}@${REDIS_HOST}:${REDIS_PORT}/1"

      # Vector Store
      VECTOR_STORE: qdrant
      QDRANT_URL: http://${QDRANT_HOST}:${QDRANT_PORT}
      QDRANT_API_KEY: ${QDRANT_API_KEY}
      QDRANT_CLIENT_TIMEOUT: 20

      # Storage
      STORAGE_TYPE: local
      STORAGE_LOCAL_PATH: /app/api/storage

      # Sandbox
      CODE_EXECUTION_ENDPOINT: http://dify-sandbox:8194
      CODE_EXECUTION_API_KEY: ${DIFY_SANDBOX_KEY}
      CODE_MAX_NUMBER: 9223372036854775807
      CODE_MIN_NUMBER: -9223372036854775808
      CODE_MAX_DEPTH: 5
      CODE_MAX_PRECISION: 20
      CODE_MAX_STRING_LENGTH: 80000
      CODE_MAX_STRING_ARRAY_LENGTH: 30
      CODE_MAX_OBJECT_ARRAY_LENGTH: 30
      CODE_MAX_NUMBER_ARRAY_LENGTH: 1000

      # Mail (disabled by default)
      MAIL_TYPE: ""
      MAIL_DEFAULT_SEND_FROM: ""

      # Sentry (disabled)
      SENTRY_DSN: ""

    volumes:
      - ai-platform-dify-storage:/app/api/storage
    networks:
      - ai-platform
      - ai-backend
    ports:
      - "127.0.0.1:5001:5001"
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:5001/health || exit 1"]
      interval: 15s
      timeout: 10s
      retries: 5
      start_period: 60s
    extra_hosts:
      - "host.docker.internal:host-gateway"
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 512M

volumes:
  ai-platform-dify-storage:
    name: ai-platform-dify-storage

networks:
  ai-platform:
    external: true
  ai-backend:
    external: true
EOF

    log_info "docker-compose.dify-api.yml generated"
}

21.3 Docker Compose — Dify Worker
generate_compose_dify_worker() {
    log_info "Generating docker-compose.dify-worker.yml..."

    cat > "${DOCKER_PATH}/docker-compose.dify-worker.yml" << EOF
# AI Platform — Dify Worker (Celery)
# Generated by 2-deploy-platform.sh

services:
  dify-worker:
    image: ${DIFY_API_IMAGE}
    container_name: ai-platform-dify-worker
    restart: unless-stopped
    environment:
      MODE: worker
      LOG_LEVEL: INFO
      SECRET_KEY: ${DIFY_SECRET_KEY}

      # Database
      DB_USERNAME: ${DIFY_DB_USER}
      DB_PASSWORD: ${DIFY_DB_PASSWORD}
      DB_HOST: ${POSTGRES_HOST}
      DB_PORT: ${POSTGRES_PORT}
      DB_DATABASE: ${DIFY_DB_NAME}

      # Redis
      REDIS_HOST: ${REDIS_HOST}
      REDIS_PORT: ${REDIS_PORT}
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      REDIS_DB: 0
      REDIS_USE_SSL: "false"

      # Celery
      CELERY_BROKER_URL: "redis://:${REDIS_PASSWORD}@${REDIS_HOST}:${REDIS_PORT}/1"

      # Vector Store
      VECTOR_STORE: qdrant
      QDRANT_URL: http://${QDRANT_HOST}:${QDRANT_PORT}
      QDRANT_API_KEY: ${QDRANT_API_KEY}

      # Storage
      STORAGE_TYPE: local
      STORAGE_LOCAL_PATH: /app/api/storage

    volumes:
      - ai-platform-dify-storage:/app/api/storage
    networks:
      - ai-backend
    extra_hosts:
      - "host.docker.internal:host-gateway"
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 256M

volumes:
  ai-platform-dify-storage:
    name: ai-platform-dify-storage

networks:
  ai-backend:
    external: true
EOF

    log_info "docker-compose.dify-worker.yml generated"
}

21.4 Docker Compose — Dify Web
generate_compose_dify_web() {
    log_info "Generating docker-compose.dify-web.yml..."

    cat > "${DOCKER_PATH}/docker-compose.dify-web.yml" << EOF
# AI Platform — Dify Web Frontend
# Generated by 2-deploy-platform.sh

services:
  dify-web:
    image: ${DIFY_WEB_IMAGE}
    container_name: ai-platform-dify-web
    restart: unless-stopped
    environment:
      CONSOLE_API_URL: ${URL_PROTOCOL}://${DOMAIN_NAME}
      APP_API_URL: ${URL_PROTOCOL}://${DOMAIN_NAME}
      SENTRY_DSN: ""
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:3000 || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 15s
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 64M

networks:
  ai-platform:
    external: true
EOF

    log_info "docker-compose.dify-web.yml generated"
}

21.5 Docker Compose — Dify Sandbox
generate_compose_dify_sandbox() {
    log_info "Generating docker-compose.dify-sandbox.yml..."

    cat > "${DOCKER_PATH}/docker-compose.dify-sandbox.yml" << EOF
# AI Platform — Dify Sandbox (Code Execution)
# Generated by 2-deploy-platform.sh

services:
  dify-sandbox:
    image: ${DIFY_SANDBOX_IMAGE}
    container_name: ai-platform-dify-sandbox
    restart: unless-stopped
    environment:
      API_KEY: ${DIFY_SANDBOX_KEY}
      GIN_MODE: release
      WORKER_TIMEOUT: 15
      ENABLE_NETWORK: "true"
      SANDBOX_PORT: 8194
    networks:
      - ai-backend
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:8194/health || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 64M

networks:
  ai-backend:
    external: true
EOF

    log_info "docker-compose.dify-sandbox.yml generated"
}


Section 22: Phase 5 — Docker Compose Files (Application Tier)
22.1 Docker Compose — n8n
generate_compose_n8n() {
    log_info "Generating docker-compose.n8n.yml..."

    cat > "${DOCKER_PATH}/docker-compose.n8n.yml" << EOF
# AI Platform — n8n Workflow Automation
# Generated by 2-deploy-platform.sh

services:
  n8n:
    image: ${N8N_IMAGE}
    container_name: ai-platform-n8n
    restart: unless-stopped
    environment:
      N8N_HOST: 0.0.0.0
      N8N_PORT: 5678
      N8N_PROTOCOL: https
      WEBHOOK_URL: ${URL_PROTOCOL}://${DOMAIN_NAME}:5678/
      N8N_ENCRYPTION_KEY: ${N8N_ENCRYPTION_KEY}
      N8N_USER_MANAGEMENT_JWT_SECRET: ${N8N_WEBHOOK_SECRET}

      # Database
      DB_TYPE: postgresdb
      DB_POSTGRESDB_HOST: ${POSTGRES_HOST}
      DB_POSTGRESDB_PORT: ${POSTGRES_PORT}
      DB_POSTGRESDB_DATABASE: ${N8N_DB_NAME}
      DB_POSTGRESDB_USER: ${N8N_DB_USER}
      DB_POSTGRESDB_PASSWORD: ${N8N_DB_PASSWORD}

      # Execution
      EXECUTIONS_MODE: regular
      EXECUTIONS_DATA_SAVE_ON_SUCCESS: all
      EXECUTIONS_DATA_SAVE_ON_ERROR: all
      EXECUTIONS_DATA_PRUNE: "true"
      EXECUTIONS_DATA_MAX_AGE: 168

      # External hooks
      N8N_DIAGNOSTICS_ENABLED: "false"
      N8N_VERSION_NOTIFICATIONS_ENABLED: "false"
      GENERIC_TIMEZONE: UTC

    volumes:
      - ai-platform-n8n-data:/home/node/.n8n
    networks:
      - ai-platform
      - ai-backend
    ports:
      - "127.0.0.1:5678:5678"
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:5678/healthz || exit 1"]
      interval: 15s
      timeout: 10s
      retries: 5
      start_period: 30s
    extra_hosts:
      - "host.docker.internal:host-gateway"
    deploy:
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 256M

volumes:
  ai-platform-n8n-data:
    name: ai-platform-n8n-data

networks:
  ai-platform:
    external: true
  ai-backend:
    external: true
EOF

    log_info "docker-compose.n8n.yml generated"
}

22.2 Docker Compose — Open WebUI
generate_compose_open_webui() {
    log_info "Generating docker-compose.open-webui.yml..."

    cat > "${DOCKER_PATH}/docker-compose.open-webui.yml" << EOF
# AI Platform — Open WebUI
# Generated by 2-deploy-platform.sh

services:
  open-webui:
    image: ${OPEN_WEBUI_IMAGE}
    container_name: ai-platform-open-webui
    restart: unless-stopped
    environment:
      OLLAMA_BASE_URL: ${OLLAMA_BASE_URL}
      OPENAI_API_BASE_URL: http://litellm:4000/v1
      OPENAI_API_KEY: ${LITELLM_MASTER_KEY}
      WEBUI_SECRET_KEY: ${DIFY_STORAGE_KEY}
      WEBUI_AUTH: "true"
      ENABLE_SIGNUP: "false"
      DEFAULT_USER_ROLE: user
      ENABLE_COMMUNITY_SHARING: "false"
    volumes:
      - ai-platform-openwebui-data:/app/backend/data
    networks:
      - ai-platform
      - ai-backend
    ports:
      - "127.0.0.1:3001:8080"
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:8080/health || exit 1"]
      interval: 15s
      timeout: 10s
      retries: 5
      start_period: 30s
    extra_hosts:
      - "host.docker.internal:host-gateway"
    deploy:
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 256M

volumes:
  ai-platform-openwebui-data:
    name: ai-platform-openwebui-data

networks:
  ai-platform:
    external: true
  ai-backend:
    external: true
EOF

    log_info "docker-compose.open-webui.yml generated"
}

22.3 Docker Compose — Flowise (Conditional)
generate_compose_flowise() {
    if [[ " $ FLOWISE_ENABLED" != "true" ]]; then
        log_info "Flowise disabled — skipping compose generation"
        return 0
    fi

    log_info "Generating docker-compose.flowise.yml..."

    cat > " $ {DOCKER_PATH}/docker-compose.flowise.yml" << EOF
# AI Platform — Flowise
# Generated by 2-deploy-platform.sh

services:
  flowise:
    image: ${FLOWISE_IMAGE}
    container_name: ai-platform-flowise
    restart: unless-stopped
    environment:
      PORT: 3000
      FLOWISE_USERNAME: admin
      FLOWISE_PASSWORD: ${ADMIN_PASSWORD}
      FLOWISE_SECRETKEY_OVERWRITE: ${FLOWISE_SECRET_KEY}
      DATABASE_TYPE: postgres
      DATABASE_HOST: ${POSTGRES_HOST}
      DATABASE_PORT: ${POSTGRES_PORT}
      DATABASE_NAME: ${FLOWISE_DB_NAME}
      DATABASE_USER: ${FLOWISE_DB_USER}
      DATABASE_PASSWORD: ${FLOWISE_DB_PASSWORD}
      APIKEY_PATH: /root/.flowise
      LOG_LEVEL: info
    volumes:
      - ai-platform-flowise-data:/root/.flowise
    networks:
      - ai-platform
      - ai-backend
    ports:
      - "127.0.0.1:3002:3000"
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:3000 || exit 1"]
      interval: 15s
      timeout: 10s
      retries: 5
      start_period: 30s
    extra_hosts:
      - "host.docker.internal:host-gateway"
    deploy:
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 256M

volumes:
  ai-platform-flowise-data:
    name: ai-platform-flowise-data

networks:
  ai-platform:
    external: true
  ai-backend:
    external: true
EOF

    log_info "docker-compose.flowise.yml generated"
}

---

## Section 23: Phase 5 — Docker Compose Files (Front & Monitoring Tier)

### 23.1 Docker Compose — Caddy

```bash
generate_compose_caddy() {
    log_info "Generating docker-compose.caddy.yml..."

    # Build ports list based on mode
    local ports_block
    if [[ " $ DOMAIN_MODE" == "ip" ]]; then
        ports_block="    ports:
      - \"80:80\"
      - \"443:443\"
      - \"5678:5678\"
      - \"3001:3001\"
      - \"4000:4000\""

        if [[ " $ FLOWISE_ENABLED" == "true" ]]; then
            ports_block="${ports_block}
      - \"3002:3002\""
        fi
        if [[ " $ GRAFANA_ENABLED" == "true" ]]; then
            ports_block=" $ {ports_block}
      - \"3003:3003\""
        fi
    else
        ports_block="    ports:
      - \"80:80\"
      - \"443:443\""
    fi

    cat > "${DOCKER_PATH}/docker-compose.caddy.yml" << EOF
# AI Platform — Caddy Reverse Proxy
# Generated by 2-deploy-platform.sh

services:
  caddy:
    image: ${CADDY_IMAGE}
    container_name: ai-platform-caddy
    restart: unless-stopped
    volumes:
      - ${CONFIG_PATH}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro
      - ai-platform-caddy-data:/data
      - ai-platform-caddy-config:/config
      - ai-platform-caddy-logs:/data/logs
${ports_block}
    networks:
      - ai-platform
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:80 || curl -sfk https://localhost:443 || exit 1"]
      interval: 15s
      timeout: 10s
      retries: 5
      start_period: 15s
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 64M

volumes:
  ai-platform-caddy-data:
    name: ai-platform-caddy-data
  ai-platform-caddy-config:
    name: ai-platform-caddy-config
  ai-platform-caddy-logs:
    name: ai-platform-caddy-logs

networks:
  ai-platform:
    external: true
EOF

    log_info "docker-compose.caddy.yml generated"
}

23.2 Docker Compose — Prometheus
generate_compose_prometheus() {
    if [[ " $ PROMETHEUS_ENABLED" != "true" ]]; then
        log_info "Prometheus disabled — skipping compose generation"
        return 0
    fi

    log_info "Generating docker-compose.prometheus.yml..."

    cat > " $ {DOCKER_PATH}/docker-compose.prometheus.yml" << EOF
# AI Platform — Prometheus
# Generated by 2-deploy-platform.sh

services:
  prometheus:
    image: ${PROMETHEUS_IMAGE}
    container_name: ai-platform-prometheus
    restart: unless-stopped
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--web.enable-lifecycle'
    volumes:
      - ${CONFIG_PATH}/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ai-platform-prometheus-data:/prometheus
    networks:
      - ai-platform
      - ai-backend
    ports:
      - "127.0.0.1:9090:9090"
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost:9090/-/healthy || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 15s
    deploy:
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 256M

volumes:
  ai-platform-prometheus-data:
    name: ai-platform-prometheus-data

networks:
  ai-platform:
    external: true
  ai-backend:
    external: true
EOF

    log_info "docker-compose.prometheus.yml generated"
}

23.3 Docker Compose — Grafana
generate_compose_grafana() {
    if [[ " $ GRAFANA_ENABLED" != "true" ]]; then
        log_info "Grafana disabled — skipping compose generation"
        return 0
    fi

    log_info "Generating docker-compose.grafana.yml..."

    cat > " $ {DOCKER_PATH}/docker-compose.grafana.yml" << EOF
# AI Platform — Grafana
# Generated by 2-deploy-platform.sh

services:
  grafana:
    image: ${GRAFANA_IMAGE}
    container_name: ai-platform-grafana
    restart: unless-stopped
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD}
      GF_USERS_ALLOW_SIGN_UP: "false"
      GF_SERVER_ROOT_URL: ${URL_PROTOCOL}://${GRAFANA_URL}
      GF_SERVER_SERVE_FROM_SUB_PATH: "false"
      GF_LOG_LEVEL: info
      GF_INSTALL_PLUGINS: grafana-clock-panel,grafana-simple-json-datasource
    volumes:
      - ai-platform-grafana-data:/var/lib/grafana
      - ${CONFIG_PATH}/grafana/provisioning:/etc/grafana/provisioning:ro
      - ${CONFIG_PATH}/grafana/dashboards:/var/lib/grafana/dashboards:ro
    networks:
      - ai-platform
      - ai-backend
    ports:
      - "127.0.0.1:3003:3000"
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:3000/api/health || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 30s
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 128M

volumes:
  ai-platform-grafana-data:
    name: ai-platform-grafana-data

networks:
  ai-platform:
    external: true
  ai-backend:
    external: true
EOF

    log_info "docker-compose.grafana.yml generated"
}


Section 24: Phase 6 — Deployment Engine
24.1 Overview
Deployment is strictly ordered in tiers. Each tier must be healthy before the next starts.
Deployment Order:
  Tier 1: Infrastructure  →  postgres, redis, qdrant, supertokens
  Tier 2: AI Services     →  litellm, dify-sandbox, dify-api, dify-worker, dify-web
  Tier 3: Applications    →  n8n, open-webui, flowise (if enabled)
  Tier 4: Front           →  caddy
  Tier 5: Monitoring      →  prometheus (if enabled), grafana (if enabled)

24.2 Core Deployment Function
deploy_service() {
    local compose_file=" $ 1"
    local service_name=" $ 2"
    local max_wait="${3:-120}"  # Default 120s timeout

    if [[ ! -f "${DOCKER_PATH}/${compose_file}" ]]; then
        log_warn "Compose file not found: ${compose_file} — skipping"
        return 0
    fi

    log_info "Deploying ${service_name}..."
    docker compose -f "${DOCKER_PATH}/${compose_file}" up -d

    if [[ $? -ne 0 ]]; then
        log_error "Failed to start ${service_name}"
        return 1
    fi

    # Wait for health check
    wait_for_healthy "${service_name}" "${max_wait}"
}

wait_for_healthy() {
    local container_name="ai-platform-${1}"
    local max_wait="$2"
    local elapsed=0
    local interval=5

    log_info "Waiting for ${1} to be healthy (timeout: ${max_wait}s)..."

    while [[ $elapsed -lt  $ max_wait ]]; do
        local status
        status= $ (docker inspect --format='{{.State.Health.Status}}' "${container_name}" 2>/dev/null)

        case "$status" in
            healthy)
                log_info "✓ ${1} is healthy (${elapsed}s)"
                return 0
                ;;
            unhealthy)
                log_error "✗ ${1} is unhealthy after ${elapsed}s"
                docker logs --tail 20 "${container_name}" 2>&1 | while read -r line; do
                    log_error "  ${line}"
                done
                return 1
                ;;
            *)
                # starting or no health check
                sleep " $ interval"
                elapsed= $ ((elapsed + interval))
                ;;
        esac
    done

    log_error "✗ ${1} timed out after ${max_wait}s"
    log_error "  Current status: ${status:-unknown}"
    docker logs --tail 20 "${container_name}" 2>&1 | while read -r line; do
        log_error "  ${line}"
    done
    return 1
}

24.3 Tiered Deployment Execution
deploy_all_services() {
    log_section "DEPLOYMENT PHASE"
    local errors=0

    # ── Tier 1: Infrastructure ──
    log_section "Tier 1: Infrastructure Services"

    deploy_service "docker-compose.postgres.yml" "postgres" 120
    [[  $ ? -ne 0 ]] && errors= $ ((errors + 1))

    deploy_service "docker-compose.redis.yml" "redis" 60
    [[  $ ? -ne 0 ]] && errors= $ ((errors + 1))

    deploy_service "docker-compose.qdrant.yml" "qdrant" 60
    [[  $ ? -ne 0 ]] && errors= $ ((errors + 1))

    deploy_service "docker-compose.supertokens.yml" "supertokens" 90
    [[  $ ? -ne 0 ]] && errors= $ ((errors + 1))

    if [[ $errors -gt 0 ]]; then
        log_error "Infrastructure tier failed with ${errors} error(s)"
        log_error "Cannot proceed — fix infrastructure before continuing"
        exit 1
    fi
    log_info "✓ Infrastructure tier fully healthy"

    # ── Tier 2: AI Services ──
    log_section "Tier 2: AI Services"
    errors=0

    deploy_service "docker-compose.litellm.yml" "litellm" 120
    [[  $ ? -ne 0 ]] && errors= $ ((errors + 1))

    deploy_service "docker-compose.dify-sandbox.yml" "dify-sandbox" 60
    [[  $ ? -ne 0 ]] && errors= $ ((errors + 1))

    deploy_service "docker-compose.dify-api.yml" "dify-api" 180
    [[  $ ? -ne 0 ]] && errors= $ ((errors + 1))

    deploy_service "docker-compose.dify-worker.yml" "dify-worker" 60
    # Worker has no health check — just wait
    sleep 10
    log_info "✓ Dify worker started (no health check)"

    deploy_service "docker-compose.dify-web.yml" "dify-web" 60
    [[  $ ? -ne 0 ]] && errors= $ ((errors + 1))

    if [[ $errors -gt 0 ]]; then
        log_error "AI tier had ${errors} error(s) — proceeding with warnings"
    else
        log_info "✓ AI tier fully healthy"
    fi

    # ── Tier 3: Applications ──
    log_section "Tier 3: Application Services"
    errors=0

    deploy_service "docker-compose.n8n.yml" "n8n" 90
    [[  $ ? -ne 0 ]] && errors= $ ((errors + 1))

    deploy_service "docker-compose.open-webui.yml" "open-webui" 90
    [[  $ ? -ne 0 ]] && errors= $ ((errors + 1))

    if [[ "$FLOWISE_ENABLED" == "true" ]]; then
        deploy_service "docker-compose.flowise.yml" "flowise" 90
        [[  $ ? -ne 0 ]] && errors= $ ((errors + 1))
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Application tier had ${errors} error(s) — proceeding with warnings"
    else
        log_info "✓ Application tier fully healthy"
    fi

    # ── Tier 4: Front ──
    log_section "Tier 4: Reverse Proxy"

    deploy_service "docker-compose.caddy.yml" "caddy" 60
    [[  $ ? -ne 0 ]] && log_warn "Caddy may need a moment to obtain certificates"

    # ── Tier 5: Monitoring ──
    if [[ " $ PROMETHEUS_ENABLED" == "true" ]] || [[ " $ GRAFANA_ENABLED" == "true" ]]; then
        log_section "Tier 5: Monitoring Services"

        if [[ " $ PROMETHEUS_ENABLED" == "true" ]]; then
            deploy_service "docker-compose.prometheus.yml" "prometheus" 60
        fi

        if [[ "$GRAFANA_ENABLED" == "true" ]]; then
            deploy_service "docker-compose.grafana.yml" "grafana" 60
        fi

        log_info "✓ Monitoring tier deployed"
    fi
}

24.4 Post-Deployment Validation
post_deployment_validation() {
    log_section "POST-DEPLOYMENT VALIDATION"

    local total=0
    local healthy=0
    local unhealthy=0

    echo ""
    printf "%-25s %-15s %-10s\n" "SERVICE" "STATUS" "PORT"
    printf "%-25s %-15s %-10s\n" "-------" "------" "----"

    # Check each container
    for container in  $ (docker ps --format '{{.Names}}' | grep '^ai-platform-' | sort); do
        total= $ ((total + 1))
        local svc_name="${container#ai-platform-}"
        local status
        status= $ (docker inspect --format='{{.State.Health.Status}}' " $ container" 2>/dev/null || echo "running")
        local port
        port= $ (docker port " $ container" 2>/dev/null | head -1 | awk -F: '{print  $ NF}' || echo "-")

        if [[ " $ status" == "healthy" ]] || [[ " $ status" == "running" ]]; then
            healthy= $ ((healthy + 1))
            printf "%-25s %-15s %-10s\n" "$svc_name" "✓ ${status}" "${port:-'-'}"
        else
            unhealthy= $ ((unhealthy + 1))
            printf "%-25s %-15s %-10s\n" " $ svc_name" "✗ ${status}" "${port:-'-'}"
        fi
    done

    echo ""
    log_info "Total: ${total} | Healthy: ${healthy} | Unhealthy: ${unhealthy}"
    echo ""
}


Section 25: Phase 7 — Summary & Access Information
25.1 Final Output
print_deployment_summary() {
    log_section "DEPLOYMENT COMPLETE"

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║              AI PLATFORM — DEPLOYMENT SUMMARY              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    # Access URLs
    echo "┌─ Access URLs ────────────────────────────────────────────────┐"
    if [[ " $ DOMAIN_MODE" == "ip" ]]; then
        local base=" $ {URL_PROTOCOL}://${HOST_IP}"
        echo "│  Dify:           ${base}                                    │"
        echo "│  n8n:            ${base}:5678                               │"
        echo "│  Open WebUI:     ${base}:3001                               │"
        echo "│  LiteLLM:        ${base}:4000                               │"
        if [[ "$FLOWISE_ENABLED" == "true" ]]; then
            echo "│  Flowise:        ${base}:3002                               │"
        fi
        if [[ "$GRAFANA_ENABLED" == "true" ]]; then
            echo "│  Grafana:        ${base}:3003                               │"
        fi
    else
        echo "│  Dify:           ${URL_PROTOCOL}://${DOMAIN_NAME}           │"
        echo "│  n8n:            ${URL_PROTOCOL}://n8n.${DOMAIN_NAME}       │"
        echo "│  Open WebUI:     ${URL_PROTOCOL}://chat.${DOMAIN_NAME}      │"
        echo "│  LiteLLM:        ${URL_PROTOCOL}://llm.${DOMAIN_NAME}      │"
        if [[ "$FLOWISE_ENABLED" == "true" ]]; then
            echo "│  Flowise:        ${URL_PROTOCOL}://flow.${DOMAIN_NAME}      │"
        fi
        if [[ "$GRAFANA_ENABLED" == "true" ]]; then
            echo "│  Grafana:        ${URL_PROTOCOL}://grafana.${DOMAIN_NAME}   │"
        fi
    fi
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""

    # Credentials
    echo "┌─ Default Credentials ────────────────────────────────────────┐"
    echo "│                                                              │"
    echo "│  Dify Admin:     Set on first login                          │"
    echo "│  n8n:            Set on first login                          │"
    echo "│  Open WebUI:     Set on first login                          │"
    echo "│  Grafana:        admin / (see credentials.env)               │"
    echo "│  LiteLLM Admin:  (see credentials.env for master key)       │"
    echo "│                                                              │"
    echo "│  All credentials saved to:                                   │"
    echo "│    ${CONFIG_PATH}/credentials.env                            │"
    echo "│                                                              │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""

    # Quick commands
    echo "┌─ Useful Commands ────────────────────────────────────────────┐"
    echo "│                                                              │"
    echo "│  View all containers:                                        │"
    echo "│    docker ps --format 'table {{.Names}}\t{{.Status}}'        │"
    echo "│                                                              │"
    echo "│  View logs:                                                  │"
    echo "│    docker logs -f ai-platform-<service>                      │"
    echo "│                                                              │"
    echo "│  Restart a service:                                          │"
    echo "│    cd /opt/ai-platform/docker                                │"
    echo "│    docker compose -f docker-compose.<svc>.yml restart        │"
    echo "│                                                              │"
    echo "│  Next step — Configure platform:                             │"
    echo "│    sudo bash 3-configure-platform.sh                         │"
    echo "│                                                              │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""
}


Section 26: Script 2 — Main Execution Flow
26.1 Complete main() Function
main() {
    # Initialize logging
    LOG_FILE="${ROOT_PATH}/logs/script-2.log"
    exec > >(tee -a "$LOG_FILE") 2>&1

    echo ""
    log_section "AI PLATFORM — DEPLOYMENT SCRIPT (Script 2 of 4)"
    log_info "Started at: $(date)"
    echo ""

    # Phase 1: Pre-flight
    preflight_checks

    # Phase 2: Questionnaire
    interactive_questionnaire

    # Phase 3: Credentials
    generate_all_credentials

    # Phase 4: Config files
    generate_master_env
    generate_postgres_init
    generate_redis_config
    generate_litellm_config
    generate_dify_env            # Not shown — writes supplementary Dify config
    generate_caddyfile
    generate_prometheus_config
    generate_grafana_provisioning

    # Phase 5: Docker compose files
    create_docker_networks
    generate_compose_postgres
    generate_compose_redis
    generate_compose_qdrant
    generate_compose_supertokens
    generate_compose_litellm
    generate_compose_dify_api
    generate_compose_dify_worker
    generate_compose_dify_web
    generate_compose_dify_sandbox
    generate_compose_n8n
    generate_compose_open_webui
    generate_compose_flowise
    generate_compose_caddy
    generate_compose_prometheus
    generate_compose_grafana

    # Phase 6: Deploy
    deploy_all_services

    # Phase 7: Validate & summarize
    post_deployment_validation
    print_deployment_summary

    log_info "Script 2 completed at:  $ (date)"
}

# Entry point
main " $ @"


Section 27: Script 3 — Configure Platform
27.1 Purpose
3-configure-platform.sh performs post-deployment configuration that requires running services. It sets up:
LiteLLM model verification
n8n credential helpers
Dify initial API verification
Connectivity tests between services
Convenience alias scripts
27.2 Execution
sudo bash 3-configure-platform.sh

27.3 Phase Map
Script 3: Configure Platform
│
├── Phase 1: Pre-flight Checks
│   ├── Verify running as root
│   ├── Source master.env
│   ├── Source credentials.env
│   └── Verify all containers running
│
├── Phase 2: Service Connectivity Tests
│   ├── Test Ollama (host → Ollama)
│   ├── Test LiteLLM → Ollama
│   ├── Test LiteLLM → PostgreSQL
│   ├── Test LiteLLM → Redis
│   ├── Test Dify API → PostgreSQL
│   ├── Test Dify API → Redis
│   ├── Test Dify API → Qdrant
│   ├── Test n8n → PostgreSQL
│   ├── Test Open WebUI → LiteLLM
│   └── Test Open WebUI → Ollama
│
├── Phase 3: LiteLLM Model Verification
│   ├── Query LiteLLM /model/info
│   ├── Verify each Ollama model appears
│   ├── Verify cloud models (if configured)
│   └── Test a simple completion call
│
├── Phase 4: Generate Convenience Scripts
│   ├── platform-status.sh
│   ├── platform-restart.sh
│   ├── platform-stop.sh
│   ├── platform-start.sh
│   ├── platform-logs.sh
│   ├── platform-backup.sh
│   └── platform-update.sh
│
└── Phase 5: Final Report
    ├── Connectivity matrix
    ├── Model availability
    └── Platform readiness score

27.4 Connectivity Testing
test_connectivity() {
    log_section "SERVICE CONNECTIVITY TESTS"
    local pass=0
    local fail=0

    # Test: Ollama on host
    log_info "Testing Ollama..."
    if curl -sf http://localhost:11434/api/tags &>/dev/null; then
        log_info "  ✓ Ollama responding on localhost:11434"
        pass= $ ((pass + 1))
    else
        log_error "  ✗ Ollama not responding"
        fail= $ ((fail + 1))
    fi

    # Test: LiteLLM
    log_info "Testing LiteLLM..."
    if curl -sf http://localhost:4000/health/liveliness &>/dev/null; then
        log_info "  ✓ LiteLLM alive on localhost:4000"
        pass= $ ((pass + 1))
    else
        log_error "  ✗ LiteLLM not responding"
        fail= $ ((fail + 1))
    fi

    # Test: LiteLLM → Ollama (through LiteLLM)
    log_info "Testing LiteLLM → Ollama routing..."
    local test_response
    test_response=$(curl -sf -X POST http://localhost:4000/v1/chat/completions \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
        -d '{
            "model": "'"${PRIMARY_MODEL}"'",
            "messages": [{"role": "user", "content": "Say hello in exactly one word."}],
            "max_tokens": 10
        }' 2>/dev/null)

    if echo " $ test_response" | jq -e '.choices[0].message.content' &>/dev/null; then
        local reply
        reply= $ (echo "$test_response" | jq -r '.choices[0].message.content')
        log_info "  ✓ LiteLLM → Ollama working (response: ${reply})"
        pass= $ ((pass + 1))
    else
        log_error "  ✗ LiteLLM → Ollama routing failed"
        fail= $ ((fail + 1))
    fi

    # Test: Dify API
    log_info "Testing Dify API..."
    if curl -sf http://localhost:5001/health &>/dev/null; then
        log_info "  ✓ Dify API healthy"
        pass= $ ((pass + 1))
    else
        log_error "  ✗ Dify API not responding"
        fail= $ ((fail + 1))
    fi

    # Test: n8n
    log_info "Testing n8n..."
    if curl -sf http://localhost:5678/healthz &>/dev/null; then
        log_info "  ✓ n8n healthy"
        pass= $ ((pass + 1))
    else
        log_error "  ✗ n8n not responding"
        fail= $ ((fail + 1))
    fi

    # Test: Open WebUI
    log_info "Testing Open WebUI..."
    if curl -sf http://localhost:3001/health &>/dev/null 2>&1 || \
       curl -sf http://localhost:3001 &>/dev/null 2>&1; then
        log_info "  ✓ Open WebUI responding"
        pass= $ ((pass + 1))
    else
        log_error "  ✗ Open WebUI not responding"
        fail= $ ((fail + 1))
    fi

    # Test: PostgreSQL
    log_info "Testing PostgreSQL..."
    if docker exec ai-platform-postgres pg_isready -U "${POSTGRES_USER}" &>/dev/null; then
        log_info "  ✓ PostgreSQL ready"
        pass= $ ((pass + 1))
    else
        log_error "  ✗ PostgreSQL not ready"
        fail= $ ((fail + 1))
    fi

    # Test: Redis
    log_info "Testing Redis..."
    if docker exec ai-platform-redis redis-cli -a "${REDIS_PASSWORD}" ping 2>/dev/null | grep -q PONG; then
        log_info "  ✓ Redis responding (PONG)"
        pass= $ ((pass + 1))
    else
        log_error "  ✗ Redis not responding"
        fail= $ ((fail + 1))
    fi

    # Test: Qdrant
    log_info "Testing Qdrant..."
    if curl -sf http://localhost:6333/healthz &>/dev/null; then
        log_info "  ✓ Qdrant healthy"
        pass= $ ((pass + 1))
    else
        log_error "  ✗ Qdrant not responding"
        fail= $ ((fail + 1))
    fi

    echo ""
    log_info "Connectivity: ${pass} passed, ${fail} failed out of $((pass + fail)) tests"

    if [[ $fail -gt 0 ]]; then
        log_warn "Some services are not responding — check logs with:"
        log_warn "  docker logs ai-platform-<service-name>"
    fi

    return $fail
}

27.5 Convenience Script Generation
generate_convenience_scripts() {
    log_section "GENERATING CONVENIENCE SCRIPTS"

    local scripts_dir="${ROOT_PATH}/scripts"
    mkdir -p " $ scripts_dir"

    # ── platform-status.sh ──
    cat > " $ {scripts_dir}/platform-status.sh" << 'EOF'
#!/bin/bash
# AI Platform — Status Check
echo ""
echo "=== AI Platform Status ==="
echo ""
printf "%-30s %-15s %-10s\n" "CONTAINER" "STATUS" "UPTIME"
printf "%-30s %-15s %-10s\n" "---------" "------" "------"
docker ps --filter "name=ai-platform-" --format "table {{.Names}}\t{{.Status}}" | tail -n +2 | sort | while read -r line; do
    printf "%-30s\n" "$line"
done
echo ""
echo "=== Ollama ==="
if systemctl is-active --quiet ollama; then
    echo "  Status: Running"
    echo "  Models:  $ (curl -sf http://localhost:11434/api/tags | jq -r '.models[].name' 2>/dev/null | tr '\n' ', ' | sed 's/, $ //')"
else
    echo "  Status: Stopped"
fi
echo ""
EOF
    chmod +x "${scripts_dir}/platform-status.sh"

    # ── platform-restart.sh ──
    cat > "${scripts_dir}/platform-restart.sh" << 'SCRIPTEOF'
#!/bin/bash
# AI Platform — Restart all services
DOCKER_PATH="/opt/ai-platform/docker"

echo "Restarting AI Platform..."

if [[ -n "$1" ]]; then
    # Restart specific service
    echo "Restarting  $ 1..."
    docker compose -f " $ {DOCKER_PATH}/docker-compose.${1}.yml" restart
else
    # Restart all in order
    for f in $(ls ${DOCKER_PATH}/docker-compose.*.yml 2>/dev/null | sort); do
        svc= $ (basename " $ f" | sed 's/docker-compose\.$ .* $ \.yml/\1/')
        echo "Restarting ${svc}..."
        docker compose -f " $ f" restart
    done
fi

echo "Done."
SCRIPTEOF
    chmod +x " $ {scripts_dir}/platform-restart.sh"

    # ── platform-stop.sh ──
    cat > "${scripts_dir}/platform-stop.sh" << 'SCRIPTEOF'
#!/bin/bash
# AI Platform — Stop all services
DOCKER_PATH="/opt/ai-platform/docker"

echo "Stopping AI Platform..."

# Stop in reverse order (front first)
for f in $(ls ${DOCKER_PATH}/docker-compose.*.yml 2>/dev/null | sort -r); do
    svc= $ (basename " $ f" | sed 's/docker-compose\.$ .* $ \.yml/\1/')
    echo "Stopping ${svc}..."
    docker compose -f " $ f" down
done

echo "All services stopped."
echo "Note: Ollama is still running (systemd service)"
SCRIPTEOF
    chmod +x " $ {scripts_dir}/platform-stop.sh"

    # ── platform-start.sh ──
    cat > "${scripts_dir}/platform-start.sh" << 'SCRIPTEOF'
#!/bin/bash
# AI Platform — Start all services
DOCKER_PATH="/opt/ai-platform/docker"

echo "Starting AI Platform..."

# Start infrastructure first
for svc in postgres redis qdrant supertokens; do
    [[ -f "${DOCKER_PATH}/docker-compose.${svc}.yml" ]] && \
        docker compose -f "${DOCKER_PATH}/docker-compose.${svc}.yml" up -d
done
echo "Waiting for infrastructure..."
sleep 15

# AI services
for svc in litellm dify-sandbox dify-api dify-worker dify-web; do
    [[ -f "${DOCKER_PATH}/docker-compose.${svc}.yml" ]] && \
        docker compose -f "${DOCKER_PATH}/docker-compose.${svc}.yml" up -d
done
echo "Waiting for AI services..."
sleep 20

# Applications
for svc in n8n open-webui flowise; do
    [[ -f "${DOCKER_PATH}/docker-compose.${svc}.yml" ]] && \
        docker compose -f "${DOCKER_PATH}/docker-compose.${svc}.yml" up -d
done

# Front & monitoring
for svc in caddy prometheus grafana; do
    [[ -f "${DOCKER_PATH}/docker-compose.${svc}.yml" ]] && \
        docker compose -f "${DOCKER_PATH}/docker-compose.${svc}.yml" up -d
done

echo "All services started."
SCRIPTEOF
    chmod +x "${scripts_dir}/platform-start.sh"

    # ── platform-logs.sh ──
    cat > "${scripts_dir}/platform-logs.sh" << 'SCRIPTEOF'
#!/bin/bash
# AI Platform — View logs
if [[ -z " $ 1" ]]; then
    echo "Usage: platform-logs.sh <service-name> [lines]"
    echo ""
    echo "Available services:"
    docker ps --filter "name=ai-platform-" --format "  {{.Names}}" | sed 's/ai-platform-//' | sort
    exit 1
fi
LINES=" $ {2:-100}"
docker logs --tail " $ LINES" -f "ai-platform- $ {1}"
SCRIPTEOF
    chmod +x "${scripts_dir}/platform-logs.sh"

    # ── platform-backup.sh ──
    cat > "${scripts_dir}/platform-backup.sh" << 'SCRIPTEOF'
#!/bin/bash
# AI Platform — Backup
BACKUP_DIR="/opt/ai-platform/backups/ $ (date +%Y%m%d-%H%M%S)"
mkdir -p " $ BACKUP_DIR"

echo "Backing up AI Platform to ${BACKUP_DIR}..."

# Backup configs
cp -r /opt/ai-platform/config " $ BACKUP_DIR/config"

# Backup PostgreSQL
echo "Backing up PostgreSQL..."
docker exec ai-platform-postgres pg_dumpall -U postgres > " $ BACKUP_DIR/postgres-full.sql"

# Backup docker compose files
cp -r /opt/ai-platform/docker " $ BACKUP_DIR/docker"

# Compress
tar -czf " $ {BACKUP_DIR}.tar.gz" -C "$(dirname  $ BACKUP_DIR)" " $ (basename  $ BACKUP_DIR)"
rm -rf " $ BACKUP_DIR"

echo "Backup complete: ${BACKUP_DIR}.tar.gz"
echo "Size:  $ (du -h " $ {BACKUP_DIR}.tar.gz" | cut -f1)"
SCRIPTEOF
    chmod +x "${scripts_dir}/platform-backup.sh"

    log_info "Generated convenience scripts in ${scripts_dir}/"
    log_info "  platform-status.sh   — Check all services"
    log_info "  platform-restart.sh  — Restart all or one service"
    log_info "  platform-stop.sh     — Stop all services"
    log_info "  platform-start.sh    — Start all services (ordered)"
    log_info "  platform-logs.sh     — View service logs"
    log_info "  platform-backup.sh   — Backup configs and databases"
}

27.6 Script 3 — Main Flow
main() {
    LOG_FILE="${ROOT_PATH}/logs/script-3.log"
    exec > >(tee -a "$LOG_FILE") 2>&1

    log_section "AI PLATFORM — CONFIGURATION SCRIPT (Script 3 of 4)"
    log_info "Started at:  $ (date)"

    # Source configs
    source " $ {CONFIG_PATH}/master.env"
    source "${CONFIG_PATH}/credentials.env"

    # Phase 2: Connectivity
    test_connectivity
    local test_result=$?

    # Phase 4: Convenience scripts
    generate_convenience_scripts

    # Phase 5: Final report
    log_section "CONFIGURATION COMPLETE"
    echo ""

    if [[ $test_result -eq 0 ]]; then
        log_info "✓ All connectivity tests passed"
        log_info "✓ Platform is fully operational"
    else
        log_warn "Some connectivity tests failed"
        log_warn "Platform is partially operational — check failing services"
    fi

    echo ""
    log_info "Platform management scripts installed to:"
    log_info "  /opt/ai-platform/scripts/"
    echo ""
    log_info "Next step (optional): Add extra models or services:"
    log_info "  sudo bash 4-add-services.sh"
    echo ""

    log_info "Script 3 completed at:  $ (date)"
}

main " $ @"


Section 28: Script 4 — Add Services
28.1 Purpose
4-add-services.sh is a menu-driven utility for post-deployment additions:
Pull additional Ollama models
Add cloud provider API keys to LiteLLM
Enable/deploy optional services that were skipped during install
Add custom LiteLLM model entries
28.2 Execution
sudo bash 4-add-services.sh

28.3 Menu Structure
show_menu() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║            AI PLATFORM — ADD SERVICES MENU              ║"
    echo "╠══════════════════════════════════════════════════════════╣"
    echo "║                                                          ║"
    echo "║  1) Pull additional Ollama model                         ║"
    echo "║  2) Add cloud provider API key                           ║"
    echo "║  3) Add custom model to LiteLLM                          ║"
    echo "║  4) Enable Flowise (if not installed)                    ║"
    echo "║  5) Enable Prometheus + Grafana (if not installed)       ║"
    echo "║  6) Show current model list                              ║"
    echo "║  7) Show platform status                                 ║"
    echo "║  0) Exit                                                 ║"
    echo "║                                                          ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    read -rp "Select option: " choice
}

28.4 Add Ollama Model
add_ollama_model() {
    echo ""
    echo "Popular models:"
    echo "  llama3.1:8b      — General purpose (4.7GB)"
    echo "  llama3.1:70b     — Large general purpose (40GB)"
    echo "  codellama:13b    — Code generation (7.4GB)"
    echo "  mistral:7b       — Fast general purpose (4.1GB)"
    echo "  mixtral:8x7b     — MoE model (26GB)"
    echo "  deepseek-coder-v2:16b — Coding (8.9GB)"
    echo "  nomic-embed-text — Embeddings (274MB)"
    echo "  mxbai-embed-large — Embeddings (670MB)"
    echo ""
    read -rp "Enter model name (e.g., mistral:7b): " model_name

    if [[ -z "$model_name" ]]; then
        log_warn "No model name provided"
        return
    fi

    log_info "Pulling ${model_name}..."
    ollama pull "$model_name"

    if [[ $? -eq 0 ]]; then
        log_info "✓ Model ${model_name} pulled successfully"

        # Add to LiteLLM config
        read -rp "Add to LiteLLM proxy? (y/n): " add_to_litellm
        if [[ " $ add_to_litellm" =~ ^[Yy] ]]; then
            add_model_to_litellm " $ model_name" "ollama/${model_name}" "${OLLAMA_BASE_URL}"
        fi
    else
        log_error "Failed to pull ${model_name}"
    fi
}

28.5 Add Model to LiteLLM (Runtime)
add_model_to_litellm() {
    local model_alias=" $ 1"
    local litellm_model=" $ 2"
    local api_base=" $ 3"
    local api_key=" $ {4:-}"

    log_info "Adding ${model_alias} to LiteLLM..."

    local payload
    if [[ -n " $ api_key" ]]; then
        payload= $ (cat << EOF
{
    "model_name": "${model_alias}",
    "litellm_params": {
        "model": "${litellm_model}",
        "api_key": "${api_key}"
    }
}
EOF
)
    else
        payload= $ (cat << EOF
{
    "model_name": " $ {model_alias}",
    "litellm_params": {
        "model": "${litellm_model}",
        "api_base": "${api_base}"
    }
}
EOF
)
    fi

    local response
    response=$(curl -sf -X POST http://localhost:4000/model/new \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
        -d " $ payload" 2>&1)

    if echo " $ response" | jq -e '.model_id' &>/dev/null 2>&1; then
        log_info "✓ Model ${model_alias} added to LiteLLM"

        # Also append to config file for persistence
        cat >> "${CONFIG_PATH}/litellm/config.yaml" << EOF

  - model_name: ${model_alias}
    litellm_params:
      model: ${litellm_model}
 $ (if [[ -n " $ api_base" ]]; then echo "      api_base: ${api_base}"; fi)
 $ (if [[ -n " $ api_key" ]]; then echo "      api_key: ${api_key}"; fi)
EOF
        log_info "  Also written to config file for persistence"
    else
        log_error "Failed to add model: ${response}"
    fi
}

28.6 Add Cloud Provider
add_cloud_provider() {
    echo ""
    echo "Available providers:"
    echo "  1) OpenAI"
    echo "  2) Anthropic"
    echo "  3) Google AI (Gemini)"
    echo "  4) Mistral AI"
    echo "  5) Groq"
    echo "  6) Together AI"
    echo ""
    read -rp "Select provider: " provider_choice

    case " $ provider_choice" in
        1)
            read -rsp "Enter OpenAI API key: " api_key; echo ""
            add_model_to_litellm "gpt-4o" "openai/gpt-4o" "" " $ api_key"
            add_model_to_litellm "gpt-4o-mini" "openai/gpt-4o-mini" "" " $ api_key"
            add_model_to_litellm "text-embedding-3-small" "openai/text-embedding-3-small" "" " $ api_key"
            ;;
        2)
            read -rsp "Enter Anthropic API key: " api_key; echo ""
            add_model_to_litellm "claude-sonnet-4-20250514" "anthropic/claude-sonnet-4-20250514" "" " $ api_key"
            add_model_to_litellm "claude-3-5-haiku" "anthropic/claude-3-5-haiku-20241022" "" " $ api_key"
            ;;
        3)
            read -rsp "Enter Google AI API key: " api_key; echo ""
            add_model_to_litellm "gemini-2.0-flash" "gemini/gemini-2.0-flash" "" " $ api_key"
            add_model_to_litellm "gemini-2.5-pro" "gemini/gemini-2.5-pro-preview-06-05" "" " $ api_key"
            ;;
        4)
            read -rsp "Enter Mistral API key: " api_key; echo ""
            add_model_to_litellm "mistral-large" "mistral/mistral-large-latest" "" " $ api_key"
            add_model_to_litellm "mistral-small" "mistral/mistral-small-latest" "" " $ api_key"
            ;;
        5)
            read -rsp "Enter Groq API key: " api_key; echo ""
            add_model_to_litellm "groq-llama-3.1-70b" "groq/llama-3.1-70b-versatile" "" " $ api_key"
            add_model_to_litellm "groq-llama-3.1-8b" "groq/llama-3.1-8b-instant" "" " $ api_key"
            add_model_to_litellm "groq-mixtral-8x7b" "groq/mixtral-8x7b-32768" "" " $ api_key"
            ;;
        6)
            read -rsp "Enter Together AI API key: " api_key; echo ""
            add_model_to_litellm "together-llama-3.1-70b" "together_ai/meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo" "" " $ api_key"
            ;;
        *)
            log_warn "Invalid selection"
            ;;
    esac
}

28.7 Show Model List
show_models() {
    log_section "CURRENT MODELS"

    echo ""
    echo "── Ollama Models (Local) ──"
    curl -sf http://localhost:11434/api/tags | jq -r '.models[] | "  \(.name)\t\(.size / 1024 / 1024 / 1024 | . * 100 | floor / 100)GB"' 2>/dev/null || echo "  (Ollama not responding)"

    echo ""
    echo "── LiteLLM Models (Proxy) ──"
    curl -sf http://localhost:4000/model/info \
        -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" | \
        jq -r '.data[] | "  \(.model_name)\t→ \(.litellm_params.model)"' 2>/dev/null || echo "  (LiteLLM not responding)"

    echo ""
}

28.8 Script 4 — Main Loop
main() {
    LOG_FILE="${ROOT_PATH}/logs/script-4.log"
    exec > >(tee -a " $ LOG_FILE") 2>&1

    # Source configs
    source " $ {CONFIG_PATH}/master.env"
    source "${CONFIG_PATH}/credentials.env"

    log_section "AI PLATFORM — ADD SERVICES (Script 4 of 4)"

    while true; do
        show_menu
        case " $ choice" in
            1) add_ollama_model ;;
            2) add_cloud_provider ;;
            3)
                read -rp "Model alias (e.g., my-model): " alias
                read -rp "LiteLLM model string (e.g., ollama/modelname): " model_str
                read -rp "API base URL (blank for cloud): " base_url
                read -rsp "API key (blank for local): " key; echo ""
                add_model_to_litellm " $ alias" " $ model_str" " $ base_url" " $ key"
                ;;
            4)
                source " $ {CONFIG_PATH}/master.env"
                FLOWISE_ENABLED="true"
                generate_compose_flowise
                deploy_service "docker-compose.flowise.yml" "flowise" 90
                ;;
            5)
                source "${CONFIG_PATH}/master.env"
                PROMETHEUS_ENABLED="true"
                GRAFANA_ENABLED="true"
                generate_compose_prometheus
                generate_compose_grafana
                deploy_service "docker-compose.prometheus.yml" "prometheus" 60
                deploy_service "docker-compose.grafana.yml" "grafana" 60
                ;;
            6) show_models ;;
            7) bash "${ROOT_PATH}/scripts/platform-status.sh" ;;
            0) echo "Exiting."; exit 0 ;;
            *) echo "Invalid option." ;;
        esac
    done
}

main "$@"

---

## Section 29: Troubleshooting Guide

### 29.1 Diagnostic Flowchart

```text
Problem Detected
│
├─ Container won't start?
│  ├─ docker logs ai-platform-<service>
│  ├─ Check: docker compose -f docker-compose.<svc>.yml config
│  ├─ Check: .env file variables populated?
│  └─ Check: dependent service healthy?
│
├─ Service unhealthy?
│  ├─ docker inspect ai-platform-<service> | jq '.[0].State.Health'
│  ├─ Check port binding: ss -tlnp | grep <port>
│  └─ Check memory: docker stats ai-platform-<service> --no-stream
│
├─ Can't access Web UI?
│  ├─ Is Caddy running? docker logs ai-platform-caddy
│  ├─ DNS / IP correct?
│  ├─ Firewall: ufw status (ports 80, 443, 5678, 3001, 4000)
│  └─ Try direct: curl -k https://localhost:443
│
├─ Ollama models not in LiteLLM?
│  ├─ curl http://localhost:11434/api/tags
│  ├─ curl http://localhost:4000/model/info -H "Authorization: Bearer $KEY"
│  ├─ Check LiteLLM config.yaml model entries
│  └─ Restart: docker compose -f docker-compose.litellm.yml restart
│
├─ Dify can't reach LiteLLM?
│  ├─ From Dify container: curl http://litellm:4000/health/liveliness
│  ├─ Check network: docker network inspect ai-platform
│  └─ Verify Dify .env has correct LiteLLM URL
│
├─ n8n workflow errors?
│  ├─ docker logs ai-platform-n8n --tail 50
│  ├─ Check n8n credentials in UI
│  └─ Verify: curl http://localhost:5678/healthz
│
├─ Database connection refused?
│  ├─ docker logs ai-platform-postgres
│  ├─ Check: docker exec ai-platform-postgres pg_isready -U postgres
│  ├─ Verify init SQL ran: docker exec ai-platform-postgres psql -U postgres -l
│  └─ Check credentials match between service .env and postgres init
│
└─ Out of memory?
   ├─ docker stats --no-stream
   ├─ Check: free -h
   ├─ Reduce Ollama model size
   └─ Disable optional services (Flowise, Grafana)

29.2 Common Issues & Solutions
Copy table
Issue
Cause
Solution
port already in use
Another service on that port
ss -tlnp | grep <port> then stop conflicting service
OCI runtime error
Docker storage full
docker system prune -a --volumes (⚠️ removes unused data)
Ollama connection refused from container
Wrong host address
Verify extra_hosts: host.docker.internal:host-gateway in compose
LiteLLM model not found
Model name mismatch
Check config.yaml model names match Ollama ollama list output
Dify 500 Internal Server Error
DB migration incomplete
docker restart ai-platform-dify-api — wait 60s for migrations
Caddy TLS handshake error
Self-signed cert warning
Expected with tls internal — accept in browser or use curl -k
Qdrant disk space
Vector DB growing
Check /opt/ai-platform/data/qdrant/ size — add storage or prune collections
SuperTokens connection refused
PostgreSQL not ready
Restart SuperTokens after PostgreSQL is confirmed healthy
Redis NOAUTH
Password mismatch
Compare REDIS_PASSWORD in credentials.env vs redis.conf requirepass
n8n CSRF error
Webhook URL mismatch
Verify N8N_EDITOR_BASE_URL and WEBHOOK_URL in compose match actual URL

29.3 Log Locations
/opt/ai-platform/
├── logs/
│   ├── script-1.log          # System prep log
│   ├── script-2.log          # Deployment log
│   ├── script-3.log          # Configuration log
│   └── script-4.log          # Add services log
│
Docker container logs:
  docker logs ai-platform-<service>
  docker logs --since 1h ai-platform-<service>
  docker logs --tail 100 -f ai-platform-<service>

Caddy logs (inside volume):
  docker exec ai-platform-caddy cat /data/logs/caddy.log

29.4 Emergency Recovery
# Full platform restart (ordered)
sudo bash /opt/ai-platform/scripts/platform-stop.sh
sleep 10
sudo bash /opt/ai-platform/scripts/platform-start.sh

# Nuclear option — rebuild single service
cd /opt/ai-platform/docker
docker compose -f docker-compose.<service>.yml down -v  # ⚠️ destroys volume
docker compose -f docker-compose.<service>.yml up -d

# Restore from backup
tar -xzf /opt/ai-platform/backups/<timestamp>.tar.gz -C /tmp/restore
# Restore PostgreSQL
cat /tmp/restore/*/postgres-full.sql | docker exec -i ai-platform-postgres psql -U postgres
# Restore configs
cp -r /tmp/restore/*/config/* /opt/ai-platform/config/
# Restart all
sudo bash /opt/ai-platform/scripts/platform-restart.sh


Section 30: Architecture & Network Diagrams
30.1 Full Architecture Diagram
                         ┌──────────────────────────────────┐
                          │          INTERNET / USER          │
                          └──────────┬───────────────────────┘
                                     │
                              Ports 80/443
                            (+ 5678, 3001, 4000
                             3002, 3003 in IP mode)
                                     │
                          ┌──────────▼───────────────────────┐
                          │         CADDY (Reverse Proxy)     │
                          │    TLS termination / routing       │
                          └──────────┬───────────────────────┘
                                     │
              ┌──────────────────────┼──────────────────────────┐
              │                      │                          │
    ┌─────────▼──────────┐ ┌────────▼─────────┐ ┌──────────────▼────────┐
    │    DIFY (Web UI)   │ │      n8n         │ │    Open WebUI         │
    │    Port 3000       │ │   Port 5678      │ │    Port 8080          │
    └─────────┬──────────┘ └────────┬─────────┘ └──────────────┬────────┘
              │                     │                           │
              │                     │                           │
    ┌─────────▼──────────┐         │                           │
    │  DIFY API + Worker │         │                           │
    │    Port 5001       │         │                           │
    └─────────┬──────────┘         │                           │
              │                     │                           │
              ├─────────────────────┼───────────────────────────┘
              │                     │
    ┌─────────▼─────────────────────▼───────────────────────────┐
    │                    LiteLLM Proxy                           │
    │                   Port 4000                                │
    │           (Unified AI Gateway)                             │
    └──────┬───────────────────┬────────────────────┬───────────┘
           │                   │                    │
    ┌──────▼──────┐    ┌──────▼──────┐    ┌────────▼────────┐
    │   Ollama    │    │  OpenAI     │    │   Anthropic     │
    │ (Host GPU)  │    │  (Cloud)    │    │   (Cloud)       │
    │ Port 11434  │    │             │    │                 │
    └─────────────┘    └─────────────┘    └─────────────────┘

    ┌───────────────────────────────────────────────────────────┐
    │                  Infrastructure Layer                      │
    │                                                           │
    │  ┌──────────┐  ┌───────┐  ┌────────┐  ┌──────────────┐  │
    │  │PostgreSQL│  │ Redis │  │ Qdrant │  │ SuperTokens  │  │
    │  │  :5432   │  │ :6379 │  │ :6333  │  │   :3567      │  │
    │  └──────────┘  └───────┘  └────────┘  └──────────────┘  │
    └───────────────────────────────────────────────────────────┘

30.2 Docker Network Topology
   Network: ai-platform (bridge)
    ┌─────────────────────────────────────────────────────┐
    │                                                     │
    │  caddy ◄──► dify-web ◄──► dify-api                 │
    │    │                        │                       │
    │    ├──► n8n                 ├──► dify-worker         │
    │    │                        │                       │
    │    ├──► open-webui          ├──► dify-sandbox        │
    │    │                        │                       │
    │    ├──► litellm             ├──► litellm             │
    │    │                                                │
    │    ├──► flowise (optional)                          │
    │    └──► grafana (optional)                          │
    │                                                     │
    └─────────────────────────────────────────────────────┘

    Network: ai-backend (bridge)
    ┌─────────────────────────────────────────────────────┐
    │                                                     │
    │  postgres ◄──► dify-api                             │
    │     │     ◄──► dify-worker                          │
    │     │     ◄──► n8n                                  │
    │     │     ◄──► litellm                              │
    │     │     ◄──► supertokens                          │
    │     │     ◄──► flowise (optional)                   │
    │                                                     │
    │  redis ◄──► dify-api                                │
    │    │   ◄──► dify-worker                             │
    │    │   ◄──► litellm                                 │
    │                                                     │
    │  qdrant ◄──► dify-api                               │
    │         ◄──► dify-worker                            │
    │                                                     │
    │  prometheus ◄──► litellm (metrics scrape)           │
    │       │     ◄──► grafana (data source)              │
    │                                                     │
    └─────────────────────────────────────────────────────┘

    Host Network (not Docker):
    ┌─────────────────────────────────────────────────────┐
    │  Ollama (systemd)  —  Port 11434                    │
    │  Accessed via host.docker.internal from containers  │
    └─────────────────────────────────────────────────────┘

30.3 Data Flow: User Chat Request
User types message in Open WebUI
         │
         ▼
    Open WebUI (container)
    Sends to LiteLLM endpoint
         │
         ▼
    LiteLLM Proxy (container)
    Routes based on model name:
    ├── Local model? → Ollama (host:11434)
    │                   │
    │                   ▼
    │              GPU inference
    │                   │
    │                   ▼
    │              Response streamed back
    │
    └── Cloud model? → OpenAI / Anthropic / Google API
                        │
                        ▼
                   Response streamed back
         │
         ▼
    LiteLLM logs usage to PostgreSQL
    LiteLLM updates cache in Redis
    LiteLLM emits metrics to Prometheus
         │
         ▼
    Response returned to Open WebUI
         │
         ▼
    Displayed to user (streaming)

30.4 Data Flow: Dify RAG Pipeline
User sends query to Dify chatbot
         │
         ▼
    Dify Web → Dify API
         │
         ├── 1. Generate embedding
         │      │
         │      ▼
         │   LiteLLM → Ollama (nomic-embed-text)
         │      │
         │      ▼
         │   Embedding vector returned
         │
         ├── 2. Vector search
         │      │
         │      ▼
         │   Qdrant (similarity search)
         │      │
         │      ▼
         │   Relevant document chunks returned
         │
         ├── 3. Build prompt with context
         │      │
         │      ▼
         │   System prompt + retrieved chunks + user query
         │
         └── 4. LLM completion
                │
                ▼
           LiteLLM → Ollama (llama3.1 or chosen model)
                │
                ▼
           Streaming response → User


Section 31: Complete Port Reference
31.1 External Ports (Exposed to Host)
Copy table
Port
Service
Protocol
Mode
80
Caddy (HTTP redirect)
TCP
Always
443
Caddy → Dify Web
TCP
Always
5678
Caddy → n8n
TCP
IP mode
3001
Caddy → Open WebUI
TCP
IP mode
4000
Caddy → LiteLLM
TCP
IP mode
3002
Caddy → Flowise
TCP
IP mode (optional)
3003
Caddy → Grafana
TCP
IP mode (optional)
11434
Ollama (host)
TCP
Always (localhost)

31.2 Internal Ports (Container-to-Container)
Copy table
Port
Service
Network
5432
PostgreSQL
ai-backend
6379
Redis
ai-backend
6333
Qdrant HTTP
ai-backend
6334
Qdrant gRPC
ai-backend
3567
SuperTokens
ai-backend
4000
LiteLLM
ai-platform
5001
Dify API
ai-platform
5002
Dify Worker (internal)
ai-backend
3000
Dify Web
ai-platform
8194
Dify Sandbox
ai-backend
5678
n8n
ai-platform
8080
Open WebUI
ai-platform
3000
Flowise
ai-platform
9090
Prometheus
ai-backend
3000
Grafana
ai-platform

31.3 Localhost-Bound Ports (127.0.0.1 only)
These ports are bound for health checks and direct admin access, NOT exposed externally:
Copy table
Port
Service
127.0.0.1:5432
PostgreSQL
127.0.0.1:6379
Redis
127.0.0.1:6333
Qdrant
127.0.0.1:5001
Dify API
127.0.0.1:9090
Prometheus
127.0.0.1:3003
Grafana (direct)


Section 32: Complete Environment Variable Reference
32.1 Infrastructure Variables
Copy table
Variable
Example
Used By
POSTGRES_HOST
postgres
All services
POSTGRES_PORT
5432
All services
POSTGRES_USER
postgres
PostgreSQL
POSTGRES_PASSWORD
(generated)
PostgreSQL, all services
REDIS_HOST
redis
Dify, LiteLLM
REDIS_PORT
6379
Dify, LiteLLM
REDIS_PASSWORD
(generated)
Redis, Dify, LiteLLM
QDRANT_HOST
qdrant
Dify
QDRANT_PORT
6333
Dify
QDRANT_API_KEY
(generated)
Qdrant, Dify

32.2 Service-Specific Database Variables
Copy table
Variable
Example
DIFY_DB_NAME
dify
DIFY_DB_USER
dify_user
DIFY_DB_PASSWORD
(generated)
N8N_DB_NAME
n8n
N8N_DB_USER
n8n_user
N8N_DB_PASSWORD
(generated)
LITELLM_DB_NAME
litellm
LITELLM_DB_USER
litellm_user
LITELLM_DB_PASSWORD
(generated)
SUPERTOKENS_DB_NAME
supertokens
SUPERTOKENS_DB_USER
supertokens_user
SUPERTOKENS_DB_PASSWORD
(generated)
FLOWISE_DB_NAME
flowise
FLOWISE_DB_USER
flowise_user
FLOWISE_DB_PASSWORD
(generated)

32.3 Secret Keys & Tokens
Copy table
Variable
Length
Used By
DIFY_SECRET_KEY
42 chars
Dify API
LITELLM_MASTER_KEY
32 chars (sk- prefix)
LiteLLM Admin
N8N_ENCRYPTION_KEY
32 chars
n8n credential encryption
FLOWISE_SECRET_KEY
32 chars
Flowise
SUPERTOKENS_API_KEY
32 chars
SuperTokens
GRAFANA_ADMIN_PASSWORD
24 chars
Grafana
OPEN_WEBUI_SECRET_KEY
32 chars
Open WebUI JWT

32.4 Cloud Provider Variables (Optional)
Copy table
Variable
Used By
OPENAI_API_KEY
LiteLLM → OpenAI
ANTHROPIC_API_KEY
LiteLLM → Anthropic
GOOGLE_API_KEY
LiteLLM → Google AI
MISTRAL_API_KEY
LiteLLM → Mistral
GROQ_API_KEY
LiteLLM → Groq
TOGETHER_API_KEY
LiteLLM → Together AI

32.5 Platform Configuration Variables
Copy table
Variable
Example
Purpose
DOMAIN_MODE
ip or domain
Routing strategy
HOST_IP
192.168.1.100
Server IP
DOMAIN_NAME
ai.example.com
Base domain
URL_PROTOCOL
https
HTTP or HTTPS
SSL_MODE
selfsigned / letsencrypt
TLS strategy
ADMIN_EMAIL
admin@example.com
Let's Encrypt + alerts
OLLAMA_BASE_URL
http://host.docker.internal:11434
Ollama endpoint
PRIMARY_MODEL
llama3.1:8b
Default chat model
EMBEDDING_MODEL
nomic-embed-text:latest
Default embedding model


Section 33: Update & Maintenance Procedures
33.1 Updating a Single Service
cd /opt/ai-platform/docker

# Pull new image
docker compose -f docker-compose.<service>.yml pull

# Recreate with new image
docker compose -f docker-compose.<service>.yml up -d

# Verify health
docker ps --filter "name=ai-platform-<service>"

33.2 Updating Ollama
# Update Ollama binary
curl -fsSL https://ollama.ai/install.sh | sh

# Restart service
sudo systemctl restart ollama

# Verify
ollama --version

# Models persist — no re-download needed
ollama list

33.3 Updating All Images
cd /opt/ai-platform/docker

# Stop all (reverse order)
sudo bash /opt/ai-platform/scripts/platform-stop.sh

# Pull all new images
for f in docker-compose.*.yml; do
    docker compose -f "$f" pull
done

# Start all (correct order)
sudo bash /opt/ai-platform/scripts/platform-start.sh

33.4 Updating Platform Configuration
# Edit configuration
nano /opt/ai-platform/config/litellm/config.yaml  # Example: add model

# Restart affected service
cd /opt/ai-platform/docker
docker compose -f docker-compose.litellm.yml restart

# Or for .env changes — must recreate
docker compose -f docker-compose.<service>.yml up -d

33.5 Database Maintenance
# PostgreSQL vacuum (run weekly)
docker exec ai-platform-postgres psql -U postgres -c "VACUUM ANALYZE;"

# Check database sizes
docker exec ai-platform-postgres psql -U postgres -c \
    "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database ORDER BY pg_database_size(datname) DESC;"

# Backup before major updates
sudo bash /opt/ai-platform/scripts/platform-backup.sh

33.6 Disk Space Management
# Check Docker disk usage
docker system df

# Remove unused images (safe)
docker image prune -f

# Remove unused volumes (⚠️ CAREFUL — only if you know they're unused)
docker volume prune -f

# Check Ollama model sizes
du -sh ~/.ollama/models/blobs/*

# Remove an Ollama model
ollama rm <model-name>


Section 34: Security Hardening Notes
34.1 Default Security Posture
The platform deploys with these security measures:
No default passwords — all credentials randomly generated
Credentials file restricted — chmod 600 on credentials.env
Internal ports localhost-bound — databases not exposed externally
Docker networks isolated — backend services unreachable from frontend network directly
TLS enabled — self-signed by default, Let's Encrypt optional
UFW firewall configured — only required ports open
34.2 Additional Hardening (Post-Install)
# Restrict SSH to key-only
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# Enable automatic security updates
sudo apt install unattended-upgrades -y
sudo dpkg-reconfigure -plow unattended-upgrades

# Set up fail2ban
sudo apt install fail2ban -y
sudo systemctl enable fail2ban

# Restrict Docker socket
sudo chmod 660 /var/run/docker.sock

# Review open ports periodically
sudo ss -tlnp | grep -v 127.0.0.1

34.3 API Key Security
IMPORTANT: LiteLLM Master Key grants full access to all models.

- Never expose port 4000 without authentication
- Caddy proxies LiteLLM — but does NOT add auth by default
- For production: add basic auth to Caddy for /api/* routes
- Rotate the master key periodically:
    1. Generate new key
    2. Update credentials.env
    3. Update litellm config.yaml
    4. Restart litellm
    5. Update Dify, n8n, Open WebUI connections


Section 35: Final Notes & Design Decisions
35.1 Why Separate Docker Compose Files?
Each service gets its own compose file rather than one monolithic file because:
Independent lifecycle — restart/update one service without touching others
Selective deployment — enable/disable optional services cleanly
Debugging — isolate issues to a single compose file
Resource management — control memory limits per service
Order control — deploy infrastructure before applications
35.2 Why LiteLLM as the AI Gateway?
LiteLLM provides a single OpenAI-compatible endpoint that:
Routes to 100+ LLM providers with one API format
Handles retries, fallbacks, and load balancing
Tracks token usage and cost per model
Caches responses in Redis
Exposes Prometheus metrics
Means all downstream services (Dify, n8n, Open WebUI) use the same endpoint format
35.3 Why Ollama on Host (Not in Docker)?
Direct GPU access — no NVIDIA Container Toolkit complexity
Shared across all containers — one Ollama serves everything via host.docker.internal
Model persistence — models survive container rebuilds
Simpler updates — curl install.sh vs rebuilding Docker image
Memory management — Ollama manages GPU VRAM directly without Docker overhead
35.4 Why Caddy (Not Nginx/Traefik)?
Automatic HTTPS — Let's Encrypt built-in, zero config
Simple config — Caddyfile vs nginx.conf complexity
Self-signed TLS — tls internal for IP-based installs
Low resource usage — single binary, minimal RAM
HTTP/3 support — built-in, no modules needed
35.5 Hardware Tier Design Philosophy
The three tiers (minimum, recommended, production) exist because:
Minimum (16GB): Runs small models (7B). Good for testing and light personal use
Recommended (32GB): Runs medium models (13B). Good for small teams
Production (64GB+): Runs large models (70B+) or multiple concurrent models. Good for organizations
GPU tiers follow the same logic — VRAM determines max model size that fits entirely in GPU memory, avoiding slow CPU fallback.
35.6 File Tree — Final State
/opt/ai-platform/
├── config/
│   ├── master.env                          # All platform variables
│   ├── credentials.env                     # All secrets (chmod 600)
│   ├── hardware-profile.env                # Detected hardware
│   ├── caddy/
│   │   └── Caddyfile                       # Reverse proxy config
│   ├── litellm/
│   │   └── config.yaml                     # Model routing config
│   ├── postgres/
│   │   └── init-databases.sql              # Multi-DB init script
│   ├── redis/
│   │   └── redis.conf                      # Redis configuration
│   ├── prometheus/
│   │   └── prometheus.yml                  # Scrape targets
│   └── grafana/
│       ├── provisioning/
│       │   └── datasources/
│       │       └── prometheus.yml          # Auto-provision datasource
│       └── dashboards/
│           └── (placeholder for JSON dashboards)
│
├── docker/
│   ├── docker-compose.postgres.yml
│   ├── docker-compose.redis.yml
│   ├── docker-compose.qdrant.yml
│   ├── docker-compose.supertokens.yml
│   ├── docker-compose.litellm.yml
│   ├── docker-compose.dify-api.yml
│   ├── docker-compose.dify-worker.yml
│   ├── docker-compose.dify-web.yml
│   ├── docker-compose.dify-sandbox.yml
│   ├── docker-compose.n8n.yml
│   ├── docker-compose.open-webui.yml
│   ├── docker-compose.flowise.yml          # (if enabled)
│   ├── docker-compose.caddy.yml
│   ├── docker-compose.prometheus.yml       # (if enabled)
│   └── docker-compose.grafana.yml          # (if enabled)
│
├── scripts/
│   ├── platform-status.sh
│   ├── platform-start.sh
│   ├── platform-stop.sh
│   ├── platform-restart.sh
│   ├── platform-logs.sh
│   └── platform-backup.sh
│
├── backups/
│   └── (timestamped .tar.gz files)
│
├── logs/
│   ├── script-1.log
│   ├── script-2.log
│   ├── script-3.log
│   └── script-4.log
│
├── 1-prep-system.sh
├── 2-deploy-platform.sh
├── 3-configure-platform.sh
└── 4-add-services.sh


END OF MASTER DOCUMENT
═══════════════════════════════════════════════════════════════
  AI PLATFORM — COMPLETE DEPLOYMENT MASTER DOCUMENT
  Total Sections: 35
  Total Scripts: 4
  Total Services: 15 (12 core + 3 optional)
  Target OS: Ubuntu 22.04 / 24.04 LTS
  Author: AI Platform Deployment Project
  Version: 1.0.0
═══════════════════════════════════════════════════════════════



