# PENDING TASKS — for next model session
> Baseline: v5.14.0 (commit b125582). Branch: main. Tenant: datasquiz.

---

## IMMEDIATE FIX (highest priority)

### 1. OpenClaw "pairing required" — enter the token
**User symptom:** Browser shows "pairing required" after clicking Connect.  
**Root cause:** User left Password field EMPTY. The password IS the gateway token.  
**Fix:** In the OpenClaw web UI connection dialog, enter:
- WebSocket URL: `wss://openclaw.ai.datasquiz.net`
- Password: value of `OPENCLAW_PASSWORD` from `/mnt/datasquiz/config/platform.conf`  
  (currently `Th301nd13!#` — confirm with `grep OPENCLAW_PASSWORD /mnt/datasquiz/config/platform.conf`)

**If token is correct but still fails:** The pending device pairing request needs approval (see item 2).

---

## TASK 2 — OpenClaw Device Pairing Approval (GitHub issue #16305)

**Problem:** OpenClaw requires a CLI command `openclaw devices approve <requestID>` to approve pairing requests. The web UI initiates a request but the server must approve it. Without a CLI, this needs automation.

**Research needed:** Read https://github.com/openclaw/openclaw/issues/16305 to understand:
- Where pending pairing requests are stored (likely in the openclaw data dir)
- Whether there's an HTTP API to approve them
- Whether `openclaw.json` can be configured to auto-approve requests

**Implementation required:**
1. **Script 2** (`prepare_data_dirs()`): After seeding `openclaw.json`, check for pending pairing requests in `${DATA_DIR}/openclaw/` and auto-approve them by writing to config or calling the API.
2. **Script 3** (`configure_openclaw()`): Add `--openclaw-pairs` subcommand that:
   - Lists pending pairing requests: `GET /api/v1/device-pairs` or equivalent
   - Approves a request: `POST /api/v1/device-pairs/{id}/approve` or equivalent
   - Example Script 3 usage: `bash scripts/3-configure-services.sh datasquiz --openclaw-pairs`

**Key file:** OpenClaw data dir is at `/mnt/datasquiz/openclaw/home/` (mounted at `/home/node/.openclaw/` inside container). Check for pairing request files there.

**Check container API:** `DOCKER_HOST=unix:///var/run/docker.sock docker exec ai-datasquiz-openclaw ls /home/node/.openclaw/` to find request storage format.

---

## TASK 3 — Telegram + Discord channels in OpenClaw

**User request:** Add Telegram and Discord as OpenClaw channel options alongside Signal.

**Reference:** https://share.google/aimode/VT6ECWYUGu03o0gxx (user provided link — check OpenClaw docs for Telegram/Discord channel config format)

**OpenClaw channel config format (openclaw.json):**
```json
{
  "channels": {
    "signal": { "enabled": true, "account": "+...", "httpUrl": "...", "autoStart": false },
    "telegram": { "enabled": true, "token": "BOT_TOKEN", "autoStart": false },
    "discord": { "enabled": true, "token": "BOT_TOKEN", "guildId": "...", "autoStart": false }
  }
}
```
*(Verify exact field names from OpenClaw docs/source)*

### Script 1 changes required:
In `configure_service_credentials()` Signal section, add channel selection:
```bash
echo "  OpenClaw communication channels:"
echo "  1) Signal only"
echo "  2) Telegram only"  
echo "  3) Discord only"
echo "  4) Web only (no messaging channel)"
echo "  5) All channels"
safe_read "Select channels [1-5]" "1" "OPENCLAW_CHANNELS"
```

Then conditionally collect per-channel variables:
- **Signal**: `SIGNAL_PHONE`, `SIGNAL_RECIPIENT`, `SIGNAL_REGISTRATION_METHOD` (already done)
- **Telegram**: `TELEGRAM_BOT_TOKEN` (get from @BotFather)
- **Discord**: `DISCORD_BOT_TOKEN`, `DISCORD_GUILD_ID`

Write all to platform.conf. Update template generation (`save_configuration_template`) to include new vars.

