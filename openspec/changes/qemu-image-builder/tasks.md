## 1. Project scaffolding

- [ ] 1.1 Create `scripts/qemu_image_builder/` Python package (`__init__.py`, `__main__.py`) and wire a `qemu-image-builder` console-script entrypoint in `pyproject.toml`
- [ ] 1.2 Add runtime dependencies: `boto3`, `botocore`, `zstandard`, `tomli`/`tomllib`, `pyyaml`; add dev deps for testing (`pytest`, `pytest-mock`)
- [ ] 1.3 Add `.gitignore` entries for `.cache/qemu-image-builder/`, `tmp/`, and any non-committed kernel/image artifacts
- [ ] 1.4 Create the canonical config schema (file at `~/.config/qemu-image-builder/config.toml` plus repo-local `qemu-image-builder.toml` for overrides); document precedence (CLI flag > env > local toml > user toml > defaults)
- [ ] 1.5 Stand up a `Phase` context manager (timing capture per the metrics spec) with `record(name)` / `mark_not_run(name)` / `dump()` methods and unit tests covering success, exception, and "phase did not run" cases

## 2. Storage backend abstraction

- [ ] 2.1 Define `StorageBackend` ABC: `fetch(key, dest_path)`, `put(src_path, key)`, `exists(key) -> bool`, `list(prefix) -> Iterator[str]`, `delete(key)`. Document idempotence and error contract (`StorageNotFound`, `StorageAuthError`, `StorageTransientError`).
- [ ] 2.2 Implement `LocalBackend` rooted at a configurable directory, mirroring the R2 key layout from design.md (Decision 6) so it doubles as a debug mirror.
- [ ] 2.3 Implement `R2Backend` via `boto3` with explicit endpoint URL. Resolve credentials in order: explicit kwargs → env (`R2_ACCESS_KEY_ID`/`R2_SECRET_ACCESS_KEY`/`R2_ENDPOINT_URL`/`R2_BUCKET`) → `~/.config/rclone/rclone.conf` parse → fail with a structured `StorageAuthError`.
- [ ] 2.4 Write `tests/storage/test_local_backend.py` covering: round-trip put/fetch, `exists`/`list`/`delete`, missing-key error, prefix listing.
- [ ] 2.5 Write `tests/storage/test_r2_backend_credentials.py` covering the credential-resolution chain (env, rclone.conf parse, both absent → `StorageAuthError`) without making real R2 calls.
- [ ] 2.6 Implement the `*.partial` → rename → write-`latest.json` upload protocol from design risks; cover the crash-mid-upload case with a test that asserts no `latest.json` is written when the final rename fails.

## 3. Base image fetch + cache

- [ ] 3.1 Implement `RaspiosCatalog` that discovers the latest `raspios-arm64-lite` release identifier and checksum from the upstream source (well-known URL + JSON or HTML parse — pick one and document).
- [ ] 3.2 Implement `fetch_base_image(release_id, backend) -> Path`: check local working copy (`.cache/qemu-image-builder/base/<release_id>/...`); on miss, pull from the active backend; on backend miss, pull from upstream and re-upload to the backend (so the backend mirror grows as releases come in).
- [ ] 3.3 Verify upstream checksum on every fresh download; abort build on mismatch (image-builder-pipeline spec: "checksum mismatch aborts the build").
- [ ] 3.4 Cover cache-hit + cache-miss + checksum-mismatch in `tests/test_base_fetch.py` using `LocalBackend` as the active backend.

## 4. Working image preparation

