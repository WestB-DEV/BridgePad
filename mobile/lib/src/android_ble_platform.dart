import 'dart:io';

import 'package:flutter/services.dart';

class AndroidBlePlatform {
  const AndroidBlePlatform();

  static const _channel = MethodChannel('dev.bridgepad.bridgepad/android');

  Future<void> requestPermissions() async {
    if (!Platform.isAndroid) return;
    final granted = await _channel.invokeMethod<bool>('requestBlePermissions');
    if (granted != true) {
      throw PlatformException(
        code: 'permissions_denied',
        message: 'Bluetooth permission is required to find BridgePad.',
      );
    }
  }

  Future<void> bond(String deviceId) async {
    if (!Platform.isAndroid) return;
    final bonded = await _channel.invokeMethod<bool>('bond', {
      'deviceId': deviceId,
    });
    if (bonded != true) {
      throw PlatformException(
        code: 'bond_failed',
        message: 'Pairing failed. Confirm the prompt and try again.',
      );
    }
  }
}
