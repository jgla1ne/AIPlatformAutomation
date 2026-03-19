The Blueprint: Fixing the LiteLLM + Postgres Architecture
1. Why Windsurf Failed (The Root Causes)
Windsurf got stuck in a loop because it missed three critical Docker/Database concepts:

The Startup Race Condition: LiteLLM boots up fast and immediately tries to connect to Postgres via Prisma. If Postgres is still initializing (which takes several seconds), Prisma throws a fatal error and LiteLLM crashes. Windsurf tried to fix the crash by removing the DB entirely, rather than delaying LiteLLM's startup.
Docker Network Resolution: The DATABASE_URL in LiteLLM must point to the Docker service name (e.g., postgres or db), not localhost or 127.0.0.1.
Database Initialization: LiteLLM needs the database to exist before it runs its internal Prisma migrations on boot.

2. Phase 1: The Database Layer (Postgres)
You must re-introduce the Postgres container in your deployment scripts (likely via Docker Compose or docker run inside 2-deploy-services.sh).

Requirement: Add a Docker Healthcheck to the Postgres container. This is non-negotiable. 
Action for Windsurf: Configure the Postgres container to run pg_isready -U <user> -d <dbname>.
Volumes: Ensure Postgres data is persisted to a Docker volume so keys survive restarts.

3. Phase 2: The LiteLLM Layer
LiteLLM must be configured to wait for Postgres and connect properly.

Environment Variables:
DATABASE_URL=postgresql://<user>:<password>@postgres:5432/litellm (Ensure postgres matches the exact container name).
LITELLM_MASTER_KEY=sk-your-master-key (Must be set to bootstrap the database).
STORE_MODEL_IN_DB=True


Dependency Constraint: In Docker Compose (or deployment script equivalent), LiteLLM must have a depends_on block linking to the Postgres container with condition: service_healthy. This ensures LiteLLM does not attempt to start until pg_isready returns true.

4. Phase 3: The Dependent Services (AnythingLLM & OpenWebUI)
These services are failing because they are looking for a LiteLLM endpoint that doesn't exist or is crashing.

Network Integration: Ensure OpenWebUI and AnythingLLM are on the exact same Docker network as LiteLLM.
Environment Variables: 
Their OPENAI_API_BASE_URL (or equivalent) must point to the internal Docker network URL: http://litellm:4000/v1 (assuming litellm is the container name and 4000 is the port).
Provide them with the LITELLM_MASTER_KEY defined in Phase 2 as their API key.


Startup Order: Just like LiteLLM depends on Postgres, OpenWebUI and AnythingLLM should ideally have a dependency or retry mechanism waiting for LiteLLM.

5. Phase 4: Fixing Ingress & Routing (openclaw.ai.datadwuiz.net)
Currently, openclaw.ai.datadwuiz.net is resolving to codeserv. This is a reverse proxy configuration error (Traefik/Nginx/Caddy).

The Fix: Windsurf needs to audit the reverse proxy labels or configuration files in 3-configure-services.sh. 
Diagnosis: codeserv likely has a wildcard Host rule, an overlapping Hostname, or the exact same Hostname assigned to it as the intended AI frontend. 
Action for Windsurf: Explicitly define the routing rule for openclaw.ai.datadwuiz.net to point to the OpenWebUI container port (e.g., 8080) and ensure codeserv is strictly isolated to its own subdomain (e.g., code.ai.datadwuiz.net).


Instructions for Windsurf's Next Steps:

Do not write placeholder code. 
Modify scripts/2-deploy-services.sh to inject the Postgres healthcheck and link it to LiteLLM's depends_on.
Re-add the DATABASE_URL to LiteLLM's environment file generation.
Modify scripts/3-configure-services.sh to fix the reverse proxy routing rules, ensuring openclaw points to OpenWebUI and absolutely nothing points to codeserv unless explicitly intended for the IDE/Code server.
Verify that all services share a common Docker network (ai-network).