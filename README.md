# BridgePad

BridgePad turns a Flipper Zero into an explicitly armed Bluetooth-to-USB keyboard and mouse bridge. The phone communicates with the Flipper over its stock BLE serial profile; the Flipper presents a generic `BridgePad HID` keyboard/mouse to the USB host.

## Install the test build

Download the matching files from [0.2.0 controls preview](https://github.com/WestB-DEV/BridgePad/releases/tag/v0.2.0-test.1):

- [Android APK](https://github.com/WestB-DEV/BridgePad/releases/download/v0.2.0-test.1/bridgepad-debug.apk)
- [Flipper Zero FAP](https://github.com/WestB-DEV/BridgePad/releases/download/v0.2.0-test.1/bridgepad.fap)
- [SHA-256 checksums](https://github.com/WestB-DEV/BridgePad/releases/download/v0.2.0-test.1/SHA256SUMS)

This is a **prerelease**, not a hardware-certified stable version. It contains the
main-based controls redesign; the separate `experiment/badusb-bridge` branch and
its 0.1.5 BLE discovery/response-queue changes have not been merged into this preview.
Earlier experimental builds remain on the [releases page](https://github.com/WestB-DEV/BridgePad/releases).

1. Copy the downloaded `bridgepad.fap` to `apps/USB/` on the Flipper SD card with qFlipper.
2. On Android, enable installation from your file manager and install `bridgepad-debug.apk`. Android will warn that this is a developer-signed, debuggable sideloaded build. If an older build has a different signing certificate, Android requires uninstalling it first; uninstalling removes its local app data.
3. Connect the Flipper USB-C data cable to the target Mac, PC, or other USB host.
4. Run **Apps → USB → BridgePad** on the Flipper. It temporarily takes over Bluetooth and USB, then restores both when it exits.
5. Open BridgePad on Android, tap **Find BridgePad**, select the Flipper, and accept Android's pairing prompt.
6. Confirm that the phone and USB indicators are ready, then press **OK** physically on the Flipper. The ARMED indicator must light before input is accepted.

Press **Back** on the Flipper or **RELEASE ALL + DISARM** on the phone to stop input immediately. A BLE/USB disconnect, app lifecycle interruption, or five-second heartbeat loss also releases all keys and buttons.

The Flipper can use Bluetooth and USB HID at the same time; that simultaneous connection is BridgePad's normal operating mode. Close qFlipper before launching BridgePad because qFlipper may keep the USB control interface busy.

If Android pairing fails, leave BridgePad open on the Flipper, keep it near the phone, and retry from the app. A failed attempt now times out after 30 seconds and returns to the scan screen instead of leaving a stale connection behind.

## Privacy and safety

- No account, analytics, advertising, clipboard history, or background clipboard access. The debug APK includes Flutter development tooling and its Internet permission; BridgePad's control flow uses local BLE/USB, not a cloud service.
- Clipboard text is read only when **Read clipboard** is tapped and is not persisted or logged.
- Reviewed text accepts printable US-QWERTY ASCII plus line breaks (CRLF is normalized), up to 4,096 characters. Other Unicode and control characters are rejected before transmission.
- This project does not use Logitech USB identifiers. The test build uses development USB ID `1209:B1D6`; a reserved production PID remains a stable-release gate.

## Keyboard and trackpad controls (0.2.0 preview)

Install **both** the new Android APK and Flipper FAP: 0.2.0 corrects the firmware's modifier adapter and all-mouse-button release mask without changing protocol v1.

- The remote workspace does not page-scroll. Live typing and the trackpad share the available space; **Keys** opens a separately scrolling panel with modifiers, navigation, and F1–F12.
- **Live Enter** sends one host Enter and leaves the phone keyboard open. **Compose Enter** adds a draft newline. **Send** stays above the keyboard, sends the reviewed draft immediately, and never appends an extra Enter.
- Draft line breaks are real host Enter events and can execute commands in a terminal. Check the target application before sending. A failed send retains the draft; some text may already have arrived, so inspect the host before manually retrying.
- Tap Ctrl, Shift, Alt, or **Super** for the next key. Use the adjacent lock button for repeated shortcuts. Super means Command on macOS and the Windows/Super key elsewhere. The persistent indicator shows `next` or `locked`; these are logical locks, not indefinitely held host keys. Compose text ignores shortcut modifiers.
- Move with one finger, tap to click, double-tap to double-click, or double-tap and hold to drag. Two fingers scroll vertically. **Left**, **Right**, and latched **Drag** also work without gesture timing; Drag stays on across repeated strokes until toggled off.
- Pointer settings provide linear sensitivity, Precision, and Natural scroll. Fractional motion accumulates; an excessive or stale backlog disarms instead of replaying delayed movement. The pad pauses during an atomic Compose send.
- Release All, disconnection, app interruption, and failed input release clear local modifier/drag state. Re-arm physically after an interruption; orientation changes may also trigger this safety path.

See [verification results](tasks/controls-verification.md) for automated/emulator evidence and the outstanding physical Android/Gboard and Flipper-to-host gates. This is not a hardware-validated public release.

## Build

The 0.2.0 test build was verified with Flutter 3.47.3 / Dart 3.13.3, Android SDK 36, JDK 21, ufbt 0.2.6, and official Flipper SDK release 1.4.3 (API 87.1, target 7).

```sh
make test
cd firmware && ufbt
cd ../mobile && flutter test && flutter analyze && flutter build apk --debug
```

The mobile dependency is pinned by `pubspec.lock`. `flutter_reactive_ble` 5.5.0 declares Android compile SDK 33 while its resolved AndroidX dependencies require 34+, so the root Android Gradle script applies a narrowly scoped compile-SDK 36 compatibility override. Minimum Android remains API 26 (Android 8).

## Repository boundaries

- `firmware/`: GPL-3.0-only Flipper application.
- `protocol/`: MIT-licensed protocol specification and golden vectors.
- `mobile/`: proprietary mobile application source; third-party dependencies retain their own licenses.
- `release/`: locally built, ignored test artifacts and checksums.

BridgePad is an independent project and is not affiliated with or endorsed by Flipper Devices Inc.

The public repository does not change these licenses. Mobile source remains
source-visible/proprietary; the distributed APK may be used for its intended
BridgePad functionality. See each directory's license for its terms.
