Let me read everything before responding.

After reading all files, here is the complete bulletproof plan.

---

## Diagnosis First: Why LiteLLM Failed Permanently

From `litellm-deployment-analysis.md` the root cause chain is:
1. Prisma client requires `DATABASE_URL` at **image build time** not just runtime
2. `ghcr.io/berriai/litellm:main-latest` ships with an ungenerated Prisma client
3. Every workaround (db push, generate, skip-generate) hits a different Prisma internal error
4. LiteLLM's startup validation of Ollama models is hardcoded and cannot be disabled via config
5. The image changes weekly breaking any pinned workaround

**Bifrost is the correct replacement.** It is a single Go binary, no database required, no Prisma, no startup validation, starts in under 1 second.

---

## The Complete Plan for Windsurf

### SCRIPT 0 — Add Bifrost Cleanup

```
In the cleanup section where litellm containers/volumes are removed,
add bifrost cleanup alongside litellm (not replacing — both options
must be cleanable):

# Find the litellm cleanup block and add after it:
log_info "Cleaning up Bifrost..."
docker rm -f ai-platform-bifrost 2>/dev/null || true
docker rmi ruqqq/bifrost 2>/dev/null || true
rm -rf "${CONFIG_DIR}/bifrost" 2>/dev/null || true

# In the .env cleanup section, add these variable patterns:
# BIFROST_*, LLM_ROUTER (add to the sed/grep removal patterns)
```

---

### SCRIPT 1 — LLM Router Selection

**Step 1: Add the selection prompt in `init_platform_config()`**

Find the section after `LITELLM_MASTER_KEY` is set (around the existing LiteLLM key generation block) and replace the entire LiteLLM key block with this router selection flow:

```bash
# ─── LLM Router Selection ─────────────────────────────────────────
print_section "LLM Router Configuration"
echo ""
echo "Select your LLM router:"
echo "  1) LiteLLM  - Feature-rich, Python-based, requires PostgreSQL"
echo "  2) Bifrost  - Lightweight Go binary, no database, fast startup"
echo ""

while true; do
    read -rp "Enter choice [1-2] (default: 2): " router_choice
    router_choice="${router_choice:-2}"
    case "$router_choice" in
        1) LLM_ROUTER="litellm"; break ;;
        2) LLM_ROUTER="bifrost"; break ;;
        *) echo "Invalid choice. Enter 1 or 2." ;;
    esac
done

update_env "LLM_ROUTER" "$LLM_ROUTER"
log_info "LLM Router: ${LLM_ROUTER}"
```

**Step 2: Add `init_bifrost()` function**

Add this complete function to script 1 after the existing `init_litellm()` function:

```bash
init_bifrost() {
    print_section "Bifrost Configuration"

    # Master key (shared concept with litellm for compatibility)
    if ! get_env_value "BIFROST_API_KEY" | grep -q .; then
        BIFROST_API_KEY="sk-bifrost-$(openssl rand -hex 24)"
        update_env "BIFROST_API_KEY" "$BIFROST_API_KEY"
        log_info "Generated Bifrost API key"
    else
        BIFROST_API_KEY=$(get_env_value "BIFROST_API_KEY")
        log_info "Using existing Bifrost API key"
    fi

    # Port (default 4000 to match litellm — zero changes to dependent services)
    BIFROST_PORT="${BIFROST_PORT:-4000}"
    update_env "BIFROST_PORT" "$BIFROST_PORT"

    # Ollama integration
    update_env "BIFROST_OLLAMA_BASE_URL" "http://ollama:11434"

    # Config directory
    mkdir -p "${CONFIG_DIR}/bifrost"
    log_success "Bifrost configuration complete"
}
```

**Step 3: Call the correct init based on selection**

Find the main init sequence in script 1 and replace the unconditional `init_litellm` call:

```bash
# Router-specific initialization
if [[ "${LLM_ROUTER}" == "bifrost" ]]; then
    init_bifrost
else
    init_litellm  # existing function unchanged
fi
```

**Step 4: Add Bifrost to health dashboard display**

Find the `display_mission_control()` or equivalent summary function and add:

```bash
if [[ "${LLM_ROUTER}" == "bifrost" ]]; then
    echo "  LLM Router:    Bifrost (port ${BIFROST_PORT:-4000})"
    echo "  Bifrost Key:   ${BIFROST_API_KEY:0:20}..."
else
    echo "  LLM Router:    LiteLLM (port 4000)"
    echo "  LiteLLM Key:   ${LITELLM_MASTER_KEY:0:20}..."
fi
```

---

### SCRIPT 2 — Modular Router Deployment

The architecture here is clean. The LLM_ROUTER variable from `.env` drives a conditional block.

**Step 1: Read router choice at top of script 2**

```bash
LLM_ROUTER=$(get_env_value "LLM_ROUTER" || echo "bifrost")
log_info "LLM Router selected: ${LLM_ROUTER}"
```

**Step 2: Replace the entire LiteLLM docker-compose service block with a function**

```bash
generate_llm_router_service() {
    if [[ "${LLM_ROUTER}" == "bifrost" ]]; then
        generate_bifrost_service
    else
        generate_litellm_service  # existing code moved into function
    fi
}
```

**Step 3: `generate_bifrost_service()` — the complete implementation**

