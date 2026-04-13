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
└──────────────────┬───────────────────────────────┘
                   │ Internal Docker network
                   │ (${DOCKER_NETWORK}  e.g. datasquiz-network)
      ┌────────────┼───────────────────────┐
      │            │                       │
      ▼            ▼                       ▼
┌──────────┐ ┌──────────────┐     ┌──────────────────┐
│ LiteLLM  │ │   Web UIs    │     │   Automation     │
│  Proxy   │ │              │     │                  │
│  (unified│ │ OpenWebUI    │     │  N8N             │
│  LLM API)│ │ OpenClaw     │     │  Flowise         │
│          │ │ AnythingLLM  │     │  Dify            │
└────┬─────┘ │ LibreChat    │     └──────┬───────────┘
     │       └──────┬───────┘            │
     │              │                    │
     ▼              ▼                    ▼
┌──────────┐ ┌──────────────┐     ┌──────────────────┐
│  Ollama  │ │  Authentik   │     │  PostgreSQL+pgvec │
│  (local  │ │  (SSO/IdP)   │     │  Redis            │
│  models) │ └──────────────┘     │  MongoDB          │
└──────────┘                      └──────────────────┘
      │
      ▼
┌──────────────────────────────────────┐
│  Memory / Knowledge Layer            │
│  Zep CE   — Conversation memory      │
│  Letta    — Stateful agent runtime   │
│  Mem0     — Persistent AI memory     │
│  Qdrant / Weaviate / Chroma / Milvus │
└──────────────────────────────────────┘
      │
      ▼
┌─────────────────┐     ┌──────────────────┐
│  Monitoring     │     │  Development     │
│  Grafana        │     │  Code Server     │
│  Prometheus     │     │  Continue.dev    │
└─────────────────┘     └──────────────────┘
      │
      ▼
┌──────────────────────────────────────────┐
│  Alerting / Comms                        │
│  Signalbot (Signal messenger REST API)   │
└──────────────────────────────────────────┘
```

> **LibreChat** is deployed when enabled. MongoDB is co-deployed automatically as its backing store (LibreChat does not support PostgreSQL as its chat store). The LibreChat RAG API uses pgvector (Postgres) for document embeddings.

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

**Expected outcome:** `Script 1 Complete ✓` banner. `platform.conf` written with all `ENABLE_*`, port, secret, and domain variables. EBS mounted and Docker pointing at it. Ready for Script 2.

**Key variables written to platform.conf:**
```
TENANT_ID, TENANT_PREFIX, BASE_DIR, DATA_DIR, CONFIG_DIR
DOMAIN, BASE_DOMAIN, TLS_MODE
ENABLE_<SERVICE>=true/false  (one per service)
<SERVICE>_PORT=<preferred>   (Script 2 may allocate different actual port)
PROXY_TYPE, ENABLE_CADDY, ENABLE_NPM
PUID, PGID
```

---

### Script 2 — Deployment Engine

**Purpose:** Read `platform.conf`, generate all configs, allocate ports, deploy all containers, and wait until every enabled service is healthy.

**Prerequisites:** Non-root. Docker group member. Script 1 must have run successfully (EBS mounted, `platform.conf` present, Docker data-root on EBS).

**Usage:**
```bash
bash scripts/2-deploy-services.sh <tenant_id>
```

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
9. `wait_for_all_health()` — polls every enabled service health endpoint with per-service timeouts; creates Letta's dedicated PostgreSQL database + pgvector extension after Postgres healthy; restarts Letta after DB creation; proactively creates Zep watermill tables to prevent startup error loop
10. `trigger_initial_rclone_sync()` — restarts the rclone container immediately after all health checks pass so the first Google Drive sync fires without waiting for the poll interval
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
```

**Inputs:**
- `/mnt/<tenant>/config/platform.conf` (primary)
- `/mnt/<tenant>/.configured/port-allocations` (takes precedence for ports)

Port-allocations file is sourced after platform.conf so any Script 2 conflict-resolved port always wins.

**Execution:**
1. Sources both files
2. Calls `configure_<service>()` for each enabled service (guards against container non-existence)
3. Displays full health status table (28 service rows)
4. Runs port health checks (24 endpoints)
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
| OpenClaw | URL, username, password |
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

**Domain-aware URL logic (both `show_credentials()` and access URL section):**
```
if CADDY_ENABLED=true or NPM_ENABLED=true and DOMAIN is set:
    URL = https://<subdomain>.<DOMAIN>       ← subdomain routing, no port
else:
    URL = http://<server-LAN-IP>:<port>      ← direct IP:port
```

Every `_url <subdomain> <port>` call in Script 3 applies this logic. Caddy is configured for subdomains — path-based URLs (`https://domain/service`) are NOT used anywhere.

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
| | Mem0 | `mem0ai/mem0` | Persistent AI memory layer |
| **Identity** | Authentik | `ghcr.io/goauthentik/server` | SSO / OIDC provider |
| **Monitoring** | Grafana | `grafana/grafana` | Dashboards |
| | Prometheus | `prom/prometheus` | Metrics scraping |
| **Dev** | Code Server | `codercom/code-server` | Browser VS Code |
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
| Dify-web | `wget` | `wget -q --spider http://localhost:3000` |
| Dify-api | `curl` | `curl -sf http://localhost:5001/health` |
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
| Dify-api | — | `/health` |
| Authentik | `/-/health/` (404) | `/-/health/live/` |
| LiteLLM | `/health` | `/health/liveliness` |
| LibreChat | `/api/health` (404) | `/health` |
| OpenClaw | `/api/health` (404) | `/health` |
| Zep CE | `/` (404) | `/healthz` |

