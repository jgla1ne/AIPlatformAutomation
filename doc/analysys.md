# Windsurf Proxy Configuration Fix Plan

Based on the current audit and script 2 constraints, here's a targeted solution that maintains your system architecture while fixing all identified issues.

## 1. Caddyfile Proxy Configuration Fix

```bash
cat > /mnt/data/Caddyfile << 'EOF'
ai.datasquiz.net {
    # Handle path routing with proper header management
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

    handle /ollama/* {
        reverse_proxy localhost:11434 {
            header_up Host {host}
            header_up X-Real-IP {remote}
        }
    }

    handle /litellm/* {
        reverse_proxy localhost:4000 {
            header_up Host {host}
            header_up X-Real-IP {remote}
        }
    }

    handle /anythingllm/* {
        reverse_proxy localhost:5004 {
            header_up Host {host}
            header_up X-Real-IP {remote}
        }
    }

    handle /prometheus/* {
        reverse_proxy localhost:9090 {
            header_up Host {host}
            header_up X-Real-IP {remote}
        }
    }

    handle /dify/* {
        reverse_proxy localhost:3002 {
            header_up Host {host}
            header_up X-Real-IP {remote}
        }
    }

    handle /minio/* {
        reverse_proxy localhost:5007 {
            header_up Host {host}
            header_up X-Real-IP {remote}
        }
    }

    handle /minio/console/* {
        uri strip_prefix /minio/console
        reverse_proxy localhost:5008 {
            header_up Host {host}
            header_up X-Real-IP {remote}
        }
    }

    # Default catch-all
    handle {
        reverse_proxy localhost:5006
    }
}
EOF

# Reload Caddy
docker exec caddy caddy reload --config /etc/caddy/Caddyfile
```

## 2. Service-Specific Fixes in Script 2

### Litellm Port Alignment
```bash
# Change port mapping to match configured port
docker run -d \
  --name litellm \
  -p 5005:4000 \  # Changed from 4000:4000 to 5005:4000
  -v /mnt/data/litellm/config:/app/config \
  -e CONFIG_FILE=/app/config/config.yaml \
  --network ai_platform \
  --restart unless-stopped \
  ghcr.io/berriai/litellm:main-latest
```

### Dify-Web Port Alignment
```bash
# Change port mapping to match configured port
docker run -d \
  --name dify-web \
  -p 8085:3000 \  # Changed from 3002:3000 to 8085:3000
  -e MODE=web \
  -e API_URL="https://ai.datasquiz.net/dify" \
  -v /mnt/data/dify:/app/api/storage \
  --network ai_platform \
  --restart unless-stopped \
  langgenius/dify-web:latest
```

### Prometheus Port Alignment
```bash
# Change port mapping to match configured port
docker run -d \
  --name prometheus \
  -p 5000:9090 \  # Changed from 9090:9090 to 5000:9090
  -v /mnt/data/prometheus:/etc/prometheus \
  -v /mnt/data/prometheus_data:/prometheus \
  --network ai_platform \
  --restart unless-stopped \
  prom/prometheus:latest
```

### MinIO Configuration Fix
```bash
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

### AnythingLLM Health Fix
```bash
docker run -d \
  --name anythingllm \
  -p 5004:3000 \
  -e SERVER_PORT=3000 \
  -e STORAGE_DIR="/app/server/storage" \
  -e SERVER_URL="https://ai.datasquiz.net/anythingllm" \
  -e DISABLE_TELEMETRY="true" \
  -v /mnt/data/anythingllm/storage:/app/server/storage \
  --network ai_platform \
  --health-cmd "curl -f http://localhost:3000/health || exit 1" \
  --health-interval 30s \
  --restart unless-stopped \
  mintplexlabs/anythingllm:latest
```

## 3. Missing Services Deployment

### Flowise
```bash
docker run -d \
  --name flowise \
  -p 5003:3000 \
  -e PORT=3000 \
  -v /mnt/data/flowise:/root/.flowise \
  --network ai_platform \
  --restart unless-stopped \
  flowiseai/flowise:latest
