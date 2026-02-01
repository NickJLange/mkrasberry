# Codebase Optimization and Dead Branch Analysis

## Executive Summary

This analysis identifies opportunities to optimize and simplify the mkrasberry codebase by removing dead branches, consolidating duplicate functionality, and cleaning up unused or broken references.

## Critical Issues

### 1. Broken Symlink in Makefile
**Location**: [`Makefile`](../Makefile:38)
**Issue**: Line 38 references `playbooks/internal_certs_update_endpoints.yml` which is a broken symlink pointing to `../../overlord/ansible/playbooks/internal_certs_update_endpoints.yml` (target does not exist)
**Impact**: The `make configure` command will fail at this step
**Recommendation**: 
- Remove the broken symlink: `rm playbooks/internal_certs_update_endpoints.yml`
- Remove line 38 from Makefile, or comment it out with explanation
- If the functionality is needed, implement it directly or fix the symlink target

### 2. Non-existent Makefile Target
**Location**: [`AGENTS.md`](../AGENTS.md:49)
**Issue**: Documents `make configure_dns` command which doesn't exist in Makefile
**Impact**: Misleading documentation
**Recommendation**: Remove this line from AGENTS.md or implement the missing target

## Duplicate Playbooks

### 3. Duplicate Podman Installation Playbooks
**Files**: 
- [`playbooks/podman-install.yml`](../playbooks/podman-install.yml)
- [`playbooks/podman-ecosystem-install.yml`](../playbooks/podman-ecosystem-install.yml)

**Analysis**: Both files are identical - they call the same role `podmanSetupRaspberryPi`
**Recommendation**: 
- Keep `podman-install.yml` (shorter, clearer name)
- Delete `podman-ecosystem-install.yml`
- Search for any references to the deleted file and update them

### 4. Overlapping Backup/Restore Functionality
**Old approach**:
- [`playbooks/wireguard-backup.yml`](../playbooks/wireguard-backup.yml) - WireGuard-specific backup
- [`playbooks/wireguard-restore.yml`](../playbooks/wireguard-restore.yml) - WireGuard-specific restore

**New approach** (from consolidate-open-work.md):
- [`playbooks/backup-services.yml`](../playbooks/backup-services.yml) - Multi-service backup
- [`playbooks/restore-services.yml`](../playbooks/restore-services.yml) - Multi-service restore
- [`playbooks/restore-wireguard-only.yml`](../playbooks/restore-wireguard-only.yml) - Selective restore
- [`playbooks/restore-pihole-only.yml`](../playbooks/restore-pihole-only.yml) - Selective restore
- [`playbooks/restore-homeassistant-only.yml`](../playbooks/restore-homeassistant-only.yml) - Selective restore

**Recommendation**: 
- **Keep**: New backup system (backup-services.yml, restore-services.yml, restore-*-only.yml)
- **Delete**: Old backup playbooks (wireguard-backup.yml, wireguard-restore.yml)
- **Rationale**: New system is more comprehensive and handles multiple services

### 5. Variant Stage-1 Playbooks
**Files**:
- [`playbooks/initial-playbook-stage-1.yml`](../playbooks/initial-playbook-stage-1.yml) - Standard
- [`playbooks/initial-playbook-stage-1-cloud.yml`](../playbooks/initial-playbook-stage-1-cloud.yml) - Cloud variant
- [`playbooks/initial-playbook-stage-1-nuk.yml`](../playbooks/initial-playbook-stage-1-nuk.yml) - NUK variant

**Analysis**: 
- Cloud variant has custom SSH key path configuration
- NUK variant includes `cron` package and complete symlink attributes
- Standard version is used in Makefile

**Recommendation**: 
- **Keep all three** if they serve different deployment scenarios
- **Document** in AGENTS.md when to use each variant
- **Consider**: Consolidating with conditional logic based on host groups if differences are minimal

## Potentially Unused Playbooks

### 6. Playbooks Not Referenced in Makefile or Documentation

The following playbooks are not referenced in the Makefile or AGENTS.md:

**Service Installation** (may be used manually):
- `awtrix2-install.yml` - AWTRIX2 display service
- `epgstation.yml` - TV recording service (Japan-specific?)
- `homebridge-install.yml` - HomeKit bridge
- `jellyfin.container` - Media server
- `mqtt-install.yml` - MQTT broker (superseded by mosquitto.container?)
- `nomad-install.yml` - HashiCorp Nomad orchestration
- `teleport-service-install.yml` - Teleport access platform
- `tvtuner-install.yml` - TV tuner setup
- `vault-install.yml` - HashiCorp Vault
- `wifiServer-install.yml` - WiFi server setup

**Maintenance/Refresh** (may be used manually):
- `datadog-fix.yml` - Datadog troubleshooting
- `defenseshield-install.yml` - Firewall setup
- `defenseshield-refresh.yml` - Firewall refresh
- `msmtp-refresh-config.yml` - Email config refresh
- `phone-home-refresh.yml` - Phone home refresh
- `telegraf-service-install.yml` - Metrics collection
- `telegraf-service-refresh-config.yml` - Metrics config refresh
- `unbound-refresh-install.yml` - DNS resolver refresh
- `unbound-refresh-localzone.yml` - DNS local zone refresh
- `unbound-status-check.yml` - DNS status check

**WireGuard Management**:
- `wireguard-add-client.yml` - Add VPN client
- `wireguard-client-install.yml` - Client setup
- `wireguard-server-install.yml` - Server setup
- `wireguard-refresh-server-clients.yml` - Refresh configs

**Other**:
- `install-personal-local-utils.yml` - Personal utilities (copies 'sub' script)

