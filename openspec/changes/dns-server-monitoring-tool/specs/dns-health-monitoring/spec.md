## ADDED Requirements

### Requirement: DNS health metrics collection
The system SHALL collect DNS health metrics from each Pi-hole server (all, new york, miyami) using OpenTelemetry-compatible format.

#### Scenario: Metrics endpoint accessible
- **WHEN** Datadog Agent scrapes the metrics endpoint on a DNS server
- **THEN** the response includes `dns_query_total`, `dns_up`, `dns_response_time_ms`, and `dns_upstream_response_time_ms` metrics with server-specific labels

#### Scenario: Metrics include server identity
- **WHEN** metrics are collected from any DNS server
- **THEN** each metric includes a `server` label with value matching the server identifier (all, new_york, or miyami)

#### Scenario: Metrics collected at regular intervals
- **WHEN** Datadog Agent is configured to scrape metrics
- **THEN** collection occurs at 60-second intervals by default

### Requirement: Individual server health status
The system SHALL expose a binary `dns_up` metric indicating whether each DNS server is responding to queries.

#### Scenario: Server healthy
- **WHEN** the DNS server is responding to queries
- **THEN** the `dns_up` metric value is 1

#### Scenario: Server unhealthy
- **WHEN** the DNS server is not responding to queries
- **THEN** the `dns_up` metric value is 0

### Requirement: Query statistics
The system SHALL expose metrics about DNS query volume and upstream response times.

#### Scenario: Query count tracked
- **WHEN** DNS queries are processed
- **THEN** the `dns_query_total` counter increments with query type and status labels

#### Scenario: Upstream latency measured
- **WHEN** Unbound processes upstream requests
- **THEN** the `dns_upstream_response_time_ms` histogram records response times in milliseconds
