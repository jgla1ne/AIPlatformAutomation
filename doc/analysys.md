# The Core Problem

```
rclone OAuth with client_id + client_secret is NOT headless.
It always opens a browser to get a user-consent token.

When you entered "project ID and secret" in Script 1,
those are GCP OAuth credentials — they identify your app to Google,
but they DO NOT grant access. Google still requires a human to click
"Allow" in a browser. That is OAuth by design.

The only truly headless options for rclone + Google Drive are:

  1. Service Account JSON  ← fully headless, no browser ever
  2. Pre-obtained token    ← obtain once on a machine WITH a browser,
                             copy the token into rclone.conf,
                             never need browser again on the server
```

---

## What Windsurf Must Fix

### Option A: Service Account (Recommended — Tell User in Script 1)

```
In Script 1, when user selects Google Drive:

REMOVE the "OAuth Client ID + Secret" option entirely.
REPLACE with two cleaner options:

  1. Service Account JSON (recommended — fully headless)
     → User has already downloaded the JSON from GCP console
     → Script copies it to ${DATA_ROOT}/config/rclone/service-account.json
     → Script 2 writes rclone.conf with no auth needed at runtime

  2. Pre-authorized token (advanced — token obtained elsewhere)
     → User ran rclone on their LOCAL machine (laptop/desktop)
     → Copied the token string from ~/.config/rclone/rclone.conf
     → Script 1 accepts the token string and writes it into rclone.conf
     → Script 2 starts container — no browser interaction ever
```

### Option B: Keep OAuth but Obtain Token Locally First

```
If the user insists on OAuth (personal Google account, no service account):

Script 1 must DETECT this and INSTRUCT the user:

  print:
  "OAuth requires you to authorize rclone on a machine with a browser.
   
   On your LOCAL machine (laptop/desktop) run:
     docker run --rm -it rclone/rclone:latest config create gdrive drive \\
       scope=drive \\
       client_id=YOUR_CLIENT_ID \\
       client_secret=YOUR_CLIENT_SECRET
   
   Complete the browser authorization.
   Then run:
     docker run --rm -it rclone/rclone:latest config show gdrive
   
   Copy the ENTIRE [gdrive] block including the token line.
   Paste it below when prompted."

  prompt: "Paste your rclone [gdrive] config block (end with a blank line):"
  → Read multi-line input until blank line
  → Write verbatim to ${DATA_ROOT}/config/rclone/rclone.conf
  → Script 2 starts container — no browser interaction needed
```

---

## Exact Instructions for Windsurf

