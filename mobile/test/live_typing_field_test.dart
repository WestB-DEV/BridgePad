import 'package:bridgepad/src/keyboard_input.dart';
import 'package:bridgepad/src/live_typing_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('paired newline action is consumed once even when delayed', (
    tester,
  ) async {
    final focus = FocusNode();
    final edits = <LiveEdit>[];
    var actions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 160,
            child: LiveTypingField(
              enabled: true,
              focusNode: focus,
              resetToken: 0,
              onEdit: edits.add,
              onEnter: () => actions++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('live-input')));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '\u2060\n',
        selection: TextSelection.collapsed(offset: 2),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.testTextInput.receiveAction(TextInputAction.newline);
    expect(edits.single.text, '\n');
    expect(actions, 0);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(actions, 1);
    expect(focus.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    focus.dispose();
  });

  testWidgets(
    'Backspace at the live anchor sends deletion and restores anchor',
    (tester) async {
      final focus = FocusNode();
      final edits = <LiveEdit>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 160,
              child: LiveTypingField(
                enabled: true,
                focusNode: focus,
                resetToken: 0,
                onEdit: edits.add,
                onEnter: () {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('live-input')));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        ),
      );
      await tester.pump();
      expect(edits.single.backspaces, 1);
      final field = tester.widget<TextField>(
        find.byKey(const Key('live-input')),
      );
      expect(field.controller!.text, '\u2060');
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        ),
      );
      expect(edits.length, 2);
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
    },
  );
}
