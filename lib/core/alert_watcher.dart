import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'alarm_notifier.dart';
import 'alarm_state.dart';
import 'background_watch.dart';
import 'grafana_api.dart';
import 'system_access.dart';

enum WatchState { off, starting, on, blocked }

/// Watches Grafana for firing alerts and raises a local alarm for every alert
/// that was not firing before. No notification server or Firebase is used.
///
/// On Android the alarms come from a background service, so they keep working
/// when the app is closed. This class then only keeps the screens fresh and
/// shows what the service reports. On other platforms it raises the alarms
/// itself while the app is running.
class AlertWatcher extends ChangeNotifier {
  AlertWatcher() {
    // Listen from the start (before sign-in finishes) so an alarm that opened
    // the app is on screen straight away.
    _alarmSub = BackgroundWatch.alarmEvents.listen((m) {
      if (m == null) return;
      _setAlarm(AlarmSnapshot.fromJson(m));
    });
    BackgroundWatch.requestSync();
    // Power button while an alarm is ringing: snooze it.
    SystemAccess.listenScreenOff(() {
      if (pageOpen.value && alarm.value.ringing) unawaited(snoozeAlarm());
    });
  }

  /// Time between two checks. Changed with [setIntervalSeconds].
  Duration interval = const Duration(seconds: defaultWatchSeconds);

  WatchState state = WatchState.off;
  String? message;
  DateTime? lastCheck;

  /// True when alarms are handled by the background service.
  bool inBackground = false;

  /// Bumped after every poll so the alert lists can reload.
  final alertTick = ValueNotifier<int>(0);

  /// Bumped when the user taps an alarm notification.
  final openAlerts = ValueNotifier<int>(0);

  /// Every critical alert firing now. The alarm page shows this while
  /// [AlarmSnapshot.ringing] and updates as alerts come and go.
  final alarm = ValueNotifier<AlarmSnapshot>(AlarmSnapshot.empty);

  /// Whether the full-screen alarm page is up. It opens when a critical alert
  /// starts ringing and stays until the user closes it, even after the alarm
  /// was acknowledged, so the details can still be read.
  final pageOpen = ValueNotifier<bool>(false);

  /// Emits each newly firing alert while the app is open.
  final _fired = StreamController<AlertInstance>.broadcast();
  Stream<AlertInstance> get fired => _fired.stream;

  final _notifier = AlarmNotifier();
  final _tracker = FiringTracker();
  final _critical = CriticalTracker();
  StreamSubscription<Map<String, dynamic>?>? _alarmSub;
  GrafanaApi? _api;
  Timer? _timer;
  bool _polling = false;

  /// Starts watching with [api]. Safe to call again with a new account.
  Future<bool> start(GrafanaApi api, {int? seconds}) async {
    stop(notify: false);
    if (seconds != null) {
      interval = Duration(seconds: clampWatchSeconds(seconds));
    }
    _api = api;
    state = WatchState.starting;
    message = null;
    notifyListeners();
    try {
      await _notifier.init(onTap: (_) => openAlerts.value++);
      await SystemAccess.setupCriticalChannel();
      final allowed = await _notifier.askPermission();
      if (!allowed) {
        state = WatchState.blocked;
        message = 'Notifications are blocked. Allow them in system settings '
            'so alarms can sound.';
        notifyListeners();
        return false;
      }
    } catch (e) {
      state = WatchState.blocked;
      message = 'Alarms are not available on this device.';
      notifyListeners();
      return false;
    }
    inBackground = await BackgroundWatch.start();
    state = WatchState.on;
    notifyListeners();
    _timer = Timer.periodic(interval, (_) => _poll());
    unawaited(_poll());
    return true;
  }

  /// Applies a new check interval. The caller saves it first; the background
  /// service reads it from storage.
  void setIntervalSeconds(int seconds) {
    interval = Duration(seconds: clampWatchSeconds(seconds));
    if (state == WatchState.on) {
      _timer?.cancel();
      _timer = Timer.periodic(interval, (_) => _poll());
    }
    BackgroundWatch.intervalChanged();
  }

  /// Stops the checks made by the open app. The background service keeps
  /// running; use [shutdownBackground] to stop it.
  void stop({bool notify = true}) {
    _timer?.cancel();
    _timer = null;
    _api = null;
    _tracker.reset();
    _critical.reset();
    state = WatchState.off;
    message = null;
    if (notify) notifyListeners();
  }

  /// Turns alarms off completely, including the background service.
  Future<void> shutdownBackground() async {
    inBackground = false;
    await SystemAccess.cancelSnooze();
    await BackgroundWatch.stop();
    await _notifier.clearCritical();
    _setAlarm(AlarmSnapshot.empty);
  }

  /// Poll right now, e.g. when the app returns to the foreground.
  Future<void> checkNow() {
    BackgroundWatch.requestSync();
    return _poll();
  }

