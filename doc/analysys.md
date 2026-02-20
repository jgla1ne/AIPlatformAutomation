# Diagnosis: The Problem with the "100% Complete" Report

The document is **a success theater report** — it describes what *should* work conceptually but the actual proxy configurations have real bugs. Let me diagnose the specific issues.

---

## Root Cause Analysis

The report says "Caddy configuration generation ready" but the **actual Caddyfile blocks being generated are broken**. Here's why each service fails:

---

## Specific Proxy Configuration Bugs

### Bug 1: Sub-path Stripping — The Core Issue

```
# WHAT'S LIKELY BEING GENERATED (BROKEN):
https://ai.datasquiz.net {
    handle /flowise/* {
        reverse_proxy flowise:3000
    }
}

# PROBLEM: 
# Request comes in as: /flowise/api/something
# Gets forwarded as:   /flowise/api/something  ← prefix NOT stripped
# Service expects:     /api/something
```

```
# CORRECT Caddy syntax:
https://ai.datasquiz.net {
    handle_path /flowise/* {      # ← handle_path strips the prefix
        reverse_proxy flowise:3000
    }
}
```

**`handle` vs `handle_path` is the critical difference in Caddy.**

---

### Bug 2: Service-Specific Path Awareness

Some services are **not sub-path aware** and need the prefix kept OR need internal config:

```
# Services that CAN strip prefix (handle_path works):
flowise     ✓ (with FLOWISE_BASE_PATH env)
n8n         ✓ (with N8N_PATH env)  
litellm     ✓ (stateless API)
signal      ✓ (stateless API)

# Services that CANNOT have prefix stripped without app config:
grafana     ← needs GF_SERVER_ROOT_URL + serve_from_sub_path=true
minio       ← needs MINIO_BROWSER_REDIRECT_URL
dify        ← complex: frontend + API + worker are separate containers
anythingllm ← needs APP_BASE_PATH env
openwebui   ← needs WEBUI_BASE_URL env (likely missing from implementation)
```

---

### Bug 3: Dify Multi-Container Routing (Almost Certainly Broken)

```
# Dify is NOT a single container — it needs:
handle_path /dify/* {
    reverse_proxy dify-web:3000        # Frontend
}

handle_path /dify/api/* {
    reverse_proxy dify-api:5001         # API backend
}

handle_path /dify/console/api/* {
    reverse_proxy dify-api:5001
}

handle /dify/v1/* {
    reverse_proxy dify-api:5001
}

# The ORDER matters — more specific paths must come FIRST
# If /dify/* catches everything, /dify/api/* never matches
```

---

### Bug 4: WebSocket Handling in Caddy

```
# Caddy handles WebSockets automatically BUT only if:
# 1. The Connection/Upgrade headers are passed through
# 2. The timeout is sufficient

# BROKEN (likely generated):
handle_path /n8n/* {
    reverse_proxy n8n:5678
}

# CORRECT:
handle_path /n8n/* {
    reverse_proxy n8n:5678 {
        transport http {
            keepalive 86400s
            keepalive_idle_conns 10
        }
        header_up Connection {http.request.header.Connection}
        header_up Upgrade {http.request.header.Upgrade}
    }
}
```

---

### Bug 5: MinIO Dual-Port Problem

```
# MinIO has TWO ports:
# 9000 = API/data port
# 9001 = Console (web UI) port

# If only 9001 is proxied but API calls go to /minio/api → broken uploads
# Correct setup:

handle_path /minio/* {
    reverse_proxy minio:9001    # Console UI
}

# MinIO API should be direct or separately handled:
handle_path /minio-api/* {
    reverse_proxy minio:9000    # S3 API
}
```

---

## The Fix: Windsurf Implementation Instructions

### Step 1: Fix `nginx-generator.sh` (or `caddy-generator.sh`)

Tell Windsurf to **replace** the entire config generation with this verified template:

