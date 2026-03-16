Let me read every file carefully before writing anything.The logs are pointing at **three root causes** — not ten. The comprehensive log analysis Windsurf wrote is partially correct but misidentifies the actual source of each failure. Here is the precise picture:

---

## What is Actually Broken (3 Issues, Not 10)

### Issue 1 — `GRAFANA_ADMIN_PASSWORD` is never written to the `.env` (confirmed blocker)

Script 3's `generate_env` writes `GRAFANA_ADMIN_PASSWORD=\${ADMIN_PASSWORD}` (line 135 — a deferred reference). Script 1's `write_env_file` writes `GRAFANA_PASSWORD` and `GF_SECURITY_ADMIN_PASSWORD` (lines 2277–2278) but **never writes `GRAFANA_ADMIN_PASSWORD`**. The compose block uses `${GRAFANA_ADMIN_PASSWORD}` (line 601). Docker Compose finds it blank, logs the warning, and Grafana starts with no password. This also means `ADMIN_PASSWORD` in the `.env` resolves to `AUTHENTIK_BOOTSTRAP_PASSWORD` — which may be empty when Authentik isn't enabled, making every service that depends on `${ADMIN_PASSWORD}` (openclaw, flowise) also start with a blank password.

**Fix — Script 1 `write_env_file`, add after line 2278:**
```bash
GRAFANA_ADMIN_PASSWORD="${GRAFANA_PASSWORD}"
ADMIN_PASSWORD="${GRAFANA_PASSWORD}"
```
Use `GRAFANA_PASSWORD` as the source (it is always generated). Do not tie `ADMIN_PASSWORD` to `AUTHENTIK_BOOTSTRAP_PASSWORD` since Authentik is often disabled.

### Issue 2 — `openwebui` database not in `generate_postgres_init` grants (confirmed blocker)

Script 3's `generate_postgres_init` (lines 202–210) creates `litellm`, `openwebui`, and `n8n` databases correctly. However the GRANT section only grants privileges on `litellm`, `openwebui`, and `n8n` — but misses `flowise`. More critically, the role being granted is hardcoded as `aiplatform` but the `POSTGRES_USER` from Script 1's `.env` may differ if the user customised it during `collect_database`. Since `provision_databases` in Script 3 also runs at deploy time and creates databases with `OWNER "${POSTGRES_USER}"`, this is a belt-and-suspenders approach — but the init script role name must match `POSTGRES_USER` exactly or the grants fail silently.

**Fix — Script 3 `generate_postgres_init`:** Replace the hardcoded role name `aiplatform` with `${POSTGRES_USER}` throughout the init script. This ensures the role created and the databases owned are always the same user regardless of what Script 1 collected:

```bash
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${POSTGRES_USER}') THEN
      CREATE ROLE ${POSTGRES_USER} WITH LOGIN PASSWORD '${POSTGRES_PASSWORD}';
    END IF;
```
And add `flowise` to the database creation and grants.

### Issue 3 — LiteLLM `config.yaml` hardcodes Ollama model names that don't exist yet

Script 3's `generate_litellm_config` hardcodes `ollama/llama3.2:1b` and `ollama/llama3.2:3b` as the local models (lines 240–249) regardless of what `OLLAMA_MODELS` is set to in the `.env`. When Ollama starts fresh it has no models pulled. LiteLLM tries to verify these models at startup, gets a 404, and crashes. The Azure config issue in the logs is **a red herring from a previous deployment** — the current `generate_litellm_config` already has correct Azure guards. The actual crash is the hardcoded model names.

**Fix — Script 3 `generate_litellm_config`:** Remove the hardcoded `llama3.2:1b` and `llama3.2:3b` blocks and replace with the dynamic `OLLAMA_MODELS` loop that was in the previous version:

```bash
    # Replace the hardcoded block (lines 239-250) with:
    [[ -n "${OLLAMA_MODELS:-}" ]] && for m in ${OLLAMA_MODELS//,/ }; do
        cat >> "${CONFIG_DIR}/litellm/config.yaml" <<EOF
  - model_name: ${m}
    litellm_params:
      model: ollama/${m}
      api_base: "http://ollama:11434"
EOF
    done
```

Also add `OLLAMA_KEEP_ALIVE: -1` and `OLLAMA_NOHISTORY: "true"` to the Ollama compose environment to prevent it from unloading models after idle time.

---

## The Three Exact File Changes

**`scripts/3-configure-services.sh` — 2 changes:**

**Change A** — `generate_litellm_config` (lines 239–250): replace hardcoded model block with dynamic `OLLAMA_MODELS` loop.

**Change B** — `generate_postgres_init` (lines 196–210): replace hardcoded `aiplatform` role with `${POSTGRES_USER}` throughout, and add `flowise` to the database creation and grants.

**`scripts/1-setup-system.sh` — 1 change:**

**Change C** — `write_env_file` (after line 2278): add `GRAFANA_ADMIN_PASSWORD="${GRAFANA_PASSWORD}"` and `ADMIN_PASSWORD="${GRAFANA_PASSWORD}"` so all downstream services that use `${ADMIN_PASSWORD}` get a real value regardless of whether Authentik is enabled.

**`scripts/2-deploy-services.sh` — 0 changes.** It is correct.  
**`scripts/0-complete-cleanup.sh` — 0 changes.** It is correct.

---

After these three changes: run Script 0 to wipe, Script 1 to collect, Script 2 to deploy. LiteLLM will start cleanly because it only references models that exist in `OLLAMA_MODELS`. OpenWebUI will connect to its database because the init script creates it under the correct role. Grafana will have its admin password. All three restart loops stop.