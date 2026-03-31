# Windsurf Fix Instructions — AI Platform Scripts
> Grounded entirely in the North Star README v2.1.0.
> Read this document in full before touching any file.
> Every instruction below cites the README principle it enforces.

---

## Why this document exists

Windsurf keeps introducing the same class of regressions after each fix cycle
because it is pattern-matching to "what looks like a working script" rather
than implementing the README as a specification. The README is not a
suggestion. It contains the phrase: *"Any undiscussed deviation is a bug,
regardless of intent."* This document translates the README into a concrete,
ordered repair checklist so the same mistakes cannot re-enter.

---

## Part 1 — Confirmed Bugs in the Current Scripts

These are verified deviations from the README, found in the submitted scripts.
Each must be fixed. No new code may be written until these are resolved.

---

### BUG-01 — Script 0 uses wrong confirmation phrase (README §6 Script 0)

**File:** `0-complete-cleanup.sh`

**Current behaviour:**
```bash
typed_confirmation "NUKE-${tenant_id}" "NUKE-${tenant_id}"
```

**README requirement (§6, Script 0, "Typed confirmation — mandatory"):**
```bash
[[ "${response}" == "DELETE ${TENANT_ID}" ]] \
    || { echo "Confirmation did not match. Aborting."; exit 1; }
```

**Fix:** Replace the `typed_confirmation` function and its call with the exact
pattern from the README. The confirmation phrase must be `DELETE ${TENANT_ID}`,
not `NUKE-${tenant_id}`. This is not a style choice — it is the specified UX.

---

### BUG-02 — Script 0 does not source `platform.conf` before cleanup (README P1)

**File:** `0-complete-cleanup.sh`

**Current behaviour:** The script receives `tenant_id` as an argument and
constructs paths like `/mnt/${tenant_id}` by string concatenation. It never
sources `platform.conf`.

**README requirement (P1):**
> Scripts 0, 2, and 3 source `platform.conf`.
> `CONFIGURED_DIR`, `DATA_DIR`, `CONFIG_DIR`, `DOCKER_NETWORK`, `TENANT_PREFIX`
> are all defined in `platform.conf`. Nothing is hardcoded in scripts 0, 2, or 3.

**Fix:**
```bash
platform_conf="/mnt/${tenant_id}/platform.conf"
[[ -f "$platform_conf" ]] || fail "platform.conf not found. Cannot clean up safely."
# shellcheck source=/dev/null
source "$platform_conf"
```
After sourcing, replace every hardcoded path construction with the variables
from `platform.conf`: `${BASE_DIR}`, `${DATA_DIR}`, `${CONFIG_DIR}`,
`${CONFIGURED_DIR}`, `${LOG_DIR}`, `${DOCKER_NETWORK}`, `${TENANT_PREFIX}`.

---

### BUG-03 — Script 0 cleanup order is wrong (README §6 Script 0)

**File:** `0-complete-cleanup.sh`

**Current behaviour:** Calls individual container/network/volume functions in
custom order. Does not call `docker compose down`.

**README requirement (§6, "Execution order — strict"):**
```
1. Typed confirmation: DELETE ${TENANT_ID}
2. docker compose down --volumes --remove-orphans
3. Remove images (scoped by label AND tenant prefix)
4. rm -rf "${DATA_DIR}"
5. rm -rf "${CONFIG_DIR}"
6. rm -rf "${CONFIGURED_DIR}"   ← CRITICAL: clears idempotency markers
7. rm -rf "${LOG_DIR}"
8. docker network rm "${DOCKER_NETWORK}" || true
9. Optional: unmount EBS (--unmount-ebs flag)
```

**Fix:** Rewrite `main()` to follow this exact order. Use
`docker compose -f "${COMPOSE_FILE}" down --volumes --remove-orphans`
at step 2, then the scoped image removal pattern from the README §6.

---

### BUG-04 — Script 0 image removal is a broad purge (README §6 Script 0)

**File:** `0-complete-cleanup.sh`

