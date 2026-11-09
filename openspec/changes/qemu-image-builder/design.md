## Context

The repo's current Pi-provisioning flow is `build_image.sh` + `post_install.sh`: copy a raspios `.img` from `images/`, expand it, `hdiutil attach` so macOS auto-mounts the FAT32 boot partition at `/Volumes/bootfs`, drop `wpa_supplicant.conf` / `ssh` / `userconf.txt` into it, detach, then boot under `qemu-system-aarch64` using an extracted `kernels/Image` and `vmnet-shared` networking. Ansible runbooks under `roles/` are then run separately against the eventual Pi over its production network.

Constraints we are designing within:

- **Host platform is macOS.** `vmnet-shared`, `hdiutil`, FAT32 native mount, lack of a native ext4 driver. No `losetup`, no `qemu-nbd` without extra work.
- **The repo already standardizes on Python tooling** (`pyproject.toml`, `uv.lock`) and bash scripts under `scripts/`. We have both registers available.
- **Ansible inventory is host-keyed** (`hosts`, `host_vars/<host>.yml`). The build engine will reuse this rather than invent a parallel fleet model.
- **Kernel for qemu (`kernels/Image`)** is currently a checked-in snapshot; it will need to track the raspios release we boot.
- **The current `vmnet-shared` path requires `sudo`** and gives the VM an unpredictable IP — that is the half-broken seam this change fixes.

Stakeholders: the operator (one person doing fleet maintenance), and a future scheduler (the `image-fleet-prebuilder` change) that will call this engine on a cadence.

## Goals / Non-Goals

**Goals:**

- Single command: `<builder> --host <name>` produces an image in the configured store, no SD card touched.
- Predictable, sudo-free networking between host and VM.
- macOS-friendly: no Linux-only mount tooling.
- Storage abstraction is thin enough that adding a third backend (e.g. local NAS over SSH) is mechanical.
- R2 key layout is **already shaped for fleet pre-builds** so the follow-up change is additive.
- Failure of any phase exits non-zero with the failing phase named, and timings are still emitted.

**Non-Goals:**

- Cross-platform support (Linux/Windows hosts).
- Pre-building images for the whole fleet on a schedule — that's `image-fleet-prebuilder`.
- A new fleet inventory or host model — we use ansible's `host_vars/`.
- Runtime credential rotation for tokens baked into images.
- A GUI / web UI.
- Migrating archived images out of the existing `images/` directory.

## Decisions

### Decision 1: Top-level driver in Python; thin shell shims allowed

The orchestrator is a Python entrypoint (`scripts/qemu_image_builder/cli.py`, exposed via `pyproject.toml`). Bash is acceptable for one-line wrappers but not for the pipeline itself.

**Why:** The pipeline has real branching (cache hit/miss, backend selection, retries on `ssh` ready-check, structured timing capture, JSON-Lines output). Bash makes that brittle, especially with `set -euo pipefail` and trap interactions around timing. Python also makes the storage-backend abstraction (a single interface with two implementations) straightforward.

**Alternatives considered:**

- *All bash, like the current scripts.* Rejected: the cache-on-miss + structured-timings + retry logic gets ugly fast; we already saw the existing `build_image.sh` skip the post-install branch silently when `/Volumes/bootfs` was missing.
- *Make / Makefile.* Rejected: orchestration logic doesn't map cleanly to file targets; we want timings and failure modes that Make doesn't express well.

### Decision 2: User-mode networking with hostfwd, not vmnet-shared

qemu boots with `-netdev user,hostfwd=tcp::<port>-:22` (port allocated per build, default 2222). Ansible connects over `localhost:<port>`.

**Why:** This eliminates the `sudo` requirement, eliminates IP guessing, and naturally satisfies the spec's "ansible apply with IP override" requirement — the VM's reachable address is `localhost:<port>`, while the production IP for the host lives in `host_vars/<host>.yml` and is baked into the image's persisted config.

**Alternatives considered:**

