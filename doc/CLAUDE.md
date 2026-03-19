# Comprehensive Blueprint: Fixing AIPlatformAutomation Stack

## Executive Summary of What Windsurf Has Missed

After analyzing the repository, commit history, and the reported vs actual state, here is a precise diagnosis and implementation guide.

---

## 1. ROOT CAUSE: The LiteLLM/Prisma/PostgreSQL Problem

### What Windsurf Did Wrong
Windsurf removed Prisma from the LiteLLM configuration as a "fix" when LiteLLM failed to start. This is the **original sin** that cascades into every other service failure.

**Why LiteLLM needs PostgreSQL + Prisma:**
- LiteLLM uses Prisma ORM to manage its database schema
- PostgreSQL stores: API keys, spend tracking, model routing config, user management
- Without a valid DB connection with migrated schema, LiteLLM starts but **cannot validate API keys**
- Every downstream service (AnythingLLM, OpenWebUI, Flowise, Dify) authenticates through LiteLLM — if key management is broken, they either fail auth or cannot start properly

### The Actual LiteLLM Startup Sequence (What Windsurf Missed)
```
PostgreSQL must be healthy FIRST
  → Prisma migrations must run (prisma migrate deploy or prisma db push)
  → Only THEN does LiteLLM start
  → LiteLLM generates/validates master key against DB
  → Only THEN do dependent services start
```

Windsurf skipped step 2 (migration) and removed step 1 (postgres dependency), breaking the entire auth chain.

---

## 2. Diagnosis of Every Failing Service

### 2.1 LiteLLM Without Prisma — The Core Fix

**What the docker-compose entry for LiteLLM must look like:**

```yaml
litellm:
  image: ghcr.io/berriai/litellm:main-latest
  depends_on:
    postgres:
      condition: service_healthy
    litellm-prisma-migrate:  # THIS IS WHAT WINDSURF REMOVED
      condition: service_completed_successfully
  environment:
    DATABASE_URL: "postgresql://litellm:${POSTGRES_PASSWORD}@postgres:5432/litellm"
    LITELLM_MASTER_KEY: "${LITELLM_MASTER_KEY}"
    STORE_MODEL_IN_DB: "True"  # THIS IS CRITICAL - enables DB-backed config
  # ...
```

**The missing migration init container:**
```yaml
litellm-prisma-migrate:
  image: ghcr.io/berriai/litellm:main-latest
  depends_on:
    postgres:
      condition: service_healthy
  command: >
    sh -c "
      cd /app &&
      python -c 'from litellm.proxy.proxy_server import *; import prisma; prisma.Client().connect()' ||
      litellm --config /app/config.yaml &
      sleep 10 &&
      cd /usr/local/lib/python3.11/dist-packages/litellm/proxy &&
      prisma db push --schema ./schema.prisma &&
      kill %1
    "
  environment:
    DATABASE_URL: "postgresql://litellm:${POSTGRES_PASSWORD}@postgres:5432/litellm"
  restart: "no"
```

**IMPORTANT NOTE:** The exact migration command varies by LiteLLM version. The correct approach is:
```bash
# Inside the litellm container, find the schema:
find / -name "schema.prisma" -path "*/litellm/*" 2>/dev/null
# Then run:
prisma db push --schema <found_path>
```

Windsurf needs to exec into the image, find the actual schema path, and hardcode it.

---

### 2.2 OpenWebUI — SSL Error

**Root cause:** Nginx/Caddy is terminating SSL and passing HTTP internally, but OpenWebUI is either:
1. Receiving a redirect loop (configured to force HTTPS internally)
2. The proxy is not setting the correct headers

**What's missing in the proxy config:**
```nginx
location / {
    proxy_pass http://openwebui:3000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;  # THIS LINE IS MISSING
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;      # REQUIRED for WebSocket
    proxy_set_header Connection "upgrade";        # REQUIRED for WebSocket
}
```

OpenWebUI uses WebSockets for real-time chat. Without the Upgrade headers, connections silently fail.

---

