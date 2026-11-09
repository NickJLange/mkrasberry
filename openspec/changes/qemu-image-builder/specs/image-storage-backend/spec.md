## ADDED Requirements

### Requirement: Pluggable storage backend selection

The system SHALL support multiple image-storage backends behind a single interface, and SHALL select the active backend from configuration. The system SHALL provide at minimum a Cloudflare R2 backend and a local-attached-disk backend. The default backend SHALL be Cloudflare R2. The interface SHALL provide fetch, atomic per-object put, exists, list, idempotent delete, and promote (make a staged object visible under its final key) operations.

#### Scenario: Default backend is R2

- **WHEN** a build is invoked with no backend configuration override
- **THEN** the system reads from and writes to a Cloudflare R2 bucket

#### Scenario: Local backend is selected by configuration

- **WHEN** a build is invoked with the storage backend explicitly configured to local-attached disk
- **THEN** the system reads from and writes to the configured local directory and does not contact R2

### Requirement: Fleet-aware key layout

The system SHALL organize stored artifacts under a key layout that distinguishes upstream base images and kernels from built artifacts and that scopes built artifacts by target host so multiple hosts can coexist in a single store. Built-artifact keys SHALL include the upstream raspios release identifier and a build timestamp so multiple builds for the same host are addressable. Each built artifact SHALL be stored with a SHA-256 checksum sidecar and a build manifest.

#### Scenario: Base image is stored under a base namespace

- **WHEN** the system fetches an upstream raspios release that is not already cached
- **THEN** the system writes the release artifact under a key prefix that identifies it as a base image (not a built artifact)

#### Scenario: Built image is stored under a host-scoped, version-stamped key

- **WHEN** the system completes a successful build for host `foo` against raspios release `R`
- **THEN** the resulting artifact is stored under a key that contains both `foo` and `R` and includes a build timestamp that distinguishes it from prior builds for the same host and release

### Requirement: Safe key and path components

