import 'dart:typed_data';

import 'package:bridgepad/main.dart';
import 'package:bridgepad/src/android_ble_platform.dart';
import 'package:bridgepad/src/ble_transport.dart';
import 'package:bridgepad/src/bridgepad_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';

class SuccessfulAndroidPlatform extends AndroidBlePlatform {
  SuccessfulAndroidPlatform();

  int bondCalls = 0;

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<void> bond(String deviceId) async {
    bondCalls++;
  }
}

class TooSmallMtuBleClient implements BridgepadBleClient {
  int connectCalls = 0;

  @override
  Stream<DiscoveredDevice> scanForDevices({
    required List<Uuid> withServices,
    required ScanMode scanMode,
    required bool requireLocationServicesEnabled,
  }) => Stream.value(
    DiscoveredDevice(
      id: 'device-1',
      name: 'Test Flipper',
      serviceData: const {},
      manufacturerData: Uint8List(0),
      rssi: -42,
      serviceUuids: [BridgepadBleUuids.service],
    ),
  );

  @override
  Stream<ConnectionStateUpdate> connectToDevice({
    required String id,
    required Map<Uuid, List<Uuid>> servicesWithCharacteristicsToDiscover,
    required Duration connectionTimeout,
  }) {
    connectCalls++;
    return Stream.value(
      ConnectionStateUpdate(
        deviceId: id,
        connectionState: DeviceConnectionState.connected,
        failure: null,
      ),
    );
  }

  @override
  Future<int> requestMtu({required String deviceId, required int mtu}) async =>
      BridgepadBleTransport.minimumMtu - 1;

  @override
  Stream<List<int>> subscribeToCharacteristic(
    QualifiedCharacteristic characteristic,
  ) => const Stream.empty();

  @override
  Future<void> writeCharacteristicWithResponse(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
  }) async {}
}

void main() {
  testWidgets('full app fits a compact landscape keyboard viewport', (
    tester,
  ) async {
    await tester.pumpWidget(const BridgepadApp());
    await tester.tap(find.text('Open hardware-free demo'));
    await tester.pumpAndSettle();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(740, 360);
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.byTooltip('Release All + Disarm').hitTestable(),
      findsOneWidget,
    );
    expect(find.byTooltip('Extra keys').hitTestable(), findsOneWidget);
  });

  testWidgets('hardware-free demo opens the armed remote controls', (
    tester,
  ) async {
    await tester.pumpWidget(const BridgepadApp());

    expect(find.text('Find BridgePad'), findsOneWidget);
    expect(find.textContaining('no accounts'), findsOneWidget);

    await tester.tap(find.text('Open hardware-free demo'));
    await tester.pumpAndSettle();

    expect(find.text('TRACKPAD'), findsOneWidget);
    expect(find.byTooltip('Compose and review'), findsOneWidget);
    expect(find.byIcon(Icons.link_off), findsOneWidget);

    expect(find.byType(ListView), findsNothing);
    expect(
      find.byTooltip('Release All + Disarm').hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('failed hardware connection returns to a retryable scan screen', (
    tester,
  ) async {
    final client = TooSmallMtuBleClient();
    final android = SuccessfulAndroidPlatform();
    final transport = BridgepadBleTransport(
      client: client,
      negotiateMtu: true,
      notificationSettleDelay: Duration.zero,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BridgepadHome(bleTransport: transport, androidPlatform: android),
      ),
    );
    expect(
      tester.widget<BridgepadHome>(find.byType(BridgepadHome)).androidPlatform,
      same(android),
    );

    await tester.tap(find.text('Find BridgePad'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Test Flipper'));
    await tester.pumpAndSettle();
    final deviceTile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('Test Flipper'),
        matching: find.byType(ListTile),
      ),
    );
    await tester.runAsync(() async {
      deviceTile.onTap!.call();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Find BridgePad'), findsOneWidget);
    expect(android.bondCalls, 1);
    expect(client.connectCalls, 1);
    final error = tester.widget<Text>(
      find.byKey(const Key('connection-error')),
    );
    expect(error.data, contains('needs BLE MTU'));
    expect(find.byIcon(Icons.link_off), findsNothing);
  });
}
