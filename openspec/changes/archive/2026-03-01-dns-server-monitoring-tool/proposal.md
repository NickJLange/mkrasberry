## Why

The home DNS infrastructure (Pi-hole + Unbound on multiple servers: all, new york, miyami) is experiencing flaky behavior. Current monitoring is insufficient - the container has a healthcheck that isn't working with Podman, and there's no standardized way to restart or diagnose issues. We need a monitoring and operational toolkit to reduce noise and enable reliable DNS operations.

## What Changes

- Create a DNS monitoring tool with OpenTelemetry-compatible metrics collection per server
- Integrate health alerts with Datadog which triggers Pagerduty
- Build a restart playbook that SSHs to DNS servers, escalates privileges, switches to pihole user, and restarts the service while collecting diagnostic information
- Investigate and fix the Podman healthcheck compatibility issue for the DNS container

## Capabilities

### New Capabilities
- `dns-health-monitoring`: OpenTelemetry-compatible DNS health metrics collection at individual server level (all, new york, miyami). Exposes metrics for Datadog agent to scrape and forward to Datadog.
- `dns-alerting`: Datadog alert configuration that monitors DNS health metrics and triggers Pagerduty notifications when thresholds are breached.
- `dns-restart-playbook`: Ansible-style playbook (in ~/dev/src/mkrasberry) to SSH to DNS servers, restart the pihole service as the pihole user, and collect diagnostic output if the service is down.
- `pihole-healthcheck-fix`: Investigation and fix for the Podman healthcheck that is currently not functioning with the DNS container.

### Modified Capabilities
- (None - this is a new capability set)

## Impact

- New code in ~/dev/src/mkrasberry (playbook, monitoring config)
- Datadog monitoring configuration changes
- Pagerduty alert routing configuration
- No changes to production DNS infrastructure - operational tooling only
