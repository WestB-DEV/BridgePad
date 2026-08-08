import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
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

abstract interface class BridgepadBleClient {
  Stream<DiscoveredDevice> scanForDevices({
    required List<Uuid> withServices,
    required ScanMode scanMode,
    required bool requireLocationServicesEnabled,
  });

  Stream<ConnectionStateUpdate> connectToDevice({
    required String id,
    required Map<Uuid, List<Uuid>> servicesWithCharacteristicsToDiscover,
    required Duration connectionTimeout,
  });

  Stream<List<int>> subscribeToCharacteristic(
    QualifiedCharacteristic characteristic,
  );

  Future<int> requestMtu({required String deviceId, required int mtu});

  Future<void> writeCharacteristicWithResponse(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
  });

  Future<void> writeCharacteristicWithoutResponse(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
  });
}

class FlutterReactiveBleClient implements BridgepadBleClient {
  FlutterReactiveBleClient([FlutterReactiveBle? ble])
    : _ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle _ble;

  @override
  Stream<DiscoveredDevice> scanForDevices({
    required List<Uuid> withServices,
    required ScanMode scanMode,
    required bool requireLocationServicesEnabled,
  }) => _ble.scanForDevices(
    withServices: withServices,
    scanMode: scanMode,
    requireLocationServicesEnabled: requireLocationServicesEnabled,
  );

  @override
  Stream<ConnectionStateUpdate> connectToDevice({
    required String id,
    required Map<Uuid, List<Uuid>> servicesWithCharacteristicsToDiscover,
    required Duration connectionTimeout,
  }) => _ble.connectToDevice(
    id: id,
    servicesWithCharacteristicsToDiscover:
        servicesWithCharacteristicsToDiscover,
    connectionTimeout: connectionTimeout,
  );

  @override
  Stream<List<int>> subscribeToCharacteristic(
    QualifiedCharacteristic characteristic,
  ) => _ble.subscribeToCharacteristic(characteristic);

  @override
  Future<int> requestMtu({required String deviceId, required int mtu}) =>
      _ble.requestMtu(deviceId: deviceId, mtu: mtu);

  @override
  Future<void> writeCharacteristicWithResponse(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
  }) => _ble.writeCharacteristicWithResponse(characteristic, value: value);

  @override
  Future<void> writeCharacteristicWithoutResponse(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
  }) => _ble.writeCharacteristicWithoutResponse(characteristic, value: value);
}

class BridgepadBleTransport implements BridgepadTransport {
  BridgepadBleTransport({
    BridgepadBleClient? client,
    bool? negotiateMtu,
    this.notificationSettleDelay = const Duration(milliseconds: 150),
  }) : _client = client ?? FlutterReactiveBleClient(),
       _negotiateMtu =
           negotiateMtu ?? defaultTargetPlatform == TargetPlatform.android;

  static const preferredMtu = 247;
  static const minimumMtu = 229;

  final BridgepadBleClient _client;
  final bool _negotiateMtu;
  final Duration notificationSettleDelay;
  final _messages = StreamController<Uint8List>.broadcast();
  final _connections = StreamController<bool>.broadcast();
  StreamSubscription<ConnectionStateUpdate>? _connection;
  StreamSubscription<List<int>>? _notifications;
  QualifiedCharacteristic? _rx;

  @override
  Stream<Uint8List> get messages => _messages.stream;

  @override
  Stream<bool> get connectionChanges => _connections.stream;

  Stream<BridgepadBleDevice> scan() => _client
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
    var preparingConnection = false;
    _connection = _client
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
          (update) {
            switch (update.connectionState) {
              case DeviceConnectionState.connected:
                if (preparingConnection) return;
                preparingConnection = true;
                unawaited(
                  _prepareConnectedLink(deviceId)
                      .then((_) {
                        _connections.add(true);
                        if (!connected.isCompleted) connected.complete();
                      })
                      .catchError((Object error) {
                        _rx = null;
                        if (!connected.isCompleted) {
                          connected.completeError(error);
                        }
                      }),
                );
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

  Future<void> _prepareConnectedLink(String deviceId) async {
    if (_negotiateMtu) {
      final mtu = await _client.requestMtu(
        deviceId: deviceId,
        mtu: preferredMtu,
      );
      if (mtu < minimumMtu) {
        throw StateError(
          'BridgePad needs BLE MTU $minimumMtu or larger; Android negotiated $mtu',
        );
      }
    }
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
    _notifications = _client
        .subscribeToCharacteristic(tx)
        .listen(
          (value) => _messages.add(Uint8List.fromList(value)),
          onError: _messages.addError,
        );
    await Future<void>.delayed(notificationSettleDelay);
  }

  @override
  Future<void> write(Uint8List value, {bool withResponse = true}) async {
    final characteristic = _rx;
    if (characteristic == null) throw StateError('BridgePad is not connected');
    if (withResponse) {
      await _client.writeCharacteristicWithResponse(
        characteristic,
        value: value,
      );
    } else {
      await _client.writeCharacteristicWithoutResponse(
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
