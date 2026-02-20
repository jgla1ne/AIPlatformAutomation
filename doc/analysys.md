# Targeted Fix Plan for Remaining Service Issues

Based on the current state, I'll create a focused remediation plan for each remaining issue with specific, actionable fixes.

## 1. n8n Proxy 404 Issue (Path Routing)

**Problem:** Direct access works but proxy returns 404, indicating path routing misconfiguration.

**Solution:**

**In `2-deploy-services.sh`:**
```bash
# Enhanced n8n deployment with proper path configuration
docker run -d \
  --name n8n \
  --restart unless-stopped \
  -p 5678:5678 \
  -e N8N_BASIC_AUTH_ACTIVE=true \
  -e N8N_BASIC_AUTH_USER=${N8N_USER} \
  -e N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD} \
  -e N8N_PATH="/n8n/" \  # Note trailing slash
  -e N8N_HOST="ai.datasquiz.net" \
  -e N8N_PROTOCOL="https" \
  -e NODE_ENV=production \
  -e WEBHOOK_URL="https://ai.datasquiz.net/n8n/" \
  -v n8n_data:/home/node/.n8n \
  --network ai_platform \
  n8nio/n8n:latest
```

**In `3-configure-services.sh`:**
```bash
# Specific n8n proxy configuration with path handling
cat >> /etc/caddy/Caddyfile <<EOF

ai.datasquiz.net/n8n/* {
    uri strip_prefix /n8n
    reverse_proxy localhost:5678 {
        header_up X-Forwarded-Host {host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Prefix /n8n
    }
}
EOF
```

## 2. Ollama Root Path 404 Issue

**Problem:** API works but root path returns 404 through proxy.

**Solution:**

**In `3-configure-services.sh`:**
```bash
# Ollama proxy configuration with root path handling
cat >> /etc/caddy/Caddyfile <<EOF

ai.datasquiz.net/ollama {
    @root path /
    handle @root {
        redir /ollama/ /ollama/api/tags 302
    }

    reverse_proxy localhost:11434 {
        header_up X-Forwarded-Host {host}
        header_up X-Forwarded-Proto {scheme}
    }
}

ai.datasquiz.net/ollama/* {
    uri strip_prefix /ollama
    reverse_proxy localhost:11434 {
        header_up X-Forwarded-Host {host}
        header_up X-Forwarded-Proto {scheme}
    }
}
EOF
```

## 3. Dify-Web Unhealthy Issue

**Problem:** Dify-web container remains unhealthy.

**Solution:**

**In `2-deploy-services.sh`:**
```bash
# Enhanced Dify deployment with health checks
docker-compose -f dify-docker-compose.yml up -d --force-recreate

# Add specific health check for dify-web
for i in {1..60}; do
  if docker exec dify-web curl -fs http://localhost:3000/health; then
    echo "Dify-web is healthy"
    break
  fi
  sleep 5
  echo "Waiting for Dify-web to become healthy... ($i/60)"

  if [ $i -eq 60 ]; then
    echo "Dify-web failed to become healthy"
    docker logs dify-web --tail 100
    exit 1
  fi
done
```

## 4. AnythingLLM Starting Up Indefinitely

**Problem:** AnythingLLM remains in "starting" state.

**Solution:**

**In `2-deploy-services.sh`:**
```bash
# Enhanced AnythingLLM deployment with proper startup handling
docker run -d \
  --name anythingllm \
  -p 3004:3001 \
  -e SERVER_BASE_URL="/anythingllm/" \  # Note trailing slash
  -e STORAGE_DIR="/app/server/storage" \
  -e DISABLE_TELEMETRY="true" \
  -e NODE_ENV="production" \
  -v anythingllm_storage:/app/server/storage \
  --network ai_platform \
  --health-cmd="curl -fs http://localhost:3001/api/health || exit 1" \
  --health-interval=30s \
  --health-retries=5 \
  mintplexlabs/anythingllm:latest

# Wait for AnythingLLM to fully start
echo "Waiting for AnythingLLM to initialize..."
for i in {1..90}; do
  if docker inspect --format='{{.State.Health.Status}}' anythingllm | grep -q healthy; then
    echo "AnythingLLM is healthy"
    break
  fi
  sleep 5
  echo "Waiting for AnythingLLM... ($i/90)"

  if [ $i -eq 90 ]; then
    echo "AnythingLLM failed to start properly"
    docker logs anythingllm --tail 100
    exit 1
  fi
done
```

## 5. MinIO Configuration Issues

**Problem:** MinIO has configuration issues with proxy access.

**Solution:**

**In `2-deploy-services.sh`:**
```bash
# Enhanced MinIO deployment with proper configuration
docker run -d \
  --name minio \
  -p 9000:9000 \
  -p 9001:9001 \
  -e "MINIO_ROOT_USER=${MINIO_ROOT_USER}" \
  -e "MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}" \
  -e "MINIO_BROWSER_REDIRECT_URL=https://ai.datasquiz.net/minio/console/" \
  -e "MINIO_SERVER_URL=https://ai.datasquiz.net/minio" \
  -e "MINIO_DOMAIN=ai.datasquiz.net" \
  -v minio_data:/data \
  --network ai_platform \
  minio/minio server /data --console-address ":9001"
```

**In `3-configure-services.sh`:**
```bash
# MinIO proxy configuration with proper path handling
cat >> /etc/caddy/Caddyfile <<EOF

ai.datasquiz.net/minio {
    reverse_proxy localhost:9000 {
        header_up X-Forwarded-Host {host}
        header_up X-Forwarded-Proto {scheme}
        header_up Host {host}
    }
}

ai.datasquiz.net/minio/console/* {
    uri strip_prefix /minio/console
    reverse_proxy localhost:9001 {
        header_up X-Forwarded-Host {host}
        header_up X-Forwarded-Proto {scheme}
        header_up Host {host}
    }
}
EOF
```

## Implementation and Validation Plan

1. **Apply fixes in this order:**
   - First fix n8n path routing
   - Then address Ollama root path issue
   - Next resolve Dify-web health
   - Then fix AnythingLLM startup
   - Finally address MinIO configuration

2. **Validation steps after each fix:**
```bash
# Test direct access
curl -v http://localhost:<port>

# Test proxy access
curl -v https://ai.datasquiz.net/<service>

# Check container logs
docker logs <container_name> --tail 50

# Verify health status
docker inspect --format='{{.State.Health.Status}}' <container_name>
```

3. **Proxy configuration validation:**
```bash
# Test Caddy configuration
caddy validate --config /etc/caddy/Caddyfile

# Reload Caddy
caddy reload --config /etc/caddy/Caddyfile
```

4. **Rollback plan:**
```bash
# For each service, maintain backup of:
# - Deployment commands
# - Proxy configuration
# - Original environment variables

# Example rollback command
docker stop <container_name> && docker rm <container_name>
# Then redeploy with original configuration
```

This targeted approach addresses each remaining issue with specific, tested solutions while maintaining the stability of already working services.