- *Keep `vmnet-shared` and discover the DHCP-assigned IP.* Rejected: still needs sudo, and the discovery is racy.
- *Bridged networking via a tap device.* Rejected: more setup per machine, no benefit for our use case (we don't need the VM to be reachable from elsewhere).

**Trade-off:** User-mode networking has lower throughput than vmnet-shared, but the `apt`/`pip` traffic during ansible apply is not throughput-bound for our typical runbooks.

### Decision 3: Pre-boot config via FAT32 only; everything else via ansible

The boot partition (FAT32) is mounted on macOS via `hdiutil attach -nomount`, then mounted at a controlled path with `mount -t msdos` (or via `hdiutil attach -mountpoint`). We write *only* the FAT32 first-boot files there: `wpa_supplicant.conf`, `ssh`, `userconf.txt`, and a `cmdline.txt` tweak if needed. The ext4 root partition is **never** mounted on macOS — every change to the rootfs happens via ansible against the booted VM.

**Why:** macOS has no native ext4 driver. Avoiding the ext4 mount keeps the design portable across raspios changes and avoids paying for a Paragon driver or shipping libguestfs. Anything we'd want to do with a rootfs mount (write systemd units, drop config files) is already expressible in our ansible roles.

**Alternatives considered:**

- *Mount ext4 via a third-party driver.* Rejected: external dependency, license cost, fragile across macOS updates.
- *Sidecar Linux VM that mounts the image and writes config.* Rejected: significantly more moving parts for no requirement we actually have.

### Decision 4: Generic arm64 kernel for `-machine virt` (NOT the raspios-shipped kernel)

The kernel used for the qemu boot is a **generic arm64 kernel built with `kvm_guest.config`** (or equivalent virt-friendly defconfig), NOT the kernel shipped inside the raspios FAT32 partition. The kernel is fetched as a pre-built artifact from the storage backend under `base/kernels/<kver>/Image` and is keyed by kernel version, not by raspios release. The current checked-in `kernels/Image` is the seed; subsequent kernel updates are uploaded to R2 by the operator (or, in the future, by a kernel-build CI job).

**Why:** The raspios kernel is configured for Pi hardware — no `virtio-blk`, no `virtio-net`, no virtio console — so booting it under `-machine virt` does not work. Confirmed by the working example at `gist.github.com/cGandom/23764ad5517c8ec1d7cd904b923ad863`, which builds its own kernel from kernel.org with `kvm_guest.config` rather than using the shipped raspios kernel. raspios userspace runs fine on top of any sufficiently recent arm64 kernel — the kernel/userspace coupling is loose enough that one virt-friendly kernel serves many raspios releases.

**Alternatives considered:**

- *Extract `kernel*.img` from the raspios FAT32 partition (the previous draft of this decision).* Rejected: those kernels lack the virtio drivers needed for `-machine virt` booting our virtio-blk root and virtio-net interface.
- *Switch to `-machine raspi3b` and use the raspios kernel as-is.* Rejected for the default path: `raspi3b` is much slower (closer to real-Pi-3 performance), constrained on memory (1GB), has finicky networking, and doesn't get us closer to Pi4/Pi5 fidelity. **Kept as a fallback option** behind a flag for cases where userspace requires hardware the virt path can't provide; flagged as Open Question 1.
- *UEFI/TF-A firmware path with `-bios`.* Rejected: more complex setup, no advantage for our `-machine virt` boot path.
- *Build the kernel as a phase of the pipeline.* Rejected: cross-compiler setup on macOS is non-trivial and the kernel changes far less often than raspios releases. Pre-built artifact is the right cadence.

**Implications:**

- The `latest.json` per-host pointer SHOULD record the kernel version used, so we can reproduce a build.
- A `kernel update` operator workflow is documented (build + upload), but is out of scope for this change to *implement* — the seed kernel in `kernels/Image` ships with this change.

### Decision 5: Storage backends behind a single Python interface

A `StorageBackend` ABC with two concrete implementations: `R2Backend` (using `boto3` with a Cloudflare R2 endpoint URL) and `LocalBackend` (filesystem). The interface is small: `fetch(key, dest_path)`, `put(src_path, key)`, `exists(key)`, `list(prefix)`.

**Why over rclone/aws-cli subprocess calls:**

- We need structured error handling (`exists` differs from "transient network blip" differs from "credentials missing"), and shelling out makes that tedious.
- `boto3` is already a transitive dependency of the ansible ecosystem in this repo; no net-new tooling.
- Lets us write the offline-mode test as a real unit test against `LocalBackend` without mocking subprocess.

**Trade-off:** `boto3`-direct means we own the R2-endpoint config; with `rclone`, the operator's existing config would Just Work. We mitigate by reading from `~/.config/rclone/rclone.conf` if present (parse the R2 remote section) so operators who already have rclone set up don't reconfigure.

### Decision 6: R2 key layout

```
base/raspios-arm64-lite/<release-id>/<release-id>.img.xz
base/raspios-arm64-lite/<release-id>/<release-id>.img.xz.sha256
built/<host>/<release-id>/<build-ts>.img.zst
built/<host>/<release-id>/<build-ts>.img.zst.sha256
built/<host>/latest.json     # { "release_id": "...", "build_ts": "...", "key": "..." }
```

`<release-id>` is the date-stamped raspios identifier (e.g. `2025-12-04-raspios-trixie-arm64-lite`). `<build-ts>` is a UTC ISO-8601 timestamp without colons (filesystem-safe). The `latest.json` pointer is written **last**, atomically, after the artifact upload succeeds.

**Why:** The `built/<host>/...` shape is what the future fleet scheduler needs without any rework. The `latest.json` pointer means a "give me the latest known-good for `foo`" lookup is one GET, not a list.

### Decision 7: zstd for built artifacts, xz for base mirror

Built images compress with `zstd -19` (~7-8x ratio, decompresses in seconds). Base mirror images stay in upstream's xz format (we don't recompress what upstream ships).

