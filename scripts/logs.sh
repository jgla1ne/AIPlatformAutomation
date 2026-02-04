#!/bin/bash
SERVICE=$1
if [ -z "$SERVICE" ]; then
    echo "Usage: $0 <service-name>"
    echo "Available services:"
    docker ps --format "{{.Names}}" | grep -E "ai-|dify-"
    exit 1
fi
docker logs -f "$SERVICE"
