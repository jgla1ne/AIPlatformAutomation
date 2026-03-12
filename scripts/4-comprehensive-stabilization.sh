#!/bin/bash

# Comprehensive Platform Stabilization Script
# Addresses all remaining issues identified in the analysis

set -euo pipefail

TENANT_ID="${1:-datasquiz}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
}

# Phase 1: Infrastructure Fixes
fix_infrastructure() {
    log "=== PHASE 1: INFRASTRUCTURE FIXES ==="
    
    # Fix Rclone FUSE issues
    log "Fixing Rclone FUSE mount issues..."
    sudo modprobe fuse 2>/dev/null || true
    sudo systemctl enable fuse 2>/dev/null || true
    
    # Create proper cache directory for rclone
    sudo mkdir -p /mnt/data/${TENANT_ID}/rclone/.cache
    sudo chown -R 1001:1001 /mnt/data/${TENANT_ID}/rclone
    
    # Fix Qdrant data directory permissions
    sudo mkdir -p /mnt/data/${TENANT_ID}/qdrant
    sudo chown -R 1000:1000 /mnt/data/${TENANT_ID}/qdrant
    
    # Restart critical services
    log "Restarting critical infrastructure services..."
    sudo docker restart ai-datasquiz-rclone-1 2>/dev/null || true
    sudo docker restart ai-datasquiz-qdrant-1 2>/dev/null || true
    
    sleep 10
}

# Phase 2: Start Application Services
start_application_services() {
    log "=== PHASE 2: STARTING APPLICATION SERVICES ==="
    
    # List of services to start
    local services=("ollama" "litellm" "openwebui" "anythingllm" "n8n" "flowise" "dify")
    
    for service in "${services[@]}"; do
        log "Starting ${service}..."
        if sudo bash "${SCRIPT_DIR}/3-configure-services.sh" "${TENANT_ID}" --start "${service}" 2>/dev/null; then
            ok "${service} started successfully"
        else
            warn "${service} failed to start (may not be enabled)"
        fi
        sleep 5
    done
}

# Phase 3: Network Configuration
configure_networking() {
    log "=== PHASE 3: NETWORK CONFIGURATION ==="
    
    # Add Ollama to Caddyfile if not already present
    local caddyfile="/mnt/data/${TENANT_ID}/caddy/Caddyfile"
    if ! grep -q "ollama.ai.datasquiz.net" "$caddyfile"; then
        log "Adding Ollama to Caddyfile..."
        echo "ollama.ai.datasquiz.net {
    reverse_proxy ollama:11434
    tls internal
}" >> "$caddyfile"
        
        # Restart Caddy to apply changes
        sudo docker restart ai-datasquiz-caddy-1
        ok "Ollama route added to Caddyfile"
    else
        ok "Ollama already configured in Caddyfile"
    fi
    
    # Configure Tailscale for OpenClaw
    log "Configuring Tailscale for OpenClaw access..."
    # This will be handled in the next phase
}

# Phase 4: Data Integration
setup_data_integration() {
    log "=== PHASE 4: DATA INTEGRATION ==="
    
    # Test Rclone connection
    log "Testing Rclone Google Drive connection..."
    if sudo docker ps --filter name=ai-datasquiz-rclone-1 --format "{{.Status}}" | grep -q "Up"; then
        # Check if gdrive directory is populated
        sleep 30  # Give rclone time to mount
        if [ "$(ls -A /mnt/data/${TENANT_ID}/gdrive/ 2>/dev/null)" ]; then
            ok "Google Drive mounted successfully"
        else
            warn "Google Drive directory still empty - checking logs..."
            sudo docker logs ai-datasquiz-rclone-1 --tail 10
        fi
    else
        fail "Rclone service not running"
    fi
    
    # Test Qdrant connectivity
    log "Testing Qdrant vector database..."
    if sudo docker ps --filter name=ai-datasquiz-qdrant-1 --format "{{.Status}}" | grep -q "Up"; then
        if curl -s http://localhost:6333/health >/dev/null 2>&1; then
            ok "Qdrant is responding"
        else
            warn "Qdrant not responding on port 6333"
        fi
    else
        fail "Qdrant service not running"
    fi
}

