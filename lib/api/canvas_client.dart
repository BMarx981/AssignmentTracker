import 'package:dio/dio.dart';

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

  /// Detects whether the token is a parent/observer or a student token, and
  /// returns the list of students we should fetch for.
  Future<({List<Map<String, dynamic>> students, bool isParent})>
      fetchAllStudents() async {
    final Map<String, dynamic> profile;
    try {
      final (body, _) = await _request('/users/self/profile');
      profile = (body.value is Map)
          ? (body.value as Map).cast<String, dynamic>()
          : const {};
    } catch (_) {
      return (students: const <Map<String, dynamic>>[], isParent: false);
    }

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
      // params, so we don't pass per_page/score_statistics here.
      final assignments = await _getAll(
        '/courses/$courseId/assignments',
        {'order_by': 'due_at'},
      );
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

    return {
      'student_id': student['student_id'],
      'name': student['name'],
      'canvas_user_id': canvasUid,
      'current_grading_period': currentGradingPeriod,
      'courses': outCourses,
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
