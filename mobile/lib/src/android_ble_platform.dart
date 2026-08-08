import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class AndroidBlePlatform {
  const AndroidBlePlatform({
    this.channel = const MethodChannel('dev.bridgepad.bridgepad/android'),
    this.isAndroidOverride,
    this.bondTimeout = const Duration(seconds: 30),
  });

  final MethodChannel channel;
  final bool? isAndroidOverride;
  final Duration bondTimeout;

  bool get _isAndroid => isAndroidOverride ?? Platform.isAndroid;

  Future<void> requestPermissions() async {
    if (!_isAndroid) return;
    final granted = await channel.invokeMethod<bool>('requestBlePermissions');
    if (granted != true) {
      throw PlatformException(
        code: 'permissions_denied',
        message: 'Bluetooth permission is required to find BridgePad.',
      );
    }
  }

  Future<void> bond(String deviceId) async {
    if (!_isAndroid) return;
    bool? bonded;
    try {
      bonded = await channel
          .invokeMethod<bool>('bond', {'deviceId': deviceId})
          .timeout(bondTimeout);
    } on TimeoutException {
      try {
        await channel.invokeMethod<void>('cancelBond');
      } catch (_) {
        // The timeout remains the actionable error if cleanup also fails.
      }
      throw PlatformException(
        code: 'bond_timeout',
        message: 'Pairing timed out. Confirm the Flipper prompt and try again.',
      );
    }
    if (bonded != true) {
      throw PlatformException(
        code: 'bond_failed',
        message: 'Pairing failed. Confirm the prompt and try again.',
      );
    }
  }
}
