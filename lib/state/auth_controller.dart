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
  static const _kWatch = 'watch_alerts';
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

  /// Whether the app should watch alerts and sound alarms (on by default).
  bool watchWanted = true;

  /// True only when the user explicitly allowed plain http:// servers.
  bool allowInsecure = false;

  Future<void> restore() async {
    try {
      final url = await _storage.read(key: _kUrl);
      final u = await _storage.read(key: _kUser);
      final p = await _storage.read(key: _kPass);
      watchWanted = (await _storage.read(key: _kWatch)) != 'false';
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
    bool allowInsecure = false,
  }) async {
    final problem = GrafanaApi.checkUrl(url, allowInsecure: allowInsecure);
    if (problem != null) throw GrafanaException(problem);
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
    try {
      await _storage.write(key: _kUrl, value: candidate.baseUrl);
      await _storage.write(key: _kUser, value: username);
      await _storage.write(key: _kPass, value: password);
      await _storage.write(key: _kInsecure, value: allowInsecure ? 'true' : 'false');
    } catch (_) {
      // Storage failure should not block use of the app this session.
    }
    status = AuthStatus.loggedIn;
    notifyListeners();
  }

  Future<void> setWatch(bool on) async {
    watchWanted = on;
    try {
      await _storage.write(key: _kWatch, value: on ? 'true' : 'false');
    } catch (_) {}
    notifyListeners();
  }

  Future<void> logout() async {
    api?.close();
    api = null;
    user = null;
    try {
      await _storage.delete(key: _kPass);
    } catch (_) {}
    try {
      // Drop the Grafana web session held by the dashboard WebView.
      await WebViewCookieManager().clearCookies();
    } catch (_) {}
    status = AuthStatus.loggedOut;
    notifyListeners();
  }
}