### Slow-Starting Services — `start_period` Required

| Service | `start_period` | Reason |
|---|---|---|
| LiteLLM | 600s | Downloads Prisma binaries + handles migration conflicts on re-deploy (~6 min) |
| OpenWebUI | 120s | DB migrations on first run |
| Zep CE | 60s | Postgres migrations + hnsw index creation |
| N8N | 60s | DB init |
| Flowise | 60s | SQLite init |
| Dify-web | 60s | Next.js hydration |
| Dify-api | 90s | DB migrations + Celery init |
| Dify-worker | 120s | Celery worker startup |
| Authentik | 60s | Migration runner |
| Signalbot | 60s | signal-cli daemon takes ~26 s |
| AnythingLLM | 60s | DB migrations |
| Letta | 120s | Postgres migration runs on startup; dedicated `_letta` DB must be created before container starts |

`wait_for_all_health()` timeouts: litellm 900s (600s start_period + migration time), openwebui 180s, authentik 180s, letta 300s.

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

### OpenWebUI — Correct Variable Names

`WEBUI_SECRET_KEY` (not `WEBUI_SECRET`). Container listens on port **8080** (not 3000). Port mapping: `"127.0.0.1:${OPENWEBUI_PORT}:8080"`.

### OpenClaw — Dynamic Port and Config Mount

OpenClaw reads `OPENCLAW_PORT` from its environment and binds to **that port** inside the container (not a fixed 3001). Correct port mapping: `"127.0.0.1:${OPENCLAW_PORT}:${OPENCLAW_PORT}"`. Caddy/NPM proxy must also target `${TENANT_PREFIX}-openclaw:${OPENCLAW_PORT}`.

OpenClaw writes its config to `/.openclaw` (container root). This path must be explicitly bind-mounted:
```yaml
volumes:
  - ${DATA_DIR}/openclaw/data:/app/data
  - ${DATA_DIR}/openclaw/config:/.openclaw
```
Without the second mount the container crashes on startup with permission denied.

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

### Zep — Watermill Tables Must Be Pre-Created

Zep runs `CREATE TABLE IF NOT EXISTS watermill_*` at startup, but if Postgres is slow to accept connections during the first initialization the tables may not be created. Zep then enters an error loop (`ERROR: relation "watermill_offsets_message_token_count" does not exist`) even though it reports healthy (the healthcheck only tests TCP connectivity).

Script 2 proactively creates the two watermill tables after Zep is healthy, then restarts Zep so it gets a clean startup with the tables present:

```bash
# watermill_message_token_count and watermill_offsets_message_token_count
# must exist before Zep's subscriber goroutine starts reading
docker exec postgres psql -U user -d db -c "CREATE TABLE IF NOT EXISTS watermill_message_token_count ..."
docker restart zep
```

### LiteLLM — Config Flag Required

LiteLLM's image default entrypoint does NOT automatically load `/app/config.yaml`. The `--config` flag must be explicit:

```yaml
command: ["--config", "/app/config.yaml", "--port", "4000"]
```

Without this, LiteLLM starts with 0 models registered (model list API returns empty array) and all routing attempts fail.

### rclone — Config Format and service-account.json Mount

The rclone config file must be INI-format, not a raw JSON service account file. Script 2 copies `GDRIVE_CREDENTIALS_FILE` to `${DATA_DIR}/rclone/service-account.json` and mounts it at `/credentials/service-account.json` inside the container:

```ini
[gdrive]
type = drive
scope = drive.readonly
service_account_file = /credentials/service-account.json
```

The service account must have the target Google Drive folder explicitly shared with its email (`service-account@project.iam.gserviceaccount.com`). Service accounts have no access to Drive by default.

After all health checks pass, Script 2 calls `trigger_initial_rclone_sync()` which restarts the rclone container to kick off an immediate sync — files appear in `${DATA_DIR}/ingestion/` without waiting for the first poll interval.

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

OpenClaw's gateway CORS check rejects requests from `https://openclaw.${BASE_DOMAIN}` unless explicitly allowed. Script 2 applies a two-layer fix:

1. Env vars in compose: `CORS_ORIGIN=*`, `ALLOWED_ORIGINS=*`, `GATEWAY_CONTROL_UI_ALLOWED_ORIGINS=*`
2. Config JSON written by `prepare_data_dirs()` at `${DATA_DIR}/openclaw/config/config.json` (mounted at `/.openclaw/config.json`):
```json
{
  "gateway": {
    "controlUi": {
      "allowedOrigins": ["https://openclaw.yourdomain.net", "*"]
    }
  }
}
```

### Code Server — Password Generated and Persisted

