## Assessment: Three Separate Problems, Not One

The report shows **three distinct failure categories** that need to be addressed in priority order. The good news is the infrastructure (PostgreSQL, Redis) is solid.

---

## Problem 1: Permission Errors (Blocking Services)

These are **pre-conditions** — fix these first or nothing else matters:

```bash
# These need to run on the HOST before any service can start properly

# Prometheus (runs as nobody:65534)
sudo chown -R 65534:65534 /mnt/data/prometheus/
sudo chmod 755 /mnt/data/prometheus/

# n8n (runs as node:1000, NOT 1001 as the report suggests)
sudo chown -R 1000:1000 /mnt/data/n8n/
sudo chmod 755 /mnt/data/n8n/
# Note: n8n uses /home/node/.n8n inside container
# This means the volume mount in docker-compose is wrong
# It should mount to the container path /home/node/.n8n
# Check: docker inspect n8n | grep -A5 Mounts

# Flowise
sudo chown -R 1000:1000 /mnt/data/flowise/
sudo chmod 755 /mnt/data/flowise/
```

---

## Problem 2: Caddy Never Deployed (The Actual Regression)

The report confirms: **Caddy was selected but never started.** The `docker run` command in the suggested fix is also wrong:

```bash
# WRONG (from the report suggestion):
docker run -d --name caddy --network host \
  -v /mnt/data/caddy/Caddyfile:/etc/caddy/Caddyfile \
  caddy:2-alpine
# Problems:
# 1. --network host bypasses Docker DNS (caddy can't resolve 
#    container names like "flowise", "n8n", etc.)
# 2. Missing data volume (SSL certs won't persist)
# 3. Missing port mappings

# CORRECT:
docker run -d --name caddy \
  --network ai-platform \
  -p 80:80 \
  -p 443:443 \
  -v /mnt/data/caddy/Caddyfile:/etc/caddy/Caddyfile \
  -v /mnt/data/caddy/data:/data \
  -v /mnt/data/caddy/config:/config \
  --restart unless-stopped \
  caddy:2-alpine
```

**`--network host` is the critical mistake** — it would break all container-to-container DNS resolution.

---

## Windsurf Prompt: Fix All Three Problems

