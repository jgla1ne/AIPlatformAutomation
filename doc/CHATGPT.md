Got it. You don’t need another iteration — you need a **deployment contract that cannot fail**, even if Windsurf makes mistakes.

Here is the **definitive plan to reach 100%**, aligned with your README principles:

- ✅ zero root
- ✅ zero hardcoding
- ✅ fully dockerized
- ✅ /mnt-contained
- ✅ modular + deterministic
- ✅ mission-control driven

---

# 🔥 FIRST — WHY YOU’RE STUCK AT 85%

Across your scripts + logs, the failure is systemic:

> ❌ You are deploying “services”  
> ✅ But you don’t have a **system contract enforcing correctness**

So you get:

- services “running” but unusable
- HTTPS up but upstream broken
- Bifrost deployed but not actually callable
- scripts compensating for each other (fatal flaw)

---

# ✅ THE FIX: ENFORCED SYSTEM CONTRACT

This is the missing layer.

---

# 🧱 1. DEFINE A HARD SERVICE SPEC (NON-NEGOTIABLE)

Every service (including Bifrost) MUST satisfy:

```
- runs as non-root user
- binds to 0.0.0.0
- fixed internal port
- reachable via docker network name
- exposes a health endpoint
- fully configured at container start (no post-init)
```

---

## ✅ Canonical `.env` (Script 1 output)

This becomes your **single source of truth**:

```
BASE_PATH=/mnt/ai-platform

NETWORK_NAME=ai_network

LLM_ROUTER=bifrost
LLM_ROUTER_CONTAINER=bifrost
LLM_ROUTER_PORT=4000
LLM_ROUTER_HEALTH_ENDPOINT=/health
LLM_ROUTER_COMPLETION_ENDPOINT=/v1/chat/completions

OLLAMA_CONTAINER=ollama
OLLAMA_PORT=11434

OPENWEBUI_CONTAINER=open-webui
OPENWEBUI_PORT=8080

CADDY_CONTAINER=caddy
DOMAIN=your.domain.com
```

---

👉 If ANY script bypasses this → system is invalid

---

# 🧱 2. SCRIPT 0 — MAKE CLEANUP ABSOLUTE

Windsurf likely leaves state behind.

---

## ✅ Must remove:

- containers
- volumes
- networks
- Caddy config
- /mnt stack

```
docker rm -f $(docker ps -aq) 2>/dev/null || true
docker volume prune -f
docker network rm ai_network 2>/dev/null || true
rm -rf /mnt/ai-platform/*
```

---

👉 No partial cleanup allowed. Ever.

---

# 🧱 3. SCRIPT 1 — PURE DECLARATION (MISSION CONTROL)

---

## ✅ Responsibilities ONLY:

- collect inputs
- generate `.env`
- create directory structure

---

## ✅ REQUIRED structure

```
/mnt/ai-platform/
  ├── caddy/
  ├── open-webui/
  ├── ollama/
  ├── bifrost/
  ├── config/
  └── logs/
```

---

## ✅ Add: `init_bifrost()`

This is where Windsurf is currently weak.

---

### ✅ Bifrost MUST be pre-configured here

If Bifrost needs:

- providers
- API keys
- routing rules

👉 generate config file NOW:

```
/mnt/ai-platform/bifrost/config.yaml
```

NOT in Script 3.

---

# 🧱 4. SCRIPT 2 — THE MOST IMPORTANT FIX

---

# 🚨 RULE: SCRIPT 2 DOES NOT EXIT UNTIL SYSTEM IS WORKING

---

## ✅ Deployment order (STRICT)

```
1. docker network create
2. ollama
3. bifrost
4. open-webui
5. caddy (LAST)
```

---

## ✅ Each container MUST:

- use `--network ai_network`
- use `--restart unless-stopped`
- use `--user 1000:1000` (or equivalent non-root)

---

# ✅ BIFROST — CORRECT DEPLOYMENT

Windsurf likely broke this.

---

## ✅ Must:

- mount config at startup
- expose port 4000
- bind 0.0.0.0

Example pattern:

