#!/usr/bin/env bash
# Health Check Script v100.0.0

source "$(dirname "$0")/../.env"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "=== AI Platform Health Check ==="

# Check Docker daemon
if ! docker info &>/dev/null; then
    log "ERROR: Docker daemon not running"
    exit 1
fi

# Check containers
declare -a required_containers=("ollama" "webui")

if [[ "$ENABLE_LITELLM" == "true" ]]; then
    required_containers+=("litellm")
fi

if [[ "$ENABLE_POSTGRES" == "true" ]]; then
    required_containers+=("postgres")
fi

if [[ "$ENABLE_REDIS" == "true" ]]; then
    required_containers+=("redis")
fi

if [[ "$ENABLE_CADDY" == "true" ]]; then
    required_containers+=("caddy")
fi

if [[ "$ENABLE_NGINX" == "true" ]]; then
    required_containers+=("nginx")
fi

if [[ "$ENABLE_SIGNAL_API" == "true" ]]; then
    required_containers+=("signal-api")
fi

all_healthy=true

for container in "${required_containers[@]}"; do
    if docker ps --filter "name=ai-platform-${container}" --filter "status=running" | grep -q "${container}"; then
        log "✓ ${container} is running"
    else
        log "✗ ${container} is NOT running"
        all_healthy=false
    fi
done

# Check disk space
free_space=$(df -BG "${ROOT_PATH}" | awk 'NR==2 {print $4}' | sed 's/G//')
if [[ $free_space -lt 10 ]]; then
    log "WARNING: Low disk space: ${free_space}GB remaining"
fi

if $all_healthy; then
    log "=== All services healthy ==="
    exit 0
else
    log "=== Some services unhealthy ==="
    exit 1
fi
