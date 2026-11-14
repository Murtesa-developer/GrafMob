import 'package:flutter_test/flutter_test.dart';
import 'package:grafmod/core/grafana_api.dart';

void main() {
  group('GrafanaApi.normalizeUrl', () {
    test('adds https and strips trailing slashes', () {
      expect(GrafanaApi.normalizeUrl('grafana.example.com//'),
          'https://grafana.example.com');
    });

    test('keeps an explicit scheme', () {
      expect(GrafanaApi.normalizeUrl(' http://10.0.0.5:3000/ '),
          'http://10.0.0.5:3000');
    });
  });

  group('GrafanaApi.checkUrl', () {
    test('accepts https', () {
      expect(GrafanaApi.checkUrl('https://grafana.example.com'), isNull);
    });

    test('rejects http unless insecure is allowed', () {
      expect(GrafanaApi.checkUrl('http://10.0.0.5:3000'), isNotNull);
      expect(
          GrafanaApi.checkUrl('http://10.0.0.5:3000', allowInsecure: true),
          isNull);
    });

    test('rejects other schemes', () {
      expect(GrafanaApi.checkUrl('ftp://example.com'), isNotNull);
      expect(GrafanaApi.checkUrl('file:///etc/passwd'), isNotNull);
    });
  });
}
