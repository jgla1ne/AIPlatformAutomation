# Iterative Fix Plan for AI Platform Services

Based on the current status report, I'll outline a phased approach to get all services operational. We'll address issues in order of priority while maintaining system stability.

## Phase 1: Critical Configuration Fixes (Day 1)

### 1. Fix LiteLLM Configuration
```bash
# Create proper config directory and file
mkdir -p /mnt/data/litellm/config
cat > /mnt/data/litellm/config/config.yaml <<EOF
model_list:
  - model_name: gpt-3.5-turbo
    litellm_params:
      model: gpt-3.5-turbo
      api_key: ${OPENAI_API_KEY}
      api_base: https://api.openai.com/v1

general_settings:
  master_key: ${LITELLM_MASTER_KEY}
EOF

# Update LiteLLM deployment in script 2
docker run -d \
  --name litellm \
  -p 4000:4000 \
  -v /mnt/data/litellm/config:/app/config \
  -e CONFIG_FILE=/app/config/config.yaml \
  --network ai_platform \
  --restart unless-stopped \
  ghcr.io/berriai/litellm:main-latest
```

### 2. Fix AnythingLLM Database Permissions
```bash
# Create proper directory structure with correct permissions
mkdir -p /mnt/data/anythingllm/storage
chmod -R 777 /mnt/data/anythingllm  # Temporary for troubleshooting

# Update AnythingLLM deployment
docker run -d \
  --name anythingllm \
  -p 5004:3000 \
  -e SERVER_PORT=3000 \
  -e STORAGE_DIR="/app/server/storage" \
  -e SERVER_URL="https://ai.datasquiz.net/anythingllm" \
  -v /mnt/data/anythingllm/storage:/app/server/storage \
  --network ai_platform \
  --restart unless-stopped \
  mintplexlabs/anythingllm:latest
```

### 3. Fix Ollama Health Check
```bash
# Update Ollama deployment with health check
docker run -d \
  --name ollama \
  -p 11434:11434 \
  -v /mnt/data/ollama:/root/.ollama \
  --network ai_platform \
  --health-cmd "curl -f http://localhost:11434/api/tags || exit 1" \
  --health-interval 30s \
  --health-retries 3 \
  --restart unless-stopped \
  ollama/ollama:latest

# Pull default model to ensure content
docker exec ollama ollama pull llama3
```

## Phase 2: Network and Proxy Configuration (Day 2)

### 1. Fix MinIO Configuration
```bash
# Update MinIO deployment with proper domain settings
docker run -d \
  --name minio \
  -p 5007:9000 \
  -p 5008:9001 \
  -e MINIO_ROOT_USER=${MINIO_ROOT_USER} \
  -e MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD} \
  -e MINIO_DOMAIN=ai.datasquiz.net \
  -e MINIO_SERVER_URL="https://ai.datasquiz.net/minio" \
  -e MINIO_BROWSER_REDIRECT_URL="https://ai.datasquiz.net/minio/console" \
  -v /mnt/data/minio:/data \
  --network ai_platform \
  --restart unless-stopped \
  minio/minio server /data --console-address ":9001"
```

### 2. Fix Proxy Path Routing in Caddyfile
```bash
# Update Caddyfile configuration
cat > /mnt/data/Caddyfile <<EOF
ai.datasquiz.net {
    # Handle path routing in order of specificity
    handle /n8n/* {
        reverse_proxy localhost:5002 {
            header_up X-Forwarded-Host {host}
            header_up X-Forwarded-Proto {scheme}
            header_up X-Forwarded-Prefix /n8n
        }
    }

    handle /grafana/* {
        reverse_proxy localhost:5001
    }

    handle /webui/* {
        reverse_proxy localhost:5006
    }

    handle /prometheus/* {
        reverse_proxy localhost:9090
    }

    handle /dify/* {
        reverse_proxy localhost:3002
    }

    handle /ollama/* {
        reverse_proxy localhost:11434
    }

    handle /minio/* {
        reverse_proxy localhost:5007
    }

    handle /minio/console/* {
        uri strip_prefix /minio/console
        reverse_proxy localhost:5008
    }

    handle /anythingllm/* {
        reverse_proxy localhost:5004
    }

    handle /litellm/* {
        reverse_proxy localhost:4000
    }

    # Default catch-all
    handle {
        reverse_proxy localhost:5006  # Default to openwebui
    }
}
EOF

# Reload Caddy configuration
docker exec caddy caddy reload --config /etc/caddy/Caddyfile
```

## Phase 3: Service Health and Deployment (Day 3)

### 1. Fix Dify Web Health
```bash
# Update Dify deployment with proper health checks
docker run -d \
  --name dify-web \
  -p 3002:3000 \
  -e MODE=web \
  -e API_URL="https://ai.datasquiz.net/dify" \
  -e PUBLIC_API_URL="https://ai.datasquiz.net/dify" \
  -e CONSOLE_API_URL="https://ai.datasquiz.net/dify" \
  -e APP_WEB_URL="https://ai.datasquiz.net/dify" \
  -v /mnt/data/dify:/app/api/storage \
  --network ai_platform \
  --health-cmd "curl -f http://localhost:3000/health || exit 1" \
  --health-interval 30s \
  --health-retries 3 \
  --restart unless-stopped \
  langgenius/dify-web:latest
```

