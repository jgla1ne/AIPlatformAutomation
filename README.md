# AI Platform Automation

> **Simple and reliable over complex and clever.**  
> This is a local tool, not a production SaaS.

A fully automated, containerised AI platform that deploys LLM routing, vector databases, web UIs, automation tools, and monitoring with **zero manual configuration**. Any model with access to the four scripts can reproduce a complete deployment from scratch by following this document.

---

## PLATFORM OVERVIEW

### Network Architecture

```
Internet
    │
    │ HTTPS (443) / HTTP (80)
    ▼
┌──────────────────────────────────────────────────┐
│                  Reverse Proxy                    │
│         Caddy  ──or──  Nginx Proxy Manager        │
│         (TLS: Let's Encrypt / self-signed / none) │
└──────────┬───────────────────────────────┘
           │ Internal Docker network
           │ (${DOCKER_NETWORK}  e.g. datasquiz-network)
      ┌────────────┼───────────────────────┐
      │            │                       │
      ▼            ▼                       ▼
┌──────────────┐ ┌──────────────┐     ┌──────────────────┐
│ LiteLLM      │ │   Web UIs    │     │   Automation     │
│  Proxy       │ │              │     │                  │
│  (unified    │ │ OpenWebUI    │     │  N8N             │
│  LLM API)    │ │ OpenClaw     │     │  Flowise         │
│              │ │ AnythingLLM  │     │  Dify            │
│ Providers:   │ │ LibreChat    │     └──────┬───────────┘
│  Ollama      │ └──────┬───────┘            │
│  Groq        │        │                    │
│  OpenRouter  │        ▼                    ▼
│  Mammouth    │ ┌──────────────┐     ┌──────────────────┐
│  Anthropic   │ │  Authentik   │     │  PostgreSQL+pgvec │
│  Google      │ │  (SSO/IdP)   │     │  Redis            │
│  OpenAI      │ └──────────────┘     │  MongoDB          │
└──────┬───────┘                      └──────────────────┘
       │
       ▼
┌───────────────────────────────────────────────┐
│  Local Model Runner                           │
│  Ollama  (gemma3, llama3.2, etc.)             │
└───────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│  Memory / Knowledge Layer            │
│  Zep CE   — Conversation memory      │
│  Letta    — Stateful agent runtime   │
│  Qdrant / Weaviate / Chroma / Milvus │
└──────────────────────────────────────┘
       │
       ▼
┌────────────────────┐  ┌──────────────────┐  ┌────────────────────┐
│  Monitoring        │  │  Development     │  │  Search / Comms    │
│  Grafana           │  │  Code Server     │  │  SearXNG           │
│  Prometheus        │  │  Continue.dev    │  │  Signalbot         │
└────────────────────┘  └──────────────────┘  └────────────────────┘
       │
       ▼
┌──────────────────────────────────────────┐
│  Ingestion                               │
│  rclone → Google Drive / S3 / local      │
│  Script 3 --ingest → embed → Qdrant      │
└──────────────────────────────────────────┘
```

> **LibreChat** is deployed when enabled. MongoDB is co-deployed automatically as its backing store (LibreChat does not support PostgreSQL as its chat store). The LibreChat RAG API uses pgvector (Postgres) for document embeddings.

### LibreChat Issues
- **MongoDB Connection**: LibreChat requires MongoDB. Ensure MongoDB container is healthy
- **MongoDB Corruption**: Script 2 automatically detects and recovers from MongoDB corruption by clearing data and restarting
- **RAG API**: LibreChat depends on the RAG API sidecar for document processing
- **Manual Recovery**: If automatic recovery fails, run `sudo rm -rf /mnt/datasquiz/mongodb/*` and restart MongoDB

### Integration Pipeline

```
Google Drive (rclone)
       │ sync to ${DATA_DIR}/ingestion/
       ▼
Vector Databases (Qdrant / Weaviate / Chroma / Milvus)
Conversation Memory (Zep CE — Postgres + pgvector)
Agent Memory (Letta — dedicated Postgres DB)
       │ retrieved context
       ▼
LiteLLM (unified OpenAI-compatible endpoint at :4000/v1)
       │ routes to Ollama (local) or external APIs (OpenAI, Anthropic, etc.)
       ▼
Web UIs (OpenWebUI / LibreChat / AnythingLLM / OpenClaw)
Automation (N8N / Flowise / Dify)
       │
       ▼
Reverse Proxy (Caddy or NPM) → Internet via HTTPS
```

Every web UI and automation tool routes all LLM calls through LiteLLM at `http://${TENANT_PREFIX}-litellm:4000/v1`. This gives unified cost tracking, model aliasing, and a single key rotation point.

---

## FOUR-SCRIPT ARCHITECTURE

```
Script 0 — Complete Cleanup      (root required)
Script 1 — Setup Wizard          (interactive, non-root)
Script 2 — Deployment Engine     (non-root, Docker group)
Script 3 — Mission Control       (non-root, Docker group)
```

### Data Flow

```
Script 1 ──writes──► platform.conf
                          │
Script 2 ──reads──────────┘
         ──writes──► docker-compose.yml
                  ──writes──► .configured/port-allocations
                  ──writes──► platform.conf  (runtime secrets only)
                  ──writes──► litellm_config.yaml, Caddyfile, zep-config.yaml
                  ──starts──► all containers (waits for healthy)
                          │
Script 3 ──reads──────────┘ (platform.conf + port-allocations)
         ──calls──► configure_*() per service
         ──displays──► credentials summary + post-deploy dashboard
         ──verifies──► port health, DNS, API keys
```

---

## SCRIPT REFERENCE

### Script 0 — Complete Cleanup

**Purpose:** Remove all containers, images, volumes, networks, data, and EBS mount for a named tenant. Full reset to pre-Script-1 state.

**Prerequisites:** Root (`sudo bash`).

**Usage:**
```bash
sudo bash scripts/0-complete-cleanup.sh <tenant_id> [--dry-run] [--containers-only]
```

**Options:**
- `--dry-run` — print all actions, execute nothing
- `--containers-only` — stop containers and remove networks only; leave data directories intact

**Inputs:**
- `tenant_id` — required positional argument
- `/mnt/<tenant>/config/platform.conf` — sourced if present; defaults used if absent

**Execution order (strict — must not be reordered):**
1. Typed confirmation: user must type exactly `DELETE <tenant_id>`
2. `docker compose down --volumes` via compose file (or manual container removal by label)
3. Remove Docker images scoped to tenant (by label + name prefix)
4. Stop Docker daemon if its `data-root` is on the EBS volume (holds block device FDs; unmount would fail without this)
5. `umount /mnt/<tenant>` (lazy fallback if busy)
6. `rm -rf /mnt/<tenant>` (safety: rejects paths outside `/opt/` or `/mnt/`)
7. `docker network rm <tenant>-network`

**Outputs:** Clean slate. No tenant files, containers, images, or networks remain.

**Expected outcome:** `Script 0 Complete ✓` banner. All data gone. Docker daemon stopped if it was using EBS. Script 1 can now run against the same tenant_id on a fresh EBS format.

**Multi-tenant support**: Each tenant gets isolated data directories, Docker networks, and port ranges to prevent conflicts. Subdomain architecture with internal routing: `tenant.domain.net` routes to internal services while keeping ports 80/443 open for direct access. Shared services (monitoring, logging) can be deployed in a shared namespace.

---

### Script 1 — Setup Wizard

**Purpose:** Collect all deployment configuration interactively and write a single `platform.conf` that drives the entire platform. Does NOT touch Docker.

**Prerequisites:** Non-root. Run as the deploy user (Docker group member).

**Usage:**
```bash
bash scripts/1-setup-system.sh <tenant_id>
```

**Inputs (collected interactively):**
- Tenant identity (ID, display name, admin email)
- Domain / base URL (used by Caddy for TLS + by Script 3 for access URLs)
- EBS device path (e.g. `/dev/nvme1n1`) and mount point (`/mnt/<tenant>`)
- Stack preset (minimal / development / standard / full / custom)
- Individual service toggles for custom stacks
- Memory layer selection (None / Zep / Letta / Both) for standard/full/custom
- API keys (OpenAI, Anthropic, etc.)
- Port preferences per service
- Reverse proxy type (Caddy or Nginx Proxy Manager) + TLS mode
- PUID / PGID for host-side directory ownership

**Dependency enforcement (automatic, non-overridable):**
- Zep or Letta enabled → forces `ENABLE_POSTGRES=true` + `ENABLE_LITELLM=true`
- LibreChat enabled → forces `ENABLE_MONGODB=true`
- LiteLLM enabled → validates at least one model provider (Ollama or API key)

