import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

/// Talks directly to the Canvas LMS REST API.
///
/// Mirrors `../assignment-tracker/canvas_fetch.py` — same endpoints, same query
/// params, same output JSON shape. The resulting Map can be fed to
/// `CanvasData.fromJson` (per-student) verbatim.
class CanvasClient {
  CanvasClient({
    required this.baseUrl,
    required this.token,
    Dio? dio,
  }) : _dio = dio ?? Dio() {
    _dio.options.headers['Authorization'] = 'Bearer $token';
    _dio.options.headers['Accept'] = 'application/json';
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    // Canvas wants include[]=a&include[]=b, not include[]=a,b.
    _dio.options.listFormat = ListFormat.multi;
  }

  /// Canvas instance root, e.g. `https://mcpsmd.instructure.com`. No trailing slash.
  final String baseUrl;
  final String token;
  final Dio _dio;

  String get _apiBase => '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1';

  /// Fetches a single page. Returns (body, links).
  Future<(_Body, Map<String, String>)> _request(
    String pathOrUrl, [
    Map<String, dynamic>? params,
  ]) async {
    final url = pathOrUrl.startsWith('http') ? pathOrUrl : '$_apiBase$pathOrUrl';
    final r = await _dio.getUri<dynamic>(
      Uri.parse(url).replace(
        queryParameters:
            params?.map((k, v) => MapEntry(k, _stringifyParam(v))),
      ),
    );
    final body = r.data;
    final linkHeader = r.headers.value('link') ?? '';
    return (_Body(body), _parseLinks(linkHeader));
  }

  /// Follows `Link: rel="next"` pagination across all pages. Flattens list bodies.
  Future<List<dynamic>> _getAll(String path, [Map<String, dynamic>? params]) async {
    final out = <dynamic>[];
    String? url = path;
    Map<String, dynamic>? p = params;
    while (url != null) {
      final (body, links) = await _request(url, p);
      final value = body.value;
      if (value is List) {
        out.addAll(value);
      } else if (value != null) {
        out.add(value);
      }
      url = links['next'];
      p = null; // next URL already encodes params
    }
    return out;
  }

  // ---------- public API ----------

