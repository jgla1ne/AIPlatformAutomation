#!/bin/bash

# Script to test all promised URLs from script 1
# Tests internal Docker network, external HTTPS, and local access URLs

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test function
test_url() {
    local url="$1"
    local description="$2"
    
    echo -n "Testing $description: "
    echo -n "$url "
    
    if curl -s -f -m 10 "$url" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ SUCCESS${NC}"
        return 0
    else
        echo -e "${RED}❌ FAILED${NC}"
        echo "   Error: $(curl -s -S -m 10 "$url" 2>&1 | head -1)"
        return 1
    fi
}

echo "==============================================="
echo "🔍 TESTING PROMISED URLS FROM SCRIPT 1"
echo "==============================================="
echo ""

# Internal Docker network tests (requires Docker network access)
echo "🐳 INTERNAL DOCKER NETWORK TESTS"
echo "================================"
test_url "http://n8n:5678" "n8n internal"
test_url "http://ollama:11434/api/tags" "Ollama API internal"
test_url "http://qdrant:6333" "Qdrant internal"
test_url "http://litellm:4000" "LiteLLM internal"
echo ""

# External HTTPS URL tests
echo "🌐 EXTERNAL HTTPS URL TESTS"
echo "================================"
test_url "https://n8n.ai.datasquiz.net" "n8n"
test_url "https://flowise.ai.datasquiz.net" "Flowise"
test_url "https://openwebui.ai.datasquiz.net" "Open WebUI"
test_url "https://anythingllm.ai.datasquiz.net" "AnythingLLM"
test_url "https://litellm.ai.datasquiz.net" "LiteLLM"
test_url "https://grafana.ai.datasquiz.net" "Grafana"
test_url "https://auth.ai.datasquiz.net" "Authentik"
echo ""

# Local access URL tests
echo "🏠 LOCAL ACCESS URL TESTS"
echo "================================"
test_url "http://localhost:8080" "Open WebUI local"
test_url "http://localhost:11434/api/tags" "Ollama API local"
test_url "http://localhost:6333" "Qdrant local"
echo ""

echo "==============================================="
echo "✅ URL TESTING COMPLETE"
echo "==============================================="