**Outputs:**
- `/mnt/<tenant>/config/platform.conf` — single source of truth for all downstream scripts
- EBS volume formatted (ext4), mounted, and added to `/etc/fstab`
- Docker data-root configured to `${DATA_DIR}/docker` (daemon restarted)
- System packages installed (docker, rclone, etc.)

**Expected outcome:** `Script 1 Complete` banner. All configuration saved to `platform.conf`. Ready for Script 2 deployment.

#### Ollama Model Selection

Script 1 provides an interactive model selection menu with the latest available models:

**Available Ollama Models (Script 1 selection):**

**Small Models (< 4GB RAM):**
- Llama 3.2 1B - Latest compact model
- Llama 3.2 3B - Balanced small model
- Phi-3 Mini 4K - Microsoft's 4K context model
- Gemma 2 2B - Google's lightweight model
- Qwen 2.5 3B - Efficient multilingual model

**Medium Models (4-8GB RAM):**
- Llama 3.1 8B - General purpose, good balance
- Llama 3.2 7B - Latest medium model
- Mistral 7B - Fast, efficient for most tasks
- Qwen 2.5 7B - Strong reasoning capabilities
- Deepseek Coder V2 16B - Advanced coding model

**Large Models (8-16GB+ RAM):**
- Llama 3.1 70B - High performance, larger context
- Llama 3.3 70B - Latest large model
- Mixtral 8x7B - Mixture of experts, excellent reasoning
- Qwen 2.5 72B - Strong multilingual capabilities
- CodeLlama 70B - Specialized for code generation
- Gemma 4 9B - Google's latest multimodal model
- Gemma 4 27B - Google's large multimodal model

**Custom Options:**
- Custom model entry (option 18) for any model from ollama.com/library
- Support for model variants: `gemma3:4b`, `nemotron-cascade-2:latest`
- Multiple models: `gemma3:4b,llama3.2:3b` (note: `gemma4` tags do not exist in Ollama registry — use `gemma3`)

**Model Management:**
- Models are downloaded only once during initial deployment (P14 cost optimization)
- Script 3 provides `--ollama-pull`, `--ollama-remove`, `--ollama-list` commands
- `--flushall` properly wipes model cache for clean re-deploys
- Dynamic validation ensures models exist before LiteLLM configuration

#### GPU/CPU Detection and Deployment Guidance

Script 1 automatically detects hardware capabilities and provides deployment recommendations:

**Hardware Detection:**
- **NVIDIA GPU**: Detects VRAM capacity, recommends large models (8-16GB+)
- **AMD ROCm**: Detects ROCm support, recommends medium models (4-8GB)  
- **CPU-only**: Detects no GPU, recommends small models (< 4GB) for efficiency

**Deployment Mode Confirmation:**
- **GPU-accelerated**: Fast inference for production workloads
- **CPU-only**: Slower inference, suitable for development/testing
- **Upgrade guidance**: Recommends GPU instances for large model deployments

**System Resources Display:**
- GPU type and memory (NVIDIA/AMD/None)
- Total and available RAM
- Disk space availability
- Deployment mode recommendations based on hardware

**Key variables written to platform.conf:**
```
TENANT_ID, TENANT_PREFIX, BASE_DIR, DATA_DIR, CONFIG_DIR
DOMAIN, BASE_DOMAIN, TLS_MODE
ENABLE_<SERVICE>=true/false  (one per service)
<SERVICE>_PORT=<preferred>   (Script 2 may allocate different actual port)
PROXY_TYPE, ENABLE_CADDY, CADDY_ENABLED, ENABLE_NPM, NPM_ENABLED
URL_ROUTING_MODE=subdomain|port|path   (controls dashboard and Script 3 URL format)
PUID, PGID
GPU_TYPE=nvidia|rocm|none
GPU_MEMORY=<VRAM_MB>
TOTAL_RAM=<SYSTEM_RAM_MB>
AVAILABLE_RAM=<FREE_RAM_MB>
# LLM providers (all optional; used only when API key supplied)
ENABLE_OPENAI, OPENAI_API_KEY, OPENAI_MODELS
ENABLE_ANTHROPIC, ANTHROPIC_API_KEY, ANTHROPIC_MODELS
ENABLE_GOOGLE, GOOGLE_AI_API_KEY, GOOGLE_MODELS
ENABLE_GROQ, GROQ_API_KEY, GROQ_MODELS
ENABLE_OPENROUTER, OPENROUTER_API_KEY
ENABLE_MAMMOUTH, MAMMOUTH_API_KEY, MAMMOUTH_BASE_URL, MAMMOUTH_MODELS
# Ingestion
ENABLE_INGESTION, INGESTION_METHOD=rclone|s3|azure|local
GDRIVE_CREDENTIALS_FILE, GDRIVE_FOLDER_ID
# Memory / search extras
ZEP_AUTH_SECRET, LETTA_SERVER_PASS
SEARXNG_PORT, SEARXNG_SECRET_KEY
SERPAPI_KEY, BRAVE_API_KEY
```

---

### Script 2 — Deployment Engine

**Purpose:** Read `platform.conf`, generate all configs, allocate ports, deploy all containers, and wait until every enabled service is healthy.

**Prerequisites:** Non-root. Docker group member. Script 1 must have run successfully (EBS mounted, `platform.conf` present, Docker data-root on EBS).

**Self-Healing Database Recovery:**
Script 2 includes automatic database recovery for common migration issues:
- **Dify**: Auto-detects migration failures and wipes/recreates schema
- **LiteLLM**: Auto-detects table errors and clears cache/reinitializes
- **PostgreSQL**: Maintains schema integrity across service restarts
- **Result**: First-time deployments succeed reliably without manual intervention

**AI Development Tools Integration:**
All AI development tools are fully integrated with LiteLLM proxy:
- **Code Server**: Environment variables for LiteLLM URL, API key, and default model
- **Continue.dev**: VS Code extension with config.json pointing to LiteLLM
- **Model Access**: Both tools automatically use selected Ollama models via proxy
- **Unified Authentication**: Single LITELLM_MASTER_KEY for all AI services

**LiteLLM Admin UI:**
- **Access**: `http://127.0.0.1:4000/ui` (local) or subdomain if Caddy enabled
- **Authentication**: Password stored in platform.conf (LITELLM_UI_PASSWORD)
- **Model Management**: View loaded models and usage statistics
- **API Testing**: Built-in interface for testing model responses

**Integrated Monitoring Platform:**
Complete observability stack with automatic service discovery and health monitoring:
- **Prometheus**: Central metrics collection for all enabled services
- **Grafana**: Pre-configured dashboards for AI platform overview
- **Zero Configuration**: Automatic monitoring setup for every deployed component
- **Service Coverage**: Ollama, LiteLLM, Dify, Code Server, N8N, Flowise, AnythingLLM, OpenWebUI, LibreChat, OpenClaw, Authentik, Qdrant, PostgreSQL, Redis, MongoDB
- **Health Checks**: Service-specific endpoints with configurable scrape intervals
- **Resource Monitoring**: Container CPU, memory, and performance metrics
- **Request Tracking**: LiteLLM API request rates and response times

**Monitoring Access:**
```bash
# Prometheus UI (local)
http://127.0.0.1:9090

# Grafana Dashboard (with Caddy)
https://grafana.ai.datasquiz.net

# Direct Grafana (local)
http://127.0.0.1:3002
```

**Automatic Service Discovery:**
Every enabled service is automatically configured for monitoring:
- **AI Services**: Health endpoints, metrics collection, performance tracking
- **Infrastructure**: Database connections, vector DB status, reverse proxy health
- **Development Tools**: Code Server, Continue.dev integration status
- **Automation**: N8N workflow execution, Flowise pipeline health

**Usage:**
```bash
# Default: containers pruned; EBS data (Postgres, Redis, MongoDB, Ollama models,
# Docker image cache) preserved for fast cost-efficient retry
bash scripts/2-deploy-services.sh <tenant_id>

# Database-only recovery: wipes databases, preserves containers and models
bash scripts/2-deploy-services.sh <tenant_id> --flush-dbs

# True clean redeploy: wipes all databases, service state dirs, Ollama model
# cache, and Docker image cache before deploying
bash scripts/2-deploy-services.sh <tenant_id> --flushall
```

**Flags:**
| Flag | Effect |
|---|---|
| --flushall | Wipe all data (databases, models, images) |
| --flush-dbs | Wipe only databases (preserve containers/models) |
| _(none)_ | Prune containers; keep all EBS data intact. Images and models already cached are reused. Fast retry path — no re-download of models, no re-migration from scratch. |
| `--flushall` | After stopping containers, delete all DB data dirs (postgres/redis/mongodb), all service state dirs, Ollama model cache, and Docker image cache. Equivalent to a fresh deploy on a wiped volume without running Script 0+1. |
| `--dry-run` | Print what would be deployed; execute nothing. |