```bash
# /mnt/data/scripts/lib/caddy-generator.sh

generate_caddy_config() {
  local manifest="/mnt/data/config/installed_services.json"
  local caddyfile="/mnt/data/caddy/Caddyfile"
  
  mkdir -p "$(dirname "$caddyfile")"
  
  cat > "$caddyfile" << 'CADDY_HEADER'
{
    email admin@datasquiz.net
    admin off
}

https://ai.datasquiz.net {
    tls {
        protocols tls1.2 tls1.3
    }

CADDY_HEADER

  # ── Read manifest and generate only installed services ──

  # FLOWISE
  if is_installed "flowise" "$manifest"; then
    cat >> "$caddyfile" << 'EOF'
    # Flowise - handle_path strips /flowise prefix
    handle_path /flowise/* {
        reverse_proxy flowise:3000 {
            header_up Host {upstream_hostport}
            header_up X-Forwarded-Proto https
            header_up X-Real-IP {remote_host}
        }
    }
EOF
  fi

  # GRAFANA - keep prefix, grafana handles it internally
  if is_installed "grafana" "$manifest"; then
    cat >> "$caddyfile" << 'EOF'
    # Grafana - must keep /grafana prefix (GF_SERVER_SERVE_FROM_SUB_PATH=true)
    handle /grafana/* {
        reverse_proxy grafana:3000 {
            header_up Host {upstream_hostport}
            header_up X-Forwarded-Proto https
            header_up X-Real-IP {remote_host}
        }
    }
EOF
  fi

  # N8N - WebSocket required
  if is_installed "n8n" "$manifest"; then
    cat >> "$caddyfile" << 'EOF'
    # n8n - handle_path strips prefix, WebSocket support
    handle_path /n8n/* {
        reverse_proxy n8n:5678 {
            header_up Host {upstream_hostport}
            header_up X-Forwarded-Proto https
            header_up X-Real-IP {remote_host}
            header_up Connection {http.request.header.Connection}
            header_up Upgrade {http.request.header.Upgrade}
            transport http {
                keepalive 86400s
                keepalive_idle_conns 10
            }
        }
    }
EOF
  fi

  # OPENCLAW
  if is_installed "openclaw" "$manifest"; then
    cat >> "$caddyfile" << 'EOF'
    # OpenClaw
    handle_path /openclaw/* {
        reverse_proxy openclaw:3002 {
            header_up Host {upstream_hostport}
            header_up X-Forwarded-Proto https
        }
    }
EOF
  fi

  # DIFY - multi-container, ORDER CRITICAL (specific before general)
  if is_installed "dify" "$manifest"; then
    cat >> "$caddyfile" << 'EOF'
    # Dify API routes - MUST come before frontend catch-all
    handle /dify/api/* {
        uri strip_prefix /dify
        reverse_proxy dify-api:5001 {
            header_up Host {upstream_hostport}
            header_up X-Forwarded-Proto https
        }
    }
    handle /dify/console/api/* {
        uri strip_prefix /dify
        reverse_proxy dify-api:5001 {
            header_up Host {upstream_hostport}
            header_up X-Forwarded-Proto https
        }
    }
    handle /dify/v1/* {
        uri strip_prefix /dify
        reverse_proxy dify-api:5001 {
            header_up Host {upstream_hostport}
            header_up X-Forwarded-Proto https
        }
    }
    # Dify frontend - catches remaining /dify/* traffic
    handle_path /dify/* {
        reverse_proxy dify-web:3000 {
            header_up Host {upstream_hostport}
            header_up X-Forwarded-Proto https
        }
    }
EOF
  fi

  # ANYTHINGLLM - WebSocket required
  if is_installed "anythingllm" "$manifest"; then
    cat >> "$caddyfile" << 'EOF'
    # AnythingLLM - WebSocket support
    handle_path /anythingllm/* {
        reverse_proxy anythingllm:3001 {
            header_up Host {upstream_hostport}
            header_up X-Forwarded-Proto https
            header_up Connection {http.request.header.Connection}
            header_up Upgrade {http.request.header.Upgrade}
            transport http {
                keepalive 86400s
            }
        }
    }
EOF
  fi

  # LITELLM
  if is_installed "litellm" "$manifest"; then
    cat >> "$caddyfile" << 'EOF'
    # LiteLLM
    handle_path /litellm/* {
        reverse_proxy litellm:4000 {
            header_up Host {upstream_hostport}
            header_up X-Forwarded-Proto https
        }
    }
EOF
  fi

  # OPEN WEBUI - WebSocket required
  if is_installed "openwebui" "$manifest"; then
    cat >> "$caddyfile" << 'EOF'
    # Open WebUI - WebSocket support
    handle_path /openwebui/* {
        reverse_proxy open-webui:8080 {
            header_up Host {upstream_hostport}
            header_up X-Forwarded-Proto https
            header_up Connection {http.request.header.Connection}
            header_up Upgrade {http.request.header.Upgrade}
            transport http {
                keepalive 86400s
            }
        }
    }
EOF
  fi

  # SIGNAL API
  if is_installed "signal" "$manifest"; then
    cat >> "$caddyfile" << 'EOF'
    # Signal CLI REST API
    handle_path /signal/* {
        reverse_proxy signal-cli-rest-api:8080 {
            header_up Host {upstream_hostport}
            header_up X-Forwarded-Proto https
        }
    }
EOF
  fi

  # MINIO - Console (9001) + API note
  if is_installed "minio" "$manifest"; then
    cat >> "$caddyfile" << 'EOF'
    # MinIO Console UI (port 9001)
    handle_path /minio/* {
        reverse_proxy minio:9001 {
            header_up Host {upstream_hostport}
            header_up X-Forwarded-Proto https
        }
    }
    # MinIO S3 API (port 9000) - for internal service use
    handle_path /minio-api/* {
        reverse_proxy minio:9000 {
            header_up Host {upstream_hostport}
            header_up X-Forwarded-Proto https
        }
    }
EOF
  fi

  # Close server block
  echo "}" >> "$caddyfile"
  
  log "SUCCESS" "Caddyfile generated: $caddyfile"
}

# Helper: check if service is in manifest
is_installed() {
  local service=$1
  local manifest=$2
  jq -e ".services.\"$service\".installed == true" "$manifest" > /dev/null 2>&1
}
```