  /// Applies a new alarm state. The page opens when an alert rings and closes
  /// by itself when every critical alert has resolved.
  void _setAlarm(AlarmSnapshot s, {bool endNative = true}) {
    final wasOpen = pageOpen.value;
    alarm.value = s;
    if (s.items.isEmpty) {
      if (wasOpen) {
        pageOpen.value = false;
        unawaited(SystemAccess.setRinging(false));
        if (endNative) unawaited(SystemAccess.endAlarm(moveToBack: true));
      }
    } else if (s.ringing && !wasOpen) {
      pageOpen.value = true;
      unawaited(SystemAccess.setRinging(true));
    }
  }

  /// Stops the sound and remembers these alerts as seen. The page stays up.
  /// A critical alert that starts later rings again.
  Future<void> acknowledgeAlarm() async {
    unawaited(SystemAccess.cancelSnooze());
    _setAlarm(alarm.value.acknowledged(), endNative: false);
    BackgroundWatch.ack();
    _critical.ackAll();
    await _notifier.clearCritical();
  }

  Future<void> _closePage({bool moveToBack = true}) async {
    pageOpen.value = false;
    await SystemAccess.setRinging(false);
    await SystemAccess.endAlarm(moveToBack: moveToBack);
  }

  /// Stops the sound and closes the page.
  Future<void> dismissAlarm() async {
    await acknowledgeAlarm();
    await _closePage();
  }

  /// Silences the alarm and closes the page; rings again after
  /// [snoozeDuration] if the alerts are still firing.
  Future<void> snoozeAlarm() async {
    final items = alarm.value.items;
    // A system alarm wakes the phone when the snooze ends, even if the phone
    // or the app is asleep (timers inside the app are not reliable then). The
    // two seconds let the background service un-snooze first.
    if (items.isNotEmpty) {
      final n = items.length;
      unawaited(SystemAccess.scheduleSnooze(
        DateTime.now().add(snoozeDuration + const Duration(seconds: 2)),
        n == 1 ? 'CRITICAL: ${items.first.name}' : '$n CRITICAL ALERTS',
        n == 1
            ? (items.first.summary ?? 'A critical alert is firing in Grafana.')
            : items.map((i) => i.name).join(', '),
      ));
    }
    _setAlarm(alarm.value.acknowledged(), endNative: false);
    BackgroundWatch.snooze();
    _critical.snooze(snoozeDuration);
    await _notifier.clearCritical();
    await _closePage();
  }

  /// Unlocks the phone if needed, silences the alarm and shows the alerts.
  Future<void> openAppFromAlarm() async {
    if (!await SystemAccess.dismissKeyguard()) return;
    await acknowledgeAlarm();
    await _closePage(moveToBack: false);
    openAlerts.value++;
  }

  Future<void> _poll() async {
    final api = _api;
    if (api == null || _polling) return;
    _polling = true;
    try {
      final all = await api.alerts();
      final firing = all.where((a) => a.state == 'active').toList();
      for (final a in _tracker.fresh(firing)) {
        _fired.add(a);
        // The background service rings the alarm when it is running.
        if (!inBackground && !a.isCritical) unawaited(_notifier.alert(a));
      }
      if (!inBackground) {
        final u = _critical.update(firing);
        if (u.changed) _setAlarm(u.snapshot);
        if (u.snapshot.ringing) {
          // Sounded again every check until the user dismisses it.
          if (_critical.snapshot.ringing) {
            await _notifier.showCritical(u.snapshot);
          }
        } else if (u.changed) {
          await _notifier.clearCritical();
        }
      }
      lastCheck = DateTime.now();
      if (message != null && state == WatchState.on) message = null;
      alertTick.value++;
      notifyListeners();
    } catch (e) {
      // Keep watching; the next poll may succeed.
      if (state == WatchState.on) {
        message = 'Last check failed: $e';
        notifyListeners();
      }
    } finally {
      _polling = false;
    }
  }

  /// Raises a sample alarm so the user can check sound and permissions.
  Future<void> sendTest() => _notifier.show(
      'Test alarm', 'GrafMod alarms are working on this device.');

  /// Rings the real critical alarm, with the full-screen page, for two sample
  /// alerts so the user can check Do Not Disturb, volume and the lock screen.
  Future<void> sendTestCritical() async {
    final now = DateTime.now();
    final snap = AlarmSnapshot([
      AlarmItem(
        key: 'test-1',
        name: 'Test: database down',
        severity: 'critical',
        summary: 'This is how a critical alert looks and sounds.',
        labels: const {'severity': 'critical', 'instance': 'db-1'},
        startsAt: now,
        isNew: true,
      ),
      AlarmItem(
        key: 'test-2',
        name: 'Test: disk almost full',
        severity: 'critical',
        summary: 'Several critical alerts are all listed on one page.',
        labels: const {'severity': 'critical', 'instance': 'web-2'},
        startsAt: now.subtract(const Duration(minutes: 2)),
        isNew: true,
      ),
    ], now);
    _setAlarm(snap);
    await _notifier.showCritical(snap);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _alarmSub?.cancel();
    _fired.close();
    alertTick.dispose();
    openAlerts.dispose();
    alarm.dispose();
    pageOpen.dispose();
    super.dispose();
  }
}
