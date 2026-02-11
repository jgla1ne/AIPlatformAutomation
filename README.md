# **AIPlatformAutomation — Full Solution v76.5.0**

`# AIPlatformAutomation`

`## Overview`  
`AIPlatformAutomation provides a **fully modular, dockerized AI platform** enabling:`

`- Internal LLMs (Ollama, LiteLLM, AnythingLLM)`  
`- External LLM providers (Google Gemini, OpenRouter, Groq, OpenAI)`  
`- AI applications (Dify, ComfyUI, OpenWebUI, Flowise, OpenClaw UI)`  
`- Vector databases (Chroma, Qdrant)`  
`- Monitoring stack (Grafana, Prometheus, ELK, Portainer)`  
`- Secure internal networking via Tailscale`  
`- Private embeddings and credentials management`  
`- Optional Google Drive sync`  
`- Signal integration for messaging`

`The platform is designed for **fully autonomous deployment** while offering a **rich interactive UX** with numbered selections, retry loops, icons, and post-step summaries.`

`## Key Outcomes`

`- Fully autonomous AI platform.`  
`- On-premise embeddings for private data and synced data from gdrive in /mnt/data/gdrive`  
`- Modular stack for AI apps, internal and external LLMs.`  
`- customizable routing strategy internal/external via litellm,`  
`- Secure networking via Tailscale and optional public proxy.`  
`- Comprehensive logging, health checks, and interactive UX.`

## \#\# Expected behavior

