Let me fetch the current state of everything.

**WINDSURF.md:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/doc/WINDSURF.md

**Scripts:**
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/1-setup-system.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/2-deploy-services.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/3-configure-services.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/0-complete-cleanup.sh

**README:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/README.md

---

After reviewing WINDSURF.md and the current scripts, here is my targeted guidance:

---

```markdown
# CLAUDE.md — Deployment Issue Guidance
**Date:** 2025-07
**Status:** POST-IMPLEMENTATION TRIAGE
**Input:** WINDSURF.md deployment status report

---

## 🔴 ISSUE 1: Ollama health check failing before model pull

**Symptom (from WINDSURF.md):** Script 3 proceeds before Ollama is ready,
model pull fails or times out.

**Root cause:** The health check is testing the wrong endpoint, or the retry
loop exits too early.

**Exact fix in Script 3:**
```bash
# Replace any existing Ollama health check with this:
echo "Waiting for Ollama..."
MAX_ATTEMPTS=30
ATTEMPT=0
until curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; do
  ATTEMPT=$((ATTEMPT + 1))
  if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
    echo "ERROR: Ollama did not become ready after ${MAX_ATTEMPTS} attempts. Aborting."
    exit 1
  fi
  echo "  Attempt ${ATTEMPT}/${MAX_ATTEMPTS} — waiting 10s..."
  sleep 10
done
echo "✅ Ollama is ready."

# Then pull with retry:
OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.2}"
for i in 1 2 3; do
  docker exec ollama ollama pull "${OLLAMA_MODEL}" && break
  echo "Pull attempt $i failed, retrying in 30s..."
  sleep 30
done

# Verify pull succeeded:
docker exec ollama ollama list | grep "${OLLAMA_MODEL}" || {
  echo "ERROR: Model ${OLLAMA_MODEL} not found after pull attempts."
  exit 1
}
```

**Key points:**
- Use `/api/tags` not `/` — the root endpoint returns 200 before the model
  server is actually ready to serve
- 30 × 10s = 5 minutes max wait — sufficient for slow hosts
- Hard exit if model not confirmed present — do not silently continue

---

## 🔴 ISSUE 2: N8N credential injection failing

**Symptom:** Script 3 N8N API calls return 401 or connection refused.

**Root cause diagnosis — check in order:**

### Step A: Is N8N actually up?
```bash
curl -v http://localhost:5678/healthz
```
Expected: `{"status":"ok"}` with HTTP 200.
If connection refused → N8N container not running. Check:
```bash
docker compose ps n8n
docker compose logs n8n --tail=50
```

### Step B: Are credentials correct?
N8N Basic Auth uses the values set at container start. Verify `.env` has:
```
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=<value>
N8N_BASIC_AUTH_PASSWORD=<value>
```
And that the container was started AFTER these were set (not before).
```bash
docker compose exec n8n env | grep N8N_BASIC
```

### Step C: Idempotent credential POST
```bash
# Source .env
source /opt/ai-platform/.env

N8N_BASE="http://localhost:5678"
AUTH="-u ${N8N_BASIC_AUTH_USER}:${N8N_BASIC_AUTH_PASSWORD}"

# Check if credential already exists before creating
EXISTING=$(curl -sf ${AUTH} "${N8N_BASE}/api/v1/credentials" | \
  jq -r '.data[] | select(.name=="Ollama") | .id' 2>/dev/null)

if [ -n "${EXISTING}" ]; then
  echo "✅ Ollama credential already exists (id: ${EXISTING}), skipping."
else
  curl -sf ${AUTH} \
    -H "Content-Type: application/json" \
    -X POST "${N8N_BASE}/api/v1/credentials" \
    -d "{
      \"name\": \"Ollama\",
      \"type\": \"ollamaApi\",
      \"data\": {\"baseUrl\": \"http://ollama:11434\"}
    }" || { echo "ERROR: Failed to create Ollama credential"; exit 1; }
  echo "✅ Ollama credential created."
