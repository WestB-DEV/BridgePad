# BLE Discovery and BadUSB Feasibility Experiment

## Phase 0: Source Validation

- [x] Verify official Flipper serial advertisement UUID behavior.
- [x] Verify Momentum uses the same advertisement UUID.
- [x] Verify Flutter BLE scan-filter semantics.
- [x] Verify BadUSB USB/BLE boundaries and SDK export status.
- [x] Create isolated `experiment/badusb-bridge` branch.

## Phase 1: Discovery Correction

- [x] Add failing advertisement-contract tests.
- [x] Scan for advertised UUIDs `0x3080`–`0x3083`.
- [x] Add clear no-result and Android location-permission guidance.
- [x] Pass focused tests, full mobile tests, analysis, and APK build.

## Checkpoint A: Hardware Discovery

- [ ] Android lists the running BridgePad FAP.
- [ ] Pairing succeeds and protocol reaches Ready.
- [ ] Capture state-only evidence if either step fails.

## Phase 2: Full Bridge Acceptance

- [ ] Type text and Enter through the USB host.
- [ ] Move, click, and scroll through the USB host.
- [ ] Verify release-all on Back, BLE loss, and heartbeat timeout.

## Phase 3: Optional BadUSB Comparison

- [ ] Obtain explicit approval before this phase.
- [ ] Add a minimal USB-only BadUSB-style HID adapter.
- [ ] Run current-backend versus BadUSB-style A/B tests.
- [ ] Keep the adapter only if it demonstrates a concrete advantage.

## Phase 4: Decision and Delivery

- [ ] Record the architecture decision and test evidence.
- [ ] Review all changes and run mobile/firmware release gates.
- [ ] Push the private experiment branch and publish test artifacts if approved.
- [ ] Merge only proven improvements into `main`.
