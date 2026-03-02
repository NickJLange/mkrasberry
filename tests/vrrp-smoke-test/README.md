# VRRP Smoke Tests

Containerized VRRP testing using Podman with network isolation.

## Quick Start

```bash
cd tests/vrrp-smoke-test

# Fast syntax check (if keepalived is installed)
./test-configs-only.sh

# Full failover test with Podman containers (RECOMMENDED - network isolated)
./test-vrrp-podman.sh

# Rootless test with unshare (alternative, less isolated)
./test-vrrp-unshare.sh
```

## Requirements

- Podman installed and configured
- Linux kernel with network namespace support
- Container capabilities: NET_ADMIN, NET_RAW

## How It Works (Podman Mode)

The `test-vrrp-podman.sh` script creates:
1. Isolated Podman bridge network (random 10.99.x.x/24 subnet)
2. Two Alpine-based keepalived containers
3. VRRP communication via unicast within isolated network
4. Complete cleanup after tests

**Safety Features:**
- Randomized subnet to avoid conflicts with production (192.168.x.x)
- Isolated bridge network (no host network access)
- Containers run with minimal required capabilities
- Automatic cleanup on exit (containers, network, images)

## Test Modes

### 1. Podman Mode (test-vrrp-podman.sh) - RECOMMENDED
- **Pros:** Full network isolation, runs as regular user, safe for production servers
- **Cons:** Requires Podman, slightly slower (container startup)
- **Best for:** Testing on lunarBeacon or other production-adjacent systems

### 2. Unshare Mode (test-vrrp-unshare.sh) - Alternative
- **Pros:** No container runtime needed, faster startup
- **Cons:** Runs on host network namespace (less isolated), requires user namespace support
- **Best for:** Development systems, quick syntax checks

### 3. Config Only (test-configs-only.sh) - Validation
- **Pros:** Fastest, no runtime requirements beyond keepalived binary
- **Cons:** Only validates syntax, no runtime behavior testing
- **Best for:** CI/CD pipelines, pre-deployment checks

## Production Safety Checklist

When running on lunarBeacon or production systems:

- [ ] Verify test subnet doesn't conflict with production (192.168.x.x)
- [ ] Confirm Podman is using bridge network (not host networking)
- [ ] Check no test containers bind to port 53
- [ ] Ensure cleanup runs even on test failure
- [ ] Monitor production DNS during test (`dig @192.168.100.112 google.com`)

## Production Config Testing

To validate actual production configs:

1. Copy configs from archive:
   ```bash
   cp openspec/changes/archive/2026-03-01-dns-keepalived-analysis/specs/dns-ha-analysis/*.conf tmp/
   ```

2. Run validation in container:
   ```bash
   podman run --rm -v ./tmp:/configs:ro alpine/keepalived keepalived -t -f /configs/production.conf
   ```

## Troubleshooting

**Issue:** "podman: command not found"  
**Fix:** Install Podman: `sudo apt-get install podman` (Ubuntu/Debian)

**Issue:** Containers can't communicate  
**Fix:** Check firewall rules for bridge networks: `sudo iptables -L -v -n | grep FORWARD`

**Issue:** "network is already allocated"  
**Fix:** Remove old networks: `podman network prune`
