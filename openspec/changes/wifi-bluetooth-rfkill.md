# Wifi and Bluetooth rfkill Unblocking for wifiClientSetup

## Goal
Ensure that when the wifiClientSetup role configures wifi on a Raspberry Pi, it also guarantees that both wifi and bluetooth are unblocked via rfkill, and that the role documentation clearly advertises this behavior.

## Proposed Changes
- Update `roles/wifiClientSetup/tasks/install.yml` to add an idempotent task that runs `rfkill unblock bluetooth` alongside the existing `rfkill unblock wifi` behavior.
- Keep the new bluetooth task conditioned on `wpa_supplicant_updated` (matching the existing rfkill unblock wifi task) to avoid unnecessary executions when wifi is not being (re)configured.
- Update `roles/wifiClientSetup/meta/main.yml` role description to indicate that it configures wifi and ensures radio state (wifi + bluetooth) is enabled via rfkill.

## Verification
- Run the `wifiClientSetup` role against a Raspberry Pi host where bluetooth is currently soft-blocked by rfkill.
  - Before run: `rfkill list` should show bluetooth as `Soft blocked: yes`.
  - After run: `rfkill list` should show both wifi and bluetooth as `Soft blocked: no`.
- Confirm that the role metadata now describes both wifi configuration and enabling wifi/bluetooth via rfkill.
