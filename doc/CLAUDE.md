Let me read every file completely before writing anything.---

I have now read every file completely. Here is the definitive, zero-error blueprint for Windsurf.

---

## Complete Audit: What Works, What Is Broken, What Is Missing

### What is working correctly
Script 0 (cleanup), Script 2 (deploy sequence), the postgres init, provision_databases, the LiteLLM command override, generate_litellm_config logic, generate_caddyfile structure, all existing service compose blocks.

### The Six Bugs Requiring Fixes

---

**Bug 1 — Script 1: `ENABLE_CODESERVER` never written to `.env`**

Script 1 sets `ENABLE_CODESERVER=true` in bash memory during `select_stack()` (lines 836, 854) but the `write_env_file()` heredoc lists every other ENABLE flag except `ENABLE_CODESERVER`. When Script 2 reads `.env`, the variable is absent, defaults to `false`, and codeserver is never deployed.

**Fix — Script 1 `write_env_file`, in the Service Flags section (after line 2159):**
```bash
ENABLE_CODESERVER=${ENABLE_CODESERVER:-false}
ENABLE_CONTINUE=${ENABLE_CONTINUE:-false}
```

---

**Bug 2 — Script 2: `codeserver` never deployed**

Script 2 has no deploy step for codeserver. After step 9 (openclaw), add:

```bash
    [[ "${ENABLE_CODESERVER:-false}" == "true" ]] && deploy_service codeserver
```

Place it between openclaw and gdrive in step 9.

---

**Bug 3 — Script 3: `codeserver` compose block — three sub-issues**

**3a — Wrong healthcheck.** `lscr.io/linuxserver/code-server` runs plain HTTP internally on port 8443 (despite the port number). The healthcheck `curl -sf http://localhost:8443/` is correct. **No change needed here.**

**3b — `/mnt/data` mounted read-only, but codeserver needs write access to execute scripts on the server.** The user explicitly requires codeserver to run bash scripts directly on the server. The current mount is `:ro`. Change to `:rw`.

**3c — Git folder.** The user confirmed the git folder is at `${TENANT_DIR}/${GITHUB_PROJECT:-github}` which IS under `/mnt/data`. This is not an exception to the `/mnt` rule. The current mount is correct. The note about it being an exception was a misunderstanding — it is still under `/mnt/data/datasquiz/github`. No change needed for this.

**Fix — Script 3 `generate_compose`, codeserver volumes block, line 853:**
```yaml
# FROM:
      - /mnt/data:/mnt/data:ro
# TO:
      - /mnt/data:/mnt/data:rw
```

---

**Bug 4 — Script 3: `service_is_enabled()` missing `codeserver` and `anythingllm`**

The `service_is_enabled()` case statement (lines 969–981) is missing entries for `codeserver` and `anythingllm`. Add them:

```bash
        codeserver) [[ "${ENABLE_CODESERVER:-false}" == "true" ]] ;;
        anythingllm)[[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] ;;
```

---

**Bug 5 — Script 3: `health_dashboard` missing codeserver HTTPS URL and all service access URLs**

The dashboard checks `codeserver` via `http://localhost:${PORT_CODESERVER:-8443}/` — correct for container-internal check. But it must also show the user the HTTPS subdomain URL. Replace the Development Environment section and add the full access URL table at the end:

Replace the `Development Environment` section (lines 1174–1176):
```bash
    echo ""
    echo -e "  ${BOLD}Development Environment${NC}"
    [[ "${ENABLE_CODESERVER:-false}" == "true" ]] && {
        _check_http  "codeserver"  "http://localhost:${PORT_CODESERVER:-8443}/"
        printf "  %-14s %s\n" "→ OpenCode URL:" "https://opencode.${DOMAIN}"
        printf "  %-14s %s\n" "→ Continue.dev:" "LiteLLM at http://litellm:4000/v1 (pre-configured)"
    }
```

