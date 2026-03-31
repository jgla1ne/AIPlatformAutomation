# Windsurf Implementation Plan - Attempt 3 Code Review Fixes
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Based on: doc/CLAUDE.md Attempt 3 Code Review
# Target: README v5.1.0 Compliance

## 📋 EXECUTIVE SUMMARY

The CLAUDE.md Attempt 3 Code Review has identified **16 critical failures** across all 4 scripts that must be fixed to achieve true README v5.1.0 compliance. The previous DEPLOYMENT_ASSESSMENT.md claimed 100% compliance incorrectly due to unexpanded shell variables and insufficient testing.

## 🎯 IMPLEMENTATION PLAN

### Phase 1: Critical Path Fixes (High Priority)

#### Script 0: Nuclear Cleanup (2 fixes)
1. **FAILURE 1**: Add root execution check (README P7 exception)
   - Add `if [[ $EUID -ne 0 ]]` check after `set -euo pipefail`
   - Script 0 MUST run as root, unlike other scripts

2. **FAILURE 2**: Fix platform.conf path (README P1)
   - Change `/mnt/${tenant_id}/config/platform.conf` to `/mnt/${tenant_id}/platform.conf`
   - Apply to ALL scripts (0, 2, 3)

#### Script 1: System Compiler (6 fixes)
3. **FAILURE 3**: Fix variable ordering in `write_platform_conf()`
   - Define local variables before using them in `litellm_db_url`
   - Remove dependency on undefined variables

4. **FAILURE 4**: Fix yq architecture mapping
   - Map `x86_64` → `amd64`, `aarch64` → `arm64`
   - Add error handling for unsupported architectures

5. **FAILURE 5**: Fix subshell capture pattern in `collect_service_flags()`
   - Replace `$(prompt_yesno ... && echo "true" || echo "false")` with `if/else`
   - Apply to all 15 services in both preset and custom modes

6. **FAILURE 6**: Remove tenant_id argument bypass
   - Always call `collect_tenant_config()` interactively
   - Remove argument short-circuit that skips interactive collection

7. **FAILURE 7**: Fix main() execution order
   - Ensure `collect_tenant_config()` runs before platform.conf existence check
   - Fix variable ordering dependencies

8. **FAILURE 11**: Prompt for Signal phone numbers
   - Replace hardcoded `+15551234567` with interactive prompts
   - Validate E.164 format and non-empty values

9. **FAILURE 12**: Add Caddy ports to platform.conf
   - Add `CADDY_HTTP_PORT` and `CADDY_HTTPS_PORT` to `write_platform_conf()` heredoc

#### Script 2: Atomic Deployer (5 fixes)
10. **FAILURE 2**: Fix platform.conf path (same as Script 0)
    - Change `/mnt/${tenant_id}/config/platform.conf` to `/mnt/${tenant_id}/platform.conf`

11. **FAILURE 8**: Fix `depends_on` inline subshell in heredoc
    - Build complete blocks including key in builder functions
    - Use single variable expansion in heredoc, not subshell calls

12. **FAILURE 9**: Fix `validate_compose()` error suppression
    - Capture and display validation errors
    - Add dry-run mode handling

13. **FAILURE 10**: Fix idempotency marker placement
    - Remove markers from fast/config steps (must always re-run)
    - Keep markers only on slow/disruptive steps (pull, deploy, health)

14. **FAILURE 15**: Remove LibreChat (no MongoDB support)
    - Remove LibreChat from `service_enabled_by_preset()`
    - Remove LibreChat compose block entirely
    - Update documentation accordingly

#### Script 3: Mission Control (3 fixes)
15. **FAILURE 2**: Fix platform.conf path (same as Scripts 0 & 2)
    - Change `/mnt/${tenant_id}/config/platform.conf` to `/mnt/${tenant_id}/platform.conf`

16. **FAILURE 13**: Call `verify_containers_healthy` before `rotate_keys`
    - Add health check before key rotation operations
    - Ensure containers exist before restarting them

17. **FAILURE 14**: Fix Authentik authentication
    - Use POST to `/api/v3/core/token/` first
    - Then use Bearer token for subsequent calls
    - Fix sed pattern with `|` delimiter for secrets

### Phase 2: Implementation Strategy

#### Implementation Order
1. **Script 0** (2 fixes) - Critical path fixes
2. **Script 1** (6 fixes) - Foundation fixes affecting all other scripts
3. **Script 2** (5 fixes) - Deployment fixes
4. **Script 3** (3 fixes) - Configuration fixes

#### Testing Strategy
- Fix scripts incrementally
- Test each script individually after fixes
- Run README §14 checkpoints after each phase
- Update DEPLOYMENT_ASSESSMENT.md with real execution results

#### Validation Requirements
- All shell variables must expand properly in assessment document
- All scripts must execute without unbound variable errors
- All README §14 checkpoints must pass
- No prohibited patterns from Appendix A

### Phase 3: Documentation Updates

#### DEPLOYMENT_ASSESSMENT.md Updates
- Regenerate with actual executed commands
- Ensure all shell variables are expanded
- Include real test results from README §14 checkpoints
- Remove any false compliance claims

#### README.md Updates
- Remove LibreChat from service catalogue
- Update preset descriptions to reflect removed service
- Ensure all documentation matches implementation

## 🔧 TECHNICAL IMPLEMENTATION DETAILS

### Critical Path Dependencies
- Script 1 fixes must be completed first (variable definitions)
- platform.conf path fixes affect all 3 scripts (0, 2, 3)
- LibreChat removal affects preset logic and compose generation

### Risk Mitigation
- Test each fix individually before proceeding
- Maintain backup of working scripts
- Use feature branches for major changes
- Validate with README §14 checkpoints

### Success Criteria
- All 16 failures resolved
- All scripts execute without errors
- All README §14 checkpoints pass
- DEPLOYMENT_ASSESSMENT.md shows real execution results
- True README v5.1.0 compliance achieved

## 📊 IMPLEMENTATION TRACKING

### Status Matrix
| Script | Failures | Status | Priority |
|--------|-----------|---------|----------|
| 0-complete-cleanup.sh | 2 | Pending | High |
| 1-setup-system.sh | 6 | Pending | High |
| 2-deploy-services.sh | 5 | Pending | High |
| 3-configure-services.sh | 3 | Pending | High |

### Next Steps
1. Implement Script 0 fixes (2 failures)
2. Implement Script 1 fixes (6 failures) 
3. Implement Script 2 fixes (5 failures)
4. Implement Script 3 fixes (3 failures)
5. Test complete deployment workflow
6. Update DEPLOYMENT_ASSESSMENT.md with real results
7. Final validation against README §14

---

**This plan addresses all 16 identified failures in CLAUDE.md Attempt 3.**
**Implementation will proceed in priority order to achieve true README v5.1.0 compliance.**
