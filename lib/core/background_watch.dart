import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'alarm_notifier.dart';
import 'alarm_state.dart';
import 'grafana_api.dart';

const _kUrl = 'grafana_url';
const _kUser = 'grafana_user';
const _kPass = 'grafana_pass';
const _kWatch = 'watch_alerts';
const _kInterval = 'watch_interval';
const _kSnooze = 'snooze_until';

/// Android foreground service that keeps checking Grafana and sounding alarms
/// while the app is closed. A small notification stays visible while it runs.
class BackgroundWatch {
  static bool get supported => !kIsWeb && Platform.isAndroid;

  static Future<void> configure() async {
    if (!supported) return;
    try {
      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            'grafmod_watch',
            'Alert watching',
            description: 'Shown while GrafMod watches your alerts.',
            importance: Importance.low,
          ));
      await FlutterBackgroundService().configure(
        androidConfiguration: AndroidConfiguration(
          onStart: backgroundMain,
          autoStart: false,
          autoStartOnBoot: true,
          isForegroundMode: true,
          notificationChannelId: 'grafmod_watch',
          initialNotificationTitle: 'GrafMod',
          initialNotificationContent: 'Watching your alerts',
          foregroundServiceNotificationId: 4711,
          foregroundServiceTypes: [AndroidForegroundType.specialUse],
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: backgroundMain,
          onBackground: (_) => true,
        ),
      );
    } catch (_) {}
  }

  /// Starts the service. Returns false when it could not be started.
  static Future<bool> start() async {
    if (!supported) return false;
    try {
      final service = FlutterBackgroundService();
      if (await service.isRunning()) return true;
      return await service.startService();
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    if (!supported) return;
    try {
      final service = FlutterBackgroundService();
      if (await service.isRunning()) service.invoke('stop');
    } catch (_) {}
  }

  /// Critical-alarm updates sent by the service while it runs.
  static Stream<Map<String, dynamic>?> get alarmEvents {
    if (!supported) return const Stream.empty();
    return FlutterBackgroundService().on('alarm');
  }

  static void _send(String event) {
    if (!supported) return;
    try {
      FlutterBackgroundService().invoke(event);
    } catch (_) {}
  }

  /// Asks the service to send the current alarm state again.
  static void requestSync() => _send('sync');

  /// Tells the service the user dismissed the alarm.
  static void ack() => _send('ack');

  /// Tells the service to silence the alarm for [snoozeDuration].
  static void snooze() => _send('snooze');

  /// Tells the service the check interval changed (it is read from storage).
  static void intervalChanged() => _send('interval');
}

Future<int> _readSeconds(FlutterSecureStorage storage) async {
  try {
    final v = int.tryParse(await storage.read(key: _kInterval) ?? '');
    return clampWatchSeconds(v ?? defaultWatchSeconds);
  } catch (_) {
    return defaultWatchSeconds;
  }
}

/// Entry point of the background service (runs in its own isolate).
@pragma('vm:entry-point')
Future<void> backgroundMain(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final notifier = AlarmNotifier();
  await notifier.init();
  final tracker = FiringTracker();
  final critical = CriticalTracker();
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  var stopped = false;
  var generation = 0;
  Timer? timer;

  // A snooze survives the service being restarted by the system.
  var snoozeSaved = false;
  try {
    final ms = int.tryParse(await storage.read(key: _kSnooze) ?? '');
    if (ms != null) {
      snoozeSaved = true;
      critical.restoreSnooze(DateTime.fromMillisecondsSinceEpoch(ms));
    }
  } catch (_) {}

  /// Sends every critical alert to the app so the alarm page can show them.
  void publish() => service.invoke('alarm', critical.snapshot.toJson());

  service.on('stop').listen((_) {
    stopped = true;
    timer?.cancel();
    service.stopSelf();
  });
  // The user dismissed the alarm.
  service.on('ack').listen((_) async {
    critical.ackAll();
    await notifier.clearCritical();
    publish();
  });

  // Silence for a while; rings again after that if still firing.
  service.on('snooze').listen((_) async {
    critical.snooze(snoozeDuration);
    final until = critical.snoozeUntil;
    if (until != null) {
      snoozeSaved = true;
      try {
        await storage.write(
            key: _kSnooze, value: '${until.millisecondsSinceEpoch}');
      } catch (_) {}
    }
    await notifier.clearCritical();
    publish();
  });

  var busy = false;
  Future<void> tick() async {
    if (busy) return;
    busy = true;
    try {
      final url = await storage.read(key: _kUrl);
      final user = await storage.read(key: _kUser);
      final pass = await storage.read(key: _kPass);
      final watch = await storage.read(key: _kWatch);
      if (url == null || user == null || pass == null || watch == 'false') {
        // Signed out or alarms turned off: nothing left to watch.
        stopped = true;
        timer?.cancel();
        await notifier.clearCritical();
        try {
          await storage.delete(key: _kSnooze);
        } catch (_) {}
        service.stopSelf();
        return;
      }
      final api = GrafanaApi(baseUrl: url, username: user, password: pass);
      try {
        final all = await api.alerts();
        final firing = all.where((a) => a.state == 'active').toList();

        // Normal alerts: one notification each, the first time they fire.
        for (final a in tracker.fresh(firing)) {
          if (!a.isCritical) await notifier.alert(a);
        }

        // Critical alerts: one alarm that lists all of them. New ones join a
        // ringing alarm without restarting it.
        final u = critical.update(firing);
        // Snooze over: forget the saved end time.
        if (critical.snoozeUntil == null && snoozeSaved) {
          snoozeSaved = false;
          try {
            await storage.delete(key: _kSnooze);
          } catch (_) {}
        }
        if (u.changed) publish();
        if (u.snapshot.ringing) {
          // Sounded again every round while it is not dismissed, so nothing
          // (screen turning on, the app opening, a swiped notification) can
          // end the alarm. Only "Dismiss alarm" does.
          if (critical.snapshot.ringing) {
            await notifier.showCritical(u.snapshot);
          }
        } else {
          // Nothing is ringing: make sure no stale alarm notification (for
          // example from the snooze alarm, when the alert resolved meanwhile)
          // keeps sounding.
          await notifier.clearCritical();
        }

        if (service is AndroidServiceInstance) {
          await service.setForegroundNotificationInfo(
            title: 'GrafMod',
            content: firing.isEmpty
                ? 'Watching your alerts. All clear.'
                : '${firing.length} alert${firing.length == 1 ? '' : 's'} firing',
          );
        }
      } finally {
        api.close();
      }
    } catch (_) {
      // Network or server problem: try again on the next round.
    } finally {
      busy = false;
    }
  }

  // Checks now, then again after the interval the user picked. The interval
  // is read every round, so a change applies without restarting the service.
  Future<void> loop() async {
    final mine = ++generation;
    timer?.cancel();
    await tick();
    if (stopped || mine != generation) return;
    final secs = await _readSeconds(storage);
    timer = Timer(Duration(seconds: secs), () => unawaited(loop()));
  }

  // The app opening (or being woken by the snooze alarm) also checks Grafana
  // right away, so a snooze that has just ended rings without waiting.
  service.on('sync').listen((_) async {
    publish();
    await tick();
    if (!critical.snapshot.ringing) await notifier.clearCritical();
  });

  service.on('interval').listen((_) => unawaited(loop()));
  unawaited(loop());
}
