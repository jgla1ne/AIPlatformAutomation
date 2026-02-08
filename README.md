\# AI PLATFORM DEPLOYMENT — COMPLETE REFERENCE v76.3.0

\> \*\*Document Version:\*\* 76.3.0  
\> \*\*Date:\*\* 2025-01-27  
\> \*\*Compatibility:\*\* Ubuntu 24.04 LTS (Noble Numbat)  
\> \*\*Architecture:\*\* Single-node, Docker-based, GPU-optional  
\> \*\*Script Flow:\*\* 0-cleanup → 1-setup → 2-deploy → 3-configure → 4-add

\---

\#\# Table of Contents

\#\#\# Part 1 — Architecture & Foundation  
\- \[Section 1: Architecture Overview\](\#section-1-architecture-overview)  
\- \[Section 2: Design Philosophy\](\#section-2-design-philosophy)  
\- \[Section 3: Prerequisites & Assumptions\](\#section-3-prerequisites-assumptions)  
\- \[Section 4: Script Inventory & Flow\](\#section-4-script-inventory--flow)

\#\#\# Part 2 — Script 0: Cleanup  
\- \[Section 5: Script 0 — Cleanup System\](\#section-5-script-0--cleanup-system)

\#\#\# Part 3 — Script 1: System Setup  
\- \[Section 6: Script 1 — Structure & Phases\](\#section-6-script-1--structure--phases)  
\- \[Section 7: Phase 1 — Hardware Detection & Profiling\](\#section-7-phase-1--hardware-detection--profiling)  
\- \[Section 8: Phase 2 — Docker Engine Installation\](\#section-8-phase-2--docker-engine-installation)  
\- \[Section 9: Phase 3 — NVIDIA Container Toolkit\](\#section-9-phase-3--nvidia-container-toolkit)  
\- \[Section 10: Phase 4 — Ollama Installation & Model Pull\](\#section-10-phase-4--ollama-installation--model-pull)  
\- \[Section 11: Phase 5 — Validation & Handoff\](\#section-11-phase-5--validation--handoff)

\#\#\# Part 4 — Script 2: Deploy Platform  
\- \[Section 12: Script 2 — Structure & Phases\](\#section-12-script-2--structure--phases)  
\- \[Section 13: Phase 1 — Interactive Questionnaire\](\#section-13-phase-1--interactive-questionnaire)  
\- \[Section 14: Phase 2 — Credential Generation\](\#section-14-phase-2--credential-generation)  
\- \[Section 15: Phase 3 — master.env Generation\](\#section-15-phase-3--masterenv-generation)  
\- \[Section 16: Phase 4 — Service Environment Files\](\#section-16-phase-4--service-environment-files)  
\- \[Section 17: Phase 5 — PostgreSQL Initialization\](\#section-17-phase-5--postgresql-initialization)  
\- \[Section 18: Phase 6 — Redis Configuration\](\#section-18-phase-6--redis-configuration)  
\- \[Section 19: Phase 7 — LiteLLM Configuration\](\#section-19-phase-7--litellm-configuration)  
\- \[Section 20: Phase 8 — Dify Configuration Files\](\#section-20-phase-8--dify-configuration-files)  
\- \[Section 21: Phase 9 — Docker Compose Files (per service)\](\#section-21-phase-9--docker-compose-files-per-service)  
\- \[Section 22: Phase 10 — Caddyfile Generation\](\#section-22-phase-10--caddyfile-generation)  
\- \[Section 23: Phase 11 — Monitoring Stack Configuration\](\#section-23-phase-11--monitoring-stack-configuration)  
\- \[Section 24: Phase 12 — Convenience Scripts\](\#section-24-phase-12--convenience-scripts)  
\- \[Section 25: Phase 13 — Deploy All Services\](\#section-25-phase-13--deploy-all-services)

\#\#\# Part 5 — Script 3: Configure Services  
\- \[Section 26: Script 3 — Structure & Phases\](\#section-26-script-3--structure--phases)  
\- \[Section 27: Phase 1 — Wait for All Services Healthy\](\#section-27-phase-1--wait-for-all-services-healthy)  
\- \[Section 28: Phase 2 — Configure Dify via API\](\#section-28-phase-2--configure-dify-via-api)  
\- \[Section 29: Phase 3 — Configure n8n via API\](\#section-29-phase-3--configure-n8n-via-api)  
\- \[Section 30: Phase 4 — Configure OpenWebUI\](\#section-30-phase-4--configure-openwebui)  
\- \[Section 31: Phase 5 — Validate All Integrations\](\#section-31-phase-5--validate-all-integrations)

\#\#\# Part 6 — Script 4: Add Services  
\- \[Section 32: Script 4 — Structure & Purpose\](\#section-32-script-4--structure--purpose)

\#\#\# Part 7 — Reference Material  
\- \[Section 33: Complete File Manifest\](\#section-33-complete-file-manifest)  
\- \[Section 34: Environment Variable Reference\](\#section-34-environment-variable-reference)  
\- \[Section 35: Port Map\](\#section-35-port-map)  
\- \[Section 36: Post-Deployment Verification Checklist\](\#section-36-post-deployment-verification-checklist)  
\- \[Section 37: Architecture Diagram\](\#section-37-architecture-diagram)

\---

\#\# Section 1: Architecture Overview

\#\#\# 1.1 Platform Components

The AI Platform deploys the following services on a single Ubuntu 24.04 node:

| Layer | Service | Purpose | Container Name |  
|-------|---------|---------|----------------|  
| \*\*Reverse Proxy\*\* | Caddy 2 | HTTPS termination, routing, auto-TLS | \`caddy\` |  
| \*\*AI Gateway\*\* | LiteLLM | Unified API gateway for all LLM providers | \`litellm\` |  
| \*\*AI Runtime\*\* | Ollama | Local model inference (GPU/CPU) | System service (not containerized) |  
| \*\*AI Platform\*\* | Dify | AI application builder (API \+ Web \+ Worker \+ Sandbox) | \`dify-api\`, \`dify-web\`, \`dify-worker\`, \`dify-sandbox\` |  
| \*\*Automation\*\* | n8n | Workflow automation | \`n8n\` |  
| \*\*Chat UI\*\* | Open WebUI | Chat interface for local/remote models | \`open-webui\` |  
| \*\*Flow Builder\*\* | Flowise | Visual LLM flow builder | \`flowise\` |  
| \*\*Auth\*\* | SuperTokens | Authentication service | \`supertokens\` |  
| \*\*Database\*\* | PostgreSQL 16 | Shared database (multi-schema) | \`postgres\` |  
| \*\*Cache\*\* | Redis 7 | Caching, queues, sessions | \`redis\` |  
| \*\*Vector DB\*\* | Qdrant | Vector similarity search | \`qdrant\` |  
| \*\*Monitoring\*\* | Prometheus \+ Grafana | Metrics collection \+ dashboards | \`prometheus\`, \`grafana\` |

\#\#\# 1.2 Network Architecture

\`\`\`text  
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

### **1.3 Ollama — System Service (Not Containerized)**

Ollama runs as a **systemd service** on the host, NOT inside Docker. This is a deliberate architectural decision:

* **Direct GPU access** — No Docker GPU passthrough overhead  
* **Shared across services** — LiteLLM, Dify, Open WebUI, and Flowise all connect to Ollama via `http://host.docker.internal:11434` or `http://${HOST_IP}:11434`  
* **Independent lifecycle** — Can pull models without restarting containers  
* **Script 1** installs and configures Ollama  
* **Script 2** references it in container environment variables

### **1.4 Docker Compose Strategy — One Compose Per Service**

Each service gets its own `docker-compose.<service>.yml` file. This provides:

* **Independent lifecycle** — Restart one service without affecting others  
* **Easier debugging** — Isolate failures to specific services  
* **Modular deployment** — Add/remove services without editing a monolithic file  
* **Clear ownership** — Each compose file manages exactly one concern

All compose files share external networks (`ai-platform`, `ai-backend`) created before any service starts.

### **1.5 Directory Structure**

/mnt/data/ai-platform/                          ← ROOT\_PATH  
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

---

## **Section 2: Design Philosophy**

### **2.1 Core Principles**

1. **Idempotent Execution** — Every script can be run multiple times safely. Functions check current state before making changes.

2. **Fail-Fast with Recovery** — Scripts stop on first error (`set -euo pipefail`), but include trap handlers that save state for re-run.

3. **Transparent Logging** — Every action is logged to both terminal (colored) and file (plain). Log files are saved to `${ROOT_PATH}/logs/`.

4. **User Confirmation** — Destructive operations require explicit confirmation. Non-destructive operations proceed automatically.

5. **Configuration-Driven** — All runtime values come from `master.env`. No hardcoded values in compose files or app configs.

6. **One Compose Per Service** — Modular, independent lifecycle per container group.

### **2.2 Logging Standard**

All scripts use a common logging pattern:

RED='\\033\[0;31m'  
GREEN='\\033\[0;32m'  
YELLOW='\\033\[1;33m'  
BLUE='\\033\[0;34m'  
CYAN='\\033\[0;36m'  
NC='\\033\[0m'

LOG\_FILE="${ROOT\_PATH}/logs/script-N.log"

log\_info()    { echo \-e "${GREEN}\[INFO\]${NC}  $ 1" | tee \-a " $ LOG\_FILE"; }  
log\_warn()    { echo \-e "${YELLOW}\[WARN\]${NC}  $ 1" | tee \-a " $ LOG\_FILE"; }  
log\_error()   { echo \-e "${RED}\[ERROR\]${NC}  $ 1" | tee \-a " $ LOG\_FILE"; }  
log\_section() { echo \-e "\\n${CYAN}========================================${NC}" | tee \-a " $ LOG\_FILE"  
                echo \-e " $ {CYAN}   $ 1 $ {NC}" | tee \-a " $ LOG\_FILE"  
                echo \-e " $ {CYAN}========================================${NC}\\n" | tee \-a "$LOG\_FILE"; }

### **2.3 Error Handling Standard**

set \-euo pipefail

trap 'error\_handler $? $LINENO  $ BASH\_COMMAND' ERR

error\_handler() {  
    local exit\_code= $ 1  
    local line\_number= $ 2  
    local command= $ 3  
    log\_error "Command failed at line ${line\_number}: ${command} (exit code: ${exit\_code})"  
    log\_error "Log file: ${LOG\_FILE}"  
    exit "${exit\_code}"  
}

### **2.4 Idempotency Pattern**

Every function follows this pattern:

install\_something() {  
    if something\_already\_installed; then  
        log\_info "Something already installed, skipping"  
        return 0  
    fi  
    \# ... perform installation ...  
    log\_info "Something installed successfully"  
}

---

## **Section 3: Prerequisites & Assumptions**

### **3.1 System Requirements**

Copy table

| Requirement | Minimum | Recommended |
| ----- | ----- | ----- |
| OS | Ubuntu 24.04 LTS | Ubuntu 24.04 LTS |
| CPU | 4 cores | 8+ cores |
| RAM | 16 GB | 32+ GB |
| Disk | 50 GB free | 100+ GB free (SSD/NVMe) |
| GPU | None (CPU-only mode) | NVIDIA with 8+ GB VRAM |
| Network | Internet access | Internet access |
| User | sudo privileges | sudo privileges |

### **3.2 What Must Exist Before Script 0**

* Ubuntu 24.04 fresh install or existing system  
* User with sudo access  
* Internet connectivity  
* `git` installed (to clone the repository)

### **3.3 What Script 0 Produces**

* Clean system: previous Docker, Ollama, NVIDIA container toolkit removed  
* Directory `/mnt/data/ai-platform/` created with proper ownership  
* Ready for Script 1

### **3.4 What Script 1 Produces**

* Hardware profile detected and saved  
* Docker Engine \+ Docker Compose installed and running  
* NVIDIA Container Toolkit installed (if GPU detected)  
* Ollama installed as systemd service with configured models  
* AppArmor profiles configured for Docker  
* System validated and ready for Script 2

### **3.5 What Script 2 Produces**

* User preferences collected (domain, providers, passwords)  
* All credentials generated  
* `master.env` with all 80+ variables  
* All service environment files  
* All `docker-compose.<service>.yml` files  
* Caddyfile, LiteLLM config, Prometheus config, Grafana provisioning  
* PostgreSQL init SQL, Redis config  
* All convenience scripts  
* ALL containers started and running

### **3.6 What Script 3 Produces**

* All services verified healthy  
* Dify configured (admin account, model providers connected)  
* n8n configured (initial workflows optional)  
* Open WebUI configured (Ollama connection verified)  
* All integrations tested and validated

### **3.7 What Script 4 Produces**

* Additional optional services deployed  
* Additional models pulled  
* Custom integrations configured

---

## **Section 4: Script Inventory & Flow**

### **4.1 Execution Order**

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

### **4.2 Inter-Script Communication**

Scripts communicate via:

1. **File system** — Each script reads outputs from previous scripts:

   * Script 1 writes: `${ROOT_PATH}/config/hardware-profile.env`  
   * Script 2 reads hardware profile, writes all configs \+ composes  
   * Script 3 reads `master.env` for URLs, credentials  
2. **Exit codes** — Each script exits 0 on success, non-zero on failure

3. **Log files** — Each script writes to `${ROOT_PATH}/logs/script-N.log`

### **4.3 Common Variables**

All scripts share these base variables:

ROOT\_PATH="/mnt/data/ai-platform"  
CONFIG\_PATH="${ROOT\_PATH}/config"  
DOCKER\_PATH="${ROOT\_PATH}/docker"  
DATA\_PATH="${ROOT\_PATH}/data"  
LOG\_PATH="${ROOT\_PATH}/logs"  
SCRIPTS\_PATH="${ROOT\_PATH}/scripts"  
BACKUP\_PATH="${ROOT\_PATH}/backups"

\---

\#\# Section 5: Script 0 — Cleanup System

\#\#\# 5.1 Purpose

\`0-cleanup.sh\` removes all traces of a previous installation so the system can be re-provisioned cleanly. It is \*\*optional\*\* — only needed when re-installing or resetting.

\#\#\# 5.2 Safety

The script requires explicit confirmation before proceeding. It distinguishes between:

\- \*\*Soft reset\*\* — Stop containers, remove configs, keep data volumes  
\- \*\*Hard reset\*\* — Remove everything including data volumes

\#\#\# 5.3 Execution

\`\`\`bash  
sudo bash 0-cleanup.sh          \# Interactive — asks which mode  
sudo bash 0-cleanup.sh \--hard   \# Non-interactive hard reset  
sudo bash 0-cleanup.sh \--soft   \# Non-interactive soft reset

### **5.4 Cleanup Phases**

Phase 1: Stop & Remove Containers  
  ├── Find all docker-compose.\*.yml files in /mnt/data/ai-platform/docker/  
  ├── For each: docker compose \-f \<file\> down \--remove-orphans  
  ├── docker container prune \-f  
  └── Remove external networks (ai-platform, ai-backend)

Phase 2: Remove Docker Volumes (hard mode only)  
  ├── docker volume ls \--filter label=com.docker.compose.project  
  ├── docker volume rm \<each volume\>  
  └── docker volume prune \-f

Phase 3: Stop Ollama (optional)  
  ├── systemctl stop ollama  
  ├── systemctl disable ollama  
  └── Note: does NOT uninstall Ollama binary (Script 1 handles install)

Phase 4: Remove Configuration Files  
  ├── rm \-rf /mnt/data/ai-platform/config/\*  
  ├── rm \-rf /mnt/data/ai-platform/docker/\*  
  ├── rm \-rf /mnt/data/ai-platform/scripts/\*  
  └── rm \-rf /mnt/data/ai-platform/logs/\*

Phase 5: Remove Data Directories (hard mode only)  
  ├── rm \-rf /mnt/data/ai-platform/data/\*  
  └── rm \-rf /mnt/data/ai-platform/backups/\*

Phase 6: Recreate Directory Structure  
  ├── mkdir \-p /mnt/data/ai-platform/{config,docker,data,logs,scripts,backups}  
  └── chown \-R ${SUDO\_USER:- $ USER}: $ {SUDO\_USER:-$USER} /mnt/data/ai-platform/

### **5.5 What It Does NOT Remove**

* Docker Engine itself (Script 1 manages this)  
* NVIDIA drivers or Container Toolkit (Script 1 manages this)  
* Ollama binary (Script 1 manages this)  
* System packages  
* User accounts

### **5.6 Pseudocode**

\#\!/usr/bin/env bash  
set \-euo pipefail

ROOT\_PATH="/mnt/data/ai-platform"  
LOG\_FILE="${ROOT\_PATH}/logs/script-0.log"

\# Source logging functions (same pattern as Section 2.2)

parse\_arguments() {  
    CLEANUP\_MODE="interactive"  
    while \[\[  $ \# \-gt 0 \]\]; do  
        case " $ 1" in  
            \--hard) CLEANUP\_MODE="hard" ;;  
            \--soft) CLEANUP\_MODE="soft" ;;  
            \--help) show\_help; exit 0 ;;  
            \*) log\_error "Unknown option:  $ 1"; exit 1 ;;  
        esac  
        shift  
    done  
}

confirm\_cleanup() {  
    if \[\[ " $ CLEANUP\_MODE" \== "interactive" \]\]; then  
        echo ""  
        echo "Select cleanup mode:"  
        echo "  1\) Soft reset — remove configs, keep data"  
        echo "  2\) Hard reset — remove EVERYTHING"  
        echo "  3\) Cancel"  
        read \-rp "Choice \[1-3\]: " choice  
        case "$choice" in  
            1\) CLEANUP\_MODE="soft" ;;  
            2\) CLEANUP\_MODE="hard" ;;  
            \*) log\_info "Cancelled."; exit 0 ;;  
        esac  
    fi

    log\_warn "This will perform a ${CLEANUP\_MODE} reset."  
    read \-rp "Type YES to confirm: " confirm  
    \[\[ " $ confirm" \== "YES" \]\] || { log\_info "Cancelled."; exit 0; }  
}

stop\_containers() {  
    log\_section "Stopping All Containers"  
    if \[\[ \-d " $ {ROOT\_PATH}/docker" \]\]; then  
        for compose\_file in "${ROOT\_PATH}"/docker/docker-compose.\*.yml; do  
            \[\[ \-f " $ compose\_file" \]\] || continue  
            local service\_name  
            service\_name= $ (basename "$compose\_file" | sed 's/docker-compose\\.$ .\* $ \\.yml/\\1/')  
            log\_info "Stopping ${service\_name}..."  
            docker compose \-f " $ compose\_file" down \--remove-orphans 2\>/dev/null || true  
        done  
    fi  
    docker container prune \-f 2\>/dev/null || true  
}

remove\_networks() {  
    log\_section "Removing Docker Networks"  
    docker network rm ai-platform 2\>/dev/null || true  
    docker network rm ai-backend 2\>/dev/null || true  
}

remove\_volumes() {  
    if \[\[ " $ CLEANUP\_MODE" \== "hard" \]\]; then  
        log\_section "Removing Docker Volumes"  
        docker volume prune \-f 2\>/dev/null || true  
    fi  
}

stop\_ollama() {  
    log\_section "Stopping Ollama"  
    if systemctl is-active \--quiet ollama 2\>/dev/null; then  
        systemctl stop ollama  
        systemctl disable ollama  
        log\_info "Ollama stopped and disabled"  
    else  
        log\_info "Ollama not running"  
    fi  
}

remove\_configs() {  
    log\_section "Removing Configuration Files"  
    rm \-rf "${ROOT\_PATH}/config"/\*  
    rm \-rf "${ROOT\_PATH}/docker"/\*  
    rm \-rf "${ROOT\_PATH}/scripts"/\*  
    rm \-rf "${ROOT\_PATH}/logs"/\*  
    log\_info "Configuration files removed"  
}

remove\_data() {  
    if \[\[ " $ CLEANUP\_MODE" \== "hard" \]\]; then  
        log\_section "Removing All Data"  
        rm \-rf " $ {ROOT\_PATH}/data"/\*  
        rm \-rf "${ROOT\_PATH}/backups"/\*  
        log\_info "All data removed"  
    fi  
}

recreate\_directories() {  
    log\_section "Recreating Directory Structure"  
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

    for dir in "${dirs\[@\]}"; do  
        mkdir \-p "${ROOT\_PATH}/${dir}"  
    done

    local owner="${SUDO\_USER:- $ USER}"  
    chown \-R " $ {owner}:${owner}" "${ROOT\_PATH}"  
    log\_info "Directory structure recreated"  
}

\# \--- Main \---  
parse\_arguments " $ @"  
mkdir \-p " $ {ROOT\_PATH}/logs"  
confirm\_cleanup  
stop\_containers  
remove\_networks  
remove\_volumes  
stop\_ollama  
remove\_configs  
remove\_data  
recreate\_directories  
log\_section "Cleanup Complete (${CLEANUP\_MODE} mode)"

---

## **Section 6: Script 1 — Structure & Phases**

### **6.1 Purpose**

`1-setup-system.sh` prepares the bare Ubuntu 24.04 system to host the AI platform. It detects hardware, installs Docker, configures GPU support if available, installs Ollama, pulls models, and validates everything.

### **6.2 Execution**

sudo bash 1-setup-system.sh

### **6.3 Phase Map**

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
│   ├── Configure Ollama environment (OLLAMA\_HOST, OLLAMA\_ORIGINS)  
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

---

## **Section 7: Phase 1 — Hardware Detection & Profiling**

### **7.1 Detection Logic**

detect\_hardware() {  
    log\_section "Detecting Hardware"

    \# CPU  
    CPU\_CORES= $ (nproc)  
    CPU\_MODEL= $ (grep \-m1 'model name' /proc/cpuinfo | cut \-d':' \-f2 | xargs)  
    log\_info "CPU: ${CPU\_MODEL} (${CPU\_CORES} cores)"

    \# Memory  
    TOTAL\_RAM\_KB=$(grep MemTotal /proc/meminfo | awk '{print  $ 2}')  
    TOTAL\_RAM\_GB= $ (( TOTAL\_RAM\_KB / 1024 / 1024 ))  
    log\_info "RAM: ${TOTAL\_RAM\_GB} GB"

    \# Disk  
    DISK\_FREE\_GB=$(df \-BG / | tail \-1 | awk '{print  $ 4}' | tr \-d 'G')  
    DISK\_TOTAL\_GB= $ (df \-BG / | tail \-1 | awk '{print  $ 2}' | tr \-d 'G')  
    \# Detect SSD vs HDD  
    ROOT\_DEVICE= $ (findmnt \-n \-o SOURCE / | sed 's/\[0-9\]\* $ //' | xargs basename 2\>/dev/null || echo "unknown")  
    DISK\_TYPE="unknown"  
    if \[\[ \-f "/sys/block/ $ {ROOT\_DEVICE}/queue/rotational" \]\]; then  
        if \[\[  $ (cat "/sys/block/ $ {ROOT\_DEVICE}/queue/rotational") \== "0" \]\]; then  
            DISK\_TYPE="ssd"  
        else  
            DISK\_TYPE="hdd"  
        fi  
    fi  
    log\_info "Disk: ${DISK\_FREE\_GB} GB free / ${DISK\_TOTAL\_GB} GB total (${DISK\_TYPE})"

    \# GPU  
    GPU\_AVAILABLE="false"  
    GPU\_MODEL="none"  
    GPU\_VRAM\_MB="0"  
    GPU\_DRIVER\_VERSION="none"

    if command \-v nvidia-smi &\>/dev/null; then  
        if nvidia-smi &\>/dev/null; then  
            GPU\_AVAILABLE="true"  
            GPU\_MODEL= $ (nvidia-smi \--query-gpu=name \--format=csv,noheader | head \-1 | xargs)  
            GPU\_VRAM\_MB= $ (nvidia-smi \--query-gpu=memory.total \--format=csv,noheader,nounits | head \-1 | xargs)  
            GPU\_DRIVER\_VERSION=$(nvidia-smi \--query-gpu=driver\_version \--format=csv,noheader | head \-1 | xargs)  
            log\_info "GPU: ${GPU\_MODEL} (${GPU\_VRAM\_MB} MB VRAM, driver ${GPU\_DRIVER\_VERSION})"  
        fi  
    fi

    if \[\[ "$GPU\_AVAILABLE" \== "false" \]\]; then  
        log\_info "GPU: None detected — CPU-only mode"  
    fi  
}

### **7.2 System Tier Classification**

classify\_system\_tier() {  
    \# Tier determines default model selection and resource limits  
    if \[\[ " $ GPU\_AVAILABLE" \== "true" && " $ GPU\_VRAM\_MB" \-ge 16000 && " $ TOTAL\_RAM\_GB" \-ge 32 \]\]; then  
        SYSTEM\_TIER="performance"  
        DEFAULT\_MODELS="llama3.1:8b,nomic-embed-text,codellama:13b"  
    elif \[\[ " $ GPU\_AVAILABLE" \== "true" && " $ GPU\_VRAM\_MB" \-ge 6000 && " $ TOTAL\_RAM\_GB" \-ge 16 \]\]; then  
        SYSTEM\_TIER="standard"  
        DEFAULT\_MODELS="llama3.1:8b,nomic-embed-text"  
    else  
        SYSTEM\_TIER="minimal"  
        DEFAULT\_MODELS="llama3.2:3b,nomic-embed-text"  
    fi

    log\_info "System tier: ${SYSTEM\_TIER}"  
    log\_info "Default models: ${DEFAULT\_MODELS}"  
}

### **7.3 Hardware Profile Output**

write\_hardware\_profile() {  
    local profile\_file="${CONFIG\_PATH}/hardware-profile.env"  
    cat \> "$profile\_file" \<\< EOF  
\# Hardware Profile — Generated by 1-setup-system.sh  
\# Generated:  $ (date \-u \+"%Y-%m-%dT%H:%M:%SZ")

CPU\_CORES= $ {CPU\_CORES}  
CPU\_MODEL="${CPU\_MODEL}"  
TOTAL\_RAM\_GB=${TOTAL\_RAM\_GB}  
DISK\_FREE\_GB=${DISK\_FREE\_GB}  
DISK\_TOTAL\_GB=${DISK\_TOTAL\_GB}  
DISK\_TYPE=${DISK\_TYPE}  
GPU\_AVAILABLE=${GPU\_AVAILABLE}  
GPU\_MODEL="${GPU\_MODEL}"  
GPU\_VRAM\_MB=${GPU\_VRAM\_MB}  
GPU\_DRIVER\_VERSION="${GPU\_DRIVER\_VERSION}"  
SYSTEM\_TIER=${SYSTEM\_TIER}  
DEFAULT\_MODELS="${DEFAULT\_MODELS}"  
EOF  
    log\_info "Hardware profile written to ${profile\_file}"  
}

---

## **Section 8: Phase 2 — Docker Engine Installation**

### **8.1 Installation Logic**

install\_docker() {  
    log\_section "Installing Docker Engine"

    \# Idempotency check  
    if command \-v docker &\>/dev/null && docker compose version &\>/dev/null; then  
        local docker\_version  
        docker\_version=$(docker \--version)  
        log\_info "Docker already installed: ${docker\_version}"  
        return 0  
    fi

    \# Remove conflicting packages  
    log\_info "Removing conflicting packages..."  
    local conflicting\_packages=(  
        docker.io docker-doc docker-compose docker-compose-v2  
        podman-docker containerd runc  
    )  
    for pkg in "${conflicting\_packages\[@\]}"; do  
        apt-get remove \-y " $ pkg" 2\>/dev/null || true  
    done

    \# Install prerequisites  
    log\_info "Installing prerequisites..."  
    apt-get update \-y  
    apt-get install \-y ca-certificates curl gnupg lsb-release

    \# Add Docker GPG key  
    log\_info "Adding Docker GPG key..."  
    install \-m 0755 \-d /etc/apt/keyrings  
    curl \-fsSL https://download.docker.com/linux/ubuntu/gpg | \\  
        gpg \--dearmor \-o /etc/apt/keyrings/docker.gpg  
    chmod a+r /etc/apt/keyrings/docker.gpg

    \# Add Docker repository  
    log\_info "Adding Docker repository..."  
    echo \\  
        "deb \[arch= $ (dpkg \--print-architecture) signed-by=/etc/apt/keyrings/docker.gpg\] \\  
        https://download.docker.com/linux/ubuntu \\  
         $ (. /etc/os-release && echo " $ VERSION\_CODENAME") stable" | \\  
        tee /etc/apt/sources.list.d/docker.list \> /dev/null

    \# Install Docker  
    log\_info "Installing Docker packages..."  
    apt-get update \-y  
    apt-get install \-y \\  
        docker-ce \\  
        docker-ce-cli \\  
        containerd.io \\  
        docker-buildx-plugin \\  
        docker-compose-plugin

    \# Add user to docker group  
    local target\_user="${SUDO\_USER:- $ USER}"  
    if \! groups " $ target\_user" | grep \-q docker; then  
        usermod \-aG docker "$target\_user"  
        log\_info "Added ${target\_user} to docker group"  
    fi

    \# Configure Docker daemon  
    configure\_docker\_daemon

    \# Start and enable  
    systemctl enable docker  
    systemctl start docker

    log\_info "Docker installed: $(docker \--version)"  
}

### **8.2 Docker Daemon Configuration**

configure\_docker\_daemon() {  
    log\_info "Configuring Docker daemon..."  
    mkdir \-p /etc/docker

    cat \> /etc/docker/daemon.json \<\< 'EOF'  
{  
    "log-driver": "json-file",  
    "log-opts": {  
        "max-size": "10m",  
        "max-file": "3"  
    },  
    "storage-driver": "overlay2",  
    "live-restore": true,  
    "default-address-pools": \[  
        {  
            "base": "172.20.0.0/14",  
            "size": 24  
        }  
    \]  
}  
EOF

    log\_info "Docker daemon configured"  
}

### **8.3 Docker Verification**

verify\_docker() {  
    log\_info "Verifying Docker installation..."

    \# Test docker daemon  
    if \! docker info &\>/dev/null; then  
        log\_error "Docker daemon is not responding"  
        return 1  
    fi

    \# Test docker compose  
    if \! docker compose version &\>/dev/null; then  
        log\_error "Docker Compose plugin not available"  
        return 1  
    fi

    \# Test container execution  
    if \! docker run \--rm hello-world &\>/dev/null; then  
        log\_error "Docker cannot run containers"  
        return 1  
    fi

    log\_info "Docker verification passed"  
}

---

## **Section 9: Phase 3 — NVIDIA Container Toolkit**

### **9.1 Installation Logic**

install\_nvidia\_toolkit() {  
    log\_section "NVIDIA Container Toolkit"

    \# Skip if no GPU  
    if \[\[ "$GPU\_AVAILABLE" \!= "true" \]\]; then  
        log\_info "No GPU detected — skipping NVIDIA Container Toolkit"  
        return 0  
    fi

    \# Idempotency check  
    if dpkg \-l | grep \-q nvidia-container-toolkit && \\  
       docker run \--rm \--gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi &\>/dev/null; then  
        log\_info "NVIDIA Container Toolkit already installed and working"  
        return 0  
    fi

    \# Verify NVIDIA driver is present  
    if \! nvidia-smi &\>/dev/null; then  
        log\_error "NVIDIA driver not installed. Install GPU drivers first."  
        log\_error "Run: sudo apt install nvidia-driver-535 (or appropriate version)"  
        return 1  
    fi

    \# Add NVIDIA Container Toolkit repository  
    log\_info "Adding NVIDIA Container Toolkit repository..."  
    curl \-fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \\  
        gpg \--dearmor \-o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

    curl \-s \-L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \\  
        sed 's\#deb https://\#deb \[signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg\] https://\#g' | \\  
        tee /etc/apt/sources.list.d/nvidia-container-toolkit.list \> /dev/null

    \# Install  
    log\_info "Installing nvidia-container-toolkit..."  
    apt-get update \-y  
    apt-get install \-y nvidia-container-toolkit

    \# Configure Docker runtime  
    log\_info "Configuring NVIDIA Docker runtime..."  
    nvidia-ctk runtime configure \--runtime=docker

    \# Restart Docker to apply runtime changes  
    systemctl restart docker

    \# Test GPU passthrough  
    log\_info "Testing GPU passthrough..."  
    if docker run \--rm \--gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi; then  
        log\_info "GPU passthrough test PASSED"  
    else  
        log\_error "GPU passthrough test FAILED"  
        return 1  
    fi

    log\_info "NVIDIA Container Toolkit installed and configured"  
}

---

## **Section 10: Phase 4 — Ollama Installation & Model Pull**

### **10.1 Installation Logic**

install\_ollama() {  
    log\_section "Installing Ollama"

    \# Idempotency check  
    if command \-v ollama &\>/dev/null && systemctl is-active \--quiet ollama; then  
        log\_info "Ollama already installed and running"  
        configure\_ollama\_env  
        return 0  
    fi

    \# Install via official script  
    log\_info "Installing Ollama..."  
    curl \-fsSL https://ollama.com/install.sh | sh

    \# Configure environment  
    configure\_ollama\_env

    \# Handle AppArmor if active  
    configure\_ollama\_apparmor

    \# Start and enable  
    systemctl daemon-reload  
    systemctl enable ollama  
    systemctl start ollama

    \# Wait for API to respond  
    wait\_for\_ollama

    log\_info "Ollama installed and running"  
}

### **10.2 Ollama Environment Configuration**

configure\_ollama\_env() {  
    log\_info "Configuring Ollama environment..."

    \# Create override directory  
    mkdir \-p /etc/systemd/system/ollama.service.d

    \# Detect host IP for container access  
    HOST\_IP=$(hostname \-I | awk '{print $1}')

    cat \> /etc/systemd/system/ollama.service.d/override.conf \<\< EOF  
\[Service\]  
Environment="OLLAMA\_HOST=0.0.0.0:11434"  
Environment="OLLAMA\_ORIGINS=\*"  
Environment="OLLAMA\_KEEP\_ALIVE=5m"  
EOF

    systemctl daemon-reload  
    log\_info "Ollama configured: listening on 0.0.0.0:11434"  
}

### **10.3 AppArmor Configuration**

configure\_ollama\_apparmor() {  
    \# Check if AppArmor is active  
    if \! command \-v aa-status &\>/dev/null; then  
        log\_info "AppArmor not installed — skipping"  
        return 0  
    fi

    if \! aa-status \--enabled 2\>/dev/null; then  
        log\_info "AppArmor not enabled — skipping"  
        return 0  
    fi

    log\_info "Configuring AppArmor for Ollama..."

    \# Check if Ollama is being blocked by AppArmor  
    if aa-status 2\>/dev/null | grep \-q ollama; then  
        log\_info "Ollama AppArmor profile already exists"  
        return 0  
    fi

    \# Create permissive profile for Ollama if it gets blocked  
    \# This is needed on some Ubuntu 24.04 installations  
    cat \> /etc/apparmor.d/usr.local.bin.ollama \<\< 'EOF'  
\#include \<tunables/global\>

/usr/local/bin/ollama flags=(unconfined) {  
  userns,  
}  
EOF

    \# Reload AppArmor  
    apparmor\_parser \-r /etc/apparmor.d/usr.local.bin.ollama 2\>/dev/null || true  
    log\_info "AppArmor profile configured for Ollama"  
}

### **10.4 Wait for Ollama**

wait\_for\_ollama() {  
    log\_info "Waiting for Ollama API..."  
    local max\_attempts=30  
    local attempt=0

    while \[\[ $attempt \-lt  $ max\_attempts \]\]; do  
        if curl \-sf http://localhost:11434/api/tags &\>/dev/null; then  
            log\_info "Ollama API is ready"  
            return 0  
        fi  
        attempt= $ ((attempt \+ 1))  
        sleep 2  
    done

    log\_error "Ollama API did not respond after ${max\_attempts} attempts"  
    return 1  
}

### **10.5 Model Pull**

pull\_ollama\_models() {  
    log\_section "Pulling Ollama Models"

    \# DEFAULT\_MODELS is set by classify\_system\_tier()  
    IFS=',' read \-ra MODELS \<\<\< " $ DEFAULT\_MODELS"

    for model in " $ {MODELS\[@\]}"; do  
        model= $ (echo " $ model" | xargs)  \# trim whitespace  
        log\_info "Pulling model: ${model}..."

        \# Check if already pulled  
        if ollama list 2\>/dev/null | grep \-q "^${model}"; then  
            log\_info "Model ${model} already available"  
            continue  
        fi

        if ollama pull "$model"; then  
            log\_info "Model ${model} pulled successfully"  
        else  
            log\_warn "Failed to pull model ${model} — continuing"  
        fi  
    done

    \# List all available models  
    log\_info "Available models:"  
    ollama list  
}

---

## **Section 11: Phase 5 — Validation & Handoff**

### **11.1 Validation Logic**

validate\_system() {  
    log\_section "System Validation"

    local errors=0

    \# Docker  
    if docker info &\>/dev/null; then  
        log\_info "✓ Docker daemon running"  
    else  
        log\_error "✗ Docker daemon not running"  
        errors= $ ((errors \+ 1))  
    fi

    \# Docker Compose  
    if docker compose version &\>/dev/null; then  
        log\_info "✓ Docker Compose available"  
    else  
        log\_error "✗ Docker Compose not available"  
        errors= $ ((errors \+ 1))  
    fi

    \# GPU (if detected)  
    if \[\[ " $ GPU\_AVAILABLE" \== "true" \]\]; then  
        if docker run \--rm \--gpus all nvidia/cuda:12.0.0-base-ubuntu22.04 nvidia-smi &\>/dev/null; then  
            log\_info "✓ GPU passthrough working"  
        else  
            log\_error "✗ GPU passthrough failed"  
            errors= $ ((errors \+ 1))  
        fi  
    fi

    \# Ollama  
    if curl \-sf http://localhost:11434/api/tags &\>/dev/null; then  
        log\_info "✓ Ollama API responding"  
    else  
        log\_error "✗ Ollama API not responding"  
        errors= $ ((errors \+ 1))  
    fi

    \# Models  
    local model\_count  
    model\_count= $ (ollama list 2\>/dev/null | tail \-n \+2 | wc \-l)  
    if \[\[ "$model\_count" \-gt 0 \]\]; then  
        log\_info "✓ ${model\_count} model(s) available"  
    else  
        log\_warn "⚠ No models available (pull may have failed)"  
    fi

    \# Directory structure  
    if \[\[ \-d "${ROOT\_PATH}/config" && \-d "${ROOT\_PATH}/docker" && \-d "${ROOT\_PATH}/data" \]\]; then  
        log\_info "✓ Directory structure intact"  
    else  
        log\_error "✗ Directory structure incomplete"  
        errors= $ ((errors \+ 1))  
    fi

    \# Hardware profile  
    if \[\[ \-f " $ {CONFIG\_PATH}/hardware-profile.env" \]\]; then  
        log\_info "✓ Hardware profile saved"  
    else  
        log\_error "✗ Hardware profile missing"  
        errors=$((errors \+ 1))  
    fi

    \# Summary  
    echo ""  
    if \[\[ $errors \-eq 0 \]\]; then  
        log\_section "VALIDATION PASSED — System Ready"  
        echo ""  
        log\_info "Next step: Run 2-deploy-platform.sh"  
        echo ""  
        echo "  sudo bash 2-deploy-platform.sh"  
        echo ""  
    else  
        log\_error "VALIDATION FAILED — ${errors} error(s) found"  
        log\_error "Fix the issues above and re-run this script"  
        exit 1  
    fi  
}

### **11.2 Handoff Summary**

At the end of Script 1, the following exists on the system:

Copy table

| Component | State | Location |
| ----- | ----- | ----- |
| Docker Engine | Running | systemd service |
| Docker Compose | Available | Plugin for docker CLI |
| NVIDIA Container Toolkit | Installed (if GPU) | Docker runtime configured |
| Ollama | Running | systemd service, port 11434 |
| Models | Pulled | `~/.ollama/models/` |
| Hardware Profile | Written | `${CONFIG_PATH}/hardware-profile.env` |
| Directory Structure | Created | `/mnt/data/ai-platform/*` |
| Log File | Written | `${ROOT_PATH}/logs/script-1.log` |

\---

\#\# Section 12: Script 2 — Overview & Structure

\#\#\# 12.1 Purpose

\`2-deploy-platform.sh\` is the primary deployment script. It collects user preferences via an interactive questionnaire, generates ALL configuration files, creates ALL docker-compose files (one per service), then deploys every container.

\#\#\# 12.2 Execution

\`\`\`bash  
sudo bash 2-deploy-platform.sh

### **12.3 Phase Map**

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
    └── Print next-steps (run script 3\)

---

## **Section 13: Phase 1 — Pre-flight Checks**

### **13.1 Preflight Logic**

preflight\_checks() {  
    log\_section "Pre-flight Checks"

    local errors=0

    \# Root check  
    if \[\[  $ EUID \-ne 0 \]\]; then  
        log\_error "This script must be run as root (use sudo)"  
        exit 1  
    fi

    \# Docker  
    if \! docker info &\>/dev/null; then  
        log\_error "Docker is not running. Run 1-setup-system.sh first."  
        errors= $ ((errors \+ 1))  
    else  
        log\_info "✓ Docker is running"  
    fi

    \# Docker Compose  
    if \! docker compose version &\>/dev/null; then  
        log\_error "Docker Compose not available. Run 1-setup-system.sh first."  
        errors= $ ((errors \+ 1))  
    else  
        log\_info "✓ Docker Compose available"  
    fi

    \# Ollama  
    if \! curl \-sf http://localhost:11434/api/tags &\>/dev/null; then  
        log\_error "Ollama is not running. Run 1-setup-system.sh first."  
        errors= $ ((errors \+ 1))  
    else  
        log\_info "✓ Ollama is running"  
    fi

    \# Hardware profile  
    if \[\[ \! \-f "${CONFIG\_PATH}/hardware-profile.env" \]\]; then  
        log\_error "Hardware profile not found. Run 1-setup-system.sh first."  
        errors= $ ((errors \+ 1))  
    else  
        source " $ {CONFIG\_PATH}/hardware-profile.env"  
        log\_info "✓ Hardware profile loaded (tier: ${SYSTEM\_TIER})"  
    fi

    \# Disk space check (need at least 20GB free for images)  
    local free\_gb  
    free\_gb=$(df \-BG /var/lib/docker 2\>/dev/null | tail \-1 | awk '{print  $ 4}' | tr \-d 'G')  
    if \[\[ \-n " $ free\_gb" && " $ free\_gb" \-lt 20 \]\]; then  
        log\_error "Less than 20GB free in /var/lib/docker — need space for images"  
        errors= $ ((errors \+ 1))  
    else  
        log\_info "✓ Disk space OK (${free\_gb}GB free)"  
    fi

    if \[\[ $errors \-gt 0 \]\]; then  
        log\_error "Pre-flight failed with ${errors} error(s)"  
        exit 1  
    fi

    log\_info "All pre-flight checks passed"  
}

---

## **Section 14: Phase 2 — Interactive Questionnaire**

### **14.1 Design Principles**

* Every question has a sensible default (press Enter to accept)  
* Passwords are never displayed on screen (use `read -s`)  
* Input is validated before proceeding  
* All answers stored in variables for later use

### **14.2 Questionnaire Logic**

run\_questionnaire() {  
    log\_section "Platform Configuration"  
    echo ""  
    echo "Answer the following questions to configure your platform."  
    echo "Press Enter to accept \[default\] values."  
    echo ""

    \# \--- Network Configuration \---  
    echo "─── Network Configuration ───"  
    echo ""

    \# Domain or IP  
    local detected\_ip  
    detected\_ip=$(hostname \-I | awk '{print  $ 1}')

    read \-rp "Domain name or IP address \[ $ {detected\_ip}\]: " USER\_DOMAIN  
    USER\_DOMAIN="${USER\_DOMAIN:- $ detected\_ip}"

    \# Determine if domain or IP  
    if \[\[ " $ USER\_DOMAIN" \=\~ ^\[0-9\]+\\.\[0-9\]+\\.\[0-9\]+\\.\[0-9\]+$ \]\]; then  
        DOMAIN\_MODE="ip"  
        DOMAIN\_NAME=" $ USER\_DOMAIN"  
        log\_info "Mode: IP-based access ( $ {DOMAIN\_NAME})"  
    else  
        DOMAIN\_MODE="domain"  
        DOMAIN\_NAME=" $ USER\_DOMAIN"  
        log\_info "Mode: Domain-based access ( $ {DOMAIN\_NAME})"  
    fi

    \# SSL mode  
    echo ""  
    if \[\[ " $ DOMAIN\_MODE" \== "domain" \]\]; then  
        echo "SSL Certificate Mode:"  
        echo "  1\) Automatic (Let's Encrypt via Caddy) — recommended for public domains"  
        echo "  2\) Self-signed — for internal/private domains"  
        echo "  3\) None (HTTP only) — not recommended"  
        read \-rp "SSL mode \[1\]: " ssl\_choice  
        case " $ {ssl\_choice:-1}" in  
            1\) SSL\_MODE="letsencrypt" ;;  
            2\) SSL\_MODE="selfsigned" ;;  
            3\) SSL\_MODE="none" ;;  
            \*) SSL\_MODE="letsencrypt" ;;  
        esac  
    else  
        echo "IP-based access: SSL will use self-signed certificate"  
        SSL\_MODE="selfsigned"  
    fi  
    log\_info "SSL mode: ${SSL\_MODE}"

    \# \--- Admin Configuration \---  
    echo ""  
    echo "─── Admin Configuration ───"  
    echo ""

    read \-rp "Admin email address \[admin@${DOMAIN\_NAME}\]: " ADMIN\_EMAIL  
    ADMIN\_EMAIL="${ADMIN\_EMAIL:-admin@${DOMAIN\_NAME}}"

    echo ""  
    while true; do  
        read \-srp "Admin password (min 12 chars): " ADMIN\_PASSWORD  
        echo ""  
        if \[\[ ${\#ADMIN\_PASSWORD} \-ge 12 \]\]; then  
            read \-srp "Confirm admin password: " ADMIN\_PASSWORD\_CONFIRM  
            echo ""  
            if \[\[ " $ ADMIN\_PASSWORD" \== " $ ADMIN\_PASSWORD\_CONFIRM" \]\]; then  
                break  
            else  
                echo "Passwords do not match. Try again."  
            fi  
        else  
            echo "Password must be at least 12 characters. Try again."  
        fi  
    done  
    log\_info "Admin credentials configured"

    \# \--- LLM Provider API Keys \---  
    echo ""  
    echo "─── LLM Provider API Keys (optional — press Enter to skip) ───"  
    echo ""

    read \-srp "OpenAI API key: " OPENAI\_API\_KEY  
    echo ""  
    OPENAI\_API\_KEY="${OPENAI\_API\_KEY:-}"  
    if \[\[ \-n " $ OPENAI\_API\_KEY" \]\]; then  
        OPENAI\_ENABLED="true"  
        log\_info "OpenAI: configured"  
    else  
        OPENAI\_ENABLED="false"  
        log\_info "OpenAI: skipped"  
    fi

    read \-srp "Anthropic API key: " ANTHROPIC\_API\_KEY  
    echo ""  
    ANTHROPIC\_API\_KEY=" $ {ANTHROPIC\_API\_KEY:-}"  
    if \[\[ \-n " $ ANTHROPIC\_API\_KEY" \]\]; then  
        ANTHROPIC\_ENABLED="true"  
        log\_info "Anthropic: configured"  
    else  
        ANTHROPIC\_ENABLED="false"  
        log\_info "Anthropic: skipped"  
    fi

    read \-srp "Google AI (Gemini) API key: " GOOGLE\_API\_KEY  
    echo ""  
    GOOGLE\_API\_KEY=" $ {GOOGLE\_API\_KEY:-}"  
    if \[\[ \-n " $ GOOGLE\_API\_KEY" \]\]; then  
        GOOGLE\_ENABLED="true"  
        log\_info "Google AI: configured"  
    else  
        GOOGLE\_ENABLED="false"  
        log\_info "Google AI: skipped"  
    fi

    \# \--- Optional Services \---  
    echo ""  
    echo "─── Optional Services ───"  
    echo ""

    read \-rp "Enable Flowise? (visual workflow builder) \[y/N\]: " enable\_flowise  
    FLOWISE\_ENABLED="false"  
    \[\[ " $ {enable\_flowise,,}" \== "y" \]\] && FLOWISE\_ENABLED="true"  
    log\_info "Flowise: ${FLOWISE\_ENABLED}"

    read \-rp "Enable Grafana monitoring? \[Y/n\]: " enable\_grafana  
    GRAFANA\_ENABLED="true"  
    \[\[ "${enable\_grafana,,}" \== "n" \]\] && GRAFANA\_ENABLED="false"  
    log\_info "Grafana: ${GRAFANA\_ENABLED}"

    \# \--- Summary \---  
    echo ""  
    echo "─── Configuration Summary ───"  
    echo ""  
    echo "  Domain/IP:     ${DOMAIN\_NAME} (${DOMAIN\_MODE} mode)"  
    echo "  SSL:           ${SSL\_MODE}"  
    echo "  Admin email:   ${ADMIN\_EMAIL}"  
    echo "  OpenAI:        ${OPENAI\_ENABLED}"  
    echo "  Anthropic:     ${ANTHROPIC\_ENABLED}"  
    echo "  Google AI:     ${GOOGLE\_ENABLED}"  
    echo "  Flowise:       ${FLOWISE\_ENABLED}"  
    echo "  Grafana:       ${GRAFANA\_ENABLED}"  
    echo "  System tier:   ${SYSTEM\_TIER}"  
    echo ""  
    read \-rp "Proceed with this configuration? \[Y/n\]: " confirm  
    if \[\[ "${confirm,,}" \== "n" \]\]; then  
        log\_info "Cancelled by user"  
        exit 0  
    fi  
}

---

## **Section 15: Phase 3 — Credential Generation**

### **15.1 Generation Functions**

generate\_password() {  
    \# Generate a random password of specified length  
    local length="${1:-32}"  
    openssl rand \-base64 48 | tr \-dc 'A-Za-z0-9\!@\# $ %' | head \-c " $ length"  
}

generate\_hex\_key() {  
    \# Generate a hex key (for secret keys)  
    local length="${1:-64}"  
    openssl rand \-hex "$((length / 2))"  
}

generate\_uuid() {  
    cat /proc/sys/kernel/random/uuid  
}

### **15.2 Credential Generation Logic**

generate\_all\_credentials() {  
    log\_section "Generating Credentials"

    \# Database passwords  
    POSTGRES\_PASSWORD= $ (generate\_password 32\)  
    REDIS\_PASSWORD= $ (generate\_password 32\)  
    QDRANT\_API\_KEY= $ (generate\_password 32\)

    \# Service-specific database passwords  
    DIFY\_DB\_PASSWORD= $ (generate\_password 32\)  
    N8N\_DB\_PASSWORD= $ (generate\_password 32\)  
    LITELLM\_DB\_PASSWORD= $ (generate\_password 32\)  
    SUPERTOKENS\_DB\_PASSWORD= $ (generate\_password 32\)  
    FLOWISE\_DB\_PASSWORD= $ (generate\_password 32\)  
    GRAFANA\_DB\_PASSWORD= $ (generate\_password 32\)

    \# Secret keys  
    DIFY\_SECRET\_KEY= $ (generate\_hex\_key 64\)  
    N8N\_ENCRYPTION\_KEY= $ (generate\_hex\_key 64\)  
    LITELLM\_MASTER\_KEY="sk-litellm- $ (generate\_password 32)"  
    LITELLM\_ADMIN\_KEY="sk-admin- $ (generate\_password 32)"  
    FLOWISE\_SECRET\_KEY= $ (generate\_hex\_key 64\)  
    SUPERTOKENS\_API\_KEY= $ (generate\_password 32\)

    \# Dify-specific keys  
    DIFY\_INIT\_PASSWORD= $ (generate\_password 16\)  
    DIFY\_SANDBOX\_KEY= $ (generate\_hex\_key 32\)  
    DIFY\_STORAGE\_KEY= $ (generate\_hex\_key 32\)

    \# Grafana  
    GRAFANA\_ADMIN\_PASSWORD= $ (generate\_password 24\)

    \# Inter-service tokens  
    N8N\_WEBHOOK\_SECRET= $ (generate\_hex\_key 32\)

    log\_info "All credentials generated (${credential\_count} items)"  
}

### **15.3 Credentials File Output**

write\_credentials\_file() {  
    local cred\_file="${CONFIG\_PATH}/credentials.env"

    cat \> "$cred\_file" \<\< EOF  
\# Platform Credentials — Generated by 2-deploy-platform.sh  
\# Generated:  $ (date \-u \+"%Y-%m-%dT%H:%M:%SZ")  
\# WARNING: This file contains sensitive data. Restrict access.

\# \--- Database Passwords \---  
POSTGRES\_PASSWORD= $ {POSTGRES\_PASSWORD}  
REDIS\_PASSWORD=${REDIS\_PASSWORD}  
QDRANT\_API\_KEY=${QDRANT\_API\_KEY}

\# \--- Service Database Passwords \---  
DIFY\_DB\_PASSWORD=${DIFY\_DB\_PASSWORD}  
N8N\_DB\_PASSWORD=${N8N\_DB\_PASSWORD}  
LITELLM\_DB\_PASSWORD=${LITELLM\_DB\_PASSWORD}  
SUPERTOKENS\_DB\_PASSWORD=${SUPERTOKENS\_DB\_PASSWORD}  
FLOWISE\_DB\_PASSWORD=${FLOWISE\_DB\_PASSWORD}  
GRAFANA\_DB\_PASSWORD=${GRAFANA\_DB\_PASSWORD}

\# \--- Secret Keys \---  
DIFY\_SECRET\_KEY=${DIFY\_SECRET\_KEY}  
N8N\_ENCRYPTION\_KEY=${N8N\_ENCRYPTION\_KEY}  
LITELLM\_MASTER\_KEY=${LITELLM\_MASTER\_KEY}  
LITELLM\_ADMIN\_KEY=${LITELLM\_ADMIN\_KEY}  
FLOWISE\_SECRET\_KEY=${FLOWISE\_SECRET\_KEY}  
SUPERTOKENS\_API\_KEY=${SUPERTOKENS\_API\_KEY}

\# \--- Dify-Specific \---  
DIFY\_INIT\_PASSWORD=${DIFY\_INIT\_PASSWORD}  
DIFY\_SANDBOX\_KEY=${DIFY\_SANDBOX\_KEY}  
DIFY\_STORAGE\_KEY=${DIFY\_STORAGE\_KEY}

\# \--- Grafana \---  
GRAFANA\_ADMIN\_PASSWORD=${GRAFANA\_ADMIN\_PASSWORD}

\# \--- Inter-Service Tokens \---  
N8N\_WEBHOOK\_SECRET=${N8N\_WEBHOOK\_SECRET}

\# \--- Admin (user-provided) \---  
ADMIN\_EMAIL=${ADMIN\_EMAIL}  
ADMIN\_PASSWORD=${ADMIN\_PASSWORD}  
EOF

    chmod 600 "$cred\_file"  
    log\_info "Credentials written to ${cred\_file} (mode 600)"  
}

---

## **Section 16: Phase 4 — master.env Generation**

### **16.1 Purpose**

`master.env` is the single source of truth for ALL platform variables. Every docker-compose file, every service config, and every convenience script references this file.

### **16.2 Generation Logic**

generate\_master\_env() {  
    log\_section "Generating master.env"

    local master\_file="${CONFIG\_PATH}/master.env"

    \# Detect host IP  
    HOST\_IP=$(hostname \-I | awk '{print  $ 1}')

    \# Set protocol based on SSL mode  
    if \[\[ " $ SSL\_MODE" \== "none" \]\]; then  
        URL\_PROTOCOL="http"  
    else  
        URL\_PROTOCOL="https"  
    fi

    cat \> "$master\_file" \<\< EOF  
\# ╔══════════════════════════════════════════════════════════╗  
\# ║  AI PLATFORM — MASTER ENVIRONMENT FILE                  ║  
\# ║  Generated:  $ (date \-u \+"%Y-%m-%dT%H:%M:%SZ")                       ║  
\# ║  Do not edit manually — regenerate with Script 2        ║  
\# ╚══════════════════════════════════════════════════════════╝

\# ── Paths ──  
ROOT\_PATH=/mnt/data/ai-platform  
CONFIG\_PATH=/mnt/data/ai-platform/config  
DOCKER\_PATH=/mnt/data/ai-platform/docker  
DATA\_PATH=/mnt/data/ai-platform/data  
LOG\_PATH=/mnt/data/ai-platform/logs  
SCRIPTS\_PATH=/mnt/data/ai-platform/scripts  
BACKUP\_PATH=/mnt/data/ai-platform/backups

\# ── Network ──  
DOMAIN\_MODE= $ {DOMAIN\_MODE}  
DOMAIN\_NAME=${DOMAIN\_NAME}  
HOST\_IP=${HOST\_IP}  
SSL\_MODE=${SSL\_MODE}  
URL\_PROTOCOL=${URL\_PROTOCOL}

\# ── Hardware ──  
SYSTEM\_TIER=${SYSTEM\_TIER}  
GPU\_AVAILABLE=${GPU\_AVAILABLE}  
GPU\_VRAM\_MB=${GPU\_VRAM\_MB}  
CPU\_CORES=${CPU\_CORES}  
TOTAL\_RAM\_GB=${TOTAL\_RAM\_GB}

\# ── Feature Flags ──  
OPENAI\_ENABLED=${OPENAI\_ENABLED}  
ANTHROPIC\_ENABLED=${ANTHROPIC\_ENABLED}  
GOOGLE\_ENABLED=${GOOGLE\_ENABLED}  
FLOWISE\_ENABLED=${FLOWISE\_ENABLED}  
GRAFANA\_ENABLED=${GRAFANA\_ENABLED}

\# ── Admin ──  
ADMIN\_EMAIL=${ADMIN\_EMAIL}  
ADMIN\_PASSWORD=${ADMIN\_PASSWORD}

\# ── Provider API Keys ──  
OPENAI\_API\_KEY=${OPENAI\_API\_KEY:-}  
ANTHROPIC\_API\_KEY=${ANTHROPIC\_API\_KEY:-}  
GOOGLE\_API\_KEY=${GOOGLE\_API\_KEY:-}

\# ── PostgreSQL ──  
POSTGRES\_HOST=postgres  
POSTGRES\_PORT=5432  
POSTGRES\_USER=postgres  
POSTGRES\_PASSWORD=${POSTGRES\_PASSWORD}  
POSTGRES\_SHARED\_DB=ai\_platform

\# Service-specific database names  
DIFY\_DB\_NAME=dify  
DIFY\_DB\_USER=dify  
DIFY\_DB\_PASSWORD=${DIFY\_DB\_PASSWORD}

N8N\_DB\_NAME=n8n  
N8N\_DB\_USER=n8n  
N8N\_DB\_PASSWORD=${N8N\_DB\_PASSWORD}

LITELLM\_DB\_NAME=litellm  
LITELLM\_DB\_USER=litellm  
LITELLM\_DB\_PASSWORD=${LITELLM\_DB\_PASSWORD}

SUPERTOKENS\_DB\_NAME=supertokens  
SUPERTOKENS\_DB\_USER=supertokens  
SUPERTOKENS\_DB\_PASSWORD=${SUPERTOKENS\_DB\_PASSWORD}

FLOWISE\_DB\_NAME=flowise  
FLOWISE\_DB\_USER=flowise  
FLOWISE\_DB\_PASSWORD=${FLOWISE\_DB\_PASSWORD}

GRAFANA\_DB\_NAME=grafana  
GRAFANA\_DB\_USER=grafana  
GRAFANA\_DB\_PASSWORD=${GRAFANA\_DB\_PASSWORD}

\# ── Redis ──  
REDIS\_HOST=redis  
REDIS\_PORT=6379  
REDIS\_PASSWORD=${REDIS\_PASSWORD}

\# ── Qdrant ──  
QDRANT\_HOST=qdrant  
QDRANT\_PORT=6333  
QDRANT\_GRPC\_PORT=6334  
QDRANT\_API\_KEY=${QDRANT\_API\_KEY}

\# ── SuperTokens ──  
SUPERTOKENS\_HOST=supertokens  
SUPERTOKENS\_PORT=3567  
SUPERTOKENS\_API\_KEY=${SUPERTOKENS\_API\_KEY}

\# ── Ollama ──  
OLLAMA\_HOST=${HOST\_IP}  
OLLAMA\_PORT=11434  
OLLAMA\_BASE\_URL=http://${HOST\_IP}:11434

\# ── LiteLLM ──  
LITELLM\_HOST=litellm  
LITELLM\_PORT=4000  
LITELLM\_MASTER\_KEY=${LITELLM\_MASTER\_KEY}  
LITELLM\_ADMIN\_KEY=${LITELLM\_ADMIN\_KEY}  
LITELLM\_BASE\_URL=http://litellm:4000

\# ── Dify ──  
DIFY\_API\_HOST=dify-api  
DIFY\_API\_PORT=5001  
DIFY\_WEB\_HOST=dify-web  
DIFY\_WEB\_PORT=3000  
DIFY\_SECRET\_KEY=${DIFY\_SECRET\_KEY}  
DIFY\_INIT\_PASSWORD=${DIFY\_INIT\_PASSWORD}  
DIFY\_SANDBOX\_KEY=${DIFY\_SANDBOX\_KEY}  
DIFY\_STORAGE\_KEY=${DIFY\_STORAGE\_KEY}

\# ── n8n ──  
N8N\_HOST=n8n  
N8N\_PORT=5678  
N8N\_ENCRYPTION\_KEY=${N8N\_ENCRYPTION\_KEY}  
N8N\_WEBHOOK\_SECRET=${N8N\_WEBHOOK\_SECRET}  
N8N\_EXTERNAL\_URL=${URL\_PROTOCOL}://${DOMAIN\_NAME}:5678

\# ── Open WebUI ──  
OPEN\_WEBUI\_HOST=open-webui  
OPEN\_WEBUI\_PORT=3001

\# ── Flowise ──  
FLOWISE\_HOST=flowise  
FLOWISE\_PORT=3002  
FLOWISE\_SECRET\_KEY=${FLOWISE\_SECRET\_KEY}

\# ── Caddy ──  
CADDY\_HTTP\_PORT=80  
CADDY\_HTTPS\_PORT=443

\# ── Prometheus ──  
PROMETHEUS\_HOST=prometheus  
PROMETHEUS\_PORT=9090

\# ── Grafana ──  
GRAFANA\_HOST=grafana  
GRAFANA\_PORT=3003  
GRAFANA\_ADMIN\_PASSWORD=${GRAFANA\_ADMIN\_PASSWORD}

\# ── Docker Networks ──  
NETWORK\_FRONTEND=ai-platform  
NETWORK\_BACKEND=ai-backend

\# ── Container Image Versions ──  
POSTGRES\_IMAGE=postgres:16-alpine  
REDIS\_IMAGE=redis:7-alpine  
QDRANT\_IMAGE=qdrant/qdrant:v1.7.4  
SUPERTOKENS\_IMAGE=registry.supertokens.io/supertokens/supertokens-postgresql:9.0  
LITELLM\_IMAGE=ghcr.io/berriai/litellm:main-latest  
DIFY\_API\_IMAGE=langgenius/dify-api:0.15.3  
DIFY\_WEB\_IMAGE=langgenius/dify-web:0.15.3  
DIFY\_SANDBOX\_IMAGE=langgenius/dify-sandbox:0.2.10  
N8N\_IMAGE=docker.n8n.io/n8nio/n8n:latest  
OPEN\_WEBUI\_IMAGE=ghcr.io/open-webui/open-webui:main  
FLOWISE\_IMAGE=flowiseai/flowise:latest  
CADDY\_IMAGE=caddy:2-alpine  
PROMETHEUS\_IMAGE=prom/prometheus:v2.48.0  
GRAFANA\_IMAGE=grafana/grafana:10.2.0  
EOF

    chmod 600 "$master\_file"  
    log\_info "master.env written to ${master\_file} (mode 600)"  
}

---

## **Section 17: Phase 4 — Service Environment Files**

### **17.1 Purpose**

Each service gets its own `.env` file containing only the variables it needs. These are referenced by the per-service docker-compose files.

### **17.2 PostgreSQL Init SQL**

generate\_postgres\_init() {  
    log\_info "Generating PostgreSQL init script..."

    cat \> "${CONFIG\_PATH}/postgres/init-databases.sql" \<\< EOF  
\-- AI Platform — PostgreSQL Database Initialization  
\-- Generated by 2-deploy-platform.sh

\-- Create service roles and databases

\-- Dify  
CREATE USER ${DIFY\_DB\_USER} WITH PASSWORD '${DIFY\_DB\_PASSWORD}';  
CREATE DATABASE ${DIFY\_DB\_NAME} OWNER ${DIFY\_DB\_USER};  
GRANT ALL PRIVILEGES ON DATABASE ${DIFY\_DB\_NAME} TO ${DIFY\_DB\_USER};

\-- n8n  
CREATE USER ${N8N\_DB\_USER} WITH PASSWORD '${N8N\_DB\_PASSWORD}';  
CREATE DATABASE ${N8N\_DB\_NAME} OWNER ${N8N\_DB\_USER};  
GRANT ALL PRIVILEGES ON DATABASE ${N8N\_DB\_NAME} TO ${N8N\_DB\_USER};

\-- LiteLLM  
CREATE USER ${LITELLM\_DB\_USER} WITH PASSWORD '${LITELLM\_DB\_PASSWORD}';  
CREATE DATABASE ${LITELLM\_DB\_NAME} OWNER ${LITELLM\_DB\_USER};  
GRANT ALL PRIVILEGES ON DATABASE ${LITELLM\_DB\_NAME} TO ${LITELLM\_DB\_USER};

\-- SuperTokens  
CREATE USER ${SUPERTOKENS\_DB\_USER} WITH PASSWORD '${SUPERTOKENS\_DB\_PASSWORD}';  
CREATE DATABASE ${SUPERTOKENS\_DB\_NAME} OWNER ${SUPERTOKENS\_DB\_USER};  
GRANT ALL PRIVILEGES ON DATABASE ${SUPERTOKENS\_DB\_NAME} TO ${SUPERTOKENS\_DB\_USER};

\-- Flowise (conditional — always create, service may not be deployed)  
CREATE USER ${FLOWISE\_DB\_USER} WITH PASSWORD '${FLOWISE\_DB\_PASSWORD}';  
CREATE DATABASE ${FLOWISE\_DB\_NAME} OWNER ${FLOWISE\_DB\_USER};  
GRANT ALL PRIVILEGES ON DATABASE ${FLOWISE\_DB\_NAME} TO ${FLOWISE\_DB\_USER};

\-- Grafana  
CREATE USER ${GRAFANA\_DB\_USER} WITH PASSWORD '${GRAFANA\_DB\_PASSWORD}';  
CREATE DATABASE ${GRAFANA\_DB\_NAME} OWNER ${GRAFANA\_DB\_USER};  
GRANT ALL PRIVILEGES ON DATABASE ${GRAFANA\_DB\_NAME} TO ${GRAFANA\_DB\_USER};

\-- Grant schema permissions (required for some services)  
\\c ${DIFY\_DB\_NAME}  
GRANT ALL ON SCHEMA public TO ${DIFY\_DB\_USER};

\\c ${N8N\_DB\_NAME}  
GRANT ALL ON SCHEMA public TO ${N8N\_DB\_USER};

\\c ${LITELLM\_DB\_NAME}  
GRANT ALL ON SCHEMA public TO ${LITELLM\_DB\_USER};

\\c ${SUPERTOKENS\_DB\_NAME}  
GRANT ALL ON SCHEMA public TO ${SUPERTOKENS\_DB\_USER};

\\c ${FLOWISE\_DB\_NAME}  
GRANT ALL ON SCHEMA public TO ${FLOWISE\_DB\_USER};

\\c ${GRAFANA\_DB\_NAME}  
GRANT ALL ON SCHEMA public TO ${GRAFANA\_DB\_USER};  
EOF

    log\_info "PostgreSQL init script generated"  
}

### **17.3 Redis Configuration**

generate\_redis\_config() {  
    log\_info "Generating Redis configuration..."

    cat \> "${CONFIG\_PATH}/redis/redis.conf" \<\< EOF  
\# AI Platform — Redis Configuration  
\# Generated by 2-deploy-platform.sh

\# Network  
bind 0.0.0.0  
port 6379  
protected-mode yes  
requirepass ${REDIS\_PASSWORD}

\# Memory  
maxmemory 256mb  
maxmemory-policy allkeys-lru

\# Persistence  
appendonly yes  
appendfsync everysec  
save 900 1  
save 300 10  
save 60 10000

\# Logging  
loglevel notice

\# Security  
rename-command FLUSHDB ""  
rename-command FLUSHALL ""  
rename-command DEBUG ""  
EOF

    log\_info "Redis configuration generated"  
}

### **17.4 LiteLLM Configuration**

generate\_litellm\_config() {  
    log\_info "Generating LiteLLM configuration..."

    cat \> "${CONFIG\_PATH}/litellm/config.yaml" \<\< EOF  
\# AI Platform — LiteLLM Proxy Configuration  
\# Generated by 2-deploy-platform.sh

model\_list:  
EOF

    \# Always add Ollama models  
    cat \>\> "${CONFIG\_PATH}/litellm/config.yaml" \<\< EOF  
  \# \--- Ollama Models (local) \---  
  \- model\_name: llama3.1  
    litellm\_params:  
      model: ollama/llama3.1:8b  
      api\_base: ${OLLAMA\_BASE\_URL}  
      stream: true

  \- model\_name: nomic-embed-text  
    litellm\_params:  
      model: ollama/nomic-embed-text  
      api\_base: ${OLLAMA\_BASE\_URL}  
EOF

    \# Conditional: OpenAI  
    if \[\[ " $ OPENAI\_ENABLED" \== "true" \]\]; then  
        cat \>\> " $ {CONFIG\_PATH}/litellm/config.yaml" \<\< EOF

  \# \--- OpenAI Models \---  
  \- model\_name: gpt-4o  
    litellm\_params:  
      model: openai/gpt-4o  
      api\_key: ${OPENAI\_API\_KEY}

  \- model\_name: gpt-4o-mini  
    litellm\_params:  
      model: openai/gpt-4o-mini  
      api\_key: ${OPENAI\_API\_KEY}

  \- model\_name: text-embedding-3-small  
    litellm\_params:  
      model: openai/text-embedding-3-small  
      api\_key: ${OPENAI\_API\_KEY}  
EOF  
    fi

    \# Conditional: Anthropic  
    if \[\[ " $ ANTHROPIC\_ENABLED" \== "true" \]\]; then  
        cat \>\> " $ {CONFIG\_PATH}/litellm/config.yaml" \<\< EOF

  \# \--- Anthropic Models \---  
  \- model\_name: claude-sonnet-4-20250514  
    litellm\_params:  
      model: anthropic/claude-sonnet-4-20250514  
      api\_key: ${ANTHROPIC\_API\_KEY}

  \- model\_name: claude-3-5-haiku  
    litellm\_params:  
      model: anthropic/claude-3-5-haiku-20241022  
      api\_key: ${ANTHROPIC\_API\_KEY}  
EOF  
    fi

    \# Conditional: Google  
    if \[\[ " $ GOOGLE\_ENABLED" \== "true" \]\]; then  
        cat \>\> " $ {CONFIG\_PATH}/litellm/config.yaml" \<\< EOF

  \# \--- Google AI Models \---  
  \- model\_name: gemini-2.0-flash  
    litellm\_params:  
      model: gemini/gemini-2.0-flash  
      api\_key: ${GOOGLE\_API\_KEY}

  \- model\_name: gemini-2.5-pro  
    litellm\_params:  
      model: gemini/gemini-2.5-pro-preview-06-05  
      api\_key: ${GOOGLE\_API\_KEY}  
EOF  
    fi

    \# General settings  
    cat \>\> "${CONFIG\_PATH}/litellm/config.yaml" \<\< EOF

\# \--- General Settings \---  
litellm\_settings:  
  drop\_params: true  
  set\_verbose: false  
  cache: true  
  cache\_params:  
    type: redis  
    host: ${REDIS\_HOST}  
    port: ${REDIS\_PORT}  
    password: ${REDIS\_PASSWORD}  
  success\_callback: \["prometheus"\]  
  failure\_callback: \["prometheus"\]  
  max\_budget: 100.0  
  budget\_duration: "30d"

general\_settings:  
  master\_key: ${LITELLM\_MASTER\_KEY}  
  database\_url: "postgresql://${LITELLM\_DB\_USER}:${LITELLM\_DB\_PASSWORD}@${POSTGRES\_HOST}:${POSTGRES\_PORT}/${LITELLM\_DB\_NAME}"  
  alerting:  
    \- "webhook"  
  alerting\_threshold: 300  
EOF

    log\_info "LiteLLM configuration generated"  
}

\---

\#\# Section 12: Script 2 — Overview & Structure

\#\#\# 12.1 Purpose

\`2-deploy-platform.sh\` is the primary deployment script. It collects user preferences via an interactive questionnaire, generates ALL configuration files, creates ALL docker-compose files (one per service), then deploys every container.

\#\#\# 12.2 Execution

\`\`\`bash  
sudo bash 2-deploy-platform.sh

### **12.3 Phase Map**

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
    └── Print next-steps (run script 3\)

---

## **Section 13: Phase 1 — Pre-flight Checks**

### **13.1 Preflight Logic**

preflight\_checks() {  
    log\_section "Pre-flight Checks"

    local errors=0

    \# Root check  
    if \[\[  $ EUID \-ne 0 \]\]; then  
        log\_error "This script must be run as root (use sudo)"  
        exit 1  
    fi

    \# Docker  
    if \! docker info &\>/dev/null; then  
        log\_error "Docker is not running. Run 1-setup-system.sh first."  
        errors= $ ((errors \+ 1))  
    else  
        log\_info "✓ Docker is running"  
    fi

    \# Docker Compose  
    if \! docker compose version &\>/dev/null; then  
        log\_error "Docker Compose not available. Run 1-setup-system.sh first."  
        errors= $ ((errors \+ 1))  
    else  
        log\_info "✓ Docker Compose available"  
    fi

    \# Ollama  
    if \! curl \-sf http://localhost:11434/api/tags &\>/dev/null; then  
        log\_error "Ollama is not running. Run 1-setup-system.sh first."  
        errors= $ ((errors \+ 1))  
    else  
        log\_info "✓ Ollama is running"  
    fi

    \# Hardware profile  
    if \[\[ \! \-f "${CONFIG\_PATH}/hardware-profile.env" \]\]; then  
        log\_error "Hardware profile not found. Run 1-setup-system.sh first."  
        errors= $ ((errors \+ 1))  
    else  
        source " $ {CONFIG\_PATH}/hardware-profile.env"  
        log\_info "✓ Hardware profile loaded (tier: ${SYSTEM\_TIER})"  
    fi

    \# Disk space check (need at least 20GB free for images)  
    local free\_gb  
    free\_gb=$(df \-BG /var/lib/docker 2\>/dev/null | tail \-1 | awk '{print  $ 4}' | tr \-d 'G')  
    if \[\[ \-n " $ free\_gb" && " $ free\_gb" \-lt 20 \]\]; then  
        log\_error "Less than 20GB free in /var/lib/docker — need space for images"  
        errors= $ ((errors \+ 1))  
    else  
        log\_info "✓ Disk space OK (${free\_gb}GB free)"  
    fi

    if \[\[ $errors \-gt 0 \]\]; then  
        log\_error "Pre-flight failed with ${errors} error(s)"  
        exit 1  
    fi

    log\_info "All pre-flight checks passed"  
}

---

## **Section 14: Phase 2 — Interactive Questionnaire**

### **14.1 Design Principles**

* Every question has a sensible default (press Enter to accept)  
* Passwords are never displayed on screen (use `read -s`)  
* Input is validated before proceeding  
* All answers stored in variables for later use

### **14.2 Questionnaire Logic**

run\_questionnaire() {  
    log\_section "Platform Configuration"  
    echo ""  
    echo "Answer the following questions to configure your platform."  
    echo "Press Enter to accept \[default\] values."  
    echo ""

    \# \--- Network Configuration \---  
    echo "─── Network Configuration ───"  
    echo ""

    \# Domain or IP  
    local detected\_ip  
    detected\_ip=$(hostname \-I | awk '{print  $ 1}')

    read \-rp "Domain name or IP address \[ $ {detected\_ip}\]: " USER\_DOMAIN  
    USER\_DOMAIN="${USER\_DOMAIN:- $ detected\_ip}"

    \# Determine if domain or IP  
    if \[\[ " $ USER\_DOMAIN" \=\~ ^\[0-9\]+\\.\[0-9\]+\\.\[0-9\]+\\.\[0-9\]+$ \]\]; then  
        DOMAIN\_MODE="ip"  
        DOMAIN\_NAME=" $ USER\_DOMAIN"  
        log\_info "Mode: IP-based access ( $ {DOMAIN\_NAME})"  
    else  
        DOMAIN\_MODE="domain"  
        DOMAIN\_NAME=" $ USER\_DOMAIN"  
        log\_info "Mode: Domain-based access ( $ {DOMAIN\_NAME})"  
    fi

    \# SSL mode  
    echo ""  
    if \[\[ " $ DOMAIN\_MODE" \== "domain" \]\]; then  
        echo "SSL Certificate Mode:"  
        echo "  1\) Automatic (Let's Encrypt via Caddy) — recommended for public domains"  
        echo "  2\) Self-signed — for internal/private domains"  
        echo "  3\) None (HTTP only) — not recommended"  
        read \-rp "SSL mode \[1\]: " ssl\_choice  
        case " $ {ssl\_choice:-1}" in  
            1\) SSL\_MODE="letsencrypt" ;;  
            2\) SSL\_MODE="selfsigned" ;;  
            3\) SSL\_MODE="none" ;;  
            \*) SSL\_MODE="letsencrypt" ;;  
        esac  
    else  
        echo "IP-based access: SSL will use self-signed certificate"  
        SSL\_MODE="selfsigned"  
    fi  
    log\_info "SSL mode: ${SSL\_MODE}"

    \# \--- Admin Configuration \---  
    echo ""  
    echo "─── Admin Configuration ───"  
    echo ""

    read \-rp "Admin email address \[admin@${DOMAIN\_NAME}\]: " ADMIN\_EMAIL  
    ADMIN\_EMAIL="${ADMIN\_EMAIL:-admin@${DOMAIN\_NAME}}"

    echo ""  
    while true; do  
        read \-srp "Admin password (min 12 chars): " ADMIN\_PASSWORD  
        echo ""  
        if \[\[ ${\#ADMIN\_PASSWORD} \-ge 12 \]\]; then  
            read \-srp "Confirm admin password: " ADMIN\_PASSWORD\_CONFIRM  
            echo ""  
            if \[\[ " $ ADMIN\_PASSWORD" \== " $ ADMIN\_PASSWORD\_CONFIRM" \]\]; then  
                break  
            else  
                echo "Passwords do not match. Try again."  
            fi  
        else  
            echo "Password must be at least 12 characters. Try again."  
        fi  
    done  
    log\_info "Admin credentials configured"

    \# \--- LLM Provider API Keys \---  
    echo ""  
    echo "─── LLM Provider API Keys (optional — press Enter to skip) ───"  
    echo ""

    read \-srp "OpenAI API key: " OPENAI\_API\_KEY  
    echo ""  
    OPENAI\_API\_KEY="${OPENAI\_API\_KEY:-}"  
    if \[\[ \-n " $ OPENAI\_API\_KEY" \]\]; then  
        OPENAI\_ENABLED="true"  
        log\_info "OpenAI: configured"  
    else  
        OPENAI\_ENABLED="false"  
        log\_info "OpenAI: skipped"  
    fi

    read \-srp "Anthropic API key: " ANTHROPIC\_API\_KEY  
    echo ""  
    ANTHROPIC\_API\_KEY=" $ {ANTHROPIC\_API\_KEY:-}"  
    if \[\[ \-n " $ ANTHROPIC\_API\_KEY" \]\]; then  
        ANTHROPIC\_ENABLED="true"  
        log\_info "Anthropic: configured"  
    else  
        ANTHROPIC\_ENABLED="false"  
        log\_info "Anthropic: skipped"  
    fi

    read \-srp "Google AI (Gemini) API key: " GOOGLE\_API\_KEY  
    echo ""  
    GOOGLE\_API\_KEY=" $ {GOOGLE\_API\_KEY:-}"  
    if \[\[ \-n " $ GOOGLE\_API\_KEY" \]\]; then  
        GOOGLE\_ENABLED="true"  
        log\_info "Google AI: configured"  
    else  
        GOOGLE\_ENABLED="false"  
        log\_info "Google AI: skipped"  
    fi

    \# \--- Optional Services \---  
    echo ""  
    echo "─── Optional Services ───"  
    echo ""

    read \-rp "Enable Flowise? (visual workflow builder) \[y/N\]: " enable\_flowise  
    FLOWISE\_ENABLED="false"  
    \[\[ " $ {enable\_flowise,,}" \== "y" \]\] && FLOWISE\_ENABLED="true"  
    log\_info "Flowise: ${FLOWISE\_ENABLED}"

    read \-rp "Enable Grafana monitoring? \[Y/n\]: " enable\_grafana  
    GRAFANA\_ENABLED="true"  
    \[\[ "${enable\_grafana,,}" \== "n" \]\] && GRAFANA\_ENABLED="false"  
    log\_info "Grafana: ${GRAFANA\_ENABLED}"

    \# \--- Summary \---  
    echo ""  
    echo "─── Configuration Summary ───"  
    echo ""  
    echo "  Domain/IP:     ${DOMAIN\_NAME} (${DOMAIN\_MODE} mode)"  
    echo "  SSL:           ${SSL\_MODE}"  
    echo "  Admin email:   ${ADMIN\_EMAIL}"  
    echo "  OpenAI:        ${OPENAI\_ENABLED}"  
    echo "  Anthropic:     ${ANTHROPIC\_ENABLED}"  
    echo "  Google AI:     ${GOOGLE\_ENABLED}"  
    echo "  Flowise:       ${FLOWISE\_ENABLED}"  
    echo "  Grafana:       ${GRAFANA\_ENABLED}"  
    echo "  System tier:   ${SYSTEM\_TIER}"  
    echo ""  
    read \-rp "Proceed with this configuration? \[Y/n\]: " confirm  
    if \[\[ "${confirm,,}" \== "n" \]\]; then  
        log\_info "Cancelled by user"  
        exit 0  
    fi  
}

---

## **Section 15: Phase 3 — Credential Generation**

### **15.1 Generation Functions**

generate\_password() {  
    \# Generate a random password of specified length  
    local length="${1:-32}"  
    openssl rand \-base64 48 | tr \-dc 'A-Za-z0-9\!@\# $ %' | head \-c " $ length"  
}

generate\_hex\_key() {  
    \# Generate a hex key (for secret keys)  
    local length="${1:-64}"  
    openssl rand \-hex "$((length / 2))"  
}

generate\_uuid() {  
    cat /proc/sys/kernel/random/uuid  
}

### **15.2 Credential Generation Logic**

generate\_all\_credentials() {  
    log\_section "Generating Credentials"

    \# Database passwords  
    POSTGRES\_PASSWORD= $ (generate\_password 32\)  
    REDIS\_PASSWORD= $ (generate\_password 32\)  
    QDRANT\_API\_KEY= $ (generate\_password 32\)

    \# Service-specific database passwords  
    DIFY\_DB\_PASSWORD= $ (generate\_password 32\)  
    N8N\_DB\_PASSWORD= $ (generate\_password 32\)  
    LITELLM\_DB\_PASSWORD= $ (generate\_password 32\)  
    SUPERTOKENS\_DB\_PASSWORD= $ (generate\_password 32\)  
    FLOWISE\_DB\_PASSWORD= $ (generate\_password 32\)  
    GRAFANA\_DB\_PASSWORD= $ (generate\_password 32\)

    \# Secret keys  
    DIFY\_SECRET\_KEY= $ (generate\_hex\_key 64\)  
    N8N\_ENCRYPTION\_KEY= $ (generate\_hex\_key 64\)  
    LITELLM\_MASTER\_KEY="sk-litellm- $ (generate\_password 32)"  
    LITELLM\_ADMIN\_KEY="sk-admin- $ (generate\_password 32)"  
    FLOWISE\_SECRET\_KEY= $ (generate\_hex\_key 64\)  
    SUPERTOKENS\_API\_KEY= $ (generate\_password 32\)

    \# Dify-specific keys  
    DIFY\_INIT\_PASSWORD= $ (generate\_password 16\)  
    DIFY\_SANDBOX\_KEY= $ (generate\_hex\_key 32\)  
    DIFY\_STORAGE\_KEY= $ (generate\_hex\_key 32\)

    \# Grafana  
    GRAFANA\_ADMIN\_PASSWORD= $ (generate\_password 24\)

    \# Inter-service tokens  
    N8N\_WEBHOOK\_SECRET= $ (generate\_hex\_key 32\)

    log\_info "All credentials generated (${credential\_count} items)"  
}

### **15.3 Credentials File Output**

write\_credentials\_file() {  
    local cred\_file="${CONFIG\_PATH}/credentials.env"

    cat \> "$cred\_file" \<\< EOF  
\# Platform Credentials — Generated by 2-deploy-platform.sh  
\# Generated:  $ (date \-u \+"%Y-%m-%dT%H:%M:%SZ")  
\# WARNING: This file contains sensitive data. Restrict access.

\# \--- Database Passwords \---  
POSTGRES\_PASSWORD= $ {POSTGRES\_PASSWORD}  
REDIS\_PASSWORD=${REDIS\_PASSWORD}  
QDRANT\_API\_KEY=${QDRANT\_API\_KEY}

\# \--- Service Database Passwords \---  
DIFY\_DB\_PASSWORD=${DIFY\_DB\_PASSWORD}  
N8N\_DB\_PASSWORD=${N8N\_DB\_PASSWORD}  
LITELLM\_DB\_PASSWORD=${LITELLM\_DB\_PASSWORD}  
SUPERTOKENS\_DB\_PASSWORD=${SUPERTOKENS\_DB\_PASSWORD}  
FLOWISE\_DB\_PASSWORD=${FLOWISE\_DB\_PASSWORD}  
GRAFANA\_DB\_PASSWORD=${GRAFANA\_DB\_PASSWORD}

\# \--- Secret Keys \---  
DIFY\_SECRET\_KEY=${DIFY\_SECRET\_KEY}  
N8N\_ENCRYPTION\_KEY=${N8N\_ENCRYPTION\_KEY}  
LITELLM\_MASTER\_KEY=${LITELLM\_MASTER\_KEY}  
LITELLM\_ADMIN\_KEY=${LITELLM\_ADMIN\_KEY}  
FLOWISE\_SECRET\_KEY=${FLOWISE\_SECRET\_KEY}  
SUPERTOKENS\_API\_KEY=${SUPERTOKENS\_API\_KEY}

\# \--- Dify-Specific \---  
DIFY\_INIT\_PASSWORD=${DIFY\_INIT\_PASSWORD}  
DIFY\_SANDBOX\_KEY=${DIFY\_SANDBOX\_KEY}  
DIFY\_STORAGE\_KEY=${DIFY\_STORAGE\_KEY}

\# \--- Grafana \---  
GRAFANA\_ADMIN\_PASSWORD=${GRAFANA\_ADMIN\_PASSWORD}

\# \--- Inter-Service Tokens \---  
N8N\_WEBHOOK\_SECRET=${N8N\_WEBHOOK\_SECRET}

\# \--- Admin (user-provided) \---  
ADMIN\_EMAIL=${ADMIN\_EMAIL}  
ADMIN\_PASSWORD=${ADMIN\_PASSWORD}  
EOF

    chmod 600 "$cred\_file"  
    log\_info "Credentials written to ${cred\_file} (mode 600)"  
}

---

## **Section 16: Phase 4 — master.env Generation**

### **16.1 Purpose**

`master.env` is the single source of truth for ALL platform variables. Every docker-compose file, every service config, and every convenience script references this file.

### **16.2 Generation Logic**

generate\_master\_env() {  
    log\_section "Generating master.env"

    local master\_file="${CONFIG\_PATH}/master.env"

    \# Detect host IP  
    HOST\_IP=$(hostname \-I | awk '{print  $ 1}')

    \# Set protocol based on SSL mode  
    if \[\[ " $ SSL\_MODE" \== "none" \]\]; then  
        URL\_PROTOCOL="http"  
    else  
        URL\_PROTOCOL="https"  
    fi

    cat \> "$master\_file" \<\< EOF  
\# ╔══════════════════════════════════════════════════════════╗  
\# ║  AI PLATFORM — MASTER ENVIRONMENT FILE                  ║  
\# ║  Generated:  $ (date \-u \+"%Y-%m-%dT%H:%M:%SZ")                       ║  
\# ║  Do not edit manually — regenerate with Script 2        ║  
\# ╚══════════════════════════════════════════════════════════╝

\# ── Paths ──  
ROOT\_PATH=/mnt/data/ai-platform  
CONFIG\_PATH=/mnt/data/ai-platform/config  
DOCKER\_PATH=/mnt/data/ai-platform/docker  
DATA\_PATH=/mnt/data/ai-platform/data  
LOG\_PATH=/mnt/data/ai-platform/logs  
SCRIPTS\_PATH=/mnt/data/ai-platform/scripts  
BACKUP\_PATH=/mnt/data/ai-platform/backups

\# ── Network ──  
DOMAIN\_MODE= $ {DOMAIN\_MODE}  
DOMAIN\_NAME=${DOMAIN\_NAME}  
HOST\_IP=${HOST\_IP}  
SSL\_MODE=${SSL\_MODE}  
URL\_PROTOCOL=${URL\_PROTOCOL}

\# ── Hardware ──  
SYSTEM\_TIER=${SYSTEM\_TIER}  
GPU\_AVAILABLE=${GPU\_AVAILABLE}  
GPU\_VRAM\_MB=${GPU\_VRAM\_MB}  
CPU\_CORES=${CPU\_CORES}  
TOTAL\_RAM\_GB=${TOTAL\_RAM\_GB}

\# ── Feature Flags ──  
OPENAI\_ENABLED=${OPENAI\_ENABLED}  
ANTHROPIC\_ENABLED=${ANTHROPIC\_ENABLED}  
GOOGLE\_ENABLED=${GOOGLE\_ENABLED}  
FLOWISE\_ENABLED=${FLOWISE\_ENABLED}  
GRAFANA\_ENABLED=${GRAFANA\_ENABLED}

\# ── Admin ──  
ADMIN\_EMAIL=${ADMIN\_EMAIL}  
ADMIN\_PASSWORD=${ADMIN\_PASSWORD}

\# ── Provider API Keys ──  
OPENAI\_API\_KEY=${OPENAI\_API\_KEY:-}  
ANTHROPIC\_API\_KEY=${ANTHROPIC\_API\_KEY:-}  
GOOGLE\_API\_KEY=${GOOGLE\_API\_KEY:-}

\# ── PostgreSQL ──  
POSTGRES\_HOST=postgres  
POSTGRES\_PORT=5432  
POSTGRES\_USER=postgres  
POSTGRES\_PASSWORD=${POSTGRES\_PASSWORD}  
POSTGRES\_SHARED\_DB=ai\_platform

\# Service-specific database names  
DIFY\_DB\_NAME=dify  
DIFY\_DB\_USER=dify  
DIFY\_DB\_PASSWORD=${DIFY\_DB\_PASSWORD}

N8N\_DB\_NAME=n8n  
N8N\_DB\_USER=n8n  
N8N\_DB\_PASSWORD=${N8N\_DB\_PASSWORD}

LITELLM\_DB\_NAME=litellm  
LITELLM\_DB\_USER=litellm  
LITELLM\_DB\_PASSWORD=${LITELLM\_DB\_PASSWORD}

SUPERTOKENS\_DB\_NAME=supertokens  
SUPERTOKENS\_DB\_USER=supertokens  
SUPERTOKENS\_DB\_PASSWORD=${SUPERTOKENS\_DB\_PASSWORD}

FLOWISE\_DB\_NAME=flowise  
FLOWISE\_DB\_USER=flowise  
FLOWISE\_DB\_PASSWORD=${FLOWISE\_DB\_PASSWORD}

GRAFANA\_DB\_NAME=grafana  
GRAFANA\_DB\_USER=grafana  
GRAFANA\_DB\_PASSWORD=${GRAFANA\_DB\_PASSWORD}

\# ── Redis ──  
REDIS\_HOST=redis  
REDIS\_PORT=6379  
REDIS\_PASSWORD=${REDIS\_PASSWORD}

\# ── Qdrant ──  
QDRANT\_HOST=qdrant  
QDRANT\_PORT=6333  
QDRANT\_GRPC\_PORT=6334  
QDRANT\_API\_KEY=${QDRANT\_API\_KEY}

\# ── SuperTokens ──  
SUPERTOKENS\_HOST=supertokens  
SUPERTOKENS\_PORT=3567  
SUPERTOKENS\_API\_KEY=${SUPERTOKENS\_API\_KEY}

\# ── Ollama ──  
OLLAMA\_HOST=${HOST\_IP}  
OLLAMA\_PORT=11434  
OLLAMA\_BASE\_URL=http://${HOST\_IP}:11434

\# ── LiteLLM ──  
LITELLM\_HOST=litellm  
LITELLM\_PORT=4000  
LITELLM\_MASTER\_KEY=${LITELLM\_MASTER\_KEY}  
LITELLM\_ADMIN\_KEY=${LITELLM\_ADMIN\_KEY}  
LITELLM\_BASE\_URL=http://litellm:4000

\# ── Dify ──  
DIFY\_API\_HOST=dify-api  
DIFY\_API\_PORT=5001  
DIFY\_WEB\_HOST=dify-web  
DIFY\_WEB\_PORT=3000  
DIFY\_SECRET\_KEY=${DIFY\_SECRET\_KEY}  
DIFY\_INIT\_PASSWORD=${DIFY\_INIT\_PASSWORD}  
DIFY\_SANDBOX\_KEY=${DIFY\_SANDBOX\_KEY}  
DIFY\_STORAGE\_KEY=${DIFY\_STORAGE\_KEY}

\# ── n8n ──  
N8N\_HOST=n8n  
N8N\_PORT=5678  
N8N\_ENCRYPTION\_KEY=${N8N\_ENCRYPTION\_KEY}  
N8N\_WEBHOOK\_SECRET=${N8N\_WEBHOOK\_SECRET}  
N8N\_EXTERNAL\_URL=${URL\_PROTOCOL}://${DOMAIN\_NAME}:5678

\# ── Open WebUI ──  
OPEN\_WEBUI\_HOST=open-webui  
OPEN\_WEBUI\_PORT=3001

\# ── Flowise ──  
FLOWISE\_HOST=flowise  
FLOWISE\_PORT=3002  
FLOWISE\_SECRET\_KEY=${FLOWISE\_SECRET\_KEY}

\# ── Caddy ──  
CADDY\_HTTP\_PORT=80  
CADDY\_HTTPS\_PORT=443

\# ── Prometheus ──  
PROMETHEUS\_HOST=prometheus  
PROMETHEUS\_PORT=9090

\# ── Grafana ──  
GRAFANA\_HOST=grafana  
GRAFANA\_PORT=3003  
GRAFANA\_ADMIN\_PASSWORD=${GRAFANA\_ADMIN\_PASSWORD}

\# ── Docker Networks ──  
NETWORK\_FRONTEND=ai-platform  
NETWORK\_BACKEND=ai-backend

\# ── Container Image Versions ──  
POSTGRES\_IMAGE=postgres:16-alpine  
REDIS\_IMAGE=redis:7-alpine  
QDRANT\_IMAGE=qdrant/qdrant:v1.7.4  
SUPERTOKENS\_IMAGE=registry.supertokens.io/supertokens/supertokens-postgresql:9.0  
LITELLM\_IMAGE=ghcr.io/berriai/litellm:main-latest  
DIFY\_API\_IMAGE=langgenius/dify-api:0.15.3  
DIFY\_WEB\_IMAGE=langgenius/dify-web:0.15.3  
DIFY\_SANDBOX\_IMAGE=langgenius/dify-sandbox:0.2.10  
N8N\_IMAGE=docker.n8n.io/n8nio/n8n:latest  
OPEN\_WEBUI\_IMAGE=ghcr.io/open-webui/open-webui:main  
FLOWISE\_IMAGE=flowiseai/flowise:latest  
CADDY\_IMAGE=caddy:2-alpine  
PROMETHEUS\_IMAGE=prom/prometheus:v2.48.0  
GRAFANA\_IMAGE=grafana/grafana:10.2.0  
EOF

    chmod 600 "$master\_file"  
    log\_info "master.env written to ${master\_file} (mode 600)"  
}

---

## **Section 17: Phase 4 — Service Environment Files**

### **17.1 Purpose**

Each service gets its own `.env` file containing only the variables it needs. These are referenced by the per-service docker-compose files.

### **17.2 PostgreSQL Init SQL**

generate\_postgres\_init() {  
    log\_info "Generating PostgreSQL init script..."

    cat \> "${CONFIG\_PATH}/postgres/init-databases.sql" \<\< EOF  
\-- AI Platform — PostgreSQL Database Initialization  
\-- Generated by 2-deploy-platform.sh

\-- Create service roles and databases

\-- Dify  
CREATE USER ${DIFY\_DB\_USER} WITH PASSWORD '${DIFY\_DB\_PASSWORD}';  
CREATE DATABASE ${DIFY\_DB\_NAME} OWNER ${DIFY\_DB\_USER};  
GRANT ALL PRIVILEGES ON DATABASE ${DIFY\_DB\_NAME} TO ${DIFY\_DB\_USER};

\-- n8n  
CREATE USER ${N8N\_DB\_USER} WITH PASSWORD '${N8N\_DB\_PASSWORD}';  
CREATE DATABASE ${N8N\_DB\_NAME} OWNER ${N8N\_DB\_USER};  
GRANT ALL PRIVILEGES ON DATABASE ${N8N\_DB\_NAME} TO ${N8N\_DB\_USER};

\-- LiteLLM  
CREATE USER ${LITELLM\_DB\_USER} WITH PASSWORD '${LITELLM\_DB\_PASSWORD}';  
CREATE DATABASE ${LITELLM\_DB\_NAME} OWNER ${LITELLM\_DB\_USER};  
GRANT ALL PRIVILEGES ON DATABASE ${LITELLM\_DB\_NAME} TO ${LITELLM\_DB\_USER};

\-- SuperTokens  
CREATE USER ${SUPERTOKENS\_DB\_USER} WITH PASSWORD '${SUPERTOKENS\_DB\_PASSWORD}';  
CREATE DATABASE ${SUPERTOKENS\_DB\_NAME} OWNER ${SUPERTOKENS\_DB\_USER};  
GRANT ALL PRIVILEGES ON DATABASE ${SUPERTOKENS\_DB\_NAME} TO ${SUPERTOKENS\_DB\_USER};

\-- Flowise (conditional — always create, service may not be deployed)  
CREATE USER ${FLOWISE\_DB\_USER} WITH PASSWORD '${FLOWISE\_DB\_PASSWORD}';  
CREATE DATABASE ${FLOWISE\_DB\_NAME} OWNER ${FLOWISE\_DB\_USER};  
GRANT ALL PRIVILEGES ON DATABASE ${FLOWISE\_DB\_NAME} TO ${FLOWISE\_DB\_USER};

\-- Grafana  
CREATE USER ${GRAFANA\_DB\_USER} WITH PASSWORD '${GRAFANA\_DB\_PASSWORD}';  
CREATE DATABASE ${GRAFANA\_DB\_NAME} OWNER ${GRAFANA\_DB\_USER};  
GRANT ALL PRIVILEGES ON DATABASE ${GRAFANA\_DB\_NAME} TO ${GRAFANA\_DB\_USER};

\-- Grant schema permissions (required for some services)  
\\c ${DIFY\_DB\_NAME}  
GRANT ALL ON SCHEMA public TO ${DIFY\_DB\_USER};

\\c ${N8N\_DB\_NAME}  
GRANT ALL ON SCHEMA public TO ${N8N\_DB\_USER};

\\c ${LITELLM\_DB\_NAME}  
GRANT ALL ON SCHEMA public TO ${LITELLM\_DB\_USER};

\\c ${SUPERTOKENS\_DB\_NAME}  
GRANT ALL ON SCHEMA public TO ${SUPERTOKENS\_DB\_USER};

\\c ${FLOWISE\_DB\_NAME}  
GRANT ALL ON SCHEMA public TO ${FLOWISE\_DB\_USER};

\\c ${GRAFANA\_DB\_NAME}  
GRANT ALL ON SCHEMA public TO ${GRAFANA\_DB\_USER};  
EOF

    log\_info "PostgreSQL init script generated"  
}

### **17.3 Redis Configuration**

generate\_redis\_config() {  
    log\_info "Generating Redis configuration..."

    cat \> "${CONFIG\_PATH}/redis/redis.conf" \<\< EOF  
\# AI Platform — Redis Configuration  
\# Generated by 2-deploy-platform.sh

\# Network  
bind 0.0.0.0  
port 6379  
protected-mode yes  
requirepass ${REDIS\_PASSWORD}

\# Memory  
maxmemory 256mb  
maxmemory-policy allkeys-lru

\# Persistence  
appendonly yes  
appendfsync everysec  
save 900 1  
save 300 10  
save 60 10000

\# Logging  
loglevel notice

\# Security  
rename-command FLUSHDB ""  
rename-command FLUSHALL ""  
rename-command DEBUG ""  
EOF

    log\_info "Redis configuration generated"  
}

### **17.4 LiteLLM Configuration**

generate\_litellm\_config() {  
    log\_info "Generating LiteLLM configuration..."

    cat \> "${CONFIG\_PATH}/litellm/config.yaml" \<\< EOF  
\# AI Platform — LiteLLM Proxy Configuration  
\# Generated by 2-deploy-platform.sh

model\_list:  
EOF

    \# Always add Ollama models  
    cat \>\> "${CONFIG\_PATH}/litellm/config.yaml" \<\< EOF  
  \# \--- Ollama Models (local) \---  
  \- model\_name: llama3.1  
    litellm\_params:  
      model: ollama/llama3.1:8b  
      api\_base: ${OLLAMA\_BASE\_URL}  
      stream: true

  \- model\_name: nomic-embed-text  
    litellm\_params:  
      model: ollama/nomic-embed-text  
      api\_base: ${OLLAMA\_BASE\_URL}  
EOF

    \# Conditional: OpenAI  
    if \[\[ " $ OPENAI\_ENABLED" \== "true" \]\]; then  
        cat \>\> " $ {CONFIG\_PATH}/litellm/config.yaml" \<\< EOF

  \# \--- OpenAI Models \---  
  \- model\_name: gpt-4o  
    litellm\_params:  
      model: openai/gpt-4o  
      api\_key: ${OPENAI\_API\_KEY}

  \- model\_name: gpt-4o-mini  
    litellm\_params:  
      model: openai/gpt-4o-mini  
      api\_key: ${OPENAI\_API\_KEY}

  \- model\_name: text-embedding-3-small  
    litellm\_params:  
      model: openai/text-embedding-3-small  
      api\_key: ${OPENAI\_API\_KEY}  
EOF  
    fi

    \# Conditional: Anthropic  
    if \[\[ " $ ANTHROPIC\_ENABLED" \== "true" \]\]; then  
        cat \>\> " $ {CONFIG\_PATH}/litellm/config.yaml" \<\< EOF

  \# \--- Anthropic Models \---  
  \- model\_name: claude-sonnet-4-20250514  
    litellm\_params:  
      model: anthropic/claude-sonnet-4-20250514  
      api\_key: ${ANTHROPIC\_API\_KEY}

  \- model\_name: claude-3-5-haiku  
    litellm\_params:  
      model: anthropic/claude-3-5-haiku-20241022  
      api\_key: ${ANTHROPIC\_API\_KEY}  
EOF  
    fi

    \# Conditional: Google  
    if \[\[ " $ GOOGLE\_ENABLED" \== "true" \]\]; then  
        cat \>\> " $ {CONFIG\_PATH}/litellm/config.yaml" \<\< EOF

  \# \--- Google AI Models \---  
  \- model\_name: gemini-2.0-flash  
    litellm\_params:  
      model: gemini/gemini-2.0-flash  
      api\_key: ${GOOGLE\_API\_KEY}

  \- model\_name: gemini-2.5-pro  
    litellm\_params:  
      model: gemini/gemini-2.5-pro-preview-06-05  
      api\_key: ${GOOGLE\_API\_KEY}  
EOF  
    fi

    \# General settings  
    cat \>\> "${CONFIG\_PATH}/litellm/config.yaml" \<\< EOF

\# \--- General Settings \---  
litellm\_settings:  
  drop\_params: true  
  set\_verbose: false  
  cache: true  
  cache\_params:  
    type: redis  
    host: ${REDIS\_HOST}  
    port: ${REDIS\_PORT}  
    password: ${REDIS\_PASSWORD}  
  success\_callback: \["prometheus"\]  
  failure\_callback: \["prometheus"\]  
  max\_budget: 100.0  
  budget\_duration: "30d"

general\_settings:  
  master\_key: ${LITELLM\_MASTER\_KEY}  
  database\_url: "postgresql://${LITELLM\_DB\_USER}:${LITELLM\_DB\_PASSWORD}@${POSTGRES\_HOST}:${POSTGRES\_PORT}/${LITELLM\_DB\_NAME}"  
  alerting:  
    \- "webhook"  
  alerting\_threshold: 300  
EOF

    log\_info "LiteLLM configuration generated"  
}

\---

\#\# Section 18: Phase 4 — Caddyfile Generation

\#\#\# 18.1 Purpose

Caddy serves as the reverse proxy / TLS termination layer. The Caddyfile routes traffic to each service based on port or path.

\#\#\# 18.2 IP-Based Caddyfile (port routing)

When running in IP mode, each service gets its own port on the host.

\`\`\`bash  
generate\_caddyfile() {  
    log\_info "Generating Caddyfile..."

    mkdir \-p "${CONFIG\_PATH}/caddy"

    if \[\[ " $ DOMAIN\_MODE" \== "ip" \]\]; then  
        generate\_caddyfile\_ip  
    else  
        generate\_caddyfile\_domain  
    fi

    log\_info "Caddyfile generated"  
}

generate\_caddyfile\_ip() {  
    cat \> " $ {CONFIG\_PATH}/caddy/Caddyfile" \<\< 'CADDYEOF'  
\# AI Platform — Caddyfile (IP mode)  
\# Generated by 2-deploy-platform.sh  
\# Each service on its own port with self-signed TLS

{  
    auto\_https disable\_redirects  
    admin off  
    log {  
        level INFO  
        output file /data/logs/caddy.log {  
            roll\_size 10mb  
            roll\_keep 5  
        }  
    }  
}

CADDYEOF

    \# Dify Web — port 443 (main entry)  
    cat \>\> "${CONFIG\_PATH}/caddy/Caddyfile" \<\< EOF  
:443 {  
    tls internal  
    reverse\_proxy dify-web:3000  
    handle\_path /api/\* {  
        reverse\_proxy dify-api:5001  
    }  
    handle\_path /console/api/\* {  
        reverse\_proxy dify-api:5001  
    }  
    handle\_path /v1/\* {  
        reverse\_proxy dify-api:5001  
    }  
    handle\_path /files/\* {  
        reverse\_proxy dify-api:5001  
    }  
}

\# n8n — port 5678  
:5678 {  
    tls internal  
    reverse\_proxy n8n:5678  
}

\# Open WebUI — port 3001  
:3001 {  
    tls internal  
    reverse\_proxy open-webui:8080  
}

\# LiteLLM — port 4000  
:4000 {  
    tls internal  
    reverse\_proxy litellm:4000  
}  
EOF

    \# Conditional: Flowise  
    if \[\[ " $ FLOWISE\_ENABLED" \== "true" \]\]; then  
        cat \>\> " $ {CONFIG\_PATH}/caddy/Caddyfile" \<\< EOF

\# Flowise — port 3002  
:3002 {  
    tls internal  
    reverse\_proxy flowise:3000  
}  
EOF  
    fi

    \# Conditional: Grafana  
    if \[\[ " $ GRAFANA\_ENABLED" \== "true" \]\]; then  
        cat \>\> " $ {CONFIG\_PATH}/caddy/Caddyfile" \<\< EOF

\# Grafana — port 3003  
:3003 {  
    tls internal  
    reverse\_proxy grafana:3000  
}  
EOF  
    fi  
}

### **18.3 Domain-Based Caddyfile (subdomain routing)**

generate\_caddyfile\_domain() {  
    local tls\_directive  
    if \[\[ "$SSL\_MODE" \== "letsencrypt" \]\]; then  
        tls\_directive="tls ${ADMIN\_EMAIL}"  
    elif \[\[ " $ SSL\_MODE" \== "selfsigned" \]\]; then  
        tls\_directive="tls internal"  
    else  
        tls\_directive=""  
    fi

    cat \> " $ {CONFIG\_PATH}/caddy/Caddyfile" \<\< EOF  
\# AI Platform — Caddyfile (Domain mode)  
\# Generated by 2-deploy-platform.sh

{  
    email ${ADMIN\_EMAIL}  
    log {  
        level INFO  
        output file /data/logs/caddy.log {  
            roll\_size 10mb  
            roll\_keep 5  
        }  
    }  
}

\# Dify — main domain  
${DOMAIN\_NAME} {  
    ${tls\_directive}  
    reverse\_proxy dify-web:3000

    handle\_path /api/\* {  
        reverse\_proxy dify-api:5001  
    }  
    handle\_path /console/api/\* {  
        reverse\_proxy dify-api:5001  
    }  
    handle\_path /v1/\* {  
        reverse\_proxy dify-api:5001  
    }  
    handle\_path /files/\* {  
        reverse\_proxy dify-api:5001  
    }  
}

\# n8n  
n8n.${DOMAIN\_NAME} {  
    ${tls\_directive}  
    reverse\_proxy n8n:5678  
}

\# Open WebUI  
chat.${DOMAIN\_NAME} {  
    ${tls\_directive}  
    reverse\_proxy open-webui:8080  
}

\# LiteLLM  
llm.${DOMAIN\_NAME} {  
    ${tls\_directive}  
    reverse\_proxy litellm:4000  
}  
EOF

    if \[\[ " $ FLOWISE\_ENABLED" \== "true" \]\]; then  
        cat \>\> " $ {CONFIG\_PATH}/caddy/Caddyfile" \<\< EOF

\# Flowise  
flow.${DOMAIN\_NAME} {  
    ${tls\_directive}  
    reverse\_proxy flowise:3000  
}  
EOF  
    fi

    if \[\[ " $ GRAFANA\_ENABLED" \== "true" \]\]; then  
        cat \>\> " $ {CONFIG\_PATH}/caddy/Caddyfile" \<\< EOF

\# Grafana  
grafana.${DOMAIN\_NAME} {  
    ${tls\_directive}  
    reverse\_proxy grafana:3000  
}  
EOF  
    fi  
}

---

## **Section 19: Phase 4 — Prometheus & Grafana Configuration**

### **19.1 Prometheus Configuration**

generate\_prometheus\_config() {  
    log\_info "Generating Prometheus configuration..."

    mkdir \-p "${CONFIG\_PATH}/prometheus"

    cat \> "${CONFIG\_PATH}/prometheus/prometheus.yml" \<\< EOF  
\# AI Platform — Prometheus Configuration  
\# Generated by 2-deploy-platform.sh

global:  
  scrape\_interval: 15s  
  evaluation\_interval: 15s  
  scrape\_timeout: 10s

scrape\_configs:  
  \- job\_name: 'prometheus'  
    static\_configs:  
      \- targets: \['localhost:9090'\]

  \- job\_name: 'litellm'  
    static\_configs:  
      \- targets: \['litellm:4000'\]  
    metrics\_path: /metrics

  \- job\_name: 'caddy'  
    static\_configs:  
      \- targets: \['caddy:2019'\]  
    metrics\_path: /metrics

  \- job\_name: 'docker'  
    static\_configs:  
      \- targets: \['${HOST\_IP}:9323'\]

  \- job\_name: 'node'  
    static\_configs:  
      \- targets: \['${HOST\_IP}:9100'\]  
EOF

    log\_info "Prometheus configuration generated"  
}

### **19.2 Grafana Provisioning**

generate\_grafana\_provisioning() {  
    log\_info "Generating Grafana provisioning..."

    mkdir \-p "${CONFIG\_PATH}/grafana/provisioning/datasources"  
    mkdir \-p "${CONFIG\_PATH}/grafana/provisioning/dashboards"  
    mkdir \-p "${CONFIG\_PATH}/grafana/dashboards"

    \# Datasource provisioning  
    cat \> "${CONFIG\_PATH}/grafana/provisioning/datasources/prometheus.yml" \<\< EOF  
apiVersion: 1

datasources:  
  \- name: Prometheus  
    type: prometheus  
    access: proxy  
    url: http://prometheus:9090  
    isDefault: true  
    editable: true  
EOF

    \# Dashboard provisioning config  
    cat \> "${CONFIG\_PATH}/grafana/provisioning/dashboards/default.yml" \<\< EOF  
apiVersion: 1

providers:  
  \- name: 'default'  
    orgId: 1  
    folder: 'AI Platform'  
    type: file  
    disableDeletion: false  
    editable: true  
    options:  
      path: /var/lib/grafana/dashboards  
      foldersFromFilesStructure: false  
EOF

    log\_info "Grafana provisioning generated"  
}

---

## **Section 20: Phase 5 — Docker Compose Files (Infrastructure Tier)**

### **20.1 Design Principles**

* **One file per service** — enables individual restart/update  
* **All files** reference the same external networks  
* **Environment variables** inline (not via env\_file) to avoid path issues  
* **Health checks** on every service  
* **Named volumes** with consistent naming: `ai-platform-<service>-data`  
* **Resource limits** based on `SYSTEM_TIER`

### **20.2 Network Creation**

create\_docker\_networks() {  
    log\_section "Creating Docker Networks"

    \# Frontend network (services \+ Caddy)  
    if \! docker network inspect ai-platform &\>/dev/null; then  
        docker network create ai-platform  
        log\_info "Created network: ai-platform"  
    else  
        log\_info "Network ai-platform already exists"  
    fi

    \# Backend network (infrastructure only)  
    if \! docker network inspect ai-backend &\>/dev/null; then  
        docker network create ai-backend  
        log\_info "Created network: ai-backend"  
    else  
        log\_info "Network ai-backend already exists"  
    fi  
}

### **20.3 Docker Compose — PostgreSQL**

generate\_compose\_postgres() {  
    log\_info "Generating docker-compose.postgres.yml..."

    cat \> "${DOCKER\_PATH}/docker-compose.postgres.yml" \<\< EOF  
\# AI Platform — PostgreSQL  
\# Generated by 2-deploy-platform.sh

services:  
  postgres:  
    image: ${POSTGRES\_IMAGE}  
    container\_name: ai-platform-postgres  
    restart: unless-stopped  
    environment:  
      POSTGRES\_USER: ${POSTGRES\_USER}  
      POSTGRES\_PASSWORD: ${POSTGRES\_PASSWORD}  
      POSTGRES\_DB: ${POSTGRES\_SHARED\_DB}  
      PGDATA: /var/lib/postgresql/data/pgdata  
    volumes:  
      \- ai-platform-postgres-data:/var/lib/postgresql/data  
      \- ${CONFIG\_PATH}/postgres/init-databases.sql:/docker-entrypoint-initdb.d/init-databases.sql:ro  
    networks:  
      \- ai-backend  
    ports:  
      \- "127.0.0.1:5432:5432"  
    healthcheck:  
      test: \["CMD-SHELL", "pg\_isready \-U ${POSTGRES\_USER}"\]  
      interval: 10s  
      timeout: 5s  
      retries: 5  
      start\_period: 30s  
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

    log\_info "docker-compose.postgres.yml generated"  
}

### **20.4 Docker Compose — Redis**

generate\_compose\_redis() {  
    log\_info "Generating docker-compose.redis.yml..."

    cat \> "${DOCKER\_PATH}/docker-compose.redis.yml" \<\< EOF  
\# AI Platform — Redis  
\# Generated by 2-deploy-platform.sh

services:  
  redis:  
    image: ${REDIS\_IMAGE}  
    container\_name: ai-platform-redis  
    restart: unless-stopped  
    command: redis-server /usr/local/etc/redis/redis.conf  
    volumes:  
      \- ai-platform-redis-data:/data  
      \- ${CONFIG\_PATH}/redis/redis.conf:/usr/local/etc/redis/redis.conf:ro  
    networks:  
      \- ai-backend  
    ports:  
      \- "127.0.0.1:6379:6379"  
    healthcheck:  
      test: \["CMD", "redis-cli", "-a", "${REDIS\_PASSWORD}", "ping"\]  
      interval: 10s  
      timeout: 5s  
      retries: 5  
      start\_period: 10s  
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

    log\_info "docker-compose.redis.yml generated"  
}

### **20.5 Docker Compose — Qdrant**

generate\_compose\_qdrant() {  
    log\_info "Generating docker-compose.qdrant.yml..."

    cat \> "${DOCKER\_PATH}/docker-compose.qdrant.yml" \<\< EOF  
\# AI Platform — Qdrant Vector Database  
\# Generated by 2-deploy-platform.sh

services:  
  qdrant:  
    image: ${QDRANT\_IMAGE}  
    container\_name: ai-platform-qdrant  
    restart: unless-stopped  
    environment:  
      QDRANT\_\_SERVICE\_\_API\_KEY: ${QDRANT\_API\_KEY}  
      QDRANT\_\_SERVICE\_\_GRPC\_PORT: 6334  
    volumes:  
      \- ai-platform-qdrant-data:/qdrant/storage  
    networks:  
      \- ai-backend  
    ports:  
      \- "127.0.0.1:6333:6333"  
      \- "127.0.0.1:6334:6334"  
    healthcheck:  
      test: \["CMD-SHELL", "curl \-sf http://localhost:6333/healthz || exit 1"\]  
      interval: 10s  
      timeout: 5s  
      retries: 5  
      start\_period: 15s  
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

    log\_info "docker-compose.qdrant.yml generated"  
}

### **20.6 Docker Compose — SuperTokens**

generate\_compose\_supertokens() {  
    log\_info "Generating docker-compose.supertokens.yml..."

    cat \> "${DOCKER\_PATH}/docker-compose.supertokens.yml" \<\< EOF  
\# AI Platform — SuperTokens Authentication  
\# Generated by 2-deploy-platform.sh

services:  
  supertokens:  
    image: ${SUPERTOKENS\_IMAGE}  
    container\_name: ai-platform-supertokens  
    restart: unless-stopped  
    environment:  
      POSTGRESQL\_CONNECTION\_URI: "postgresql://${SUPERTOKENS\_DB\_USER}:${SUPERTOKENS\_DB\_PASSWORD}@postgres:5432/${SUPERTOKENS\_DB\_NAME}"  
      API\_KEYS: ${SUPERTOKENS\_API\_KEY}  
    networks:  
      \- ai-backend  
    ports:  
      \- "127.0.0.1:3567:3567"  
    healthcheck:  
      test: \["CMD-SHELL", "curl \-sf http://localhost:3567/hello || exit 1"\]  
      interval: 10s  
      timeout: 5s  
      retries: 5  
      start\_period: 30s  
    depends\_on:  
      postgres:  
        condition: service\_healthy  
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

    log\_info "docker-compose.supertokens.yml generated"  
}

---

## **Section 21: Phase 5 — Docker Compose Files (AI Tier)**

### **21.1 Docker Compose — LiteLLM**

generate\_compose\_litellm() {  
    log\_info "Generating docker-compose.litellm.yml..."

    cat \> "${DOCKER\_PATH}/docker-compose.litellm.yml" \<\< EOF  
\# AI Platform — LiteLLM Proxy  
\# Generated by 2-deploy-platform.sh

services:  
  litellm:  
    image: ${LITELLM\_IMAGE}  
    container\_name: ai-platform-litellm  
    restart: unless-stopped  
    command: \--config /app/config.yaml \--port 4000  
    environment:  
      LITELLM\_MASTER\_KEY: ${LITELLM\_MASTER\_KEY}  
      LITELLM\_ADMIN\_KEY: ${LITELLM\_ADMIN\_KEY}  
      DATABASE\_URL: "postgresql://${LITELLM\_DB\_USER}:${LITELLM\_DB\_PASSWORD}@postgres:5432/${LITELLM\_DB\_NAME}"  
      REDIS\_HOST: ${REDIS\_HOST}  
      REDIS\_PORT: ${REDIS\_PORT}  
      REDIS\_PASSWORD: ${REDIS\_PASSWORD}  
      STORE\_MODEL\_IN\_DB: "True"  
    volumes:  
      \- ${CONFIG\_PATH}/litellm/config.yaml:/app/config.yaml:ro  
    networks:  
      \- ai-platform  
      \- ai-backend  
    ports:  
      \- "127.0.0.1:4000:4000"  
    healthcheck:  
      test: \["CMD-SHELL", "curl \-sf http://localhost:4000/health/liveliness || exit 1"\]  
      interval: 15s  
      timeout: 10s  
      retries: 5  
      start\_period: 45s  
    extra\_hosts:  
      \- "host.docker.internal:host-gateway"  
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

    log\_info "docker-compose.litellm.yml generated"  
}

### **21.2 Docker Compose — Dify API**

generate\_compose\_dify\_api() {  
    log\_info "Generating docker-compose.dify-api.yml..."

    cat \> "${DOCKER\_PATH}/docker-compose.dify-api.yml" \<\< EOF  
\# AI Platform — Dify API Server  
\# Generated by 2-deploy-platform.sh

services:  
  dify-api:  
    image: ${DIFY\_API\_IMAGE}  
    container\_name: ai-platform-dify-api  
    restart: unless-stopped  
    environment:  
      MODE: api  
      LOG\_LEVEL: INFO  
      SECRET\_KEY: ${DIFY\_SECRET\_KEY}  
      INIT\_PASSWORD: ${DIFY\_INIT\_PASSWORD}  
      CONSOLE\_WEB\_URL: ${URL\_PROTOCOL}://${DOMAIN\_NAME}  
      CONSOLE\_API\_URL: ${URL\_PROTOCOL}://${DOMAIN\_NAME}  
      SERVICE\_API\_URL: ${URL\_PROTOCOL}://${DOMAIN\_NAME}  
      APP\_WEB\_URL: ${URL\_PROTOCOL}://${DOMAIN\_NAME}  
      FILES\_URL: ""  
      FILES\_ACCESS\_TIMEOUT: 300

      \# Database  
      DB\_USERNAME: ${DIFY\_DB\_USER}  
      DB\_PASSWORD: ${DIFY\_DB\_PASSWORD}  
      DB\_HOST: ${POSTGRES\_HOST}  
      DB\_PORT: ${POSTGRES\_PORT}  
      DB\_DATABASE: ${DIFY\_DB\_NAME}

      \# Redis  
      REDIS\_HOST: ${REDIS\_HOST}  
      REDIS\_PORT: ${REDIS\_PORT}  
      REDIS\_PASSWORD: ${REDIS\_PASSWORD}  
      REDIS\_DB: 0  
      REDIS\_USE\_SSL: "false"

      \# Celery (uses Redis)  
      CELERY\_BROKER\_URL: "redis://:${REDIS\_PASSWORD}@${REDIS\_HOST}:${REDIS\_PORT}/1"

      \# Vector Store  
      VECTOR\_STORE: qdrant  
      QDRANT\_URL: http://${QDRANT\_HOST}:${QDRANT\_PORT}  
      QDRANT\_API\_KEY: ${QDRANT\_API\_KEY}  
      QDRANT\_CLIENT\_TIMEOUT: 20

      \# Storage  
      STORAGE\_TYPE: local  
      STORAGE\_LOCAL\_PATH: /app/api/storage

      \# Sandbox  
      CODE\_EXECUTION\_ENDPOINT: http://dify-sandbox:8194  
      CODE\_EXECUTION\_API\_KEY: ${DIFY\_SANDBOX\_KEY}  
      CODE\_MAX\_NUMBER: 9223372036854775807  
      CODE\_MIN\_NUMBER: \-9223372036854775808  
      CODE\_MAX\_DEPTH: 5  
      CODE\_MAX\_PRECISION: 20  
      CODE\_MAX\_STRING\_LENGTH: 80000  
      CODE\_MAX\_STRING\_ARRAY\_LENGTH: 30  
      CODE\_MAX\_OBJECT\_ARRAY\_LENGTH: 30  
      CODE\_MAX\_NUMBER\_ARRAY\_LENGTH: 1000

      \# Mail (disabled by default)  
      MAIL\_TYPE: ""  
      MAIL\_DEFAULT\_SEND\_FROM: ""

      \# Sentry (disabled)  
      SENTRY\_DSN: ""

    volumes:  
      \- ai-platform-dify-storage:/app/api/storage  
    networks:  
      \- ai-platform  
      \- ai-backend  
    ports:  
      \- "127.0.0.1:5001:5001"  
    healthcheck:  
      test: \["CMD-SHELL", "curl \-sf http://localhost:5001/health || exit 1"\]  
      interval: 15s  
      timeout: 10s  
      retries: 5  
      start\_period: 60s  
    extra\_hosts:  
      \- "host.docker.internal:host-gateway"  
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

    log\_info "docker-compose.dify-api.yml generated"  
}

### **21.3 Docker Compose — Dify Worker**

generate\_compose\_dify\_worker() {  
    log\_info "Generating docker-compose.dify-worker.yml..."

    cat \> "${DOCKER\_PATH}/docker-compose.dify-worker.yml" \<\< EOF  
\# AI Platform — Dify Worker (Celery)  
\# Generated by 2-deploy-platform.sh

services:  
  dify-worker:  
    image: ${DIFY\_API\_IMAGE}  
    container\_name: ai-platform-dify-worker  
    restart: unless-stopped  
    environment:  
      MODE: worker  
      LOG\_LEVEL: INFO  
      SECRET\_KEY: ${DIFY\_SECRET\_KEY}

      \# Database  
      DB\_USERNAME: ${DIFY\_DB\_USER}  
      DB\_PASSWORD: ${DIFY\_DB\_PASSWORD}  
      DB\_HOST: ${POSTGRES\_HOST}  
      DB\_PORT: ${POSTGRES\_PORT}  
      DB\_DATABASE: ${DIFY\_DB\_NAME}

      \# Redis  
      REDIS\_HOST: ${REDIS\_HOST}  
      REDIS\_PORT: ${REDIS\_PORT}  
      REDIS\_PASSWORD: ${REDIS\_PASSWORD}  
      REDIS\_DB: 0  
      REDIS\_USE\_SSL: "false"

      \# Celery  
      CELERY\_BROKER\_URL: "redis://:${REDIS\_PASSWORD}@${REDIS\_HOST}:${REDIS\_PORT}/1"

      \# Vector Store  
      VECTOR\_STORE: qdrant  
      QDRANT\_URL: http://${QDRANT\_HOST}:${QDRANT\_PORT}  
      QDRANT\_API\_KEY: ${QDRANT\_API\_KEY}

      \# Storage  
      STORAGE\_TYPE: local  
      STORAGE\_LOCAL\_PATH: /app/api/storage

    volumes:  
      \- ai-platform-dify-storage:/app/api/storage  
    networks:  
      \- ai-backend  
    extra\_hosts:  
      \- "host.docker.internal:host-gateway"  
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

    log\_info "docker-compose.dify-worker.yml generated"  
}

### **21.4 Docker Compose — Dify Web**

generate\_compose\_dify\_web() {  
    log\_info "Generating docker-compose.dify-web.yml..."

    cat \> "${DOCKER\_PATH}/docker-compose.dify-web.yml" \<\< EOF  
\# AI Platform — Dify Web Frontend  
\# Generated by 2-deploy-platform.sh

services:  
  dify-web:  
    image: ${DIFY\_WEB\_IMAGE}  
    container\_name: ai-platform-dify-web  
    restart: unless-stopped  
    environment:  
      CONSOLE\_API\_URL: ${URL\_PROTOCOL}://${DOMAIN\_NAME}  
      APP\_API\_URL: ${URL\_PROTOCOL}://${DOMAIN\_NAME}  
      SENTRY\_DSN: ""  
    networks:  
      \- ai-platform  
    healthcheck:  
      test: \["CMD-SHELL", "curl \-sf http://localhost:3000 || exit 1"\]  
      interval: 10s  
      timeout: 5s  
      retries: 5  
      start\_period: 15s  
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

    log\_info "docker-compose.dify-web.yml generated"  
}

### **21.5 Docker Compose — Dify Sandbox**

generate\_compose\_dify\_sandbox() {  
    log\_info "Generating docker-compose.dify-sandbox.yml..."

    cat \> "${DOCKER\_PATH}/docker-compose.dify-sandbox.yml" \<\< EOF  
\# AI Platform — Dify Sandbox (Code Execution)  
\# Generated by 2-deploy-platform.sh

services:  
  dify-sandbox:  
    image: ${DIFY\_SANDBOX\_IMAGE}  
    container\_name: ai-platform-dify-sandbox  
    restart: unless-stopped  
    environment:  
      API\_KEY: ${DIFY\_SANDBOX\_KEY}  
      GIN\_MODE: release  
      WORKER\_TIMEOUT: 15  
      ENABLE\_NETWORK: "true"  
      SANDBOX\_PORT: 8194  
    networks:  
      \- ai-backend  
    healthcheck:  
      test: \["CMD-SHELL", "curl \-sf http://localhost:8194/health || exit 1"\]  
      interval: 10s  
      timeout: 5s  
      retries: 5  
      start\_period: 10s  
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

    log\_info "docker-compose.dify-sandbox.yml generated"  
}

---

## **Section 22: Phase 5 — Docker Compose Files (Application Tier)**

### **22.1 Docker Compose — n8n**

generate\_compose\_n8n() {  
    log\_info "Generating docker-compose.n8n.yml..."

    cat \> "${DOCKER\_PATH}/docker-compose.n8n.yml" \<\< EOF  
\# AI Platform — n8n Workflow Automation  
\# Generated by 2-deploy-platform.sh

services:  
  n8n:  
    image: ${N8N\_IMAGE}  
    container\_name: ai-platform-n8n  
    restart: unless-stopped  
    environment:  
      N8N\_HOST: 0.0.0.0  
      N8N\_PORT: 5678  
      N8N\_PROTOCOL: https  
      WEBHOOK\_URL: ${URL\_PROTOCOL}://${DOMAIN\_NAME}:5678/  
      N8N\_ENCRYPTION\_KEY: ${N8N\_ENCRYPTION\_KEY}  
      N8N\_USER\_MANAGEMENT\_JWT\_SECRET: ${N8N\_WEBHOOK\_SECRET}

      \# Database  
      DB\_TYPE: postgresdb  
      DB\_POSTGRESDB\_HOST: ${POSTGRES\_HOST}  
      DB\_POSTGRESDB\_PORT: ${POSTGRES\_PORT}  
      DB\_POSTGRESDB\_DATABASE: ${N8N\_DB\_NAME}  
      DB\_POSTGRESDB\_USER: ${N8N\_DB\_USER}  
      DB\_POSTGRESDB\_PASSWORD: ${N8N\_DB\_PASSWORD}

      \# Execution  
      EXECUTIONS\_MODE: regular  
      EXECUTIONS\_DATA\_SAVE\_ON\_SUCCESS: all  
      EXECUTIONS\_DATA\_SAVE\_ON\_ERROR: all  
      EXECUTIONS\_DATA\_PRUNE: "true"  
      EXECUTIONS\_DATA\_MAX\_AGE: 168

      \# External hooks  
      N8N\_DIAGNOSTICS\_ENABLED: "false"  
      N8N\_VERSION\_NOTIFICATIONS\_ENABLED: "false"  
      GENERIC\_TIMEZONE: UTC

    volumes:  
      \- ai-platform-n8n-data:/home/node/.n8n  
    networks:  
      \- ai-platform  
      \- ai-backend  
    ports:  
      \- "127.0.0.1:5678:5678"  
    healthcheck:  
      test: \["CMD-SHELL", "curl \-sf http://localhost:5678/healthz || exit 1"\]  
      interval: 15s  
      timeout: 10s  
      retries: 5  
      start\_period: 30s  
    extra\_hosts:  
      \- "host.docker.internal:host-gateway"  
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

    log\_info "docker-compose.n8n.yml generated"  
}

### **22.2 Docker Compose — Open WebUI**

generate\_compose\_open\_webui() {  
    log\_info "Generating docker-compose.open-webui.yml..."

    cat \> "${DOCKER\_PATH}/docker-compose.open-webui.yml" \<\< EOF  
\# AI Platform — Open WebUI  
\# Generated by 2-deploy-platform.sh

services:  
  open-webui:  
    image: ${OPEN\_WEBUI\_IMAGE}  
    container\_name: ai-platform-open-webui  
    restart: unless-stopped  
    environment:  
      OLLAMA\_BASE\_URL: ${OLLAMA\_BASE\_URL}  
      OPENAI\_API\_BASE\_URL: http://litellm:4000/v1  
      OPENAI\_API\_KEY: ${LITELLM\_MASTER\_KEY}  
      WEBUI\_SECRET\_KEY: ${DIFY\_STORAGE\_KEY}  
      WEBUI\_AUTH: "true"  
      ENABLE\_SIGNUP: "false"  
      DEFAULT\_USER\_ROLE: user  
      ENABLE\_COMMUNITY\_SHARING: "false"  
    volumes:  
      \- ai-platform-openwebui-data:/app/backend/data  
    networks:  
      \- ai-platform  
      \- ai-backend  
    ports:  
      \- "127.0.0.1:3001:8080"  
    healthcheck:  
      test: \["CMD-SHELL", "curl \-sf http://localhost:8080/health || exit 1"\]  
      interval: 15s  
      timeout: 10s  
      retries: 5  
      start\_period: 30s  
    extra\_hosts:  
      \- "host.docker.internal:host-gateway"  
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

    log\_info "docker-compose.open-webui.yml generated"  
}

### **22.3 Docker Compose — Flowise (Conditional)**

generate\_compose\_flowise() {  
    if \[\[ " $ FLOWISE\_ENABLED" \!= "true" \]\]; then  
        log\_info "Flowise disabled — skipping compose generation"  
        return 0  
    fi

    log\_info "Generating docker-compose.flowise.yml..."

    cat \> " $ {DOCKER\_PATH}/docker-compose.flowise.yml" \<\< EOF  
\# AI Platform — Flowise  
\# Generated by 2-deploy-platform.sh

services:  
  flowise:  
    image: ${FLOWISE\_IMAGE}  
    container\_name: ai-platform-flowise  
    restart: unless-stopped  
    environment:  
      PORT: 3000  
      FLOWISE\_USERNAME: admin  
      FLOWISE\_PASSWORD: ${ADMIN\_PASSWORD}  
      FLOWISE\_SECRETKEY\_OVERWRITE: ${FLOWISE\_SECRET\_KEY}  
      DATABASE\_TYPE: postgres  
      DATABASE\_HOST: ${POSTGRES\_HOST}  
      DATABASE\_PORT: ${POSTGRES\_PORT}  
      DATABASE\_NAME: ${FLOWISE\_DB\_NAME}  
      DATABASE\_USER: ${FLOWISE\_DB\_USER}  
      DATABASE\_PASSWORD: ${FLOWISE\_DB\_PASSWORD}  
      APIKEY\_PATH: /root/.flowise  
      LOG\_LEVEL: info  
    volumes:  
      \- ai-platform-flowise-data:/root/.flowise  
    networks:  
      \- ai-platform  
      \- ai-backend  
    ports:  
      \- "127.0.0.1:3002:3000"  
    healthcheck:  
      test: \["CMD-SHELL", "curl \-sf http://localhost:3000 || exit 1"\]  
      interval: 15s  
      timeout: 10s  
      retries: 5  
      start\_period: 30s  
    extra\_hosts:  
      \- "host.docker.internal:host-gateway"  
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

    log\_info "docker-compose.flowise.yml generated"  
}

\---

\#\# Section 23: Phase 5 — Docker Compose Files (Front & Monitoring Tier)

\#\#\# 23.1 Docker Compose — Caddy

\`\`\`bash  
generate\_compose\_caddy() {  
    log\_info "Generating docker-compose.caddy.yml..."

    \# Build ports list based on mode  
    local ports\_block  
    if \[\[ " $ DOMAIN\_MODE" \== "ip" \]\]; then  
        ports\_block="    ports:  
      \- \\"80:80\\"  
      \- \\"443:443\\"  
      \- \\"5678:5678\\"  
      \- \\"3001:3001\\"  
      \- \\"4000:4000\\""

        if \[\[ " $ FLOWISE\_ENABLED" \== "true" \]\]; then  
            ports\_block="${ports\_block}  
      \- \\"3002:3002\\""  
        fi  
        if \[\[ " $ GRAFANA\_ENABLED" \== "true" \]\]; then  
            ports\_block=" $ {ports\_block}  
      \- \\"3003:3003\\""  
        fi  
    else  
        ports\_block="    ports:  
      \- \\"80:80\\"  
      \- \\"443:443\\""  
    fi

    cat \> "${DOCKER\_PATH}/docker-compose.caddy.yml" \<\< EOF  
\# AI Platform — Caddy Reverse Proxy  
\# Generated by 2-deploy-platform.sh

services:  
  caddy:  
    image: ${CADDY\_IMAGE}  
    container\_name: ai-platform-caddy  
    restart: unless-stopped  
    volumes:  
      \- ${CONFIG\_PATH}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro  
      \- ai-platform-caddy-data:/data  
      \- ai-platform-caddy-config:/config  
      \- ai-platform-caddy-logs:/data/logs  
${ports\_block}  
    networks:  
      \- ai-platform  
    healthcheck:  
      test: \["CMD-SHELL", "curl \-sf http://localhost:80 || curl \-sfk https://localhost:443 || exit 1"\]  
      interval: 15s  
      timeout: 10s  
      retries: 5  
      start\_period: 15s  
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

    log\_info "docker-compose.caddy.yml generated"  
}

### **23.2 Docker Compose — Prometheus**

generate\_compose\_prometheus() {  
    if \[\[ " $ PROMETHEUS\_ENABLED" \!= "true" \]\]; then  
        log\_info "Prometheus disabled — skipping compose generation"  
        return 0  
    fi

    log\_info "Generating docker-compose.prometheus.yml..."

    cat \> " $ {DOCKER\_PATH}/docker-compose.prometheus.yml" \<\< EOF  
\# AI Platform — Prometheus  
\# Generated by 2-deploy-platform.sh

services:  
  prometheus:  
    image: ${PROMETHEUS\_IMAGE}  
    container\_name: ai-platform-prometheus  
    restart: unless-stopped  
    command:  
      \- '--config.file=/etc/prometheus/prometheus.yml'  
      \- '--storage.tsdb.path=/prometheus'  
      \- '--storage.tsdb.retention.time=30d'  
      \- '--web.console.libraries=/etc/prometheus/console\_libraries'  
      \- '--web.console.templates=/etc/prometheus/consoles'  
      \- '--web.enable-lifecycle'  
    volumes:  
      \- ${CONFIG\_PATH}/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro  
      \- ai-platform-prometheus-data:/prometheus  
    networks:  
      \- ai-platform  
      \- ai-backend  
    ports:  
      \- "127.0.0.1:9090:9090"  
    healthcheck:  
      test: \["CMD-SHELL", "wget \-q \--spider http://localhost:9090/-/healthy || exit 1"\]  
      interval: 15s  
      timeout: 5s  
      retries: 5  
      start\_period: 15s  
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

    log\_info "docker-compose.prometheus.yml generated"  
}

### **23.3 Docker Compose — Grafana**

generate\_compose\_grafana() {  
    if \[\[ " $ GRAFANA\_ENABLED" \!= "true" \]\]; then  
        log\_info "Grafana disabled — skipping compose generation"  
        return 0  
    fi

    log\_info "Generating docker-compose.grafana.yml..."

    cat \> " $ {DOCKER\_PATH}/docker-compose.grafana.yml" \<\< EOF  
\# AI Platform — Grafana  
\# Generated by 2-deploy-platform.sh

services:  
  grafana:  
    image: ${GRAFANA\_IMAGE}  
    container\_name: ai-platform-grafana  
    restart: unless-stopped  
    environment:  
      GF\_SECURITY\_ADMIN\_USER: admin  
      GF\_SECURITY\_ADMIN\_PASSWORD: ${GRAFANA\_ADMIN\_PASSWORD}  
      GF\_USERS\_ALLOW\_SIGN\_UP: "false"  
      GF\_SERVER\_ROOT\_URL: ${URL\_PROTOCOL}://${GRAFANA\_URL}  
      GF\_SERVER\_SERVE\_FROM\_SUB\_PATH: "false"  
      GF\_LOG\_LEVEL: info  
      GF\_INSTALL\_PLUGINS: grafana-clock-panel,grafana-simple-json-datasource  
    volumes:  
      \- ai-platform-grafana-data:/var/lib/grafana  
      \- ${CONFIG\_PATH}/grafana/provisioning:/etc/grafana/provisioning:ro  
      \- ${CONFIG\_PATH}/grafana/dashboards:/var/lib/grafana/dashboards:ro  
    networks:  
      \- ai-platform  
      \- ai-backend  
    ports:  
      \- "127.0.0.1:3003:3000"  
    healthcheck:  
      test: \["CMD-SHELL", "curl \-sf http://localhost:3000/api/health || exit 1"\]  
      interval: 15s  
      timeout: 5s  
      retries: 5  
      start\_period: 30s  
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

    log\_info "docker-compose.grafana.yml generated"  
}

---

## **Section 24: Phase 6 — Deployment Engine**

### **24.1 Overview**

Deployment is strictly ordered in tiers. Each tier must be healthy before the next starts.

Deployment Order:  
  Tier 1: Infrastructure  →  postgres, redis, qdrant, supertokens  
  Tier 2: AI Services     →  litellm, dify-sandbox, dify-api, dify-worker, dify-web  
  Tier 3: Applications    →  n8n, open-webui, flowise (if enabled)  
  Tier 4: Front           →  caddy  
  Tier 5: Monitoring      →  prometheus (if enabled), grafana (if enabled)

### **24.2 Core Deployment Function**

deploy\_service() {  
    local compose\_file=" $ 1"  
    local service\_name=" $ 2"  
    local max\_wait="${3:-120}"  \# Default 120s timeout

    if \[\[ \! \-f "${DOCKER\_PATH}/${compose\_file}" \]\]; then  
        log\_warn "Compose file not found: ${compose\_file} — skipping"  
        return 0  
    fi

    log\_info "Deploying ${service\_name}..."  
    docker compose \-f "${DOCKER\_PATH}/${compose\_file}" up \-d

    if \[\[ $? \-ne 0 \]\]; then  
        log\_error "Failed to start ${service\_name}"  
        return 1  
    fi

    \# Wait for health check  
    wait\_for\_healthy "${service\_name}" "${max\_wait}"  
}

wait\_for\_healthy() {  
    local container\_name="ai-platform-${1}"  
    local max\_wait="$2"  
    local elapsed=0  
    local interval=5

    log\_info "Waiting for ${1} to be healthy (timeout: ${max\_wait}s)..."

    while \[\[ $elapsed \-lt  $ max\_wait \]\]; do  
        local status  
        status= $ (docker inspect \--format='{{.State.Health.Status}}' "${container\_name}" 2\>/dev/null)

        case "$status" in  
            healthy)  
                log\_info "✓ ${1} is healthy (${elapsed}s)"  
                return 0  
                ;;  
            unhealthy)  
                log\_error "✗ ${1} is unhealthy after ${elapsed}s"  
                docker logs \--tail 20 "${container\_name}" 2\>&1 | while read \-r line; do  
                    log\_error "  ${line}"  
                done  
                return 1  
                ;;  
            \*)  
                \# starting or no health check  
                sleep " $ interval"  
                elapsed= $ ((elapsed \+ interval))  
                ;;  
        esac  
    done

    log\_error "✗ ${1} timed out after ${max\_wait}s"  
    log\_error "  Current status: ${status:-unknown}"  
    docker logs \--tail 20 "${container\_name}" 2\>&1 | while read \-r line; do  
        log\_error "  ${line}"  
    done  
    return 1  
}

### **24.3 Tiered Deployment Execution**

deploy\_all\_services() {  
    log\_section "DEPLOYMENT PHASE"  
    local errors=0

    \# ── Tier 1: Infrastructure ──  
    log\_section "Tier 1: Infrastructure Services"

    deploy\_service "docker-compose.postgres.yml" "postgres" 120  
    \[\[  $ ? \-ne 0 \]\] && errors= $ ((errors \+ 1))

    deploy\_service "docker-compose.redis.yml" "redis" 60  
    \[\[  $ ? \-ne 0 \]\] && errors= $ ((errors \+ 1))

    deploy\_service "docker-compose.qdrant.yml" "qdrant" 60  
    \[\[  $ ? \-ne 0 \]\] && errors= $ ((errors \+ 1))

    deploy\_service "docker-compose.supertokens.yml" "supertokens" 90  
    \[\[  $ ? \-ne 0 \]\] && errors= $ ((errors \+ 1))

    if \[\[ $errors \-gt 0 \]\]; then  
        log\_error "Infrastructure tier failed with ${errors} error(s)"  
        log\_error "Cannot proceed — fix infrastructure before continuing"  
        exit 1  
    fi  
    log\_info "✓ Infrastructure tier fully healthy"

    \# ── Tier 2: AI Services ──  
    log\_section "Tier 2: AI Services"  
    errors=0

    deploy\_service "docker-compose.litellm.yml" "litellm" 120  
    \[\[  $ ? \-ne 0 \]\] && errors= $ ((errors \+ 1))

    deploy\_service "docker-compose.dify-sandbox.yml" "dify-sandbox" 60  
    \[\[  $ ? \-ne 0 \]\] && errors= $ ((errors \+ 1))

    deploy\_service "docker-compose.dify-api.yml" "dify-api" 180  
    \[\[  $ ? \-ne 0 \]\] && errors= $ ((errors \+ 1))

    deploy\_service "docker-compose.dify-worker.yml" "dify-worker" 60  
    \# Worker has no health check — just wait  
    sleep 10  
    log\_info "✓ Dify worker started (no health check)"

    deploy\_service "docker-compose.dify-web.yml" "dify-web" 60  
    \[\[  $ ? \-ne 0 \]\] && errors= $ ((errors \+ 1))

    if \[\[ $errors \-gt 0 \]\]; then  
        log\_error "AI tier had ${errors} error(s) — proceeding with warnings"  
    else  
        log\_info "✓ AI tier fully healthy"  
    fi

    \# ── Tier 3: Applications ──  
    log\_section "Tier 3: Application Services"  
    errors=0

    deploy\_service "docker-compose.n8n.yml" "n8n" 90  
    \[\[  $ ? \-ne 0 \]\] && errors= $ ((errors \+ 1))

    deploy\_service "docker-compose.open-webui.yml" "open-webui" 90  
    \[\[  $ ? \-ne 0 \]\] && errors= $ ((errors \+ 1))

    if \[\[ "$FLOWISE\_ENABLED" \== "true" \]\]; then  
        deploy\_service "docker-compose.flowise.yml" "flowise" 90  
        \[\[  $ ? \-ne 0 \]\] && errors= $ ((errors \+ 1))  
    fi

    if \[\[ $errors \-gt 0 \]\]; then  
        log\_error "Application tier had ${errors} error(s) — proceeding with warnings"  
    else  
        log\_info "✓ Application tier fully healthy"  
    fi

    \# ── Tier 4: Front ──  
    log\_section "Tier 4: Reverse Proxy"

    deploy\_service "docker-compose.caddy.yml" "caddy" 60  
    \[\[  $ ? \-ne 0 \]\] && log\_warn "Caddy may need a moment to obtain certificates"

    \# ── Tier 5: Monitoring ──  
    if \[\[ " $ PROMETHEUS\_ENABLED" \== "true" \]\] || \[\[ " $ GRAFANA\_ENABLED" \== "true" \]\]; then  
        log\_section "Tier 5: Monitoring Services"

        if \[\[ " $ PROMETHEUS\_ENABLED" \== "true" \]\]; then  
            deploy\_service "docker-compose.prometheus.yml" "prometheus" 60  
        fi

        if \[\[ "$GRAFANA\_ENABLED" \== "true" \]\]; then  
            deploy\_service "docker-compose.grafana.yml" "grafana" 60  
        fi

        log\_info "✓ Monitoring tier deployed"  
    fi  
}

### **24.4 Post-Deployment Validation**

post\_deployment\_validation() {  
    log\_section "POST-DEPLOYMENT VALIDATION"

    local total=0  
    local healthy=0  
    local unhealthy=0

    echo ""  
    printf "%-25s %-15s %-10s\\n" "SERVICE" "STATUS" "PORT"  
    printf "%-25s %-15s %-10s\\n" "-------" "------" "----"

    \# Check each container  
    for container in  $ (docker ps \--format '{{.Names}}' | grep '^ai-platform-' | sort); do  
        total= $ ((total \+ 1))  
        local svc\_name="${container\#ai-platform-}"  
        local status  
        status= $ (docker inspect \--format='{{.State.Health.Status}}' " $ container" 2\>/dev/null || echo "running")  
        local port  
        port= $ (docker port " $ container" 2\>/dev/null | head \-1 | awk \-F: '{print  $ NF}' || echo "-")

        if \[\[ " $ status" \== "healthy" \]\] || \[\[ " $ status" \== "running" \]\]; then  
            healthy= $ ((healthy \+ 1))  
            printf "%-25s %-15s %-10s\\n" "$svc\_name" "✓ ${status}" "${port:-'-'}"  
        else  
            unhealthy= $ ((unhealthy \+ 1))  
            printf "%-25s %-15s %-10s\\n" " $ svc\_name" "✗ ${status}" "${port:-'-'}"  
        fi  
    done

    echo ""  
    log\_info "Total: ${total} | Healthy: ${healthy} | Unhealthy: ${unhealthy}"  
    echo ""  
}

---

## **Section 25: Phase 7 — Summary & Access Information**

### **25.1 Final Output**

print\_deployment\_summary() {  
    log\_section "DEPLOYMENT COMPLETE"

    echo ""  
    echo "╔══════════════════════════════════════════════════════════════╗"  
    echo "║              AI PLATFORM — DEPLOYMENT SUMMARY              ║"  
    echo "╚══════════════════════════════════════════════════════════════╝"  
    echo ""

    \# Access URLs  
    echo "┌─ Access URLs ────────────────────────────────────────────────┐"  
    if \[\[ " $ DOMAIN\_MODE" \== "ip" \]\]; then  
        local base=" $ {URL\_PROTOCOL}://${HOST\_IP}"  
        echo "│  Dify:           ${base}                                    │"  
        echo "│  n8n:            ${base}:5678                               │"  
        echo "│  Open WebUI:     ${base}:3001                               │"  
        echo "│  LiteLLM:        ${base}:4000                               │"  
        if \[\[ "$FLOWISE\_ENABLED" \== "true" \]\]; then  
            echo "│  Flowise:        ${base}:3002                               │"  
        fi  
        if \[\[ "$GRAFANA\_ENABLED" \== "true" \]\]; then  
            echo "│  Grafana:        ${base}:3003                               │"  
        fi  
    else  
        echo "│  Dify:           ${URL\_PROTOCOL}://${DOMAIN\_NAME}           │"  
        echo "│  n8n:            ${URL\_PROTOCOL}://n8n.${DOMAIN\_NAME}       │"  
        echo "│  Open WebUI:     ${URL\_PROTOCOL}://chat.${DOMAIN\_NAME}      │"  
        echo "│  LiteLLM:        ${URL\_PROTOCOL}://llm.${DOMAIN\_NAME}      │"  
        if \[\[ "$FLOWISE\_ENABLED" \== "true" \]\]; then  
            echo "│  Flowise:        ${URL\_PROTOCOL}://flow.${DOMAIN\_NAME}      │"  
        fi  
        if \[\[ "$GRAFANA\_ENABLED" \== "true" \]\]; then  
            echo "│  Grafana:        ${URL\_PROTOCOL}://grafana.${DOMAIN\_NAME}   │"  
        fi  
    fi  
    echo "└─────────────────────────────────────────────────────────────┘"  
    echo ""

    \# Credentials  
    echo "┌─ Default Credentials ────────────────────────────────────────┐"  
    echo "│                                                              │"  
    echo "│  Dify Admin:     Set on first login                          │"  
    echo "│  n8n:            Set on first login                          │"  
    echo "│  Open WebUI:     Set on first login                          │"  
    echo "│  Grafana:        admin / (see credentials.env)               │"  
    echo "│  LiteLLM Admin:  (see credentials.env for master key)       │"  
    echo "│                                                              │"  
    echo "│  All credentials saved to:                                   │"  
    echo "│    ${CONFIG\_PATH}/credentials.env                            │"  
    echo "│                                                              │"  
    echo "└─────────────────────────────────────────────────────────────┘"  
    echo ""

    \# Quick commands  
    echo "┌─ Useful Commands ────────────────────────────────────────────┐"  
    echo "│                                                              │"  
    echo "│  View all containers:                                        │"  
    echo "│    docker ps \--format 'table {{.Names}}\\t{{.Status}}'        │"  
    echo "│                                                              │"  
    echo "│  View logs:                                                  │"  
    echo "│    docker logs \-f ai-platform-\<service\>                      │"  
    echo "│                                                              │"  
    echo "│  Restart a service:                                          │"  
    echo "│    cd /mnt/data/ai-platform/docker                                │"  
    echo "│    docker compose \-f docker-compose.\<svc\>.yml restart        │"  
    echo "│                                                              │"  
    echo "│  Next step — Configure platform:                             │"  
    echo "│    sudo bash 3-configure-platform.sh                         │"  
    echo "│                                                              │"  
    echo "└─────────────────────────────────────────────────────────────┘"  
    echo ""  
}

---

## **Section 26: Script 2 — Main Execution Flow**

### **26.1 Complete main() Function**

main() {  
    \# Initialize logging  
    LOG\_FILE="${ROOT\_PATH}/logs/script-2.log"  
    exec \> \>(tee \-a "$LOG\_FILE") 2\>&1

    echo ""  
    log\_section "AI PLATFORM — DEPLOYMENT SCRIPT (Script 2 of 4)"  
    log\_info "Started at: $(date)"  
    echo ""

    \# Phase 1: Pre-flight  
    preflight\_checks

    \# Phase 2: Questionnaire  
    interactive\_questionnaire

    \# Phase 3: Credentials  
    generate\_all\_credentials

    \# Phase 4: Config files  
    generate\_master\_env  
    generate\_postgres\_init  
    generate\_redis\_config  
    generate\_litellm\_config  
    generate\_dify\_env            \# Not shown — writes supplementary Dify config  
    generate\_caddyfile  
    generate\_prometheus\_config  
    generate\_grafana\_provisioning

    \# Phase 5: Docker compose files  
    create\_docker\_networks  
    generate\_compose\_postgres  
    generate\_compose\_redis  
    generate\_compose\_qdrant  
    generate\_compose\_supertokens  
    generate\_compose\_litellm  
    generate\_compose\_dify\_api  
    generate\_compose\_dify\_worker  
    generate\_compose\_dify\_web  
    generate\_compose\_dify\_sandbox  
    generate\_compose\_n8n  
    generate\_compose\_open\_webui  
    generate\_compose\_flowise  
    generate\_compose\_caddy  
    generate\_compose\_prometheus  
    generate\_compose\_grafana

    \# Phase 6: Deploy  
    deploy\_all\_services

    \# Phase 7: Validate & summarize  
    post\_deployment\_validation  
    print\_deployment\_summary

    log\_info "Script 2 completed at:  $ (date)"  
}

\# Entry point  
main " $ @"

---

## **Section 27: Script 3 — Configure Platform**

### **27.1 Purpose**

`3-configure-platform.sh` performs post-deployment configuration that requires running services. It sets up:

* LiteLLM model verification  
* n8n credential helpers  
* Dify initial API verification  
* Connectivity tests between services  
* Convenience alias scripts

### **27.2 Execution**

sudo bash 3-configure-platform.sh

### **27.3 Phase Map**

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

### **27.4 Connectivity Testing**

test\_connectivity() {  
    log\_section "SERVICE CONNECTIVITY TESTS"  
    local pass=0  
    local fail=0

    \# Test: Ollama on host  
    log\_info "Testing Ollama..."  
    if curl \-sf http://localhost:11434/api/tags &\>/dev/null; then  
        log\_info "  ✓ Ollama responding on localhost:11434"  
        pass= $ ((pass \+ 1))  
    else  
        log\_error "  ✗ Ollama not responding"  
        fail= $ ((fail \+ 1))  
    fi

    \# Test: LiteLLM  
    log\_info "Testing LiteLLM..."  
    if curl \-sf http://localhost:4000/health/liveliness &\>/dev/null; then  
        log\_info "  ✓ LiteLLM alive on localhost:4000"  
        pass= $ ((pass \+ 1))  
    else  
        log\_error "  ✗ LiteLLM not responding"  
        fail= $ ((fail \+ 1))  
    fi

    \# Test: LiteLLM → Ollama (through LiteLLM)  
    log\_info "Testing LiteLLM → Ollama routing..."  
    local test\_response  
    test\_response=$(curl \-sf \-X POST http://localhost:4000/v1/chat/completions \\  
        \-H "Content-Type: application/json" \\  
        \-H "Authorization: Bearer ${LITELLM\_MASTER\_KEY}" \\  
        \-d '{  
            "model": "'"${PRIMARY\_MODEL}"'",  
            "messages": \[{"role": "user", "content": "Say hello in exactly one word."}\],  
            "max\_tokens": 10  
        }' 2\>/dev/null)

    if echo " $ test\_response" | jq \-e '.choices\[0\].message.content' &\>/dev/null; then  
        local reply  
        reply= $ (echo "$test\_response" | jq \-r '.choices\[0\].message.content')  
        log\_info "  ✓ LiteLLM → Ollama working (response: ${reply})"  
        pass= $ ((pass \+ 1))  
    else  
        log\_error "  ✗ LiteLLM → Ollama routing failed"  
        fail= $ ((fail \+ 1))  
    fi

    \# Test: Dify API  
    log\_info "Testing Dify API..."  
    if curl \-sf http://localhost:5001/health &\>/dev/null; then  
        log\_info "  ✓ Dify API healthy"  
        pass= $ ((pass \+ 1))  
    else  
        log\_error "  ✗ Dify API not responding"  
        fail= $ ((fail \+ 1))  
    fi

    \# Test: n8n  
    log\_info "Testing n8n..."  
    if curl \-sf http://localhost:5678/healthz &\>/dev/null; then  
        log\_info "  ✓ n8n healthy"  
        pass= $ ((pass \+ 1))  
    else  
        log\_error "  ✗ n8n not responding"  
        fail= $ ((fail \+ 1))  
    fi

    \# Test: Open WebUI  
    log\_info "Testing Open WebUI..."  
    if curl \-sf http://localhost:3001/health &\>/dev/null 2\>&1 || \\  
       curl \-sf http://localhost:3001 &\>/dev/null 2\>&1; then  
        log\_info "  ✓ Open WebUI responding"  
        pass= $ ((pass \+ 1))  
    else  
        log\_error "  ✗ Open WebUI not responding"  
        fail= $ ((fail \+ 1))  
    fi

    \# Test: PostgreSQL  
    log\_info "Testing PostgreSQL..."  
    if docker exec ai-platform-postgres pg\_isready \-U "${POSTGRES\_USER}" &\>/dev/null; then  
        log\_info "  ✓ PostgreSQL ready"  
        pass= $ ((pass \+ 1))  
    else  
        log\_error "  ✗ PostgreSQL not ready"  
        fail= $ ((fail \+ 1))  
    fi

    \# Test: Redis  
    log\_info "Testing Redis..."  
    if docker exec ai-platform-redis redis-cli \-a "${REDIS\_PASSWORD}" ping 2\>/dev/null | grep \-q PONG; then  
        log\_info "  ✓ Redis responding (PONG)"  
        pass= $ ((pass \+ 1))  
    else  
        log\_error "  ✗ Redis not responding"  
        fail= $ ((fail \+ 1))  
    fi

    \# Test: Qdrant  
    log\_info "Testing Qdrant..."  
    if curl \-sf http://localhost:6333/healthz &\>/dev/null; then  
        log\_info "  ✓ Qdrant healthy"  
        pass= $ ((pass \+ 1))  
    else  
        log\_error "  ✗ Qdrant not responding"  
        fail= $ ((fail \+ 1))  
    fi

    echo ""  
    log\_info "Connectivity: ${pass} passed, ${fail} failed out of $((pass \+ fail)) tests"

    if \[\[ $fail \-gt 0 \]\]; then  
        log\_warn "Some services are not responding — check logs with:"  
        log\_warn "  docker logs ai-platform-\<service-name\>"  
    fi

    return $fail  
}

### **27.5 Convenience Script Generation**

generate\_convenience\_scripts() {  
    log\_section "GENERATING CONVENIENCE SCRIPTS"

    local scripts\_dir="${ROOT\_PATH}/scripts"  
    mkdir \-p " $ scripts\_dir"

    \# ── platform-status.sh ──  
    cat \> " $ {scripts\_dir}/platform-status.sh" \<\< 'EOF'  
\#\!/bin/bash  
\# AI Platform — Status Check  
echo ""  
echo "=== AI Platform Status \==="  
echo ""  
printf "%-30s %-15s %-10s\\n" "CONTAINER" "STATUS" "UPTIME"  
printf "%-30s %-15s %-10s\\n" "---------" "------" "------"  
docker ps \--filter "name=ai-platform-" \--format "table {{.Names}}\\t{{.Status}}" | tail \-n \+2 | sort | while read \-r line; do  
    printf "%-30s\\n" "$line"  
done  
echo ""  
echo "=== Ollama \==="  
if systemctl is-active \--quiet ollama; then  
    echo "  Status: Running"  
    echo "  Models:  $ (curl \-sf http://localhost:11434/api/tags | jq \-r '.models\[\].name' 2\>/dev/null | tr '\\n' ', ' | sed 's/, $ //')"  
else  
    echo "  Status: Stopped"  
fi  
echo ""  
EOF  
    chmod \+x "${scripts\_dir}/platform-status.sh"

    \# ── platform-restart.sh ──  
    cat \> "${scripts\_dir}/platform-restart.sh" \<\< 'SCRIPTEOF'  
\#\!/bin/bash  
\# AI Platform — Restart all services  
DOCKER\_PATH="/mnt/data/ai-platform/docker"

echo "Restarting AI Platform..."

if \[\[ \-n "$1" \]\]; then  
    \# Restart specific service  
    echo "Restarting  $ 1..."  
    docker compose \-f " $ {DOCKER\_PATH}/docker-compose.${1}.yml" restart  
else  
    \# Restart all in order  
    for f in $(ls ${DOCKER\_PATH}/docker-compose.\*.yml 2\>/dev/null | sort); do  
        svc= $ (basename " $ f" | sed 's/docker-compose\\.$ .\* $ \\.yml/\\1/')  
        echo "Restarting ${svc}..."  
        docker compose \-f " $ f" restart  
    done  
fi

echo "Done."  
SCRIPTEOF  
    chmod \+x " $ {scripts\_dir}/platform-restart.sh"

    \# ── platform-stop.sh ──  
    cat \> "${scripts\_dir}/platform-stop.sh" \<\< 'SCRIPTEOF'  
\#\!/bin/bash  
\# AI Platform — Stop all services  
DOCKER\_PATH="/mnt/data/ai-platform/docker"

echo "Stopping AI Platform..."

\# Stop in reverse order (front first)  
for f in $(ls ${DOCKER\_PATH}/docker-compose.\*.yml 2\>/dev/null | sort \-r); do  
    svc= $ (basename " $ f" | sed 's/docker-compose\\.$ .\* $ \\.yml/\\1/')  
    echo "Stopping ${svc}..."  
    docker compose \-f " $ f" down  
done

echo "All services stopped."  
echo "Note: Ollama is still running (systemd service)"  
SCRIPTEOF  
    chmod \+x " $ {scripts\_dir}/platform-stop.sh"

    \# ── platform-start.sh ──  
    cat \> "${scripts\_dir}/platform-start.sh" \<\< 'SCRIPTEOF'  
\#\!/bin/bash  
\# AI Platform — Start all services  
DOCKER\_PATH="/mnt/data/ai-platform/docker"

echo "Starting AI Platform..."

\# Start infrastructure first  
for svc in postgres redis qdrant supertokens; do  
    \[\[ \-f "${DOCKER\_PATH}/docker-compose.${svc}.yml" \]\] && \\  
        docker compose \-f "${DOCKER\_PATH}/docker-compose.${svc}.yml" up \-d  
done  
echo "Waiting for infrastructure..."  
sleep 15

\# AI services  
for svc in litellm dify-sandbox dify-api dify-worker dify-web; do  
    \[\[ \-f "${DOCKER\_PATH}/docker-compose.${svc}.yml" \]\] && \\  
        docker compose \-f "${DOCKER\_PATH}/docker-compose.${svc}.yml" up \-d  
done  
echo "Waiting for AI services..."  
sleep 20

\# Applications  
for svc in n8n open-webui flowise; do  
    \[\[ \-f "${DOCKER\_PATH}/docker-compose.${svc}.yml" \]\] && \\  
        docker compose \-f "${DOCKER\_PATH}/docker-compose.${svc}.yml" up \-d  
done

\# Front & monitoring  
for svc in caddy prometheus grafana; do  
    \[\[ \-f "${DOCKER\_PATH}/docker-compose.${svc}.yml" \]\] && \\  
        docker compose \-f "${DOCKER\_PATH}/docker-compose.${svc}.yml" up \-d  
done

echo "All services started."  
SCRIPTEOF  
    chmod \+x "${scripts\_dir}/platform-start.sh"

    \# ── platform-logs.sh ──  
    cat \> "${scripts\_dir}/platform-logs.sh" \<\< 'SCRIPTEOF'  
\#\!/bin/bash  
\# AI Platform — View logs  
if \[\[ \-z " $ 1" \]\]; then  
    echo "Usage: platform-logs.sh \<service-name\> \[lines\]"  
    echo ""  
    echo "Available services:"  
    docker ps \--filter "name=ai-platform-" \--format "  {{.Names}}" | sed 's/ai-platform-//' | sort  
    exit 1  
fi  
LINES=" $ {2:-100}"  
docker logs \--tail " $ LINES" \-f "ai-platform- $ {1}"  
SCRIPTEOF  
    chmod \+x "${scripts\_dir}/platform-logs.sh"

    \# ── platform-backup.sh ──  
    cat \> "${scripts\_dir}/platform-backup.sh" \<\< 'SCRIPTEOF'  
\#\!/bin/bash  
\# AI Platform — Backup  
BACKUP\_DIR="/mnt/data/ai-platform/backups/ $ (date \+%Y%m%d-%H%M%S)"  
mkdir \-p " $ BACKUP\_DIR"

echo "Backing up AI Platform to ${BACKUP\_DIR}..."

\# Backup configs  
cp \-r /mnt/data/ai-platform/config " $ BACKUP\_DIR/config"

\# Backup PostgreSQL  
echo "Backing up PostgreSQL..."  
docker exec ai-platform-postgres pg\_dumpall \-U postgres \> " $ BACKUP\_DIR/postgres-full.sql"

\# Backup docker compose files  
cp \-r /mnt/data/ai-platform/docker " $ BACKUP\_DIR/docker"

\# Compress  
tar \-czf " $ {BACKUP\_DIR}.tar.gz" \-C "$(dirname  $ BACKUP\_DIR)" " $ (basename  $ BACKUP\_DIR)"  
rm \-rf " $ BACKUP\_DIR"

echo "Backup complete: ${BACKUP\_DIR}.tar.gz"  
echo "Size:  $ (du \-h " $ {BACKUP\_DIR}.tar.gz" | cut \-f1)"  
SCRIPTEOF  
    chmod \+x "${scripts\_dir}/platform-backup.sh"

    log\_info "Generated convenience scripts in ${scripts\_dir}/"  
    log\_info "  platform-status.sh   — Check all services"  
    log\_info "  platform-restart.sh  — Restart all or one service"  
    log\_info "  platform-stop.sh     — Stop all services"  
    log\_info "  platform-start.sh    — Start all services (ordered)"  
    log\_info "  platform-logs.sh     — View service logs"  
    log\_info "  platform-backup.sh   — Backup configs and databases"  
}

### **27.6 Script 3 — Main Flow**

main() {  
    LOG\_FILE="${ROOT\_PATH}/logs/script-3.log"  
    exec \> \>(tee \-a "$LOG\_FILE") 2\>&1

    log\_section "AI PLATFORM — CONFIGURATION SCRIPT (Script 3 of 4)"  
    log\_info "Started at:  $ (date)"

    \# Source configs  
    source " $ {CONFIG\_PATH}/master.env"  
    source "${CONFIG\_PATH}/credentials.env"

    \# Phase 2: Connectivity  
    test\_connectivity  
    local test\_result=$?

    \# Phase 4: Convenience scripts  
    generate\_convenience\_scripts

    \# Phase 5: Final report  
    log\_section "CONFIGURATION COMPLETE"  
    echo ""

    if \[\[ $test\_result \-eq 0 \]\]; then  
        log\_info "✓ All connectivity tests passed"  
        log\_info "✓ Platform is fully operational"  
    else  
        log\_warn "Some connectivity tests failed"  
        log\_warn "Platform is partially operational — check failing services"  
    fi

    echo ""  
    log\_info "Platform management scripts installed to:"  
    log\_info "  /mnt/data/ai-platform/scripts/"  
    echo ""  
    log\_info "Next step (optional): Add extra models or services:"  
    log\_info "  sudo bash 4-add-services.sh"  
    echo ""

    log\_info "Script 3 completed at:  $ (date)"  
}

main " $ @"

---

## **Section 28: Script 4 — Add Services**

### **28.1 Purpose**

`4-add-services.sh` is a menu-driven utility for post-deployment additions:

* Pull additional Ollama models  
* Add cloud provider API keys to LiteLLM  
* Enable/deploy optional services that were skipped during install  
* Add custom LiteLLM model entries

### **28.2 Execution**

sudo bash 4-add-services.sh

### **28.3 Menu Structure**

show\_menu() {  
    echo ""  
    echo "╔══════════════════════════════════════════════════════════╗"  
    echo "║            AI PLATFORM — ADD SERVICES MENU              ║"  
    echo "╠══════════════════════════════════════════════════════════╣"  
    echo "║                                                          ║"  
    echo "║  1\) Pull additional Ollama model                         ║"  
    echo "║  2\) Add cloud provider API key                           ║"  
    echo "║  3\) Add custom model to LiteLLM                          ║"  
    echo "║  4\) Enable Flowise (if not installed)                    ║"  
    echo "║  5\) Enable Prometheus \+ Grafana (if not installed)       ║"  
    echo "║  6\) Show current model list                              ║"  
    echo "║  7\) Show platform status                                 ║"  
    echo "║  0\) Exit                                                 ║"  
    echo "║                                                          ║"  
    echo "╚══════════════════════════════════════════════════════════╝"  
    echo ""  
    read \-rp "Select option: " choice  
}

### **28.4 Add Ollama Model**

add\_ollama\_model() {  
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
    read \-rp "Enter model name (e.g., mistral:7b): " model\_name

    if \[\[ \-z "$model\_name" \]\]; then  
        log\_warn "No model name provided"  
        return  
    fi

    log\_info "Pulling ${model\_name}..."  
    ollama pull "$model\_name"

    if \[\[ $? \-eq 0 \]\]; then  
        log\_info "✓ Model ${model\_name} pulled successfully"

        \# Add to LiteLLM config  
        read \-rp "Add to LiteLLM proxy? (y/n): " add\_to\_litellm  
        if \[\[ " $ add\_to\_litellm" \=\~ ^\[Yy\] \]\]; then  
            add\_model\_to\_litellm " $ model\_name" "ollama/${model\_name}" "${OLLAMA\_BASE\_URL}"  
        fi  
    else  
        log\_error "Failed to pull ${model\_name}"  
    fi  
}

### **28.5 Add Model to LiteLLM (Runtime)**

add\_model\_to\_litellm() {  
    local model\_alias=" $ 1"  
    local litellm\_model=" $ 2"  
    local api\_base=" $ 3"  
    local api\_key=" $ {4:-}"

    log\_info "Adding ${model\_alias} to LiteLLM..."

    local payload  
    if \[\[ \-n " $ api\_key" \]\]; then  
        payload= $ (cat \<\< EOF  
{  
    "model\_name": "${model\_alias}",  
    "litellm\_params": {  
        "model": "${litellm\_model}",  
        "api\_key": "${api\_key}"  
    }  
}  
EOF  
)  
    else  
        payload= $ (cat \<\< EOF  
{  
    "model\_name": " $ {model\_alias}",  
    "litellm\_params": {  
        "model": "${litellm\_model}",  
        "api\_base": "${api\_base}"  
    }  
}  
EOF  
)  
    fi

    local response  
    response=$(curl \-sf \-X POST http://localhost:4000/model/new \\  
        \-H "Content-Type: application/json" \\  
        \-H "Authorization: Bearer ${LITELLM\_MASTER\_KEY}" \\  
        \-d " $ payload" 2\>&1)

    if echo " $ response" | jq \-e '.model\_id' &\>/dev/null 2\>&1; then  
        log\_info "✓ Model ${model\_alias} added to LiteLLM"

        \# Also append to config file for persistence  
        cat \>\> "${CONFIG\_PATH}/litellm/config.yaml" \<\< EOF

  \- model\_name: ${model\_alias}  
    litellm\_params:  
      model: ${litellm\_model}  
 $ (if \[\[ \-n " $ api\_base" \]\]; then echo "      api\_base: ${api\_base}"; fi)  
 $ (if \[\[ \-n " $ api\_key" \]\]; then echo "      api\_key: ${api\_key}"; fi)  
EOF  
        log\_info "  Also written to config file for persistence"  
    else  
        log\_error "Failed to add model: ${response}"  
    fi  
}

### **28.6 Add Cloud Provider**

add\_cloud\_provider() {  
    echo ""  
    echo "Available providers:"  
    echo "  1\) OpenAI"  
    echo "  2\) Anthropic"  
    echo "  3\) Google AI (Gemini)"  
    echo "  4\) Mistral AI"  
    echo "  5\) Groq"  
    echo "  6\) Together AI"  
    echo ""  
    read \-rp "Select provider: " provider\_choice

    case " $ provider\_choice" in  
        1\)  
            read \-rsp "Enter OpenAI API key: " api\_key; echo ""  
            add\_model\_to\_litellm "gpt-4o" "openai/gpt-4o" "" " $ api\_key"  
            add\_model\_to\_litellm "gpt-4o-mini" "openai/gpt-4o-mini" "" " $ api\_key"  
            add\_model\_to\_litellm "text-embedding-3-small" "openai/text-embedding-3-small" "" " $ api\_key"  
            ;;  
        2\)  
            read \-rsp "Enter Anthropic API key: " api\_key; echo ""  
            add\_model\_to\_litellm "claude-sonnet-4-20250514" "anthropic/claude-sonnet-4-20250514" "" " $ api\_key"  
            add\_model\_to\_litellm "claude-3-5-haiku" "anthropic/claude-3-5-haiku-20241022" "" " $ api\_key"  
            ;;  
        3\)  
            read \-rsp "Enter Google AI API key: " api\_key; echo ""  
            add\_model\_to\_litellm "gemini-2.0-flash" "gemini/gemini-2.0-flash" "" " $ api\_key"  
            add\_model\_to\_litellm "gemini-2.5-pro" "gemini/gemini-2.5-pro-preview-06-05" "" " $ api\_key"  
            ;;  
        4\)  
            read \-rsp "Enter Mistral API key: " api\_key; echo ""  
            add\_model\_to\_litellm "mistral-large" "mistral/mistral-large-latest" "" " $ api\_key"  
            add\_model\_to\_litellm "mistral-small" "mistral/mistral-small-latest" "" " $ api\_key"  
            ;;  
        5\)  
            read \-rsp "Enter Groq API key: " api\_key; echo ""  
            add\_model\_to\_litellm "groq-llama-3.1-70b" "groq/llama-3.1-70b-versatile" "" " $ api\_key"  
            add\_model\_to\_litellm "groq-llama-3.1-8b" "groq/llama-3.1-8b-instant" "" " $ api\_key"  
            add\_model\_to\_litellm "groq-mixtral-8x7b" "groq/mixtral-8x7b-32768" "" " $ api\_key"  
            ;;  
        6\)  
            read \-rsp "Enter Together AI API key: " api\_key; echo ""  
            add\_model\_to\_litellm "together-llama-3.1-70b" "together\_ai/meta-llama/Meta-Llama-3.1-70B-Instruct-Turbo" "" " $ api\_key"  
            ;;  
        \*)  
            log\_warn "Invalid selection"  
            ;;  
    esac  
}

### **28.7 Show Model List**

show\_models() {  
    log\_section "CURRENT MODELS"

    echo ""  
    echo "── Ollama Models (Local) ──"  
    curl \-sf http://localhost:11434/api/tags | jq \-r '.models\[\] | "  \\(.name)\\t\\(.size / 1024 / 1024 / 1024 | . \* 100 | floor / 100)GB"' 2\>/dev/null || echo "  (Ollama not responding)"

    echo ""  
    echo "── LiteLLM Models (Proxy) ──"  
    curl \-sf http://localhost:4000/model/info \\  
        \-H "Authorization: Bearer ${LITELLM\_MASTER\_KEY}" | \\  
        jq \-r '.data\[\] | "  \\(.model\_name)\\t→ \\(.litellm\_params.model)"' 2\>/dev/null || echo "  (LiteLLM not responding)"

    echo ""  
}

### **28.8 Script 4 — Main Loop**

main() {  
    LOG\_FILE="${ROOT\_PATH}/logs/script-4.log"  
    exec \> \>(tee \-a " $ LOG\_FILE") 2\>&1

    \# Source configs  
    source " $ {CONFIG\_PATH}/master.env"  
    source "${CONFIG\_PATH}/credentials.env"

    log\_section "AI PLATFORM — ADD SERVICES (Script 4 of 4)"

    while true; do  
        show\_menu  
        case " $ choice" in  
            1\) add\_ollama\_model ;;  
            2\) add\_cloud\_provider ;;  
            3\)  
                read \-rp "Model alias (e.g., my-model): " alias  
                read \-rp "LiteLLM model string (e.g., ollama/modelname): " model\_str  
                read \-rp "API base URL (blank for cloud): " base\_url  
                read \-rsp "API key (blank for local): " key; echo ""  
                add\_model\_to\_litellm " $ alias" " $ model\_str" " $ base\_url" " $ key"  
                ;;  
            4\)  
                source " $ {CONFIG\_PATH}/master.env"  
                FLOWISE\_ENABLED="true"  
                generate\_compose\_flowise  
                deploy\_service "docker-compose.flowise.yml" "flowise" 90  
                ;;  
            5\)  
                source "${CONFIG\_PATH}/master.env"  
                PROMETHEUS\_ENABLED="true"  
                GRAFANA\_ENABLED="true"  
                generate\_compose\_prometheus  
                generate\_compose\_grafana  
                deploy\_service "docker-compose.prometheus.yml" "prometheus" 60  
                deploy\_service "docker-compose.grafana.yml" "grafana" 60  
                ;;  
            6\) show\_models ;;  
            7\) bash "${ROOT\_PATH}/scripts/platform-status.sh" ;;  
            0\) echo "Exiting."; exit 0 ;;  
            \*) echo "Invalid option." ;;  
        esac  
    done  
}

main "$@"

\---

\#\# Section 29: Troubleshooting Guide

\#\#\# 29.1 Diagnostic Flowchart

\`\`\`text  
Problem Detected  
│  
├─ Container won't start?  
│  ├─ docker logs ai-platform-\<service\>  
│  ├─ Check: docker compose \-f docker-compose.\<svc\>.yml config  
│  ├─ Check: .env file variables populated?  
│  └─ Check: dependent service healthy?  
│  
├─ Service unhealthy?  
│  ├─ docker inspect ai-platform-\<service\> | jq '.\[0\].State.Health'  
│  ├─ Check port binding: ss \-tlnp | grep \<port\>  
│  └─ Check memory: docker stats ai-platform-\<service\> \--no-stream  
│  
├─ Can't access Web UI?  
│  ├─ Is Caddy running? docker logs ai-platform-caddy  
│  ├─ DNS / IP correct?  
│  ├─ Firewall: ufw status (ports 80, 443, 5678, 3001, 4000\)  
│  └─ Try direct: curl \-k https://localhost:443  
│  
├─ Ollama models not in LiteLLM?  
│  ├─ curl http://localhost:11434/api/tags  
│  ├─ curl http://localhost:4000/model/info \-H "Authorization: Bearer $KEY"  
│  ├─ Check LiteLLM config.yaml model entries  
│  └─ Restart: docker compose \-f docker-compose.litellm.yml restart  
│  
├─ Dify can't reach LiteLLM?  
│  ├─ From Dify container: curl http://litellm:4000/health/liveliness  
│  ├─ Check network: docker network inspect ai-platform  
│  └─ Verify Dify .env has correct LiteLLM URL  
│  
├─ n8n workflow errors?  
│  ├─ docker logs ai-platform-n8n \--tail 50  
│  ├─ Check n8n credentials in UI  
│  └─ Verify: curl http://localhost:5678/healthz  
│  
├─ Database connection refused?  
│  ├─ docker logs ai-platform-postgres  
│  ├─ Check: docker exec ai-platform-postgres pg\_isready \-U postgres  
│  ├─ Verify init SQL ran: docker exec ai-platform-postgres psql \-U postgres \-l  
│  └─ Check credentials match between service .env and postgres init  
│  
└─ Out of memory?  
   ├─ docker stats \--no-stream  
   ├─ Check: free \-h  
   ├─ Reduce Ollama model size  
   └─ Disable optional services (Flowise, Grafana)

### **29.2 Common Issues & Solutions**

Copy table

| Issue | Cause | Solution |
| ----- | ----- | ----- |
| `port already in use` | Another service on that port | `ss -tlnp | grep <port>` then stop conflicting service |
| `OCI runtime error` | Docker storage full | `docker system prune -a --volumes` (⚠️ removes unused data) |
| Ollama `connection refused` from container | Wrong host address | Verify `extra_hosts: host.docker.internal:host-gateway` in compose |
| LiteLLM `model not found` | Model name mismatch | Check `config.yaml` model names match Ollama `ollama list` output |
| Dify `500 Internal Server Error` | DB migration incomplete | `docker restart ai-platform-dify-api` — wait 60s for migrations |
| Caddy `TLS handshake error` | Self-signed cert warning | Expected with `tls internal` — accept in browser or use `curl -k` |
| Qdrant `disk space` | Vector DB growing | Check `/mnt/data/ai-platform/data/qdrant/` size — add storage or prune collections |
| SuperTokens `connection refused` | PostgreSQL not ready | Restart SuperTokens after PostgreSQL is confirmed healthy |
| Redis `NOAUTH` | Password mismatch | Compare `REDIS_PASSWORD` in `credentials.env` vs `redis.conf` `requirepass` |
| n8n `CSRF error` | Webhook URL mismatch | Verify `N8N_EDITOR_BASE_URL` and `WEBHOOK_URL` in compose match actual URL |

### **29.3 Log Locations**

/mnt/data/ai-platform/  
├── logs/  
│   ├── script-1.log          \# System prep log  
│   ├── script-2.log          \# Deployment log  
│   ├── script-3.log          \# Configuration log  
│   └── script-4.log          \# Add services log  
│  
Docker container logs:  
  docker logs ai-platform-\<service\>  
  docker logs \--since 1h ai-platform-\<service\>  
  docker logs \--tail 100 \-f ai-platform-\<service\>

Caddy logs (inside volume):  
  docker exec ai-platform-caddy cat /data/logs/caddy.log

### **29.4 Emergency Recovery**

\# Full platform restart (ordered)  
sudo bash /mnt/data/ai-platform/scripts/platform-stop.sh  
sleep 10  
sudo bash /mnt/data/ai-platform/scripts/platform-start.sh

\# Nuclear option — rebuild single service  
cd /mnt/data/ai-platform/docker  
docker compose \-f docker-compose.\<service\>.yml down \-v  \# ⚠️ destroys volume  
docker compose \-f docker-compose.\<service\>.yml up \-d

\# Restore from backup  
tar \-xzf /mnt/data/ai-platform/backups/\<timestamp\>.tar.gz \-C /tmp/restore  
\# Restore PostgreSQL  
cat /tmp/restore/\*/postgres-full.sql | docker exec \-i ai-platform-postgres psql \-U postgres  
\# Restore configs  
cp \-r /tmp/restore/\*/config/\* /mnt/data/ai-platform/config/  
\# Restart all  
sudo bash /mnt/data/ai-platform/scripts/platform-restart.sh

---

## **Section 30: Architecture & Network Diagrams**

### **30.1 Full Architecture Diagram**

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
    │  DIFY API \+ Worker │         │                           │  
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

### **30.2 Docker Network Topology**

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

### **30.3 Data Flow: User Chat Request**

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

### **30.4 Data Flow: Dify RAG Pipeline**

User sends query to Dify chatbot  
         │  
         ▼  
    Dify Web → Dify API  
         │  
         ├── 1\. Generate embedding  
         │      │  
         │      ▼  
         │   LiteLLM → Ollama (nomic-embed-text)  
         │      │  
         │      ▼  
         │   Embedding vector returned  
         │  
         ├── 2\. Vector search  
         │      │  
         │      ▼  
         │   Qdrant (similarity search)  
         │      │  
         │      ▼  
         │   Relevant document chunks returned  
         │  
         ├── 3\. Build prompt with context  
         │      │  
         │      ▼  
         │   System prompt \+ retrieved chunks \+ user query  
         │  
         └── 4\. LLM completion  
                │  
                ▼  
           LiteLLM → Ollama (llama3.1 or chosen model)  
                │  
                ▼  
           Streaming response → User

---

## **Section 31: Complete Port Reference**

### **31.1 External Ports (Exposed to Host)**

Copy table

| Port | Service | Protocol | Mode |
| ----- | ----- | ----- | ----- |
| 80 | Caddy (HTTP redirect) | TCP | Always |
| 443 | Caddy → Dify Web | TCP | Always |
| 5678 | Caddy → n8n | TCP | IP mode |
| 3001 | Caddy → Open WebUI | TCP | IP mode |
| 4000 | Caddy → LiteLLM | TCP | IP mode |
| 3002 | Caddy → Flowise | TCP | IP mode (optional) |
| 3003 | Caddy → Grafana | TCP | IP mode (optional) |
| 11434 | Ollama (host) | TCP | Always (localhost) |

### **31.2 Internal Ports (Container-to-Container)**

Copy table

| Port | Service | Network |
| ----- | ----- | ----- |
| 5432 | PostgreSQL | ai-backend |
| 6379 | Redis | ai-backend |
| 6333 | Qdrant HTTP | ai-backend |
| 6334 | Qdrant gRPC | ai-backend |
| 3567 | SuperTokens | ai-backend |
| 4000 | LiteLLM | ai-platform |
| 5001 | Dify API | ai-platform |
| 5002 | Dify Worker (internal) | ai-backend |
| 3000 | Dify Web | ai-platform |
| 8194 | Dify Sandbox | ai-backend |
| 5678 | n8n | ai-platform |
| 8080 | Open WebUI | ai-platform |
| 3000 | Flowise | ai-platform |
| 9090 | Prometheus | ai-backend |
| 3000 | Grafana | ai-platform |

### **31.3 Localhost-Bound Ports (127.0.0.1 only)**

These ports are bound for health checks and direct admin access, NOT exposed externally:

Copy table

| Port | Service |
| ----- | ----- |
| 127.0.0.1:5432 | PostgreSQL |
| 127.0.0.1:6379 | Redis |
| 127.0.0.1:6333 | Qdrant |
| 127.0.0.1:5001 | Dify API |
| 127.0.0.1:9090 | Prometheus |
| 127.0.0.1:3003 | Grafana (direct) |

---

## **Section 32: Complete Environment Variable Reference**

### **32.1 Infrastructure Variables**

Copy table

| Variable | Example | Used By |
| ----- | ----- | ----- |
| `POSTGRES_HOST` | `postgres` | All services |
| `POSTGRES_PORT` | `5432` | All services |
| `POSTGRES_USER` | `postgres` | PostgreSQL |
| `POSTGRES_PASSWORD` | `(generated)` | PostgreSQL, all services |
| `REDIS_HOST` | `redis` | Dify, LiteLLM |
| `REDIS_PORT` | `6379` | Dify, LiteLLM |
| `REDIS_PASSWORD` | `(generated)` | Redis, Dify, LiteLLM |
| `QDRANT_HOST` | `qdrant` | Dify |
| `QDRANT_PORT` | `6333` | Dify |
| `QDRANT_API_KEY` | `(generated)` | Qdrant, Dify |

### **32.2 Service-Specific Database Variables**

Copy table

| Variable | Example |
| ----- | ----- |
| `DIFY_DB_NAME` | `dify` |
| `DIFY_DB_USER` | `dify_user` |
| `DIFY_DB_PASSWORD` | `(generated)` |
| `N8N_DB_NAME` | `n8n` |
| `N8N_DB_USER` | `n8n_user` |
| `N8N_DB_PASSWORD` | `(generated)` |
| `LITELLM_DB_NAME` | `litellm` |
| `LITELLM_DB_USER` | `litellm_user` |
| `LITELLM_DB_PASSWORD` | `(generated)` |
| `SUPERTOKENS_DB_NAME` | `supertokens` |
| `SUPERTOKENS_DB_USER` | `supertokens_user` |
| `SUPERTOKENS_DB_PASSWORD` | `(generated)` |
| `FLOWISE_DB_NAME` | `flowise` |
| `FLOWISE_DB_USER` | `flowise_user` |
| `FLOWISE_DB_PASSWORD` | `(generated)` |

### **32.3 Secret Keys & Tokens**

Copy table

| Variable | Length | Used By |
| ----- | ----- | ----- |
| `DIFY_SECRET_KEY` | 42 chars | Dify API |
| `LITELLM_MASTER_KEY` | 32 chars (`sk-` prefix) | LiteLLM Admin |
| `N8N_ENCRYPTION_KEY` | 32 chars | n8n credential encryption |
| `FLOWISE_SECRET_KEY` | 32 chars | Flowise |
| `SUPERTOKENS_API_KEY` | 32 chars | SuperTokens |
| `GRAFANA_ADMIN_PASSWORD` | 24 chars | Grafana |
| `OPEN_WEBUI_SECRET_KEY` | 32 chars | Open WebUI JWT |

### **32.4 Cloud Provider Variables (Optional)**

Copy table

| Variable | Used By |
| ----- | ----- |
| `OPENAI_API_KEY` | LiteLLM → OpenAI |
| `ANTHROPIC_API_KEY` | LiteLLM → Anthropic |
| `GOOGLE_API_KEY` | LiteLLM → Google AI |
| `MISTRAL_API_KEY` | LiteLLM → Mistral |
| `GROQ_API_KEY` | LiteLLM → Groq |
| `TOGETHER_API_KEY` | LiteLLM → Together AI |

### **32.5 Platform Configuration Variables**

Copy table

| Variable | Example | Purpose |
| ----- | ----- | ----- |
| `DOMAIN_MODE` | `ip` or `domain` | Routing strategy |
| `HOST_IP` | `192.168.1.100` | Server IP |
| `DOMAIN_NAME` | `ai.example.com` | Base domain |
| `URL_PROTOCOL` | `https` | HTTP or HTTPS |
| `SSL_MODE` | `selfsigned` / `letsencrypt` | TLS strategy |
| `ADMIN_EMAIL` | `admin@example.com` | Let's Encrypt \+ alerts |
| `OLLAMA_BASE_URL` | `http://host.docker.internal:11434` | Ollama endpoint |
| `PRIMARY_MODEL` | `llama3.1:8b` | Default chat model |
| `EMBEDDING_MODEL` | `nomic-embed-text:latest` | Default embedding model |

---

## **Section 33: Update & Maintenance Procedures**

### **33.1 Updating a Single Service**

cd /mnt/data/ai-platform/docker

\# Pull new image  
docker compose \-f docker-compose.\<service\>.yml pull

\# Recreate with new image  
docker compose \-f docker-compose.\<service\>.yml up \-d

\# Verify health  
docker ps \--filter "name=ai-platform-\<service\>"

### **33.2 Updating Ollama**

\# Update Ollama binary  
curl \-fsSL https://ollama.ai/install.sh | sh

\# Restart service  
sudo systemctl restart ollama

\# Verify  
ollama \--version

\# Models persist — no re-download needed  
ollama list

### **33.3 Updating All Images**

cd /mnt/data/ai-platform/docker

\# Stop all (reverse order)  
sudo bash /mnt/data/ai-platform/scripts/platform-stop.sh

\# Pull all new images  
for f in docker-compose.\*.yml; do  
    docker compose \-f "$f" pull  
done

\# Start all (correct order)  
sudo bash /mnt/data/ai-platform/scripts/platform-start.sh

### **33.4 Updating Platform Configuration**

\# Edit configuration  
nano /mnt/data/ai-platform/config/litellm/config.yaml  \# Example: add model

\# Restart affected service  
cd /mnt/data/ai-platform/docker  
docker compose \-f docker-compose.litellm.yml restart

\# Or for .env changes — must recreate  
docker compose \-f docker-compose.\<service\>.yml up \-d

### **33.5 Database Maintenance**

\# PostgreSQL vacuum (run weekly)  
docker exec ai-platform-postgres psql \-U postgres \-c "VACUUM ANALYZE;"

\# Check database sizes  
docker exec ai-platform-postgres psql \-U postgres \-c \\  
    "SELECT datname, pg\_size\_pretty(pg\_database\_size(datname)) FROM pg\_database ORDER BY pg\_database\_size(datname) DESC;"

\# Backup before major updates  
sudo bash /mnt/data/ai-platform/scripts/platform-backup.sh

### **33.6 Disk Space Management**

\# Check Docker disk usage  
docker system df

\# Remove unused images (safe)  
docker image prune \-f

\# Remove unused volumes (⚠️ CAREFUL — only if you know they're unused)  
docker volume prune \-f

\# Check Ollama model sizes  
du \-sh \~/.ollama/models/blobs/\*

\# Remove an Ollama model  
ollama rm \<model-name\>

---

## **Section 34: Security Hardening Notes**

### **34.1 Default Security Posture**

The platform deploys with these security measures:

1. **No default passwords** — all credentials randomly generated  
2. **Credentials file restricted** — `chmod 600` on `credentials.env`  
3. **Internal ports localhost-bound** — databases not exposed externally  
4. **Docker networks isolated** — backend services unreachable from frontend network directly  
5. **TLS enabled** — self-signed by default, Let's Encrypt optional  
6. **UFW firewall configured** — only required ports open

### **34.2 Additional Hardening (Post-Install)**

\# Restrict SSH to key-only  
sudo sed \-i 's/\#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd\_config  
sudo systemctl restart sshd

\# Enable automatic security updates  
sudo apt install unattended-upgrades \-y  
sudo dpkg-reconfigure \-plow unattended-upgrades

\# Set up fail2ban  
sudo apt install fail2ban \-y  
sudo systemctl enable fail2ban

\# Restrict Docker socket  
sudo chmod 660 /var/run/docker.sock

\# Review open ports periodically  
sudo ss \-tlnp | grep \-v 127.0.0.1

### **34.3 API Key Security**

IMPORTANT: LiteLLM Master Key grants full access to all models.

\- Never expose port 4000 without authentication  
\- Caddy proxies LiteLLM — but does NOT add auth by default  
\- For production: add basic auth to Caddy for /api/\* routes  
\- Rotate the master key periodically:  
    1\. Generate new key  
    2\. Update credentials.env  
    3\. Update litellm config.yaml  
    4\. Restart litellm  
    5\. Update Dify, n8n, Open WebUI connections

---

## **Section 35: Final Notes & Design Decisions**

### **35.1 Why Separate Docker Compose Files?**

Each service gets its own compose file rather than one monolithic file because:

1. **Independent lifecycle** — restart/update one service without touching others  
2. **Selective deployment** — enable/disable optional services cleanly  
3. **Debugging** — isolate issues to a single compose file  
4. **Resource management** — control memory limits per service  
5. **Order control** — deploy infrastructure before applications

### **35.2 Why LiteLLM as the AI Gateway?**

LiteLLM provides a single OpenAI-compatible endpoint that:

1. Routes to 100+ LLM providers with one API format  
2. Handles retries, fallbacks, and load balancing  
3. Tracks token usage and cost per model  
4. Caches responses in Redis  
5. Exposes Prometheus metrics  
6. Means all downstream services (Dify, n8n, Open WebUI) use the same endpoint format

### **35.3 Why Ollama on Host (Not in Docker)?**

1. **Direct GPU access** — no NVIDIA Container Toolkit complexity  
2. **Shared across all containers** — one Ollama serves everything via `host.docker.internal`  
3. **Model persistence** — models survive container rebuilds  
4. **Simpler updates** — `curl install.sh` vs rebuilding Docker image  
5. **Memory management** — Ollama manages GPU VRAM directly without Docker overhead

### **35.4 Why Caddy (Not Nginx/Traefik)?**

1. **Automatic HTTPS** — Let's Encrypt built-in, zero config  
2. **Simple config** — Caddyfile vs nginx.conf complexity  
3. **Self-signed TLS** — `tls internal` for IP-based installs  
4. **Low resource usage** — single binary, minimal RAM  
5. **HTTP/3 support** — built-in, no modules needed

### **35.5 Hardware Tier Design Philosophy**

The three tiers (minimum, recommended, production) exist because:

* **Minimum (16GB)**: Runs small models (7B). Good for testing and light personal use  
* **Recommended (32GB)**: Runs medium models (13B). Good for small teams  
* **Production (64GB+)**: Runs large models (70B+) or multiple concurrent models. Good for organizations

GPU tiers follow the same logic — VRAM determines max model size that fits entirely in GPU memory, avoiding slow CPU fallback.

### **35.6 File Tree — Final State**

/mnt/data/ai-platform/  
├── config/  
│   ├── master.env                          \# All platform variables  
│   ├── credentials.env                     \# All secrets (chmod 600\)  
│   ├── hardware-profile.env                \# Detected hardware  
│   ├── caddy/  
│   │   └── Caddyfile                       \# Reverse proxy config  
│   ├── litellm/  
│   │   └── config.yaml                     \# Model routing config  
│   ├── postgres/  
│   │   └── init-databases.sql              \# Multi-DB init script  
│   ├── redis/  
│   │   └── redis.conf                      \# Redis configuration  
│   ├── prometheus/  
│   │   └── prometheus.yml                  \# Scrape targets  
│   └── grafana/  
│       ├── provisioning/  
│       │   └── datasources/  
│       │       └── prometheus.yml          \# Auto-provision datasource  
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
│   ├── docker-compose.flowise.yml          \# (if enabled)  
│   ├── docker-compose.caddy.yml  
│   ├── docker-compose.prometheus.yml       \# (if enabled)  
│   └── docker-compose.grafana.yml          \# (if enabled)  
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

---

## **END OF MASTER DOCUMENT**

═══════════════════════════════════════════════════════════════  
  AI PLATFORM — COMPLETE DEPLOYMENT MASTER DOCUMENT  
  Total Sections: 35  
  Total Scripts: 4  
  Total Services: 15 (12 core \+ 3 optional)  
  Target OS: Ubuntu 22.04 / 24.04 LTS  
  Author: AI Platform Deployment Project  
  Version: 1.0.0  
═══════════════════════════════════════════════════════════════


