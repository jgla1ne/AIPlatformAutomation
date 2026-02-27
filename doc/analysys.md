Let me fetch all current files.

**Fetching:**
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/1-setup-system.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/2-deploy-services.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/3-configure-services.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/docker-compose.yml

---

## Full Audit — Current Codebase State

### Table 1 — Service Inventory vs Script 1 Menu Options

```
┌─────────────────────┬───────────┬────────────┬───────────┬────────────────────────────────────────┐
│ SERVICE             │ S1 MENU   │ COMPOSE    │ S2 DEPLOY │ LEGITIMACY / PURPOSE                   │
├─────────────────────┼───────────┼────────────┼───────────┼────────────────────────────────────────┤
│ INFRASTRUCTURE (auto-deployed when needed)                                                        │
├─────────────────────┼───────────┼────────────┼───────────┼────────────────────────────────────────┤
│ PostgreSQL          │ ✅ auto   │ ✅         │ ✅ wait   │ Core DB — needed by 8+ services        │
│ Redis               │ ✅ auto   │ ✅         │ ✅ wait   │ Cache/queue — needed by 6+ services    │
│ Caddy               │ ✅ auto   │ ✅         │ ✅        │ Reverse proxy — auto SSL               │
├─────────────────────┼───────────┼────────────┼───────────┼────────────────────────────────────────┤
│ VECTOR DB (user selects one)                                                                      │
├─────────────────────┼───────────┼────────────┼───────────┼────────────────────────────────────────┤
│ Qdrant              │ ✅ opt    │ ✅         │ ✅        │ Vector DB option 1                     │
│ Weaviate            │ ❌ MISS   │ ❌ MISS    │ ❌ MISS   │ Vector DB option 2 — NOT IN STACK      │
│ Chroma              │ ❌ MISS   │ ❌ MISS    │ ❌ MISS   │ Vector DB option 3 — NOT IN STACK      │
├─────────────────────┼───────────┼────────────┼───────────┼────────────────────────────────────────┤
│ AI PLATFORMS                                                                                      │
├─────────────────────┼───────────┼────────────┼───────────┼────────────────────────────────────────┤
│ AnythingLLM         │ ✅ opt    │ ✅         │ ✅        │ RAG + chat UI — YES belongs            │
│ OpenWebUI           │ ✅ opt    │ ✅         │ ✅        │ Ollama/LLM chat UI — YES belongs       │
│ Dify                │ ✅ opt    │ ⚠️ partial │ ✅        │ LLM app builder — YES belongs          │
│ Flowise             │ ✅ opt    │ ✅         │ ✅        │ LLM flow builder — YES belongs         │
│ LibreChat           │ ✅ opt    │ ⚠️ partial │ ✅        │ Multi-model chat — YES belongs         │
│ Lobe-Chat           │ ✅ opt    │ ✅         │ ✅        │ Modern chat UI — YES belongs           │
├─────────────────────┼───────────┼────────────┼───────────┼────────────────────────────────────────┤
│ LLM / MODEL SERVING                                                                               │
├─────────────────────┼───────────┼────────────┼───────────┼────────────────────────────────────────┤
│ LiteLLM             │ ✅ opt    │ ✅         │ ✅        │ LLM proxy/router — YES belongs         │
│ Ollama              │ ✅ opt    │ ✅         │ ✅        │ Local model runner — YES belongs        │
│ LocalAI             │ ✅ opt    │ ✅         │ ✅        │ Local model runner alt — YES belongs    │
│ vLLM                │ ✅ opt    │ ✅         │ ✅        │ GPU model serving — YES belongs        │
│ Whisper             │ ✅ opt    │ ✅         │ ✅        │ Speech-to-text — YES belongs           │
│ ComfyUI             │ ✅ opt    │ ✅         │ ✅        │ Image gen UI — YES belongs             │
│ Stable Diffusion    │ ✅ opt    │ ✅         │ ✅        │ Image gen backend — YES belongs        │
├─────────────────────┼───────────┼────────────┼───────────┼────────────────────────────────────────┤
│ AUTOMATION / AGENTS                                                                               │
├─────────────────────┼───────────┼────────────┼───────────┼────────────────────────────────────────┤
│ n8n                 │ ✅ opt    │ ✅         │ ✅        │ Workflow automation — YES belongs       │
│ Activepieces        │ ✅ opt    │ ⚠️ partial │ ✅        │ Automation alt — YES belongs           │
│ AutoGPT             │ ✅ opt    │ ⚠️ partial │ ✅        │ Autonomous agent — YES belongs         │
│ OpenHands           │ ✅ opt    │ ✅         │ ✅        │ Code agent — YES belongs               │
│ Temporal            │ ⚠️ MISS  │ ⚠️ partial │ ❌        │ Workflow engine — ONLY if n8n/AP use it│
│ Langfuse            │ ✅ opt    │ ⚠️ partial │ ✅        │ LLM observability — YES belongs        │
├─────────────────────┼───────────┼────────────┼───────────┼────────────────────────────────────────┤
│ COMMS / MESSAGING                                                                                 │
├─────────────────────┼───────────┼────────────┼───────────┼────────────────────────────────────────┤
│ Signal API          │ ✅ opt    │ ✅         │ ⚠️ part   │ Signal bridge — YES belongs            │
│ Mattermost          │ ✅ opt    │ ⚠️ partial │ ✅        │ Team messaging — YES belongs           │
│ Matrix/Synapse      │ ✅ opt    │ ⚠️ partial │ ✅        │ Federated chat — YES belongs           │
├─────────────────────┼───────────┼────────────┼───────────┼────────────────────────────────────────┤
│ DATA / STORAGE                                                                                    │
├─────────────────────┼───────────┼────────────┼───────────┼────────────────────────────────────────┤
│ Minio               │ ✅ opt    │ ✅         │ ✅        │ S3-compatible storage — YES belongs    │
│ Firecrawl           │ ✅ opt    │ ⚠️ partial │ ✅        │ Web scraper for RAG — YES belongs      │
│ rclone/GDrive       │ ⚠️ part  │ ❌ MISS    │ ❌ MISS   │ GDrive sync — NOT IN COMPOSE           │
├─────────────────────┼───────────┼────────────┼───────────┼────────────────────────────────────────┤
│ MONITORING                                                                                        │
├─────────────────────┼───────────┼────────────┼───────────┼────────────────────────────────────────┤
│ Grafana             │ ✅ opt    │ ⚠️ partial │ ✅        │ Dashboards — YES belongs               │
│ Prometheus          │ ✅ opt    │ ⚠️ partial │ ✅        │ Metrics — YES belongs                  │
│ Portainer           │ ✅ opt    │ ✅         │ ✅        │ Docker UI — YES belongs                │
│ Netdata             │ ✅ opt    │ ✅         │ ✅        │ System metrics — YES belongs           │
├─────────────────────┼───────────┼────────────┼───────────┼────────────────────────────────────────┤
│ ACCESS / SECURITY                                                                                 │
├─────────────────────┼───────────┼────────────┼───────────┼────────────────────────────────────────┤
│ OpenClaw            │ ✅ opt    │ ✅         │ ⚠️ part   │ VPN access layer — YES belongs         │
│ Tailscale           │ ✅ opt    │ ⚠️ part    │ ❌ MISS   │ Mesh VPN — YES belongs                 │
│ Authentik           │ ✅ opt    │ ⚠️ partial │ ✅        │ SSO/IdP — YES belongs                  │
│ Keycloak            │ ✅ opt    │ ⚠️ partial │ ✅        │ SSO/IdP alt — REDUNDANT w/ Authentik   │
└─────────────────────┴───────────┴────────────┴───────────┴────────────────────────────────────────┘
```

