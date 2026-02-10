# **AIPlatformAutomation — Full Solution v76.4.0**

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

`---`

`## Network Architecture`

     `┌─────────────┐`  
      `│ Public IP   │`  
      `│ Proxy/SSL   │`  
      `└─────┬──────┘`  
            `│`  
      `┌─────▼─────┐`  
      `│  Tailscale │`  
      `│  Overlay  │`  
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

`> Tailscale overlay handles secure internal traffic; public IP used only for proxies, SSL, and external endpoints.`

`---`

`## Step-by-Step Deployment`

``### Step 0 — Cleanup (`0-complete-cleanup.sh`)``  
`**Purpose:** Nuclear cleanup before deployment.`

`- Removes all Docker containers, images, networks, and volumes.`  
``- Cleans `/mnt/data` and `$HOME/config` (root-owned files included).``  
``- Preserves `/scripts/` folder.``  
`- Optionally dry-run.`  
``- Logs all deletions: `/mnt/data/logs/cleanup.log`.``  
`- Optional system reboot.`

`---`

``### Step 1 — Setup (`1-setup-system.sh`)``  
`**Purpose:** Collect configuration and prepare system.`

`**Features:**`

`1. **Volume & directories:**`  
   ``- Mount `/mnt/data` or alternative.``  
   ``- Creates folder structure: `/mnt/data/config`, `/mnt/data/logs`.``  
   ``- Correct ownership (`chown` for running user).``

`2. **Service selection (numbered):**`  
   `- **Core:** Ollama, LiteLLM, AnythingLLM`  
   `- **AI Stack:** Dify, ComfyUI, OpenWebUI, Flowise, OpenClaw UI`  
   `- **Optional Monitoring:** Grafana, Prometheus, ELK, Portainer`

`3. **External services configuration:**`  
   `- Google Drive: OAuth or service account JSON`  
   `- Signal phone number`  
   `- Tailscale auth key + API key`  
   `- Proxy: HTTP/HTTPS ports, SSL email, public domain`

`4. **Ports & routing:**`  
   `- Assign ports per service with pre-filled defaults`  
   `- LiteLLM routing: Round Robin, Priority, Weighted`

`5. **Outputs:**`  
   `` - `.env`, `credentials.txt`, `openclaw_config.json` written to `/mnt/data/config` ``  
   `- Summary table of services, selected ports, routing strategy, mounts`  
   `` - Logs: `/mnt/data/logs/setup.log` ``

`---`

``### Step 2 — Deploy Services (`2-deploy-services.sh`)``  
`**Purpose:** Pull and deploy Docker services in correct dependency order.`

`**Deployment order:**`  
`1. VectorDB (Chroma/Qdrant)`  
`2. OpenClaw`  
`3. Core LLMs`  
`4. AI Stack apps`  
`5. Optional monitoring tools`

`**Features:**`  
`- Pull Docker images with retry logic.`  
`- Up services incrementally using Docker Compose fragments.`  
`- Timeout-based health checks per service.`  
`` - Structured logs: `/mnt/data/logs/deploy.log` ``  
`- Conflict detection for ports before deployment.`  
`- Post-deployment summary table: service, port, endpoint, status.`

`---`

``### Step 3 — Configure Services (`3-configure-services.sh`)``  
`**Purpose:** Wire services together and validate endpoints.`

`**Features:**`  
`- Configure LiteLLM routing.`  
`- OpenClaw → VectorDB linkage.`  
`- Signal number verification.`  
`- Google Drive configuration check.`  
`- Tailscale overlay verification.`  
`- Optional monitoring integration.`  
`- Summary table: endpoints, ports, status.`  
`` - Logs: `/mnt/data/logs/configure.log` ``

`---`

``### Step 4 — Add Service (`4-add-service.sh`)``  
`**Purpose:** Incremental addition of new services.`

`**Features:**`  
`- Templates for AI apps or monitoring tools.`  
`- Collect service-specific env variables and credentials.`  
`- Generate Docker Compose fragment.`  
`- Port conflict detection.`  
`- Deploy new service.`  
`` - Post-deployment log: `/mnt/data/logs/add_service.log` ``

`---`

`## Directory Structure`

/mnt/data/  
 config/ \# .env, credentials.txt, openclaw\_config.json  
 logs/ \# step-specific logs  
 docker/ \# optional persistent volumes  
 /scripts/ \# all step scripts  
 /compose/ \# individual service docker-compose fragments

`---`

`## Services & Default Ports`

`| Service      | Port | Notes |`  
`|--------------|------|-------|`  
`| LiteLLM      | TBD  | Configured in Step 1 |`  
`| OpenClaw     | TBD  | Linked to Vector DB |`  
`| VectorDB     | TBD  | Chroma / Qdrant |`  
`| Dify         | TBD  | AI Stack |`  
`| ComfyUI      | TBD  | AI Stack |`  
`| OpenWebUI    | TBD  | AI Stack |`  
`| Flowise      | TBD  | AI Stack |`  
`| Grafana      | 5601 | Optional |`  
`| Prometheus   | 9090 | Optional |`  
`| ELK          | 5601 | Optional |`  
`| Portainer    | 9000 | Optional |`

`---`

`## UX Design`

`- **Interactive numbered selection** for services and routing options.`  
`- **Icons** and clear prompts for status, input, and errors.`  
`- **Retry loops** for invalid input.`  
`- **Post-step summary tables** with endpoints, ports, and health status.`  
`` - **Logs centralized** at `/mnt/data/logs/` ``

`---`

`## Security`

`- Secrets dynamically generated.`  
`- Tailscale overlay ensures secure internal access.`  
`- SSL certificates for proxy domain.`  
`- Optional Google Drive authentication via OAuth or Service Account JSON.`  
`- Signal integration with phone number verification.`

`---`

`## Observability`

`` - Logs per step in `/mnt/data/logs/` ``  
`- Health check summaries per service`  
`- Optional monitoring stack integrated with Grafana, Prometheus, ELK.`

`---`

`## Notes`

``- Re-running Step 1 detects existing `.env` and prompts for cleanup first.``  
`- All scripts are **idempotent and modular**, safe to re-run.`  
`- Volume mounts are selectable and properly permissioned for the running user.`  
`- Docker Compose fragments allow incremental service addition via Step 4.`

`---`

`## Key Outcomes`

`- Fully autonomous AI platform.`  
`- On-premise embeddings for private data.`  
`- Modular stack for AI apps, internal and external LLMs.`  
`- Secure networking via Tailscale and optional public proxy.`  
`- Comprehensive logging, health checks, and interactive UX.`  