**Data persistence model:**
- EBS data directories (`${DATA_DIR}/postgres`, `redis`, `mongodb`, etc.) are **bind mounts** — `docker compose down` never touches them.
- Re-running Script 2 without `--flushall` gives idempotent retries: migrations are skipped (tables already exist), models are already downloaded, images are already pulled.
- `--flushall` is the right choice when you need a clean Prisma/Alembic migration state, or when releasing to a new environment.

**Inputs:**
- `/mnt/<tenant>/config/platform.conf` (written by Script 1)
- Docker group access

**Execution order:**
1. Framework validation — hard-fail if Docker data-root is not on EBS (forces Script 1 re-run)
2. Pre-flight checks — Docker daemon healthy, EBS mounted, network reachable
3. `prepare_data_dirs()` — `mkdir -p` all service directories, set ownership to `PUID:PGID`, `chmod 777` for services with fixed internal UIDs
4. Port allocator — `allocate_host_port()` resolves conflicts from preferred ports; writes `.configured/port-allocations`
5. `persist_generated_secrets()` — generates and persists (idempotent) all runtime secrets: `LITELLM_MASTER_KEY`, `POSTGRES_PASSWORD`, `AUTHENTIK_SECRET_KEY`, `AUTHENTIK_BOOTSTRAP_PASSWORD`, `ANYTHINGLLM_JWT_SECRET`, etc.
6. `generate_compose()` — writes `docker-compose.yml` via heredoc blocks (one per enabled service); no templating, no `.env` files
7. Config file generation — `litellm_config.yaml`, `Caddyfile` (Caddy only), `zep-config.yaml` (Zep only)
8. `docker compose up -d`
9. `wait_for_all_health()` — polls every enabled service health endpoint with per-service timeouts; creates Letta's dedicated PostgreSQL database + pgvector extension after Postgres healthy; restarts Letta after DB creation; checks Zep watermill tables exist (only restarts Zep if tables were missing — avoids unnecessary second boot cycle)
10. `trigger_initial_rclone_sync()` — restarts rclone container immediately after all health checks pass so first Google Drive sync fires without waiting for poll interval
11. `download_ollama_models()` — automatically pulls all configured Ollama models if not present, with cost-optimized duplicate checking
11. `show_post_deploy_dashboard()` — prints all service URLs (domain-aware), credentials, and pipeline description

**Outputs:**
- `/mnt/<tenant>/config/docker-compose.yml`
- `/mnt/<tenant>/config/litellm_config.yaml`
- `/mnt/<tenant>/config/Caddyfile` (Caddy only)
- `/mnt/<tenant>/config/zep-config.yaml` (Zep only)
- `/mnt/<tenant>/.configured/port-allocations` — actual ports (may differ from platform.conf preferences)
- `platform.conf` updated with runtime secrets (via `update_conf_value()`)
- All containers running and healthy

**Expected outcome:** `Script 2 Complete ✓` banner + post-deploy dashboard. Every enabled service has a running, healthy container. All URLs accessible (via proxy if configured). Ready for Script 3.

---

## MULTI-TENANT DEPLOYMENT

### Subdomain Architecture with Internal Routing

For multiple tenants, use subdomain-based deployment with internal port mapping:

```bash
# First tenant
./scripts/1-setup-system.sh datasquiz \
  --base-domain ai.dataquiz.net

# Second tenant  
./scripts/1-setup-system.sh tenant2 \
  --base-domain tenant2.dataquiz.net
```

**Service Access Patterns:**
- **External**: `https://tenant2.dataquiz.net:8080` → routes to internal port `3000`
- **Internal**: `https://tenant2.dataquiz.net` → routes to internal services on different ports

**Port Isolation:**
- Each tenant gets dedicated port range (e.g., 3000-3099, 3100-3199)
- Caddy uses ports 80/443 globally for all tenants
- Internal services communicate via tenant-specific subdomains

**Benefits:**
- ✅ No port conflicts between tenants
- ✅ Independent TLS certificates per tenant
- ✅ Complete service isolation while maintaining shared monitoring
- ✅ Flexible internal routing architecture

**Port allocations file** (authoritative over platform.conf for ports):
```
OPENWEBUI_HOST_PORT="3000"
LITELLM_HOST_PORT="4000"
# ... one line per service
```

**Runtime secrets written back to platform.conf:**
```
LITELLM_MASTER_KEY, POSTGRES_PASSWORD, REDIS_PASSWORD
AUTHENTIK_BOOTSTRAP_PASSWORD, AUTHENTIK_SECRET_KEY
ANYTHINGLLM_JWT_SECRET, ZEP_AUTH_SECRET, LETTA_SERVER_PASS
CODE_SERVER_PASSWORD   (random; shown in dashboard + Script 3 credentials)
LITELLM_UI_PASSWORD    (random; for LiteLLM web UI login)
DIFY_INIT_PASSWORD     (random; used by Script 3 configure_dify() to bootstrap first admin)
```

---

### Script 3 — Mission Control

**Purpose:** Post-deploy operations hub. Configures services, displays credentials, verifies health, and provides ongoing management commands.

**Prerequisites:** Non-root. Docker group member. Script 2 must have run successfully (all containers healthy).

**Usage:**
```bash
bash scripts/3-configure-services.sh <tenant_id>

# Self-healing database recovery
bash scripts/3-configure-services.sh <tenant_id> --flushall

# Configure AI development tools
bash scripts/3-configure-services.sh <tenant_id> --configure-ai

# Interactive model management
bash scripts/3-configure-services.sh <tenant_id> --configure-models
```

**Inputs:**
- `/mnt/<tenant>/config/platform.conf` (primary)
- `/mnt/<tenant>/.configured/port-allocations` (takes precedence for ports)

Port-allocations file is sourced after platform.conf so any Script 2 conflict-resolved port always wins.

