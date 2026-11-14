import '../models/models.dart';

/// Shortest and longest time between two checks of Grafana, and the step the
/// picker moves in (10 s, 20 s, 30 s ... 2 min).
const minWatchSeconds = 10;
const maxWatchSeconds = 120;
const watchStepSeconds = 10;
const defaultWatchSeconds = 20;

/// How long "Snooze" silences the alarm before it rings again.
const snoozeDuration = Duration(minutes: 15);

int clampWatchSeconds(int s) => s.clamp(minWatchSeconds, maxWatchSeconds);

/// "20 seconds", "1 min", "1 min 30 s" ...
String formatWatchSeconds(int s) {
  if (s < 60) return '$s seconds';
  final m = s ~/ 60;
  final r = s % 60;
  return r == 0 ? '$m min' : '$m min $r s';
}

/// Stable identity of an alert: its sorted labels.
String alertKey(AlertInstance a) {
  final entries = a.labels.entries.toList()
    ..sort((x, y) => x.key.compareTo(y.key));
  return entries.map((e) => '${e.key}=${e.value}').join(',');
}

/// One critical alert as shown on the alarm page. Plain data so it can be sent
/// between the background service and the app.
class AlarmItem {
  const AlarmItem({
    required this.key,
    required this.name,
    required this.labels,
    required this.startsAt,
    required this.isNew,
    this.severity,
    this.summary,
  });

  final String key;
  final String name;
  final String? severity;
  final String? summary;
  final Map<String, String> labels;
  final DateTime startsAt;

  /// True until the user dismisses the alarm.
  final bool isNew;

  factory AlarmItem.fromAlert(AlertInstance a, {required bool isNew}) =>
      AlarmItem(
        key: alertKey(a),
        name: a.name,
        severity: a.severity,
        summary: a.summary,
        labels: a.labels,
        startsAt: a.startsAt,
        isNew: isNew,
      );

  AlarmItem acknowledged() => AlarmItem(
        key: key,
        name: name,
        severity: severity,
        summary: summary,
        labels: labels,
        startsAt: startsAt,
        isNew: false,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'severity': severity,
        'summary': summary,
        'labels': labels,
        'startsAt': startsAt.millisecondsSinceEpoch,
        'isNew': isNew,
      };

  factory AlarmItem.fromJson(Map<dynamic, dynamic> j) => AlarmItem(
        key: '${j['key'] ?? ''}',
        name: '${j['name'] ?? 'Alert'}',
        severity: j['severity'] as String?,
        summary: j['summary'] as String?,
        labels: {
          for (final e in ((j['labels'] as Map?) ?? const {}).entries)
            '${e.key}': '${e.value}'
        },
        startsAt: DateTime.fromMillisecondsSinceEpoch(
            (j['startsAt'] as num?)?.toInt() ?? 0),
        isNew: j['isNew'] == true,
      );
}

/// Every critical alert that is firing right now.
class AlarmSnapshot {
  const AlarmSnapshot(this.items, [this.updatedAt]);

  static const empty = AlarmSnapshot([]);

  final List<AlarmItem> items;
  final DateTime? updatedAt;

  /// The alarm is sounding while at least one alert has not been dismissed.
  bool get ringing => items.any((i) => i.isNew);

  AlarmSnapshot acknowledged() =>
      AlarmSnapshot([for (final i in items) i.acknowledged()], updatedAt);

  Map<String, dynamic> toJson() => {
        'items': [for (final i in items) i.toJson()],
        'at': (updatedAt ?? DateTime.now()).millisecondsSinceEpoch,
      };

  factory AlarmSnapshot.fromJson(Map<dynamic, dynamic> j) => AlarmSnapshot(
        [
          for (final i in ((j['items'] as List?) ?? const []))
            AlarmItem.fromJson(i as Map)
        ],
        DateTime.fromMillisecondsSinceEpoch((j['at'] as num?)?.toInt() ?? 0),
      );
}

class CriticalUpdate {
  const CriticalUpdate(this.snapshot,
      {required this.changed, required this.wasRinging});

  final AlarmSnapshot snapshot;

  /// Something worth redrawing or re-notifying happened since the last check.
  final bool changed;

  /// The alarm was already sounding before this check. A new critical alert
  /// then only updates the page and notification, it does not restart the
  /// sound.
  final bool wasRinging;
}

/// Tracks the critical alerts across checks: which are firing, which the user
/// already dismissed, and whether anything changed.
class CriticalTracker {
  final Set<String> _acked = {};
  bool _baselined = false;
  String _signature = '';
  DateTime? _snoozeUntil;
  AlarmSnapshot _snapshot = AlarmSnapshot.empty;

  AlarmSnapshot get snapshot => _snapshot;

  /// When the current snooze ends, or null when not snoozed.
  DateTime? get snoozeUntil => _snoozeUntil;

  bool _ackOnNext = false;

  /// Brings back a snooze after the background service was restarted (the
  /// phone or the system killed it). Without this the restarted service would
  /// treat every firing alert as already known and never ring again.
  /// Alerts firing while the snooze is still running stay silent; once it has
  /// ended they ring.
  void restoreSnooze(DateTime until) {
    _baselined = true;
    _snoozeUntil = until;
    _ackOnNext = DateTime.now().isBefore(until);
  }

  static String _sigOf(List<AlarmItem> items) =>
      items.map((i) => '${i.key}|${i.isNew}|${i.summary}').join('\n');

  /// [firing] is every firing alert; only the critical ones are used. Alerts
  /// that were already firing on the very first check are treated as known
  /// and do not ring.
  CriticalUpdate update(List<AlertInstance> firing) {
    final crit = [
      for (final a in firing)
        if (a.isCritical) a
    ];
    final keys = {for (final a in crit) alertKey(a)};
    if (!_baselined) {
      _baselined = true;
      _acked.addAll(keys);
    }
    if (_ackOnNext) {
      _ackOnNext = false;
      _acked.addAll(keys);
    }
    // A resolved alert is forgotten, so it rings again if it comes back.
    _acked.retainAll(keys);
    // Snooze over: whatever is still firing rings again.
    final until = _snoozeUntil;
    if (until != null && !DateTime.now().isBefore(until)) {
      _snoozeUntil = null;
      _acked.clear();
    }

    final wasRinging = _snapshot.ringing;
    final items = [
      for (final a in crit)
        AlarmItem.fromAlert(a, isNew: !_acked.contains(alertKey(a)))
    ]..sort((a, b) => b.startsAt.compareTo(a.startsAt));

    final sig = _sigOf(items);
    final changed = sig != _signature;
    _signature = sig;
    _snapshot = AlarmSnapshot(items, DateTime.now());
    return CriticalUpdate(_snapshot, changed: changed, wasRinging: wasRinging);
  }

  /// The user dismissed the alarm: everything now firing is acknowledged.
  void ackAll() {
    _acked.addAll(_snapshot.items.map((i) => i.key));
    _snapshot = _snapshot.acknowledged();
    _signature = _sigOf(_snapshot.items);
  }

  /// Silences the alarm for [d]. New critical alerts that start meanwhile
  /// still ring; the snoozed ones ring again when the time is up.
  void snooze(Duration d) {
    ackAll();
    _snoozeUntil = DateTime.now().add(d);
  }

  void reset() {
    _snoozeUntil = null;
    _ackOnNext = false;
    _acked.clear();
    _baselined = false;
    _signature = '';
    _snapshot = AlarmSnapshot.empty;
  }
}