### 2.3 Dify — SSL Error

**Root cause:** Dify is a multi-container service (api, worker, web, sandbox) and the proxy is likely pointing at the wrong internal port or the Dify nginx container is conflicting with the outer reverse proxy.

**Dify's internal architecture:**
```
Outer Reverse Proxy → Dify's own nginx (port 80) → Dify API/Web
```

**What Windsurf likely configured:**
```
Outer Reverse Proxy → Dify API directly (port 5001) [WRONG]
```

**Correct proxy target for Dify:**
```nginx
# Point to Dify's internal nginx, NOT the API directly
proxy_pass http://dify-nginx:80;
```

Also verify Dify's `.env`:
```env
CONSOLE_WEB_URL=https://dify.yourdomain.com
APP_WEB_URL=https://dify.yourdomain.com
```
These must match the actual external URL or Dify generates broken redirect URLs.

---

### 2.4 Flowise — HTTP 502

**502 = upstream not responding.** This means the Flowise container is either not running or listening on the wrong port.

**Check sequence:**
```bash
docker ps | grep flowise          # Is it running?
docker logs flowise --tail 50     # Why is it not running?
docker exec flowise curl localhost:3000  # Is it listening internally?
```

**Most likely cause:** Flowise requires a `FLOWISE_USERNAME` and `FLOWISE_PASSWORD` if auth is enabled, and if these aren't set in environment it may crash silently.

Also verify the LiteLLM API key in Flowise's environment — if it can't reach LiteLLM on startup and has a health check dependency, it fails.

---

### 2.5 OpenClaw Routing to Code-Server — Proxy Config Bug

**This is a classic Nginx location block ordering issue.**

What's happening:
```
https://openclaw.ai.datasquiz.net → Should go to service on port 18789
                                   → Actually going to code-server
```

**The bug:** Nginx location blocks are matched by specificity. If code-server has a catch-all or broader match, it wins.

**What to tell Windsurf to check:**
```nginx
# In the nginx config, there is likely something like:
server_name *.datasquiz.net;  # code-server catching everything

# Or the openclaw server block is missing and requests fall through to default
```

**The fix pattern:**
```nginx
# Ensure openclaw has its OWN server block, not a location block inside a shared server
server {
    listen 443 ssl;
    server_name openclaw.ai.datasquiz.net;  # Exact match takes priority
    
    location / {
        proxy_pass http://127.0.0.1:18789;
        # ... headers
    }
}
```

**Do NOT use a shared server block with multiple location blocks for different subdomains.** Each service needs its own `server {}` block.

---

### 2.6 Signal API — /v1/qrcodelink Not Working

**Signal-CLI REST API** requires:
1. Registration to complete first (phone number must be registered)
2. The QR code endpoint only works in `native` mode, not `json-rpc` mode

**Check the Signal container startup mode:**
```bash
docker logs signal-api | head -30
```

If Windsurf configured it with `MODE=json-rpc`, the QR code endpoint doesn't exist.

**Correct environment:**
```yaml
signal-api:
  environment:
    MODE: native          # NOT json-rpc
    SIGNAL_CLI_CONFIG: /home/.local/share/signal-cli
    AUTO_RECEIVE_SCHEDULE: "0 * * * *"
```

Also — the phone number must be pre-registered. The QR link only works for linking an existing account as secondary device, OR you must first call the register endpoint.

**Tell Windsurf to verify:**
```bash
# Check if account is registered
curl http://localhost:8080/v1/accounts
# If empty array, registration hasn't happened
```

---

### 2.7 RClone Not Mounting/Syncing GDrive

**Two separate issues Windsurf has conflated:**

**Issue A — Mounting:** RClone mount requires `--allow-other` flag AND the Docker container needs `/dev/fuse` device access and `SYS_ADMIN` capability.

```yaml
rclone:
  image: rclone/rclone
  cap_add:
    - SYS_ADMIN          # REQUIRED for FUSE mount
  devices:
    - /dev/fuse          # REQUIRED for FUSE mount
  security_opt:
    - apparmor:unconfined # May be needed on Ubuntu
```