- Clean slate system, reset via script 0  
- Step 1 to install required dependencies, collect all user variables in a nice UX flow interactively  
- Step 2 deploys each service, performs health checks, display a summary of all services working  
- Step 3 allow to re-configure a service (re-pair with signal, enter new auth key for gdrive, add a llm provider, change litellm query routing etc  
- \- step 4 allows the user to add a new service to the stack and re-deploy

After step2, most urls must be accessible (unless failed services which can be fixed in step3). From there:

* A user will use openclaw to interrogate data and perfroam actions via channels  
* A user will use anything llm to work on the same embeddings  
* A user will use dify or any programmatic agentic flow that’s connected to the embeddings

Any queries will be routed locally first or externally (based on complexity and maybe more fine tuning later)

→\> the stack is DOCKERIZED as much as possible and automated and modular. Whilst scripts runs as sudo, they need to retrieve the $PID of the logged in user, and use this for paths, chmod operations etc. This stack may run tomorrow with a different OS, GPU enabled and potentially different EBS volumes, which is why script 1 should take care of mountain the device into /mnt/data, and script 0 deletes and unmount.

\#\# KEy architecture principles

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

## **Section 4: Script Inventory & Flow**

### **4.1 Execution Order**

┌──────────────────┐  
│  0-complete-cleanup.sh     │  Purge & reset (optional, for re-installs)  
└────────┬─────────┘  
         ▼  
┌──────────────────┐  
│ 1-setup-system.sh   │  Hardware, Docker, NVIDIA, Ollama, validation  
└────────┬─────────┘  
         ▼  
┌──────────────────┐  
│  2-deploy-services.sh │  Questionnaire → generate configs → deploy containers  
└────────┬─────────┘  
         ▼  
┌──────────────────┐  
│  3-configure-services.sh │  Wait healthy → configure Dify, n8n,signal WebUI etc via APIs  
└────────┬─────────┘  
         ▼  
┌──────────────────┐  
│ 4-add-service.sh │  Optional: extra services, models, integrations, remove a service  
└────────┴─────────┘

`*** Target Folder Structure :` 

## **MODULAR FILE STRUCTURE (CORRECTED)**

/mnt/data/  
├── compose/                           \# Individual service compose files  
│   ├── nginx.yml                      \# If Nginx selected  
│   ├── traefik.yml                    \# If Traefik selected  
│   ├── caddy.yml                      \# If Caddy selected  
│   ├── postgres.yml                   \# Core infrastructure  
│   ├── redis.yml  
│   ├── qdrant.yml                     \# If Qdrant selected  
│   ├── weaviate.yml                   \# If Weaviate selected  
│   ├── milvus.yml                     \# If Milvus selected  
│   ├── ollama.yml                     \# LLM engines  
│   ├── litellm.yml  
│   ├── localai.yml                    \# If selected  
│   ├── openwebui.yml                  \# AI platforms (if selected)  
│   ├── anythingllm.yml  
│   ├── dify-api.yml                   \# Dify split into 3 services  
│   ├── dify-worker.yml  
│   ├── dify-web.yml  
│   ├── n8n.yml  
│   ├── flowise.yml  
│   ├── signal-api.yml                 \# Integrations (if selected)  
│   ├── gdrive.yml  
│   ├── langfuse.yml                   \# Monitoring (if selected)  
│   ├── prometheus.yml  
│   ├── grafana.yml  
│   ├── loki.yml  
│   ├── promtail.yml  
│   ├── cadvisor.yml  
│   └── node-exporter.yml  
│  
├── env/                               \# Individual service environment files  
│   ├── global.env                     \# Shared variables (domain, IPs, etc.)  
│   ├── nginx.env  
│   ├── traefik.env  
│   ├── caddy.env  
│   ├── postgres.env  
│   ├── redis.env  
│   ├── qdrant.env  
│   ├── ollama.env  
│   ├── litellm.env                    \# Contains all provider API keys  
│   ├── openwebui.env  
│   ├── anythingllm.env  
│   ├── dify.env                       \# Shared by all 3 Dify services  
│   ├── n8n.env  
│   ├── flowise.env  
│   ├── signal-api.env  
│   ├── gdrive.env  
│   ├── langfuse.env  
│   └── monitoring.env                 \# Shared by Prometheus, Grafana, Loki  
│  
├── config/                            \# Service-specific configuration files  
│   ├── nginx/  
│   │   ├── nginx.conf                 \# Main config  
│   │   ├── ssl/                       \# SSL certificates  
│   │   │   ├── dhparam.pem  
│   │   │   └── letsencrypt/  
│   │   └── sites/                     \# Per-service configs  
│   │       ├── openwebui.conf  
│   │       ├── anythingllm.conf  
│   │       ├── dify.conf  
│   │       ├── n8n.conf  
│   │       ├── flowise.conf  
│   │       ├── grafana.conf  
│   │       └── langfuse.conf  
│   │  
│   ├── traefik/  
│   │   ├── traefik.yml                \# Static config  
│   │   ├── acme.json                  \# Let's Encrypt certificates  
│   │   └── dynamic/                   \# Dynamic configs  
│   │       ├── routers.yml  
│   │       └── middlewares.yml  
│   │  
│   ├── caddy/  
│   │   ├── Caddyfile                  \# Main config (auto-HTTPS)  
│   │   └── data/                      \# Caddy data dir  
│   │  
│   ├── litellm/  
│   │   └── config.yaml                \# Routing strategy \+ model definitions  
│   │  
│   ├── postgres/  
│   │   └── init.sql                   \# Create all databases \+ users  
│   │  
│   ├── redis/  
│   │   └── redis.conf                 \# Redis configuration  
│   │  
│   ├── prometheus/  
│   │   └── prometheus.yml             \# Scrape configs for all services  
│   │  
│   ├── grafana/  
│   │   ├── datasources.yml            \# Prometheus, Loki  
│   │   └── dashboards/                \# Pre-configured dashboards  
│   │       ├── docker.json  
│   │       ├── llm-metrics.json  
│   │       ├── n8n.json  
│   │       ├── dify.json  
│   │       └── system.json  
│   │  
│   ├── loki/  
│   │   └── loki-config.yaml  
│   │  
│   ├── promtail/  
│   │   └── promtail-config.yaml       \# Log collection from all containers  
│   │  
│   ├── gdrive/  
│   │   └── credentials.json           \# Service account key (if selected)  
│   │  
│   └── signal-api/  
│       └── signal-config.json  
│  
├── metadata/                          \# Script 1 outputs (used by script 2\)  
│   ├── selected\_services.json         \# List of services user selected  
│   ├── configuration.json             \# All user inputs & generated secrets  
│   ├── deployment\_plan.json           \# Ordered deployment plan  
│   ├── proxy\_config.json              \# Proxy type & SSL settings  
│   ├── network\_config.json            \# Domain, IPs, DNS resolution  
│   ├── directory\_structure.json       \# Paths, symlinks  
│   ├── vectordb\_choice.json           \# Which vector DB was chosen  
│   ├── ollama\_models.json             \# Models to download  
│   ├── providers.json                 \# External LLM providers configured  
│   ├── routing\_strategy.json          \# LiteLLM routing logic  
│   ├── signal\_config.json             \# Signal pairing method & number  
│   ├── gdrive\_config.json             \# GDrive auth method & credentials  
│   ├── port\_check.json                \# Port availability results  
│   └── deployment\_summary.json        \# Human-readable summary  
│  
├── data/                              \# Actual persistent data  
│   ├── postgres/                      \# Database files  
│   ├── redis/                         \# Redis persistence  
│   ├── qdrant/                        \# Vector DB storage  
│   ├── ollama/models/                 \# Downloaded Ollama models  
│   ├── litellm/                       \# LiteLLM database  
│   ├── n8n/                           \# N8N workflows & executions  
│   ├── dify/                          \# Dify knowledge base & uploads  
│   ├── anythingllm/documents/         \# AnythingLLM documents  
│   ├── flowise/                       \# Flowise flows  
│   ├── grafana/                       \# Grafana dashboards & plugins  
│   ├── prometheus/                    \# Prometheus TSDB  
│   ├── loki/                          \# Loki chunks  
│   └── langfuse/                      \# Langfuse traces  
│  
└── backups/                           \# Backup location  
    └── pre-install-YYYYMMDD-HHMMSS.tar.gz

Script 2 will:  
1\. Read metadata/\*.json files  
2\. Merge compose/\*.yml files into final docker-compose.yml  
3\. Merge env/\*.env files into final .env  
4\. Copy config/\* to appropriate locations  
5\. Deploy services based on deployment\_plan.json  
`---`

`## Network Architecture`

     `┌─────────────┐`  
      `│ Public IP 80`    
      `│ Proxy/SSL 443│`  
      `└─────┬──────┘`  
            `│`  
      `┌─────▼─────┐`  
      `│  Tailscale  │`  
      `│ IP :8443 )  │`  
      `└─────┬─────┘`  
            `│`

┌──────────────┴───────────────┐  
 │ Core LLMs │  
 │ Ollama | LiteLLM | AnythingLLM│  
 └──────────────┬───────────────┘  
 │  
 ┌──────────────▼───────────────┐  
 │ Vector DB │  
 │ Chroma | Qdrant │  
 └──────────────┬───────────────┘  
 │  
 ┌──────────────▼───────────────┐  
 │ AI Applications │  
 │ Dify | ComfyUI | OpenWebUI │  
 │ Flowise | OpenClaw UI │  
 └──────────────┬───────────────┘  
 │  
 ┌──────────────▼───────────────┐  
 │ Optional Monitoring │  
 │ Grafana | Prometheus | ELK │  
 │ Portainer │  
 └──────────────────────────────┘

\#\# Section 5: Script 0 — Cleanup System

\#\#\# 5.1 Purpose

\`0-cleanup.sh\` removes all traces of a previous installation so the system can be re-provisioned cleanly. It is \*\*optional\*\* — only needed when re-installing or resetting (to validate entire script consistency).

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
Phase 6 : apt purge, remove cache, docker purge, reboot

Script will handle re-creating all environment and directory  
Phase 1: Recreate Directory Structure  
  ├── mkdir \-p /mnt/data/ai-platform/{config,docker,data,logs,scripts,backups}  
  └── chown \-R ${SUDO\_USER:- $ USER}: $ {SUDO\_USER:-$USER} /mnt/data/ai-platform/

### **5.5 What It Does NOT Remove**

* Docker Engine itself (Script 1 manages this)  
* NVIDIA drivers or Container Toolkit (Script 1 manages this)  
* Ollama binary (Script 1 manages this)  
* System packages  
* User accounts

## **SCRIPT 1: SETUP SYSTEM**

### **Intent**

Prepare the complete foundation for deployment WITHOUT starting any AI services. This script collects all configuration, allocates ports, creates directory structures, and generates the master `.env` file.

### **Key Responsibilities**

#### **1\. System Validation**

* Root privileges check  
* Docker installation verification  
* Docker daemon running check  
* GPU detection (NVIDIA/AMD/None)

#### **2\. User & Permissions**

* Add user to `docker` group  
* Automate session refresh (`newgrp docker` or logout warning)  
* Create service user: `ai-user` (non-root for containers)  
* Mount `/mnt/data` (persistent storage for large datasets)  
* Create `/mnt/data/gdrive/` for rsync target and all directory structure for all stacks

### **Success Definition**

* ✅ All directories created  
* ✅ `/mnt/data` mounted and accessible  
* ✅ All ports allocated (no conflicts)  
* ✅ `.env` file generated (pure text, no ANSI codes)  
* ✅ `credentials.txt` prepared (populated in Script 2\)  
* ✅ Reverse proxy config files created (not deployed)  
* ✅ User confirmed configuration summary  
* ✅ Docker group permissions active  
* ✅ NO containers running yet

`UI EXPECTED OUTPUTS` 

`Script 1 expected output :`   
╔══════════════════════════════════════════════════════════════════╗  
║                                                                  ║  
║          AI Platform Automation Setup v3.0                       ║  
║          Complete Installation Wizard                            ║  
║                                                                  ║  
╚══════════════════════════════════════════════════════════════════╝

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  
🔍 STEP 0/13: PRE-FLIGHT CHECK  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Checking system requirements...

✓ Docker version: 24.0.7  
✓ Docker Compose version: 2.23.0  
✓ Available disk space: 250 GB (/mnt/data)  
✓ Available RAM: 16 GB  
✓ User in docker group: yes

Checking port availability...

Port Check Results:  
  ✓ 80    \[FREE\]  \- HTTP (Reverse Proxy)  
  ✓ 443   \[FREE\]  \- HTTPS (Reverse Proxy)  
  ✓ 3000  \[FREE\]  \- OpenWebUI / Grafana / Langfuse  
  ✓ 3001  \[FREE\]  \- AnythingLLM  
  ✓ 5678  \[FREE\]  \- N8N  
  ✓ 6333  \[FREE\]  \- Qdrant  
  ✓ 6334  \[FREE\]  \- Qdrant GRPC  
  ✓ 8080  \[FREE\]  \- Dify  
  ✓ 11434 \[FREE\]  \- Ollama  
  ✗ 5432  \[IN USE\] \- PostgreSQL (pid: 1234, /usr/bin/postgres)  
  ✓ 6379  \[FREE\]  \- Redis  
  ✓ 4000  \[FREE\]  \- LiteLLM  
  ✓ 9090  \[FREE\]  \- Prometheus

⚠ WARNING: Port 5432 is already in use by system PostgreSQL

Options:  
  1\) Stop system PostgreSQL and continue  
  2\) Use alternative port (e.g., 5433\)  
  3\) Abort installation

Select option \[1-3\]: 2

✓ PostgreSQL will use port 5433  
✓ All required ports are available

Saving port check results...  
✓ Saved: /mnt/data/metadata/port\_check.json

Continue with installation? \[Y/n\]: y

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  
🌐 STEP 1/13: REVERSE PROXY & SSL CONFIGURATION  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Do you want to use a reverse proxy? \[Y/n\]: y

Select reverse proxy:  
  1\) Nginx (Traditional \- Reliable, manual SSL config)  
  2\) Traefik (Modern \- Auto SSL with Docker labels)  
  3\) Caddy (Automatic \- Zero-config HTTPS)  
  4\) None (Direct port access \- Not recommended)  
    
Select option \[1-4\]: 3

✓ Caddy selected

Caddy Features:  
  • Automatic HTTPS with Let's Encrypt  
  • HTTP/2 and HTTP/3 (QUIC) support  
  • Simple configuration (Caddyfile)  
  • Auto certificate renewal  
  • No manual SSL setup needed\!

SSL/TLS Configuration:  
  Since Caddy handles SSL automatically, we only need:  
    
  1\) Automatic Let's Encrypt (Requires valid domain)  
  2\) Self-signed certificates (Testing/Internal)  
  3\) No SSL \- HTTP only (Local development)  
    
Select option \[1-3\]: 1

✓ Automatic Let's Encrypt SSL selected

Email for Let's Encrypt notifications: admin@example.com  
✓ Email saved: admin@example.com

Generating Caddy configuration...  
✓ Created: /mnt/data/compose/caddy.yml  
✓ Created: /mnt/data/env/caddy.env  
✓ Created: /mnt/data/config/caddy/Caddyfile  
✓ Saved: /mnt/data/metadata/proxy\_config.json

Caddy will be configured with:  
  • HTTP (80) → HTTPS (443) auto-redirect  
  • Let's Encrypt certificates (auto-renewed)  
  • HTTP/2 enabled  
  • Subpath routing for all services

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  
🏠 STEP 2/13: DOMAIN & NETWORK CONFIGURATION  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Enter your domain or subdomain: ai.example.com

Resolving DNS...  
  ⏳ Querying DNS servers for ai.example.com...  
  ✓ A record found: 203.0.113.45  
    
Detecting public IP...  
  ⏳ Checking https://api.ipify.org...  
  ✓ Public IP detected: 203.0.113.45  
    
DNS Validation:  
  ✓ Domain resolves to: 203.0.113.45  
  ✓ Public IP matches:  203.0.113.45  
  ✓ DNS propagation complete  
  ✓ Domain is accessible from internet

Subdomain Detection:  
  Base domain: example.com  
  Subdomain: ai  
  TLD: com  
    
Services will be available at:  
  • OpenWebUI:    https://ai.example.com/openwebui  
  • AnythingLLM:  https://ai.example.com/anythingllm  
  • N8N:          https://ai.example.com/n8n  
  • Dify:         https://ai.example.com/dify  
  • Flowise:      https://ai.example.com/flowise  
  • Grafana:      https://ai.example.com/grafana  
  • Langfuse:     https://ai.example.com/langfuse

Configure individual subdomains instead?   
(e.g., n8n.example.com, dify.example.com) \[y/N\]: n

✓ Single domain with subpaths confirmed

Detect LAN IP for local access? \[Y/n\]: y

⏳ Detecting local network...  
✓ LAN IP detected: 192.168.1.100  
✓ Network interface: eth0

Local access will also be available:  
  • http://192.168.1.100:3000 (OpenWebUI)  
  • http://192.168.1.100:3001 (AnythingLLM)  
  • http://192.168.1.100:5678 (N8N)  
  • http://192.168.1.100:8080 (Dify)  
  • etc.

Saving network configuration...  
✓ Saved: /mnt/data/metadata/network\_config.json

Network Config Summary:  
  Domain:     ai.example.com  
  Public IP:  203.0.113.45  
  LAN IP:     192.168.1.100  
  Proxy:      Caddy (auto HTTPS)  
  SSL Email:  admin@example.com

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  
📁 STEP 3/13: INSTALLATION DIRECTORY  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Current working directory: /home/user/AIPlatformAutomation

Validating directory structure...

Repository structure:  
  ✓ Base directory:   /home/user/AIPlatformAutomation  
  ✓ Scripts location: /home/user/AIPlatformAutomation/scripts  
  ✓ Config location:  /home/user/AIPlatformAutomation/config

Data directory (/mnt/data) validation:  
  ⏳ Checking /mnt/data...  
  ✓ Path exists  
  ✓ Writable by current user  
  ✓ 230 GB available (225 GB free)

Creating modular directory structure in /mnt/data...  
  ✓ Created: /mnt/data/compose/  
  ✓ Created: /mnt/data/env/  
  ✓ Created: /mnt/data/config/  
  ✓ Created: /mnt/data/metadata/  
  ✓ Created: /mnt/data/data/  
  ✓ Created: /mnt/data/backups/

Create symlink from ./data to /mnt/data/data? \[Y/n\]: y  
✓ Symlink created: ./data → /mnt/data/data

Saving directory structure...  
✓ Saved: /mnt/data/metadata/directory\_structure.json

Directory Structure:  
  Base:           /home/user/AIPlatformAutomation  
  Scripts:        ./scripts/  
  Compose Files:  /mnt/data/compose/  
  Env Files:      /mnt/data/env/  
  Config Files:   /mnt/data/config/  
  Metadata:       /mnt/data/metadata/  
  Persistent Data:/mnt/data/data/  
  Backups:        /mnt/data/backups/

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  
📦 STEP 4/13: CORE INFRASTRUCTURE  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Select core infrastructure services:

  DATABASE:  
  \[✓\] 1\. PostgreSQL (Required for: N8N, Dify, Flowise, LiteLLM, Langfuse)  
    
  CACHE/QUEUE:  
  \[✓\] 2\. Redis (Required for: N8N queues, Dify cache, AnythingLLM sessions)  
    
  VECTOR DATABASE:  
  \[ \] 3\. Qdrant (Recommended \- Easiest setup, Rust-based, fast)  
  \[ \] 4\. Weaviate (Advanced \- GraphQL API, schema validation)  
  \[ \] 5\. Milvus (Enterprise \- Highest performance, complex setup)  
    
⚠ Note: PostgreSQL and Redis are required and pre-selected  
         You must choose ONE vector database

Select vector database \[3-5\]: 3

✓ Qdrant selected

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

POSTGRESQL CONFIGURATION:

Databases to create:  
  • n8n (for N8N workflows)  
  • dify (for Dify platform)  
  • flowise (for Flowise flows)  
  • litellm (for LiteLLM proxy)  
  • langfuse (for Langfuse traces)

Root password (auto-generated): postgres\_\*\*\*\*\*\*\*\*\*\*\*\*  
✓ Strong password generated

Per-database users will be created with individual passwords  
Port: 5433 (avoiding conflict with system PostgreSQL)

Generating files...  
✓ Created: /mnt/data/compose/postgres.yml  
✓ Created: /mnt/data/env/postgres.env  
✓ Created: /mnt/data/config/postgres/init.sql

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

REDIS CONFIGURATION:

Redis password (auto-generated): redis\_\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*  
✓ Strong password generated

Configuration:  
  • Max memory: 256 MB  
  • Eviction policy: allkeys-lru (Least Recently Used)  
  • Persistence: AOF \+ RDB (for durability)  
  • Port: 6379

Generating files...  
✓ Created: /mnt/data/compose/redis.yml  
✓ Created: /mnt/data/env/redis.env  
✓ Created: /mnt/data/config/redis/redis.conf

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

QDRANT CONFIGURATION:

API Key (auto-generated): qdrant\_\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*  
✓ Strong API key generated

Configuration:  
  • HTTP API Port: 6333  
  • GRPC Port: 6334 (enabled)  
  • Anonymous access: Disabled (API key required)  
  • Storage: /mnt/data/data/qdrant/storage  
  • Snapshots: /mnt/data/data/qdrant/snapshots

Generating files...  
✓ Created: /mnt/data/compose/qdrant.yml  
✓ Created: /mnt/data/env/qdrant.env  
✓ Saved: /mnt/data/metadata/vectordb\_choice.json

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  
🤖 STEP 5/13: LLM ENGINES  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Select LLM runtime engines:

  LOCAL ENGINES:  
  \[ \] 1\. Ollama (Local LLM runtime \- Recommended)  
  \[ \] 2\. LocalAI (Alternative to Ollama)  
    
  PROXY/ROUTER:  
  \[ \] 3\. LiteLLM (Multi-provider proxy \+ routing)  
    
  \[ \] 0\. Select All  
    
Enter numbers (e.g., '1 3'): 1 3

✓ Ollama selected  
✓ LiteLLM selected

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

OLLAMA CONFIGURATION:

Fetching available models from Ollama library...

⏳ Connecting to https://ollama.com/api/tags...  
✓ Successfully connected  
✓ Found 347 available models

Filter by category:  
  1\) All models (347)  
  2\) Recommended for production (12)  
  3\) Chat models only (156)  
  4\) Code models (42)  
  5\) Embedding models (18)  
  6\) Vision models (23)  
    
Select filter \[1-6\]: 2

RECOMMENDED PRODUCTION MODELS:

  LIGHTWEIGHT (\< 2GB):  
  \[ \] 1\. llama3.2:1b          (1.3 GB)   \- Fastest, good for simple tasks  
  \[ \] 2\. phi3:mini            (2.2 GB)   \- High quality, balanced

  BALANCED (2-5GB):  
  \[ \] 3\. llama3.2:3b          (2.0 GB)   \- Best balance (RECOMMENDED)  
  \[ \] 4\. mistral:7b           (4.1 GB)   \- High quality chat  
  \[ \] 5\. phi4:latest          (8.7 GB)   \- Latest Microsoft model

  CODE GENERATION (3-8GB):  
  \[ \] 6\. qwen2.5-coder:7b     (4.7 GB)   \- Best for code (RECOMMENDED)  
  \[ \] 7\. codellama:7b         (3.8 GB)   \- Meta's code model  
  \[ \] 8\. deepseek-coder:6.7b  (3.8 GB)   \- Trained on 2T tokens

  EMBEDDINGS (\< 1GB):  
  \[ \] 9\. nomic-embed-text     (274 MB)   \- Text embeddings (REQUIRED for RAG)  
  \[✓\] 10\. mxbai-embed-large   (669 MB)   \- Better quality embeddings  
  \[ \] 11\. all-minilm          (45 MB)    \- Lightweight embeddings

  MULTIMODAL (4-8GB):  
  \[ \] 12\. llava:7b            (4.7 GB)   \- Vision \+ Language  
    
  \[ \] 0\. Enter custom model names  
  \[ \] 00\. Skip (download later in UI)

⚠ Note: At least one embedding model is REQUIRED for RAG features

Select models (space separated, e.g., '3 6 9'): 3 6 9

Selected models:  
  ✓ llama3.2:3b (2.0 GB) \- General chat  
  ✓ qwen2.5-coder:7b (4.7 GB) \- Code generation  
  ✓ nomic-embed-text (274 MB) \- Text embeddings

Total download size: \~7.0 GB  
Estimated download time: 3-5 minutes (25 Mbps)

These models will be downloaded during deployment (script 2\)

Proceed? \[Y/n\]: y

Generating files...  
✓ Created: /mnt/data/compose/ollama.yml  
✓ Created: /mnt/data/env/ollama.env  
✓ Saved: /mnt/data/metadata/ollama\_models.json

Ollama Configuration:  
  • Port: 11434  
  • Origins: \* (allow all origins)  
  • Keep alive: 5m  
  • Models to download: 3  
  • Storage: /mnt/data/data/ollama/models

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  
🔌 STEP 6/13: EXTERNAL LLM PROVIDERS  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

LiteLLM can proxy requests to external API providers.

Configure external providers?  
  • Yes \- Use paid APIs for high-quality responses  
  • No \- Use local Ollama only (free but limited)

Configure external providers? \[Y/n\]: y

Select providers to configure:

  MAJOR PROVIDERS:  
  \[ \] 1\.  OpenAI (GPT-4, GPT-4o, GPT-3.5-turbo)  
  \[ \] 2\.  Anthropic (Claude 3.5 Sonnet, Opus, Haiku)  
  \[ \] 3\.  Google (Gemini 2.0 Flash, Pro, Ultra)  
    
  HIGH-PERFORMANCE:  
  \[ \] 4\.  Groq (Fastest inference \- llama, mixtral)  
  \[ \] 5\.  Together AI (100+ open models)  
  \[ \] 6\.  Fireworks AI (Fast inference)  
    
  SPECIALIZED:  
  \[ \] 7\.  Mistral AI (Mistral Large, Codestral)  
  \[ \] 8\.  Cohere (Command R+, Enterprise NLP)  
  \[ \] 9\.  Perplexity (Search-augmented LLMs)  
  \[ \] 10\. DeepSeek (Reasoning-focused models)  
  \[ \] 11\. xAI (Grok models)  
    
  AGGREGATORS:  
  \[ \] 12\. OpenRouter (270+ models from 30+ providers)  
    
  \[ \] 0\. Skip (local Ollama only)  
    
Enter numbers (e.g., '1 2 4 12'): 1 2 3 12

You selected:  
  ✓ OpenAI  
  ✓ Anthropic  
  ✓ Google (Gemini)  
  ✓ OpenRouter

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

OPENAI CONFIGURATION:

API Key: sk-proj-\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*  
  ⏳ Validating API key...  
  ✓ Valid key detected  
  ✓ Organization: org-XXXXXXXXXX  
    
  ⏳ Fetching available models...  
  ✓ Found 18 models

Available models:  
  • gpt-4o (128k context)  
  • gpt-4o-mini (128k context)  
  • gpt-4-turbo (128k context)  
  • gpt-4 (8k context)  
  • gpt-3.5-turbo (16k context)  
  • \+ 13 more models

✓ OpenAI configured

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ANTHROPIC CONFIGURATION:

API Key: sk-ant-\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*  
  ⏳ Validating API key...  
  ✓ Valid key detected  
    
Available models:  
  • claude-3-5-sonnet-20241022 (200k context)  
  • claude-3-opus-20240229 (200k context)  
  • claude-3-haiku-20240307 (200k context)

✓ Anthropic configured

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

GOOGLE (GEMINI) CONFIGURATION:

API Key: AIzaSy\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*  
  ⏳ Validating API key...  
  ✓ Valid key detected  
    
  ⏳ Fetching available models...  
  ✓ Found 12 models

Available models:  
  • gemini-2.0-flash-exp (1M context)  
  • gemini-1.5-pro (2M context)  
  • gemini-1.5-flash (1M context)

✓ Google Gemini configured

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

OPENROUTER CONFIGURATION:

API Key: sk-or-\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*  
  ⏳ Validating API key...  
  ✓ Valid key detected  
    
  ⏳ Fetching available models...  
  ✓ Found 273 models from 35 providers

Popular models available:  
  • OpenAI (GPT-4, GPT-3.5)  
  • Anthropic (Claude 3.5)  
  • Google (Gemini Pro)  
  • Meta (Llama 3.1)  
  • Mistral (Mistral Large)  
  • And 270+ more...

✓ OpenRouter configured

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Provider Configuration Summary:  
  ✓ 4 providers configured  
  ✓ 300+ models available  
  ✓ All API keys validated

Saving provider configuration...  
✓ Saved: /mnt/data/metadata/providers.json  
✓ API keys stored in: /mnt/data/env/litellm.env (encrypted)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  
🔀 STEP 7/13: LITELLM ROUTING STRATEGY  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Configure how LiteLLM routes requests between local and external providers:

  1\) Internal Only (All → Ollama)  
     ├─ Cost:  $ 0/request  
     ├─ Privacy: Complete (all local)  
     ├─ Performance: Limited by local hardware  
     └─ Use case: Privacy-first, cost-sensitive  
       
  2\) External Only (All → API providers)  
     ├─ Cost: Variable ( $ 0.0001-$0.03/request)  
     ├─ Privacy: Data sent to external APIs  
     ├─ Performance: Best quality responses  
     └─ Use case: Quality-first, budget available  
       
  3\) Hybrid \- Complexity-Based (RECOMMENDED)  
     ├─ Simple queries → Ollama (free)  
     ├─ Complex queries → External APIs (paid)  
     ├─ Automatic failover on errors  
     ├─ Best cost/performance balance  
     └─ Use case: Production recommended  
       
  4\) Fallback Chain (Try local → fallback external)  
     ├─ Always try Ollama first  
     ├─ Use external only on failure  
     ├─ Maximum reliability  
     └─ Use case: Uptime-critical  
       
Select strategy \[1-4\]: 3

✓ Hybrid complexity-based routing selected

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

COMPLEXITY THRESHOLD CONFIGURATION:

Requests will be classified as:  
  • SIMPLE  → Ollama (llama3.2:3b)  
  • COMPLEX → External (GPT-4o, Claude 3.5)

Classification criteria:  
  1\) Token count threshold  
  2\) Keyword detection ("complex", "detailed", "analyze")  
  3\) Context length  
  4\) User tags (can be set per-request)

Token count threshold (default: 2000): \[press enter for default\]  
✓ Using default: 2000 tokens

Routing rules:  
  ✓ Tokens \< 2000 → Ollama (llama3.2:3b)  
  ✓ Tokens \>= 2000 → OpenAI (gpt-4o-mini) or Anthropic (claude-3-haiku)  
  ✓ Keyword "complex" → Force external  
  ✓ On Ollama failure → Fallback to GPT-3.5-turbo

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

FALLBACK CHAIN CONFIGURATION:

For maximum reliability, configure fallback models:

Primary model: ollama/llama3.2:3b (local)  
Fallback 1:    openai/gpt-3.5-turbo (fast \+ cheap)  
Fallback 2:    anthropic/claude-3-haiku (reliable)  
Fallback 3:    openrouter/meta-llama/llama-3.1-8b (affordable)

Max retry attempts: 3  
Cooldown between retries: 5 seconds

Looks good? \[Y/n\]: y

✓ Routing strategy configured

Generating LiteLLM configuration...  
✓ Created: /mnt/data/compose/litellm.yml  
✓ Created: /mnt/data/env/litellm.env (with all API keys)  
✓ Created: /mnt/data/config/litellm/config.yaml (routing rules)  
✓ Saved: /mnt/data/metadata/routing\_strategy.json

LiteLLM Configuration:  
  • Port: 4000  
  • Database: PostgreSQL (for model storage)  
  • UI enabled: Yes (username: admin)  
  • Routing: Hybrid complexity-based  
  • Providers: OpenAI, Anthropic, Google, OpenRouter, Ollama  
  • Fallback chain: 3 levels

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  
🎯 STEP 8/13: AI PLATFORMS  
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Select AI application platforms to install:

  CHAT INTERFACES:  
  \[ \] 1\. OpenWebUI (Ollama web UI with RAG)  
  \[ \] 2\. AnythingLLM (Document Q\&A \+ Knowledge base)  
    
  WORKFLOW AUTOMATION:  
  \[ \] 3\. N8N (Workflow automation platform)  
      Requires: PostgreSQL ✓, Redis ✓  
    
  LOW-CODE AI BUILDERS:  
  \[ \] 4\. Flowise (Drag-drop AI flows)  
      Requires: PostgreSQL ✓  
        
  \[ \] 5\. Dify (Enterprise AI platform)  
      Requires: PostgreSQL ✓, Redis  
`(to be finished)`

`Script 2 Expected output :` 

## **SCRIPT 2: DEPLOY SERVICES**

### **Intent**

Pull Docker images, deploy containers with proper network configuration, perform health checks, and deliver a working system.

### **Key Responsibilities**

#### **1\. Environment Validation**

* Source `.env` file  
* Validate NO ANSI codes present  
* Validate NO shell injection patterns  
* Confirm all required variables set

#### **2\. Pre-Deployment Cleanup**

* Remove any existing containers with same names  
* Preserve volumes (data persistence)  
* Clean stale network connections

#### **3\. Docker Network Creation**

docker network create ai-network 2\>/dev/null || true

#### **4\. Service Deployment (Dependency Order)**

**Phase 1: Core Infrastructure**

\# 1\. Ollama (LLM backend)  
docker run \-d \--name ollama \\  
  \--network ai-network \\  
  \-p ${OLLAMA\_PORT}:11434 \\  
  \-v ollama-data:/root/.ollama \\  
  \--gpus all \\  \# If GPU detected  
  \--restart unless-stopped \\  
  ollama/ollama:latest

\# 2\. Qdrant (Vector DB)  
docker run \-d \--name qdrant \\  
  \--network ai-network \\  
  \-p ${QDRANT\_PORT}:6333 \\  
  \-v qdrant-data:/qdrant/storage \\  
  \-e QDRANT\_\_SERVICE\_\_API\_KEY=${QDRANT\_API\_KEY} \\  
  \--restart unless-stopped \\  
  qdrant/qdrant:latest

**Phase 2: Search Infrastructure**

\# 3\. SearXNG (if selected)  
docker run \-d \--name searxng \\  
  \--network ai-network \\  
  \-p ${SEARXNG\_PORT}:8080 \\  
  \-v searxng-data:/etc/searxng \\  
  \-e SEARXNG\_SECRET=${SEARXNG\_SECRET\_KEY} \\  
  \--restart unless-stopped \\  
  searxng/searxng:latest

**Phase 3: LLM Gateway**

\# 4\. LiteLLM (Unified API)  
docker run \-d \--name litellm \\  
  \--network ai-network \\  
  \-p ${LITELLM\_PORT}:4000 \\  
  \-v litellm-data:/app/config \\  
  \-e OLLAMA\_BASE\_URL=http://ollama:11434 \\  
  \-e LITELLM\_MASTER\_KEY=${LITELLM\_MASTER\_KEY} \\  
  \-e OPENAI\_API\_KEY=${OPENAI\_API\_KEY:-} \\  
  \-e ANTHROPIC\_API\_KEY=${ANTHROPIC\_API\_KEY:-} \\  
  \--restart unless-stopped \\  
  ghcr.io/berriai/litellm:main-latest

**Phase 4: AI Platforms**

\# 5\. Ollama WebUI  
docker run \-d \--name ollama-webui \\  
  \--network ai-network \\  
  \-p ${OLLAMA\_WEBUI\_PORT}:8080 \\  
  \-v ollama-webui-data:/app/backend/data \\  
  \-e OLLAMA\_BASE\_URL=http://ollama:11434 \\  
  \--restart unless-stopped \\  
  ghcr.io/open-webui/open-webui:main

\# 6\. AnythingLLM  
docker run \-d \--name anythingllm \\  
  \--network ai-network \\  
  \-p ${ANYTHINGLLM\_PORT}:3001 \\  
  \-v anythingllm-data:/app/server/storage \\  
  \-v /mnt/data/gdrive:/app/collector/hotdir \\  
  \-e LLM\_PROVIDER=ollama \\  
  \-e OLLAMA\_BASE\_PATH=http://ollama:11434 \\  
  \-e VECTOR\_DB=qdrant \\  
  \-e QDRANT\_ENDPOINT=http://qdrant:6333 \\  
  \-e QDRANT\_API\_KEY=${QDRANT\_API\_KEY} \\  
  \--restart unless-stopped \\  
  mintplexlabs/anythingllm:latest

\# 7\. Dify  
docker run \-d \--name dify \\  
  \--network ai-network \\  
  \-p ${DIFY\_PORT}:3000 \\  
  \-v dify-data:/app/storage \\  
  \-e LLM\_PROVIDER=openai \\  
  \-e OPENAI\_API\_BASE=http://litellm:4000 \\  
  \-e OPENAI\_API\_KEY=${LITELLM\_MASTER\_KEY} \\  
  \--restart unless-stopped \\  
  langgenius/dify-api:latest

**Phase 5: Automation**

\# 8\. OpenClaw  
docker run \-d \--name open-claw \\  
  \--network ai-network \\  
  \-p ${OPENCLAW\_PORT}:3000 \\  
  \-v openclaw-data:/app/data \\  
  \-e ANYTHINGLLM\_API\_BASE=http://anythingllm:3001 \\  
  \--restart unless-stopped \\  
  openclawai/openclaw:latest

\# 9\. n8n (if selected)  
docker run \-d \--name n8n \\  
  \--network ai-network \\  
  \-p ${N8N\_PORT}:5678 \\  
  \-v n8n-data:/home/node/.n8n \\  
  \--restart unless-stopped \\  
  n8nio/n8n:latest

**Phase 6: Reverse Proxy**

\# 10a. Nginx (if selected)  
docker run \-d \--name nginx \\  
  \--network ai-network \\  
  \-p ${NGINX\_HTTP\_PORT}:80 \\  
  \-p ${NGINX\_HTTPS\_PORT}:443 \\  
  \-v /opt/ai-services/config/nginx/conf.d:/etc/nginx/conf.d:ro \\  
  \-v /opt/ai-services/config/nginx/ssl:/etc/nginx/ssl:ro \\  
  \-v nginx-cache:/var/cache/nginx \\  
  \--restart unless-stopped \\  
  nginx:alpine

\# 10b. Caddy (if selected \- MUTUALLY EXCLUSIVE)  
docker run \-d \--name caddy \\  
  \--network ai-network \\  
  \-p ${CADDY\_HTTP\_PORT}:80 \\  
  \-p ${CADDY\_HTTPS\_PORT}:443 \\  
  \-v /opt/ai-services/config/caddy/Caddyfile:/etc/caddy/Caddyfile:ro \\  
  \-v caddy-data:/data \\  
  \-v caddy-config:/config \\  
  \--restart unless-stopped \\  
  caddy:latest

**Phase 7: VPN**

\# 11\. Tailscale  
docker run \-d \--name tailscale \\  
  \--network host \\  
  \--cap-add NET\_ADMIN \\  
  \--cap-add SYS\_MODULE \\  
  \-v /dev/net/tun:/dev/net/tun \\  
  \-v tailscale-data:/var/lib/tailscale \\  
  \-e TS\_AUTHKEY=${TAILSCALE\_AUTH\_KEY} \\  
  \-e TS\_STATE\_DIR=/var/lib/tailscale \\  
  \--restart unless-stopped \\  
  tailscale/tailscale:latest

**Phase 8: Data Sync**

\# 12\. Rsync (Cron-based Google Drive sync)  
\# Create systemd timer or cron job:  
\# \*/6 \* \* \* \* rsync \-avz /path/to/gdrive/ /mnt/data/gdrive/

#### **5\. Health Checks (Per Service)**

check\_service\_health() {  
    local service=$1  
    local port=$2  
    local max\_attempts=30  
      
    for i in $(seq 1 $max\_attempts); do  
        if curl \-sf "http://localhost:${port}/health" \>/dev/null 2\>&1; then  
            log\_success "$service healthy on port $port"  
            return 0  
        fi  
        sleep 2  
    done  
      
    log\_error "$service failed health check"  
    docker logs "$service" | tail \-20  
    return 1  
}

\# Execute health checks  
check\_service\_health "ollama" "$OLLAMA\_PORT"  
check\_service\_health "litellm" "$LITELLM\_PORT"  
check\_service\_health "qdrant" "$QDRANT\_PORT"  
\# ... etc

#### **6\. Credentials File Update**

cat \>\> /opt/ai-services/credentials.txt \<\<EOF  
╔════════════════════════════════════════╗  
║     AI PLATFORM ACCESS CREDENTIALS     ║  
╚════════════════════════════════════════╝

Generated: $(date)

OLLAMA:  
  URL: http://localhost:${OLLAMA\_PORT}  
  API: http://localhost:${OLLAMA\_PORT}/api

OLLAMA WEBUI:  
  URL: http://localhost:${OLLAMA\_WEBUI\_PORT}  
  Default Admin: Create on first access

LITELLM:  
  URL: http://localhost:${LITELLM\_PORT}  
  API Key: ${LITELLM\_MASTER\_KEY}  
  Docs: http://localhost:${LITELLM\_PORT}/docs

QDRANT:  
  URL: http://localhost:${QDRANT\_PORT}  
  API Key: ${QDRANT\_API\_KEY}  
  Dashboard: http://localhost:${QDRANT\_PORT}/dashboard

ANYTHINGLLM:  
  URL: http://localhost:${ANYTHINGLLM\_PORT}  
  OR: https://${DOMAIN}/anythingllm

DIFY:  
  URL: http://localhost:${DIFY\_PORT}  
  OR: https://${DOMAIN}/dify

OPENCLAW (via Tailscale):  
  URL: https://$(tailscale status \--json | jq \-r '.Self.DNSName'):18789

TAILSCALE:  
  Admin: https://login.tailscale.com/admin/machines  
  This Device IP: $(tailscale ip \-4)

REVERSE PROXY:  
  Public URL: https://${DOMAIN}  
  Backend: ${PROXY\_TYPE} (Nginx/Caddy)

EOF

#### **7\. Deployment Summary**

echo ""  
echo "╔════════════════════════════════════════╗"  
echo "║   DEPLOYMENT COMPLETE v68.0.0          ║"  
echo "╚════════════════════════════════════════╝"  
echo ""  
echo "✓ All containers running"  
echo "✓ Health checks passed"  
echo "✓ Credentials saved to /opt/ai-services/credentials.txt"  
echo ""  
echo "Next steps:"  
echo "  1\. Run: 3-configure-services.sh"  
echo "  2\. Access services at: https://${DOMAIN}"  
echo ""

### **Success Definition**

* ✅ All selected containers running (`docker ps` shows all)  
* ✅ All services pass health checks  
* ✅ Reverse proxy routing works (test `curl https://${DOMAIN}/anythingllm`)  
* ✅ Inter-service communication works (Dify can reach LiteLLM)  
* ✅ Credentials file populated  
* ✅ Tailscale connected (if enabled)  
* ✅ No port conflicts  
* ✅ All containers have `restart: unless-stopped`

## **SCRIPT 3: CONFIGURE SERVICES**

### **Intent**

Fine-tune service-specific settings, load initial models, configure routing rules, enable systemd persistence, and link external integrations (Signal, Google Drive sync).

### **Key Responsibilities**

#### **1\. Service Status Check**

display\_service\_status() {  
    echo "╔════════════════════════════════════════╗"  
    echo "║        SERVICE STATUS OVERVIEW         ║"  
    echo "╚════════════════════════════════════════╝"  
      
    for service in ollama litellm qdrant anythingllm dify openclaw; do  
        if docker ps \--format '{{.Names}}' | grep \-q "^${service}$"; then  
            status="✓ Running"  
            color="${GREEN}"  
        else  
            status="✗ Stopped"  
            color="${RED}"  
        fi  
        printf "%-20s %s\\n" "$service" "${color}${status}${NC}"  
    done  
}

#### **2\. Ollama Model Management**

configure\_ollama\_models() {  
    echo ""  
    log "Ollama Model Configuration"  
    echo "  Current models:"  
    docker exec ollama ollama list  
      
    echo ""  
    echo "Available models:"  
    echo "  1\) llama3.2:1b (Fast, minimal)"  
    echo "  2\) llama3.2:3b (Balanced \- RECOMMENDED)"  
    echo "  3\) mistral:7b (High quality)"  
    echo "  4\) deepseek-coder:6.7b (Code-focused)"  
    echo "  5\) Custom model name"  
      
    read \-p "Select model to pull \[2\]: " model\_choice  
      
    case "${model\_choice:-2}" in  
        1\) MODEL="llama3.2:1b" ;;  
        2\) MODEL="llama3.2:3b" ;;  
        3\) MODEL="mistral:7b" ;;  
        4\) MODEL="deepseek-coder:6.7b" ;;  
        5\) read \-p "Enter model name: " MODEL ;;  
    esac  
      
    log "Pulling model: $MODEL (this may take several minutes)"  
    docker exec ollama ollama pull "$MODEL"  
      
    \# Set as default in LiteLLM routing  
    update\_litellm\_config "default\_model" "$MODEL"  
}

