# AppArmor Profile Load Failure — Root Cause Analysis

## What The Error Actually Means

```
AppArmor parser error: Could not open 'tunables/global'
```

This is not a permissions error. It is a **missing include path** error.

Every AppArmor profile starts with:
```
#include <tunables/global>
```

The parser resolves this relative to its base directory, which is `/etc/apparmor.d/`. So it looks for:
```
/etc/apparmor.d/tunables/global
```

This file ships with the `apparmor` package. The error means one of two things:

```
CAUSE A: apparmor package is installed but apparmor-utils is not
         apparmor-utils contains the tunables directory
         Fix: apt-get install -y apparmor-utils apparmor-profiles

CAUSE B: The profile files were written without the #include line
         The script generated bare profiles missing the header
         Fix: profiles must start with #include <tunables/global>

CAUSE C: The profile template substitution produced malformed output
         sed replaced BASE_DIR_PLACEHOLDER but mangled the include line
         Fix: inspect the actual file content at /etc/apparmor.d/ai_platform-default
```

---

## How To Diagnose Right Now

Run these three commands and share output:

```bash
# Check what is actually in the profile file
cat /etc/apparmor.d/ai_platform-default

# Check if tunables directory exists
ls /etc/apparmor.d/tunables/

# Check what apparmor packages are installed
dpkg -l | grep apparmor
```

The most likely finding is **Cause B** — the generated profile file does not contain `#include <tunables/global>` as its first line.

---

## What A Valid AppArmor Profile Must Look Like

```
#include <tunables/global>          ← LINE 1, non-negotiable

profile ai_platform-default flags=(attach_disconnected) {
    #include <abstractions/base>
    #include <abstractions/nameservice>

    # Allow reads from BASE_DIR
    /mnt/data/** r,

    # Deny sensitive paths
    deny /etc/shadow r,
    deny /proc/sysrq-trigger rw,

    network,
}
```

Without `#include <tunables/global>` the parser has no variable definitions (like `@{PROC}`, `@{HOME}`) and refuses to parse anything.

---

## The Secondary Error

```
Warning from stdin (line 1): config file '/etc/apparmor/parser.conf' not found
```

Note the path: `/etc/apparmor/parser.conf` — not `/etc/apparmor.d/`.

This is a **warning, not a fatal error**. It means apparmor-utils was installed without its default config file. It does not stop profile loading but indicates an incomplete package installation.

---

## Message For Windsurf

```
The AppArmor profiles are failing to load for two reasons.
Fix both before attempting to load any profile.

FIX 1: Ensure packages are installed before profile loading
  In the setup_apparmor_profiles() function, before any
  apparmor_parser call, add:

  apt-get install -y apparmor apparmor-utils apparmor-profiles 2>/dev/null || true

FIX 2: Every generated profile file must begin with exactly this line:
  #include <tunables/global>

  The current template generation is producing files without this header.
  Each profile written to /etc/apparmor.d/ must have this as line 1.

  Correct structure for each profile file:

  #include <tunables/global>

  profile ai_platform-default flags=(attach_disconnected) {
      #include <abstractions/base>
      #include <abstractions/nameservice>

      /mnt/data/** rw,
      deny /etc/shadow r,
      deny /proc/sysrq-trigger rw,

      network,
      capability net_bind_service,
  }

FIX 3: After writing each profile, verify it parses before loading:
  apparmor_parser --preprocess /etc/apparmor.d/ai_platform-default
  If that returns non-zero, print the file content and exit 1.
  Do not silently continue with broken profiles.

VERIFICATION: After fixes, this command must return 0:
  apparmor_parser -r /etc/apparmor.d/ai_platform-default && echo "OK"

Do not change anything else in Script 2.
```