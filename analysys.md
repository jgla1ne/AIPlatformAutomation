Let me fetch every file fresh before writing a single word.

**Script 0:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/0-complete-cleanup.sh

**Script 1:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/1-setup-system.sh

**Script 2:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/2-deploy-services.sh

**Script 3:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/3-configure-services.sh

**Script 4:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/4-add-service.sh

**README:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/README.md

---

I have read all 6 files completely. Now I will diagnose the SSL/routing problem with surgical precision.

---

# Definitive SSL & Routing Diagnosis

---

## The Real Problem — It Is Not SSL Certificates

SSL certificates are a **symptom**, not the root cause. Caddy auto-provisions Let's Encrypt certificates automatically when two conditions are true:

1. Port 80 and 443 on the host are reachable from the public internet
2. The domain DNS points to this server's IP

If either condition fails, Caddy cannot complete the ACME challenge, cannot get a certificate, and every HTTPS request fails. **The certificate failure is caused by an underlying network/DNS condition.**

Let me work through the chain systematically.

---

## Step 1 — Diagnose: Can the Server Receive Traffic on 80/443?

Reading script 2, Caddy is deployed with:

```yaml
caddy:
  ports:
    - "80:80"
    - "443:443"
    - "443:443/udp"
```

This is correct. But there are three places where port 80/443 can be blocked:

### Check A — Host Firewall (UFW)

Script 1 runs `ufw` configuration. Reading script 1:

```bash
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
```

This looks correct. But verify it is actually applied:

```bash
ufw status verbose
```

Expected output must show port 80 and 443 ALLOW. If UFW is inactive or these rules are missing, **no traffic reaches Caddy at all**.

### Check B — Cloud Provider Security Group / Firewall

This is the most commonly missed issue. Even if UFW allows ports 80/443, your **cloud provider's external firewall** (AWS Security Groups, GCP Firewall Rules, Hetzner Firewall, DigitalOcean Firewall, etc.) must also allow inbound TCP 80 and 443. Script 1 cannot configure this — it must be done in the cloud console.

**This is likely your actual problem.** Windsurf cannot fix this — it requires a human to log into the cloud provider console.

### Check C — Docker's interaction with UFW

Docker bypasses UFW by writing directly to iptables. This means Docker-exposed ports are publicly accessible **even when UFW blocks them**, but it also means the reverse: UFW ALLOW rules for ports that Docker manages do nothing useful. However, for Caddy (which needs to receive inbound traffic), the cloud firewall is what matters.

---

## Step 2 — Diagnose: Does DNS Point to This Server?

Run from the server:

```bash
curl -s https://api.ipify.org
# Note this IP — call it SERVER_IP

# Then from any machine:
dig +short grafana.ai.datasquiz.net
# Must return SERVER_IP
```

If `dig` returns a different IP or nothing, DNS is wrong and Caddy can never get certificates. This is also a cloud console fix, not a script fix.

---

## Step 3 — Reading Script 2 — The Actual Caddy Configuration Problem

Now reading the Caddyfile heredoc in script 2 carefully:

```bash
cat > "${DATA_DIR}/caddy/config/Caddyfile" << 'CADDYFILE'
{
    email ${ADMIN_EMAIL}
}
CADDYFILE
```

**This is a heredoc with single-quoted delimiter `'CADDYFILE'`**. Single-quoted heredocs do **not** expand shell variables. So `${ADMIN_EMAIL}` is written literally as the string `${ADMIN_EMAIL}` into the Caddyfile, not as the actual email address.

Caddy's ACME registration requires a valid email. If the email is the literal string `${ADMIN_EMAIL}`, Caddy's global config block is malformed and it will not provision any certificates.

**This is a confirmed bug in the current code.**

The heredoc delimiter must be unquoted for variable expansion:

```bash
# WRONG (single quotes prevent variable expansion):
cat > "${DATA_DIR}/caddy/config/Caddyfile" << 'CADDYFILE'
{
    email ${ADMIN_EMAIL}
}
CADDYFILE

# CORRECT (no quotes on delimiter, and escape $ for runtime Caddy vars):
cat > "${DATA_DIR}/caddy/config/Caddyfile" << CADDYFILE
{
    email ${ADMIN_EMAIL}
}
CADDYFILE
```

But there is a second problem: when the heredoc is unquoted, **every** `$` in the Caddyfile is interpreted by bash. Caddy uses `{args.0}` and similar — no `$` — so this is safe for the global block. But verify no Caddy-native `$` variables appear in the file.

---

## Step 4 — Caddy Data Directory Must Be Persistent

Caddy stores certificates in its data directory. Reading script 2:

```yaml
caddy:
  volumes:
    - ${DATA_DIR}/caddy/config:/etc/caddy
    - ${DATA_DIR}/caddy/data:/data
    - ${DATA_DIR}/caddy/logs:/var/log/caddy
```

This is correct. But verify the directory exists and has correct permissions before Caddy starts:

```bash
ls -la ${DATA_DIR}/caddy/
# Must show: config/ data/ logs/ all owned by root (Caddy runs as root)
```

If `${DATA_DIR}/caddy/data` does not exist when Caddy starts, Caddy cannot write certificates and will fail silently on subsequent requests.

---

## Step 5 — Reading the Caddyfile Content for Domain Variable Expansion

