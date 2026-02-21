Let me fetch all three scripts from the repository.

**Script 0:**
https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/0-pre-setup.sh

**Script 1:**
https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/1-setup-system.sh

**Script 2:**
https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/2-deploy-services.sh

---

# Script Analysis: 0, 1, and 2

---

## Script 0 — `0-pre-setup.sh`

### What It Does
- Installs system dependencies
- Configures Docker
- Sets up AppArmor baseline
- Creates stack user

### ✅ Correct
```bash
# Checks for root
# Installs docker, apparmor, ss (iproute2) — correct toolchain
# Creates docker group if missing
```

### ❌ Critical Issues

**Issue 0-1: Hardcoded UID/GID — defeats parameterization**
```bash
# Windsurf wrote:
useradd -m -u 1000 -g 1000 -s /bin/bash aiplatform
groupadd -g 1000 aiplatform

# Problem: If STACK_USER_UID=2000 for User B,
# Script 0 already created UID 1000 as "aiplatform"
# Script 1's STACK_USER_UID=2000 will conflict or be ignored
```

**Fix:**
```bash
# Script 0 should NOT create the stack user.
# Script 1 owns user creation because it knows STACK_USER_UID.
# Script 0 only installs packages and configures Docker daemon.
# Remove all useradd/groupadd from Script 0.
```

---

**Issue 0-2: AppArmor profiles loaded with hardcoded paths**
```bash
# Windsurf wrote:
cat > /etc/apparmor.d/ai-platform-default << 'EOF'
  /mnt/data/** rw,
  /mnt/data/openclaw/** rw,
EOF
apparmor_parser -r /etc/apparmor.d/ai-platform-default
```

**Problem:** 
- Profile hardcodes `/mnt/data` — breaks for User B on `/mnt/data2`
- Profile name `ai-platform-default` is not network-scoped — two stacks overwrite the same profile
- Loading in Script 0 is wrong — `BASE_DIR` is not known yet

**Fix:**
```bash
# Script 0: do NOT load any AppArmor profiles.
# Only install apparmor packages and ensure the service is running.
# Profile TEMPLATES are created by Script 1 in ${BASE_DIR}/apparmor/
# Profiles are loaded by Script 2 after BASE_DIR is known.

# Script 0 should only do:
systemctl enable apparmor
systemctl start apparmor
echo "✅ AppArmor service enabled — profiles loaded by Script 2"
```

---

**Issue 0-3: Docker daemon.json hardcodes storage path**
```bash
# Windsurf wrote:
cat > /etc/docker/daemon.json << 'EOF'
{
  "data-root": "/mnt/data/docker",
  "log-driver": "json-file"
}
EOF
```

**Problem:** Docker's `data-root` is a global daemon setting — it cannot be per-tenant. Setting it to `/mnt/data/docker` means User B's containers also store their layers there, defeating EBS isolation.

**Fix:**
```bash
# Docker data-root cannot be per-tenant — it's a daemon-level setting.
# Options:
# 1. Leave data-root at default (/var/lib/docker) — simplest, correct
# 2. Set it to the FIRST stack's EBS — document that it's shared
#
# Per-tenant isolation of container DATA is achieved through
# volume mounts into ${BASE_DIR}/data/${service}/ — NOT through data-root.
#
# REMOVE data-root from daemon.json:
cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
```

---

**Issue 0-4: Script 0 teardown logic mixed with setup**
```bash
# Windsurf added cleanup functions in Script 0:
cleanup_previous_installation() {
    docker rm -f $(docker ps -aq) 2>/dev/null
    rm -rf /mnt/data/  # ← DESTROYS ALL TENANT DATA
}
```

**This is catastrophic.** If User B runs Script 0 on a host where User A's stack exists, User A's entire `/mnt/data` is deleted.

**Fix:**
```bash
# Script 0 must NEVER touch /mnt/data or any BASE_DIR.
# Cleanup is Script 0's job only for:
#   - Previously installed system packages (if re-running)
#   - /etc/apparmor.d/ai-platform-* (but only the old hardcoded ones)
# 
# Stack-specific cleanup belongs in a future script-0-tenant.sh
# or handled manually. Script 0 is host-level only.
```

