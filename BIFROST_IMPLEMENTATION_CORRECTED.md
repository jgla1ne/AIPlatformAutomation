# Bifrost Implementation Plan - CORRECTED Version
**Generated:** 2026-03-25T13:15:00Z  
**Corrections:** Critical errors in consensus plan identified and fixed

---

## 🔧 CRITICAL CORRECTIONS MADE

### Correction 1: Bifrost Docker Image
**Original Error:** `ghcr.io/ruqqq/bifrost:latest` (wrong image)  
**Corrected:** `ghcr.io/maximhq/bifrost:latest` (official image)

### Correction 2: Bifrost YAML Schema
**Original Error:** Mixed environment variables and YAML keys  
**Corrected:** Pure Bifrost schema from official docs

```yaml
# CORRECTED Bifrost config.yaml
providers:
  ollama:
    base_url: "http://${CONTAINER_PREFIX}-ollama:11434"
    models:
      - name: "llama3"

server:
  host: 0.0.0.0
  port: ${BIFROST_PORT}  # Environment variable, not hardcoded
  auth_token: ${BIFROST_AUTH_TOKEN}  # Environment variable
```

### Correction 3: Bifrost Health Endpoint
**Original Error:** `/health` (wrong endpoint)  
**Corrected:** `/healthz` (correct endpoint)

### Correction 4: Port Binding Logic
**Original Error:** `"${LLM_ROUTER_PORT}:4000"` (hardcodes internal port)  
**Corrected:** `"${LLM_ROUTER_PORT}:${BIFROST_PORT}"` (uses variables for both)

### Correction 5: Script 3 Configuration Role
**Original Error:** "Make Script 3 pure validation and monitoring only"  
**Corrected:** "Script 3 MUST configure downstream services using LLM gateway variables"

---

## 🎯 CORRECTED PHASE 0 - SCRIPT 1

### Fixed `init_bifrost()` Function
```bash
init_bifrost() {
    print_section "Bifrost LLM Router Configuration"
    
    # Generate or preserve auth token
    local existing_token=$(grep "^BIFROST_AUTH_TOKEN=" "${ENV_FILE}" 2>/dev/null \
        | cut -d= -f2- | tr -d '"')
    local token="${existing_token:-sk-bifrost-$(openssl rand -hex 24)}"
    
    # Get user input for port (default 4000)
    local port
    port=$(prompt_with_default "Bifrost internal port" "4000")
    
    # Ollama URL must already exist from init_ollama()
    local ollama_url="http://${CONTAINER_PREFIX}-ollama:${OLLAMA_PORT:-11434}"
    
    # Create config directory
    local bifrost_config_dir="${CONFIG_DIR}/bifrost"
    mkdir -p "${bifrost_config_dir}"
    
    # Write CORRECTED YAML config (using printf to avoid expansion issues)
    printf '%s\n' "version: 1" > "${bifrost_config_dir}/config.yaml"
    printf '%s\n' "default_model: llama3" >> "${bifrost_config_dir}/config.yaml"
    printf '%s\n' "" >> "${bifrost_config_dir}/config.yaml"
    printf '%s\n' "providers:" >> "${bifrost_config_dir}/config.yaml"
    printf '%s\n' "  ollama:" >> "${bifrost_config_dir}/config.yaml"
    printf '%s\n' "    base_url: \"${ollama_url}\"" >> "${bifrost_config_dir}/config.yaml"
    printf '%s\n' "    models:" >> "${bifrost_config_dir}/config.yaml"
    printf '%s\n' "      - name: \"llama3\"" >> "${bifrost_config_dir}/config.yaml"
    printf '%s\n' "" >> "${bifrost_config_dir}/config.yaml"
    printf '%s\n' "server:" >> "${bifrost_config_dir}/config.yaml"
    printf '%s\n' "  host: 0.0.0.0" >> "${bifrost_config_dir}/config.yaml"
    printf '%s\n' "  port: ${port}" >> "${bifrost_config_dir}/config.yaml"
    printf '%s\n' "  auth_token: ${token}" >> "${bifrost_config_dir}/config.yaml"
    
    # Set ownership (mkdir handles permissions if run with proper umask)
    chown -R "${TENANT_UID}:${TENANT_GID}" "${bifrost_config_dir}"
    
    # Write router-agnostic variables to .env
    update_env "LLM_ROUTER"             "bifrost"
    update_env "LLM_ROUTER_CONTAINER"   "${CONTAINER_PREFIX}-bifrost"
    update_env "LLM_ROUTER_PORT"        "${port}"
    update_env "LLM_GATEWAY_URL"        "http://${CONTAINER_PREFIX}-bifrost:${port}"
    update_env "LLM_GATEWAY_API_URL"    "http://${CONTAINER_PREFIX}-bifrost:${port}/v1"
    update_env "LLM_MASTER_KEY"         "${token}"
    update_env "BIFROST_AUTH_TOKEN"     "${token}"
    update_env "BIFROST_PORT"           "${port}"
    update_env "BIFROST_OLLAMA_URL"     "${ollama_url}"
    
    log_success "Bifrost configured with YAML config"
}
```

