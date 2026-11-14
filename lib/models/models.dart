class GrafanaUser {
  GrafanaUser({required this.login, required this.name, required this.email});
  final String login;
  final String name;
  final String email;

  factory GrafanaUser.fromJson(Map<String, dynamic> j) => GrafanaUser(
        login: (j['login'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
      );
}

class DashboardItem {
  DashboardItem({
    required this.uid,
    required this.title,
    required this.folder,
    required this.tags,
    required this.starred,
  });

  final String uid;
  final String title;
  final String folder;
  final List<String> tags;
  final bool starred;

  factory DashboardItem.fromJson(Map<String, dynamic> j) => DashboardItem(
        uid: (j['uid'] ?? '').toString(),
        title: (j['title'] ?? 'Untitled').toString(),
        folder: (j['folderTitle'] ?? 'General').toString(),
        tags: ((j['tags'] as List?) ?? const []).map((e) => '$e').toList(),
        starred: j['isStarred'] == true,
      );
}

class AlertInstance {
  AlertInstance({
    required this.labels,
    required this.annotations,
    required this.startsAt,
    required this.state,
    required this.receivers,
    required this.generatorUrl,
  });

  final Map<String, String> labels;
  final Map<String, String> annotations;
  final DateTime startsAt;
  final String state; // active | suppressed | unprocessed
  final List<String> receivers;
  final String generatorUrl;

  String get name => labels['alertname'] ?? 'Alert';
  /// Severity label. Some setups use another label name for it.
  String? get severity =>
      labels['severity'] ??
      labels['Severity'] ??
      labels['priority'] ??
      labels['level'] ??
      labels['urgency'];

  /// True for critical alerts, which get the loud alarm.
  bool get isCritical {
    final v = (severity ?? '').toLowerCase().trim();
    if (v.contains('crit')) return true;
    const names = {
      'page',
      'p0',
      'p1',
      'sev0',
      'sev1',
      'emergency',
      'fatal',
      'disaster',
      'urgent',
    };
    return names.contains(v);
  }
  String? get summary => annotations['summary'] ?? annotations['description'];

  factory AlertInstance.fromJson(Map<String, dynamic> j) => AlertInstance(
        labels: _strMap(j['labels']),
        annotations: _strMap(j['annotations']),
        startsAt:
            DateTime.tryParse((j['startsAt'] ?? '').toString())?.toLocal() ??
                DateTime.now(),
        state: ((j['status'] as Map?)?['state'] ?? 'active').toString(),
        receivers: ((j['receivers'] as List?) ?? const [])
            .map((e) => ((e as Map)['name'] ?? '').toString())
            .toList(),
        generatorUrl: (j['generatorURL'] ?? '').toString(),
      );
}

class AlertRule {
  AlertRule({
    required this.name,
    required this.state,
    required this.health,
    required this.folder,
    required this.labels,
    required this.annotations,
    required this.activeCount,
    required this.lastEvaluation,
    required this.lastError,
  });

  final String name;
  final String state; // firing | pending | inactive
  final String health; // ok | error | nodata
  final String folder;
  final Map<String, String> labels;
  final Map<String, String> annotations;
  final int activeCount;
  final DateTime? lastEvaluation;
  final String lastError;

  int get severityRank {
    switch (state) {
      case 'firing':
        return 0;
      case 'pending':
        return 1;
      default:
        return health == 'ok' ? 3 : 2;
    }
  }

  factory AlertRule.fromJson(Map<String, dynamic> j, String folder) =>
      AlertRule(
        name: (j['name'] ?? 'Rule').toString(),
        state: (j['state'] ?? 'inactive').toString(),
        health: (j['health'] ?? 'ok').toString(),
        folder: folder,
        labels: _strMap(j['labels']),
        annotations: _strMap(j['annotations']),
        activeCount: ((j['alerts'] as List?) ?? const []).length,
        lastEvaluation: DateTime.tryParse(
          (j['lastEvaluation'] ?? '').toString(),
        )?.toLocal(),
        lastError: (j['lastError'] ?? '').toString(),
      );
}

Map<String, String> _strMap(dynamic m) {
  if (m is! Map) return {};
  return m.map((k, v) => MapEntry('$k', '$v'));
}

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ${d.inMinutes % 60}m ago';
  return '${d.inDays}d ${d.inHours % 24}h ago';
}
