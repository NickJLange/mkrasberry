## ADDED Requirements

### Requirement: SSH connectivity to DNS servers
The playbook SHALL establish SSH connections to each DNS server using configured credentials.

#### Scenario: SSH connection successful
- **WHEN** the playbook runs against a DNS server
- **THEN** an SSH connection is established using key-based authentication

#### Scenario: SSH connection fails
- **WHEN** SSH connection to a DNS server fails
- **THEN** the playbook aborts with a clear error message indicating which server failed

### Requirement: Privilege escalation to root
The playbook SHALL escalate to root privileges after SSH connection.

#### Scenario: Escalation successful
- **WHEN** sudo or su is executed
- **THEN** the shell runs as root user

#### Scenario: Escalation denied
- **WHEN** privilege escalation fails
- **THEN** the playbook aborts with an error and does not proceed

### Requirement: Restart pihole service as pihole user
The playbook SHALL restart the Pi-hole DNS service while running as the pihole user.

#### Scenario: Restart executed
- **WHEN** the playbook runs the restart command as pihole user
- **THEN** the command `pihole restartdns` executes successfully

#### Scenario: Restart fails
- **WHEN** the restart command returns a non-zero exit code
- **THEN** the playbook captures diagnostic output and reports failure

### Requirement: Diagnostic collection on failure
The playbook SHALL collect diagnostic information when the DNS service fails to restart or appears unhealthy.

#### Scenario: Diagnostics collected
- **WHEN** restart fails or healthcheck indicates issues
- **THEN** the playbook runs `pihole -d` and captures output to a log file

#### Scenario: Diagnostics saved
- **WHEN** diagnostics are collected
- **THEN** output is saved to a timestamped file in the playbook logs directory

### Requirement: Playbook idempotency
The playbook SHALL be idempotent - running it multiple times produces the same result.

#### Scenario: Multiple runs
- **WHEN** the playbook is run multiple times on a healthy server
- **THEN** the server remains healthy and no errors are reported
