## Context

### Current DNS Infrastructure

**Wisconsin (marsAlpha, marsBeta)**
- Network: 192.168.20.0/24
- IPs: 192.168.20.250, 192.168.20.251

**New York (terraOmega, terraPhi)**
- Network: 192.168.100.0/24
- IPs: 192.168.100.112, 192.168.100.110

**Miyagi (alphaCenA, alphaCenB)**
- Network: 192.168.3.0/24
- IPs: 192.168.3.100, 192.168.3.101

Each server runs:
- Pi-hole container (DNS sinkhole on port 53)
- Unbound (upstream resolver on port 5335)

**Current client DNS configuration:**
- Clients point to individual DNS servers or round-robin via DHCP
- No automatic failover - if server down, clients fail until manual intervention

### Constraints
- Want to minimize changes
- Brief downtime acceptable when I'm at keyboard
- Prefer open-source, simple solutions
- Current monitoring and restart playbook should continue to work

## Goals / Non-Goals

**Goals:**
- Understand network changes required for DNS HA
- Document failover behavior and timing
- Identify common pitfalls and how to avoid them
- Create implementation roadmap

**Non-Goals:**
- Do NOT implement HA (this is analysis only)
- Do NOT change client configurations unless necessary
- Do NOT modify existing monitoring/alerting

## Decisions

### D1: HA Approach Options

**Option A: Keepalived/VRRP (Recommended for HA)**

| Aspect | Details |
|--------|---------|
| How it works | Virtual IP (VIP) floats between servers using VRRP protocol |
| Failover | Automatic, typically 3-5 seconds |
| Network changes | Need to allow VRRP multicast, may need switch config |
| Complexity | Medium - keepalived daemon on each DNS server |
| Pros | True HA, automatic failover, widely used |
| Cons | Requires network coordination, ARP cache issues |

**Option B: HSRP (Cisco proprietary)**

| Aspect | Details |
|--------|---------|
| How it works | Cisco's proprietary failover protocol |
| Failover | Automatic |
| Network changes | Requires Cisco equipment |
| Complexity | Medium |
| Pros | Integrated with Cisco gear |
| Cons | Proprietary, not applicable to home network |

**Option C: DNS Round-Robin (Simpler, no HA)**

| Aspect | Details |
|--------|---------|
| How it works | Multiple A records for same hostname |
| Failover | None - clients get all IPs, try sequentially |
| Network changes | None |
| Complexity | Low |
| Pros | Simple, no daemon, no network changes |
| Cons | No automatic failover, clients may cache failed IP |

**Option D: Client-side failover (Alternative)**

| Aspect | Details |
|--------|---------|
| How it works | Configure multiple DNS servers in DHCP/client |
| Failover | Client-dependent (some OSes retry automatically) |
| Network changes | None |
| Complexity | Low |
| Pros | No infrastructure changes |
| Cons | Inconsistent behavior across clients |

### D2: Recommended Approach

**Recommendation: Option A (Keepalived) per region**

- Each region (Wisconsin, New York, Miyagi) gets its own VIP
- Pair servers within each region (e.g., marsAlpha ↔ marsBeta)
- VIP becomes the DNS address for that region
- If one server fails, VIP moves to other within seconds

### D3: Network Architecture

**VIP Address Plan (per region):**
- Reserve .2 for DNS VIP in each subnet
- DHCP range: .11 - .254 (leaving .2 for VIP, .10 for infrastructure)

```
Wisconsin (192.168.20.0/24):
  marsAlpha (192.168.20.250) ←→ marsBeta (192.168.20.251)
  VIP: 192.168.20.2
  DHCP: 192.168.20.11 - 192.168.20.254

New York (192.168.100.0/24):
  terraOmega (192.168.100.112) ←→ terraPhi (192.168.100.110)
  VIP: 192.168.100.2
  DHCP: 192.168.100.11 - 192.168.100.254

Miyagi (192.168.3.0/24):
  alphaCenA (192.168.3.100) ←→ alphaCenB (192.168.3.101)
  VIP: 192.168.3.2
  DHCP: 192.168.3.11 - 192.168.3.254
```

Clients would use regional VIP (.2) as their DNS server.

## Risks / Trade-offs

### Network Risks

- **[Risk]** VRRP multicast blocked by switch
  - **Mitigation**: Check switch allows VRRP (multicast 224.0.0.18), or configure unicast

- **[Risk]** ARP cache on switches/clients points to wrong server after failover
  - **Mitigation**: Set lower `advertisement_intvl` and use `garp_master_delay`

- **[Risk]** Both servers claim VIP (split-brain)
  - **Mitigation**: Use `priority` to designate master, `preempt` to ensure master always holds VIP

- **[Risk]** Network segmentation blocks VRRP packets
  - **Mitigation**: Ensure firewall allows VRRP (protocol 112) between DNS servers

### Operational Risks

- **[Risk]** Keepalived misconfiguration causes failover storms
  - **Mitigation**: Test failover in maintenance window, set appropriate timeouts

- **[Risk]** Failover doesn't trigger DNS service restart
  - **Mitigation**: Monitor both master and backup, verify DNS service on both

- **[Risk]** Upstream Unbound not configured for VIP
  - **Mitigation**: Unbound listens on all interfaces by default, verify

### Performance Trade-offs

- **Latency**: Minor increase during failover (seconds)
- **Complexity**: Additional daemon to monitor and maintain
- **Monitoring**: Need to monitor keepalived state, not just DNS

## Implementation Roadmap

### Phase 1: Network Preparation (Research)
- [ ] Verify network equipment allows VRRP
- [ ] Choose VIP addresses for each region
- [ ] Test VRRP between pairs

### Phase 2: Keepalived Configuration
- [ ] Install keepalived on each DNS server
- [ ] Configure master/backup pairs per region
- [ ] Add firewall rules for VRRP

### Phase 3: DNS Service Integration
- [ ] Ensure pihole/unbound binds to VIP
- [ ] Update monitoring to track keepalived state
- [ ] Update restart playbook for HA (restart VIP holder)

### Phase 4: Client Migration
- [ ] Update DHCP to serve regional VIPs
- [ ] Test failover manually
- [ ] Monitor for issues

## Open Questions

1. ~~VIP addresses~~ - **RESOLVED**: Using .2 for each regional subnet
2. ~~Network equipment~~ - **RESOLVED**: Ubiquity and commodity switches between servers - need VRRP compatibility check
3. ~~Client migration~~ - **RESOLVED**: Migrate clients gradually
4. ~~Cross-region failover~~ - **RESOLVED**: No - too complex
5. ~~Monitoring~~ - **RESOLVED**: Yes - alerts for keepalived state changes