Without these, the mount silently fails and RClone falls back or exits.

**Issue B — Active Sync to Qdrant:** The README describes an ingestion pipeline that Windsurf has **not implemented at all**. This is a missing feature, not a bug.

---

## 3. The Missing Ingestion Pipeline (Windsurf Never Built This)

This is the most significant gap. The README describes:
```
GDrive → RClone Sync → Local Storage → Embedding → Qdrant
                                                     ↑
                              AnythingLLM, OpenWebUI, OpenClaw all query here
```

**What needs to be built in Script 3:**

### Step 1: RClone Sync (not mount — sync is more reliable in Docker)
```bash
# In script 3 or a dedicated sync script:
docker exec rclone rclone sync \
  gdrive:/YourFolder \
  /data/gdrive-sync \
  --progress \
  --transfers=4
```

### Step 2: Embedding Ingestion into Qdrant

Windsurf needs to create a new container or script that:
1. Watches the sync directory for new/changed files
2. Chunks documents (PDF, DOCX, TXT, MD)
3. Calls the embedding model via LiteLLM
4. Upserts vectors into Qdrant with metadata

**Recommended approach — use a Python ingestion script:**

```python
# /scripts/ingestion/ingest.py (Windsurf needs to create this)

import os
import hashlib
from pathlib import Path
from qdrant_client import QdrantClient
from qdrant_client.models import PointStruct, VectorParams, Distance
import requests

QDRANT_URL = os.getenv("QDRANT_URL", "http://qdrant:6333")
LITELLM_URL = os.getenv("LITELLM_URL", "http://litellm:4000")
LITELLM_KEY = os.getenv("LITELLM_MASTER_KEY")
COLLECTION_NAME = "gdrive_documents"
EMBED_MODEL = "text-embedding-3-small"  # or whatever is configured in LiteLLM
SYNC_DIR = "/data/gdrive-sync"
CHUNK_SIZE = 500  # tokens approx
```

The script must:
- Maintain a hash-based index so it doesn't re-embed unchanged files
- Support PDF (use pypdf), DOCX (use python-docx), TXT/MD natively
- Create the Qdrant collection if it doesn't exist with correct vector dimensions
- Store metadata: filename, path, gdrive_path, chunk_index, timestamp

### Step 3: Docker Compose Service for Ingestion
```yaml
gdrive-ingestion:
  build:
    context: ./ingestion
    dockerfile: Dockerfile
  depends_on:
    - qdrant
    - litellm
    - rclone
  volumes:
    - gdrive_data:/data/gdrive-sync:ro
    - ingestion_state:/data/ingestion-state
  environment:
    QDRANT_URL: http://qdrant:6333
    LITELLM_URL: http://litellm:4000
    LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
    SYNC_DIR: /data/gdrive-sync
    WATCH_MODE: "true"   # continuous watching vs one-shot
  restart: unless-stopped
```

### Step 4: Configure Each Service to Use Shared Qdrant Collection

**AnythingLLM:**
```env
VECTOR_DB=qdrant
QDRANT_ENDPOINT=http://qdrant:6333
QDRANT_COLLECTION_NAME=gdrive_documents
```

**OpenWebUI:**
- Navigate to Settings → Documents → Vector Database
- Set to Qdrant, URL: http://qdrant:6333
- Collection: gdrive_documents

**OpenClaw:** Needs API configuration pointing to Qdrant endpoint

---

## 4. The Definitive Service Startup Order

This is what `docker-compose.yml` `depends_on` must enforce:

```
Layer 0 (Infrastructure):
  postgres (healthcheck: pg_isready)
  redis (healthcheck: redis-cli ping)
  qdrant (healthcheck: curl /healthz)

Layer 1 (Schema):
  litellm-prisma-migrate (depends: postgres healthy, runs once)

Layer 2 (Core AI Gateway):
  litellm (depends: postgres healthy + migrate completed)

Layer 3 (Storage/Sync):
  rclone (depends: nothing, but needs credentials volume)
  minio (if used)

Layer 4 (AI Applications):
  anythingllm (depends: litellm healthy, qdrant healthy)
  openwebui (depends: litellm healthy, qdrant healthy)
  flowise (depends: litellm healthy)
  dify-api (depends: postgres healthy, redis healthy, litellm healthy)
  dify-worker (depends: dify-api healthy)
  openclaw (depends: litellm healthy)

Layer 5 (Ingestion):
  gdrive-ingestion (depends: qdrant healthy, litellm healthy, rclone)

Layer 6 (Observability):
  prometheus
  grafana (depends: prometheus)

Layer 7 (Proxy — LAST):
  nginx/caddy (depends: all application services)
```

**Windsurf has been starting the proxy before services are ready, causing 502s that persist.**

---

## 5. The Nginx Configuration — Complete Structural Fix

Tell Windsurf the nginx config must follow this pattern **exactly**:

```nginx
# /etc/nginx/conf.d/services.conf

# Each service = its own server block. No exceptions.

server {
    listen 80;
    server_name _;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name litellm.datasquiz.net;
    ssl_certificate /etc/nginx/certs/datasquiz.net/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/datasquiz.net/privkey.pem;
    
    location / {
        proxy_pass http://litellm:4000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Real-IP $remote_addr;
    }
}

server {
    listen 443 ssl http2;
    server_name openwebui.datasquiz.net;
    # ... separate block entirely
    
    location / {
        proxy_pass http://openwebui:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;  # WebSocket long-lived connections
    }
}

# openclaw MUST be server_name openclaw.ai.datasquiz.net
# NOT a location block inside another server
server {
    listen 443 ssl http2;
    server_name openclaw.ai.datasquiz.net;
    
    location / {
        proxy_pass http://openclaw:18789;  # Internal Docker port, not host port
        # ...
    }
}
```

---

## 6. Environment Variables Windsurf Is Likely Getting Wrong

The `.env` file must have these **all consistent** — Windsurf has likely set them inconsistently across service definitions:

```env
# PostgreSQL — ONE password used everywhere
POSTGRES_PASSWORD=<strong_password>
POSTGRES_USER=postgres

# LiteLLM must have its OWN database (not shared with other services)
LITELLM_DB_URL=postgresql://litellm:${POSTGRES_PASSWORD}@postgres:5432/litellm

# Dify has its OWN database
DIFY_DB_URL=postgresql://dify:${POSTGRES_PASSWORD}@postgres:5432/dify

# LiteLLM Master Key — this is what ALL services use to auth
LITELLM_MASTER_KEY=sk-<generated_key>

# Services must reference this key
OPENWEBUI_OPENAI_API_KEY=${LITELLM_MASTER_KEY}
ANYTHINGLLM_LITELLM_KEY=${LITELLM_MASTER_KEY}

# Qdrant — if auth enabled, key must be consistent
QDRANT_API_KEY=<qdrant_key>

# Domain — used to construct URLs for services
BASE_DOMAIN=datasquiz.net
```

---

## 7. What to Tell Windsurf — Precise Instructions

### Fix 1: Restore and Fix LiteLLM + PostgreSQL
```
1. Add back the postgres service with a healthcheck
2. Add a litellm-prisma-migrate init container that runs `prisma db push`
3. Find the actual schema.prisma path inside the litellm image: 
   `docker run --rm --entrypoint find ghcr.io/berriai/litellm:main-latest / -name schema.prisma`
4. Set STORE_MODEL_IN_DB=True in litellm environment
5. Set DATABASE_URL correctly
6. Make litellm depend on both postgres (healthy) and migrate (completed)
```

### Fix 2: Nginx — Separate Server Blocks
```
1. Delete current nginx config entirely
2. Create one server block per subdomain
3. Add X-Forwarded-Proto https to all blocks
4. Add Upgrade/Connection headers to OpenWebUI and any WebSocket service
5. Set proxy_read_timeout 86400 for streaming/WebSocket services
6. Ensure openclaw.ai.datasquiz.net is its own server block pointing to openclaw container
```

