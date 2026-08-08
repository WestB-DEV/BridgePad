import 'dart:async';

import 'package:bridgepad/src/ble_transport.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBleClient implements BridgepadBleClient {
  final operations = <String>[];
  final notifications = StreamController<List<int>>.broadcast();
  int negotiatedMtu = BridgepadBleTransport.preferredMtu;

  @override
  Stream<ConnectionStateUpdate> connectToDevice({
    required String id,
    required Map<Uuid, List<Uuid>> servicesWithCharacteristicsToDiscover,
    required Duration connectionTimeout,
  }) => Stream.value(
    ConnectionStateUpdate(
      deviceId: id,
      connectionState: DeviceConnectionState.connected,
      failure: null,
    ),
  );

  @override
  Future<int> requestMtu({required String deviceId, required int mtu}) async {
    operations.add('mtu');
    return negotiatedMtu;
  }

  @override
  Stream<List<int>> subscribeToCharacteristic(
    QualifiedCharacteristic characteristic,
  ) {
    operations.add('subscribe');
    return notifications.stream;
  }

  @override
  Stream<DiscoveredDevice> scanForDevices({
    required List<Uuid> withServices,
    required ScanMode scanMode,
    required bool requireLocationServicesEnabled,
  }) => const Stream.empty();

  @override
  Future<void> writeCharacteristicWithResponse(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
  }) async {}

  @override
  Future<void> writeCharacteristicWithoutResponse(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
  }) async {}

  Future<void> close() => notifications.close();
}

void main() {
  late FakeBleClient client;
  late BridgepadBleTransport transport;

  setUp(() {
    client = FakeBleClient();
    transport = BridgepadBleTransport(
      client: client,
      negotiateMtu: true,
      notificationSettleDelay: Duration.zero,
    );
  });

  tearDown(() async {
    await transport.dispose();
    await client.close();
  });

  test(
    'prepares Android MTU and notifications before reporting connected',
    () async {
      final connectionStates = <bool>[];
      final subscription = transport.connectionChanges.listen(
        connectionStates.add,
      );

      await transport.connect('device-1');

      expect(client.operations, ['mtu', 'subscribe']);
      expect(connectionStates, [true]);
      await subscription.cancel();
    },
  );

  test('rejects an MTU that cannot carry a complete protocol frame', () async {
    client.negotiatedMtu = BridgepadBleTransport.minimumMtu - 1;

    await expectLater(
      transport.connect('device-1'),
      throwsA(isA<StateError>()),
    );
  });
}