---

### Keycloak & Temporal Verdict

```
KEYCLOAK:
  Currently in compose AND Script 1 as option.
  Authentik is also in stack doing same job (SSO/IdP).
  RECOMMENDATION: Remove Keycloak. Keep Authentik only.
  Reason: Two SSO providers creates config confusion,
  double postgres databases, double maintenance.
  Authentik is more modern and Docker-native.

TEMPORAL:
  In compose partially but NOT in Script 1 menu.
  Temporal is a workflow orchestration engine.
  It is NOT needed unless you are building custom
  long-running workflows beyond n8n/Activepieces.
  RECOMMENDATION: Remove Temporal from compose entirely.
  It adds 3 containers (server, ui, worker) and a
  postgres schema with zero user-facing value in this stack.
```

---

### Table 2 — Non-Root & /mnt Compliance Per Service

```
┌─────────────────────┬──────────────────┬─────────────────────┬────────────────────────────────────┐
│ SERVICE             │ NON-ROOT         │ DATA ON /mnt        │ ISSUE                              │
├─────────────────────┼──────────────────┼─────────────────────┼────────────────────────────────────┤
│ PostgreSQL          │ ❌ user: removed  │ ✅ named volume     │ pgvector runs as uid 999 internally │
│                     │ in last fix but  │                     │ named volume must be on /mnt        │
│                     │ needs validation │                     │ Docker default puts it in /var      │
├─────────────────────┼──────────────────┼─────────────────────┼────────────────────────────────────┤
│ Redis               │ ⚠️ no user set   │ ✅ named volume     │ Same volume location issue         │
├─────────────────────┼──────────────────┼─────────────────────┼────────────────────────────────────┤
│ Qdrant              │ ⚠️ no user set   │ ✅ bind mount       │ /mnt/data/${TENANT}/qdrant ✅       │
├─────────────────────┼──────────────────┼─────────────────────┼────────────────────────────────────┤
│ AnythingLLM         │ ✅ user set      │ ✅ bind mount       │ OK                                 │
├─────────────────────┼──────────────────┼─────────────────────┼────────────────────────────────────┤
│ OpenWebUI           │ ⚠️ no user set   │ ✅ bind mount       │ Runs as root by default            │
├─────────────────────┼──────────────────┼─────────────────────┼────────────────────────────────────┤
│ Dify                │ ❌ not set       │ ⚠️ partial          │ Sandbox needs seccomp profile      │
├─────────────────────┼──────────────────┼─────────────────────┼────────────────────────────────────┤
│ n8n                 │ ✅ user set      │ ✅ bind mount       │ OK after last fix                  │
├─────────────────────┼──────────────────┼─────────────────────┼────────────────────────────────────┤
│ LiteLLM             │ ⚠️ no user set   │ ✅ bind mount       │ Needs user: declaration            │
├─────────────────────┼──────────────────┼─────────────────────┼────────────────────────────────────┤
│ Caddy               │ ⚠️ must be root  │ ✅ bind mount       │ Port 80/443 requires root OR       │
│                     │ for ports <1024  │                     │ use CAP_NET_BIND_SERVICE instead   │
├─────────────────────┼──────────────────┼─────────────────────┼────────────────────────────────────┤
│ OpenClaw            │ ✅ non-root set  │ ✅ bind mount       │ AppArmor profile referenced but    │
│                     │                  │                     │ profile file not generated         │
├─────────────────────┼──────────────────┼─────────────────────┼────────────────────────────────────┤
│ Tailscale           │ ❌ needs NET_ADM │ ⚠️ partial          │ tailscale up never called          │
│                     │ CAP not root     │                     │ IP never retrieved                 │
├─────────────────────┼──────────────────┼─────────────────────┼────────────────────────────────────┤
│ Named Volumes       │ N/A              │ ❌ CRITICAL         │ Docker named volumes default to    │
│ (postgres,redis)    │                  │                     │ /var/lib/docker NOT /mnt/data      │
│                     │                  │                     │ Violates EBS-only data rule        │
└─────────────────────┴──────────────────┴─────────────────────┴────────────────────────────────────┘
```

