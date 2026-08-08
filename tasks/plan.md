# Implementation Plan: BLE Discovery and BadUSB Feasibility Experiment

## Overview

This experiment will live on `experiment/badusb-bridge` and will not alter the working `main` branch. The source review found that the current Android discovery filter is mismatched with the Flipper advertisement: BridgePad scans for the 128-bit serial GATT service, while both official and Momentum firmware advertise a color-dependent 16-bit service ID (`0x3080` through `0x3083`). The first implementation slice should correct discovery without changing the proven BLE-serial-to-USB-HID architecture.

BadUSB is not a replacement phone-input protocol. Its USB implementation is a host-facing HID backend built on the same `furi_hal_hid_*` calls BridgePad already uses, and its Bluetooth implementation makes the Flipper a BLE keyboard/mouse for a host. It does not accept live commands from a phone. A BadUSB-style USB backend comparison remains an optional, gated experiment after discovery is working.

## Evidence and Validity

- The pinned Flutter BLE library states that `withServices` matches advertised service IDs; an empty list reports all advertisers: <https://github.com/PhilipsHue/flutter_reactive_ble#device-discovery>
- Official Flipper serial-profile advertising uses a 16-bit `0x3080` service ID ORed with hardware color, while the connected GATT service remains the 128-bit serial UUID: <https://github.com/flipperdevices/flipperzero-firmware/blob/dev/targets/f7/ble_glue/profiles/serial_profile.c>
- Momentum retains the same `0x3080` serial-profile advertisement: <https://github.com/Next-Flip/Momentum-Firmware/blob/dev/targets/f7/ble_glue/profiles/serial_profile.c>
- Official hardware colors are `0x00` through `0x03`, producing advertised IDs `0x3080` through `0x3083`: <https://github.com/flipperdevices/flipperzero-firmware/blob/dev/targets/furi_hal_include/furi_hal_version.h>
- BadUSB exposes either a USB HID output or a BLE HID output. Its interface contains no phone-to-Flipper transport: <https://github.com/flipperdevices/flipperzero-firmware/blob/dev/applications/main/bad_usb/helpers/bad_usb_hid.h>
- BadUSB's USB backend calls the same Flipper HID HAL already used by BridgePad, and the BadUSB helpers are not exported FAP SDK symbols: <https://github.com/flipperdevices/flipperzero-firmware/blob/dev/applications/main/bad_usb/helpers/bad_usb_hid.c>

## Architecture Decision

```text
Android scan for advertised 0x3080–0x3083
                    ↓
        Explicit user selection and bond
                    ↓
      Discover 128-bit serial GATT service
                    ↓
        BridgePad authenticated protocol
                    ↓
          Flipper USB keyboard/mouse HID
```

- Keep BLE serial as the inbound phone channel.
- Keep USB HID as the outbound computer channel.
- Use the four advertised 16-bit UUIDs only during discovery.
- Continue using the existing 128-bit service and characteristic UUIDs after connection.
- Do not use BadUSB BLE mode; it points HID reports toward the Bluetooth host and therefore competes with the phone transport instead of carrying it.
- Do not write clipboard values or generated DuckyScript to the SD card.

## Dependency Order

Discovery contract tests → Android scan correction → physical scan/pair acceptance → full bridge acceptance → optional BadUSB USB-backend comparison → merge/no-merge decision.

## Task 1: Lock the Advertisement Contract in Tests

**Description:** Add fake-BLE tests that prove discovery requests the Flipper serial advertisement IDs rather than the connected 128-bit GATT service.

**Acceptance criteria:**

- The scan filter contains standard Bluetooth UUID expansions of `0x3080`, `0x3081`, `0x3082`, and `0x3083`.
- The 128-bit serial GATT service is absent from the advertisement filter but remains in service discovery after connection.
- A regression test fails against the current APK behavior and passes only after Task 2.

**Verification:**

- Focused test: `flutter test test/ble_transport_test.dart`
- Static analysis: `flutter analyze`

**Dependencies:** None

**Files likely touched:**

- `mobile/test/ble_transport_test.dart`
- `mobile/lib/src/ble_transport.dart`

**Estimated scope:** Small, 2 files

## Task 2: Correct Android Discovery and No-Result Guidance

**Description:** Replace the incorrect 128-bit advertisement filter with the four official/Momentum 16-bit advertisement IDs. Keep the scan bounded and explain the older-Android location prompt without collecting location data.

**Acceptance criteria:**

- A running BridgePad FAP is listed when its advertisement contains any `0x3080`–`0x3083` service.
- Scan still stops after ten seconds and does not persist device observations.
- A zero-result scan tells the tester to keep BridgePad open on the Flipper and explains that Android 11 or lower requires location permission for BLE scanning.

**Verification:**

