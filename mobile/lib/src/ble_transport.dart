import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'transport.dart';

abstract final class BridgepadBleUuids {
  static final service = Uuid.parse('8fe5b3d5-2e7f-4a98-2a48-7acc60fe0000');
  static final rx = Uuid.parse('19ed82ae-ed21-4c9d-4145-228e62fe0000');
  static final tx = Uuid.parse('19ed82ae-ed21-4c9d-4145-228e61fe0000');
  static final flow = Uuid.parse('19ed82ae-ed21-4c9d-4145-228e63fe0000');
}

class BridgepadBleDevice {
  const BridgepadBleDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  final String id;
  final String name;
  final int rssi;
}

class BridgepadBleTransport implements BridgepadTransport {
  BridgepadBleTransport([FlutterReactiveBle? ble])
    : _ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle _ble;
  final _messages = StreamController<Uint8List>.broadcast();
  final _connections = StreamController<bool>.broadcast();
  StreamSubscription<ConnectionStateUpdate>? _connection;
  StreamSubscription<List<int>>? _notifications;
  QualifiedCharacteristic? _rx;

  @override
  Stream<Uint8List> get messages => _messages.stream;

  @override
  Stream<bool> get connectionChanges => _connections.stream;

  Stream<BridgepadBleDevice> scan() => _ble
      .scanForDevices(
        withServices: [BridgepadBleUuids.service],
        scanMode: ScanMode.lowLatency,
        requireLocationServicesEnabled: false,
      )
      .map(
        (device) => BridgepadBleDevice(
          id: device.id,
          name: device.name.isEmpty ? 'BridgePad / Flipper Zero' : device.name,
          rssi: device.rssi,
        ),
      );

  @override
  Future<void> connect(String deviceId) async {
    await disconnect();
    final connected = Completer<void>();
    _connection = _ble
        .connectToDevice(
          id: deviceId,
          servicesWithCharacteristicsToDiscover: {
            BridgepadBleUuids.service: [
              BridgepadBleUuids.rx,
              BridgepadBleUuids.tx,
              BridgepadBleUuids.flow,
            ],
          },
          connectionTimeout: const Duration(seconds: 12),
        )
        .listen(
          (update) async {
            switch (update.connectionState) {
              case DeviceConnectionState.connected:
                _rx = QualifiedCharacteristic(
                  serviceId: BridgepadBleUuids.service,
                  characteristicId: BridgepadBleUuids.rx,
                  deviceId: deviceId,
                );
                final tx = QualifiedCharacteristic(
                  serviceId: BridgepadBleUuids.service,
                  characteristicId: BridgepadBleUuids.tx,
                  deviceId: deviceId,
                );
                _notifications = _ble.subscribeToCharacteristic(tx).listen(
                  (value) => _messages.add(Uint8List.fromList(value)),
                  onError: _messages.addError,
                );
                _connections.add(true);
                if (!connected.isCompleted) connected.complete();
              case DeviceConnectionState.disconnected:
                _rx = null;
                _connections.add(false);
                if (!connected.isCompleted) {
                  connected.completeError(
                    update.failure ?? Exception('BLE connection failed'),
                  );
                }
              case DeviceConnectionState.connecting:
              case DeviceConnectionState.disconnecting:
                break;
            }
          },
          onError: (Object error) {
            _connections.addError(error);
            if (!connected.isCompleted) connected.completeError(error);
          },
        );
    await connected.future;
  }

  @override
  Future<void> write(Uint8List value, {bool withResponse = true}) async {
    final characteristic = _rx;
    if (characteristic == null) throw StateError('BridgePad is not connected');
    if (withResponse) {
      await _ble.writeCharacteristicWithResponse(
        characteristic,
        value: value,
      );
    } else {
      await _ble.writeCharacteristicWithoutResponse(
        characteristic,
        value: value,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    _rx = null;
    await _notifications?.cancel();
    _notifications = null;
    await _connection?.cancel();
    _connection = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
    await _connections.close();
  }
}
