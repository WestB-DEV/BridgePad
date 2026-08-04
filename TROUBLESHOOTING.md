# Troubleshooting

- **No device appears:** Open the BridgePad FAP first, enable Bluetooth on Android, grant Nearby Devices (Android 12+) or Location (Android 8–11), then scan again. Exit the official Flipper mobile app so it does not hold the BLE connection.
- **Pairing fails:** Remove the old Android Bluetooth bond, exit/reopen the FAP, and accept the new system pairing prompt. BridgePad intentionally uses a separate Flipper bond store.
- **USB is not ready:** Use a data-capable USB cable and close other Flipper USB apps. The host should enumerate `BridgePad HID` as a generic keyboard and mouse.
- **Input is ignored:** Both BLE and USB must be ready, then OK must be pressed on the Flipper for every session.
- **Text is rejected:** V1 permits printable US-QWERTY ASCII only; line breaks, emoji, and accented characters are blocked. Use the Enter key control for a newline.
- **A modifier seems held:** Tap **RELEASE ALL + DISARM** or press Back on the Flipper. Disconnect and timeout paths also release everything.
- **macOS keyboard setup appears:** Choose ANSI/US if prompted. BridgePad sends standard HID usages and does not impersonate a branded receiver.
