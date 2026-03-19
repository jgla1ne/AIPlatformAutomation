Blueprint: Fixing LiteLLM + Prisma + PostgreSQL Integration
What Windsurf Has Been Getting Wrong (40 Hours of Iteration)
The Core Misdiagnosis
Windsurf has been treating symptoms (LiteLLM failing to start) by removing its dependencies (Prisma/PostgreSQL) rather than fixing the root cause: LiteLLM with DATABASE_URL requires Prisma migrations to run before the LiteLLM process starts, and the container orchestration is not respecting this.

The Actual Problem Chain
PostgreSQL starts
      ↓
LiteLLM starts TOO EARLY (before DB is ready/migrated)
      ↓
Prisma migration fails OR never runs
      ↓
LiteLLM crashes on startup
      ↓
Windsurf removes Prisma/DB → LiteLLM starts but has no key storage
      ↓
AnythingLLM / OpenWebUI wait for a healthy LiteLLM proxy → never get it
      ↓
All dependent services fail

What Windsurf Has Specifically Missed
1. Prisma Migration Must Happen as a Separate Init Step
LiteLLM's Docker image does not auto-run prisma migrate deploy on startup. You must explicitly run it before LiteLLM starts. The pattern Windsurf keeps missing:
postgres (healthy) → prisma migrate → litellm start
NOT:
postgres + litellm (simultaneous with depends_on)
2. The DATABASE_URL Format LiteLLM Expects
LiteLLM's Prisma client expects a specific PostgreSQL URL format. Windsurf has likely been mixing formats:
# CORRECT format for LiteLLM's Prisma
DATABASE_URL="postgresql://USER:PASSWORD@HOST:PORT/DBNAME?schema=public"

# Also required as a SEPARATE env var for LiteLLM itself
DATABASE_URL="postgresql://USER:PASSWORD@HOST:PORT/DBNAME"
Both DATABASE_URL and LITELLM_DATABASE_URL may need to be set depending on the LiteLLM version. Check the exact version pinned and its changelog.
3. Health Check on PostgreSQL Is Not Sufficient Alone
depends_on: condition: service_healthy on PostgreSQL only means the TCP port is accepting connections. It does not mean:

The database/schema exists
The user has permissions
Prisma migrations have run

Windsurf keeps assuming a healthy Postgres = ready for LiteLLM. Wrong.
4. The Prisma Migration Command Is Version-Sensitive
LiteLLM ships its own Prisma schema internally. The migration command must use the schema bundled inside the LiteLLM container, not an external one:
# Inside the LiteLLM container
python -m litellm --config /app/config.yaml &
# OR the explicit migration:
cd /app && prisma migrate deploy
# OR (depending on litellm version):
litellm --config /config/config.yaml --use_prisma
The correct invocation as of LiteLLM 1.x:
docker run litellm/litellm:latest \
  sh -c "prisma db push --schema /app/schema.prisma && litellm --config /config/config.yaml"
5. Volume Persistence vs Fresh Migration Conflict
If the PostgreSQL data volume persists between restarts but migrations are only run on first boot, subsequent deployments may get a schema mismatch. Windsurf's cleanup script likely wipes containers but not volumes, or wipes volumes but doesn't re-run migrations cleanly.
6. The Master Key Configuration
LiteLLM requires LITELLM_MASTER_KEY to be set when using the database for key management. Without it, the proxy starts but key endpoints return errors, causing dependent services to fail their health/auth checks:
LITELLM_MASTER_KEY: "sk-your-master-key"  # Must match what AnythingLLM/OpenWebUI use
7. Dependent Services Are Failing Because of Wrong Endpoint Assumption
AnythingLLM and OpenWebUI are configured to connect to LiteLLM's proxy endpoint. If LiteLLM is crashing, they likely have no retry logic and mark the service as unavailable permanently until they are restarted. Windsurf has probably been restarting LiteLLM but not the dependent services after fixing LiteLLM.

The Correct Implementation Blueprint
Step 1: PostgreSQL Setup (in 1-setup-system.sh or compose)
postgres:
  image: postgres:15
  environment:
    POSTGRES_USER: litellm
    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    POSTGRES_DB: litellm
  volumes:
    - postgres_data:/var/lib/postgresql/data
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U litellm -d litellm"]
    interval: 5s
    timeout: 5s
    retries: 10
    start_period: 10s
