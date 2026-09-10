import 'dart:async';
import 'dart:typed_data';

import 'protocol.dart';
import 'transport.dart';

class DemoBridgepadTransport implements BridgepadTransport {
  // Bounded protocol-only trace for tests; never records typed text in the UI/logs.
  final opcodeCounts = <BridgepadOpcode, int>{};
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
  Future<void> write(Uint8List value) async {
    final frame = BridgepadProtocol.decode(value);
    opcodeCounts.update(frame.opcode, (count) => count + 1, ifAbsent: () => 1);
    if (frame.opcode == BridgepadOpcode.hello) {
      _messages.add(
        BridgepadProtocol.encode(
          opcode: BridgepadOpcode.status,
          sequence: frame.sequence,
          payload: Uint8List.fromList([0x07, 1, 220, 0]),
        ),
      );
    }
    if (frame.opcode == BridgepadOpcode.releaseAll) {
      _messages.add(
        BridgepadProtocol.encode(
          opcode: BridgepadOpcode.status,
          sequence: frame.sequence,
          payload: Uint8List.fromList([0x03, 1, 220, 0]),
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
