#!/usr/bin/env bash
#############################################################################
# Script 3 — Configure Services
# Finalizes deployed services: LiteLLM routing, OpenClaw, Tailscale, Signal, GDrive
# Performs integration checks, updates configuration files, logs everything
#############################################################################

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$ROOT_DIR/config"
DATA_DIR="/mnt/data"
LOG_DIR="$DATA_DIR/logs"
LOG_FILE="$LOG_DIR/configure.log"
SUMMARY_FILE="$CONFIG_DIR/service_deploy_summary.txt"
OPENCLAW_CONF="$CONFIG_DIR/openclaw_config.json"
ENV_FILE="$CONFIG_DIR/.env"
CREDENTIALS_FILE="$CONFIG_DIR/credentials.txt"

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
touch "$SUMMARY_FILE"

log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
fail() { log "ERROR: $*"; exit 1; }
pause() { read -rp "Press ENTER to continue..."; }

log "=== STEP 3 — Configure Services ==="

# --------------------------------------------------
# STEP 0 — Load Environment
# --------------------------------------------------
[[ -f "$ENV_FILE" ]] || fail ".env missing! Run Script 1 first."
set -o allexport
source "$ENV_FILE"
set +o allexport
log "Environment loaded from $ENV_FILE"

# --------------------------------------------------
# STEP 1 — LiteLLM routing configuration
# --------------------------------------------------
if [[ "${SERVICE_LiteLLM:-false}" == true ]]; then
    echo "Select LiteLLM routing strategy:"
    PS3="Select routing by number: "
    options=("Round-Robin" "Weighted" "Custom")
    select opt in "${options[@]}"; do
        case $REPLY in
            1|2|3) LITELLM_ROUTING="$opt"; break ;;
            *) echo "Invalid selection" ;;
        esac
    done
    log "LiteLLM routing strategy set to: $LITELLM_ROUTING"
    echo "LITELLM_ROUTING=$LITELLM_ROUTING" >> "$ENV_FILE"
fi

# --------------------------------------------------
# STEP 2 — OpenClaw configuration
# --------------------------------------------------
if [[ "${SERVICE_OpenClaw_UI:-false}" == true ]]; then
    # VectorDB selection
    echo "Select VectorDB for OpenClaw:"
    PS3="Select DB by number: "
    db_options=("Qdrant" "Chroma")
    select db_opt in "${db_options[@]}"; do
        case $REPLY in
            1|2) VECTOR_DB="$db_opt"; break ;;
            *) echo "Invalid selection" ;;
        esac
    done
    log "OpenClaw VectorDB: $VECTOR_DB"

    # Generate credentials
    OPENCLAW_USER="openclaw_user"
    OPENCLAW_PASS=$(openssl rand -base64 12)
    echo "$OPENCLAW_USER:$OPENCLAW_PASS" > "$CREDENTIALS_FILE"
    log "OpenClaw credentials generated"

    # Write config JSON
    cat > "$OPENCLAW_CONF" <<EOF
{
    "vector_db": "$VECTOR_DB",
    "user": "$OPENCLAW_USER",
    "password": "$OPENCLAW_PASS",
    "services": {
        "LiteLLM": "$LITELLM_ROUTING"
    }
}
EOF
    log "OpenClaw configuration written to $OPENCLAW_CONF"
fi

# --------------------------------------------------
# STEP 3 — Tailscale configuration
# --------------------------------------------------
if [[ "${SERVICE_Tailscale:-false}" == true ]]; then
    read -rp "Enter Tailscale auth key: " TAILSCALE_AUTH_KEY
    read -rp "Enter Tailscale API key: " TAILSCALE_API_KEY
    echo "TAILSCALE_AUTH_KEY=$TAILSCALE_AUTH_KEY" >> "$ENV_FILE"
    echo "TAILSCALE_API_KEY=$TAILSCALE_API_KEY" >> "$ENV_FILE"
    log "Tailscale auth & API keys recorded"
fi

# --------------------------------------------------
# STEP 4 — Signal configuration
# --------------------------------------------------
if [[ "${SERVICE_Signal:-false}" == true ]]; then
    read -rp "Enter Signal user phone number (with country code): " SIGNAL_NUMBER
    echo "SIGNAL_NUMBER=$SIGNAL_NUMBER" >> "$ENV_FILE"
    log "Signal user number recorded"
fi

# --------------------------------------------------
# STEP 5 — GDrive configuration
# --------------------------------------------------
if [[ "${SERVICE_GDrive:-false}" == true ]]; then
    echo "GDrive configuration options:"
    echo "1) Project ID + Secret"
    echo "2) OAuth URL"
    PS3="Select configuration type: "
    select g_opt in "ProjectID+Secret" "OAuthURL"; do
        case $REPLY in
            1)
                read -rp "Enter GDrive Project ID: " GDRIVE_PROJECT_ID
                read -rp "Enter GDrive Secret: " GDRIVE_SECRET
                echo "GDRIVE_PROJECT_ID=$GDRIVE_PROJECT_ID" >> "$ENV_FILE"
                echo "GDRIVE_SECRET=$GDRIVE_SECRET" >> "$ENV_FILE"
                break
                ;;
            2)
                read -rp "Enter OAuth URL: " GDRIVE_OAUTH_URL
                echo "GDRIVE_OAUTH_URL=$GDRIVE_OAUTH_URL" >> "$ENV_FILE"
                break
                ;;
            *)
                echo "Invalid option"
                ;;
        esac
    done
    log "GDrive configuration saved"
fi

# --------------------------------------------------
# STEP 6 — Optional service checks
# --------------------------------------------------
OPTIONAL_SERVICES=("Grafana" "Prometheus" "ELK" "Portainer")
for svc in "${OPTIONAL_SERVICES[@]}"; do
    if [[ "${!SERVICE_$svc:-false}" == true ]]; then
        PORT="${!PORT_$svc:-0}"
        log "Optional service $svc configured on port $PORT"
        echo "$svc -> http://$(hostname -I | awk '{print $1}'):$PORT/" >> "$SUMMARY_FILE"
    fi
done

# --------------------------------------------------
# STEP 7 — Post-configuration summary
# --------------------------------------------------
log "=== Service Configuration Summary ==="
cat "$SUMMARY_FILE"
log "All selected services configured."
pause