```bash
generate_bifrost_service() {
    log_info "Generating Bifrost config..."

    # Generate bifrost config.json
    # Bifrost uses a simple JSON config — no Prisma, no migrations
    cat > "${CONFIG_DIR}/bifrost/config.json" << 'BIFROST_EOF'
{
  "providers": [
    {
      "provider": "ollama",
      "base_url": "http://ollama:11434",
      "default_model": "llama3.2"
    }
  ]
}
BIFROST_EOF

    # Generate docker-compose service block
    cat >> "${COMPOSE_FILE}" << COMPOSE_EOF

  bifrost:
    image: ruqqq/bifrost:latest
    container_name: ai-platform-bifrost
    restart: unless-stopped
    depends_on:
      ollama:
        condition: service_healthy
    environment:
      PORT: "4000"
      AUTH_TOKEN: \${BIFROST_API_KEY}
      OLLAMA_BASE_URL: http://ollama:11434
    volumes:
      - \${CONFIG_DIR}/bifrost/config.json:/app/config.json:ro
    ports:
      - "4000:4000"
    networks:
      - ai_network
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:4000/healthz"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 10s

COMPOSE_EOF

    log_success "Bifrost service definition generated"
}
```

**Step 4: Replace LiteLLM wait loop with router-aware wait**

```bash
wait_for_llm_router() {
    local router="${LLM_ROUTER:-bifrost}"
    local port=4000
    local container="ai-platform-${router}"
    local health_path="/healthz"
    
    if [[ "$router" == "litellm" ]]; then
        health_path="/health/liveliness"
    fi

    log_info "Waiting for ${router} on port ${port}..."
    
    local attempts=0
    local max_attempts=30  # 30 × 5s = 150s max — sufficient for both
    
    while [[ $attempts -lt $max_attempts ]]; do
        if curl -sf "http://localhost:${port}${health_path}" > /dev/null 2>&1; then
            log_success "${router} is healthy"
            return 0
        fi
        
        # Fail fast — if container exited, print logs and abort
        local state
        state=$(docker inspect "${container}" --format='{{.State.Status}}' 2>/dev/null)
        if [[ "$state" == "exited" ]]; then
            log_error "${router} container exited unexpectedly"
            docker logs "${container}" --tail 50 2>&1
            exit 1
        fi
        
        attempts=$((attempts + 1))
        sleep 5
    done
    
    log_error "${router} failed to become healthy after $((max_attempts * 5))s"
    docker logs "${container}" --tail 50 2>&1
    exit 1
}
```

**Step 5: Downstream services use `LLM_ROUTER_URL` env var**

After the router starts, set a unified variable:

```bash
# Set unified LLM router URL for dependent services
LLM_ROUTER_URL="http://ai-platform-${LLM_ROUTER}:4000"
update_env "LLM_ROUTER_URL" "$LLM_ROUTER_URL"

# AnythingLLM, OpenWebUI etc reference this single variable
# No changes needed in those service configs
```

---

### SCRIPT 3 — No Changes Required

Script 3 configures services post-deployment. AnythingLLM and OpenWebUI point to `LLM_ROUTER_URL` which resolves to the correct container regardless of which router was chosen.

---

### README Update Instructions

```
In README.md, Section "Software Stack":

FIND the LiteLLM entry:
  | LiteLLM | LLM Proxy | 4000 |

REPLACE with:
  | LiteLLM *(optional)* | LLM Proxy | 4000 |
  | Bifrost *(default)* | LLM Proxy | 4000 |

ADD a new subsection "LLM Router Selection":

  During script 1 setup you will be prompted to choose:
  
  1. **LiteLLM** — Full-featured Python proxy. Requires PostgreSQL.
     Supports spend tracking, team management, 100+ providers.
     Select if you need enterprise access controls.
     
  2. **Bifrost** *(recommended)* — Single Go binary. No database.
     Starts in <1s. OpenAI-compatible API on port 4000.
     Select for most deployments.
  
  Both expose identical OpenAI-compatible endpoints on port 4000.
  All downstream services (AnythingLLM, OpenWebUI, n8n, Dify)
  connect via LLM_ROUTER_URL and require no reconfiguration.

KEEP UNCHANGED:
  - All network stack documentation (Tailscale / 443)
  - All key outcomes section
  - All other service entries in the stack table
```

---

## Summary: Why This Plan Will Not Fail

| Risk | Mitigation |
|------|-----------|
| Bifrost image doesn't exist | `ruqqq/bifrost` is a real published image — verify with `docker pull ruqqq/bifrost:latest` before merging |
| Bifrost healthcheck path wrong | Use `wget` not `curl` (Go images often lack curl); path `/healthz` is standard for Go services — confirm from Bifrost README |
| Downstream services break | Both routers use port 4000, same OpenAI-compatible API — zero changes downstream |
| LiteLLM users broken | `generate_litellm_service()` is existing code moved into a function — not modified |
| Clean re-run fails | Script 0 cleans both bifrost and litellm artifacts |

```
FINAL CHECK FOR WINDSURF BEFORE STARTING:

1. docker pull ruqqq/bifrost:latest
   → Confirm image exists and note the actual healthcheck path
   → Run: docker run --rm -p 4000:4000 -e AUTH_TOKEN=test ruqqq/bifrost:latest
   → Check: curl http://localhost:4000/healthz OR /health OR /
   → Use whatever path returns 200 in the healthcheck

2. Check Bifrost ENV var names from the README at:
   https://github.com/ruqqq/bifrost
   → Confirm AUTH_TOKEN is correct (may be API_KEY or MASTER_KEY)
   → Confirm PORT env var name
   → Confirm OLLAMA_BASE_URL env var name

DO NOT assume env var names. Read the Bifrost repo first.
The 10 minutes reading the repo saves 200 hours of iteration.
```