#### **3\. LiteLLM Routing Configuration**

configure\_litellm\_routing() {  
    echo ""  
    log "LiteLLM Routing Rules Configuration"  
      
    cat \> /opt/ai-services/config/litellm/config.yaml \<\<EOF  
model\_list:  
  \# Local Ollama models  
  \- model\_name: local-llm  
    litellm\_params:  
      model: ollama/${OLLAMA\_MODEL:-llama3.2:3b}  
      api\_base: http://ollama:11434  
        
  \# Cloud fallback models  
  \- model\_name: gpt-4-turbo  
    litellm\_params:  
      model: gpt-4-turbo-preview  
      api\_key: ${OPENAI\_API\_KEY:-}  
        
  \- model\_name: claude-3-opus  
    litellm\_params:  
      model: claude-3-opus-20240229  
      api\_key: ${ANTHROPIC\_API\_KEY:-}

router\_settings:  
  routing\_strategy: usage-based-routing  
    
  \# Route simple queries to local, complex to cloud  
  model\_routing:  
    \- pattern: ".\*simple.\*|.\*quick.\*|.\*basic.\*"  
      target: local-llm  
        
    \- pattern: ".\*complex.\*|.\*analysis.\*|.\*research.\*"  
      target: gpt-4-turbo  
      fallback: local-llm  
        
    \- pattern: ".\*code.\*|.\*programming.\*"  
      target: ${CODE\_MODEL:-local-llm}  
        
  \# Cost limits  
  max\_budget: 100  \# USD per month  
  budget\_duration: 30d  
EOF

    docker restart litellm  
    log\_success "LiteLLM routing configured"  
}

