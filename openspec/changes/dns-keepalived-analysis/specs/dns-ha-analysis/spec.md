## ADDED Requirements

### Requirement: Network compatibility analysis
The analysis SHALL document whether the existing network infrastructure supports VRRP/keepalived.

#### Scenario: VRRP multicast allowed
- **WHEN** network switches allow VRRP multicast (224.0.0.18)
- **THEN** keepalived can operate in full multicast mode

#### Scenario: VRRP multicast blocked
- **WHEN** network switches block VRRP multicast
- **THEN** keepalived can be configured for unicast mode

#### Scenario: VRRP not supported
- **WHEN** network equipment does not support VRRP
- **THEN** alternative HA solutions (round-robin DNS or client-side) must be used

### Requirement: Failover behavior specification
The analysis SHALL document expected failover timing and behavior.

#### Scenario: Primary server fails
- **WHEN** the primary DNS server becomes unreachable
- **THEN** the VIP should migrate to backup within 5 seconds

#### Scenario: Primary recovers
- **WHEN** the primary DNS server becomes available again
- **THEN** the VIP should migrate back to primary based on preemption policy

#### Scenario: Both servers fail
- **WHEN** all DNS servers in a region are down
- **THEN** clients should timeout and move to secondary DNS (if configured)

### Requirement: Network address planning
The analysis SHALL specify VIP addresses for each region.

#### Scenario: Wisconsin VIP
- **WHEN** planning Wisconsin DNS HA
- **THEN** use 192.168.20.2 as VIP, reserve in DHCP (range: .11-.254)

#### Scenario: New York VIP
- **WHEN** planning New York DNS HA
- **THEN** use 192.168.100.2 as VIP, reserve in DHCP (range: .11-.254)

#### Scenario: Miyagi VIP
- **WHEN** planning Miyagi DNS HA
- **THEN** use 192.168.3.2 as VIP, reserve in DHCP (range: .11-.254)

### Requirement: Common pitfalls documentation
The analysis SHALL document known pitfalls and mitigations.

#### Scenario: ARP cache stale
- **WHEN** failover occurs
- **THEN** client ARP caches may point to wrong MAC for VIP
- **MITIGATION**: Use lower advertisement interval and garp_master_delay

#### Scenario: Split-brain
- **WHEN** both servers claim VIP
- **THEN** DNS responses are inconsistent
- **MITIGATION**: Use priority and preempt settings correctly

#### Scenario: Firewall blocks VRRP
- **WHEN** firewalls between servers block VRRP protocol
- **THEN** failover cannot occur
- **MITIGATION**: Allow protocol 112 and multicast

### Requirement: Implementation roadmap
The analysis SHALL provide a phased implementation plan.

#### Scenario: Phase 1 - Network prep
- **WHEN** beginning HA implementation
- **THEN** verify network equipment (Ubiquity + commodity switches) allows VRRP

#### Scenario: Phase 2 - Keepalived config
- **WHEN** network is ready
- **THEN** install and configure keepalived on each server pair

#### Scenario: Phase 3 - Integration
- **WHEN** keepalived is running
- **THEN** integrate with DNS service and monitoring

#### Scenario: Phase 4 - Client migration
- **WHEN** HA is tested
- **THEN** update DHCP to serve VIPs to clients gradually