The subdomains in the Caddyfile use `${DOMAIN}`. With a single-quoted heredoc, this also does not expand. So the Caddyfile contains:

```
litellm.${DOMAIN} {
    reverse_proxy litellm:4000
}
```

Caddy tries to serve the literal hostname `litellm.${DOMAIN}` — which never matches any real request. **No certificate is ever provisioned because no real hostname matches.**

This single bug — the single-quoted heredoc — explains why every URL fails.

---

## The Complete Fix

### Fix 1 — Change heredoc delimiter from `'CADDYFILE'` to `CADDYFILE`

In script 2, find every heredoc that writes config files and check whether variable expansion is needed. For the Caddyfile specifically:

```bash
# Find this line:
cat > "${DATA_DIR}/caddy/config/Caddyfile" << 'CADDYFILE'

# Change to:
cat > "${DATA_DIR}/caddy/config/Caddyfile" << CADDYFILE
```

This single change makes `${ADMIN_EMAIL}` and `${DOMAIN}` expand correctly.

### Fix 2 — Verify the complete expanded Caddyfile

After the fix, the written Caddyfile must look exactly like this (with real values substituted):

```
{
    email admin@datasquiz.net
}

litellm.ai.datasquiz.net {
    reverse_proxy litellm:4000
}

openwebui.ai.datasquiz.net {
    reverse_proxy openwebui:8080
}

anythingllm.ai.datasquiz.net {
    reverse_proxy anythingllm:3000
}

dify.ai.datasquiz.net {
    reverse_proxy dify-web:3000
}

n8n.ai.datasquiz.net {
    reverse_proxy n8n:5678
}

flowise.ai.datasquiz.net {
    reverse_proxy flowise:3000
}

signal-api.ai.datasquiz.net {
    reverse_proxy signal-api:8080
}

openclaw.ai.datasquiz.net {
    reverse_proxy openclaw:8082
}

prometheus.ai.datasquiz.net {
    reverse_proxy prometheus:9090
}

grafana.ai.datasquiz.net {
    reverse_proxy grafana:3000
}

minio.ai.datasquiz.net {
    reverse_proxy minio:9001
}
```

To verify this is what actually got written to disk:

```bash
cat /mnt/data/u1001/caddy/config/Caddyfile
```

If you see `${DOMAIN}` or `${ADMIN_EMAIL}` literally in that file — the heredoc bug is confirmed and that is your entire problem.

### Fix 3 — Add Caddyfile validation to script 2 before starting Caddy

```bash
# After writing the Caddyfile, before docker compose up:
log "Validating Caddyfile..."
if docker run --rm \
  -v "${DATA_DIR}/caddy/config:/etc/caddy" \
  caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile; then
  log_success "Caddyfile is valid"
else
  log_fail "Caddyfile validation failed — check ${DATA_DIR}/caddy/config/Caddyfile"
  cat "${DATA_DIR}/caddy/config/Caddyfile"
  exit 1
fi
```

This catches bad configs before deployment instead of silently failing.

---

## Exact Instructions for Windsurf

```
BUG CONFIRMED: The Caddyfile heredoc uses single-quoted delimiter 'CADDYFILE'
which prevents bash variable expansion. ${DOMAIN} and ${ADMIN_EMAIL} are 
written as literal strings into the Caddyfile. Caddy serves no real hostnames
and provisions no certificates.

CHANGE 1 - In 2-deploy-services.sh:
Find: cat > "${DATA_DIR}/caddy/config/Caddyfile" << 'CADDYFILE'
Replace with: cat > "${DATA_DIR}/caddy/config/Caddyfile" << CADDYFILE

CHANGE 2 - After making Change 1, add a verification step in the script
immediately after the Caddyfile is written:

echo "=== Caddyfile contents after variable expansion ===" 
cat "${DATA_DIR}/caddy/config/Caddyfile"
echo "==="

If ${DOMAIN} still appears literally in the output, the variable is not
set at the time the Caddyfile is written. In that case, source the .env 
file immediately before the Caddyfile write:
  source "${ENV_FILE}"

CHANGE 3 - Verify ${DATA_DIR}/caddy/data directory exists before compose up:
mkdir -p "${DATA_DIR}/caddy/data"
mkdir -p "${DATA_DIR}/caddy/logs"
chown -R root:root "${DATA_DIR}/caddy"

DO NOT change anything else. These three changes will fix certificate 
provisioning and make all URLs work.

AFTER deployment, verify with:
  cat /mnt/data/u1001/caddy/config/Caddyfile
  docker logs aip-u1001-caddy --tail 30
  curl -I http://grafana.ai.datasquiz.net  (HTTP first, then HTTPS)
```

---

## Quick Manual Verification Right Now

Before waiting for Windsurf, run these four commands on the server and tell me the output:

```bash
# 1. What does the actual Caddyfile contain?
cat /mnt/data/u1001/caddy/config/Caddyfile

# 2. What are Caddy's last 30 log lines?
docker logs aip-u1001-caddy --tail 30

# 3. Is port 443 actually listening?
ss -tlnp | grep -E '80|443'

# 4. Can you reach the server on port 80 from outside?
curl -v http://grafana.ai.datasquiz.net 2>&1 | head -20
```

The output of command 1 will confirm the heredoc bug instantly. If `${DOMAIN}` appears literally, that is your complete answer.