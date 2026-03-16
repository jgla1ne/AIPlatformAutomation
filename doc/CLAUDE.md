Let me read the actual files to find the source of this.Found it. Now I need to verify one more thing — where the stale Azure config is coming from.Now I have the complete picture with certainty. Let me write the implementation.

---

## Root Cause — Definitive

The log line `"general_settings": null` is the smoking gun. It means LiteLLM is **not reading `config.yaml`**. It is reading its model list entirely from the Postgres database, because `STORE_MODEL_IN_DB: "True"` is set in the compose block.

Here is the exact sequence of events that causes the Azure config to always reappear:

1. A previous deployment ran Script 1 with Azure keys configured. LiteLLM started, read `config.yaml` (which had Azure models), and stored them in the `litellm` Postgres database under `STORE_MODEL_IN_DB=True`.
2. Script 0 ran. It removed containers and wiped `/mnt/data`. However, `postgres_data` is a **named Docker volume** (`volumes: postgres_data:` in the compose file). Docker names it `ai-datasquiz_postgres_data`. Script 0's filter `name=ai-` should catch it — but only if the containers were fully stopped before `docker volume rm` ran. If any container held the volume open, the `rm` silently failed (`|| true` swallows the error).
3. On re-deploy, postgres comes up with its old data intact, containing the `litellm` database with the Azure models still stored in it.
4. LiteLLM starts, ignores `config.yaml` entirely (because `STORE_MODEL_IN_DB=True` means "trust the database"), reads Azure models from the DB, and crashes because the Azure credentials are gone.

`config.yaml` is correct. `generate_litellm_config` is correct. The problem is that `STORE_MODEL_IN_DB=True` bypasses `config.yaml` after the first run.

---

## Two Fixes Required

### Fix 1 — `scripts/3-configure-services.sh`: Remove `STORE_MODEL_IN_DB` from the LiteLLM compose block

This is the direct fix. Without `STORE_MODEL_IN_DB`, LiteLLM reads **only** from `config.yaml` on every startup. The freshly generated `config.yaml` is always correct. Stale DB state can never override it.

In `generate_compose`, replace the entire litellm environment block:

```bash
# FROM (lines 506–517):
    environment:
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
      LITELLM_SALT_KEY: ${LITELLM_SALT_KEY}
      DATABASE_URL: ${LITELLM_DATABASE_URL}
      REDIS_URL: ${REDIS_URL}
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      OPENAI_API_KEY: ${OPENAI_API_KEY:-}
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:-}
      GROQ_API_KEY: ${GROQ_API_KEY:-}
      STORE_MODEL_IN_DB: "True"
      LITELLM_TELEMETRY: "False"
      PRISMA_DISABLE_WARNINGS: "true"

# TO:
    environment:
      LITELLM_MASTER_KEY: ${LITELLM_MASTER_KEY}
      LITELLM_SALT_KEY: ${LITELLM_SALT_KEY}
      DATABASE_URL: ${LITELLM_DATABASE_URL}
      REDIS_URL: ${REDIS_URL}
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      OPENAI_API_KEY: ${OPENAI_API_KEY:-}
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:-}
      GROQ_API_KEY: ${GROQ_API_KEY:-}
      LITELLM_TELEMETRY: "False"
      PRISMA_DISABLE_WARNINGS: "true"
```

`STORE_MODEL_IN_DB: "True"` is the only line removed. The database is still used for spend tracking, audit logs, and API key management — just not for the model list. The model list comes exclusively from `config.yaml` which is regenerated on every deploy from what the user actually configured in Script 1.

### Fix 2 — `scripts/0-complete-cleanup.sh`: Guarantee named volumes are destroyed

The current volume cleanup can silently fail if a container held a volume open. Add an explicit `docker volume rm` for each known named volume by its computed name, after the containers are confirmed dead:

In `main()`, after the existing volume prune block (after line 87), add:

```bash
    # Explicitly remove named compose volumes by computed name
    # These follow the pattern: {COMPOSE_PROJECT_NAME}_{volume_name}
    log "Explicitly removing named compose volumes..."
    for vol in postgres_data prometheus_data grafana_data litellm_data; do
        local vol_name="${COMPOSE_PROJECT_NAME}_${vol}"
        if docker volume inspect "$vol_name" &>/dev/null; then
            docker volume rm "$vol_name" && ok "Removed volume: ${vol_name}" || warn "Could not remove ${vol_name} (may be in use)"
        fi
    done
```

This is belt-and-suspenders. Fix 1 is the real solution. Fix 2 ensures the DB is always clean regardless. Together they make it impossible for stale model configuration to survive a cleanup cycle.

---

## Why `config.yaml` Was Being Ignored (Not a Code Bug — a Design Conflict)

`STORE_MODEL_IN_DB=True` is a LiteLLM feature for teams who want to manage models via the LiteLLM UI or API after deployment. The platform's architecture principle is **Zero Hardcoded Values — all configuration via `.env` variables**. These two things are in direct conflict. Our `config.yaml` is the source of truth, generated at deploy time from what the user selected. Giving LiteLLM permission to override that from a database that may contain stale data from a previous deployment violates the principle. Removing `STORE_MODEL_IN_DB` restores `config.yaml` as the single authoritative source.