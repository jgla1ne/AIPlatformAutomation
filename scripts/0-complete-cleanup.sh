#!/bin/bash
set -euo pipefail

echo "╔════════════════════════════════════════════════════════════╗"
echo "║          ☢️  NUCLEAR CLEANUP - LAST WARNING  ☢️            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "This will PERMANENTLY DESTROY:"
echo "  • All Docker containers, images, volumes, networks"
echo "  • All services: n8n, flowise, litellm, langfuse, postgresql"
echo "  • All data in /mnt/data/"
echo "  • All application files in /root/"
echo "  • All systemd service files"
echo "  • Network configurations"
echo ""
echo "The system will REBOOT after cleanup."
echo ""
read -p "Type 'DESTROY' to continue: " confirm

if [ "$confirm" != "DESTROY" ]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Starting nuclear cleanup in 5 seconds... Press Ctrl+C to abort!"
sleep 5

# Stop all services immediately
echo "⏹  Stopping all services..."
systemctl stop n8n flowise litellm langfuse nginx postgresql docker 2>/dev/null || true
killall -9 node npm npx python3 nginx postgres docker dockerd containerd 2>/dev/null || true

# Docker complete removal
echo "🐳 Removing Docker..."
if command -v docker &> /dev/null; then
    docker stop $(docker ps -aq) 2>/dev/null || true
    docker rm -f $(docker ps -aq) 2>/dev/null || true
    docker rmi -f $(docker images -q) 2>/dev/null || true
    docker volume rm -f $(docker volume ls -q) 2>/dev/null || true
    docker network rm $(docker network ls -q) 2>/dev/null || true
    docker system prune -af --volumes 2>/dev/null || true
fi

# Purge Docker packages
apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
apt-get autoremove -y 2>/dev/null || true
rm -rf /var/lib/docker
rm -rf /var/lib/containerd
rm -rf /etc/docker

# Remove all systemd services
echo "🗑️  Removing systemd services..."
for service in n8n flowise litellm langfuse; do
    systemctl stop $service 2>/dev/null || true
    systemctl disable $service 2>/dev/null || true
    rm -f /etc/systemd/system/${service}.service
done
systemctl daemon-reload
systemctl reset-failed

# PostgreSQL complete removal
echo "🗄️  Removing PostgreSQL..."
systemctl stop postgresql 2>/dev/null || true
apt-get purge -y postgresql* 2>/dev/null || true
rm -rf /etc/postgresql
rm -rf /var/lib/postgresql
rm -rf /var/log/postgresql

# Nginx removal
echo "🌐 Removing Nginx..."
systemctl stop nginx 2>/dev/null || true
apt-get purge -y nginx* 2>/dev/null || true
rm -rf /etc/nginx
rm -rf /var/log/nginx
rm -rf /var/www

# Remove all application directories
echo "📁 Removing application files..."
rm -rf /root/n8n
rm -rf /root/flowise
rm -rf /root/litellm
rm -rf /root/langfuse
rm -rf /root/.n8n
rm -rf /root/.npm
rm -rf /root/.cache

# Clean data directory (preserve structure)
echo "💾 Cleaning data directory..."
if [ -d "/mnt/data" ]; then
    rm -rf /mnt/data/postgresql
    rm -rf /mnt/data/n8n
    rm -rf /mnt/data/flowise
    rm -rf /mnt/data/nginx
    rm -rf /mnt/data/logs
    rm -rf /mnt/data/backups
    rm -rf /mnt/data/uploads
fi

# Clean Node.js global packages
echo "📦 Cleaning Node.js packages..."
if command -v npm &> /dev/null; then
    npm cache clean --force 2>/dev/null || true
fi

# Clean Python packages
echo "🐍 Cleaning Python packages..."
if command -v pip3 &> /dev/null; then
    pip3 freeze | xargs pip3 uninstall -y 2>/dev/null || true
    rm -rf /root/.cache/pip
fi

# Remove network configurations
echo "🔌 Resetting network configurations..."
rm -f /etc/nginx/sites-enabled/*
rm -f /etc/nginx/sites-available/ai-platform

# Clean logs
echo "📝 Cleaning logs..."
rm -rf /var/log/n8n*
rm -rf /var/log/flowise*
rm -rf /var/log/litellm*
rm -rf /var/log/langfuse*
journalctl --vacuum-time=1s 2>/dev/null || true

# Clean temp files
echo "🧹 Cleaning temporary files..."
rm -rf /tmp/n8n*
rm -rf /tmp/flowise*
rm -rf /tmp/npm*
rm -rf /tmp/pip*

# Final cleanup
apt-get autoremove -y
apt-get autoclean -y

echo ""
echo "✅ Nuclear cleanup complete!"
echo ""
echo "System will REBOOT in 10 seconds..."
echo "Press Ctrl+C to cancel reboot"
sleep 10

echo "🔄 Rebooting now..."
reboot

