# VRRP Smoke Tests

Rootless VRRP testing using Linux namespaces.

## Quick Start

```bash
cd tests/vrrp-smoke-test

# Fast syntax check
./test-configs-only.sh

# Full failover test (requires keepalived installed)
./test-vrrp-unshare.sh
```

## Requirements

- Linux with user namespace support (`/proc/sys/kernel/unprivileged_userns_clone` = 1)
- `keepalived` binary installed
- `unshare` from util-linux
- `ip` command (iproute2)

## How It Works

Uses `unshare --user --map-root-user` to create isolated namespaces where:
- Current user is mapped to root inside namespace
- keepalived runs with necessary "root" permissions
- VRRP communicates via unicast on loopback interfaces (127.99.0.x)
- No privileged network operations required on host

## Limitations

- Uses unicast instead of multicast (VRRP still works)
- Cannot test actual VIP movement on real interfaces
- Recovery/preemption test is simplified (backup stays master)

## Production Config Testing

To test actual production configs:

1. Copy configs from archive:
   ```bash
   cp openspec/changes/archive/2026-03-01-dns-keepalived-analysis/specs/dns-ha-analysis/*.conf tmp/
   ```

2. Modify for testing:
   - Change Virtual Router IDs to 99
   - Change VIPs to 127.99.0.2
   - Change interfaces to 'lo'
   - Add unicast configuration

3. Run validation:
   ```bash
   KEEPALIVED_BIN=/usr/sbin/keepalived ./test-vrrp-unshare.sh
   ```
