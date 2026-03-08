Analysis:

Your feedback reveals the core issue: the current script architecture is flawed because it splits the deployment (script-2) from the configuration (script-3). This contradicts the user's valid expectation of having a functional stack after the main deployment script runs. The README.md is outdated; it describes a process we must now fix.

Our new strategy will be to make script-2 the single source of truth for a fully operational deployment. script-3 will be repurposed for "Day 2" operations and advanced diagnostics, not critical-path setup.

Goal: Ensure that by the end of script-2, all core AI services are running, interconnected, and accessible via their final reverse-proxy URLs.

Problem: LiteLLM, the pivotal service, is left unconfigured, rendering the entire AI stack useless after script-2. This is the highest priority issue.
Solution: We will move the model-registration logic from script-3 into script-2, executing it immediately after the LiteLLM container becomes healthy. This aligns with the "Service auto-integration" principle.
File to Edit: scripts/2-deploy-services.sh Instruction:

Add a wait_for_service helper function.
After the docker compose up -d command, add a new block to wait for and configure LiteLLM.
# Add this helper function at the top of script-2
wait_for_service() {
    local name=$1 url=$2 max=${3:-120}
    log "INFO" "Waiting for ${name} at ${url}..."
    for ((i=0; i<max; i+=5)); do
        if curl -sf --max-time 5 "${url}" &>/dev/null; then
            ok "${name} is responding."
            return 0
        fi
        sleep 5
    done
    fail "${name} did not respond within ${max}s. Deployment failed."
}

# --- In main() function of script-2 ---
# ... (docker-compose.yml generation) ...

log "INFO" "Deploying stack '${COMPOSE_PROJECT_NAME}'..."
docker compose up -d

# --- NEW: Post-Startup Service Interconnection ---
ok "Stack deployed. Proceeding with critical service configuration..."

# 1. Configure LiteLLM (MOVED FROM SCRIPT-3)
wait_for_service "LiteLLM" "http://localhost:${LITELLM_PORT}"
log "INFO" "Registering models with LiteLLM..."
# Move the 'curl' loops for model registration from script-3 to a new
# function here in script-2, e.g., configure_litellm_models
configure_litellm_models

# ... (rest of main function) ...



Problem: The stub Caddyfile causes the "Caddy is working!" issue. Signal and other services are not proxied.
Solution: We will generate the final, production-ready Caddyfile in script-2 before docker compose up. This file must include reverse proxy rules for all external services, including Signal.
File to Edit: scripts/2-deploy-services.sh Instruction:

Move the write_production_caddyfile function from script-3 into script-2.
Ensure it includes a block for every service, including the user's specific request for Signal.
# In the new write_production_caddyfile function in script-2

# ... (add rules for n8n, dify, anythingllm etc.) ...

# Ensure Signal API is included as requested
if [[ "${ENABLE_SIGNAL:-false}" == "true" ]]; then
    caddyfile_content+="
signal.${TENANT_DOMAIN} {
    reverse_proxy signal-api:${SIGNAL_PORT:-8080}
}
"
fi

# ... call this function BEFORE docker-compose.yml generation ...



Goal: Repurpose script-3 as a powerful diagnostics and Day-2 operations tool, and make deployment logs cleaner.

Problem: The user is seeing excessive, unhelpful download logs.
Solution: Silence the noise and provide a clean summary.
File to Edit: scripts/2-deploy-services.sh Instruction:

Use docker compose pull --quiet to hide download progress.
Add a print_final_summary function to be called at the very end of the script. This function must show all external URLs and the Tailscale IP for OpenClaw.
# Add this function to script-2, to be called last.
print_final_summary() {
    print_section "✅ Deployment Complete: Access Summary"

    # Print all reverse-proxied URLs from .env
    log "INFO" "External Service URLs:"
    [[ "${ENABLE_N8N:-false}" == "true" ]] && echo "  - n8n:          https://n8n.${TENANT_DOMAIN}"
    [[ "${ENABLE_DIFY:-false}" == "true" ]] && echo "  - Dify:         https://dify.${TENANT_DOMAIN}"
    [[ "${ENABLE_ANYTHINGLLM:-false}" == "true" ]] && echo "  - AnythingLLM:  https://anythingllm.${TENANT_DOMAIN}"
    [[ "${ENABLE_SIGNAL:-false}" == "true" ]] && echo "  - Signal API:   https://signal.${TENANT_DOMAIN}"
    # ... add all other proxied services ...

    # Fulfill the user's request to show the Tailscale URL for OpenClaw
    if [[ "${ENABLE_TAILSCALE:-false}" == "true" && "${ENABLE_OPENCLAW:-false}" == "true" ]]; then
        log "INFO" "Fetching Tailscale IP for OpenClaw..."
        local ts_ip
        # Use docker inspect to find the Tailscale IP of the OpenClaw container
        ts_ip=$(docker inspect "${COMPOSE_PROJECT_NAME}-openclaw-1" | grep -oP '\"TailscaleIPs\": \[\"\\K[^\"]+')
        if [[ -n "$ts_ip" ]]; then
            echo "  - OpenClaw (via Tailscale): https://${ts_ip}:${OPENCLAW_PORT:-18789}"
        else
            warn "Could not determine Tailscale IP for OpenClaw. Check the container logs."
        fi
    fi
}



Problem: Debugging is difficult. There's no way to see specific logs or increase verbosity.
Solution: Convert script-3 into the interactive diagnostics tool the user requested.
File to Edit: scripts/3-configure-services.sh Instruction: Gut the old configuration logic and replace it with the interactive menu system.

# The new main function for script-3
main() {
    # ... (load env, print header) ...

    # NEW: The script's main purpose is now this interactive menu
    interactive_diagnostics_menu

    ok "SCRIPT 3 COMPLETED."
}

# The menu function (as proposed before)
interactive_diagnostics_menu() {
    PS3="Select a diagnostic action: "
    options=(
        "View Docker Logs for a Service"
        "Set Proxy Log Level (Caddy/Nginx)"
        "Run Full Health Check"
        "Configure Rclone/gdrive (Day 2 Ops)"
        "Quit"
    )
    # ... implement the select case for this menu ...
}



By executing this plan, you will perfectly align the platform's architecture with the user's stated needs, resolving all their current issues and delivering the robust, enterprise-grade experience defined in the README.md's principles.