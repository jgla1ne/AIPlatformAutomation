## Assessment: This is a Step Backward

The current state tells me the refactor **abandoned the reverse proxy entirely** and fell back to direct port mapping. This is the wrong direction.

---

## What Actually Happened

```
EXPECTED OUTCOME:
Browser → https://ai.datasquiz.net/flowise → Caddy → flowise:3000

WHAT WAS BUILT INSTEAD:
Browser → http://localhost:5006 → OpenWebUI (direct)
Browser → http://localhost:8082 → Dify API (direct)
Browser → http://localhost:3002 → Flowise (direct)

The proxy layer was REMOVED, not FIXED.
```

The "landing page" suggestion is also wrong — it's a workaround that avoids solving the actual problem.

---

## The Real Issue: Why This Happened

Windsurf likely hit the `handle` vs `handle_path` complexity and the Dify multi-container routing, got errors during validation, and **took the path of least resistance** — removing the proxy rather than fixing the config.

---

## Correct Direction: Fix Script 2 Properly

Here is the exact Windsurf prompt to get this back on track:

```
STOP. The current script 2 refactor is wrong.

CURRENT BROKEN STATE:
- Services are running on direct ports (5006, 8082, 3002, etc.)
- No reverse proxy is routing /path/* requests
- This is NOT acceptable - we need sub-path routing

REQUIRED END STATE:
- Caddy reverse proxy running as a Docker container
- All services ONLY accessible via https://ai.datasquiz.net/{service}
- Direct ports should NOT be exposed to host (remove port mappings 
  from docker-compose files for all services except Caddy)
- Caddy exposes ONLY 80 and 443 to host

DO NOT suggest direct port mapping as a solution.
DO NOT suggest a landing page as a solution.
DO NOT remove the proxy layer.

TASK: Fix script 2 (2-deploy-services.sh) to:

1. Deploy Caddy as the entry point container:
   - Image: caddy:2-alpine
   - Ports: "80:80" and "443:443" mapped to host
   - Volume: /mnt/data/caddy/Caddyfile:/etc/caddy/Caddyfile
   - Volume: /mnt/data/caddy/data:/data
   - Network: ai-platform (shared with all services)
   - Restart: unless-stopped

2. Generate /mnt/data/caddy/Caddyfile with these EXACT rules:

   For each service use handle_path (strips prefix):
   EXCEPT grafana which uses handle (keeps prefix)
   
   FLOWISE (internal port 3000):
   handle_path /flowise/* {
       reverse_proxy flowise:3000
   }
   
   GRAFANA (internal port 3000):
   handle /grafana/* {
       reverse_proxy grafana:3000
   }
   
   N8N (internal port 5678) WITH websockets:
   handle_path /n8n/* {
       reverse_proxy n8n:5678 {
           header_up Connection {http.request.header.Connection}
           header_up Upgrade {http.request.header.Upgrade}
       }
   }
   
   DIFY (two containers, ORDER MATTERS - specific before general):
   handle /dify/api/* {
       uri strip_prefix /dify
       reverse_proxy dify-api:5001
   }
   handle /dify/console/api/* {
       uri strip_prefix /dify
       reverse_proxy dify-api:5001
   }
   handle /dify/v1/* {
       uri strip_prefix /dify
       reverse_proxy dify-api:5001
   }
   handle_path /dify/* {
       reverse_proxy dify-web:3000
   }
   
   ANYTHINGLLM (internal port 3001) WITH websockets:
   handle_path /anythingllm/* {
       reverse_proxy anythingllm:3001 {
           header_up Connection {http.request.header.Connection}
           header_up Upgrade {http.request.header.Upgrade}
       }
   }
   
   LITELLM (internal port 4000):
   handle_path /litellm/* {
       reverse_proxy litellm:4000
   }
   
   OPENWEBUI (internal port 8080) WITH websockets:
   handle_path /openwebui/* {
       reverse_proxy open-webui:8080 {
           header_up Connection {http.request.header.Connection}
           header_up Upgrade {http.request.header.Upgrade}
       }
   }
   
   SIGNAL (internal port 8080):
   handle_path /signal/* {
       reverse_proxy signal-cli-rest-api:8080
   }
   
   MINIO Console (internal port 9001):
   handle_path /minio/* {
       reverse_proxy minio:9001
   }

3. Remove host port mappings from ALL service docker-compose 
   definitions EXCEPT Caddy. Services communicate only on 
   the internal Docker network ai-platform.

4. Add these environment variables to docker-compose definitions:
   
   grafana:
     GF_SERVER_ROOT_URL: https://ai.datasquiz.net/grafana
     GF_SERVER_SERVE_FROM_SUB_PATH: "true"
   
   n8n:
     N8N_EDITOR_BASE_URL: https://ai.datasquiz.net/n8n
     WEBHOOK_URL: https://ai.datasquiz.net/n8n
     N8N_PATH: /n8n/
   
   flowise:
     FLOWISE_BASE_PATH: /flowise
   
   openwebui:
     WEBUI_URL: https://ai.datasquiz.net/openwebui
   
   minio:
     MINIO_BROWSER_REDIRECT_URL: https://ai.datasquiz.net/minio

5. After generating Caddyfile, validate it:
   docker run --rm \
     -v /mnt/data/caddy/Caddyfile:/etc/caddy/Caddyfile \
     caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile
   
   If validation fails: print the error and EXIT with code 1.
   Do NOT continue deployment with an invalid Caddyfile.

6. After Caddy starts, run health checks:
   For each service path, curl https://ai.datasquiz.net/{service}
   and verify HTTP response is not 502/504.
   Print PASS or FAIL per service.

INTERNAL PORT REFERENCE (use these, not the random host ports):
- flowise:3000
- grafana:3000  
- n8n:5678
- openclaw:3002
- dify-api:5001
- dify-web:3000
- anythingllm:3001
- litellm:4000
- open-webui:8080
- signal-cli-rest-api:8080
- minio:9001 (console), minio:9000 (S3 API)

ALL DATA PATHS under /mnt/data/
DO NOT change script 1, 3, or 4.
DO NOT add a 5th script.
```

---

## Key Rules to Give Windsurf to Prevent Regression

```
GUARDRAILS - never violate these:

❌ NEVER expose service ports directly to host
❌ NEVER suggest direct port mapping as a "solution"  
❌ NEVER remove the Caddy proxy layer
❌ NEVER create a 5th script
❌ NEVER use a landing page to replace proper routing

✅ ALWAYS route through Caddy on 80/443
✅ ALWAYS validate Caddyfile before reload
✅ ALWAYS fail loudly with clear error messages
✅ ALWAYS keep all data under /mnt/data/
```

The services working on direct ports confirms **the underlying containers are healthy** — that's actually good news. The fix is purely in the proxy layer, not in the services themselves.
