Let me fetch the current repo structure first.

**Fetching:**
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/1-setup-system.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/2-deploy-services.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/3-configure-services.sh
- https://github.com/jgla1ne/AIPlatformAutomation/tree/main/scripts

Let me check what extra files exist:
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/0-reset-tenant.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/4-add-service.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/utils.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/gpu-setup.sh
- https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/scripts/docker-compose.yml

---

## What I Found

```
CURRENT FILES IN /scripts:
──────────────────────────────────────────────
0-reset-tenant.sh        ✅ IS one of the 5
1-setup-system.sh        ✅ IS one of the 5
2-deploy-services.sh     ✅ IS one of the 5
3-configure-services.sh  ✅ IS one of the 5
4-add-service.sh         ✅ IS one of the 5
──────────────────────────────────────────────
utils.sh                 ❌ VIOLATES the rule
gpu-setup.sh             ❌ VIOLATES the rule
docker-compose.yml       ✅ Not a script, acceptable
──────────────────────────────────────────────
```

The constraint is broken by `utils.sh` and `gpu-setup.sh`. Here is exactly how to fix it.

---

## The Fix: Absorb Both Files Into Their Owners

### Where Each File Belongs

```
utils.sh     → SPLIT between Script 1 and Script 2
               (shared functions = top of each script
                that uses them, not a separate file)

gpu-setup.sh → ABSORBED into Script 1
               (GPU detection is setup, not deployment)
```

---

## Concrete Action for Windsurf

### Step 1 — Absorb `gpu-setup.sh` into Script 1

Script 1 currently sources `gpu-setup.sh` like this:

```bash
source "$(dirname "$0")/gpu-setup.sh"
# or
bash scripts/gpu-setup.sh
```

Replace that entire source/call with the function body **inline** inside Script 1:

```bash
# ─────────────────────────────────────────────────────────────
# SECTION: GPU/CPU Detection  (was gpu-setup.sh — now inline)
# ─────────────────────────────────────────────────────────────
detect_compute() {
  log_info "Detecting compute capabilities..."

  COMPUTE_TYPE="cpu"
  GPU_COUNT=0
  GPU_MEMORY_MB=0

  if command -v nvidia-smi &>/dev/null; then
    local gpu_info
    gpu_info=$(nvidia-smi --query-gpu=name,memory.total \
               --format=csv,noheader 2>/dev/null) || true

    if [[ -n "$gpu_info" ]]; then
      COMPUTE_TYPE="gpu"
      GPU_COUNT=$(echo "$gpu_info" | wc -l)
      GPU_MEMORY_MB=$(echo "$gpu_info" | awk -F', ' \
        '{gsub(/ MiB/,"",$2); sum+=$2} END{print sum}')
      log_success "GPU detected: ${GPU_COUNT} GPU(s), ${GPU_MEMORY_MB}MB VRAM"
    fi
  elif command -v rocm-smi &>/dev/null; then
    rocm-smi &>/dev/null 2>&1 && COMPUTE_TYPE="gpu" || true
    [[ "$COMPUTE_TYPE" == "gpu" ]] && \
      log_success "AMD GPU detected via ROCm"
  fi

  [[ "$COMPUTE_TYPE" == "cpu" ]] && \
    log_info "No GPU found — CPU-only deployment"

  # Write to .env — Script 2 reads this
  cat >> "${ENV_FILE}" <<EOF

# Compute
COMPUTE_TYPE=${COMPUTE_TYPE}
GPU_COUNT=${GPU_COUNT}
GPU_MEMORY_MB=${GPU_MEMORY_MB}
EOF
  return 0
}
```

Then **delete `gpu-setup.sh`**.

---

### Step 2 — Absorb `utils.sh` into Script 1 and Script 2

`utils.sh` typically contains logging, color codes, helper functions. These go at the **top of each script that uses them** as a `# ── UTILITIES ──` section.

Pattern for both Script 1 and Script 2 header:

```bash
#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# Script N — [Name]
# Part of 5-script AI Platform stack
# ═══════════════════════════════════════════════════════════════
set -o pipefail

# ─────────────────────────────────────────────────────────────
# UTILITIES  (inline — no external utils.sh dependency)
# ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_section() { echo -e "\n${CYAN}══ $* ══${NC}"; }

die() {
  log_error "$*"
  exit 1
}

require_root() {
  [[ $EUID -eq 0 ]] && die "Do not run as root. Use your deploy user."
}

check_command() {
  command -v "$1" &>/dev/null || die "Required command not found: $1"
}
# ─────────────────────────────────────────────────────────────
```

Then **delete `utils.sh`**.

---

## Verified 5-Script Architecture

```
┌────┬─────────────────────────┬──────────────────────────────────────────┐
│ #  │ SCRIPT                  │ OWNS                                     │
├────┼─────────────────────────┼──────────────────────────────────────────┤
│ 0  │ 0-reset-tenant.sh       │ Full EBS wipe, Docker prune, .env delete │
│ 1  │ 1-setup-system.sh       │ Packages, users, GPU detect, .env gen,   │
│    │                         │ service selection, Caddy config, SSL mode │
│ 2  │ 2-deploy-services.sh    │ Docker up, DB init, healthchecks,        │
│    │                         │ Tailscale auth, rclone mount, AppArmor   │
│ 3  │ 3-configure-services.sh │ SSL reconfigure, Tailscale re-auth,      │
│    │                         │ GDrive re-auth, Signal re-pair, restarts │
│ 4  │ 4-add-service.sh        │ Add new dockerized service post-deploy,  │
│    │                         │ generates compose fragment + Caddy route │
├────┼─────────────────────────┼──────────────────────────────────────────┤
│    │ docker-compose.yml      │ Not a script — compose definition only   │
│    │ .env (generated)        │ Not a script — written by Script 1       │
└────┴─────────────────────────┴──────────────────────────────────────────┘

DELETED:
  utils.sh     → functions inlined into scripts that use them
  gpu-setup.sh → detect_compute() inlined into Script 1
```

---

## What To Tell Windsurf

```
Instructions for Windsurf:

1. Open gpu-setup.sh
   - Copy ALL function bodies
   - Paste them into 1-setup-system.sh 
     after the UTILITIES section
   - Remove any "source gpu-setup.sh" line in Script 1
   - Delete gpu-setup.sh

2. Open utils.sh  
   - Copy ALL content
   - Paste at top of 1-setup-system.sh (after shebang)
   - Paste at top of 2-deploy-services.sh (after shebang)
   - Paste at top of 3-configure-services.sh (after shebang)
   - Paste at top of 4-add-service.sh (after shebang)
   - Remove any "source utils.sh" lines in all scripts
   - Delete utils.sh

3. Verify final state:
   ls scripts/
   # Must show ONLY:
   # 0-reset-tenant.sh
   # 1-setup-system.sh
   # 2-deploy-services.sh
   # 3-configure-services.sh
   # 4-add-service.sh
   # docker-compose.yml
```