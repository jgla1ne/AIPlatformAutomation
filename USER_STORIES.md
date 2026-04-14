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
- All Docker volumes removed
- Tenant data directory removed (`/mnt/<tenant>`)
- Docker images scoped to tenant removed (by label and name prefix)
- Docker daemon stopped if data-root is on EBS (prevents block device busy error on re-format)
- EBS unmounted before directory removal
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
- Validates domain format and DNS resolution
- Validates EBS device exists before formatting
- Stack presets (minimal / development / standard / full / custom) reduce decision fatigue
- Dependency enforcement is automatic and non-overridable (Zep/Letta force Postgres + LiteLLM; LibreChat forces MongoDB)
- Memory layer prompt shown only for presets that support it (standard, full, custom)
- All inputs written to `platform.conf` — no other files touched
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
- Post-deploy dashboard printed with all service URLs and credentials
- Script exits non-zero if any enabled service fails health checks within timeout
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
- Script 1 wizard collects keys for: OpenAI, Anthropic, Google, Azure, Groq, Mistral, Cohere
- All keys written to platform.conf
- Script 2 injects keys into `litellm_config.yaml` only for providers where a key was supplied
- No key written to docker-compose.yml in plaintext (all via LiteLLM proxy)
- Services: `litellm`

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

### Feature 3.3 — Persistent AI Memory Layer

**As an** AI developer,  
**I want** a persistent, structured memory layer that stores and retrieves facts across AI interactions,  
**so that** applications can maintain long-term user context without building custom memory logic.

**Acceptance criteria:**
- Mem0 deployed and healthy
- API accessible within Docker network
- Service: `mem0`

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
- `CONSOLE_API_URL` in the web container is the **browser-accessible** dify-api URL (Caddy subdomain when active: `https://dify-api.${BASE_DOMAIN}`) — not `http://127.0.0.1:5001` which resolves inside the wrong container
- Caddy route `dify-api.${BASE_DOMAIN}` auto-generated by Script 2
- `DIFY_INIT_PASSWORD` generated and persisted; Script 3 `configure_dify()` calls `/console/api/setup` on port 5001 (not the web port)
- Dify-web healthcheck uses `bash /dev/tcp/127.0.0.1/3000` (TCP socket — avoids `$(hostname)` which expands to EC2 host at heredoc write time)
- `start_period: 120s` for dify-web, 90s for dify-api, 120s for dify-worker
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
```

---

*Version: 2.0.0 | Last Updated: 2026-04-14*
