#!/bin/bash

# FOCUSED ACTION PLAN for Remaining Platform Issues
# Addresses the 7 specific issues identified

set -euo pipefail

TENANT_ID="${1:-datasquiz}"
ENV_FILE="/mnt/data/${TENANT_ID}/.env"

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

# Issue 1: Enable missing application services
enable_application_services() {
    log "=== ISSUE 1: ENABLING MISSING APPLICATION SERVICES ==="
    
    # Backup current .env
    cp "$ENV_FILE" "${ENV_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
    
    # Enable missing services
    local services=("OLLAMA" "LITELLM" "OPENWEBUI" "ANYTHINGLLM" "N8N" "FLOWISE" "DIFY")
    
    for service in "${services[@]}"; do
        if ! grep -q "ENABLE_${service}=true" "$ENV_FILE"; then
            echo "ENABLE_${service}=true" >> "$ENV_FILE"
            ok "Enabled ${service}"
        else
            ok "${service} already enabled"
        fi
    done
    
    log "Services enabled. Re-run deployment to add them to docker-compose."
}

# Issue 2: Configure OpenClaw Tailscale routing
configure_openclaw_tailscale() {
    log "=== ISSUE 2: OPENCLAW TAILSCALE ROUTING ==="
    
    # Check Tailscale status
    if sudo docker ps --filter name=ai-datasquiz-tailscale-1 --format "{{.Status}}" | grep -q "Up"; then
        log "Tailscale is running"
        log "OpenClaw requires Tailscale funnel configuration:"
        log "1. Connect to Tailscale network:"
        log "   sudo docker exec ai-datasquiz-tailscale-1 tailscale up"
        log "2. Configure funnel:"
        log "   sudo docker exec ai-datasquiz-tailscale-1 tailscale funnel 18789"
        log "3. Access OpenClaw via:"
        log "   https://<tailscale-ip>:18789"
        log "   OR http://localhost:18789 (if Tailscale IP is localhost)"
        
        # Try to get Tailscale status
        local tailscale_status=$(sudo docker exec ai-datasquiz-tailscale-1 tailscale status 2>/dev/null || echo "Not connected")
        log "Current Tailscale status: $tailscale_status"
    else
        fail "Tailscale service not running"
    fi
}

# Issue 3: Fix Rclone Google Drive sync
fix_rclone_sync() {
    log "=== ISSUE 3: RCLONE GOOGLE DRIVE SYNC ==="
    
    # Check current rclone status
    local rclone_status=$(sudo docker ps --filter name=ai-datasquiz-rclone-1 --format "{{.Status}}" | head -1)
    log "Current Rclone status: $rclone_status"
    
    # Fix FUSE issues
    log "Fixing FUSE permissions..."
    sudo modprobe fuse 2>/dev/null || true
    
    # Create proper cache directory
    sudo mkdir -p /mnt/data/${TENANT_ID}/rclone/.cache
    sudo chown -R 1001:1001 /mnt/data/${TENANT_ID}/rclone
    
    # Check if gdrive has content
    local gdrive_files=$(ls -la /mnt/data/${TENANT_ID}/gdrive/ 2>/dev/null | wc -l)
    log "Google Drive directory has $gdrive_files files"
    
    if [ "$gdrive_files" -gt 3 ]; then
        ok "Google Drive appears to be syncing"
    else
        warn "Google Drive may not be fully synced"
        log "Checking Rclone logs..."
        sudo docker logs ai-datasquiz-rclone-1 --tail 10
    fi
}