#### **4\. LiteLLM Web UI (Expose Configuration Interface)**

\# Deploy optional LiteLLM admin UI  
deploy\_litellm\_ui() {  
    read \-p "Deploy LiteLLM Admin UI? \[Y/n\]: " \-n 1 \-r  
    echo  
      
    if \[\[ \! $REPLY \=\~ ^\[Nn\]$ \]\]; then  
        LITELLM\_UI\_PORT=$(find\_available\_port "litellm-ui" 4001\)  
          
        docker run \-d \--name litellm-ui \\  
          \--network ai-network \\  
          \-p ${LITELLM\_UI\_PORT}:3000 \\  
          \-e LITELLM\_API\_BASE=http://litellm:4000 \\  
          \-e LITELLM\_API\_KEY=${LITELLM\_MASTER\_KEY} \\  
          \--restart unless-stopped \\  
          ghcr.io/berriai/litellm-ui:latest  
            
        log\_success "LiteLLM UI: http://localhost:${LITELLM\_UI\_PORT}"  
    fi  
}

#### **5\. AnythingLLM Configuration**

configure\_anythingllm() {  
    log "Configuring AnythingLLM..."  
      
    \# Connect to Qdrant vector DB  
    docker exec anythingllm curl \-X POST http://localhost:3001/api/system/vector-db \\  
      \-H "Content-Type: application/json" \\  
      \-d '{  
        "provider": "qdrant",  
        "config": {  
          "url": "http://qdrant:6333",  
          "apiKey": "'"${QDRANT\_API\_KEY}"'"  
        }  
      }'  
      
    \# Set Ollama as LLM provider  
    docker exec anythingllm curl \-X POST http://localhost:3001/api/system/llm \\  
      \-H "Content-Type: application/json" \\  
      \-d '{  
        "provider": "ollama",  
        "config": {  
          "baseUrl": "http://ollama:11434",  
          "model": "'"${OLLAMA\_MODEL}"'"  
        }  
      }'  
      
    \# Configure document ingestion from /mnt/data/gdrive  
    docker exec anythingllm curl \-X POST http://localhost:3001/api/system/data-connectors \\  
      \-H "Content-Type: application/json" \\  
      \-d '{  
        "type": "local\_files",  
        "path": "/app/collector/hotdir"  
      }'  
      
    log\_success "AnythingLLM configured with Qdrant \+ Ollama"  
}

