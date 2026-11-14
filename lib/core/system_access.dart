import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SystemStatus {
  const SystemStatus({
    this.batteryUnrestricted = true,
    this.dndOverride = true,
    this.fullScreen = true,
  });
  final bool batteryUnrestricted;
  final bool dndOverride;
  final bool fullScreen;
}

/// Android-only helpers: battery optimisation, Do Not Disturb override and the
/// loud critical alarm channel. Everything is a no-op on other platforms.
class SystemAccess {
  static const _ch = MethodChannel('grafmod/system');

  static bool get supported => !kIsWeb && Platform.isAndroid;

  static Future<SystemStatus> status() async {
    if (!supported) return const SystemStatus();
    try {
      final m = await _ch.invokeMapMethod<String, bool>('status');
      return SystemStatus(
        batteryUnrestricted: m?['battery'] ?? true,
        dndOverride: m?['dnd'] ?? true,
        fullScreen: m?['fullScreen'] ?? true,
      );
    } catch (_) {
      return const SystemStatus();
    }
  }

  static Future<void> _call(String method) async {
    if (!supported) return;
    try {
      await _ch.invokeMethod<void>(method);
    } catch (_) {}
  }

  static Future<void> setupCriticalChannel() => _call('setupCriticalChannel');
  static Future<void> requestIgnoreBattery() => _call('requestIgnoreBattery');
  static Future<void> openBatterySettings() => _call('openBatterySettings');
  static Future<void> openDndAccess() => _call('openDndAccess');
  static Future<void> openFullScreenSettings() =>
      _call('openFullScreenSettings');
}
