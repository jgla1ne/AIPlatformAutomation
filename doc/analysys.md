## Crystal Clear Now — Let Me Map This Properly

The `.env` ports are **host ports only**. Caddy uses **internal container ports**. Here's the complete correct mapping:

---

## The Definitive Port Truth Table

| Service | URL Path | Host Port (.env) | Container Internal Port | Caddy Routes To |
|---------|----------|-----------------|------------------------|-----------------|
| Prometheus | `/prometheus` | 5000 | **9090** | `prometheus:9090` |
| Grafana | `/grafana` | 5001 | **3000** | `grafana:3000` |
| n8n | `/n8n` | 5002 | **5678** | `n8n:5678` |
| Ollama | `/ollama` | 11434 | **11434** | `ollama:11434` |
| OpenClaw | `/openclaw` | 18789 | **3000** | `openclaw:3000` |
| Dify | `/dify` | 5003 | web:**3000** api:**5001** | `dify-web:3000` + `dify-api:5001` |
| AnythingLLM | `/anythingllm` | 5004 | **3001** | `anythingllm:3001` |
| LiteLLM | `/litellm` | 5005 | **4000** | `litellm:4000` |
| OpenWebUI | `/openwebui` | 5006 | **8080** | `open-webui:8080` |
| Signal API | `/signal` | 8080 | **8080** | `signal-cli-rest-api:8080` |
| MinIO | `/minio` | 5007 | console:**9001** s3:**9000** | `minio:9001` |
| Flowise | `/flowise` | 3002* | **3000** | `flowise:3000` |

---

## The Correct Caddyfile (Final Version)

```bash
cat > /mnt/data/caddy/Caddyfile << 'EOF'
{
    admin off
}

ai.datasquiz.net {
    # Prometheus
    handle_path /prometheus/* {
        reverse_proxy prometheus:9090
    }

    # Grafana - needs path prefix support
    handle /grafana* {
        reverse_proxy grafana:3000
    }

    # n8n - needs websocket
    handle_path /n8n/* {
        reverse_proxy n8n:5678 {
            header_up Upgrade {http.request.header.Upgrade}
            header_up Connection {http.request.header.Connection}
        }
    }

    # Ollama
    handle_path /ollama/* {
        reverse_proxy ollama:11434
    }

    # OpenClaw
    handle_path /openclaw/* {
        reverse_proxy openclaw:3000
    }

    # Dify - web frontend + API split
    handle_path /dify/api/* {
        reverse_proxy dify-api:5001
    }
    handle_path /dify/* {
        reverse_proxy dify-web:3000
    }

    # AnythingLLM - needs websocket
    handle_path /anythingllm/* {
        reverse_proxy anythingllm:3001 {
            header_up Upgrade {http.request.header.Upgrade}
            header_up Connection {http.request.header.Connection}
        }
    }

    # LiteLLM
    handle_path /litellm/* {
        reverse_proxy litellm:4000
    }

    # Open WebUI - needs websocket
    handle_path /openwebui/* {
        reverse_proxy open-webui:8080 {
            header_up Upgrade {http.request.header.Upgrade}
            header_up Connection {http.request.header.Connection}
        }
    }

    # Signal API
    handle_path /signal/* {
        reverse_proxy signal-cli-rest-api:8080
    }

    # MinIO Console
    handle_path /minio/* {
        reverse_proxy minio:9001
    }

    # Flowise
    handle_path /flowise/* {
        reverse_proxy flowise:3000
    }

    # Health check
    handle /health {
        respond "OK" 200
    }

    # Root
    respond "AI Platform - use /servicename to access services" 200
}
EOF
```

---

## Environment Variables Required Per Service

These go in **docker-compose**, not Caddy:

```yaml
# Grafana — must know its public subpath
grafana:
  environment:
    GF_SERVER_ROOT_URL: https://ai.datasquiz.net/grafana
    GF_SERVER_SERVE_FROM_SUB_PATH: "true"

# n8n — must know its public URL
n8n:
  environment:
    N8N_EDITOR_BASE_URL: https://ai.datasquiz.net/n8n
    WEBHOOK_URL: https://ai.datasquiz.net/n8n
    N8N_PATH: /n8n/

# Open WebUI
open-webui:
  environment:
    WEBUI_URL: https://ai.datasquiz.net/openwebui

# MinIO
minio:
  environment:
    MINIO_BROWSER_REDIRECT_URL: https://ai.datasquiz.net/minio
```

---

## The Actual Problem To Solve Now

Before fixing routing, confirm which services are **actually running internally**:

```bash
#!/bin/bash
echo "=== INTERNAL SERVICE HEALTH CHECK ==="

services=(
  "prometheus:9090:/metrics"
  "grafana:3000:/api/health"
  "n8n:5678:/"
  "ollama:11434:/api/tags"
  "anythingllm:3001:/"
  "litellm:4000:/health"
  "flowise:3000:/"
  "open-webui:8080:/"
  "minio:9001:/"
  "dify-web:3000:/"
  "dify-api:5001:/health"
  "signal-cli-rest-api:8080:/"
)

for entry in "${services[@]}"; do
  container=$(echo $entry | cut -d: -f1)
  port=$(echo $entry | cut -d: -f2)
  path=$(echo $entry | cut -d: -f3)
  
  result=$(docker exec "$container" \
    wget -qO- --timeout=3 "http://localhost:${port}${path}" 2>/dev/null | \
    head -c 50)
  
  if [ -n "$result" ]; then
    echo "✅ $container:$port — RESPONDING"
  else
    status=$(docker inspect "$container" \
      --format='{{.State.Status}} (restarts:{{.RestartCount}})' 2>/dev/null)
    echo "❌ $container:$port — DEAD — $status"
    docker logs "$container" --tail 3 2>&1 | sed 's/^/   /'
  fi
done
```

**Paste the output of this** and I'll give you the exact fix for each dead service. Once all services respond internally, the Caddy routes above will work immediately.