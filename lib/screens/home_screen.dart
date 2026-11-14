import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../core/push_service.dart';
import '../state/auth_controller.dart';
import '../theme.dart';
import 'account_screen.dart';
import 'alerts_screen.dart';
import 'dashboards_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.auth, required this.push});
  final AuthController auth;
  final PushService push;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  StreamSubscription<RemoteMessage>? _fgSub;

  @override
  void initState() {
    super.initState();
    _fgSub = widget.push.foreground.listen(_onForeground);
    widget.push.openAlerts.addListener(_openAlerts);
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoEnablePush());
  }

  @override
  void dispose() {
    _fgSub?.cancel();
    widget.push.openAlerts.removeListener(_openAlerts);
    super.dispose();
  }

  Future<void> _autoEnablePush() async {
    final api = widget.auth.api;
    final url = widget.auth.backendUrl;
    if (api == null || url == null || !widget.auth.pushWanted) return;
    await widget.push.enable(api, url);
  }

  void _openAlerts() {
    if (mounted) setState(() => _index = 1);
  }

  void _onForeground(RemoteMessage m) {
    widget.push.alertTick.value++;
    final n = m.notification;
    if (!mounted || n == null) return;
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
                  Text(n.title ?? 'Alert',
                      style: TextStyle(
                          color: p.text, fontWeight: FontWeight.w700)),
                  if ((n.body ?? '').isNotEmpty)
                    Text(n.body!,
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
      AlertsScreen(api: api, refreshOn: widget.push.alertTick),
      AccountScreen(auth: widget.auth, push: widget.push),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard_rounded),
              label: 'Dashboards'),
          NavigationDestination(
              icon: Icon(Icons.notifications_none_rounded),
              selectedIcon: Icon(Icons.notifications_rounded),
              label: 'Alerts'),
          NavigationDestination(
              icon: Icon(Icons.account_circle_outlined),
              selectedIcon: Icon(Icons.account_circle_rounded),
              label: 'Account'),
        ],
      ),
    );
  }
}
