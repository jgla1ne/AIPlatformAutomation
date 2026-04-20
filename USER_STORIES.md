# AI Platform — Functional Blueprint

> This document breaks the platform into epics, features, and user stories.  
> Each story maps to scripts, services, and config variables so any engineer can implement, test, or extend a feature in isolation.

---

## EPIC 1 — Platform Lifecycle

**Goal:** A DevOps engineer can stand up a complete AI platform from a bare EC2 instance, tear it down completely, and redeploy — all without manual intervention beyond answering the Script 1 wizard.

---

### Feature 1.1 — Complete Cleanup

**As a** DevOps engineer,  
**I want** a single command that completely removes all containers, data, and configuration for a tenant,  
**so that** I can start a fresh deployment without leftover state causing mysterious failures.

**Acceptance criteria:**
- Typed confirmation (`DELETE <tenant_id>`) required before any destructive action
- All containers stopped and removed
- All containers stopped and removed
- All Docker volumes removed
- Tenant data directory removed (`/mnt/<tenant>`)
- Docker images scoped to tenant removed (by label and name prefix)
- Docker daemon stopped if data-root is on EBS (with cooldown period)
- EBS unmounted before directory removal; uses `fuser -km` to break process locks
- Post-unmount verification: Script fails if mountpoint remains (protects data)
- Path safety: Refuses to delete `/mnt` or `/opt` root directories
- Docker network removed
- Supports `--dry-run` (print actions, execute nothing)
- Supports `--containers-only` (leave data intact)
- Script: `0-complete-cleanup.sh`

---

### Feature 1.2 — Interactive Configuration Wizard

**As a** DevOps engineer,  
**I want** an interactive wizard that asks me all deployment questions once and writes a single config file,  
**so that** I never have to edit YAML or shell scripts manually.

**Acceptance criteria:**
- Collects: tenant ID, display name, admin email, domain, EBS device, stack preset, service toggles, API keys, ports, proxy type, TLS mode, PUID/PGID
- Auto-detects system capabilities: CPU, RAM, and GPU (NVIDIA/ROCm/None)
- Validates domain format and DNS resolution
- Validates EBS device exists before formatting
- All inputs, including detected `GPU_TYPE` and `GPU_MEMORY`, written to `platform.conf`
- Script: `1-setup-system.sh`

---

### Feature 1.3 — Zero-Touch Deployment

**As a** DevOps engineer,  
**I want** a single command that deploys all selected services and waits until every one is healthy,  
**so that** I know the platform is ready before running any configuration steps.

**Acceptance criteria:**
- Reads `platform.conf` — no interactive input required
- Generates `docker-compose.yml` via heredoc blocks (no templating engines)
- Allocates ports, resolving conflicts automatically
- Creates all data directories with correct ownership before container start
- All containers deployed in correct dependency order
- Health checks pass for every enabled service before script exits
- **Stability requirement**: Healthchecks for Dify/Celery use lightweight shell probes (no Python) to prevent process piling.
- **GPU leverage**: Automatically injects `deploy.resources.reservations` for NVIDIA devices into relevant containers (Ollama, OpenWebUI).
- **First-Boot Resilience**: LiteLLM/Letta support 1-hour `start_period` to safely complete migrations on fresh EBS volumes.
- **Dynamic Model Validation**: Automatic validation of all provider models against their APIs before configuration; deprecated models auto-upgraded to latest versions.
- **Permanent Gateway**: Automatic injection of `text-embedding-3-small` and validated model routing into `config.yaml`.
- **GPU leverage**: Automatically injects `deploy.resources.reservations` for NVIDIA devices.
- Post-deploy dashboard printed with all service URLs and credentials
- Script exits non-zero if any enabled service fails health checks within timeout
- Default re-run (no flags): containers pruned, EBS data preserved — fast retry, no re-pull
- `--flushall` flag: wipes all databases, service state, Ollama models, Docker image cache — true clean redeploy
- Script: `2-deploy-services.sh`

---

### Feature 1.4 — Post-Deploy Mission Control

**As a** DevOps engineer,  
**I want** a single command that configures all services, displays all credentials, and verifies everything is reachable,  
**so that** I can hand over a working platform without any manual post-deploy steps.

