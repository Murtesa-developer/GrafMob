import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'alarm_notifier.dart';
import 'grafana_api.dart';

/// How often Grafana is checked for firing alerts.
const watchInterval = Duration(seconds: 20);

const _kUrl = 'grafana_url';
const _kUser = 'grafana_user';
const _kPass = 'grafana_pass';
const _kWatch = 'watch_alerts';

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
}

/// Entry point of the background service (runs in its own isolate).
@pragma('vm:entry-point')
Future<void> backgroundMain(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final notifier = AlarmNotifier();
  await notifier.init();
  final tracker = FiringTracker();
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  service.on('stop').listen((_) => service.stopSelf());

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
        service.stopSelf();
        return;
      }
      final api = GrafanaApi(baseUrl: url, username: user, password: pass);
      try {
        final all = await api.alerts();
        final firing = all.where((a) => a.state == 'active').toList();
        for (final a in tracker.fresh(firing)) {
          await notifier.alert(a);
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

  unawaited(tick());
  Timer.periodic(watchInterval, (_) => tick());
}
