import 'dart:typed_data';

abstract interface class BridgepadTransport {
  Stream<Uint8List> get messages;
  Stream<bool> get connectionChanges;

  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Future<void> write(Uint8List value, {bool withResponse = true});
}
