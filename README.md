# BridgePad

BridgePad turns a Flipper Zero into an explicitly armed Bluetooth-to-USB keyboard and mouse bridge. The phone communicates with the Flipper over its stock BLE serial profile; the Flipper presents a generic `BridgePad HID` keyboard/mouse to the USB host.

## Install the test build

1. Copy `release/bridgepad.fap` to `apps/USB/` on the Flipper SD card with qFlipper.
2. On Android, enable installation from your file manager and install `release/bridgepad-debug.apk`. Android will warn that this is a developer-signed sideloaded build.
3. Connect the Flipper USB-C data cable to the target Mac, PC, or other USB host.
4. Run **Apps → USB → BridgePad** on the Flipper. It temporarily takes over Bluetooth and USB, then restores both when it exits.
5. Open BridgePad on Android, tap **Find BridgePad**, select the Flipper, and accept Android's pairing prompt.
6. Confirm that the phone and USB indicators are ready, then press **OK** physically on the Flipper. The ARMED indicator must light before input is accepted.

Press **Back** on the Flipper or **RELEASE ALL + DISARM** on the phone to stop input immediately. A BLE/USB disconnect, app lifecycle interruption, or five-second heartbeat loss also releases all keys and buttons.

## Privacy and safety

- No account, analytics, advertising, Internet permission, clipboard history, or background clipboard access.
- Clipboard text is read only when **Read clipboard** is tapped and is not persisted or logged.
- V1 accepts printable US-QWERTY ASCII only. Unsupported Unicode and control characters are rejected visibly.
- This project does not use Logitech USB identifiers. The development build uses `1209:B1D6`; reserve a PID before public distribution.

## Build

Prerequisites are Flutter stable, Android SDK 36, JDK 17, `ufbt`, and the official release-channel Flipper SDK.

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