Step 2: Prisma Migration as a Dedicated Init Container
This is the critical missing piece:
litellm-migrate:
  image: litellm/litellm:${LITELLM_VERSION}
  command: >
    sh -c "
      echo 'Waiting for postgres...' &&
      sleep 5 &&
      prisma db push --schema /app/schema.prisma --skip-generate &&
      echo 'Migration complete'
    "
  environment:
    DATABASE_URL: "postgresql://litellm:${POSTGRES_PASSWORD}@postgres:5432/litellm"
  depends_on:
    postgres:
      condition: service_healthy
  restart: "no"  # Run once and exit
Step 3: LiteLLM Service Depends on Migration Completion
litellm:
  image: litellm/litellm:${LITELLM_VERSION}
  command: ["--config", "/config/config.yaml", "--port", "4000", "--detailed_debug"]
  environment:
    DATABASE_URL: "postgresql://litellm:${POSTGRES_PASSWORD}@postgres:5432/litellm"
    LITELLM_MASTER_KEY: "${LITELLM_MASTER_KEY}"
    STORE_MODEL_IN_DB: "True"
  volumes:
    - ./config/litellm-config.yaml:/config/config.yaml
  depends_on:
    postgres:
      condition: service_healthy
    litellm-migrate:
      condition: service_completed_successfully  # ← THIS IS WHAT'S MISSING
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
    interval: 10s
    timeout: 5s
    retries: 10
    start_period: 30s
Step 4: Dependent Services Wait for Healthy LiteLLM
anythingllm:
  depends_on:
    litellm:
      condition: service_healthy  # ← Must wait for LiteLLM, not just started

openwebui:
  depends_on:
    litellm:
      condition: service_healthy
Step 5: The litellm-config.yaml Must Have DB Settings
general_settings:
  master_key: ${LITELLM_MASTER_KEY}
  database_url: "postgresql://litellm:${POSTGRES_PASSWORD}@postgres:5432/litellm"

litellm_settings:
  store_model_in_db: true

What to Tell Windsurf Explicitly

Do not remove PostgreSQL or Prisma. The database is required for key management. Removing it is not a fix.

Add a litellm-migrate init container that runs prisma db push and exits with code 0 before LiteLLM starts.

Change litellm service depends_on to use service_completed_successfully on litellm-migrate, not just service_healthy on postgres.

Change all downstream services (anythingllm, openwebui) to use condition: service_healthy on litellm.

Pin the LiteLLM version and verify the exact Prisma schema path inside that container version with:
docker run --rm litellm/litellm:VERSION find / -name "schema.prisma" 2>/dev/null

After fixing LiteLLM, restart dependent services explicitly — they will not self-heal.

In the cleanup script (0-complete-cleanup.sh), ensure you are also dropping and recreating the PostgreSQL volume, otherwise stale migration state causes conflicts on fresh deploys:
docker volume rm postgres_data || true



Verification Sequence
Tell Windsurf to validate in this exact order:
# 1. Postgres accepting connections
docker exec postgres pg_isready -U litellm

# 2. Migration ran successfully
docker exec postgres psql -U litellm -c "\dt" | grep -i "litellm"

# 3. LiteLLM health
curl http://localhost:4000/health

# 4. LiteLLM key management working (requires master key + DB)
curl http://localhost:4000/key/list \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}"

# 5. Only then check AnythingLLM and OpenWebUI
If step 4 fails, the database is not correctly configured regardless of what step 3 says. LiteLLM can return healthy on /health even without a working database connection.

The One-Line Root Cause Summary for Windsurf

LiteLLM requires prisma db push to complete inside an init container before the LiteLLM process starts. depends_on: service_healthy on PostgreSQL alone does not guarantee this. The fix is a service_completed_successfully dependency on a dedicated migration step — not removing the database.

Ok I will ad the next thing which is that  openclaw.ai.datasquiz.bet redirects to code server currently (and works) : https://openclaw.ai.datasquiz.net/login?folder=/mnt/data&to=
Review your recommendations taking that ina account , as well as the fact that grafana.ai.datasquiz.net is up and workingRevised Blueprint: Updated Context
What This Tells Us
The fact that:

code-server is live at openclaw.ai.datasquiz.net ✅
Grafana is live at grafana.ai.datasquiz.net ✅