**Execution:**
1. Sources both files
2. Calls `configure_<service>()` for each enabled service (guards against container non-existence)
3. Displays full health status table (up to 32 rows depending on enabled services — includes all 3 Dify containers, SearXNG, and rclone)
4. Runs port health checks for all enabled endpoints
5. Shows domain-aware access URLs (https://domain when Caddy/NPM active, http://IP otherwise)
6. Displays all credentials in a single summary block

**Outputs:**
- Health status table printed to stdout (all containers including dify-api, dify-worker)
- Credentials summary printed to stdout — every web service has a URL + login credentials
- Access URLs printed to stdout
- Service-specific configuration applied (Authentik bootstrap, Grafana datasource, Dify init, etc.)

**Expected outcome:** All enabled services show `healthy` or `running`. Access URLs use correct subdomain format when Caddy is active. Credentials summary contains login details for every service — the user never needs to hunt for a password after a fresh deploy.

**Credentials covered per service:**
| Service | What's shown |
|---|---|
| PostgreSQL | Host, user, password |
| Redis | Password |
| LiteLLM | URL, master key, UI password |
| OpenWebUI | URL (register on first visit) |
| LibreChat | URL (register on first visit) |
| OpenClaw | URL, WSS gateway URL, gateway token |
| AnythingLLM | URL, JWT secret |
| N8N | URL, encryption key |
| Flowise | URL, username, password |
| Dify | Web URL, API URL, init password |
| Authentik | URL, bootstrap email, bootstrap password |
| Grafana | URL, admin/password |
| Prometheus | URL |
| Code Server | URL, password |
| Signalbot | API URL, QR pairing link |
| Zep CE | URL, auth secret |
| Letta | URL, server password |
| Qdrant | API key |

**Management commands (post-deploy):**
```bash
# Ingestion pipeline — rclone → vector DB
bash scripts/3-configure-services.sh <tenant_id> --ingest
bash scripts/3-configure-services.sh <tenant_id> --ingest --skip-sync   # skip rclone step

# Tail logs for a service
bash scripts/3-configure-services.sh <tenant_id> --logs n8n
bash scripts/3-configure-services.sh <tenant_id> --logs n8n --log-lines 500

# Error audit across all containers
bash scripts/3-configure-services.sh <tenant_id> --audit-logs

# Reset credentials for a service
bash scripts/3-configure-services.sh <tenant_id> --reconfigure openwebui
bash scripts/3-configure-services.sh <tenant_id> --reconfigure dify
# Supported: openwebui, librechat, openclaw, dify, flowise, n8n, litellm, grafana, code-server, anythingllm

# Change LiteLLM routing strategy
bash scripts/3-configure-services.sh <tenant_id> --litellm-routing least-busy
# Valid: simple-shuffle, least-busy, usage-based-routing, cost-based-routing, latency-based-routing

# Ollama model management
bash scripts/3-configure-services.sh <tenant_id> --ollama-list
bash scripts/3-configure-services.sh <tenant_id> --ollama-pull llama3.2:3b
bash scripts/3-configure-services.sh <tenant_id> --ollama-remove llama3.2:1b

# Interactive model configuration
bash scripts/3-configure-services.sh <tenant_id> --configure-models

# Backup
bash scripts/3-configure-services.sh <tenant_id> --backup
bash scripts/3-configure-services.sh <tenant_id> --backup --schedule "0 3 * * *"  # daily at 3am
```

**Domain-aware URL logic (both `show_credentials()` and access URL section):**
```
URL_ROUTING_MODE=subdomain (default):
    URL = https://<subdomain>.<DOMAIN>        ← requires Caddy/NPM active

URL_ROUTING_MODE=path:
    URL = https://<DOMAIN>/<subdomain>        ← path-based; less common

URL_ROUTING_MODE=port (or no proxy):
    URL = http://<server-IP>:<port>           ← direct port access
```

`URL_ROUTING_MODE` is set by Script 1 wizard and written to platform.conf. Both `show_credentials()` and `show_post_deploy_dashboard()` in Script 3, and `display_service_summary()` in Script 1, all read this flag to format URLs consistently. Both `CADDY_ENABLED` and `ENABLE_CADDY` are checked (dual flag — both are written to platform.conf for compatibility).

---

## ALL SERVICES — FULL STACK

| Layer | Service | Image | Notes |
|---|---|---|---|
| **Infrastructure** | PostgreSQL | `pgvector/pgvector:pg15` | Shared DB + vector store; used by LiteLLM, Dify, Authentik, LibreChat RAG API; Letta gets dedicated `${DB}_letta` database |
| | Redis | `redis:7-alpine` | Session / queue store |
| | MongoDB | `mongo:7` | Required by LibreChat only; co-deployed automatically |
| **LLM** | Ollama | `ollama/ollama` | Local model runner |
| | LiteLLM | `ghcr.io/berriai/litellm:main-stable` | Unified LLM proxy + cost tracking; central gateway for all UIs |
| | Bifrost | `bifrost` | Optional alternative LLM gateway |
| **Web UIs** | OpenWebUI | `ghcr.io/open-webui/open-webui:main` | Primary chat UI |
| | AnythingLLM | `mintplexlabs/anythingllm` | RAG-first UI |
| | OpenClaw | `alpine/openclaw:latest` | Dynamic internal port via `OPENCLAW_PORT` env var |
| | LibreChat | `ghcr.io/danny-avila/librechat:latest` | Requires MongoDB (co-deployed); LLMs via LiteLLM |
| | LibreChat RAG API | `registry.librechat.ai/danny-avila/librechat-rag-api-dev-lite:latest` | Document RAG; embeddings via LiteLLM, vectors via pgvector |
| **Vector DB** | Qdrant | `qdrant/qdrant` | Fast ANN search |
| | Weaviate | `semitechnologies/weaviate` | Semantic + hybrid search |
| | ChromaDB | `chromadb/chroma` | Lightweight embedding store |
| | Milvus | `milvusdb/milvus:v2.4.0` | 3-container stack: etcd + MinIO + milvus (standalone) |
| **Automation** | N8N | `n8nio/n8n` | Workflow orchestration; pre-wired to LiteLLM |
| | Flowise | `flowiseai/flowise` | Low-code AI chains; SQLite backend |
| | Dify (web) | `langgenius/dify-web` | LLM app builder frontend (Next.js); requires dify-api |
| | Dify (api) | `langgenius/dify-api` | Flask backend (`command: api`); `CONSOLE_API_URL` must point here |
| | Dify (worker) | `langgenius/dify-api` | Celery background tasks (`command: worker`) |
| **Memory** | Zep CE | `ghcr.io/getzep/zep:latest` | Conversation memory; Postgres + pgvector; embeddings via LiteLLM |
| | Letta | `letta/letta:latest` | Stateful agent runtime (MemGPT); dedicated Postgres DB; LLMs via LiteLLM |
| **Identity** | Authentik | `ghcr.io/goauthentik/server` | SSO / OIDC provider |
| **Monitoring** | Grafana | `grafana/grafana` | Dashboards |
| | Prometheus | `prom/prometheus` | Metrics scraping |
| **Dev** | Code Server | `codercom/code-server` | Browser VS Code |
| **Search** | SearXNG | `searxng/searxng:latest` | Privacy-respecting meta search engine |
| **Alerting** | Signalbot | `bbernhard/signal-cli-rest-api` | Signal messenger REST API |
| **Proxy** | Caddy | `caddy:2-alpine` | Auto-configured reverse proxy (Caddyfile generated by Script 2) |
| | Nginx Proxy Manager | `jc21/nginx-proxy-manager:latest` | GUI reverse proxy; routes managed via web UI at :81 |

---

## CORE PRINCIPLES

**P1 — platform.conf is the primary source of truth**  
Script 1 writes it. Scripts 0, 2, 3 source it. Script 2 may append runtime-generated secrets (those Script 1 cannot know, e.g. `AUTHENTIK_BOOTSTRAP_PASSWORD`) via `update_conf_value()`. These write-backs are clearly labelled and idempotent.

**P2 — Script boundaries are strict**  
No cross-script calls. Each script has atomic responsibility. Clear input/output contracts.

**P3 — Explicit heredoc blocks for compose generation**  
No templating engines. No `.env` files. All configuration inline in `generate_compose()`. Every service block is a self-contained heredoc appended to docker-compose.yml.

**P4 — No `.env` files**  
Secrets are passed inline in `environment:` blocks within docker-compose.yml. No `envsubst`.

**P5 — Ports bind to `127.0.0.1` only**  
All internal services are localhost-only. Only the reverse proxy (80/443) is world-accessible.

**P6 — Rootless containers with documented exceptions**  
Most services run as `user: "${PUID}:${PGID}"`. Exceptions (must run as root in container):
- **LiteLLM** — Prisma writes migrations to Python package directories at startup.
- **OpenWebUI** — writes `.webui_secret_key` to `/app/backend/` (image-internal path).
- **Letta** — writes agent state to `/root/.letta` (image-internal path).

> **LibreChat** runs as `node` (uid 1000), NOT root. Its data dirs need `chmod 777`.

**P7 — Idempotency via marker files**  
`${CONFIGURED_DIR}/service_name` markers in `.configured/`. Scripts skip completed steps. Script 0 removes the entire `.configured/` tree.

**P8 — `set -euo pipefail` everywhere**  
Exit on error, unset variables, and pipe failures. Every variable referenced in Scripts 2 and 3 must have a `:-default` or be explicitly written before use.

**P9 — Bind mounts only**  
No named Docker volumes. All persistent data uses bind mounts under `/mnt/${TENANT_ID}/`.

**P10 — Dual logging**  
Timestamped log files at `${LOG_DIR}/` plus simultaneous stdout.

**P11 — No `/opt` usage**  
EBS mount: `/mnt/${TENANT_ID}/`. Fallback: `~/ai-platform/${TENANT_ID}/`. Never system directories.

**P12 — LiteLLM as central gateway**  
Every web UI and automation tool must be wired to LiteLLM (`http://${TENANT_PREFIX}-litellm:4000/v1`). No service connects to Ollama or external APIs directly.

**P13 - Dynamic Model Validation**  
All model configurations must be validated against provider APIs before deployment. No hardcoded model names. Deprecated models are automatically upgraded to latest available versions. Invalid models are gracefully skipped with warnings.

**P14 - Model Download Cost Optimization**  
Model downloads happen only in Script 2 during initial deployment. Script 3 re-runs avoid re-downloading existing models unless explicitly requested via --ollama-pull. The --flushall flag properly wipes model cache when clean re-deploy is needed.

---

## SERVICE QUIRKS (hard-won — required for correct deployment)

### Healthcheck Tool Availability

Not every image ships `curl`. Use the right tool per image or the healthcheck will always fail:

| Service | Available | Healthcheck pattern |
|---|---|---|
| OpenWebUI | `curl` | `curl -f http://localhost:8080/api/health` |
| LiteLLM | `python3` | `python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:4000/health/liveliness')"` |
| Qdrant | `bash` (no curl/wget) | `["CMD", "bash", "-c", "echo > /dev/tcp/localhost/6333"]` |
| N8N | `wget` | `wget -q --spider http://localhost:5678/healthz` |
| Dify-web | `node` | `node -e "const net=require('net');const s=net.connect(3000,'127.0.0.1',()=>{s.destroy();process.exit(0)});s.on('error',()=>process.exit(1));setTimeout(()=>process.exit(1),3000);"` — requires `HOSTNAME=0.0.0.0` so Next.js binds to all interfaces, not just Docker bridge IP |
| Dify-api | `python3` | `python3 -c "import socket; s=socket.socket(); s.settimeout(3); s.connect(('127.0.0.1',5001)); s.close()"` — `/health` returns non-2xx during Flask init; TCP check is reliable |
| Authentik | `python3` | `python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:9000/-/health/live/')"` |
| Flowise | `curl` | `curl -f http://localhost:3000/api/v1/ping` |
| LibreChat | `wget` | `wget -q --spider http://0.0.0.0:3080/health` (binds to 0.0.0.0; `/health` not `/api/health`) |
| LibreChat RAG API | `python3` (no curl/wget) | `python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"` |
| OpenClaw | `curl` | `curl -f http://localhost:${OPENCLAW_PORT}/health` (port dynamic — see quirk below) |
| Signalbot | `curl` | `curl -sf http://localhost:8080/v1/about` |
| Zep CE | `bash` (no curl/wget) | `["CMD", "bash", "-c", "echo > /dev/tcp/localhost/8000"]` |
| Letta | `curl` | `curl -f http://localhost:8283/v1/health` |

> **Dify-api** is a separate container (`langgenius/dify-api:latest`, `command: api`). Without it the web frontend loops forever on `/install`. `CONSOLE_API_URL` in the web container must point to the **browser-accessible** dify-api URL (Caddy subdomain when active, not `http://127.0.0.1:5001` which resolves inside the container).

### Correct Health Endpoints

| Service | Wrong | Correct |
|---|---|---|
| Qdrant | `/health` (404) | `/healthz` |
| Dify-web | — | Node.js TCP connect to `127.0.0.1:3000` (requires `HOSTNAME=0.0.0.0` — otherwise Next.js binds to Docker bridge IP, not loopback) |
| Dify-api | — | Python3 socket connect to `127.0.0.1:5001` (`/health` hangs during Flask init) |
| Authentik | `/-/health/` (404) | `/-/health/live/` |
| LiteLLM | `/health` | `/health/liveliness` |
| LibreChat | `/api/health` (404) | `/health` |
| OpenClaw | `/api/health` (404) | `/health` |
| Zep CE | `/` (404) | `/healthz` |

### Slow-Starting Services — `start_period` Required

| Service | `start_period` | Reason |
|---|---|---|
| LiteLLM | 900s | Downloads Prisma binaries + 20+ migration tables in `main-stable` image (~13-15 min on first run, Apr 2026+) |
| OpenWebUI | 120s | DB migrations on first run |
| Zep CE | 60s | Postgres migrations + hnsw index creation |
| N8N | 60s | DB init |
| Flowise | 60s | SQLite init |
| Dify-web | 2400s | All containers start simultaneously; dify-web is checked after LiteLLM's 30-min wait — start_period must outlast that window |
| Dify-api | 2400s | Same timing issue; Flask init is slow but TCP port opens quickly once gunicorn binds |
| Dify-worker | 2400s | Same timing issue; Celery startup 1-3 min; healthcheck is non-fatal |
| Authentik | 60s | Migration runner |
| Signalbot | 60s | signal-cli daemon takes ~26 s |
| AnythingLLM | 60s | DB migrations |
| Letta | 600s | Alembic migrations run before HTTP server binds — observed 5-8 min on first run; dedicated `_letta` DB must exist first |
| OpenClaw | 60s | DB + Redis connect on cold start |
| Code Server | 30s | VS Code server initialization |
| Weaviate | 30s | Data path scan on startup |
| ChromaDB | 30s | SQLite + segment manager init |

`wait_for_all_health()` timeouts: litellm 1800s (30 min — Prisma download + migrations), letta 900s, openwebui/authentik 180s. Dify-worker timeout is 180s but non-fatal (worker takes 1-3 min; deployment continues regardless).

### Directory Permissions

Services running as internal UIDs (not PUID:PGID) cannot write to host-side data directories owned by 1001:1001. Fix with `chmod 777` **before** container start:

| Service | Directory | Reason |
|---|---|---|
| Qdrant | `${DATA_DIR}/qdrant` | uid 1000 inside container |
| N8N | `${DATA_DIR}/n8n` | uid 1000 (node) |
| Signalbot | `${DATA_DIR}/signalbot` | uid 1000 |
| Authentik | `${DATA_DIR}/authentik` | migration creates `/media/public` |
| LibreChat | `${DATA_DIR}/librechat/uploads` `${DATA_DIR}/librechat/logs` | runs as `node` (uid 1000) |

> `prepare_data_dirs()` in Script 2 applies `chown -R PUID:PGID` only to subdirectories it created — never to `lost+found` or `docker` (root-owned EBS system dirs).

### Flowise — SQLite Only

`flowiseai/flowise:latest` is the enterprise edition. Its Postgres migrations break when schema was initialised by a different image version. Use `DATABASE_TYPE: sqlite`. Data at `/root/.flowise/database.sqlite` in the volume.

### LiteLLM — Key Variables

```
LITELLM_MIGRATION_DIR: /tmp/litellm-migrations   # avoids P3005 "schema not empty"
PRISMA_BINARY_CACHE_DIR: /tmp/prisma-cache
HOME: /tmp                                         # prevents PermissionError in wolfi
```

### LiteLLM — Model Name Conventions

All model entries in `config.yaml` follow the `provider/model` format for `litellm_params.model`. The `model_name` (alias shown to clients) uses a consistent scheme:

| Provider | `model_name` | `litellm_params.model` |
|---|---|---|
| Ollama | `ollama/gemma3:4b` | `ollama/gemma3:4b` |
| Groq | `groq/llama-3.3-70b-versatile` | `groq/llama-3.3-70b-versatile` |
| OpenRouter | `openrouter/meta-llama/llama-3-70b-instruct` | `openrouter/meta-llama/...` |
| Mammouth | `mammouth/claude-sonnet-4-6` | `openai/claude-sonnet-4-6` + `api_base` |
| Anthropic | `claude-3-5-sonnet-20241022` | `anthropic/claude-3-5-sonnet-20241022` |
| Google | `gemini-1.5-flash` | `google/gemini-1.5-flash` |

**Mammouth AI** is a multi-model proxy (`https://api.mammouth.ai/v1`) that exposes Claude, Gemini, and GPT models under an OpenAI-compatible API. Configure as `openai/` provider with `api_base` override. Default models: `claude-sonnet-4-6`, `gemini-2.5-flash`, `gpt-4o`. Model names are resolved via Mammouth's `/v1/models` endpoint.

**Ollama memory management** — on low-RAM hosts set these to prevent model hoarding:
```
OLLAMA_KEEP_ALIVE: "5m"       # unload model after 5 min idle
OLLAMA_MAX_LOADED_MODELS: "1" # only keep 1 model hot at a time
```

### OpenWebUI — Correct Variable Names

`WEBUI_SECRET_KEY` (not `WEBUI_SECRET`). Container listens on port **8080** (not 3000). Port mapping: `"127.0.0.1:${OPENWEBUI_PORT}:8080"`.

### OpenClaw — Dynamic Port, Config Mount, and Token Auth

OpenClaw reads `OPENCLAW_PORT` from its environment and binds to **that port** inside the container. Do NOT pass `--port` in the command — let the env var control the bind port. Correct port mapping: `"127.0.0.1:${OPENCLAW_PORT}:${OPENCLAW_PORT}"`. Caddy/NPM proxy targets `${TENANT_PREFIX}-openclaw:${OPENCLAW_PORT}`.

OpenClaw stores its config at `/home/node/.openclaw/openclaw.json` (not `/.openclaw`). The volume must be mounted there:
```yaml
volumes:
  - ${DATA_DIR}/openclaw/data:/app/data
  - ${DATA_DIR}/openclaw/home:/home/node/.openclaw
```
Script 2's `prepare_data_dirs()` pre-seeds `openclaw.json` with the `OPENCLAW_PASSWORD` gateway token and allowed CORS origins before the first container start — this is the only way to seed the token (env var `GATEWAY_TOKEN` seeds it only when the file is absent).

**Credentials displayed by Script 3:**
- Web UI: `https://openclaw.${BASE_DOMAIN}`
- Gateway URL (for desktop/mobile client): `wss://openclaw.${BASE_DOMAIN}`
- Token: `${OPENCLAW_PASSWORD}` (from platform.conf)

### Zep CE — Config File Required (Not Env Vars)

Zep 0.27.x uses viper's `AutomaticEnv()` but does **not** honour env vars for `store.type`. Core settings must be in a `/app/config.yaml` file:
```yaml
store:
  type: postgres
  postgres:
    dsn: "postgres://user:pass@host:5432/db?sslmode=disable"
auth:
  required: true
  secret: "..."
```
Script 2 generates this file at deploy time and mounts it `:ro`. Zep has no `curl` or `wget` — use `bash /dev/tcp` for the healthcheck.

### Letta — Dedicated Database

Letta and LiteLLM both create a `users` table. They **cannot share a database**. Script 2:
1. Creates `${POSTGRES_DB}_letta` database after Postgres is healthy: `psql -U ${POSTGRES_USER} -d postgres -c "CREATE DATABASE ..."`
2. Enables pgvector extension in the new database separately
3. Restarts the Letta container to break the crash-backoff loop

`LETTA_PG_URI` must point to `.../${POSTGRES_DB}_letta`, not `.../${POSTGRES_DB}`.

### Zep — Watermill Table Guard (Conditional Restart)

Zep runs `CREATE TABLE IF NOT EXISTS watermill_*` at startup via its own "Initializing subscriber schema" routine. In the rare case where Postgres is slow to accept connections at Zep's first init, those tables may not be created — causing a subscriber error loop on subsequent starts.

After Zep is healthy, Script 2 queries Postgres to check whether both watermill tables exist. It only restarts Zep if the tables are actually missing:

```bash
# Count watermill tables — only restart if fewer than 2 exist
count=$(psql -tAc "SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema='public'
    AND table_name IN ('watermill_message_token_count','watermill_offsets_message_token_count');")
if [[ "$count" -lt 2 ]]; then
    psql -c "CREATE TABLE IF NOT EXISTS watermill_message_token_count ..."
    docker restart zep   # only when tables were actually missing
fi
```

**Why conditional?** An unconditional restart causes a second boot cycle (migrations + hnsw index rebuild) that exceeds the `wait_for_health` timeout. Zep normally creates its own tables — the restart is only needed on the rare Postgres-busy edge case.

### LiteLLM — Config Flag Required

LiteLLM's image default entrypoint does NOT automatically load `/app/config.yaml`. The `--config` flag must be explicit:

```yaml
command: ["--config", "/app/config.yaml", "--port", "4000"]
```

Without this, LiteLLM starts with 0 models registered (model list API returns empty array) and all routing attempts fail.

### rclone — Config Format and service-account.json Mount

Script 1 saves the pasted service account JSON as `service-account.json` and generates a proper INI `rclone.conf` alongside it. The `INGESTION_METHOD` variable is stored as `"rclone"` (not numeric `"1"`) — Script 2 reads this string to decide whether to deploy the rclone container. The rclone config file must be INI-format, not a raw JSON service account file. Script 2 copies `GDRIVE_CREDENTIALS_FILE` to `${DATA_DIR}/rclone/service-account.json` and mounts it at `/credentials/service-account.json` inside the container:

```ini
[gdrive]
type = drive
scope = drive.readonly
service_account_file = /credentials/service-account.json
```

The service account must have the target Google Drive folder explicitly shared with its email (`service-account@project.iam.gserviceaccount.com`). Service accounts have no access to Drive by default.

After all health checks pass, Script 2 calls `trigger_initial_rclone_sync()` which restarts the rclone container to kick off an immediate sync — files appear in `${DATA_DIR}/ingestion/` without waiting for the first poll interval.

**Ingestion pipeline (Script 3 `--ingest`):** After files are synced to `${DATA_DIR}/ingestion/`, Script 3's `run_ingestion_pipeline()` discovers text-based files (txt, md, pdf, csv, json, yaml, etc.), embeds each via LiteLLM (`/v1/embeddings`), and upserts vectors into the selected vector DB (Qdrant by default, collection `ingestion`). The Qdrant collection is created automatically if it doesn't exist (1536-dim cosine for OpenAI `text-embedding-3-small`). The pipeline can be triggered after an rclone sync or with `--skip-sync` to embed already-synced files only. Trigger: `bash scripts/3-configure-services.sh <tenant_id> --ingest`.

### N8N — Webhook URL Must Use HTTPS Subdomain When Caddy Active

`N8N_WEBHOOK_URL=http://${DOMAIN}/` (the old default) causes "Error connecting to n8n" in the browser because n8n tries to establish a WebSocket connection to the wrong host/protocol.

When `CADDY_ENABLED=true`, Script 2 sets:
```
N8N_WEBHOOK_URL=https://n8n.${BASE_DOMAIN}/
N8N_HOST=n8n.${BASE_DOMAIN}
N8N_PROTOCOL=https
N8N_EDITOR_BASE_URL=https://n8n.${BASE_DOMAIN}
```

### Signalbot — Caddy Route Required for QR Pairing

Signalbot's REST API binds to `127.0.0.1:8080` only. Without a Caddy route the pairing URL (`/v1/qrcodelink`) is not reachable from a browser. Script 2 generates a `signal.${BASE_DOMAIN}` route in the Caddyfile. The post-deploy dashboard prints the full QR link URL:
```
https://signal.ai.yourdomain.net/v1/qrcodelink?device_name=signal-api
```

### OpenClaw — "Origin Not Allowed" CORS Error

OpenClaw's gateway CORS check rejects browser connections from `https://openclaw.${BASE_DOMAIN}` unless explicitly allowed. Script 2 applies a two-layer fix:

1. Env vars in compose: `CORS_ORIGIN=*`, `ALLOWED_ORIGINS=*`, `GATEWAY_CONTROL_UI_ALLOWED_ORIGINS=*`
2. `openclaw.json` pre-seeded by `prepare_data_dirs()` at `${DATA_DIR}/openclaw/home/openclaw.json` (mounted at `/home/node/.openclaw/openclaw.json`):
```json
{
  "gateway": {
    "auth": { "mode": "token", "token": "${OPENCLAW_PASSWORD}" },
    "controlUi": {
      "allowedOrigins": ["https://openclaw.yourdomain.net", "*"]
    }
  }
}
```
The file is only written if absent (idempotent). The `GATEWAY_TOKEN` env var is also set as a fallback for fresh containers with no pre-seeded file.

### Code Server — Password Generated and Persisted

The default `changeme` password was replaced. Script 2 now generates a random password via `openssl rand -base64 16` and writes it to `platform.conf` via `persist_generated_secrets()`. The password is shown in the post-deploy dashboard credentials block and at `code.${BASE_DOMAIN}`.

### Dify — Full Stack Required (web + api + worker)

Deploying only `langgenius/dify-web` causes the browser to loop forever on `/install`. The full stack requires three containers using two images:

| Container | Image | Command | Port |
|---|---|---|---|
| `dify` | `langgenius/dify-web:latest` | (default) | 3000 |
| `dify-api` | `langgenius/dify-api:latest` | `api` | 5001 |
| `dify-worker` | `langgenius/dify-api:latest` | `worker` | — |

**Single-subdomain path routing (required for self-signed TLS):**  
When Caddy uses a self-signed cert, the browser accepts the cert for `dify.${BASE_DOMAIN}` but blocks XHR to `dify-api.${BASE_DOMAIN}` (different hostname = different cert = separate manual acceptance required, which the browser silently blocks). This causes `/install` to hang — the page renders but all API calls fail with no visible error.

Script 2 routes **all Dify traffic through `dify.${BASE_DOMAIN}`** using Caddy path handles (matching dify's official nginx config):
```
dify.example.com {
    handle /console/api* { reverse_proxy dify-api:5001 }
    handle /api*         { reverse_proxy dify-api:5001 }
    handle /v1*          { reverse_proxy dify-api:5001 }
    handle /files*       { reverse_proxy dify-api:5001 }
    handle               { reverse_proxy dify:3000     }
}
```

`CONSOLE_API_URL` and `APP_API_URL` in the web container are set to `https://dify.${BASE_DOMAIN}` (same hostname as the UI). There is no separate `dify-api.${BASE_DOMAIN}` route.

**`HOSTNAME=0.0.0.0` required:**  
Next.js standalone server uses `$HOSTNAME` as its bind address. Without an explicit override it resolves the container hostname (e.g. `c6adbb7ed196`) to the Docker bridge IP (`172.17.0.2`), making `127.0.0.1` unreachable inside the container. All TCP healthcheck probes fail. Setting `HOSTNAME: "0.0.0.0"` in the compose environment makes it bind to all interfaces.

**dify-worker healthcheck**: Celery workers don't expose HTTP — `celery inspect ping` is fragile (requires broker reachability and correct app path). The worker healthcheck uses `pgrep -f 'celery' > /dev/null` instead. The dify-worker `wait_for_health` timeout is non-fatal — deployment completes even if the worker health check times out.

### Milvus — Three-Container Stack

Milvus standalone requires three containers:
- `milvus-etcd` — metadata store (`quay.io/coreos/etcd:v3.5.5`)
- `milvus-minio` — object store (`minio/minio:latest`)
- `milvus` — vector engine (`milvusdb/milvus:v2.4.0`)

`milvus` depends on both sidecars. Data dirs: `${DATA_DIR}/milvus/etcd`, `${DATA_DIR}/milvus/minio`, `${DATA_DIR}/milvus/data`.

### Authentik — Bootstrap, Secret Stability, and Schema Migrations

`AUTHENTIK_BOOTSTRAP_PASSWORD` and `AUTHENTIK_BOOTSTRAP_EMAIL` are generated by Script 2 at deploy time and written to docker-compose.yml. Script 2 also appends them to platform.conf via `update_conf_value()`.

`AUTHENTIK_SECRET_KEY` must be **stable across redeploys** — regenerating it invalidates all Authentik sessions and tokens. Script 2's `persist_generated_secrets()` generates it once and writes it to platform.conf; subsequent runs read the existing value.

**Authentik 500 / "relation does not exist"**: On fresh or version-upgraded databases, Authentik's internal django-tenant schema objects may be missing even though `Running migrations: No migrations to apply.` is logged. Script 3's `configure_authentik()` runs `docker exec <container> ak migrate` (idempotent) to force-apply all pending tenant schema migrations. If you hit 500s after a manual deploy, run this manually:
```bash
docker exec ai-<tenant>-authentik ak migrate
docker restart ai-<tenant>-authentik
```

### Reverse Proxy — Caddy vs NPM

Two options, mutually exclusive — only one may be enabled per deployment:

| Proxy | Image | Config | Admin |
|---|---|---|---|
| **Caddy** | `caddy:2-alpine` | Caddyfile auto-generated by Script 2; all routes pre-configured | No admin UI — routes from Caddyfile |
| **Nginx Proxy Manager** | `jc21/nginx-proxy-manager:latest` | No config generated; routes managed via web UI at `:81` | `admin@example.com` / `changeme` (change on first login) |

NPM is more flexible (GUI route management, per-route SSL, access lists). Caddy requires no manual post-deploy configuration.

**Critical:** Script 1 writes **both** `ENABLE_CADDY` and `CADDY_ENABLED` (and equivalents for NPM) to platform.conf — Scripts 2 and 3 check both names for maximum compatibility. `URL_ROUTING_MODE` (subdomain/port/path) must also be written so Scripts 2 and 3 generate correct URLs. If upgrading an old platform.conf, add all three variables manually.

### networks: in build_*_deps() Functions

Every `build_*_deps()` function in Script 2 that emits a `depends_on:` block **must also emit a `networks:` block**. Services that omit `networks:` default to the `config_default` bridge — not the tenant network — making inter-service DNS resolution fail silently.

---

## DEPLOYMENT WORKFLOW

### Full Deployment (from scratch)

```bash
# 1. Complete cleanup (idempotent — safe on a fresh machine)
sudo bash scripts/0-complete-cleanup.sh <tenant_id>

# 2. Interactive configuration (collects all inputs, writes platform.conf)
bash scripts/1-setup-system.sh <tenant_id>

# 3. Deploy all containers
bash scripts/2-deploy-services.sh <tenant_id>

# 4. Configure services, display credentials, run health checks
bash scripts/3-configure-services.sh <tenant_id>
```

### Stack Presets (Script 1)

| Preset | Services |
|---|---|
| `minimal` | Postgres, Redis, Ollama, LiteLLM, OpenWebUI, Qdrant, SearXNG |
| `development` | Minimal + Code Server |
| `standard` | Development + N8N, Flowise, Grafana, Prometheus + **memory layer prompt** |
| `full` | Standard + OpenClaw, AnythingLLM, Dify, Authentik, SignalBot, LibreChat + **memory layer prompt** |
| `coding` | Minimal + Code Server, Continue.dev, SearXNG (optimized for development) |
| `custom` | Individual toggle per service |

After selecting `standard`, `full`, or `custom`, Script 1 shows the **Memory Layer** prompt:

| Choice | Services | Purpose |
|---|---|---|
| None | — | — |
| Zep CE | `ghcr.io/getzep/zep:latest` | Conversation memory — extracts facts from chat; gives UIs access to past context. Postgres + pgvector. |
| Letta | `letta/letta:latest` | Stateful agent runtime (MemGPT) — agents manage their own memory blocks. Dedicated Postgres DB. |
| Both | Zep CE + Letta | Complementary. Zep = chat-level memory, Letta = agent-level memory. |

### TLS Modes

| Mode | What Script 2 does |
|---|---|
| `letsencrypt` | Caddy / NPM handles ACME automatically |
| `manual` | Expects cert/key at paths set in platform.conf |
| `selfsigned` | Generates self-signed cert at deploy time |
| `none` | HTTP only |

### Port Resolution

Script 1 stores **preferred** ports in platform.conf. Script 2's `allocate_host_port()` walks forward from the preferred port until it finds an unclaimed value. Results stored in `.configured/port-allocations`. Script 3 sources this file after platform.conf — actual allocated ports always win.

Example (OPENWEBUI_PORT=3000, FLOWISE_PORT=3000 — same preference):
- openwebui → 3000 (first-served)
- flowise → 3001 (auto-incremented)
- dify → 3002
- grafana → 3003
- anythingllm → 3004

---

## CORE PRINCIPLES — COMPLIANCE CHECKLIST

Use when implementing or reviewing any script change:

- [ ] Does Script 2 write `platform.conf`? Only via `update_conf_value()` for runtime secrets.
- [ ] Does every `build_*_deps()` emit both `depends_on:` and `networks:`?
- [ ] Does every service with a fixed internal UID get `chmod 777` on its data dir?
- [ ] Does LiteLLM / OpenWebUI / Letta omit `user:` override (must run as root in container)?
- [ ] Does LibreChat have `chmod 777` on its uploads/ and logs/ dirs (runs as node uid 1000)?
- [ ] Does every `configure_*()` function in Script 3 guard against container non-existence?
- [ ] Are all healthcheck endpoints correct (see table above)?
- [ ] Are `start_period` values set for slow-starting services?
- [ ] Is `set -euo pipefail` at the top of every script?
- [ ] Do all variable references use `${VAR:-default}` or have guaranteed prior assignment?
- [ ] Are all host ports bound to `127.0.0.1`?
- [ ] Does `prepare_data_dirs()` chown only created subdirectories (not `lost+found` or `docker`)?
- [ ] Is `AUTHENTIK_SECRET_KEY` persisted (not regenerated) across redeploys?
- [ ] Is `LETTA_PG_URI` pointing to `.../${POSTGRES_DB}_letta` (not the shared DB)?
- [ ] Does every web UI pass LiteLLM master key + base URL (not direct model endpoints)?
- [ ] Is `N8N_WEBHOOK_URL` using `https://n8n.${BASE_DOMAIN}/` when Caddy is active?
- [ ] Does `CODE_SERVER_PASSWORD` use a generated random value (not `changeme`) and is it in `persist_generated_secrets()`?
- [ ] Does `flush_all_data()` only run when `--flushall` is passed (never by default)?
- [ ] Are all Zep watermill restarts conditional (check table count before restarting)?
- [ ] Do Node.js-based container healthchecks use `node -e` not `bash /dev/tcp` (bash absent in Node images)?
- [ ] Is Dify deployed as 3 containers (web + api + worker)? Is `CONSOLE_API_URL` set to `https://dify.${BASE_DOMAIN}` (NOT a separate `dify-api` subdomain — self-signed TLS + separate subdomain = browser blocks all XHR)?
- [ ] Does the Caddy `dify.${BASE_DOMAIN}` block use path handles (`/console/api*`, `/api*`, `/v1*`, `/files*` → dify-api; `handle` → dify-web)?
- [ ] Is `HOSTNAME: "0.0.0.0"` set in the dify-web environment (without it Next.js binds to Docker bridge IP, breaking internal healthchecks)?
- [ ] Does Signalbot have a Caddy route (`signal.${BASE_DOMAIN}`)? Is the QR link URL printed in the dashboard?
- [ ] Does the rclone config reference `service_account_file = /credentials/service-account.json` (not `credentials.json`)?
- [ ] Does `trigger_initial_rclone_sync()` fire after `wait_for_all_health()` in main()?
- [ ] Does platform.conf contain `URL_ROUTING_MODE` (subdomain/port/path) and both `ENABLE_CADDY`+`CADDY_ENABLED` (or NPM equivalents)?
- [ ] Do all URL helper functions (`_url()` in Script 3, `_mu()` in Script 1) check both `CADDY_ENABLED` and `ENABLE_CADDY` and respect `URL_ROUTING_MODE`?
- [ ] Does `show_credentials()` display login credentials for every enabled web service?
- [ ] Does `configure_dify()` call `/console/api/setup` on dify-api port (5001), not on dify-web port?
- [ ] Does dify-web healthcheck use `node -e "net.connect(3000,'127.0.0.1',...)"` (bash absent in Next.js image; nc -z unreliable; node is guaranteed present)?
- [ ] Does Script 1 translate numeric `INGESTION_METHOD` (1-5) to string (`rclone`, `gdrive`, etc.) before writing platform.conf?
- [ ] Does Script 1 save rclone credentials as `service-account.json` + generate INI `rclone.conf` (not write raw JSON as `rclone.conf`)?
- [ ] Does `reconfigure_service()` in Script 3 also update platform.conf (not just restart the container)?
- [ ] Does `change_litellm_routing()` update both `litellm_config.yaml` and `platform.conf`?
- [ ] Does Script 0 stop Docker, use `fuser -km` on mount, and verify unmount success?
- [ ] Is `GPU_TYPE` detected in Script 1 and respected in Script 2 (Ollama/OpenWebUI reservations)?
- [ ] Does Script 2 include 1-hour `start_period` for LiteLLM first-boot resilience?
- [ ] Does Script 2 implement dynamic model validation (P13) before configuring LiteLLM?
- [ ] Are embedding models (`text-embedding-3-small`) dynamically validated and injected into Script 2's LiteLLM config?
- [ ] Does Script 2 handle model downloads (not Script 3) to avoid re-download costs on re-runs (P14)?
- [ ] Does Script 2 check if models already exist before pulling to avoid unnecessary downloads?
- [ ] Does --flushall properly wipe Ollama model cache for clean re-deploys?
- [ ] Does Script 2 implement MongoDB corruption detection and recovery before LibreChat health check?
- [ ] Does Script 2 clear MongoDB data directory and restart container when corruption is detected?
- [ ] Does Script 3 include `--test-pipeline` command for end-to-end validation?
- [ ] Does Script 3 install the `ai-platform-${TENANT_ID}` systemd unit when `--setup-persistence` is used?
- [ ] Is the Dify worker healthcheck using the lightweight Python-based `/proc` probe (not `celery status`)?

---

## TROUBLESHOOTING

### Container not starting

1. `docker logs <container>` — always start here.
2. `docker inspect <container> --format '{{.State.Health}}'` for healthcheck output.
3. `docker inspect <container> --format '{{json .HostConfig.PortBindings}}'` to verify port mapping.

### Script 3 times out on a service

The service is enabled in platform.conf but the container was not deployed. Either:
- Add a container-existence guard in `configure_<service>()` (preferred), or
- Set `ENABLE_<SERVICE>="false"` in platform.conf and re-run Script 3.

### Port mismatch between platform.conf and running containers

Script 2 resolved a port conflict and wrote the actual port to `.configured/port-allocations`. Script 3 sources this file. The port-allocations value is authoritative.

### LibreChat MongoDB Connection Issues

**Symptoms**: LibreChat logs show `connect ECONNREFUSED` to MongoDB
**Automatic Recovery**: Script 2 detects MongoDB corruption and automatically:
1. Stops MongoDB container
2. Clears corrupted data from `/mnt/datasquiz/mongodb/*`
3. Restarts MongoDB with fresh database
4. Verifies connectivity before proceeding to LibreChat

**Manual Recovery**: If automatic recovery fails:
```bash
sudo docker stop ai-datasquiz-mongodb
sudo rm -rf /mnt/datasquiz/mongodb/*
sudo docker start ai-datasquiz-mongodb
# Wait 30 seconds for MongoDB to initialize
```

### LiteLLM P1001 (can't reach Postgres)

The litellm service is on the wrong Docker network. Every `build_*_deps()` function must emit `networks: - ${DOCKER_NETWORK}` alongside its `depends_on:` block.

### LiteLLM P3005 (database schema not empty)

Set `LITELLM_MIGRATION_DIR: /tmp/litellm-migrations` in the compose environment block.

### Letta reported unhealthy — migrations still running

Letta runs Alembic schema migrations before binding the HTTP server. On first deploy against a new `_letta` database this takes 5-8 minutes. If `wait_for_health` fires before the server is up, Docker reports `unhealthy` and deployment fails.

**Root cause:** Docker's healthcheck `start_period` was too short — failed checks during migration counted toward the retry limit, flipping status to `unhealthy` before migration finished.

**Fix (already applied):** `start_period: 600s` in the Letta healthcheck (keeps Docker in `starting` through the migration window) and `wait_for_health letta 900s`. The server comes up ~30s after "Starting Letta Server..." appears in logs.

### Letta `relation "users" already exists`

Letta is sharing a database with LiteLLM. `LETTA_PG_URI` must point to a dedicated `${POSTGRES_DB}_letta` database, not the shared `${POSTGRES_DB}`. Script 2 creates this database automatically after Postgres is healthy.

### Dify loops on `/install`

`CONSOLE_API_URL` points to a dify-api that isn't running or isn't reachable from the browser. Check:
1. The `dify-api` container is healthy: `docker ps | grep dify-api`
2. The Caddy route `dify-api.${BASE_DOMAIN}` is present: `curl -s http://127.0.0.1:2019/config/ | grep dify-api`
3. `CONSOLE_API_URL` in the web container env matches the Caddy route URL: `docker inspect ${TENANT_PREFIX}-dify | grep CONSOLE_API_URL`

If `CONSOLE_API_URL=http://127.0.0.1:5001`, it resolves inside the container (loopback to the dify-web container itself, not dify-api). Re-deploy with the fix in Script 2.

### N8N — "Error connecting to n8n"

`N8N_WEBHOOK_URL` is set to the wrong host or protocol. Check:
```bash
docker inspect ${TENANT_PREFIX}-n8n | grep N8N_WEBHOOK_URL
```
It must be `https://n8n.${BASE_DOMAIN}/` when Caddy is active. Also verify `N8N_HOST`, `N8N_PROTOCOL`, and `N8N_EDITOR_BASE_URL` match.

### EBS format fails (`/dev/nvme1n1 apparently in use`)

Docker daemon's `data-root` is on the EBS volume and holds open file descriptors to the block device. Script 0 must stop the Docker daemon before unmounting. If running cleanup manually, stop Docker first: `sudo systemctl stop docker`.

### HTTPS not serving (services unreachable via domain)

Check that `ENABLE_CADDY="true"` **or** `ENABLE_NPM="true"` is in platform.conf (not just `PROXY_TYPE="caddy"`). Script 2 checks the `_ENABLED` variable, not `PROXY_TYPE`. If missing, add the variable and re-run Script 2.

### Signalbot — number not paired

After deploy, pair the phone number. The post-deploy dashboard prints the exact QR link URL. When Caddy is active, open it in the browser directly:
```
https://signal.ai.yourdomain.net/v1/qrcodelink?device_name=signal-api
```

From the server (without Caddy), use curl:
```bash
# Option A — link existing device (scan QR in Signal app)
curl -s "http://127.0.0.1:${SIGNALBOT_PORT}/v1/qrcodelink?device_name=ai-platform"

# Option B — register a new number (receives SMS code)
curl -s -X POST "http://127.0.0.1:${SIGNALBOT_PORT}/v1/register/+<number>"
curl -s -X POST "http://127.0.0.1:${SIGNALBOT_PORT}/v1/register/+<number>/verify/<CODE>"
```

---

## PROJECT STATUS

| Script | Status | Key behaviours |
|---|---|---|
| **Script 0** — Nuclear Cleanup | Production ready | Typed confirmation, Docker daemon stop before EBS unmount, scoped image removal |
| **Script 1** — Setup Wizard | Production ready | Interactive wizard, stack presets, memory layer selection, dependency enforcement, writes platform.conf |
| **Script 2** — Deployment Engine | Production ready | Heredoc compose generation, port allocator, secret persistence, Letta DB creation, MongoDB corruption recovery, Dify database recovery, --flush-dbs flag, P14 model cost optimization, SearXNG search engine, post-deploy dashboard |
| **Script 3** — Mission Control | Production ready | Sources port-allocations (takes precedence), 24-service health table, domain-aware URLs, credentials summary, ingestion pipeline, log management, service reconfigure, LiteLLM routing, **dynamic model lookup** (--ollama-latest, 30 models), **batch model input** (comma-separated), **success tracking** (X/Y reporting), Ollama model management, interactive model configuration, SearXNG configuration, backup, **reboot persistence** |

---

*Version: 5.8.0 | Last Updated: 2026-04-20 | Architecture: 4 scripts, 26 services (Dify 3-container stack, SearXNG, rclone), single-tenant per EBS volume | Providers: Ollama, Groq, OpenRouter, Mammouth AI, Anthropic, Google, OpenAI | URL_ROUTING_MODE: subdomain/port/path | Mem0 removed*
