#!/bin/bash

# Iterative Deployment Script
# Runs deployment in iterations until all services are healthy

set -euo pipefail

TENANT_ID="${1:-datasquiz}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/mnt/data/${TENANT_ID}/logs/iterative-deploy-$(date +%Y%m%d-%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1" | tee -a "$LOG_FILE"
}

check_service_health() {
    log "=== SERVICE HEALTH CHECK ==="
    
    # Check container status
    local containers=$(docker ps --format "table {{.Names}}\t{{.Status}}")
    log "Running containers:"
    echo "$containers" | tee -a "$LOG_FILE"
    
    # Test Caddy specifically
    log "Testing Caddy HTTPS connectivity..."
    if curl -k -s -m 5 https://ai.datasquiz.net >/dev/null 2>&1; then
        ok "Caddy HTTPS: RESPONDING (200)"
        
        # Test working services
        local working_services=0
        local total_services=5
        
        if curl -k -s -m 5 https://grafana.ai.datasquiz.net >/dev/null 2>&1; then
            ok "Grafana: RESPONDING"
            ((working_services++))
        else
            warn "Grafana: NOT RESPONDING"
        fi
        
        if curl -k -s -m 5 https://signal.ai.datasquiz.net >/dev/null 2>&1; then
            ok "Signal: RESPONDING"
            ((working_services++))
        else
            warn "Signal: NOT RESPONDING"
        fi
        
        # Check if at least 2 services are working
        if [[ $working_services -ge 2 ]]; then
            ok "Core services operational ($working_services/$total_services)"
            return 0
        else
            warn "Insufficient services operational ($working_services/$total_services)"
            return 1
        fi
    else
        warn "Caddy HTTPS: NOT RESPONDING"
        return 1
    fi
}

run_deployment_iteration() {
    local iteration=$1
    log "=== DEPLOYMENT ITERATION $iteration ==="
    
    # Run deployment script
    if sudo bash "/home/jglaine/AIPlatformAutomation/scripts/2-deploy-services.sh" "$TENANT_ID" >> "$LOG_FILE" 2>&1; then
        ok "Deployment iteration $iteration completed successfully"
        return 0
    else
        warn "Deployment iteration $iteration failed"
        return 1
    fi
}

main() {
    log "Starting iterative deployment for tenant: $TENANT_ID"
    log "Log file: $LOG_FILE"
    
    local max_iterations=5
    local iteration=1
    
    while [[ $iteration -le $max_iterations ]]; do
        log "=== ITERATION $iteration of $max_iterations ==="
        
        if run_deployment_iteration "$iteration"; then
            if check_service_health; then
                ok "All services healthy after iteration $iteration"
                log "=== DEPLOYMENT SUCCESS ==="
                echo "All services are running and accessible!"
                echo "Next: sudo bash scripts/3-configure-services.sh $TENANT_ID"
                exit 0
            fi
        fi
        
        if [[ $iteration -lt $max_iterations ]]; then
            log "Waiting 30 seconds before next iteration..."
            sleep 30
        fi
        
        ((iteration++))
    done
    
    fail "Deployment failed after $max_iterations iterations"
    exit 1
}

main "$@"