**Current behaviour:** Uses `docker system prune -f` — this is a broad purge
that removes resources from **all** projects on the host, not just the tenant.

**README requirement (§6, Script 0, "Image removal — scoped"):**
```bash
# By compose project label
docker images \
    --filter "label=com.docker.compose.project=${TENANT_ID}" \
    -q | xargs -r docker rmi --force

# By name prefix (catches label-less images)
docker images --format "{{.Repository}}:{{.Tag}}" \
    | grep "^${TENANT_PREFIX}-" \
    | xargs -r docker rmi --force
```

**Fix:** Remove `docker system prune`. Replace with the two scoped removal
commands above. The `|| true` must be on the network removal, not on image
removal.

---

### BUG-05 — Script 2 requires `yq` but Script 1 must install it (README §13)

**File:** `2-deploy-services.sh` — `framework_validate()`

**Current behaviour:** The function correctly checks for `yq`, which is
required. However, the Script 1 output assessment (SCRIPT1_OUTPUT_ASSESSMENT.md)
confirms Script 1 does **not** install `yq` — it installs only
`curl wget git jq docker.io docker-compose-plugin`.

**README requirement (§13 Dependencies):**
> `yq` — Used by Script 2. Installed by Script 1.

**Fix to Script 1** (not shown but required): Add `yq` to the package
installation step in `1-setup-system.sh`. Install via:
```bash
wget -qO /usr/local/bin/yq \
    "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
chmod +x /usr/local/bin/yq
```
Also add `lsof` and `openssl` to Script 1's package install list — both are
required by the README and not present in the assessment output.

---

### BUG-06 — Script 2 `depends_on` blocks reference potentially disabled services (README §6 Script 2)

**File:** `2-deploy-services.sh` — `generate_compose()`

**Current behaviour:** LiteLLM's `depends_on` unconditionally lists `postgres`
and `redis`. Open WebUI unconditionally lists `ollama`. If any of those services
are disabled, the compose file will fail validation.

**README requirement (§6, Script 2, "depends_on correctness — mandatory"):**
```bash
webui_deps=""
[[ "${POSTGRES_ENABLED}" == "true" ]] && webui_deps+="      - postgres"$'\n'
[[ "${REDIS_ENABLED}"    == "true" ]] && webui_deps+="      - redis"$'\n'
```
Then reference `${webui_deps}` in the heredoc. A disabled service must **never**
appear in another service's `depends_on`.

**Fix:** Before `generate_compose()`, build dependency strings conditionally
for every service that has `depends_on`. Apply the same pattern to LiteLLM,
Open WebUI, and any other service with dependencies. If the dependency list
is empty, omit the `depends_on` key entirely.

---

### BUG-07 — Script 2 execution order is wrong (README §6 Script 2)

**File:** `2-deploy-services.sh` — `main()`

**Current behaviour:** Generates compose → generates configs → deploys.
Missing: `validate_compose()`, `pull_images()`, `validate_caddyfile()`,
`wait_for_health()`, and hardcoded sentinel scan.

**README requirement (§6, Script 2, "Execution order — strict"):**
```
1.  source platform.conf
2.  Pre-flight checks (docker daemon, disk space, platform.conf exists)
3.  generate_compose()          → config/docker-compose.yml
4.  validate_compose()          → docker compose config (dry run)
5.  generate_litellm_config()   → config/litellm/config.yaml
6.  generate_caddyfile()        → config/caddy/Caddyfile  [if caddy enabled]
7.  docker compose pull
8.  validate_caddyfile()        → caddy validate [AFTER pull, not before]
9.  docker compose up -d
10. wait_for_health() for each enabled service
11. mark_done() for each step
```

**Fix:** Rewrite `main()` to implement every step in this order. Do not
combine steps. `validate_caddyfile()` must run at step 8, after pull —
running it before the image exists will always fail.

---

### BUG-08 — Script 2 missing `generate_litellm_config()` per README spec (README §10)

