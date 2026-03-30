Reading both documents before writing anything.

Reading: https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/doc/BULLETPROOF_REFACTOR_PLAN.md

Reading: https://raw.githubusercontent.com/jgla1ne/AIPlatformAutomation/refs/heads/main/README.md

---

# Review: BULLETPROOF_REFACTOR_PLAN.md against README

## Overall verdict

The plan is **structurally sound** but contains **14 material conflicts with the README**, **6 over-engineered additions not in scope**, and **9 genuine gaps the plan correctly identifies**. Each is documented below with the exact README clause it conflicts with or supports.

---

## Section-by-section review

---

### 1. "Core Principles" (plan lines 1–28)

**Aligned:**
- Non-root enforcement ✓
- `set -euo pipefail` ✓
- `platform.conf` as single source of truth ✓
- Idempotency markers in `.configured/` ✓
- Layered startup order ✓
- Bind mounts only, no named volumes ✓

**Conflict 1 — secret storage location**

Plan states:
> "All secrets stored in platform.conf with 600 permissions"

README states:
> "All secrets in `platform.conf` (chmod 600). Never in compose files, never in environment files checked into git."

The plan's implementation section later generates a `.env` file alongside `docker-compose.yml` and passes it via `env_file:` in the compose block. This directly contradicts the README. The README model is: secrets go into `platform.conf`, script 2 renders them **inline** into `docker-compose.yml` (which is itself under `/mnt/${TENANT_ID}/` with appropriate permissions), never into a separate `.env` file. Remove the `.env` file approach entirely.

**Conflict 2 — compose file location**

Plan states compose file goes to `${BASE_DIR}/docker-compose.yml`

README states:
> Generated files go to `/mnt/${TENANT_ID}/compose/docker-compose.yml`

Use the README path. This matters because script 3 and script 0 both reference the compose file location.

---

### 2. "Script 1 Refactor" (plan lines 29–98)

**Genuine gap correctly identified:**
- Port conflict detection per service ✓
- `STACK_PRESET` pre-populating `*_ENABLED` flags ✓
- `PLATFORM_ARCH` detection ✓
- E.164 validation for Signal phone number ✓
- `gen_password` vs `gen_secret` distinction ✓

**Conflict 3 — preset definitions**

Plan defines presets as:
```
minimal: openwebui + litellm + ollama + qdrant
dev:     minimal + n8n + flowise + dify
full:    all services
```

README defines presets as:
```
minimal: core infrastructure + one LLM proxy + one vector DB + Open-WebUI
dev:     minimal + workflow (n8n or flowise) + one coding assistant
full:    all enabled
custom:  user selects every service
```

The plan's `minimal` hardcodes Qdrant. The README explicitly says "one vector DB" — meaning the user still chooses which vector DB even in minimal preset. Fix: preset sets `VECTOR_DB_COUNT=1` and prompts which one, it does not hardcode Qdrant.

**Conflict 4 — LLM proxy in presets**

Plan's minimal preset hardcodes LiteLLM. README says "one LLM proxy" — user still selects LiteLLM or Bifrost. Fix same as above.

**Conflict 5 — input validation scope**

Plan adds regex validation for `BASE_DOMAIN` and `TLS_EMAIL`. README does not specify this. This is fine to add **but** the plan's regex for BASE_DOMAIN:
```
^[a-zA-Z0-9][a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}$
```
rejects valid domains like `ai.example.co.uk` (two-part TLD). Use a looser check: must contain at least one dot, no spaces, no leading hyphen.

**Conflict 6 — SA JSON file prompt**

Plan adds prompt for gdrive-sa JSON path. Correct. However the plan stores the path as `RCLONE_SA_JSON_PATH` but the README's `platform.conf` reference section uses `RCLONE_GDRIVE_SA_CREDENTIALS_FILE`. Use the README key name.

---

### 3. "Script 2 Refactor" (plan lines 99–210)

**Genuine gaps correctly identified:**
- Azure `api_version` in LiteLLM config ✓
- Bifrost config generation ✓
- Weaviate port in Caddyfile ✓
- Dify-api healthcheck for depends_on ✓
- `runtime: nvidia` for Ollama ✓
- AnythingLLM volume mount ✓
- rclone cron entry ✓
- Mission Control disabled service display ✓

**Conflict 7 — Milvus compose block**

