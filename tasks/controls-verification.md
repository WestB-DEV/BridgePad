# BridgePad 0.2.0 controls preview — verification

## Release scope

Tag: `v0.2.0-test.1`. Android: `0.2.0+7`; Flipper FAP: `0.2.0`.
This is a public, developer-signed **prerelease**, not a production or
hardware-certified release. Install its matching APK and FAP.
Exact asset digests are in `release/SHA256SUMS`.

The controls work started from main commit `4d79951`. The separate
`experiment/badusb-bridge` branch and its 0.1.5 BLE discovery and firmware TX
queue work remain intact but are **not merged into this preview**. Consequently,
this preview is not a claim of complete parity with the experimental builds.

## Automated verification

- All **55 Flutter tests pass**; `flutter analyze` reports no issues.
- All **four host-C suites pass**: protocol, core, startup, HID adapter.
- Android debug APK and Flipper FAP build successfully.
- FAP target 7, API 87.1, official Flipper release SDK 1.4.3.
- Flutter 3.47.3 / Dart 3.13.3, Android SDK 36, JDK 21, ufbt 0.2.6.
- Locked dependency resolution passes; no advisories were reported by pub.
  This is not a comprehensive dependency or application security audit.
- The BLE plugin emits a future Kotlin Gradle migration warning.

Regression coverage includes exactly-once Enter, retained focus, reachable Send,
multiline ordering, whole-draft validation, limits, packed shortcuts, one-shot
and locked modifiers, IME replacements/Backspace, cancellation with delayed
ACKs, disarm/re-arm, fractional motion, signed-byte splitting, tap/double-tap/
drag/scroll, stale backlog safety, and heartbeat failure/release paths.

Baseline tests reproduced multiline rejection and interleaved down/down/up/up
commands. Firmware adapter regressions failed before correction. A full-app
compact-landscape test reproduced a 44-pixel overflow; hiding the title bar
while the keyboard is open corrected it.

## Emulator evidence — not physical hardware

Android 35 x86_64, Gboard, 1080x2220 at 440 dpi, hardware-free demo transport:

- Actual Gboard Enter displayed a return arrow, entered a newline, and retained
  editor focus and keyboard visibility.
- Compose Send cleared a settled draft and retained focus; Android reported
  `mInputShown=true` and `mIsInputViewShown=true`.
- Keys opened above Gboard. Trackpad swipes left editor/page bounds unchanged.
- Portrait at 1.5x system text scale fit with Gboard open.
- Rotation exercised the lifecycle safety-disarm path.
- Widget tests cover compact portrait, landscape, enlarged text, and keyboard insets.
- Screenshots are in `release/evidence/`; the final enlarged-text Compose
  screenshot is `compose-large-final.png`. Earlier screenshots predate the
  compact title-bar adjustment.

The host emulator repeatedly crashed when opening landscape Gboard, including
with software rendering. Therefore landscape keyboard behavior is **not**
emulator-validated. Immediate synthetic typing after a mode switch sometimes
produced no draft; settled-view typing worked. Cause is not established and
rapid mode transitions remain an explicit validation gate.

## Physical hardware gates

No physical phone, Flipper, or macOS host was tested during this implementation.
Before a stable release:

1. Verify Android/Gboard Enter, Backspace, paste, composition, rapid mode
   transitions, Send, focus retention, simultaneous typing/pointer and multitouch.
2. Measure macOS precision, target selection, double-click, repeated-stroke
   dragging, scrolling and Command shortcuts; then Windows/Linux equivalents.
3. Exercise physical disarm, BLE/USB loss, backgrounding, rotation, heartbeat loss
   and failed release during drag/chords/long drafts. Confirm no held input and
   no replay after re-arm.
4. Resolve the development USB PID before a production release.

## Cleanup and publication checks

A reference-checked cleanup removed 166 net lines of unused code/configuration/
template comments and the unused Cupertino icon dependency. Existing test
assertions, safety paths, demo instrumentation and platform entry points remain.
Independent firmware/native review found no blocking cleanup issue.

Before publication, all reachable Git history and current files were checked for
common credential patterns and sensitive filenames; no credentials were found.
Machine-specific implementation notes were retained locally, not published.
Existing licenses are unchanged: firmware GPL-3.0-only, protocol MIT, mobile
source proprietary/source-visible with intended-use permission for binaries.

## Reproduction

```sh
make test
cd firmware
ufbt
cd ../mobile
flutter pub get --enforce-lockfile
flutter test
flutter analyze
flutter build apk --debug --no-pub
```

## If testing fails

Use Release All + Disarm and stop using the affected build. Report reproduction
steps without passwords, clipboard contents, or device identifiers. Earlier
prerelease assets remain available; Android may require uninstalling a newer
version before installing an older one, which removes local app data. A severe
issue warrants withdrawing the affected release assets; already-downloaded
copies and public repository history cannot be recalled.