fi
```

**Critical:** The URL inside the credential data MUST be `http://ollama:11434`
(Docker internal hostname), NOT `http://localhost:11434`.

---

## 🔴 ISSUE 3: Inter-service connectivity (if N8N cannot reach Ollama)

**Symptom:** N8N workflows fail with "connection refused" to Ollama even though
both containers are running.

**Diagnosis:**
```bash
# Test from inside N8N container:
docker compose exec n8n curl -sf http://ollama:11434/api/tags
```

If this fails → network configuration issue.

**Fix:** Ensure both services are on the same Docker network in
`docker-compose.yml`:
```yaml
services:
  n8n:
    networks:
      - ai-platform
  ollama:
    networks:
      - ai-platform

networks:
  ai-platform:
    driver: bridge
```

Both must declare the SAME named network. If they are on default networks
separately, they cannot resolve each other by service name.

---

## 🟡 ISSUE 4: Script 3 partial failure on re-run

**Symptom:** Re-running Script 3 creates duplicate N8N credentials or
re-pulls Ollama model unnecessarily.

**Fix:** All three idempotency guards must be in place:

```bash
# Guard 1 — Ollama model
docker exec ollama ollama list | grep "${OLLAMA_MODEL}" && \
  echo "✅ Model already present, skipping pull." || \
  docker exec ollama ollama pull "${OLLAMA_MODEL}"

# Guard 2 — N8N credentials (see Issue 2 above — GET before POST)

# Guard 3 — Flowise chatflows
FLOW_EXISTS=$(curl -sf http://localhost:3001/api/v1/chatflows | \
  jq -r '.[] | select(.name=="Default") | .id' 2>/dev/null)
[ -n "${FLOW_EXISTS}" ] && echo "✅ Flowise chatflow exists, skipping." || \
  <import command here>
```

---

## 📋 IMMEDIATE DIAGNOSTIC SEQUENCE

Run these commands on the host RIGHT NOW and share the output in WINDSURF.md:

```bash
# 1. Container status
docker compose ps

# 2. Recent logs for failing services
docker compose logs ollama --tail=30
docker compose logs n8n --tail=30
docker compose logs flowise --tail=30

# 3. Network topology
docker network ls
docker network inspect <ai-platform-network-name>

# 4. Environment sanity check
cat /opt/ai-platform/.env | grep -v PASSWORD | grep -v SECRET

# 5. Quick connectivity matrix
curl -s http://localhost:11434/api/tags | head -c 100
curl -s http://localhost:5678/healthz
curl -s http://localhost:3001/api/v1/chatflows | head -c 100
```

Paste the output of these 5 commands into WINDSURF.md. The specific error
messages will pinpoint which of the above fixes to apply first.

---

## 🔒 DO NOT DO WHILE TROUBLESHOOTING

| Prohibited action | Why |
|------------------|-----|
| `docker compose down` | Destroys volumes, loses all N8N/Flowise data |
| Changing ports in docker-compose.yml | Breaks .env references everywhere |
| Adding new services to resolve connectivity | Symptom masking |
| Re-running Script 1 or 2 while Script 3 is failing | Unnecessary, Script 3 is the only broken layer |

---

## ✅ DEFINITION OF SUCCESS

All of the following must return expected results before closing this iteration:

| Check | Command | Expected |
|-------|---------|----------|
| Ollama running | `curl http://localhost:11434/api/tags` | JSON with models list |
| Ollama model present | `docker exec ollama ollama list` | `llama3.2` listed |
| N8N healthy | `curl http://localhost:5678/healthz` | `{"status":"ok"}` |
| N8N credential exists | `curl -u user:pass http://localhost:5678/api/v1/credentials` | Ollama entry present |
| N8N→Ollama internal | `docker exec n8n_container curl http://ollama:11434/api/tags` | JSON response |
| Flowise running | `curl http://localhost:3001/api/v1/chatflows` | JSON array |

Only once all 6 pass should WINDSURF.md be updated to "DEPLOYMENT COMPLETE".
```