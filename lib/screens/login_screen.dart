import 'package:flutter/material.dart';

import '../state/auth_controller.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});
  final AuthController auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _url = TextEditingController(text: widget.auth.savedUrl ?? '');
  late final _user = TextEditingController(text: widget.auth.savedUser ?? '');
  late final _push = TextEditingController(text: widget.auth.backendUrl ?? '');
  final _pass = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  bool _allowInsecure = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _push.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.login(
        _url.text,
        _user.text.trim(),
        _pass.text,
        pushUrl: _push.text,
        allowInsecure: _allowInsecure,
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -1.05),
                  radius: 1.15,
                  colors: [
                    Pal.accent.withOpacity(p.isDark ? 0.30 : 0.20),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('GrafMod',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: p.text,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8)),
                        const SizedBox(height: 6),
                        Text('Sign in to your Grafana server',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: p.muted, fontSize: 15)),
                        const SizedBox(height: 28),
                        AppCard(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _url,
                                keyboardType: TextInputType.url,
                                autocorrect: false,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Server URL',
                                  hintText: 'https://grafana.example.com',
                                  prefixIcon: Icon(Icons.dns_rounded),
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? 'Enter your Grafana URL'
                                        : null,
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: Text('Allow insecure HTTP',
                                    style: TextStyle(color: p.text)),
                                subtitle: Text(
                                    'Only for servers on a network you trust',
                                    style: TextStyle(color: p.muted)),
                                value: _allowInsecure,
                                onChanged: (v) =>
                                    setState(() => _allowInsecure = v),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _user,
                                autocorrect: false,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                  prefixIcon: Icon(Icons.person_rounded),
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                        ? 'Enter your username'
                                        : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _pass,
                                obscureText: _obscure,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_rounded),
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscure
                                        ? Icons.visibility_rounded
                                        : Icons.visibility_off_rounded),
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                ),
                                validator: (v) => (v == null || v.isEmpty)
                                    ? 'Enter your password'
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        AppCard(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const IconBadge(
                                      icon: Icons.notifications_active_rounded,
                                      color: Pal.accent,
                                      size: 40),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('Push notifications',
                                            style: TextStyle(
                                                color: p.text,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15)),
                                        Text('Optional. Alerts on your phone.',
                                            style: TextStyle(
                                                color: p.muted, fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _push,
                                keyboardType: TextInputType.url,
                                autocorrect: false,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                decoration: const InputDecoration(
                                  labelText: 'Notification server URL',
                                  hintText: 'https://push.example.com',
                                  prefixIcon: Icon(Icons.cell_tower_rounded),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Pal.red.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_rounded,
                                    color: Pal.red, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(_error!,
                                      style: const TextStyle(color: Pal.red)),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        GradientButton(
                          label: 'Sign in',
                          icon: Icons.login_rounded,
                          busy: _busy,
                          onPressed: _submit,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