**Why:** zstd's decompress speed matters when an operator is rushing to flash a card; xz's better ratio doesn't help once we already have the artifact in R2 (zero egress).

**Alternatives considered:** xz everywhere (slower decompress, marginal extra ratio); none / raw (3-4x more R2 storage, slower uploads on slow connections).

### Decision 8: Credentials from environment, layered

Credential resolution order: explicit CLI flag → environment variable → `~/.config/rclone/rclone.conf` parse → fail with a clear error.

**Why:** Environment is the lowest common denominator; an operator using `direnv`, `1Password CLI` (`op run --env-file ...`), or `sops exec-env` all converge to env vars at invocation time. We don't bake any one secret-store choice into the engine.

**Alternatives considered:** Hard-coded sops integration (forces sops on every operator); 1Password-only (forces 1Password on every operator). The env-var seam keeps both paths open.

### Decision 9: Phase markers and timing capture

A `phase()` context manager records start/end wall-clock around each labeled phase. Timings live in a list of dicts; on EXIT (success or failure), the list is emitted in two forms:

- Human: aligned table to stderr.
- Machine: a single JSON-Lines stream to a configurable path (default `build_images/<host>-<build-ts>.timings.jsonl`), one record per phase, plus a final summary record.

Phases that didn't run because of upstream failure get a `not_run: true` record so consumers can distinguish "skipped" from "missing data".

### Decision 10: Working-copy layout

```
build_images/                  # operator-visible output (existing dir)
.cache/qemu-image-builder/
  base/<release-id>/...        # local mirror of base/ key prefix
  built/<host>/<release-id>/...# local working copies of built artifacts
  kernels/<release-id>/...     # extracted kernel + DTB per release
```

`build_images/` stays as the human-facing output; the cache is hidden under `.cache/` (and gitignored). The cache layout intentionally mirrors the R2 key layout so `LocalBackend` can serve as both a real backend and a debugging mirror of R2.

## Risks / Trade-offs

