import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'android_ble_platform.dart';
import 'ble_transport.dart';
import 'demo_transport.dart';
import 'session_controller.dart';
import 'trackpad.dart';

class BridgepadHome extends StatefulWidget {
  const BridgepadHome({
    super.key,
    this.bleTransport,
    this.androidPlatform = const AndroidBlePlatform(),
    this.scanTimeout = const Duration(seconds: 10),
  });

  final BridgepadBleTransport? bleTransport;
  final AndroidBlePlatform androidPlatform;
  final Duration scanTimeout;

  @override
  State<BridgepadHome> createState() => _BridgepadHomeState();
}

class _BridgepadHomeState extends State<BridgepadHome>
    with WidgetsBindingObserver {
  static const _noDeviceGuidance =
      'No BridgePad found. Keep BridgePad open on the Flipper and try again. '
      'On Android 11 or older, allow Location and turn the phone\'s Location '
      'switch on. BridgePad does not collect or store your location.';

  late final BridgepadBleTransport _bleTransport;
  late final AndroidBlePlatform _android;
  BridgepadSessionController? _session;
  StreamSubscription<BridgepadBleDevice>? _scan;
  final _devices = <String, BridgepadBleDevice>{};
  int _scanGeneration = 0;
  bool _scanning = false;
  String? _pageError;

  @override
  void initState() {
    super.initState();
    _bleTransport = widget.bleTransport ?? BridgepadBleTransport();
    _android = widget.androidPlatform;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      final release = _session?.emergencyRelease();
      if (release != null) unawaited(release.catchError((_) {}));
    }
  }

  Future<void> _startScan() async {
    final generation = ++_scanGeneration;
    setState(() {
      _pageError = null;
      _devices.clear();
      _scanning = true;
    });
    try {
      await _android.requestPermissions();
      if (!mounted || generation != _scanGeneration) return;
      await _scan?.cancel();
      _scan = null;
      if (!mounted || generation != _scanGeneration) return;
      var scanFailed = false;
      _scan = _bleTransport.scan().listen(
        (device) {
          if (!mounted || generation != _scanGeneration) return;
          setState(() => _devices[device.id] = device);
        },
        onError: (Object error) {
          scanFailed = true;
          if (!mounted || generation != _scanGeneration) return;
          setState(() {
            _pageError = _friendly(error);
            _scanning = false;
          });
        },
      );
      await Future<void>.delayed(widget.scanTimeout);
      if (!mounted || generation != _scanGeneration || scanFailed) return;
      final completedScan = _scan;
      _scan = null;
      if (completedScan != null) unawaited(completedScan.cancel());
      setState(() {
        _scanning = false;
        if (_devices.isEmpty) _pageError = _noDeviceGuidance;
      });
    } catch (error) {
      if (!mounted || generation != _scanGeneration) return;
      setState(() {
        _pageError = _friendly(error);
        _scanning = false;
      });
    }
  }

  Future<void> _connect(BridgepadBleDevice device) async {
    _scanGeneration++;
    await _scan?.cancel();
    _scan = null;
    setState(() {
      _scanning = false;
      _pageError = null;
    });
    BridgepadSessionController? connectingSession;
    try {
      await _android.bond(device.id);
      final session = BridgepadSessionController(_bleTransport);
      connectingSession = session;
      session.addListener(_sessionChanged);
      setState(() => _session = session);
      await session.connect(device.id);
    } catch (error) {
      connectingSession?.removeListener(_sessionChanged);
      connectingSession?.dispose();
      if (!mounted) return;
      setState(() {
        if (identical(_session, connectingSession)) _session = null;
        _pageError = _friendly(error);
      });
    }
  }

  Future<void> _startDemo() async {
    final session = BridgepadSessionController(DemoBridgepadTransport());
    session.addListener(_sessionChanged);
    setState(() {
      _pageError = null;
      _session = session;
    });
    await session.connect('demo');
  }

  void _sessionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _disconnect() async {
    final session = _session;
    if (session == null) return;
    await session.disconnect();
    session.removeListener(_sessionChanged);
    session.dispose();
    if (mounted) setState(() => _session = null);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanGeneration++;
    _scan?.cancel();
    _session?.dispose();
    unawaited(_bleTransport.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('BridgePad'),
            Text(
              'PHONE → BLE → USB HID',
              style: TextStyle(fontSize: 10, letterSpacing: 1.4),
            ),
          ],
        ),
        actions: [
          if (session != null)
            IconButton(
              tooltip: 'Disconnect',
              onPressed: _disconnect,
              icon: const Icon(Icons.link_off),
            ),
        ],
      ),
      body: SafeArea(
        child: session == null
            ? _ConnectionPanel(
                scanning: _scanning,
                devices: _devices.values.toList(),
                error: _pageError,
                onScan: _startScan,
                onConnect: _connect,
                onDemo: _startDemo,
              )
            : BridgepadRemotePanel(session: session),
      ),
    );
  }

  static String _friendly(Object error) {
    if (error is PlatformException) return error.message ?? error.code;
    return error.toString().replaceFirst('Exception: ', '');
  }
}

