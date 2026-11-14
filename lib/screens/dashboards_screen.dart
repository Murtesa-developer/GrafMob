import 'package:flutter/material.dart';

import '../core/grafana_api.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/async_list.dart';
import '../widgets/ui.dart';
import 'dashboard_view_screen.dart';

class DashboardsScreen extends StatefulWidget {
  const DashboardsScreen({super.key, required this.api});
  final GrafanaApi api;

  @override
  State<DashboardsScreen> createState() => _DashboardsScreenState();
}

class _DashboardsScreenState extends State<DashboardsScreen> {
  final _search = TextEditingController();
  String _query = '';
  int _total = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<DashboardItem>> _load() async {
    final list = await widget.api.dashboards();
    if (mounted) setState(() => _total = list.length);
    return list;
  }

  Color _colorFor(String key) =>
      Pal.series[key.codeUnits.fold<int>(0, (a, b) => a + b) % Pal.series.length];

  void _open(DashboardItem d) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DashboardViewScreen(api: widget.api, item: d),
        ),
      );

  Widget _tile(DashboardItem d) {
    final p = Pal.of(context);
    final color = _colorFor(d.title);
    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      onTap: () => _open(d),
      child: Row(
        children: [
          IconBadge(icon: Icons.bar_chart_rounded, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.text,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700)),
                if (d.tags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final t in d.tags.take(4))
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: p.surface2,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.sell_rounded,
                                  size: 11, color: p.muted),
                              const SizedBox(width: 4),
                              Text(t,
                                  style: TextStyle(
                                      color: p.muted, fontSize: 11.5)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (d.starred)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.star_rounded, color: Pal.amber, size: 22),
            ),
          Icon(Icons.chevron_right_rounded, color: p.muted),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'Dashboards',
          subtitle: _total == 0 ? null : '$_total available',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search by name, folder or tag',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
        ),
        Expanded(
          child: AsyncList<DashboardItem>(
            load: _load,
            emptyIcon: Icons.space_dashboard_outlined,
            emptyTitle: 'No dashboards',
            emptyMessage: 'This account cannot see any dashboards yet.',
            builder: (context, all) {
              final items = _query.isEmpty
                  ? all
                  : all
                      .where((d) =>
                          d.title.toLowerCase().contains(_query) ||
                          d.folder.toLowerCase().contains(_query) ||
                          d.tags.any((t) => t.toLowerCase().contains(_query)))
                      .toList();
              if (items.isEmpty) {
                return const Center(
                  child: StateView(
                    icon: Icons.search_off_rounded,
                    title: 'No matches',
                    message: 'Try another search term.',
                  ),
                );
              }

              final starred = items.where((d) => d.starred).toList();
              final folders = <String, List<DashboardItem>>{};
              for (final d in items) {
                folders.putIfAbsent(d.folder, () => []).add(d);
              }
              final names = folders.keys.toList()
                ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  if (starred.isNotEmpty && _query.isEmpty) ...[
                    SectionLabel(
                        text: 'Starred',
                        icon: Icons.star_rounded,
                        count: starred.length),
                    for (final d in starred) _tile(d),
                  ],
                  for (final f in names) ...[
                    SectionLabel(
                        text: f,
                        icon: Icons.folder_rounded,
                        count: folders[f]!.length),
                    for (final d in folders[f]!) _tile(d),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
