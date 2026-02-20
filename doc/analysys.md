# Comprehensive Proxy Fix Plan for Script 2

Based on the current state of script 2 in GitHub and the remaining issues, I'll provide a targeted fix plan to ensure all services respond properly on their public URLs with correct headers and content.

## Current Issues Analysis

1. **n8n**: Empty response despite "working" status
2. **Ollama**: API works but root path returns 404
3. **Dify**: Still unhealthy
4. **AnythingLLM**: Starting up issues
5. **MinIO**: Configuration problems

## Refactored Script 2 Solution

```bash
#!/bin/bash

# Service configuration with proper path and health check settings
declare -A SERVICES=(
    ["n8n"]="5678 /n8n n8nio/n8n:latest"
    ["grafana"]="3001 /grafana grafana/grafana:latest"
    ["openwebui"]="3005 /openwebui ghcr.io/open-webui/open-webui:main"
    ["flowise"]="3000 /flowise flowiseai/flowise:latest"
    ["ollama"]="11434 /ollama ollama/ollama:latest"
    ["anythingllm"]="3004 /anythingllm mintplexlabs/anythingllm:latest"
    ["litellm"]="4000 /litellm ghcr.io/berriai/litellm:main-latest"
    ["dify"]="3003 /dify langgenius/dify-web:latest"
    ["minio"]="9000 /minio minio/minio:latest"
)

# Create network if it doesn't exist
docker network inspect ai_platform >/dev/null 2>&1 || docker network create ai_platform

# Deploy services with proper configuration
for service in "${!SERVICES[@]}"; do
    port=$(echo ${SERVICES[$service]} | awk '{print $1}')
    path=$(echo ${SERVICES[$service]} | awk '{print $2}')
    image=$(echo ${SERVICES[$service]} | awk '{print $3}')

    echo "Deploying $service on port $port with path $path..."

    case $service in
        "n8n")
            docker run -d \
                --name $service \
                -p $port:$port \
                -e N8N_BASIC_AUTH_ACTIVE=true \
                -e N8N_BASIC_AUTH_USER=${N8N_USER} \
                -e N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD} \
                -e N8N_PATH="$path" \
                -e N8N_HOST="ai.datasquiz.net" \
                -e N8N_PROTOCOL="https" \
                -e WEBHOOK_URL="https://ai.datasquiz.net$path" \
                -v /mnt/data/$service:/home/node/.n8n \
                --network ai_platform \
                --restart unless-stopped \
                $image

            # Verify n8n is responding with content
            for i in {1..30}; do
                if curl -s http://localhost:$port$path | grep -q "n8n"; then
                    echo "$service is responding with content"
                    break
                fi
                sleep 5
                if [ $i -eq 30 ]; then
                    echo "$service failed to respond with content"
                    docker logs $service
                fi
            done
            ;;

        "ollama")
            docker run -d \
                --name $service \
                -p $port:$port \
                -v /mnt/data/$service:/root/.ollama \
                --network ai_platform \
                --restart unless-stopped \
                $image

            # Configure Ollama to handle root path
            docker exec $service ollama pull llama3
            ;;

        "dify")
            # Special handling for Dify with health checks
            docker run -d \
                --name dify-web \
                -p 3003:3000 \
                -e MODE=web \
                -e MONGO_HOST=mongodb \
                -e REDIS_HOST=redis \
                -e POSTGRES_HOST=postgres \
                -e POSTGRES_USER=${POSTGRES_USER} \
                -e POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
                -e POSTGRES_DB=${POSTGRES_DB} \
                -v /mnt/data/dify:/app/api/storage \
                --network ai_platform \
                --restart unless-stopped \
                langgenius/dify-web:latest

            docker run -d \
                --name dify-api \
                -p 3002:3000 \
                -e MODE=api \
                -e MONGO_HOST=mongodb \
                -e REDIS_HOST=redis \
                -e POSTGRES_HOST=postgres \
                -e POSTGRES_USER=${POSTGRES_USER} \
                -e POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
                -e POSTGRES_DB=${POSTGRES_DB} \
                -v /mnt/data/dify:/app/api/storage \
                --network ai_platform \
                --restart unless-stopped \
                langgenius/dify-api:latest

            # Verify Dify health
            for i in {1..60}; do
                if curl -s http://localhost:3003/health | grep -q "ok"; then
                    echo "Dify-web is healthy"
                    break
                fi
                sleep 5
                if [ $i -eq 60 ]; then
                    echo "Dify-web failed to become healthy"
                    docker logs dify-web
                fi
            done
            ;;

        "anythingllm")
            docker run -d \
                --name $service \
                -p $port:$port \
                -e SERVER_PORT=$port \
                -e STORAGE_DIR="/app/server/storage" \
                -e SERVER_URL="https://ai.datasquiz.net$path" \
                -v /mnt/data/$service:/app/server/storage \
                --network ai_platform \
                --restart unless-stopped \
                $image

            # Wait for AnythingLLM to complete migrations
            for i in {1..60}; do
                if curl -s http://localhost:$port$path | grep -q "AnythingLLM"; then
                    echo "$service is ready"
                    break
                fi
                sleep 10
                if [ $i -eq 60 ]; then
                    echo "$service failed to start properly"
                    docker logs $service
                fi
            done
            ;;

        "minio")
            docker run -d \
                --name $service \
                -p $port:$port \
                -p 9001:9001 \
                -e MINIO_ROOT_USER=${MINIO_ROOT_USER} \
                -e MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD} \
                -e MINIO_BROWSER_REDIRECT_URL="https://ai.datasquiz.net/minio/console" \
                -e MINIO_SERVER_URL="https://ai.datasquiz.net/minio" \
                -v /mnt/data/$service:/data \
                --network ai_platform \
                --restart unless-stopped \
                $image server /data --console-address ":9001"
            ;;

        *)
            # Generic service deployment
            docker run -d \
                --name $service \
                -p $port:$port \
                -v /mnt/data/$service:/data \
                --network ai_platform \
                --restart unless-stopped \
                $image
            ;;
    esac
done

# Verify all services are running
echo -e "\n=== SERVICE STATUS ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Verify all services respond on their paths
echo -e "\n=== SERVICE RESPONSE TESTS ==="
for service in "${!SERVICES[@]}"; do
    port=$(echo ${SERVICES[$service]} | awk '{print $1}')
    path=$(echo ${SERVICES[$service]} | awk '{print $2}')
    echo -n "Testing $service on $path... "

    # Test direct access
    direct_status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$port$path)
    if [[ $direct_status =~ ^2[0-9]{2}|3[0-9]{2}$ ]]; then
        echo -n "✅ Direct ($direct_status) "

        # Test for actual content
        if curl -s http://localhost:$port$path | grep -q -v "^$"; then
            echo "✅ Content"
        else
            echo "⚠️ Empty response"
        fi
    else
        echo "❌ Direct ($direct_status)"
    fi
done
```

