import 'dart:async';

import 'package:flutter/foundation.dart';

import 'protocol.dart';
import 'transport.dart';

enum BridgepadConnectionState { disconnected, connecting, negotiating, ready }

class DeviceRejectedException implements Exception {
  const DeviceRejectedException(this.status);
  final BridgepadStatus status;

  @override
  String toString() => 'BridgePad rejected the command: ${status.name}';
}

class _PendingCommand {
  _PendingCommand(this.completer, this.timer);
  final Completer<BridgepadStatus> completer;
  final Timer timer;
}

class BridgepadSessionController extends ChangeNotifier {
  BridgepadSessionController(
    this._transport, {
    this.heartbeatInterval = const Duration(seconds: 2),
    this.commandTimeout = const Duration(seconds: 3),
    this.helloAttempts = 2,
  }) : assert(helloAttempts > 0);

  final BridgepadTransport _transport;
  final Duration heartbeatInterval;
  final Duration commandTimeout;
  final int helloAttempts;
  final Map<int, _PendingCommand> _pending = {};
  StreamSubscription<Uint8List>? _messageSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  Timer? _heartbeat;
  int _nextSequence = 1;
  bool _disposed = false;

  BridgepadConnectionState connectionState =
      BridgepadConnectionState.disconnected;
  BridgepadDeviceStatus deviceStatus = BridgepadDeviceStatus.disconnected;
  String? lastError;

  bool get canSend =>
      connectionState == BridgepadConnectionState.ready &&
      deviceStatus.isUsbConnected &&
      deviceStatus.isArmed;

