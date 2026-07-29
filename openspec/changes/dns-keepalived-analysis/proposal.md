## Why

The current DNS infrastructure (Pi-hole + Unbound) has no high availability. If a DNS server fails, clients lose DNS resolution until manual intervention. This is a single point of failure that impacts all services. We need to understand the architectural changes required to add DNS HA using keepalived/HSRP and/or round-robin DNS.

## What Changes

This is a **planning/analysis** change to document the requirements, risks, and architectural impact of adding DNS high availability.

- Document current DNS infrastructure and dependencies
- Analyze keepalived/VRRP/HSRP options for DNS failover
- Analyze DNS round-robin load balancing as an alternative
- Document network changes required (VIP, ARP, etc.)
- Identify common pitfalls and failure modes
- Create implementation roadmap

## Capabilities

### New Capabilities
- `dns-ha-analysis`: Analysis document covering keepalived/HSRP/round-robin options, network requirements, failover behavior, and common pitfalls for DNS HA deployment.

### Modified Capabilities
- (None - this is a new analysis)

## Impact

- **Network**: May require VIP (Virtual IP) configuration, network switch changes for ARP
- **DNS Servers**: Keepalived daemon, additional network config
- **Clients**: May need updated DNS client configurations to use VIP
- **Monitoring**: Update monitoring to track HA state
- **Existing Playbooks**: Restart playbook should continue to work
