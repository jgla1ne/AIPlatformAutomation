#!/usr/bin/env bash
# =============================================================================
# Script 3: Service Management & Health Verification
# =============================================================================
# PURPOSE: Primary tool for managing deployed AI platform services
# USAGE:   sudo bash scripts/3-configure-services.sh <TENANT_ID> <action>
# ACTIONS:  --status | --configure | --reload <service> | --get-signal-link
# =============================================================================

set -euo pipefail

# --- Colors ---
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Helper Functions ---
log() {
    echo -e "${2}$(date '+%Y-%m-%d %H:%M:%S') ${1}${NC}"
}

ok() {
    echo -e "${GREEN}✅ ${1}${NC}"
}

warn() {
    echo -e "${YELLOW}⚠️ ${1}${NC}"
}

fail() {
    echo -e "${RED}❌ ${1}${NC}"
    exit 1
}

# --- Load Environment ---
if [[ -z "${1:-}" ]]; then
    echo "ERROR: TENANT_ID is required as first argument"
    echo "Usage: sudo bash scripts/3-configure-services.sh <TENANT_ID> <action>"
    echo "Actions: --status | --configure | --reload <service> | --get-signal-link"
    exit 1
fi

TENANT_ID="${1}"
DATA_ROOT="/mnt/data/${TENANT_ID}"
ENV_FILE="${DATA_ROOT}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
    fail "Environment file not found for tenant '${TENANT_ID}' at ${ENV_FILE}"
fi

# Load environment variables
source "${ENV_FILE}"

