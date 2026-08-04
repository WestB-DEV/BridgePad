import 'dart:typed_data';

enum BridgepadOpcode {
  hello(0x01),
  ping(0x02),
  releaseAll(0x03),
  textAscii(0x10),
  keyDown(0x11),
  keyUp(0x12),
  pointerMove(0x20),
  pointerButton(0x21),
  scroll(0x22),
  status(0x80),
  ack(0x81),
  error(0x82);

  const BridgepadOpcode(this.code);
  final int code;

  static BridgepadOpcode? fromCode(int code) {
    for (final opcode in values) {
      if (opcode.code == code) return opcode;
    }
    return null;
  }
}

enum BridgepadStatus {
  ok(0),
  notArmed(1),
  invalidPayload(2),
  unsupported(3),
  duplicate(4),
  usbUnavailable(5);

  const BridgepadStatus(this.code);
  final int code;

  static BridgepadStatus? fromCode(int code) {
    for (final status in values) {
      if (status.code == code) return status;
    }
    return null;
  }
}

class ProtocolException implements Exception {
  const ProtocolException(this.message);
  final String message;

  @override
  String toString() => 'ProtocolException: $message';
}

class UnsupportedTextException extends ProtocolException {
  const UnsupportedTextException(super.message);
}

class BridgepadFrame {
  const BridgepadFrame({
    required this.opcode,
    required this.sequence,
    required this.payload,
  });

  final BridgepadOpcode opcode;
  final int sequence;
  final Uint8List payload;
}

class BridgepadDeviceStatus {
  const BridgepadDeviceStatus({
    required this.isBleConnected,
    required this.isUsbConnected,
    required this.isArmed,
    required this.protocolVersion,
    required this.maxPayload,
  });

  factory BridgepadDeviceStatus.fromPayload(Uint8List payload) {
    if (payload.length != 4) {
      throw const ProtocolException('Status payload must be four bytes');
    }
    final flags = payload[0];
    return BridgepadDeviceStatus(
      isBleConnected: flags & 0x01 != 0,
      isUsbConnected: flags & 0x02 != 0,
      isArmed: flags & 0x04 != 0,
      protocolVersion: payload[1],
      maxPayload: payload[2] | payload[3] << 8,
    );
  }

  static const disconnected = BridgepadDeviceStatus(
    isBleConnected: false,
    isUsbConnected: false,
    isArmed: false,
    protocolVersion: BridgepadProtocol.version,
    maxPayload: BridgepadProtocol.maxPayload,
  );

  final bool isBleConnected;
  final bool isUsbConnected;
  final bool isArmed;
  final int protocolVersion;
  final int maxPayload;
}

abstract final class BridgepadProtocol {
  static const version = 1;
  static const headerSize = 6;
  static const maxPayload = 220;
  static const maxTextBytes = 4096;

  static Uint8List encode({
    required BridgepadOpcode opcode,
    required int sequence,
    Uint8List? payload,
  }) {
    final data = payload ?? Uint8List(0);
    if (sequence < 0 || sequence > 0xffff) {
      throw const ProtocolException('Sequence must fit in 16 bits');
    }
    if (data.length > maxPayload) {
      throw const ProtocolException('Payload exceeds 220 bytes');
    }
    final output = Uint8List(headerSize + data.length);
    output[0] = version;
    output[1] = opcode.code;
    output[2] = sequence & 0xff;
    output[3] = sequence >> 8;
    output[4] = data.length & 0xff;
    output[5] = data.length >> 8;
    output.setRange(headerSize, output.length, data);
    return output;
  }

  static BridgepadFrame decode(Uint8List bytes) {
    if (bytes.length < headerSize) {
      throw const ProtocolException('Frame is shorter than its header');
    }
    if (bytes[0] != version) {
      throw ProtocolException('Unsupported protocol version ${bytes[0]}');
    }
    final opcode = BridgepadOpcode.fromCode(bytes[1]);
    if (opcode == null) {
      throw ProtocolException('Unknown opcode 0x${bytes[1].toRadixString(16)}');
    }
    final sequence = bytes[2] | bytes[3] << 8;
    final payloadLength = bytes[4] | bytes[5] << 8;
    if (payloadLength > maxPayload) {
      throw const ProtocolException('Payload exceeds 220 bytes');
    }
    if (bytes.length != headerSize + payloadLength) {
      throw const ProtocolException('Frame length does not match its header');
    }
    return BridgepadFrame(
      opcode: opcode,
      sequence: sequence,
      payload: Uint8List.fromList(bytes.sublist(headerSize)),
    );
  }

  static List<Uint8List> asciiChunks(String text) {
    final codeUnits = text.codeUnits;
    if (codeUnits.length > maxTextBytes) {
      throw const UnsupportedTextException('Text is limited to 4,096 characters');
    }
    for (final codeUnit in codeUnits) {
      if (codeUnit < 0x20 || codeUnit > 0x7e) {
        throw const UnsupportedTextException(
          'BridgePad v1 supports printable US-QWERTY ASCII only',
        );
      }
    }
    final chunks = <Uint8List>[];
    for (var offset = 0; offset < codeUnits.length; offset += maxPayload) {
      final end = (offset + maxPayload).clamp(0, codeUnits.length);
      chunks.add(Uint8List.fromList(codeUnits.sublist(offset, end)));
    }
    return chunks;
  }
}
