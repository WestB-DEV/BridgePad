import 'package:flutter/material.dart';

import 'keyboard_input.dart';

class LiveTypingField extends StatefulWidget {
  const LiveTypingField({
    super.key,
    required this.enabled,
    required this.focusNode,
    required this.onEdit,
    required this.onEnter,
    required this.resetToken,
    this.shortcutMode = false,
  });
  final bool enabled;
  final FocusNode focusNode;
  final ValueChanged<LiveEdit> onEdit;
  final VoidCallback onEnter;
  final int resetToken;
  final bool shortcutMode;

  @override
  State<LiveTypingField> createState() => LiveTypingFieldState();
}

class LiveTypingFieldState extends State<LiveTypingField> {
  // A nonprinting anchor lets an IME report Backspace even on an empty buffer.
  static const _anchor = '\u2060';
  final _controller = TextEditingController(text: _anchor);
  final _tracker = LiveEditTracker();
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _tracker.reset(_anchor);
    _controller.selection = const TextSelection.collapsed(offset: 1);
    _controller.addListener(_changed);
  }

  void _reset() {
    _updating = true;
    _tracker.reset(_anchor);
    _controller.value = const TextEditingValue(
      text: _anchor,
      selection: TextSelection.collapsed(offset: 1),
    );
    _updating = false;
  }

  @override
  void didUpdateWidget(covariant LiveTypingField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetToken != widget.resetToken ||
        oldWidget.enabled != widget.enabled) {
      _reset();
    }
  }

  void commitPending() => _changed(forceCommit: true);

  void _changed({bool forceCommit = false}) {
    if (_updating || !widget.enabled) return;
    final value = _controller.value;
    final edit = _tracker.update(
      forceCommit || widget.shortcutMode
          ? value.copyWith(composing: TextRange.empty)
          : value,
    );
    if (edit == null || (edit.backspaces == 0 && edit.text.isEmpty)) return;
    final text = edit.text.replaceAll(_anchor, '');
    widget.onEdit(LiveEdit(edit.backspaces, text));
    // Keep normal composing/committed text intact. Only reset an exhausted anchor
    // or a bounded buffer, never clear the controller on every keystroke.
    if (value.text.isEmpty || value.text.length > 4096) _reset();
  }

  void _submitted(String _) {
    // Multiline EditableText consumes the paired newline action itself. Other
    // IME completion actions arrive here and each represents a distinct Enter.
    widget.onEnter();
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: const Key('live-input'),
    controller: _controller,
    focusNode: widget.focusNode,
    enabled: widget.enabled,
    keyboardType: TextInputType.multiline,
    textInputAction: TextInputAction.newline,
    autocorrect: false,
    enableSuggestions: false,
    enableIMEPersonalizedLearning: false,
    smartDashesType: SmartDashesType.disabled,
    smartQuotesType: SmartQuotesType.disabled,
    enableInteractiveSelection: false,
    maxLines: null,
    expands: true,
    textAlignVertical: TextAlignVertical.top,
    decoration: const InputDecoration(
      labelText: 'Live typing',
      hintText: 'Type to the connected computer',
      isDense: true,
    ),
    onEditingComplete: () {},
    onSubmitted: _submitted,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