**File:** `2-deploy-services.sh`

**Current behaviour:** Generates a hardcoded LiteLLM config with `llama2` and
`success_callback: ["langfuse"]`. Neither matches the README spec.

**README requirement (§10, "LiteLLM config.yaml"):**
- Include `ollama/${OLLAMA_DEFAULT_MODEL}` only if `OLLAMA_ENABLED=true`
- Include OpenAI block only if `OPENAI_API_KEY` is non-empty
- Include Anthropic block only if `ANTHROPIC_API_KEY` is non-empty
- (etc. for each provider key)
- `master_key: ${LITELLM_MASTER_KEY}` must be present
- `database_url: ${LITELLM_DB_URL}` must be present
- No hardcoded model names. No `langfuse` unless explicitly configured.

**Fix:** Rewrite `generate_litellm_config()` using conditional heredoc blocks
(same pattern as `generate_compose()`) so only non-empty API keys produce
model entries. The `api_base` for ollama must use the container name:
`http://${TENANT_PREFIX}-ollama:11434`.

---

### BUG-09 — Script 2 `wait_for_health()` is absent (README Appendix C)

**File:** `2-deploy-services.sh`

**Current behaviour:** After `docker compose up -d`, the script completes
immediately. No health waiting occurs. Script 3 then runs against containers
that may not yet be healthy.

**README requirement:** `wait_for_health()` must be called for each enabled
service after `docker compose up -d`. Health is `State.Health.Status == "healthy"`,
not `State.Status == "running"`. Timeouts per service are specified in §6.

**Fix:** Implement `wait_for_health()` per Appendix C of the README and call
it for each enabled service after deployment, in dependency order
(postgres → redis → ollama → litellm → openwebui → qdrant).

---

### BUG-10 — Script 2 missing hardcoded sentinel scan (README §6 Script 2)

**File:** `2-deploy-services.sh`

**Current behaviour:** No sentinel scan exists.

**README requirement (§6, Script 2, "Hardcoded value scan — mandatory"):**
```bash
grep -rE "CHANGEME|TODO_REPLACE|FIXME|xxxx|\{\{[A-Z_]+\}\}" \
    "${CONFIG_DIR}/" && fail "Unreplaced sentinels found" || true
```
This must run before `deploy_containers()`.

**Fix:** Add this exact grep command as a function `scan_for_sentinels()` and
call it between step 6 and step 7 (after config generation, before pull).

---

### BUG-11 — Script 2 uses wrong container name format (README §7)

**File:** `2-deploy-services.sh` — `generate_compose()`

**Current behaviour:** Container names use `${PREFIX}-${TENANT_ID}-postgres`
(e.g. `ai-datasquiz-postgres`).

**README requirement (§7, Service Catalogue):**
Container names follow the pattern `${TENANT_PREFIX}-postgres` where
`TENANT_PREFIX` equals `TENANT_ID`. The `PREFIX` variable (separate from
`TENANT_ID`) is not part of the README spec. The compose project label is
set by the tenant prefix alone.

**Fix:** Container names must be `${TENANT_PREFIX}-postgres`,
`${TENANT_PREFIX}-redis`, etc. Remove the `${PREFIX}-` wrapper.
Verify that `TENANT_PREFIX` is written to `platform.conf` by Script 1
(it is defined in the README §5 canonical key list).

---

### BUG-12 — Script 3 LiteLLM health endpoint is wrong (README §6 Script 3)

**File:** `3-configure-services.sh` — `configure_litellm()`

**Current behaviour:**
```bash
curl -s "$litellm_url/health"
```

**README requirement (§6, Script 3):**
> LiteLLM: Health check via `GET /health/liveliness` (not `/health`).

**Fix:** Change the health check URL to `${litellm_url}/health/liveliness`.

---

### BUG-13 — Script 3 pulls a hardcoded model (`llama2`) rather than `OLLAMA_DEFAULT_MODEL` (README P1)

**File:** `3-configure-services.sh` — `configure_ollama()`

