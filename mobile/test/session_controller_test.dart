import 'dart:async';
import 'dart:typed_data';

import 'package:bridgepad/src/protocol.dart';
import 'package:bridgepad/src/session_controller.dart';
import 'package:bridgepad/src/transport.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTransport implements BridgepadTransport {
  final _messages = StreamController<Uint8List>.broadcast(sync: true);
  final _connections = StreamController<bool>.broadcast(sync: true);
  final writes = <BridgepadFrame>[];
  bool autoAck = true;
  int helloResponsesToDrop = 0;

  @override
  Stream<bool> get connectionChanges => _connections.stream;

  @override
  Stream<Uint8List> get messages => _messages.stream;

  @override
  Future<void> connect(String deviceId) async {
    _connections.add(true);
  }

  @override
  Future<void> disconnect() async {
    _connections.add(false);
  }

  @override
  Future<void> write(Uint8List value, {bool withResponse = true}) async {
    final frame = BridgepadProtocol.decode(value);
    writes.add(frame);
    if (frame.opcode == BridgepadOpcode.hello) {
      if (helloResponsesToDrop > 0) {
        helloResponsesToDrop--;
        return;
      }
      emitStatus(ble: true, usb: true, armed: true, sequence: frame.sequence);
    }
    if (autoAck) emitResult(BridgepadOpcode.ack, frame.sequence, BridgepadStatus.ok);
  }

  void emitStatus({
    required bool ble,
    required bool usb,
    required bool armed,
    int sequence = 0,
  }) {
    var flags = 0;
    if (ble) flags |= 1;
    if (usb) flags |= 2;
    if (armed) flags |= 4;
    _messages.add(
      BridgepadProtocol.encode(
        opcode: BridgepadOpcode.status,
        sequence: sequence,
        payload: Uint8List.fromList([flags, 1, 220, 0]),
      ),
    );
  }

  void emitResult(
    BridgepadOpcode opcode,
    int sequence,
    BridgepadStatus status,
  ) {
    _messages.add(
      BridgepadProtocol.encode(
        opcode: opcode,
        sequence: sequence,
        payload: Uint8List.fromList([
          sequence & 0xff,
          sequence >> 8,
          status.code,
        ]),
      ),
    );
  }

  Future<void> close() async {
    await _messages.close();
    await _connections.close();
  }
}

void main() {
  late FakeTransport transport;
  late BridgepadSessionController controller;

  setUp(() {
    transport = FakeTransport();
    controller = BridgepadSessionController(
      transport,
      heartbeatInterval: const Duration(days: 1),
    );
  });

  tearDown(() async {
    controller.dispose();
    await transport.close();
  });

  test('HELLO negotiates status and records armed state', () async {
    await controller.connect('device-1');

    expect(transport.writes.single.opcode, BridgepadOpcode.hello);
    expect(controller.connectionState, BridgepadConnectionState.ready);
    expect(controller.deviceStatus.isUsbConnected, isTrue);
    expect(controller.deviceStatus.isArmed, isTrue);
  });

  test('HELLO retries when the first notification response is lost', () async {
    controller.dispose();
    transport.helloResponsesToDrop = 1;
    controller = BridgepadSessionController(
      transport,
      heartbeatInterval: const Duration(days: 1),
      commandTimeout: const Duration(milliseconds: 5),
      helloAttempts: 2,
    );

    await controller.connect('device-1');

    expect(
      transport.writes.where((frame) => frame.opcode == BridgepadOpcode.hello),
      hasLength(2),
    );
    expect(controller.connectionState, BridgepadConnectionState.ready);
  });

  test('text is sent sequentially in acknowledged protocol chunks', () async {
    await controller.connect('device-1');
    transport.writes.clear();

    await controller.sendText(List.filled(441, 'x').join());

    final textFrames = transport.writes
        .where((frame) => frame.opcode == BridgepadOpcode.textAscii)
        .toList();
    expect(textFrames.map((frame) => frame.payload.length), [220, 220, 1]);
    expect(textFrames.map((frame) => frame.sequence).toSet().length, 3);
  });

  test('structured device error becomes an actionable exception', () async {
    await controller.connect('device-1');
    transport.autoAck = false;

    final sending = controller.sendKey(0x28);
    final frame = transport.writes.last;
    transport.emitResult(
      BridgepadOpcode.error,
      frame.sequence,
      BridgepadStatus.notArmed,
    );

    await expectLater(sending, throwsA(isA<DeviceRejectedException>()));
    expect(controller.lastError, contains('not armed'));
  });

  test('disconnect resets device state and clears pending input state', () async {
    await controller.connect('device-1');
    transport.emitStatus(ble: false, usb: false, armed: false);
    await transport.disconnect();
    await Future<void>.delayed(Duration.zero);

    expect(controller.connectionState, BridgepadConnectionState.disconnected);
    expect(controller.deviceStatus.isArmed, isFalse);
  });
}
