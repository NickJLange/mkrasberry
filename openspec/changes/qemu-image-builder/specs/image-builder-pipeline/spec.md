## ADDED Requirements

### Requirement: Fetch latest raspios-arm64-lite release

The system SHALL retrieve the latest official `raspios-arm64-lite` release (or an explicitly requested release id) and SHALL verify the release artifact's integrity against the publisher's checksum before every use, regardless of whether the artifact came from the upstream source, the active storage backend, or the local cache. If the checksum does not match, the system SHALL NOT use that copy. A mismatching cached or backend copy SHALL be discarded and re-fetched from the next source (local cache → backend → upstream). If no available source yields a matching artifact, the system SHALL abort the build and SHALL NOT proceed to boot the image. The system SHALL decompress the verified `.img.xz` artifact into a raw working image before any partition is mounted or the image is booted.

#### Scenario: Latest release is fetched and verified

- **WHEN** a build is invoked and the latest upstream release is not already present in the configured image store
- **THEN** the system downloads the release artifact, verifies its checksum against the publisher-supplied value, and makes it available to subsequent phases

#### Scenario: Cached artifact is verified before reuse

- **WHEN** a build finds the required release artifact in the local cache or the active backend
- **THEN** the system verifies that copy against the publisher-supplied checksum before decompressing or booting it

#### Scenario: Corrupted cache entry is replaced

- **WHEN** the local cached copy of the release artifact does not match the publisher-supplied checksum
- **THEN** the system discards it, re-fetches the artifact from the next source, verifies the new copy, and continues only if that copy matches

#### Scenario: Checksum mismatch aborts the build

- **WHEN** no available source yields a release artifact whose checksum matches the publisher-supplied value
- **THEN** the system exits with a non-zero status, surfaces the mismatch in the build output, and does not boot the image

#### Scenario: Compressed base is decompressed before preparation

- **WHEN** the verified release artifact is an `.img.xz`
- **THEN** the system decompresses it into a raw working image, and all mounting, growing, and booting operate on that raw image

### Requirement: Verified virt kernel

The system SHALL boot the VM with the generic arm64 virt kernel identified by the kernel version pinned in committed configuration, fetched from `base/kernels/<kver>/Image`. Before passing the kernel to the virtualization layer, the system SHALL verify it against the SHA-256 digest pinned in committed configuration on every use. The system SHALL record the kernel version and digest in the build manifest.

#### Scenario: Kernel digest mismatch aborts the build

- **WHEN** the fetched or cached kernel `Image` does not match the pinned digest
- **THEN** the system exits with a non-zero status naming the `fetch` phase and does not start the VM

### Requirement: Headless first-boot configuration

The system SHALL apply first-boot configuration (SSH enablement and the bootstrap user credential) to the base image's boot partition without requiring a physical SD card to be inserted in the host machine. The system SHALL persist Wi-Fi credentials in the release-supported form for the target release — a NetworkManager keyfile (`root`-owned, mode `0600`) under `/etc/NetworkManager/system-connections/` for Bookworm and later — applied during the ansible phase, and SHALL NOT rely on a boot-partition `wpa_supplicant.conf`.

#### Scenario: Image is configured without physical SD card

- **WHEN** a build runs on a host that has no SD card reader attached and no `/Volumes/bootfs` mount
- **THEN** the system applies first-boot configuration to the image and proceeds to the boot phase

#### Scenario: Wi-Fi is configured for a NetworkManager release

- **WHEN** a build targets a host whose configuration includes Wi-Fi credentials and the release uses NetworkManager
- **THEN** the resulting image contains a NetworkManager keyfile for that network with mode `0600`, and the boot partition contains no `wpa_supplicant.conf`

### Requirement: Non-interactive VM access

The system SHALL reach the VM's SSH service only through a port forward bound to the host loopback address (`127.0.0.1`). The system SHALL authenticate the bootstrap connection non-interactively, SHALL record the VM's host key in a per-build `known_hosts` file rather than the operator's, and SHALL NOT disable host-key checking. The bootstrap password SHALL NOT be written to disk, logs, or process arguments, and SHALL be locked in the image before export.

#### Scenario: SSH forward is loopback-only

- **WHEN** the VM is running
- **THEN** its SSH port is reachable on `127.0.0.1:<port>` and is not listening on any other host interface