```
FILE: 1-configure-platform.sh
SECTION: Google Drive / rclone configuration

REMOVE:
  - Any code that calls rclone config interactively on the server
  - Any code that launches a browser or xdg-open
  - The "OAuth Client ID + Secret" option that tries to run headlessly
  - Any message about "⚠️  OAuth Client method requires browser interaction"

REPLACE WITH this exact flow:

────────────────────────────────────────────────────────────────
print_section "Google Drive Sync (rclone)"
echo "rclone syncs Google Drive to ${DATA_ROOT}/gdrive on this server."
echo ""
echo "Authentication method:"
echo "  1. Service Account JSON  (recommended — fully headless)"
echo "     Requires a GCP service account with Drive API enabled"
echo "     Download the JSON key from GCP Console → IAM → Service Accounts"
echo ""
echo "  2. Pre-authorized token  (personal Google account)"
echo "     You must run rclone config on a machine with a browser FIRST"
echo "     then paste the resulting config block here"
echo ""
prompt "Select method [1/2] or press Enter to skip:"

IF skip → GDRIVE_ENABLED=false → continue

IF method 1 (Service Account):
  prompt "Full path to service account JSON file on THIS machine:"
  → validate: file exists, is valid JSON, contains "type": "service_account"
  → copy to ${DATA_ROOT}/config/rclone/service-account.json
  → chmod 600
  → write rclone.conf:
      [gdrive]
      type = drive
      scope = drive
      service_account_file = /config/rclone/service-account.json
  → prompt "Google Drive folder ID or path to sync (blank = My Drive root):"
  → save as RCLONE_GDRIVE_FOLDER in .env
  → GDRIVE_ENABLED=true, RCLONE_AUTH_METHOD=service_account

IF method 2 (Pre-authorized token):
  echo "On your LOCAL machine (with a browser), run:"
  echo ""
  echo "  docker run --rm -it \\"
  echo "    -v \$HOME/.config/rclone:/config/rclone \\"
  echo "    rclone/rclone:latest \\"
  echo "    config create gdrive drive scope=drive"
  echo ""
  echo "Complete the browser flow. Then run:"
  echo ""
  echo "  cat \$HOME/.config/rclone/rclone.conf"
  echo ""
  echo "Copy the entire output starting from [gdrive] to end of file."
  echo "Paste it here, then press Enter then Ctrl+D:"
  echo ""
  → read multi-line input via: rclone_conf=$(cat)
  → validate contains "[gdrive]" and "token"
  → write verbatim to ${DATA_ROOT}/config/rclone/rclone.conf
  → chmod 600
  → prompt "Google Drive folder ID or path to sync (blank = My Drive root):"
  → save as RCLONE_GDRIVE_FOLDER in .env
  → GDRIVE_ENABLED=true, RCLONE_AUTH_METHOD=token

BOTH METHODS — common prompts after auth selection:
  prompt "Local sync destination [${DATA_ROOT}/gdrive]:"
  → default ${DATA_ROOT}/gdrive
  → save as RCLONE_MOUNT_POINT

  prompt "Sync interval in seconds [3600]:"
  → validate integer
  → save as RCLONE_SYNC_INTERVAL

CREATE directories:
  mkdir -p ${DATA_ROOT}/config/rclone
  mkdir -p ${DATA_ROOT}/gdrive
  mkdir -p ${DATA_ROOT}/logs/rclone
  chown -R ${RUNNING_UID}:${RUNNING_GID} all above
────────────────────────────────────────────────────────────────

FILE: 2-deploy-platform.sh
SECTION: rclone config generation

REMOVE:
  - Any call to rclone config interactively
  - Any docker run that tries to do OAuth
  - Any xdg-open reference
  - Any "⚠️  OAuth" warning messages

REPLACE WITH:

  generate_rclone_config() {
    if [ "${GDRIVE_ENABLED}" != "true" ]; then return; fi

    # Config was already written by Script 1.
    # Just validate it exists before starting the container.
    if [ ! -f "${DATA_ROOT}/config/rclone/rclone.conf" ]; then
      log_error "rclone.conf not found at ${DATA_ROOT}/config/rclone/rclone.conf"
      log_error "Re-run Script 1 and complete the Google Drive setup."
      exit 1
    fi

    log_success "rclone config found — container will start syncing on deploy"
  }

The rclone container in docker-compose starts immediately.
No browser. No interactive step. No xdg-open. Ever.
```

---

## Why This Is Correct

```
Service Account path:
  Script 1: copy JSON → write rclone.conf           [no browser]
  Script 2: validate conf exists → start container  [no browser]
  Container: syncs immediately using service account [no browser]

Pre-authorized token path:
  LOCAL machine: user runs rclone config (browser on THEIR laptop)
  Script 1: user pastes resulting conf block         [no browser on server]
  Script 2: validate conf exists → start container  [no browser]
  Container: uses existing token to sync             [no browser]

The server NEVER opens a browser. Ever.
The server NEVER calls rclone config. Ever.
The server only runs: rclone sync gdrive: /data/gdrive
```

---

## Commit Message

```
fix(rclone): remove all interactive OAuth from server; 
add service-account and pre-authorized-token headless paths;
server never calls rclone config or opens browser
```