# cert-setup

Creates the unprivileged `certpush` account and makes it the owner of
`/etc/letsencrypt`, so the internal cert-renewal job (lunarBeacon,
`overlord/internal_cert_management`) can push certificates over SSH **without
sudo**. A leaked push key can replace certificates; this account has no sudo
privileges.

Applied in `playbooks/initial-playbook-stage-3.yml`. Run alone with:

    ansible-playbook -e hostlist=HOST_OR_GROUP playbooks/initial-playbook-stage-3.yml --tags cert_setup

Replace `HOST_OR_GROUP` with the target inventory host or group.

## What it does

- Refuses a `cert_dir` containing an `accounts` entry (including symlinks)
  before creating the account or changing ownership or permissions. This role
  manages distributed endpoint certificates, not Certbot issuer state.
- `certpush` system user: home `/var/lib/certpush`, `/bin/sh`, password
  locked, no supplementary groups, no sudo (asserted with `sudo -l -U`).
- `authorized_keys` managed exclusively from `certpush_authorized_keys`.
- `/etc/letsencrypt` and `/etc/letsencrypt/backup`: owner `certpush`, `0755`.
- Existing files under `/etc/letsencrypt`: owner `certpush`, `0644`.
  Hidden files and directories are included; symlinks (`server.cert`,
  `server.key`) are left as they are.

Certs and keys are world-readable on purpose: Home Assistant, Node-RED and
Homebridge (`/etc/letsencrypt` mounted at `/ssl`), Vault, nginx containers and
rsyslog TLS all read them. Changing ownership needs no service restart.

This explicitly accepts that **every local account can read the distributed
TLS private keys**; compromising any local account exposes those keys. Do not
store ACME account credentials or other secrets in this directory. Merely
excluding `accounts/` from the ownership pass would not isolate it: `certpush`
owns its parent and could rename or replace that entry. Use a separate issuer
directory for Certbot state.

## Variables

| Variable | Default | Notes |
|---|---|---|
| `cert_setup_enabled` | `yes` | |
| `certpush_user` | `certpush` | |
| `certpush_home` | `/var/lib/certpush` | |
| `certpush_authorized_keys` | `[]` | **Required.** Set in `group_vars/all.yml`. |
| `certpush_key_options` | `""` | e.g. `from="192.168.100.10"` |
| `cert_dir` | `/etc/letsencrypt` | |
| `cert_backup_dir` | `{{ cert_dir }}/backup` | |
