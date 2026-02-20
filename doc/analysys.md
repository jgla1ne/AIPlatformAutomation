## Cross-Check Analysis: Windsurf Summary vs. Correct Architecture

The Windsurf summary has **one persistent conceptual error** mixed with some real progress. Let me break it down precisely.

---

## ✅ What Windsurf Got Right

| Item | Status |
|------|--------|
| Prometheus routing: `prometheus:9090` in Caddyfile | ✅ Correct |
| Host port mappings updated to use `.env` vars | ✅ Correct |
| 7/10 services now responding | ✅ Real progress |
| Grafana working via proxy | ✅ Good |
| OpenWebUI working | ✅ Good |

---

## ❌ The Persistent Wrong Belief

Windsurf still thinks changing host ports fixed the proxy. It didn't. Look at this:

```
Their claim:
"Dynamic Port Usage: 0% → 100%"
"Proxy URLs now use .env ports"

What actually happened:
Caddy still routes to container-internal ports (correct).
Host port changes only affect external direct access.
The proxy worked/failed for OTHER reasons.
```

The Caddyfile correctly uses `prometheus:9090`, `grafana:3000`, `open-webui:8080` — **none of these are `.env` ports**. That's correct and should stay that way forever.

---

## 🗺️ Definitive Architecture Reference

```
EXTERNAL USER
     │
     ▼
https://ai.datasquiz.net  (port 443)
     │
     ▼
[CADDY CONTAINER] ──── uses container DNS names + internal ports
     │
     ├──► flowise:3000          (not 3002)
     ├──► grafana:3000          (not 5001)
     ├──► n8n:5678              (not 5002)
     ├──► prometheus:9090       (not 5000)
     ├──► ollama:11434          (not 11434 — same here)
     ├──► openclaw:3000         (not 18789)
     ├──► dify-web:3000         (not 5003)
     ├──► dify-api:5001         (not 5003)
     ├──► anythingllm:3001      (not 5004)
     ├──► litellm:4000          (not 5005)
     ├──► open-webui:8080       (not 5006)
     ├──► signal-cli-rest-api:8080 (not 8080 — same)
     └──► minio:9001            (console, not 5007/5008)

HOST PORTS (only for direct debug access, irrelevant to Caddy):
  prometheus → 5000:9090
  grafana    → 5001:3000
  n8n        → 5002:5678
  flowise    → 3002:3000
  anythingllm → 5004:3001
  litellm    → 5005:4000
  openwebui  → 5006:8080
  minio      → 5007:9000, 5008:9001
```

---

## 📋 Script 2 Crosscheck — What Must Be True

Here's what script 2's `deploy_caddy()` function **must generate**, locked and immutable:

```bash
deploy_caddy() {
  mkdir -p /mnt/data/caddy

  # NOTE: These are CONTAINER-INTERNAL ports, NOT .env host ports
  # Do NOT substitute .env port variables here
  cat > /mnt/data/caddy/Caddyfile << 'CADDYEOF'
{
    admin off
    email admin@datasquiz.net
}

ai.datasquiz.net {

    handle_path /prometheus/* {
        reverse_proxy prometheus:9090
    }

    handle /grafana* {
        reverse_proxy grafana:3000 {
            header_up X-Forwarded-Prefix /grafana
        }
    }

    handle_path /n8n/* {
        reverse_proxy n8n:5678 {
            header_up Upgrade {http.request.header.Upgrade}
            header_up Connection {http.request.header.Connection}
        }
    }

    handle_path /ollama/* {
        reverse_proxy ollama:11434
    }

    handle_path /openclaw/* {
        reverse_proxy openclaw:3000
    }

    handle_path /dify/api/* {
        reverse_proxy dify-api:5001
    }

    handle_path /dify/* {
        reverse_proxy dify-web:3000
    }

    handle_path /anythingllm/* {
        reverse_proxy anythingllm:3001 {
            header_up Upgrade {http.request.header.Upgrade}
            header_up Connection {http.request.header.Connection}
        }
    }

    handle_path /litellm/* {
        reverse_proxy litellm:4000
    }

    handle_path /openwebui/* {
        reverse_proxy open-webui:8080 {
            header_up Upgrade {http.request.header.Upgrade}
            header_up Connection {http.request.header.Connection}
        }
    }

    handle_path /signal/* {
        reverse_proxy signal-cli-rest-api:8080
    }

    handle_path /flowise/* {
        reverse_proxy flowise:3000
    }

    handle_path /minio/* {
        reverse_proxy minio:9001 {
            header_up X-Forwarded-Prefix /minio
        }
    }

    handle /health {
        respond "OK" 200
    }

    respond "AI Platform" 200
}
CADDYEOF

  # Deploy caddy container on the ai_platform network
  docker rm -f caddy 2>/dev/null || true
  docker run -d \
    --name caddy \
    --network ai_platform \
    --restart unless-stopped \
    -p 80:80 \
    -p 443:443 \
    -v /mnt/data/caddy/Caddyfile:/etc/caddy/Caddyfile:ro \
    -v /mnt/data/caddy/data:/data \
    -v /mnt/data/caddy/config:/config \
    caddy:2-alpine

  echo "Caddy deployed. Testing in 5s..."
  sleep 5
  curl -s -o /dev/null -w "Caddy health: %{http_code}\n" \
    http://localhost/health
}
```