### Script 2 changes required:
In `prepare_data_dirs()` openclaw section — seed `channels` in `openclaw.json` based on `OPENCLAW_CHANNELS`:
```bash
local _channels_json=""
if echo "${OPENCLAW_CHANNELS}" | grep -qE "signal|all"; then
    _channels_json += signal block
fi
if echo "${OPENCLAW_CHANNELS}" | grep -qE "telegram|all"; then
    _channels_json += telegram block (requires TELEGRAM_BOT_TOKEN)
fi
if echo "${OPENCLAW_CHANNELS}" | grep -qE "discord|all"; then
    _channels_json += discord block (requires DISCORD_BOT_TOKEN + DISCORD_GUILD_ID)
fi
```

No new containers needed — OpenClaw handles Telegram/Discord natively via its channel plugins.

`SIGNALBOT_ENABLED` should remain independent of channel selection (signalbot container is required for Signal channel but not Telegram/Discord).

### Script 3 changes:
Add channel management to `configure_openclaw()` and credentials display.

---

## TASK 4 — EBS Format still failing (if still an issue)

**Current Script 1 SUDO_EOF does:**
1. Stop Docker service/socket
2. Kill processes with fuser
3. Unmount if mounted
4. sync + drop_caches + blockdev --flushbufs + sleep 2
5. Remove fstab UUID entries + device-path entries (`sed -i "\|^${device}[[:space:]]|d"`)
6. systemctl daemon-reload
7. wipefs -a
8. dd zero first 34 + last 34 sectors (GPT headers)
9. udevadm trigger/settle + sync + sleep 2
10. mkfs.ext4

**If still failing:** The nuclear option is a reboot before running Script 1. This is documented in README. No code change needed — tell user to reboot.

**fstab entry to pre-clean:** `/dev/nvme1n1 /mnt ext4 defaults 0 2` — this raw-device entry (not UUID-based) is the suspected persistent cause. Confirm it's removed by the `sed -i "\|^${device}[[:space:]]|d"` line.

---

## TASK 5 — Documentation update (after Tasks 2 + 3 complete)

After implementing Tasks 2 and 3, update:
- **README.md**: Add OpenClaw pairing approval section; add Telegram/Discord channel config section; update compliance checklist
- **UNIT_TESTING.md**: Add T50 for channel selection (Telegram/Discord); update T49 with pairing fix
- **USER_STORIES.md**: Update Feature 9.1 with multi-channel acceptance criteria; update Feature 4.3 with pairing approval workflow

Then: `git commit` + `git push` + `git tag v5.15.0` + `git push origin v5.15.0`

---

## KEY FILES

| File | Purpose |
|------|---------|
| `scripts/1-setup-system.sh` | Add OPENCLAW_CHANNELS prompt + Telegram/Discord vars |
| `scripts/2-deploy-services.sh` | Seed multi-channel openclaw.json; auto-approve pairing |
| `scripts/3-configure-services.sh` | Add `--openclaw-pairs` command |
| `/mnt/datasquiz/config/platform.conf` | Current live config (source of truth) |
| `/mnt/datasquiz/openclaw/home/openclaw.json` | Live openclaw config (currently has signal only) |

## CURRENT STATE (live as of 2026-04-21)
- OpenClaw: UP and healthy, Signal provider started at port 9999 (no SSE errors)
- Signalbot: UP and healthy, signal-cli registered with +61410594574
- Signal registration: CONFIRMED (SMS received "registration successful")
- OpenClaw pairing: BLOCKED — user enters empty password in UI (token = OPENCLAW_PASSWORD from platform.conf)
- EBS: unknown state (may still need format fix or reboot)

## DO NOT REGRESS
- `autoStart: false` in openclaw.json channels.signal — NEVER change to true
- signalbot httpUrl must point to port 9999 (SSE proxy), NOT 8080 (bbernhard)
- Script 1 SUDO_EOF: no `local` variables (runs outside function context)
- EBS formatting in Script 1: use plain `mkfs.ext4` (no -F flags) after wipefs+dd+udevadm
