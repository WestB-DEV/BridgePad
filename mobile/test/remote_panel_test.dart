import 'dart:async';

import 'package:bridgepad/src/bridgepad_home.dart';
import 'package:bridgepad/src/protocol.dart';
import 'package:bridgepad/src/session_controller.dart';
import 'package:bridgepad/src/transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingTransport implements BridgepadTransport {
  final _messages = StreamController<Uint8List>.broadcast(sync: true);
  final _connections = StreamController<bool>.broadcast(sync: true);
  final writes = <BridgepadFrame>[];

  @override
  Stream<bool> get connectionChanges => _connections.stream;

  @override
  Stream<Uint8List> get messages => _messages.stream;

  @override
  Future<void> connect(String deviceId) async => _connections.add(true);

  @override
  Future<void> disconnect() async => _connections.add(false);

  @override
  Future<void> write(Uint8List value, {bool withResponse = true}) async {
    final frame = BridgepadProtocol.decode(value);
    writes.add(frame);
    if (frame.opcode == BridgepadOpcode.hello) {
      _messages.add(
        BridgepadProtocol.encode(
          opcode: BridgepadOpcode.status,
          sequence: frame.sequence,
          payload: Uint8List.fromList([0x07, 1, 220, 0]),
        ),
      );
    }
    _messages.add(
      BridgepadProtocol.encode(
        opcode: BridgepadOpcode.ack,
        sequence: frame.sequence,
        payload: Uint8List.fromList([
          frame.sequence & 0xff,
          frame.sequence >> 8,
          BridgepadStatus.ok.code,
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
  testWidgets('Android keyboard Enter sends HID Enter and stays multiline', (
    tester,
  ) async {
    final transport = RecordingTransport();
    final session = BridgepadSessionController(transport);
    addTearDown(() async {
      session.dispose();
      await transport.close();
    });
    await session.connect('test-device');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BridgepadRemotePanel(session: session)),
      ),
    );

    final liveField = tester.widget<TextField>(
      find.byKey(const Key('live-typing')),
    );
    expect(liveField.keyboardType, TextInputType.multiline);
    expect(liveField.textInputAction, TextInputAction.newline);

    liveField.onChanged!.call('A\nB');
    await tester.pumpAndSettle();

    final inputFrames = transport.writes
        .where((frame) => frame.opcode != BridgepadOpcode.hello)
        .toList();
    expect(inputFrames.map((frame) => frame.opcode), [
      BridgepadOpcode.textAscii,
      BridgepadOpcode.keyDown,
      BridgepadOpcode.keyUp,
      BridgepadOpcode.textAscii,
    ]);
    expect(inputFrames[1].payload, [0x28, 0x00]);
    expect(inputFrames[2].payload, [0x28, 0x00]);
    await session.disconnect();
  });
}