Add a full access URL table before `log_write INFO` (before line 1195):
```bash
    echo ""
    echo -e "  ${BOLD}Access URLs${NC}"
    printf "  %-28s %s\n" "Chat (OpenWebUI):"        "https://chat.${DOMAIN}"
    [[ "${ENABLE_LITELLM:-false}"    == "true" ]] && \
        printf "  %-28s %s\n" "LiteLLM API:"          "https://litellm.${DOMAIN}"
    [[ "${ENABLE_N8N:-false}"        == "true" ]] && \
        printf "  %-28s %s\n" "n8n Automation:"       "https://n8n.${DOMAIN}"
    [[ "${ENABLE_FLOWISE:-false}"    == "true" ]] && \
        printf "  %-28s %s\n" "Flowise:"              "https://flowise.${DOMAIN}"
    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && \
        printf "  %-28s %s\n" "AnythingLLM:"          "https://anythingllm.${DOMAIN}"
    [[ "${ENABLE_CODESERVER:-false}" == "true" ]] && \
        printf "  %-28s %s\n" "OpenCode IDE:"         "https://opencode.${DOMAIN}"
    [[ "${ENABLE_MONITORING:-false}" == "true" ]] && {
        printf "  %-28s %s\n" "Grafana:"              "https://grafana.${DOMAIN}"
        printf "  %-28s %s\n" "Prometheus:"           "https://prometheus.${DOMAIN}"
    }
    [[ "${ENABLE_OPENCLAW:-false}"   == "true" ]] && \
        printf "  %-28s %s\n" "OpenClaw (Tailscale):" "https://openclaw.${DOMAIN} or https://${ip}:${PORT_OPENCLAW:-18789}"
    echo ""
    echo -e "  ${BOLD}LiteLLM Quick Test${NC}"
    echo -e "    curl -s https://litellm.${DOMAIN}/v1/models \\"
    echo -e "      -H 'Authorization: Bearer \${LITELLM_MASTER_KEY}' | jq '.data[].id'"
```

---

**Bug 6 — Script 3: Continue.dev not properly configured in codeserver**

`lscr.io/linuxserver/code-server` does not support installing extensions via `EXTENSIONS` env var — that is not a recognised variable for this image. Continue.dev must be pre-installed or configured via a startup script. The correct approach is to write a `continue.json` config file to the codeserver data directory at deploy time, and mount it.

**Fix — Script 3 `generate_configs()`: add `generate_codeserver_config` call:**

Add this function before `generate_configs()`:

```bash
generate_codeserver_config() {
    [[ "${ENABLE_CODESERVER:-false}" == "true" ]] || return 0
    local config_dir="${DATA_DIR}/codeserver/.continue"
    mkdir -p "$config_dir"
    chown -R 1000:"${TENANT_GID:-1001}" "$(dirname "$config_dir")"

    cat > "${config_dir}/config.json" <<EOF
{
  "models": [
    {
      "title": "Local (Ollama via LiteLLM)",
      "provider": "openai",
      "model": "${OLLAMA_DEFAULT_MODEL:-llama3.2:1b}",
      "apiBase": "http://litellm:4000/v1",
      "apiKey": "${LITELLM_MASTER_KEY}"
    }
$(
  [[ -n "${OPENAI_API_KEY:-}" ]] && echo "    ,{\"title\":\"GPT-4o (via LiteLLM)\",\"provider\":\"openai\",\"model\":\"gpt-4o\",\"apiBase\":\"http://litellm:4000/v1\",\"apiKey\":\"${LITELLM_MASTER_KEY}\"}"
  [[ -n "${GOOGLE_API_KEY:-}" ]] && echo "    ,{\"title\":\"Gemini Pro (via LiteLLM)\",\"provider\":\"openai\",\"model\":\"gemini-pro\",\"apiBase\":\"http://litellm:4000/v1\",\"apiKey\":\"${LITELLM_MASTER_KEY}\"}"
  [[ -n "${GROQ_API_KEY:-}" ]]  && echo "    ,{\"title\":\"Llama3 Groq (via LiteLLM)\",\"provider\":\"openai\",\"model\":\"llama3-groq\",\"apiBase\":\"http://litellm:4000/v1\",\"apiKey\":\"${LITELLM_MASTER_KEY}\"}"
)
  ],
  "tabAutocompleteModel": {
    "title": "Autocomplete",
    "provider": "openai",
    "model": "${OLLAMA_DEFAULT_MODEL:-llama3.2:1b}",
    "apiBase": "http://litellm:4000/v1",
    "apiKey": "${LITELLM_MASTER_KEY}"
  },
  "embeddingsProvider": {
    "provider": "openai",
    "model": "${OLLAMA_DEFAULT_MODEL:-llama3.2:1b}",
    "apiBase": "http://litellm:4000/v1",
    "apiKey": "${LITELLM_MASTER_KEY}"
  }
}
EOF
    log_success "Continue.dev config written to ${config_dir}/config.json"
}
```