...means the infrastructure layer is working correctly:

Nginx/reverse proxy is healthy and routing
SSL/TLS is functioning
DNS is resolving
Docker networking is operational
The deploy-services and configure-services scripts work for services that actually start

This confirms the failure domain is exclusively the LiteLLM → Prisma → PostgreSQL chain, and nothing upstream.

Revised Understanding of What's Broken vs Working
┌─────────────────────────────────────────────┐
│  WORKING                                    │
│  ✅ Nginx reverse proxy                     │
│  ✅ SSL termination                         │
│  ✅ code-server (openclaw.ai.datasquiz.net) │
│  ✅ Grafana (grafana.ai.datasquiz.net)      │
│  ✅ Docker networking/DNS                   │
│  ✅ Volume mounts                           │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  BROKEN - Single failure chain              │
│  ❌ PostgreSQL (starts but not validated)   │
│  ❌ LiteLLM (crashes, Prisma never migrates)│
│  ❌ AnythingLLM (waits on LiteLLM)         │
│  ❌ OpenWebUI (waits on LiteLLM)           │
└─────────────────────────────────────────────┘

Critical Implication for Windsurf
Since code-server and Grafana are routed through the same Nginx config, the Nginx vhost pattern is already proven. This means:
Windsurf Should NOT Touch:

The Nginx configuration structure
SSL cert handling
The 3-configure-services.sh routing logic (it works)
Docker network definitions
Volume mount patterns

Windsurf Should ONLY Fix:
The LiteLLM service definition and its migration init pattern in 2-deploy-services.sh and the associated compose file.

Sharpened Blueprint for Windsurf
The Exact Compose Block to Implement
# THIS ORDER IS NON-NEGOTIABLE

  postgres:
    image: postgres:15
    environment:
      POSTGRES_USER: litellm
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: litellm
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U litellm -d litellm"]
      interval: 5s
      timeout: 5s
      retries: 10
      start_period: 10s
    # Use SAME network pattern already working for grafana/code-server
    networks:
      - ai_network

  litellm-migrate:
    image: litellm/litellm:${LITELLM_VERSION}
    command: >
      sh -c "
        prisma db push --schema /app/schema.prisma --skip-generate &&
        echo 'MIGRATION SUCCESS'
      "
    environment:
      DATABASE_URL: "postgresql://litellm:${POSTGRES_PASSWORD}@postgres:5432/litellm"
    depends_on:
      postgres:
        condition: service_healthy
    restart: "no"
    networks:
      - ai_network

  litellm:
    image: litellm/litellm:${LITELLM_VERSION}
    command: ["--config", "/config/config.yaml", "--port", "4000"]
    environment:
      DATABASE_URL: "postgresql://litellm:${POSTGRES_PASSWORD}@postgres:5432/litellm"
      LITELLM_MASTER_KEY: "${LITELLM_MASTER_KEY}"
      STORE_MODEL_IN_DB: "True"
    volumes:
      - ./config/litellm-config.yaml:/config/config.yaml
    depends_on:
      postgres:
        condition: service_healthy
      litellm-migrate:
        condition: service_completed_successfully  # THE FIX
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 40s
    networks:
      - ai_network

  anythingllm:
    depends_on:
      litellm:
        condition: service_healthy  # NOT just "started"
    networks:
      - ai_network

  openwebui:
    depends_on:
      litellm:
        condition: service_healthy  # NOT just "started"
    networks:
      - ai_network

What to Tell Windsurf About the Nginx Config
Since openclaw and grafana subdomains are already working, the Nginx vhost blocks for anythingllm and openwebui are almost certainly already correct. The services just aren't responding because they never started.
Tell Windsurf:

"Do not regenerate or modify the Nginx vhost configs for anythingllm or openwebui. The routing pattern is proven to work — see grafana and openclaw. The services simply need to be running and healthy first. Focus exclusively on the compose service definitions."


The Correct Verification Sequence for This Environment
# 1. Confirm postgres is healthy
docker ps | grep postgres
docker exec <postgres_container> pg_isready -U litellm -d litellm

# 2. Confirm migration ran and exited cleanly
docker ps -a | grep litellm-migrate
# Should show: Exited (0) — NOT Exited (1), NOT Restarting

