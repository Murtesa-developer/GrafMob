import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/grafana_api.dart';
import '../models/models.dart';

enum AuthStatus { unknown, loggedOut, loggedIn }

class AuthController extends ChangeNotifier {
  static const _kUrl = 'grafana_url';
  static const _kUser = 'grafana_user';
  static const _kPass = 'grafana_pass';
  static const _kPushUrl = 'push_backend_url';
  static const _kPushOn = 'push_wanted';
  static const _kInsecure = 'allow_insecure';

  // Credentials live in the Android Keystore / iOS Keychain, are readable only
  // after first unlock and never leave this device.
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  AuthStatus status = AuthStatus.unknown;
  GrafanaApi? api;
  GrafanaUser? user;

  String? savedUrl;
  String? savedUser;

  /// Notification backend URL and whether push should be active.
  String? backendUrl;
  bool pushWanted = false;

  /// True only when the user explicitly allowed plain http:// servers.
  bool allowInsecure = false;

  Future<void> restore() async {
    try {
      final url = await _storage.read(key: _kUrl);
      final u = await _storage.read(key: _kUser);
      final p = await _storage.read(key: _kPass);
      backendUrl = await _storage.read(key: _kPushUrl);
      pushWanted = (await _storage.read(key: _kPushOn)) == 'true';
      allowInsecure = (await _storage.read(key: _kInsecure)) == 'true';
      savedUrl = url;
      savedUser = u;
      if (url == null || u == null || p == null) {
        status = AuthStatus.loggedOut;
        notifyListeners();
        return;
      }
      final candidate = GrafanaApi(baseUrl: url, username: u, password: p);
      api = candidate;
      status = AuthStatus.loggedIn;
      notifyListeners();
      try {
        user = await candidate.currentUser();
        notifyListeners();
      } on GrafanaAuthException {
        await logout();
      } catch (_) {
        // Offline or server unreachable: stay signed in, screens show errors.
      }
    } catch (_) {
      status = AuthStatus.loggedOut;
      notifyListeners();
    }
  }

  /// Throws [GrafanaException] when the login fails.
  Future<void> login(
    String url,
    String username,
    String password, {
    String? pushUrl,
    bool allowInsecure = false,
  }) async {
    final problem = GrafanaApi.checkUrl(url, allowInsecure: allowInsecure);
    if (problem != null) throw GrafanaException(problem);
    final pushText = (pushUrl ?? '').trim();
    if (pushText.isNotEmpty) {
      final pushProblem =
          GrafanaApi.checkUrl(pushText, allowInsecure: allowInsecure);
      if (pushProblem != null) {
        throw GrafanaException('Notification server: $pushProblem');
      }
    }
    final candidate =
        GrafanaApi(baseUrl: url, username: username, password: password);
    try {
      user = await candidate.currentUser();
    } catch (_) {
      candidate.close();
      rethrow;
    }
    api?.close();
    api = candidate;
    savedUrl = candidate.baseUrl;
    savedUser = username;
    this.allowInsecure = allowInsecure;
    final push = (pushUrl ?? '').trim();
    backendUrl = push.isEmpty ? null : GrafanaApi.normalizeUrl(push);
    pushWanted = backendUrl != null;
    try {
      await _storage.write(key: _kUrl, value: candidate.baseUrl);
      await _storage.write(key: _kUser, value: username);
      await _storage.write(key: _kPass, value: password);
      await _storage.write(key: _kInsecure, value: allowInsecure ? 'true' : 'false');
      await _writePush();
    } catch (_) {
      // Storage failure should not block use of the app this session.
    }
    status = AuthStatus.loggedIn;
    notifyListeners();
  }

  Future<void> setPush(String? url, bool on) async {
    backendUrl = (url == null || url.trim().isEmpty)
        ? null
        : GrafanaApi.normalizeUrl(url);
    pushWanted = on && backendUrl != null;
    try {
      await _writePush();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _writePush() async {
    if (backendUrl == null) {
      await _storage.delete(key: _kPushUrl);
    } else {
      await _storage.write(key: _kPushUrl, value: backendUrl);
    }
    await _storage.write(key: _kPushOn, value: pushWanted ? 'true' : 'false');
  }

  Future<void> logout() async {
    api?.close();
    api = null;
    user = null;
    pushWanted = false;
    try {
      await _storage.delete(key: _kPass);
      await _storage.write(key: _kPushOn, value: 'false');
    } catch (_) {}
    try {
      // Drop the Grafana web session held by the dashboard WebView.
      await WebViewCookieManager().clearCookies();
    } catch (_) {}
    status = AuthStatus.loggedOut;
    notifyListeners();
  }
}
