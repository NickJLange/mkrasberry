# Podman OverlayFS Configuration

## Goal
Configure Podman to use `overlay` as the default storage driver across the fleet. This ensures consistent performance and behavior for container storage.

## Proposed Changes
- Ensure `fuse-overlayfs` package is installed (via `roles/podmanSetupRaspberryPi/tasks/install.yml` and `playbooks/initial-playbook-stage-5.yml`).
- Modify `roles/podmanSetupRaspberryPi/tasks/configure.yml` and `playbooks/initial-playbook-stage-5.yml` to:
    - Ensure `/etc/containers/storage.conf` exists.
    - Explicitly set `driver = "overlay"` in the `[storage]` section of `/etc/containers/storage.conf` using `ini_file` module.
    - Ensure `graphroot` is set to `/var/lib/containers/storage`.

## Verification
- Run the role on a host.
- Check `/etc/containers/storage.conf`:
    - `[storage]` section should have `driver = "overlay"`.
- Run `podman info` to verify the storage driver is active.
