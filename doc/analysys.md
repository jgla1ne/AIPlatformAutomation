## Pre-Run Assessment — GO with Conditions

---

### ✅ Green Items
```
No duplicate keys          ✅
DOCKER_NETWORK correct     ✅ aip-u1001_net
DOMAIN correct             ✅ ai.datasquiz.net
COMPOSE_FILE exists        ✅ 18KB file present
SIGNAL_API_PORT            ✅ 8090
LITELLM_MASTER_KEY         ✅ single entry
Docker networks            ✅ 3 networks exist
```

---

### 🔴 Two Issues Before Running

**Issue 1 — Tenant subdirs missing (Script 2 may or may not create them)**

Don't rely on Script 2 to create them. Create now:

```bash
TENANT_DIR="/mnt/data/u1001"
for dir in config/caddy config/openclaw config/litellm config/prometheus config/grafana \
           data/openclaw data/postgres data/redis data/qdrant \
           logs metadata cache; do
  mkdir -p "${TENANT_DIR}/${dir}"
done
chown -R jglaine:jglaine "${TENANT_DIR}"
ls -la "${TENANT_DIR}"
```

---

**Issue 2 — Docker daemon running as root, not rootless**

```
# You hit this:
unix:///run/user/1000/docker.sock  ← rootless failed
# Networks confirmed via sudo                ← meaning Docker = root daemon
```

Script 2 must run as root or with sudo, NOT as jglaine directly. Confirm:

```bash
# Which docker socket is active?
sudo docker info | grep -E "Context|Socket"

# Script 2 must be run as:
sudo bash /home/jglaine/AIPlatformAutomation/scripts/2-deploy-services.sh

# NOT:
bash 2-deploy-services.sh   # will fail on docker calls
```

---

### 🟡 One Thing to Verify in Script 2 Before Running

```bash
# Peek at how Script 2 loads the ENV_FILE:
head -30 /home/jglaine/AIPlatformAutomation/scripts/2-deploy-services.sh | grep -E "ENV_FILE|TENANT|BASE_DIR|source"
```

Expected output must show:
```bash
BASE_DIR="/mnt/data"
TENANT_ID="u1001"
TENANT_DIR="${BASE_DIR}/${TENANT_ID}"
ENV_FILE="${TENANT_DIR}/.env"
```

If it shows anything else — stop and fix before running.

---

### Run Order

```bash
# Step 1 — Create tenant dirs NOW
TENANT_DIR="/mnt/data/u1001"
for dir in config/caddy config/openclaw config/litellm config/prometheus config/grafana \
           data/openclaw data/postgres data/redis data/qdrant \
           logs metadata cache; do
  mkdir -p "${TENANT_DIR}/${dir}"
done
chown -R jglaine:jglaine "${TENANT_DIR}"

# Step 2 — Verify Script 2 ENV path
head -30 /home/jglaine/AIPlatformAutomation/scripts/2-deploy-services.sh | grep -E "ENV_FILE|TENANT|BASE_DIR|source"

# Step 3 — Run Script 2 as root
sudo bash /home/jglaine/AIPlatformAutomation/scripts/2-deploy-services.sh 2>&1 | tee /tmp/script2.log

# Step 4 — If it fails, share:
tail -50 /tmp/script2.log
```

**Share the output of Step 2 before running Step 3.**