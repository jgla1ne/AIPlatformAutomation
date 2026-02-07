#!/bin/bash

#############################################################################
# Script 4: Add New Docker Service to Stack
# Interactive new service deployment + compose update
#############################################################################

COMPOSE_FILE="/opt/ai-platform/compose/docker-compose.yml"
ENV_FILE="/opt/ai-platform/.env"

add_new_service() {
    echo "🆕 ADD NEW SERVICE TO AI PLATFORM"
    read -p "Docker image name: " IMAGE_NAME
    read -p "Service name: " SERVICE_NAME
    read -p "Internal port: " INTERNAL_PORT
    read -p "External port (Enter=auto): " EXTERNAL_PORT
    
    # Add to compose
    local service_yaml=$(cat << EOF
  ${SERVICE_NAME}:
    image: ${IMAGE_NAME}
    container_name: ${SERVICE_NAME}
    restart: unless-stopped
    networks:
      - ai-platform
    ports:
      - "${EXTERNAL_PORT:-auto}:${INTERNAL_PORT}"
    volumes:
      - ${SERVICE_NAME}_data:/data
EOF
)
    
    echo "$service_yaml" >> "$COMPOSE_FILE"
    
    # Deploy
    cd /opt/ai-platform/compose
    docker compose up -d "$SERVICE_NAME"
    
    echo "✅ $SERVICE_NAME added & running!"
}

main() {
    add_new_service
}