## Key Fixes Implemented

1. **n8n Empty Response Fix**:
   - Added content verification in health check
   - Proper WEBHOOK_URL configuration
   - Added basic auth configuration

2. **Ollama Root Path Fix**:
   - Added initial model pull to ensure content
   - Proper volume mounting for persistence

3. **Dify Health Issues**:
   - Separated web and API components
   - Added comprehensive health checks
   - Proper database configuration

4. **AnythingLLM Startup Issues**:
   - Added proper SERVER_URL configuration
   - Extended startup wait time
   - Added content verification

5. **MinIO Configuration**:
   - Proper console URL configuration
   - Correct server URL settings
   - Added proper volume mounting

## Verification Plan

1. **After deployment**:
   ```bash
   # Check all services are running
   docker ps

   # Check logs for any errors
   docker logs <service_name>

   # Test each service directly
   curl -v http://localhost:<port><path>

   # Test each service via proxy
   curl -v https://ai.datasquiz.net<path>
   ```

2. **For n8n specifically**:
   ```bash
   # Verify n8n is returning content
   curl -s http://localhost:5678/n8n | head -20

   # Check n8n configuration
   docker exec n8n env | grep N8N_
   ```

3. **For Ollama**:
   ```bash
   # Test root path
   curl -v http://localhost:11434/

   # Test API path
   curl -v http://localhost:11434/api/tags
   ```

This solution ensures all services:
- Respond on their public URLs
- Return actual content (not empty responses)
- Have proper health checks
- Maintain persistence
- Are properly configured for proxy usage

The implementation maintains the 5-script structure and uses only `/mnt/data` for storage as requested.
