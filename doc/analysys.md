# rsync with Google Drive + Signal Pairing + Step 3 Role Clarification

## rsync + Google Drive — The Right Tool Is rclone, Not rsync

```
rsync = syncs between two filesystems (local↔local or local↔SSH)
rsync does NOT speak Google Drive API natively

rclone = rsync-style tool but speaks 70+ cloud APIs including Google Drive
rclone is the correct tool for Google Drive sync
```

### Where This Lives in the 5-Script Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Script 1: Ask user if they want Google Drive sync              │
│            ENABLE_GDRIVE_SYNC=true/false → written to .env      │
│            If true: ask for GDRIVE_REMOTE_NAME, GDRIVE_FOLDER   │
│                                                                  │
│  Script 2: If ENABLE_GDRIVE_SYNC=true                           │
│            Install rclone binary (single binary, no daemon)      │
│            Create rclone config dir under BASE_DIR               │
│            Deploy rclone as a container with:                    │
│              - /mnt/data mounted read/write                      │
│              - cron schedule (every 6h or configurable)          │
│              - rclone config mounted from BASE_DIR/config/rclone │
│            NOTE: rclone CANNOT auth headlessly without a token   │
│            Token must be obtained interactively ONCE             │
│                                                                  │
│  Script 3: rclone auth flow (interactive, one-time)             │
│            rclone config reconnect ${GDRIVE_REMOTE_NAME}:        │
│            Prints auth URL → user opens in browser              │
│            Pastes token back → stored in BASE_DIR/config/rclone  │
│            From this point sync runs automatically via cron      │
└─────────────────────────────────────────────────────────────────┘
```

### Why rclone Auth Cannot Be in Script 2

```
Script 2 runs non-interactively (or should)
Google OAuth requires a browser redirect
The token is user-specific and cannot be pre-baked
This is exactly what Script 3 is for:
  one-time interactive configuration that requires human input
```

---

## Signal Pairing — Correct Architecture

```
Signal API (signal-cli REST) starts in Script 2
It becomes accessible at https://ai.datasquiz.net/signal

User pairing flow is:
  1. Call POST /v1/register/{phone}
  2. Receive SMS code
  3. Call POST /v1/register/{phone}/verify/{code}
  This is done via curl or the Swagger UI at /signal/v1/api-docs

This does NOT require Script 3 at all.
User does it themselves via the public endpoint.
Document the URL in the deployment summary printout from Script 2.
That is sufficient.

Only put Signal in Script 3 if you want to offer:
  - Re-registration (number change)
  - Linking a second device
  - Resetting the signal identity
```

---

## Script 3 — Correct Scope Definition

This is the key design question. Here is the clean split:

```
┌─────────────────────────────────────────────────────────────────┐
│  SCRIPT 3 owns: things that need human input OR periodic action │
│                                                                  │
│  Category A — One-time interactive setup (run once after S2):   │
│    ├── rclone Google Drive auth token                           │
│    ├── Tailscale re-auth if TS_AUTHKEY expired                  │
│    └── SSL cert force-renew (Caddy normally auto-renews)        │
│                                                                  │
│  Category B — Operational actions (run anytime after S2):       │
│    ├── Restart any specific service                             │
│    ├── Rotate secrets (generate new API keys → write to .env)  │
│    ├── Re-run Caddy config reload after domain change           │
│    └── Re-run vector DB env wiring if DB was switched           │
│                                                                  │
│  Category C — Recovery (when a service failed in S2):           │
│    ├── Retry failed service with debug output                   │
│    ├── Check logs for specific service                          │
│    └── Re-run health checks and print current status           │
│                                                                  │
│  SCRIPT 3 does NOT own:                                         │
│    ✗ Deploying new services (that is Script 4)                  │
│    ✗ Changing the vector DB selection (re-run Script 1+2)       │
│    ✗ Signal user pairing (user does this via the public URL)    │
└─────────────────────────────────────────────────────────────────┘
```

### Script 3 Menu Structure

```bash
# Script 3 presents a numbered menu:

