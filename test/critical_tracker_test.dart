import 'package:flutter_test/flutter_test.dart';
import 'package:grafmod/core/alarm_state.dart';
import 'package:grafmod/models/models.dart';

AlertInstance alert(String name, {String sev = 'critical', String? summary}) =>
    AlertInstance(
      labels: {'alertname': name, 'severity': sev},
      annotations: {if (summary != null) 'summary': summary},
      startsAt: DateTime(2026, 1, 1),
      state: 'active',
      receivers: const [],
      generatorUrl: '',
    );

void main() {
  snoozeTests();
  group('CriticalTracker', () {
    test('alerts already firing at the first check do not ring', () {
      final t = CriticalTracker();
      final u = t.update([alert('A')]);
      expect(u.snapshot.items.length, 1);
      expect(u.snapshot.ringing, isFalse);
    });

    test('a new critical alert rings and lists every critical alert', () {
      final t = CriticalTracker()..update([alert('A')]);
      final u = t.update([alert('A'), alert('B')]);
      expect(u.changed, isTrue);
      expect(u.snapshot.ringing, isTrue);
      expect(u.snapshot.items.map((i) => i.name).toSet(), {'A', 'B'});
      expect(u.snapshot.items.where((i) => i.isNew).single.name, 'B');
    });

    test('another alert during a ringing alarm updates it without a restart',
        () {
      final t = CriticalTracker()..update(const []);
      t.update([alert('A')]);
      final u = t.update([alert('A'), alert('B')]);
      expect(u.wasRinging, isTrue);
      expect(u.snapshot.items.length, 2);
      expect(u.snapshot.items.every((i) => i.isNew), isTrue);
    });

    test('a changed summary updates the page', () {
      final t = CriticalTracker()..update(const []);
      t.update([alert('A', summary: 'one')]);
      final u = t.update([alert('A', summary: 'two')]);
      expect(u.changed, isTrue);
      expect(u.snapshot.items.single.summary, 'two');
    });

    test('nothing changed means no update', () {
      final t = CriticalTracker()..update(const []);
      t.update([alert('A')]);
      expect(t.update([alert('A')]).changed, isFalse);
    });

    test('dismissing silences the alarm until a new alert fires', () {
      final t = CriticalTracker()..update(const []);
      t.update([alert('A')]);
      t.ackAll();
      expect(t.snapshot.ringing, isFalse);
      expect(t.update([alert('A')]).changed, isFalse);
      final u = t.update([alert('A'), alert('B')]);
      expect(u.snapshot.ringing, isTrue);
      expect(u.snapshot.items.where((i) => i.isNew).single.name, 'B');
    });

    test('an alert that resolves and returns rings again', () {
      final t = CriticalTracker()..update(const []);
      t.update([alert('A')]);
      t.ackAll();
      t.update(const []);
      expect(t.update([alert('A')]).snapshot.ringing, isTrue);
    });

    test('non-critical alerts are ignored', () {
      final t = CriticalTracker()..update(const []);
      expect(t.update([alert('W', sev: 'warning')]).snapshot.items, isEmpty);
    });

    test('snapshot survives the trip to the app as JSON', () {
      final t = CriticalTracker()..update(const []);
      final snap = t.update([alert('A', summary: 'x')]).snapshot;
      final back = AlarmSnapshot.fromJson(snap.toJson());
      expect(back.items.single.name, 'A');
      expect(back.items.single.summary, 'x');
      expect(back.ringing, isTrue);
    });
  });

  test('watch interval is clamped to 10 s .. 2 min', () {
    expect(clampWatchSeconds(1), 10);
    expect(clampWatchSeconds(500), 120);
    expect(formatWatchSeconds(30), '30 seconds');
    expect(formatWatchSeconds(60), '1 min');
    expect(formatWatchSeconds(90), '1 min 30 s');
  });
}

void snoozeTests() {
  group('snooze', () {
    test('silences until the time is up, then rings again', () {
      final t = CriticalTracker()..update(const []);
      t.update([alert('A')]);
      t.snooze(const Duration(hours: 1));
      expect(t.update([alert('A')]).snapshot.ringing, isFalse);
      // A different new alert still rings during the snooze.
      expect(t.update([alert('A'), alert('B')]).snapshot.ringing, isTrue);
    });

    test('an expired snooze rings the alert again', () {
      final t = CriticalTracker()..update(const []);
      t.update([alert('A')]);
      t.snooze(Duration.zero);
      expect(t.update([alert('A')]).snapshot.ringing, isTrue);
    });

    test('a restored snooze keeps quiet, then rings when it has ended', () {
      final t = CriticalTracker()
        ..restoreSnooze(DateTime.now().add(const Duration(minutes: 5)));
      expect(t.update([alert('A')]).snapshot.ringing, isFalse);
      expect(t.snoozeUntil, isNotNull);
    });

    test('a restored snooze that already ended rings the alert', () {
      final t = CriticalTracker()
        ..restoreSnooze(DateTime.now().subtract(const Duration(seconds: 1)));
      expect(t.update([alert('A')]).snapshot.ringing, isTrue);
      expect(t.snoozeUntil, isNull);
    });
  });
}
