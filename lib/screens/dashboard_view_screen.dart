import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

import '../core/grafana_api.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Shows a real Grafana dashboard. A web session is created by posting the
/// credentials to Grafana's /login endpoint from inside the WebView, then the
/// dashboard is opened in kiosk mode.
class DashboardViewScreen extends StatefulWidget {
  const DashboardViewScreen({super.key, required this.api, required this.item});
  final GrafanaApi api;
  final DashboardItem item;

  @override
  State<DashboardViewScreen> createState() => _DashboardViewScreenState();
}

class _DashboardViewScreenState extends State<DashboardViewScreen> {
  late final WebViewController _controller;
  bool _loginSent = false;
  bool _sessionOk = false;
  bool _retried = false;
  int _navFixes = 0;
  bool _fallbackUsed = false;
  bool _loading = true;
  String? _error;

  String get _dashUrl =>
      '${widget.api.baseUrl}/d/${Uri.encodeComponent(widget.item.uid)}?kiosk';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel('Auth', onMessageReceived: _onAuth)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onPageFinished: _onPageFinished,
          onWebResourceError: (e) {
            if (e.isForMainFrame != true) return;
            // -3 (Android ERR_ABORTED) and -999 (iOS cancelled) just mean one
            // navigation replaced another. That is normal here, not a failure.
            if (e.errorCode == -3 || e.errorCode == -999) return;
            _fail('Could not load the page: ${e.description}');
          },
        ),
      );
    _start();
  }

  /// Signs in from the start. The session is created with a normal HTTP
  /// request and handed to the WebView as cookies, so Grafana's login page
  /// (and its home-page redirect) is never opened. If that does not work, the
  /// old way is used: sign in from inside the WebView.
  Future<void> _start() async {
    _loginSent = false;
    _sessionOk = false;
    _navFixes = 0;
    if (await _nativeLogin()) {
      _loginSent = true;
      _sessionOk = true;
      await _controller.loadRequest(Uri.parse(_dashUrl));
    } else {
      _restartWeb();
    }
  }

  void _restartWeb() {
    _loginSent = false;
    _sessionOk = false;
    _navFixes = 0;
    _controller.loadRequest(Uri.parse('${widget.api.baseUrl}/login'));
  }

  void _restart() => _start();

  Future<bool> _nativeLogin() async {
    try {
      final base = Uri.parse(widget.api.baseUrl);
      final res = await http
          .post(
            Uri.parse('${widget.api.baseUrl}/login'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'user': widget.api.username,
              'password': widget.api.password,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode < 200 || res.statusCode >= 300) return false;
      final raw = res.headers['set-cookie'];
      if (raw == null || raw.isEmpty) return false;
      final mgr = WebViewCookieManager();
      var any = false;
      // Several Set-Cookie headers arrive joined by commas; dates contain a
      // comma too, so only split where a new "name=" follows.
      for (final part in raw.split(RegExp(r',(?=\s*[A-Za-z0-9_\-]+=)'))) {
        final nv = part.split(';').first.trim();
        final i = nv.indexOf('=');
        if (i <= 0) continue;
        final value = nv.substring(i + 1);
        if (value.isEmpty) continue;
        await mgr.setCookie(WebViewCookie(
          name: nv.substring(0, i),
          value: value,
          domain: base.host,
          path: '/',
        ));
        any = true;
      }
      return any;
    } catch (_) {
      return false;
    }
  }

  /// Retries once on its own before showing the error screen.
  void _fail(String message) {
    if (!mounted) return;
    if (!_retried) {
      _retried = true;
      _restart();
      return;
    }
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  /// Only pages on the signed-in Grafana server may load in the WebView.
  /// Anything else (external links, other schemes) is blocked.
  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final target = Uri.tryParse(request.url);
    final base = Uri.parse(widget.api.baseUrl);
    if (target == null) return NavigationDecision.prevent;
    if (target.scheme == 'about' ||
        target.scheme == 'blob' ||
        target.scheme == 'data') {
      return NavigationDecision.navigate;
    }
    final sameOrigin = target.scheme == base.scheme &&
        target.host == base.host &&
        target.port == base.port;
    return sameOrigin
        ? NavigationDecision.navigate
        : NavigationDecision.prevent;
  }

  Future<void> _onPageFinished(String url) async {
    if (!_loginSent) {
      _loginSent = true;
      final body = jsonEncode({
        'user': widget.api.username,
        'password': widget.api.password,
      });
      final js = '''
fetch(${jsonEncode('${widget.api.baseUrl}/login')}, {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: ${jsonEncode(body)},
  credentials: 'include'
}).then(function(r){ Auth.postMessage(r.ok ? 'ok' : 'fail:' + r.status); })
  .catch(function(e){ Auth.postMessage('fail:' + e); });
''';
      try {
        await _controller.runJavaScript(js);
      } catch (e) {
        _fail('Login failed: $e');
      }
      return;
    }
    // If this is not the chosen dashboard, fix it: a login page means the
    // cookies were not accepted (sign in inside the WebView instead), and the
    // home page means Grafana redirected us (open the dashboard again).
    if (_sessionOk) {
      final cur = await _controller.currentUrl();
      final want = '/d/${Uri.encodeComponent(widget.item.uid)}';
      if (cur != null && !cur.contains(want)) {
        if (cur.contains('/login') && !_fallbackUsed) {
          _fallbackUsed = true;
          _restartWeb();
          return;
        }
        if (_navFixes < 3) {
          _navFixes++;
          _controller.loadRequest(Uri.parse(_dashUrl));
          return;
        }
      }
    }
    // Grafana is a single-page app: this event fires while its own loading
    // screen (the animated Grafana logo) is still showing. Hide that screen
    // and the footer, then keep our cover up until panels are drawn.
    try {
      await _controller.runJavaScript('''
(function(){
  if (window.__gmClean) return;
  window.__gmClean = true;
  var s = document.createElement('style');
  s.textContent = 'footer, [data-testid="footer"], [class*="footer" i], .preloader { display: none !important; }';
  document.head.appendChild(s);
  var re = /powered by grafana/i;
  function sweep(){
    var nodes = document.querySelectorAll('a, span, div, li, p');
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i];
      if (n.__gmHidden || n.children.length > 2) continue;
      var t = (n.textContent || '').trim();
      if (t.length < 80 && re.test(t)) {
        var el = n;
        while (el.parentElement && el.parentElement !== document.body &&
               (el.parentElement.textContent || '').trim().length < 80) {
          el = el.parentElement;
        }
        el.style.setProperty('display', 'none', 'important');
        n.__gmHidden = true;
      }
    }
  }
  sweep();
  var pending = false;
  new MutationObserver(function(){
    if (pending) return;
    pending = true;
    setTimeout(function(){ pending = false; sweep(); }, 200);
  }).observe(document.documentElement, {childList: true, subtree: true});
})();
''');
    } catch (_) {}
    await _waitUntilRendered();
    if (mounted && _error == null) setState(() => _loading = false);
  }

  /// Waits (at most ~8s) until the dashboard has drawn its panels.
  Future<void> _waitUntilRendered() async {
    const probe = '''
(function(){
  return !!document.querySelector(
    '.react-grid-item, [data-testid^="data-testid Panel"], [data-testid*="Panel header"]'
  );
})();
''';
    for (var i = 0; i < 32; i++) {
      if (!mounted) return;
      try {
        final r = await _controller.runJavaScriptReturningResult(probe);
        if (r.toString().toLowerCase().contains('true')) {
          // Let the first frame paint so no spinner flashes through.
          await Future<void>.delayed(const Duration(milliseconds: 250));
          return;
        }
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  void _onAuth(JavaScriptMessage m) {
    if (!mounted) return;
    if (m.message == 'ok') {
      _sessionOk = true;
      _controller.loadRequest(Uri.parse(_dashUrl));
    } else {
      _fail('Could not open a web session (${m.message}).');
    }
  }

  void _reload() {
    setState(() {
      _error = null;
      _loading = true;
    });
    _navFixes = 0;
    if (_sessionOk) {
      _controller.loadRequest(Uri.parse(_dashUrl));
    } else {
      _retried = true;
      _restart();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(widget.item.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload',
            onPressed: _reload,
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _loading
              ? const LinearProgressIndicator(minHeight: 2)
              : Divider(height: 2, color: p.outline),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          // Cover the WebView while it signs in and loads, so Grafana's login
          // page never flashes on screen.
          if (_loading && _error == null)
            Positioned.fill(
              child: ColoredBox(
                color: p.bg,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
          if (_error != null)
            Container(
              color: p.bg,
              alignment: Alignment.center,
              child: StateView(
                icon: Icons.error_outline_rounded,
                color: Pal.red,
                title: 'Dashboard unavailable',
                message: _error,
                onAction: _reload,
              ),
            ),
        ],
      ),
    );
  }
}
