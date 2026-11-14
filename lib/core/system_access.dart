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

  /// Calls [onScreenOff] when the power button turns the screen off while the
  /// alarm page is up (the native side only reports it then).
  static void listenScreenOff(VoidCallback onScreenOff) {
    if (!supported) return;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'screenOff') onScreenOff();
      return null;
    });
  }

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

  /// Ends the lock-screen alarm mode (screen no longer forced on / shown over
  /// the lock screen). With [moveToBack] a locked phone goes back to its lock
  /// screen instead of leaving the app open behind it.
  static Future<void> endAlarm({bool moveToBack = true}) async {
    if (!supported) return;
    try {
      await _ch.invokeMethod<void>('endAlarm', {'moveToBack': moveToBack});
    } catch (_) {}
  }

  /// While true the Android back button is ignored, so the alarm page cannot
  /// be left by accident. Only "Dismiss alarm" ends the alarm.
  static Future<void> setRinging(bool ringing) async {
    if (!supported) return;
    try {
      await _ch.invokeMethod<void>('setRinging', {'ringing': ringing});
    } catch (_) {}
  }

  /// Asks the user to unlock a locked phone. True when it is unlocked.
  static Future<bool> dismissKeyguard() async {
    if (!supported) return true;
    try {
      return await _ch.invokeMethod<bool>('dismissKeyguard') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Sets a system alarm for the end of a snooze. It wakes the phone and rings
  /// the alarm again even if the app or the phone is asleep.
  static Future<void> scheduleSnooze(
      DateTime at, String title, String body) async {
    if (!supported) return;
    try {
      await _ch.invokeMethod<void>('scheduleSnooze', {
        'at': at.millisecondsSinceEpoch,
        'title': title,
        'body': body,
      });
    } catch (_) {}
  }

  static Future<void> cancelSnooze() => _call('cancelSnooze');

  static Future<void> setupCriticalChannel() => _call('setupCriticalChannel');
  static Future<void> requestIgnoreBattery() => _call('requestIgnoreBattery');
  static Future<void> openBatterySettings() => _call('openBatterySettings');
  static Future<void> openDndAccess() => _call('openDndAccess');
  static Future<void> openFullScreenSettings() =>
      _call('openFullScreenSettings');
}
