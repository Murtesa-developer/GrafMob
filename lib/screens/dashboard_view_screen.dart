import 'dart:convert';

import 'package:flutter/material.dart';
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
            if (e.isForMainFrame == true && mounted) {
              setState(() {
                _error = 'Could not load the page: ${e.description}';
                _loading = false;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse('${widget.api.baseUrl}/login'));
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
        if (mounted) {
          setState(() {
            _error = 'Login failed: $e';
            _loading = false;
          });
        }
      }
      return;
    }
    if (mounted && _error == null) setState(() => _loading = false);
  }

  void _onAuth(JavaScriptMessage m) {
    if (!mounted) return;
    if (m.message == 'ok') {
      _controller.loadRequest(Uri.parse(_dashUrl));
    } else {
      setState(() {
        _error = 'Could not open a web session (${m.message}).';
        _loading = false;
      });
    }
  }

  void _reload() {
    setState(() {
      _error = null;
      _loading = true;
    });
    _controller.loadRequest(Uri.parse(_dashUrl));
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
