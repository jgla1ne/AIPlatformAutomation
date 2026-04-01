Let me fetch everything.

**WINDSURF.md:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/doc/WINDSURF.md

**Script 1 current:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/1-setup-system.sh

**README:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/README.md

**Working commit c38d365 Script 1:** https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/c38d365/scripts/1-setup-system.sh

---

```markdown
# CLAUDE.md — Script 1 Restoration Plan
**Date:** 2025-07
**Reference commit:** c38d365 (known working input collector)

---

## 🔎 DIAGNOSIS: What Windsurf's plan gets right vs wrong

After reading WINDSURF.md proposed plan and comparing c38d365 vs current Script 1:

### ✅ Windsurf correctly identified:
- The `read` calls hang in non-TTY context
- c38d365 had a working UI/input pattern worth restoring
- The `prompt_input` function approach is the right abstraction

### ❌ Windsurf's plan is INCOMPLETE on these points:

1. **It plans to rewrite Script 1 from scratch** — this is the same circular
   mistake made before. The correct approach is SURGICAL: restore c38d365's
   input collection block verbatim, then ADD the non-TTY safety wrapper.

2. **It does not account for the full service menu** from README — the input
   collector must cover ALL service categories as defined in the north star,
   not just the subset Windsurf remembers.

3. **The `platform.conf` write block** must be atomic — write to a temp file
   then `mv`, never write directly, to prevent partial configs on interrupt.

---

## 📋 THE CORRECT RESTORATION PLAN — 4 SURGICAL STEPS ONLY

### STEP 1: Restore c38d365 input collection verbatim

Do NOT rewrite. Do NOT refactor. Extract these exact blocks from c38d365
and place them in the current Script 1:

- The banner/UI display function
- The `collect_input()` or equivalent function containing all `read` calls
- The service selection menu (all categories)
- The `write_platform_conf()` block

```bash
# Windsurf command to get the exact diff:
git show c38d365:scripts/1-setup-system.sh > /tmp/script1_working.sh
diff /tmp/script1_working.sh scripts/1-setup-system.sh
# Apply ONLY the input collection sections from the working version
```

### STEP 2: Wrap EVERY `read` call with TTY detection — ONE function

Add this single function at the top of Script 1, above all other functions.
Do not add it inline at each `read` call:

```bash
# ─── NON-INTERACTIVE SAFE INPUT ──────────────────────────────────────────────
safe_read() {
  # Usage: safe_read "Prompt text" DEFAULT_VALUE VARIABLE_NAME
  local prompt="$1"
  local default="$2"
  local varname="$3"
  local value

  # Check for env var override first (allows: VAR=x sudo -E bash script1.sh)
  value=$(printenv "${varname}" 2>/dev/null || true)

  if [ -n "${value}" ]; then
    echo "  ${prompt}: ${value} (from environment)"
  elif [ -t 0 ]; then
    # Real TTY — show prompt and wait for input
    read -rp "  ${prompt} [${default}]: " value
    value="${value:-${default}}"
  else
    # Non-TTY (Windsurf, CI, pipe) — use default silently
    value="${default}"
    echo "  ${prompt}: ${value} (default — non-interactive mode)"
  fi

  printf -v "${varname}" '%s' "${value}"
}
# ─────────────────────────────────────────────────────────────────────────────
```

### STEP 3: Replace every `read` call with `safe_read`

Pattern — mechanical find-and-replace, no logic changes:
```bash
# BEFORE:
read -rp "  Enter tenant name: " TENANT_NAME

# AFTER:
safe_read "Enter tenant name" "datasquiz" "TENANT_NAME"
```

### STEP 4: Atomic platform.conf write

```bash
write_platform_conf() {
  local conf_file="${BASE_DIR}/platform.conf"
  local tmp_file="${conf_file}.tmp"

  cat > "${tmp_file}" << EOF
# AI Platform Configuration
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Tenant: ${TENANT_NAME}

TENANT_NAME=${TENANT_NAME}
BASE_DIR=${BASE_DIR}
DOMAIN=${DOMAIN}

# ── Postgres ──────────────────────────────────────────────
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}

# ── Service Flags ─────────────────────────────────────────
DEPLOY_OLLAMA=${DEPLOY_OLLAMA}
DEPLOY_OPENWEBUI=${DEPLOY_OPENWEBUI}
DEPLOY_N8N=${DEPLOY_N8N}
DEPLOY_FLOWISE=${DEPLOY_FLOWISE}
DEPLOY_LITELLM=${DEPLOY_LITELLM}
DEPLOY_QDRANT=${DEPLOY_QDRANT}
DEPLOY_REDIS=${DEPLOY_REDIS}

# ── Ollama ────────────────────────────────────────────────
OLLAMA_MODEL=${OLLAMA_MODEL}

