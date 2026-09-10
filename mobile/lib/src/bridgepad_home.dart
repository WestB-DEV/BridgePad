import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'android_ble_platform.dart';
import 'ble_transport.dart';
import 'demo_transport.dart';
import 'session_controller.dart';
import 'remote_workspace.dart';

class BridgepadHome extends StatefulWidget {
  const BridgepadHome({
    super.key,
    this.bleTransport,
    this.androidPlatform = const AndroidBlePlatform(),
  });

  final BridgepadBleTransport? bleTransport;
  final AndroidBlePlatform androidPlatform;

  @override
  State<BridgepadHome> createState() => _BridgepadHomeState();
}

class _BridgepadHomeState extends State<BridgepadHome>
    with WidgetsBindingObserver {
  BridgepadBleTransport? _ownedBleTransport;
  BridgepadBleTransport get _bleTransport =>
      widget.bleTransport ?? (_ownedBleTransport ??= BridgepadBleTransport());
  late final AndroidBlePlatform _android;
  BridgepadSessionController? _session;
  StreamSubscription<BridgepadBleDevice>? _scan;
  final _devices = <String, BridgepadBleDevice>{};
  bool _scanning = false;
  String? _pageError;

  @override
  void initState() {
    super.initState();
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
    setState(() {
      _pageError = null;
      _devices.clear();
      _scanning = true;
    });
    try {
      await _android.requestPermissions();
      await _scan?.cancel();
      _scan = _bleTransport.scan().listen(
        (device) {
          if (!mounted) return;
          setState(() => _devices[device.id] = device);
        },
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _pageError = _friendly(error);
            _scanning = false;
          });
        },
      );
      Future<void>.delayed(const Duration(seconds: 10), () {
        if (mounted) setState(() => _scanning = false);
        _scan?.cancel();
      });
    } catch (error) {
      setState(() {
        _pageError = _friendly(error);
        _scanning = false;
      });
    }
  }

  Future<void> _connect(BridgepadBleDevice device) async {
    await _scan?.cancel();
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
    _scan?.cancel();
    _session?.dispose();
    final ble = widget.bleTransport ?? _ownedBleTransport;
    if (ble != null) unawaited(ble.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      // Keep the safety/status row, not decorative chrome, above a short IME viewport.
      appBar: session != null && MediaQuery.viewInsetsOf(context).bottom > 0
          ? null
          : AppBar(
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
            : RemoteWorkspace(session: session),
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