echo "=== Configure Services ==="
echo "1) Authorize Google Drive sync (rclone - required once)"
echo "2) Re-authorize Tailscale (if auth key expired)"
echo "3) Restart a service"
echo "4) Force SSL certificate renewal"
echo "5) Rotate API secrets"
echo "6) View service health status"
echo "7) Re-wire vector DB config to all services"
echo "8) View service logs"
echo "9) Exit"
```

---

## What Goes Into Script 2 Right Now (No New Scope)

```
Script 2 additions needed (confirmed, not new scope):

  ADD: rclone container deployment (if ENABLE_GDRIVE_SYNC=true)
       No auth yet — just deploy the container and mount the config dir
       Container starts but sync will fail until Script 3 auth is done
       Deployment summary prints:
         "Google Drive sync: run Script 3 option 1 to authorize"

  ADD: Signal deployment summary line:
         "Signal API: https://${DOMAIN}/signal"
         "Signal pairing: open https://${DOMAIN}/signal/v1/api-docs"
         "Register your number and verify the SMS code to activate"

  NO CHANGE to anything else in Script 2
```

---

## Full Picture Across All 5 Scripts (Current Agreed State)

```
Script 0: Packages, Docker daemon, AppArmor service, NO user creation
          NO hardcoded UIDs, NO profile loading

Script 1: Interactive collection of all config
          User/UID creation, directory structure, .env generation
          AppArmor profile generation (using BASE_DIR from user input)
          Caddyfile generation (all routes, no openclaw route)
          chown -R STACK_USER_UID:STACK_USER_GID BASE_DIR
          chown -R 999:999 BASE_DIR/data/postgres (one exception)

Script 2: Deploy all services in layers
          Layer 1: postgres, redis, vector DB, minio (health gated)
          Layer 2: app services with VDBENV_* vars injected
          Layer 3: Tailscale sidecar → tailscale up → get IP
          Layer 4: openclaw (--network container:tailscale-openclaw)
          Layer 5: rclone (if ENABLE_GDRIVE_SYNC=true, no auth yet)
          Layer 6: Caddy (last, all upstreams verified first)
          Deployment summary: all URLs + openclaw Tailscale IP

Script 3: Interactive operations menu
          A: rclone gdrive auth (one-time)
          B: Tailscale re-auth
          C: Service restart
          D: SSL renewal
          E: Secret rotation
          F: Health status
          G: Vector DB re-wire
          H: Service logs

Script 4: Add new dockerized service to running stack
          Prompts for: image, port, subdomain path, env vars
          Appends service to Docker network
          Appends Caddy route
          Runs health check
          Updates deployment summary
```

---

## Message for Windsurf

```
Two additions to Script 2 only. Nothing else changes.

ADDITION 1: rclone deployment (after minio, before Caddy)

if [[ "${ENABLE_GDRIVE_SYNC:-false}" == "true" ]]; then
    mkdir -p ${BASE_DIR}/config/rclone
    chown ${STACK_USER_UID}:${STACK_USER_GID} ${BASE_DIR}/config/rclone

    docker run -d \
        --name rclone-gdrive \
        --network ${DOCKER_NETWORK} \
        --user ${STACK_USER_UID}:${STACK_USER_GID} \
        -v ${BASE_DIR}/config/rclone:/config/rclone \
        -v ${BASE_DIR}/data:/data \
        rclone/rclone:latest \
        sync /data gdrive:${GDRIVE_FOLDER:-AIPlatformBackup} \
        --config /config/rclone/rclone.conf \
        --create-empty-src-dirs \
        --log-level INFO

    echo "[INFO] rclone deployed. Run Script 3 option 1 to authorize Google Drive."
fi

ADDITION 2: Add to deployment summary printout at end of Script 2

echo "Signal API:     https://${DOMAIN}/signal"
echo "Signal pairing: https://${DOMAIN}/signal/v1/api-docs"
echo "GDrive sync:    Run './3-configure-services.sh' → option 1 to authorize"

Do not change anything else in Script 2.

Script 3 will be written separately as a menu-driven operations script
covering: rclone auth, tailscale re-auth, service restart, SSL renewal,
secret rotation, health status, vector DB re-wire, log viewing.
```