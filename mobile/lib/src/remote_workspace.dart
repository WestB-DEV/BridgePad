import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'keyboard_input.dart';
import 'live_typing_field.dart';
import 'session_controller.dart';
import 'protocol.dart';
import 'trackpad.dart';

class RemoteWorkspace extends StatefulWidget {
  const RemoteWorkspace({super.key, required this.session});
  final BridgepadSessionController session;

  @override
  State<RemoteWorkspace> createState() => _RemoteWorkspaceState();
}

class _RemoteWorkspaceState extends State<RemoteWorkspace>
    with WidgetsBindingObserver {
  final _compose = TextEditingController();
  final _liveFocus = FocusNode();
  final _liveField = GlobalKey<LiveTypingFieldState>();
  final _composeFocus = FocusNode();
  final _modifiers = ModifierState();
  bool _composeMode = false;
  bool _keysOpen = false;
  bool _sending = false;
  int _liveReset = 0;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_sessionChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void _sessionChanged() {
    if (!mounted) return;
    setState(() {
      if (!widget.session.canSend) {
        _modifiers.clear();
        _liveReset++;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _modifiers.clear();
      _liveReset++;
      unawaited(widget.session.emergencyRelease().catchError((_) {}));
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _modifiers.clear();
        _liveReset++;
      });
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _sendKey(int usage) {
    _commitLive();
    final modifiers = _modifiers.take();
    setState(() => _liveReset++);
    unawaited(
      _guard(() => widget.session.sendKey(usage, modifiers: modifiers)),
    );
  }

  void _commitLive() {
    if (!_composeMode) _liveField.currentState?.commitPending();
  }

  void _liveEdit(LiveEdit edit) {
    final modifiers = [
      for (var i = 0; i < edit.backspaces + edit.text.length; i++)
        _modifiers.take(),
    ];
    setState(() {});
    unawaited(
      _guard(
        () => widget.session.sendLiveEdit(
          edit.backspaces,
          edit.text,
          modifiers: modifiers,
        ),
      ),
    );
  }

  Future<void> _sendCompose() async {
    if (_sending || _compose.text.isEmpty || !widget.session.canSend) return;
    final draft = _compose.text;
    final revision = widget.session.inputRevision;
    try {
      BridgepadSessionController.validatedTextLines(draft);
    } catch (error) {
      await _guard(() async => throw error);
      return;
    }
    _composeFocus.requestFocus();
    setState(() => _sending = true);
    try {
      // Let the pad cancel its gesture queue before the atomic reviewed send.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      if (revision != widget.session.inputRevision) {
        throw const ProtocolException(
          'Session changed; review the draft before sending again',
        );
      }
      await widget.session.pointerButton(0x07, false);
      if (!mounted || revision != widget.session.inputRevision) {
        throw const ProtocolException(
          'Session changed; review the draft before sending again',
        );
      }
      await widget.session.sendText(draft);
      if (mounted) _compose.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$error\nDraft kept. Some text may already have arrived; check the host before sending again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _setMode(bool compose) {
    if (_sending) return;
    _commitLive();
    setState(() {
      _composeMode = compose;
      _keysOpen = false;
      _liveReset++;
    });
    (compose ? _composeFocus : _liveFocus).requestFocus();
  }

  Future<void> _paste() => _guard(() async {
    if (_sending) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || _sending || data?.text == null) return;
    _setMode(true);
    _compose.value = TextEditingValue(
      text: data!.text!,
      selection: TextSelection.collapsed(offset: data.text!.length),
    );
  });

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final enabled = session.canSend && !_sending;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        for (final entry in <String, bool>{
                          'BLE': session.deviceStatus.isBleConnected,
                          'USB': session.deviceStatus.isUsbConnected,
                          'ARMED': session.canSend,
                        }.entries)
                          Expanded(
                            child: Semantics(
                              label:
                                  '${entry.key} ${entry.value ? 'ready' : 'not ready'}',
                              child: Text(
                                '${entry.value ? '●' : '○'} ${entry.key}',
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: entry.value
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.outline,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (!session.canSend || _modifiers.active.isNotEmpty)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          !session.canSend
                              ? 'Press OK on the Flipper to arm.'
                              : _modifiers.active
                                    .map(
                                      (usage) =>
                                          '${_ExtraKeys.modifierLabels[usage]} ${_modifiers.isLocked(usage) ? 'locked' : 'next'}',
                                    )
                                    .join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Release All + Disarm',
                style: IconButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => _guard(session.emergencyRelease),
                icon: const Icon(Icons.pan_tool_outlined),
              ),
            ],
          ),
          Expanded(
            child: Stack(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final pad = BridgepadTrackpad(
                      session: session,
                      guard: _guard,
                      enabled: !_sending,
                      onBeforeInput: _commitLive,
                    );
                    final editor = _editor(enabled);
                    if (constraints.maxWidth >= 560) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: pad),
                          const SizedBox(width: 8),
                          Expanded(child: editor),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        Expanded(flex: 3, child: pad),
                        const SizedBox(height: 8),
                        Expanded(flex: 2, child: editor),
                      ],
                    );
                  },
                ),
                if (_keysOpen)
                  Positioned.fill(
                    child: TweenAnimationBuilder<double>(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 120),
                      tween: Tween(begin: 0, end: 1),
                      builder: (context, opacity, child) =>
                          Opacity(opacity: opacity, child: child),
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        child: _ExtraKeys(
                          enabled: enabled,
                          modifiers: _modifiers,
                          onKey: _sendKey,
                          onToggle: (usage) {
                            _commitLive();
                            setState(() => _modifiers.toggle(usage));
                          },
                          onLock: (usage) {
                            _commitLive();
                            setState(() => _modifiers.lock(usage));
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _actions(enabled),
        ],
      ),
    );
  }

  Widget _editor(bool enabled) => IndexedStack(
    index: _composeMode ? 1 : 0,
    sizing: StackFit.expand,
    children: [
      LiveTypingField(
        key: _liveField,
        shortcutMode: _modifiers.active.isNotEmpty,
        enabled: enabled,
        focusNode: _liveFocus,
        onEdit: _liveEdit,
        onEnter: () => _sendKey(0x28),
        resetToken: _liveReset,
      ),
      TextField(
        key: const Key('compose-input'),
        controller: _compose,
        focusNode: _composeFocus,
        readOnly: _sending,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        maxLines: null,
        expands: true,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        textAlignVertical: TextAlignVertical.top,
        onEditingComplete: () {},
        decoration: InputDecoration(
          labelText: _sending ? 'Sending…' : 'Compose and review',
          hintText: 'ASCII + line breaks · 4,096 max',
          isDense: true,
        ),
      ),
    ],
  );

  Widget _actions(bool enabled) => TextFieldTapRegion(
    child: Row(
      children: [
        IconButton(
          tooltip: 'Live typing',
          isSelected: !_composeMode,
          onPressed: _sending ? null : () => _setMode(false),
          icon: const Icon(Icons.keyboard),
        ),
        IconButton(
          tooltip: 'Compose and review',
          isSelected: _composeMode,
          onPressed: _sending ? null : () => _setMode(true),
          icon: const Icon(Icons.edit_note),
        ),
        IconButton(
          tooltip: 'Extra keys',
          isSelected: _keysOpen,
          onPressed: _sending
              ? null
              : () => setState(() => _keysOpen = !_keysOpen),
          icon: const Icon(Icons.keyboard_command_key),
        ),
        IconButton(
          tooltip: 'Read clipboard',
          onPressed: _sending ? null : _paste,
          icon: const Icon(Icons.content_paste),
        ),
        Expanded(
          child: _composeMode
              ? FilledButton(
                  key: const Key('send-compose'),
                  onPressed: enabled ? _sendCompose : null,
                  child: Text(_sending ? 'Sending' : 'Send', maxLines: 1),
                )
              : FilledButton(
                  onPressed: enabled ? () => _sendKey(0x28) : null,
                  child: const Text('Enter', maxLines: 1),
                ),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_sessionChanged);
    _compose.dispose();
    _liveFocus.dispose();
    _composeFocus.dispose();
    super.dispose();
  }
}

class _ExtraKeys extends StatelessWidget {
  const _ExtraKeys({
    required this.enabled,
    required this.modifiers,
    required this.onKey,
    required this.onToggle,
    required this.onLock,
  });
  final bool enabled;
  final ModifierState modifiers;
  final ValueChanged<int> onKey, onToggle, onLock;
  static const modifierLabels = {
    0xe0: 'Ctrl',
    0xe1: 'Shift',
    0xe2: 'Alt',
    0xe3: 'Super',
  };
  static const keys = {
    'Esc': 0x29,
    'Tab': 0x2b,
    'Enter': 0x28,
    '⌫': 0x2a,
    'Delete': 0x4c,
    '←': 0x50,
    '↑': 0x52,
    '↓': 0x51,
    '→': 0x4f,
    'Home': 0x4a,
    'End': 0x4d,
    'PgUp': 0x4b,
    'PgDn': 0x4e,
  };

  @override
  Widget build(BuildContext context) => TextFieldTapRegion(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('MODIFIERS', style: TextStyle(fontSize: 12)),
          const Text(
            'Tap: next key · Lock: repeated shortcuts\nSuper = Command on Mac / Windows key',
            style: TextStyle(fontSize: 12),
          ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final entry in modifierLabels.entries)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton(
                      onPressed: enabled ? () => onToggle(entry.key) : null,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: modifiers.active.contains(entry.key)
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                      ),
                      child: Text(entry.value),
                    ),
                    IconButton(
                      tooltip:
                          '${modifiers.isLocked(entry.key) ? 'Unlock' : 'Lock'} ${entry.value}',
                      onPressed: enabled ? () => onLock(entry.key) : null,
                      icon: Icon(
                        modifiers.isLocked(entry.key)
                            ? Icons.lock
                            : Icons.lock_open,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('NAVIGATION', style: TextStyle(fontSize: 12)),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final entry in keys.entries)
                OutlinedButton(
                  onPressed: enabled ? () => onKey(entry.value) : null,
                  child: Text(entry.key),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('FUNCTION KEYS', style: TextStyle(fontSize: 12)),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (var i = 1; i <= 12; i++)
                OutlinedButton(
                  onPressed: enabled ? () => onKey(0x39 + i) : null,
                  child: Text('F$i'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
