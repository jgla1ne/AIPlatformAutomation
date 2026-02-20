# Refactoring Plan for AI Platform Automation Proxy Configuration

Based on the current state where only Dify is working through the proxy while other services return 502 errors, I'll propose a minimal refactoring plan that focuses on fixing the proxy configuration without introducing regressions.

## Analysis

The issue appears to be in the proxy configuration (likely in `2-deploy-services.sh` or `3-configure-services.sh`) where:
1. The proxy is correctly configured for Dify
2. Other services are either:
   - Not properly configured in the proxy
   - Not running/healthy when the proxy tries to connect
   - Missing proper path-based routing rules

## Refactoring Plan

### Phase 1: Diagnostic Steps (Before Making Changes)

1. **Add health check verification** in `3-configure-services.sh`:
   ```bash
   # Add before proxy configuration
   echo "Verifying service health before proxy configuration..."
   for service in flowise grafana n8n ollama openclaw anythingllm litellm openwebui signal minio; do
     if ! curl -sSf "http://localhost:${SERVICE_PORTS[$service]}/health" >/dev/null 2>&1; then
       echo "⚠️ Service $service is not responding on port ${SERVICE_PORTS[$service]}"
     else
       echo "✅ Service $service is healthy"
     fi
   done
   ```

2. **Add proxy configuration verification**:
   ```bash
   # Add after proxy configuration
   echo "Verifying proxy configuration..."
   for service in flowise grafana n8n openclaw anythingllm litellm openwebui signal minio; do
     if ! grep -q "location /${service}" /etc/nginx/sites-available/ai-platform; then
       echo "⚠️ Proxy configuration missing for $service"
     fi
   done
   ```

### Phase 2: Minimal Proxy Configuration Fixes

1. **Standardize proxy configuration** in `3-configure-services.sh`:
   ```bash
   # Replace individual proxy configurations with a standardized approach
   for service in flowise grafana n8n openclaw anythingllm litellm openwebui signal minio; do
     cat >> /etc/nginx/sites-available/ai-platform <<EOF

   location /${service} {
       proxy_pass http://localhost:${SERVICE_PORTS[$service]};
       proxy_set_header Host \$host;
       proxy_set_header X-Real-IP \$remote_addr;
       proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
       proxy_set_header X-Forwarded-Proto \$scheme;

       # WebSocket support
       proxy_http_version 1.1;
       proxy_set_header Upgrade \$http_upgrade;
       proxy_set_header Connection "upgrade";
   }
   EOF
   done
   ```

2. **Add proper path rewriting** for services that need it:
   ```bash
   # For services that expect to be at root (like Open WebUI)
   cat >> /etc/nginx/sites-available/ai-platform <<EOF

   location /openwebui/ {
       proxy_pass http://localhost:${SERVICE_PORTS[openwebui]}/;
       proxy_set_header Host \$host;
       proxy_set_header X-Real-IP \$remote_addr;
       proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
       proxy_set_header X-Forwarded-Proto \$scheme;

       # Rewrite the path
       rewrite ^/openwebui/(.*)$ /\$1 break;
   }
   EOF
   ```

### Phase 3: Service-Specific Adjustments

1. **Add service-specific configurations** in `3-configure-services.sh`:
   ```bash
   # Flowise specific
   cat >> /etc/nginx/sites-available/ai-platform <<EOF
   location /flowise/ {
       proxy_pass http://localhost:${SERVICE_PORTS[flowise]}/;
       proxy_set_header Host \$host;
       proxy_set_header X-Real-IP \$remote_addr;
       proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
       proxy_set_header X-Forwarded-Proto \$scheme;
   }
   EOF

   # Grafana specific
   cat >> /etc/nginx/sites-available/ai-platform <<EOF
   location /grafana/ {
       proxy_pass http://localhost:${SERVICE_PORTS[grafana]}/;
       proxy_set_header Host \$host;
       proxy_set_header X-Real-IP \$remote_addr;
   }
   EOF
   ```

### Phase 4: Validation and Testing

1. **Add automated testing** in `3-configure-services.sh`:
   ```bash
   # Add after nginx reload
   echo "Testing proxy configuration..."
   for service in flowise grafana n8n openclaw anythingllm litellm openwebui signal minio; do
     if ! curl -sSf "https://ai.datasquiz.net/${service}" >/dev/null 2>&1; then
       echo "❌ Proxy test failed for $service"
       exit 1
     else
       echo "✅ Proxy test passed for $service"
     fi
   done
   ```

2. **Add cleanup safety net** in `0-complete-cleanup.sh`:
   ```bash
   # Add before nginx cleanup
   echo "Backing up current nginx configuration..."
   cp /etc/nginx/sites-available/ai-platform /tmp/ai-platform-nginx-backup-$(date +%s).conf
   ```

## Implementation Recommendations

1. **Implement in stages**:
   - First add the diagnostic checks
   - Then implement the standardized proxy configuration
   - Finally add service-specific adjustments

2. **Test each stage**:
   - After each change, verify Dify still works
   - Check if any other services start working
   - Only proceed if no regressions are introduced

3. **Document changes**:
   - Add comments explaining each proxy configuration
   - Document any service-specific requirements

4. **Consider adding**:
   ```bash
   # In 2-deploy-services.sh, ensure services are started before proxy config
   echo "Waiting for services to initialize..."
   sleep 30  # Adjust based on actual service startup times
   ```

This approach maintains the existing logic while systematically addressing the proxy configuration issues with minimal risk of regression.