Add `generate_codeserver_config` to `generate_configs()`:
```bash
generate_configs() {
    log_info "Generating all configuration files..."
    generate_postgres_init
    generate_litellm_config
    generate_caddyfile
    generate_prometheus_config
    generate_codeserver_config    # ← ADD THIS LINE
    log_success "All configuration files generated"
}
```

And mount the continue config in the codeserver compose block — update the volumes section:
```yaml
    volumes:
      - ${DATA_DIR}/codeserver:/config
      - ${DATA_DIR}/codeserver/.continue:/home/abc/.continue:rw
      - /mnt/data:/mnt/data:rw
      - ${TENANT_DIR}/${GITHUB_PROJECT:-github}:/home/coder/project
```

---

## LiteLLM Integration Audit — Every Service

| Service | Connected to LiteLLM | How | Status |
|---------|---------------------|-----|--------|
| **OpenWebUI** | ✅ | `OPENAI_API_BASE_URL=http://litellm:4000/v1`, key=`LITELLM_MASTER_KEY` | Correct |
| **n8n** | ✅ | `N8N_AI_OPENAI_BASE_URL=http://litellm:4000/v1`, key=`LITELLM_MASTER_KEY` | Correct |
| **Flowise** | ✅ | `OPENAI_API_BASE=http://litellm:4000/v1`, key=`LITELLM_MASTER_KEY` | Correct |
| **AnythingLLM** | ✅ | `OPEN_AI_BASE_PATH=http://litellm:4000/v1`, key=`LITELLM_MASTER_KEY` | Correct |
| **CodeServer/Continue.dev** | ⚠️ | Env vars only — no config.json → not actually wired | Fixed by Bug 6 above |
| **Ollama** | N/A | Ollama is the *source*, not a consumer. LiteLLM routes TO Ollama | Correct |
| **Qdrant** | N/A | Vector DB, not an LLM consumer | Correct |

All services correctly point to `http://litellm:4000/v1` and use `LITELLM_MASTER_KEY` as the API key. LiteLLM then routes internally to Ollama (local) or external providers based on the routing strategy. The architecture is correct.

---

## Caddy HTTPS Issue

The user reports some URLs work under HTTPS, others don't. This is not a code bug — it is a **DNS configuration requirement**. Caddy can only serve `https://chat.ai.datasquiz.net` if DNS has a wildcard `*.ai.datasquiz.net → server IP` record. If some subdomains resolve and others don't, the DNS wildcard is not set, and each subdomain needs a separate A record. Nothing in the scripts can fix this. The user must add `*.ai.datasquiz.net IN A <server-public-ip>` to their DNS provider.

With `tls internal` (self-signed), Caddy generates certs for all configured domains but browsers will show a security warning until a trusted cert is used. Switching to `USE_LETSENCRYPT=true` during Script 1 collection resolves this, provided DNS is set correctly so Let's Encrypt can validate the domains.

---

## Summary: All Changes Required

| File | Change |
|------|--------|
| `scripts/1-setup-system.sh` | Add `ENABLE_CODESERVER` and `ENABLE_CONTINUE` to the service flags section of `write_env_file()` |
| `scripts/2-deploy-services.sh` | Add `[[ "${ENABLE_CODESERVER:-false}" == "true" ]] && deploy_service codeserver` in step 9 |
| `scripts/3-configure-services.sh` | Fix codeserver compose volumes: `/mnt/data:rw` not `:ro` |
| `scripts/3-configure-services.sh` | Add `codeserver` and `anythingllm` to `service_is_enabled()` |
| `scripts/3-configure-services.sh` | Add `generate_codeserver_config` function + call in `generate_configs()` |
| `scripts/3-configure-services.sh` | Add `.continue` volume mount in codeserver compose block |
| `scripts/3-configure-services.sh` | Update `health_dashboard` with full access URL table and codeserver section |