---

### Table 3 — Cross-Service Linking Gaps

```
┌─────────────────────┬────────────┬────────────┬────────────────┬────────────┬────────────────────┐
│ SERVICE             │ OWN PG DB  │ REDIS LINK │ VECTOR DB LINK │ LITELLM    │ MINIO LINK         │
├─────────────────────┼────────────┼────────────┼────────────────┼────────────┼────────────────────┤
│ AnythingLLM         │ ❌ sqlite  │ ❌         │ ❌ NOT WIRED   │ ❌         │ ❌                 │
│ OpenWebUI           │ ❌ sqlite  │ ❌         │ ❌ NOT WIRED   │ ❌         │ ❌                 │
│ Dify                │ ✅ shared  │ ✅         │ ❌ NOT WIRED   │ ❌         │ ✅                 │
│ Flowise             │ ❌ sqlite  │ ❌         │ ❌ NOT WIRED   │ ❌         │ ❌                 │
│ LibreChat           │ ❌ needs   │ ❌         │ ❌ NOT WIRED   │ ❌         │ ❌                 │
│                     │ MongoDB    │            │                │            │                    │
│ LiteLLM             │ ✅ linked  │ ✅         │ ❌             │ N/A        │ ❌                 │
│ n8n                 │ ✅ linked  │ ❌         │ ❌             │ ❌         │ ❌                 │
│ Langfuse            │ ✅ shared  │ ❌         │ ❌             │ ❌         │ ❌                 │
│ Activepieces        │ ❌ MISSING │ ❌ MISSING │ ❌             │ ❌         │ ❌                 │
│ Mattermost          │ ❌ MISSING │ ❌         │ ❌             │ ❌         │ ⚠️ manual          │
│ Matrix              │ ❌ MISSING │ ❌         │ ❌             │ ❌         │ ❌                 │
│ Authentik           │ ❌ MISSING │ ❌ MISSING │ ❌             │ ❌         │ ❌                 │
│ Grafana             │ ❌         │ ❌         │ ❌             │ ❌         │ ❌                 │
│ OpenClaw            │ ❌         │ ❌         │ ❌ CRITICAL    │ ❌         │ ❌                 │
│ Firecrawl           │ ❌         │ ❌ MISSING │ ❌             │ ❌         │ ❌                 │
└─────────────────────┴────────────┴────────────┴────────────────┴────────────┴────────────────────┘
```

