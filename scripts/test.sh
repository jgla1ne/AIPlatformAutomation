#!/bin/bash
# diagnostic.sh - Run this NOW
cd /AIPlatformAutomation/scripts/

echo "🔍 DIAGNOSTIC v74.8.0"
echo "======================"

echo "📁 PROJECT STATE:"
ls -la /AIPlatformAutomation/ | grep -E "(stack|logs|data|backups|.env)" || echo "✅ NO remnants"

echo "🐳 DOCKER STATE:"
docker ps -a | wc -l && docker volume ls | wc -l && docker network ls | wc -l

echo "📦 PACKAGES:"
dpkg -l | grep -E "(docker|rclone|tailscale)" || echo "✅ CLEAN"

echo "🔥 FILES Script1 checks:"
[[ -f ".env" ]] && echo "❌ .env exists" || echo "✅ .env gone"
[[ -d "stack" ]] && echo "❌ stack/ exists" || echo "✅ stack/ gone"