# Phase 5: LLM Proxy Testing
test_llm_proxy() {
    log "=== PHASE 5: LLM PROXY TESTING ==="
    
    # Test LiteLLM if running
    if sudo docker ps --filter name=ai-datasquiz-litellm-1 --format "{{.Status}}" | grep -q "Up"; then
        log "Testing LiteLLM proxy..."
        if curl -s http://localhost:4000/health >/dev/null 2>&1; then
            ok "LiteLLM proxy is responding"
            
            # Test model routing
            log "Testing Ollama model via LiteLLM..."
            if curl -s -X POST http://localhost:4000/v1/chat/completions \
                -H "Content-Type: application/json" \
                -d '{"model": "ollama/llama2", "messages": [{"role": "user", "content": "Hello"}]}' \
                --max-time 10 >/dev/null 2>&1; then
                ok "LiteLLM proxy to Ollama working"
            else
                warn "LiteLLM proxy test failed - Ollama may not be ready"
            fi
        else
            warn "LiteLLM not responding on port 4000"
        fi
    else
        warn "LiteLLM service not running"
    fi
}

# Phase 6: OpenClaw Tailscale Configuration
configure_openclaw() {
    log "=== PHASE 6: OPENCLAW TAILSCALE CONFIGURATION ==="
    
    # Note: OpenClaw requires Tailscale funnel on port 18789
    log "OpenClaw requires Tailscale funnel configuration..."
    log "Current status: OpenClaw should be accessible via Tailscale IP on port 18789"
    log "To configure Tailscale funnel:"
    log "1. Connect to Tailscale network"
    log "2. Run: tailscale funnel 18789"
    log "3. Access OpenClaw via: https://<tailscale-ip>:18789"
}

# Final Status Check
final_status() {
    log "=== FINAL STATUS CHECK ==="
    
    echo ""
    echo "=== SERVICE STATUS ==="
    sudo docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(ollama|litellm|openwebui|anythingllm|n8n|flowise|dify|qdrant|rclone)" || echo "No application services running"
    
    echo ""
    echo "=== URL ACCESSIBILITY ==="
    local urls=(
        "https://ollama.ai.datasquiz.net"
        "https://openwebui.ai.datasquiz.net"
        "https://anythingllm.ai.datasquiz.net"
        "https://n8n.ai.datasquiz.net"
        "https://flowise.ai.datasquiz.net"
    )
    
    for url in "${urls[@]}"; do
        if curl -k -s -m 5 "$url" >/dev/null 2>&1; then
            ok "$url - ACCESSIBLE"
        else
            warn "$url - NOT ACCESSIBLE"
        fi
    done
    
    echo ""
    echo "=== DATA DIRECTORIES ==="
    echo "Google Drive: $(ls -la /mnt/data/${TENANT_ID}/gdrive/ 2>/dev/null | wc -l) files"
    echo "Qdrant: $(sudo docker ps --filter name=ai-datasquiz-qdrant-1 --format "{{.Status}}" | head -1)"
    echo "Rclone: $(sudo docker ps --filter name=ai-datasquiz-rclone-1 --format "{{.Status}}" | head -1)"
}

# Main execution
main() {
    log "Starting comprehensive platform stabilization for tenant: ${TENANT_ID}"
    
    fix_infrastructure
    start_application_services
    configure_networking
    setup_data_integration
    test_llm_proxy
    configure_openclaw
    final_status
    
    log "Comprehensive stabilization completed!"
    log "Next steps:"
    log "1. Check individual service logs for any remaining issues"
    log "2. Configure Tailscale funnel for OpenClaw access"
    log "3. Test Google Drive sync and vector ingestion"
    log "4. Verify LLM proxy routing between Ollama and external providers"
}

main "$@"
