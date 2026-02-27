## Three Issues — Prioritize in Order

---

### Issue 1 — Volume Name Double-Prefixed (cosmetic but wrong)
```
Volume aip-u1001_aip-u1001_postgres_data Creating
```
Docker compose is prepending `aip-u1001_` to `${PG_VOLUME}` which is already `aip-u1001_postgres_data`.

**Fix in docker-compose.yml — top-level volumes block:**
```yaml
# Current (WRONG):
volumes:
  ${PG_VOLUME}:
  
# Fix — use short names, let compose prefix them:
volumes:
  postgres_data:
  redis_data:
  qdrant_data:
```
Then update all service volume references from `${PG_VOLUME}` to `postgres_data`.

**OR** keep the env vars but mark external:
```yaml
volumes:
  aip-u1001_postgres_data:
    external: true
  aip-u1001_redis_data:
    external: true
  aip-u1001_qdrant_data:
    external: true
```

---

### Issue 2 — BLOCKING: Wrong compose file path for Redis layer
```
open /mnt/data/ai-platform/deployment/stack/docker-compose.yml: no such file or directory
```
Script 2 has a **hardcoded old path** for the Redis deploy call. It's not using `${COMPOSE_FILE}`.

```bash
# Find the bad line in Script 2:
grep -n "ai-platform/deployment" /home/jglaine/AIPlatformAutomation/scripts/2-deploy-services.sh
grep -n "docker compose" /home/jglaine/AIPlatformAutomation/scripts/2-deploy-services.sh | head -30
```

Every `docker compose` call in Script 2 must use:
```bash
docker compose \
  --project-name "${COMPOSE_PROJECT_NAME}" \
  --env-file "${ENV_FILE}" \
  -f "${COMPOSE_FILE}" \
  ...
```

Not a hardcoded path.

---

### Issue 3 — TENANT_DIR and TAILSCALE_EXTRA_ARGS not exported

```bash
# Add immediately after source "${ENV_FILE}" in Script 2:
export TENANT_DIR="/mnt/data/${TENANT_ID}"
export TAILSCALE_EXTRA_ARGS="${TAILSCALE_EXTRA_ARGS:-}"
```

---

### Immediate Actions

```bash
# 1 — Find the hardcoded path:
grep -n "ai-platform/deployment\|ai-platform/stack" \
  /home/jglaine/AIPlatformAutomation/scripts/2-deploy-services.sh

# 2 — Find ALL docker compose calls to audit:
grep -n "docker compose\|docker-compose" \
  /home/jglaine/AIPlatformAutomation/scripts/2-deploy-services.sh
```

**Share that output — I'll write the exact sed fixes for every bad line.**