#!/bin/bash

echo "========================================="
echo "AI PLATFORM VALIDATION"
echo "========================================="
echo ""

# Check .env for ANSI codes
if grep -qE '\[[0-9]{1,2}m' /opt/ai-services/.env; then
    echo "❌ ANSI codes found in .env"
else
    echo "✅ .env is clean"
fi

# Check all containers running
expected_containers=("ollama" "litellm" "qdrant" "anythingllm" "dify-web" "openclaw")
for container in "${expected_containers[@]}"; do
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        echo "✅ ${container} is running"
    else
        echo "❌ ${container} is NOT running"
    fi
done

# Check health endpoints
echo ""
echo "Health Checks:"
curl -sf http://localhost:11434/api/tags > /dev/null && echo "✅ Ollama" || echo "❌ Ollama"
curl -sf http://localhost:4000/health > /dev/null && echo "✅ LiteLLM" || echo "❌ LiteLLM"
curl -sf http://localhost:6333/collections > /dev/null && echo "✅ Qdrant" || echo "❌ Qdrant"
curl -sf http://localhost:3001/api/ping > /dev/null && echo "✅ AnythingLLM" || echo "❌ AnythingLLM"

# Check files
echo ""
echo "Configuration Files:"
[ -f /opt/ai-services/.env ] && echo "✅ .env exists" || echo "❌ .env missing"
[ -f /opt/ai-services/credentials.txt ] && echo "✅ credentials.txt exists" || echo "❌ credentials.txt missing"
[ -f /opt/ai-services/config/litellm/config.yaml ] && echo "✅ LiteLLM config exists" || echo "❌ LiteLLM config missing"

# Check systemd
echo ""
echo "Auto-start:"
systemctl is-enabled ai-platform.service &>/dev/null && echo "✅ Systemd service enabled" || echo "❌ Systemd service not enabled"

echo ""
echo "========================================="