---

## Critical Gaps — Prioritised

```
CRITICAL — Will cause data loss or boot failure
────────────────────────────────────────────────────────────────

C1. NAMED VOLUMES NOT ON /mnt
    Docker named volumes (postgres, redis) default to
    /var/lib/docker/volumes — NOT on your EBS mount.
    On instance termination ALL postgres and redis data is lost.
    
    FIX in docker-compose.yml:
      volumes:
        postgres_data:
          driver: local
          driver_opts:
            type: none
            o: bind
            device: ${TENANT_ROOT}/postgres
        redis_data:
          driver: local
          driver_opts:
            type: none
            o: bind
            device: ${TENANT_ROOT}/redis
    
    Script 1 must mkdir -p these paths before compose runs.

C2. POSTGRES DATABASES NOT CREATED PER SERVICE
    n8n, dify, mattermost, matrix, authentik, langfuse,
    activepieces all need their own database.
    Currently only n8n and dify have any DB config.
    Others will fail to start or corrupt shared schema.
    
    FIX in Script 2 — after wait_for_postgres():
      create_db "n8n"        "n8n_user"
      create_db "dify"       "dify_user"
      create_db "langfuse"   "langfuse_user"
      create_db "mattermost" "mm_user"
      create_db "authentik"  "authentik_user"
      create_db "librechat"  "librechat_user"
      create_db "matrix"     "matrix_user"
      create_db "activepieces" "ap_user"
    
    Only create the DB if that service is ENABLE_X=true.

C3. TAILSCALE NEVER CALLS tailscale up
    Container starts but is never authenticated.
    TAILSCALE_IP is never populated.
    OpenClaw Caddy route points to empty variable.
    
    FIX in Script 2 after tailscale container starts:
      docker exec tailscale \
        tailscale up --authkey="${TAILSCALE_AUTH_KEY}" \
                     --hostname="${TAILSCALE_HOSTNAME}"
      TAILSCALE_IP=$(docker exec tailscale tailscale ip -4)
      append_env TAILSCALE_IP "${TAILSCALE_IP}"

C4. VECTOR DB NOT WIRED TO ANY AI SERVICE
    VECTOR_DB_TYPE is set but no service receives
    VECTOR_DB_URL, QDRANT_URL, or equivalent.
    AnythingLLM, OpenWebUI, OpenClaw all start with
    no vector DB connection — RAG is completely broken.
    
    FIX: Add to each AI service in compose:
      VECTOR_DB_TYPE: ${VECTOR_DB_TYPE}
      QDRANT_URL: http://qdrant:6333
      QDRANT_API_KEY: ${QDRANT_API_KEY:-}
      COLLECTION_NAME: ${COMPOSE_PROJECT_NAME}

C5. LIBRECHAT NEEDS MONGODB — NOT IN STACK
    LibreChat cannot use PostgreSQL.
    It requires MongoDB. No MongoDB in compose.
    LibreChat will fail to start every time.
    
    FIX OPTION A: Add MongoDB to compose
      mongodb:
        image: mongo:7
        user: "${STACK_USER_UID}:${STACK_USER_GID}"
        volumes:
          - ${TENANT_ROOT}/mongodb:/data/db
        only started when ENABLE_LIBRECHAT=true
    
    FIX OPTION B: Remove LibreChat from stack
      It duplicates OpenWebUI functionality.

HIGH — Will cause incorrect behaviour silently
────────────────────────────────────────────────────────────────

H1. LITELLM NOT OFFERED AS LLM BACKEND TO OTHER SERVICES
    When LiteLLM + AnythingLLM both selected, AnythingLLM
    still calls OpenAI directly. LiteLLM is unused.
    Same for OpenWebUI, Flowise, n8n, Dify.
    
    FIX: Script 1, after both are selected:
      If ENABLE_LITELLM=true AND ENABLE_X=true:
        LLM_BASE_URL=http://litellm:4000/v1
        LLM_API_KEY=${LITELLM_MASTER_KEY}
      Inject into every AI platform service in compose.

H2. GDRIVE NOT IN COMPOSE — NO INGESTION PATH
    rclone is mentioned in Script 1 but has no
    compose service, no mount path, no trigger
    to feed /mnt/data/gdrive into vector DB.
    
    FIX: Add rclone service to compose:
      rclone:
        image: rclone/rclone
        user: "${STACK_USER_UID}:${STACK_USER_GID}"
        volumes:
          - ${TENANT_ROOT}/rclone:/config/rclone
          - ${TENANT_ROOT}/gdrive:/mnt/gdrive
        command: mount gdrive: /mnt/gdrive --vfs-cache-mode writes
    
    AnythingLLM storage.documents path → /mnt/gdrive
    Dify dataset input path → /mnt/gdrive

H3. DIFY MISSING WORKER + SANDBOX CONTAINERS
    Dify API starts but workflow execution fails
    without dify-worker. Code execution fails
    without dify-sandbox.
    
    FIX: Add to compose:
      dify-worker: (same image, command: celery worker)
      dify-sandbox: (langgenius/dify-sandbox:latest)

H4. AUTHENTIK MISSING WORKER CONTAINER
    Authentik server starts but email, flows,
    and policy evaluation all require authentik-worker.
    SSO will appear to work but fail on first real use.
    
    FIX: Add authentik-worker to compose using same
    image and env, command: worker

H5. APPARMOR PROFILE REFERENCED BUT NOT GENERATED
    OpenClaw compose block references an AppArmor
    profile that is never written to disk.
    Container will fail to start if AppArmor is enforcing.
    
    FIX in Script 1 or Script 2:
      generate_apparmor_profile() and
      apparmor_parser -r profile_file

H6. PROMETHEUS HAS NO SCRAPE CONFIG
    prometheus.yml is never generated.
    Prometheus starts but scrapes nothing.
    Grafana datasource never provisioned.
    
    FIX: Script 2 generates prometheus.yml
    with scrape targets for each enabled service.
    Script 2 generates grafana/provisioning/datasources/prometheus.yml

MEDIUM — Operational gaps
────────────────────────────────────────────────────────────────

M1. SCRIPT 3 COVERS ~4 SERVICES OF 25+
    configure_litellm(), configure_n8n(),
    configure_anythingllm(), configure_openwebui()
    exist. Everything else has no reconfiguration path.
    
    MISSING reconfigure options for:
      SSL/Caddy, Tailscale re-auth, GDrive re-auth,
      Signal re-pair, Dify, Flowise, Grafana,
      Prometheus, Minio, Langfuse, Authentik,
      Mattermost, Matrix, OpenClaw

M2. SIGNAL PAIRING URL NOT SHOWN TO USER
    After signal-api starts, the pairing URL is
    never printed. User has no way to know where to go.
    
    FIX in Script 2 after signal-api healthy:
      echo "Signal pairing: http://${HOST_IP}:${SIGNAL_PORT}/v1/qrcodelink"

M3. CADDY RUNS AS ROOT FOR PORTS 80/443
    Caddy requires root or CAP_NET_BIND_SERVICE.
    Current compose has no user: set for Caddy.
    Should add: cap_add: [NET_BIND_SERVICE]
    and user: "${STACK_USER_UID}:${STACK_USER_GID}"
```

