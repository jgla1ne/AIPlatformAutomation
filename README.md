# AI Platform Automation

> **Modular, production-ready automation for self-hosted AI infrastructure.**  
> Four sequential scripts. One input session. Every component independently selectable.  
> True multi-tenant architecture: each tenant isolated by ID, user, and optionally a dedicated EBS volume.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-bash-blue.svg)](scripts/)
[![Platform](https://img.shields.io/badge/platform-Ubuntu%2022.04%20%7C2024.04-orange.svg)]()
[![Docker](https://img.shields.io/badge/requires-Docker-2496ED.svg)](https://docker.com)

---

## What This Is

Four bash scripts that turn a fresh Ubuntu server into a fully integrated,
production-ready AI platform in under 30 minutes — with true multi-tenant
isolation and AWS-native storage integration.

Every architectural layer — LLM proxy, local LLM inference, vector database,
web UIs, workflow automation, reverse proxy, TLS, authentication, messaging
gateway, observability, developer tooling, and backup — is independently
selectable at runtime. The scripts never assume a fixed stack.

**Fully integrated** means: after script 3 completes, every selected service
is already wired to every other relevant service. Open-WebUI, Dify, and
AnythingLLM all know your LLM proxy endpoint and vector DB. Ollama is
registered as a local model provider inside LLM proxy and surfaced
through the same routing strategy as external providers. The Signal gateway
is wired to query LLM proxy so that a Signal message triggers a full
RAG pipeline: Signal → LLM proxy → Ollama (local) or external LLM →
Qdrant/Weaviate/Chroma/Milvus → response back to Signal. OpenClaw is served
behind reverse proxy like all other web services — a managed browser
session accessible at its own subdomain over HTTPS. n8n and Flowise know
your LLM proxy credentials. Grafana has pre-imported dashboards for every
deployed service. Prometheus is pre-configured with scrape targets for
exactly your stack. rclone targets your tenant's `/mnt/<tenant-id>/` path
as single backup source covering the entire tenant deployment. You do
not configure inter-service connections manually.

**The core query path this platform enables:**

```
Signal message  ──or──  OpenClaw browser  ──or──  Web UI (Open-WebUI / Dify / AnythingLLM)
      │                        │                              │
      └────────────────────────┴──────────────────────────────┘
                                       │
                                       ▼
                          LLM Proxy (LiteLLM or Bifrost)
                          routing: local-first / fallback /
                                   round-robin / cost / latency
                                       │
                    ┌──────────────────┴──────────────────┐
                    ▼                                       ▼
             Ollama (local)                      External LLM
         Llama / Mistral / Phi /           OpenAI / Anthropic /
         Gemma / CodeLlama / …            Gemini / Bedrock / Azure
                    │                                       │
                    └──────────────────┬────────────────────┘
                                       ▼
                              Vector DB (RAG context)
                     Qdrant / Weaviate / Chroma / Milvus
                                       │
                                       ▼
                              Response to originating surface
```

**OpenClaw** provides a managed browser session behind the reverse proxy,
accessible at its own subdomain over HTTPS. All platform web interfaces are
reachable through OpenClaw without requiring any separate network tunnel.

**Post-deployment management** is handled by script 3 without full redeploy:
add providers, change routing strategy, enable/disable services, regenerate
proxy config, force rclone ingest, complete Signal registration, persist
startup state.

Script 1 is the **single source of truth**: it collects every variable,
generates every internal key, validates DNS, detects available EBS volumes,
mounts storage, creates the tenant user, and writes `platform.conf`. Scripts
2 and 3 are fully non-interactive and read exclusively from `platform.conf`.

---

### Non-Root Operation — Enforced, Not Recommended

**Every script rejects execution if `EUID == 0` and exits immediately.**

All scripts run as a named non-root platform user specific to the tenant
(`<prefix><tenant-id>`). Docker group membership is granted to that user.
All generated files, mounted volumes, and container bind mounts are owned
by the platform user, with UID/GID mapping enforced inside containers where
the service image supports it.

No UFW rules are created or modified. Firewall management is handled at the
AWS security group level.

---

## Network Architecture

```
Internet
    │
    ▼ :80 (redirect to HTTPS) / :443 (HTTPS)
┌──────────────────────────────────────────────────────┐
│              Reverse Proxy (Caddy or Nginx)                   │
│     TLS: Let's Encrypt / self-signed / provided certificate   │
│     Routes by subdomain to each service on Docker bridge      │
│                                                               │
│  chat.example.com      → Open-WebUI      :3000               │
│  dify.example.com      → Dify web        :3010               │
│  anything.example.com  → AnythingLLM     :3001               │
│  openclaw.example.com  → OpenClaw        :3002               │
│  n8n.example.com       → n8n             :5678               │
│  flowise.example.com   → Flowise         :3100               │
│  auth.example.com      → Authentik       :9000               │
│  monitor.example.com   → Grafana         :3030               │
│  llm.example.com       → LiteLLM        :4000               │
│  code.example.com      → Code Server     :8090               │
└──────────────────────────────┬───────────────────────────────┘
                               │  Docker bridge network
                               │  (<prefix><tenant-id>_net)
        ┌──────────────────────┼─────────────────────────────┐
        │                      │                             │
   ┌────▼────┐          ┌──────▼──────┐           ┌─────────▼──────┐
   │  Web UIs │          │  Workflow    │           │  Authentication │
   │Open-WebUI│          │  n8n :5678  │           │  Authentik      │
   │  Dify    │          │  Flowise    │           │  :9000          │
   │AnythingLLM          │  :3100      │           └────────────────┘
   │OpenClaw  │          └────────────┘
   └────┬─────┘
        │
   ┌────▼──────────────────────────────────────┐
   │      LLM Proxy (LiteLLM :4000                 │
   │                 or Bifrost :8181)              │
   │  routing: local-first / fallback /             │
   │           round-robin / cost / latency         │
   ├──────────────────┬────────────────────────────┤
   │                  │                            │
   ▼                  ▼                            ▼
Ollama          External LLMs              Vector DBs
:11434     OpenAI/Anthropic/etc.    Qdrant  :6333/:6334
(local)         (outbound only)     Weaviate :8082
                                    Chroma   :8000
                                    Milvus   :19530

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Signal CLI REST API — :8085 (127.0.0.1 only, temporary during registration)
Signal gateway      — Docker bridge only; no public or host port at runtime
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  └── LLM Proxy → Vector DB → LLM → Signal response

Observability (internal only, proxied to monitor subdomain)
  ├── Prometheus :9090
  └── Grafana    :3030

Developer (proxied to code subdomain)
  └── Code Server :8090
```

**Public:** ports 80 (redirect) and 443 only, via reverse proxy with TLS.
All services accessible through their subdomain — no direct port exposure.
**Signal CLI REST API registration:** bound to `127.0.0.1:8085` temporarily
during device registration only. Removed from host bindings post-registration.
**Signal gateway runtime:** Docker bridge only. No host port.
**No host firewall management:** AWS EC2 security groups are the perimeter.

---

## Multi-Tenant Architecture

Multiple independent AI platform stacks can be deployed on the same server.
Tenant isolation is enforced at every layer:

| Isolation Layer | Mechanism |
|-----------------|-----------|
| **Filesystem** | All data under `/mnt/<tenant-id>/` — separate EBS volume per tenant supported |
| **OS user** | Dedicated non-root user per tenant: `<platform-prefix><tenant-id>` |
| **Docker** | Separate Compose project per tenant; separate bridge network per tenant |
| **Container naming** | All containers: `<platform-prefix><tenant-id>-<service>` |
| **Config** | Separate `platform.conf` per tenant: `/mnt/<tenant-id>/config/` |
| **Ports** | All ports independently overridable per tenant; port conflict pre-check before any service starts |
| **Keys and secrets** | All internal keys generated independently per tenant at init |

### Port Conflict Pre-Check

**Before any service is configured or started**, script 3 checks every port
in `platform.conf` against all currently listening ports on the host using
`ss -tlnp`. If any collision is detected — between selected services or
against an already-bound host port — the script reports the conflict,
identifies the owning process, and halts before writing any configuration.
The check runs again on re-deployment.

### Tenant ID and Platform Prefix

During `1-setup-system.sh` you provide:

- **Platform prefix** — prepended to all container names, network names, and
  the OS username. Default: `ai-`. Examples: `ai-`, `prod-`, `staging-`.
- **Tenant ID** — unique identifier for this deployment. Used as the data
  directory name under `/mnt/` and as part of the OS username.

All container names follow `<prefix><tenant-id>-<service>`,
e.g. `ai-acme-litellm`, `ai-acme-qdrant`, `ai-acme-openwebui`.

### EBS Volume Selection and Mounting

Script 1 **mounts storage before any other operation**:

```
Available block devices:
  [1] /dev/nvme1n1   50GB   (unformatted — available)
  [2] /dev/nvme2n1  100GB   (unformatted — available)
  [3] Use existing /mnt/<tenant-id>/ on OS disk (no separate volume)
```

Selecting an unformatted EBS volume:
1. Formats as ext4
2. Creates `/mnt/<tenant-id>/` as the mount point
3. Adds to `/etc/fstab` using UUID (persistent across reboots)
4. Mounts it immediately

---

## Scripts Overview

| Script | Purpose | Interactive |
|--------|---------|-------------|
| `0-complete-cleanup.sh` | Nuclear removal of a specific tenant deployment | Yes — tenant selection + confirmation |
| `1-setup-system.sh` | All input collection, validation, key generation, EBS mount, user creation, `platform.conf` write | Yes — all prompts here only |
| `2-deploy-services.sh` | Pull images, create networks, start all selected containers in dependency order, display Mission Control health dashboard | No |
| `3-configure-services.sh` | Generate all configs, proxy rules, inter-service wiring, monitoring, rclone, systemd; post-deployment management | No |

### Quick Start

```bash
bash scripts/1-setup-system.sh   # Interactive: one session only
bash scripts/2-deploy-services.sh
bash scripts/3-configure-services.sh
```

Scripts 2 and 3 are re-runnable at any time after initial deployment.

---

## Script 0 — Complete Cleanup

- Prompts for tenant ID; will not proceed without explicit confirmation
- Stops and removes all containers matching `<prefix><tenant-id>-*`
- Removes Docker Compose project and bridge network
- Removes all generated config files under `/mnt/<tenant-id>/config/`
- Removes all systemd unit files for the tenant
- Removes the tenant OS user
- Optionally unmounts and wipes the tenant EBS volume (separate confirmation required)
- Does **not** affect other tenants on the same server

---

## Script 1 — Full Input Collection Reference

Script 1 is the only interactive script. Inputs are collected in dependency
order: identity and storage first, then domain, then each service layer in
the order that later services depend on earlier ones.

---

### Step 1 — Identity

| Input | Description | Default |
|-------|-------------|---------|
| Platform prefix | Prepended to container names, network name, OS username | `ai-` |
| Tenant ID | Deployment identifier; becomes `/mnt/<tenant-id>/` | Required |
| Platform OS username | Auto-derived: `<prefix><tenant-id>` | Auto |

---

### Step 2 — Storage (EBS Detection and Mount)

Runs immediately after identity. All subsequent writes go to the mounted volume.

| Input | Description |
|-------|-------------|
| EBS block device selection | Numbered list of available unformatted volumes + OS disk option |
| Volume formatting confirmation | Explicit yes/no before `mkfs.ext4` |

---

### Step 3 — Domain and DNS Validation

| Input | Description |
|-------|-------------|
| Base domain | Root domain, e.g. `example.com` |
| Per-service subdomain overrides | Defaults auto-generated; each individually overridable |
| DNS validation | Resolves each subdomain against server public IP; warns on mismatch |

DNS validation runs before TLS is configured. A failed validation with
`letsencrypt` TLS mode triggers an abort recommendation.

---

### Step 4 — Stack Type (Preset Selector)

| Stack Type | Description |
|------------|-------------|
| `minimal` | LLM proxy + one vector DB + one web UI only |
| `dev` | Adds workflow tools, Code Server, Ollama; no auth or monitoring |
| `full` | All services enabled — all three web UIs, all four vector DBs, all workflow tools, Ollama, Signal, OpenClaw, Authentik, monitoring, Code Server, rclone |
| `custom` | All services start disabled; user enables each one individually |

---

### Step 5 — Reverse Proxy

| Option | Details |
|--------|---------|
| `caddy` | Automatic Let's Encrypt TLS; recommended for public deployment |
| `nginx` | Manual TLS; self-signed or provided certificate |
| `none` | No reverse proxy; direct port access only |

---

### Step 6 — TLS Mode

| Option | Details |
|--------|---------|
| `letsencrypt` | Caddy auto-obtains and renews; valid public DNS required |
| `selfsigned` | Script generates self-signed cert; internal or dev use |
| `provided` | Provide certificate and key file paths |
| `none` | HTTP only |

---

### Step 7 — OpenClaw

| Input | Description | Default |
|-------|-------------|---------|
| `OPENCLAW_ENABLED` | Enable managed browser session service | `false` |
| `OPENCLAW_SUBDOMAIN` | Subdomain served behind reverse proxy | `openclaw.<base-domain>` |
| `OPENCLAW_PORT` | Internal host port | `3002` |
| `OPENCLAW_PASSWORD` | Session access password; generated if blank | Auto-generated |

OpenClaw is deployed as a containerised browser session behind the reverse
proxy. It is accessible at `https://openclaw.<base-domain>` after script 2
completes. No separate network tunnel required.

---

### Step 8 — LLM Proxy

| Input | Description | Default |
|-------|-------------|---------|
| `LLM_PROXY` | `litellm` or `bifrost` | `litellm` |
| `LLM_PROXY_PORT` | Host port | `4000` (LiteLLM) / `8181` (Bifrost) |
| `LLM_ROUTING_STRATEGY` | `local-first` / `fallback` / `round-robin` / `cost` / `latency` | `local-first` |
| `LLM_PROXY_MASTER_KEY` | Master API key for proxy; generated if blank | Auto-generated |
| `LLM_PROXY_DB_URL` | PostgreSQL DSN for proxy state persistence | Auto-generated |

**LiteLLM-specific:**

| Input | Description |
|-------|-------------|
| `LITELLM_UI_USERNAME` | LiteLLM dashboard username |
| `LITELLM_UI_PASSWORD` | LiteLLM dashboard password; generated if blank |

**Bifrost-specific:**

| Input | Description |
|-------|-------------|
| `BIFROST_API_KEY` | Bifrost API key; generated if blank |

---

### Step 9 — External LLM Providers

Collected per provider. Only enabled providers are written to `platform.conf`.

| Provider | Variables Collected |
|----------|-------------------|
| OpenAI | `OPENAI_API_KEY`, `OPENAI_ENABLED` |
| Anthropic | `ANTHROPIC_API_KEY`, `ANTHROPIC_ENABLED` |
| Google Gemini | `GEMINI_API_KEY`, `GEMINI_ENABLED` |
| AWS Bedrock | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `BEDROCK_ENABLED` |
| Azure OpenAI | `AZURE_API_KEY`, `AZURE_API_BASE`, `AZURE_API_VERSION`, `AZURE_ENABLED` |
| Cohere | `COHERE_API_KEY`, `COHERE_ENABLED` |
| Mistral | `MISTRAL_API_KEY`, `MISTRAL_ENABLED` |
| Custom endpoint | `CUSTOM_LLM_URL`, `CUSTOM_LLM_API_KEY`, `CUSTOM_LLM_ENABLED` |

At least one provider or Ollama must be enabled (enforced).

---

### Step 10 — Ollama (Local LLM Inference)

| Input | Description | Default |
|-------|-------------|---------|
| `OLLAMA_ENABLED` | Enable Ollama local inference | `false` |
| `OLLAMA_PORT` | Host port | `11434` |
| `OLLAMA_MODELS` | Comma-separated list of models to pull on first start | e.g. `llama3.2,mistral,phi3` |
| `OLLAMA_GPU_ENABLED` | Mount GPU device if available | `false` |

Ollama is auto-registered as a local provider inside the LLM proxy after
script 3 runs. The `local-first` routing strategy will route all requests
to Ollama first and fall back to external providers if Ollama is unavailable
or the requested model is not present locally.

---

### Step 11 — Vector Database

| Input | Description | Default |
|-------|-------------|---------|
| `VECTOR_DB_PRIMARY` | Primary vector DB: `qdrant` / `weaviate` / `chroma` / `milvus` | `qdrant` |
| `QDRANT_ENABLED` | | `false` |
| `QDRANT_REST_PORT` | Host port for REST API | `6333` |
| `QDRANT_GRPC_PORT` | Host port for gRPC | `6334` |
| `WEAVIATE_ENABLED` | | `false` |
| `WEAVIATE_PORT` | Host port | `8082` |
| `CHROMA_ENABLED` | | `false` |
| `CHROMA_PORT` | Host port | `8000` |
| `MILVUS_ENABLED` | | `false` |
| `MILVUS_PORT` | Host port | `19530` |

All enabled vector DBs are wired to every enabled web UI and the LLM proxy
during script 3. The `VECTOR_DB_PRIMARY` value determines which DB is
offered as the default in each web UI's settings.

---

### Step 12 — Web UIs

| Input | Description | Default |
|-------|-------------|---------|
| `OPENWEBUI_ENABLED` | | `false` |
| `OPENWEBUI_PORT` | Host port | `3000` |
| `OPENWEBUI_SUBDOMAIN` | | `chat.<base-domain>` |
| `DIFY_ENABLED` | | `false` |
| `DIFY_WEB_PORT` | Host port for Dify web frontend | `3010` |
| `DIFY_API_PORT` | Host port for Dify API | `5001` |
| `DIFY_SUBDOMAIN` | | `dify.<base-domain>` |
| `DIFY_SECRET_KEY` | Dify application secret; generated if blank | Auto-generated |
| `ANYTHINGLLM_ENABLED` | | `false` |
| `ANYTHINGLLM_PORT` | Host port | `3001` |
| `ANYTHINGLLM_SUBDOMAIN` | | `anything.<base-domain>` |
| `ANYTHINGLLM_JWT_SECRET` | JWT secret; generated if blank | Auto-generated |

---

### Step 13 — Workflow Automation

| Input | Description | Default |
|-------|-------------|---------|
| `N8N_ENABLED` | | `false` |
| `N8N_PORT` | Host port | `5678` |
| `N8N_SUBDOMAIN` | | `n8n.<base-domain>` |
| `N8N_ENCRYPTION_KEY` | n8n credential encryption key; generated if blank | Auto-generated |
| `N8N_BASIC_AUTH_USER` | Basic auth username | Required if enabled |
| `N8N_BASIC_AUTH_PASSWORD` | Basic auth password; generated if blank | Auto-generated |
| `FLOWISE_ENABLED` | | `false` |
| `FLOWISE_PORT` | Host port | `3100` |
| `FLOWISE_SUBDOMAIN` | | `flowise.<base-domain>` |
| `FLOWISE_USERNAME` | Flowise auth username | Required if enabled |
| `FLOWISE_PASSWORD` | Flowise auth password; generated if blank | Auto-generated |

n8n and Flowise are wired to the LLM proxy endpoint and credentials
automatically during script 3.

---

### Step 14 — Authentication (Authentik)

| Input | Description | Default |
|-------|-------------|---------|
| `AUTHENTIK_ENABLED` | | `false` |
| `AUTHENTIK_PORT` | Host port | `9000` |
| `AUTHENTIK_SUBDOMAIN` | | `auth.<base-domain>` |
| `AUTHENTIK_SECRET_KEY` | Django secret key; generated if blank | Auto-generated |
| `AUTHENTIK_BOOTSTRAP_EMAIL` | Initial admin email | Required if enabled |
| `AUTHENTIK_BOOTSTRAP_PASSWORD` | Initial admin password; generated if blank | Auto-generated |
| `AUTHENTIK_POSTGRES_PASSWORD` | Dedicated Authentik DB password; generated | Auto-generated |

---

### Step 15 — Signal Gateway

| Input | Description | Default |
|-------|-------------|---------|
| `SIGNAL_ENABLED` | Enable Signal messaging gateway | `false` |
| `SIGNAL_PHONE_NUMBER` | Phone number to register with Signal (E.164 format) | Required if enabled |
| `SIGNAL_REGISTRATION_METHOD` | `sms` or `voice` | `sms` |
| `SIGNAL_REST_PORT` | Host port for registration API — `127.0.0.1` bound, temporary only | `8085` |
| `SIGNAL_API_KEY` | Internal API key for gateway ↔ LLM proxy wiring; generated | Auto-generated |

**Signal Registration Flow:**

Signal CLI REST API requires a two-step device registration that must
happen before the gateway can receive or send messages. The port `8085`
is bound to `127.0.0.1` only and is temporary — it is removed from host
bindings after registration completes.

Registration is completed via script 3:

```bash
bash scripts/3-configure-services.sh --register-signal
```

This executes the following sequence:

```
Step 1 — Request verification code
  POST http://127.0.0.1:8085/v1/register/<SIGNAL_PHONE_NUMBER>
  Body: {"use_voice": false}
  → Signal sends SMS verification code to SIGNAL_PHONE_NUMBER

Step 2 — Submit verification code
  POST http://127.0.0.1:8085/v1/register/<SIGNAL_PHONE_NUMBER>/verify/<CODE>
  → Returns 201 on success; device is now registered

Step 3 — Verify registration
  GET http://127.0.0.1:8085/v1/about
  → Returns {"versions": [...], "build": ...}
  → Confirms service is operational

Step 4 — Remove temporary host port binding
  Script 3 removes 127.0.0.1:8085 from docker-compose service definition
  Signal CLI REST API continues running on Docker bridge only
  No host port exposed at runtime
```

After registration, the Signal gateway routes inbound Signal messages
through the LLM proxy, through the configured vector DB for RAG context,
and returns the response to the originating Signal conversation.

---

### Step 16 — rclone Backup

| Input | Description | Default |
|-------|-------------|---------|
| `RCLONE_ENABLED` | Enable automated backup | `false` |
| `RCLONE_BACKEND` | `gdrive` / `s3` / `b2` | Required if enabled |
| `RCLONE_SCHEDULE` | Cron expression for backup schedule | `0 2 * * *` |
| `RCLONE_BACKUP_PATH` | Source path | `/mnt/<tenant-id>/` |
| `RCLONE_RETENTION_DAYS` | Days to retain remote backups | `30` |

**Backend-specific inputs:**

**Google Drive — OAuth flow (interactive):**

| Input | Description |
|-------|-------------|
| `GDRIVE_CLIENT_ID` | OAuth2 client ID from Google Cloud Console |
| `GDRIVE_CLIENT_SECRET` | OAuth2 client secret |
| `GDRIVE_ROOT_FOLDER_ID` | Target folder ID in Google Drive |

OAuth authorisation URL is displayed in the terminal during script 1.
User opens the URL, grants access, and pastes the returned authorisation
code. Token is stored at `/mnt/<tenant-id>/config/rclone/gdrive.token`.

**Google Drive — Service Account (non-interactive, recommended for servers):**

| Input | Description |
|-------|-------------|
| `GDRIVE_SERVICE_ACCOUNT_JSON` | Path to downloaded service account JSON key file |
| `GDRIVE_ROOT_FOLDER_ID` | Target folder ID shared with the service account |

**AWS S3:**

| Input | Description |
|-------|-------------|
| `S3_ACCESS_KEY_ID` | AWS access key |
| `S3_SECRET_ACCESS_KEY` | AWS secret key |
| `S3_BUCKET` | Target bucket name |
| `S3_REGION` | AWS region |
| `S3_ENDPOINT` | Custom endpoint for S3-compatible stores (optional) |

**Backblaze B2:**

| Input | Description |
|-------|-------------|
| `B2_ACCOUNT_ID` | B2 account ID |
| `B2_APPLICATION_KEY` | B2 application key |
| `B2_BUCKET` | Target bucket name |

rclone is configured to back up the entire `/mnt/<tenant-id>/` path,
which contains all service data, configuration, and generated keys for
the tenant. A delta ingest to the primary vector DB can be triggered
after any restore:

```bash
bash scripts/3-configure-services.sh --ingest-delta
```

---

### Step 17 — Observability

| Input | Description | Default |
|-------|-------------|---------|
| `PROMETHEUS_ENABLED` | | `false` |
| `PROMETHEUS_PORT` | Host port | `9090` |
| `GRAFANA_ENABLED` | | `false` |
| `GRAFANA_PORT` | Host port | `3030` |
| `GRAFANA_SUBDOMAIN` | | `monitor.<base-domain>` |
| `GRAFANA_ADMIN_PASSWORD` | Generated if blank | Auto-generated |

Prometheus is pre-configured with scrape targets for every enabled service
that exposes a `/metrics` endpoint. Grafana is pre-configured with
Prometheus as the default data source and pre-imported dashboards for
Ollama inference metrics, LLM proxy throughput, vector DB performance,
container resource usage, and host system metrics.

---

### Step 18 — Code Server

| Input | Description | Default |
|-------|-------------|---------|
| `CODESERVER_ENABLED` | Enable VS Code in browser | `false` |
| `CODESERVER_PORT` | Host port | `8090` |
| `CODESERVER_SUBDOMAIN` | | `code.<base-domain>` |
| `CODESERVER_PASSWORD` | Generated if blank | Auto-generated |
| `CODESERVER_WORKSPACE` | Workspace path inside container | `/home/coder/project` |

---

### Step 19 — Shared Infrastructure

These are always deployed; inputs are collected once.

**PostgreSQL:**

| Input | Description | Default |
|-------|-------------|---------|
| `POSTGRES_PORT` | Host port | `5432` |
| `POSTGRES_PASSWORD` | Root password; generated if blank | Auto-generated |
| `POSTGRES_DATA_PATH` | Bind mount path | `/mnt/<tenant-id>/postgres/` |

Individual databases and users are auto-created per service during script 3.

**Redis:**

| Input | Description | Default |
|-------|-------------|---------|
| `REDIS_PORT` | Host port | `6379` |
| `REDIS_PASSWORD` | Auth password; generated if blank | Auto-generated |
| `REDIS_DATA_PATH` | Bind mount path | `/mnt/<tenant-id>/redis/` |

---

## Port Reference

All host ports. All container-to-container communication uses Docker
bridge service names and container ports — not host ports.

| Service | Container Port | Default Host Port | Conflict-Free Assignment |
|---------|---------------|-------------------|--------------------------|
| Caddy / Nginx | 80, 443 | 80, 443 | Public ingress only |
| LiteLLM | 4000 | 4000 | |
| Bifrost | 8080 | **8181** | Remapped: container 8080 → host 8181 |
| Ollama | 11434 | 11434 | |
| Qdrant REST | 6333 | 6333 | |
| Qdrant gRPC | 6334 | 6334 | |
| Weaviate | 8080 | **8082** | Remapped: container 8080 → host 8082 |
| Chroma | 8000 | 8000 | |
| Milvus | 19530 | 19530 | |
| Open-WebUI | 3000 | 3000 | |
| Dify web frontend | 3000 | **3010** | Remapped: container 3000 → host 3010 |
| Dify API | 5001 | 5001 | |
| AnythingLLM | 3001 | 3001 | |
| OpenClaw | 3002 | 3002 | |
| n8n | 5678 | 5678 | |
| Flowise | 3100 | 3100 | |
| Authentik | 9000 | 9000 | |
| Grafana | 3000 | **3030** | Remapped: container 3000 → host 3030 |
| Prometheus | 9090 | 9090 | |
| Code Server | 8080 | **8090** | Remapped: container 8080 → host 8090 |
| Signal CLI REST API | 8080 | **8085** (127.0.0.1, temporary) | Registration only; removed post-registration |
| PostgreSQL | 5432 | 5432 | |
| Redis | 6379 | 6379 | |

All ports are overridable per tenant via `platform.conf`. The port
conflict pre-check in script 3 validates this full table against live
host bindings before any service configuration begins.

---

## Service Dependency Chain

Script 2 starts services in strict dependency order. Each layer must
reach healthy status before the next layer starts.

```
Layer 0 — Storage and Network
  └── EBS mounted and verified
  └── Docker bridge network created: <prefix><tenant-id>_net

Layer 1 — Data Layer (must be healthy before anything else starts)
  ├── PostgreSQL          health: pg_isready -U postgres
  └── Redis               health: redis-cli -a $REDIS_PASSWORD ping → PONG

Layer 2 — Inference and Vector (depends on Layer 1)
  ├── Ollama              health: GET http://localhost:11434/api/version → 200
  ├── Qdrant              health: GET http://localhost:6333/healthz → {"status":"ok"}
  ├── Weaviate            health: GET http://localhost:8082/v1/.well-known/ready → 200
  ├── Chroma              health: GET http://localhost:8000/api/v1/heartbeat → 200
  └── Milvus              health: grpc_health_probe -addr=localhost:19530

Layer 3 — LLM Proxy (depends on Layer 1 + at least one LLM source)
  ├── LiteLLM             health: GET http://localhost:4000/health → {"status":"healthy"}
  └── Bifrost             health: GET http://localhost:8181/health → 200

Layer 4 — Application Layer (depends on Layers 1–3)
  ├── Open-WebUI          health: GET http://localhost:3000/health → 200
  ├── Dify API            health: GET http://localhost:5001/health → {"status":"ok"}
  ├── Dify web            health: GET http://localhost:3010/ → 200
  ├── AnythingLLM         health: GET http://localhost:3001/api/ping → {"online":true}
  ├── OpenClaw            health: GET http://localhost:3002/ → 200
  ├── n8n                 health: GET http://localhost:5678/healthz → {"status":"ok"}
  ├── Flowise             health: GET http://localhost:3100/api/v1/ping → {"ping":"pong"}
  └── Authentik           health: GET http://localhost:9000/-/health/ready/ → 200

Layer 5 — Proxy and TLS (depends on Layer 4)
  └── Caddy / Nginx       health: GET https://<base-domain>/ → 200 or redirect

Layer 6 — Observability (depends on Layers 1–4)
  ├── Prometheus          health: GET http://localhost:9090/-/healthy → 200
  └── Grafana             health: GET http://localhost:3030/api/health → {"database":"ok"}

Layer 7 — Developer Tools (depends on Layer 5)
  └── Code Server         health: GET http://localhost:8090/ → 200

Layer 8 — Messaging Gateway (depends on Layers 3 + 2)
  └── Signal CLI REST     health: GET http://127.0.0.1:8085/v1/about → {"versions":[...]}
                          (registration only; not part of runtime health)
```

Each service's `docker-compose.yml` block includes a `healthcheck`
directive matching the endpoint above. Script 2 uses `depends_on:
condition: service_healthy` to enforce layer ordering.

---

## Script 2 — Mission Control Health Dashboard

At the end of script 2, after all selected services have started and
passed their health checks, the following dashboard is printed to the
terminal. This is the **expected output** of a successful deployment.

```
╔════════════════════════════════════════════════════════════════════╗
║              AI PLATFORM — MISSION CONTROL                                  ║
║              Tenant: acme    Prefix: ai-    Stack: full                     ║
╠══════════════════════════════════════════════════════════════╣
║ LAYER 1 — DATA                                                               ║
║  ✓  PostgreSQL        :5432   healthy   pg_isready OK                        ║
║  ✓  Redis             :6379   healthy   PONG                                 ║
╠════════════════════════════════════════════════════════════════╣
║ LAYER 2 — INFERENCE & VECTOR                                                 ║
║  ✓  Ollama            :11434  healthy   version: 0.x.x   models: 3 loaded    ║
║  ✓  Qdrant            :6333   healthy   {"status":"ok"}                      ║
║  ✓  Weaviate          :8082   healthy   ready                                ║
║  ✓  Chroma            :8000   healthy   heartbeat OK                         ║
║  ✓  Milvus            :19530  healthy   grpc healthy                         ║
╠════════════════════════════════════════════════════════════════╣
║ LAYER 3 — LLM PROXY                                                          ║
║  ✓  LiteLLM           :4000   healthy   {"status":"healthy"}                 ║
║     Providers wired:  openai ✓  anthropic ✓  ollama/local ✓                 ║
║     Routing strategy: local-first                                            ║
╠══════════════════════════════════════════════════════════════════╣
║ LAYER 4 — APPLICATIONS                                                       ║
║  ✓  Open-WebUI        :3000   healthy   200 OK                               ║
║  ✓  Dify API          :5001   healthy   {"status":"ok"}                      ║
║  ✓  Dify web          :3010   healthy   200 OK                               ║
║  ✓  AnythingLLM       :3001   healthy   {"online":true}                      ║
║  ✓  OpenClaw          :3002   healthy   200 OK                               ║
║  ✓  n8n               :5678   healthy   {"status":"ok"}                      ║
║  ✓  Flowise           :3100   healthy   {"ping":"pong"}                      ║
║  ✓  Authentik         :9000   healthy   200 OK                               ║
╠════════════════════════════════════════════════════════════════╣
║ LAYER 5 — PROXY & TLS                                                        ║
║  ✓  Caddy             :443    healthy   TLS: Let's Encrypt                   ║
╠════════════════════════════════════════════════════════════════════╣
║ LAYER 6 — OBSERVABILITY                                                      ║
║  ✓  Prometheus        :9090   healthy   targets: 12 active                   ║
║  ✓  Grafana           :3030   healthy   {"database":"ok"}                    ║
╠══════════════════════════════════════════════════════════════════════════╣
║ LAYER 7 — DEVELOPER                                                          ║
║  ✓  Code Server       :8090   healthy   200 OK                               ║
╠══════════════════════════════════════════════════════════════════════════╣
║ LAYER 8 — MESSAGING                                                          ║
║  ⚠  Signal            :8085   awaiting registration                          ║
║     Run: bash scripts/3-configure-services.sh --register-signal             ║
╠══════════════════════════════════════════════════════════════════════════╣
║ ACCESS URLS                                                                  ║
║  Open-WebUI   →  https://chat.example.com                                   ║
║  Dify         →  https://dify.example.com                                   ║
║  AnythingLLM  →  https://anything.example.com                               ║
║  OpenClaw     →  https://openclaw.example.com                               ║
║  n8n          →  https://n8n.example.com                                    ║
║  Flowise      →  https://flowise.example.com                                ║
║  Authentik    →  https://auth.example.com                                   ║
║  Grafana      →  https://monitor.example.com                                ║
║  Code Server  →  https://code.example.com                                   ║
║  LiteLLM UI   →  https://llm.example.com                                    ║
╠══════════════════════════════════════════════════════════════════╣
║ CREDENTIALS                                                                  ║
║  Stored at:   /mnt/acme/config/platform.conf                                ║
║  Display:     bash scripts/3-configure-services.sh --show-credentials       ║
╠══════════════════════════════════════════════════════════════════════════╣
║ NEXT STEP                                                                    ║
║  bash scripts/3-configure-services.sh                                       ║
╚════════════════════════════════════════════════════════════════════════════════════╝
```

**Dashboard rules:**

| Symbol | Meaning |
|--------|---------|
| `✓` | Service started, health check passed, endpoint responding |
| `✗` | Service failed to start or health check timed out — see error recovery |
| `⚠` | Service running but requires a manual step to become operational |
| `—` | Service not selected for this deployment |

If any `✗` is present dashboard prints recovery command before exiting.

---

## Script 3 — Post-Deployment Management

Script 3 runs once after script 2 to complete all inter-service wiring.
It also accepts flags for post-deployment operations without full redeploy.

```bash
bash scripts/3-configure-services.sh                  # Full initial configuration
bash scripts/3-configure-services.sh --register-signal    # Complete Signal device registration
bash scripts/3-configure-services.sh --add-provider       # Add an LLM provider
bash scripts/3-configure-services.sh --reload-proxy       # Reload LLM proxy config
bash scripts/3-configure-services.sh --ingest-delta       # Trigger rclone delta ingest to vector DB
bash scripts/3-configure-services.sh --show-credentials   # Print all generated credentials
bash scripts/3-configure-services.sh --rotate-keys        # Rotate all internal API keys
bash scripts/3-configure-services.sh --enable <service>   # Enable a service post-deployment
bash scripts/3-configure-services.sh --disable <service>  # Disable a service post-deployment
bash scripts/3-configure-services.sh --reload-proxy       # Reload reverse proxy configuration
bash scripts/3-configure-services.sh --status             # Re-run health dashboard
```

Script 3 is idempotent. Re-running it on an already-configured deployment
is safe and will update configuration where values in `platform.conf`
have changed.

---

## Error Recovery

### EBS Mount Failure
```
ERROR: /dev/nvme1n1 did not mount at /mnt/<tenant-id>/
```
- Verify the device is attached: `lsblk`
- Check for existing filesystem: `blkid /dev/nvme1n1`
- Check fstab entry: `cat /etc/fstab | grep <tenant-id>`
- Attempt manual mount: `mount -a` then re-run script 1

### Health Check Timeout
```
✗  <service>   :PORT   timeout after 120s
```
- View container logs: `docker logs <prefix><tenant-id>-<service>`
- Check container state: `docker inspect <prefix><tenant-id>-<service>`
- Verify bind mount exists: `ls -la /mnt/<tenant-id>/<service>/`
- Re-run script 2; it will skip already-healthy services

### LLM Proxy Unreachable
```
✗  LiteLLM     :4000   connection refused
```
- Check PostgreSQL health first — LiteLLM requires database on start
- View logs: `docker logs <prefix><tenant-id>-litellm`
- Verify `LLM_PROXY_DB_URL` in `platform.conf` is correct
- Confirm PostgreSQL is accepting connections: `docker exec <prefix><tenant-id>-postgres pg_isready`

### Signal Registration Failure
```
POST /v1/register/<number> → 400 or 500
```
- Verify `SIGNAL_PHONE_NUMBER` is E.164 format: `+15551234567`
- Check service is bound: `ss -tlnp | grep 8085`
- View logs: `docker logs <prefix><tenant-id>-signal-cli-rest-api`
- Retry: `bash scripts/3-configure-services.sh --register-signal`

### Port Conflict Detected
```
ERROR: Port 6333 is already in use by process: <pid> (<name>)
       Conflicts with: QDRANT_REST_PORT
```
- Identify the process: `ss -tlnp | grep 6333`
- Override the port in `platform.conf`: `QDRANT_REST_PORT=6335`
- Re-run script 3; the port pre-check will validate the new value

---

## Resource Requirements

### Minimum RAM by Stack Type

| Stack Type | Minimum RAM | Recommended RAM |
|------------|-------------|-----------------|
| `minimal` | 4 GB | 8 GB |
| `dev` | 8 GB | 16 GB |
| `full` (no GPU) | 24 GB | 32 GB |
| `full` (with GPU) | 16 GB + VRAM | 32 GB + VRAM |

### Ollama VRAM by Model

| Model | VRAM Required |
|-------|--------------|
| `phi3` (3.8B) | 4 GB |
| `llama3.2` (3B) | 4 GB |
| `mistral` (7B) | 8 GB |
| `llama3.1` (8B) | 8 GB |
| `llama3.1:70b` (70B) | 48 GB |
| `codellama` (7B) | 8 GB |

### Recommended EC2 Instance Types

| Use Case | Instance | vCPU | RAM | Storage |
|----------|----------|------|-----|---------|
| Minimal / dev | `t3.xlarge` | 4 | 16 GB | 50 GB gp3 |
| Full stack, no local LLM | `m6i.2xlarge` | 8 | 32 GB | 100 GB gp3 |
| Full stack + Ollama (small models) | `g4dn.xlarge` | 4 | 16 GB | 16 GB VRAM T4 |
| Full stack + Ollama (large models) | `g4dn.12xlarge` | 48 | 192 GB | 64 GB VRAM 4×T4 |

### Multi-Tenant Guidance

Each additional tenant on the same server requires approximately:
- Minimal stack: +4 GB RAM, +20 GB disk
- Full stack: +16 GB RAM, +80 GB disk (separate EBS volume strongly recommended)

---

## platform.conf — Complete Key Reference

Generated by script 1 at `/mnt/<tenant-id>/config/platform.conf`.
Read by scripts 2 and 3. Never edited manually after generation except
to override a port before re-running script 3.

```bash
# Identity
PLATFORM_PREFIX=ai-
TENANT_ID=acme
PLATFORM_USER=ai-acme

# Storage
TENANT_DATA_PATH=/mnt/acme/
TENANT_CONFIG_PATH=/mnt/acme/config/
EBS_DEVICE=/dev/nvme1n1
EBS_MOUNT_POINT=/mnt/acme/

# Domain
BASE_DOMAIN=example.com

# Stack
STACK_TYPE=full
PROXY_TYPE=caddy
TLS_MODE=letsencrypt

# OpenClaw
OPENCLAW_ENABLED=true
OPENCLAW_PORT=3002
OPENCLAW_SUBDOMAIN=openclaw.example.com
OPENCLAW_PASSWORD=<generated>

# LLM Proxy
LLM_PROXY=litellm
LLM_PROXY_PORT=4000
LLM_ROUTING_STRATEGY=local-first
LLM_PROXY_MASTER_KEY=<generated>
LLM_PROXY_DB_URL=postgresql://litellm:<generated>@localhost:5432/litellm_acme
LITELLM_UI_USERNAME=admin
LITELLM_UI_PASSWORD=<generated>

# External LLM Providers
OPENAI_ENABLED=true
OPENAI_API_KEY=sk-...
ANTHROPIC_ENABLED=true
ANTHROPIC_API_KEY=sk-ant-...
GEMINI_ENABLED=false
BEDROCK_ENABLED=false
AZURE_ENABLED=false
COHERE_ENABLED=false
MISTRAL_ENABLED=false
CUSTOM_LLM_ENABLED=false

# Ollama
OLLAMA_ENABLED=true
OLLAMA_PORT=11434
OLLAMA_MODELS=llama3.2,mistral,phi3
OLLAMA_GPU_ENABLED=false

# Vector Databases
VECTOR_DB_PRIMARY=qdrant
QDRANT_ENABLED=true
QDRANT_REST_PORT=6333
QDRANT_GRPC_PORT=6334
QDRANT_API_KEY=<generated>
WEAVIATE_ENABLED=true
WEAVIATE_PORT=8082
CHROMA_ENABLED=false
CHROMA_PORT=8000
MILVUS_ENABLED=false
MILVUS_PORT=19530

# Web UIs
OPENWEBUI_ENABLED=true
OPENWEBUI_PORT=3000
OPENWEBUI_SUBDOMAIN=chat.example.com
OPENWEBUI_SECRET_KEY=<generated>
DIFY_ENABLED=true
DIFY_WEB_PORT=3010
DIFY_API_PORT=5001
DIFY_SUBDOMAIN=dify.example.com
DIFY_SECRET_KEY=<generated>
ANYTHINGLLM_ENABLED=true
ANYTHINGLLM_PORT=3001
ANYTHINGLLM_SUBDOMAIN=anything.example.com
ANYTHINGLLM_JWT_SECRET=<generated>

# Workflow
N8N_ENABLED=true
N8N_PORT=5678
N8N_SUBDOMAIN=n8n.example.com
N8N_ENCRYPTION_KEY=<generated>
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=<generated>
FLOWISE_ENABLED=true
FLOWISE_PORT=3100
FLOWISE_SUBDOMAIN=flowise.example.com
FLOWISE_USERNAME=admin
FLOWISE_PASSWORD=<generated>

# Authentication
AUTHENTIK_ENABLED=true
AUTHENTIK_PORT=9000
AUTHENTIK_SUBDOMAIN=auth.example.com
AUTHENTIK_SECRET_KEY=<generated>
AUTHENTIK_BOOTSTRAP_EMAIL=admin@example.com
AUTHENTIK_BOOTSTRAP_PASSWORD=<generated>
AUTHENTIK_POSTGRES_PASSWORD=<generated>

# Signal
SIGNAL_ENABLED=true
SIGNAL_PHONE_NUMBER=+15551234567
SIGNAL_REGISTRATION_METHOD=sms
SIGNAL_REST_PORT=8085
SIGNAL_API_KEY=<generated>
SIGNAL_REGISTERED=false

# Observability
PROMETHEUS_ENABLED=true
PROMETHEUS_PORT=9090
GRAFANA_ENABLED=true
GRAFANA_PORT=3030
GRAFANA_SUBDOMAIN=monitor.example.com
GRAFANA_ADMIN_PASSWORD=<generated>

# Code Server
CODESERVER_ENABLED=true
CODESERVER_PORT=8090
CODESERVER_SUBDOMAIN=code.example.com
CODESERVER_PASSWORD=<generated>
CODESERVER_WORKSPACE=/home/coder/project

# Shared Infrastructure
POSTGRES_PORT=5432
POSTGRES_PASSWORD=<generated>
POSTGRES_DATA_PATH=/mnt/acme/postgres/
REDIS_PORT=6379
REDIS_PASSWORD=<generated>
REDIS_DATA_PATH=/mnt/acme/redis/
DOCKER_NETWORK=ai-acme_net
```

---

## Data Layout

```
/mnt/<tenant-id>/
├── config/
│   ├── platform.conf          # Single source of truth for this tenant
│   ├── docker-compose.yml     # Generated by script 2
│   ├── caddy/Caddyfile        # Generated by script 3
│   ├── litellm/config.yaml    # Generated by script 3
│   ├── prometheus/            # Generated by script 3
│   ├── grafana/               # Dashboards + datasource provisioning
│   ├── rclone/                # rclone.conf + oauth token if gdrive
│   └── .configured/           # Per-service completion markers
├── postgres/                  # PostgreSQL data
├── redis/                     # Redis data
├── ollama/                    # Ollama model files
├── qdrant/                    # Qdrant collections
├── weaviate/                  # Weaviate data
├── chroma/                    # Chroma data
├── milvus/                    # Milvus data
├── openwebui/                 # Open-WebUI database and uploads
├── dify/                      # Dify application data
├── anythingllm/               # AnythingLLM data
├── openclaw/                  # OpenClaw session data
├── n8n/                       # n8n workflows and credentials
├── flowise/                   # Flowise flows
├── authentik/                 # Authentik media and certs
├── signal/                    # Signal CLI REST API data and registered account
├── prometheus/                # Prometheus TSDB
├── grafana/                   # Grafana dashboards and DB
├── codeserver/                # Code Server workspace and config
└── backup/                    # Local backup staging before remote push
```

---

## Contributing

### Required for any new service addition

1. **Port assignment** — assign a unique host port that does not conflict
   with any existing entry in Port Reference table; document both
   container port and assigned host port
2. **`platform.conf` key** — add `<SERVICE>_ENABLED`, `<SERVICE>_PORT`,
   and all service-specific variables to Script 1 input collection in
   dependency order
3. **Dependency layer** — identify which layer the service belongs to;
   document its `depends_on` requirements
4. **Health check** — add a `healthcheck` block to the service's
   `docker-compose.yml` entry using the actual health endpoint verified
   against the service's Docker documentation
5. **Dashboard row** — add a row to the Mission Control dashboard spec
   in this README and to script 2 dashboard output function
6. **Data path** — add `/mnt/<tenant-id>/<service>/` to the Data Layout
   section; all persistent data must go here, nowhere else
7. **Script 0 cleanup** — add removal of the service's data path and
   any systemd units to script 0
8. **Test matrix** — new service × each proxy type (`caddy`, `nginx`,
   `none`) × each TLS mode × two tenants on same server

### Design Principles

1. Every port, username, database name, and API key is a `platform.conf`
   variable — never hardcoded in any script or compose file
2. No script runs as root; `EUID == 0` check at entry exits immediately
3. No Docker named volumes; only bind mounts to `/mnt/<tenant-id>/`
4. No UFW or iptables manipulation
5. DNS validation runs before TLS is attempted
6. All internal keys are generated at init; never entered manually
7. Port conflict pre-check runs before any service is configured or started
8. Signal registration port `127.0.0.1:8085` is temporary and removed
   post-registration; no host port exposed at runtime
9. Script 3 is idempotent; re-running is always safe
10. Every new service must have a health check; scripts 2 and 3 never
    assume a service is ready without a passing health check response
11. All services — including browser session tools such as OpenClaw —
    are served behind reverse proxy over HTTPS; no separate tunnel
    or network overlay is required or supported
12. Phased delivery: each phase produces a stable, fully working platform;
    no phase leaves the system in a partially integrated state

---

## License

MIT — see [LICENSE](LICENSE)
