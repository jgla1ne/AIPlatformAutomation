# Refactored Plan for AI Platform Service Accessibility Issues

After reviewing the current state where several services (AnythingLLM, n8n, etc.) are still not accessible despite the proxy configuration changes, I'll propose a more targeted refactoring plan that addresses the root causes while maintaining system stability.

## Current Analysis

The persistent 502 errors suggest:
1. Services may not be properly binding to their designated ports
2. Proxy configurations might not match the actual service requirements
3. Some services may need specific headers or path adjustments
4. Health checks might be failing silently

## Comprehensive Refactoring Plan

### Phase 1: Enhanced Service Verification (2-deploy-services.sh)

1. **Add detailed service status verification**:
```bash
verify_service() {
    local service=$1
    local port=$2
    local health_endpoint=${3:-"/"}

    echo "Verifying $service on port $port..."
    if ! ss -tuln | grep -q ":$port "; then
        echo "❌ Port $port not in use"
        return 1
    fi

    if ! timeout 5 curl -sSf "http://localhost:$port$health_endpoint" >/dev/null 2>&1; then
        echo "❌ $service not responding on port $port"
        return 1
    fi

    echo "✅ $service is healthy on port $port"
    return 0
}
```

2. **Add service-specific verification**:
```bash
# After service deployments
declare -A SERVICE_PORTS=(
    ["flowise"]=3000
    ["grafana"]=3001
    ["n8n"]=5678
    ["ollama"]=11434
    ["openclaw"]=3002
    ["dify"]=3003
    ["anythingllm"]=3004
    ["litellm"]=4000
    ["openwebui"]=3005
    ["signal"]=3006
    ["minio"]=9000
)

declare -A SERVICE_HEALTH_ENDPOINTS=(
    ["flowise"]="/api/v1/ping"
    ["grafana"]="/api/health"
    ["n8n"]="/healthz"
    ["openclaw"]="/health"
    ["dify"]="/health"
    ["anythingllm"]="/api/health"
    ["litellm"]="/health/ready"
    ["openwebui"]="/health"
    ["minio"]="/minio/health/live"
)

for service in "${!SERVICE_PORTS[@]}"; do
    verify_service "$service" "${SERVICE_PORTS[$service]}" "${SERVICE_HEALTH_ENDPOINTS[$service]}" || {
        echo "Attempting to restart $service..."
        # Add service-specific restart commands here
        docker restart "${service}" >/dev/null 2>&1 || true
        sleep 5
        verify_service "$service" "${SERVICE_PORTS[$service]}" "${SERVICE_HEALTH_ENDPOINTS[$service]}" || {
            echo "⚠️ $service failed to start properly"
        }
    }
done
```

### Phase 2: Proxy Configuration Refinement (3-configure-services.sh)

1. **Standardized proxy configuration with service-specific adjustments**:
```bash
configure_proxy() {
    local service=$1
    local port=$2
    local path=$3
    local additional_config=$4

    cat >> /etc/nginx/sites-available/ai-platform <<EOF

location ${path} {
    proxy_pass http://localhost:${port};
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;

    # WebSocket support
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";

    # Service-specific configurations
    ${additional_config}
}
EOF
}
```

2. **Service-specific proxy configurations**:
```bash
# AnythingLLM
configure_proxy "anythingllm" "3004" "/anythingllm/" "
    proxy_set_header X-Forwarded-Prefix /anythingllm;
    rewrite ^/anythingllm/(.*)$ /\$1 break;
"

# n8n
configure_proxy "n8n" "5678" "/n8n/" "
    proxy_set_header X-n8n-Path /n8n;
    rewrite ^/n8n/(.*)$ /\$1 break;
"

# Open WebUI
configure_proxy "openwebui" "3005" "/openwebui/" "
    rewrite ^/openwebui/(.*)$ /\$1 break;
"

# MinIO
configure_proxy "minio" "9000" "/minio/" "
    rewrite ^/minio/(.*)$ /\$1 break;
    proxy_set_header X-Forwarded-Prefix /minio;
"
```

### Phase 3: Service-Specific Fixes

1. **AnythingLLM configuration**:
```bash
# In 2-deploy-services.sh, ensure AnythingLLM has proper base path
docker run -d \
    --name anythingllm \
    -p 3004:3001 \
    -e SERVER_BASE_URL="/anythingllm" \
    # ... other parameters
```

2. **n8n configuration**:
```bash
# In 2-deploy-services.sh, ensure n8n has proper path configuration
docker run -d \
    --name n8n \
    -p 5678:5678 \
    -e N8N_PATH="/n8n" \
    # ... other parameters
```

### Phase 4: Enhanced Testing Framework

1. **Add comprehensive proxy testing**:
```bash
test_proxy() {
    local service=$1
    local path=$2
    local expected_status=${3:-200}

    echo "Testing $service proxy..."
    response=$(curl -s -o /dev/null -w "%{http_code}" "https://ai.datasquiz.net${path}")

    if [ "$response" -eq "$expected_status" ]; then
        echo "✅ $service proxy test passed"
        return 0
    else
        echo "❌ $service proxy test failed with HTTP $response"
        return 1
    fi
}

# Test all services
test_proxy "flowise" "/flowise/api/v1/ping"
test_proxy "grafana" "/grafana/api/health"
test_proxy "n8n" "/n8n/healthz"
test_proxy "anythingllm" "/anythingllm/api/health"
test_proxy "openwebui" "/openwebui/health"
test_proxy "minio" "/minio/health/live"
```

### Phase 5: Fallback and Recovery

1. **Add automatic recovery mechanism**:
```bash
# In 3-configure-services.sh, after proxy configuration
if ! nginx -t; then
    echo "❌ Nginx configuration test failed"
    echo "Restoring previous configuration..."
    cp /etc/nginx/sites-available/ai-platform.bak /etc/nginx/sites-available/ai-platform
    nginx -t && systemctl reload nginx
    exit 1
fi
```

## Implementation Recommendations

1. **Implement in this order**:
   - First add the enhanced service verification
   - Then implement the refined proxy configuration
   - Add service-specific fixes
   - Finally implement the testing framework

2. **Test incrementally**:
   - Verify each service locally before testing through proxy
   - Test one service at a time through the proxy
   - Ensure Dify continues to work after each change

3. **Monitor logs**:
```bash
# Add to 3-configure-services.sh
echo "Monitoring service logs for errors..."
for service in anythingllm n8n openwebui; do
    echo "=== $service logs ==="
    docker logs "$service" --tail 50
    echo
done
```

4. **Add timeout handling**:
```bash
# In 2-deploy-services.sh, after service starts
echo "Waiting for services to stabilize..."
for i in {1..30}; do
    if verify_service "anythingllm" "3004" "/api/health" && \
       verify_service "n8n" "5678" "/healthz"; then
        break
    fi
    sleep 5
done
```

This plan provides a systematic approach to identify and resolve the remaining service accessibility issues while maintaining the existing functionality. The key improvements are in service verification, proxy configuration standardization, and comprehensive testing.
