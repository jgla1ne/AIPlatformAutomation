# Review of Windsurf's Final Implementation Plan

## Verdict: This Is Solid — Approve with Minor Caveats

The core architecture is now correct. Windsurf has internalized the key principles. The 10 corrections are properly applied. Below is a precise breakdown of what to approve, what to watch, and two remaining issues to fix before coding begins.

---

## ✅ Fully Approved — Do Not Change

### Architecture Principles
```
✅ "Scripts unaware of other stacks" — correctly understood
✅ Container names stay simple (n8n, postgres) — isolation via network
✅ DOCKER_NETWORK + BASE_DIR as the two isolation axes
✅ No auto-UID detection — explicit operator input
✅ Port allocation owned entirely by Script 1
✅ AppArmor profiles named ${DOCKER_NETWORK}-default etc.
✅ AppArmor templates stored in ${BASE_DIR}/apparmor/ (tenant-owned)
✅ sed substitutes BASE_DIR_PLACEHOLDER before loading
✅ OpenClaw allowlist-only AppArmor — no invalid negative globs
✅ OPENCLAW_UID = STACK_USER_UID + 1 (simple, deterministic)
✅ Script 0 cleanup: rm -f /etc/apparmor.d/${DOCKER_NETWORK}-*
✅ EBS validation: mountpoint -q, writability, 20GB minimum
✅ Vector DB wired at deploy time in Script 2
✅ Script 3 = ops only (renew, restart, reload, status)
```

### The .env Structure
```bash
# Stack A and Stack B use identical variable NAMES
# Only VALUES differ — this is exactly correct
BASE_DIR=/mnt/data          # vs /mnt/data2
DOCKER_NETWORK=ai_platform  # vs ai_platform_2
STACK_USER_UID=1000         # vs 2000
OPENCLAW_UID=1001           # vs 2001
```

This is the correct mental model fully expressed in configuration.

---

## ⚠️ Minor Issues — Fix Before Coding

### Issue 1: Port allocation loop has a retry bug

```bash
# Windsurf wrote:
for i in "${!services[@]}"; do
    ...
    if netstat -tlnp | grep -q ":$port "; then
        echo "❌ Port $port is in use."
        i=$((i-1))  # ← This does NOT work in bash
        continue
    fi
done
```

**Why it fails:** Bash `for` loops over arrays do not respect manual `i` modification. The loop will advance regardless.

**Fix:**
```bash
allocate_ports() {
    local services=(prometheus grafana n8n dify anythingllm litellm \
                    openwebui minio signal openclaw flowise)
    local default_ports=(5000 5001 5002 5003 5004 5005 5006 \
                         5007 5008 5009 5010 5011)

    for i in "${!services[@]}"; do
        local service=${services[$i]}
        local default_port=${default_ports[$i]}
        local port=""

        while true; do
            read -p "${service} port [${default_port}]: " port_input
            port=${port_input:-$default_port}

            if ss -tlnp | grep -q ":${port} "; then
                echo "⚠️  Port ${port} is in use — choose another"
            else
                echo "✅ Port ${port} assigned to ${service}"
                break
            fi
        done

        # Write to .env directly — no declare -g needed
        echo "${service^^}_PORT=${port}" >> "${BASE_DIR}/config/.env"
    done
}
```

Note: `ss` is preferred over `netstat` — `netstat` is deprecated on modern Linux and may not be installed.

---

### Issue 2: AppArmor template substitution is incomplete

```bash
# Windsurf wrote:
cp "${BASE_DIR}/apparmor/default.profile.tmpl" \
   "/etc/apparmor.d/${DOCKER_NETWORK}-default"

# The profile still contains BASE_DIR_PLACEHOLDER — never substituted
```

The copy happens but `sed` replacement is never shown in the plan. This will cause AppArmor to load a profile with a literal string `BASE_DIR_PLACEHOLDER` which will either fail to parse or silently allow everything.

