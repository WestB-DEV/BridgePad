import 'dart:async';

import 'package:bridgepad/src/ble_transport.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeBleClient implements BridgepadBleClient {
  final operations = <String>[];
  final notifications = StreamController<List<int>>.broadcast();
  List<Uuid>? scannedServices;
  int negotiatedMtu = BridgepadBleTransport.preferredMtu;
  Completer<int>? pendingMtu;
  StreamController<ConnectionStateUpdate>? connectionUpdates;

  @override
  Stream<ConnectionStateUpdate> connectToDevice({
    required String id,
    required Map<Uuid, List<Uuid>> servicesWithCharacteristicsToDiscover,
    required Duration connectionTimeout,
  }) => connectionUpdates?.stream ??
      Stream.value(
        ConnectionStateUpdate(
          deviceId: id,
          connectionState: DeviceConnectionState.connected,
          failure: null,
        ),
      );

  @override
  Future<int> requestMtu({required String deviceId, required int mtu}) async {
    operations.add('mtu');
    if (pendingMtu case final pending?) return pending.future;
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
  }) {
    scannedServices = withServices;
    return const Stream.empty();
  }

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

  Future<void> close() async {
    await connectionUpdates?.close();
    await notifications.close();
  }
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
    'scans for Flipper serial advertisements, not its GATT service',
    () async {
      await transport.scan().drain<void>();

      expect(client.scannedServices, [
        Uuid.parse('00003080-0000-1000-8000-00805f9b34fb'),
        Uuid.parse('00003081-0000-1000-8000-00805f9b34fb'),
        Uuid.parse('00003082-0000-1000-8000-00805f9b34fb'),
        Uuid.parse('00003083-0000-1000-8000-00805f9b34fb'),
      ]);
      expect(
        client.scannedServices,
        isNot(contains(BridgepadBleUuids.service)),
      );
    },
  );

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

  test('disconnect during MTU setup cannot report a stale connected state', () async {
    client.pendingMtu = Completer<int>();
    final connectionStates = <bool>[];
    final subscription = transport.connectionChanges.listen(
      connectionStates.add,
    );

    final connecting = transport.connect('device-1');
    final connectionResult = expectLater(connecting, throwsA(isA<StateError>()));
    await Future<void>.delayed(Duration.zero);
    await transport.disconnect();
    client.pendingMtu!.complete(BridgepadBleTransport.preferredMtu);

    await connectionResult;
    expect(connectionStates, isNot(contains(true)));
    await subscription.cancel();
  }, timeout: const Timeout(Duration(seconds: 2)));

  test('remote disconnect invalidates MTU setup still in flight', () async {
    client.pendingMtu = Completer<int>();
    client.connectionUpdates = StreamController<ConnectionStateUpdate>.broadcast(
      sync: true,
    );
    final connectionStates = <bool>[];
    final subscription = transport.connectionChanges.listen(
      connectionStates.add,
    );

    final connecting = transport.connect('device-1');
    final connectionResult = expectLater(connecting, throwsA(isA<Exception>()));
    await Future<void>.delayed(Duration.zero);
    client.connectionUpdates!.add(
      const ConnectionStateUpdate(
        deviceId: 'device-1',
        connectionState: DeviceConnectionState.connected,
        failure: null,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    client.connectionUpdates!.add(
      const ConnectionStateUpdate(
        deviceId: 'device-1',
        connectionState: DeviceConnectionState.disconnected,
        failure: null,
      ),
    );
    client.pendingMtu!.complete(BridgepadBleTransport.preferredMtu);

    await connectionResult;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(connectionStates, [false]);
    await subscription.cancel();
  }, timeout: const Timeout(Duration(seconds: 2)));
}
