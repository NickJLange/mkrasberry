## ADDED Requirements

### Requirement: Podman healthcheck functional
The Podman container running Pi-hole SHALL have a working healthcheck that correctly reports container health.

#### Scenario: Healthcheck passes
- **WHEN** the DNS container is healthy
- **THEN** `podman inspect` shows `Health` status as "healthy"

#### Scenario: Healthcheck fails
- **WHEN** the DNS container is unhealthy
- **THEN** `podman inspect` shows `Health` status as "unhealthy" and triggers any configured container restart policy

### Requirement: Healthcheck uses appropriate check method
The healthcheck SHALL use either exec or httpGet method that works reliably with Podman.

#### Scenario: Exec method works
- **WHEN** healthcheck uses exec to run a command inside the container
- **THEN** the command executes successfully and returns exit code 0

#### Scenario: HTTP method works
- **WHEN** healthcheck uses httpGet to ping Pi-hole web interface
- **THEN** the HTTP request returns 200 OK within the timeout period

### Requirement: Healthcheck checks DNS functionality
The healthcheck SHALL verify that DNS resolution is actually working, not just that the container is running.

#### Scenario: DNS resolution verified
- **WHEN** healthcheck runs
- **THEN** it performs an actual DNS query (e.g., `dig +short pi.hole @127.0.0.1`) and verifies a response

#### Scenario: DNS resolution fails
- **WHEN** DNS resolution fails
- **THEN** the healthcheck returns a non-zero exit code, marking the container unhealthy
