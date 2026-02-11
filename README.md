\# \*\*AIPlatformAutomation — Full Solution v76.5.0\*\*

\`\# AIPlatformAutomation\`

\`\#\# Overview\`    
\`AIPlatformAutomation provides a \*\*fully modular, dockerized AI platform\*\* enabling:\`

\`- Internal LLMs (Ollama, LiteLLM, AnythingLLM)\`    
\`- External LLM providers (Google Gemini, OpenRouter, Groq, OpenAI)\`    
\`- AI applications (Dify, ComfyUI, OpenWebUI, Flowise, OpenClaw UI)\`    
\`- Vector databases (Chroma, Qdrant)\`    
\`- Monitoring stack (Grafana, Prometheus, ELK, Portainer)\`    
\`- Secure internal networking via Tailscale\`    
\`- Private embeddings and credentials management\`    
\`- Optional Google Drive sync\`    
\`- Signal integration for messaging\`

\`The platform is designed for \*\*fully autonomous deployment\*\* while offering a \*\*rich interactive UX\*\* with numbered selections, retry loops, icons, and post-step summaries.\`

\`\#\# Key Outcomes\`

\`- Fully autonomous AI platform.\`    
\`- On-premise embeddings for private data and synced data from gdrive in /mnt/data/gdrive\`    
\`- Modular stack for AI apps, internal and external LLMs.\`    
\`- customizable routing strategy internal/external via litellm,\`    
\`- Secure networking via Tailscale and optional public proxy.\`    
\`- Comprehensive logging, health checks, and interactive UX.\`

\#\# \\\#\\\# Expected behavior

\- Clean slate system, reset via script 0    
\- Step 1 to install required dependencies, collect all user variables in a nice UX flow interactively    
\- Step 2 deploys each service, performs health checks, display a summary of all services working    
\- Step 3 allow to re-configure a service (re-pair with signal, enter new auth key for gdrive, add a llm provider, change litellm query routing etc    
\- \\- step 4 allows the user to add a new service to the stack and re-deploy

After step2, most urls must be accessible (unless failed services which can be fixed in step3). From there:

\* A user will use openclaw to interrogate data and perfroam actions via channels    
\* A user will use anything llm to work on the same embeddings    
\* A user will use dify or any programmatic agentic flow that’s connected to the embeddings

Any queries will be routed locally first or externally (based on complexity and maybe more fine tuning later)

→\\\> the stack is DOCKERIZED as much as possible and automated and modular. Whilst scripts runs as sudo, they need to retrieve the $PID of the logged in user, and use this for paths, chmod operations etc. This stack may run tomorrow with a different OS, GPU enabled and potentially different EBS volumes, which is why script 1 should take care of mountain the device into /mnt/data, and script 0 deletes and unmount.

\\\#\\\# KEy architecture principles

\#\#\# \*\*2.2 Logging Standard\*\*

All scripts use a common logging pattern:

RED='\\\\033\\\[0;31m'    
GREEN='\\\\033\\\[0;32m'    
YELLOW='\\\\033\\\[1;33m'    
BLUE='\\\\033\\\[0;34m'    
CYAN='\\\\033\\\[0;36m'    
NC='\\\\033\\\[0m'

LOG\\\_FILE="${ROOT\\\_PATH}/logs/script-N.log"

log\\\_info()    { echo \\-e "${GREEN}\\\[INFO\\\]${NC}  $ 1" | tee \\-a " $ LOG\\\_FILE"; }    
log\\\_warn()    { echo \\-e "${YELLOW}\\\[WARN\\\]${NC}  $ 1" | tee \\-a " $ LOG\\\_FILE"; }    
log\\\_error()   { echo \\-e "${RED}\\\[ERROR\\\]${NC}  $ 1" | tee \\-a " $ LOG\\\_FILE"; }    
log\\\_section() { echo \\-e "\\\\n${CYAN}========================================${NC}" | tee \\-a " $ LOG\\\_FILE"    
                echo \\-e " $ {CYAN}   $ 1 $ {NC}" | tee \\-a " $ LOG\\\_FILE"    
                echo \\-e " $ {CYAN}========================================${NC}\\\\n" | tee \\-a "$LOG\\\_FILE"; }

\#\#\# \*\*2.3 Error Handling Standard\*\*

set \\-euo pipefail

trap 'error\\\_handler $? $LINENO  $ BASH\\\_COMMAND' ERR

error\\\_handler() {    
    local exit\\\_code= $ 1    
    local line\\\_number= $ 2    
    local command= $ 3    
    log\\\_error "Command failed at line ${line\\\_number}: ${command} (exit code: ${exit\\\_code})"    
    log\\\_error "Log file: ${LOG\\\_FILE}"    
    exit "${exit\\\_code}"    
}

\#\#\# \*\*2.4 Idempotency Pattern\*\*

Every function follows this pattern:

install\\\_something() {    
    if something\\\_already\\\_installed; then    
        log\\\_info "Something already installed, skipping"    
        return 0    
    fi    
    \\\# ... perform installation ...    
    log\\\_info "Something installed successfully"    
}

\#\# \*\*Section 4: Script Inventory & Flow\*\*

\#\#\# \*\*4.1 Execution Order\*\*

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

\`\*\*\* Target Folder Structure :\` 

\#\# \*\*MODULAR FILE STRUCTURE (CORRECTED)\*\*

/mnt/data/    
├── compose/                           \\\# Individual service compose files    
│   ├── nginx.yml                      \\\# If Nginx selected    
│   ├── traefik.yml                    \\\# If Traefik selected    
│   ├── caddy.yml                      \\\# If Caddy selected    
│   ├── postgres.yml                   \\\# Core infrastructure    
│   ├── redis.yml    
│   ├── qdrant.yml                     \\\# If Qdrant selected    
│   ├── weaviate.yml                   \\\# If Weaviate selected    
│   ├── milvus.yml                     \\\# If Milvus selected    
│   ├── ollama.yml                     \\\# LLM engines    
│   ├── litellm.yml    
│   ├── localai.yml                    \\\# If selected    
│   ├── openwebui.yml                  \\\# AI platforms (if selected)    
│   ├── anythingllm.yml    
│   ├── dify-api.yml                   \\\# Dify split into 3 services    
│   ├── dify-worker.yml    
│   ├── dify-web.yml    
│   ├── n8n.yml    
│   ├── flowise.yml    
│   ├── signal-api.yml                 \\\# Integrations (if selected)    
│   ├── gdrive.yml    
│   ├── langfuse.yml                   \\\# Monitoring (if selected)    
│   ├── prometheus.yml    
│   ├── grafana.yml    
│   ├── loki.yml    
│   ├── promtail.yml    
│   ├── cadvisor.yml    
│   └── node-exporter.yml    
│    
├── env/                               \\\# Individual service environment files    
│   ├── global.env                     \\\# Shared variables (domain, IPs, etc.)    
│   ├── nginx.env    
│   ├── traefik.env    
│   ├── caddy.env    
│   ├── postgres.env    
│   ├── redis.env    
│   ├── qdrant.env    
│   ├── ollama.env    
│   ├── litellm.env                    \\\# Contains all provider API keys    
│   ├── openwebui.env    
│   ├── anythingllm.env    
│   ├── dify.env                       \\\# Shared by all 3 Dify services    
│   ├── n8n.env    
│   ├── flowise.env    
│   ├── signal-api.env    
│   ├── gdrive.env    
│   ├── langfuse.env    
│   └── monitoring.env                 \\\# Shared by Prometheus, Grafana, Loki    
│    
├── config/                            \\\# Service-specific configuration files    
│   ├── nginx/    
│   │   ├── nginx.conf                 \\\# Main config    
│   │   ├── ssl/                       \\\# SSL certificates    
│   │   │   ├── dhparam.pem    
│   │   │   └── letsencrypt/    
│   │   └── sites/                     \\\# Per-service configs    
│   │       ├── openwebui.conf    
│   │       ├── anythingllm.conf    
│   │       ├── dify.conf    
│   │       ├── n8n.conf    
│   │       ├── flowise.conf    
│   │       ├── grafana.conf    
│   │       └── langfuse.conf    
│   │    
│   ├── traefik/    
│   │   ├── traefik.yml                \\\# Static config    
│   │   ├── acme.json                  \\\# Let's Encrypt certificates    
│   │   └── dynamic/                   \\\# Dynamic configs    
│   │       ├── routers.yml    
│   │       └── middlewares.yml    
│   │    
│   ├── caddy/    
│   │   ├── Caddyfile                  \\\# Main config (auto-HTTPS)    
│   │   └── data/                      \\\# Caddy data dir    
│   │    
│   ├── litellm/    
│   │   └── config.yaml                \\\# Routing strategy \\+ model definitions    
│   │    
│   ├── postgres/    
│   │   └── init.sql                   \\\# Create all databases \\+ users    
│   │    
│   ├── redis/    
│   │   └── redis.conf                 \\\# Redis configuration    
│   │    
│   ├── prometheus/    
│   │   └── prometheus.yml             \\\# Scrape configs for all services    
│   │    
│   ├── grafana/    
│   │   ├── datasources.yml            \\\# Prometheus, Loki    
│   │   └── dashboards/                \\\# Pre-configured dashboards    
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
│   │   └── promtail-config.yaml       \\\# Log collection from all containers    
│   │    
│   ├── gdrive/    
│   │   └── credentials.json           \\\# Service account key (if selected)    
│   │    
│   └── signal-api/    
│       └── signal-config.json    
│    
├── metadata/                          \\\# Script 1 outputs (used by script 2\\)    
│   ├── selected\\\_services.json         \\\# List of services user selected    
│   ├── configuration.json             \\\# All user inputs & generated secrets    
│   ├── deployment\\\_plan.json           \\\# Ordered deployment plan    
│   ├── proxy\\\_config.json              \\\# Proxy type & SSL settings    
│   ├── network\\\_config.json            \\\# Domain, IPs, DNS resolution    
│   ├── directory\\\_structure.json       \\\# Paths, symlinks    
│   ├── vectordb\\\_choice.json           \\\# Which vector DB was chosen    
│   ├── ollama\\\_models.json             \\\# Models to download    
│   ├── providers.json                 \\\# External LLM providers configured    
│   ├── routing\\\_strategy.json          \\\# LiteLLM routing logic    
│   ├── signal\\\_config.json             \\\# Signal pairing method & number    
│   ├── gdrive\\\_config.json             \\\# GDrive auth method & credentials    
│   ├── port\\\_check.json                \\\# Port availability results    
│   └── deployment\\\_summary.json        \\\# Human-readable summary    
│    
├── data/                              \\\# Actual persistent data    
│   ├── postgres/                      \\\# Database files    
│   ├── redis/                         \\\# Redis persistence    
│   ├── qdrant/                        \\\# Vector DB storage    
│   ├── ollama/models/                 \\\# Downloaded Ollama models    
│   ├── litellm/                       \\\# LiteLLM database    
│   ├── n8n/                           \\\# N8N workflows & executions    
│   ├── dify/                          \\\# Dify knowledge base & uploads    
│   ├── anythingllm/documents/         \\\# AnythingLLM documents    
│   ├── flowise/                       \\\# Flowise flows    
│   ├── grafana/                       \\\# Grafana dashboards & plugins    
│   ├── prometheus/                    \\\# Prometheus TSDB    
│   ├── loki/                          \\\# Loki chunks    
│   └── langfuse/                      \\\# Langfuse traces    
│    
└── backups/                           \\\# Backup location    
    └── pre-install-YYYYMMDD-HHMMSS.tar.gz

Script 2 will:    
1\\. Read metadata/\\\*.json files    
2\\. Merge compose/\\\*.yml files into final docker-compose.yml    
3\\. Merge env/\\\*.env files into final .env    
4\\. Copy config/\\\* to appropriate locations    
5\\. Deploy services based on deployment\\\_plan.json    
\`---\`

\`\#\# Network Architecture\`

     \`┌─────────────┐\`    
      \`│ Public IP 80\`      
      \`│ Proxy/SSL 443│\`    
      \`└─────┬──────┘\`    
            \`│\`    
      \`┌─────▼─────┐\`    
      \`│  Tailscale  │\`    
      \`│ IP :8443 )  │\`    
      \`└─────┬─────┘\`    
            \`│\`

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

\\\#\\\# Section 5: Script 0 — Cleanup System

\\\#\\\#\\\# 5.1 Purpose

\\\`0-cleanup.sh\\\` removes all traces of a previous installation so the system can be re-provisioned cleanly. It is \\\*\\\*optional\\\*\\\* — only needed when re-installing or resetting (to validate entire script consistency).

\\\#\\\#\\\# 5.2 Safety

The script requires explicit confirmation before proceeding. It distinguishes between:

\\- \\\*\\\*Soft reset\\\*\\\* — Stop containers, remove configs, keep data volumes    
\\- \\\*\\\*Hard reset\\\*\\\* — Remove everything including data volumes

\\\#\\\#\\\# 5.3 Execution

\\\`\\\`\\\`bash    
sudo bash 0-cleanup.sh          \\\# Interactive — asks which mode    
sudo bash 0-cleanup.sh \\--hard   \\\# Non-interactive hard reset    
sudo bash 0-cleanup.sh \\--soft   \\\# Non-interactive soft reset

\#\#\# \*\*5.4 Cleanup Phases\*\*

Phase 1: Stop & Remove Containers    
  ├── Find all docker-compose.\\\*.yml files in /mnt/data/ai-platform/docker/    
  ├── For each: docker compose \\-f \\\<file\\\> down \\--remove-orphans    
  ├── docker container prune \\-f    
  └── Remove external networks (ai-platform, ai-backend)

Phase 2: Remove Docker Volumes (hard mode only)    
  ├── docker volume ls \\--filter label=com.docker.compose.project    
  ├── docker volume rm \\\<each volume\\\>    
  └── docker volume prune \\-f

Phase 3: Stop Ollama (optional)    
  ├── systemctl stop ollama    
  ├── systemctl disable ollama    
  └── Note: does NOT uninstall Ollama binary (Script 1 handles install)

Phase 4: Remove Configuration Files    
  ├── rm \\-rf /mnt/data/ai-platform/config/\\\*    
  ├── rm \\-rf /mnt/data/ai-platform/docker/\\\*    
  ├── rm \\-rf /mnt/data/ai-platform/scripts/\\\*    
  └── rm \\-rf /mnt/data/ai-platform/logs/\\\*

Phase 5: Remove Data Directories (hard mode only)    
  ├── rm \\-rf /mnt/data/ai-platform/data/\\\*    
  └── rm \\-rf /mnt/data/ai-platform/backups/\\\*    
Phase 6 : apt purge, remove cache, docker purge, reboot

Script will handle re-creating all environment and directory    
Phase 1: Recreate Directory Structure    
  ├── mkdir \\-p /mnt/data/ai-platform/{config,docker,data,logs,scripts,backups}    
  └── chown \\-R ${SUDO\\\_USER:- $ USER}: $ {SUDO\\\_USER:-$USER} /mnt/data/ai-platform/

\#\#\# \*\*5.5 What It Does NOT Remove\*\*

\* Docker Engine itself (Script 1 manages this)    
\* NVIDIA drivers or Container Toolkit (Script 1 manages this)    
\* Ollama binary (Script 1 manages this)    
\* System packages    
\* User accounts

\#\# \*\*SCRIPT 1: SETUP SYSTEM\*\*

\#\#\# \*\*Intent\*\*

Prepare the complete foundation for deployment WITHOUT starting any AI services. This script collects all configuration, allocates ports, creates directory structures, and generates the master \`.env\` file.

\#\#\# \*\*Key Responsibilities\*\*

\#\#\#\# \*\*1\\. System Validation\*\*

\* Root privileges check    
\* Docker installation verification    
\* Docker daemon running check    
\* GPU detection (NVIDIA/AMD/None)

\#\#\#\# \*\*2\\. User & Permissions\*\*

\* Add user to \`docker\` group    
\* Automate session refresh (\`newgrp docker\` or logout warning)    
\* Create service user: \`ai-user\` (non-root for containers)    
\* Mount \`/mnt/data\` (persistent storage for large datasets)    
\* Create \`/mnt/data/gdrive/\` for rsync target and all directory structure for all stacks

\#\#\# \*\*Success Definition\*\*

\* ✅ All directories created    
\* ✅ \`/mnt/data\` mounted and accessible    
\* ✅ All ports allocated (no conflicts)    
\* ✅ \`.env\` file generated (pure text, no ANSI codes)    
\* ✅ \`credentials.txt\` prepared (populated in Script 2\\)    
\* ✅ Reverse proxy config files created (not deployed)    
\* ✅ User confirmed configuration summary    
\* ✅ Docker group permissions active    
\* ✅ NO containers running yet

\`UI EXPECTED OUTPUTS\` 

\`Script 1 expected output :\`   

# **SCRIPT 1: COMPLETE UI FLOW \- CORRECTED**

## **System Setup & Configuration Collection**

**Version:** 4.0.0  
 **Purpose:** Collect ALL configuration, generate modular files, prepare metadata  
 **Path:** All files in `/mnt/data/` (NO `/opt`)  
 **Important:** This script does NOT deploy \- only prepares configuration

---

## **🎯 Complete Variable Collection List (67 Variables)**

### **System Detection (Auto) \- 7 variables**

* OS type and version  
* CPU cores  
* RAM (GB)  
* Disk space (GB)  
* GPU type (nvidia/amd/intel/apple/none)  
* GPU count  
* Hardware mode (gpu/cpu)

### **Network & Domain \- 5 variables**

* Base domain  
* Proxy type (nginx/traefik/caddy/none)  
* SSL type (letsencrypt/self-signed/none)  
* Let's Encrypt email (if applicable)  
* Cloudflare API token (optional, for DNS challenge)

### **Core Infrastructure \- 4 variables**

* Vector DB choice (qdrant/weaviate/milvus)  
* PostgreSQL version  
* Redis version  
* Object storage type (minio/s3)

### **Core AI Services \- 8 variables**

* Ollama enable (Y/n)  
* Ollama models list (comma-separated)  
* Ollama port (default: 11434\)  
* LiteLLM enable (Y/n)  
* LiteLLM port (default: 4000\)  
* LiteLLM routing strategy (cost/latency/simple-shuffle/usage)  
* Open WebUI enable (Y/n)  
* Open WebUI port (default: 3000\)

### **AI Platforms \- 6 variables**

* AnythingLLM enable (y/N)  
* AnythingLLM port (default: 3001\)  
* Dify enable (y/N)  
* Dify API port (default: 5001\)  
* Dify Web port (default: 3002\)  
* Dify sandbox enable (for code execution)

### **Workflow Tools \- 6 variables**

* n8n enable (y/N)  
* n8n port (default: 5678\)  
* Flowise enable (y/N)  
* Flowise port (default: 3003\)  
* Apache Airflow enable (y/N)  
* Airflow webserver port (default: 8080\)

### **Search & Web Scraping \- 7 variables**

* OpenClaw enable (y/N)  
* OpenClaw port (default: 8000\)  
* Brave Search API key (for web search)  
* SerpAPI key (alternative web search)  
* Web search provider (brave/serpapi/none)  
* Firecrawl enable (for web scraping)  
* Firecrawl API key

### **Signal API \- 5 variables**

* Signal API enable (y/N)  
* Signal API port (default: 8080\)  
* Signal phone number (E.164 format)  
* Signal auth method (qr-code/linking-code)  
* Signal webhook URL (for incoming messages)

### **Google Drive Integration \- 7 variables**

* Google Drive enable (y/N)  
* GDrive auth method (oauth/service-account/rclone)  
* GDrive Client ID (if oauth)  
* GDrive Client Secret (if oauth)  
* GDrive Service Account JSON (if service-account)  
* GDrive sync interval (minutes, default: 15\)  
* GDrive target folders (comma-separated)

### **Tailscale VPN \- 3 variables**

* Tailscale enable (y/N)  
* Tailscale auth key  
* Tailscale exit node enable (y/N)

### **LLM Provider API Keys \- 7 variables**

* OpenAI API key  
* Anthropic API key  
* Google Gemini API key  
* Groq API key  
* Mistral API key  
* OpenRouter API key  
* HuggingFace API key

### **Auto-Generated Secrets (Overridable) \- 12 variables**

Each with: auto-generate OR custom value option

* PostgreSQL master password  
* Redis password  
* Qdrant API key  
* Admin password (for UIs)  
* JWT secret (for auth)  
* Encryption key (for data at rest)  
* n8n encryption key  
* Dify secret key  
* MinIO root password  
* Grafana admin password  
* LiteLLM master key  
* Webhook secret (for integrations)

---

## **📺 COMPLETE UI FLOW**

╔════════════════════════════════════════════════════════════════════╗  
║                                                                    ║  
║            AI PLATFORM AUTOMATION \- SETUP                          ║  
║                      Version 4.0.0                                 ║  
║               Configuration Collection Only                        ║  
║                  (No Deployment in Script 1\)                       ║  
║                                                                    ║  
╚════════════════════════════════════════════════════════════════════╝

All files will be created in: /mnt/data/  
Deployment will happen in Script 2

Repository root: /home/user/AIPlatformAutomation  
Running as user: john

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 1: System Detection & Hardware Configuration                ║  
╚════════════════════════════════════════════════════════════════════╝

▶ Detecting system hardware...

System Information:  
  • OS: ubuntu 22.04  
  • Architecture: x86\_64  
  • CPU Cores: 8  
  • RAM: 32GB  
  • Available Disk: 250GB

▶ GPU Detection...  
  Checking for NVIDIA GPUs... ✓ Found  
  • GPU Type: NVIDIA GeForce RTX 3090  
  • GPU Count: 1  
  • CUDA Version: 12.1  
  • Driver Version: 525.147.05

Hardware Mode: GPU-Accelerated ✓

▶ Checking system requirements (guidelines)...  
✓ CPU: 8 cores (4+ recommended)  
✓ RAM: 32GB (16GB+ recommended)    
✓ Disk: 250GB (50GB+ minimum)  
✓ GPU: NVIDIA detected (optional but recommended)

⚠ Note: Your system exceeds minimum requirements  
  GPU acceleration will be enabled for:  
  \- Ollama (local LLM inference)  
  \- Dify (if using local embeddings)  
  \- Any ML workloads

Continue with GPU-accelerated configuration? (Y/n): y

✓ System detection completed  
  Mode: GPU-Accelerated  
  Ollama will use: NVIDIA GPU  
  Recommended models: llama3.1:70b, mixtral:8x7b, codestral

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 2: Package Installation                                     ║  
╚════════════════════════════════════════════════════════════════════╝

ℹ Installing system dependencies...  
  (These were removed by Script 0 cleanup)

▶ Essential packages:  
  ✓ curl  
  ✓ wget  
  ✓ git  
  ✓ jq (for JSON processing)  
  ✓ openssl (for secret generation)  
  ✓ ca-certificates  
  ✓ gnupg

▶ Docker prerequisites:  
  ✓ apt-transport-https  
  ✓ software-properties-common  
  ✓ lsb-release

▶ Network tools:  
  ✓ net-tools  
  ✓ dnsutils  
  ✓ iputils-ping

▶ Monitoring tools:  
  ✓ htop  
  ✓ iotop  
  ✓ ncdu

✓ All system packages installed

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 3: Docker Installation & Configuration                      ║  
╚════════════════════════════════════════════════════════════════════╝

▶ Checking Docker installation...

Docker not found. Installing Docker CE...

▶ Adding Docker's official GPG key...  
✓ GPG key added

▶ Adding Docker repository...  
✓ Repository configured for ubuntu jammy

▶ Installing Docker packages...  
  ✓ docker-ce (25.0.3)  
  ✓ docker-ce-cli  
  ✓ containerd.io  
  ✓ docker-buildx-plugin  
  ✓ docker-compose-plugin

▶ Configuring Docker daemon...  
  Log driver: json-file (max-size: 10m, max-file: 3\)  
  Live restore: enabled  
  Storage driver: overlay2  
    
▶ GPU Support Configuration...  
  ✓ NVIDIA Container Toolkit detected  
  ✓ GPU runtime configured

▶ Starting Docker service...  
  ✓ Docker daemon started  
  ✓ Docker daemon enabled (auto-start on boot)

▶ User configuration...  
  ✓ User 'john' added to docker group  
  ⚠ You'll need to log out and back in for group changes to take effect

✓ Docker installed successfully  
  Version: Docker version 25.0.3, build 4debf41  
  Compose: Docker Compose version v2.24.5

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 4: Directory Structure Creation                             ║  
╚════════════════════════════════════════════════════════════════════╝

ℹ Creating modular directory structure at /mnt/data/...

▶ Creating core directories:  
  ✓ /mnt/data/compose/           (individual service compose files)  
  ✓ /mnt/data/env/               (individual service .env files)  
  ✓ /mnt/data/config/            (service-specific configs)  
  ✓ /mnt/data/metadata/          (deployment metadata)  
  ✓ /mnt/data/logs/              (setup logs)  
  ✓ /mnt/data/secrets/           (encrypted secrets storage)

▶ Creating config subdirectories:  
  ✓ /mnt/data/config/nginx/  
  ✓ /mnt/data/config/traefik/  
  ✓ /mnt/data/config/caddy/  
  ✓ /mnt/data/config/litellm/  
  ✓ /mnt/data/config/ollama/  
  ✓ /mnt/data/config/postgres/  
  ✓ /mnt/data/config/prometheus/  
  ✓ /mnt/data/config/grafana/  
  ✓ /mnt/data/config/loki/

▶ Setting permissions:  
  ✓ Owner: john:john (UID:1000, GID:1000)  
  ✓ Permissions: 755 (directories), 600 (secrets)

✓ Directory structure created  
  Base: /mnt/data/

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 5: Docker Networks Creation                                 ║  
╚════════════════════════════════════════════════════════════════════╝

▶ Creating Docker networks for service isolation...

  ✓ ai-platform               (bridge, public services)  
  ✓ ai-platform-internal      (internal, isolated services)  
  ✓ ai-platform-monitoring    (monitoring stack)

Network architecture:  
  • Public services (OpenWebUI, Dify) → ai-platform  
  • Databases, queues → ai-platform-internal  
  • Prometheus, Grafana → ai-platform-monitoring  
  • Proxy can access all networks

✓ Docker networks configured

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 6: Firewall Configuration                                   ║  
╚════════════════════════════════════════════════════════════════════╝

ℹ Firewall management delegated to EC2 Security Groups

⚠ IMPORTANT: Configure your EC2 Security Group to allow:  
  • SSH (22/tcp) \- from your IP only  
  • HTTP (80/tcp) \- if using Let's Encrypt  
  • HTTPS (443/tcp) \- for public access  
  • Custom ports \- if exposing services directly

This script does NOT configure UFW or iptables.  
All firewall rules should be managed at the EC2 level.

✓ Firewall note recorded

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 7: Reverse Proxy Selection                                  ║  
╚════════════════════════════════════════════════════════════════════╝

Select reverse proxy for public access:

  1\) Nginx      \- Traditional, battle-tested, full control  
  2\) Traefik    \- Modern, auto-discovery, Docker labels  
  3\) Caddy      \- Automatic HTTPS, zero config  
  4\) None       \- Direct port access (testing only)

Which proxy? \[1-4\] (default: 3): 3

Selected: Caddy ✓

▶ Caddy configuration:  
  Automatic HTTPS: Yes  
  HTTP/3 support: Yes  
  Auto-reload on config change: Yes

✓ Proxy type: caddy

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 8: Domain & SSL Configuration                               ║  
╚════════════════════════════════════════════════════════════════════╝

Domain Configuration  
────────────────────────────────────────────────────────────

Enter your base domain (e.g., example.com): ai.mycompany.com

✓ Domain: ai.mycompany.com

Services will be accessible at:  
  • Open WebUI:  https://chat.ai.mycompany.com  
  • Dify:        https://dify.ai.mycompany.com  
  • n8n:         https://workflows.ai.mycompany.com  
  • Grafana:     https://metrics.ai.mycompany.com  
  • LiteLLM:     https://api.ai.mycompany.com

SSL Certificate Configuration  
────────────────────────────────────────────────────────────

  1\) Let's Encrypt \- Free, automatic renewal, requires DNS  
  2\) Self-signed   \- Testing/internal use only  
  3\) None          \- HTTP only (not recommended)

Select SSL type \[1-3\] (default: 1): 1

Selected: Let's Encrypt ✓

Enter email for Let's Encrypt notifications: admin@mycompany.com

✓ SSL Type: letsencrypt  
✓ Email: admin@mycompany.com

⚠ DNS Configuration Required:  
  Before running Script 2, create DNS A records:  
  • chat.ai.mycompany.com      → \<your-server-ip\>  
  • dify.ai.mycompany.com      → \<your-server-ip\>  
  • workflows.ai.mycompany.com → \<your-server-ip\>  
  • metrics.ai.mycompany.com   → \<your-server-ip\>  
  • api.ai.mycompany.com       → \<your-server-ip\>

Optional: Use Cloudflare DNS Challenge?  
(Allows SSL without exposing port 80\) (y/N): y

Enter Cloudflare API Token: \[paste token\]

✓ Cloudflare DNS challenge configured

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 9: Core Infrastructure Selection                            ║  
╚════════════════════════════════════════════════════════════════════╝

━━━ PostgreSQL Configuration ━━━

PostgreSQL is REQUIRED for:  
  • LiteLLM (request logging, API keys)  
  • n8n (workflows, credentials)  
  • Dify (app configurations)  
  • Flowise (chatflows)  
  • Langfuse (observability logs)

PostgreSQL Version:  
  1\) 16 (latest, recommended)  
  2\) 15  
  3\) 14

Select version \[1-3\] (default: 1): 1

✓ PostgreSQL: 16-alpine

━━━ Redis Configuration ━━━

Redis is REQUIRED for:  
  • Caching (LiteLLM, Dify)  
  • Queue management (n8n, Airflow)  
  • Session storage

✓ Redis: 7-alpine

━━━ Vector Database Selection ━━━

A vector database is REQUIRED for RAG capabilities.  
Choose ONE:

  1\) Qdrant     \- Fastest, simplest, recommended  
  2\) Weaviate   \- Advanced, graph capabilities  
  3\) Milvus     \- Enterprise-scale, most complex

Select vector DB \[1-3\] (default: 1): 1

✓ Vector DB: Qdrant

━━━ Object Storage ━━━

For file uploads, backups, artifacts:

  1\) MinIO      \- Self-hosted S3-compatible  
  2\) AWS S3     \- Managed service (requires credentials)  
  3\) None       \- Use local filesystem only

Select storage \[1-3\] (default: 1): 1

✓ Object Storage: MinIO

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 10: Core AI Services Configuration                          ║  
╚════════════════════════════════════════════════════════════════════╝

━━━ Ollama (Local LLM Engine) ━━━

Install Ollama for local LLM inference? (Y/n): y

✓ Ollama: enabled

▶ Ollama Configuration:

Port for Ollama API \[default: 11434\]: 11434  
✓ Port: 11434

GPU Configuration:  
  Detected: NVIDIA GeForce RTX 3090  
  ✓ GPU acceleration: ENABLED  
  ✓ CUDA layers: All layers on GPU

Which models to pre-download? (comma-separated)  
Recommended for your GPU (24GB VRAM):  
  \- llama3.1:8b       (4.7GB)  \- Fast, general purpose  
  \- llama3.1:70b      (40GB)   \- Powerful, needs offloading  
  \- mixtral:8x7b      (26GB)   \- Good quality/speed  
  \- codestral:22b     (12GB)   \- Best for coding  
  \- phi3:mini         (2.3GB)  \- Tiny, fast

Enter model list: llama3.1:8b,codestral:22b,phi3:mini

✓ Models to download: llama3.1:8b, codestral:22b, phi3:mini  
  Total size: \~19GB

━━━ LiteLLM (AI Gateway & Router) ━━━

Install LiteLLM for unified AI API? (Y/n): y

✓ LiteLLM: enabled

▶ LiteLLM Configuration:

Port for LiteLLM API \[default: 4000\]: 4000  
✓ Port: 4000

Routing Strategy:  
  1\) cost           \- Cheapest model first  
  2\) latency        \- Fastest response first  
  3\) simple-shuffle \- Random load balancing  
  4\) usage          \- Least-used model first

Select strategy \[1-4\] (default: 1): 1

✓ Routing: cost-based (Ollama free → Groq cheap → OpenAI expensive)

Database for LiteLLM:  
  ✓ PostgreSQL database: litellm\_db (will be auto-created)  
  ✓ Logging: All requests logged  
  ✓ Caching: Redis cache enabled

━━━ Open WebUI (Chat Interface) ━━━

Install Open WebUI for chat interface? (Y/n): y

✓ Open WebUI: enabled

Port for Open WebUI \[default: 3000\]: 3000  
✓ Port: 3000

Connect to:  
  ✓ Ollama: http://ollama:11434  
  ✓ LiteLLM: http://litellm:4000  
  ✓ Vector DB: Qdrant

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 11: AI Platform Services                                    ║  
╚════════════════════════════════════════════════════════════════════╝

━━━ AnythingLLM ━━━

Install AnythingLLM? (y/N): n

━━━ Dify (AI Application Platform) ━━━

Install Dify for building AI apps? (y/N): y

✓ Dify: enabled

▶ Dify Configuration:

API Port \[default: 5001\]: 5001  
Web UI Port \[default: 3002\]: 3002

✓ Ports: API 5001, Web 3002

Enable Dify Sandbox (for code execution)? (y/N): y  
✓ Sandbox: enabled (isolated Docker-in-Docker)

Dify will use:  
  ✓ PostgreSQL: dify\_db (auto-created)  
  ✓ Redis: Caching  
  ✓ Qdrant: Vector storage  
  ✓ LiteLLM: LLM routing

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 12: Workflow Automation Tools                               ║  
╚════════════════════════════════════════════════════════════════════╝

━━━ n8n (Workflow Automation) ━━━

Install n8n? (y/N): y

✓ n8n: enabled

Port \[default: 5678\]: 5678  
✓ Port: 5678

n8n will use:  
  ✓ PostgreSQL: n8n\_db (auto-created)  
  ✓ Encryption: Auto-generated key

━━━ Flowise ━━━

Install Flowise (no-code AI workflows)? (y/N): y

✓ Flowise: enabled

Port \[default: 3003\]: 3003  
✓ Port: 3003

━━━ Apache Airflow ━━━

Install Apache Airflow (data orchestration)? (y/N): n

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 13: Search & Web Scraping                                   ║  
╚════════════════════════════════════════════════════════════════════╝

━━━ OpenClaw (AI Web Agent) ━━━

Install OpenClaw for web browsing/research? (y/N): y

✓ OpenClaw: enabled

Port \[default: 8000\]: 8000  
✓ Port: 8000

Web Search Provider:  
  1\) Brave Search    \- Fast, privacy-focused (API key required)  
  2\) SerpAPI         \- Google results (API key required)  
  3\) None            \- No web search

Select provider \[1-3\] (default: 1): 1

Enter Brave Search API Key: BSA\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*

✓ Brave Search API: configured

━━━ Firecrawl ━━━

Install Firecrawl for web scraping? (y/N): n

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 14: Signal API Configuration                                ║  
╚════════════════════════════════════════════════════════════════════╝

━━━ Signal API (SMS/Messaging) ━━━

Install Signal API for messaging? (y/N): y

✓ Signal API: enabled

Port \[default: 8080\]: 8080  
✓ Port: 8080

Signal Phone Number (E.164 format, e.g., \+14155551234): \+14155551234  
✓ Phone: \+14155551234

Registration Method:  
  1\) QR Code        \- Scan with Signal app (easier)  
  2\) Linking Code   \- Enter 6-digit code from app

Select method \[1-2\] (default: 1): 1

✓ Method: QR Code (will be shown during Script 2 deployment)

Webhook URL for incoming messages (optional):  
Leave blank to skip: https://api.mycompany.com/webhooks/signal

✓ Webhook: https://api.mycompany.com/webhooks/signal

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 15: Google Drive Integration                                ║  
╚════════════════════════════════════════════════════════════════════╝

━━━ Google Drive Sync ━━━

Install Google Drive integration? (y/N): y

✓ Google Drive: enabled

Authentication Method:  
  1\) OAuth          \- Interactive browser auth (easiest)  
  2\) Service Account \- JSON key file (automated)  
  3\) Rclone Config  \- Pre-configured rclone.conf

Select method \[1-3\] (default: 1): 2

✓ Method: Service Account

Upload/paste Service Account JSON:  
(Contents will be securely stored)

\[Paste JSON content here\]

✓ Service Account: configured

Folders to sync (comma-separated, or \* for all):  
  e.g., "Documents/AI,Projects/Research"

Enter folders: Documents/AI,Research

✓ Folders: Documents/AI, Research

Sync interval (minutes) \[default: 15\]: 15  
✓ Interval: 15 minutes

Target directory in AnythingLLM/Dify: /data/gdrive  
✓ Auto-ingestion: enabled

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 16: Tailscale VPN (Optional)                                ║  
╚════════════════════════════════════════════════════════════════════╝

━━━ Tailscale ━━━

Install Tailscale for secure remote access? (y/N): y

✓ Tailscale: enabled

Tailscale Auth Key:  
(Get from: https://login.tailscale.com/admin/settings/keys)

Enter auth key: tskey-auth-\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*

✓ Auth key: configured

Use this machine as exit node? (y/N): n

✓ Exit node: disabled

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 17: LLM Provider API Keys                                   ║  
╚════════════════════════════════════════════════════════════════════╝

━━━ External LLM API Keys ━━━

Configure external LLM providers for LiteLLM routing.  
(All optional \- press Enter to skip)

OpenAI API Key: sk-proj-\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*  
✓ OpenAI: configured

Anthropic API Key: sk-ant-\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*  
✓ Anthropic: configured

Google Gemini API Key: \[Enter to skip\]  
⊘ Gemini: skipped

Groq API Key: gsk\_\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*  
✓ Groq: configured

Mistral API Key: \[Enter to skip\]  
⊘ Mistral: skipped

OpenRouter API Key: \[Enter to skip\]  
⊘ OpenRouter: skipped

HuggingFace API Key: \[Enter to skip\]  
⊘ HuggingFace: skipped

Summary:  
  ✓ Configured: 3 providers (OpenAI, Anthropic, Groq)  
  ⊘ Skipped: 4 providers

LiteLLM will route:  
  1\. Ollama models (free, local)  
  2\. Groq models (cheap, fast)  
  3\. OpenAI models (expensive, powerful)  
  4\. Anthropic models (expensive, powerful)

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 18: Security & Secrets Configuration                        ║  
╚════════════════════════════════════════════════════════════════════╝

━━━ Auto-Generated Secrets ━━━

Generating secure credentials for all services...  
(You can override any of these with custom values)

▶ Core Infrastructure:  
  PostgreSQL master password:    \[auto\] ✓ Generated (32 chars)  
    Override with custom value? (y/N): n  
    
  Redis password:                \[auto\] ✓ Generated (32 chars)  
    Override? (y/N): n  
    
  Qdrant API key:                \[auto\] ✓ Generated (32 chars)  
    Override? (y/N): n

▶ Platform Security:  
  Admin password (UIs):          \[auto\] ✓ Generated (24 chars)  
    Override? (y/N): n  
    
  JWT secret:                    \[auto\] ✓ Generated (64 chars)  
    Override? (y/N): n  
    
  Encryption key:                \[auto\] ✓ Generated (32 bytes hex)  
    Override? (y/N): n

▶ Service-Specific:  
  n8n encryption key:            \[auto\] ✓ Generated  
  Dify secret key:               \[auto\] ✓ Generated  
  MinIO root password:           \[auto\] ✓ Generated  
  Grafana admin password:        \[auto\] ✓ Generated  
  LiteLLM master key:            \[auto\] ✓ Generated  
  Webhook secret:                \[auto\] ✓ Generated

✓ All secrets generated  
  Location: /mnt/data/secrets/  
  Permissions: 600 (owner only)

⚠ CRITICAL: These secrets will be saved to:  
  /mnt/data/metadata/secrets.json (encrypted)  
    
  BACKUP THIS FILE IMMEDIATELY AFTER SETUP\!

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 19: Monitoring Stack (Optional)                             ║  
╚════════════════════════════════════════════════════════════════════╝

━━━ Monitoring ━━━

Install monitoring stack (Prometheus \+ Grafana \+ Loki)? (Y/n): y

✓ Monitoring: enabled

Prometheus port \[default: 9090\]: 9090  
Grafana port \[default: 3001\]: 3001  
Loki port \[default: 3100\]: 3100

✓ Monitoring configured:  
  • Prometheus: http://prometheus:9090  
  • Grafana: http://grafana:3001  
  • Loki: http://loki:3100

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 20: Custom Port Configuration Summary                       ║  
╚════════════════════════════════════════════════════════════════════╝

Review port assignments:

Service                Internal Port    Public URL  
────────────────────────────────────────────────────────────────────  
Ollama                 11434           (internal only)  
LiteLLM                4000            https://api.ai.mycompany.com  
Open WebUI             3000            https://chat.ai.mycompany.com  
Dify API               5001            (internal only)  
Dify Web               3002            https://dify.ai.mycompany.com  
n8n                    5678            https://workflows.ai.mycompany.com  
Flowise                3003            https://flowise.ai.mycompany.com  
OpenClaw               8000            https://browse.ai.mycompany.com  
Signal API             8080            (webhook only)  
Prometheus             9090            (internal only)  
Grafana                3001            https://metrics.ai.mycompany.com

PostgreSQL             5432            (internal only)  
Redis                  6379            (internal only)  
Qdrant                 6333            (internal only)  
MinIO API              9000            (internal only)  
MinIO Console          9001            https://storage.ai.mycompany.com

Modify any ports? (y/N): n

✓ Port configuration confirmed

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 21: Generating Metadata Files                               ║  
╚════════════════════════════════════════════════════════════════════╝

ℹ Generating deployment metadata...

▶ Creating metadata files:

  ✓ configuration.json  
    \- System hardware info  
    \- Network configuration  
    \- Domain & SSL settings  
    \- GPU configuration  
    
  ✓ selected\_services.json  
    \- Enabled services list  
    \- Service dependencies  
    \- Port mappings  
    
  ✓ deployment\_plan.json  
    \- Deployment order  
    \- Service dependencies graph  
    \- Health check configuration  
    
  ✓ secrets.json (encrypted)  
    \- Auto-generated secrets  
    \- API keys  
    \- Service credentials  
    
  ✓ litellm\_config.json  
    \- Model routing configuration  
    \- Provider priorities  
    \- Cost/latency settings

All metadata files created in: /mnt/data/metadata/

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 22: Generating Modular Compose Files                        ║  
╚════════════════════════════════════════════════════════════════════╝

ℹ Generating individual Docker Compose files...

Creating compose files for 15 services:

  ✓ postgres.yml        (PostgreSQL 16\)  
  ✓ redis.yml           (Redis 7\)  
  ✓ qdrant.yml          (Qdrant vector DB)  
  ✓ minio.yml           (Object storage)  
  ✓ caddy.yml           (Reverse proxy)  
  ✓ ollama.yml          (Local LLM \- GPU enabled)  
  ✓ litellm.yml         (AI gateway)  
  ✓ openwebui.yml       (Chat UI)  
  ✓ dify-api.yml        (Dify backend)  
  ✓ dify-worker.yml     (Dify worker)  
  ✓ dify-web.yml        (Dify frontend)  
  ✓ n8n.yml             (Workflows)  
  ✓ flowise.yml         (No-code AI)  
  ✓ openclaw.yml        (Web agent)  
  ✓ signal-api.yml      (Messaging)  
  ✓ prometheus.yml      (Metrics)  
  ✓ grafana.yml         (Dashboards)  
  ✓ loki.yml            (Logs)

All compose files created in: /mnt/data/compose/

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 23: Generating Modular Environment Files                    ║  
╚════════════════════════════════════════════════════════════════════╝

ℹ Generating individual .env files...

Creating environment files for 15 services:

  ✓ postgres.env        (DB credentials)  
  ✓ redis.env           (Cache config)  
  ✓ qdrant.env          (Vector DB config)  
  ✓ minio.env           (Storage credentials)  
  ✓ caddy.env           (Proxy \+ SSL config)  
  ✓ ollama.env          (GPU config \+ models)  
  ✓ litellm.env         (API keys \+ routing)  
  ✓ openwebui.env       (UI config)  
  ✓ dify.env            (Dify stack config)  
  ✓ n8n.env             (Workflow config)  
  ✓ flowise.env         (Flowise config)  
  ✓ openclaw.env        (Search API keys)  
  ✓ signal.env          (Phone \+ auth config)  
  ✓ gdrive.env          (Drive sync config)  
  ✓ monitoring.env      (Prometheus \+ Grafana)

All env files created in: /mnt/data/env/  
Permissions: 600 (owner only \- contains secrets)

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 24: Generating Service Configuration Files                  ║  
╚════════════════════════════════════════════════════════════════════╝

ℹ Generating service-specific configuration files...

▶ LiteLLM Router Configuration:  
  ✓ config/litellm/config.yaml  
    
  Models configured:  
    Local (Ollama):  
      • llama3.1:8b      → ollama/llama3.1:8b  
      • codestral:22b    → ollama/codestral:22b  
      • phi3:mini        → ollama/phi3:mini  
      
    Cloud (API):  
      • gpt-4o-mini      → openai/gpt-4o-mini      (cost: $0.15/1M)  
      • gpt-4o           → openai/gpt-4o           (cost: $2.50/1M)  
      • claude-3-5-sonnet → anthropic/claude-3-5-sonnet (cost: $3.00/1M)  
      • llama-3.1-70b    → groq/llama-3.1-70b-versatile (cost: $0.59/1M)  
      
  Routing: cost-based (Ollama → Groq → OpenAI → Anthropic)

▶ Caddy Reverse Proxy:  
  ✓ config/caddy/Caddyfile  
    
  Routes configured:  
    • chat.ai.mycompany.com      → openwebui:3000  
    • api.ai.mycompany.com       → litellm:4000  
    • dify.ai.mycompany.com      → dify-web:3002  
    • workflows.ai.mycompany.com → n8n:5678  
    • flowise.ai.mycompany.com   → flowise:3003  
    • browse.ai.mycompany.com    → openclaw:8000  
    • metrics.ai.mycompany.com   → grafana:3001  
    • storage.ai.mycompany.com   → minio:9001  
    
  SSL: Let's Encrypt (Cloudflare DNS challenge)

▶ PostgreSQL Initialization:  
  ✓ config/postgres/init.sql  
    
  Databases to be created:  
    • litellm\_db   (for LiteLLM request logging)  
    • n8n\_db       (for n8n workflows)  
    • dify\_db      (for Dify apps)  
    • flowise\_db   (for Flowise chatflows)  
    
  Extensions:  
    • uuid-ossp (UUID generation)  
    • pgcrypto (encryption)  
    • pg\_trgm (fuzzy search)

▶ Prometheus Monitoring:  
  ✓ config/prometheus/prometheus.yml  
    
  Scrape targets:  
    • postgres:5432/metrics  
    • redis:6379/metrics  
    • ollama:11434/metrics  
    • litellm:4000/metrics  
    • caddy:2019/metrics

▶ Grafana Dashboards:  
  ✓ config/grafana/dashboards/ai-platform.json  
  ✓ config/grafana/dashboards/llm-performance.json  
  ✓ config/grafana/dashboards/infrastructure.json

All config files created in: /mnt/data/config/

╔════════════════════════════════════════════════════════════════════╗  
║ PHASE 25: Final Validation                                        ║  
╚════════════════════════════════════════════════════════════════════╝

▶ Validating all generated files...

Metadata files:  
  ✓ configuration.json (valid JSON, 847 lines)  
  ✓ selected\_services.json (valid JSON, 134 lines)  
  ✓ deployment\_plan.json (valid JSON, 89 lines)  
  ✓ secrets.json (valid JSON, encrypted, 256 lines)  
  ✓ litellm\_config.json (valid JSON, 178 lines)

Compose files (18 files):  
  ✓ All YAML syntax valid  
  ✓ All images specified  
  ✓ All networks referenced exist  
  ✓ All volumes defined  
  ✓ All env\_file paths correct

Environment files (15 files):  
  ✓ All required variables present  
  ✓ No syntax errors  
  ✓ Permissions: 600

Configuration files:  
  ✓ LiteLLM config valid  
  ✓ Caddyfile syntax valid  
  ✓ PostgreSQL init.sql valid  
  ✓ Prometheus config valid  
  ✓ Grafana dashboards valid JSON

Dependencies:  
  ✓ Docker installed  
  ✓ Docker Compose available  
  ✓ Networks created  
  ✓ Directories exist with correct permissions

✓ All validation checks passed\!

╔════════════════════════════════════════════════════════════════════╗  
║                                                                    ║  
║          ✓ CONFIGURATION COLLECTION COMPLETED\!                     ║  
║                                                                    ║  
╚════════════════════════════════════════════════════════════════════╝

📋 Setup Summary  
────────────────────────────────────────────────────────────────────

System Configuration:  
  • Hardware: GPU-Accelerated (NVIDIA RTX 3090\)  
  • OS: Ubuntu 22.04 x86\_64  
  • Resources: 8 cores, 32GB RAM, 250GB disk  
  • Docker: 25.0.3 with GPU support

Network Configuration:  
  • Domain: ai.mycompany.com  
  • Proxy: Caddy (automatic HTTPS)  
  • SSL: Let's Encrypt (Cloudflare DNS)  
  • Networks: 3 isolated networks

Services Selected (15 total):  
  Core Infrastructure:  
    ✓ PostgreSQL 16 (multi-database)  
    ✓ Redis 7 (cache \+ queue)  
    ✓ Qdrant (vector DB)  
    ✓ MinIO (object storage)  
    
  AI Services:  
    ✓ Ollama (3 models, GPU-accelerated)  
    ✓ LiteLLM (cost-based routing, 3 providers)  
    ✓ Open WebUI (chat interface)  
    ✓ Dify (AI app platform)  
    
  Workflows:  
    ✓ n8n (automation)  
    ✓ Flowise (no-code AI)  
    
  Integrations:  
    ✓ OpenClaw (web agent \+ Brave Search)  
    ✓ Signal API (messaging)  
    ✓ Google Drive (auto-sync)  
    ✓ Tailscale (VPN)  
    
  Monitoring:  
    ✓ Prometheus (metrics)  
    ✓ Grafana (dashboards)  
    ✓ Loki (logs)

External Integrations:  
  • API Keys: 3 providers (OpenAI, Anthropic, Groq)  
  • Search: Brave Search API  
  • Storage: Google Drive (service account)  
  • Network: Tailscale VPN

Generated Files:  
  • Metadata: 5 files in /mnt/data/metadata/  
  • Compose: 18 files in /mnt/data/compose/  
  • Environment: 15 files in /mnt/data/env/  
  • Configs: 12 files in /mnt/data/config/  
  • Total: 50 configuration files

Security:  
  ✓ 12 auto-generated secrets (32-64 chars each)  
  ✓ All credentials unique per service  
  ✓ Secrets encrypted at rest  
  ✓ File permissions: 600 for sensitive files

────────────────────────────────────────────────────────────────────

🚀 Next Steps:

  1\. BACKUP YOUR SECRETS (CRITICAL):  
     cp /mnt/data/metadata/secrets.json \~/ai-platform-secrets-backup.json  
     chmod 400 \~/ai-platform-secrets-backup.json

  2\. VERIFY DNS CONFIGURATION:  
     Ensure all subdomains point to this server:  
     • chat.ai.mycompany.com  
     • api.ai.mycompany.com  
     • dify.ai.mycompany.com  
     • workflows.ai.mycompany.com  
     • flowise.ai.mycompany.com  
     • browse.ai.mycompany.com  
     • metrics.ai.mycompany.com  
     • storage.ai.mycompany.com

  3\. DEPLOY THE PLATFORM:  
     cd \~/AIPlatformAutomation/scripts  
     sudo ./2-deploy-services.sh  
       
     Deployment will:  
     • Pull all Docker images (\~15GB)  
     • Download Ollama models (\~19GB)  
     • Initialize databases  
     • Start all services  
     • Run health checks  
     • Show Signal QR code for registration  
       
     Estimated time: 15-25 minutes

  4\. AFTER DEPLOYMENT:  
     • Change admin passwords (stored in secrets.json)  
     • Test all service URLs  
     • Configure Google Drive sync  
     • Set up monitoring alerts

────────────────────────────────────────────────────────────────────

📄 Important Files:  
  • Setup log: /mnt/data/logs/setup-20260211-143022.log  
  • Secrets (BACKUP\!): /mnt/data/metadata/secrets.json  
  • Configuration: /mnt/data/metadata/configuration.json

⚠️  CRITICAL REMINDERS:  
  1\. BACKUP secrets.json IMMEDIATELY \- contains all passwords  
  2\. Configure DNS before running Script 2  
  3\. This script did NOT deploy anything \- only prepared configuration  
  4\. All deployment happens in Script 2

✓ Setup completed successfully\!  
  You may now run: sudo ./2-deploy-services.sh

\`Script 2 Expected output :\` 

\#\# \*\*SCRIPT 2: DEPLOY SERVICES\*\*

\#\#\# \*\*Intent\*\*

Pull Docker images, deploy containers with proper network configuration, perform health checks, and deliver a working system.

\#\#\# \*\*Key Responsibilities\*\*

\#\#\#\# \*\*1\\. Environment Validation\*\*

\* Source \`.env\` file    
\* Validate NO ANSI codes present    
\* Validate NO shell injection patterns    
\* Confirm all required variables set

\#\#\#\# \*\*2\\. Pre-Deployment Cleanup\*\*

\* Remove any existing containers with same names    
\* Preserve volumes (data persistence)    
\* Clean stale network connections

\#\#\#\# \*\*3\\. Docker Network Creation\*\*

docker network create ai-network 2\\\>/dev/null || true

\#\#\#\# \*\*4\\. Service Deployment (Dependency Order)\*\*

\*\*Phase 1: Core Infrastructure\*\*

\\\# 1\\. Ollama (LLM backend)    
docker run \\-d \\--name ollama \\\\    
  \\--network ai-network \\\\    
  \\-p ${OLLAMA\\\_PORT}:11434 \\\\    
  \\-v ollama-data:/root/.ollama \\\\    
  \\--gpus all \\\\  \\\# If GPU detected    
  \\--restart unless-stopped \\\\    
  ollama/ollama:latest

\\\# 2\\. Qdrant (Vector DB)    
docker run \\-d \\--name qdrant \\\\    
  \\--network ai-network \\\\    
  \\-p ${QDRANT\\\_PORT}:6333 \\\\    
  \\-v qdrant-data:/qdrant/storage \\\\    
  \\-e QDRANT\\\_\\\_SERVICE\\\_\\\_API\\\_KEY=${QDRANT\\\_API\\\_KEY} \\\\    
  \\--restart unless-stopped \\\\    
  qdrant/qdrant:latest

\*\*Phase 2: Search Infrastructure\*\*

\\\# 3\\. SearXNG (if selected)    
docker run \\-d \\--name searxng \\\\    
  \\--network ai-network \\\\    
  \\-p ${SEARXNG\\\_PORT}:8080 \\\\    
  \\-v searxng-data:/etc/searxng \\\\    
  \\-e SEARXNG\\\_SECRET=${SEARXNG\\\_SECRET\\\_KEY} \\\\    
  \\--restart unless-stopped \\\\    
  searxng/searxng:latest

\*\*Phase 3: LLM Gateway\*\*

\\\# 4\\. LiteLLM (Unified API)    
docker run \\-d \\--name litellm \\\\    
  \\--network ai-network \\\\    
  \\-p ${LITELLM\\\_PORT}:4000 \\\\    
  \\-v litellm-data:/app/config \\\\    
  \\-e OLLAMA\\\_BASE\\\_URL=http://ollama:11434 \\\\    
  \\-e LITELLM\\\_MASTER\\\_KEY=${LITELLM\\\_MASTER\\\_KEY} \\\\    
  \\-e OPENAI\\\_API\\\_KEY=${OPENAI\\\_API\\\_KEY:-} \\\\    
  \\-e ANTHROPIC\\\_API\\\_KEY=${ANTHROPIC\\\_API\\\_KEY:-} \\\\    
  \\--restart unless-stopped \\\\    
  ghcr.io/berriai/litellm:main-latest

\*\*Phase 4: AI Platforms\*\*

\\\# 5\\. Ollama WebUI    
docker run \\-d \\--name ollama-webui \\\\    
  \\--network ai-network \\\\    
  \\-p ${OLLAMA\\\_WEBUI\\\_PORT}:8080 \\\\    
  \\-v ollama-webui-data:/app/backend/data \\\\    
  \\-e OLLAMA\\\_BASE\\\_URL=http://ollama:11434 \\\\    
  \\--restart unless-stopped \\\\    
  ghcr.io/open-webui/open-webui:main

\\\# 6\\. AnythingLLM    
docker run \\-d \\--name anythingllm \\\\    
  \\--network ai-network \\\\    
  \\-p ${ANYTHINGLLM\\\_PORT}:3001 \\\\    
  \\-v anythingllm-data:/app/server/storage \\\\    
  \\-v /mnt/data/gdrive:/app/collector/hotdir \\\\    
  \\-e LLM\\\_PROVIDER=ollama \\\\    
  \\-e OLLAMA\\\_BASE\\\_PATH=http://ollama:11434 \\\\    
  \\-e VECTOR\\\_DB=qdrant \\\\    
  \\-e QDRANT\\\_ENDPOINT=http://qdrant:6333 \\\\    
  \\-e QDRANT\\\_API\\\_KEY=${QDRANT\\\_API\\\_KEY} \\\\    
  \\--restart unless-stopped \\\\    
  mintplexlabs/anythingllm:latest

\\\# 7\\. Dify    
docker run \\-d \\--name dify \\\\    
  \\--network ai-network \\\\    
  \\-p ${DIFY\\\_PORT}:3000 \\\\    
  \\-v dify-data:/app/storage \\\\    
  \\-e LLM\\\_PROVIDER=openai \\\\    
  \\-e OPENAI\\\_API\\\_BASE=http://litellm:4000 \\\\    
  \\-e OPENAI\\\_API\\\_KEY=${LITELLM\\\_MASTER\\\_KEY} \\\\    
  \\--restart unless-stopped \\\\    
  langgenius/dify-api:latest

\*\*Phase 5: Automation\*\*

\\\# 8\\. OpenClaw    
docker run \\-d \\--name open-claw \\\\    
  \\--network ai-network \\\\    
  \\-p ${OPENCLAW\\\_PORT}:3000 \\\\    
  \\-v openclaw-data:/app/data \\\\    
  \\-e ANYTHINGLLM\\\_API\\\_BASE=http://anythingllm:3001 \\\\    
  \\--restart unless-stopped \\\\    
  openclawai/openclaw:latest

\\\# 9\\. n8n (if selected)    
docker run \\-d \\--name n8n \\\\    
  \\--network ai-network \\\\    
  \\-p ${N8N\\\_PORT}:5678 \\\\    
  \\-v n8n-data:/home/node/.n8n \\\\    
  \\--restart unless-stopped \\\\    
  n8nio/n8n:latest

\*\*Phase 6: Reverse Proxy\*\*

\\\# 10a. Nginx (if selected)    
docker run \\-d \\--name nginx \\\\    
  \\--network ai-network \\\\    
  \\-p ${NGINX\\\_HTTP\\\_PORT}:80 \\\\    
  \\-p ${NGINX\\\_HTTPS\\\_PORT}:443 \\\\    
  \\-v /mnt/data/ai-services/config/nginx/conf.d:/etc/nginx/conf.d:ro \\\\    
  \\-v /mnt/data/ai-services/config/nginx/ssl:/etc/nginx/ssl:ro \\\\    
  \\-v nginx-cache:/var/cache/nginx \\\\    
  \\--restart unless-stopped \\\\    
  nginx:alpine

\\\# 10b. Caddy (if selected \\- MUTUALLY EXCLUSIVE)    
docker run \\-d \\--name caddy \\\\    
  \\--network ai-network \\\\    
  \\-p ${CADDY\\\_HTTP\\\_PORT}:80 \\\\    
  \\-p ${CADDY\\\_HTTPS\\\_PORT}:443 \\\\    
  \\-v /mnt/data/ai-services/config/caddy/Caddyfile:/etc/caddy/Caddyfile:ro \\\\    
  \\-v caddy-data:/data \\\\    
  \\-v caddy-config:/config \\\\    
  \\--restart unless-stopped \\\\    
  caddy:latest

\*\*Phase 7: VPN\*\*

\\\# 11\\. Tailscale    
docker run \\-d \\--name tailscale \\\\    
  \\--network host \\\\    
  \\--cap-add NET\\\_ADMIN \\\\    
  \\--cap-add SYS\\\_MODULE \\\\    
  \\-v /dev/net/tun:/dev/net/tun \\\\    
  \\-v tailscale-data:/var/lib/tailscale \\\\    
  \\-e TS\\\_AUTHKEY=${TAILSCALE\\\_AUTH\\\_KEY} \\\\    
  \\-e TS\\\_STATE\\\_DIR=/var/lib/tailscale \\\\    
  \\--restart unless-stopped \\\\    
  tailscale/tailscale:latest

\*\*Phase 8: Data Sync\*\*

\\\# 12\\. Rsync (Cron-based Google Drive sync)    
\\\# Create systemd timer or cron job:    
\\\# \\\*/6 \\\* \\\* \\\* \\\* rsync \\-avz /path/to/gdrive/ /mnt/data/gdrive/

\#\#\#\# \*\*5\\. Health Checks (Per Service)\*\*

check\\\_service\\\_health() {    
    local service=$1    
    local port=$2    
    local max\\\_attempts=30    
        
    for i in $(seq 1 $max\\\_attempts); do    
        if curl \\-sf "http://localhost:${port}/health" \\\>/dev/null 2\\\>&1; then    
            log\\\_success "$service healthy on port $port"    
            return 0    
        fi    
        sleep 2    
    done    
        
    log\\\_error "$service failed health check"    
    docker logs "$service" | tail \\-20    
    return 1    
}

\\\# Execute health checks    
check\\\_service\\\_health "ollama" "$OLLAMA\\\_PORT"    
check\\\_service\\\_health "litellm" "$LITELLM\\\_PORT"    
check\\\_service\\\_health "qdrant" "$QDRANT\\\_PORT"    
\\\# ... etc

\#\#\#\# \*\*6\\. Credentials File Update\*\*

cat \\\>\\\> /mnt/data/ai-services/credentials.txt \\\<\\\<EOF    
╔════════════════════════════════════════╗    
║     AI PLATFORM ACCESS CREDENTIALS     ║    
╚════════════════════════════════════════╝

Generated: $(date)

OLLAMA:    
  URL: http://localhost:${OLLAMA\\\_PORT}    
  API: http://localhost:${OLLAMA\\\_PORT}/api

OLLAMA WEBUI:    
  URL: http://localhost:${OLLAMA\\\_WEBUI\\\_PORT}    
  Default Admin: Create on first access

LITELLM:    
  URL: http://localhost:${LITELLM\\\_PORT}    
  API Key: ${LITELLM\\\_MASTER\\\_KEY}    
  Docs: http://localhost:${LITELLM\\\_PORT}/docs

QDRANT:    
  URL: http://localhost:${QDRANT\\\_PORT}    
  API Key: ${QDRANT\\\_API\\\_KEY}    
  Dashboard: http://localhost:${QDRANT\\\_PORT}/dashboard

ANYTHINGLLM:    
  URL: http://localhost:${ANYTHINGLLM\\\_PORT}    
  OR: https://${DOMAIN}/anythingllm

DIFY:    
  URL: http://localhost:${DIFY\\\_PORT}    
  OR: https://${DOMAIN}/dify

OPENCLAW (via Tailscale):    
  URL: https://$(tailscale status \\--json | jq \\-r '.Self.DNSName'):18789

TAILSCALE:    
  Admin: https://login.tailscale.com/admin/machines    
  This Device IP: $(tailscale ip \\-4)

REVERSE PROXY:    
  Public URL: https://${DOMAIN}    
  Backend: ${PROXY\\\_TYPE} (Nginx/Caddy)

EOF

\#\#\#\# \*\*7\\. Deployment Summary\*\*

echo ""    
echo "╔════════════════════════════════════════╗"    
echo "║   DEPLOYMENT COMPLETE v68.0.0          ║"    
echo "╚════════════════════════════════════════╝"    
echo ""    
echo "✓ All containers running"    
echo "✓ Health checks passed"    
echo "✓ Credentials saved to /mnt/data/ai-services/credentials.txt"    
echo ""    
echo "Next steps:"    
echo "  1\\. Run: 3-configure-services.sh"    
echo "  2\\. Access services at: https://${DOMAIN}"    
echo ""

\#\#\# \*\*Success Definition\*\*

\* ✅ All selected containers running (\`docker ps\` shows all)    
\* ✅ All services pass health checks    
\* ✅ Reverse proxy routing works (test \`curl https://${DOMAIN}/anythingllm\`)    
\* ✅ Inter-service communication works (Dify can reach LiteLLM)    
\* ✅ Credentials file populated    
\* ✅ Tailscale connected (if enabled)    
\* ✅ No port conflicts    
\* ✅ All containers have \`restart: unless-stopped\`

\#\# \*\*SCRIPT 3: CONFIGURE SERVICES\*\*

\#\#\# \*\*Intent\*\*

Fine-tune service-specific settings, load initial models, configure routing rules, enable systemd persistence, and link external integrations (Signal, Google Drive sync).

\#\#\# \*\*Key Responsibilities\*\*

\#\#\#\# \*\*1\\. Service Status Check\*\*

display\\\_service\\\_status() {    
    echo "╔════════════════════════════════════════╗"    
    echo "║        SERVICE STATUS OVERVIEW         ║"    
    echo "╚════════════════════════════════════════╝"    
        
    for service in ollama litellm qdrant anythingllm dify openclaw; do    
        if docker ps \\--format '{{.Names}}' | grep \\-q "^${service}$"; then    
            status="✓ Running"    
            color="${GREEN}"    
        else    
            status="✗ Stopped"    
            color="${RED}"    
        fi    
        printf "%-20s %s\\\\n" "$service" "${color}${status}${NC}"    
    done    
}

\#\#\#\# \*\*2\\. Ollama Model Management\*\*

configure\\\_ollama\\\_models() {    
    echo ""    
    log "Ollama Model Configuration"    
    echo "  Current models:"    
    docker exec ollama ollama list    
        
    echo ""    
    echo "Available models:"    
    echo "  1\\) llama3.2:1b (Fast, minimal)"    
    echo "  2\\) llama3.2:3b (Balanced \\- RECOMMENDED)"    
    echo "  3\\) mistral:7b (High quality)"    
    echo "  4\\) deepseek-coder:6.7b (Code-focused)"    
    echo "  5\\) Custom model name"    
        
    read \\-p "Select model to pull \\\[2\\\]: " model\\\_choice    
        
    case "${model\\\_choice:-2}" in    
        1\\) MODEL="llama3.2:1b" ;;    
        2\\) MODEL="llama3.2:3b" ;;    
        3\\) MODEL="mistral:7b" ;;    
        4\\) MODEL="deepseek-coder:6.7b" ;;    
        5\\) read \\-p "Enter model name: " MODEL ;;    
    esac    
        
    log "Pulling model: $MODEL (this may take several minutes)"    
    docker exec ollama ollama pull "$MODEL"    
        
    \\\# Set as default in LiteLLM routing    
    update\\\_litellm\\\_config "default\\\_model" "$MODEL"    
}

\#\#\#\# \*\*3\\. LiteLLM Routing Configuration\*\*

configure\\\_litellm\\\_routing() {    
    echo ""    
    log "LiteLLM Routing Rules Configuration"    
        
    cat \\\> /mnt/data/ai-services/config/litellm/config.yaml \\\<\\\<EOF    
model\\\_list:    
  \\\# Local Ollama models    
  \\- model\\\_name: local-llm    
    litellm\\\_params:    
      model: ollama/${OLLAMA\\\_MODEL:-llama3.2:3b}    
      api\\\_base: http://ollama:11434    
          
  \\\# Cloud fallback models    
  \\- model\\\_name: gpt-4-turbo    
    litellm\\\_params:    
      model: gpt-4-turbo-preview    
      api\\\_key: ${OPENAI\\\_API\\\_KEY:-}    
          
  \\- model\\\_name: claude-3-opus    
    litellm\\\_params:    
      model: claude-3-opus-20240229    
      api\\\_key: ${ANTHROPIC\\\_API\\\_KEY:-}

router\\\_settings:    
  routing\\\_strategy: usage-based-routing    
      
  \\\# Route simple queries to local, complex to cloud    
  model\\\_routing:    
    \\- pattern: ".\\\*simple.\\\*|.\\\*quick.\\\*|.\\\*basic.\\\*"    
      target: local-llm    
          
    \\- pattern: ".\\\*complex.\\\*|.\\\*analysis.\\\*|.\\\*research.\\\*"    
      target: gpt-4-turbo    
      fallback: local-llm    
          
    \\- pattern: ".\\\*code.\\\*|.\\\*programming.\\\*"    
      target: ${CODE\\\_MODEL:-local-llm}    
          
  \\\# Cost limits    
  max\\\_budget: 100  \\\# USD per month    
  budget\\\_duration: 30d    
EOF

    docker restart litellm    
    log\\\_success "LiteLLM routing configured"    
}

\#\#\#\# \*\*4\\. LiteLLM Web UI (Expose Configuration Interface)\*\*

\\\# Deploy optional LiteLLM admin UI    
deploy\\\_litellm\\\_ui() {    
    read \\-p "Deploy LiteLLM Admin UI? \\\[Y/n\\\]: " \\-n 1 \\-r    
    echo    
        
    if \\\[\\\[ \\\! $REPLY \\=\\\~ ^\\\[Nn\\\]$ \\\]\\\]; then    
        LITELLM\\\_UI\\\_PORT=$(find\\\_available\\\_port "litellm-ui" 4001\\)    
            
        docker run \\-d \\--name litellm-ui \\\\    
          \\--network ai-network \\\\    
          \\-p ${LITELLM\\\_UI\\\_PORT}:3000 \\\\    
          \\-e LITELLM\\\_API\\\_BASE=http://litellm:4000 \\\\    
          \\-e LITELLM\\\_API\\\_KEY=${LITELLM\\\_MASTER\\\_KEY} \\\\    
          \\--restart unless-stopped \\\\    
          ghcr.io/berriai/litellm-ui:latest    
              
        log\\\_success "LiteLLM UI: http://localhost:${LITELLM\\\_UI\\\_PORT}"    
    fi    
}

\#\#\#\# \*\*5\\. AnythingLLM Configuration\*\*

configure\\\_anythingllm() {    
    log "Configuring AnythingLLM..."    
        
    \\\# Connect to Qdrant vector DB    
    docker exec anythingllm curl \\-X POST http://localhost:3001/api/system/vector-db \\\\    
      \\-H "Content-Type: application/json" \\\\    
      \\-d '{    
        "provider": "qdrant",    
        "config": {    
          "url": "http://qdrant:6333",    
          "apiKey": "'"${QDRANT\\\_API\\\_KEY}"'"    
        }    
      }'    
        
    \\\# Set Ollama as LLM provider    
    docker exec anythingllm curl \\-X POST http://localhost:3001/api/system/llm \\\\    
      \\-H "Content-Type: application/json" \\\\    
      \\-d '{    
        "provider": "ollama",    
        "config": {    
          "baseUrl": "http://ollama:11434",    
          "model": "'"${OLLAMA\\\_MODEL}"'"    
        }    
      }'    
        
    \\\# Configure document ingestion from /mnt/data/gdrive    
    docker exec anythingllm curl \\-X POST http://localhost:3001/api/system/data-connectors \\\\    
      \\-H "Content-Type: application/json" \\\\    
      \\-d '{    
        "type": "local\\\_files",    
        "path": "/app/collector/hotdir"    
      }'    
        
    log\\\_success "AnythingLLM configured with Qdrant \\+ Ollama"    
}

\#\#\#\# \*\*6\\. OpenClaw Configuration\*\*

configure\\\_openclaw() {    
    log "Configuring OpenClaw..."    
        
    \\\# Link to AnythingLLM for knowledge retrieval    
    docker exec open-claw sh \\-c 'cat \\\> /app/config.json' \\\<\\\<EOF    
{    
  "llm": {    
    "provider": "anythingllm",    
    "endpoint": "http://anythingllm:3001/api/chat",    
    "defaultModel": "${OLLAMA\\\_MODEL}"    
  },    
  "vectorDB": {    
    "provider": "qdrant",    
    "endpoint": "http://qdrant:6333",    
    "apiKey": "${QDRANT\\\_API\\\_KEY}",    
    "collection": "openclaw-knowledge"    
  },    
  "automation": {    
    "screenshotPath": "/app/data/screenshots",    
    "maxRetries": 3    
  }    
}    
EOF    
        
    docker restart open-claw    
    log\\\_success "OpenClaw linked to AnythingLLM \\+ Qdrant"    
}

\#\#\#\# \*\*7\\. OpenClaw via Tailscale HTTPS\*\*

configure\\\_openclaw\\\_tailscale() {    
    log "Configuring OpenClaw access via Tailscale..."    
        
    \\\# Get Tailscale IP    
    TAILSCALE\\\_IP=$(docker exec tailscale tailscale ip \\-4)    
        
    \\\# Update Caddy/Nginx to serve OpenClaw on Tailscale interface    
    if \\\[\\\[ "$PROXY\\\_TYPE" \\== "caddy" \\\]\\\]; then    
        cat \\\>\\\> /mnt/data/ai-services/config/caddy/Caddyfile \\\<\\\<EOF

\\\# OpenClaw via Tailscale HTTPS    
https://${TAILSCALE\\\_IP}:8443 {    
    reverse\\\_proxy open-claw:3000    
    tls internal    
}    
EOF    
        docker exec caddy caddy reload \\--config /etc/caddy/Caddyfile    
    fi    
        
    log\\\_success "OpenClaw accessible at: https://${TAILSCALE\\\_IP}:8443"    
    log "  OR: https://$(docker exec tailscale tailscale status \\--json | jq \\-r '.Self.DNSName'):18789"    
}

\#\#\#\# \*\*8\\. Dify Configuration\*\*

configure\\\_dify() {    
    log "Configuring Dify..."    
        
    \\\# Point Dify to LiteLLM for intelligent routing    
    docker exec dify sh \\-c 'cat \\\> /app/.env' \\\<\\\<EOF    
LLM\\\_PROVIDER=openai    
OPENAI\\\_API\\\_BASE=http://litellm:4000    
OPENAI\\\_API\\\_KEY=${LITELLM\\\_MASTER\\\_KEY}    
VECTOR\\\_STORE=qdrant    
QDRANT\\\_URL=http://qdrant:6333    
QDRANT\\\_API\\\_KEY=${QDRANT\\\_API\\\_KEY}    
EOF    
        
    docker restart dify    
    log\\\_success "Dify configured with LiteLLM \\+ Qdrant"    
}

\#\#\#\# \*\*9\\. Signal Bot Configuration (Optional)\*\*

configure\\\_signal\\\_bot() {    
    read \\-p "Link Signal messaging bot? \\\[y/N\\\]: " \\-n 1 \\-r    
    echo    
        
    if \\\[\\\[ $REPLY \\=\\\~ ^\\\[Yy\\\]$ \\\]\\\]; then    
        log "Signal bot requires:"    
        log "  1\\. Signal CLI installed: https://github.com/AsamK/signal-cli"    
        log "  2\\. Phone number registered"    
            
        read \\-p "Enter Signal phone number (with country code): " SIGNAL\\\_PHONE    
            
        \\\# Link device    
        docker run \\--rm \\-it \\\\    
          \\-v signal-data:/root/.local/share/signal-cli \\\\    
          bbernhard/signal-cli:latest \\\\    
          \\-u "$SIGNAL\\\_PHONE" link    
            
        log "Scan QR code with Signal app (Settings → Linked Devices)"    
            
        \\\# Deploy Signal bridge    
        docker run \\-d \\--name signal-bridge \\\\    
          \\--network ai-network \\\\    
          \\-v signal-data:/root/.local/share/signal-cli \\\\    
          \\-e SIGNAL\\\_PHONE="$SIGNAL\\\_PHONE" \\\\    
          \\-e OPENCLAW\\\_ENDPOINT="http://open-claw:3000" \\\\    
          \\--restart unless-stopped \\\\    
          custom/signal-openclaw-bridge:latest    
            
        log\\\_success "Signal bot linked \\- messages route to OpenClaw"    
    fi    
}

\#\#\#\# \*\*10\\. Google Drive Rsync Configuration\*\*

configure\\\_gdrive\\\_sync() {    
    log "Configuring Google Drive sync..."    
        
    read \\-p "Enable Google Drive sync to /mnt/data/gdrive? \\\[Y/n\\\]: " \\-n 1 \\-r    
    echo    
        
    if \\\[\\\[ \\\! $REPLY \\=\\\~ ^\\\[Nn\\\]$ \\\]\\\]; then    
        read \\-p "Enter Google Drive source path (rclone remote:path): " GDRIVE\\\_SOURCE    
        read \\-p "Sync interval (hours) \\\[6\\\]: " SYNC\\\_INTERVAL    
        SYNC\\\_INTERVAL=${SYNC\\\_INTERVAL:-6}    
            
        \\\# Create systemd timer    
        cat \\\> /etc/systemd/system/gdrive-sync.service \\\<\\\<EOF    
\\\[Unit\\\]    
Description=Google Drive Sync to /mnt/data/gdrive    
After=network.target

\\\[Service\\\]    
Type=oneshot    
ExecStart=/usr/bin/rclone sync ${GDRIVE\\\_SOURCE} /mnt/data/gdrive/ \\-v \\--log-file=/var/log/gdrive-sync.log    
User=root

\\\[Install\\\]    
WantedBy=multi-user.target    
EOF

        cat \\\> /etc/systemd/system/gdrive-sync.timer \\\<\\\<EOF    
\\\[Unit\\\]    
Description=Google Drive Sync Timer

\\\[Timer\\\]    
OnBootSec=5min    
OnUnitActiveSec=${SYNC\\\_INTERVAL}h    
Persistent=true

\\\[Install\\\]    
WantedBy=timers.target    
EOF

        systemctl daemon-reload    
        systemctl enable \\--now gdrive-sync.timer    
            
        log\\\_success "Google Drive sync enabled (every ${SYNC\\\_INTERVAL}h)"    
        log "  Source: ${GDRIVE\\\_SOURCE}"    
        log "  Target: /mnt/data/gdrive/"    
    fi    
}

\#\#\#\# \*\*11\\. Port Reconfiguration\*\*

reconfigure\\\_port() {    
    local service=$1    
    local current\\\_port=$2    
        
    read \\-p "Change port for $service (current: $current\\\_port)? \\\[y/N\\\]: " \\-n 1 \\-r    
    echo    
        
    if \\\[\\\[ $REPLY \\=\\\~ ^\\\[Yy\\\]$ \\\]\\\]; then    
        read \\-p "Enter new port: " new\\\_port    
            
        \\\# Validate and stop service    
        docker stop "$service"    
        docker rm "$service"    
            
        \\\# Update ENV    
        sed \\-i "s/^${service^^}\\\_PORT=.\\\*/${service^^}\\\_PORT=$new\\\_port/" "$ENV\\\_FILE"    
            
        \\\# Re-deploy with new port    
        source "$ENV\\\_FILE"    
        deploy\\\_${service}    
            
        log\\\_success "$service moved to port $new\\\_port"    
    fi    
}

\#\#\#\# \*\*12\\. System Integration (Systemd)\*\*

make\\\_persistent() {    
    log "Creating systemd service for container auto-start..."    
        
    \\\# Docker containers already have \\--restart unless-stopped    
    \\\# but ensure Docker starts on boot    
    systemctl enable docker    
        
    \\\# Optionally create a wrapper service    
    cat \\\> /etc/systemd/system/ai-platform.service \\\<\\\<'EOF'    
\\\[Unit\\\]    
Description=AI Platform Container Stack    
After=docker.service    
Requires=docker.service

\\\[Service\\\]    
Type=oneshot    
RemainAfterExit=yes    
ExecStart=/usr/bin/docker start ollama litellm qdrant anythingllm dify openclaw caddy tailscale    
ExecStop=/usr/bin/docker stop ollama litellm qdrant anythingllm dify openclaw caddy tailscale    
User=root

\\\[Install\\\]    
WantedBy=multi-user.target    
EOF

    systemctl daemon-reload    
    systemctl enable ai-platform.service    
        
    log\\\_success "AI Platform will auto-start on boot"    
}

\#\#\#\# \*\*13\\. Configuration Menu\*\*

show\\\_configuration\\\_menu() {    
    while true; do    
        echo ""    
        echo "╔════════════════════════════════════════╗"    
        echo "║    SERVICE CONFIGURATION MENU          ║"    
        echo "╚════════════════════════════════════════╝"    
        echo ""    
        echo "  1\\) View service status"    
        echo "  2\\) Configure Ollama models"    
        echo "  3\\) Configure LiteLLM routing"    
        echo "  4\\) Deploy LiteLLM Web UI"    
        echo "  5\\) Configure AnythingLLM"    
        echo "  6\\) Configure OpenClaw"    
        echo "  7\\) Configure OpenClaw via Tailscale"    
        echo "  8\\) Configure Dify"    
        echo "  9\\) Configure Signal bot"    
        echo " 10\\) Configure Google Drive sync"    
        echo " 11\\) Reconfigure service ports"    
        echo " 12\\) Make configuration permanent (systemd)"    
        echo " 13\\) Restart all services"    
        echo "  0\\) Exit"    
        echo ""    
        read \\-p "Select option: " choice    
            
        case $choice in    
            1\\) display\\\_service\\\_status ;;    
            2\\) configure\\\_ollama\\\_models ;;    
            3\\) configure\\\_litellm\\\_routing ;;    
            4\\) deploy\\\_litellm\\\_ui ;;    
            5\\) configure\\\_anythingllm ;;    
            6\\) configure\\\_openclaw ;;    
            7\\) configure\\\_openclaw\\\_tailscale ;;    
            8\\) configure\\\_dify ;;    
            9\\) configure\\\_signal\\\_bot ;;    
            10\\) configure\\\_gdrive\\\_sync ;;    
            11\\) reconfigure\\\_ports\\\_menu ;;    
            12\\) make\\\_persistent ;;    
            13\\) restart\\\_all\\\_services ;;    
            0\\) break ;;    
            \\\*) log\\\_error "Invalid option" ;;    
        esac    
    done    
}

\#\#\# \*\*Success Definition\*\*

\* ✅ Ollama model pulled and active    
\* ✅ LiteLLM routing rules configured (local-first, cloud fallback)    
\* ✅ AnythingLLM connected to Qdrant \\+ Ollama    
\* ✅ OpenClaw linked to AnythingLLM vector DB    
\* ✅ OpenClaw accessible via Tailscale HTTPS    
\* ✅ Dify using LiteLLM for intelligent routing    
\* ✅ Google Drive sync active (if enabled)    
\* ✅ Signal bot linked (if enabled)    
\* ✅ All services set to auto-start on boot    
\* ✅ User can modify configuration via menu (no manual file editing)

\#\# \*\*SCRIPT 4: ADD SERVICE (FUTURE EXTENSIBILITY)\*\*

\#\#\# \*\*Intent\*\*

Provide a framework to add new Docker-based AI services without modifying core scripts.

\#\#\# \*\*Template Structure\*\*

add\\\_new\\\_service() {    
    local service\\\_name=$1    
        
    echo "Adding new service: $service\\\_name"    
        
    \\\# 1\\. Collect configuration    
    read \\-p "Docker image: " image    
    read \\-p "Port: " port    
        
    \\\# 2\\. Validate port availability    
    if \\\! is\\\_port\\\_available "$port"; then    
        log\\\_error "Port $port already in use"    
        return 1    
    fi    
        
    \\\# 3\\. Deploy container    
    docker run \\-d \\\\    
      \\--name "$service\\\_name" \\\\    
      \\--network ai-network \\\\    
      \\-p "${port}:${port}" \\\\    
      \\-v "${service\\\_name}-data:/data" \\\\    
      \\--restart unless-stopped \\\\    
      "$image"    
        
    \\\# 4\\. Update ENV    
    echo "${service\\\_name^^}\\\_PORT=$port" \\\>\\\> "$ENV\\\_FILE"    
        
    \\\# 5\\. Update credentials file    
    cat \\\>\\\> "$CREDS\\\_FILE" \\\<\\\<EOF

${service\\\_name^^}:    
  URL: http://localhost:${port}    
  Added: $(date)    
EOF    
        
    \\\# 6\\. Add to reverse proxy    
    update\\\_reverse\\\_proxy\\\_config "$service\\\_name" "$port"    
        
    log\\\_success "$service\\\_name deployed on port $port"    
}

\#\#\# \*\*Success Definition\*\*

\* ✅ New service deployed without editing Scripts 1-3    
\* ✅ Port automatically allocated    
\* ✅ Service added to reverse proxy routing    
\* ✅ ENV file updated    
\* ✅ Credentials documented

\#\# \*\*KEY ARCHITECTURE DEFINITIONS\*\*

\#\#\# \*\*Primary Access Flows\*\*

\#\#\#\# \*\*1\\. Public Access (via Reverse Proxy)\*\*

User → https://ai.example.com/anythingllm → Caddy → AnythingLLM:3001    
User → https://ai.example.com/dify → Caddy → Dify:3000

\#\#\#\# \*\*2\\. Tailscale Private Access (OpenClaw)\*\*

User → https://tailscale-ip:18789 → Tailscale → OpenClaw:18789

\#\#\#\# \*\*3\\. LLM Request Routing\*\*

Dify → LiteLLM:4000 → \\\[Simple query\\\] → Ollama:11434 → llama3.2:3b    
                    → \\\[Complex query\\\] → OpenAI API → gpt-4-turbo

\#\#\#\# \*\*4\\. Vector DB Flow\*\*

AnythingLLM → Qdrant:6333 (embeddings storage)    
OpenClaw → Qdrant:6333 (knowledge retrieval)    
Dify → Qdrant:6333 (RAG queries)

\#\#\#\# \*\*5\\. Data Sync Flow\*\*

Google Drive → rclone (systemd timer) → /mnt/data/gdrive/ → AnythingLLM ingestion

\---

\#\# \*\*TECHNOLOGY STACK SUMMARY\*\*

| Component | Technology | Purpose | Port |  
| \----- | \----- | \----- | \----- |  
| \*\*LLM Backend\*\* | Ollama | Local inference | 11434 |  
| \*\*Tailscale auth\*\* | tailscale | Retrieve tailscale ip | na |  
| \*\*LLM Gateway\*\* | LiteLLM | Unified API \\+ routing | 4000 |  
| \*\*Vector DB\*\* | Qdrant | Embeddings storage | 6333 |  
| \*\*Document Chat\*\* | AnythingLLM | RAG interface | 3001 |  
| \*\*AI Workflows\*\* | Dify | Visual AI builder | 3000 |  
| \*\*Web Automation\*\* | OpenClaw | Browser automation | 18789 |  
| \*\*Workflow Automation\*\* | n8n | General automation | 5678 |  
| \*\*Reverse Proxy\*\* | Caddy OR Nginx OR traefik | HTTPS termination | 80/443 |  
| \*\*VPN\*\* | Tailscale | Secure remote access | 8443  |  
| \*\*Signal API\*\* | Signal | Pair device for openclaw integration | 8081 |  
| \*\*Data Sync\*\* | Rclone | Google Drive → local | N/A  |  
| \*\*Ai workflows\*\* | Flowise | Visual ai builder | 3000 |  
| \*\*Vector db\*\* | weaviate | Embeddings storage | 50051 |  
| \*\*Vector DB\*\* | Redis | Embeddings storage | 7379 |  
| \*\*Vector db\*\* | Milvus | Embeddings storage | 1953 |  
| \*\*Database\*\* | Postgres | storage | 5432 |  
| \*\*LLM observability\*\* | langfuse | Metrics | 3000 |  
| \*\*LLM observability\*\* | grafana | logging | 3000 |  
| \*\*LLM monitoring\*\* | prometheus | MEtrics | 9090 |  
| \*\*LLM Monitoring\*\* | LOKI=promtai | MEtrics | 3100 |

\#\# \*\*TABLE 1: COMPLETE SERVICE INVENTORY & GAPS\*\* 

In order to initialise step 2 without errors, we reviewed the official documentation for all the stack components and identified additional key variables to generate at step1

| \\\# | Service | Category | Variables Required | File Outputs | Integration Points | Priority |  
| \----- | \----- | \----- | \----- | \----- | \----- | \----- |  
| \*\*REVERSE PROXY\*\* |  |  |  |  |  |  |  
| 1 | \*\*Nginx\*\* | Proxy Option 1 | \`PROXY\_TYPE=nginx\`\\\<br\\\>\`HTTP\_PORT=80\`\\\<br\\\>\`HTTPS\_PORT=443\`\\\<br\\\>\`SSL\_TYPE=letsencrypt/self/none\` | \`compose/nginx.yml\`\\\<br\\\>\`env/nginx.env\`\\\<br\\\>\`config/nginx/nginx.conf\`\\\<br\\\>\`config/nginx/sites/\*.conf\` | All services routed through | 🔴 CRITICAL |  
| 2 | \*\*Traefik\*\* | Proxy Option 2 | \`PROXY\_TYPE=traefik\`\\\<br\\\>\`TRAEFIK\_DASHBOARD=true\`\\\<br\\\>\`TRAEFIK\_API=true\`\\\<br\\\>\`ACME\_EMAIL=\` | \`compose/traefik.yml\`\\\<br\\\>\`env/traefik.env\`\\\<br\\\>\`config/traefik/traefik.yml\`\\\<br\\\>\`config/traefik/dynamic/\*.yml\` | Auto-discovers services via labels | 🔴 CRITICAL |  
| 3 | \*\*Caddy\*\* | Proxy Option 3 | \`PROXY\_TYPE=caddy\`\\\<br\\\>\`CADDY\_AUTO\_HTTPS=true\` | \`compose/caddy.yml\`\\\<br\\\>\`env/caddy.env\`\\\<br\\\>\`config/caddy/Caddyfile\` | Auto HTTPS, simple config | 🔴 CRITICAL |  
| \*\*CORE INFRASTRUCTURE\*\* |  |  |  |  |  |  |  
| 4 | \*\*PostgreSQL\*\* | Database | \`POSTGRES\_VERSION=16-alpine\`\\\<br\\\>\`POSTGRES\_PORT=5432\`\\\<br\\\>Per-service DBs:\\\<br\\\>\`N8N\_DB\`, \`DIFY\_DB\`, \`FLOWISE\_DB\`, \`LITELLM\_DB\`, \`LANGFUSE\_DB\`\\\<br\\\>Each with user/pass | \`compose/postgres.yml\`\\\<br\\\>\`env/postgres.env\`\\\<br\\\>\`config/postgres/init.sql\` | N8N, Dify, Flowise, LiteLLM, Langfuse | 🔴 CRITICAL |  
| 5 | \*\*Redis\*\* | Cache/Queue | \`REDIS\_PORT=6379\`\\\<br\\\>\`REDIS\_PASSWORD=\`\\\<br\\\>\`REDIS\_MAXMEMORY=256mb\`\\\<br\\\>\`REDIS\_POLICY=allkeys-lru\` | \`compose/redis.yml\`\\\<br\\\>\`env/redis.env\`\\\<br\\\>\`config/redis/redis.conf\` | N8N (queue), Dify (cache) | 🔴 CRITICAL |  
| 6 | \*\*Qdrant\*\* | Vector DB | \`QDRANT\_PORT=6333\`\\\<br\\\>\`QDRANT\_GRPC\_PORT=6334\`\\\<br\\\>\`QDRANT\_API\_KEY=\`\\\<br\\\>\`QDRANT\_ALLOW\_ANONYMOUS=false\` | \`compose/qdrant.yml\`\\\<br\\\>\`env/qdrant.env\` | Dify, AnythingLLM, OpenWebUI, Flowise | 🔴 CRITICAL |  
| 7 | \*\*Weaviate\*\* | Vector DB Alt | \`WEAVIATE\_PORT=8080\`\\\<br\\\>\`WEAVIATE\_GRPC\_PORT=50051\`\\\<br\\\>\`AUTHENTICATION\_API\_KEY=\` | \`compose/weaviate.yml\`\\\<br\\\>\`env/weaviate.env\` | Alternative to Qdrant | 🟡 HIGH |  
| 8 | \*\*Milvus\*\* | Vector DB Alt | \`MILVUS\_PORT=19530\`\\\<br\\\>\`MILVUS\_USER=\`\\\<br\\\>\`MILVUS\_PASSWORD=\`\\\<br\\\>\`ETCD\_ENDPOINTS=\` | \`compose/milvus.yml\`\\\<br\\\>\`env/milvus.env\`\\\<br\\\>\`config/milvus/milvus.yaml\` | Alternative to Qdrant | 🟡 HIGH |  
| \*\*COMMUNICATION & STORAGE\*\* |  |  |  |  |  |  |  
| 9 | \*\*Signal-API\*\* | Messaging | \*\*QR Method:\*\*\\\<br\\\>\`SIGNAL\_NUMBER=+1234567890\`\\\<br\\\>\`SIGNAL\_DEVICE\_NAME=\`\\\<br\\\>\`MODE=native\`\\\<br\\\>\\\<br\\\>\*\*API Method:\*\*\\\<br\\\>\`SIGNAL\_NUMBER=+1234567890\`\\\<br\\\>\`SIGNAL\_CAPTCHA\_TOKEN=\`\\\<br\\\>\`SIGNAL\_VERIFICATION\_CODE=\`\\\<br\\\>\`MODE=json-rpc\` | \`compose/signal-api.yml\`\\\<br\\\>\`env/signal-api.env\` | N8N webhooks, notifications | 🔴 CRITICAL |  
| 10 | \*\*Google Drive\*\* | Storage | \*\*OAuth:\*\*\\\<br\\\>\`GDRIVE\_CLIENT\_ID=\`\\\<br\\\>\`GDRIVE\_CLIENT\_SECRET=\`\\\<br\\\>\`GDRIVE\_REDIRECT\_URI=\`\\\<br\\\>\`GDRIVE\_REFRESH\_TOKEN=\`\\\<br\\\>\\\<br\\\>\*\*Service Account:\*\*\\\<br\\\>\`GDRIVE\_SERVICE\_ACCOUNT\_EMAIL=\`\\\<br\\\>\`GDRIVE\_SERVICE\_ACCOUNT\_KEY=\` (base64)\\\<br\\\>\\\<br\\\>\*\*API Key:\*\*\\\<br\\\>\`GDRIVE\_API\_KEY=\`\\\<br\\\>\`GDRIVE\_FOLDER\_ID=\` | \`compose/gdrive.yml\`\\\<br\\\>\`env/gdrive.env\`\\\<br\\\>\`config/gdrive/credentials.json\` | N8N workflows, Dify uploads | 🔴 CRITICAL |  
| \*\*LLM ENGINES\*\* |  |  |  |  |  |  |  
| 11 | \*\*Ollama\*\* | LLM Runtime | \`OLLAMA\_HOST=0.0.0.0\`\\\<br\\\>\`OLLAMA\_ORIGINS=\*\`\\\<br\\\>\`OLLAMA\_PORT=11434\`\\\<br\\\>\`OLLAMA\_MODELS=\` (comma-separated)\\\<br\\\>\`OLLAMA\_KEEP\_ALIVE=5m\` | \`compose/ollama.yml\`\\\<br\\\>\`env/ollama.env\`\\\<br\\\>\`metadata/ollama\_models.json\` | All AI platforms, LiteLLM | 🔴 CRITICAL |  
| 12 | \*\*LiteLLM\*\* | LLM Proxy | \`LITELLM\_PORT=4000\`\\\<br\\\>\`LITELLM\_MASTER\_KEY=\`\\\<br\\\>\`LITELLM\_SALT\_KEY=\`\\\<br\\\>\`DATABASE\_URL=postgresql://...\`\\\<br\\\>\`STORE\_MODEL\_IN\_DB=true\`\\\<br\\\>\`UI\_USERNAME=\`\\\<br\\\>\`UI\_PASSWORD=\`\\\<br\\\>\\\<br\\\>\*\*Per Provider:\*\*\\\<br\\\>\`OPENAI\_API\_KEY=\`\\\<br\\\>\`ANTHROPIC\_API\_KEY=\`\\\<br\\\>\`GOOGLE\_API\_KEY=\`\\\<br\\\>\`GROQ\_API\_KEY=\`\\\<br\\\>\`MISTRAL\_API\_KEY=\`\\\<br\\\>\`COHERE\_API\_KEY=\`\\\<br\\\>\`TOGETHER\_API\_KEY=\`\\\<br\\\>\`PERPLEXITY\_API\_KEY=\`\\\<br\\\>\`DEEPSEEK\_API\_KEY=\`\\\<br\\\>\`XAI\_API\_KEY=\`\\\<br\\\>\`FIREWORKS\_API\_KEY=\`\\\<br\\\>\`OPENROUTER\_API\_KEY=\`\\\<br\\\>\\\<br\\\>\*\*Routing:\*\*\\\<br\\\>\`ROUTING\_STRATEGY=complexity-based/internal-only/external-only/fallback\`\\\<br\\\>\`COMPLEXITY\_THRESHOLD=2000\`\\\<br\\\>\`FALLBACK\_MODELS=\` (comma-separated) | \`compose/litellm.yml\`\\\<br\\\>\`env/litellm.env\`\\\<br\\\>\`config/litellm/config.yaml\` (routing rules) | All AI platforms | 🔴 CRITICAL |  
| 13 | \*\*LocalAI\*\* | LLM Alt | \`LOCALAI\_PORT=8080\`\\\<br\\\>\`LOCALAI\_MODELS\_PATH=/models\`\\\<br\\\>\`THREADS=4\`\\\<br\\\>\`CONTEXT\_SIZE=4096\` | \`compose/localai.yml\`\\\<br\\\>\`env/localai.env\` | Alternative to Ollama | 🟢 LOW |  
| \*\*AI PLATFORMS\*\* |  |  |  |  |  |  |  
| 14 | \*\*OpenWebUI\*\* | Chat UI | \`WEBUI\_PORT=8080\`\\\<br\\\>\`OLLAMA\_BASE\_URL=http://ollama:11434\`\\\<br\\\>\`WEBUI\_SECRET\_KEY=\`\\\<br\\\>\`WEBUI\_NAME="AI Platform"\`\\\<br\\\>\`DEFAULT\_MODELS=\`\\\<br\\\>\`DEFAULT\_USER\_ROLE=user\`\\\<br\\\>\\\<br\\\>\*\*RAG Config:\*\*\\\<br\\\>\`RAG\_EMBEDDING\_MODEL=nomic-embed-text\`\\\<br\\\>\`RAG\_VECTOR\_DB=qdrant\`\\\<br\\\>\`QDRANT\_URL=http://qdrant:6333\`\\\<br\\\>\`QDRANT\_API\_KEY=\` | \`compose/openwebui.yml\`\\\<br\\\>\`env/openwebui.env\` | Ollama, Qdrant | 🔴 CRITICAL |  
| 15 | \*\*AnythingLLM\*\* | Document AI | \`SERVER\_PORT=3001\`\\\<br\\\>\`STORAGE\_DIR=/app/storage\`\\\<br\\\>\`JWT\_SECRET=\`\\\<br\\\>\`LLM\_PROVIDER=ollama\`\\\<br\\\>\`EMBEDDING\_ENGINE=ollama\`\\\<br\\\>\`EMBEDDING\_MODEL=nomic-embed-text\`\\\<br\\\>\\\<br\\\>\*\*Vector DB:\*\*\\\<br\\\>\`VECTOR\_DB=qdrant\`\\\<br\\\>\`QDRANT\_ENDPOINT=http://qdrant:6333\`\\\<br\\\>\`QDRANT\_API\_KEY=\` | \`compose/anythingllm.yml\`\\\<br\\\>\`env/anythingllm.env\` | Ollama, Qdrant | 🔴 CRITICAL |  
| 16 | \*\*Dify\*\* | AI Workflow | \`DIFY\_PORT=80\`\\\<br\\\>\`MODE=production\`\\\<br\\\>\`SECRET\_KEY=\`\\\<br\\\>\`INIT\_PASSWORD=\`\\\<br\\\>\`CONSOLE\_WEB\_URL=https://domain/dify\`\\\<br\\\>\`SERVICE\_API\_URL=https://domain/dify/api\`\\\<br\\\>\\\<br\\\>\*\*Database:\*\*\\\<br\\\>\`DB\_HOST=postgres\`\\\<br\\\>\`DB\_PORT=5432\`\\\<br\\\>\`DB\_DATABASE=dify\`\\\<br\\\>\`DB\_USERNAME=dify\`\\\<br\\\>\`DB\_PASSWORD=\`\\\<br\\\>\\\<br\\\>\*\*Redis:\*\*\\\<br\\\>\`REDIS\_HOST=redis\`\\\<br\\\>\`REDIS\_PORT=6379\`\\\<br\\\>\`REDIS\_PASSWORD=\`\\\<br\\\>\`REDIS\_USE\_SSL=false\`\\\<br\\\>\`REDIS\_DB=0\`\\\<br\\\>\\\<br\\\>\*\*Vector DB:\*\*\\\<br\\\>\`VECTOR\_STORE=qdrant\`\\\<br\\\>\`QDRANT\_URL=http://qdrant:6333\`\\\<br\\\>\`QDRANT\_API\_KEY=\`\\\<br\\\>\`QDRANT\_CLIENT\_TIMEOUT=20\`\\\<br\\\>\\\<br\\\>\*\*Storage:\*\*\\\<br\\\>\`STORAGE\_TYPE=local\`\\\<br\\\>\`STORAGE\_LOCAL\_PATH=/app/storage\` | \`compose/dify.yml\` (api \\+ worker \\+ web)\\\<br\\\>\`env/dify.env\` | Postgres, Redis, Qdrant, Ollama, LiteLLM | 🔴 CRITICAL |  
| 17 | \*\*N8N\*\* | Workflow | \`N8N\_PORT=5678\`\\\<br\\\>\`N8N\_HOST=n8n\`\\\<br\\\>\`N8N\_PROTOCOL=https\`\\\<br\\\>\`N8N\_EDITOR\_BASE\_URL=https://domain/n8n\`\\\<br\\\>\`WEBHOOK\_URL=https://domain/n8n\`\\\<br\\\>\`N8N\_ENCRYPTION\_KEY=\`\\\<br\\\>\\\<br\\\>\*\*Database:\*\*\\\<br\\\>\`DB\_TYPE=postgresdb\`\\\<br\\\>\`DB\_POSTGRESDB\_HOST=postgres\`\\\<br\\\>\`DB\_POSTGRESDB\_PORT=5432\`\\\<br\\\>\`DB\_POSTGRESDB\_DATABASE=n8n\`\\\<br\\\>\`DB\_POSTGRESDB\_USER=n8n\`\\\<br\\\>\`DB\_POSTGRESDB\_PASSWORD=\`\\\<br\\\>\\\<br\\\>\*\*Redis Queue:\*\*\\\<br\\\>\`QUEUE\_BULL\_REDIS\_HOST=redis\`\\\<br\\\>\`QUEUE\_BULL\_REDIS\_PORT=6379\`\\\<br\\\>\`QUEUE\_BULL\_REDIS\_PASSWORD=\`\\\<br\\\>\`EXECUTIONS\_MODE=queue\`\\\<br\\\>\\\<br\\\>\*\*User Management:\*\*\\\<br\\\>\`N8N\_USER\_MANAGEMENT\_DISABLED=false\`\\\<br\\\>\`N8N\_EMAIL\_MODE=smtp\` (optional) | \`compose/n8n.yml\`\\\<br\\\>\`env/n8n.env\` | Postgres, Redis, Signal, GDrive | 🔴 CRITICAL |  
| 18 | \*\*Flowise\*\* | Low-code AI | \`FLOWISE\_PORT=3000\`\\\<br\\\>\`FLOWISE\_USERNAME=\`\\\<br\\\>\`FLOWISE\_PASSWORD=\`\\\<br\\\>\`PASSPHRASE=\`\\\<br\\\>\\\<br\\\>\*\*Database:\*\*\\\<br\\\>\`DATABASE\_TYPE=postgres\`\\\<br\\\>\`DATABASE\_HOST=postgres\`\\\<br\\\>\`DATABASE\_PORT=5432\`\\\<br\\\>\`DATABASE\_NAME=flowise\`\\\<br\\\>\`DATABASE\_USER=flowise\`\\\<br\\\>\`DATABASE\_PASSWORD=\`\\\<br\\\>\\\<br\\\>\*\*Vector DB (in flows):\*\*\\\<br\\\>Configured via UI to connect to Qdrant | \`compose/flowise.yml\`\\\<br\\\>\`env/flowise.env\` | Postgres, Qdrant (via UI), Ollama | 🔴 CRITICAL |  
| \*\*OBSERVABILITY\*\* |  |  |  |  |  |  |  
| 19 | \*\*Langfuse\*\* | LLM Observability | \`LANGFUSE\_PORT=3000\`\\\<br\\\>\`NEXTAUTH\_URL=https://domain/langfuse\`\\\<br\\\>\`NEXTAUTH\_SECRET=\`\\\<br\\\>\`SALT=\`\\\<br\\\>\`ENCRYPTION\_KEY=\`\\\<br\\\>\\\<br\\\>\*\*Database:\*\*\\\<br\\\>\`DATABASE\_URL=postgresql://langfuse:pass@postgres:5432/langfuse\`\\\<br\\\>\\\<br\\\>\*\*Auth:\*\*\\\<br\\\>\`LANGFUSE\_INIT\_USER\_EMAIL=\`\\\<br\\\>\`LANGFUSE\_INIT\_USER\_PASSWORD=\`\\\<br\\\>\`LANGFUSE\_INIT\_PROJECT\_NAME="AI Platform"\`\\\<br\\\>\`LANGFUSE\_INIT\_PROJECT\_PUBLIC\_KEY=\`\\\<br\\\>\`LANGFUSE\_INIT\_PROJECT\_SECRET\_KEY=\` | \`compose/langfuse.yml\`\\\<br\\\>\`env/langfuse.env\` | Postgres, LiteLLM integration | 🟡 HIGH |  
| 20 | \*\*Prometheus\*\* | Metrics | \`PROMETHEUS\_PORT=9090\`\\\<br\\\>\`SCRAPE\_INTERVAL=15s\`\\\<br\\\>\`RETENTION\_TIME=15d\`\\\<br\\\>\\\<br\\\>\*\*Scrape Configs:\*\*\\\<br\\\>- Node Exporter\\\<br\\\>- cAdvisor\\\<br\\\>- All services with /metrics | \`compose/prometheus.yml\`\\\<br\\\>\`env/prometheus.env\`\\\<br\\\>\`config/prometheus/prometheus.yml\` | All services | 🟡 MEDIUM |  
| 21 | \*\*Grafana\*\* | Dashboards | \`GRAFANA\_PORT=3000\`\\\<br\\\>\`GF\_SECURITY\_ADMIN\_USER=admin\`\\\<br\\\>\`GF\_SECURITY\_ADMIN\_PASSWORD=\`\\\<br\\\>\`GF\_SERVER\_ROOT\_URL=https://domain/grafana\`\\\<br\\\>\`GF\_AUTH\_ANONYMOUS\_ENABLED=false\`\\\<br\\\>\\\<br\\\>\*\*Datasources:\*\*\\\<br\\\>- Prometheus\\\<br\\\>- Loki\\\<br\\\>- Postgres (optional) | \`compose/grafana.yml\`\\\<br\\\>\`env/grafana.env\`\\\<br\\\>\`config/grafana/datasources.yml\`\\\<br\\\>\`config/grafana/dashboards/\*.json\` | Prometheus, Loki | 🟡 MEDIUM |  
| 22 | \*\*Loki \\+ Promtail\*\* | Logs | \`LOKI\_PORT=3100\`\\\<br\\\>\`LOKI\_RETENTION\_PERIOD=168h\`\\\<br\\\>\`PROMTAIL\_PORT=9080\` | \`compose/loki.yml\`\\\<br\\\>\`compose/promtail.yml\`\\\<br\\\>\`env/loki.env\`\\\<br\\\>\`config/loki/loki-config.yaml\`\\\<br\\\>\`config/promtail/promtail-config.yaml\` | Grafana, all containers | 🟡 MEDIUM |  
| 23 | \*\*cAdvisor\*\* | Container Stats | \`CADVISOR\_PORT=8080\` | \`compose/cadvisor.yml\`\\\<br\\\>\`env/cadvisor.env\` | Prometheus | 🟡 MEDIUM |  
| 24 | \*\*Node Exporter\*\* | Host Metrics | \`NODE\_EXPORTER\_PORT=9100\` | \`compose/node-exporter.yml\`\\\<br\\\>\`env/node-exporter.env\` | Prometheus | 🟡 MEDIUM |

\---

\#\# \*\*TABLE 2: CORRECTED USER INTERACTION FLOW\*\*

Copy table

| Step | Phase | Interaction | Output Files | Next Script Uses | Priority |  
| \----- | \----- | \----- | \----- | \----- | \----- |  
| \*\*0\*\* | \*\*PRE-FLIGHT\*\* | Port availability check (80, 443, all services) | \`metadata/port\_check.json\` | Script 2 validates before deploy | 🔴 CRITICAL |  
| \*\*1\*\* | \*\*PROXY SELECTION\*\* | \*\*CORRECTED:\*\*\\\<br\\\>1) Nginx\\\<br\\\>2) Traefik\\\<br\\\>3) \*\*Caddy\*\*\\\<br\\\>4) None\\\<br\\\>\\\<br\\\>+ SSL type selection | \`compose/{nginx|traefik|caddy}.yml\`\\\<br\\\>\`env/{proxy}.env\`\\\<br\\\>\`config/{proxy}/...\`\\\<br\\\>\`metadata/proxy\_config.json\` | Script 2 deploys proxy first | 🔴 CRITICAL |  
| 2 | \*\*DOMAIN/IP\*\* | Domain input → DNS resolution → Store public IP | \`metadata/network\_config.json\` | Script 2 configures proxy routing | 🔴 CRITICAL |  
| 3 | \*\*DIRECTORY\*\* | Validate \`/mnt/data\`, create structure | \`metadata/directory\_structure.json\` | Script 2 mounts volumes | 🔴 CRITICAL |  
| 4 | \*\*VECTOR DB\*\* | Qdrant / Weaviate / Milvus choice | \`compose/{vectordb}.yml\`\\\<br\\\>\`env/{vectordb}.env\`\\\<br\\\>\`metadata/vectordb\_choice.json\` | Script 3 configures AI platforms to use it | 🔴 CRITICAL |  
| 5 | \*\*OLLAMA MODELS\*\* | \*\*Dynamic fetch\*\* from \`ollama.ai/library/api\`, user selects | \`metadata/ollama\_models.json\`\\\<br\\\>\`env/ollama.env\` | Script 2 downloads selected models | 🔴 CRITICAL |  
| 6 | \*\*LLM PROVIDERS\*\* | \*\*All 12 providers\*\* (OpenAI, Anthropic, Google, Groq, Mistral, Cohere, Together, Perplexity, DeepSeek, xAI, Fireworks, OpenRouter) | \`env/litellm.env\` (per-provider API keys)\\\<br\\\>\`metadata/providers.json\` | Script 2 configures LiteLLM | 🔴 CRITICAL |  
| 7 | \*\*LITELLM ROUTING\*\* | Strategy selection:\\\<br\\\>1) Internal-only\\\<br\\\>2) External-only\\\<br\\\>3) \*\*Hybrid (complexity-based)\*\*\\\<br\\\>4) Fallback chain | \`config/litellm/config.yaml\`\\\<br\\\>\`metadata/routing\_strategy.json\` | Script 2 loads routing config | 🔴 CRITICAL |  
| 8 | \*\*AI PLATFORMS\*\* | Service selection \\+ per-service config | Individual \`compose/\*.yml\` \\+ \`env/\*.env\` files | Script 2 deploys selected services | 🔴 CRITICAL |  
| 9 | \*\*VECTOR DB INTEGRATION\*\* | \*\*Auto-configure\*\* all selected AI platforms to use chosen vector DB | Updates to \`env/dify.env\`, \`env/anythingllm.env\`, \`env/openwebui.env\` | Script 3 verifies connections | 🔴 CRITICAL |  
| 10 | \*\*SIGNAL-API\*\* | Method selection:\\\<br\\\>1) QR Code\\\<br\\\>2) API registration | \`compose/signal-api.yml\`\\\<br\\\>\`env/signal-api.env\`\\\<br\\\>\`metadata/signal\_config.json\` | Script 2 starts pairing process | 🔴 CRITICAL |  
| 11 | \*\*GOOGLE DRIVE\*\* | Auth method:\\\<br\\\>1) OAuth\\\<br\\\>2) Service Account\\\<br\\\>3) API Key | \`compose/gdrive.yml\`\\\<br\\\>\`env/gdrive.env\`\\\<br\\\>\`config/gdrive/credentials.json\`\\\<br\\\>\`metadata/gdrive\_config.json\` | Script 3 completes OAuth flow if needed | 🔴 CRITICAL |  
| 12 | \*\*MONITORING\*\* | Service selection (Langfuse, Prometheus, etc.) | Individual \`compose/\*.yml\` \\+ \`env/\*.env\` | Script 2 deploys monitoring stack | 🟡 HIGH |  
| 13 | \*\*SUMMARY\*\* | Display all choices, confirm | \`metadata/deployment\_summary.json\` | Script 2 reads as deployment plan | 🔴 CRITICAL |

\#\# \*\*SUCCESS CRITERIA BY PHASE\*\*

\#\#\# \*\*Phase 0 (Cleanup)\*\*

\* ✅ System returned to clean state    
\* ✅ No orphaned containers/volumes/networks    
\* ✅ Ready for fresh deployment

\#\#\# \*\*Phase 1 (Setup)\*\*

\* ✅ All ports allocated without conflicts    
\* ✅ User reviewed and approved configuration    
\* ✅ \`.env\` file generated (pure text, no ANSI codes)    
\* ✅ Docker group permissions active    
\* ✅ Reverse proxy config files created    
\* ✅ NO containers running yet

\#\#\# \*\*Phase 2 (Deployment)\*\*

\* ✅ All containers running with \`restart: unless-stopped\`    
\* ✅ All services pass health checks    
\* ✅ Inter-service communication works    
\* ✅ Reverse proxy routes traffic correctly    
\* ✅ Tailscale connected    
\* ✅ Credentials documented

\#\#\# \*\*Phase 3 (Configuration)\*\*

\* ✅ LLM models loaded in Ollama    
\* ✅ LiteLLM routing configured (local → cloud fallback)    
\* ✅ AnythingLLM using Qdrant \\+ Ollama    
\* ✅ OpenClaw linked to AnythingLLM    
\* ✅ OpenClaw accessible via Tailscale HTTPS    
\* ✅ Dify using LiteLLM gateway    
\* ✅ Google Drive sync active    
\* ✅ Services auto-start on reboot

\#\#\# \*\*Phase 4 (Extensibility)\*\*

\* ✅ New services can be added via standardized script    
\* ✅ No modification of core scripts required    
\* ✅ Automatic integration with existing infrastructure

\---

\#\# \*\*FINAL VALIDATION CHECKLIST\*\*

\*\*After completing all 4 scripts, the system MUST:\*\*

1\. ✅ \*\*Deploy from scratch\*\* on fresh Ubuntu in \\\<30 minutes    
2\. ✅ \*\*Survive reboots\*\* (all services auto-restart)    
3\. ✅ \*\*Route LLM requests\*\* intelligently (local-first, cloud fallback)    
4\. ✅ \*\*Expose services\*\* via HTTPS (Caddy auto-cert OR Nginx self-signed)    
5\. ✅ \*\*Secure remote access\*\* via Tailscale VPN    
6\. ✅ \*\*Sync Google Drive\*\* to \`/mnt/data/gdrive/\` automatically    
7\. ✅ \*\*Link OpenClaw\*\* to AnythingLLM vector DB    
8\. ✅ \*\*Accessible endpoints:\*\*    
   \* Public: \`https://domain/anythingllm\`, \`https://domain/dify\`    
   \* Private: \`https://tailscale-ip:18789\` (OpenClaw)    
9\. ✅ \*\*Zero manual configuration\*\* (all via scripts)    
10\. ✅ \*\*Fully documented\*\* (credentials.txt, .env, logs)

Codebase : 

\* The repository \[https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation\](https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation)    
\* high level objectives here : \[https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/README.md\](https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/README.md)    
\* The previous (superseeded) high level objectives : \[https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/3176f2f3da7ee9ccb2908380387df3e38923a8d4/README.md\](https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/3176f2f3da7ee9ccb2908380387df3e38923a8d4/README.md)    
\* script 0 : https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/0-complete-cleanup.sh    
\* script 1: https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/1-setup-system.sh    
\* script 2 : https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/2-deploy-services.sh    
\* script 3 : https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/3-configure-services.sh    
\* script 4 : https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/3-configure-services.sh    
      
\* This was a good start ui wise : \[https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/7df4b977d0d66f7dcdd0b099a38fb4011402d280/scripts/1-setup-system.sh\](https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/7df4b977d0d66f7dcdd0b099a38fb4011402d280/scripts/1-setup-system.sh)    
\* This was the iteration with more bugs : \[https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/0af338937926c8d052d9a413b79409376e8c7dfa/scripts/1-setup-system.sh\](https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/0af338937926c8d052d9a413b79409376e8c7dfa/scripts/1-setup-system.sh)    
\* This was a good attempt to incorporate all mandatory variables from services : https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/069b5f51f047319120a1a97080116bbe4a1d322b/scripts/1-setup-system.sh

 

