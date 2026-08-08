# Implementation Plan: Stabilize Android BLE Connection

## Overview

Android could report GATT connected before the notification channel was ready, then send a single `HELLO`. Losing that first response caused an intermittent timeout, left a partial link alive, and made retry awkward. Pairing also had no timeout and accepted unrelated bond-state broadcasts.

## Architecture Decisions

- Complete Android MTU negotiation and notification subscription before exposing the BLE link to the protocol controller.
- Retry the idempotent `HELLO` negotiation once when its first response is lost.
- Close every partial link on failure and return the UI to a clean scan screen.
- Bound pairing, filter native bond events by the selected device, and preserve payload-free diagnostics.

## Task List

### Phase 1: Reproduce and guard

- [x] Reproduce a lost first `HELLO` response with a fake BLE transport.
- [x] Reproduce partial-link leakage after failed negotiation.
- [x] Reproduce the non-retryable connection screen and unbounded pairing.

### Phase 2: Harden connection setup

- [x] Request Android MTU 247 and reject values below the 229-byte protocol requirement.
- [x] Subscribe to TX notifications before reporting the link connected.
- [x] Retry `HELLO` once, then cleanly disconnect if negotiation still fails.
- [x] Return failed attempts to the scan screen with an actionable error.
- [x] Add a 30-second pairing timeout, cancellation, and selected-device filtering.

### Phase 3: Verify and deliver

- [x] Pass Flutter unit/widget tests and static analysis.
- [x] Compile the Android native bridge and debug APK.
- [ ] Run firmware host tests and validate the existing 0.1.1 FAP against API 87.1.
- [ ] Publish APK 0.1.2 test build with the compatible FAP and checksums.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Android vendor BLE timing differs | High | Delay protocol negotiation until setup completes and retry the idempotent handshake. |
| Small negotiated MTU truncates text frames | High | Fail early below MTU 229 with an actionable error. |
| Pairing prompt is ignored or another device bonds | Medium | Timeout, cancel, and filter broadcasts by device address. |
| Failed attempt poisons retry | High | Close the GATT link and restore the scan screen on every failure path. |

## Open Questions

- Physical phone-to-Flipper acceptance still requires an Android device to be attached or tested by the user; no Android device was visible to ADB during this repair.
