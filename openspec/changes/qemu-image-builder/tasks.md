## 1. Project scaffolding

- [ ] 1.1 Create `scripts/qemu_image_builder/` Python package (`__init__.py`, `__main__.py`, `cli.py`) and wire a `qemu-image-builder` console-script entrypoint in `pyproject.toml`
- [ ] 1.2 Add direct runtime dependencies to `pyproject.toml`: `boto3`, `botocore`, `zstandard`, `pyyaml` (`tomllib` and `lzma` are stdlib on Python ≥3.12); add dev deps for testing (`pytest`, `pytest-mock`); run `uv lock` and commit the updated `uv.lock`
- [ ] 1.3 Add `.gitignore` entries for `build_images/`, `.cache/qemu-image-builder/`, `tmp/`, and any non-committed kernel/image artifacts; the builder creates `build_images/` (mode `0700`) on first run
- [ ] 1.4 Create the canonical config schema (file at `~/.config/qemu-image-builder/config.toml` plus committed repo-local `qemu-image-builder.toml`, which pins `[kernel] version` and `sha256`); document precedence (CLI flag > env > local toml > user toml > defaults)
- [ ] 1.5 Stand up a `Phase` context manager (timing capture per the metrics spec, monotonic clock) over the canonical phase list (`fetch`, `prep`, `boot`, `apt-refresh`, `ansible-apply`, `export`, `compress`, `upload`) with `record(name)` / `mark_not_run(name)` / `mark_skipped(name)` / `dump()` methods and unit tests covering success, exception, skipped, and "phase did not run" cases
- [ ] 1.6 Implement identifier validation (host, release id, kernel version) per design Decision 5 and run it before any storage or filesystem operation; unit tests for `..`, `.`, `/`, `\`, NUL, empty, and over-length inputs
- [ ] 1.7 Set `umask 077` at startup and create the cache, workdirs, and `build_images/` with mode `0700`; test that retained files are `0600`

## 2. Storage backend abstraction

- [ ] 2.1 Define `StorageBackend` ABC: `fetch(key, dest_path)`, `put(src_path, key)` (atomic per object), `exists(key) -> bool`, `list(prefix) -> Iterator[str]`, `delete(key)` (idempotent), `promote(staging_key, final_key)`. Document idempotence and error contract (`StorageNotFound`, `StorageAuthError`, `StorageTransientError`).
- [ ] 2.2 Implement `LocalBackend` rooted at a configurable directory, mirroring the R2 key layout from design.md (Decision 6) so it doubles as a debug mirror. `put` writes to a temp file in the target directory then `os.replace`; `promote` is `os.replace`; every resolved path (following symlinks) must stay under the root.
- [ ] 2.3 Implement `R2Backend` via `boto3` with explicit endpoint URL; `promote` = managed server-side `copy` then `delete`. Resolve credentials in order: explicit kwargs → env (`R2_ACCESS_KEY_ID`/`R2_SECRET_ACCESS_KEY`/`R2_ENDPOINT_URL`/`R2_BUCKET`) → `~/.config/rclone/rclone.conf` parse → fail with a structured `StorageAuthError`.
- [ ] 2.4 Write `tests/storage/test_local_backend.py` covering: round-trip put/fetch, `exists`/`list`/`delete` (including deleting a missing key), `promote`, missing-key error, prefix listing, and refusal of traversal keys and symlink escapes.
- [ ] 2.5 Write `tests/storage/test_r2_backend_credentials.py` covering the credential-resolution chain (env, rclone.conf parse, both absent → `StorageAuthError`) without making real R2 calls.
- [ ] 2.6 Implement the publish protocol from design Decision 6: upload artifact, sidecar, and manifest each to `<key>.partial`, `promote` each, then `put` `latest.json`; best-effort `delete` of own `.partial` and already-promoted final-key objects on failure. Test with `LocalBackend` that no `latest.json` change happens when any upload or promote fails, and that `.partial` objects are never referenced by `latest.json`.

## 3. Base image and kernel fetch + cache

- [ ] 3.1 Implement `RaspiosCatalog` that discovers the latest `raspios-arm64-lite` release identifier and publisher checksum from the upstream source (well-known URL + JSON or HTML parse — pick one and document). With `--release <id>` and no catalog access, use the publisher SHA-256 committed under `[base.pinned]` in `qemu-image-builder.toml`, and fail if that release has none; never trust the mirrored `.sha256` sidecar on its own.
- [ ] 3.2 Implement `fetch_base_image(release_id, backend) -> Path` returning a verified `.img.xz`: check local cache (`.cache/qemu-image-builder/base/raspios-arm64-lite/<release_id>/...`); on miss, pull from the active backend; on backend miss, pull from upstream and mirror it (artifact + publisher `.sha256`) to the backend, unless `--no-upload`.
- [ ] 3.3 Verify the publisher checksum on **every** use — upstream download, backend pull, and local cache hit — before the image is decompressed or booted. On a local-cache mismatch, discard and re-fetch from the backend; on a backend mismatch, re-fetch from upstream and re-mirror; if no source matches, abort (image-builder-pipeline spec: "checksum mismatch aborts the build").
- [ ] 3.4 Implement `fetch_kernel(kver, backend) -> KernelArtifact`, where `KernelArtifact` is a frozen dataclass `(path: Path, version: str, sha256: str)`: cache at `.cache/qemu-image-builder/kernels/<kver>/Image`, pull from `base/kernels/<kver>/Image` on miss, verify against the pinned `sha256` from `qemu-image-builder.toml` on every use, abort on mismatch; the manifest reads `version` and `sha256` from the returned `KernelArtifact`.
- [ ] 3.5 Cover cache-hit, cache-miss, corrupted-cache-entry (re-fetch), corrupted-backend-object, and checksum-mismatch-everywhere (abort) for both base image and kernel in `tests/test_base_fetch.py` using `LocalBackend` as the active backend.

## 4. Working image preparation

- [ ] 4.1 Implement `decompress_and_grow(src_xz, dest, size_gb)`: stream-decompress the verified `.img.xz` with `lzma` into `<workdir>/work.img`, then grow it sparsely with `os.truncate(dest, size_gb * 1024**3)` (`size_gb` in GiB, default from config); refuse a size smaller than the decompressed image. All later steps operate on this raw image.
- [ ] 4.2 Implement `MacFat32Mount` context manager: `hdiutil attach -nomount`, parse the FAT32 partition device from output, `mount -t msdos <dev> <path>`, yield path; on exit `diskutil unmount` then `hdiutil detach` (spike confirmed plain `umount` fails on macOS due to Spotlight; design's macOS-version risk applies here).
- [ ] 4.3 Implement first-boot file writers for the boot partition only: `ssh` flag file and `userconf.txt` (bootstrap user `local_ssh_user` + password hash). No `wpa_supplicant.conf` (Wi-Fi is handled in task 6.7).
- [ ] 4.4 Generate a per-build random bootstrap password whose plaintext is held in memory only for this build and passed to child processes only via environment (`SSHPASS`, `QIB_BOOTSTRAP_PASSWORD`); never written to disk, argv, or logs. Only its hash goes into `userconf.txt`.
- [ ] 4.5 Integration test on a real image: mount the FAT32 partition of a checked-in tiny test fixture (or a small downloaded image in CI's hosted-runner cache), write files, unmount cleanly. Skip on non-macOS.

## 5. qemu boot + SSH readiness

- [ ] 5.1 Implement `QemuRunner` that builds the command line from config (`-machine virt` only; no raspi3b path, per design Decision 4) using the verified kernel from task 3.4 as `-kernel`, `-append "root=/dev/vda2 rootfstype=ext4 rw panic=0 console=ttyAMA0"` (direct kernel boot ignores the boot partition's `cmdline.txt`; same arguments as `build_image.sh`), the working image as `-drive format=raw,file=<workdir>/work.img,if=none,id=hd0,cache=writeback -device virtio-blk,drive=hd0`, `-device virtio-net-pci,netdev=net0`, and `-netdev user,id=net0,hostfwd=tcp:127.0.0.1:<port>-:22`, launches qemu in a subprocess, captures serial console to `<workdir>/serial.log`, and records the PID for cleanup.
- [ ] 5.2 Implement `wait_for_ssh_banner(port, timeout)` that polls `127.0.0.1:<port>` for an `SSH-` banner; on timeout, dump last 80 lines of serial log and raise a phase-bound exception.
- [ ] 5.3 Implement `wait_for_authenticated_login(port, user, timeout)` that polls `sshpass -e ssh -o BatchMode=no -o PubkeyAuthentication=no -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=<workdir>/known_hosts -o ConnectTimeout=5 -p <port> <user>@127.0.0.1 true`, with `SSHPASS` set only in the child environment, until login succeeds (spike showed this takes ~30s after banner because `userconfig.service` runs post-boot).
- [ ] 5.4 Implement clean shutdown (part of the `export` phase): prefer `ssh sudo shutdown -h now`, fall back to qemu-monitor `system_powerdown`, fall back to SIGTERM with a grace period, last resort SIGKILL. Wait for image-file fsync.
- [ ] 5.5 Integration test that boots a fixture kernel served from a `LocalBackend` fixture at `base/kernels/<kver>/Image` (through `fetch_kernel`, not the local `kernels/Image` path) plus a small fixture image, asserts the SSH-ready event fires within the configured timeout, and asserts nothing listens on a non-loopback interface for the forwarded port.

## 6. Ansible apply with connection-address override

- [ ] 6.1 Implement `build_ansible_invocation(host, port, workdir)` that runs `ansible-playbook -i hosts -e hostlist=<host> playbooks/image-build.yml` with connection-only extra-vars `ansible_ssh_host=127.0.0.1`, `ansible_port=<port>`, `ansible_user=<local_ssh_user>`, `target_host_ip=<production address from inventory>`, and, for the stage-1 invocation only, `ansible_password` as the env-lookup template from design Decision 8. SSH args point at `<workdir>/known_hosts` with `StrictHostKeyChecking=accept-new`. Never set `ansible_host`; write no credential to any file. Test that the generated argv and any files contain no password.
- [ ] 6.2 Add a pre-flight grep over `roles/` and the imported playbooks for hard-coded production IPs, `ansible_default_ipv4` used to persist the host's own address (e.g. `roles/tvTunerSetup/templates/epgstation.config.yml`), and `delegate_to` (design risk mitigation); surface a warning listing matches; fail loudly only if `--strict` is set.
- [ ] 6.3 Implement the `apt-refresh` phase as two separate become-enabled ansible `command` tasks, run unconditionally before stage-1 with the same password-based connection as the stage-1 invocation (`ansible_password` and `ansible_become_password` from the `QIB_BOOTSTRAP_PASSWORD` env lookup): `apt-get clean`, then `apt-get update -o Acquire::AllowReleaseInfoChange=true`.
- [ ] 6.4 Create `playbooks/image-build.yml` importing `initial-playbook-stage-2.yml` … `initial-playbook-stage-5.yml` in that order (design Review decision R6). Implement `apply_ansible()` that runs `initial-playbook-stage-1.yml` with the bootstrap password, clears the per-build `known_hosts` if stage-1 rotated host keys, re-probes as `local_ssh_user` with `PasswordAuthentication=no` (fail the phase if it fails), then runs `playbooks/image-build.yml` without `ansible_password`; each invocation streams output to `<workdir>/ansible.log`, captures the exit code, and fails the phase on any non-zero exit (no `|| true`). Bootstrap user in `userconf.txt` is `local_ssh_user` (task 4.3).
- [ ] 6.5 Audit existing roles for under-virt behavior; add `when:` guards or fact-based skips for hardware-touching tasks (hciuart, GPIO, raspi-config hardware probes); switch self-address consumers found in 6.2 to `target_host_ip`; mark credential-bearing tasks `no_log: true`; check cloud-init on Trixie images did not write a conflicting network config; track each adjustment as its own commit.
- [ ] 6.6 Integration smoke: run the full `fetch` → `prep` → `boot` → `apt-refresh` → ansible-ping → ansible-setup → ansible-command flow end-to-end against a fixture host config and assert no errors.
- [ ] 6.7 Persist Wi-Fi as a NetworkManager keyfile: add a task (new, or a Bookworm+ variant of `roles/wifiClientSetup`) that writes the fixed path `/etc/NetworkManager/system-connections/qib-wifi.nmconnection` (the SSID appears only inside the file as `ssid=`, never in a path) (`root:root`, `0600`, `no_log: true`) and sets the Wi-Fi regulatory country from host/group vars; include it from `playbooks/image-build.yml` when Wi-Fi vars are defined.
- [ ] 6.8 Final step of `ansible-apply`: collect `dpkg-query -W` output for the manifest, then lock the bootstrap user's password (`usermod -L`) so the image accepts only key-based login (design Review decision R5).

## 7. Image export, compression, upload

- [ ] 7.1 Implement `export_image(work_img, dest_path)` that, after clean shutdown (task 5.4), produces the final raw `.img` in `build_images/` (no transformation needed since the working copy is the artifact; just rename/move, mode `0600`).
- [ ] 7.2 Implement `compress_image(src, dest)` using `zstandard` at the configured level (default per design: benchmark `-9` vs `-19` and commit the choice).
- [ ] 7.3 Implement SHA-256 sidecar generation and the build manifest (fields per design Decision 6) alongside the compressed artifact, in the `compress` phase.
- [ ] 7.4 Implement `upload_built(image_path, host, release_id, build_ts, backend)` that uploads `built/<host>/<release_id>/<build_ts>.img.zst`, `.img.zst.sha256`, and `.manifest.json` via the staging/promote protocol (task 2.6), then writes `built/<host>/latest.json` (schema per Decision 6) only after all three are promoted, and only if the current pointer's `build_ts` is not newer than this build's. Under `--no-upload`, skip the phase entirely.
- [ ] 7.5 Test the full upload flow against `LocalBackend`: success path, failure on each of the three uploads and promotes (no `latest.json` change, staging cleaned up), `latest.json` written last and referencing the artifact checksum, `--no-upload` makes zero backend writes.

## 8. Metrics emission

- [ ] 8.1 Wire the `Phase` context manager around every canonical pipeline phase: `fetch`, `prep`, `boot`, `apt-refresh`, `ansible-apply`, `export`, `compress`, `upload`.
- [ ] 8.2 Implement two emitters: aligned human-readable table to stderr, and the JSON Lines contract from the build-metrics spec, always written to `--timing-output` (default `build_images/<host>-<build_ts>.timings.jsonl`): one `phase` record per canonical phase in order, then one `summary` record.
- [ ] 8.3 Ensure timings emit on both success and failure paths: failed phase `status: "failed"` with `error`, downstream phases `status: "not_run"` with `null` `started_at`/`duration_s`, `upload` `status: "skipped"` under `--no-upload`.
- [ ] 8.4 Test: simulate a failure in the `ansible-apply` phase and assert all eight phases are accounted for in the JSON Lines output, with the correct statuses, field types, and summary record.

## 9. CLI surface

- [ ] 9.1 Implement `qemu-image-builder build --host <name>` as the primary entrypoint. Required arg: `--host`. Optional: `--release latest|<id>`, `--backend {r2,local}`, `--ssh-port <port>`, `--no-upload` (debug: no backend writes, `upload` reported `skipped`, `latest.json` untouched), `--keep-vm` (for debugging), `--timing-output <path>`.
- [ ] 9.2 Implement `qemu-image-builder fetch --release latest|<id>` for warming the base and kernel cache without doing a full build; after verifying against upstream it prints the `[base.pinned]` line to commit for offline builds of that release.
- [ ] 9.3 Implement `qemu-image-builder prune --keep-base N --keep-built M --keep-failed K` for cache hygiene (design risk: cache directory grows unboundedly), including retained failed workdirs. Targets local cache only by default; `--remote` extends to the active backend and also deletes `built/` objects (staging or final key) older than 24h that no `latest.json` references. Never deletes the artifact referenced by a host's `latest.json`.
- [ ] 9.4 Implement `qemu-image-builder latest --host <name>` that prints the current `built/<host>/latest.json` from the active backend.
- [ ] 9.5 Implement per-host build lock via `fcntl.flock` on `.cache/qemu-image-builder/locks/<host>.lock`; second invocation fails fast with a clear message.

## 10. Documentation

- [ ] 10.1 Write `scripts/qemu_image_builder/README.md` covering: prereqs (qemu, ansible, sshpass), config file layout, R2 credential sources, the apt-refresh step, the canonical phase list, and that built images and retained workdirs contain secrets (owner-only, private bucket).
- [ ] 10.2 Document the operator workflow for building and uploading a virt kernel to `base/kernels/<kver>/Image` (+ `.sha256`) and committing its version and digest to `qemu-image-builder.toml`, including the one-time seed from the local `kernels/Image` (out of scope to automate per design Decision 4, but the recipe is needed).
- [ ] 10.3 Add a troubleshooting section: qemu-died-on-boot (check `serial.log`), SSH timeout (extend `BOOT_TIMEOUT`), host-key mismatch in the per-build `known_hosts`, apt 404s after a Debian point-release move, stale FAT32 mount (`diskutil unmount` then `hdiutil detach`), checksum mismatches.

## 11. End-to-end validation

- [ ] 11.1 Run the full pipeline against one real host config (a low-stakes Pi in the fleet). Capture timings.
- [ ] 11.2 Flash the resulting `.img` to an SD card with `dd`, swap into the target Pi, power on, verify it boots with the bootstrap configuration (stages 1–5) applied and no further manual steps for that portion (the proposal's success criterion), including joining Wi-Fi via the NetworkManager keyfile.
- [ ] 11.3 Pi5 validation: same pipeline, real Pi5 hardware. The image is universal raspios-arm64-lite; this confirms our virt-built image actually boots Pi5 hardware (per design Open Question 2).
- [ ] 11.4 No-storage-access validation: with a pre-warmed cache, unset R2 credentials and block access to R2 and the upstream image source while keeping VM package egress; run `--backend local --release <id>` and confirm the build completes and writes to the local backend. Fully air-gapped builds are out of scope (design Review decision R7).
- [ ] 11.5 Concurrent-build validation: run two builds for the same host in parallel; second must fail fast with the lock message (per task 9.5).

## 12. Retire old paths (deferred to follow-up change)

- [ ] 12.1 *(Out of scope for this change per design Migration Plan.)* Follow-up change will remove `build_image.sh`, `post_install.sh`, the per-region `*-wifi.sh` scripts, `userconf.txt`, and the local `kernels/Image` (superseded by `base/kernels/<kver>/Image`) once the new engine has been validated on at least one real Pi in production.
