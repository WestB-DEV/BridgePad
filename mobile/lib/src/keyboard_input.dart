import 'package:flutter/services.dart';

class LiveEdit {
  const LiveEdit(this.backspaces, this.text);
  final int backspaces;
  final String text;
}

/// Only committed IME changes become host input. No clipboard or disk history.
class LiveEditTracker {
  String _committed = '';

  LiveEdit? update(TextEditingValue value) {
    if (value.composing.isValid && !value.composing.isCollapsed) return null;
    final text = value.text;
    var common = 0;
    while (common < text.length &&
        common < _committed.length &&
        text.codeUnitAt(common) == _committed.codeUnitAt(common)) {
      common++;
    }
    final edit = LiveEdit(_committed.length - common, text.substring(common));
    _committed = text;
    return edit;
  }

  void reset([String text = '']) => _committed = text;
}

class ModifierState {
  final _next = <int>{};
  final _locked = <int>{};
  Set<int> get active => {..._next, ..._locked};
  bool isLocked(int usage) => _locked.contains(usage);
  void toggle(int usage) {
    if (_locked.remove(usage)) return;
    if (!_next.remove(usage)) _next.add(usage);
  }

  void lock(int usage) {
    _next.remove(usage);
    if (!_locked.remove(usage)) _locked.add(usage);
  }

  Set<int> take() {
    final result = active;
    _next.clear();
    return result;
  }

  void clear() {
    _next.clear();
    _locked.clear();
  }
}

abstract final class HidKeyboard {
  static int chord(int key, Set<int> modifiers) {
    var result = key;
    for (final modifier in modifiers) {
      if (modifier < 0xe0 || modifier > 0xe7) {
        throw ArgumentError.value(modifier, 'modifier');
      }
      result |= 1 << (8 + modifier - 0xe0);
    }
    return result;
  }

  /// Flipper keycode: low byte HID usage; high byte modifier bit mask.
  static int ascii(String character) {
    if (character.length != 1) throw ArgumentError.value(character);
    final code = character.codeUnitAt(0);
    if (code >= 97 && code <= 122) return code - 97 + 4;
    if (code >= 65 && code <= 90) return 0x0200 | (code - 65 + 4);
    if (code >= 49 && code <= 57) return code - 49 + 0x1e;
    const plain = '0\n\b\t -=[]\\;\',./`';
    const usages = [
      0x27,
      0x28,
      0x2a,
      0x2b,
      0x2c,
      0x2d,
      0x2e,
      0x2f,
      0x30,
      0x31,
      0x33,
      0x34,
      0x36,
      0x37,
      0x38,
      0x35,
    ];
    final index = plain.indexOf(character);
    if (index >= 0) return usages[index];
    const shifted = '!@#\$%^&*()_+{}|:"<>?~';
    const shiftedUsages = [
      0x1e,
      0x1f,
      0x20,
      0x21,
      0x22,
      0x23,
      0x24,
      0x25,
      0x26,
      0x27,
      0x2d,
      0x2e,
      0x2f,
      0x30,
      0x31,
      0x33,
      0x34,
      0x36,
      0x37,
      0x38,
      0x35,
    ];
    final shiftedIndex = shifted.indexOf(character);
    if (shiftedIndex >= 0) return 0x0200 | shiftedUsages[shiftedIndex];
    throw ArgumentError.value(character, 'character', 'US-QWERTY ASCII only');
  }
}
