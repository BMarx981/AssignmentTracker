import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:html/parser.dart' as html_parser;

/// Talks directly to Synergy ParentVUE.
///
/// Mirrors `../assignment-tracker/synergy_fetch.py`: scrape the ASP.NET login
/// form, POST credentials, iterate `AGU=0..N` to discover multi-child accounts,
/// scrape `data-focus` JSON off the gradebook home page, then activate each
/// class via `/service/PXP2Communication.asmx/LoadControl` and pull its data
/// from `/api/GB/ClientSideData/Transfer`.
///
/// Output JSON shape matches the Python script's so the existing
/// `SynergyData.fromJson` model consumes it verbatim.
class SynergyClient {
  SynergyClient({
    required String baseUrl,
    required this.username,
    required this.password,
    Dio? dio,
    CookieJar? cookieJar,
  })  : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
        _jar = cookieJar ?? CookieJar(),
        _dio = dio ?? Dio() {
    _dio.options.headers.addAll(_browserHeaders);
    _dio.options.followRedirects = true;
    _dio.options.maxRedirects = 5;
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.validateStatus = (s) => s != null && s < 500;
    if (!_dio.interceptors.any((i) => i is CookieManager)) {
      _dio.interceptors.add(CookieManager(_jar));
    }
  }

  final String baseUrl;
  final String username;
  final String password;
  final Dio _dio;
  final CookieJar _jar;

  String get _loginUrl => '$baseUrl/PXP2_Login_Parent.aspx';
  String get _loadControlUrl =>
      '$baseUrl/service/PXP2Communication.asmx/LoadControl';
  String get _transferUrl => '$baseUrl/api/GB/ClientSideData/Transfer';
  String _gradebookUrl(int agu) => '$baseUrl/PXP2_GradeBook.aspx?AGU=$agu';

