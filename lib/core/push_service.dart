import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, SocketException;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'grafana_api.dart';

class PushException implements Exception {
  PushException(this.message);
  final String message;
  @override
  String toString() => message;
}

enum PushState { unavailable, off, working, on }

/// Registers this device with the push backend and surfaces incoming alerts.
class PushService extends ChangeNotifier {
  PushState state = PushState.off;

  /// Last error / status text for the UI.
  String? message;

  bool _firebaseReady = false;
  GrafanaApi? _api;
  String? _backend;
  String? _token;
  StreamSubscription<String>? _refreshSub;

  final _foreground = StreamController<RemoteMessage>.broadcast();
  Stream<RemoteMessage> get foreground => _foreground.stream;

  /// Bumped whenever a push arrives while the app is open.
  final alertTick = ValueNotifier<int>(0);

  /// Bumped when the user taps a notification.
  final openAlerts = ValueNotifier<int>(0);

  Future<void>? _initFuture;

  /// Safe to call several times; the work runs once.
  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
      FirebaseMessaging.onMessage.listen(_foreground.add);
      FirebaseMessaging.onMessageOpenedApp.listen((_) => openAlerts.value++);
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) openAlerts.value++;
    } catch (_) {
      _firebaseReady = false;
      state = PushState.unavailable;
      message = 'Push notifications are not available in this build.';
      notifyListeners();
    }
  }

  bool get available => _firebaseReady;
  String? get backendUrl => _backend;

  Future<String> _fetchToken() async {
    final fm = FirebaseMessaging.instance;
    if (!kIsWeb && Platform.isIOS) {
      // iOS needs the APNs token before an FCM token can be issued.
      for (var i = 0; i < 8 && await fm.getAPNSToken() == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    }
    final t = await fm.getToken();
    if (t == null || t.isEmpty) {
      throw PushException('Could not get a device token from Firebase.');
    }
    return t;
  }

  Future<http.Response> _call(
    GrafanaApi api,
    String base,
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final req = http.Request(method, Uri.parse('$base$path'))
      ..headers['Authorization'] =
          'Basic ${base64Encode(utf8.encode('${api.username}:${api.password}'))}'
      ..headers['Content-Type'] = 'application/json';
    if (body != null) req.body = jsonEncode(body);
    try {
      final streamed =
          await req.send().timeout(const Duration(seconds: 20));
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode >= 200 && res.statusCode < 300) return res;
      String detail = 'HTTP ${res.statusCode}';
      try {
        final j = jsonDecode(res.body);
        if (j is Map && j['error'] != null) detail = '${j['error']}';
      } catch (_) {}
      throw PushException(res.statusCode == 401
          ? 'The notification server rejected your Grafana login.'
          : 'Notification server error: $detail');
    } on TimeoutException {
      throw PushException('Notification server timed out.');
    } on SocketException {
      throw PushException('Cannot reach the notification server.');
    } on http.ClientException catch (e) {
      throw PushException('Network error: ${e.message}');
    } on FormatException {
      throw PushException('The notification server URL is not valid.');
    }
  }

  /// Registers this phone. Returns true on success.
  Future<bool> enable(GrafanaApi api, String url) async {
    await init();
    if (!_firebaseReady) {
      state = PushState.unavailable;
      notifyListeners();
      return false;
    }
    state = PushState.working;
    message = null;
    notifyListeners();
    try {
      final base = GrafanaApi.normalizeUrl(url);
      final perm = await FirebaseMessaging.instance
          .requestPermission(alert: true, badge: true, sound: true);
      if (perm.authorizationStatus == AuthorizationStatus.denied) {
        throw PushException(
            'Notifications are blocked. Allow them in system settings.');
      }
      final token = await _fetchToken();
      await _call(api, base, 'POST', '/api/devices', {
        'token': token,
        'platform': !kIsWeb && Platform.isIOS ? 'ios' : 'android',
      });
      _api = api;
      _backend = base;
      _token = token;
      _refreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        final a = _api, b = _backend;
        if (a == null || b == null) return;
        _token = t;
        _call(a, b, 'POST', '/api/devices', {
          'token': t,
          'platform': !kIsWeb && Platform.isIOS ? 'ios' : 'android',
        }).catchError((_) => http.Response('', 500));
      });
      state = PushState.on;
      message = null;
      notifyListeners();
      return true;
    } catch (e) {
      state = PushState.off;
      message = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Unregisters this phone (best effort).
  Future<void> disable(GrafanaApi api) async {
    final base = _backend;
    final token = _token;
    if (base != null && token != null) {
      try {
        await _call(api, base, 'DELETE', '/api/devices', {'token': token});
      } catch (_) {}
    }
    try {
      if (_firebaseReady) await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    await _refreshSub?.cancel();
    _refreshSub = null;
    _token = null;
    state = _firebaseReady ? PushState.off : PushState.unavailable;
    message = null;
    notifyListeners();
  }

  /// Asks the backend to push a test notification to this user's devices.
  Future<void> sendTest(GrafanaApi api) async {
    final base = _backend;
    if (base == null) throw PushException('Push is not enabled.');
    await _call(api, base, 'POST', '/api/test');
  }

  @override
  void dispose() {
    _refreshSub?.cancel();
    _foreground.close();
    alertTick.dispose();
    openAlerts.dispose();
    super.dispose();
  }
}
