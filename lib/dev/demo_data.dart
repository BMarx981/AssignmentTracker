// Synthetic Canvas + Synergy data for testing without live credentials.
//
// Everything is generated relative to `DateTime.now()` so a seed always lands
// inside the dashboard's default window (one month back, one month forward) —
// important over the summer, when a real fetch returns nothing useful and a
// static fixture would fall outside the range.
//
// The payloads match what `CanvasClient.fetchAll` / `SynergyClient.fetchAll`
// return, so seeding exercises the same DataAssembler → mergeData → priority
// path the real app uses. Nothing here is imported by release code paths; the
// Settings entry point is gated on `kDebugMode`.

import 'package:assignment_tracker_app/domain/name_utils.dart';
import 'package:assignment_tracker_app/storage/local_store.dart';

/// Writes a full demo dataset (two students, mixed course health, local
/// statuses, comments, thresholds) into [store], replacing whatever is there.
///
/// Credentials are left alone — wiping them would log the user out of a real
/// account they may still want.
Future<void> seedDemoData(LocalStore store) async {
  final anchor = DateTime.now();

  await store.writeCanvasData(buildCanvasPayload(anchor));
  await store.writeSynergyData(buildSynergyPayload(anchor));
  await store.writeGradeBands({'failing': 60, 'at_risk': 75});

  for (final student in _students) {
    await store.writeScoreThresholds(student.id, student.thresholds);
    await store.writeComments(student.id, student.comments(anchor));
    await store.writeAssignmentStatus(student.id, {
      'entries': student.statusEntries(anchor),
    });
  }
}

/// Deletes seeded data (and everything else in the store) but preserves
/// credentials so a real fetch still works afterwards.
Future<void> clearDemoData(LocalStore store) async {
  final creds = await store.readCredentials();
  await store.wipe();
  if (creds != null) await store.writeCredentials(creds);
}

// ---------------------------------------------------------------------------
// date helpers
// ---------------------------------------------------------------------------