**Current behaviour:**
```bash
docker exec "$container_name" ollama pull llama2
```

**README requirement (P1 + §5):** `OLLAMA_DEFAULT_MODEL` is defined in
`platform.conf`. Script 3 sources `platform.conf`. Therefore the model
to pull is `${OLLAMA_DEFAULT_MODEL}`. Hardcoding `llama2` violates P1
(nothing hardcoded in scripts 2, 3, or 0).

**Fix:**
```bash
docker exec "$container_name" ollama pull "${OLLAMA_DEFAULT_MODEL}"
```

---

### BUG-14 — Script 3 `--health-check` flag silently ignores `tenant_id` requirement

**File:** `3-configure-services.sh` — `main()`

**Current behaviour:** After parsing flags, the script sources `platform.conf`
using `tenant_id`. If `tenant_id` is empty (e.g. user runs
`bash 3-configure-services.sh --health-check` without a tenant arg), the
source path becomes `/mnt//config/platform.conf` and the script may silently
succeed with empty variables.

**Fix:** Validate that `tenant_id` is non-empty before sourcing `platform.conf`,
regardless of which flags are set. Fail immediately with a clear message if
`tenant_id` is not provided.

---

### BUG-15 — Script 1 did not run interactively (Assessment doc — core issue)

**File:** `1-setup-system.sh` (not submitted, but evidenced by the assessment)

The SCRIPT1_OUTPUT_ASSESSMENT.md reveals that Script 1 collected inputs
(Tenant ID, ports, service enablement, etc.) and produced `platform.conf`.
However the assessment was generated non-interactively — the values appear
to have been either defaulted or injected, not typed by a human at a terminal.

**This is not a bug in scripts 2, 3, or 0.** It is a constraint on how
Script 1 must be run: **interactively, in a real terminal, by a human.**

Windsurf must not attempt to simulate, mock, or auto-populate Script 1's
prompts. Script 1 must use `read` for every prompt. If Windsurf is asked to
test Script 1 in a non-interactive environment, it must stop and report that
the test requires a human operator.

---

## Part 2 — Patterns Windsurf Must Never Introduce

These are taken directly from README Appendix A. Treat each as a hard lint
rule. If Windsurf generates any of these patterns, it has made an error and
must self-correct before submitting.

| Pattern | Why it is prohibited |
|---|---|
| `jq '.key' some-file.json` reading platform state | P1: `platform.conf` is the only source of truth. Source it. |
| `cat > .env << EOF` writing secrets | P4: No `.env` files. Ever. |
| `env_file: - .env` in compose | P4: No `.env` files. Ever. |
| `envsubst` on any generated file | P5: Double-expansion corrupts `$`-containing secrets. |
| `"${PORT}:4000"` (no `127.0.0.1:`) | P6: All ports bind to `127.0.0.1` except the proxy. |
| `for service in "${array[@]}"; do echo ... >> compose.yml` | P3: No loop-based compose generation. |
| `generate_service_block "postgres" >> compose.yml` | P3: No fragment appending from subshells. |
| `docker system prune` in script 0 | README §6: Scoped removal only. |
| `mission-control.json`, `config.json`, `platform.json` | A1: These files must never exist as runtime artifacts. |
| `$RANDOM` or `date` seeds for secret generation | P11/§11: Always `openssl rand`. |
| Named Docker volumes (`volumes:` at compose top level) | P10: Bind mounts only, under `${DATA_DIR}`. |
| `user: root` on any container | P7: All containers run as `${PUID}:${PGID}`. |
| Ports without `127.0.0.1:` prefix on non-proxy services | P6: Hard requirement. |

---

## Part 3 — Mandatory Implementation Checklist

Before submitting any revised scripts, Windsurf must verify every item.
Do not mark a box unless the code literally contains what is described.

### Script 0

