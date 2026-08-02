// Lean hand-written models for the FastAPI shapes consumed by the Flutter app.
// Mirrors tracker/models.py (request bodies) and the /api/data response.
//
// We keep these immutable + permissive: every nullable field can actually be
// missing from the server payload (Canvas data is absent when the user hasn't
// fetched yet; comments/status maps default to empty).

import 'dart:convert';

T? _asT<T>(dynamic v) => v is T ? v : null;

List<T> _asList<T>(dynamic v, T Function(dynamic) f) =>
    (v is List) ? v.map(f).toList(growable: false) : const [];

Map<String, T> _asMap<T>(dynamic v, T Function(dynamic) f) =>
    (v is Map) ? v.map((k, val) => MapEntry(k.toString(), f(val))) : const {};

class Me {
  final String email;
  final String? name;
  final String? picture;
  final bool devMode;
  final String? studentId;

  const Me({
    required this.email,
    this.name,
    this.picture,
    required this.devMode,
    this.studentId,
  });

  factory Me.fromJson(Map<String, dynamic> j) => Me(
        email: j['email'] as String? ?? '',
        name: j['name'] as String?,
        picture: j['picture'] as String?,
        devMode: j['dev_mode'] as bool? ?? false,
        studentId: j['student_id'] as String?,
      );
}

class GradeBands {
  final int failing;
  final int atRisk;
  const GradeBands({required this.failing, required this.atRisk});

  factory GradeBands.fromJson(Map<String, dynamic> j) => GradeBands(
        failing: (j['failing'] as num?)?.toInt() ?? 60,
        atRisk: (j['at_risk'] as num?)?.toInt() ?? 75,
      );

  Map<String, dynamic> toJson() => {'failing': failing, 'at_risk': atRisk};
}

class SynergyAssignment {
  final String? date;
  final String name;
  final String? type;
  final double? pointsPossible;
  final double? score;
  final String? status;
  final num? displayedPercent;
  final String? comment;

  const SynergyAssignment({
    this.date,
    required this.name,
    this.type,
    this.pointsPossible,
    this.score,
    this.status,
    this.displayedPercent,
    this.comment,
  });

  factory SynergyAssignment.fromJson(Map<String, dynamic> j) =>
      SynergyAssignment(
        date: j['date'] as String?,
        name: (j['name'] as String?) ?? '(untitled)',
        type: j['type'] as String?,
        pointsPossible: (j['points_possible'] as num?)?.toDouble(),
        score: (j['score'] as num?)?.toDouble(),
        status: j['status'] as String?,
        displayedPercent: j['displayed_percent'] as num?,
        comment: j['comment'] as String?,
      );
}

class SynergyCourse {
  final String synergyName;
  final String? teacher;
  final String? teacherEmail;
  final String? letterGrade;
  final double? percent;
  final double? computedPercent;
  final int missingCount;
  final String? policy; // "half_credit_for_missing_work" | null
  final String? canvasCourseId;
  final List<SynergyAssignment> assignments;

  const SynergyCourse({
    required this.synergyName,
    this.teacher,
    this.teacherEmail,
    this.letterGrade,
    this.percent,
    this.computedPercent,
    this.missingCount = 0,
    this.policy,
    this.canvasCourseId,
    this.assignments = const [],
  });

  factory SynergyCourse.fromJson(Map<String, dynamic> j) => SynergyCourse(
        synergyName: (j['synergy_name'] as String?) ?? '(unnamed course)',
        teacher: j['teacher'] as String?,
        teacherEmail: j['teacher_email'] as String?,
        letterGrade: j['letter_grade'] as String?,
        percent: (j['percent'] as num?)?.toDouble(),
        computedPercent: (j['computed_percent'] as num?)?.toDouble(),
        missingCount: (j['missing_count'] as num?)?.toInt() ?? 0,
        policy: j['policy'] as String?,
        canvasCourseId: j['canvas_course_id']?.toString(),
        assignments: _asList(j['assignments'],
            (e) => SynergyAssignment.fromJson(e as Map<String, dynamic>)),
      );
}

class CanvasAssignment {
  final String name;
  final String? dueDate;
  final double? pointsPossible;
  final String? htmlUrl;
  final Map<String, dynamic>? submission;
  final Map<String, dynamic> raw; // keep raw for fields the UI may use later

  const CanvasAssignment({
    required this.name,
    this.dueDate,
    this.pointsPossible,
    this.htmlUrl,
    this.submission,
    required this.raw,
  });

  factory CanvasAssignment.fromJson(Map<String, dynamic> j) => CanvasAssignment(
        name: (j['name'] as String?) ?? '(untitled)',
        dueDate: j['due_date'] as String? ?? j['date'] as String?,
        pointsPossible: (j['points_possible'] as num?)?.toDouble(),
        htmlUrl: j['html_url'] as String?,
        submission: _asT<Map<String, dynamic>>(j['submission']),
        raw: j,
      );
}

class CanvasCourse {
  final String name;
  final List<CanvasAssignment> assignments;
  final double? avgWithMissing;
  final Map<String, dynamic> raw;

