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
│  LLM API)│ │ OpenClaw*    │     │  Flowise         │
│          │ │ AnythingLLM  │     │  Dify            │
└────┬─────┘ └──────┬───────┘     └──────┬───────────┘
     │              │                    │
     ▼              ▼                    ▼
┌──────────┐ ┌──────────────┐     ┌──────────────────┐
│  Ollama  │ │  Authentik   │     │  PostgreSQL+pgvec │
│  (local  │ │  (SSO/IdP)   │     │  Redis            │
│  models) │ └──────────────┘     │  MongoDB          │
└──────────┘                      └──────────────────┘
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

> **LibreChat** is deployed when enabled. MongoDB is co-deployed automatically as its backing store. No manual intervention needed.

### All Services — Full Stack

| Layer | Service | Image | Notes |
|---|---|---|---|
| **Infrastructure** | PostgreSQL | `pgvector/pgvector:pg15` | Shared DB + vector store (pgvector ext built-in); used by LiteLLM, Dify, Authentik, LibreChat RAG API |
| | Redis | `redis:7-alpine` | Session / queue store |
| | MongoDB | `mongo:7` | Required by LibreChat; deployed only when LibreChat is enabled |
| **LLM** | Ollama | `ollama/ollama` | Local model runner |
| | LiteLLM | `ghcr.io/berriai/litellm:main-stable` | Unified LLM proxy + cost tracking |
| | Bifrost | `bifrost` | Optional alt gateway |
| **Web UIs** | OpenWebUI | `ghcr.io/open-webui/open-webui:main` | Primary chat UI |
| | AnythingLLM | `mintplexlabs/anythingllm` | RAG-first UI |
| | OpenClaw | `alpine/openclaw:latest` | |
| | LibreChat | `ghcr.io/danny-avila/librechat:latest` | Requires MongoDB (co-deployed automatically); LLMs routed via LiteLLM |
| | LibreChat RAG API | `registry.librechat.ai/danny-avila/librechat-rag-api-dev-lite:latest` | Document RAG sidecar; embeddings via LiteLLM, vector store via pgvector |
| **Vector DB** | Qdrant | `qdrant/qdrant` | Optional; LibreChat RAG API uses pgvector (Postgres) by default |
| | Weaviate | `semitechnologies/weaviate` | Optional |
| | ChromaDB | `chromadb/chroma` | Optional |
| **Automation** | N8N | `n8nio/n8n` | Workflow orchestration |
| | Flowise | `flowiseai/flowise` | Low-code AI chains |
| | Dify | `langgenius/dify-web` | LLM app builder (web frontend only) |
| **Identity** | Authentik | `ghcr.io/goauthentik/server` | SSO / OIDC provider |
| **Monitoring** | Grafana | `grafana/grafana` | Dashboards |
| | Prometheus | `prom/prometheus` | Metrics scraping |
| **Dev** | Code Server | `codercom/code-server` | Browser VS Code |
| **Alerting** | Signalbot | `bbernhard/signal-cli-rest-api` | Signal messenger API |
| **Memory** | Zep CE | `ghcr.io/getzep/zep:latest` | Long-term conversation memory; backed by Postgres + pgvector, embeddings via LiteLLM |
| | Letta | `letta-ai/letta:latest` | Stateful agent memory server (MemGPT); backed by Postgres, LLM via LiteLLM |

---

## FOUR-SCRIPT ARCHITECTURE