class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({
    required this.scanning,
    required this.devices,
    required this.error,
    required this.onScan,
    required this.onConnect,
    required this.onDemo,
  });

  final bool scanning;
  final List<BridgepadBleDevice> devices;
  final String? error;
  final VoidCallback onScan;
  final ValueChanged<BridgepadBleDevice> onConnect;
  final VoidCallback onDemo;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.keyboard_alt_outlined, size: 64),
        const SizedBox(height: 16),
        Text(
          'Turn any USB host into your workspace.',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        const Text(
          'Open BridgePad on the Flipper, connect its USB cable to the computer, then find it here. Input stays blocked until you press OK on the Flipper.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: scanning ? null : onScan,
          icon: scanning
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.bluetooth_searching),
          label: Text(scanning ? 'Scanning…' : 'Find BridgePad'),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            key: const Key('connection-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        for (final device in devices)
          Card(
            child: ListTile(
              leading: const Icon(Icons.developer_board),
              title: Text(device.name),
              subtitle: Text('${device.id}  •  ${device.rssi} dBm'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onConnect(device),
            ),
          ),
        const SizedBox(height: 24),
        TextButton(
          onPressed: onDemo,
          child: const Text('Open hardware-free demo'),
        ),
        const Text(
          'Offline by design • no accounts • no clipboard history',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}

class BridgepadRemotePanel extends StatefulWidget {
  const BridgepadRemotePanel({super.key, required this.session});
  final BridgepadSessionController session;

  @override
  State<BridgepadRemotePanel> createState() => _RemotePanelState();
}

class _RemotePanelState extends State<BridgepadRemotePanel> {
  final _compose = TextEditingController();
  final _live = TextEditingController();
  final _focus = FocusNode();
  final _modifiers = <int>{};

  @override
  void dispose() {
    _compose.dispose();
    _live.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _sendCompose() => _guard(() async {
    final text = _compose.text;
    if (text.isEmpty) return;
    await widget.session.sendText(text);
    _compose.clear();
  });

  Future<void> _paste() => _guard(() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null) _compose.text = text;
  });

  void _sendLiveInput(String value) {
    if (value.isEmpty) return;
    _live.clear();
    _guard(() async {
      final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      final segments = normalized.split('\n');
      for (var index = 0; index < segments.length; index++) {
        if (segments[index].isNotEmpty) {
          await widget.session.sendText(segments[index]);
        }
        if (index + 1 < segments.length) {
          await widget.session.sendKey(0x28);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        _StatusStrip(session: session),
        if (!session.deviceStatus.isArmed)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.secondary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('Press OK on the Flipper to arm this session.'),
          ),
        const SizedBox(height: 12),
        BridgepadTrackpad(
          enabled: session.canSend,
          guard: _guard,
          onMove: session.pointerMove,
          onScroll: session.scroll,
          onButton: session.pointerButton,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('live-typing'),
          controller: _live,
          focusNode: _focus,
          enabled: session.canSend,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          maxLines: 1,
          decoration: const InputDecoration(
            labelText: 'Live typing',
            hintText: 'Type here • keyboard Enter sends Enter',
            prefixIcon: Icon(Icons.keyboard),
          ),
          onChanged: _sendLiveInput,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _compose,
          minLines: 2,
          maxLines: 5,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Compose and review',
            helperText: 'Printable US-QWERTY ASCII • 4,096 characters max',
            suffixIcon: IconButton(
              tooltip: 'Read clipboard',
              onPressed: _paste,
              icon: const Icon(Icons.content_paste),
            ),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: session.canSend ? _sendCompose : null,
          icon: const Icon(Icons.send),
          label: const Text('Send reviewed text'),
        ),
        const SizedBox(height: 12),
        _KeyToolbar(
          enabled: session.canSend,
          modifiers: _modifiers,
          onKey: (usage) => _guard(() => session.sendKey(usage)),
          onModifier: (usage) => _guard(() async {
            if (_modifiers.remove(usage)) {
              await session.keyUp(usage);
            } else {
              await session.keyDown(usage);
              _modifiers.add(usage);
            }
            setState(() {});
          }),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => _guard(() async {
            await session.emergencyRelease();
            _modifiers.clear();
            setState(() {});
          }),
          icon: const Icon(Icons.pan_tool_outlined),
          label: const Text('RELEASE ALL + DISARM'),
        ),
      ],
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.session});
  final BridgepadSessionController session;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _Status('BLE', session.deviceStatus.isBleConnected)),
        const SizedBox(width: 6),
        Expanded(child: _Status('USB', session.deviceStatus.isUsbConnected)),
        const SizedBox(width: 6),
        Expanded(child: _Status('ARMED', session.deviceStatus.isArmed)),
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status(this.label, this.active);
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outline;
    return Semantics(
      label: '$label ${active ? 'ready' : 'not ready'}',
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          border: Border.all(color: color.withValues(alpha: .45)),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          '●  $label',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _KeyToolbar extends StatelessWidget {
  const _KeyToolbar({
    required this.enabled,
    required this.modifiers,
    required this.onKey,
    required this.onModifier,
  });

  final bool enabled;
  final Set<int> modifiers;
  final ValueChanged<int> onKey;
  final ValueChanged<int> onModifier;

  static const keys = <String, int>{
    'Esc': 0x29,
    'Tab': 0x2b,
    'Enter': 0x28,
    '⌫': 0x2a,
    '←': 0x50,
    '↑': 0x52,
    '↓': 0x51,
    '→': 0x4f,
    'Home': 0x4a,
    'End': 0x4d,
    'PgUp': 0x4b,
    'PgDn': 0x4e,
    'F1': 0x3a,
    'F2': 0x3b,
    'F3': 0x3c,
    'F4': 0x3d,
    'F5': 0x3e,
    'F6': 0x3f,
    'F7': 0x40,
    'F8': 0x41,
    'F9': 0x42,
    'F10': 0x43,
    'F11': 0x44,
    'F12': 0x45,
  };

  static const modifierKeys = <String, int>{
    'Ctrl': 0xe0,
    'Shift': 0xe1,
    'Alt': 0xe2,
    'Meta': 0xe3,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('KEYS', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final entry in modifierKeys.entries)
              FilterChip(
                label: Text(entry.key),
                selected: modifiers.contains(entry.value),
                onSelected: enabled ? (_) => onModifier(entry.value) : null,
              ),
            for (final entry in keys.entries)
              ActionChip(
                label: Text(entry.key),
                onPressed: enabled ? () => onKey(entry.value) : null,
              ),
          ],
        ),
      ],
    );
  }
}