### Fix 3: Build the Ingestion Pipeline
```
1. Create /ingestion directory with Dockerfile + ingest.py
2. Add gdrive-ingestion service to docker-compose
3. Configure rclone to sync (not mount) to a named volume
4. Ingestion script reads that volume, chunks files, embeds via LiteLLM, upserts to Qdrant
5. Configure AnythingLLM and OpenWebUI to point to same Qdrant collection
```

### Fix 4: Signal API
```
1. Check Signal container logs for current mode
2. Set MODE=native (not json-rpc)  
3. Verify phone number registration status via /v1/accounts
4. If unregistered, call registration endpoint first
```

### Fix 5: RClone
```
1. Add cap_add: [SYS_ADMIN] to rclone service
2. Add devices: [/dev/fuse]
3. Switch from rclone mount to rclone sync on a cron schedule
4. Use sync to a Docker named volume shared with ingestion service
```

### Fix 6: Dify
```
1. Verify proxy points to dify-nginx:80, not dify-api:5001
2. Set CONSOLE_WEB_URL and APP_WEB_URL to match actual external URL
3. Ensure dify has its own postgres database created
```

---

## 8. Validation Checklist for Windsurf to Run After Each Fix

```bash
# After Fix 1 (LiteLLM):
curl -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  http://localhost:4000/health
# Expected: {"status":"healthy","db":"connected"}

# After Fix 2 (Nginx):
curl -I https://openwebui.datasquiz.net
# Expected: HTTP/2 200, no SSL errors

# After Fix 3 (Ingestion):
curl http://localhost:6333/collections/gdrive_documents
# Expected: collection exists with vector count > 0

# After Fix 4 (Signal):
curl http://localhost:8080/v1/accounts
# Expected: array with registered number

# After Fix 5 (RClone):
docker exec rclone rclone lsd gdrive:/
# Expected: directory listing, no auth errors

# After Fix 6 (Dify):
curl -I https://dify.datasquiz.net
# Expected: HTTP/2 200
```

---

## 9. Why Windsurf Keeps Failing in Circles

The fundamental issue is **Windsurf is fixing symptoms rather than the dependency graph**. Each "fix" breaks a downstream dependency it didn't model:

1. Removes Prisma → LiteLLM starts but can't manage keys → all services that need key validation fail silently
2. Fixes one service's SSL → another service's WebSocket breaks because the same header fix wasn't applied globally
3. Claims 100% success because services return *some* HTTP response, not necessarily *correct* HTTP response

**The instruction Windsurf needs:** "Do not mark any service as fixed until the validation curl command above returns the expected response. Treat any non-200 or unexpected response as a failure."

---

## 10. The Correct Final Architecture Diagram

```
Internet
    │
    ▼
Nginx (443 SSL termination)
    │
    ├──► OpenWebUI (WebSocket + HTTP)
    ├──► AnythingLLM (HTTP)  
    ├──► Dify-nginx (HTTP → Dify internal routing)
    ├──► Flowise (HTTP)
    ├──► OpenClaw (HTTP)
    ├──► LiteLLM (HTTP - API Gateway)
    ├──► Grafana (HTTP)
    └──► Code-Server (HTTP)
    
LiteLLM ──► PostgreSQL (Prisma schema, keys, spend)
LiteLLM ──► Redis (caching)
LiteLLM ──► Ollama/OpenAI (model backends)

Qdrant ◄─── gdrive-ingestion ◄─── rclone-sync ◄─── GDrive
  ▲
  ├── AnythingLLM (shared collection)
  ├── OpenWebUI (shared collection)
  └── OpenClaw (shared collection)

Signal-API (standalone, phone registration required)
Prometheus ◄─── all services (metrics)
Grafana ──► Prometheus
```

This architecture is what the README describes and what needs to be implemented. The proxy, the DB-backed LiteLLM, and the shared Qdrant ingestion pipeline are the three pillars Windsurf has failed to correctly implement simultaneously.