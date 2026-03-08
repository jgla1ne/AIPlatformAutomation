The platform is on the verge of being 100% ready. The user and I are now in full agreement on the final architectural constraint: some services require specific non-root UIDs, and the filesystem must be prepared for them. This is not a violation of our "Nothing as root" principle; it is an acknowledgment of third-party image requirements.

The current script-1 contains a critical flaw that breaks this principle by indiscriminately setting all ownership to the tenant user. This action is the sole remaining blocker to a fully successful deployment.

This plan provides the exact, copy-pasteable code to fix this flaw.

The Problem: The function write_env_and_set_ownership in script-1 uses a single chown -R "${TENANT_UID}:${TENANT_GID}" command on the entire tenant directory. This incorrectly overwrites the required ownership for services like Grafana and n8n, guaranteeing they will fail to start in script-2.

The Solution: We must replace this single command with a more intelligent, two-stage ownership function that correctly applies the "Pragmatic Exception Pattern."

File to Edit: scripts/1-setup-system.sh

Instruction:

Delete the existing chown -R line from the write_env_and_set_ownership function.
Create a new, dedicated function called apply_final_ownership that contains the correct logic.
Call this new function at the end of main().
Add this new function to scripts/1-setup-system.sh. This is the most critical piece of code in the entire plan.

# =============================================================================
# NEW FUNCTION: Apply Final Ownership with Pragmatic Exceptions
# =============================================================================
apply_final_ownership() {
    print_section "Applying Final Ownership Structure"

    # --- Stage 1: Set Base Ownership ---
    # Set the entire directory to the tenant's ownership first. This is the default.
    log "Setting base ownership for tenant ${TENANT_UID}:${TENANT_GID} on ${DATA_ROOT}..."
    if ! chown -R "${TENANT_UID}:${TENANT_GID}" "${DATA_ROOT}"; then
        fail "Failed to set base recursive ownership on ${DATA_ROOT}."
    fi
    ok "Base ownership applied."

    # --- Stage 2: Apply Pragmatic Exceptions ---
    # Now, override ownership for specific directories that run as their own user.
    # This correctly implements the learning from README.md (Line 537).
    log "Applying ownership exceptions for specific services..."

    # Exception for n8n (typically runs as user 1000)
    if [[ -d "${DATA_ROOT}/n8n" && -n "${N8N_UID:-}" ]]; then
        chown -R "${N8N_UID}:${N8N_UID}" "${DATA_ROOT}/n8n"
        ok "Set ownership for 'n8n' to ${N8N_UID}:${N8N_UID}."
    fi

    # Exception for Grafana (runs as user 472)
    if [[ -d "${DATA_ROOT}/grafana" && -n "${GRAFANA_UID:-}" ]]; then
        chown -R "${GRAFANA_UID}:${GRAFANA_UID}" "${DATA_ROOT}/grafana"
        ok "Set ownership for 'grafana' to ${GRAFANA_UID}:${GRAFANA_UID}."
    fi
    
    # Exception for Prometheus (runs as user 65534)
    if [[ -d "${DATA_ROOT}/prometheus-data" && -n "${PROMETHEUS_UID:-}" ]]; then
        chown -R "${PROMETHEUS_UID}:${PROMETHEUS_UID}" "${DATA_ROOT}/prometheus-data"
        ok "Set ownership for 'prometheus' to ${PROMETHEUS_UID}:${PROMETHEUS_UID}."
    fi
    
    # NOTE: Add any other service exceptions here if they are discovered.

    # --- Stage 3: Secure Permissions ---
    log "Setting final secure permissions on tenant root and .env file..."
    chmod 750 "${DATA_ROOT}"
    chmod 640 "${ENV_FILE}"
    ok "Secure permissions set."

    ok "Final ownership structure is correct and production-ready."
}



Modify the main() function in scripts/1-setup-system.sh to call this new function at the correct time.

# --- In the main() function of script-1 ---

# ... (all data collection, summary, and confirmation logic) ...

# 1. Create all directories
create_directory_scaffold

# 2. Write the .env file (DO NOT SET OWNERSHIP HERE ANYMORE)
# The old write_env_and_set_ownership function is now just write_env_file
write_env_file

# 3. Write supplementary configs like the Caddyfile
write_caddyfile

# 4. Apply the final, correct ownership structure (NEW FINAL STEP)
apply_final_ownership

# --- Final Output ---
offer_next_step



Implement the Fix: Apply the exact code changes to scripts/1-setup-system.sh as described above.
Re-Run from Scratch: Execute the full deployment sequence: script-0 -> script-1.
Verification: After script-1 completes, I will manually verify the ownership of the n8n and grafana directories to confirm they are correct before allowing the analysis of script-2 to proceed.
Once this foundational fix is implemented and verified, I will resume the full analysis of the remaining scripts to confirm the platform's 100% readiness.