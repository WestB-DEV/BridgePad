import 'dart:async';

import 'package:bridgepad/src/android_ble_platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.bridgepad.bridgepad/android-test');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'pairing timeout cancels the native attempt and reports a retryable error',
    () async {
      final pendingBond = Completer<bool>();
      var cancelCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'bond') return pendingBond.future;
            if (call.method == 'cancelBond') {
              cancelCalls++;
              return null;
            }
            return true;
          });
      final platform = AndroidBlePlatform(
        channel: channel,
        isAndroidOverride: true,
        bondTimeout: const Duration(milliseconds: 5),
      );

      await expectLater(
        platform.bond('device-1'),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'bond_timeout',
          ),
        ),
      );
      expect(cancelCalls, 1);
    },
  );
}