**Acceptance criteria:**
- Sources actual allocated ports (not just preferred ports) from `.configured/port-allocations`
- Displays health status table for all 28+ services (container name, health state, port) — includes dify, dify-api, dify-worker
- Runs port-level health checks for 24 endpoints
- Displays domain-aware access URLs (https://domain when proxy active, http://IP:port otherwise)
- Displays credentials summary (all usernames, passwords, API keys) in a single block covering every enabled web service
- Service-specific configuration applied (Authentik bootstrap, Grafana datasource, N8N LiteLLM wiring, Dify API setup)
- Post-deploy management commands available (no full redeploy required):
  - `--ingest [--skip-sync]` — run ingestion pipeline
  - `--logs <service> [--log-lines N]` — tail service logs
  - `--audit-logs` — ERROR/FATAL scan across all containers
  - `--reconfigure <service>` — reset credentials for any web service
  - `--litellm-routing <strategy>` — change LLM routing strategy live
  - `--ollama-list / --ollama-pull / --ollama-remove` — manage Ollama models
  - `--backup [--schedule "<cron>"]` — one-off or scheduled data backup
  - `--setup-persistence` — install systemd unit for automatic reboot standup
  - `--health-check` — print live container health table only
  - `--show-credentials` — print credentials only
- Script: `3-configure-services.sh`

---

### Feature 1.5 — Idempotent Re-runs

**As a** DevOps engineer,  
**I want** all four scripts to be safely re-runnable without duplicating work or breaking existing state,  
**so that** I can resume an interrupted deployment or apply configuration changes without a full teardown.

**Acceptance criteria:**
- Script 0: `--dry-run` always safe; destructive actions require typed confirmation
- Script 1: re-running overwrites `platform.conf` (intended — wizard is the source of truth)
- Script 2: marker files in `.configured/` skip already-completed steps; port allocations idempotent; secrets not regenerated if already in platform.conf
- Script 3: `configure_*()` functions guard against already-configured services; re-run safe
- Secret persistence: `AUTHENTIK_SECRET_KEY`, `ANYTHINGLLM_JWT_SECRET`, `LITELLM_MASTER_KEY` stable across redeploys

---

### Feature 1.6 — Cost-Efficient Deployment Iteration

**As a** DevOps engineer iterating on deployment fixes,  
**I want** to re-run Script 2 without re-downloading images or re-running long migrations,  
**so that** I minimise EC2 data transfer costs and time spent waiting during debugging cycles.

**Acceptance criteria:**
- Default Script 2 re-run preserves all EBS-mounted data: Postgres, Redis, MongoDB, Ollama models, Docker image cache
- EBS bind-mount directories survive `docker compose down` — no data loss on container restart
- `CREATE TABLE IF NOT EXISTS` / migration idempotency means existing schemas don't block re-deploy
- `--flushall` flag available when a genuinely clean state is required:
  - Deletes: `postgres/`, `redis/`, `mongodb/`, all service state dirs, `ollama/models/`
  - Runs `docker image prune -af` to force re-pull of all images
  - 5-second countdown warning before irreversible deletion
  - Skips deletion of: `config/`, `logs/`, `rclone/` (credentials from Script 1)
- Script 0 full teardown (`rm -rf ${BASE_DIR}`) wipes EBS filesystem entirely; Script 1 re-formats it
- Script: `2-deploy-services.sh --flushall`

---

## EPIC 2 — LLM Access & Routing

**Goal:** Every AI service in the platform routes all LLM calls through a single unified gateway (LiteLLM), giving the operator unified cost tracking, model aliasing, and a single key rotation point.

---

### Feature 2.1 — Local Model Serving

**As a** platform operator,  
**I want** to run open-source LLMs locally on the same EC2 instance,  
**so that** I can serve AI capabilities without sending data to external APIs.

**Acceptance criteria:**
- Ollama deployed and healthy
- GPU passthrough configured when GPU available
- Default model pulled during Script 3 `configure_ollama()` step
- Post-deploy model management via Script 3 without container restart:
  - `--ollama-list` — list currently loaded models
  - `--ollama-pull <model>` — download a new model (e.g. `llama3.2:3b`)
  - `--ollama-remove <model>` — remove an existing model to free disk space
- Ollama accessible within Docker network at `http://${TENANT_PREFIX}-ollama:11434`
- Service: `ollama`

---

### Feature 2.2 — Unified LLM Proxy

**As a** platform operator,  
**I want** a single OpenAI-compatible endpoint that routes to any configured model (local or cloud),  
**so that** I can switch providers or add new models without reconfiguring every web UI.

**Acceptance criteria:**
- LiteLLM deployed and healthy at `:4000`
- `litellm_config.yaml` generated by Script 2 with all configured providers
- Ollama local models registered in config when Ollama enabled
- External API keys (OpenAI, Anthropic, etc.) from platform.conf registered in config
- Master key generated and persisted in platform.conf
- All web UIs and automation tools wired to `http://${TENANT_PREFIX}-litellm:4000/v1`
- Service: `litellm`

---

### Feature 2.2b — Live Routing Strategy Management

**As a** platform operator,  
**I want** to change LiteLLM's routing strategy without redeploying,  
**so that** I can tune cost vs latency trade-offs after launch based on observed usage.

**Acceptance criteria:**
- Script 3 `--litellm-routing <strategy>` updates `litellm_config.yaml` and restarts LiteLLM
- Supported strategies: `simple-shuffle`, `least-busy`, `usage-based-routing`, `cost-based-routing`, `latency-based-routing`
- `LITELLM_ROUTING_STRATEGY` updated in platform.conf so the change survives future redeploys
- LiteLLM health-polled after restart before command returns
- Script: `3-configure-services.sh --litellm-routing <strategy>`

---

### Feature 2.3 — Multi-Provider Key Management

**As a** platform operator,  
**I want** to configure API keys for multiple providers once (in the wizard),  
**so that** all services can access cloud models without per-service key management.

**Acceptance criteria:**
- Script 1 wizard collects keys for: OpenAI, Anthropic, Google, Groq, OpenRouter, Mammouth AI
- All keys written to platform.conf
- Script 2 injects keys into `litellm_config.yaml` only for providers where a key was supplied
- Model names validated against provider APIs before writing config (stale/deprecated names auto-replaced)
- No key written to docker-compose.yml in plaintext (all via LiteLLM proxy)
- Services: `litellm`

---

### Feature 2.4 — Mammouth AI Multi-Model Proxy

**As a** platform operator,  
**I want** a single API key that gives access to Claude, Gemini, and GPT models simultaneously,  
**so that** I can use best-in-class models from different vendors without managing multiple billing accounts.

**Acceptance criteria:**
- Mammouth AI configured in LiteLLM as an `openai`-compatible provider with `api_base: https://api.mammouth.ai/v1`
- Default models: `claude-sonnet-4-6`, `gemini-2.5-flash`, `gpt-4o` (each as a separate `model_name` entry)
- Model list sourced from Mammouth's `/v1/models` endpoint at deploy time; configurable via `MAMMOUTH_MODELS`
- `ENABLE_MAMMOUTH`, `MAMMOUTH_API_KEY`, `MAMMOUTH_BASE_URL`, `MAMMOUTH_MODELS` written to platform.conf
- Script 1 wizard prompts for Mammouth API key when `ENABLE_MAMMOUTH=true`
- Services: `litellm` (no new container — provider config only)

---

### Feature 2.5 — URL Routing Mode

**As a** platform operator,  
**I want** to choose how service URLs are formatted in dashboards and credentials output,  
**so that** the displayed URLs match how my network actually routes traffic to services.

**Acceptance criteria:**
- Script 1 wizard presents three choices: `subdomain` / `port` / `path`
- `URL_ROUTING_MODE` written to platform.conf
- All URL helper functions in Scripts 1, 2, and 3 read `URL_ROUTING_MODE` to format URLs:
  - `subdomain`: `https://service.${BASE_DOMAIN}` (default; requires Caddy/NPM)
  - `port`: `http://${SERVER_IP}:${PORT}` (direct port; no proxy required)
  - `path`: `https://${BASE_DOMAIN}/service` (path-based proxy)
- Both `CADDY_ENABLED` and `ENABLE_CADDY` written to platform.conf (dual-flag for script compatibility)

---

## EPIC 3 — Memory & Knowledge

**Goal:** AI agents and chat interfaces have access to persistent memory (past conversations, facts, agent state) and a knowledge base (document embeddings in vector databases).

---

### Feature 3.1 — Conversation Memory

**As an** AI chat user,  
**I want** my chat UI to remember context from previous sessions,  
**so that** I don't have to re-explain my background and preferences every conversation.

**Acceptance criteria:**
- Zep CE deployed and healthy at `:8000`
- Postgres + pgvector backing store (shared Postgres instance, dedicated schema)
- Auth token generated and persisted in platform.conf
- Embeddings generated via LiteLLM (not a separate embedding model)
- OpenWebUI and LibreChat wired to Zep API URL + token at deploy time
- Service: `zep`

---

### Feature 3.2 — Stateful Agent Memory

**As an** AI developer,  
**I want** to deploy agents that remember their own state (persona, facts, scratchpad) across sessions,  
**so that** I can build MemGPT-style agents without managing memory logic myself.

**Acceptance criteria:**
- Letta deployed and healthy at `:8283`
- Dedicated PostgreSQL database `${POSTGRES_DB}_letta` (separate from shared DB to prevent table conflicts)
- pgvector extension enabled in dedicated database
- Database created and pgvector enabled by Script 2 after Postgres healthy
- Letta restarted after database creation (breaks crash-backoff loop)
- LLM calls routed via LiteLLM
- Service: `letta`

---

### Feature 3.3 — REMOVED (Mem0)

> **Removed.** Mem0 was removed from the stack in v5.7.0. Zep CE (Feature 3.1) covers conversation memory; Letta (Feature 3.2) covers stateful agent memory. The `mem0` container no longer exists in Script 2 or Script 3.

---

### Feature 3.4 — Vector Search (Qdrant)

**As an** AI developer,  
**I want** a high-performance vector database for semantic search and RAG,  
**so that** I can build retrieval-augmented generation pipelines.

**Acceptance criteria:**
- Qdrant deployed and healthy at `:6333`
- Data directory at `${DATA_DIR}/qdrant` with correct permissions (uid 1000 inside container)
- Healthcheck via `bash /dev/tcp` (no curl/wget in image)
- Service: `qdrant`

---

### Feature 3.5 — Additional Vector Databases

**As an** AI developer,  
**I want** to choose between Weaviate (hybrid search), ChromaDB (lightweight), and Milvus (enterprise-scale),  
**so that** I can match the vector store to my use case.

**Acceptance criteria:**
- Weaviate deployable independently; accessible at `:8080`
- ChromaDB deployable independently; accessible at `:8000`
- Milvus deployable as 3-container standalone stack (etcd + MinIO + milvus); accessible at `:19530`
- All three deployable simultaneously without port conflicts
- Services: `weaviate`, `chroma`, `milvus` (+ `milvus-etcd`, `milvus-minio`)

---

## EPIC 4 — Web UIs

**Goal:** Multiple chat and RAG interfaces are available so users can choose the UI that fits their workflow, all backed by the same LiteLLM gateway.

---

### Feature 4.1 — Primary Chat Interface (OpenWebUI)

**As an** end user,  
**I want** a polished, feature-rich chat interface with model selection and conversation history,  
**so that** I can have productive AI conversations without using external services.

**Acceptance criteria:**
- OpenWebUI deployed and healthy
- Pre-configured with LiteLLM as the OpenAI endpoint
- `WEBUI_SECRET_KEY` set (not `WEBUI_SECRET`)
- Port mapping to internal port 8080 (not 3000)
- Zep API URL + token injected at deploy time when Zep is enabled
- Letta API URL + token injected at deploy time when Letta is enabled
- Service: `openwebui`

---

### Feature 4.2 — RAG-First Interface (AnythingLLM)

**As an** end user,  
**I want** a UI focused on document upload and retrieval-augmented chat,  
**so that** I can ask questions about my own documents without building a RAG pipeline.

**Acceptance criteria:**
- AnythingLLM deployed and healthy
- JWT secret generated and persisted (stable across redeploys)
- LiteLLM API URL and key pre-configured
- Service: `anythingllm`

---

### Feature 4.3 — OpenClaw Interface

**As an** end user,  
**I want** access to the OpenClaw AI interface,  
**so that** I have an additional UI option for different interaction styles.

**Acceptance criteria:**
- OpenClaw deployed and healthy
- Dynamic internal port: `OPENCLAW_PORT` env var tells OpenClaw which port to bind; port mapping uses same port on both sides
- Config directory mounted at `/.openclaw` (not just `/app/data`)
- Proxy routes to `${TENANT_PREFIX}-openclaw:${OPENCLAW_PORT}`
- Service: `openclaw`

---

### Feature 4.4 — LibreChat

**As an** end user,  
**I want** LibreChat's multi-modal, multi-provider interface with agent and plugin support,  
**so that** I have the most feature-complete open-source chat UI available.

**Acceptance criteria:**
- LibreChat deployed and healthy
- MongoDB co-deployed automatically (LibreChat requires it; Postgres is not supported as chat store)
- LibreChat RAG API deployed as sidecar; embeddings via LiteLLM; vector store via pgvector
- All LLM calls routed via LiteLLM
- Upload and log directories have `chmod 777` (LibreChat runs as node uid 1000)
- Healthcheck at `/health` (not `/api/health`)
- Services: `librechat`, `librechat-rag-api`, `mongodb`

---

## EPIC 5 — Automation & Workflows

**Goal:** Visual workflow builders and automation tools are pre-wired to LiteLLM so operators can build AI-powered automations without manual API key configuration.

---

### Feature 5.1 — N8N Workflow Automation

**As an** operator,  
**I want** N8N pre-configured with LiteLLM credentials,  
**so that** I can build AI workflows immediately after deploy without configuring the OpenAI node manually.

**Acceptance criteria:**
- N8N deployed and healthy at `:5678`
- `OPENAI_API_KEY` set to LiteLLM master key
- `OPENAI_API_BASE_URL` set to `http://${TENANT_PREFIX}-litellm:4000/v1`
- Service: `n8n`

---

### Feature 5.2 — Flowise Low-Code AI Chains

**As an** AI developer,  
**I want** Flowise deployed and accessible,  
**so that** I can build and test LangChain/LlamaIndex pipelines via drag-and-drop.

**Acceptance criteria:**
- Flowise deployed and healthy at `:3000`
- `DATABASE_TYPE: sqlite` (not Postgres — enterprise migrations break on re-deploy)
- Service: `flowise`

---

### Feature 5.3 — Dify LLM App Builder

**As an** AI developer,  
**I want** Dify deployed as a full-stack LLM app builder,  
**so that** I can build and deploy LLM-powered applications with a visual builder, backed by a real API and worker process.

**Acceptance criteria:**
- Three containers deployed: `dify` (Next.js frontend, port 3000), `dify-api` (Flask backend, `command: api`, port 5001), `dify-worker` (Celery worker, `command: worker`)
- Both `dify-api` and `dify-worker` use image `langgenius/dify-api:latest` with different `command:` values
- **Single-subdomain path routing** — Caddy routes `/console/api*`, `/api*`, `/v1*`, `/files*` on `dify.${BASE_DOMAIN}` to dify-api; all other paths to dify-web. No separate `dify-api.${BASE_DOMAIN}` subdomain. This is mandatory when TLS is self-signed: the browser accepts a cert for one hostname but silently blocks XHR to a second hostname with its own cert, causing `/install` to hang.
- `CONSOLE_API_URL` and `APP_API_URL` set to `https://dify.${BASE_DOMAIN}` (same hostname as the web UI)
- `HOSTNAME: "0.0.0.0"` set in dify-web environment — Next.js standalone server uses `$HOSTNAME` as its bind address; without it Next.js resolves the container hostname to the Docker bridge IP (e.g. `172.17.0.2`), making `127.0.0.1` unreachable inside the container and breaking all healthcheck probes
- `DIFY_INIT_PASSWORD` generated and persisted; Script 3 `configure_dify()` calls `/console/api/setup` on port 5001 (not the web port)
- Dify-web healthcheck: `node -e "net.connect(3000,'127.0.0.1',...)"` — bash absent in Next.js image; `nc -z` is unreliable (exits 0 even when nothing is listening in this image); Node.js is guaranteed present
- Dify-api healthcheck: Python3 socket connect to port 5001 — `/health` endpoint returns non-2xx during Flask initialization; TCP check confirms gunicorn is bound
- `start_period: 2400s` for all three dify containers — all containers start simultaneously; dify services are checked after LiteLLM's ~30 min wait; start_period must exceed that window
- dify-worker `wait_for_health` timeout is non-fatal — deployment completes even if the Celery worker takes > 3 min to fully start
- Services: `dify`, `dify-api`, `dify-worker`

---

## EPIC 6 — Content Ingestion

**Goal:** Documents from Google Drive are automatically synced into the platform's knowledge base so AI services always have access to the latest content.

---

### Feature 6.1 — Google Drive Sync

**As an** operator,  
**I want** files from a Google Drive folder automatically synced to the platform,  
**so that** my AI services always have up-to-date documents without manual uploads.

**Acceptance criteria:**
- Script 1 wizard prompts for Google service account JSON; saves it as `${DATA_DIR}/config/service-account.json` and generates a proper INI `rclone.conf` alongside it — raw JSON is NOT written as `rclone.conf`
- `INGESTION_METHOD` written to platform.conf as `"rclone"` (string), not `"1"` (numeric) — Script 2 reads the string value to decide whether to deploy the rclone container
- `GDRIVE_CREDENTIALS_FILE` set to the `service-account.json` path in platform.conf
- rclone container deployed when `ENABLE_INGESTION=true` and `INGESTION_METHOD=rclone`
- rclone.conf mounted at `/config/rclone/rclone.conf:ro`; service-account.json mounted at `/credentials/service-account.json:ro`
- Sync target (container `/data`): bind-mounted to `${DATA_DIR}/ingestion/` on host
- Container runs a polling sync loop (configurable interval, default 5 min)
- After `wait_for_all_health()`, Script 2 calls `trigger_initial_rclone_sync()` to kick off immediate first sync
- Service account must have the target Google Drive folder **explicitly shared** with it (service accounts have no Drive access by default)
- Service: `rclone`

---

### Feature 6.2 — Ingestion Pipeline to Vector Store

**As an** AI developer,  
**I want** synced documents automatically embedded and indexed in the vector database,  
**so that** new content is searchable by AI services without manual indexing steps.

**Acceptance criteria:**
- Script 3 `--ingest` command triggers the full pipeline end-to-end
- `--skip-sync` flag skips the rclone sync step and embeds already-present files only
- Pipeline discovers all text-based files in `${DATA_DIR}/ingestion/` (txt, md, pdf, csv, json, yaml, yml, rst, log, html, xml)
- Each file embedded via LiteLLM `/v1/embeddings` (model: `text-embedding-3-small`, truncated to 8000 chars)
- Vectors upserted into Qdrant collection `ingestion` (1536-dim cosine); collection auto-created if not present
- Point IDs are deterministic (md5 of file path → integer) so re-running is idempotent
- Payload stored with each vector: `filename`, `path`, `source: "ingestion"`
- Progress reported: files ingested / files failed
- Trigger: `bash scripts/3-configure-services.sh <tenant_id> --ingest`

---

## EPIC 7 — Identity & Security

**Goal:** All web-facing services are protected by a single SSO provider, and all secrets are generated securely and never hardcoded.

---

### Feature 7.1 — Single Sign-On (Authentik)

**As an** operator,  
**I want** a self-hosted SSO provider that gates access to all web UIs,  
**so that** I don't have to manage separate accounts for every service.

**Acceptance criteria:**
- Authentik deployed and healthy at `:9000`
- `AUTHENTIK_BOOTSTRAP_PASSWORD` generated at deploy time, persisted to platform.conf, displayed in Script 3 credentials summary
- `AUTHENTIK_SECRET_KEY` generated once and persisted (stable across redeploys — regenerating invalidates all sessions)
- Healthcheck at `/-/health/live/` (not `/-/health/`)
- Script 3 displays akadmin credentials and OIDC configuration steps
- Service: `authentik`

---

### Feature 7.2 — Secret Generation and Persistence

**As a** security-conscious operator,  
**I want** all secrets generated automatically and persisted across redeploys,  
**so that** I never have hardcoded passwords and services don't lose their sessions on re-deploy.

**Acceptance criteria:**
- Secrets generated in `persist_generated_secrets()`: `LITELLM_MASTER_KEY`, `LITELLM_UI_PASSWORD`, `POSTGRES_PASSWORD`, `REDIS_PASSWORD`, `AUTHENTIK_SECRET_KEY`, `AUTHENTIK_BOOTSTRAP_PASSWORD`, `ANYTHINGLLM_JWT_SECRET`, `ZEP_AUTH_SECRET`, `LETTA_SERVER_PASS`, `CODE_SERVER_PASSWORD`, `DIFY_INIT_PASSWORD`
- All generated with `openssl rand -hex N` or `openssl rand -base64` (cryptographically secure)
- Written to platform.conf via `update_conf_value()` on first run; subsequent runs read existing value (idempotent)
- No secret ever hardcoded in script source (`changeme` is not an acceptable default)
- Script 3 `--reconfigure <service>` resets a service's credentials, updates platform.conf, and restarts the container

---

### Feature 7.3 — Network Isolation

**As a** security-conscious operator,  
**I want** all services to communicate on an isolated Docker network with no direct internet exposure,  
**so that** attackers cannot reach internal services even if the reverse proxy is misconfigured.

**Acceptance criteria:**
- All services attached to tenant-specific Docker network (`${TENANT_ID}-network`)
- All host port bindings use `127.0.0.1:PORT:PORT` (not `0.0.0.0`)
- Only reverse proxy (80/443) exposed to external interfaces
- Every `build_*_deps()` function emits `networks:` block (missing networks block → service joins wrong bridge → DNS breaks)

---

## EPIC 8 — Monitoring & Operations

**Goal:** The operator has full visibility into service health, resource usage, and LLM cost — and can manage services from a single script.

---

### Feature 8.1 — Metrics and Dashboards

**As an** operator,  
**I want** Grafana dashboards showing service health, resource usage, and LLM costs,  
**so that** I can detect problems before they affect users.

**Acceptance criteria:**
- Prometheus deployed and scraping all containers
- Grafana deployed at configured port with Prometheus datasource pre-configured
- LiteLLM cost metrics available (LiteLLM exposes Prometheus metrics natively)
- Services: `grafana`, `prometheus`

---

### Feature 8.2 — Live Health Monitoring (Script 3)

**As an** operator,  
**I want** a single command that shows the health of every service,  
**so that** I can diagnose issues without running multiple docker commands.

**Acceptance criteria:**
- Script 3 `show_health_status()` prints 28-row table: service name, health state, container name, port
- Port-level health checks for 24 endpoints (separate from Docker healthcheck)
- DNS validation for configured domain
- LiteLLM API key live-test
- Script: `3-configure-services.sh`

---

### Feature 8.3 — Credential Management

**As an** operator,  
**I want** all credentials displayed in one place after deploy,  
**so that** I don't have to search through config files to log into services.

**Acceptance criteria:**
- Script 3 credentials summary includes credentials for every enabled web service: LiteLLM, Postgres, Redis, OpenWebUI, LibreChat, OpenClaw, AnythingLLM, Flowise, N8N, Dify, Authentik, Grafana, Code Server, Signalbot (QR link), Zep, Letta, Qdrant
- Script 2 post-deploy dashboard shows the same information immediately after deploy
- All credentials sourced from platform.conf (never hardcoded)
- URL format is domain-aware: `https://<subdomain>.<domain>` when Caddy active, `http://<IP>:<port>` otherwise

---

### Feature 8.4 — Service Reconfiguration (Credential Reset)

**As an** operator,  
**I want** to reset a service's credentials post-deploy without a full teardown,  
**so that** I can rotate passwords or recover from a compromised secret without rebuilding the stack.

**Acceptance criteria:**
- Script 3 `--reconfigure <service>` generates new credentials, updates platform.conf, and restarts the container
- Supported services: `openwebui`, `librechat`, `openclaw`, `dify`, `flowise`, `n8n`, `litellm`, `grafana`, `code-server`, `anythingllm`
- New credential printed to stdout after reset
- platform.conf updated atomically (no truncation)
- Container restarted and implicitly picks up new credentials from the env vars (compose must be regenerated on next full redeploy)
- Script: `3-configure-services.sh --reconfigure <service>`

---

### Feature 8.5 — Log Management

**As an** operator,  
**I want** to tail or audit logs for any service from a single command,  
**so that** I can diagnose problems without knowing the exact container name.

**Acceptance criteria:**
- `--logs <service>` tails the last N lines and follows (interactive); service name maps to `${TENANT_PREFIX}-<service>`
- `--log-lines N` controls how many lines to show (default 200)
- Dify special case: `--logs dify` shows logs for all three dify containers (dify, dify-api, dify-worker)
- `--audit-logs` scans all tenant containers for ERROR/FATAL in the last 60 seconds and prints a summary; only containers with errors are shown
- Script: `3-configure-services.sh --logs <service>` / `--audit-logs`

---

### Feature 8.6 — Backup Strategy

**As an** operator,  
**I want** to back up all platform data with one command, optionally on a schedule,  
**so that** I can recover from data loss or a failed EC2 instance without losing months of data.

**Acceptance criteria:**
- `--backup` creates a compressed tar archive of `${DATA_DIR}` excluding ingestion cache, rclone sync dir, and Ollama models (re-pullable)
- DBs (postgres, redis, mongodb, qdrant) are paused during archiving for consistency; unpaused immediately after
- Archive stored at `${DATA_DIR}/backups/<tenant>-backup-<timestamp>.tar.gz`
- Archive size printed after creation
- `--schedule "<cron>"` adds a system crontab entry; existing entry for the tenant is replaced (idempotent)
- Script: `3-configure-services.sh --backup [--schedule "<cron>"]`

---

## EPIC 9 — Alerting & Communications

**Goal:** The platform can send alerts and notifications via Signal messenger so operators receive critical events on their phones.

---

### Feature 9.1 — Signal Messenger Integration

**As an** operator,  
**I want** to receive platform alerts via Signal,  
**so that** I am notified of critical events even when not actively monitoring.

**Acceptance criteria:**
- Signalbot deployed and healthy at configured port
- REST API available at `/v1/` for sending messages
- Phone number pairing documented in README and Script 3 instructions
- N8N workflows can trigger Signalbot via HTTP request node
- Healthcheck at `/v1/about` (not `/`)
- `start_period: 60s` (signal-cli daemon takes ~26s to start)
- Service: `signalbot`

---

## EPIC 10 — Development Environment

**Goal:** Developers can write and test code directly in the browser without setting up a local development environment.

---

### Feature 10.1 — Browser IDE (Code Server)

**As a** developer,  
**I want** a browser-based VS Code instance with access to the platform's data directories,  
**so that** I can develop AI applications, inspect logs, and edit configs without SSH.

**Acceptance criteria:**
- Code Server deployed and healthy at configured port
- Workspace mounted at `${DATA_DIR}` (full access to platform data)
- Password set in platform.conf and displayed in Script 3 credentials summary
- Service: `code-server`

---

### Feature 10.2 — AI Code Completion (Continue.dev)

**As a** developer,  
**I want** AI code completion in Code Server backed by models running locally,  
**so that** I get GitHub Copilot-quality completions without sending code to external services.

**Acceptance criteria:**
- Continue.dev extension or server deployed when enabled
- Configured to use LiteLLM as the code completion endpoint
- Ollama local models available for completion (low latency, no cost)
- Service: `continue-dev`

---

## EPIC 11 — Model Management

**Goal:** Users can configure and manage Ollama and external LLM models through an interactive interface without manual configuration file editing.

---

### Feature 11.1 — Interactive Model Configuration

**As an** operator,  
**I want** to configure Ollama and external LLM models through an interactive interface,  
**so that** I can easily switch between different models and providers without editing configuration files.

**Acceptance criteria:**
- Interactive menu for model configuration (Script 3 --configure-models)
- Ollama model size selection (Small/Medium/Large) or custom model names
- External LLM provider configuration (Groq, OpenAI, Anthropic, Google)
- API key management with secure input
- Template saving for model configurations
- Automatic re-deployment with new model settings
- Validation of model availability before deployment

---

### Feature 11.2 — Database Recovery Automation

**As an** operator,  
**I want** automatic database corruption detection and recovery,  
**so that** Script 2 re-runs succeed without manual intervention.

**Acceptance criteria:**
- MongoDB corruption detection and automatic recovery
- Dify database migration issue detection and recovery
- --flush-dbs flag for database-only recovery
- Container and model preservation during database recovery
- Graceful error handling with informative logs

---

## EPIC 12 - Search Integration

**Goal:** Users have access to privacy-respecting search capabilities that augment AI responses without external API dependencies.

---

### Feature 12.1 - Privacy-Respecting Search Engine

**As an** operator,  
**I want** a local search engine that provides web search capabilities without external dependencies,  
**so that** AI applications can augment responses with current web information while maintaining privacy.

**Acceptance criteria:**
- SearXNG deployed automatically in all stack presets (except custom)
- Subdomain routing via search.${BASE_DOMAIN}
- Auto-generated secret key for security
- Integration with LiteLLM for search-augmented responses
- Health checks and monitoring in Script 3
- Configurable search engines and preferences
- No external API dependencies for search functionality

---

## EPIC 13 - Hardware Detection & Optimization

**Goal:** Users receive intelligent deployment recommendations based on detected hardware capabilities for optimal performance.

---

### Feature 13.1 - GPU/CPU Detection and Deployment Guidance

**As an** operator,  
**I want** the system to automatically detect my hardware capabilities and provide deployment recommendations,  
**so that** I can choose the right models and configuration for optimal performance.

**Acceptance criteria:**
- NVIDIA GPU detection with VRAM capacity reporting
- AMD ROCm GPU detection and compatibility assessment
- CPU-only detection with efficiency recommendations
- Hardware-aware model size recommendations
- Deployment mode confirmation with performance guidance
- GPU/CPU variables written to platform.conf for Script 2 usage
- Upgrade recommendations for CPU-only deployments

---

## STORY MAP SUMMARY

```
Epic 1 — Lifecycle      Script 0 → Script 1 → Script 2 → Script 3
                        Script 3 management: --ingest, --reconfigure, --backup,
                          --logs, --audit-logs, --litellm-routing, --ollama-*
Epic 2 — LLM Routing    ollama → litellm → (all UIs)
                        Post-deploy: --ollama-pull/remove/list, --litellm-routing
Epic 3 — Memory         postgres+pgvector → zep, letta, mem0
                        qdrant / weaviate / chroma / milvus
Epic 4 — Web UIs        openwebui, anythingllm, openclaw, librechat
Epic 5 — Automation     n8n, flowise, dify (3 containers: web + api + worker)
Epic 6 — Ingestion      rclone (gdrive, INI config) → ingestion/
                        Script 3 --ingest: embed via LiteLLM → upsert Qdrant
Epic 7 — Identity       authentik → OIDC → all UIs
                        secret generation → platform.conf (11 auto-generated secrets)
                        Script 3 --reconfigure: live credential reset
Epic 8 — Monitoring     prometheus → grafana
                        script 3 health table + port checks + audit-logs
                        script 3 --backup: tar + cron scheduling
Epic 9 — Alerting       signalbot → Signal messenger
Epic 10 — Dev           code-server, continue-dev
Epic 11 — Model Management Script 3 --configure-models, --flush-dbs flag
                        Interactive Ollama/external LLM configuration, template saving
                        Automatic database corruption detection and recovery
Epic 12 — Search        SearXNG privacy search engine, subdomain routing
                        Auto-generated secrets, health checks, LiteLLM integration
Epic 13 — Hardware       GPU/CPU detection, deployment guidance, model recommendations
                        Hardware-aware configuration, performance optimization
```

---

*Version: 2.4.0 | Last Updated: 2026-04-20*

## IMPLEMENTATION STATUS UPDATES

### Completed Features (2026-04-20)
- **Mammouth AI Multi-Model Proxy**: Single API key for Claude/Gemini/GPT via Mammouth; 3 model entries auto-generated in LiteLLM config (`claude-sonnet-4-6`, `gemini-2.5-flash`, `gpt-4o`)
- **URL Routing Mode**: Script 1 wizard adds subdomain/port/path selection; `URL_ROUTING_MODE` written to platform.conf; all URL helpers in Scripts 1, 2, 3 respect it
- **Dual Caddy/NPM Flag**: Both `CADDY_ENABLED` and `ENABLE_CADDY` written to platform.conf to prevent URL helpers from defaulting to IP:port when proxy is active
- **Stale Model Name Fixes**: Anthropic `claude-3-sonnet-20240229` → `claude-3-5-sonnet-20241022`; Google `gemini-pro` → `gemini-1.5-flash`; Groq model names updated to current names
- **Groq model_name format**: Fixed to `groq/${model}` (was `${model}-groq`) in Script 2
- **Ollama RAM management**: `OLLAMA_KEEP_ALIVE=5m`, `OLLAMA_MAX_LOADED_MODELS=1` prevent model hoarding on low-RAM hosts
- **Dify alembic stamp recovery**: Replaced wipe-schema recovery with alembic version stamp (`6b5f9f8b1a2c`) — preserves data on re-deploy
- **Signal QR Code Caddy Route**: `signal.${BASE_DOMAIN}` Caddy route ensures QR pairing URL is browser-accessible
- **SearXNG + rclone in health table**: Script 3 `show_health_status()` now includes SearXNG and rclone rows (previously omitted)
- **OpenWebUI QDRANT_URI**: Fixed `QDRANT_URL` → `QDRANT_URI` (current env var name in OpenWebUI)
- **Signalbot healthcheck**: Fixed `wget` → `curl` (wget not in image)
- **26/26 containers healthy**: All services verified healthy on datasquiz tenant (2026-04-20)
- **8/8 LiteLLM endpoints healthy**: Ollama (×2), Groq (×2), OpenRouter, Mammouth Claude/Gemini/GPT

### Completed Features (2026-04-17)
- **MongoDB Corruption Recovery**: Automatic detection and recovery implemented in Script 2
- **Dify Database Recovery**: Automatic detection and recovery of database migration issues
- **--flush-dbs Flag**: Database-only recovery while preserving containers and models
- **P14 Model Download Cost Optimization**: Models download once, preserved on re-runs, cleared with --flushall
- **Full 25-Container Deployment**: All services healthy and operational
- **Dynamic Model Validation**: Groq, OpenAI, and Ollama models validated before configuration
- **Interactive Model Management**: Script 3 --configure-models for Ollama and external LLM configuration
- **Template Saving**: Model configurations saved as reusable templates
- **SearXNG Integration**: Privacy-respecting search engine deployed across all stacks
- **GPU/CPU Detection**: Hardware-aware deployment guidance and model recommendations
- **Latest Ollama Models**: Llama 3.2, Qwen 2.5, Gemma 4, Deepseek Coder V2 added
- **Custom Model Entry**: Support for any model from ollama.com/library with variants
- **AI Development Tools Integration**: Code Server + Continue.dev with LiteLLM proxy
- **Mem0 Removal**: Deprecated service completely removed from codebase
- **Multi-Provider AI Routing**: All services properly connected to LiteLLM proxy
- **Gemma 4 Model Support**: Added Google's latest multimodal model to Ollama selection
- **GPU/CPU Detection**: Hardware detection and deployment guidance in Script 1
- **Self-Healing Database Recovery**: Auto-detects and recovers from Dify/LiteLLM migration failures
- **Stable Credential Management**: Script 1 generates all credentials; stable across re-deploys
- **Script 3 Database Flush**: User-triggered database recovery via --flushall option
- **Enhanced Error Handling**: Robust deployment with automatic failure recovery
- **Code Server LiteLLM Integration**: Full AI development environment with LiteLLM proxy
- **Continue.dev Integration**: VS Code extension configured for LiteLLM and selected models
- **LiteLLM Admin UI**: Web interface for model management and API testing
- **Complete Service Integration**: All AI services properly connected to LiteLLM proxy
- **Dify Database Recovery**: Enhanced SQLAlchemy error handling and schema cleanup
- **Script 2 Automatic Model Download**: Deployment engine automatically pulls all configured Ollama models without manual intervention
- **Model Loading Optimization**: Automatic model downloading and availability verification during deployment
- **Integrated Monitoring Platform**: Complete observability stack with Prometheus + Grafana
- **Automatic Service Discovery**: Zero-configuration monitoring for all enabled services
- **Comprehensive Service Coverage**: Ollama, LiteLLM, Dify, Code Server, N8N, Flowise, AnythingLLM, OpenWebUI, LibreChat, OpenClaw, Authentik, Qdrant, PostgreSQL, Redis, MongoDB
- **Health Endpoint Monitoring**: Service-specific health checks with configurable intervals
- **Resource Usage Tracking**: Container CPU, memory, and performance metrics
- **Request Rate Monitoring**: LiteLLM API request rates and response times
- **Grafana Dashboard Provisioning**: Pre-configured AI Platform Overview dashboard
- **Script 3 Dynamic Model Lookup**: Mission Control provides --ollama-latest to fetch 30 real-time models from ollama.com/api/tags
- **Batch Model Input**: Comma-separated model processing for multiple model deployment (e.g., 'gemma4:31b,llama3.2:3b')
- **Interactive Model Management**: Live model selection with automatic platform.conf and LiteLLM configuration updates
- **Success Tracking**: Batch operation feedback with X/Y models successful reporting
- **Modular Model Deployment**: Extensible design for filtering, searching, and custom model entry
- **Latest Model Availability**: gemma4:31b and other newest models available in all selection methods
- **Subdomain Architecture**: Multi-tenant support with subdomain routing and internal port mapping
- **Port Isolation**: Tenant-specific port ranges prevent conflicts between deployments
- **Internal Service Routing**: Subdomain access routes to different internal ports while keeping 80/443 open
- **GPU-Accelerated Deployment**: NVIDIA L4 GPU support on g6.2xlarge with 24GB VRAM
- **GPU Memory Management**: OLLAMA_GPU_LAYERS=auto optimizes VRAM usage for large models
- **GPU Health Monitoring**: Prometheus/Grafana GPU metrics and alerting
- **GPU Fallback Support**: Graceful CPU fallback when GPU unavailable
- **Multi-GPU Ready**: Architecture supports multiple GPU configurations
- **Prometheus Dynamic Configuration**: Automatic service monitoring based on enabled components
