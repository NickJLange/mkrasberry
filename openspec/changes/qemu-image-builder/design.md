## Context

The repo's current Pi-provisioning flow is `build_image.sh` + `post_install.sh`: copy a raspios `.img` from `images/`, expand it, `hdiutil attach` so macOS auto-mounts the FAT32 boot partition at `/Volumes/bootfs`, drop `wpa_supplicant.conf` / `ssh` / `userconf.txt` into it, detach, then boot under `qemu-system-aarch64` using a local `kernels/Image` and `vmnet-shared` networking. Ansible runbooks under `playbooks/` and `roles/` are then run separately against the eventual Pi over its production network (`make configure`).

Constraints we are designing within:

- **Host platform is macOS.** `vmnet-shared`, `hdiutil`, FAT32 native mount, lack of a native ext4 driver. No `losetup`, no `qemu-nbd` without extra work.
- **The repo already standardizes on Python tooling** (`pyproject.toml`, `uv.lock`) and bash scripts under `scripts/`. We have both registers available.
- **Ansible inventory is host-keyed** (`hosts`, `host_vars/<host>.yml`). The build engine will reuse this rather than invent a parallel fleet model.
- **Kernel for qemu (`kernels/Image`)** is currently a local, gitignored snapshot. Per Decision 4 it is a generic virt kernel versioned independently of raspios releases, not something extracted from each release.
- **The current `vmnet-shared` path requires `sudo`** and gives the VM an unpredictable IP — that is the half-broken seam this change fixes.
- **Raspberry Pi OS Bookworm and later use NetworkManager.** A `wpa_supplicant.conf` on the boot partition no longer configures Wi-Fi; Trixie images additionally ship cloud-init for first-boot customisation.

Stakeholders: the operator (one person doing fleet maintenance), and a future scheduler (the `image-fleet-prebuilder` change) that will call this engine on a cadence.

## Goals / Non-Goals

**Goals:**

- Single command: `qemu-image-builder build --host <name>` produces an image in the configured store, no SD card touched.
- Predictable, sudo-free networking between host and VM, reachable only from the build machine's loopback interface.
- macOS-friendly: no Linux-only mount tooling.
- Storage abstraction is thin enough that adding a third backend (e.g. local NAS over SSH) is mechanical.
- R2 key layout is **already shaped for fleet pre-builds** so the follow-up change is additive.
- Failure of any phase exits non-zero with the failing phase named, and timings are still emitted.
- Every artifact (base image, kernel, built image) is checksum-verified before use, whatever its source.

**Non-Goals:**

- Cross-platform support (Linux/Windows hosts).
- Pre-building images for the whole fleet on a schedule — that's `image-fleet-prebuilder`.
- A new fleet inventory or host model — we use ansible's `host_vars/`.
- Runtime credential rotation for tokens baked into images.
- A GUI / web UI.
- Migrating archived images out of the existing `images/` directory.
- Bit-for-bit reproducible images or a pinned apt snapshot (see Review decision R4).
- Fully air-gapped builds: the VM still needs package egress for `apt` and ansible.

## Decisions

### Decision 1: Top-level driver in Python; thin shell shims allowed

The orchestrator is a Python entrypoint (`scripts/qemu_image_builder/cli.py`, exposed as the `qemu-image-builder` console script via `pyproject.toml`). Bash is acceptable for one-line wrappers but not for the pipeline itself.

**Why:** The pipeline has real branching (cache hit/miss, backend selection, retries on `ssh` ready-check, structured timing capture, JSON-Lines output). Bash makes that brittle, especially with `set -euo pipefail` and trap interactions around timing. Python also makes the storage-backend abstraction (a single interface with two implementations) straightforward.

**Alternatives considered:**

- *All bash, like the current scripts.* Rejected: the cache-on-miss + structured-timings + retry logic gets ugly fast; we already saw the existing `build_image.sh` skip the post-install branch silently when `/Volumes/bootfs` was missing.
- *Make / Makefile.* Rejected: orchestration logic doesn't map cleanly to file targets; we want timings and failure modes that Make doesn't express well.