---

## Clean Action List for Windsurf

```
REMOVE IMMEDIATELY (reduces complexity, no user value):
  - Keycloak (Authentik covers SSO)
  - Temporal (no service in stack uses it)

ADD TO COMPOSE:
  - MongoDB (for LibreChat) OR remove LibreChat
  - rclone service (for GDrive mount)
  - dify-worker + dify-sandbox
  - authentik-worker
  - Named volume bind mounts to /mnt for postgres + redis

ADD TO SCRIPT 1:
  - TAILSCALE_AUTH_KEY prompt when OpenClaw selected
  - VECTOR_DB_URL construction after VectorDB selected
  - Signal pairing URL pre-announcement

ADD TO SCRIPT 2:
  - tailscale up + IP retrieval
  - create_service_database() called per enabled service
  - Vector DB env injection into AI services
  - LiteLLM URL injection when both LiteLLM + AI platform enabled
  - rclone OAuth flow + mount validation
  - prometheus.yml generation from enabled services
  - Signal pairing URL printed after signal-api healthy
  - AppArmor profile generation for OpenClaw

ADD TO SCRIPT 3:
  - [S] SSL/Caddy reconfigure
  - [T] Tailscale re-auth
  - [G] GDrive re-auth
  - [M] Signal re-pair
  - [D] Dify reconfigure
  - [F] Flowise reconfigure
  - [P] Prometheus/Grafana reconfigure
  - [A] Authentik reconfigure
  - Generic [service] restart/logs/test for all others
```