The proposed "High-Level Fix Strategy" is conceptually right but suggests "quick win" code changes that violate your project's core architectural principles. Applying chown commands in script-2 or removing user: directives are bandage fixes that create technical debt.

The architecturally-pure solution is to handle these known exceptions during the environment setup (script-1), ensuring script-2 remains a pure deployer. This document provides Windsurf with the precise, compliant code snippets to achieve 100% stability.

Analysis:

The logs confirm all 7 failing services are experiencing a "UID Mismatch." Our docker-compose.yml correctly attempts to run them as the tenant user (user: "${TENANT_UID}:${TENANT_GID}"), but these specific images ignore that directive and run as their own internal, non-root user. They then crash because they lack permission to write to their data directories, which are owned by the tenant user.

The Solution:

The solution is to embrace the "Pragmatic Exception Pattern" (precedent: README.md, Line 484, PostgreSQL fix) at the correct architectural stage: environment setup (script-1). We will make these UID exceptions configurable in the .env file and use them to set the correct directory ownership from the moment of creation.

This is the core of the solution. We perfect the environment so that script-2 can deploy to it flawlessly.

This makes the exceptions manageable configuration, not hardcoded script logic.

File to Edit: scripts/1-setup-tenant.sh Instruction: In the .env generation block (cat > "${ENV_FILE_PATH}" << EOF...), add the following variables.

# --- Service Ownership UIDs (The "Pragmatic Exception Pattern") ---
# Per README.md, some services ignore the 'user:' directive and require
# their internal UID to own their data directory. These are defined here as
# configurable variables to avoid hardcoding in scripts.
TENANT_UID=$(id -u "${TENANT_ID}")
TENANT_GID=$(id -g "${TENANT_ID}")
POSTGRES_UID=70
PROMETHEUS_UID=65534
GRAFANA_UID=472
N8N_UID=1000
QDRANT_UID=1000
REDIS_UID=999 # Standard redis user
OPENWEBUI_UID=1000
ANYTHINGLLM_UID=1000
OLLAMA_UID=1001
FLOWISE_UID=1000



This new function in script-1 creates every directory with the correct final ownership from the start.

File to Edit: scripts/1-setup-tenant.sh Instruction: Replace your existing directory creation logic with this comprehensive block.

# =============================================================================
# STEP 1: PRE-CREATE ALL DIRECTORIES WITH ARCHITECTURALLY-CORRECT OWNERSHIP
# =============================================================================
log "Creating all service directories with architecturally-compliant ownership..."

# Source the .env file we just created to access the UID variables
set -a; source "${ENV_FILE_PATH}"; set +a

# This function creates a directory and sets ownership based on the .env file.
# It defaults to the TENANT_UID but uses the specific service UID if that variable exists.
create_and_own() {
    local dir_path="$1"
    local service_uid_var_name="${2:-TENANT}_UID" # e.g., "QDRANT_UID" or "TENANT_UID"
    local owner_uid="${!service_uid_var_name:-$TENANT_UID}" # Use specific UID, fallback to tenant
    
    mkdir -p "${TENANT_DIR}/${dir_path}"
    chown -R "${owner_uid}:${owner_uid}" "${TENANT_DIR}/${dir_path}"
    ok "Created '${dir_path}' and set owner to '${owner_uid}'"
}

# --- Create all possible directories with the correct owner from the start ---
create_and_own "logs"; create_and_own "caddy-data"; create_and_own "litellm";
create_and_own "authentik/media"; create_and_own "authentik/custom-templates";

# Use the specific UID variables for non-compliant services
create_and_own "postgres"    "POSTGRES"; create_and_own "prometheus-data" "PROMETHEUS";
create_and_own "grafana/provisioning/datasources" "GRAFANA"; create_and_own "n8n" "N8N";
create_and_own "qdrant"      "QDRANT";   create_and_own "redis" "REDIS";
create_and_own "openwebui"   "OPENWEBUI";create_and_own "anythingllm" "ANYTHINGLLM";
create_and_own "flowise"     "FLOWISE";  create_and_own "ollama" "OLLAMA";

ok "All service directories created with correct, final ownership."



This restores script-2 to its pure role as a deployer, removing all bandage fixes.

File to Edit: scripts/2-deploy-services.sh Instruction: Find and delete the entire chown block (e.g., Applying 'Prometheus Pattern' for directory ownership...). This script must not perform any chown operations.

The docker-compose.yml should still specify the user: directive where appropriate, asserting our security baseline. The directory permissions set in script-1 will handle the reality of non-compliant images.

File to Edit: scripts/2-deploy-services.sh Instruction: When generating the service definitions, ensure they look like this:

# For a compliant service that will obey the directive:
  litellm:
    # ...
    user: "${TENANT_UID}:${TENANT_GID}"
    # ...

# For Postgres, which has a well-known user:
  postgres:
    # ...
    user: "${POSTGRES_UID:-70}:${POSTGRES_UID:-70}" # Use variable, with fallback
    # ...

# For Ollama, which ignores the directive (but we state our intent anyway):
  ollama:
    # ...
    # The 'user' directive is best practice, even if this image ignores it.
    # The directory permission set in script-1 is what actually fixes the issue.
    user: "${TENANT_UID}:${TENANT_GID}"
    # ...


This table explicitly maps each service failure to the architecturally-pure fix.

Service	Symptom (Error from Log)	Architecturally-Compliant Solution
Ollama	Error: could not create directory mkdir /.ollama: permission denied	Action 1.2's create_and_own "ollama" "OLLAMA" uses the OLLAMA_UID=1001 variable (from Action 1.1) to set 1001:1001 ownership on ./ollama during setup in script-1.
Postgres	initdb: error: could not change permissions... Operation not permitted	Action 1.2's create_and_own "postgres" "POSTGRES" uses POSTGRES_UID=70 (from Action 1.1) to set 70:70 ownership on ./postgres in script-1. Action 2.2 sets the user: directive in the compose file to match.
Qdrant	...Failed to write file: Permission denied at path "/qdrant/./storage/.atomicwrite"	Action 1.2's create_and_own "qdrant" "QDRANT" uses QDRANT_UID=1000 (from Action 1.1) to set 1000:1000 ownership on ./qdrant in script-1.
AnythingLLM	Permission issues (similar to others)	Action 1.2's create_and_own "anythingllm" "ANYTHINGLLM" uses ANYTHINGLLM_UID=1000 (from Action 1.1) to set 1000:1000 ownership on ./anythingllm in script-1.
Flowise	Permission denied creating directories	Action 1.2's create_and_own "flowise" "FLOWISE" uses FLOWISE_UID=1000 (from Action 1.1) to set 1000:1000 ownership on ./flowise in script-1.
Redis	Permission denied accessing data directory	Action 1.2's create_and_own "redis" "REDIS" uses REDIS_UID=999 (from Action 1.1) to set 999:999 ownership on ./redis in script-1.