---

## Script 1 — `1-setup-system.sh`

### What It Does
- Interactive configuration collection
- EBS validation
- User creation
- Directory structure creation
- Port allocation
- `.env` generation
- AppArmor template creation

### ✅ Correct
```bash
# Interactive prompts for BASE_DIR, DOCKER_NETWORK ✅
# EBS validation using mountpoint -q ✅
# OPENCLAW_UID = STACK_USER_UID + 1 ✅
# Port allocation with ss ✅
# .env written to ${BASE_DIR}/config/.env ✅
```

### ❌ Critical Issues

**Issue 1-1: Port retry loop still uses broken pattern**
```bash
# Windsurf wrote:
for service in "${services[@]}"; do
    port=${default_ports[$i]}
    if ss -tlnp | grep -q ":${port} "; then
        echo "Port in use"
        # No retry — just increments and moves on
    fi
    i=$((i+1))
done
```

**Fix (as specified in previous review):**
```bash
allocate_port() {
    local service=$1
    local default_port=$2
    local port

    while true; do
        read -p "  ${service} port [${default_port}]: " port_input
        port=${port_input:-$default_port}

        if ss -tlnp | grep -q ":${port} "; then
            echo "  ⚠️  Port ${port} in use — try another"
        else
            echo "  ✅ ${service}: ${port}"
            echo "${service^^}_PORT=${port}" >> "${BASE_DIR}/config/.env"
            break
        fi
    done
}

# Call per service:
allocate_port "prometheus"   5000
allocate_port "grafana"      5001
allocate_port "n8n"          5002
allocate_port "dify"         5003
allocate_port "anythingllm"  5004
allocate_port "litellm"      5005
allocate_port "openwebui"    5006
allocate_port "minio_s3"     5007
allocate_port "minio_console" 5008
allocate_port "signal"       5009
allocate_port "openclaw"     5010
allocate_port "flowise"      5011
```

---

**Issue 1-2: AppArmor templates have literal BASE_DIR — not placeholder**
```bash
# Windsurf wrote:
cat > "${BASE_DIR}/apparmor/default.profile.tmpl" << EOF
profile ai-platform-default {
  ${BASE_DIR}/** rw,   ← This substitutes NOW (double-quote heredoc)
}
EOF
```

This looks correct at first glance — but it means the template IS the final profile (BASE_DIR is baked in at template creation time). This is actually fine IF the template is only used for this stack's Script 2. However it breaks the `BASE_DIR_PLACEHOLDER` pattern referenced throughout the plan.

**Verdict:** The double-quote heredoc approach (substituting at template creation) is actually **simpler and correct** for this use case. The `BASE_DIR_PLACEHOLDER` + sed pattern is only needed if templates are shared across stacks (they are not).

**However:** The profile name inside the template must use `DOCKER_NETWORK`:
```bash
cat > "${BASE_DIR}/apparmor/default.profile.tmpl" << EOF
profile ${DOCKER_NETWORK}-default flags=(attach_disconnected) {
  #include <abstractions/base>

  # Stack data directory — this stack only
  ${BASE_DIR}/** rw,

  # Docker overlay filesystem
  /var/lib/docker/** r,

  # Network
  network inet tcp,
  network inet udp,

  # Deny other mount points
  deny /mnt/** rw,         # too broad — see Issue 1-3
}
EOF
```

---

**Issue 1-3: AppArmor deny rule blocks own BASE_DIR**
```bash
# Windsurf wrote:
deny /mnt/** rw,
# Then also:
${BASE_DIR}/** rw,   ← BASE_DIR = /mnt/data

# AppArmor evaluates deny BEFORE allow.
# "deny /mnt/**" blocks access to /mnt/data/** regardless of the allow rule.
# Result: all containers fail to access their data directories.
```

**Fix:**
```bash
# AppArmor deny rules override allows — never deny a parent of an allow.
# Remove the broad deny. Instead, use a specific deny for OTHER mount points:

# If BASE_DIR=/mnt/data, deny /mnt/data2, /mnt/data3 etc.
# But this requires
