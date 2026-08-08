# Changelog

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