### 2. Deploy Missing Services
```bash
# Flowise
docker run -d \
  --name flowise \
  -p 5003:3000 \
  -e PORT=3000 \
  -v /mnt/data/flowise:/root/.flowise \
  --network ai_platform \
  --restart unless-stopped \
  flowiseai/flowise:latest

# Signal (example - adjust as needed)
docker run -d \
  --name signal \
  -p 5005:3000 \
  --network ai_platform \
  --restart unless-stopped \
  signalapp/server:latest

# Openclaw (example - adjust as needed)
docker run -d \
  --name openclaw \
  -p 5009:8000 \
  --network ai_platform \
  --restart unless-stopped \
  your-openclaw-image:latest
```

## Phase 4: Verification and Monitoring (Ongoing)

### 1. Comprehensive Verification Script
```bash
#!/bin/bash

# Service verification script
declare -A SERVICES=(
    ["n8n"]="5002 /n8n"
    ["grafana"]="5001 /grafana"
    ["openwebui"]="5006 /webui"
    ["prometheus"]="9090 /prometheus"
    ["dify"]="3002 /dify"
    ["ollama"]="11434 /ollama"
    ["minio"]="5007 /minio"
    ["anythingllm"]="5004 /anythingllm"
    ["litellm"]="4000 /litellm"
    ["flowise"]="5003 /flowise"
    ["signal"]="5005 /signal"
    ["openclaw"]="5009 /openclaw"
)

echo "=== SERVICE VERIFICATION REPORT ==="
echo "Service | Docker Status | Direct Access | Proxy Access | Content Check"
echo "---------------------------------------------------------------"

for service in "${!SERVICES[@]}"; do
    port=$(echo ${SERVICES[$service]} | awk '{print $1}')
    path=$(echo ${SERVICES[$service]} | awk '{print $2}')

    # Check Docker status
    if docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
        docker_status="✅ Up"
        if docker inspect --format='{{.State.Health.Status}}' $service 2>/dev/null | grep -q "healthy"; then
            docker_status="✅ Healthy"
        fi
    else
        docker_status="❌ Down"
    fi

    # Check direct access
    direct_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$port$path)
    if [[ $direct_status =~ ^2[0-9]{2}|3[0-9]{2}$ ]]; then
        direct_status="✅ $direct_status"
    else
        direct_status="❌ $direct_status"
    fi

    # Check proxy access
    proxy_status=$(curl -s -o /dev/null -w "%{http_code}" https://ai.datasquiz.net$path)
    if [[ $proxy_status =~ ^2[0-9]{2}|3[0-9]{2}$ ]]; then
        proxy_status="✅ $proxy_status"
    else
        proxy_status="❌ $proxy_status"
    fi

    # Check content
    content_check=$(curl -s https://ai.datasquiz.net$path | head -1 | grep -v "^$" | wc -l)
    if [ $content_check -gt 0 ]; then
        content_check="✅ Content"
    else
        content_check="❌ Empty"
    fi

    printf "%-10s | %-12s | %-13s | %-12s | %s\n" "$service" "$docker_status" "$direct_status" "$proxy_status" "$content_check"
done
```

### 2. Monitoring Setup
```bash
# Add to script 2 for Prometheus monitoring
docker run -d \
  --name prometheus \
  -p 9090:9090 \
  -v /mnt/data/prometheus:/etc/prometheus \
  -v /mnt/data/prometheus_data:/prometheus \
  --network ai_platform \
  --restart unless-stopped \
  prom/prometheus:latest
```

## Implementation Schedule

| Phase | Task | Time Estimate | Success Criteria |
|-------|------|---------------|------------------|
| 1 | Fix LiteLLM config | 1 hour | Container stays running |
| 1 | Fix AnythingLLM DB | 1 hour | Container healthy with content |
| 1 | Fix Ollama health | 30 min | Health check passes |
| 2 | Fix MinIO config | 1 hour | Both API and console accessible |
| 2 | Fix proxy routing | 2 hours | All services return 200/302 |
| 3 | Fix Dify health | 1 hour | Container shows healthy |
| 3 | Deploy missing services | 1 hour | All containers running |
| 4 | Verify all services | 1 hour | All services accessible |
| 4 | Setup monitoring | 30 min | Prometheus collecting metrics |

## Rollback Plan

For each change:
1. Take snapshot of current state:
```bash
docker commit <container_name> backup_<container_name>_$(date +%s)
docker save -o /mnt/data/backups/<container_name>_$(date +%s).tar <image_name>
```

2. If issues occur:
```bash
docker stop <container_name>
docker rm <container_name>
docker load -i /mnt/data/backups/<container_name>_backup.tar
# Redeploy with previous configuration
```

This iterative plan addresses all critical issues first, then moves to proxy configuration, and finally ensures all services are deployed and healthy. Each phase builds on the previous one to maintain system stability.
