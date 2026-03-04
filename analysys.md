Windsurf Instructions: Fix & Deploy Script 2
Context Summary
Script 1 generates a docker-compose.yml with condition: service_healthy on depends_on. Docker Compose silently exits 0 but starts zero containers because ollama's healthcheck has a start_period: 60s — open-webui never satisfies the dependency and the whole graph stalls. Script 2 attempts a Python patch but the YAML round-trip via PyYAML destroys the version key ordering and can corrupt anchors, and the patch runs after compose config validation — meaning the bad file is already confirmed "valid" before fixing. The fix must be pre-deployment, surgical, and verified.

Phase 1 — Rewrite docker-compose.yml Generation in Script 1
File: scripts/1-setup-system.sh
Action: Replace the docker-compose.yml heredoc with a clean version that has no condition: service_healthy and uses simple depends_on lists only. This is the root cause fix.
Tell Windsurf:

In scripts/1-setup-system.sh, find the section starting with:
cat > $PLATFORM_DIR/docker-compose.yml << 'EOF'
Replace the entire heredoc block (everything between << 'EOF' and the closing EOF) with the following:

version: '3.8'

networks:
  ai-network:
    driver: bridge

volumes:
  ollama_data:
  open_webui_data:
  n8n_data:
  qdrant_data:
  npm_data:
  npm_letsencrypt:

services:
  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    restart: unless-stopped
    networks:
      - ai-network
    ports:
      - "6333:6333"
      - "6334:6334"
    volumes:
      - qdrant_data:/qdrant/storage

  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    networks:
      - ai-network
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: unless-stopped
    networks:
      - ai-network
    ports:
      - "3000:8080"
    volumes:
      - open_webui_data:/app/backend/data
    environment:
      - OLLAMA_BASE_URL=${OLLAMA_BASE_URL}
      - WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}
    depends_on:
      - ollama

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    networks:
      - ai-network
    ports:
      - "5678:5678"
    volumes:
      - n8n_data:/home/node/.n8n
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
    depends_on:
      - qdrant

  nginx-proxy-manager:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager
    restart: unless-stopped
    networks:
      - ai-network
    ports:
      - "80:80"
      - "443:443"
      - "81:81"
    volumes:
      - npm_data:/data
      - npm_letsencrypt:/etc/letsencrypt
Key changes made:

✅ Removed ALL healthcheck blocks (eliminates the service_healthy stall)
✅ Removed ALL condition: service_healthy from depends_on
✅ Changed depends_on to simple lists only
✅ Reordered services: qdrant and ollama first (no upstream deps)
✅ Added Qdrant gRPC port 6334


Phase 2 — Rewrite scripts/2-deploy-services.sh Completely
File: scripts/2-deploy-services.sh
Tell Windsurf:

Replace the entire contents of scripts/2-deploy-services.sh with the following:

#!/bin/bash
# Script 2: Deploy Services
# Deploys all Docker services using Docker Compose

