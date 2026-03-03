AI Platform — Deployment Runsheet
Version: Post-fix (Scripts 1/2/3 validated)
Target: Fresh Ubuntu 22.04/24.04 VPS with /mnt/data mounted
Time estimate: ~25–40 min (depending on model pull sizes)

PRE-FLIGHT CHECKLIST
Before touching the server, confirm:
Copy table


Item
Required
Notes



VPS accessible via SSH
✅
Root or sudo user


/mnt/data mounted & writable
✅
df -h /mnt/data


DNS A records pointing to VPS IP
✅
All subdomains you plan to use


Ports 80 + 443 open in firewall
✅
ufw allow 80/tcp && ufw allow 443/tcp


Groq / Gemini API keys ready
Optional
Have them on hand


Tailscale auth key
Optional
Only if deploying Tailscale


GDrive service account JSON
Optional
Only if enabling GDrive sync



PHASE 1 — Get the scripts onto the server
# SSH into the server
ssh root@<YOUR_SERVER_IP>

# Install git if not present
apt-get update -qq && apt-get install -y git curl

# Clone the repo
git clone https://github.com/jgla1ne/AIPlatformAutomation.git ~/ai-platform-automation
cd /ai-platform-automation

# Make all scripts executable
chmod +x scripts/*.sh

PHASE 2 — Script 1: Environment Setup
sudo bash scripts/1-setup-environment.sh
What the wizard asks — recommended answers for datasquiz standard stack:
Copy table


Prompt
Recommended Answer
Notes



Tenant name
datasquiz



Tenant ID
u1001
Must match u#### format


Base domain
ai.datasquiz.net
Your actual domain


ACME email
admin@datasquiz.net
For Let's Encrypt TLS


Timezone
UTC or Australia/Sydney



Base data directory
/mnt/data/datasquiz
Default — press Enter


Proxy type
caddy



PostgreSQL
y



Redis
y



Ollama
y



Open WebUI
y



LiteLLM
y



AnythingLLM
n
Enable if needed


Flowise
n
Enable if needed


n8n
y



Qdrant
y



Authentik
n
Enable for SSO


Grafana + Prometheus
n
Enable for monitoring


Dify
n
Enable if needed


Tailscale
n
y if VPN tunnel required


Signal API
n



OpenClaw
n
y + image if deploying


DB username
aiplatform



DB password
(auto-generated — press Enter)



DB name
aiplatform



Ollama models
llama3.2:3b,nomic-embed-text
Add more comma-separated


GPU for Ollama
n
y if NVIDIA GPU present


Groq API key
(paste or blank)



Gemini API key
(paste or blank)



OpenAI API key
(paste or blank)



Open WebUI subdomain
chat
→ chat.ai.datasquiz.net


LiteLLM subdomain
litellm



n8n subdomain
n8n



Qdrant subdomain
qdrant



Qdrant collection
datasquiz-docs



Qdrant vector size
768
Match your embedding model


Expose Qdrant UI
n
y only if needed


✅ Verify Script 1 output:
# Confirm .env was written
cat /mnt/data/datasquiz/.env

# Spot-check critical values
grep -E "COMPOSE_PROJECT_NAME|DOMAIN|DEPLOY_" /mnt/data/datasquiz/.env

PHASE 3 — Script 2: Deploy Services
sudo bash scripts/2-deploy-services.sh
What Script 2 does (in order):

Sources .env
Creates all data directories (including tailscale/, caddy/, Dify only if enabled)
Writes stub Caddyfile (so Caddy has a valid bind mount at start)
Generates docker-compose.yml with only enabled services
Writes networks: block once (no duplicate declaration)
Pulls all images: docker compose pull
Starts all containers: docker compose up -d
Waits for Caddy to be healthy then reloads if needed
Pulls Ollama models (llama3.2:3b + nomic-embed-text by default)
Writes LiteLLM config.yaml and restarts LiteLLM
Waits for Qdrant then creates collection
Writes Prometheus config (if monitoring enabled)
Runs health checks
Prints access summary

✅ Verify Script 2 output:
# Validate compose file (must exit 0)
docker compose -f /mnt/data/datasquiz/docker-compose.yml config --quiet
echo "Exit: $?"

# Check all containers are running
docker compose -f /mnt/data/datasquiz/docker-compose.yml ps

# Confirm single networks: key
grep -c "^networks:" /mnt/data/datasquiz/docker-compose.yml
# Expected: 1

# Confirm single services: key  
grep -c "^services:" /mnt/data/datasquiz/docker-compose.yml
# Expected: 1

# Check Ollama is responding
curl -s http://localhost:11434/api/tags | jq '.models[].name'

# Check Qdrant
curl -s http://localhost:6333/collections | jq .

PHASE 4 — Script 3: Configure Services (Caddy + post-config)
sudo bash scripts/3-configure-services.sh
What Script 3 does:

Builds the full production Caddyfile with all enabled service reverse-proxy blocks
Reloads Caddy (zero-downtime — no container restart)
Re-runs Ollama model pulls (idempotent — skips already-present)
Re-writes and restarts LiteLLM config (idempotent)
Creates Qdrant collection if not already present
Configures Prometheus scrape targets (if monitoring)
Sets up rclone GDrive sync + systemd timer (if enabled)
Runs full health check suite
Prints final access summary with all URLs

✅ Verify Script 3 output:
# Test TLS is working (replace with your domain)
curl -sI https://chat.ai.datasquiz.net | head -5
# Expected: HTTP/2 200

curl -sI https://litellm.ai.datasquiz.net | head -5
curl -sI https://n8n.ai.datasquiz.net | head -5

# Verify Caddy has valid certs
docker exec datasquiz-caddy caddy validate --config /etc/caddy/Caddyfile

# Check Caddy logs for any cert errors
docker logs aip-u1001-caddy --tail 50 2>&1 | grep -E "error|certificate|tls"

# LiteLLM health
curl -s http://localhost:4000/health | jq .

# Test LiteLLM model list (use your master key from .env)
LITELLM_KEY=$(grep LITELLM_MASTER_KEY /mnt/data/datasquiz/.env | cut -d= -f2)
curl -s -H "Authorization: Bearer ${LITELLM_KEY}" http://localhost:4000/models | jq '.data[].id'

PHASE 5 — Post-Deployment Verification
# Full container status
docker compose -f /mnt/data/datasquiz/docker-compose.yml ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

# Resource usage
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# Check no containers are restarting
docker ps --filter "status=restarting"
# Expected: empty

# Postgres connectivity
docker exec aip-u1001-postgres pg_isready -U aiplatform -d aiplatform

# Redis connectivity  
docker exec aip-u1001-redis redis-cli ping
# Expected: PONG

# n8n is up
curl -sI http://localhost:5678 | head -3

PHASE 6 — First-Use Setup (Manual, browser)
Copy table


Service
URL
First-Run Action



Open WebUI
https://chat.ai.datasquiz.net
Create admin account (first signup = admin)


n8n
https://n8n.ai.datasquiz.net
Create owner account


LiteLLM
https://litellm.ai.datasquiz.net
UI uses master key from .env


Qdrant UI
http://<IP>:6333/dashboard
No auth by default



TROUBLESHOOTING REFERENCE
Container won't start
docker logs aip-u1001-<service> --tail 100
Caddy cert not issuing
# Confirm DNS resolves to this server
dig +short chat.ai.datasquiz.net
# Must match server IP

# Check port 80 is open (ACME HTTP-01 challenge)
curl -v http://chat.ai.datasquiz.net/.well-known/acme-challenge/test
LiteLLM DB connection error
# Confirm postgres is healthy
docker inspect aip-u1001-postgres | jq '.[0].State.Health.Status'
# Must be: "healthy"
Ollama model pull failed
# Re-pull manually
docker exec aip-u1001-ollama ollama pull llama3.2:3b
docker exec aip-u1001-ollama ollama pull nomic-embed-text
Qdrant collection missing
# Re-create manually
curl -X PUT http://localhost:6333/collections/datasquiz-docs \
  -H "Content-Type: application/json" \
  -d '{"vectors": {"size": 768, "distance": "Cosine"}}'
Re-run any script safely (all scripts are idempotent)
# Script 2 regenerates compose and re-deploys (existing volumes preserved)
sudo bash scripts/2-deploy-services.sh

# Script 3 reconfigures Caddy and services without downtime
sudo bash scripts/3-configure-services.sh

KEY FILE LOCATIONS
Copy table


File
Path



Environment config
/mnt/data/datasquiz/.env


Docker Compose file
/mnt/data/datasquiz/docker-compose.yml


Caddyfile
/mnt/data/datasquiz/caddy/Caddyfile


LiteLLM config
/mnt/data/datasquiz/litellm/config.yaml


Prometheus config
/mnt/data/datasquiz/prometheus/prometheus.yml


Ollama models
/mnt/data/datasquiz/ollama/


n8n data
/mnt/data/datasquiz/n8n/


GDrive sync logs
/mnt/data/datasquiz/logs/rclone-datasquiz.log



COMPLETE COMMAND SEQUENCE (copy-paste)
# Phase 1
apt-get update -qq && apt-get install -y git curl
git clone https://github.com/jgla1ne/AIPlatformAutomation.git /~/ai-platform-automation
cd /ai-platform-automation && chmod +x scripts/*.sh

# Phase 2
sudo bash scripts/1-setup-environment.sh

# Phase 3
sudo bash scripts/2-deploy-services.sh

# Phase 4
sudo bash scripts/3-configure-services.sh

# Phase 5 — verify
docker compose -f /mnt/data/datasquiz/docker-compose.yml ps
curl -sI https://chat.ai.datasquiz.net | head -3

The runsheet is complete. All scripts have been re-read in their fixed state — no further blockers identified. Ready to execute.