Plan implements Milvus as a single `milvus-standalone` container. Milvus standalone mode requires three containers: `etcd`, `minio`, and `milvus` itself. The README lists Milvus as a supported vector DB without specifying architecture, but any Milvus standalone deployment that omits etcd and minio will fail to start. The plan must include all three containers in the compose block, or explicitly document that it uses an embedded etcd/minio mode (which does not exist in Milvus stable releases).

**Conflict 8 — wait_for_health fallback**

Plan's fallback checks `State.Running` after `Health.Status` fails. Correct direction. However the plan uses:
```bash
docker inspect --format='{{.State.Running}}' "${container}"
```
This returns `true` even for a container that started and immediately exited (exit code 0). Use:
```bash
docker inspect --format='{{.State.Status}}' "${container}"
```
and check for `running`, not just non-empty.

**Conflict 9 — Authentik bootstrap token sequencing**

Plan acknowledges the sequencing issue and moves `AUTHENTIK_BOOTSTRAP_TOKEN` into the compose env block. Correct. However the plan's implementation still calls `authentik worker` setup from script 3. The Authentik bootstrap token approach means the initial admin password is set via `AUTHENTIK_BOOTSTRAP_PASSWORD` env var at first start — script 3 should **not** attempt to call the Authentik API to create an admin user if the bootstrap env vars are set; it should only verify the bootstrap worked. The plan does not reflect this distinction.

**Conflict 10 — .env file generation (repeated from Conflict 1)**

The plan's script 2 section generates `/mnt/${TENANT_ID}/compose/.env` and references it from `docker-compose.yml`. As stated above: prohibited by README. All values must be rendered inline.

**Conflict 11 — post-deploy validation placement**

Plan places post-deploy validation at the end of script 2. README places it explicitly as the last step of script 2 **and** says script 3 re-runs it at the start before attempting any configuration. The plan's script 3 does not include a pre-flight health check of the running stack before attempting API calls. Add it.

---

### 4. "Script 3 Refactor" (plan lines 211–340)

**Genuine gaps correctly identified:**
- `--rotate-keys` writing back to `platform.conf` ✓
- Container name prefix fix ✓
- LiteLLM endpoint fix (`/model/new`) ✓
- Dify idempotency check ✓
- Grafana provisioning path fix ✓
- `--reload-proxy` Caddy vs nginx distinction ✓
- Signal container exec vs host CLI ✓

**Conflict 12 — `--show-credentials` masking**

Plan adds a warning header. Good. But the plan then outputs credentials to stdout with no masking option. README section on credentials states:
> "Credentials are printed once at the end of script 3 and also accessible via `./3-configure-services.sh --show-credentials`"

The README does not require masking, just the warning. The plan's warning header is sufficient. No conflict here — minor note only.

**Conflict 13 — `--ingest-delta` checksum file location**

Plan writes checksums to `ingest/done/manifest.sha256`. Correct approach. However the plan uses `sha256sum` which is not available on macOS (where the equivalent is `shasum -a 256`). Since the README targets Ubuntu 22.04 LTS exclusively, `sha256sum` is correct. Add a pre-flight check that `sha256sum` is available, which it will be on any Ubuntu install, but the check makes the dependency explicit.

**Conflict 14 — `--rotate-keys` scope**

Plan rotates all secrets when `--rotate-keys` is called. README states:
> "`--rotate-keys [service]` — rotate credentials for one or all services"

The plan does not implement the optional `[service]` argument — it only supports rotating all secrets. This must be implemented: `--rotate-keys litellm` should only regenerate LiteLLM keys and restart the LiteLLM container, not trigger a full stack restart.

---

### 5. "Script 0 Refactor" (plan lines 341–390)

**Genuine gaps correctly identified:**
- Volume filter pattern fix ✓
- Cron entry removal ✓
- systemd mount unit removal ✓
- Typed tenant ID confirmation ✓

**Conflict 15 — `--remove-images` flag**

Plan implements `--remove-images`. README spec includes this flag explicitly. The plan's implementation uses `docker rmi $(docker images --filter reference="*${TENANT_ID}*" -q)`. This filter is too broad — it would match images whose name contains the tenant ID string, which on a shared host could remove images belonging to other tenants or system images if the tenant ID is a common word. Use explicit image names sourced from `platform.conf` service image variables, or filter by compose project label: `docker images --filter label=com.docker.compose.project=${DOCKER_NETWORK}`.

**Over-engineering item 1 — `--remove-images` prompt**

Plan prompts for confirmation before removing images even when `--confirm-destroy` is already set. One confirmation is enough. If `--confirm-destroy` is set and typed confirmation matches, proceed with all destructive actions including image removal if `--remove-images` is also set.

