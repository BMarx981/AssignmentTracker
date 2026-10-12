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
  final List<Uri> uris = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options.uri.path);
    uris.add(options.uri);
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

  group('fetchCourseEvents', () {
    Map<String, dynamic> ev(int id, int course, {String? state, String? desc}) => {
          'id': id,
          'title': 'Event $id',
          'start_at': '2026-10-14T19:00:00Z',
          'end_at': '2026-10-14T20:00:00Z',
          'all_day': false,
          'context_code': 'course_$course',
          'workflow_state': state ?? 'active',
          'description': desc,
          'html_url': 'https://canvas.test/calendar?event_id=$id',
        };

    test('parents use the observer endpoint, ten courses per request',
        () async {
      final fake = _FakeCanvas({
        '/api/v1/users/77/calendar_events': (
          200,
          [
            ev(1, 101, desc: '<p>Bring a <b>pencil</b></p>'),
            ev(2, 102),
            ev(3, 101, state: 'deleted'),
          ],
        ),
      });
      final out = await _client(fake).fetchCourseEvents(
        [for (var i = 101; i <= 112; i++) i],
        canvasUserId: 77,
        isParent: true,
        from: DateTime(2026, 4, 12),
        to: DateTime(2027, 4, 12),
      );

      expect(fake.uris, hasLength(2));
      final first = fake.uris.first.queryParametersAll;
      expect(first['context_codes[]'],
          [for (var i = 101; i <= 110; i++) 'course_$i']);
      expect(fake.uris.last.queryParametersAll['context_codes[]'],
          ['course_111', 'course_112']);
      expect(first['start_date'], ['2026-04-12']);
      expect(first['end_date'], ['2027-04-12']);
      // Observer tokens 200-with-empty on params Canvas doesn't expect.
      expect(first.keys, unorderedEquals(
          ['context_codes[]', 'start_date', 'end_date']));

      // Both batches answered with the same body, so each event shows twice;
      // what matters is the grouping, the dropped delete and the plain text.
      expect(out.keys, unorderedEquals([101, 102]));
      expect(out[101]!.map((e) => e['id']), [1, 1]);
      expect(out[101]!.first['description'], 'Bring a pencil');
    });

    test('students use their own calendar endpoint', () async {
      final fake = _FakeCanvas({'/api/v1/calendar_events': (200, [])});
      await _client(fake).fetchCourseEvents([5],
          canvasUserId: 77,
          isParent: false,
          from: DateTime(2026, 1, 1),
          to: DateTime(2026, 12, 31));
      expect(fake.seen, ['/api/v1/calendar_events']);
    });
  });

  test('processStudent keeps assignments when the event fetch fails',
      () async {
    final fake = _FakeCanvas({
      '/api/v1/users/77/courses': (
        200,
        [
          {'id': 5, 'name': 'Math', 'enrollments': []},
        ],
      ),
      '/api/v1/courses/5/assignments': (
        200,
        [
          {'id': 9, 'name': 'Quiz', 'due_at': '2026-10-14T15:00:00Z'},
        ],
      ),
      '/api/v1/courses/5/students/submissions': (200, []),
      '/api/v1/users/77/calendar_events': (403, {'errors': []}),
    });
    final out = await _client(fake).processStudent(
      {'canvas_user_id': 77, 'student_id': 's1', 'name': 'Kid'},
      isParent: true,
    );
    final course = (out['courses'] as List).single as Map;
    expect((course['assignments'] as List).single['name'], 'Quiz');
    expect(course['events'], isNull);
    expect(out['events_error'], contains('HTTP 403'));
  });
}
