# ADR-001: Locked input workspace and cancellable HID transactions

## Status

Accepted for private 0.2.0 testing; physical-host tuning remains open.

## Date

2026-09-09

## Context

The scrolling remote competed with pointer gestures, keyboard completion could
dismiss the IME, and a throttled move was discarded instead of accumulated.
Independent HID down/up calls could interleave. The existing protocol and physical
arming flow should remain compatible, and uncertain host input must not replay.

## Decision

- Keep the root remote fixed and let Scaffold resize to keyboard insets. Only the
  draft and expanded Keys panel scroll. Preserve separate editor focus nodes and
  use TextFieldTapRegion around controls.
- Track committed IME edits without clearing the controller on each change. Flush
  pending composition before explicit host keys, modifiers, mode switches, or
  pointer actions so a composing word does not arrive after its intended action.
- Serialize discrete input transactions with a generation token checked before
  every frame. RELEASE_ALL bypasses the input queue and invalidates queued work;
  heartbeat remains independent. Close a faulted link even if release succeeds,
  so an apparently armed session cannot survive without its heartbeat.
- Keep protocol v1. Encode line breaks with existing Enter commands and pack
  modifier bits into HID key codes. Lock modifiers logically in the UI, emitting
  a complete press/release chord for each key. Never hold Super indefinitely.
- Accumulate fractional linear motion at 33 ms cadence, split signed-byte deltas,
  and bound stale/pending movement. A safety cancellation may discard queued
  motion deliberately; normal coalescing must preserve distance. No acceleration
  or smoothing until measurements on a physical Mac justify it.
- Validate a complete Compose draft before transmission, release mouse buttons,
  pause pointer/editor input, then send atomically. Clear only on success. Never
  auto-retry input after an uncertain acknowledgement.

## Alternatives considered

- A scrolling single page retains reachability problems and gesture competition.
- Physically held modifier locks complicate Compose isolation and stuck-key
  recovery; logical locks support the requested repeated keyboard shortcuts.
- Browser-only mocks cannot verify Android IME behavior. Use Flutter widget tests
  plus the existing Android emulator/Gboard and an instrumented demo transport.
- Motion acceleration could conceal lost deltas and compound host acceleration;
  linear baseline plus precision is easier to measure first.

## Consequences

Long Compose sends temporarily pause mouse input. Old queued input is cancelled,
not replayed after disarm/re-arm. Physical re-arming is required after lifecycle
interruptions (including orientation changes that trigger Android interruption).
0.2.0's FAP is required for the corrected modifier and mouse-release adapter.
The demo records aggregate opcode counts only, not typed/clipboard text.

## Source references

- [Flutter keyboard insets](https://api.flutter.dev/flutter/widgets/MediaQueryData/viewInsets.html)
- [Flutter editing completion](https://api.flutter.dev/flutter/material/TextField/onEditingComplete.html)
- [Flutter multiline action dispatch](https://api.flutter.dev/flutter/widgets/EditableTextState/performAction.html)
- [Remote Mouse gesture conventions](https://www.remotemouse.net/faq)

See `tasks/controls-verification.md` for the test evidence and remaining gates.