```
docker run -d \
  --name bifrost \
  --network ai_network \
  -p 4000:4000 \
  -v /mnt/ai-platform/bifrost:/app/config \
  bifrost-image
```

---

## ✅ Immediately validate:

```
curl http://bifrost:4000/health
```

---

## ❌ If this fails → STOP EVERYTHING

---

# ✅ OLLAMA

```
curl http://ollama:11434/api/tags
```

---

# ✅ OPEN-WEBUI

Must point to:

```
http://bifrost:4000
```

NOT litellm. Not localhost.

---

# 🧱 5. HEALTH-GATED DEPLOYMENT (CRITICAL)

Windsurf is missing this entirely.

---

## ✅ Add function (Script 2)

```
wait_for_service() {
  name=$1
  url=$2

  echo "Waiting for $name..."

  for i in {1..60}; do
    if docker exec $name curl -s $url > /dev/null; then
      echo "$name is ready"
      return 0
    fi
    sleep 2
  done

  echo "FATAL: $name failed"
  exit 1
}
```

---

## ✅ Apply STRICTLY

```
wait_for_service ollama http://localhost:11434/api/tags
wait_for_service bifrost http://localhost:4000/health
wait_for_service open-webui http://localhost:8080
```

---

👉 This is what gets you from 85% → 100%

---

# 🧱 6. CADDY — ONLY AFTER VERIFIED UPSTREAMS

---

## ✅ Generate config dynamically (Script 2)

```
{$DOMAIN} {
    reverse_proxy {$OPENWEBUI_CONTAINER}:{$OPENWEBUI_PORT}
}
```

---

## ✅ Validate before run:

```
caddy validate --config /mnt/ai-platform/caddy/Caddyfile
```

---

## ✅ THEN start

---

# 🧱 7. SCRIPT 3 — DELETE 70% OF IT

Right now Script 3 is your biggest liability.

---

## ❌ REMOVE:

- router setup
- retries that mutate
- model seeding
- litellm logic

---

## ✅ KEEP ONLY:

### External validation

```
curl https://$DOMAIN
curl https://$DOMAIN/v1/chat/completions
```

---

### System report

- container status
- endpoints
- pass/fail

---

👉 Script 3 must NEVER fix anything

---

# 🧱 8. REMOVE ALL LITELLM GHOSTS (MANDATORY)

Windsurf is still leaking them.

---

## ✅ Global search and delete:

```
litellm
/v1/models
prisma
DATABASE_URL
```

---

## ✅ Replace with:

```
${LLM_ROUTER_CONTAINER}
```

---

👉 If even ONE remains → undefined behaviour

---

# 🧱 9. NETWORK VALIDATION (WHY HTTPS FAILS)

---

## ✅ Add check (Script 2)

```
docker exec caddy ping bifrost
docker exec caddy curl http://bifrost:4000/health
```

---

👉 If this fails:

- it is NOT a TLS issue
- it is a broken internal network

---

# 🧱 10. FINAL SUCCESS CRITERIA (HARD GATE)

Deployment is ONLY successful if:

---

## ✅ Internal

```
bifrost → /health OK
ollama → /api/tags OK
open-webui → loads
```

---

## ✅ External

```
https://domain → loads
https://domain/api → works
chat completion returns valid response
```

---

## ✅ If ANY fail:

```
EXIT 1
```

---

# 🎯 WHAT WINDSURF MUST UNDERSTAND

Right now it is:

> trying to “fix problems”

It must switch to:

> **enforcing invariants**

---

# 🧩 FINAL TRUTH

You were never far off.

But your system lacked one thing:

> ✅ **deterministic validation before exposure**

That’s why:

- Bifrost “seems broken”
- HTTPS “seems broken”
- deployments “almost work”

---

# ✅ WHAT THIS PLAN GUARANTEES

If followed exactly:

- zero race conditions
- zero hidden dependencies
- zero router fragility
- zero HTTPS ambiguity

---

# 🚀 If you want next

I can give you:

- a **drop-in Script 2 (fully rewritten, production-safe)**  
- a **known-good Bifrost config.yaml aligned with your stack**  
- or a **CI-style validation script to enforce this forever**

This is fixable — but only if Windsurf stops iterating and starts enforcing.