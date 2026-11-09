## ADDED Requirements

### Requirement: Fetch latest raspios-arm64-lite release

The system SHALL retrieve the latest official `raspios-arm64-lite` release from the upstream source and SHALL verify its integrity against the publisher's checksum before use. If the checksum does not match, the system SHALL abort the build and SHALL NOT proceed to boot the image.

#### Scenario: Latest release is fetched and verified

- **WHEN** a build is invoked and the latest upstream release is not already present in the configured image store
- **THEN** the system downloads the release artifact, verifies its checksum against the publisher-supplied value, and makes it available to subsequent phases

#### Scenario: Checksum mismatch aborts the build

- **WHEN** a downloaded release artifact's checksum does not match the publisher-supplied value
- **THEN** the system exits with a non-zero status, surfaces the mismatch in the build output, and does not boot the image

### Requirement: Headless first-boot configuration

The system SHALL apply first-boot configuration (WiFi credentials, SSH enablement, default user credentials) to the base image without requiring a physical SD card to be inserted in the host machine.

#### Scenario: Image is configured without physical SD card

- **WHEN** a build runs on a host that has no SD card reader attached and no `/Volumes/bootfs` mount
- **THEN** the system applies first-boot configuration to the image and proceeds to the boot phase

### Requirement: Ansible apply against booted VM with IP override

The system SHALL boot the configured image in a virtual machine and SHALL apply the project's ansible runbooks against the running VM using a caller-supplied IP override so the runbooks execute against the VM's reachable address rather than the target Pi's eventual production address.

#### Scenario: Runbooks apply against the VM, not the production address

- **WHEN** a build is invoked with a target host whose production IP differs from the VM's reachable IP
- **THEN** ansible runs against the VM's IP, completes successfully, and the production IP appears in the resulting image's persisted configuration (not in the ansible inventory used during the build)

### Requirement: Export dd-able raw image artifact

On successful ansible application, the system SHALL emit a raw `.img` artifact that an operator can write directly to an SD card with `dd` (or an equivalent tool) and that boots the target Raspberry Pi 4 or Raspberry Pi 5 into its configured state.

#### Scenario: Operator boots a Pi from the exported image

- **WHEN** an operator writes the exported `.img` to an SD card with `dd`, inserts the SD into a Pi4 or Pi5, and powers the Pi on
- **THEN** the Pi boots into the configuration applied during the build with no further manual provisioning required

### Requirement: Per-host parameterization

The system SHALL accept a target host identifier as input and SHALL produce an image specific to that host's configuration. The same input host identifier and the same upstream raspios release SHALL produce equivalent output (the image MAY differ in fields that are required to be unique per build, such as build timestamps or freshly generated identifiers).

#### Scenario: Two builds for the same host produce equivalent images

- **WHEN** the system is invoked twice for the same host identifier against the same upstream raspios release
- **THEN** both builds complete successfully and produce images that boot to the same configured state

#### Scenario: Two builds for different hosts produce different images

- **WHEN** the system is invoked for two different host identifiers against the same upstream raspios release
- **THEN** the resulting images carry the host-specific configuration appropriate to each target

### Requirement: Build failures surface actionable diagnostics

When any pipeline phase fails, the system SHALL exit with a non-zero status, SHALL identify which phase failed, and SHALL preserve enough output (logs, stderr, the partial image where applicable) for an operator to diagnose the failure without re-running.

#### Scenario: Ansible failure is diagnosable

- **WHEN** the ansible-apply phase fails partway through
- **THEN** the build exits non-zero, the output names the failing phase, and the ansible output is retained for inspection