String _day(DateTime anchor, int offsetDays) {
  final d = DateTime(anchor.year, anchor.month, anchor.day + offsetDays);
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

String _stamp(DateTime anchor, int offsetDays, {int hour = 23, int minute = 59}) {
  final d = DateTime.utc(
    anchor.year,
    anchor.month,
    anchor.day + offsetDays,
    hour,
    minute,
  );
  return d.toIso8601String();
}

// ---------------------------------------------------------------------------
// synergy
// ---------------------------------------------------------------------------

/// One Synergy assignment row, in the shape `_fetchClassData` produces.
Map<String, dynamic> _syn(
  DateTime anchor,
  int day,
  String name, {
  required double points,
  double? score,
  required String status,
  String type = 'Practice / Preparation',
  String? comment,
}) {
  return {
    'date': _day(anchor, day),
    'name': name,
    'type': type,
    'points_possible': points,
    'score': score,
    'status': status,
    'displayed_percent':
        (score != null && points > 0) ? (score / points * 100).round() : 0,
    'comment': comment ?? (status == 'missing' ? 'Missing' : null),
  };
}

/// A Synergy course record, post-`_postProcess` (missing_count already
/// counted, canvas_course_id / policy already attached).
Map<String, dynamic> _course(
  String name, {
  required String teacher,
  String? teacherEmail,
  String? letterGrade,
  double? percent,
  double? computedPercent,
  String? policy,
  String? canvasCourseId,
  required List<Map<String, dynamic>> assignments,
}) {
  return {
    'synergy_name': name,
    'teacher': teacher,
    'teacher_email': teacherEmail,
    'letter_grade': letterGrade,
    'percent': percent,
    'computed_percent': computedPercent,
    'missing_count': assignments.where((a) => a['status'] == 'missing').length,
    'policy': policy,
    'canvas_course_id': canvasCourseId,
    'assignments': assignments,
  };
}

Map<String, dynamic> buildSynergyPayload(DateTime anchor) {
  return {
    'source': 'Synergy ParentVUE (demo data)',
    'synergy_base_url': 'https://demo.example.invalid',
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'students': [
      {
        'student_id': _felix.id,
        'name': _felix.name,
        'courses': _felixSynergyCourses(anchor),
      },
      {
        'student_id': _nora.id,
        'name': _nora.name,
        'courses': _noraSynergyCourses(anchor),
      },
    ],
  };
}

List<Map<String, dynamic>> _felixSynergyCourses(DateTime anchor) => [
      // Failing, Canvas-linked, several missing items → dominates the catch-up
      // list because courseDistress is highest here.
      _course(
        'Accelerated Math 6',
        teacher: 'Alicia James',
        teacherEmail: 'ajames@demo.invalid',
        letterGrade: 'D',
        percent: 63.5,
        canvasCourseId: '20601',
        assignments: [
          _syn(anchor, -24, 'HW: IXL Convert fractions to decimals (DL:04/22)',
              points: 5, score: 0, status: 'missing'),
          _syn(anchor, -20, 'Cool Down Quiz: Percent increase and decrease',
              points: 6,
              score: 6,
              status: 'graded',
              type: 'All Tasks / Assessments'),
          _syn(anchor, -16, 'HW: IXL Write variable expressions',
              points: 5, score: 0, status: 'missing'),
          _syn(anchor, -11, 'Unit 4 Test: Ratios and Percent',
              points: 25,
              score: 14,
              status: 'graded',
              type: 'All Tasks / Assessments'),
          _syn(anchor, -6, 'HW #2: IXL Percents of money amounts',
              points: 5, score: 0, status: 'missing'),
          _syn(anchor, -4, 'Exit Ticket: Unit rates',
              points: 4, score: 0, status: 'zero_graded'),
          _syn(anchor, -2, 'Graded CW: Proportional relationships',
              points: 10,
              score: null,
              status: 'not_graded',
              type: 'All Tasks / Assessments'),
          _syn(anchor, 4, 'Unit 5 Project: Data displays',
              points: 30,
              score: null,
              status: 'not_graded',
              type: 'All Tasks / Assessments'),
        ],
      ),
      // Half-credit-for-missing-work policy: distress uses the alt percent,
      // and half_credit_missing items are deliberately NOT actionable.
      _course(
        'Historical Inquiry 6',
        teacher: 'Marcus Bell',
        teacherEmail: 'mbell@demo.invalid',
        letterGrade: 'C',
        percent: 72.0,
        policy: 'half_credit_for_missing_work',
        assignments: [
          _syn(anchor, -22, 'Primary Source Analysis: Silk Road',
              points: 10, score: 8, status: 'graded'),
          _syn(anchor, -15, 'Reading Notes: Chapter 7',
              points: 6, score: null, status: 'half_credit_missing'),
          _syn(anchor, -9, 'DBQ Draft: Trade networks',
              points: 20, score: 0, status: 'missing'),
          _syn(anchor, -3, 'Reading Notes: Chapter 8',
              points: 6, score: null, status: 'half_credit_missing'),
          _syn(anchor, 6, 'DBQ Final: Trade networks',
              points: 25,
              score: null,
              status: 'not_graded',
              type: 'All Tasks / Assessments'),
        ],
      ),
      // No official percent — forces the computed-percent path and its badge.
      // No teacher email either, so the "Talk to teacher" fallback shows.
      _course(
        'Science 6',
        teacher: 'Dana Okafor',
        letterGrade: 'B+',
        percent: null,
        computedPercent: 88.2,
        assignments: [
          _syn(anchor, -19, 'Lab Report: Density column',
              points: 20, score: 18, status: 'graded'),
          _syn(anchor, -12, 'Vocab Quiz: Matter',
              points: 10,
              score: 9,
              status: 'graded',
              type: 'All Tasks / Assessments'),
          _syn(anchor, -5, 'Homework: Phase change diagram',
              points: 5, score: 0, status: 'zero_graded'),
          _syn(anchor, 8, 'Lab Report: Chemical reactions',
              points: 20, score: null, status: 'not_graded'),
        ],
      ),
      // Below the failing band → red. Carries the score-threshold case (a
      // graded 62% item stays actionable) and an in-class-only item, which is
      // deprioritized by the 0.25 multiplier.
      _course(
        'Language Arts 6',
        teacher: 'Priya Raman',
        teacherEmail: 'praman@demo.invalid',
        letterGrade: 'F',
        percent: 57.0,
        canvasCourseId: '20604',
        assignments: [
          _syn(anchor, -21, 'Essay 2: Character analysis',
              points: 40,
              score: 25,
              status: 'graded',
              type: 'All Tasks / Assessments'),
          _syn(anchor, -14, 'IC: Peer review workshop',
              points: 5, score: 0, status: 'missing'),
          // Deliberately NOT "Week 6" / "Week 7": normalizeName drops tokens
          // shorter than three characters, so week numbers vanish and the two
          // logs would tie on similarity — Canvas would then merge into
          // whichever came first in the list.
          _syn(anchor, -10, 'Reading Log: Fiction unit',
              points: 10, score: 0, status: 'missing'),
          _syn(anchor, -7, 'Grammar Practice: Clauses',
              points: 8, score: 5, status: 'graded'),
          _syn(anchor, -1, 'Reading Log: Poetry unit',
              points: 10, score: 0, status: 'missing'),
          _syn(anchor, 9, 'Essay 3: Theme and evidence',
              points: 40,
              score: null,
              status: 'not_graded',
              type: 'All Tasks / Assessments'),
        ],
      ),
      // Healthy course — should sort to the bottom and show no catch-up rows.
      _course(
        'PE 6',
        teacher: 'Sam Whitfield',
        teacherEmail: 'swhitfield@demo.invalid',
        letterGrade: 'A',
        percent: 100.0,
        assignments: [
          _syn(anchor, -18, 'Participation: Week 5',
              points: 10, score: 10, status: 'graded'),
          _syn(anchor, -8, 'Fitness Log: Week 6',
              points: 10, score: 10, status: 'graded'),
          _syn(anchor, 2, 'Participation: Week 8',
              points: 10, score: null, status: 'not_graded'),
        ],
      ),
    ];

List<Map<String, dynamic>> _noraSynergyCourses(DateTime anchor) => [
      _course(
        'Algebra 1',
        teacher: 'Rosa Delgado',
        teacherEmail: 'rdelgado@demo.invalid',
        letterGrade: 'A-',
        percent: 91.0,
        canvasCourseId: '30701',
        assignments: [
          _syn(anchor, -17, 'Quiz: Systems of equations',
              points: 20,
              score: 19,
              status: 'graded',
              type: 'All Tasks / Assessments'),
          _syn(anchor, -3, 'HW 6.2: Substitution',
              points: 5, score: 0, status: 'missing'),
          _syn(anchor, 5, 'Unit 6 Test',
              points: 50,
              score: null,
              status: 'not_graded',
              type: 'All Tasks / Assessments'),
        ],
      ),
      _course(
        'Biology',
        teacher: 'Henry Osei',
        teacherEmail: 'hosei@demo.invalid',
        letterGrade: 'C+',
        percent: 78.5,
        assignments: [
          _syn(anchor, -13, 'Cell Organelle Diagram',
              points: 15, score: 11, status: 'graded'),
          _syn(anchor, -6, 'Reading Guide: Mitosis',
              points: 10, score: 0, status: 'missing'),
          _syn(anchor, 3, 'Lab: Osmosis in potato cores',
              points: 25, score: null, status: 'not_graded'),
        ],
      ),
      _course(
        'Spanish 2',
        teacher: 'Elena Castillo',
        teacherEmail: 'ecastillo@demo.invalid',
        letterGrade: 'B',
        percent: 85.0,
        canvasCourseId: '30703',
        assignments: [
          _syn(anchor, -11, 'Vocabulario Unidad 4',
              points: 10, score: 9, status: 'graded'),
          _syn(anchor, -2, 'Composición: Mi rutina diaria',
              points: 20, score: null, status: 'not_graded'),
        ],
      ),
    ];

// ---------------------------------------------------------------------------
// canvas
// ---------------------------------------------------------------------------

/// One Canvas assignment in the trimmed shape `processStudent` writes.
Map<String, dynamic> _canvasAssignment(
  DateTime anchor,
  int id,
  int day,
  String name, {
  required double points,
  required String workflowState, // graded | submitted | unsubmitted
  double? score,
}) {
  return {
    'id': id,
    'name': name,
    'due_at': _stamp(anchor, day),
    'due_date': _day(anchor, day),
    'points_possible': points,
    'html_url': 'https://demo.instructure.invalid/courses/0/assignments/$id',
    'submission_types': const ['online_upload'],
    'workflow_state': 'published',
    'omit_from_final_grade': false,
    'muted': false,
    'submission': {
      'workflow_state': workflowState,
      'submitted_at': workflowState == 'unsubmitted'
          ? null
          : _stamp(anchor, day, hour: 18, minute: 4),
      'missing': workflowState == 'unsubmitted',
      'late': false,
      'excused': false,
      'score': score,
      'grade': score?.toString(),
      'entered_score': score,
      'graded_at':
          workflowState == 'graded' ? _stamp(anchor, day + 2, hour: 9) : null,
    },
  };
}

Map<String, dynamic> buildCanvasPayload(DateTime anchor) {
  return {
    'source': 'Canvas (demo data)',
    'canvas_base_url': 'https://demo.instructure.invalid',
    'generated_at': DateTime.now().toUtc().toIso8601String(),
    'students': [
      {
        'student_id': _felix.id,
        'name': _felix.name,
        'canvas_user_id': 8801,
        'current_grading_period': {
          'title': 'Quarter 4',
          'start_date': _day(anchor, -45),
          'end_date': _day(anchor, 20),
        },
        'courses': _felixCanvasCourses(anchor),
        'generated_at': DateTime.now().toUtc().toIso8601String(),
      },
      {
        'student_id': _nora.id,
        'name': _nora.name,
        'canvas_user_id': 8802,
        'current_grading_period': {
          'title': 'Quarter 4',
          'start_date': _day(anchor, -45),
          'end_date': _day(anchor, 20),
        },
        'courses': _noraCanvasCourses(anchor),
        'generated_at': DateTime.now().toUtc().toIso8601String(),
      },
    ],
  };
}

// Names here deliberately echo the Synergy titles so nameSimilarity clears the
// 0.5 bar and the rows merge into source='both'. The odd one out in each list
// stays Canvas-only, which is the other branch worth looking at.
List<Map<String, dynamic>> _felixCanvasCourses(DateTime anchor) => [
      {
        'id': 20601,
        'name': 'Accelerated Math 6-JAMES-YR-2026',
        'course_code': 'MATH6ACC',
        'current_score': 63.5,
        'current_grade': 'D',
        'assignments': [
          _canvasAssignment(anchor, 991001, -24,
              'HW: IXL Convert fractions to decimals',
              points: 5, workflowState: 'unsubmitted'),
          _canvasAssignment(anchor, 991002, -11,
              'Unit 4 Test: Ratios and Percent',
              points: 25, workflowState: 'graded', score: 14),
          _canvasAssignment(anchor, 991003, -2,
              'Graded CW: Proportional relationships',
              points: 10, workflowState: 'submitted'),
          _canvasAssignment(
              anchor, 991004, 7, 'Khan Academy: Unit 5 warmup set',
              points: 8, workflowState: 'unsubmitted'),
        ],
      },
      {
        'id': 20604,
        'name': 'Language Arts 6-RAMAN-YR-2026',
        'course_code': 'LA6',
        'current_score': 57.0,
        'current_grade': 'F',
        'assignments': [
          _canvasAssignment(anchor, 992001, -21, 'Essay 2: Character analysis',
              points: 40, workflowState: 'graded', score: 25),
          // Canvas-only and graded at 60% — below the 70% threshold seeded for
          // this course, which is the only way a graded row stays actionable.
          // (A Synergy-sourced graded row flattens to status 'ok' and the
          // threshold never sees it.)
          _canvasAssignment(anchor, 992004, -13, 'Vocabulary Quiz: Greek roots',
              points: 20, workflowState: 'graded', score: 12),
          _canvasAssignment(anchor, 992002, -1, 'Reading Log: Poetry unit',
              points: 10, workflowState: 'unsubmitted'),
          _canvasAssignment(anchor, 992003, 9, 'Essay 3: Theme and evidence',
              points: 40, workflowState: 'unsubmitted'),
        ],
      },
    ];

List<Map<String, dynamic>> _noraCanvasCourses(DateTime anchor) => [
      {
        'id': 30701,
        'name': 'Algebra 1-DELGADO-YR-2026',
        'course_code': 'ALG1',
        'current_score': 91.0,
        'current_grade': 'A-',
        'assignments': [
          _canvasAssignment(anchor, 993001, -3, 'HW 6.2: Substitution',
              points: 5, workflowState: 'unsubmitted'),
          _canvasAssignment(anchor, 993002, 5, 'Unit 6 Test',
              points: 50, workflowState: 'unsubmitted'),
        ],
      },
      {
        'id': 30703,
        'name': 'Spanish 2-CASTILLO-YR-2026',
        'course_code': 'SPAN2',
        'current_score': 85.0,
        'current_grade': 'B',
        'assignments': [
          _canvasAssignment(anchor, 994001, -2, 'Composición: Mi rutina diaria',
              points: 20, workflowState: 'submitted'),
        ],
      },
    ];

// ---------------------------------------------------------------------------
// per-student local state
// ---------------------------------------------------------------------------

/// Keys must be built the same way the UI builds them, or seeded statuses and
/// comments attach to nothing. Merged (Canvas+Synergy) rows key off the Canvas
/// id; Synergy-only rows key off normalized course + assignment names.
String _synKey(String course, String name) =>
    assignmentKey(canvasId: null, courseName: course, assignmentName: name);

String _canvasKey(int id) => assignmentKey(
      canvasId: '$id',
      courseName: null,
      assignmentName: null,
    );

class _DemoStudent {
  const _DemoStudent({
    required this.id,
    required this.name,
    required this.thresholds,
    required this.comments,
    required this.statusEntries,
  });

  final String id;
  final String name;
  final Map<String, int> thresholds;
  final Map<String, dynamic> Function(DateTime) comments;
  final Map<String, dynamic> Function(DateTime) statusEntries;
}

Map<String, dynamic> _thread(
  DateTime anchor,
  String id,
  String text,
  String author,
  int day, {
  List<Map<String, dynamic>> replies = const [],
}) =>
    {
      'id': id,
      'text': text,
      'author': author,
      'created_at': _stamp(anchor, day, hour: 19, minute: 12),
      'replies': replies,
    };

final _felix = _DemoStudent(
  id: '294651',
  name: 'Felix',
  // Language Arts is graded harshly, so anything at or below 70% still counts
  // as actionable — this is what makes the 62% essay show up in catch-up.
  thresholds: const {'Language Arts 6': 70},
  comments: (anchor) => {
    _synKey('Accelerated Math 6', 'HW #2: IXL Percents of money amounts'): [
      _thread(anchor, 'demo-c1', 'Says the IXL link was broken all week.', 'me',
          -5,
          replies: [
            {
              'id': 'demo-r1',
              'text': 'Emailed Ms. James, waiting to hear back.',
              'author': 'me',
              'created_at': _stamp(anchor, -4, hour: 8, minute: 30),
            },
          ]),
    ],
    _canvasKey(992002): [
      _thread(anchor, 'demo-c2', 'Reading log is in the blue folder, not typed.',
          'me', -1),
    ],
    _synKey('Historical Inquiry 6', 'DBQ Draft: Trade networks'): [
      _thread(
          anchor, 'demo-c3', 'Needs the outline before he can start.', 'me', -8),
    ],
  },
  statusEntries: (anchor) => {
    // Planned for a future date — should show the "planned" badge and take the
    // 1.0 multiplier (no reduction) until it is claimed complete.
    _synKey('Accelerated Math 6', 'HW: IXL Write variable expressions'): {
      'status': 'planned',
      'updated_at': _stamp(anchor, -2, hour: 20),
      'assignment_name': 'HW: IXL Write variable expressions',
      'course_name': 'Accelerated Math 6',
      'planned_date': _day(anchor, 2),
    },
    // Done but not turned in → 0.40 multiplier.
    _synKey('Language Arts 6', 'Reading Log: Fiction unit'): {
      'status': 'complete_pending_submission',
      'updated_at': _stamp(anchor, -1, hour: 17),
      'assignment_name': 'Reading Log: Fiction unit',
      'course_name': 'Language Arts 6',
    },
    // Turned in, waiting on the teacher → 0.20 multiplier, sinks in the list.
    _synKey('Historical Inquiry 6', 'DBQ Draft: Trade networks'): {
      'status': 'submitted_pending_feedback',
      'updated_at': _stamp(anchor, -1, hour: 9),
      'assignment_name': 'DBQ Draft: Trade networks',
      'course_name': 'Historical Inquiry 6',
      'submitted_date': _day(anchor, -1),
    },
    // Attached to an item that IS graded — getLocalStatus should suppress it,
    // so this one must NOT appear in the UI.
    _canvasKey(992001): {
      'status': 'submitted_pending_feedback',
      'updated_at': _stamp(anchor, -20, hour: 9),
      'assignment_name': 'Essay 2: Character analysis',
      'course_name': 'Language Arts 6',
      'submitted_date': _day(anchor, -20),
    },
  },
);

final _nora = _DemoStudent(
  id: '301884',
  name: 'Nora',
  thresholds: const {},
  comments: (anchor) => {
    _synKey('Biology', 'Reading Guide: Mitosis'): [
      _thread(anchor, 'demo-c4', 'Lost the packet, asked for a reprint.', 'me',
          -4),
    ],
  },
  statusEntries: (anchor) => {
    _canvasKey(993001): {
      'status': 'complete_pending_submission',
      'updated_at': _stamp(anchor, -1, hour: 21),
      'assignment_name': 'HW 6.2: Substitution',
      'course_name': 'Algebra 1',
    },
  },
);

final _students = <_DemoStudent>[_felix, _nora];