```
Script 0 — Complete Cleanup
    Stops and removes all containers, images, volumes, network, data directory,
    and EBS mount for a named tenant. Requires typed confirmation ("DELETE <tenant>").
    Requires root.

Script 1 — Setup Wizard  (interactive, non-root)
    Collects all configuration interactively: tenant identity, domain, EBS storage,
    stack preset, service selection, API keys, ports, TLS mode.
    Writes a single platform.conf — the one source of truth for the entire platform.
    Does NOT touch Docker.

Script 2 — Deployment Engine  (non-root, Docker group)
    Sources platform.conf. Generates docker-compose.yml (heredoc blocks only),
    Caddyfile, litellm_config.yaml, and auxiliary configs.
    Allocates ports (resolving conflicts), deploys all containers,
    waits for health checks.
    Writes resolved ports to .configured/port-allocations and writes
    runtime-generated secrets (e.g. AUTHENTIK_BOOTSTRAP_PASSWORD) back to
    platform.conf so Script 3 can display them.

Script 3 — Mission Control  (non-root, Docker group)
    Sources platform.conf and .configured/port-allocations (port-allocations takes
    precedence for any conflict-resolved ports).
    Calls each service's configure_*() function, displays credentials, runs port
    health checks, DNS validation, and API key live-tests.
```

### Data Flow

```
Script 1 ──writes──► platform.conf
                          │
Script 2 ──reads──────────┘
         ──writes──► docker-compose.yml
                  ──writes──► .configured/port-allocations
                  ──writes──► platform.conf  (runtime secrets only)
                  ──writes──► litellm_config.yaml, Caddyfile, etc.
                  ──starts──► all containers (healthy)
                          │
Script 3 ──reads──────────┘ (platform.conf + port-allocations)
         ──calls──► configure_*() per service
         ──displays──► credentials summary
         ──verifies──► port health, DNS, API keys
```

### Port Resolution

Script 1 stores **preferred** ports in platform.conf. Script 2's `allocate_host_port()` walks forward from the preferred port until it finds an unclaimed value within the current run. Results are stored in `.configured/port-allocations` as `SERVICE_HOST_PORT="N"`. Script 3 sources this file after platform.conf, so the actual allocated ports always win.

Example with datasquiz (OPENWEBUI_PORT=3000, FLOWISE_PORT=3000 — same preference):
- openwebui → 3000 (first-served)
- flowise → 3001 (auto-incremented)
- dify → 3002
- grafana → 3003
- anythingllm → 3004

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
Most services run as `user: "${PUID}:${PGID}"`. Exceptions (must run as root):
- **LiteLLM** — Prisma writes baseline migrations to Python package directories at startup.
- **OpenWebUI** — writes `.webui_secret_key` to `/app/backend/` (image-internal path).
- **Letta** — writes agent state to `/root/.letta` (image-internal path).

> **LibreChat** runs as `node` (uid 1000), NOT root. Its data dirs need `chmod 777` — see directory permissions table below.

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
| Dify-web | `wget` | `wget -q --spider http://$(hostname):3000` (binds to bridge IP, not localhost) |
| Authentik | `python3` | `python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:9000/-/health/live/')"` |
| Flowise | `curl` | `curl -f http://localhost:3000/api/v1/ping` |
| LibreChat | `wget` | `wget -q --spider http://0.0.0.0:3080/health` (binds to 0.0.0.0; `/health` not `/api/health`) |
| LibreChat RAG API | `python3` (no curl/wget) | `python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"` |
| OpenClaw | `curl` | `curl -f http://localhost:${OPENCLAW_PORT}/health` (port dynamic — see quirk below) |
| Signalbot | `curl` | `curl -sf http://localhost:8080/v1/about` |
| Zep CE | `bash` (no curl/wget) | `["CMD", "bash", "-c", "echo > /dev/tcp/localhost/8000"]` |
| Letta | `curl` | `curl -f http://localhost:8283/v1/health` |

> **Dify-web** (Next.js) binds to the container's bridge network IP, not `127.0.0.1`. `wget http://localhost:3000` always returns connection refused. Use `http://$(hostname):3000` (escaped in heredoc as `\$(hostname)`).

### Correct Health Endpoints

