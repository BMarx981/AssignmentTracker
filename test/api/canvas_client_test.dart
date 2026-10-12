import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:assignment_tracker_app/api/canvas_client.dart';

/// Answers every request from [routes] (keyed by path), 404 otherwise, and
/// records the paths it saw.
class _FakeCanvas implements HttpClientAdapter {
  _FakeCanvas(this.routes);

  final Map<String, (int, Object?)> routes;
  final List<String> seen = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options.uri.path);
    final (status, body) = routes[options.uri.path] ?? (404, null);
    return ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

CanvasClient _client(_FakeCanvas fake, {String token = '2873~az23vSECRET'}) =>
    CanvasClient(
      baseUrl: 'https://canvas.test',
      token: token,
      dio: Dio()..httpClientAdapter = fake,
    );

void main() {
  test('fetchAllStudents surfaces a 401 instead of returning no students',
      () async {
    final fake = _FakeCanvas({
      '/api/v1/users/self/profile': (401, {'errors': []}),
    });
    await expectLater(
      _client(fake).fetchAllStudents(),
      throwsA(isA<DioException>().having(
          (e) => e.response?.statusCode, 'status', 401)),
    );
  });

  group('fetchTokenInfo', () {
    test('looks the token up by its hint', () async {
      final fake = _FakeCanvas({
        '/api/v1/users/self/tokens/2873~az23v': (
          200,
          {'expires_at': '2027-01-10T05:00:00Z'},
        ),
      });
      final info = await _client(fake).fetchTokenInfo();
      expect(info?['expires_at'], '2027-01-10T05:00:00Z');
      expect(fake.seen, ['/api/v1/users/self/tokens/2873~az23v']);
    });

    test('returns null when Canvas has no record for the hint', () async {
      expect(await _client(_FakeCanvas({})).fetchTokenInfo(), isNull);
    });

    test('skips the request for a token without a hint shape', () async {
      final fake = _FakeCanvas({});
      expect(await _client(fake, token: 'nohint').fetchTokenInfo(), isNull);
      expect(fake.seen, isEmpty);
    });

    test('rethrows a 401', () async {
      final fake = _FakeCanvas({
        '/api/v1/users/self/tokens/2873~az23v': (401, {'errors': []}),
      });
      await expectLater(
          _client(fake).fetchTokenInfo(), throwsA(isA<DioException>()));
    });
  });
}
