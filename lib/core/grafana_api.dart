import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/models.dart';

class GrafanaException implements Exception {
  GrafanaException(this.message);
  final String message;
  @override
  String toString() => message;
}

class GrafanaAuthException extends GrafanaException {
  GrafanaAuthException() : super('Invalid username or password.');
}

/// Thin client over the Grafana HTTP API using HTTP Basic auth.
class GrafanaApi {
  GrafanaApi({
    required String baseUrl,
    required this.username,
    required this.password,
    http.Client? client,
  })  : baseUrl = normalizeUrl(baseUrl),
        _client = client ?? http.Client();

  final String baseUrl;
  final String username;
  final String password;
  final http.Client _client;

  static String normalizeUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return url;
    if (!url.contains('://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// Returns an error message when [input] must not be used, otherwise null.
  /// Only http(s) is accepted, and plain http only when [allowInsecure] is set.
  static String? checkUrl(String input, {bool allowInsecure = false}) {
    final uri = Uri.tryParse(normalizeUrl(input));
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return 'Enter a valid server URL starting with https://';
    }
    if (uri.scheme == 'http' && !allowInsecure) {
      return 'Plain http:// is not secure. Use https://, or turn on '
          '"Allow insecure HTTP" if you trust this network.';
    }
    return null;
  }

  Map<String, String> get _headers => {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$username:$password'))}',
        'Accept': 'application/json',
      };

  Future<dynamic> _get(String path, [Map<String, String>? query]) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    http.Response res;
    try {
      res = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw GrafanaException('Connection timed out. Check the server URL.');
    } on SocketException {
      throw GrafanaException('Cannot reach the server. Check URL and network.');
    } on HandshakeException {
      throw GrafanaException(
          'TLS/SSL error. The server certificate is not trusted.');
    } on http.ClientException catch (e) {
      throw GrafanaException('Network error: ${e.message}');
    } on FormatException {
      throw GrafanaException('The server URL is not valid.');
    }
    if (res.statusCode == 401) throw GrafanaAuthException();
    if (res.statusCode == 403) {
      throw GrafanaException('Access denied (403). Your user lacks permission.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw GrafanaException('Server returned HTTP ${res.statusCode} for $path');
    }
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw GrafanaException(
          'Unexpected response from server. Is this a Grafana URL?');
    }
  }

  /// Validates credentials and returns the signed in user.
  Future<GrafanaUser> currentUser() async {
    final json = await _get('/api/user');
    if (json is! Map<String, dynamic>) {
      throw GrafanaException('Unexpected response from /api/user');
    }
    return GrafanaUser.fromJson(json);
  }

  Future<List<DashboardItem>> dashboards({String? query}) async {
    final json = await _get('/api/search', {
      'type': 'dash-db',
      'limit': '5000',
      if (query != null && query.isNotEmpty) 'query': query,
    });
    return (json as List)
        .map((e) => DashboardItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Active alert instances from Grafana's built-in Alertmanager.
  Future<List<AlertInstance>> alerts() async {
    final json = await _get('/api/alertmanager/grafana/api/v2/alerts');
    final list = (json as List)
        .map((e) => AlertInstance.fromJson(e as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => b.startsAt.compareTo(a.startsAt));
    return list;
  }

  /// Grafana-managed alert rules with their current state.
  Future<List<AlertRule>> rules() async {
    final json = await _get('/api/prometheus/grafana/api/v1/rules');
    final groups = ((json as Map)['data']?['groups'] as List?) ?? const [];
    final out = <AlertRule>[];
    for (final g in groups) {
      final group = g as Map<String, dynamic>;
      final folder = (group['file'] ?? '').toString();
      for (final r in (group['rules'] as List? ?? const [])) {
        out.add(AlertRule.fromJson(r as Map<String, dynamic>, folder));
      }
    }
    out.sort((a, b) {
      final c = a.severityRank.compareTo(b.severityRank);
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  void close() => _client.close();
}