  static const _browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  Map<String, String> get _ajaxHeaders => {
        'X-Requested-With': 'XMLHttpRequest',
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json, text/javascript, */*; q=0.01',
        'Origin': baseUrl,
        'Referer': _gradebookUrl(0),
        'AGU': '0',
      };

  // ---------- public API ----------

  /// Performs the form POST that establishes the session cookie. Throws
  /// [SynergyAuthException] on auth failure.
  Future<void> login() async {
    final r = await _dio.get<String>(
      _loginUrl,
      options: Options(responseType: ResponseType.plain),
    );
    final getStatus = r.statusCode;
    if (getStatus == null || getStatus >= 400) {
      throw SynergyAuthException(
        'Could not load the Synergy login page.',
        diagnostics: 'GET $_loginUrl → HTTP $getStatus',
      );
    }
    final hidden = _scrapeAllHiddenInputs(r.data ?? '');
    if (!hidden.containsKey('__VIEWSTATE') ||
        !hidden.containsKey('__EVENTVALIDATION')) {
      throw SynergyAuthException(
        "The Synergy login page didn't look the way we expected. "
        'The site may have changed.',
        diagnostics: 'GET $_loginUrl → HTTP $getStatus\n'
            'Hidden inputs found: ${hidden.keys.toList()}',
        rawHtml: r.data,
      );
    }

    final formFields = <String, String>{
      ...hidden,
      r'ctl00$MainContent$username': username,
      r'ctl00$MainContent$password': password,
      r'ctl00$MainContent$Submit1': 'Login',
    };

    // Synergy answers a successful login with a 302 to /PXP2_LaunchPad.aspx
    // and a failed login with a 200 redisplay of the login form. dio's
    // built-in follower doesn't always chase 302-on-POST reliably across
    // platforms, so we handle the redirect ourselves and look at the
    // Location header to decide success.
    final r2 = await _dio.post<String>(
      _loginUrl,
      data: _formEncode(formFields),
      options: Options(
        responseType: ResponseType.plain,
        contentType: Headers.formUrlEncodedContentType,
        followRedirects: false,
        validateStatus: (s) => s != null && s < 400,
      ),
    );

    final postStatus = r2.statusCode;
    final location = r2.headers.value('location');

    if ((postStatus == 302 || postStatus == 303) && location != null) {
      final dest = location.toLowerCase();
      final wasSentBackToLogin = dest.contains('login');
      if (!wasSentBackToLogin) {
        // Success. Follow once to land on the launchpad so the next GET
        // (the gradebook home) starts from a fully-warmed session.
        final next = location.startsWith('http') ? location : '$baseUrl$location';
        await _dio.get<dynamic>(
          next,
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: true,
          ),
        );
        return;
      }
    }

    final pageError = _scrapeLoginError(r2.data ?? '');
    throw SynergyAuthException(
      pageError ??
          'Synergy did not accept the username or password. The site '
              'sent us back to the login page without an error message.',
      diagnostics: 'GET $_loginUrl → HTTP $getStatus\n'
          'POST $_loginUrl → HTTP $postStatus\n'
          'Location header: ${location ?? '(none)'}\n'
          'Hidden fields submitted: ${hidden.keys.toList()}',
      rawHtml: r2.data,
    );
  }

  /// Looks for the visible error message Synergy renders in its login form
  /// when credentials are rejected. Returns null if no message can be found.
  String? _scrapeLoginError(String html) {
    final doc = html_parser.parse(html);
    for (final selector in const [
      '#ErrorMessage',
      '.ErrorMessage',
      '.error',
      '.alert',
      "[class*='error']",
      "[class*='alert']",
    ]) {
      for (final el in doc.querySelectorAll(selector)) {
        final text = el.text.trim();
        if (text.isNotEmpty && text.length < 300) return text;
      }
    }
    return null;
  }

  /// Iterates AGU=0..9, scraping the gradebook home for each child. Stops as
  /// soon as the sisNumber repeats (Synergy wraps around once you exceed the
  /// account's actual child count).
  Future<List<Map<String, dynamic>>> fetchAllStudents() async {
    final seenSids = <String>{};
    final allStudents = <Map<String, dynamic>>[];
    for (var agu = 0; agu < 10; agu++) {
      final r = await _dio.get<String>(
        _gradebookUrl(agu),
        options: Options(responseType: ResponseType.plain),
      );
      if (r.statusCode == null || r.statusCode! >= 400) break;
      final homeHtml = r.data ?? '';

      final (studentId, classes, teacherEmails) = _scrapeHome(homeHtml);
      if (studentId == null || seenSids.contains(studentId)) break;
      seenSids.add(studentId);
      final name = _scrapeStudentName(homeHtml);

      final courses = <Map<String, dynamic>>[];
      for (final cls in classes) {
        final rec = await _fetchClassData(cls);
        courses.add(_postProcess(rec, teacherEmails));
      }
      allStudents.add({
        'student_id': studentId,
        'name': name,
        'courses': courses,
      });
    }
    return allStudents;
  }

  /// Top-level convenience: login + iterate students, returning the same
  /// payload shape `synergy_fetch.py` writes.
  Future<Map<String, dynamic>> fetchAll() async {
    await login();
    final students = await fetchAllStudents();
    return {
      'source': 'Synergy ParentVUE (direct HTTP)',
      'synergy_base_url': baseUrl,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'students': students,
    };
  }

  // ---------- login page scraping ----------

  /// Parse the login page properly and pull EVERY hidden input. Modern
  /// ASP.NET pages sometimes require `__VIEWSTATEGENERATOR`,
  /// `__EVENTTARGET`, `__EVENTARGUMENT`, `__PREVIOUSPAGE`, etc. in addition
  /// to `__VIEWSTATE` and `__EVENTVALIDATION`.
  Map<String, String> _scrapeAllHiddenInputs(String html) {
    final out = <String, String>{};
    final doc = html_parser.parse(html);
    for (final el in doc.querySelectorAll('input')) {
      final type = (el.attributes['type'] ?? '').toLowerCase();
      if (type != 'hidden') continue;
      final name = el.attributes['name'];
      if (name == null || name.isEmpty) continue;
      out[name] = el.attributes['value'] ?? '';
    }
    return out;
  }

  // ---------- gradebook home scraping ----------

  /// Returns `(student_id, classes, teacherEmails)` where each class is
  /// `{focus: Map, classID: int, name: String}` and teacherEmails maps the
  /// teacher's display name (lower-cased, whitespace-collapsed) to their
  /// email address — scraped from `mailto:` links on the gradebook home page.
  (String?, List<Map<String, dynamic>>, Map<String, String>) _scrapeHome(
      String html) {
    String? studentId;
    final sidMatch =
        RegExp(r'"sisNumber"\s*:\s*"(\d{5,9})"').firstMatch(html);
    if (sidMatch != null) studentId = sidMatch.group(1);

    final seenIds = <int>{};
    final classes = <Map<String, dynamic>>[];

    final doc = html_parser.parse(html);
    final candidates = doc.querySelectorAll('button[data-focus], a[data-focus]');
    for (final el in candidates) {
      final raw = el.attributes['data-focus'];
      if (raw == null || raw.isEmpty) continue;
      Map<String, dynamic> obj;
      try {
        obj = (jsonDecode(raw) as Map).cast<String, dynamic>();
      } catch (_) {
        continue;
      }
      final lp = (obj['LoadParams'] as Map?)?.cast<String, dynamic>() ?? const {};
      final fa = (obj['FocusArgs'] as Map?)?.cast<String, dynamic>() ?? const {};
      if (lp['ControlName'] != 'Gradebook_RichContentClassDetails') continue;
      final cidRaw = fa['classID'];
      final cid = cidRaw is int
          ? cidRaw
          : int.tryParse('${cidRaw ?? ''}') ?? -1;
      if (cid <= 0 || seenIds.contains(cid)) continue;
      seenIds.add(cid);
      final text = el.text.split('\n').first.trim();
      final name = _classHeaderRe.hasMatch(text) ? text : 'Class $cid';
      classes.add({'focus': obj, 'classID': cid, 'name': name});
    }

    final teacherEmails = <String, String>{};
    for (final a in doc.querySelectorAll('a[href^="mailto:"]')) {
      final href = a.attributes['href'] ?? '';
      final email = href.substring('mailto:'.length).split('?').first.trim();
      if (email.isEmpty || !email.contains('@')) continue;
      final label = a.text.trim();
      if (label.isNotEmpty) {
        teacherEmails[_normalizeTeacherKey(label)] = email;
      }
      // Some ParentVUE deployments put the teacher name in the title attribute
      // or in a sibling element. Capture title too as a fallback key.
      final title = a.attributes['title']?.trim();
      if (title != null && title.isNotEmpty) {
        teacherEmails[_normalizeTeacherKey(title)] = email;
      }
    }

    return (studentId, classes, teacherEmails);
  }

  String? _scrapeStudentName(String html) {
    for (final pattern in [
      r'class="student-name"[^>]*>\s*([^<]+)',
      r'"studentName"\s*:\s*"([^"]+)"',
      r'<title>[^<]*[-|]\s*([A-Z][a-z]+ [A-Z][a-zA-Z .\x27]+)',
    ]) {
      final m = RegExp(pattern).firstMatch(html);
      if (m != null) {
        final name = m.group(1)!.trim();
        if (name.length > 2 && name.length < 80) return name;
      }
    }
    return null;
  }

  static final _classHeaderRe = RegExp(r'^\d+\s*:\s*\S');

  // ---------- per-class fetch ----------

  Future<void> _activateClass(Map<String, dynamic> focus) async {
    final control =
        (focus['LoadParams'] as Map?)?['ControlName'] as String? ?? '';
    final parameters =
        Map<String, dynamic>.from((focus['FocusArgs'] as Map?) ?? const {});
    final body = jsonEncode({
      'request': {'control': control, 'parameters': parameters},
    });
    await _dio.post<dynamic>(
      _loadControlUrl,
      data: body,
      options: Options(
        headers: _ajaxHeaders,
        contentType: 'application/json; charset=utf-8',
      ),
    );
  }

  Future<Map<String, dynamic>> _fetchClassData(Map<String, dynamic> cls) async {
    final name = (cls['name'] as String?) ?? 'Class ${cls['classID']}';
    final focus = (cls['focus'] as Map).cast<String, dynamic>();
    await _activateClass(focus);

    const itemsParams =
        r'{"loadOptions":{"sort":[{"selector":"due_date","desc":false}],'
        r'"filter":[["isDone","=",false]],'
        r'"group":[{"Selector":"Week","desc":false}],'
        r'"requireTotalCount":true,"userData":{}},"clientState":{}}';

    final calls = <List<String>>[
      ['pxp.course.grade.card-get', 'pxp.course.grade.card', 'get', '{}'],
      [
        'pxp.course.content.items-LoadWithOptions',
        'pxp.course.content.items',
        'LoadWithOptions',
        itemsParams,
      ],
      ['genericdata.classdata-GetClassData', 'genericdata.classdata',
          'GetClassData', '{}'],
    ];

    final captured = <Map<String, dynamic>>[];
    for (final c in calls) {
      try {
        final body = jsonEncode({
          'FriendlyName': c[1],
          'Method': c[2],
          'Parameters': c[3],
        });
        final r = await _dio.post<dynamic>(
          _transferUrl,
          queryParameters: {'action': c[0]},
          data: body,
          options: Options(
            headers: _ajaxHeaders,
            contentType: 'application/json; charset=utf-8',
          ),
        );
        captured.add({
          'url': r.realUri.toString(),
          'body': r.data,
        });
      } catch (_) {
        // tolerate individual call failures — parser handles partial data
      }
    }

    return _parseClassFromXhr(captured) ??
        {
          'synergy_name': name,
          'assignments': const <dynamic>[],
          '_warning': 'parse failed',
        };
  }

  // ---------- parsers ----------

  Map<String, dynamic>? _parseClassFromXhr(List<Map<String, dynamic>> captured) {
    Map<String, dynamic>? gradeCard;
    Map<String, dynamic>? contentItems;
    Map<String, dynamic>? classData;

    for (final entry in captured) {
      final url = (entry['url'] as String?) ?? '';
      final body = entry['body'];
      if (body is! Map) continue;
      final map = body.cast<String, dynamic>();
      if (url.contains('pxp.course.grade.card-get') &&
          map.containsKey('classPct')) {
        gradeCard = map;
      } else if (url.contains('pxp.course.content.items-LoadWithOptions')) {
        final rd = (map['responseData'] as Map?)?.cast<String, dynamic>();
        if (rd != null && rd['data'] is List) contentItems = map;
      } else if (url.contains('genericdata.classdata-GetClassData')) {
        classData = map;
      }
    }

    if (gradeCard == null && contentItems == null && classData == null) {
      return null;
    }

    String? name;
    String? teacher;
    String? letter;
    double? percent;

    if (gradeCard != null) {
      name = gradeCard['className'] as String?;
      teacher = gradeCard['teacherName'] as String?;
      letter = gradeCard['classGrade'] as String?;
      final pctRaw = ((gradeCard['classPct'] as String?) ?? '')
          .replaceAll('%', '')
          .trim();
      percent = pctRaw.isEmpty ? null : double.tryParse(pctRaw);
    }
    if (percent == null && classData != null) {
      final cg = (classData['classGrades'] as List?) ?? const [];
      if (cg.isNotEmpty && cg.first is Map) {
        final first = (cg.first as Map).cast<String, dynamic>();
        percent = _toFloat(first['totalWeightedPercentage']);
        letter ??= (first['calculatedMark'] as String?) ??
            (first['manualMark'] as String?);
      }
    }

    final assignments = <Map<String, dynamic>>[];
    if (contentItems != null) {
      final groups = (contentItems['responseData'] as Map)['data'] as List;
      for (final g in groups) {
        final items = ((g as Map)['items'] as List?) ?? const [];
        for (final it in items) {
          assignments.add(
              _assignmentFromContentItem((it as Map).cast<String, dynamic>()));
        }
      }
    }

    // Synergy sometimes embeds the teacher's email directly in the gradeCard
    // or in classData. Keys vary by deployment; try the common ones.
    final teacherEmail = _pickFirstNonEmptyString([
      gradeCard?['teacherEmail'],
      gradeCard?['teacherEmail1'],
      gradeCard?['teacherEmailAddress'],
      gradeCard?['staffEmail'],
      classData?['teacherEmail'],
      classData?['staffEmail'],
    ]);

    return {
      'synergy_name': _shortClassName(name) ?? name,
      'teacher': teacher,
      'teacher_email': teacherEmail,
      'letter_grade': letter,
      'percent': percent,
      'missing_count':
          assignments.where((a) => a['status'] == 'missing').length,
      'assignments': assignments,
    };
  }

  Map<String, dynamic> _assignmentFromContentItem(Map<String, dynamic> it) {
    final title = (it['title'] as String?) ?? '(untitled)';
    final pts = _toFloat(it['pointsPossible']);
    final score = _toFloat(it['gradeMark']);
    final pctRaw =
        ((it['calcValue'] as String?) ?? '').replaceAll('%', '').trim();
    final dpct = pctRaw.isEmpty ? null : double.tryParse(pctRaw);
    final due = _normalizeDate(it['due_date']);
    final isMissing = it['isMissing'] == true;
    final comment = ((it['commentText'] as String?) ?? '').trim();

    String status;
    if (isMissing) {
      status = 'missing';
    } else if (score == null) {
      status = 'not_graded';
    } else if (pts != null && pts != 0 && score == 0) {
      status = 'zero_graded';
    } else {
      final lc = comment.toLowerCase();
      if (lc.contains('reassess')) {
        status = 'reassessed';
      } else if (lc.contains('incomplete')) {
        status =
            dpct != null ? 'incomplete_${dpct.round()}' : 'incomplete';
      } else if (lc.contains('late') && dpct == 100) {
        status = 'late_100';
      } else if (lc.contains('late')) {
        status = 'late';
      } else {
        status = 'graded';
      }
    }

    return {
      'date': due,
      'name': title,
      'type': (it['assignmentType'] as String?) ?? '',
      'points_possible': pts,
      'score': score,
      'status': status,
      'displayed_percent': dpct?.round(),
      'comment': comment.isEmpty ? null : comment,
    };
  }

  // ---------- post-processing ----------

  /// Hard-coded course→Canvas-id mapping carried over from `synergy_fetch.py`.
  /// Move to user settings if you want this configurable.
  static const _canvasIdByFragment = <String, int>{
    'adv english': 965768,
    'algebra 1b': 1020522,
    'band 2 ms': 1003899,
    'french 2b': 968511,
    'health education': 968338,
    'historical inquiry': 965057,
    'investigations in life': 965080,
  };

  static const _policyOverrides = <String, Map<String, Object>>{
    'historical inquiry': {'policy': 'half_credit_for_missing_work'},
  };

  Map<String, dynamic> _postProcess(
      Map<String, dynamic> course, Map<String, String> teacherEmails) {
    final name = ((course['synergy_name'] as String?) ?? '').toLowerCase();
    for (final entry in _canvasIdByFragment.entries) {
      if (name.contains(entry.key)) {
        course['canvas_course_id'] = entry.value;
        break;
      }
    }
    for (final entry in _policyOverrides.entries) {
      if (name.contains(entry.key)) {
        course.addAll(entry.value);
        break;
      }
    }
    final assignments = (course['assignments'] as List?) ?? const [];
    course['missing_count'] =
        assignments.where((a) => (a as Map)['status'] == 'missing').length;

    // If the per-class XHR didn't surface an email, look the teacher up by
    // name in the home-page mailto: index.
    if ((course['teacher_email'] as String?)?.isNotEmpty != true) {
      final teacher = course['teacher'] as String?;
      if (teacher != null && teacher.isNotEmpty) {
        final key = _normalizeTeacherKey(teacher);
        final email = teacherEmails[key] ??
            teacherEmails[_normalizeTeacherKey(_swapLastFirst(teacher))];
        if (email != null) course['teacher_email'] = email;
      }
    }
    return course;
  }

  // ---------- form encoding (preserves ASP.NET hidden field order) ----------

  String _formEncode(Map<String, String> fields) {
    final parts = <String>[];
    for (final entry in fields.entries) {
      parts.add('${Uri.encodeQueryComponent(entry.key)}'
          '=${Uri.encodeQueryComponent(entry.value)}');
    }
    return parts.join('&');
  }
}

// ---------- helpers (top-level, easier to unit-test) ----------

String? _pickFirstNonEmptyString(Iterable<Object?> values) {
  for (final v in values) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return null;
}

/// Lower-cases, strips honorifics, and collapses whitespace so that
/// "Ms. Jane Smith" and "Smith, Jane" can both be looked up consistently.
String _normalizeTeacherKey(String s) {
  var t = s.toLowerCase().trim();
  t = t.replaceAll(RegExp(r'^(mr|mrs|ms|miss|mx|dr|prof)\.?\s+'), '');
  t = t.replaceAll(RegExp(r'\s+'), ' ');
  return t;
}

/// Converts "Smith, Jane" → "Jane Smith" so the lookup can match either
/// directory orientation. Returns the input unchanged when no comma is found.
String _swapLastFirst(String s) {
  final m = RegExp(r'^([^,]+),\s*(.+)$').firstMatch(s.trim());
  if (m == null) return s;
  return '${m.group(2)} ${m.group(1)}';
}

String? _shortClassName(String? s) {
  if (s == null || s.isEmpty) return s;
  var out = s;
  out = out.replaceFirst(RegExp(r'^\s*\([A-Z]+\d*\)\s*'), '');
  out = out.replaceFirst(RegExp(r'\s*SEC:[A-Za-z0-9-]+\s*$'), '');
  out = out.replaceFirst(RegExp(r'\(\d+\)\s*$'), '');
  out = out.replaceFirst(RegExp(r"^\s*[A-Z][a-zA-Z'-]+,\s*[A-Z]\.?\s+"), '');
  out = out.trim();
  return out.isEmpty ? s : out;
}

double? _toFloat(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  final s = v.toString().replaceAll('%', '').trim();
  if (s.isEmpty || s == '-') return null;
  return double.tryParse(s);
}

String? _normalizeDate(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  // ISO 8601 — DateTime.parse handles this.
  final iso = DateTime.tryParse(s);
  if (iso != null) {
    return '${iso.year.toString().padLeft(4, '0')}-'
        '${iso.month.toString().padLeft(2, '0')}-'
        '${iso.day.toString().padLeft(2, '0')}';
  }
  // M/D/YYYY and M/D/YY
  final us = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2,4})$').firstMatch(s);
  if (us != null) {
    final m = int.parse(us.group(1)!);
    final d = int.parse(us.group(2)!);
    var y = int.parse(us.group(3)!);
    if (y < 100) y += 2000;
    return '${y.toString().padLeft(4, '0')}-'
        '${m.toString().padLeft(2, '0')}-'
        '${d.toString().padLeft(2, '0')}';
  }
  // "Mon D YYYY"
  final mon = RegExp(r'^([A-Za-z]{3})\s+(\d{1,2})\s+(\d{4})$').firstMatch(s);
  if (mon != null) {
    const months = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final m = months[mon.group(1)!.toLowerCase()];
    if (m != null) {
      final d = int.parse(mon.group(2)!);
      final y = int.parse(mon.group(3)!);
      return '${y.toString().padLeft(4, '0')}-'
          '${m.toString().padLeft(2, '0')}-'
          '${d.toString().padLeft(2, '0')}';
    }
  }
  return s;
}

/// Thrown when Synergy login fails (bad credentials, redirected to login, etc).
class SynergyAuthException implements Exception {
  SynergyAuthException(this.message, {this.diagnostics, this.rawHtml});
  final String message;

  /// Structured request/response trace (URLs, status codes, scraped fields)
  /// suitable for a "technical details" panel.
  final String? diagnostics;

  /// Full HTML of the response that triggered the failure — kept around so a
  /// debug/details panel can show it without the user having to re-run.
  final String? rawHtml;

  @override
  String toString() => 'SynergyAuthException: $message';
}
