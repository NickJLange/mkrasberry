## Why

Provisioning a new Raspberry Pi today requires inserting a physical SD card into the macOS host so `build_image.sh` can write WiFi/SSH/user config to the auto-mounted `/Volumes/bootfs`, then booting the Pi to apply ansible runbooks over the network — a workflow that fails when the SD reader is flaky, blocks parallel builds, and ties image storage to whichever local disk has space. We want a fully headless pipeline on macOS that produces a finished, ansible-configured `.img` ready to `dd` to an SD card, with image artifacts stored in a remote-by-default location so the laptop's disk health stops being load-bearing.

## What Changes

- Add a headless image-builder pipeline that fetches the latest `raspios-arm64-lite` release, boots it under qemu (no physical SD card required), applies our ansible runbooks against the booted VM with an IP override so they run before the Pi has its real network identity, then exports a dd-able `.img`.
- Replace the `/Volumes/bootfs` macOS auto-mount dependency in `build_image.sh` and `post_install.sh` with a loop-mount / qemu-driven configuration step that works without inserting an SD card. **BREAKING** for the existing `build_image.sh` invocation contract.
- Add a pluggable image-storage backend so base images and built artifacts live in a configurable store, with **Cloudflare R2 as the default** (zero-egress, source-of-truth) and **local-attached disk as fallback** for offline builds. Keys are namespaced (`base/`, `built/`) and content-addressed (SHA or build timestamp) so `dd` writes are reproducible.
- Capture light timing metrics for each pipeline phase (fetch, boot, ansible apply, export, upload) and emit them at the end of a build for visibility into where time is spent.
- Success criterion: operator powers off a Pi4/Pi5, swaps in an SD written from the built image, and the Pi boots into its target configuration with no further manual steps.

### Future Scope (out of scope for this change)

A follow-up change, tentatively `image-fleet-prebuilder`, will orchestrate this engine on a schedule (weekly/monthly, plus on new raspios releases) to pre-bake an image per host in the fleet so a failed Pi can be reflashed in minutes instead of waiting for an ansible run. To keep that follow-up purely additive, this change deliberately:

- Shapes the R2 key layout to be **fleet-aware from day one** (e.g. `built/<host>/<raspios-version>/<build-ts>.img.xz`), even though only one host is built per invocation.
- Keeps the build engine **idempotent and parameterized by host** so a scheduler can call it in a loop with no internal changes.

The scheduler itself, fleet inventory wiring, retention policy, secret-freshness handling, and notifications are explicitly out of scope here.

## Capabilities

### New Capabilities

- `image-builder-pipeline`: End-to-end orchestration that fetches a base raspios image, performs first-boot configuration headlessly under qemu, applies ansible runbooks with a known IP, and exports a dd-able `.img` artifact.
- `image-storage-backend`: Pluggable storage abstraction for base and built image artifacts, with a Cloudflare R2 backend (default) and a local-attached-disk backend (offline fallback), plus the cache semantics needed because qemu requires images on a real filesystem.
- `build-metrics`: Lightweight per-phase timing instrumentation emitted at the end of each build so the operator can see where wall-clock time is spent.

### Modified Capabilities

<!-- None. The repo currently has no specs in openspec/specs/ that this change modifies. -->

## Impact

- **Code**: `build_image.sh`, `post_install.sh`, the per-region `*-wifi.sh` scripts (e.g. `us-ny-wifi.sh`), `userconf.txt`, `kernels/Image`, the empty `build_images/` and `automated_image_testing/` directories, and the existing ansible role tree under `roles/` (specifically the runbooks invoked against a freshly booted host).
- **Dependencies**: `qemu-system-aarch64` on macOS (already in use), a tool to fetch raspios releases (curl + checksum verify), an R2-compatible client (`rclone` or `aws s3` with R2 endpoint), and credentials for the R2 bucket.
- **Configuration**: New configuration surface for the storage backend (backend type, bucket name, credentials source) and for the IP override applied during ansible runs.
- **Secrets**: R2 API token must be sourced from a secret store (sops / 1Password CLI / env) — adds a credentials surface that did not exist when images lived only on local disk.
- **Operational**: First build on a fresh machine pays a ~3GB cache-miss download from R2; subsequent builds reuse the local working copy.