#### **6\. OpenClaw Configuration**

configure\_openclaw() {  
    log "Configuring OpenClaw..."  
      
    \# Link to AnythingLLM for knowledge retrieval  
    docker exec open-claw sh \-c 'cat \> /app/config.json' \<\<EOF  
{  
  "llm": {  
    "provider": "anythingllm",  
    "endpoint": "http://anythingllm:3001/api/chat",  
    "defaultModel": "${OLLAMA\_MODEL}"  
  },  
  "vectorDB": {  
    "provider": "qdrant",  
    "endpoint": "http://qdrant:6333",  
    "apiKey": "${QDRANT\_API\_KEY}",  
    "collection": "openclaw-knowledge"  
  },  
  "automation": {  
    "screenshotPath": "/app/data/screenshots",  
    "maxRetries": 3  
  }  
}  
EOF  
      
    docker restart open-claw  
    log\_success "OpenClaw linked to AnythingLLM \+ Qdrant"  
}

#### **7\. OpenClaw via Tailscale HTTPS**

configure\_openclaw\_tailscale() {  
    log "Configuring OpenClaw access via Tailscale..."  
      
    \# Get Tailscale IP  
    TAILSCALE\_IP=$(docker exec tailscale tailscale ip \-4)  
      
    \# Update Caddy/Nginx to serve OpenClaw on Tailscale interface  
    if \[\[ "$PROXY\_TYPE" \== "caddy" \]\]; then  
        cat \>\> /opt/ai-services/config/caddy/Caddyfile \<\<EOF

\# OpenClaw via Tailscale HTTPS  
https://${TAILSCALE\_IP}:8443 {  
    reverse\_proxy open-claw:3000  
    tls internal  
}  
EOF  
        docker exec caddy caddy reload \--config /etc/caddy/Caddyfile  
    fi  
      
    log\_success "OpenClaw accessible at: https://${TAILSCALE\_IP}:8443"  
    log "  OR: https://$(docker exec tailscale tailscale status \--json | jq \-r '.Self.DNSName'):18789"  
}

#### **8\. Dify Configuration**

configure\_dify() {  
    log "Configuring Dify..."  
      
    \# Point Dify to LiteLLM for intelligent routing  
    docker exec dify sh \-c 'cat \> /app/.env' \<\<EOF  
LLM\_PROVIDER=openai  
OPENAI\_API\_BASE=http://litellm:4000  
OPENAI\_API\_KEY=${LITELLM\_MASTER\_KEY}  
VECTOR\_STORE=qdrant  
QDRANT\_URL=http://qdrant:6333  
QDRANT\_API\_KEY=${QDRANT\_API\_KEY}  
EOF  
      
    docker restart dify  
    log\_success "Dify configured with LiteLLM \+ Qdrant"  
}

#### **9\. Signal Bot Configuration (Optional)**

configure\_signal\_bot() {  
    read \-p "Link Signal messaging bot? \[y/N\]: " \-n 1 \-r  
    echo  
      
    if \[\[ $REPLY \=\~ ^\[Yy\]$ \]\]; then  
        log "Signal bot requires:"  
        log "  1\. Signal CLI installed: https://github.com/AsamK/signal-cli"  
        log "  2\. Phone number registered"  
          
        read \-p "Enter Signal phone number (with country code): " SIGNAL\_PHONE  
          
        \# Link device  
        docker run \--rm \-it \\  
          \-v signal-data:/root/.local/share/signal-cli \\  
          bbernhard/signal-cli:latest \\  
          \-u "$SIGNAL\_PHONE" link  
          
        log "Scan QR code with Signal app (Settings → Linked Devices)"  
          
        \# Deploy Signal bridge  
        docker run \-d \--name signal-bridge \\  
          \--network ai-network \\  
          \-v signal-data:/root/.local/share/signal-cli \\  
          \-e SIGNAL\_PHONE="$SIGNAL\_PHONE" \\  
          \-e OPENCLAW\_ENDPOINT="http://open-claw:3000" \\  
          \--restart unless-stopped \\  
          custom/signal-openclaw-bridge:latest  
          
        log\_success "Signal bot linked \- messages route to OpenClaw"  
    fi  
}

#### **10\. Google Drive Rsync Configuration**