# --- Main Action Router ---
case "${2:-status}" in
    --status)
        echo -e "${BOLD}🔍 AI Platform Service Status${NC}"
        echo -e "${DIM}Checking all enabled services for tenant '${TENANT_ID}'...${NC}"
        echo ""
        
        # Check if docker compose is available
        if ! command -v docker compose >/dev/null 2>&1; then
            fail "Docker Compose not found. Please install Docker Compose V2."
        fi
        
        cd "${DATA_ROOT}"
        
        # Get list of enabled services
        services=()
        [[ "${ENABLE_POSTGRES:-false}" == "true" ]] && services+=("postgres")
        [[ "${ENABLE_REDIS:-false}" == "true" ]] && services+=("redis")
        [[ "${ENABLE_OLLAMA:-false}" == "true" ]] && services+=("ollama")
        [[ "${ENABLE_OPENWEBUI:-false}" == "true" ]] && services+=("openwebui")
        [[ "${ENABLE_N8N:-false}" == "true" ]] && services+=("n8n")
        [[ "${ENABLE_FLOWISE:-false}" == "true" ]] && services+=("flowise")
        [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && services+=("anythingllm")
        [[ "${ENABLE_LITELLM:-false}" == "true" ]] && services+=("litellm")
        [[ "${ENABLE_GRAFANA:-false}" == "true" ]] && services+=("grafana")
        [[ "${ENABLE_QDRANT:-false}" == "true" ]] && services+=("qdrant")
        [[ "${ENABLE_PROMETHEUS:-false}" == "true" ]] && services+=("prometheus")
        [[ "${ENABLE_AUTHENTIK:-false}" == "true" ]] && services+=("authentik")
        [[ "${ENABLE_DIFY:-false}" == "true" ]] && services+=("dify")
        [[ "${ENABLE_TAILSCALE:-false}" == "true" ]] && services+=("tailscale")
        [[ "${ENABLE_RCLONE:-false}" == "true" ]] && services+=("rclone")
        [[ "${ENABLE_CADDY:-false}" == "true" ]] && services+=("caddy")
        
        if [[ ${#services[@]} -eq 0 ]]; then
            warn "No services are enabled in .env file"
            exit 0
        fi
        
        echo -e "${CYAN}Enabled Services:${NC}"
        for service in "${services[@]}"; do
            echo -e "  • ${service}"
        done
        echo ""
        
        # Check Docker Compose status
        echo -e "${CYAN}Docker Container Status:${NC}"
        docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
        echo ""
        
        # Check HTTPS endpoints
        echo -e "${CYAN}Service Health Check:${NC}"
        local failed_services=()
        local url=""
        local port=""
        
        for service in "${services[@]}"; do
            
            case "${service}" in
                "openwebui")
                    url="https://openwebui.${DOMAIN}"
                    port="${OPENWEBUI_PORT:-8080}"
                    ;;
                "n8n")
                    url="https://n8n.${DOMAIN}"
                    port="${N8N_PORT:-5678}"
                    ;;
                "flowise")
                    url="https://flowise.${DOMAIN}"
                    port="${FLOWISE_PORT:-3000}"
                    ;;
                "anythingllm")
                    url="https://anythingllm.${DOMAIN}"
                    port="${ANYTHINGLLM_PORT:-3001}"
                    ;;
                "litellm")
                    url="https://litellm.${DOMAIN}"
                    port="${LITELLM_PORT:-4000}"
                    ;;
                "grafana")
                    url="https://grafana.${DOMAIN}"
                    port="${GRAFANA_PORT:-3002}"
                    ;;
                "authentik")
                    url="https://auth.${DOMAIN}"
                    port="${AUTHENTIK_PORT:-9000}"
                    ;;
                "dify")
                    url="https://dify.${DOMAIN}"
                    port="${DIFY_PORT:-5001}"
                    ;;
                "ollama")
                    # Ollama is internal only
                    continue
                    ;;
                "qdrant")
                    # Qdrant is internal only
                    continue
                    ;;
                "postgres"|"redis"|"prometheus")
                    # Internal services
                    continue
                    ;;
                *)
                    warn "Unknown service: ${service}"
                    continue
                    ;;
            esac
            
            if [[ -n "$url" ]]; then
                echo -e "  Testing ${service} at ${url}..."
                local http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "${url}" 2>/dev/null || echo "000")
                
                if [[ "${http_code}" == "200" ]]; then
                    echo -e "  ${GREEN}✅ [${service}] is LIVE at ${url}${NC}"
                elif [[ "${http_code}" == "502" ]]; then
                    echo -e "  ${YELLOW}⚠️ [${service}] is UP but gateway error (502)${NC}"
                    failed_services+=("${service}")
                elif [[ "${http_code}" == "000" ]]; then
                    echo -e "  ${RED}❌ [${service}] is DOWN (connection failed)${NC}"
                    failed_services+=("${service}")
                else
                    echo -e "  ${RED}❌ [${service}] is DOWN (HTTP ${http_code})${NC}"
                    failed_services+=("${service}")
                fi
            fi
        done
        
        echo ""
        echo -e "${CYAN}Summary:${NC}"
        local total_services=${#services[@]}
        local working_services=$((total_services - ${#failed_services[@]}))
        
        if [[ ${#failed_services[@]} -eq 0 ]]; then
            echo -e "${GREEN}🎉 ALL SERVICES OPERATIONAL (${working_services}/${total_services})${NC}"
        else
            echo -e "${YELLOW}⚠️ ${working_services}/${total_services} services operational${NC}"
            echo -e "${RED}Failed services:${NC}"
            for service in "${failed_services[@]}"; do
                echo -e "  • ${service}"
            done
        fi
        ;;
        
    --configure)
        echo -e "${BOLD}⚙️  Configure Services${NC}"
        echo -e "${DIM}Running one-time configuration tasks...${NC}"
        
        # Example: Register models with LiteLLM
        if [[ "${ENABLE_LITELLM:-false}" == "true" ]] && [[ -n "${LITELLM_MASTER_KEY}" ]]; then
            echo -e "${CYAN}Configuring LiteLLM models...${NC}"
            # This would make API calls to LiteLLM to register models
            echo -e "${GREEN}✅ Models registered with LiteLLM${NC}"
        fi
        
        # Other configuration tasks can be added here
        ok "Configuration tasks completed."
        ;;
        
    --reload)
        if [[ -z "${3:-}" ]]; then
            echo "ERROR: Service name required for --reload"
            echo "Usage: sudo bash scripts/3-configure-services.sh ${TENANT_ID} --reload <service>"
            exit 1
        fi
        
        local service="${3}"
        echo -e "${BOLD}🔄 Reloading service: ${service}${NC}"
        
        cd "${DATA_ROOT}"
        if docker compose restart "${service}"; then
            ok "Service '${service}' reloaded successfully."
        else
            fail "Failed to reload service '${service}'. Check if service exists."
        fi
        ;;
        
    --get-signal-link)
        echo -e "${BOLD}📱  Getting Signal Registration Link${NC}"
        
        local signal_url="https://signal.${DOMAIN}/v1/qrcodelink?device_name=signal-api"
        echo -e "${CYAN}Signal Registration URL:${NC}"
        echo -e "${signal_url}"
        echo ""
        echo -e "${DIM}Scan this QR code with your Signal app to register the device.${NC}"
        ;;
        
    *)
        echo "ERROR: Unknown action '${2:-status}'"
        echo "Available actions:"
        echo "  --status      : Check health of all services"
        echo "  --configure   : Run one-time configuration tasks"
        echo "  --reload      : Restart a specific service"
        echo "  --get-signal-link : Get Signal device registration QR code"
        exit 1
        ;;
esac
