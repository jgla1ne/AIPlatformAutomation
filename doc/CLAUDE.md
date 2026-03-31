Let me fetch everything current.

**README:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/README.md

**WINDSURF.md:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/doc/WINDSURF.md

**Script 1:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/1-setup-system.sh

**Script 2:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/2-deploy-services.sh

**Script 3:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/3-configure-services.sh

---

After reading Script 1 carefully, here is the precise diagnosis:

---

```markdown
# CLAUDE.md — Script 1 Interactive Input Failure: Root Cause & Definitive Fix
**Date:** 2025-07
**Status:** BLOCKING — Script 1 hangs, deployment cannot proceed

---

## 🔴 THE CORE PROBLEM: WHY WINDSURF CANNOT SEE IT

Windsurf executes scripts in a **non-interactive, piped subprocess** — there is
no TTY attached. The `read` builtin in bash behaves differently depending on
whether stdin is a terminal:

| Execution context | `read -p "prompt"` behaviour |
|-------------------|------------------------------|
| Real terminal (TTY) | Shows prompt, waits for keypress |
| Piped / subprocess | **Silently blocks forever** — no prompt shown, no timeout |
| SSH without `-t` flag | Same as above — hangs |

Windsurf sees the script as "running" because it IS running — it's just blocked
on `read` waiting for stdin that will never come. This is why Windsurf thinks
the script is valid: from its perspective, no error has occurred.

---

## 🔎 EXACT LINES CAUSING THE HANG

The hang occurs at the FIRST `read` call in Script 1. Every subsequent `read`
will hang identically. The pattern to search for:

```bash
read -p "..."         # NO timeout — hangs forever in non-TTY
read -rp "..."        # Same problem
read -r VARNAME       # Same problem if stdin is not a terminal
```

---

## ✅ DEFINITIVE FIX STRATEGY: TWO-MODE SCRIPT

Script 1 must support BOTH execution modes without changing how a human runs it:

### Mode A — Interactive (human at terminal): unchanged UX
### Mode B — Non-interactive (Windsurf / CI / SSH pipe): uses defaults from args or env

**Implementation pattern — apply to EVERY `read` call:**

```bash
# At the top of Script 1, add this function ONCE:
prompt_input() {
  local prompt="$1"
  local default="$2"
  local varname="$3"

  if [ -t 0 ]; then
    # stdin IS a terminal — interactive mode
    read -rp "${prompt} [${default}]: " value
    value="${value:-${default}}"
  else
    # stdin is NOT a terminal — non-interactive mode
    echo "${prompt}: using default '${default}'"
    value="${default}"
  fi

  # Allow environment variable override in both modes:
  # e.g. TENANT_NAME=myco bash script1.sh
  local envval
  envval=$(eval echo "\${${varname}}")
  if [ -n "${envval}" ]; then
    value="${envval}"
    echo "${prompt}: using env override '${value}'"
  fi

  eval "${varname}=\"${value}\""
}
```

**Then replace every `read` call:**
```bash
# BEFORE:
read -p "Enter tenant name: " TENANT_NAME

