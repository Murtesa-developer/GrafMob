import 'package:flutter/material.dart';

import '../core/grafana_api.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/async_list.dart';
import '../widgets/ui.dart';

Color _severityColor(String? s) {
  switch ((s ?? '').toLowerCase()) {
    case 'critical':
    case 'page':
      return Pal.red;
    case 'warning':
    case 'warn':
      return Pal.amber;
    case 'info':
      return Pal.blue;
    default:
      return Pal.violet;
  }
}

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key, required this.api, this.refreshOn});
  final GrafanaApi api;
  final Listenable? refreshOn;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: PageHeader(title: 'Alerts'),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: p.surface2,
              borderRadius: BorderRadius.circular(16),
            ),
            child: TabBar(
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              splashBorderRadius: BorderRadius.circular(12),
              indicator: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.outline),
              ),
              labelColor: p.text,
              unselectedLabelColor: p.muted,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700),
              tabs: const [
                Tab(
                  height: 40,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_active_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Active'),
                    ],
                  ),
                ),
                Tab(
                  height: 40,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.rule_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Rules'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _ActiveTab(api: api, refreshOn: refreshOn),
                _RulesTab(api: api, refreshOn: refreshOn),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveTab extends StatelessWidget {
  const _ActiveTab({required this.api, this.refreshOn});
  final GrafanaApi api;
  final Listenable? refreshOn;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return AsyncList<AlertInstance>(
      load: api.alerts,
      refreshOn: refreshOn,
      autoRefresh: const Duration(seconds: 30),
      emptyIcon: Icons.verified_rounded,
      emptyColor: Pal.green,
      emptyTitle: 'All clear',
      emptyMessage: 'No alerts are firing right now.',
      builder: (context, items) {
        final active = items.where((a) => a.state == 'active').length;
        final critical = items
            .where((a) => (a.severity ?? '').toLowerCase() == 'critical')
            .length;
        final suppressed = items.where((a) => a.state != 'active').length;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            Row(
              children: [
                Expanded(
                    child: StatTile(
                        icon: Icons.notifications_active_rounded,
                        label: 'Active',
                        value: active,
                        color: Pal.red)),
                const SizedBox(width: 10),
                Expanded(
                    child: StatTile(
                        icon: Icons.crisis_alert_rounded,
                        label: 'Critical',
                        value: critical,
                        color: Pal.amber)),
                const SizedBox(width: 10),
                Expanded(
                    child: StatTile(
                        icon: Icons.notifications_paused_rounded,
                        label: 'Silenced',
                        value: suppressed,
                        color: Pal.blue)),
              ],
            ),
            const SectionLabel(
                text: 'Latest first', icon: Icons.schedule_rounded),
            for (final a in items) _alertCard(context, a, p),
          ],
        );
      },
    );
  }

  Widget _alertCard(BuildContext context, AlertInstance a, Pal p) {
    final live = a.state == 'active';
    final color = live ? _severityColor(a.severity) : Pal.blue;
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      accent: color,
      onTap: () => showAlertDetails(
        context,
        title: a.name,
        icon: live
            ? Icons.notifications_active_rounded
            : Icons.notifications_paused_rounded,
        color: color,
        pillLabel: live ? 'Firing' : 'Silenced',
        labels: a.labels,
        annotations: a.annotations,
        extra: {
          'Started': '${timeAgo(a.startsAt)}  (${_fmt(a.startsAt)})',
          if (a.receivers.isNotEmpty) 'Receivers': a.receivers.join(', '),
        },
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(
            icon: live
                ? Icons.notifications_active_rounded
                : Icons.notifications_paused_rounded,
            color: color,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.name,
                    style: TextStyle(
                        color: p.text,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700)),
                if (a.summary != null && a.summary!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(a.summary!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, height: 1.3)),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 15, color: p.muted),
                    const SizedBox(width: 4),
                    Text(timeAgo(a.startsAt),
                        style: TextStyle(color: p.muted, fontSize: 12.5)),
                    const Spacer(),
                    if (a.severity != null && a.severity!.isNotEmpty)
                      StatusPill(label: a.severity!, color: color),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RulesTab extends StatelessWidget {
  const _RulesTab({required this.api, this.refreshOn});
  final GrafanaApi api;
  final Listenable? refreshOn;

  (IconData, Color, String) _look(AlertRule r) {
    if (r.state == 'firing') {
      return (Icons.local_fire_department_rounded, Pal.red, 'Firing');
    }
    if (r.state == 'pending') {
      return (Icons.hourglass_top_rounded, Pal.amber, 'Pending');
    }
    if (r.health != 'ok') {
      return (Icons.report_problem_rounded, Pal.amber, 'Check rule');
    }
    return (Icons.check_circle_rounded, Pal.green, 'Normal');
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return AsyncList<AlertRule>(
      load: api.rules,
      refreshOn: refreshOn,
      emptyIcon: Icons.rule_rounded,
      emptyTitle: 'No alert rules',
      emptyMessage: 'Create rules in Grafana under Alerting.',
      builder: (context, items) {
        final firing = items.where((r) => r.state == 'firing').length;
        final pending = items.where((r) => r.state == 'pending').length;
        final normal = items.length - firing - pending;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            Row(
              children: [
                Expanded(
                    child: StatTile(
                        icon: Icons.local_fire_department_rounded,
                        label: 'Firing',
                        value: firing,
                        color: Pal.red)),
                const SizedBox(width: 10),
                Expanded(
                    child: StatTile(
                        icon: Icons.hourglass_top_rounded,
                        label: 'Pending',
                        value: pending,
                        color: Pal.amber)),
                const SizedBox(width: 10),
                Expanded(
                    child: StatTile(
                        icon: Icons.check_circle_rounded,
                        label: 'Normal',
                        value: normal,
                        color: Pal.green)),
              ],
            ),
            SectionLabel(
                text: 'All rules', icon: Icons.rule_rounded, count: items.length),
            for (final r in items)
              Builder(builder: (context) {
                final (icon, color, label) = _look(r);
                return AppCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  onTap: () => showAlertDetails(
                    context,
                    title: r.name,
                    icon: icon,
                    color: color,
                    pillLabel: label,
                    labels: r.labels,
                    annotations: r.annotations,
                    extra: {
                      if (r.folder.isNotEmpty) 'Folder': r.folder,
                      'Health': r.health,
                      'Active instances': '${r.activeCount}',
                      if (r.lastEvaluation != null)
                        'Last evaluation': timeAgo(r.lastEvaluation!),
                      if (r.lastError.isNotEmpty) 'Last error': r.lastError,
                    },
                  ),
                  child: Row(
                    children: [
                      IconBadge(icon: icon, color: color),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: p.text,
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w700)),
                            if (r.folder.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.folder_rounded,
                                      size: 14, color: p.muted),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(r.folder,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: p.muted, fontSize: 12.5)),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusPill(label: label, color: color),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

String _fmt(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

void showAlertDetails(
  BuildContext context, {
  required String title,
  required IconData icon,
  required Color color,
  required String pillLabel,
  required Map<String, String> labels,
  required Map<String, String> annotations,
  required Map<String, String> extra,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final p = Pal.of(ctx);

      Widget section(String name, IconData ic, Map<String, String> m) {
        if (m.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(text: name, icon: ic),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  for (final e in m.entries.toList().asMap().entries) ...[
                    if (e.key > 0) Divider(color: p.outline),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 112,
                            child: Text(e.value.key,
                                style: TextStyle(
                                    color: p.muted, fontSize: 13.5)),
                          ),
                          Expanded(
                            child: SelectableText(e.value.value,
                                style: TextStyle(
                                    color: p.text,
                                    fontWeight: FontWeight.w600,
                                    height: 1.3)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      }

      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            Row(
              children: [
                IconBadge(icon: icon, color: color, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: p.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: StatusPill(label: pillLabel, color: color),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            section('Details', Icons.info_rounded, extra),
            section('Annotations', Icons.notes_rounded, annotations),
            section('Labels', Icons.sell_rounded, labels),
          ],
        ),
      );
    },
  );
}