configure\_gdrive\_sync() {  
    log "Configuring Google Drive sync..."  
      
    read \-p "Enable Google Drive sync to /mnt/data/gdrive? \[Y/n\]: " \-n 1 \-r  
    echo  
      
    if \[\[ \! $REPLY \=\~ ^\[Nn\]$ \]\]; then  
        read \-p "Enter Google Drive source path (rclone remote:path): " GDRIVE\_SOURCE  
        read \-p "Sync interval (hours) \[6\]: " SYNC\_INTERVAL  
        SYNC\_INTERVAL=${SYNC\_INTERVAL:-6}  
          
        \# Create systemd timer  
        cat \> /etc/systemd/system/gdrive-sync.service \<\<EOF  
\[Unit\]  
Description=Google Drive Sync to /mnt/data/gdrive  
After=network.target

\[Service\]  
Type=oneshot  
ExecStart=/usr/bin/rclone sync ${GDRIVE\_SOURCE} /mnt/data/gdrive/ \-v \--log-file=/var/log/gdrive-sync.log  
User=root

\[Install\]  
WantedBy=multi-user.target  
EOF

        cat \> /etc/systemd/system/gdrive-sync.timer \<\<EOF  
\[Unit\]  
Description=Google Drive Sync Timer

\[Timer\]  
OnBootSec=5min  
OnUnitActiveSec=${SYNC\_INTERVAL}h  
Persistent=true

\[Install\]  
WantedBy=timers.target  
EOF

        systemctl daemon-reload  
        systemctl enable \--now gdrive-sync.timer  
          
        log\_success "Google Drive sync enabled (every ${SYNC\_INTERVAL}h)"  
        log "  Source: ${GDRIVE\_SOURCE}"  
        log "  Target: /mnt/data/gdrive/"  
    fi  
}

#### **11\. Port Reconfiguration**

reconfigure\_port() {  
    local service=$1  
    local current\_port=$2  
      
    read \-p "Change port for $service (current: $current\_port)? \[y/N\]: " \-n 1 \-r  
    echo  
      
    if \[\[ $REPLY \=\~ ^\[Yy\]$ \]\]; then  
        read \-p "Enter new port: " new\_port  
          
        \# Validate and stop service  
        docker stop "$service"  
        docker rm "$service"  
          
        \# Update ENV  
        sed \-i "s/^${service^^}\_PORT=.\*/${service^^}\_PORT=$new\_port/" "$ENV\_FILE"  
          
        \# Re-deploy with new port  
        source "$ENV\_FILE"  
        deploy\_${service}  
          
        log\_success "$service moved to port $new\_port"  
    fi  
}

#### **12\. System Integration (Systemd)**

make\_persistent() {  
    log "Creating systemd service for container auto-start..."  
      
    \# Docker containers already have \--restart unless-stopped  
    \# but ensure Docker starts on boot  
    systemctl enable docker  
      
    \# Optionally create a wrapper service  
    cat \> /etc/systemd/system/ai-platform.service \<\<'EOF'  
\[Unit\]  
Description=AI Platform Container Stack  
After=docker.service  
Requires=docker.service

\[Service\]  
Type=oneshot  
RemainAfterExit=yes  
ExecStart=/usr/bin/docker start ollama litellm qdrant anythingllm dify openclaw caddy tailscale  
ExecStop=/usr/bin/docker stop ollama litellm qdrant anythingllm dify openclaw caddy tailscale  
User=root

\[Install\]  
WantedBy=multi-user.target  
EOF

    systemctl daemon-reload  
    systemctl enable ai-platform.service  
      
    log\_success "AI Platform will auto-start on boot"  
}

#### **13\. Configuration Menu**

show\_configuration\_menu() {  
    while true; do  
        echo ""  
        echo "╔════════════════════════════════════════╗"  
        echo "║    SERVICE CONFIGURATION MENU          ║"  
        echo "╚════════════════════════════════════════╝"  
        echo ""  
        echo "  1\) View service status"  
        echo "  2\) Configure Ollama models"  
        echo "  3\) Configure LiteLLM routing"  
        echo "  4\) Deploy LiteLLM Web UI"  
        echo "  5\) Configure AnythingLLM"  
        echo "  6\) Configure OpenClaw"  
        echo "  7\) Configure OpenClaw via Tailscale"  
        echo "  8\) Configure Dify"  
        echo "  9\) Configure Signal bot"  
        echo " 10\) Configure Google Drive sync"  
        echo " 11\) Reconfigure service ports"  
        echo " 12\) Make configuration permanent (systemd)"  
        echo " 13\) Restart all services"  
        echo "  0\) Exit"  
        echo ""  
        read \-p "Select option: " choice  
          
        case $choice in  
            1\) display\_service\_status ;;  
            2\) configure\_ollama\_models ;;  
            3\) configure\_litellm\_routing ;;  
            4\) deploy\_litellm\_ui ;;  
            5\) configure\_anythingllm ;;  
            6\) configure\_openclaw ;;  
            7\) configure\_openclaw\_tailscale ;;  
            8\) configure\_dify ;;  
            9\) configure\_signal\_bot ;;  
            10\) configure\_gdrive\_sync ;;  
            11\) reconfigure\_ports\_menu ;;  
            12\) make\_persistent ;;  
            13\) restart\_all\_services ;;  
            0\) break ;;  
            \*) log\_error "Invalid option" ;;  
        esac  
    done  
}

### **Success Definition**

* ✅ Ollama model pulled and active  
* ✅ LiteLLM routing rules configured (local-first, cloud fallback)  
* ✅ AnythingLLM connected to Qdrant \+ Ollama  
* ✅ OpenClaw linked to AnythingLLM vector DB  
* ✅ OpenClaw accessible via Tailscale HTTPS  
* ✅ Dify using LiteLLM for intelligent routing  
* ✅ Google Drive sync active (if enabled)  
* ✅ Signal bot linked (if enabled)  
* ✅ All services set to auto-start on boot  
* ✅ User can modify configuration via menu (no manual file editing)

## **SCRIPT 4: ADD SERVICE (FUTURE EXTENSIBILITY)**

### **Intent**

Provide a framework to add new Docker-based AI services without modifying core scripts.

### **Template Structure**

add\_new\_service() {  
    local service\_name=$1  
      
    echo "Adding new service: $service\_name"  
      
    \# 1\. Collect configuration  
    read \-p "Docker image: " image  
    read \-p "Port: " port  
      
    \# 2\. Validate port availability  
    if \! is\_port\_available "$port"; then  
        log\_error "Port $port already in use"  
        return 1  
    fi  
      
    \# 3\. Deploy container  
    docker run \-d \\  
      \--name "$service\_name" \\  
      \--network ai-network \\  
      \-p "${port}:${port}" \\  
      \-v "${service\_name}-data:/data" \\  
      \--restart unless-stopped \\  
      "$image"  
      
    \# 4\. Update ENV  
    echo "${service\_name^^}\_PORT=$port" \>\> "$ENV\_FILE"  
      
    \# 5\. Update credentials file  
    cat \>\> "$CREDS\_FILE" \<\<EOF

${service\_name^^}:  
  URL: http://localhost:${port}  
  Added: $(date)  
EOF  
      
    \# 6\. Add to reverse proxy  
    update\_reverse\_proxy\_config "$service\_name" "$port"  
      
    log\_success "$service\_name deployed on port $port"  
}

### **Success Definition**

* ✅ New service deployed without editing Scripts 1-3  
* ✅ Port automatically allocated  
* ✅ Service added to reverse proxy routing  
* ✅ ENV file updated  
* ✅ Credentials documented

## **KEY ARCHITECTURE DEFINITIONS**

### **Primary Access Flows**

#### **1\. Public Access (via Reverse Proxy)**

User → https://ai.example.com/anythingllm → Caddy → AnythingLLM:3001  
User → https://ai.example.com/dify → Caddy → Dify:3000

#### **2\. Tailscale Private Access (OpenClaw)**

User → https://tailscale-ip:18789 → Tailscale → OpenClaw:18789

#### **3\. LLM Request Routing**

Dify → LiteLLM:4000 → \[Simple query\] → Ollama:11434 → llama3.2:3b  
                    → \[Complex query\] → OpenAI API → gpt-4-turbo

#### **4\. Vector DB Flow**

AnythingLLM → Qdrant:6333 (embeddings storage)  
OpenClaw → Qdrant:6333 (knowledge retrieval)  
Dify → Qdrant:6333 (RAG queries)

#### **5\. Data Sync Flow**

Google Drive → rclone (systemd timer) → /mnt/data/gdrive/ → AnythingLLM ingestion

---

## **TECHNOLOGY STACK SUMMARY**

| Component | Technology | Purpose | Port |
| ----- | ----- | ----- | ----- |
| **LLM Backend** | Ollama | Local inference | 11434 |
| **Tailscale auth** | tailscale | Retrieve tailscale ip | na |
| **LLM Gateway** | LiteLLM | Unified API \+ routing | 4000 |
| **Vector DB** | Qdrant | Embeddings storage | 6333 |
| **Document Chat** | AnythingLLM | RAG interface | 3001 |
| **AI Workflows** | Dify | Visual AI builder | 3000 |
| **Web Automation** | OpenClaw | Browser automation | 18789 |
| **Workflow Automation** | n8n | General automation | 5678 |
| **Reverse Proxy** | Caddy OR Nginx OR traefik | HTTPS termination | 80/443 |
| **VPN** | Tailscale | Secure remote access | 8443  |
| **Signal API** | Signal | Pair device for openclaw integration | 8081 |
| **Data Sync** | Rclone | Google Drive → local | N/A  |
| **Ai workflows** | Flowise | Visual ai builder | 3000 |
| **Vector db** | weaviate | Embeddings storage | 50051 |
| **Vector DB** | Redis | Embeddings storage | 7379 |
| **Vector db** | Milvus | Embeddings storage | 1953 |
| **Database** | Postgres | storage | 5432 |
| **LLM observability** | langfuse | Metrics | 3000 |
| **LLM observability** | grafana | logging | 3000 |
| **LLM monitoring** | prometheus | MEtrics | 9090 |
| **LLM Monitoring** | LOKI=promtai | MEtrics | 3100 |

## **TABLE 1: COMPLETE SERVICE INVENTORY & GAPS** 

In order to initialise step 2 without errors, we reviewed the official documentation for all the stack components and identified additional key variables to generate at step1