| Service | Wrong | Correct |
|---|---|---|
| Qdrant | `/health` (404) | `/healthz` |
| Dify-web | `/health` (404) | `/apps` |
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
| Authentik | 60s | Migration runner |
| Signalbot | 60s | signal-cli daemon takes ~26 s |
| AnythingLLM | 60s | DB migrations |

`wait_for_all_health()` timeouts to match: litellm 900 s (600 s start_period + migration time on re-deploy), openwebui 180 s, authentik 180 s.

### Directory Permissions

Services running as internal UIDs (not PUID:PGID) cannot write to host-side data directories owned by 1001:1001. Fix with `chmod 777` **before** container start:

| Service | Directory | Reason |
|---|---|---|
| Qdrant | `${DATA_DIR}/qdrant` | uid 1000 inside container |
| N8N | `${DATA_DIR}/n8n` | uid 1000 (node) |
| Signalbot | `${DATA_DIR}/signalbot` | uid 1000 |
| Authentik | `${DATA_DIR}/authentik` | migration creates `/media/public` |
| LibreChat | `${DATA_DIR}/librechat/uploads` `${DATA_DIR}/librechat/logs` | runs as `node` (uid 1000), not root |

### Flowise — SQLite Only

`flowiseai/flowise:latest` is the enterprise edition. Its Postgres migrations break when schema was initialised by a different image version (common with `latest` tag). Use `DATABASE_TYPE: sqlite` to avoid all migration conflicts. Data is stored in the volume at `/root/.flowise/database.sqlite`.

### LiteLLM — Key Variables

```
LITELLM_MIGRATION_DIR: /tmp/litellm-migrations   # avoids P3005 "schema not empty"
PRISMA_BINARY_CACHE_DIR: /tmp/prisma-cache
HOME: /tmp                                         # prevents PermissionError in wolfi
```

### OpenWebUI — Correct Variable Names

`WEBUI_SECRET_KEY` (not `WEBUI_SECRET`). Container listens on port **8080** (not 3000). Port mapping: `"127.0.0.1:${OPENWEBUI_PORT}:8080"`.

### OpenClaw — Dynamic Port and Config Mount

OpenClaw reads `OPENCLAW_PORT` from its environment and binds to **that port** inside the container (not a fixed 3001). Correct port mapping: `"127.0.0.1:${OPENCLAW_PORT}:${OPENCLAW_PORT}"`. Caddy reverse proxy must also target `${TENANT_PREFIX}-openclaw:${OPENCLAW_PORT}`.

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
Script 2 generates this file at deploy time (same pattern as `litellm_config.yaml`) and mounts it `:ro`. Zep has no `curl` or `wget` — use `bash /dev/tcp` for the healthcheck.

### Authentik — Bootstrap

`AUTHENTIK_BOOTSTRAP_PASSWORD` and `AUTHENTIK_BOOTSTRAP_EMAIL` are generated by Script 2 at deploy time and written to docker-compose.yml. Script 2 also appends them to platform.conf via `update_conf_value()` so that Script 3 can display them in the credentials summary. The Authentik bootstrap API does not support a direct username/password → Bearer token exchange; the akadmin user and password are set automatically by the container from these env vars.

### Services with Container-Existence Guards in Script 3

Script 3's `configure_*()` functions guard against enabled-but-not-deployed services. Currently no guards are active — all enabled services are deployed by Script 2.

### networks: in build_*_deps() Functions

Every `build_*_deps()` function in Script 2 that emits a `depends_on:` block **must also emit a `networks:` block**. Services that omit `networks:` default to the `config_default` bridge, not the tenant network, making inter-service DNS resolution fail.

---

## DEPLOYMENT WORKFLOW

### Full Deployment

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
| `standard` | Development + N8N, Flowise, Grafana, Prometheus, Zep |
| `full` | Standard + OpenClaw, AnythingLLM, Dify, Authentik, SignalBot, LibreChat, Zep + Letta |

### TLS Modes