#### Scenario: First connection does not prompt

- **WHEN** the readiness probe connects to a freshly booted VM for the first time
- **THEN** the connection completes without a password or host-key prompt, and the VM's host key is recorded only in the per-build `known_hosts`

### Requirement: Ansible apply against booted VM with connection-address override

The system SHALL boot the configured image in a virtual machine and SHALL run the canonical image-build entrypoint, `playbooks/image-build.yml`, against the running VM. That entrypoint SHALL import exactly the bootstrap playbooks `initial-playbook-stage-1.yml` through `initial-playbook-stage-5.yml`, in that order. Applying any other playbook (service, restore, or backup playbooks) SHALL NOT count as successful provisioning. The system SHALL connect to the VM through connection-only variables (`ansible_ssh_host`, `ansible_port`) and SHALL NOT override `ansible_host`, which keeps the target Pi's production address. The production address SHALL also be passed explicitly as `target_host_ip`. The `apt-refresh` phase SHALL run `apt-get clean` and then `apt-get update -o Acquire::AllowReleaseInfoChange=true` as separate commands before the entrypoint runs.

#### Scenario: Runbooks apply against the VM, not the production address

- **WHEN** a build is invoked with a target host whose production address differs from the VM's reachable address
- **THEN** ansible connects to the VM at `127.0.0.1:<port>`, the entrypoint completes successfully, and any address the roles persist in the image is the production address, not `127.0.0.1`, `localhost`, or the VM's internal address

#### Scenario: A failing bootstrap stage fails the build

- **WHEN** any playbook imported by `playbooks/image-build.yml` fails
- **THEN** the `ansible-apply` phase fails and the build exits non-zero

### Requirement: Export dd-able raw image artifact

On successful ansible application, the system SHALL emit a raw `.img` artifact that an operator can write directly to an SD card with `dd` (or an equivalent tool) and that boots the target Raspberry Pi 4 or Raspberry Pi 5 into its configured state.

#### Scenario: Operator boots a Pi from the exported image

- **WHEN** an operator writes the exported `.img` to an SD card with `dd`, inserts the SD into a Pi4 or Pi5, and powers the Pi on
- **THEN** the Pi boots into the configuration applied during the build with no further manual provisioning required

### Requirement: Per-host parameterization

The system SHALL accept a target host identifier as input and SHALL produce an image specific to that host's configuration. Builds with the same build inputs — host identifier and its configuration, repo commit, upstream raspios release, and pinned kernel — SHALL be configuration-equivalent: the same playbooks complete and the same configuration is applied. Images are not required to be bit-identical. They MAY differ in build timestamps, the generated bootstrap credential (which is locked before export and never delivered), SSH host keys and other identifiers generated at boot, logs, and package versions resolved live from the package repositories. The system SHALL record the build inputs and the resolved package list in a build manifest stored with the artifact, so that differences between builds are visible.

#### Scenario: Two builds for the same host produce equivalent images

- **WHEN** the system is invoked twice for the same host identifier with the same build inputs
- **THEN** both builds complete successfully, produce images that boot to the same configured state, and each has a manifest listing its inputs and resolved package versions

#### Scenario: Two builds for different hosts produce different images

- **WHEN** the system is invoked for two different host identifiers against the same upstream raspios release
- **THEN** the resulting images carry the host-specific configuration appropriate to each target

### Requirement: Build failures surface actionable diagnostics

When any pipeline phase fails, the system SHALL exit with a non-zero status, SHALL identify which phase failed, and SHALL preserve enough output (logs, stderr, the partial image where applicable) for an operator to diagnose the failure without re-running. Retained images and logs SHALL be readable only by the invoking user (directories `0700`, files `0600`). Logs SHALL NOT contain the bootstrap password or task output marked as secret. Retained failure workdirs SHALL be removable through the `prune` command.

#### Scenario: Ansible failure is diagnosable

- **WHEN** the ansible-apply phase fails partway through
- **THEN** the build exits non-zero, the output names the failing phase and the retained workdir path, and the ansible output is retained for inspection

#### Scenario: Retained artifacts are owner-only

- **WHEN** a build fails after first-boot configuration has been written
- **THEN** the retained working image and logs are accessible only to the invoking user