  Future<void> connect(String deviceId) async {
    if (connectionState != BridgepadConnectionState.disconnected) return;
    lastError = null;
    connectionState = BridgepadConnectionState.connecting;
    notifyListeners();
    _messageSubscription ??= _transport.messages.listen(
      _handleMessage,
      onError: _handleTransportError,
    );
    _connectionSubscription ??= _transport.connectionChanges.listen(
      _handleConnectionChange,
      onError: _handleTransportError,
    );
    try {
      await _transport.connect(deviceId);
      connectionState = BridgepadConnectionState.negotiating;
      notifyListeners();
      await _negotiateHello();
      if (deviceStatus.protocolVersion != BridgepadProtocol.version) {
        throw ProtocolException(
          'Device uses protocol ${deviceStatus.protocolVersion}; this app uses v1',
        );
      }
      connectionState = BridgepadConnectionState.ready;
      _heartbeat = Timer.periodic(heartbeatInterval, (_) => _sendHeartbeat());
      notifyListeners();
    } catch (error) {
      lastError = _friendlyError(error);
      try {
        await _transport.disconnect();
      } catch (_) {
        // Preserve the negotiation error; a partial link must not block retry.
      }
      connectionState = BridgepadConnectionState.disconnected;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    if (connectionState == BridgepadConnectionState.ready) {
      try {
        await _sendReliable(BridgepadOpcode.releaseAll);
      } catch (_) {
        // The Flipper also releases locally on a BLE disconnect.
      }
    }
    await _transport.disconnect();
    _resetDisconnected();
  }

  Future<void> sendText(String text) async {
    _requireArmed();
    for (final chunk in BridgepadProtocol.asciiChunks(text)) {
      await _sendReliable(BridgepadOpcode.textAscii, chunk);
    }
  }

  Future<void> sendKey(int hidUsage) async {
    _requireArmed();
    final payload = _keyPayload(hidUsage);
    await _sendReliable(BridgepadOpcode.keyDown, payload);
    await _sendReliable(BridgepadOpcode.keyUp, payload);
  }

  Future<void> keyDown(int hidUsage) async {
    _requireArmed();
    await _sendReliable(BridgepadOpcode.keyDown, _keyPayload(hidUsage));
  }

  Future<void> keyUp(int hidUsage) async {
    await _sendReliable(BridgepadOpcode.keyUp, _keyPayload(hidUsage));
  }

  Future<void> pointerMove(int dx, int dy) => _sendInput(
    BridgepadOpcode.pointerMove,
    Uint8List.fromList([_signedByte(dx, allowZero: true), _signedByte(dy, allowZero: true)]),
  );

  Future<void> pointerButton(int mask, bool pressed) => _sendInput(
    BridgepadOpcode.pointerButton,
    Uint8List.fromList([mask, pressed ? 1 : 0]),
  );

  Future<void> scroll(int amount) => _sendInput(
    BridgepadOpcode.scroll,
    Uint8List.fromList([_signedByte(amount)]),
  );

  Future<void> emergencyRelease() async {
    if (connectionState == BridgepadConnectionState.ready) {
      await _sendReliable(BridgepadOpcode.releaseAll);
    }
  }

  Future<void> _sendInput(
    BridgepadOpcode opcode,
    Uint8List payload, {
    bool withResponse = true,
  }) async {
    _requireArmed();
    if (withResponse) {
      await _sendReliable(opcode, payload);
    } else {
      final sequence = _takeSequence();
      await _transport.write(
        BridgepadProtocol.encode(
          opcode: opcode,
          sequence: sequence,
          payload: payload,
        ),
        withResponse: false,
      );
    }
  }

  Future<BridgepadStatus> _sendReliable(
    BridgepadOpcode opcode, [
    Uint8List? payload,
  ]) async {
    final sequence = _takeSequence();
    final completer = Completer<BridgepadStatus>();
    final timer = Timer(commandTimeout, () {
      _pending.remove(sequence);
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('BridgePad did not acknowledge the command'),
        );
      }
    });
    _pending[sequence] = _PendingCommand(completer, timer);
    try {
      await _transport.write(
        BridgepadProtocol.encode(
          opcode: opcode,
          sequence: sequence,
          payload: payload,
        ),
      );
      return await completer.future;
    } catch (error) {
      final pending = _pending.remove(sequence);
      pending?.timer.cancel();
      rethrow;
    }
  }

  Future<void> _negotiateHello() async {
    for (var attempt = 0; attempt < helloAttempts; attempt++) {
      try {
        await _sendReliable(BridgepadOpcode.hello);
        return;
      } on TimeoutException {
        if (attempt + 1 >= helloAttempts) rethrow;
      }
    }
  }

  void _handleMessage(Uint8List bytes) {
    try {
      final frame = BridgepadProtocol.decode(bytes);
      if (frame.opcode == BridgepadOpcode.status) {
        deviceStatus = BridgepadDeviceStatus.fromPayload(frame.payload);
        notifyListeners();
        return;
      }
      if (frame.opcode != BridgepadOpcode.ack &&
          frame.opcode != BridgepadOpcode.error) {
        return;
      }
      if (frame.payload.length != 3) {
        throw const ProtocolException('ACK/ERROR payload must be three bytes');
      }
      final acknowledgedSequence = frame.payload[0] | frame.payload[1] << 8;
      final status = BridgepadStatus.fromCode(frame.payload[2]);
      if (status == null) {
        throw ProtocolException('Unknown device status ${frame.payload[2]}');
      }
      final pending = _pending.remove(acknowledgedSequence);
      if (pending == null) return;
      pending.timer.cancel();
      if (frame.opcode == BridgepadOpcode.error) {
        final error = DeviceRejectedException(status);
        lastError = _friendlyError(error);
        pending.completer.completeError(error);
        notifyListeners();
      } else {
        pending.completer.complete(status);
      }
    } catch (error) {
      _handleTransportError(error);
    }
  }

  void _handleConnectionChange(bool connected) {
    if (!connected) _resetDisconnected();
  }

  void _handleTransportError(Object error) {
    lastError = _friendlyError(error);
    notifyListeners();
  }

  void _resetDisconnected() {
    _heartbeat?.cancel();
    _heartbeat = null;
    connectionState = BridgepadConnectionState.disconnected;
    deviceStatus = BridgepadDeviceStatus.disconnected;
    for (final pending in _pending.values) {
      pending.timer.cancel();
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          const ProtocolException('BridgePad disconnected'),
        );
      }
    }
    _pending.clear();
    if (!_disposed) notifyListeners();
  }

  Future<void> _sendHeartbeat() async {
    if (connectionState != BridgepadConnectionState.ready) return;
    try {
      await _sendReliable(BridgepadOpcode.ping);
    } catch (error) {
      _handleTransportError(error);
    }
  }

  void _requireArmed() {
    if (!canSend) {
      throw const DeviceRejectedException(BridgepadStatus.notArmed);
    }
  }

  int _takeSequence() {
    final result = _nextSequence;
    _nextSequence = _nextSequence == 0xffff ? 1 : _nextSequence + 1;
    return result;
  }

  static Uint8List _keyPayload(int usage) {
    if (usage <= 0 || usage > 0xffff) {
      throw const ProtocolException('HID usage must be between 1 and 65535');
    }
    return Uint8List.fromList([usage & 0xff, usage >> 8]);
  }

  static int _signedByte(int value, {bool allowZero = false}) {
    if (value < -127 || value > 127 || (!allowZero && value == 0)) {
      throw const ProtocolException('Relative input must fit in a signed byte');
    }
    return value & 0xff;
  }

  static String _friendlyError(Object error) {
    if (error is DeviceRejectedException) {
      return switch (error.status) {
        BridgepadStatus.notArmed => 'BridgePad is not armed. Press OK on the Flipper.',
        BridgepadStatus.usbUnavailable => 'Connect the Flipper USB cable to the host.',
        BridgepadStatus.invalidPayload => 'The device rejected an invalid command.',
        BridgepadStatus.unsupported => 'This command is not supported by the device.',
        BridgepadStatus.duplicate => 'The device already received this command.',
        BridgepadStatus.ok => 'The device returned an unexpected error.',
      };
    }
    return error.toString();
  }

  @override
  void dispose() {
    _disposed = true;
    _heartbeat?.cancel();
    for (final pending in _pending.values) {
      pending.timer.cancel();
    }
    _pending.clear();
    _messageSubscription?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }
}