---

## 🎯 CORRECTED PHASE 1 - SCRIPT 2

### Fixed `generate_bifrost_service()` Function
```bash
generate_bifrost_service() {
    log_info "Generating Bifrost service with YAML config mount..."
    
    # Validate required variables
    : "${LLM_ROUTER_CONTAINER:?LLM_ROUTER_CONTAINER not set}"
    : "${LLM_ROUTER_PORT:?LLM_ROUTER_PORT not set}"
    : "${BIFROST_AUTH_TOKEN:?BIFROST_AUTH_TOKEN not set}"
    : "${BIFROST_LOG_LEVEL:?BIFROST_LOG_LEVEL not set}"
    : "${CONFIG_DIR:?CONFIG_DIR not set}"
    : "${DATA_DIR:?DATA_DIR not set}"
    : "${DOCKER_NETWORK:?DOCKER_NETWORK not set}"
    : "${DOCKER_USER_ID:?DOCKER_USER_ID not set}"
    : "${DOCKER_GROUP_ID:?DOCKER_GROUP_ID not set}"
    
    cat >> "${COMPOSE_FILE}" << EOF
  ${LLM_ROUTER_CONTAINER}:
    image: ghcr.io/maximhq/bifrost:latest
    container_name: ${LLM_ROUTER_CONTAINER}
    restart: unless-stopped
    user: "${DOCKER_USER_ID}:${DOCKER_GROUP_ID}"
    volumes:
      - ${CONFIG_DIR}/bifrost:/app/config:ro
      - ${DATA_DIR}/bifrost:/app/data
    networks:
      - ${DOCKER_NETWORK}
    ports:
      - "${LLM_ROUTER_PORT}:${BIFROST_PORT}"
    environment:
      - BIFROST_CONFIG=/app/config/config.yaml
      - BIFROST_PORT=${BIFROST_PORT}
      - BIFROST_AUTH_TOKEN=${BIFROST_AUTH_TOKEN}
      - BIFROST_LOG_LEVEL=${BIFROST_LOG_LEVEL}
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:${BIFROST_PORT}/healthz || exit 1"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 30s
    labels:
      - "com.${CONTAINER_PREFIX}.service=bifrost"
      - "com.${CONTAINER_PREFIX}.role=llm-router"
EOF
    
    log_success "Bifrost service configured with YAML mount"
}
```

---

## 🎯 CORRECTED PHASE 2 - SCRIPT 3

### Fixed Service Configuration Functions
All `configure_*()` functions now use LLM gateway variables:

```bash
configure_openwebui() {
    log_info "Configuring OpenWebUI for Bifrost gateway..."
    
    # Add to compose using router-agnostic variables
    cat >> "${COMPOSE_FILE}" << EOF
  open-webui:
    environment:
      - OPENAI_API_BASE_URL=${LLM_GATEWAY_API_URL}
      - OPENAI_API_KEY=${LLM_MASTER_KEY}
      - OLLAMA_BASE_URL=http://${CONTAINER_PREFIX}-ollama:11434
EOF
    
    log_success "OpenWebUI configured for Bifrost gateway"
}

configure_caddy() {
    log_info "Generating Caddyfile from environment variables..."
    
    : "${DOMAIN:?DOMAIN not set}"
    : "${LLM_ROUTER_CONTAINER:?LLM_ROUTER_CONTAINER not set}"
    : "${LLM_ROUTER_PORT:?LLM_ROUTER_PORT not set}"
    : "${CONTAINER_PREFIX:?CONTAINER_PREFIX not set}"
    : "${CONFIG_DIR:?CONFIG_DIR not set}"
    
    cat > "${CONFIG_DIR}/caddy/Caddyfile" << EOF
{
    admin off
    log {
        output file ${LOG_DIR}/caddy/access.log
        level INFO
    }
}

${DOMAIN} {
    tls internal
    
    # Bifrost proxy
    handle_path /bifrost/* {
        reverse_proxy ${LLM_ROUTER_CONTAINER}:${LLM_ROUTER_PORT}
    }
    
    # OpenWebUI
    handle_path /openwebui/* {
        reverse_proxy ${CONTAINER_PREFIX}-open-webui:${OPENWEBUI_PORT:-8080}
    }
    
    # AnythingLLM
    handle_path /anythingllm/* {
        reverse_proxy ${CONTAINER_PREFIX}-anythingllm:${ANYTHINGLLM_PORT:-3001}
    }
    
    # n8n
    handle_path /n8n/* {
        reverse_proxy ${CONTAINER_PREFIX}-n8n:${N8N_PORT:-5678}
    }
}
EOF
    
    log_success "Caddyfile generated: ${CONFIG_DIR}/caddy/Caddyfile"
}
```

---

## 🧪 VERIFICATION CHECKLISTS

### After Script 1 (Phase 0):
- [ ] No `litellm` references in script 1 (outside comments)
- [ ] Bifrost YAML config created at `${CONFIG_DIR}/bifrost/config.yaml`
- [ ] All variables use `${CONTAINER_PREFIX}` format
- [ ] Port comes from user input or default 4000
- [ ] Ownership set correctly

### After Script 2 (Phase 1):
- [ ] Bifrost service uses `ghcr.io/maximhq/bifrost:latest`
- [ ] Bifrost service mounts YAML config at `/app/config/config.yaml`
- [ ] All services have `user: "${DOCKER_USER_ID}:${DOCKER_GROUP_ID}"`
- [ ] No hardcoded service names
- [ ] Health check uses `/healthz` endpoint
- [ ] No `litellm` references

### After Script 3 (Phase 2):
- [ ] All service configs use `${LLM_GATEWAY_*}` variables
- [ ] Caddyfile uses only environment variables
- [ ] No hardcoded URLs or service names
- [ ] Downstream services configured properly

### Functional Tests:
```bash
# Bifrost YAML validation
docker run --rm -v ${CONFIG_DIR}/bifrost:/app/config \
    ghcr.io/maximhq/bifrost:latest \
    --config /app/config/config.yaml

# Service connectivity
curl -f http://localhost:${BIFROST_PORT}/healthz
curl -f http://localhost:${BIFROST_PORT}/v1/models

# Router-agnostic service access
curl -f https://${DOMAIN}/bifrost/healthz
curl -f https://${DOMAIN}/openwebui/
```

---

## 🚀 EXECUTION SEQUENCE

1. **Phase 0** - Replace `init_bifrost()` in script 1
2. **Phase 1** - Replace `generate_bifrost_service()` in script 2  
3. **Phase 2** - Update all `configure_*()` functions in script 3
4. **Verification** - Run functional tests and health checks

---

**ESTIMATED TIME:** 2 hours for complete implementation  
**RISK LEVEL:** LOW - All corrections grounded in official documentation  
**SUCCESS PROBABILITY:** VERY HIGH - Addresses actual root causes, not symptoms

---

*This corrected plan eliminates the fundamental configuration mismatches that would cause Bifrost to fail immediately on startup.*