```

### Signal (Example)
```bash
docker run -d \
  --name signal \
  -p 8080:8080 \
  --network ai_platform \
  --restart unless-stopped \
  signalapp/server:latest
```

### Openclaw (Example)
```bash
docker run -d \
  --name openclaw \
  -p 18789:18789 \
  --network ai_platform \
  --restart unless-stopped \
  your-openclaw-image:latest
```

## 4. Verification Script

```bash
#!/bin/bash

# Service verification
declare -A SERVICES=(
    ["n8n"]="5002 /n8n"
    ["grafana"]="5001 /grafana"
    ["openwebui"]="5006 /webui"
    ["ollama"]="11434 /ollama"
    ["litellm"]="5005 /litellm"
    ["anythingllm"]="5004 /anythingllm"
    ["prometheus"]="5000 /prometheus"
    ["dify"]="8085 /dify"
    ["minio"]="5007 /minio"
    ["flowise"]="5003 /flowise"
    ["signal"]="8080 /signal"
    ["openclaw"]="18789 /openclaw"
)

echo "=== SERVICE VERIFICATION REPORT ==="
echo "Service | Port Match | Docker Status | Direct Access | Proxy Access"
echo "---------------------------------------------------------------"

for service in "${!SERVICES[@]}"; do
    configured_port=$(echo ${SERVICES[$service]} | awk '{print $1}')
    path=$(echo ${SERVICES[$service]} | awk '{print $2}')

    # Check port mapping
    actual_port=$(docker port $service | head -1 | awk -F'->' '{print $1}' | tr -d ' ')
    if [ "$configured_port" == "$actual_port" ]; then
        port_match="✅"
    else
        port_match="❌ ($actual_port)"
    fi

    # Check Docker status
    if docker ps --format '{{.Names}}' | grep -q "^${service}$"; then
        docker_status="✅ Up"
    else
        docker_status="❌ Down"
    fi

    # Check direct access
    direct_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$configured_port$path 2>/dev/null || echo "000")
    if [[ $direct_status =~ ^2[0-9]{2}|3[0-9]{2}$ ]]; then
        direct_status="✅ $direct_status"
    else
        direct_status="❌ $direct_status"
    fi

    # Check proxy access
    proxy_status=$(curl -s -o /dev/null -w "%{http_code}" https://ai.datasquiz.net$path 2>/dev/null || echo "000")
    if [[ $proxy_status =~ ^2[0-9]{2}|3[0-9]{2}$ ]]; then
        proxy_status="✅ $proxy_status"
    else
        proxy_status="❌ $proxy_status"
    fi

    printf "%-10s | %-10s | %-12s | %-13s | %s\n" "$service" "$port_match" "$docker_status" "$direct_status" "$proxy_status"
done
```

## Implementation Steps

1. **First Priority: Fix Port Mismatches**
   - Update litellm, dify-web, and prometheus port mappings
   - Verify direct access works on configured ports

2. **Second Priority: Fix Proxy Routing**
   - Update Caddyfile with proper path handling
   - Add necessary headers for each service
   - Reload Caddy configuration

3. **Third Priority: Fix Service-Specific Issues**
   - Update MinIO configuration
   - Add health checks to anythingllm
   - Verify ollama health check

4. **Fourth Priority: Deploy Missing Services**
   - Deploy flowise, signal, and openclaw
   - Verify they start properly

5. **Final Verification**
   - Run the verification script
   - Check all services respond on their public URLs
   - Monitor for any errors

This solution maintains all system constraints while fixing:
- Port mismatches (litellm, dify-web, prometheus)
- Proxy routing issues (ollama, anythingllm, litellm, prometheus, dify)
- Configuration issues (minio)
- Missing services (flowise, signal, openclaw)
- Health check issues (anythingllm)