  const CanvasCourse({
    required this.name,
    this.assignments = const [],
    this.avgWithMissing,
    required this.raw,
  });

  factory CanvasCourse.fromJson(Map<String, dynamic> j) => CanvasCourse(
        name: (j['name'] as String?) ?? '(unnamed course)',
        assignments: _asList(j['assignments'],
            (e) => CanvasAssignment.fromJson(e as Map<String, dynamic>)),
        avgWithMissing: (j['avgWithMissing'] as num?)?.toDouble() ??
            (j['avg_with_missing'] as num?)?.toDouble(),
        raw: j,
      );
}

class CanvasData {
  final String? generatedAt;
  final String? currentGradingPeriod;
  final List<CanvasCourse> courses;
  const CanvasData(
      {this.generatedAt, this.currentGradingPeriod, this.courses = const []});

  factory CanvasData.fromJson(Map<String, dynamic> j) => CanvasData(
        generatedAt: j['generated_at'] as String?,
        // Canvas fetches store this as `{title, start_date, end_date}`; older
        // payloads stored just the title. Accept both — an `as String?` cast
        // on the map form throws and takes the whole assemble() down.
        currentGradingPeriod: switch (j['current_grading_period']) {
          final Map m => m['title'] as String?,
          final String s => s,
          _ => null,
        },
        courses: _asList(j['courses'],
            (e) => CanvasCourse.fromJson(e as Map<String, dynamic>)),
      );
}

class SynergyData {
  final String? generatedAt;
  final List<SynergyCourse> courses;
  const SynergyData({this.generatedAt, this.courses = const []});

  factory SynergyData.fromJson(Map<String, dynamic> j) => SynergyData(
        generatedAt: j['generated_at'] as String?,
        courses: _asList(j['courses'],
            (e) => SynergyCourse.fromJson(e as Map<String, dynamic>)),
      );
}

/// One row in `assignment_status.json`: the locally-tracked claim about a
/// specific assignment ("planned by date X" / "Felix says submitted" / etc.).
class LocalStatus {
  final String status; // "planned" | "complete_pending_submission" | "submitted_pending_feedback"
  final String assignmentName;
  final String courseName;
  final String? plannedDate;
  final String? submittedDate;
  final String? updatedAt;

  const LocalStatus({
    required this.status,
    required this.assignmentName,
    required this.courseName,
    this.plannedDate,
    this.submittedDate,
    this.updatedAt,
  });

  factory LocalStatus.fromJson(Map<String, dynamic> j) => LocalStatus(
        status: (j['status'] as String?) ?? '',
        assignmentName: (j['assignment_name'] as String?) ?? '',
        courseName: (j['course_name'] as String?) ?? '',
        plannedDate: j['planned_date'] as String?,
        submittedDate: j['submitted_date'] as String?,
        updatedAt: j['updated_at'] as String?,
      );
}

class CommentReply {
  final String id;
  final String text;
  final String author;
  final String createdAt;
  const CommentReply({
    required this.id,
    required this.text,
    required this.author,
    required this.createdAt,
  });
  factory CommentReply.fromJson(Map<String, dynamic> j) => CommentReply(
        id: (j['id'] as String?) ?? '',
        text: (j['text'] as String?) ?? '',
        author: (j['author'] as String?) ?? '',
        createdAt: (j['created_at'] as String?) ?? '',
      );
}

class CommentThread {
  final String id;
  final String text;
  final String author;
  final String createdAt;
  final List<CommentReply> replies;
  const CommentThread({
    required this.id,
    required this.text,
    required this.author,
    required this.createdAt,
    this.replies = const [],
  });
  factory CommentThread.fromJson(Map<String, dynamic> j) => CommentThread(
        id: (j['id'] as String?) ?? '',
        text: (j['text'] as String?) ?? '',
        author: (j['author'] as String?) ?? '',
        createdAt: (j['created_at'] as String?) ?? '',
        replies: _asList(j['replies'],
            (e) => CommentReply.fromJson(e as Map<String, dynamic>)),
      );
}

class Student {
  final String studentId;
  final String name;
  final CanvasData? canvas;
  final SynergyData? synergy;
  final Map<String, int> scoreThresholds; // course_name -> %
  final Map<String, List<CommentThread>> comments; // assignment_key -> threads
  final Map<String, LocalStatus> assignmentStatus; // assignment_key -> claim

  const Student({
    required this.studentId,
    required this.name,
    this.canvas,
    this.synergy,
    this.scoreThresholds = const {},
    this.comments = const {},
    this.assignmentStatus = const {},
  });

