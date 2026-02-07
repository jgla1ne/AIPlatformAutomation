#!/bin/bash

#############################################################################
# Script 3: Configure Running Services
# Tailscale auth, GDrive setup, networking, service config
#############################################################################

set -euo pipefail

source /opt/ai-platform/.env

configure_tailscale() {
    [[ -n $TAILSCALE_AUTH_KEY ]] || return 0
    
    docker run -d --name tailscale --network host \
        --cap-add=NET_ADMIN -v tailscale_data:/var/lib/tailscale \
        tailscale/tailscale:latest tailscaled
        
    docker exec tailscale tailscale up --authkey="$TAILSCALE_AUTH_KEY" \
        --advertise-exit-node
}

setup_gdrive_rclone() {
    rclone config create gdrive drive \
        client_id="$GDRIVE_CLIENT_ID" \
        client_secret="$GDRIVE_CLIENT_SECRET" \
        token='{"access_token":"...","token_type":"Bearer","refresh_token":"'"$GDRIVE_REFRESH_TOKEN"'","expiry":"..."}'
}

create_ingestion_systemd() {
    cat > /etc/systemd/system/gdrive-sync.service << EOF
[Unit]
Description=AI Platform GDrive → AnythingLLM
After=docker.service network.target

[Service]  
ExecStart=/bin/bash -c 'rclone sync gdrive: /mnt/data/gdrive/ && docker exec anythingllm /app/ingest.sh'
User=root
EOF

    cat > /etc/systemd/system/gdrive-sync.timer << EOF
[Unit]
Description=GDrive Sync Timer

[Timer]
OnCalendar=*:0/4
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    systemctl daemon-reload
    systemctl enable --now gdrive-sync.timer
}

configure_litellm_routing() {
    cat > /opt/ai-platform/config/litellm/config.yaml << EOF
model_list:
  - model_name: llama3.1  
    litellm_params:
      model: ollama/$OLLAMA_MODEL
      api_base: http://ollama:11434
  - model_name: gpt-4o-mini
    litellm_params:
      model: openai/gpt-4o-mini
      api_key: $OPENAI_API_KEY
  - model_name: claude-3-5-sonnet
    litellm_params:
      model: anthropic/claude-3-5-sonnet-20240620
      api_key: $ANTHROPIC_API_KEY
routing_strategy: cost
min_cost_model: ollama/$OLLAMA_MODEL
EOF
    docker compose -f /opt/ai-platform/compose/docker-compose.yml restart litellm
}

main() {
    configure_tailscale
    setup_gdrive_rclone  
    create_ingestion_systemd
    configure_litellm_routing
    
    echo "${GREEN}✅ SCRIPT 3 COMPLETE - SERVICES CONFIGURED${NC}"
    echo "Next: ./4-add-service.sh (optional)"
}
