\# AI Platform Deployment Guide

\> \*\*Version:\*\* 76.2.0  
\> \*\*Date:\*\* 2025-07-12  
\> \*\*Repository:\*\* \[github.com/jgla1ne/AIPlatformAutomation\](https://github.com/jgla1ne/AIPlatformAutomation)  
\> \*\*Previous:\*\* 76.1.0 → 76.2.0 (full rewrite — architecture corrections, Hetzner references removed, EC2-native)

| Script | Status |  
|--------|--------|  
| \`0-complete-cleanup.sh\` | Tested ✅ |  
| \`1-setup-system.sh\` | In Progress 🔧 (fails at dependency install) |  
| \`2-deploy-services.sh\` | Projected 📐 |  
| \`3-configure-services.sh\` | Projected 📐 |  
| \`4-add-service.sh\` | Projected 📐 |

\---

\#\# Table of Contents

1\. \[Executive Summary\](\#1-executive-summary)  
2\. \[System Architecture\](\#2-system-architecture)  
3\. \[Repository & Folder Structure\](\#3-repository--folder-structure)  
4\. \[Service Inventory & Port Map\](\#4-service-inventory--port-map)  
5\. \[Storage Architecture\](\#5-storage-architecture)  
6\. \[Network & Access Architecture\](\#6-network--access-architecture)  
7\. \[LLM Models — Local (Ollama)\](\#7-llm-models--local-ollama)  
8\. \[LLM Models — External (Cloud APIs)\](\#8-llm-models--external-cloud-apis)  
9\. \[LiteLLM Routing Strategy\](\#9-litellm-routing-strategy)  
10\. \[Vector Database — Fluid Selection & OpenClaw Integration\](\#10-vector-database--fluid-selection--openclaw-integration)  
11\. \[Google Drive Rsync — Authentication & Embedding Pipeline\](\#11-google-drive-rsync--authentication--embedding-pipeline)  
12\. \[Reverse Proxy — Fluid Selection\](\#12-reverse-proxy--fluid-selection)  
13\. \[Monitoring — Optional Prometheus & Grafana Stack\](\#13-monitoring--optional-prometheus--grafana-stack)  
14\. \[Security Model\](\#14-security-model)  
15\. \[Credentials & Secrets Management\](\#15-credentials--secrets-management)  
16\. \[Script Pipeline Overview\](\#16-script-pipeline-overview)  
17\. \[Script 0 — Nuclear Clean\](\#17-script-0--nuclear-clean)  
18\. \[Script 1 — System Setup\](\#18-script-1--system-setup)  
19\. \[Script 2 — Deploy Services\](\#19-script-2--deploy-services)  
20\. \[Script 3 — Configure Services\](\#20-script-3--configure-services)  
21\. \[Script 4 — Add Service\](\#21-script-4--add-service)  
22\. \[Per-Service Configuration Details\](\#22-per-service-configuration-details)  
23\. \[Backup & Disaster Recovery\](\#23-backup--disaster-recovery)  
24\. \[Startup Order & Dependency Chain\](\#24-startup-order--dependency-chain)  
25\. \[Lessons Learnt & No-Go Rules\](\#25-lessons-learnt--no-go-rules)  
26\. \[Changelog\](\#26-changelog)

\---

\#\# 1\. Executive Summary

This document is the complete specification for deploying a self-hosted AI platform on a \*\*single EC2 instance\*\* running Ubuntu 24.04 LTS. The platform provides:

| Capability | Service(s) |  
|------------|-----------|  
| AI workflow orchestration | Dify, n8n, Flowise |  
| Chat interface | Open WebUI |  
| Local LLM inference | Ollama (native systemd) |  
| Cloud LLM routing | LiteLLM proxy |  
| Knowledge base / RAG | OpenClaw \+ Vector DB (fluid) |  
| Document storage & sync | Google Drive → local rsync → embedding pipeline |  
| Object storage | MinIO |  
| Reverse proxy & TLS | Caddy or nginx (fluid) |  
| Monitoring (optional) | Prometheus \+ Grafana \+ Dozzle |  
| Container log viewer | Dozzle |  
| Backup | Local snapshots \+ Google Drive |

\#\#\# Design Principles

1\. \*\*Single machine\*\* — one EC2 instance, no cluster orchestration  
2\. \*\*One compose per service\*\* — modular, independently manageable  
3\. \*\*Tailscale-only access\*\* — no public ports, no UFW (EC2 security groups \+ Tailscale)  
4\. \*\*Fluid selections\*\* — vector DB, reverse proxy, LLM models chosen at deploy time  
5\. \*\*Script separation\*\* — setup (1) → deploy (2) → configure (3) → extend (4)  
6\. \*\*All logs under \`$ROOT\_PATH/logs/\`\*\* — every script logs everything  
7\. \*\*Secrets auto-generated, user-confirmed\*\* — visible via interactive prompts

\---

\#\# 2\. System Architecture

\#\#\# Hardware (EC2)

| Resource | Minimum | Recommended |  
|----------|---------|-------------|  
| vCPU | 4 | 8+ |  
| RAM | 16 GB | 32 GB+ |  
| OS Disk | 30 GB | 50 GB |  
| Data Disk (EBS) | 100 GB | 200 GB+ |  
| GPU | Optional | NVIDIA (for local LLM) |

\#\#\# Architecture Tiers

┌─────────────────────────────────────────────────────────────┐ │ EC2 INSTANCE (Ubuntu 24.04) │ ├─────────────────────────────────────────────────────────────┤ │ Tier 0: OS \+ System Packages \[Script 1\] │ │ └── Docker, Docker Compose, NVIDIA drivers (if GPU) │ │ │ │ Tier 1: Networking \[Script 1\] │ │ └── Tailscale VPN, Docker networks │ │ │ │ Tier 2: Storage \[Script 1\] │ │ └── /mnt/data mount, directory tree, fstab │ │ │ │ Tier 3: Data Layer \[Script 2\] │ │ └── PostgreSQL, Redis, Vector DB, MinIO │ │ │ │ Tier 4: Infrastructure Services \[Script 2\] │ │ └── Ollama (systemd), LiteLLM, Reverse Proxy │ │ │ │ Tier 5: Application Services \[Script 2\] │ │ └── Dify, n8n, Open WebUI, Flowise, AnythingLLM │ │ │ │ Tier 6: Knowledge & RAG \[Script 2 \+ 3\] │ │ └── OpenClaw, Google Drive sync, embedding pipeline │ │ │ │ Tier 7: Monitoring (Optional) \[Script 2 \+ 3\] │ │ └── Prometheus, Grafana, Dozzle │ ├─────────────────────────────────────────────────────────────┤ │ Configuration & Wiring \[Script 3\] │ │ Service Addition \[Script 4\] │ │ Full Reset \[Script 0\] │ └─────────────────────────────────────────────────────────────┘

\#\#\# Data Flow

User (browser) │ ▼ Tailscale VPN tunnel │ ▼ Reverse Proxy (Caddy/nginx) :443 │ ├──► Dify :3000 ──► LiteLLM :4000 ──► Ollama :11434 ├──► n8n :5678 ──► LiteLLM :4000 ──► Cloud APIs ├──► Open WebUI :8080 ──► Ollama :11434 (direct) ├──► Flowise :3001 ──► LiteLLM :4000 ├──► AnythingLLM :3002 ──► LiteLLM :4000 ├──► OpenClaw :8888 ──► Vector DB :6333/:19530/:8001 ├──► Grafana :3100 (optional) ├──► Dozzle :9999 └──► MinIO :9001 (console) │ ▼ MinIO API :9000 (S3-compatible, internal)

\---

\#\# 3\. Repository & Folder Structure

\#\#\# Git Repository (OS Disk)

\~/AIPlatformAutomation/ ├── scripts/ │ ├── 0-complete-cleanup.sh │ ├── 1-setup-system.sh │ ├── 2-deploy-services.sh │ ├── 3-configure-services.sh │ └── 4-add-service.sh ├── lib/ │ └── common.sh \# Shared functions (logging, prompts, checks) ├── templates/ │ ├── docker-compose/ │ │ ├── dify.yaml.tpl │ │ ├── n8n.yaml.tpl │ │ ├── open-webui.yaml.tpl │ │ ├── flowise.yaml.tpl │ │ ├── anythingllm.yaml.tpl │ │ ├── openclaw.yaml.tpl │ │ ├── litellm.yaml.tpl │ │ ├── postgres.yaml.tpl │ │ ├── redis.yaml.tpl │ │ ├── qdrant.yaml.tpl │ │ ├── weaviate.yaml.tpl │ │ ├── milvus.yaml.tpl │ │ ├── minio.yaml.tpl │ │ ├── caddy.yaml.tpl │ │ ├── nginx.yaml.tpl │ │ ├── prometheus.yaml.tpl │ │ ├── grafana.yaml.tpl │ │ └── dozzle.yaml.tpl │ ├── configs/ │ │ ├── litellm-config.yaml.tpl │ │ ├── Caddyfile.tpl │ │ ├── nginx.conf.tpl │ │ ├── prometheus.yml.tpl │ │ └── grafana-datasources.yaml.tpl │ └── env/ │ └── master.env.tpl ├── doc/ │ └── AI-PLATFORM-DEPLOYMENT-GUIDE-76.2.0.md ├── logs/ \# All script output logs │ ├── script-0-*.log │ ├── script-1-*.log │ ├── script-2-*.log │ ├── script-3-*.log │ └── script-4-\*.log └── README.md

\#\#\# Runtime Data (/mnt/data)

/mnt/data/ ├── docker/ │ ├── dify/ │ │ ├── docker-compose.yaml \# Generated from template │ │ ├── .env \# Service-specific env │ │ └── data/ \# Persistent volumes │ ├── n8n/ │ │ ├── docker-compose.yaml │ │ ├── .env │ │ └── data/ │ ├── open-webui/ │ │ ├── docker-compose.yaml │ │ ├── .env │ │ └── data/ │ ├── flowise/ │ │ ├── docker-compose.yaml │ │ ├── .env │ │ └── data/ │ ├── anythingllm/ │ │ ├── docker-compose.yaml │ │ ├── .env │ │ └── data/ │ ├── openclaw/ │ │ ├── docker-compose.yaml │ │ ├── .env │ │ └── data/ │ ├── litellm/ │ │ ├── docker-compose.yaml │ │ ├── .env │ │ ├── config.yaml \# LiteLLM routing config │ │ └── data/ │ ├── postgres/ │ │ ├── docker-compose.yaml │ │ ├── .env │ │ ├── init/ \# SQL init scripts │ │ │ └── 00-create-databases.sql │ │ └── data/ │ ├── redis/ │ │ ├── docker-compose.yaml │ │ └── data/ │ ├── vector-db/ \# Whichever was selected │ │ ├── docker-compose.yaml │ │ ├── .env │ │ └── data/ │ ├── minio/ │ │ ├── docker-compose.yaml │ │ ├── .env │ │ └── data/ │ ├── caddy/ (or nginx/) │ │ ├── docker-compose.yaml │ │ ├── Caddyfile (or nginx.conf) │ │ ├── data/ │ │ └── config/ │ ├── prometheus/ \# Optional │ │ ├── docker-compose.yaml │ │ ├── prometheus.yml │ │ └── data/ │ ├── grafana/ \# Optional │ │ ├── docker-compose.yaml │ │ ├── provisioning/ │ │ └── data/ │ └── dozzle/ │ └── docker-compose.yaml ├── ollama/ │ └── models/ \# Ollama model storage ├── gdrive/ \# Google Drive rsync target │ └── (synced files for embedding) ├── backups/ │ ├── daily/ │ └── manual/ ├── secrets/ │ └── master.env \# All credentials (chmod 600\) └── logs/ \# Symlink → \~/AIPlatformAutomation/logs/

\---

\#\# 4\. Service Inventory & Port Map

\#\#\# Core Services

| Service | Container Name | Port | Network(s) | Depends On | Disk |  
|---------|---------------|------|------------|------------|------|  
| PostgreSQL | postgres | 5432 | backend | — | data |  
| Redis | redis | 6379 | backend | — | data |  
| Vector DB (fluid) | qdrant/weaviate/milvus | 6333/8080/19530 | backend | — | data |  
| MinIO | minio | 9000 (API), 9001 (console) | backend, frontend | — | data |  
| Ollama | — (systemd) | 11434 | host network | — | data |

\#\#\# Infrastructure Services

| Service | Container Name | Port | Network(s) | Depends On | Disk |  
|---------|---------------|------|------------|------------|------|  
| LiteLLM | litellm | 4000 | backend, frontend | PostgreSQL | data |  
| Caddy (or nginx) | caddy | 80, 443 | frontend | — | data |

\#\#\# Application Services

| Service | Container Name | Port | Network(s) | Depends On | Disk |  
|---------|---------------|------|------------|------------|------|  
| Dify | dify-\* (multi-container) | 3000 | backend, frontend | PostgreSQL, Redis, MinIO | data |  
| n8n | n8n | 5678 | backend, frontend | PostgreSQL | data |  
| Open WebUI | open-webui | 8080 | frontend | Ollama | data |  
| Flowise | flowise | 3001 | backend, frontend | — | data |  
| AnythingLLM | anythingllm | 3002 | backend, frontend | — | data |  
| OpenClaw | openclaw | 8888 | backend, frontend | Vector DB | data |

\#\#\# Monitoring Services (Optional)

| Service | Container Name | Port | Network(s) | Depends On | Disk |  
|---------|---------------|------|------------|------------|------|  
| Dozzle | dozzle | 9999 | frontend | Docker socket | data |  
| Prometheus | prometheus | 9090 | monitoring, backend | — | data |  
| Grafana | grafana | 3100 | monitoring, frontend | Prometheus | data |

\#\#\# Docker Networks

| Network | Purpose | Services |  
|---------|---------|----------|  
| \`frontend\` | Reverse proxy → application UIs | Caddy, all apps, Grafana, Dozzle |  
| \`backend\` | App → database/API communication | All apps, PostgreSQL, Redis, Vector DB, MinIO, LiteLLM |  
| \`monitoring\` | Metrics collection (optional) | Prometheus, Grafana, exporters |

\---

\#\# 5\. Storage Architecture

\#\#\# Disk Detection Logic (Script 1\)

Boot → detect\_disks() ├── List all block devices (lsblk) ├── Identify OS disk (mounted at /) ├── Find additional EBS volumes │ ├── Found → prompt user to confirm │ │ ├── Already mounted → use existing mount │ │ ├── Not mounted → format ext4, mount at /mnt/data, add to fstab │ │ └── Multiple found → user selects one │ └── Not found → use /mnt/data on OS disk (mkdir) └── Set DATA\_DISK=/mnt/data

\#\#\# Volume Mapping Principle

\- \*\*OS Disk (\`\~/AIPlatformAutomation/\`)\*\*: Git repo, scripts, templates, logs  
\- \*\*Data Disk (\`/mnt/data/\`)\*\*: All Docker volumes, model files, synced data, backups, secrets  
\- \*\*Rationale\*\*: OS disk can be rebuilt from Git; data disk holds state

\#\#\# fstab Entry (if separate EBS)

/dev/xvdf /mnt/data ext4 defaults,nofail 0 2

The \`nofail\` flag ensures the instance boots even if the EBS volume is detached.

\---

\#\# 6\. Network & Access Architecture

\#\#\# Access Model: Tailscale-Only

Internet ──X──► EC2 (no public ports) │ Tailscale Network ──► EC2 Tailscale IP (100.x.y.z) │ ▼ Caddy :443 ──► services

\*\*No UFW.\*\* Firewall is handled by:  
1\. \*\*EC2 Security Group\*\* — allow only Tailscale UDP (port 41641\) \+ SSH from Tailscale  
2\. \*\*Tailscale ACLs\*\* — control which users/devices reach which ports  
3\. \*\*Docker network isolation\*\* — services only see networks they're attached to

\#\#\# Tailscale Setup (Script 1\)

install\_tailscale() ├── curl \-fsSL [https://tailscale.com/install.sh](https://tailscale.com/install.sh) | sh ├── Prompt for auth key (or use TAILSCALE\_AUTH\_KEY env var) ├── tailscale up \--authkey=$key \--hostname=ai-platform ├── Wait for connection (poll tailscale status) ├── Retrieve Tailscale IP: tailscale ip \-4 ├── Store TAILSCALE\_IP in master.env └── Verify: tailscale status shows "authenticated"

\#\#\# DNS Strategy

| Method | URL Pattern | How |  
|--------|-------------|-----|  
| Tailscale MagicDNS | \`ai-platform.tail-net:port\` | Automatic |  
| Custom domain | \`\*.ai.datasquiz.net\` | DNS CNAME → Tailscale IP, Caddy handles TLS |

The \`$DOMAIN\_NAME\` variable (default: \`ai.datasquiz.net\`) is set interactively in Script 1 and used by Script 2 to generate reverse proxy config.

Subdomains generated:  
\- \`dify.ai.datasquiz.net\`  
\- \`n8n.ai.datasquiz.net\`  
\- \`chat.ai.datasquiz.net\` (Open WebUI)  
\- \`flowise.ai.datasquiz.net\`  
\- \`anythingllm.ai.datasquiz.net\`  
\- \`openclaw.ai.datasquiz.net\`  
\- \`minio.ai.datasquiz.net\`  
\- \`grafana.ai.datasquiz.net\` (optional)  
\- \`dozzle.ai.datasquiz.net\`  
\- \`litellm.ai.datasquiz.net\`  
\---

\#\# 7\. LLM Models — Local (Ollama)

\#\#\# Installation Method

Ollama runs as a \*\*native systemd service\*\* (NOT in Docker) for direct GPU passthrough.

install\_ollama() ├── curl \-fsSL [https://ollama.com/install.sh](https://ollama.com/install.sh) | sh ├── Create override: /etc/systemd/system/ollama.service.d/override.conf │ \[Service\] │ Environment="OLLAMA\_HOST=0.0.0.0:11434" │ Environment="OLLAMA\_MODELS=/mnt/data/ollama/models" ├── systemctl daemon-reload ├── systemctl enable \--now ollama ├── Wait for health: curl \-s [http://localhost:11434/api/version](http://localhost:11434/api/version) └── Store OLLAMA\_BASE\_URL=[http://host.docker.internal:11434](http://host.docker.internal:11434) in master.env

\#\#\# Model Categories

| Category | Models | Size Range | Use Case |  
|----------|--------|------------|----------|  
| Lightweight | tinyllama, phi3:mini, gemma2:2b | 1–3 GB | Testing, quick inference |  
| Midrange | mistral, llama3.1:8b, codellama:7b | 4–8 GB | General chat, code assist |  
| Heavy | llama3.1:70b, deepseek-coder-v2, mixtral:8x7b | 20–50 GB | Complex reasoning, RAG |  
| Embedding | nomic-embed-text, mxbai-embed-large | 0.3–1 GB | Vector DB ingestion |

\#\#\# Model Pull Strategy (Script 2\)

pull\_ollama\_models() ├── Read MODEL\_TIER from master.env (set interactively in Script 1\) │ TIER=minimal → tinyllama, nomic-embed-text │ TIER=standard → above \+ mistral, llama3.1:8b, codellama:7b │ TIER=full → above \+ llama3.1:70b, mixtral:8x7b, deepseek-coder-v2 ├── Check available disk: df \-BG /mnt/data | awk 'NR==2{print $4}' │ If \<50GB remaining, warn and skip heavy models ├── For each model: │ ├── Check if already present: ollama list | grep $model │ ├── If missing: ollama pull $model │ ├── Verify: ollama list | grep $model │ └── Log result to $LOG\_DIR/ollama-pulls.log └── Generate $CONFIG\_DIR/ollama-models.json (consumed by LiteLLM)

\#\#\# Model Storage

/mnt/data/ollama/ └── models/ ├── manifests/ │ └── registry.ollama.ai/ │ └── library/ │ ├── mistral/ │ ├── llama3.1/ │ ├── nomic-embed-text/ │ └── ... └── blobs/ ├── sha256-xxxxxx (model weights) └── ...

All models live on the EBS data volume. Instance stop/start preserves them. Instance terminate loses them unless EBS is set to persist.

\---

\#\# 8\. LLM Models — External (Cloud APIs)

\#\#\# Supported Providers

| Provider | Env Variable | Models Available | Cost Model |  
|----------|-------------|------------------|------------|  
| OpenAI | OPENAI\_API\_KEY | gpt-4o, gpt-4o-mini, gpt-4-turbo, o1, o1-mini | Per-token |  
| Anthropic | ANTHROPIC\_API\_KEY | claude-sonnet-4, claude-3.5-haiku, opus | Per-token |  
| Google | GOOGLE\_API\_KEY | gemini-2.5-pro, gemini-2.5-flash | Per-token (free tier available) |  
| Mistral | MISTRAL\_API\_KEY | mistral-large, mistral-medium, codestral | Per-token |  
| Groq | GROQ\_API\_KEY | llama-3.1-70b, mixtral-8x7b (fast inference) | Per-token (free tier) |  
| OpenRouter | OPENROUTER\_API\_KEY | 200+ models via single key | Per-token (markup) |  
| AWS Bedrock | AWS\_ACCESS\_KEY\_ID \+ AWS\_SECRET\_ACCESS\_KEY | claude, titan, llama via AWS | Per-token |

\#\#\# Key Collection (Script 1\)

collect\_api\_keys() ├── echo "Enter API keys (press Enter to skip any):" ├── For each provider: │ ├── read \-sp " $PROVIDER API key: " key │ ├── If non-empty: │ │ ├── Validate format (basic regex per provider) │ │ ├── Write to master.env: ${PROVIDER}\_API\_KEY=$key │ │ └── Add provider to ENABLED\_CLOUD\_PROVIDERS list │ └── If empty: skip (log "Skipped $PROVIDER") ├── At least one of: local Ollama OR one cloud key must be set │ Otherwise: error "No LLM backend configured" └── Write ENABLED\_CLOUD\_PROVIDERS to master.env

\#\#\# Security

\- Keys stored in \`master.env\` with \`chmod 600\`  
\- Docker services receive keys via \`env\_file:\` directive (never baked into images)  
\- \`master.env\` is in \`.gitignore\` — never committed  
\- Backup: keys are included in encrypted config backup (Section 16\)

\---

\#\# 9\. LiteLLM Routing Strategy

\#\#\# Purpose

LiteLLM provides a \*\*single OpenAI-compatible endpoint\*\* that routes to any backend — local Ollama models, OpenAI, Anthropic, etc. Every service on the platform points to LiteLLM instead of directly to individual providers.

\#\#\# Architecture

┌─────────────┐ │ Dify │──┐ │ n8n │──┤ │ Open WebUI│──┼──► [http://litellm:4000/v1](http://litellm:4000/v1) ──► Router │ Flowise │──┤ │ │ AnythingLLM──┘ │ │ OpenClaw │──┘ ▼ ┌──────────────┐ │ Model Map │ ├──────────────┤ │ gpt-4o → OpenAI API │ │ claude-sonnet → Anthropic API │ │ mistral → ollama/mistral │ │ llama3.1 → ollama/llama3.1:8b │ │ embed → ollama/nomic-embed-text │ └──────────────┘

\#\#\# Configuration File Generation (Script 2\)

generate\_litellm\_config() ├── Source master.env ├── Start config YAML: │ model\_list: \[\] │ general\_settings: │ master\_key: $ LITELLM\_MASTER\_KEY │ database\_url: postgresql:// $ POSTGRES\_USER:$POSTGRES\_PASSWORD@postgres:5432/litellm │ ├── Add Ollama models (from ollama-models.json): │ For each model in ollama list: │ \- model\_name: $ friendly\_name │ litellm\_params: │ model: ollama/ $ model\_tag │ api\_base: [http://host.docker.internal:11434](http://host.docker.internal:11434) │ ├── Add cloud models (from ENABLED\_CLOUD\_PROVIDERS): │ If OPENAI\_API\_KEY set: │ \- model\_name: gpt-4o │ litellm\_params: │ model: openai/gpt-4o │ api\_key: os.environ/OPENAI\_API\_KEY │ \- model\_name: gpt-4o-mini │ ... │ If ANTHROPIC\_API\_KEY set: │ \- model\_name: claude-sonnet │ litellm\_params: │ model: anthropic/claude-sonnet-4 │ api\_key: os.environ/ANTHROPIC\_API\_KEY │ ... (repeat per provider) │ ├── Add embedding models: │ \- model\_name: text-embedding │ litellm\_params: │ model: ollama/nomic-embed-text │ api\_base: [http://host.docker.internal:11434](http://host.docker.internal:11434) │ ├── Add router settings: │ router\_settings: │ routing\_strategy: least-busy │ num\_retries: 3 │ timeout: 120 │ fallbacks: │ \- gpt-4o: \[claude-sonnet, llama3.1\] │ \- claude-sonnet: \[gpt-4o, mistral\] │ └── Write to $CONFIG\_DIR/litellm/config.yaml

\#\#\# Docker Compose Block

\`\`\`yaml  
litellm:  
  image: ghcr.io/berriai/litellm:main-latest  
  container\_name: litellm  
  restart: unless-stopped  
  ports:  
    \- "127.0.0.1:4000:4000"  
  volumes:  
    \- ${CONFIG\_DIR}/litellm/config.yaml:/app/config.yaml:ro  
  env\_file:  
    \- ${ENV\_DIR}/master.env  
  environment:  
    \- LITELLM\_MASTER\_KEY=${LITELLM\_MASTER\_KEY}  
    \- DATABASE\_URL=postgresql://${POSTGRES\_USER}:${POSTGRES\_PASSWORD}@postgres:5432/litellm  
    \- LITELLM\_LOG\_LEVEL=INFO  
  extra\_hosts:  
    \- "host.docker.internal:host-gateway"  
  networks:  
    \- backend  
    \- db-network  
  depends\_on:  
    postgres:  
      condition: service\_healthy  
  healthcheck:  
    test: \["CMD", "curl", "-f", "http://localhost:4000/health"\]  
    interval: 30s  
    timeout: 10s  
    retries: 5

### **How Services Connect**

Each service is configured to use LiteLLM as its OpenAI-compatible backend:

Copy table

| Service | Configuration Setting | Value |
| ----- | ----- | ----- |
| Dify | Custom Model Provider → OpenAI-compatible | `http://litellm:4000/v1` \+ master key |
| n8n | OpenAI credentials node | Base URL: `http://litellm:4000/v1` |
| Open WebUI | Settings → Connections → OpenAI | `http://litellm:4000/v1` |
| Flowise | ChatOpenAI node | Base URL: `http://litellm:4000/v1` |
| AnythingLLM | LLM Provider → Generic OpenAI | `http://litellm:4000/v1` |
| OpenClaw | Provider config | `http://litellm:4000/v1` |

---

## **10\. Vector Database — Fluid Selection & OpenClaw Integration**

### **Design Principle**

The platform does **not** hardcode a single vector DB. The user selects during Script 1, and Script 2 deploys accordingly. All services that need vector search are configured to point at whichever was chosen.

### **Supported Options**

Copy table

| Option | Image | Port | Strength | When to Choose |
| ----- | ----- | ----- | ----- | ----- |
| Qdrant | qdrant/qdrant:latest | 6333 | Rust-fast, rich filtering, REST+gRPC | Default recommendation. Best all-around. |
| Weaviate | semitechnologies/weaviate:latest | 8080 | GraphQL, multi-modal, auto-vectorize | If you want schema-based search |
| Milvus | milvusdb/milvus:latest | 19530 | Massive scale, GPU index | If dataset \>10M vectors |
| ChromaDB | chromadb/chroma:latest | 8000 | Dead simple, Python-native | Quick prototyping, small datasets |
| pgvector | (extension on Postgres) | 5432 | No extra service, SQL-native | Minimize containers, moderate scale |

### **Selection Flow (Script 1\)**

select\_vector\_db()  
  ├── echo "Select vector database:"  
  ├── echo "  1\) Qdrant     (recommended — fast, production-ready)"  
  ├── echo "  2\) Weaviate   (GraphQL, auto-vectorization)"  
  ├── echo "  3\) Milvus     (massive scale)"  
  ├── echo "  4\) ChromaDB   (simple, lightweight)"  
  ├── echo "  5\) pgvector   (PostgreSQL extension, no extra container)"  
  ├── read \-p "Choice \[1\]: " choice  
  ├── Set VECTOR\_DB=qdrant|weaviate|milvus|chromadb|pgvector  
  ├── Write to master.env  
  └── If pgvector: set flag PGVECTOR\_ENABLED=true (handled in postgres setup)

### **Docker Compose Blocks (Script 2 generates based on selection)**

**Qdrant:**

qdrant:  
  image: qdrant/qdrant:latest  
  container\_name: qdrant  
  restart: unless-stopped  
  ports:  
    \- "127.0.0.1:6333:6333"  
    \- "127.0.0.1:6334:6334"  
  volumes:  
    \- ${DATA\_DIR}/qdrant/storage:/qdrant/storage  
    \- ${DATA\_DIR}/qdrant/snapshots:/qdrant/snapshots  
  environment:  
    \- QDRANT\_\_SERVICE\_\_API\_KEY=${QDRANT\_API\_KEY}  
  networks:  
    \- backend  
  healthcheck:  
    test: \["CMD", "curl", "-f", "http://localhost:6333/readyz"\]  
    interval: 30s  
    timeout: 10s  
    retries: 5

**Weaviate:**

weaviate:  
  image: semitechnologies/weaviate:latest  
  container\_name: weaviate  
  restart: unless-stopped  
  ports:  
    \- "127.0.0.1:8080:8080"  
  volumes:  
    \- ${DATA\_DIR}/weaviate:/var/lib/weaviate  
  environment:  
    \- QUERY\_DEFAULTS\_LIMIT=25  
    \- AUTHENTICATION\_APIKEY\_ENABLED=true  
    \- AUTHENTICATION\_APIKEY\_ALLOWED\_KEYS=${WEAVIATE\_API\_KEY}  
    \- PERSISTENCE\_DATA\_PATH=/var/lib/weaviate  
    \- DEFAULT\_VECTORIZER\_MODULE=none  
    \- CLUSTER\_HOSTNAME=node1  
  networks:  
    \- backend  
  healthcheck:  
    test: \["CMD", "curl", "-f", "http://localhost:8080/v1/.well-known/ready"\]  
    interval: 30s  
    timeout: 10s  
    retries: 5

**Milvus:**

milvus-etcd:  
  image: quay.io/coreos/etcd:v3.5.11  
  container\_name: milvus-etcd  
  restart: unless-stopped  
  environment:  
    \- ETCD\_AUTO\_COMPACTION\_MODE=revision  
    \- ETCD\_AUTO\_COMPACTION\_RETENTION=1000  
    \- ETCD\_QUOTA\_BACKEND\_BYTES=4294967296  
    \- ETCD\_SNAPSHOT\_COUNT=50000  
  volumes:  
    \- ${DATA\_DIR}/milvus/etcd:/etcd  
  command: etcd \-advertise-client-urls=http://127.0.0.1:2379 \-listen-client-urls http://0.0.0.0:2379 \--data-dir /etcd  
  networks:  
    \- backend

milvus-minio:  
  image: minio/minio:latest  
  container\_name: milvus-minio  
  restart: unless-stopped  
  environment:  
    \- MINIO\_ACCESS\_KEY=${MINIO\_ACCESS\_KEY}  
    \- MINIO\_SECRET\_KEY=${MINIO\_SECRET\_KEY}  
  volumes:  
    \- ${DATA\_DIR}/milvus/minio:/minio\_data  
  command: minio server /minio\_data \--console-address ":9001"  
  networks:  
    \- backend

milvus:  
  image: milvusdb/milvus:latest  
  container\_name: milvus  
  restart: unless-stopped  
  ports:  
    \- "127.0.0.1:19530:19530"  
    \- "127.0.0.1:9091:9091"  
  volumes:  
    \- ${DATA\_DIR}/milvus/data:/var/lib/milvus  
  environment:  
    \- ETCD\_ENDPOINTS=milvus-etcd:2379  
    \- MINIO\_ADDRESS=milvus-minio:9000  
  depends\_on:  
    \- milvus-etcd  
    \- milvus-minio  
  networks:  
    \- backend  
  healthcheck:  
    test: \["CMD", "curl", "-f", "http://localhost:9091/healthz"\]  
    interval: 30s  
    timeout: 10s  
    retries: 5

**ChromaDB:**

chromadb:  
  image: chromadb/chroma:latest  
  container\_name: chromadb  
  restart: unless-stopped  
  ports:  
    \- "127.0.0.1:8000:8000"  
  volumes:  
    \- ${DATA\_DIR}/chromadb:/chroma/chroma  
  environment:  
    \- CHROMA\_SERVER\_AUTH\_CREDENTIALS=${CHROMA\_API\_KEY}  
    \- CHROMA\_SERVER\_AUTH\_PROVIDER=chromadb.auth.token.TokenAuthServerProvider  
    \- IS\_PERSISTENT=TRUE  
    \- ANONYMIZED\_TELEMETRY=FALSE  
  networks:  
    \- backend  
  healthcheck:  
    test: \["CMD", "curl", "-f", "http://localhost:8000/api/v1/heartbeat"\]  
    interval: 30s  
    timeout: 10s  
    retries: 5

**pgvector (extension on existing Postgres):**

No separate container. During postgres init:  
  CREATE EXTENSION IF NOT EXISTS vector;  
  CREATE EXTENSION IF NOT EXISTS pg\_trgm;

### **Service ↔ Vector DB Wiring**

Script 3 configures each service based on `$VECTOR_DB`:

Copy table

| Service | Qdrant Config | Weaviate Config | ChromaDB Config | pgvector Config |
| ----- | ----- | ----- | ----- | ----- |
| Dify | VECTOR\_STORE=qdrant, QDRANT\_URL=[http://qdrant:6333](http://qdrant:6333) | VECTOR\_STORE=weaviate, WEAVIATE\_ENDPOINT=[http://weaviate:8080](http://weaviate:8080) | VECTOR\_STORE=chroma, CHROMA\_HOST=chromadb | VECTOR\_STORE=pgvector (uses internal pg) |
| AnythingLLM | Vector DB → Qdrant, URL=[http://qdrant:6333](http://qdrant:6333) | Vector DB → Weaviate | Vector DB → Chroma | Vector DB → pgvector |
| Flowise | Qdrant node | Weaviate node | Chroma node | pgvector node |
| OpenClaw | vectordb.type=qdrant | vectordb.type=weaviate | vectordb.type=chroma | vectordb.type=pgvector |

### **OpenClaw Integration Note**

OpenClaw connects to whichever vector DB is deployed. Its config is templated:

\# $CONFIG\_DIR/openclaw/config.yaml (generated by Script 3\)  
llm:  
  provider: openai-compatible  
  base\_url: http://litellm:4000/v1  
  api\_key: ${LITELLM\_MASTER\_KEY}

vectordb:  
  type: ${VECTOR\_DB}          \# qdrant | weaviate | chromadb | pgvector | milvus  
  host: ${VECTOR\_DB\_HOST}     \# resolved from VECTOR\_DB selection  
  port: ${VECTOR\_DB\_PORT}     \# resolved from VECTOR\_DB selection  
  api\_key: ${VECTOR\_DB\_KEY}   \# resolved from VECTOR\_DB selection

embedding:  
  model: text-embedding  
  base\_url: http://litellm:4000/v1

---

## **11\. Google Drive Rsync — Authentication & Embedding Pipeline**

### **Purpose**

Sync documents from Google Drive to `/mnt/data/gdrive/` on the EC2 instance, then feed them into the vector database for RAG (Retrieval-Augmented Generation) across all platform services.

### **Tool: rclone**

rclone is the standard tool for Google Drive ↔ Linux sync. Installed in Script 1\.

### **Installation (Script 1\)**

install\_rclone()  
  ├── curl https://rclone.org/install.sh | bash  
  ├── Verify: rclone version  
  ├── Create dirs:  
  │     mkdir \-p /mnt/data/gdrive  
  │     mkdir \-p $CONFIG\_DIR/rclone  
  └── Log: "rclone installed — configure with 'rclone config' or provide rclone.conf"

### **Authentication Options**

**Option A: Interactive (recommended for first setup)**

rclone config  
  ├── n (new remote)  
  ├── name: gdrive  
  ├── storage: drive (Google Drive)  
  ├── client\_id: (leave blank for default, or use own OAuth app)  
  ├── client\_secret: (leave blank for default)  
  ├── scope: drive.readonly  
  ├── root\_folder\_id: (blank \= entire drive, or specific folder ID)  
  ├── service\_account\_file: (blank unless using service account)  
  └── Auto config:   
        If headless (EC2): n → gives URL to visit on local machine  
        Visit URL → authorize → paste code back into terminal

**Option B: Service Account (recommended for automation)**

setup\_gdrive\_service\_account()  
  ├── Requires: Google Cloud project \+ service account JSON key  
  ├── Place key at: $CONFIG\_DIR/rclone/gdrive-service-account.json  
  ├── Generate rclone.conf:  
  │     \[gdrive\]  
  │     type \= drive  
  │     scope \= drive.readonly  
  │     service\_account\_file \= /opt/ai-platform/config/rclone/gdrive-service-account.json  
  │     team\_drive \=           (blank unless using Shared Drive)  
  ├── Write to  $ CONFIG\_DIR/rclone/rclone.conf  
  └── Test: rclone lsd gdrive: \--config= $ CONFIG\_DIR/rclone/rclone.conf

**Option C: Pre-existing rclone.conf**

If  $ CONFIG\_DIR/rclone/rclone.conf already exists:  
  ├── Validate: rclone lsd gdrive: \--config= $ CONFIG\_DIR/rclone/rclone.conf  
  ├── If valid: skip auth setup  
  └── If invalid: prompt for re-auth

### **Sync Configuration (Script 3\)**

configure\_gdrive\_sync()  
  ├── Read GDRIVE\_SYNC\_ENABLED from master.env (set in Script 1\)  
  ├── If disabled: skip entirely  
  ├── Read GDRIVE\_FOLDERS from master.env  
  │     Default: "" (sync entire drive)  
  │     Or comma-separated: "Documents/AI,Projects/RAG-data,Research"  
  │  
  ├── Generate sync script: /opt/ai-platform/scripts/sync-gdrive.sh  
  │     \#\!/bin/bash  
  │     RCLONE\_CONF=/opt/ai-platform/config/rclone/rclone.conf  
  │     DEST=/mnt/data/gdrive  
  │     LOG=/var/log/ai-platform/gdrive-sync.log  
  │       
  │     echo "\[$(date)\] Starting Google Drive sync" \>\>  $ LOG  
  │       
  │     if \[ \-z " $ GDRIVE\_FOLDERS" \]; then  
  │       rclone sync gdrive:  $ DEST \\  
  │         \--config= $ RCLONE\_CONF \\  
  │         \--transfers=4 \\  
  │         \--checkers=8 \\  
  │         \--log-file= $ LOG \\  
  │         \--log-level=INFO \\  
  │         \--exclude=".Trash-\*/\*\*" \\  
  │         \--exclude="\*.tmp" \\  
  │         \--max-size=100M \\  
  │         \--drive-acknowledge-abuse  
  │     else  
  │       IFS=',' read \-ra FOLDERS \<\<\< " $ GDRIVE\_FOLDERS"  
  │       for folder in "${FOLDERS\[@\]}"; do  
  │         folder= $ (echo " $ folder" | xargs)  \# trim whitespace  
  │         rclone sync "gdrive: $ folder" " $ DEST/ $ folder" \\  
  │           \--config= $ RCLONE\_CONF \\  
  │           \--transfers=4 \\  
  │           \--checkers=8 \\  
  │           \--log-file= $ LOG \\  
  │           \--log-level=INFO \\  
  │           \--max-size=100M \\  
  │           \--drive-acknowledge-abuse  
  │       done  
  │     fi  
  │       
  │     echo "\[ $ (date)\] Sync complete. Files:" \>\> $LOG  
  │     find $DEST \-type f | wc \-l \>\>  $ LOG  
  │       
  │     \# Trigger embedding pipeline if configured  
  │     if \[ " $ AUTO\_EMBED\_AFTER\_SYNC" \= "true" \]; then  
  │       /opt/ai-platform/scripts/embed-documents.sh  
  │     fi  
  │  
  ├── chmod \+x /opt/ai-platform/scripts/sync-gdrive.sh  
  │  
  ├── Create systemd timer for scheduled sync:  
  │     /etc/systemd/system/gdrive-sync.service  
  │       \[Unit\]  
  │       Description=Google Drive Sync  
  │       \[Service\]  
  │       Type=oneshot  
  │       ExecStart=/opt/ai-platform/scripts/sync-gdrive.sh  
  │       User=root  
  │       EnvironmentFile=/opt/ai-platform/env/master.env  
  │  
  │     /etc/systemd/system/gdrive-sync.timer  
  │       \[Unit\]  
  │       Description=Google Drive Sync Timer  
  │       \[Timer\]  
  │       OnCalendar=\*-\*-\* 02:00:00    \# Daily at 2 AM  
  │       Persistent=true  
  │       \[Install\]  
  │       WantedBy=timers.target  
  │  
  ├── systemctl daemon-reload  
  ├── systemctl enable \--now gdrive-sync.timer  
  └── Run initial sync: systemctl start gdrive-sync.service

### **Embedding Pipeline**

After sync, documents need to be vectorized and inserted into the selected vector DB.

generate\_embed\_script()  
  ├── Generate /opt/ai-platform/scripts/embed-documents.sh:  
  │  
  │     \#\!/bin/bash  
  │     source /opt/ai-platform/env/master.env  
  │       
  │     GDRIVE\_DIR=/mnt/data/gdrive  
  │     PROCESSED\_LOG=/mnt/data/gdrive/.processed\_files  
  │     LOG=/var/log/ai-platform/embedding.log  
  │       
  │     touch  $ PROCESSED\_LOG  
  │       
  │     echo "\[ $ (date)\] Starting embedding pipeline" \>\> $LOG  
  │       
  │     \# Find new/modified files since last run  
  │     find $GDRIVE\_DIR \-type f \\  
  │       $  \-name "\*.pdf" \-o \-name "\*.txt" \-o \-name "\*.md" \\  │          \-o \-name "\*.docx" \-o \-name "\*.csv" \-o \-name "\*.json" \\  │          \-o \-name "\*.html" \-o \-name "\*.epub"  $  \\  
  │       \-newer  $ PROCESSED\_LOG \\  
  │       \> /tmp/files\_to\_embed.txt  
  │       
  │     FILE\_COUNT= $ (wc \-l \< /tmp/files\_to\_embed.txt)  
  │     echo "\[$(date)\] Found $FILE\_COUNT new/modified files" \>\>  $ LOG  
  │       
  │     if \[ " $ FILE\_COUNT" \-eq 0 \]; then  
  │       echo "\[$(date)\] No new files to embed" \>\>  $ LOG  
  │       exit 0  
  │     fi  
  │       
  │     \# Method depends on which services are running:  
  │     \# Priority: Dify API \> AnythingLLM API \> Direct script  
  │       
  │     if docker ps \--format '{{.Names}}' | grep \-q "^dify-api $ "; then  
  │       \# Use Dify's document API  
  │       echo "\[$(date)\] Embedding via Dify API" \>\>  $ LOG  
  │       while IFS= read \-r file; do  
  │         curl \-s \-X POST "http://localhost:5001/v1/datasets/ $ {DIFY\_KNOWLEDGE\_DATASET\_ID}/document/create\_by\_file" \\  
  │           \-H "Authorization: Bearer ${DIFY\_API\_KEY}" \\  
  │           \-F "file=@$file" \\  
  │           \-F 'data={"indexing\_technique":"high\_quality","process\_rule":{"mode":"automatic"}}' \\  
  │           \>\>  $ LOG 2\>&1  
  │       done \< /tmp/files\_to\_embed.txt  
  │       
  │     elif docker ps \--format '{{.Names}}' | grep \-q "^anythingllm $ "; then  
  │       \# Use AnythingLLM's document API  
  │       echo "\[$(date)\] Embedding via AnythingLLM API" \>\> $LOG  
  │       while IFS= read \-r file; do  
  │         curl \-s \-X POST "http://localhost:3001/api/v1/document/upload" \\  
  │           \-H "Authorization: Bearer ${ANYTHINGLLM\_API\_KEY}" \\  
  │           \-F "file=@$file" \\  
  │           \>\>  $ LOG 2\>&1  
  │       done \< /tmp/files\_to\_embed.txt  
  │       
  │     else  
  │       \# Direct embedding via LiteLLM \+ vector DB API  
  │       echo "\[ $ (date)\] Direct embedding via LiteLLM → ${VECTOR\_DB}" \>\> $LOG  
  │       python3 /opt/ai-platform/scripts/direct-embed.py \\  
  │         \--files /tmp/files\_to\_embed.txt \\  
  │         \--litellm-url http://localhost:4000/v1 \\  
  │         \--litellm-key $LITELLM\_MASTER\_KEY \\  
  │         \--vector-db $VECTOR\_DB \\  
  │         \--vector-db-url  $ VECTOR\_DB\_HOST: $ VECTOR\_DB\_PORT \\  
  │         \--vector-db-key $VECTOR\_DB\_KEY \\  
  │         \>\> $LOG 2\>&1  
  │     fi  
  │       
  │     \# Update processed timestamp  
  │     touch  $ PROCESSED\_LOG  
  │     echo "\[ $ (date)\] Embedding pipeline complete" \>\> $LOG  
  │  
  └── chmod \+x /opt/ai-platform/scripts/embed-documents.sh

### **Storage Layout**

/mnt/data/gdrive/  
├── .processed\_files              (timestamp marker)  
├── Documents/  
│   └── AI/  
│       ├── research-paper.pdf  
│       ├── meeting-notes.md  
│       └── dataset-docs.txt  
├── Projects/  
│   └── RAG-data/  
│       ├── knowledge-base.json  
│       └── faq.csv  
└── Research/  
    ├── arxiv-papers/  
    └── notes/

### **Manual Operations**

\# Manual sync (immediate)  
sudo systemctl start gdrive-sync.service

\# Manual embed (immediate)    
sudo /opt/ai-platform/scripts/embed-documents.sh

\# Check sync status  
sudo systemctl status gdrive-sync.timer  
sudo journalctl \-u gdrive-sync.service \-f

\# Check last sync log  
tail \-50 /var/log/ai-platform/gdrive-sync.log

\# Check embedding log  
tail \-50 /var/log/ai-platform/embedding.log

\# Re-embed everything (reset processed marker)  
rm /mnt/data/gdrive/.processed\_files  
sudo /opt/ai-platform/scripts/embed-documents.sh

\# List synced files  
find /mnt/data/gdrive \-type f | head \-50  
du \-sh /mnt/data/gdrive

\---

\#\# 12\. Reverse Proxy — Caddy with Auto-SSL

\#\#\# Why Caddy (Not Nginx/Traefik)

\- \*\*Automatic HTTPS\*\* via Let's Encrypt / ZeroSSL — zero config  
\- \*\*Automatic certificate renewal\*\* — no cron jobs  
\- \*\*Single config file\*\* — Caddyfile is human-readable  
\- \*\*HTTP/2 and HTTP/3\*\* out of the box  
\- \*\*On-demand TLS\*\* support for wildcard subdomains

\#\#\# Architecture

Internet │ ▼ ┌──────────────────────────────────────────┐ │ EC2 Security Group │ │ Port 80 (→ Caddy → auto-redirect 443\) │ │ Port 443 (→ Caddy → TLS termination) │ └──────────────┬───────────────────────────┘ │ ▼ ┌──────────────────────────────────────────┐ │ Caddy Container (:80, :443) │ │ │ │ dify.yourdomain.com → dify:80 │ │ n8n.yourdomain.com → n8n:5678 │ │ webui.yourdomain.com → open-webui:8080│ │ flowise.yourdomain.com → flowise:3000 │ │ llm.yourdomain.com → litellm:4000 │ │ grafana.yourdomain.com → grafana:3000 │ │ anything.yourdomain.com → anythingllm:3001│ │ openclaw.yourdomain.com → openclaw:PORT │ │ portainer.yourdomain.com→ portainer:9000 │ │ supertokens.yourdomain.com → supertokens:3567│ │ │ │ If no domain: localhost mode (self-signed)│ └──────────────────────────────────────────┘

\#\#\# Domain Configuration (Script 1\)

configure\_domain() ├── read \-p "Do you have a domain name pointing to this server? (y/n) \[n\]: " has\_domain │ ├── If YES: │ ├── read \-p "Base domain (e.g., ai.example.com): " BASE\_DOMAIN │ ├── read \-p "Email for Let's Encrypt: " ACME\_EMAIL │ ├── Validate domain resolves to this server's public IP: │ │ SERVER\_IP= $ (curl \-s ifconfig.me) │ │ DOMAIN\_IP= (dig+short BASE\_DOMAIN) │ │ If mismatch: warn "Domain does not resolve to this server yet" │ ├── Set DOMAIN\_MODE=production │ ├── Write to master.env: │ │ BASE\_DOMAIN= $ BASE\_DOMAIN │ │ ACME\_EMAIL=$ACME\_EMAIL │ │ DOMAIN\_MODE=production │ └── Generate subdomain map (see below) │ └── If NO: ├── Set DOMAIN\_MODE=local ├── Write to master.env: │ BASE\_DOMAIN=localhost │ DOMAIN\_MODE=local └── Caddy will serve on IP with self-signed certs or HTTP only

\#\#\# Subdomain Map Generation

generate\_subdomain\_map() ├── Read ENABLED\_SERVICES from master.env ├── For each service, assign subdomain: │ DIFY\_DOMAIN=dify.${BASE\_DOMAIN} │ N8N\_DOMAIN=n8n.${BASE\_DOMAIN} │ WEBUI\_DOMAIN=webui.${BASE\_DOMAIN} │ FLOWISE\_DOMAIN=flowise.${BASE\_DOMAIN} │ LITELLM\_DOMAIN=llm.${BASE\_DOMAIN} │ GRAFANA\_DOMAIN=grafana.${BASE\_DOMAIN} │ ANYTHINGLLM\_DOMAIN=anything.${BASE\_DOMAIN} │ OPENCLAW\_DOMAIN=openclaw.${BASE\_DOMAIN} │ PORTAINER\_DOMAIN=portainer.${BASE\_DOMAIN} │ SUPERTOKENS\_DOMAIN=auth.${BASE\_DOMAIN} ├── Write all to master.env └── echo "Configure these DNS records (A or CNAME) pointing to $SERVER\_IP:" For each: echo " $subdomain → $SERVER\_IP"

\#\#\# Caddyfile Generation (Script 2\)

generate\_caddyfile() ├── Source master.env ├── Start Caddyfile: │ │ \# Global options │ { │ email ${ACME\_EMAIL} │ acme\_ca [https://acme-v02.api.letsencrypt.org/directory](https://acme-v02.api.letsencrypt.org/directory) │ \# For local mode: │ \# local\_certs │ } │ ├── If DOMAIN\_MODE=production: │ For each enabled service: │ ${SERVICE\_DOMAIN} { │ reverse\_proxy ${service\_container}:${service\_port} │ encode gzip │ header { │ Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" │ X-Content-Type-Options "nosniff" │ X-Frame-Options "SAMEORIGIN" │ Referrer-Policy "strict-origin-when-cross-origin" │ } │ log { │ output file /var/log/caddy/${service}.log { │ roll\_size 10mb │ roll\_keep 5 │ } │ } │ } │ ├── If DOMAIN\_MODE=local: │ :80 { │ \# Landing page with links to all services │ respond "AI Platform Running. Services available at localhost:PORT" │ } │ For each enabled service: │ :${external\_port} { │ reverse\_proxy ${service\_container}:${service\_port} │ } │ ├── Add special handling for WebSocket services: │ \# n8n needs WebSocket for workflow editor │ ${N8N\_DOMAIN} { │ reverse\_proxy n8n:5678 { │ header\_up X-Forwarded-Proto {scheme} │ } │ } │ \# Open WebUI uses WebSocket │ ${WEBUI\_DOMAIN} { │ reverse\_proxy open-webui:8080 { │ header\_up Connection {\>Connection} │ header\_up Upgrade {\>Upgrade} │ } │ } │ └── Write to $CONFIG\_DIR/caddy/Caddyfile

\#\#\# Docker Compose Block

\`\`\`yaml  
caddy:  
  image: caddy:2-alpine  
  container\_name: caddy  
  restart: unless-stopped  
  ports:  
    \- "80:80"  
    \- "443:443"  
    \- "443:443/udp"   \# HTTP/3  
  volumes:  
    \- ${CONFIG\_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro  
    \- ${DATA\_DIR}/caddy/data:/data          \# TLS certificates  
    \- ${DATA\_DIR}/caddy/config:/config      \# Caddy config state  
    \- ${LOG\_DIR}/caddy:/var/log/caddy       \# Access logs  
  environment:  
    \- ACME\_EMAIL=${ACME\_EMAIL}  
  networks:  
    \- frontend  
    \- backend  
  healthcheck:  
    test: \["CMD", "caddy", "validate", "--config", "/etc/caddy/Caddyfile"\]  
    interval: 60s  
    timeout: 10s  
    retries: 3

### **Local Mode Port Map (no domain)**

When DOMAIN\_MODE=local, services are accessed directly via IP:port:

Copy table

| Service | URL |
| ----- | ----- |
| Dify | [http://SERVER\_IP:3000](http://SERVER_IP:3000) |
| n8n | [http://SERVER\_IP:5678](http://SERVER_IP:5678) |
| Open WebUI | [http://SERVER\_IP:8080](http://SERVER_IP:8080) |
| Flowise | [http://SERVER\_IP:3001](http://SERVER_IP:3001) |
| LiteLLM | [http://SERVER\_IP:4000](http://SERVER_IP:4000) |
| Grafana | [http://SERVER\_IP:3002](http://SERVER_IP:3002) |
| Portainer | [http://SERVER\_IP:9000](http://SERVER_IP:9000) |
| AnythingLLM | [http://SERVER\_IP:3003](http://SERVER_IP:3003) |
| OpenClaw | [http://SERVER\_IP:3004](http://SERVER_IP:3004) |

Note: In local mode, ports are mapped to `0.0.0.0:PORT` instead of `127.0.0.1:PORT` since there's no reverse proxy handling external access. Security group still controls access.

---

## **13\. Monitoring Stack — Prometheus, Grafana, cAdvisor, node\_exporter**

### **Purpose**

Full observability of the platform: container health, system resources, GPU utilization, service response times, cost tracking (via LiteLLM), and alerting.

### **Architecture**

┌─────────────────────────────────────────────────────┐  
│                    Grafana                           │  
│              (Dashboards & Alerts)                   │  
│    ┌──────────┬──────────┬──────────┬──────────┐    │  
│    │System    │Docker    │GPU      │LLM Cost  │    │  
│    │Dashboard │Dashboard │Dashboard│Dashboard │    │  
│    └────┬─────┴────┬─────┴────┬────┴────┬─────┘    │  
│         │          │          │         │           │  
│         ▼          ▼          ▼         ▼           │  
│    ┌─────────────────────────────────────────┐      │  
│    │           Prometheus                     │      │  
│    │    (Scrape → Store → Query)              │      │  
│    │    Retention: 30 days                    │      │  
│    └────┬─────┬──────┬──────┬──────┬────────┘      │  
│         │     │      │      │      │                │  
└─────────┼─────┼──────┼──────┼──────┼────────────────┘  
          │     │      │      │      │  
          ▼     ▼      ▼      ▼      ▼  
       node\_  cAdvisor nvidia  litellm  caddy  
       export          dcgm   /metrics  /metrics  
       er               export  
                        er

### **Components**

Copy table

| Component | Image | Purpose | Port |
| ----- | ----- | ----- | ----- |
| Prometheus | prom/prometheus:latest | Time-series metrics store | 9090 |
| Grafana | grafana/grafana:latest | Visualization & alerts | 3002 |
| node\_exporter | prom/node-exporter:latest | Host CPU/RAM/disk/network | 9100 |
| cAdvisor | gcr.io/cadvisor/cadvisor:latest | Per-container metrics | 9080 |
| dcgm-exporter | nvcr.io/nvidia/k8s/dcgm-exporter:latest | GPU metrics (if GPU instance) | 9400 |

### **Prometheus Configuration (Script 2\)**

generate\_prometheus\_config()  
  ├── Create $CONFIG\_DIR/prometheus/prometheus.yml:  
  │  
  │   global:  
  │     scrape\_interval: 15s  
  │     evaluation\_interval: 15s  
  │     scrape\_timeout: 10s  
  │  
  │   rule\_files:  
  │     \- /etc/prometheus/alert\_rules.yml  
  │  
  │   alerting:  
  │     alertmanagers:  
  │       \- static\_configs:  
  │           \- targets: \[\]   \# Add alertmanager if needed  
  │  
  │   scrape\_configs:  
  │     \- job\_name: 'prometheus'  
  │       static\_configs:  
  │         \- targets: \['localhost:9090'\]  
  │  
  │     \- job\_name: 'node'  
  │       static\_configs:  
  │         \- targets: \['node-exporter:9100'\]  
  │  
  │     \- job\_name: 'cadvisor'  
  │       static\_configs:  
  │         \- targets: \['cadvisor:8080'\]  
  │  
  │     \- job\_name: 'litellm'  
  │       metrics\_path: /metrics  
  │       static\_configs:  
  │         \- targets: \['litellm:4000'\]  
  │  
  │     \- job\_name: 'caddy'  
  │       static\_configs:  
  │         \- targets: \['caddy:2019'\]   \# Caddy admin API  
  │  
  │   \# Conditional: only if GPU instance  
  │     \- job\_name: 'gpu'  
  │       static\_configs:  
  │         \- targets: \['dcgm-exporter:9400'\]  
  │  
  ├── Create $CONFIG\_DIR/prometheus/alert\_rules.yml:  
  │  
  │   groups:  
  │     \- name: platform\_alerts  
  │       rules:  
  │         \- alert: HighCPUUsage  
  │           expr: 100 \- (avg by(instance) (irate(node\_cpu\_seconds\_total{mode="idle"}\[5m\])) \* 100\) \> 85  
  │           for: 5m  
  │           labels:  
  │             severity: warning  
  │           annotations:  
  │             summary: "High CPU usage detected ({{ $value }}%)"  
  │  
  │         \- alert: HighMemoryUsage  
  │           expr: (1 \- node\_memory\_MemAvailable\_bytes / node\_memory\_MemTotal\_bytes) \* 100 \> 90  
  │           for: 5m  
  │           labels:  
  │             severity: critical  
  │           annotations:  
  │             summary: "Memory usage above 90% ({{ $value }}%)"  
  │  
  │         \- alert: DiskSpaceLow  
  │           expr: (1 \- node\_filesystem\_avail\_bytes{mountpoint="/mnt/data"} / node\_filesystem\_size\_bytes{mountpoint="/mnt/data"}) \* 100 \> 85  
  │           for: 10m  
  │           labels:  
  │             severity: warning  
  │           annotations:  
  │             summary: "Disk usage above 85% on /mnt/data"  
  │  
  │         \- alert: ContainerDown  
  │           expr: absent(container\_last\_seen{name=\~"dify-api|n8n|litellm|open-webui"}) \== 1  
  │           for: 2m  
  │           labels:  
  │             severity: critical  
  │           annotations:  
  │             summary: "Container {{ $labels.name }} is down"  
  │  
  │         \- alert: GPUTemperatureHigh  
  │           expr: DCGM\_FI\_DEV\_GPU\_TEMP \> 85  
  │           for: 5m  
  │           labels:  
  │             severity: warning  
  │           annotations:  
  │             summary: "GPU temperature above 85°C"  
  │  
  └── Set permissions: chmod 644 on all config files

### **Grafana Provisioning (Script 2\)**

generate\_grafana\_config()  
  ├── Create $CONFIG\_DIR/grafana/provisioning/datasources/prometheus.yml:  
  │  
  │   apiVersion: 1  
  │   datasources:  
  │     \- name: Prometheus  
  │       type: prometheus  
  │       access: proxy  
  │       url: http://prometheus:9090  
  │       isDefault: true  
  │       editable: false  
  │  
  ├── Create $CONFIG\_DIR/grafana/provisioning/dashboards/dashboards.yml:  
  │  
  │   apiVersion: 1  
  │   providers:  
  │     \- name: 'default'  
  │       folder: 'AI Platform'  
  │       type: file  
  │       options:  
  │         path: /var/lib/grafana/dashboards  
  │  
  ├── Download/generate dashboard JSONs:  
  │     $CONFIG\_DIR/grafana/dashboards/  
  │     ├── system-overview.json      (node\_exporter metrics)  
  │     ├── docker-containers.json    (cAdvisor metrics)  
  │     ├── gpu-metrics.json          (DCGM metrics — if GPU)  
  │     ├── litellm-costs.json        (LiteLLM token/cost tracking)  
  │     └── platform-health.json      (composite service health)  
  │  
  └── Generate grafana.ini overrides:  
        $CONFIG\_DIR/grafana/grafana.ini:  
          \[security\]  
          admin\_user \= ${GRAFANA\_ADMIN\_USER}  
          admin\_password \= ${GRAFANA\_ADMIN\_PASSWORD}  
          \[server\]  
          root\_url \= https://${GRAFANA\_DOMAIN}  
          \[auth.anonymous\]  
          enabled \= false

### **Docker Compose Blocks**

prometheus:  
  image: prom/prometheus:latest  
  container\_name: prometheus  
  restart: unless-stopped  
  ports:  
    \- "127.0.0.1:9090:9090"  
  volumes:  
    \- ${CONFIG\_DIR}/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro  
    \- ${CONFIG\_DIR}/prometheus/alert\_rules.yml:/etc/prometheus/alert\_rules.yml:ro  
    \- ${DATA\_DIR}/prometheus:/prometheus  
  command:  
    \- '--config.file=/etc/prometheus/prometheus.yml'  
    \- '--storage.tsdb.path=/prometheus'  
    \- '--storage.tsdb.retention.time=30d'  
    \- '--web.console.libraries=/etc/prometheus/console\_libraries'  
    \- '--web.console.templates=/etc/prometheus/consoles'  
    \- '--web.enable-lifecycle'  
  networks:  
    \- monitoring  
    \- backend  
  healthcheck:  
    test: \["CMD", "wget", "--tries=1", "--spider", "http://localhost:9090/-/healthy"\]  
    interval: 30s  
    timeout: 10s  
    retries: 3

grafana:  
  image: grafana/grafana:latest  
  container\_name: grafana  
  restart: unless-stopped  
  ports:  
    \- "127.0.0.1:3002:3000"  
  volumes:  
    \- ${DATA\_DIR}/grafana:/var/lib/grafana  
    \- ${CONFIG\_DIR}/grafana/provisioning:/etc/grafana/provisioning:ro  
    \- ${CONFIG\_DIR}/grafana/dashboards:/var/lib/grafana/dashboards:ro  
    \- ${CONFIG\_DIR}/grafana/grafana.ini:/etc/grafana/grafana.ini:ro  
  environment:  
    \- GF\_SECURITY\_ADMIN\_USER=${GRAFANA\_ADMIN\_USER}  
    \- GF\_SECURITY\_ADMIN\_PASSWORD=${GRAFANA\_ADMIN\_PASSWORD}  
    \- GF\_INSTALL\_PLUGINS=grafana-clock-panel,grafana-simple-json-datasource  
  networks:  
    \- monitoring  
    \- frontend  
  depends\_on:  
    prometheus:  
      condition: service\_healthy  
  healthcheck:  
    test: \["CMD", "curl", "-f", "http://localhost:3000/api/health"\]  
    interval: 30s  
    timeout: 10s  
    retries: 5

node-exporter:  
  image: prom/node-exporter:latest  
  container\_name: node-exporter  
  restart: unless-stopped  
  ports:  
    \- "127.0.0.1:9100:9100"  
  volumes:  
    \- /proc:/host/proc:ro  
    \- /sys:/host/sys:ro  
    \- /:/rootfs:ro  
  command:  
    \- '--path.procfs=/host/proc'  
    \- '--path.sysfs=/host/sys'  
    \- '--path.rootfs=/rootfs'  
    \- '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'  
  networks:  
    \- monitoring

cadvisor:  
  image: gcr.io/cadvisor/cadvisor:latest  
  container\_name: cadvisor  
  restart: unless-stopped  
  ports:  
    \- "127.0.0.1:9080:8080"  
  volumes:  
    \- /:/rootfs:ro  
    \- /var/run:/var/run:ro  
    \- /sys:/sys:ro  
    \- /var/lib/docker/:/var/lib/docker:ro  
    \- /dev/disk/:/dev/disk:ro  
  privileged: true  
  devices:  
    \- /dev/kmsg  
  networks:  
    \- monitoring

\# Conditional: only on GPU instances  
dcgm-exporter:  
  image: nvcr.io/nvidia/k8s/dcgm-exporter:3.3.5-3.4.0-ubuntu22.04  
  container\_name: dcgm-exporter  
  restart: unless-stopped  
  ports:  
    \- "127.0.0.1:9400:9400"  
  deploy:  
    resources:  
      reservations:  
        devices:  
          \- driver: nvidia  
            count: all  
            capabilities: \[gpu\]  
  networks:  
    \- monitoring

### **Key Metrics Tracked**

Copy table

| Metric Category | Source | Key Metrics |
| ----- | ----- | ----- |
| System | node\_exporter | CPU%, RAM%, disk I/O, network throughput |
| Containers | cAdvisor | Per-container CPU, RAM, restart count, network |
| GPU | dcgm-exporter | Utilization%, temperature, memory used/free, power draw |
| LLM Usage | LiteLLM | Tokens in/out per model, latency p50/p95/p99, cost per model, errors |
| Proxy | Caddy | Requests/sec, response times, status codes, bytes transferred |

---

## **14\. Script 0 — AWS Infrastructure Provisioning**

### **Scope**

Script 0 creates the AWS resources needed BEFORE SSH into the instance. It is the **only script that runs from your local machine** (or CloudShell).

### **Prerequisites**

* AWS CLI v2 installed and configured (`aws configure`)  
* IAM user/role with EC2, EBS, VPC, SecurityGroup, IAM permissions  
* SSH key pair (existing or script creates one)

### **Full Logic Flow**

script\_0\_aws\_provisioner.sh  
│  
├── PHASE 0: Preflight  
│   ├── Verify AWS CLI: aws \--version || error "Install AWS CLI first"  
│   ├── Verify credentials: aws sts get-caller-identity || error "Run 'aws configure' first"  
│   ├── Detect/select region:  
│   │     DEFAULT\_REGION= $ (aws configure get region)  
│   │     read \-p "AWS Region \[ $ DEFAULT\_REGION\]: " REGION  
│   │     REGION=${REGION:-$DEFAULT\_REGION}  
│   └── Verify region is valid: aws ec2 describe-regions \--region-names  $ REGION  
│  
├── PHASE 1: Configuration Interview  
│   ├── Instance sizing:  
│   │     echo "Select instance type:"  
│   │     echo "  1\) g4dn.xlarge    — 1x T4 GPU, 4 vCPU, 16 GB  (\~ $ 0.53/hr)"  
│   │     echo "  2\) g4dn.2xlarge   — 1x T4 GPU, 8 vCPU, 32 GB  (\~ $ 0.75/hr)"  
│   │     echo "  3\) g5.xlarge      — 1x A10G GPU, 4 vCPU, 16 GB (\~ $ 1.01/hr)"  
│   │     echo "  4\) g5.2xlarge     — 1x A10G GPU, 8 vCPU, 32 GB (\~ $ 1.21/hr)"  
│   │     echo "  5\) g5.4xlarge     — 1x A10G GPU, 16 vCPU, 64 GB(\~ $ 1.62/hr)"  
│   │     echo "  6\) p3.2xlarge     — 1x V100 GPU, 8 vCPU, 61 GB (\~ $ 3.06/hr)"  
│   │     echo "  7\) t3.2xlarge     — NO GPU, 8 vCPU, 32 GB       (\~ $ 0.33/hr)"  
│   │     echo "  8\) Custom         — enter instance type manually"  
│   │     read \-p "Choice \[2\]: " choice  
│   │     Map choice to INSTANCE\_TYPE  
│   │  
│   ├── EBS volume sizing:  
│   │     echo "Data volume size (for models, databases, documents):"  
│   │     echo "  Minimum: 100 GB (lightweight models only)"  
│   │     echo "  Recommended: 200 GB (standard model set)"  
│   │     echo "  Large: 500 GB (full model set \+ large document corpus)"  
│   │     read \-p "Data volume size in GB \[200\]: " EBS\_SIZE  
│   │     EBS\_SIZE=${EBS\_SIZE:-200}  
│   │     EBS\_TYPE=gp3  \# Always gp3 for cost efficiency  
│   │  
│   ├── SSH key:  
│   │     \# Check for existing key pairs  
│   │     EXISTING\_KEYS=$(aws ec2 describe-key-pairs \--query 'KeyPairs\[\].KeyName' \--output text)  
│   │     echo "Existing key pairs:  $ EXISTING\_KEYS"  
│   │     echo "  1\) Use existing key pair"  
│   │     echo "  2\) Create new key pair"  
│   │     read \-p "Choice \[1\]: " key\_choice  
│   │     If 1: read \-p "Key pair name: " KEY\_NAME  
│   │     If 2:  
│   │       KEY\_NAME="ai-platform- $ (date \+%Y%m%d)"  
│   │       aws ec2 create-key-pair \--key-name  $ KEY\_NAME \\  
│   │         \--query 'KeyMaterial' \--output text \> \~/.ssh/ $ {KEY\_NAME}.pem  
│   │       chmod 400 \~/.ssh/${KEY\_NAME}.pem  
│   │       echo "Key saved to \~/.ssh/${KEY\_NAME}.pem"  
│   │  
│   ├── Network:  
│   │     echo "Network configuration:"  
│   │     echo "  1\) Default VPC (simplest — recommended)"  
│   │     echo "  2\) Specify VPC and subnet"  
│   │     read \-p "Choice \[1\]: " net\_choice  
│   │     If 1:  
│   │       VPC\_ID= $ (aws ec2 describe-vpcs \--filters "Name=is-default,Values=true" \\  
│   │         \--query 'Vpcs\[0\].VpcId' \--output text)  
│   │       SUBNET\_ID= $ (aws ec2 describe-subnets \--filters "Name=vpc-id,Values= $ VPC\_ID" \\  
│   │         \--query 'Subnets\[0\].SubnetId' \--output text)  
│   │     If 2:  
│   │       read \-p "VPC ID: " VPC\_ID  
│   │       read \-p "Subnet ID: " SUBNET\_ID  
│   │  
│   ├── Access control:  
│   │     MY\_IP= $ (curl \-s ifconfig.me)  
│   │     echo "Your current public IP:  $ MY\_IP"  
│   │     echo "SSH access:"  
│   │     echo "  1\) My IP only ( $ MY\_IP/32) — recommended"  
│   │     echo "  2\) Specific CIDR range"  
│   │     echo "  3\) Open to all (0.0.0.0/0) — NOT recommended"  
│   │     read \-p "Choice \[1\]: " ssh\_choice  
│   │     Map to SSH\_CIDR  
│   │       
│   │     echo "Web access (ports 80/443):"  
│   │     echo "  1\) Open to all (0.0.0.0/0) — standard for web services"  
│   │     echo "  2\) My IP only ( $ MY\_IP/32)"  
│   │     echo "  3\) Specific CIDR range"  
│   │     read \-p "Choice \[1\]: " web\_choice  
│   │     Map to WEB\_CIDR  
│   │  
│   └── Naming:  
│       read \-p "Instance name tag \[ai-platform\]: " INSTANCE\_NAME  
│       INSTANCE\_NAME= $ {INSTANCE\_NAME:-ai-platform}  
│  
├── PHASE 2: AMI Selection  
│   ├── Determine AMI:  
│   │     If GPU instance (g4\*, g5\*, p3\*):  
│   │       \# Use NVIDIA Deep Learning AMI (has CUDA \+ drivers pre-installed)  
│   │       AMI\_ID= $ (aws ec2 describe-images \\  
│   │         \--owners amazon \\  
│   │         \--filters \\  
│   │           "Name=name,Values=Deep Learning AMI GPU PyTorch\*Ubuntu 22.04\*" \\  
│   │           "Name=state,Values=available" \\  
│   │         \--query 'sort\_by(Images, \&CreationDate)\[-1\].ImageId' \\  
│   │         \--output text)  
│   │         
│   │       If AMI\_ID is empty or "None":  
│   │         \# Fallback: Ubuntu 22.04 (will install CUDA in Script 1\)  
│   │         AMI\_ID= $ (aws ec2 describe-images \\  
│   │           \--owners 099720109477 \\  
│   │           \--filters \\  
│   │             "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-\*" \\  
│   │             "Name=state,Values=available" \\  
│   │           \--query 'sort\_by(Images, \&CreationDate)\[-1\].ImageId' \\  
│   │           \--output text)  
│   │         GPU\_DRIVERS\_NEEDED=true  
│   │  
│   │     If non-GPU instance:  
│   │       AMI\_ID=$(aws ec2 describe-images \\  
│   │         \--owners 099720109477 \\  
│   │         \--filters \\  
│   │           "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-\*" \\  
│   │           "Name=state,Values=available" \\  
│   │         \--query 'sort\_by(Images, \&CreationDate)\[-1\].ImageId' \\  
│   │         \--output text)  
│   │       GPU\_DRIVERS\_NEEDED=false  
│   │  
│   └── echo "Selected AMI:  $ AMI\_ID"  
│  
├── PHASE 3: Security Group  
│   ├── SG\_NAME="ai-platform-sg- $ (date \+%Y%m%d%H%M)"  
│   ├── SG\_ID= $ (aws ec2 create-security-group \\  
│   │     \--group-name " $ SG\_NAME" \\  
│   │     \--description "AI Platform security group" \\  
│   │     \--vpc-id $VPC\_ID \\  
│   │     \--query 'GroupId' \--output text)  
│   │  
│   ├── Ingress rules:  
│   │     \# SSH  
│   │     aws ec2 authorize-security-group-ingress \--group-id $SG\_ID \\  
│   │       \--protocol tcp \--port 22 \--cidr $SSH\_CIDR  
│   │     \# HTTP  
│   │     aws ec2 authorize-security-group-ingress \--group-id $SG\_ID \\  
│   │       \--protocol tcp \--port 80 \--cidr $WEB\_CIDR  
│   │     \# HTTPS  
│   │     aws ec2 authorize-security-group-ingress \--group-id $SG\_ID \\  
│   │       \--protocol tcp \--port 443 \--cidr $WEB\_CIDR  
│   │     \# HTTPS UDP (HTTP/3)  
│   │     aws ec2 authorize-security-group-ingress \--group-id $SG\_ID \\  
│   │       \--protocol udp \--port 443 \--cidr $WEB\_CIDR  
│   │  
│   ├── Egress: default (all outbound allowed)  
│   └── Tag: aws ec2 create-tags \--resources  $ SG\_ID \--tags Key=Name,Value= $ SG\_NAME  
│  
├── PHASE 4: IAM Instance Profile (for S3 backup access)  
│   ├── Create IAM role:  
│   │     ROLE\_NAME="ai-platform-ec2-role"  
│   │     aws iam create-role \--role-name  $ ROLE\_NAME \\  
│   │       \--assume-role-policy-document '{  
│   │         "Version": "2012-10-17",  
│   │         "Statement": \[{  
│   │           "Effect": "Allow",  
│   │           "Principal": {"Service": "ec2.amazonaws.com"},  
│   │           "Action": "sts:AssumeRole"  
│   │         }\]  
│   │       }'  
│   │  
│   ├── Attach S3 policy (limited to platform bucket):  
│   │     BUCKET\_NAME="ai-platform-backups- $ (aws sts get-caller-identity \--query Account \--output text)"  
│   │     aws iam put-role-policy \--role-name  $ ROLE\_NAME \\  
│   │       \--policy-name ai-platform-s3 \\  
│   │       \--policy-document '{  
│   │         "Version": "2012-10-17",  
│   │         "Statement": \[{  
│   │           "Effect": "Allow",  
│   │           "Action": \["s3:PutObject","s3:GetObject","s3:ListBucket","s3:DeleteObject"\],  
│   │           "Resource": \[  
│   │             "arn:aws:s3:::'" $ BUCKET\_NAME"'",  
│   │             "arn:aws:s3:::'"$BUCKET\_NAME"'/\*"  
│   │           \]  
│   │         }\]  
│   │       }'  
│   │  
│   ├── Create instance profile:  
│   │     aws iam create-instance-profile \--instance-profile-name $ROLE\_NAME  
│   │     aws iam add-role-to-instance-profile \\  
│   │       \--instance-profile-name $ROLE\_NAME \--role-name  $ ROLE\_NAME  
│   │     sleep 10   \# Wait for IAM propagation  
│   │  
│   └── Create S3 bucket:  
│         aws s3 mb s3:// $ BUCKET\_NAME \--region $REGION  
│         aws s3api put-bucket-encryption \--bucket  $ BUCKET\_NAME \\  
│           \--server-side-encryption-configuration '{  
│             "Rules": \[{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}\]  
│           }'  
│  
├── PHASE 5: Launch Instance  
│   ├── Generate user-data script (cloud-init):  
│   │     USER\_DATA= $ (cat \<\<'USERDATA'  
│   │     \#\!/bin/bash  
│   │     \# Minimal bootstrap — just enough for Script 1  
│   │     apt-get update \-qq  
│   │     apt-get install \-y \-qq git curl wget  
│   │       
│   │     \# Clone the platform repo  
│   │     git clone https://github.com/YOUR\_REPO/ai-platform.git /opt/ai-platform-setup  
│   │       
│   │     \# Signal that instance is ready  
│   │     touch /tmp/cloud-init-complete  
│   │     USERDATA  
│   │     )  
│   │  
│   ├── Launch:  
│   │     INSTANCE\_ID=$(aws ec2 run-instances \\  
│   │       \--image-id $AMI\_ID \\  
│   │       \--instance-type $INSTANCE\_TYPE \\  
│   │       \--key-name $KEY\_NAME \\  
│   │       \--security-group-ids $SG\_ID \\  
│   │       \--subnet-id  $ SUBNET\_ID \\  
│   │       \--iam-instance-profile Name= $ ROLE\_NAME \\  
│   │       \--block-device-mappings "\[  
│   │         {\\"DeviceName\\":\\"/dev/sda1\\",\\"Ebs\\":{\\"VolumeSize\\":50,\\"VolumeType\\":\\"gp3\\",\\"DeleteOnTermination\\":true}},  
│   │         {\\"DeviceName\\":\\"/dev/sdf\\",\\"Ebs\\":{\\"VolumeSize\\":${EBS\_SIZE},\\"VolumeType\\":\\"gp3\\",\\"DeleteOnTermination\\":false,\\"Iops\\":3000,\\"Throughput\\":125}}  
│   │       \]" \\  
│   │       \--tag-specifications "ResourceType=instance,Tags=\[  
│   │         {Key=Name,Value= $ INSTANCE\_NAME},  
│   │         {Key=Project,Value=ai-platform},  
│   │         {Key=ManagedBy,Value=script-0}  
│   │       \]" \\  
│   │       \--user-data " $ USER\_DATA" \\  
│   │       \--query 'Instances\[0\].InstanceId' \\  
│   │       \--output text)  
│   │  
│   ├── echo "Instance launching: $INSTANCE\_ID"  
│   │  
│   ├── Wait for running:  
│   │     aws ec2 wait instance-running \--instance-ids  $ INSTANCE\_ID  
│   │     echo "Instance is running"  
│   │  
│   ├── Get public IP:  
│   │     PUBLIC\_IP= $ (aws ec2 describe-instances \--instance-ids  $ INSTANCE\_ID \\  
│   │       \--query 'Reservations\[0\].Instances\[0\].PublicIpAddress' \--output text)  
│   │  
│   ├── Tag EBS data volume:  
│   │     DATA\_VOL\_ID= $ (aws ec2 describe-volumes \\  
│   │       \--filters "Name=attachment.instance-id,Values=$INSTANCE\_ID" \\  
│   │                 "Name=attachment.device,Values=/dev/sdf" \\  
│   │       \--query 'Volumes\[0\].VolumeId' \--output text)  
│   │     aws ec2 create-tags \--resources  $ DATA\_VOL\_ID \\  
│   │       \--tags Key=Name,Value=" $ {INSTANCE\_NAME}-data"  
│   │  
│   └── Wait for SSH ready:  
│         echo "Waiting for SSH to become available..."  
│         for i in  $ (seq 1 30); do  
│           if ssh \-o StrictHostKeyChecking=no \-o ConnectTimeout=5 \\  
│                \-i \~/.ssh/ $ {KEY\_NAME}.pem ubuntu@$PUBLIC\_IP "echo ready" 2\>/dev/null; then  
│             SSH\_READY=true  
│             break  
│           fi  
│           sleep 10  
│         done  
│  
├── PHASE 6: Generate Connection Info  
│   ├── Create local info file: ai-platform-connection.txt  
│   │     \==========================================  
│   │     AI Platform Instance Information  
│   │     \==========================================  
│   │     Instance ID:    $INSTANCE\_ID  
│   │     Instance Type:  $INSTANCE\_TYPE  
│   │     Public IP:      $PUBLIC\_IP  
│   │     Region:         $REGION  
│   │     Key Pair:       $KEY\_NAME  
│   │     Security Group:  $ SG\_ID ( $ SG\_NAME)  
│   │     Data Volume:     $ DATA\_VOL\_ID ( $ {EBS\_SIZE} GB)  
│   │     S3 Bucket:      $BUCKET\_NAME  
│   │     AMI:            $AMI\_ID  
│   │     GPU Drivers:    ${GPU\_DRIVERS\_NEEDED}  
│   │       
│   │     SSH Command:  
│   │       ssh \-i \~/.ssh/${KEY\_NAME}.pem ubuntu@ $ PUBLIC\_IP  
│   │       
│   │     Next Step:  
│   │       1\. SSH into the instance  
│   │       2\. Run: sudo bash /opt/ai-platform-setup/script-1-setup.sh  
│   │     \==========================================  
│   │  
│   ├── Display connection info  
│   └── Optionally copy Script 1 to instance:  
│         scp \-i \~/.ssh/ $ {KEY\_NAME}.pem \\  
│           ./script-1-setup.sh ubuntu@ $ PUBLIC\_IP:/tmp/  
│  
└── PHASE 7: Optional — Elastic IP  
    ├── read \-p "Allocate Elastic IP (static IP survives stop/start)? (y/n) \[y\]: " eip\_choice  
    ├── If yes:  
    │     EIP\_ALLOC= $ (aws ec2 allocate-address \--domain vpc \--query 'AllocationId' \--output text)  
    │     aws ec2 associate-address \--instance-id $INSTANCE\_ID \--allocation-id  $ EIP\_ALLOC  
    │     STATIC\_IP= $ (aws ec2 describe-addresses \--allocation-ids $EIP\_ALLOC \\  
    │       \--query 'Addresses\[0\].PublicIp' \--output text)  
    │     echo "Elastic IP: $STATIC\_IP (replaces  $ PUBLIC\_IP)"  
    │     PUBLIC\_IP= $ STATIC\_IP  
    │     Update connection info file  
    └── If no: echo "Warning: Public IP will change on instance stop/start"

### **Estimated Costs**

Copy table

| Resource | Cost |
| ----- | ----- |
| g4dn.2xlarge (on-demand) | \~$0.75/hr \= \~$540/month |
| g4dn.2xlarge (1yr reserved) | \~$0.35/hr \= \~$252/month |
| g5.2xlarge (on-demand) | \~$1.21/hr \= \~$871/month |
| 200 GB gp3 EBS | \~$16/month |
| 500 GB gp3 EBS | \~$40/month |
| Elastic IP (attached) | Free |
| Elastic IP (detached) | \~$3.65/month |
| S3 backup (50 GB) | \~$1.15/month |
| Data transfer out (first 100 GB) | Free tier |

---

## **15\. Script 1 — System Setup & Configuration Interview**

### **Scope**

Script 1 runs on the EC2 instance. It installs all system-level dependencies, conducts the configuration interview, and prepares everything for Script 2 (Docker deployment).

### **Full Logic Flow**

script\_1\_system\_setup.sh  
│  
├── PHASE 0: Validation & Root Check  
│   ├── if \[\[ $EUID \-ne 0 \]\]; then error "Run as root: sudo bash  $ 0"; fi  
│   ├── Detect OS: must be Ubuntu 22.04 or 24.04  
│   │     source /etc/os-release  
│   │     if \[\[ " $ ID" \!= "ubuntu" \]\] || \[\[ \! " $ VERSION\_ID" \=\~ ^(22.04|24.04) $  \]\]; then  
│   │       error "Requires Ubuntu 22.04 or 24.04"  
│   │     fi  
│   ├── Check internet: curl \-s \--max-time 5 https://google.com \> /dev/null || error "No internet"  
│   ├── Check minimum resources:  
│   │     TOTAL\_RAM\_GB=$(free \-g | awk '/Mem:/{print $2}')  
│   │     if \[\[  $ TOTAL\_RAM\_GB \-lt 8 \]\]; then warn "Less than 8 GB RAM — performance will suffer"; fi  
│   │     TOTAL\_DISK\_GB= $ (df \-BG / | awk 'NR==2{gsub(/G/,""); print $4}')  
│   │     if \[\[  $ TOTAL\_DISK\_GB \-lt 20 \]\]; then error "Less than 20 GB free on root — cannot proceed"; fi  
│   ├── Create log directory: mkdir \-p /var/log/ai-platform  
│   ├── Start transcript: exec \> \>(tee \-a /var/log/ai-platform/script-1.log) 2\>&1  
│   └── Record start time: START\_TIME= $ (date \+%s)  
│  
├── PHASE 1: Directory Structure  
│   ├── Create base directories:  
│   │     BASE\_DIR=/opt/ai-platform  
│   │     mkdir \-p  $ BASE\_DIR/{config,env,scripts,backups}  
│   │     mkdir \-p /var/log/ai-platform  
│   │  
│   ├── Detect and mount EBS data volume:  
│   │     \# Find unmounted EBS volume (the one from Script 0\)  
│   │     DATA\_DEVICE=""  
│   │     for dev in /dev/nvme1n1 /dev/xvdf /dev/sdf; do  
│   │       if \[\[ \-b " $ dev" \]\]; then  
│   │         DATA\_DEVICE= $ dev  
│   │         break  
│   │       fi  
│   │     done  
│   │       
│   │     if \[\[ \-z " $ DATA\_DEVICE" \]\]; then  
│   │       warn "No separate data volume found — using /opt/ai-platform/data"  
│   │       DATA\_DIR=$BASE\_DIR/data  
│   │       mkdir \-p $DATA\_DIR  
│   │     else  
│   │       \# Check if already formatted  
│   │       if \! blkid $DATA\_DEVICE | grep \-q ext4; then  
│   │         echo "Formatting $DATA\_DEVICE as ext4..."  
│   │         mkfs.ext4 \-m 0 \-F $DATA\_DEVICE  
│   │       fi  
│   │       DATA\_DIR=/mnt/data  
│   │       mkdir \-p $DATA\_DIR  
│   │       mount $DATA\_DEVICE  $ DATA\_DIR  
│   │         
│   │       \# Add to fstab for persistence  
│   │       UUID= $ (blkid \-s UUID \-o value  $ DATA\_DEVICE)  
│   │       if \! grep \-q " $ UUID" /etc/fstab; then  
│   │         echo "UUID=$UUID $DATA\_DIR ext4 defaults,nofail 0 2" \>\> /etc/fstab  
│   │       fi  
│   │     fi  
│   │  
│   ├── Create data subdirectories:  
│   │     mkdir \-p $DATA\_DIR/{postgres,redis,qdrant,ollama/models,n8n,dify,flowise}  
│   │     mkdir \-p $DATA\_DIR/{anythingllm,openclaw,caddy,prometheus,grafana}  
│   │     mkdir \-p  $ DATA\_DIR/{chromadb,weaviate,milvus,gdrive}  
│   │  
│   └── Initialize master.env:  
│         ENV\_DIR= $ BASE\_DIR/env  
│         CONFIG\_DIR=$BASE\_DIR/config  
│         cat \> $ENV\_DIR/master.env \<\< EOF  
│         \# AI Platform Master Configuration  
│         \# Generated:  $ (date \-u \+"%Y-%m-%dT%H:%M:%SZ")  
│         \# Script 1 version: 1.0.0  
│           
│         \# Paths  
│         BASE\_DIR= $ BASE\_DIR  
│         DATA\_DIR= $ DATA\_DIR  
│         CONFIG\_DIR= $ CONFIG\_DIR  
│         ENV\_DIR= $ ENV\_DIR  
│         LOG\_DIR=/var/log/ai-platform  
│           
│         \# Instance Info  
│         INSTANCE\_TYPE= $ (curl \-s http://169.254.169.254/latest/meta-data/instance-type 2\>/dev/null || echo "unknown")  
│         INSTANCE\_ID= $ (curl \-s http://169.254.169.254/latest/meta-data/instance-id 2\>/dev/null || echo "unknown")  
│         PUBLIC\_IP= $ (curl \-s http://169.254.169.254/latest/meta-data/public-ipv4 2\>/dev/null || echo "unknown")  
│         REGION=$(curl \-s http://169.254.169.254/latest/meta-data/placement/region 2\>/dev/null || echo "unknown")  
│         EOF  
│         chmod 600  $ ENV\_DIR/master.env  
│  
├── PHASE 2: System Packages  
│   ├── export DEBIAN\_FRONTEND=noninteractive  
│   ├── apt-get update \-qq  
│   ├── apt-get upgrade \-y \-qq  
│   ├── apt-get install \-y \-qq \\  
│   │     curl wget git jq yq unzip htop tree ncdu tmux \\  
│   │     ca-certificates gnupg lsb-release software-properties-common \\  
│   │     build-essential python3 python3-pip python3-venv \\  
│   │     apache2-utils openssl uuid-runtime \\  
│   │     dnsutils net-tools iotop sysstat \\  
│   │     fail2ban ufw  
│   └── pip3 install \--quiet langchain chromadb sentence-transformers  \# For direct embed script  
│  
├── PHASE 3: Docker Installation  
│   ├── Remove old Docker (if any):  
│   │     apt-get remove \-y docker docker-engine docker.io containerd runc 2\>/dev/null  
│   ├── Add Docker GPG key and repo:  
│   │     install \-m 0755 \-d /etc/apt/keyrings  
│   │     curl \-fsSL https://download.docker.com/linux/ubuntu/gpg | \\  
│   │       gpg \--dearmor \-o /etc/apt/keyrings/docker.gpg  
│   │     chmod a+r /etc/apt/keyrings/docker.gpg  
│   │     echo "deb \[arch= $ (dpkg \--print-architecture) signed-by=/etc/apt/keyrings/docker.gpg\] \\  
│   │       https://download.docker.com/linux/ubuntu  $ (lsb\_release \-cs) stable" | \\  
│   │       tee /etc/apt/sources.list.d/docker.list \> /dev/null  
│   ├── apt-get update \-qq  
│   ├── apt-get install \-y \-qq docker-ce docker-ce-cli containerd.io \\  
│   │     docker-buildx-plugin docker-compose-plugin  
│   ├── systemctl enable \--now docker  
│   ├── usermod \-aG docker ubuntu   \# Allow non-root docker  
│   ├── Verify: docker \--version && docker compose version  
│   └── Write DOCKER\_VERSION to master.env  
│  
├── PHASE 4: NVIDIA GPU Setup (Conditional)  
│   ├── Detect GPU:  
│   │     HAS\_GPU=false  
│   │     if lspci | grep \-i nvidia \> /dev/null 2\>&1; then  
│   │       HAS\_GPU=true  
│   │     fi  
│   │     echo "HAS\_GPU= $ HAS\_GPU" \>\>  $ ENV\_DIR/master.env  
│   │  
│   ├── If HAS\_GPU=true:  
│   │     ├── Check if NVIDIA drivers already installed (Deep Learning AMI):  
│   │     │     if nvidia-smi \> /dev/null 2\>&1; then  
│   │     │       echo "NVIDIA drivers already installed"  
│   │     │       DRIVER\_VERSION= $ (nvidia-smi \--query-gpu=driver\_version \--format=csv,noheader)  
│   │     │       echo "NVIDIA\_DRIVER\_VERSION=$DRIVER\_VERSION" \>\>  $ ENV\_DIR/master.env  
│   │     │     else  
│   │     │       echo "Installing NVIDIA drivers..."  
│   │     │       apt-get install \-y \-qq nvidia-driver-535 nvidia-utils-535  
│   │     │       \# May require reboot — script detects and handles  
│   │     │     fi  
│   │     │  
│   │     ├── Install NVIDIA Container Toolkit:  
│   │     │     distribution= $ (. /etc/os-release; echo  $ ID $ VERSION\_ID)  
│   │     │     curl \-fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \\  
│   │     │       gpg \--dearmor \-o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg  
│   │     │     curl \-s \-L https://nvidia.github.io/libnvidia-container/ $ distribution/libnvidia-container.list | \\  
│   │     │       sed 's\#deb https://\#deb \[signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg\] https://\#g' | \\  
│   │     │       tee /etc/apt/sources.list.d/nvidia-container-toolkit.list  
│   │     │     apt-get update \-qq  
│   │     │     apt-get install \-y \-qq nvidia-container-toolkit  
│   │     │     nvidia-ctk runtime configure \--runtime=docker  
│   │     │     systemctl restart docker  
│   │     │  
│   │     ├── Verify GPU in Docker:  
│   │     │     docker run \--rm \--gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi  
│   │     │     If fails: error "GPU not accessible in Docker — check drivers"  
│   │     │  
│   │     └── Record GPU info:  
│   │           GPU\_NAME= $ (nvidia-smi \--query-gpu=gpu\_name \--format=csv,noheader | head \-1)  
│   │           GPU\_MEMORY= $ (nvidia-smi \--query-gpu=memory.total \--format=csv,noheader | head \-1)  
│   │           echo "GPU\_NAME= $ GPU\_NAME" \>\>  $ ENV\_DIR/master.env  
│   │           echo "GPU\_MEMORY= $ GPU\_MEMORY" \>\> $ENV\_DIR/master.env  
│   │  
│   └── If HAS\_GPU=false:  
│         echo "No NVIDIA GPU detected — Ollama will run CPU-only"  
│         echo "GPU\_NAME=none" \>\>  $ ENV\_DIR/master.env  
│  
├── PHASE 5: Ollama Installation  
│   ├── curl \-fsSL https://ollama.com/install.sh | sh  
│   ├── Create systemd override:  
│   │     mkdir \-p /etc/systemd/system/ollama.service.d  
│   │     cat \> /etc/systemd/system/ollama.service.d/override.conf \<\< EOF  
│   │     \[Service\]  
│   │     Environment="OLLAMA\_HOST=0.0.0.0:11434"  
│   │     Environment="OLLAMA\_MODELS= $ {DATA\_DIR}/ollama/models"  
│   │     Environment="OLLAMA\_KEEP\_ALIVE=24h"  
│   │     Environment="OLLAMA\_MAX\_LOADED\_MODELS=2"  
│   │     EOF  
│   ├── systemctl daemon-reload  
│   ├── systemctl enable \--now ollama  
│   ├── Wait for ready:  
│   │     for i in $(seq 1 30); do  
│   │       curl \-s http://localhost:11434/api/version \> /dev/null 2\>&1 && break  
│   │       sleep 2  
│   │     done  
│   ├── Verify: curl \-s http://localhost:11434/api/version | jq .  
│   └── echo "OLLAMA\_BASE\_URL=http://host.docker.internal:11434" \>\> $ENV\_DIR/master.env  
│  
├── PHASE 6: rclone Installation  
│   ├── curl https://rclone.org/install.sh | bash  
│   ├── mkdir \-p $CONFIG\_DIR/rclone  
│   ├── rclone version  
│   └── echo "RCLONE\_INSTALLED=true" \>\>  $ ENV\_DIR/master.env  
│  
├── PHASE 7: Security Hardening  
│   ├── Configure fail2ban:  
│   │     cat \> /etc/fail2ban/jail.local \<\< EOF  
│   │     \[sshd\]  
│   │     enabled \= true  
│   │     port \= ssh  
│   │     filter \= sshd  
│   │     logpath \= /var/log/auth.log  
│   │     maxretry \= 5  
│   │     bantime \= 3600  
│   │     findtime \= 600  
│   │     EOF  
│   │     systemctl enable \--now fail2ban  
│   │  
│   ├── Configure UFW:  
│   │     ufw default deny incoming  
│   │     ufw default allow outgoing  
│   │     ufw allow 22/tcp     \# SSH  
│   │     ufw allow 80/tcp     \# HTTP  
│   │     ufw allow 443/tcp    \# HTTPS  
│   │     ufw allow 443/udp    \# HTTP/3  
│   │     ufw \--force enable  
│   │  
│   ├── Kernel tuning:  
│   │     cat \>\> /etc/sysctl.d/99-ai-platform.conf \<\< EOF  
│   │     \# Network performance  
│   │     net.core.somaxconn \= 65535  
│   │     net.ipv4.tcp\_max\_syn\_backlog \= 65535  
│   │     net.core.netdev\_max\_backlog \= 65535  
│   │       
│   │     \# Memory  
│   │     vm.overcommit\_memory \= 1  
│   │     vm.swappiness \= 10  
│   │       
│   │     \# File descriptors  
│   │     fs.file-max \= 2097152  
│   │     fs.inotify.max\_user\_watches \= 524288  
│   │     EOF  
│   │     sysctl \-p /etc/sysctl.d/99-ai-platform.conf  
│   │  
│   └── Set Docker log limits:  
│         cat \> /etc/docker/daemon.json \<\< EOF  
│         {  
│           "log-driver": "json-file",  
│           "log-opts": {  
│             "max-size": "10m",  
│             "max-file": "5"  
│           },  
│           "default-runtime": " $ (if \[\[  $ HAS\_GPU \== true \]\]; then echo nvidia; else echo runc; fi)",  
│           "runtimes": {  
│             "nvidia": {  
│               "path": "nvidia-container-runtime",  
│               "runtimeArgs": \[\]  
│             }  
│           },  
│           "storage-driver": "overlay2",  
│           "live-restore": true  
│         }  
│         EOF  
│         systemctl restart docker  
│  
├── PHASE 8: Configuration Interview  
│   ├── echo "============================================"  
│   ├── echo "    AI Platform Configuration Interview"  
│   ├── echo "============================================"  
│   │  
│   ├── 8a. Service Selection:  
│   │     echo ""  
│   │     echo "Select services to deploy:"  
│   │     echo "  Core (always installed):"  
│   │     echo "    ✓ PostgreSQL \+ Redis"  
│   │     echo "    ✓ LiteLLM (model router)"  
│   │     echo "    ✓ Caddy (reverse proxy)"  
│   │     echo "    ✓ Portainer (container management)"  
│   │     echo ""  
│   │     echo "  AI Platforms:"  
│   │     read \-p "    Install Dify? (y/n) \[y\]: " INSTALL\_DIFY  
│   │     read \-p "    Install n8n? (y/n) \[y\]: " INSTALL\_N8N  
│   │     read \-p "    Install Open WebUI? (y/n) \[y\]: " INSTALL\_OPENWEBUI  
│   │     read \-p "    Install Flowise? (y/n) \[y\]: " INSTALL\_FLOWISE  
│   │     read \-p "    Install AnythingLLM? (y/n) \[n\]: " INSTALL\_ANYTHINGLLM  
│   │     read \-p "    Install OpenClaw? (y/n) \[n\]: " INSTALL\_OPENCLAW  
│   │     echo ""  
│   │     echo "  Monitoring:"  
│   │     read \-p "    Install monitoring stack (Prometheus+Grafana)? (y/n) \[y\]: " INSTALL\_MONITORING  
│   │     echo ""  
│   │     echo "  Auth:"  
│   │     read \-p "    Install SuperTokens (centralized auth)? (y/n) \[n\]: " INSTALL\_SUPERTOKENS  
│   │       
│   │     \# Build ENABLED\_SERVICES list  
│   │     ENABLED\_SERVICES="postgres,redis,litellm,caddy,portainer"  
│   │     \[\[ " $ {INSTALL\_DIFY:-y}" \=\~ ^\[Yy\] \]\] && ENABLED\_SERVICES+=",dify"  
│   │     \[\[ "${INSTALL\_N8N:-y}" \=\~ ^\[Yy\] \]\] && ENABLED\_SERVICES+=",n8n"  
│   │     \[\[ "${INSTALL\_OPENWEBUI:-y}" \=\~ ^\[Yy\] \]\] && ENABLED\_SERVICES+=",open-webui"  
│   │     \[\[ "${INSTALL\_FLOWISE:-y}" \=\~ ^\[Yy\] \]\] && ENABLED\_SERVICES+=",flowise"  
│   │     \[\[ "${INSTALL\_ANYTHINGLLM:-n}" \=\~ ^\[Yy\] \]\] && ENABLED\_SERVICES+=",anythingllm"  
│   │     \[\[ "${INSTALL\_OPENCLAW:-n}" \=\~ ^\[Yy\] \]\] && ENABLED\_SERVICES+=",openclaw"  
│   │     \[\[ "${INSTALL\_MONITORING:-y}" \=\~ ^\[Yy\] \]\] && ENABLED\_SERVICES+=",monitoring"  
│   │     \[\[ "${INSTALL\_SUPERTOKENS:-n}" \=\~ ^\[Yy\] \]\] && ENABLED\_SERVICES+=",supertokens"  
│   │     echo "ENABLED\_SERVICES=$ENABLED\_SERVICES" \>\>  $ ENV\_DIR/master.env  
│   │  
│   ├── 8b. Vector DB Selection:  
│   │     select\_vector\_db   \# (as defined in Section 10\)  
│   │  
│   ├── 8c. Model Tier Selection:  
│   │     echo ""  
│   │     echo "Select Ollama model tier:"  
│   │     echo "  1\) Minimal  — tinyllama \+ nomic-embed-text (\~3 GB)"  
│   │     echo "  2\) Standard — \+ mistral, llama3.1:8b, codellama:7b (\~25 GB)"  
│   │     echo "  3\) Full     — \+ llama3.1:70b, mixtral, deepseek-coder (\~120 GB)"  
│   │     echo "  4\) Custom   — choose individual models later"  
│   │     read \-p "Choice \[2\]: " model\_choice  
│   │     MODEL\_TIER= $ (map\_choice\_to\_tier  $ model\_choice)  
│   │     echo "MODEL\_TIER= $ MODEL\_TIER" \>\> $ENV\_DIR/master.env  
│   │  
│   ├── 8d. API Keys:  
│   │     collect\_api\_keys   \# (as defined in Section 8\)  
│   │  
│   ├── 8e. Domain Configuration:  
│   │     configure\_domain   \# (as defined in Section 12\)  
│   │  
│   ├── 8f. Google Drive Sync:  
│   │     echo ""  
│   │     read \-p "Enable Google Drive sync for RAG documents? (y/n) \[n\]: " ENABLE\_GDRIVE  
│   │     if \[\[ "${ENABLE\_GDRIVE}" \=\~ ^\[Yy\] \]\]; then  
│   │       echo "GDRIVE\_ENABLED=true" \>\> $ENV\_DIR/master.env  
│   │       echo ""  
│   │       echo "Google Drive sync requires OAuth2 credentials."  
│   │       echo "You'll need a Google Cloud project with Drive API enabled."  
│   │       echo "See: https://rclone.org/drive/\#making-your-own-client-id"  
│   │       echo ""  
│   │       read \-p "  Google OAuth Client ID: " GDRIVE\_CLIENT\_ID  
│   │       read \-p "  Google OAuth Client Secret: " GDRIVE\_CLIENT\_SECRET  
│   │       read \-p "  Folder ID or path to sync \[root\]: " GDRIVE\_FOLDER  
│   │       GDRIVE\_FOLDER=${GDRIVE\_FOLDER:-root}  
│   │       read \-p "  Sync interval in minutes \[60\]: " GDRIVE\_INTERVAL  
│   │       GDRIVE\_INTERVAL=${GDRIVE\_INTERVAL:-60}  
│   │       echo "GDRIVE\_CLIENT\_ID=${GDRIVE\_CLIENT\_ID}" \>\> $ENV\_DIR/master.env  
│   │       echo "GDRIVE\_CLIENT\_SECRET=${GDRIVE\_CLIENT\_SECRET}" \>\> $ENV\_DIR/master.env  
│   │       echo "GDRIVE\_FOLDER=${GDRIVE\_FOLDER}" \>\> $ENV\_DIR/master.env  
│   │       echo "GDRIVE\_INTERVAL=${GDRIVE\_INTERVAL}" \>\> $ENV\_DIR/master.env  
│   │       echo "GDRIVE\_SYNC\_DIR=${DATA\_DIR}/gdrive" \>\> $ENV\_DIR/master.env  
│   │       echo ""  
│   │       echo "NOTE: You will need to complete rclone OAuth authorization"  
│   │       echo "during Script 2 (requires browser or token paste)."  
│   │     else  
│   │       echo "GDRIVE\_ENABLED=false" \>\> $ENV\_DIR/master.env  
│   │     fi  
│   │  
│   ├── 8g. Backup Configuration:  
│   │     echo ""  
│   │     echo "Backup configuration:"  
│   │     read \-p "  Enable automated S3 backups? (y/n) \[y\]: " ENABLE\_BACKUPS  
│   │     if \[\[ "${ENABLE\_BACKUPS:-y}" \=\~ ^\[Yy\] \]\]; then  
│   │       echo "BACKUP\_ENABLED=true" \>\> $ENV\_DIR/master.env  
│   │       \# Detect S3 bucket from instance tags or ask  
│   │       DETECTED\_BUCKET=$(aws s3 ls 2\>/dev/null | grep ai-platform | awk '{print $3}' | head \-1)  
│   │       if \[\[ \-n "$DETECTED\_BUCKET" \]\]; then  
│   │         read \-p "  S3 bucket \[$DETECTED\_BUCKET\]: " S3\_BUCKET  
│   │         S3\_BUCKET=${S3\_BUCKET:-$DETECTED\_BUCKET}  
│   │       else  
│   │         read \-p "  S3 bucket name: " S3\_BUCKET  
│   │       fi  
│   │       read \-p "  Backup frequency — daily/weekly \[daily\]: " BACKUP\_FREQ  
│   │       BACKUP\_FREQ=${BACKUP\_FREQ:-daily}  
│   │       read \-p "  Retention days \[30\]: " BACKUP\_RETENTION  
│   │       BACKUP\_RETENTION=${BACKUP\_RETENTION:-30}  
│   │       echo "S3\_BUCKET=${S3\_BUCKET}" \>\> $ENV\_DIR/master.env  
│   │       echo "BACKUP\_FREQUENCY=${BACKUP\_FREQ}" \>\> $ENV\_DIR/master.env  
│   │       echo "BACKUP\_RETENTION\_DAYS=${BACKUP\_RETENTION}" \>\> $ENV\_DIR/master.env  
│   │     else  
│   │       echo "BACKUP\_ENABLED=false" \>\> $ENV\_DIR/master.env  
│   │     fi  
│   │  
│   └── 8h. Confirmation Summary:  
│         echo ""  
│         echo "════════════════════════════════════════════════════════"  
│         echo "  CONFIGURATION SUMMARY"  
│         echo "════════════════════════════════════════════════════════"  
│         echo ""  
│         echo "  Instance:     $(grep INSTANCE\_TYPE $ENV\_DIR/master.env | cut \-d= \-f2)"  
│         echo "  GPU:          $(grep GPU\_NAME $ENV\_DIR/master.env | cut \-d= \-f2)"  
│         echo "  Data Volume:  $DATA\_DIR ($(df \-BG $DATA\_DIR | awk 'NR==2{print $2}'))"  
│         echo ""  
│         echo "  Services:     $(grep ENABLED\_SERVICES $ENV\_DIR/master.env | cut \-d= \-f2 | tr ',' '\\n' | sed 's/^/    ✓ /')"  
│         echo ""  
│         echo "  Vector DB:    $(grep VECTOR\_DB= $ENV\_DIR/master.env | cut \-d= \-f2)"  
│         echo "  Model Tier:   $(grep MODEL\_TIER $ENV\_DIR/master.env | cut \-d= \-f2)"  
│         echo "  Domain:       $(grep BASE\_DOMAIN $ENV\_DIR/master.env | cut \-d= \-f2)"  
│         echo "  Domain Mode:  $(grep DOMAIN\_MODE $ENV\_DIR/master.env | cut \-d= \-f2)"  
│         echo "  GDrive Sync:  $(grep GDRIVE\_ENABLED $ENV\_DIR/master.env | cut \-d= \-f2)"  
│         echo "  S3 Backups:   $(grep BACKUP\_ENABLED $ENV\_DIR/master.env | cut \-d= \-f2)"  
│         echo ""  
│         echo "  API Keys configured:"  
│         grep \-c "\_API\_KEY=" $ENV\_DIR/master.env | xargs \-I{} echo "    {} provider keys set"  
│         echo ""  
│         echo "════════════════════════════════════════════════════════"  
│         echo ""  
│         read \-p "  Proceed with this configuration? (y/n) \[y\]: " CONFIRM  
│         if \[\[ \! "${CONFIRM:-y}" \=\~ ^\[Yy\] \]\]; then  
│           echo "Configuration cancelled. Re-run script to reconfigure."  
│           exit 0  
│         fi  
│  
├── PHASE 9: Generate Credentials  
│   ├── echo "Generating secure credentials..."  
│   ├── Generate all passwords and secrets:  
│   │     POSTGRES\_PASSWORD=$(openssl rand \-base64 32 | tr \-dc 'a-zA-Z0-9' | head \-c 32\)  
│   │     REDIS\_PASSWORD=$(openssl rand \-base64 32 | tr \-dc 'a-zA-Z0-9' | head \-c 32\)  
│   │     LITELLM\_MASTER\_KEY=$(openssl rand \-hex 24\)  
│   │     LITELLM\_SALT\_KEY=$(openssl rand \-hex 24\)  
│   │     N8N\_ENCRYPTION\_KEY=$(openssl rand \-hex 32\)  
│   │     DIFY\_SECRET\_KEY=$(openssl rand \-hex 32\)  
│   │     DIFY\_INIT\_PASSWORD=$(openssl rand \-base64 16 | tr \-dc 'a-zA-Z0-9' | head \-c 16\)  
│   │     FLOWISE\_PASSWORD=$(openssl rand \-base64 16 | tr \-dc 'a-zA-Z0-9' | head \-c 16\)  
│   │     GRAFANA\_ADMIN\_PASSWORD=$(openssl rand \-base64 16 | tr \-dc 'a-zA-Z0-9' | head \-c 16\)  
│   │     PORTAINER\_ADMIN\_PASSWORD=$(openssl rand \-base64 16 | tr \-dc 'a-zA-Z0-9' | head \-c 16\)  
│   │     SUPERTOKENS\_API\_KEY=$(openssl rand \-hex 24\)  
│   │     ANYTHINGLLM\_API\_KEY=$(openssl rand \-hex 24\)  
│   │     QDRANT\_API\_KEY=$(openssl rand \-hex 24\)  
│   │     WEAVIATE\_API\_KEY=$(openssl rand \-hex 24\)  
│   │     MILVUS\_TOKEN=$(openssl rand \-hex 24\)  
│   │     JWT\_SECRET=$(openssl rand \-hex 32\)  
│   │     WEBHOOK\_SECRET=$(openssl rand \-hex 16\)  
│   │  
│   ├── Write all to master.env:  
│   │     cat \>\> $ENV\_DIR/master.env \<\< EOF  
│   │       
│   │     \# ── Generated Credentials ──  
│   │     POSTGRES\_USER=aiplatform  
│   │     POSTGRES\_PASSWORD=${POSTGRES\_PASSWORD}  
│   │     POSTGRES\_HOST=postgres  
│   │     POSTGRES\_PORT=5432  
│   │     REDIS\_PASSWORD=${REDIS\_PASSWORD}  
│   │     REDIS\_HOST=redis  
│   │     REDIS\_PORT=6379  
│   │     LITELLM\_MASTER\_KEY=sk-${LITELLM\_MASTER\_KEY}  
│   │     LITELLM\_SALT\_KEY=${LITELLM\_SALT\_KEY}  
│   │     N8N\_ENCRYPTION\_KEY=${N8N\_ENCRYPTION\_KEY}  
│   │     DIFY\_SECRET\_KEY=${DIFY\_SECRET\_KEY}  
│   │     DIFY\_INIT\_PASSWORD=${DIFY\_INIT\_PASSWORD}  
│   │     FLOWISE\_USERNAME=admin  
│   │     FLOWISE\_PASSWORD=${FLOWISE\_PASSWORD}  
│   │     GRAFANA\_ADMIN\_USER=admin  
│   │     GRAFANA\_ADMIN\_PASSWORD=${GRAFANA\_ADMIN\_PASSWORD}  
│   │     PORTAINER\_ADMIN\_PASSWORD=${PORTAINER\_ADMIN\_PASSWORD}  
│   │     SUPERTOKENS\_API\_KEY=${SUPERTOKENS\_API\_KEY}  
│   │     ANYTHINGLLM\_API\_KEY=${ANYTHINGLLM\_API\_KEY}  
│   │     QDRANT\_API\_KEY=${QDRANT\_API\_KEY}  
│   │     WEAVIATE\_API\_KEY=${WEAVIATE\_API\_KEY}  
│   │     MILVUS\_TOKEN=${MILVUS\_TOKEN}  
│   │     JWT\_SECRET=${JWT\_SECRET}  
│   │     WEBHOOK\_SECRET=${WEBHOOK\_SECRET}  
│   │     EOF  
│   │  
│   ├── Create human-readable credentials file:  
│   │     cat \> $ENV\_DIR/credentials.txt \<\< EOF  
│   │     ╔══════════════════════════════════════════════════════╗  
│   │     ║       AI PLATFORM CREDENTIALS — SAVE THIS FILE      ║  
│   │     ╠══════════════════════════════════════════════════════╣  
│   │     ║                                                      ║  
│   │     ║  PostgreSQL:                                         ║  
│   │     ║    User:     aiplatform                              ║  
│   │     ║    Password: ${POSTGRES\_PASSWORD}                    ║  
│   │     ║                                                      ║  
│   │     ║  Redis:                                              ║  
│   │     ║    Password: ${REDIS\_PASSWORD}                       ║  
│   │     ║                                                      ║  
│   │     ║  LiteLLM:                                            ║  
│   │     ║    Master Key: sk-${LITELLM\_MASTER\_KEY}              ║  
│   │     ║                                                      ║  
│   │     ║  Dify:                                               ║  
│   │     ║    Init Password: ${DIFY\_INIT\_PASSWORD}              ║  
│   │     ║    URL: https://${DIFY\_DOMAIN:-dify.localhost}       ║  
│   │     ║                                                      ║  
│   │     ║  n8n:                                                ║  
│   │     ║    URL: https://${N8N\_DOMAIN:-n8n.localhost}         ║  
│   │     ║    (Set password on first login)                     ║  
│   │     ║                                                      ║  
│   │     ║  Open WebUI:                                         ║  
│   │     ║    URL: https://${WEBUI\_DOMAIN:-webui.localhost}     ║  
│   │     ║    (Set password on first login)                     ║  
│   │     ║                                                      ║  
│   │     ║  Flowise:                                            ║  
│   │     ║    User:     admin                                   ║  
│   │     ║    Password: ${FLOWISE\_PASSWORD}                     ║  
│   │     ║    URL: https://${FLOWISE\_DOMAIN:-flowise.localhost} ║  
│   │     ║                                                      ║  
│   │     ║  Grafana:                                            ║  
│   │     ║    User:     admin                                   ║  
│   │     ║    Password: ${GRAFANA\_ADMIN\_PASSWORD}               ║  
│   │     ║    URL: https://${GRAFANA\_DOMAIN:-grafana.localhost} ║  
│   │     ║                                                      ║  
│   │     ║  Portainer:                                          ║  
│   │     ║    Password: ${PORTAINER\_ADMIN\_PASSWORD}             ║  
│   │     ║    URL: https://${PORTAINER\_DOMAIN:-portainer.localhost}║  
│   │     ║                                                      ║  
│   │     ╚══════════════════════════════════════════════════════╝  
│   │       
│   │     Generated: $(date \-u \+"%Y-%m-%dT%H:%M:%SZ")  
│   │       
│   │     ⚠  BACK UP THIS FILE SECURELY AND DELETE FROM SERVER  
│   │     EOF  
│   │     chmod 600 $ENV\_DIR/credentials.txt  
│   │  
│   └── echo "Credentials saved to $ENV\_DIR/credentials.txt"  
│       echo "⚠  Copy this file to a secure location, then delete it from the server"  
│  
├── PHASE 10: Create PostgreSQL Init Script  
│   ├── Generate database initialization SQL:  
│   │     cat \> $CONFIG\_DIR/postgres/init-databases.sql \<\< 'EOF'  
│   │     \-- Create databases for each service  
│   │     CREATE DATABASE dify OWNER aiplatform;  
│   │     CREATE DATABASE n8n OWNER aiplatform;  
│   │     CREATE DATABASE litellm OWNER aiplatform;  
│   │     CREATE DATABASE flowise OWNER aiplatform;  
│   │     CREATE DATABASE supertokens OWNER aiplatform;  
│   │     CREATE DATABASE anythingllm OWNER aiplatform;  
│   │     CREATE DATABASE openclaw OWNER aiplatform;  
│   │       
│   │     \-- Enable extensions  
│   │     \\c dify  
│   │     CREATE EXTENSION IF NOT EXISTS "uuid-ossp";  
│   │     CREATE EXTENSION IF NOT EXISTS "vector";  
│   │       
│   │     \\c litellm  
│   │     CREATE EXTENSION IF NOT EXISTS "uuid-ossp";  
│   │       
│   │     \\c n8n  
│   │     CREATE EXTENSION IF NOT EXISTS "uuid-ossp";  
│   │     EOF  
│   │  
│   └── Note: Only creates DBs for enabled services — Script 2 filters  
│  
├── PHASE 11: Set Script 2 Ready Flag  
│   ├── echo "SCRIPT\_1\_COMPLETED=$(date \-u \+%Y-%m-%dT%H:%M:%SZ)" \>\> $ENV\_DIR/master.env  
│   ├── echo "SCRIPT\_1\_VERSION=1.0.0" \>\> $ENV\_DIR/master.env  
│   │  
│   ├── Calculate duration:  
│   │     END\_TIME=$(date \+%s)  
│   │     DURATION=$((END\_TIME \- START\_TIME))  
│   │     MINUTES=$((DURATION / 60))  
│   │     SECONDS=$((DURATION % 60))  
│   │  
│   └── Final output:  
│         echo ""  
│         echo "════════════════════════════════════════════════════════"  
│         echo "  ✓ SCRIPT 1 COMPLETE  (${MINUTES}m ${SECONDS}s)"  
│         echo "════════════════════════════════════════════════════════"  
│         echo ""  
│         echo "  System packages:     ✓ Installed"  
│         echo "  Docker:              ✓ $(docker \--version | awk '{print $3}')"  
│         echo "  Docker Compose:      ✓ $(docker compose version \--short)"  
│         echo "  GPU:                 $(if \[\[ $HAS\_GPU \== true \]\]; then echo "✓ $GPU\_NAME ($GPU\_MEMORY)"; else echo "✗ Not detected (CPU mode)"; fi)"  
│         echo "  Ollama:              ✓ Running on :11434"  
│         echo "  Data volume:         ✓ $DATA\_DIR ($(df \-BG $DATA\_DIR | awk 'NR==2{print $4}') free)"  
│         echo "  Configuration:       ✓ $ENV\_DIR/master.env"  
│         echo "  Credentials:         ✓ $ENV\_DIR/credentials.txt"  
│         echo ""  
│         echo "  NEXT STEP:"  
│         echo "    sudo bash /opt/ai-platform/scripts/script-2-deploy.sh"  
│         echo ""  
│         echo "════════════════════════════════════════════════════════"  
│  
└── PHASE 12: Reboot Check  
    ├── \# Reboot needed if NVIDIA drivers were freshly installed  
    ├── if \[\[ "$NVIDIA\_FRESH\_INSTALL" \== "true" \]\]; then  
    │     echo ""  
    │     echo "⚠  NVIDIA drivers were installed — REBOOT REQUIRED"  
    │     echo ""  
    │     read \-p "Reboot now? (y/n) \[y\]: " REBOOT  
    │     if \[\[ "${REBOOT:-y}" \=\~ ^\[Yy\] \]\]; then  
    │       echo "Rebooting in 5 seconds... After reboot, run Script 2."  
    │       sleep 5  
    │       reboot  
    │     else  
    │       echo "Please reboot manually before running Script 2:"  
    │       echo "  sudo reboot"  
    │     fi  
    └── fi

### **Final master.env After Script 1 (Example)**

\# AI Platform Master Configuration  
\# Generated: 2025-01-15T10:30:00Z  
\# Script 1 version: 1.0.0

\# Paths  
BASE\_DIR=/opt/ai-platform  
DATA\_DIR=/mnt/data  
CONFIG\_DIR=/opt/ai-platform/config  
ENV\_DIR=/opt/ai-platform/env  
LOG\_DIR=/var/log/ai-platform

\# Instance Info  
INSTANCE\_TYPE=g4dn.2xlarge  
INSTANCE\_ID=i-0abc123def456  
PUBLIC\_IP=54.123.45.67  
REGION=us-east-1

\# Hardware Detection  
HAS\_GPU=true  
NVIDIA\_DRIVER\_VERSION=535.104.12  
GPU\_NAME=Tesla T4  
GPU\_MEMORY=15360 MiB  
DOCKER\_VERSION=24.0.7

\# Ollama  
OLLAMA\_BASE\_URL=http://host.docker.internal:11434  
RCLONE\_INSTALLED=true

\# Service Selection  
ENABLED\_SERVICES=postgres,redis,litellm,caddy,portainer,dify,n8n,open-webui,flowise,monitoring

\# Vector DB  
VECTOR\_DB=qdrant  
VECTOR\_DB\_HOST=qdrant  
VECTOR\_DB\_PORT=6333

\# Model Tier  
MODEL\_TIER=standard

\# Domain  
BASE\_DOMAIN=ai.example.com  
ACME\_EMAIL=admin@example.com  
DOMAIN\_MODE=production  
DIFY\_DOMAIN=dify.ai.example.com  
N8N\_DOMAIN=n8n.ai.example.com  
WEBUI\_DOMAIN=webui.ai.example.com  
FLOWISE\_DOMAIN=flowise.ai.example.com  
LITELLM\_DOMAIN=llm.ai.example.com  
GRAFANA\_DOMAIN=grafana.ai.example.com  
PORTAINER\_DOMAIN=portainer.ai.example.com

\# Google Drive  
GDRIVE\_ENABLED=true  
GDRIVE\_CLIENT\_ID=xxxxx.apps.googleusercontent.com  
GDRIVE\_CLIENT\_SECRET=GOCSPX-xxxxx  
GDRIVE\_FOLDER=root  
GDRIVE\_INTERVAL=60  
GDRIVE\_SYNC\_DIR=/mnt/data/gdrive

\# Backups  
BACKUP\_ENABLED=true  
S3\_BUCKET=ai-platform-backups-abc123  
BACKUP\_FREQUENCY=daily  
BACKUP\_RETENTION\_DAYS=30

\# External API Keys  
OPENAI\_API\_KEY=sk-xxxxx  
ANTHROPIC\_API\_KEY=sk-ant-xxxxx  
GOOGLE\_AI\_API\_KEY=AIzaSyxxxxx

\# ── Generated Credentials ──  
POSTGRES\_USER=aiplatform  
POSTGRES\_PASSWORD=aB3xK9mP2qR7sT4vW6yZ8nL1cD5fG0h  
POSTGRES\_HOST=postgres  
POSTGRES\_PORT=5432  
REDIS\_PASSWORD=jH2kM4nP6qS8tV0wX3yA5bC7dF9gI1lE  
REDIS\_HOST=redis  
REDIS\_PORT=6379  
LITELLM\_MASTER\_KEY=sk-a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6  
LITELLM\_SALT\_KEY=f6e5d4c3b2a1f6e5d4c3b2a1f6e5d4c3b2a1f6e5d4c3b2a1  
N8N\_ENCRYPTION\_KEY=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef  
DIFY\_SECRET\_KEY=fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210  
DIFY\_INIT\_PASSWORD=xK9mP2qR7sT4vW6y  
FLOWISE\_USERNAME=admin  
FLOWISE\_PASSWORD=aB3xK9mP2qR7sT4v  
GRAFANA\_ADMIN\_USER=admin  
GRAFANA\_ADMIN\_PASSWORD=W6yZ8nL1cD5fG0hJ  
PORTAINER\_ADMIN\_PASSWORD=2kM4nP6qS8tV0wX3  
SUPERTOKENS\_API\_KEY=a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6  
ANYTHINGLLM\_API\_KEY=b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1  
QDRANT\_API\_KEY=c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2  
JWT\_SECRET=d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5  
WEBHOOK\_SECRET=e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2

\# Script Tracking  
SCRIPT\_1\_COMPLETED=2025-01-15T10:45:23Z  
SCRIPT\_1\_VERSION=1.0.0  
\---

\#\# 16\. Script 2 — Docker Compose Generation & Deployment

\#\#\# Script Overview

script-2-deploy.sh │ ├── Pre-flight Checks ├── PHASE 1: Validate Script 1 completion ├── PHASE 2: Source master.env ├── PHASE 3: Generate per-service environment files ├── PHASE 4: Generate LiteLLM config (litellm\_config.yaml) ├── PHASE 5: Generate Caddyfile ├── PHASE 6: Generate docker-compose.yml (dynamic, based on ENABLED\_SERVICES) ├── PHASE 7: Generate monitoring configs (Prometheus, Grafana) ├── PHASE 8: Pull Docker images ├── PHASE 9: Start core infrastructure (postgres, redis) ├── PHASE 10: Wait for DB readiness, run init SQL ├── PHASE 11: Start remaining services in dependency order ├── PHASE 12: Pull Ollama models ├── PHASE 13: Configure Google Drive (rclone OAuth \+ systemd timers) ├── PHASE 14: Configure backup cron ├── PHASE 15: Health check all services ├── PHASE 16: Generate convenience scripts └── PHASE 17: Final summary

\#\#\# Pre-flight & Phases 1–2

\`\`\`bash  
\#\!/bin/bash  
set \-euo pipefail

\# ── Constants ──  
BASE\_DIR=/opt/ai-platform  
ENV\_DIR= $ BASE\_DIR/env  
CONFIG\_DIR= $ BASE\_DIR/config  
DATA\_DIR=$(grep DATA\_DIR  $ ENV\_DIR/master.env | cut \-d= \-f2)  
LOG\_FILE=/var/log/ai-platform/script-2.log  
COMPOSE\_DIR= $ BASE\_DIR/docker

START\_TIME=$(date \+%s)

\# ── Logging ──  
mkdir \-p /var/log/ai-platform  
exec \> \>(tee \-a $LOG\_FILE) 2\>&1  
echo "═══════════════════════════════════════════════════"  
echo "  Script 2 — Deploy AI Platform Services"  
echo "  Started: $(date)"  
echo "═══════════════════════════════════════════════════"

\# ── PHASE 1: Validate ──  
if \[\[ \! \-f $ENV\_DIR/master.env \]\]; then  
  echo "ERROR: master.env not found. Run Script 1 first."  
  exit 1  
fi  
if \! grep \-q "SCRIPT\_1\_COMPLETED" $ENV\_DIR/master.env; then  
  echo "ERROR: Script 1 did not complete. Re-run Script 1."  
  exit 1  
fi

\# ── PHASE 2: Source config ──  
set \-a  
source $ENV\_DIR/master.env  
set \+a

echo "Configuration loaded. Deploying services: $ENABLED\_SERVICES"

### **PHASE 3: Generate Per-Service Environment Files**

generate\_env\_files()  
│  
├── postgres.env:  
│     POSTGRES\_USER=${POSTGRES\_USER}  
│     POSTGRES\_PASSWORD=${POSTGRES\_PASSWORD}  
│     POSTGRES\_DB=aiplatform  
│     PGDATA=/var/lib/postgresql/data/pgdata  
│  
├── redis.env:  
│     REDIS\_PASSWORD=${REDIS\_PASSWORD}  
│  
├── litellm.env:  
│     LITELLM\_MASTER\_KEY=${LITELLM\_MASTER\_KEY}  
│     LITELLM\_SALT\_KEY=${LITELLM\_SALT\_KEY}  
│     DATABASE\_URL=postgresql://${POSTGRES\_USER}:${POSTGRES\_PASSWORD}@postgres:5432/litellm  
│     REDIS\_HOST=redis  
│     REDIS\_PORT=6379  
│     REDIS\_PASSWORD=${REDIS\_PASSWORD}  
│     STORE\_MODEL\_IN\_DB=True  
│     OPENAI\_API\_KEY=${OPENAI\_API\_KEY:-}  
│     ANTHROPIC\_API\_KEY=${ANTHROPIC\_API\_KEY:-}  
│     GOOGLE\_AI\_API\_KEY=${GOOGLE\_AI\_API\_KEY:-}  
│     AZURE\_API\_KEY=${AZURE\_API\_KEY:-}  
│     AZURE\_API\_BASE=${AZURE\_API\_BASE:-}  
│     AWS\_ACCESS\_KEY\_ID=${AWS\_ACCESS\_KEY\_ID:-}  
│     AWS\_SECRET\_ACCESS\_KEY=${AWS\_SECRET\_ACCESS\_KEY:-}  
│     AWS\_REGION\_NAME=${AWS\_REGION\_NAME:-}  
│  
├── dify.env (if dify in ENABLED\_SERVICES):  
│     \# Core  
│     MODE=api  
│     LOG\_LEVEL=INFO  
│     SECRET\_KEY=${DIFY\_SECRET\_KEY}  
│     INIT\_PASSWORD=${DIFY\_INIT\_PASSWORD}  
│     CONSOLE\_WEB\_URL=https://${DIFY\_DOMAIN:-dify.localhost}  
│     CONSOLE\_API\_URL=https://${DIFY\_DOMAIN:-dify.localhost}  
│     SERVICE\_API\_URL=https://${DIFY\_DOMAIN:-dify.localhost}  
│     APP\_WEB\_URL=https://${DIFY\_DOMAIN:-dify.localhost}  
│     \# Database  
│     DB\_USERNAME=${POSTGRES\_USER}  
│     DB\_PASSWORD=${POSTGRES\_PASSWORD}  
│     DB\_HOST=postgres  
│     DB\_PORT=5432  
│     DB\_DATABASE=dify  
│     \# Redis  
│     REDIS\_HOST=redis  
│     REDIS\_PORT=6379  
│     REDIS\_PASSWORD=${REDIS\_PASSWORD}  
│     REDIS\_USE\_SSL=false  
│     REDIS\_DB=1  
│     \# Celery (Dify uses separate Redis DBs)  
│     CELERY\_BROKER\_URL=redis://:${REDIS\_PASSWORD}@redis:6379/2  
│     \# Storage  
│     STORAGE\_TYPE=local  
│     STORAGE\_LOCAL\_PATH=/app/api/storage  
│     \# Vector Store — route through selected vector DB  
│     VECTOR\_STORE=${VECTOR\_DB}  
│     $(case  $ VECTOR\_DB in  
│       qdrant)  
│         echo "QDRANT\_URL=http://qdrant:6333"  
│         echo "QDRANT\_API\_KEY= $ {QDRANT\_API\_KEY}"  
│         ;;  
│       weaviate)  
│         echo "WEAVIATE\_ENDPOINT=http://weaviate:8080"  
│         echo "WEAVIATE\_API\_KEY=${WEAVIATE\_API\_KEY}"  
│         ;;  
│       milvus)  
│         echo "MILVUS\_HOST=milvus"  
│         echo "MILVUS\_PORT=19530"  
│         echo "MILVUS\_TOKEN=${MILVUS\_TOKEN}"  
│         ;;  
│     esac)  
│     \# LLM — point Dify at LiteLLM  
│     LITELLM\_API\_BASE=http://litellm:4000  
│     LITELLM\_API\_KEY=${LITELLM\_MASTER\_KEY}  
│  
├── n8n.env (if n8n in ENABLED\_SERVICES):  
│     DB\_TYPE=postgresdb  
│     DB\_POSTGRESDB\_HOST=postgres  
│     DB\_POSTGRESDB\_PORT=5432  
│     DB\_POSTGRESDB\_DATABASE=n8n  
│     DB\_POSTGRESDB\_USER=${POSTGRES\_USER}  
│     DB\_POSTGRESDB\_PASSWORD=${POSTGRES\_PASSWORD}  
│     N8N\_ENCRYPTION\_KEY=${N8N\_ENCRYPTION\_KEY}  
│     N8N\_HOST=0.0.0.0  
│     N8N\_PORT=5678  
│     N8N\_PROTOCOL=https  
│     WEBHOOK\_URL=https://${N8N\_DOMAIN:-n8n.localhost}  
│     N8N\_EDITOR\_BASE\_URL=https://${N8N\_DOMAIN:-n8n.localhost}  
│     GENERIC\_TIMEZONE=UTC  
│     N8N\_METRICS=true  
│     N8N\_DIAGNOSTICS\_ENABLED=false  
│     \# Community nodes  
│     N8N\_COMMUNITY\_PACKAGES\_ENABLED=true  
│     NODE\_FUNCTION\_ALLOW\_EXTERNAL=\*  
│  
├── openwebui.env (if open-webui in ENABLED\_SERVICES):  
│     OLLAMA\_BASE\_URL=${OLLAMA\_BASE\_URL}  
│     OPENAI\_API\_BASE\_URL=http://litellm:4000/v1  
│     OPENAI\_API\_KEY=${LITELLM\_MASTER\_KEY}  
│     WEBUI\_SECRET\_KEY=${JWT\_SECRET}  
│     ENABLE\_SIGNUP=true  
│     DEFAULT\_MODELS=mistral  
│     ENABLE\_RAG\_WEB\_SEARCH=true  
│     RAG\_EMBEDDING\_ENGINE=openai  
│     RAG\_EMBEDDING\_MODEL=nomic-embed-text  
│     RAG\_OPENAI\_API\_BASE\_URL=http://litellm:4000/v1  
│     RAG\_OPENAI\_API\_KEY=${LITELLM\_MASTER\_KEY}  
│     DATA\_DIR=/app/backend/data  
│  
├── flowise.env (if flowise in ENABLED\_SERVICES):  
│     DATABASE\_TYPE=postgres  
│     DATABASE\_HOST=postgres  
│     DATABASE\_PORT=5432  
│     DATABASE\_NAME=flowise  
│     DATABASE\_USER=${POSTGRES\_USER}  
│     DATABASE\_PASSWORD=${POSTGRES\_PASSWORD}  
│     FLOWISE\_USERNAME=${FLOWISE\_USERNAME}  
│     FLOWISE\_PASSWORD=${FLOWISE\_PASSWORD}  
│     APIKEY\_PATH=/root/.flowise  
│     LOG\_LEVEL=info  
│     EXECUTION\_MODE=main  
│  
├── anythingllm.env (if anythingllm in ENABLED\_SERVICES):  
│     STORAGE\_DIR=/app/server/storage  
│     LLM\_PROVIDER=litellm  
│     LITELLM\_BASE\_PATH=http://litellm:4000  
│     LITELLM\_API\_KEY=${LITELLM\_MASTER\_KEY}  
│     EMBEDDING\_ENGINE=native  
│     VECTOR\_DB=${VECTOR\_DB}  
│     $(case  $ VECTOR\_DB in  
│       qdrant) echo "QDRANT\_ENDPOINT=http://qdrant:6333" && echo "QDRANT\_API\_KEY= $ {QDRANT\_API\_KEY}" ;;  
│       weaviate) echo "WEAVIATE\_ENDPOINT=http://weaviate:8080" && echo "WEAVIATE\_API\_KEY=${WEAVIATE\_API\_KEY}" ;;  
│       milvus) echo "MILVUS\_ADDRESS=milvus:19530" && echo "MILVUS\_TOKEN=${MILVUS\_TOKEN}" ;;  
│     esac)  
│     AUTH\_TOKEN=${ANYTHINGLLM\_API\_KEY}  
│     JWT\_SECRET=${JWT\_SECRET}  
│  
├── supertokens.env (if supertokens in ENABLED\_SERVICES):  
│     POSTGRESQL\_CONNECTION\_URI=postgresql://${POSTGRES\_USER}:${POSTGRES\_PASSWORD}@postgres:5432/supertokens  
│     API\_KEYS=${SUPERTOKENS\_API\_KEY}  
│  
└── Write all env files to $ENV\_DIR/\<service\>.env with chmod 600

### **PHASE 4: Generate LiteLLM Config**

generate\_litellm\_config()  
│  
├── cat \> $CONFIG\_DIR/litellm/litellm\_config.yaml \<\< 'YAML'  
│   model\_list:  
│     \# ── Local Ollama Models ──  
│     \# (populated dynamically based on MODEL\_TIER)  
│     
│   YAML  
│  
├── \# Add Ollama models based on tier  
│   cat \>\> $CONFIG\_DIR/litellm/litellm\_config.yaml \<\< YAML  
│     
│     \- model\_name: tinyllama  
│       litellm\_params:  
│         model: ollama/tinyllama  
│         api\_base: ${OLLAMA\_BASE\_URL}  
│     
│     \- model\_name: nomic-embed-text  
│       litellm\_params:  
│         model: ollama/nomic-embed-text  
│         api\_base: ${OLLAMA\_BASE\_URL}  
│   YAML  
│  
│   if \[\[ " $ MODEL\_TIER" \=\~ ^(standard|full|custom) $  \]\]; then  
│     cat \>\> $CONFIG\_DIR/litellm/litellm\_config.yaml \<\< YAML  
│     
│     \- model\_name: mistral  
│       litellm\_params:  
│         model: ollama/mistral  
│         api\_base: ${OLLAMA\_BASE\_URL}  
│     
│     \- model\_name: llama3.1  
│       litellm\_params:  
│         model: ollama/llama3.1:8b  
│         api\_base: ${OLLAMA\_BASE\_URL}  
│     
│     \- model\_name: codellama  
│       litellm\_params:  
│         model: ollama/codellama:7b  
│         api\_base: ${OLLAMA\_BASE\_URL}  
│     YAML  
│   fi  
│  
│   if \[\[ "$MODEL\_TIER" \== "full" \]\]; then  
│     cat \>\> $CONFIG\_DIR/litellm/litellm\_config.yaml \<\< YAML  
│     
│     \- model\_name: llama3.1-70b  
│       litellm\_params:  
│         model: ollama/llama3.1:70b  
│         api\_base: ${OLLAMA\_BASE\_URL}  
│     
│     \- model\_name: mixtral  
│       litellm\_params:  
│         model: ollama/mixtral:8x7b  
│         api\_base: ${OLLAMA\_BASE\_URL}  
│     
│     \- model\_name: deepseek-coder  
│       litellm\_params:  
│         model: ollama/deepseek-coder-v2  
│         api\_base: ${OLLAMA\_BASE\_URL}  
│     YAML  
│   fi  
│  
├── \# Add cloud provider models if API keys present  
│   if \[\[ \-n "${OPENAI\_API\_KEY:-}" \]\]; then  
│     cat \>\>  $ CONFIG\_DIR/litellm/litellm\_config.yaml \<\< YAML  
│     
│     \# ── OpenAI Models ──  
│     \- model\_name: gpt-4o  
│       litellm\_params:  
│         model: openai/gpt-4o  
│         api\_key: os.environ/OPENAI\_API\_KEY  
│     
│     \- model\_name: gpt-4o-mini  
│       litellm\_params:  
│         model: openai/gpt-4o-mini  
│         api\_key: os.environ/OPENAI\_API\_KEY  
│     
│     \- model\_name: gpt-4-turbo  
│       litellm\_params:  
│         model: openai/gpt-4-turbo  
│         api\_key: os.environ/OPENAI\_API\_KEY  
│     
│     \- model\_name: gpt-3.5-turbo  
│       litellm\_params:  
│         model: openai/gpt-3.5-turbo  
│         api\_key: os.environ/OPENAI\_API\_KEY  
│     
│     \- model\_name: text-embedding-3-small  
│       litellm\_params:  
│         model: openai/text-embedding-3-small  
│         api\_key: os.environ/OPENAI\_API\_KEY  
│     
│     \- model\_name: text-embedding-3-large  
│       litellm\_params:  
│         model: openai/text-embedding-3-large  
│         api\_key: os.environ/OPENAI\_API\_KEY  
│     YAML  
│   fi  
│  
│   if \[\[ \-n " $ {ANTHROPIC\_API\_KEY:-}" \]\]; then  
│     cat \>\>  $ CONFIG\_DIR/litellm/litellm\_config.yaml \<\< YAML  
│     
│     \# ── Anthropic Models ──  
│     \- model\_name: claude-3.5-sonnet  
│       litellm\_params:  
│         model: anthropic/claude-3-5-sonnet-20241022  
│         api\_key: os.environ/ANTHROPIC\_API\_KEY  
│     
│     \- model\_name: claude-3-opus  
│       litellm\_params:  
│         model: anthropic/claude-3-opus-20240229  
│         api\_key: os.environ/ANTHROPIC\_API\_KEY  
│     
│     \- model\_name: claude-3-haiku  
│       litellm\_params:  
│         model: anthropic/claude-3-haiku-20240307  
│         api\_key: os.environ/ANTHROPIC\_API\_KEY  
│     YAML  
│   fi  
│  
│   if \[\[ \-n " $ {GOOGLE\_AI\_API\_KEY:-}" \]\]; then  
│     cat \>\>  $ CONFIG\_DIR/litellm/litellm\_config.yaml \<\< YAML  
│     
│     \# ── Google AI Models ──  
│     \- model\_name: gemini-pro  
│       litellm\_params:  
│         model: gemini/gemini-1.5-pro  
│         api\_key: os.environ/GOOGLE\_AI\_API\_KEY  
│     
│     \- model\_name: gemini-flash  
│       litellm\_params:  
│         model: gemini/gemini-1.5-flash  
│         api\_key: os.environ/GOOGLE\_AI\_API\_KEY  
│     YAML  
│   fi  
│  
│   if \[\[ \-n " $ {AWS\_ACCESS\_KEY\_ID:-}" \]\]; then  
│     cat \>\> $CONFIG\_DIR/litellm/litellm\_config.yaml \<\< YAML  
│     
│     \# ── AWS Bedrock Models ──  
│     \- model\_name: bedrock-claude-3.5-sonnet  
│       litellm\_params:  
│         model: bedrock/anthropic.claude-3-5-sonnet-20241022-v2:0  
│     
│     \- model\_name: bedrock-claude-3-haiku  
│       litellm\_params:  
│         model: bedrock/anthropic.claude-3-haiku-20240307-v1:0  
│     YAML  
│   fi  
│  
├── \# Add router settings and general config  
│   cat \>\> $CONFIG\_DIR/litellm/litellm\_config.yaml \<\< YAML  
│     
│   litellm\_settings:  
│     drop\_params: true  
│     set\_verbose: false  
│     cache: true  
│     cache\_params:  
│       type: redis  
│       host: redis  
│       port: 6379  
│       password: ${REDIS\_PASSWORD}  
│     success\_callback: \["prometheus"\]  
│     failure\_callback: \["prometheus"\]  
│     max\_budget: 1000  
│     budget\_duration: monthly  
│     
│   router\_settings:  
│     routing\_strategy: simple-shuffle  
│     num\_retries: 3  
│     timeout: 120  
│     retry\_after: 5  
│     allowed\_fails: 3  
│     cooldown\_time: 60  
│     
│   general\_settings:  
│     master\_key: ${LITELLM\_MASTER\_KEY}  
│     database\_url: postgresql://${POSTGRES\_USER}:${POSTGRES\_PASSWORD}@postgres:5432/litellm  
│     store\_model\_in\_db: true  
│   YAML  
│  
└── echo "LiteLLM config generated with $(grep 'model\_name:' $CONFIG\_DIR/litellm/litellm\_config.yaml | wc \-l) models"

### **PHASE 5: Generate Caddyfile**

generate\_caddyfile()  
│  
├── If DOMAIN\_MODE \== "production":  
│     cat \> $CONFIG\_DIR/caddy/Caddyfile \<\< CADDYFILE  
│     {  
│       email ${ACME\_EMAIL}  
│       acme\_ca https://acme-v02.api.letsencrypt.org/directory  
│     }  
│     CADDYFILE  
│  
├── If DOMAIN\_MODE \== "local":  
│     cat \> $CONFIG\_DIR/caddy/Caddyfile \<\< CADDYFILE  
│     {  
│       auto\_https off  
│     }  
│     CADDYFILE  
│  
├── \# Common snippet for security headers  
│   cat \>\>  $ CONFIG\_DIR/caddy/Caddyfile \<\< 'CADDYFILE'  
│     
│   (security\_headers) {  
│     header {  
│       X-Content-Type-Options nosniff  
│       X-Frame-Options SAMEORIGIN  
│       Referrer-Policy strict-origin-when-cross-origin  
│       X-XSS-Protection "1; mode=block"  
│       \-Server  
│     }  
│   }  
│     
│   (proxy\_defaults) {  
│     header\_up X-Real-IP {remote\_host}  
│     header\_up X-Forwarded-For {remote\_host}  
│     header\_up X-Forwarded-Proto {scheme}  
│   }  
│   CADDYFILE  
│  
├── \# Generate service blocks based on ENABLED\_SERVICES  
│   IFS=',' read \-ra SERVICES \<\<\< " $ ENABLED\_SERVICES"  
│  
│   \# Helper function — add\_service\_block(domain, upstream, options)  
│   add\_service\_block() {  
│     local domain= $ 1  
│     local upstream= $ 2  
│     local websocket=${3:-false}  
│       
│     if \[\[ " $ DOMAIN\_MODE" \== "local" \]\]; then  
│       domain=": $ {4:-80}"  \# Fallback port for local mode  
│     fi  
│       
│     cat \>\> $CONFIG\_DIR/caddy/Caddyfile \<\< CADDYFILE  
│     
│   ${domain} {  
│     import security\_headers  
│     reverse\_proxy ${upstream} {  
│       import proxy\_defaults  
│    $ (if \[\[ " $ websocket" \== "true" \]\]; then echo "    transport http {  
│         keepalive 30s  
│       }"; fi)  
│     }  
│   }  
│   CADDYFILE  
│   }  
│  
│   for service in "${SERVICES\[@\]}"; do  
│     case  $ service in  
│       dify)  
│         add\_service\_block " $ {DIFY\_DOMAIN}" "dify-nginx:80" "false"  
│         ;;  
│       n8n)  
│         add\_service\_block "${N8N\_DOMAIN}" "n8n:5678" "true"  
│         ;;  
│       open-webui)  
│         add\_service\_block "${WEBUI\_DOMAIN}" "open-webui:8080" "true"  
│         ;;  
│       flowise)  
│         add\_service\_block "${FLOWISE\_DOMAIN}" "flowise:3000" "true"  
│         ;;  
│       litellm)  
│         add\_service\_block "${LITELLM\_DOMAIN}" "litellm:4000" "false"  
│         ;;  
│       monitoring)  
│         add\_service\_block "${GRAFANA\_DOMAIN}" "grafana:3000" "true"  
│         ;;  
│       portainer)  
│         add\_service\_block "${PORTAINER\_DOMAIN}" "portainer:9000" "true"  
│         ;;  
│       anythingllm)  
│         add\_service\_block "${ANYTHINGLLM\_DOMAIN}" "anythingllm:3001" "true"  
│         ;;  
│       supertokens)  
│         add\_service\_block "${SUPERTOKENS\_DOMAIN}" "supertokens:3567" "false"  
│         ;;  
│     esac  
│   done  
│  
└── echo "Caddyfile generated for $(grep \-c 'reverse\_proxy' $CONFIG\_DIR/caddy/Caddyfile) services"

### **PHASE 6: Generate docker-compose.yml (Dynamic)**

This is the largest phase. The compose file is **generated dynamically** based on ENABLED\_SERVICES.

generate\_docker\_compose()  
│  
├── \# ── Header ──  
│   cat \> $COMPOSE\_DIR/docker-compose.yml \<\< 'YAML'  
│   \# AI Platform — Auto-generated by Script 2  
│   \# Do not edit manually — regenerate with:  
│   \#   sudo bash /opt/ai-platform/scripts/script-2-deploy.sh \--regenerate  
│     
│   version: "3.8"  
│     
│   x-common-env: \&common-env  
│     TZ: UTC  
│     PUID: 1000  
│     PGID: 1000  
│   YAML  
│  
├── \# ── Networks Section ──  
│   cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< 'YAML'  
│     
│   networks:  
│     ai-platform:  
│       driver: bridge  
│       name: ai-platform  
│     monitoring:  
│       driver: bridge  
│       name: monitoring  
│   YAML  
│  
├── \# ── Volumes Section ──  
│   cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< YAML  
│     
│   volumes:  
│     postgres-data:  
│       driver: local  
│       driver\_opts:  
│         type: none  
│         o: bind  
│         device: ${DATA\_DIR}/postgres  
│     redis-data:  
│       driver: local  
│       driver\_opts:  
│         type: none  
│         o: bind  
│         device: ${DATA\_DIR}/redis  
│     caddy-data:  
│       driver: local  
│       driver\_opts:  
│         type: none  
│         o: bind  
│         device: ${DATA\_DIR}/caddy/data  
│     caddy-config:  
│       driver: local  
│       driver\_opts:  
│         type: none  
│         o: bind  
│         device: ${DATA\_DIR}/caddy/config  
│     portainer-data:  
│       driver: local  
│       driver\_opts:  
│         type: none  
│         o: bind  
│         device: ${DATA\_DIR}/portainer  
│   YAML  
│  
│   \# Add service-specific volumes  
│   if service\_enabled "dify"; then  
│     cat \>\> ... dify-storage volume  
│   fi  
│   if service\_enabled "n8n"; then  
│     cat \>\> ... n8n-data volume  
│   fi  
│   \# ... etc for each service  
│  
├── \# ── Services Section ──  
│   echo "" \>\> $COMPOSE\_DIR/docker-compose.yml  
│   echo "services:" \>\> $COMPOSE\_DIR/docker-compose.yml  
│  
├── \# ── PostgreSQL (always) ──  
│   cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< YAML  
│     
│     postgres:  
│       image: pgvector/pgvector:pg16  
│       container\_name: postgres  
│       restart: unless-stopped  
│       env\_file: ${ENV\_DIR}/postgres.env  
│       volumes:  
│         \- postgres-data:/var/lib/postgresql/data  
│         \- ${CONFIG\_DIR}/postgres/init-databases.sql:/docker-entrypoint-initdb.d/init.sql:ro  
│       ports:  
│         \- "127.0.0.1:5432:5432"  
│       networks:  
│         \- ai-platform  
│       healthcheck:  
│         test: \["CMD-SHELL", "pg\_isready \-U ${POSTGRES\_USER}"\]  
│         interval: 10s  
│         timeout: 5s  
│         retries: 5  
│         start\_period: 30s  
│       deploy:  
│         resources:  
│           limits:  
│             memory: 2G  
│           reservations:  
│             memory: 512M  
│   YAML  
│  
├── \# ── Redis (always) ──  
│   cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< YAML  
│     
│     redis:  
│       image: redis:7-alpine  
│       container\_name: redis  
│       restart: unless-stopped  
│       command: \>  
│         redis-server  
│         \--requirepass ${REDIS\_PASSWORD}  
│         \--maxmemory 1gb  
│         \--maxmemory-policy allkeys-lru  
│         \--appendonly yes  
│         \--appendfsync everysec  
│       volumes:  
│         \- redis-data:/data  
│       ports:  
│         \- "127.0.0.1:6379:6379"  
│       networks:  
│         \- ai-platform  
│       healthcheck:  
│         test: \["CMD", "redis-cli", "-a", "${REDIS\_PASSWORD}", "ping"\]  
│         interval: 10s  
│         timeout: 5s  
│         retries: 5  
│       deploy:  
│         resources:  
│           limits:  
│             memory: 1G  
│   YAML  
│  
├── \# ── LiteLLM (always) ──  
│   cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< YAML  
│     
│     litellm:  
│       image: ghcr.io/berriai/litellm:main-latest  
│       container\_name: litellm  
│       restart: unless-stopped  
│       env\_file: ${ENV\_DIR}/litellm.env  
│       volumes:  
│         \- ${CONFIG\_DIR}/litellm/litellm\_config.yaml:/app/config.yaml:ro  
│       command: \["--config", "/app/config.yaml", "--port", "4000"\]  
│       ports:  
│         \- "127.0.0.1:4000:4000"  
│       networks:  
│         \- ai-platform  
│         \- monitoring  
│       depends\_on:  
│         postgres:  
│           condition: service\_healthy  
│         redis:  
│           condition: service\_healthy  
│       extra\_hosts:  
│         \- "host.docker.internal:host-gateway"  
│       healthcheck:  
│         test: \["CMD", "curl", "-f", "http://localhost:4000/health"\]  
│         interval: 30s  
│         timeout: 10s  
│         retries: 5  
│         start\_period: 45s  
│       deploy:  
│         resources:  
│           limits:  
│             memory: 2G  
│   YAML  
│  
├── \# ── Vector DB (based on VECTOR\_DB selection) ──  
│   case $VECTOR\_DB in  
│     qdrant)  
│       cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< YAML  
│     
│     qdrant:  
│       image: qdrant/qdrant:latest  
│       container\_name: qdrant  
│       restart: unless-stopped  
│       environment:  
│         QDRANT\_\_SERVICE\_\_API\_KEY: ${QDRANT\_API\_KEY}  
│         QDRANT\_\_STORAGE\_\_STORAGE\_PATH: /qdrant/storage  
│         QDRANT\_\_SERVICE\_\_GRPC\_PORT: 6334  
│       volumes:  
│         \- ${DATA\_DIR}/qdrant/storage:/qdrant/storage  
│         \- ${DATA\_DIR}/qdrant/snapshots:/qdrant/snapshots  
│       ports:  
│         \- "127.0.0.1:6333:6333"  
│         \- "127.0.0.1:6334:6334"  
│       networks:  
│         \- ai-platform  
│       healthcheck:  
│         test: \["CMD", "curl", "-f", "http://localhost:6333/healthz"\]  
│         interval: 30s  
│         timeout: 10s  
│         retries: 3  
│       deploy:  
│         resources:  
│           limits:  
│             memory: 4G  
│   YAML  
│       ;;  
│     weaviate)  
│       cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< YAML  
│     
│     weaviate:  
│       image: semitechnologies/weaviate:latest  
│       container\_name: weaviate  
│       restart: unless-stopped  
│       environment:  
│         QUERY\_DEFAULTS\_LIMIT: 25  
│         AUTHENTICATION\_APIKEY\_ENABLED: "true"  
│         AUTHENTICATION\_APIKEY\_ALLOWED\_KEYS: ${WEAVIATE\_API\_KEY}  
│         AUTHENTICATION\_APIKEY\_USERS: admin  
│         PERSISTENCE\_DATA\_PATH: /var/lib/weaviate  
│         DEFAULT\_VECTORIZER\_MODULE: none  
│         CLUSTER\_HOSTNAME: weaviate-node1  
│       volumes:  
│         \- ${DATA\_DIR}/weaviate:/var/lib/weaviate  
│       ports:  
│         \- "127.0.0.1:8080:8080"  
│         \- "127.0.0.1:50051:50051"  
│       networks:  
│         \- ai-platform  
│       healthcheck:  
│         test: \["CMD", "curl", "-f", "http://localhost:8080/v1/.well-known/ready"\]  
│         interval: 30s  
│         timeout: 10s  
│         retries: 3  
│       deploy:  
│         resources:  
│           limits:  
│             memory: 4G  
│   YAML  
│       ;;  
│     milvus)  
│       cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< YAML  
│     
│     etcd:  
│       image: quay.io/coreos/etcd:v3.5.11  
│       container\_name: milvus-etcd  
│       restart: unless-stopped  
│       environment:  
│         ETCD\_AUTO\_COMPACTION\_MODE: revision  
│         ETCD\_AUTO\_COMPACTION\_RETENTION: "1000"  
│         ETCD\_QUOTA\_BACKEND\_BYTES: "4294967296"  
│         ETCD\_SNAPSHOT\_COUNT: "50000"  
│       volumes:  
│         \- ${DATA\_DIR}/milvus/etcd:/etcd  
│       command: \>  
│         etcd  
│         \-advertise-client-urls=http://127.0.0.1:2379  
│         \-listen-client-urls=http://0.0.0.0:2379  
│         \--data-dir /etcd  
│       networks:  
│         \- ai-platform  
│       healthcheck:  
│         test: \["CMD", "etcdctl", "endpoint", "health"\]  
│         interval: 30s  
│         timeout: 20s  
│         retries: 3  
│     
│     minio-milvus:  
│       image: minio/minio:latest  
│       container\_name: milvus-minio  
│       restart: unless-stopped  
│       environment:  
│         MINIO\_ACCESS\_KEY: minioadmin  
│         MINIO\_SECRET\_KEY: minioadmin  
│       volumes:  
│         \- ${DATA\_DIR}/milvus/minio:/minio\_data  
│       command: minio server /minio\_data \--console-address ":9001"  
│       networks:  
│         \- ai-platform  
│       healthcheck:  
│         test: \["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"\]  
│         interval: 30s  
│         timeout: 20s  
│         retries: 3  
│     
│     milvus:  
│       image: milvusdb/milvus:v2.4-latest  
│       container\_name: milvus  
│       restart: unless-stopped  
│       environment:  
│         ETCD\_ENDPOINTS: etcd:2379  
│         MINIO\_ADDRESS: minio-milvus:9000  
│         COMMON\_SECURITY\_AUTHORIZATIONENABLED: "true"  
│       volumes:  
│         \- ${DATA\_DIR}/milvus/data:/var/lib/milvus  
│       ports:  
│         \- "127.0.0.1:19530:19530"  
│         \- "127.0.0.1:9091:9091"  
│       networks:  
│         \- ai-platform  
│       depends\_on:  
│         etcd:  
│           condition: service\_healthy  
│         minio-milvus:  
│           condition: service\_healthy  
│       healthcheck:  
│         test: \["CMD", "curl", "-f", "http://localhost:9091/healthz"\]  
│         interval: 30s  
│         timeout: 10s  
│         retries: 3  
│       deploy:  
│         resources:  
│           limits:  
│             memory: 4G  
│   YAML  
│       ;;  
│   esac  
│  
├── \# ── Dify (if enabled) ──  
│   if service\_enabled "dify"; then  
│     cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< YAML  
│     
│     dify-api:  
│       image: langgenius/dify-api:latest  
│       container\_name: dify-api  
│       restart: unless-stopped  
│       env\_file: ${ENV\_DIR}/dify.env  
│       volumes:  
│         \- ${DATA\_DIR}/dify/storage:/app/api/storage  
│       networks:  
│         \- ai-platform  
│       depends\_on:  
│         postgres:  
│           condition: service\_healthy  
│         redis:  
│           condition: service\_healthy  
│       extra\_hosts:  
│         \- "host.docker.internal:host-gateway"  
│       healthcheck:  
│         test: \["CMD", "curl", "-f", "http://localhost:5001/health"\]  
│         interval: 30s  
│         timeout: 10s  
│         retries: 5  
│         start\_period: 60s  
│       deploy:  
│         resources:  
│           limits:  
│             memory: 2G  
│     
│     dify-worker:  
│       image: langgenius/dify-api:latest  
│       container\_name: dify-worker  
│       restart: unless-stopped  
│       env\_file: ${ENV\_DIR}/dify.env  
│       environment:  
│         MODE: worker  
│       volumes:  
│         \- ${DATA\_DIR}/dify/storage:/app/api/storage  
│       networks:  
│         \- ai-platform  
│       depends\_on:  
│         postgres:  
│           condition: service\_healthy  
│         redis:  
│           condition: service\_healthy  
│       deploy:  
│         resources:  
│           limits:  
│             memory: 2G  
│     
│     dify-web:  
│       image: langgenius/dify-web:latest  
│       container\_name: dify-web  
│       restart: unless-stopped  
│       environment:  
│         CONSOLE\_API\_URL: https://${DIFY\_DOMAIN}  
│         APP\_API\_URL: https://${DIFY\_DOMAIN}  
│         SENTRY\_DSN: ""  
│       networks:  
│         \- ai-platform  
│     
│     dify-nginx:  
│       image: nginx:alpine  
│       container\_name: dify-nginx  
│       restart: unless-stopped  
│       volumes:  
│         \- ${CONFIG\_DIR}/dify/nginx.conf:/etc/nginx/nginx.conf:ro  
│       networks:  
│         \- ai-platform  
│       depends\_on:  
│         \- dify-api  
│         \- dify-web  
│   YAML  
│   fi  
│  
├── \# ── n8n (if enabled) ──  
│   if service\_enabled "n8n"; then  
│     cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< YAML  
│     
│     n8n:  
│       image: n8nio/n8n:latest  
│       container\_name: n8n  
│       restart: unless-stopped  
│       env\_file: ${ENV\_DIR}/n8n.env  
│       volumes:  
│         \- ${DATA\_DIR}/n8n:/home/node/.n8n  
│       networks:  
│         \- ai-platform  
│       depends\_on:  
│         postgres:  
│           condition: service\_healthy  
│         redis:  
│           condition: service\_healthy  
│       extra\_hosts:  
│         \- "host.docker.internal:host-gateway"  
│       healthcheck:  
│         test: \["CMD-SHELL", "wget \-qO- http://localhost:5678/healthz || exit 1"\]  
│         interval: 30s  
│         timeout: 10s  
│         retries: 5  
│         start\_period: 30s  
│       deploy:  
│         resources:  
│           limits:  
│             memory: 2G  
│   YAML  
│   fi  
│  
├── \# ── Open WebUI (if enabled) ──  
│   if service\_enabled "open-webui"; then  
│     cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< YAML  
│     
│     open-webui:  
│       image: ghcr.io/open-webui/open-webui:main  
│       container\_name: open-webui  
│       restart: unless-stopped  
│       env\_file: ${ENV\_DIR}/openwebui.env  
│       volumes:  
│         \- ${DATA\_DIR}/open-webui:/app/backend/data  
│       networks:  
│         \- ai-platform  
│       extra\_hosts:  
│         \- "host.docker.internal:host-gateway"  
│       depends\_on:  
│         litellm:  
│           condition: service\_healthy  
│       healthcheck:  
│         test: \["CMD", "curl", "-f", "http://localhost:8080/health"\]  
│         interval: 30s  
│         timeout: 10s  
│         retries: 5  
│         start\_period: 30s  
│       deploy:  
│         resources:  
│           limits:  
│             memory: 2G  
│   YAML  
│   fi  
│  
├── \# ── Flowise (if enabled) ──  
│   if service\_enabled "flowise"; then  
│     cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< YAML  
│     
│     flowise:  
│       image: flowiseai/flowise:latest  
│       container\_name: flowise  
│       restart: unless-stopped  
│       env\_file: ${ENV\_DIR}/flowise.env  
│       volumes:  
│         \- ${DATA\_DIR}/flowise:/root/.flowise  
│       networks:  
│         \- ai-platform  
│       depends\_on:  
│         postgres:  
│           condition: service\_healthy  
│       extra\_hosts:  
│         \- "host.docker.internal:host-gateway"  
│       healthcheck:  
│         test: \["CMD", "curl", "-f", "http://localhost:3000"\]  
│         interval: 30s  
│         timeout: 10s  
│         retries: 5  
│         start\_period: 30s  
│       deploy:  
│         resources:  
│           limits:  
│             memory: 2G  
│   YAML  
│   fi  
│  
├── \# ── AnythingLLM (if enabled) ──  
│   if service\_enabled "anythingllm"; then  
│     cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< YAML  
│     
│     anythingllm:  
│       image: mintplexlabs/anythingllm:latest  
│       container\_name: anythingllm  
│       restart: unless-stopped  
│       env\_file: ${ENV\_DIR}/anythingllm.env  
│       volumes:  
│         \- ${DATA\_DIR}/anythingllm:/app/server/storage  
│       networks:  
│         \- ai-platform  
│       extra\_hosts:  
│         \- "host.docker.internal:host-gateway"  
│       healthcheck:  
│         test: \["CMD", "curl", "-f", "http://localhost:3001/api/ping"\]  
│         interval: 30s  
│         timeout: 10s  
│         retries: 5  
│       deploy:  
│         resources:  
│           limits:  
│             memory: 2G  
│   YAML  
│   fi  
│  
├── \# ── SuperTokens (if enabled) ──  
│   if service\_enabled "supertokens"; then  
│     cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< YAML  
│     
│     supertokens:  
│       image: registry.supertokens.io/supertokens/supertokens-postgresql:latest  
│       container\_name: supertokens  
│       restart: unless-stopped  
│       env\_file: ${ENV\_DIR}/supertokens.env  
│       networks:  
│         \- ai-platform  
│       depends\_on:  
│         postgres:  
│           condition: service\_healthy  
│       ports:  
│         \- "127.0.0.1:3567:3567"  
│       healthcheck:  
│         test: \["CMD", "curl", "-f", "http://localhost:3567/hello"\]  
│         interval: 30s  
│         timeout: 10s  
│         retries: 3  
│   YAML  
│   fi  
│  
├── \# ── Caddy (always) ──  
│   cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< YAML  
│     
│     caddy:  
│       image: caddy:2-alpine  
│       container\_name: caddy  
│       restart: unless-stopped  
│       ports:  
│         \- "80:80"  
│         \- "443:443"  
│         \- "443:443/udp"  
│       volumes:  
│         \- ${CONFIG\_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro  
│         \- caddy-data:/data  
│         \- caddy-config:/config  
│       networks:  
│         \- ai-platform  
│       healthcheck:  
│         test: \["CMD", "caddy", "validate", "--config", "/etc/caddy/Caddyfile"\]  
│         interval: 60s  
│         timeout: 10s  
│         retries: 3  
│       deploy:  
│         resources:  
│           limits:  
│             memory: 512M  
│   YAML  
│  
├── \# ── Portainer (always) ──  
│   cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< YAML  
│     
│     portainer:  
│       image: portainer/portainer-ce:latest  
│       container\_name: portainer  
│       restart: unless-stopped  
│       volumes:  
│         \- /var/run/docker.sock:/var/run/docker.sock:ro  
│         \- portainer-data:/data  
│       networks:  
│         \- ai-platform  
│       healthcheck:  
│         test: \["CMD", "wget", "-qO-", "http://localhost:9000/api/system/status"\]  
│         interval: 30s  
│         timeout: 10s  
│         retries: 3  
│       deploy:  
│         resources:  
│           limits:  
│             memory: 512M  
│   YAML  
│  
├── \# ── Monitoring Stack (if enabled) ──  
│   if service\_enabled "monitoring"; then  
│     cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< YAML  
│     
│     prometheus:  
│       image: prom/prometheus:latest  
│       container\_name: prometheus  
│       restart: unless-stopped  
│       command:  
│         \- '--config.file=/etc/prometheus/prometheus.yml'  
│         \- '--storage.tsdb.path=/prometheus'  
│         \- '--storage.tsdb.retention.time=30d'  
│         \- '--web.console.libraries=/etc/prometheus/console\_libraries'  
│         \- '--web.console.templates=/etc/prometheus/consoles'  
│       volumes:  
│         \- ${CONFIG\_DIR}/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro  
│         \- ${DATA\_DIR}/prometheus:/prometheus  
│       networks:  
│         \- ai-platform  
│         \- monitoring  
│       healthcheck:  
│         test: \["CMD", "wget", "-qO-", "http://localhost:9090/-/healthy"\]  
│         interval: 30s  
│         timeout: 10s  
│         retries: 3  
│       deploy:  
│         resources:  
│           limits:  
│             memory: 1G  
│     
│     grafana:  
│       image: grafana/grafana:latest  
│       container\_name: grafana  
│       restart: unless-stopped  
│       environment:  
│         GF\_SECURITY\_ADMIN\_USER: ${GRAFANA\_ADMIN\_USER}  
│         GF\_SECURITY\_ADMIN\_PASSWORD: ${GRAFANA\_ADMIN\_PASSWORD}  
│         GF\_USERS\_ALLOW\_SIGN\_UP: "false"  
│         GF\_SERVER\_ROOT\_URL: https://${GRAFANA\_DOMAIN:-grafana.localhost}  
│       volumes:  
│         \- ${DATA\_DIR}/grafana:/var/lib/grafana  
│         \- ${CONFIG\_DIR}/grafana/provisioning:/etc/grafana/provisioning:ro  
│         \- ${CONFIG\_DIR}/grafana/dashboards:/var/lib/grafana/dashboards:ro  
│       networks:  
│         \- ai-platform  
│         \- monitoring  
│       depends\_on:  
│         \- prometheus  
│       healthcheck:  
│         test: \["CMD", "curl", "-f", "http://localhost:3000/api/health"\]  
│         interval: 30s  
│         timeout: 10s  
│         retries: 3  
│       deploy:  
│         resources:  
│           limits:  
│             memory: 512M  
│     
│     node-exporter:  
│       image: prom/node-exporter:latest  
│       container\_name: node-exporter  
│       restart: unless-stopped  
│       command:  
│         \- '--path.procfs=/host/proc'  
│         \- '--path.rootfs=/rootfs'  
│         \- '--path.sysfs=/host/sys'  
│         \- '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'  
│       volumes:  
│         \- /proc:/host/proc:ro  
│         \- /sys:/host/sys:ro  
│         \- /:/rootfs:ro  
│       networks:  
│         \- monitoring  
│       deploy:  
│         resources:  
│           limits:  
│             memory: 128M  
│     
│     cadvisor:  
│       image: gcr.io/cadvisor/cadvisor:latest  
│       container\_name: cadvisor  
│       restart: unless-stopped  
│       privileged: true  
│       devices:  
│         \- /dev/kmsg:/dev/kmsg  
│       volumes:  
│         \- /:/rootfs:ro  
│         \- /var/run:/var/run:ro  
│         \- /sys:/sys:ro  
│         \- /var/lib/docker/:/var/lib/docker:ro  
│       networks:  
│         \- monitoring  
│       deploy:  
│         resources:  
│           limits:  
│             memory: 256M  
│   YAML  
│  
│     \# Add nvidia-smi-exporter if GPU present  
│     if \[\[ "$HAS\_GPU" \== "true" \]\]; then  
│       cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< YAML  
│     
│     nvidia-smi-exporter:  
│       image: nvcr.io/nvidia/k8s/dcgm-exporter:latest  
│       container\_name: nvidia-exporter  
│       restart: unless-stopped  
│       runtime: nvidia  
│       environment:  
│         NVIDIA\_VISIBLE\_DEVICES: all  
│       networks:  
│         \- monitoring  
│       deploy:  
│         resources:  
│           reservations:  
│             devices:  
│               \- driver: nvidia  
│                 count: all  
│                 capabilities: \[gpu\]  
│   YAML  
│     fi  
│   fi  
│  
└── echo "docker-compose.yml generated: $(grep 'container\_name:' $COMPOSE\_DIR/docker-compose.yml | wc \-l) containers"

### **PHASE 7: Generate Monitoring Configs**

generate\_monitoring\_configs()  
│  
├── \# Prometheus config  
│   cat \>  $ CONFIG\_DIR/prometheus/prometheus.yml \<\< YAML  
│   global:  
│     scrape\_interval: 15s  
│     evaluation\_interval: 15s  
│     
│   scrape\_configs:  
│     \- job\_name: 'prometheus'  
│       static\_configs:  
│         \- targets: \['localhost:9090'\]  
│     
│     \- job\_name: 'node-exporter'  
│       static\_configs:  
│         \- targets: \['node-exporter:9100'\]  
│     
│     \- job\_name: 'cadvisor'  
│       static\_configs:  
│         \- targets: \['cadvisor:8080'\]  
│     
│     \- job\_name: 'litellm'  
│       metrics\_path: /metrics  
│       static\_configs:  
│         \- targets: \['litellm:4000'\]  
│     
│     \- job\_name: 'ollama'  
│       metrics\_path: /metrics  
│       static\_configs:  
│         \- targets: \['host.docker.internal:11434'\]  
│   YAML  
│  
│   if \[\[ " $ HAS\_GPU" \== "true" \]\]; then  
│     cat \>\> $CONFIG\_DIR/prometheus/prometheus.yml \<\< YAML  
│     
│     \- job\_name: 'nvidia-gpu'  
│       static\_configs:  
│         \- targets: \['nvidia-exporter:9400'\]  
│   YAML  
│   fi  
│  
├── \# Grafana datasource provisioning  
│   mkdir \-p $CONFIG\_DIR/grafana/provisioning/datasources  
│   cat \> $CONFIG\_DIR/grafana/provisioning/datasources/prometheus.yml \<\< YAML  
│   apiVersion: 1  
│   datasources:  
│     \- name: Prometheus  
│       type: prometheus  
│       access: proxy  
│       url: http://prometheus:9090  
│       isDefault: true  
│       editable: false  
│   YAML  
│  
├── \# Grafana dashboard provisioning  
│   mkdir \-p $CONFIG\_DIR/grafana/provisioning/dashboards  
│   mkdir \-p $CONFIG\_DIR/grafana/dashboards  
│   cat \> $CONFIG\_DIR/grafana/provisioning/dashboards/default.yml \<\< YAML  
│   apiVersion: 1  
│   providers:  
│     \- name: 'default'  
│       orgId: 1  
│       folder: 'AI Platform'  
│       type: file  
│       disableDeletion: false  
│       editable: true  
│       options:  
│         path: /var/lib/grafana/dashboards  
│         foldersFromFilesStructure: false  
│   YAML  
│  
└── \# Generate AI Platform dashboard JSON (LiteLLM metrics, GPU, system)  
    \# (Large JSON dashboard definition — stored as file)  
    \# Includes panels for:  
    \#   \- LLM requests/sec, tokens/sec, latency P50/P95/P99  
    \#   \- Cost per model (from LiteLLM Prometheus metrics)  
    \#   \- GPU utilization, GPU memory, GPU temperature  
    \#   \- System CPU, RAM, disk I/O  
    \#   \- Container resource usage (from cAdvisor)  
    \#   \- Ollama model loading status  
    cp $BASE\_DIR/assets/grafana-dashboard-ai-platform.json \\  
       $CONFIG\_DIR/grafana/dashboards/ 2\>/dev/null || \\  
    generate\_dashboard\_json \> $CONFIG\_DIR/grafana/dashboards/ai-platform.json

### **PHASE 8: Pull Docker Images**

pull\_docker\_images()  
│  
├── echo "Pulling Docker images (this may take 5–15 minutes)..."  
│  
├── \# Parse compose file for image list  
│   IMAGES=$(grep 'image:' $COMPOSE\_DIR/docker-compose.yml | awk '{print  $ 2}' | sort \-u)  
│  
├── TOTAL= $ (echo "$IMAGES" | wc \-l)  
│   COUNT=0  
│   FAILED=()  
│  
├── for img in  $ IMAGES; do  
│     COUNT= $ ((COUNT \+ 1))  
│     echo "  \[ $ COUNT/ $ TOTAL\] Pulling  $ img..."  
│     if \! docker pull " $ img" 2\>\>$LOG\_FILE; then  
│       echo "    ⚠ Failed to pull  $ img — will retry"  
│       FAILED+=(" $ img")  
│     fi  
│   done  
│  
├── \# Retry failed pulls once  
│   for img in "${FAILED\[@\]}"; do  
│     echo "  Retrying  $ img..."  
│     docker pull " $ img" || echo "  ✗ FAILED: $img — check network/registry"  
│   done  
│  
└── echo "Docker images ready."

### **PHASES 9–11: Start Services in Order**

deploy\_services()  
│  
├── cd $COMPOSE\_DIR  
│  
├── \# PHASE 9: Core infrastructure  
│   echo "Starting core infrastructure..."  
│   docker compose up \-d postgres redis  
│  
├── \# PHASE 10: Wait for DB  
│   echo "Waiting for PostgreSQL..."  
│   RETRIES=0  
│   MAX\_RETRIES=30  
│   until docker exec postgres pg\_isready \-U ${POSTGRES\_USER} 2\>/dev/null; do  
│     RETRIES=$((RETRIES \+ 1))  
│     if \[\[ $RETRIES \-ge $MAX\_RETRIES \]\]; then  
│       echo "ERROR: PostgreSQL failed to start after ${MAX\_RETRIES} attempts"  
│       docker logs postgres \--tail 50  
│       exit 1  
│     fi  
│     echo "  Waiting for PostgreSQL... ( $ RETRIES/ $ MAX\_RETRIES)"  
│     sleep 2  
│   done  
│   echo "  ✓ PostgreSQL ready"  
│  
│   echo "Waiting for Redis..."  
│   until docker exec redis redis-cli \-a ${REDIS\_PASSWORD} ping 2\>/dev/null | grep \-q PONG; do  
│     sleep 2  
│   done  
│   echo "  ✓ Redis ready"  
│  
├── \# PHASE 11: Start remaining services in waves  
│   echo ""  
│   echo "Starting services..."  
│     
│   \# Wave 1: Vector DB \+ LiteLLM (foundation layer)  
│   echo "  Wave 1: Vector DB \+ LiteLLM..."  
│   WAVE1="litellm"  
│   case  $ VECTOR\_DB in  
│     qdrant)  WAVE1=" $ WAVE1 qdrant" ;;  
│     weaviate) WAVE1=" $ WAVE1 weaviate" ;;  
│     milvus)  WAVE1=" $ WAVE1 etcd minio-milvus milvus" ;;  
│   esac  
│   docker compose up \-d  $ WAVE1  
│     
│   \# Wait for LiteLLM health  
│   echo "  Waiting for LiteLLM..."  
│   RETRIES=0  
│   until curl \-sf http://localhost:4000/health \>/dev/null 2\>&1; do  
│     RETRIES= $ ((RETRIES \+ 1))  
│     \[\[  $ RETRIES \-ge 60 \]\] && { echo "ERROR: LiteLLM failed"; docker logs litellm \--tail 30; exit 1; }  
│     sleep 3  
│   done  
│   echo "  ✓ LiteLLM ready"  
│  
│   \# Wave 2: Application services  
│   echo "  Wave 2: Application services..."  
│   WAVE2=""  
│   service\_enabled "dify" && WAVE2=" $ WAVE2 dify-api dify-worker dify-web dify-nginx"  
│   service\_enabled "n8n" && WAVE2=" $ WAVE2 n8n"  
│   service\_enabled "open-webui" && WAVE2=" $ WAVE2 open-webui"  
│   service\_enabled "flowise" && WAVE2=" $ WAVE2 flowise"  
│   service\_enabled "anythingllm" && WAVE2=" $ WAVE2 anythingllm"  
│   service\_enabled "supertokens" && WAVE2=" $ WAVE2 supertokens"  
│   \[\[ \-n " $ WAVE2" \]\] && docker compose up \-d  $ WAVE2  
│     
│   \# Wave 3: Infrastructure services  
│   echo "  Wave 3: Infrastructure (Caddy, Portainer, Monitoring)..."  
│   WAVE3="caddy portainer"  
│   service\_enabled "monitoring" && WAVE3=" $ WAVE3 prometheus grafana node-exporter cadvisor"  
│   \[\[ " $ HAS\_GPU" \== "true" \]\] && service\_enabled "monitoring" && WAVE3=" $ WAVE3 nvidia-smi-exporter"  
│   docker compose up \-d $WAVE3  
│     
│   echo ""  
│   echo "All services started. Waiting 30s for stabilization..."  
│   sleep 30

### **PHASE 12: Pull Ollama Models**

pull\_ollama\_models()  
│  
├── echo "Pulling Ollama models (tier:  $ MODEL\_TIER)..."  
│  
├── declare \-A TIER\_MODELS  
│   TIER\_MODELS\[minimal\]="tinyllama nomic-embed-text"  
│   TIER\_MODELS\[standard\]=" $ {TIER\_MODELS\[minimal\]} mistral llama3.1:8b codellama:7b"  
│   TIER\_MODELS\[full\]="${TIER\_MODELS\[standard\]} llama3.1:70b mixtral:8x7b deepseek-coder-v2"  
│  
├── MODELS=${TIER\_MODELS\[ $ MODEL\_TIER\]:- $ {TIER\_MODELS\[minimal\]}}  
│  
├── for model in  $ MODELS; do  
│     if ollama list 2\>/dev/null | grep \-q "^ $ model"; then  
│       echo "  ✓ $model (already present)"  
│     else  
│       echo "  ↓ Pulling  $ model..."  
│       DISK\_FREE= $ (df \-BG /mnt/data | awk 'NR==2{gsub("G",""); print $4}')  
│       if \[\[  $ DISK\_FREE \-lt 10 \]\]; then  
│         echo "    ⚠ Low disk space ( $ {DISK\_FREE}GB free) — skipping remaining models"  
│         break  
│       fi  
│       if ollama pull " $ model" 2\>\> $ LOG\_FILE; then  
│         echo "    ✓ $model pulled successfully"  
│       else  
│         echo "    ✗ Failed to pull $model"  
│       fi  
│     fi  
│   done  
│  
└── echo "Ollama models: $(ollama list 2\>/dev/null | tail \-n \+2 | wc \-l) installed"

### **PHASE 13: Configure Google Drive**

configure\_gdrive()  
│  
├── if \[\[ "${GDRIVE\_ENABLED}" \!= "true" \]\]; then  
│     echo "Google Drive sync: disabled"  
│     return  
│   fi  
│  
├── echo "Configuring Google Drive sync..."  
│  
├── \# Configure rclone  
│   mkdir \-p /root/.config/rclone  
│   cat \> /root/.config/rclone/rclone.conf \<\< CONF  
│   \[gdrive\]  
│   type \= drive  
│   client\_id \= ${GDRIVE\_CLIENT\_ID}  
│   client\_secret \= ${GDRIVE\_CLIENT\_SECRET}  
│   scope \= drive.readonly  
│   root\_folder\_id \= ${GDRIVE\_FOLDER}  
│   CONF  
│  
├── \# OAuth token — needs interactive auth  
│   echo ""  
│   echo "═══════════════════════════════════════════════════"  
│   echo "  Google Drive OAuth Authorization Required"  
│   echo "═══════════════════════════════════════════════════"  
│   echo ""  
│   echo "Option 1: If you have a browser on this machine:"  
│   echo "  rclone config reconnect gdrive:"  
│   echo ""  
│   echo "Option 2: Remote (headless) authorization:"  
│   echo "  On a machine with a browser, run:"  
│   echo "    rclone authorize drive client\_id=${GDRIVE\_CLIENT\_ID} client\_secret=${GDRIVE\_CLIENT\_SECRET}"  
│   echo "  Then paste the token here."  
│   echo ""  
│   read \-p "Paste OAuth token (or 'skip' to configure later): " GDRIVE  
│   read \-p "Paste OAuth token (or 'skip' to configure later): " GDRIVE\_TOKEN  
│  
├── if \[\[ "$GDRIVE\_TOKEN" \!= "skip" \]\] && \[\[ \-n "$GDRIVE\_TOKEN" \]\]; then  
│     \# Append token to rclone config  
│     echo "token \= ${GDRIVE\_TOKEN}" \>\> /root/.config/rclone/rclone.conf  
│       
│     \# Verify connection  
│     if rclone lsd gdrive: \--max-depth 0 \>/dev/null 2\>&1; then  
│       echo "  ✓ Google Drive connection verified"  
│     else  
│       echo "  ⚠ Could not verify connection — check token and try:"  
│       echo "    rclone config reconnect gdrive:"  
│     fi  
│   else  
│     echo "  ⚠ Skipped — run later: rclone config reconnect gdrive:"  
│   fi  
│  
├── \# Create sync directory  
│   mkdir \-p ${GDRIVE\_SYNC\_DIR}  
│  
├── \# Create sync script  
│   cat \> $BASE\_DIR/scripts/gdrive-sync.sh \<\< 'SCRIPT'  
│   \#\!/bin/bash  
│   set \-euo pipefail  
│   LOG=/var/log/ai-platform/gdrive-sync.log  
│   LOCK=/tmp/gdrive-sync.lock  
│     
│   \# Prevent concurrent runs  
│   exec 200\>"$LOCK"  
│   flock \-n 200 || { echo "$(date) — sync already running" \>\> $LOG; exit 0; }  
│     
│   echo "$(date) — Starting Google Drive sync" \>\> $LOG  
│     
│   SYNC\_DIR=$(grep GDRIVE\_SYNC\_DIR /opt/ai-platform/env/master.env | cut \-d= \-f2)  
│     
│   rclone sync gdrive: "$SYNC\_DIR" \\  
│     \--transfers 4 \\  
│     \--checkers 8 \\  
│     \--contimeout 60s \\  
│     \--timeout 300s \\  
│     \--retries 3 \\  
│     \--low-level-retries 10 \\  
│     \--stats-one-line \\  
│     \--log-file "$LOG" \\  
│     \--log-level INFO \\  
│     \--exclude ".trash/\*\*" \\  
│     \--exclude ".\~\*" \\  
│     \--exclude "\~$\*"  
│     
│   SYNC\_STATUS=$?  
│     
│   if \[\[ $SYNC\_STATUS \-eq 0 \]\]; then  
│     echo "$(date) — Sync completed successfully" \>\> $LOG  
│     FILE\_COUNT=$(find "$SYNC\_DIR" \-type f | wc \-l)  
│     TOTAL\_SIZE=$(du \-sh "$SYNC\_DIR" | awk '{print $1}')  
│     echo "$(date) — Files: $FILE\_COUNT, Size: $TOTAL\_SIZE" \>\> $LOG  
│   else  
│     echo "$(date) — Sync failed with code $SYNC\_STATUS" \>\> $LOG  
│   fi  
│   SCRIPT  
│   chmod \+x $BASE\_DIR/scripts/gdrive-sync.sh  
│  
├── \# Create systemd timer for periodic sync  
│   cat \> /etc/systemd/system/gdrive-sync.service \<\< SERVICE  
│   \[Unit\]  
│   Description=Google Drive Sync for AI Platform  
│   After=network-online.target  
│   Wants=network-online.target  
│     
│   \[Service\]  
│   Type=oneshot  
│   ExecStart=$BASE\_DIR/scripts/gdrive-sync.sh  
│   User=root  
│   StandardOutput=journal  
│   StandardError=journal  
│   SERVICE  
│  
│   cat \> /etc/systemd/system/gdrive-sync.timer \<\< TIMER  
│   \[Unit\]  
│   Description=Run Google Drive Sync every ${GDRIVE\_INTERVAL} minutes  
│     
│   \[Timer\]  
│   OnBootSec=5min  
│   OnUnitActiveSec=${GDRIVE\_INTERVAL}min  
│   Persistent=true  
│   RandomizedDelaySec=60  
│     
│   \[Install\]  
│   WantedBy=timers.target  
│   TIMER  
│  
│   systemctl daemon-reload  
│   systemctl enable \--now gdrive-sync.timer  
│   echo "  ✓ Google Drive sync scheduled every ${GDRIVE\_INTERVAL} minutes"  
│  
├── \# Run initial sync  
│   echo "  Running initial sync..."  
│   bash $BASE\_DIR/scripts/gdrive-sync.sh &  
│   echo "  ✓ Initial sync started in background"  
│  
└── echo "Google Drive configuration complete"

### **PHASE 14: Configure Backups**

configure\_backups()  
│  
├── if \[\[ "${BACKUP\_ENABLED}" \!= "true" \]\]; then  
│     echo "Automated backups: disabled"  
│     return  
│   fi  
│  
├── echo "Configuring automated backups..."  
│  
├── \# Create backup script  
│   cat \> $BASE\_DIR/scripts/backup.sh \<\< 'SCRIPT'  
│   \#\!/bin/bash  
│   set \-euo pipefail  
│     
│   \# ── Config ──  
│   source /opt/ai-platform/env/master.env  
│   BACKUP\_DIR=/tmp/ai-platform-backup  
│   TIMESTAMP=$(date \+%Y%m%d-%H%M%S)  
│   BACKUP\_NAME="ai-platform-${TIMESTAMP}"  
│   LOG=/var/log/ai-platform/backup.log  
│   LOCK=/tmp/ai-platform-backup.lock  
│     
│   exec 200\>"$LOCK"  
│   flock \-n 200 || { echo "$(date) — backup already running" \>\> $LOG; exit 0; }  
│     
│   log() { echo "$(date '+%Y-%m-%d %H:%M:%S') — $1" | tee \-a $LOG; }  
│     
│   log "Starting backup: ${BACKUP\_NAME}"  
│     
│   \# Clean previous temp  
│   rm \-rf $BACKUP\_DIR  
│   mkdir \-p $BACKUP\_DIR/${BACKUP\_NAME}  
│     
│   \# ── 1\. PostgreSQL dump ──  
│   log "Dumping PostgreSQL databases..."  
│   DATABASES=$(docker exec postgres psql \-U ${POSTGRES\_USER} \-t \-c \\  
│     "SELECT datname FROM pg\_database WHERE datistemplate \= false AND datname \!= 'postgres';" | tr \-d ' ')  
│     
│   mkdir \-p $BACKUP\_DIR/${BACKUP\_NAME}/postgres  
│   for db in $DATABASES; do  
│     \[\[ \-z "$db" \]\] && continue  
│     log "  Dumping database: $db"  
│     docker exec postgres pg\_dump \-U ${POSTGRES\_USER} \-Fc "$db" \\  
│       \> $BACKUP\_DIR/${BACKUP\_NAME}/postgres/${db}.dump  
│   done  
│     
│   \# ── 2\. Redis snapshot ──  
│   log "Creating Redis snapshot..."  
│   docker exec redis redis-cli \-a ${REDIS\_PASSWORD} BGSAVE \>/dev/null 2\>&1  
│   sleep 5  
│   mkdir \-p $BACKUP\_DIR/${BACKUP\_NAME}/redis  
│   docker cp redis:/data/appendonly.aof $BACKUP\_DIR/${BACKUP\_NAME}/redis/ 2\>/dev/null || true  
│   docker cp redis:/data/dump.rdb $BACKUP\_DIR/${BACKUP\_NAME}/redis/ 2\>/dev/null || true  
│     
│   \# ── 3\. Environment & config (no secrets in backup — can be regenerated) ──  
│   log "Backing up configuration..."  
│   mkdir \-p $BACKUP\_DIR/${BACKUP\_NAME}/config  
│   cp \-r /opt/ai-platform/config/ $BACKUP\_DIR/${BACKUP\_NAME}/config/  
│   cp \-r /opt/ai-platform/docker/ $BACKUP\_DIR/${BACKUP\_NAME}/config/  
│   \# Exclude master.env (contains secrets) — store encrypted separately  
│   openssl enc \-aes-256-cbc \-salt \-pbkdf2 \\  
│     \-in /opt/ai-platform/env/master.env \\  
│     \-out $BACKUP\_DIR/${BACKUP\_NAME}/config/master.env.enc \\  
│     \-pass pass:${LITELLM\_SALT\_KEY} 2\>/dev/null || \\  
│     cp /opt/ai-platform/env/master.env $BACKUP\_DIR/${BACKUP\_NAME}/config/master.env  
│     
│   \# ── 4\. Vector DB data ──  
│   log "Backing up vector database..."  
│   mkdir \-p $BACKUP\_DIR/${BACKUP\_NAME}/vectordb  
│   case ${VECTOR\_DB} in  
│     qdrant)  
│       \# Qdrant snapshot via API  
│       curl \-sf \-X POST http://localhost:6333/snapshots \-o \\  
│         $BACKUP\_DIR/${BACKUP\_NAME}/vectordb/qdrant-snapshot.tar 2\>/dev/null || \\  
│         log "  ⚠ Qdrant snapshot failed — backing up data dir"  
│       ;;  
│     weaviate)  
│       curl \-sf \-X POST http://localhost:8080/v1/backups/filesystem \\  
│         \-H 'Content-Type: application/json' \\  
│         \-d "{\\"id\\": \\"${TIMESTAMP}\\"}" 2\>/dev/null || \\  
│         log "  ⚠ Weaviate backup failed"  
│       ;;  
│     milvus)  
│       log "  Milvus backup requires milvus-backup tool — skipping data dir copy"  
│       ;;  
│   esac  
│     
│   \# ── 5\. Service-specific data ──  
│   log "Backing up service data..."  
│     
│   \# n8n workflows export  
│   if docker ps \--format '{{.Names}}' | grep \-q '^n8n$'; then  
│     mkdir \-p $BACKUP\_DIR/${BACKUP\_NAME}/n8n  
│     curl \-sf http://localhost:5678/api/v1/workflows \\  
│       \-H "Accept: application/json" \\  
│       \> $BACKUP\_DIR/${BACKUP\_NAME}/n8n/workflows.json 2\>/dev/null || true  
│     curl \-sf http://localhost:5678/api/v1/credentials \\  
│       \-H "Accept: application/json" \\  
│       \> $BACKUP\_DIR/${BACKUP\_NAME}/n8n/credentials.json 2\>/dev/null || true  
│   fi  
│     
│   \# Dify storage (uploaded files)  
│   if \[\[ \-d "${DATA\_DIR}/dify/storage" \]\]; then  
│     log "  Backing up Dify storage..."  
│     mkdir \-p $BACKUP\_DIR/${BACKUP\_NAME}/dify  
│     tar \-czf $BACKUP\_DIR/${BACKUP\_NAME}/dify/storage.tar.gz \\  
│       \-C ${DATA\_DIR}/dify storage 2\>/dev/null || true  
│   fi  
│     
│   \# Flowise flows  
│   if \[\[ \-d "${DATA\_DIR}/flowise" \]\]; then  
│     mkdir \-p $BACKUP\_DIR/${BACKUP\_NAME}/flowise  
│     cp \-r ${DATA\_DIR}/flowise/ $BACKUP\_DIR/${BACKUP\_NAME}/flowise/ 2\>/dev/null || true  
│   fi  
│     
│   \# ── 6\. Compress ──  
│   log "Compressing backup..."  
│   cd $BACKUP\_DIR  
│   tar \-czf ${BACKUP\_NAME}.tar.gz ${BACKUP\_NAME}/  
│   BACKUP\_SIZE=$(du \-sh ${BACKUP\_NAME}.tar.gz | awk '{print $1}')  
│   log "Backup size: ${BACKUP\_SIZE}"  
│     
│   \# ── 7\. Upload to S3 ──  
│   log "Uploading to S3..."  
│   aws s3 cp ${BACKUP\_NAME}.tar.gz \\  
│     s3://${S3\_BUCKET}/backups/${BACKUP\_NAME}.tar.gz \\  
│     \--storage-class STANDARD\_IA \\  
│     \--only-show-errors  
│     
│   if \[\[ $? \-eq 0 \]\]; then  
│     log "  ✓ Uploaded to s3://${S3\_BUCKET}/backups/${BACKUP\_NAME}.tar.gz"  
│   else  
│     log "  ✗ S3 upload failed"  
│     \# Keep local copy if S3 fails  
│     mkdir \-p ${DATA\_DIR}/backups  
│     mv ${BACKUP\_NAME}.tar.gz ${DATA\_DIR}/backups/  
│     log "  → Saved locally to ${DATA\_DIR}/backups/${BACKUP\_NAME}.tar.gz"  
│   fi  
│     
│   \# ── 8\. Cleanup old backups ──  
│   log "Cleaning up old backups..."  
│   \# Remote: lifecycle policy handles S3 — but also prune manually  
│   RETENTION\_DAYS=${BACKUP\_RETENTION\_DAYS:-30}  
│   aws s3 ls s3://${S3\_BUCKET}/backups/ 2\>/dev/null | while read \-r line; do  
│     BACKUP\_DATE=$(echo "$line" | awk '{print $1}')  
│     BACKUP\_FILE=$(echo "$line" | awk '{print $4}')  
│     if \[\[ \-n "$BACKUP\_DATE" \]\] && \[\[ \-n "$BACKUP\_FILE" \]\]; then  
│       AGE\_DAYS=$(( ($(date \+%s) \- $(date \-d "$BACKUP\_DATE" \+%s)) / 86400 ))  
│       if \[\[ $AGE\_DAYS \-gt $RETENTION\_DAYS \]\]; then  
│         log "  Removing old backup: $BACKUP\_FILE (${AGE\_DAYS} days old)"  
│         aws s3 rm "s3://${S3\_BUCKET}/backups/${BACKUP\_FILE}" \--only-show-errors  
│       fi  
│     fi  
│   done  
│     
│   \# Local cleanup  
│   find ${DATA\_DIR}/backups/ \-name "ai-platform-\*.tar.gz" \-mtime \+7 \-delete 2\>/dev/null || true  
│     
│   \# Temp cleanup  
│   rm \-rf $BACKUP\_DIR  
│     
│   log "Backup complete: ${BACKUP\_NAME}"  
│   SCRIPT  
│   chmod \+x $BASE\_DIR/scripts/backup.sh  
│  
├── \# Create restore script  
│   cat \> $BASE\_DIR/scripts/restore.sh \<\< 'SCRIPT'  
│   \#\!/bin/bash  
│   set \-euo pipefail  
│     
│   BACKUP\_FILE=${1:-}  
│   if \[\[ \-z "$BACKUP\_FILE" \]\]; then  
│     echo "Usage: $0 \<backup-file-or-s3-key\>"  
│     echo ""  
│     echo "Examples:"  
│     echo "  $0 /path/to/ai-platform-20250115-104523.tar.gz"  
│     echo "  $0 s3://bucket/backups/ai-platform-20250115-104523.tar.gz"  
│     echo ""  
│     echo "Available S3 backups:"  
│     source /opt/ai-platform/env/master.env  
│     aws s3 ls s3://${S3\_BUCKET}/backups/ 2\>/dev/null | tail \-10  
│     exit 1  
│   fi  
│     
│   source /opt/ai-platform/env/master.env  
│   RESTORE\_DIR=/tmp/ai-platform-restore  
│     
│   echo "═══════════════════════════════════════════════════"  
│   echo "  AI Platform Restore"  
│   echo "═══════════════════════════════════════════════════"  
│   echo ""  
│   echo "WARNING: This will overwrite current databases and configs."  
│   read \-p "Continue? (yes/no): " CONFIRM  
│   \[\[ "$CONFIRM" \!= "yes" \]\] && exit 0  
│     
│   rm \-rf $RESTORE\_DIR  
│   mkdir \-p $RESTORE\_DIR  
│     
│   \# Download if S3  
│   if \[\[ "$BACKUP\_FILE" \== s3://\* \]\]; then  
│     echo "Downloading from S3..."  
│     aws s3 cp "$BACKUP\_FILE" $RESTORE\_DIR/backup.tar.gz  
│     BACKUP\_FILE="$RESTORE\_DIR/backup.tar.gz"  
│   fi  
│     
│   echo "Extracting..."  
│   tar \-xzf "$BACKUP\_FILE" \-C $RESTORE\_DIR  
│   BACKUP\_DIR=$(ls \-d $RESTORE\_DIR/ai-platform-\* | head \-1)  
│     
│   echo "Stopping application services..."  
│   cd /opt/ai-platform/docker  
│   docker compose stop dify-api dify-worker dify-web n8n open-webui flowise anythingllm litellm 2\>/dev/null || true  
│     
│   \# Restore PostgreSQL  
│   if \[\[ \-d "$BACKUP\_DIR/postgres" \]\]; then  
│     echo "Restoring PostgreSQL databases..."  
│     for dump in $BACKUP\_DIR/postgres/\*.dump; do  
│       DB\_NAME=$(basename "$dump" .dump)  
│       echo "  Restoring database: $DB\_NAME"  
│       docker exec postgres dropdb \-U ${POSTGRES\_USER} \--if-exists "$DB\_NAME" 2\>/dev/null || true  
│       docker exec postgres createdb \-U ${POSTGRES\_USER} "$DB\_NAME" 2\>/dev/null || true  
│       cat "$dump" | docker exec \-i postgres pg\_restore \-U ${POSTGRES\_USER} \-d "$DB\_NAME" \--clean \--if-exists 2\>/dev/null || true  
│     done  
│   fi  
│     
│   \# Restore Redis  
│   if \[\[ \-d "$BACKUP\_DIR/redis" \]\]; then  
│     echo "Restoring Redis data..."  
│     docker compose stop redis  
│     cp $BACKUP\_DIR/redis/\* ${DATA\_DIR}/redis/ 2\>/dev/null || true  
│     docker compose start redis  
│     sleep 5  
│   fi  
│     
│   \# Restore service data  
│   if \[\[ \-f "$BACKUP\_DIR/dify/storage.tar.gz" \]\]; then  
│     echo "Restoring Dify storage..."  
│     tar \-xzf "$BACKUP\_DIR/dify/storage.tar.gz" \-C ${DATA\_DIR}/dify/  
│   fi  
│     
│   echo "Restarting all services..."  
│   docker compose up \-d  
│     
│   echo ""  
│   echo "✓ Restore complete. Services restarting..."  
│   echo "  Monitor with: docker compose logs \-f"  
│     
│   rm \-rf $RESTORE\_DIR  
│   SCRIPT  
│   chmod \+x $BASE\_DIR/scripts/restore.sh  
│  
├── \# Schedule backup via systemd timer  
│   cat \> /etc/systemd/system/ai-platform-backup.service \<\< SERVICE  
│   \[Unit\]  
│   Description=AI Platform Backup  
│   After=network-online.target docker.service  
│   Wants=network-online.target  
│     
│   \[Service\]  
│   Type=oneshot  
│   ExecStart=/opt/ai-platform/scripts/backup.sh  
│   User=root  
│   StandardOutput=journal  
│   StandardError=journal  
│   TimeoutStartSec=3600  
│   SERVICE  
│  
│   if \[\[ "$BACKUP\_FREQUENCY" \== "daily" \]\]; then  
│     TIMER\_SCHEDULE="OnCalendar=\*-\*-\* 02:00:00"  
│   else  
│     TIMER\_SCHEDULE="OnCalendar=Sun \*-\*-\* 02:00:00"  
│   fi  
│  
│   cat \> /etc/systemd/system/ai-platform-backup.timer \<\< TIMER  
│   \[Unit\]  
│   Description=AI Platform Backup Timer (${BACKUP\_FREQUENCY})  
│     
│   \[Timer\]  
│   ${TIMER\_SCHEDULE}  
│   Persistent=true  
│   RandomizedDelaySec=1800  
│     
│   \[Install\]  
│   WantedBy=timers.target  
│   TIMER  
│  
│   systemctl daemon-reload  
│   systemctl enable \--now ai-platform-backup.timer  
│   echo "  ✓ Backup scheduled: ${BACKUP\_FREQUENCY} at 2:00 AM"  
│   echo "  ✓ Retention: ${BACKUP\_RETENTION\_DAYS} days"  
│   echo "  ✓ Destination: s3://${S3\_BUCKET}/backups/"  
│  
└── echo "Backup configuration complete"

### **PHASE 15: Health Check All Services**

health\_check\_all()  
│  
├── echo ""  
│   echo "═══════════════════════════════════════════════════"  
│   echo "  Service Health Check"  
│   echo "═══════════════════════════════════════════════════"  
│   echo ""  
│  
├── PASS=0  
│   FAIL=0  
│   WARN=0  
│  
├── check\_service() {  
│     local name=$1  
│     local url=$2  
│     local expected=${3:-200}  
│       
│     STATUS=$(curl \-sf \-o /dev/null \-w "%{http\_code}" "$url" 2\>/dev/null || echo "000")  
│       
│     if \[\[ "$STATUS" \== "$expected" \]\] || \[\[ "$STATUS" \== "200" \]\]; then  
│       echo "  ✓ ${name} — healthy (HTTP ${STATUS})"  
│       PASS=$((PASS \+ 1))  
│     elif \[\[ "$STATUS" \== "000" \]\]; then  
│       echo "  ✗ ${name} — unreachable"  
│       FAIL=$((FAIL \+ 1))  
│     else  
│       echo "  ⚠ ${name} — unexpected status (HTTP ${STATUS})"  
│       WARN=$((WARN \+ 1))  
│     fi  
│   }  
│  
├── \# Core  
│   check\_service "PostgreSQL" "skip" "skip"  
│   \# PostgreSQL check via docker  
│   if docker exec postgres pg\_isready \-U ${POSTGRES\_USER} \>/dev/null 2\>&1; then  
│     echo "  ✓ PostgreSQL — healthy"  
│     PASS=$((PASS \+ 1))  
│   else  
│     echo "  ✗ PostgreSQL — not ready"  
│     FAIL=$((FAIL \+ 1))  
│   fi  
│     
│   if docker exec redis redis-cli \-a ${REDIS\_PASSWORD} ping 2\>/dev/null | grep \-q PONG; then  
│     echo "  ✓ Redis — healthy"  
│     PASS=$((PASS \+ 1))  
│   else  
│     echo "  ✗ Redis — not responding"  
│     FAIL=$((FAIL \+ 1))  
│   fi  
│  
├── \# LiteLLM  
│   check\_service "LiteLLM" "http://localhost:4000/health"  
│  
├── \# Vector DB  
│   case $VECTOR\_DB in  
│     qdrant)   check\_service "Qdrant" "http://localhost:6333/healthz" ;;  
│     weaviate) check\_service "Weaviate" "http://localhost:8080/v1/.well-known/ready" ;;  
│     milvus)   check\_service "Milvus" "http://localhost:9091/healthz" ;;  
│   esac  
│  
├── \# Application services  
│   service\_enabled "dify" && check\_service "Dify" "http://localhost:5001/health" "200"  
│   service\_enabled "n8n" && check\_service "n8n" "http://localhost:5678/healthz"  
│   service\_enabled "open-webui" && check\_service "Open WebUI" "http://localhost:8080/health"  
│   service\_enabled "flowise" && check\_service "Flowise" "http://localhost:3000"  
│   service\_enabled "anythingllm" && check\_service "AnythingLLM" "http://localhost:3001/api/ping"  
│   service\_enabled "supertokens" && check\_service "SuperTokens" "http://localhost:3567/hello"  
│  
├── \# Infrastructure  
│   check\_service "Caddy" "http://localhost:80"  
│   check\_service "Portainer" "http://localhost:9000/api/system/status"  
│   service\_enabled "monitoring" && check\_service "Prometheus" "http://localhost:9090/-/healthy"  
│   service\_enabled "monitoring" && check\_service "Grafana" "http://localhost:3000/api/health"  
│  
├── \# Ollama (host)  
│   if curl \-sf http://localhost:11434/api/tags \>/dev/null 2\>&1; then  
│     MODEL\_COUNT=$(curl \-sf http://localhost:11434/api/tags | python3 \-c "import sys,json; print(len(json.load(sys.stdin).get('models',\[\])))" 2\>/dev/null || echo "?")  
│     echo "  ✓ Ollama — healthy (${MODEL\_COUNT} models loaded)"  
│     PASS=$((PASS \+ 1))  
│   else  
│     echo "  ⚠ Ollama — not responding on port 11434"  
│     WARN=$((WARN \+ 1))  
│   fi  
│  
├── echo ""  
│   echo "  Results: ${PASS} passed, ${WARN} warnings, ${FAIL} failed"  
│   echo ""  
│  
└── if \[\[ $FAIL \-gt 0 \]\]; then  
│     echo "  ⚠ Some services failed. Check logs:"  
│     echo "    docker compose \-f $COMPOSE\_DIR/docker-compose.yml logs \<service\>"  
│     echo ""  
│   fi  
│   return $FAIL

### **PHASE 16: Generate Convenience Scripts**

generate\_convenience\_scripts()  
│  
├── \# ── ai-status — quick dashboard ──  
│   cat \> /usr/local/bin/ai-status \<\< 'SCRIPT'  
│   \#\!/bin/bash  
│   source /opt/ai-platform/env/master.env 2\>/dev/null  
│   echo ""  
│   echo "═══ AI Platform Status ═══"  
│   echo ""  
│   echo "Services:"  
│   docker ps \--format "table {{.Names}}\\t{{.Status}}\\t{{.Ports}}" | \\  
│     grep \-E "(postgres|redis|litellm|dify|n8n|open-webui|flowise|caddy|grafana|portainer|qdrant|weaviate|milvus|anythingllm|supertokens|prometheus)" | \\  
│     sort  
│   echo ""  
│   echo "Ollama Models:"  
│   ollama list 2\>/dev/null || echo "  Ollama not running"  
│   echo ""  
│   echo "Disk Usage:"  
│   df \-h /mnt/data 2\>/dev/null || df \-h /  
│   echo ""  
│   echo "GPU:"  
│   nvidia-smi \--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu \\  
│     \--format=csv,noheader 2\>/dev/null || echo "  No GPU detected"  
│   echo ""  
│   if \[\[ \-n "${BASE\_DOMAIN:-}" \]\]; then  
│     echo "URLs:"  
│     echo "  Dify:        https://${DIFY\_DOMAIN:-N/A}"  
│     echo "  n8n:         https://${N8N\_DOMAIN:-N/A}"  
│     echo "  Open WebUI:  https://${WEBUI\_DOMAIN:-N/A}"  
│     echo "  Flowise:     https://${FLOWISE\_DOMAIN:-N/A}"  
│     echo "  LiteLLM:     https://${LITELLM\_DOMAIN:-N/A}"  
│     echo "  Grafana:     https://${GRAFANA\_DOMAIN:-N/A}"  
│     echo "  Portainer:   https://${PORTAINER\_DOMAIN:-N/A}"  
│   fi  
│   echo ""  
│   SCRIPT  
│   chmod \+x /usr/local/bin/ai-status  
│  
├── \# ── ai-logs — tail logs ──  
│   cat \> /usr/local/bin/ai-logs \<\< 'SCRIPT'  
│   \#\!/bin/bash  
│   SERVICE=${1:-}  
│   if \[\[ \-z "$SERVICE" \]\]; then  
│     echo "Usage: ai-logs \<service|all\>"  
│     echo "Services: postgres redis litellm dify n8n open-webui flowise caddy grafana portainer"  
│     exit 1  
│   fi  
│   if \[\[ "$SERVICE" \== "all" \]\]; then  
│     docker compose \-f /opt/ai-platform/docker/docker-compose.yml logs \-f \--tail 50  
│   else  
│     docker compose \-f /opt/ai-platform/docker/docker-compose.yml logs \-f \--tail 100 "$SERVICE"  
│   fi  
│   SCRIPT  
│   chmod \+x /usr/local/bin/ai-logs  
│  
├── \# ── ai-restart — restart service(s) ──  
│   cat \> /usr/local/bin/ai-restart \<\< 'SCRIPT'  
│   \#\!/bin/bash  
│   SERVICE=${1:-}  
│   if \[\[ \-z "$SERVICE" \]\]; then  
│     echo "Usage: ai-restart \<service|all\>"  
│     exit 1  
│   fi  
│   if \[\[ "$SERVICE" \== "all" \]\]; then  
│     docker compose \-f /opt/ai-platform/docker/docker-compose.yml restart  
│   else  
│     docker compose \-f /opt/ai-platform/docker/docker-compose.yml restart "$SERVICE"  
│   fi  
│   SCRIPT  
│   chmod \+x /usr/local/bin/ai-restart  
│  
├── \# ── ai-backup — trigger backup ──  
│   cat \> /usr/local/bin/ai-backup \<\< 'SCRIPT'  
│   \#\!/bin/bash  
│   echo "Starting backup..."  
│   bash /opt/ai-platform/scripts/backup.sh  
│   SCRIPT  
│   chmod \+x /usr/local/bin/ai-backup  
│  
├── \# ── ai-update — update all containers ──  
│   cat \> /usr/local/bin/ai-update \<\< 'SCRIPT'  
│   \#\!/bin/bash  
│   echo "═══ AI Platform Update ═══"  
│   echo ""  
│   echo "1. Creating pre-update backup..."  
│   bash /opt/ai-platform/scripts/backup.sh  
│   echo ""  
│   echo "2. Pulling latest images..."  
│   docker compose \-f /opt/ai-platform/docker/docker-compose.yml pull  
│   echo ""  
│   echo "3. Recreating containers..."  
│   docker compose \-f /opt/ai-platform/docker/docker-compose.yml up \-d \--remove-orphans  
│   echo ""  
│   echo "4. Cleaning old images..."  
│   docker image prune \-f  
│   echo ""  
│   echo "5. Health check..."  
│   sleep 30  
│   ai-status  
│   SCRIPT  
│   chmod \+x /usr/local/bin/ai-update  
│  
├── \# ── ai-models — manage Ollama models ──  
│   cat \> /usr/local/bin/ai-models \<\< 'SCRIPT'  
│   \#\!/bin/bash  
│   ACTION=${1:-list}  
│   case $ACTION in  
│     list)   ollama list ;;  
│     pull)   ollama pull "${2:?Specify model name}" ;;  
│     remove) ollama rm "${2:?Specify model name}" ;;  
│     run)    ollama run "${2:?Specify model name}" ;;  
│     \*)      echo "Usage: ai-models \<list|pull|remove|run\> \[model\]" ;;  
│   esac  
│   SCRIPT  
│   chmod \+x /usr/local/bin/ai-models  
│  
└── echo "Convenience commands installed: ai-status, ai-logs, ai-restart, ai-backup, ai-update, ai-models"

### **PHASE 17: Final Summary**

print\_final\_summary()  
│  
├── ELAPSED=$(( $(date \+%s) \- START\_TIME ))  
│   MINUTES=$(( ELAPSED / 60 ))  
│   SECONDS=$(( ELAPSED % 60 ))  
│  
├── echo ""  
│   echo "╔══════════════════════════════════════════════════════════════╗"  
│   echo "║                                                            ║"  
│   echo "║   ✓  AI Platform Deployment Complete                       ║"  
│   echo "║                                                            ║"  
│   echo "║   Deployment time: ${MINUTES}m ${SECONDS}s                 ║"  
│   echo "║                                                            ║"  
│   echo "╠══════════════════════════════════════════════════════════════╣"  
│   echo "║                                                            ║"  
│   echo "║   SERVICE URLS                                             ║"  
│   echo "║                                                            ║"  
│  
│   if \[\[ "$DOMAIN\_MODE" \== "production" \]\]; then  
│     service\_enabled "dify" && \\  
│       echo "║   Dify:         https://${DIFY\_DOMAIN}                  ║"  
│     service\_enabled "n8n" && \\  
│       echo "║   n8n:          https://${N8N\_DOMAIN}                   ║"  
│     service\_enabled "open-webui" && \\  
│       echo "║   Open WebUI:   https://${WEBUI\_DOMAIN}                 ║"  
│     service\_enabled "flowise" && \\  
│       echo "║   Flowise:      https://${FLOWISE\_DOMAIN}               ║"  
│     echo "║   LiteLLM:      https://${LITELLM\_DOMAIN}                ║"  
│     service\_enabled "monitoring" && \\  
│       echo "║   Grafana:      https://${GRAFANA\_DOMAIN}               ║"  
│     echo "║   Portainer:    https://${PORTAINER\_DOMAIN}              ║"  
│   else  
│     echo "║   Access via: http://\<server-ip\>:\<port\>                  ║"  
│     echo "║   Ports: Dify(80) n8n(5678) WebUI(8080) Flowise(3000)   ║"  
│     echo "║          LiteLLM(4000) Grafana(3001) Portainer(9000)    ║"  
│   fi  
│  
│   echo "║                                                            ║"  
│   echo "╠══════════════════════════════════════════════════════════════╣"  
│   echo "║                                                            ║"  
│   echo "║   DEFAULT CREDENTIALS                                     ║"  
│   echo "║                                                            ║"  
│   echo "║   Dify:        admin / ${DIFY\_INIT\_PASSWORD}               ║"  
│   echo "║   Flowise:     ${FLOWISE\_USERNAME} / ${FLOWISE\_PASSWORD}   ║"  
│   echo "║   Grafana:     ${GRAFANA\_ADMIN\_USER} / ${GRAFANA\_ADMIN\_PASSWORD} ║"  
│   echo "║   Portainer:   Set on first login                         ║"  
│   echo "║   n8n:         Set on first login                         ║"  
│   echo "║   Open WebUI:  Set on first login                         ║"  
│   echo "║   LiteLLM key: ${LITELLM\_MASTER\_KEY:0:20}...             ║"  
│   echo "║                                                            ║"  
│   echo "╠══════════════════════════════════════════════════════════════╣"  
│   echo "║                                                            ║"  
│   echo "║   USEFUL COMMANDS                                         ║"  
│   echo "║                                                            ║"  
│   echo "║   ai-status           — Service dashboard                 ║"  
│   echo "║   ai-logs \<service\>   — View logs                         ║"  
│   echo "║   ai-restart \<service\>— Restart service                   ║"  
│   echo "║   ai-backup           — Trigger backup                    ║"  
│   echo "║   ai-update           — Update all services               ║"  
│   echo "║   ai-models list      — List Ollama models                ║"  
│   echo "║   ai-models pull \<m\>  — Pull new model                    ║"  
│   echo "║                                                            ║"  
│   echo "╠══════════════════════════════════════════════════════════════╣"  
│   echo "║                                                            ║"  
│   echo "║   CREDENTIALS FILE                                        ║"  
│   echo "║   /opt/ai-platform/env/master.env                         ║"  
│   echo "║   (chmod 600 — root only)                                 ║"  
│   echo "║                                                            ║"  
│   echo "╠══════════════════════════════════════════════════════════════╣"  
│   echo "║                                                            ║"  
│   echo "║   NEXT STEPS                                              ║"  
│   echo "║                                                            ║"  
│   echo "║   1\. Access each service URL and complete initial setup    ║"  
│   echo "║   2\. Configure Dify to use LiteLLM as model provider      ║"  
│   echo "║      (API base: http://litellm:4000/v1)                   ║"  
│   echo "║   3\. Import n8n workflow templates from:                   ║"  
│   echo "║      /opt/ai-platform/templates/n8n/                      ║"  
│   echo "║   4\. Set up Grafana alerts for cost/usage thresholds       ║"  
│   echo "║   5\. Upload documents to Google Drive for RAG sync         ║"  
│   echo "║   6\. Run 'ai-status' to verify everything is healthy      ║"  
│   echo "║                                                            ║"  
│   echo "╚══════════════════════════════════════════════════════════════╝"  
│   echo ""  
│  
├── \# Mark completion  
│   echo "SCRIPT\_2\_COMPLETED=$(date \-u \+%Y-%m-%dT%H:%M:%SZ)" \>\> $ENV\_DIR/master.env  
│   echo "SCRIPT\_2\_VERSION=1.0.0" \>\> $ENV\_DIR/master.env  
│  
└── echo "Deployment log: $LOG\_FILE"

### **Complete Script 2 Flow (main)**

main() {  
  \# Phases 1-2: Validate & source  
  validate\_prerequisites  
  source\_config  
    
  \# Phase 3: Environment files  
  generate\_env\_files  
    
  \# Phase 4: LiteLLM config  
  generate\_litellm\_config  
    
  \# Phase 5: Caddyfile  
  generate\_caddyfile  
    
  \# Phase 6: Docker compose  
  generate\_docker\_compose  
    
  \# Phase 7: Monitoring configs  
  if service\_enabled "monitoring"; then  
    generate\_monitoring\_configs  
  fi  
    
  \# Phase 8: Pull images  
  pull\_docker\_images  
    
  \# Phases 9-11: Deploy  
  deploy\_services  
    
  \# Phase 12: Ollama models  
  pull\_ollama\_models  
    
  \# Phase 13: Google Drive  
  configure\_gdrive  
    
  \# Phase 14: Backups  
  configure\_backups  
    
  \# Phase 15: Health check  
  health\_check\_all || true  
    
  \# Phase 16: Convenience scripts  
  generate\_convenience\_scripts  
    
  \# Phase 17: Summary  
  print\_final\_summary  
}

\# Support \--regenerate flag for config updates  
if \[\[ "${1:-}" \== "--regenerate" \]\]; then  
  echo "Regenerating configs without redeploying..."  
  source\_config  
  generate\_env\_files  
  generate\_litellm\_config  
  generate\_caddyfile  
  generate\_docker\_compose  
  generate\_monitoring\_configs  
  echo "Done. Restart with: docker compose \-f $COMPOSE\_DIR/docker-compose.yml up \-d"  
  exit 0  
fi

main "$@"  
\---

\#\# 17\. PostgreSQL Initialization SQL

\#\#\# Generated by Script 2, Phase 10

generate\_postgres\_init() │ ├── File: $CONFIG\_DIR/postgres/init.sql │ ├── \-- ═══════════════════════════════════════════════════ │ \-- AI Platform — PostgreSQL Initialization │ \-- Generated by Script 2 │ \-- ═══════════════════════════════════════════════════ │ ├── \-- ── Extensions ── │ CREATE EXTENSION IF NOT EXISTS "uuid-ossp"; │ CREATE EXTENSION IF NOT EXISTS "pgcrypto"; │ CREATE EXTENSION IF NOT EXISTS "pg\_trgm"; │ CREATE EXTENSION IF NOT EXISTS "vector"; \-- pgvector for embeddings │ CREATE EXTENSION IF NOT EXISTS "hstore"; │ ├── \-- ── Database: LiteLLM ── │ CREATE DATABASE litellm OWNER ${POSTGRES\_USER}; │ \\c litellm │ CREATE EXTENSION IF NOT EXISTS "uuid-ossp"; │ CREATE EXTENSION IF NOT EXISTS "pgcrypto"; │  
│ \-- LiteLLM manages its own schema via migrations │ \-- but we pre-create the spend tracking view │ \-- (LiteLLM will create tables on first start) │ ├── \-- ── Database: Dify ── │ CREATE DATABASE dify OWNER ${POSTGRES\_USER}; │ \\c dify │ CREATE EXTENSION IF NOT EXISTS "uuid-ossp"; │ CREATE EXTENSION IF NOT EXISTS "pgcrypto"; │ CREATE EXTENSION IF NOT EXISTS "vector"; │ CREATE EXTENSION IF NOT EXISTS "pg\_trgm"; │ ├── \-- ── Database: n8n ── │ CREATE DATABASE n8n OWNER ${POSTGRES\_USER}; │ \\c n8n │ CREATE EXTENSION IF NOT EXISTS "uuid-ossp"; │ CREATE EXTENSION IF NOT EXISTS "pgcrypto"; │ ├── \-- ── Database: SuperTokens ── │ CREATE DATABASE supertokens OWNER ${POSTGRES\_USER}; │ \\c supertokens │ CREATE EXTENSION IF NOT EXISTS "uuid-ossp"; │ ├── \-- ── Database: Grafana ── │ CREATE DATABASE grafana OWNER ${POSTGRES\_USER}; │ ├── \-- ── Database: Platform (shared/custom tables) ── │ CREATE DATABASE platform OWNER ${POSTGRES\_USER}; │ \\c platform │ CREATE EXTENSION IF NOT EXISTS "uuid-ossp"; │ CREATE EXTENSION IF NOT EXISTS "pgcrypto"; │ CREATE EXTENSION IF NOT EXISTS "vector"; │ CREATE EXTENSION IF NOT EXISTS "hstore"; │  
│ \-- ── API Key Management ── │ CREATE TABLE IF NOT EXISTS api\_keys ( │ id UUID PRIMARY KEY DEFAULT uuid\_generate\_v4(), │ key\_hash VARCHAR(128) NOT NULL UNIQUE, │ key\_prefix VARCHAR(10) NOT NULL, \-- e.g., "sk-plat-" │ name VARCHAR(255) NOT NULL, │ description TEXT, │ user\_id VARCHAR(255), \-- links to SuperTokens user │ permissions JSONB DEFAULT '\["read"\]'::jsonb, │ rate\_limit\_rpm INTEGER DEFAULT 60, │ rate\_limit\_rpd INTEGER DEFAULT 1000, │ monthly\_budget\_usd DECIMAL(10,2), │ total\_spend\_usd DECIMAL(10,2) DEFAULT 0, │ allowed\_models TEXT\[\], \-- NULL \= all models │ allowed\_ips INET\[\], \-- NULL \= any IP │ metadata JSONB DEFAULT '{}'::jsonb, │ is\_active BOOLEAN DEFAULT true, │ expires\_at TIMESTAMP WITH TIME ZONE, │ last\_used\_at TIMESTAMP WITH TIME ZONE, │ created\_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(), │ updated\_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() │ ); │  
│ CREATE INDEX idx\_api\_keys\_hash ON api\_keys(key\_hash); │ CREATE INDEX idx\_api\_keys\_user ON api\_keys(user\_id); │ CREATE INDEX idx\_api\_keys\_active ON api\_keys(is\_active) WHERE is\_active \= true; │  
│ \-- ── Usage Tracking ── │ CREATE TABLE IF NOT EXISTS usage\_logs ( │ id UUID PRIMARY KEY DEFAULT uuid\_generate\_v4(), │ api\_key\_id UUID REFERENCES api\_keys(id), │ user\_id VARCHAR(255), │ model VARCHAR(255) NOT NULL, │ provider VARCHAR(100), │ request\_type VARCHAR(50) DEFAULT 'chat', \-- chat, completion, embedding, image │ input\_tokens INTEGER DEFAULT 0, │ output\_tokens INTEGER DEFAULT 0, │ total\_tokens INTEGER DEFAULT 0, │ input\_cost\_usd DECIMAL(10,6) DEFAULT 0, │ output\_cost\_usd DECIMAL(10,6) DEFAULT 0, │ total\_cost\_usd DECIMAL(10,6) DEFAULT 0, │ latency\_ms INTEGER, │ status\_code INTEGER, │ error\_message TEXT, │ cache\_hit BOOLEAN DEFAULT false, │ metadata JSONB DEFAULT '{}'::jsonb, │ requested\_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() │ ); │  
│ \-- Partitioned by month for performance │ CREATE INDEX idx\_usage\_requested ON usage\_logs(requested\_at); │ CREATE INDEX idx\_usage\_user ON usage\_logs(user\_id); │ CREATE INDEX idx\_usage\_model ON usage\_logs(model); │ CREATE INDEX idx\_usage\_api\_key ON usage\_logs(api\_key\_id); │ CREATE INDEX idx\_usage\_cost ON usage\_logs(total\_cost\_usd) WHERE total\_cost\_usd \> 0; │  
│ \-- ── Budget Alerts ── │ CREATE TABLE IF NOT EXISTS budget\_alerts ( │ id UUID PRIMARY KEY DEFAULT uuid\_generate\_v4(), │ scope VARCHAR(50) NOT NULL, \-- 'global', 'user', 'api\_key', 'model' │ scope\_id VARCHAR(255), \-- NULL for global, user\_id, key\_id, model name │ period VARCHAR(20) DEFAULT 'monthly', \-- 'daily', 'weekly', 'monthly' │ budget\_usd DECIMAL(10,2) NOT NULL, │ alert\_threshold\_pct INTEGER DEFAULT 80, \-- alert at 80% of budget │ hard\_limit BOOLEAN DEFAULT false, \-- if true, block requests over budget │ notification\_channels TEXT\[\] DEFAULT ARRAY\['log'\], \-- 'log', 'webhook', 'email' │ webhook\_url TEXT, │ current\_spend\_usd DECIMAL(10,2) DEFAULT 0, │ last\_alert\_at TIMESTAMP WITH TIME ZONE, │ is\_active BOOLEAN DEFAULT true, │ created\_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() │ ); │  
│ \-- ── RAG Document Registry ── │ CREATE TABLE IF NOT EXISTS rag\_documents ( │ id UUID PRIMARY KEY DEFAULT uuid\_generate\_v4(), │ source VARCHAR(50) NOT NULL, \-- 'upload', 'gdrive', 'url', 'api' │ source\_path TEXT, │ filename VARCHAR(500) NOT NULL, │ file\_type VARCHAR(50), │ file\_size\_bytes BIGINT, │ checksum\_sha256 VARCHAR(64), │ chunk\_count INTEGER DEFAULT 0, │ embedding\_model VARCHAR(255), │ vector\_db VARCHAR(50), \-- 'qdrant', 'weaviate', 'milvus', 'pgvector' │ collection\_name VARCHAR(255), │ processing\_status VARCHAR(50) DEFAULT 'pending', \-- pending, processing, completed, failed │ processing\_error TEXT, │ last\_synced\_at TIMESTAMP WITH TIME ZONE, │ metadata JSONB DEFAULT '{}'::jsonb, │ created\_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(), │ updated\_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() │ ); │  
│ CREATE INDEX idx\_rag\_docs\_source ON rag\_documents(source); │ CREATE INDEX idx\_rag\_docs\_status ON rag\_documents(processing\_status); │ CREATE INDEX idx\_rag\_docs\_checksum ON rag\_documents(checksum\_sha256); │  
│ \-- ── Audit Log ── │ CREATE TABLE IF NOT EXISTS audit\_log ( │ id BIGSERIAL PRIMARY KEY, │ event\_type VARCHAR(100) NOT NULL, \-- 'api\_key.created', 'model.added', 'budget.exceeded' │ actor\_type VARCHAR(50), \-- 'user', 'system', 'api\_key' │ actor\_id VARCHAR(255), │ resource\_type VARCHAR(100), │ resource\_id VARCHAR(255), │ details JSONB DEFAULT '{}'::jsonb, │ ip\_address INET, │ user\_agent TEXT, │ created\_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() │ ); │  
│ CREATE INDEX idx\_audit\_event ON audit\_log(event\_type); │ CREATE INDEX idx\_audit\_actor ON audit\_log(actor\_id); │ CREATE INDEX idx\_audit\_time ON audit\_log(created\_at); │  
│ \-- ── Materialized View: Daily Cost Summary ── │ CREATE MATERIALIZED VIEW IF NOT EXISTS daily\_cost\_summary AS │ SELECT │ DATE(requested\_at) AS date, │ model, │ provider, │ user\_id, │ COUNT(\*) AS request\_count, │ SUM(input\_tokens) AS total\_input\_tokens, │ SUM(output\_tokens) AS total\_output\_tokens, │ SUM(total\_tokens) AS total\_tokens, │ SUM(total\_cost\_usd) AS total\_cost\_usd, │ AVG(latency\_ms) AS avg\_latency\_ms, │ PERCENTILE\_CONT(0.95) WITHIN GROUP (ORDER BY latency\_ms) AS p95\_latency\_ms, │ SUM(CASE WHEN cache\_hit THEN 1 ELSE 0 END) AS cache\_hits, │ SUM(CASE WHEN status\_code \>= 400 THEN 1 ELSE 0 END) AS error\_count │ FROM usage\_logs │ GROUP BY DATE(requested\_at), model, provider, user\_id; │  
│ CREATE UNIQUE INDEX idx\_daily\_cost\_unique │ ON daily\_cost\_summary(date, model, provider, user\_id); │  
│ \-- ── Function: Refresh daily summary (called by cron) ── │ CREATE OR REPLACE FUNCTION refresh\_daily\_cost\_summary() │ RETURNS void AS $$ │ BEGIN │ REFRESH MATERIALIZED VIEW CONCURRENTLY daily\_cost\_summary; │ END; │ $$ LANGUAGE plpgsql; │  
│ \-- ── Function: Check budget and return status ── │ CREATE OR REPLACE FUNCTION check\_budget( │ p\_scope VARCHAR, │ p\_scope\_id VARCHAR DEFAULT NULL │ ) RETURNS TABLE( │ budget\_usd DECIMAL, │ current\_spend DECIMAL, │ remaining DECIMAL, │ pct\_used DECIMAL, │ is\_exceeded BOOLEAN, │ hard\_limit BOOLEAN │ ) AS $$ │ BEGIN │ RETURN QUERY │ SELECT │ ba.budget\_usd, │ COALESCE(SUM(ul.total\_cost\_usd), 0\) AS current\_spend, │ ba.budget\_usd \- COALESCE(SUM(ul.total\_cost\_usd), 0\) AS remaining, │ CASE WHEN ba.budget\_usd \> 0 │ THEN ROUND(COALESCE(SUM(ul.total\_cost\_usd), 0\) / ba.budget\_usd \* 100, 2\) │ ELSE 0 │ END AS pct\_used, │ COALESCE(SUM(ul.total\_cost\_usd), 0\) \>= ba.budget\_usd AS is\_exceeded, │ ba.hard\_limit │ FROM budget\_alerts ba │ LEFT JOIN usage\_logs ul ON ( │ CASE │ WHEN ba.scope \= 'global' THEN true │ WHEN ba.scope \= 'user' THEN ul.user\_id \= ba.scope\_id │ WHEN ba.scope \= 'model' THEN ul.model \= ba.scope\_id │ WHEN ba.scope \= 'api\_key' THEN ul.api\_key\_id::text \= ba.scope\_id │ END │ AND ul.requested\_at \>= DATE\_TRUNC( │ CASE ba.period │ WHEN 'daily' THEN 'day' │ WHEN 'weekly' THEN 'week' │ WHEN 'monthly' THEN 'month' │ END, │ NOW() │ ) │ ) │ WHERE ba.scope \= p\_scope │ AND (ba.scope\_id \= p\_scope\_id OR (p\_scope\_id IS NULL AND ba.scope \= 'global')) │ AND ba.is\_active \= true │ GROUP BY ba.id, ba.budget\_usd, ba.hard\_limit; │ END; │ $$ LANGUAGE plpgsql; │  
│ \-- ── Insert default global budget ── │ INSERT INTO budget\_alerts (scope, period, budget\_usd, alert\_threshold\_pct, hard\_limit) │ VALUES ('global', 'monthly', 500.00, 80, false) │ ON CONFLICT DO NOTHING; │  
│ \-- ── Grant permissions ── │ \\c aiplatform │ GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${POSTGRES\_USER}; │ GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${POSTGRES\_USER};

\---

\#\# 18\. Dify Reverse Proxy Configuration

\#\#\# Dify Internal Architecture (requires nginx between Caddy and Dify components)

generate\_dify\_nginx\_conf() │ ├── File: $CONFIG\_DIR/dify/nginx.conf │ ├── upstream dify\_api { │ server dify-api:5001; │ } │  
│ upstream dify\_web { │ server dify-web:3000; │ } │  
│ server { │ listen 80; │ server\_name \_; │  
│ client\_max\_body\_size 100M; │  
│ \# ── API routes ── │ location /v1 { │ proxy\_pass [http://dify\_api](http://dify_api); │ proxy\_set\_header Host $host; │ proxy\_set\_header X-Real-IP $remote\_addr; │ proxy\_set\_header X-Forwarded-For $proxy\_add\_x\_forwarded\_for; │ proxy\_set\_header X-Forwarded-Proto $scheme; │ proxy\_read\_timeout 300s; │ proxy\_send\_timeout 300s; │ } │  
│ location /console/api { │ proxy\_pass [http://dify\_api](http://dify_api); │ proxy\_set\_header Host $host; │ proxy\_set\_header X-Real-IP $remote\_addr; │ proxy\_set\_header X-Forwarded-For $proxy\_add\_x\_forwarded\_for; │ proxy\_set\_header X-Forwarded-Proto $scheme; │ proxy\_read\_timeout 300s; │ } │  
│ location /api { │ proxy\_pass [http://dify\_api](http://dify_api); │ proxy\_set\_header Host $host; │ proxy\_set\_header X-Real-IP $remote\_addr; │ proxy\_set\_header X-Forwarded-For $proxy\_add\_x\_forwarded\_for; │ proxy\_set\_header X-Forwarded-Proto $scheme; │ proxy\_read\_timeout 300s; │ } │  
│ location /files { │ proxy\_pass [http://dify\_api](http://dify_api); │ proxy\_set\_header Host $host; │ proxy\_set\_header X-Real-IP $remote\_addr; │ proxy\_set\_header X-Forwarded-For $proxy\_add\_x\_forwarded\_for; │ proxy\_set\_header X-Forwarded-Proto $scheme; │ } │  
│ \# ── SSE (Server-Sent Events) for streaming ── │ location /v1/chat-messages { │ proxy\_pass [http://dify\_api](http://dify_api); │ proxy\_set\_header Host $host; │ proxy\_set\_header X-Real-IP $remote\_addr; │ proxy\_set\_header X-Forwarded-For $proxy\_add\_x\_forwarded\_for; │ proxy\_set\_header X-Forwarded-Proto $scheme; │ proxy\_set\_header Connection ''; │ proxy\_http\_version 1.1; │ chunked\_transfer\_encoding off; │ proxy\_buffering off; │ proxy\_cache off; │ proxy\_read\_timeout 600s; │ } │  
│ location /v1/completion-messages { │ proxy\_pass [http://dify\_api](http://dify_api); │ proxy\_set\_header Host $host; │ proxy\_set\_header X-Real-IP $remote\_addr; │ proxy\_set\_header X-Forwarded-For $proxy\_add\_x\_forwarded\_for; │ proxy\_set\_header X-Forwarded-Proto $scheme; │ proxy\_set\_header Connection ''; │ proxy\_http\_version 1.1; │ chunked\_transfer\_encoding off; │ proxy\_buffering off; │ proxy\_cache off; │ proxy\_read\_timeout 600s; │ } │  
│ \# ── Web UI (frontend) ── │ location / { │ proxy\_pass [http://dify\_web](http://dify_web); │ proxy\_set\_header Host $host; │ proxy\_set\_header X-Real-IP $remote\_addr; │ proxy\_set\_header X-Forwarded-For $proxy\_add\_x\_forwarded\_for; │ proxy\_set\_header X-Forwarded-Proto $scheme; │ } │  
│ \# ── WebSocket support ── │ location /ws { │ proxy\_pass [http://dify\_api](http://dify_api); │ proxy\_http\_version 1.1; │ proxy\_set\_header Upgrade $http\_upgrade; │ proxy\_set\_header Connection "upgrade"; │ proxy\_set\_header Host $host; │ proxy\_read\_timeout 86400; │ } │ } │ └── Dify container "dify-nginx" uses this config and Caddy proxies to dify-nginx:80

\---

\#\# 19\. OpenClaw / Open WebUI Integration Details

\#\#\# Open WebUI Configuration for LiteLLM Backend

configure\_open\_webui() │ ├── Open WebUI environment variables (in docker-compose): │  
│ OPENAI\_API\_BASE\_URL: [http://litellm:4000/v1](http://litellm:4000/v1) │ OPENAI\_API\_KEY: ${LITELLM\_MASTER\_KEY} │ OLLAMA\_BASE\_URL: [http://host.docker.internal:11434](http://host.docker.internal:11434) │ WEBUI\_AUTH: true │ WEBUI\_NAME: "AI Platform" │ ENABLE\_SIGNUP: true │ ENABLE\_RAG\_WEB\_SEARCH: true │ RAG\_EMBEDDING\_ENGINE: openai │ RAG\_OPENAI\_API\_BASE\_URL: [http://litellm:4000/v1](http://litellm:4000/v1) │ RAG\_OPENAI\_API\_KEY: ${LITELLM\_MASTER\_KEY} │ RAG\_EMBEDDING\_MODEL: nomic-embed-text │ ENABLE\_IMAGE\_GENERATION: false │ DEFAULT\_MODELS: "mistral,llama3.1:8b,gpt-4o-mini" │ ENABLE\_ADMIN\_EXPORT: true │ ENABLE\_COMMUNITY\_SHARING: false │ ├── Volume mounts: │ \- ${DATA\_DIR}/open-webui:/app/backend/data │ ├── Open WebUI sees ALL models via LiteLLM: │ ┌─────────────────────────────────────────────┐ │ │ Open WebUI Model Selector │ │ ├─────────────────────────────────────────────┤ │ │ LOCAL (Ollama via LiteLLM): │ │ │ • tinyllama │ │ │ • mistral │ │ │ • llama3.1:8b │ │ │ • codellama:7b │ │ │ • nomic-embed-text │ │ │ │ │ │ CLOUD (via LiteLLM): │ │ │ • gpt-4o │ │ │ • gpt-4o-mini │ │ │ • claude-3.5-sonnet │ │ │ • gemini-1.5-pro │ │ │ │ │ │ All requests → LiteLLM → provider │ │ │ Cost tracking unified across all models │ │ └─────────────────────────────────────────────┘ │ ├── RAG Integration: │ Open WebUI has built-in RAG that can use: │ 1\. Local documents uploaded via UI │ 2\. Web search results (via SearXNG or Google) │ 3\. External knowledge bases │  
│ For Google Drive documents: │ \- gdrive-sync.sh syncs to ${GDRIVE\_SYNC\_DIR} │ \- Configure Open WebUI to scan that directory │ \- Or use Dify's knowledge base (more advanced) │ └── Authentication: If SuperTokens is enabled, Open WebUI delegates auth via WEBUI\_AUTH\_TRUSTED\_EMAIL\_HEADER pattern (configured in Caddy as X-Auth-Email from SuperTokens middleware)

\#\#\# Open WebUI ↔ Dify Integration

Dual UI Strategy: │ ├── Open WebUI \= Simple chat interface │ \- End users who just want to chat │ \- Model switching on the fly │ \- Simple RAG (upload \+ ask) │ \- Ollama model management │ ├── Dify \= Advanced AI application builder │ \- Workflow automation │ \- Multi-step agents │ \- Complex RAG pipelines │ \- API endpoint generation │ \- Prompt engineering studio │ ├── Both share: │ \- LiteLLM as unified model gateway │ \- Same Ollama models │ \- Same cloud API keys │ \- Same PostgreSQL (different databases) │ \- Same Redis │ \- Same vector DB │ └── Cross-Integration: \- Dify APIs can be called from Open WebUI "Tools" \- n8n can orchestrate between both \- Flowise agents can use Dify knowledge bases

\---

\#\# 20\. Cost Management & Budget Controls

\#\#\# Architecture

Cost Management Flow: │ ├── Layer 1: LiteLLM (Real-time tracking) │ │ │ │ Every API request → LiteLLM logs: │ │ \- model, tokens (in/out), cost, latency │ │ \- stored in litellm PostgreSQL DB │ │ \- callbacks to custom webhook │ │ │ │ LiteLLM config (litellm\_config.yaml): │ │ litellm\_settings: │ │ success\_callback: \["postgres", "custom\_callback\_api"\] │ │ max\_budget: 500 \# global monthly limit USD │ │ budget\_duration: "monthly" │ │  
│ │ general\_settings: │ │ max\_parallel\_requests: 100 │ │ global\_max\_parallel\_requests: 200 │ │ │ └── Per-key budgets via LiteLLM admin API: │ curl \-X POST [http://litellm:4000/key/generate](http://litellm:4000/key/generate)  
 │ \-H "Authorization: Bearer ${LITELLM\_MASTER\_KEY}"  
 │ \-d '{ │ "max\_budget": 50.0, │ "budget\_duration": "monthly", │ "models": \["gpt-4o-mini", "mistral"\], │ "max\_parallel\_requests": 10, │ "tpm\_limit": 100000, │ "rpm\_limit": 60, │ "metadata": {"user": "team-a"} │ }' │ ├── Layer 2: Platform DB (Aggregated analytics) │ │ │ │ Materialized view: daily\_cost\_summary │ │ \- Refreshed every 15 minutes via pg\_cron or systemd │ │ \- Powers Grafana dashboards │ │ │ │ Budget alerts table checked by: │ │ \- Prometheus alerting rules │ │ \- n8n scheduled workflow │ │ \- Custom webhook from LiteLLM │ │ │ └── check\_budget() function returns: │ \- current spend vs budget │ \- percentage used │ \- whether hard limit is exceeded │ ├── Layer 3: Grafana Dashboards │ │ │ │ Dashboard: "AI Platform — Cost Overview" │ │ ┌──────────────────────────────────────────────┐ │ │ │ Monthly Spend │ Budget Remaining │ │ │ │ ████████░░ $347.22 │ ██░░░░░░░░ $152.78 │ │ │ │ of $500.00 (69.4%) │ 69.4% used │ │ │ ├──────────────────────────────────────────────┤ │ │ │ Cost by Model (30d) │ │ │ │ ┌───────────────────────────────┐ │ │ │ │ │ gpt-4o ████████ $180 │ │ │ │ │ │ claude-3.5 ██████ $98 │ │ │ │ │ │ gpt-4o-mini ███ $42 │ │ │ │ │ │ mistral(local)│ $0 │ │ │ │ │ │ llama3.1(local)│ $0 │ │ │ │ │ └───────────────────────────────┘ │ │ │ ├──────────────────────────────────────────────┤ │ │ │ Cost by User (30d) │ │ │ │ ┌───────────────────────────────┐ │ │ │ │ │ team-dev ████████ $210 │ │ │ │ │ │ team-support ████ $87 │ │ │ │ │ │ team-sales ██ $50 │ │ │ │ │ └───────────────────────────────┘ │ │ │ ├──────────────────────────────────────────────┤ │ │ │ Daily Spend Trend │ │ │ │ $25 ┤ ╭─╮ │ │ │ │ $20 ┤ ╭─╮ │ │ ╭╮ │ │ │ │ $15 ┤ ╭─╯ ╰──╯ ╰─╯╰╮ │ │ │ │ $10 ┤╭─╯ ╰──╮ │ │ │ │ $5 ┤╯ ╰── │ │ │ │ └───────────────────────── │ │ │ │ 1 5 10 15 20 25 │ │ │ ├──────────────────────────────────────────────┤ │ │ │ Cache Savings │ │ │ │ Requests cached: 12,847 (34.2%) │ │ │ │ Estimated savings: $89.50 │ │ │ │ │ │ │ │ Local vs Cloud │ │ │ │ Local model requests: 45,230 (68%) │ │ │ │ Cloud model requests: 21,340 (32%) │ │ │ │ Estimated local savings: $412.00 │ │ │ └──────────────────────────────────────────────┘ │ │ │ └── Dashboard provisioned automatically by Script 2 │ (JSON model in $CONFIG\_DIR/grafana/dashboards/) │ ├── Layer 4: Alert Rules │ │ │ │ Prometheus alerting rules: │ │  
│ │ groups: │ │ \- name: cost\_alerts │ │ rules: │ │ \- alert: BudgetWarning │ │ expr: ai\_platform\_monthly\_spend\_usd / ai\_platform\_monthly\_budget\_usd \> 0.8 │ │ for: 5m │ │ labels: │ │ severity: warning │ │ annotations: │ │ summary: "AI Platform spend at {{ $value | humanizePercentage }} of budget" │ │ │ │ \- alert: BudgetCritical │ │ expr: ai\_platform\_monthly\_spend\_usd / ai\_platform\_monthly\_budget\_usd \> 0.95 │ │ for: 5m │ │ labels: │ │ severity: critical │ │ annotations: │ │ summary: "AI Platform spend at {{ $ value | humanizePercentage }} — approaching limit" │ │ │ │ \- alert: UnusualSpendSpike │ │ expr: \> │ │ rate(ai\_platform\_daily\_spend\_usd\[1h\]) \> │ │ 2 \* avg\_over\_time(ai\_platform\_daily\_spend\_usd\[7d\]) │ │ for: 15m │ │ labels: │ │ severity: warning │ │ annotations: │ │ summary: "Unusual spending spike detected" │ │ │ │ \- alert: HighErrorRate │ │ expr: \> │ │ rate(litellm\_request\_errors\_total\[5m\]) / │ │ rate(litellm\_requests\_total\[5m\]) \> 0.05 │ │ for: 5m │ │ labels: │ │ severity: warning │ │ annotations: │ │ summary: "LiteLLM error rate above 5%" │ │ │ └── n8n workflow for alerts: │ Trigger: Webhook from Prometheus AlertManager │ Actions: │ 1\. Parse alert details │ 2\. Check budget\_alerts table for context │ 3\. Send notification: │ \- Slack webhook (if configured) │ \- Email (if SMTP configured) │ \- Webhook (custom) │ 4\. If hard\_limit exceeded: │ \- Call LiteLLM API to disable expensive models │ \- Log to audit\_log │ └── Layer 5: Smart Routing (Cost Optimization) │ │ LiteLLM router config for cost-aware routing: │  
 │ router\_settings: │ routing\_strategy: "cost-based" │ \# Try local model first, fall back to cloud │ model\_group\_alias: │ "default-chat": \["ollama/mistral", "gpt-4o-mini"\] │ "code-assist": \["ollama/codellama:7b", "gpt-4o"\] │  
 │ \# Fallback chain: local → cheap cloud → expensive cloud │ fallbacks: │ \- model\_name: "ollama/mistral" │ fallback: "gpt-4o-mini" │ \- model\_name: "gpt-4o-mini" │ fallback: "gpt-4o" │  
 │ Caching (Redis-backed): │ litellm\_settings: │ cache: true │ cache\_params: │ type: "redis" │ host: "redis" │ port: 6379 │ password: " $ {REDIS\_PASSWORD}" │ ttl: 3600 │ \# Semantic caching with embeddings │ supported\_call\_types: │ \- "acompletion" │ \- "completion" │ \- "aembedding" │ \- "embedding" │ └── Result: Automatic cost optimization \- Simple requests → local Ollama (free) \- Cache hits → zero cost \- Complex requests → cheapest capable cloud model \- Budget exceeded → block cloud, allow local only

\#\#\# Budget Management n8n Workflow

n8n Workflow: "Budget Monitor" (auto-imported) │ ├── Trigger: Cron every 15 minutes │ ├── Step 1: Query PostgreSQL │ SELECT \* FROM check\_budget('global'); │ SELECT \* FROM check\_budget('user', user\_id) │ FROM (SELECT DISTINCT user\_id FROM usage\_logs │ WHERE requested\_at \> NOW() \- INTERVAL '1 day'); │ ├── Step 2: Evaluate thresholds │ For each budget result: │ if pct\_used \>= alert\_threshold\_pct AND NOT already\_alerted\_today: │ → trigger alert │ if is\_exceeded AND hard\_limit: │ → trigger enforcement │ ├── Step 3: Alert (if threshold crossed) │ \- Log to audit\_log │ \- Send webhook/email/Slack │ \- Update last\_alert\_at │ ├── Step 4: Enforce (if hard limit exceeded) │ POST [http://litellm:4000/model/update](http://litellm:4000/model/update) │ { │ "model\_id": "\<cloud-models\>", │ "model\_info": { "mode": "blocked" } │ } │ → Cloud models disabled, local models still work │ ├── Step 5: Refresh materialized view │ SELECT refresh\_daily\_cost\_summary(); │ └── Step 6: Export metrics for Prometheus Write to /tmp/ai-platform-metrics.prom (node\_exporter textfile collector picks up)

\---  
\*\*End of Part 5 (Sections 17–20).\*\*  
\---

\#\# 21\. Docker Compose Generation (Dynamic Builder)

\#\#\# Generator Function

generate\_docker\_compose() │ ├── The compose file is built dynamically based on: │ \- ENABLED\_SERVICES from master.env │ \- GPU\_AVAILABLE flag │ \- Selected vector DB │ \- DNS/SSL configuration │ \- Hardware detection results │ ├── File: $COMPOSE\_DIR/docker-compose.yml │ ├── ── Header ── │ cat \> $COMPOSE\_DIR/docker-compose.yml \<\< 'HEADER' │ \# ═══════════════════════════════════════════════════ │ \# AI Platform — Docker Compose │ \# Auto-generated by Script 2 — DO NOT EDIT MANUALLY │ \# Regenerate with: script-2-deploy.sh \--regenerate │ \# ═══════════════════════════════════════════════════ │  
│ version: "3.8" │  
│ x-common-env: \&common-env │ TZ: ${TIMEZONE} │ PUID: 1000 │ PGID: 1000 │  
│ x-restart-policy: \&restart-policy │ restart: unless-stopped │  
│ x-logging: \&default-logging │ logging: │ driver: json-file │ options: │ max-size: "10m" │ max-file: "3" │  
│ HEADER │ ├── ── Networks ── │ cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< 'NETWORKS' │ networks: │ ai-platform: │ driver: bridge │ ipam: │ config: │ \- subnet: 172.28.0.0/16 │ monitoring: │ driver: bridge │  
│ NETWORKS │ ├── ── Volumes ── │ cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< EOF │ volumes: │ postgres\_data: │ driver: local │ driver\_opts: │ type: none │ o: bind │ device: ${DATA\_DIR}/postgres │ redis\_data: │ driver: local │ driver\_opts: │ type: none │ o: bind │ device: ${DATA\_DIR}/redis │ caddy\_data: │ driver: local │ caddy\_config: │ driver: local │  
│ EOF │ ├── ── Services Start ── │ echo "services:" \>\> $COMPOSE\_DIR/docker-compose.yml │ ├── ── Core: PostgreSQL ── │ cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< EOF │ \# ── PostgreSQL with pgvector ── │ postgres: │ image: pgvector/pgvector:pg16 │ container\_name: ai-postgres │ \<\<: \*restart-policy │ \<\<: \*default-logging │ environment: │ POSTGRES\_USER: ${POSTGRES\_USER} │ POSTGRES\_PASSWORD: ${POSTGRES\_PASSWORD} │ POSTGRES\_DB: aiplatform │ PGDATA: /var/lib/postgresql/data/pgdata │ volumes: │ \- postgres\_data:/var/lib/postgresql/data │ \- ${CONFIG\_DIR}/postgres/init.sql:/docker-entrypoint-initdb.d/init.sql:ro │ \- ${CONFIG\_DIR}/postgres/postgresql.conf:/etc/postgresql/postgresql.conf:ro │ command: postgres \-c config\_file=/etc/postgresql/postgresql.conf │ ports: │ \- "127.0.0.1:5432:5432" │ networks: │ ai-platform: │ ipv4\_address: 172.28.0.10 │ healthcheck: │ test: \["CMD-SHELL", "pg\_isready \-U ${POSTGRES\_USER} \-d aiplatform"\] │ interval: 10s │ timeout: 5s │ retries: 5 │ start\_period: 30s │ shm\_size: '256mb' │ deploy: │ resources: │ limits: │ memory: ${POSTGRES\_MEMORY\_LIMIT:-2G} │  
│ EOF │ ├── ── Core: Redis ── │ cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< EOF │ \# ── Redis with persistence ── │ redis: │ image: redis:7-alpine │ container\_name: ai-redis │ \<\<: \*restart-policy │ \<\<: \*default-logging │ command: \> │ redis-server │ \--requirepass ${REDIS\_PASSWORD} │ \--maxmemory ${REDIS\_MAX\_MEMORY:-512mb} │ \--maxmemory-policy allkeys-lru │ \--appendonly yes │ \--appendfsync everysec │ \--save 60 1000 │ \--save 300 100 │ volumes: │ \- redis\_data:/data │ ports: │ \- "127.0.0.1:6379:6379" │ networks: │ ai-platform: │ ipv4\_address: 172.28.0.11 │ healthcheck: │ test: \["CMD", "redis-cli", "-a", "${REDIS\_PASSWORD}", "ping"\] │ interval: 10s │ timeout: 5s │ retries: 5 │  
│ EOF │ ├── ── Core: Caddy ── │ cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< EOF │ \# ── Caddy Reverse Proxy ── │ caddy: │ image: caddy:2-alpine │ container\_name: ai-caddy │ \<\<: \*restart-policy │ \<\<: \*default-logging │ ports: │ \- "80:80" │ \- "443:443" │ \- "443:443/udp" │ volumes: │ \- ${CONFIG\_DIR}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro │ \- caddy\_data:/data │ \- caddy\_config:/config │ networks: │ ai-platform: │ ipv4\_address: 172.28.0.2 │ depends\_on: │ \- litellm │ healthcheck: │ test: \["CMD", "caddy", "version"\] │ interval: 30s │ timeout: 5s │ retries: 3 │  
│ EOF │ ├── ── LiteLLM ── │ cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< EOF │ \# ── LiteLLM Proxy ── │ litellm: │ image: ghcr.io/berriai/litellm:main-latest │ container\_name: ai-litellm │ \<\<: \*restart-policy │ \<\<: \*default-logging │ env\_file: │ \- ${ENV\_DIR}/litellm.env │ volumes: │ \- ${CONFIG\_DIR}/litellm/litellm\_config.yaml:/app/config.yaml:ro │ command: \["--config", "/app/config.yaml", "--port", "4000", "--num\_workers", "4"\] │ ports: │ \- "127.0.0.1:4000:4000" │ networks: │ ai-platform: │ ipv4\_address: 172.28.0.20 │ depends\_on: │ postgres: │ condition: service\_healthy │ redis: │ condition: service\_healthy │ healthcheck: │ test: \["CMD", "curl", "-f", "[http://localhost:4000/health"\]](http://localhost:4000/health) │ interval: 30s │ timeout: 10s │ retries: 5 │ start\_period: 40s │ deploy: │ resources: │ limits: │ memory: 1G │  
│ EOF │ ├── ── Conditional: Dify Stack ── │ if service\_enabled "dify"; then │ cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< EOF │ \# ── Dify API ── │ dify-api: │ image: langgenius/dify-api:latest │ container\_name: ai-dify-api │ \<\<: \*restart-policy │ \<\<: \*default-logging │ env\_file: │ \- ${ENV\_DIR}/dify.env │ volumes: │ \- ${DATA\_DIR}/dify/storage:/app/api/storage │ networks: │ ai-platform: │ ipv4\_address: 172.28.0.30 │ depends\_on: │ postgres: │ condition: service\_healthy │ redis: │ condition: service\_healthy │ deploy: │ resources: │ limits: │ memory: 2G │  
│ \# ── Dify Worker ── │ dify-worker: │ image: langgenius/dify-api:latest │ container\_name: ai-dify-worker │ \<\<: \*restart-policy │ \<\<: \*default-logging │ env\_file: │ \- ${ENV\_DIR}/dify.env │ command: celery \-A app.celery worker \-P gevent \-c 1 \--loglevel INFO │ volumes: │ \- ${DATA\_DIR}/dify/storage:/app/api/storage │ networks: │ \- ai-platform │ depends\_on: │ \- dify-api │ deploy: │ resources: │ limits: │ memory: 1G │  
│ \# ── Dify Web ── │ dify-web: │ image: langgenius/dify-web:latest │ container\_name: ai-dify-web │ \<\<: \*restart-policy │ \<\<: \*default-logging │ environment: │ CONSOLE\_API\_URL: https://${DIFY\_DOMAIN} │ APP\_API\_URL: https://${DIFY\_DOMAIN} │ SENTRY\_DSN: "" │ networks: │ ai-platform: │ ipv4\_address: 172.28.0.31 │  
│ \# ── Dify Nginx ── │ dify-nginx: │ image: nginx:alpine │ container\_name: ai-dify-nginx │ \<\<: \*restart-policy │ \<\<: \*default-logging │ volumes: │ \- ${CONFIG\_DIR}/dify/nginx.conf:/etc/nginx/conf.d/default.conf:ro │ networks: │ ai-platform: │ ipv4\_address: 172.28.0.32 │ depends\_on: │ \- dify-api │ \- dify-web │  
│ \# ── Dify Sandbox ── │ dify-sandbox: │ image: langgenius/dify-sandbox:latest │ container\_name: ai-dify-sandbox │ \<\<: \*restart-policy │ \<\<: \*default-logging │ environment: │ API\_KEY: ${DIFY\_SANDBOX\_KEY} │ GIN\_MODE: release │ WORKER\_TIMEOUT: 15 │ networks: │ \- ai-platform │  
│ EOF │ fi │ ├── ── Conditional: n8n ── │ if service\_enabled "n8n"; then │ cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< EOF │ \# ── n8n Workflow Automation ── │ n8n: │ image: docker.n8n.io/n8nio/n8n:latest │ container\_name: ai-n8n │ \<\<: \*restart-policy │ \<\<: \*default-logging │ env\_file: │ \- ${ENV\_DIR}/n8n.env │ environment: │ \<\<: \*common-env │ N8N\_HOST: ${N8N\_DOMAIN} │ N8N\_PORT: 5678 │ N8N\_PROTOCOL: https │ WEBHOOK\_URL: https://${N8N\_DOMAIN}/ │ N8N\_EDITOR\_BASE\_URL: https://${N8N\_DOMAIN}/ │ DB\_TYPE: postgresdb │ DB\_POSTGRESDB\_HOST: postgres │ DB\_POSTGRESDB\_PORT: 5432 │ DB\_POSTGRESDB\_DATABASE: n8n │ DB\_POSTGRESDB\_USER: ${POSTGRES\_USER} │ DB\_POSTGRESDB\_PASSWORD: ${POSTGRES\_PASSWORD} │ N8N\_ENCRYPTION\_KEY: ${N8N\_ENCRYPTION\_KEY} │ EXECUTIONS\_MODE: regular │ GENERIC\_TIMEZONE: ${TIMEZONE} │ N8N\_DIAGNOSTICS\_ENABLED: false │ N8N\_PERSONALIZATION\_ENABLED: false │ volumes: │ \- ${DATA\_DIR}/n8n:/home/node/.n8n │ ports: │ \- "127.0.0.1:5678:5678" │ networks: │ ai-platform: │ ipv4\_address: 172.28.0.40 │ depends\_on: │ postgres: │ condition: service\_healthy │ healthcheck: │ test: \["CMD-SHELL", "curl \-f [http://localhost:5678/healthz](http://localhost:5678/healthz) || exit 1"\] │ interval: 30s │ timeout: 10s │ retries: 5 │ start\_period: 30s │ deploy: │ resources: │ limits: │ memory: 1G │  
│ EOF │ fi │ ├── ── Conditional: Open WebUI ── │ if service\_enabled "open-webui"; then │ cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< EOF │ \# ── Open WebUI ── │ open-webui: │ image: ghcr.io/open-webui/open-webui:main │ container\_name: ai-open-webui │ \<\<: \*restart-policy │ \<\<: \*default-logging │ environment: │ OPENAI\_API\_BASE\_URL: [http://litellm:4000/v1](http://litellm:4000/v1) │ OPENAI\_API\_KEY: ${LITELLM\_MASTER\_KEY} │ OLLAMA\_BASE\_URL: [http://host.docker.internal:11434](http://host.docker.internal:11434) │ WEBUI\_AUTH: "true" │ WEBUI\_NAME: "AI Platform" │ WEBUI\_URL: https://${OPEN\_WEBUI\_DOMAIN} │ ENABLE\_SIGNUP: "true" │ ENABLE\_RAG\_WEB\_SEARCH: "true" │ RAG\_EMBEDDING\_ENGINE: openai │ RAG\_OPENAI\_API\_BASE\_URL: [http://litellm:4000/v1](http://litellm:4000/v1) │ RAG\_OPENAI\_API\_KEY: ${LITELLM\_MASTER\_KEY} │ RAG\_EMBEDDING\_MODEL: nomic-embed-text │ ENABLE\_IMAGE\_GENERATION: "false" │ ENABLE\_COMMUNITY\_SHARING: "false" │ DEFAULT\_MODELS: "${DEFAULT\_CHAT\_MODEL:-mistral}" │ volumes: │ \- ${DATA\_DIR}/open-webui:/app/backend/data │ ports: │ \- "127.0.0.1:3000:8080" │ networks: │ ai-platform: │ ipv4\_address: 172.28.0.50 │ depends\_on: │ \- litellm │ extra\_hosts: │ \- "host.docker.internal:host-gateway" │ healthcheck: │ test: \["CMD", "curl", "-f", "[http://localhost:8080/"\]](http://localhost:8080/) │ interval: 30s │ timeout: 10s │ retries: 5 │ start\_period: 30s │ deploy: │ resources: │ limits: │ memory: 1G │  
│ EOF │ fi │ ├── ── Conditional: Flowise ── │ if service\_enabled "flowise"; then │ cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< EOF │ \# ── Flowise ── │ flowise: │ image: flowiseai/flowise:latest │ container\_name: ai-flowise │ \<\<: \*restart-policy │ \<\<: \*default-logging │ environment: │ FLOWISE\_USERNAME: ${FLOWISE\_USER} │ FLOWISE\_PASSWORD: ${FLOWISE\_PASSWORD} │ DATABASE\_TYPE: postgres │ DATABASE\_HOST: postgres │ DATABASE\_PORT: 5432 │ DATABASE\_NAME: aiplatform │ DATABASE\_USER: ${POSTGRES\_USER} │ DATABASE\_PASSWORD: ${POSTGRES\_PASSWORD} │ APIKEY\_PATH: /root/.flowise │ LOG\_LEVEL: info │ volumes: │ \- ${DATA\_DIR}/flowise:/root/.flowise │ ports: │ \- "127.0.0.1:3001:3000" │ networks: │ ai-platform: │ ipv4\_address: 172.28.0.55 │ depends\_on: │ postgres: │ condition: service\_healthy │ healthcheck: │ test: \["CMD", "curl", "-f", "[http://localhost:3000/"\]](http://localhost:3000/) │ interval: 30s │ timeout: 10s │ retries: 5 │  
│ EOF │ fi │ ├── ── Conditional: Vector DB (Qdrant) ── │ if \[\[ "${VECTOR\_DB}" \== "qdrant" \]\]; then │ cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< EOF │ \# ── Qdrant Vector Database ── │ qdrant: │ image: qdrant/qdrant:latest │ container\_name: ai-qdrant │ \<\<: \*restart-policy │ \<\<: \*default-logging │ environment: │ QDRANT\_\_SERVICE\_\_API\_KEY: ${QDRANT\_API\_KEY} │ QDRANT\_\_STORAGE\_\_STORAGE\_PATH: /qdrant/storage │ QDRANT\_\_STORAGE\_\_SNAPSHOTS\_PATH: /qdrant/snapshots │ volumes: │ \- ${DATA\_DIR}/qdrant/storage:/qdrant/storage │ \- ${DATA\_DIR}/qdrant/snapshots:/qdrant/snapshots │ ports: │ \- "127.0.0.1:6333:6333" │ \- "127.0.0.1:6334:6334" │ networks: │ ai-platform: │ ipv4\_address: 172.28.0.60 │ healthcheck: │ test: \["CMD", "curl", "-f", "[http://localhost:6333/healthz"\]](http://localhost:6333/healthz) │ interval: 30s │ timeout: 10s │ retries: 5 │ deploy: │ resources: │ limits: │ memory: ${QDRANT\_MEMORY\_LIMIT:-1G} │  
│ EOF │ fi │ ├── ── Conditional: Vector DB (Weaviate) ── │ if \[\[ "${VECTOR\_DB}" \== "weaviate" \]\]; then │ cat \>\> $ COMPOSE\_DIR/docker-compose.yml \<\< EOF │ \# ── Weaviate Vector Database ── │ weaviate: │ image: semitechnologies/weaviate:latest │ container\_name: ai-weaviate │ \<\<: \*restart-policy │ \<\<: \*default-logging │ environment: │ QUERY\_DEFAULTS\_LIMIT: 25 │ AUTHENTICATION\_APIKEY\_ENABLED: "true" │ AUTHENTICATION\_APIKEY\_ALLOWED\_KEYS: " $ {WEAVIATE\_API\_KEY}" │ AUTHENTICATION\_APIKEY\_USERS: "admin" │ PERSISTENCE\_DATA\_PATH: /var/lib/weaviate │ DEFAULT\_VECTORIZER\_MODULE: none │ CLUSTER\_HOSTNAME: node1 │ volumes: │ \- ${DATA\_DIR}/weaviate:/var/lib/weaviate │ ports: │ \- "127.0.0.1:8080:8080" │ \- "127.0.0.1:50051:50051" │ networks: │ ai-platform: │ ipv4\_address: 172.28.0.60 │ healthcheck: │ test: \["CMD", "curl", "-f", "[http://localhost:8080/v1/.well-known/ready"\]](http://localhost:8080/v1/.well-known/ready) │ interval: 30s │ timeout: 10s │ retries: 5 │ deploy: │ resources: │ limits: │ memory: ${WEAVIATE\_MEMORY\_LIMIT:-1G} │  
│ EOF │ fi │ ├── ── Conditional: Vector DB (Milvus) ── │ if \[\[ "${VECTOR\_DB}" \== "milvus" \]\]; then │ cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< EOF │ \# ── Milvus Dependencies ── │ milvus-etcd: │ image: quay.io/coreos/etcd:v3.5.5 │ container\_name: ai-milvus-etcd │ \<\<: \*restart-policy │ environment: │ ETCD\_AUTO\_COMPACTION\_MODE: revision │ ETCD\_AUTO\_COMPACTION\_RETENTION: "1000" │ ETCD\_QUOTA\_BACKEND\_BYTES: "4294967296" │ ETCD\_SNAPSHOT\_COUNT: "50000" │ volumes: │ \- ${DATA\_DIR}/milvus/etcd:/etcd │ command: etcd \-advertise-client-urls=[http://127.0.0.1:2379](http://127.0.0.1:2379) \-listen-client-urls [http://0.0.0.0:2379](http://0.0.0.0:2379) \--data-dir /etcd │ networks: │ \- ai-platform │  
│ milvus-minio: │ image: minio/minio:RELEASE.2023-03-20T20-16-18Z │ container\_name: ai-milvus-minio │ \<\<: \*restart-policy │ environment: │ MINIO\_ACCESS\_KEY: minioadmin │ MINIO\_SECRET\_KEY: minioadmin │ volumes: │ \- ${DATA\_DIR}/milvus/minio:/minio\_data │ command: minio server /minio\_data \--console-address ":9001" │ networks: │ \- ai-platform │ healthcheck: │ test: \["CMD", "curl", "-f", "[http://localhost:9000/minio/health/live"\]](http://localhost:9000/minio/health/live) │ interval: 30s │ timeout: 10s │ retries: 5 │  
│ \# ── Milvus Standalone ── │ milvus: │ image: milvusdb/milvus:v2.3-latest │ container\_name: ai-milvus │ \<\<: \*restart-policy │ \<\<: \*default-logging │ environment: │ ETCD\_ENDPOINTS: milvus-etcd:2379 │ MINIO\_ADDRESS: milvus-minio:9000 │ volumes: │ \- ${DATA\_DIR}/milvus/data:/var/lib/milvus │ command: \["milvus", "run", "standalone"\] │ ports: │ \- "127.0.0.1:19530:19530" │ \- "127.0.0.1:9091:9091" │ networks: │ ai-platform: │ ipv4\_address: 172.28.0.60 │ depends\_on: │ \- milvus-etcd │ \- milvus-minio │ healthcheck: │ test: \["CMD", "curl", "-f", "[http://localhost:9091/healthz"\]](http://localhost:9091/healthz) │ interval: 30s │ timeout: 10s │ retries: 5 │ deploy: │ resources: │ limits: │ memory: ${MILVUS\_MEMORY\_LIMIT:-2G} │  
│ EOF │ fi │ ├── ── Conditional: SuperTokens ── │ if service\_enabled "supertokens"; then │ cat \>\> $ COMPOSE\_DIR/docker-compose.yml \<\< EOF │ \# ── SuperTokens Authentication ── │ supertokens: │ image: registry.supertokens.io/supertokens/supertokens-postgresql:latest │ container\_name: ai-supertokens │ \<\<: \*restart-policy │ \<\<: \*default-logging │ environment: │ POSTGRESQL\_CONNECTION\_URI: "postgresql:// $ {POSTGRES\_USER}:${POSTGRES\_PASSWORD}@postgres:5432/supertokens" │ API\_KEYS: ${SUPERTOKENS\_API\_KEY} │ ports: │ \- "127.0.0.1:3567:3567" │ networks: │ ai-platform: │ ipv4\_address: 172.28.0.70 │ depends\_on: │ postgres: │ condition: service\_healthy │ healthcheck: │ test: \["CMD", "curl", "-f", "[http://localhost:3567/hello"\]](http://localhost:3567/hello) │ interval: 30s │ timeout: 10s │ retries: 5 │  
│ EOF │ fi │ ├── ── Conditional: Monitoring Stack ── │ if service\_enabled "monitoring"; then │ cat \>\> $COMPOSE\_DIR/docker-compose.yml \<\< EOF │ \# ── Prometheus ── │ prometheus: │ image: prom/prometheus:latest │ container\_name: ai-prometheus │ \<\<: \*restart-policy │ \<\<: \*default-logging │ command: │ \- '--config.file=/etc/prometheus/prometheus.yml' │ \- '--storage.tsdb.path=/prometheus' │ \- '--storage.tsdb.retention.time=30d' │ \- '--storage.tsdb.retention.size=5GB' │ \- '--web.enable-lifecycle' │ volumes: │ \- ${CONFIG\_DIR}/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro │ \- ${CONFIG\_DIR}/prometheus/alert\_rules.yml:/etc/prometheus/alert\_rules.yml:ro │ \- ${DATA\_DIR}/prometheus:/prometheus │ ports: │ \- "127.0.0.1:9090:9090" │ networks: │ ai-platform: │ ipv4\_address: 172.28.0.80 │ monitoring: │ healthcheck: │ test: \["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "[http://localhost:9090/-/healthy"\]](http://localhost:9090/-/healthy) │ interval: 30s │ timeout: 10s │ retries: 5 │  
│ \# ── Grafana ── │ grafana: │ image: grafana/grafana:latest │ container\_name: ai-grafana │ \<\<: \*restart-policy │ \<\<: \*default-logging │ environment: │ GF\_SECURITY\_ADMIN\_USER: ${GRAFANA\_USER} │ GF\_SECURITY\_ADMIN\_PASSWORD: ${GRAFANA\_PASSWORD} │ GF\_SERVER\_ROOT\_URL: https://${GRAFANA\_DOMAIN} │ GF\_DATABASE\_TYPE: postgres │ GF\_DATABASE\_HOST: postgres:5432 │ GF\_DATABASE\_NAME: grafana │ GF\_DATABASE\_USER: ${POSTGRES\_USER} │ GF\_DATABASE\_PASSWORD: ${POSTGRES\_PASSWORD} │ GF\_USERS\_ALLOW\_SIGN\_UP: "false" │ GF\_AUTH\_ANONYMOUS\_ENABLED: "false" │ GF\_INSTALL\_PLUGINS: grafana-clock-panel,grafana-simple-json-datasource │ volumes: │ \- ${DATA\_DIR}/grafana:/var/lib/grafana │ \- ${CONFIG\_DIR}/grafana/provisioning:/etc/grafana/provisioning:ro │ \- ${CONFIG\_DIR}/grafana/dashboards:/var/lib/grafana/dashboards:ro │ ports: │ \- "127.0.0.1:3100:3000" │ networks: │ ai-platform: │ ipv4\_address: 172.28.0.81 │ monitoring: │ depends\_on: │ postgres: │ condition: service\_healthy │ healthcheck: │ test: \["CMD", "curl", "-f", "[http://localhost:3000/api/health"\]](http://localhost:3000/api/health) │ interval: 30s │ timeout: 10s │ retries: 5 │  
│ \# ── Node Exporter ── │ node-exporter: │ image: prom/node-exporter:latest │ container\_name: ai-node-exporter │ \<\<: \*restart-policy │ command: │ \- '--path.rootfs=/host' │ \- '--collector.textfile.directory=/etc/node-exporter/textfile' │ volumes: │ \- /:/host:ro,rslave │ \- /tmp:/etc/node-exporter/textfile:ro │ ports: │ \- "127.0.0.1:9100:9100" │ networks: │ \- monitoring │ pid: host │  
│ \# ── cAdvisor ── │ cadvisor: │ image: gcr.io/cadvisor/cadvisor:latest │ container\_name: ai-cadvisor │ \<\<: \*restart-policy │ volumes: │ \- /:/rootfs:ro │ \- /var/run:/var/run:ro │ \- /sys:/sys:ro │ \- /var/lib/docker/:/var/lib/docker:ro │ \- /dev/disk/:/dev/disk:ro │ ports: │ \- "127.0.0.1:8081:8080" │ networks: │ \- monitoring │ privileged: true │ devices: │ \- /dev/kmsg │  
│ EOF │ fi │ └── echo " ✓ docker-compose.yml generated" echo " Services: $(grep 'container\_name:' $COMPOSE\_DIR/docker-compose.yml | wc \-l)"

\#\#\# PostgreSQL Custom Configuration

generate\_postgres\_conf() │ ├── File: $CONFIG\_DIR/postgres/postgresql.conf │ ├── \# Auto-tuned based on available RAM: ${TOTAL\_RAM\_GB}GB │  
│ \# ── Memory ── │ shared\_buffers \= ${PG\_SHARED\_BUFFERS} \# \~25% of RAM allocated to PG │ effective\_cache\_size \= ${PG\_EFFECTIVE\_CACHE} \# \~50% of RAM allocated to PG │ work\_mem \= ${PG\_WORK\_MEM} \# Per-operation sort memory │ maintenance\_work\_mem \= ${PG\_MAINT\_MEM} \# For VACUUM, CREATE INDEX │  
│ \# ── WAL ── │ wal\_buffers \= 16MB │ max\_wal\_size \= 2GB │ min\_wal\_size \= 512MB │ checkpoint\_completion\_target \= 0.9 │  
│ \# ── Connections ── │ max\_connections \= 200 │  
│ \# ── Query Planner ── │ random\_page\_cost \= 1.1 \# SSD optimized │ effective\_io\_concurrency \= 200 \# SSD optimized │  
│ \# ── pgvector ── │ \# Enable parallel index builds for HNSW │ max\_parallel\_workers\_per\_gather \= 4 │ max\_parallel\_workers \= 8 │ max\_parallel\_maintenance\_workers \= 4 │  
│ \# ── Logging ── │ log\_min\_duration\_statement \= 1000 \# Log queries \> 1s │ log\_checkpoints \= on │ log\_lock\_waits \= on │  
│ \# ── Locale ── │ timezone \= '${TIMEZONE}' │ ├── Memory auto-tuning logic: │ PG\_ALLOCATED\_RAM=$(( TOTAL\_RAM\_GB / 4 )) \# 25% of total RAM to PG │ if \[\[ $PG\_ALLOCATED\_RAM \-lt 1 \]\]; then PG\_ALLOCATED\_RAM=1; fi │ if \[\[ $ PG\_ALLOCATED\_RAM \-gt 8 \]\]; then PG\_ALLOCATED\_RAM=8; fi │  
│ PG\_SHARED\_BUFFERS=" $ {PG\_ALLOCATED\_RAM}GB" │ PG\_EFFECTIVE\_CACHE=" $ (( PG\_ALLOCATED\_RAM \* 2 ))GB" │ PG\_WORK\_MEM=" $ (( PG\_ALLOCATED\_RAM \* 64 ))MB" │ PG\_MAINT\_MEM=" $ (( PG\_ALLOCATED\_RAM \* 256 ))MB" │ └── echo " ✓ PostgreSQL config generated ( $ {PG\_ALLOCATED\_RAM}GB shared\_buffers)"

\---

\#\# 22\. Caddyfile Generation

generate\_caddyfile() │ ├── File: $CONFIG\_DIR/caddy/Caddyfile │ ├── ── Global Options ── │ { │ email ${ADMIN\_EMAIL} │  
│ \# If using IP-only (no domain), use internal CA │ (if\[\[" {SSL\_MODE}" \== "selfsigned" \]\]; then │ echo " local\_certs" │ fi) │  
│ \# Rate limiting │ order rate\_limit before basicauth │  
│ \# Logging │ log { │ output file /data/access.log { │ roll\_size 100mb │ roll\_keep 5 │ } │ } │ } │ ├── ── Snippet: Common Security Headers ── │ (security-headers) { │ header { │ X-Content-Type-Options "nosniff" │ X-Frame-Options "SAMEORIGIN" │ Referrer-Policy "strict-origin-when-cross-origin" │ X-XSS-Protection "1; mode=block" │ \-Server │ } │ } │  
│ (proxy-common) { │ header\_up X-Real-IP {remote\_host} │ header\_up X-Forwarded-For {remote\_host} │ header\_up X-Forwarded-Proto {scheme} │ } │ ├── ── LiteLLM (always enabled) ── │ ${LITELLM\_DOMAIN} { │ import security-headers │  
│ \# Health check endpoint (no auth) │ @health path /health /health/liveliness /health/readiness │ handle @health { │ reverse\_proxy litellm:4000 │ } │  
│ \# API endpoints │ handle { │ reverse\_proxy litellm:4000 { │ import proxy-common │ transport http { │ read\_timeout 300s │ write\_timeout 300s │ } │ } │ } │ } │ ├── ── Conditional: Dify ── │ if service\_enabled "dify"; then │ cat \>\> Caddyfile \<\< EOF │ ${DIFY\_DOMAIN} { │ import security-headers │  
│ reverse\_proxy dify-nginx:80 { │ import proxy-common │ transport http { │ read\_timeout 600s │ write\_timeout 600s │ } │ \# SSE support │ flush\_interval \-1 │ } │ } │ EOF │ fi │ ├── ── Conditional: n8n ── │ if service\_enabled "n8n"; then │ cat \>\> Caddyfile \<\< EOF │ ${N8N\_DOMAIN} { │ import security-headers │  
│ reverse\_proxy n8n:5678 { │ import proxy-common │ transport http { │ read\_timeout 300s │ } │ \# WebSocket support for n8n │ flush\_interval \-1 │ } │ } │ EOF │ fi │ ├── ── Conditional: Open WebUI ── │ if service\_enabled "open-webui"; then │ cat \>\> Caddyfile \<\< EOF │ ${OPEN\_WEBUI\_DOMAIN} { │ import security-headers │  
│ reverse\_proxy open-webui:8080 { │ import proxy-common │ transport http { │ read\_timeout 600s │ write\_timeout 600s │ } │ \# SSE support for streaming │ flush\_interval \-1 │ } │ } │ EOF │ fi │ ├── ── Conditional: Flowise ── │ if service\_enabled "flowise"; then │ cat \>\> Caddyfile \<\< EOF │ ${FLOWISE\_DOMAIN} { │ import security-headers │  
│ reverse\_proxy flowise:3000 { │ import proxy-common │ } │ } │ EOF │ fi │ ├── ── Conditional: Grafana ── │ if service\_enabled "monitoring"; then │ cat \>\> Caddyfile \<\< EOF │ ${GRAFANA\_DOMAIN} { │ import security-headers │  
│ reverse\_proxy grafana:3000 { │ import proxy-common │ } │ } │ EOF │ fi │ ├── ── IP-only mode (no DNS) ── │ If SSL\_MODE \== "selfsigned" or no domains configured: │  
│ :443 { │ tls internal │ import security-headers │  
│ \# Route by path prefix │ handle /litellm/\* { │ uri strip\_prefix /litellm │ reverse\_proxy litellm:4000 │ } │  
│ handle /dify/\* { │ uri strip\_prefix /dify │ reverse\_proxy dify-nginx:80 │ } │  
│ handle /n8n/\* { │ uri strip\_prefix /n8n │ reverse\_proxy n8n:5678 │ } │  
│ handle /chat/\* { │ uri strip\_prefix /chat │ reverse\_proxy open-webui:8080 │ } │  
│ handle /flowise/\* { │ uri strip\_prefix /flowise │ reverse\_proxy flowise:3000 │ } │  
│ handle /grafana/\* { │ uri strip\_prefix /grafana │ reverse\_proxy grafana:3000 │ } │  
│ \# Default landing page │ handle { │ respond "AI Platform is running. Services: /litellm /dify /n8n /chat /flowise /grafana" 200 │ } │ } │ └── echo " ✓ Caddyfile generated" echo " Mode: (if\[\[−n" {DOMAIN\_BASE}" \]\]; then echo "subdomain (${DOMAIN\_BASE})"; else echo "IP-only path-based"; fi)"

\---

\#\# 23\. LiteLLM Configuration YAML

generate\_litellm\_config() │ ├── File: $CONFIG\_DIR/litellm/litellm\_config.yaml │ ├── \# ═══════════════════════════════════════════════════ │ \# LiteLLM Configuration — Auto-generated by Script 2 │ \# ═══════════════════════════════════════════════════ │  
│ \# ── Model List ── │ model\_list: │ ├── ── Always: Ollama models ── │ \# ── Local Ollama Models ── │ \- model\_name: tinyllama │ litellm\_params: │ model: ollama/tinyllama │ api\_base: [http://host.docker.internal:11434](http://host.docker.internal:11434) │ stream: true │ model\_info: │ mode: chat │ input\_cost\_per\_token: 0 │ output\_cost\_per\_token: 0 │  
│ \# Add each configured Ollama model │ for model in ${OLLAMA\_MODELS\[@\]}; do │ model\_name=$(echo $model | cut \-d: \-f1) │ cat \>\> config \<\< EOF │ \- model\_name: ${model\_name} │ litellm\_params: │ model: ollama/${model} │ api\_base: [http://host.docker.internal:11434](http://host.docker.internal:11434) │ stream: true │ model\_info: │ mode: chat │ input\_cost\_per\_token: 0 │ output\_cost\_per\_token: 0 │ EOF │ done │ ├── ── Conditional: OpenAI models ── │ if \[\[ \-n "${OPENAI\_API\_KEY}" \]\]; then │ cat \>\> config \<\< EOF │ \# ── OpenAI Models ── │ \- model\_name: gpt-4o │ litellm\_params: │ model: openai/gpt-4o │ api\_key: os.environ/OPENAI\_API\_KEY │  
│ \- model\_name: gpt-4o-mini │ litellm\_params: │ model: openai/gpt-4o-mini │ api\_key: os.environ/OPENAI\_API\_KEY │  
│ \- model\_name: gpt-4-turbo │ litellm\_params: │ model: openai/gpt-4-turbo │ api\_key: os.environ/OPENAI\_API\_KEY │  
│ \- model\_name: gpt-3.5-turbo │ litellm\_params: │ model: openai/gpt-3.5-turbo │ api\_key: os.environ/OPENAI\_API\_KEY │  
│ \- model\_name: text-embedding-3-small │ litellm\_params: │ model: openai/text-embedding-3-small │ api\_key: os.environ/OPENAI\_API\_KEY │ model\_info: │ mode: embedding │  
│ \- model\_name: text-embedding-3-large │ litellm\_params: │ model: openai/text-embedding-3-large │ api\_key: os.environ/OPENAI\_API\_KEY │ model\_info: │ mode: embedding │ EOF │ fi │ ├── ── Conditional: Anthropic models ── │ if \[\[ \-n "${ANTHROPIC\_API\_KEY}" \]\]; then │ cat \>\> config \<\< EOF │ \# ── Anthropic Models ── │ \- model\_name: claude-3.5-sonnet │ litellm\_params: │ model: anthropic/claude-3-5-sonnet-20241022 │ api\_key: os.environ/ANTHROPIC\_API\_KEY │  
│ \- model\_name: claude-3-haiku │ litellm\_params: │ model: anthropic/claude-3-haiku-20240307 │ api\_key: os.environ/ANTHROPIC\_API\_KEY │  
│ \- model\_name: claude-3-opus │ litellm\_params: │ model: anthropic/claude-3-opus-20240229 │ api\_key: os.environ/ANTHROPIC\_API\_KEY │ EOF │ fi │ ├── ── Conditional: Google models ── │ if \[\[ \-n "${GEMINI\_API\_KEY}" \]\]; then │ cat \>\> config \<\< EOF │ \# ── Google Gemini Models ── │ \- model\_name: gemini-1.5-pro │ litellm\_params: │ model: gemini/gemini-1.5-pro-latest │ api\_key: os.environ/GEMINI\_API\_KEY │  
│ \- model\_name: gemini-1.5-flash │ litellm\_params: │ model: gemini/gemini-1.5-flash-latest │ api\_key: os.environ/GEMINI\_API\_KEY │ EOF │ fi │ ├── ── Conditional: Groq models ── │ if \[\[ \-n "${GROQ\_API\_KEY}" \]\]; then │ cat \>\> config \<\< EOF │ \# ── Groq Models (fast inference) ── │ \- model\_name: groq-llama3-70b │ litellm\_params: │ model: groq/llama3-70b-8192 │ api\_key: os.environ/GROQ\_API\_KEY │  
│ \- model\_name: groq-mixtral │ litellm\_params: │ model: groq/mixtral-8x7b-32768 │ api\_key: os.environ/GROQ\_API\_KEY │ EOF │ fi │ ├── ── Router Settings ── │ cat \>\> config \<\< EOF │  
│ \# ── Router Configuration ── │ router\_settings: │ routing\_strategy: simple-shuffle │ num\_retries: 3 │ timeout: 120 │ retry\_after: 5 │ allowed\_fails: 3 │ cooldown\_time: 60 │  
│ \# Fallback chains │ fallbacks: │ \- model\_name: mistral │ fallback: gpt-4o-mini │ (if\[\[−n" {OPENAI\_API\_KEY}" \]\]; then echo " │ \- model\_name: gpt-4o │ fallback: claude-3.5-sonnet"; fi) │  
│ \# ── LiteLLM Settings ── │ litellm\_settings: │ \# Callbacks │ success\_callback: \["postgres"\] │ failure\_callback: \["postgres"\] │ service\_callback: \["postgres"\] │  
│ \# Caching │ cache: true │ cache\_params: │ type: redis │ host: redis │ port: 6379 │ password: os.environ/REDIS\_PASSWORD │ ttl: 3600 │ namespace: litellm\_cache │  
│ \# Budgets │ max\_budget: ${MONTHLY\_BUDGET\_USD:-500} │ budget\_duration: monthly │  
│ \# Logging │ set\_verbose: false │ json\_logs: true │  
│ \# Rate Limiting │ global\_max\_parallel\_requests: 200 │ max\_request\_size\_mb: 100 │  
│ \# Drop unsupported params silently │ drop\_params: true │  
│ \# ── General Settings ── │ general\_settings: │ master\_key: os.environ/LITELLM\_MASTER\_KEY │ database\_url: os.environ/DATABASE\_URL │  
│ \# Admin UI │ store\_model\_in\_db: true │  
│ \# Alerting │ alerting: │ \- slack │ alerting\_threshold: 300 \# alert if request takes \> 300s │  
│ EOF │ └── echo " ✓ LiteLLM config generated" echo " Models configured: $(grep 'model\_name:' $CONFIG\_DIR/litellm/litellm\_config.yaml | wc \-l)"

\---

\#\# 24\. Monitoring Stack Configuration

\#\#\# Prometheus Configuration

generate\_prometheus\_config() │ ├── File: $CONFIG\_DIR/prometheus/prometheus.yml │ ├── global: │ scrape\_interval: 15s │ evaluation\_interval: 15s │ scrape\_timeout: 10s │  
│ \# ── Alert Rules ── │ rule\_files: │ \- "alert\_rules.yml" │  
│ \# ── Scrape Configs ── │ scrape\_configs: │ \# ── Prometheus self ── │ \- job\_name: 'prometheus' │ static\_configs: │ \- targets: \['localhost:9090'\] │  
│ \# ── Node Exporter (host metrics) ── │ \- job\_name: 'node-exporter' │ static\_configs: │ \- targets: \['node-exporter:9100'\] │  
│ \# ── cAdvisor (container metrics) ── │ \- job\_name: 'cadvisor' │ static\_configs: │ \- targets: \['cadvisor:8080'\] │  
│ \# ── LiteLLM metrics ── │ \- job\_name: 'litellm' │ metrics\_path: /metrics │ static\_configs: │ \- targets: \['litellm:4000'\] │  
│ \# ── PostgreSQL Exporter ── │ \- job\_name: 'postgres' │ static\_configs: │ \- targets: \['postgres-exporter:9187'\] │  
│ \# ── Redis Exporter ── │ \- job\_name: 'redis' │ static\_configs: │ \- targets: \['redis-exporter:9121'\] │  
│ \# ── Ollama metrics (if available) ── │ \- job\_name: 'ollama' │ static\_configs: │ \- targets: \['host.docker.internal:11434'\] │ metrics\_path: /api/metrics │ scrape\_interval: 30s │  
│ \# ── Custom platform metrics (textfile collector) ── │ \- job\_name: 'ai-platform-custom' │ static\_configs: │ \- targets: \['node-exporter:9100'\] │ metrics\_path: /metrics │ params: │ collect\[\]: │ \- textfile │ └── File: $CONFIG\_DIR/prometheus/alert\_rules.yml (Full alert rules as documented in Section 20\)

\#\#\# Grafana Provisioning

generate\_grafana\_provisioning() │ ├── Directory structure: │ $CONFIG\_DIR/grafana/ │ ├── provisioning/ │ │ ├── datasources/ │ │ │ └── datasources.yml │ │ └── dashboards/ │ │ └── dashboards.yml │ └── dashboards/ │ ├── ai-platform-overview.json │ ├── litellm-metrics.json │ ├── cost-management.json │ └── infrastructure.json │ ├── File: provisioning/datasources/datasources.yml │ apiVersion: 1 │  
│ datasources: │ \- name: Prometheus │ type: prometheus │ access: proxy │ url: [http://prometheus:9090](http://prometheus:9090) │ isDefault: true │ editable: false │  
│ \- name: PostgreSQL │ type: postgres │ access: proxy │ url: postgres:5432 │ database: platform │ user: ${POSTGRES\_USER} │ secureJsonData: │ password: ${POSTGRES\_PASSWORD} │ jsonData: │ sslmode: disable │ maxOpenConns: 5 │ maxIdleConns: 2 │ connMaxLifetime: 14400 │ postgresVersion: 1600 │ timescaledb: false │ editable: false │  
│ \- name: LiteLLM-DB │ type: postgres │ access: proxy │ url: postgres:5432 │ database: litellm │ user: ${POSTGRES\_USER} │ secureJsonData: │ password: ${POSTGRES\_PASSWORD} │ jsonData: │ sslmode: disable │ postgresVersion: 1600 │ editable: false │ ├── File: provisioning/dashboards/dashboards.yml │ apiVersion: 1 │  
│ providers: │ \- name: 'AI Platform' │ orgId: 1 │ folder: 'AI Platform' │ type: file │ disableDeletion: false │ editable: true │ updateIntervalSeconds: 30 │ options: │ path: /var/lib/grafana/dashboards │ foldersFromFilesStructure: false │ ├── Dashboard: ai-platform-overview.json │ (Auto-generated JSON with panels): │  
│ Row 1: Status Overview │ \- Service health status (up/down per container) │ \- Total requests today │ \- Current spend (month) │ \- Active models count │  
│ Row 2: Request Metrics │ \- Requests per minute (time series) │ \- Latency distribution (histogram) │ \- Error rate (gauge) │ \- Cache hit rate (gauge) │  
│ Row 3: Cost Analytics │ \- Daily spend (bar chart) │ \- Cost by model (pie chart) │ \- Cost by user (table) │ \- Budget gauge (threshold markers) │  
│ Row 4: Model Performance │ \- Tokens per second by model │ \- Time to first token │ \- Model availability % │ \- Queue depth │  
│ Row 5: Infrastructure │ \- CPU usage (host \+ per container) │ \- Memory usage (host \+ per container) │ \- Disk I/O │ \- Network traffic │ \- GPU utilization (if available) │  
│ Row 6: RAG & Documents │ \- Documents indexed count │ \- Last sync timestamp │ \- Embedding generation rate │ \- Vector DB collection sizes │ └── echo " ✓ Grafana provisioning generated" echo " Dashboards: 4 auto-provisioned" echo " Datasources: 3 configured"

\#\#\# Dashboard JSON Generation Helper

generate\_dashboard\_json() │ ├── Rather than embedding 1000+ line JSON, Script 2 uses a │ template approach with variable substitution: │ ├── \# Panel template function │ grafana\_panel() { │ local id=$1 title=$2 type=$3 query=$4 x=$5 y=$6 w=$7 h=$8 │ cat \<\< PANEL │ { │ "id": ${id}, │ "title": "${title}", │ "type": "${type}", │ "gridPos": {"x": ${x}, "y": ${y}, "w": ${w}, "h": ${h}}, │ "datasource": {"type": "prometheus", "uid": "prometheus"}, │ "targets": \[ │ { │ "expr": "${query}", │ "refId": "A" │ } │ \], │ "fieldConfig": { │ "defaults": { │ "color": {"mode": "palette-classic"} │ } │ } │ } │ PANEL │ } │ ├── \# Build dashboard │ PANELS="" │ PANELS+= $ (grafana\_panel 1 "Total Requests" "stat"  
 │ 'sum(increase(litellm\_requests\_total\[24h\]))' 0 0 6 4\) │ PANELS+="," │ PANELS+= $ (grafana\_panel 2 "Monthly Spend" "stat"  
 │ 'ai\_platform\_monthly\_spend\_usd' 6 0 6 4\) │ PANELS+="," │ PANELS+= $ (grafana\_panel 3 "Error Rate" "gauge"  
 │ 'rate(litellm\_request\_errors\_total\[5m\])/rate(litellm\_requests\_total\[5m\])\*100' 12 0 6 4\) │ PANELS+="," │ PANELS+= $ (grafana\_panel 4 "Cache Hit Rate" "gauge"  
 │ 'rate(litellm\_cache\_hits\_total\[1h\])/rate(litellm\_requests\_total\[1h\])\*100' 18 0 6 4\) │ \# ... additional panels ... │ └── \# Wrap in dashboard envelope cat \> $ CONFIG\_DIR/grafana/dashboards/ai-platform-overview.json \<\< EOF { "dashboard": { "id": null, "uid": "ai-platform-overview", "title": "AI Platform — Overview", "tags": \["ai-platform", "auto-generated"\], "timezone": "browser", "refresh": "30s", "time": {"from": "now-24h", "to": "now"}, "panels": \[ $ {PANELS}\] }, "overwrite": true } EOF

\---

\*\*End of Part 6 (Sections 21–24).\*\*  
\---

\#\# 25\. Backup & Restore System

\#\#\# Backup Script (Generated by Script 2, Phase 14\)

File: $ BASE\_DIR/scripts/backup.sh │ ├── \#\!/bin/bash │ set \-euo pipefail │  
│ \# ═══════════════════════════════════════════════════ │ \# AI Platform — Backup Script │ \# Usage: ./backup.sh \[full|db|configs|volumes\] \[--upload\] │ \# ═══════════════════════════════════════════════════ │ ├── ── Configuration ── │ source /opt/ai-platform/env/master.env │ BACKUP\_DIR=" $ {BACKUP\_BASE\_DIR:-/opt/ai-platform/backups}" │ TIMESTAMP= $ (date \+%Y%m%d\_%H%M%S) │ BACKUP\_NAME="ai-platform-backup- $ {TIMESTAMP}" │ CURRENT\_BACKUP="${BACKUP\_DIR}/${BACKUP\_NAME}" │ LOG="/var/log/ai-platform/backup.log" │ RETENTION\_DAYS=${BACKUP\_RETENTION\_DAYS:-7} │ BACKUP\_TYPE="${1:-full}" │ UPLOAD\_FLAG="${2:-}" │ ├── ── Logging ── │ log() { │ echo "$(date \-u \+%Y-%m-%dT%H:%M:%SZ) | BACKUP | 1"∣tee−a" LOG" │ } │ ├── ── Pre-flight ── │ preflight\_check() { │ \# Check disk space (need at least 2x current data size free) │ local data\_size=$(du \-sm {DATA\_DIR} | awk '{print 1}') │ local free\_space= $ (df \-m ${BACKUP\_DIR} | tail \-1 | awk '{print $4}') │  
│ if \[\[ $free\_space \-lt $(( data\_size \* 2 )) \]\]; then │ log "ERROR: Insufficient disk space. Need $(( data\_size \* 2 ))MB, have ${free\_space}MB" │ exit 1 │ fi │  
│ mkdir \-p "${CURRENT\_BACKUP}"/{db,configs,volumes,meta} │ log "Starting ${BACKUP\_TYPE} backup → ${CURRENT\_BACKUP}" │ } │ ├── ── Database Backup ── │ backup\_databases() { │ log "Backing up PostgreSQL databases..." │  
│ local DBS=("aiplatform" "litellm" "dify" "n8n" "supertokens" "grafana" "platform") │  
│ for db in "${DBS\[@\]}"; do │ log " Dumping ${db}..." │ docker exec ai-postgres pg\_dump  
 │ \-U ${POSTGRES\_USER}  
 │ \-d ${db}  
 │ \--format=custom  
 │ \--compress=6  
 │ \--verbose  
 │ 2\>\>" $ LOG"  
 │ \> " $ {CURRENT\_BACKUP}/db/${db}.dump" || { │ log " WARNING: Failed to dump ${db} (may not exist yet)" │ continue │ } │  
│ local size= (du−sh" {CURRENT\_BACKUP}/db/${db}.dump" | awk '{print $1}') │ log " ✓ ${db}: ${size}" │ done │  
│ \# Also take a full cluster dump as safety net │ log " Creating full cluster dump..." │ docker exec ai-postgres pg\_dumpall  
 │ \-U ${POSTGRES\_USER}  
 │ \--clean  
 │ 2\>\>" $ LOG"  
 │ | gzip \> " $ {CURRENT\_BACKUP}/db/full\_cluster.sql.gz" │  
│ log "✓ Database backup complete" │ } │ ├── ── Redis Backup ── │ backup\_redis() { │ log "Backing up Redis..." │  
│ \# Trigger synchronous save │ docker exec ai-redis redis-cli  
 │ \-a "${REDIS\_PASSWORD}"  
 │ \--no-auth-warning  
 │ BGSAVE │  
│ \# Wait for save to complete │ local timeout=60 │ while \[\[ $ timeout \-gt 0 \]\]; do │ local status= $ (docker exec ai-redis redis-cli  
 │ \-a "${REDIS\_PASSWORD}"  
 │ \--no-auth-warning  
 │ LASTSAVE) │ sleep 2 │ local new\_status= $ (docker exec ai-redis redis-cli  
 │ \-a " $ {REDIS\_PASSWORD}"  
 │ \--no-auth-warning  
 │ LASTSAVE) │ if \[\[ " status"\!=" new\_status" \]\] || \[\[ $ timeout \-lt 55 \]\]; then │ break │ fi │ timeout= $ ((timeout \- 2)) │ done │  
│ cp "${DATA\_DIR}/redis/dump.rdb" "${CURRENT\_BACKUP}/db/redis-dump.rdb" │  
│ \# Also backup AOF if exists │ if \[\[ \-f "${DATA\_DIR}/redis/appendonly.aof" \]\]; then │ cp "${DATA\_DIR}/redis/appendonly.aof" "${CURRENT\_BACKUP}/db/redis-appendonly.aof" │ fi │  
│ log "✓ Redis backup complete" │ } │ ├── ── Configuration Backup ── │ backup\_configs() { │ log "Backing up configurations..." │  
│ \# All config files │ tar czf "${CURRENT\_BACKUP}/configs/config-files.tar.gz"  
 │ \-C /  
 │ opt/ai-platform/config  
 │ opt/ai-platform/env  
 │ opt/ai-platform/compose  
 │ opt/ai-platform/scripts  
 │ 2\>\>" $ LOG" │  
│ \# Docker compose files │ cp " $ {COMPOSE\_DIR}/docker-compose.yml" "${CURRENT\_BACKUP}/configs/" │  
│ \# Crontabs │ crontab \-l \> "${CURRENT\_BACKUP}/configs/crontab.bak" 2\>/dev/null || true │  
│ \# Systemd services │ cp /etc/systemd/system/ollama.service "${CURRENT\_BACKUP}/configs/" 2\>/dev/null || true │  
│ \# UFW rules │ if command \-v ufw &\>/dev/null; then │ ufw status verbose \> "${CURRENT\_BACKUP}/configs/ufw-rules.txt" │ fi │  
│ \# Installed packages list │ dpkg \--get-selections \> "${CURRENT\_BACKUP}/configs/dpkg-selections.txt" │  
│ log "✓ Configuration backup complete" │ } │ ├── ── Volume Data Backup ── │ backup\_volumes() { │ log "Backing up volume data..." │  
│ local VOLUMES=( │ "dify/storage" │ "n8n" │ "open-webui" │ "flowise" │ "caddy" │ ) │  
│ for vol in "${VOLUMES\[@\]}"; do │ if \[\[ \-d "${DATA\_DIR}/${vol}" \]\]; then │ log " Archiving ${vol}..." │ tar czf "${CURRENT\_BACKUP}/volumes/${vol////*}.tar.gz"*  
 *│ \-C "${DATA\_DIR}"*  
 *│ "${vol}"*  
 *│ 2\>\>" $ LOG" │ local size= $ (du \-sh "${CURRENT\_BACKUP}/volumes/${vol////*}.tar.gz" | awk '{print $1}') │ log " ✓ ${vol}: ${size}" │ fi │ done │  
│ \# Vector DB data (can be large — optional) │ if \[\[ \-d "${DATA\_DIR}/qdrant" \]\]; then │ log " Archiving Qdrant data..." │ \# Use Qdrant snapshot API instead of raw files │ curl \-s \-X POST "[http://localhost:6333/snapshots](http://localhost:6333/snapshots)"  
 │ \-H "api-key: ${QDRANT\_API\_KEY}"  
 │ \> "${CURRENT\_BACKUP}/volumes/qdrant-snapshot-info.json" │  
│ \# Copy snapshot file │ local snap\_name= (jq−r′.result.name′" {CURRENT\_BACKUP}/volumes/qdrant-snapshot-info.json") │ if \[\[ \-n " snap\_name" \]\] && \[\[ " snap\_name" \!= "null" \]\]; then │ curl \-s "[http://localhost:6333/snapshots/${snap\_name}](http://localhost:6333/snapshots/${snap_name})"  
 │ \-H "api-key: ${QDRANT\_API\_KEY}"  
 │ \-o "${CURRENT\_BACKUP}/volumes/qdrant-snapshot.tar" │ log " ✓ Qdrant snapshot: ${snap\_name}" │ fi │ fi │  
│ log "✓ Volume backup complete" │ } │ ├── ── Metadata ── │ save\_metadata() { │ log "Saving backup metadata..." │  
 │ cat \> "${CURRENT\_BACKUP}/meta/backup-info.json" \<\< EOF │ { │ "timestamp": " $ (date \-u \+%Y-%m-%dT%H:%M:%SZ)", │ "hostname": " $ (hostname)", │ "backup\_type": "${BACKUP\_TYPE}", │ "backup\_name": "${BACKUP\_NAME}", │ "platform\_version": "$(grep SCRIPT\_2\_VERSION ${ENV\_DIR}/master.env | cut \-d= \-f2)", │ "docker\_compose\_hash": "$(md5sum ${COMPOSE\_DIR}/docker-compose.yml | awk '{print $1}')", │ "services\_running": $(docker ps \--format '{{.Names}}' | jq \-R \-s 'split("\\n") | map(select(. \!= ""))'), │ "database\_sizes": { │ $(docker exec ai-postgres psql \-U ${POSTGRES\_USER} \-d aiplatform \-t \-c  
 │ "SELECT json\_object\_agg(datname, pg\_size\_pretty(pg\_database\_size(datname))) │ FROM pg\_database WHERE datistemplate \= false;" 2\>/dev/null || echo '"error": "unavailable"') │ }, │ "disk\_usage": { │ "data\_dir": "$(du \-sh {DATA\_DIR} | awk '{print 1}')", │ "backup\_size": " (du \-sh ${CURRENT\_BACKUP} | awk '{print 1}')" │ } │ } │ EOF │  
│ \# Docker image versions │ docker ps \--format '{{.Image}}' | sort \-u \> " $ {CURRENT\_BACKUP}/meta/docker-images.txt" │  
│ \# Environment snapshot (redacted) │ grep \-v \-E '(PASSWORD|KEY|SECRET|TOKEN)' ${ENV\_DIR}/master.env  
 │ \> "${CURRENT\_BACKUP}/meta/env-redacted.txt" │  
│ log "✓ Metadata saved" │ } │ ├── ── Create Archive ── │ create\_archive() { │ log "Creating compressed archive..." │ │ cd "${BACKUP\_DIR}" │ tar czf "${BACKUP\_NAME}.tar.gz" "${BACKUP\_NAME}/" │  
│ \# Generate checksum │ sha256sum "${BACKUP\_NAME}.tar.gz" \> "${BACKUP\_NAME}.tar.gz.sha256" │  
│ local final\_size= (du−sh" {BACKUP\_NAME}.tar.gz" | awk '{print $1}') │ log "✓ Archive created: ${BACKUP\_NAME}.tar.gz (${final\_size})" │  
│ \# Cleanup temp directory │ rm \-rf "${CURRENT\_BACKUP}" │ } │ ├── ── Upload to Google Drive ── │ upload\_backup() { │ if \[\[ "${UPLOAD\_FLAG}" \== "--upload" \]\] && command \-v rclone &\>/dev/null; then │ log "Uploading to Google Drive..." │  
│ rclone copy  
 │ "${BACKUP\_DIR}/${BACKUP\_NAME}.tar.gz"  
 │ "gdrive:AI-Platform-Backups/"  
 │ \--progress  
 │ \--transfers 1  
 │ 2\>\>" $ LOG" │  
│ rclone copy  
 │ " $ {BACKUP\_DIR}/${BACKUP\_NAME}.tar.gz.sha256"  
 │ "gdrive:AI-Platform-Backups/"  
 │ 2\>\>"$LOG" │  
│ log "✓ Uploaded to Google Drive" │ fi │ } │ ├── ── Rotation ── │ rotate\_backups() { │ log "Rotating old backups (keeping ${RETENTION\_DAYS} days)..." │  
│ \# Local rotation │ find "${BACKUP\_DIR}" \-name "ai-platform-backup-*.tar.gz"*  
 *│ \-mtime \+${RETENTION\_DAYS} \-delete \-print | while read f; do │ log " Deleted: (basename f)" │ done │*  
*│ find " $ {BACKUP\_DIR}" \-name "*.sha256" \-mtime \+${RETENTION\_DAYS} \-delete │  
│ \# Remote rotation (keep 30 days on GDrive) │ if command \-v rclone &\>/dev/null; then │ rclone delete "gdrive:AI-Platform-Backups/"  
 │ \--min-age 30d  
 │ 2\>\>" $ LOG" || true │ fi │  
│ local remaining= $ (ls \-1 ${BACKUP\_DIR}/ai-platform-backup-\*.tar.gz 2\>/dev/null | wc \-l) │ log "✓ Rotation complete. ${remaining} backups retained locally" │ } │ ├── ── Main ── │ main() { │ preflight\_check │  
│ case "${BACKUP\_TYPE}" in │ full) │ backup\_databases │ backup\_redis │ backup\_configs │ backup\_volumes │ ;; │ db) │ backup\_databases │ backup\_redis │ ;; │ configs) │ backup\_configs │ ;; │ volumes) │ backup\_volumes │ ;; │ \*) │ echo "Usage: $0 \[full|db|configs|volumes\] \[--upload\]" │ exit 1 │ ;; │ esac │  
│ save\_metadata │ create\_archive │ upload\_backup │ rotate\_backups │  
│ log "════════════════════════════════════════════" │ log "BACKUP COMPLETE: ${BACKUP\_NAME}.tar.gz" │ log "════════════════════════════════════════════" │ } │  
│ main "$@" │ └── Crontab entry (installed by Script 2): 0 2 \* \* \* /opt/ai-platform/scripts/backup.sh full \--upload \>\> /var/log/ai-platform/backup-cron.log 2\>&1

\#\#\# Restore Script

File: $ BASE\_DIR/scripts/restore.sh │ ├── \#\!/bin/bash │ set \-euo pipefail │  
│ \# ═══════════════════════════════════════════════════ │ \# AI Platform — Restore Script │ \# Usage: ./restore.sh \<backup-archive.tar.gz\> \[--confirm\] │ \# ═══════════════════════════════════════════════════ │ ├── ARCHIVE=" {1:?Usage: 0 \<backup.tar.gz\> \[--confirm\]}" │ CONFIRM=" $ {2:-}" │ RESTORE\_DIR="/tmp/ai-platform-restore- $ (date \+%s)" │ LOG="/var/log/ai-platform/restore.log" │ ├── ── Validation ── │ validate() { │ \[\[ \-f " ARCHIVE" \]\] || { echo "File not found: ARCHIVE"; exit 1; } │  
│ \# Verify checksum if available │ if \[\[ \-f " $ {ARCHIVE}.sha256" \]\]; then │ echo "Verifying checksum..." │ sha256sum \-c "${ARCHIVE}.sha256" || { echo "CHECKSUM FAILED"; exit 1; } │ echo " ✓ Checksum verified" │ fi │  
│ \# Extract and check metadata │ mkdir \-p " $ RESTORE\_DIR" │ tar xzf " ARCHIVE"−C" RESTORE\_DIR" │  
│ local backup\_dir= (ls" RESTORE\_DIR") │ local meta\_file=" $ {RESTORE\_DIR}/${backup\_dir}/meta/backup-info.json" │  
│ if \[\[ \-f "$meta\_file" \]\]; then │ echo "═══ Backup Info ═══" │ echo "Date: $(jq \-r '.timestamp' $meta\_file)" │ echo "Type: $(jq \-r '.backup\_type' $meta\_file)" │ echo "Host: $(jq \-r '.hostname' $meta\_file)" │ echo "Version: $(jq \-r '.platform\_version' $meta\_file)" │ echo "Size: (jq−r′.disku​sage.backups​ize′ meta\_file)" │ echo "═══════════════════" │ fi │  
│ if \[\[ " $ CONFIRM" \!= "--confirm" \]\]; then │ echo "" │ echo "⚠ WARNING: This will overwrite current data\!" │ echo " Run with \--confirm to proceed" │ echo " Recommended: take a backup first with ./backup.sh full" │ rm \-rf "$RESTORE\_DIR" │ exit 0 │ fi │ } │ ├── ── Stop Services ── │ stop\_services() { │ echo "Stopping services..." │ cd ${COMPOSE\_DIR} │ docker compose down \--timeout 30 │ echo " ✓ Services stopped" │ } │ ├── ── Restore Databases ── │ restore\_databases() { │ local backup\_path="$1" │ echo "Restoring databases..." │  
│ \# Start only postgres │ docker compose up \-d postgres │ sleep 10 \# Wait for PG to be ready │  
│ \# Wait for health │ local retries=30 │ until docker exec ai-postgres pg\_isready \-U POSTGRESU​SER∣∣\[\[ retries \-eq 0 \]\]; do │ sleep 2 │ retries= $ ((retries \- 1)) │ done │  
│ \# Restore each database │ for dump\_file in ${backup\_path}/db/*.dump; do │ local db\_name= (basename" dump\_file" .dump) │ echo " Restoring ${db\_name}..." │*  
*│ \# Drop and recreate │ docker exec ai-postgres psql \-U ${POSTGRES\_USER} \-c*  
 *│ "SELECT pg\_terminate\_backend(pid) FROM pg\_stat\_activity WHERE datname='${db\_name}';"*  
 *│ 2\>/dev/null || true │ docker exec ai-postgres psql \-U ${POSTGRES\_USER} \-c*  
 *│ "DROP DATABASE IF EXISTS ${db\_name};" 2\>/dev/null || true │ docker exec ai-postgres psql \-U ${POSTGRES\_USER} \-c*  
 *│ "CREATE DATABASE ${db\_name} OWNER ${POSTGRES\_USER};" │*  
*│ \# Restore from dump │ cat "$dump\_file" | docker exec \-i ai-postgres pg\_restore*  
 *│ \-U ${POSTGRES\_USER}*  
 *│ \-d ${db\_name}*  
 *│ \--no-owner*  
 *│ \--no-privileges*  
 *│ \--clean*  
 *│ \--if-exists*  
 *│ 2\>\>"$LOG" || { │ echo " ⚠ Warning: Some errors during ${db\_name} restore (may be normal)" │ } │*  
*│ echo " ✓ ${db\_name} restored" │ done │ } │ ├── ── Restore Redis ── │ restore\_redis() { │ local backup\_path=" $ 1" │ echo "Restoring Redis..." │*  
*│ if \[\[ \-f " $ {backup\_path}/db/redis-dump.rdb" \]\]; then │ cp "${backup\_path}/db/redis-dump.rdb" "${DATA\_DIR}/redis/dump.rdb" │ echo " ✓ Redis data restored" │ fi │ } │ ├── ── Restore Configs ── │ restore\_configs() { │ local backup\_path=" $ 1" │ echo "Restoring configurations..." │*  
*│ if \[\[ \-f " $ {backup\_path}/configs/config-files.tar.gz" \]\]; then │ \# Backup current configs first │ cp \-r /opt/ai-platform/config /opt/ai-platform/config.pre-restore.bak │*  
*│ tar xzf "${backup\_path}/configs/config-files.tar.gz" \-C / │ echo " ✓ Configuration files restored" │ fi │ } │ ├── ── Restore Volumes ── │ restore\_volumes() { │ local backup\_path="$1" │ echo "Restoring volume data..." │*  
*│ for archive in ${backup\_path}/volumes/*.tar.gz; do │ local name= (basename" archive" .tar.gz) │ echo " Extracting ${name}..." │ tar xzf " archive"−C" {DATA\_DIR}/" │ echo " ✓ ${name}" │ done │ } │ ├── ── Main ── │ main() { │ validate │  
│ local backup\_path="${RESTORE\_DIR}/$(ls ${RESTORE\_DIR})" │  
│ echo "" │ echo "Starting restore..." │  
│ stop\_services │  
│ \[\[ \-d "${backup\_path}/db" \]\] && restore\_databases " $ backup\_path" │ \[\[ \-f " {backup\_path}/db/redis-dump.rdb" \]\] && restore\_redis " backup\_path" │ \[\[ \-d " {backup\_path}/configs" \]\] && restore\_configs " backup\_path" │ \[\[ \-d " $ {backup\_path}/volumes" \]\] && restore\_volumes "$backup\_path" │  
│ \# Start all services │ echo "Starting all services..." │ cd ${COMPOSE\_DIR} │ docker compose up \-d │  
│ echo "" │ echo "Waiting for services to start..." │ sleep 30 │  
│ \# Run health checks │ /opt/ai-platform/scripts/ai-status.sh │  
│ \# Cleanup │ rm \-rf " $ RESTORE\_DIR" │  
│ echo "" │ echo "═══════════════════════════════════════" │ echo "RESTORE COMPLETE" │ echo "═══════════════════════════════════════" │ } │  
│ main " $ @"

\---

\#\# 26\. Convenience Scripts

\#\#\# ai-status

File: $BASE\_DIR/scripts/ai-status.sh Symlink: /usr/local/bin/ai-status │ ├── \#\!/bin/bash │ source /opt/ai-platform/env/master.env 2\>/dev/null || true │ ├── echo "═══════════════════════════════════════════════════" │ echo " AI PLATFORM STATUS — $ (date)" │ echo "═══════════════════════════════════════════════════" │ ├── ── Docker Services ── │ echo "" │ echo "── Docker Services ──" │ printf "%-25s %-12s %-10s %s\\n" "CONTAINER" "STATUS" "HEALTH" "UPTIME" │ printf "%-25s %-12s %-10s %s\\n" "─────────" "──────" "──────" "──────" │  
│ docker ps \-a \--filter "name=ai-"  
 │ \--format '{{.Names}}\\t{{.Status}}' |  
 │ while IFS= $ '\\t' read name status; do │ \# Parse health │ health="—" │ if echo " $ status" | grep \-q "healthy"; then health="✓ healthy" │ elif echo " $ status" | grep \-q "unhealthy"; then health="✗ unhealthy" │ elif echo " $ status" | grep \-q "starting"; then health="◌ starting" │ fi │  
│ \# Parse uptime │ uptime= (echo" status" | grep \-oP 'Up \\K.*' | sed 's/ (.*)//') │  
│ \# Color code │ if echo " $ status" | grep \-q "Up"; then │ state="running" │ else │ state="stopped" │ fi │  
│ printf "%-25s %-12s %-10s %s\\n" " name"" state" " health"" uptime" │ done │ ├── ── Resource Usage ── │ echo "" │ echo "── Resource Usage ──" │ printf "%-25s %-10s %-10s %-10s %s\\n" "CONTAINER" "CPU %" "MEM" "MEM %" "NET I/O" │ printf "%-25s %-10s %-10s %-10s %s\\n" "─────────" "─────" "───" "─────" "───────" │  
│ docker stats \--no-stream \--format  
 │ '{{.Name}}\\t{{.CPUPerc}}\\t{{.MemUsage}}\\t{{.MemPerc}}\\t{{.NetIO}}'  
 │ $ (docker ps \--filter "name=ai-" \-q) 2\>/dev/null |  
 │ while IFS= $ '\\t' read name cpu mem memperc net; do │ printf "%-25s %-10s %-10s %-10s %s\\n" " name"" cpu" " mem"" memperc" "$net" │ done │ ├── ── Ollama ── │ echo "" │ echo "── Ollama Models ──" │ if command \-v ollama &\>/dev/null && systemctl is-active ollama &\>/dev/null; then │ ollama list 2\>/dev/null || echo " (unavailable)" │ else │ echo " Ollama not running" │ fi │ ├── ── GPU Status ── │ if command \-v nvidia-smi &\>/dev/null; then │ echo "" │ echo "── GPU Status ──" │ nvidia-smi \--query-gpu=name,temperature.gpu,utilization.gpu,utilization.memory,memory.used,memory.total  
 │ \--format=csv,noheader,nounits 2\>/dev/null |  
 │ while IFS=, read name temp gpu\_util mem\_util mem\_used mem\_total; do │ echo " ${name}: ${temp}°C | GPU: ${gpu\_util}% | VRAM: ${mem\_used}/${mem\_total} MiB (${mem\_util}%)" │ done │ fi │ ├── ── Endpoints ── │ echo "" │ echo "── Service Endpoints ──" │  
│ check\_endpoint() { │ local name=$1 url= $ 2 │ local code= (curl−s−o/dev/null−w" url" 2\>/dev/null) │ if \[\[ " code"= (200∣301∣302∣307∣308) \]\]; then │ printf " ✓ %-15s %s (HTTP %s)\\n" " name"" url" " $ code" │ else │ printf " ✗ %-15s %s (HTTP %s)\\n" " name"" url" " $ code" │ fi │ } │  
│ check\_endpoint "LiteLLM" "[http://localhost:4000/health](http://localhost:4000/health)" │ \[\[ \-n "${DIFY\_DOMAIN:-}" \]\] && check\_endpoint "Dify" "[http://localhost:5001/health](http://localhost:5001/health)" │ \[\[ \-n "${N8N\_DOMAIN:-}" \]\] && check\_endpoint "n8n" "[http://localhost:5678/healthz](http://localhost:5678/healthz)" │ \[\[ \-n "${OPEN\_WEBUI\_DOMAIN:-}" \]\] && check\_endpoint "Open WebUI" "[http://localhost:3000/](http://localhost:3000/)" │ check\_endpoint "Caddy" "[http://localhost:80](http://localhost:80)" │ ├── ── Disk Usage ── │ echo "" │ echo "── Disk Usage ──" │ echo " Data directory: $(du \-sh ${DATA\_DIR:-/opt/ai-platform/data} 2\>/dev/null | awk '{print $1}')" │ echo " Docker images: $(docker system df \--format '{{.Size}}' 2\>/dev/null | head \-1)" │ echo " Docker volumes: $(docker system df \--format '{{.Size}}' 2\>/dev/null | tail \-1)" │ echo " System free: (df \-h / | tail \-1 | awk '{print 4}')" │ ├── ── Cost Summary ── │ echo "" │ echo "── Cost Summary (this month) ──" │ \# Query LiteLLM for spend │ local spend= $ (curl \-s "[http://localhost:4000/global/spend/report](http://localhost:4000/global/spend/report)"  
 │ \-H "Authorization: Bearer ${LITELLM\_MASTER\_KEY:-}" 2\>/dev/null |  
 │ jq \-r '.total\_spend // "unavailable"' 2\>/dev/null || echo "unavailable") │ echo " API spend: ${spend}" │ echo " Budget: ${MONTHLY\_BUDGET\_USD:-not set}" │ └── echo "" echo "═══════════════════════════════════════════════════"

\#\#\# ai-logs

File: $ BASE\_DIR/scripts/ai-logs.sh Symlink: /usr/local/bin/ai-logs │ ├── \#\!/bin/bash │ \# Usage: ai-logs \[service\] \[--follow|-f\] \[--lines|-n NUM\] │  
│ SERVICE=" $ {1:-all}" │ FOLLOW="" │ LINES="100" │  
│ shift || true │ while \[\[ $ \# \-gt 0 \]\]; do │ case " $ 1" in │ \-f|--follow) FOLLOW="--follow" ;; │ \-n|--lines) LINES=" $ 2"; shift ;; │ esac │ shift │ done │ ├── case " $ SERVICE" in │ all) │ docker compose \-f /opt/ai-platform/compose/docker-compose.yml  
 │ logs \--tail="$LINES" $ FOLLOW │ ;; │ litellm|dify|n8n|postgres|redis|caddy|grafana|prometheus) │ docker logs ai- {SERVICE} \--tail="$LINES" FOLLOW 2\>&1 │ ;; │ dify-api|dify-worker|dify-web) │ docker logs ai- {SERVICE} \--tail="$LINES" FOLLOW 2\>&1 │ ;; │ ollama) │ journalctl \-u ollama \--no-pager \-n " LINES" ( \[\[ \-n " $ FOLLOW" \]\] && echo "-f" ) │ ;; │ backup) │ tail (\[\[−n" FOLLOW" \]\] && echo "-f" ) \-n "$LINES" /var/log/ai-platform/backup.log │ ;; │ platform) │ tail (\[\[−n" FOLLOW" \]\] && echo "-f" ) \-n "$LINES" /var/log/ai-platform/\*.log │ ;; │ \*) │ echo "Usage: ai-logs \[all|litellm|dify|n8n|postgres|redis|caddy|grafana|prometheus|ollama|backup|platform\] \[-f\] \[-n NUM\]" │ exit 1 │ ;; │ esac

\#\#\# ai-backup

File: $ BASE\_DIR/scripts/ai-backup.sh Symlink: /usr/local/bin/ai-backup │ ├── \#\!/bin/bash │ \# Wrapper for backup script │ exec /opt/ai-platform/scripts/backup.sh " $ @"

\#\#\# ai-update

File: $BASE\_DIR/scripts/ai-update.sh Symlink: /usr/local/bin/ai-update │ ├── \#\!/bin/bash │ set \-euo pipefail │  
│ echo "═══════════════════════════════════════" │ echo " AI Platform — Update" │ echo "═══════════════════════════════════════" │ ├── ── Pre-update backup ── │ echo "Step 1: Creating pre-update backup..." │ /opt/ai-platform/scripts/backup.sh full │ ├── ── Pull new images ── │ echo "Step 2: Pulling latest images..." │ cd /opt/ai-platform/compose │ docker compose pull │ ├── ── Rolling restart ── │ echo "Step 3: Restarting services..." │  
│ \# Core infra first (quick restart) │ docker compose up \-d postgres redis │ sleep 10 │  
│ \# Main services │ docker compose up \-d litellm │ sleep 10 │  
│ \# Everything else │ docker compose up \-d │  
│ echo "Step 4: Waiting for health checks..." │ sleep 30 │ ├── ── Update Ollama models ── │ echo "Step 5: Updating Ollama models..." │ source /opt/ai-platform/env/master.env │ for model in $(ollama list 2\>/dev/null | tail \-n \+2 | awk '{print $1}'); do │ echo " Updating ${model}..." │ ollama pull "${model}" 2\>/dev/null || true │ done │ ├── ── Verify ── │ echo "Step 6: Verifying..." │ /opt/ai-platform/scripts/ai-status.sh │ └── echo "" echo "═══ Update complete ═══" echo "Previous images can be cleaned with: docker image prune \-f"

\#\#\# ai-models

File: $ BASE\_DIR/scripts/ai-models.sh Symlink: /usr/local/bin/ai-models │ ├── \#\!/bin/bash │ \# Manage Ollama models and LiteLLM model list │  
│ ACTION=" $ {1:-list}" │ MODEL="${2:-}" │ source /opt/ai-platform/env/master.env 2\>/dev/null || true │ ├── case "$ACTION" in │ list) │ echo "── Local Ollama Models ──" │ ollama list 2\>/dev/null || echo "Ollama not running" │  
│ echo "" │ echo "── LiteLLM Registered Models ──" │ curl \-s "[http://localhost:4000/model/info](http://localhost:4000/model/info)"  
 │ \-H "Authorization: Bearer ${LITELLM\_MASTER\_KEY}" 2\>/dev/null |  
 │ jq \-r '.data\[\] | "(.model\_name)\\t(.litellm\_params.model)\\t(.model\_info.mode // "chat")"' 2\>/dev/null |  
 │ column \-t \-s $ '\\t' || echo "LiteLLM not available" │ ;; │  
│ pull) │ \[\[ \-z " $ MODEL" \]\] && { echo "Usage: ai-models pull \<model-name\>"; exit 1; } │ echo "Pulling ${MODEL} via Ollama..." │ ollama pull " $ MODEL" │ echo "✓ Model available. Add to LiteLLM via admin UI or config." │ ;; │  
│ remove) │ \[\[ \-z " $ MODEL" \]\] && { echo "Usage: ai-models remove \<model-name\>"; exit 1; } │ echo "Removing ${MODEL}..." │ ollama rm " $ MODEL" │ ;; │  
│ test) │ MODEL=" $ {MODEL:-mistral}" │ echo "Testing ${MODEL} via LiteLLM..." │ curl \-s "[http://localhost:4000/chat/completions](http://localhost:4000/chat/completions)"  
 │ \-H "Authorization: Bearer ${LITELLM\_MASTER\_KEY}"  
 │ \-H "Content-Type: application/json"  
 │ \-d "{ │ "model": "${MODEL}", │ "messages": \[{"role": "user", "content": "Say hello in exactly 5 words."}\], │ "max\_tokens": 50 │ }" | jq '.' 2\>/dev/null || echo "Request failed" │ ;; │  
│ \*) │ echo "Usage: ai-models \[list|pull|remove|test\] \[model-name\]" │ ;; │ esac

\---

\#\# 27\. n8n Workflow Templates

\#\#\# Auto-import System

Script 2, Phase 15: Import n8n workflows │ ├── n8n provides a CLI and API for importing workflows │ Workflows are stored as JSON and imported after n8n starts │ ├── ── Wait for n8n readiness ── │ import\_n8n\_workflows() { │ echo "Importing n8n workflow templates..." │  
│ local retries=30 │ until curl \-sf [http://localhost:5678/healthz](http://localhost:5678/healthz) \>/dev/null 2\>&1; do │ sleep 5 │ retries=$((retries \- 1)) │ \[\[ $retries \-eq 0 \]\] && { echo " ⚠ n8n not ready, skipping import"; return; } │ done │ ├── ── Workflow 1: Budget Monitor ── │ File: $CONFIG\_DIR/n8n/workflows/budget-monitor.json │  
│ { │ "name": "AI Platform — Budget Monitor", │ "nodes": \[ │ { │ "name": "Schedule Trigger", │ "type": "n8n-nodes-base.scheduleTrigger", │ "parameters": { │ "rule": { "interval": \[{"field": "minutes", "minutesInterval": 15}\] } │ }, │ "position": \[250, 300\] │ }, │ { │ "name": "Query Spend", │ "type": "n8n-nodes-base.httpRequest", │ "parameters": { │ "url": "[http://litellm:4000/global/spend/report](http://litellm:4000/global/spend/report)", │ "method": "GET", │ "headerParameters": { │ "parameters": \[{ │ "name": "Authorization", │ "value": "Bearer {{ $env.LITELLM\_MASTER\_KEY }}" │ }\] │ } │ }, │ "position": \[470, 300\] │ }, │ { │ "name": "Check Threshold", │ "type": "n8n-nodes-base.if", │ "parameters": { │ "conditions": { │ "number": \[{ │ "value1": "={{ $json.total\_spend }}", │ "operation": "largerEqual", │ "value2": "={{ $ env.MONTHLY\_BUDGET\_USD \* 0.8 }}" │ }\] │ } │ }, │ "position": \[690, 300\] │ }, │ { │ "name": "Log Alert", │ "type": "n8n-nodes-base.postgres", │ "parameters": { │ "operation": "executeQuery", │ "query": "INSERT INTO platform.audit\_log (event\_type, details) VALUES ('budget\_alert', '{{ JSON.stringify( $ json) }}')", │ "additionalFields": {} │ }, │ "position": \[910, 200\] │ }, │ { │ "name": "Budget OK", │ "type": "n8n-nodes-base.noOp", │ "position": \[910, 400\] │ } │ \], │ "connections": { │ "Schedule Trigger": { "main": \[\[{"node": "Query Spend", "type": "main", "index": 0}\]\] }, │ "Query Spend": { "main": \[\[{"node": "Check Threshold", "type": "main", "index": 0}\]\] }, │ "Check Threshold": { │ "main": \[ │ \[{"node": "Log Alert", "type": "main", "index": 0}\], │ \[{"node": "Budget OK", "type": "main", "index": 0}\] │ \] │ } │ }, │ "settings": { "executionOrder": "v1" }, │ "tags": \[{"name": "ai-platform"}, {"name": "auto-imported"}\] │ } │ ├── ── Workflow 2: Health Monitor ── │ File: $CONFIG\_DIR/n8n/workflows/health-monitor.json │  
│ { │ "name": "AI Platform — Health Monitor", │ "nodes": \[ │ { │ "name": "Schedule", │ "type": "n8n-nodes-base.scheduleTrigger", │ "parameters": { │ "rule": { "interval": \[{"field": "minutes", "minutesInterval": 5}\] } │ } │ }, │ { │ "name": "Check Services", │ "type": "n8n-nodes-base.httpRequest", │ "parameters": { │ "url": "[http://litellm:4000/health](http://litellm:4000/health)", │ "method": "GET", │ "options": { "timeout": 10000 } │ } │ }, │ { │ "name": "Check Ollama", │ "type": "n8n-nodes-base.httpRequest", │ "parameters": { │ "url": "http://host.docker.internal:11434/api/tags", │ "method": "GET", │ "options": { "timeout": 10000 } │ } │ }, │ { │ "name": "Evaluate Health", │ "type": "n8n-nodes-base.code", │ "parameters": { │ "jsCode": "const results \= $input.all();\\nconst unhealthy \= results.filter(r \=\> r.json.statusCode \>= 400);\\nif (unhealthy.length \> 0\) {\\n return \[{json: {status: 'unhealthy', failed: unhealthy.length, details: unhealthy}}\];\\n}\\nreturn \[{json: {status: 'healthy'}}\];" │ } │ }, │ { │ "name": "Alert If Unhealthy", │ "type": "n8n-nodes-base.if", │ "parameters": { │ "conditions": { │ "string": \[{ │ "value1": "={{ $json.status }}", │ "value2": "unhealthy" │ }\] │ } │ } │ } │ \] │ } │ ├── ── Workflow 3: Google Drive Sync ── │ File: $CONFIG\_DIR/n8n/workflows/gdrive-sync.json │  
│ Triggers rclone sync on schedule and logs results │ (Uses n8n Execute Command node to call gdrive-sync.sh) │ ├── ── Workflow 4: Daily Report ── │ File: $CONFIG\_DIR/n8n/workflows/daily-report.json │  
│ \- Runs at 8 AM daily │ \- Queries PostgreSQL for yesterday's usage stats │ \- Queries LiteLLM for model performance │ \- Formats summary │ \- (Optional) sends email/webhook │ ├── ── Import via n8n API ── │ for workflow\_file in ${CONFIG\_DIR}/n8n/workflows/\*.json; do │ local wf\_name= (jq−r′.name′" workflow\_file") │ echo " Importing: ${wf\_name}" │  
│ curl \-s \-X POST "[http://localhost:5678/api/v1/workflows](http://localhost:5678/api/v1/workflows)"  
 │ \-H "Content-Type: application/json"  
 │ \-u "${N8N\_BASIC\_AUTH\_USER}:${N8N\_BASIC\_AUTH\_PASSWORD}"  
 │ \-d @"$workflow\_file" \>/dev/null 2\>&1 &&  
 │ echo " ✓ Imported" ||  
 │ echo " ⚠ Import failed (can import manually via n8n UI)" │ done │ └── echo " ✓ n8n workflows imported"

\---

\#\# 28\. Troubleshooting & Recovery

\#\#\# Common Issues Decision Tree

ai-troubleshoot (generated convenience script) │ ├── \#\!/bin/bash │ echo "═══ AI Platform Troubleshooter ═══" │ echo "" │ ├── ── Check 1: Docker ── │ echo "1. Docker daemon..." │ if \! docker info &\>/dev/null; then │ echo " ✗ Docker not running\!" │ echo " FIX: sudo systemctl start docker" │ exit 1 │ fi │ echo " ✓ Docker OK" │ ├── ── Check 2: Containers ── │ echo "2. Container status..." │ STOPPED= $ (docker ps \-a \--filter "name=ai-" \--filter "status=exited" \--format '{{.Names}}') │ if \[\[ \-n " $ STOPPED" \]\]; then │ echo " ✗ Stopped containers:" │ echo " $ STOPPED" | sed 's/^/ \- /' │ echo " FIX: cd /opt/ai-platform/compose && docker compose up \-d" │ echo " LOGS: docker logs \<container-name\>" │ fi │  
│ UNHEALTHY= $ (docker ps \--filter "name=ai-" \--filter "health=unhealthy" \--format '{{.Names}}') │ if \[\[ \-n " $ UNHEALTHY" \]\]; then │ echo " ⚠ Unhealthy containers:" │ echo " $ UNHEALTHY" | sed 's/^/ \- /' │ for c in $UNHEALTHY; do │ echo " Last 5 log lines for $ c:" │ docker logs \--tail 5 " $ c" 2\>&1 | sed 's/^/ /' │ done │ fi │ ├── ── Check 3: Disk Space ── │ echo "3. Disk space..." │ local usage=$(df / | tail \-1 | awk '{print $5}' | tr \-d '%') │ if \[\[ $usage \-gt 90 \]\]; then │ echo " ✗ Disk ${usage}% full\!" │ echo " FIX options:" │ echo " docker system prune \-f \# Remove unused images/containers" │ echo " docker volume prune \-f \# Remove unused volumes" │ echo " journalctl \--vacuum-size=500M \# Trim system logs" │ echo " ollama rm \<unused-model\> \# Remove unused models" │ else │ echo " ✓ Disk ${usage}% used" │ fi │ ├── ── Check 4: Memory ── │ echo "4. Memory..." │ local mem\_avail=$(free \-m | awk '/Mem:/ {print $7}') │ if \[\[ $mem\_avail \-lt 1024 \]\]; then │ echo " ⚠ Low memory: ${mem\_avail}MB available" │ echo " Top memory consumers:" │ docker stats \--no-stream \--format '{{.Name}}\\t{{.MemUsage}}' $(docker ps \-q) |  
 │ sort \-k2 \-h \-r | head \-5 | sed 's/^/ /' │ echo " FIX: Consider disabling unused services in master.env" │ else │ echo " ✓ Memory OK: ${mem\_avail}MB available" │ fi │ ├── ── Check 5: PostgreSQL ── │ echo "5. PostgreSQL..." │ if docker exec ai-postgres pg\_isready \-U aiplatform &\>/dev/null; then │ echo " ✓ PostgreSQL accepting connections" │  
│ \# Check connection count │ local conns=$(docker exec ai-postgres psql \-U aiplatform \-t \-c  
 │ "SELECT count(\*) FROM pg\_stat\_activity;" 2\>/dev/null | tr \-d ' ') │ echo " Active connections: ${conns}/200" │  
│ if \[\[ ${conns:-0} \-gt 180 \]\]; then │ echo " ⚠ Near connection limit\!" │ echo " FIX: docker exec ai-postgres psql \-U aiplatform \-c \\" │ echo " "SELECT pg\_terminate\_backend(pid) FROM pg\_stat\_activity WHERE state \= 'idle' AND state\_change \< NOW() \- INTERVAL '10 minutes';"" │ fi │ else │ echo " ✗ PostgreSQL not responding\!" │ echo " LOGS: docker logs ai-postgres \--tail 20" │ echo " FIX: docker restart ai-postgres" │ fi │ ├── ── Check 6: Ollama ── │ echo "6. Ollama..." │ if curl \-sf [http://localhost:11434/api/tags](http://localhost:11434/api/tags) &\>/dev/null; then │ local model\_count= $ (curl \-s [http://localhost:11434/api/tags](http://localhost:11434/api/tags) | jq '.models | length') │ echo " ✓ Ollama running ( $ {model\_count} models)" │  
│ \# Test inference │ local start= $ (date \+%s%N) │ local test= $ (curl \-s \--max-time 30 [http://localhost:11434/api/generate](http://localhost:11434/api/generate)  
 │ \-d '{"model":"tinyllama","prompt":"hi","stream":false}' 2\>/dev/null | jq \-r '.response' 2\>/dev/null) │ local elapsed= ((( (date \+%s%N) \- start) / 1000000 )) │  
│ if \[\[ \-n " $ test" \]\]; then │ echo " ✓ Inference test passed ( $ {elapsed}ms)" │ else │ echo " ⚠ Inference test failed" │ echo " LOGS: journalctl \-u ollama \--no-pager \-n 20" │ fi │ else │ echo " ✗ Ollama not responding\!" │ echo " FIX: sudo systemctl restart ollama" │ fi │ ├── ── Check 7: LiteLLM ── │ echo "7. LiteLLM proxy..." │ local health= $ (curl \-sf [http://localhost:4000/health](http://localhost:4000/health) 2\>/dev/null) │ if \[\[ \-n " $ health" \]\]; then │ echo " ✓ LiteLLM healthy" │  
│ \# Check model availability │ local models=$(curl \-s [http://localhost:4000/model/info](http://localhost:4000/model/info)  
 │ \-H "Authorization: Bearer ${LITELLM\_MASTER\_KEY}" 2\>/dev/null |  
 │ jq '.data | length' 2\>/dev/null) │ echo " Models registered: ${models:-unknown}" │ else │ echo " ✗ LiteLLM not responding\!" │ echo " LOGS: docker logs ai-litellm \--tail 30" │ echo " Common fixes:" │ echo " \- Check API keys in /opt/ai-platform/env/litellm.env" │ echo " \- Verify config: docker exec ai-litellm cat /app/config.yaml" │ echo " \- Restart: docker restart ai-litellm" │ fi │ ├── ── Check 8: SSL/Caddy ── │ echo "8. SSL/Reverse proxy..." │ if docker exec ai-caddy caddy validate \--config /etc/caddy/Caddyfile &\>/dev/null; then │ echo " ✓ Caddyfile valid" │ else │ echo " ✗ Invalid Caddyfile\!" │ echo " FIX: Regenerate with script-2-deploy.sh \--regenerate" │ fi │  
│ if \[\[ \-n "${DOMAIN\_BASE:-}" \]\]; then │ local ssl\_test= (curl−sI"https:// {LITELLM\_DOMAIN:-localhost}" 2\>/dev/null | head \-1) │ if echo "$ssl\_test" | grep \-q "200|301|302"; then │ echo " ✓ SSL working" │ else │ echo " ⚠ SSL may not be configured" │ echo " Check DNS points to this server: dig \+short ${DOMAIN\_BASE}" │ fi │ fi │ ├── ── Check 9: Network ── │ echo "9. Network..." │ \# Check inter-container connectivity │ if docker exec ai-litellm curl \-sf [http://postgres:5432](http://postgres:5432) &\>/dev/null 2\>&1 ||  
 │ docker exec ai-litellm nc \-z postgres 5432 &\>/dev/null 2\>&1; then │ echo " ✓ Container networking OK" │ else │ echo " ⚠ Container network issue" │ echo " FIX: docker network inspect ai-platform\_ai-platform" │ echo " FIX: docker compose down && docker compose up \-d" │ fi │ ├── ── Summary ── │ echo "" │ echo "═══ Quick Fixes ═══" │ echo " Restart everything: cd /opt/ai-platform/compose && docker compose restart" │ echo " Full rebuild: cd /opt/ai-platform/compose && docker compose down && docker compose up \-d" │ echo " Regenerate configs: /opt/ai-platform/scripts/script-2-deploy.sh \--regenerate" │ echo " View all logs: ai-logs all \-f" │ echo " Full status: ai-status" │ └── echo " Restore from backup: /opt/ai-platform/scripts/restore.sh \<backup.tar.gz\> \--confirm"

\#\#\# Nuclear Recovery Option

File: $BASE\_DIR/scripts/factory-reset.sh │ ├── \#\!/bin/bash │ echo "╔═══════════════════════════════════════════╗" │ echo "║ ⚠ FACTORY RESET — AI PLATFORM ║" │ echo "║ This will DESTROY all data\! ║" │ echo "╚═══════════════════════════════════════════╝" │ echo "" │ echo "This will:" │ echo " 1\. Stop and remove all containers" │ echo " 2\. Remove all Docker volumes" │ echo " 3\. Delete all data in ${DATA\_DIR}" │ echo " 4\. Keep configurations and scripts" │ echo " 5\. Keep Ollama models (system-level)" │ echo "" │ read \-p "Type 'RESET' to confirm: " CONFIRM │ \[\[ " $ CONFIRM" \!= "RESET" \]\] && { echo "Aborted."; exit 0; } │  
│ read \-p "Create backup first? (y/N): " BACKUP │ \[\[ " $ BACKUP" \== "y" \]\] && /opt/ai-platform/scripts/backup.sh full \--upload │  
│ echo "Stopping services..." │ cd /opt/ai-platform/compose │ docker compose down \-v \--remove-orphans │  
│ echo "Removing data..." │ rm \-rf ${DATA\_DIR}/\* │  
│ echo "Recreating directory structure..." │ \# Re-run directory creation from Script 1 │ mkdir \-p ${DATA\_DIR}/{postgres,redis,dify/storage,n8n,open-webui,flowise,qdrant/{storage,snapshots},prometheus,grafana} │  
│ echo "Redeploying..." │ docker compose up \-d │  
│ echo "" │ echo "Factory reset complete. Services restarting with fresh data." │ echo "Run 'ai-status' in 60 seconds to verify."

\---

\*\*End of Part 7 (Sections 25–28).\*\*

\---

\#\# 29\. Complete File Manifest & Directory Tree

\#\#\# Full Directory Structure After Script 2 Completes

/opt/ai-platform/ ← BASE\_DIR │ ├── env/ ← ENV\_DIR — All environment files │ ├── master.env ← Master configuration (source of truth) │ ├── postgres.env ← PostgreSQL credentials │ ├── redis.env ← Redis credentials │ ├── litellm.env ← LiteLLM config \+ API keys │ ├── dify.env ← Dify configuration │ ├── n8n.env ← n8n configuration │ ├── open-webui.env ← Open WebUI configuration │ ├── flowise.env ← Flowise configuration │ ├── supertokens.env ← SuperTokens configuration │ ├── caddy.env ← Caddy/SSL configuration │ ├── monitoring.env ← Prometheus/Grafana config │ ├── qdrant.env ← Qdrant vector DB config │ └── .env.backup.{timestamp} ← Auto-backup before regeneration │ ├── config/ ← CONFIG\_DIR — Service configs │ ├── postgres/ │ │ └── init.sql ← Database initialization SQL │ ├── redis/ │ │ └── redis.conf ← Redis configuration │ ├── litellm/ │ │ ├── config.yaml ← LiteLLM model routing config │ │ └── custom\_callbacks/ ← Custom callback plugins │ │ └── cost\_tracker.py │ ├── caddy/ │ │ └── Caddyfile ← Reverse proxy configuration │ ├── prometheus/ │ │ ├── prometheus.yml ← Prometheus scrape config │ │ └── alert-rules.yml ← Alert rules │ ├── grafana/ │ │ ├── provisioning/ │ │ │ ├── dashboards/ │ │ │ │ └── dashboards.yml ← Dashboard provisioning config │ │ │ └── datasources/ │ │ │ └── datasources.yml ← Datasource provisioning config │ │ └── dashboards/ │ │ ├── ai-platform-overview.json ← Main dashboard │ │ ├── llm-performance.json ← LLM metrics dashboard │ │ ├── cost-tracking.json ← Cost/budget dashboard │ │ └── infrastructure.json ← System resources dashboard │ ├── dify/ │ │ └── .env ← Dify-specific internal env │ ├── n8n/ │ │ └── workflows/ │ │ ├── budget-monitor.json ← Auto-imported workflow │ │ ├── health-monitor.json ← Auto-imported workflow │ │ ├── gdrive-sync.json ← Auto-imported workflow │ │ └── daily-report.json ← Auto-imported workflow │ ├── supertokens/ │ │ └── config.yaml ← SuperTokens configuration │ └── qdrant/ │ └── config.yaml ← Qdrant configuration │ ├── compose/ ← COMPOSE\_DIR │ ├── docker-compose.yml ← Main compose file (generated) │ └── docker-compose.override.yml ← User overrides (preserved on regenerate) │ ├── data/ ← DATA\_DIR — Persistent volumes │ ├── postgres/ ← PostgreSQL data │ ├── redis/ ← Redis data \+ AOF │ ├── dify/ │ │ └── storage/ ← Dify file uploads & assets │ ├── n8n/ ← n8n workflow data │ ├── open-webui/ ← Open WebUI data │ ├── flowise/ ← Flowise data │ ├── qdrant/ │ │ ├── storage/ ← Qdrant vector storage │ │ └── snapshots/ ← Qdrant snapshots │ ├── caddy/ │ │ ├── data/ ← SSL certificates │ │ └── config/ ← Caddy auto-config │ ├── prometheus/ ← Prometheus TSDB │ ├── grafana/ ← Grafana data (dashboards, prefs) │ ├── supertokens/ ← SuperTokens data │ └── ollama-shared/ ← Shared Ollama socket/config │ ├── backups/ ← BACKUP\_DIR │ ├── ai-platform-backup-{date}.tar.gz ← Compressed backups │ └── ai-platform-backup-{date}.tar.gz.sha256 ← Checksums │ ├── scripts/ ← Operational scripts │ ├── script-2-deploy.sh ← This script (preserved for re-run) │ ├── ai-status.sh ← Platform status checker │ ├── ai-logs.sh ← Log viewer │ ├── ai-backup.sh ← Backup wrapper │ ├── ai-update.sh ← Update/upgrade tool │ ├── ai-models.sh ← Model management │ ├── ai-troubleshoot.sh ← Diagnostic tool │ ├── backup.sh ← Full backup script │ ├── restore.sh ← Full restore script │ ├── factory-reset.sh ← Nuclear reset option │ ├── gdrive-sync.sh ← Google Drive sync helper │ └── validate-env.sh ← Environment validator │ ├── logs/ ← Platform-level logs │ └── (symlink → /var/log/ai-platform/) │ └── docs/ ← Auto-generated documentation ├── README.md ← Quick-start guide ├── endpoints.md ← All URLs and access info ├── passwords.md ← Credential reference (encrypted) └── architecture.md ← Architecture overview

/var/log/ai-platform/ ← System log directory ├── deploy.log ← Script 2 deployment log ├── backup.log ← Backup operation logs ├── backup-cron.log ← Cron backup logs ├── health.log ← Health check logs └── update.log ← Update operation logs

/usr/local/bin/ ← System-wide convenience symlinks ├── ai-status → /opt/ai-platform/scripts/ai-status.sh ├── ai-logs → /opt/ai-platform/scripts/ai-logs.sh ├── ai-backup → /opt/ai-platform/scripts/ai-backup.sh ├── ai-update → /opt/ai-platform/scripts/ai-update.sh ├── ai-models → /opt/ai-platform/scripts/ai-models.sh └── ai-troubleshoot → /opt/ai-platform/scripts/ai-troubleshoot.sh

/etc/systemd/system/ └── ollama.service ← Ollama systemd service (from Script 1\)

Crontab entries: ├── 0 2 \* \* \* /opt/ai-platform/scripts/backup.sh full \--upload ├── \*/5 \* \* \* \* /opt/ai-platform/scripts/health-check.sh └── 0 4 \* \* 0 docker system prune \-f \>\> /var/log/ai-platform/cleanup.log 2\>&1

\---

\#\# 30\. Environment Variable Complete Reference

\#\#\# master.env — All Variables

Variable Name │ Source │ Example Value │ Description ─────────────────────────────────┼──────────┼──────────────────────────────┼──────────────────────────────

# **── Identity ── │ │ │**

PLATFORM\_NAME │ Script 2 │ "AI Platform" │ Display name DEPLOYMENT\_ID │ Script 2 │ "ai-plat-a1b2c3" │ Unique deployment identifier SCRIPT\_2\_VERSION │ Script 2 │ "2.0.0" │ Script version DEPLOYED\_AT │ Script 2 │ "2025-01-15T10:30:00Z" │ Deployment timestamp │ │ │

# **── System Detection ── │ │ │**

TOTAL\_RAM\_GB │ Script 1 │ 64 │ Detected total RAM CPU\_CORES │ Script 1 │ 16 │ Detected CPU cores GPU\_AVAILABLE │ Script 1 │ true │ GPU detected flag GPU\_TYPE │ Script 1 │ "nvidia" │ GPU vendor GPU\_VRAM\_MB │ Script 1 │ 24576 │ Total GPU VRAM CUDA\_VERSION │ Script 1 │ "12.2" │ Detected CUDA version DISK\_TOTAL\_GB │ Script 1 │ 500 │ Total disk space DISK\_FREE\_GB │ Script 1 │ 420 │ Free disk at deploy time │ │ │

# **── Network & DNS ── │ │ │**

DOMAIN\_BASE │ User │ "myai.example.com" │ Base domain USE\_SUBDOMAINS │ Script 2 │ true │ Subdomain mode flag LITELLM\_DOMAIN │ Script 2 │ "llm.myai.example.com" │ LiteLLM URL DIFY\_DOMAIN │ Script 2 │ "dify.myai.example.com" │ Dify URL N8N\_DOMAIN │ Script 2 │ "n8n.myai.example.com" │ n8n URL OPEN\_WEBUI\_DOMAIN │ Script 2 │ "chat.myai.example.com" │ Open WebUI URL FLOWISE\_DOMAIN │ Script 2 │ "flow.myai.example.com" │ Flowise URL GRAFANA\_DOMAIN │ Script 2 │ "grafana.myai.example.com" │ Grafana URL SUPERTOKENS\_DOMAIN │ Script 2 │ "auth.myai.example.com" │ SuperTokens URL SSL\_MODE │ Script 2 │ "auto" │ auto|manual|selfsigned SSL\_EMAIL │ User │ "admin@example.com" │ Let's Encrypt email SERVER\_IP │ Script 1 │ "203.0.113.50" │ Public IP address │ │ │

# **── Service Toggles ── │ │ │**

ENABLED\_SERVICES │ Script 2 │ "postgres,redis,litellm..." │ Comma-separated list ENABLE\_DIFY │ Script 2 │ true │ Dify enabled ENABLE\_N8N │ Script 2 │ true │ n8n enabled ENABLE\_OPEN\_WEBUI │ Script 2 │ true │ Open WebUI enabled ENABLE\_FLOWISE │ Script 2 │ true │ Flowise enabled ENABLE\_MONITORING │ Script 2 │ true │ Prometheus+Grafana ENABLE\_SUPERTOKENS │ Script 2 │ true │ Auth service VECTOR\_DB\_CHOICE │ Script 2 │ "qdrant" │ qdrant|weaviate|milvus │ │ │

# **── PostgreSQL ── │ │ │**

POSTGRES\_USER │ Script 2 │ "aiplatform" │ DB superuser POSTGRES\_PASSWORD │ Generate │ "xK9m2...(32 chars)" │ DB password POSTGRES\_HOST │ Script 2 │ "postgres" │ Docker hostname POSTGRES\_PORT │ Script 2 │ 5432 │ Internal port POSTGRES\_EXTERNAL\_PORT │ Script 2 │ 5432 │ External port (or "none") │ │ │

# **── Redis ── │ │ │**

REDIS\_PASSWORD │ Generate │ "rP8k4...(32 chars)" │ Redis password REDIS\_HOST │ Script 2 │ "redis" │ Docker hostname REDIS\_PORT │ Script 2 │ 6379 │ Internal port REDIS\_MAXMEMORY │ Script 2 │ "2gb" │ Memory limit │ │ │

# **── LiteLLM ── │ │ │**

LITELLM\_MASTER\_KEY │ Generate │ "sk-litellm-...(48 chars)" │ Admin API key LITELLM\_SALT\_KEY │ Generate │ "salt-...(32 chars)" │ Encryption salt LITELLM\_PORT │ Script 2 │ 4000 │ Proxy port LITELLM\_UI\_USERNAME │ Script 2 │ "admin" │ Web UI username LITELLM\_UI\_PASSWORD │ Generate │ "uP3x...(24 chars)" │ Web UI password LITELLM\_LOG\_LEVEL │ Script 2 │ "INFO" │ Log verbosity │ │ │

# **── API Keys (Cloud LLMs) ── │ │ │**

OPENAI\_API\_KEY │ User │ "sk-..." │ OpenAI key ANTHROPIC\_API\_KEY │ User │ "sk-ant-..." │ Anthropic key GOOGLE\_API\_KEY │ User │ "AIza..." │ Google AI key GROQ\_API\_KEY │ User │ "gsk\_..." │ Groq key MISTRAL\_API\_KEY │ User │ "..." │ Mistral key OPENROUTER\_API\_KEY │ User │ "sk-or-..." │ OpenRouter key COHERE\_API\_KEY │ User │ "..." │ Cohere key │ │ │

# **── Dify ── │ │ │**

DIFY\_SECRET\_KEY │ Generate │ "dify-...(48 chars)" │ App secret DIFY\_INIT\_PASSWORD │ Generate │ "dP5j...(16 chars)" │ Initial admin password DIFY\_API\_PORT │ Script 2 │ 5001 │ API port DIFY\_WEB\_PORT │ Script 2 │ 3001 │ Web UI port DIFY\_SANDBOX\_PORT │ Script 2 │ 8194 │ Sandbox port DIFY\_WEAVIATE\_PORT │ Script 2 │ 8080 │ Vector DB port (if used) │ │ │

# **── n8n ── │ │ │**

N8N\_ENCRYPTION\_KEY │ Generate │ "n8n-...(48 chars)" │ Workflow encryption N8N\_BASIC\_AUTH\_USER │ Script 2 │ "admin" │ Basic auth user N8N\_BASIC\_AUTH\_PASSWORD │ Generate │ "nP4z...(24 chars)" │ Basic auth password N8N\_PORT │ Script 2 │ 5678 │ Web UI port N8N\_WEBHOOK\_URL │ Script 2 │ "[https://n8n.example.com](https://n8n.example.com)" │ Webhook base URL │ │ │

# **── Open WebUI ── │ │ │**

OPEN\_WEBUI\_PORT │ Script 2 │ 3000 │ Web UI port OPEN\_WEBUI\_SECRET\_KEY │ Generate │ "ow-...(32 chars)" │ Session secret WEBUI\_AUTH │ Script 2 │ true │ Enable auth │ │ │

# **── Flowise ── │ │ │**

FLOWISE\_PORT │ Script 2 │ 3002 │ Web UI port FLOWISE\_USERNAME │ Script 2 │ "admin" │ Login username FLOWISE\_PASSWORD │ Generate │ "fP7w...(24 chars)" │ Login password FLOWISE\_SECRETKEY\_OVERWRITE │ Generate │ "fl-...(32 chars)" │ API secret │ │ │

# **── Qdrant ── │ │ │**

QDRANT\_PORT │ Script 2 │ 6333 │ HTTP API port QDRANT\_GRPC\_PORT │ Script 2 │ 6334 │ gRPC port QDRANT\_API\_KEY │ Generate │ "qd-...(32 chars)" │ API key │ │ │

# **── SuperTokens ── │ │ │**

SUPERTOKENS\_API\_KEY │ Generate │ "st-...(48 chars)" │ Core API key SUPERTOKENS\_PORT │ Script 2 │ 3567 │ Core port │ │ │

# **── Monitoring ── │ │ │**

GRAFANA\_ADMIN\_USER │ Script 2 │ "admin" │ Grafana admin GRAFANA\_ADMIN\_PASSWORD │ Generate │ "gP2m...(24 chars)" │ Grafana password GRAFANA\_PORT │ Script 2 │ 3003 │ Grafana web port PROMETHEUS\_PORT │ Script 2 │ 9090 │ Prometheus port PROMETHEUS\_RETENTION │ Script 2 │ "30d" │ Data retention │ │ │

# **── Ollama ── │ │ │**

OLLAMA\_HOST │ Script 2 │ "[http://host.docker.internal:11434](http://host.docker.internal:11434)" │ Ollama URL for containers OLLAMA\_BASE\_URL │ Script 2 │ "[http://host.docker.internal:11434](http://host.docker.internal:11434)" │ Alternative form OLLAMA\_MODELS\_DIR │ Script 1 │ "/usr/share/ollama/.ollama/models" │ Model storage path OLLAMA\_DEFAULT\_MODEL │ Script 2 │ "mistral" │ Default chat model OLLAMA\_EMBEDDING\_MODEL │ Script 2 │ "nomic-embed-text" │ Default embedding model │ │ │

# **── Budget ── │ │ │**

MONTHLY\_BUDGET\_USD │ User │ 50 │ Monthly budget cap BUDGET\_ALERT\_THRESHOLD │ Script 2 │ 0.8 │ Alert at 80% BUDGET\_HARD\_LIMIT │ Script 2 │ true │ Enforce limit? │ │ │

# **── Backup ── │ │ │**

BACKUP\_BASE\_DIR │ Script 2 │ "/opt/ai-platform/backups" │ Backup storage BACKUP\_RETENTION\_DAYS │ Script 2 │ 7 │ Local retention BACKUP\_SCHEDULE │ Script 2 │ "0 2 \* \* \*" │ Cron schedule ENABLE\_GDRIVE\_BACKUP │ User │ false │ GDrive sync enabled GDRIVE\_FOLDER\_ID │ User │ "" │ GDrive target folder │ │ │

# **── Resource Limits ── │ │ │**

POSTGRES\_MEMORY\_LIMIT │ Script 2 │ "4g" │ PG container limit REDIS\_MEMORY\_LIMIT │ Script 2 │ "2g" │ Redis container limit LITELLM\_MEMORY\_LIMIT │ Script 2 │ "2g" │ LiteLLM container limit DIFY\_API\_MEMORY\_LIMIT │ Script 2 │ "4g" │ Dify API limit N8N\_MEMORY\_LIMIT │ Script 2 │ "2g" │ n8n container limit │ │ │

# **── Paths ── │ │ │**

BASE\_DIR │ Script 2 │ "/opt/ai-platform" │ Root directory CONFIG\_DIR │ Script 2 │ "/opt/ai-platform/config" │ Configuration dir DATA\_DIR │ Script 2 │ "/opt/ai-platform/data" │ Persistent data COMPOSE\_DIR │ Script 2 │ "/opt/ai-platform/compose" │ Compose files ENV\_DIR │ Script 2 │ "/opt/ai-platform/env" │ Environment files SCRIPTS\_DIR │ Script 2 │ "/opt/ai-platform/scripts" │ Script directory LOG\_DIR │ Script 2 │ "/var/log/ai-platform" │ Log directory TIMEZONE │ Script 2 │ "UTC" │ System timezone

\---

\#\# 31\. IP Address & Port Map

\#\#\# Internal Network (Docker: 172.28.0.0/16)

Container Name │ Docker IP │ Internal Port │ Host Port │ Protocol │ URL Path ───────────────────┼────────────────┼───────────────┼───────────┼──────────┼────────── ai-postgres │ 172.28.0.10 │ 5432 │ 5432\* │ TCP │ — ai-redis │ 172.28.0.11 │ 6379 │ —\*\* │ TCP │ — ai-litellm │ 172.28.0.20 │ 4000 │ 4000 │ HTTP │ / ai-dify-api │ 172.28.0.30 │ 5001 │ 5001 │ HTTP │ / ai-dify-worker │ 172.28.0.31 │ — │ — │ — │ — ai-dify-web │ 172.28.0.32 │ 3001 │ 3001 │ HTTP │ / ai-dify-sandbox │ 172.28.0.33 │ 8194 │ — │ HTTP │ — ai-n8n │ 172.28.0.40 │ 5678 │ 5678 │ HTTP │ / ai-open-webui │ 172.28.0.50 │ 3000 (→8080) │ 3000 │ HTTP │ / ai-flowise │ 172.28.0.60 │ 3002 (→3000) │ 3002 │ HTTP │ / ai-qdrant │ 172.28.0.70 │ 6333/6334 │ 6333 │ HTTP/gRPC│ / ai-supertokens │ 172.28.0.80 │ 3567 │ 3567 │ HTTP │ / ai-caddy │ 172.28.0.2 │ 80/443 │ 80/443 │ HTTP/S │ / ai-prometheus │ 172.28.1.10 │ 9090 │ 9090\* │ HTTP │ / ai-grafana │ 172.28.1.20 │ 3000 │ 3003 │ HTTP │ / ───────────────────┴────────────────┴───────────────┴───────────┴──────────┴──────────

* \= Only exposed to localhost (127.0.0.1:port:port) unless explicitly opened \*\* \= Redis never exposed to host network

Host-level service: Ollama │ 0.0.0.0 │ 11434 │ 11434 │ HTTP │ /api/

\#\#\# Caddy Reverse Proxy Routes

External URL │ Internal Target │ Auth ──────────────────────────────────────┼───────────────────────────┼────── [https://llm.{domain}/](https://llm.{domain}/) │ [http://ai-litellm:4000](http://ai-litellm:4000) │ API Key [https://dify.{domain}/](https://dify.{domain}/) │ [http://ai-dify-web:3001](http://ai-dify-web:3001) │ Built-in [https://dify.{domain}/v1/](https://dify.{domain}/v1/)\* │ [http://ai-dify-api:5001](http://ai-dify-api:5001) │ API Key [https://n8n.{domain}/](https://n8n.{domain}/) │ [http://ai-n8n:5678](http://ai-n8n:5678) │ Basic Auth [https://chat.{domain}/](https://chat.{domain}/) │ [http://ai-open-webui:8080](http://ai-open-webui:8080) │ Built-in [https://flow.{domain}/](https://flow.{domain}/) │ [http://ai-flowise:3000](http://ai-flowise:3000) │ Basic Auth [https://grafana.{domain}/](https://grafana.{domain}/) │ [http://ai-grafana:3000](http://ai-grafana:3000) │ Built-in [https://auth.{domain}/](https://auth.{domain}/) │ [http://ai-supertokens:3567│](http://ai-supertokens:3567│) API Key

Without domain (IP-only mode): http://{IP}:80/litellm/\* │ [http://ai-litellm:4000](http://ai-litellm:4000) │ API Key http://{IP}:80/dify/\* │ [http://ai-dify-web:3001](http://ai-dify-web:3001) │ Built-in http://{IP}:80/n8n/\* │ [http://ai-n8n:5678](http://ai-n8n:5678) │ Basic Auth http://{IP}:80/chat/\* │ [http://ai-open-webui:8080](http://ai-open-webui:8080) │ Built-in http://{IP}:80/flowise/\* │ [http://ai-flowise:3000](http://ai-flowise:3000) │ Basic Auth http://{IP}:80/grafana/\* │ [http://ai-grafana:3000](http://ai-grafana:3000) │ Built-in

\#\#\# Firewall Rules (UFW)

Rule │ Purpose │ Set By ──────────────────────────────┼────────────────────────────┼──────── 22/tcp ALLOW │ SSH access │ Script 1 80/tcp ALLOW │ HTTP (Caddy redirect) │ Script 2 443/tcp ALLOW │ HTTPS (Caddy SSL) │ Script 2 11434/tcp ALLOW from 172.28.0.0/16 │ Ollama (Docker only) │ Script 2 5432/tcp DENY from any │ PostgreSQL (no external) │ Script 2 6379/tcp DENY from any │ Redis (no external) │ Script 2

\---

\#\# 32\. Post-Deployment Checklist

\#\#\# Automated Verification (Script 2, Phase 16\)

run\_post\_deployment\_checks() │ ├── CHECK 1: All containers running │ Expected: All enabled services show "running" │ Command: docker ps \--filter "name=ai-" \--format '{{.Names}} {{.Status}}' │ Pass: All containers show "Up" │  
├── CHECK 2: Health endpoints responding │ ┌─────────────┬────────────────────────────────────────┬──────────┐ │ │ Service │ Health URL │ Expected │ │ ├─────────────┼────────────────────────────────────────┼──────────┤ │ │ PostgreSQL │ pg\_isready \-U aiplatform │ exit 0 │ │ │ Redis │ redis-cli \-a $PASS ping │ PONG │ │ │ LiteLLM │ [http://localhost:4000/health](http://localhost:4000/health) │ HTTP 200 │ │ │ Dify API │ [http://localhost:5001/health](http://localhost:5001/health) │ HTTP 200 │ │ │ Dify Web │ [http://localhost:3001/](http://localhost:3001/) │ HTTP 200 │ │ │ n8n │ [http://localhost:5678/healthz](http://localhost:5678/healthz) │ HTTP 200 │ │ │ Open WebUI │ [http://localhost:3000/](http://localhost:3000/) │ HTTP 200 │ │ │ Flowise │ [http://localhost:3002/](http://localhost:3002/) │ HTTP 200 │ │ │ Qdrant │ [http://localhost:6333/healthz](http://localhost:6333/healthz) │ HTTP 200 │ │ │ Caddy │ [http://localhost:80/](http://localhost:80/) │ HTTP 2xx │ │ │ Prometheus │ [http://localhost:9090/-/healthy](http://localhost:9090/-/healthy) │ HTTP 200 │ │ │ Grafana │ [http://localhost:3003/api/health](http://localhost:3003/api/health) │ HTTP 200 │ │ │ SuperTokens │ [http://localhost:3567/hello](http://localhost:3567/hello) │ HTTP 200 │ │ │ Ollama │ [http://localhost:11434/api/tags](http://localhost:11434/api/tags) │ HTTP 200 │ │ └─────────────┴────────────────────────────────────────┴──────────┘ │ ├── CHECK 3: Database connectivity │ \- Each service database exists │ \- Extensions loaded (uuid-ossp, vector, etc.) │ \- Platform schema created │  
├── CHECK 4: LiteLLM model access │ \- At least 1 model responding │ \- Test: simple chat completion │ \- Response received within timeout │  
├── CHECK 5: Ollama models loaded │ \- At least default model present │ \- Test inference works │  
├── CHECK 6: Inter-service communication │ \- Dify → LiteLLM connectivity │ \- n8n → PostgreSQL connectivity  
│ \- Open WebUI → Ollama connectivity │ \- All services → Redis connectivity │  
├── CHECK 7: SSL/TLS (if configured) │ \- Certificates obtained or self-signed present │ \- HTTPS responding on port 443 │ \- HTTP → HTTPS redirect working │  
├── CHECK 8: Disk space adequate │ \- At least 20% free space remaining │ \- All data directories writable │  
├── CHECK 9: Backup system ready │ \- Backup script executable │ \- Crontab entry present │ \- Backup directory writable │ \- Test backup of configs succeeds │  
├── CHECK 10: Monitoring operational │ \- Prometheus scraping targets │ \- Grafana datasource connected │ \- Dashboards loaded │ └── ── Output Summary ──

═══════════════════════════════════════════════════════════════  
    AI PLATFORM — DEPLOYMENT COMPLETE  
═══════════════════════════════════════════════════════════════

Status:     ✓ ALL CHECKS PASSED (10/10)  
Deployed:   2025-01-15 10:45:32 UTC  
Duration:   12 minutes 34 seconds

── Service URLs ──

LiteLLM Proxy:    https://llm.myai.example.com  
                  API Key: sk-litellm-xxxx...xxxx

Dify Platform:    https://dify.myai.example.com  
                  Initial password: dP5j...

n8n Workflows:    https://n8n.myai.example.com  
                  Login: admin / nP4z...

Open WebUI:       https://chat.myai.example.com  
                  (Create account on first visit)

Flowise:          https://flow.myai.example.com  
                  Login: admin / fP7w...

Grafana:          https://grafana.myai.example.com  
                  Login: admin / gP2m...

── Local Models (Ollama) ──

mistral:latest         4.1 GB    ✓ Ready  
nomic-embed-text:latest 274 MB   ✓ Ready

── Quick Commands ──

ai-status          Check platform status  
ai-logs \[service\]  View logs (-f to follow)  
ai-models list     List available models  
ai-models pull X   Download new model  
ai-backup full     Create full backup  
ai-update          Update all services  
ai-troubleshoot    Run diagnostics

── Files ──

Master config:   /opt/ai-platform/env/master.env  
Docker compose:  /opt/ai-platform/compose/docker-compose.yml  
Service configs: /opt/ai-platform/config/  
Backups:         /opt/ai-platform/backups/  
Logs:            /var/log/ai-platform/

── Credentials ──

All passwords saved to: /opt/ai-platform/env/master.env  
(File permissions: 600 — owner-read only)

⚠ IMPORTANT: Save your credentials securely\!

═══════════════════════════════════════════════════════════════

Full credential list:  
grep \-E '(PASSWORD|KEY|SECRET)' /opt/ai-platform/env/master.env

═══════════════════════════════════════════════════════════════

\---

\#\# 33\. Architecture Diagram

\#\#\# System Architecture (ASCII)

┌─────────────────────────────────────────────────────────────────────────────┐ │ INTERNET │ │ │ │ Users / API Clients / Webhooks │ │ │ │ │ │ └─────────┼─────────┼──────────┼──────────────────────────────────────────────┘ │ │ │ ▼ ▼ ▼ ┌─────────────────────────────────────────────────────────────────────────────┐ │ CADDY REVERSE PROXY │ │ (Auto-SSL / Let's Encrypt) │ │ Port 80 ──→ 443 redirect │ │ Port 443 ──→ Route by subdomain: │ │ │ │ llm.domain → LiteLLM:4000 chat.domain → Open-WebUI:8080 │ │ dify.domain → Dify-Web:3001 flow.domain → Flowise:3000 │ │ n8n.domain → n8n:5678 grafana.domain → Grafana:3000 │ │ auth.domain → SuperTokens:3567 │ └───────────────────────┬─────────────────────────────────────────────────────┘ │ ┌─────────────┼─────────────────────────────────┐ │ Docker Network: ai-platform (172.28.0.0/16)│ │ │ │ │ ┌────────┴────────┐ │ │ │ │ │ │ ▼ ▼ │ │ ┌──────────┐ ┌──────────────┐ │ │ │ LiteLLM │ │ Dify │ │ │ │ Proxy │ │ Platform │ │ │ │ :4000 │ │ API :5001 │ │ │ │ │ │ Web :3001 │ │ │ │ ┌──────┐ │ │ Worker │ │ │ │ │Router│ │ │ Sandbox:8194 │ │ │ │ │ │ │ └──────┬───────┘ │ │ │ │ Cost │ │ │ │ │ │ │Track │ │ │ (uses LiteLLM │ │ │ │ │ │ │ as LLM backend) │ │ │ │Cache │ │ │ │ │ │ └──┬───┘ │ ┌─────┴──────┐ │ │ └────┼─────┘ │ │ │ │ │ │ ┌───────┴──────┐ │ │ │ │ │ │ │ │ ▼ ▼ ▼ ▼ │ │ ┌────────┐ ┌────────┐ ┌──────────┐ │ │ │ Redis │ │ n8n │ │ Open │ │ │ │ :6379 │ │ :5678 │ │ WebUI │ │ │ │ │ │ │ │ :8080 │ │ │ │ Cache │ │Workflows│ │ │ │ │ │ Queue │ │Automaton│ │ Chat UI │ │ │ │ Session│ │ │ │ │ │ │ └────────┘ └───┬────┘ └────┬─────┘ │ │ │ │ │ │ ┌──────────┴──────┐ │ │ │ ▼ ▼ │ │ │ ┌──────────┐ ┌──────────┐ │ │ │ │PostgreSQL│ │ Flowise │ │ │ │ │ :5432 │ │ :3000 │ │ │ │ │ │ │ │ │ │ │ │ pgvector │ │ Flow │ │ │ │ │ │ │ Builder │ │ │ │ │ DBs: │ └────┬─────┘ │ │ │ │ litellm │ │ │ │ │ │ dify │ │ │ │ │ │ n8n │ ▼ ▼ │ │ │ platform │ ┌──────────────────────┐ │ │ │ grafana │ │ Qdrant │ │ │ │ super- │ │ Vector DB │ │ │ │ tokens │ │ :6333 HTTP │ │ │ └──────────┘ │ :6334 gRPC │ │ │ │ Embeddings Store │ │ │ └──────────────────────┘ │ │ │ │ ┌─────────────────────────────────────┐ │ │ │ Monitoring Network │ │ │ │ │ │ │ │ ┌────────────┐ ┌──────────────┐ │ │ │ │ │ Prometheus │ │ Grafana │ │ │ │ │ │ :9090 │ │ :3000 │ │ │ │ │ │ │ │ │ │ │ │ │ │ Scrapes: │ │ Dashboards: │ │ │ │ │ │ \- LiteLLM │──│ \- Overview │ │ │ │ │ │ \- Caddy │ │ \- LLM Perf │ │ │ │ │ │ \- Postgres │ │ \- Cost Track │ │ │ │ │ │ \- Redis │ │ \- Infra │ │ │ │ │ │ \- Node │ │ │ │ │ │ │ └────────────┘ └──────────────┘ │ │ │ └─────────────────────────────────────┘ │ │ │ │ ┌──────────────┐ │ │ │ SuperTokens │ │ │ │ Auth :3567 │ │ │ └──────────────┘ │ │ │ └───────────────────────┬───────────────────────┘ │ ┌─────────────┼──────────────┐ │ HOST SYSTEM │ │ │ │ │ ┌────────┴─────────┐ │ │ │ Ollama │ │ │ │ :11434 │ │ │ │ │ │ │ │ Models: │ │ │ │ \- mistral │ │ │ │ \- nomic-embed │ │ │ │ \- llama3.1 │ │ │ │ \- codellama │ │ │ │ \- (user added) │ │ │ │ │ │ │ │ ┌────────────┐ │ │ │ │ │ GPU/CUDA │ │ │ │ │ │ or CPU │ │ │ │ │ └────────────┘ │ │ │ └─────────────────┘ │ │ │ └───────────────────────────┘

    ┌──────────────────────────────────────┐  
     │         CLOUD LLM PROVIDERS          │  
     │  (via LiteLLM Router)                │  
     │                                      │  
     │  ┌──────────┐  ┌──────────────────┐ │  
     │  │ OpenAI   │  │ Anthropic        │ │  
     │  │ GPT-4o   │  │ Claude 3.5       │ │  
     │  └──────────┘  └──────────────────┘ │  
     │  ┌──────────┐  ┌──────────────────┐ │  
     │  │ Google   │  │ Groq             │ │  
     │  │ Gemini   │  │ (fast inference) │ │  
     │  └──────────┘  └──────────────────┘ │  
     │  ┌──────────┐  ┌──────────────────┐ │  
     │  │ Mistral  │  │ OpenRouter       │ │  
     │  │          │  │ (100+ models)    │ │  
     │  └──────────┘  └──────────────────┘ │  
     └──────────────────────────────────────┘

\#\#\# Data Flow: Chat Request

User sends message │ ▼ ┌─────────┐ │ Caddy │ ── SSL termination └────┬─────┘ │ ▼ ┌─────────────┐ │ LiteLLM │ ── Authentication (API key check) │ Proxy │ ── Check Redis cache │ │ ── Budget check │ │ ── Route decision: │ │ │ Cache HIT? ├──YES──→ Return cached response (0 cost) │ │ │ Cache MISS │ │ Route: │ │ │ │ Simple? ──├──YES──→ Ollama (local, free) │ │ │ │ Complex? ──├──YES──→ Cloud Provider (paid) │ │ │ │ Budget │ │ │ exceeded?──├──YES──→ Ollama fallback (free) │ │ │ └─────────────┘ │ │ │ ▼ ▼ ┌─────────────┐ ┌──────────────┐ │ Log to │ │ Response │ │ PostgreSQL │ │ returned │ │ \+ Redis │ │ to user │ │ cache │ └──────────────┘ └─────────────┘

\#\#\# Data Flow: RAG (Retrieval-Augmented Generation)

User uploads document │ ▼ ┌──────────┐ │ Dify / │ ── Document received │ Flowise │ └────┬─────┘ │ ▼ ┌──────────────┐ │ Text │ ── Extract text from PDF/DOC/etc. │ Extraction │ ── Chunk into segments (\~512 tokens) └──────┬───────┘ │ ▼ ┌──────────────┐ ┌───────────┐ │ LiteLLM │ ── Request ──→ │ Ollama │ │ (embedding) │ embedding │ nomic- │ │ │ ◀── Vector ── │ embed │ └──────┬───────┘ \[768 dims\] └───────────┘ │ ▼ ┌──────────────┐ │ Qdrant │ ── Store vector \+ metadata │ Vector DB │ ── Collection: "user\_docs" └──────────────┘

     ⋮ (later, user asks question)  
      

┌──────────────┐ │ User Query │ └──────┬───────┘ │ ▼ ┌──────────────┐ │ Embed query │ ── Same embedding model └──────┬───────┘ │ ▼ ┌──────────────┐ │ Qdrant │ ── Similarity search │ Search │ ── Return top-K chunks └──────┬───────┘ │ ▼ ┌──────────────────────────────┐ │ Construct prompt: │ │ │ │ System: You are helpful... │ │ Context: {retrieved chunks} │ │ User: {original question} │ └──────────────┬───────────────┘ │ ▼ ┌──────────────┐ │ LiteLLM │ ── Route to best model │ → LLM │ ── Generate answer using context └──────┬───────┘ │ ▼ ┌──────────────┐ │ Response │ ── Answer grounded in documents │ to user │ ── With source citations └──────────────┘

\---

\#\# END OF DOCUMENT

\#\#\# Document Statistics

Total Sections: 33 Total Parts: 8 Estimated Lines: \~4,500+ (pseudocode/config) Services Covered: 14 (PostgreSQL, Redis, LiteLLM, Dify, n8n, Open WebUI, Flowise, Qdrant, Caddy, Prometheus, Grafana, SuperTokens, Ollama, \+ supporting scripts) Config Files: 25+ generated files Scripts Generated: 12 operational scripts Env Variables: 80+ tracked Docker Containers: 14+ orchestrated

\#\#\# How to Use This Document

1. Feed Part 1-2 to an LLM to generate Script 1 (system prep)  
2. Feed Part 1 \+ Parts 3-8 to generate Script 2 (deployment)  
3. Each section is self-contained enough for targeted regeneration  
4. The pseudocode is implementation-language-agnostic but optimized for bash script generation  
5. Variable references (${VAR}) are consistent throughout — they all trace back to master.env

\#\#\# Version

Document Version: 1.0.0 Created: 2025 Target: Ubuntu 22.04/24.04 LTS Architecture: Single-server, Docker-based

═══════════════════════════════════════════════════  
              END OF SPECIFICATION  
═══════════════════════════════════════════════════

---

**This concludes all 8 parts of the complete specification document.**

The entire document provides a comprehensive blueprint covering:

Copy table

| Part | Sections | Content |
| ----- | ----- | ----- |
| **1** | 1–4 | Architecture, philosophy, prerequisites, Script 1 structure |
| **2** | 5–8 | Script 1 execution phases, hardware detection, Docker/Ollama install |
| **3** | 9–12 | Script 2 overview, phase execution, interactive questionnaire |
| **4** | 13–16 | Credential generation, master.env builder, service env files |
| **5** | 17–20 | PostgreSQL init, Redis config, LiteLLM routing, budget system |
| **6** | 21–24 | Docker Compose builder, Caddyfile, monitoring configs |
| **7** | 25–28 | Backup/restore, convenience scripts, n8n workflows, troubleshooting |
| **8** | 29–33 | File manifest, env reference, port map, checklist, architecture diagrams |