  /// Canvas's record for this client's own token (`expires_at`,
  /// `workflow_state`, `purpose`, …), or null when it can't be looked up.
  ///
  /// Canvas finds a token by its hint: the shard prefix plus the first five
  /// characters after the `~` (`2873~az23v` for `2873~az23vn3B…`). A 401 means
  /// the token itself is dead and is rethrown.
  Future<Map<String, dynamic>?> fetchTokenInfo() async {
    final tilde = token.indexOf('~');
    if (tilde < 0 || token.length < tilde + 6) return null;
    final hint = token.substring(0, tilde + 6);
    try {
      final (body, _) =
          await _request('/users/self/tokens/${Uri.encodeComponent(hint)}');
      final value = body.value;
      return value is Map ? value.cast<String, dynamic>() : null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Detects whether the token is a parent/observer or a student token, and
  /// returns the list of students we should fetch for.
  Future<({List<Map<String, dynamic>> students, bool isParent})>
      fetchAllStudents() async {
    // Errors propagate: this is the first call a fetch makes, so a 401 here is
    // how an expired or revoked token surfaces. Swallowing it used to make a
    // dead token look like an account with no students.
    final (body, _) = await _request('/users/self/profile');
    final profile = (body.value is Map)
        ? (body.value as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    final canvasUserId = profile['id'];
    final integrationId = (profile['integration_id'] as String?) ?? '';
    final name = (profile['name'] as String?) ??
        (profile['short_name'] as String?) ??
        '';

    if (integrationId.startsWith('parent_') || integrationId.isEmpty) {
      try {
        final observees = await _getAll('/users/self/observees');
        if (observees.isNotEmpty) {
          final students = <Map<String, dynamic>>[];
          for (final raw in observees) {
            final o = (raw as Map).cast<String, dynamic>();
            final sid = (o['sis_user_id'] as String?) ??
                (o['integration_id'] as String?);
            students.add({
              'canvas_user_id': o['id'],
              'student_id': sid,
              'name': (o['name'] as String?) ??
                  (o['short_name'] as String?) ??
                  'Student ${o['id']}',
            });
          }
          return (students: students, isParent: true);
        }
      } catch (_) {
        // fall through to student-token path
      }
    }

    return (
      students: [
        {
          'canvas_user_id': canvasUserId,
          'student_id': integrationId.isEmpty ? null : integrationId,
          'name': name,
        },
      ],
      isParent: false,
    );
  }

  /// Returns `{title, start_date, end_date}` for today's grading period, or null.
  Future<Map<String, dynamic>?> fetchCurrentGradingPeriod(int courseId) async {
    try {
      final (body, _) = await _request('/courses/$courseId/grading_periods');
      final value = body.value;
      if (value is! Map) return null;
      final periods = (value['grading_periods'] as List?) ?? const [];
      final today = DateTime.now().toUtc();
      for (final raw in periods) {
        final gp = (raw as Map).cast<String, dynamic>();
        final start = gp['start_date'] as String?;
        final end = gp['end_date'] as String?;
        if (start == null || end == null) continue;
        final s = DateTime.tryParse(start);
        final e = DateTime.tryParse(end);
        if (s == null || e == null) continue;
        if (!today.isBefore(s) && !today.isAfter(e)) {
          return {
            'title': gp['title'],
            'start_date': _isoDate(s),
            'end_date': _isoDate(e),
          };
        }
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> fetchCoursesForStudent(
    int canvasUserId, {
    required bool isParent,
  }) async {
    final path = isParent ? '/users/$canvasUserId/courses' : '/courses';
    final raw = await _getAll(path, {
      'enrollment_state': 'active',
      'per_page': 100,
      'include[]': ['total_scores', 'current_grading_period_scores'],
    });
    return raw
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchAssignmentsForCourse(
    int courseId, {
    required int? studentCanvasId,
    required bool isParent,
  }) async {
    if (isParent && studentCanvasId != null) {
      // Observer tokens silently 200-with-empty if Canvas sees unrecognized
      // params, so we don't pass per_page/score_statistics here. order_by=due_at
      // triggers it too (verified against mcpsmd 2026-10): every course came
      // back empty. Callers key off due_at, so Canvas ordering isn't needed.
      final assignments = await _getAll('/courses/$courseId/assignments');
      final subs = await _getAll(
        '/courses/$courseId/students/submissions',
        {
          'student_ids[]': ['$studentCanvasId'],
          'per_page': 100,
        },
      );
      final byId = <Object, Map<String, dynamic>>{};
      for (final s in subs) {
        final m = (s as Map).cast<String, dynamic>();
        final id = m['assignment_id'];
        if (id != null) byId[id] = m;
      }
      final out = <Map<String, dynamic>>[];
      for (final a in assignments) {
        final m = (a as Map).cast<String, dynamic>();
        m['submission'] = byId[m['id']];
        out.add(m);
      }
      return out;
    }
    final raw = await _getAll('/courses/$courseId/assignments', {
      'per_page': 100,
      'include[]': ['submission', 'score_statistics'],
      'order_by': 'due_at',
    });
    return raw
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList(growable: false);
  }

  /// Course calendar events (not assignments: `type` defaults to `event`, so
  /// it isn't sent) from [from] to [to], keyed by course id.
  ///
  /// Parents go through `/users/:id/calendar_events`, the endpoint Canvas
  /// documents for observers. Only documented params are sent: observer
  /// tokens have twice answered unrecognized ones with a silent empty list.
  /// Canvas caps `context_codes[]` at 10 per request, hence the batching.
  Future<Map<int, List<Map<String, dynamic>>>> fetchCourseEvents(
    List<int> courseIds, {
    required int canvasUserId,
    required bool isParent,
    required DateTime from,
    required DateTime to,
  }) async {
    final path =
        isParent ? '/users/$canvasUserId/calendar_events' : '/calendar_events';
    final out = <int, List<Map<String, dynamic>>>{};
    for (var i = 0; i < courseIds.length; i += 10) {
      final batch = courseIds.skip(i).take(10);
      final raw = await _getAll(path, {
        'context_codes[]': [for (final id in batch) 'course_$id'],
        'start_date': _isoDate(from),
        'end_date': _isoDate(to),
      });
      for (final e in raw) {
        final m = (e as Map).cast<String, dynamic>();
        if (m['workflow_state'] == 'deleted' || m['hidden'] == true) continue;
        final ctx = (m['context_code'] as String?) ?? '';
        final cid = int.tryParse(ctx.replaceFirst('course_', ''));
        if (cid == null) continue;
        final desc = m['description'] as String?;
        (out[cid] ??= []).add({
          'id': m['id'],
          'title': m['title'],
          'start_at': m['start_at'],
          'end_at': m['end_at'],
          'all_day': m['all_day'],
          'all_day_date': m['all_day_date'],
          'location_name': m['location_name'],
          'html_url': m['html_url'],
          'description': desc == null || desc.isEmpty
              ? null
              : html_parser.parseFragment(desc).text?.trim(),
        });
      }
    }
    return out;
  }

  /// Builds the per-student payload — same shape `canvas_fetch.py` writes for
  /// one student. Pluggable into `CanvasData.fromJson`.
  Future<Map<String, dynamic>> processStudent(
    Map<String, dynamic> student, {
    required bool isParent,
  }) async {
    final canvasUid = student['canvas_user_id'] as int;
    final coursesRaw = await fetchCoursesForStudent(canvasUid, isParent: isParent);

    Map<String, dynamic>? currentGradingPeriod;
    final outCourses = <Map<String, dynamic>>[];
    for (final c in coursesRaw) {
      final cid = c['id'];
      if (cid is! int) continue;
      final name = (c['name'] as String?) ??
          (c['course_code'] as String?) ??
          'Course $cid';
      final (currentScore, currentGrade) = _extractEnrollmentScores(
        ((c['enrollments'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList(),
      );

      currentGradingPeriod ??= await fetchCurrentGradingPeriod(cid);

      List<Map<String, dynamic>> assignments = const [];
      try {
        assignments = await fetchAssignmentsForCourse(
          cid,
          studentCanvasId: canvasUid,
          isParent: isParent,
        );
      } catch (_) {
        assignments = const [];
      }

      final kept = <Map<String, dynamic>>[];
      for (final a in assignments) {
        final due = a['due_at'] as String?;
        if (due == null || due.isEmpty) continue;
        final dueDate = DateTime.tryParse(due);
        if (dueDate == null) continue;
        final sub = (a['submission'] as Map?)?.cast<String, dynamic>() ?? const {};
        kept.add({
          'id': a['id'],
          'name': a['name'],
          'due_at': due,
          'due_date': _isoDate(dueDate),
          'points_possible': a['points_possible'],
          'html_url': a['html_url'],
          'submission_types': a['submission_types'],
          'workflow_state': a['workflow_state'],
          'omit_from_final_grade': a['omit_from_final_grade'],
          'muted': a['muted'],
          'submission': {
            'workflow_state': sub['workflow_state'],
            'submitted_at': sub['submitted_at'],
            'missing': sub['missing'],
            'late': sub['late'],
            'excused': sub['excused'],
            'score': sub['score'],
            'grade': sub['grade'],
            'entered_score': sub['entered_score'],
            'graded_at': sub['graded_at'],
          },
        });
      }

      outCourses.add({
        'id': cid,
        'name': name,
        'course_code': c['course_code'],
        'current_score': currentScore,
        'current_grade': currentGrade,
        'assignments': kept,
      });
    }

    // Half a year either side covers the school year from any point in it.
    // A failure here costs the calendar its events, not the fetch its
    // assignments, so it's recorded rather than thrown.
    String? eventsError;
    try {
      final now = DateTime.now();
      final events = await fetchCourseEvents(
        [for (final c in outCourses) c['id'] as int],
        canvasUserId: canvasUid,
        isParent: isParent,
        from: now.subtract(const Duration(days: 183)),
        to: now.add(const Duration(days: 183)),
      );
      for (final c in outCourses) {
        c['events'] = events[c['id']] ?? const <Map<String, dynamic>>[];
      }
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      eventsError = code == null
          ? 'Canvas calendar events could not be loaded.'
          : 'Canvas calendar events could not be loaded (HTTP $code).';
    } catch (_) {
      eventsError = 'Canvas calendar events could not be loaded.';
    }

    return {
      'student_id': student['student_id'],
      'name': student['name'],
      'canvas_user_id': canvasUid,
      'current_grading_period': currentGradingPeriod,
      'courses': outCourses,
      'events_error': eventsError,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// Top-level convenience: detect students, fetch each, return the full payload
  /// in the same shape `canvas_fetch.py` writes.
  Future<Map<String, dynamic>> fetchAll() async {
    final result = await fetchAllStudents();
    final out = <Map<String, dynamic>>[];
    for (final s in result.students) {
      out.add(await processStudent(s, isParent: result.isParent));
    }
    return {
      'source': 'Canvas',
      'canvas_base_url': baseUrl,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'students': out,
    };
  }
}

(double? score, String? grade) _extractEnrollmentScores(
  List<Map<String, dynamic>> enrollments,
) {
  for (final enr in enrollments) {
    final score = (enr['current_period_computed_current_score'] as num?) ??
        (enr['computed_current_score'] as num?);
    final grade = (enr['current_period_computed_current_grade'] as String?) ??
        (enr['computed_current_grade'] as String?);
    if (score != null || grade != null) return (score?.toDouble(), grade);
  }
  return (null, null);
}

/// Parses an RFC 5988 Link header into a {rel: url} map.
Map<String, String> _parseLinks(String header) {
  final out = <String, String>{};
  for (final piece in header.split(',')) {
    final p = piece.trim();
    if (p.isEmpty || !p.contains(';')) continue;
    final idx = p.indexOf(';');
    var ref = p.substring(0, idx).trim();
    final rel = p.substring(idx + 1).trim();
    ref = ref.replaceAll(RegExp(r'^<'), '').replaceAll(RegExp(r'>$'), '');
    final m = RegExp(r'^rel="([^"]+)"').firstMatch(rel);
    if (m != null) out[m.group(1)!] = ref;
  }
  return out;
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

dynamic _stringifyParam(dynamic v) {
  if (v is List) return v.map((e) => '$e').toList();
  return '$v';
}

/// Wrapper so we can return dynamic-typed bodies through a typed tuple.
class _Body {
  const _Body(this.value);
  final dynamic value;
}