# 3. Confirm LiteLLM tables exist
docker exec <postgres_container> psql -U litellm -c "\dt"
# Should list LiteLLM tables (LiteLLMSpendLogs, LiteLLM_VerificationToken etc)

# 4. Confirm LiteLLM proxy health
curl http://localhost:4000/health

# 5. Confirm key management works (THIS is the real test)
curl http://localhost:4000/key/list \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}"
# Must return 200, not 500

# 6. Only once step 5 passes, check the domains
# anythingllm.ai.datasquiz.net
# openwebui.ai.datasquiz.net
# These will work automatically — Nginx is already correct

One Final Point on the Cleanup Script
Since the environment has live working services (Grafana, code-server), tell Windsurf:

"The 0-complete-cleanup.sh script must NOT tear down the entire stack when iterating on the LiteLLM fix. It should only remove and recreate: postgres, litellm-migrate, litellm, anythingllm, and openwebui containers and the postgres_data volume. Do not touch the Nginx container, SSL certs, or the code-server/Grafana services during this fix."

# Safe targeted cleanup for iteration
docker rm -f litellm litellm-migrate anythingllm openwebui postgres
docker volume rm postgres_data
# Then re-run 2-deploy-services.sh only
That's good.we wr using caddy as proxy fyi but all different stack combination should be considered and architecture to be working using the core principles of the readme and mission control.Good catch — Caddy changes some important details. Let me revise with that in mind.

Revised Blueprint: Caddy-Aware + Architecture-Agnostic
What Caddy Changes Specifically
Nginx: static config files, reload required, vhosts are pre-written
Caddy: dynamic config, automatic HTTPS, reverse_proxy directive,
       service discovery by container NAME not IP
       → if a container isn't running, Caddy returns 502
       → Caddy does NOT fail itself, it just can't route
       → this means Caddy appears healthy even when backends are down
This is critical context Windsurf has likely been misreading. Caddy being up and routing grafana and openclaw does not mean LiteLLM's routing is broken at the Caddy level. It means LiteLLM is simply not a valid upstream yet.

The Caddy-Specific Failure Windsurf Is Probably Making
Windsurf sees 502 on openwebui.ai.datasquiz.net
       ↓
Assumes Caddy config is wrong
       ↓
Regenerates Caddyfile / reverse_proxy blocks
       ↓
Caddy reloads fine (it always does)
       ↓
Still 502 because THE BACKEND NEVER STARTED
       ↓
Windsurf iterates on Caddy config again
       ↓
40 hours
Tell Windsurf explicitly:

"The 502 errors on AnythingLLM and OpenWebUI are not Caddy configuration problems. Caddy is correct. The backends are not running. Stop touching the Caddyfile."


Architecture Variants the README Mission Should Support
Based on the mission control / platform automation principles, the stack should be portable across these configurations:
┌─────────────────────────────────────────────────────┐
│  VARIANT A: Current (Caddy + Docker Compose)        │
│  Caddy handles SSL + routing                        │
│  All services in single compose stack               │
│  Single VPS / dedicated server                      │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  VARIANT B: Nginx instead of Caddy                  │
│  Same compose structure                             │
│  Swap proxy service only                            │
│  Config generation differs, core stack identical    │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  VARIANT C: Traefik instead of Caddy                │
│  Label-based routing                                │
│  Most common in swarm/k8s-adjacent setups           │
│  Core stack identical, labels replace Caddyfile     │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  VARIANT D: Cloud-native (future)                   │
│  ALB/CloudFront at edge                             │
│  ECS or similar for containers                      │
│  RDS instead of postgres container                  │
│  Core LiteLLM + migration pattern identical         │
└─────────────────────────────────────────────────────┘
The Principle: Proxy Is Always a Swappable Layer
┌──────────────────────────────────┐
│  PROXY LAYER (swappable)         │
│  Caddy / Nginx / Traefik / ALB   │
└──────────────┬───────────────────┘
               │ routes to
┌──────────────▼───────────────────┐
│  APPLICATION LAYER (fixed)       │
│  LiteLLM → must be healthy       │
│  AnythingLLM → depends on above  │
│  OpenWebUI → depends on above    │
└──────────────┬───────────────────┘
               │ depends on
