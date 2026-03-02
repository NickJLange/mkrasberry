## ADDED Requirements

### Requirement: Datadog monitors DNS health
The system SHALL configure Datadog monitors to alert when DNS health metrics indicate failure.

#### Scenario: Server down alert
- **WHEN** the `dns_up` metric equals 0 for 5 consecutive minutes
- **THEN** Datadog triggers a WARNING alert

#### Scenario: Server prolonged outage
- **WHEN** the `dns_up` metric equals 0 for 15 consecutive minutes
- **THEN** Datadog triggers a CRITICAL alert and notifies Pagerduty

### Requirement: Pagerduty notification
The system SHALL route critical DNS alerts to Pagerduty for escalation.

#### Scenario: Critical alert triggers
- **WHEN** a CRITICAL Datadog monitor fires for DNS health
- **THEN** Pagerduty receives the alert and creates an incident

#### Scenario: Alert recovers
- **WHEN** the DNS server recovers (`dns_up` returns to 1)
- **THEN** Datadog sends a recovery notification to Pagerduty, resolving the incident

### Requirement: Alert configuration managed as code
The system SHALL store Datadog monitor definitions in version control.

#### Scenario: Monitor definition in repo
- **WHEN** a team member reviews monitor configuration
- **THEN** they can view the JSON/YAML definition in the repository under monitoring/datadog/