| \# | Service | Category | Variables Required | File Outputs | Integration Points | Priority |
| ----- | ----- | ----- | ----- | ----- | ----- | ----- |
| **REVERSE PROXY** |  |  |  |  |  |  |
| 1 | **Nginx** | Proxy Option 1 | `PROXY_TYPE=nginx`\<br\>`HTTP_PORT=80`\<br\>`HTTPS_PORT=443`\<br\>`SSL_TYPE=letsencrypt/self/none` | `compose/nginx.yml`\<br\>`env/nginx.env`\<br\>`config/nginx/nginx.conf`\<br\>`config/nginx/sites/*.conf` | All services routed through | 🔴 CRITICAL |
| 2 | **Traefik** | Proxy Option 2 | `PROXY_TYPE=traefik`\<br\>`TRAEFIK_DASHBOARD=true`\<br\>`TRAEFIK_API=true`\<br\>`ACME_EMAIL=` | `compose/traefik.yml`\<br\>`env/traefik.env`\<br\>`config/traefik/traefik.yml`\<br\>`config/traefik/dynamic/*.yml` | Auto-discovers services via labels | 🔴 CRITICAL |
| 3 | **Caddy** | Proxy Option 3 | `PROXY_TYPE=caddy`\<br\>`CADDY_AUTO_HTTPS=true` | `compose/caddy.yml`\<br\>`env/caddy.env`\<br\>`config/caddy/Caddyfile` | Auto HTTPS, simple config | 🔴 CRITICAL |
| **CORE INFRASTRUCTURE** |  |  |  |  |  |  |
| 4 | **PostgreSQL** | Database | `POSTGRES_VERSION=16-alpine`\<br\>`POSTGRES_PORT=5432`\<br\>Per-service DBs:\<br\>`N8N_DB`, `DIFY_DB`, `FLOWISE_DB`, `LITELLM_DB`, `LANGFUSE_DB`\<br\>Each with user/pass | `compose/postgres.yml`\<br\>`env/postgres.env`\<br\>`config/postgres/init.sql` | N8N, Dify, Flowise, LiteLLM, Langfuse | 🔴 CRITICAL |
| 5 | **Redis** | Cache/Queue | `REDIS_PORT=6379`\<br\>`REDIS_PASSWORD=`\<br\>`REDIS_MAXMEMORY=256mb`\<br\>`REDIS_POLICY=allkeys-lru` | `compose/redis.yml`\<br\>`env/redis.env`\<br\>`config/redis/redis.conf` | N8N (queue), Dify (cache) | 🔴 CRITICAL |
| 6 | **Qdrant** | Vector DB | `QDRANT_PORT=6333`\<br\>`QDRANT_GRPC_PORT=6334`\<br\>`QDRANT_API_KEY=`\<br\>`QDRANT_ALLOW_ANONYMOUS=false` | `compose/qdrant.yml`\<br\>`env/qdrant.env` | Dify, AnythingLLM, OpenWebUI, Flowise | 🔴 CRITICAL |
| 7 | **Weaviate** | Vector DB Alt | `WEAVIATE_PORT=8080`\<br\>`WEAVIATE_GRPC_PORT=50051`\<br\>`AUTHENTICATION_API_KEY=` | `compose/weaviate.yml`\<br\>`env/weaviate.env` | Alternative to Qdrant | 🟡 HIGH |
| 8 | **Milvus** | Vector DB Alt | `MILVUS_PORT=19530`\<br\>`MILVUS_USER=`\<br\>`MILVUS_PASSWORD=`\<br\>`ETCD_ENDPOINTS=` | `compose/milvus.yml`\<br\>`env/milvus.env`\<br\>`config/milvus/milvus.yaml` | Alternative to Qdrant | 🟡 HIGH |
| **COMMUNICATION & STORAGE** |  |  |  |  |  |  |
| 9 | **Signal-API** | Messaging | **QR Method:**\<br\>`SIGNAL_NUMBER=+1234567890`\<br\>`SIGNAL_DEVICE_NAME=`\<br\>`MODE=native`\<br\>\<br\>**API Method:**\<br\>`SIGNAL_NUMBER=+1234567890`\<br\>`SIGNAL_CAPTCHA_TOKEN=`\<br\>`SIGNAL_VERIFICATION_CODE=`\<br\>`MODE=json-rpc` | `compose/signal-api.yml`\<br\>`env/signal-api.env` | N8N webhooks, notifications | 🔴 CRITICAL |
| 10 | **Google Drive** | Storage | **OAuth:**\<br\>`GDRIVE_CLIENT_ID=`\<br\>`GDRIVE_CLIENT_SECRET=`\<br\>`GDRIVE_REDIRECT_URI=`\<br\>`GDRIVE_REFRESH_TOKEN=`\<br\>\<br\>**Service Account:**\<br\>`GDRIVE_SERVICE_ACCOUNT_EMAIL=`\<br\>`GDRIVE_SERVICE_ACCOUNT_KEY=` (base64)\<br\>\<br\>**API Key:**\<br\>`GDRIVE_API_KEY=`\<br\>`GDRIVE_FOLDER_ID=` | `compose/gdrive.yml`\<br\>`env/gdrive.env`\<br\>`config/gdrive/credentials.json` | N8N workflows, Dify uploads | 🔴 CRITICAL |
| **LLM ENGINES** |  |  |  |  |  |  |
| 11 | **Ollama** | LLM Runtime | `OLLAMA_HOST=0.0.0.0`\<br\>`OLLAMA_ORIGINS=*`\<br\>`OLLAMA_PORT=11434`\<br\>`OLLAMA_MODELS=` (comma-separated)\<br\>`OLLAMA_KEEP_ALIVE=5m` | `compose/ollama.yml`\<br\>`env/ollama.env`\<br\>`metadata/ollama_models.json` | All AI platforms, LiteLLM | 🔴 CRITICAL |
| 12 | **LiteLLM** | LLM Proxy | `LITELLM_PORT=4000`\<br\>`LITELLM_MASTER_KEY=`\<br\>`LITELLM_SALT_KEY=`\<br\>`DATABASE_URL=postgresql://...`\<br\>`STORE_MODEL_IN_DB=true`\<br\>`UI_USERNAME=`\<br\>`UI_PASSWORD=`\<br\>\<br\>**Per Provider:**\<br\>`OPENAI_API_KEY=`\<br\>`ANTHROPIC_API_KEY=`\<br\>`GOOGLE_API_KEY=`\<br\>`GROQ_API_KEY=`\<br\>`MISTRAL_API_KEY=`\<br\>`COHERE_API_KEY=`\<br\>`TOGETHER_API_KEY=`\<br\>`PERPLEXITY_API_KEY=`\<br\>`DEEPSEEK_API_KEY=`\<br\>`XAI_API_KEY=`\<br\>`FIREWORKS_API_KEY=`\<br\>`OPENROUTER_API_KEY=`\<br\>\<br\>**Routing:**\<br\>`ROUTING_STRATEGY=complexity-based/internal-only/external-only/fallback`\<br\>`COMPLEXITY_THRESHOLD=2000`\<br\>`FALLBACK_MODELS=` (comma-separated) | `compose/litellm.yml`\<br\>`env/litellm.env`\<br\>`config/litellm/config.yaml` (routing rules) | All AI platforms | 🔴 CRITICAL |
| 13 | **LocalAI** | LLM Alt | `LOCALAI_PORT=8080`\<br\>`LOCALAI_MODELS_PATH=/models`\<br\>`THREADS=4`\<br\>`CONTEXT_SIZE=4096` | `compose/localai.yml`\<br\>`env/localai.env` | Alternative to Ollama | 🟢 LOW |
| **AI PLATFORMS** |  |  |  |  |  |  |
| 14 | **OpenWebUI** | Chat UI | `WEBUI_PORT=8080`\<br\>`OLLAMA_BASE_URL=http://ollama:11434`\<br\>`WEBUI_SECRET_KEY=`\<br\>`WEBUI_NAME="AI Platform"`\<br\>`DEFAULT_MODELS=`\<br\>`DEFAULT_USER_ROLE=user`\<br\>\<br\>**RAG Config:**\<br\>`RAG_EMBEDDING_MODEL=nomic-embed-text`\<br\>`RAG_VECTOR_DB=qdrant`\<br\>`QDRANT_URL=http://qdrant:6333`\<br\>`QDRANT_API_KEY=` | `compose/openwebui.yml`\<br\>`env/openwebui.env` | Ollama, Qdrant | 🔴 CRITICAL |
| 15 | **AnythingLLM** | Document AI | `SERVER_PORT=3001`\<br\>`STORAGE_DIR=/app/storage`\<br\>`JWT_SECRET=`\<br\>`LLM_PROVIDER=ollama`\<br\>`EMBEDDING_ENGINE=ollama`\<br\>`EMBEDDING_MODEL=nomic-embed-text`\<br\>\<br\>**Vector DB:**\<br\>`VECTOR_DB=qdrant`\<br\>`QDRANT_ENDPOINT=http://qdrant:6333`\<br\>`QDRANT_API_KEY=` | `compose/anythingllm.yml`\<br\>`env/anythingllm.env` | Ollama, Qdrant | 🔴 CRITICAL |
| 16 | **Dify** | AI Workflow | `DIFY_PORT=80`\<br\>`MODE=production`\<br\>`SECRET_KEY=`\<br\>`INIT_PASSWORD=`\<br\>`CONSOLE_WEB_URL=https://domain/dify`\<br\>`SERVICE_API_URL=https://domain/dify/api`\<br\>\<br\>**Database:**\<br\>`DB_HOST=postgres`\<br\>`DB_PORT=5432`\<br\>`DB_DATABASE=dify`\<br\>`DB_USERNAME=dify`\<br\>`DB_PASSWORD=`\<br\>\<br\>**Redis:**\<br\>`REDIS_HOST=redis`\<br\>`REDIS_PORT=6379`\<br\>`REDIS_PASSWORD=`\<br\>`REDIS_USE_SSL=false`\<br\>`REDIS_DB=0`\<br\>\<br\>**Vector DB:**\<br\>`VECTOR_STORE=qdrant`\<br\>`QDRANT_URL=http://qdrant:6333`\<br\>`QDRANT_API_KEY=`\<br\>`QDRANT_CLIENT_TIMEOUT=20`\<br\>\<br\>**Storage:**\<br\>`STORAGE_TYPE=local`\<br\>`STORAGE_LOCAL_PATH=/app/storage` | `compose/dify.yml` (api \+ worker \+ web)\<br\>`env/dify.env` | Postgres, Redis, Qdrant, Ollama, LiteLLM | 🔴 CRITICAL |
| 17 | **N8N** | Workflow | `N8N_PORT=5678`\<br\>`N8N_HOST=n8n`\<br\>`N8N_PROTOCOL=https`\<br\>`N8N_EDITOR_BASE_URL=https://domain/n8n`\<br\>`WEBHOOK_URL=https://domain/n8n`\<br\>`N8N_ENCRYPTION_KEY=`\<br\>\<br\>**Database:**\<br\>`DB_TYPE=postgresdb`\<br\>`DB_POSTGRESDB_HOST=postgres`\<br\>`DB_POSTGRESDB_PORT=5432`\<br\>`DB_POSTGRESDB_DATABASE=n8n`\<br\>`DB_POSTGRESDB_USER=n8n`\<br\>`DB_POSTGRESDB_PASSWORD=`\<br\>\<br\>**Redis Queue:**\<br\>`QUEUE_BULL_REDIS_HOST=redis`\<br\>`QUEUE_BULL_REDIS_PORT=6379`\<br\>`QUEUE_BULL_REDIS_PASSWORD=`\<br\>`EXECUTIONS_MODE=queue`\<br\>\<br\>**User Management:**\<br\>`N8N_USER_MANAGEMENT_DISABLED=false`\<br\>`N8N_EMAIL_MODE=smtp` (optional) | `compose/n8n.yml`\<br\>`env/n8n.env` | Postgres, Redis, Signal, GDrive | 🔴 CRITICAL |
| 18 | **Flowise** | Low-code AI | `FLOWISE_PORT=3000`\<br\>`FLOWISE_USERNAME=`\<br\>`FLOWISE_PASSWORD=`\<br\>`PASSPHRASE=`\<br\>\<br\>**Database:**\<br\>`DATABASE_TYPE=postgres`\<br\>`DATABASE_HOST=postgres`\<br\>`DATABASE_PORT=5432`\<br\>`DATABASE_NAME=flowise`\<br\>`DATABASE_USER=flowise`\<br\>`DATABASE_PASSWORD=`\<br\>\<br\>**Vector DB (in flows):**\<br\>Configured via UI to connect to Qdrant | `compose/flowise.yml`\<br\>`env/flowise.env` | Postgres, Qdrant (via UI), Ollama | 🔴 CRITICAL |
| **OBSERVABILITY** |  |  |  |  |  |  |
| 19 | **Langfuse** | LLM Observability | `LANGFUSE_PORT=3000`\<br\>`NEXTAUTH_URL=https://domain/langfuse`\<br\>`NEXTAUTH_SECRET=`\<br\>`SALT=`\<br\>`ENCRYPTION_KEY=`\<br\>\<br\>**Database:**\<br\>`DATABASE_URL=postgresql://langfuse:pass@postgres:5432/langfuse`\<br\>\<br\>**Auth:**\<br\>`LANGFUSE_INIT_USER_EMAIL=`\<br\>`LANGFUSE_INIT_USER_PASSWORD=`\<br\>`LANGFUSE_INIT_PROJECT_NAME="AI Platform"`\<br\>`LANGFUSE_INIT_PROJECT_PUBLIC_KEY=`\<br\>`LANGFUSE_INIT_PROJECT_SECRET_KEY=` | `compose/langfuse.yml`\<br\>`env/langfuse.env` | Postgres, LiteLLM integration | 🟡 HIGH |
| 20 | **Prometheus** | Metrics | `PROMETHEUS_PORT=9090`\<br\>`SCRAPE_INTERVAL=15s`\<br\>`RETENTION_TIME=15d`\<br\>\<br\>**Scrape Configs:**\<br\>- Node Exporter\<br\>- cAdvisor\<br\>- All services with /metrics | `compose/prometheus.yml`\<br\>`env/prometheus.env`\<br\>`config/prometheus/prometheus.yml` | All services | 🟡 MEDIUM |
| 21 | **Grafana** | Dashboards | `GRAFANA_PORT=3000`\<br\>`GF_SECURITY_ADMIN_USER=admin`\<br\>`GF_SECURITY_ADMIN_PASSWORD=`\<br\>`GF_SERVER_ROOT_URL=https://domain/grafana`\<br\>`GF_AUTH_ANONYMOUS_ENABLED=false`\<br\>\<br\>**Datasources:**\<br\>- Prometheus\<br\>- Loki\<br\>- Postgres (optional) | `compose/grafana.yml`\<br\>`env/grafana.env`\<br\>`config/grafana/datasources.yml`\<br\>`config/grafana/dashboards/*.json` | Prometheus, Loki | 🟡 MEDIUM |
| 22 | **Loki \+ Promtail** | Logs | `LOKI_PORT=3100`\<br\>`LOKI_RETENTION_PERIOD=168h`\<br\>`PROMTAIL_PORT=9080` | `compose/loki.yml`\<br\>`compose/promtail.yml`\<br\>`env/loki.env`\<br\>`config/loki/loki-config.yaml`\<br\>`config/promtail/promtail-config.yaml` | Grafana, all containers | 🟡 MEDIUM |
| 23 | **cAdvisor** | Container Stats | `CADVISOR_PORT=8080` | `compose/cadvisor.yml`\<br\>`env/cadvisor.env` | Prometheus | 🟡 MEDIUM |
| 24 | **Node Exporter** | Host Metrics | `NODE_EXPORTER_PORT=9100` | `compose/node-exporter.yml`\<br\>`env/node-exporter.env` | Prometheus | 🟡 MEDIUM |

