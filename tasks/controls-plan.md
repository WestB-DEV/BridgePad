# Smoother controls — implementation contract

Implement the approved locked keyboard-aware Flutter workspace, retained IME focus,
multiline reviewed text, logical one-shot/locked Super/Ctrl/Shift/Alt chords,
lossless ordinary trackpad coalescing, discrete input ordering, and fail-closed release.
Connection setup, physical Flipper arming, privacy, and protocol v1 remain intact.

## Checkpoints

- [x] Input-delivery regression tests and serialized/cancellable session operations.
- [x] Locked combined workspace, Live/Compose, visible Send and extra Keys panel.
- [x] IME editing, chord mapping, modifier safety and firmware release correction.
- [x] Independent gesture/controller tests and trackpad integration.
- [x] Flutter tests/analyzer, host firmware tests, Android test APK.
- [ ] Emulator demo checks with keyboard, compact/landscape/enlarged text.
- [ ] Physical Android/Gboard and macOS/Windows/Linux HID verification (requires hardware).

No website changes or store publishing. Do not report emulator checks as hardware
validation. Record exact commands, artifacts, failures and unverified gates in
`tasks/controls-verification.md`. Spark unavailable: independent firmware review
and standalone trackpad implementation use available subagents; root owns shared
UI/session integration and all emulator operations.
