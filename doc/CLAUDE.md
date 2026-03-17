Let me read everything before writing a single word.**The actual remaining issues, in plain language:**

---

## The Four Issues Windsurf Must Fix — Nothing More

### Issue 1 — Gemini key variable name split (confirmed, 2 lines to fix)

Script 1 collects the Gemini key into `GOOGLE_API_KEY` and writes `GOOGLE_API_KEY` to the `.env`. Script 3's `generate_env` (the standalone path) writes `GEMINI_API_KEY`. Script 3's `generate_litellm_config` checks `GOOGLE_API_KEY`. Script 3's compose block passes `GOOGLE_API_KEY`. The generate path is consistent. The standalone `generate_env` is not. Fix: in Script 3's `generate_env` API keys section (line 140), replace `GEMINI_API_KEY` with `GOOGLE_API_KEY` to match Script 1 and `generate_litellm_config`.

### Issue 2 — Fallback references non-existent models (confirmed crash cause)

When only `GROQ_API_KEY` is set, the fallback section writes `llama3-groq: ["gemini-pro", "openrouter-mixtral"]`. Neither `gemini-pro` nor `openrouter-mixtral` exist in the model list since those keys aren't set. LiteLLM validates fallback targets at startup and crashes immediately with a validation error. This is why LiteLLM fails even after removing `STORE_MODEL_IN_DB`.

**Fix** — Script 3 `generate_litellm_config`: Each fallback must only list models that are actually in the model list. Build the fallback list dynamically:

```bash
    # Build fallback list from only configured models
    if [[ -n "${OPENAI_API_KEY:-}" || -n "${GROQ_API_KEY:-}" || -n "${GOOGLE_API_KEY:-}" || -n "${OPENROUTER_API_KEY:-}" ]]; then
        # Collect which external models are configured
        local external_models=()
        [[ -n "${OPENAI_API_KEY:-}" ]]     && external_models+=("gpt-4o")
        [[ -n "${GROQ_API_KEY:-}" ]]       && external_models+=("llama3-groq")
        [[ -n "${GOOGLE_API_KEY:-}" ]]     && external_models+=("gemini-pro")
        [[ -n "${OPENROUTER_API_KEY:-}" ]] && external_models+=("openrouter-mixtral")

        if [[ ${#external_models[@]} -gt 1 ]]; then
            cat >> "${CONFIG_DIR}/litellm/config.yaml" <<EOF
  fallbacks:
EOF
            for model in "${external_models[@]}"; do
                # Build fallback list = all other external models
                local others=()
                for other in "${external_models[@]}"; do
                    [[ "$other" != "$model" ]] && others+=("\"$other\"")
                done
                local others_str
                others_str=$(IFS=,; echo "${others[*]}")
                cat >> "${CONFIG_DIR}/litellm/config.yaml" <<EOF
    - ${model}: [${others_str}]
EOF
            done
        fi
    fi
```

This guarantees fallbacks only reference models that exist in the model list.

### Issue 3 — CI/CD race condition (confirmed, Script 0 must kill bash processes)

Windsurf re-runs Script 1 without running Script 0 first, then encounters leftover Docker and bash processes from the previous run. The fix already exists in Script 0 (`pkill` calls) but it targets Docker process names. Add explicit killing of any running deploy/setup scripts before starting fresh:

Add to Script 0 `main()` at the very top, before stopping containers:

```bash
    # Kill any running AI platform scripts to prevent race conditions
    log "Terminating any running platform scripts..."
    pkill -f "1-setup-system.sh" || true
    pkill -f "2-deploy-services.sh" || true
    pkill -f "3-configure-services.sh" || true
    sleep 2  # Let them terminate cleanly
    ok "Platform scripts terminated."
```

### Issue 4 — LiteLLM `config.yaml` YAML indentation in the router_settings block is wrong

The `fallbacks:` block is written under `router_settings:` but with inconsistent indentation — `fallbacks:` gets 2-space indent, then each fallback entry gets 4-space. In YAML, `fallbacks:` must be at the same level as `routing_strategy:`. Check the current output:

```yaml
router_settings:
  routing_strategy: least-busy
  fallbacks:         ← this is CORRECT (same level as routing_strategy)
    - llama3-groq: [...]   ← this is also CORRECT
```

Looking at the code, `fallbacks:` is written inside the `router_settings:` block correctly. **But** the `general_settings:` block is written as a top-level key right after, with no blank line separation — this is fine in YAML but worth verifying the generated file has no indentation errors.

The real verification step: after each deploy, run:

```bash
cat /mnt/data/datasquiz/configs/litellm/config.yaml
```

And confirm it looks exactly like:

```yaml
model_list:
  - model_name: llama3.1
    litellm_params:
      model: ollama/llama3.1
      api_base: "http://ollama:11434"
      rpm: 100

litellm_settings:
  drop_params: true
  set_verbose: false
  cache: true
  cache_params:
    type: redis
    host: redis
    port: 6379
    password: os.environ/REDIS_PASSWORD

router_settings:
  routing_strategy: least-busy

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/LITELLM_DATABASE_URL
```

No Azure models. No missing key references. No fallbacks pointing to unconfigured models.

---

## What Windsurf Must Do — Exactly This, Nothing Else

**File: `scripts/3-configure-services.sh`**

1. Line 140: change `GEMINI_API_KEY=${GEMINI_API_KEY:-}` → `GOOGLE_API_KEY=${GOOGLE_API_KEY:-}`
2. Lines 332–347: replace the entire fallbacks block with the dynamic version above that only references actually-configured models

**File: `scripts/0-complete-cleanup.sh`**

3. Add `pkill` for running platform scripts at the top of `main()` before any other action

**No changes to Script 1. No changes to Script 2. No changes to the postgres init. No changes to the compose block.** Those are all correct. The LiteLLM crash is caused entirely by the fallback validation referencing models that don't exist.