The system SHALL validate every identifier used as a key or path component (host identifier, release identifier, kernel version) before any read or write. It SHALL reject empty components, `.` and `..`, components containing `/`, `\`, or NUL, and anything outside the documented character set for that identifier. The local backend and the local cache SHALL resolve each target path (following symlinks) and SHALL refuse any operation whose resolved path is not inside the configured root.

#### Scenario: Traversal in a host identifier is rejected

- **WHEN** a build is invoked with a host identifier such as `../etc` or `foo/bar`
- **THEN** the system exits with a non-zero status before any storage or filesystem operation and names the invalid identifier

#### Scenario: Symlink escape is refused

- **WHEN** a path under the local backend root resolves, through a symlink, to a location outside the root
- **THEN** the local backend refuses the read or write with an error

### Requirement: Cache-on-miss, verify-on-hit working copy

The system SHALL maintain a local working copy of any image it operates on (because the virtualization layer requires images on a real filesystem). On cache miss, the system SHALL pull the artifact from the active backend into the local cache. Every cached or backend-sourced artifact SHALL be verified against its trusted checksum before it is used: the publisher checksum for base images, the pinned digest for kernels. On a verified cache hit, the system SHALL reuse the local copy without re-downloading. On a mismatch, the system SHALL discard the copy and re-fetch it.

#### Scenario: Cache miss triggers a download

- **WHEN** a build needs a base image that is not present in the local cache
- **THEN** the system pulls the artifact from the active backend, verifies it against the publisher checksum, places it in the cache, and proceeds

#### Scenario: Cache hit avoids redundant download

- **WHEN** a build needs a base image that is already present in the local cache and matches the expected checksum
- **THEN** the system uses the local copy and does not re-download

#### Scenario: Backend copy failing verification is not used

- **WHEN** an artifact pulled from the active backend does not match its trusted checksum
- **THEN** the system does not use it and falls back to the upstream source, or aborts if no upstream source is available

### Requirement: Successful builds are published to the store

On successful completion of a build, the system SHALL upload the exported image artifact, its SHA-256 sidecar, and its build manifest to the active backend under the fleet-aware key layout. Only after all of those uploads have succeeded SHALL the system update the host's `latest.json` pointer. The pointer SHALL reference the artifact key and checksum and SHALL be written as a single atomic object write, so readers observe either the previous pointer or the new one. The system SHALL NOT replace an existing pointer whose `build_ts` is newer than the current build's. One builder machine per store is the supported concurrency model. The system MAY write private staging objects (keys ending in `.partial`) during upload. Staging objects SHALL NOT be referenced by `latest.json` and SHALL NOT be treated as published artifacts. When `--no-upload` is given, the system SHALL perform no backend writes, SHALL leave `latest.json` unchanged, SHALL report the upload phase as skipped, and SHALL still exit successfully if all other phases succeeded.

#### Scenario: Successful build is uploaded

- **WHEN** a build completes successfully
- **THEN** the exported image, its checksum sidecar, and its manifest are uploaded to the active backend under the host-scoped, version-stamped key, and `latest.json` is then updated to reference them before the build exits

#### Scenario: Pointer is published last

- **WHEN** any of the artifact, sidecar, or manifest uploads fails
- **THEN** `latest.json` is not modified and still references the previous build

#### Scenario: Upload disabled for debugging

- **WHEN** a build is invoked with `--no-upload` and all other phases succeed
- **THEN** the artifact remains in the local output directory, no object is written to the backend, `latest.json` is unchanged, and the build exits zero

### Requirement: Failed builds publish no built artifact

On build failure, the system SHALL NOT publish a built artifact, checksum sidecar, manifest, or `latest.json` update for that invocation. Verified base-image mirror uploads made earlier in the same invocation are permitted. The system SHALL make a best-effort deletion of the staging objects it created, and SHALL provide a `prune --remote` operation that removes staging objects older than a safety threshold (default 24 hours).

#### Scenario: Failed build is not published

- **WHEN** a build fails partway through any phase
- **THEN** no built artifact, sidecar, or manifest is visible under a final key for that invocation and `latest.json` is unchanged; a base-image mirror upload made earlier in the same invocation may remain

#### Scenario: Leftover staging objects are cleaned up

- **WHEN** an operator runs `prune --remote` and the backend contains staging objects older than the threshold
- **THEN** those staging objects are deleted and no published artifact or `latest.json` is touched

### Requirement: Credentials sourced from a secret store

When using a backend that requires credentials (such as R2), the system SHALL obtain those credentials from a configured secret source at invocation time and SHALL NOT require credentials to be checked into the repository.

#### Scenario: R2 credentials are not committed

- **WHEN** a build is invoked using the R2 backend
- **THEN** the system retrieves the R2 credentials from the configured secret source and proceeds without reading any committed credential file

#### Scenario: Missing credentials fail fast

- **WHEN** a build is invoked using the R2 backend and the configured secret source returns no credentials
- **THEN** the system exits with a non-zero status before attempting any R2 operations and surfaces a message identifying the missing credential

### Requirement: Operation without storage access via local backend

When the active backend is local-attached disk, the system SHALL complete a build successfully without any network access to remote storage or to the upstream image source, given that the release is specified explicitly and the required base image and kernel are already present and verifiable locally. Without network access, the system SHALL verify the base image against a publisher SHA-256 committed in the repository (`qemu-image-builder.toml`, `[base.pinned]`, keyed by release id), and SHALL refuse an offline build for a release that has no committed digest. A `.sha256` sidecar stored next to the image SHALL NOT be accepted as the trust anchor on its own. The VM's package egress (for `apt-refresh` and ansible) remains required. Fully air-gapped builds are out of scope.

#### Scenario: Build completes with no network to storage

- **WHEN** the local-disk backend is selected, the release is given explicitly, the required base image and kernel are already present, and network access to remote storage and the upstream image source is unavailable while VM package egress is available
- **THEN** the build completes successfully and writes the output artifact to the local backend