---

## The Three Remaining Broken Services

| Service | Real Problem | Fix |
|---------|-------------|-----|
| **n8n** | Permission error on `/mnt/data/n8n` | `chown -R 1000:1000 /mnt/data/n8n && docker restart n8n` |
| **AnythingLLM** | Not listening on 3001 internally | Check if port in docker-compose is `3001:3001` not `5004:3000` |
| **LiteLLM** | Config file missing or wrong | Check `/mnt/data/litellm/config.yaml` exists |

```bash
# Run this now to fix all three
# Check anythingllm actual internal port
docker inspect anythingllm \
  --format='Ports: {{json .NetworkSettings.Ports}}'

# Check litellm config
ls -la /mnt/data/litellm/

docker restart n8n anythingllm litellm
sleep 10

for svc in n8n anythingllm litellm; do
  echo "=== $svc logs ==="
  docker logs $svc --tail 5 2>&1
done
```

**DIAGNOSTIC RESULTS:**

### **n8n**
```
=== n8n logs ===
password authentication failed for user "ds-admin"
Last session crashed
Initializing n8n process
There was an error initializing DB
password authentication failed for user "ds-admin"
```
**Issue**: PostgreSQL authentication failure
**Fix**: Check PostgreSQL credentials and restart n8n

### **AnythingLLM**
```
=== anythingllm logs ===
[backend] info: [BackgroundWorkerService] Service started with 1 jobs ["cleanup-orphan-documents"]
[backend] info: ⚡Pre-cached context windows for Ollama
[backend] info: [PushNotifications] Loaded existing VAPID keys!
[backend] info: [PushNotifications] Loading single user mode subscriptions...
[backend] info: Primary server in HTTP mode listening on port 3001
```
**Issue**: Service is listening on port 3001, not 3000
**Fix**: Update docker-compose port mapping from `5004:3000` to `5004:3001`

### **LiteLLM**
```
=== litellm logs ===
Exception: Config file not found: /app/config/config.yaml
```
**Issue**: Missing configuration file
**Fix**: Create `/mnt/data/litellm/config/config.yaml` or copy from template

---

## 🎯 EXACT FIXES REQUIRED

### **1. Fix n8n PostgreSQL Authentication**
```bash
# Check PostgreSQL connection
sudo docker exec postgres psql -U ${POSTGRES_USER:-ds-admin} -d ${POSTGRES_DB:-aiplatform} -c "SELECT 1;"
# If fails, fix credentials in .env and restart postgres
sudo docker restart postgres
sudo docker restart n8n
```

### **2. Fix AnythingLLM Port Mismatch**
```bash
# Update docker-compose.yml
# Change from: "${ANYTHINGLLM_PORT:-5004}:3000"
# To: "${ANYTHINGLLM_PORT:-5004}:3001"

# Recreate container
sudo docker stop anythingllm
sudo docker rm anythingllm
cd /mnt/data/ai-platform/deployment/stack
sudo docker compose --env-file /mnt/data/.env up -d anythingllm
```

### **3. Fix LiteLLM Configuration**
```bash
# Create missing config file
cat > /mnt/data/litellm/config/config.yaml << 'EOF'
model_list:
  - model_name: ollama/llama3.2
    model_id: ollama/llama3.2:latest
    litellm_params:
      model_name: ollama/llama3.2
      api_base: http://ollama:11434
      api_base: http://ollama:11434

litellm_settings:
  database_url: postgresql://ds-admin:bG4CpMQlb5v5SSG9IdUrWCON@postgres:5432/aiplatform
  redis_url: redis://:6379
  redis_password: FGCUJpVlKPtQHWBTZFq7CE1a

general_settings:
  master_key: rjcfVbbNbxuoMV9WwVBn8nEcTeBuhQJ7
  salt_key: ygt23OKv3WQkur8n
  cache_enabled: true
  cache_ttl: 3600
  rate_limit_enabled: true
  rate_limit_requests_per_minute: 60
  routing_strategy: local-first
EOF

sudo docker restart litellm
```

---

## 📊 Expected Results After Fixes

Once these three fixes are applied, all services should respond internally:

| Service | Internal Port | Expected Status |
|---------|---------------|----------------|
| **n8n** | 5678 | ✅ Responding |
| **AnythingLLM** | 3001 | ✅ Responding |
| **LiteLLM** | 4000 | ✅ Responding |

Then the Caddy proxy routes will work immediately for all services.