  factory Student.fromJson(Map<String, dynamic> j) {
    final thresholdsRaw = _asMap<dynamic>(j['score_thresholds'], (v) => v);
    final thresholds = <String, int>{
      for (final e in thresholdsRaw.entries)
        e.key: (e.value as num?)?.toInt() ?? 0,
    };

    final commentsRaw = _asMap<dynamic>(j['comments'], (v) => v);
    final comments = <String, List<CommentThread>>{
      for (final e in commentsRaw.entries)
        e.key: _asList(e.value,
            (t) => CommentThread.fromJson(t as Map<String, dynamic>)),
    };

    final asRaw = (j['assignment_status'] as Map?)?['entries'] as Map? ?? {};
    final assignmentStatus = <String, LocalStatus>{
      for (final e in asRaw.entries)
        e.key.toString():
            LocalStatus.fromJson((e.value as Map).cast<String, dynamic>()),
    };

    return Student(
      studentId: (j['student_id'] as String?) ?? '',
      name: (j['name'] as String?) ?? '',
      canvas: j['canvas'] is Map
          ? CanvasData.fromJson((j['canvas'] as Map).cast<String, dynamic>())
          : null,
      synergy: j['synergy'] is Map
          ? SynergyData.fromJson((j['synergy'] as Map).cast<String, dynamic>())
          : null,
      scoreThresholds: thresholds,
      comments: comments,
      assignmentStatus: assignmentStatus,
    );
  }
}

class DataPayload {
  final List<Student> students;
  final GradeBands gradeBands;
  const DataPayload({required this.students, required this.gradeBands});

  factory DataPayload.fromJson(Map<String, dynamic> j) => DataPayload(
        students: _asList(
            j['students'], (e) => Student.fromJson(e as Map<String, dynamic>)),
        gradeBands: GradeBands.fromJson(
            (j['grade_bands'] as Map?)?.cast<String, dynamic>() ?? const {}),
      );

  factory DataPayload.fromJsonString(String s) =>
      DataPayload.fromJson(jsonDecode(s) as Map<String, dynamic>);
}

class FetchStatus {
  final String canvas; // "idle" | "running" | "done" | "error"
  final String synergy;
  final String? canvasError;
  final String? synergyError;
  const FetchStatus({
    required this.canvas,
    required this.synergy,
    this.canvasError,
    this.synergyError,
  });

  factory FetchStatus.fromJson(Map<String, dynamic> j) => FetchStatus(
        canvas: (j['canvas'] as String?) ?? 'idle',
        synergy: (j['synergy'] as String?) ?? 'idle',
        canvasError: j['canvas_error'] as String?,
        synergyError: j['synergy_error'] as String?,
      );

  FetchStatus copyWith({
    String? canvas,
    String? synergy,
    Object? canvasError = _unset,
    Object? synergyError = _unset,
  }) {
    return FetchStatus(
      canvas: canvas ?? this.canvas,
      synergy: synergy ?? this.synergy,
      canvasError:
          canvasError == _unset ? this.canvasError : canvasError as String?,
      synergyError:
          synergyError == _unset ? this.synergyError : synergyError as String?,
    );
  }
}

const _unset = Object();

class Credentials {
  final String? canvasToken;
  final String? canvasBaseUrl;
  final String? synergyUsername;
  final String? synergyPassword;
  final String? synergyBaseUrl;

  const Credentials({
    this.canvasToken,
    this.canvasBaseUrl,
    this.synergyUsername,
    this.synergyPassword,
    this.synergyBaseUrl,
  });

  factory Credentials.fromJson(Map<String, dynamic> j) => Credentials(
        canvasToken: j['canvas_token'] as String?,
        canvasBaseUrl: j['canvas_base_url'] as String?,
        synergyUsername: j['synergy_username'] as String?,
        synergyPassword: j['synergy_password'] as String?,
        synergyBaseUrl: j['synergy_base_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (canvasToken != null) 'canvas_token': canvasToken,
        if (canvasBaseUrl != null) 'canvas_base_url': canvasBaseUrl,
        if (synergyUsername != null) 'synergy_username': synergyUsername,
        if (synergyPassword != null) 'synergy_password': synergyPassword,
        if (synergyBaseUrl != null) 'synergy_base_url': synergyBaseUrl,
      };
}

/// Request body for POST /api/assignments/{key}/status — mirrors AssignmentStatusIn.
class AssignmentStatusReq {
  final String status; // planned | complete_pending_submission | submitted_pending_feedback | clear
  final String assignmentName;
  final String courseName;
  final String? studentId;
  final String? plannedDate;
  final String? submittedDate;
  const AssignmentStatusReq({
    required this.status,
    required this.assignmentName,
    required this.courseName,
    this.studentId,
    this.plannedDate,
    this.submittedDate,
  });
  Map<String, dynamic> toJson() => {
        'status': status,
        'assignment_name': assignmentName,
        'course_name': courseName,
        if (studentId != null) 'student_id': studentId,
        if (plannedDate != null) 'planned_date': plannedDate,
        if (submittedDate != null) 'submitted_date': submittedDate,
      };
}

/// Request body for POST /api/assignments/{key}/comments — mirrors CommentIn.
class CommentReq {
  final String text;
  final String? studentId;
  final String? replyToId;
  const CommentReq({required this.text, this.studentId, this.replyToId});
  Map<String, dynamic> toJson() => {
        'text': text,
        if (studentId != null) 'student_id': studentId,
        if (replyToId != null) 'reply_to_id': replyToId,
      };
}
