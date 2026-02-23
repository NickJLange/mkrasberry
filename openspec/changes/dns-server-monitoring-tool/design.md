## Context

The home DNS infrastructure consists of three Pi-hole + Unbound servers:
- `all` (primary)
- `new york`
- `miyami` (note: user said "miyagi" initially but I'll use what they clarified)

Currently:
- Containers run on Podman but the healthcheck is not working
- No centralized monitoring beyond basic container health
- No automated way to restart or diagnose DNS issues
- Alerts go to nowhere meaningful

Constraints:
- Keep changes minimal - we're breaking the house is acceptable but we want to minimize risk
- Use existing tools where possible (Datadog already in use for alerts → Pagerduty)
- Playbooks live in ~/dev/src/mkrasberry

## Goals / Non-Goals

**Goals:**
- Implement OpenTelemetry-compatible DNS health metrics per server
- Configure Datadog to scrape metrics and trigger Pagerduty alerts
- Create a restart playbook that safely restarts DNS services with diagnostics
- Fix the Podman healthcheck issue

**Non-Goals:**
- Load balancing or HA setup (that's the separate `dns-keepalived-analysis` change)
- Modifying DNS server configurations or zone data
- Long-term metric storage solutions beyond Datadog
- Auto-remediation beyond the restart playbook

## Decisions

### D1: Metrics Collection Method
**Decision:** Use Pi-hole's built-in Teleporter API + a sidecar Prometheus exporter

**Alternatives considered:**
- Direct Prometheus scraping of Pi-hole's internal metrics (limited)
- Custom Python script parsing logs (fragile)
- OpenTelemetry collector on each DNS server (additional resource overhead)

**Rationale:** Pi-hole exposes query logs and statistics via its API. A lightweight exporter can poll this and expose OpenTelemetry-compatible metrics. This reuses existing Pi-hole functionality and minimizes install footprint.

### D2: Alerting Pipeline
**Decision:** Prometheus scraper → Datadog Agent → Datadog Monitor → Pagerduty

**Alternatives considered:**
- Prometheus Alertmanager → Pagerduty (adds complexity)
- Push directly to Datadog API (loses Datadog monitor features)
- Custom webhook → Pagerduty (reinventing)

**Rationale:** Datadog is already in the stack. Datadog Agents can be installed on the DNS servers to scrape the metrics endpoint and forward to Datadog. This leverages existing infrastructure.

### D3: Restart Playbook Approach
**Decision:** Ansible playbook with SSH key authentication

**Alternatives considered:**
- Fabric/Paramiko script (less idempotent)
- Direct SSH commands (not auditable, harder to maintain)
- systemd timers on the DNS servers (tightly coupled)

**Rationale:** Ansible provides idempotency, clear execution flow, and is already used in ~/dev/src/mkrasberry. The playbook will:
1. SSH to target server
2. `sudo -i` to become root
3. `su - pihole -c "pihole restartdns"` to restart as the pihole user
4. Collect `pihole -d` diagnostic output if restart fails or service appears unhealthy

### D4: Healthcheck Fix Approach
**Decision:** Investigate Podman healthcheck exec vs httpGet, implement whichever works

**Alternatives considered:**
- Switch to Docker Compose (not using Docker)
- Remove healthcheck (loses container restart automation)
- Use a wrapper script (adds complexity)

**Rationale:** Podman healthchecks have known quirks with certain exec commands. Will test both `exec` (running a check inside container) and `httpGet` (hitting Pi-hole's web interface) to find what works.

## Risks / Trade-offs

- **[Risk]** Datadog Agent on DNS servers adds resource overhead
  - **Mitigation:** Use minimal metric collection, Agent can be configured to scrape only what's needed

- **[Risk]** SSH-based restart requires key management
  - **Mitigation:** Use existing SSH keys from ~/dev/src/mkrasberry, limit to specific users/commands via sudo

- **[Risk]** Healthcheck fix may require container recreation
  - **Mitigation:** Document the change, ensure backup of current container state before testing

- **[Risk]** Alert storms if DNS flaps
  - **Mitigation:** Set reasonable hysteresis (e.g., 5 minute failure threshold before alerting)

## Open Questions

- Should the restart playbook include automatic execution or remain manual-only?
- What's the desired alert escalation timeline (how many failures before Pagerduty triggers)?
- Are there specific metrics beyond "is DNS working" that should trigger alerts (e.g., query volume drop, high latency)?