| Mode | What Script 2 does |
|---|---|
| `letsencrypt` | Caddy handles ACME automatically |
| `manual` | Expects cert/key at paths set in platform.conf |
| `selfsigned` | Generates self-signed cert at deploy time |
| `none` | HTTP only |

---

## CORE PRINCIPLES — COMPLIANCE CHECKLIST

Use this when implementing or reviewing any script change:

- [ ] Does Script 2 write `platform.conf`? Only via `update_conf_value()` for runtime secrets.
- [ ] Does every `build_*_deps()` emit both `depends_on:` and `networks:`?
- [ ] Does every service with a fixed internal UID get `chmod 777` on its data dir?
- [ ] Does LiteLLM / OpenWebUI / Letta omit `user:` override (must run as root)?
- [ ] Does LibreChat have `chmod 777` on its uploads/ and logs/ dirs (runs as node uid 1000)?
- [ ] Does every `configure_*()` function in Script 3 guard against container non-existence?
- [ ] Are all healthcheck endpoints correct (see table above)?
- [ ] Are `start_period` values set for slow-starting services?
- [ ] Is `set -euo pipefail` at the top of every script?
- [ ] Do all variable references use `${VAR:-default}` or have guaranteed prior assignment?
- [ ] Are all host ports bound to `127.0.0.1`?

---

## TROUBLESHOOTING

### Container not starting

1. `docker logs <container>` — always start here.
2. Check `docker inspect <container> --format '{{.State.Health}}'` for healthcheck output.
3. Verify the correct port mapping: `docker inspect <container> --format '{{json .HostConfig.PortBindings}}'`.

### Script 3 times out on a service

The service is enabled in platform.conf but the container was not deployed. Either:
- Add a container-existence guard in `configure_<service>()` (preferred), or
- Set `ENABLE_<SERVICE>="false"` in platform.conf.

### Port mismatch between platform.conf and running containers

Script 2 resolved a port conflict and wrote the actual port to `.configured/port-allocations`. Script 3 sources this file. If you inspect a running container's port binding and it differs from platform.conf, that is expected — the port-allocations value is authoritative.

### LiteLLM P1001 (can't reach Postgres)

The litellm service is on the wrong Docker network. Every `build_*_deps()` function must emit `networks: - ${DOCKER_NETWORK}` alongside its `depends_on:` block.

### LiteLLM P3005 (database schema not empty)

Set `LITELLM_MIGRATION_DIR: /tmp/litellm-migrations` in the compose environment block.

### Signalbot — number not paired

After deploy, pair the phone number manually:
```bash
# Option A — link existing device (scan QR in Signal app)
curl -s "http://127.0.0.1:${SIGNALBOT_PORT}/v1/qrcodelink/+<number>?device_name=ai-platform"

# Option B — register a new number (receives SMS code)
curl -s -X POST "http://127.0.0.1:${SIGNALBOT_PORT}/v1/register/+<number>"
curl -s -X POST "http://127.0.0.1:${SIGNALBOT_PORT}/v1/register/+<number>/verify/<CODE>"
```

---

## PROJECT STATUS

| Script | Status | Key behaviours |
|---|---|---|
| **Script 0** — Nuclear Cleanup | ✅ Production ready | Typed confirmation, EBS unmount before rm -rf, scoped to tenant |
| **Script 1** — Setup Wizard | ✅ Production ready | Interactive wizard, stack presets, port conflict detection, DNS/TLS validation, writes platform.conf |
| **Script 2** — Deployment Engine | ✅ Production ready | Heredoc compose generation, port allocator, writes port-allocations + runtime secrets back to platform.conf, full health-check wait |
| **Script 3** — Mission Control | ✅ Production ready | Sources port-allocations, configure_*() guards, port/DNS/API-key health checks, credentials display |

---

*Version: 4.1.0 | Last Updated: 2026-04-12 | Architecture: 4 scripts, ~20 services, single-tenant per EBS volume*
