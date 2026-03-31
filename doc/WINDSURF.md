# Windsurf Implementation Plan - Updated Guidance
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Based on: doc/CLAUDE.md Updated Guidance
# Target: README v5.1.0 Compliance

## 📋 EXECUTIVE SUMMARY

The CLAUDE.md has been updated to provide high-level guidance focused on **preventing circular regressions** rather than detailed technical failure analysis. The new approach emphasizes:

1. **Root Cause Analysis**: Previous iterations failed due to "added abstractions on top of the spec"
2. **Surgical Implementation**: File-by-file, change-by-change instructions only
3. **No Full Rewrites**: Only targeted fixes, no architectural changes
4. **Regression Prevention**: Hard prohibition table and binary acceptance checklist

## 🎯 CURRENT GUIDANCE FROM CLAUDE.md

### Core Principles
- **Read README First**: Not summaries - the actual document in repo root
- **Cross-Reference Every Function**: Check README and Appendix B before implementation
- **No "Improvements"**: Use exact README patterns (heredoc, confirmation phrases, etc.)
- **Check Appendix F**: Use known failure modes and fixes before implementing
- **Mandatory Checklist**: Every unchecked box is a bug

### Prohibited Patterns (Hard Rules)
| Pattern | Why Prohibited |
|---|---|
| `jq '.key' some-file.json` | P1: platform.conf is only source of truth |
| `cat > .env << EOF` | P4: No .env files ever |
| `envsubst` on generated files | P5: Corrupts secrets with $ expansion |
| `"${PORT}:4000"` (no 127.0.0.1) | P6: All ports bind to 127.0.0.1 |
| Loop-based compose generation | P3: Use explicit heredoc blocks only |
| `docker system prune` | README §6: Scoped removal only |
| Named Docker volumes | P10: Bind mounts only under DATA_DIR |
| `user: root` on containers | P7: All containers run as PUID:PGID |

### Implementation Strategy
1. **Phase 1**: Script 0 fixes (if needed)
2. **Phase 2**: Script 1 fixes (if needed) 
3. **Phase 3**: Script 2 fixes (if needed)
4. **Phase 4**: Script 3 fixes (if needed)
5. **Testing**: README §14 checkpoints after each phase
6. **Validation**: Binary acceptance checklist completion

## 🔄 NEXT STEPS

### Immediate Actions
1. **Review Current Implementation**: Check existing scripts against README requirements
2. **Identify Specific Issues**: Look for actual violations vs. guidance
3. **Implement Targeted Fixes**: File-by-file, change-by-change only
4. **Validate Each Fix**: Run README §14 checkpoints
5. **Update Documentation**: Real execution results in DEPLOYMENT_ASSESSMENT.md

### Success Criteria
- All scripts follow README patterns exactly
- No prohibited patterns introduced
- Binary acceptance checklist complete
- README §14 checkpoints pass
- No circular regressions

---

**This plan reflects the updated high-level guidance from CLAUDE.md.**
**Focus is on surgical, targeted fixes rather than architectural changes.**
