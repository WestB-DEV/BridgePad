import 'dart:typed_data';

import 'package:bridgepad/src/protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BridgepadProtocol', () {
    test('encodes and decodes the shared ACK golden vector', () {
      final bytes = BridgepadProtocol.encode(
        opcode: BridgepadOpcode.ack,
        sequence: 9,
        payload: Uint8List.fromList([0x34, 0x12, BridgepadStatus.ok.code]),
      );

      expect(
        bytes,
        Uint8List.fromList([1, 0x81, 9, 0, 3, 0, 0x34, 0x12, 0]),
      );
      final decoded = BridgepadProtocol.decode(bytes);
      expect(decoded.opcode, BridgepadOpcode.ack);
      expect(decoded.sequence, 9);
      expect(decoded.payload, [0x34, 0x12, 0]);
    });

    test('rejects truncated and length-mismatched frames', () {
      expect(
        () => BridgepadProtocol.decode(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<ProtocolException>()),
      );
      expect(
        () => BridgepadProtocol.decode(
          Uint8List.fromList([1, BridgepadOpcode.ping.code, 1, 0, 2, 0, 9]),
        ),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('rejects unsupported versions and opcodes', () {
      expect(
        () => BridgepadProtocol.decode(Uint8List.fromList([2, 2, 1, 0, 0, 0])),
        throwsA(isA<ProtocolException>()),
      );
      expect(
        () => BridgepadProtocol.decode(Uint8List.fromList([1, 0x7f, 1, 0, 0, 0])),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('splits supported ASCII into 220-byte chunks', () {
      final chunks = BridgepadProtocol.asciiChunks(List.filled(441, 'a').join());

      expect(chunks.map((chunk) => chunk.length), [220, 220, 1]);
    });

    test('rejects control characters and non-ASCII clipboard text', () {
      expect(
        () => BridgepadProtocol.asciiChunks('line\nbreak'),
        throwsA(isA<UnsupportedTextException>()),
      );
      expect(
        () => BridgepadProtocol.asciiChunks('café'),
        throwsA(isA<UnsupportedTextException>()),
      );
    });

    test('parses status flags and negotiated payload limit', () {
      final status = BridgepadDeviceStatus.fromPayload(
        Uint8List.fromList([0x07, 1, 220, 0]),
      );

      expect(status.isBleConnected, isTrue);
      expect(status.isUsbConnected, isTrue);
      expect(status.isArmed, isTrue);
      expect(status.protocolVersion, 1);
      expect(status.maxPayload, 220);
    });
  });
}
