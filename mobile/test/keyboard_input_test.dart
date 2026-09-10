import 'package:bridgepad/src/keyboard_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('committed edits retain composing text until committed', () {
    final edits = LiveEditTracker();
    expect(
      edits.update(
        const TextEditingValue(
          text: 'h',
          composing: TextRange(start: 0, end: 1),
        ),
      ),
      isNull,
    );
    final result = edits.update(const TextEditingValue(text: 'hi'))!;
    expect(result.text, 'hi');
    expect(result.backspaces, 0);
    final deletion = edits.update(const TextEditingValue(text: 'h'))!;
    expect(deletion.backspaces, 1);
    expect(deletion.text, isEmpty);
  });

  test('committed replacement sends only changed tail', () {
    final edits = LiveEditTracker();
    edits.update(const TextEditingValue(text: 'cat'));
    final result = edits.update(const TextEditingValue(text: 'car'))!;
    expect(result.backspaces, 1);
    expect(result.text, 'r');
  });

  test('one-shot is consumed once while locked modifiers persist', () {
    final modifiers = ModifierState();
    modifiers.toggle(0xe0);
    modifiers.lock(0xe3);
    expect(modifiers.take(), {0xe0, 0xe3});
    expect(modifiers.take(), {0xe3});
    modifiers.clear();
    expect(modifiers.active, isEmpty);
  });

  test('Super C and Shift A map to Flipper packed keycodes', () {
    expect(HidKeyboard.chord(0x06, {0xe3}), 0x0806);
    expect(HidKeyboard.ascii('A'), 0x0204);
    expect(HidKeyboard.ascii('?'), 0x0238);
    expect(() => HidKeyboard.ascii('☃'), throwsArgumentError);
  });
}
