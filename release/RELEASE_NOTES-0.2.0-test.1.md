# BridgePad 0.2.0 — controls preview

Public prerelease for testing, not a stable or hardware-certified release.
Install **both** the APK and FAP attached below. Android package version is
`0.2.0+7`; firmware version is `0.2.0` (Flipper target 7, API 87.1).

## Downloads and installation

- `bridgepad-debug.apk`: Android 8+ developer-signed, debuggable sideload build.
- `bridgepad.fap`: copy to `apps/USB/` on the Flipper SD card using qFlipper.
- `SHA256SUMS`: integrity hashes for both files.
- `COPYING`: firmware GPL-3.0 license text. Matching source is in this release tag.

Use a USB data cable from Flipper to the computer, open BridgePad on both devices,
connect over BLE, then press OK physically on the Flipper to arm. Use Release All
+ Disarm or Flipper Back to stop. If Android reports a signing-certificate
conflict with an older APK, uninstalling it removes its local app data.

## Included

- Locked, keyboard-aware workspace and expandable extra keys.
- Live Enter and Compose Send with retained keyboard focus.
- Reviewed ASCII plus line breaks, whole-draft validation and no appended Enter.
- Super/Command/Windows shortcuts with one-shot or logical modifier locks.
- Fractional pointer accumulation, sensitivity/precision, explicit drag and
  bounded input delivery with safety releases.
- Firmware modifier/release fixes and unused-code/dependency cleanup.

## Verified and still open

55 Flutter tests, four firmware host-test suites, static analysis, APK and FAP
builds pass. Portrait Gboard/demo checks include retained focus, reachable Send,
no page scrolling and enlarged text.

Physical Android/Flipper-to-Mac/Windows/Linux testing remains required. Landscape
Gboard crashed the host emulator; rapid synthetic typing after mode changes was
inconsistent. These are not reported as verified. Line breaks are real host Enter
events and may execute commands in a terminal: review the target before sending.

This preview is based on main's controls redesign. The separate
`experiment/badusb-bridge` branch and 0.1.5 BLE discovery/response-queue work are
preserved but **not merged** here. Earlier experimental prereleases remain
available; this release does not claim complete feature parity with them.

The APK is a debug build with Flutter development tooling/Internet permission,
not store-ready production signing. The development USB PID also remains a
stable-release gate. See `tasks/controls-verification.md` in the tagged source.

## Licenses

Repository visibility does not change licensing: firmware GPL-3.0-only, protocol
MIT, mobile source proprietary/source-visible. Distributed mobile binaries may
be used for their intended BridgePad functionality. Third-party licenses remain.