# ── N8N ──────────────────────────────────────────────────
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_USER=${N8N_USER}
N8N_PASSWORD=${N8N_PASSWORD}

# ── OpenWebUI ────────────────────────────────────────────
WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}

# ── LiteLLM ──────────────────────────────────────────────
LITELLM_MASTER_KEY=${LITELLM_MASTER_KEY}
EOF

  mv "${tmp_file}" "${conf_file}"
  chmod 600 "${conf_file}"
  echo "✅ platform.conf written to ${conf_file}"
}
```

---

## 📦 FULL SERVICE INPUT COLLECTION — README NORTH STAR ALIGNMENT

Script 1 must collect input for ALL services from README. 
Windsurf must NOT reduce this list:

```bash
collect_all_inputs() {
  echo ""
  echo "━━━ TENANT CONFIGURATION ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  safe_read "Tenant name (alphanumeric, no spaces)" "datasquiz" "TENANT_NAME"
  safe_read "Base data directory" "/mnt/${TENANT_NAME}" "BASE_DIR"
  safe_read "Domain name" "${TENANT_NAME}.local" "DOMAIN"

  echo ""
  echo "━━━ AI ENGINE ────────────────────────────────────────────────"
  safe_read "Deploy Ollama (local LLM runner)" "true" "DEPLOY_OLLAMA"
  safe_read "Default Ollama model" "llama3.2" "OLLAMA_MODEL"
  safe_read "Deploy LiteLLM (unified LLM API gateway)" "true" "DEPLOY_LITELLM"

  echo ""
  echo "━━━ AI INTERFACES ────────────────────────────────────────────"
  safe_read "Deploy OpenWebUI (chat interface)" "true" "DEPLOY_OPENWEBUI"
  safe_read "Deploy Flowise (visual AI workflows)" "true" "DEPLOY_FLOWISE"

  echo ""
  echo "━━━ AUTOMATION & INTEGRATION ─────────────────────────────────"
  safe_read "Deploy N8N (workflow automation)" "true" "DEPLOY_N8N"

  echo ""
  echo "━━━ DATA & STORAGE ───────────────────────────────────────────"
  safe_read "Deploy Qdrant (vector database)" "true" "DEPLOY_QDRANT"
  safe_read "Deploy Redis (cache/queue)" "true" "DEPLOY_REDIS"

  echo ""
  echo "━━━ DATABASE CREDENTIALS ─────────────────────────────────────"
  safe_read "Postgres username" "${TENANT_NAME}" "POSTGRES_USER"
  safe_read "Postgres database name" "${TENANT_NAME}" "POSTGRES_DB"
  safe_read "Postgres password" "$(openssl rand -hex 16)" "POSTGRES_PASSWORD"

  echo ""
  echo "━━━ SERVICE SECRETS (auto-generated if blank) ────────────────"
  safe_read "N8N admin user" "admin" "N8N_USER"
  safe_read "N8N admin password" "$(openssl rand -hex 8)" "N8N_PASSWORD"
  safe_read "N8N encryption key" "$(openssl rand -hex 16)" "N8N_ENCRYPTION_KEY"
  safe_read "OpenWebUI secret key" "$(openssl rand -hex 32)" "WEBUI_SECRET_KEY"
  safe_read "LiteLLM master key" "$(openssl rand -hex 16)" "LITELLM_MASTER_KEY"
}
```

---

## ⚠️ CRITICAL CONSTRAINTS FOR WINDSURF

| Rule | Reason |
|------|--------|
| Do NOT rewrite Script 1 from scratch | Creates new bugs, loses c38d365 UI |
| Do NOT remove any service from the menu | README defines all services |
| Do NOT change Script 2 or 3 during this fix | Scope is Script 1 only |
| Do NOT use `echo -n` + `read` pattern | Fails in non-TTY |
| DO run `echo "" \| bash scripts/1-setup-system.sh` to test | Validates non-TTY |
| DO run `bash scripts/1-setup-system.sh` to test interactively | Validates TTY |

---

## ✅ VALIDATION TESTS — BOTH MUST PASS

```bash
# Test 1: Non-interactive (Windsurf's execution context)
echo "" | sudo bash scripts/1-setup-system.sh
# Expected: completes without hanging, writes platform.conf with defaults

# Test 2: Env var override
TENANT_NAME=mytest sudo -E bash scripts/1-setup-system.sh
# Expected: platform.conf contains TENANT_NAME=mytest

# Test 3: Verify output
cat /mnt/datasquiz/platform.conf
# Expected: all variables present, no blank values

# Test 4: Interactive smoke test
sudo bash scripts/1-setup-system.sh
# Expected: prompts appear, accepts input, writes platform.conf
```

**Script 1 is not done until all 4 tests pass.**
```