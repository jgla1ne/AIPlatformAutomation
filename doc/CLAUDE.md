Let me read every uploaded file carefully before writing anything.---

## Final Windsurf Blueprint — Zero Warnings, Full Stack

### The Root Cause of "Outbound Variables"

Script 1 collects and writes ports as `LITELLM_PORT`, `GRAFANA_PORT`, `OPENWEBUI_PORT`, etc. Script 3's compose file reads `${PORT_LITELLM:-4000}`, `${PORT_GRAFANA:-3002}`, `${PORT_OPENWEBUI:-3000}` etc. These are **completely different variable names**. Docker Compose emits a `WARN: PORT_LITELLM variable is not set` for every one of them. That is the entire cause of the outbound variable flood.

**Fix — Script 1 `write_env_file`**, in the Ports section (after line 2471, before the Additional Variables comment):

```bash
# ─── PORT_ aliases for Docker Compose (Script 3 uses PORT_X naming) ─────────
PORT_LITELLM=${LITELLM_PORT:-4000}
PORT_OPENWEBUI=${OPENWEBUI_PORT:-3000}
PORT_N8N=${N8N_PORT:-5678}
PORT_FLOWISE=${FLOWISE_PORT:-3001}
PORT_GRAFANA=${GRAFANA_PORT:-3002}
PORT_PROMETHEUS=${PROMETHEUS_PORT:-9090}
PORT_QDRANT=${QDRANT_PORT:-6333}
PORT_ANYTHINGLLM=${ANYTHINGLLM_PORT:-3003}
PORT_OPENCLAW=${OPENCLAW_PORT:-18789}
PORT_CODESERVER=${CODESERVER_PORT:-8443}
PORT_OLLAMA=${OLLAMA_PORT:-11434}
```

That eliminates every "not set" warning from Docker Compose. Zero other changes needed for this issue.

---

### The Three Remaining Code Bugs

**Bug 1 — Script 3 `prepare_directories`: codeserver directory missing**

`prepare_directories` creates all service data directories but has no entry for `codeserver`. Add it to the `mkdir -p` block and the UID ownership block:

```bash
# In the mkdir -p block, add:
"${DATA_DIR}/codeserver" \

# In the 1000-UID ownership block, add:
"${DATA_DIR}/codeserver" \
```

**Bug 2 — Script 3 `generate_compose` codeserver: wrong workspace mount target**

`lscr.io/linuxserver/code-server` runs as user `abc` (UID 1000). The home directory is `/home/abc`. The workspace/project should be mounted at `/config/workspace` (linuxserver convention), not `/home/coder/project` (that user doesn't exist in this image).

```yaml
# FROM:
      - ${TENANT_DIR}/${GITHUB_PROJECT:-github}:/home/coder/project
# TO:
      - ${TENANT_DIR}/${GITHUB_PROJECT:-github}:/config/workspace
```

**Bug 3 — Script 3 `health_dashboard`: missing access URL table and codeserver HTTPS URL**

The dashboard shows service health checks (localhost ports) but not the HTTPS URLs the user actually opens in a browser. Add this block before `log_write INFO` (after line 1237):

```bash
    echo ""
    echo -e "  ${BOLD}🌐 Access URLs${NC}"
    printf "  %-26s %s\n" "Chat (OpenWebUI):"     "https://chat.${DOMAIN}"
    [[ "${ENABLE_LITELLM:-false}"    == "true" ]] && printf "  %-26s %s\n" "LiteLLM API:"        "https://litellm.${DOMAIN}"
    [[ "${ENABLE_N8N:-false}"        == "true" ]] && printf "  %-26s %s\n" "n8n Automation:"     "https://n8n.${DOMAIN}"
    [[ "${ENABLE_FLOWISE:-false}"    == "true" ]] && printf "  %-26s %s\n" "Flowise:"            "https://flowise.${DOMAIN}"
    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && printf "  %-26s %s\n" "AnythingLLM:"       "https://anythingllm.${DOMAIN}"
    [[ "${ENABLE_CODESERVER:-false}" == "true" ]] && printf "  %-26s %s\n" "OpenCode IDE:"       "https://opencode.${DOMAIN}"
    [[ "${ENABLE_MONITORING:-false}" == "true" ]] && {
        printf "  %-26s %s\n" "Grafana:"           "https://grafana.${DOMAIN}"
        printf "  %-26s %s\n" "Prometheus:"        "https://prometheus.${DOMAIN}"
    }
    [[ "${ENABLE_OPENCLAW:-false}"  == "true" ]] && \
        printf "  %-26s %s\n" "OpenClaw (Tailscale):" "https://${ip:-<tailscale-ip>}:${PORT_OPENCLAW:-18789}"
    echo ""
    echo -e "  ${BOLD}⚡ LiteLLM Quick Test${NC}"
    echo -e "    curl -s https://litellm.${DOMAIN}/v1/models \\"
    echo -e "      -H 'Authorization: Bearer \${LITELLM_MASTER_KEY}' | jq '.data[].id'"
```

---

### Summary Table

| File | Line(s) | Change |
|------|---------|--------|
| `scripts/1-setup-system.sh` | After line 2471 | Add 11 `PORT_X=` alias lines |
| `scripts/3-configure-services.sh` | `prepare_directories` (~line 59) | Add `${DATA_DIR}/codeserver` to mkdir and chown blocks |
| `scripts/3-configure-services.sh` | Codeserver compose ~line 897 | Change `/home/coder/project` → `/config/workspace` |
| `scripts/3-configure-services.sh` | `health_dashboard` after line 1237 | Add access URL table block |

**Scripts 0 and 2 are correct. No changes needed.**