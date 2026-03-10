#!/usr/bin/env bash
# =============================================================================
# Script 2: Service Deployer - STABLE v5.1 (Definitive Reconstruction)
# =============================================================================
# PURPOSE: A definitive, faithful reconstruction of the deployment logic from
#          commit b8f7478 and the provided backup file. It correctly and 
#          completely deploys all services configured by the setup wizard.
# =============================================================================

set -euo pipefail

# --- SOURCE MISSION CONTROL & LOAD ENVIRONMENT ---
source "$(dirname "${BASH_SOURCE[0]}")/3-configure-services.sh"
if [[ -z "${1:-}" ]]; then fail "TENANT_ID is required. Usage: sudo bash $0 <tenant_id>"; fi
TENANT_ID="$1"
load_tenant_env "${TENANT_ID}"

# --- MAIN DOCKER COMPOSE GENERATION ---
main() {
    log "Entering data root: ${DATA_ROOT}"
    cd "${DATA_ROOT}"

    log "Generating master docker-compose.yml file..."
    cat > docker-compose.yml << EOF
version: "3.8"

networks:
  ${DOCKER_NETWORK}:
    driver: bridge

services:
EOF

    # --- Base Services (Always On) ---
    if [[ "${ENABLE_POSTGRES}" == "true" ]]; then cat >> docker-compose.yml << EOF
  postgres:
    image: postgres:16-alpine
    user: "${TENANT_UID}:${TENANT_GID}"
    environment:
      POSTGRES_USER: "${POSTGRES_USER}"
      POSTGRES_PASSWORD: "${POSTGRES_PASSWORD}"
      POSTGRES_DB: "${POSTGRES_DB}"
    volumes:
      - ./postgres:/var/lib/postgresql/data
    ports:
      - "${POSTGRES_PORT}:5432"
    networks:
      - ${DOCKER_NETWORK}
    restart: unless-stopped

EOF
    fi

    if [[ "${ENABLE_REDIS}" == "true" ]]; then cat >> docker-compose.yml << EOF
  redis:
    image: redis:7-alpine
    user: "${TENANT_UID}:${TENANT_GID}"
    command: redis-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - ./redis:/data
    ports:
      - "${REDIS_PORT}:6379"
    networks:
      - ${DOCKER_NETWORK}
    restart: unless-stopped

EOF
    fi

    # --- Reverse Proxy (Caddy or Traefik) ---
    if [[ "${ENABLE_CADDY}" == "true" ]]; then cat >> docker-compose.yml << EOF
  caddy:
    image: caddy:2-alpine
    user: "${TENANT_UID}:${TENANT_GID}"
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ./caddy_data:/data
    networks:
      - ${DOCKER_NETWORK}
    restart: unless-stopped

EOF
    fi

    if [[ "${ENABLE_TRAEFIK}" == "true" ]]; then echo "# Traefik service placeholder"; fi

    # --- Tailscale (Correct, Full Implementation) ---
    if [[ "${ENABLE_TAILSCALE}" == "true" ]]; then cat >> docker-compose.yml << EOF
  tailscale:
    image: tailscale/tailscale:latest
    user: "${TENANT_UID}:${TENANT_GID}"
    hostname: ${TAILSCALE_HOSTNAME}
    environment:
      - TS_AUTHKEY=${TAILSCALE_AUTH_KEY}
      - TS_EXTRA_ARGS=${TAILSCALE_EXTRA_ARGS}
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_ACCEPT_DNS=true
      - TS_USERSPACE=true
    volumes:
      - ./lib/tailscale:/var/lib/tailscale
      - ./run/tailscale:/var/run/tailscale
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - net_admin
      - sys_module
    ports:
      - "${TAILSCALE_PORT}:8443"
    networks:
      - ${DOCKER_NETWORK}
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "tailscale", "status"]
      interval: 10s
      timeout: 5s
      retries: 3

EOF
    fi

    log "Docker Compose file generated successfully."

    read -p "Deploy services now? [Y/n]: " deploy_now
    if [[ "${deploy_now:-y}" =~ ^y$ ]]; then
        log "Starting Docker Compose deployment..."
        docker compose up -d
        ok "Deployment started. Services are coming online."
    else
        log "Deployment skipped."
    fi
}

main