# AFTER:
prompt_input "Enter tenant name" "datasquiz" "TENANT_NAME"
```

---

## 📋 ALL `read` CALLS IN SCRIPT 1 — REQUIRED DEFAULTS

Windsurf must apply the `prompt_input` function to each of these, with the
defaults listed. These defaults align with README north star:

| Prompt | Variable | Default |
|--------|----------|---------|
| Tenant name | `TENANT_NAME` | `datasquiz` |
| Base directory | `BASE_DIR` | `/mnt/datasquiz` |
| Domain | `DOMAIN` | `datasquiz.local` |
| Deploy Ollama | `DEPLOY_OLLAMA` | `true` |
| Ollama model | `OLLAMA_MODEL` | `llama3.2` |
| Deploy OpenWebUI | `DEPLOY_OPENWEBUI` | `true` |
| Deploy N8N | `DEPLOY_N8N` | `true` |
| Deploy Flowise | `DEPLOY_FLOWISE` | `true` |
| Deploy LiteLLM | `DEPLOY_LITELLM` | `true` |
| Deploy Qdrant | `DEPLOY_QDRANT` | `true` |
| Postgres password | `POSTGRES_PASSWORD` | `$(openssl rand -hex 16)` |
| N8N encryption key | `N8N_ENCRYPTION_KEY` | `$(openssl rand -hex 16)` |
| WebUI secret key | `WEBUI_SECRET_KEY` | `$(openssl rand -hex 32)` |

**For generated secrets:** generate ONCE at script start, store in variable,
use as the default. Do NOT regenerate on each call or the values will differ
between the prompt and the written config.

```bash
# At TOP of Script 1, before any prompts:
_DEFAULT_POSTGRES_PASS="$(openssl rand -hex 16)"
_DEFAULT_N8N_KEY="$(openssl rand -hex 16)"
_DEFAULT_WEBUI_KEY="$(openssl rand -hex 32)"

# Then:
prompt_input "Postgres password" "${_DEFAULT_POSTGRES_PASS}" "POSTGRES_PASSWORD"
```

---

## 🔧 SECONDARY FIX: NON-INTERACTIVE EXECUTION METHOD FOR WINDSURF

Even with the above fix, Windsurf should invoke Script 1 this way to pass all
values via environment, bypassing all prompts entirely:

```bash
TENANT_NAME=datasquiz \
BASE_DIR=/mnt/datasquiz \
DOMAIN=datasquiz.local \
DEPLOY_OLLAMA=true \
DEPLOY_OPENWEBUI=true \
DEPLOY_N8N=true \
DEPLOY_FLOWISE=true \
DEPLOY_LITELLM=true \
DEPLOY_QDRANT=true \
OLLAMA_MODEL=llama3.2 \
sudo -E bash scripts/1-setup-system.sh
```

The `-E` flag preserves environment variables through sudo. This is the
**canonical non-interactive invocation** Windsurf must use.

---

## 🔁 COMPLETE EXECUTION SEQUENCE AFTER FIX

### Step 0: Clean state
```bash
sudo bash scripts/0-complete-cleanup.sh datasquiz
docker ps -a                          # must return empty
ls /mnt/datasquiz 2>/dev/null         # must return nothing or not exist
```

### Step 1: Non-interactive invocation
```bash
TENANT_NAME=datasquiz \
BASE_DIR=/mnt/datasquiz \
DOMAIN=datasquiz.local \
DEPLOY_OLLAMA=true \
DEPLOY_OPENWEBUI=true \
DEPLOY_N8N=true \
DEPLOY_FLOWISE=true \
DEPLOY_LITELLM=true \
DEPLOY_QDRANT=true \
OLLAMA_MODEL=llama3.2 \
sudo -E bash scripts/1-setup-system.sh

# Verify before proceeding:
test -f /mnt/datasquiz/platform.conf && echo "✅ platform.conf OK" || echo "❌ MISSING"
ls -la /mnt/datasquiz/ollama/         # must show uid 1000
```

### Step 2: Deploy services
```bash
sudo bash scripts/2-deploy-services.sh
sleep 60
docker compose -p datasquiz ps        # all must show "Up"
```

### Step 3: Configure services
```bash
sudo bash scripts/3-configure-services.sh
```

---

## ⚠️ NOTE TO WINDSURF ON WHY IT COULDN'T DETECT THIS

The script passes shell syntax validation (`bash -n script.sh`) because `read`
is syntactically valid. Static analysis tools will not flag it. The hang only
manifests at **runtime in a non-TTY context**. The test for this is:

```bash
# This will reproduce the hang immediately:
echo "" | bash scripts/1-setup-system.sh

# This is how to test the fix works:
TENANT_NAME=datasquiz BASE_DIR=/mnt/datasquiz bash scripts/1-setup-system.sh
# Should complete without hanging
```

Windsurf must add this test to its validation before declaring Script 1 valid.
```