# Issue 4: Set up Qdrant vector ingestion
setup_qdrant_ingestion() {
    log "=== ISSUE 4: QDRANT VECTOR INGESTION ==="
    
    # Check Qdrant status
    local qdrant_status=$(sudo docker ps --filter name=ai-datasquiz-qdrant-1 --format "{{.Status}}" | head -1)
    log "Qdrant status: $qdrant_status"
    
    if echo "$qdrant_status" | grep -q "Up"; then
        # Test Qdrant API
        if curl -s http://localhost:6333/health >/dev/null 2>&1; then
            ok "Qdrant API is responding"
            
            # Check collections
            local collections=$(curl -s http://localhost:6333/collections 2>/dev/null | jq -r '.collections | length' 2>/dev/null || echo "0")
            log "Qdrant has $collections collections"
            
            if [ "$collections" -eq 0 ]; then
                log "No collections found - ready for ingestion"
                log "To set up ingestion:"
                log "1. Ensure Rclone is working"
                log "2. Run: sudo bash scripts/3-configure-services.sh ${TENANT_ID} ingest"
            else
                ok "Qdrant has collections - ingestion may have started"
            fi
        else
            fail "Qdrant API not responding"
        fi
    else
        fail "Qdrant service not running"
    fi
}

# Issue 5: Test LiteLLM proxy (will be enabled in Issue 1)
test_litellm_proxy() {
    log "=== ISSUE 5: LITELLM PROXY TESTING ==="
    
    # Check if LiteLLM is enabled in .env
    if grep -q "ENABLE_LITELLM=true" "$ENV_FILE"; then
        log "LiteLLM is enabled in .env"
        log "After re-running deployment, test with:"
        log "curl -X POST http://localhost:4000/v1/chat/completions \\"
        log "  -H 'Content-Type: application/json' \\"
        log "  -d '{\"model\": \"ollama/llama2\", \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"]}'"
    else
        warn "LiteLLM not enabled - will be enabled in Issue 1"
    fi
}

# Issue 6: Check Ollama resolution (already working)
check_ollama_resolution() {
    log "=== ISSUE 6: OLLAMA RESOLUTION ==="
    
    # Test ollama.ai.datasquiz.net
    if curl -k -s -m 5 https://ollama.ai.datasquiz.net >/dev/null 2>&1; then
        ok "https://ollama.ai.datasquiz.net is RESOLVING"
    else
        warn "https://ollama.ai.datasquiz.net not accessible"
    fi
    
    # Test direct port 11434
    if curl -s -m 5 http://localhost:11434/api/tags >/dev/null 2>&1; then
        ok "Ollama API responding on port 11434"
    else
        warn "Ollama API not responding on port 11434"
    fi
}

# Issue 7: Check current service URLs
check_service_urls() {
    log "=== ISSUE 7: CURRENT SERVICE URL STATUS ==="
    
    local urls=(
        "https://anythingllm.ai.datasquiz.net"
        "https://n8n.ai.datasquiz.net"
        "https://openwebui.ai.datasquiz.net"
        "https://dify.ai.datasquiz.net"
        "https://flowise.ai.datasquiz.net"
        "https://openclaw.ai.datasquiz.net"
        "https://ollama.ai.datasquiz.net"
    )
    
    for url in "${urls[@]}"; do
        if curl -k -s -m 5 "$url" >/dev/null 2>&1; then
            ok "$url - ACCESSIBLE"
        else
            warn "$url - NOT ACCESSIBLE"
        fi
    done
}

# Main execution
main() {
    log "Starting focused action plan for platform issues"
    
    check_service_urls
    check_ollama_resolution
    configure_openclaw_tailscale
    fix_rclone_sync
    setup_qdrant_ingestion
    test_litellm_proxy
    enable_application_services
    
    log ""
    log "=== SUMMARY OF ACTIONS NEEDED ==="
    log "1. Re-run deployment to add newly enabled services:"
    log "   sudo bash scripts/2-deploy-services.sh ${TENANT_ID}"
    log ""
    log "2. Configure Tailscale for OpenClaw:"
    log "   sudo docker exec ai-datasquiz-tailscale-1 tailscale up"
    log "   sudo docker exec ai-datasquiz-tailscale-1 tailscale funnel 18789"
    log ""
    log "3. Test services after deployment:"
    log "   sudo bash scripts/3-configure-services.sh ${TENANT_ID} health"
    log ""
    log "4. Set up vector ingestion once Rclone is stable:"
    log "   sudo bash scripts/3-configure-services.sh ${TENANT_ID} ingest"
    log ""
    log "5. Test LiteLLM proxy once enabled:"
    log "   curl -X POST http://localhost:4000/v1/chat/completions ..."
}

main "$@"
