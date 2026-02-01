# wifiClientSetup wpa_cli reload robustness

## Goal
Make the `wifiClientSetup` role resilient when reloading the wifi configuration with `wpa_cli -i wlan0 reconfigure` so that a missing control socket (or similar transient issues) do not cause the playbook to fail on hosts like terraTau.

## Proposed Changes
- Update `roles/wifiClientSetup/tasks/install.yml` `reload the config` task to:
  - Continue to run only when `wpa_supplicant_updated` is defined.
  - Register the result of `wpa_cli -i wlan0 reconfigure`.
  - Treat non-zero return codes as non-fatal to the play (i.e., do not fail the play when `wpa_cli` cannot connect to the control socket).

Concretely, change the task to:

```yaml
- name: reload the config
  shell: wpa_cli -i wlan0 reconfigure
  when: wpa_supplicant_updated is defined
  register: wpa_cli_reconfigure
  failed_when: false
```

## Verification
- Run the same targeted wifiClientSetup test playbook against terraTau used previously.
  - Confirm that the play completes successfully even if `wpa_cli` reports it cannot connect to the control socket.
  - Verify that the new bluetooth rfkill task still runs and that wifi/bluetooth are unblocked as expected.