- [ ] Sources `platform.conf` before any cleanup operation
- [ ] Confirmation phrase is exactly `DELETE ${TENANT_ID}`
- [ ] Cleanup order matches README §6 exactly (compose down → images → data → config → .configured → logs → network)
- [ ] Uses `docker compose -f "${COMPOSE_FILE}" down --volumes --remove-orphans`
- [ ] Image removal uses scoped label filter AND prefix filter (no `docker system prune`)
- [ ] `${CONFIGURED_DIR}` is explicitly removed (step 6)
- [ ] Network removal uses `|| true` (non-fatal)
- [ ] `--dry-run` uses the `run_cmd()` pattern from README §12
- [ ] `set -euo pipefail` on line 2

### Script 2

- [ ] First action after shebang/pipefail: `source "${PLATFORM_CONF}"`
- [ ] `PLATFORM_CONF` path is `/mnt/${tenant_id}/platform.conf`
- [ ] `generate_compose()` uses explicit `if/fi` heredoc blocks only (no loops, no subshell appending)
- [ ] All container names follow `${TENANT_PREFIX}-<service>` format
- [ ] All ports use `127.0.0.1:${PORT}:internal` format
- [ ] All containers have `user: "${PUID}:${PGID}"`
- [ ] All containers have `restart: unless-stopped`
- [ ] All volumes use bind mounts under `${DATA_DIR}`
- [ ] `depends_on` blocks are built conditionally (disabled services never referenced)
- [ ] Execution order: generate_compose → validate_compose → generate_litellm_config → generate_caddyfile → pull → validate_caddyfile → up -d → wait_for_health
- [ ] `scan_for_sentinels()` runs before deploy
- [ ] `wait_for_health()` is implemented and called for each enabled service
- [ ] LiteLLM config includes only non-empty API key providers
- [ ] LiteLLM ollama `api_base` uses container name: `http://${TENANT_PREFIX}-ollama:11434`
- [ ] No `.env` files written
- [ ] `--dry-run` uses `run_cmd()` pattern
- [ ] `set -euo pipefail` on line 2

### Script 3

- [ ] Sources `platform.conf` as first action
- [ ] `verify_containers_healthy()` called before any `configure_*` function
- [ ] LiteLLM health check uses `/health/liveliness`
- [ ] Ollama model pull uses `${OLLAMA_DEFAULT_MODEL}`, not a hardcoded name
- [ ] `tenant_id` validated non-empty before sourcing `platform.conf`
- [ ] `--verify-only`, `--health-check`, `--show-credentials`, `--rotate-keys` all implemented
- [ ] `show_credentials()` omits disabled services entirely
- [ ] `set -euo pipefail` on line 2

---

## Part 4 — How to avoid circular regressions

The root cause of Windsurf's circular behaviour is that it treats each fix
session as a fresh creative problem rather than a bounded implementation
task. To break the cycle:

1. **Read the README before writing any code.** Not a summary of it — the
   actual document. The README is in the repo root.

2. **Cross-reference every function you write against the README.**
   If a function name doesn't appear in the README or Appendix B, ask
   whether it belongs in this script at all.

3. **Do not "improve" the README's patterns.** If the README says use a
   heredoc, use a heredoc. Do not refactor it into a helper function.
   If the README says `DELETE ${TENANT_ID}`, that string is the confirmation.
   Do not change it to `NUKE-*` because it "sounds clearer".

4. **The README's Appendix F lists every known failure mode with its fix.**
   Before implementing anything, check Appendix F first. If the symptom
   you are solving is listed there, use the fix stated. Do not invent a
   different fix.

5. **After implementing, run the checklist in Part 3 of this document.**
   Every unchecked box is a bug. Do not submit with unchecked boxes.

6. **Script 1 must always be run interactively.** Do not attempt to drive it
   programmatically. If a test environment cannot support interactive input,
   provide a pre-populated `platform.conf` for test purposes only, and
   document clearly that Script 1 was not exercised in that test.

---

*This document is derived solely from README v2.1.0 and the submitted script
files. It makes no recommendations that are not grounded in the README.
If the README changes, this document must be regenerated.*