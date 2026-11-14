import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/models.dart';

/// Builds and shows alarm notifications. Used by the app and by the
/// background service, which runs in a separate isolate.
class AlarmNotifier {
  AlarmNotifier();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _normal = AndroidNotificationDetails(
    'grafmod_alarms',
    'Alert alarms',
    channelDescription: 'Sounds an alarm when a Grafana alert starts firing.',
    importance: Importance.max,
    priority: Priority.high,
    category: AndroidNotificationCategory.alarm,
    playSound: true,
    enableVibration: true,
  );

  /// Loud, repeating alarm for critical alerts. The channel itself is created
  /// natively (see MainActivity) so it can override Do Not Disturb.
  static final _critical = AndroidNotificationDetails(
    'grafmod_critical',
    'Critical alarms',
    channelDescription: 'Loud alarm for critical Grafana alerts.',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.alarm,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    playSound: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 800, 400, 800, 400, 800]),
    fullScreenIntent: true,
    visibility: NotificationVisibility.public,
    // 4 = FLAG_INSISTENT: keep sounding until the alarm is dismissed.
    additionalFlags: Int32List.fromList([4]),
  );

  static bool isCritical(AlertInstance a) => a.isCritical;

  /// Makes sure the loud channel exists with alarm sound and vibration. The
  /// app normally creates it with a Do Not Disturb override; if that has not
  /// happened yet (for example the service started first) this is the backup.
  /// An existing channel is never changed by this.
  Future<void> _ensureCriticalChannel() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    try {
      await android.createNotificationChannel(AndroidNotificationChannel(
        'grafmod_critical',
        'Critical alarms',
        description: 'Loud alarm for critical Grafana alerts.',
        importance: Importance.max,
        playSound: true,
        sound: const UriAndroidNotificationSound(
            'content://settings/system/alarm_alert'),
        audioAttributesUsage: AudioAttributesUsage.alarm,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 800, 400, 800, 400, 800]),
        showBadge: true,
      ));
    } catch (_) {}
  }

  Future<void> init({void Function(NotificationResponse)? onTap}) async {
    if (_ready) return;
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: onTap,
    );
    _ready = true;
    await _ensureCriticalChannel();
  }

  Future<bool> askPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final ok = await android.requestNotificationsPermission();
      return ok ?? true;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final ok =
          await ios.requestPermissions(alert: true, badge: true, sound: true);
      return ok ?? false;
    }
    return true;
  }

  Future<void> alert(AlertInstance a) {
    final sev = (a.severity ?? '').trim();
    final title = sev.isEmpty ? a.name : '${sev.toUpperCase()}: ${a.name}';
    return show(title, a.summary ?? 'An alert is firing in Grafana.',
        critical: isCritical(a));
  }

  Future<void> show(String title, String body, {bool critical = false}) async {
    try {
      await init();
      // Unique id so alarms never replace each other.
      final id = (DateTime.now().microsecondsSinceEpoch ~/ 1000) % 2000000000;
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: critical ? _critical : _normal,
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    } catch (_) {}
  }
}

/// Remembers which alerts were already firing so each one rings only once.
class FiringTracker {
  Set<String>? _known; // null until the first check sets the baseline

  static String keyOf(AlertInstance a) {
    final entries = a.labels.entries.toList()
      ..sort((x, y) => x.key.compareTo(y.key));
    return entries.map((e) => '${e.key}=${e.value}').join(',');
  }

  /// Returns the alerts in [firing] that were not firing at the last check.
  /// The first call only records the baseline and returns nothing.
  List<AlertInstance> fresh(List<AlertInstance> firing) {
    final keys = {for (final a in firing) keyOf(a)};
    final known = _known;
    _known = keys;
    if (known == null) return const [];
    return [
      for (final a in firing)
        if (!known.contains(keyOf(a))) a
    ];
  }

  void reset() => _known = null;
}