- [ ] 4.1 Implement `clone_and_grow(src, dest, size_gb)` using `cp -c` (APFS clonefile) + `dd if=/dev/zero seek=N obs=1G count=0` to grow sparsely; default size from config.
- [ ] 4.2 Implement `MacFat32Mount` context manager: `hdiutil attach -nomount`, parse the FAT32 partition device from output, `mount -t msdos <dev> <path>`, yield path; on exit `diskutil unmount` then `hdiutil detach` (spike confirmed plain `umount` fails on macOS due to Spotlight; design's macOS-version risk applies here).
- [ ] 4.3 Implement first-boot file writers: `ssh` flag file, `userconf.txt` from configured user + password hash, optional `wpa_supplicant.conf` from config (per-host overrides via `host_vars/<host>.yml`).
- [ ] 4.4 Generate a per-build `userconf.txt` with a randomly-generated password whose plaintext is held in memory only for this build (used to authenticate ansible's first connection; never written to disk or to the final image's persistent config).
- [ ] 4.5 Integration test on a real image: mount the FAT32 partition of a checked-in tiny test fixture (or a small downloaded image in CI's hosted-runner cache), write files, unmount cleanly. Skip on non-macOS.

## 5. qemu boot + SSH readiness

- [ ] 5.1 Implement `QemuRunner` that builds the command line from config (machine=virt by default; raspi3b fallback per design Decision 4), launches qemu in a subprocess, captures serial console to `<workdir>/serial.log`, and records the PID for cleanup.
- [ ] 5.2 Implement `wait_for_ssh_banner(port, timeout)` that polls `nc`-style for an `SSH-` banner; on timeout, dump last 80 lines of serial log and raise a phase-bound exception.
- [ ] 5.3 Implement `wait_for_authenticated_login(host, port, user, password, timeout)` that polls `ssh -o BatchMode=no` until login succeeds (spike showed this takes ~30s after banner because `userconfig.service` runs post-boot).
- [ ] 5.4 Implement clean shutdown: prefer `ssh sudo shutdown -h now`, fall back to qemu-monitor `system_powerdown`, fall back to SIGTERM with a grace period, last resort SIGKILL. Wait for image-file fsync.
- [ ] 5.5 Integration test that boots the existing `kernels/Image` + a small fixture image and asserts the SSH-ready event fires within the configured timeout.

## 6. Ansible apply with IP override

- [ ] 6.1 Implement `generate_inventory(host, vm_address)` that writes a per-build inventory pointing the target host group at `ansible_host=<vm_ip> ansible_port=<port> ansible_user=<vm_user> ansible_ssh_pass=<one-shot-password>`, plus `target_host_ip` (the production IP) as a host var for roles that persist network config.
- [ ] 6.2 Add a pre-flight grep over `roles/` for hard-coded production IPs (design risk mitigation) and surface a warning listing matches; fail loudly only if `--strict` is set.
- [ ] 6.3 Implement the apt-drift mitigation step: `apt clean && apt-get update -o Acquire::AllowReleaseInfoChange=true` via ansible's `command` module, run unconditionally before the first role.
- [ ] 6.4 Implement `apply_ansible(host, inventory_path, extra_vars)` that invokes `ansible-playbook` against the project's existing playbook tree (the entrypoint playbook for a single-host run — pick one or scaffold one if none fits), streams output, captures exit code, returns timing-friendly outcome.
- [ ] 6.5 Audit existing roles for under-virt behavior; add `when:` guards or fact-based skips for hardware-touching tasks (hciuart, GPIO, raspi-config hardware probes); track each adjustment as its own commit.
- [ ] 6.6 Integration smoke: run the full prep → boot → apt-drift → ansible-ping → ansible-setup → ansible-command flow end-to-end against a fixture host config and assert no errors.

## 7. Image export, compression, upload

- [ ] 7.1 Implement `export_image(work_img, dest_path)` that produces the final raw `.img` (no transformation needed since the working copy is the artifact; just rename/copy to the build output dir).
- [ ] 7.2 Implement `compress_image(src, dest)` using `zstandard` at the configured level (default per design: benchmark `-9` vs `-19` and commit the choice).
- [ ] 7.3 Implement `upload_built(image_path, host, release_id, build_ts, backend)` that uploads to `built/<host>/<release_id>/<build_ts>.img.zst` and `*.img.zst.sha256` via the partial-then-rename protocol; only writes `built/<host>/latest.json` after both succeed.
- [ ] 7.4 Implement SHA256 sidecar generation alongside the compressed artifact.
- [ ] 7.5 Test the full upload flow against `LocalBackend`: success path, partial-on-failure (no `latest.json` written), latest.json is written last.

## 8. Metrics emission

- [ ] 8.1 Wire the `Phase` context manager around every top-level pipeline phase (fetch, prep, boot, apt-refresh, ansible-apply, export, compress, upload).
- [ ] 8.2 Implement two emitters: aligned human-readable table to stderr, JSON-Lines to `build_images/<host>-<build_ts>.timings.jsonl` (one record per phase + a summary record).
- [ ] 8.3 Ensure timings emit on both success and failure paths (failed phases marked `status: failed`, downstream phases marked `not_run: true`).
- [ ] 8.4 Test: simulate a failure in the ansible phase and assert all phases are accounted for in the JSON-Lines output, with the correct status flags.

## 9. CLI surface

- [ ] 9.1 Implement `qemu-image-builder build --host <name>` as the primary entrypoint. Required arg: `--host`. Optional: `--backend {r2,local}`, `--machine {virt,raspi3b}`, `--no-upload`, `--keep-vm` (for debugging), `--timing-output <path>`.
- [ ] 9.2 Implement `qemu-image-builder fetch --release latest|<id>` for warming the base cache without doing a full build.
- [ ] 9.3 Implement `qemu-image-builder prune --keep-base N --keep-built M` for cache hygiene (design risk: cache directory grows unboundedly). Targets local cache only by default; `--remote` extends to the active backend.
- [ ] 9.4 Implement `qemu-image-builder latest --host <name>` that prints the current `built/<host>/latest.json` from the active backend.
- [ ] 9.5 Implement per-host build lock via `fcntl.flock` on `.cache/qemu-image-builder/locks/<host>.lock`; second invocation fails fast with a clear message.

## 10. Documentation

- [ ] 10.1 Write `scripts/qemu_image_builder/README.md` covering: prereqs (qemu, ansible, sshpass), config file layout, R2 credential sources, the `--machine raspi3b` fallback, and the apt-drift step.
- [ ] 10.2 Document the operator workflow for building/uploading a fresh `kernels/Image` (out of scope to automate per design Decision 4, but the recipe is needed).
- [ ] 10.3 Add a troubleshooting section: qemu-died-on-boot (check `serial.log`), SSH timeout (extend `BOOT_TIMEOUT`), apt 404s after a Debian point-release move, stale FAT32 mount (`diskutil unmount` then `hdiutil detach`).

## 11. End-to-end validation

- [ ] 11.1 Run the full pipeline against one real host config (a low-stakes Pi in the fleet). Capture timings.
- [ ] 11.2 Flash the resulting `.img` to an SD card with `dd`, swap into the target Pi, power on, verify it boots into configured state with no further manual steps (the proposal's success criterion).
- [ ] 11.3 Pi5 validation: same pipeline, real Pi5 hardware. The image is universal raspios-arm64-lite; this confirms our virt-built image actually boots Pi5 hardware (per design Open Question 2).
- [ ] 11.4 Offline-mode validation: disconnect from network, run with `--backend local` against pre-warmed cache, confirm build completes.
- [ ] 11.5 Concurrent-build validation: run two builds for the same host in parallel; second must fail fast with the lock message (per task 9.5).

## 12. Retire old paths (deferred to follow-up change)

- [ ] 12.1 *(Out of scope for this change per design Migration Plan.)* Follow-up change will remove `build_image.sh`, `post_install.sh`, the per-region `*-wifi.sh` scripts, `userconf.txt`, and the checked-in `kernels/Image` once the new engine has been validated on at least one real Pi in production.
