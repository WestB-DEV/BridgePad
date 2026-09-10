import 'dart:async';

import 'package:flutter/foundation.dart';

import 'protocol.dart';
import 'keyboard_input.dart';
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
  Future<void> _inputTail = Future<void>.value();
  int _inputGeneration = 0;
  int _queuedInputs = 0;
  bool _releasing = false;
  bool _recoveringLink = false;
  int get inputRevision => _inputGeneration;

  BridgepadConnectionState connectionState =
      BridgepadConnectionState.disconnected;
  BridgepadDeviceStatus deviceStatus = BridgepadDeviceStatus.disconnected;
  String? lastError;

  bool get canSend =>
      !_disposed &&
      !_releasing &&
      !_recoveringLink &&
      connectionState == BridgepadConnectionState.ready &&
      deviceStatus.isBleConnected &&
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
        await emergencyRelease();
      } catch (_) {
        // The Flipper also releases locally on a BLE disconnect.
      }
    }
    await _transport.disconnect();
    _resetDisconnected();
  }

  static List<List<Uint8List>> validatedTextLines(String text) {
    final normalized = text.replaceAll('\r\n', '\n');
    if (normalized.length > BridgepadProtocol.maxTextBytes) {
      throw const UnsupportedTextException(
        'Text is limited to 4,096 characters',
      );
    }
    // Validate the entire draft before the first irreversible host event.
    return normalized.split('\n').map(BridgepadProtocol.asciiChunks).toList();
  }

  Future<void> sendText(String text) async {
    final lines = validatedTextLines(text);
    await _transaction((write) async {
      for (var i = 0; i < lines.length; i++) {
        if (i > 0) {
          await write(BridgepadOpcode.keyDown, _keyPayload(0x28));
          await write(BridgepadOpcode.keyUp, _keyPayload(0x28));
        }
        for (final chunk in lines[i]) {
          await write(BridgepadOpcode.textAscii, chunk);
        }
      }
    });
  }

  Future<void> sendKey(int hidUsage, {Set<int> modifiers = const {}}) async {
    final payload = _keyPayload(HidKeyboard.chord(hidUsage, modifiers));
    await _transaction((write) async {
      await write(BridgepadOpcode.keyDown, payload);
      await write(BridgepadOpcode.keyUp, payload);
    });
  }

  Future<void> sendLiveEdit(
    int backspaces,
    String text, {
    List<Set<int>> modifiers = const [],
  }) async {
    // Prevalidate committed IME content, including replacements, before deleting.
    BridgepadProtocol.asciiChunks(text.replaceAll('\n', ''));
    if (backspaces < 0 || backspaces + text.length > 4096) {
      throw const UnsupportedTextException(
        'Live edit is limited to 4,096 keys',
      );
    }
    final keys = [
      for (var i = 0; i < backspaces; i++) 0x2a,
      for (final character in text.split('')) HidKeyboard.ascii(character),
    ];
    await _transaction((write) async {
      for (var i = 0; i < keys.length; i++) {
        final payload = _keyPayload(
          HidKeyboard.chord(
            keys[i],
            i < modifiers.length ? modifiers[i] : const {},
          ),
        );
        await write(BridgepadOpcode.keyDown, payload);
        await write(BridgepadOpcode.keyUp, payload);
      }
    });
  }

  Future<void> pointerMove(int dx, int dy) => _sendInput(
    BridgepadOpcode.pointerMove,
    Uint8List.fromList([
      _signedByte(dx, allowZero: true),
      _signedByte(dy, allowZero: true),
    ]),
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
    _invalidateInput();
    if (_releasing) return;
    _releasing = true;
    try {
      if (connectionState == BridgepadConnectionState.ready) {
        // Bypass queued input, including a text command awaiting acknowledgement.
        await _sendReliable(BridgepadOpcode.releaseAll);
      }
    } catch (_) {
      // A failed release cannot leave a usable session with unknown held keys.
      try {
        await _transport.disconnect();
      } finally {
        _resetDisconnected();
      }
      rethrow;
    } finally {
      _releasing = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _invalidateInput() {
    _inputGeneration++;
    deviceStatus = BridgepadDeviceStatus(
      isBleConnected: deviceStatus.isBleConnected,
      isUsbConnected: deviceStatus.isUsbConnected,
      isArmed: false,
      protocolVersion: deviceStatus.protocolVersion,
      maxPayload: deviceStatus.maxPayload,
    );
    if (!_disposed) notifyListeners();
  }

  Future<void> _transaction(
    Future<void> Function(
      Future<void> Function(BridgepadOpcode, [Uint8List?]) write,
    )
    action,
  ) {
    try {
      _requireArmed();
    } catch (error, stack) {
      return Future<void>.error(error, stack);
    }
    if (_queuedInputs >= 128) {
      unawaited(emergencyRelease().catchError((_) {}));
      return Future<void>.error(
        const ProtocolException('Input backlog exceeded; session disarmed'),
      );
    }
    final generation = _inputGeneration;
    _queuedInputs++;
    final result = _inputTail.then((_) async {
      Future<void> write(BridgepadOpcode opcode, [Uint8List? payload]) async {
        if (_disposed || generation != _inputGeneration) {
          throw const ProtocolException('Input cancelled; session changed');
        }
        _requireArmed();
        await _sendReliable(opcode, payload);
      }

      try {
        if (generation != _inputGeneration) {
          throw const ProtocolException('Input cancelled; session changed');
        }
        await action(write);
      } catch (_) {
        if (generation == _inputGeneration && !_disposed) {
          unawaited(emergencyRelease().catchError((_) {}));
        }
        rethrow;
      } finally {
        _queuedInputs--;
      }
    });
    _inputTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<void> _sendInput(BridgepadOpcode opcode, Uint8List payload) async {
    await _transaction((write) => write(opcode, payload));
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
    // Attach the completion listener before a synchronous transport can ACK/error.
    unawaited(
      _transport
          .write(
            BridgepadProtocol.encode(
              opcode: opcode,
              sequence: sequence,
              payload: payload,
            ),
          )
          .catchError((Object error, StackTrace stack) {
            final pending = _pending.remove(sequence);
            pending?.timer.cancel();
            if (pending != null && !pending.completer.isCompleted) {
              pending.completer.completeError(error, stack);
            }
          }),
    );
    return completer.future;
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
        final wasArmed = deviceStatus.isArmed;
        deviceStatus = BridgepadDeviceStatus.fromPayload(frame.payload);
        if (wasArmed &&
            (!deviceStatus.isArmed ||
                !deviceStatus.isUsbConnected ||
                !deviceStatus.isBleConnected)) {
          _invalidateInput();
        }
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
    _heartbeat?.cancel();
    _heartbeat = null;
    if (!_disposed &&
        !_recoveringLink &&
        connectionState == BridgepadConnectionState.ready) {
      _recoveringLink = true;
      unawaited(_closeFaultedLink());
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _closeFaultedLink() async {
    try {
      await emergencyRelease();
    } catch (_) {
      // Release failure already resets the link; firmware has its watchdog too.
    } finally {
      try {
        if (connectionState != BridgepadConnectionState.disconnected) {
          await _transport.disconnect();
        }
      } catch (_) {
        // Still fail closed locally if the platform cannot confirm disconnect.
      } finally {
        _resetDisconnected();
        _recoveringLink = false;
      }
    }
  }

  void _resetDisconnected() {
    _inputGeneration++;
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
        BridgepadStatus.notArmed =>
          'BridgePad is not armed. Press OK on the Flipper.',
        BridgepadStatus.usbUnavailable =>
          'Connect the Flipper USB cable to the host.',
        BridgepadStatus.invalidPayload =>
          'The device rejected an invalid command.',
        BridgepadStatus.unsupported =>
          'This command is not supported by the device.',
        BridgepadStatus.duplicate =>
          'The device already received this command.',
        BridgepadStatus.ok => 'The device returned an unexpected error.',
      };
    }
    return error.toString();
  }

  @override
  void dispose() {
    _disposed = true;
    _inputGeneration++;
    _heartbeat?.cancel();
    for (final pending in _pending.values) {
      pending.timer.cancel();
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          const ProtocolException('Session disposed'),
        );
      }
    }
    _pending.clear();
    _messageSubscription?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }
}
