import 'dart:async';
import 'dart:typed_data';

import 'protocol.dart';
import 'transport.dart';

class DemoBridgepadTransport implements BridgepadTransport {
  final _messages = StreamController<Uint8List>.broadcast(sync: true);
  final _connections = StreamController<bool>.broadcast(sync: true);

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
}
