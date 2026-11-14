import 'dart:async';

import 'package:flutter/material.dart';

import '../core/alert_watcher.dart';
import '../models/models.dart';
import '../state/auth_controller.dart';
import '../theme.dart';
import 'account_screen.dart';
import 'alerts_screen.dart';
import 'dashboards_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.auth, required this.watcher});
  final AuthController auth;
  final AlertWatcher watcher;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _index = 0;
  StreamSubscription<AlertInstance>? _fgSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fgSub = widget.watcher.fired.listen(_onFired);
    widget.watcher.openAlerts.addListener(_openAlerts);
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoStartWatch());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fgSub?.cancel();
    widget.watcher.openAlerts.removeListener(_openAlerts);
    widget.watcher.stop(notify: false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.watcher.state == WatchState.on) {
      widget.watcher.checkNow();
    }
  }

  Future<void> _autoStartWatch() async {
    final api = widget.auth.api;
    if (api == null || !widget.auth.watchWanted) return;
    await widget.watcher.start(api, seconds: widget.auth.watchSeconds);
  }

  void _openAlerts() {
    if (mounted) setState(() => _index = 1);
  }

  void _onFired(AlertInstance a) {
    if (!mounted) return;
    final p = Pal.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 7),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        content: Row(
          children: [
            const Icon(Icons.notifications_active_rounded, color: Pal.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name,
                      style: TextStyle(
                          color: p.text, fontWeight: FontWeight.w700)),
                  if ((a.summary ?? '').isNotEmpty)
                    Text(a.summary!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted)),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'View',
          textColor: Pal.accent,
          onPressed: () => setState(() => _index = 1),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.auth.api;
    if (api == null) return const SizedBox.shrink();

    final pages = <Widget>[
      DashboardsScreen(api: api),
      AlertsScreen(api: api, refreshOn: widget.watcher.alertTick),
      AccountScreen(auth: widget.auth, watcher: widget.watcher),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        // Icons only: cleaner, and the tooltips still name each tab.
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard_rounded),
              label: 'Dashboards',
              tooltip: 'Dashboards'),
          NavigationDestination(
              icon: Icon(Icons.notifications_none_rounded),
              selectedIcon: Icon(Icons.notifications_rounded),
              label: 'Alerts',
              tooltip: 'Alerts'),
          NavigationDestination(
              icon: Icon(Icons.account_circle_outlined),
              selectedIcon: Icon(Icons.account_circle_rounded),
              label: 'Account',
              tooltip: 'Account'),
        ],
      ),
    );
  }
}
