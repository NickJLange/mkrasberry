## ADDED Requirements

### Requirement: Pluggable storage backend selection

The system SHALL support multiple image-storage backends behind a single interface, and SHALL select the active backend from configuration. The system SHALL provide at minimum a Cloudflare R2 backend and a local-attached-disk backend. The default backend SHALL be Cloudflare R2.

#### Scenario: Default backend is R2

- **WHEN** a build is invoked with no backend configuration override
- **THEN** the system reads from and writes to a Cloudflare R2 bucket

#### Scenario: Local backend is selected by configuration

- **WHEN** a build is invoked with the storage backend explicitly configured to local-attached disk
- **THEN** the system reads from and writes to the configured local directory and does not contact R2

### Requirement: Fleet-aware key layout

The system SHALL organize stored artifacts under a key layout that distinguishes upstream base images from built artifacts and that scopes built artifacts by target host so multiple hosts can coexist in a single store. Built-artifact keys SHALL include the upstream raspios release identifier and a build timestamp so multiple builds for the same host are addressable.

#### Scenario: Base image is stored under a base namespace

- **WHEN** the system fetches an upstream raspios release that is not already cached
- **THEN** the system writes the release artifact under a key prefix that identifies it as a base image (not a built artifact)

#### Scenario: Built image is stored under a host-scoped, version-stamped key

- **WHEN** the system completes a successful build for host `foo` against raspios release `R`
- **THEN** the resulting artifact is stored under a key that contains both `foo` and `R` and includes a build timestamp that distinguishes it from prior builds for the same host and release

### Requirement: Cache-on-miss, reuse-on-hit working copy

The system SHALL maintain a local working copy of any image it operates on (because the virtualization layer requires images on a real filesystem). On cache miss, the system SHALL pull the artifact from the active backend into the working copy. On cache hit, the system SHALL reuse the existing working copy without re-downloading.

#### Scenario: Cache miss triggers a download

- **WHEN** a build needs a base image that is not present in the local working copy
- **THEN** the system pulls the artifact from the active backend, places it in the working copy, and proceeds

#### Scenario: Cache hit avoids redundant download

- **WHEN** a build needs a base image that is already present in the local working copy and matches the expected checksum
- **THEN** the system uses the local copy and does not re-download

### Requirement: Successful builds are pushed back to the store

On successful completion of a build, the system SHALL upload the exported image artifact to the active backend under the fleet-aware key layout described above. On build failure, the system SHALL NOT upload a partial or invalid artifact.

#### Scenario: Successful build is uploaded

- **WHEN** a build completes successfully
- **THEN** the exported image is uploaded to the active backend under its host-scoped, version-stamped key before the build exits

#### Scenario: Failed build is not uploaded

- **WHEN** a build fails partway through any phase prior to export
- **THEN** no artifact is uploaded to the active backend for that invocation

### Requirement: Credentials sourced from a secret store

When using a backend that requires credentials (such as R2), the system SHALL obtain those credentials from a configured secret source at invocation time and SHALL NOT require credentials to be checked into the repository.

#### Scenario: R2 credentials are not committed

- **WHEN** a build is invoked using the R2 backend
- **THEN** the system retrieves the R2 credentials from the configured secret source and proceeds without reading any committed credential file

#### Scenario: Missing credentials fail fast

- **WHEN** a build is invoked using the R2 backend and the configured secret source returns no credentials
- **THEN** the system exits with a non-zero status before attempting any R2 operations and surfaces a message identifying the missing credential

### Requirement: Offline operation via local backend

When the active backend is local-attached disk, the system SHALL complete a build successfully without any network access to the storage backend, given that all required base images are already present locally.

#### Scenario: Build completes with no network to storage

- **WHEN** the local-disk backend is selected, the required base image is already present, and network access to remote storage is unavailable
- **THEN** the build completes successfully and writes the output artifact to the local backend
