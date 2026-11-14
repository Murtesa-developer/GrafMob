import 'package:flutter/material.dart';

import '../core/alarm_state.dart';
import '../models/models.dart';
import '../core/alert_watcher.dart';
import '../core/system_access.dart';
import '../state/auth_controller.dart';
import 'terms_screen.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.auth, required this.watcher});
  final AuthController auth;
  final AlertWatcher watcher;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen>
    with WidgetsBindingObserver {
  SystemStatus _sys = const SystemStatus();
  int? _dragSecs; // slider value while the finger is down

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshSystem();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshSystem();
  }

  /// Re-reads the Android settings. The alarm channel is rebuilt each time so
  /// a newly granted Do Not Disturb override takes effect.
  Future<void> _refreshSystem() async {
    if (!SystemAccess.supported) return;
    await SystemAccess.setupCriticalChannel();
    final s = await SystemAccess.status();
    if (mounted) setState(() => _sys = s);
  }

  AuthController get auth => widget.auth;
  AlertWatcher get watcher => widget.watcher;

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          Icon(error ? Icons.error_rounded : Icons.check_circle_rounded,
              color: error ? Pal.red : Pal.green),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ]),
      ));
  }

  Future<void> _toggle(bool on) async {
    final api = auth.api;
    if (api == null) return;
    if (on) {
      final ok = await watcher.start(api);
      await auth.setWatch(ok);
      if (ok) {
        _toast('Alarms are on. GrafMod is watching your alerts.');
      } else {
        _toast(watcher.message ?? 'Could not turn alarms on', error: true);
      }
    } else {
      watcher.stop();
      await watcher.shutdownBackground();
      await auth.setWatch(false);
    }
  }

  Future<void> _testCritical() async {
    await watcher.sendTestCritical();
    _toast('Critical test alarm sent');
  }

  Widget _accessRow(BuildContext context,
      {required IconData icon,
      required String title,
      required String okText,
      required String fixText,
      required bool ok,
      required VoidCallback onFix}) {
    final p = Pal.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: ok ? Pal.green : Pal.amber),
      title: Text(title, style: TextStyle(color: p.text)),
      subtitle: Text(ok ? okText : fixText, style: TextStyle(color: p.muted)),
      trailing: ok
          ? const Icon(Icons.check_circle_rounded, color: Pal.green)
          : TextButton(onPressed: onFix, child: const Text('Allow')),
    );
  }

  Widget _intervalRow(BuildContext context) {
    final p = Pal.of(context);
    final secs = _dragSecs ?? auth.watchSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.timer_outlined, color: p.muted),
            const SizedBox(width: 16),
            Expanded(
              child: Text('Check every', style: TextStyle(color: p.text)),
            ),
            Text(formatWatchSeconds(secs),
                style: const TextStyle(
                    color: Pal.accent, fontWeight: FontWeight.w700)),
          ],
        ),
        Slider(
          min: minWatchSeconds.toDouble(),
          max: maxWatchSeconds.toDouble(),
          divisions: (maxWatchSeconds - minWatchSeconds) ~/ watchStepSeconds,
          value: secs.toDouble(),
          label: formatWatchSeconds(secs),
          onChanged: (v) => setState(() => _dragSecs = v.round()),
          onChangeEnd: (v) async {
            final s = v.round();
            await auth.setWatchSeconds(s);
            watcher.setIntervalSeconds(s);
            if (mounted) setState(() => _dragSecs = null);
          },
        ),
        Text(
            'Shorter times find problems sooner but use more battery. '
            'Works while the app is closed too.',
            style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.35)),
      ],
    );
  }

  Future<void> _test() async {
    await watcher.sendTest();
    _toast('Test alarm sent');
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.logout_rounded, color: Pal.red),
        title: const Text('Sign out?'),
        content: const Text('Alarms stop on this device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                minimumSize: const Size(110, 44), backgroundColor: Pal.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    watcher.stop();
    await watcher.shutdownBackground();
    await auth.logout();
  }

  Widget _row(BuildContext context, IconData icon, String label, String value,
      {Color? color}) {
    final p = Pal.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          IconBadge(icon: icon, color: color ?? Pal.blue, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: p.muted, fontSize: 12.5)),
                const SizedBox(height: 2),
                Text(value.isEmpty ? '-' : value,
                    style: TextStyle(
                        color: p.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([auth, watcher]),
      builder: (context, _) {
        final user = auth.user;
        final display = user == null
            ? (auth.savedUser ?? '')
            : (user.name.isEmpty ? user.login : user.name);
        final initial =
            display.isEmpty ? '?' : display.substring(0, 1).toUpperCase();

        final working = watcher.state == WatchState.starting;
        final on = watcher.state == WatchState.on;
        final blocked = watcher.state == WatchState.blocked;

        final (pillLabel, pillColor, pillIcon) = switch (watcher.state) {
          WatchState.on => ('Watching', Pal.green, Icons.check_circle_rounded),
          WatchState.starting =>
            ('Starting', Pal.amber, Icons.sync_rounded),
          WatchState.blocked =>
            ('Blocked', Pal.red, Icons.block_rounded),
          WatchState.off =>
            ('Off', p.muted, Icons.notifications_off_rounded),
        };

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            const PageHeader(title: 'Account'),
            const SizedBox(height: 18),
            AppCard(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: Pal.brand,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(initial,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(display,
                            style: TextStyle(
                                color: p.text,
                                fontSize: 19,
                                fontWeight: FontWeight.w800)),
                        if (user != null && user.email.isNotEmpty)
                          Text(user.email,
                              style: TextStyle(color: p.muted, fontSize: 13.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: _row(context, Icons.dns_rounded, 'Grafana server',
                  auth.api?.baseUrl ?? ''),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const IconBadge(
                          icon: Icons.notifications_active_rounded,
                          color: Pal.accent,
                          size: 40),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text('Alert alarms',
                            style: TextStyle(
                                color: p.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                      ),
                      StatusPill(
                          label: pillLabel, color: pillColor, icon: pillIcon),
                    ],
                  ),
                  if (watcher.message != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_rounded,
                            size: 18, color: blocked ? Pal.red : Pal.amber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(watcher.message!,
                              style: TextStyle(color: p.muted, height: 1.35)),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: on || working,
                    onChanged: working ? null : (v) => _toggle(v),
                    title: Text('Watch alerts',
                        style: TextStyle(color: p.text)),
                    subtitle: Text(
                        watcher.inBackground
                            ? 'GrafMod checks Grafana every ${formatWatchSeconds(auth.watchSeconds)} and '
                                'sounds an alarm when an alert starts firing, '
                                'even when the app is closed. A small '
                                'notification stays visible while it runs.'
                            : 'GrafMod checks Grafana every ${formatWatchSeconds(auth.watchSeconds)} and '
                                'sounds an alarm when an alert starts firing. '
                                'Works while the app is running.',
                        style: TextStyle(color: p.muted)),
                    secondary: Icon(Icons.campaign_rounded, color: p.muted),
                  ),
                  const SizedBox(height: 4),
                  _intervalRow(context),
                  if (on && watcher.lastCheck != null) ...[
                    Divider(color: p.outline),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.schedule_rounded, color: p.muted),
                      title: Text('Last check',
                          style: TextStyle(color: p.text)),
                      subtitle: Text(timeAgo(watcher.lastCheck!),
                          style: TextStyle(color: p.muted)),
                    ),
                  ],
                  if (on) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: Pal.accent,
                        side: BorderSide(color: Pal.accent.withOpacity(0.5)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _test,
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Send test alarm'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (SystemAccess.supported) ...[
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const IconBadge(
                            icon: Icons.crisis_alert_rounded,
                            color: Pal.red,
                            size: 40),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text('Critical alarm',
                              style: TextStyle(
                                  color: p.text,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                        'Critical alerts ring loudly and keep ringing until '
                        'you open them, like an alarm clock.',
                        style: TextStyle(color: p.muted, height: 1.35)),
                    const SizedBox(height: 6),
                    _accessRow(context,
                        icon: Icons.do_not_disturb_off_rounded,
                        title: 'Ring in Do Not Disturb',
                        okText: 'Critical alarms can break through',
                        fixText: 'Allow GrafMod to override Do Not Disturb',
                        ok: _sys.dndOverride,
                        onFix: SystemAccess.openDndAccess),
                    Divider(color: p.outline),
                    _accessRow(context,
                        icon: Icons.battery_charging_full_rounded,
                        title: 'Battery optimisation',
                        okText: 'Unrestricted, GrafMod can keep watching',
                        fixText: 'Stop Android from pausing GrafMod',
                        ok: _sys.batteryUnrestricted,
                        onFix: SystemAccess.requestIgnoreBattery),
                    if (!_sys.fullScreen) ...[
                      Divider(color: p.outline),
                      _accessRow(context,
                          icon: Icons.fullscreen_rounded,
                          title: 'Full-screen alarm',
                          okText: 'Allowed',
                          fixText: 'Wake the screen when a critical alert fires',
                          ok: _sys.fullScreen,
                          onFix: SystemAccess.openFullScreenSettings),
                    ],
                    if (watcher.state == WatchState.on) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: Pal.red,
                          side: BorderSide(color: Pal.red.withOpacity(0.5)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _testCritical,
                        icon: const Icon(Icons.volume_up_rounded),
                        label: const Text('Test critical alarm'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            AppCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.info_rounded, color: p.muted),
                title:
                    Text('About GrafMod', style: TextStyle(color: p.text)),
                subtitle: Text('Open source, MIT License',
                    style: TextStyle(color: p.muted)),
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'GrafMod',
                  applicationVersion: '1.0.0',
                  applicationLegalese:
                      'Developed by Murtesa\nReleased under the MIT License.\n\n'
                      'GrafMod is an independent project and is not affiliated '
                      'with or endorsed by Grafana Labs.',
                ),
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.gavel_rounded, color: p.muted),
                title: Text('Terms of Use', style: TextStyle(color: p.text)),
                trailing: Icon(Icons.chevron_right_rounded, color: p.muted),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TermsScreen()),
                ),
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: Pal.red,
                side: BorderSide(color: Pal.red.withOpacity(0.5)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _signOut,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ],
        );
      },
    );
  }
}