The default `changeme` password was replaced. Script 2 now generates a random password via `openssl rand -base64 16` and writes it to `platform.conf` via `persist_generated_secrets()`. The password is shown in the post-deploy dashboard credentials block and at `code.${BASE_DOMAIN}`.

### Dify — Full Stack Required (web + api + worker)

Deploying only `langgenius/dify-web` causes the browser to loop forever on `/install`. The full stack requires three containers using two images:

| Container | Image | Command | Port |
|---|---|---|---|
| `dify` | `langgenius/dify-web:latest` | (default) | 3000 |
| `dify-api` | `langgenius/dify-api:latest` | `api` | 5001 |
| `dify-worker` | `langgenius/dify-api:latest` | `worker` | — |

`CONSOLE_API_URL` in the web container must be the **browser-accessible** URL of dify-api. When Caddy is active: `https://dify-api.${BASE_DOMAIN}`. Script 2 generates a `dify-api.${BASE_DOMAIN}` Caddy route automatically.

### Milvus — Three-Container Stack

Milvus standalone requires three containers:
- `milvus-etcd` — metadata store (`quay.io/coreos/etcd:v3.5.5`)
- `milvus-minio` — object store (`minio/minio:latest`)
- `milvus` — vector engine (`milvusdb/milvus:v2.4.0`)

`milvus` depends on both sidecars. Data dirs: `${DATA_DIR}/milvus/etcd`, `${DATA_DIR}/milvus/minio`, `${DATA_DIR}/milvus/data`.

### Authentik — Bootstrap and Secret Stability

`AUTHENTIK_BOOTSTRAP_PASSWORD` and `AUTHENTIK_BOOTSTRAP_EMAIL` are generated by Script 2 at deploy time and written to docker-compose.yml. Script 2 also appends them to platform.conf via `update_conf_value()`.

`AUTHENTIK_SECRET_KEY` must be **stable across redeploys** — regenerating it invalidates all Authentik sessions and tokens. Script 2's `persist_generated_secrets()` generates it once and writes it to platform.conf; subsequent runs read the existing value.

### Reverse Proxy — Caddy vs NPM

Two options, mutually exclusive — only one may be enabled per deployment:

| Proxy | Image | Config | Admin |
|---|---|---|---|
| **Caddy** | `caddy:2-alpine` | Caddyfile auto-generated by Script 2; all routes pre-configured | No admin UI — routes from Caddyfile |
| **Nginx Proxy Manager** | `jc21/nginx-proxy-manager:latest` | No config generated; routes managed via web UI at `:81` | `admin@example.com` / `changeme` (change on first login) |

NPM is more flexible (GUI route management, per-route SSL, access lists). Caddy requires no manual post-deploy configuration.

**Critical:** `configure_proxy()` in Script 1 must set `ENABLE_CADDY="true"` **or** `ENABLE_NPM="true"` — not just `PROXY_TYPE`. Script 2 guards on `CADDY_ENABLED` and `NPM_ENABLED` (which are set from these vars).

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
| `minimal` | Postgres, Redis, Ollama, LiteLLM, OpenWebUI, Qdrant |
| `development` | Minimal + Code Server |
| `standard` | Development + N8N, Flowise, Grafana, Prometheus + **memory layer prompt** |
| `full` | Standard + OpenClaw, AnythingLLM, Dify, Authentik, SignalBot, LibreChat + **memory layer prompt** |
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
- [ ] Is Dify deployed as 3 containers (web + api + worker)? Is `CONSOLE_API_URL` set to the public dify-api URL?
- [ ] Does Signalbot have a Caddy route (`signal.${BASE_DOMAIN}`)? Is the QR link URL printed in the dashboard?
- [ ] Does the rclone config reference `service_account_file = /credentials/service-account.json` (not `credentials.json`)?
- [ ] Does `trigger_initial_rclone_sync()` fire after `wait_for_all_health()` in main()?
- [ ] Do Script 3 URLs use `https://subdomain.${BASE_DOMAIN}` when Caddy active (not path-based `https://${BASE_DOMAIN}/service` and not IP:port)?
- [ ] Does `show_credentials()` display login credentials for every enabled web service?
- [ ] Does `configure_dify()` call `/console/api/setup` on dify-api port (5001), not on dify-web port?

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

### LiteLLM P1001 (can't reach Postgres)

The litellm service is on the wrong Docker network. Every `build_*_deps()` function must emit `networks: - ${DOCKER_NETWORK}` alongside its `depends_on:` block.

### LiteLLM P3005 (database schema not empty)

Set `LITELLM_MIGRATION_DIR: /tmp/litellm-migrations` in the compose environment block.

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
| **Script 2** — Deployment Engine | Production ready | Heredoc compose generation, port allocator, secret persistence, Letta DB creation, post-deploy dashboard |
| **Script 3** — Mission Control | Production ready | Sources port-allocations (takes precedence), 28-service health table, domain-aware URLs, credentials summary |

---

*Version: 5.1.0 | Last Updated: 2026-04-13 | Architecture: 4 scripts, ~30 services (Dify 3-container stack), single-tenant per EBS volume*
