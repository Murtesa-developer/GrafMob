import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'alarm_notifier.dart';
import 'background_watch.dart';
import 'grafana_api.dart';
import 'system_access.dart';

enum WatchState { off, starting, on, blocked }

/// Watches Grafana for firing alerts and raises a local alarm for every alert
/// that was not firing before. No notification server or Firebase is used.
///
/// On Android the alarms come from a background service, so they keep working
/// when the app is closed. This class then only keeps the screens fresh. On
/// other platforms it raises the alarms itself while the app is running.
class AlertWatcher extends ChangeNotifier {
  AlertWatcher({this.interval = watchInterval});

  final Duration interval;

  WatchState state = WatchState.off;
  String? message;
  DateTime? lastCheck;

  /// True when alarms are handled by the background service.
  bool inBackground = false;

  /// Bumped after every poll so the alert lists can reload.
  final alertTick = ValueNotifier<int>(0);

  /// Bumped when the user taps an alarm notification.
  final openAlerts = ValueNotifier<int>(0);

  /// Emits each newly firing alert while the app is open.
  final _fired = StreamController<AlertInstance>.broadcast();
  Stream<AlertInstance> get fired => _fired.stream;

  final _notifier = AlarmNotifier();
  final _tracker = FiringTracker();
  GrafanaApi? _api;
  Timer? _timer;
  bool _polling = false;

  /// Starts watching with [api]. Safe to call again with a new account.
  Future<bool> start(GrafanaApi api) async {
    stop(notify: false);
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

  /// Stops the checks made by the open app. The background service keeps
  /// running; use [shutdownBackground] to stop it.
  void stop({bool notify = true}) {
    _timer?.cancel();
    _timer = null;
    _api = null;
    _tracker.reset();
    state = WatchState.off;
    message = null;
    if (notify) notifyListeners();
  }

  /// Turns alarms off completely, including the background service.
  Future<void> shutdownBackground() async {
    inBackground = false;
    await BackgroundWatch.stop();
  }

  /// Poll right now, e.g. when the app returns to the foreground.
  Future<void> checkNow() => _poll();

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
        if (!inBackground) unawaited(_notifier.alert(a));
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

  /// Sounds the loud critical alarm so the user can check DND and volume.
  Future<void> sendTestCritical() => _notifier.show(
      'CRITICAL: Test alarm', 'This is how a critical alert will sound.',
      critical: true);

  @override
  void dispose() {
    _timer?.cancel();
    _fired.close();
    alertTick.dispose();
    openAlerts.dispose();
    super.dispose();
  }
}