---

## **TABLE 2: CORRECTED USER INTERACTION FLOW**

Copy table

| Step | Phase | Interaction | Output Files | Next Script Uses | Priority |
| ----- | ----- | ----- | ----- | ----- | ----- |
| **0** | **PRE-FLIGHT** | Port availability check (80, 443, all services) | `metadata/port_check.json` | Script 2 validates before deploy | 🔴 CRITICAL |
| **1** | **PROXY SELECTION** | **CORRECTED:**\<br\>1) Nginx\<br\>2) Traefik\<br\>3) **Caddy**\<br\>4) None\<br\>\<br\>+ SSL type selection | `compose/{nginx|traefik|caddy}.yml`\<br\>`env/{proxy}.env`\<br\>`config/{proxy}/...`\<br\>`metadata/proxy_config.json` | Script 2 deploys proxy first | 🔴 CRITICAL |
| 2 | **DOMAIN/IP** | Domain input → DNS resolution → Store public IP | `metadata/network_config.json` | Script 2 configures proxy routing | 🔴 CRITICAL |
| 3 | **DIRECTORY** | Validate `/mnt/data`, create structure | `metadata/directory_structure.json` | Script 2 mounts volumes | 🔴 CRITICAL |
| 4 | **VECTOR DB** | Qdrant / Weaviate / Milvus choice | `compose/{vectordb}.yml`\<br\>`env/{vectordb}.env`\<br\>`metadata/vectordb_choice.json` | Script 3 configures AI platforms to use it | 🔴 CRITICAL |
| 5 | **OLLAMA MODELS** | **Dynamic fetch** from `ollama.ai/library/api`, user selects | `metadata/ollama_models.json`\<br\>`env/ollama.env` | Script 2 downloads selected models | 🔴 CRITICAL |
| 6 | **LLM PROVIDERS** | **All 12 providers** (OpenAI, Anthropic, Google, Groq, Mistral, Cohere, Together, Perplexity, DeepSeek, xAI, Fireworks, OpenRouter) | `env/litellm.env` (per-provider API keys)\<br\>`metadata/providers.json` | Script 2 configures LiteLLM | 🔴 CRITICAL |
| 7 | **LITELLM ROUTING** | Strategy selection:\<br\>1) Internal-only\<br\>2) External-only\<br\>3) **Hybrid (complexity-based)**\<br\>4) Fallback chain | `config/litellm/config.yaml`\<br\>`metadata/routing_strategy.json` | Script 2 loads routing config | 🔴 CRITICAL |
| 8 | **AI PLATFORMS** | Service selection \+ per-service config | Individual `compose/*.yml` \+ `env/*.env` files | Script 2 deploys selected services | 🔴 CRITICAL |
| 9 | **VECTOR DB INTEGRATION** | **Auto-configure** all selected AI platforms to use chosen vector DB | Updates to `env/dify.env`, `env/anythingllm.env`, `env/openwebui.env` | Script 3 verifies connections | 🔴 CRITICAL |
| 10 | **SIGNAL-API** | Method selection:\<br\>1) QR Code\<br\>2) API registration | `compose/signal-api.yml`\<br\>`env/signal-api.env`\<br\>`metadata/signal_config.json` | Script 2 starts pairing process | 🔴 CRITICAL |
| 11 | **GOOGLE DRIVE** | Auth method:\<br\>1) OAuth\<br\>2) Service Account\<br\>3) API Key | `compose/gdrive.yml`\<br\>`env/gdrive.env`\<br\>`config/gdrive/credentials.json`\<br\>`metadata/gdrive_config.json` | Script 3 completes OAuth flow if needed | 🔴 CRITICAL |
| 12 | **MONITORING** | Service selection (Langfuse, Prometheus, etc.) | Individual `compose/*.yml` \+ `env/*.env` | Script 2 deploys monitoring stack | 🟡 HIGH |
| 13 | **SUMMARY** | Display all choices, confirm | `metadata/deployment_summary.json` | Script 2 reads as deployment plan | 🔴 CRITICAL |

## **SUCCESS CRITERIA BY PHASE**

### **Phase 0 (Cleanup)**

* ✅ System returned to clean state  
* ✅ No orphaned containers/volumes/networks  
* ✅ Ready for fresh deployment

### **Phase 1 (Setup)**

* ✅ All ports allocated without conflicts  
* ✅ User reviewed and approved configuration  
* ✅ `.env` file generated (pure text, no ANSI codes)  
* ✅ Docker group permissions active  
* ✅ Reverse proxy config files created  
* ✅ NO containers running yet

### **Phase 2 (Deployment)**

* ✅ All containers running with `restart: unless-stopped`  
* ✅ All services pass health checks  
* ✅ Inter-service communication works  
* ✅ Reverse proxy routes traffic correctly  
* ✅ Tailscale connected  
* ✅ Credentials documented

### **Phase 3 (Configuration)**

* ✅ LLM models loaded in Ollama  
* ✅ LiteLLM routing configured (local → cloud fallback)  
* ✅ AnythingLLM using Qdrant \+ Ollama  
* ✅ OpenClaw linked to AnythingLLM  
* ✅ OpenClaw accessible via Tailscale HTTPS  
* ✅ Dify using LiteLLM gateway  
* ✅ Google Drive sync active  
* ✅ Services auto-start on reboot

### **Phase 4 (Extensibility)**

* ✅ New services can be added via standardized script  
* ✅ No modification of core scripts required  
* ✅ Automatic integration with existing infrastructure

---

## **FINAL VALIDATION CHECKLIST**

**After completing all 4 scripts, the system MUST:**

1. ✅ **Deploy from scratch** on fresh Ubuntu in \<30 minutes  
2. ✅ **Survive reboots** (all services auto-restart)  
3. ✅ **Route LLM requests** intelligently (local-first, cloud fallback)  
4. ✅ **Expose services** via HTTPS (Caddy auto-cert OR Nginx self-signed)  
5. ✅ **Secure remote access** via Tailscale VPN  
6. ✅ **Sync Google Drive** to `/mnt/data/gdrive/` automatically  
7. ✅ **Link OpenClaw** to AnythingLLM vector DB  
8. ✅ **Accessible endpoints:**  
   * Public: `https://domain/anythingllm`, `https://domain/dify`  
   * Private: `https://tailscale-ip:18789` (OpenClaw)  
9. ✅ **Zero manual configuration** (all via scripts)  
10. ✅ **Fully documented** (credentials.txt, .env, logs)

Codebase : 

* The repository [https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation](https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation)  
* high level objectives here : [https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/README.md](https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/README.md)  
* The previous (superseeded) high level objectives : [https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/3176f2f3da7ee9ccb2908380387df3e38923a8d4/README.md](https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/3176f2f3da7ee9ccb2908380387df3e38923a8d4/README.md)  
* script 0 : https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/0-complete-cleanup.sh  
* script 1: https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/1-setup-system.sh  
* script 2 : https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/2-deploy-services.sh  
* script 3 : https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/3-configure-services.sh  
* script 4 : https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/3-configure-services.sh  
    
* This was a good start ui wise : [https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/7df4b977d0d66f7dcdd0b099a38fb4011402d280/scripts/1-setup-system.sh](https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/7df4b977d0d66f7dcdd0b099a38fb4011402d280/scripts/1-setup-system.sh)  
* This was the iteration with more bugs : [https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/0af338937926c8d052d9a413b79409376e8c7dfa/scripts/1-setup-system.sh](https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/0af338937926c8d052d9a413b79409376e8c7dfa/scripts/1-setup-system.sh)  
* This was a good attempt to incorporate all mandatory variables from services : https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/069b5f51f047319120a1a97080116bbe4a1d322b/scripts/1-setup-system.sh


  