- Focused tests: `flutter test test/ble_transport_test.dart test/app_test.dart`
- Full gate: `flutter test && flutter analyze && flutter build apk --debug`

**Dependencies:** Task 1

**Files likely touched:**

- `mobile/lib/src/ble_transport.dart`
- `mobile/lib/src/bridgepad_home.dart`
- `mobile/test/ble_transport_test.dart`
- `mobile/test/app_test.dart`

**Estimated scope:** Medium, 4 files

## Checkpoint A: Discovery Proof

- The APK shows the Flipper while BridgePad is open.
- The Flipper is not required to advertise the 128-bit GATT UUID.
- No BadUSB firmware changes are permitted before this checkpoint passes or produces captured evidence of a different failure.

## Task 3: Physical Pairing and Full-Bridge Acceptance

**Description:** Test the corrected APK with Momentum, record the exact transition from scan through pairing and protocol readiness, then exercise USB HID output.

**Acceptance criteria:**

- Android discovers and bonds with the selected Flipper.
- The app reaches protocol Ready and reflects USB/armed status.
- Text, Enter, pointer movement, click, and release-all reach the USB host.

**Verification:**

- Capture Android state-only logs without keyboard or clipboard payloads.
- Confirm the host enumerates `BridgePad HID` and receives the acceptance inputs.
- Confirm Back, BLE loss, and heartbeat timeout release all input.

**Dependencies:** Task 2 and physical Android/Flipper access

**Files likely touched:** None unless evidence reveals another defect

**Estimated scope:** Small diagnostic session

## Task 4: Optional BadUSB USB-Backend Comparison

**Description:** Only if explicitly approved after Checkpoint A, place a minimal BadUSB-style USB HID adapter behind BridgePad's existing HID boundary. Keep BLE serial as input. Do not copy the DuckyScript engine or BadUSB BLE mode.

**Acceptance criteria:**

- The alternative backend is isolated to the experiment branch and compile-time selectable.
- It passes the same arming, keyboard, mouse, release-all, and teardown tests as the current backend.
- The comparison records artifact size, startup stability, host enumeration, and any measurable behavioral advantage.

**Verification:**

- Firmware tests: `make test`
- FAP build and compatibility check: `cd firmware && ufbt`
- Hardware A/B test using identical phone commands and USB host

**Dependencies:** Checkpoint A and explicit approval

**Files likely touched:**

- `firmware/bridgepad_app.c`
- `firmware/bridgepad_hid_backend.h`
- `firmware/bridgepad_hid_backend.c`
- `firmware/tests/test_hid_backend.c`
- `Makefile`

**Estimated scope:** Medium, 5 files

## Task 5: Decide What Returns to Main

**Description:** Merge only evidence-backed improvements. The discovery correction can return to `main` after physical acceptance. The BadUSB adapter returns only if it demonstrates a concrete benefit over direct HAL calls.

**Acceptance criteria:**

- A short decision record states what was tested and why the selected backend won.
- No experimental BadUSB code is merged merely because it functions equivalently.
- Updated APK/FAP artifacts remain private and are published as a prerelease only after full verification.

**Verification:**

- Code-quality review, full mobile and firmware gates, clean Git status
- Private GitHub branch and prerelease assets verified before handoff

**Dependencies:** Tasks 3–4 as applicable

**Files likely touched:**

- `tasks/plan.md`
- `tasks/todo.md`
- `CHANGELOG.md`
- `README.md`

**Estimated scope:** Small, documentation and release metadata

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Android 11 or lower asks for location permission | Medium | Explain the OS requirement; retain `maxSdkVersion=30` and never collect/store location. |
| Advertisement differs on a firmware fork | Medium | Official and Momentum sources currently match; capture actual scan records if the four-ID filter still fails. |
| Stale BLE bond blocks the first corrected connection | Medium | Separate discovery acceptance from bonding; clear only the selected BridgePad bond when evidence requires it. |
| BadUSB internals are app-private and unexported | High | Treat them as reference design only; vendor a minimal GPL-compatible adapter on the experimental branch if approved. |
| DuckyScript would persist sensitive text | High | Do not use scripts or temporary SD files for clipboard/password transfer. |
| BadUSB BLE mode consumes the Bluetooth role needed by the phone | High | Do not use it; retain serial BLE for inbound commands. |

## Go/No-Go Recommendation

- **GO:** Correct the advertisement filter and run physical discovery/pairing acceptance.
- **CONDITIONAL:** Compare a BadUSB-style USB backend only after discovery works and only with explicit approval.
- **NO-GO:** Replacing the phone BLE serial channel with BadUSB BLE or routing live clipboard/password text through stored DuckyScript files.

## Approval Gate

No application or firmware implementation begins until this plan is reviewed and approved.