---

### 6. "Dry-run implementation" (plan lines 391–430)

**Aligned with README:** README explicitly requires `--dry-run` on all scripts.

**Over-engineering item 2 — temp dir for dry-run**

Plan writes generated files to `/tmp/dry-run-${TENANT_ID}/` during dry-run. Good. But the plan then runs `docker compose config` against the dry-run output as a validation step. This requires docker to be available and the compose file to reference no local build contexts. Since all services use pre-built images this works, but the plan should note this dependency explicitly so it is not broken by adding a `build:` context later.

---

### 7. "Static validation framework" (plan lines 431–510)

**Aligned with README:** README requires framework-tested end result before first run.

**Over-engineering item 3 — Python YAML validation**

Plan uses `python3 -c "import yaml..."` to validate `litellm/config.yaml`. Python3 is not in the README's required dependencies list. Use `yq` (already required for some config operations) or validate with the LiteLLM container itself:
```bash
docker run --rm -v /tmp/litellm:/app/config \
  ghcr.io/berriai/litellm:main-latest \
  litellm --config /app/config/config.yaml --test
```
Alternatively keep python3 but add it to the pre-flight dependency check.

**Over-engineering item 4 — CI/CD pipeline definition**

Plan includes a GitHub Actions workflow definition. README does not mention CI/CD. Out of scope for this implementation. Remove.

**Over-engineering item 5 — Makefile targets**

Plan includes `make test`, `make dry-run`, etc. README does not mention a Makefile. Out of scope. Remove.

**Over-engineering item 6 — `scripts/lib/` shared library**

Plan proposes extracting shared functions (logging, pre-flight checks, secret generation) into `scripts/lib/common.sh` sourced by all scripts. This is architecturally sound but the README does not specify it and introduces a new deployment dependency: all four scripts now fail if `lib/common.sh` is not present at the expected relative path. The README's design is that each script is independently executable. If shared functions are extracted, each script must either:
(a) source `lib/common.sh` with a clear error if not found, or
(b) inline the shared functions with a note that they are duplicated by design for standalone operation.

Option (b) is more consistent with the README's standalone-script philosophy. The plan should clarify which approach is taken.

---

## Summary table

| # | Item | Plan status | Verdict |
|---|------|-------------|---------|
| C1 | .env file prohibited by README | Plan generates .env | **Fix required** |
| C2 | Compose file path | Plan uses wrong path | **Fix required** |
| C3 | Preset does not hardcode vector DB | Plan hardcodes Qdrant | **Fix required** |
| C4 | Preset does not hardcode LLM proxy | Plan hardcodes LiteLLM | **Fix required** |
| C5 | BASE_DOMAIN regex rejects valid domains | Plan regex too strict | **Fix required** |
| C6 | SA JSON key name mismatch | Plan uses wrong key | **Fix required** |
| C7 | Milvus needs 3 containers | Plan uses 1 | **Fix required** |
| C8 | State.Running vs State.Status | Plan uses wrong field | **Fix required** |
| C9 | Authentik bootstrap vs API creation | Plan conflates both | **Fix required** |
| C10 | .env file (repeated) | Same as C1 | **Fix required** |
| C11 | Script 3 pre-flight health check missing | Plan omits it | **Fix required** |
| C12 | --show-credentials | Plan aligned | Minor note |
| C13 | sha256sum on Ubuntu only | Plan aligned | Minor note |
| C14 | --rotate-keys [service] arg missing | Plan omits per-service | **Fix required** |
| C15 | --remove-images filter too broad | Plan filter dangerous | **Fix required** |
| OE1 | Double confirmation on --remove-images | Redundant | Remove |
| OE2 | dry-run docker compose config note | Minor | Clarify |
| OE3 | python3 not in dependencies | Out of scope | Replace with yq |
| OE4 | GitHub Actions workflow | Out of scope | Remove |
| OE5 | Makefile | Out of scope | Remove |
| OE6 | scripts/lib/ shared library | Needs clarification | Clarify approach |
| G1–G9 | Genuine gaps correctly identified | Plan correct | Implement as written |

---

## Recommended action

The plan needs **15 fixes** before implementation begins. None are architectural rewrites — they are targeted corrections. The genuine gaps (G1–G9) are correctly identified and the plan's proposed solutions for them are sound.

**Recommended next step:** Produce a corrected version of the plan incorporating all 15 fixes, then proceed directly to implementation in script order: 1 → 0 → 2 → 3.

State which script to implement first and I will write the complete corrected script.