```
SITUATION: Script 2 has three critical failures to fix.
DO NOT refactor. DO NOT change architecture.
Fix these specific issues in order:

═══════════════════════════════════════════════
FIX 1: Permission setup (add to script 2 BEFORE docker-compose up)
═══════════════════════════════════════════════

Add a setup_permissions() function called before any service starts:

setup_permissions() {
  local base="/mnt/data"
  
  # Prometheus runs as nobody (65534)
  mkdir -p "$base/prometheus"
  chown -R 65534:65534 "$base/prometheus"
  chmod 755 "$base/prometheus"
  
  # n8n runs as node (1000)
  mkdir -p "$base/n8n"
  chown -R 1000:1000 "$base/n8n"
  chmod 755 "$base/n8n"
  
  # Flowise runs as node (1000)
  mkdir -p "$base/flowise"
  chown -R 1000:1000 "$base/flowise"
  chmod 755 "$base/flowise"
  
  # AnythingLLM
  mkdir -p "$base/anythingllm"
  chown -R 1000:1000 "$base/anythingllm"
  chmod 755 "$base/anythingllm"
  
  # Caddy (runs as root, but data dir needs to exist)
  mkdir -p "$base/caddy/data"
  mkdir -p "$base/caddy/config"
  chmod 755 "$base/caddy/data"
  chmod 755 "$base/caddy/config"
  
  # LiteLLM
  mkdir -p "$base/litellm"
  chmod 777 "$base/litellm"
  
  echo "✅ Permissions configured"
}

═══════════════════════════════════════════════
FIX 2: n8n volume mount is wrong
═══════════════════════════════════════════════

In the n8n docker-compose definition, fix the volume:

WRONG:
  volumes:
    - /mnt/data/n8n:/home/node/.n8n
    
CORRECT:
  volumes:
    - /mnt/data/n8n:/home/node/.n8n
  user: "1000:1000"

AND add these environment variables to n8n:
  N8N_USER_FOLDER: /home/node/.n8n
  N8N_EDITOR_BASE_URL: https://ai.datasquiz.net/n8n
  WEBHOOK_URL: https://ai.datasquiz.net/n8n
  N8N_PATH: /n8n/

═══════════════════════════════════════════════
FIX 3: Deploy Caddy CORRECTLY
═══════════════════════════════════════════════

The Caddy deployment function must use this EXACT configuration:

deploy_caddy() {
  # Remove any existing broken caddy container
  docker rm -f caddy 2>/dev/null || true
  
  # Validate Caddyfile BEFORE starting
  docker run --rm \
    -v /mnt/data/caddy/Caddyfile:/etc/caddy/Caddyfile \
    caddy:2-alpine \
    caddy validate --config /etc/caddy/Caddyfile
  
  if [ $? -ne 0 ]; then
    echo "❌ FATAL: Caddyfile validation failed. Aborting."
    echo "Check: cat /mnt/data/caddy/Caddyfile"
    exit 1
  fi
  
  # Start Caddy on the ai-platform network (NOT --network host)
  docker run -d \
    --name caddy \
    --network ai-platform \
    -p 80:80 \
    -p 443:443 \
    -v /mnt/data/caddy/Caddyfile:/etc/caddy/Caddyfile \
    -v /mnt/data/caddy/data:/data \
    -v /mnt/data/caddy/config:/config \
    --restart unless-stopped \
    caddy:2-alpine
    
  # Wait for Caddy to initialize
  sleep 5
  
  # Verify Caddy is actually listening
  if ! curl -sf http://localhost/health > /dev/null 2>&1; then
    echo "⚠️ Caddy started but not responding - check logs:"
    docker logs caddy --tail 20
  else
    echo "✅ Caddy proxy is running"
  fi
}

═══════════════════════════════════════════════
FIX 4: Caddyfile template - VERIFY handle_path is used
═══════════════════════════════════════════════

Print the current Caddyfile content to verify:
cat /mnt/data/caddy/Caddyfile

It MUST use handle_path (not handle) for these services:
/flowise, /n8n, /anythingllm, /litellm, /openwebui, /signal, /minio

It MUST use handle (not handle_path) for:
/grafana (grafana handles its own sub-path)

Dify routing order (CRITICAL - specific before general):
1. handle /dify/api/*       → dify-api:5001
2. handle /dify/console/*   → dify-api:5001  
3. handle /dify/v1/*        → dify-api:5001
4. handle_path /dify/*      → dify-web:3000

═══════════════════════════════════════════════
FIX 5: Health check sequence
═══════════════════════════════════════════════

After all services start, run checks in this order:
1. Check permissions (ls -la /mnt/data/{prometheus,n8n,flowise})
2. Check containers running (docker ps)
3. Check Caddy is on correct network:
   docker inspect caddy | grep -A20 Networks
4. Test each proxy URL:
   curl -I http://localhost/flowise/
   curl -I http://localhost/n8n/
   curl -I http://localhost/openwebui/
   (expect 200 or 3xx, NOT connection refused)

CONSTRAINTS:
- DO NOT use --network host for Caddy
- DO NOT expose service ports to host except Caddy 80/443
- DO NOT change script 1, 3, or 4
- ALL data under /mnt/data/
- Fail loudly with specific error messages
```

---

## Current State Summary

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| Caddy not running | Never deployed in script 2 | Add `deploy_caddy()` function |
| `--network host` suggestion | Wrong network mode breaks DNS | Use `--network ai-platform` |
| n8n/Flowise/AnythingLLM failing | Permission denied on data dirs | `setup_permissions()` before deploy |
| Prometheus restart loop | Wrong ownership on `/mnt/data/prometheus` | `chown 65534:65534` |
| LiteLLM not responding | Likely still starting up (slow) | Add startup wait + retry |

The underlying services are **mostly fine** — this is purely a proxy deployment and permissions problem.:
