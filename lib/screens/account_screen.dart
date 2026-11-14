import 'package:flutter/material.dart';

import '../core/grafana_api.dart';
import '../core/push_service.dart';
import '../state/auth_controller.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.auth, required this.push});
  final AuthController auth;
  final PushService push;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _testing = false;

  AuthController get auth => widget.auth;
  PushService get push => widget.push;

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

  Future<String?> _askUrl({String? initial}) {
    final c = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.cell_tower_rounded, color: Pal.accent),
        title: const Text('Notification server'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(
            hintText: 'https://push.example.com',
            prefixIcon: Icon(Icons.link_rounded),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _enableWith(String url) async {
    final api = auth.api;
    if (api == null) return;
    final problem =
        GrafanaApi.checkUrl(url, allowInsecure: auth.allowInsecure);
    if (problem != null) {
      _toast(problem, error: true);
      return;
    }
    final ok = await push.enable(api, url);
    if (ok) {
      await auth.setPush(url, true);
      _toast('Push notifications are on');
    } else {
      await auth.setPush(url, false);
      _toast(push.message ?? 'Could not enable push', error: true);
    }
  }

  Future<void> _toggle(bool on) async {
    final api = auth.api;
    if (api == null) return;
    if (on) {
      var url = auth.backendUrl;
      if (url == null || url.isEmpty) {
        url = await _askUrl();
        if (url == null || url.isEmpty) return;
      }
      await _enableWith(url);
    } else {
      await push.disable(api);
      await auth.setPush(auth.backendUrl, false);
    }
  }

  Future<void> _editUrl() async {
    final url = await _askUrl(initial: auth.backendUrl);
    if (url == null || url.isEmpty) return;
    await _enableWith(url);
  }

  Future<void> _test() async {
    final api = auth.api;
    if (api == null) return;
    setState(() => _testing = true);
    try {
      await push.sendTest(api);
      _toast('Test notification sent');
    } catch (e) {
      _toast(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.logout_rounded, color: Pal.red),
        title: const Text('Sign out?'),
        content: const Text('Push notifications stop on this device.'),
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
    final api = auth.api;
    if (api != null) await push.disable(api);
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
      listenable: Listenable.merge([auth, push]),
      builder: (context, _) {
        final user = auth.user;
        final display = user == null
            ? (auth.savedUser ?? '')
            : (user.name.isEmpty ? user.login : user.name);
        final initial =
            display.isEmpty ? '?' : display.substring(0, 1).toUpperCase();

        final working = push.state == PushState.working;
        final on = push.state == PushState.on;
        final unavailable = push.state == PushState.unavailable;

        final (pillLabel, pillColor, pillIcon) = switch (push.state) {
          PushState.on => ('Active', Pal.green, Icons.check_circle_rounded),
          PushState.working => ('Connecting', Pal.amber, Icons.sync_rounded),
          PushState.unavailable =>
            ('Unavailable', Pal.red, Icons.block_rounded),
          PushState.off => ('Off', p.muted, Icons.notifications_off_rounded),
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
                        child: Text('Push notifications',
                            style: TextStyle(
                                color: p.text,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                      ),
                      StatusPill(
                          label: pillLabel, color: pillColor, icon: pillIcon),
                    ],
                  ),
                  if (push.message != null && !on) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_rounded,
                            size: 18, color: unavailable ? Pal.red : Pal.amber),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(push.message!,
                              style: TextStyle(color: p.muted, height: 1.35)),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: on || working,
                    onChanged:
                        (working || unavailable) ? null : (v) => _toggle(v),
                    title: Text('Receive alerts',
                        style: TextStyle(color: p.text)),
                    secondary: Icon(Icons.campaign_rounded, color: p.muted),
                  ),
                  Divider(color: p.outline),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.cell_tower_rounded, color: p.muted),
                    title: Text('Notification server',
                        style: TextStyle(color: p.text)),
                    subtitle: Text(auth.backendUrl ?? 'Not set',
                        style: TextStyle(color: p.muted)),
                    trailing: Icon(Icons.edit_rounded, color: p.muted),
                    onTap: unavailable || working ? null : _editUrl,
                  ),
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
                      onPressed: _testing ? null : _test,
                      icon: _testing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded),
                      label: const Text('Send test notification'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
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
