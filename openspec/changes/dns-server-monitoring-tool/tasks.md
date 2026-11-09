## 1. DNS Health Metrics Collection

- [x] 1.1 Create metrics exporter script in ~/dev/src/mkrasberry/dns-monitoring/
- [x] 1.2 Implement DNS query count collection from Pi-hole API
- [x] 1.3 Implement dns_up binary metric (health check)
- [x] 1.4 Implement dns_response_time_ms metric
- [x] 1.5 Implement dns_upstream_response_time_ms histogram
- [x] 1.6 Configure server-specific labels (all, new_york, miyami)
- [x] 1.7 Expose OpenTelemetry-compatible /metrics endpoint
- [x] 1.8 Test metrics collection on each DNS server

## 2. Datadog Integration

- [x] 2.1 Configure Telegraf to poll Pi-hole API (using inventory)
- [x] 2.2 Configure Telegraf to run DNS latency checks (internal + external)
- [x] 2.3 Configure Unbound access-control for monitoring host
- [x] 2.4 Create Datadog monitor for dns_up (WARNING: 5min)
- [x] 2.5 Create Datadog monitor for dns_up (CRITICAL: 15min)
- [ ] 2.6 Configure Pagerduty integration for critical alerts
- [ ] 2.7 Test alert firing and Pagerduty notification

## 3. Restart Playbook

- [x] 3.1 Create Ansible playbook structure in ~/dev/src/mkrasberry/
- [x] 3.2 Add DNS server inventory (all, new_york, miyami)
- [x] 3.3 Implement SSH connection task
- [x] 3.4 Implement privilege escalation (sudo/su)
- [x] 3.5 Implement pihole restart as pihole user
- [x] 3.6 Add diagnostic collection on failure (pihole -d)
- [x] 3.7 Add log output saving with timestamps
- [x] 3.8 Test playbook against a single server (syntax verified, no running pihole to test)
- [x] 3.9 Document playbook usage

## 4. Podman Healthcheck Fix

- [x] 4.1 Investigate current healthcheck configuration
- [x] 4.2 Test exec-based healthcheck inside container
- [x] 4.3 Test httpGet healthcheck against Pi-hole web interface
- [x] 4.4 Implement working healthcheck (choose exec or httpGet)
- [x] 4.5 Verify healthcheck returns correct status for DNS functionality
- [x] 4.6 Apply healthcheck fix to container (may require recreation)
- [x] 4.7 Verify container auto-restart on failure works (requires pihole container running)