---

### Step 2: Fix Environment Variables in Docker Compose Files

**Windsurf: Verify these exist in the actual compose files, not just the report:**

```bash
# Script to VERIFY env vars are actually set (add to script 3):
verify_subpath_env_vars() {
  log "INFO" "Verifying sub-path environment variables..."
  
  # n8n
  docker exec n8n env 2>/dev/null | grep -q "N8N_PATH=/n8n/" || \
    log "ERROR" "n8n: N8N_PATH not set - sub-path will fail"
    
  # grafana  
  docker exec grafana env 2>/dev/null | grep -q "GF_SERVER_SERVE_FROM_SUB_PATH=true" || \
    log "ERROR" "grafana: GF_SERVER_SERVE_FROM_SUB_PATH not set"
    
  # openwebui - THIS WAS LIKELY MISSED
  docker exec open-webui env 2>/dev/null | grep -q "WEBUI_URL" || \
    log "WARN" "open-webui: WEBUI_URL not set"
    
  # minio
  docker exec minio env 2>/dev/null | grep -q "MINIO_BROWSER_REDIRECT_URL" || \
    log "ERROR" "minio: MINIO_BROWSER_REDIRECT_URL not set"
}
```

---

### Step 3: Windsurf Prompt to Fix the Actual Issue

```
TASK: The proxy configuration generator (caddy-generator.sh or 
nginx-generator.sh) is generating broken configurations.

SPECIFIC BUGS TO FIX:

1. CADDY: Replace all `handle /path/*` with `handle_path /path/*` 
   EXCEPT for grafana (which needs to keep its prefix)

2. DIFY: The /dify/* catch-all is eating API requests.
   Add specific routes for /dify/api/*, /dify/console/api/*, 
   /dify/v1/* BEFORE the frontend catch-all. Use `uri strip_prefix` 
   not `handle_path` for these API routes.

3. WEBSOCKET: Add these headers to n8n, flowise, anythingllm, 
   open-webui reverse_proxy blocks:
   header_up Connection {http.request.header.Connection}
   header_up Upgrade {http.request.header.Upgrade}

4. MINIO: Proxy to port 9001 (console) not 9000 (S3 API).
   Add separate /minio-api/* route for port 9000.

5. OPEN WEBUI: Add missing env var to docker-compose:
   WEBUI_URL=https://ai.datasquiz.net/openwebui

6. OPENCLAW: Verify the actual internal port (3002 assumed - check 
   the docker-compose file for the real port).

7. Add validate_caddyfile() function that runs:
   docker exec caddy caddy validate --config /etc/caddy/Caddyfile
   BEFORE doing caddy reload - fail loudly if config is invalid.

DO NOT change the 4-script architecture.
All changes go in /mnt/data/scripts/lib/caddy-generator.sh
```

---

## Quick Diagnostic Commands

**Give these to run on the server right now to confirm the bugs:**

```bash
# 1. See what Caddyfile was actually generated
cat /mnt/data/caddy/Caddyfile

# 2. Check if handle vs handle_path is the issue
grep -n "handle" /mnt/data/caddy/Caddyfile

# 3. Test each endpoint directly (bypassing caddy)
docker exec caddy curl -s http://flowise:3000 -o /dev/null -w "%{http_code}"
docker exec caddy curl -s http://grafana:3000 -o /dev/null -w "%{http_code}"
docker exec caddy curl -s http://n8n:5678 -o /dev/null -w "%{http_code}"

# 4. Check caddy logs for routing errors
docker logs caddy --tail 50 2>&1 | grep -E "error|warn|upstream"

# 5. Validate current Caddyfile syntax
docker exec caddy caddy validate --config /etc/caddy/Caddyfile
```

The output of `cat /mnt/data/caddy/Caddyfile` will immediately confirm which specific bug is causing failures.