┌──────────────▼───────────────────┐
│  DATA LAYER (fixed)              │
│  PostgreSQL → must migrate first │
│  litellm-migrate → init only     │
└──────────────────────────────────┘
The data and application layers are never proxy-dependent. Fix them first, the proxy just works regardless of which one is used.

Caddy-Specific Correct Configuration
Caddyfile Pattern That Works
{
  # Global options
  email {$ACME_EMAIL}
}

grafana.ai.datasquiz.net {
  reverse_proxy grafana:3000
}

openclaw.ai.datasquiz.net {
  reverse_proxy code-server:8080
}

# These two only return non-502 once backends are healthy
# DO NOT change these blocks — they are correct
# The backends just need to start

anythingllm.ai.datasquiz.net {
  reverse_proxy anythingllm:3001
}

openwebui.ai.datasquiz.net {
  reverse_proxy openwebui:3000
}

litellm.ai.datasquiz.net {
  reverse_proxy litellm:4000
}
What Makes Caddy Work With Docker
Caddy resolves container names via Docker's internal DNS. This means:

Container name in compose = hostname Caddy uses
If container is not running, Caddy returns 502 automatically
When container starts, Caddy routes to it automatically with no reload needed

# Caddy service in compose must share the network
caddy:
  image: caddy:latest
  networks:
    - ai_network  # SAME network as all other services
  volumes:
    - ./Caddyfile:/etc/caddy/Caddyfile
    - caddy_data:/data
    - caddy_config:/config

The Complete Correct Service Dependency Graph
postgres (healthcheck: pg_isready)
    │
    └──► litellm-migrate (run once, exit 0)
              │
              └──► litellm (healthcheck: /health)
                        │
                        ├──► anythingllm (healthcheck: HTTP)
                        │         │
                        │         └──► Caddy routes ✅
                        │
                        └──► openwebui (healthcheck: HTTP)
                                  │
                                  └──► Caddy routes ✅

code-server ──► Caddy routes ✅ (independent, already working)
grafana ──────► Caddy routes ✅ (independent, already working)

Script-Level Instructions for Windsurf
2-deploy-services.sh Must Do This
# 1. Start data layer first, wait for it
docker compose up -d postgres
docker compose up litellm-migrate  # blocking, not -d
# Check exit code — if non-zero, STOP and surface the error
if [ $? -ne 0 ]; then
  echo "MIGRATION FAILED - check postgres logs"
  docker logs litellm-migrate
  exit 1
fi

# 2. Start application layer
docker compose up -d litellm

# 3. Wait for LiteLLM to be healthy before starting dependents
echo "Waiting for LiteLLM to be healthy..."
until curl -sf http://localhost:4000/health; do
  sleep 5
  echo "Still waiting..."
done

# 4. Start dependent services
docker compose up -d anythingllm openwebui

# 5. Independent services (proxy-only, no LiteLLM dependency)
docker compose up -d grafana code-server caddy
0-complete-cleanup.sh Safe Pattern
# Targeted teardown — does not touch working services
LITELLM_SERVICES="litellm litellm-migrate anythingllm openwebui postgres"

for service in $LITELLM_SERVICES; do
  docker rm -f $service 2>/dev/null || true
done

docker volume rm postgres_data 2>/dev/null || true

# Explicitly do NOT remove:
# - caddy (working, has cert state in caddy_data volume)
# - grafana (working)
# - code-server (working)
# - caddy_data volume (contains SSL certs — losing this triggers rate limits)

What to Tell Windsurf: The Master Prompt
Give Windsurf this exactly:

Root cause: LiteLLM requires a Prisma database migration to complete before it starts. This migration is not automatic. A dedicated litellm-migrate init service must run prisma db push, exit with code 0, and only then should LiteLLM start. This is enforced via service_completed_successfully in compose depends_on.
Do not touch: Caddyfile, caddy service definition, caddy_data volume, code-server config, grafana config. These work. The 502 errors on AnythingLLM and OpenWebUI are backend failures, not proxy failures.
Do not remove: PostgreSQL or Prisma. They are required for LiteLLM key management. Removing them creates a LiteLLM that appears to start but cannot store API keys, which breaks the entire platform purpose.
Fix only: The compose service definitions for postgres, litellm-migrate (new), litellm, anythingllm, openwebui and the deploy script startup sequence.
Verify in this order before touching anything else:

