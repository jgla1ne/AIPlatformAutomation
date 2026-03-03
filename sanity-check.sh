#!/usr/bin/env bash
# =============================================================================
# Sanity Check Script for AI Platform Automation
# =============================================================================
# PURPOSE: Comprehensive verification of .env files and script configurations
# USAGE:   sudo bash sanity-check.sh
# =============================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

log_info() { echo -e "${CYAN}ℹ️   $*${NC}"; ((TOTAL_CHECKS++)); }
log_pass() { echo -e "${GREEN}✅   $*${NC}"; ((PASSED_CHECKS++)); }
log_fail() { echo -e "${RED}❌   $*${NC}"; ((FAILED_CHECKS++)); }
log_warn() { echo -e "${YELLOW}⚠️   $*${NC}"; ((WARNINGS++)); }

echo "==============================================================================="
echo "                    AI Platform Automation - Sanity Check"
echo "==============================================================================="
echo ""

# Check 1: Script syntax validation
log_info "Checking script syntax..."
if bash -n scripts/0-complete-cleanup.sh && \
   bash -n scripts/1-setup-system.sh && \
   bash -n scripts/2-deploy-services.sh && \
   bash -n scripts/3-configure-services.sh && \
   bash -n scripts/4-add-service.sh; then
    log_pass "All scripts have valid syntax"
else
    log_fail "Script syntax errors detected"
fi

# Check 2: Shebang validation
log_info "Checking script shebangs..."
for script in scripts/*.sh; do
    if head -n1 "$script" | grep -q "^#!/usr/bin/env bash"; then
        continue
    else
        log_fail "Invalid shebang in $script"
        break
    fi
done
log_pass "All scripts have correct shebangs"

# Check 3: Environment file structure
log_info "Checking .env file structure..."
if [[ -f "/mnt/data/u1001/.env" ]]; then
    ENV_FILE="/mnt/data/u1001/.env"
elif [[ -f "/mnt/data"/*/.env ]]; then
    ENV_FILE=$(find /mnt/data -name ".env" -type f | head -1)
else
    log_warn "No .env file found - this is expected before running script 1"
    ENV_FILE=""
fi

if [[ -n "$ENV_FILE" ]]; then
    log_info "Found .env at $ENV_FILE"
    
    # Check critical variables
    critical_vars=("TENANT_ID" "DATA_ROOT" "COMPOSE_PROJECT_NAME" "DOCKER_NETWORK")
    for var in "${critical_vars[@]}"; do
        if grep -q "^${var}=" "$ENV_FILE"; then
            log_pass "$var defined in .env"
        else
            log_fail "$var missing from .env"
        fi
    done
    
    # Check port conflicts
    log_info "Checking for port conflicts in .env..."
    ports=$(grep "_PORT=" "$ENV_FILE" | cut -d= -f2 | sort -n)
    duplicate_ports=$(echo "$ports" | uniq -d)
    if [[ -z "$duplicate_ports" ]]; then
        log_pass "No duplicate ports found"
    else
        log_fail "Duplicate ports: $duplicate_ports"
    fi
fi

# Check 4: Docker availability
log_info "Checking Docker installation..."
if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
        log_pass "Docker is running and accessible"
    else
        log_fail "Docker installed but not running"
    fi
else
    log_fail "Docker not installed"
fi

# Check 5: Docker Compose availability
log_info "Checking Docker Compose..."
if docker compose version >/dev/null 2>&1; then
    log_pass "Docker Compose plugin available"
else
    log_fail "Docker Compose plugin not available"
fi

# Check 6: Script function dependencies
log_info "Checking script function dependencies..."
script_functions=(
    "scripts/2-deploy-services.sh:compose_append"
    "scripts/2-deploy-services.sh:append_postgres"
    "scripts/2-deploy-services.sh:append_redis"
    "scripts/2-deploy-services.sh:append_caddy"
    "scripts/2-deploy-services.sh:append_ollama"
    "scripts/2-deploy-services.sh:append_openwebui"
    "scripts/2-deploy-services.sh:append_n8n"
    "scripts/2-deploy-services.sh:append_grafana"
)

for func_def in "${script_functions[@]}"; do
    script="${func_def%:*}"
    func="${func_def#*:}"
    if grep -q "^$func()" "$script"; then
        log_pass "$func() defined in $script"
    else
        log_fail "$func() missing from $script"
    fi
done

# Check 7: Health check endpoints
log_info "Checking health check endpoints..."
health_checks=(
    "scripts/2-deploy-services.sh:localhost:8080/health:OpenWebUI"
    "scripts/2-deploy-services.sh:localhost:4000/health/readiness:LiteLLM"
    "scripts/2-deploy-services.sh:localhost:6333/:Qdrant"
    "scripts/2-deploy-services.sh:localhost:3000/api/health:Grafana"
)

for check in "${health_checks[@]}"; do
    script="${check%:*:*}"
    endpoint="${check#*:}"
    endpoint="${endpoint%:*}"
    service="${check##*:}"
    
    if grep -q "$endpoint" "$script"; then
        log_pass "$service health check uses $endpoint"
    else
        log_fail "$service health check incorrect/missing"
    fi
done

# Check 8: Network mode configurations
log_info "Checking network mode configurations..."
if grep -q "PROXY_TYPE" scripts/2-deploy-services.sh; then
    log_pass "PROXY_TYPE variable used for network configuration"
else
    log_fail "PROXY_TYPE not used for network configuration"
fi

# Check 9: Volume declarations
log_info "Checking volume declarations..."
volumes=(
    "postgres_data"
    "redis_data"
    "ollama_data"
    "openwebui_data"
    "n8n_data"
    "grafana_data"
    "prometheus_data"
)

for volume in "${volumes[@]}"; do
    if grep -q "$volume" scripts/2-deploy-services.sh; then
        log_pass "$volume volume declared"
    else
        log_fail "$volume volume missing"
    fi
done

# Check 10: Security configurations
log_info "Checking security configurations..."
if grep -q "user:" scripts/2-deploy-services.sh; then
    log_pass "Container user specifications found"
else
    log_warn "No container user specifications found"
fi

if grep -q "TENANT_UID" scripts/2-deploy-services.sh; then
    log_pass "TENANT_UID used for container permissions"
else
    log_fail "TENANT_UID not used for container permissions"
fi

# Results Summary
echo ""
echo "==============================================================================="
echo "                           Sanity Check Results"
echo "==============================================================================="
echo -e "Total Checks: ${CYAN}$TOTAL_CHECKS${NC}"
echo -e "Passed:       ${GREEN}$PASSED_CHECKS${NC}"
echo -e "Failed:       ${RED}$FAILED_CHECKS${NC}"
echo -e "Warnings:     ${YELLOW}$WARNINGS${NC}"

if [[ $FAILED_CHECKS -eq 0 ]]; then
    echo ""
    log_pass "All critical checks passed! Platform is ready for deployment."
    exit 0
else
    echo ""
    log_fail "$FAILED_CHECKS critical issues found. Fix before deployment."
    exit 1
fi