# DO NOT use set -e — we want controlled error handling per step

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING:${NC} $1"; }
error(){ echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $1"; }
info() { echo -e "${BLUE}[$(date +'%H:%M:%S')] INFO:${NC} $1"; }

PLATFORM_DIR="/opt/ai-platform"
COMPOSE_FILE="$PLATFORM_DIR/docker-compose.yml"

# ─── Root check ───────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (sudo bash 2-deploy-services.sh)"
    exit 1
fi

# ─── Prerequisites ────────────────────────────────────────────────────────────
log "Checking prerequisites..."

[[ ! -f "$COMPOSE_FILE" ]] && { error "docker-compose.yml not found at $COMPOSE_FILE — run script 1 first."; exit 1; }
[[ ! -f "$PLATFORM_DIR/.env" ]] && { error ".env not found at $PLATFORM_DIR/.env — run script 1 first."; exit 1; }

# ─── Docker daemon ────────────────────────────────────────────────────────────
log "Ensuring Docker daemon is running..."
systemctl start docker
sleep 2
if ! docker info &>/dev/null; then
    error "Docker daemon is not responding. Check: systemctl status docker"
    exit 1
fi
log "Docker daemon OK"

# ─── Detect compose command ───────────────────────────────────────────────────
if docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    error "No Docker Compose found. Re-run script 1 to install it."
    exit 1
fi
log "Using: $COMPOSE_CMD"

# ─── Sanitise compose file (belt-and-braces) ─────────────────────────────────
# Use sed to strip any remaining service_healthy conditions.
# This protects against the file being regenerated with old script 1.
log "Sanitising docker-compose.yml (removing service_healthy conditions)..."
sed -i 's/condition: service_healthy/condition: service_started/g' "$COMPOSE_FILE"
sed -i 's/condition: service_completed_successfully/condition: service_started/g' "$COMPOSE_FILE"
log "Sanitisation complete"

# ─── Validate compose config ──────────────────────────────────────────────────
log "Validating Docker Compose configuration..."
cd "$PLATFORM_DIR"
if ! $COMPOSE_CMD config --quiet 2>&1; then
    error "docker-compose.yml is invalid. Output:"
    $COMPOSE_CMD config 2>&1
    exit 1
fi
log "Configuration valid"

# ─── Create required directories ─────────────────────────────────────────────
log "Creating required bind-mount directories..."
mkdir -p /opt/ai-platform/nginx/data
mkdir -p /opt/ai-platform/nginx/letsencrypt
mkdir -p /opt/ai-platform/nginx/logs
mkdir -p /opt/ai-platform/ollama
mkdir -p /opt/ai-platform/open-webui
mkdir -p /opt/ai-platform/n8n
mkdir -p /opt/ai-platform/qdrant
chown -R 1000:1000 /opt/ai-platform/n8n 2>/dev/null || true
chmod -R 755 /opt/ai-platform
log "Directories ready"

# ─── Pull images ──────────────────────────────────────────────────────────────
log "Pulling Docker images (this may take several minutes on first run)..."
$COMPOSE_CMD pull 2>&1
PULL_EXIT=$?
if [[ $PULL_EXIT -ne 0 ]]; then
    warn "Some images may not have pulled cleanly (exit $PULL_EXIT) — attempting deployment anyway"
fi

# ─── Tear down any existing stack ─────────────────────────────────────────────
log "Stopping any existing containers from this stack..."
$COMPOSE_CMD down --remove-orphans 2>/dev/null || true
sleep 2

# ─── Deploy stack ─────────────────────────────────────────────────────────────
log "Starting all services..."
$COMPOSE_CMD up -d --remove-orphans 2>&1
UP_EXIT=$?

if [[ $UP_EXIT -ne 0 ]]; then
    error "docker compose up exited with code $UP_EXIT"
    error "Compose logs:"
    $COMPOSE_CMD logs --tail=60 2>&1
    exit 1
fi

# ─── Wait for containers to initialise ───────────────────────────────────────
log "Waiting 20 seconds for containers to initialise..."
sleep 20

# ─── Verify each service individually ────────────────────────────────────────
log "Verifying individual service status..."

SERVICES=("ollama" "open-webui" "n8n" "qdrant" "nginx-proxy-manager")
FAILED=()

for SVC in "${SERVICES[@]}"; do
    STATE=$(docker inspect --format '{{.State.Status}}' "$SVC" 2>/dev/null || echo "missing")
    if [[ "$STATE" == "running" ]]; then
        log "  ✅  $SVC — running"
    else
        warn "  ❌  $SVC — state: $STATE"
        FAILED+=("$SVC")
    fi
done

# ─── Retry failed services ────────────────────────────────────────────────────
if [[ ${#FAILED[@]} -gt 0 ]]; then
    warn "${#FAILED[@]} service(s) not running: ${FAILED[*]}"
    warn "Attempting individual restart of failed services..."
    for SVC in "${FAILED[@]}"; do
        log "Restarting $SVC..."
        $COMPOSE_CMD restart "$SVC" 2>&1 || true
    done
    sleep 15

    STILL_FAILED=()
    for SVC in "${FAILED[@]}"; do
        STATE=$(docker inspect --format '{{.State.Status}}' "$SVC" 2>/dev/null || echo "missing")
        if [[ "$STATE" == "running" ]]; then
            log "  ✅  $SVC — now running after restart"
        else
            error "  ❌  $SVC — still not running (state: $STATE)"
            STILL_FAILED+=("$SVC")
        fi
    done

    if [[ ${#STILL_FAILED[@]} -gt 0 ]]; then
        error "The following services failed to start: ${STILL_FAILED[*]}"
        error "Dumping logs for failed services..."
        for SVC in "${STILL_FAILED[@]}"; do
            echo ""
            echo "===== LOGS: $SVC ====="
            $COMPOSE_CMD logs --tail=40 "$SVC" 2>&1
        done
        exit 1
    fi
fi

# ─── Port connectivity spot-checks ───────────────────────────────────────────
log "Checking port accessibility..."
PORTS=("11434:Ollama" "3000:Open-WebUI" "5678:n8n" "6333:Qdrant" "81:Nginx-Proxy-Manager")
for ENTRY in "${PORTS[@]}"; do
    PORT="${ENTRY%%:*}"
    NAME="${ENTRY##*:}"
    if ss -tlnp | grep -q ":$PORT "; then
        log "  ✅  Port $PORT ($NAME) is listening"
    else
        warn "  ⚠️   Port $PORT ($NAME) not yet listening (service may still be starting)"
    fi
done

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "  AI Platform — Deployment Complete"
echo "=========================================="
$COMPOSE_CMD ps
echo ""
SERVER_IP=$(hostname -I | awk '{print $1}')
echo "Access URLs:"
echo "  Open WebUI:          http://${SERVER_IP}:3000"
echo "  n8n:                 http://${SERVER_IP}:5678"
echo "  Qdrant:              http://${SERVER_IP}:6333"
echo "  Nginx Proxy Manager: http://${SERVER_IP}:81"
echo ""
echo "  NPM default login:   admin@example.com / changeme"
echo "=========================================="
echo ""
log "Run script 3 to configure services: sudo bash 3-configure-services.sh"

Phase 3 — Execution Order on the Server
Tell Windsurf to execute these commands in sequence on the target machine:
# Step 1: Clean slate
sudo bash /path/to/scripts/0-complete-cleanup.sh

# Step 2: Re-run setup with the fixed script 1
sudo bash /path/to/scripts/1-setup-system.sh

# Step 3: Verify the generated compose file has NO service_healthy
grep -n "service_healthy" /opt/ai-platform/docker-compose.yml
# Expected output: (nothing — zero matches)

# Step 4: Deploy
sudo bash /path/to/scripts/2-deploy-services.sh

# Step 5: Confirm all 5 containers are running
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

Phase 4 — If Script 2 Still Fails (Diagnostic Escalation)
Tell Windsurf: If docker ps shows 0 containers after script 2, run these diagnostics and report back:
# Check compose sees the file correctly
docker compose -f /opt/ai-platform/docker-compose.yml config 2>&1 | head -40

# Try starting just qdrant in foreground to see raw error
docker compose -f /opt/ai-platform/docker-compose.yml up qdrant 2>&1

# Check available disk space (images need ~10GB+)
df -h /var/lib/docker

# Check if images were actually pulled
docker images | grep -E "ollama|webui|n8n|qdrant|nginx-proxy"

# Check system memory
free -h

Summary of All Changes
Copy table


File
Change
Reason



1-setup-system.sh
Remove all healthcheck: blocks from compose heredoc
Eliminates service_healthy stall condition


1-setup-system.sh
Change depends_on to simple lists
Removes blocking dependency conditions


2-deploy-services.sh
Add sed sanitiser before validation
Catches any residual service_healthy conditions


2-deploy-services.sh
Remove PyYAML Python patch block
PyYAML round-trip corrupts YAML; sed is safer


2-deploy-services.sh
Add per-container docker inspect verification
Detects silent failures immediately


2-deploy-services.sh
Add per-service restart retry loop
Recovers transient startup failures


2-deploy-services.sh
Add port listening check via ss
Confirms services are actually bound


2-deploy-services.sh
Remove set -e
Allows controlled per-step error handling