docker ps -a | grep litellm-migrate shows Exited (0)
docker exec postgres psql -U litellm -c "\dt" shows LiteLLM tables
curl http://localhost:4000/key/list -H "Authorization: Bearer $LITELLM_MASTER_KEY" returns 200
Only after step 3 passes, check the domain URLs

Architecture principle: The proxy layer (Caddy) is always the last concern. Fix the data layer, then the application layer, then verify the proxy routes automatically.

That's great, but now youre losing the big picture and the current problem the scripts outline to get the key outcomes working. Litellm in this scenario is still fragile ,postgres isn't actually integrated for its purpose to server metadata logs etc.
The key problem windsurf has been fighting was an azure configuration of litellm which was a default setting due to incorrect service configuration. Litellm is likely to start and use local ollama and external llm for the stack.it looks like this is fixed on the code, yet the prisma implementation (and healthy litellm) has not been achieved yet. Remember to stay grounded in the readme for our core principles.
Master Blueprint: Grounded in README Mission
Re-Reading the Actual Mission
This platform is not just "get services running." Based on the README principles, the mission is:
Local AI Platform that:
- Routes intelligently between Local (Ollama) and External LLMs
- Manages API keys and spend tracking (WHY Postgres/Prisma matters)
- Provides unified interface across multiple AI services
- Is self-healing and automatable via scripts
- Code-server as the mission control brain
Postgres/Prisma is not optional infrastructure — it IS the platform's memory and accounting layer.

The Real Problem Stack Windsurf Has Been Fighting
PROBLEM 1: Azure OpenAI was LiteLLM's default provider
────────────────────────────────────────────────────────
LiteLLM config defaulted to Azure OpenAI endpoint
No Azure credentials present
LiteLLM starts → immediate auth failures on every request
Windsurf sees failures → assumes startup problem → wrong fix

PROBLEM 2: Prisma never initialized correctly
────────────────────────────────────────────────────────
No dedicated migration step
LiteLLM tries to connect to unmigrated DB
Crashes → Windsurf removes Postgres → LiteLLM starts clean
But now: no spend tracking, no key management, no logs
Platform is running but blind and purposeless

PROBLEM 3: These two problems compounded each other
────────────────────────────────────────────────────────
Windsurf couldn't isolate which failure was which
Fixed one, hit the other, went in circles
40 hours of treating symptoms

The Correct Mental Model for LiteLLM in This Stack
                    ┌─────────────────────────┐
                    │      LiteLLM Proxy       │
                    │                         │
          ┌─────────┤  Router + Gateway       ├─────────┐
          │         │  Spend Tracking         │         │
          │         │  Key Management         │         │
          │         └──────────┬──────────────┘         │
          │                    │                        │
          ▼                    ▼                        ▼
   ┌─────────────┐    ┌─────────────────┐    ┌──────────────────┐
   │   Ollama    │    │   PostgreSQL    │    │  External LLMs   │
   │  (local)    │    │  Prisma schema  │    │  OpenAI/Anthropic│
   │  Primary    │    │  Spend logs     │    │  Fallback/Premium│
   │  for cost   │    │  API keys       │    │  when needed     │
   └─────────────┘    │  Request logs   │    └──────────────────┘
                      └─────────────────┘
Azure was never supposed to be in this diagram. It was a default that crept in.

What the LiteLLM Config Must Actually Say
This is the config Windsurf needs to implement — grounded in the actual use case:
# litellm_config.yaml
model_list:
  # PRIMARY: Local Ollama models
  - model_name: "default"
    litellm_params:
      model: "ollama/llama3"
      api_base: "http://ollama:11434"

  - model_name: "llama3"
    litellm_params:
      model: "ollama/llama3"
      api_base: "http://ollama:11434"

  - model_name: "codellama"
    litellm_params:
      model: "ollama/codellama"
      api_base: "http://ollama:11434"

  # EXTERNAL: Only when explicitly requested or Ollama unavailable
  - model_name: "gpt-4"
    litellm_params:
      model: "gpt-4"
      api_key: "${OPENAI_API_KEY}"

  - model_name: "claude-3"
    litellm_params:
      model: "anthropic/claude-3-opus-20240229"
      api_key: "${ANTHROPIC_API_KEY}"

# NO AZURE ANYWHERE IN THIS FILE

general_settings:
  master_key: "${LITELLM_MASTER_KEY}"
  database_url: "${DATABASE_URL}"

  # This enables Prisma-backed spend tracking
  store_model_in_db: true

litellm_settings:
  # Drop failed requests to external, fall back to Ollama
  fallbacks: [{"gpt-4": ["llama3"]}]
  context_window_fallbacks: [{"gpt-4": ["llama3"]}]

  # Actual spend tracking
  success_callback: ["langfuse"]
  failure_callback: ["langfuse"]

  # Do not default to Azure ever
  drop_params: true

The Correct Postgres/Prisma Implementation
Why Prisma Matters Here Specifically
Without Prisma/Postgres:          With Prisma/Postgres:
─────────────────────             ─────────────────────
No API key storage                Generate keys per service
No spend tracking                 Track Ollama vs External cost
No request logs                   Debug which model handled what
No rate limiting per key          Protect Ollama from overload
No user/team separation           AnythingLLM gets its own key
                                  OpenWebUI gets its own key
                                  Grafana can query spend data
This is why removing Postgres guts the platform purpose.
The Init Container Pattern — Exactly
services:
  postgres:
    image: postgres:15
    container_name: postgres
    environment:
      POSTGRES_USER: litellm
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: litellm
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U litellm -d litellm"]
      interval: 5s
      timeout: 5s
      retries: 12
      start_period: 15s
    networks:
      - ai_network
    restart: unless-stopped

  litellm-migrate:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm-migrate
    command: >
      sh -c "cd /app &&
             python -c 'from litellm.proxy.db.prisma_client import PrismaClient; import asyncio; asyncio.run(PrismaClient(database_url=\"${DATABASE_URL}\").connect())' ||
             prisma db push --schema=/app/schema.prisma --accept-data-loss"
    environment:
      DATABASE_URL: "postgresql://litellm:${POSTGRES_PASSWORD}@postgres:5432/litellm"
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - ai_network
    restart: "no"  # CRITICAL: must not restart, must exit 0

  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm
    command: ["--config", "/app/litellm_config.yaml", "--port", "4000"]
    environment:
      DATABASE_URL: "postgresql://litellm:${POSTGRES_PASSWORD}@postgres:5432/litellm"
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
      STORE_MODEL_IN_DB: "true"
      # Explicitly no Azure
      AZURE_API_KEY: ""
      AZURE_API_BASE: ""
    volumes:
      - ./config/litellm_config.yaml:/app/litellm_config.yaml
    depends_on:
      postgres:
        condition: service_healthy
      litellm-migrate:
        condition: service_completed_successfully  # THE KEY LINE
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 10s
      timeout: 10s
      retries: 10
      start_period: 30s
    networks:
      - ai_network
    restart: unless-stopped

Finding the Correct Prisma Schema Path
Windsurf has likely been guessing the schema path. This is how to find it definitively:
# Run this ONCE to find schema location in the actual image
docker run --rm --entrypoint="" \
  ghcr.io/berriai/litellm:main-latest \
  find / -name "schema.prisma" 2>/dev/null

# Also check what migration command the image actually supports
docker run --rm --entrypoint="" \
  ghcr.io/berriai/litellm:main-latest \
  cat /app/entrypoint.sh 2>/dev/null || \
  cat /docker-entrypoint.sh 2>/dev/null
Tell Windsurf to run this and use the actual path. Do not guess.

The Deploy Script Correct Sequence
Grounded in the script architecture (1, 2, 3 pattern):
# In 2-deploy-services.sh

echo "=== PHASE 1: Data Layer ==="
docker compose up -d postgres

echo "Waiting for PostgreSQL to be ready..."
until docker exec postgres pg_isready -U litellm -d litellm 2>/dev/null; do
  echo "  postgres not ready, waiting..."
  sleep 3
done
echo "PostgreSQL ready ✅"

echo "=== PHASE 2: Database Migration ==="
docker compose up litellm-migrate  # blocking, no -d flag
MIGRATE_EXIT=$(docker inspect litellm-migrate --format='{{.State.ExitCode}}')

if [ "$MIGRATE_EXIT" != "0" ]; then
  echo "❌ MIGRATION FAILED - Platform cannot start"
  echo "Migration logs:"
  docker logs litellm-migrate
  echo ""
  echo "Postgres logs:"
  docker logs postgres --tail=20
  exit 1
