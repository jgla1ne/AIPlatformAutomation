#!/bin/bash

# Simple test for Script 2 functionality
set -euo pipefail

# Paths
readonly DATA_ROOT="/mnt/data"
readonly METADATA_DIR="$DATA_ROOT/metadata"
readonly SERVICES_FILE="$METADATA_DIR/selected_services.json"

echo "=== TEST: Script 2 Components ==="

echo "1. Testing JSON loading..."
if [[ -f "/mnt/data/metadata/selected_services.json" ]]; then
    SELECTED_SERVICES=($(jq -r '.services[].key' "/mnt/data/metadata/selected_services.json"))
    echo "✅ Loaded ${#SELECTED_SERVICES[@]} services"
    echo "Services: ${SELECTED_SERVICES[*]}"
else
    echo "❌ Selected services file not found"
    exit 1
fi

echo "2. Testing environment loading..."
if [[ -f "/mnt/data/.env" ]]; then
    echo "✅ Environment file found"
    echo "POSTGRES_USER: $(grep "^POSTGRES_USER=" /mnt/data/.env | cut -d= -f2)"
    echo "REDIS_USER: $(grep "^REDIS_USER=" /mnt/data/.env | cut -d= -f2)"
else
    echo "❌ Environment file not found"
    exit 1
fi

echo "3. Testing compose directory..."
if [[ -d "/mnt/data/compose" ]]; then
    echo "✅ Compose directory exists"
    echo "Templates: $(ls /mnt/data/compose/)"
else
    echo "❌ Compose directory not found"
    exit 1
fi

echo "4. Testing Docker..."
if command -v docker >/dev/null 2>&1; then
    echo "✅ Docker available"
    echo "Docker version: $(docker --version)"
else
    echo "❌ Docker not available"
    exit 1
fi

echo "=== TEST COMPLETE ==="
echo "All components ready for deployment!"
