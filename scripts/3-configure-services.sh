#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Script 3: Mission Control - Service Management Interface
# =============================================================================
# PURPOSE: Primary management interface for AI platform services
# USAGE:   sudo bash scripts/3-configure-services.sh <TENANT_ID> <action> [service]
# ACTIONS: --start, --stop, --status, --manage
# =============================================================================

# --- Tenant ID and .env loading ---
TENANT_ID="$1"
if [[ -z "$TENANT_ID" ]]; then
    echo "ERROR: TENANT_ID is required as first argument"
    echo "Usage: sudo bash scripts/3-configure-services.sh <TENANT_ID> <action> [service]"
    exit 1
fi

TENANT_DIR="/mnt/data/${TENANT_ID}"
ENV_FILE="${TENANT_DIR}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
    echo "ERROR: Environment file not found for tenant '${TENANT_ID}' at ${ENV_FILE}"
    exit 1
fi

# source the .env file to get all variables
set -a; source "${ENV_FILE}"; set +a
cd "${TENANT_DIR}" # CRITICAL: Run all docker commands from the tenant dir

# --- Helper Functions ---
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${1}"
}

ok() {
    echo -e "✅ ${1}"
}

warn() {
    echo -e "⚠️ ${1}"
}

fail() {
    echo -e "❌ ${1}"
    exit 1
}

# --- ACTION FUNCTIONS ---

start_service() {
    log INFO "Attempting to start service: $1"
    if docker compose up -d "$1"; then
        ok "Service $1 started successfully."
    else
        fail "Failed to start service $1. Check logs: docker compose logs $1"
    fi
}

stop_service() {
    log INFO "Attempting to stop service: $1"
    if docker compose stop "$1"; then
        ok "Service $1 stopped successfully."
    else
        fail "Failed to stop service $1."
    fi
}

show_status() {
    echo "=========================================="
    echo "     AI Platform Status Dashboard"
    echo "=========================================="
    echo ""
    echo "SERVICE                  | STATUS"
    echo "-------------------------|----------"
    docker compose ps --format "table {{.Name}}\t{{.State}}"
    echo ""
    echo "=========================================="
    echo "     Real-time Resource Usage"
    echo "=========================================="
    docker stats --no-stream
    echo ""
}

manage_interactive() {
    while true; do
        clear
        show_status
        echo ""
        echo "Available commands:"
        echo "  start <service>  - Start a service"
        echo "  stop <service>   - Stop a service"
        echo "  exit             - Exit management interface"
        echo ""
        read -p "Enter command: " cmd arg
        
        case "$cmd" in
            start)
                [ -n "$arg" ] && start_service "$arg" || warn "Please specify a service to start."
                ;;
            stop)
                [ -n "$arg" ] && stop_service "$arg" || warn "Please specify a service to stop."
                ;;
            exit)
                break
                ;;
            *)
                warn "Invalid command. Use 'start <service>', 'stop <service>', or 'exit'."
                ;;
        esac
        sleep 2 # Brief pause before re-displaying status
    done
    ok "Exiting interactive management."
}

# --- Main script logic ---
main() {
    ACTION=${2:---status} # Default to --status if no action is provided
    SERVICE=${3:-}

    case "$ACTION" in
        --start)
            [ -z "$SERVICE" ] && fail "Usage: $0 $TENANT_ID --start <service_name>"
            start_service "$SERVICE"
            ;;
        --stop)
            [ -z "$SERVICE" ] && fail "Usage: $0 $TENANT_ID --stop <service_name>"
            stop_service "$SERVICE"
            ;;
        --status)
            show_status
            ;;
        --manage)
            manage_interactive
            ;;
        *)
            fail "Unknown action: $ACTION. Use --start, --stop, --status, or --manage."
            ;;
    esac
}

main "$@"