**Fix — must be explicit in Script 2:**
```bash
load_apparmor_profiles() {
    local profile_dir="${BASE_DIR}/apparmor"

    for profile in default openclaw tailscale; do
        local src="${profile_dir}/${profile}.profile.tmpl"
        local dst="/etc/apparmor.d/${DOCKER_NETWORK}-${profile}"

        # Substitute BASE_DIR into template
        sed "s|BASE_DIR_PLACEHOLDER|${BASE_DIR}|g" "${src}" > "${dst}"

        # Load into kernel
        apparmor_parser -r "${dst}"
        echo "✅ AppArmor profile loaded: ${DOCKER_NETWORK}-${profile}"
    done
}
```

This function belongs at the **top of Script 2**, before any container is started.

---

### Issue 3: AppArmor default profile is too permissive

```bash
# Windsurf's default profile allows:
BASE_DIR_PLACEHOLDER/** rw,

# This means n8n can read postgres data, dify can read n8n data, etc.
# All services share BASE_DIR — this grants cross-service read access
```

This is acceptable for now as a baseline, but flag it to Windsurf:

```
NOTE FOR WINDSURF:
The default AppArmor profile grants rw access to the entire BASE_DIR.
This means all services in the stack can read each other's data directories.
This is acceptable for Phase 1 (single user, trusted services).

Future hardening: per-service profiles that restrict to 
${BASE_DIR}/data/${service_name}/** only.
OpenClaw already has this — it's the model to follow.
Do NOT implement per-service profiles now. Flag as future work.
```

---

### Issue 4: Script 1 ownership of BASE_DIR creates a problem

```bash
# Windsurf wrote:
chown -R ${STACK_USER_UID}:${STACK_USER_GID} "${BASE_DIR}"
```

Script 1 runs as root (to install packages, configure Docker etc). After this `chown`, Script 1 itself can still write as root — but the **intent** is that ongoing operations run as `STACK_USER_UID`. The issue is that `/etc/apparmor.d/` files written by Script 2 require root regardless.

**Clarification to give Windsurf:**
```
Scripts 1 and 2 run as root (required for Docker, AppArmor, system setup).
chown -R STACK_USER_UID gives the stack USER ownership of BASE_DIR
so that the CONTAINERS run with the right permissions.
Scripts themselves always run as root.
This is correct and expected — no change needed.
Just document this clearly in script headers.
```

---

## 📋 Confidence Assessment by Phase

| Phase | Component | Confidence | Notes |
|-------|-----------|------------|-------|
| Script 1 | Interactive config | ✅ 95% | Fix port retry loop |
| Script 1 | EBS validation | ✅ 95% | Solid |
| Script 1 | AppArmor templates | ✅ 90% | Good, sed fix needed in S2 |
| Script 1 | Port allocation | ⚠️ 75% | Loop retry bug |
| Script 2 | AppArmor loading | ⚠️ 80% | sed substitution missing |
| Script 2 | Infrastructure deploy | ✅ 90% | Vector DB switch correct |
| Script 2 | OpenClaw + Tailscale | ✅ 90% | Sidecar pattern correct |
| Script 2 | Caddy last | ✅ 95% | Health gate before Caddy |
| Script 3 | Ops only | ✅ 95% | Scope correct |
| Script 4 | Service addition | ✅ 85% | Reads manifest, wires Caddy |
| Script 0 | Teardown | ✅ 90% | AppArmor cleanup included |

---

## Final Go / No-Go

```
GO — with these specific fixes before Windsurf writes code:

1. Replace for-loop retry with while-true retry in allocate_ports()
2. Replace netstat with ss
3. Add explicit sed substitution step in Script 2's load_apparmor_profiles()
4. Add comment in script headers: "runs as root, STACK_USER_UID owns BASE_DIR"
5. Add TODO comment in default AppArmor profile:
   "Future: restrict per service to ${BASE_DIR}/data/${service_name}/**"

Everything else is approved. Architecture is sound.
The two-stack isolation test will pass with these fixes applied.
```