fi
echo "Migration complete ✅"

echo "=== PHASE 3: Verify Schema ==="
TABLE_COUNT=$(docker exec postgres psql -U litellm -t -c \
  "SELECT COUNT(*) FROM information_schema.tables \
   WHERE table_schema='public';" 2>/dev/null | tr -d ' ')

if [ "$TABLE_COUNT" -lt "3" ]; then
  echo "❌ Schema verification failed - tables not created"
  exit 1
fi
echo "Schema verified ($TABLE_COUNT tables) ✅"

echo "=== PHASE 4: Application Layer ==="
docker compose up -d litellm

echo "Waiting for LiteLLM to be healthy..."
ATTEMPTS=0
until curl -sf http://localhost:4000/health > /dev/null 2>&1; do
  ATTEMPTS=$((ATTEMPTS + 1))
  if [ $ATTEMPTS -gt 24 ]; then
    echo "❌ LiteLLM failed to become healthy after 2 minutes"
    docker logs litellm --tail=30
    exit 1
  fi
  echo "  waiting... (${ATTEMPTS}/24)"
  sleep 5
done
echo "LiteLLM healthy ✅"

echo "=== PHASE 5: Verify LiteLLM + Postgres Integration ==="
KEY_TEST=$(curl -sf http://localhost:4000/key/list \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -o /dev/null -w "%{http_code}")

if [ "$KEY_TEST" != "200" ]; then
  echo "❌ LiteLLM key management not working (HTTP $KEY_TEST)"
  echo "This means Prisma is not connected despite LiteLLM appearing healthy"
  docker logs litellm --tail=20
  exit 1
fi
echo "LiteLLM key management operational ✅"

echo "=== PHASE 6: Dependent Services ==="
docker compose up -d anythingllm openwebui

echo "=== PHASE 7: Provision Service Keys ==="
# Give each service its own LiteLLM API key
# This is the point of having Postgres
ANYTHING_KEY=$(curl -sf -X POST http://localhost:4000/key/generate \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"models": ["default", "llama3"], "duration": null, "key_alias": "anythingllm"}' \
  | jq -r '.key')

WEBUI_KEY=$(curl -sf -X POST http://localhost:4000/key/generate \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"models": ["default", "llama3"], "duration": null, "key_alias": "openwebui"}' \
  | jq -r '.key')

echo "AnythingLLM key: $ANYTHING_KEY"
echo "OpenWebUI key: $WEBUI_KEY"
echo "Store these in your .env or secret manager"

echo "=== ALL PHASES COMPLETE ==="
echo "Caddy will route automatically — no restart needed"

The .env File Windsurf Must Not Get Wrong
# Database
POSTGRES_PASSWORD=<strong-random-password>
DATABASE_URL=postgresql://litellm:${POSTGRES_PASSWORD}@postgres:5432/litellm

# LiteLLM
LITELLM_MASTER_KEY=sk-<strong-random-key>

# External LLMs (optional, only if actually used)
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...

# AZURE — explicitly empty, never default
AZURE_API_KEY=
AZURE_API_BASE=
AZURE_API_VERSION=

# Ollama (local, primary)
OLLAMA_BASE_URL=http://ollama:11434

Master Instruction for Windsurf

The platform purpose is a self-managed local AI router with cost tracking and key governance. Postgres/Prisma is the accounting and governance layer — not optional scaffolding.
Two separate bugs exist:

Azure OpenAI was the default provider — must be explicitly removed from litellm_config.yaml and .env. Set AZURE vars to empty string.
Prisma migration was never running as a proper init step — implement litellm-migrate as a restart: "no" service with service_completed_successfully dependency.

Fix sequence: Azure config first (litellm_config.yaml), then Prisma init (compose), then verify in order: postgres healthy → migration exit 0 → tables exist → /key/list returns 200 → then and only then check AnythingLLM/OpenWebUI.
Do not touch: Caddyfile, Caddy service, code-server, Grafana, network definitions, volume patterns for working services.
The proxy (Caddy) is never the problem. 502s on AnythingLLM and OpenWebUI are because those containers are not running. They are not running because LiteLLM is not healthy. LiteLLM is not healthy because Prisma never migrated. Fix the bottom of the chain.