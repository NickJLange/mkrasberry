## ADDED Requirements

### Requirement: Network compatibility analysis
The analysis SHALL document whether the existing network infrastructure supports VRRP/keepalived.

#### Scenario: VRRP multicast allowed
- **WHEN** network switches allow VRRP multicast (224.0.0.18) and protocol 112
- **THEN** keepalived can operate in full multicast mode
- **NOTE** VRRP runs directly on Linux DNS servers via keepalived daemon, not on routers/switches

#### Scenario: VRRP multicast blocked
- **WHEN** network switches block VRRP multicast
- **THEN** keepalived can be configured for unicast mode
- **NOTE** Unicast mode requires explicit peer IP configuration

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

### Requirement: Keepalived configuration design
The analysis SHALL specify keepalived configuration parameters for each region.

#### Scenario: Virtual router IDs assigned
- **WHEN** configuring keepalived for Wisconsin (marsAlpha/marsBeta)
- **THEN** use virtual_router_id 51

#### Scenario: Virtual router IDs assigned - New York
- **WHEN** configuring keepalived for New York (terraOmega/terraPhi)
- **THEN** use virtual_router_id 52

#### Scenario: Virtual router IDs assigned - Miyagi
- **WHEN** configuring keepalived for Miyagi (alphaCenA/alphaCenB)
- **THEN** use virtual_router_id 53

#### Scenario: Priority configuration
- **WHEN** configuring keepalived master server
- **THEN** set priority to 101

#### Scenario: Priority configuration - backup
- **WHEN** configuring keepalived backup server
- **THEN** set priority to 100

#### Scenario: Interface tracking
- **WHEN** keepalived monitors network interface health
- **THEN** use built-in interface tracking (no custom track scripts required)

### Requirement: Preemption policy
The analysis SHALL specify the VIP preemption behavior.

#### Scenario: Delayed preemption configured
- **WHEN** the primary server recovers after a failover
- **THEN** the master waits 30 seconds before reclaiming VIP
- **AND** this prevents flapping during intermittent network issues

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

### Requirement: Monitoring integration
The analysis SHALL specify how keepalived state is monitored.

#### Scenario: Keepalived state metrics
- **WHEN** keepalived is running on DNS servers
- **THEN** Telegraf collects keepalived state via OpenTelemetry OTLP format
- **AND** metrics are forwarded to Datadog for alerting

#### Scenario: State change alerting
- **WHEN** keepalived transitions between MASTER/BACKUP states
- **THEN** Datadog receives the state change event
- **AND** alerts are triggered if unexpected transitions occur

### Requirement: Testing strategy
The analysis SHALL specify how to test failover behavior.

#### Scenario: Manual failover test
- **WHEN** testing HA functionality
- **THEN** stop keepalived on master server
- **AND** verify VIP migrates to backup within 5 seconds

#### Scenario: Recovery test
- **WHEN** testing preemption behavior
- **THEN** restart keepalived on master server
- **AND** verify VIP returns to master after 30-second delay

#### Scenario: Interface failure test
- **WHEN** testing network interface failure
- **THEN** disable primary network interface
- **AND** verify failover triggers based on interface tracking

### Requirement: Implementation roadmap
The analysis SHALL provide a phased implementation plan.

#### Scenario: Phase 1 - Network prep
- **WHEN** beginning HA implementation
- **THEN** verify network equipment (Ubiquity + commodity switches) allows VRRP multicast (224.0.0.18) and protocol 112

#### Scenario: Phase 2 - Keepalived config
- **WHEN** network is ready
- **THEN** install keepalived on each DNS server
- **AND** configure 6 configs total (2 per region with unique virtual_router_id)

#### Scenario: Phase 3 - Integration
- **WHEN** keepalived is running
- **THEN** integrate with DNS service and existing Telegraf monitoring

#### Scenario: Phase 4 - Client migration
- **WHEN** HA is tested
- **THEN** update DHCP to serve VIPs (.2) to clients
- **AND** shift DHCP range to .11-.254 to avoid conflicts
