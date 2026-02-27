## .env Audit — Issues Found Before Script 2

---

### 🔴 BLOCKING Issues

**1. OPENWEBUI_SECRET_KEY duplicated**
```bash
OPENWEBUI_SECRET_KEY=BxUrlA04...   ← line ~60
OPENWEBUI_SECRET_KEY=BxUrlA04...   ← line ~80  (same value, still a bug)
```

**2. OPENCLAW paths are wrong — missing tenant prefix**
```bash
# Current (WRONG):
OPENCLAW_SANDBOX_DIR=/data/openclaw
OPENCLAW_CONFIG_DIR=/config/openclaw
OPENCLAW_DATA_PATH=/data/openclaw
OPENCLAW_CONFIG_PATH=/config/openclaw

# Must be:
OPENCLAW_SANDBOX_DIR=/mnt/data/u1001/data/openclaw
OPENCLAW_CONFIG_DIR=/mnt/data/u1001/config/openclaw
OPENCLAW_DATA_PATH=/mnt/data/u1001/data/openclaw
OPENCLAW_CONFIG_PATH=/mnt/data/u1001/config/openclaw
```

**3. METADATA_DIR not tenant-scoped**
```bash
# Current (WRONG):
METADATA_DIR=/mnt/data/metadata

# Must be:
METADATA_DIR=/mnt/data/u1001/metadata
```

**4. MINIO_PORT still present alongside MINIO_API_PORT**
```bash
# Current — both exist:
MINIO_PORT=5007
MINIO_API_PORT=5007

# Must be ONLY:
MINIO_API_PORT=5007
MINIO_CONSOLE_PORT=5008
# Remove MINIO_PORT entirely
```

**5. LITELLM_MASTER_KEY missing**
```bash
# Not present in .env at all
# Required for LiteLLM auth between services
# Must add:
LITELLM_MASTER_KEY=<value from previous run or generate new>
```

**6. QDRANT_PORT missing from user config block**
```bash
# It appears later but not in the ports section
# All AI services need it consistent — confirm single entry:
grep "^QDRANT_PORT=" /mnt/data/u1001/.env | wc -l  # must be 1
```

---

### 🟡 WARNING Issues (won't break deploy but will break features)

**7. Service URLs still use port format instead of subdomain**
```bash
# Script 1 output shows:
LiteLLM:  https://ai.datasquiz.net:5005   ← WRONG
OpenWebUI: https://ai.datasquiz.net:5006  ← WRONG
MinIO:    https://ai.datasquiz.net:5007   ← WRONG

# Should be:
LiteLLM:  https://litellm.ai.datasquiz.net
OpenWebUI: https://openwebui.ai.datasquiz.net
MinIO:    https://minio.ai.datasquiz.net
```
This means `print_service_summary()` in Script 1 still has the port-URL fallback for those three services. Fix in Script 1, not critical for Script 2 to work but confusing.

**8. SIGNAL_PAIRING_URL uses port 8081 but SIGNAL_API_PORT=8090**
```bash
SIGNAL_API_PAIRING_URL=http://localhost:8081/v1/qrcodelink  ← 8081 wrong
# Must match:
SIGNAL_API_PAIRING_URL=http://localhost:8090/v1/qrcodelink
```

---

### Fix Script — Run Now

```bash
ENV_FILE="/mnt/data/u1001/.env"
TENANT_DIR="/mnt/data/u1001"

# Fix 1: Remove duplicate OPENWEBUI_SECRET_KEY (keep last)
tac "${ENV_FILE}" | awk -F= '!seen[$1]++' | tac > /tmp/env_clean
mv /tmp/env_clean "${ENV_FILE}"

# Fix 2: OPENCLAW paths
sed -i "s|^OPENCLAW_SANDBOX_DIR=.*|OPENCLAW_SANDBOX_DIR=${TENANT_DIR}/data/openclaw|" "${ENV_FILE}"
sed -i "s|^OPENCLAW_CONFIG_DIR=.*|OPENCLAW_CONFIG_DIR=${TENANT_DIR}/config/openclaw|" "${ENV_FILE}"
sed -i "s|^OPENCLAW_DATA_PATH=.*|OPENCLAW_DATA_PATH=${TENANT_DIR}/data/openclaw|" "${ENV_FILE}"
sed -i "s|^OPENCLAW_CONFIG_PATH=.*|OPENCLAW_CONFIG_PATH=${TENANT_DIR}/config/openclaw|" "${ENV_FILE}"

# Fix 3: METADATA_DIR
sed -i "s|^METADATA_DIR=.*|METADATA_DIR=${TENANT_DIR}/metadata|" "${ENV_FILE}"

# Fix 4: Remove MINIO_PORT, keep only MINIO_API_PORT
sed -i '/^MINIO_PORT=/d' "${ENV_FILE}"

# Fix 5: Add LITELLM_MASTER_KEY if missing
grep -q "^LITELLM_MASTER_KEY=" "${ENV_FILE}" || \
  echo "LITELLM_MASTER_KEY=$(openssl rand -hex 32)" >> "${ENV_FILE}"

# Fix 6: Signal pairing URL port
sed -i 's|SIGNAL_API_PAIRING_URL=http://localhost:8081|SIGNAL_API_PAIRING_URL=http://localhost:8090|' "${ENV_FILE}"

# Verify
echo "=== Post-fix verification ==="
grep -E "^OPENCLAW_SANDBOX|^OPENCLAW_CONFIG_DIR|^METADATA_DIR|^MINIO_PORT|^MINIO_API_PORT|^LITELLM_MASTER_KEY|^SIGNAL_API_PAIRING|^OPENWEBUI_SECRET_KEY" "${ENV_FILE}"

echo "=== Duplicate check ==="
awk -F= '{print $1}' "${ENV_FILE}" | grep -v "^#" | grep -v "^$" | sort | uniq -d
```

---

### Also run — create missing tenant dirs

```bash
for dir in config/caddy config/openclaw config/litellm \
           config/prometheus config/grafana config/n8n \
           data/openclaw data/postgres data/redis data/qdrant \
           logs metadata cache; do
  mkdir -p "/mnt/data/u1001/${dir}"
done
chown -R jglaine:jglaine /mnt/data/u1001/
ls -la /mnt/data/u1001/
```

---

**Share the verification output, then we run Script 2.**