**Recommendation**: 
- **Audit**: Review each playbook to determine if it's still needed
- **Document**: Add commonly-used manual playbooks to AGENTS.md
- **Archive**: Move truly unused playbooks to an `archive/` directory
- **Delete**: Remove playbooks for deprecated services

## Stale Branches (from consolidate-open-work.md)

### 7. Local Branches to Delete
Per the approved consolidation spec, these branches should be deleted:
- `2025_q4_updates` - Work already in feature/backup-services
- `december_23_update` - HomeAssistant prototype (superseded)
- `november_update` - Duplicates PR #24
- `update-phone-home-role` - WIP syslog/Datadog (abandoned)

**Recommendation**: Execute Phase 5 of consolidate-open-work.md

### 8. Stale Pull Requests
- PR #26 (`december_catchup`) - Stale since Dec 2023
- PR #24 (`july_update`) - Stale since Aug 2023

**Recommendation**: Execute Phases 3-4 of consolidate-open-work.md (rebase or close)

## Code Quality Issues

### 9. Inconsistent Host Pattern
**Issue**: Most playbooks use `{{ hostlist | default('do_not_match_ever')}}` but some use `{{ hostlist }}`
**Files with inconsistent pattern**:
- `wireguard-backup.yml` - Uses `{{ hostlist }}` without default
- `install-personal-local-utils.yml` - Uses `{{ hostlist }}` without default

**Recommendation**: Standardize all playbooks to use the safe default pattern

### 10. README.md is Minimal
**Location**: [`README.md`](../README.md)
**Issue**: Contains only "Hello world" and 2 TODOs
**Recommendation**: 
- Expand README.md with project overview from AGENTS.md
- Keep AGENTS.md for AI-specific guidance
- Add setup instructions, prerequisites, and quick start guide

## Submodule Issues (from consolidate-open-work.md)

### 11. Missing .gitmodules Entry
**Issue**: `roles/mosquitto.container` missing from .gitmodules
**Recommendation**: Execute Phase 1 of consolidate-open-work.md

### 12. Submodule State Issues
- `mkrasberry_config` - 2 commits ahead, uncommitted changes
- `roles/ansible-phoneHome` - 2 commits behind, uncommitted changes

**Recommendation**: Execute Phase 1 of consolidate-open-work.md

## Optimization Opportunities

### 13. Consolidate Stage-1 Variants
**Opportunity**: The three stage-1 playbooks have minimal differences
**Recommendation**: 
- Create a single stage-1 playbook with conditional logic based on host groups
- Use Ansible's `group_vars` to define environment-specific settings
- Reduces maintenance burden and ensures consistency

### 14. Extract Common Tasks
**Opportunity**: Many playbooks repeat similar patterns (timezone setup, package installation)
**Recommendation**:
- Create reusable task files in `playbooks/tasks/common/`
- Use `include_tasks` to reduce duplication
- Examples: `setup-timezone.yml`, `install-base-packages.yml`

### 15. Standardize Container Roles
**Observation**: Container roles follow a pattern but with variations
**Recommendation**:
- Document the standard pattern in AGENTS.md (already partially done)
- Create a role template or generator script
- Audit existing container roles for compliance

## Priority Recommendations

### High Priority (Breaking Issues)
1. **Fix broken symlink** in Makefile (line 38)
2. **Remove duplicate** podman-ecosystem-install.yml
3. **Update AGENTS.md** to remove non-existent `configure_dns` target

### Medium Priority (Cleanup)
4. **Delete old backup playbooks** (wireguard-backup.yml, wireguard-restore.yml)
5. **Execute consolidate-open-work.md** phases (branch cleanup, submodule fixes)
6. **Standardize host patterns** in all playbooks
7. **Expand README.md** with proper documentation

### Low Priority (Optimization)
8. **Audit unused playbooks** and archive/delete as appropriate
9. **Document manual playbooks** in AGENTS.md
10. **Consider consolidating** stage-1 variants
11. **Extract common tasks** to reduce duplication

## Implementation Plan

### Phase 1: Critical Fixes (Immediate)
```bash
# Remove broken symlink
rm playbooks/internal_certs_update_endpoints.yml

# Update Makefile - comment out line 38
# Update AGENTS.md - remove configure_dns reference

# Delete duplicate playbook
rm playbooks/podman-ecosystem-install.yml
```

### Phase 2: Backup System Cleanup (After feature/backup-services merge)
```bash
# Delete old backup playbooks
rm playbooks/wireguard-backup.yml
rm playbooks/wireguard-restore.yml
```

### Phase 3: Branch Cleanup (Per consolidate-open-work.md)
```bash
# Delete stale local branches
git branch -D 2025_q4_updates december_23_update november_update update-phone-home-role
```

### Phase 4: Documentation Updates
- Expand README.md
- Update AGENTS.md with manual playbook usage
- Document stage-1 variant usage

### Phase 5: Code Quality (Ongoing)
- Standardize host patterns
- Extract common tasks
- Audit and archive unused playbooks

## Verification Checklist

- [ ] Makefile executes without errors
- [ ] All symlinks resolve correctly
- [ ] No duplicate functionality exists
- [ ] Documentation matches actual code
- [ ] All playbooks use consistent patterns
- [ ] Submodules are in clean state
- [ ] No orphaned branches exist
- [ ] README.md provides adequate project overview

## Questions for Review

1. Are the variant stage-1 playbooks still needed, or can they be consolidated?
2. Which of the "unused" playbooks are actually used manually and should be documented?
3. Should archived playbooks be moved to a separate branch or deleted entirely?
4. Is the `install-personal-local-utils.yml` playbook still needed? What is the 'sub' script?
5. Are services like Nomad, Teleport, and Vault actively used or planned?
