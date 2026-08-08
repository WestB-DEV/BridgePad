# Changelog

## 0.1.5-test.1 - 2026-08-08

### Fixed

- The armed trackpad now owns touches inside its surface instead of accidentally scrolling the surrounding Android page.
- Pointer movement is accumulated at 30 Hz and accelerated 2.4× so quick swipes no longer lose most of their motion.
- Two-finger scrolling now follows the fingers' shared vertical movement independently from pointer movement.
- The Android keyboard's Enter action now sends a USB HID Enter without requiring the keyboard to be collapsed.

## 0.1.4-test.1 - 2026-08-08

### Fixed

- Flipper BLE responses are now serialized through a bounded queue and advanced only after the serial service confirms `DataSent`, preventing the `HELLO` acknowledgement from being dropped behind its status response.

### Changed

- APK, FAP, and checksum deliverables now include the complete test version in their filenames.
- Android and Flipper application metadata now share the `0.1.4` base version.

## 0.1.3 - 2026-08-08

### Fixed

- Android discovery now scans for the four Flipper serial-profile advertisement IDs used by official and Momentum firmware instead of filtering for a GATT service that appears only after connection.
- Empty scans now explain the Flipper app prerequisite and the Location permission and system switch required for BLE discovery on Android 11 or older without collecting or storing location data.

## 0.1.2 - 2026-08-08

### Fixed

- Android now prepares BLE notifications and negotiates a 247-byte MTU before starting the BridgePad protocol handshake.
- A lost first `HELLO` response is retried instead of immediately failing the connection.
- Failed handshakes close partial GATT links and return to the scan screen so the next attempt starts cleanly.
- Pairing is limited to 30 seconds, ignores bond events from other devices, and can be cancelled safely before retry.

## 0.1.1 - 2026-08-08

### Fixed

- BridgePad now remains open when qFlipper, RPC, USB, or Bluetooth temporarily blocks hardware startup.
- The Flipper displays the unavailable subsystem and lets OK retry it instead of returning to the application folder.
- Partial Bluetooth startup is unwound before retry, preventing stale callbacks and profiles.

## 0.1.0 - 2026-08-04

- Initial stock-firmware Flipper BLE-to-USB HID bridge.
- Android 8+ sideloadable Flutter client with explicit bonding.
- Live and reviewed ASCII typing, explicit clipboard read, special/function/modifier keys.
- Trackpad movement, click, right-click, drag, and two-finger scroll.
- Physical arming, heartbeat timeout, release-all safety paths, and offline demo mode.
