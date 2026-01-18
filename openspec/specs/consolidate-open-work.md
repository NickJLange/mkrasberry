# Consolidate Open Work

## Goal
Merge all open PRs, branches, and submodule updates into master to clean up repository state.

## Current State Analysis

### Open Pull Requests
| PR | Title | Branch | Status |
|----|-------|--------|--------|
| #26 | Holding Commit | `december_catchup` | Stale (Dec 2023) |
| #24 | Makefile/post_install for new bootfs | `july_update` | Stale (Aug 2023) |

### Active Branch: `feature/backup-services`
5 commits ahead of master with backup/restore functionality:
- `aac5b22` fix(datadog): update ansible-datadog role to v5.5.0
- `599d0c1` fix(ansible): resolve type errors in msmtp role and stage-2 playbook
- `95e101a` Add restore-services playbook with in-place service recovery
- `90148d2` Test backup system: create, fetch, restore
- `ebbe675` Update pihole.container submodule: disable DNSSEC

**Uncommitted changes:**
- Deleted: `CLAUDE.md` (replaced by `AGENTS.md`)
- Modified: `Makefile`, `README.md`, playbooks, roles
- Untracked: `AGENTS.md`, restore playbooks, `.gemini/`

### Submodules Requiring Action
| Submodule | Issue | Action |
|-----------|-------|--------|
| `mkrasberry_config` | 2 commits ahead, uncommitted changes | Push commits to origin; uncommitted changes are local env config (keep unstaged) |
| `roles/ansible-phoneHome` | 2 commits behind, uncommitted changes | Create branch, commit cron fix, open PR, merge, then pull origin/master |
| `roles/mosquitto.container` | Missing .gitmodules entry | Fix submodule registration |

### Stale Local Branches
**Keep & Rebase:**
- `fix/msmtp-conditional-and-loop-error` — msmtp fix, restore playbooks, backup testing

**Delete:**
- `2025_q4_updates` — work already in feature/backup-services
- `december_23_update` — HomeAssistant prototype (superseded)
- `november_update` — duplicates PR #24
- `update-phone-home-role` — WIP syslog/Datadog (abandoned)

## Proposed Changes

### Phase 1: Fix Submodule Issues
1. Fix `roles/mosquitto.container` .gitmodules entry
2. **mkrasberry_config**: Push 2 commits to origin (leave uncommitted local config unstaged)
3. **ansible-phoneHome**: 
   - Create branch `fix/cron-user-param`
   - Commit cron fix (removes `user:` param, adds crontab existence check)
   - Open PR to origin/master
   - After merge, pull origin/master

### Phase 2: Complete Current Branch
1. Stage and commit all relevant changes on `feature/backup-services`
2. Create PR for `feature/backup-services` → `master`

### Phase 3: Rebase Stale PRs
1. Rebase PR #26 (`december_catchup`) onto master
2. Rebase PR #24 (`july_update`) onto master

### Phase 4: Rebase Local Branch
1. Rebase `fix/msmtp-conditional-and-loop-error` onto master

### Phase 5: Cleanup
1. Delete merged branches
2. Delete stale local branches: `2025_q4_updates`, `december_23_update`, `november_update`, `update-phone-home-role`

## Verification
- All submodules in clean state: `git submodule status` shows no `+` or `-` prefixes
- `git status` on main repo shows clean working tree
- CI/tests pass on merged master (if applicable)
- No orphaned local branches

## Questions for Review
1. ~~Should stale PRs #24 and #26 be closed or rebased?~~ **RESOLVED**: Rebase both
2. ~~Are the uncommitted submodule changes intentional?~~ **RESOLVED**: mkrasberry_config local-only; ansible-phoneHome to be PR'd
3. ~~Should stale local branches be deleted?~~ **RESOLVED**: Keep & rebase `fix/msmtp-conditional-and-loop-error`; delete others

## Status: APPROVED — Ready for Implementation
