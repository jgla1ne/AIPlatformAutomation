#!/bin/bash
# Comprehensive fixes for volume mounting, proxy routing, and configuration
set -euo pipefail

echo "🔧 COMPREHENSIVE SYSTEM FIXES"
echo "==============================="

# Fix 1: Environment file issues
echo "1. FIXING .ENV FILE ISSUES..."
if [[ -f "/mnt/data/.env" ]]; then
    # Fix SIGNAL-API_PORT line
    sed -i 's/SIGNAL-API_PORT=8090/SIGNAL_API_PORT=8090/' /mnt/data/.env
    echo "✅ Fixed SIGNAL_API_PORT syntax"
    
    # Fix Grafana port consistency
    sed -i 's/GRAFANA_PORT=3001/GRAFANA_PORT=3000/' /mnt/data/.env
    echo "✅ Fixed Grafana port to match container (3000)"
    
    # Remove PROXY_TYPE completely
    sed -i '/^# PROXY_TYPE.*REMOVED/d' /mnt/data/.env
    echo "✅ Removed PROXY_TYPE comment"
fi

# Fix 2: Volume mounting prompt
echo ""
echo "2. VOLUME MOUNTING SOLUTION..."
echo "Available volumes for mounting:"
/home/jglaine/AIPlatformAutomation/scripts/volume-detector.sh

echo ""
echo "🎯 VOLUME MOUNTING COMMANDS:"
echo "# Choose one of the volumes above and run:"
echo "sudo mkfs.ext4 /dev/nvmeXn1  # Format if needed"
echo "sudo mount /dev/nvmeXn1 /mnt"
echo "echo '/dev/nvmeXn1 /mnt ext4 defaults 0 2' | sudo tee -a /etc/fstab"
echo ""

# Fix 3: Proxy routing analysis
echo "3. PROXY ROUTING ANALYSIS..."
source /mnt/data/.env

echo "Current working URLs:"
echo "- n8n: http://$DOMAIN_NAME:8080/apps ✅"
echo "- dify: http://$DOMAIN_NAME:3000/login ✅"
echo "- grafana: http://$DOMAIN_NAME:$GRAFANA_PORT (should work)"
echo ""

echo "🔍 GRAFANA ISSUE:"
echo "Container port: 3000"
echo "Env port: $GRAFANA_PORT"
echo "Expected: http://$DOMAIN_NAME:3000 OR https://$DOMAIN_NAME/grafana"
echo ""

echo "🌐 PROXY CONFIG METHOD: $PROXY_CONFIG_METHOD"
if [[ "$PROXY_CONFIG_METHOD" == "alias" ]]; then
    echo "✅ Alias method should work with direct port access"
    echo "❌ But /grafana path won't work without rewrite rules"
elif [[ "$PROXY_CONFIG_METHOD" == "direct" ]]; then
    echo "✅ Direct port forwarding should work"
    echo "❌ Domain paths need specific routing"
fi

echo ""
echo "🎯 IMMEDIATE FIXES NEEDED:"
echo "1. Mount EBS volume to /mnt"
echo "2. Re-run Script 1 with proper volume"
echo "3. Fix Grafana routing in proxy config"
echo "4. Test all service URLs"
echo ""

echo "📋 TESTING COMMANDS:"
echo "# Test current setup:"
echo "curl -I http://$DOMAIN_NAME:8080/apps"
echo "curl -I http://$DOMAIN_NAME:3000"
echo "curl -I http://$DOMAIN_NAME:$GRAFANA_PORT"
echo ""
echo "# After volume mount:"
echo "sudo ./1-setup-system.sh  # Reconfigure with proper volume"
echo "sudo ./2-deploy-services.sh  # Redeploy services"
