# Implementation Plan: Stabilize Flipper Application Startup

## Overview

BridgePad currently treats a temporary USB or Bluetooth startup failure as fatal, waits 1.5 seconds, and returns to the USB application folder. This is especially easy to trigger while qFlipper or an RPC session still owns the USB configuration. The fix will keep the application alive, display the blocked subsystem, and retry missing hardware safely when OK is pressed.

## Architecture Decisions

- Separate startup retry policy into a small pure-C coordinator so failure and recovery can be host-tested without Flipper hardware.
- Keep allocation failures fatal, but make USB/Bluetooth availability failures recoverable.
- Start Bluetooth before taking over USB, preserving the diagnostic serial connection for as long as possible.
- Never arm during a retry press; the user must see both connections ready and press OK again to arm.
- Preserve release-all and original USB/Bluetooth restoration behavior on every exit path.

## Task List

### Phase 1: Reproduce and guard

- [ ] Add a failing host test proving a failed USB start does not terminate the runtime and can succeed on retry.
- [ ] Add a failing host test proving successful subsystems are not restarted during retry.

### Checkpoint: Policy

- [ ] Focused startup tests fail before implementation and pass afterward.

### Phase 2: Firmware integration

- [ ] Integrate the startup coordinator into `bridgepad_app.c`.
- [ ] Keep the UI active with actionable USB/Bluetooth errors.
- [ ] Make OK retry unavailable subsystems before normal arming behavior.
- [ ] Harden partial Bluetooth-start cleanup.

### Checkpoint: Firmware

- [ ] All host tests pass.
- [ ] FAP builds and passes API compatibility checks.

### Phase 3: Hardware and release

- [ ] Install and launch the fixed FAP on Momentum mntm-012.
- [ ] Confirm it remains active and enumerates as `BridgePad HID`.
- [ ] Update troubleshooting and changelog.
- [ ] Commit, push, and publish refreshed test artifacts.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| USB takeover removes serial diagnostics | Medium | Verify liveness from macOS USB enumeration and keep failures visible on the Flipper screen. |
| Partial BLE startup leaves callbacks/profile active | High | Explicitly unwind every partially acquired Bluetooth resource before allowing retry. |
| Retry accidentally arms input | High | Retry and arming are separate user actions. |
| Firmware-specific behavior | Medium | Build against API 87.1 and test on the attached Momentum mntm-012 device. |

## Open Questions

- None. The user authorized planning and execution; firmware replacement is out of scope because mntm-012 is already installed.
