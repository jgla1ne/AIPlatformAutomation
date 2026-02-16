#!/bin/bash
# Fix proxy routing issues for proper domain access
set -euo pipefail

echo "🔧 ANALYZING PROXY ROUTING ISSUES..."

# Load environment
source /mnt/data/.env

echo "Current configuration:"
echo "DOMAIN: $DOMAIN"
echo "DOMAIN_NAME: $DOMAIN_NAME"
echo "PROXY_CONFIG_METHOD: $PROXY_CONFIG_METHOD"
echo ""

echo "🌐 ACCESS TESTING:"
echo "Working URLs:"
echo "- http://$DOMAIN_NAME:8080/apps (n8n)"
echo "- http://$DOMAIN_NAME:3000/login (dify)"
echo ""
echo "Not working URLs:"
echo "- https://$DOMAIN_NAME/grafana"
echo ""

echo "🔍 ROOT CAUSE ANALYSIS:"
echo "1. Grafana port mismatch:"
echo "   - GRAFANA_PORT=$GRAFANA_PORT (should be 3001)"
echo "   - But Grafana container likely on default 3000"
echo ""
echo "2. Proxy routing method:"
echo "   - PROXY_CONFIG_METHOD=$PROXY_CONFIG_METHOD"
echo "   - If 'alias', needs proper rewrite rules"
echo "   - If 'direct', needs port forwarding"
echo ""

echo "🎯 SOLUTIONS:"

echo "Option 1 - Fix Port Configuration:"
echo "   GRAFANA_PORT=3001  # Update .env"
echo "   Ensure proxy routes :3001 → grafana:3000"
echo ""

echo "Option 2 - Fix Proxy Routing:"
echo "   Create proper nginx/caddy config for:"
echo "   - grafana.$DOMAIN_NAME → localhost:3001"
echo "   - Direct /grafana → localhost:3000"
echo ""

echo "Option 3 - SSL Termination:"
echo "   SSL_TYPE=letsencrypt  # Enable SSL"
echo "   Configure proper HTTPS redirects"
echo ""

echo "📋 IMMEDIATE ACTIONS:"
echo "1. Check Grafana container port mapping"
echo "2. Verify proxy configuration files"
echo "3. Test port accessibility"
echo "4. Fix SSL/HTTPS routing"