- **qemu boot can hang indefinitely on a malformed config.** → Hard timeout (default 5 min) on the "wait for ssh on `localhost:<port>`" loop; on timeout, dump the qemu serial log and fail the phase.
- **Ansible runbooks may have implicit assumptions about the production IP.** → A pre-flight grep over `roles/` for hard-coded IPs that only make sense at production time; document a `target_host_ip` variable convention so persisted config is parameterized rather than substituted from `ansible_host`.
- **Pre-baked secrets (WiFi PSK, etc.) in the image age.** → Out of scope for this change (engine is one-shot, on-demand). Flagged as a `image-fleet-prebuilder` concern for the follow-up.
- **macOS bumps `hdiutil` behavior.** → Use `hdiutil attach -nomount` and explicit `mount_msdos` so we control mount points; if a future macOS regresses this, the failure is at one phase boundary, not throughout.
- **Cache directory grows unboundedly.** → A `prune` subcommand that keeps the N most recent base releases and the N most recent built artifacts per host. Default N=2 base, N=3 built. Documented; not auto-run.
- **Two builds for the same host racing.** → A `flock`-equivalent on `.cache/qemu-image-builder/locks/<host>`. Second invocation fails fast with a clear "build for `<host>` already running" message.
- **R2 partial upload on crash.** → Always upload to a `*.partial` key first, then copy/rename to the final key, then write `latest.json`. Failed uploads leave `*.partial` debris that `prune` cleans up.
- **Base raspios image drifts from upstream Debian between release dates.** Confirmed in spike: a Dec-2025 raspios image cannot `apt-get update` in May 2026 without `Acquire::AllowReleaseInfoChange=true` because the trixie point-release moved from 13.2 → 13.4 and the cached `InRelease` is stale. This is not a virt issue — it would happen on a real Pi too. → The pipeline runs `apt clean && apt-get update -o Acquire::AllowReleaseInfoChange=true` as the first step after boot, before any ansible role apply, so role-level `apt:` tasks find a fresh, consistent cache.

## Migration Plan

1. Land the new engine alongside the existing scripts. New entrypoint at `scripts/qemu_image_builder/` and the Python package; no edits to `build_image.sh` or `post_install.sh` in this change.
2. Operator validates by running the new engine for one host end-to-end, flashing the result, and confirming the Pi boots configured.
3. Once validated, a follow-up change deletes `build_image.sh`, `post_install.sh`, the per-region `*-wifi.sh` scripts, `userconf.txt`, and the checked-in `kernels/Image` (replaced by per-release extraction).
4. **Rollback:** the old scripts remain untouched in this change, so reverting is `git revert` of the new code; no state to undo.

## Open Questions

1. **Do our ansible runbooks all succeed against `-machine virt` userspace?** Spike confirmed: boot, authenticated SSH, ansible `ping`/`setup`/`command`-with-become, and VM-to-internet network egress all work. What remains unverified is whether specific roles (`mikolak-net.raspi_config`, anything touching hciuart/GPIO/hardware probes) complete cleanly — best answered while implementing, since failures are tactical (`when:` guards, mocks for hardware modules) rather than architectural. The `--machine raspi3b` fallback flag from Decision 4 stays as the escape hatch.
2. **Pi5 has no qemu machine type and `-machine raspi4b` Pi4 emulation is incomplete (per the gist's linked qemu issue 1208).** Our build path under `virt` produces an image that should boot Pi5 hardware (raspios-arm64-lite is one image for Pi3/4/5), but we cannot fully *test* a Pi5-specific code path under emulation. We will need to validate Pi5 on real hardware before declaring success.
3. **Default zstd level:** `-19` is great for storage but slow on compress. Worth benchmarking against `-9` for the typical 5-8GB image to see if the storage savings justify the time.
4. **Kernel update cadence:** the seed kernel ships with this change, but the operator workflow for building and uploading new kernels is documented, not automated. Worth deciding (in a follow-up) whether to add a CI job that rebuilds the virt kernel against new upstream releases on a schedule.
5. **Should `latest.json` be signed?** Not in scope here, but worth noting if we ever ship an image to a third party off this same store.