### Decision 2: User-mode networking with a loopback-bound hostfwd, not vmnet-shared

qemu boots with `-netdev user,id=net0,hostfwd=tcp:127.0.0.1:<port>-:22` (a free loopback port is chosen per build by binding `127.0.0.1:0`; if qemu then fails to bind the forward, the builder picks a new port and relaunches, up to 3 times; `--ssh-port` overrides for a single build). The host side of the forward is bound explicitly to `127.0.0.1`, so the VM's SSH port is not exposed on any other host interface. Ansible connects to `127.0.0.1:<port>`.

**Connection-address override (see Review decision R3):** the builder never overrides `ansible_host`. The VM's address is supplied as connection-only extra-vars (`-e ansible_ssh_host=127.0.0.1 -e ansible_port=<port>`), the same mechanism the `Makefile`'s `host_ip_override` already uses. `ansible_host` keeps the production address from the repo inventory, and the builder also passes it explicitly as `target_host_ip`. Roles that persist the host's own address must read `target_host_ip` (or `ansible_host`), never `ansible_default_ipv4` or the connection address — under user-mode networking the VM's own facts report `10.0.2.15`. Known consumer to audit: `roles/tvTunerSetup/templates/epgstation.config.yml` uses `ansible_default_ipv4`.

**Why:** This eliminates the `sudo` requirement and IP guessing, and keeps the production address intact in every variable that roles might persist.

**Alternatives considered:**

- *Keep `vmnet-shared` and discover the DHCP-assigned IP.* Rejected: still needs sudo, and the discovery is racy.
- *Bridged networking via a tap device.* Rejected: more setup per machine, no benefit for our use case (we don't need the VM to be reachable from elsewhere).
- *Override `ansible_host` with `localhost`.* Rejected: roles and templates that read `hostvars[...].ansible_host` (e.g. the telegraf DNS-monitoring template) would persist `localhost`/`127.0.0.1` into the image.

**Trade-off:** User-mode networking has lower throughput than vmnet-shared, but the `apt`/`pip` traffic during ansible apply is not throughput-bound for our typical runbooks. Connection overrides passed as extra-vars apply to every host in the play, so the image-build entrypoint must not `delegate_to` other inventory hosts; the pre-flight check flags `delegate_to` in the playbooks it imports.

### Decision 3: Pre-boot config via FAT32 only; everything else, including Wi-Fi, via ansible

The boot partition (FAT32) is mounted on macOS via `hdiutil attach -nomount`, then mounted at a controlled path with `mount -t msdos` (or via `hdiutil attach -mountpoint`). We write *only* these first-boot files there: `ssh`, `userconf.txt`, and a `cmdline.txt` tweak if needed. The ext4 root partition is **never** mounted on macOS — every change to the rootfs happens via ansible against the booted VM.

**Wi-Fi (see Review decision R2):** Wi-Fi is not needed during the build (the VM uses virtio-net). The production Wi-Fi connection is persisted by ansible as a NetworkManager keyfile, `/etc/NetworkManager/system-connections/qib-wifi.nmconnection` (fixed filename, so the SSID is never a path component; owner `root`, mode `0600`), together with the Wi-Fi regulatory country. No `wpa_supplicant.conf` is written to the boot partition, because Bookworm and later ignore it.

**Bootstrap credential (see Review decision R5):** `userconf.txt` creates the bootstrap user with a random per-build password. The plaintext lives only in the builder's memory and in the environment of the child processes that need it. Before export, ansible locks that password (`usermod -L`), so the built image accepts only the SSH keys installed by the existing roles. The password is never delivered to the operator.

**Why:** macOS has no native ext4 driver. Avoiding the ext4 mount keeps the design portable across raspios changes and avoids paying for a Paragon driver or shipping libguestfs. Anything we'd want to do with a rootfs mount (write systemd units, drop config files, NetworkManager keyfiles) is already expressible in our ansible roles.

**Alternatives considered:**

- *Mount ext4 via a third-party driver.* Rejected: external dependency, license cost, fragile across macOS updates.
- *Sidecar Linux VM that mounts the image and writes config.* Rejected: significantly more moving parts for no requirement we actually have.
- *cloud-init `network-config` on the boot partition (Trixie).* Rejected for now: Bookworm images don't use it, cloud-init has been disabled in some Trixie builds, and it would run during the VM's first boot anyway, not on the Pi.

### Decision 4: Generic arm64 kernel for `-machine virt` (NOT the raspios-shipped kernel)

The kernel used for the qemu boot is a **generic arm64 kernel built with `kvm_guest.config`** (or equivalent virt-friendly defconfig), NOT the kernel shipped inside the raspios FAT32 partition. The kernel is fetched as a pre-built artifact from the storage backend under `base/kernels/<kver>/Image` and is keyed by kernel version, not by raspios release. The kernel version and its SHA-256 are pinned in the committed repo config (`qemu-image-builder.toml`, `[kernel] version` / `sha256`). The fetched `Image` is verified against the pinned digest every time it is used (fresh fetch or cache hit) before it is passed to qemu; a mismatch aborts the build. The operator's existing local `kernels/Image` is the seed: it is uploaded once to `base/kernels/<kver>/Image` (with an `Image.sha256` sidecar) and its digest is committed. Later kernel updates follow the same recipe (or, in the future, a kernel-build CI job).

**Why:** The raspios kernel is configured for Pi hardware — no `virtio-blk`, no `virtio-net`, no virtio console — so booting it under `-machine virt` does not work. Confirmed by the working example at `gist.github.com/cGandom/23764ad5517c8ec1d7cd904b923ad863`, which builds its own kernel from kernel.org with `kvm_guest.config` rather than using the shipped raspios kernel. raspios userspace runs fine on top of any sufficiently recent arm64 kernel — the kernel/userspace coupling is loose enough that one virt-friendly kernel serves many raspios releases. Pinning the digest in git gives a trust anchor outside the bucket, so a tampered or corrupted kernel object is caught.

**Alternatives considered:**

- *Extract `kernel*.img` from the raspios FAT32 partition (the previous draft of this decision).* Rejected: those kernels lack the virtio drivers needed for `-machine virt` booting our virtio-blk root and virtio-net interface.
- *Switch to `-machine raspi3b` and use the raspios kernel as-is.* Rejected for the default path: `raspi3b` is much slower (closer to real-Pi-3 performance), constrained on memory (1GB), has finicky networking, and doesn't get us closer to Pi4/Pi5 fidelity. Not offered as a fallback either: it would need its own Pi kernel/DTB path. Roles that need real hardware get `when:` guards instead (Open Question 1).
- *UEFI/TF-A firmware path with `-bios`.* Rejected: more complex setup, no advantage for our `-machine virt` boot path.
- *Build the kernel as a phase of the pipeline.* Rejected: cross-compiler setup on macOS is non-trivial and the kernel changes far less often than raspios releases. Pre-built artifact is the right cadence.
- *Verify only against the `Image.sha256` sidecar in the bucket.* Rejected: it lives next to the object it protects, so it catches corruption but not tampering.

**Implications:**

- The build manifest and `latest.json` record the kernel version and digest used, so we can reproduce a build.
- A `kernel update` operator workflow is documented (build + upload + commit the digest), but is out of scope for this change to *automate*.

### Decision 5: Storage backends behind a single Python interface

A `StorageBackend` ABC with two concrete implementations: `R2Backend` (using `boto3` with a Cloudflare R2 endpoint URL) and `LocalBackend` (filesystem). The interface is small:

- `fetch(key, dest_path)` — download an object.
- `put(src_path, key)` — upload an object. Each `put` is atomic per object: readers never see a partially written object under `key` (R2: single PUT or completed multipart upload; local: write to a temp file in the same directory, then `os.replace`).
- `exists(key) -> bool`, `list(prefix) -> Iterator[str]`.
- `delete(key)` — idempotent; deleting a missing key is not an error. Used by `prune` and by staging cleanup.
- `promote(staging_key, final_key)` — make a staged object visible under its final key. R2: server-side copy (boto3 managed `copy`, multipart for large objects) followed by `delete(staging_key)`. Local: `os.replace`.

Errors are structured: `StorageNotFound`, `StorageAuthError`, `StorageTransientError`.

**Key and path validation:** every key is built from validated components. Host identifiers and kernel versions must match `^[A-Za-z0-9][A-Za-z0-9._+-]{0,62}$`; release ids must match the upstream pattern `^\d{4}-\d{2}-\d{2}-raspios-[a-z]+-arm64-lite$`; build timestamps are generated internally. Components containing `/`, `\`, NUL, or equal to `.`/`..` are rejected before any read or write. `LocalBackend` additionally resolves every path (following symlinks) and refuses any path that does not stay under the configured backend root. The same check applies to the local cache root.

**Why over rclone/aws-cli subprocess calls:**

- We need structured error handling (`exists` differs from "transient network blip" differs from "credentials missing"), and shelling out makes that tedious.
- Lets us write the backend tests as real unit tests against `LocalBackend` without mocking subprocess.

`boto3` is **not** currently a dependency of this project (`pyproject.toml` lists only `ansible-core` and `datadog`). It is declared as a direct runtime dependency and `uv.lock` is regenerated in the same commit.

**Trade-off:** `boto3`-direct means we own the R2-endpoint config; with `rclone`, the operator's existing config would Just Work. We mitigate by reading from `~/.config/rclone/rclone.conf` if present (parse the R2 remote section) so operators who already have rclone set up don't reconfigure.

### Decision 6: R2 key layout

```
base/raspios-arm64-lite/<release-id>/<release-id>.img.xz
base/raspios-arm64-lite/<release-id>/<release-id>.img.xz.sha256   # publisher checksum, copied at mirror time
base/kernels/<kver>/Image
base/kernels/<kver>/Image.sha256
built/<host>/<release-id>/<build-ts>.img.zst
built/<host>/<release-id>/<build-ts>.img.zst.sha256
built/<host>/<release-id>/<build-ts>.manifest.json
built/<host>/latest.json
<any of the built/ keys above>.partial                             # private staging object, never published
```

`<release-id>` is the date-stamped raspios identifier (e.g. `2025-12-04-raspios-trixie-arm64-lite`). `<build-ts>` is a UTC ISO-8601 timestamp without colons (filesystem-safe), e.g. `20260512T143005Z`.

The manifest records: host, release id, base `.img.xz` SHA-256, kernel version and SHA-256, repo git commit (and whether the tree was dirty), image-build playbook list, resolved package list (`dpkg-query -W` output), and the built artifact's SHA-256.

`latest.json` schema: `{ "schema_version": 1, "host": "...", "release_id": "...", "build_ts": "...", "key": "built/...img.zst", "sha256": "...", "manifest_key": "built/...manifest.json", "kernel_version": "...", "kernel_sha256": "..." }`.

**Publish protocol:** upload the artifact, its sidecar, and the manifest each to `<final-key>.partial`, then `promote` each to its final key, and only after all three succeed `put` `latest.json`. `latest.json` is a single atomic object write, so readers see either the previous pointer or the new one. Immediately before writing, the builder re-reads `latest.json` and does not replace a pointer whose `build_ts` is newer than its own (the build still succeeds; it logs that a newer build is already published). This read-then-write is not atomic across machines, so the supported mode is one builder machine per bucket (Review decision R9); the per-host `flock` serializes builds on that machine. Publication is defined by `latest.json` alone: a `built/` object no pointer references is unpublished, even under its final key. On failure the builder makes a best-effort `delete` of its own `.partial` and already-promoted final-key objects; `prune --remote` removes any unreferenced `built/` objects older than 24h, which covers crashes. `.partial` keys are never referenced by `latest.json`, and consumers (`latest`, future fleet tooling) ignore them.

**Why:** The `built/<host>/...` shape is what the future fleet scheduler needs without any rework. The `latest.json` pointer means a "give me the latest known-good for `foo`" lookup is one GET, not a list.

### Decision 7: zstd for built artifacts, xz for base mirror

Built images compress with `zstd -19` (~7-8x ratio, decompresses in seconds). Base mirror images stay in upstream's xz format (we don't recompress what upstream ships). The builder decompresses the verified `.img.xz` with Python's `lzma` straight into the per-build working image during `prep`. The cache keeps only the `.img.xz` that the publisher checksum covers.

**Why:** zstd's decompress speed matters when an operator is rushing to flash a card; xz's better ratio doesn't help once we already have the artifact in R2 (zero egress). Keeping the base cached as `.img.xz` means the publisher checksum can be re-checked on every use without introducing a second, self-computed trust chain for a raw copy.

**Alternatives considered:** xz everywhere (slower decompress, marginal extra ratio); none / raw (3-4x more R2 storage, slower uploads on slow connections); caching a decompressed raw base and cloning it with `cp -c` (faster prep, but needs its own locally recorded checksum).

### Decision 8: Credentials from environment, layered

R2 credential resolution order: explicit CLI flag → environment variable → `~/.config/rclone/rclone.conf` parse → fail with a clear error.

**Why:** Environment is the lowest common denominator; an operator using `direnv`, `1Password CLI` (`op run --env-file ...`), or `sops exec-env` all converge to env vars at invocation time. We don't bake any one secret-store choice into the engine.

**Bootstrap SSH credential:** the per-build password (Decision 3) reaches child processes only through the environment, never through argv or files. The SSH readiness probe runs `sshpass -e ssh -o BatchMode=no -o PubkeyAuthentication=no -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=<workdir>/known_hosts -o ConnectTimeout=5 -p <port> <user>@127.0.0.1 true`, with `SSHPASS` set only in that child's environment. Ansible gets the same password through an extra-var that is a template, not a value: `-e '{"ansible_password": "{{ lookup(\"env\", \"QIB_BOOTSTRAP_PASSWORD\") }}"}'`. Its SSH arguments point at the same per-build `known_hosts` with `StrictHostKeyChecking=accept-new`, so the first connection is non-interactive, a key change later in the build fails loudly, and the operator's `~/.ssh/known_hosts` is never touched. The password is used only for the stage-1 invocation. Stage-1 installs `local_ssh_user`'s key (the bootstrap user is `local_ssh_user`) and may lock the password, so the builder then re-probes as `local_ssh_user` with key authentication only (`-o PasswordAuthentication=no`, the operator's key from `ssh-agent`) and runs stages 2–5 as a second invocation without `ansible_password`. If stage-1 rotates host keys (the `Makefile` notes it can), the builder clears the per-build `known_hosts` at that boundary before the re-probe; it never disables host-key checking globally.

**Alternatives considered:** Hard-coded sops integration (forces sops on every operator); 1Password-only (forces 1Password on every operator). The env-var seam keeps both paths open.

### Decision 9: Phase markers and timing capture

The canonical phase list, in order, used identically in the specs, tasks, and emitted records:

| # | Phase | Covers |
|---|-------|--------|
| 1 | `fetch` | resolve release, fetch + verify base `.img.xz` and kernel `Image` |
| 2 | `prep` | xz-decompress into the working image, grow it, write FAT32 first-boot files |
| 3 | `boot` | start qemu, wait for SSH banner and authenticated login |
| 4 | `apt-refresh` | `apt-get clean`, then `apt-get update -o Acquire::AllowReleaseInfoChange=true` |
| 5 | `ansible-apply` | run stage-1 with the bootstrap password, re-probe with key auth, run `playbooks/image-build.yml` (stages 2–5), collect the package list for the manifest |
| 6 | `export` | lock bootstrap password, clean shutdown, fsync, move raw `.img` to the output dir |
| 7 | `compress` | zstd-compress, compute SHA-256 sidecar, write manifest |
| 8 | `upload` | staged upload, promote, publish `latest.json` |

A `phase()` context manager records start/end around each labeled phase using a monotonic clock. On exit (success or failure), records are emitted in two forms:

- Human: aligned table to stderr.
- Machine: a JSON Lines file, always written, at `--timing-output <path>` (default `build_images/<host>-<build-ts>.timings.jsonl`). The record contract is defined in the `build-metrics` spec.

Every phase gets exactly one record with `status` one of `ok`, `failed`, `not_run` (an earlier phase failed), or `skipped` (intentionally disabled, e.g. `upload` under `--no-upload`).

### Decision 10: Working-copy layout

```
build_images/                       # operator-visible output; created by the builder, gitignored, mode 0700
.cache/qemu-image-builder/          # mode 0700
  base/raspios-arm64-lite/<release-id>/...   # local mirror of base/ key prefix (.img.xz + .sha256)
  kernels/<kver>/Image              # verified virt kernel, keyed by kernel version
  work/<host>-<build-ts>/           # per-build workdir: working .img, serial.log, ansible.log, known_hosts, inventory
  locks/<host>.lock
```

`build_images/` stays as the human-facing output; the cache is hidden under `.cache/` (already gitignored). The base cache layout mirrors the R2 key layout so `LocalBackend` can serve as both a real backend and a debugging mirror of R2.

**Retained artifacts are owner-only.** The builder runs with `umask 077`; `build_images/`, the cache, and every workdir are `0700`, and files inside are `0600`. A working image retained after a failed build can contain the Wi-Fi PSK, host secrets, and the bootstrap password hash. Logs must not contain secrets: credential-bearing ansible tasks use `no_log: true`, and the bootstrap password never appears in argv or logs. On success the workdir is deleted. On failure it is kept for diagnosis and the failure output prints its path. `prune` deletes retained failed workdirs (`--keep-failed N`, default 1).

## Risks / Trade-offs

- **qemu boot can hang indefinitely on a malformed config.** → Hard timeout (default 5 min) on the "wait for ssh on `127.0.0.1:<port>`" loop; on timeout, dump the qemu serial log and fail the phase.
- **Ansible runbooks may have implicit assumptions about the production IP.** → A pre-flight grep over `roles/` for hard-coded IPs and for `ansible_default_ipv4` uses that only make sense at production time; roles that persist the host's own address read `target_host_ip` (Decision 2).
- **Pre-baked secrets (WiFi PSK, etc.) in the image age.** → Out of scope for this change (engine is one-shot, on-demand). Flagged as a `image-fleet-prebuilder` concern for the follow-up.
- **cloud-init on Trixie images runs during the VM's first boot.** → It records its instance as complete, so it does not re-run on the Pi. The ansible audit (task 6.5) checks that it did not write a network config that would conflict with the NetworkManager keyfile.
- **macOS bumps `hdiutil` behavior.** → Use `hdiutil attach -nomount` and explicit `mount_msdos` so we control mount points; if a future macOS regresses this, the failure is at one phase boundary, not throughout.
- **Cache directory grows unboundedly.** → A `prune` subcommand that keeps the N most recent base releases and the N most recent built artifacts per host. Default N=2 base, N=3 built. Documented; not auto-run.
- **Two builds for the same host racing.** → A `flock`-equivalent on `.cache/qemu-image-builder/locks/<host>.lock`. Second invocation fails fast with a clear "build for `<host>` already running" message. The lock is per machine. Builds from several machines against one bucket are unsupported (Review decision R9); the stale-`build_ts` check on `latest.json` and the 24h age limit on `prune --remote` only limit the damage if it happens.
- **R2 partial upload on crash.** → Uploads go to `*.partial` staging keys first, are promoted to final keys, and only then is `latest.json` written (Decision 6). A crash leaves at most unreferenced `.partial` objects, which the builder deletes on handled failures and `prune --remote` removes once older than 24h.
- **Corrupted or tampered cache entries.** → Base images are verified against the publisher checksum, and kernels against the pinned digest, on every use. A local cache mismatch discards the entry and re-fetches it from the backend. A backend mismatch re-fetches from upstream and re-mirrors. A mismatch from every available source aborts the build.
- **Base raspios image drifts from upstream Debian between release dates.** Confirmed in spike: a Dec-2025 raspios image cannot `apt-get update` in May 2026 without `Acquire::AllowReleaseInfoChange=true` because the trixie point-release moved from 13.2 → 13.4 and the cached `InRelease` is stale. This is not a virt issue — it would happen on a real Pi too. → The `apt-refresh` phase runs `apt-get clean` and then `apt-get update -o Acquire::AllowReleaseInfoChange=true` as two separate commands, before any ansible role apply, so role-level `apt:` tasks find a fresh, consistent cache.
- **Package versions resolve live.** → Two builds from identical inputs can differ in package versions. Accepted (Review decision R4); the manifest records the resolved package list so differences are visible.

## Migration Plan

1. Land the new engine alongside the existing scripts. New `qemu-image-builder` entrypoint in `scripts/qemu_image_builder/`, plus the new `playbooks/image-build.yml`; no edits to `build_image.sh`, `post_install.sh`, or the `Makefile` in this change.
2. Seed the kernel: upload the local `kernels/Image` to `base/kernels/<kver>/Image` (+ `.sha256`) and commit its version and digest in `qemu-image-builder.toml`.
3. Operator validates by running the new engine for one host end-to-end, flashing the result, and confirming the Pi boots configured.
4. Once validated, a follow-up change deletes `build_image.sh`, `post_install.sh`, the per-region `*-wifi.sh` scripts, `userconf.txt`, and the local `kernels/Image` (superseded by the versioned generic virt kernel under `base/kernels/<kver>/Image`, per Decision 4).
5. **Rollback:** the old scripts remain untouched in this change, so reverting is `git revert` of the new code; R2 objects written by the new engine can be left in place or deleted with `prune --remote`.

## Open Questions

1. **Do our ansible runbooks all succeed against `-machine virt` userspace?** Spike confirmed: boot, authenticated SSH, ansible `ping`/`setup`/`command`-with-become, and VM-to-internet network egress all work. What remains unverified is whether specific roles (`mikolak-net.raspi_config`, anything touching hciuart/GPIO/hardware probes) complete cleanly — best answered while implementing, since failures are tactical (`when:` guards, mocks for hardware modules) rather than architectural. There is no emulated-Pi fallback (Decision 4); a role that cannot run under `virt` is guarded or skipped.
2. **Pi5 has no qemu machine type and `-machine raspi4b` Pi4 emulation is incomplete (per the gist's linked qemu issue 1208).** Our build path under `virt` produces an image that should boot Pi5 hardware (raspios-arm64-lite is one image for Pi3/4/5), but we cannot fully *test* a Pi5-specific code path under emulation. We will need to validate Pi5 on real hardware before declaring success.
3. **Default zstd level:** `-19` is great for storage but slow on compress. Worth benchmarking against `-9` for the typical 5-8GB image to see if the storage savings justify the time.
4. **Kernel update cadence:** the seed kernel is uploaded as part of this change's rollout, but the operator workflow for building and uploading new kernels is documented, not automated. Worth deciding (in a follow-up) whether to add a CI job that rebuilds the virt kernel against new upstream releases on a schedule.
5. **Should `latest.json` be signed?** Not in scope here, but worth noting if we ever ship an image to a third party off this same store.

## Review decisions (pending owner)

These were chosen while addressing the PR #62 review, picking the most conservative option consistent with the rest of this design. Each can be overturned.

- **R1 — Kernel source.** Follow Decision 4: one generic virt kernel stored under `base/kernels/<kver>/Image`, pinned by version and SHA-256 in committed config and verified on every use. No per-release extraction. *Alternative:* per-release extraction (contradicts Decision 4, and the kernels lack virtio).
- **R2 — Wi-Fi on Bookworm/Trixie.** Ansible writes a NetworkManager keyfile (`0600`, root-owned) into the rootfs during `ansible-apply`; nothing Wi-Fi related goes on the boot partition. *Alternatives:* cloud-init `network-config` on the boot partition (Trixie only, and it would be consumed by the VM's first boot); keyfile dropped via a boot-partition first-run script.
- **R3 — Production address passing.** Never override `ansible_host`; pass the VM connection via `-e ansible_ssh_host=127.0.0.1 -e ansible_port=<port>` (the existing `Makefile` pattern) and pass the production address explicitly as `target_host_ip`; roles that persist their own address use `target_host_ip`. *Alternatives:* generated inventory that overrides `ansible_host` (breaks `hostvars[...].ansible_host` consumers); a brand-new connection variable that every play must opt into.
- **R4 — Reproducibility.** Configuration-equivalence only: same inputs → same applied configuration, with resolved package versions recorded in the manifest. *Alternative:* pin an apt snapshot (e.g. `snapshot.debian.org` + an archive.raspberrypi.com mirror) as a build input for true package-level reproducibility — more infrastructure, and the RPi archive has no official snapshot service.
- **R5 — Bootstrap credential delivery.** The random per-build password is never delivered; it is locked before export, and operator access is via the SSH keys the existing roles install. *Alternatives:* print it once to the operator's terminal; store it in the operator's secret store; use a fixed password from `host_vars` (vaulted).
- **R6 — Ansible build boundary.** The build applies `initial-playbook-stage-1.yml` (first invocation, bootstrap password) and then `playbooks/image-build.yml`, which imports `initial-playbook-stage-2.yml` … `initial-playbook-stage-5.yml` (second invocation, key auth after a re-probe) — the bootstrap portion of `make configure` — with stage-1 failures fatal rather than ignored (`|| true` in the `Makefile`). Service, restore, backup, wireguard, certificate, and datadog playbooks are excluded until added to the entrypoint explicitly. *Alternative:* mirror the full `make configure` sequence, including `syslog-configure`, `datadog-install`, `fix-locale`, `wireguard-install-simple`, and `internal_certs_update_endpoints`.
- **R7 — Offline scope.** "Offline" means no access to the storage backend or the upstream image source; the VM still needs package egress for `apt-refresh` and ansible. Offline builds require `--release <id>` (the catalog is unreachable) and verify the base image against a publisher SHA-256 committed in git under `[base.pinned]` in `qemu-image-builder.toml`; `qemu-image-builder fetch --release <id>`, run online, verifies against upstream and prints the line to commit. A release with no committed digest cannot be built offline, and the mirrored `.sha256` sidecar is never trusted on its own, so replacing an image and its sidecar together is caught. *Alternative:* a full offline mode with a local apt cache/proxy.
- **R8 — `--no-upload`.** Kept as an explicit debug exception: it suppresses all backend writes (including base-mirror uploads), marks `upload` as `skipped`, leaves `latest.json` untouched, and keeps the artifact in `build_images/`. *Alternative:* drop the flag and require `--backend local` for local-only builds.
- **R9 — Concurrent builders.** One builder machine per bucket is the supported mode; the per-host `flock` serializes builds on that machine, and `latest.json` is not replaced by an older `build_ts`. *Alternatives:* a distributed lock object in the bucket, or conditional (`If-Match`) pointer writes.
- **R10 — No emulated-Pi fallback.** `-machine raspi3b` is dropped rather than given a second kernel/DTB path; hardware-only roles are guarded instead. *Alternative:* keep it with a Pi kernel + DTB fetched and pinned like the virt kernel.
